// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("tdnf_common");
const builtin = @import("builtin");
const abi = @import("client_abi");
const client_download = @import("client_download");
const errors = @import("tdnf_error");
const uri_sanitize = @import("uri_sanitize");

const CnfNode = abi.CnfNode;
const Conf = abi.Conf;
const DownloadToFdRequest = client_download.DownloadToFdRequest;
const RepoData = abi.RepoData;
const RepoMetadata = abi.RepoMetadata;
const RepoMdRecord = abi.RepoMdRecord;
const Tdnf = abi.Tdnf;

const CnfModule = opaque {};
const RepoMdDoc = opaque {};
const DIR = opaque {};

const Dirent = extern struct {
    ino: u64,
    off: i64,
    reclen: c_ushort,
    type: u8,
    name: [256]u8,
};

const SockaddrUn = extern struct {
    family: std.c.sa_family_t,
    path: [108]u8,
};

const Stat = std.os.linux.Statx;
const mode_type_mask = std.os.linux.S.IFMT;
const mode_regular = std.os.linux.S.IFREG;
const at_symlink_nofollow = std.os.linux.AT.SYMLINK_NOFOLLOW;

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const LOG_CRIT: c_int = 2;
const LOG_NOTICE: c_int = 3;

const system_repo_name = "@System";
const cmdline_repo_name = "@cmdline";
const repo_extension = ".repo";
const repomd_file_path = "repodata/repomd.xml";
const repomd_file_name = "repomd.xml";
const metadata_marker = "lastrefresh";
const metadata_mirrorlist = "mirrorlist";
const metadata_snapshot = "snapshot";
const cookie_len = 32;
const download_temp_attempts = 64;

var download_progress_data = DownloadProgressData{};

const ScanFailureStage = enum {
    directory_open,
    duplicate,
    fdopendir,
    readdir,
    pre_stat,
    entry_open,
    post_stat,
};

const ScanFailure = struct {
    stage: ScanFailureStage,
    errno_value: c_int,
    triggered: bool = false,
};

const CloseFailure = struct {
    errno_value: c_int,
    triggered: bool = false,
};

const SyncFailureStage = enum {
    file,
    source_directory,
    destination_directory,
};

const SyncFailure = struct {
    stage: SyncFailureStage,
    errno_value: c_int,
    triggered: bool = false,
};

const ResetFailureStage = enum {
    truncate,
    seek,
};

const ResetFailure = struct {
    stage: ResetFailureStage,
    errno_value: c_int,
    triggered: bool = false,
};

const PartialDownloadFailure = struct {
    url: []const u8,
    bytes: []const u8,
    remaining: usize,
    triggered: usize = 0,
};

const DownloadErrorFailure = struct {
    url: []const u8,
    err: anyerror,
    remaining: usize,
    triggered: usize = 0,
};

var injected_scan_failure: ?ScanFailure = null;
var injected_close_failure: ?CloseFailure = null;
var injected_sync_failure: ?SyncFailure = null;
var injected_reset_failure: ?ResetFailure = null;
var injected_partial_download_failure: ?PartialDownloadFailure = null;
var injected_download_error_failure: ?DownloadErrorFailure = null;
var suppress_test_info_logs = false;
var sync_stage_counts = [_]usize{0} ** 3;

const repomd_primary = "primary";
const repomd_filelists = "filelists";
const repomd_updateinfo = "updateinfo";
const repomd_other = "other";
const record_kind_updateinfo: u32 = 4;

const default_enabled = 0;
const default_skip = 0;
const default_minrate = 0;
const default_throttle = 0;
const default_timeout = 0;
const default_retries = 10;
const default_priority = 50;
const default_metadata_expire = 172800;
const default_skip_filelists = 0;
const default_skip_updateinfo = 0;
const default_skip_other = 0;

const DownloadProgressData = struct {
    text: [1024]u8 = [_]u8{0} ** 1024,
    previous_time: std.c.time_t = 0,
};

extern fn TDNFAllocateMemory(usize, usize, *?*anyopaque) u32;
extern fn TDNFAllocateString(?[*:0]const u8, *?[*:0]u8) u32;
extern fn TDNFFreeMemory(?*anyopaque) void;
extern fn TDNFFreeStringArray(?[*]?[*:0]u8) void;
extern fn TDNFAllocateStringArray(?[*]?[*:0]u8, *?[*]?[*:0]u8) u32;
extern fn TDNFAddStringArray(*?[*]?[*:0]u8, ?[*:0]const u8) u32;
extern fn TDNFSplitStringToArray(?[*:0]const u8, ?[*:0]const u8, *?[*]?[*:0]u8) u32;
extern fn TDNFMergeStringArrays(*?[*]?[*:0]u8, ?[*]?[*:0]u8) u32;
extern fn TDNFReadFileToStringArray(?[*:0]const u8, *?[*]?[*:0]u8) u32;
extern fn TDNFJoinPathFromArray(*?[*:0]u8, [*]?[*:0]u8, c_int) u32;
extern fn TDNFAppendPath(?[*:0]const u8, ?[*:0]const u8, *?[*:0]u8) u32;
extern fn TDNFParseMetadataExpire(?[*:0]const u8, *c_long) u32;
extern fn TDNFConfigReplaceVars(?*Tdnf, *?[*:0]u8) u32;
extern fn TDNFIsDir(?[*:0]const u8, *c_int) u32;
extern fn TDNFUriIsRemote(?[*:0]const u8, *c_int) u32;
extern fn TDNFIsGlob(?[*:0]const u8) c_int;
extern fn isTrue(?[*:0]const u8) c_int;
extern fn strtoi(?[*:0]const u8) i32;
extern fn find_cnfmodule(?[*:0]const u8) ?*CnfModule;
extern fn cnfmodule_parse_file(?*CnfModule, ?[*:0]const u8) ?*CnfNode;
extern fn destroy_cnftree(?*CnfNode) void;
extern fn find_node(?*CnfNode, ?[*:0]const u8) ?*CnfNode;
extern fn readdir(*DIR) ?*Dirent;
extern fn closedir(*DIR) c_int;
extern fn fdopendir(c_int) ?*DIR;
extern fn mkfifo([*:0]const u8, std.c.mode_t) c_int;
extern fn mknod([*:0]const u8, std.c.mode_t, std.c.dev_t) c_int;
extern fn fnmatch([*:0]const u8, [*:0]const u8, c_int) c_int;
extern fn isatty(c_int) c_int;
extern fn time(?*std.c.time_t) std.c.time_t;

extern fn BuiltinPluginsRepoConfig(?*Tdnf, ?*const CnfNode) u32;
extern fn BuiltinPluginsRepoMDDownloadStart(?*Tdnf, ?[*:0]const u8, ?[*:0]const u8) u32;
extern fn BuiltinPluginsRepoMDDownloadEnd(?*Tdnf, ?[*:0]const u8, ?[*:0]const u8) u32;
extern fn TDNFRepoMdCreateRepoCacheName(?[*:0]const u8, ?[*:0]const u8, *?[*:0]u8) u32;
extern fn TDNFRepoMdCalculateCookieForFile(?[*:0]const u8, ?[*]u8) u32;
extern fn TDNFRepoMdParseFile(?[*:0]const u8, *?*RepoMdDoc) u32;
extern fn TDNFRepoMdParseBuffer(?[*]const u8, usize, *?*RepoMdDoc) u32;
extern fn TDNFRepoMdLastError() [*:0]const u8;
extern fn TDNFRepoMdFree(?*RepoMdDoc) void;
extern fn TDNFRepoMdGetRecordCount(?*const RepoMdDoc) u32;
extern fn TDNFRepoMdGetRecord(?*const RepoMdDoc, u32) ?*const RepoMdRecord;
extern fn TDNFGetCachePath(?*Tdnf, ?*RepoData, ?[*:0]const u8, ?[*:0]const u8, *?[*:0]u8) u32;
extern fn TDNFRepoRemoveCache(?*Tdnf, ?*RepoData) u32;
extern fn TDNFRemoveSolvCache(?*Tdnf, ?*RepoData) u32;
extern fn TDNFRemoveLastRefreshMarker(?*Tdnf, ?*RepoData) u32;
extern fn TDNFRemoveRpmCache(?*Tdnf, ?*RepoData) u32;
extern fn TDNFRemoveTmpRepodata(?[*:0]const u8) u32;
extern fn TDNFUtilsMakeDir(?[*:0]const u8) u32;
extern fn TDNFUtilsMakeDirs(?[*:0]const u8) u32;
extern fn TDNFGetErrorString(u32, *?[*:0]u8) u32;

fn isNullOrEmpty(value: ?[*:0]const u8) bool {
    return value == null or value.?[0] == 0;
}

fn systemError() u32 {
    return systemErrorFrom(std.c._errno().*);
}

fn systemErrorFrom(errno_value: c_int) u32 {
    return errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(errno_value));
}

fn injectScanFailure(stage: ScanFailureStage) bool {
    if (!builtin.is_test) return false;
    if (injected_scan_failure) |*failure| {
        if (!failure.triggered and failure.stage == stage) {
            failure.triggered = true;
            std.c._errno().* = failure.errno_value;
            return true;
        }
    }
    return false;
}

fn syncFd(fd: c_int, stage: SyncFailureStage) u32 {
    if (builtin.is_test) {
        sync_stage_counts[@intFromEnum(stage)] += 1;
        if (injected_sync_failure) |*failure| {
            if (!failure.triggered and failure.stage == stage) {
                failure.triggered = true;
                return systemErrorFrom(failure.errno_value);
            }
        }
    }
    if (std.c.fsync(fd) != 0) return systemError();
    return 0;
}

fn injectResetFailure(stage: ResetFailureStage) bool {
    if (!builtin.is_test) return false;
    if (injected_reset_failure) |*failure| {
        if (!failure.triggered and failure.stage == stage) {
            failure.triggered = true;
            std.c._errno().* = failure.errno_value;
            return true;
        }
    }
    return false;
}

fn resetDownloadFd(fd: c_int) u32 {
    if (injectResetFailure(.truncate)) return systemError();
    if (std.c.ftruncate(fd, 0) != 0) return systemError();
    if (injectResetFailure(.seek)) return systemError();
    if (std.c.lseek(fd, 0, 0) < 0) return systemError();
    return 0;
}

fn injectPartialDownloadFailure(url: []const u8, fd: c_int) ?u32 {
    if (!builtin.is_test) return null;
    if (injected_partial_download_failure) |*failure| {
        if (failure.remaining == 0 or !std.mem.eql(u8, failure.url, url))
            return null;
        const written = std.c.write(fd, failure.bytes.ptr, failure.bytes.len);
        if (written < 0) return systemError();
        if (written != failure.bytes.len)
            return systemErrorFrom(@intFromEnum(std.c.E.IO));
        failure.remaining -= 1;
        failure.triggered += 1;
        return errors.ERROR_TDNF_REPO_PERFORM;
    }
    return null;
}

fn downloadToFd(
    io: std.Io,
    request: DownloadToFdRequest,
    destination_fd: c_int,
) !u16 {
    if (builtin.is_test) {
        if (injected_download_error_failure) |*failure| {
            if (failure.remaining > 0 and std.mem.eql(u8, failure.url, request.url)) {
                failure.remaining -= 1;
                failure.triggered += 1;
                return failure.err;
            }
        }
    }
    return client_download.client_download_to_fd(
        std.heap.c_allocator,
        io,
        request,
        destination_fd,
    );
}

fn freeString(slot: *?[*:0]u8) void {
    if (slot.*) |value| TDNFFreeMemory(@ptrCast(value));
    slot.* = null;
}

fn replaceString(slot: *?[*:0]u8, value: ?[*:0]const u8) u32 {
    freeString(slot);
    if (value == null) return 0;
    return TDNFAllocateString(value, slot);
}

fn allocateOptionalString(value: ?[*:0]const u8, output: *?[*:0]u8) u32 {
    output.* = null;
    if (value == null) return 0;
    return TDNFAllocateString(value, output);
}

fn joinPath(output: *?[*:0]u8, parts: []const ?[*:0]const u8) u32 {
    var nodes: [4]?[*:0]u8 = .{ null, null, null, null };
    var count: usize = 0;
    for (parts) |part| {
        nodes[count] = @ptrCast(@constCast(part orelse break));
        count += 1;
    }
    return TDNFJoinPathFromArray(output, &nodes, @intCast(count));
}

fn allocateRepo(handle: *Tdnf, id: [*:0]const u8, output: *?*RepoData) u32 {
    output.* = null;
    const args = handle.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    _ = args;
    const conf = handle.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var raw: ?*anyopaque = null;
    var result = TDNFAllocateMemory(1, @sizeOf(RepoData), &raw);
    if (result != 0) return result;
    const repo: *RepoData = @ptrCast(@alignCast(raw.?));
    repo.* = .{};
    defer if (output.* == null) freeReposInternal(repo);

    result = TDNFAllocateString(id, &repo.pszId);
    if (result != 0) return result;
    repo.nEnabled = default_enabled;
    repo.nHasMetaData = 1;
    repo.nSkipIfUnavailable = default_skip;
    repo.nGPGCheck = conf.nGPGCheck;
    repo.nSSLVerify = conf.nSSLVerify;
    repo.lMetadataExpire = default_metadata_expire;
    repo.nPriority = default_priority;
    repo.nTimeout = default_timeout;
    repo.nMinrate = default_minrate;
    repo.nThrottle = default_throttle;
    repo.nRetries = default_retries;
    repo.nSkipMDFileLists = default_skip_filelists;
    repo.nSkipMDUpdateInfo = default_skip_updateinfo;
    repo.nSkipMDOther = default_skip_other;
    output.* = repo;
    return 0;
}

fn configureRepo(handle: *Tdnf, repo: *RepoData, top: *CnfNode) u32 {
    _ = handle;
    var node = top.first_child;
    while (node) |current| : (node = current.next) {
        const name_z = current.name orelse continue;
        const value = current.value orelse continue;
        const name = std.mem.span(name_z);
        if (name.len == 0 or name[0] == '.') continue;

        if (std.mem.eql(u8, name, "enabled")) repo.nEnabled = isTrue(value) else if (std.mem.eql(u8, name, "name")) {
            const result = replaceString(&repo.pszName, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "baseurl")) {
            const result = TDNFAddStringArray(&repo.ppszBaseUrls, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "metalink")) {
            const result = replaceString(&repo.pszMetaLink, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "mirrorlist")) {
            const result = replaceString(&repo.pszMirrorList, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "snapshot")) {
            const result = replaceString(&repo.pszSnapshotUrl, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "skip_if_unavailable")) repo.nSkipIfUnavailable = isTrue(value) else if (std.mem.eql(u8, name, "gpgcheck")) repo.nGPGCheck = isTrue(value) else if (std.mem.eql(u8, name, "gpgkey")) {
            const result = TDNFAddStringArray(&repo.ppszUrlGPGKeys, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "username")) {
            const result = replaceString(&repo.pszUser, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "password")) {
            const result = replaceString(&repo.pszPass, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "priority")) repo.nPriority = strtoi(value) else if (std.mem.eql(u8, name, "timeout")) repo.nTimeout = strtoi(value) else if (std.mem.eql(u8, name, "retries")) repo.nRetries = strtoi(value) else if (std.mem.eql(u8, name, "minrate")) repo.nMinrate = strtoi(value) else if (std.mem.eql(u8, name, "throttle")) repo.nThrottle = strtoi(value) else if (std.mem.eql(u8, name, "sslverify")) repo.nSSLVerify = isTrue(value) else if (std.mem.eql(u8, name, "sslcacert")) {
            const result = replaceString(&repo.pszSSLCaCert, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "sslclientcert")) {
            const result = replaceString(&repo.pszSSLClientCert, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "sslclientkey")) {
            const result = replaceString(&repo.pszSSLClientKey, value);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "metadata_expire")) {
            const result = TDNFParseMetadataExpire(value, &repo.lMetadataExpire);
            if (result != 0) return result;
        } else if (std.mem.eql(u8, name, "skip_md_filelists")) repo.nSkipMDFileLists = isTrue(value) else if (std.mem.eql(u8, name, "skip_md_updateinfo")) repo.nSkipMDUpdateInfo = isTrue(value) else if (std.mem.eql(u8, name, "skip_md_other")) repo.nSkipMDOther = isTrue(value);
    }
    return 0;
}

fn createCmdlineRepo(handle: *Tdnf, output: *?*RepoData) u32 {
    var repo: ?*RepoData = null;
    var result = allocateRepo(handle, cmdline_repo_name, &repo);
    if (result != 0) return result;
    defer if (output.* == null) freeReposInternal(repo);
    repo.?.nHasMetaData = 0;
    if (handle.pConf.?.nCliGPGCheck == 0) repo.?.nGPGCheck = 0;
    result = TDNFAllocateString(cmdline_repo_name, &repo.?.pszName);
    if (result != 0) return result;
    output.* = repo;
    return 0;
}

fn validSpecialRepoId(id: [*:0]const u8) bool {
    const value = std.mem.span(id);
    return !std.mem.eql(u8, value, system_repo_name) and
        !std.mem.eql(u8, value, cmdline_repo_name);
}

fn createRepoFromPath(handle: *Tdnf, id: [*:0]const u8, path: [*:0]const u8, output: *?*RepoData) u32 {
    output.* = null;
    if (!validSpecialRepoId(id)) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var repo: ?*RepoData = null;
    var result = allocateRepo(handle, id, &repo);
    if (result != 0) return result;
    defer if (output.* == null) freeReposInternal(repo);
    repo.?.nEnabled = 1;
    result = TDNFAllocateString(id, &repo.?.pszName);
    if (result != 0) return result;
    var raw: ?*anyopaque = null;
    result = TDNFAllocateMemory(2, @sizeOf(?[*:0]u8), &raw);
    if (result != 0) return result;
    repo.?.ppszBaseUrls = @ptrCast(@alignCast(raw.?));

    if (path[0] == '/') {
        var is_dir: c_int = 0;
        result = TDNFIsDir(path, &is_dir);
        if (result != 0) {
            common.log(LOG_ERR, "CreateRepoFromPath: Error while operating on '%s'\n", .{path});
            return result;
        }
        if (is_dir == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
        result = common.allocPrint(&repo.?.ppszBaseUrls.?[0], "file://%s", .{path});
    } else {
        var remote: c_int = 0;
        result = TDNFUriIsRemote(path, &remote);
        if (result != 0) return result;
        result = TDNFAllocateString(path, &repo.?.ppszBaseUrls.?[0]);
    }
    if (result != 0) return result;
    output.* = repo;
    return 0;
}

fn createRepoFromDirectory(handle: *Tdnf, id: [*:0]const u8, path: [*:0]const u8, output: *?*RepoData) u32 {
    output.* = null;
    if (!validSpecialRepoId(id)) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var is_dir: c_int = 0;
    var result = TDNFIsDir(path, &is_dir);
    if (result != 0) {
        common.log(LOG_ERR, "CreateRepoFromDir: Error while operating on '%s'\n", .{path});
        return result;
    }
    if (is_dir == 0) {
        common.log(LOG_ERR, "%s is not a directory\n", .{path});
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var repo: ?*RepoData = null;
    result = allocateRepo(handle, id, &repo);
    if (result != 0) return result;
    defer if (output.* == null) freeReposInternal(repo);
    repo.?.nHasMetaData = 0;
    repo.?.nEnabled = 1;
    result = TDNFAllocateString(id, &repo.?.pszName);
    if (result != 0) return result;
    var raw: ?*anyopaque = null;
    result = TDNFAllocateMemory(2, @sizeOf(?[*:0]u8), &raw);
    if (result != 0) return result;
    repo.?.ppszBaseUrls = @ptrCast(@alignCast(raw.?));
    result = TDNFAllocateString(path, &repo.?.ppszBaseUrls.?[0]);
    if (result != 0) return result;

    var ids_raw: ?*anyopaque = null;
    result = TDNFAllocateMemory(2, @sizeOf(?[*:0]u8), &ids_raw);
    if (result != 0) return result;
    var ids: ?[*]?[*:0]u8 = @ptrCast(@alignCast(ids_raw.?));
    defer if (ids != null) TDNFFreeStringArray(ids);
    result = TDNFAllocateString(id, &ids.?[0]);
    if (result != 0) return result;
    if (handle.ppszRepoFromDirIds) |_| {
        result = TDNFMergeStringArrays(&handle.ppszRepoFromDirIds, ids);
        if (result != 0) return result;
    } else {
        handle.ppszRepoFromDirIds = ids;
    }
    ids = null;
    output.* = repo;
    return 0;
}

fn openDirectoryPathNoFollow(path_z: [*:0]const u8, output: *c_int) u32 {
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
    if (current_fd < 0) return systemError();
    defer {
        if (current_fd >= 0) _ = std.c.close(current_fd);
    }

    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, ".")) continue;
        if (std.mem.eql(u8, component, "..") or component.len > std.fs.max_name_bytes)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        var buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
        @memcpy(buffer[0..component.len], component);
        buffer[component.len] = 0;
        const next_fd = std.c.openat(current_fd, @ptrCast(&buffer), .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (next_fd < 0) return systemError();
        _ = std.c.close(current_fd);
        current_fd = next_fd;
    }
    output.* = current_fd;
    current_fd = -1;
    return 0;
}

const PinnedPath = struct {
    parent_fd: c_int = -1,
    name: [std.fs.max_name_bytes + 1]u8 = undefined,

    fn deinit(self: *PinnedPath) void {
        if (self.parent_fd >= 0) _ = std.c.close(self.parent_fd);
        self.parent_fd = -1;
    }

    fn nameZ(self: *PinnedPath) [*:0]const u8 {
        return @ptrCast(&self.name);
    }
};

fn pinPath(path_z: [*:0]const u8, output: *PinnedPath) u32 {
    const path = std.mem.span(path_z);
    if (path.len == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') : (end -= 1) {}
    const trimmed = path[0..end];
    const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/');
    const name = if (slash) |index| trimmed[index + 1 ..] else trimmed;
    if (name.len == 0 or
        name.len > std.fs.max_name_bytes or
        std.mem.eql(u8, name, ".") or
        std.mem.eql(u8, name, ".."))
    {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    const parent = if (slash) |index|
        if (index == 0) "/" else trimmed[0..index]
    else
        ".";
    const parent_z = std.heap.c_allocator.dupeZ(u8, parent) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer std.heap.c_allocator.free(parent_z);
    var parent_fd: c_int = -1;
    const result = openDirectoryPathNoFollow(parent_z, &parent_fd);
    if (result != 0) return result;
    output.* = .{ .parent_fd = parent_fd };
    @memcpy(output.name[0..name.len], name);
    output.name[name.len] = 0;
    return 0;
}

fn statPinned(path_z: [*:0]const u8, output: *Stat) u32 {
    var pinned: PinnedPath = undefined;
    const result = pinPath(path_z, &pinned);
    if (result != 0) return result;
    defer pinned.deinit();
    if (std.c.statx(
        pinned.parent_fd,
        pinned.nameZ(),
        at_symlink_nofollow,
        .{ .TYPE = true, .SIZE = true, .CTIME = true },
        output,
    ) != 0) {
        return systemError();
    }
    if (output.mode & mode_type_mask != mode_regular)
        return systemErrorFrom(@intFromEnum(std.c.E.LOOP));
    return 0;
}

fn regularPathExists(path_z: [*:0]const u8, exists: *bool) u32 {
    var stat_buf = std.mem.zeroes(Stat);
    const result = statPinned(path_z, &stat_buf);
    if (result == systemErrorFrom(@intFromEnum(std.c.E.NOENT))) {
        exists.* = false;
        return 0;
    }
    if (result != 0) return result;
    exists.* = true;
    return 0;
}

fn openRepoDirectory(path: [*:0]const u8, output: *c_int) u32 {
    if (injectScanFailure(.directory_open)) return systemError();
    return openDirectoryPathNoFollow(path, output);
}

fn duplicateRepoDirectory(fd: c_int) c_int {
    if (injectScanFailure(.duplicate)) return -1;
    return std.c.dup(fd);
}

fn repoFdopendir(fd: c_int) ?*DIR {
    if (injectScanFailure(.fdopendir)) return null;
    return fdopendir(fd);
}

fn closeRepoScanFd(fd: c_int) c_int {
    if (builtin.is_test) {
        if (injected_close_failure) |*failure| {
            if (!failure.triggered) {
                failure.triggered = true;
                _ = std.c.close(fd);
                std.c._errno().* = failure.errno_value;
                return -1;
            }
        }
    }
    return std.c.close(fd);
}

fn closeRepoScanFdPreservingError(fd: c_int, errno_value: c_int) u32 {
    _ = closeRepoScanFd(fd);
    std.c._errno().* = errno_value;
    return systemErrorFrom(errno_value);
}

fn readRepoEntry(dir: *DIR) ?*Dirent {
    if (injectScanFailure(.readdir)) return null;
    return readdir(dir);
}

fn statRepoEntry(
    directory_fd: c_int,
    name: [*:0]const u8,
    output: *Stat,
) c_int {
    if (injectScanFailure(.pre_stat)) return -1;
    return std.c.statx(
        directory_fd,
        name,
        at_symlink_nofollow,
        .{ .TYPE = true, .INO = true },
        output,
    );
}

fn openRepoEntry(directory_fd: c_int, name: [*:0]const u8) c_int {
    if (injectScanFailure(.entry_open)) return -1;
    return std.c.openat(directory_fd, name, .{
        .ACCMODE = .RDONLY,
        .NONBLOCK = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
}

fn statRegularFd(fd: c_int, output: *Stat) u32 {
    if (injectScanFailure(.post_stat)) return systemError();
    var stat_buf = std.mem.zeroes(Stat);
    if (std.c.statx(
        fd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        .{ .TYPE = true, .INO = true },
        &stat_buf,
    ) != 0) return systemError();
    output.* = stat_buf;
    return 0;
}

fn repoOpenError(errno_value: c_int) ?u32 {
    if (errno_value == @intFromEnum(std.c.E.NOENT) or
        errno_value == @intFromEnum(std.c.E.LOOP))
    {
        return null;
    }
    return systemErrorFrom(errno_value);
}

fn sameFile(left: Stat, right: Stat) bool {
    return left.ino == right.ino and
        left.dev_major == right.dev_major and
        left.dev_minor == right.dev_minor;
}

fn loadReposFromFile(handle: *Tdnf, path: [*:0]const u8, output: *?*RepoData) u32 {
    output.* = null;
    const module = find_cnfmodule("ini") orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const config = cnfmodule_parse_file(module, path) orelse {
        if (std.c._errno().* != 0) return systemError();
        return errors.ERROR_TDNF_CONF_FILE_LOAD;
    };
    defer destroy_cnftree(config);

    var repos: ?*RepoData = null;
    defer if (output.* == null) freeReposInternal(repos);
    var section = config.first_child;
    while (section) |current| : (section = current.next) {
        const id = current.name orelse continue;
        if (id[0] == '.') continue;
        if (!validSpecialRepoId(id)) return errors.ERROR_TDNF_INVALID_PARAMETER;
        var repo: ?*RepoData = null;
        var result = allocateRepo(handle, id, &repo);
        if (result != 0) return result;
        defer if (repo != null) freeReposInternal(repo);
        result = configureRepo(handle, repo.?, current);
        if (result != 0) return result;
        result = BuiltinPluginsRepoConfig(handle, current);
        if (result != 0) return result;
        if (repo.?.pszName == null) {
            result = TDNFAllocateString(repo.?.pszId, &repo.?.pszName);
            if (result != 0) return result;
        }
        if (handle.pArgs.?.nNoGPGCheck != 0) repo.?.nGPGCheck = 0;
        repo.?.pNext = repos;
        repos = repo;
        repo = null;
    }
    output.* = repos;
    return 0;
}

fn appendList(tail: *?*RepoData, list: ?*RepoData) *?*RepoData {
    tail.* = list;
    var cursor = tail;
    while (cursor.*) |repo| cursor = &repo.pNext;
    return cursor;
}

fn loadRepoDirectoryEntry(
    handle: *Tdnf,
    directory_fd: c_int,
    entry: *Dirent,
    output: *?*RepoData,
) u32 {
    output.* = null;
    const name_z: [*:0]const u8 = @ptrCast(&entry.name);
    var before = std.mem.zeroes(Stat);
    if (statRepoEntry(directory_fd, name_z, &before) != 0) {
        const errno_value = std.c._errno().*;
        if (repoOpenError(errno_value)) |entry_error| return entry_error;
        return 0;
    }
    if (before.mode & mode_type_mask != mode_regular) return 0;

    const repo_fd = openRepoEntry(directory_fd, name_z);
    if (repo_fd < 0) {
        const errno_value = std.c._errno().*;
        if (repoOpenError(errno_value)) |open_error| return open_error;
        return 0;
    }
    defer _ = std.c.close(repo_fd);

    var after = std.mem.zeroes(Stat);
    var result = statRegularFd(repo_fd, &after);
    if (result != 0) return result;
    if (after.mode & mode_type_mask != mode_regular or !sameFile(before, after))
        return 0;

    var path_buffer: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buffer, "/proc/self/fd/{d}", .{repo_fd}) catch
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    result = loadReposFromFile(handle, path, output);
    return result;
}

pub export fn TDNFLoadRepoData(handle_opt: ?*Tdnf, output_opt: ?*?*RepoData) u32 {
    const output = output_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    output.* = null;
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const conf = handle.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = handle.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_dir = conf.pszRepoDir orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const setopts = args.cn_setopts orelse return errors.ERROR_TDNF_INVALID_PARAMETER;

    var repos: ?*RepoData = null;
    defer if (output.* == null) freeReposInternal(repos);
    var result = createCmdlineRepo(handle, &repos);
    if (result != 0) return result;
    var tail: *?*RepoData = &repos.?.pNext;

    var option = setopts.first_child;
    while (option) |current| : (option = current.next) {
        const name = current.name orelse continue;
        const value = current.value orelse continue;
        const kind = std.mem.span(name);
        if (!std.mem.eql(u8, kind, "repofrompath") and
            !std.mem.eql(u8, kind, "repofromdir")) continue;
        var tuple: ?[*]?[*:0]u8 = null;
        result = TDNFSplitStringToArray(value, ",", &tuple);
        if (result != 0) return result;
        defer TDNFFreeStringArray(tuple);
        if (tuple == null or tuple.?[0] == null or tuple.?[1] == null)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        var repo: ?*RepoData = null;
        if (std.mem.eql(u8, kind, "repofrompath")) {
            result = createRepoFromPath(handle, tuple.?[0].?, tuple.?[1].?, &repo);
            if (result != 0) return result;
            tail = appendList(tail, repo);
        } else {
            result = createRepoFromDirectory(handle, tuple.?[0].?, tuple.?[1].?, &repo);
            if (result != 0) return result;
            repo.?.pNext = repos;
            repos = repo;
        }
    }

    var repo_dir_fd: c_int = -1;
    result = openRepoDirectory(repo_dir, &repo_dir_fd);
    if (result != 0) return result;
    defer _ = std.c.close(repo_dir_fd);
    const scan_fd = duplicateRepoDirectory(repo_dir_fd);
    if (scan_fd < 0) return systemError();
    const dir = repoFdopendir(scan_fd) orelse {
        const errno_value = std.c._errno().*;
        return closeRepoScanFdPreservingError(scan_fd, errno_value);
    };
    defer _ = closedir(dir);
    while (true) {
        std.c._errno().* = 0;
        const entry = readRepoEntry(dir) orelse {
            if (std.c._errno().* != 0) return systemError();
            break;
        };
        const name = std.mem.sliceTo(&entry.name, 0);
        if (name.len <= repo_extension.len or
            !std.mem.endsWith(u8, name, repo_extension)) continue;
        var loaded: ?*RepoData = null;
        result = loadRepoDirectoryEntry(handle, repo_dir_fd, entry, &loaded);
        if (result != 0) return result;
        tail = appendList(tail, loaded);
    }

    var first = repos;
    while (first) |left| : (first = left.pNext) {
        var second = left.pNext;
        while (second) |right| : (second = right.pNext) {
            if (left.pszId != null and right.pszId != null and
                std.mem.eql(u8, std.mem.span(left.pszId.?), std.mem.span(right.pszId.?)))
            {
                common.log(LOG_ERR, "ERROR: duplicate repo id: %s\n", .{left.pszId.?});
                return errors.ERROR_TDNF_DUPLICATE_REPO_ID;
            }
        }
    }

    if (args.cn_repoopts) |repo_options| {
        var repo = repos;
        while (repo) |current| : (repo = current.pNext) {
            const id = current.pszId orelse continue;
            if (find_node(repo_options.first_child, id)) |tree| {
                result = configureRepo(handle, current, tree);
                if (result != 0) return result;
            }
        }
    }
    output.* = repos;
    return 0;
}

fn alterRepoState(repos_opt: ?*RepoData, enabled: c_int, id: [*:0]const u8) u32 {
    var repos = repos_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (id[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const glob = TDNFIsGlob(id) != 0;
    while (true) {
        const repo_id = repos.pszId;
        const matched = if (repo_id == null) false else if (glob) fnmatch(id, repo_id.?, 0) == 0 else std.mem.eql(u8, std.mem.span(id), std.mem.span(repo_id.?));
        if (matched) {
            repos.nEnabled = enabled;
            if (!glob) break;
        }
        repos = repos.pNext orelse break;
    }
    return 0;
}

fn replaceRepoVars(handle: *Tdnf, repo: *RepoData) u32 {
    const scalar_fields = [_]*?[*:0]u8{
        &repo.pszName,
        &repo.pszMetaLink,
        &repo.pszMirrorList,
        &repo.pszSnapshotUrl,
        &repo.pszUser,
        &repo.pszPass,
        &repo.pszSSLCaCert,
        &repo.pszSSLClientCert,
        &repo.pszSSLClientKey,
    };
    for (scalar_fields) |slot| if (slot.* != null) {
        const result = TDNFConfigReplaceVars(handle, slot);
        if (result != 0) return result;
    };
    for ([_]?[*]?[*:0]u8{ repo.ppszBaseUrls, repo.ppszUrlGPGKeys }) |values| {
        if (values) |list| {
            var index: usize = 0;
            while (list[index] != null) : (index += 1) {
                const result = TDNFConfigReplaceVars(handle, &list[index]);
                if (result != 0) return result;
            }
        }
    }
    return 0;
}

pub export fn TDNFRepoListFinalize(handle_opt: ?*Tdnf) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = handle.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repos = handle.pRepos orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const setopts = args.cn_setopts orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var repoid_seen = false;
    var node = setopts.first_child;
    while (node) |current| : (node = current.next) {
        const name_z = current.name orelse continue;
        const value = current.value orelse continue;
        const name = std.mem.span(name_z);
        var enabled: ?c_int = null;
        if (std.mem.eql(u8, name, "enablerepo")) enabled = 1 else if (std.mem.eql(u8, name, "disablerepo")) enabled = 0;
        if (enabled) |state| {
            var ids: ?[*]?[*:0]u8 = null;
            var result = TDNFSplitStringToArray(value, ",", &ids);
            if (result != 0) return result;
            defer TDNFFreeStringArray(ids);
            var index: usize = 0;
            while (ids.?[index]) |id| : (index += 1) {
                result = alterRepoState(repos, state, id);
                if (result != 0) return result;
            }
        } else if (std.mem.eql(u8, name, "repo") or std.mem.eql(u8, name, "repoid")) {
            if (!repoid_seen) {
                const result = alterRepoState(repos, 0, "*");
                if (result != 0) return result;
                repoid_seen = true;
            }
            var ids: ?[*]?[*:0]u8 = null;
            var result = TDNFSplitStringToArray(value, ",", &ids);
            if (result != 0) return result;
            defer TDNFFreeStringArray(ids);
            var index: usize = 0;
            while (ids.?[index]) |id| : (index += 1) {
                result = alterRepoState(repos, 1, id);
                if (result != 0) return result;
            }
        }
    }

    var repo: ?*RepoData = repos;
    while (repo) |current| : (repo = current.pNext) {
        var result = replaceRepoVars(handle, current);
        if (result != 0) return result;
        freeString(&current.pszCacheName);
        const url = current.pszMetaLink orelse
            current.pszMirrorList orelse
            if (current.ppszBaseUrls) |urls| urls[0] else null;
        if (url) |cache_url| {
            result = TDNFRepoMdCreateRepoCacheName(current.pszId, cache_url, &current.pszCacheName);
            if (result != 0) return result;
        }
    }
    return 0;
}

pub export fn TDNFCloneRepo(input_opt: ?*RepoData, output_opt: ?*?*RepoData) u32 {
    const output = output_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    output.* = null;
    const input = input_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var raw: ?*anyopaque = null;
    var result = TDNFAllocateMemory(1, @sizeOf(RepoData), &raw);
    if (result != 0) return result;
    const repo: *RepoData = @ptrCast(@alignCast(raw.?));
    repo.* = .{ .nEnabled = input.nEnabled };
    defer if (output.* == null) TDNFFreeRepos(repo);
    result = allocateOptionalString(input.pszId, &repo.pszId);
    if (result != 0) return result;
    result = allocateOptionalString(input.pszName, &repo.pszName);
    if (result != 0) return result;
    if (input.ppszBaseUrls != null and input.ppszBaseUrls.?[0] != null) {
        result = TDNFAllocateStringArray(input.ppszBaseUrls, &repo.ppszBaseUrls);
        if (result != 0) return result;
    }
    result = allocateOptionalString(input.pszMetaLink, &repo.pszMetaLink);
    if (result != 0) return result;
    output.* = repo;
    return 0;
}

extern fn TDNFFreeRepos(?*RepoData) void;

fn freeReposInternal(repos_opt: ?*RepoData) void {
    var repos = repos_opt;
    while (repos) |repo| {
        const next = repo.pNext;
        freeString(&repo.pszId);
        freeString(&repo.pszName);
        TDNFFreeStringArray(repo.ppszBaseUrls);
        freeString(&repo.pszMetaLink);
        freeString(&repo.pszMirrorList);
        freeString(&repo.pszSnapshotUrl);
        freeString(&repo.pszSnapshotFile);
        TDNFFreeStringArray(repo.ppszUrlGPGKeys);
        freeString(&repo.pszSSLCaCert);
        freeString(&repo.pszSSLClientCert);
        freeString(&repo.pszSSLClientKey);
        freeString(&repo.pszUser);
        freeString(&repo.pszPass);
        freeString(&repo.pszCacheName);
        TDNFFreeMemory(repo);
        repos = next;
    }
}

pub export fn TDNFFreeReposInternal(repos: ?*RepoData) void {
    freeReposInternal(repos);
}

pub export fn TDNFGetGPGKeys(
    handle: ?*Tdnf,
    repo_opt: ?*RepoData,
    output_opt: ?*?[*]?[*:0]u8,
) u32 {
    _ = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo = repo_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (output_opt) |output| {
        output.* = null;
        if (repo.ppszUrlGPGKeys == null or isNullOrEmpty(repo.ppszUrlGPGKeys.?[0]))
            return errors.ERROR_TDNF_NO_GPGKEY_CONF_ENTRY;
        return TDNFAllocateStringArray(repo.ppszUrlGPGKeys, output);
    }
    return 0;
}

fn freeRepoMetadata(metadata_opt: ?*RepoMetadata) void {
    const metadata = metadata_opt orelse return;
    freeString(&metadata.pszRepoCacheDir);
    freeString(&metadata.pszRepo);
    freeString(&metadata.pszRepoMD);
    freeString(&metadata.pszPrimary);
    freeString(&metadata.pszFileLists);
    freeString(&metadata.pszUpdateInfo);
    freeString(&metadata.pszOther);
    TDNFFreeMemory(metadata);
}

pub export fn TDNFFreeRepoMetadata(metadata: ?*RepoMetadata) void {
    freeRepoMetadata(metadata);
}

fn safeRelativePath(path_z: [*:0]const u8) bool {
    const path = std.mem.span(path_z);
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return false;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

fn findRepoMdPart(doc: *const RepoMdDoc, kind: [*:0]const u8, output: *?[*:0]u8) u32 {
    output.* = null;
    var index: u32 = 0;
    while (index < TDNFRepoMdGetRecordCount(doc)) : (index += 1) {
        const record = TDNFRepoMdGetRecord(doc, index) orelse continue;
        const location = record.pszLocationHref orelse continue;
        if (!safeRelativePath(location)) return errors.ERROR_TDNF_INVALID_REPO_FILE;
        const match = if (std.mem.eql(u8, std.mem.span(kind), repomd_updateinfo))
            record.dwKind == record_kind_updateinfo
        else if (record.pszType) |record_type|
            std.mem.eql(u8, std.mem.span(kind), std.mem.span(record_type))
        else
            false;
        if (match) return TDNFAllocateString(location, output);
    }
    return errors.ERROR_TDNF_NO_DATA;
}

fn parseRepoMdDoc(path: [*:0]const u8, output: *?*RepoMdDoc) u32 {
    output.* = null;
    var result = TDNFRepoMdParseFile(path, output);
    if (result == errors.ERROR_TDNF_INVALID_REPO_FILE) {
        common.log(LOG_CRIT, "Error(%u) parsing repomd: %s\n", .{ result, TDNFRepoMdLastError() });
        const empty = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><repomd xmlns=\"http://linux.duke.edu/metadata/repo\"></repomd>";
        result = TDNFRepoMdParseBuffer(empty.ptr, empty.len, output);
    }
    return result;
}

fn parseRepoMd(metadata: *RepoMetadata) u32 {
    const path = metadata.pszRepoMD orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var stat_buf = std.mem.zeroes(Stat);
    var result = statPinned(path, &stat_buf);
    if (result != 0) return result;
    var doc: ?*RepoMdDoc = null;
    result = parseRepoMdDoc(path, &doc);
    if (result != 0) return result;
    defer TDNFRepoMdFree(doc);
    result = findRepoMdPart(doc.?, repomd_primary, &metadata.pszPrimary);
    if (result != 0) return result;
    result = findRepoMdPart(doc.?, repomd_filelists, &metadata.pszFileLists);
    if (result != 0 and result != errors.ERROR_TDNF_NO_DATA) return result;
    result = findRepoMdPart(doc.?, repomd_updateinfo, &metadata.pszUpdateInfo);
    if (result != 0 and result != errors.ERROR_TDNF_NO_DATA) return result;
    result = findRepoMdPart(doc.?, repomd_other, &metadata.pszOther);
    if (result != 0 and result != errors.ERROR_TDNF_NO_DATA) return result;
    return 0;
}

fn downloadProgressCallback(
    user_data: ?*anyopaque,
    download_total: i64,
    download_now: i64,
    upload_total: i64,
    upload_now: i64,
) callconv(.c) c_int {
    _ = upload_total;
    _ = upload_now;
    if (download_total <= 0 or user_data == null) return 0;
    const data: *DownloadProgressData = @ptrCast(@alignCast(user_data.?));
    var percent: u32 = 100;
    if (download_now < download_total) {
        const current = time(null);
        if (data.previous_time != 0 and current - data.previous_time < 1) return 0;
        data.previous_time = current;
        percent = @intFromFloat(
            (@as(f64, @floatFromInt(download_now)) /
                @as(f64, @floatFromInt(download_total))) * 100.0,
        );
    } else {
        data.previous_time = 0;
    }
    if (isatty(2) == 0) {
        common.log(LOG_NOTICE, "%s %u%% %ld\n", .{ @as([*:0]const u8, @ptrCast(&data.text)), percent, @as(c_long, @intCast(download_now)) });
    } else {
        common.log(LOG_NOTICE, "%-35s %10ld %u%%\r", .{ @as([*:0]const u8, @ptrCast(&data.text)), @as(c_long, @intCast(download_now)), percent });
    }
    return 0;
}

fn prepareDownloadRequest(
    handle: *Tdnf,
    repo: *RepoData,
    url: [*:0]const u8,
    progress_text: ?[*:0]const u8,
    request: *DownloadToFdRequest,
    no_output: *bool,
) u32 {
    const args = handle.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const conf = handle.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const connect_timeout = std.math.cast(u32, conf.nConnectTimeout) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const timeout = std.math.cast(u32, repo.nTimeout) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const minrate = std.math.cast(u64, repo.nMinrate) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const throttle = std.math.cast(u64, repo.nThrottle) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    request.* = .{
        .url = std.mem.span(url),
        .user_agent = optionalSpan(conf.pszUserAgentHeader),
        .proxy_url = optionalSpan(conf.pszProxy),
        .proxy_userpwd = optionalSpan(conf.pszProxyUserPass),
        .username = optionalSpan(repo.pszUser),
        .password = optionalSpan(repo.pszPass),
        .ca_cert = optionalSpan(repo.pszSSLCaCert),
        .client_cert = optionalSpan(repo.pszSSLClientCert),
        .client_key = optionalSpan(repo.pszSSLClientKey),
        .ssl_verify = repo.nSSLVerify != 0,
        .connect_timeout_secs = connect_timeout,
        .total_timeout_secs = timeout,
        .low_speed_limit = minrate,
        .low_speed_time_secs = timeout,
        .max_recv_speed = throttle,
    };
    no_output.* = true;
    if (args.nQuiet == 0 and progress_text != null and
        (isatty(1) != 0 or args.nVerbose != 0))
    {
        download_progress_data = .{};
        const text = std.mem.span(progress_text.?);
        const length = @min(text.len, download_progress_data.text.len - 1);
        @memcpy(download_progress_data.text[0..length], text[0..length]);
        request.progress_fn = downloadProgressCallback;
        request.progress_data = &download_progress_data;
        no_output.* = false;
    }
    return 0;
}

fn optionalSpan(value: ?[*:0]const u8) ?[]const u8 {
    return if (value) |text| std.mem.span(text) else null;
}

fn mapDownloadError(err: anyerror) u32 {
    return switch (err) {
        error.UnsupportedConfiguration => errors.ERROR_TDNF_CALL_NOT_SUPPORTED,
        error.InvalidUrl, error.HttpsRequired => errors.ERROR_TDNF_URL_INVALID,
        error.TlsConfiguration => errors.ERROR_TDNF_SET_SSL_SETTINGS,
        error.Timeout, error.LowSpeedLimit => errors.ERROR_TDNF_TIMED_OUT,
        error.OperationAborted => errors.ERROR_TDNF_OPERATION_ABORTED,
        error.OutOfMemory => errors.ERROR_TDNF_OUT_OF_MEMORY,
        else => errors.ERROR_TDNF_REPO_PERFORM,
    };
}

fn downloadErrorIsFatal(result: u32, status: c_long) bool {
    if (status >= 400) return true;
    return switch (result) {
        errors.ERROR_TDNF_CALL_NOT_SUPPORTED,
        errors.ERROR_TDNF_INVALID_PARAMETER,
        errors.ERROR_TDNF_URL_INVALID,
        errors.ERROR_TDNF_SET_SSL_SETTINGS,
        errors.ERROR_TDNF_OPERATION_ABORTED,
        errors.ERROR_TDNF_OUT_OF_MEMORY,
        => true,
        else => false,
    };
}

fn downloadErrorIsLocal(err: anyerror) bool {
    return switch (err) {
        error.InvalidDestinationFd,
        error.LocalOutputFailed,
        => true,
        else => false,
    };
}

fn downloadUrlToFd(
    handle: *Tdnf,
    repo: *RepoData,
    url: [*:0]const u8,
    destination_fd: c_int,
    progress_text: ?[*:0]const u8,
    local_failure: ?*bool,
) u32 {
    if (local_failure) |failure| failure.* = false;
    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const safe_url = uri_sanitize.redactAlloc(arena_state.allocator(), std.mem.span(url)) catch
        "repository URL";
    var request: DownloadToFdRequest = undefined;
    var no_output = true;
    var result = prepareDownloadRequest(
        handle,
        repo,
        url,
        progress_text,
        &request,
        &no_output,
    );
    if (result != 0) return result;
    result = systemErrorFrom(@intFromEnum(std.c.E.NOENT));

    var attempt: c_int = 0;
    var io_state: std.Io.Threaded = .init(std.heap.c_allocator, .{});
    defer io_state.deinit();
    const io = io_state.io();
    while (attempt <= repo.nRetries) : (attempt += 1) {
        if (attempt > 0 and !(builtin.is_test and suppress_test_info_logs))
            common.log(LOG_INFO, "retrying %d/%d\n", .{ attempt, repo.nRetries });
        result = resetDownloadFd(destination_fd);
        if (result != 0) {
            if (local_failure) |failure| failure.* = true;
            return result;
        }
        if (injectPartialDownloadFailure(request.url, destination_fd)) |injected_result| {
            result = injected_result;
            if (attempt == repo.nRetries or downloadErrorIsFatal(result, 0))
                return result;
            continue;
        }
        const status_value = downloadToFd(io, request, destination_fd) catch |err| {
            result = mapDownloadError(err);
            if (downloadErrorIsLocal(err)) {
                if (local_failure) |failure| failure.* = true;
                return result;
            }
            if (attempt == repo.nRetries or downloadErrorIsFatal(result, 0)) {
                common.log(LOG_ERR, "Error: failed to download %.*s: error %u\n", .{ @as(c_int, @intCast(safe_url.len)), safe_url.ptr, result });
                return result;
            }
            continue;
        };
        const status: c_long = @intCast(status_value);
        if (status < 400) {
            result = 0;
            break;
        }
        result = errors.ERROR_TDNF_INVALID_PARAMETER;
        common.log(LOG_ERR, "Error: %ld when downloading %.*s. Please check repo url or refresh metadata with 'tdnf makecache'.\n", .{ status, @as(c_int, @intCast(safe_url.len)), safe_url.ptr });
        return result;
    }
    if (!no_output) common.log(LOG_INFO, "\n", .{});
    return result;
}

fn downloadFromRepoToFd(
    handle: *Tdnf,
    repo: *RepoData,
    location: [*:0]const u8,
    destination_fd: c_int,
    progress_text: ?[*:0]const u8,
) u32 {
    if (repo.ppszBaseUrls) |base_urls| {
        if (base_urls[0] != null and
            std.mem.indexOf(u8, std.mem.span(location), "://") == null)
        {
            var index: usize = 0;
            while (base_urls[index]) |base_url| : (index += 1) {
                var url: ?[*:0]u8 = null;
                defer freeString(&url);
                var result = joinPath(&url, &.{ base_url, location });
                if (result != 0) return result;
                var local_failure = false;
                result = downloadUrlToFd(
                    handle,
                    repo,
                    url.?,
                    destination_fd,
                    progress_text,
                    &local_failure,
                );
                if (result == 0) return 0;
                if (local_failure) return result;
                if (base_urls[index + 1] == null) return result;
                var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
                defer arena_state.deinit();
                const safe_url = uri_sanitize.redactAlloc(
                    arena_state.allocator(),
                    std.mem.span(url.?),
                ) catch "repository URL";
                common.log(LOG_ERR, "Warning: failed to download %.*s, trying next base URL\n", .{ @as(c_int, @intCast(safe_url.len)), safe_url.ptr });
            }
        }
    }
    return downloadUrlToFd(
        handle,
        repo,
        location,
        destination_fd,
        progress_text,
        null,
    );
}

fn randomTempName(buffer: *[96]u8) u32 {
    var random_bytes: [16]u8 = undefined;
    var offset: usize = 0;
    while (offset < random_bytes.len) {
        const count = std.c.getrandom(
            random_bytes[offset..].ptr,
            random_bytes.len - offset,
            0,
        );
        if (count < 0) {
            if (std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
            return systemError();
        }
        if (count == 0) return systemErrorFrom(@intFromEnum(std.c.E.IO));
        offset += @intCast(count);
    }
    const encoded = std.fmt.bytesToHex(random_bytes, .lower);
    _ = std.fmt.bufPrintZ(
        buffer,
        ".tdnf-repository-{s}.tmp",
        .{&encoded},
    ) catch return errors.ERROR_TDNF_INVALID_PARAMETER;
    return 0;
}

fn secureDownload(
    handle: *Tdnf,
    repo: *RepoData,
    source: [*:0]const u8,
    destination: [*:0]const u8,
    progress_text: ?[*:0]const u8,
    from_repo: bool,
) u32 {
    var pinned: PinnedPath = undefined;
    var result = pinPath(destination, &pinned);
    if (result != 0) return result;
    defer pinned.deinit();

    var destination_stat = std.mem.zeroes(Stat);
    if (std.c.statx(
        pinned.parent_fd,
        pinned.nameZ(),
        at_symlink_nofollow,
        .{ .TYPE = true },
        &destination_stat,
    ) == 0) {
        if (destination_stat.mode & mode_type_mask != mode_regular)
            return systemErrorFrom(@intFromEnum(std.c.E.LOOP));
    } else if (std.c._errno().* != @intFromEnum(std.c.E.NOENT)) {
        return systemError();
    }

    var temp_name: [96]u8 = undefined;
    var temp_fd: c_int = -1;
    var attempt: usize = 0;
    while (attempt < download_temp_attempts) : (attempt += 1) {
        result = randomTempName(&temp_name);
        if (result != 0) return result;
        const temp_name_z: [*:0]const u8 = @ptrCast(&temp_name);
        temp_fd = std.c.openat(pinned.parent_fd, temp_name_z, .{
            .ACCMODE = .WRONLY,
            .CREAT = true,
            .EXCL = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        }, @as(c_uint, 0o600));
        if (temp_fd >= 0) break;
        if (std.c._errno().* != @intFromEnum(std.c.E.EXIST))
            return systemError();
    }
    if (temp_fd < 0) return systemErrorFrom(@intFromEnum(std.c.E.EXIST));
    const temp_name_z: [*:0]const u8 = @ptrCast(&temp_name);
    defer {
        _ = std.c.close(temp_fd);
        _ = std.c.unlinkat(pinned.parent_fd, temp_name_z, 0);
    }

    result = if (from_repo)
        downloadFromRepoToFd(handle, repo, source, temp_fd, progress_text)
    else
        downloadUrlToFd(handle, repo, source, temp_fd, progress_text, null);
    if (result != 0) return result;
    if (std.c.fchmod(temp_fd, 0o644) != 0) return systemError();
    result = syncFd(temp_fd, .file);
    if (result != 0) return result;

    destination_stat = std.mem.zeroes(Stat);
    if (std.c.statx(
        pinned.parent_fd,
        pinned.nameZ(),
        at_symlink_nofollow,
        .{ .TYPE = true },
        &destination_stat,
    ) == 0) {
        if (destination_stat.mode & mode_type_mask != mode_regular)
            return systemErrorFrom(@intFromEnum(std.c.E.LOOP));
    } else if (std.c._errno().* != @intFromEnum(std.c.E.NOENT)) {
        return systemError();
    }
    if (std.c.renameat(
        pinned.parent_fd,
        temp_name_z,
        pinned.parent_fd,
        pinned.nameZ(),
    ) != 0) return systemError();
    // The rename is committed; durability failure is reported without rollback.
    return syncFd(pinned.parent_fd, .destination_directory);
}

fn downloadRepoMdPart(
    handle: *Tdnf,
    repo: *RepoData,
    location: [*:0]const u8,
    destination: [*:0]const u8,
    name: [*:0]const u8,
) u32 {
    if (!safeRelativePath(location)) return errors.ERROR_TDNF_INVALID_REPO_FILE;
    var exists = false;
    var result = regularPathExists(destination, &exists);
    if (result != 0) return result;
    if (exists) return 0;
    var info: ?[*:0]u8 = null;
    defer freeString(&info);
    result = common.allocPrint(&info, "%s (%s)", .{ repo.pszId, name });
    if (result != 0) return result;
    result = secureDownload(handle, repo, location, destination, info, true);
    return result;
}

fn ensureRepoMdParts(handle: *Tdnf, repo: *RepoData, relative: *RepoMetadata, output: *?*RepoMetadata) u32 {
    output.* = null;
    var raw: ?*anyopaque = null;
    var result = TDNFAllocateMemory(1, @sizeOf(RepoMetadata), &raw);
    if (result != 0) return result;
    const metadata: *RepoMetadata = @ptrCast(@alignCast(raw.?));
    metadata.* = .{};
    defer if (output.* == null) freeRepoMetadata(metadata);
    metadata.pszRepoMD = relative.pszRepoMD;
    relative.pszRepoMD = null;

    const fields = [_]struct {
        source: *?[*:0]u8,
        destination: *?[*:0]u8,
        skip: bool,
        name: [*:0]const u8,
    }{
        .{ .source = &relative.pszPrimary, .destination = &metadata.pszPrimary, .skip = false, .name = "primary" },
        .{ .source = &relative.pszFileLists, .destination = &metadata.pszFileLists, .skip = repo.nSkipMDFileLists != 0, .name = "file lists" },
        .{ .source = &relative.pszUpdateInfo, .destination = &metadata.pszUpdateInfo, .skip = repo.nSkipMDUpdateInfo != 0, .name = "update info" },
        .{ .source = &relative.pszOther, .destination = &metadata.pszOther, .skip = repo.nSkipMDOther != 0, .name = "other" },
    };
    for (fields) |field| {
        const source = field.source.* orelse continue;
        if (field.skip) continue;
        if (!safeRelativePath(source)) return errors.ERROR_TDNF_INVALID_REPO_FILE;
        result = TDNFAppendPath(relative.pszRepoCacheDir, source, field.destination);
        if (result != 0) return result;
        result = downloadRepoMdPart(handle, repo, source, field.destination.*.?, field.name);
        if (result != 0) return result;
    }
    output.* = metadata;
    return 0;
}

fn replaceFile(source: [*:0]const u8, destination: [*:0]const u8) u32 {
    if (source[0] == 0 or destination[0] == 0)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var source_path: PinnedPath = undefined;
    var result = pinPath(source, &source_path);
    if (result != 0) return result;
    defer source_path.deinit();
    var destination_path: PinnedPath = undefined;
    result = pinPath(destination, &destination_path);
    if (result != 0) return result;
    defer destination_path.deinit();
    var source_stat = std.mem.zeroes(Stat);
    if (std.c.statx(
        source_path.parent_fd,
        source_path.nameZ(),
        at_symlink_nofollow,
        .{ .TYPE = true },
        &source_stat,
    ) != 0) return systemError();
    if (source_stat.mode & mode_type_mask != mode_regular)
        return systemErrorFrom(@intFromEnum(std.c.E.LOOP));
    var destination_stat = std.mem.zeroes(Stat);
    if (std.c.statx(
        destination_path.parent_fd,
        destination_path.nameZ(),
        at_symlink_nofollow,
        .{ .TYPE = true },
        &destination_stat,
    ) == 0) {
        if (destination_stat.mode & mode_type_mask != mode_regular)
            return systemErrorFrom(@intFromEnum(std.c.E.LOOP));
    } else if (std.c._errno().* != @intFromEnum(std.c.E.NOENT)) {
        return systemError();
    }
    if (std.c.renameat(
        source_path.parent_fd,
        source_path.nameZ(),
        destination_path.parent_fd,
        destination_path.nameZ(),
    ) != 0) return systemError();
    // The rename is committed; sync both parents and report without rollback.
    const source_sync = syncFd(source_path.parent_fd, .source_directory);
    const destination_sync = syncFd(
        destination_path.parent_fd,
        .destination_directory,
    );
    if (source_sync != 0) return source_sync;
    return destination_sync;
}

fn filterMirrorComments(values_opt: ?[*]?[*:0]u8) void {
    const values = values_opt orelse return;
    var read_index: usize = 0;
    var write_index: usize = 0;
    while (values[read_index]) |value| : (read_index += 1) {
        if (value[0] == '#') {
            TDNFFreeMemory(@ptrCast(value));
            continue;
        }
        values[write_index] = value;
        write_index += 1;
    }
    values[write_index] = null;
}

fn statChanged(path: [*:0]const u8, expire: c_long, needs_download: *bool) u32 {
    var stat_buf = std.mem.zeroes(Stat);
    const result = statPinned(path, &stat_buf);
    if (result != 0) {
        if (result == systemErrorFrom(@intFromEnum(std.c.E.NOENT))) {
            needs_download.* = true;
            return 0;
        }
        return result;
    }
    const now = time(null);
    needs_download.* = now - stat_buf.ctime.sec > expire;
    return 0;
}

fn validateLocalSnapshot(path: [*:0]const u8) u32 {
    var stat_buf = std.mem.zeroes(Stat);
    return statPinned(path, &stat_buf);
}

fn touchPinnedFile(path: [*:0]const u8) u32 {
    var pinned: PinnedPath = undefined;
    const result = pinPath(path, &pinned);
    if (result != 0) return result;
    defer pinned.deinit();
    const fd = std.c.openat(pinned.parent_fd, pinned.nameZ(), .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    }, @as(c_uint, 0o644));
    if (fd < 0) return systemError();
    defer _ = std.c.close(fd);
    if (std.c.futimens(fd, null) != 0) return systemError();
    var sync_result = syncFd(fd, .file);
    if (sync_result != 0) return sync_result;
    sync_result = syncFd(pinned.parent_fd, .destination_directory);
    return sync_result;
}

fn resolveSnapshot(handle: *Tdnf, repo: *RepoData) u32 {
    const snapshot = repo.pszSnapshotUrl orelse return 0;
    freeString(&repo.pszSnapshotFile);
    if (snapshot[0] == '/') {
        const result = validateLocalSnapshot(snapshot);
        if (result != 0) return result;
        return TDNFAllocateString(snapshot, &repo.pszSnapshotFile);
    }
    var remote: c_int = 0;
    const uri_result = TDNFUriIsRemote(snapshot, &remote);
    if (uri_result != 0) {
        if (!safeRelativePath(snapshot)) return errors.ERROR_TDNF_INVALID_PARAMETER;
        var result = joinPath(&repo.pszSnapshotFile, &.{ handle.pConf.?.pszRepoDir, snapshot });
        if (result != 0) return result;
        result = validateLocalSnapshot(repo.pszSnapshotFile.?);
        if (result != 0) freeString(&repo.pszSnapshotFile);
        return result;
    }
    if (remote != 0) {
        var cache_file: ?[*:0]u8 = null;
        defer freeString(&cache_file);
        var result = TDNFRepoMdCreateRepoCacheName(metadata_snapshot, snapshot, &cache_file);
        if (result != 0) return result;
        result = TDNFGetCachePath(handle, repo, cache_file, null, &repo.pszSnapshotFile);
        if (result != 0) return result;
        var need_download = false;
        result = statChanged(repo.pszSnapshotFile.?, repo.lMetadataExpire, &need_download);
        if (result != 0) return result;
        if (need_download)
            return secureDownload(
                handle,
                repo,
                snapshot,
                repo.pszSnapshotFile.?,
                repo.pszId,
                false,
            );
        return 0;
    }
    const value = std.mem.span(snapshot);
    if (std.mem.startsWith(u8, value, "file://")) {
        const local: [*:0]const u8 = snapshot + 7;
        const result = validateLocalSnapshot(local);
        if (result != 0) return result;
        return TDNFAllocateString(local, &repo.pszSnapshotFile);
    }
    return errors.ERROR_TDNF_URL_INVALID;
}

fn getRepoMD(
    handle_opt: ?*Tdnf,
    repo_opt: ?*RepoData,
    repo_data_dir_opt: ?[*:0]const u8,
    output_opt: ?*?*RepoMetadata,
) u32 {
    const output = output_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    output.* = null;
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo = repo_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_data_dir = repo_data_dir_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (repo_data_dir[0] == 0 or handle.pArgs == null or handle.pConf == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var result = BuiltinPluginsRepoMDDownloadStart(handle, repo.pszId, repo_data_dir);
    if (result != 0) return result;

    var mirror_file: ?[*:0]u8 = null;
    defer freeString(&mirror_file);
    if (repo.pszMirrorList) |mirror_url| {
        result = TDNFGetCachePath(handle, repo, metadata_mirrorlist, null, &mirror_file);
        if (result != 0) return result;
        var need_download = false;
        result = statChanged(mirror_file.?, repo.lMetadataExpire, &need_download);
        if (result != 0) return result;
        if (need_download) {
            result = secureDownload(
                handle,
                repo,
                mirror_url,
                mirror_file.?,
                repo.pszId,
                false,
            );
            if (result != 0) return result;
        }
        TDNFFreeStringArray(repo.ppszBaseUrls);
        repo.ppszBaseUrls = null;
        result = TDNFReadFileToStringArray(mirror_file, &repo.ppszBaseUrls);
        if (result != 0) return result;
        filterMirrorComments(repo.ppszBaseUrls);
    }
    if (repo.ppszBaseUrls == null or isNullOrEmpty(repo.ppszBaseUrls.?[0])) {
        common.log(LOG_ERR, "Error: Cannot find a valid base URL for repo: %s\n", .{repo.pszName});
        return errors.ERROR_TDNF_BASEURL_DOES_NOT_EXISTS;
    }

    var repomd_path: ?[*:0]u8 = null;
    defer freeString(&repomd_path);
    result = joinPath(&repomd_path, &.{ repo_data_dir, repomd_file_name });
    if (result != 0) return result;
    var raw: ?*anyopaque = null;
    result = TDNFAllocateMemory(1, @sizeOf(RepoMetadata), &raw);
    if (result != 0) return result;
    const relative: *RepoMetadata = @ptrCast(@alignCast(raw.?));
    relative.* = .{};
    defer freeRepoMetadata(relative);
    result = TDNFGetCachePath(handle, repo, null, null, &relative.pszRepoCacheDir);
    if (result != 0) return result;
    result = TDNFAllocateString(repomd_path, &relative.pszRepoMD);
    if (result != 0) return result;
    result = TDNFAllocateString(repo.pszId, &relative.pszRepo);
    if (result != 0) return result;

    var repomd_exists = false;
    result = regularPathExists(repomd_path.?, &repomd_exists);
    if (result != 0) return result;
    var need_download = !repomd_exists;
    var old_cookie = [_]u8{0} ** cookie_len;
    if (handle.pArgs.?.nRefresh != 0) {
        if (repomd_exists) {
            result = TDNFRepoMdCalculateCookieForFile(repomd_path, &old_cookie);
            if (result != 0) return result;
        }
        need_download = true;
    }

    var temp_dir: ?[*:0]u8 = null;
    defer {
        if (temp_dir != null) _ = TDNFRemoveTmpRepodata(temp_dir);
        freeString(&temp_dir);
    }
    var temp_repomd: ?[*:0]u8 = null;
    defer freeString(&temp_repomd);
    var replace_repomd = false;
    var new_repomd = false;
    if (need_download and handle.pArgs.?.nCacheOnly == 0) {
        common.log(LOG_NOTICE, "Refreshing metadata for: '%s'\n", .{repo.pszName});
        result = TDNFGetCachePath(handle, repo, "tmp", null, &temp_dir);
        if (result != 0) return result;
        result = TDNFUtilsMakeDirs(temp_dir);
        if (result == errors.ERROR_TDNF_ALREADY_EXISTS) result = 0;
        if (result != 0) return result;
        result = joinPath(&temp_repomd, &.{ temp_dir, repomd_file_name });
        if (result != 0) return result;
        result = secureDownload(
            handle,
            repo,
            repomd_file_path,
            temp_repomd.?,
            repo.pszId,
            true,
        );
        if (result != 0) return result;
        replace_repomd = true;
        if (old_cookie[0] != 0) {
            var new_cookie = [_]u8{0} ** cookie_len;
            result = TDNFRepoMdCalculateCookieForFile(temp_repomd, &new_cookie);
            if (result != 0) return result;
            replace_repomd = !std.mem.eql(u8, &old_cookie, &new_cookie);
        }
        new_repomd = true;
        result = BuiltinPluginsRepoMDDownloadEnd(handle, repo.pszId, temp_repomd);
        if (result != 0) return result;
    }
    if (replace_repomd) {
        _ = TDNFRepoRemoveCache(handle, repo);
        _ = TDNFRemoveSolvCache(handle, repo);
        _ = TDNFRemoveLastRefreshMarker(handle, repo);
        if (handle.pConf.?.nKeepCache == 0) _ = TDNFRemoveRpmCache(handle, repo);
        result = TDNFUtilsMakeDirs(repo_data_dir);
        if (result != 0) return result;
        result = replaceFile(temp_repomd.?, repomd_path.?);
        if (result != 0) return result;
    }
    if (new_repomd) {
        var marker: ?[*:0]u8 = null;
        defer freeString(&marker);
        result = TDNFGetCachePath(handle, repo, metadata_marker, null, &marker);
        if (result != 0) return result;
        result = touchPinnedFile(marker.?);
        if (result != 0) return result;
    }
    result = parseRepoMd(relative);
    if (result == errors.ERROR_TDNF_FILE_NOT_FOUND and handle.pArgs.?.nCacheOnly != 0)
        return errors.ERROR_TDNF_CACHE_DISABLED;
    if (result != 0) return result;
    var metadata: ?*RepoMetadata = null;
    result = ensureRepoMdParts(handle, repo, relative, &metadata);
    if (result != 0) return result;
    defer if (output.* == null) freeRepoMetadata(metadata);
    result = resolveSnapshot(handle, repo);
    if (result != 0) return result;
    output.* = metadata;
    return 0;
}

pub export fn TDNFGetRepoMD(
    handle: ?*Tdnf,
    repo: ?*RepoData,
    repo_data_dir: ?[*:0]const u8,
    output: ?*?*RepoMetadata,
) u32 {
    const result = getRepoMD(handle, repo, repo_data_dir, output);
    if (result != 0) {
        var message: ?[*:0]u8 = null;
        defer freeString(&message);
        _ = TDNFGetErrorString(result, &message);
        if (!isNullOrEmpty(message)) {
            common.log(LOG_ERR, "Error(%u) : %s\n", .{ result, message });
        }
    }
    return result;
}

pub export fn TDNFDownloadMetadata(
    handle_opt: ?*Tdnf,
    repo_opt: ?*RepoData,
    repo_dir_opt: ?[*:0]const u8,
    print_only: c_int,
) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo = repo_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo_dir = repo_dir_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (repo_dir[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var repomd_path: ?[*:0]u8 = null;
    defer freeString(&repomd_path);
    var repodata_dir: ?[*:0]u8 = null;
    defer freeString(&repodata_dir);
    var result: u32 = 0;
    if (print_only == 0) {
        result = TDNFUtilsMakeDir(repo_dir);
        if (result != 0) return result;
        result = joinPath(&repodata_dir, &.{ repo_dir, "repodata" });
        if (result != 0) return result;
        result = TDNFUtilsMakeDir(repodata_dir);
        if (result != 0) return result;
        result = joinPath(&repomd_path, &.{ repodata_dir, repomd_file_name });
        if (result != 0) return result;
        result = secureDownload(
            handle,
            repo,
            repomd_file_path,
            repomd_path.?,
            repo.pszId,
            true,
        );
        if (result != 0) return result;
    } else {
        if (repo.ppszBaseUrls == null or repo.ppszBaseUrls.?[0] == null)
            return errors.ERROR_TDNF_BASEURL_DOES_NOT_EXISTS;
        var url: ?[*:0]u8 = null;
        defer freeString(&url);
        result = joinPath(&url, &.{ repo.ppszBaseUrls.?[0], repomd_file_path });
        if (result != 0) return result;
        result = TDNFGetCachePath(handle, repo, repomd_file_path, null, &repomd_path);
        if (result != 0) return result;
        common.log(LOG_INFO, "%s\n", .{url});
    }
    var repomd_stat = std.mem.zeroes(Stat);
    result = statPinned(repomd_path.?, &repomd_stat);
    if (result != 0) return result;
    var doc: ?*RepoMdDoc = null;
    result = parseRepoMdDoc(repomd_path.?, &doc);
    if (result != 0) return result;
    defer TDNFRepoMdFree(doc);

    var index: u32 = 0;
    while (index < TDNFRepoMdGetRecordCount(doc)) : (index += 1) {
        const record = TDNFRepoMdGetRecord(doc, index) orelse continue;
        const location = record.pszLocationHref orelse continue;
        if (!safeRelativePath(location)) return errors.ERROR_TDNF_INVALID_REPO_FILE;
        var destination: ?[*:0]u8 = null;
        defer freeString(&destination);
        result = joinPath(&destination, &.{ repo_dir, location });
        if (result != 0) return result;
        if (print_only == 0) {
            result = secureDownload(
                handle,
                repo,
                location,
                destination.?,
                repo.pszId,
                true,
            );
            if (result != 0) return result;
        } else {
            var url: ?[*:0]u8 = null;
            defer freeString(&url);
            result = joinPath(&url, &.{ repo.ppszBaseUrls.?[0], location });
            if (result != 0) return result;
            common.log(LOG_INFO, "%s\n", .{url});
        }
    }
    return 0;
}

test "repositories production: path validation rejects traversal and absolute metadata" {
    try std.testing.expect(safeRelativePath("repodata/primary.xml.gz"));
    try std.testing.expect(!safeRelativePath("../outside"));
    try std.testing.expect(!safeRelativePath("repodata/../outside"));
    try std.testing.expect(!safeRelativePath("/outside"));
    try std.testing.expect(safeRelativePath("repodata//primary"));
}

test "repositories production: ABI remains canonical" {
    try std.testing.expectEqual(@sizeOf(abi.C.TDNF_REPO_DATA), @sizeOf(RepoData));
    try std.testing.expectEqual(@sizeOf(abi.C.TDNF_REPO_METADATA), @sizeOf(RepoMetadata));
}

fn readTestFile(path: []const u8) ![]u8 {
    const io = std.testing.io;
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffer: [256]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return reader.interface.allocRemaining(std.testing.allocator, .limited(4096));
}

fn expectNoDownloadTemps(directory: []const u8) !void {
    const io = std.testing.io;
    var dir = try std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true });
    defer dir.close(io);
    var iterator = dir.iterateAssumeFirstIteration();
    while (try iterator.next(io)) |entry| {
        try std.testing.expect(!std.mem.startsWith(
            u8,
            entry.name,
            ".tdnf-repository-",
        ));
    }
}

const TestRepoFixture = struct {
    args: abi.CmdArgs,
    conf: Conf,
    handle: Tdnf,
};

fn testRepoHandle(repo_dir: [*:0]u8, setopts: *CnfNode) TestRepoFixture {
    return .{
        .args = abi.CmdArgs{ .cn_setopts = setopts },
        .conf = Conf{ .pszRepoDir = repo_dir },
        .handle = Tdnf{},
    };
}

fn expectProductionScanFailure(
    repo_dir: [*:0]u8,
    setopts: *CnfNode,
    stage: ScanFailureStage,
    errno_value: c_int,
) !void {
    var fixture = testRepoHandle(repo_dir, setopts);
    fixture.handle = .{ .pArgs = &fixture.args, .pConf = &fixture.conf };
    injected_scan_failure = .{
        .stage = stage,
        .errno_value = errno_value,
    };
    defer injected_scan_failure = null;
    var repos: ?*RepoData = @ptrFromInt(@alignOf(RepoData));
    try std.testing.expectEqual(
        systemErrorFrom(errno_value),
        TDNFLoadRepoData(&fixture.handle, &repos),
    );
    try std.testing.expect(injected_scan_failure.?.triggered);
    try std.testing.expectEqual(@as(?*RepoData, null), repos);
}

test "repositories production: scan propagates syscall failures" {
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const root = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/repository-scan-errors-{d}",
        .{std.os.linux.getpid()},
        0,
    );
    defer std.testing.allocator.free(root);
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root);
    const repo_file = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/entry.repo",
        .{root},
    );
    defer std.testing.allocator.free(repo_file);
    try cwd.writeFile(io, .{ .sub_path = repo_file, .data = "[entry]\n" });
    var setopts = CnfNode{};

    try expectProductionScanFailure(
        root.ptr,
        &setopts,
        .directory_open,
        @intFromEnum(std.c.E.ACCES),
    );
    try expectProductionScanFailure(
        root.ptr,
        &setopts,
        .duplicate,
        @intFromEnum(std.c.E.MFILE),
    );
    try expectProductionScanFailure(
        root.ptr,
        &setopts,
        .fdopendir,
        @intFromEnum(std.c.E.MFILE),
    );
    try expectProductionScanFailure(
        root.ptr,
        &setopts,
        .readdir,
        @intFromEnum(std.c.E.IO),
    );
    try expectProductionScanFailure(
        root.ptr,
        &setopts,
        .pre_stat,
        @intFromEnum(std.c.E.IO),
    );
    try expectProductionScanFailure(
        root.ptr,
        &setopts,
        .entry_open,
        @intFromEnum(std.c.E.ACCES),
    );
    try expectProductionScanFailure(
        root.ptr,
        &setopts,
        .post_stat,
        @intFromEnum(std.c.E.IO),
    );
}

test "repositories production: fdopendir error survives cleanup close failure" {
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const root = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/repository-close-error-{d}",
        .{std.os.linux.getpid()},
        0,
    );
    defer std.testing.allocator.free(root);
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root);

    var setopts = CnfNode{};
    injected_scan_failure = .{
        .stage = .fdopendir,
        .errno_value = @intFromEnum(std.c.E.MFILE),
    };
    defer injected_scan_failure = null;
    injected_close_failure = .{
        .errno_value = @intFromEnum(std.c.E.IO),
    };
    defer injected_close_failure = null;
    var fixture = testRepoHandle(root.ptr, &setopts);
    fixture.handle = .{ .pArgs = &fixture.args, .pConf = &fixture.conf };
    var repos: ?*RepoData = @ptrFromInt(@alignOf(RepoData));
    try std.testing.expectEqual(
        systemErrorFrom(@intFromEnum(std.c.E.MFILE)),
        TDNFLoadRepoData(&fixture.handle, &repos),
    );
    try std.testing.expect(injected_scan_failure.?.triggered);
    try std.testing.expect(injected_close_failure.?.triggered);
    try std.testing.expectEqual(
        @intFromEnum(std.c.E.MFILE),
        std.c._errno().*,
    );
    try std.testing.expectEqual(@as(?*RepoData, null), repos);
}

test "repositories production: scan skips fifo socket device and symlink promptly" {
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const root = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/repository-special-files-{d}",
        .{std.os.linux.getpid()},
        0,
    );
    defer std.testing.allocator.free(root);
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root);

    const fifo = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/fifo.repo",
        .{root},
        0,
    );
    defer std.testing.allocator.free(fifo);
    try std.testing.expectEqual(@as(c_int, 0), mkfifo(fifo.ptr, 0o600));

    const socket_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/socket.repo",
        .{root},
        0,
    );
    defer std.testing.allocator.free(socket_path);
    const socket_fd = std.c.socket(
        std.c.AF.UNIX,
        std.c.SOCK.STREAM | std.c.SOCK.CLOEXEC,
        0,
    );
    try std.testing.expect(socket_fd >= 0);
    defer _ = std.c.close(socket_fd);
    var address = std.mem.zeroes(SockaddrUn);
    address.family = std.c.AF.UNIX;
    const socket_bytes = std.mem.span(socket_path.ptr);
    try std.testing.expect(socket_bytes.len < address.path.len);
    @memcpy(address.path[0..socket_bytes.len], socket_bytes);
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.bind(
            socket_fd,
            @ptrCast(&address),
            @sizeOf(SockaddrUn),
        ),
    );

    const device = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/device.repo",
        .{root},
        0,
    );
    defer std.testing.allocator.free(device);
    if (mknod(
        device.ptr,
        std.os.linux.S.IFCHR | 0o600,
        @as(std.c.dev_t, 0x103),
    ) != 0) {
        try std.testing.expect(
            std.c._errno().* == @intFromEnum(std.c.E.PERM) or
                std.c._errno().* == @intFromEnum(std.c.E.ACCES),
        );
    }

    const symlink = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/symlink.repo",
        .{root},
    );
    defer std.testing.allocator.free(symlink);
    try cwd.symLink(io, "fifo.repo", symlink, .{});

    var setopts = CnfNode{};
    var fixture = testRepoHandle(root.ptr, &setopts);
    fixture.handle = .{ .pArgs = &fixture.args, .pConf = &fixture.conf };
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    var repos: ?*RepoData = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFLoadRepoData(&fixture.handle, &repos),
    );
    defer TDNFFreeReposInternal(repos);
    const elapsed = start.durationTo(
        std.Io.Clock.Timestamp.now(io, .awake),
    ).raw.toNanoseconds();
    try std.testing.expect(elapsed < 2 * std.time.ns_per_s);
    try std.testing.expect(repos != null);
    try std.testing.expectEqualStrings(
        cmdline_repo_name,
        std.mem.span(repos.?.pszId.?),
    );
    try std.testing.expectEqual(@as(?*RepoData, null), repos.?.pNext);
}

test "repositories production: download temp names are high entropy and unique" {
    var names: [32][96]u8 = undefined;
    for (&names, 0..) |*name, index| {
        try std.testing.expectEqual(@as(u32, 0), randomTempName(name));
        const value = std.mem.sliceTo(name, 0);
        try std.testing.expect(std.mem.startsWith(
            u8,
            value,
            ".tdnf-repository-",
        ));
        try std.testing.expect(std.mem.endsWith(u8, value, ".tmp"));
        try std.testing.expectEqual(
            @as(usize, ".tdnf-repository-".len + 32 + ".tmp".len),
            value.len,
        );
        for (names[0..index]) |prior| {
            try std.testing.expect(!std.mem.eql(
                u8,
                value,
                std.mem.sliceTo(&prior, 0),
            ));
        }
    }
}

test "repositories production: metadata and snapshot downloads reject symlinks and retry remote failures" {
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const root = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/repository-download-security-{d}",
        .{std.os.linux.getpid()},
    );
    defer std.testing.allocator.free(root);
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root);

    const source = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/payload",
        .{root},
    );
    defer std.testing.allocator.free(source);
    const sentinel = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/outside-sentinel",
        .{root},
    );
    defer std.testing.allocator.free(sentinel);
    try cwd.writeFile(io, .{ .sub_path = source, .data = "payload" });
    try cwd.writeFile(io, .{ .sub_path = sentinel, .data = "outside" });

    const source_url = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "file:///proc/self/cwd/{s}",
        .{source},
        0,
    );
    defer std.testing.allocator.free(source_url);
    const source_parent_url = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "file:///proc/self/cwd/{s}",
        .{root},
        0,
    );
    defer std.testing.allocator.free(source_parent_url);
    const sentinel_absolute = try std.fmt.allocPrint(
        std.testing.allocator,
        "/proc/self/cwd/{s}",
        .{sentinel},
    );
    defer std.testing.allocator.free(sentinel_absolute);

    var args = abi.CmdArgs{};
    var conf = abi.Conf{};
    var handle = abi.Tdnf{ .pArgs = &args, .pConf = &conf };
    var base_urls = [_]?[*:0]u8{ source_parent_url.ptr, null };
    var repo = RepoData{
        .ppszBaseUrls = &base_urls,
        .nRetries = 0,
        .nSSLVerify = 1,
    };

    const destinations = [_]struct {
        directory: []const u8,
        filename: []const u8,
        source_value: [*:0]const u8,
        from_repo: bool,
    }{
        .{
            .directory = "metadata",
            .filename = "repomd.xml",
            .source_value = "payload",
            .from_repo = true,
        },
        .{
            .directory = "snapshot",
            .filename = "snapshot.list",
            .source_value = source_url.ptr,
            .from_repo = false,
        },
    };
    for (destinations) |entry| {
        const directory = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/{s}",
            .{ root, entry.directory },
        );
        defer std.testing.allocator.free(directory);
        try cwd.createDirPath(io, directory);
        const destination = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/{s}",
            .{ directory, entry.filename },
            0,
        );
        defer std.testing.allocator.free(destination);

        const legacy_temp = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}.tmp",
            .{destination},
        );
        defer std.testing.allocator.free(legacy_temp);
        try cwd.symLink(io, sentinel_absolute, legacy_temp, .{});
        for (0..download_temp_attempts) |candidate| {
            const predictable = try std.fmt.allocPrint(
                std.testing.allocator,
                "{s}/.tdnf-repository-{d}-{d}.tmp",
                .{ directory, std.os.linux.getpid(), candidate },
            );
            defer std.testing.allocator.free(predictable);
            try cwd.symLink(io, sentinel_absolute, predictable, .{});
        }

        try std.testing.expectEqual(
            @as(u32, 0),
            secureDownload(
                &handle,
                &repo,
                entry.source_value,
                destination.ptr,
                null,
                entry.from_repo,
            ),
        );
        const downloaded = try readTestFile(destination);
        defer std.testing.allocator.free(downloaded);
        try std.testing.expectEqualStrings("payload", downloaded);
        const outside = try readTestFile(sentinel);
        defer std.testing.allocator.free(outside);
        try std.testing.expectEqualStrings("outside", outside);

        try cwd.deleteFile(io, destination);
        try cwd.symLink(io, sentinel_absolute, destination, .{});
        try std.testing.expectEqual(
            systemErrorFrom(@intFromEnum(std.c.E.LOOP)),
            secureDownload(
                &handle,
                &repo,
                entry.source_value,
                destination.ptr,
                null,
                entry.from_repo,
            ),
        );
        const outside_after = try readTestFile(sentinel);
        defer std.testing.allocator.free(outside_after);
        try std.testing.expectEqualStrings("outside", outside_after);
    }

    const outside_dir = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/outside-directory",
        .{root},
    );
    defer std.testing.allocator.free(outside_dir);
    try cwd.createDirPath(io, outside_dir);
    const ancestor_link = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/cache-link",
        .{root},
    );
    defer std.testing.allocator.free(ancestor_link);
    try cwd.symLink(io, "outside-directory", ancestor_link, .{ .is_directory = true });
    const escaped_destination = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/escaped",
        .{ancestor_link},
        0,
    );
    defer std.testing.allocator.free(escaped_destination);
    const ancestor_result = secureDownload(
        &handle,
        &repo,
        source_url.ptr,
        escaped_destination.ptr,
        null,
        false,
    );
    try std.testing.expect(
        ancestor_result == systemErrorFrom(@intFromEnum(std.c.E.LOOP)) or
            ancestor_result == systemErrorFrom(@intFromEnum(std.c.E.NOTDIR)),
    );
    try std.testing.expectError(
        error.FileNotFound,
        cwd.access(io, escaped_destination, .{}),
    );

    const clean_body = "payload";
    const stale_prefix = "stale-partial-prefix:";
    {
        const directory = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/metadata-fallback",
            .{root},
        );
        defer std.testing.allocator.free(directory);
        try cwd.createDirPath(io, directory);
        const destination = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/repomd.xml",
            .{directory},
            0,
        );
        defer std.testing.allocator.free(destination);

        const partial_url = try std.testing.allocator.dupeZ(
            u8,
            "file:///injected-partial",
        );
        defer std.testing.allocator.free(partial_url);
        var retry_urls = [_]?[*:0]u8{
            partial_url.ptr,
            source_parent_url.ptr,
            null,
        };
        injected_partial_download_failure = .{
            .url = "file:///injected-partial/payload",
            .bytes = stale_prefix,
            .remaining = 1,
        };
        defer injected_partial_download_failure = null;
        repo.ppszBaseUrls = &retry_urls;
        repo.nRetries = 0;
        const result = secureDownload(
            &handle,
            &repo,
            "payload",
            destination.ptr,
            null,
            true,
        );
        try std.testing.expectEqual(@as(u32, 0), result);
        try std.testing.expectEqual(
            @as(usize, 1),
            injected_partial_download_failure.?.triggered,
        );
        try std.testing.expectEqual(
            @as(usize, 0),
            injected_partial_download_failure.?.remaining,
        );
        const downloaded = try readTestFile(destination);
        defer std.testing.allocator.free(downloaded);
        try std.testing.expectEqualStrings(clean_body, downloaded);
        try expectNoDownloadTemps(directory);
        injected_partial_download_failure = null;
    }

    {
        const directory = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/snapshot-retry",
            .{root},
        );
        defer std.testing.allocator.free(directory);
        try cwd.createDirPath(io, directory);
        const destination = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/snapshot.list",
            .{directory},
            0,
        );
        defer std.testing.allocator.free(destination);

        injected_partial_download_failure = .{
            .url = std.mem.span(source_url.ptr),
            .bytes = stale_prefix,
            .remaining = 1,
        };
        defer injected_partial_download_failure = null;
        suppress_test_info_logs = true;
        defer suppress_test_info_logs = false;
        repo.nRetries = 1;
        const result = secureDownload(
            &handle,
            &repo,
            source_url.ptr,
            destination.ptr,
            null,
            false,
        );
        try std.testing.expectEqual(@as(u32, 0), result);
        try std.testing.expectEqual(
            @as(usize, 1),
            injected_partial_download_failure.?.triggered,
        );
        try std.testing.expectEqual(
            @as(usize, 0),
            injected_partial_download_failure.?.remaining,
        );
        const downloaded = try readTestFile(destination);
        defer std.testing.allocator.free(downloaded);
        try std.testing.expectEqualStrings(clean_body, downloaded);
        try expectNoDownloadTemps(directory);
        injected_partial_download_failure = null;
        suppress_test_info_logs = false;
    }

    const remote_errors = [_]anyerror{
        error.WriteFailed,
        error.Unexpected,
        error.SystemResources,
    };
    for (remote_errors, 0..) |remote_error, index| {
        const directory = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/remote-fallback-{d}",
            .{ root, index },
        );
        defer std.testing.allocator.free(directory);
        try cwd.createDirPath(io, directory);
        const destination = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/repomd.xml",
            .{directory},
            0,
        );
        defer std.testing.allocator.free(destination);

        const failing_url = try std.testing.allocator.dupeZ(
            u8,
            "file:///remote-write-failure",
        );
        defer std.testing.allocator.free(failing_url);
        var retry_urls = [_]?[*:0]u8{
            failing_url.ptr,
            source_parent_url.ptr,
            null,
        };
        injected_download_error_failure = .{
            .url = "file:///remote-write-failure/payload",
            .err = remote_error,
            .remaining = 1,
        };
        defer injected_download_error_failure = null;
        repo.ppszBaseUrls = &retry_urls;
        repo.nRetries = 0;
        try std.testing.expectEqual(
            @as(u32, 0),
            secureDownload(
                &handle,
                &repo,
                "payload",
                destination.ptr,
                null,
                true,
            ),
        );
        try std.testing.expectEqual(
            @as(usize, 1),
            injected_download_error_failure.?.triggered,
        );
        const downloaded = try readTestFile(destination);
        defer std.testing.allocator.free(downloaded);
        try std.testing.expectEqualStrings(clean_body, downloaded);
        try expectNoDownloadTemps(directory);
        injected_download_error_failure = null;
    }
}

test "repositories production: metadata local fd and fsync failures never fall through" {
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const root = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/repository-fsync-{d}",
        .{std.os.linux.getpid()},
    );
    defer std.testing.allocator.free(root);
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    const source_root = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/source",
        .{root},
    );
    defer std.testing.allocator.free(source_root);
    const source_repodata = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/repodata",
        .{source_root},
    );
    defer std.testing.allocator.free(source_repodata);
    try cwd.createDirPath(io, source_repodata);
    const source_repomd = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/repomd.xml",
        .{source_repodata},
    );
    defer std.testing.allocator.free(source_repomd);
    const repomd =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" ++
        "<repomd xmlns=\"http://linux.duke.edu/metadata/repo\"></repomd>";
    try cwd.writeFile(io, .{ .sub_path = source_repomd, .data = repomd });

    const source_url = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "file:///proc/self/cwd/{s}",
        .{source_root},
        0,
    );
    defer std.testing.allocator.free(source_url);
    var base_urls = [_]?[*:0]u8{ source_url.ptr, null };
    var args = abi.CmdArgs{};
    var conf = Conf{};
    var handle = Tdnf{ .pArgs = &args, .pConf = &conf };
    var repo = RepoData{
        .pszId = @constCast("fsync"),
        .pszName = @constCast("fsync"),
        .ppszBaseUrls = &base_urls,
        .nRetries = 0,
        .nSSLVerify = 1,
    };

    const reset_failure_url = try std.testing.allocator.dupeZ(
        u8,
        "file:///reset-failure",
    );
    defer std.testing.allocator.free(reset_failure_url);
    const fallback_url = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/repodata/repomd.xml",
        .{std.mem.span(source_url.ptr)},
    );
    defer std.testing.allocator.free(fallback_url);
    {
        const destination = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/local-output",
            .{root},
            0,
        );
        defer std.testing.allocator.free(destination);
        injected_download_error_failure = .{
            .url = "file:///reset-failure/repodata/repomd.xml",
            .err = error.LocalOutputFailed,
            .remaining = 1,
        };
        defer injected_download_error_failure = null;
        injected_partial_download_failure = .{
            .url = fallback_url,
            .bytes = "fallback-must-not-run",
            .remaining = 1,
        };
        defer injected_partial_download_failure = null;
        var local_failure_base_urls = [_]?[*:0]u8{
            reset_failure_url.ptr,
            source_url.ptr,
            null,
        };
        repo.ppszBaseUrls = &local_failure_base_urls;
        try std.testing.expectEqual(
            errors.ERROR_TDNF_REPO_PERFORM,
            TDNFDownloadMetadata(&handle, &repo, destination.ptr, 0),
        );
        try std.testing.expectEqual(
            @as(usize, 1),
            injected_download_error_failure.?.triggered,
        );
        try std.testing.expectEqual(
            @as(usize, 0),
            injected_partial_download_failure.?.triggered,
        );
        try std.testing.expectEqual(
            @as(usize, 1),
            injected_partial_download_failure.?.remaining,
        );
        const destination_repomd = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/repodata/repomd.xml",
            .{destination},
        );
        defer std.testing.allocator.free(destination_repomd);
        try std.testing.expectError(
            error.FileNotFound,
            cwd.access(io, destination_repomd, .{}),
        );
        const repodata_directory = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/repodata",
            .{destination},
        );
        defer std.testing.allocator.free(repodata_directory);
        try expectNoDownloadTemps(repodata_directory);
        injected_download_error_failure = null;
        injected_partial_download_failure = null;
    }
    const reset_stages = [_]ResetFailureStage{ .truncate, .seek };
    for (reset_stages, 0..) |stage, index| {
        const destination = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/reset-{d}",
            .{ root, index },
            0,
        );
        defer std.testing.allocator.free(destination);
        injected_reset_failure = .{
            .stage = stage,
            .errno_value = @intFromEnum(std.c.E.IO),
        };
        defer injected_reset_failure = null;
        injected_partial_download_failure = .{
            .url = fallback_url,
            .bytes = "fallback-must-not-run",
            .remaining = 1,
        };
        defer injected_partial_download_failure = null;
        var reset_base_urls = [_]?[*:0]u8{
            reset_failure_url.ptr,
            source_url.ptr,
            null,
        };
        repo.ppszBaseUrls = &reset_base_urls;
        try std.testing.expectEqual(
            systemErrorFrom(@intFromEnum(std.c.E.IO)),
            TDNFDownloadMetadata(&handle, &repo, destination.ptr, 0),
        );
        try std.testing.expect(injected_reset_failure.?.triggered);
        try std.testing.expectEqual(
            @as(usize, 0),
            injected_partial_download_failure.?.triggered,
        );
        try std.testing.expectEqual(
            @as(usize, 1),
            injected_partial_download_failure.?.remaining,
        );
        const destination_repomd = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/repodata/repomd.xml",
            .{destination},
        );
        defer std.testing.allocator.free(destination_repomd);
        try std.testing.expectError(
            error.FileNotFound,
            cwd.access(io, destination_repomd, .{}),
        );
        const repodata_directory = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/repodata",
            .{destination},
        );
        defer std.testing.allocator.free(repodata_directory);
        try expectNoDownloadTemps(repodata_directory);
        injected_reset_failure = null;
        injected_partial_download_failure = null;
    }
    repo.ppszBaseUrls = &base_urls;

    const destinations = [_]struct {
        suffix: []const u8,
        stage: SyncFailureStage,
        committed: bool,
    }{
        .{ .suffix = "file-sync", .stage = .file, .committed = false },
        .{
            .suffix = "directory-sync",
            .stage = .destination_directory,
            .committed = true,
        },
    };
    for (destinations) |entry| {
        const destination = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/{s}",
            .{ root, entry.suffix },
            0,
        );
        defer std.testing.allocator.free(destination);
        injected_sync_failure = .{
            .stage = entry.stage,
            .errno_value = @intFromEnum(std.c.E.IO),
        };
        defer injected_sync_failure = null;
        try std.testing.expectEqual(
            systemErrorFrom(@intFromEnum(std.c.E.IO)),
            TDNFDownloadMetadata(&handle, &repo, destination.ptr, 0),
        );
        try std.testing.expect(injected_sync_failure.?.triggered);
        const destination_repomd = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/repodata/repomd.xml",
            .{destination},
        );
        defer std.testing.allocator.free(destination_repomd);
        if (entry.committed) {
            const contents = try readTestFile(destination_repomd);
            defer std.testing.allocator.free(contents);
            try std.testing.expectEqualStrings(repomd, contents);
        } else {
            try std.testing.expectError(
                error.FileNotFound,
                cwd.access(io, destination_repomd, .{}),
            );
        }
        injected_sync_failure = null;
    }
}

test "repositories production: cross-directory rename syncs both parents and never rolls back" {
    const cwd = std.Io.Dir.cwd();
    const io = std.testing.io;
    const root = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/repository-rename-sync-{d}",
        .{std.os.linux.getpid()},
    );
    defer std.testing.allocator.free(root);
    cwd.deleteTree(io, root) catch {};
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root);

    const stages = [_]SyncFailureStage{
        .source_directory,
        .destination_directory,
    };
    for (stages, 0..) |stage, index| {
        const source_dir = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/source-{d}",
            .{ root, index },
        );
        defer std.testing.allocator.free(source_dir);
        const destination_dir = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}/destination-{d}",
            .{ root, index },
        );
        defer std.testing.allocator.free(destination_dir);
        try cwd.createDirPath(io, source_dir);
        try cwd.createDirPath(io, destination_dir);
        const source = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/file",
            .{source_dir},
            0,
        );
        defer std.testing.allocator.free(source);
        const destination = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}/file",
            .{destination_dir},
            0,
        );
        defer std.testing.allocator.free(destination);
        try cwd.writeFile(io, .{ .sub_path = source, .data = "committed" });

        sync_stage_counts = [_]usize{0} ** 3;
        injected_sync_failure = .{
            .stage = stage,
            .errno_value = @intFromEnum(std.c.E.IO),
        };
        defer injected_sync_failure = null;
        try std.testing.expectEqual(
            systemErrorFrom(@intFromEnum(std.c.E.IO)),
            replaceFile(source.ptr, destination.ptr),
        );
        try std.testing.expect(injected_sync_failure.?.triggered);
        try std.testing.expectEqual(
            @as(usize, 1),
            sync_stage_counts[@intFromEnum(SyncFailureStage.source_directory)],
        );
        try std.testing.expectEqual(
            @as(usize, 1),
            sync_stage_counts[@intFromEnum(SyncFailureStage.destination_directory)],
        );
        try std.testing.expectError(
            error.FileNotFound,
            cwd.access(io, source, .{}),
        );
        const contents = try readTestFile(destination);
        defer std.testing.allocator.free(contents);
        try std.testing.expectEqualStrings("committed", contents);
        injected_sync_failure = null;
    }
}
