// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("rpmz_common");
const builtin = @import("builtin");
const abi = @import("client_abi");
const errors = @import("rpmz_error");
const options = @import("client_config_options");
const rpmtrans = @import("rpmtrans_flags");
const txn_config = @import("rpm_txn_config");
const varsdir = @import("client_varsdir");

const CnfNode = abi.CnfNode;
const CmdArgs = abi.CmdArgs;
const Conf = abi.Conf;
const Tdnf = abi.Tdnf;

const OS_REL_FILE = "/etc/os-release";

const DEFAULT_REPO_LOCATION = "/etc/yum.repos.d";
const DEFAULT_CACHE_LOCATION = "/var/cache/tdnf";
const DEFAULT_VARS_DIRS = "/etc/rpmz/vars /etc/dnf/vars /etc/yum/vars";
const DEFAULT_DISTROVERPKGS = "system-release(releasever) system-release redhat-release";
const DEFAULT_PLUGIN_CONF_PATH = "/etc/rpmz/pluginconf.d";
const DEFAULT_PLUGIN_PATH = options.system_libdir ++ "/rpmz-plugins";

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const LOG_NOTICE: c_int = 3;

const DIR = opaque {};
const FILE = opaque {};
const CnfModule = opaque {};

const NAME_BUF_LEN = 256;
const Dirent = extern struct {
    ino: u64,
    off: i64,
    reclen: c_ushort,
    type: u8,
    name: [NAME_BUF_LEN]u8,
};

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
extern fn TDNFSplitStringToArray(
    value: ?[*:0]const u8,
    separators: ?[*:0]const u8,
    output: *?[*]?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFAddStringArray(
    values: *?[*]?[*:0]u8,
    value: ?[*:0]const u8,
) callconv(.c) u32;
extern fn TDNFStringArrayCount(
    values: ?[*]?[*:0]u8,
    count: *c_int,
) callconv(.c) u32;
extern fn TDNFReadFileToStringArray(
    path: ?[*:0]const u8,
    output: *?[*]?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFJoinPathFromArray(
    output: *?[*:0]u8,
    nodes: [*]?[*:0]u8,
    count: c_int,
) callconv(.c) u32;
extern fn TDNFDirName(
    path: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFIsDir(
    path: ?[*:0]const u8,
    is_dir: *c_int,
) callconv(.c) u32;
extern fn strtoi(value: ?[*:0]const u8) callconv(.c) i32;
extern fn isTrue(value: ?[*:0]const u8) callconv(.c) c_int;
extern fn register_ini(root: ?*CnfNode) callconv(.c) void;
extern fn find_cnfmodule(name: ?[*:0]const u8) callconv(.c) ?*CnfModule;
extern fn cnfmodule_parse_file(
    module: ?*CnfModule,
    path: ?[*:0]const u8,
) callconv(.c) ?*CnfNode;
extern fn cnfmodule_parse(
    module: ?*CnfModule,
    stream: ?*FILE,
) callconv(.c) ?*CnfNode;
extern fn create_cnfnode(name: ?[*:0]const u8) callconv(.c) ?*CnfNode;
extern fn cnfnode_setval(
    node: ?*CnfNode,
    value: ?[*:0]const u8,
) callconv(.c) void;
extern fn append_node(parent: ?*CnfNode, node: ?*CnfNode) callconv(.c) void;
extern fn destroy_cnftree(node: ?*CnfNode) callconv(.c) void;
extern fn opendir(path: [*:0]const u8) callconv(.c) ?*DIR;
extern fn readdir(dir: *DIR) callconv(.c) ?*Dirent;
extern fn closedir(dir: *DIR) callconv(.c) c_int;
extern fn fnmatch(
    pattern: [*:0]const u8,
    value: [*:0]const u8,
    flags: c_int,
) callconv(.c) c_int;
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*FILE;
extern fn fdopen(fd: c_int, mode: [*:0]const u8) callconv(.c) ?*FILE;
extern fn fclose(stream: *FILE) callconv(.c) c_int;
extern fn fdopendir(fd: c_int) callconv(.c) ?*DIR;
extern fn getline(
    line: *?[*]u8,
    capacity: *usize,
    stream: *FILE,
) callconv(.c) isize;
extern fn strerror(value: c_int) callconv(.c) [*:0]const u8;

const Ops = struct {
    context: ?*anyopaque = null,
    allocate_memory: *const fn (
        context: ?*anyopaque,
        count: usize,
        size: usize,
        output: *?*anyopaque,
    ) u32,
    allocate_string: *const fn (
        context: ?*anyopaque,
        source: ?[*:0]const u8,
        output: *?[*:0]u8,
    ) u32,
};

fn productionAllocateMemory(
    _: ?*anyopaque,
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32 {
    return TDNFAllocateMemory(count, size, output);
}

fn productionAllocateString(
    _: ?*anyopaque,
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    return TDNFAllocateString(source, output);
}

const production_ops = Ops{
    .allocate_memory = productionAllocateMemory,
    .allocate_string = productionAllocateString,
};

const Production = if (builtin.is_test) struct {
    fn getVersion() [*:0]const u8 {
        return "test-version";
    }

    fn getReleaseVersionConfig(
        _: ?*const anyopaque,
        _: ?[*:0]const u8,
        version: *?[*:0]u8,
    ) u32 {
        version.* = null;
        return errors.ERROR_TDNF_NO_DISTROVERPKG;
    }

    fn getKernelArch(output: *?[*:0]u8) u32 {
        return TDNFAllocateString("test-kernel-arch", output);
    }
} else struct {
    extern fn TDNFGetVersion() callconv(.c) [*:0]const u8;
    extern fn TdnfGetReleaseVersionConfig(
        rpm_config: ?*const anyopaque,
        package: ?[*:0]const u8,
        version: *?[*:0]u8,
    ) callconv(.c) u32;
    extern fn TDNFGetKernelArch(output: *?[*:0]u8) callconv(.c) u32;

    fn getVersion() [*:0]const u8 {
        return TDNFGetVersion();
    }

    fn getReleaseVersionConfig(
        rpm_config: ?*const anyopaque,
        package: ?[*:0]const u8,
        version: *?[*:0]u8,
    ) u32 {
        return TdnfGetReleaseVersionConfig(rpm_config, package, version);
    }

    fn getKernelArch(output: *?[*:0]u8) u32 {
        return TDNFGetKernelArch(output);
    }
};

pub const RpmTransFlagMapEntry = extern struct {
    name: ?[*:0]const u8,
    flag: u32,
    nCompatibilityNoOp: c_int,
};

pub export var rpmtransflags_map = [_]RpmTransFlagMapEntry{
    .{ .name = "noscripts", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOSCRIPTS, .nCompatibilityNoOp = 0 },
    .{ .name = "justdb", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_JUSTDB, .nCompatibilityNoOp = 0 },
    .{ .name = "notriggers", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOTRIGGERS, .nCompatibilityNoOp = 0 },
    .{ .name = "nodocs", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NODOCS, .nCompatibilityNoOp = 0 },
    .{ .name = "allfiles", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_ALLFILES, .nCompatibilityNoOp = 1 },
    .{ .name = "noplugins", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOPLUGINS, .nCompatibilityNoOp = 1 },
    .{ .name = "nocontexts", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOCONTEXTS, .nCompatibilityNoOp = 1 },
    .{ .name = "nocaps", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOCAPS, .nCompatibilityNoOp = 0 },
    .{ .name = "nodb", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NODB, .nCompatibilityNoOp = 0 },
    .{ .name = "notriggerprein", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOTRIGGERPREIN, .nCompatibilityNoOp = 1 },
    .{ .name = "nopre", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOPRE, .nCompatibilityNoOp = 0 },
    .{ .name = "nopost", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOPOST, .nCompatibilityNoOp = 0 },
    .{ .name = "notriggerin", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOTRIGGERIN, .nCompatibilityNoOp = 0 },
    .{ .name = "notriggerun", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOTRIGGERUN, .nCompatibilityNoOp = 0 },
    .{ .name = "nopreun", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOPREUN, .nCompatibilityNoOp = 0 },
    .{ .name = "nopostun", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOPOSTUN, .nCompatibilityNoOp = 0 },
    .{ .name = "notriggerpostun", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOTRIGGERPOSTUN, .nCompatibilityNoOp = 0 },
    .{ .name = "nopretrans", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOPRETRANS, .nCompatibilityNoOp = 0 },
    .{ .name = "noposttrans", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOPOSTTRANS, .nCompatibilityNoOp = 0 },
    .{ .name = "nomd5", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOMD5, .nCompatibilityNoOp = 1 },
    .{ .name = "nofiledigest", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOFILEDIGEST, .nCompatibilityNoOp = 1 },
    .{ .name = "noartifacts", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOARTIFACTS, .nCompatibilityNoOp = 1 },
    .{ .name = "noconfigs", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NOCONFIGS, .nCompatibilityNoOp = 0 },
    .{ .name = "deploops", .flag = rpmtrans.TDNF_RPMTRANS_FLAG_DEPLOOPS, .nCompatibilityNoOp = 1 },
    .{ .name = null, .flag = rpmtrans.TDNF_RPMTRANS_FLAG_NONE, .nCompatibilityNoOp = 0 },
};

fn freeString(value: *?[*:0]u8) void {
    if (value.*) |pointer| TDNFFreeMemory(@ptrCast(pointer));
    value.* = null;
}

fn replaceString(
    slot: *?[*:0]u8,
    source: ?[*:0]const u8,
    ops: Ops,
) u32 {
    freeString(slot);
    if (source == null) return 0;
    return ops.allocate_string(ops.context, source, slot);
}

fn allocateFormatted(
    output: *?[*:0]u8,
    comptime format: []const u8,
    args: anytype,
    ops: Ops,
) u32 {
    output.* = null;
    const length = std.fmt.count(format, args);
    var raw: ?*anyopaque = null;
    const result = ops.allocate_memory(ops.context, length + 1, 1, &raw);
    if (result != 0) return result;

    const bytes: [*]u8 = @ptrCast(raw.?);
    _ = std.fmt.bufPrint(bytes[0..length], format, args) catch unreachable;
    bytes[length] = 0;
    output.* = @ptrCast(bytes);
    return 0;
}

fn allocateSlice(output: *?[*:0]u8, value: []const u8, ops: Ops) u32 {
    output.* = null;
    var raw: ?*anyopaque = null;
    const result = ops.allocate_memory(ops.context, value.len + 1, 1, &raw);
    if (result != 0) return result;
    const bytes: [*]u8 = @ptrCast(raw.?);
    @memcpy(bytes[0..value.len], value);
    bytes[value.len] = 0;
    output.* = @ptrCast(bytes);
    return 0;
}

fn replaceSlice(slot: *?[*:0]u8, value: []const u8, ops: Ops) u32 {
    freeString(slot);
    return allocateSlice(slot, value, ops);
}

fn replaceSplit(
    slot: *?[*]?[*:0]u8,
    value: [*:0]const u8,
) u32 {
    if (slot.*) |old| TDNFFreeStringArray(old);
    slot.* = null;
    return TDNFSplitStringToArray(value, " ", slot);
}

fn joinPath(
    output: *?[*:0]u8,
    first: [*:0]const u8,
    second: [*:0]const u8,
) u32 {
    var nodes = [_]?[*:0]u8{
        @constCast(first),
        @constCast(second),
    };
    return TDNFJoinPathFromArray(output, &nodes, nodes.len);
}

fn parseOsInfo(conf: *Conf, path: [*:0]const u8, ops: Ops) u32 {
    const stream = fopen(path, "r") orelse {
        common.log(LOG_NOTICE, "Warning: '%s' file is not present in the system\n", .{path});
        return 0;
    };
    defer _ = fclose(stream);
    return parseOsInfoStream(conf, stream, ops);
}

fn parseOsInfoStream(conf: *Conf, stream: *FILE, ops: Ops) u32 {
    var raw: ?*anyopaque = null;
    var result = ops.allocate_memory(ops.context, 1, 256, &raw);
    if (result != 0) return result;

    var line: ?[*]u8 = @ptrCast(raw.?);
    defer if (line) |value| TDNFFreeMemory(@ptrCast(value));
    var capacity: usize = 256;
    var name: ?[*:0]u8 = null;
    defer freeString(&name);
    var version: ?[*:0]u8 = null;
    defer freeString(&version);

    while (getline(&line, &capacity, stream) >= 0) {
        const bytes = std.mem.sliceTo(line.?, 0);
        const trimmed = std.mem.trimEnd(u8, bytes, "\n");
        for ([_][]const u8{ "ID", "VERSION_ID" }) |key| {
            if (trimmed.len <= key.len or
                !std.mem.eql(u8, trimmed[0..key.len], key) or
                trimmed[key.len] != '=')
            {
                continue;
            }
            var value = trimmed[key.len + 1 ..];
            if (value.len > 0 and value[0] == '"') {
                value = value[1..];
                const quote = std.mem.lastIndexOfScalar(u8, value, '"') orelse
                    continue;
                value = value[0..quote];
            }

            var value_buffer: [*:0]const u8 = undefined;
            const end: [*]u8 = @constCast(value.ptr) + value.len;
            const saved = end[0];
            end[0] = 0;
            value_buffer = @ptrCast(@constCast(value.ptr));
            defer end[0] = saved;

            if (std.mem.eql(u8, key, "ID")) {
                freeString(&name);
                result = ops.allocate_string(ops.context, value_buffer, &name);
            } else {
                freeString(&version);
                result = ops.allocate_string(ops.context, value_buffer, &version);
            }
            if (result != 0) return result;
        }
    }

    conf.pszOSName = name;
    name = null;
    conf.pszOSVersion = version;
    version = null;
    return 0;
}

fn parseTransFlags(conf: *Conf, value: [*:0]const u8) u32 {
    const text = std.mem.span(value);
    if (text.len == 0) {
        conf.rpmTransFlags = 0;
        return 0;
    }

    var tokens = std.mem.tokenizeScalar(u8, text, ' ');
    while (tokens.next()) |token| {
        var found: ?*const RpmTransFlagMapEntry = null;
        for (&rpmtransflags_map) |*entry| {
            const name = entry.name orelse break;
            if (std.mem.eql(u8, token, std.mem.span(name))) {
                found = entry;
                break;
            }
        }
        const entry = found orelse {
            common.log(LOG_ERR, "unknown tsflag '%.*s'\n", .{ @as(c_int, @intCast(token.len)), token.ptr });
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        };
        conf.rpmTransFlags |= entry.flag;
        if (entry.nCompatibilityNoOp != 0) {
            common.log(LOG_INFO, "tsflag '%.*s' is a recognized compatibility no-op in the native transaction engine\n", .{ @as(c_int, @intCast(token.len)), token.ptr });
        }
    }
    return 0;
}

fn configFromTree(conf: *Conf, top: ?*CnfNode, ops: Ops) u32 {
    const root = top orelse return 0;
    var proxy_user: ?[*:0]const u8 = null;
    var proxy_pass: ?[*:0]const u8 = null;
    var node = root.first_child;

    while (node) |current| : (node = current.next) {
        const name_ptr = current.name orelse continue;
        const value = current.value orelse continue;
        const name = std.mem.span(name_ptr);
        if (name.len == 0 or name[0] == '.') continue;

        var result: u32 = 0;
        if (std.mem.eql(u8, name, "installonly_limit")) {
            conf.nInstallOnlyLimit = strtoi(value);
        } else if (std.mem.eql(u8, name, "clean_requirements_on_remove")) {
            conf.nCleanRequirementsOnRemove = isTrue(value);
        } else if (std.mem.eql(u8, name, "gpgcheck")) {
            conf.nGPGCheck = isTrue(value);
        } else if (std.mem.eql(u8, name, "cligpgcheck")) {
            conf.nCliGPGCheck = isTrue(value);
        } else if (std.mem.eql(u8, name, "connect_timeout")) {
            conf.nConnectTimeout = strtoi(value);
        } else if (std.mem.eql(u8, name, "sslverify")) {
            conf.nSSLVerify = isTrue(value);
        } else if (std.mem.eql(u8, name, "keepcache")) {
            conf.nKeepCache = isTrue(value);
        } else if (std.mem.eql(u8, name, "reposdir") or
            std.mem.eql(u8, name, "repodir"))
        {
            result = replaceString(&conf.pszRepoDir, value, ops);
        } else if (std.mem.eql(u8, name, "cachedir")) {
            result = replaceString(&conf.pszCacheDir, value, ops);
        } else if (std.mem.eql(u8, name, "persistdir")) {
            result = replaceString(&conf.pszPersistDir, value, ops);
        } else if (std.mem.eql(u8, name, "distroverpkg")) {
            result = replaceSplit(&conf.ppszDistroVerPkgs, value);
        } else if (std.mem.eql(u8, name, "excludepkgs")) {
            result = TDNFAddStringArray(&conf.ppszExcludes, value);
        } else if (std.mem.eql(u8, name, "minversions")) {
            result = TDNFAddStringArray(&conf.ppszMinVersions, value);
        } else if (std.mem.eql(u8, name, "openmax")) {
            conf.nOpenMax = strtoi(value);
        } else if (std.mem.eql(u8, name, "dnf_check_update_compat")) {
            conf.nCheckUpdateCompat = isTrue(value);
        } else if (std.mem.eql(u8, name, "distrosync_reinstall_changed")) {
            conf.nDistroSyncReinstallChanged = isTrue(value);
        } else if (std.mem.eql(u8, name, "proxy")) {
            result = replaceString(&conf.pszProxy, value, ops);
        } else if (std.mem.eql(u8, name, "proxy_username")) {
            proxy_user = value;
        } else if (std.mem.eql(u8, name, "proxy_password")) {
            proxy_pass = value;
        } else if (std.mem.eql(u8, name, "installonlypkgs")) {
            result = TDNFAddStringArray(&conf.ppszInstallOnlyPkgs, value);
        } else if (std.mem.eql(u8, name, "varsdir")) {
            result = replaceSplit(&conf.ppszVarsDirs, value);
        } else if (std.mem.eql(u8, name, "plugins")) {
            conf.nPluginsEnabled = isTrue(value);
        } else if (std.mem.eql(u8, name, "pluginconfpath")) {
            result = replaceString(&conf.pszPluginConfPath, value, ops);
        } else if (std.mem.eql(u8, name, "pluginpath")) {
            result = replaceString(&conf.pszPluginPath, value, ops);
        } else if (std.mem.eql(u8, name, "tsflags")) {
            result = parseTransFlags(conf, value);
        }
        if (result != 0) return result;
    }

    if (proxy_user != null and proxy_pass != null) {
        freeString(&conf.pszProxyUserPass);
        return allocateFormatted(
            &conf.pszProxyUserPass,
            "{s}:{s}",
            .{ std.mem.span(proxy_user.?), std.mem.span(proxy_pass.?) },
            ops,
        );
    }
    return 0;
}

fn nativeConfig(handle: *Tdnf) ?*txn_config.TxnConfig {
    return @ptrCast(@alignCast(handle.pRpmConfig orelse return null));
}

fn targetPathError(err: txn_config.TargetPathError) u32 {
    return switch (err) {
        error.NotFound => errors.ERROR_TDNF_FILE_NOT_FOUND,
        error.InvalidTargetPath, error.UnsafeTargetPath => errors.ERROR_TDNF_INVALID_PARAMETER,
        error.SyscallFailed => errors.ERROR_TDNF_SYSTEM_BASE +
            @as(u32, @intCast(std.c._errno().*)),
    };
}

fn parsePinnedIni(
    config: *const txn_config.TxnConfig,
    module: *CnfModule,
    path: []const u8,
) union(enum) { tree: *CnfNode, status: u32 } {
    const fd = config.openPinnedRegular(path) catch |err|
        return .{ .status = targetPathError(err) };
    const stream = fdopen(fd, "r") orelse {
        _ = std.c.close(fd);
        return .{ .status = errors.ERROR_TDNF_SYSTEM_BASE +
            @as(u32, @intCast(std.c._errno().*)) };
    };
    defer _ = fclose(stream);
    const tree = cnfmodule_parse(module, stream) orelse
        return .{ .status = errors.ERROR_TDNF_CONF_FILE_LOAD };
    return .{ .tree = tree };
}

fn parsePinnedOsInfo(
    config: *const txn_config.TxnConfig,
    conf: *Conf,
    ops: Ops,
) u32 {
    const fd = config.openPinnedRegular(OS_REL_FILE) catch |err| {
        if (err == error.NotFound) {
            common.log(
                LOG_NOTICE,
                "Warning: '%s' file is not present in the target\n",
                .{OS_REL_FILE},
            );
            return 0;
        }
        return targetPathError(err);
    };
    const stream = fdopen(fd, "r") orelse {
        _ = std.c.close(fd);
        return errors.ERROR_TDNF_SYSTEM_BASE +
            @as(u32, @intCast(std.c._errno().*));
    };
    defer _ = fclose(stream);
    return parseOsInfoStream(conf, stream, ops);
}

fn readFdToStringArray(fd: c_int, lines: *?[*]?[*:0]u8) u32 {
    const stream = fdopen(fd, "r") orelse {
        _ = std.c.close(fd);
        return errors.ERROR_TDNF_SYSTEM_BASE +
            @as(u32, @intCast(std.c._errno().*));
    };
    defer _ = fclose(stream);
    var line: ?[*]u8 = null;
    defer if (line) |value| std.c.free(value);
    var capacity: usize = 0;
    while (getline(&line, &capacity, stream) >= 0) {
        const raw = std.mem.sliceTo(line.?, 0);
        const value = std.mem.trimEnd(u8, raw, "\r\n");
        const value_z = std.heap.c_allocator.dupeZ(u8, value) catch
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        defer std.heap.c_allocator.free(value_z);
        const result = TDNFAddStringArray(lines, value_z.ptr);
        if (result != 0) return result;
    }
    return 0;
}

fn readConfFilesFromPinnedDir(
    config: *const txn_config.TxnConfig,
    path: []const u8,
    lines: *?[*]?[*:0]u8,
) u32 {
    const directory_fd = config.openPinnedDirectory(
        path,
        false,
    ) catch |err| {
        if (err == error.NotFound) return 0;
        return targetPathError(err);
    };
    const scan_fd = std.c.fcntl(
        directory_fd,
        std.c.F.DUPFD_CLOEXEC,
        @as(c_int, 0),
    );
    if (scan_fd < 0) {
        _ = std.c.close(directory_fd);
        return errors.ERROR_TDNF_SYSTEM_BASE +
            @as(u32, @intCast(std.c._errno().*));
    }
    const directory = fdopendir(scan_fd) orelse {
        const saved = std.c._errno().*;
        _ = std.c.close(scan_fd);
        _ = std.c.close(directory_fd);
        return errors.ERROR_TDNF_SYSTEM_BASE +
            @as(u32, @intCast(saved));
    };
    defer _ = closedir(directory);
    defer _ = std.c.close(directory_fd);

    while (readdir(directory)) |entry| {
        const name: [*:0]const u8 = @ptrCast(&entry.name);
        if (fnmatch("*.conf", name, 0) != 0) continue;
        const fd = std.c.openat(directory_fd, name, .{
            .ACCMODE = .RDONLY,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (fd < 0) {
            if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
                continue;
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        }
        var stat = std.mem.zeroes(std.os.linux.Statx);
        if (std.c.statx(
            fd,
            "",
            std.os.linux.AT.EMPTY_PATH,
            std.os.linux.STATX.BASIC_STATS,
            &stat,
        ) != 0 or (stat.mode & 0o170000) != 0o100000 or stat.nlink != 1) {
            _ = std.c.close(fd);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        }
        const result = readFdToStringArray(fd, lines);
        if (result != 0) return result;
    }
    return 0;
}

fn readConfFilesFromDir(path: [*:0]const u8, lines: *?[*]?[*:0]u8) u32 {
    var dir = opendir(path) orelse return 0;
    var file_count: usize = 0;
    while (readdir(dir)) |entry| {
        if (fnmatch("*.conf", @ptrCast(&entry.name), 0) == 0) file_count += 1;
    }
    _ = closedir(dir);

    var raw_lists: ?*anyopaque = null;
    var result = TDNFAllocateMemory(
        file_count + 2,
        @sizeOf(?[*]?[*:0]u8),
        &raw_lists,
    );
    if (result != 0) return result;
    const lists: [*]?[*]?[*:0]u8 = @ptrCast(@alignCast(raw_lists.?));
    defer TDNFFreeMemory(raw_lists);

    dir = opendir(path) orelse
        return errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(std.c._errno().*));
    defer _ = closedir(dir);
    var loaded: usize = 0;
    defer {
        var i: usize = 0;
        while (i < loaded) : (i += 1) {
            if (lists[i]) |values| TDNFFreeStringArray(values);
        }
    }

    while (readdir(dir)) |entry| {
        if (loaded == file_count) break;
        if (fnmatch("*.conf", @ptrCast(&entry.name), 0) != 0) continue;

        var file_path: ?[*:0]u8 = null;
        result = joinPath(&file_path, path, @ptrCast(&entry.name));
        if (result != 0) return result;
        defer freeString(&file_path);

        result = TDNFReadFileToStringArray(file_path, &lists[loaded]);
        if (result != 0) return result;
        loaded += 1;
    }
    lists[loaded] = lines.*;

    var line_count: usize = 0;
    var list_index: usize = 0;
    while (lists[list_index]) |values| : (list_index += 1) {
        var count: c_int = 0;
        result = TDNFStringArrayCount(values, &count);
        if (result != 0) return result;
        line_count += @intCast(count);
    }

    var raw_new: ?*anyopaque = null;
    result = TDNFAllocateMemory(
        line_count + 1,
        @sizeOf(?[*:0]u8),
        &raw_new,
    );
    if (result != 0) return result;
    const new_lines: [*]?[*:0]u8 = @ptrCast(@alignCast(raw_new.?));

    var output_index: usize = 0;
    list_index = 0;
    while (lists[list_index]) |values| : (list_index += 1) {
        var value_index: usize = 0;
        while (values[value_index]) |value| : (value_index += 1) {
            new_lines[output_index] = value;
            output_index += 1;
        }
        TDNFFreeMemory(@ptrCast(values));
        lists[list_index] = null;
    }
    new_lines[output_index] = null;
    lines.* = new_lines;
    return 0;
}

fn freeConfig(conf: ?*Conf) void {
    const value = conf orelse return;
    freeString(&value.pszProxy);
    freeString(&value.pszProxyUserPass);
    freeString(&value.pszRepoDir);
    freeString(&value.pszCacheDir);
    freeString(&value.pszPersistDir);
    if (value.ppszDistroVerPkgs) |items| TDNFFreeStringArray(items);
    freeString(&value.pszVarReleaseVer);
    freeString(&value.pszVarBaseArch);
    freeString(&value.pszBaseArch);
    freeString(&value.pszUserAgentHeader);
    freeString(&value.pszOSName);
    freeString(&value.pszOSVersion);
    freeString(&value.pszPluginPath);
    freeString(&value.pszPluginConfPath);
    if (value.ppszExcludes) |items| TDNFFreeStringArray(items);
    if (value.ppszMinVersions) |items| TDNFFreeStringArray(items);
    if (value.ppszPkgLocks) |items| TDNFFreeStringArray(items);
    if (value.ppszProtectedPkgs) |items| TDNFFreeStringArray(items);
    if (value.ppszInstallOnlyPkgs) |items| TDNFFreeStringArray(items);
    if (value.ppszVarsDirs) |items| TDNFFreeStringArray(items);
    TDNFFreeMemory(value);
}

fn readConfigMode(
    handle_opt: ?*Tdnf,
    config_path_opt: ?[*:0]const u8,
    group_opt: ?[*:0]const u8,
    pinned_source: bool,
    ops: Ops,
) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const config_path = config_path_opt orelse {
        freeConfig(handle.pConf);
        handle.pConf = null;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (config_path[0] == 0 or group_opt == null or group_opt.?[0] == 0 or
        handle.pArgs == null)
    {
        freeConfig(handle.pConf);
        handle.pConf = null;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    const previous = handle.pConf;
    handle.pConf = null;

    var raw_conf: ?*anyopaque = null;
    var result = ops.allocate_memory(
        ops.context,
        1,
        @sizeOf(Conf),
        &raw_conf,
    );
    if (result != 0) {
        freeConfig(previous);
        return result;
    }
    const conf: *Conf = @ptrCast(@alignCast(raw_conf.?));

    conf.nCliGPGCheck = -1;
    conf.nOpenMax = 1024;
    conf.nInstallOnlyLimit = 2;
    conf.nSSLVerify = 1;

    register_ini(null);
    const module = find_cnfmodule("ini") orelse {
        freeConfig(previous);
        freeConfig(conf);
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    const tree = if (pinned_source) blk: {
        const config = nativeConfig(handle) orelse {
            freeConfig(previous);
            freeConfig(conf);
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        };
        switch (parsePinnedIni(
            config,
            module,
            std.mem.span(config_path),
        )) {
            .tree => |tree| break :blk tree,
            .status => |status| {
                freeConfig(previous);
                freeConfig(conf);
                return status;
            },
        }
    } else cnfmodule_parse_file(module, config_path) orelse {
        const errno_value = std.c._errno().*;
        freeConfig(previous);
        freeConfig(conf);
        return if (errno_value != 0)
            errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(errno_value))
        else
            errors.ERROR_TDNF_CONF_FILE_LOAD;
    };
    defer destroy_cnftree(tree);

    const args = handle.pArgs.?;
    const pinned_config = nativeConfig(handle);
    result = if (pinned_config != null and
        pinned_config.?.pinnedInstallRootFd() != null)
        parsePinnedOsInfo(pinned_config.?, conf, ops)
    else blk: {
        var os_path: ?[*:0]u8 = null;
        defer freeString(&os_path);
        if (args.pszInstallRoot) |root| {
            if (root[0] != 0 and !std.mem.eql(u8, std.mem.span(root), "/")) {
                const join_result = joinPath(&os_path, root, OS_REL_FILE);
                if (join_result != 0) break :blk join_result;
            }
        }
        break :blk parseOsInfo(conf, os_path orelse OS_REL_FILE, ops);
    };
    if (result != 0) {
        freeConfig(previous);
        freeConfig(conf);
        return result;
    }

    result = configFromTree(conf, if (tree.first_child) |section| section else null, ops);
    if (result != 0) {
        freeConfig(previous);
        freeConfig(conf);
        return result;
    }

    if (args.nNoGPGCheck != 0) conf.nGPGCheck = 0;
    if (args.nSkipDigest != 0) conf.nSkipDigest = 1;
    if (args.nSkipSignature != 0) conf.nSkipSignature = 1;

    if (conf.pszRepoDir == null) {
        result = replaceString(&conf.pszRepoDir, DEFAULT_REPO_LOCATION, ops);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }
    if (conf.pszCacheDir == null) {
        result = replaceString(&conf.pszCacheDir, DEFAULT_CACHE_LOCATION, ops);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }

    if (pinned_config) |config| {
        if (config.pinnedInstallRootFd() != null) {
            const cache_dir = std.mem.span(conf.pszCacheDir.?);
            if (cache_dir.len == 0 or cache_dir[0] != '/') {
                freeConfig(previous);
                freeConfig(conf);
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            }
            const cache_fd = config.openPinnedDirectory(
                cache_dir,
                true,
            ) catch |err| {
                freeConfig(previous);
                freeConfig(conf);
                return targetPathError(err);
            };
            defer _ = std.c.close(cache_fd);
            config.repinCacheDir(cache_dir, cache_fd) catch |err| {
                freeConfig(previous);
                freeConfig(conf);
                return switch (err) {
                    error.OutOfMemory => errors.ERROR_TDNF_OUT_OF_MEMORY,
                    else => errors.ERROR_TDNF_INVALID_PARAMETER,
                };
            };

            const repo_dir = std.mem.span(conf.pszRepoDir.?);
            const target_repo = blk: {
                const fd = config.openPinnedDirectory(
                    repo_dir,
                    false,
                ) catch |err| switch (err) {
                    error.NotFound => break :blk pinned_source,
                    else => {
                        freeConfig(previous);
                        freeConfig(conf);
                        return targetPathError(err);
                    },
                };
                _ = std.c.close(fd);
                break :blk true;
            };
            if (target_repo) {
                config.setPinnedRepoDir(repo_dir) catch {
                    freeConfig(previous);
                    freeConfig(conf);
                    return errors.ERROR_TDNF_OUT_OF_MEMORY;
                };
            }
        } else if (args.pszInstallRoot) |root| {
            if (root[0] != 0 and !std.mem.eql(u8, std.mem.span(root), "/")) {
                var rooted_cache: ?[*:0]u8 = null;
                result = joinPath(&rooted_cache, root, conf.pszCacheDir.?);
                if (result != 0) {
                    freeConfig(previous);
                    freeConfig(conf);
                    return result;
                }
                freeString(&conf.pszCacheDir);
                conf.pszCacheDir = rooted_cache;

                var rooted_repo: ?[*:0]u8 = null;
                defer freeString(&rooted_repo);
                result = joinPath(&rooted_repo, root, conf.pszRepoDir.?);
                if (result != 0) {
                    freeConfig(previous);
                    freeConfig(conf);
                    return result;
                }
                var is_dir: c_int = 0;
                result = TDNFIsDir(rooted_repo, &is_dir);
                if (result == errors.ERROR_TDNF_FILE_NOT_FOUND) {
                    result = 0;
                    is_dir = 0;
                }
                if (result != 0) {
                    freeConfig(previous);
                    freeConfig(conf);
                    return result;
                }
                if (is_dir != 0) {
                    freeString(&conf.pszRepoDir);
                    conf.pszRepoDir = rooted_repo;
                    rooted_repo = null;
                }
            }
        }
    } else if (args.pszInstallRoot) |root| {
        if (root[0] != 0 and !std.mem.eql(u8, std.mem.span(root), "/")) {
            var rooted_cache: ?[*:0]u8 = null;
            result = joinPath(&rooted_cache, root, conf.pszCacheDir.?);
            if (result != 0) {
                freeConfig(previous);
                freeConfig(conf);
                return result;
            }
            freeString(&conf.pszCacheDir);
            conf.pszCacheDir = rooted_cache;

            var rooted_repo: ?[*:0]u8 = null;
            defer freeString(&rooted_repo);
            result = joinPath(&rooted_repo, root, conf.pszRepoDir.?);
            if (result != 0) {
                freeConfig(previous);
                freeConfig(conf);
                return result;
            }
            var is_dir: c_int = 0;
            result = TDNFIsDir(rooted_repo, &is_dir);
            if (result == errors.ERROR_TDNF_FILE_NOT_FOUND) {
                result = 0;
                is_dir = 0;
            }
            if (result != 0) {
                freeConfig(previous);
                freeConfig(conf);
                return result;
            }
            if (is_dir != 0) {
                freeString(&conf.pszRepoDir);
                conf.pszRepoDir = rooted_repo;
                rooted_repo = null;
            }
        }
    }

    if (args.cn_setopts) |setopts| {
        result = configFromTree(conf, setopts, ops);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }

    if (pinned_config) |config| {
        if (config.pinnedInstallRootFd() != null) {
            const cache_dir = std.mem.span(conf.pszCacheDir.?);
            if (cache_dir.len == 0 or cache_dir[0] != '/') {
                freeConfig(previous);
                freeConfig(conf);
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            }
            if (!config.cacheDirUsesPinnedRoot(cache_dir)) {
                const cache_fd = config.openPinnedDirectory(
                    cache_dir,
                    true,
                ) catch |err| {
                    freeConfig(previous);
                    freeConfig(conf);
                    return targetPathError(err);
                };
                defer _ = std.c.close(cache_fd);
                config.repinCacheDir(cache_dir, cache_fd) catch |err| {
                    freeConfig(previous);
                    freeConfig(conf);
                    return switch (err) {
                        error.OutOfMemory => errors.ERROR_TDNF_OUT_OF_MEMORY,
                        else => errors.ERROR_TDNF_INVALID_PARAMETER,
                    };
                };
            }
        }
    }

    if (args.nNoCmdLineGPGCheck != 0) {
        conf.nCliGPGCheck = 0;
    } else if (conf.nCliGPGCheck == -1) {
        conf.nCliGPGCheck = conf.nGPGCheck;
    }

    if (conf.pszOSName == null) {
        result = replaceString(&conf.pszOSName, "UNKNOWN", ops);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }
    if (conf.pszOSVersion == null) {
        result = replaceString(&conf.pszOSVersion, "UNKNOWN", ops);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }
    result = allocateFormatted(
        &conf.pszUserAgentHeader,
        "rpmz/{s} {s}/{s}",
        .{
            std.mem.span(Production.getVersion()),
            std.mem.span(conf.pszOSName.?),
            std.mem.span(conf.pszOSVersion.?),
        },
        ops,
    );
    if (result != 0) {
        freeConfig(previous);
        freeConfig(conf);
        return result;
    }

    if (conf.ppszDistroVerPkgs == null) {
        result = TDNFSplitStringToArray(
            DEFAULT_DISTROVERPKGS,
            " ",
            &conf.ppszDistroVerPkgs,
        );
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }
    if (conf.pszPersistDir == null) {
        result = replaceSlice(&conf.pszPersistDir, options.history_db_dir, ops);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }
    if (conf.ppszVarsDirs == null) {
        result = TDNFSplitStringToArray(DEFAULT_VARS_DIRS, " ", &conf.ppszVarsDirs);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }
    if (conf.pszPluginPath == null) {
        result = allocateFormatted(
            &conf.pszPluginPath,
            "{s}/rpmz-plugins",
            .{options.system_libdir},
            ops,
        );
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }
    if (conf.pszPluginConfPath == null) {
        result = replaceString(&conf.pszPluginConfPath, DEFAULT_PLUGIN_CONF_PATH, ops);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }
    if (pinned_config) |config| {
        if (config.pinnedInstallRootFd() != null) {
            const plugin_dir = std.mem.span(conf.pszPluginConfPath.?);
            const target_plugin = blk: {
                const fd = config.openPinnedDirectory(
                    plugin_dir,
                    false,
                ) catch |err| switch (err) {
                    error.NotFound => break :blk pinned_source,
                    else => {
                        freeConfig(previous);
                        freeConfig(conf);
                        return targetPathError(err);
                    },
                };
                _ = std.c.close(fd);
                break :blk true;
            };
            if (target_plugin) {
                config.setPinnedPluginConfDir(plugin_dir) catch {
                    freeConfig(previous);
                    freeConfig(conf);
                    return errors.ERROR_TDNF_OUT_OF_MEMORY;
                };
            }
        }
    }

    var config_dir: ?[*:0]u8 = null;
    defer freeString(&config_dir);
    result = TDNFDirName(config_path, &config_dir);
    if (result != 0) {
        freeConfig(previous);
        freeConfig(conf);
        return result;
    }

    inline for (.{
        .{ "minversions.d", &conf.ppszMinVersions },
        .{ "locks.d", &conf.ppszPkgLocks },
        .{ "protected.d", &conf.ppszProtectedPkgs },
    }) |directory| {
        var path: ?[*:0]u8 = null;
        result = joinPath(&path, config_dir.?, directory[0]);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
        result = if (pinned_source)
            readConfFilesFromPinnedDir(
                pinned_config.?,
                std.mem.span(path.?),
                directory[1],
            )
        else
            readConfFilesFromDir(path.?, directory[1]);
        freeString(&path);
        if (result != 0) {
            freeConfig(previous);
            freeConfig(conf);
            return result;
        }
    }

    freeConfig(previous);
    handle.pConf = conf;
    return 0;
}

fn readConfig(
    handle: ?*Tdnf,
    config_path: ?[*:0]const u8,
    group: ?[*:0]const u8,
    ops: Ops,
) u32 {
    return readConfigMode(handle, config_path, group, false, ops);
}

export fn TDNFReadConfig(
    handle: ?*Tdnf,
    config_path: ?[*:0]const u8,
    group: ?[*:0]const u8,
) callconv(.c) u32 {
    return readConfig(handle, config_path, group, production_ops);
}

export fn TDNFReadConfigPinned(
    handle: ?*Tdnf,
    config_path: ?[*:0]const u8,
    group: ?[*:0]const u8,
) callconv(.c) u32 {
    return readConfigMode(
        handle,
        config_path,
        group,
        true,
        production_ops,
    );
}

export fn TDNFConfigExpandVars(handle_opt: ?*Tdnf) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const conf = handle.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = handle.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;

    if (conf.pszVarReleaseVer == null and args.pszReleaseVer != null and
        args.pszReleaseVer.?[0] != 0)
    {
        const result = TDNFAllocateString(args.pszReleaseVer, &conf.pszVarReleaseVer);
        if (result != 0) return result;
    }

    if (conf.pszVarReleaseVer == null or args.pszReleaseVer == null or
        args.pszReleaseVer.?[0] == 0)
    {
        var result: u32 = 0;
        var index: usize = 0;
        while (conf.ppszDistroVerPkgs.?[index]) |package| : (index += 1) {
            result = Production.getReleaseVersionConfig(
                handle.pRpmConfig,
                package,
                &conf.pszVarReleaseVer,
            );
            if (result == 0) break;
            if (result != errors.ERROR_TDNF_NO_DISTROVERPKG) return result;
        }
        if (result != 0) return result;
    }

    if (args.pszArch != null and args.pszArch.?[0] != 0) {
        freeString(&conf.pszVarBaseArch);
        const result = TDNFAllocateString(args.pszArch, &conf.pszVarBaseArch);
        if (result != 0) return result;
    }
    if (conf.pszVarBaseArch == null or conf.pszVarBaseArch.?[0] == 0) {
        return Production.getKernelArch(&conf.pszVarBaseArch);
    }
    return 0;
}

export fn TDNFFreeConfig(conf: ?*Conf) callconv(.c) void {
    freeConfig(conf);
}

export fn TDNFConfigReplaceVars(
    handle_opt: ?*Tdnf,
    string_opt: ?*?[*:0]u8,
) callconv(.c) u32 {
    const handle = handle_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const string_slot = string_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const source = string_slot.* orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (source[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const conf = handle.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;

    const config = nativeConfig(handle);
    const vars = if (config != null and
        config.?.pinnedInstallRootFd() != null)
        varsdir.parse_varsdirs_at(
            config.?.pinnedInstallRootFd().?,
            @ptrCast(conf.ppszVarsDirs),
        )
    else
        varsdir.parse_varsdirs(@ptrCast(conf.ppszVarsDirs));
    const vars_root = vars orelse {
        const errno_value = std.c._errno().*;
        common.log(LOG_ERR, "parsing vars failed: %s (%d)\n", .{ strerror(errno_value), errno_value });
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    defer destroy_cnftree(vars_root);

    const release = create_cnfnode("releasever");
    cnfnode_setval(release, conf.pszVarReleaseVer);
    append_node(vars_root, release);
    const arch = create_cnfnode("basearch");
    cnfnode_setval(arch, conf.pszVarBaseArch);
    append_node(vars_root, arch);

    const replaced = varsdir.replace_vars(vars_root, source) orelse {
        common.log(LOG_ERR, "replacing vars in %s failed\n", .{source});
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    TDNFFreeMemory(@ptrCast(source));
    string_slot.* = replaced;
    return 0;
}

const testing = std.testing;

fn expectString(actual: ?[*:0]u8, expected: []const u8) !void {
    try testing.expect(actual != null);
    try testing.expectEqualStrings(expected, std.mem.span(actual.?));
}

fn expectArray(actual: ?[*]?[*:0]u8, expected: []const []const u8) !void {
    const values = actual orelse return error.TestUnexpectedNull;
    for (expected, 0..) |value, index| {
        try expectString(values[index], value);
    }
    try testing.expect(values[expected.len] == null);
}

fn fixturePath(comptime suffix: []const u8) [:0]const u8 {
    return options.source_root ++ "/client/fixtures/config/" ++ suffix;
}

test "configuration layouts match the private cross-module ABI" {
    try testing.expectEqual(@as(usize, 216), @sizeOf(Conf));
    try testing.expectEqual(@as(usize, 56), @offsetOf(Conf, "pszRepoDir"));
    try testing.expectEqual(@as(usize, 96), @offsetOf(Conf, "ppszDistroVerPkgs"));
    try testing.expectEqual(@as(usize, 200), @offsetOf(Conf, "pszPluginPath"));
    try testing.expectEqual(@as(usize, 216), @sizeOf(CmdArgs));
    try testing.expectEqual(@as(usize, 128), @offsetOf(CmdArgs, "pszArch"));
    try testing.expectEqual(@as(usize, 184), @offsetOf(CmdArgs, "cn_setopts"));
    try testing.expectEqual(@as(usize, 144), @sizeOf(Tdnf));
    try testing.expectEqual(@as(usize, 8), @offsetOf(Tdnf, "pArgs"));
    try testing.expectEqual(@as(usize, 16), @offsetOf(Tdnf, "pConf"));
    try testing.expectEqual(
        @as(usize, 120),
        @offsetOf(Tdnf, "pTransactionTargetLock"),
    );
    try testing.expectEqual(@as(usize, 104), @offsetOf(Tdnf, "ppszCmdLinePkgPaths"));
}

test "default configuration uses production defaults without host configuration" {
    var args = CmdArgs{ .pszInstallRoot = @constCast(fixturePath("default-root")) };
    var handle = Tdnf{ .pArgs = &args };
    try testing.expectEqual(
        @as(u32, 0),
        TDNFReadConfig(&handle, fixturePath("default-root/etc/rpmz/rpmz.conf"), "ignored-group"),
    );
    defer TDNFFreeConfig(handle.pConf);
    const conf = handle.pConf.?;

    try testing.expectEqual(@as(c_int, 0), conf.nGPGCheck);
    try testing.expectEqual(@as(c_int, 0), conf.nCliGPGCheck);
    try testing.expectEqual(@as(c_int, 1), conf.nSSLVerify);
    try testing.expectEqual(@as(c_int, 2), conf.nInstallOnlyLimit);
    try testing.expectEqual(@as(c_int, 1024), conf.nOpenMax);
    try expectString(conf.pszRepoDir, DEFAULT_REPO_LOCATION);
    try expectString(
        conf.pszCacheDir,
        fixturePath("default-root/var/cache/tdnf"),
    );
    try expectString(conf.pszPersistDir, options.history_db_dir);
    try expectString(conf.pszPluginPath, DEFAULT_PLUGIN_PATH);
    try expectString(conf.pszPluginConfPath, DEFAULT_PLUGIN_CONF_PATH);
    try expectString(conf.pszOSName, "fixture");
    try expectString(conf.pszOSVersion, "1");
    try expectArray(conf.ppszDistroVerPkgs, &.{
        "system-release(releasever)",
        "system-release",
        "redhat-release",
    });
}

test "complete fixture preserves every config field, rooted paths, and conf fragments" {
    var args = CmdArgs{
        .pszInstallRoot = @constCast(fixturePath("complete-root")),
        .nSkipDigest = 1,
        .nSkipSignature = 1,
    };
    var handle = Tdnf{ .pArgs = &args };
    try testing.expectEqual(
        @as(u32, 0),
        TDNFReadConfig(&handle, fixturePath("complete-root/etc/rpmz/rpmz.conf"), "main"),
    );
    defer TDNFFreeConfig(handle.pConf);
    const conf = handle.pConf.?;

    try testing.expectEqual(@as(c_int, 1), conf.nGPGCheck);
    try testing.expectEqual(@as(c_int, 0), conf.nCliGPGCheck);
    try testing.expectEqual(@as(c_int, 0), conf.nSSLVerify);
    try testing.expectEqual(@as(c_int, 9), conf.nInstallOnlyLimit);
    try testing.expectEqual(@as(c_int, 1), conf.nCleanRequirementsOnRemove);
    try testing.expectEqual(@as(c_int, 1), conf.nKeepCache);
    try testing.expectEqual(@as(c_int, 4096), conf.nOpenMax);
    try testing.expectEqual(@as(c_int, 1), conf.nCheckUpdateCompat);
    try testing.expectEqual(@as(c_int, 1), conf.nDistroSyncReinstallChanged);
    try testing.expectEqual(@as(c_int, 15), conf.nConnectTimeout);
    try testing.expectEqual(@as(c_int, 1), conf.nPluginsEnabled);
    try testing.expectEqual(@as(c_int, 1), conf.nSkipDigest);
    try testing.expectEqual(@as(c_int, 1), conf.nSkipSignature);
    try testing.expectEqual(@as(u32, 0x400a000c), conf.rpmTransFlags);
    try expectString(
        conf.pszRepoDir,
        fixturePath("complete-root/etc/custom.repos.d"),
    );
    try expectString(
        conf.pszCacheDir,
        fixturePath("complete-root/var/cache/custom"),
    );
    try expectString(conf.pszPersistDir, "/var/lib/custom");
    try expectString(conf.pszProxy, "https://proxy.example.test:8443");
    try expectString(conf.pszProxyUserPass, "alice:secret");
    try expectString(conf.pszPluginPath, "/plugins");
    try expectString(conf.pszPluginConfPath, "/pluginconf");
    try expectString(conf.pszOSName, "complete-os");
    try expectString(conf.pszOSVersion, "42");
    try expectArray(conf.ppszDistroVerPkgs, &.{ "release-a", "release-b" });
    try expectArray(conf.ppszExcludes, &.{ "bad-a", "bad-b" });
    try expectArray(conf.ppszMinVersions, &.{ "fragment-a>=2", "fragment-b>=3", "inline>=1" });
    try expectArray(conf.ppszPkgLocks, &.{ "locked-a", "locked-b" });
    try expectArray(conf.ppszProtectedPkgs, &.{ "protected-a", "protected-b" });
    try expectArray(conf.ppszInstallOnlyPkgs, &.{ "kernel", "kernel-core" });
    try expectArray(conf.ppszVarsDirs, &.{ "/vars/a", "/vars/b" });
}

test "setopts apply after install-root handling and replace owned values" {
    const setopts = create_cnfnode("(setopts)") orelse return error.TestUnexpectedNull;
    defer destroy_cnftree(setopts);
    inline for (.{
        .{ "gpgcheck", "false" },
        .{ "cachedir", "/cli-cache" },
        .{ "excludepkgs", "" },
        .{ "tsflags", "" },
        .{ "proxy_username", "cli-user" },
        .{ "proxy_password", "cli-pass" },
    }) |entry| {
        const node = create_cnfnode(entry[0]) orelse return error.TestUnexpectedNull;
        cnfnode_setval(node, entry[1]);
        append_node(setopts, node);
    }

    var args = CmdArgs{
        .pszInstallRoot = @constCast(fixturePath("complete-root")),
        .cn_setopts = setopts,
    };
    var handle = Tdnf{ .pArgs = &args };
    try testing.expectEqual(
        @as(u32, 0),
        TDNFReadConfig(&handle, fixturePath("complete-root/etc/rpmz/rpmz.conf"), "main"),
    );
    defer TDNFFreeConfig(handle.pConf);
    const conf = handle.pConf.?;
    try testing.expectEqual(@as(c_int, 0), conf.nGPGCheck);
    try testing.expectEqual(@as(u32, 0), conf.rpmTransFlags);
    try expectString(conf.pszCacheDir, "/cli-cache");
    try expectString(conf.pszProxyUserPass, "cli-user:cli-pass");
    try testing.expect(conf.ppszExcludes == null);
}

test "missing install-root os-release uses UNKNOWN without reading host state" {
    var args = CmdArgs{ .pszInstallRoot = @constCast(fixturePath("missing-os-root")) };
    var handle = Tdnf{ .pArgs = &args };
    try testing.expectEqual(
        @as(u32, 0),
        TDNFReadConfig(
            &handle,
            fixturePath("missing-os-root/etc/rpmz/rpmz.conf"),
            "main",
        ),
    );
    defer TDNFFreeConfig(handle.pConf);
    try expectString(handle.pConf.?.pszOSName, "UNKNOWN");
    try expectString(handle.pConf.?.pszOSVersion, "UNKNOWN");
}

test "pinned config and os-release survive root replacement" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/etc/rpmz");
    try tmp.dir.createDirPath(std.testing.io, "root/repos");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/etc/rpmz/rpmz.conf",
        .data =
        \\[main]
        \\gpgcheck=1
        \\plugins=0
        \\repodir=/repos
        \\cachedir=/cache
        \\persistdir=/persist
        \\varsdir=
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/etc/os-release",
        .data = "ID=pinned\nVERSION_ID=1\n",
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
    const parked = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "parked" },
    );
    defer std.testing.allocator.free(parked);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const parked_z = try std.testing.allocator.dupeZ(u8, parked);
    defer std.testing.allocator.free(parked_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    var base_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer base_config.deinit();
    var pinned = try base_config.cloneWithPinnedInstallRootDeferredRpmDb(
        std.testing.allocator,
        root,
        root_fd,
    );
    defer pinned.deinit();

    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.rename(root_z.ptr, parked_z.ptr),
    );
    try tmp.dir.createDirPath(std.testing.io, "root/etc/rpmz");
    try tmp.dir.createDirPath(std.testing.io, "root/repos");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/etc/rpmz/rpmz.conf",
        .data = "[main]\ngpgcheck=0\nplugins=0\ncachedir=/cache\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/etc/os-release",
        .data = "ID=replacement\nVERSION_ID=9\n",
    });

    var args = CmdArgs{ .pszInstallRoot = root_z.ptr };
    var handle = Tdnf{
        .pArgs = &args,
        .pRpmConfig = @ptrCast(&pinned),
    };
    try testing.expectEqual(
        @as(u32, 0),
        TDNFReadConfigPinned(
            &handle,
            "/etc/rpmz/rpmz.conf",
            "main",
        ),
    );
    defer TDNFFreeConfig(handle.pConf);
    try testing.expectEqual(@as(c_int, 1), handle.pConf.?.nGPGCheck);
    try expectString(handle.pConf.?.pszOSName, "pinned");
    try tmp.dir.access(std.testing.io, "parked/cache", .{});
    try testing.expectError(
        error.FileNotFound,
        tmp.dir.access(std.testing.io, "root/cache", .{}),
    );
}

test "pinned cachedir setopt repins only the final target path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/etc/rpmz");
    try tmp.dir.createDirPath(std.testing.io, "root/repos");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/etc/rpmz/rpmz.conf",
        .data =
        \\[main]
        \\plugins=0
        \\repodir=/repos
        \\cachedir=/old-cache
        \\
        ,
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
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    var base_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer base_config.deinit();
    var pinned = try base_config.cloneWithPinnedInstallRootDeferredRpmDb(
        std.testing.allocator,
        root,
        root_fd,
    );
    defer pinned.deinit();
    const setopts = create_cnfnode("(setopts)") orelse
        return error.TestUnexpectedNull;
    defer destroy_cnftree(setopts);
    const cachedir = create_cnfnode("cachedir") orelse
        return error.TestUnexpectedNull;
    cnfnode_setval(cachedir, "/new-cache");
    append_node(setopts, cachedir);
    var args = CmdArgs{
        .pszInstallRoot = root_z.ptr,
        .cn_setopts = setopts,
    };
    var handle = Tdnf{
        .pArgs = &args,
        .pRpmConfig = @ptrCast(&pinned),
    };
    try testing.expectEqual(
        @as(u32, 0),
        TDNFReadConfigPinned(
            &handle,
            "/etc/rpmz/rpmz.conf",
            "main",
        ),
    );
    defer TDNFFreeConfig(handle.pConf);
    try expectString(handle.pConf.?.pszCacheDir, "/new-cache");
    try testing.expect(pinned.cacheDirUsesPinnedRoot("/new-cache"));
    try testing.expect(!pinned.cacheDirUsesPinnedRoot("/old-cache"));
    try tmp.dir.access(std.testing.io, "root/new-cache", .{});
}

test "pinned config rejects absolute symlink escapes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/etc/rpmz");
    try tmp.dir.createDirPath(std.testing.io, "outside");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside/rpmz.conf",
        .data = "[main]\nplugins=0\n",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside/os-release",
        .data = "ID=escaped\nVERSION_ID=9\n",
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
    const outside_config = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "outside", "rpmz.conf" },
    );
    defer std.testing.allocator.free(outside_config);
    try tmp.dir.symLink(
        std.testing.io,
        outside_config,
        "root/etc/rpmz/rpmz.conf",
        .{},
    );
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    var base_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer base_config.deinit();
    var pinned = try base_config.cloneWithPinnedInstallRootDeferredRpmDb(
        std.testing.allocator,
        root,
        root_fd,
    );
    defer pinned.deinit();
    var args = CmdArgs{ .pszInstallRoot = root_z.ptr };
    var handle = Tdnf{
        .pArgs = &args,
        .pRpmConfig = @ptrCast(&pinned),
    };
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFReadConfigPinned(
            &handle,
            "/etc/rpmz/rpmz.conf",
            "main",
        ),
    );
    try testing.expect(handle.pConf == null);

    try tmp.dir.deleteFile(std.testing.io, "root/etc/rpmz/rpmz.conf");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/etc/rpmz/rpmz.conf",
        .data = "[main]\nplugins=0\ncachedir=/cache\n",
    });
    const outside_os = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "outside", "os-release" },
    );
    defer std.testing.allocator.free(outside_os);
    try tmp.dir.symLink(
        std.testing.io,
        outside_os,
        "root/etc/os-release",
        .{},
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFReadConfigPinned(
            &handle,
            "/etc/rpmz/rpmz.conf",
            "main",
        ),
    );
    try testing.expect(handle.pConf == null);

    try tmp.dir.deleteFile(std.testing.io, "root/etc/os-release");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/etc/os-release",
        .data = "ID=safe\nVERSION_ID=1\n",
    });
    try tmp.dir.createDirPath(std.testing.io, "outside/cache");
    const outside_cache = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "outside", "cache" },
    );
    defer std.testing.allocator.free(outside_cache);
    try tmp.dir.symLink(
        std.testing.io,
        outside_cache,
        "root/cache",
        .{},
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFReadConfigPinned(
            &handle,
            "/etc/rpmz/rpmz.conf",
            "main",
        ),
    );
    try testing.expect(handle.pConf == null);

    try tmp.dir.deleteFile(std.testing.io, "root/cache");
    try tmp.dir.createDirPath(std.testing.io, "root/cache");
    try tmp.dir.createDirPath(std.testing.io, "outside/repos");
    const outside_repos = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "outside", "repos" },
    );
    defer std.testing.allocator.free(outside_repos);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "root/etc/rpmz/rpmz.conf",
        .data = "[main]\nplugins=0\ncachedir=/cache\nrepodir=/repos\n",
    });
    try tmp.dir.symLink(
        std.testing.io,
        outside_repos,
        "root/repos",
        .{},
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFReadConfigPinned(
            &handle,
            "/etc/rpmz/rpmz.conf",
            "main",
        ),
    );
    try testing.expect(handle.pConf == null);
}

test "missing files, invalid parameters, and invalid tsflags reset handle output" {
    var args = CmdArgs{};
    var handle = Tdnf{ .pArgs = &args };
    try testing.expectEqual(
        errors.ERROR_TDNF_FILE_NOT_FOUND,
        TDNFReadConfig(&handle, fixturePath("does-not-exist.conf"), "main"),
    );
    try testing.expect(handle.pConf == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFReadConfig(&handle, fixturePath("default-root/etc/rpmz/rpmz.conf"), ""),
    );
    try testing.expect(handle.pConf == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFReadConfig(&handle, fixturePath("invalid-root/etc/rpmz/rpmz.conf"), "main"),
    );
    try testing.expect(handle.pConf == null);
}

test "boolean and integer parsing retain strtoi edge behavior" {
    var conf = Conf{};
    const root = create_cnfnode("(root)") orelse return error.TestUnexpectedNull;
    defer destroy_cnftree(root);
    inline for (.{
        .{ "gpgcheck", "TRUE" },
        .{ "sslverify", "false" },
        .{ "keepcache", "-2" },
        .{ "plugins", "yes" },
        .{ "installonly_limit", "2147483647" },
        .{ "openmax", "2147483648" },
        .{ "connect_timeout", "12x" },
    }) |entry| {
        const node = create_cnfnode(entry[0]) orelse return error.TestUnexpectedNull;
        cnfnode_setval(node, entry[1]);
        append_node(root, node);
    }
    try testing.expectEqual(@as(u32, 0), configFromTree(&conf, root, production_ops));
    try testing.expectEqual(@as(c_int, 1), conf.nGPGCheck);
    try testing.expectEqual(@as(c_int, 0), conf.nSSLVerify);
    try testing.expectEqual(@as(c_int, 1), conf.nKeepCache);
    try testing.expectEqual(@as(c_int, 0), conf.nPluginsEnabled);
    try testing.expectEqual(std.math.maxInt(c_int), conf.nInstallOnlyLimit);
    try testing.expectEqual(@as(c_int, 0), conf.nOpenMax);
    try testing.expectEqual(@as(c_int, 0), conf.nConnectTimeout);
}

test "long configured strings are owned without truncation" {
    var long_value: [4097:0]u8 = undefined;
    @memset(long_value[0..4096], 'x');
    long_value[4096] = 0;
    var conf = Conf{};
    defer freeString(&conf.pszProxy);
    const root = create_cnfnode("(root)") orelse return error.TestUnexpectedNull;
    defer destroy_cnftree(root);
    const node = create_cnfnode("proxy") orelse return error.TestUnexpectedNull;
    cnfnode_setval(node, &long_value);
    append_node(root, node);
    try testing.expectEqual(@as(u32, 0), configFromTree(&conf, root, production_ops));
    try testing.expectEqual(@as(usize, 4096), std.mem.len(conf.pszProxy.?));
}

const FailureContext = struct {
    calls: usize = 0,
    fail_at: usize,
};

fn failingAllocateMemory(
    context: ?*anyopaque,
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32 {
    const state: *FailureContext = @ptrCast(@alignCast(context.?));
    state.calls += 1;
    if (state.calls == state.fail_at) {
        output.* = null;
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    }
    return TDNFAllocateMemory(count, size, output);
}

fn failingAllocateString(
    context: ?*anyopaque,
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    const state: *FailureContext = @ptrCast(@alignCast(context.?));
    state.calls += 1;
    if (state.calls == state.fail_at) {
        output.* = null;
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    }
    return TDNFAllocateString(source, output);
}

test "allocation failure frees partial config and clears output" {
    var counting = FailureContext{ .fail_at = std.math.maxInt(usize) };
    var ops = Ops{
        .context = &counting,
        .allocate_memory = failingAllocateMemory,
        .allocate_string = failingAllocateString,
    };
    var args = CmdArgs{ .pszInstallRoot = @constCast(fixturePath("complete-root")) };
    var handle = Tdnf{ .pArgs = &args };
    try testing.expectEqual(@as(u32, 0), readConfig(
        &handle,
        fixturePath("complete-root/etc/rpmz/rpmz.conf"),
        "main",
        ops,
    ));
    TDNFFreeConfig(handle.pConf);
    handle.pConf = null;

    var fail_at: usize = 1;
    while (fail_at <= counting.calls) : (fail_at += 1) {
        var state = FailureContext{ .fail_at = fail_at };
        ops.context = &state;
        try testing.expectEqual(
            errors.ERROR_TDNF_OUT_OF_MEMORY,
            readConfig(
                &handle,
                fixturePath("complete-root/etc/rpmz/rpmz.conf"),
                "main",
                ops,
            ),
        );
        try testing.expect(handle.pConf == null);
    }
}

test "successful reload replaces ownership and failed reload clears it" {
    var args = CmdArgs{ .pszInstallRoot = @constCast(fixturePath("default-root")) };
    var handle = Tdnf{ .pArgs = &args };
    try testing.expectEqual(
        @as(u32, 0),
        TDNFReadConfig(&handle, fixturePath("default-root/etc/rpmz/rpmz.conf"), "main"),
    );
    const first = handle.pConf.?;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFReadConfig(&handle, fixturePath("default-root/etc/rpmz/rpmz.conf"), "main"),
    );
    try testing.expect(handle.pConf != first);
    try testing.expectEqual(
        errors.ERROR_TDNF_FILE_NOT_FOUND,
        TDNFReadConfig(&handle, fixturePath("missing-after-reload.conf"), "main"),
    );
    try testing.expect(handle.pConf == null);
    TDNFFreeConfig(null);
}

test "release and architecture overrides avoid host rpm and uname state" {
    var distro = [_]?[*:0]u8{ @constCast("unused"), null };
    var args = CmdArgs{
        .pszReleaseVer = @constCast("99"),
        .pszArch = @constCast("test-arch"),
    };
    var conf = Conf{ .ppszDistroVerPkgs = &distro };
    defer freeString(&conf.pszVarReleaseVer);
    defer freeString(&conf.pszVarBaseArch);
    var handle = Tdnf{ .pArgs = &args, .pConf = &conf };
    try testing.expectEqual(@as(u32, 0), TDNFConfigExpandVars(&handle));
    try expectString(conf.pszVarReleaseVer, "99");
    try expectString(conf.pszVarBaseArch, "test-arch");
}

test "variable replacement transfers the caller-owned string" {
    var dirs = [_]?[*:0]u8{null};
    var conf = Conf{
        .ppszVarsDirs = &dirs,
        .pszVarReleaseVer = @constCast("7"),
        .pszVarBaseArch = @constCast("x86_64"),
    };
    var args = CmdArgs{};
    var handle = Tdnf{ .pArgs = &args, .pConf = &conf };
    var source: ?[*:0]u8 = null;
    try testing.expectEqual(@as(u32, 0), TDNFAllocateString("repo-$releasever-$basearch", &source));
    try testing.expectEqual(@as(u32, 0), TDNFConfigReplaceVars(&handle, &source));
    defer freeString(&source);
    try expectString(source, "repo-7-x86_64");
}
