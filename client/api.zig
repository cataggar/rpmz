// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("tdnf_common");
const abi = @import("client_abi");
const errors = @import("tdnf_error");
const options = @import("client_config_options");
const transaction_plan_abi = @import("transaction_plan_capture_abi");
const transaction_lock = @import("transaction_lock");
const txn_config = @import("rpm_txn_config");
const resolve_service = @import("resolve_service.zig");

const c = abi.C;
const CmdArgs = abi.CmdArgs;
const Conf = abi.Conf;
const CnfNode = abi.CnfNode;
const HistoryCtx = abi.HistoryCtx;
const HistoryDelta = abi.HistoryDelta;
const HistoryFlagsDelta = abi.HistoryFlagsDelta;
const HistoryInfo = abi.HistoryInfo;
const HistoryInfoItem = abi.HistoryInfoItem;
const HistoryNevraMap = abi.HistoryNevraMap;
const HistoryTransaction = abi.HistoryTransaction;
const IdList = abi.IdList;
const NativeRepoInput = abi.NativeRepoInput;
const PackageInfo = abi.PackageInfo;
const RepoData = abi.RepoData;
const SolvedPackageInfo = abi.SolvedPackageInfo;
const Tdnf = abi.Tdnf;
const UpdateInfo = abi.UpdateInfo;

const RepoSyncArgs = c.TDNF_REPOSYNC_ARGS;
const RepoQueryArgs = c.TDNF_REPOQUERY_ARGS;
const HistoryArgs = c.TDNF_HISTORY_ARGS;
const RpmFile = opaque {};

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const LOG_CRIT: c_int = 2;

const DETAIL_LIST: c_uint = 0;
const DETAIL_INFO: c_uint = 1;
const DETAIL_LOCATION: c_uint = 4;
const TDNF_NEVRA_UNINSTALLED: c_int = 0;
const TDNF_NEVRA_INSTALLED: c_int = 1;
const FTW_PHYS: c_int = 1;
const FTW_DEPTH: c_int = 8;

const command_line_repo_name: [*:0]const u8 = "@cmdline";
const system_repo_name: [*:0]const u8 = "@System";
const config_file: [*:0]const u8 = "/etc/tdnf/tdnf.conf";
const config_group: [*:0]const u8 = "main";

export var gEuid: std.posix.uid_t = 0;

fn commandRequiresTargetLock(args: *const CmdArgs) bool {
    if (args.ppszCmds == null or args.nCmdCount <= 0)
        return false;
    const command = args.ppszCmds.?[0] orelse return false;
    const name = std.mem.span(command);
    inline for (.{
        "autoerase",
        "autoremove",
        "distro-sync",
        "downgrade",
        "erase",
        "history",
        "install",
        "mark",
        "plan",
        "reinstall",
        "remove",
        "update",
        "update-to",
        "upgrade",
        "upgrade-to",
    }) |candidate| {
        if (std.ascii.eqlIgnoreCase(name, candidate)) return true;
    }
    return false;
}

fn bindTransactionTarget(handle: *Tdnf) u32 {
    const raw_config = handle.pRpmConfig orelse
        return errors.ERROR_TDNF_RPMRC_FAIL;
    const config: *txn_config.TxnConfig = @ptrCast(@alignCast(raw_config));
    const acquired = transaction_lock.acquireRoot(
        std.heap.c_allocator,
        config,
    ) catch |err| {
        common.log(
            LOG_ERR,
            "Unable to lock transaction target: %s\n",
            .{@errorName(err)},
        );
        return errors.ERROR_TDNF_RPMRC_FAIL;
    };
    const guard = std.heap.c_allocator.create(
        transaction_lock.Guard,
    ) catch {
        var cleanup = acquired;
        cleanup.deinit();
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    };
    guard.* = acquired;
    const pinned_root = std.heap.c_allocator.dupeZ(
        u8,
        guard.config().installRoot(),
    ) catch {
        guard.deinit();
        std.heap.c_allocator.destroy(guard);
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    };
    const args = handle.pArgs orelse {
        std.heap.c_allocator.free(pinned_root);
        guard.deinit();
        std.heap.c_allocator.destroy(guard);
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    const original_config = handle.pRpmConfig;
    handle.pTransactionTargetLock = guard;
    handle.pszPinnedInstallRoot = pinned_root.ptr;
    handle.pszOriginalInstallRoot = args.pszInstallRoot;
    handle.pRpmConfig = @ptrCast(guard.config());
    args.pszInstallRoot = pinned_root.ptr;
    tdnf_rpm_config_destroy(original_config);
    return 0;
}

fn releaseTransactionTarget(handle: *Tdnf) void {
    const raw_guard = handle.pTransactionTargetLock orelse {
        tdnf_rpm_config_destroy(handle.pRpmConfig);
        handle.pRpmConfig = null;
        return;
    };
    const guard: *transaction_lock.Guard = @ptrCast(@alignCast(raw_guard));
    if (handle.pArgs) |args| {
        args.pszInstallRoot = handle.pszOriginalInstallRoot;
    }
    if (handle.pszPinnedInstallRoot) |root| {
        std.heap.c_allocator.free(std.mem.span(root));
    }
    handle.pszPinnedInstallRoot = null;
    handle.pszOriginalInstallRoot = null;
    handle.pRpmConfig = null;
    handle.pTransactionTargetLock = null;
    guard.deinit();
    std.heap.c_allocator.destroy(guard);
}

extern fn TDNFAllocateMemory(
    count: usize,
    size: usize,
    output: *?*anyopaque,
) callconv(.c) u32;
extern fn TDNFReAllocateMemory(
    size: usize,
    output: *?*anyopaque,
) callconv(.c) u32;
extern fn TDNFAllocateString(
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFFreeMemory(memory: ?*anyopaque) callconv(.c) void;
extern fn TDNFFreeStringArray(
    values: ?[*]?[*:0]u8,
) callconv(.c) void;
extern fn TDNFFreeStringArrayWithCount(
    values: ?[*]?[*:0]u8,
    count: c_int,
) callconv(.c) void;
extern fn TDNFJoinPathFromArray(
    output: *?[*:0]u8,
    nodes: [*c]?[*:0]u8,
    count: c_int,
) callconv(.c) u32;
extern fn TDNFJoinArrayToString(
    values: ?[*]?[*:0]u8,
    separator: ?[*:0]const u8,
    count: c_int,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFNormalizePath(
    path: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFStringMatchesOneOf(
    value: ?[*:0]const u8,
    values: ?[*]?[*:0]u8,
    matched: *c_int,
) callconv(.c) u32;
extern fn TDNFIdListInit(list: *IdList) callconv(.c) void;
extern fn TDNFIdListFree(list: *IdList) callconv(.c) void;
extern fn TDNFIdListPush(list: *IdList, value: i32) callconv(.c) u32;
extern fn GlobalSetQuiet(value: i32) callconv(.c) void;
extern fn GlobalSetJson(value: i32) callconv(.c) void;
extern fn GlobalSetDnfCheckUpdateCompat(value: i32) callconv(.c) void;

extern fn TDNFRefresh(handle: ?*Tdnf) callconv(.c) u32;
extern fn TDNFReadConfig(
    handle: ?*Tdnf,
    path: ?[*:0]const u8,
    group: ?[*:0]const u8,
) callconv(.c) u32;
extern fn TDNFConfigExpandVars(handle: ?*Tdnf) callconv(.c) u32;
extern fn TDNFFreeConfig(conf: ?*Conf) callconv(.c) void;
extern fn TDNFLoadPlugins(handle: ?*Tdnf) callconv(.c) u32;
extern fn TDNFFreePlugins(plugins: ?*abi.Plugin) callconv(.c) void;
extern fn TDNFLoadRepoData(
    handle: ?*Tdnf,
    output: *?*RepoData,
) callconv(.c) u32;
extern fn TDNFRepoListFinalize(handle: ?*Tdnf) callconv(.c) u32;
extern fn TDNFCloneRepo(
    input: ?*RepoData,
    output: *?*RepoData,
) callconv(.c) u32;
extern fn TDNFFreeReposInternal(repos: ?*RepoData) callconv(.c) void;
extern fn TDNFFreeRepos(repos: ?*RepoData) callconv(.c) void;

extern fn tdnf_rpm_config_create(
    root: ?[*:0]const u8,
) callconv(.c) ?*anyopaque;
extern fn tdnf_rpm_config_destroy(config: ?*anyopaque) callconv(.c) void;
extern fn tdnf_rpm_config_apply_define(
    config: ?*anyopaque,
    value: ?[*:0]const u8,
) callconv(.c) c_int;
extern fn tdnf_rpm_config_finalize_rpmdb_pin(
    config: ?*anyopaque,
) callconv(.c) c_int;
extern fn tdnf_rpm_config_last_error() callconv(.c) [*:0]const u8;

extern fn TDNFPackageContextCreate(
    cache_dir: ?[*:0]const u8,
    root: ?[*:0]const u8,
    arch: ?[*:0]const u8,
    rpm_config: ?*const anyopaque,
    include_installed: c_int,
    output: *?*anyopaque,
) callconv(.c) u32;
extern fn TDNFPackageContextFree(context: ?*anyopaque) callconv(.c) void;
extern fn TDNFPackageContextInitCommandLine(
    context: ?*anyopaque,
    output: *?*anyopaque,
) callconv(.c) u32;

extern fn TDNFNativeQueryBuildRepoInputs(
    handle: ?*Tdnf,
    output: *?[*]NativeRepoInput,
    count: *u32,
) callconv(.c) u32;
extern fn TDNFNativeQueryFreeRepoInputs(
    repos: ?[*]NativeRepoInput,
    count: u32,
) callconv(.c) void;
extern fn TDNFNativeQueryFilterUserInstalled(
    handle: ?*Tdnf,
    infos: ?*PackageInfo,
    count: *u32,
) callconv(.c) u32;
extern fn TDNFNativeQueryApplyLocationUrls(
    handle: ?*Tdnf,
    infos: ?*PackageInfo,
    count: u32,
) callconv(.c) u32;
extern fn TDNFNativeQueryResolvePackageRefArrayToQueue(
    sack: ?*anyopaque,
    refs: ?[*]?[*:0]u8,
    count: u32,
    installed_only: c_int,
    queue: *IdList,
) callconv(.c) u32;
extern fn TDNFNativeQueryBuildUpdateInfo(
    lines: ?[*]?[*:0]u8,
    count: u32,
    output: *?*UpdateInfo,
) callconv(.c) u32;
extern fn TDNFPkgInfoFilterNewest(
    sack: ?*anyopaque,
    infos: ?*PackageInfo,
) callconv(.c) u32;

extern fn TDNFRepoMdNativeListConfig(
    repos: ?[*]NativeRepoInput,
    repo_count: u32,
    rpm_config: ?*const anyopaque,
    scope: c_int,
    specs: ?[*]?[*:0]u8,
    detail: c_uint,
    output: *?*PackageInfo,
    count: *u32,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeProvidesConfig(
    repos: ?[*]NativeRepoInput,
    repo_count: u32,
    rpm_config: ?*const anyopaque,
    spec: ?[*:0]const u8,
    output: *?*PackageInfo,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeRepoQueryConfig(
    repos: ?[*]NativeRepoInput,
    repo_count: u32,
    rpm_config: ?*const anyopaque,
    args: ?*const RepoQueryArgs,
    output: *?*PackageInfo,
    count: *u32,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeSearchConfig(
    repos: ?[*]NativeRepoInput,
    repo_count: u32,
    rpm_config: ?*const anyopaque,
    values: ?[*]?[*:0]u8,
    start: c_int,
    end: c_int,
    output: *?*PackageInfo,
    count: *u32,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeUpdateInfoLinesConfig(
    repos: ?[*]NativeRepoInput,
    repo_count: u32,
    rpm_config: ?*const anyopaque,
    specs: ?[*]?[*:0]u8,
    security: u32,
    severity: ?[*:0]const u8,
    reboot_required: u32,
    lines: *?[*]?[*:0]u8,
    count: *u32,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeFindNevraMatchesConfig(
    repos: ?[*]NativeRepoInput,
    repo_count: u32,
    rpm_config: ?*const anyopaque,
    nevra: ?[*:0]const u8,
    installed: c_int,
    matches: *?[*]?[*:0]u8,
    count: *u32,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeSolverCheckLocal(
    directory: ?[*:0]const u8,
    arch: ?[*:0]const u8,
    count: *u32,
    handle: *?*anyopaque,
    error_path: *?[*:0]const u8,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeSolverLiveSolveRelease(
    handle: ?*anyopaque,
) callconv(.c) void;
extern fn TDNFReportNativeSolverProblems(
    handle: ?*anyopaque,
    skip: c_uint,
) callconv(.c) u32;

extern fn TDNFRpmExecTransaction(
    handle: ?*Tdnf,
    solved: ?*SolvedPackageInfo,
) callconv(.c) u32;
extern fn TDNFRpmExecHistoryTransaction(
    handle: ?*Tdnf,
    solved: ?*SolvedPackageInfo,
    args: ?*HistoryArgs,
) callconv(.c) u32;
extern fn TDNFHistoryGoalWithUnresolved(
    handle: ?*Tdnf,
    install: *IdList,
    erase: *IdList,
    unresolved_count: u32,
    output: *?*SolvedPackageInfo,
) callconv(.c) u32;
extern fn TDNFAddNotResolved(
    unresolved: ?[*]?[*:0]u8,
    name: ?[*:0]const u8,
) callconv(.c) u32;

extern fn TDNFRepoRemoveCache(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) callconv(.c) u32;
extern fn TDNFRemoveSolvCache(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) callconv(.c) u32;
extern fn TDNFRemoveRpmCache(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) callconv(.c) u32;
extern fn TDNFRemoveKeysCache(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) callconv(.c) u32;
extern fn TDNFRemoveLastRefreshMarker(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) callconv(.c) u32;
extern fn TDNFRemoveMirrorList(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) callconv(.c) u32;
extern fn TDNFRemoveSnapshot(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) callconv(.c) u32;
extern fn TDNFRepoRemoveCacheDir(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) callconv(.c) u32;
extern fn TDNFFindRepoById(
    handle: ?*Tdnf,
    id: ?[*:0]const u8,
    output: *?*RepoData,
) callconv(.c) u32;
extern fn TDNFTouchFile(path: ?[*:0]const u8) callconv(.c) u32;

extern fn TDNFDownloadPackageToTree(
    handle: ?*Tdnf,
    location: ?[*:0]const u8,
    package_name: ?[*:0]const u8,
    repo: ?*RepoData,
    directory: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFCreatePackageUrl(
    repo: ?*RepoData,
    location: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFDownloadMetadata(
    handle: ?*Tdnf,
    repo: ?*RepoData,
    directory: ?[*:0]const u8,
    print_only: c_int,
) callconv(.c) u32;
extern fn TDNFGPGCheckPackageEx(
    handle: ?*Tdnf,
    repo: ?*RepoData,
    path: ?[*:0]const u8,
    rpm_file: *?*RpmFile,
    policy_rejected: *c_int,
) callconv(.c) u32;
extern fn tdnf_rpm_file_close(file: ?*RpmFile) callconv(.c) void;

extern fn TDNFUtilsMakeDir(path: ?[*:0]const u8) callconv(.c) u32;
extern fn TDNFIsFileOrSymlink(
    path: ?[*:0]const u8,
    exists: *c_int,
) callconv(.c) u32;
extern fn TDNFGetKernelArch(output: *?[*:0]u8) callconv(.c) u32;

extern fn TDNFFreePackageInfo(info: ?*PackageInfo) callconv(.c) void;
extern fn TDNFFreePackageInfoArray(
    infos: ?*PackageInfo,
    count: u32,
) callconv(.c) void;
extern fn TDNFFreeSolvedPackageInfo(
    solved: ?*SolvedPackageInfo,
) callconv(.c) void;
extern fn TDNFFreeUpdateInfo(info: ?*UpdateInfo) callconv(.c) void;
extern fn TDNFFreeHistoryInfoItems(
    items: ?[*]HistoryInfoItem,
    count: c_int,
) callconv(.c) void;

extern fn TDNFGetSecuritySeverityOption(
    handle: ?*Tdnf,
    security: *u32,
    severity: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFGetRebootRequiredOption(
    handle: ?*Tdnf,
    reboot_required: *u32,
) callconv(.c) u32;

extern fn TDNFGetHistoryCtx(
    handle: ?*Tdnf,
    output: *?*HistoryCtx,
    must_exist: c_int,
) callconv(.c) u32;
extern fn destroy_history_ctx(ctx: ?*HistoryCtx) callconv(.c) void;
extern fn history_sync_config(
    ctx: ?*HistoryCtx,
    rpm_config: ?*const anyopaque,
) callconv(.c) c_int;
extern fn history_get_current_transaction_id(
    ctx: ?*HistoryCtx,
) callconv(.c) c_int;
extern fn history_get_delta(
    ctx: ?*HistoryCtx,
    id: c_int,
) callconv(.c) ?*HistoryDelta;
extern fn history_get_delta_range(
    ctx: ?*HistoryCtx,
    from: c_int,
    to: c_int,
) callconv(.c) ?*HistoryDelta;
extern fn history_free_delta(delta: ?*HistoryDelta) callconv(.c) void;
extern fn history_get_flags_delta(
    ctx: ?*HistoryCtx,
    from: c_int,
    to: c_int,
) callconv(.c) ?*HistoryFlagsDelta;
extern fn history_free_flags_delta(
    delta: ?*HistoryFlagsDelta,
) callconv(.c) void;
extern fn history_nevra_map(
    ctx: ?*HistoryCtx,
) callconv(.c) ?*HistoryNevraMap;
extern fn history_free_nevra_map(
    map: ?*HistoryNevraMap,
) callconv(.c) void;
extern fn history_get_nevra(
    map: ?*HistoryNevraMap,
    id: c_int,
) callconv(.c) ?[*:0]u8;
extern fn history_get_transactions(
    ctx: ?*HistoryCtx,
    transactions: *?[*]HistoryTransaction,
    count: *c_int,
    reverse: c_int,
    from: c_int,
    to: c_int,
) callconv(.c) c_int;
extern fn history_free_transactions(
    transactions: ?[*]HistoryTransaction,
    count: c_int,
) callconv(.c) void;
extern fn history_add_transaction(
    ctx: ?*HistoryCtx,
    command_line: ?[*:0]const u8,
) callconv(.c) c_int;
extern fn history_set_auto_flag(
    ctx: ?*HistoryCtx,
    name: ?[*:0]const u8,
    value: c_int,
) callconv(.c) c_int;

extern fn TDNFTransactionPlanStateClear(
    state: ?*anyopaque,
) callconv(.c) void;
extern fn TDNFTransactionPlanStateDestroy(
    state: ?*anyopaque,
) callconv(.c) void;
extern fn TDNFTransactionPlanRequestTraceCreateHistory() callconv(.c) ?*anyopaque;
extern fn TDNFTransactionPlanRequestTraceDestroy(
    trace: ?*anyopaque,
) callconv(.c) void;
extern fn TDNFTransactionPlanRequestTraceRecordHistoryGoal(
    trace: ?*anyopaque,
    subject: ?[*:0]const u8,
    request_kind: u32,
    action: u32,
    ids: ?[*]const i32,
    start: u32,
    end: u32,
    outcome: u32,
) callconv(.c) void;

extern fn getcwd(buffer: ?[*]u8, size: usize) callconv(.c) ?[*:0]u8;
extern fn geteuid() callconv(.c) std.posix.uid_t;
extern fn remove(path: [*:0]const u8) callconv(.c) c_int;
extern fn stat(path: [*:0]const u8, info: *std.c.Stat) callconv(.c) c_int;
extern fn strerror(value: c_int) callconv(.c) [*:0]const u8;
extern fn strncasecmp(
    left: [*:0]const u8,
    right: [*:0]const u8,
    count: usize,
) callconv(.c) c_int;

const NftwCallback = *const fn (
    [*:0]const u8,
    ?*const anyopaque,
    c_int,
    ?*anyopaque,
) callconv(.c) c_int;
extern fn nftw(
    directory: [*:0]const u8,
    callback: NftwCallback,
    fd_limit: c_int,
    flags: c_int,
) callconv(.c) c_int;

fn isNullOrEmpty(value: ?[*:0]const u8) bool {
    return value == null or value.?[0] == 0;
}

fn eqlZ(left: [*:0]const u8, right: []const u8) bool {
    return std.mem.eql(u8, std.mem.span(left), right);
}

fn eqlIgnoreCaseZ(left: [*:0]const u8, right: []const u8) bool {
    return std.ascii.eqlIgnoreCase(std.mem.span(left), right);
}

fn freeString(slot: *?[*:0]u8) void {
    if (slot.*) |value| TDNFFreeMemory(@ptrCast(value));
    slot.* = null;
}

fn freeStringArray(slot: *?[*]?[*:0]u8) void {
    TDNFFreeStringArray(slot.*);
    slot.* = null;
}

fn joinPath(output: *?[*:0]u8, nodes: []const ?[*:0]const u8) u32 {
    return TDNFJoinPathFromArray(
        output,
        @ptrCast(@constCast(nodes.ptr)),
        @intCast(nodes.len),
    );
}

fn allocatePointerArray(count: usize, output: *?[*]?[*:0]u8) u32 {
    var raw: ?*anyopaque = null;
    const result = TDNFAllocateMemory(count, @sizeOf(?[*:0]u8), &raw);
    if (result != 0) {
        output.* = null;
        return result;
    }
    output.* = @ptrCast(@alignCast(raw.?));
    return 0;
}

fn packageNext(info: *PackageInfo) ?*PackageInfo {
    if (info.pNext == null) return null;
    return @ptrCast(info.pNext);
}

fn systemError() u32 {
    return errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(std.c._errno().*));
}

pub export fn TDNFInit() callconv(.c) u32 {
    return 0;
}

pub export fn TDNFUninit() callconv(.c) void {}

pub export fn TDNFCheckPackages(handle_opt: ?*Tdnf) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = handle.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const original_count = args.nCmdCount;
    const original_commands = args.ppszCmds;
    var solved: ?*SolvedPackageInfo = null;
    defer {
        args.nCmdCount = original_count;
        args.ppszCmds = original_commands;
        if (solved != null) TDNFFreeSolvedPackageInfo(solved);
    }

    var check_commands = [_]?[*:0]u8{
        @constCast(@as([*:0]const u8, "check")),
        @constCast(@as([*:0]const u8, "*")),
        null,
    };
    args.nAssumeNo = 1;
    args.nCmdCount = 2;
    args.ppszCmds = &check_commands;
    return TDNFResolve(handle, c.ALTER_INSTALL, &solved);
}

pub export fn TDNFAlterCommand(
    handle: ?*Tdnf,
    solved: ?*SolvedPackageInfo,
) callconv(.c) u32 {
    if (handle == null or solved == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    return TDNFRpmExecTransaction(handle, solved);
}

pub export fn TDNFAlterHistoryCommand(
    handle: ?*Tdnf,
    solved: ?*SolvedPackageInfo,
    args: ?*HistoryArgs,
) callconv(.c) u32 {
    if (handle == null or solved == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    return TDNFRpmExecHistoryTransaction(handle, solved, args);
}

pub export fn TDNFGetSkipProblemOption(
    handle_opt: ?*Tdnf,
    output: ?*c_uint,
) callconv(.c) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    out.* = c.SKIPPROBLEM_NONE;
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = handle.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;

    var node = args.cn_setopts.?.first_child;
    while (node) |current| : (node = current.next) {
        const name = current.name orelse continue;
        if (eqlIgnoreCaseZ(name, "skipconflicts"))
            out.* |= c.SKIPPROBLEM_CONFLICTS;
        if (eqlIgnoreCaseZ(name, "skipobsoletes"))
            out.* |= c.SKIPPROBLEM_OBSOLETES;
    }
    if (args.nSkipBroken != 0) out.* |= c.SKIPPROBLEM_BROKEN;
    return 0;
}

pub export fn TDNFCheckLocalPackages(
    handle_opt: ?*Tdnf,
    local_path: ?[*:0]const u8,
) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = handle.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pSack == null or local_path == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    common.log(LOG_INFO, "Checking all packages from: %s\n", .{local_path.?});
    var owned_arch: ?[*:0]u8 = null;
    defer freeString(&owned_arch);
    var arch: ?[*:0]const u8 = args.pszArch;
    if (isNullOrEmpty(arch)) {
        const result = TDNFGetKernelArch(&owned_arch);
        if (result != 0) return result;
        arch = owned_arch;
    }
    if (isNullOrEmpty(arch)) return errors.ERROR_TDNF_NO_DATA;

    var count: u32 = 0;
    var solver: ?*anyopaque = null;
    defer TDNFRepoMdNativeSolverLiveSolveRelease(solver);
    var error_path: ?[*:0]const u8 = null;
    var result = TDNFRepoMdNativeSolverCheckLocal(
        local_path,
        arch,
        &count,
        &solver,
        &error_path,
    );
    if (result != 0 and error_path != null) {
        const errno_value: c_int = if (result > errors.ERROR_TDNF_SYSTEM_BASE)
            @intCast(result - errors.ERROR_TDNF_SYSTEM_BASE)
        else
            0;
        common.log(LOG_ERR, "ReadRpms: Error while operating on '%s', '%s'\n", .{ error_path.?, strerror(errno_value) });
    }
    if (result != 0) return result;
    common.log(LOG_INFO, "Found %u packages\n", .{count});

    if (solver != null) {
        var skip: c_uint = c.SKIPPROBLEM_NONE;
        result = TDNFGetSkipProblemOption(handle, &skip);
        if (result != 0) return result;
        result = TDNFReportNativeSolverProblems(solver, skip);
        if (result != 0) return result;
    }
    return 0;
}

pub export fn TDNFCheckUpdates(
    handle: ?*Tdnf,
    specs: ?[*]?[*:0]u8,
    output: ?*?*PackageInfo,
    count: ?*u32,
) callconv(.c) u32 {
    const result = TDNFList(handle, c.SCOPE_UPGRADES, specs, output, count);
    return if (result == errors.ERROR_TDNF_NO_MATCH) 0 else result;
}

pub export fn TDNFClean(
    handle_opt: ?*Tdnf,
    clean_type: u32,
) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (clean_type == c.CLEANTYPE_PLUGINS)
        return errors.ERROR_TDNF_CLEAN_UNSUPPORTED;

    var repo = handle.pRepos;
    while (repo) |current| : (repo = current.pNext) {
        if (current.pszId != null and
            eqlZ(current.pszId.?, std.mem.span(command_line_repo_name)))
            continue;
        common.log(LOG_INFO, "cleaning %s:", .{current.pszId.?});
        var result: u32 = 0;
        if (clean_type & c.CLEANTYPE_METADATA != 0) {
            common.log(LOG_INFO, " metadata", .{});
            result = TDNFRepoRemoveCache(handle, current);
            if (result != 0) return result;
        }
        if (clean_type & c.CLEANTYPE_DBCACHE != 0) {
            common.log(LOG_INFO, " dbcache", .{});
            result = TDNFRemoveSolvCache(handle, current);
            if (result != 0) return result;
        }
        if (clean_type & c.CLEANTYPE_PACKAGES != 0) {
            common.log(LOG_INFO, " packages", .{});
            result = TDNFRemoveRpmCache(handle, current);
            if (result != 0) return result;
        }
        if (clean_type & c.CLEANTYPE_KEYS != 0) {
            common.log(LOG_INFO, " keys", .{});
            result = TDNFRemoveKeysCache(handle, current);
            if (result != 0) return result;
        }
        if (clean_type & c.CLEANTYPE_EXPIRE_CACHE != 0) {
            common.log(LOG_INFO, " expire-cache", .{});
            result = TDNFRemoveLastRefreshMarker(handle, current);
            if (result != 0) return result;
            result = TDNFRemoveMirrorList(handle, current);
            if (result != 0) return result;
            result = TDNFRemoveSnapshot(handle, current);
            if (result != 0) return result;
        }
        result = TDNFRepoRemoveCacheDir(handle, current);
        if (result == errors.fromErrno(.NOTEMPTY)) {
            if (clean_type == c.CLEANTYPE_ALL) {
                common.log(LOG_ERR, "Cache directory for %s not removed because it's not empty.\n", .{current.pszId.?});
            }
            result = 0;
        }
        if (result != 0) return result;
        common.log(LOG_INFO, "\n", .{});
    }
    return 0;
}

pub export fn TDNFCountCommand(
    handle_opt: ?*Tdnf,
    count_output: ?*u32,
) callconv(.c) u32 {
    const out = count_output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const handle = handle_opt orelse {
        out.* = 0;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (handle.pSack == null) {
        out.* = 0;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var infos: ?*PackageInfo = null;
    var count: u32 = 0;
    defer if (infos != null) TDNFFreePackageInfoArray(infos, count);
    var repos: ?[*]NativeRepoInput = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);

    var result = TDNFRefresh(handle);
    if (result == 0)
        result = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);
    if (result == 0) {
        result = TDNFRepoMdNativeListConfig(
            repos,
            repo_count,
            handle.pRpmConfig,
            c.SCOPE_ALL,
            null,
            DETAIL_LIST,
            &infos,
            &count,
        );
    }
    if (result != 0) {
        out.* = 0;
        return result;
    }
    out.* = count;
    return 0;
}

pub export fn TDNFInfo(
    handle: ?*Tdnf,
    scope: c_int,
    specs: ?[*]?[*:0]u8,
    output: ?*?*PackageInfo,
    count: ?*u32,
) callconv(.c) u32 {
    return listInternal(handle, scope, specs, output, count, DETAIL_INFO);
}

pub export fn TDNFList(
    handle: ?*Tdnf,
    scope: c_int,
    specs: ?[*]?[*:0]u8,
    output: ?*?*PackageInfo,
    count: ?*u32,
) callconv(.c) u32 {
    return listInternal(handle, scope, specs, output, count, DETAIL_LIST);
}

fn listInternal(
    handle_opt: ?*Tdnf,
    scope: c_int,
    specs: ?[*]?[*:0]u8,
    output_opt: ?*?*PackageInfo,
    count_opt: ?*u32,
    detail: c_uint,
) u32 {
    if (output_opt) |output| output.* = null;
    if (count_opt) |count| count.* = 0;
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pSack == null or specs == null or
        output_opt == null or count_opt == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var infos: ?*PackageInfo = null;
    var count: u32 = 0;
    var repos: ?[*]NativeRepoInput = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);

    var result = TDNFRefresh(handle);
    if (result == 0)
        result = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);
    if (result == 0) {
        result = TDNFRepoMdNativeListConfig(
            repos,
            repo_count,
            handle.pRpmConfig,
            scope,
            specs,
            detail,
            &infos,
            &count,
        );
    }
    if (result != 0) {
        if (infos != null) TDNFFreePackageInfoArray(infos, count);
        return result;
    }
    output_opt.?.* = infos;
    count_opt.?.* = count;
    return 0;
}

pub export fn TDNFOpenHandle(
    args_opt: ?*CmdArgs,
    output_opt: ?*?*Tdnf,
) callconv(.c) u32 {
    if (args_opt == null or output_opt == null) {
        if (output_opt) |output| output.* = null;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    const args = args_opt.?;
    const output = output_opt.?;
    gEuid = geteuid();
    GlobalSetQuiet(args.nQuiet);
    GlobalSetJson(args.nJsonOutput);

    var raw_handle: ?*anyopaque = null;
    var result = TDNFAllocateMemory(1, @sizeOf(Tdnf), &raw_handle);
    if (result != 0) {
        output.* = null;
        return result;
    }
    const handle: *Tdnf = @ptrCast(@alignCast(raw_handle.?));
    handle.pArgs = args;
    var sack: ?*anyopaque = null;
    var conf_path: ?[*:0]u8 = null;
    defer freeString(&conf_path);
    var rooted_conf_path: ?[*:0]u8 = null;
    defer freeString(&rooted_conf_path);
    var pinned_conf_path: ?[:0]u8 = null;
    defer if (pinned_conf_path) |path| std.heap.c_allocator.free(path);

    handle.pRpmConfig = tdnf_rpm_config_create(args.pszInstallRoot);
    if (handle.pRpmConfig == null) {
        common.log(LOG_ERR, "Failed to initialize native rpm configuration: %s\n", .{tdnf_rpm_config_last_error()});
        result = errors.ERROR_TDNF_RPMRC_FAIL;
    }
    if (result == 0 and commandRequiresTargetLock(args))
        result = bindTransactionTarget(handle);

    if (result == 0 and isNullOrEmpty(args.pszConfFile) and
        !isNullOrEmpty(args.pszInstallRoot) and
        !eqlZ(args.pszInstallRoot.?, "/"))
    {
        const config: *const txn_config.TxnConfig = @ptrCast(@alignCast(
            handle.pRpmConfig.?,
        ));
        if (config.pinnedInstallRootFd()) |root_fd| {
            pinned_conf_path = std.fmt.allocPrintSentinel(
                std.heap.c_allocator,
                "/proc/self/fd/{d}{s}",
                .{ root_fd, std.mem.span(config_file) },
                0,
            ) catch blk: {
                result = errors.ERROR_TDNF_OUT_OF_MEMORY;
                break :blk null;
            };
        } else {
            const nodes = [_]?[*:0]const u8{
                args.pszInstallRoot,
                config_file,
            };
            result = joinPath(&rooted_conf_path, &nodes);
        }
        var exists: c_int = 0;
        const candidate: ?[*:0]const u8 = if (pinned_conf_path) |path|
            path.ptr
        else
            rooted_conf_path;
        if (result == 0) result = TDNFIsFileOrSymlink(candidate, &exists);
        if (result == 0) {
            result = TDNFAllocateString(
                if (exists != 0) candidate else config_file,
                &conf_path,
            );
        }
    } else if (result == 0) {
        result = TDNFAllocateString(
            args.pszConfFile orelse config_file,
            &conf_path,
        );
    }

    if (result == 0)
        result = TDNFReadConfig(handle, conf_path, config_group);
    if (result == 0) {
        var node = handle.pArgs.?.cn_setopts.?.first_child;
        while (node) |current| : (node = current.next) {
            if (current.name != null and eqlZ(current.name.?, "rpmdefine")) {
                result = applyRpmDefine(handle, current.value);
                if (result != 0) break;
            }
        }
    }
    if (result == 0 and handle.pTransactionTargetLock != null)
        result = finalizeTransactionRpmDb(handle);
    if (result == 0) result = TDNFConfigExpandVars(handle);
    if (result == 0) {
        GlobalSetDnfCheckUpdateCompat(handle.pConf.?.nCheckUpdateCompat);
        result = TDNFLoadPlugins(handle);
    }
    if (result == 0) {
        result = TDNFPackageContextCreate(
            handle.pConf.?.pszCacheDir,
            handle.pArgs.?.pszInstallRoot,
            handle.pArgs.?.pszArch,
            handle.pRpmConfig,
            @intFromBool(args.nAllDeps == 0),
            &sack,
        );
    }
    if (result == 0) result = TDNFLoadRepoData(handle, &handle.pRepos);
    if (result == 0) result = TDNFRepoListFinalize(handle);
    if (result == 0)
        result = TDNFPackageContextInitCommandLine(sack, &handle.pCmdLineRepo);
    if (result == 0) {
        handle.pSack = sack;
        output.* = handle;
        return 0;
    }

    TDNFCloseHandle(handle);
    output.* = null;
    if (sack != null) TDNFPackageContextFree(sack);
    return result;
}

fn applyRpmDefine(handle_opt: ?*Tdnf, value: ?[*:0]const u8) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pRpmConfig == null or isNullOrEmpty(value))
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (tdnf_rpm_config_apply_define(handle.pRpmConfig, value) != 0) {
        common.log(LOG_ERR, "Invalid rpmdefine '%s': %s\n", .{ value.?, tdnf_rpm_config_last_error() });
        return errors.ERROR_TDNF_RPMRC_FAIL;
    }
    return 0;
}

fn finalizeTransactionRpmDb(handle: *Tdnf) u32 {
    if (tdnf_rpm_config_finalize_rpmdb_pin(handle.pRpmConfig) != 0) {
        common.log(
            LOG_ERR,
            "Failed to pin native rpm database: %s\n",
            .{tdnf_rpm_config_last_error()},
        );
        return errors.ERROR_TDNF_RPMRC_FAIL;
    }
    return 0;
}

pub export fn TDNFProvides(
    handle_opt: ?*Tdnf,
    spec: ?[*:0]const u8,
    output_opt: ?*?*PackageInfo,
) callconv(.c) u32 {
    if (output_opt) |output| output.* = null;
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pSack == null or isNullOrEmpty(spec) or output_opt == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var repos: ?[*]NativeRepoInput = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);
    var info: ?*PackageInfo = null;
    var result = TDNFRefresh(handle);
    if (result == 0)
        result = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);
    if (result == 0) {
        result = TDNFRepoMdNativeProvidesConfig(
            repos,
            repo_count,
            handle.pRpmConfig,
            spec,
            &info,
        );
    }
    if (result != 0) {
        TDNFFreePackageInfo(info);
        return if (result == errors.ERROR_TDNF_NO_MATCH)
            errors.ERROR_TDNF_NO_DATA
        else
            result;
    }
    output_opt.?.* = info;
    return 0;
}

pub export fn TDNFRepoList(
    handle_opt: ?*Tdnf,
    filter: c_uint,
    output_opt: ?*?*RepoData,
) callconv(.c) u32 {
    if (output_opt) |output| output.* = null;
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pRepos == null or output_opt == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var result_head: ?*RepoData = null;
    var result_tail: ?*RepoData = null;
    var repo = handle.pRepos;
    while (repo) |current| : (repo = current.pNext) {
        const add = filter == c.REPOLISTFILTER_ALL or
            (filter == c.REPOLISTFILTER_ENABLED and current.nEnabled != 0) or
            (filter == c.REPOLISTFILTER_DISABLED and current.nEnabled == 0);
        if (!add) continue;
        var clone: ?*RepoData = null;
        const result = TDNFCloneRepo(current, &clone);
        if (result != 0) {
            TDNFFreeRepos(result_head);
            return result;
        }
        if (result_head == null) {
            result_head = clone;
            result_tail = clone;
        } else {
            result_tail.?.pNext = clone;
            result_tail = clone;
        }
    }
    output_opt.?.* = result_head;
    return 0;
}

fn removeUnkeptRpm(
    path: [*:0]const u8,
    _: ?*const anyopaque,
    _: c_int,
    _: ?*anyopaque,
) callconv(.c) c_int {
    if (!std.mem.endsWith(u8, std.mem.span(path), ".rpm")) return 0;
    var marker: ?[*:0]u8 = null;
    defer freeString(&marker);
    var result = common.allocPrint(&marker, "%s.reposync-keep", .{path});
    if (result != 0) return @intCast(result);

    var marker_stat = std.mem.zeroes(std.c.Stat);
    if (stat(marker.?, &marker_stat) != 0) {
        if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT)) {
            common.log(LOG_INFO, "deleting %s\n", .{path});
            if (remove(path) < 0) {
                common.log(LOG_CRIT, "unable to remove %s: %s\n", .{ path, strerror(std.c._errno().*) });
            }
        } else {
            result = systemError();
            return @intCast(result);
        }
    } else if (remove(marker.?) < 0) {
        common.log(LOG_CRIT, "unable to remove %s: %s\n", .{ marker.?, strerror(std.c._errno().*) });
    }
    return 0;
}

pub export fn TDNFRepoSync(
    handle: ?*Tdnf,
    args: ?*RepoSyncArgs,
) callconv(.c) u32 {
    const result = repoSync(handle, args);
    return if (result == errors.ERROR_TDNF_NO_MATCH)
        errors.ERROR_TDNF_NO_DATA
    else
        result;
}

fn repoSync(
    handle_opt: ?*Tdnf,
    args_opt: ?*RepoSyncArgs,
) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = args_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pSack == null) return errors.ERROR_TDNF_INVALID_PARAMETER;

    var enabled_count: u32 = 0;
    var repo = handle.pRepos;
    while (repo) |current| : (repo = current.pNext) {
        if (current.pszId != null and
            eqlZ(current.pszId.?, std.mem.span(command_line_repo_name)))
            continue;
        if (current.nEnabled != 0) enabled_count += 1;
    }
    if (enabled_count > 1 and args.nNoRepoPath != 0) {
        common.log(LOG_CRIT, "cannot use norepopath with multiple repos\n", .{});
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (args.nDelete != 0 and args.nNoRepoPath != 0) {
        common.log(LOG_CRIT, "cannot use the delete option with norepopath\n", .{});
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (args.nSourceOnly != 0 and args.ppszArchs != null) {
        common.log(LOG_CRIT, "cannot use the source option with arch\n", .{});
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var repos: ?[*]NativeRepoInput = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);
    var infos: ?*PackageInfo = null;
    var info_count: u32 = 0;
    defer TDNFFreePackageInfoArray(infos, info_count);
    var root_path: ?[*:0]u8 = null;
    defer freeString(&root_path);
    var repo_dir: ?[*:0]u8 = null;
    defer freeString(&repo_dir);
    var directory: ?[*:0]u8 = null;
    defer freeString(&directory);
    var file_path: ?[*:0]u8 = null;
    defer freeString(&file_path);
    var marker: ?[*:0]u8 = null;
    defer freeString(&marker);
    var url: ?[*:0]u8 = null;
    defer freeString(&url);
    var rpm_file: ?*RpmFile = null;
    defer tdnf_rpm_file_close(rpm_file);

    var result = TDNFRefresh(handle);
    if (result == 0)
        result = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);
    if (result == 0) {
        result = TDNFRepoMdNativeListConfig(
            repos,
            repo_count,
            handle.pRpmConfig,
            c.SCOPE_ALL,
            null,
            DETAIL_LOCATION,
            &infos,
            &info_count,
        );
    }
    if (result != 0) return result;

    if (args.pszDownloadPath == null) {
        root_path = getcwd(null, 0);
        if (root_path == null) return systemError();
    } else {
        result = TDNFNormalizePath(args.pszDownloadPath, &root_path);
        if (result != 0) return result;
    }
    if (args.nNewestOnly != 0 and infos != null)
        _ = TDNFPkgInfoFilterNewest(handle.pSack, infos);

    var info = infos;
    while (info) |current| : (info = packageNext(current)) {
        if (current.pszRepoName != null and
            eqlZ(current.pszRepoName.?, std.mem.span(system_repo_name)))
            continue;
        if (args.ppszArchs != null) {
            var matched: c_int = 0;
            _ = TDNFStringMatchesOneOf(
                current.pszArch,
                @ptrCast(args.ppszArchs),
                &matched,
            );
            if (matched == 0) continue;
        } else if (args.nSourceOnly != 0) {
            if (current.pszArch == null or !eqlZ(current.pszArch.?, "src"))
                continue;
        }

        if (args.nPrintUrlsOnly == 0) {
            var package_repo: ?*RepoData = null;
            var keep_package = true;
            if (args.nNoRepoPath == 0) {
                const base: [*:0]const u8 = if (root_path != null and
                    !eqlZ(root_path.?, "/")) root_path.? else "";
                const nodes = [_]?[*:0]const u8{
                    base,
                    current.pszRepoName,
                };
                result = joinPath(&directory, &nodes);
            } else {
                result = TDNFAllocateString(root_path, &directory);
            }
            if (result != 0) return result;
            result = TDNFUtilsMakeDir(directory);
            if (result != 0) return result;
            result = TDNFFindRepoById(
                handle,
                current.pszRepoName,
                &package_repo,
            );
            if (result != 0) return result;
            result = TDNFDownloadPackageToTree(
                handle,
                current.pszLocation,
                current.pszName,
                package_repo,
                directory,
                &file_path,
            );
            if (result != 0) return result;

            if (args.nGPGCheck != 0) {
                var check_repo = package_repo.?.*;
                var policy_rejected: c_int = 0;
                check_repo.nGPGCheck = 1;
                result = TDNFGPGCheckPackageEx(
                    handle,
                    &check_repo,
                    file_path,
                    &rpm_file,
                    &policy_rejected,
                );
                tdnf_rpm_file_close(rpm_file);
                rpm_file = null;
                if (policy_rejected != 0) {
                    common.log(LOG_CRIT, "checking package %s failed: %d, deleting\n", .{ file_path.?, result });
                    if (remove(file_path.?) < 0) {
                        const errno_value = std.c._errno().*;
                        common.log(LOG_CRIT, "unable to remove %s: %s\n", .{ file_path.?, strerror(errno_value) });
                        return errors.ERROR_TDNF_SYSTEM_BASE +
                            @as(u32, @intCast(errno_value));
                    }
                    keep_package = false;
                    result = 0;
                } else if (result != 0) {
                    return result;
                }
            }

            if (args.nDelete != 0 and keep_package) {
                result = common.allocPrint(&marker, "%s.reposync-keep", .{file_path.?});
                if (result != 0) return result;
                result = TDNFTouchFile(marker);
                if (result != 0) return result;
                freeString(&marker);
            }
            freeString(&directory);
            freeString(&file_path);
        } else {
            var package_repo: ?*RepoData = null;
            result = TDNFFindRepoById(
                handle,
                current.pszRepoName,
                &package_repo,
            );
            if (result != 0) return result;
            result = TDNFCreatePackageUrl(
                package_repo,
                current.pszLocation,
                &url,
            );
            if (result != 0) return result;
            common.log(LOG_INFO, "%s\n", .{url.?});
            freeString(&url);
        }
    }

    if (args.nDelete != 0) {
        repo = handle.pRepos;
        while (repo) |current| : (repo = current.pNext) {
            if ((current.pszId != null and
                eqlZ(current.pszId.?, std.mem.span(command_line_repo_name))) or
                current.nEnabled == 0) continue;
            const base: [*:0]const u8 = if (root_path != null and
                !eqlZ(root_path.?, "/")) root_path.? else "";
            const nodes = [_]?[*:0]const u8{ base, current.pszId };
            result = joinPath(&repo_dir, &nodes);
            if (result != 0) return result;
            const walk_result = nftw(
                repo_dir.?,
                &removeUnkeptRpm,
                10,
                FTW_DEPTH | FTW_PHYS,
            );
            if (walk_result < 0) return systemError();
            if (walk_result != 0) return @intCast(walk_result);
            freeString(&repo_dir);
        }
    }

    if (args.nDownloadMetadata != 0) {
        repo = handle.pRepos;
        while (repo) |current| : (repo = current.pNext) {
            if ((current.pszId != null and
                eqlZ(current.pszId.?, std.mem.span(command_line_repo_name))) or
                current.nEnabled == 0) continue;
            if (args.nNoRepoPath == 0) {
                const metadata_base = args.pszMetaDataPath orelse root_path;
                const base: [*:0]const u8 = if (metadata_base != null and
                    !eqlZ(metadata_base.?, "/")) metadata_base.? else "";
                const nodes = [_]?[*:0]const u8{ base, current.pszId };
                result = joinPath(&repo_dir, &nodes);
            } else {
                result = TDNFAllocateString(
                    args.pszMetaDataPath orelse root_path,
                    &repo_dir,
                );
            }
            if (result != 0) return result;
            result = TDNFUtilsMakeDir(repo_dir);
            if (result != 0) return result;
            result = TDNFDownloadMetadata(
                handle,
                current,
                repo_dir,
                args.nPrintUrlsOnly,
            );
            if (result != 0) return result;
            freeString(&repo_dir);
        }
    }
    return 0;
}

pub export fn TDNFRepoQuery(
    handle_opt: ?*Tdnf,
    args_opt: ?*RepoQueryArgs,
    output_opt: ?*?*PackageInfo,
    count_opt: ?*u32,
) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = args_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pSack == null or output_opt == null or count_opt == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (args.nExtras != 0 and
        (args.nInstalled != 0 or args.nAvailable != 0 or
            args.nDuplicates != 0))
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (args.nDuplicates != 0 and
        (args.nInstalled != 0 or args.nAvailable != 0))
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (args.nUserInstalled != 0) args.nInstalled = 1;

    var repos: ?[*]NativeRepoInput = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);
    var infos: ?*PackageInfo = null;
    var count: u32 = 0;
    var result = TDNFRefresh(handle);
    if (result == 0)
        result = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);
    if (result == 0) {
        result = TDNFRepoMdNativeRepoQueryConfig(
            repos,
            repo_count,
            handle.pRpmConfig,
            args,
            &infos,
            &count,
        );
    }
    if (result == 0 and args.nUserInstalled != 0) {
        result = TDNFNativeQueryFilterUserInstalled(handle, infos, &count);
        if (result == 0 and count == 0) result = errors.ERROR_TDNF_NO_DATA;
    }
    if (result == 0 and args.nLocation != 0)
        result = TDNFNativeQueryApplyLocationUrls(handle, infos, count);
    if (result != 0) {
        if (infos != null) TDNFFreePackageInfoArray(infos, count);
        return if (result == errors.ERROR_TDNF_NO_MATCH)
            errors.ERROR_TDNF_NO_DATA
        else
            result;
    }
    output_opt.?.* = infos;
    count_opt.?.* = count;
    return 0;
}

pub export fn TDNFResolve(
    handle_opt: ?*Tdnf,
    requested_alter_type: c_uint,
    output_opt: ?*?*SolvedPackageInfo,
) callconv(.c) u32 {
    return resolve_service.resolveAlterType(
        handle_opt,
        requested_alter_type,
        output_opt,
    );
}

pub export fn TDNFSearchCommand(
    handle_opt: ?*Tdnf,
    args_opt: ?*CmdArgs,
    output_opt: ?*?*PackageInfo,
    count_opt: ?*u32,
) callconv(.c) u32 {
    if (output_opt) |output| output.* = null;
    if (count_opt) |count| count.* = 0;
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = args_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (output_opt == null or count_opt == null or handle.pSack == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var start: c_int = 1;
    if (args.nCmdCount > 1 and
        strncasecmp(args.ppszCmds.?[1].?, "all", 3) == 0)
        start = 2;
    var repos: ?[*]NativeRepoInput = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);
    var infos: ?*PackageInfo = null;
    var count: u32 = 0;
    var result = TDNFRefresh(handle);
    if (result == 0)
        result = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);
    if (result == 0) {
        result = TDNFRepoMdNativeSearchConfig(
            repos,
            repo_count,
            handle.pRpmConfig,
            args.ppszCmds,
            start,
            args.nCmdCount,
            &infos,
            &count,
        );
    }
    if (result != 0) {
        TDNFFreePackageInfoArray(infos, count);
        return if (result == errors.ERROR_TDNF_NO_MATCH)
            errors.ERROR_TDNF_NO_SEARCH_RESULTS
        else
            result;
    }
    output_opt.?.* = infos;
    count_opt.?.* = count;
    return 0;
}

pub export fn TDNFUpdateInfo(
    handle_opt: ?*Tdnf,
    specs: ?[*]?[*:0]u8,
    output_opt: ?*?*UpdateInfo,
) callconv(.c) u32 {
    if (output_opt) |output| output.* = null;
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pSack == null or output_opt == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var repos: ?[*]NativeRepoInput = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);
    var lines: ?[*]?[*:0]u8 = null;
    defer TDNFFreeStringArray(lines);
    var line_count: u32 = 0;
    var severity: ?[*:0]u8 = null;
    defer freeString(&severity);
    var infos: ?*UpdateInfo = null;
    var security: u32 = 0;
    var reboot_required: u32 = 0;

    var result = TDNFRefresh(handle);
    if (result == 0) {
        result = TDNFGetSecuritySeverityOption(
            handle,
            &security,
            &severity,
        );
    }
    if (result == 0)
        result = TDNFGetRebootRequiredOption(handle, &reboot_required);
    if (result == 0)
        result = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);
    if (result == 0) {
        result = TDNFRepoMdNativeUpdateInfoLinesConfig(
            repos,
            repo_count,
            handle.pRpmConfig,
            specs,
            security,
            severity,
            reboot_required,
            &lines,
            &line_count,
        );
        if (result == errors.ERROR_TDNF_NO_DATA)
            common.log(LOG_INFO, "\n0 updates.\n", .{});
    }
    if (result == 0)
        result = TDNFNativeQueryBuildUpdateInfo(lines, line_count, &infos);
    if (result != 0) {
        if (infos != null) TDNFFreeUpdateInfo(infos);
        return result;
    }
    output_opt.?.* = infos;
    return 0;
}

pub export fn TDNFHistoryResolve(
    handle_opt: ?*Tdnf,
    args_opt: ?*HistoryArgs,
    output_opt: ?*?*SolvedPackageInfo,
) callconv(.c) u32 {
    if (handle_opt) |handle| {
        TDNFTransactionPlanStateClear(handle.pTransactionPlanState);
        TDNFTransactionPlanRequestTraceDestroy(handle.pRequestTrace);
        handle.pRequestTrace = null;
    }
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = args_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const output = output_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;

    if (args.nCommand == c.HISTORY_CMD_ROLLBACK) {
        if (args.nTo <= 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    } else if (args.nCommand == c.HISTORY_CMD_UNDO or
        args.nCommand == c.HISTORY_CMD_REDO)
    {
        if (args.nFrom <= 1 or args.nFrom > args.nTo)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
    } else if (args.nCommand != c.HISTORY_CMD_INIT) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var result: u32 = 0;
    if (args.nCommand != c.HISTORY_CMD_INIT) {
        handle.pRequestTrace = TDNFTransactionPlanRequestTraceCreateHistory();
        result = resolve_service.checkTrace(handle);
        if (result == 0) result = resolve_service.rejectRepoFromDir(handle);
        if (result == 0) result = TDNFRefresh(handle);
    }

    var ctx: ?*HistoryCtx = null;
    defer destroy_history_ctx(ctx);
    if (result == 0) {
        result = TDNFGetHistoryCtx(
            handle,
            &ctx,
            @intFromBool(args.nCommand != c.HISTORY_CMD_INIT),
        );
    }
    if (result == 0 and history_sync_config(ctx, handle.pRpmConfig) != 0)
        result = errors.ERROR_TDNF_HISTORY_ERROR;
    if (result != 0) {
        resolve_service.handleResolveError(handle);
        return result;
    }
    if (args.nCommand == c.HISTORY_CMD_INIT) return 0;

    var delta: ?*HistoryDelta = null;
    defer history_free_delta(delta);
    var flags_delta: ?*HistoryFlagsDelta = null;
    defer history_free_flags_delta(flags_delta);
    switch (args.nCommand) {
        c.HISTORY_CMD_ROLLBACK => {
            delta = history_get_delta(ctx, args.nTo);
            flags_delta = history_get_flags_delta(
                ctx,
                history_get_current_transaction_id(ctx),
                args.nTo,
            );
        },
        c.HISTORY_CMD_UNDO => {
            delta = history_get_delta_range(ctx, args.nFrom - 1, args.nTo);
            flags_delta = history_get_flags_delta(
                ctx,
                args.nTo,
                args.nFrom - 1,
            );
        },
        c.HISTORY_CMD_REDO => {
            delta = history_get_delta_range(ctx, args.nTo, args.nFrom - 1);
            flags_delta = history_get_flags_delta(
                ctx,
                args.nFrom - 1,
                args.nTo,
            );
        },
        else => result = errors.ERROR_TDNF_INVALID_PARAMETER,
    }
    if (result == 0 and delta == null)
        result = errors.ERROR_TDNF_HISTORY_ERROR;

    var unresolved: ?[*]?[*:0]u8 = null;
    if (result == 0 and delta.?.added_count > 0) {
        result = allocatePointerArray(
            @intCast(delta.?.added_count + 1),
            &unresolved,
        );
    }
    var nevra_map: ?*HistoryNevraMap = null;
    defer history_free_nevra_map(nevra_map);
    if (result == 0) {
        nevra_map = history_nevra_map(ctx);
        if (nevra_map == null) result = errors.ERROR_TDNF_HISTORY_ERROR;
    }
    var repos: ?[*]NativeRepoInput = null;
    var repo_count: u32 = 0;
    defer TDNFNativeQueryFreeRepoInputs(repos, repo_count);
    if (result == 0)
        result = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);

    var install = IdList{};
    TDNFIdListInit(&install);
    defer TDNFIdListFree(&install);
    var erase = IdList{};
    TDNFIdListInit(&erase);
    defer TDNFIdListFree(&erase);
    var matches: ?[*]?[*:0]u8 = null;
    defer freeStringArray(&matches);
    var match_count: u32 = 0;
    var unresolved_count: u32 = 0;

    if (result == 0) {
        var index: c_int = 0;
        while (index < delta.?.added_count) : (index += 1) {
            const name = history_get_nevra(
                nevra_map,
                delta.?.added_ids.?[@intCast(index)],
            ) orelse {
                result = errors.ERROR_TDNF_HISTORY_ERROR;
                break;
            };
            if (std.mem.startsWith(u8, std.mem.span(name), "gpg-pubkey-"))
                continue;
            const trace_start = install.dwCount;
            var outcome: c_int =
                transaction_plan_abi.request_outcome.satisfied;
            var candidates = IdList{};
            TDNFIdListInit(&candidates);
            defer TDNFIdListFree(&candidates);
            result = TDNFRepoMdNativeFindNevraMatchesConfig(
                repos,
                repo_count,
                handle.pRpmConfig,
                name,
                TDNF_NEVRA_UNINSTALLED,
                &matches,
                &match_count,
            );
            if (result != 0) break;
            result = TDNFNativeQueryResolvePackageRefArrayToQueue(
                handle.pSack,
                matches,
                match_count,
                0,
                &candidates,
            );
            if (result != 0) break;
            if (candidates.dwCount == 0) {
                result = TDNFAddNotResolved(unresolved, name);
                if (result != 0) break;
                outcome =
                    transaction_plan_abi.request_outcome.no_candidate;
                unresolved_count += 1;
            } else {
                freeStringArray(&matches);
                match_count = 0;
                var installed = IdList{};
                TDNFIdListInit(&installed);
                defer TDNFIdListFree(&installed);
                result = TDNFRepoMdNativeFindNevraMatchesConfig(
                    repos,
                    repo_count,
                    handle.pRpmConfig,
                    name,
                    TDNF_NEVRA_INSTALLED,
                    &matches,
                    &match_count,
                );
                if (result != 0) break;
                result = TDNFNativeQueryResolvePackageRefArrayToQueue(
                    handle.pSack,
                    matches,
                    match_count,
                    1,
                    &installed,
                );
                if (result != 0) break;
                if (installed.dwCount == 0) {
                    result = TDNFIdListPush(
                        &install,
                        candidates.pnElements.?[0],
                    );
                    if (result != 0) break;
                    outcome =
                        transaction_plan_abi.request_outcome.queued;
                }
            }
            freeStringArray(&matches);
            match_count = 0;
            TDNFTransactionPlanRequestTraceRecordHistoryGoal(
                handle.pRequestTrace,
                name,
                transaction_plan_abi.request_kind.install,
                transaction_plan_abi.job_action.install,
                install.pnElements,
                trace_start,
                install.dwCount,
                @intCast(outcome),
            );
        }
    }

    if (result == 0) {
        var index: c_int = 0;
        while (index < delta.?.removed_count) : (index += 1) {
            const name = history_get_nevra(
                nevra_map,
                delta.?.removed_ids.?[@intCast(index)],
            ) orelse {
                result = errors.ERROR_TDNF_HISTORY_ERROR;
                break;
            };
            if (std.mem.startsWith(u8, std.mem.span(name), "gpg-pubkey-"))
                continue;
            const trace_start = erase.dwCount;
            result = TDNFRepoMdNativeFindNevraMatchesConfig(
                repos,
                repo_count,
                handle.pRpmConfig,
                name,
                TDNF_NEVRA_INSTALLED,
                &matches,
                &match_count,
            );
            if (result != 0) break;
            result = TDNFNativeQueryResolvePackageRefArrayToQueue(
                handle.pSack,
                matches,
                match_count,
                1,
                &erase,
            );
            if (result != 0) break;
            const outcome: u32 = if (erase.dwCount == trace_start)
                transaction_plan_abi.request_outcome.satisfied
            else
                transaction_plan_abi.request_outcome.queued;
            freeStringArray(&matches);
            match_count = 0;
            TDNFTransactionPlanRequestTraceRecordHistoryGoal(
                handle.pRequestTrace,
                name,
                transaction_plan_abi.request_kind.erase,
                transaction_plan_abi.job_action.erase,
                erase.pnElements,
                trace_start,
                erase.dwCount,
                outcome,
            );
        }
    }

    var solved: ?*SolvedPackageInfo = null;
    if (result == 0) {
        result = TDNFHistoryGoalWithUnresolved(
            handle,
            &install,
            &erase,
            unresolved_count,
            &solved,
        );
    }
    if (result == 0) {
        const info = solved.?;
        info.nNeedAction = @intFromBool(
            info.pPkgsToInstall != null or
                info.pPkgsToUpgrade != null or
                info.pPkgsToDowngrade != null or
                info.pPkgsToRemove != null or
                info.pPkgsUnNeeded != null or
                info.pPkgsToReinstall != null or
                info.pPkgsObsoleted != null,
        );
        info.nNeedDownload = @intFromBool(
            info.pPkgsToInstall != null or
                info.pPkgsToUpgrade != null or
                info.pPkgsToDowngrade != null or
                info.pPkgsToReinstall != null,
        );
        if (info.nNeedAction == 0)
            info.nNeedAction = @intFromBool(
                flags_delta != null and flags_delta.?.count > 0,
            );
        result = resolve_service.publishPlan(handle);
        if (result == 0) {
            info.ppszPkgsNotResolved = @ptrCast(unresolved);
            output.* = info;
            return 0;
        }
    }

    resolve_service.handleResolveError(handle);
    if (solved != null) TDNFFreeSolvedPackageInfo(solved);
    freeStringArray(&unresolved);
    return result;
}

pub export fn TDNFHistoryList(
    handle_opt: ?*Tdnf,
    args_opt: ?*HistoryArgs,
    output_opt: ?*?*HistoryInfo,
) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = args_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const output = output_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (args.nFrom < 0 or args.nTo < 0)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (args.nFrom != 0 and args.nTo != 0 and args.nFrom > args.nTo)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var ctx: ?*HistoryCtx = null;
    defer destroy_history_ctx(ctx);
    var result = TDNFGetHistoryCtx(handle, &ctx, 1);
    if (result != 0) return result;
    var transactions: ?[*]HistoryTransaction = null;
    var count: c_int = 0;
    defer history_free_transactions(transactions, count);
    if (history_get_transactions(
        ctx,
        &transactions,
        &count,
        args.nReverse,
        args.nFrom,
        args.nTo,
    ) != 0) return errors.ERROR_TDNF_HISTORY_ERROR;

    var raw_items: ?*anyopaque = null;
    result = TDNFAllocateMemory(
        @intCast(count),
        @sizeOf(HistoryInfoItem),
        &raw_items,
    );
    if (result != 0) return result;
    const items: [*]HistoryInfoItem = @ptrCast(@alignCast(raw_items.?));
    var transferred = false;
    defer if (!transferred) TDNFFreeHistoryInfoItems(items, count);

    var nevra_map: ?*HistoryNevraMap = null;
    defer history_free_nevra_map(nevra_map);
    if (args.nInfo != 0) nevra_map = history_nevra_map(ctx);

    var index: c_int = 0;
    while (index < count) : (index += 1) {
        const transaction = &transactions.?[@intCast(index)];
        const item = &items[@intCast(index)];
        item.nId = transaction.id;
        item.nType = transaction.type;
        result = TDNFAllocateString(
            transaction.cmdline orelse "(none)",
            &item.pszCmdLine,
        );
        if (result != 0) return result;
        item.timeStamp = transaction.timestamp;
        item.nAddedCount = transaction.delta.added_count;
        item.nRemovedCount = transaction.delta.removed_count;
        if (nevra_map == null) continue;

        if (transaction.delta.added_count > 0) {
            var raw_added: ?*anyopaque = null;
            result = TDNFAllocateMemory(
                @intCast(transaction.delta.added_count),
                @sizeOf(?[*:0]u8),
                &raw_added,
            );
            if (result != 0) return result;
            item.ppszAddedPkgs = @ptrCast(@alignCast(raw_added.?));
            var package_index: c_int = 0;
            while (package_index < transaction.delta.added_count) : (package_index += 1) {
                result = TDNFAllocateString(
                    history_get_nevra(
                        nevra_map,
                        transaction.delta.added_ids.?[
                            @intCast(package_index)
                        ],
                    ),
                    &item.ppszAddedPkgs.?[@intCast(package_index)],
                );
                if (result != 0) return result;
            }
        }
        if (transaction.delta.removed_count > 0) {
            var raw_removed: ?*anyopaque = null;
            result = TDNFAllocateMemory(
                @intCast(transaction.delta.removed_count),
                @sizeOf(?[*:0]u8),
                &raw_removed,
            );
            if (result != 0) return result;
            item.ppszRemovedPkgs = @ptrCast(@alignCast(raw_removed.?));
            var package_index: c_int = 0;
            while (package_index < transaction.delta.removed_count) : (package_index += 1) {
                result = TDNFAllocateString(
                    history_get_nevra(
                        nevra_map,
                        transaction.delta.removed_ids.?[
                            @intCast(package_index)
                        ],
                    ),
                    &item.ppszRemovedPkgs.?[@intCast(package_index)],
                );
                if (result != 0) return result;
            }
        }
    }

    var raw_info: ?*anyopaque = null;
    result = TDNFAllocateMemory(
        @intCast(count),
        @sizeOf(HistoryInfo),
        &raw_info,
    );
    if (result != 0) return result;
    const info: *HistoryInfo = @ptrCast(@alignCast(raw_info.?));
    info.nItemCount = count;
    info.pItems = items;
    output.* = info;
    transferred = true;
    return 0;
}

pub export fn TDNFGetPackageUrls(
    handle_opt: ?*Tdnf,
    solved_opt: ?*SolvedPackageInfo,
    output_opt: ?*?[*]?[*:0]u8,
    count_opt: ?*c_int,
) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const solved = solved_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const output = output_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const count_output = count_opt orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const lists = [_][*c]PackageInfo{
        solved.pPkgsToInstall,
        solved.pPkgsToUpgrade,
        solved.pPkgsToDowngrade,
        solved.pPkgsToReinstall,
    };
    var count: c_int = 0;
    for (lists) |head| {
        var info: ?*PackageInfo = if (head == null) null else @ptrCast(head);
        while (info) |current| : (info = packageNext(current)) {
            if (!isNullOrEmpty(current.pszLocation) and
                current.pszLocation[0] != '/')
                count += 1;
        }
    }

    var urls: ?[*]?[*:0]u8 = null;
    var result = allocatePointerArray(@intCast(count + 1), &urls);
    if (result != 0) return result;
    var index: usize = 0;
    var url: ?[*:0]u8 = null;
    defer freeString(&url);
    for (lists) |head| {
        var info: ?*PackageInfo = if (head == null) null else @ptrCast(head);
        while (info) |current| : (info = packageNext(current)) {
            if (isNullOrEmpty(current.pszLocation) or
                current.pszLocation[0] == '/')
                continue;
            var repo: ?*RepoData = null;
            result = TDNFFindRepoById(handle, current.pszRepoName, &repo);
            if (result != 0) {
                TDNFFreeStringArray(urls);
                return result;
            }
            result = TDNFCreatePackageUrl(repo, current.pszLocation, &url);
            if (result != 0) {
                TDNFFreeStringArray(urls);
                return result;
            }
            urls.?[index] = url;
            url = null;
            index += 1;
        }
    }
    output.* = urls;
    count_output.* = count;
    return 0;
}

pub export fn TDNFHistoryGetId(
    handle_opt: ?*Tdnf,
    output_opt: ?*c_int,
) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const output = output_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var ctx: ?*HistoryCtx = null;
    defer destroy_history_ctx(ctx);
    const result = TDNFGetHistoryCtx(handle, &ctx, 1);
    if (result != 0) return result;
    output.* = history_get_current_transaction_id(ctx);
    return 0;
}

pub export fn TDNFMark(
    handle_opt: ?*Tdnf,
    specs: ?[*]?[*:0]u8,
    value: u32,
) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pSack == null or specs == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var infos: ?*PackageInfo = null;
    var count: u32 = 0;
    defer if (infos != null) TDNFFreePackageInfoArray(infos, count);
    var result = TDNFRepoMdNativeListConfig(
        null,
        0,
        handle.pRpmConfig,
        c.SCOPE_INSTALLED,
        specs,
        DETAIL_LIST,
        &infos,
        &count,
    );
    if (result != 0) return result;
    if (count == 0) return errors.ERROR_TDNF_NO_MATCH;

    var command_line: ?[*:0]u8 = null;
    defer freeString(&command_line);
    result = TDNFJoinArrayToString(
        handle.pArgs.?.ppszArgv.? + 1,
        " ",
        handle.pArgs.?.nArgc,
        &command_line,
    );
    if (result != 0) return result;
    var ctx: ?*HistoryCtx = null;
    defer destroy_history_ctx(ctx);
    result = TDNFGetHistoryCtx(handle, &ctx, 1);
    if (result != 0) return result;
    _ = history_add_transaction(ctx, command_line);

    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const info = &@as([*]PackageInfo, @ptrCast(infos.?))[index];
        common.log(LOG_INFO, "marking %s as %sinstalled\n", .{ info.pszName.?, if (value != 0) "auto" else "user" });
        if (history_set_auto_flag(ctx, info.pszName, @bitCast(value)) != 0)
            return errors.ERROR_TDNF_HISTORY_ERROR;
    }
    return 0;
}

pub export fn TDNFCloseHandle(handle_opt: ?*Tdnf) callconv(.c) void {
    if (handle_opt) |handle| {
        if (handle.pRepos != null) TDNFFreeReposInternal(handle.pRepos);
        if (handle.pConf != null) TDNFFreeConfig(handle.pConf);
        if (handle.pSack != null) TDNFPackageContextFree(handle.pSack);
        releaseTransactionTarget(handle);
        TDNFFreePlugins(handle.pPlugins);
        TDNFFreeStringArray(handle.ppszRepoFromDirIds);
        TDNFFreeStringArray(handle.ppszHiddenRefs);
        handle.dwHiddenRefCount = 0;
        TDNFFreeStringArrayWithCount(
            handle.ppszCmdLinePkgPaths,
            @intCast(handle.dwCmdLinePkgCount),
        );
        handle.ppszCmdLinePkgPaths = null;
        if (handle.pdwCmdLinePkgIds) |ids| TDNFFreeMemory(@ptrCast(ids));
        handle.pdwCmdLinePkgIds = null;
        handle.dwCmdLinePkgCount = 0;
        TDNFTransactionPlanRequestTraceDestroy(handle.pRequestTrace);
        TDNFTransactionPlanStateDestroy(handle.pTransactionPlanState);
        TDNFFreeMemory(handle);
    }
}

pub export fn TDNFGetVersion() callconv(.c) [*:0]const u8 {
    return @ptrCast(options.project_version.ptr);
}

pub export fn TDNFGetPackageName() callconv(.c) [*:0]const u8 {
    return @ptrCast(options.project_name.ptr);
}

fn recordCmdLinePkgPathWithOps(
    handle_opt: ?*Tdnf,
    package_id: u32,
    path: ?[*:0]const u8,
    ops: CmdLinePkgPathOps,
) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (isNullOrEmpty(path)) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const count = handle.dwCmdLinePkgCount;

    var raw_ids: ?*anyopaque = if (handle.pdwCmdLinePkgIds) |ids|
        @ptrCast(ids)
    else
        null;
    var result = ops.reallocate(
        ops.context,
        (@as(usize, count) + 1) * @sizeOf(u32),
        &raw_ids,
    );
    handle.pdwCmdLinePkgIds = if (raw_ids) |ids|
        @ptrCast(@alignCast(ids))
    else
        null;
    if (result != 0) {
        clearCmdLinePkgPathsWithOps(handle, ops);
        return result;
    }

    var raw_paths: ?*anyopaque = if (handle.ppszCmdLinePkgPaths) |paths|
        @ptrCast(paths)
    else
        null;
    result = ops.reallocate(
        ops.context,
        (@as(usize, count) + 1) * @sizeOf(?[*:0]u8),
        &raw_paths,
    );
    handle.ppszCmdLinePkgPaths = if (raw_paths) |paths|
        @ptrCast(@alignCast(paths))
    else
        null;
    if (result != 0) {
        clearCmdLinePkgPathsWithOps(handle, ops);
        return result;
    }
    result = ops.allocateString(
        ops.context,
        path,
        &handle.ppszCmdLinePkgPaths.?[count],
    );
    if (result != 0) {
        clearCmdLinePkgPathsWithOps(handle, ops);
        return result;
    }
    handle.pdwCmdLinePkgIds.?[count] = package_id;
    handle.dwCmdLinePkgCount = count + 1;
    return 0;
}

const CmdLinePkgPathOps = struct {
    context: ?*anyopaque = null,
    reallocate: *const fn (
        ?*anyopaque,
        usize,
        *?*anyopaque,
    ) u32,
    allocateString: *const fn (
        ?*anyopaque,
        ?[*:0]const u8,
        *?[*:0]u8,
    ) u32,
    freeStringArray: *const fn (
        ?*anyopaque,
        ?[*]?[*:0]u8,
        c_int,
    ) void,
    freeMemory: *const fn (?*anyopaque, ?*anyopaque) void,
};

fn productionReallocate(
    _: ?*anyopaque,
    size: usize,
    output: *?*anyopaque,
) u32 {
    return TDNFReAllocateMemory(size, output);
}

fn productionAllocateString(
    _: ?*anyopaque,
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    return TDNFAllocateString(source, output);
}

fn productionFreeStringArray(
    _: ?*anyopaque,
    values: ?[*]?[*:0]u8,
    count: c_int,
) void {
    TDNFFreeStringArrayWithCount(values, count);
}

fn productionFreeMemory(_: ?*anyopaque, memory: ?*anyopaque) void {
    TDNFFreeMemory(memory);
}

const production_cmdline_ops = CmdLinePkgPathOps{
    .reallocate = &productionReallocate,
    .allocateString = &productionAllocateString,
    .freeStringArray = &productionFreeStringArray,
    .freeMemory = &productionFreeMemory,
};

pub fn recordCmdLinePkgPath(
    handle_opt: ?*Tdnf,
    package_id: u32,
    path: ?[*:0]const u8,
) u32 {
    return recordCmdLinePkgPathWithOps(
        handle_opt,
        package_id,
        path,
        production_cmdline_ops,
    );
}

fn clearCmdLinePkgPathsWithOps(
    handle: *Tdnf,
    ops: CmdLinePkgPathOps,
) void {
    ops.freeStringArray(
        ops.context,
        handle.ppszCmdLinePkgPaths,
        @intCast(handle.dwCmdLinePkgCount),
    );
    handle.ppszCmdLinePkgPaths = null;
    if (handle.pdwCmdLinePkgIds) |ids|
        ops.freeMemory(ops.context, @ptrCast(ids));
    handle.pdwCmdLinePkgIds = null;
    handle.dwCmdLinePkgCount = 0;
}

const FailingCmdLineAllocator = struct {
    calls: usize = 0,
    fail_at: usize,
    ids: [2]u32 = undefined,
    paths: [2]?[*:0]u8 = .{ null, null },

    fn shouldFail(self: *FailingCmdLineAllocator) bool {
        self.calls += 1;
        return self.calls == self.fail_at;
    }

    fn reallocate(
        context: ?*anyopaque,
        size: usize,
        output: *?*anyopaque,
    ) u32 {
        const self: *FailingCmdLineAllocator = @ptrCast(@alignCast(context.?));
        if (self.shouldFail()) {
            output.* = null;
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        }
        _ = size;
        output.* = if (self.calls == 1)
            @ptrCast(&self.ids)
        else
            @ptrCast(&self.paths);
        return 0;
    }

    fn allocateString(
        context: ?*anyopaque,
        source: ?[*:0]const u8,
        output: *?[*:0]u8,
    ) u32 {
        const self: *FailingCmdLineAllocator = @ptrCast(@alignCast(context.?));
        if (self.shouldFail()) {
            output.* = null;
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        }
        _ = source;
        output.* = null;
        return 0;
    }

    fn freeRecordedStrings(
        context: ?*anyopaque,
        values: ?[*]?[*:0]u8,
        count: c_int,
    ) void {
        _ = context;
        const array = values orelse return;
        _ = array;
        _ = count;
    }

    fn freeMemory(context: ?*anyopaque, memory: ?*anyopaque) void {
        _ = context;
        _ = memory;
    }

    fn ops(self: *FailingCmdLineAllocator) CmdLinePkgPathOps {
        return .{
            .context = self,
            .reallocate = &reallocate,
            .allocateString = &allocateString,
            .freeStringArray = &freeRecordedStrings,
            .freeMemory = &freeMemory,
        };
    }
};

test "record command-line path clears parallel arrays on every allocation failure" {
    inline for (1..4) |fail_at| {
        var failing = FailingCmdLineAllocator{
            .fail_at = fail_at,
        };
        var handle = Tdnf{};
        const result = recordCmdLinePkgPathWithOps(
            &handle,
            7,
            "/package.rpm",
            failing.ops(),
        );
        try std.testing.expectEqual(errors.ERROR_TDNF_OUT_OF_MEMORY, result);
        try std.testing.expectEqual(@as(?[*]u32, null), handle.pdwCmdLinePkgIds);
        try std.testing.expectEqual(
            @as(?[*]?[*:0]u8, null),
            handle.ppszCmdLinePkgPaths,
        );
        try std.testing.expectEqual(@as(u32, 0), handle.dwCmdLinePkgCount);
    }
}

test "normal handle target lock spans the handle lifetime" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/custom/rpm");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/custom/rpm/rpmdb.sqlite",
        .data = "",
    });
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    var args = CmdArgs{ .pszInstallRoot = root_z.ptr };
    const original_root = args.pszInstallRoot;
    const config = tdnf_rpm_config_create(root_z.ptr) orelse
        return error.TestUnexpectedResult;
    var handle = Tdnf{
        .pArgs = &args,
        .pRpmConfig = config,
    };
    try std.testing.expectEqual(@as(u32, 0), bindTransactionTarget(&handle));
    defer if (handle.pTransactionTargetLock != null)
        releaseTransactionTarget(&handle);
    try std.testing.expect(handle.pTransactionTargetLock != null);
    const pinned: *txn_config.TxnConfig = @ptrCast(@alignCast(
        handle.pRpmConfig.?,
    ));
    try std.testing.expect(pinned.pinnedInstallRootFd() != null);
    try std.testing.expect(pinned.pinnedRpmDbDirFd() == null);
    try pinned.setMacro(.dbpath, "/custom/rpm");
    try std.testing.expectEqual(
        @as(u32, 0),
        finalizeTransactionRpmDb(&handle),
    );
    try std.testing.expect(pinned.pinnedRpmDbDirFd() != null);
    try std.testing.expectError(
        error.InvalidMacroValue,
        pinned.setMacro(.dbpath, "/var/lib/rpm"),
    );

    var contender = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer contender.deinit();
    try std.testing.expectError(
        error.WouldBlock,
        transaction_lock.tryAcquireInDirectory(
            std.testing.allocator,
            &contender,
            "",
        ),
    );

    releaseTransactionTarget(&handle);
    try std.testing.expectEqual(original_root, args.pszInstallRoot);
    try std.testing.expect(handle.pRpmConfig == null);
    try std.testing.expect(handle.pTransactionTargetLock == null);
}

test "only transaction commands require a handle-lifetime root lock" {
    inline for (.{
        "install",
        "erase",
        "update",
        "downgrade",
        "distro-sync",
        "reinstall",
        "autoremove",
        "history",
        "mark",
        "plan",
    }) |name| {
        var commands = [_]?[*:0]u8{
            @ptrCast(@constCast(name.ptr)),
            null,
        };
        const args = CmdArgs{ .ppszCmds = &commands, .nCmdCount = 1 };
        try std.testing.expect(commandRequiresTargetLock(&args));
    }
    inline for (.{
        "check",
        "check-update",
        "count",
        "help",
        "info",
        "list",
        "provides",
        "repolist",
        "repoquery",
        "reposync",
        "search",
        "updateinfo",
    }) |name| {
        var commands = [_]?[*:0]u8{
            @ptrCast(@constCast(name.ptr)),
            null,
        };
        const args = CmdArgs{ .ppszCmds = &commands, .nCmdCount = 1 };
        try std.testing.expect(!commandRequiresTargetLock(&args));
    }
}
