//! The single native resolve-only service.
//!
//! Every resolve in tdnf funnels through `resolve` below: it owns operation
//! validation and normalization, request-trace setup, repository refresh,
//! command-line rpm staging, solver job preparation, the native solve, the
//! download-cache policy check, and transaction-plan capture/publication.
//!
//! The service never executes a transaction and never mutates the target root
//! or rpmdb. `TDNFResolve` in `api.zig` is a thin adapter over it, and the
//! public Zig resolver added for issue #186 calls the same service so that the
//! canonical plan produced by either caller is identical.

const std = @import("std");
const common = @import("tdnf_common");
const abi = @import("client_abi");
const errors = @import("tdnf_error");
const transaction_plan_abi = @import("transaction_plan_capture_abi");
const api = @import("api.zig");

const c = abi.C;
const IdList = abi.IdList;
const RepoData = abi.RepoData;
const SolvedPackageInfo = abi.SolvedPackageInfo;
const Tdnf = abi.Tdnf;

const LOG_ERR: c_int = 1;

const command_line_repo_name: [*:0]const u8 = "@cmdline";

extern fn TDNFAllocateMemory(
    count: usize,
    size: usize,
    output: *?*anyopaque,
) callconv(.c) u32;
extern fn TDNFAllocateString(
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFFreeMemory(memory: ?*anyopaque) callconv(.c) void;
extern fn TDNFFreeStringArray(values: ?[*]?[*:0]u8) callconv(.c) void;
extern fn TDNFFreeStringArrayWithCount(
    values: ?[*]?[*:0]u8,
    count: c_int,
) callconv(.c) void;
extern fn TDNFFreeSolvedPackageInfo(
    solved: ?*SolvedPackageInfo,
) callconv(.c) void;

extern fn TDNFIdListInit(list: *IdList) callconv(.c) void;
extern fn TDNFIdListFree(list: *IdList) callconv(.c) void;
extern fn TDNFIdListPush(list: *IdList, value: i32) callconv(.c) u32;

extern fn TDNFRefresh(handle: ?*Tdnf) callconv(.c) u32;
extern fn TDNFFindRepoById(
    handle: ?*Tdnf,
    id: ?[*:0]const u8,
    output: *?*RepoData,
) callconv(.c) u32;
extern fn TDNFDownloadPackageToCacheFd(
    handle: ?*Tdnf,
    location: ?[*:0]const u8,
    name: ?[*:0]const u8,
    repo: ?*RepoData,
    output: *?[*:0]u8,
    output_fd: *c_int,
) callconv(.c) u32;
extern fn TDNFIsFileOrSymlink(
    path: ?[*:0]const u8,
    result: *c_int,
) callconv(.c) u32;
extern fn TDNFUriIsRemote(
    value: ?[*:0]const u8,
    remote: *c_int,
) callconv(.c) u32;
extern fn TDNFPathFromUri(
    value: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFPackageContextAddRpm(
    context: ?*anyopaque,
    repository: ?*anyopaque,
    path: ?[*:0]const u8,
    output: *u32,
) callconv(.c) u32;
extern fn TDNFPackageContextAddRpmFd(
    context: ?*anyopaque,
    repository: ?*anyopaque,
    path: ?[*:0]const u8,
    fd: c_int,
    output: *u32,
) callconv(.c) u32;

extern fn TDNFPrepareAllPackages(
    handle: ?*Tdnf,
    alter_type: *c_uint,
    unresolved: ?[*]?[*:0]u8,
    queue: *IdList,
) callconv(.c) u32;
extern fn TDNFResolveBuildDependencies(
    handle: ?*Tdnf,
    specs: ?[*]?[*:0]u8,
    unresolved: ?[*]?[*:0]u8,
    queue: *IdList,
) callconv(.c) u32;
extern fn TDNFGoal(
    handle: ?*Tdnf,
    queue: *IdList,
    output: *?*SolvedPackageInfo,
    alter_type: c_uint,
    unresolved: c_int,
) callconv(.c) u32;
extern fn TDNFGoalNoDeps(
    handle: ?*Tdnf,
    queue: *IdList,
    output: *?*SolvedPackageInfo,
) callconv(.c) u32;
extern fn TDNFGetAvailableCacheBytes(
    conf: ?*abi.Conf,
    available: *u64,
) callconv(.c) u32;
extern fn TDNFGetAvailableCacheBytesHandle(
    handle: ?*Tdnf,
    available: *u64,
) callconv(.c) u32;
extern fn TDNFCheckDownloadCacheBytes(
    solved: ?*SolvedPackageInfo,
    available: u64,
) callconv(.c) u32;

extern fn TDNFTransactionPlanStateIsEnabled(
    state: ?*const anyopaque,
) callconv(.c) u32;
extern fn TDNFTransactionPlanStateClear(state: ?*anyopaque) callconv(.c) void;
extern fn TDNFTransactionPlanStatePublish(
    state: ?*anyopaque,
) callconv(.c) u32;
extern fn TDNFTransactionPlanStatePublishProblem(
    state: ?*anyopaque,
) callconv(.c) u32;
extern fn TDNFTransactionPlanRequestTraceCreate(
    alter_type: u32,
    subjects: ?*const anyopaque,
    count: u32,
) callconv(.c) ?*anyopaque;
extern fn TDNFTransactionPlanRequestTraceDestroy(
    trace: ?*anyopaque,
) callconv(.c) void;
extern fn TDNFTransactionPlanRequestTraceGetError(
    trace: ?*const anyopaque,
) callconv(.c) u32;
extern fn TDNFTransactionPlanRequestTraceRecordGoalRange(
    trace: ?*anyopaque,
    ids: ?[*]const i32,
    start: u32,
    end: u32,
    alter_type: u32,
    reason: u32,
    request_ref: u32,
) callconv(.c) void;
extern fn TDNFTransactionPlanRequestTraceRecordRequestOutcome(
    trace: ?*anyopaque,
    request_ref: u32,
    outcome: u32,
) callconv(.c) void;

extern fn fnmatch(
    pattern: [*:0]const u8,
    value: [*:0]const u8,
    flags: c_int,
) callconv(.c) c_int;
extern fn realpath(
    path: [*:0]const u8,
    resolved: ?[*]u8,
) callconv(.c) ?[*:0]u8;
extern fn basename(path: [*:0]u8) callconv(.c) [*:0]u8;

/// The typed transaction operation the resolver understands.
///
/// This is the internal spelling of the historical `ALTER_*` numbers. Callers
/// outside `api.zig` should always pass an `Operation`; the numeric form only
/// survives where it crosses the remaining private cross-module ABI.
pub const Operation = enum {
    autoerase,
    autoerase_all,
    downgrade,
    downgrade_all,
    erase,
    install,
    reinstall,
    upgrade,
    upgrade_all,
    distro_sync,
    obsoleted,

    /// Maps a private-ABI `ALTER_*` value onto the typed operation, or null
    /// when the value is not a transaction operation the resolver supports.
    pub fn fromAlterType(raw: c_uint) ?Operation {
        return switch (raw) {
            @as(c_uint, @intCast(c.ALTER_AUTOERASE)) => .autoerase,
            @as(c_uint, @intCast(c.ALTER_AUTOERASEALL)) => .autoerase_all,
            @as(c_uint, @intCast(c.ALTER_DOWNGRADE)) => .downgrade,
            @as(c_uint, @intCast(c.ALTER_DOWNGRADEALL)) => .downgrade_all,
            @as(c_uint, @intCast(c.ALTER_ERASE)) => .erase,
            @as(c_uint, @intCast(c.ALTER_INSTALL)) => .install,
            @as(c_uint, @intCast(c.ALTER_REINSTALL)) => .reinstall,
            @as(c_uint, @intCast(c.ALTER_UPGRADE)) => .upgrade,
            @as(c_uint, @intCast(c.ALTER_UPGRADEALL)) => .upgrade_all,
            @as(c_uint, @intCast(c.ALTER_DISTRO_SYNC)) => .distro_sync,
            @as(c_uint, @intCast(c.ALTER_OBSOLETED)) => .obsoleted,
            else => null,
        };
    }

    /// The private-ABI `ALTER_*` value for this operation.
    pub fn alterType(self: Operation) c_uint {
        return switch (self) {
            .autoerase => @intCast(c.ALTER_AUTOERASE),
            .autoerase_all => @intCast(c.ALTER_AUTOERASEALL),
            .downgrade => @intCast(c.ALTER_DOWNGRADE),
            .downgrade_all => @intCast(c.ALTER_DOWNGRADEALL),
            .erase => @intCast(c.ALTER_ERASE),
            .install => @intCast(c.ALTER_INSTALL),
            .reinstall => @intCast(c.ALTER_REINSTALL),
            .upgrade => @intCast(c.ALTER_UPGRADE),
            .upgrade_all => @intCast(c.ALTER_UPGRADEALL),
            .distro_sync => @intCast(c.ALTER_DISTRO_SYNC),
            .obsoleted => @intCast(c.ALTER_OBSOLETED),
        };
    }

    /// True when the operation is meaningless without explicit subjects.
    pub fn requiresSubjects(self: Operation) bool {
        return switch (self) {
            .install, .reinstall, .erase => true,
            else => false,
        };
    }

    /// True when the operation stages `*.rpm` command-line arguments into the
    /// `@cmdline` repository before solving.
    pub fn stagesCommandLineRpms(self: Operation) bool {
        return switch (self) {
            .install, .reinstall => true,
            else => false,
        };
    }
};

/// Everything the resolve service needs for one solve.
///
/// `handle` is borrowed for the duration of the call. The service leaves the
/// handle's transaction-plan state holding the published plan on success.
pub const Request = struct {
    handle: *Tdnf,
    operation: Operation,
};

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

fn freeRaw(comptime T: type, slot: *?[*]T) void {
    if (slot.*) |value| TDNFFreeMemory(@ptrCast(value));
    slot.* = null;
}

fn freeStringArray(slot: *?[*]?[*:0]u8) void {
    TDNFFreeStringArray(slot.*);
    slot.* = null;
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

fn systemError() u32 {
    return errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(std.c._errno().*));
}

fn planEnabled(handle: *Tdnf) bool {
    return TDNFTransactionPlanStateIsEnabled(handle.pTransactionPlanState) != 0;
}

/// Drops any plan the failed resolve left behind, keeping a structured problem
/// plan when the solver produced one.
pub fn handleResolveError(handle: ?*Tdnf) void {
    const tdnf = handle orelse return;
    if (TDNFTransactionPlanStatePublishProblem(tdnf.pTransactionPlanState) == 0) {
        TDNFTransactionPlanStateClear(tdnf.pTransactionPlanState);
    }
}

/// Planning cannot represent build-dependency, source, or dependency-free
/// resolves, so they are refused rather than silently producing a plan that
/// does not describe the solve.
pub fn rejectUnsupportedResolve(handle: *Tdnf) u32 {
    if (!planEnabled(handle)) return 0;
    const args = handle.pArgs.?;
    if (args.nBuildDeps != 0 or args.nSource != 0 or args.nNoDeps != 0)
        return errors.ERROR_TDNF_CALL_NOT_SUPPORTED;
    return 0;
}

/// `--repofromdir` metadata has no stable repository identity, so it cannot
/// participate in a canonical plan.
pub fn rejectRepoFromDir(handle: *Tdnf) u32 {
    if (!planEnabled(handle)) return 0;
    var ids = handle.ppszRepoFromDirIds;
    while (ids) |values| {
        const id = values[0] orelse break;
        var repo = handle.pRepos;
        while (repo) |current| : (repo = current.pNext) {
            if (current.nEnabled != 0 and current.pszId != null and
                eqlZ(current.pszId.?, std.mem.span(id)))
            {
                return errors.ERROR_TDNF_CALL_NOT_SUPPORTED;
            }
        }
        ids = values + 1;
    }
    return 0;
}

/// Surfaces a request-trace construction failure as a resolve error.
pub fn checkTrace(handle: *Tdnf) u32 {
    if (!planEnabled(handle)) return 0;
    return TDNFTransactionPlanRequestTraceGetError(handle.pRequestTrace);
}

/// Promotes the pending plan captured during the solve to the published plan.
pub fn publishPlan(handle: *Tdnf) u32 {
    return TDNFTransactionPlanStatePublish(handle.pTransactionPlanState);
}

fn resetPlanState(handle: *Tdnf) void {
    TDNFTransactionPlanStateClear(handle.pTransactionPlanState);
    TDNFTransactionPlanRequestTraceDestroy(handle.pRequestTrace);
    handle.pRequestTrace = null;
}

/// Refuses `upgrade-all` filters that select a subset of updates: the plan has
/// no way to record advisory-scoped selection as part of the request.
fn rejectUnsupportedUpgradeAllFilters(handle: *Tdnf) u32 {
    if (!planEnabled(handle)) return 0;
    const args = handle.pArgs.?;
    var option = args.cn_setopts.?.first_child;
    while (option) |current| : (option = current.next) {
        const name = current.name orelse continue;
        if (eqlIgnoreCaseZ(name, "security") or
            eqlIgnoreCaseZ(name, "sec-severity") or
            eqlIgnoreCaseZ(name, "reboot-required"))
        {
            return errors.ERROR_TDNF_CALL_NOT_SUPPORTED;
        }
    }
    return 0;
}

/// Validates the operation against the parsed command line before any solver
/// state is built.
fn validateOperation(handle: *Tdnf, operation: Operation) u32 {
    var result = rejectUnsupportedResolve(handle);
    if (result == 0 and operation == .upgrade_all)
        result = rejectUnsupportedUpgradeAllFilters(handle);
    if (result == 0 and operation.requiresSubjects() and
        handle.pArgs.?.nCmdCount <= 1)
        result = errors.ERROR_TDNF_PACKAGE_REQUIRED;
    return result;
}

/// Starts recording how each command-line subject became a solver job. Skipped
/// for the build-dependency, source, and dependency-free paths, which planning
/// already refused above.
fn beginRequestTrace(handle: *Tdnf, operation: Operation) void {
    const args = handle.pArgs.?;
    if (args.nBuildDeps != 0 or args.nSource != 0 or args.nNoDeps != 0) return;
    const subject_count: u32 = if (args.nCmdCount > 1)
        @intCast(args.nCmdCount - 1)
    else
        0;
    const subjects: ?*const anyopaque = if (args.ppszCmds) |commands|
        @ptrCast(commands + 1)
    else
        null;
    handle.pRequestTrace = TDNFTransactionPlanRequestTraceCreate(
        operation.alterType(),
        subjects,
        subject_count,
    );
}

/// Stages every `*.rpm` command-line argument into the `@cmdline` repository
/// and pushes the resulting solvables onto the goal queue.
pub fn stageCommandLinePackages(
    handle_opt: ?*Tdnf,
    queue: *IdList,
    operation: Operation,
    unresolved_output: *c_int,
) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    unresolved_output.* = 0;
    const args = handle.pArgs.?;

    TDNFFreeStringArrayWithCount(
        handle.ppszCmdLinePkgPaths,
        @intCast(handle.dwCmdLinePkgCount),
    );
    handle.ppszCmdLinePkgPaths = null;
    if (handle.pdwCmdLinePkgIds) |ids| TDNFFreeMemory(@ptrCast(ids));
    handle.pdwCmdLinePkgIds = null;
    handle.dwCmdLinePkgCount = 0;

    var path: ?[*:0]u8 = null;
    defer freeString(&path);
    var package_copy: ?[*:0]u8 = null;
    defer freeString(&package_copy);

    var index: c_int = 1;
    while (index < args.nCmdCount) : (index += 1) {
        const package_name = args.ppszCmds.?[@intCast(index)].?;
        if (fnmatch("*.rpm", package_name, 0) != 0) continue;
        freeString(&path);
        freeString(&package_copy);
        var package_fd: c_int = -1;
        defer {
            if (package_fd >= 0) _ = std.c.close(package_fd);
        }
        if (fnmatch("*.src.rpm", package_name, 0) == 0 or
            fnmatch("*.nosrc.rpm", package_name, 0) == 0)
        {
            if (args.nSource == 0 and args.nBuildDeps == 0) {
                common.log(LOG_ERR, "package '%s' appears to be a source rpm - use --source to install, or --builddeps to install its build depenfdencies\n", .{package_name});
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            }
        } else if (args.nSource != 0 or args.nBuildDeps != 0) {
            common.log(LOG_ERR, "package '%s' appears not to be a source rpm but --source or --builddeps was used\n", .{package_name});
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        }

        var is_file: c_int = 0;
        var result = TDNFIsFileOrSymlink(package_name, &is_file);
        if (result != 0) return result;
        if (is_file != 0) {
            path = realpath(package_name, null);
            if (path == null) return systemError();
        } else {
            var is_remote: c_int = 0;
            result = TDNFUriIsRemote(package_name, &is_remote);
            if (result == errors.ERROR_TDNF_URL_INVALID) {
                if (planEnabled(handle)) {
                    TDNFTransactionPlanRequestTraceRecordRequestOutcome(
                        handle.pRequestTrace,
                        @intCast(index - 1),
                        transaction_plan_abi.request_outcome.no_candidate,
                    );
                    unresolved_output.* += 1;
                }
                continue;
            }
            if (result != 0) return result;
            if (is_remote == 0) {
                result = TDNFPathFromUri(package_name, &path);
                if (result != 0) return result;
            } else {
                result = TDNFAllocateString(package_name, &package_copy);
                if (result != 0) return result;
                var repo: ?*RepoData = null;
                result = TDNFFindRepoById(handle, command_line_repo_name, &repo);
                if (result != 0) return result;
                result = TDNFDownloadPackageToCacheFd(
                    handle,
                    package_name,
                    basename(package_copy.?),
                    repo,
                    &path,
                    &package_fd,
                );
                if (result != 0) return result;
                freeString(&package_copy);
            }
        }

        var package_id: u32 = 0;
        result = if (package_fd >= 0)
            TDNFPackageContextAddRpmFd(
                handle.pSack,
                handle.pCmdLineRepo,
                path,
                package_fd,
                &package_id,
            )
        else
            TDNFPackageContextAddRpm(
                handle.pSack,
                handle.pCmdLineRepo,
                path,
                &package_id,
            );
        if (result != 0) return result;
        result = api.recordCmdLinePkgPath(handle, package_id, path);
        if (result != 0) return result;
        const trace_start = queue.dwCount;
        result = TDNFIdListPush(queue, @intCast(package_id));
        if (result != 0) return result;
        TDNFTransactionPlanRequestTraceRecordGoalRange(
            handle.pRequestTrace,
            queue.pnElements,
            trace_start,
            queue.dwCount,
            operation.alterType(),
            transaction_plan_abi.request_reason.user,
            @intCast(index - 1),
        );
    }
    return 0;
}

/// Applies the download-cache policy and marks the derived action/download
/// flags the CLI and transaction layers read.
fn finalizeSolved(handle: *Tdnf, info: *SolvedPackageInfo) u32 {
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
    var available: u64 = 0;
    var result = TDNFGetAvailableCacheBytesHandle(handle, &available);
    if (result == 0 and info.nNeedDownload != 0)
        result = TDNFCheckDownloadCacheBytes(info, available);
    return result;
}

/// Resolves one typed operation without executing anything.
///
/// On success `output` owns the solved package info and, when planning is
/// enabled, the handle's transaction-plan state holds the published plan. On
/// failure `output` is null and any pending plan has been dropped, except for a
/// structured problem plan, which is published so the caller can report it.
pub fn resolve(request: Request, output: *?*SolvedPackageInfo) u32 {
    const handle = request.handle;
    const operation = request.operation;
    resetPlanState(handle);

    var alter_type = operation.alterType();
    var queue = IdList{};
    TDNFIdListInit(&queue);
    defer TDNFIdListFree(&queue);
    var unresolved: ?[*]?[*:0]u8 = null;
    var solved: ?*SolvedPackageInfo = null;
    var package_names: ?[*]?[*:0]u8 = null;
    defer freeRaw(?[*:0]u8, &package_names);
    var package_files: ?[*]?[*:0]u8 = null;
    defer freeRaw(?[*:0]u8, &package_files);

    const args = handle.pArgs.?;
    var result = validateOperation(handle, operation);

    if (result == 0) beginRequestTrace(handle, operation);
    if (result == 0) result = checkTrace(handle);
    if (result == 0) result = rejectRepoFromDir(handle);
    if (result == 0) result = TDNFRefresh(handle);

    var command_line_unresolved: c_int = 0;
    if (result == 0 and operation.stagesCommandLineRpms()) {
        result = stageCommandLinePackages(
            handle,
            &queue,
            operation,
            &command_line_unresolved,
        );
    }

    const command_count: usize = @intCast(args.nCmdCount);
    if (result == 0)
        result = allocatePointerArray(command_count, &package_names);
    if (result == 0)
        result = allocatePointerArray(command_count, &package_files);
    if (result == 0) {
        var files: usize = 0;
        var names: usize = 0;
        var index: usize = 1;
        while (index < command_count) : (index += 1) {
            const name = args.ppszCmds.?[index].?;
            if (fnmatch("*.rpm", name, 0) == 0) {
                package_files.?[files] = name;
                files += 1;
            } else {
                package_names.?[names] = name;
                names += 1;
            }
        }
        result = allocatePointerArray(command_count, &unresolved);
    }
    if (result == 0) {
        result = if (args.nBuildDeps == 0)
            TDNFPrepareAllPackages(handle, &alter_type, unresolved, &queue)
        else
            TDNFResolveBuildDependencies(
                handle,
                package_names,
                unresolved,
                &queue,
            );
    }

    var unresolved_count: c_int = 0;
    if (result == 0) {
        while (unresolved.?[@intCast(unresolved_count)] != null)
            unresolved_count += 1;
        result = if (args.nSource == 0 and args.nNoDeps == 0)
            TDNFGoal(
                handle,
                &queue,
                &solved,
                alter_type,
                unresolved_count + command_line_unresolved,
            )
        else
            TDNFGoalNoDeps(handle, &queue, &solved);
    }
    if (result == 0) {
        const info = solved.?;
        result = finalizeSolved(handle, info);
        if (result == 0) result = publishPlan(handle);
        if (result == 0) {
            info.ppszPkgsNotResolved = @ptrCast(unresolved);
            output.* = info;
            return 0;
        }
    }

    handleResolveError(handle);
    output.* = null;
    if (solved != null) TDNFFreeSolvedPackageInfo(solved);
    freeStringArray(&unresolved);
    return result;
}

/// Private-ABI adapter used by `TDNFResolve`.
pub fn resolveAlterType(
    handle_opt: ?*Tdnf,
    requested_alter_type: c_uint,
    output_opt: ?*?*SolvedPackageInfo,
) u32 {
    if (handle_opt) |handle| resetPlanState(handle);
    const handle = handle_opt orelse {
        if (output_opt) |output| output.* = null;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    const output = output_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const operation = Operation.fromAlterType(requested_alter_type) orelse {
        output.* = null;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    return resolve(.{ .handle = handle, .operation = operation }, output);
}

test "operation round-trips through the private alter-type ABI" {
    inline for (comptime std.enums.values(Operation)) |operation| {
        try std.testing.expectEqual(
            @as(?Operation, operation),
            Operation.fromAlterType(operation.alterType()),
        );
    }
    try std.testing.expectEqual(
        @as(?Operation, null),
        Operation.fromAlterType(11),
    );
    try std.testing.expectEqual(
        @as(?Operation, null),
        Operation.fromAlterType(std.math.maxInt(c_uint)),
    );
}

test "operations declare their subject and command-line rpm requirements" {
    try std.testing.expect(Operation.install.requiresSubjects());
    try std.testing.expect(Operation.erase.requiresSubjects());
    try std.testing.expect(Operation.reinstall.requiresSubjects());
    try std.testing.expect(!Operation.upgrade.requiresSubjects());
    try std.testing.expect(!Operation.upgrade_all.requiresSubjects());
    try std.testing.expect(!Operation.autoerase_all.requiresSubjects());

    try std.testing.expect(Operation.install.stagesCommandLineRpms());
    try std.testing.expect(Operation.reinstall.stagesCommandLineRpms());
    try std.testing.expect(!Operation.erase.stagesCommandLineRpms());
    try std.testing.expect(!Operation.distro_sync.stagesCommandLineRpms());
}
