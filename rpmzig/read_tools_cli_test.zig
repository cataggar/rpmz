const std = @import("std");
const header = @import("rpm_header");
const testing = std.testing;

const TestEntry = struct {
    tag: u32,
    typ: header.TypeId,
    count: u32,
    data: []const u8,
};

fn binaryPath(environment_name: []const u8) ![]u8 {
    return testing.environ.getAlloc(testing.allocator, environment_name);
}

fn run(binary: []const u8, args: []const []const u8) !std.process.RunResult {
    const argv = try testing.allocator.alloc([]const u8, args.len + 1);
    defer testing.allocator.free(argv);
    argv[0] = binary;
    @memcpy(argv[1..], args);
    return std.process.run(testing.allocator, testing.io, .{
        .argv = argv,
        .stdout_limit = .limited(16 * 1024),
        .stderr_limit = .limited(16 * 1024),
    });
}

fn expectExit(result: std.process.RunResult, expected: u8) !void {
    try testing.expectEqual(expected, switch (result.term) {
        .exited => |code| code,
        else => 255,
    });
}

fn tempPath(
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    name: []const u8,
) ![]u8 {
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(testing.io, &path_buffer);
    return std.fs.path.join(
        allocator,
        &.{ path_buffer[0..root_len], name },
    );
}

fn appendU32(
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    value: u32,
) !void {
    try list.append(allocator, @truncate(value >> 24));
    try list.append(allocator, @truncate(value >> 16));
    try list.append(allocator, @truncate(value >> 8));
    try list.append(allocator, @truncate(value));
}

fn typeAlignment(typ: header.TypeId) usize {
    return switch (typ) {
        .int16 => 2,
        .int32 => 4,
        .int64 => 8,
        else => 1,
    };
}

fn buildRegionHeader(
    allocator: std.mem.Allocator,
    region: header.RegionTag,
    entries: []const TestEntry,
) ![]u8 {
    var data = std.ArrayList(u8).empty;
    defer data.deinit(allocator);
    var offsets = std.ArrayList(u32).empty;
    defer offsets.deinit(allocator);

    for (entries) |entry| {
        while (data.items.len % typeAlignment(entry.typ) != 0)
            try data.append(allocator, 0);
        try offsets.append(allocator, @intCast(data.items.len));
        try data.appendSlice(allocator, entry.data);
    }

    const trailer_offset: u32 = @intCast(data.items.len);
    const region_tag = @intFromEnum(region);
    try appendU32(&data, allocator, region_tag);
    try appendU32(&data, allocator, @intFromEnum(header.TypeId.bin));
    const index_count: u32 = @intCast(entries.len + 1);
    const negative_span: i32 = -@as(i32, @intCast(index_count * 16));
    try appendU32(&data, allocator, @bitCast(negative_span));
    try appendU32(&data, allocator, 16);

    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);
    try result.appendSlice(allocator, &.{ 0x8e, 0xad, 0xe8, 0x01, 0, 0, 0, 0 });
    try appendU32(&result, allocator, index_count);
    try appendU32(&result, allocator, @intCast(data.items.len));
    try appendU32(&result, allocator, region_tag);
    try appendU32(&result, allocator, @intFromEnum(header.TypeId.bin));
    try appendU32(&result, allocator, trailer_offset);
    try appendU32(&result, allocator, 16);
    for (entries, offsets.items) |entry, offset| {
        try appendU32(&result, allocator, entry.tag);
        try appendU32(&result, allocator, @intFromEnum(entry.typ));
        try appendU32(&result, allocator, offset);
        try appendU32(&result, allocator, entry.count);
    }
    try result.appendSlice(allocator, data.items);
    return result.toOwnedSlice(allocator);
}

fn buildMalformedPayloadRpm(allocator: std.mem.Allocator) ![]u8 {
    const signature = try buildRegionHeader(allocator, .signatures, &.{
        .{
            .tag = @intFromEnum(header.SigTagId.size),
            .typ = .int32,
            .count = 1,
            .data = "\x00\x00\x00\x01",
        },
    });
    defer allocator.free(signature);
    const main = try buildRegionHeader(allocator, .immutable, &.{
        .{ .tag = @intFromEnum(header.TagId.name), .typ = .string, .count = 1, .data = "pkg\x00" },
        .{ .tag = @intFromEnum(header.TagId.version), .typ = .string, .count = 1, .data = "1\x00" },
        .{ .tag = @intFromEnum(header.TagId.release), .typ = .string, .count = 1, .data = "1\x00" },
        .{ .tag = @intFromEnum(header.TagId.arch), .typ = .string, .count = 1, .data = "noarch\x00" },
        .{ .tag = @intFromEnum(header.TagId.payload_compressor), .typ = .string, .count = 1, .data = "none\x00" },
    });
    defer allocator.free(main);

    const malformed_name = "safe\x00VULNERABLE-SUFFIX\x00";
    const payload_len = std.mem.alignForward(usize, 110 + malformed_name.len, 4);
    const signature_padding = (8 - (signature.len % 8)) % 8;
    const payload_offset = 96 + signature.len + signature_padding + main.len;
    const rpm = try allocator.alloc(u8, payload_offset + payload_len);
    @memset(rpm, 0);
    const lead_magic = [_]u8{ 0xed, 0xab, 0xee, 0xdb };
    @memcpy(rpm[0..4], &lead_magic);
    @memcpy(rpm[96 .. 96 + signature.len], signature);
    const main_offset = 96 + signature.len + signature_padding;
    @memcpy(rpm[main_offset .. main_offset + main.len], main);

    const payload = rpm[payload_offset..];
    @memcpy(payload[0..6], "070701");
    @memcpy(payload[6..110], "00000000" ** 13);
    const name_size = try std.fmt.bufPrint(
        payload[94..102],
        "{x:0>8}",
        .{malformed_name.len},
    );
    try testing.expectEqual(@as(usize, 8), name_size.len);
    @memcpy(payload[110 .. 110 + malformed_name.len], malformed_name);
    return rpm;
}

test "rpmdb read tools preserve empty-root and extra-argument behavior" {
    const count = try binaryPath("TDNF_RPMDB_COUNT_TEST_BINARY");
    defer testing.allocator.free(count);
    const list = try binaryPath("TDNF_RPMDB_LIST_TEST_BINARY");
    defer testing.allocator.free(list);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const missing = try tempPath(testing.allocator, tmp, "missing");
    defer testing.allocator.free(missing);

    const count_result = try run(count, &.{ missing, "ignored" });
    defer testing.allocator.free(count_result.stdout);
    defer testing.allocator.free(count_result.stderr);
    try expectExit(count_result, 0);
    try testing.expectEqualStrings("0\n", count_result.stdout);
    try testing.expectEqualStrings("", count_result.stderr);

    const list_result = try run(list, &.{ missing, "ignored" });
    defer testing.allocator.free(list_result.stdout);
    defer testing.allocator.free(list_result.stderr);
    try expectExit(list_result, 0);
    try testing.expectEqualStrings("", list_result.stdout);
    try testing.expectEqualStrings("", list_result.stderr);
}

test "rpm file tools preserve accepted arguments, usage output, and status" {
    inline for (
        .{ "TDNF_RPM_INFO_TEST_BINARY", "TDNF_RPM_FILES_TEST_BINARY" },
    ) |environment_name| {
        const binary = try binaryPath(environment_name);
        defer testing.allocator.free(binary);
        const expected = try std.fmt.allocPrint(
            testing.allocator,
            "usage: {s} <file.rpm>\n",
            .{binary},
        );
        defer testing.allocator.free(expected);

        inline for (.{ &.{}, &.{ "one.rpm", "two.rpm" } }) |args| {
            const result = try run(binary, args);
            defer testing.allocator.free(result.stdout);
            defer testing.allocator.free(result.stderr);
            try expectExit(result, 2);
            try testing.expectEqualStrings("", result.stdout);
            try testing.expectEqualStrings(expected, result.stderr);
        }
    }
}

test "rpm file tools preserve open diagnostics" {
    const info = try binaryPath("TDNF_RPM_INFO_TEST_BINARY");
    defer testing.allocator.free(info);
    const files = try binaryPath("TDNF_RPM_FILES_TEST_BINARY");
    defer testing.allocator.free(files);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const missing = try tempPath(testing.allocator, tmp, "missing");
    defer testing.allocator.free(missing);

    const info_result = try run(info, &.{missing});
    defer testing.allocator.free(info_result.stdout);
    defer testing.allocator.free(info_result.stderr);
    const info_error = try std.fmt.allocPrint(
        testing.allocator,
        "tdnf-rpm-info: rpm_file_open({s}): StatFailed\n",
        .{missing},
    );
    defer testing.allocator.free(info_error);
    try expectExit(info_result, 1);
    try testing.expectEqualStrings("", info_result.stdout);
    try testing.expectEqualStrings(info_error, info_result.stderr);

    const files_result = try run(files, &.{missing});
    defer testing.allocator.free(files_result.stdout);
    defer testing.allocator.free(files_result.stderr);
    const files_error = try std.fmt.allocPrint(
        testing.allocator,
        "tdnf-rpm-files: open: rpm_file_open({s}): StatFailed\n",
        .{missing},
    );
    defer testing.allocator.free(files_error);
    try expectExit(files_result, 1);
    try testing.expectEqualStrings("", files_result.stdout);
    try testing.expectEqualStrings(files_error, files_result.stderr);
}

test "rpm files rejects embedded NUL names without printing suffix bytes" {
    const files = try binaryPath("TDNF_RPM_FILES_TEST_BINARY");
    defer testing.allocator.free(files);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const rpm = try buildMalformedPayloadRpm(testing.allocator);
    defer testing.allocator.free(rpm);
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "malformed.rpm",
        .data = rpm,
    });
    const rpm_path = try tempPath(testing.allocator, tmp, "malformed.rpm");
    defer testing.allocator.free(rpm_path);

    const result = try run(files, &.{rpm_path});
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try expectExit(result, 1);
    try testing.expectEqualStrings("", result.stdout);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "VULNERABLE-SUFFIX") == null);
    try testing.expectEqualStrings(
        "tdnf-rpm-files: cpio walker: BadName\n",
        result.stderr,
    );
}
