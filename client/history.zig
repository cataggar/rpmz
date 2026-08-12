// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const tdnf_error = @import("tdnf_error");
const abi = @import("client_abi");

pub const CmdArgs = abi.CmdArgs;
pub const Conf = abi.Conf;
pub const Tdnf = abi.Tdnf;

pub const HistoryCtx = opaque {};
const TxnConfig = opaque {};

extern fn history_open_config(
    config: ?*const TxnConfig,
    persist_dir: ?[*:0]const u8,
    must_exist: c_int,
    output: ?*?*HistoryCtx,
) c_int;

pub export fn TDNFGetHistoryCtx(
    pTdnf: ?*Tdnf,
    ppCtx: ?*?*HistoryCtx,
    nMustExist: c_int,
) u32 {
    if (pTdnf == null or ppCtx == null) {
        return tdnf_error.ERROR_TDNF_INVALID_PARAMETER;
    }

    const tdnf = pTdnf.?;
    const conf = tdnf.pConf orelse
        return tdnf_error.ERROR_TDNF_INVALID_PARAMETER;
    const raw_config = tdnf.pRpmConfig orelse
        return tdnf_error.ERROR_TDNF_INVALID_PARAMETER;
    const result = history_open_config(
        @ptrCast(@alignCast(raw_config)),
        conf.pszPersistDir,
        nMustExist,
        ppCtx,
    );
    if (result == 0) return 0;
    if (result == 1) return tdnf_error.ERROR_TDNF_HISTORY_NODB;
    if (result == 2) return tdnf_error.ERROR_TDNF_INVALID_DIR;
    return tdnf_error.ERROR_TDNF_HISTORY_ERROR;
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
