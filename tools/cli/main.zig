// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const jsondump = @import("jsondump_abi");
const common = @import("tdnf_common");
const client = @import("tdnf_client");
const cli = @import("tdnf_cli");
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

fn planAlterType(
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
    pnAlterType: *abi.TDNF_ALTERTYPE,
) u32 {
    const cmd_args = pCmdArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    if (cmd_args.nCmdCount < 2) {
        common.log(LOG_CRIT, "need transaction command as argument\n", .{});
        return abi.ERROR_TDNF_CLI_NOT_ENOUGH_ARGS;
    }

    const transaction_count = cmd_args.nCmdCount - 1;
    const pszTransaction = cmd_args.ppszCmds[1];
    if (c.strcmp(pszTransaction, "install") == 0) {
        pnAlterType.* = abi.ALTER_INSTALL;
    } else if (c.strcmp(pszTransaction, "erase") == 0 or
        c.strcmp(pszTransaction, "remove") == 0)
    {
        pnAlterType.* = abi.ALTER_ERASE;
    } else if (c.strcmp(pszTransaction, "upgrade") == 0 or
        c.strcmp(pszTransaction, "update") == 0 or
        c.strcmp(pszTransaction, "upgrade-to") == 0 or
        c.strcmp(pszTransaction, "update-to") == 0)
    {
        pnAlterType.* = if (transaction_count == 1)
            abi.ALTER_UPGRADEALL
        else
            abi.ALTER_UPGRADE;
    } else if (c.strcmp(pszTransaction, "downgrade") == 0) {
        pnAlterType.* = if (transaction_count == 1)
            abi.ALTER_DOWNGRADEALL
        else
            abi.ALTER_DOWNGRADE;
    } else if (c.strcmp(pszTransaction, "distro-sync") == 0) {
        pnAlterType.* = abi.ALTER_DISTRO_SYNC;
    } else if (c.strcmp(pszTransaction, "reinstall") == 0) {
        pnAlterType.* = abi.ALTER_REINSTALL;
    } else if (c.strcmp(pszTransaction, "autoerase") == 0 or
        c.strcmp(pszTransaction, "autoremove") == 0)
    {
        pnAlterType.* = if (transaction_count == 1)
            abi.ALTER_AUTOERASEALL
        else
            abi.ALTER_AUTOERASE;
    } else {
        common.log(LOG_CRIT, "unsupported transaction plan command '%s'\n", .{pszTransaction});
        return abi.ERROR_TDNF_CLI_INVALID_ARGUMENT;
    }

    return 0;
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

    var nAlterType: abi.TDNF_ALTERTYPE = undefined;
    var dwError = planAlterType(cmd_args, &nAlterType);
    if (dwError != 0) {
        return dwError;
    }

    dwError = abi.TDNFTransactionPlanSetEnabled(handle, 1);
    if (dwError != 0) {
        return dwError;
    }

    const ppszSavedCmds = cmd_args.ppszCmds;
    const nSavedCmdCount = cmd_args.nCmdCount;
    cmd_args.ppszCmds += 1;
    cmd_args.nCmdCount -= 1;
    defer {
        cmd_args.ppszCmds = ppszSavedCmds;
        cmd_args.nCmdCount = nSavedCmdCount;
    }

    var pSolvedPkgInfo: ?*abi.TDNF_SOLVED_PKG_INFO = null;
    defer abi.TDNFFreeSolvedPackageInfo(pSolvedPkgInfo);

    const dwResolveError = context.pFnResolve.?(context, nAlterType, &pSolvedPkgInfo);
    var pszJson: [*c]u8 = null;
    const dwPlanError = abi.TDNFTransactionPlanGetCanonicalJson(handle, &pszJson);
    defer abi.TDNFTransactionPlanFreeCanonicalJson(pszJson);

    if (dwPlanError != 0) {
        return if (dwResolveError != 0) dwResolveError else dwPlanError;
    }
    if (pszJson == null) {
        return abi.ERROR_TDNF_NO_DATA;
    }

    // Unsatisfied and conflicting requests are reported as structured problem
    // plans. Once those canonical bytes are emitted, the CLI command succeeded.
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
        abi.TDNFUninit();
    }

    dwError = abi.TDNFCliParseArgs(argc, @ptrCast(argv_ptr), &pCmdArgs);
    if (dwError == 0) {
        const cmd_args = pCmdArgs.?;

        if (cmd_args.nShowVersion != 0) {
            TDNFCliShowVersion(cmd_args);
        } else if (cmd_args.nShowHelp != 0) {
            abi.TDNFCliShowHelp();
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

    if (dwError != 0) {
        _ = TDNFCliPrintError(dwError, if (pCmdArgs) |args| args.nJsonOutput else 0);
        if (dwError == abi.ERROR_TDNF_CLI_NOTHING_TO_DO or dwError == abi.ERROR_TDNF_NO_DATA) {
            dwError = 0;
        }
    }

    return @truncate(dwError);
}
