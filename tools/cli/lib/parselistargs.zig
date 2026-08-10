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

const ScopeChoice = choice_parse.NamedValue(abi.TDNF_SCOPE);
const scopes = [_]ScopeChoice{
    .{ .name = "all", .value = abi.SCOPE_ALL },
    .{ .name = "installed", .value = abi.SCOPE_INSTALLED },
    .{ .name = "available", .value = abi.SCOPE_AVAILABLE },
    .{ .name = "extras", .value = abi.SCOPE_EXTRAS },
    .{ .name = "obsoletes", .value = abi.SCOPE_OBSOLETES },
    .{ .name = "recent", .value = abi.SCOPE_RECENT },
    .{ .name = "upgrades", .value = abi.SCOPE_UPGRADES },
    .{ .name = "updates", .value = abi.SCOPE_UPGRADES },
    .{ .name = "downgrades", .value = abi.SCOPE_DOWNGRADES },
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

fn freeStringArray(ppszArray: [*c][*c]u8) void {
    if (ppszArray != null) {
        var i: usize = 0;
        while (ppszArray[i] != null) : (i += 1) {
            c.free(ppszArray[i]);
        }
        c.free(@ptrCast(ppszArray));
    }
}

fn freeListArgs(pListArgs: *abi.TDNF_LIST_ARGS) void {
    freeStringArray(pListArgs.ppszPackageNameSpecs);
    c.free(pListArgs);
}

pub export fn TDNFCliParseInfoArgs(
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
    ppListArgs: ?*[*c]abi.TDNF_LIST_ARGS,
) u32 {
    return TDNFCliParseListArgs(pCmdArgs, ppListArgs);
}

pub export fn TDNFCliParsePackageArgs(
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
    pppszPackageArgs: ?*[*c][*c]u8,
    pnPackageCount: ?*const c_int,
) u32 {
    const cmd_args = pCmdArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const out = pppszPackageArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    _ = pnPackageCount orelse return abi.ERROR_TDNF_INVALID_PARAMETER;

    const nPackageCount = cmd_args.nCmdCount - 1;
    if (nPackageCount < 0) {
        return abi.ERROR_TDNF_CLI_NOT_ENOUGH_ARGS;
    }

    return duplicateCmdArgs(cmd_args.ppszCmds, 1, nPackageCount, out);
}

pub export fn TDNFCliParseListArgs(
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
    ppListArgs: ?*[*c]abi.TDNF_LIST_ARGS,
) u32 {
    const cmd_args = pCmdArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const out = ppListArgs orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    if (cmd_args.nCmdCount < 1) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const pAllocated = c.calloc(1, @sizeOf(abi.TDNF_LIST_ARGS)) orelse
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    const pListArgs: *abi.TDNF_LIST_ARGS = @ptrCast(@alignCast(pAllocated));

    pListArgs.nScope = abi.SCOPE_ALL;

    var pNode: [*c]abi.struct_cnfnode = if (cmd_args.cn_setopts != null) cmd_args.cn_setopts[0].first_child else null;
    while (pNode != null) : (pNode = pNode[0].next) {
        const dwError = TDNFCliParseScope(pNode[0].name, &pListArgs.nScope);
        if (dwError == abi.ERROR_TDNF_CLI_NO_MATCH) {
            continue;
        }
        if (dwError != 0) {
            freeListArgs(pListArgs);
            return dwError;
        }
    }

    var nStartIndex: c_int = 1;
    if (cmd_args.nCmdCount > 1) {
        nStartIndex = 2;
        const dwError = TDNFCliParseScope(cmd_args.ppszCmds[1], &pListArgs.nScope);
        if (dwError == abi.ERROR_TDNF_CLI_NO_MATCH) {
            nStartIndex = 1;
        } else if (dwError != 0) {
            freeListArgs(pListArgs);
            return dwError;
        }
    }

    const nPackageCount = cmd_args.nCmdCount - nStartIndex;
    const dwError = duplicateCmdArgs(cmd_args.ppszCmds, nStartIndex, nPackageCount, &pListArgs.ppszPackageNameSpecs);
    if (dwError != 0) {
        freeListArgs(pListArgs);
        return dwError;
    }

    out.* = pListArgs;
    return 0;
}

pub export fn TDNFCliParseScope(
    pszScope: [*c]const u8,
    pnScope: ?*abi.TDNF_SCOPE,
) u32 {
    const out = pnScope orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    if (pszScope == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const nScope = choice_parse.parseChoice(abi.TDNF_SCOPE, @ptrCast(pszScope), &scopes) orelse
        return abi.ERROR_TDNF_CLI_NO_MATCH;
    out.* = nScope;
    return 0;
}

pub export fn TDNFCliFreeListArgs(pListArgs: ?*abi.TDNF_LIST_ARGS) void {
    if (pListArgs) |list_args| {
        freeListArgs(list_args);
    }
}

test "TDNFCliParseScope preserves list scope aliases" {
    var nScope: abi.TDNF_SCOPE = abi.SCOPE_ALL;

    try std.testing.expectEqual(@as(u32, 0), TDNFCliParseScope("UpDaTeS", &nScope));
    try std.testing.expectEqual(
        @as(@TypeOf(nScope), @intCast(abi.SCOPE_UPGRADES)),
        nScope,
    );
}
