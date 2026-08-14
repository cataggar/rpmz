// Copyright (C) 2020-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("tdnf_common");
const builtin = @import("builtin");
const abi = @import("client_abi");
const errors = @import("tdnf_error");
const backend = @import("builtin_plugins");
const plugin_metadata = @import("plugin_metadata");
const txn_config = @import("rpm_txn_config");

const CnfNode = abi.CnfNode;
const CmdArgs = abi.CmdArgs;
const Conf = abi.Conf;
const Plugin = abi.Plugin;
const PinnedDirectory = plugin_metadata.PinnedDirectory;
const PinnedFile = plugin_metadata.PinnedFile;
const RepoData = abi.RepoData;
const Tdnf = abi.Tdnf;

const CnfModule = opaque {};
const FILE = opaque {};

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const F_OK: c_int = 0;

const ERROR_TDNF_NO_PLUGIN_CONF_DIR: u32 = 1518;
const metalink_kind: c_uint = 0;
const repogpgcheck_kind: c_uint = 1;

const PluginDesc = struct {
    name: [*:0]const u8,
    kind: c_uint,
};

const builtins = [_]PluginDesc{
    .{ .name = "tdnfmetalink", .kind = metalink_kind },
    .{ .name = "tdnfrepogpgcheck", .kind = repogpgcheck_kind },
};

pub const DownloadPinnedFn = *const fn (
    ?*Tdnf,
    ?*RepoData,
    ?[*:0]const u8,
    ?*const PinnedDirectory,
    ?[*:0]const u8,
    ?[*:0]const u8,
    c_int,
    ?*PinnedFile,
) u32;

var test_download_pinned: ?DownloadPinnedFn = null;

pub fn setTestDownloadPinned(callback: ?DownloadPinnedFn) void {
    if (builtin.is_test) test_download_pinned = callback;
}

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
extern fn find_cnfmodule(name: ?[*:0]const u8) callconv(.c) ?*CnfModule;
extern fn cnfmodule_parse_file(
    module: ?*CnfModule,
    path: ?[*:0]const u8,
) callconv(.c) ?*CnfNode;
extern fn cnfmodule_parse(
    module: ?*CnfModule,
    stream: ?*FILE,
) callconv(.c) ?*CnfNode;
extern fn fdopen(fd: c_int, mode: [*:0]const u8) callconv(.c) ?*FILE;
extern fn fclose(stream: *FILE) callconv(.c) c_int;
extern fn destroy_cnfnode(node: ?*CnfNode) callconv(.c) void;
extern fn isTrue(value: ?[*:0]const u8) callconv(.c) c_int;
extern fn register_ini(root: ?*CnfNode) callconv(.c) void;
extern fn access(path: ?[*:0]const u8, mode: c_int) callconv(.c) c_int;
extern fn fnmatch(
    pattern: [*:0]const u8,
    value: [*:0]const u8,
    flags: c_int,
) callconv(.c) c_int;
extern fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]const u8;

const Production = if (builtin.is_test) struct {
    fn findRepo(
        tdnf_opt: ?*Tdnf,
        id_opt: ?[*:0]const u8,
        output: *?*RepoData,
    ) u32 {
        output.* = null;
        const tdnf = tdnf_opt orelse
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        const id = id_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
        var repo = tdnf.pRepos;
        while (repo) |current| : (repo = current.pNext) {
            if (current.pszId) |candidate| {
                if (std.mem.eql(
                    u8,
                    std.mem.span(candidate),
                    std.mem.span(id),
                )) {
                    output.* = current;
                    return 0;
                }
            }
        }
        return errors.ERROR_TDNF_REPO_NOT_FOUND;
    }

    fn downloadFilePinned(
        tdnf: ?*Tdnf,
        repo: ?*RepoData,
        source: ?[*:0]const u8,
        destination: ?*const PinnedDirectory,
        destination_name: ?[*:0]const u8,
        progress: ?[*:0]const u8,
        from_repo: c_int,
        output: ?*PinnedFile,
    ) u32 {
        if (output) |value| value.* = .{};
        if (test_download_pinned) |callback| {
            return callback(
                tdnf,
                repo,
                source,
                destination,
                destination_name,
                progress,
                from_repo,
                output,
            );
        }
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
} else struct {
    extern fn TDNFFindRepoById(
        tdnf: ?*Tdnf,
        id: ?[*:0]const u8,
        output: *?*RepoData,
    ) callconv(.c) u32;
    extern fn TDNFDownloadFilePinned(
        tdnf: ?*Tdnf,
        repo: ?*RepoData,
        source: ?[*:0]const u8,
        destination: ?*const PinnedDirectory,
        destination_name: ?[*:0]const u8,
        progress: ?[*:0]const u8,
        from_repo: c_int,
        output: ?*PinnedFile,
    ) callconv(.c) u32;

    fn findRepo(
        tdnf: ?*Tdnf,
        id: ?[*:0]const u8,
        output: *?*RepoData,
    ) u32 {
        return TDNFFindRepoById(tdnf, id, output);
    }

    fn downloadFilePinned(
        tdnf: ?*Tdnf,
        repo: ?*RepoData,
        source: ?[*:0]const u8,
        destination: ?*const PinnedDirectory,
        destination_name: ?[*:0]const u8,
        progress: ?[*:0]const u8,
        from_repo: c_int,
        output: ?*PinnedFile,
    ) u32 {
        return TDNFDownloadFilePinned(
            tdnf,
            repo,
            source,
            destination,
            destination_name,
            progress,
            from_repo,
            output,
        );
    }
};

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
    allocate_path: *const fn (
        context: ?*anyopaque,
        directory: ?[*:0]const u8,
        name: [*:0]const u8,
        output: *?[*:0]u8,
    ) u32,
    create_metalink: *const fn (
        context: ?*anyopaque,
        tdnf: ?*Tdnf,
        output: *?*anyopaque,
    ) u32,
    destroy_metalink: *const fn (
        context: ?*anyopaque,
        handle: ?*anyopaque,
    ) void,
    metalink_repo_config: *const fn (
        context: ?*anyopaque,
        handle: ?*anyopaque,
        section: ?*const CnfNode,
    ) u32,
    metalink_repo_md_start: *const fn (
        context: ?*anyopaque,
        handle: ?*anyopaque,
        repo_id: ?[*:0]const u8,
        repo_data_dir: ?*const PinnedDirectory,
    ) u32,
    metalink_repo_md_end: *const fn (
        context: ?*anyopaque,
        handle: ?*anyopaque,
        repo_id: ?[*:0]const u8,
        repomd_file: ?*const PinnedFile,
    ) u32,
    create_repogpgcheck: *const fn (
        context: ?*anyopaque,
        tdnf: ?*Tdnf,
        output: *?*anyopaque,
    ) u32,
    destroy_repogpgcheck: *const fn (
        context: ?*anyopaque,
        handle: ?*anyopaque,
    ) void,
    repogpgcheck_repo_config: *const fn (
        context: ?*anyopaque,
        handle: ?*anyopaque,
        section: ?*const CnfNode,
    ) u32,
    repogpgcheck_repo_md_end: *const fn (
        context: ?*anyopaque,
        handle: ?*anyopaque,
        repo_id: ?[*:0]const u8,
        repomd_file: ?*const PinnedFile,
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

fn productionAllocatePath(
    _: ?*anyopaque,
    directory: ?[*:0]const u8,
    name: [*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    return common.allocPrint(output, "%s/%s.conf", .{ directory, name });
}

fn productionCreateMetalink(
    _: ?*anyopaque,
    tdnf: ?*Tdnf,
    output: *?*anyopaque,
) u32 {
    return backend.BuiltinMetalinkCreate(tdnf, output);
}

fn productionDestroyMetalink(_: ?*anyopaque, handle: ?*anyopaque) void {
    backend.BuiltinMetalinkDestroy(handle);
}

fn productionMetalinkRepoConfig(
    _: ?*anyopaque,
    handle: ?*anyopaque,
    section: ?*const CnfNode,
) u32 {
    return backend.BuiltinMetalinkRepoConfig(handle, @ptrCast(section));
}

fn productionMetalinkRepoMDStart(
    _: ?*anyopaque,
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
    repo_data_dir: ?*const PinnedDirectory,
) u32 {
    return backend.BuiltinMetalinkRepoMDDownloadStart(
        handle,
        repo_id,
        repo_data_dir,
    );
}

fn productionMetalinkRepoMDEnd(
    _: ?*anyopaque,
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
    repomd_file: ?*const PinnedFile,
) u32 {
    return backend.BuiltinMetalinkRepoMDDownloadEnd(
        handle,
        repo_id,
        repomd_file,
    );
}

fn productionCreateRepoGPGCheck(
    _: ?*anyopaque,
    tdnf: ?*Tdnf,
    output: *?*anyopaque,
) u32 {
    return backend.BuiltinRepoGPGCheckCreate(tdnf, output);
}

fn productionDestroyRepoGPGCheck(_: ?*anyopaque, handle: ?*anyopaque) void {
    backend.BuiltinRepoGPGCheckDestroy(handle);
}

fn productionRepoGPGCheckRepoConfig(
    _: ?*anyopaque,
    handle: ?*anyopaque,
    section: ?*const CnfNode,
) u32 {
    return backend.BuiltinRepoGPGCheckRepoConfig(handle, @ptrCast(section));
}

fn productionRepoGPGCheckRepoMDEnd(
    _: ?*anyopaque,
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
    repomd_file: ?*const PinnedFile,
) u32 {
    return backend.BuiltinRepoGPGCheckRepoMDDownloadEnd(
        handle,
        repo_id,
        repomd_file,
    );
}

const production_ops = Ops{
    .allocate_memory = productionAllocateMemory,
    .allocate_string = productionAllocateString,
    .allocate_path = productionAllocatePath,
    .create_metalink = productionCreateMetalink,
    .destroy_metalink = productionDestroyMetalink,
    .metalink_repo_config = productionMetalinkRepoConfig,
    .metalink_repo_md_start = productionMetalinkRepoMDStart,
    .metalink_repo_md_end = productionMetalinkRepoMDEnd,
    .create_repogpgcheck = productionCreateRepoGPGCheck,
    .destroy_repogpgcheck = productionDestroyRepoGPGCheck,
    .repogpgcheck_repo_config = productionRepoGPGCheckRepoConfig,
    .repogpgcheck_repo_md_end = productionRepoGPGCheckRepoMDEnd,
};

fn isNullOrEmpty(value: ?[*:0]const u8) bool {
    const ptr = value orelse return true;
    return ptr[0] == 0;
}

fn validPinnedDirectory(value: ?*const PinnedDirectory) bool {
    return value != null and value.?.fd >= 0;
}

fn validPinnedFile(value: ?*const PinnedFile) bool {
    const file = value orelse return false;
    return file.fd >= 0 and file.directory_fd >= 0 and
        !isNullOrEmpty(file.name);
}

fn systemError() u32 {
    return errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(std.c._errno().*));
}

fn freeString(value: *?[*:0]u8) void {
    TDNFFreeMemory(value.*);
    value.* = null;
}

fn loadPluginConfigTree(
    config: *CnfNode,
    desc: ?*const PluginDesc,
    output: ?*?*Plugin,
    ops: Ops,
) u32 {
    if (desc == null or output == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var raw: ?*anyopaque = null;
    var result = ops.allocate_memory(
        ops.context,
        1,
        @sizeOf(Plugin),
        &raw,
    );
    if (result != 0) return result;
    const plugin: *Plugin = @ptrCast(@alignCast(raw.?));
    plugin.* = .{};

    result = ops.allocate_string(
        ops.context,
        desc.?.name,
        &plugin.pszName,
    );
    if (result != 0) {
        TDNFFreeMemory(plugin);
        return result;
    }
    plugin.nKind = desc.?.kind;

    var section = config.first_child;
    while (section) |current_section| : (section = current_section.next) {
        const section_name = current_section.name orelse continue;
        if (section_name[0] == '.' or
            !std.mem.eql(u8, std.mem.span(section_name), "main"))
        {
            continue;
        }
        var node = current_section.first_child;
        while (node) |current| : (node = current.next) {
            const name = current.name orelse continue;
            const value = current.value orelse continue;
            if (name[0] == '.') continue;
            if (std.mem.eql(u8, std.mem.span(name), "enabled"))
                plugin.nEnabled = isTrue(value);
        }
    }

    output.?.* = plugin;
    return 0;
}

fn loadPluginConfig(
    config_file: ?[*:0]const u8,
    desc: ?*const PluginDesc,
    output: ?*?*Plugin,
    ops: Ops,
) u32 {
    if (isNullOrEmpty(config_file) or desc == null or output == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (access(config_file, F_OK) != 0) {
        if (std.c._errno().* == @intFromEnum(std.c.E.NOENT)) return 0;
        return systemError();
    }
    const module = find_cnfmodule("ini") orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const config = cnfmodule_parse_file(module, config_file) orelse {
        if (std.c._errno().* != 0) return systemError();
        return errors.ERROR_TDNF_CONF_FILE_LOAD;
    };
    defer destroy_cnfnode(config);
    return loadPluginConfigTree(config, desc, output, ops);
}

fn loadPluginConfigAt(
    directory_fd: c_int,
    name: [*:0]const u8,
    desc: *const PluginDesc,
    output: *?*Plugin,
    ops: Ops,
) u32 {
    const fd = std.c.openat(directory_fd, name, .{
        .ACCMODE = .RDONLY,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    if (fd < 0) {
        if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT)) return 0;
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
    const stream = fdopen(fd, "r") orelse {
        _ = std.c.close(fd);
        return systemError();
    };
    defer _ = fclose(stream);
    const module = find_cnfmodule("ini") orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const config = cnfmodule_parse(module, stream) orelse
        return errors.ERROR_TDNF_CONF_FILE_LOAD;
    defer destroy_cnfnode(config);
    return loadPluginConfigTree(config, desc, output, ops);
}

fn freePlugins(plugins_opt: ?*Plugin, ops: Ops) void {
    var plugins = plugins_opt;
    while (plugins) |plugin| {
        const next = plugin.pNext;
        if (plugin.pHandle != null) {
            if (plugin.nKind == metalink_kind)
                ops.destroy_metalink(ops.context, plugin.pHandle)
            else
                ops.destroy_repogpgcheck(ops.context, plugin.pHandle);
        }
        freeString(&plugin.pszName);
        TDNFFreeMemory(plugin);
        plugins = next;
    }
}

fn loadPluginConfigs(
    tdnf_opt: ?*Tdnf,
    output: ?*?*Plugin,
    ops: Ops,
) u32 {
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const conf = tdnf.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;

    var pinned_directory: c_int = -1;
    defer {
        if (pinned_directory >= 0) _ = std.c.close(pinned_directory);
    }
    if (tdnf.pRpmConfig) |raw| {
        const config: *const txn_config.TxnConfig =
            @ptrCast(@alignCast(raw));
        const path = std.mem.span(conf.pszPluginConfPath.?);
        if (config.pluginConfDirUsesPinnedRoot(path)) {
            pinned_directory = config.openPinnedDirectory(
                path,
                false,
            ) catch |err| return switch (err) {
                error.NotFound => ERROR_TDNF_NO_PLUGIN_CONF_DIR,
                error.InvalidTargetPath,
                error.UnsafeTargetPath,
                => errors.ERROR_TDNF_INVALID_PARAMETER,
                error.SyscallFailed => systemError(),
            };
        }
    }
    if (pinned_directory < 0 and access(conf.pszPluginConfPath, F_OK) != 0) {
        if (std.c._errno().* == @intFromEnum(std.c.E.NOENT))
            return ERROR_TDNF_NO_PLUGIN_CONF_DIR;
        return systemError();
    }

    var plugins: ?*Plugin = null;
    var last: ?*Plugin = null;
    for (&builtins) |*desc| {
        var config: ?[*:0]u8 = null;
        var result = ops.allocate_path(
            ops.context,
            conf.pszPluginConfPath,
            desc.name,
            &config,
        );
        if (result != 0) {
            freePlugins(plugins, ops);
            return result;
        }

        var plugin: ?*Plugin = null;
        result = if (pinned_directory >= 0) blk: {
            const full = std.mem.span(config.?);
            const basename = std.fs.path.basename(full);
            if (basename.len == 0 or
                basename.len > std.fs.max_name_bytes or
                std.mem.indexOfScalar(u8, basename, '/') != null)
            {
                break :blk errors.ERROR_TDNF_INVALID_PARAMETER;
            }
            const name_z = std.heap.c_allocator.dupeZ(
                u8,
                basename,
            ) catch break :blk errors.ERROR_TDNF_OUT_OF_MEMORY;
            defer std.heap.c_allocator.free(name_z);
            break :blk loadPluginConfigAt(
                pinned_directory,
                name_z.ptr,
                desc,
                &plugin,
                ops,
            );
        } else loadPluginConfig(config, desc, &plugin, ops);
        freeString(&config);
        if (result != 0) {
            freePlugins(plugins, ops);
            return result;
        }
        const loaded = plugin orelse continue;
        if (plugins == null) {
            plugins = loaded;
            last = loaded;
        } else {
            last.?.pNext = loaded;
            last = loaded;
        }
    }

    out.* = plugins;
    return 0;
}

fn isGlob(name: [*:0]const u8) bool {
    for (std.mem.span(name)) |ch| {
        if (ch == '*' or ch == '?' or ch == '[') return true;
    }
    return false;
}

fn alterPluginState(
    plugins_opt: ?*Plugin,
    enable: c_int,
    name_opt: ?[*:0]const u8,
) u32 {
    var plugin = plugins_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (isNullOrEmpty(name_opt)) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const name = name_opt.?;
    const glob = isGlob(name);
    while (true) {
        const plugin_name = plugin.pszName orelse
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        const matches = if (glob)
            fnmatch(name, plugin_name, 0) == 0
        else
            std.mem.orderZ(u8, name, plugin_name) == .eq;
        if (matches) {
            plugin.nEnabled = enable;
            if (!glob) break;
        }
        plugin = plugin.pNext orelse break;
    }
    return 0;
}

fn applyPluginOverrides(tdnf: *Tdnf, plugins: *Plugin) u32 {
    const args = tdnf.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const setopts = args.cn_setopts orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var node = setopts.first_child;
    while (node) |current| : (node = current.next) {
        const name = current.name orelse continue;
        const result = if (std.mem.eql(u8, std.mem.span(name), "enableplugin"))
            alterPluginState(plugins, 1, current.value)
        else if (std.mem.eql(u8, std.mem.span(name), "disableplugin"))
            alterPluginState(plugins, 0, current.value)
        else
            continue;
        if (result != 0) return result;
    }
    return 0;
}

fn pluginErrorDescription(plugin: *const Plugin, result: u32) [*:0]const u8 {
    if (plugin.nKind == repogpgcheck_kind) {
        return switch (result) {
            2001 => "unknown error",
            2002 => "version failed",
            2003 => "failed to verify result",
            2004 => "failed to verify signature",
            else => "unknown error",
        };
    }
    return switch (result) {
        2701 => "Failed to parse and create document tree",
        2702 => "Root element not found",
        2703 => "Missing filename in metalink file",
        2704 => "Invalid filename present",
        2705 => "Missing file size in metalink file",
        2706 => "Missing attribute in hash tag",
        2707 => "Missing content in hash tag value",
        2708 => "Missing attribute in url tag",
        2709 => "Missing content in url tag value",
        else => "unknown error",
    };
}

fn showPluginError(plugin_opt: ?*Plugin, result: u32) void {
    const plugin = plugin_opt orelse return;
    if (result == 0) return;
    const prefix: [*:0]const u8 = if (plugin.nKind == metalink_kind)
        "metalink plugin error"
    else
        "repogpgcheck plugin error";
    common.log(LOG_ERR, "Plugin error: %s: %s\n", .{ prefix, pluginErrorDescription(plugin, result) });
}

fn initPlugin(tdnf: *Tdnf, plugin: *Plugin, ops: Ops) u32 {
    const result = if (plugin.nKind == metalink_kind)
        ops.create_metalink(ops.context, tdnf, &plugin.pHandle)
    else
        ops.create_repogpgcheck(ops.context, tdnf, &plugin.pHandle);
    if (result != 0) {
        showPluginError(plugin, result);
        return result;
    }
    common.log(LOG_INFO, "Loaded plugin: %s\n", .{plugin.pszName});
    return 0;
}

fn loadPlugins(tdnf_opt: ?*Tdnf, ops: Ops) u32 {
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const args = tdnf.pArgs orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const conf = tdnf.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (conf.nPluginsEnabled == 0) return 0;

    const setopts = args.cn_setopts orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var option = setopts.first_child;
    while (option) |current| : (option = current.next) {
        if (current.name) |name| {
            if (std.mem.eql(u8, std.mem.span(name), "noplugins")) return 0;
        }
    }

    var plugins: ?*Plugin = null;
    var result = loadPluginConfigs(tdnf, &plugins, ops);
    if (result == ERROR_TDNF_NO_PLUGIN_CONF_DIR) return 0;
    if (result != 0) return result;

    if (plugins) |head| {
        result = applyPluginOverrides(tdnf, head);
        if (result != 0) {
            freePlugins(plugins, ops);
            return result;
        }
    }
    var plugin = plugins;
    while (plugin) |current| : (plugin = current.pNext) {
        if (current.nEnabled == 0) continue;
        result = initPlugin(tdnf, current, ops);
        if (result != 0) {
            freePlugins(plugins, ops);
            return result;
        }
    }

    tdnf.pPlugins = plugins;
    return 0;
}

fn pluginsRepoConfig(
    tdnf_opt: ?*Tdnf,
    section_opt: ?*const CnfNode,
    ops: Ops,
) u32 {
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const section = section_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var plugin = tdnf.pPlugins;
    while (plugin) |current| : (plugin = current.pNext) {
        if (current.nEnabled == 0) continue;
        const result = if (current.nKind == metalink_kind)
            ops.metalink_repo_config(ops.context, current.pHandle, section)
        else
            ops.repogpgcheck_repo_config(ops.context, current.pHandle, section);
        if (result != 0) {
            showPluginError(current, result);
            return result;
        }
    }
    return 0;
}

fn pluginsRepoMDDownloadStart(
    tdnf_opt: ?*Tdnf,
    repo_id: ?[*:0]const u8,
    repo_data_dir: ?*const PinnedDirectory,
    ops: Ops,
) u32 {
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (isNullOrEmpty(repo_id) or !validPinnedDirectory(repo_data_dir))
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var plugin = tdnf.pPlugins;
    while (plugin) |current| : (plugin = current.pNext) {
        if (current.nEnabled == 0 or current.nKind != metalink_kind) continue;
        const result = ops.metalink_repo_md_start(
            ops.context,
            current.pHandle,
            repo_id,
            repo_data_dir,
        );
        if (result != 0) {
            showPluginError(current, result);
            return result;
        }
    }
    return 0;
}

fn pluginsRepoMDDownloadEnd(
    tdnf_opt: ?*Tdnf,
    repo_id: ?[*:0]const u8,
    repomd_file: ?*const PinnedFile,
    ops: Ops,
) u32 {
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (isNullOrEmpty(repo_id) or !validPinnedFile(repomd_file))
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var plugin = tdnf.pPlugins;
    while (plugin) |current| : (plugin = current.pNext) {
        if (current.nEnabled == 0) continue;
        const result = if (current.nKind == metalink_kind)
            ops.metalink_repo_md_end(
                ops.context,
                current.pHandle,
                repo_id,
                repomd_file,
            )
        else
            ops.repogpgcheck_repo_md_end(
                ops.context,
                current.pHandle,
                repo_id,
                repomd_file,
            );
        if (result != 0) {
            showPluginError(current, result);
            return result;
        }
    }
    return 0;
}

export fn TDNFLoadPlugins(tdnf: ?*Tdnf) callconv(.c) u32 {
    return loadPlugins(tdnf, production_ops);
}

export fn TDNFFreePlugins(plugins: ?*Plugin) callconv(.c) void {
    freePlugins(plugins, production_ops);
}

export fn BuiltinPluginsRepoConfig(
    tdnf: ?*Tdnf,
    section: ?*const CnfNode,
) callconv(.c) u32 {
    return pluginsRepoConfig(tdnf, section, production_ops);
}

export fn BuiltinPluginsRepoMDDownloadStart(
    tdnf: ?*Tdnf,
    repo_id: ?[*:0]const u8,
    repo_data_dir: ?*const PinnedDirectory,
) callconv(.c) u32 {
    return pluginsRepoMDDownloadStart(
        tdnf,
        repo_id,
        repo_data_dir,
        production_ops,
    );
}

export fn BuiltinPluginsRepoMDDownloadEnd(
    tdnf: ?*Tdnf,
    repo_id: ?[*:0]const u8,
    repomd_file: ?*const PinnedFile,
) callconv(.c) u32 {
    return pluginsRepoMDDownloadEnd(
        tdnf,
        repo_id,
        repomd_file,
        production_ops,
    );
}

export fn BuiltinRefreshRequested(handle: ?*anyopaque) callconv(.c) c_int {
    const tdnf: *Tdnf = @ptrCast(@alignCast(handle orelse return 0));
    const args = tdnf.pArgs orelse return 0;
    return args.nRefresh;
}

export fn BuiltinGetEnv(
    name: ?[*:0]const u8,
) callconv(.c) ?[*:0]const u8 {
    return getenv(name orelse return null);
}

export fn BuiltinFindRepo(
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
    output: ?*?*anyopaque,
) callconv(.c) u32 {
    const out = output orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var repo: ?*RepoData = null;
    const result = Production.findRepo(
        @ptrCast(@alignCast(handle)),
        repo_id,
        &repo,
    );
    out.* = repo;
    return result;
}

export fn BuiltinDownloadMetalink(
    handle: ?*anyopaque,
    repo_handle: ?*anyopaque,
    destination: ?*const PinnedDirectory,
    destination_name: ?[*:0]const u8,
    output: ?*PinnedFile,
) callconv(.c) u32 {
    if (output) |value| value.* = .{};
    const tdnf: *Tdnf = @ptrCast(@alignCast(handle orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER));
    const repo: *RepoData = @ptrCast(@alignCast(repo_handle orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER));
    if (isNullOrEmpty(repo.pszMetaLink) or
        !validPinnedDirectory(destination) or
        isNullOrEmpty(destination_name) or output == null)
    {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    return Production.downloadFilePinned(
        tdnf,
        repo,
        repo.pszMetaLink,
        destination,
        destination_name,
        repo.pszId,
        0,
        output,
    );
}

export fn BuiltinDownloadRepoFile(
    handle: ?*anyopaque,
    repo_handle: ?*anyopaque,
    location: ?[*:0]const u8,
    destination: ?*const PinnedDirectory,
    destination_name: ?[*:0]const u8,
    progress: ?[*:0]const u8,
    output: ?*PinnedFile,
) callconv(.c) u32 {
    if (output) |value| value.* = .{};
    if (isNullOrEmpty(location) or
        !validPinnedDirectory(destination) or
        isNullOrEmpty(destination_name) or output == null)
    {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    return Production.downloadFilePinned(
        @ptrCast(@alignCast(handle)),
        @ptrCast(@alignCast(repo_handle)),
        location,
        destination,
        destination_name,
        progress,
        1,
        output,
    );
}

export fn BuiltinReplaceBaseUrls(
    repo_handle: ?*anyopaque,
    base_urls: ?[*]?[*:0]u8,
) callconv(.c) void {
    const repo: *RepoData = @ptrCast(@alignCast(repo_handle orelse {
        TDNFFreeStringArray(base_urls);
        return;
    }));
    TDNFFreeStringArray(repo.ppszBaseUrls);
    repo.ppszBaseUrls = base_urls;
}

const testing = std.testing;
var test_ini_registered = false;

const TestState = struct {
    allocations: usize = 0,
    fail_allocation_at: usize = std.math.maxInt(usize),
    creates: [2]usize = .{ 0, 0 },
    destroys: [2]usize = .{ 0, 0 },
    fail_create_kind: ?c_uint = null,
    fail_event: ?u8 = null,
    sequence: [16]u8 = @splat(0),
    sequence_len: usize = 0,

    fn record(self: *TestState, value: u8) void {
        self.sequence[self.sequence_len] = value;
        self.sequence_len += 1;
    }
};

fn testState(context: ?*anyopaque) *TestState {
    return @ptrCast(@alignCast(context.?));
}

fn testAllocation(state: *TestState) bool {
    state.allocations += 1;
    return state.allocations == state.fail_allocation_at;
}

fn testAllocateMemory(
    context: ?*anyopaque,
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32 {
    if (testAllocation(testState(context))) {
        output.* = null;
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    }
    return TDNFAllocateMemory(count, size, output);
}

fn testAllocateString(
    context: ?*anyopaque,
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    if (testAllocation(testState(context))) {
        output.* = null;
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    }
    return TDNFAllocateString(source, output);
}

fn testAllocatePath(
    context: ?*anyopaque,
    directory: ?[*:0]const u8,
    name: [*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    if (testAllocation(testState(context))) {
        output.* = null;
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    }
    return common.allocPrint(output, "%s/%s.conf", .{ directory, name });
}

fn testCreate(
    context: ?*anyopaque,
    kind: c_uint,
    output: *?*anyopaque,
) u32 {
    const state = testState(context);
    state.creates[kind] += 1;
    if (state.fail_create_kind == kind) return 2004;
    output.* = @ptrFromInt(kind + 1);
    return 0;
}

fn testCreateMetalink(
    context: ?*anyopaque,
    _: ?*Tdnf,
    output: *?*anyopaque,
) u32 {
    return testCreate(context, metalink_kind, output);
}

fn testCreateRepoGPGCheck(
    context: ?*anyopaque,
    _: ?*Tdnf,
    output: *?*anyopaque,
) u32 {
    return testCreate(context, repogpgcheck_kind, output);
}

fn testDestroy(context: ?*anyopaque, handle: ?*anyopaque) void {
    const kind: usize = @intFromPtr(handle.?) - 1;
    testState(context).destroys[kind] += 1;
}

fn testEvent(
    context: ?*anyopaque,
    code: u8,
    handle: ?*anyopaque,
    first: ?[*:0]const u8,
    second: ?[*:0]const u8,
) u32 {
    const state = testState(context);
    testing.expect(handle != null) catch return 999;
    testing.expect(first != null) catch return 999;
    testing.expect(second != null) catch return 999;
    state.record(code);
    return if (state.fail_event == code) 2704 else 0;
}

fn testMetalinkRepoConfig(
    context: ?*anyopaque,
    handle: ?*anyopaque,
    section: ?*const CnfNode,
) u32 {
    return testEvent(
        context,
        10,
        handle,
        if (section) |value| value.name else null,
        "repo-config",
    );
}

fn testRepoGPGCheckRepoConfig(
    context: ?*anyopaque,
    handle: ?*anyopaque,
    section: ?*const CnfNode,
) u32 {
    return testEvent(
        context,
        11,
        handle,
        if (section) |value| value.name else null,
        "repo-config",
    );
}

fn testMetalinkRepoMDStart(
    context: ?*anyopaque,
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
    repo_data_dir: ?*const PinnedDirectory,
) u32 {
    testing.expect(repo_data_dir != null and repo_data_dir.?.fd >= 0) catch
        return 999;
    return testEvent(context, 20, handle, repo_id, "pinned-directory");
}

fn testMetalinkRepoMDEnd(
    context: ?*anyopaque,
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
    repomd_file: ?*const PinnedFile,
) u32 {
    testing.expect(validPinnedFile(repomd_file)) catch return 999;
    return testEvent(context, 30, handle, repo_id, repomd_file.?.name);
}

fn testRepoGPGCheckRepoMDEnd(
    context: ?*anyopaque,
    handle: ?*anyopaque,
    repo_id: ?[*:0]const u8,
    repomd_file: ?*const PinnedFile,
) u32 {
    testing.expect(validPinnedFile(repomd_file)) catch return 999;
    return testEvent(context, 31, handle, repo_id, repomd_file.?.name);
}

fn testOps(state: *TestState) Ops {
    return .{
        .context = state,
        .allocate_memory = testAllocateMemory,
        .allocate_string = testAllocateString,
        .allocate_path = testAllocatePath,
        .create_metalink = testCreateMetalink,
        .destroy_metalink = testDestroy,
        .metalink_repo_config = testMetalinkRepoConfig,
        .metalink_repo_md_start = testMetalinkRepoMDStart,
        .metalink_repo_md_end = testMetalinkRepoMDEnd,
        .create_repogpgcheck = testCreateRepoGPGCheck,
        .destroy_repogpgcheck = testDestroy,
        .repogpgcheck_repo_config = testRepoGPGCheckRepoConfig,
        .repogpgcheck_repo_md_end = testRepoGPGCheckRepoMDEnd,
    };
}

fn testPlugin(
    name: [*:0]u8,
    enabled: c_int,
    kind: c_uint,
    handle: ?*anyopaque,
) Plugin {
    return .{
        .pszName = name,
        .nEnabled = enabled,
        .nKind = kind,
        .pHandle = handle,
    };
}

fn fixturePath(
    tmp: *std.testing.TmpDir,
    suffix: []const u8,
    buffer: []u8,
) [:0]u8 {
    return std.fmt.bufPrintZ(
        buffer,
        ".zig-cache/tmp/{s}/{s}",
        .{ &tmp.sub_path, suffix },
    ) catch @panic("fixture path too long");
}

fn writePluginConfigs(
    tmp: *std.testing.TmpDir,
    metalink_enabled: bool,
    repogpgcheck_enabled: bool,
) !void {
    if (!test_ini_registered) {
        register_ini(null);
        test_ini_registered = true;
    }
    try tmp.dir.createDirPath(testing.io, "pluginconf.d");
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "pluginconf.d/tdnfmetalink.conf",
        .data = if (metalink_enabled) "[main]\nenabled=true\n" else "[main]\nenabled=false\n",
    });
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "pluginconf.d/tdnfrepogpgcheck.conf",
        .data = if (repogpgcheck_enabled) "[main]\nenabled=1\n" else "[main]\nenabled=0\n",
    });
}

test "plugin ABI layouts match the private canonical definitions" {
    try testing.expectEqual(@sizeOf(abi.C.TDNF_PLUGIN), @sizeOf(Plugin));
    try testing.expectEqual(@alignOf(abi.C.TDNF_PLUGIN), @alignOf(Plugin));
    try testing.expectEqual(@sizeOf(abi.C.TDNF_REPO_DATA), @sizeOf(RepoData));
    try testing.expectEqual(@alignOf(abi.C.TDNF_REPO_DATA), @alignOf(RepoData));
}

test "plugin overrides preserve command order and glob precedence" {
    var metalink = testPlugin(@constCast("tdnfmetalink"), 1, metalink_kind, null);
    var repogpgcheck = testPlugin(
        @constCast("tdnfrepogpgcheck"),
        1,
        repogpgcheck_kind,
        null,
    );
    metalink.pNext = &repogpgcheck;
    var enable = CnfNode{
        .name = @constCast("enableplugin"),
        .value = @constCast("tdnfrepo*"),
    };
    var disable = CnfNode{
        .next = &enable,
        .name = @constCast("disableplugin"),
        .value = @constCast("*"),
    };
    var setopts = CnfNode{ .first_child = &disable };
    var args = CmdArgs{ .cn_setopts = &setopts };
    var tdnf = Tdnf{ .pArgs = &args };

    try testing.expectEqual(@as(u32, 0), applyPluginOverrides(&tdnf, &metalink));
    try testing.expectEqual(@as(c_int, 0), metalink.nEnabled);
    try testing.expectEqual(@as(c_int, 1), repogpgcheck.nEnabled);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        alterPluginState(null, 1, "*"),
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        alterPluginState(&metalink, 1, ""),
    );
}

test "plugin lifecycle initializes, cleans up, and repeats safely" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writePluginConfigs(&tmp, true, true);

    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = fixturePath(&tmp, "pluginconf.d", &path_buffer);
    var setopts = CnfNode{};
    var args = CmdArgs{ .cn_setopts = &setopts };
    var conf = Conf{
        .nPluginsEnabled = 1,
        .pszPluginConfPath = path.ptr,
    };
    var tdnf = Tdnf{ .pArgs = &args, .pConf = &conf };

    var state = TestState{};
    const ops = testOps(&state);
    try testing.expectEqual(@as(u32, 0), loadPlugins(&tdnf, ops));
    try testing.expect(tdnf.pPlugins != null);
    try testing.expectEqual([2]usize{ 1, 1 }, state.creates);
    freePlugins(tdnf.pPlugins, ops);
    tdnf.pPlugins = null;
    try testing.expectEqual([2]usize{ 1, 1 }, state.destroys);

    try testing.expectEqual(@as(u32, 0), loadPlugins(&tdnf, ops));
    freePlugins(tdnf.pPlugins, ops);
    tdnf.pPlugins = null;
    freePlugins(null, ops);
    try testing.expectEqual([2]usize{ 2, 2 }, state.creates);
    try testing.expectEqual([2]usize{ 2, 2 }, state.destroys);
}

test "per-plugin configuration retains disabled entries without initializing them" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writePluginConfigs(&tmp, false, true);

    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = fixturePath(&tmp, "pluginconf.d", &path_buffer);
    var setopts = CnfNode{};
    var args = CmdArgs{ .cn_setopts = &setopts };
    var conf = Conf{
        .nPluginsEnabled = 1,
        .pszPluginConfPath = path.ptr,
    };
    var tdnf = Tdnf{ .pArgs = &args, .pConf = &conf };
    var state = TestState{};
    const ops = testOps(&state);

    try testing.expectEqual(@as(u32, 0), loadPlugins(&tdnf, ops));
    const metalink = tdnf.pPlugins.?;
    const repogpgcheck = metalink.pNext.?;
    try testing.expectEqual(@as(c_int, 0), metalink.nEnabled);
    try testing.expectEqual(@as(c_int, 1), repogpgcheck.nEnabled);
    try testing.expectEqual([2]usize{ 0, 1 }, state.creates);
    freePlugins(tdnf.pPlugins, ops);
    tdnf.pPlugins = null;
    try testing.expectEqual([2]usize{ 0, 1 }, state.destroys);
}

test "plugin events preserve registration, payload, order, and failures" {
    var state = TestState{};
    const ops = testOps(&state);
    var metalink = testPlugin(
        @constCast("tdnfmetalink"),
        1,
        metalink_kind,
        @ptrFromInt(1),
    );
    var disabled = testPlugin(
        @constCast("tdnfmetalink-disabled"),
        0,
        metalink_kind,
        @ptrFromInt(1),
    );
    var repogpgcheck = testPlugin(
        @constCast("tdnfrepogpgcheck"),
        1,
        repogpgcheck_kind,
        @ptrFromInt(2),
    );
    metalink.pNext = &disabled;
    disabled.pNext = &repogpgcheck;
    var tdnf = Tdnf{ .pPlugins = &metalink };
    var section = CnfNode{ .name = @constCast("repo-id") };
    const directory = PinnedDirectory{ .fd = 10 };
    const repomd = PinnedFile{
        .fd = 11,
        .directory_fd = directory.fd,
        .name = "repomd.xml",
    };

    try testing.expectEqual(
        @as(u32, 0),
        pluginsRepoConfig(&tdnf, &section, ops),
    );
    try testing.expectEqual(
        @as(u32, 0),
        pluginsRepoMDDownloadStart(&tdnf, "repo-id", &directory, ops),
    );
    try testing.expectEqual(
        @as(u32, 0),
        pluginsRepoMDDownloadEnd(&tdnf, "repo-id", &repomd, ops),
    );
    try testing.expectEqualSlices(
        u8,
        &.{ 10, 11, 20, 30, 31 },
        state.sequence[0..state.sequence_len],
    );

    const FailureCase = struct {
        code: u8,
        expected: []const u8,
        event: enum { config, start, end },
    };
    const failures = [_]FailureCase{
        .{ .code = 10, .expected = &.{10}, .event = .config },
        .{ .code = 11, .expected = &.{ 10, 11 }, .event = .config },
        .{ .code = 20, .expected = &.{20}, .event = .start },
        .{ .code = 30, .expected = &.{30}, .event = .end },
        .{ .code = 31, .expected = &.{ 30, 31 }, .event = .end },
    };
    for (failures) |failure| {
        state.fail_event = failure.code;
        state.sequence_len = 0;
        const result = switch (failure.event) {
            .config => pluginsRepoConfig(&tdnf, &section, ops),
            .start => pluginsRepoMDDownloadStart(
                &tdnf,
                "repo-id",
                &directory,
                ops,
            ),
            .end => pluginsRepoMDDownloadEnd(
                &tdnf,
                "repo-id",
                &repomd,
                ops,
            ),
        };
        try testing.expectEqual(@as(u32, 2704), result);
        try testing.expectEqualSlices(
            u8,
            failure.expected,
            state.sequence[0..state.sequence_len],
        );
    }
}

test "plugin entry points reject invalid payloads and accept empty lists" {
    var state = TestState{};
    const ops = testOps(&state);
    var tdnf = Tdnf{};
    var section = CnfNode{};
    const directory = PinnedDirectory{ .fd = 10 };

    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        pluginsRepoConfig(null, &section, ops),
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        pluginsRepoConfig(&tdnf, null, ops),
    );
    try testing.expectEqual(@as(u32, 0), pluginsRepoConfig(&tdnf, &section, ops));
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        pluginsRepoMDDownloadStart(&tdnf, "", &directory, ops),
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        pluginsRepoMDDownloadEnd(&tdnf, "repo", null, ops),
    );
}

test "plugin initialization failure frees every partial resource" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writePluginConfigs(&tmp, true, true);

    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = fixturePath(&tmp, "pluginconf.d", &path_buffer);
    var setopts = CnfNode{};
    var args = CmdArgs{ .cn_setopts = &setopts };
    var conf = Conf{
        .nPluginsEnabled = 1,
        .pszPluginConfPath = path.ptr,
    };
    var tdnf = Tdnf{ .pArgs = &args, .pConf = &conf };
    var state = TestState{ .fail_create_kind = repogpgcheck_kind };

    try testing.expectEqual(@as(u32, 2004), loadPlugins(&tdnf, testOps(&state)));
    try testing.expect(tdnf.pPlugins == null);
    try testing.expectEqual([2]usize{ 1, 1 }, state.creates);
    try testing.expectEqual([2]usize{ 1, 0 }, state.destroys);
}

test "plugin allocation failures leave no list or initialized handle" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try writePluginConfigs(&tmp, true, true);

    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = fixturePath(&tmp, "pluginconf.d", &path_buffer);
    var setopts = CnfNode{};
    var args = CmdArgs{ .cn_setopts = &setopts };
    var conf = Conf{
        .nPluginsEnabled = 1,
        .pszPluginConfPath = path.ptr,
    };
    var tdnf = Tdnf{ .pArgs = &args, .pConf = &conf };

    var count = TestState{};
    try testing.expectEqual(@as(u32, 0), loadPlugins(&tdnf, testOps(&count)));
    freePlugins(tdnf.pPlugins, testOps(&count));
    tdnf.pPlugins = null;

    var fail_at: usize = 1;
    while (fail_at <= count.allocations) : (fail_at += 1) {
        var state = TestState{ .fail_allocation_at = fail_at };
        try testing.expectEqual(
            errors.ERROR_TDNF_OUT_OF_MEMORY,
            loadPlugins(&tdnf, testOps(&state)),
        );
        try testing.expect(tdnf.pPlugins == null);
        try testing.expectEqual([2]usize{ 0, 0 }, state.creates);
        try testing.expectEqual([2]usize{ 0, 0 }, state.destroys);
    }
}

test "global disable, noplugins, and missing config directory skip plugins" {
    var setopts = CnfNode{};
    var args = CmdArgs{ .cn_setopts = &setopts };
    var conf = Conf{ .pszPluginConfPath = @constCast("missing-plugin-dir") };
    var tdnf = Tdnf{ .pArgs = &args, .pConf = &conf };
    var state = TestState{};
    const ops = testOps(&state);

    try testing.expectEqual(@as(u32, 0), loadPlugins(&tdnf, ops));
    conf.nPluginsEnabled = 1;
    try testing.expectEqual(@as(u32, 0), loadPlugins(&tdnf, ops));
    var no_plugins = CnfNode{ .name = @constCast("noplugins") };
    setopts.first_child = &no_plugins;
    try testing.expectEqual(@as(u32, 0), loadPlugins(&tdnf, ops));
    try testing.expectEqual([2]usize{ 0, 0 }, state.creates);
}

test "built-in bridge helpers preserve null and ownership behavior" {
    var args = CmdArgs{ .nRefresh = 1 };
    var tdnf = Tdnf{ .pArgs = &args };
    try testing.expectEqual(@as(c_int, 1), BuiltinRefreshRequested(&tdnf));
    try testing.expectEqual(@as(c_int, 0), BuiltinRefreshRequested(null));
    try testing.expect(BuiltinGetEnv(null) == null);

    var urls: ?[*]?[*:0]u8 = null;
    var raw: ?*anyopaque = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFAllocateMemory(1, @sizeOf(?[*:0]u8), &raw),
    );
    urls = @ptrCast(@alignCast(raw.?));
    urls.?[0] = null;
    BuiltinReplaceBaseUrls(null, urls);

    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        BuiltinDownloadMetalink(null, null, null, null, null),
    );
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        BuiltinFindRepo(null, null, null),
    );
}
