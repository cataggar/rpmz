// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const abi = @import("client_abi");
const errors = @import("tdnf_error");

const CnfNode = abi.CnfNode;
const Conf = abi.Conf;
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

const Stat = std.os.linux.Statx;

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const LOG_CRIT: c_int = 2;
const LOG_NOTICE: c_int = 3;
const F_OK: c_int = 0;

const system_repo_name = "@System";
const cmdline_repo_name = "@cmdline";
const repo_extension = ".repo";
const repomd_file_path = "repodata/repomd.xml";
const repomd_file_name = "repomd.xml";
const metadata_marker = "lastrefresh";
const metadata_mirrorlist = "mirrorlist";
const metadata_snapshot = "snapshot";
const cookie_len = 32;

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

extern fn TDNFAllocateMemory(usize, usize, *?*anyopaque) u32;
extern fn TDNFAllocateString(?[*:0]const u8, *?[*:0]u8) u32;
extern fn TDNFAllocateStringPrintf(*?[*:0]u8, [*:0]const u8, ...) u32;
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
extern fn fnmatch([*:0]const u8, [*:0]const u8, c_int) c_int;
extern fn access(?[*:0]const u8, c_int) c_int;
extern fn rename([*:0]const u8, [*:0]const u8) c_int;
extern fn time(?*std.c.time_t) std.c.time_t;
extern fn log_console(c_int, [*:0]const u8, ...) void;

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
extern fn TDNFTouchFile(?[*:0]const u8) u32;
extern fn TDNFDownloadFile(?*Tdnf, ?*RepoData, ?[*:0]const u8, ?[*:0]const u8, ?[*:0]const u8, c_int) u32;
extern fn TDNFDownloadFileFromRepo(?*Tdnf, ?*RepoData, ?[*:0]const u8, ?[*:0]const u8, ?[*:0]const u8) u32;
extern fn TDNFGetErrorString(u32, *?[*:0]u8) u32;

fn isNullOrEmpty(value: ?[*:0]const u8) bool {
    return value == null or value.?[0] == 0;
}

fn systemError() u32 {
    return errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(std.c._errno().*));
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
            log_console(LOG_ERR, "CreateRepoFromPath: Error while operating on '%s'\n", path);
            return result;
        }
        if (is_dir == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
        result = TDNFAllocateStringPrintf(&repo.?.ppszBaseUrls.?[0], "file://%s", path);
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
        log_console(LOG_ERR, "CreateRepoFromDir: Error while operating on '%s'\n", path);
        return result;
    }
    if (is_dir == 0) {
        log_console(LOG_ERR, "%s is not a directory\n", path);
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

fn isRegularFd(fd: c_int) bool {
    var stat_buf = std.mem.zeroes(Stat);
    if (std.c.statx(
        fd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        .{ .TYPE = true },
        &stat_buf,
    ) != 0) return false;
    return stat_buf.mode & std.os.linux.S.IFMT == std.os.linux.S.IFREG;
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
    result = openDirectoryPathNoFollow(repo_dir, &repo_dir_fd);
    if (result != 0) return errors.ERROR_TDNF_REPO_DIR_OPEN;
    defer _ = std.c.close(repo_dir_fd);
    const scan_fd = std.c.dup(repo_dir_fd);
    if (scan_fd < 0) return errors.ERROR_TDNF_REPO_DIR_OPEN;
    const dir = fdopendir(scan_fd) orelse {
        _ = std.c.close(scan_fd);
        return errors.ERROR_TDNF_REPO_DIR_OPEN;
    };
    defer _ = closedir(dir);
    while (readdir(dir)) |entry| {
        const name = std.mem.sliceTo(&entry.name, 0);
        if (name.len <= repo_extension.len or
            !std.mem.endsWith(u8, name, repo_extension)) continue;
        const name_z: [*:0]const u8 = @ptrCast(&entry.name);
        const repo_fd = std.c.openat(repo_dir_fd, name_z, .{
            .ACCMODE = .RDONLY,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (repo_fd < 0) continue;
        defer _ = std.c.close(repo_fd);
        if (!isRegularFd(repo_fd)) continue;
        var path_buffer: [64]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buffer, "/proc/self/fd/{d}", .{repo_fd}) catch
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        var loaded: ?*RepoData = null;
        result = loadReposFromFile(handle, path, &loaded);
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
                log_console(LOG_ERR, "ERROR: duplicate repo id: %s\n", left.pszId.?);
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
        log_console(LOG_CRIT, "Error(%u) parsing repomd: %s\n", result, TDNFRepoMdLastError());
        const empty = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><repomd xmlns=\"http://linux.duke.edu/metadata/repo\"></repomd>";
        result = TDNFRepoMdParseBuffer(empty.ptr, empty.len, output);
    }
    return result;
}

fn parseRepoMd(metadata: *RepoMetadata) u32 {
    const path = metadata.pszRepoMD orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var doc: ?*RepoMdDoc = null;
    var result = parseRepoMdDoc(path, &doc);
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

fn downloadRepoMdPart(
    handle: *Tdnf,
    repo: *RepoData,
    location: [*:0]const u8,
    destination: [*:0]const u8,
    name: [*:0]const u8,
) u32 {
    if (!safeRelativePath(location)) return errors.ERROR_TDNF_INVALID_REPO_FILE;
    if (access(destination, F_OK) == 0) return 0;
    if (std.c._errno().* != @intFromEnum(std.c.E.NOENT)) return systemError();
    var info: ?[*:0]u8 = null;
    defer freeString(&info);
    var result = TDNFAllocateStringPrintf(&info, "%s (%s)", repo.pszId, name);
    if (result != 0) return result;
    result = TDNFDownloadFileFromRepo(handle, repo, location, destination, info);
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
    if (source[0] == 0 or destination[0] == 0 or access(source, F_OK) != 0)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (rename(source, destination) != 0) return systemError();
    return 0;
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
    if (std.c.statx(std.os.linux.AT.FDCWD, path, 0, .{ .TYPE = true, .CTIME = true }, &stat_buf) != 0) {
        if (std.c._errno().* == @intFromEnum(std.c.E.NOENT)) {
            needs_download.* = true;
            return 0;
        }
        return systemError();
    }
    const now = time(null);
    needs_download.* = now - stat_buf.ctime.sec > expire;
    return 0;
}

fn validateLocalSnapshot(path: [*:0]const u8) u32 {
    var stat_buf = std.mem.zeroes(Stat);
    if (std.c.statx(
        std.os.linux.AT.FDCWD,
        path,
        std.os.linux.AT.SYMLINK_NOFOLLOW,
        .{ .TYPE = true },
        &stat_buf,
    ) != 0) return systemError();
    if (stat_buf.mode & std.os.linux.S.IFMT != std.os.linux.S.IFREG)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    return 0;
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
            return TDNFDownloadFile(handle, repo, snapshot, repo.pszSnapshotFile, repo.pszId, 0);
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
            result = TDNFDownloadFile(handle, repo, mirror_url, mirror_file, repo.pszId, 0);
            if (result != 0) return result;
        }
        TDNFFreeStringArray(repo.ppszBaseUrls);
        repo.ppszBaseUrls = null;
        result = TDNFReadFileToStringArray(mirror_file, &repo.ppszBaseUrls);
        if (result != 0) return result;
        filterMirrorComments(repo.ppszBaseUrls);
    }
    if (repo.ppszBaseUrls == null or isNullOrEmpty(repo.ppszBaseUrls.?[0])) {
        log_console(LOG_ERR, "Error: Cannot find a valid base URL for repo: %s\n", repo.pszName);
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

    var need_download = access(repomd_path, F_OK) != 0;
    if (need_download and std.c._errno().* != @intFromEnum(std.c.E.NOENT)) return systemError();
    var old_cookie = [_]u8{0} ** cookie_len;
    if (handle.pArgs.?.nRefresh != 0) {
        if (access(repomd_path, F_OK) == 0) {
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
        log_console(LOG_NOTICE, "Refreshing metadata for: '%s'\n", repo.pszName);
        result = TDNFGetCachePath(handle, repo, "tmp", null, &temp_dir);
        if (result != 0) return result;
        result = TDNFUtilsMakeDirs(temp_dir);
        if (result == errors.ERROR_TDNF_ALREADY_EXISTS) result = 0;
        if (result != 0) return result;
        result = joinPath(&temp_repomd, &.{ temp_dir, repomd_file_name });
        if (result != 0) return result;
        result = TDNFDownloadFileFromRepo(handle, repo, repomd_file_path, temp_repomd, repo.pszId);
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
        result = TDNFTouchFile(marker);
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
            log_console(LOG_ERR, "Error(%u) : %s\n", result, message);
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
        result = TDNFDownloadFileFromRepo(handle, repo, repomd_file_path, repomd_path, repo.pszId);
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
        log_console(LOG_INFO, "%s\n", url);
    }
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
            result = TDNFDownloadFileFromRepo(handle, repo, location, destination, repo.pszId);
            if (result != 0) return result;
        } else {
            var url: ?[*:0]u8 = null;
            defer freeString(&url);
            result = joinPath(&url, &.{ repo.ppszBaseUrls.?[0], location });
            if (result != 0) return result;
            log_console(LOG_INFO, "%s\n", url);
        }
    }
    return 0;
}

test "repository path validation rejects traversal and absolute metadata" {
    try std.testing.expect(safeRelativePath("repodata/primary.xml.gz"));
    try std.testing.expect(!safeRelativePath("../outside"));
    try std.testing.expect(!safeRelativePath("repodata/../outside"));
    try std.testing.expect(!safeRelativePath("/outside"));
    try std.testing.expect(safeRelativePath("repodata//primary"));
}

test "repository ABI remains canonical" {
    try std.testing.expectEqual(@sizeOf(abi.C.TDNF_REPO_DATA), @sizeOf(RepoData));
    try std.testing.expectEqual(@sizeOf(abi.C.TDNF_REPO_METADATA), @sizeOf(RepoMetadata));
}
