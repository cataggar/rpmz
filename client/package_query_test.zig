const std = @import("std");
const abi = @import("client_abi");
const repomd = @import("repository_metadata");

comptime {
    _ = @import("client_root");
}

const context_api = repomd.package_context;
const c = abi.C;

extern fn TDNFNativeQuerySerializePackageId(
    ?*context_api.Context,
    i32,
    *?[*:0]u8,
) u32;
extern fn TDNFNativeQueryResolvePackageRefArrayToQueue(
    ?*context_api.Context,
    [*c][*c]u8,
    u32,
    c_int,
    ?*abi.IdList,
) u32;
extern fn TDNFNativeQuerySplitPackageRef(
    ?[*:0]const u8,
    *?[*:0]u8,
    *u32,
    *?[*:0]u8,
    *?[*:0]u8,
    *?[*:0]u8,
    *?[*:0]u8,
) u32;
extern fn TDNFPopulatePkgInfosFromRefs(
    ?*context_api.Context,
    [*c][*c]u8,
    u32,
    *c.PTDNF_PKG_INFO,
) u32;
extern fn TDNFNativeQueryBuildUpdateInfoSummary(
    [*c][*c]u8,
    u32,
    *c.PTDNF_UPDATEINFO_SUMMARY,
) u32;
extern fn TDNFNativeQueryBuildUpdateInfo(
    [*c][*c]u8,
    u32,
    *c.PTDNF_UPDATEINFO,
) u32;
extern fn TDNFFreeMemory(?*anyopaque) void;
extern fn TDNFFreePackageInfo(c.PTDNF_PKG_INFO) void;
extern fn TDNFFreeUpdateInfoSummary(c.PTDNF_UPDATEINFO_SUMMARY) void;
extern fn TDNFFreeUpdateInfo(c.PTDNF_UPDATEINFO) void;

fn free(value: anytype) void {
    TDNFFreeMemory(@ptrCast(value));
}

fn tmpPath(
    tmp: *const std.testing.TmpDir,
    buffer: *[std.Io.Dir.max_path_bytes]u8,
    suffix: []const u8,
) [:0]const u8 {
    return std.fmt.bufPrintZ(
        buffer,
        ".zig-cache/tmp/{s}/{s}",
        .{ &tmp.sub_path, suffix },
    ) catch @panic("temporary path too long");
}

fn writeRpm(
    tmp: *std.testing.TmpDir,
    sub_path: []const u8,
    name: []const u8,
) !void {
    const bytes = try repomd.rpm_package.makeMinimalRpmBytesForTest(
        std.testing.allocator,
        name,
        "1",
        "2",
        "x86_64",
    );
    defer std.testing.allocator.free(bytes);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = sub_path,
        .data = bytes,
    });
}

test "production query layer preserves repository and command-line handles" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "repo-a", .default_dir);
    try tmp.dir.createDir(std.testing.io, "repo-b", .default_dir);
    try writeRpm(&tmp, "repo-a/alpha.rpm", "alpha");
    try writeRpm(&tmp, "repo-b/beta.rpm", "beta");
    try writeRpm(&tmp, "local.rpm", "local");

    var path_a_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var path_b_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var local_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_a = tmpPath(&tmp, &path_a_buffer, "repo-a");
    const path_b = tmpPath(&tmp, &path_b_buffer, "repo-b");
    const local = tmpPath(&tmp, &local_buffer, "local.rpm");

    const context = try context_api.create(
        std.testing.allocator,
        null,
        null,
        "x86_64",
    );
    defer context_api.destroy(context);
    const repo_a = try context_api.loadAvailableDirectory(
        context,
        "repo-a",
        null,
        10,
        path_a,
        -1,
    );
    const repo_b = try context_api.loadAvailableDirectory(
        context,
        "repo-b",
        null,
        20,
        path_b,
        -1,
    );
    const command_line = try context_api.createCommandLine(context);
    const local_id = try context_api.addCommandLineRpm(
        context,
        command_line,
        local,
    );
    const alpha_id: i32 = @intCast(repo_a.handles[0]);
    const beta_id: i32 = @intCast(repo_b.handles[0]);

    var alpha_ref: ?[*:0]u8 = null;
    defer free(alpha_ref);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFNativeQuerySerializePackageId(context, alpha_id, &alpha_ref),
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        std.mem.span(alpha_ref.?),
        "repo-a\x1falpha-1-2.x86_64",
    ));

    var local_ref: ?[*:0]u8 = null;
    defer free(local_ref);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFNativeQuerySerializePackageId(
            context,
            @intCast(local_id),
            &local_ref,
        ),
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        std.mem.span(local_ref.?),
        "@cmdline\x1flocal-1-2.x86_64",
    ));

    try std.testing.expect(context_api.removeRepository(context, repo_a));
    var stale: ?[*:0]u8 = @ptrFromInt(1);
    try std.testing.expectEqual(
        @as(u32, 1622),
        TDNFNativeQuerySerializePackageId(context, alpha_id, &stale),
    );
    try std.testing.expectEqual(@as(?[*:0]u8, null), stale);

    var beta_ref: ?[*:0]u8 = null;
    defer free(beta_ref);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFNativeQuerySerializePackageId(context, beta_id, &beta_ref),
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        std.mem.span(beta_ref.?),
        "repo-b\x1fbeta-1-2.x86_64",
    ));

    var refs = [_][*c]u8{ @ptrCast(local_ref.?), @ptrCast(local_ref.?), null };
    var queue = abi.IdList{};
    defer free(queue.pnElements);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFNativeQueryResolvePackageRefArrayToQueue(
            context,
            &refs,
            2,
            0,
            &queue,
        ),
    );
    try std.testing.expectEqual(@as(u32, 1), queue.dwCount);
    try std.testing.expectEqual(@as(i32, @intCast(local_id)), queue.pnElements.?[0]);

    var infos: c.PTDNF_PKG_INFO = null;
    var one_ref = [_][*c]u8{ @ptrCast(local_ref.?), null };
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFPopulatePkgInfosFromRefs(context, &one_ref, 1, &infos),
    );
    defer TDNFFreePackageInfo(infos);
    try std.testing.expectEqualStrings("local", std.mem.span(infos[0].pszName));
    try std.testing.expectEqualStrings(
        "@cmdline",
        std.mem.span(infos[0].pszRepoName),
    );
    try std.testing.expectEqualStrings("1", std.mem.span(infos[0].pszVersion));
    try std.testing.expectEqualStrings("2", std.mem.span(infos[0].pszRelease));
    try std.testing.expectEqualStrings("x86_64", std.mem.span(infos[0].pszArch));
}

test "package reference parser rejects malformed epochs and resets outputs" {
    var repo: ?[*:0]u8 = @ptrFromInt(1);
    var epoch: u32 = 99;
    var name: ?[*:0]u8 = @ptrFromInt(1);
    var version: ?[*:0]u8 = @ptrFromInt(1);
    var release: ?[*:0]u8 = @ptrFromInt(1);
    var arch: ?[*:0]u8 = @ptrFromInt(1);
    try std.testing.expectEqual(
        @as(u32, 1622),
        TDNFNativeQuerySplitPackageRef(
            "repo\x1fpkg-x:1-2.x86_64",
            &repo,
            &epoch,
            &name,
            &version,
            &release,
            &arch,
        ),
    );
    try std.testing.expectEqual(@as(?[*:0]u8, null), repo);
    try std.testing.expectEqual(@as(?[*:0]u8, null), name);
    try std.testing.expectEqual(@as(u32, 0), epoch);

    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFNativeQuerySplitPackageRef(
            "repo\x1fpkg-7:1-2.x86_64",
            &repo,
            &epoch,
            &name,
            &version,
            &release,
            &arch,
        ),
    );
    defer {
        free(repo);
        free(name);
        free(version);
        free(release);
        free(arch);
    }
    try std.testing.expectEqual(@as(u32, 7), epoch);
    try std.testing.expectEqualStrings("pkg", std.mem.span(name.?));
}

test "updateinfo conversion owns linked summaries and packages" {
    var summary_lines = [_][*c]u8{
        @ptrCast(@constCast("0\x1f3")),
        @ptrCast(@constCast("2\x1f5")),
        null,
    };
    var summary: c.PTDNF_UPDATEINFO_SUMMARY = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFNativeQueryBuildUpdateInfoSummary(
            &summary_lines,
            2,
            &summary,
        ),
    );
    defer TDNFFreeUpdateInfoSummary(summary);
    try std.testing.expectEqual(@as(c_int, 3), summary[0].nCount);
    try std.testing.expectEqual(@as(c_int, 5), summary[2].nCount);

    var detail_lines = [_][*c]u8{
        @ptrCast(@constCast(
            "1\x1f1\x1fADV-1\x1fdescription\x1f2026-08-08\x1f" ++
                "alpha\x1d1-2\x1dx86_64\x1dalpha.rpm",
        )),
        null,
    };
    var info: c.PTDNF_UPDATEINFO = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFNativeQueryBuildUpdateInfo(&detail_lines, 1, &info),
    );
    defer TDNFFreeUpdateInfo(info);
    try std.testing.expectEqualStrings("ADV-1", std.mem.span(info[0].pszID));
    try std.testing.expectEqualStrings(
        "alpha",
        std.mem.span(info[0].pPackages[0].pszName),
    );
}
