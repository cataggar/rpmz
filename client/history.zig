// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const tdnf_error = @import("tdnf_error");

pub const CmdArgs = extern struct {
    option_values: [31]c_int = [_]c_int{0} ** 31,
    pszArch: ?[*:0]u8 = null,
    pszDownloadDir: ?[*:0]u8 = null,
    pszInstallRoot: ?[*:0]u8 = null,
};

pub const Conf = extern struct {
    integer_values_before_flags: [10]c_int = [_]c_int{0} ** 10,
    rpmTransFlags: u32 = 0,
    integer_values_after_flags: [3]c_int = [_]c_int{0} ** 3,
    pszRepoDir: ?[*:0]u8 = null,
    pszCacheDir: ?[*:0]u8 = null,
    pszPersistDir: ?[*:0]u8 = null,
};

pub const Tdnf = extern struct {
    pSack: ?*anyopaque = null,
    pArgs: ?*CmdArgs = null,
    pConf: ?*Conf = null,
};

pub const HistoryCtx = opaque {};

extern fn TDNFJoinPathFromArray(
    ppszPath: ?*?[*:0]u8,
    ppszNodes: [*c]?[*:0]u8,
    nCount: c_int,
) u32;
extern fn TDNFFreeMemory(pMemory: ?*anyopaque) void;
extern fn TDNFIsFileOrSymlink(
    pszPath: ?[*:0]const u8,
    pnPathIsFile: ?*c_int,
) u32;
extern fn TDNFUtilsMakeDirs(pszPath: ?[*:0]const u8) u32;
extern fn create_history_ctx(
    db_filename: ?[*:0]const u8,
) ?*HistoryCtx;

fn freeString(value: ?[*:0]u8) void {
    if (value) |pointer| TDNFFreeMemory(@ptrCast(pointer));
}

fn joinPath(
    out: *?[*:0]u8,
    nodes: []const ?[*:0]u8,
) u32 {
    var count: usize = 0;
    while (count < nodes.len and nodes[count] != null) : (count += 1) {}
    return TDNFJoinPathFromArray(
        out,
        @ptrCast(@constCast(nodes.ptr)),
        @intCast(count),
    );
}

pub export fn TDNFGetHistoryCtx(
    pTdnf: ?*Tdnf,
    ppCtx: ?*?*HistoryCtx,
    nMustExist: c_int,
) u32 {
    if (pTdnf == null or ppCtx == null) {
        return tdnf_error.ERROR_TDNF_INVALID_PARAMETER;
    }

    const tdnf = pTdnf.?;
    const args = tdnf.pArgs.?;
    const conf = tdnf.pConf.?;
    var data_dir: ?[*:0]u8 = null;
    defer freeString(data_dir);
    var history_db: ?[*:0]u8 = null;
    defer freeString(history_db);

    const data_nodes = [_]?[*:0]u8{
        args.pszInstallRoot,
        conf.pszPersistDir,
    };
    var result = joinPath(&data_dir, &data_nodes);
    if (result != 0) return result;

    const history_nodes = [_]?[*:0]u8{
        data_dir,
        @constCast(@as([*:0]const u8, "history.db")),
    };
    result = joinPath(&history_db, &history_nodes);
    if (result != 0) return result;

    if (nMustExist != 0) {
        var exists: c_int = 0;
        result = TDNFIsFileOrSymlink(history_db, &exists);
        if (result != 0) return result;
        if (exists == 0) return tdnf_error.ERROR_TDNF_HISTORY_NODB;
    }

    result = TDNFUtilsMakeDirs(data_dir);
    if (result == tdnf_error.ERROR_TDNF_ALREADY_EXISTS) result = 0;
    if (result != 0) return result;

    const context = create_history_ctx(history_db) orelse
        return tdnf_error.ERROR_TDNF_HISTORY_ERROR;
    ppCtx.?.* = context;
    return 0;
}

comptime {
    if (@offsetOf(CmdArgs, "pszInstallRoot") != 144)
        @compileError("TDNF_CMD_ARGS.pszInstallRoot ABI drift");
    if (@offsetOf(Conf, "pszPersistDir") != 72)
        @compileError("TDNF_CONF.pszPersistDir ABI drift");
    if (@offsetOf(Tdnf, "pArgs") != @sizeOf(?*anyopaque) or
        @offsetOf(Tdnf, "pConf") != 2 * @sizeOf(?*anyopaque))
        @compileError("TDNF handle prefix ABI drift");
}
