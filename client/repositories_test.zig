const std = @import("std");
const root = @import("client_root");
const abi = @import("client_abi");
const errors = @import("tdnf_error");

const CnfNode = abi.CnfNode;
const RepoData = abi.RepoData;

extern fn create_cnfnode(?[*:0]const u8) ?*CnfNode;
extern fn cnfnode_setval(?*CnfNode, ?[*:0]const u8) void;
extern fn append_node(?*CnfNode, ?*CnfNode) void;
extern fn destroy_cnftree(?*CnfNode) void;
extern fn register_ini(?*CnfNode) void;
extern fn TDNFLoadRepoData(?*abi.Tdnf, ?*?*RepoData) u32;
extern fn TDNFRepoListFinalize(?*abi.Tdnf) u32;
extern fn TDNFFreeReposInternal(?*RepoData) void;

fn scratchPath(name: []const u8) ![:0]u8 {
    return std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/client-repositories-{d}-{s}",
        .{ std.os.linux.getpid(), name },
        0,
    );
}

fn findRepo(repos: ?*RepoData, id: []const u8) ?*RepoData {
    var current = repos;
    while (current) |repo| : (current = repo.pNext) {
        if (repo.pszId != null and std.mem.eql(u8, id, std.mem.span(repo.pszId.?)))
            return repo;
    }
    return null;
}

test "production repository loader preserves defaults and full config" {
    _ = root;
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const path = try scratchPath("load");
    defer std.testing.allocator.free(path);
    cwd.deleteTree(io, path) catch {};
    defer cwd.deleteTree(io, path) catch {};
    try cwd.createDirPath(io, path);
    const repo_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/sample.repo",
        .{path},
    );
    defer std.testing.allocator.free(repo_path);
    try cwd.writeFile(io, .{
        .sub_path = repo_path,
        .data =
        \\[defaults]
        \\baseurl=https://example.invalid/defaults
        \\
        \\[full]
        \\name=Full Repository
        \\enabled=1
        \\baseurl=https://one.invalid/repo
        \\baseurl=https://two.invalid/repo
        \\mirrorlist=https://mirror.invalid/list
        \\metalink=https://meta.invalid/file
        \\snapshot=snapshots/current
        \\gpgcheck=1
        \\gpgkey=https://keys.invalid/one
        \\gpgkey=https://keys.invalid/two
        \\priority=7
        \\metadata_expire=1h
        \\timeout=12
        \\retries=4
        \\minrate=9
        \\throttle=10
        \\sslverify=0
        \\sslcacert=/ca.pem
        \\sslclientcert=/client.pem
        \\sslclientkey=/client.key
        \\username=user
        \\password=pass
        \\skip_md_filelists=1
        \\skip_md_updateinfo=1
        \\skip_md_other=1
        \\
        ,
    });

    register_ini(null);
    const setopts = create_cnfnode("(root)") orelse return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const enable = create_cnfnode("enablerepo") orelse return error.OutOfMemory;
    cnfnode_setval(enable, "defaults");
    append_node(setopts, enable);
    const repoopts = create_cnfnode("(root)") orelse return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    const full_options = create_cnfnode("full") orelse return error.OutOfMemory;
    append_node(repoopts, full_options);
    const priority = create_cnfnode("priority") orelse return error.OutOfMemory;
    cnfnode_setval(priority, "3");
    append_node(full_options, priority);
    var args = abi.CmdArgs{ .cn_setopts = setopts, .cn_repoopts = repoopts };
    var conf = abi.Conf{
        .nGPGCheck = 0,
        .nCliGPGCheck = 1,
        .nSSLVerify = 1,
        .pszRepoDir = path.ptr,
        .pszVarReleaseVer = @constCast("42"),
        .pszVarBaseArch = @constCast("x86_64"),
    };
    var handle = abi.Tdnf{ .pArgs = &args, .pConf = &conf };
    var repos: ?*RepoData = null;
    try std.testing.expectEqual(@as(u32, 0), TDNFLoadRepoData(&handle, &repos));
    defer if (repos != null) TDNFFreeReposInternal(repos);

    const defaults = findRepo(repos, "defaults") orelse return error.MissingRepo;
    try std.testing.expectEqual(@as(c_int, 0), defaults.nEnabled);
    try std.testing.expectEqual(@as(c_int, 50), defaults.nPriority);
    try std.testing.expectEqual(@as(c_long, 172800), defaults.lMetadataExpire);
    try std.testing.expectEqualStrings("defaults", std.mem.span(defaults.pszName.?));

    const full = findRepo(repos, "full") orelse return error.MissingRepo;
    try std.testing.expectEqual(@as(c_int, 1), full.nEnabled);
    try std.testing.expectEqual(@as(c_int, 3), full.nPriority);
    try std.testing.expectEqual(@as(c_long, 3600), full.lMetadataExpire);
    try std.testing.expectEqual(@as(c_long, 12), full.nTimeout);
    try std.testing.expectEqual(@as(c_int, 4), full.nRetries);
    try std.testing.expectEqual(@as(c_int, 0), full.nSSLVerify);
    try std.testing.expectEqualStrings("https://two.invalid/repo", std.mem.span(full.ppszBaseUrls.?[1].?));
    try std.testing.expectEqualStrings("https://keys.invalid/two", std.mem.span(full.ppszUrlGPGKeys.?[1].?));

    handle.pRepos = repos;
    try std.testing.expectEqual(@as(u32, 0), TDNFRepoListFinalize(&handle));
    try std.testing.expectEqual(@as(c_int, 1), defaults.nEnabled);
    try std.testing.expect(full.pszCacheName != null);
    try std.testing.expect(!std.mem.eql(
        u8,
        std.mem.span(full.pszId.?),
        std.mem.span(full.pszCacheName.?),
    ));

    TDNFFreeReposInternal(repos);
    repos = null;
    handle.pRepos = null;
    for (0..8) |_| {
        try std.testing.expectEqual(@as(u32, 0), TDNFLoadRepoData(&handle, &repos));
        TDNFFreeReposInternal(repos);
        repos = null;
    }
}

test "production repository loader rejects negative retries and accepts zero or positive values" {
    _ = root;
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const path = try scratchPath("retries");
    defer std.testing.allocator.free(path);
    cwd.deleteTree(io, path) catch {};
    defer cwd.deleteTree(io, path) catch {};
    try cwd.createDirPath(io, path);
    const repo_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/sample.repo",
        .{path},
    );
    defer std.testing.allocator.free(repo_path);

    register_ini(null);
    const setopts = create_cnfnode("(root)") orelse return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    var args = abi.CmdArgs{ .cn_setopts = setopts };
    var conf = abi.Conf{ .pszRepoDir = path.ptr };
    var handle = abi.Tdnf{ .pArgs = &args, .pConf = &conf };

    const cases = [_]struct {
        value: c_int,
        expected_result: u32,
    }{
        .{ .value = -1, .expected_result = errors.ERROR_TDNF_INVALID_PARAMETER },
        .{ .value = 0, .expected_result = 0 },
        .{ .value = 3, .expected_result = 0 },
    };
    for (cases) |case| {
        const contents = try std.fmt.allocPrint(
            std.testing.allocator,
            "[sample]\nbaseurl=https://example.invalid/repo\nretries={d}\n",
            .{case.value},
        );
        defer std.testing.allocator.free(contents);
        try cwd.writeFile(io, .{ .sub_path = repo_path, .data = contents });

        var repos: ?*RepoData = null;
        const result = TDNFLoadRepoData(&handle, &repos);
        defer if (repos != null) TDNFFreeReposInternal(repos);
        try std.testing.expectEqual(case.expected_result, result);
        if (result == 0) {
            const repo = findRepo(repos, "sample") orelse
                return error.MissingRepo;
            try std.testing.expectEqual(case.value, repo.nRetries);
        } else {
            try std.testing.expectEqual(@as(?*RepoData, null), repos);
        }
    }
}

test "production repository loader rejects duplicate ids and symlink repo files" {
    _ = root;
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const path = try scratchPath("duplicates");
    defer std.testing.allocator.free(path);
    cwd.deleteTree(io, path) catch {};
    defer cwd.deleteTree(io, path) catch {};
    try cwd.createDirPath(io, path);
    const first = try std.fmt.allocPrint(std.testing.allocator, "{s}/one.repo", .{path});
    defer std.testing.allocator.free(first);
    const second = try std.fmt.allocPrint(std.testing.allocator, "{s}/two.repo", .{path});
    defer std.testing.allocator.free(second);
    try cwd.writeFile(io, .{ .sub_path = first, .data = "[same]\nbaseurl=https://one.invalid\n" });
    try cwd.writeFile(io, .{ .sub_path = second, .data = "[same]\nbaseurl=https://two.invalid\n" });

    register_ini(null);
    const setopts = create_cnfnode("(root)") orelse return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    var args = abi.CmdArgs{ .cn_setopts = setopts };
    var conf = abi.Conf{ .pszRepoDir = path.ptr };
    var handle = abi.Tdnf{ .pArgs = &args, .pConf = &conf };
    var repos: ?*RepoData = @ptrFromInt(@alignOf(RepoData));
    try std.testing.expectEqual(
        errors.ERROR_TDNF_DUPLICATE_REPO_ID,
        TDNFLoadRepoData(&handle, &repos),
    );
    try std.testing.expectEqual(@as(?*RepoData, null), repos);

    try cwd.deleteFile(io, second);
    try cwd.symLink(io, "one.repo", second, .{});
    try std.testing.expectEqual(@as(u32, 0), TDNFLoadRepoData(&handle, &repos));
    defer TDNFFreeReposInternal(repos);
    try std.testing.expect(findRepo(repos, "same") != null);
}
