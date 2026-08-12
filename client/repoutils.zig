// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("tdnf_common");
const builtin = @import("builtin");
const abi = @import("client_abi");
const errors = @import("tdnf_error");

const Conf = abi.Conf;
const RepoData = abi.RepoData;
const Tdnf = abi.Tdnf;

const c = std.c;

const EACCES: c_int = @intFromEnum(std.posix.E.ACCES);
const EISDIR: c_int = @intFromEnum(std.posix.E.ISDIR);
const ELOOP: c_int = @intFromEnum(std.posix.E.LOOP);
const ENAMETOOLONG: c_int = @intFromEnum(std.posix.E.NAMETOOLONG);
const ENOENT: c_int = @intFromEnum(std.posix.E.NOENT);
const ENOTDIR: c_int = @intFromEnum(std.posix.E.NOTDIR);
const LOG_CRIT: c_int = 2;

const UtimeBuf = extern struct {
    actime: std.c.time_t,
    modtime: std.c.time_t,
};

const Stat = std.os.linux.Statx;

const libc = struct {
    extern fn difftime(std.c.time_t, std.c.time_t) f64;
    extern fn strerror(c_int) [*:0]const u8;
    extern fn time(?*std.c.time_t) std.c.time_t;
    extern fn utime([*:0]const u8, ?*const UtimeBuf) c_int;
};

extern fn TDNFJoinPathFromArray(
    ppszPath: ?*?[*:0]u8,
    ppszNodes: [*c]?[*:0]u8,
    nCount: c_int,
) u32;
extern fn TDNFFreeMemory(pMemory: ?*anyopaque) void;

const rpm_cache_dir_name = "rpms";
const repodata_dir_name = "repodata";
const solv_cache_dir_name = "solvcache";
const metadata_marker = "lastrefresh";
const metadata_mirrorlist = "mirrorlist";
const metadata_snapshot_prefix = "snapshot";
const at_removedir: c_int = 0x200;

const RepoPathBasis = enum {
    cache_name,
    id,
};

const RemoveOps = struct {
    context: ?*anyopaque = null,
    unlinkAt: *const fn (
        context: ?*anyopaque,
        parent_fd: c_int,
        name: [*:0]const u8,
        flags: c_int,
    ) c_int,
};

const PinnedParent = struct {
    fd: c_int,
    name: [std.fs.max_name_bytes + 1]u8,

    fn deinit(self: *PinnedParent) void {
        _ = c.close(self.fd);
    }

    fn nameZ(self: *const PinnedParent) [*:0]const u8 {
        return @ptrCast(&self.name);
    }
};

fn errnoValue() c_int {
    return std.c._errno().*;
}

fn statPath(path: [*:0]const u8, no_follow: bool, output: *Stat) c_int {
    return std.c.statx(
        std.os.linux.AT.FDCWD,
        path,
        if (no_follow) std.os.linux.AT.SYMLINK_NOFOLLOW else 0,
        .{ .TYPE = true, .ATIME = true, .MTIME = true, .CTIME = true },
        output,
    );
}

fn systemError(value: c_int) u32 {
    return @as(u32, @intCast(errors.ERROR_TDNF_SYSTEM_BASE)) +
        @as(u32, @intCast(value));
}

fn isNullOrEmpty(value: ?[*:0]const u8) bool {
    return value == null or value.?[0] == 0;
}

fn cString(value: [*c]u8) ?[*:0]const u8 {
    if (value == null) return null;
    return @ptrCast(value);
}

fn freeCString(value: ?[*:0]u8) void {
    if (value) |ptr| TDNFFreeMemory(@ptrCast(ptr));
}

fn isSafeComponent(value: []const u8) bool {
    return value.len != 0 and
        !std.mem.eql(u8, value, ".") and
        !std.mem.eql(u8, value, "..") and
        std.mem.indexOfScalar(u8, value, '/') == null;
}

fn repositoryComponent(
    repo: *RepoData,
    basis: RepoPathBasis,
) ?[*:0]const u8 {
    return switch (basis) {
        .cache_name => cString(repo.pszCacheName) orelse cString(repo.pszId),
        .id => cString(repo.pszId),
    };
}

fn checkedRepositoryComponent(
    repo: *RepoData,
    basis: RepoPathBasis,
) ?[*:0]const u8 {
    const component = repositoryComponent(repo, basis) orelse return null;
    if (!isSafeComponent(std.mem.span(component))) return null;
    return component;
}

fn joinPath(
    output: *?[*:0]u8,
    parts: []const ?[*:0]const u8,
) u32 {
    var nodes: [4]?[*:0]u8 = .{ null, null, null, null };
    var count: usize = 0;
    for (parts) |part| {
        const value = part orelse break;
        nodes[count] = @ptrCast(@constCast(value));
        count += 1;
    }
    return TDNFJoinPathFromArray(
        output,
        @ptrCast(&nodes),
        @intCast(count),
    );
}

fn getCachePathWithBasis(
    handle: *Tdnf,
    repo: *RepoData,
    basis: RepoPathBasis,
    subdir: ?[*:0]const u8,
    filename: ?[*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    const conf = handle.pConf;
    if (conf == null) return errors.ERROR_TDNF_INVALID_CONF;
    const cache_dir = cString(conf.?.pszCacheDir) orelse
        return errors.ERROR_TDNF_INVALID_CONF;
    if (cache_dir[0] == 0) return errors.ERROR_TDNF_INVALID_CONF;

    const repo_name = checkedRepositoryComponent(repo, basis) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    return joinPath(output, &.{ cache_dir, repo_name, subdir, filename });
}

fn getCachePath(
    handle: *Tdnf,
    repo: *RepoData,
    subdir: ?[*:0]const u8,
    filename: ?[*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    return getCachePathWithBasis(
        handle,
        repo,
        .cache_name,
        subdir,
        filename,
        output,
    );
}

fn openDirectoryPathNoFollow(
    path_z: [*:0]const u8,
    output: *c_int,
) u32 {
    // Pin every ancestor independently so a symlink swap can never redirect a
    // later openat/unlinkat outside the directory tree selected by the caller.
    const path = std.mem.span(path_z);
    if (path.len == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;

    var current_fd = std.c.open(
        if (std.fs.path.isAbsolute(path)) "/" else ".",
        .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        },
    );
    if (current_fd < 0) return systemError(errnoValue());
    defer {
        if (current_fd >= 0) _ = c.close(current_fd);
    }

    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".")) continue;
        if (std.mem.eql(u8, component, "..")) {
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        }
        if (component.len > std.fs.max_name_bytes) {
            return systemError(ENAMETOOLONG);
        }

        var component_buf: [std.fs.max_name_bytes + 1]u8 = undefined;
        @memcpy(component_buf[0..component.len], component);
        component_buf[component.len] = 0;
        const component_z: [*:0]const u8 = @ptrCast(&component_buf);
        const next_fd = std.c.openat(current_fd, component_z, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (next_fd < 0) return systemError(errnoValue());
        _ = c.close(current_fd);
        current_fd = next_fd;
    }

    output.* = current_fd;
    current_fd = -1;
    return 0;
}

fn pinParent(path_z: [*:0]const u8, output: *PinnedParent) u32 {
    const path = std.mem.span(path_z);
    if (path.len == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;

    var end = path.len;
    while (end > 1 and path[end - 1] == '/') : (end -= 1) {}
    const trimmed = path[0..end];
    const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/');
    const basename = if (slash) |index| trimmed[index + 1 ..] else trimmed;
    if (!isSafeComponent(basename)) return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (basename.len > std.fs.max_name_bytes) {
        return systemError(ENAMETOOLONG);
    }

    const parent_path = if (slash) |index|
        if (index == 0) "/" else trimmed[0..index]
    else
        ".";
    var parent_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
    if (parent_path.len >= parent_buf.len) return systemError(ENAMETOOLONG);
    @memcpy(parent_buf[0..parent_path.len], parent_path);
    parent_buf[parent_path.len] = 0;
    const parent_z: [*:0]const u8 = @ptrCast(&parent_buf);

    var parent_fd: c_int = -1;
    const result = openDirectoryPathNoFollow(parent_z, &parent_fd);
    if (result != 0) return result;

    output.* = .{
        .fd = parent_fd,
        .name = undefined,
    };
    @memcpy(output.name[0..basename.len], basename);
    output.name[basename.len] = 0;
    return 0;
}

fn openCacheRoot(handle: *Tdnf, output: *c_int) u32 {
    const conf = handle.pConf;
    if (conf == null) return errors.ERROR_TDNF_INVALID_CONF;
    const cache_dir = cString(conf.?.pszCacheDir) orelse
        return errors.ERROR_TDNF_INVALID_CONF;
    if (cache_dir[0] == 0) return errors.ERROR_TDNF_INVALID_CONF;
    return openDirectoryPathNoFollow(cache_dir, output);
}

fn openDirectoryAt(
    parent_fd: c_int,
    name: [*:0]const u8,
    output: *c_int,
) u32 {
    const fd = std.c.openat(parent_fd, name, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    if (fd < 0) return systemError(errnoValue());
    output.* = fd;
    return 0;
}

fn productionUnlinkAt(
    _: ?*anyopaque,
    parent_fd: c_int,
    name: [*:0]const u8,
    flags: c_int,
) c_int {
    return c.unlinkat(parent_fd, name, @intCast(flags));
}

const production_remove_ops = RemoveOps{
    .unlinkAt = productionUnlinkAt,
};

fn removalError(name: [*:0]const u8, value: c_int) u32 {
    if (!builtin.is_test) {
        common.log(LOG_CRIT, "unable to remove %s: %s\n", .{ name, libc.strerror(value) });
    }
    return systemError(value);
}

fn unlinkWithOps(
    parent_fd: c_int,
    name: [*:0]const u8,
    flags: c_int,
    ops: RemoveOps,
) u32 {
    if (ops.unlinkAt(ops.context, parent_fd, name, flags) == 0) return 0;
    const value = errnoValue();
    if (value == ENOENT) return 0;
    return removalError(name, value);
}

fn removeDirectoryContentsWithOps(
    directory_fd: c_int,
    ops: RemoveOps,
) u32 {
    const scan_fd = std.c.fcntl(
        directory_fd,
        std.c.F.DUPFD_CLOEXEC,
        @as(c_int, 0),
    );
    if (scan_fd < 0) return systemError(errnoValue());
    const stream = c.fdopendir(scan_fd);
    if (stream == null) {
        _ = c.close(scan_fd);
        return systemError(errnoValue());
    }
    defer _ = c.closedir(stream.?);

    while (true) {
        std.c._errno().* = 0;
        const entry = c.readdir(stream.?);
        if (entry == null) {
            const value = errnoValue();
            if (value != 0) return systemError(value);
            return 0;
        }
        const name_z: [*:0]const u8 = @ptrCast(&entry.?.name);
        const name = std.mem.span(name_z);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) {
            continue;
        }
        const result = removeEntryAtWithOps(directory_fd, name_z, ops);
        if (result != 0) return result;
    }
}

fn removeEntryAtWithOps(
    parent_fd: c_int,
    name: [*:0]const u8,
    ops: RemoveOps,
) u32 {
    // A directory is opened and pinned before traversal. Non-directories,
    // including symlinks, are unlinked as entries and are never followed.
    const child_fd = std.c.openat(parent_fd, name, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    if (child_fd < 0) {
        const value = errnoValue();
        return switch (value) {
            ENOENT => 0,
            ELOOP, ENOTDIR => unlinkWithOps(parent_fd, name, 0, ops),
            else => systemError(value),
        };
    }
    defer _ = c.close(child_fd);

    const result = removeDirectoryContentsWithOps(child_fd, ops);
    if (result != 0) return result;
    return unlinkWithOps(parent_fd, name, at_removedir, ops);
}

fn removePathWithOps(path: [*:0]const u8, ops: RemoveOps) u32 {
    var parent: PinnedParent = undefined;
    const result = pinParent(path, &parent);
    if (result == systemError(ENOENT)) return 0;
    if (result != 0) return result;
    defer parent.deinit();
    return removeEntryAtWithOps(parent.fd, parent.nameZ(), ops);
}

fn openCacheRepository(
    handle: *Tdnf,
    repo: *RepoData,
    basis: RepoPathBasis,
    root_fd: *c_int,
    repo_fd: *c_int,
) u32 {
    const component = checkedRepositoryComponent(repo, basis) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var root: c_int = -1;
    var result = openCacheRoot(handle, &root);
    if (result != 0) return result;

    var directory: c_int = -1;
    result = openDirectoryAt(root, component, &directory);
    if (result != 0) {
        _ = c.close(root);
        return result;
    }
    root_fd.* = root;
    repo_fd.* = directory;
    return 0;
}

fn removeCacheChildWithOps(
    handle: ?*Tdnf,
    repo: ?*RepoData,
    basis: RepoPathBasis,
    name: [*:0]const u8,
    ops: RemoveOps,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_data = repo orelse return errors.ERROR_TDNF_INVALID_PARAMETER;

    var root_fd: c_int = -1;
    var repo_fd: c_int = -1;
    const result = openCacheRepository(
        tdnf,
        repo_data,
        basis,
        &root_fd,
        &repo_fd,
    );
    if (result == systemError(ENOENT)) return 0;
    if (result != 0) return result;
    defer _ = c.close(repo_fd);
    defer _ = c.close(root_fd);
    return removeEntryAtWithOps(repo_fd, name, ops);
}

fn removeRepoCacheFile(
    handle: ?*Tdnf,
    repo: ?*RepoData,
    filename: [*:0]const u8,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_data = repo orelse return errors.ERROR_TDNF_INVALID_PARAMETER;

    var root_fd: c_int = -1;
    var repo_fd: c_int = -1;
    const result = openCacheRepository(
        tdnf,
        repo_data,
        .cache_name,
        &root_fd,
        &repo_fd,
    );
    if (result == systemError(ENOENT)) return 0;
    if (result != 0) return result;
    defer _ = c.close(repo_fd);
    defer _ = c.close(root_fd);
    return unlinkWithOps(repo_fd, filename, 0, production_remove_ops);
}

pub export fn TDNFRepoRemoveCacheDir(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_data = repo orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const component = checkedRepositoryComponent(repo_data, .cache_name) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var root_fd: c_int = -1;
    const result = openCacheRoot(tdnf, &root_fd);
    if (result == systemError(ENOENT)) return 0;
    if (result != 0) return result;
    defer _ = c.close(root_fd);
    return unlinkWithOps(
        root_fd,
        component,
        at_removedir,
        production_remove_ops,
    );
}

pub export fn TDNFRepoRemoveCache(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) u32 {
    return removeCacheChildWithOps(
        handle,
        repo,
        .cache_name,
        repodata_dir_name,
        production_remove_ops,
    );
}

pub export fn TDNFRemoveRpmCache(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) u32 {
    return removeCacheChildWithOps(
        handle,
        repo,
        .id,
        rpm_cache_dir_name,
        production_remove_ops,
    );
}

pub export fn TDNFRemoveTmpRepodata(
    path: ?[*:0]const u8,
) u32 {
    if (isNullOrEmpty(path)) return errors.ERROR_TDNF_INVALID_PARAMETER;
    return removePathWithOps(path.?, production_remove_ops);
}

pub export fn TDNFRemoveLastRefreshMarker(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) u32 {
    return removeRepoCacheFile(handle, repo, metadata_marker);
}

pub export fn TDNFRemoveMirrorList(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) u32 {
    return removeRepoCacheFile(handle, repo, metadata_mirrorlist);
}

pub export fn TDNFRemoveSnapshot(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_data = repo orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var root_fd: c_int = -1;
    var repo_fd: c_int = -1;
    const result = openCacheRepository(
        tdnf,
        repo_data,
        .cache_name,
        &root_fd,
        &repo_fd,
    );
    if (result == systemError(ENOENT)) return 0;
    if (result != 0) return result;
    defer _ = c.close(repo_fd);
    defer _ = c.close(root_fd);

    const scan_fd = std.c.fcntl(
        repo_fd,
        std.c.F.DUPFD_CLOEXEC,
        @as(c_int, 0),
    );
    if (scan_fd < 0) return systemError(errnoValue());
    const stream = c.fdopendir(scan_fd);
    if (stream == null) {
        _ = c.close(scan_fd);
        return systemError(errnoValue());
    }
    defer _ = c.closedir(stream.?);

    while (true) {
        std.c._errno().* = 0;
        const entry = c.readdir(stream.?);
        if (entry == null) {
            const value = errnoValue();
            if (value != 0) return systemError(value);
            return 0;
        }
        const name_z: [*:0]const u8 = @ptrCast(&entry.?.name);
        const name = std.mem.span(name_z);
        if (!std.mem.startsWith(u8, name, metadata_snapshot_prefix ++ "-")) {
            continue;
        }
        const unlink_result = unlinkWithOps(
            repo_fd,
            name_z,
            0,
            production_remove_ops,
        );
        if (unlink_result != 0) return unlink_result;
    }
}

fn removeNamedTree(
    handle: ?*Tdnf,
    repo: ?*RepoData,
    name: [*:0]const u8,
) u32 {
    return removeCacheChildWithOps(
        handle,
        repo,
        .cache_name,
        name,
        production_remove_ops,
    );
}

pub export fn TDNFRemoveSolvCache(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) u32 {
    return removeNamedTree(handle, repo, solv_cache_dir_name);
}

pub export fn TDNFRemoveKeysCache(
    handle: ?*Tdnf,
    repo: ?*RepoData,
) u32 {
    return removeNamedTree(handle, repo, "keys");
}

pub export fn TDNFGetCachePath(
    handle: ?*Tdnf,
    repo: ?*RepoData,
    subdir: ?[*:0]const u8,
    filename: ?[*:0]const u8,
    output: ?*?[*:0]u8,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_data = repo orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    return getCachePath(tdnf, repo_data, subdir, filename, out);
}

pub export fn RepoutilsGetRpmCachePath(
    handle: ?*Tdnf,
    repo: ?*RepoData,
    output: ?*?[*:0]u8,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_data = repo orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    // The downloader has always stored RPMs under pszId, not pszCacheName.
    return getCachePathWithBasis(
        tdnf,
        repo_data,
        .id,
        rpm_cache_dir_name,
        null,
        out,
    );
}

pub export fn TDNFFindRepoById(
    handle: ?*Tdnf,
    repo_id: ?[*:0]const u8,
    output: ?*?*RepoData,
) u32 {
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const id = repo_id orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (id[0] == 0 or output == null) return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (tdnf.pRepos == null) return errors.ERROR_TDNF_NO_REPOS;

    var current = tdnf.pRepos;
    while (current) |repo| : (current = repo.pNext) {
        const current_id = cString(repo.pszId) orelse continue;
        if (std.mem.eql(u8, std.mem.span(id), std.mem.span(current_id))) {
            output.?.* = repo;
            return 0;
        }
    }
    return errors.ERROR_TDNF_REPO_NOT_FOUND;
}

pub export fn TDNFTouchFile(path: ?[*:0]const u8) u32 {
    if (isNullOrEmpty(path)) return errors.ERROR_TDNF_INVALID_PARAMETER;

    var parent: PinnedParent = undefined;
    const pin_result = pinParent(path.?, &parent);
    if (pin_result != 0) return pin_result;
    defer parent.deinit();

    const old_mask = c.umask(0o22);
    defer _ = c.umask(old_mask);
    const fd = std.c.openat(parent.fd, parent.nameZ(), .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    }, @as(
        std.c.mode_t,
        std.c.S.IRUSR | std.c.S.IWUSR | std.c.S.IRGRP | std.c.S.IROTH,
    ));
    if (fd < 0) return systemError(errnoValue());
    defer _ = c.close(fd);
    if (c.futimens(fd, null) != 0) return systemError(errnoValue());
    return 0;
}

fn metadataExpired(
    current: c.time_t,
    changed: c.time_t,
    expire: c_long,
) bool {
    return libc.difftime(current, changed) > @as(f64, @floatFromInt(expire));
}

pub export fn TDNFShouldSyncMetadata(
    repo_data_folder: ?[*:0]const u8,
    metadata_expire: c_long,
    output: ?*c_int,
) u32 {
    if (output) |out| out.* = 0;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (isNullOrEmpty(repo_data_folder)) return errors.ERROR_TDNF_INVALID_PARAMETER;

    var marker: ?[*:0]u8 = null;
    const result = joinPath(
        &marker,
        &.{ repo_data_folder, metadata_marker },
    );
    if (result != 0) return result;
    defer freeCString(marker);

    var stat_buf = std.mem.zeroes(Stat);
    if (statPath(marker.?, false, &stat_buf) != 0) {
        const stat_errno = errnoValue();
        if (stat_errno == ENOENT) {
            out.* = 1;
            return 0;
        }
        return systemError(stat_errno);
    }

    if (metadataExpired(libc.time(null), stat_buf.ctime.sec, metadata_expire)) {
        out.* = 1;
    }
    return 0;
}

const testing = std.testing;

const Fixture = struct {
    tmp: testing.TmpDir,
    cache_dir: [:0]u8,
    conf: Conf,
    repo: RepoData,
    second_repo: RepoData,
    handle_value: Tdnf,

    fn init() !Fixture {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();
        const cache_dir = try std.fmt.allocPrintSentinel(
            testing.allocator,
            ".zig-cache/tmp/{s}/cache-root",
            .{&tmp.sub_path},
            0,
        );
        errdefer testing.allocator.free(cache_dir);

        return .{
            .tmp = tmp,
            .cache_dir = cache_dir,
            .conf = std.mem.zeroes(Conf),
            .repo = std.mem.zeroes(RepoData),
            .second_repo = std.mem.zeroes(RepoData),
            .handle_value = std.mem.zeroes(Tdnf),
        };
    }

    fn deinit(self: *Fixture) void {
        testing.allocator.free(self.cache_dir);
        self.tmp.cleanup();
    }

    fn handle(self: *Fixture) *Tdnf {
        self.conf.pszCacheDir = @ptrCast(self.cache_dir.ptr);
        self.repo.pszId = @constCast("repo-id");
        self.repo.pszCacheName = @constCast("repo-cache");
        self.repo.pNext = &self.second_repo;
        self.second_repo.pszId = @constCast("second");
        self.second_repo.pNext = null;
        self.handle_value.pConf = &self.conf;
        self.handle_value.pRepos = &self.repo;
        return &self.handle_value;
    }

    fn repoPath(self: *Fixture, suffix: []const u8) ![:0]u8 {
        return std.fmt.allocPrintSentinel(
            testing.allocator,
            "{s}/repo-cache/{s}",
            .{ self.cache_dir, suffix },
            0,
        );
    }
};

fn expectPathMissing(dir: std.Io.Dir, path: []const u8) !void {
    try testing.expectError(error.FileNotFound, dir.access(testing.io, path, .{}));
}

fn expectPathPresent(dir: std.Io.Dir, path: []const u8) !void {
    try dir.access(testing.io, path, .{});
}

const FailingUnlink = struct {
    name: []const u8,
    error_value: c_int,
};

fn injectedUnlinkFailure(
    context: ?*anyopaque,
    parent_fd: c_int,
    name: [*:0]const u8,
    flags: c_int,
) c_int {
    const failure: *FailingUnlink = @ptrCast(@alignCast(context.?));
    if (std.mem.eql(u8, std.mem.span(name), failure.name)) {
        std.c._errno().* = failure.error_value;
        return -1;
    }
    return c.unlinkat(parent_fd, name, @intCast(flags));
}

test "cache path construction and repository lookup preserve ABI ownership" {
    var fixture = try Fixture.init();
    defer fixture.deinit();

    var path: ?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFGetCachePath(
            fixture.handle(),
            &fixture.repo,
            "repodata",
            "repomd.xml",
            &path,
        ),
    );
    defer freeCString(path);
    const expected = try fixture.repoPath("repodata/repomd.xml");
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, std.mem.span(path.?));
    freeCString(path);
    path = null;

    const handle = fixture.handle();
    fixture.repo.pszCacheName = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFGetCachePath(
            handle,
            &fixture.repo,
            null,
            "ignored-after-null",
            &path,
        ),
    );
    const id_path = try std.fmt.allocPrint(
        testing.allocator,
        "{s}/repo-id",
        .{fixture.cache_dir},
    );
    defer testing.allocator.free(id_path);
    try testing.expectEqualStrings(id_path, std.mem.span(path.?));

    var found: ?*RepoData = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFFindRepoById(fixture.handle(), "second", &found),
    );
    try testing.expect(found == &fixture.second_repo);
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_REPO_NOT_FOUND),
        TDNFFindRepoById(fixture.handle(), "missing", &found),
    );
    try testing.expect(found == &fixture.second_repo);
}

test "cache helpers reject invalid arguments and configuration" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var path: ?[*:0]u8 = @constCast("unchanged");
    var found: ?*RepoData = null;

    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFGetCachePath(null, &fixture.repo, null, null, &path),
    );
    try testing.expectEqualStrings("unchanged", std.mem.span(path.?));
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFGetCachePath(fixture.handle(), null, null, null, &path),
    );
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFGetCachePath(fixture.handle(), &fixture.repo, null, null, null),
    );
    fixture.handle_value.pConf = null;
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_CONF),
        TDNFGetCachePath(&fixture.handle_value, &fixture.repo, null, null, &path),
    );
    try testing.expectEqualStrings("unchanged", std.mem.span(path.?));
    fixture.handle_value.pConf = &fixture.conf;
    fixture.conf.pszCacheDir = null;
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_CONF),
        TDNFGetCachePath(&fixture.handle_value, &fixture.repo, null, null, &path),
    );
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_CONF),
        TDNFRemoveRpmCache(&fixture.handle_value, &fixture.repo),
    );
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFFindRepoById(fixture.handle(), "", &found),
    );
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFFindRepoById(fixture.handle(), "repo-id", null),
    );
    fixture.handle_value.pRepos = null;
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_NO_REPOS),
        TDNFFindRepoById(&fixture.handle_value, "repo-id", &found),
    );

    const invalid_calls = [_]u32{
        TDNFRepoRemoveCacheDir(null, &fixture.repo),
        TDNFRepoRemoveCache(null, &fixture.repo),
        TDNFRemoveRpmCache(null, &fixture.repo),
        TDNFRemoveLastRefreshMarker(null, &fixture.repo),
        TDNFRemoveMirrorList(null, &fixture.repo),
        TDNFRemoveSnapshot(null, &fixture.repo),
        TDNFRemoveSolvCache(null, &fixture.repo),
        TDNFRemoveKeysCache(null, &fixture.repo),
    };
    for (invalid_calls) |result| {
        try testing.expectEqual(
            @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
            result,
        );
    }
}

test "destructive cache operations reject traversal repository components" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "cache-root/repo-cache");
    try fixture.tmp.dir.createDirPath(testing.io, "outside");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "outside/sentinel",
        .data = "outside",
    });

    const handle = fixture.handle();
    const unsafe_names = [_][*:0]const u8{
        "..",
        "../outside",
        "nested/repo",
    };
    for (unsafe_names) |unsafe_name| {
        fixture.repo.pszCacheName = @constCast(unsafe_name);
        try testing.expectEqual(
            @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
            TDNFRepoRemoveCache(handle, &fixture.repo),
        );
        try testing.expectEqual(
            @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
            TDNFRemoveLastRefreshMarker(handle, &fixture.repo),
        );
        var path: ?[*:0]u8 = null;
        try testing.expectEqual(
            @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
            TDNFGetCachePath(handle, &fixture.repo, null, null, &path),
        );
        try testing.expect(path == null);
    }

    fixture.repo.pszCacheName = @constCast("repo-cache");
    fixture.repo.pszId = @constCast("../outside");
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFRemoveRpmCache(handle, &fixture.repo),
    );
    var rpm_path: ?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        RepoutilsGetRpmCachePath(handle, &fixture.repo, &rpm_path),
    );
    try testing.expect(rpm_path == null);
    try expectPathPresent(fixture.tmp.dir, "outside/sentinel");
}

test "destructive cache operations reject malicious ancestor symlinks" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "cache-root");
    try fixture.tmp.dir.createDirPath(testing.io, "outside");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "outside/sentinel",
        .data = "outside",
    });
    try fixture.tmp.dir.symLink(
        testing.io,
        "../outside",
        "cache-root/repo-cache",
        .{ .is_directory = true },
    );

    const remove_result = TDNFRepoRemoveCache(
        fixture.handle(),
        &fixture.repo,
    );
    try testing.expect(
        remove_result == systemError(ELOOP) or
            remove_result == systemError(ENOTDIR),
    );
    const marker_result = TDNFRemoveLastRefreshMarker(
        fixture.handle(),
        &fixture.repo,
    );
    try testing.expect(
        marker_result == systemError(ELOOP) or
            marker_result == systemError(ENOTDIR),
    );
    try expectPathPresent(fixture.tmp.dir, "outside/sentinel");

    try fixture.tmp.dir.deleteFile(testing.io, "cache-root/repo-cache");
    try fixture.tmp.dir.deleteDir(testing.io, "cache-root");
    try fixture.tmp.dir.symLink(
        testing.io,
        "outside",
        "cache-root",
        .{ .is_directory = true },
    );
    const root_result = TDNFRemoveKeysCache(
        fixture.handle(),
        &fixture.repo,
    );
    try testing.expect(
        root_result == systemError(ELOOP) or
            root_result == systemError(ENOTDIR),
    );
    try expectPathPresent(fixture.tmp.dir, "outside/sentinel");
}

test "recursive removal returns injected unlink failure and leaves entry" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(
        testing.io,
        "cache-root/repo-cache/repodata",
    );
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-cache/repodata/blocked",
        .data = "keep",
    });

    var failure = FailingUnlink{
        .name = "blocked",
        .error_value = EACCES,
    };
    const result = removeCacheChildWithOps(
        fixture.handle(),
        &fixture.repo,
        .cache_name,
        repodata_dir_name,
        .{
            .context = &failure,
            .unlinkAt = injectedUnlinkFailure,
        },
    );
    try testing.expectEqual(systemError(EACCES), result);
    try expectPathPresent(
        fixture.tmp.dir,
        "cache-root/repo-cache/repodata/blocked",
    );
}

test "repo top-level cache removal handles missing empty and wrong file states" {
    var fixture = try Fixture.init();
    defer fixture.deinit();

    try testing.expectEqual(
        @as(u32, 0),
        TDNFRepoRemoveCacheDir(fixture.handle(), &fixture.repo),
    );

    try fixture.tmp.dir.createDirPath(testing.io, "cache-root/repo-cache");
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRepoRemoveCacheDir(fixture.handle(), &fixture.repo),
    );
    try expectPathMissing(fixture.tmp.dir, "cache-root/repo-cache");

    try fixture.tmp.dir.createDirPath(testing.io, "cache-root");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-cache",
        .data = "file",
    });
    try testing.expectEqual(
        systemError(ENOTDIR),
        TDNFRepoRemoveCacheDir(fixture.handle(), &fixture.repo),
    );
    try fixture.tmp.dir.deleteFile(testing.io, "cache-root/repo-cache");

    try fixture.tmp.dir.symLink(
        testing.io,
        "missing-target",
        "cache-root/repo-cache",
        .{},
    );
    try testing.expectEqual(
        systemError(ENOTDIR),
        TDNFRepoRemoveCacheDir(fixture.handle(), &fixture.repo),
    );
}

test "recursive repository cache removal handles files symlinks nested dirs and scope" {
    var fixture = try Fixture.init();
    defer fixture.deinit();

    const states = [_]enum { file, symlink, nested_dir }{
        .file,
        .symlink,
        .nested_dir,
    };
    try fixture.tmp.dir.createDirPath(testing.io, "outside");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "outside/data",
        .data = "outside",
    });
    for (states) |state| {
        try fixture.tmp.dir.createDirPath(testing.io, "cache-root/repo-cache");
        switch (state) {
            .file => try fixture.tmp.dir.writeFile(testing.io, .{
                .sub_path = "cache-root/repo-cache/repodata",
                .data = "metadata",
            }),
            .symlink => try fixture.tmp.dir.symLink(
                testing.io,
                "../../outside",
                "cache-root/repo-cache/repodata",
                .{ .is_directory = true },
            ),
            .nested_dir => {
                try fixture.tmp.dir.createDirPath(
                    testing.io,
                    "cache-root/repo-cache/repodata/a/b",
                );
                try fixture.tmp.dir.writeFile(testing.io, .{
                    .sub_path = "cache-root/repo-cache/repodata/a/b/data",
                    .data = "metadata",
                });
            },
        }
        try fixture.tmp.dir.writeFile(testing.io, .{
            .sub_path = "cache-root/repo-cache/keep",
            .data = "keep",
        });
        try testing.expectEqual(
            @as(u32, 0),
            TDNFRepoRemoveCache(fixture.handle(), &fixture.repo),
        );
        try expectPathMissing(fixture.tmp.dir, "cache-root/repo-cache/repodata");
        try expectPathPresent(fixture.tmp.dir, "cache-root/repo-cache/keep");
        try expectPathPresent(fixture.tmp.dir, "outside/data");
        try fixture.tmp.dir.deleteFile(testing.io, "cache-root/repo-cache/keep");
    }
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRepoRemoveCache(fixture.handle(), &fixture.repo),
    );
}

test "named recursive caches remove only their own trees" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(
        testing.io,
        "cache-root/repo-cache/solvcache/nested",
    );
    try fixture.tmp.dir.createDirPath(
        testing.io,
        "cache-root/repo-cache/keys/nested",
    );
    try fixture.tmp.dir.createDirPath(
        testing.io,
        "cache-root/repo-id/rpms/nested",
    );
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-cache/keep",
        .data = "keep",
    });

    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveSolvCache(fixture.handle(), &fixture.repo),
    );
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveKeysCache(fixture.handle(), &fixture.repo),
    );
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveRpmCache(fixture.handle(), &fixture.repo),
    );
    try expectPathMissing(fixture.tmp.dir, "cache-root/repo-cache/solvcache");
    try expectPathMissing(fixture.tmp.dir, "cache-root/repo-cache/keys");
    try expectPathMissing(fixture.tmp.dir, "cache-root/repo-id/rpms");
    try expectPathPresent(fixture.tmp.dir, "cache-root/repo-cache/keep");

    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveSolvCache(fixture.handle(), &fixture.repo),
    );
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveKeysCache(fixture.handle(), &fixture.repo),
    );
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveRpmCache(fixture.handle(), &fixture.repo),
    );
}

test "rpm cleanup uses downloader ID path when cache name differs" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(
        testing.io,
        "cache-root/repo-id/rpms/packages",
    );

    var rpm_cache_path: ?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        RepoutilsGetRpmCachePath(
            fixture.handle(),
            &fixture.repo,
            &rpm_cache_path,
        ),
    );
    defer freeCString(rpm_cache_path);
    const expected_path = try std.fmt.allocPrint(
        testing.allocator,
        "{s}/repo-id/rpms",
        .{fixture.cache_dir},
    );
    defer testing.allocator.free(expected_path);
    try testing.expectEqualStrings(
        expected_path,
        std.mem.span(rpm_cache_path.?),
    );
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-id/rpms/packages/downloaded.rpm",
        .data = "rpm",
    });
    try fixture.tmp.dir.createDirPath(
        testing.io,
        "cache-root/repo-cache/rpms",
    );
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-cache/rpms/not-downloader-path.rpm",
        .data = "keep",
    });
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveRpmCache(fixture.handle(), &fixture.repo),
    );
    try expectPathMissing(fixture.tmp.dir, "cache-root/repo-id/rpms");
    try expectPathPresent(
        fixture.tmp.dir,
        "cache-root/repo-cache/rpms/not-downloader-path.rpm",
    );

    try fixture.tmp.dir.createDirPath(testing.io, "outside-rpms");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "outside-rpms/package.rpm",
        .data = "outside",
    });
    try fixture.tmp.dir.symLink(
        testing.io,
        "../../outside-rpms",
        "cache-root/repo-id/rpms",
        .{ .is_directory = true },
    );
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveRpmCache(fixture.handle(), &fixture.repo),
    );
    try expectPathMissing(fixture.tmp.dir, "cache-root/repo-id/rpms");
    try expectPathPresent(fixture.tmp.dir, "outside-rpms/package.rpm");

    try fixture.tmp.dir.symLink(
        testing.io,
        "missing-target",
        "cache-root/repo-id/rpms",
        .{ .is_directory = true },
    );

    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveRpmCache(fixture.handle(), &fixture.repo),
    );
    try expectPathMissing(fixture.tmp.dir, "cache-root/repo-id/rpms");
}

test "temporary repodata removal is idempotent and root-scoped" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "tmp-repodata/a/b");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "tmp-repodata/a/b/data",
        .data = "data",
    });
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "outside",
        .data = "keep",
    });
    const path = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/tmp-repodata",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(path);

    try testing.expectEqual(@as(u32, 0), TDNFRemoveTmpRepodata(path.ptr));
    try testing.expectEqual(@as(u32, 0), TDNFRemoveTmpRepodata(path.ptr));
    try expectPathMissing(fixture.tmp.dir, "tmp-repodata");
    try expectPathPresent(fixture.tmp.dir, "outside");
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFRemoveTmpRepodata(""),
    );

    try fixture.tmp.dir.createDirPath(testing.io, "outside-tmp");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "outside-tmp/sentinel",
        .data = "outside",
    });
    try fixture.tmp.dir.symLink(
        testing.io,
        "outside-tmp",
        "tmp-alias",
        .{ .is_directory = true },
    );
    const redirected = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/tmp-alias/sentinel",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(redirected);
    const redirected_result = TDNFRemoveTmpRepodata(redirected.ptr);
    try testing.expect(
        redirected_result == systemError(ELOOP) or
            redirected_result == systemError(ENOTDIR),
    );
    try expectPathPresent(fixture.tmp.dir, "outside-tmp/sentinel");
}

test "marker and mirror removal handle missing files symlinks and directories" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "cache-root/repo-cache");

    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveLastRefreshMarker(fixture.handle(), &fixture.repo),
    );
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-cache/lastrefresh",
        .data = "marker",
    });
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveLastRefreshMarker(fixture.handle(), &fixture.repo),
    );
    try fixture.tmp.dir.symLink(
        testing.io,
        "target",
        "cache-root/repo-cache/mirrorlist",
        .{},
    );
    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveMirrorList(fixture.handle(), &fixture.repo),
    );
    try fixture.tmp.dir.createDirPath(
        testing.io,
        "cache-root/repo-cache/lastrefresh/nested",
    );
    try testing.expectEqual(
        systemError(EISDIR),
        TDNFRemoveLastRefreshMarker(fixture.handle(), &fixture.repo),
    );
}

test "snapshot removal matches only snapshot dash entries" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "cache-root/repo-cache");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-cache/snapshot-one",
        .data = "one",
    });
    try fixture.tmp.dir.symLink(
        testing.io,
        "missing",
        "cache-root/repo-cache/snapshot-two",
        .{},
    );
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-cache/snapshot",
        .data = "keep",
    });
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "cache-root/repo-cache/snapshot.other",
        .data = "keep",
    });

    try testing.expectEqual(
        @as(u32, 0),
        TDNFRemoveSnapshot(fixture.handle(), &fixture.repo),
    );
    try expectPathMissing(fixture.tmp.dir, "cache-root/repo-cache/snapshot-one");
    const symlink = try fixture.repoPath("snapshot-two");
    defer testing.allocator.free(symlink);
    var stat_buf = std.mem.zeroes(Stat);
    try testing.expectEqual(@as(c_int, -1), statPath(symlink.ptr, true, &stat_buf));
    try expectPathPresent(fixture.tmp.dir, "cache-root/repo-cache/snapshot");
    try expectPathPresent(fixture.tmp.dir, "cache-root/repo-cache/snapshot.other");

    try fixture.tmp.dir.createDirPath(
        testing.io,
        "cache-root/repo-cache/snapshot-dir/nested",
    );
    try testing.expectEqual(
        systemError(EISDIR),
        TDNFRemoveSnapshot(fixture.handle(), &fixture.repo),
    );
}

test "touch creates and updates regular files without truncation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "touch/nested");
    const missing = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/touch/new",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(missing);
    try testing.expectEqual(@as(u32, 0), TDNFTouchFile(missing.ptr));
    try expectPathPresent(fixture.tmp.dir, "touch/new");

    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "touch/existing",
        .data = "contents",
    });
    const existing = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/touch/existing",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(existing);
    try testing.expectEqual(@as(u32, 0), TDNFTouchFile(existing.ptr));
    const contents = try fixture.tmp.dir.readFileAlloc(
        testing.io,
        "touch/existing",
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(contents);
    try testing.expectEqualStrings("contents", contents);

    var old_times = UtimeBuf{
        .actime = 1,
        .modtime = 1,
    };
    try testing.expectEqual(@as(c_int, 0), libc.utime(existing.ptr, &old_times));
    try testing.expectEqual(@as(u32, 0), TDNFTouchFile(existing.ptr));
    var existing_stat = std.mem.zeroes(Stat);
    try testing.expectEqual(
        @as(c_int, 0),
        statPath(existing.ptr, false, &existing_stat),
    );
    try testing.expect(existing_stat.mtime.sec > 1);
}

test "touch rejects symlinks and preserves outside targets" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "touch");

    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "touch/target",
        .data = "target",
    });
    try fixture.tmp.dir.symLink(
        testing.io,
        "target",
        "touch/link",
        .{},
    );
    const link = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/touch/link",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(link);
    const target_path = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/touch/target",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(target_path);
    var old_times = UtimeBuf{
        .actime = 1,
        .modtime = 1,
    };
    try testing.expectEqual(
        @as(c_int, 0),
        libc.utime(target_path.ptr, &old_times),
    );
    var before = std.mem.zeroes(Stat);
    try testing.expectEqual(@as(c_int, 0), statPath(target_path.ptr, false, &before));

    try testing.expectEqual(systemError(ELOOP), TDNFTouchFile(link.ptr));
    var after = std.mem.zeroes(Stat);
    try testing.expectEqual(@as(c_int, 0), statPath(target_path.ptr, false, &after));
    try testing.expectEqual(before.atime.sec, after.atime.sec);
    try testing.expectEqual(before.atime.nsec, after.atime.nsec);
    try testing.expectEqual(before.mtime.sec, after.mtime.sec);
    try testing.expectEqual(before.mtime.nsec, after.mtime.nsec);
    try testing.expectEqual(before.ctime.sec, after.ctime.sec);
    try testing.expectEqual(before.ctime.nsec, after.ctime.nsec);
    const target = try fixture.tmp.dir.readFileAlloc(
        testing.io,
        "touch/target",
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(target);
    try testing.expectEqualStrings("target", target);

    try fixture.tmp.dir.createDirPath(testing.io, "outside-touch");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "outside-touch/sentinel",
        .data = "outside",
    });
    try fixture.tmp.dir.symLink(
        testing.io,
        "../outside-touch",
        "touch/ancestor",
        .{ .is_directory = true },
    );
    const redirected = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/touch/ancestor/sentinel",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(redirected);
    const redirected_result = TDNFTouchFile(redirected.ptr);
    try testing.expect(
        redirected_result == systemError(ELOOP) or
            redirected_result == systemError(ENOTDIR),
    );
    const sentinel = try fixture.tmp.dir.readFileAlloc(
        testing.io,
        "outside-touch/sentinel",
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(sentinel);
    try testing.expectEqualStrings("outside", sentinel);
}

test "touch reports directory and missing-parent errors" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "touch/nested");

    const directory = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/touch/nested",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(directory);
    try testing.expectEqual(systemError(EISDIR), TDNFTouchFile(directory.ptr));
    const absent_parent = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/absent/file",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(absent_parent);
    try testing.expectEqual(
        systemError(ENOENT),
        TDNFTouchFile(absent_parent.ptr),
    );
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFTouchFile(null),
    );
}

test "metadata expiry comparison preserves strict boundary and signed time behavior" {
    try testing.expect(!metadataExpired(100, 90, 10));
    try testing.expect(metadataExpired(101, 90, 10));
    try testing.expect(!metadataExpired(89, 90, 0));
    try testing.expect(metadataExpired(100, 100, -1));
    try testing.expect(!metadataExpired(100, 200, -1));
    try testing.expect(metadataExpired(
        std.math.maxInt(c.time_t),
        std.math.maxInt(c.time_t) - 1,
        0,
    ));
}

test "metadata sync check handles missing file symlink directory and errors" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.tmp.dir.createDirPath(testing.io, "metadata");
    const folder = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/metadata",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(folder);

    var should_sync: c_int = -1;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFShouldSyncMetadata(folder.ptr, 3600, &should_sync),
    );
    try testing.expectEqual(@as(c_int, 1), should_sync);

    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "metadata/lastrefresh",
        .data = "",
    });
    try testing.expectEqual(
        @as(u32, 0),
        TDNFShouldSyncMetadata(folder.ptr, 3600, &should_sync),
    );
    try testing.expectEqual(@as(c_int, 0), should_sync);
    try testing.expectEqual(
        @as(u32, 0),
        TDNFShouldSyncMetadata(folder.ptr, -1, &should_sync),
    );
    try testing.expectEqual(@as(c_int, 1), should_sync);

    try fixture.tmp.dir.rename(
        "metadata/lastrefresh",
        fixture.tmp.dir,
        "metadata/target",
        testing.io,
    );
    try fixture.tmp.dir.symLink(
        testing.io,
        "target",
        "metadata/lastrefresh",
        .{},
    );
    try testing.expectEqual(
        @as(u32, 0),
        TDNFShouldSyncMetadata(folder.ptr, 3600, &should_sync),
    );
    try testing.expectEqual(@as(c_int, 0), should_sync);
    try fixture.tmp.dir.deleteFile(testing.io, "metadata/lastrefresh");
    try fixture.tmp.dir.deleteFile(testing.io, "metadata/target");
    try fixture.tmp.dir.symLink(
        testing.io,
        "missing",
        "metadata/lastrefresh",
        .{},
    );
    try testing.expectEqual(
        @as(u32, 0),
        TDNFShouldSyncMetadata(folder.ptr, 3600, &should_sync),
    );
    try testing.expectEqual(@as(c_int, 1), should_sync);
    try fixture.tmp.dir.deleteFile(testing.io, "metadata/lastrefresh");
    try fixture.tmp.dir.createDirPath(testing.io, "metadata/lastrefresh/nested");
    try testing.expectEqual(
        @as(u32, 0),
        TDNFShouldSyncMetadata(folder.ptr, 3600, &should_sync),
    );
    try testing.expectEqual(@as(c_int, 0), should_sync);

    should_sync = 9;
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFShouldSyncMetadata("", 1, &should_sync),
    );
    try testing.expectEqual(@as(c_int, 0), should_sync);
    try testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        TDNFShouldSyncMetadata(folder.ptr, 1, null),
    );

    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "not-a-directory",
        .data = "file",
    });
    const blocker = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/not-a-directory",
        .{&fixture.tmp.sub_path},
        0,
    );
    defer testing.allocator.free(blocker);
    try testing.expectEqual(
        systemError(ENOTDIR),
        TDNFShouldSyncMetadata(blocker.ptr, 1, &should_sync),
    );
    try testing.expectEqual(@as(c_int, 0), should_sync);

    if (c.geteuid() != 0) {
        try fixture.tmp.dir.createDirPath(testing.io, "denied");
        const denied = try std.fmt.allocPrintSentinel(
            testing.allocator,
            ".zig-cache/tmp/{s}/denied",
            .{&fixture.tmp.sub_path},
            0,
        );
        defer testing.allocator.free(denied);
        try testing.expectEqual(@as(c_int, 0), c.chmod(denied.ptr, 0));
        defer _ = c.chmod(denied.ptr, 0o700);
        try testing.expectEqual(
            systemError(EACCES),
            TDNFShouldSyncMetadata(denied.ptr, 1, &should_sync),
        );
        try testing.expectEqual(@as(c_int, 0), should_sync);
    }
}
