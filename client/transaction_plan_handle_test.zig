const std = @import("std");

comptime {
    _ = @import("client_root");
}

const CmdArgs = extern struct {
    nAllDeps: c_int = 0,
    nAllowErasing: c_int = 0,
    nAssumeNo: c_int = 0,
    nAssumeYes: c_int = 0,
    nBest: c_int = 0,
    nCacheOnly: c_int = 0,
    nDebugSolver: c_int = 0,
    nShowHelp: c_int = 0,
    nRefresh: c_int = 0,
    nRpmVerbosity: c_int = 0,
    nShowDuplicates: c_int = 0,
    nShowVersion: c_int = 0,
    nNoDeps: c_int = 0,
    nNoGPGCheck: c_int = 0,
    nNoCmdLineGPGCheck: c_int = 0,
    nSkipSignature: c_int = 0,
    nSkipDigest: c_int = 0,
    nNoOutput: c_int = 0,
    nQuiet: c_int = 0,
    nVerbose: c_int = 0,
    nIPv4: c_int = 0,
    nIPv6: c_int = 0,
    nDisableExcludes: c_int = 0,
    nDownloadOnly: c_int = 0,
    nUrlsOnly: c_int = 0,
    nNoAutoRemove: c_int = 0,
    nJsonOutput: c_int = 0,
    nTestOnly: c_int = 0,
    nSkipBroken: c_int = 0,
    nSource: c_int = 0,
    nBuildDeps: c_int = 0,
    pszArch: ?[*:0]u8 = null,
    pszDownloadDir: ?[*:0]u8 = null,
    pszInstallRoot: ?[*:0]u8 = null,
    pszConfFile: ?[*:0]u8 = null,
    pszReleaseVer: ?[*:0]u8 = null,
    ppszCmds: ?[*]?[*:0]u8 = null,
    nCmdCount: c_int = 0,
    cn_setopts: ?*anyopaque = null,
    cn_repoopts: ?*anyopaque = null,
    nArgc: c_int = 0,
    ppszArgv: ?[*]?[*:0]u8 = null,
};

const HistoryArgs = extern struct {
    command: c_int = 1,
    info: c_int = 0,
    from: c_int = 0,
    to: c_int = 0,
    reverse: c_int = 0,
    spec: ?[*:0]u8 = null,
};

const HistoryDelta = extern struct {
    added_ids: ?[*]c_int,
    added_count: c_int,
    removed_ids: ?[*]c_int,
    removed_count: c_int,
};

const SolvSackView = extern struct {
    pool: ?*anyopaque,
    command_package_count: u32,
    cache_dir: ?[*:0]u8,
    root_dir: ?[*:0]u8,
};

const SackSnapshot = extern struct {
    pool_identity: usize = 0,
    repository_identity: usize = 0,
    considered_identity: usize = 0,
    indexes_identity: usize = 0,
    solvable_count: u32 = 0,
    repository_count: u32 = 0,
    considered_count: u32 = 0,
    digest: [32]u8 = [_]u8{0} ** 32,
};

const alter_install: c_int = 5;
const alter_erase: c_int = 4;
const alter_upgrade_all: c_int = 8;
const error_call_not_supported: u32 = 1638;
const error_invalid_parameter: u32 = 1622;
const error_out_of_memory: u32 = 1612;
const error_protected: u32 = 1030;
const error_solv_failed: u32 = 1301;
const error_already_installed: u32 = 1026;
const error_cache_disabled: u32 = 1034;
const filter_security: u8 = 1 << 0;
const filter_severity: u8 = 1 << 1;
const filter_reboot_required: u8 = 1 << 2;

extern fn create_cnfnode(name: ?[*:0]const u8) ?*anyopaque;
extern fn destroy_cnftree(node: ?*anyopaque) void;
extern fn cnfnode_setval(
    node: ?*anyopaque,
    value: ?[*:0]const u8,
) void;
extern fn append_node(parent: ?*anyopaque, node: ?*anyopaque) void;
extern fn SolvCreateRepoCacheName(
    repository: ?[*:0]const u8,
    source: ?[*:0]const u8,
    output: ?*?[*:0]u8,
) u32;
extern fn TDNFFreeMemory(memory: ?*anyopaque) void;
extern fn TDNFOpenHandle(args: ?*CmdArgs, handle: ?*?*anyopaque) u32;
extern fn TDNFCloseHandle(handle: ?*anyopaque) void;
extern fn TDNFResolve(
    handle: ?*anyopaque,
    alter_type: c_int,
    solved: ?*?*anyopaque,
) u32;
extern fn TDNFHistoryResolve(
    handle: ?*anyopaque,
    args: ?*HistoryArgs,
    solved: ?*?*anyopaque,
) u32;
extern fn TDNFRefresh(handle: ?*anyopaque) u32;
extern fn TDNFRefreshSack(
    handle: ?*anyopaque,
    sack: ?*anyopaque,
    clean_metadata: c_int,
) u32;
extern fn SolvInitSack(
    sack: ?*?*anyopaque,
    cache_dir: ?[*:0]const u8,
    root_dir: ?[*:0]const u8,
    arch: ?[*:0]const u8,
) u32;
extern fn SolvFreeSack(sack: ?*anyopaque) void;
extern fn SolvCountPackages(
    sack: ?*anyopaque,
    count: ?*u32,
) u32;
extern fn repo_create(
    pool: ?*anyopaque,
    name: ?[*:0]const u8,
) ?*anyopaque;
extern fn repo_add_solvable(repo: ?*anyopaque) c_int;
extern fn TDNFFreeSolvedPackageInfo(solved: ?*anyopaque) void;
extern fn TDNFTransactionPlanCaptureSetEnabled(
    handle: ?*anyopaque,
    enabled: u32,
) u32;
extern fn TDNFTransactionPlanCaptureGetCanonicalJson(
    handle: ?*anyopaque,
    data: ?*?[*]const u8,
    length: ?*usize,
) u32;
extern fn TDNFTransactionPlanCaptureFailNextRepositoryRecord(
    handle: ?*anyopaque,
) void;
extern fn TDNFTransactionPlanCaptureFailNextComposition(
    handle: ?*anyopaque,
) void;
extern fn TDNFTransactionPlanCaptureFailNextIntegrity(
    handle: ?*anyopaque,
) void;
extern fn TDNFTransactionPlanTestFailNextReload(
    handle: ?*anyopaque,
    stage: u32,
) void;
extern fn TDNFTransactionPlanTestPoolIdentity(handle: ?*anyopaque) usize;
extern fn TDNFTransactionPlanTestPoolSolvableCount(
    handle: ?*anyopaque,
) u32;
extern fn TDNFTransactionPlanTestPoolRepoCount(
    handle: ?*anyopaque,
) u32;
extern fn TDNFTransactionPlanTestConsideredCount(
    handle: ?*anyopaque,
) u32;
extern fn TDNFTransactionPlanTestConsideredIdentity(
    handle: ?*anyopaque,
) usize;
extern fn TDNFTransactionPlanTestRepoDataCount(handle: ?*anyopaque) u32;
extern fn TDNFTransactionPlanTestGrowCmdlineConsidered(
    handle: ?*anyopaque,
) u32;
extern fn TDNFTransactionPlanTestRetireNullSack(
    handle: ?*anyopaque,
) u32;
extern fn TDNFTransactionPlanTestPublicInitRepo(
    handle: ?*anyopaque,
) u32;
extern fn TDNFTransactionPlanTestReloadRepo(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
) u32;
extern fn TDNFTransactionPlanTestInitRepoInSack(
    handle: ?*anyopaque,
    sack: ?*anyopaque,
    repo_id: ?[*:0]const u8,
) u32;
extern fn TDNFTransactionPlanTestRepoIdentity(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
) usize;
extern fn TDNFTransactionPlanTestRepoId(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
) u32;
extern fn TDNFTransactionPlanTestRepoPackageCount(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
) u32;
extern fn TDNFTransactionPlanTestRepoBindingCount(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
) u32;
extern fn TDNFTransactionPlanTestRepoRecordCount(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
) u32;
extern fn TDNFTransactionPlanTestRepoRecordDigest(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
    digest: ?[*]u8,
) u32;
extern fn TDNFTransactionPlanTestInitRepoValidation(
    handle: ?*anyopaque,
) u32;
extern fn TDNFTransactionPlanTestPoolIndexesHealthy(
    handle: ?*anyopaque,
) u32;
extern fn TDNFTransactionPlanTestSackSnapshot(
    sack: ?*anyopaque,
    repository_id: ?[*:0]const u8,
    snapshot: ?*SackSnapshot,
) u32;
extern fn TDNFTransactionPlanTestEnableRepo(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
) u32;
extern fn TDNFTransactionPlanStateFreeCanonicalJson(
    data: ?[*]const u8,
    length: usize,
) void;
extern fn tdnf_rpm_config_create(root: ?[*:0]const u8) ?*anyopaque;
extern fn tdnf_rpm_config_destroy(config: ?*anyopaque) void;
extern fn tdnf_rpm_config_resolve_path(
    config: ?*const anyopaque,
    name: ?[*:0]const u8,
) ?[*:0]u8;
extern fn tdnf_rpm_config_string_free(value: ?[*:0]u8) void;

/// Resolves the rpmdb file the writer actually uses. The `_dbpath` macro
/// is host configurable, so the location cannot be assumed to be
/// `<root>/var/lib/rpm`.
fn resolveRpmDbPath(
    allocator: std.mem.Allocator,
    rpm_config: ?*anyopaque,
) ![]u8 {
    const dbpath = tdnf_rpm_config_resolve_path(rpm_config, "_dbpath") orelse
        return error.TestUnexpectedResult;
    defer tdnf_rpm_config_string_free(dbpath);
    return std.fmt.allocPrint(
        allocator,
        "{s}/rpmdb.sqlite",
        .{std.mem.span(dbpath)},
    );
}
extern fn TDNFTransactionPlanTestWriteFileProvider(
    config: ?*const anyopaque,
) c_int;
extern fn TDNFTransactionPlanTestWriteHistoryFixture(
    path: ?[*:0]const u8,
) c_int;
extern fn TDNFTransactionPlanTestWriteExcludedHistoryFixture(
    path: ?[*:0]const u8,
) c_int;
extern fn create_history_ctx(path: ?[*:0]const u8) ?*anyopaque;
extern fn destroy_history_ctx(context: ?*anyopaque) void;
extern fn history_get_delta_range(
    context: ?*anyopaque,
    from: c_int,
    to: c_int,
) ?*HistoryDelta;
extern fn history_free_delta(delta: ?*HistoryDelta) void;
extern fn TDNFTransactionPlanRequestTraceTestFailNextCreate() void;
extern fn TDNFTransactionPlanRequestTraceTestFailNextRecord() void;
extern fn TDNFInitRepoFromMetadata(
    repository: ?*anyopaque,
    repository_name: ?[*:0]const u8,
    metadata: ?*anyopaque,
) u32;
extern fn chmod(path: ?[*:0]const u8, mode: c_uint) c_int;

const primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common"
    \\          xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="3">
    \\  <package type="rpm">
    \\    <name>app</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</checksum>
    \\    <size package="123"/>
    \\    <location href="packages/app.rpm"/>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>conflict-a</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee</checksum>
    \\    <size package="124"/>
    \\    <location href="packages/conflict-a.rpm"/>
    \\    <format>
    \\      <rpm:requires><rpm:entry name="missing-capability"/></rpm:requires>
    \\    </format>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>replacement-provider</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff</checksum>
    \\    <size package="125"/>
    \\    <location href="packages/replacement-provider.rpm"/>
    \\    <format>
    \\      <rpm:obsoletes><rpm:entry name="installed-file-provider"/></rpm:obsoletes>
    \\    </format>
    \\  </package>
    \\</metadata>
;

const extras_primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common"
    \\          xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="2">
    \\  <package type="rpm">
    \\    <name>excluded</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb</checksum>
    \\    <size package="321"/>
    \\    <location href="packages/excluded.rpm"/>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>survivor</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc</checksum>
    \\    <size package="222"/>
    \\    <location href="packages/survivor.rpm"/>
    \\    <format>
    \\      <rpm:requires><rpm:entry name="/usr/bin/tool"/></rpm:requires>
    \\    </format>
    \\  </package>
    \\</metadata>
;

const empty_primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common" packages="0">
    \\</metadata>
;

const filtered_update_primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common" packages="1">
    \\  <package type="rpm">
    \\    <name>installed-file-provider</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="2" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd</checksum>
    \\    <size package="223"/>
    \\    <location href="packages/installed-file-provider.rpm"/>
    \\  </package>
    \\</metadata>
;

const filtered_updateinfo_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<updates>
    \\  <update from="handle-test" status="stable" type="security" version="1">
    \\    <id>HTSA-1</id>
    \\    <title>installed-file-provider</title>
    \\    <severity>7.5</severity>
    \\    <issued date="2026-01-01 00:00:00"/>
    \\    <description>Filtered update fixture.</description>
    \\    <pkglist>
    \\      <collection short="handle-test">
    \\        <name>Handle test</name>
    \\        <package arch="x86_64" epoch="0" name="installed-file-provider" release="1" version="2">
    \\          <filename>installed-file-provider-2-1.x86_64.rpm</filename>
    \\          <reboot_suggested>true</reboot_suggested>
    \\        </package>
    \\      </collection>
    \\    </pkglist>
    \\  </update>
    \\</updates>
;

const Fixture = struct {
    tmp: std.testing.TmpDir,
    root: [:0]u8,
    config: [:0]u8,
    base_repomd: []u8,
    extras_repomd: []u8,
    base_solv: []u8,

    fn create() !Fixture {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        try tmp.dir.createDirPath(std.testing.io, "root/etc");
        try tmp.dir.createDirPath(std.testing.io, "root/repos");
        try tmp.dir.createDirPath(std.testing.io, "root/cache");
        try tmp.dir.createDirPath(std.testing.io, "root/persist");
        try tmp.dir.createDirPath(std.testing.io, "root/source");
        try tmp.dir.createDirPath(std.testing.io, "root/source-extra");
        try tmp.dir.createDirPath(std.testing.io, "root/source-empty");

        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        switch (std.os.linux.errno(std.os.linux.getcwd(
            cwd_buffer[0..].ptr,
            cwd_buffer.len,
        ))) {
            .SUCCESS => {},
            else => return error.TestUnexpectedResult,
        }
        const cwd_length = std.mem.findScalar(u8, &cwd_buffer, 0) orelse
            return error.TestUnexpectedResult;
        const allocator = std.testing.allocator;
        const root = try std.fmt.allocPrintSentinel(
            allocator,
            "{s}/.zig-cache/tmp/{s}/root",
            .{ cwd_buffer[0..cwd_length], &tmp.sub_path },
            0,
        );
        errdefer allocator.free(root);
        const config = try std.fmt.allocPrintSentinel(
            allocator,
            "{s}/tdnf.conf",
            .{root},
            0,
        );
        errdefer allocator.free(config);
        const base_url = try std.fmt.allocPrintSentinel(
            allocator,
            "file://{s}/source",
            .{root},
            0,
        );
        defer allocator.free(base_url);
        const extras_url = try std.fmt.allocPrintSentinel(
            allocator,
            "file://{s}/source-extra",
            .{root},
            0,
        );
        defer allocator.free(extras_url);
        const empty_url = try std.fmt.allocPrintSentinel(
            allocator,
            "file://{s}/source-empty",
            .{root},
            0,
        );
        defer allocator.free(empty_url);

        var cache_name: ?[*:0]u8 = null;
        try std.testing.expectEqual(
            @as(u32, 0),
            SolvCreateRepoCacheName("base", base_url.ptr, &cache_name),
        );
        const cache_name_pointer = cache_name orelse
            return error.TestUnexpectedResult;
        defer TDNFFreeMemory(cache_name_pointer);
        var extras_cache_name: ?[*:0]u8 = null;
        try std.testing.expectEqual(
            @as(u32, 0),
            SolvCreateRepoCacheName(
                "extras",
                extras_url.ptr,
                &extras_cache_name,
            ),
        );
        const extras_cache_name_pointer = extras_cache_name orelse
            return error.TestUnexpectedResult;
        defer TDNFFreeMemory(extras_cache_name_pointer);
        var empty_cache_name: ?[*:0]u8 = null;
        try std.testing.expectEqual(
            @as(u32, 0),
            SolvCreateRepoCacheName(
                "empty",
                empty_url.ptr,
                &empty_cache_name,
            ),
        );
        const empty_cache_name_pointer = empty_cache_name orelse
            return error.TestUnexpectedResult;
        defer TDNFFreeMemory(empty_cache_name_pointer);
        const cache_relative = try std.fmt.allocPrint(
            allocator,
            "root/cache/{s}/repodata",
            .{std.mem.span(cache_name_pointer)},
        );
        defer allocator.free(cache_relative);
        const base_solv = try std.fmt.allocPrint(
            allocator,
            "root/cache/{s}/solvcache/base.solv",
            .{std.mem.span(cache_name_pointer)},
        );
        errdefer allocator.free(base_solv);
        try tmp.dir.createDirPath(std.testing.io, cache_relative);
        const extras_cache_relative = try std.fmt.allocPrint(
            allocator,
            "root/cache/{s}/repodata",
            .{std.mem.span(extras_cache_name_pointer)},
        );
        defer allocator.free(extras_cache_relative);
        try tmp.dir.createDirPath(std.testing.io, extras_cache_relative);
        const empty_cache_relative = try std.fmt.allocPrint(
            allocator,
            "root/cache/{s}/repodata",
            .{std.mem.span(empty_cache_name_pointer)},
        );
        defer allocator.free(empty_cache_relative);
        try tmp.dir.createDirPath(std.testing.io, empty_cache_relative);

        const primary_digest = digestHex(primary_xml);
        const repomd = try std.fmt.allocPrint(
            allocator,
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
            \\  <revision>handle-integration</revision>
            \\  <data type="primary">
            \\    <checksum type="sha256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/primary.xml"/>
            \\    <timestamp>123</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\</repomd>
        ,
            .{
                &primary_digest,
                &primary_digest,
                primary_xml.len,
                primary_xml.len,
            },
        );
        defer allocator.free(repomd);
        const repomd_relative = try std.fmt.allocPrint(
            allocator,
            "{s}/repomd.xml",
            .{cache_relative},
        );
        defer allocator.free(repomd_relative);
        const base_repomd = try allocator.dupe(u8, repomd_relative);
        errdefer allocator.free(base_repomd);
        const primary_relative = try std.fmt.allocPrint(
            allocator,
            "{s}/primary.xml",
            .{cache_relative},
        );
        defer allocator.free(primary_relative);
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = repomd_relative,
            .data = repomd,
        });
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = primary_relative,
            .data = primary_xml,
        });
        const extras_digest = digestHex(extras_primary_xml);
        const extras_repomd = try std.fmt.allocPrint(
            allocator,
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
            \\  <revision>handle-integration-extras</revision>
            \\  <data type="primary">
            \\    <checksum type="sha256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/primary.xml"/>
            \\    <timestamp>124</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\</repomd>
        ,
            .{
                &extras_digest,
                &extras_digest,
                extras_primary_xml.len,
                extras_primary_xml.len,
            },
        );
        defer allocator.free(extras_repomd);
        const extras_repomd_relative = try std.fmt.allocPrint(
            allocator,
            "{s}/repomd.xml",
            .{extras_cache_relative},
        );
        defer allocator.free(extras_repomd_relative);
        const extras_repomd_path = try allocator.dupe(
            u8,
            extras_repomd_relative,
        );
        errdefer allocator.free(extras_repomd_path);
        const extras_primary_relative = try std.fmt.allocPrint(
            allocator,
            "{s}/primary.xml",
            .{extras_cache_relative},
        );
        defer allocator.free(extras_primary_relative);
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = extras_repomd_relative,
            .data = extras_repomd,
        });
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = extras_primary_relative,
            .data = extras_primary_xml,
        });
        const empty_digest = digestHex(empty_primary_xml);
        const empty_repomd = try std.fmt.allocPrint(
            allocator,
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
            \\  <revision>handle-integration-empty</revision>
            \\  <data type="primary">
            \\    <checksum type="sha256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/primary.xml"/>
            \\    <timestamp>125</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\</repomd>
        ,
            .{
                &empty_digest,
                &empty_digest,
                empty_primary_xml.len,
                empty_primary_xml.len,
            },
        );
        defer allocator.free(empty_repomd);
        const empty_repomd_relative = try std.fmt.allocPrint(
            allocator,
            "{s}/repomd.xml",
            .{empty_cache_relative},
        );
        defer allocator.free(empty_repomd_relative);
        const empty_primary_relative = try std.fmt.allocPrint(
            allocator,
            "{s}/primary.xml",
            .{empty_cache_relative},
        );
        defer allocator.free(empty_primary_relative);
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = empty_repomd_relative,
            .data = empty_repomd,
        });
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = empty_primary_relative,
            .data = empty_primary_xml,
        });
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "root/etc/os-release",
            .data = "ID=handle-test\nVERSION_ID=1\n",
        });
        const repo_config = try std.fmt.allocPrint(
            allocator,
            \\[base]
            \\name=Base
            \\baseurl={s}
            \\enabled=1
            \\gpgcheck=0
            \\metadata_expire=-1
            \\skip_if_unavailable=1
            \\
            \\[extras]
            \\name=Extras
            \\baseurl={s}
            \\enabled=1
            \\gpgcheck=0
            \\metadata_expire=-1
            \\skip_if_unavailable=1
            \\
            \\[empty]
            \\name=Empty
            \\baseurl={s}
            \\enabled=1
            \\gpgcheck=0
            \\metadata_expire=-1
            \\skip_if_unavailable=1
            \\
        ,
            .{ base_url, extras_url, empty_url },
        );
        defer allocator.free(repo_config);
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "root/repos/base.repo",
            .data = repo_config,
        });
        const tdnf_config = try std.fmt.allocPrint(
            allocator,
            \\[main]
            \\gpgcheck=0
            \\installonly_limit=3
            \\clean_requirements_on_remove=0
            \\repodir=/repos
            \\cachedir=/cache
            \\persistdir=/persist
            \\plugins=0
            \\excludepkgs=excluded
            \\excludepkgs=excluded
            \\
        ,
            .{},
        );
        defer allocator.free(tdnf_config);
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "root/tdnf.conf",
            .data = tdnf_config,
        });
        return .{
            .tmp = tmp,
            .root = root,
            .config = config,
            .base_repomd = base_repomd,
            .extras_repomd = extras_repomd_path,
            .base_solv = base_solv,
        };
    }

    fn destroy(self: *Fixture) void {
        const allocator = std.testing.allocator;
        allocator.free(self.root);
        allocator.free(self.config);
        allocator.free(self.base_repomd);
        allocator.free(self.extras_repomd);
        allocator.free(self.base_solv);
        self.tmp.cleanup();
        self.* = undefined;
    }

    fn corruptBaseSolvCookie(self: *Fixture) !void {
        const bytes = try self.tmp.dir.readFileAlloc(
            std.testing.io,
            self.base_solv,
            std.testing.allocator,
            .limited(64 * 1024 * 1024),
        );
        defer std.testing.allocator.free(bytes);
        if (bytes.len < 32) return error.TestUnexpectedResult;
        @memset(bytes[bytes.len - 32 ..], 0);
        const absolute = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/{s}",
            .{ self.root, self.base_solv["root/".len..] },
            0,
        );
        defer std.testing.allocator.free(absolute);
        if (chmod(absolute.ptr, 0o600) != 0) {
            return error.TestUnexpectedResult;
        }
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = self.base_solv,
            .data = bytes,
        });
    }

    fn requireBaseAvailable(self: *Fixture) !void {
        const bytes = try self.tmp.dir.readFileAlloc(
            std.testing.io,
            "root/repos/base.repo",
            std.testing.allocator,
            .limited(1024 * 1024),
        );
        defer std.testing.allocator.free(bytes);
        const setting = "skip_if_unavailable=1";
        const offset = std.mem.indexOf(u8, bytes, setting) orelse
            return error.TestUnexpectedResult;
        bytes[offset + setting.len - 1] = '0';
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "root/repos/base.repo",
            .data = bytes,
        });
    }

    fn advertiseOversizedPrimary(self: *Fixture) !void {
        const bytes = try self.tmp.dir.readFileAlloc(
            std.testing.io,
            self.base_repomd,
            std.testing.allocator,
            .limited(1024 * 1024),
        );
        defer std.testing.allocator.free(bytes);
        const marker = "<open-size>";
        const start = (std.mem.indexOf(u8, bytes, marker) orelse
            return error.TestUnexpectedResult) + marker.len;
        const end = std.mem.indexOfPos(u8, bytes, start, "</open-size>") orelse
            return error.TestUnexpectedResult;
        const advertised = "268435457";
        const output = try std.testing.allocator.alloc(
            u8,
            start + advertised.len + bytes.len - end,
        );
        defer std.testing.allocator.free(output);
        @memcpy(output[0..start], bytes[0..start]);
        @memcpy(output[start .. start + advertised.len], advertised);
        @memcpy(output[start + advertised.len ..], bytes[end..]);
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = self.base_repomd,
            .data = output,
        });
        self.tmp.dir.deleteFile(std.testing.io, self.base_solv) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    fn enableFilteredUpdate(self: *Fixture) !void {
        const allocator = std.testing.allocator;
        const repodata_dir = std.fs.path.dirname(self.base_repomd) orelse
            return error.TestUnexpectedResult;
        const primary_relative = try std.fmt.allocPrint(
            allocator,
            "{s}/primary.xml",
            .{repodata_dir},
        );
        defer allocator.free(primary_relative);
        const updateinfo_relative = try std.fmt.allocPrint(
            allocator,
            "{s}/updateinfo.xml",
            .{repodata_dir},
        );
        defer allocator.free(updateinfo_relative);
        const primary_digest = digestHex(filtered_update_primary_xml);
        const updateinfo_digest = digestHex(filtered_updateinfo_xml);
        const repomd = try std.fmt.allocPrint(
            allocator,
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
            \\  <revision>handle-filtered-update</revision>
            \\  <data type="primary">
            \\    <checksum type="sha256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/primary.xml"/>
            \\    <timestamp>126</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\  <data type="updateinfo">
            \\    <checksum type="sha256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/updateinfo.xml"/>
            \\    <timestamp>127</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\</repomd>
        ,
            .{
                &primary_digest,
                &primary_digest,
                filtered_update_primary_xml.len,
                filtered_update_primary_xml.len,
                &updateinfo_digest,
                &updateinfo_digest,
                filtered_updateinfo_xml.len,
                filtered_updateinfo_xml.len,
            },
        );
        defer allocator.free(repomd);
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = primary_relative,
            .data = filtered_update_primary_xml,
        });
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = updateinfo_relative,
            .data = filtered_updateinfo_xml,
        });
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = self.base_repomd,
            .data = repomd,
        });
        self.tmp.dir.deleteFile(std.testing.io, self.base_solv) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    fn enableBaseSnapshot(self: *Fixture) !void {
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "root/base.snapshot",
            .data = "app=1-1\n",
        });
        const bytes = try self.tmp.dir.readFileAlloc(
            std.testing.io,
            "root/repos/base.repo",
            std.testing.allocator,
            .limited(1024 * 1024),
        );
        defer std.testing.allocator.free(bytes);
        const marker = "metadata_expire=-1\n";
        const offset = (std.mem.indexOf(u8, bytes, marker) orelse
            return error.TestUnexpectedResult) + marker.len;
        const snapshot = try std.fmt.allocPrint(
            std.testing.allocator,
            "snapshot={s}/base.snapshot\n",
            .{self.root},
        );
        defer std.testing.allocator.free(snapshot);
        const output = try std.testing.allocator.alloc(
            u8,
            bytes.len + snapshot.len,
        );
        defer std.testing.allocator.free(output);
        @memcpy(output[0..offset], bytes[0..offset]);
        @memcpy(output[offset .. offset + snapshot.len], snapshot);
        @memcpy(output[offset + snapshot.len ..], bytes[offset..]);
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "root/repos/base.repo",
            .data = output,
        });
    }

    fn useCmdlineDisplayName(self: *Fixture) !void {
        const bytes = try self.tmp.dir.readFileAlloc(
            std.testing.io,
            "root/repos/base.repo",
            std.testing.allocator,
            .limited(1024 * 1024),
        );
        defer std.testing.allocator.free(bytes);
        const old_name = "name=Extras";
        const offset = std.mem.indexOf(u8, bytes, old_name) orelse
            return error.TestUnexpectedResult;
        const new_name = "name=@cmdline";
        const output = try std.testing.allocator.alloc(
            u8,
            bytes.len - old_name.len + new_name.len,
        );
        defer std.testing.allocator.free(output);
        @memcpy(output[0..offset], bytes[0..offset]);
        @memcpy(output[offset .. offset + new_name.len], new_name);
        @memcpy(
            output[offset + new_name.len ..],
            bytes[offset + old_name.len ..],
        );
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "root/repos/base.repo",
            .data = output,
        });
    }
};

fn digestHex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var output: [64]u8 = undefined;
    const alphabet = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        output[index * 2] = alphabet[byte >> 4];
        output[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return output;
}

fn resolve(handle: ?*anyopaque) !void {
    var solved: ?*anyopaque = null;
    const result = TDNFResolve(handle, alter_upgrade_all, &solved);
    try std.testing.expectEqual(@as(u32, 0), result);
    defer TDNFFreeSolvedPackageInfo(solved);
    try std.testing.expect(solved != null);
}

test "repo init failures leave pool indexes queryable" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("installed-file-provider")),
        null,
    };
    var args = CmdArgs{};
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 2;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));

    TDNFTransactionPlanTestFailNextReload(handle, 3);
    try std.testing.expectEqual(
        error_out_of_memory,
        TDNFTransactionPlanTestPublicInitRepo(handle),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPoolIndexesHealthy(handle),
    );

    TDNFTransactionPlanTestFailNextReload(handle, 3);
    try std.testing.expectEqual(
        error_out_of_memory,
        TDNFRefresh(handle),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPoolIndexesHealthy(handle),
    );
}

test "targeted repository reload is atomic and does not duplicate packages" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.enableBaseSnapshot();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    var args = CmdArgs{};
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    try resolve(handle);
    const baseline_json = try capturedJson(handle);
    defer std.testing.allocator.free(baseline_json);

    const baseline_packages =
        TDNFTransactionPlanTestRepoPackageCount(handle, "base");
    try std.testing.expectEqual(@as(u32, 3), baseline_packages);
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoBindingCount(handle, "base"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordCount(handle, "base"),
    );
    const baseline_repositories =
        TDNFTransactionPlanTestPoolRepoCount(handle);
    const baseline_solvables =
        TDNFTransactionPlanTestPoolSolvableCount(handle);
    const baseline_considered =
        TDNFTransactionPlanTestConsideredCount(handle);
    const baseline_repo_id =
        TDNFTransactionPlanTestRepoId(handle, "base");
    var baseline_extras_digest: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordDigest(
            handle,
            "extras",
            &baseline_extras_digest,
        ),
    );
    for (1..8) |stage| {
        const prior_solvables =
            TDNFTransactionPlanTestPoolSolvableCount(handle);
        const prior_repodata =
            TDNFTransactionPlanTestRepoDataCount(handle);
        const prior_considered =
            TDNFTransactionPlanTestConsideredCount(handle);
        const prior_considered_identity =
            TDNFTransactionPlanTestConsideredIdentity(handle);
        const prior_identity =
            TDNFTransactionPlanTestRepoIdentity(handle, "base");
        const prior_repo_id =
            TDNFTransactionPlanTestRepoId(handle, "base");
        TDNFTransactionPlanTestFailNextReload(handle, @intCast(stage));
        try std.testing.expectEqual(
            error_out_of_memory,
            TDNFTransactionPlanTestReloadRepo(handle, "base"),
        );
        try std.testing.expectEqual(
            prior_solvables,
            TDNFTransactionPlanTestPoolSolvableCount(handle),
        );
        try std.testing.expectEqual(
            prior_repodata,
            TDNFTransactionPlanTestRepoDataCount(handle),
        );
        try std.testing.expectEqual(
            prior_considered,
            TDNFTransactionPlanTestConsideredCount(handle),
        );
        try std.testing.expectEqual(
            prior_considered_identity,
            TDNFTransactionPlanTestConsideredIdentity(handle),
        );
        try std.testing.expectEqual(
            prior_identity,
            TDNFTransactionPlanTestRepoIdentity(handle, "base"),
        );
        try std.testing.expectEqual(
            prior_repo_id,
            TDNFTransactionPlanTestRepoId(handle, "base"),
        );
        try std.testing.expectEqual(
            baseline_packages,
            TDNFTransactionPlanTestRepoPackageCount(handle, "base"),
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestRepoBindingCount(handle, "base"),
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestRepoRecordCount(handle, "base"),
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestPoolIndexesHealthy(handle),
        );
        try resolve(handle);
        const after_failure = try capturedJson(handle);
        defer std.testing.allocator.free(after_failure);
        try std.testing.expectEqualStrings(baseline_json, after_failure);
    }

    const record_failure_solvables =
        TDNFTransactionPlanTestPoolSolvableCount(handle);
    const record_failure_repodata =
        TDNFTransactionPlanTestRepoDataCount(handle);
    const record_failure_considered =
        TDNFTransactionPlanTestConsideredCount(handle);
    const record_failure_considered_identity =
        TDNFTransactionPlanTestConsideredIdentity(handle);
    const record_failure_identity =
        TDNFTransactionPlanTestRepoIdentity(handle, "base");
    const record_failure_repo_id =
        TDNFTransactionPlanTestRepoId(handle, "base");
    TDNFTransactionPlanCaptureFailNextRepositoryRecord(handle);
    try std.testing.expectEqual(
        error_out_of_memory,
        TDNFTransactionPlanTestReloadRepo(handle, "base"),
    );
    try std.testing.expectEqual(
        record_failure_solvables,
        TDNFTransactionPlanTestPoolSolvableCount(handle),
    );
    try std.testing.expectEqual(
        record_failure_repodata,
        TDNFTransactionPlanTestRepoDataCount(handle),
    );
    try std.testing.expectEqual(
        record_failure_considered,
        TDNFTransactionPlanTestConsideredCount(handle),
    );
    try std.testing.expectEqual(
        record_failure_considered_identity,
        TDNFTransactionPlanTestConsideredIdentity(handle),
    );
    try std.testing.expectEqual(
        record_failure_identity,
        TDNFTransactionPlanTestRepoIdentity(handle, "base"),
    );
    try std.testing.expectEqual(
        record_failure_repo_id,
        TDNFTransactionPlanTestRepoId(handle, "base"),
    );
    try std.testing.expectEqual(
        baseline_packages,
        TDNFTransactionPlanTestRepoPackageCount(handle, "base"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordCount(handle, "base"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPoolIndexesHealthy(handle),
    );

    const extras_repomd = try fixture.tmp.dir.readFileAlloc(
        std.testing.io,
        fixture.extras_repomd,
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(extras_repomd);
    try fixture.tmp.dir.deleteFile(
        std.testing.io,
        fixture.extras_repomd,
    );

    for (0..32) |_| {
        const prior_identity =
            TDNFTransactionPlanTestRepoIdentity(handle, "base");
        try std.testing.expectEqual(
            @as(u32, 0),
            TDNFTransactionPlanTestReloadRepo(handle, "base"),
        );
        try std.testing.expect(
            prior_identity !=
                TDNFTransactionPlanTestRepoIdentity(handle, "base"),
        );
        try std.testing.expectEqual(
            baseline_repo_id,
            TDNFTransactionPlanTestRepoId(handle, "base"),
        );
        try std.testing.expectEqual(
            baseline_repositories,
            TDNFTransactionPlanTestPoolRepoCount(handle),
        );
        try std.testing.expectEqual(
            baseline_solvables,
            TDNFTransactionPlanTestPoolSolvableCount(handle),
        );
        try std.testing.expectEqual(
            baseline_packages,
            TDNFTransactionPlanTestRepoPackageCount(handle, "base"),
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestRepoBindingCount(handle, "base"),
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestRepoRecordCount(handle, "base"),
        );
        try std.testing.expectEqual(
            baseline_considered,
            TDNFTransactionPlanTestConsideredCount(handle),
        );
        try std.testing.expectEqual(
            @as(u32, 2),
            TDNFTransactionPlanTestRepoPackageCount(handle, "extras"),
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestRepoBindingCount(handle, "extras"),
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestRepoRecordCount(handle, "extras"),
        );
        var extras_digest: [32]u8 = undefined;
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestRepoRecordDigest(
                handle,
                "extras",
                &extras_digest,
            ),
        );
        try std.testing.expectEqualSlices(
            u8,
            &baseline_extras_digest,
            &extras_digest,
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestPoolIndexesHealthy(handle),
        );
    }
    const extras_dir = std.fs.path.dirname(fixture.extras_repomd) orelse
        return error.TestUnexpectedResult;
    try fixture.tmp.dir.createDirPath(std.testing.io, extras_dir);
    try fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = fixture.extras_repomd,
        .data = extras_repomd,
    });
    try resolve(handle);
    const after_success = try capturedJson(handle);
    defer std.testing.allocator.free(after_success);
    try std.testing.expectEqualStrings(baseline_json, after_success);
}

test "repository load failure preserves live sack until successful swap" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.requireBaseAvailable();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    var args = CmdArgs{};
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;

    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));

    const repomd = try fixture.tmp.dir.readFileAlloc(
        std.testing.io,
        fixture.base_repomd,
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(repomd);
    const repodata_dir = std.fs.path.dirname(fixture.base_repomd) orelse
        return error.TestUnexpectedResult;
    const primary_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/primary.xml",
        .{repodata_dir},
    );
    defer std.testing.allocator.free(primary_path);
    const primary = try fixture.tmp.dir.readFileAlloc(
        std.testing.io,
        primary_path,
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(primary);

    const prior_pool = TDNFTransactionPlanTestPoolIdentity(handle);
    const prior_solvables =
        TDNFTransactionPlanTestPoolSolvableCount(handle);
    const prior_repodata =
        TDNFTransactionPlanTestRepoDataCount(handle);
    const prior_considered =
        TDNFTransactionPlanTestConsideredCount(handle);
    try fixture.tmp.dir.deleteFile(std.testing.io, fixture.base_repomd);
    try std.testing.expectEqual(
        error_cache_disabled,
        TDNFRefresh(handle),
    );
    try std.testing.expectEqual(
        prior_pool,
        TDNFTransactionPlanTestPoolIdentity(handle),
    );
    try std.testing.expectEqual(
        prior_solvables,
        TDNFTransactionPlanTestPoolSolvableCount(handle),
    );
    try std.testing.expectEqual(
        prior_repodata,
        TDNFTransactionPlanTestRepoDataCount(handle),
    );
    try std.testing.expectEqual(
        prior_considered,
        TDNFTransactionPlanTestConsideredCount(handle),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPoolIndexesHealthy(handle),
    );

    try fixture.tmp.dir.createDirPath(std.testing.io, repodata_dir);
    try fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = fixture.base_repomd,
        .data = repomd,
    });
    try fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = primary_path,
        .data = primary,
    });
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    try std.testing.expect(
        prior_pool != TDNFTransactionPlanTestPoolIdentity(handle),
    );
    try std.testing.expectEqual(
        prior_solvables,
        TDNFTransactionPlanTestPoolSolvableCount(handle),
    );
    try std.testing.expectEqual(
        prior_considered,
        TDNFTransactionPlanTestConsideredCount(handle),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPoolIndexesHealthy(handle),
    );
}

test "configured special repository names are rejected" {
    for ([_][]const u8{ "@System", "@cmdline" }) |name| {
        var fixture = try Fixture.create();
        defer fixture.destroy();
        const config = try std.fmt.allocPrint(
            std.testing.allocator,
            "[{s}]\nname=Collision\nbaseurl=file:///nonexistent\nenabled=1\n",
            .{name},
        );
        defer std.testing.allocator.free(config);
        try fixture.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "root/repos/collision.repo",
            .data = config,
        });
        const setopts = create_cnfnode("(setopts)") orelse
            return error.OutOfMemory;
        defer destroy_cnftree(setopts);
        const repoopts = create_cnfnode("(repoopts)") orelse
            return error.OutOfMemory;
        defer destroy_cnftree(repoopts);
        var args = CmdArgs{};
        args.pszInstallRoot = fixture.root.ptr;
        args.pszConfFile = fixture.config.ptr;
        args.pszReleaseVer = @ptrCast(@constCast("1"));
        args.cn_setopts = setopts;
        args.cn_repoopts = repoopts;
        var handle: ?*anyopaque = null;
        try std.testing.expectEqual(
            error_invalid_parameter,
            TDNFOpenHandle(&args, &handle),
        );
        try std.testing.expect(handle == null);
    }
}

test "cmdline display name does not make a normal repository synthetic" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.useCmdlineDisplayName();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    var args = CmdArgs{};
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    try std.testing.expectEqual(
        @as(u32, 2),
        TDNFTransactionPlanTestRepoPackageCount(handle, "extras"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoBindingCount(handle, "extras"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPoolIndexesHealthy(handle),
    );
    try resolve(handle);
    const captured = try capturedJson(handle);
    defer std.testing.allocator.free(captured);
    try std.testing.expect(std.mem.indexOf(
        u8,
        captured,
        "\"id\":\"extras\"",
    ) != null);
}

fn capturedJson(handle: ?*anyopaque) ![]u8 {
    var raw: ?[*]const u8 = null;
    var length: usize = 0;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureGetCanonicalJson(
            handle,
            &raw,
            &length,
        ),
    );
    const json = try std.testing.allocator.dupe(u8, raw.?[0..length]);
    TDNFTransactionPlanStateFreeCanonicalJson(raw, length);
    return json;
}

fn appendFilterSetopts(setopts: ?*anyopaque, filters: u8) !void {
    if (filters & filter_security != 0) {
        const security = create_cnfnode("security") orelse
            return error.OutOfMemory;
        append_node(setopts, security);
    }
    if (filters & filter_severity != 0) {
        const severity = create_cnfnode("sec-severity") orelse
            return error.OutOfMemory;
        cnfnode_setval(severity, "7.0");
        append_node(setopts, severity);
    }
    if (filters & filter_reboot_required != 0) {
        const reboot = create_cnfnode("reboot-required") orelse
            return error.OutOfMemory;
        append_node(setopts, reboot);
    }
}

fn expectUnfilteredUpdateAllPlan(handle: ?*anyopaque) !void {
    var solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_upgrade_all, &solved),
    );
    defer TDNFFreeSolvedPackageInfo(solved);
    try std.testing.expect(solved != null);
    const json = try capturedJson(handle);
    defer std.testing.allocator.free(json);
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();
    const object = parsed.value.object;
    const requests = object.get("requests").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), requests.len);
    const request = requests[0].object;
    try std.testing.expectEqualStrings(
        "update_all",
        request.get("kind").?.string,
    );
    try std.testing.expect(request.get("subject").? == .null);
    const request_id = request.get("id").?.string;
    const jobs = object.get("jobs").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), jobs.len);
    const job = jobs[0].object;
    try std.testing.expectEqualStrings(
        "update",
        job.get("action").?.string,
    );
    try std.testing.expectEqualStrings(
        request_id,
        job.get("request_id").?.string,
    );
    try std.testing.expectEqualStrings(
        "all",
        job.get("selection").?.object.get("kind").?.string,
    );
}

fn expectNoCapturedPlan(handle: ?*anyopaque) !void {
    var raw: ?[*]const u8 = null;
    var length: usize = 0;
    try std.testing.expect(TDNFTransactionPlanCaptureGetCanonicalJson(
        handle,
        &raw,
        &length,
    ) != 0);
    try std.testing.expect(raw == null);
    try std.testing.expectEqual(@as(usize, 0), length);
}

fn runFilteredUpdateAllCase(filters: u8) !void {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.enableFilteredUpdate();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    var args = CmdArgs{};
    args.nAssumeYes = 1;
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;

    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    var handle_live = true;
    defer if (handle_live) TDNFCloseHandle(handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    try expectUnfilteredUpdateAllPlan(handle);

    const pool_identity = TDNFTransactionPlanTestPoolIdentity(handle);
    const solvable_count =
        TDNFTransactionPlanTestPoolSolvableCount(handle);
    const repodata_count =
        TDNFTransactionPlanTestRepoDataCount(handle);
    const considered_identity =
        TDNFTransactionPlanTestConsideredIdentity(handle);
    const considered_count =
        TDNFTransactionPlanTestConsideredCount(handle);
    const base_identity =
        TDNFTransactionPlanTestRepoIdentity(handle, "base");
    const extras_identity =
        TDNFTransactionPlanTestRepoIdentity(handle, "extras");
    try appendFilterSetopts(setopts, filters);

    var unsupported: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_call_not_supported,
        TDNFResolve(handle, alter_upgrade_all, &unsupported),
    );
    try std.testing.expect(unsupported == null);
    try std.testing.expectEqual(
        pool_identity,
        TDNFTransactionPlanTestPoolIdentity(handle),
    );
    try std.testing.expectEqual(
        solvable_count,
        TDNFTransactionPlanTestPoolSolvableCount(handle),
    );
    try std.testing.expectEqual(
        repodata_count,
        TDNFTransactionPlanTestRepoDataCount(handle),
    );
    try std.testing.expectEqual(
        considered_identity,
        TDNFTransactionPlanTestConsideredIdentity(handle),
    );
    try std.testing.expectEqual(
        considered_count,
        TDNFTransactionPlanTestConsideredCount(handle),
    );
    try std.testing.expectEqual(
        base_identity,
        TDNFTransactionPlanTestRepoIdentity(handle, "base"),
    );
    try std.testing.expectEqual(
        extras_identity,
        TDNFTransactionPlanTestRepoIdentity(handle, "extras"),
    );
    try expectNoCapturedPlan(handle);

    TDNFCloseHandle(handle);
    handle = null;
    handle_live = false;
    var compatibility_handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &compatibility_handle),
    );
    defer TDNFCloseHandle(compatibility_handle);
    var filtered: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(
            compatibility_handle,
            alter_upgrade_all,
            &filtered,
        ),
    );
    defer TDNFFreeSolvedPackageInfo(filtered);
    try std.testing.expect(filtered != null);
    try expectNoCapturedPlan(compatibility_handle);
}

test "filtered update-all is capture-only unsupported before refresh" {
    try runFilteredUpdateAllCase(filter_security);
    try runFilteredUpdateAllCase(filter_severity);
    try runFilteredUpdateAllCase(filter_reboot_required);
    try runFilteredUpdateAllCase(
        filter_security | filter_severity | filter_reboot_required,
    );
}

test "private handle capture follows production resolve lifecycle" {
    try std.testing.expectEqual(
        @as(u32, 1622),
        TDNFInitRepoFromMetadata(null, null, null),
    );
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const duplicate_exclude = create_cnfnode("excludepkgs") orelse
        return error.OutOfMemory;
    cnfnode_setval(duplicate_exclude, "excluded");
    append_node(setopts, duplicate_exclude);
    const enable_all = create_cnfnode("enablerepo") orelse
        return error.OutOfMemory;
    cnfnode_setval(enable_all, "*");
    append_node(setopts, enable_all);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    const upgrade = try std.testing.allocator.dupeZ(u8, "upgrade");
    defer std.testing.allocator.free(upgrade);
    var commands = [_]?[*:0]u8{ upgrade.ptr, null };
    var args = CmdArgs{};
    args.nAssumeYes = 1;
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;

    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    var handle_live = true;
    defer if (handle_live) TDNFCloseHandle(handle);
    var sack_without_pool = SolvSackView{
        .pool = null,
        .command_package_count = 0,
        .cache_dir = null,
        .root_dir = null,
    };
    try std.testing.expectEqual(
        error_invalid_parameter,
        TDNFRefreshSack(handle, &sack_without_pool, 0),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, null, 0),
    );
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    for (1..6) |stage| {
        const prior_pool = TDNFTransactionPlanTestPoolIdentity(handle);
        const prior_solvables =
            TDNFTransactionPlanTestPoolSolvableCount(handle);
        const prior_repodata =
            TDNFTransactionPlanTestRepoDataCount(handle);
        const prior_considered =
            TDNFTransactionPlanTestConsideredCount(handle);
        TDNFTransactionPlanTestFailNextReload(handle, @intCast(stage));
        try std.testing.expectEqual(
            error_out_of_memory,
            TDNFRefresh(handle),
        );
        try std.testing.expectEqual(
            prior_pool,
            TDNFTransactionPlanTestPoolIdentity(handle),
        );
        try std.testing.expectEqual(
            prior_solvables,
            TDNFTransactionPlanTestPoolSolvableCount(handle),
        );
        try std.testing.expectEqual(
            prior_repodata,
            TDNFTransactionPlanTestRepoDataCount(handle),
        );
        try std.testing.expectEqual(
            prior_considered,
            TDNFTransactionPlanTestConsideredCount(handle),
        );
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestPoolIndexesHealthy(handle),
        );
        try resolve(handle);
    }
    const prior_success_pool = TDNFTransactionPlanTestPoolIdentity(handle);
    const prior_success_count =
        TDNFTransactionPlanTestPoolSolvableCount(handle);
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    try std.testing.expect(
        prior_success_pool != TDNFTransactionPlanTestPoolIdentity(handle),
    );
    try std.testing.expectEqual(
        prior_success_count,
        TDNFTransactionPlanTestPoolSolvableCount(handle),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPublicInitRepo(handle),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestInitRepoValidation(handle),
    );
    const alternate_cache = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/cache",
        .{fixture.root},
        0,
    );
    defer std.testing.allocator.free(alternate_cache);
    var alternate_sack: ?*anyopaque = null;
    defer if (alternate_sack) |sack| SolvFreeSack(sack);
    try std.testing.expectEqual(
        @as(u32, 0),
        SolvInitSack(
            &alternate_sack,
            alternate_cache.ptr,
            fixture.root.ptr,
            "x86_64",
        ),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, alternate_sack, 0),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, null, 0),
    );
    args.nRefresh = 0;
    TDNFTransactionPlanTestFailNextReload(handle, 1);
    try std.testing.expectEqual(
        error_out_of_memory,
        TDNFRefreshSack(handle, null, 1),
    );
    try std.testing.expectEqual(@as(c_int, 0), args.nRefresh);
    SolvFreeSack(alternate_sack);
    alternate_sack = null;
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    try resolve(handle);
    const cache_solvable_count =
        TDNFTransactionPlanTestPoolSolvableCount(handle);
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestGrowCmdlineConsidered(handle),
    );
    try fixture.corruptBaseSolvCookie();
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    try std.testing.expectEqual(
        cache_solvable_count,
        TDNFTransactionPlanTestPoolSolvableCount(handle),
    );
    TDNFTransactionPlanRequestTraceTestFailNextCreate();
    try resolve(handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    TDNFTransactionPlanRequestTraceTestFailNextCreate();
    var trace_create_failure: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_out_of_memory,
        TDNFResolve(
            handle,
            alter_upgrade_all,
            &trace_create_failure,
        ),
    );
    try std.testing.expect(trace_create_failure == null);
    var history_args = HistoryArgs{};
    var history_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFHistoryResolve(handle, &history_args, &history_solved),
    );
    try std.testing.expect(history_solved == null);
    TDNFTransactionPlanRequestTraceTestFailNextRecord();
    var trace_record_failure: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_out_of_memory,
        TDNFResolve(
            handle,
            alter_upgrade_all,
            &trace_record_failure,
        ),
    );
    try std.testing.expect(trace_record_failure == null);
    const record_failure_pool =
        TDNFTransactionPlanTestPoolIdentity(handle);
    const record_failure_solvables =
        TDNFTransactionPlanTestPoolSolvableCount(handle);
    const record_failure_considered =
        TDNFTransactionPlanTestConsideredCount(handle);
    TDNFTransactionPlanCaptureFailNextRepositoryRecord(handle);
    try std.testing.expectEqual(
        error_out_of_memory,
        TDNFRefresh(handle),
    );
    try std.testing.expectEqual(
        record_failure_pool,
        TDNFTransactionPlanTestPoolIdentity(handle),
    );
    try std.testing.expectEqual(
        record_failure_solvables,
        TDNFTransactionPlanTestPoolSolvableCount(handle),
    );
    try std.testing.expectEqual(
        record_failure_considered,
        TDNFTransactionPlanTestConsideredCount(handle),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPoolIndexesHealthy(handle),
    );
    try resolve(handle);
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPoolIndexesHealthy(handle),
    );
    const first = try capturedJson(handle);
    const stable_solvable_count =
        TDNFTransactionPlanTestPoolSolvableCount(handle);
    const stable_repodata_count =
        TDNFTransactionPlanTestRepoDataCount(handle);
    try std.testing.expect(stable_solvable_count != 0);
    try std.testing.expect(stable_repodata_count != 0);
    defer std.testing.allocator.free(first);
    try std.testing.expect(std.mem.indexOf(
        u8,
        first,
        "\"distro\":\"handle-test\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"base\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"extras\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"empty\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "\"excluded\"") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        first,
        "\"installed-file-provider\"",
    ) != null);

    try resolve(handle);
    try std.testing.expectEqual(
        stable_solvable_count,
        TDNFTransactionPlanTestPoolSolvableCount(handle),
    );
    try std.testing.expectEqual(
        stable_repodata_count,
        TDNFTransactionPlanTestRepoDataCount(handle),
    );
    const repeated = try capturedJson(handle);
    defer std.testing.allocator.free(repeated);
    try std.testing.expectEqualStrings(first, repeated);
    for (0..3) |_| {
        try resolve(handle);
        try std.testing.expectEqual(
            stable_solvable_count,
            TDNFTransactionPlanTestPoolSolvableCount(handle),
        );
        try std.testing.expectEqual(
            stable_repodata_count,
            TDNFTransactionPlanTestRepoDataCount(handle),
        );
    }

    inline for (.{
        "builddeps",
        "source",
        "nodeps",
    }) |mode| {
        if (std.mem.eql(u8, mode, "builddeps")) args.nBuildDeps = 1;
        if (std.mem.eql(u8, mode, "source")) args.nSource = 1;
        if (std.mem.eql(u8, mode, "nodeps")) args.nNoDeps = 1;
        var unsupported: ?*anyopaque = null;
        try std.testing.expectEqual(
            error_call_not_supported,
            TDNFResolve(handle, alter_upgrade_all, &unsupported),
        );
        try std.testing.expect(unsupported == null);
        args.nBuildDeps = 0;
        args.nSource = 0;
        args.nNoDeps = 0;
    }
    try resolve(handle);
    var failed: ?*anyopaque = null;
    try std.testing.expect(TDNFResolve(
        handle,
        alter_install,
        &failed,
    ) != 0);
    try std.testing.expect(failed == null);
    var stale: ?[*]const u8 = null;
    var stale_length: usize = 0;
    try std.testing.expect(TDNFTransactionPlanCaptureGetCanonicalJson(
        handle,
        &stale,
        &stale_length,
    ) != 0);
    try std.testing.expect(stale == null);
    try std.testing.expectEqual(@as(usize, 0), stale_length);

    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 0),
    );
    try resolve(handle);
    try std.testing.expect(TDNFTransactionPlanCaptureGetCanonicalJson(
        handle,
        &stale,
        &stale_length,
    ) != 0);

    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    try resolve(handle);
    var mixed_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("app")),
        @ptrCast(@constCast(
            "https://user:pass@repo.invalid/token%253Dsecret/missing",
        )),
        null,
    };
    args.ppszCmds = &mixed_commands;
    args.nCmdCount = 3;
    args.nSkipBroken = 1;
    var mixed_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_install, &mixed_solved),
    );
    defer TDNFFreeSolvedPackageInfo(mixed_solved);
    const mixed_json = try capturedJson(handle);
    defer std.testing.allocator.free(mixed_json);
    var mixed_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        mixed_json,
        .{},
    );
    defer mixed_plan.deinit();
    const mixed_object = mixed_plan.value.object;
    try std.testing.expectEqualStrings(
        "resolved_with_skips",
        mixed_object.get("environment").?.object
            .get("resolution_status").?.string,
    );
    try std.testing.expect(mixed_object.get("actions").?.array.items.len != 0);
    try std.testing.expectEqual(
        @as(usize, 1),
        mixed_object.get("skipped").?.array.items.len,
    );
    const mixed_problem =
        mixed_object.get("problems").?.array.items[0].object;
    const missing_job_id = mixed_problem.get("job_id").?.string;
    const missing_job = for (mixed_object.get("jobs").?.array.items) |job| {
        if (std.mem.eql(
            u8,
            missing_job_id,
            job.object.get("id").?.string,
        )) break job.object;
    } else return error.TestUnexpectedResult;
    const missing_request_id = missing_job.get("request_id").?.string;
    const missing_request = for (
        mixed_object.get("requests").?.array.items,
    ) |request| {
        if (std.mem.eql(
            u8,
            missing_request_id,
            request.object.get("id").?.string,
        )) break request.object;
    } else return error.TestUnexpectedResult;
    try std.testing.expect(missing_request.get("subject").? == .null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        mixed_json,
        "repo.invalid",
    ) == null);
    args.nSkipBroken = 0;

    var satisfied_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("app")),
        @ptrCast(@constCast("installed-file-provider")),
        null,
    };
    args.ppszCmds = &satisfied_commands;
    var satisfied_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_install, &satisfied_solved),
    );
    defer TDNFFreeSolvedPackageInfo(satisfied_solved);
    const satisfied_json = try capturedJson(handle);
    defer std.testing.allocator.free(satisfied_json);
    var satisfied_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        satisfied_json,
        .{},
    );
    defer satisfied_plan.deinit();
    const satisfied_object = satisfied_plan.value.object;
    try std.testing.expectEqualStrings(
        "resolved",
        satisfied_object.get("environment").?.object
            .get("resolution_status").?.string,
    );
    try std.testing.expect(
        satisfied_object.get("actions").?.array.items.len != 0,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        satisfied_object.get("requests").?.array.items.len,
    );
    const noop_request_id = for (
        satisfied_object.get("requests").?.array.items,
    ) |request| {
        if (std.mem.eql(
            u8,
            "installed-file-provider",
            request.object.get("subject").?.string,
        )) break request.object.get("id").?.string;
    } else return error.TestUnexpectedResult;
    const noop_job_id = for (
        satisfied_object.get("jobs").?.array.items,
    ) |job| {
        const request_id = job.object.get("request_id") orelse continue;
        if (std.mem.eql(u8, noop_request_id, request_id.string))
            break job.object.get("id").?.string;
    } else return error.TestUnexpectedResult;
    for (satisfied_object.get("actions").?.array.items) |action| {
        const requested_by = action.object.get("requested_by_job_id") orelse
            continue;
        try std.testing.expect(!std.mem.eql(
            u8,
            noop_job_id,
            requested_by.string,
        ));
    }

    var noop_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("installed-file-provider")),
        null,
    };
    args.ppszCmds = &noop_commands;
    args.nCmdCount = 2;
    var noop_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_install, &noop_solved),
    );
    defer TDNFFreeSolvedPackageInfo(noop_solved);
    const noop_json = try capturedJson(handle);
    defer std.testing.allocator.free(noop_json);
    var noop_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        noop_json,
        .{},
    );
    defer noop_plan.deinit();
    const noop_object = noop_plan.value.object;
    try std.testing.expectEqualStrings(
        "resolved",
        noop_object.get("environment").?.object
            .get("resolution_status").?.string,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        noop_object.get("actions").?.array.items.len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        noop_object.get("jobs").?.array.items.len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        noop_object.get("problems").?.array.items.len,
    );
    try std.testing.expectEqualStrings(
        "installed-file-provider",
        noop_object.get("requests").?.array.items[0]
            .object.get("subject").?.string,
    );

    var missing_rpm_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("missing-bare.rpm")),
        null,
    };
    args.ppszCmds = &missing_rpm_commands;
    args.nCmdCount = 2;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 0),
    );
    var missing_disabled: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_already_installed,
        TDNFResolve(handle, alter_install, &missing_disabled),
    );
    try std.testing.expect(missing_disabled == null);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    args.nSkipBroken = 1;
    var missing_rpm_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_install, &missing_rpm_solved),
    );
    defer TDNFFreeSolvedPackageInfo(missing_rpm_solved);
    const missing_rpm_json = try capturedJson(handle);
    defer std.testing.allocator.free(missing_rpm_json);
    var missing_rpm_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        missing_rpm_json,
        .{},
    );
    defer missing_rpm_plan.deinit();
    const missing_rpm_object = missing_rpm_plan.value.object;
    try std.testing.expectEqualStrings(
        "resolved_with_skips",
        missing_rpm_object.get("environment").?.object
            .get("resolution_status").?.string,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        missing_rpm_object.get("actions").?.array.items.len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        missing_rpm_object.get("problems").?.array.items.len,
    );
    try std.testing.expectEqualStrings(
        "no_candidate",
        missing_rpm_object.get("problems").?.array.items[0]
            .object.get("kind").?.string,
    );
    try std.testing.expect(
        missing_rpm_object.get("requests").?.array.items[0]
            .object.get("subject").? == .null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, missing_rpm_json, "missing-bare") == null,
    );

    var mixed_rpm_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("app")),
        @ptrCast(@constCast("missing-mixed.rpm")),
        null,
    };
    args.ppszCmds = &mixed_rpm_commands;
    args.nCmdCount = 3;
    var mixed_rpm_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_install, &mixed_rpm_solved),
    );
    defer TDNFFreeSolvedPackageInfo(mixed_rpm_solved);
    const mixed_rpm_json = try capturedJson(handle);
    defer std.testing.allocator.free(mixed_rpm_json);
    var mixed_rpm_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        mixed_rpm_json,
        .{},
    );
    defer mixed_rpm_plan.deinit();
    const mixed_rpm_object = mixed_rpm_plan.value.object;
    try std.testing.expectEqualStrings(
        "resolved_with_skips",
        mixed_rpm_object.get("environment").?.object
            .get("resolution_status").?.string,
    );
    try std.testing.expect(
        mixed_rpm_object.get("actions").?.array.items.len != 0,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        mixed_rpm_object.get("problems").?.array.items.len,
    );
    args.nSkipBroken = 0;

    var excluded_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("excluded")),
        null,
    };
    args.ppszCmds = &excluded_commands;
    args.nCmdCount = 2;
    var excluded_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_install, &excluded_solved),
    );
    defer TDNFFreeSolvedPackageInfo(excluded_solved);
    const excluded_json = try capturedJson(handle);
    defer std.testing.allocator.free(excluded_json);
    var excluded_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        excluded_json,
        .{},
    );
    defer excluded_plan.deinit();
    const excluded_object = excluded_plan.value.object;
    try std.testing.expectEqual(
        @as(usize, 0),
        excluded_object.get("actions").?.array.items.len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        excluded_object.get("jobs").?.array.items.len,
    );

    var mixed_excluded_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("excluded")),
        @ptrCast(@constCast("app")),
        null,
    };
    args.ppszCmds = &mixed_excluded_commands;
    args.nCmdCount = 3;
    var mixed_excluded_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(
            handle,
            alter_install,
            &mixed_excluded_solved,
        ),
    );
    defer TDNFFreeSolvedPackageInfo(mixed_excluded_solved);
    const mixed_excluded_json = try capturedJson(handle);
    defer std.testing.allocator.free(mixed_excluded_json);
    var mixed_excluded_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        mixed_excluded_json,
        .{},
    );
    defer mixed_excluded_plan.deinit();
    const mixed_excluded_object = mixed_excluded_plan.value.object;
    try std.testing.expectEqual(
        @as(usize, 1),
        mixed_excluded_object.get("actions").?.array.items.len,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        mixed_excluded_object.get("jobs").?.array.items.len,
    );
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    const history_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/persist/history.db",
        .{fixture.root},
        0,
    );
    defer std.testing.allocator.free(history_path);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteHistoryFixture(history_path.ptr),
    );
    const fixture_history = create_history_ctx(history_path.ptr) orelse
        return error.TestUnexpectedResult;
    const fixture_delta = history_get_delta_range(
        fixture_history,
        2,
        1,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(c_int, 3), fixture_delta.added_count);
    history_free_delta(fixture_delta);
    destroy_history_ctx(fixture_history);
    var rollback_args = HistoryArgs{ .command = 4, .from = 2, .to = 2 };
    var rollback_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFHistoryResolve(handle, &rollback_args, &rollback_solved),
    );
    defer TDNFFreeSolvedPackageInfo(rollback_solved);
    try std.testing.expect(rollback_solved != null);
    const history_json = try capturedJson(handle);
    defer std.testing.allocator.free(history_json);
    var history_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        history_json,
        .{},
    );
    defer history_plan.deinit();
    const history_object = history_plan.value.object;
    try std.testing.expectEqualStrings(
        "resolved_with_skips",
        history_object.get("environment").?.object
            .get("resolution_status").?.string,
    );
    try std.testing.expect(
        history_object.get("actions").?.array.items.len != 0,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        history_object.get("skipped").?.array.items.len,
    );
    try std.testing.expectEqual(
        @as(usize, 5),
        history_object.get("requests").?.array.items.len,
    );
    const history_problem =
        history_object.get("problems").?.array.items[0].object;
    try std.testing.expectEqualStrings(
        "no_candidate",
        history_problem.get("kind").?.string,
    );
    const unresolved_job_id = history_problem.get("job_id").?.string;
    const unresolved_job = for (
        history_object.get("jobs").?.array.items,
    ) |job| {
        if (std.mem.eql(
            u8,
            unresolved_job_id,
            job.object.get("id").?.string,
        )) break job.object;
    } else return error.TestUnexpectedResult;
    const unresolved_request_id =
        unresolved_job.get("request_id").?.string;
    const unresolved_request = for (
        history_object.get("requests").?.array.items,
    ) |request| {
        if (std.mem.eql(
            u8,
            unresolved_request_id,
            request.object.get("id").?.string,
        )) break request.object;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        "missing-history-1-1.x86_64",
        unresolved_request.get("subject").?.string,
    );
    var resolved_request_id: ?[]const u8 = null;
    for (history_object.get("requests").?.array.items) |request| {
        if (std.mem.eql(
            u8,
            "app-1-1.x86_64",
            request.object.get("subject").?.string,
        )) resolved_request_id = request.object.get("id").?.string;
    }
    try std.testing.expect(resolved_request_id != null);
    var saw_resolved_job = false;
    for (history_object.get("jobs").?.array.items) |job| {
        const request_id = job.object.get("request_id") orelse continue;
        if (std.mem.eql(
            u8,
            resolved_request_id.?,
            request_id.string,
        )) saw_resolved_job = true;
    }
    try std.testing.expect(saw_resolved_job);
    const absent_request_id = for (
        history_object.get("requests").?.array.items,
    ) |request| {
        if (std.mem.eql(
            u8,
            "absent-history-1-1.x86_64",
            request.object.get("subject").?.string,
        )) break request.object.get("id").?.string;
    } else return error.TestUnexpectedResult;
    var absent_noop_job_id: ?[]const u8 = null;
    for (history_object.get("jobs").?.array.items) |job| {
        const request_id = job.object.get("request_id") orelse continue;
        if (std.mem.eql(u8, absent_request_id, request_id.string))
            absent_noop_job_id = job.object.get("id").?.string;
    }
    try std.testing.expect(absent_noop_job_id != null);
    const excluded_request_id = for (
        history_object.get("requests").?.array.items,
    ) |request| {
        if (std.mem.eql(
            u8,
            "excluded-1-1.x86_64",
            request.object.get("subject").?.string,
        )) break request.object.get("id").?.string;
    } else return error.TestUnexpectedResult;
    const excluded_noop_job_id = for (
        history_object.get("jobs").?.array.items,
    ) |job| {
        const request_id = job.object.get("request_id") orelse continue;
        if (std.mem.eql(u8, excluded_request_id, request_id.string))
            break job.object.get("id").?.string;
    } else return error.TestUnexpectedResult;
    var saw_history_app = false;
    var saw_history_provider = false;
    for (history_object.get("actions").?.array.items) |action| {
        if (action.object.get("requested_by_job_id")) |requested_by| {
            try std.testing.expect(!std.mem.eql(
                u8,
                absent_noop_job_id.?,
                requested_by.string,
            ));
            try std.testing.expect(!std.mem.eql(
                u8,
                excluded_noop_job_id,
                requested_by.string,
            ));
        }
        const target_id =
            action.object.get("target_package_id").?.string;
        const target = for (
            history_object.get("packages").?.array.items,
        ) |package| {
            if (std.mem.eql(
                u8,
                target_id,
                package.object.get("id").?.string,
            )) break package.object;
        } else return error.TestUnexpectedResult;
        const name = target.get("identity").?.object.get("name").?.string;
        if (std.mem.eql(u8, name, "app")) saw_history_app = true;
        if (std.mem.eql(u8, name, "installed-file-provider"))
            saw_history_provider = true;
    }
    try std.testing.expect(saw_history_app);
    try std.testing.expect(saw_history_provider);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteExcludedHistoryFixture(
            history_path.ptr,
        ),
    );
    var excluded_history_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFHistoryResolve(
            handle,
            &rollback_args,
            &excluded_history_solved,
        ),
    );
    defer TDNFFreeSolvedPackageInfo(excluded_history_solved);
    const excluded_history_json = try capturedJson(handle);
    defer std.testing.allocator.free(excluded_history_json);
    var excluded_history_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        excluded_history_json,
        .{},
    );
    defer excluded_history_plan.deinit();
    const excluded_history_object = excluded_history_plan.value.object;
    try std.testing.expectEqualStrings(
        "resolved",
        excluded_history_object.get("environment").?.object
            .get("resolution_status").?.string,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        excluded_history_object.get("actions").?.array.items.len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        excluded_history_object.get("jobs").?.array.items.len,
    );
    var protected_fixture = try Fixture.create();
    defer protected_fixture.destroy();
    const protected_rpm_config =
        tdnf_rpm_config_create(protected_fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(protected_rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(protected_rpm_config),
    );
    try protected_fixture.tmp.dir.createDirPath(
        std.testing.io,
        "root/protected.d",
    );
    try protected_fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/protected.d/transaction-plan.conf",
        .data = "installed-file-provider\ninstalled-file-provider\n",
    });
    const protected_setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(protected_setopts);
    const protected_repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(protected_repoopts);
    var protected_args = CmdArgs{};
    protected_args.nAssumeYes = 1;
    protected_args.nCacheOnly = 1;
    protected_args.nNoGPGCheck = 1;
    protected_args.nQuiet = 1;
    protected_args.pszArch = @ptrCast(@constCast("x86_64"));
    protected_args.pszInstallRoot = protected_fixture.root.ptr;
    protected_args.pszConfFile = protected_fixture.config.ptr;
    protected_args.pszReleaseVer = @ptrCast(@constCast("1"));
    protected_args.cn_setopts = protected_setopts;
    protected_args.cn_repoopts = protected_repoopts;
    var protected_handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&protected_args, &protected_handle),
    );
    defer TDNFCloseHandle(protected_handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(protected_handle, 1),
    );
    const erase_command = try std.testing.allocator.dupeZ(u8, "erase");
    defer std.testing.allocator.free(erase_command);
    const protected_name = try std.testing.allocator.dupeZ(
        u8,
        "installed-file-provider",
    );
    defer std.testing.allocator.free(protected_name);
    var erase_commands = [_]?[*:0]u8{
        erase_command.ptr,
        protected_name.ptr,
        null,
    };
    protected_args.ppszCmds = &erase_commands;
    protected_args.nCmdCount = 2;
    TDNFTransactionPlanCaptureFailNextComposition(protected_handle);
    var failed_protected: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_protected,
        TDNFResolve(protected_handle, alter_erase, &failed_protected),
    );
    try std.testing.expect(failed_protected == null);
    var failed_plan: ?[*]const u8 = null;
    var failed_plan_length: usize = 0;
    try std.testing.expect(TDNFTransactionPlanCaptureGetCanonicalJson(
        protected_handle,
        &failed_plan,
        &failed_plan_length,
    ) != 0);
    try std.testing.expect(failed_plan == null);
    var protected_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_protected,
        TDNFResolve(protected_handle, alter_erase, &protected_solved),
    );
    try std.testing.expect(protected_solved == null);
    const protected_json = try capturedJson(protected_handle);
    defer std.testing.allocator.free(protected_json);
    var protected_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        protected_json,
        .{},
    );
    defer protected_plan.deinit();
    const protected_object = protected_plan.value.object;
    const protected_problem =
        protected_object.get("problems").?.array.items[0].object;
    try std.testing.expectEqualStrings(
        "protected_package",
        protected_problem.get("kind").?.string,
    );
    const protected_package_id =
        protected_problem.get("package_id").?.string;
    const protected_package = for (
        protected_object.get("packages").?.array.items,
    ) |package| {
        if (std.mem.eql(
            u8,
            protected_package_id,
            package.object.get("id").?.string,
        )) break package.object;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        "installed-file-provider",
        protected_package.get("identity").?.object.get("name").?.string,
    );
    const protected_job_id = protected_problem.get("job_id").?.string;
    const protected_job = for (
        protected_object.get("jobs").?.array.items,
    ) |job| {
        if (std.mem.eql(u8, protected_job_id, job.object.get("id").?.string))
            break job.object;
    } else return error.TestUnexpectedResult;
    const protected_request_id = protected_job.get("request_id").?.string;
    const protected_request = for (
        protected_object.get("requests").?.array.items,
    ) |request| {
        if (std.mem.eql(
            u8,
            protected_request_id,
            request.object.get("id").?.string,
        )) break request.object;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        "installed-file-provider",
        protected_request.get("subject").?.string,
    );
    var mixed_protected_commands = [_]?[*:0]u8{
        erase_command.ptr,
        protected_name.ptr,
        @ptrCast(@constCast("missing-protected")),
        null,
    };
    protected_args.ppszCmds = &mixed_protected_commands;
    protected_args.nCmdCount = 3;
    protected_args.nSkipBroken = 1;
    var mixed_protected_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_protected,
        TDNFResolve(
            protected_handle,
            alter_erase,
            &mixed_protected_solved,
        ),
    );
    try std.testing.expect(mixed_protected_solved == null);
    const mixed_protected_json = try capturedJson(protected_handle);
    defer std.testing.allocator.free(mixed_protected_json);
    var mixed_protected_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        mixed_protected_json,
        .{},
    );
    defer mixed_protected_plan.deinit();
    const mixed_protected_object = mixed_protected_plan.value.object;
    var saw_missing_problem = false;
    var saw_protected_problem = false;
    for (mixed_protected_object.get("problems").?.array.items) |problem| {
        const kind = problem.object.get("kind").?.string;
        if (std.mem.eql(u8, kind, "no_candidate"))
            saw_missing_problem = true;
        if (std.mem.eql(u8, kind, "protected_package"))
            saw_protected_problem = true;
    }
    try std.testing.expect(saw_missing_problem);
    try std.testing.expect(saw_protected_problem);
    try std.testing.expectEqual(
        @as(usize, 0),
        mixed_protected_object.get("skipped").?.array.items.len,
    );
    protected_args.nSkipBroken = 0;
    const install_replacement = try std.testing.allocator.dupeZ(
        u8,
        "install",
    );
    defer std.testing.allocator.free(install_replacement);
    const replacement_name = try std.testing.allocator.dupeZ(
        u8,
        "replacement-provider",
    );
    defer std.testing.allocator.free(replacement_name);
    var replacement_commands = [_]?[*:0]u8{
        install_replacement.ptr,
        replacement_name.ptr,
        null,
    };
    protected_args.ppszCmds = &replacement_commands;
    protected_args.nCmdCount = 2;
    var replacement_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_protected,
        TDNFResolve(protected_handle, alter_install, &replacement_solved),
    );
    try std.testing.expect(replacement_solved == null);
    const replacement_json = try capturedJson(protected_handle);
    defer std.testing.allocator.free(replacement_json);
    var replacement_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        replacement_json,
        .{},
    );
    defer replacement_plan.deinit();
    const replacement_object = replacement_plan.value.object;
    const replacement_problem =
        replacement_object.get("problems").?.array.items[0].object;
    try std.testing.expectEqualStrings(
        "protected_package",
        replacement_problem.get("kind").?.string,
    );
    const removed_package_id =
        replacement_problem.get("package_id").?.string;
    const removed_package = for (
        replacement_object.get("packages").?.array.items,
    ) |package| {
        if (std.mem.eql(
            u8,
            removed_package_id,
            package.object.get("id").?.string,
        )) break package.object;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        "installed-file-provider",
        removed_package.get("identity").?.object.get("name").?.string,
    );
    const replacement_job_id =
        replacement_problem.get("job_id").?.string;
    const replacement_job = for (
        replacement_object.get("jobs").?.array.items,
    ) |job| {
        if (std.mem.eql(
            u8,
            replacement_job_id,
            job.object.get("id").?.string,
        )) break job.object;
    } else return error.TestUnexpectedResult;
    const replacement_request_id =
        replacement_job.get("request_id").?.string;
    const replacement_request = for (
        replacement_object.get("requests").?.array.items,
    ) |request| {
        if (std.mem.eql(
            u8,
            replacement_request_id,
            request.object.get("id").?.string,
        )) break request.object;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        "replacement-provider",
        replacement_request.get("subject").?.string,
    );
    var accepted_terminal_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("replacement-provider")),
        @ptrCast(@constCast("conflict-a")),
        null,
    };
    protected_args.ppszCmds = &accepted_terminal_commands;
    protected_args.nCmdCount = 3;
    protected_args.nSkipBroken = 1;
    var accepted_terminal_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_protected,
        TDNFResolve(
            protected_handle,
            alter_install,
            &accepted_terminal_solved,
        ),
    );
    try std.testing.expect(accepted_terminal_solved == null);
    const accepted_terminal_json = try capturedJson(protected_handle);
    defer std.testing.allocator.free(accepted_terminal_json);
    var accepted_terminal_plan = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        accepted_terminal_json,
        .{},
    );
    defer accepted_terminal_plan.deinit();
    const accepted_terminal_problems = accepted_terminal_plan.value.object
        .get("problems").?.array.items;
    try std.testing.expect(accepted_terminal_problems.len >= 2);
    var accepted_saw_terminal = false;
    var accepted_saw_solver = false;
    for (accepted_terminal_problems) |problem| {
        const kind = problem.object.get("kind").?.string;
        if (std.mem.eql(u8, kind, "protected_package"))
            accepted_saw_terminal = true
        else
            accepted_saw_solver = true;
    }
    try std.testing.expect(accepted_saw_terminal);
    try std.testing.expect(accepted_saw_solver);
    protected_args.nSkipBroken = 0;
    var corrupted_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("conflict-a")),
        null,
    };
    protected_args.ppszCmds = &corrupted_commands;
    protected_args.nCmdCount = 2;
    TDNFTransactionPlanCaptureFailNextIntegrity(protected_handle);
    var corrupted_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_solv_failed,
        TDNFResolve(protected_handle, alter_install, &corrupted_solved),
    );
    try std.testing.expect(corrupted_solved == null);
    try std.testing.expect(TDNFTransactionPlanCaptureGetCanonicalJson(
        protected_handle,
        &failed_plan,
        &failed_plan_length,
    ) != 0);
    const install_problem = try std.testing.allocator.dupeZ(
        u8,
        "install",
    );
    defer std.testing.allocator.free(install_problem);
    const conflict = try std.testing.allocator.dupeZ(u8, "conflict-a");
    defer std.testing.allocator.free(conflict);
    var problem_commands = [_]?[*:0]u8{
        install_problem.ptr,
        conflict.ptr,
        null,
    };
    args.ppszCmds = &problem_commands;
    args.nCmdCount = 2;
    var problem_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_solv_failed,
        TDNFResolve(handle, alter_install, &problem_solved),
    );
    try std.testing.expect(problem_solved == null);
    var close_json: ?[*]const u8 = null;
    var close_json_length: usize = 0;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureGetCanonicalJson(
            handle,
            &close_json,
            &close_json_length,
        ),
    );
    TDNFCloseHandle(handle);
    handle = null;
    handle_live = false;
    defer TDNFTransactionPlanStateFreeCanonicalJson(
        close_json,
        close_json_length,
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        close_json.?[0..close_json_length],
        "\"resolution_status\":\"problems\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        close_json.?[0..close_json_length],
        "\"kind\":\"unsatisfied_requirement\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        close_json.?[0..close_json_length],
        "\"subject\":\"conflict-a\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        close_json.?[0..close_json_length],
        "\"job_id\":\"job-0\"",
    ) != null);
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        close_json.?[0..close_json_length],
        .{},
    );
    defer parsed.deinit();
    const object = parsed.value.object;
    const problem_job = object.get("problems").?.array.items[0]
        .object.get("job_id").?.string;
    const request = object.get("requests").?.array.items[0].object;
    try std.testing.expectEqualStrings(
        "conflict-a",
        request.get("subject").?.string,
    );
    const request_id = request.get("id").?.string;
    const jobs = object.get("jobs").?.array.items;
    const attributed_job = for (jobs) |job| {
        if (std.mem.eql(u8, problem_job, job.object.get("id").?.string))
            break job.object;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(
        request_id,
        attributed_job.get("request_id").?.string,
    );
}

test "failed skip-if-unavailable refresh retires stale solver repo" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    const install = try std.testing.allocator.dupeZ(u8, "install");
    defer std.testing.allocator.free(install);
    const app = try std.testing.allocator.dupeZ(u8, "app");
    defer std.testing.allocator.free(app);
    var commands = [_]?[*:0]u8{ install.ptr, app.ptr, null };
    var args = CmdArgs{};
    args.nAssumeYes = 1;
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 2;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;

    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    try fixture.tmp.dir.deleteFile(
        std.testing.io,
        fixture.base_repomd,
    );
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));

    var update_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    args.ppszCmds = &update_commands;
    args.nCmdCount = 1;
    var update: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_upgrade_all, &update),
    );
    defer TDNFFreeSolvedPackageInfo(update);
    const captured = try capturedJson(handle);
    defer std.testing.allocator.free(captured);
    try std.testing.expect(std.mem.indexOf(
        u8,
        captured,
        "\"id\":\"extras\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        captured,
        "\"id\":\"base\"",
    ) == null);

    args.ppszCmds = &commands;
    args.nCmdCount = 2;
    var solved: ?*anyopaque = null;
    try std.testing.expect(TDNFResolve(
        handle,
        alter_install,
        &solved,
    ) != 0);
    try std.testing.expect(solved == null);
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRetireNullSack(handle),
    );
}

test "disabled capture preserves legacy oversized metadata loading" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.advertiseOversizedPrimary();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("app")),
        null,
    };
    var args = CmdArgs{};
    args.nAssumeYes = 1;
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 2;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    var solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_install, &solved),
    );
    defer TDNFFreeSolvedPackageInfo(solved);
    try std.testing.expect(solved != null);
    var json: ?[*]const u8 = null;
    var json_length: usize = 0;
    try std.testing.expect(TDNFTransactionPlanCaptureGetCanonicalJson(
        handle,
        &json,
        &json_length,
    ) != 0);
}

test "repofromdir is rejected early only when capture is enabled" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.tmp.dir.createDirPath(std.testing.io, "root/fromdir");
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    const fromdir_value = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "dirrepo,{s}/fromdir",
        .{fixture.root},
        0,
    );
    defer std.testing.allocator.free(fromdir_value);
    const fromdir = create_cnfnode("repofromdir") orelse
        return error.OutOfMemory;
    cnfnode_setval(fromdir, fromdir_value.ptr);
    append_node(setopts, fromdir);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    var args = CmdArgs{};
    args.nAssumeYes = 1;
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    var disabled_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_upgrade_all, &disabled_solved),
    );
    defer TDNFFreeSolvedPackageInfo(disabled_solved);
    try fixture.tmp.dir.deleteDir(std.testing.io, "root/fromdir");
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    var enabled_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_call_not_supported,
        TDNFResolve(handle, alter_upgrade_all, &enabled_solved),
    );
    try std.testing.expect(enabled_solved == null);
    var history_args = HistoryArgs{ .command = 2, .to = 1 };
    var history_solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_call_not_supported,
        TDNFHistoryResolve(handle, &history_args, &history_solved),
    );
    try std.testing.expect(history_solved == null);
}

test "repofromdir tracking preserves whitespace repository ids" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.tmp.dir.createDirPath(std.testing.io, "root/fromdir");
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    const fromdir_value = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "dir repo\tid,{s}/fromdir",
        .{fixture.root},
        0,
    );
    defer std.testing.allocator.free(fromdir_value);
    const fromdir = create_cnfnode("repofromdir") orelse
        return error.OutOfMemory;
    cnfnode_setval(fromdir, fromdir_value.ptr);
    append_node(setopts, fromdir);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    var args = CmdArgs{};
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    var solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        error_call_not_supported,
        TDNFResolve(handle, alter_upgrade_all, &solved),
    );
    try std.testing.expect(solved == null);
}

test "alternate sack snapshot uses its own shifted repository ids" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.enableBaseSnapshot();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    var args = CmdArgs{};
    args.nAssumeYes = 1;
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    const live_base_identity =
        TDNFTransactionPlanTestRepoIdentity(handle, "base");
    var live_base_digest: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordDigest(
            handle,
            "base",
            &live_base_digest,
        ),
    );
    const alternate_cache = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/cache",
        .{fixture.root},
        0,
    );
    defer std.testing.allocator.free(alternate_cache);
    var alternate: ?*anyopaque = null;
    defer if (alternate) |sack| SolvFreeSack(sack);
    try std.testing.expectEqual(
        @as(u32, 0),
        SolvInitSack(
            &alternate,
            alternate_cache.ptr,
            fixture.root.ptr,
            "x86_64",
        ),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanTestInitRepoInSack(
            handle,
            alternate,
            "extras",
        ),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanTestInitRepoInSack(
            handle,
            alternate,
            "extras",
        ),
    );
    try std.testing.expectEqual(
        live_base_identity,
        TDNFTransactionPlanTestRepoIdentity(handle, "base"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordCount(handle, "base"),
    );
    var after_alternate_init_digest: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordDigest(
            handle,
            "base",
            &after_alternate_init_digest,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &live_base_digest,
        &after_alternate_init_digest,
    );
    const alternate_view: *SolvSackView = @ptrCast(@alignCast(alternate.?));
    const foreign = repo_create(alternate_view.pool, "base") orelse
        return error.OutOfMemory;
    for (0..2) |_| {
        if (repo_add_solvable(foreign) <= 0) return error.OutOfMemory;
    }
    const dummy = repo_create(alternate_view.pool, "shift") orelse
        return error.OutOfMemory;
    for (0..3) |_| {
        if (repo_add_solvable(dummy) <= 0) return error.OutOfMemory;
    }
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, alternate, 0),
    );
    var alternate_before_failures = SackSnapshot{};
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestSackSnapshot(
            alternate,
            "extras",
            &alternate_before_failures,
        ),
    );
    try std.testing.expect(alternate_before_failures.considered_identity != 0);
    try std.testing.expect(alternate_before_failures.indexes_identity != 0);
    const live_extras_identity =
        TDNFTransactionPlanTestRepoIdentity(handle, "extras");
    try std.testing.expect(
        alternate_before_failures.repository_identity != live_extras_identity,
    );
    for (1..8) |stage| {
        args.nRefresh = 0;
        TDNFTransactionPlanTestFailNextReload(handle, @intCast(stage));
        try std.testing.expectEqual(
            error_out_of_memory,
            TDNFRefreshSack(handle, alternate, 1),
        );
        try std.testing.expectEqual(@as(c_int, 0), args.nRefresh);
        var after_failure = SackSnapshot{};
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestSackSnapshot(
                alternate,
                "extras",
                &after_failure,
            ),
        );
        try std.testing.expectEqualDeep(
            alternate_before_failures,
            after_failure,
        );
        try std.testing.expectEqual(
            live_base_identity,
            TDNFTransactionPlanTestRepoIdentity(handle, "base"),
        );
        var after_failure_digest: [32]u8 = undefined;
        try std.testing.expectEqual(
            @as(u32, 1),
            TDNFTransactionPlanTestRepoRecordDigest(
                handle,
                "base",
                &after_failure_digest,
            ),
        );
        try std.testing.expectEqualSlices(
            u8,
            &live_base_digest,
            &after_failure_digest,
        );
    }
    args.nRefresh = 0;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, alternate, 1),
    );
    try std.testing.expectEqual(@as(c_int, 1), args.nRefresh);
    var alternate_after_swap = SackSnapshot{};
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestSackSnapshot(
            alternate,
            "extras",
            &alternate_after_swap,
        ),
    );
    try std.testing.expect(
        alternate_before_failures.pool_identity !=
            alternate_after_swap.pool_identity,
    );
    try std.testing.expect(
        alternate_before_failures.repository_identity !=
            alternate_after_swap.repository_identity,
    );
    try std.testing.expect(
        alternate_before_failures.considered_identity !=
            alternate_after_swap.considered_identity,
    );
    try std.testing.expect(
        alternate_before_failures.indexes_identity !=
            alternate_after_swap.indexes_identity,
    );
    try std.testing.expectEqual(
        alternate_before_failures.solvable_count,
        alternate_after_swap.solvable_count,
    );
    try std.testing.expectEqual(
        alternate_before_failures.repository_count,
        alternate_after_swap.repository_count,
    );
    try std.testing.expectEqual(
        alternate_before_failures.considered_count,
        alternate_after_swap.considered_count,
    );
    try std.testing.expectEqualSlices(
        u8,
        &alternate_before_failures.digest,
        &alternate_after_swap.digest,
    );
    const rpmdb_path = try resolveRpmDbPath(
        std.testing.allocator,
        rpm_config,
    );
    defer std.testing.allocator.free(rpmdb_path);
    const rpmdb_dir = std.Io.Dir.cwd();
    const rpmdb_bytes = try rpmdb_dir.readFileAlloc(
        std.testing.io,
        rpmdb_path,
        std.testing.allocator,
        .limited(64 * 1024 * 1024),
    );
    defer std.testing.allocator.free(rpmdb_bytes);
    try rpmdb_dir.writeFile(std.testing.io, .{
        .sub_path = rpmdb_path,
        .data = "not a sqlite database",
    });
    args.nRefresh = 0;
    const installed_failure = TDNFRefreshSack(handle, alternate, 1);
    try rpmdb_dir.writeFile(std.testing.io, .{
        .sub_path = rpmdb_path,
        .data = rpmdb_bytes,
    });
    try std.testing.expect(installed_failure != 0);
    try std.testing.expectEqual(@as(c_int, 0), args.nRefresh);
    var after_installed_failure = SackSnapshot{};
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestSackSnapshot(
            alternate,
            "extras",
            &after_installed_failure,
        ),
    );
    try std.testing.expectEqualDeep(
        alternate_after_swap,
        after_installed_failure,
    );
    try std.testing.expectEqual(
        live_base_identity,
        TDNFTransactionPlanTestRepoIdentity(handle, "base"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordCount(handle, "base"),
    );
    var after_alternate_refresh_digest: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordDigest(
            handle,
            "base",
            &after_alternate_refresh_digest,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &live_base_digest,
        &after_alternate_refresh_digest,
    );
    var alternate_count: u32 = 0;
    try std.testing.expectEqual(
        @as(u32, 0),
        SolvCountPackages(alternate, &alternate_count),
    );
    try std.testing.expectEqual(@as(u32, 9), alternate_count);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, null, 0),
    );
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    const cached_repomd = try fixture.tmp.dir.readFileAlloc(
        std.testing.io,
        fixture.base_repomd,
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(cached_repomd);
    const repodata_dir = std.fs.path.dirname(fixture.base_repomd) orelse
        return error.TestUnexpectedResult;
    const cached_primary_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/primary.xml",
        .{repodata_dir},
    );
    defer std.testing.allocator.free(cached_primary_path);
    const cached_primary = try fixture.tmp.dir.readFileAlloc(
        std.testing.io,
        cached_primary_path,
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(cached_primary);
    try fixture.tmp.dir.deleteFile(
        std.testing.io,
        fixture.base_repomd,
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestPublicInitRepo(handle),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, alternate, 0),
    );
    try fixture.tmp.dir.createDirPath(std.testing.io, repodata_dir);
    try fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = fixture.base_repomd,
        .data = cached_repomd,
    });
    try fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = cached_primary_path,
        .data = cached_primary,
    });
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestEnableRepo(handle, "base"),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, alternate, 0),
    );
    alternate_count = 0;
    try std.testing.expectEqual(
        @as(u32, 0),
        SolvCountPackages(alternate, &alternate_count),
    );
    try std.testing.expectEqual(@as(u32, 9), alternate_count);
    const before_free_identity =
        TDNFTransactionPlanTestRepoIdentity(handle, "base");
    var before_free_digest: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordDigest(
            handle,
            "base",
            &before_free_digest,
        ),
    );
    SolvFreeSack(alternate);
    alternate = null;
    try std.testing.expectEqual(
        before_free_identity,
        TDNFTransactionPlanTestRepoIdentity(handle, "base"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordCount(handle, "base"),
    );
    var after_free_digest: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordDigest(
            handle,
            "base",
            &after_free_digest,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &before_free_digest,
        &after_free_digest,
    );
    var install_commands = [_]?[*:0]u8{
        @ptrCast(@constCast("install")),
        @ptrCast(@constCast("survivor")),
        null,
    };
    args.ppszCmds = &install_commands;
    args.nCmdCount = 2;
    var solved: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFResolve(handle, alter_install, &solved),
    );
    defer TDNFFreeSolvedPackageInfo(solved);
    try std.testing.expect(solved != null);
}

test "alternate sack repository failure preserves exact state" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.requireBaseAvailable();
    const rpm_config = tdnf_rpm_config_create(fixture.root.ptr) orelse
        return error.OutOfMemory;
    defer tdnf_rpm_config_destroy(rpm_config);
    try std.testing.expectEqual(
        @as(c_int, 0),
        TDNFTransactionPlanTestWriteFileProvider(rpm_config),
    );
    const setopts = create_cnfnode("(setopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse
        return error.OutOfMemory;
    defer destroy_cnftree(repoopts);
    var commands = [_]?[*:0]u8{
        @ptrCast(@constCast("upgrade")),
        null,
    };
    var args = CmdArgs{};
    args.nAssumeYes = 1;
    args.nCacheOnly = 1;
    args.nQuiet = 1;
    args.pszArch = @ptrCast(@constCast("x86_64"));
    args.pszInstallRoot = fixture.root.ptr;
    args.pszConfFile = fixture.config.ptr;
    args.pszReleaseVer = @ptrCast(@constCast("1"));
    args.ppszCmds = &commands;
    args.nCmdCount = 1;
    args.cn_setopts = setopts;
    args.cn_repoopts = repoopts;
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFOpenHandle(&args, &handle),
    );
    defer TDNFCloseHandle(handle);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFTransactionPlanCaptureSetEnabled(handle, 1),
    );
    try std.testing.expectEqual(@as(u32, 0), TDNFRefresh(handle));
    const live_base_identity =
        TDNFTransactionPlanTestRepoIdentity(handle, "base");
    var live_base_digest: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordDigest(
            handle,
            "base",
            &live_base_digest,
        ),
    );

    const alternate_cache = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/cache",
        .{fixture.root},
        0,
    );
    defer std.testing.allocator.free(alternate_cache);
    var alternate: ?*anyopaque = null;
    defer if (alternate) |sack| SolvFreeSack(sack);
    try std.testing.expectEqual(
        @as(u32, 0),
        SolvInitSack(
            &alternate,
            alternate_cache.ptr,
            fixture.root.ptr,
            "x86_64",
        ),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFRefreshSack(handle, alternate, 0),
    );
    var before = SackSnapshot{};
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestSackSnapshot(
            alternate,
            "base",
            &before,
        ),
    );

    const cached_repomd = try fixture.tmp.dir.readFileAlloc(
        std.testing.io,
        fixture.base_repomd,
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(cached_repomd);
    const repodata_dir = std.fs.path.dirname(fixture.base_repomd) orelse
        return error.TestUnexpectedResult;
    const primary_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/primary.xml",
        .{repodata_dir},
    );
    defer std.testing.allocator.free(primary_path);
    const cached_primary = try fixture.tmp.dir.readFileAlloc(
        std.testing.io,
        primary_path,
        std.testing.allocator,
        .limited(1024 * 1024),
    );
    defer std.testing.allocator.free(cached_primary);
    const cached_solv = try fixture.tmp.dir.readFileAlloc(
        std.testing.io,
        fixture.base_solv,
        std.testing.allocator,
        .limited(64 * 1024 * 1024),
    );
    defer std.testing.allocator.free(cached_solv);
    try fixture.tmp.dir.deleteFile(std.testing.io, fixture.base_repomd);
    try fixture.tmp.dir.deleteFile(std.testing.io, fixture.base_solv);
    args.nRefresh = 0;
    const result = TDNFRefreshSack(handle, alternate, 1);
    try fixture.tmp.dir.createDirPath(std.testing.io, repodata_dir);
    try fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = fixture.base_repomd,
        .data = cached_repomd,
    });
    try fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = primary_path,
        .data = cached_primary,
    });
    try fixture.tmp.dir.createDirPath(
        std.testing.io,
        std.fs.path.dirname(fixture.base_solv) orelse
            return error.TestUnexpectedResult,
    );
    try fixture.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = fixture.base_solv,
        .data = cached_solv,
    });
    try std.testing.expect(result != 0);
    try std.testing.expectEqual(@as(c_int, 0), args.nRefresh);
    var after = SackSnapshot{};
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestSackSnapshot(
            alternate,
            "base",
            &after,
        ),
    );
    try std.testing.expectEqualDeep(before, after);
    try std.testing.expectEqual(
        live_base_identity,
        TDNFTransactionPlanTestRepoIdentity(handle, "base"),
    );
    var after_live_digest: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, 1),
        TDNFTransactionPlanTestRepoRecordDigest(
            handle,
            "base",
            &after_live_digest,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &live_base_digest,
        &after_live_digest,
    );
}
