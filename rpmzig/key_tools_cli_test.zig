// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const testing = std.testing;

const TestRoot = struct {
    tmp: std.testing.TmpDir,
    path: []u8,

    fn init(sub_path: []const u8) !TestRoot {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();
        try tmp.dir.createDirPath(testing.io, sub_path);

        var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const base_len = try tmp.dir.realPath(testing.io, &path_buffer);
        return .{
            .tmp = tmp,
            .path = try std.fs.path.join(
                testing.allocator,
                &.{ path_buffer[0..base_len], sub_path },
            ),
        };
    }

    fn deinit(self: *TestRoot) void {
        testing.allocator.free(self.path);
        self.tmp.cleanup();
    }
};

fn binaryPath(name: []const u8) ![]u8 {
    return testing.environ.getAlloc(testing.allocator, name);
}

fn run(binary: []const u8, args: []const []const u8) !std.process.RunResult {
    const argv = try testing.allocator.alloc([]const u8, args.len + 1);
    defer testing.allocator.free(argv);
    argv[0] = binary;
    @memcpy(argv[1..], args);
    return std.process.run(testing.allocator, testing.io, .{
        .argv = argv,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
}

fn expectExit(result: std.process.RunResult, expected: u8) !void {
    try testing.expectEqual(expected, switch (result.term) {
        .exited => |code| code,
        else => 255,
    });
}

fn writeUsage(allocator: std.mem.Allocator, binary: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "usage:\n" ++
            "  {s} install <root> <file.rpm> [install_tid [install_time [install_color]]]\n" ++
            "  {s} replace <root> <old_hnum> <file.rpm> [install_tid [install_time [install_color]]]\n" ++
            "  {s} erase-hnum <root> <hnum>\n" ++
            "  {s} find-hnum <root> <nevra>\n",
        .{ binary, binary, binary, binary },
    );
}

test "missing arguments and invalid options preserve CLI contracts" {
    const pubkeys = try binaryPath("TDNF_RPMDB_PUBKEYS_TEST_BINARY");
    defer testing.allocator.free(pubkeys);
    const import_pubkeys = try binaryPath(
        "TDNF_RPMDB_IMPORT_PUBKEYS_TEST_BINARY",
    );
    defer testing.allocator.free(import_pubkeys);
    const write = try binaryPath("TDNF_RPMDB_WRITE_TEST_BINARY");
    defer testing.allocator.free(write);

    const pubkeys_result = try run(pubkeys, &.{"--invalid"});
    defer testing.allocator.free(pubkeys_result.stdout);
    defer testing.allocator.free(pubkeys_result.stderr);
    try expectExit(pubkeys_result, 2);
    try testing.expectEqualStrings("", pubkeys_result.stdout);
    try testing.expectEqualStrings(
        "usage: tdnf-rpmdb-pubkeys [--dump] [root]\n",
        pubkeys_result.stderr,
    );

    const import_result = try run(import_pubkeys, &.{});
    defer testing.allocator.free(import_result.stdout);
    defer testing.allocator.free(import_result.stderr);
    try expectExit(import_result, 2);
    try testing.expectEqualStrings("", import_result.stdout);
    const import_usage = try std.fmt.allocPrint(
        testing.allocator,
        "usage: {s} <root> <key-file>\n",
        .{import_pubkeys},
    );
    defer testing.allocator.free(import_usage);
    try testing.expectEqualStrings(import_usage, import_result.stderr);

    const write_result = try run(write, &.{});
    defer testing.allocator.free(write_result.stdout);
    defer testing.allocator.free(write_result.stderr);
    try expectExit(write_result, 2);
    try testing.expectEqualStrings("", write_result.stdout);
    const expected_write_usage = try writeUsage(testing.allocator, write);
    defer testing.allocator.free(expected_write_usage);
    try testing.expectEqualStrings(
        expected_write_usage,
        write_result.stderr,
    );
}

test "malformed key input fails before creating an rpmdb" {
    const import_pubkeys = try binaryPath(
        "TDNF_RPMDB_IMPORT_PUBKEYS_TEST_BINARY",
    );
    defer testing.allocator.free(import_pubkeys);
    var root = try TestRoot.init("root");
    defer root.deinit();
    try root.tmp.dir.writeFile(testing.io, .{
        .sub_path = "invalid.asc",
        .data = "not a public key\n",
    });

    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const invalid_len = try root.tmp.dir.realPathFile(
        testing.io,
        "invalid.asc",
        &path_buffer,
    );
    const invalid_path = path_buffer[0..invalid_len];
    const result = try run(import_pubkeys, &.{ root.path, invalid_path });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try expectExit(result, 1);
    try testing.expectEqualStrings("", result.stdout);
    const expected = try std.fmt.allocPrint(
        testing.allocator,
        "{s}: pubkey import failed: MalformedPacket\n",
        .{import_pubkeys},
    );
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, result.stderr);
    try testing.expectError(
        error.FileNotFound,
        root.tmp.dir.access(
            testing.io,
            "root/var/lib/rpm/rpmdb.sqlite",
            .{},
        ),
    );
}

test "key import and listing mutate only the selected root" {
    const pubkeys = try binaryPath("TDNF_RPMDB_PUBKEYS_TEST_BINARY");
    defer testing.allocator.free(pubkeys);
    const import_pubkeys = try binaryPath(
        "TDNF_RPMDB_IMPORT_PUBKEYS_TEST_BINARY",
    );
    defer testing.allocator.free(import_pubkeys);
    const fixture = try binaryPath("TDNF_RPMDB_KEY_FIXTURE");
    defer testing.allocator.free(fixture);
    var root = try TestRoot.init("root");
    defer root.deinit();

    const import_result = try run(
        import_pubkeys,
        &.{ root.path, fixture },
    );
    defer testing.allocator.free(import_result.stdout);
    defer testing.allocator.free(import_result.stderr);
    try expectExit(import_result, 0);
    try testing.expectEqualStrings("1\n", import_result.stdout);
    try testing.expectEqualStrings("", import_result.stderr);

    const list_result = try run(pubkeys, &.{root.path});
    defer testing.allocator.free(list_result.stdout);
    defer testing.allocator.free(list_result.stderr);
    try expectExit(list_result, 0);
    try testing.expectEqualStrings("3135ce90  647\n", list_result.stdout);
    try testing.expectEqualStrings("", list_result.stderr);
}

test "dump stops at the fixture's embedded NUL like legacy fputs" {
    const pubkeys = try binaryPath("TDNF_RPMDB_PUBKEYS_TEST_BINARY");
    defer testing.allocator.free(pubkeys);
    const import_pubkeys = try binaryPath(
        "TDNF_RPMDB_IMPORT_PUBKEYS_TEST_BINARY",
    );
    defer testing.allocator.free(import_pubkeys);
    const fixture = try binaryPath("TDNF_RPMDB_KEY_FIXTURE");
    defer testing.allocator.free(fixture);
    var root = try TestRoot.init("root");
    defer root.deinit();

    const import_result = try run(
        import_pubkeys,
        &.{ root.path, fixture },
    );
    defer testing.allocator.free(import_result.stdout);
    defer testing.allocator.free(import_result.stderr);
    try expectExit(import_result, 0);

    const dump_result = try run(pubkeys, &.{ "--dump", root.path });
    defer testing.allocator.free(dump_result.stdout);
    defer testing.allocator.free(dump_result.stderr);
    try expectExit(dump_result, 0);
    try testing.expectEqualSlices(
        u8,
        "3135ce90  647\n" ++
            "\x99\x01\x0d\x04\x5e\x6f\xda\x74\x01\x08\n",
        dump_result.stdout,
    );
    try testing.expectEqualStrings("", dump_result.stderr);
}

test "invalid write input and backend failures do not mutate rpmdb data" {
    const write = try binaryPath("TDNF_RPMDB_WRITE_TEST_BINARY");
    defer testing.allocator.free(write);
    var root = try TestRoot.init("root");
    defer root.deinit();

    const invalid_result = try run(
        write,
        &.{ "install", root.path, "missing.rpm", "invalid" },
    );
    defer testing.allocator.free(invalid_result.stdout);
    defer testing.allocator.free(invalid_result.stderr);
    try expectExit(invalid_result, 2);
    try testing.expectEqualStrings("", invalid_result.stdout);
    try testing.expectEqualStrings(
        "invalid install_tid: invalid\n",
        invalid_result.stderr,
    );
    try testing.expectError(
        error.FileNotFound,
        root.tmp.dir.access(
            testing.io,
            "root/var/lib/rpm/rpmdb.sqlite",
            .{},
        ),
    );

    try root.tmp.dir.createDirPath(testing.io, "root/var/lib/rpm");
    try root.tmp.dir.writeFile(testing.io, .{
        .sub_path = "root/var/lib/rpm/Packages",
        .data = "legacy backend marker",
    });
    const backend_result = try run(
        write,
        &.{ "install", root.path, "missing.rpm", "1", "1", "3" },
    );
    defer testing.allocator.free(backend_result.stdout);
    defer testing.allocator.free(backend_result.stderr);
    try expectExit(backend_result, 1);
    try testing.expectEqualStrings("", backend_result.stdout);
    try testing.expectEqualStrings(
        "tdnf-rpmdb-write install: Writer.openRoot: UnsupportedBackend\n",
        backend_result.stderr,
    );
    const marker = try root.tmp.dir.readFileAlloc(
        testing.io,
        "root/var/lib/rpm/Packages",
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(marker);
    try testing.expectEqualStrings("legacy backend marker", marker);
}
