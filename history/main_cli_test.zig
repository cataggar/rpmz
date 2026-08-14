// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const testing = std.testing;

const IsolatedDb = struct {
    tmp: std.testing.TmpDir,
    root: []u8,
    path: []u8,

    fn init() !IsolatedDb {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();

        var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const root_len = try tmp.dir.realPath(testing.io, &path_buffer);
        const root = try testing.allocator.dupe(
            u8,
            path_buffer[0..root_len],
        );
        errdefer testing.allocator.free(root);
        return .{
            .tmp = tmp,
            .root = root,
            .path = try std.fs.path.join(
                testing.allocator,
                &.{ root, "history.db" },
            ),
        };
    }

    fn deinit(self: *IsolatedDb) void {
        testing.allocator.free(self.root);
        testing.allocator.free(self.path);
        self.tmp.cleanup();
    }

    fn expectCreated(self: *IsolatedDb) !void {
        try self.tmp.dir.access(testing.io, "history.db", .{});
    }
};

fn historyUtilPath(allocator: std.mem.Allocator) ![]u8 {
    return testing.environ.getAlloc(allocator, "TDNF_HISTORY_UTIL_TEST_BINARY");
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

fn expectedUsage(allocator: std.mem.Allocator, binary: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "tdnf history db utility\n\n" ++
            "Usage:\n\n" ++
            "{s} [-f dbfile] [-r rootdir] init|update\n" ++
            "{s} [-f dbfile] mark install|remove [pkg[...]]\n" ++
            "\n" ++
            "Commands:\n\n" ++
            "init   - Initialize the history db.\n" ++
            "mark   - Mark a package as user installed ('install') or auto installed ('remove').\n" ++
            "update - Update the history db using the current rpm db.\n" ++
            "\n",
        .{ binary, binary },
    );
}

test "missing command preserves usage, diagnostic, and exit code" {
    const binary = try historyUtilPath(testing.allocator);
    defer testing.allocator.free(binary);
    const usage = try expectedUsage(testing.allocator, binary);
    defer testing.allocator.free(usage);
    var db = try IsolatedDb.init();
    defer db.deinit();

    const result = try run(binary, &.{ "-f", db.path, "-r", db.root });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try expectExit(result, 1);
    try testing.expectEqualStrings(usage, result.stdout);
    try testing.expectEqualStrings("command expected\n", result.stderr);
    try db.expectCreated();
}

test "unknown mark subcommand preserves output and exit code" {
    const binary = try historyUtilPath(testing.allocator);
    defer testing.allocator.free(binary);
    const usage = try expectedUsage(testing.allocator, binary);
    defer testing.allocator.free(usage);
    var db = try IsolatedDb.init();
    defer db.deinit();

    const result = try run(
        binary,
        &.{ "-f", db.path, "-r", db.root, "mark", "invalid" },
    );
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try expectExit(result, 1);
    try testing.expectEqualStrings(usage, result.stdout);
    try testing.expectEqualStrings(
        "unknown sub command 'invalid'\n",
        result.stderr,
    );
    try db.expectCreated();
}

test "file option initializes the requested history database" {
    const binary = try historyUtilPath(testing.allocator);
    defer testing.allocator.free(binary);
    var db = try IsolatedDb.init();
    defer db.deinit();

    const result = try run(
        binary,
        &.{ "-f", db.path, "-r", db.root, "mark", "install" },
    );
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try expectExit(result, 0);
    try testing.expectEqualStrings("", result.stdout);
    try testing.expectEqualStrings("", result.stderr);
    try db.expectCreated();
}
