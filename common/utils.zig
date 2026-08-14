// Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("api.zig");
const variadic = @import("variadic.zig");
const abi = @import("tdnf_internal_abi");
const c = @cImport({
    @cDefine("_XOPEN_SOURCE", "500");
    @cDefine("_DEFAULT_SOURCE", "1");
    @cInclude("ctype.h");
    @cInclude("errno.h");
    @cInclude("ftw.h");
    @cInclude("libgen.h");
    @cInclude("limits.h");
    @cInclude("stdbool.h");
    @cInclude("stdint.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("strings.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
    @cInclude("../llconf/nodes.h");
});

extern fn TDNFAllocateMemory(nNumElements: usize, nSize: usize, ppMemory: ?*?*anyopaque) u32;
extern fn TDNFAllocateString(pszSrc: ?[*:0]const u8, ppszDst: ?*?[*:0]u8) u32;
extern fn TDNFFreeMemory(pMemory: ?*anyopaque) void;
extern fn TDNFFreeStringArray(ppszArray: [*c]?[*:0]u8) void;
extern fn TDNFSplitStringToArray(pszBuf: ?[*:0]const u8, pszSep: ?[*:0]const u8, pppszTokens: ?*[*c]?[*:0]u8) u32;
extern fn fgets(s: [*c]u8, n: c_int, stream: ?*c.FILE) [*c]u8;
extern fn realpath(name: [*c]const u8, resolved: [*c]u8) [*c]u8;

const DigestContext = opaque {};
extern fn tdnf_rpmzig_digest_open(kind: c_int) ?*DigestContext;
extern fn tdnf_rpmzig_digest_update(
    ctx: ?*DigestContext,
    buf: [*c]const u8,
    len: usize,
) c_int;
extern fn tdnf_rpmzig_digest_final(
    ctx: ?*DigestContext,
    out_digest: [*c]u8,
    out_len: usize,
) c_int;
extern fn tdnf_rpmzig_digest_close(ctx: ?*DigestContext) void;
extern fn tdnf_rpmzig_checksum_last_error() [*c]const u8;

const hash_md5: c_int = 0;
const hash_sha1: c_int = 1;
const hash_sha256: c_int = 2;
const hash_sha512: c_int = 3;
const hash_sentinel: c_int = 4;
const hash_count: usize = 4;
const max_digest_len: usize = 64;

const HashOp = extern struct {
    hash_type: [*c]const u8,
    length: c_uint,
};

const hash_ops: [hash_count]HashOp = .{
    .{ .hash_type = "md5", .length = 16 },
    .{ .hash_type = "sha1", .length = 20 },
    .{ .hash_type = "sha256", .length = 32 },
    .{ .hash_type = "sha512", .length = 64 },
};

fn getErrno() c_int {
    return abi.__errno_location().*;
}

fn systemError(nError: c_int) u32 {
    return @as(u32, @intCast(abi.ERROR_TDNF_SYSTEM_BASE)) + @as(u32, @intCast(nError));
}

fn isNullOrEmptyString(pszValueOpt: ?[*:0]const u8) bool {
    return pszValueOpt == null or pszValueOpt.?[0] == 0;
}

fn setNullOut(comptime T: type, out: ?*T) void {
    if (out) |p| {
        p.* = null;
    }
}

fn freeCString(pszValue: ?[*:0]u8) void {
    if (pszValue) |psz| {
        TDNFFreeMemory(@ptrCast(psz));
    }
}

fn freeCStringArray(ppszValues: [*c]?[*:0]u8) void {
    if (ppszValues != null) {
        TDNFFreeStringArray(ppszValues);
    }
}

const CnfTreeDestroyOps = struct {
    ctx: ?*anyopaque = null,
    destroyFn: *const fn (ctx: ?*anyopaque, cn: [*c]abi.struct_cnfnode) void,
};

fn destroyCnfTree(_: ?*anyopaque, cn: [*c]abi.struct_cnfnode) void {
    abi.destroy_cnftree(cn);
}

const cnf_tree_destroy_ops = CnfTreeDestroyOps{
    .destroyFn = destroyCnfTree,
};

fn allocateCStringCapacity(nCapacity: usize, ppszDst: ?*?[*:0]u8) u32 {
    var raw: ?*anyopaque = null;

    if (ppszDst == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const dwError = TDNFAllocateMemory(nCapacity, 1, &raw);
    if (dwError != 0) {
        ppszDst.?.* = null;
        return dwError;
    }

    ppszDst.?.* = @ptrCast(raw.?);
    return 0;
}

const PathAllocOps = struct {
    ctx: ?*anyopaque = null,
    allocateFn: *const fn (
        ctx: ?*anyopaque,
        size: usize,
        out: *?*anyopaque,
    ) u32,
};

fn allocatePathMemory(
    _: ?*anyopaque,
    size: usize,
    out: *?*anyopaque,
) u32 {
    return TDNFAllocateMemory(1, size, out);
}

const path_alloc_ops = PathAllocOps{
    .allocateFn = allocatePathMemory,
};

fn copyCString(pszSrc: [*:0]const u8, ppszDst: ?*?[*:0]u8) u32 {
    return TDNFAllocateString(@ptrCast(pszSrc), ppszDst);
}

fn tdnfFreeUpdateInfoReferences(pRef: abi.PTDNF_UPDATEINFO_REF) void {
    if (pRef == null) {
        return;
    }

    freeCString(pRef[0].pszID);
    freeCString(pRef[0].pszLink);
    freeCString(pRef[0].pszTitle);
    freeCString(pRef[0].pszType);
}

fn rmFile(path: [*c]const u8, sbuf: [*c]const c.struct_stat, file_type: c_int, ftwb: [*c]c.struct_FTW) callconv(.c) c_int {
    _ = sbuf;
    _ = file_type;
    _ = ftwb;

    if (c.remove(path) < 0) {
        common.log(abi.LOG_CRIT, "unable to remove %s: %s\n", .{ path, c.strerror(getErrno()) });
    }
    return 0;
}

fn isAlphaNum(ch: u8) bool {
    return c.isalnum(@as(c_int, ch)) != 0;
}

fn isSpace(ch: u8) bool {
    return c.isspace(@as(c_int, ch)) != 0;
}

fn isSupportedHashType(hash_type: c_int) bool {
    return hash_type >= hash_md5 and hash_type < hash_sentinel;
}

fn getHashOp(hash_type: c_int) *const HashOp {
    return &hash_ops[@as(usize, @intCast(hash_type))];
}

fn rpmzigErrorOrUnknown() [*:0]const u8 {
    const pszError = tdnf_rpmzig_checksum_last_error();
    return if (pszError[0] == 0) "unknown error" else pszError;
}

fn tdnfIsFipsModeEnabled() c_int {
    var pszFipsMode: ?[*:0]u8 = null;
    defer freeCString(pszFipsMode);

    if (TDNFFileReadAllText("/proc/sys/crypto/fips_enabled", &pszFipsMode, null) != 0) {
        return 0;
    }

    const pszFipsValue = TDNFLeftTrim(@ptrCast(pszFipsMode));
    if (!isNullOrEmptyString(pszFipsValue) and pszFipsValue.?[0] == '1') {
        return 1;
    }

    return 0;
}

fn tdnfGetDigestForFileRpmzig(
    filenameOpt: ?[*:0]const u8,
    hash_type: c_int,
    digest: ?[*]u8,
) u32 {
    var fp: ?*c.FILE = null;
    var ctx: ?*DigestContext = null;
    var buf = [_]u8{0} ** c.BUFSIZ;

    if (isNullOrEmptyString(filenameOpt) or digest == null or !isSupportedHashType(hash_type)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const filename = filenameOpt.?;
    const hash = getHashOp(hash_type);

    fp = c.fopen(@ptrCast(filename), "r");
    if (fp == null) {
        common.log(abi.LOG_ERR, "ERROR: Checksum validating (%s) FAILED\n", .{filename});
        return systemError(getErrno());
    }
    defer _ = c.fclose(fp);

    ctx = tdnf_rpmzig_digest_open(hash_type);
    if (ctx == null) {
        common.log(abi.LOG_ERR, "rpmzig digest open failed for %s (%s): %s\n", .{ filename, hash.hash_type, rpmzigErrorOrUnknown() });
        return abi.ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
    }
    defer tdnf_rpmzig_digest_close(ctx);
    while (true) {
        const length = c.fread(@ptrCast(&buf[0]), 1, c.BUFSIZ - 1, fp);
        if (length > 0) {
            const chunk_len: usize = length;
            if (tdnf_rpmzig_digest_update(ctx, &buf[0], chunk_len) != 0) {
                common.log(abi.LOG_ERR, "rpmzig digest update failed for %s (%s): %s\n", .{ filename, hash.hash_type, rpmzigErrorOrUnknown() });
                return abi.ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
            }
            @memset(buf[0..], 0);
            continue;
        }

        if (c.ferror(fp) != 0) {
            common.log(abi.LOG_ERR, "Error: Checksum validating (%s) FAILED\n", .{filename});
            return systemError(getErrno());
        }

        break;
    }

    if (tdnf_rpmzig_digest_final(ctx, digest, hash.length) != 0) {
        common.log(abi.LOG_ERR, "rpmzig digest final failed for %s (%s): %s\n", .{ filename, hash.hash_type, rpmzigErrorOrUnknown() });
        return abi.ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
    }

    return 0;
}

fn tdnfGetDigestForFdRpmzig(
    fd: c_int,
    hash_type: c_int,
    digest: ?[*]u8,
) u32 {
    if (fd < 0 or digest == null or !isSupportedHashType(hash_type)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const hash = getHashOp(hash_type);
    const ctx = tdnf_rpmzig_digest_open(hash_type) orelse {
        common.log(abi.LOG_ERR, "rpmzig digest open failed for pinned metadata (%s): %s\n", .{ hash.hash_type, rpmzigErrorOrUnknown() });
        return abi.ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
    };
    defer tdnf_rpmzig_digest_close(ctx);

    var buffer: [c.BUFSIZ]u8 = undefined;
    var offset: c.off_t = 0;
    while (true) {
        const length = c.pread(fd, &buffer, buffer.len, offset);
        if (length < 0) {
            if (getErrno() == c.EINTR) continue;
            return systemError(getErrno());
        }
        if (length == 0) break;
        const chunk_len: usize = @intCast(length);
        if (tdnf_rpmzig_digest_update(ctx, &buffer, chunk_len) != 0) {
            common.log(abi.LOG_ERR, "rpmzig digest update failed for pinned metadata (%s): %s\n", .{ hash.hash_type, rpmzigErrorOrUnknown() });
            return abi.ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
        }
        offset += @intCast(chunk_len);
    }

    if (tdnf_rpmzig_digest_final(ctx, digest, hash.length) != 0) {
        common.log(abi.LOG_ERR, "rpmzig digest final failed for pinned metadata (%s): %s\n", .{ hash.hash_type, rpmzigErrorOrUnknown() });
        return abi.ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
    }
    return 0;
}

export fn TDNFFileReadAllText(
    pszFileNameOpt: ?[*:0]const u8,
    ppszText: ?*?[*:0]u8,
    pnLength: ?*c_int,
) u32 {
    var fp: ?*c.FILE = null;
    var pszText: ?[*:0]u8 = null;
    var nLength: c_long = 0;

    if (pszFileNameOpt == null or ppszText == null) {
        setNullOut(?[*:0]u8, ppszText);
        if (pnLength) |pLen| {
            pLen.* = 0;
        }
        return systemError(abi.EINVAL);
    }

    fp = c.fopen(@ptrCast(pszFileNameOpt.?), "r");
    if (fp == null) {
        setNullOut(?[*:0]u8, ppszText);
        if (pnLength) |pLen| {
            pLen.* = 0;
        }
        return systemError(abi.ENOENT);
    }
    defer _ = c.fclose(fp);

    _ = c.fseek(fp, 0, c.SEEK_END);
    nLength = c.ftell(fp);
    if (nLength < 0) {
        setNullOut(?[*:0]u8, ppszText);
        if (pnLength) |pLen| {
            pLen.* = 0;
        }
        return systemError(getErrno());
    }

    {
        var raw: ?*anyopaque = null;
        const dwError = TDNFAllocateMemory(1, @as(usize, @intCast(nLength)) + 1, &raw);
        if (dwError != 0) {
            setNullOut(?[*:0]u8, ppszText);
            if (pnLength) |pLen| {
                pLen.* = 0;
            }
            return dwError;
        }
        pszText = @ptrCast(raw.?);
    }

    if (c.fseek(fp, 0, c.SEEK_SET) != 0) {
        freeCString(pszText);
        setNullOut(?[*:0]u8, ppszText);
        if (pnLength) |pLen| {
            pLen.* = 0;
        }
        return systemError(getErrno());
    }

    const nBytesRead = c.fread(@ptrCast(pszText.?), 1, @as(usize, @intCast(nLength)), fp);
    if (nBytesRead != @as(usize, @intCast(nLength))) {
        freeCString(pszText);
        setNullOut(?[*:0]u8, ppszText);
        if (pnLength) |pLen| {
            pLen.* = 0;
        }
        return systemError(abi.EBADFD);
    }

    (@as([*]u8, @ptrCast(pszText.?)))[@intCast(nLength)] = 0;
    ppszText.?.* = pszText;
    if (pnLength) |pLen| {
        pLen.* = @intCast(nLength);
    }

    return 0;
}

export fn TDNFLeftTrim(pszStrOpt: ?[*:0]const u8) ?[*:0]const u8 {
    if (pszStrOpt == null) {
        return null;
    }

    var pszStr = pszStrOpt.?;
    while (pszStr[0] != 0 and isSpace(pszStr[0])) {
        pszStr += 1;
    }
    return pszStr;
}

export fn TDNFRightTrim(pszStartOpt: ?[*:0]const u8, pszEndOpt: ?[*:0]const u8) ?[*:0]const u8 {
    if (pszStartOpt == null or pszEndOpt == null) {
        return null;
    }

    const start_addr = @intFromPtr(pszStartOpt.?);
    var end_addr = @intFromPtr(pszEndOpt.?);

    while (end_addr > start_addr) {
        const pszCurrent: [*]const u8 = @ptrFromInt(end_addr);
        if (!isSpace(pszCurrent[0])) {
            break;
        }
        end_addr -= 1;
    }

    return @ptrFromInt(end_addr);
}

export fn TDNFCreateAndWriteToFile(pszFileOpt: ?[*:0]const u8, pszDataOpt: ?[*:0]const u8) u32 {
    var fp: ?*c.FILE = null;

    if (isNullOrEmptyString(pszFileOpt) or isNullOrEmptyString(pszDataOpt)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    fp = c.fopen(@ptrCast(pszFileOpt.?), "w");
    if (fp == null) {
        return systemError(getErrno());
    }
    defer _ = c.fclose(fp);

    _ = c.fputs(@ptrCast(pszDataOpt.?), fp);
    return 0;
}

export fn TDNFUtilsFormatSize(unSize: u64, ppszFormattedSize: ?*?[*:0]u8) u32 {
    var pszFormattedSize: ?[*:0]u8 = null;
    const pszSizes = "bkMG";
    var dSize: f64 = @floatFromInt(unSize);
    var nIndex: usize = 0;
    const dKiloBytes: f64 = 1024.0;
    const nMaxSize: usize = 512;

    if (ppszFormattedSize == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    while (nIndex < pszSizes.len and dSize > dKiloBytes) {
        dSize /= dKiloBytes;
        nIndex += 1;
    }

    {
        const dwError = allocateCStringCapacity(nMaxSize, &pszFormattedSize);
        if (dwError != 0) {
            ppszFormattedSize.?.* = null;
            return dwError;
        }
    }
    const nWritten = c.snprintf(@ptrCast(pszFormattedSize.?), nMaxSize, "%6.2f%c", dSize, pszSizes[nIndex]);
    if (nWritten < 0 or @as(usize, @intCast(nWritten)) >= nMaxSize) {
        freeCString(pszFormattedSize);
        ppszFormattedSize.?.* = null;
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    }

    ppszFormattedSize.?.* = pszFormattedSize;
    return 0;
}

export fn TDNFFreePackageInfo(pPkgInfoOpt: abi.PTDNF_PKG_INFO) void {
    var pPkgInfo = pPkgInfoOpt;
    while (pPkgInfo != null) {
        const pPkgInfoTemp = pPkgInfo;
        pPkgInfo = pPkgInfo[0].pNext;
        TDNFFreePackageInfoContents(pPkgInfoTemp);
        TDNFFreeMemory(pPkgInfoTemp);
    }
}

export fn TDNFFreePackageInfoArray(pPkgInfoArray: abi.PTDNF_PKG_INFO, unLength: u32) void {
    if (pPkgInfoArray == null) {
        return;
    }

    var remaining = unLength;
    while (remaining > 0) {
        remaining -= 1;
        TDNFFreePackageInfoContents(@ptrCast(pPkgInfoArray + remaining));
    }

    TDNFFreeMemory(pPkgInfoArray);
}

export fn TDNFFreeChangeLogEntry(pEntry: abi.PTDNF_PKG_CHANGELOG_ENTRY) void {
    if (pEntry == null) {
        return;
    }

    freeCString(pEntry[0].pszAuthor);
    freeCString(pEntry[0].pszText);
    TDNFFreeMemory(pEntry);
}

export fn TDNFFreePackageInfoContents(pPkgInfo: abi.PTDNF_PKG_INFO) void {
    if (pPkgInfo == null) {
        return;
    }

    freeCString(pPkgInfo[0].pszName);
    freeCString(pPkgInfo[0].pszRepoName);
    freeCString(pPkgInfo[0].pszVersion);
    freeCString(pPkgInfo[0].pszArch);
    freeCString(pPkgInfo[0].pszEVR);
    freeCString(pPkgInfo[0].pszSummary);
    freeCString(pPkgInfo[0].pszURL);
    freeCString(pPkgInfo[0].pszLicense);
    freeCString(pPkgInfo[0].pszDescription);
    freeCString(pPkgInfo[0].pszFormattedSize);
    freeCString(pPkgInfo[0].pszFormattedDownloadSize);
    freeCString(pPkgInfo[0].pszRelease);
    freeCString(pPkgInfo[0].pszLocation);
    if (pPkgInfo[0].pbChecksum != null) {
        TDNFFreeMemory(@ptrCast(pPkgInfo[0].pbChecksum));
        pPkgInfo[0].pbChecksum = null;
    }

    if (pPkgInfo[0].pppszDependencies != null) {
        var depKey: usize = 0;
        while (depKey < abi.REPOQUERY_DEP_KEY_COUNT) : (depKey += 1) {
            freeCStringArray(pPkgInfo[0].pppszDependencies[depKey]);
            pPkgInfo[0].pppszDependencies[depKey] = null;
        }
        TDNFFreeMemory(@ptrCast(pPkgInfo[0].pppszDependencies));
        pPkgInfo[0].pppszDependencies = null;
    }

    freeCStringArray(pPkgInfo[0].ppszFileList);
    pPkgInfo[0].ppszFileList = null;

    var pEntry = pPkgInfo[0].pChangeLogEntries;
    while (pEntry != null) {
        const pEntryNext = pEntry[0].pNext;
        TDNFFreeChangeLogEntry(pEntry);
        pEntry = pEntryNext;
    }
    pPkgInfo[0].pChangeLogEntries = null;
}

export fn TDNFFreeSolvedPackageInfo(pSolvedPkgInfo: abi.PTDNF_SOLVED_PKG_INFO) void {
    if (pSolvedPkgInfo == null) {
        return;
    }

    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsNotAvailable);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsExisting);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsToInstall);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsToUpgrade);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsToDowngrade);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsToRemove);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsUnNeeded);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsToReinstall);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsObsoleted);
    TDNFFreePackageInfo(pSolvedPkgInfo[0].pPkgsRemovedByDowngrade);

    freeCStringArray(pSolvedPkgInfo[0].ppszPkgsNotResolved);
    freeCStringArray(pSolvedPkgInfo[0].ppszPkgsUserInstall);

    TDNFFreeMemory(pSolvedPkgInfo);
}

export fn TDNFFreeUpdateInfoSummary(pSummary: abi.PTDNF_UPDATEINFO_SUMMARY) void {
    if (pSummary != null) {
        TDNFFreeMemory(pSummary);
    }
}

export fn TDNFFreeUpdateInfoPackages(pPkgsOpt: abi.PTDNF_UPDATEINFO_PKG) void {
    var pPkgs = pPkgsOpt;
    while (pPkgs != null) {
        freeCString(pPkgs[0].pszName);
        freeCString(pPkgs[0].pszFileName);
        freeCString(pPkgs[0].pszEVR);
        freeCString(pPkgs[0].pszArch);

        const pTemp = pPkgs;
        pPkgs = pPkgs[0].pNext;
        TDNFFreeMemory(pTemp);
    }
}

export fn TDNFFreeUpdateInfo(pUpdateInfo: abi.PTDNF_UPDATEINFO) void {
    if (pUpdateInfo == null) {
        return;
    }

    freeCString(pUpdateInfo[0].pszID);
    freeCString(pUpdateInfo[0].pszDate);
    freeCString(pUpdateInfo[0].pszDescription);

    tdnfFreeUpdateInfoReferences(pUpdateInfo[0].pReferences);
    TDNFFreeUpdateInfoPackages(pUpdateInfo[0].pPackages);
    TDNFFreeMemory(pUpdateInfo);
}

export fn TDNFFreeCmdOpt(pCmdOptOpt: abi.PTDNF_CMD_OPT) void {
    var pCmdOpt = pCmdOptOpt;
    while (pCmdOpt != null) {
        freeCString(pCmdOpt[0].pszOptName);
        freeCString(pCmdOpt[0].pszOptValue);
        const pCmdOptTemp = pCmdOpt[0].pNext;
        TDNFFreeMemory(pCmdOpt);
        pCmdOpt = pCmdOptTemp;
    }
}

fn freeCmdArgsWithOps(pCmdArgs: abi.PTDNF_CMD_ARGS, destroy_ops: CnfTreeDestroyOps) void {
    if (pCmdArgs == null) {
        return;
    }

    freeCString(pCmdArgs[0].pszArch);
    if (pCmdArgs[0].ppszCmds != null) {
        var nIndex: usize = 0;
        while (nIndex < @as(usize, @intCast(pCmdArgs[0].nCmdCount))) : (nIndex += 1) {
            freeCString(pCmdArgs[0].ppszCmds[nIndex]);
        }
        TDNFFreeMemory(@ptrCast(pCmdArgs[0].ppszCmds));
        pCmdArgs[0].ppszCmds = null;
    }
    freeCString(pCmdArgs[0].pszDownloadDir);
    freeCString(pCmdArgs[0].pszInstallRoot);
    freeCString(pCmdArgs[0].pszConfFile);
    freeCString(pCmdArgs[0].pszReleaseVer);

    destroy_ops.destroyFn(destroy_ops.ctx, pCmdArgs[0].cn_setopts);
    destroy_ops.destroyFn(destroy_ops.ctx, pCmdArgs[0].cn_repoopts);
    TDNFFreeMemory(pCmdArgs);
}

export fn TDNFFreeCmdArgs(pCmdArgs: abi.PTDNF_CMD_ARGS) void {
    freeCmdArgsWithOps(pCmdArgs, cnf_tree_destroy_ops);
}

export fn TDNFFreeRepos(pReposOpt: abi.PTDNF_REPO_DATA) void {
    var pRepos = pReposOpt;
    while (pRepos != null) {
        const pRepo = pRepos;
        freeCString(pRepo[0].pszId);
        freeCString(pRepo[0].pszName);
        freeCStringArray(pRepo[0].ppszBaseUrls);
        freeCString(pRepo[0].pszMetaLink);
        freeCString(pRepo[0].pszMirrorList);
        freeCString(pRepo[0].pszSnapshotUrl);
        freeCString(pRepo[0].pszSnapshotFile);
        freeCStringArray(pRepo[0].ppszUrlGPGKeys);

        pRepos = pRepo[0].pNext;
        TDNFFreeMemory(pRepo);
    }
}

export fn TDNFYesOrNo(pArgs: abi.PTDNF_CMD_ARGS, pszQuestionOpt: ?[*:0]const u8, pAnswer: ?*c_int) u32 {
    var opt: i32 = 0;

    if (pArgs == null or pszQuestionOpt == null or pAnswer == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    pAnswer.?.* = 0;

    if (pArgs[0].nAssumeYes == 0 and pArgs[0].nAssumeNo == 0) {
        while (true) {
            var buf = [_]u8{0} ** 256;
            common.log(abi.LOG_CRIT, "%s", .{pszQuestionOpt.?});

            const ret = fgets(@ptrCast(&buf[0]), @intCast(buf.len - 1), c.stdin);
            if (ret != &buf[0] or buf[0] == 0) {
                return abi.ERROR_TDNF_INVALID_INPUT;
            }

            const len = c.strlen(@ptrCast(&buf[0]));
            buf[len - 1] = 0;
            if (c.strcasecmp(@ptrCast(&buf[0]), "yes") == 0 or
                c.strcasecmp(@ptrCast(&buf[0]), "y") == 0 or
                c.strcasecmp(@ptrCast(&buf[0]), "n") == 0 or
                c.strcasecmp(@ptrCast(&buf[0]), "no") == 0 or
                buf[0] == 0)
            {
                opt = c.tolower(@as(c_int, buf[0]));
                break;
            }
        }
    }

    if (pArgs[0].nAssumeYes != 0 or opt == 'y') {
        pAnswer.?.* = 1;
    }

    return 0;
}

export fn TDNFUriIsRemote(pszKeyUrlOpt: ?[*:0]const u8, pnRemote: ?*c_int) u32 {
    const remotes = [_]?[*:0]const u8{ "http://", "https://", null };
    var i: usize = 0;

    if (pnRemote == null or isNullOrEmptyString(pszKeyUrlOpt)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    pnRemote.?.* = 0;
    while (remotes[i] != null) : (i += 1) {
        const remote = remotes[i].?;
        if (c.strncasecmp(@ptrCast(pszKeyUrlOpt.?), @ptrCast(remote), c.strlen(@ptrCast(remote))) == 0) {
            pnRemote.?.* = 1;
            break;
        }
    }

    if (remotes[i] == null and c.strncasecmp(@ptrCast(pszKeyUrlOpt.?), "file://", 7) != 0) {
        return abi.ERROR_TDNF_URL_INVALID;
    }

    return 0;
}

export fn TDNFPathFromUri(pszKeyUrlOpt: ?[*:0]const u8, ppszPath: ?*?[*:0]u8) u32 {
    const protocols = [_]?[*:0]const u8{ "http://", "https://", "file://", null };
    var pszPathTmp: ?[*:0]u8 = null;
    var i: usize = 0;
    var nOffset: usize = 0;

    if (isNullOrEmptyString(pszKeyUrlOpt) or ppszPath == null) {
        setNullOut(?[*:0]u8, ppszPath);
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    while (protocols[i] != null) : (i += 1) {
        const protocol = protocols[i].?;
        if (c.strncasecmp(@ptrCast(pszKeyUrlOpt.?), @ptrCast(protocol), c.strlen(@ptrCast(protocol))) == 0) {
            nOffset = std.mem.span(protocol).len;
            break;
        }
    }
    if (protocols[i] == null) {
        setNullOut(?[*:0]u8, ppszPath);
        return abi.ERROR_TDNF_URL_INVALID;
    }

    var pszPath = pszKeyUrlOpt.? + nOffset;
    if (pszPath[0] == 0) {
        setNullOut(?[*:0]u8, ppszPath);
        return abi.ERROR_TDNF_URL_INVALID;
    }

    if (c.strchr(@ptrCast(pszPath), '#') != null) {
        setNullOut(?[*:0]u8, ppszPath);
        return abi.ERROR_TDNF_URL_INVALID;
    }

    if (pszPath[0] != '/') {
        const slash = c.strchr(@ptrCast(pszPath), '/');
        if (slash == null) {
            setNullOut(?[*:0]u8, ppszPath);
            return abi.ERROR_TDNF_URL_INVALID;
        }
        pszPath = @ptrCast(slash);
    }

    const dwError = copyCString(pszPath, &pszPathTmp);
    if (dwError != 0) {
        setNullOut(?[*:0]u8, ppszPath);
        return dwError;
    }

    ppszPath.?.* = pszPathTmp;
    return 0;
}

/// Release everything `TDNFNormalizePath` owns and report `dwError`.
///
/// `TDNFNormalizePath` returns a `u32` status rather than a Zig error union,
/// so `errdefer` there would compile but never run. Every failing path calls
/// this instead.
fn normalizePathFail(
    pszNormalPath: ?[*:0]u8,
    pszRealPath: [*c]u8,
    ppszNormalPath: ?*?[*:0]u8,
    dwError: u32,
) u32 {
    freeCString(pszNormalPath);
    if (pszRealPath != null) {
        TDNFFreeMemory(pszRealPath);
    }
    setNullOut(?[*:0]u8, ppszNormalPath);
    return dwError;
}

export fn TDNFNormalizePath(pszPathOpt: ?[*:0]const u8, ppszNormalPath: ?*?[*:0]u8) u32 {
    var pszNormalPath: ?[*:0]u8 = null;
    var pszRealPath: [*c]u8 = null;

    if (isNullOrEmptyString(pszPathOpt) or ppszNormalPath == null) {
        setNullOut(?[*:0]u8, ppszNormalPath);
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const pszPath = pszPathOpt.?;
    if (pszPath[0] != '/') {
        setNullOut(?[*:0]u8, ppszNormalPath);
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    {
        const dwError = allocateCStringCapacity(std.mem.span(pszPath).len + 1, &pszNormalPath);
        if (dwError != 0) {
            setNullOut(?[*:0]u8, ppszNormalPath);
            return dwError;
        }
    }

    var p: usize = 0;
    var q: usize = 0;
    const path_len = std.mem.span(pszPath).len;

    while (pszPath[p] != 0) {
        if (pszPath[p] == '/' and pszPath[p + 1] == '/') {
            p += 1;
            continue;
        }
        if (pszPath[p] == '/' and pszPath[p + 1] == '.' and (pszPath[p + 2] == '/' or pszPath[p + 2] == 0)) {
            p += 2;
            continue;
        }
        if (pszPath[p] == '/' and pszPath[p + 1] == '.' and pszPath[p + 2] == '.' and (pszPath[p + 3] == '/' or pszPath[p + 3] == 0)) {
            if (q == 0) {
                return normalizePathFail(
                    pszNormalPath,
                    pszRealPath,
                    ppszNormalPath,
                    abi.ERROR_TDNF_INVALID_PARAMETER,
                );
            }
            p += 3;
            const bytes: [*]u8 = @ptrCast(pszNormalPath.?);
            while (q > 0 and bytes[q] != '/') {
                q -= 1;
            }
            continue;
        }
        if (pszPath[p] == '/') {
            const bytes: [*]u8 = @ptrCast(pszNormalPath.?);
            bytes[q] = 0;
            pszRealPath = realpath(@ptrCast(pszNormalPath.?), null);
            if (pszRealPath != null) {
                if (c.strcmp(pszRealPath, @ptrCast(pszNormalPath.?)) != 0) {
                    const rlen = std.mem.span(@as([*:0]const u8, @ptrCast(pszRealPath))).len;
                    freeCString(pszNormalPath);

                    const dwError = allocateCStringCapacity(rlen + (path_len - p) + 1, &pszNormalPath);
                    if (dwError != 0) {
                        return normalizePathFail(
                            pszNormalPath,
                            pszRealPath,
                            ppszNormalPath,
                            dwError,
                        );
                    }

                    const newBytes: [*]u8 = @ptrCast(pszNormalPath.?);
                    const realPathSlice = std.mem.span(@as([*:0]const u8, @ptrCast(pszRealPath)));
                    @memcpy(newBytes[0..rlen], realPathSlice);
                    newBytes[rlen] = 0;
                    q = rlen;
                }
                TDNFFreeMemory(pszRealPath);
                pszRealPath = null;
            } else if (getErrno() != abi.ENOENT) {
                return normalizePathFail(
                    pszNormalPath,
                    pszRealPath,
                    ppszNormalPath,
                    systemError(getErrno()),
                );
            }
            if (pszPath[p + 1] == 0) {
                p += 1;
                continue;
            }
        }
        (@as([*]u8, @ptrCast(pszNormalPath.?)))[q] = pszPath[p];
        q += 1;
        p += 1;
    }
    (@as([*]u8, @ptrCast(pszNormalPath.?)))[q] = 0;

    if (pszNormalPath.?[0] == 0) {
        freeCString(pszNormalPath);
        pszNormalPath = if (c.strdup("/")) |pszDup| @ptrCast(pszDup) else null;
    }

    pszRealPath = realpath(@ptrCast(pszNormalPath.?), null);
    if (pszRealPath != null) {
        freeCString(pszNormalPath);
        pszNormalPath = @ptrCast(pszRealPath);
        pszRealPath = null;
    } else if (getErrno() != abi.ENOENT) {
        return normalizePathFail(
            pszNormalPath,
            pszRealPath,
            ppszNormalPath,
            systemError(getErrno()),
        );
    }

    ppszNormalPath.?.* = pszNormalPath;
    return 0;
}

export fn TDNFRecursivelyRemoveDir(pszPathOpt: ?[*:0]const u8) u32 {
    if (isNullOrEmptyString(pszPathOpt)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    if (c.nftw(@ptrCast(pszPathOpt.?), rmFile, 10, c.FTW_DEPTH | c.FTW_PHYS) < 0) {
        return systemError(getErrno());
    }

    return 0;
}

export fn TDNFStringMatchesOneOf(pszSearchOpt: ?[*:0]const u8, ppszList: [*c]?[*:0]u8, pRet: ?*c_int) u32 {
    var i: usize = 0;

    if (isNullOrEmptyString(pszSearchOpt) or ppszList == null or pRet == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    pRet.?.* = 0;
    while (ppszList[i] != null) : (i += 1) {
        if (c.strcmp(@ptrCast(pszSearchOpt.?), @ptrCast(ppszList[i].?)) == 0) {
            pRet.?.* = 1;
            break;
        }
    }

    return 0;
}

fn joinPathFromArrayWithOps(
    ops: PathAllocOps,
    ppszPath: ?*?[*:0]u8,
    ppszNodes: [*c]?[*:0]u8,
    nCount: c_int,
) u32 {
    var pszResult: ?[*:0]u8 = null;
    var total_len: usize = 1;
    var i: usize = 0;

    if (ppszPath == null or nCount < 0 or
        (nCount > 0 and ppszNodes == null))
    {
        setNullOut(?[*:0]u8, ppszPath);
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    if (nCount == 0) {
        ppszPath.?.* = null;
        return 0;
    }

    const count: usize = @intCast(nCount);
    while (i < count) : (i += 1) {
        const pszNode = ppszNodes[i] orelse continue;
        const node = std.mem.span(pszNode);
        var start: usize = 0;
        var end: usize = node.len;
        while (start < end and node[start] == '/') {
            start += 1;
        }
        while (end > start and node[end - 1] == '/') {
            end -= 1;
        }
        total_len += (end - start);
        if (i == 0 and node.len > 0 and node[0] == '/') {
            total_len += 1;
        }
        if (i != count - 1) {
            total_len += 1;
        }
    }

    var raw: ?*anyopaque = null;
    const dwError = ops.allocateFn(ops.ctx, total_len, &raw);
    if (dwError != 0) {
        setNullOut(?[*:0]u8, ppszPath);
        return dwError;
    }
    pszResult = @ptrCast(raw.?);

    const bytes: [*]u8 = @ptrCast(pszResult.?);
    var write_index: usize = 0;
    i = 0;
    while (i < count) : (i += 1) {
        const pszNode = ppszNodes[i] orelse continue;
        const node = std.mem.span(pszNode);
        var start: usize = 0;
        var end: usize = node.len;
        while (start < end and node[start] == '/') {
            start += 1;
        }
        while (end > start and node[end - 1] == '/') {
            end -= 1;
        }

        if (i == 0 and node.len > 0 and node[0] == '/') {
            bytes[write_index] = '/';
            write_index += 1;
        }

        if (end > start) {
            @memcpy(bytes[write_index .. write_index + (end - start)], node[start..end]);
            write_index += end - start;
        }
        if (i != count - 1) {
            bytes[write_index] = '/';
            write_index += 1;
        }
    }
    bytes[write_index] = 0;

    ppszPath.?.* = pszResult;
    return 0;
}

export fn TDNFJoinPathFromArray(
    ppszPath: ?*?[*:0]u8,
    ppszNodes: [*c]?[*:0]u8,
    nCount: c_int,
) u32 {
    return joinPathFromArrayWithOps(
        path_alloc_ops,
        ppszPath,
        ppszNodes,
        nCount,
    );
}

export fn TDNFJoinPath(ppszPath: ?*?[*:0]u8, ...) callconv(.c) u32 {
    if (ppszPath == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    var args: variadic.VaList = undefined;
    if (comptime variadic.needs_manual_start) {
        variadic.startManual(&args);
    } else {
        args = @cVaStart();
    }
    defer variadic.end(&args);

    var count_args: variadic.VaList = undefined;
    variadic.copy(&count_args, &args);
    defer variadic.end(&count_args);
    var count: usize = 0;
    while (variadic.nextPointer(&count_args) != null) {
        count += 1;
    }
    if (count > std.math.maxInt(c_int)) {
        ppszPath.?.* = null;
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    var raw: ?*anyopaque = null;
    var result = TDNFAllocateMemory(
        count + 1,
        @sizeOf(?[*:0]u8),
        &raw,
    );
    if (result != 0) {
        ppszPath.?.* = null;
        return result;
    }
    defer TDNFFreeMemory(raw);

    const nodes: [*c]?[*:0]u8 = @ptrCast(@alignCast(raw.?));
    var write_args: variadic.VaList = undefined;
    variadic.copy(&write_args, &args);
    defer variadic.end(&write_args);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        nodes[i] = @ptrCast(variadic.nextPointer(&write_args).?);
    }

    result = TDNFJoinPathFromArray(
        ppszPath,
        nodes,
        @intCast(count),
    );
    if (result != 0) {
        ppszPath.?.* = null;
    }
    return result;
}

export fn TDNFReadFileToStringArray(pszFileOpt: ?[*:0]const u8, pppszArray: ?*[*c]?[*:0]u8) u32 {
    var pszText: ?[*:0]u8 = null;
    var ppszArray: [*c]?[*:0]u8 = null;
    var nLength: c_int = 0;

    if (pszFileOpt == null or pppszArray == null) {
        setNullOut([*c]?[*:0]u8, pppszArray);
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    var dwError = TDNFFileReadAllText(pszFileOpt, &pszText, &nLength);
    if (dwError != 0) {
        setNullOut([*c]?[*:0]u8, pppszArray);
        return dwError;
    }
    defer freeCString(pszText);

    dwError = TDNFSplitStringToArray(@ptrCast(pszText.?), "\n", &ppszArray);
    if (dwError != 0) {
        if (ppszArray != null) {
            TDNFFreeStringArray(ppszArray);
        }
        setNullOut([*c]?[*:0]u8, pppszArray);
        return dwError;
    }

    pppszArray.?.* = ppszArray;
    return 0;
}

export fn TDNFIsDir(pszPathOpt: ?[*:0]const u8, pnPathIsDir: ?*c_int) u32 {
    var stStat: c.struct_stat = std.mem.zeroes(c.struct_stat);

    if (pnPathIsDir == null or isNullOrEmptyString(pszPathOpt)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    if (c.stat(@ptrCast(pszPathOpt.?), &stStat) != 0) {
        pnPathIsDir.?.* = 0;
        return systemError(getErrno());
    }

    pnPathIsDir.?.* = if (c.S_ISDIR(stStat.st_mode)) 1 else 0;
    return 0;
}

export fn TDNFDirName(pszPathOpt: ?[*:0]const u8, ppszDirName: ?*?[*:0]u8) u32 {
    var pszDirName: ?[*:0]u8 = null;
    var pszPathCopy: ?[*:0]u8 = null;

    if (isNullOrEmptyString(pszPathOpt) or ppszDirName == null) {
        setNullOut(?[*:0]u8, ppszDirName);
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    var dwError = copyCString(pszPathOpt.?, &pszPathCopy);
    if (dwError != 0) {
        setNullOut(?[*:0]u8, ppszDirName);
        return dwError;
    }
    defer freeCString(pszPathCopy);

    dwError = TDNFAllocateString(c.dirname(@ptrCast(pszPathCopy.?)), &pszDirName);
    if (dwError != 0) {
        setNullOut(?[*:0]u8, ppszDirName);
        return dwError;
    }

    ppszDirName.?.* = pszDirName;
    return 0;
}

export fn strtoi(ptrOpt: ?[*:0]const u8) i32 {
    if (ptrOpt == null) {
        return 0;
    }

    var p: [*c]u8 = null;
    const tmp = c.strtol(@ptrCast(ptrOpt.?), &p, 10);
    if (p[0] != 0 or tmp > c.INT_MAX or tmp < c.INT_MIN) {
        common.log(abi.LOG_CRIT, "WARNING: invalid arg to %s: '%s'\n", .{ "strtoi", ptrOpt.? });
        return 0;
    }

    return @intCast(tmp);
}

export fn isTrue(strOpt: ?[*:0]const u8) c_int {
    if (strOpt == null) {
        return 0;
    }

    if (c.strcasecmp(@ptrCast(strOpt.?), "false") == 0) {
        return 0;
    }

    if (c.strcasecmp(@ptrCast(strOpt.?), "true") == 0 or strtoi(strOpt) != 0) {
        return 1;
    }

    return 0;
}

export fn TDNFStrIsValidRepoName(strOpt: ?[*:0]const u8) c_int {
    if (strOpt == null or strOpt.?[0] == 0 or !(isAlphaNum(strOpt.?[0]) or strOpt.?[0] == '@')) {
        return 0;
    }

    var str = strOpt.? + 1;
    while (str[0] != 0 and (isAlphaNum(str[0]) or str[0] == '-' or str[0] == '_' or str[0] == '.')) {
        str += 1;
    }

    return if (str[0] == 0) 1 else 0;
}

export fn TDNFGetDigestForFile(
    filenameOpt: ?[*:0]const u8,
    hash_type: c_int,
    digest: ?[*]u8,
) u32 {
    if (isNullOrEmptyString(filenameOpt) or digest == null or !isSupportedHashType(hash_type)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    if (hash_type == hash_md5 and tdnfIsFipsModeEnabled() != 0) {
        common.log(abi.LOG_ERR, "Digest Init Failed\n", .{});
        return abi.ERROR_TDNF_FIPS_MODE_FORBIDDEN;
    }

    return tdnfGetDigestForFileRpmzig(filenameOpt, hash_type, digest);
}

export fn TDNFCheckHash(
    filenameOpt: ?[*:0]const u8,
    digest: ?[*]const u8,
    hash_type: c_int,
) u32 {
    var digest_from_file = [_]u8{0} ** max_digest_len;

    if (isNullOrEmptyString(filenameOpt) or digest == null or !isSupportedHashType(hash_type)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const filename = filenameOpt.?;
    const hash = getHashOp(hash_type);
    const hash_len: usize = @intCast(hash.length);

    const dwError = TDNFGetDigestForFile(filename, hash_type, digest_from_file[0..].ptr);
    if (dwError != 0) {
        return dwError;
    }

    if (!std.mem.eql(u8, digest_from_file[0..hash_len], digest.?[0..hash_len])) {
        common.log(abi.LOG_ERR, "Error: Validating Checksum (%s) FAILED (digest mismatch)\n", .{filename});
        return abi.ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
    }

    return 0;
}

export fn TDNFCheckHashFd(
    fd: c_int,
    digest: ?[*]const u8,
    hash_type: c_int,
) u32 {
    var digest_from_file = [_]u8{0} ** max_digest_len;
    if (fd < 0 or digest == null or !isSupportedHashType(hash_type)) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (hash_type == hash_md5 and tdnfIsFipsModeEnabled() != 0) {
        common.log(abi.LOG_ERR, "Digest Init Failed\n", .{});
        return abi.ERROR_TDNF_FIPS_MODE_FORBIDDEN;
    }

    const hash_len: usize = @intCast(getHashOp(hash_type).length);
    const result = tdnfGetDigestForFdRpmzig(
        fd,
        hash_type,
        digest_from_file[0..].ptr,
    );
    if (result != 0) return result;
    if (!std.mem.eql(
        u8,
        digest_from_file[0..hash_len],
        digest.?[0..hash_len],
    )) {
        common.log(abi.LOG_ERR, "Error: Validating pinned checksum FAILED (digest mismatch)\n", .{});
        return abi.ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
    }
    return 0;
}

export fn TDNFCheckHexDigest(
    hex_digestOpt: ?[*:0]const u8,
    digest_length: c_int,
) u32 {
    if (isNullOrEmptyString(hex_digestOpt) or digest_length <= 0) {
        return 0;
    }

    const hex_digest = std.mem.span(hex_digestOpt.?);
    for (hex_digest) |digit| {
        if (c.isxdigit(@as(c_int, digit)) == 0) {
            return 0;
        }
    }

    return if (hex_digest.len == @as(usize, @intCast(digest_length * 2))) 1 else 0;
}

export fn TDNFHexToUint(
    hex_digestOpt: ?[*:0]const u8,
    uintValue: ?*u8,
) u32 {
    var buf = [_:0]u8{ 0, 0, 0 };

    if (isNullOrEmptyString(hex_digestOpt) or uintValue == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const hex_digest = hex_digestOpt.?;
    buf[0] = hex_digest[0];
    buf[1] = hex_digest[1];

    abi.__errno_location().* = 0;
    const value = c.strtoul(@ptrCast(&buf), null, 16);
    if (getErrno() != 0) {
        common.log(abi.LOG_ERR, "Error: strtoul call failed\n", .{});
        return systemError(getErrno());
    }

    uintValue.?.* = @intCast(value & 0xff);
    return 0;
}

export fn TDNFChecksumFromHexDigest(
    hex_digestOpt: ?[*:0]const u8,
    ppdigest: ?[*]u8,
) u32 {
    var raw: ?*anyopaque = null;
    var uintValue: u8 = 0;

    if (isNullOrEmptyString(hex_digestOpt) or ppdigest == null) {
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    const hex_digest = std.mem.span(hex_digestOpt.?);
    const digest_len = hex_digest.len / 2;
    const dwError = TDNFAllocateMemory(1, digest_len, &raw);
    if (dwError != 0) {
        return dwError;
    }
    defer TDNFFreeMemory(raw);

    const pdigest: [*]u8 = @ptrCast(raw.?);
    var i: usize = 0;
    while (i < hex_digest.len) : (i += 2) {
        const convertError = TDNFHexToUint(hex_digestOpt.? + i, &uintValue);
        if (convertError != 0) {
            return convertError;
        }
        pdigest[i >> 1] = uintValue;
    }

    @memcpy(ppdigest.?[0..digest_len], pdigest[0..digest_len]);
    return 0;
}

fn expectedDigestBytes(comptime expected_hex: []const u8) [max_digest_len]u8 {
    var expected = [_]u8{0} ** max_digest_len;
    _ = std.fmt.hexToBytes(expected[0 .. expected_hex.len / 2], expected_hex) catch unreachable;
    return expected;
}

fn alwaysFailPathAllocate(
    _: ?*anyopaque,
    _: usize,
    _: *?*anyopaque,
) u32 {
    return abi.ERROR_TDNF_OUT_OF_MEMORY;
}

test "path joining preserves compatibility ABI and clears outputs on errors" {
    var first = [_:0]u8{ '/', 'v', 'a', 'r', '/', 0 };
    var second = [_:0]u8{ '/', 'l', 'i', 'b', '/', 0 };
    var output: ?[*:0]u8 = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFJoinPath(
            &output,
            @as(?[*:0]u8, &first),
            @as(?[*:0]u8, &second),
            @as(?[*:0]u8, null),
        ),
    );
    defer TDNFFreeMemory(@ptrCast(output.?));
    try std.testing.expectEqualStrings("/var/lib", std.mem.span(output.?));

    var third = [_:0]u8{ 'a', 0 };
    var fourth = [_:0]u8{ 'b', 0 };
    var fifth = [_:0]u8{ 'c', 0 };
    var sixth = [_:0]u8{ 'd', 0 };
    var seventh = [_:0]u8{ 'e', 0 };
    var eighth = [_:0]u8{ 'f', 0 };
    var ninth = [_:0]u8{ 'g', 0 };
    var overflow_output: ?[*:0]u8 = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFJoinPath(
            &overflow_output,
            @as(?[*:0]u8, &first),
            @as(?[*:0]u8, &second),
            @as(?[*:0]u8, &third),
            @as(?[*:0]u8, &fourth),
            @as(?[*:0]u8, &fifth),
            @as(?[*:0]u8, &sixth),
            @as(?[*:0]u8, &seventh),
            @as(?[*:0]u8, &eighth),
            @as(?[*:0]u8, &ninth),
            @as(?[*:0]u8, null),
        ),
    );
    defer TDNFFreeMemory(@ptrCast(overflow_output.?));
    try std.testing.expectEqualStrings(
        "/var/lib/a/b/c/d/e/f/g",
        std.mem.span(overflow_output.?),
    );

    const fail_ops = PathAllocOps{
        .allocateFn = alwaysFailPathAllocate,
    };
    var nodes = [_]?[*:0]u8{ &first, &second };
    var stale: ?[*:0]u8 = @ptrFromInt(1);
    try std.testing.expectEqual(
        @as(u32, abi.ERROR_TDNF_OUT_OF_MEMORY),
        joinPathFromArrayWithOps(
            fail_ops,
            &stale,
            &nodes,
            @intCast(nodes.len),
        ),
    );
    try std.testing.expect(stale == null);

    stale = @ptrFromInt(1);
    try std.testing.expectEqual(
        @as(u32, abi.ERROR_TDNF_INVALID_PARAMETER),
        TDNFJoinPathFromArray(&stale, null, 1),
    );
    try std.testing.expect(stale == null);
}

fn expectFileDigest(filename: [*:0]const u8, hash_type: c_int, comptime expected_hex: []const u8) !void {
    var actual = [_]u8{0} ** max_digest_len;
    const expected = expectedDigestBytes(expected_hex);
    const hash_len: usize = @intCast(getHashOp(hash_type).length);

    try std.testing.expectEqual(@as(u32, 0), TDNFGetDigestForFile(filename, hash_type, actual[0..].ptr));
    try std.testing.expectEqualSlices(u8, expected[0..hash_len], actual[0..hash_len]);
    try std.testing.expectEqual(@as(u32, 0), TDNFCheckHash(filename, expected[0..hash_len].ptr, hash_type));
}

test "checksum helpers validate hex digests and byte conversion" {
    try std.testing.expectEqual(@as(u32, 1), TDNFCheckHexDigest("0011aaff", 4));
    try std.testing.expectEqual(@as(u32, 0), TDNFCheckHexDigest("0011aafg", 4));
    try std.testing.expectEqual(@as(u32, 0), TDNFCheckHexDigest("0011aaff", 3));

    var byte: u8 = 0;
    try std.testing.expectEqual(@as(u32, 0), TDNFHexToUint("0f", &byte));
    try std.testing.expectEqual(@as(u8, 0x0f), byte);

    var digest = [_]u8{0} ** max_digest_len;
    try std.testing.expectEqual(@as(u32, 0), TDNFChecksumFromHexDigest("0011aaff", digest[0..].ptr));
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x11, 0xaa, 0xff }, digest[0..4]);
}

test "TDNFGetDigestForFile and TDNFCheckHash use the checksum ABI" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var rel_path_buf: [128]u8 = undefined;
    const rel_path = try std.fmt.bufPrint(&rel_path_buf, ".zig-cache/tmp/{s}/input.txt", .{tmp_dir.sub_path});

    var filename_buf: [129:0]u8 = [_:0]u8{0} ** 129;
    @memcpy(filename_buf[0..rel_path.len], rel_path);
    const filename: [*:0]const u8 = @ptrCast(&filename_buf);

    const fp = c.fopen(filename, "w");
    try std.testing.expect(fp != null);
    defer _ = c.fclose(fp);
    try std.testing.expectEqual(@as(usize, 3), c.fwrite("abc", 1, 3, fp));
    try std.testing.expectEqual(@as(c_int, 0), c.fflush(fp));

    try expectFileDigest(filename, hash_sha1, "a9993e364706816aba3e25717850c26c9cd0d89d");
    try expectFileDigest(filename, hash_sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    try expectFileDigest(
        filename,
        hash_sha512,
        "ddaf35a193617abacc417349ae204131" ++
            "12e6fa4e89a97ea20a9eeee64b55d39a" ++
            "2192992a274fc1a836ba3c23a3feebbd" ++
            "454d4423643ce80e2a9ac94fa54ca49f",
    );

    if (tdnfIsFipsModeEnabled() != 0) {
        var digest = [_]u8{0} ** max_digest_len;
        try std.testing.expectEqual(
            @as(u32, abi.ERROR_TDNF_FIPS_MODE_FORBIDDEN),
            TDNFGetDigestForFile(filename, hash_md5, digest[0..].ptr),
        );
    } else {
        try expectFileDigest(filename, hash_md5, "900150983cd24fb0d6963f7d28e17f72");
    }
}

const TrackingCnfTreeDestroyContext = struct {
    nodes: [2][*c]abi.struct_cnfnode = .{ null, null },
    count: usize = 0,
};

fn trackCnfTreeDestroy(ctx: ?*anyopaque, cn: [*c]abi.struct_cnfnode) void {
    const tracking: *TrackingCnfTreeDestroyContext = @ptrCast(@alignCast(ctx.?));
    if (tracking.count < tracking.nodes.len) {
        tracking.nodes[tracking.count] = cn;
    }
    tracking.count += 1;
}

test "TDNFFreeCmdArgs tolerates a command count with no command vector" {
    // `TDNFCliParseArgs` publishes `nCmdCount` only after `ppszCmds` exists,
    // but this is exported public API: a C caller can hand us the half-filled
    // struct an out-of-memory unwind leaves behind. Walking the vector before
    // testing it for null would fault.
    const pAllocated = c.calloc(1, @sizeOf(abi.TDNF_CMD_ARGS)) orelse
        return error.OutOfMemory;
    const pCmdArgs: abi.PTDNF_CMD_ARGS = @ptrCast(@alignCast(pAllocated));
    pCmdArgs[0].nCmdCount = 3;
    pCmdArgs[0].ppszCmds = null;
    TDNFFreeCmdArgs(pCmdArgs);
}

test "TDNFFreeCmdArgs destroys real llconf option trees" {
    const setopts = abi.create_cnfnode("setopts");
    if (setopts == null) return error.OutOfMemory;
    errdefer abi.destroy_cnftree(setopts);

    const setopt = abi.create_cnfnode_keyval("install_weak_deps=false");
    if (setopt == null) return error.OutOfMemory;
    abi.append_node(setopts, setopt);

    const repoopts = abi.create_cnfnode("repoopts");
    if (repoopts == null) return error.OutOfMemory;
    errdefer abi.destroy_cnftree(repoopts);

    const repo = abi.create_cnfnode("base");
    if (repo == null) return error.OutOfMemory;
    abi.append_node(repoopts, repo);
    const repoopt = abi.create_cnfnode_keyval("skip_if_unavailable=true");
    if (repoopt == null) return error.OutOfMemory;
    abi.append_node(repo, repoopt);

    const pAllocated = c.calloc(1, @sizeOf(abi.TDNF_CMD_ARGS)) orelse
        return error.OutOfMemory;
    const pCmdArgs: abi.PTDNF_CMD_ARGS = @ptrCast(@alignCast(pAllocated));
    pCmdArgs[0].cn_setopts = setopts;
    pCmdArgs[0].cn_repoopts = repoopts;

    TDNFFreeCmdArgs(pCmdArgs);
}

test "freeCmdArgsWithOps routes both option trees to the destroy operation" {
    const pAllocated = c.calloc(1, @sizeOf(abi.TDNF_CMD_ARGS)) orelse
        return error.OutOfMemory;
    const pCmdArgs: abi.PTDNF_CMD_ARGS = @ptrCast(@alignCast(pAllocated));
    var setopts = std.mem.zeroes(abi.struct_cnfnode);
    var repoopts = std.mem.zeroes(abi.struct_cnfnode);
    pCmdArgs[0].cn_setopts = &setopts;
    pCmdArgs[0].cn_repoopts = &repoopts;

    var tracking = TrackingCnfTreeDestroyContext{};
    freeCmdArgsWithOps(pCmdArgs, .{
        .ctx = &tracking,
        .destroyFn = trackCnfTreeDestroy,
    });

    try std.testing.expectEqual(@as(usize, 2), tracking.count);
    try std.testing.expectEqual(@intFromPtr(&setopts), @intFromPtr(tracking.nodes[0]));
    try std.testing.expectEqual(@intFromPtr(&repoopts), @intFromPtr(tracking.nodes[1]));
}
