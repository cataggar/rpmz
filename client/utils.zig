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
const rpmdb_test = if (builtin.is_test) @import("rpmdb_test") else struct {};

const HistoryInfo = abi.HistoryInfo;
const HistoryInfoItem = abi.HistoryInfoItem;
const Stat = std.os.linux.Statx;

const EEXIST: c_int = @intFromEnum(std.posix.E.EXIST);
const EINVAL: c_int = @intFromEnum(std.posix.E.INVAL);
const ELOOP: c_int = @intFromEnum(std.posix.E.LOOP);
const ENAMETOOLONG: c_int = @intFromEnum(std.posix.E.NAMETOOLONG);
const ENOENT: c_int = @intFromEnum(std.posix.E.NOENT);
const ENOTDIR: c_int = @intFromEnum(std.posix.E.NOTDIR);
const LOG_ERR: c_int = 1;
const stderr_fileno: c_int = 2;
const path_type_mask: u16 = 0o170000;
const path_type_regular: u16 = 0o100000;
const path_type_symlink: u16 = 0o120000;

const UtsName = extern struct {
    sysname: [65]u8,
    nodename: [65]u8,
    release: [65]u8,
    version: [65]u8,
    machine: [65]u8,
    domainname: [65]u8,
};

const libc = struct {
    extern fn access([*:0]const u8, c_int) c_int;
    extern fn close(c_int) c_int;
    extern fn dup(c_int) c_int;
    extern fn dup2(c_int, c_int) c_int;
    extern fn fflush(?*std.c.FILE) c_int;
    extern fn getenv([*:0]const u8) ?[*:0]u8;
    extern fn mkdirat(c_int, [*:0]const u8, u32) c_int;
    extern fn pipe([*]c_int) c_int;
    extern fn read(c_int, ?*anyopaque, usize) isize;
    extern fn setenv([*:0]const u8, [*:0]const u8, c_int) c_int;
    extern fn strcasecmp([*:0]const u8, [*:0]const u8) c_int;
    extern fn strerror(c_int) [*:0]const u8;
    extern fn strtol([*:0]const u8, *?[*:0]u8, c_int) c_long;
    extern fn umask(u32) u32;
    extern fn uname(*UtsName) c_int;
    extern fn unsetenv([*:0]const u8) c_int;
};

extern fn TDNFAllocateMemory(
    nNumElements: usize,
    nSize: usize,
    ppMemory: ?*?*anyopaque,
) u32;
extern fn TDNFAllocateString(
    pszSrc: ?[*:0]const u8,
    ppszDst: ?*?[*:0]u8,
) u32;
extern fn TDNFFreeMemory(pMemory: ?*anyopaque) void;
extern fn GlobalSetJson(nValue: c_int) void;
extern fn GlobalSetQuiet(nValue: c_int) void;
extern fn rpmz_rpm_config_create(root: ?[*:0]const u8) ?*anyopaque;
extern fn rpmz_rpm_config_destroy(config: ?*anyopaque) void;
extern fn rpmz_rpm_config_last_error() [*:0]const u8;
extern fn rpmz_rpmdb_last_error() [*:0]const u8;
extern fn rpmz_rpmdb_resolve_provider_version_config(
    config: ?*const anyopaque,
    provide_name: ?[*:0]const u8,
    version_out: ?*?[*:0]u8,
) c_int;
extern fn rpmz_rpmdb_string_free(value: ?[*:0]u8) void;

const MemoryOps = struct {
    context: ?*anyopaque = null,
    allocateMemory: *const fn (
        context: ?*anyopaque,
        count: usize,
        size: usize,
        output: *?*anyopaque,
    ) u32,
    allocateString: *const fn (
        context: ?*anyopaque,
        source: [*:0]const u8,
        output: *?[*:0]u8,
    ) u32,
    free: *const fn (context: ?*anyopaque, value: ?*anyopaque) void,
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
    source: [*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    return TDNFAllocateString(source, output);
}

fn productionFree(_: ?*anyopaque, value: ?*anyopaque) void {
    TDNFFreeMemory(value);
}

const production_memory_ops = MemoryOps{
    .allocateMemory = productionAllocateMemory,
    .allocateString = productionAllocateString,
    .free = productionFree,
};

const RpmOps = struct {
    context: ?*anyopaque = null,
    create: *const fn (
        context: ?*anyopaque,
        root: [*:0]const u8,
    ) ?*anyopaque,
    destroy: *const fn (context: ?*anyopaque, config: ?*anyopaque) void,
    resolve: *const fn (
        context: ?*anyopaque,
        config: *const anyopaque,
        name: [*:0]const u8,
        output: *?[*:0]u8,
    ) c_int,
    freeString: *const fn (context: ?*anyopaque, value: ?[*:0]u8) void,
    configError: *const fn (context: ?*anyopaque) [*:0]const u8,
    dbError: *const fn (context: ?*anyopaque) [*:0]const u8,
};

fn productionRpmCreate(
    _: ?*anyopaque,
    root: [*:0]const u8,
) ?*anyopaque {
    return rpmz_rpm_config_create(root);
}

fn productionRpmDestroy(_: ?*anyopaque, config: ?*anyopaque) void {
    rpmz_rpm_config_destroy(config);
}

fn productionRpmResolve(
    _: ?*anyopaque,
    config: *const anyopaque,
    name: [*:0]const u8,
    output: *?[*:0]u8,
) c_int {
    return rpmz_rpmdb_resolve_provider_version_config(config, name, output);
}

fn productionRpmFreeString(_: ?*anyopaque, value: ?[*:0]u8) void {
    rpmz_rpmdb_string_free(value);
}

fn productionRpmConfigError(_: ?*anyopaque) [*:0]const u8 {
    return rpmz_rpm_config_last_error();
}

fn productionRpmDbError(_: ?*anyopaque) [*:0]const u8 {
    return rpmz_rpmdb_last_error();
}

const production_rpm_ops = RpmOps{
    .create = productionRpmCreate,
    .destroy = productionRpmDestroy,
    .resolve = productionRpmResolve,
    .freeString = productionRpmFreeString,
    .configError = productionRpmConfigError,
    .dbError = productionRpmDbError,
};

const KernelOps = struct {
    context: ?*anyopaque = null,
    uname: *const fn (context: ?*anyopaque, output: *UtsName) c_int,
};

fn productionUname(_: ?*anyopaque, output: *UtsName) c_int {
    return libc.uname(output);
}

const production_kernel_ops = KernelOps{ .uname = productionUname };
var test_kernel_ops: ?KernelOps = null;

fn kernelOps() KernelOps {
    if (builtin.is_test) return test_kernel_ops orelse production_kernel_ops;
    return production_kernel_ops;
}

const ErrorDescription = struct {
    code: u32,
    description: [:0]const u8,
};

const error_descriptions = [_]ErrorDescription{
    .{ .code = 1000, .description = "Generic base error" },
    .{ .code = 1001, .description = "Package name expected but was not provided" },
    .{ .code = 1002, .description = "Error loading rpmz conf (/etc/rpmz/rpmz.conf)" },
    .{ .code = 1003, .description = "Error loading rpmz repo (normally under /etc/yum.repos.d/)" },
    .{ .code = 1004, .description = "Encountered an invalid repo file" },
    .{ .code = 1005, .description = "Error opening repo dir. Check if the repodir configured in rpmz.conf exists (usually /etc/yum.repos.d)" },
    .{ .code = 1011, .description = "No matching packages" },
    .{ .code = 1020, .description = "There was an error setting the proxy server." },
    .{ .code = 1021, .description = "There was an error setting the proxy server user and pass" },
    .{ .code = 1022, .description = "distroverpkg config entry is set to a package that is not installed. Check /etc/rpmz/rpmz.conf" },
    .{ .code = 1023, .description = "There was an error reading version of distroverpkg" },
    .{ .code = 1024, .description = "A memory allocation was requested with an invalid size" },
    .{ .code = 1025, .description = "Requested string allocation size was too long." },
    .{ .code = 1012, .description = "There are no enabled repos.\n Run \"rpmz tdnf repolist all\" to see the repos you have.\n You can enable repos by\n 1. by passing in --enablerepo <reponame>\n 2. editing repo files in your repodir(usually /etc/yum.repos.d)" },
    .{ .code = 1013, .description = "Packagelist was empty" },
    .{ .code = 1014, .description = "Error creating goal" },
    .{ .code = 1015, .description = "Invalid argument in resolve" },
    .{ .code = 1016, .description = "Clean type specified is not supported in this release. Please try clean all." },
    .{ .code = 1300, .description = "Solv base error" },
    .{ .code = 1301, .description = "Solv general runtime error" },
    .{ .code = 1302, .description = "Solv client programming error" },
    .{ .code = 1303, .description = "Solv error propagted from libsolv" },
    .{ .code = 1304, .description = "Solv - I/O error" },
    .{ .code = 1305, .description = "Solv - cache write error" },
    .{ .code = 1306, .description = "Solv - ill formed query" },
    .{ .code = 1307, .description = "Solv - unknown arch" },
    .{ .code = 1308, .description = "Solv - validation check failed" },
    .{ .code = 1310, .description = "Solv - goal found no solutions" },
    .{ .code = 1311, .description = "Solv - the capability was not available" },
    .{ .code = 1312, .description = "Solv - Checksum creation failed" },
    .{ .code = 1313, .description = "Solv - Failed to write repo" },
    .{ .code = 1314, .description = "Solv - Solv cache not found" },
    .{ .code = 1315, .description = "Solv - Failed to add solv" },
    .{ .code = 1400, .description = "Repo error base" },
    .{ .code = 1401, .description = "There was an error while setting SSL settings for the repo." },
    .{ .code = 1006, .description = "Error during repo handle execution" },
    .{ .code = 1007, .description = "Repo during repo result getinfo" },
    .{ .code = 1525, .description = "rpm transaction failed" },
    .{ .code = 1599, .description = "No matches found" },
    .{ .code = 1471, .description = "rpm generic error - not found (possible corrupt rpm file)" },
    .{ .code = 1472, .description = "rpm generic failure" },
    .{ .code = 1473, .description = "rpm signature is OK, but key is not trusted" },
    .{ .code = 1474, .description = "public key is unavailable. install public key using rpm --import or use --nogpgcheck to ignore." },
    .{ .code = 1505, .description = "public key file is invalid or corrupted" },
    .{ .code = 1508, .description = "GpgKey Url schemes other than file are not supported" },
    .{ .code = 1507, .description = "GpgKey Url is invalid" },
    .{ .code = 1510, .description = "RPM not signed. Use --nogpgcheck to ignore." },
    .{ .code = 1511, .description = "RPM data container could not be created. Use --nogpgcheck to ignore." },
    .{ .code = 1512, .description = "RPM not signed. Use --skipsignature or --nogpgcheck to ignore." },
    .{ .code = 1513, .description = "RPM failed to parse gpg key. Use --nogpgcheck to ignore." },
    .{ .code = 1514, .description = "RPM is signed but failed to match with known keys. Use --nogpgcheck to ignore." },
    .{ .code = 1018, .description = "autoerase / autoremove is not supported." },
    .{ .code = 1515, .description = "rpm check reported errors" },
    .{ .code = 1502, .description = "Bad root directory" },
    .{ .code = 1029, .description = "metadata_expire value could not be parsed. Check your repo files." },
    .{ .code = 1030, .description = "The operation would result in removing a protected package." },
    .{ .code = 1035, .description = "a downgrade is not allowed below the minimal version. Check 'minversions' in the configuration." },
    .{ .code = 1601, .description = "Operation not permitted. You have to be root." },
    .{ .code = 1520, .description = "A required option was not found" },
    .{ .code = 1032, .description = "Operation aborted." },
    .{ .code = 1033, .description = "Invalid input." },
    .{ .code = 1034, .description = "cache only is set, but no repo data found" },
    .{ .code = 1036, .description = "Insufficient disk space at cache directory /var/cache/tdnf (unless specified differently in config). Try freeing space first." },
    .{ .code = 1037, .description = "Duplicate repo id" },
    .{ .code = 1038, .description = "repo name is invalid" },
    .{ .code = 1551, .description = "An event context item was not found. This is usually related to plugin events. Try --noplugins to deactivate all plugins or --disableplugin=<plugin> to deactivate a specific one. You can permanently deactivate an offending plugin by setting enable=0 in the plugin config file." },
    .{ .code = 1552, .description = "An event item type had a mismatch. This is usually related to plugin events. Try --noplugins to deactivate all plugins or --disableplugin=<plugin> to deactivate a specific one. You can permanently deactivate an offending plugin by setting enable=0 in the plugin config file." },
    .{ .code = 1523, .description = "gpgkey entry is missing for this repo. please add gpgkey in repo file or use --nogpgcheck to ignore." },
    .{ .code = 1524, .description = "URL is invalid." },
    .{ .code = 1527, .description = "File size does not match." },
    .{ .code = 1528, .description = "File checksum does not match." },
    .{ .code = 1531, .description = "RPM package is not signed." },
    .{ .code = 2500, .description = "Base URL and Metalink URL not found in the repo file" },
    .{ .code = 2501, .description = "Checksum Validation failed for the repomd.xml downloaded using URL from metalink" },
    .{ .code = 2502, .description = "No Resource present in metalink file for file download" },
    .{ .code = 2600, .description = "API call to digest API forbidden in FIPS mode!" },
    .{ .code = 1202, .description = "Curl doesn't Support this protocol" },
    .{ .code = 1203, .description = "Curl Init Failed" },
    .{ .code = 1204, .description = "URL seems to be corrupted. Please clean all and makecache" },
    .{ .code = 1600, .description = "unknown system error" },
    .{ .code = 1801, .description = "History database error" },
    .{ .code = 1802, .description = "History database does not exist" },
};

fn errnoValue() c_int {
    return std.c._errno().*;
}

fn systemError(value: c_int) u32 {
    return errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(value));
}

fn isNullOrEmpty(value: ?[*:0]const u8) bool {
    return value == null or value.?[0] == 0;
}

fn freeWithOps(ops: MemoryOps, value: ?*anyopaque) void {
    ops.free(ops.context, value);
}

fn statPath(path: [*:0]const u8, no_follow: bool, output: *Stat) c_int {
    return std.c.statx(
        std.os.linux.AT.FDCWD,
        path,
        if (no_follow) std.os.linux.AT.SYMLINK_NOFOLLOW else 0,
        .{ .TYPE = true, .SIZE = true },
        output,
    );
}

fn descriptionForError(code: u32) ?[*:0]const u8 {
    for (error_descriptions) |entry| {
        if (entry.code == code) return entry.description.ptr;
    }
    return null;
}

fn getErrorStringWithOps(
    code: u32,
    output: ?*?[*:0]u8,
    memory: MemoryOps,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    out.* = null;

    var source = descriptionForError(code);
    if (source == null and code > errors.ERROR_TDNF_SYSTEM_BASE) {
        const actual: c_int = @bitCast(code - errors.ERROR_TDNF_SYSTEM_BASE);
        source = libc.strerror(actual);
    }
    source = source orelse "Unknown error";
    return memory.allocateString(memory.context, source.?, out);
}

pub export fn TDNFGetErrorString(
    code: u32,
    output: ?*?[*:0]u8,
) u32 {
    return getErrorStringWithOps(code, output, production_memory_ops);
}

pub export fn TDNFIsGlob(value: ?[*:0]const u8) c_int {
    const ptr = value orelse return 0;
    const bytes = std.mem.span(ptr);
    for (bytes) |byte| {
        if (byte == '*' or byte == '?' or byte == '[') return 1;
    }
    return 0;
}

fn componentIsLast(path: []const u8, start: usize) bool {
    var cursor = start;
    while (cursor < path.len) {
        while (cursor < path.len and path[cursor] == '/') : (cursor += 1) {}
        if (cursor >= path.len) return true;
        const begin = cursor;
        while (cursor < path.len and path[cursor] != '/') : (cursor += 1) {}
        if (!std.mem.eql(u8, path[begin..cursor], ".")) return false;
    }
    return true;
}

fn makeDirectoryPath(path_z: [*:0]const u8, parents: bool) u32 {
    const path = std.mem.span(path_z);
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
    defer _ = std.c.close(current_fd);

    const old_mask = libc.umask(0o022);
    defer _ = libc.umask(old_mask);

    var cursor: usize = 0;
    while (cursor < path.len) {
        while (cursor < path.len and path[cursor] == '/') : (cursor += 1) {}
        if (cursor >= path.len) return 0;
        const begin = cursor;
        while (cursor < path.len and path[cursor] != '/') : (cursor += 1) {}
        const component = path[begin..cursor];
        if (std.mem.eql(u8, component, ".")) continue;
        if (component.len > std.fs.max_name_bytes) {
            return systemError(ENAMETOOLONG);
        }

        var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
        @memcpy(name_buffer[0..component.len], component);
        name_buffer[component.len] = 0;
        const name: [*:0]const u8 = @ptrCast(&name_buffer);
        const last = componentIsLast(path, cursor);

        if (parents or last) {
            if (libc.mkdirat(current_fd, name, 0o755) != 0) {
                const value = errnoValue();
                if (value != EEXIST) return systemError(value);
            }
            if (last) return 0;
        }

        const next_fd = std.c.openat(current_fd, name, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (next_fd < 0) return systemError(errnoValue());
        _ = std.c.close(current_fd);
        current_fd = next_fd;
    }
    return 0;
}

pub export fn TDNFUtilsMakeDir(path: ?[*:0]const u8) u32 {
    if (isNullOrEmpty(path)) return errors.ERROR_TDNF_INVALID_PARAMETER;
    return makeDirectoryPath(path.?, false);
}

fn makeDirsWithOps(path: ?[*:0]const u8, memory: MemoryOps) u32 {
    if (isNullOrEmpty(path)) return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (libc.access(path.?, 0) == 0) return systemError(EEXIST);
    const access_error = errnoValue();
    if (access_error != ENOENT) return systemError(access_error);

    var copy: ?[*:0]u8 = null;
    const alloc_result = memory.allocateString(memory.context, path.?, &copy);
    if (alloc_result != 0) return alloc_result;
    defer freeWithOps(memory, @ptrCast(copy));

    const bytes = std.mem.span(copy.?);
    if (bytes.len != 0 and bytes[bytes.len - 1] == '/') {
        copy.?[bytes.len - 1] = 0;
    }
    return makeDirectoryPath(copy.?, true);
}

pub export fn TDNFUtilsMakeDirs(path: ?[*:0]const u8) u32 {
    return makeDirsWithOps(path, production_memory_ops);
}

pub export fn TDNFIsFileOrSymlink(
    path: ?[*:0]const u8,
    output: ?*c_int,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    out.* = 0;
    if (isNullOrEmpty(path)) return errors.ERROR_TDNF_INVALID_PARAMETER;

    var stat_buf = std.mem.zeroes(Stat);
    if (statPath(path.?, false, &stat_buf) != 0) {
        const value = errnoValue();
        if (value == ENOENT) return 0;
        return systemError(value);
    }
    const kind = stat_buf.mode & path_type_mask;
    out.* = @intFromBool(
        kind == path_type_regular or kind == path_type_symlink,
    );
    return 0;
}

pub export fn TDNFGetFileSize(
    path: ?[*:0]const u8,
    output: ?*c_int,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (isNullOrEmpty(path)) {
        out.* = 0;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var stat_buf = std.mem.zeroes(Stat);
    if (statPath(path.?, false, &stat_buf) != 0) {
        out.* = 0;
        return systemError(errnoValue());
    }
    if ((stat_buf.mode & path_type_mask) == path_type_regular) {
        out.* = @bitCast(@as(u32, @truncate(stat_buf.size)));
    }
    return 0;
}

fn releaseVersionConfigWithOps(
    config: ?*const anyopaque,
    distro_package: ?[*:0]const u8,
    output: ?*?[*:0]u8,
    memory: MemoryOps,
    rpm: RpmOps,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    out.* = null;
    if (config == null or isNullOrEmpty(distro_package)) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var native_version: ?[*:0]u8 = null;
    defer rpm.freeString(rpm.context, native_version);
    const resolve_result = rpm.resolve(
        rpm.context,
        config.?,
        distro_package.?,
        &native_version,
    );
    if (resolve_result < 0) {
        common.log(LOG_ERR, "Failed to read distroverpkg provider '%s': %s\n", .{ distro_package.?, rpm.dbError(rpm.context) });
        return errors.ERROR_TDNF_DISTROVERPKG_READ;
    }
    if (resolve_result == 0) return errors.ERROR_TDNF_NO_DISTROVERPKG;
    if (isNullOrEmpty(native_version)) {
        return errors.ERROR_TDNF_DISTROVERPKG_READ;
    }
    return memory.allocateString(memory.context, native_version.?, out);
}

pub export fn TdnfGetReleaseVersionConfig(
    config: ?*const anyopaque,
    distro_package: ?[*:0]const u8,
    output: ?*?[*:0]u8,
) u32 {
    return releaseVersionConfigWithOps(
        config,
        distro_package,
        output,
        production_memory_ops,
        production_rpm_ops,
    );
}

fn releaseVersionWithOps(
    root: ?[*:0]const u8,
    distro_package: ?[*:0]const u8,
    output: ?*?[*:0]u8,
    memory: MemoryOps,
    rpm: RpmOps,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    out.* = null;
    if (isNullOrEmpty(root) or isNullOrEmpty(distro_package)) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    const config = rpm.create(rpm.context, root.?) orelse {
        common.log(LOG_ERR, "Failed to initialize native rpm configuration: %s\n", .{rpm.configError(rpm.context)});
        return errors.ERROR_TDNF_DISTROVERPKG_READ;
    };
    defer rpm.destroy(rpm.context, config);
    return releaseVersionConfigWithOps(
        config,
        distro_package,
        out,
        memory,
        rpm,
    );
}

pub export fn TDNFGetReleaseVersion(
    root: ?[*:0]const u8,
    distro_package: ?[*:0]const u8,
    output: ?*?[*:0]u8,
) u32 {
    return releaseVersionWithOps(
        root,
        distro_package,
        output,
        production_memory_ops,
        production_rpm_ops,
    );
}

fn getKernelArchWithOps(
    output: ?*?[*:0]u8,
    memory: MemoryOps,
    kernel: KernelOps,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    out.* = null;
    var name = std.mem.zeroes(UtsName);
    if (kernel.uname(kernel.context, &name) != 0) {
        return systemError(errnoValue());
    }
    return memory.allocateString(
        memory.context,
        @ptrCast(&name.machine),
        out,
    );
}

pub export fn TDNFGetKernelArch(output: ?*?[*:0]u8) u32 {
    return getKernelArchWithOps(
        output,
        production_memory_ops,
        kernelOps(),
    );
}

pub export fn TDNFParseMetadataExpire(
    value: ?[*:0]const u8,
    output: ?*c_long,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (isNullOrEmpty(value)) {
        out.* = 0;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    if (libc.strcasecmp("never", value.?) == 0) {
        out.* = -1;
        return 0;
    }

    var end: ?[*:0]u8 = null;
    var parsed = libc.strtol(value.?, &end, 10);
    if (parsed < 0) {
        parsed = -1;
    } else if (parsed > 0) {
        const multiplier: c_long = switch (end.?[0]) {
            0, 's' => 1,
            'm' => 60,
            'h' => 60 * 60,
            'd' => 60 * 60 * 24,
            else => {
                out.* = 0;
                return errors.ERROR_TDNF_METADATA_EXPIRE_PARSE;
            },
        };
        parsed *%= multiplier;
    } else if (end.?[0] != 0) {
        out.* = 0;
        return errors.ERROR_TDNF_METADATA_EXPIRE_PARSE;
    }

    out.* = parsed;
    return 0;
}

fn appendPathWithOps(
    base: ?[*:0]const u8,
    part: ?[*:0]const u8,
    output: ?*?[*:0]u8,
    memory: MemoryOps,
) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    out.* = null;
    if (isNullOrEmpty(base) or isNullOrEmpty(part)) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    const base_bytes = std.mem.span(base.?);
    const part_bytes = std.mem.span(part.?);
    const capacity = base_bytes.len +% part_bytes.len +% 2;
    var raw: ?*anyopaque = null;
    const alloc_result = memory.allocateMemory(
        memory.context,
        1,
        capacity,
        &raw,
    );
    if (alloc_result != 0) return alloc_result;

    const buffer: [*]u8 = @ptrCast(raw.?);
    var base_length = base_bytes.len;
    if (base_bytes[base_length - 1] == '/') base_length -= 1;
    @memcpy(buffer[0..base_length], base_bytes[0..base_length]);
    var used = base_length;
    if (part_bytes[0] != '/') {
        buffer[used] = '/';
        used += 1;
    }
    @memcpy(buffer[used .. used + part_bytes.len], part_bytes);
    used += part_bytes.len;
    buffer[used] = 0;
    out.* = @ptrCast(buffer);
    return 0;
}

pub export fn TDNFAppendPath(
    base: ?[*:0]const u8,
    part: ?[*:0]const u8,
    output: ?*?[*:0]u8,
) u32 {
    return appendPathWithOps(base, part, output, production_memory_ops);
}

fn freeHistoryInfoItemsWithOps(
    items: ?[*]HistoryInfoItem,
    count: c_int,
    memory: MemoryOps,
) void {
    const values = items orelse return;
    var index: c_int = 0;
    while (index < count) : (index += 1) {
        const item = &values[@intCast(index)];
        freeWithOps(memory, @ptrCast(item.pszCmdLine));
        if (item.ppszAddedPkgs) |packages| {
            var package_index: c_int = 0;
            while (package_index < item.nAddedCount) : (package_index += 1) {
                freeWithOps(
                    memory,
                    @ptrCast(packages[@intCast(package_index)]),
                );
            }
            freeWithOps(memory, @ptrCast(packages));
        }
        if (item.ppszRemovedPkgs) |packages| {
            var package_index: c_int = 0;
            while (package_index < item.nRemovedCount) : (package_index += 1) {
                freeWithOps(
                    memory,
                    @ptrCast(packages[@intCast(package_index)]),
                );
            }
            freeWithOps(memory, @ptrCast(packages));
        }
    }
    freeWithOps(memory, @ptrCast(values));
}

pub export fn TDNFFreeHistoryInfoItems(
    items: ?[*]HistoryInfoItem,
    count: c_int,
) void {
    freeHistoryInfoItemsWithOps(items, count, production_memory_ops);
}

pub export fn TDNFFreeHistoryInfo(info: ?*HistoryInfo) void {
    const value = info orelse return;
    freeHistoryInfoItemsWithOps(
        value.pItems,
        value.nItemCount,
        production_memory_ops,
    );
    TDNFFreeMemory(value);
}

const testing = std.testing;

fn freeCString(value: ?[*:0]u8) void {
    if (value) |ptr| TDNFFreeMemory(@ptrCast(ptr));
}

fn testPath(tmp: *const testing.TmpDir, suffix: []const u8) ![:0]u8 {
    return std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/{s}",
        .{ &tmp.sub_path, suffix },
        0,
    );
}

fn failAllocateMemory(
    _: ?*anyopaque,
    _: usize,
    _: usize,
    output: *?*anyopaque,
) u32 {
    output.* = null;
    return errors.ERROR_TDNF_OUT_OF_MEMORY;
}

fn failAllocateString(
    _: ?*anyopaque,
    _: [*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    output.* = null;
    return errors.ERROR_TDNF_OUT_OF_MEMORY;
}

const failing_memory_ops = MemoryOps{
    .allocateMemory = failAllocateMemory,
    .allocateString = failAllocateString,
    .free = productionFree,
};

test "error strings preserve mapped system unknown ownership and OOM behavior" {
    for (error_descriptions) |entry| {
        var output: ?[*:0]u8 = @ptrFromInt(1);
        try testing.expectEqual(
            @as(u32, 0),
            TDNFGetErrorString(entry.code, &output),
        );
        defer freeCString(output);
        try testing.expectEqualStrings(
            entry.description,
            std.mem.span(output.?),
        );
        freeCString(output);
        output = null;
    }

    var output: ?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFGetErrorString(systemError(ENOENT), &output),
    );
    defer freeCString(output);
    try testing.expectEqualStrings(
        std.mem.span(libc.strerror(ENOENT)),
        std.mem.span(output.?),
    );
    freeCString(output);
    output = null;

    try testing.expectEqual(@as(u32, 0), TDNFGetErrorString(999, &output));
    try testing.expectEqualStrings("Unknown error", std.mem.span(output.?));
    freeCString(output);
    output = @ptrFromInt(1);

    try testing.expectEqual(
        errors.ERROR_TDNF_OUT_OF_MEMORY,
        getErrorStringWithOps(1000, &output, failing_memory_ops),
    );
    try testing.expect(output == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetErrorString(1000, null),
    );
}

test "glob detection matches only star question and opening bracket" {
    try testing.expectEqual(@as(c_int, 0), TDNFIsGlob(null));
    try testing.expectEqual(@as(c_int, 0), TDNFIsGlob(""));
    try testing.expectEqual(@as(c_int, 0), TDNFIsGlob("plain]"));
    try testing.expectEqual(@as(c_int, 1), TDNFIsGlob("a*b"));
    try testing.expectEqual(@as(c_int, 1), TDNFIsGlob("a?b"));
    try testing.expectEqual(@as(c_int, 1), TDNFIsGlob("a[b"));
}

test "directory helpers preserve modes errors and reject symlink ancestors" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const nested = try testPath(&tmp, "dirs/one/two");
    defer testing.allocator.free(nested);
    const old_mask = libc.umask(0o077);
    defer _ = libc.umask(old_mask);

    try testing.expectEqual(@as(u32, 0), TDNFUtilsMakeDirs(nested.ptr));
    const observed_mask = libc.umask(0o077);
    try testing.expectEqual(@as(u32, 0o077), observed_mask);
    var stat_buf = std.mem.zeroes(Stat);
    try testing.expectEqual(@as(c_int, 0), statPath(nested.ptr, false, &stat_buf));
    try testing.expectEqual(@as(u16, 0o755), stat_buf.mode & 0o777);
    try testing.expectEqual(systemError(EEXIST), TDNFUtilsMakeDirs(nested.ptr));

    const single = try testPath(&tmp, "single");
    defer testing.allocator.free(single);
    try testing.expectEqual(@as(u32, 0), TDNFUtilsMakeDir(single.ptr));
    try testing.expectEqual(@as(u32, 0), TDNFUtilsMakeDir(single.ptr));
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFUtilsMakeDir(null),
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFUtilsMakeDirs(""),
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_OUT_OF_MEMORY,
        makeDirsWithOps("missing", failing_memory_ops),
    );

    try tmp.dir.createDirPath(testing.io, "outside");
    try tmp.dir.symLink(
        testing.io,
        "../outside",
        "ancestor",
        .{ .is_directory = true },
    );
    const redirected = try testPath(&tmp, "ancestor/escaped");
    defer testing.allocator.free(redirected);
    const result = TDNFUtilsMakeDirs(redirected.ptr);
    try testing.expect(
        result == systemError(ELOOP) or result == systemError(ENOTDIR),
    );
    try testing.expectError(
        error.FileNotFound,
        tmp.dir.access(testing.io, "outside/escaped", .{}),
    );
}

test "file classification follows links without treating directories as files" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "file",
        .data = "data",
    });
    try tmp.dir.createDir(testing.io, "dir", .default_dir);
    try tmp.dir.symLink(testing.io, "file", "file-link", .{});
    try tmp.dir.symLink(
        testing.io,
        "dir",
        "dir-link",
        .{ .is_directory = true },
    );
    try tmp.dir.symLink(testing.io, "missing", "broken-link", .{});

    const file = try testPath(&tmp, "file");
    defer testing.allocator.free(file);
    const directory = try testPath(&tmp, "dir");
    defer testing.allocator.free(directory);
    const file_link = try testPath(&tmp, "file-link");
    defer testing.allocator.free(file_link);
    const dir_link = try testPath(&tmp, "dir-link");
    defer testing.allocator.free(dir_link);
    const broken = try testPath(&tmp, "broken-link");
    defer testing.allocator.free(broken);

    var is_file: c_int = 99;
    try testing.expectEqual(@as(u32, 0), TDNFIsFileOrSymlink(file.ptr, &is_file));
    try testing.expectEqual(@as(c_int, 1), is_file);
    try testing.expectEqual(@as(u32, 0), TDNFIsFileOrSymlink(file_link.ptr, &is_file));
    try testing.expectEqual(@as(c_int, 1), is_file);
    try testing.expectEqual(@as(u32, 0), TDNFIsFileOrSymlink(directory.ptr, &is_file));
    try testing.expectEqual(@as(c_int, 0), is_file);
    try testing.expectEqual(@as(u32, 0), TDNFIsFileOrSymlink(dir_link.ptr, &is_file));
    try testing.expectEqual(@as(c_int, 0), is_file);
    try testing.expectEqual(@as(u32, 0), TDNFIsFileOrSymlink(broken.ptr, &is_file));
    try testing.expectEqual(@as(c_int, 0), is_file);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFIsFileOrSymlink(null, &is_file),
    );
    try testing.expectEqual(@as(c_int, 0), is_file);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFIsFileOrSymlink(file.ptr, null),
    );
}

test "file size preserves nonregular output and C integer truncation" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "file",
        .data = "12345",
    });
    try tmp.dir.createDir(testing.io, "dir", .default_dir);
    const file = try testPath(&tmp, "file");
    defer testing.allocator.free(file);
    const directory = try testPath(&tmp, "dir");
    defer testing.allocator.free(directory);
    const missing = try testPath(&tmp, "missing");
    defer testing.allocator.free(missing);

    var size: c_int = -1;
    try testing.expectEqual(@as(u32, 0), TDNFGetFileSize(file.ptr, &size));
    try testing.expectEqual(@as(c_int, 5), size);
    size = 77;
    try testing.expectEqual(@as(u32, 0), TDNFGetFileSize(directory.ptr, &size));
    try testing.expectEqual(@as(c_int, 77), size);
    try testing.expectEqual(systemError(ENOENT), TDNFGetFileSize(missing.ptr, &size));
    try testing.expectEqual(@as(c_int, 0), size);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetFileSize(null, &size),
    );
    try testing.expectEqual(@as(c_int, 0), size);

    var sparse = try tmp.dir.createFile(testing.io, "sparse", .{});
    defer sparse.close(testing.io);
    try sparse.setLength(testing.io, @as(u64, std.math.maxInt(u32)) + 6);
    const sparse_path = try testPath(&tmp, "sparse");
    defer testing.allocator.free(sparse_path);
    try testing.expectEqual(@as(u32, 0), TDNFGetFileSize(sparse_path.ptr, &size));
    try testing.expectEqual(@as(c_int, 5), size);
}

fn testReleaseVersionFixture(macro_override: bool) !void {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const cwd = try std.process.currentPathAlloc(testing.io, testing.allocator);
    defer testing.allocator.free(cwd);
    const root = try std.fmt.allocPrintSentinel(
        testing.allocator,
        "{s}/.zig-cache/tmp/{s}/root",
        .{ cwd, &tmp.sub_path },
        0,
    );
    defer testing.allocator.free(root);
    try tmp.dir.createDirPath(testing.io, "root");

    const original_home = if (libc.getenv("HOME")) |home|
        try testing.allocator.dupeZ(u8, std.mem.span(home))
    else
        null;
    defer {
        if (original_home) |home| {
            _ = libc.setenv("HOME", home.ptr, 1);
            testing.allocator.free(home);
        } else {
            _ = libc.unsetenv("HOME");
        }
    }
    try tmp.dir.createDirPath(testing.io, "home");
    const home = try std.fmt.allocPrintSentinel(
        testing.allocator,
        "{s}/.zig-cache/tmp/{s}/home",
        .{ cwd, &tmp.sub_path },
        0,
    );
    defer testing.allocator.free(home);
    try testing.expectEqual(@as(c_int, 0), libc.setenv("HOME", home.ptr, 1));
    if (macro_override) {
        try tmp.dir.writeFile(testing.io, .{
            .sub_path = "home/.rpmmacros",
            .data = "%_dbpath /host-override/native/rpm\n",
        });
    }

    const config_raw = rpmz_rpm_config_create(root.ptr) orelse {
        std.debug.print(
            "production rpm config creation failed: {s}\n",
            .{std.mem.span(rpmz_rpm_config_last_error())},
        );
        return error.TestUnexpectedResult;
    };
    defer rpmz_rpm_config_destroy(config_raw);
    const config: *rpmdb_test.TxnConfig = @ptrCast(@alignCast(config_raw));
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const database_path = try config.resolveRpmDbSqlitePath(&path_buffer);
    try testing.expect(std.mem.startsWith(u8, database_path, root));
    if (macro_override) {
        try testing.expect(std.mem.endsWith(
            u8,
            database_path,
            "/host-override/native/rpm/rpmdb.sqlite",
        ));
    }
    try rpmdb_test.insertProviderTestPackage(
        testing.allocator,
        database_path,
        "fixture-release",
        "1",
        &.{"system-release"},
        &.{1 << 3},
        &.{"42.7"},
    );

    var version: ?[*:0]u8 = @ptrFromInt(1);
    try testing.expectEqual(
        @as(u32, 0),
        TdnfGetReleaseVersionConfig(
            config_raw,
            "system-release",
            &version,
        ),
    );
    try testing.expectEqualStrings("42.7", std.mem.span(version.?));
    freeCString(version);
    version = null;

    try testing.expectEqual(
        @as(u32, 0),
        TDNFGetReleaseVersion(root.ptr, "system-release", &version),
    );
    try testing.expectEqualStrings("42.7", std.mem.span(version.?));
    freeCString(version);
    version = @ptrFromInt(1);

    try testing.expectEqual(
        errors.ERROR_TDNF_NO_DISTROVERPKG,
        TdnfGetReleaseVersionConfig(
            config_raw,
            "missing-release",
            &version,
        ),
    );
    try testing.expect(version == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TdnfGetReleaseVersionConfig(null, "system-release", &version),
    );
    try testing.expect(version == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetReleaseVersion(root.ptr, "", &version),
    );
    try testing.expect(version == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetReleaseVersion(root.ptr, "system-release", null),
    );
}

test "release version helpers follow production macro configuration in scratch roots" {
    try testReleaseVersionFixture(false);
    try testReleaseVersionFixture(true);
}

const FakeRpmContext = struct {
    create_failure: bool = false,
    destroy_count: usize = 0,
    free_count: usize = 0,
    resolve_result: c_int = 1,
    return_empty: bool = false,
};

fn fakeRpmCreate(context: ?*anyopaque, _: [*:0]const u8) ?*anyopaque {
    const fake: *FakeRpmContext = @ptrCast(@alignCast(context.?));
    if (fake.create_failure) return null;
    return context;
}

fn fakeRpmDestroy(context: ?*anyopaque, _: ?*anyopaque) void {
    const fake: *FakeRpmContext = @ptrCast(@alignCast(context.?));
    fake.destroy_count += 1;
}

fn fakeRpmResolve(
    context: ?*anyopaque,
    _: *const anyopaque,
    _: [*:0]const u8,
    output: *?[*:0]u8,
) c_int {
    const fake: *FakeRpmContext = @ptrCast(@alignCast(context.?));
    output.* = if (fake.resolve_result > 0)
        @constCast(if (fake.return_empty) "" else "9.9")
    else
        null;
    return fake.resolve_result;
}

fn fakeRpmFree(context: ?*anyopaque, value: ?[*:0]u8) void {
    if (value != null) {
        const fake: *FakeRpmContext = @ptrCast(@alignCast(context.?));
        fake.free_count += 1;
    }
}

fn fakeRpmError(_: ?*anyopaque) [*:0]const u8 {
    return "injected";
}

fn fakeRpmOps(context: *FakeRpmContext) RpmOps {
    return .{
        .context = context,
        .create = fakeRpmCreate,
        .destroy = fakeRpmDestroy,
        .resolve = fakeRpmResolve,
        .freeString = fakeRpmFree,
        .configError = fakeRpmError,
        .dbError = fakeRpmError,
    };
}

test "release version cleanup handles allocation and native failures" {
    var fake = FakeRpmContext{};
    var output: ?[*:0]u8 = @ptrFromInt(1);
    try testing.expectEqual(
        errors.ERROR_TDNF_OUT_OF_MEMORY,
        releaseVersionWithOps(
            "/root",
            "release",
            &output,
            failing_memory_ops,
            fakeRpmOps(&fake),
        ),
    );
    try testing.expect(output == null);
    try testing.expectEqual(@as(usize, 1), fake.free_count);
    try testing.expectEqual(@as(usize, 1), fake.destroy_count);

    fake.return_empty = true;
    try testing.expectEqual(
        errors.ERROR_TDNF_DISTROVERPKG_READ,
        releaseVersionConfigWithOps(
            @ptrFromInt(1),
            "release",
            &output,
            production_memory_ops,
            fakeRpmOps(&fake),
        ),
    );
    try testing.expect(output == null);
    try testing.expectEqual(@as(usize, 2), fake.free_count);
}

fn fakeUnameSuccess(_: ?*anyopaque, output: *UtsName) c_int {
    output.* = std.mem.zeroes(UtsName);
    @memcpy(output.machine[0..7], "fixture");
    return 0;
}

fn fakeUnameFailure(_: ?*anyopaque, _: *UtsName) c_int {
    std.c._errno().* = EINVAL;
    return -1;
}

test "kernel architecture resets output and uses allocator ownership" {
    test_kernel_ops = .{ .uname = fakeUnameSuccess };
    defer test_kernel_ops = null;
    var arch: ?[*:0]u8 = @ptrFromInt(1);
    try testing.expectEqual(@as(u32, 0), TDNFGetKernelArch(&arch));
    try testing.expectEqualStrings("fixture", std.mem.span(arch.?));
    freeCString(arch);
    arch = @ptrFromInt(1);

    test_kernel_ops = .{ .uname = fakeUnameFailure };
    try testing.expectEqual(systemError(EINVAL), TDNFGetKernelArch(&arch));
    try testing.expect(arch == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetKernelArch(null),
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_OUT_OF_MEMORY,
        getKernelArchWithOps(
            &arch,
            failing_memory_ops,
            .{ .uname = fakeUnameSuccess },
        ),
    );
    try testing.expect(arch == null);
}

test "metadata expiry preserves strtol suffix errno and wrapping semantics" {
    const cases = [_]struct {
        input: [*:0]const u8,
        expected: c_long,
    }{
        .{ .input = "never", .expected = -1 },
        .{ .input = "NeVeR", .expected = -1 },
        .{ .input = "-8garbage", .expected = -1 },
        .{ .input = "0", .expected = 0 },
        .{ .input = " 0", .expected = 0 },
        .{ .input = "1", .expected = 1 },
        .{ .input = "2s", .expected = 2 },
        .{ .input = "3mignored", .expected = 180 },
        .{ .input = "4h", .expected = 14400 },
        .{ .input = "5d", .expected = 432000 },
    };
    for (cases) |case| {
        var output: c_long = 99;
        try testing.expectEqual(
            @as(u32, 0),
            TDNFParseMetadataExpire(case.input, &output),
        );
        try testing.expectEqual(case.expected, output);
    }

    for ([_][*:0]const u8{ "abc", "0s", "1H", "1.5h", " " }) |input| {
        var output: c_long = 99;
        try testing.expectEqual(
            errors.ERROR_TDNF_METADATA_EXPIRE_PARSE,
            TDNFParseMetadataExpire(input, &output),
        );
        try testing.expectEqual(@as(c_long, 0), output);
    }
    var output: c_long = 99;
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFParseMetadataExpire(null, &output),
    );
    try testing.expectEqual(@as(c_long, 0), output);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFParseMetadataExpire("1", null),
    );

    const overflow_input = try std.fmt.allocPrintSentinel(
        testing.allocator,
        "{d}d",
        .{std.math.maxInt(c_long)},
        0,
    );
    defer testing.allocator.free(overflow_input);
    try testing.expectEqual(
        @as(u32, 0),
        TDNFParseMetadataExpire(overflow_input.ptr, &output),
    );
    try testing.expectEqual(
        @as(c_long, std.math.maxInt(c_long)) *% @as(c_long, 86400),
        output,
    );
}

test "append path preserves slash byte and allocation contracts" {
    const cases = [_]struct {
        base: [*:0]const u8,
        part: [*:0]const u8,
        expected: []const u8,
    }{
        .{ .base = "/a", .part = "b", .expected = "/a/b" },
        .{ .base = "/a/", .part = "b", .expected = "/a/b" },
        .{ .base = "/a", .part = "/b", .expected = "/a/b" },
        .{ .base = "/", .part = "b", .expected = "/b" },
        .{ .base = "//", .part = "b", .expected = "//b" },
        .{ .base = "a//", .part = "b", .expected = "a//b" },
    };
    for (cases) |case| {
        var output: ?[*:0]u8 = null;
        try testing.expectEqual(
            @as(u32, 0),
            TDNFAppendPath(case.base, case.part, &output),
        );
        try testing.expectEqualStrings(case.expected, std.mem.span(output.?));
        freeCString(output);
    }

    const invalid_utf8 = [_:0]u8{ 0xff, 'x' };
    var output: ?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFAppendPath("/base", &invalid_utf8, &output),
    );
    try testing.expectEqualSlices(
        u8,
        &.{ '/', 'b', 'a', 's', 'e', '/', 0xff, 'x' },
        std.mem.span(output.?),
    );
    freeCString(output);
    output = @ptrFromInt(1);

    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFAppendPath("", "part", &output),
    );
    try testing.expect(output == null);
    output = @ptrFromInt(1);
    try testing.expectEqual(
        errors.ERROR_TDNF_OUT_OF_MEMORY,
        appendPathWithOps("base", "part", &output, failing_memory_ops),
    );
    try testing.expect(output == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFAppendPath("base", "part", null),
    );
}

const FreeTracker = struct {
    pointers: [16]usize = [_]usize{0} ** 16,
    count: usize = 0,
};

fn trackingFree(context: ?*anyopaque, value: ?*anyopaque) void {
    const ptr = value orelse return;
    const tracker: *FreeTracker = @ptrCast(@alignCast(context.?));
    tracker.pointers[tracker.count] = @intFromPtr(ptr);
    tracker.count += 1;
}

fn unusedAllocateMemory(
    _: ?*anyopaque,
    _: usize,
    _: usize,
    _: *?*anyopaque,
) u32 {
    unreachable;
}

fn unusedAllocateString(
    _: ?*anyopaque,
    _: [*:0]const u8,
    _: *?[*:0]u8,
) u32 {
    unreachable;
}

test "history free helpers release every owned partial allocation" {
    var tracker = FreeTracker{};
    const ops = MemoryOps{
        .context = &tracker,
        .allocateMemory = unusedAllocateMemory,
        .allocateString = unusedAllocateString,
        .free = trackingFree,
    };
    var added = [_]?[*:0]u8{
        @ptrFromInt(0x1010),
        null,
    };
    var removed = [_]?[*:0]u8{
        @ptrFromInt(0x2020),
        @ptrFromInt(0x3030),
    };
    var items = [_]HistoryInfoItem{
        .{
            .pszCmdLine = @ptrFromInt(0x4040),
            .nAddedCount = 2,
            .nRemovedCount = 2,
            .ppszAddedPkgs = &added,
            .ppszRemovedPkgs = &removed,
        },
        .{},
    };
    freeHistoryInfoItemsWithOps(&items, 1, ops);
    try testing.expectEqual(@as(usize, 7), tracker.count);
    try testing.expectEqual(@as(usize, 0x4040), tracker.pointers[0]);
    try testing.expectEqual(@as(usize, 0x1010), tracker.pointers[1]);
    try testing.expectEqual(@intFromPtr(&added), tracker.pointers[2]);
    try testing.expectEqual(@as(usize, 0x2020), tracker.pointers[3]);
    try testing.expectEqual(@as(usize, 0x3030), tracker.pointers[4]);
    try testing.expectEqual(@intFromPtr(&removed), tracker.pointers[5]);
    try testing.expectEqual(@intFromPtr(&items), tracker.pointers[6]);

    tracker.count = 0;
    freeHistoryInfoItemsWithOps(&items, -1, ops);
    try testing.expectEqual(@as(usize, 1), tracker.count);
    TDNFFreeHistoryInfoItems(null, 2);
    TDNFFreeHistoryInfo(null);
}

test "public history free helpers accept allocator-compatible ownership" {
    var raw_items: ?*anyopaque = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFAllocateMemory(1, @sizeOf(HistoryInfoItem), &raw_items),
    );
    const items: [*]HistoryInfoItem = @ptrCast(@alignCast(raw_items.?));
    items[0] = .{};
    try testing.expectEqual(
        @as(u32, 0),
        TDNFAllocateString("command", &items[0].pszCmdLine),
    );
    TDNFFreeHistoryInfoItems(items, 1);

    var raw_info: ?*anyopaque = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFAllocateMemory(1, @sizeOf(HistoryInfo), &raw_info),
    );
    const info: *HistoryInfo = @ptrCast(@alignCast(raw_info.?));
    info.* = .{};
    TDNFFreeHistoryInfo(info);
}

test "distro error logs remain visible in quiet and JSON modes" {
    var descriptors: [2]c_int = undefined;
    try testing.expectEqual(@as(c_int, 0), libc.pipe(&descriptors));
    defer _ = libc.close(descriptors[0]);
    var write_open = true;
    defer {
        if (write_open) _ = libc.close(descriptors[1]);
    }

    const saved_stderr = libc.dup(stderr_fileno);
    try testing.expect(saved_stderr >= 0);
    defer _ = libc.close(saved_stderr);
    try testing.expectEqual(
        stderr_fileno,
        libc.dup2(descriptors[1], stderr_fileno),
    );
    var restored = false;
    defer {
        if (!restored) _ = libc.dup2(saved_stderr, stderr_fileno);
    }

    var fake = FakeRpmContext{ .resolve_result = -1 };
    var output: ?[*:0]u8 = @ptrFromInt(1);
    GlobalSetQuiet(1);
    try testing.expectEqual(
        errors.ERROR_TDNF_DISTROVERPKG_READ,
        releaseVersionConfigWithOps(
            @ptrFromInt(1),
            "quiet-release",
            &output,
            production_memory_ops,
            fakeRpmOps(&fake),
        ),
    );
    try testing.expect(output == null);

    fake.create_failure = true;
    GlobalSetJson(1);
    try testing.expectEqual(
        errors.ERROR_TDNF_DISTROVERPKG_READ,
        releaseVersionWithOps(
            "/json-root",
            "json-release",
            &output,
            production_memory_ops,
            fakeRpmOps(&fake),
        ),
    );
    try testing.expect(output == null);
    try testing.expectEqual(@as(c_int, 0), libc.fflush(null));

    try testing.expectEqual(
        stderr_fileno,
        libc.dup2(saved_stderr, stderr_fileno),
    );
    restored = true;
    _ = libc.close(descriptors[1]);
    write_open = false;

    var buffer: [512]u8 = undefined;
    const length = libc.read(descriptors[0], &buffer, buffer.len);
    try testing.expect(length >= 0);
    const captured = buffer[0..@intCast(length)];
    try testing.expect(std.mem.indexOf(
        u8,
        captured,
        "Failed to read distroverpkg provider 'quiet-release': injected",
    ) != null);
    try testing.expect(std.mem.indexOf(
        u8,
        captured,
        "Failed to initialize native rpm configuration: injected",
    ) != null);
}
