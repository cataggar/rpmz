// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const abi = @import("tdnf_internal_abi");
const choice_parse = @import("choice_parse.zig");

const CleanType = choice_parse.NamedValue(u32);
const clean_types = [_]CleanType{
    .{ .name = "packages", .value = abi.CLEANTYPE_PACKAGES },
    .{ .name = "metadata", .value = abi.CLEANTYPE_METADATA },
    .{ .name = "dbcache", .value = abi.CLEANTYPE_DBCACHE },
    .{ .name = "plugins", .value = abi.CLEANTYPE_PLUGINS },
    .{ .name = "keys", .value = abi.CLEANTYPE_KEYS },
    .{ .name = "expire-cache", .value = abi.CLEANTYPE_EXPIRE_CACHE },
    .{ .name = "all", .value = abi.CLEANTYPE_ALL },
};

fn setCleanTypeOut(pnCleanType: ?*u32, nCleanType: u32) void {
    if (pnCleanType) |out| {
        out.* = nCleanType;
    }
}

pub export fn TDNFCliParseCleanArgs(
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
    pnCleanType: ?*u32,
) u32 {
    var nCleanType: u32 = abi.CLEANTYPE_NONE;

    if (pCmdArgs == null or pnCleanType == null) {
        setCleanTypeOut(pnCleanType, abi.CLEANTYPE_NONE);
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const cmd_args = pCmdArgs.?;
    if (cmd_args.nCmdCount == 1) {
        setCleanTypeOut(pnCleanType, abi.CLEANTYPE_NONE);
        return abi.ERROR_TDNF_CLI_CLEAN_REQUIRES_OPTION;
    }

    if (cmd_args.nCmdCount > 1) {
        const dwError = TDNFCliParseCleanType(cmd_args.ppszCmds[1], &nCleanType);
        if (dwError != 0) {
            setCleanTypeOut(pnCleanType, abi.CLEANTYPE_NONE);
            return dwError;
        }
    }

    pnCleanType.?.* = nCleanType;
    return 0;
}

pub export fn TDNFCliParseCleanType(
    pszCleanType: ?[*:0]const u8,
    pnCleanType: ?*u32,
) u32 {
    const out = pnCleanType orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const nCleanType = choice_parse.parseChoice(u32, pszCleanType, &clean_types) orelse {
        out.* = abi.CLEANTYPE_NONE;
        return if (pszCleanType == null)
            abi.ERROR_TDNF_INVALID_PARAMETER
        else
            abi.ERROR_TDNF_CLI_NO_MATCH;
    };

    out.* = nCleanType;
    return 0;
}

test "TDNFCliParseCleanType preserves clean type mappings" {
    var nCleanType: u32 = abi.CLEANTYPE_NONE;

    try std.testing.expectEqual(@as(u32, 0), TDNFCliParseCleanType("ExPiRe-CaChE", &nCleanType));
    try std.testing.expectEqual(@as(u32, abi.CLEANTYPE_EXPIRE_CACHE), nCleanType);
}
