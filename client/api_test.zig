const std = @import("std");
const client = @import("client_root");
const abi = @import("client_abi");
const errors = @import("rpmz_error");

const c = abi.C;

test "API lifecycle and identity exports preserve transitional behavior" {
    try std.testing.expectEqual(@as(u32, 0), client.api.TDNFInit());
    client.api.TDNFUninit();
    try std.testing.expectEqualStrings(
        "rpmz",
        std.mem.span(client.api.TDNFGetPackageName()),
    );
    try std.testing.expect(
        std.mem.span(client.api.TDNFGetVersion()).len != 0,
    );
    client.api.TDNFCloseHandle(null);
}

test "API error paths preserve per-entry-point output semantics" {
    const sentinel: *abi.PackageInfo = @ptrFromInt(0x1000);
    var list_output: ?*abi.PackageInfo = sentinel;
    var list_count: u32 = 41;
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        client.api.TDNFList(
            null,
            c.SCOPE_ALL,
            null,
            &list_output,
            &list_count,
        ),
    );
    try std.testing.expectEqual(@as(?*abi.PackageInfo, null), list_output);
    try std.testing.expectEqual(@as(u32, 0), list_count);

    var query_args = std.mem.zeroes(c.TDNF_REPOQUERY_ARGS);
    var query_output: ?*abi.PackageInfo = sentinel;
    var query_count: u32 = 42;
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        client.api.TDNFRepoQuery(
            null,
            &query_args,
            &query_output,
            &query_count,
        ),
    );
    try std.testing.expectEqual(
        @intFromPtr(sentinel),
        @intFromPtr(query_output.?),
    );
    try std.testing.expectEqual(@as(u32, 42), query_count);

    var history_args = std.mem.zeroes(c.TDNF_HISTORY_ARGS);
    history_args.nCommand = c.HISTORY_CMD_INIT;
    const solved_sentinel: *abi.SolvedPackageInfo = @ptrFromInt(0x2000);
    var solved_output: ?*abi.SolvedPackageInfo = solved_sentinel;
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        client.api.TDNFHistoryResolve(
            null,
            &history_args,
            &solved_output,
        ),
    );
    try std.testing.expectEqual(
        @intFromPtr(solved_sentinel),
        @intFromPtr(solved_output.?),
    );
}

test "skip-problem options combine setopts and skip-broken" {
    var broken = abi.CnfNode{
        .name = @constCast(@as([*:0]const u8, "SKIPOBSOLETES")),
    };
    var conflicts = abi.CnfNode{
        .next = &broken,
        .name = @constCast(@as([*:0]const u8, "skipconflicts")),
    };
    var root = abi.CnfNode{ .first_child = &conflicts };
    var args = abi.CmdArgs{
        .nSkipBroken = 1,
        .cn_setopts = &root,
    };
    var handle = abi.Tdnf{ .pArgs = &args };
    var skip: c_uint = 0;
    try std.testing.expectEqual(
        @as(u32, 0),
        client.api.TDNFGetSkipProblemOption(&handle, &skip),
    );
    try std.testing.expectEqual(
        @as(c_uint, c.SKIPPROBLEM_CONFLICTS |
            c.SKIPPROBLEM_OBSOLETES |
            c.SKIPPROBLEM_BROKEN),
        skip,
    );

    skip = c.SKIPPROBLEM_BROKEN;
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        client.api.TDNFGetSkipProblemOption(null, &skip),
    );
    try std.testing.expectEqual(@as(c_uint, c.SKIPPROBLEM_NONE), skip);
}

test "command-line RPM path records own copies and close releases them" {
    const handle = try std.heap.c_allocator.create(abi.Tdnf);
    handle.* = .{};

    const first: [*:0]const u8 = "/one/package.rpm";
    const second: [*:0]const u8 = "/two/package.rpm";
    try std.testing.expectEqual(
        @as(u32, 0),
        client.api.recordCmdLinePkgPath(handle, 7, first),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        client.api.recordCmdLinePkgPath(handle, 9, second),
    );
    try std.testing.expectEqual(@as(u32, 2), handle.dwCmdLinePkgCount);
    try std.testing.expectEqual(@as(u32, 7), handle.pdwCmdLinePkgIds.?[0]);
    try std.testing.expectEqual(@as(u32, 9), handle.pdwCmdLinePkgIds.?[1]);
    try std.testing.expectEqualStrings(
        std.mem.span(first),
        std.mem.span(handle.ppszCmdLinePkgPaths.?[0].?),
    );
    try std.testing.expectEqualStrings(
        std.mem.span(second),
        std.mem.span(handle.ppszCmdLinePkgPaths.?[1].?),
    );
    try std.testing.expect(
        @intFromPtr(first) !=
            @intFromPtr(handle.ppszCmdLinePkgPaths.?[0].?),
    );

    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        client.api.recordCmdLinePkgPath(handle, 11, null),
    );
    try std.testing.expectEqual(@as(u32, 2), handle.dwCmdLinePkgCount);
    client.api.TDNFCloseHandle(handle);
}
