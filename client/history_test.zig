// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const testing = std.testing;
const history = @import("client_history");
const tdnf_error = @import("tdnf_error");

comptime {
    _ = @import("client_root");
}

extern fn destroy_history_ctx(context: ?*history.HistoryCtx) void;
extern fn TDNFGetHistoryCtx(
    tdnf: ?*history.Tdnf,
    context: ?*?*history.HistoryCtx,
    must_exist: c_int,
) u32;

const Fixture = struct {
    tmp: testing.TmpDir,
    root: [:0]u8,

    fn init() !Fixture {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();
        try tmp.dir.createDirPath(testing.io, "root");

        var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const root_len = try tmp.dir.realPath(testing.io, &path_buffer);
        return .{
            .tmp = tmp,
            .root = try std.fmt.allocPrintSentinel(
                testing.allocator,
                "{s}/root",
                .{path_buffer[0..root_len]},
                0,
            ),
        };
    }

    fn deinit(self: *Fixture) void {
        testing.allocator.free(self.root);
        self.tmp.cleanup();
    }
};

fn getHistory(
    install_root: [*:0]u8,
    persist_dir: [*:0]const u8,
    out: ?*?*history.HistoryCtx,
    must_exist: c_int,
) u32 {
    var args = history.CmdArgs{
        .pszInstallRoot = install_root,
    };
    var conf = history.Conf{
        .pszPersistDir = @constCast(persist_dir),
    };
    var tdnf = history.Tdnf{
        .pArgs = &args,
        .pConf = &conf,
    };
    return TDNFGetHistoryCtx(&tdnf, out, must_exist);
}

test "TDNFGetHistoryCtx rejects only its required arguments" {
    var sentinel: ?*history.HistoryCtx = @ptrFromInt(1);
    try testing.expectEqual(
        tdnf_error.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetHistoryCtx(null, &sentinel, 0),
    );
    try testing.expectEqual(@as(usize, 1), @intFromPtr(sentinel.?));

    var tdnf = history.Tdnf{};
    try testing.expectEqual(
        tdnf_error.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetHistoryCtx(&tdnf, null, 0),
    );
}

test "TDNFGetHistoryCtx creates the install-root history path" {
    var fixture = try Fixture.init();
    defer fixture.deinit();

    var context: ?*history.HistoryCtx = null;
    try testing.expectEqual(
        @as(u32, 0),
        getHistory(fixture.root.ptr, "/persist", &context, 0),
    );
    defer destroy_history_ctx(context);
    try testing.expect(context != null);
    try fixture.tmp.dir.access(
        testing.io,
        "root/persist/history.db",
        .{},
    );
}

test "TDNFGetHistoryCtx must-exist leaves a missing path untouched" {
    var fixture = try Fixture.init();
    defer fixture.deinit();

    var context: ?*history.HistoryCtx = null;
    try testing.expectEqual(
        tdnf_error.ERROR_TDNF_HISTORY_NODB,
        getHistory(fixture.root.ptr, "/persist", &context, 1),
    );
    try testing.expect(context == null);
    try testing.expectError(
        error.FileNotFound,
        fixture.tmp.dir.access(testing.io, "root/persist", .{}),
    );
}

test "TDNFGetHistoryCtx opens existing regular and symlink databases" {
    var fixture = try Fixture.init();
    defer fixture.deinit();

    var context: ?*history.HistoryCtx = null;
    try testing.expectEqual(
        @as(u32, 0),
        getHistory(fixture.root.ptr, "/persist", &context, 0),
    );
    destroy_history_ctx(context);
    context = null;

    try testing.expectEqual(
        @as(u32, 0),
        getHistory(fixture.root.ptr, "/persist", &context, 1),
    );
    destroy_history_ctx(context);
    context = null;

    try fixture.tmp.dir.rename(
        "root/persist/history.db",
        fixture.tmp.dir,
        "root/persist/target.db",
        testing.io,
    );
    try fixture.tmp.dir.symLink(
        testing.io,
        "target.db",
        "root/persist/history.db",
        .{},
    );
    try testing.expectEqual(
        @as(u32, 0),
        getHistory(fixture.root.ptr, "/persist", &context, 1),
    );
    defer destroy_history_ctx(context);
    try testing.expect(context != null);
}

test "TDNFGetHistoryCtx reports directory creation failure" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "root/blocker",
        .data = "not a directory",
    });
    const blocker = try std.fmt.allocPrintSentinel(
        testing.allocator,
        "{s}/blocker",
        .{fixture.root},
        0,
    );
    defer testing.allocator.free(blocker);

    var context: ?*history.HistoryCtx = null;
    try testing.expectEqual(
        tdnf_error.ERROR_TDNF_INVALID_DIR,
        getHistory(blocker.ptr, "/persist", &context, 0),
    );
    try testing.expect(context == null);
}

test "TDNFGetHistoryCtx cleans up after context creation failure" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(
        testing.io,
        "root/persist/history.db",
    );

    var context: ?*history.HistoryCtx = null;
    try testing.expectEqual(
        tdnf_error.ERROR_TDNF_HISTORY_ERROR,
        getHistory(fixture.root.ptr, "/persist", &context, 0),
    );
    try testing.expect(context == null);
}
