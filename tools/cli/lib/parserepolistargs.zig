// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const abi = @import("tdnf_internal_abi");
const choice_parse = @import("choice_parse.zig");

const FilterType = choice_parse.NamedValue(abi.TDNF_REPOLISTFILTER);
const filter_types = [_]FilterType{
    .{ .name = "all", .value = abi.REPOLISTFILTER_ALL },
    .{ .name = "enabled", .value = abi.REPOLISTFILTER_ENABLED },
    .{ .name = "disabled", .value = abi.REPOLISTFILTER_DISABLED },
};

fn setFilterOut(pnFilter: ?*abi.TDNF_REPOLISTFILTER, nFilter: abi.TDNF_REPOLISTFILTER) void {
    if (pnFilter) |out| {
        out.* = nFilter;
    }
}

pub export fn TDNFCliParseRepoListArgs(
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
    pnFilter: ?*abi.TDNF_REPOLISTFILTER,
) u32 {
    var nFilter: abi.TDNF_REPOLISTFILTER = abi.REPOLISTFILTER_ENABLED;

    if (pCmdArgs == null or pnFilter == null) {
        setFilterOut(pnFilter, abi.REPOLISTFILTER_ENABLED);
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const cmd_args = pCmdArgs.?;
    if (cmd_args.nCmdCount > 1) {
        const dwError = TDNFCliParseFilter(cmd_args.ppszCmds[1], &nFilter);
        if (dwError != 0) {
            setFilterOut(pnFilter, abi.REPOLISTFILTER_ENABLED);
            return dwError;
        }
    }

    pnFilter.?.* = nFilter;
    return 0;
}

pub export fn TDNFCliParseFilter(
    pszFilter: ?[*:0]const u8,
    pnFilter: ?*abi.TDNF_REPOLISTFILTER,
) u32 {
    const out = pnFilter orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const nFilter = choice_parse.parseChoice(abi.TDNF_REPOLISTFILTER, pszFilter, &filter_types) orelse {
        out.* = abi.REPOLISTFILTER_ENABLED;
        return if (pszFilter == null)
            abi.ERROR_TDNF_INVALID_PARAMETER
        else
            abi.ERROR_TDNF_CLI_NO_MATCH;
    };

    out.* = nFilter;
    return 0;
}

test "TDNFCliParseFilter preserves repolist filters" {
    var nFilter: abi.TDNF_REPOLISTFILTER = abi.REPOLISTFILTER_ALL;

    try std.testing.expectEqual(@as(u32, 0), TDNFCliParseFilter("DisAbLeD", &nFilter));
    try std.testing.expectEqual(
        @as(@TypeOf(nFilter), @intCast(abi.REPOLISTFILTER_DISABLED)),
        nFilter,
    );
}
