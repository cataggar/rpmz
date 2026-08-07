const std = @import("std");
const testing = std.testing;

fn binaryPath() ![]u8 {
    return testing.environ.getAlloc(
        testing.allocator,
        "TDNF_RPM_VERIFY_TEST_BINARY",
    );
}

fn run(binary: []const u8, args: []const []const u8) !std.process.RunResult {
    const argv = try testing.allocator.alloc([]const u8, args.len + 1);
    defer testing.allocator.free(argv);
    argv[0] = binary;
    @memcpy(argv[1..], args);
    return std.process.run(testing.allocator, testing.io, .{
        .argv = argv,
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
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

test "verifier preserves usage and malformed argument diagnostics" {
    const binary = try binaryPath();
    defer testing.allocator.free(binary);

    const no_args = try run(binary, &.{});
    defer testing.allocator.free(no_args.stdout);
    defer testing.allocator.free(no_args.stderr);
    try expectExit(no_args, 4);
    try testing.expectEqualStrings("", no_args.stdout);
    const usage = try std.fmt.allocPrint(
        testing.allocator,
        "usage: {s} <file.rpm> [--key <key.asc> ...] [--rpmdb [root]]\n",
        .{binary},
    );
    defer testing.allocator.free(usage);
    try testing.expectEqualStrings(usage, no_args.stderr);

    inline for (
        .{
            &.{ "package.rpm", "--key" },
            &.{ "package.rpm", "--unknown" },
        },
        .{
            "unknown arg: --key\n",
            "unknown arg: --unknown\n",
        },
    ) |args, expected| {
        const result = try run(binary, args);
        defer testing.allocator.free(result.stdout);
        defer testing.allocator.free(result.stderr);
        try expectExit(result, 4);
        try testing.expectEqualStrings("", result.stdout);
        try testing.expectEqualStrings(expected, result.stderr);
    }
}

test "verifier preserves missing key diagnostic" {
    const binary = try binaryPath();
    defer testing.allocator.free(binary);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const missing = try tempPath(testing.allocator, tmp, "missing.asc");
    defer testing.allocator.free(missing);

    const result = try run(binary, &.{ "package.rpm", "--key", missing });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try expectExit(result, 4);
    try testing.expectEqualStrings("", result.stdout);
    const expected = try std.fmt.allocPrint(
        testing.allocator,
        "tdnf-rpm-verify: open key {s}: No such file or directory\n",
        .{missing},
    );
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, result.stderr);
}

test "verifier silently rejects a directory key path" {
    const binary = try binaryPath();
    defer testing.allocator.free(binary);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const directory = try tempPath(testing.allocator, tmp, ".");
    defer testing.allocator.free(directory);

    const result = try run(binary, &.{ "package.rpm", "--key", directory });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try expectExit(result, 4);
    try testing.expectEqualStrings("", result.stdout);
    try testing.expectEqualStrings("", result.stderr);
}
