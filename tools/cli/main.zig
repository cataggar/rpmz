// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const tdnf = @import("tdnf");
const jsondump = @import("jsondump_abi");
const common = @import("tdnf_common");
const client = @import("tdnf_client");
const cli = @import("tdnf_cli");
const replay_options = @import("replay_options.zig");
const abi = @import("tdnf_internal_abi");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("unistd.h");
});

extern fn TDNFFreeMemory(pMemory: ?*anyopaque) void;

comptime {
    _ = client;
    _ = cli;
}

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const LOG_CRIT: c_int = 2;

const replay_usage =
    \\Usage: tdnf replay --installroot <absolute-path> --rpmdb-path <absolute-path> --forcearch <arch> <bundle-directory>
    \\
    \\Replay applies only the exact offline bundle through tdnf.replay.
    \\All three target options are required exactly once. Paths must already
    \\be canonical absolute paths; the rpmdb path is install-root-relative.
    \\Value options accept --name VALUE, --name=VALUE, -name VALUE, and
    \\-name=VALUE. Installroot also accepts -i VALUE and -iVALUE.
    \\JSON accepts -j/--j, -js/--js, -jso/--jso, and -json/--json.
    \\Help accepts --help and -h.
    \\A valid invocation writes one canonical replay-result JSON document to
    \\stdout. Diagnostics, usage, and scriptlet output are written to stderr.
    \\RPM scriptlets/triggers are untrusted; use OS-level no-network isolation
    \\when the entire transaction must be offline.
    \\Exit status: 0 success, 2 invocation error, 3 validation failure,
    \\4 transaction failure, 1 internal/output failure.
    \\
;

const replay_exit = struct {
    const internal: u8 = 1;
    const usage: u8 = 2;
    const validation: u8 = 3;
    const transaction: u8 = 4;
};

const replay_invocation_error_schema = "tdnf.replay-invocation-error/v1";

const ReplayArgs = struct {
    bundle_directory: []const u8,
    install_root: []const u8,
    rpmdb_path: []const u8,
    architecture: []const u8,
};

const ReplayInvocation = union(enum) {
    help,
    run: ReplayArgs,
};

const ReplayParseError = error{
    DuplicateOption,
    ExtraOperand,
    MissingBundle,
    EmptyBundle,
    MissingInstallRoot,
    MissingRpmDbPath,
    MissingArchitecture,
    MissingOptionValue,
    UnsupportedOption,
};

const OptionMatch = union(enum) {
    separate,
    attached: []const u8,
};

const ReplayParseDiagnostic = struct {
    code: [*:0]const u8,
    message: [*:0]const u8,
};

const command_map = [_]abi.TDNF_CLI_CMD_MAP{
    .{ .pszCmdName = "autoerase", .pFnCmd = abi.TDNFCliAutoEraseCommand, .ReqRoot = true },
    .{ .pszCmdName = "autoremove", .pFnCmd = abi.TDNFCliAutoEraseCommand, .ReqRoot = true },
    .{ .pszCmdName = "check", .pFnCmd = abi.TDNFCliCheckCommand, .ReqRoot = false },
    .{ .pszCmdName = "check-local", .pFnCmd = abi.TDNFCliCheckLocalCommand, .ReqRoot = false },
    .{ .pszCmdName = "check-update", .pFnCmd = abi.TDNFCliCheckUpdateCommand, .ReqRoot = false },
    .{ .pszCmdName = "clean", .pFnCmd = abi.TDNFCliCleanCommand, .ReqRoot = false },
    .{ .pszCmdName = "count", .pFnCmd = abi.TDNFCliCountCommand, .ReqRoot = false },
    .{ .pszCmdName = "distro-sync", .pFnCmd = abi.TDNFCliDistroSyncCommand, .ReqRoot = true },
    .{ .pszCmdName = "downgrade", .pFnCmd = abi.TDNFCliDowngradeCommand, .ReqRoot = true },
    .{ .pszCmdName = "erase", .pFnCmd = abi.TDNFCliEraseCommand, .ReqRoot = true },
    .{ .pszCmdName = "help", .pFnCmd = abi.TDNFCliHelpCommand, .ReqRoot = false },
    .{ .pszCmdName = "history", .pFnCmd = abi.TDNFCliHistoryCommand, .ReqRoot = true },
    .{ .pszCmdName = "info", .pFnCmd = abi.TDNFCliInfoCommand, .ReqRoot = false },
    .{ .pszCmdName = "install", .pFnCmd = abi.TDNFCliInstallCommand, .ReqRoot = true },
    .{ .pszCmdName = "list", .pFnCmd = abi.TDNFCliListCommand, .ReqRoot = false },
    .{ .pszCmdName = "makecache", .pFnCmd = abi.TDNFCliMakeCacheCommand, .ReqRoot = false },
    .{ .pszCmdName = "mark", .pFnCmd = abi.TDNFCliMarkCommand, .ReqRoot = false },
    .{ .pszCmdName = "plan", .pFnCmd = TDNFCliPlanCommand, .ReqRoot = false },
    .{ .pszCmdName = "provides", .pFnCmd = abi.TDNFCliProvidesCommand, .ReqRoot = false },
    .{ .pszCmdName = "whatprovides", .pFnCmd = abi.TDNFCliProvidesCommand, .ReqRoot = false },
    .{ .pszCmdName = "reinstall", .pFnCmd = abi.TDNFCliReinstallCommand, .ReqRoot = true },
    .{ .pszCmdName = "remove", .pFnCmd = abi.TDNFCliEraseCommand, .ReqRoot = true },
    .{ .pszCmdName = "repolist", .pFnCmd = abi.TDNFCliRepoListCommand, .ReqRoot = false },
    .{ .pszCmdName = "reposync", .pFnCmd = abi.TDNFCliRepoSyncCommand, .ReqRoot = false },
    .{ .pszCmdName = "repoquery", .pFnCmd = abi.TDNFCliRepoQueryCommand, .ReqRoot = false },
    .{ .pszCmdName = "search", .pFnCmd = abi.TDNFCliSearchCommand, .ReqRoot = false },
    .{ .pszCmdName = "update", .pFnCmd = abi.TDNFCliUpgradeCommand, .ReqRoot = true },
    .{ .pszCmdName = "update-to", .pFnCmd = abi.TDNFCliUpgradeCommand, .ReqRoot = true },
    .{ .pszCmdName = "upgrade", .pFnCmd = abi.TDNFCliUpgradeCommand, .ReqRoot = true },
    .{ .pszCmdName = "upgrade-to", .pFnCmd = abi.TDNFCliUpgradeCommand, .ReqRoot = true },
    .{ .pszCmdName = "updateinfo", .pFnCmd = abi.TDNFCliUpdateInfoCommand, .ReqRoot = false },
};

fn destroyJsonDump(ppDump: *?*jsondump.JsonDump) void {
    if (ppDump.*) |pDump| {
        jsondump.jd_destroy(pDump);
        ppDump.* = null;
    }
}

fn checkJsonResult(nResult: c_int) u32 {
    if (nResult != 0) {
        return abi.ERROR_TDNF_JSONDUMP;
    }
    return 0;
}

fn freeOwnedString(ppValue: *?[*:0]u8) void {
    if (ppValue.*) |value| {
        TDNFFreeMemory(@ptrCast(value));
        ppValue.* = null;
    }
}

fn getErrno() c_int {
    return abi.__errno_location().*;
}

fn systemOutputError() u32 {
    const nErrNo = getErrno();
    if (nErrNo <= 0) {
        return abi.ERROR_TDNF_FILESYS_IO;
    }
    return @as(u32, @intCast(abi.ERROR_TDNF_SYSTEM_BASE)) +
        @as(u32, @intCast(nErrNo));
}

fn cliHandle(pContext: ?*abi.TDNF_CLI_CONTEXT) abi.PTDNF {
    return @ptrCast(@alignCast(pContext.?.hTdnf));
}

fn findCommand(pszCmd: [*c]const u8) ?*const abi.TDNF_CLI_CMD_MAP {
    for (&command_map) |*cmd| {
        if (c.strcmp(pszCmd, cmd.pszCmdName) == 0) {
            return cmd;
        }
    }
    return null;
}

fn hasSetOption(
    cmd_args: *const abi.TDNF_CMD_ARGS,
    name: [*:0]const u8,
) bool {
    if (cmd_args.cn_setopts == null) return false;
    var node = cmd_args.cn_setopts[0].first_child;
    while (node != null) : (node = node[0].next) {
        if (node[0].name != null and c.strcmp(node[0].name, name) == 0)
            return true;
    }
    return false;
}

fn matchNamedOption(arg: []const u8, name: []const u8) ?OptionMatch {
    const prefix_len: usize = if (std.mem.startsWith(u8, arg, "--"))
        2
    else if (std.mem.startsWith(u8, arg, "-"))
        1
    else
        return null;
    const body = arg[prefix_len..];
    if (std.mem.eql(u8, body, name)) return .separate;
    if (body.len > name.len and body[name.len] == '=' and
        std.mem.eql(u8, body[0..name.len], name))
    {
        return .{ .attached = body[name.len + 1 ..] };
    }
    return null;
}

fn replayOptionValue(
    argv: []const [*:0]const u8,
    index: *usize,
    matched: OptionMatch,
) ReplayParseError![]const u8 {
    const value = switch (matched) {
        .attached => |attached| attached,
        .separate => value: {
            index.* += 1;
            if (index.* >= argv.len) return error.MissingOptionValue;
            break :value std.mem.span(argv[index.*]);
        },
    };
    if (value.len == 0) return error.MissingOptionValue;
    return value;
}

fn parseReplayInvocation(
    argv: []const [*:0]const u8,
    json_output: bool,
) ReplayParseError!ReplayInvocation {
    var install_root: ?[]const u8 = null;
    var rpmdb_path: ?[]const u8 = null;
    var architecture: ?[]const u8 = null;
    var bundle_directory: ?[]const u8 = null;
    var saw_command = false;
    var help = false;
    var end_options = false;

    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        const arg = std.mem.span(argv[index]);
        if (!end_options) {
            if (std.mem.eql(u8, arg, "--")) {
                end_options = true;
                continue;
            }
            if (std.mem.eql(u8, arg, replay_options.help_long) or
                std.mem.eql(u8, arg, replay_options.help_short))
            {
                if (help) return error.DuplicateOption;
                help = true;
                continue;
            }
            if (json_output and isJsonOutputOption(arg))
                continue;

            if (matchNamedOption(
                arg,
                replay_options.install_root.name,
            )) |matched| {
                if (install_root != null) return error.DuplicateOption;
                install_root = try replayOptionValue(argv, &index, matched);
                continue;
            }
            if (std.mem.eql(u8, arg, replay_options.install_root.short.?) or
                (arg.len > replay_options.install_root.short.?.len and
                    std.mem.startsWith(
                        u8,
                        arg,
                        replay_options.install_root.short.?,
                    ) and
                    !std.mem.startsWith(
                        u8,
                        arg,
                        replay_options.install_root_single_dash,
                    )))
            {
                if (install_root != null) return error.DuplicateOption;
                const matched: OptionMatch = if (arg.len == 2)
                    .separate
                else
                    .{ .attached = arg[2..] };
                install_root = try replayOptionValue(argv, &index, matched);
                continue;
            }
            if (matchNamedOption(
                arg,
                replay_options.architecture.name,
            )) |matched| {
                if (architecture != null) return error.DuplicateOption;
                architecture = try replayOptionValue(argv, &index, matched);
                continue;
            }
            if (matchNamedOption(
                arg,
                replay_options.rpmdb_path.name,
            )) |matched| {
                if (rpmdb_path != null) return error.DuplicateOption;
                rpmdb_path = try replayOptionValue(argv, &index, matched);
                continue;
            }
            if (arg.len != 0 and arg[0] == '-')
                return error.UnsupportedOption;
        }

        if (!saw_command) {
            if (!std.mem.eql(u8, arg, "replay")) return error.ExtraOperand;
            saw_command = true;
        } else if (bundle_directory == null) {
            if (arg.len == 0) return error.EmptyBundle;
            bundle_directory = arg;
        } else {
            return error.ExtraOperand;
        }
    }

    if (help) return .help;
    if (!saw_command or bundle_directory == null) return error.MissingBundle;
    return .{ .run = .{
        .bundle_directory = bundle_directory.?,
        .install_root = install_root orelse return error.MissingInstallRoot,
        .rpmdb_path = rpmdb_path orelse return error.MissingRpmDbPath,
        .architecture = architecture orelse return error.MissingArchitecture,
    } };
}

fn optionConsumesNext(arg: []const u8) bool {
    const prefix_len: usize = if (std.mem.startsWith(u8, arg, "--"))
        2
    else if (std.mem.startsWith(u8, arg, "-"))
        1
    else
        return false;
    const body = arg[prefix_len..];
    if (body.len == 0) return false;

    const equals_index = std.mem.indexOfScalar(u8, body, '=');
    const name = if (equals_index) |index| body[0..index] else body;
    if (cli.matchLegacyLongOption(name)) |matched| {
        return equals_index == null and matched.arity != .none;
    }
    if (prefix_len != 1 or equals_index != null) return false;

    for (body, 0..) |letter, index| {
        const arity = cli.legacyShortOptionArity(letter) orelse return false;
        if (arity != .none) return index + 1 == body.len;
    }
    return false;
}

fn jsonOutputRequested(argv: []const [*:0]const u8) bool {
    if (argv.len > 0) {
        const arg0 = std.mem.span(argv[0]);
        if (arg0.len >= 5 and std.mem.eql(u8, arg0[arg0.len - 5 ..], "tdnfj"))
            return true;
    }

    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        const arg = std.mem.span(argv[index]);
        if (std.mem.eql(u8, arg, "--")) break;
        if (arg.len == 0 or arg[0] != '-') continue;

        const prefix_len: usize = if (std.mem.startsWith(u8, arg, "--")) 2 else 1;
        const body = arg[prefix_len..];
        const equals_index = std.mem.indexOfScalar(u8, body, '=');
        const name = if (equals_index) |offset| body[0..offset] else body;
        if (cli.matchLegacyLongOption(name)) |matched| {
            if (std.mem.eql(u8, matched.name, replay_options.json_name))
                return true;
        }

        if (optionConsumesNext(arg) and index + 1 < argv.len)
            index += 1;
    }
    return false;
}

fn isJsonOutputOption(arg: []const u8) bool {
    const prefix_len: usize = if (std.mem.startsWith(u8, arg, "--"))
        2
    else if (std.mem.startsWith(u8, arg, "-"))
        1
    else
        return false;
    const body = arg[prefix_len..];
    if (body.len == 0 or std.mem.indexOfScalar(u8, body, '=') != null)
        return false;
    const matched = cli.matchLegacyLongOption(body) orelse return false;
    return matched.arity == .none and
        std.mem.eql(u8, matched.name, replay_options.json_name);
}

fn isReplayInvocation(argv: []const [*:0]const u8) bool {
    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        const arg = std.mem.span(argv[index]);
        if (std.mem.eql(u8, arg, "--")) {
            return index + 1 < argv.len and
                std.mem.eql(u8, std.mem.span(argv[index + 1]), "replay");
        }
        if (arg.len == 0 or arg[0] != '-')
            return std.mem.eql(u8, arg, "replay");
        if (optionConsumesNext(arg) and index + 1 < argv.len)
            index += 1;
    }
    return false;
}

fn replayParseDiagnostic(err: ReplayParseError) ReplayParseDiagnostic {
    return switch (err) {
        error.DuplicateOption => .{
            .code = "duplicate_option",
            .message = "target options must appear exactly once",
        },
        error.ExtraOperand => .{
            .code = "extra_operand",
            .message = "expected exactly one bundle directory",
        },
        error.MissingBundle => .{
            .code = "missing_bundle",
            .message = "missing bundle directory",
        },
        error.EmptyBundle => .{
            .code = "empty_bundle",
            .message = "bundle directory must be non-empty",
        },
        error.MissingInstallRoot => .{
            .code = "missing_install_root",
            .message = "missing required --installroot",
        },
        error.MissingRpmDbPath => .{
            .code = "missing_rpmdb_path",
            .message = "missing required --rpmdb-path",
        },
        error.MissingArchitecture => .{
            .code = "missing_architecture",
            .message = "missing required --forcearch",
        },
        error.MissingOptionValue => .{
            .code = "missing_option_value",
            .message = "target option requires a non-empty value",
        },
        error.UnsupportedOption => .{
            .code = "unsupported_option",
            .message = "unsupported option for offline replay",
        },
    };
}

fn printReplayUsage(parse_error: ?ReplayParseError) void {
    if (parse_error) |err| {
        const diagnostic = replayParseDiagnostic(err);
        common.log(LOG_ERR, "tdnf replay: %s\n", .{diagnostic.message});
    }
    _ = c.fwrite(replay_usage.ptr, 1, replay_usage.len, c.stderr);
    _ = c.fflush(c.stderr);
}

const ReplayStdoutGuard = struct {
    saved_stdout: c_int,
    active: bool = true,

    fn begin() error{RedirectFailed}!ReplayStdoutGuard {
        const stderr_flags_result = std.posix.system.fcntl(
            c.STDERR_FILENO,
            std.posix.F.GETFL,
            @as(usize, 0),
        );
        if (std.posix.errno(stderr_flags_result) != .SUCCESS)
            return error.RedirectFailed;
        const stderr_flags: std.posix.O = @bitCast(
            @as(u32, @intCast(stderr_flags_result)),
        );
        if (stderr_flags.ACCMODE == .RDONLY)
            return error.RedirectFailed;

        if (c.fflush(c.stdout) != 0) return error.RedirectFailed;
        const saved = std.c.fcntl(
            c.STDOUT_FILENO,
            std.c.F.DUPFD_CLOEXEC,
            @as(c_int, 3),
        );
        if (saved < 0) return error.RedirectFailed;
        if (c.dup2(c.STDERR_FILENO, c.STDOUT_FILENO) < 0) {
            _ = c.close(saved);
            return error.RedirectFailed;
        }
        return .{ .saved_stdout = saved };
    }

    fn restore(self: *ReplayStdoutGuard) bool {
        if (!self.active) return true;
        const flushed = c.fflush(c.stdout) == 0;
        const restored = c.dup2(self.saved_stdout, c.STDOUT_FILENO) >= 0;
        const closed = c.close(self.saved_stdout) == 0;
        self.active = false;
        return flushed and restored and closed;
    }
};

fn writeReplayResult(bytes: []const u8) bool {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const written = c.fwrite(
            bytes.ptr + offset,
            1,
            bytes.len - offset,
            c.stdout,
        );
        if (written == 0) return false;
        offset += written;
    }
    return c.fflush(c.stdout) == 0;
}

fn writeReplayInvocationError(err: ReplayParseError) bool {
    const diagnostic = replayParseDiagnostic(err);
    var jd: ?*jsondump.JsonDump = jsondump.jd_create(0);
    if (jd == null) return false;
    defer destroyJsonDump(&jd);

    if (checkJsonResult(jsondump.jd_map_start(jd)) != 0) return false;
    if (checkJsonResult(jsondump.jd_map_add_string(
        jd,
        "schema",
        replay_invocation_error_schema,
    )) != 0) return false;
    if (checkJsonResult(jsondump.jd_map_add_string(
        jd,
        "error",
        diagnostic.code,
    )) != 0) return false;
    if (checkJsonResult(jsondump.jd_map_add_string(
        jd,
        "message",
        diagnostic.message,
    )) != 0) return false;
    return writeReplayResult(std.mem.span(jd.?.buf));
}

fn runReplay(invocation: ReplayArgs) u8 {
    const allocator = std.heap.c_allocator;
    var io_state: std.Io.Threaded = .init(allocator, .{});
    defer io_state.deinit();

    var stdout_guard = ReplayStdoutGuard.begin() catch {
        common.log(LOG_ERR, "tdnf replay: cannot reserve machine-output channel\n", .{});
        return replay_exit.internal;
    };
    defer _ = stdout_guard.restore();

    const result = tdnf.replay.run(allocator, io_state.io(), .{
        .bundle_directory = invocation.bundle_directory,
        .target = .{
            .install_root = invocation.install_root,
            .rpmdb_path = invocation.rpmdb_path,
            .architecture = invocation.architecture,
        },
    }) catch {
        _ = stdout_guard.restore();
        common.log(LOG_ERR, "tdnf replay: out of memory\n", .{});
        return replay_exit.internal;
    };
    defer result.deinit();

    if (!stdout_guard.restore()) {
        common.log(LOG_ERR, "tdnf replay: cannot restore machine-output channel\n", .{});
        return replay_exit.internal;
    }

    const canonical = result.canonicalJsonAlloc(allocator) catch {
        common.log(LOG_ERR, "tdnf replay: out of memory rendering result\n", .{});
        return replay_exit.internal;
    };
    defer allocator.free(canonical);
    if (!writeReplayResult(canonical)) return replay_exit.internal;

    return switch (result.status) {
        .succeeded => 0,
        .validation_failed => replay_exit.validation,
        .transaction_failed => replay_exit.transaction,
    };
}

fn dispatchReplay(argv: []const [*:0]const u8, json_output: bool) u8 {
    const invocation = parseReplayInvocation(argv, json_output) catch |err| {
        printReplayUsage(err);
        if (json_output and !writeReplayInvocationError(err))
            return replay_exit.internal;
        return replay_exit.usage;
    };
    return switch (invocation) {
        .help => help: {
            printReplayUsage(null);
            break :help 0;
        },
        .run => |replay_args| runReplay(replay_args),
    };
}

fn initializeContext() abi.TDNF_CLI_CONTEXT {
    var context: abi.TDNF_CLI_CONTEXT = std.mem.zeroes(abi.TDNF_CLI_CONTEXT);

    context.pFnCheck = TDNFCliInvokeCheck;
    context.pFnCheckLocal = TDNFCliInvokeCheckLocal;
    context.pFnCheckUpdate = TDNFCliInvokeCheckUpdate;
    context.pFnClean = TDNFCliInvokeClean;
    context.pFnCount = TDNFCliInvokeCount;
    context.pFnInfo = TDNFCliInvokeInfo;
    context.pFnList = TDNFCliInvokeList;
    context.pFnProvides = TDNFCliInvokeProvides;
    context.pFnRepoList = TDNFCliInvokeRepoList;
    context.pFnRepoSync = TDNFCliInvokeRepoSync;
    context.pFnRepoQuery = TDNFCliInvokeRepoQuery;
    context.pFnAlter = TDNFCliInvokeAlter;
    context.pFnResolve = TDNFCliInvokeResolve;
    context.pFnSearch = TDNFCliInvokeSearch;
    context.pFnUpdateInfo = TDNFCliInvokeUpdateInfo;
    context.pFnUpdateInfoSummary = TDNFCliInvokeUpdateInfoSummary;
    context.pFnHistoryList = TDNFCliInvokeHistoryList;
    context.pFnHistoryResolve = TDNFCliInvokeHistoryResolve;
    context.pFnAlterHistory = TDNFCliInvokeAlterHistory;
    context.pFnMark = TDNFCliInvokeMark;
    context.pFnGetPackageUrls = TDNFCliInvokeGetPackageUrls;
    context.pFnHistoryGetId = TDNFCliInvokeHistoryGetId;

    return context;
}

fn TDNFCliPrintError(dwErrorCode: u32, doJson: c_int) u32 {
    if (dwErrorCode == 0 or dwErrorCode == abi.ERROR_TDNF_CLI_CHECK_UPDATES_AVAILABLE) {
        return 0;
    }

    var dwError: u32 = 0;
    var pszError: ?[*:0]u8 = null;
    defer freeOwnedString(&pszError);

    if (dwErrorCode < abi.ERROR_TDNF_BASE) {
        dwError = abi.TDNFCliGetErrorString(dwErrorCode, @ptrCast(&pszError));
    } else {
        dwError = abi.TDNFGetErrorString(dwErrorCode, @ptrCast(&pszError));
    }

    if (dwError != 0 or pszError == null) {
        common.log(LOG_ERR, "Retrieving error string for %u failed with %u\n", .{ dwErrorCode, dwError });
        return dwError;
    }

    var dwPrintCode = dwErrorCode;
    if (dwPrintCode == abi.ERROR_TDNF_CLI_NOTHING_TO_DO or dwPrintCode == abi.ERROR_TDNF_NO_DATA) {
        dwPrintCode = 0;
    }

    if (doJson != 0) {
        if (dwPrintCode != 0) {
            var jd: ?*jsondump.JsonDump = jsondump.jd_create(0);
            if (jd == null) {
                return abi.ERROR_TDNF_JSONDUMP;
            }
            defer destroyJsonDump(&jd);

            dwError = checkJsonResult(jsondump.jd_map_start(jd));
            if (dwError != 0) {
                return dwError;
            }
            dwError = checkJsonResult(jsondump.jd_map_add_int(jd, "Error", @as(c_int, @intCast(dwPrintCode))));
            if (dwError != 0) {
                return dwError;
            }
            dwError = checkJsonResult(jsondump.jd_map_add_string(jd, "ErrorMessage", pszError));
            if (dwError != 0) {
                return dwError;
            }
            _ = c.fputs(jd.?.buf, c.stdout);
        }
    } else if (dwPrintCode != 0) {
        common.log(LOG_ERR, "Error(%u) : %s\n", .{ dwPrintCode, pszError.? });
    } else {
        common.log(LOG_ERR, "%s\n", .{pszError.?});
    }

    return 0;
}

fn TDNFCliShowVersion(pCmdArgs: ?*abi.TDNF_CMD_ARGS) void {
    const cmd_args = pCmdArgs orelse return;

    if (cmd_args.nJsonOutput != 0) {
        var jd: ?*jsondump.JsonDump = jsondump.jd_create(0);
        if (jd == null) {
            return;
        }
        defer destroyJsonDump(&jd);

        if (checkJsonResult(jsondump.jd_map_start(jd)) != 0) {
            return;
        }
        if (checkJsonResult(jsondump.jd_map_add_string(jd, "Name", abi.TDNFGetPackageName())) != 0) {
            return;
        }
        if (checkJsonResult(jsondump.jd_map_add_string(jd, "Version", abi.TDNFGetVersion())) != 0) {
            return;
        }
        _ = c.fputs(jd.?.buf, c.stdout);
    } else {
        common.log(LOG_INFO, "%s: %s\n", .{ abi.TDNFGetPackageName(), abi.TDNFGetVersion() });
    }
}

fn TDNFCliInvokeCheck(pContext: ?*abi.TDNF_CLI_CONTEXT) callconv(.c) u32 {
    return abi.TDNFCheckPackages(cliHandle(pContext));
}

fn TDNFCliInvokeCheckLocal(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pszFolder: [*c]const u8,
) callconv(.c) u32 {
    return abi.TDNFCheckLocalPackages(cliHandle(pContext), pszFolder);
}

fn TDNFCliInvokeCheckUpdate(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    ppszPackageArgs: [*c][*c]u8,
    ppPkgInfo: ?*[*c]abi.TDNF_PKG_INFO,
    pdwCount: ?*u32,
) callconv(.c) u32 {
    return abi.TDNFCheckUpdates(cliHandle(pContext), ppszPackageArgs, ppPkgInfo, pdwCount);
}

fn TDNFCliInvokeClean(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    nCleanType: u32,
) callconv(.c) u32 {
    return abi.TDNFClean(cliHandle(pContext), nCleanType);
}

fn TDNFCliInvokeCount(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pnCount: ?*u32,
) callconv(.c) u32 {
    return abi.TDNFCountCommand(cliHandle(pContext), pnCount);
}

fn TDNFCliInvokeAlter(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pSolvedPkgInfo: ?*abi.TDNF_SOLVED_PKG_INFO,
) callconv(.c) u32 {
    return abi.TDNFAlterCommand(cliHandle(pContext), pSolvedPkgInfo);
}

fn TDNFCliInvokeAlterHistory(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pSolvedPkgInfo: ?*abi.TDNF_SOLVED_PKG_INFO,
    pHistoryArgs: ?*abi.TDNF_HISTORY_ARGS,
) callconv(.c) u32 {
    return abi.TDNFAlterHistoryCommand(cliHandle(pContext), pSolvedPkgInfo, pHistoryArgs);
}

fn TDNFCliInvokeInfo(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pInfoArgs: ?*abi.TDNF_LIST_ARGS,
    ppPkgInfo: ?*[*c]abi.TDNF_PKG_INFO,
    pdwCount: ?*u32,
) callconv(.c) u32 {
    return abi.TDNFInfo(cliHandle(pContext), pInfoArgs.?.nScope, pInfoArgs.?.ppszPackageNameSpecs, ppPkgInfo, pdwCount);
}

fn TDNFCliInvokeList(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pListArgs: ?*abi.TDNF_LIST_ARGS,
    ppPkgInfo: ?*[*c]abi.TDNF_PKG_INFO,
    pdwCount: ?*u32,
) callconv(.c) u32 {
    return abi.TDNFList(cliHandle(pContext), pListArgs.?.nScope, pListArgs.?.ppszPackageNameSpecs, ppPkgInfo, pdwCount);
}

fn TDNFCliInvokeProvides(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pszProvides: [*c]const u8,
    ppPkgInfos: ?*?*abi.TDNF_PKG_INFO,
) callconv(.c) u32 {
    return abi.TDNFProvides(cliHandle(pContext), pszProvides, ppPkgInfos);
}

fn TDNFCliInvokeRepoList(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    nFilter: abi.TDNF_REPOLISTFILTER,
    ppRepos: ?*?*abi.TDNF_REPO_DATA,
) callconv(.c) u32 {
    return abi.TDNFRepoList(cliHandle(pContext), nFilter, ppRepos);
}

fn TDNFCliInvokeRepoSync(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pRepoSyncArgs: ?*abi.TDNF_REPOSYNC_ARGS,
) callconv(.c) u32 {
    return abi.TDNFRepoSync(cliHandle(pContext), pRepoSyncArgs);
}

fn TDNFCliInvokeRepoQuery(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pRepoQueryArgs: ?*abi.TDNF_REPOQUERY_ARGS,
    ppPkgInfos: ?*[*c]abi.TDNF_PKG_INFO,
    pdwCount: ?*u32,
) callconv(.c) u32 {
    return abi.TDNFRepoQuery(cliHandle(pContext), pRepoQueryArgs, ppPkgInfos, pdwCount);
}

fn TDNFCliInvokeResolve(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    nAlterType: abi.TDNF_ALTERTYPE,
    ppSolvedPkgInfo: ?*?*abi.TDNF_SOLVED_PKG_INFO,
) callconv(.c) u32 {
    return abi.TDNFResolve(cliHandle(pContext), nAlterType, ppSolvedPkgInfo);
}

fn TDNFCliPlanCommand(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
) callconv(.c) u32 {
    const context = pContext orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const cmd_args = pCmdArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const handle = cliHandle(context);
    if (handle == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    // Everything that decides what the plan says -- verb mapping, capture
    // lifecycle, problem-plan policy, canonical rendering -- belongs to
    // libtdnf. The command drops its own `plan` verb and prints the bytes.
    var pszJson: [*c]u8 = null;
    const dwError = abi.TDNFTransactionPlanResolveCanonicalJson(
        handle,
        cmd_args.ppszCmds + 1,
        @intCast(@max(cmd_args.nCmdCount, 1) - 1),
        &pszJson,
    );
    if (dwError != 0) {
        return dwError;
    }
    defer abi.TDNFTransactionPlanFreeCanonicalJson(pszJson);

    if (c.fputs(pszJson, c.stdout) < 0) {
        return systemOutputError();
    }
    if (c.fflush(c.stdout) != 0) {
        return systemOutputError();
    }
    return 0;
}

fn TDNFCliInvokeSearch(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
    ppPkgInfo: ?*[*c]abi.TDNF_PKG_INFO,
    pdwCount: ?*u32,
) callconv(.c) u32 {
    return abi.TDNFSearchCommand(cliHandle(pContext), pCmdArgs, ppPkgInfo, pdwCount);
}

fn TDNFCliInvokeUpdateInfo(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pInfoArgs: ?*abi.TDNF_UPDATEINFO_ARGS,
    ppUpdateInfo: ?*?*abi.TDNF_UPDATEINFO,
) callconv(.c) u32 {
    return abi.TDNFUpdateInfo(cliHandle(pContext), pInfoArgs.?.ppszPackageNameSpecs, ppUpdateInfo);
}

fn TDNFCliInvokeUpdateInfoSummary(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    nAvail: abi.TDNF_AVAIL,
    pInfoArgs: ?*abi.TDNF_UPDATEINFO_ARGS,
    ppSummary: ?*?*abi.TDNF_UPDATEINFO_SUMMARY,
) callconv(.c) u32 {
    _ = nAvail;
    return abi.TDNFUpdateInfoSummary(cliHandle(pContext), pInfoArgs.?.ppszPackageNameSpecs, ppSummary);
}

fn TDNFCliInvokeHistoryList(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pHistoryArgs: ?*abi.TDNF_HISTORY_ARGS,
    ppHistoryInfo: ?*?*abi.TDNF_HISTORY_INFO,
) callconv(.c) u32 {
    return abi.TDNFHistoryList(cliHandle(pContext), pHistoryArgs, ppHistoryInfo);
}

fn TDNFCliInvokeHistoryResolve(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pHistoryArgs: ?*abi.TDNF_HISTORY_ARGS,
    ppSolvedPkgInfo: ?*?*abi.TDNF_SOLVED_PKG_INFO,
) callconv(.c) u32 {
    return abi.TDNFHistoryResolve(cliHandle(pContext), pHistoryArgs, ppSolvedPkgInfo);
}

fn TDNFCliInvokeGetPackageUrls(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pSolvedPkgInfo: ?*abi.TDNF_SOLVED_PKG_INFO,
    pppszUrls: [*c][*c][*c]u8,
    pnCount: [*c]c_int,
) callconv(.c) u32 {
    return abi.TDNFGetPackageUrls(cliHandle(pContext), pSolvedPkgInfo, pppszUrls, pnCount);
}

fn TDNFCliInvokeHistoryGetId(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pnId: ?*c_int,
) callconv(.c) u32 {
    return abi.TDNFHistoryGetId(cliHandle(pContext), pnId);
}

fn TDNFCliInvokeMark(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    ppszPkgNameSpecs: [*c][*c]u8,
    nValue: u32,
) callconv(.c) u32 {
    return abi.TDNFMark(cliHandle(pContext), ppszPkgNameSpecs, nValue);
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    const requested_json = jsonOutputRequested(argv);
    if (isReplayInvocation(argv))
        return dispatchReplay(argv, requested_json);

    const argc: c_int = @intCast(argv.len);
    const argv_ptr: [*c]?[*:0]u8 = @ptrCast(@constCast(argv.ptr));

    var dwError: u32 = 0;
    var pTdnf: abi.PTDNF = null;
    var pCmdArgs: ?*abi.TDNF_CMD_ARGS = null;

    defer {
        if (pTdnf != null) {
            abi.TDNFCloseHandle(pTdnf);
        }
        if (pCmdArgs != null) {
            abi.TDNFFreeCmdArgs(pCmdArgs);
        }
    }

    dwError = parse: {
        cli.setParserJsonDiagnostics(requested_json);
        defer cli.setParserJsonDiagnostics(false);
        break :parse abi.TDNFCliParseArgs(argc, @ptrCast(argv_ptr), &pCmdArgs);
    };
    if (dwError == 0) {
        const cmd_args = pCmdArgs.?;

        if (cmd_args.nShowVersion != 0) {
            TDNFCliShowVersion(cmd_args);
        } else if (cmd_args.nShowHelp != 0) {
            abi.TDNFCliShowHelp();
        } else if (hasSetOption(cmd_args, "rpmdb-path")) {
            common.log(
                LOG_ERR,
                "--rpmdb-path is only valid with the replay command\n",
                .{},
            );
            dwError = abi.ERROR_TDNF_CLI_OPTION_NAME_INVALID;
        } else if (cmd_args.nCmdCount > 0) {
            const pszCmd: [*c]const u8 = cmd_args.ppszCmds[0];
            var context = initializeContext();

            if (findCommand(pszCmd)) |pCmd| {
                if (pCmd.ReqRoot and c.geteuid() != 0) {
                    dwError = abi.ERROR_TDNF_PERM;
                } else {
                    if (c.strcmp(pszCmd, "makecache") == 0) {
                        cmd_args.nRefresh = 1;
                    }

                    dwError = abi.TDNFInit();
                    if (dwError == 0) {
                        dwError = abi.TDNFOpenHandle(cmd_args, &pTdnf);
                    }
                    if (dwError == 0) {
                        context.hTdnf = @ptrCast(pTdnf);
                        dwError = pCmd.pFnCmd.?(&context, cmd_args);
                    }
                }
            } else {
                if (cmd_args.nJsonOutput == 0) {
                    abi.TDNFCliShowNoSuchCommand(pszCmd);
                }
                dwError = abi.ERROR_TDNF_CLI_NO_SUCH_CMD;
            }
        } else {
            if (cmd_args.nJsonOutput == 0) {
                abi.TDNFCliShowUsage();
            }
            dwError = abi.ERROR_TDNF_CLI_NO_SUCH_CMD;
        }
    }

    abi.TDNFUninit();
    if (dwError != 0) {
        const do_json: c_int = if (requested_json)
            1
        else if (pCmdArgs) |args|
            args.nJsonOutput
        else
            0;
        _ = TDNFCliPrintError(dwError, do_json);
        if (dwError == abi.ERROR_TDNF_CLI_NOTHING_TO_DO or dwError == abi.ERROR_TDNF_NO_DATA) {
            dwError = 0;
        }
    }

    return @truncate(dwError);
}
