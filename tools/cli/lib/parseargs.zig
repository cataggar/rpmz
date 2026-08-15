// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("tdnf_common");
const getopt = @import("getopt_c.zig").c;
const abi = @import("tdnf_internal_abi");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("strings.h");
    @cInclude("nodes.h");
});
const argparse = @import("argparse.zig");
const help = @import("help.zig");
const options = @import("options.zig");

extern fn TDNFStrIsValidRepoName(str: ?[*:0]const u8) c_int;

const LOG_ERR: c_int = 1;
const LOG_CRIT: c_int = 2;
const LEGACY_VERBOSITY_INFO: c_int = 6;
const short_options = "46bCc:d:e:hi:qvxy";

var option_state: abi.TDNF_CMD_ARGS = std.mem.zeroes(abi.TDNF_CMD_ARGS);

pub const OptionArity = enum {
    none,
    required,
    optional,
};

pub const LongOptionMatch = struct {
    name: []const u8,
    arity: OptionArity,
};

fn optionEntry(
    name: ?[*:0]const u8,
    has_arg: c_int,
    flag: ?*c_int,
    val: c_int,
) getopt.struct_option {
    return .{
        .name = name,
        .has_arg = has_arg,
        .flag = flag,
        .val = val,
    };
}

var pstOptions = [_]getopt.struct_option{
    optionEntry("4", getopt.no_argument, null, '4'),
    optionEntry("6", getopt.no_argument, null, '6'),
    optionEntry("alldeps", getopt.no_argument, &option_state.nAllDeps, 1),
    optionEntry("allowerasing", getopt.no_argument, &option_state.nAllowErasing, 1),
    optionEntry("assumeno", getopt.no_argument, &option_state.nAssumeNo, 1),
    optionEntry("assumeyes", getopt.no_argument, null, 'y'),
    optionEntry("best", getopt.no_argument, &option_state.nBest, 1),
    optionEntry("builddeps", getopt.no_argument, &option_state.nBuildDeps, 1),
    optionEntry("cacheonly", getopt.no_argument, &option_state.nCacheOnly, 1),
    optionEntry("config", getopt.required_argument, null, 'c'),
    optionEntry("debuglevel", getopt.required_argument, null, 'd'),
    optionEntry("debugsolver", getopt.no_argument, &option_state.nDebugSolver, 1),
    optionEntry("disableexcludes", getopt.no_argument, &option_state.nDisableExcludes, 1),
    optionEntry("disableplugin", getopt.required_argument, null, 0),
    optionEntry("disablerepo", getopt.required_argument, null, 0),
    optionEntry("downloaddir", getopt.required_argument, null, 0),
    optionEntry("downloadonly", getopt.no_argument, &option_state.nDownloadOnly, 1),
    optionEntry("enableplugin", getopt.required_argument, null, 0),
    optionEntry("enablerepo", getopt.required_argument, null, 0),
    optionEntry("exclude", getopt.required_argument, null, 0),
    optionEntry("forcearch", getopt.required_argument, null, 0),
    optionEntry("help", getopt.no_argument, null, 'h'),
    optionEntry("installroot", getopt.required_argument, null, 'i'),
    optionEntry("json", getopt.no_argument, &option_state.nJsonOutput, 1),
    optionEntry("noautoremove", getopt.no_argument, &option_state.nNoAutoRemove, 1),
    optionEntry("nodeps", getopt.no_argument, &option_state.nNoDeps, 1),
    optionEntry("nogpgcheck", getopt.no_argument, &option_state.nNoGPGCheck, 1),
    optionEntry("nocligpgcheck", getopt.no_argument, &option_state.nNoCmdLineGPGCheck, 1),
    optionEntry("noplugins", getopt.no_argument, null, 0),
    optionEntry("quiet", getopt.no_argument, &option_state.nQuiet, 1),
    optionEntry("refresh", getopt.no_argument, &option_state.nRefresh, 1),
    optionEntry("releasever", getopt.required_argument, null, 0),
    optionEntry("reboot-required", getopt.no_argument, null, 0),
    optionEntry("repo", getopt.required_argument, null, 0),
    optionEntry("repofromdir", getopt.required_argument, null, 0),
    optionEntry("repofrompath", getopt.required_argument, null, 0),
    optionEntry("repoid", getopt.required_argument, null, 0),
    optionEntry("rpmverbosity", getopt.required_argument, null, 0),
    optionEntry("rpmdefine", getopt.required_argument, null, 0),
    optionEntry("rpmdb-path", getopt.required_argument, null, 0),
    optionEntry("sec-severity", getopt.required_argument, null, 0),
    optionEntry("security", getopt.no_argument, null, 0),
    optionEntry("setopt", getopt.required_argument, null, 0),
    optionEntry("skip-broken", getopt.no_argument, &option_state.nSkipBroken, 1),
    optionEntry("skipconflicts", getopt.no_argument, null, 0),
    optionEntry("skipdigest", getopt.no_argument, &option_state.nSkipDigest, 1),
    optionEntry("skipobsoletes", getopt.no_argument, null, 0),
    optionEntry("skipsignature", getopt.no_argument, &option_state.nSkipSignature, 1),
    optionEntry("source", getopt.no_argument, &option_state.nSource, 1),
    optionEntry("testonly", getopt.no_argument, &option_state.nTestOnly, 1),
    optionEntry("urls", getopt.no_argument, &option_state.nUrlsOnly, 1),
    optionEntry("verbose", getopt.no_argument, &option_state.nVerbose, 1),
    optionEntry("version", getopt.no_argument, &option_state.nShowVersion, 1),
    optionEntry("arch", getopt.required_argument, null, 0),
    optionEntry("delete", getopt.no_argument, null, 0),
    optionEntry("download-metadata", getopt.no_argument, null, 0),
    optionEntry("download-path", getopt.required_argument, null, 0),
    optionEntry("gpgcheck", getopt.no_argument, null, 0),
    optionEntry("metadata-path", getopt.required_argument, null, 0),
    optionEntry("newest-only", getopt.no_argument, null, 0),
    optionEntry("norepopath", getopt.no_argument, null, 0),
    optionEntry("available", getopt.no_argument, null, 0),
    optionEntry("extras", getopt.no_argument, null, 0),
    optionEntry("file", getopt.required_argument, null, 0),
    optionEntry("installed", getopt.no_argument, null, 0),
    optionEntry("userinstalled", getopt.no_argument, null, 0),
    optionEntry("upgrades", getopt.no_argument, null, 0),
    optionEntry("whatdepends", getopt.required_argument, null, 0),
    optionEntry("whatprovides", getopt.required_argument, null, 0),
    optionEntry("whatobsoletes", getopt.required_argument, null, 0),
    optionEntry("whatconflicts", getopt.required_argument, null, 0),
    optionEntry("whatrequires", getopt.required_argument, null, 0),
    optionEntry("whatrecommends", getopt.required_argument, null, 0),
    optionEntry("whatsuggests", getopt.required_argument, null, 0),
    optionEntry("whatsupplements", getopt.required_argument, null, 0),
    optionEntry("whatenhances", getopt.required_argument, null, 0),
    optionEntry("changelogs", getopt.no_argument, null, 0),
    optionEntry("conflicts", getopt.no_argument, null, 0),
    optionEntry("depends", getopt.no_argument, null, 0),
    optionEntry("duplicates", getopt.no_argument, null, 0),
    optionEntry("enhances", getopt.no_argument, null, 0),
    optionEntry("list", getopt.no_argument, null, 0),
    optionEntry("location", getopt.no_argument, null, 0),
    optionEntry("obsoletes", getopt.no_argument, null, 0),
    optionEntry("provides", getopt.no_argument, null, 0),
    optionEntry("qf", getopt.required_argument, null, 0),
    optionEntry("recommends", getopt.no_argument, null, 0),
    optionEntry("requires", getopt.no_argument, null, 0),
    optionEntry("requires-pre", getopt.no_argument, null, 0),
    optionEntry("suggests", getopt.no_argument, null, 0),
    optionEntry("supplements", getopt.no_argument, null, 0),
    optionEntry("all", getopt.no_argument, null, 0),
    optionEntry("info", getopt.no_argument, null, 0),
    optionEntry("summary", getopt.no_argument, null, 0),
    optionEntry("recent", getopt.no_argument, null, 0),
    optionEntry("updates", getopt.no_argument, null, 0),
    optionEntry("downgrades", getopt.no_argument, null, 0),
    optionEntry("to", getopt.required_argument, null, 0),
    optionEntry("from", getopt.required_argument, null, 0),
    optionEntry("reverse", getopt.no_argument, null, 0),
    optionEntry(null, 0, null, 0),
};

fn optionArity(has_arg: c_int) OptionArity {
    if (has_arg == getopt.required_argument) return .required;
    if (has_arg == getopt.optional_argument) return .optional;
    return .none;
}

pub fn matchLegacyLongOption(name: []const u8) ?LongOptionMatch {
    var matched: ?LongOptionMatch = null;
    var ambiguous = false;
    for (pstOptions) |option| {
        const option_name = if (option.name) |value|
            std.mem.span(value)
        else
            break;
        if (std.mem.eql(u8, option_name, name))
            return .{
                .name = option_name,
                .arity = optionArity(option.has_arg),
            };
        if (!std.mem.startsWith(u8, option_name, name)) continue;
        if (matched != null) {
            ambiguous = true;
        } else {
            matched = .{
                .name = option_name,
                .arity = optionArity(option.has_arg),
            };
        }
    }
    return if (ambiguous) null else matched;
}

pub fn legacyLongOptionArity(name: []const u8) ?OptionArity {
    const matched = matchLegacyLongOption(name) orelse return null;
    return matched.arity;
}

pub fn legacyShortOptionArity(letter: u8) ?OptionArity {
    var index: usize = 0;
    while (index < short_options.len) {
        const candidate = short_options[index];
        index += 1;
        var arity: OptionArity = .none;
        if (index < short_options.len and short_options[index] == ':') {
            arity = .required;
            index += 1;
            if (index < short_options.len and short_options[index] == ':') {
                arity = .optional;
                index += 1;
            }
        }
        if (candidate == letter) return arity;
    }
    return null;
}

fn resetOptionState() void {
    option_state = std.mem.zeroes(abi.TDNF_CMD_ARGS);
}

fn isNullOrEmpty(pszValue: ?[*:0]const u8) bool {
    return pszValue == null or pszValue.?[0] == 0;
}

fn equalsIgnoreCase(pszValue: ?[*:0]const u8, comptime pszExpected: [*:0]const u8) bool {
    return pszValue != null and c.strcasecmp(pszValue, pszExpected) == 0;
}

fn freeCString(pszValue: [*c]u8) void {
    if (pszValue) |value| {
        c.free(value);
    }
}

fn duplicateCString(pszValue: ?[*:0]const u8, ppOut: *allowzero [*c]u8) u32 {
    if (pszValue == null) {
        ppOut.* = null;
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const pszDup = c.strdup(pszValue) orelse {
        ppOut.* = null;
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    };

    ppOut.* = @ptrCast(pszDup);
    return 0;
}

fn replaceStringField(ppField: *allowzero [*c]u8, pszValue: ?[*:0]const u8) u32 {
    freeCString(ppField.*);
    ppField.* = null;
    return duplicateCString(pszValue, ppField);
}

fn duplicateArgVector(ppszCmds: *[*c][*c]u8, nCount: usize) u32 {
    const pAllocated = c.calloc(nCount + 1, @sizeOf([*c]u8)) orelse {
        ppszCmds.* = null;
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    };
    ppszCmds.* = @ptrCast(@alignCast(pAllocated));
    return 0;
}

fn createOptionNode(name: ?[*:0]const u8, value: ?[*:0]const u8) ?*abi.struct_cnfnode {
    const cn = abi.create_cnfnode(name) orelse return null;
    abi.cnfnode_setval(cn, value);
    return cn;
}

fn appendNode(parent: [*c]abi.struct_cnfnode, name: ?[*:0]const u8, value: ?[*:0]const u8) u32 {
    const cn = createOptionNode(name, value) orelse return abi.ERROR_TDNF_OUT_OF_MEMORY;
    abi.append_node(parent, cn);
    return 0;
}

fn findRepoNode(root: [*c]abi.struct_cnfnode, pszRepoName: ?[*:0]const u8) ?*abi.struct_cnfnode {
    if (root == null) {
        return null;
    }
    return abi.find_node(root[0].first_child, pszRepoName);
}

fn parseSetOpt(pszArg: ?[*:0]const u8, pCmdArgs: *abi.TDNF_CMD_ARGS) u32 {
    var dwError: u32 = 0;
    var pszCopyArgs: [*c]u8 = null;

    if (pszArg == null) {
        return abi.ERROR_TDNF_CLI_OPTION_ARG_REQUIRED;
    }

    dwError = duplicateCString(pszArg, &pszCopyArgs);
    if (dwError != 0) {
        return dwError;
    }
    defer freeCString(pszCopyArgs);

    const psep_eq = c.strstr(pszCopyArgs, "=") orelse return abi.ERROR_TDNF_CLI_SETOPT_NO_EQUALS;
    psep_eq[0] = 0;

    const pseq_dot = c.strstr(pszCopyArgs, ".");
    if (pseq_dot == null) {
        return appendNode(pCmdArgs.cn_setopts, pszCopyArgs, psep_eq + 1);
    }

    pseq_dot[0] = 0;
    if (TDNFStrIsValidRepoName(pszCopyArgs) == 0) {
        return abi.ERROR_TDNF_INVALID_REPO_NAME;
    }

    var cn_repo = findRepoNode(pCmdArgs.cn_repoopts, pszCopyArgs);
    if (cn_repo == null) {
        cn_repo = abi.create_cnfnode(pszCopyArgs) orelse return abi.ERROR_TDNF_OUT_OF_MEMORY;
        abi.append_node(pCmdArgs.cn_repoopts, cn_repo);
    }

    return appendNode(cn_repo, pseq_dot + 1, psep_eq + 1);
}

fn parseExclude(pszName: ?[*:0]const u8, pszArg: ?[*:0]const u8, pCmdArgs: *abi.TDNF_CMD_ARGS) u32 {
    var dwError: u32 = 0;
    var pszCopyArgs: [*c]u8 = null;

    dwError = duplicateCString(pszArg, &pszCopyArgs);
    if (dwError != 0) {
        return dwError;
    }
    defer freeCString(pszCopyArgs);

    var pszWalker: [*c]u8 = pszCopyArgs;
    while (c.strsep(&pszWalker, ",:")) |pszToken| {
        dwError = appendNode(pCmdArgs.cn_setopts, pszName, pszToken);
        if (dwError != 0) {
            return dwError;
        }
    }

    return 0;
}

fn appendGenericSetOpt(pszName: ?[*:0]const u8, pszArg: ?[*:0]const u8, pCmdArgs: *abi.TDNF_CMD_ARGS) u32 {
    var i: usize = 0;
    while (i < pstOptions.len) : (i += 1) {
        if (pstOptions[i].name != null and c.strcasecmp(pstOptions[i].name, pszName) == 0) {
            return appendNode(pCmdArgs.cn_setopts, pszName, pszArg orelse "1");
        }
    }
    return 0;
}

pub export fn TDNFCliParseArgs(
    argc: c_int,
    argv: [*c]?[*:0]u8,
    ppCmdArgs: ?*?*abi.TDNF_CMD_ARGS,
) u32 {
    var dwError: u32 = 0;
    var pCmdArgs: ?*abi.TDNF_CMD_ARGS = null;
    var nOptionIndex: c_int = 0;
    const pszDefaultInstallRoot: [*:0]const u8 = "/";

    if (ppCmdArgs == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    ppCmdArgs.?.* = null;

    resetOptionState();

    const pAllocated = c.calloc(1, @sizeOf(abi.TDNF_CMD_ARGS)) orelse return abi.ERROR_TDNF_OUT_OF_MEMORY;
    pCmdArgs = @ptrCast(@alignCast(pAllocated));
    // This function reports failure with a `u32` status rather than a Zig
    // error union, so `errdefer` would never run. Release on every failing
    // path with a `defer` gated on reaching the success return instead.
    var transfer_complete = false;
    defer if (!transfer_complete) {
        if (pCmdArgs != null) abi.TDNFFreeCmdArgs(pCmdArgs);
    };

    pCmdArgs.?.cn_setopts = abi.create_cnfnode("(setopts)") orelse return abi.ERROR_TDNF_OUT_OF_MEMORY;
    pCmdArgs.?.cn_repoopts = abi.create_cnfnode("(repoopts)") orelse return abi.ERROR_TDNF_OUT_OF_MEMORY;

    if (argv[0]) |arg0| {
        const arg0_slice = std.mem.span(arg0);
        if (arg0_slice.len >= 5 and std.mem.eql(u8, arg0_slice[arg0_slice.len - 5 ..], "tdnfj")) {
            option_state.nJsonOutput = 1;
            option_state.nAssumeYes = 1;
        }
    }

    pCmdArgs.?.nArgc = argc;
    pCmdArgs.?.ppszArgv = @ptrCast(argv);
    pCmdArgs.?.nRpmVerbosity = -1;

    argparse.TDNFCliArgParseReset();
    while (true) {
        const nOption = argparse.TDNFCliArgParseLongOnly(
            argc,
            argv,
            short_options,
            &pstOptions,
            &nOptionIndex,
        );
        if (nOption == -1) {
            break;
        }

        switch (nOption) {
            0 => {
                dwError = ParseOption(
                    pstOptions[@intCast(nOptionIndex)].name,
                    argparse.TDNFCliArgParseOptArg(),
                    pCmdArgs,
                );
                if (dwError != 0) {
                    return dwError;
                }
            },
            'b' => option_state.nBest = 1,
            'c' => {
                dwError = ParseOption("config", argparse.TDNFCliArgParseOptArg(), pCmdArgs);
                if (dwError != 0) {
                    return dwError;
                }
            },
            'C' => option_state.nCacheOnly = 1,
            'h' => option_state.nShowHelp = 1,
            'i' => {
                dwError = ParseOption("installroot", argparse.TDNFCliArgParseOptArg(), pCmdArgs);
                if (dwError != 0) {
                    return dwError;
                }
            },
            'q' => option_state.nQuiet = 1,
            'y' => option_state.nAssumeYes = 1,
            '4' => option_state.nIPv4 = 1,
            '6' => option_state.nIPv6 = 1,
            'v' => option_state.nVerbose = 1,
            '?' => {
                const optind = argparse.TDNFCliArgParseOptInd();
                const pszName = if (optind > 0 and optind - 1 < argc)
                    argv[@intCast(optind - 1)]
                else
                    null;
                dwError = HandleOptionsError(pszName, argparse.TDNFCliArgParseOptArg(), &pstOptions);
                if (dwError != 0) {
                    return dwError;
                }
            },
            else => {},
        }
    }

    dwError = TDNFCopyOptions(&option_state, pCmdArgs);
    if (dwError != 0) {
        return dwError;
    }

    var nArgIndex = argparse.TDNFCliArgParseOptInd();
    if (nArgIndex < argc) {
        // Publish `nCmdCount` only once the vector exists: `TDNFFreeCmdArgs`
        // walks `ppszCmds` for `nCmdCount` entries, so a non-zero count over a
        // null vector would fault during cleanup.
        const nCmdCount = argc - nArgIndex;
        dwError = duplicateArgVector(&pCmdArgs.?.ppszCmds, @intCast(nCmdCount));
        if (dwError != 0) {
            return dwError;
        }
        pCmdArgs.?.nCmdCount = nCmdCount;

        var nIndex: usize = 0;
        while (nArgIndex < argc) : (nArgIndex += 1) {
            if (argv[@intCast(nArgIndex)] == null or argv[@intCast(nArgIndex)].?[0] == 0) {
                common.log(LOG_ERR, "argument is empty string\n", .{});
                return abi.ERROR_TDNF_INVALID_PARAMETER;
            }

            dwError = duplicateCString(argv[@intCast(nArgIndex)], &pCmdArgs.?.ppszCmds[nIndex]);
            if (dwError != 0) {
                return dwError;
            }
            nIndex += 1;
        }
    }

    const is_replay = pCmdArgs.?.nCmdCount > 0 and
        c.strcmp(pCmdArgs.?.ppszCmds[0], "replay") == 0;
    if (pCmdArgs.?.pszInstallRoot == null) {
        dwError = duplicateCString(pszDefaultInstallRoot, &pCmdArgs.?.pszInstallRoot);
        if (dwError != 0) {
            return dwError;
        }
    } else if (pCmdArgs.?.pszInstallRoot[0] != '/' and !is_replay) {
        common.log(help.parserDiagnosticLevel(LOG_CRIT), "Install root must be an absolute path.\n", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    if (!is_replay) {
        if (pCmdArgs.?.pszDownloadDir != null and pCmdArgs.?.nDownloadOnly == 0) {
            return abi.ERROR_TDNF_CLI_DOWNLOADDIR_REQUIRES_DOWNLOADONLY;
        }

        if (pCmdArgs.?.nAllDeps != 0 and pCmdArgs.?.nDownloadOnly == 0 and pCmdArgs.?.nUrlsOnly == 0) {
            return abi.ERROR_TDNF_CLI_ALLDEPS_REQUIRES_DOWNLOADONLY;
        }

        if (pCmdArgs.?.nNoDeps != 0 and pCmdArgs.?.nDownloadOnly == 0 and pCmdArgs.?.nUrlsOnly == 0) {
            return abi.ERROR_TDNF_CLI_NODEPS_REQUIRES_DOWNLOADONLY;
        }
    }

    ppCmdArgs.?.* = pCmdArgs;
    transfer_complete = true;
    return 0;
}

pub export fn TDNFCopyOptions(
    pOptionArgs: ?*abi.TDNF_CMD_ARGS,
    pArgs: ?*abi.TDNF_CMD_ARGS,
) u32 {
    const option_args = pOptionArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const args = pArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;

    args.nAllDeps = option_args.nAllDeps;
    args.nAllowErasing = option_args.nAllowErasing;
    args.nAssumeNo = option_args.nAssumeNo;
    args.nAssumeYes = option_args.nAssumeYes;
    args.nBest = option_args.nBest;
    args.nCacheOnly = option_args.nCacheOnly;
    args.nDebugSolver = option_args.nDebugSolver;
    args.nNoDeps = option_args.nNoDeps;
    args.nNoGPGCheck = option_args.nNoGPGCheck;
    args.nNoCmdLineGPGCheck = option_args.nNoCmdLineGPGCheck;
    args.nSkipSignature = option_args.nSkipSignature;
    args.nSkipDigest = option_args.nSkipDigest;
    args.nNoOutput = @intFromBool(option_args.nQuiet != 0 and option_args.nAssumeYes != 0);
    args.nQuiet = option_args.nQuiet;
    args.nRefresh = option_args.nRefresh;
    args.nShowDuplicates = option_args.nShowDuplicates;
    args.nShowHelp = option_args.nShowHelp;
    args.nShowVersion = option_args.nShowVersion;
    args.nVerbose = option_args.nVerbose;
    args.nIPv4 = option_args.nIPv4;
    args.nIPv6 = option_args.nIPv6;
    args.nDisableExcludes = option_args.nDisableExcludes;
    args.nDownloadOnly = option_args.nDownloadOnly;
    args.nUrlsOnly = option_args.nUrlsOnly;
    args.nNoAutoRemove = option_args.nNoAutoRemove;
    args.nJsonOutput = option_args.nJsonOutput;
    args.nTestOnly = option_args.nTestOnly;
    args.nSkipBroken = option_args.nSkipBroken;
    args.nSource = option_args.nSource;
    args.nBuildDeps = option_args.nBuildDeps;

    return 0;
}

pub export fn ParseOption(
    pszName: ?[*:0]const u8,
    pszArg: ?[*:0]const u8,
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
) u32 {
    const cmd_args = pCmdArgs orelse return abi.ERROR_TDNF_CLI_INVALID_ARGUMENT;
    if (pszName == null) {
        return abi.ERROR_TDNF_CLI_INVALID_ARGUMENT;
    }

    const dwError = options.validateOptionsRaw(pszName, pszArg, @ptrCast(&pstOptions));
    if (dwError != 0) {
        return dwError;
    }

    if (equalsIgnoreCase(pszName, "config")) {
        return replaceStringField(&cmd_args.pszConfFile, pszArg);
    }
    if (equalsIgnoreCase(pszName, "rpmverbosity")) {
        return ParseRpmVerbosity(pszArg, &cmd_args.nRpmVerbosity);
    }
    if (equalsIgnoreCase(pszName, "installroot")) {
        return replaceStringField(&cmd_args.pszInstallRoot, pszArg);
    }
    if (equalsIgnoreCase(pszName, "forcearch") and cmd_args.pszArch == null) {
        return replaceStringField(&cmd_args.pszArch, pszArg);
    }
    if (equalsIgnoreCase(pszName, "downloaddir")) {
        return replaceStringField(&cmd_args.pszDownloadDir, pszArg);
    }
    if (equalsIgnoreCase(pszName, "releasever")) {
        return replaceStringField(&cmd_args.pszReleaseVer, pszArg);
    }
    if (equalsIgnoreCase(pszName, "setopt")) {
        return parseSetOpt(pszArg, cmd_args);
    }
    if (equalsIgnoreCase(pszName, "exclude")) {
        return parseExclude(pszName, pszArg, cmd_args);
    }

    return appendGenericSetOpt(pszName, pszArg, cmd_args);
}

pub export fn ParseRpmVerbosity(
    pszRpmVerbosity: ?[*:0]const u8,
    pnRpmVerbosity: ?*c_int,
) u32 {
    const out = pnRpmVerbosity orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    _ = pszRpmVerbosity orelse return abi.ERROR_TDNF_INVALID_PARAMETER;

    out.* = LEGACY_VERBOSITY_INFO;
    return 0;
}

pub export fn HandleOptionsError(
    pszName: ?[*:0]const u8,
    pszArg: ?[*:0]const u8,
    pstOpts: [*c]getopt.struct_option,
) u32 {
    if (isNullOrEmpty(pszName) or pstOpts == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const dwError = options.validateOptionsRaw(pszName, pszArg, @ptrCast(pstOpts));
    if (dwError == abi.ERROR_TDNF_CLI_OPTION_NAME_INVALID) {
        help.TDNFCliShowNoSuchOption(pszName);
    } else if (dwError == abi.ERROR_TDNF_CLI_OPTION_ARG_REQUIRED) {
        common.log(LOG_ERR, "Option %s requires an argument\n", .{pszName.?});
    }

    return dwError;
}

test "ParseRpmVerbosity is a compatibility no-op" {
    var nVerbosity: c_int = -1;

    try std.testing.expectEqual(@as(u32, 0), ParseRpmVerbosity("DeBuG", &nVerbosity));
    try std.testing.expectEqual(LEGACY_VERBOSITY_INFO, nVerbosity);

    try std.testing.expectEqual(@as(u32, 0), ParseRpmVerbosity("unknown", &nVerbosity));
    try std.testing.expectEqual(LEGACY_VERBOSITY_INFO, nVerbosity);
}

test "ParseOption preserves repo-scoped setopt handling" {
    var cmd_args: abi.TDNF_CMD_ARGS = std.mem.zeroes(abi.TDNF_CMD_ARGS);
    cmd_args.cn_setopts = abi.create_cnfnode("(setopts)");
    cmd_args.cn_repoopts = abi.create_cnfnode("(repoopts)");
    defer abi.destroy_cnftree(cmd_args.cn_setopts);
    defer abi.destroy_cnftree(cmd_args.cn_repoopts);

    try std.testing.expectEqual(
        @as(u32, 0),
        ParseOption("setopt", "photon.skip_if_unavailable=1", &cmd_args),
    );

    const cn_repo = abi.find_node(cmd_args.cn_repoopts[0].first_child, "photon");
    try std.testing.expect(cn_repo != null);
    const cn_opt = abi.find_node(cn_repo[0].first_child, "skip_if_unavailable");
    try std.testing.expect(cn_opt != null);
    try std.testing.expectEqualStrings("1", std.mem.span(abi.cnfnode_getval(cn_opt.?)));
}
