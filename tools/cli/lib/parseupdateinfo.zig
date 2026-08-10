// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const abi = @import("tdnf_internal_abi");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("nodes.h");
});
const choice_parse = @import("choice_parse.zig");
const parselistargs = @import("parselistargs.zig");

const ModeChoice = choice_parse.NamedValue(abi.TDNF_UPDATEINFO_OUTPUT);
const modes = [_]ModeChoice{
    .{ .name = "summary", .value = abi.OUTPUT_SUMMARY },
    .{ .name = "list", .value = abi.OUTPUT_LIST },
    .{ .name = "info", .value = abi.OUTPUT_INFO },
};

fn duplicateString(pszValue: [*c]const u8, ppOut: *allowzero [*c]u8) u32 {
    if (pszValue == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    const pszDup = c.strdup(pszValue) orelse return abi.ERROR_TDNF_OUT_OF_MEMORY;
    ppOut.* = @ptrCast(pszDup);
    return 0;
}

fn allocateCStringArray(nCount: usize) [*c][*c]u8 {
    const pAllocated = c.calloc(nCount + 1, @sizeOf([*c]u8)) orelse return null;
    return @ptrCast(@alignCast(pAllocated));
}

fn freeStringArray(ppszArray: [*c][*c]u8) void {
    if (ppszArray != null) {
        var i: usize = 0;
        while (ppszArray[i] != null) : (i += 1) {
            c.free(ppszArray[i]);
        }
        c.free(@ptrCast(ppszArray));
    }
}

fn duplicateCmdArgs(
    ppszCmds: [*c][*c]u8,
    nStartIndex: c_int,
    nCount: c_int,
    ppOut: *[*c][*c]u8,
) u32 {
    const count: usize = @intCast(nCount);
    const start_index: usize = @intCast(nStartIndex);
    const ppszDuped = allocateCStringArray(count);
    if (ppszDuped == null) {
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    }
    var i: usize = 0;

    while (i < count) : (i += 1) {
        const dwError = duplicateString(ppszCmds[start_index + i], &ppszDuped[i]);
        if (dwError != 0) {
            freeStringArray(ppszDuped);
            return dwError;
        }
    }

    ppOut.* = ppszDuped;
    return 0;
}

fn freeUpdateInfoArgs(pUpdateInfoArgs: *abi.TDNF_UPDATEINFO_ARGS) void {
    freeStringArray(pUpdateInfoArgs.ppszPackageNameSpecs);
    c.free(pUpdateInfoArgs);
}

pub export fn TDNFCliParseUpdateInfoArgs(
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
    ppUpdateInfoArgs: ?*[*c]abi.TDNF_UPDATEINFO_ARGS,
) u32 {
    const cmd_args = pCmdArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const out = ppUpdateInfoArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    if (cmd_args.nCmdCount < 1) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const pAllocated = c.calloc(1, @sizeOf(abi.TDNF_UPDATEINFO_ARGS)) orelse
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    const pUpdateInfoArgs: *abi.TDNF_UPDATEINFO_ARGS = @ptrCast(@alignCast(pAllocated));

    pUpdateInfoArgs.nMode = abi.OUTPUT_SUMMARY;
    pUpdateInfoArgs.nScope = abi.SCOPE_AVAILABLE;

    var pNode: [*c]abi.struct_cnfnode = if (cmd_args.cn_setopts != null) cmd_args.cn_setopts[0].first_child else null;
    while (pNode != null) : (pNode = pNode[0].next) {
        var dwError = parselistargs.TDNFCliParseScope(pNode[0].name, &pUpdateInfoArgs.nScope);
        if (dwError == 0) {
            continue;
        }
        if (dwError == abi.ERROR_TDNF_CLI_NO_MATCH) {
            dwError = 0;
        }
        if (dwError != 0) {
            freeUpdateInfoArgs(pUpdateInfoArgs);
            return dwError;
        }

        dwError = TDNFCliParseMode(pNode[0].name, &pUpdateInfoArgs.nMode);
        if (dwError == abi.ERROR_TDNF_CLI_NO_MATCH) {
            continue;
        }
        if (dwError != 0) {
            freeUpdateInfoArgs(pUpdateInfoArgs);
            return dwError;
        }
    }

    var nStartIndex: c_int = 1;
    if (cmd_args.nCmdCount > nStartIndex) {
        var dwError = TDNFCliParseMode(cmd_args.ppszCmds[@intCast(nStartIndex)], &pUpdateInfoArgs.nMode);
        if (dwError == abi.ERROR_TDNF_CLI_NO_MATCH) {
            dwError = 0;
            nStartIndex -= 1;
        }
        if (dwError != 0) {
            freeUpdateInfoArgs(pUpdateInfoArgs);
            return dwError;
        }
        nStartIndex += 1;
    }

    if (cmd_args.nCmdCount > nStartIndex) {
        var dwError = parselistargs.TDNFCliParseScope(cmd_args.ppszCmds[@intCast(nStartIndex)], &pUpdateInfoArgs.nScope);
        if (dwError == abi.ERROR_TDNF_CLI_NO_MATCH) {
            dwError = 0;
            nStartIndex -= 1;
        }
        if (dwError != 0) {
            freeUpdateInfoArgs(pUpdateInfoArgs);
            return dwError;
        }
        nStartIndex += 1;
    }

    const nPackageCount = cmd_args.nCmdCount - nStartIndex;
    const dwError = duplicateCmdArgs(cmd_args.ppszCmds, nStartIndex, nPackageCount, &pUpdateInfoArgs.ppszPackageNameSpecs);
    if (dwError != 0) {
        freeUpdateInfoArgs(pUpdateInfoArgs);
        return dwError;
    }

    out.* = pUpdateInfoArgs;
    return 0;
}

pub export fn TDNFCliParseMode(
    pszMode: [*c]const u8,
    pnMode: ?*abi.TDNF_UPDATEINFO_OUTPUT,
) u32 {
    const out = pnMode orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    if (pszMode == null or pszMode[0] == 0) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const nMode = choice_parse.parseChoice(abi.TDNF_UPDATEINFO_OUTPUT, @ptrCast(pszMode), &modes) orelse
        return abi.ERROR_TDNF_CLI_NO_MATCH;
    out.* = nMode;
    return 0;
}

pub export fn TDNFCliFreeUpdateInfoArgs(pUpdateInfoArgs: ?*abi.TDNF_UPDATEINFO_ARGS) void {
    if (pUpdateInfoArgs) |updateinfo_args| {
        freeUpdateInfoArgs(updateinfo_args);
    }
}

test "TDNFCliParseMode preserves updateinfo modes" {
    var nMode: abi.TDNF_UPDATEINFO_OUTPUT = abi.OUTPUT_SUMMARY;

    try std.testing.expectEqual(@as(u32, 0), TDNFCliParseMode("InFo", &nMode));
    try std.testing.expectEqual(
        @as(@TypeOf(nMode), @intCast(abi.OUTPUT_INFO)),
        nMode,
    );
}
