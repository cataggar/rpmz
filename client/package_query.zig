// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1.

const std = @import("std");
const abi = @import("client_abi");
const errors = @import("tdnf_error");
const repomd = @import("repomd_client_exports");

const c = abi.C;
const libc = @cImport({
    @cInclude("sys/vfs.h");
});
const package_context = repomd.package_context;
const pkgquery = repomd.package_query;
const query_index = repomd.query_index;
const query_native = repomd.query_native;

const field_sep: u8 = 0x1f;
const group_sep: u8 = 0x1e;
const item_sep: u8 = 0x1d;
const system_repo = "@System";
const detail_list: c_int = 0;
const scope_installed: c_int = 1;
const scope_available: c_int = 2;
const update_enhancement: usize = 3;

const HistoryCtx = opaque {};
const RpmConfig = opaque {};

extern fn TDNFAllocateMemory(usize, usize, *?*anyopaque) callconv(.c) u32;
extern fn TDNFAllocateString([*:0]const u8, *?[*:0]u8) callconv(.c) u32;
extern fn TDNFFreeMemory(?*anyopaque) callconv(.c) void;
extern fn TDNFFreeStringArray([*c][*c]u8) callconv(.c) void;
extern fn TDNFFreePackageInfo(c.PTDNF_PKG_INFO) callconv(.c) void;
extern fn TDNFFreePackageInfoArray(c.PTDNF_PKG_INFO, u32) callconv(.c) void;
extern fn TDNFFreePackageInfoContents(c.PTDNF_PKG_INFO) callconv(.c) void;
extern fn TDNFFreeUpdateInfo(c.PTDNF_UPDATEINFO) callconv(.c) void;
extern fn TDNFFreeUpdateInfoPackages(c.PTDNF_UPDATEINFO_PKG) callconv(.c) void;
extern fn TDNFFreeUpdateInfoSummary(c.PTDNF_UPDATEINFO_SUMMARY) callconv(.c) void;
extern fn TDNFIdListPush(?*abi.IdList, i32) callconv(.c) u32;
extern fn TDNFIdListPushUnique(?*abi.IdList, i32) callconv(.c) u32;
extern fn TDNFGetCachePath(
    ?*abi.Tdnf,
    ?*abi.RepoData,
    ?[*:0]const u8,
    ?[*:0]const u8,
    *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFUtilsMakeDirs(?[*:0]const u8) callconv(.c) u32;
extern fn TDNFFindRepoById(
    ?*abi.Tdnf,
    ?[*:0]const u8,
    *?*abi.RepoData,
) callconv(.c) u32;
extern fn TDNFCreatePackageUrl(
    ?*abi.RepoData,
    ?[*:0]const u8,
    *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFGetHistoryCtx(
    ?*abi.Tdnf,
    *?*HistoryCtx,
    c_int,
) callconv(.c) u32;
extern fn destroy_history_ctx(?*HistoryCtx) callconv(.c) void;
extern fn history_get_auto_flag(
    ?*HistoryCtx,
    ?[*:0]const u8,
    *c_int,
) callconv(.c) c_int;
extern fn tdnf_rpm_config_create(?[*:0]const u8) callconv(.c) ?*RpmConfig;
extern fn tdnf_rpm_config_destroy(?*RpmConfig) callconv(.c) void;

extern fn TDNFRepoMdNativePackageRefLinesConfig(
    ?[*]const c.TDNF_REPOMD_NATIVE_REPO_INPUT,
    u32,
    ?*const RpmConfig,
    c_int,
    ?[*:0]const u8,
    *[*c][*c]u8,
    *u32,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeBestPackageRefConfig(
    ?[*]const c.TDNF_REPOMD_NATIVE_REPO_INPUT,
    u32,
    ?*const RpmConfig,
    c_int,
    ?[*:0]const u8,
    c_int,
    c_int,
    *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFRepoMdNativeDowngradeCandidateLines(
    ?[*]const c.TDNF_REPOMD_NATIVE_REPO_INPUT,
    u32,
    ?[*:0]const u8,
    [*c][*c]u8,
    ?[*:0]const u8,
    *[*c][*c]u8,
    *u32,
) callconv(.c) u32;
fn isEmpty(value: ?[*:0]const u8) bool {
    return value == null or value.?[0] == 0;
}

fn duplicateC(value: []const u8, output: *allowzero [*c]u8) u32 {
    var copy: ?[*:0]u8 = null;
    const rc = duplicate(value, &copy);
    if (rc != 0) return rc;
    output.* = @ptrCast(copy.?);
    return 0;
}

fn free(value: anytype) void {
    TDNFFreeMemory(@ptrCast(@constCast(value)));
}

fn duplicate(value: []const u8, output: *?[*:0]u8) u32 {
    output.* = null;
    const copy = std.heap.c_allocator.dupeZ(u8, value) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    output.* = copy.ptr;
    return 0;
}

fn allocArray(comptime T: type, count: usize, output: *?[*]T) u32 {
    output.* = null;
    var raw: ?*anyopaque = null;
    const rc = TDNFAllocateMemory(count, @sizeOf(T), &raw);
    if (rc != 0) return rc;
    output.* = @ptrCast(@alignCast(raw.?));
    return 0;
}

fn mapQueryError(err: anyerror) u32 {
    return switch (err) {
        error.OutOfMemory => errors.ERROR_TDNF_OUT_OF_MEMORY,
        error.InvalidParameter => errors.ERROR_TDNF_INVALID_PARAMETER,
        error.NoMatch => errors.ERROR_TDNF_NO_MATCH,
        error.NoData => errors.ERROR_TDNF_NO_DATA,
        else => errors.ERROR_TDNF_NO_DATA,
    };
}

fn repositoryDirectory(repo: *const abi.RepoData) ?[*:0]const u8 {
    if (repo.nHasMetaData != 0 or repo.ppszBaseUrls == null) return null;
    const first = repo.ppszBaseUrls.?[0] orelse return null;
    if (first[0] == 0) return null;
    return first;
}

fn repositoryQueryable(repo: *const abi.RepoData) bool {
    return repo.nEnabled != 0 and !isEmpty(repo.pszId) and
        (repo.nHasMetaData != 0 or repositoryDirectory(repo) != null);
}

fn freeRepoInputs(
    repos: ?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT,
    count: u32,
) void {
    const values = repos orelse return;
    for (values[0..count]) |*repo| {
        free(repo.pszCacheDir);
        repo.pszCacheDir = null;
    }
    free(values);
}

pub export fn TDNFNativeQueryBuildRepoInputs(
    handle: ?*abi.Tdnf,
    output: ?*?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT,
    count_output: ?*u32,
) u32 {
    if (output) |slot| slot.* = null;
    if (count_output) |slot| slot.* = 0;
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_count = count_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var count: usize = 0;
    var current = tdnf.pRepos;
    while (current) |repo| : (current = repo.pNext) {
        if (repositoryQueryable(repo)) count += 1;
    }
    if (count == 0) return 0;

    var repos: ?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT = null;
    var rc = allocArray(c.TDNF_REPOMD_NATIVE_REPO_INPUT, count, &repos);
    if (rc != 0) return rc;
    var populated: u32 = 0;

    current = tdnf.pRepos;
    while (current) |repo| : (current = repo.pNext) {
        if (!repositoryQueryable(repo)) continue;
        const item = &repos.?[populated];
        item.* = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_REPO_INPUT);
        item.pszDirectory = repositoryDirectory(repo);
        if (item.pszDirectory == null) {
            var cache: ?[*:0]u8 = null;
            rc = TDNFGetCachePath(tdnf, repo, null, null, &cache);
            if (rc != 0) {
                freeRepoInputs(repos, populated + 1);
                return rc;
            }
            item.pszCacheDir = cache;
        }
        item.pszId = repo.pszId;
        item.pszSnapshotFile = repo.pszSnapshotFile;
        populated += 1;
    }
    out.* = repos;
    out_count.* = populated;
    return 0;
}

pub export fn TDNFNativeQueryBuildSingleRepoInput(
    handle: ?*abi.Tdnf,
    repo: ?*abi.RepoData,
    output: ?*c.TDNF_REPOMD_NATIVE_REPO_INPUT,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const value = repo orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    out.* = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_REPO_INPUT);
    var cache: ?[*:0]u8 = null;
    const rc = TDNFGetCachePath(tdnf, value, null, null, &cache);
    if (rc != 0) return rc;
    out.pszCacheDir = cache;
    out.pszId = value.pszId;
    out.pszSnapshotFile = value.pszSnapshotFile;
    return 0;
}

pub export fn TDNFNativeQueryFreeRepoInputs(
    repos: ?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT,
    count: u32,
) void {
    freeRepoInputs(repos, count);
}

pub export fn TDNFNativeQueryInstallRoot(
    handle: ?*abi.Tdnf,
) ?[*:0]const u8 {
    const args = (handle orelse return null).pArgs orelse return null;
    const root = args.pszInstallRoot orelse return null;
    if (root[0] == 0 or std.mem.eql(u8, std.mem.span(root), "/")) return null;
    return root;
}

pub export fn TDNFNativeQueryFilterUserInstalled(
    handle: ?*abi.Tdnf,
    infos: c.PTDNF_PKG_INFO,
    count_output: ?*u32,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (infos == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_count = count_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var history: ?*HistoryCtx = null;
    const rc = TDNFGetHistoryCtx(tdnf, &history, 0);
    if (rc != 0) return rc;
    defer destroy_history_ctx(history);

    const original_count = out_count.*;
    var read: u32 = 0;
    var write: u32 = 0;
    while (read < original_count) : (read += 1) {
        var automatic: c_int = 0;
        if (history_get_auto_flag(
            history,
            infos[read].pszName,
            &automatic,
        ) != 0) return errors.ERROR_TDNF_HISTORY_ERROR;
        if (automatic == 0) {
            if (write != read) {
                infos[write] = infos[read];
                infos[read] = std.mem.zeroes(c.TDNF_PKG_INFO);
            }
            write += 1;
        } else {
            TDNFFreePackageInfoContents(@ptrCast(infos + read));
            infos[read] = std.mem.zeroes(c.TDNF_PKG_INFO);
        }
    }
    var clear = write;
    while (clear < original_count) : (clear += 1) {
        infos[clear] = std.mem.zeroes(c.TDNF_PKG_INFO);
    }
    out_count.* = write;
    read = 0;
    while (read < write) : (read += 1) {
        infos[read].pNext = if (read + 1 < write)
            @ptrCast(infos + read + 1)
        else
            null;
    }
    return 0;
}

pub export fn TDNFNativeQueryApplyLocationUrls(
    handle: ?*abi.Tdnf,
    infos: c.PTDNF_PKG_INFO,
    count: u32,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (infos == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
    for (infos[0..count]) |*info| {
        const repo_name = info.pszRepoName orelse continue;
        if (std.mem.eql(u8, std.mem.span(repo_name), system_repo) or
            info.pszLocation == null) continue;
        var repo: ?*abi.RepoData = null;
        var rc = TDNFFindRepoById(tdnf, repo_name, &repo);
        if (rc != 0) return rc;
        const prior = info.pszLocation;
        info.pszLocation = null;
        rc = TDNFCreatePackageUrl(repo, prior, &info.pszLocation);
        if (rc != 0) {
            info.pszLocation = prior;
            return rc;
        }
        free(prior);
    }
    return 0;
}

pub export fn TDNFNativeQueryInstalledPkgIds(
    context: ?*package_context.Context,
    queue: ?*abi.IdList,
) u32 {
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = queue orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    for (package_context.repositories(ctx)) |repository| {
        if (repository.kind != .installed) continue;
        for (repository.handles) |handle| {
            const rc = TDNFIdListPush(out, @intCast(handle));
            if (rc != 0) return rc;
        }
        break;
    }
    return 0;
}

fn allPackageIds(
    context: *package_context.Context,
    queue: *abi.IdList,
) u32 {
    for (package_context.repositories(context)) |repository| {
        for (repository.handles) |handle| {
            const rc = TDNFIdListPush(queue, @intCast(handle));
            if (rc != 0) return rc;
        }
    }
    return 0;
}

fn serializePackageId(
    context: *package_context.Context,
    package_id: i32,
    output: *?[*:0]u8,
) u32 {
    output.* = null;
    const pkg = package_context.packageModel(context, package_id) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repository = package_context.packageRepository(
        context,
        package_id,
    ) orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const nevra = pkgquery.nevraString(std.heap.c_allocator, pkg.*) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer std.heap.c_allocator.free(nevra);
    const line = std.fmt.allocPrintSentinel(
        std.heap.c_allocator,
        "{s}{c}{s}",
        .{ repository.id, field_sep, nevra },
        0,
    ) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    output.* = line.ptr;
    return 0;
}

pub export fn TDNFNativeQuerySerializePackageId(
    context: ?*package_context.Context,
    package_id: i32,
    output: ?*?[*:0]u8,
) u32 {
    if (output) |slot| slot.* = null;
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    return serializePackageId(
        ctx,
        package_id,
        output orelse return errors.ERROR_TDNF_INVALID_PARAMETER,
    );
}

pub export fn TDNFNativeQuerySerializeQueuePackageRefs(
    context: ?*package_context.Context,
    queue: ?*abi.IdList,
    output: ?*[*c][*c]u8,
    count_output: ?*u32,
) u32 {
    if (output) |slot| slot.* = null;
    if (count_output) |slot| slot.* = 0;
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const ids = queue orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_count = count_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var refs: ?[*]?[*:0]u8 = null;
    var rc = allocArray(?[*:0]u8, ids.dwCount + 1, &refs);
    if (rc != 0) return rc;
    for (0..ids.dwCount) |index| {
        rc = serializePackageId(ctx, ids.pnElements.?[index], &refs.?[index]);
        if (rc != 0) {
            TDNFFreeStringArray(@ptrCast(refs.?));
            return rc;
        }
    }
    out.* = @ptrCast(refs.?);
    out_count.* = ids.dwCount;
    return 0;
}

pub export fn TDNFNativeQuerySerializePackageInfoRefs(
    infos: c.PTDNF_PKG_INFO,
    count: u32,
    output: ?*[*c][*c]u8,
    count_output: ?*u32,
) u32 {
    if (output) |slot| slot.* = null;
    if (count_output) |slot| slot.* = 0;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_count = count_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (count != 0 and infos == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var refs: ?[*]?[*:0]u8 = null;
    const rc = allocArray(?[*:0]u8, count + 1, &refs);
    if (rc != 0) return rc;
    for (0..count) |index| {
        const info = infos[index];
        const name = if (info.pszName) |v| std.mem.span(v) else "";
        const evr = if (info.pszEVR) |v| std.mem.span(v) else "";
        const arch = if (info.pszArch) |v| std.mem.span(v) else "";
        const repo = if (info.pszRepoName) |v| std.mem.span(v) else "";
        const line = if (arch.len != 0)
            std.fmt.allocPrintSentinel(
                std.heap.c_allocator,
                "{s}{c}{s}-{s}.{s}",
                .{ repo, field_sep, name, evr, arch },
                0,
            )
        else
            std.fmt.allocPrintSentinel(
                std.heap.c_allocator,
                "{s}{c}{s}-{s}",
                .{ repo, field_sep, name, evr },
                0,
            );
        refs.?[index] = (line catch {
            TDNFFreeStringArray(@ptrCast(refs.?));
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        }).ptr;
    }
    out.* = @ptrCast(refs.?);
    out_count.* = count;
    return 0;
}

const RefParts = struct {
    repo: []const u8,
    epoch: u32,
    name: []const u8,
    version: []const u8,
    release: []const u8,
    arch: []const u8,
};

fn parseRef(text: []const u8) !RefParts {
    const separator = std.mem.indexOfScalar(u8, text, field_sep) orelse
        return error.InvalidParameter;
    if (separator == 0 or separator + 1 == text.len)
        return error.InvalidParameter;
    const repo = text[0..separator];
    const nevra = text[separator + 1 ..];
    const dot = std.mem.lastIndexOfScalar(u8, nevra, '.') orelse
        return error.InvalidParameter;
    if (dot == 0 or dot + 1 == nevra.len) return error.InvalidParameter;
    const arch = nevra[dot + 1 ..];
    const name_evr = nevra[0..dot];
    const release_dash = std.mem.lastIndexOfScalar(u8, name_evr, '-') orelse
        return error.InvalidParameter;
    if (release_dash == 0 or release_dash + 1 == name_evr.len)
        return error.InvalidParameter;
    const release = name_evr[release_dash + 1 ..];
    const name_version = name_evr[0..release_dash];
    const version_dash = std.mem.lastIndexOfScalar(u8, name_version, '-') orelse
        return error.InvalidParameter;
    if (version_dash == 0 or version_dash + 1 == name_version.len)
        return error.InvalidParameter;
    const name = name_version[0..version_dash];
    const raw_version = name_version[version_dash + 1 ..];
    var epoch: u32 = 0;
    var version = raw_version;
    if (std.mem.indexOfScalar(u8, raw_version, ':')) |colon| {
        if (colon == 0 or colon + 1 == raw_version.len)
            return error.InvalidParameter;
        epoch = std.fmt.parseInt(u32, raw_version[0..colon], 10) catch
            return error.InvalidParameter;
        version = raw_version[colon + 1 ..];
    }
    return .{
        .repo = repo,
        .epoch = epoch,
        .name = name,
        .version = version,
        .release = release,
        .arch = arch,
    };
}

fn packageMatchesRef(
    context: *package_context.Context,
    package_id: i32,
    parts: RefParts,
) bool {
    const pkg = package_context.packageModel(context, package_id) orelse
        return false;
    const repository = package_context.packageRepository(
        context,
        package_id,
    ) orelse return false;
    if (!std.mem.eql(u8, repository.id, parts.repo) or
        !std.mem.eql(u8, pkg.nevra.name, parts.name) or
        !std.mem.eql(u8, pkg.nevra.arch, parts.arch)) return false;
    return query_index.compareEvr(
        pkg.nevra.epoch,
        pkg.nevra.version,
        pkg.nevra.release,
        parts.epoch,
        parts.version,
        parts.release,
    ) == 0;
}

fn appendRefMatches(
    context: *package_context.Context,
    raw_ref: [*:0]const u8,
    installed_only: bool,
    queue: *abi.IdList,
    matches_output: ?*u32,
) u32 {
    if (matches_output) |slot| slot.* = 0;
    const parts = parseRef(std.mem.span(raw_ref)) catch
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var matches: u32 = 0;
    for (package_context.repositories(context)) |repository| {
        if (installed_only and repository.kind != .installed) continue;
        for (repository.handles) |handle| {
            const id: i32 = @intCast(handle);
            if (!packageMatchesRef(context, id, parts)) continue;
            const rc = TDNFIdListPushUnique(queue, id);
            if (rc != 0) return rc;
            matches += 1;
        }
    }
    if (matches_output) |slot| slot.* = matches;
    return 0;
}

pub export fn TDNFNativeQueryResolvePackageRefArrayToQueue(
    context: ?*package_context.Context,
    refs: [*c][*c]u8,
    count: u32,
    installed_only: c_int,
    queue: ?*abi.IdList,
) u32 {
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (refs == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = queue orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    for (0..count) |index| {
        if (refs[index] == null or refs[index][0] == 0) continue;
        var matches: u32 = 0;
        const rc = appendRefMatches(
            ctx,
            @ptrCast(refs[index]),
            installed_only != 0,
            out,
            &matches,
        );
        if (rc != 0) return rc;
        if (matches == 0) return errors.ERROR_TDNF_NO_DATA;
    }
    return 0;
}

pub export fn TDNFNativeQueryResolveSinglePackageRef(
    context: ?*package_context.Context,
    raw_ref: ?[*:0]const u8,
    installed_only: c_int,
    package_id_output: ?*i32,
) u32 {
    if (package_id_output) |slot| slot.* = 0;
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const ref = raw_ref orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (ref[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = package_id_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var list = abi.IdList{};
    defer free(list.pnElements);
    var matches: u32 = 0;
    const rc = appendRefMatches(
        ctx,
        ref,
        installed_only != 0,
        &list,
        &matches,
    );
    if (rc != 0) return rc;
    if (matches == 0 or list.dwCount == 0)
        return errors.ERROR_TDNF_NO_DATA;
    out.* = list.pnElements.?[0];
    return 0;
}

pub export fn TDNFNativeQuerySplitPackageRef(
    raw_ref: ?[*:0]const u8,
    repo_output: ?*?[*:0]u8,
    epoch_output: ?*u32,
    name_output: ?*?[*:0]u8,
    version_output: ?*?[*:0]u8,
    release_output: ?*?[*:0]u8,
    arch_output: ?*?[*:0]u8,
) u32 {
    if (repo_output) |slot| slot.* = null;
    if (epoch_output) |slot| slot.* = 0;
    if (name_output) |slot| slot.* = null;
    if (version_output) |slot| slot.* = null;
    if (release_output) |slot| slot.* = null;
    if (arch_output) |slot| slot.* = null;
    const ref = raw_ref orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_repo = repo_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_epoch = epoch_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_name = name_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_version = version_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_release = release_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_arch = arch_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const parts = parseRef(std.mem.span(ref)) catch
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var rc = duplicate(parts.repo, out_repo);
    if (rc != 0) return rc;
    rc = duplicate(parts.name, out_name);
    if (rc != 0) {
        free(out_repo.*);
        out_repo.* = null;
        return rc;
    }
    rc = duplicate(parts.version, out_version);
    if (rc != 0) {
        free(out_repo.*);
        free(out_name.*);
        out_repo.* = null;
        out_name.* = null;
        return rc;
    }
    rc = duplicate(parts.release, out_release);
    if (rc != 0) {
        free(out_repo.*);
        free(out_name.*);
        free(out_version.*);
        out_repo.* = null;
        out_name.* = null;
        out_version.* = null;
        return rc;
    }
    rc = duplicate(parts.arch, out_arch);
    if (rc != 0) {
        free(out_repo.*);
        free(out_name.*);
        free(out_version.*);
        free(out_release.*);
        out_repo.* = null;
        out_name.* = null;
        out_version.* = null;
        out_release.* = null;
        return rc;
    }
    out_epoch.* = parts.epoch;
    return 0;
}

pub export fn TDNFNativeQuerySerializeAutoInstalledRefs(
    handle: ?*abi.Tdnf,
    history: ?*HistoryCtx,
    output: ?*[*c][*c]u8,
    count_output: ?*u32,
) u32 {
    if (output) |slot| slot.* = null;
    if (count_output) |slot| slot.* = 0;
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (tdnf.pRpmConfig == null or history == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const context: *package_context.Context = @ptrCast(@alignCast(
        tdnf.pSack orelse return errors.ERROR_TDNF_INVALID_PARAMETER,
    ));
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out_count = count_output orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var installed_count: usize = 0;
    for (package_context.repositories(context)) |repository| {
        if (repository.kind == .installed) installed_count +=
            repository.handles.len;
    }
    var refs: ?[*]?[*:0]u8 = null;
    var rc = allocArray(?[*:0]u8, installed_count + 1, &refs);
    if (rc != 0) return rc;
    var count: u32 = 0;
    for (package_context.repositories(context)) |repository| {
        if (repository.kind != .installed) continue;
        for (repository.handles) |handle_id| {
            const pkg = package_context.packageModel(
                context,
                @intCast(handle_id),
            ) orelse continue;
            const name = std.heap.c_allocator.dupeZ(
                u8,
                pkg.nevra.name,
            ) catch {
                TDNFFreeStringArray(@ptrCast(refs.?));
                return errors.ERROR_TDNF_OUT_OF_MEMORY;
            };
            defer std.heap.c_allocator.free(name);
            var automatic: c_int = 0;
            if (history_get_auto_flag(history, name.ptr, &automatic) != 0) {
                TDNFFreeStringArray(@ptrCast(refs.?));
                return errors.ERROR_TDNF_HISTORY_ERROR;
            }
            if (automatic == 0) continue;
            rc = serializePackageId(
                context,
                @intCast(handle_id),
                &refs.?[count],
            );
            if (rc != 0) {
                TDNFFreeStringArray(@ptrCast(refs.?));
                return rc;
            }
            count += 1;
        }
    }
    out.* = @ptrCast(refs.?);
    out_count.* = count;
    return 0;
}

fn parseUnsigned(text: []const u8) !u32 {
    if (text.len == 0) return error.InvalidParameter;
    return std.fmt.parseInt(u32, text, 10) catch error.InvalidParameter;
}

pub export fn TDNFNativeQueryBuildUpdateInfoSummary(
    lines: [*c][*c]u8,
    count: u32,
    output: ?*c.PTDNF_UPDATEINFO_SUMMARY,
) u32 {
    if (output) |slot| slot.* = null;
    if (lines == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var summaries: ?[*]c.TDNF_UPDATEINFO_SUMMARY = null;
    const rc = allocArray(
        c.TDNF_UPDATEINFO_SUMMARY,
        update_enhancement + 1,
        &summaries,
    );
    if (rc != 0) return rc;
    for (0..update_enhancement + 1) |index| {
        summaries.?[index].nType = @intCast(index);
    }
    for (0..count) |index| {
        if (lines[index] == null) {
            free(summaries);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        }
        const text = std.mem.span(lines[index]);
        const separator = std.mem.indexOfScalar(u8, text, field_sep) orelse {
            free(summaries);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        };
        if (std.mem.indexOfScalar(u8, text[separator + 1 ..], field_sep) != null) {
            free(summaries);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        }
        const kind = parseUnsigned(text[0..separator]) catch {
            free(summaries);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        };
        const value = parseUnsigned(text[separator + 1 ..]) catch {
            free(summaries);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        };
        if (kind > update_enhancement or value > std.math.maxInt(c_int)) {
            free(summaries);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        }
        summaries.?[kind].nCount = @intCast(value);
    }
    out.* = @ptrCast(summaries.?);
    return 0;
}

fn allocateUpdatePackage(text: []const u8) !c.PTDNF_UPDATEINFO_PKG {
    var fields = std.mem.splitScalar(u8, text, item_sep);
    const name = fields.next() orelse return error.InvalidParameter;
    const evr = fields.next() orelse return error.InvalidParameter;
    const arch = fields.next() orelse return error.InvalidParameter;
    const filename = fields.next() orelse return error.InvalidParameter;
    if (fields.next() != null) return error.InvalidParameter;
    var raw: ?*anyopaque = null;
    if (TDNFAllocateMemory(1, @sizeOf(c.TDNF_UPDATEINFO_PKG), &raw) != 0)
        return error.OutOfMemory;
    const pkg: c.PTDNF_UPDATEINFO_PKG = @ptrCast(@alignCast(raw.?));
    errdefer TDNFFreeUpdateInfoPackages(pkg);
    if (name.len != 0 and duplicateC(name, &pkg[0].pszName) != 0)
        return error.OutOfMemory;
    if (evr.len != 0 and duplicateC(evr, &pkg[0].pszEVR) != 0)
        return error.OutOfMemory;
    if (arch.len != 0 and duplicateC(arch, &pkg[0].pszArch) != 0)
        return error.OutOfMemory;
    if (filename.len != 0 and duplicateC(filename, &pkg[0].pszFileName) != 0)
        return error.OutOfMemory;
    return pkg;
}

fn allocateUpdateInfo(text: []const u8) !c.PTDNF_UPDATEINFO {
    var fields = std.mem.splitScalar(u8, text, field_sep);
    const kind_text = fields.next() orelse return error.InvalidParameter;
    const reboot_text = fields.next() orelse return error.InvalidParameter;
    const id = fields.next() orelse return error.InvalidParameter;
    const description = fields.next() orelse return error.InvalidParameter;
    const date = fields.next() orelse return error.InvalidParameter;
    const packages = fields.rest();
    const kind = try parseUnsigned(kind_text);
    const reboot = try parseUnsigned(reboot_text);
    if (kind > std.math.maxInt(c_int) or reboot > std.math.maxInt(c_int))
        return error.InvalidParameter;

    var raw: ?*anyopaque = null;
    if (TDNFAllocateMemory(1, @sizeOf(c.TDNF_UPDATEINFO), &raw) != 0)
        return error.OutOfMemory;
    const info: c.PTDNF_UPDATEINFO = @ptrCast(@alignCast(raw.?));
    errdefer TDNFFreeUpdateInfo(info);
    info[0].nType = @intCast(kind);
    info[0].nRebootRequired = @intCast(reboot);
    if (id.len != 0 and duplicateC(id, &info[0].pszID) != 0)
        return error.OutOfMemory;
    if (description.len != 0 and
        duplicateC(description, &info[0].pszDescription) != 0)
        return error.OutOfMemory;
    if (date.len != 0 and duplicateC(date, &info[0].pszDate) != 0)
        return error.OutOfMemory;

    var head: c.PTDNF_UPDATEINFO_PKG = null;
    var tail: c.PTDNF_UPDATEINFO_PKG = null;
    errdefer TDNFFreeUpdateInfoPackages(head);
    var package_fields = std.mem.splitScalar(u8, packages, group_sep);
    while (package_fields.next()) |package_text| {
        if (package_text.len == 0) continue;
        const pkg = try allocateUpdatePackage(package_text);
        if (head == null) head = pkg else tail[0].pNext = pkg;
        tail = pkg;
    }
    info[0].pPackages = head;
    return info;
}

fn freeUpdateInfoList(head_value: c.PTDNF_UPDATEINFO) void {
    var head = head_value;
    while (head != null) {
        const next = head[0].pNext;
        head[0].pNext = null;
        TDNFFreeUpdateInfo(head);
        head = next;
    }
}

pub export fn TDNFNativeQueryBuildUpdateInfo(
    lines: [*c][*c]u8,
    count: u32,
    output: ?*c.PTDNF_UPDATEINFO,
) u32 {
    if (output) |slot| slot.* = null;
    if (lines == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var head: c.PTDNF_UPDATEINFO = null;
    var tail: c.PTDNF_UPDATEINFO = null;
    for (0..count) |index| {
        if (lines[index] == null) {
            freeUpdateInfoList(head);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        }
        const node = allocateUpdateInfo(std.mem.span(lines[index])) catch |err| {
            freeUpdateInfoList(head);
            return mapQueryError(err);
        };
        if (head == null) head = node else tail[0].pNext = node;
        tail = node;
    }
    out.* = head;
    return 0;
}

fn sackRepoInputs(
    context: *package_context.Context,
    output: *?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT,
    count_output: *u32,
) u32 {
    output.* = null;
    count_output.* = 0;
    var count: usize = 0;
    for (package_context.repositories(context)) |repository| {
        const owner: *abi.RepoData = @ptrCast(@alignCast(
            repository.owner orelse continue,
        ));
        if (repositoryQueryable(owner)) count += 1;
    }
    if (count == 0) return 0;
    var repos: ?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT = null;
    const rc = allocArray(c.TDNF_REPOMD_NATIVE_REPO_INPUT, count, &repos);
    if (rc != 0) return rc;
    var populated: u32 = 0;
    for (package_context.repositories(context)) |repository| {
        const owner: *abi.RepoData = @ptrCast(@alignCast(
            repository.owner orelse continue,
        ));
        if (!repositoryQueryable(owner)) continue;
        const item = &repos.?[populated];
        item.* = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_REPO_INPUT);
        item.pszDirectory = repositoryDirectory(owner);
        if (item.pszDirectory == null) {
            const cache_dir = package_context.cacheDir(context) orelse {
                freeRepoInputs(repos, populated);
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            };
            const cache_name = owner.pszCacheName orelse owner.pszId orelse {
                freeRepoInputs(repos, populated);
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            };
            const path = std.fs.path.joinZ(
                std.heap.c_allocator,
                &.{ std.mem.span(cache_dir), std.mem.span(cache_name) },
            ) catch {
                freeRepoInputs(repos, populated);
                return errors.ERROR_TDNF_OUT_OF_MEMORY;
            };
            item.pszCacheDir = path.ptr;
        }
        item.pszId = owner.pszId;
        item.pszSnapshotFile = owner.pszSnapshotFile;
        populated += 1;
    }
    output.* = repos;
    count_output.* = populated;
    return 0;
}

fn createRpmConfig(
    context: *package_context.Context,
    output: *?*RpmConfig,
) u32 {
    output.* = null;
    const root = package_context.rootDir(context) orelse "/";
    const config = tdnf_rpm_config_create(root) orelse
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    output.* = config;
    return 0;
}

fn findPackageRefs(
    context: *package_context.Context,
    spec: [*:0]const u8,
    scope: c_int,
    output: *[*c][*c]u8,
    count_output: *u32,
) u32 {
    output.* = null;
    count_output.* = 0;
    var repos: ?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT = null;
    var repo_count: u32 = 0;
    var rc = sackRepoInputs(context, &repos, &repo_count);
    if (rc != 0) return rc;
    defer freeRepoInputs(repos, repo_count);
    var config: ?*RpmConfig = null;
    rc = createRpmConfig(context, &config);
    if (rc != 0) return rc;
    defer tdnf_rpm_config_destroy(config);
    return TDNFRepoMdNativePackageRefLinesConfig(
        repos,
        repo_count,
        config,
        scope,
        spec,
        output,
        count_output,
    );
}

fn bestPackageRef(
    context: *package_context.Context,
    spec: [*:0]const u8,
    scope: c_int,
    source_only: bool,
    highest: bool,
    output: *?[*:0]u8,
) u32 {
    output.* = null;
    var repos: ?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT = null;
    var repo_count: u32 = 0;
    var rc = sackRepoInputs(context, &repos, &repo_count);
    if (rc != 0) return rc;
    defer freeRepoInputs(repos, repo_count);
    var config: ?*RpmConfig = null;
    rc = createRpmConfig(context, &config);
    if (rc != 0) return rc;
    defer tdnf_rpm_config_destroy(config);
    return TDNFRepoMdNativeBestPackageRefConfig(
        repos,
        repo_count,
        config,
        scope,
        spec,
        @intFromBool(source_only),
        @intFromBool(highest),
        output,
    );
}

fn resolveRef(
    context: *package_context.Context,
    ref: [*:0]const u8,
    installed_only: bool,
    output: *i32,
) u32 {
    return TDNFNativeQueryResolveSinglePackageRef(
        context,
        ref,
        @intFromBool(installed_only),
        output,
    );
}

fn comparePackageIds(
    context: *package_context.Context,
    left: i32,
    right: i32,
) ?i32 {
    const left_pkg = package_context.packageModel(context, left) orelse
        return null;
    const right_pkg = package_context.packageModel(context, right) orelse
        return null;
    return query_index.comparePackageVersions(left_pkg.*, right_pkg.*);
}

fn populateInfoArray(
    context: *package_context.Context,
    refs: [*c][*c]u8,
    ref_count: u32,
    detail: c_int,
    query_format: bool,
    dependency_mask: u32,
    file_list: bool,
    checksum: bool,
    output: *c.PTDNF_PKG_INFO,
    count_output: *u32,
) u32 {
    output.* = null;
    count_output.* = 0;
    if (ref_count == 0) return errors.ERROR_TDNF_NO_MATCH;
    var ids = std.ArrayList(i32).empty;
    defer ids.deinit(std.heap.c_allocator);
    ids.ensureTotalCapacity(std.heap.c_allocator, ref_count) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    for (0..ref_count) |index| {
        if (refs[index] == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
        var id: i32 = 0;
        const rc = resolveRef(
            context,
            @ptrCast(refs[index]),
            false,
            &id,
        );
        if (rc != 0) return rc;
        ids.appendAssumeCapacity(id);
    }
    const infos = query_native.buildPackageInfoForContext(
        context,
        ids.items,
        detail,
        query_format,
        dependency_mask,
        file_list,
        checksum,
    ) catch |err| return mapQueryError(err);
    output.* = @ptrCast(infos);
    count_output.* = @intCast(ids.items.len);
    return 0;
}

pub export fn TDNFPopulatePkgInfosFromRefs(
    context: ?*package_context.Context,
    refs: [*c][*c]u8,
    ref_count: u32,
    output: ?*c.PTDNF_PKG_INFO,
) u32 {
    if (output) |slot| slot.* = null;
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (refs == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var array: c.PTDNF_PKG_INFO = null;
    var count: u32 = 0;
    var rc = populateInfoArray(
        ctx,
        refs,
        ref_count,
        detail_list,
        true,
        0,
        false,
        true,
        &array,
        &count,
    );
    if (rc != 0) return rc;
    defer if (array != null) TDNFFreePackageInfoArray(array, count);

    var head: c.PTDNF_PKG_INFO = null;
    for (0..count) |offset| {
        const index = count - 1 - offset;
        var raw: ?*anyopaque = null;
        rc = TDNFAllocateMemory(1, @sizeOf(c.TDNF_PKG_INFO), &raw);
        if (rc != 0) {
            TDNFFreePackageInfo(head);
            return rc;
        }
        const node: c.PTDNF_PKG_INFO = @ptrCast(@alignCast(raw.?));
        node[0] = array[index];
        array[index] = std.mem.zeroes(c.TDNF_PKG_INFO);
        node[0].pNext = head;
        head = node;
    }
    out.* = head;
    return 0;
}

fn infoText(value: [*c]u8) []const u8 {
    return if (value == null) "" else std.mem.span(value);
}

fn infoLessThan(_: void, left: c.PTDNF_PKG_INFO, right: c.PTDNF_PKG_INFO) bool {
    const repo_order = std.mem.order(
        u8,
        infoText(left[0].pszRepoName),
        infoText(right[0].pszRepoName),
    );
    if (repo_order != .eq) return repo_order == .lt;
    const name_order = std.mem.order(
        u8,
        infoText(left[0].pszName),
        infoText(right[0].pszName),
    );
    if (name_order != .eq) return name_order == .lt;
    const left_evr = repomd.metadata_model.splitEvrQuery(
        infoText(left[0].pszEVR),
    );
    const right_evr = repomd.metadata_model.splitEvrQuery(
        infoText(right[0].pszEVR),
    );
    return query_index.compareEvr(
        left_evr.epoch,
        left_evr.version,
        left_evr.release,
        right_evr.epoch,
        right_evr.version,
        right_evr.release,
    ) > 0;
}

pub export fn TDNFPkgInfoFilterNewest(
    context: ?*package_context.Context,
    infos: c.PTDNF_PKG_INFO,
) u32 {
    _ = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (infos == null) return 0;
    var count: usize = 0;
    var node = infos;
    while (node != null) : (node = node[0].pNext) count += 1;
    if (count < 2) return 0;
    const pointers = std.heap.c_allocator.alloc(
        c.PTDNF_PKG_INFO,
        count,
    ) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer std.heap.c_allocator.free(pointers);
    node = infos;
    for (pointers) |*slot| {
        slot.* = node;
        node = node[0].pNext;
    }
    std.mem.sort(c.PTDNF_PKG_INFO, pointers, {}, infoLessThan);
    var tail = pointers[0];
    tail[0].pNext = null;
    for (pointers[1..]) |candidate| {
        if (std.mem.eql(
            u8,
            infoText(candidate[0].pszRepoName),
            infoText(tail[0].pszRepoName),
        ) and std.mem.eql(
            u8,
            infoText(candidate[0].pszName),
            infoText(tail[0].pszName),
        )) continue;
        tail[0].pNext = candidate;
        tail = candidate;
        tail[0].pNext = null;
    }
    return 0;
}

fn copyNevraFromRef(ref: [*:0]const u8, output: *?[*:0]u8) u32 {
    output.* = null;
    const text = std.mem.span(ref);
    const separator = std.mem.indexOfScalar(u8, text, field_sep) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (separator + 1 == text.len)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    return duplicate(text[separator + 1 ..], output);
}

fn packageNameFromRef(ref: [*:0]const u8, output: *?[*:0]u8) u32 {
    output.* = null;
    const parts = parseRef(std.mem.span(ref)) catch
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    return duplicate(parts.name, output);
}

fn compareRefs(
    context: *package_context.Context,
    left_ref: [*:0]const u8,
    right_ref: [*:0]const u8,
    output: *c_int,
) u32 {
    output.* = 0;
    var left: i32 = 0;
    var rc = resolveRef(context, left_ref, false, &left);
    if (rc != 0) return rc;
    var right: i32 = 0;
    rc = resolveRef(context, right_ref, false, &right);
    if (rc != 0) return rc;
    output.* = comparePackageIds(context, left, right) orelse
        return errors.ERROR_TDNF_NO_DATA;
    return 0;
}

fn verifyInstallPackage(
    context: *package_context.Context,
    package_id: i32,
    install_output: *u32,
) u32 {
    install_output.* = 0;
    var package_ref: ?[*:0]u8 = null;
    var rc = serializePackageId(context, package_id, &package_ref);
    if (rc != 0) return rc;
    defer free(package_ref);
    var name: ?[*:0]u8 = null;
    rc = packageNameFromRef(package_ref.?, &name);
    if (rc != 0) return rc;
    defer free(name);
    var installed_ref: ?[*:0]u8 = null;
    rc = bestPackageRef(
        context,
        name.?,
        scope_installed,
        false,
        true,
        &installed_ref,
    );
    if (rc == errors.ERROR_TDNF_NO_MATCH or
        rc == errors.ERROR_TDNF_NO_DATA)
    {
        install_output.* = 1;
        return 0;
    }
    if (rc != 0) return rc;
    defer free(installed_ref);
    var comparison: c_int = 0;
    rc = compareRefs(context, package_ref.?, installed_ref.?, &comparison);
    if (rc != 0) return rc;
    install_output.* = @intFromBool(comparison != 0);
    return 0;
}

fn verifyUpgradePackage(
    context: *package_context.Context,
    package_id: i32,
    upgrade_output: *u32,
) u32 {
    upgrade_output.* = 0;
    var package_ref: ?[*:0]u8 = null;
    var rc = serializePackageId(context, package_id, &package_ref);
    if (rc != 0) return rc;
    defer free(package_ref);
    var name: ?[*:0]u8 = null;
    rc = packageNameFromRef(package_ref.?, &name);
    if (rc != 0) return rc;
    defer free(name);
    var installed_ref: ?[*:0]u8 = null;
    rc = bestPackageRef(
        context,
        name.?,
        scope_installed,
        false,
        true,
        &installed_ref,
    );
    if (rc != 0) return rc;
    defer free(installed_ref);
    var comparison: c_int = 0;
    rc = compareRefs(context, package_ref.?, installed_ref.?, &comparison);
    if (rc != 0) return rc;
    upgrade_output.* = @intFromBool(comparison > 0);
    return 0;
}

pub export fn TDNFMatchForReinstall(
    context: ?*package_context.Context,
    raw_name: ?[*:0]const u8,
    queue: ?*abi.IdList,
) u32 {
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const name = raw_name orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (name[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = queue orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var installed_refs: [*c][*c]u8 = null;
    var installed_count: u32 = 0;
    var rc = findPackageRefs(
        ctx,
        name,
        scope_installed,
        &installed_refs,
        &installed_count,
    );
    if (rc != 0) return rc;
    defer TDNFFreeStringArray(installed_refs);
    if (installed_count == 0) return errors.ERROR_TDNF_NO_MATCH;
    var nevra: ?[*:0]u8 = null;
    rc = copyNevraFromRef(@ptrCast(installed_refs[0]), &nevra);
    if (rc != 0) return rc;
    defer free(nevra);
    var available_refs: [*c][*c]u8 = null;
    var available_count: u32 = 0;
    rc = findPackageRefs(
        ctx,
        nevra.?,
        scope_available,
        &available_refs,
        &available_count,
    );
    if (rc != 0) return rc;
    defer TDNFFreeStringArray(available_refs);
    if (available_count == 0) return errors.ERROR_TDNF_NO_MATCH;
    var package_id: i32 = 0;
    rc = resolveRef(ctx, @ptrCast(available_refs[0]), false, &package_id);
    if (rc != 0) return rc;
    return TDNFIdListPush(out, package_id);
}

pub export fn TDNFAddPackagesForErase(
    context: ?*package_context.Context,
    queue: ?*abi.IdList,
    raw_name: ?[*:0]const u8,
) u32 {
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = queue orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const name = raw_name orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (name[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var refs: [*c][*c]u8 = null;
    var count: u32 = 0;
    const rc = findPackageRefs(
        ctx,
        name,
        scope_installed,
        &refs,
        &count,
    );
    if (rc != 0) return rc;
    defer TDNFFreeStringArray(refs);
    if (count == 0) return errors.ERROR_TDNF_NO_MATCH;
    return TDNFNativeQueryResolvePackageRefArrayToQueue(
        ctx,
        refs,
        count,
        1,
        out,
    );
}

pub export fn TDNFAddPackagesForInstall(
    context: ?*package_context.Context,
    queue: ?*abi.IdList,
    raw_name: ?[*:0]const u8,
    source: c_int,
    install_only: c_int,
) u32 {
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = queue orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const name = raw_name orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (name[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var available_ref: ?[*:0]u8 = null;
    var rc = bestPackageRef(
        ctx,
        name,
        scope_available,
        source != 0,
        true,
        &available_ref,
    );
    if (source == 0 and
        (rc == errors.ERROR_TDNF_NO_MATCH or
            rc == errors.ERROR_TDNF_NO_DATA))
    {
        var installed_ref: ?[*:0]u8 = null;
        defer free(installed_ref);
        rc = bestPackageRef(
            ctx,
            name,
            scope_installed,
            false,
            true,
            &installed_ref,
        );
        if (rc == 0) return errors.ERROR_TDNF_ALREADY_INSTALLED;
    }
    if (rc != 0) return rc;
    defer free(available_ref);
    var package_id: i32 = 0;
    rc = resolveRef(ctx, available_ref.?, false, &package_id);
    if (rc != 0) return rc;
    var install: u32 = 0;
    rc = verifyInstallPackage(ctx, package_id, &install);
    if (rc != 0) return rc;
    if (install != 0 or install_only != 0 or source != 0)
        return TDNFIdListPush(out, package_id);
    return errors.ERROR_TDNF_ALREADY_INSTALLED;
}

pub export fn TDNFAddPackagesForUpgrade(
    context: ?*package_context.Context,
    queue: ?*abi.IdList,
    raw_name: ?[*:0]const u8,
) u32 {
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = queue orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const name = raw_name orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (name[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var available_ref: ?[*:0]u8 = null;
    var rc = bestPackageRef(
        ctx,
        name,
        scope_available,
        false,
        true,
        &available_ref,
    );
    if (rc != 0) return rc;
    defer free(available_ref);
    var package_id: i32 = 0;
    rc = resolveRef(ctx, available_ref.?, false, &package_id);
    if (rc != 0) return rc;
    var upgrade: u32 = 0;
    rc = verifyUpgradePackage(ctx, package_id, &upgrade);
    if (rc != 0) return rc;
    return if (upgrade != 0) TDNFIdListPush(out, package_id) else 0;
}

fn downgradePackage(
    handle: *abi.Tdnf,
    context: *package_context.Context,
    installed_id: i32,
    output: *i32,
) u32 {
    output.* = 0;
    var repos: ?[*]c.TDNF_REPOMD_NATIVE_REPO_INPUT = null;
    var repo_count: u32 = 0;
    var rc = TDNFNativeQueryBuildRepoInputs(handle, &repos, &repo_count);
    if (rc != 0) return rc;
    defer freeRepoInputs(repos, repo_count);
    var installed_ref: ?[*:0]u8 = null;
    rc = serializePackageId(context, installed_id, &installed_ref);
    if (rc != 0) return rc;
    defer free(installed_ref);
    var matches: [*c][*c]u8 = null;
    var match_count: u32 = 0;
    const conf = handle.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    rc = TDNFRepoMdNativeDowngradeCandidateLines(
        repos,
        repo_count,
        TDNFNativeQueryInstallRoot(handle),
        @ptrCast(conf.ppszMinVersions),
        installed_ref,
        &matches,
        &match_count,
    );
    if (rc == errors.ERROR_TDNF_NO_DATA)
        return errors.ERROR_TDNF_NO_DOWNGRADE_PATH;
    if (rc != 0) return rc;
    defer TDNFFreeStringArray(matches);
    if (match_count != 1) return errors.ERROR_TDNF_NO_DOWNGRADE_PATH;
    return resolveRef(context, @ptrCast(matches[0]), false, output);
}

pub export fn TDNFAddPackagesForDowngrade(
    handle: ?*abi.Tdnf,
    context: ?*package_context.Context,
    queue: ?*abi.IdList,
    raw_name: ?[*:0]const u8,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const ctx = context orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = queue orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const name_spec = raw_name orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (name_spec[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;

    var available_refs: [*c][*c]u8 = null;
    var available_count: u32 = 0;
    var rc = findPackageRefs(
        ctx,
        name_spec,
        scope_available,
        &available_refs,
        &available_count,
    );
    if (rc != 0) return rc;
    defer TDNFFreeStringArray(available_refs);
    if (available_count == 0) return errors.ERROR_TDNF_NO_MATCH;
    var name: ?[*:0]u8 = null;
    rc = packageNameFromRef(@ptrCast(available_refs[0]), &name);
    if (rc != 0) return rc;
    defer free(name);
    var installed_ref: ?[*:0]u8 = null;
    rc = bestPackageRef(
        ctx,
        name.?,
        scope_installed,
        false,
        false,
        &installed_ref,
    );
    if (rc != 0) return rc;
    defer free(installed_ref);
    var installed_id: i32 = 0;
    rc = resolveRef(ctx, installed_ref.?, true, &installed_id);
    if (rc != 0) return rc;
    var downgrade_id: i32 = 0;
    rc = downgradePackage(tdnf, ctx, installed_id, &downgrade_id);
    if (rc != 0) return rc;
    return TDNFIdListPush(out, downgrade_id);
}

pub export fn TDNFGetAvailableCacheBytes(
    conf: ?*abi.Conf,
    output: ?*u64,
) u32 {
    if (output) |slot| slot.* = 0;
    const value = conf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const cache_dir = value.pszCacheDir orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var make_rc = TDNFUtilsMakeDirs(cache_dir);
    if (make_rc == errors.ERROR_TDNF_ALREADY_EXISTS) make_rc = 0;
    if (make_rc != 0) return make_rc;
    var stat: libc.struct_statfs = undefined;
    if (libc.statfs(cache_dir, &stat) != 0) {
        const errno_value = std.posix.errno(-1);
        return errors.fromErrno(errno_value);
    }
    out.* = @as(u64, @intCast(stat.f_bsize)) *
        @as(u64, @intCast(stat.f_bavail));
    return 0;
}

fn addDownloadSizes(head: c.PTDNF_PKG_INFO, total: *u64, available: u64) bool {
    var node = head;
    while (node != null) : (node = node[0].pNext) {
        total.* += node[0].dwDownloadSizeBytes;
        if (total.* > available) return false;
    }
    return true;
}

pub export fn TDNFCheckDownloadCacheBytes(
    solved: c.PTDNF_SOLVED_PKG_INFO,
    available: u64,
) u32 {
    if (solved == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var total: u64 = 0;
    const lists = [_]c.PTDNF_PKG_INFO{
        solved[0].pPkgsToInstall,
        solved[0].pPkgsToDowngrade,
        solved[0].pPkgsToUpgrade,
        solved[0].pPkgsToReinstall,
    };
    for (lists) |head| {
        if (!addDownloadSizes(head, &total, available))
            return errors.ERROR_TDNF_CACHE_DIR_OUT_OF_DISK_SPACE;
    }
    return 0;
}

comptime {
    _ = allPackageIds;
    _ = TDNFAllocateString;
    _ = TDNFFreeUpdateInfoSummary;
}
