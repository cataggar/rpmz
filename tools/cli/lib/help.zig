// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("tdnf_common");
const abi = @import("tdnf_internal_abi");

const LOG_CRIT: c_int = 2;
const help_msg = @embedFile("help.txt");

pub export fn TDNFCliShowUsage() void {
    common.log(LOG_CRIT, "You need to give some command\n", .{});
    TDNFCliShowHelp();
}

pub export fn TDNFCliShowHelp() void {
    common.log(LOG_CRIT, "%.*s\n", .{ @as(c_int, @intCast(help_msg.len)), help_msg.ptr });
}

pub export fn TDNFCliShowNoSuchCommand(pszCmd: ?[*:0]const u8) void {
    common.log(LOG_CRIT, "No such command: %s. Please use /usr/bin/tdnf --help\n", .{pszCmd orelse ""});
}

pub export fn TDNFCliShowNoSuchOption(pszOption: ?[*:0]const u8) void {
    common.log(LOG_CRIT, "No such option: %s. Please use /usr/bin/tdnf --help\n", .{pszOption orelse ""});
}

pub export fn TDNFCliHelpCommand(
    pContext: ?*abi.TDNF_CLI_CONTEXT,
    pCmdArgs: ?*abi.TDNF_CMD_ARGS,
) u32 {
    if (pCmdArgs == null or pContext == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    TDNFCliShowHelp();
    return 0;
}

test "help text preserves usage heading" {
    try std.testing.expect(std.mem.startsWith(u8, help_msg, "Usage: tdnf [options] COMMAND\n"));
    try std.testing.expect(std.mem.indexOf(u8, help_msg, "Please refer to https://github.com/vmware/tdnf/wiki") != null);
}
