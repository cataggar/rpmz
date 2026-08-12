// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("tdnf_common");
const abi = @import("client_abi");
const options = @import("client_gpgcheck_options");
const errors = @import("tdnf_error");
const rpm = @import("rpm_gpgcheck");
const txn_config = @import("rpm_txn_config");
const transaction_lock = @import("transaction_lock");

const Repo = abi.C.TDNF_REPO_DATA;
const Tdnf = abi.Tdnf;
const FileHandle = rpm.FileHandle;
const TxnConfig = txn_config.TxnConfig;
const PubkeyIter = opaque {};

const ERROR_TDNF_INVALID_PUBKEY_FILE: u32 = 1505;
const ERROR_TDNF_KEYURL_INVALID: u32 = 1507;
const ERROR_TDNF_RPM_GPG_PARSE_FAILED: u32 = 1513;
const ERROR_TDNF_RPM_GPG_NO_MATCH: u32 = 1514;
const ERROR_TDNF_RPM_CHECK: u32 = 1515;
const ERROR_TDNF_NO_GPGKEY_CONF_ENTRY: u32 = 1523;
const ERROR_TDNF_RPMRC_NOTFOUND: u32 = 1471;
const ERROR_TDNF_RPM_UNSIGNED: u32 = 1531;

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const F_OK: c_int = 0;

extern fn TDNFAllocateMemory(
    count: usize,
    size: usize,
    output: *?*anyopaque,
) callconv(.c) u32;
extern fn TDNFFreeMemory(memory: ?*anyopaque) callconv(.c) void;
extern fn TDNFFreeStringArray(values: ?[*]?[*:0]u8) callconv(.c) void;
extern fn TDNFIsDir(
    path: ?[*:0]const u8,
    is_dir: *c_int,
) callconv(.c) u32;
extern fn TDNFFileReadAllText(
    path: ?[*:0]const u8,
    data: *?[*:0]u8,
    size: *c_int,
) callconv(.c) u32;
extern fn TDNFGetGPGKeys(
    tdnf: ?*Tdnf,
    repo: ?*Repo,
    keys: *?[*]?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFYesOrNo(
    args: ?*abi.CmdArgs,
    question: ?[*:0]const u8,
    answer: *c_int,
) callconv(.c) u32;
extern fn TDNFPathFromUri(
    uri: ?[*:0]const u8,
    path: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFGetCachePath(
    tdnf: ?*Tdnf,
    repo: ?*Repo,
    subdir: ?[*:0]const u8,
    file: ?[*:0]const u8,
    path: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFNormalizePath(
    path: ?[*:0]const u8,
    normalized: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFJoinPathFromArray(
    path: *?[*:0]u8,
    nodes: [*]?[*:0]u8,
    count: c_int,
) callconv(.c) u32;
extern fn TDNFDirName(
    path: ?[*:0]const u8,
    dirname: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFUtilsMakeDirs(path: ?[*:0]const u8) callconv(.c) u32;
extern fn TDNFDownloadFile(
    tdnf: ?*Tdnf,
    repo: ?*Repo,
    url: ?[*:0]const u8,
    path: ?[*:0]const u8,
    progress: ?[*:0]const u8,
    require_https: c_int,
) callconv(.c) u32;
extern fn access(path: [*:0]const u8, mode: c_int) callconv(.c) c_int;
extern fn unlink(path: [*:0]const u8) callconv(.c) c_int;
extern fn basename(path: [*:0]u8) callconv(.c) [*:0]u8;
extern fn __errno_location() callconv(.c) *c_int;
extern fn tdnf_rpmdb_import_pubkeys_config(
    config: ?*const TxnConfig,
    data: ?*const anyopaque,
    len: usize,
    imported: ?*usize,
) callconv(.c) c_int;
extern fn tdnf_rpmdb_pubkeys_open_config(
    config: ?*const TxnConfig,
) callconv(.c) ?*PubkeyIter;
extern fn tdnf_rpmdb_pubkeys_close(iter: ?*PubkeyIter) callconv(.c) void;
extern fn tdnf_rpmdb_pubkeys_next(
    iter: ?*PubkeyIter,
    key: ?*[*:0]u8,
    key_len: ?*usize,
    keyid: ?*[*:0]u8,
) callconv(.c) c_int;
extern fn tdnf_rpmdb_string_free(value: ?*anyopaque) callconv(.c) void;
extern fn tdnf_rpmdb_last_error() callconv(.c) [*:0]const u8;

threadlocal var direct_error: [160]u8 = [_]u8{0} ** 160;

fn setDirectError(comptime format: []const u8, args: anytype) void {
    _ = std.fmt.bufPrintZ(&direct_error, format, args) catch {
        const fallback = "direct verifier error";
        @memcpy(direct_error[0..fallback.len], fallback);
        direct_error[fallback.len] = 0;
        return;
    };
}

fn lastVerifierError() [*:0]const u8 {
    if (direct_error[0] != 0) return @ptrCast(&direct_error);
    return tdnf_rpmdb_last_error();
}

const Ops = struct {
    context: ?*anyopaque = null,
    allocate: *const fn (?*anyopaque, usize, usize, *?*anyopaque) u32,
    free: *const fn (?*anyopaque, ?*anyopaque) void,
    free_strings: *const fn (?*anyopaque, ?[*]?[*:0]u8) void,
    is_dir: *const fn (?*anyopaque, [*:0]const u8, *c_int) u32,
    read_all: *const fn (?*anyopaque, [*:0]const u8, *?[*:0]u8, *c_int) u32,
    get_keys: *const fn (?*anyopaque, *Tdnf, *Repo, *?[*]?[*:0]u8) u32,
    yes_no: *const fn (?*anyopaque, ?*abi.CmdArgs, [*:0]const u8, *c_int) u32,
    path_from_uri: *const fn (?*anyopaque, [*:0]const u8, *?[*:0]u8) u32,
    fetch_remote: *const fn (?*anyopaque, *Tdnf, *Repo, [*:0]const u8, *?[*:0]u8) u32,
    import_key: *const fn (?*anyopaque, *TxnConfig, []const u8) u32,
    verify_digests: *const fn (?*anyopaque, *FileHandle, *c_int) c_int,
    is_signed: *const fn (?*anyopaque, *FileHandle) c_int,
    verify_signatures: *const fn (
        ?*anyopaque,
        *FileHandle,
        *TxnConfig,
        ?[*]const ?*const anyopaque,
        ?[*]const usize,
        usize,
        *c_int,
    ) c_int,
    open_file: *const fn (?*anyopaque, [*:0]const u8) ?*FileHandle,
    close_file: *const fn (?*anyopaque, ?*FileHandle) void,
};

fn productionAllocate(
    _: ?*anyopaque,
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32 {
    return TDNFAllocateMemory(count, size, output);
}

fn productionFree(_: ?*anyopaque, memory: ?*anyopaque) void {
    TDNFFreeMemory(memory);
}

fn productionFreeStrings(_: ?*anyopaque, values: ?[*]?[*:0]u8) void {
    TDNFFreeStringArray(values);
}

fn productionIsDir(
    _: ?*anyopaque,
    path: [*:0]const u8,
    is_dir: *c_int,
) u32 {
    return TDNFIsDir(path, is_dir);
}

fn productionReadAll(
    _: ?*anyopaque,
    path: [*:0]const u8,
    data: *?[*:0]u8,
    size: *c_int,
) u32 {
    return TDNFFileReadAllText(path, data, size);
}

fn productionGetKeys(
    _: ?*anyopaque,
    tdnf: *Tdnf,
    repo: *Repo,
    keys: *?[*]?[*:0]u8,
) u32 {
    return TDNFGetGPGKeys(tdnf, repo, keys);
}

fn productionYesNo(
    _: ?*anyopaque,
    args: ?*abi.CmdArgs,
    question: [*:0]const u8,
    answer: *c_int,
) u32 {
    return TDNFYesOrNo(args, question, answer);
}

fn productionPathFromUri(
    _: ?*anyopaque,
    uri: [*:0]const u8,
    path: *?[*:0]u8,
) u32 {
    return TDNFPathFromUri(uri, path);
}

fn productionFetchRemote(
    _: ?*anyopaque,
    tdnf: *Tdnf,
    repo: *Repo,
    uri: [*:0]const u8,
    path: *?[*:0]u8,
) u32 {
    return fetchRemoteGpgKey(tdnf, repo, uri, path);
}

fn productionImportKey(
    _: ?*anyopaque,
    config: *TxnConfig,
    data: []const u8,
) u32 {
    return importKeyWithTargetLock(
        config,
        data,
        null,
        {},
        importKeyMutation,
    );
}

fn importKeyMutation(
    _: void,
    config: *TxnConfig,
    data: []const u8,
) u32 {
    var imported: usize = 0;
    if (tdnf_rpmdb_import_pubkeys_config(
        config,
        data.ptr,
        data.len,
        &imported,
    ) != 0 or imported == 0) {
        common.log(LOG_ERR, "Unable to import repository key: %s\n", .{tdnf_rpmdb_last_error()});
        return ERROR_TDNF_INVALID_PUBKEY_FILE;
    }
    return 0;
}

fn importKeyWithTargetLock(
    config: *TxnConfig,
    data: []const u8,
    lock_directory: ?[]const u8,
    context: anytype,
    import_fn: anytype,
) u32 {
    if (config.pinnedInstallRootFd() != null) {
        return import_fn(context, config, data);
    }
    var guard = blk: {
        if (lock_directory) |directory| {
            break :blk transaction_lock.acquireInDirectory(
                std.heap.c_allocator,
                config,
                directory,
                true,
            ) catch |err| {
                common.log(
                    LOG_ERR,
                    "Unable to lock rpmdb key import target: %s\n",
                    .{@errorName(err)},
                );
                return ERROR_TDNF_RPM_CHECK;
            };
        }
        break :blk transaction_lock.acquire(
            std.heap.c_allocator,
            config,
        ) catch |err| {
            common.log(
                LOG_ERR,
                "Unable to lock rpmdb key import target: %s\n",
                .{@errorName(err)},
            );
            return ERROR_TDNF_RPM_CHECK;
        };
    };
    defer guard.deinit();
    return import_fn(context, guard.config(), data);
}

fn productionVerifyDigests(
    _: ?*anyopaque,
    file: *FileHandle,
    outcome: *c_int,
) c_int {
    direct_error[0] = 0;
    const result = rpm.verifyDigests(std.heap.c_allocator, file) catch |err| {
        setDirectError("verify package digests: {t}", .{err});
        return -1;
    };
    outcome.* = @intFromEnum(result);
    return 0;
}

fn productionIsSigned(_: ?*anyopaque, file: *FileHandle) c_int {
    return if (file.file.isSigned()) 1 else 0;
}

fn productionVerifySignatures(
    _: ?*anyopaque,
    file: *FileHandle,
    config: *TxnConfig,
    keys: ?[*]const ?*const anyopaque,
    lengths: ?[*]const usize,
    count: usize,
    outcome: *c_int,
) c_int {
    direct_error[0] = 0;
    if (count > 0 and (keys == null or lengths == null)) {
        setDirectError("null fresh keys with non-zero key count", .{});
        return -1;
    }

    var blobs = std.ArrayList([]const u8).empty;
    defer blobs.deinit(std.heap.c_allocator);
    var owned = std.ArrayList([*:0]u8).empty;
    defer {
        for (owned.items) |key| tdnf_rpmdb_string_free(@ptrCast(key));
        owned.deinit(std.heap.c_allocator);
    }

    if (count > 0) {
        for (0..count) |index| {
            const key = keys.?[index] orelse {
                setDirectError("fresh key {d} is null", .{index});
                return -1;
            };
            if (lengths.?[index] == 0) {
                setDirectError("fresh key {d} is empty", .{index});
                return -1;
            }
            blobs.append(
                std.heap.c_allocator,
                @as([*]const u8, @ptrCast(key))[0..lengths.?[index]],
            ) catch {
                setDirectError("out of memory collecting fresh keys", .{});
                return -1;
            };
        }
    }

    const iter = tdnf_rpmdb_pubkeys_open_config(config) orelse return -1;
    defer tdnf_rpmdb_pubkeys_close(iter);
    while (true) {
        var key: [*:0]u8 = undefined;
        var key_len: usize = 0;
        const next = tdnf_rpmdb_pubkeys_next(iter, &key, &key_len, null);
        if (next == 0) break;
        if (next < 0) return -1;
        owned.append(std.heap.c_allocator, key) catch {
            tdnf_rpmdb_string_free(@ptrCast(key));
            setDirectError("out of memory collecting rpmdb keys", .{});
            return -1;
        };
        blobs.append(std.heap.c_allocator, key[0..key_len]) catch {
            setDirectError("out of memory collecting rpmdb keys", .{});
            return -1;
        };
    }

    const result = rpm.verifySignatures(
        std.heap.c_allocator,
        file,
        blobs.items,
    ) catch |err| {
        setDirectError("verify package signatures: {t}", .{err});
        return -1;
    };
    outcome.* = @intFromEnum(result);
    return 0;
}

fn productionOpenFile(_: ?*anyopaque, path: [*:0]const u8) ?*FileHandle {
    direct_error[0] = 0;
    return rpm.openFile(path[0..std.mem.len(path) :0]) catch |err| {
        setDirectError("rpm_file_open({s}): {t}", .{ std.mem.span(path), err });
        return null;
    };
}

fn productionCloseFile(_: ?*anyopaque, file: ?*FileHandle) void {
    rpm.closeFile(file);
}

const production_ops = Ops{
    .allocate = &productionAllocate,
    .free = &productionFree,
    .free_strings = &productionFreeStrings,
    .is_dir = &productionIsDir,
    .read_all = &productionReadAll,
    .get_keys = &productionGetKeys,
    .yes_no = &productionYesNo,
    .path_from_uri = &productionPathFromUri,
    .fetch_remote = &productionFetchRemote,
    .import_key = &productionImportKey,
    .verify_digests = &productionVerifyDigests,
    .is_signed = &productionIsSigned,
    .verify_signatures = &productionVerifySignatures,
    .open_file = &productionOpenFile,
    .close_file = &productionCloseFile,
};

fn systemError() u32 {
    return errors.ERROR_TDNF_SYSTEM_BASE + @as(u32, @intCast(__errno_location().*));
}

fn freeValue(ops: *const Ops, value: anytype) void {
    if (value) |pointer| {
        ops.free(ops.context, @ptrCast(@constCast(pointer)));
    }
}

fn readGpgKeyFile(
    ops: *const Ops,
    file: ?[*:0]const u8,
    data_out: ?*?[*:0]u8,
    size_out: ?*c_int,
) u32 {
    if (file == null or file.?[0] == 0 or data_out == null or size_out == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var is_dir: c_int = 0;
    var result = ops.is_dir(ops.context, file.?, &is_dir);
    if (result != 0) {
        common.log(LOG_ERR, "Error: Accessing gpgkey at %s\n", .{file.?});
        return result;
    }
    if (is_dir != 0) return ERROR_TDNF_KEYURL_INVALID;

    var data: ?[*:0]u8 = null;
    result = ops.read_all(ops.context, file.?, &data, size_out.?);
    if (result != 0) {
        freeValue(ops, data);
        return result;
    }
    data_out.?.* = data;
    return 0;
}

fn mapDigestOutcome(outcome: c_int) u32 {
    switch (outcome) {
        @intFromEnum(rpm.Outcome.ok) => return 0,
        @intFromEnum(rpm.Outcome.missing) => common.log(LOG_ERR, "RPM is missing required internal digest coverage\n", .{}),
        @intFromEnum(rpm.Outcome.bad) => common.log(LOG_ERR, "RPM internal digest verification failed\n", .{}),
        @intFromEnum(rpm.Outcome.unsupported) => common.log(LOG_ERR, "RPM uses an unsupported internal digest\n", .{}),
        @intFromEnum(rpm.Outcome.malformed) => common.log(LOG_ERR, "RPM contains malformed internal digest metadata\n", .{}),
        else => common.log(LOG_ERR, "RPM internal digest verification could not complete\n", .{}),
    }
    return ERROR_TDNF_RPM_CHECK;
}

fn mapSignatureOutcome(outcome: c_int) u32 {
    switch (outcome) {
        @intFromEnum(rpm.Outcome.ok) => return 0,
        @intFromEnum(rpm.Outcome.missing) => {
            common.log(LOG_ERR, "RPM signature has no matching trusted key\n", .{});
            return ERROR_TDNF_RPM_GPG_NO_MATCH;
        },
        @intFromEnum(rpm.Outcome.bad) => {
            common.log(LOG_ERR, "RPM signature verification failed\n", .{});
            return ERROR_TDNF_RPM_GPG_NO_MATCH;
        },
        @intFromEnum(rpm.Outcome.unsupported) => {
            common.log(LOG_ERR, "RPM signature uses unsupported OpenPGP metadata\n", .{});
            return ERROR_TDNF_RPM_GPG_PARSE_FAILED;
        },
        @intFromEnum(rpm.Outcome.malformed) => {
            common.log(LOG_ERR, "RPM contains malformed OpenPGP signature metadata\n", .{});
            return ERROR_TDNF_RPM_GPG_PARSE_FAILED;
        },
        else => {
            common.log(LOG_ERR, "RPM signature verification could not complete\n", .{});
            return ERROR_TDNF_RPM_CHECK;
        },
    }
}

const KeyLocation = enum {
    https,
    file_uri,
    local_path,
};

fn classifyKeyLocation(value: [*:0]const u8) error{InvalidKeyLocation}!KeyLocation {
    const text = std.mem.span(value);
    if (text.len == 0 or
        std.ascii.isWhitespace(text[0]) or
        std.ascii.isWhitespace(text[text.len - 1]))
    {
        return error.InvalidKeyLocation;
    }

    const colon = std.mem.indexOfScalar(u8, text, ':') orelse
        return .local_path;
    const first_separator = std.mem.indexOfAny(u8, text, "/\\");
    if (first_separator != null and colon > first_separator.?)
        return .local_path;
    if (colon == 0) return error.InvalidKeyLocation;
    for (text[0..colon], 0..) |char, index| {
        const valid = std.ascii.isAlphabetic(char) or
            (index != 0 and
                (std.ascii.isDigit(char) or char == '+' or
                    char == '-' or char == '.'));
        if (!valid) return error.InvalidKeyLocation;
    }

    const remainder = text[colon + 1 ..];
    if (!std.mem.startsWith(u8, remainder, "//"))
        return error.InvalidKeyLocation;
    const scheme = text[0..colon];
    if (std.ascii.eqlIgnoreCase(scheme, "http"))
        return error.InvalidKeyLocation;
    const parsed = std.Uri.parse(text) catch
        return error.InvalidKeyLocation;
    if (parsed.user != null or parsed.password != null)
        return error.InvalidKeyLocation;
    if (std.ascii.eqlIgnoreCase(scheme, "file")) {
        if (parsed.path.percent_encoded.len <= 1 or parsed.fragment != null)
            return error.InvalidKeyLocation;
        return .file_uri;
    }
    if (!std.ascii.eqlIgnoreCase(scheme, "https"))
        return error.InvalidKeyLocation;

    if (parsed.host == null or parsed.fragment != null) {
        return error.InvalidKeyLocation;
    }
    return .https;
}

fn gpgCheckPackage(
    ops: *const Ops,
    tdnf_opt: ?*Tdnf,
    repo_opt: ?*Repo,
    file_path: ?[*:0]const u8,
    rpm_file_opt: ?*FileHandle,
    policy_rejected: ?*c_int,
) u32 {
    if (policy_rejected) |out| out.* = 0;
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo = repo_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const path = file_path orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const file = rpm_file_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const conf = tdnf.pConf orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const raw_config = tdnf.pRpmConfig orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (path[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const config: *TxnConfig = @ptrCast(@alignCast(raw_config));

    if (repo.nGPGCheck == 0) return 0;

    var outcome: c_int = @intFromEnum(rpm.Outcome.internal);
    if (conf.nSkipDigest == 0) {
        if (ops.verify_digests(ops.context, file, &outcome) != 0) {
            common.log(LOG_ERR, "Unable to verify package digests for %s: %s\n", .{ path, lastVerifierError() });
            return ERROR_TDNF_RPM_CHECK;
        }
        const result = mapDigestOutcome(outcome);
        if (result != 0) {
            if (policy_rejected) |out| {
                if (outcome != @intFromEnum(rpm.Outcome.internal))
                    out.* = 1;
            }
            return result;
        }
    }

    if (conf.nSkipSignature != 0) return 0;

    const signed = ops.is_signed(ops.context, file);
    if (signed < 0) return ERROR_TDNF_RPM_CHECK;
    if (signed == 0) {
        if (policy_rejected) |out| out.* = 1;
        return ERROR_TDNF_RPM_UNSIGNED;
    }

    if (ops.verify_signatures(
        ops.context,
        file,
        config,
        null,
        null,
        0,
        &outcome,
    ) != 0) {
        common.log(LOG_ERR, "Unable to verify package signature for %s: %s\n", .{ path, lastVerifierError() });
        return ERROR_TDNF_RPM_CHECK;
    }
    if (outcome == @intFromEnum(rpm.Outcome.ok)) return 0;
    if (outcome != @intFromEnum(rpm.Outcome.missing)) {
        const result = mapSignatureOutcome(outcome);
        if (policy_rejected) |out| {
            if (outcome != @intFromEnum(rpm.Outcome.internal))
                out.* = 1;
        }
        return result;
    }

    var keys: ?[*]?[*:0]u8 = null;
    defer ops.free_strings(ops.context, keys);
    var result = ops.get_keys(ops.context, tdnf, repo, &keys);
    if (result != 0) return result;

    var configured_count: usize = 0;
    while (keys.?[configured_count] != null) : (configured_count += 1) {}
    if (configured_count == 0) return ERROR_TDNF_NO_GPGKEY_CONF_ENTRY;

    var raw_fresh: ?*anyopaque = null;
    result = ops.allocate(
        ops.context,
        configured_count,
        @sizeOf(?*const anyopaque),
        &raw_fresh,
    );
    if (result != 0) return result;
    const fresh: [*]?*const anyopaque = @ptrCast(@alignCast(raw_fresh.?));
    var fresh_count: usize = 0;
    defer {
        for (fresh[0..fresh_count]) |key| freeValue(ops, key);
        ops.free(ops.context, raw_fresh);
    }

    var raw_lengths: ?*anyopaque = null;
    result = ops.allocate(
        ops.context,
        configured_count,
        @sizeOf(usize),
        &raw_lengths,
    );
    if (result != 0) return result;
    const lengths: [*]usize = @ptrCast(@alignCast(raw_lengths.?));
    defer ops.free(ops.context, raw_lengths);

    for (0..configured_count) |index| {
        const key_uri = keys.?[index].?;
        const location = classifyKeyLocation(key_uri) catch
            return ERROR_TDNF_KEYURL_INVALID;

        var owned_local_key: ?[*:0]u8 = null;
        defer freeValue(ops, owned_local_key);
        var remove_remote = false;
        defer {
            if (remove_remote and owned_local_key != null)
                _ = unlink(owned_local_key.?);
        }
        if (location == .https) {
            result = ops.fetch_remote(
                ops.context,
                tdnf,
                repo,
                key_uri,
                &owned_local_key,
            );
            if (result != 0) return result;
            remove_remote = true;
        }

        common.log(LOG_INFO, "importing key from %s\n", .{key_uri});
        var answer: c_int = 0;
        result = ops.yes_no(ops.context, tdnf.pArgs, "Is this ok [y/N]: ", &answer);
        if (result != 0) return result;
        if (answer == 0) return errors.ERROR_TDNF_OPERATION_ABORTED;

        const local_key: [*:0]const u8 = switch (location) {
            .https => owned_local_key.?,
            .file_uri => blk: {
                result = ops.path_from_uri(
                    ops.context,
                    key_uri,
                    &owned_local_key,
                );
                if (result == errors.ERROR_TDNF_URL_INVALID)
                    result = ERROR_TDNF_KEYURL_INVALID;
                if (result != 0) return result;
                break :blk owned_local_key.?;
            },
            .local_path => key_uri,
        };

        var key_data: ?[*:0]u8 = null;
        var key_size: c_int = 0;
        result = readGpgKeyFile(ops, local_key, &key_data, &key_size);
        if (result != 0) return result;
        defer if (key_data) |value| ops.free(ops.context, @ptrCast(value));
        if (key_size <= 0) return ERROR_TDNF_INVALID_PUBKEY_FILE;

        const key_bytes = key_data.?[0..@intCast(key_size)];
        result = ops.import_key(ops.context, config, key_bytes);
        if (result != 0) return result;

        fresh[fresh_count] = @ptrCast(key_data.?);
        lengths[fresh_count] = @intCast(key_size);
        fresh_count += 1;
        key_data = null;

        if (location == .https) {
            if (unlink(local_key) != 0) return systemError();
            remove_remote = false;
        }
    }

    if (ops.verify_signatures(
        ops.context,
        file,
        config,
        fresh,
        lengths,
        fresh_count,
        &outcome,
    ) != 0) {
        common.log(LOG_ERR, "Unable to verify package signature for %s: %s\n", .{ path, lastVerifierError() });
        return ERROR_TDNF_RPM_CHECK;
    }
    result = mapSignatureOutcome(outcome);
    if (result != 0) {
        if (policy_rejected) |out| {
            if (outcome != @intFromEnum(rpm.Outcome.internal))
                out.* = 1;
        }
    }
    return result;
}

fn fetchRemoteGpgKey(
    tdnf_opt: ?*Tdnf,
    repo_opt: ?*Repo,
    url_opt: ?[*:0]const u8,
    location_out: ?*?[*:0]u8,
) u32 {
    if (location_out) |out| out.* = null;
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const repo = repo_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const url = url_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const out = location_out orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (url[0] == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const location = classifyKeyLocation(url) catch
        return fetchError(url, ERROR_TDNF_KEYURL_INVALID);
    if (location != .https)
        return fetchError(url, ERROR_TDNF_KEYURL_INVALID);

    var key_location: ?[*:0]u8 = null;
    defer freeValue(&production_ops, key_location);
    var result = TDNFPathFromUri(url, &key_location);
    if (result == errors.ERROR_TDNF_URL_INVALID) result = ERROR_TDNF_KEYURL_INVALID;
    if (result != 0) return fetchError(url, result);

    var top_cache: ?[*:0]u8 = null;
    defer freeValue(&production_ops, top_cache);
    result = TDNFGetCachePath(tdnf, repo, "keys", null, &top_cache);
    if (result != 0) return fetchError(url, result);

    var real_top_cache: ?[*:0]u8 = null;
    defer freeValue(&production_ops, real_top_cache);
    result = TDNFNormalizePath(top_cache, &real_top_cache);
    if (result != 0) return fetchError(url, result);

    var file_path: ?[*:0]u8 = null;
    defer freeValue(&production_ops, file_path);
    var nodes = [_]?[*:0]u8{ real_top_cache, key_location };
    result = TDNFJoinPathFromArray(&file_path, &nodes, @intCast(nodes.len));
    if (result != 0) return fetchError(url, result);

    var normal_path: ?[*:0]u8 = null;
    result = TDNFNormalizePath(file_path, &normal_path);
    if (result != 0) return fetchError(url, result);
    defer if (normal_path) |value| TDNFFreeMemory(@ptrCast(value));

    const root = std.mem.span(real_top_cache.?);
    const normalized = std.mem.span(normal_path.?);
    if (!std.mem.startsWith(u8, normalized, root))
        return fetchError(url, ERROR_TDNF_KEYURL_INVALID);

    var download_dir: ?[*:0]u8 = null;
    defer freeValue(&production_ops, download_dir);
    result = TDNFDirName(normal_path, &download_dir);
    if (result != 0) return fetchError(url, result);

    if (access(download_dir.?, F_OK) != 0) {
        if (__errno_location().* != @intFromEnum(std.posix.E.NOENT))
            return fetchError(url, systemError());
        result = TDNFUtilsMakeDirs(download_dir);
        if (result != 0) return fetchError(url, result);
    }

    result = TDNFDownloadFile(
        tdnf,
        repo,
        url,
        file_path,
        basename(file_path.?),
        1,
    );
    if (result == errors.ERROR_TDNF_URL_INVALID)
        result = ERROR_TDNF_KEYURL_INVALID;
    if (result != 0) return fetchError(url, result);

    out.* = normal_path;
    normal_path = null;
    return 0;
}

fn fetchError(url: [*:0]const u8, result: u32) u32 {
    common.log(LOG_ERR, "Error processing key: %s\n", .{url});
    return result;
}

fn gpgCheckPackageEx(
    ops: *const Ops,
    tdnf: ?*Tdnf,
    repo: ?*Repo,
    file_path: ?[*:0]const u8,
    file_out: ?*?*FileHandle,
    policy_rejected: ?*c_int,
) u32 {
    if (file_out) |out| out.* = null;
    if (policy_rejected) |out| out.* = 0;
    if (tdnf == null or tdnf.?.pConf == null or tdnf.?.pRpmConfig == null or
        repo == null or file_path == null or file_path.?[0] == 0)
    {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    const file = ops.open_file(ops.context, file_path.?) orelse {
        common.log(LOG_ERR, "Unable to parse package %s: %s\n", .{ file_path.?, lastVerifierError() });
        return ERROR_TDNF_RPMRC_NOTFOUND;
    };
    var owned = true;
    defer if (owned) ops.close_file(ops.context, file);

    const result = gpgCheckPackage(
        ops,
        tdnf,
        repo,
        file_path,
        file,
        policy_rejected,
    );
    if (result != 0) return result;

    if (file_out) |out| {
        out.* = file;
        owned = false;
    }
    return 0;
}

fn readGpgKeyFileExport(
    file: ?[*:0]const u8,
    data: ?*?[*:0]u8,
    size: ?*c_int,
) callconv(.c) u32 {
    return readGpgKeyFile(&production_ops, file, data, size);
}

fn gpgCheckPackageWithFileExport(
    tdnf: ?*Tdnf,
    repo: ?*Repo,
    file_path: ?[*:0]const u8,
    file: ?*FileHandle,
    policy_rejected: ?*c_int,
) callconv(.c) u32 {
    return gpgCheckPackage(
        &production_ops,
        tdnf,
        repo,
        file_path,
        file,
        policy_rejected,
    );
}

fn gpgCheckPackageExExport(
    tdnf: ?*Tdnf,
    repo: ?*Repo,
    file_path: ?[*:0]const u8,
    file_out: ?*?*FileHandle,
    policy_rejected: ?*c_int,
) callconv(.c) u32 {
    return gpgCheckPackageEx(
        &production_ops,
        tdnf,
        repo,
        file_path,
        file_out,
        policy_rejected,
    );
}

fn fetchRemoteGpgKeyExport(
    tdnf: ?*Tdnf,
    repo: ?*Repo,
    url: ?[*:0]const u8,
    location: ?*?[*:0]u8,
) callconv(.c) u32 {
    return fetchRemoteGpgKey(tdnf, repo, url, location);
}

comptime {
    if (!options.test_mode) {
        @export(&readGpgKeyFileExport, .{
            .name = "ReadGPGKeyFile",
            .visibility = .default,
        });
        @export(&gpgCheckPackageWithFileExport, .{
            .name = "TDNFGPGCheckPackageWithFile",
            .visibility = .default,
        });
        @export(&gpgCheckPackageExExport, .{
            .name = "TDNFGPGCheckPackageEx",
            .visibility = .default,
        });
        @export(&fetchRemoteGpgKeyExport, .{
            .name = "TDNFFetchRemoteGPGKey",
            .visibility = .default,
        });
    }
}

const Mock = struct {
    keys: []const [*:0]const u8 = &.{},
    digest_outcome: c_int = @intFromEnum(rpm.Outcome.ok),
    initial_signature: c_int = @intFromEnum(rpm.Outcome.ok),
    final_signature: c_int = @intFromEnum(rpm.Outcome.ok),
    digest_rc: c_int = 0,
    signature_rc: c_int = 0,
    import_result: u32 = 0,
    get_keys_result: u32 = 0,
    fetch_result: u32 = 0,
    answer: c_int = 1,
    signed: c_int = 1,
    fail_allocation: usize = 0,
    allocation_calls: usize = 0,
    digest_calls: usize = 0,
    signature_calls: usize = 0,
    import_calls: usize = 0,
    imported_lengths: [8]usize = [_]usize{0} ** 8,
    prompt_calls: usize = 0,
    fetch_calls: usize = 0,
    open_result: ?*FileHandle = @ptrFromInt(0x1000),
    close_calls: usize = 0,

    fn self(context: ?*anyopaque) *Mock {
        return @ptrCast(@alignCast(context.?));
    }

    fn dupeZ(value: []const u8) ?[*:0]u8 {
        const copy = std.heap.c_allocator.allocSentinel(u8, value.len, 0) catch
            return null;
        @memcpy(copy, value);
        return copy.ptr;
    }

    fn allocate(
        context: ?*anyopaque,
        count: usize,
        size: usize,
        output: *?*anyopaque,
    ) u32 {
        const mock = self(context);
        mock.allocation_calls += 1;
        output.* = null;
        if (mock.fail_allocation == mock.allocation_calls)
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        output.* = std.c.calloc(count, size) orelse
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        return 0;
    }

    fn free(_: ?*anyopaque, memory: ?*anyopaque) void {
        std.c.free(memory);
    }

    fn freeStrings(_: ?*anyopaque, values_opt: ?[*]?[*:0]u8) void {
        const values = values_opt orelse return;
        var index: usize = 0;
        while (values[index]) |value| : (index += 1)
            std.heap.c_allocator.free(value[0..std.mem.len(value) :0]);
        std.c.free(@ptrCast(values));
    }

    fn isDir(_: ?*anyopaque, _: [*:0]const u8, output: *c_int) u32 {
        output.* = 0;
        return 0;
    }

    fn readAll(
        _: ?*anyopaque,
        _: [*:0]const u8,
        data: *?[*:0]u8,
        size: *c_int,
    ) u32 {
        const key = "binary\x00key";
        const copy = std.heap.c_allocator.allocSentinel(u8, key.len, 0) catch
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        @memcpy(copy, key);
        data.* = copy.ptr;
        size.* = key.len;
        return 0;
    }

    fn getKeys(
        context: ?*anyopaque,
        _: *Tdnf,
        _: *Repo,
        output: *?[*]?[*:0]u8,
    ) u32 {
        const mock = self(context);
        if (mock.get_keys_result != 0) return mock.get_keys_result;
        const raw = std.c.calloc(
            mock.keys.len + 1,
            @sizeOf(?[*:0]u8),
        ) orelse return errors.ERROR_TDNF_OUT_OF_MEMORY;
        const values: [*]?[*:0]u8 = @ptrCast(@alignCast(raw));
        for (mock.keys, 0..) |key, index| {
            values[index] = dupeZ(std.mem.span(key)) orelse {
                freeStrings(null, values);
                return errors.ERROR_TDNF_OUT_OF_MEMORY;
            };
        }
        output.* = values;
        return 0;
    }

    fn yesNo(
        context: ?*anyopaque,
        _: ?*abi.CmdArgs,
        question: [*:0]const u8,
        output: *c_int,
    ) u32 {
        const mock = self(context);
        std.debug.assert(std.mem.eql(
            u8,
            std.mem.span(question),
            "Is this ok [y/N]: ",
        ));
        mock.prompt_calls += 1;
        output.* = mock.answer;
        return 0;
    }

    fn pathFromUri(
        _: ?*anyopaque,
        _: [*:0]const u8,
        output: *?[*:0]u8,
    ) u32 {
        output.* = dupeZ("/key") orelse
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        return 0;
    }

    fn fetchRemote(
        context: ?*anyopaque,
        _: *Tdnf,
        _: *Repo,
        _: [*:0]const u8,
        output: *?[*:0]u8,
    ) u32 {
        const mock = self(context);
        mock.fetch_calls += 1;
        if (mock.fetch_result != 0) return mock.fetch_result;
        output.* = dupeZ("/nonexistent/mock-key") orelse
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        return 0;
    }

    fn importKey(
        context: ?*anyopaque,
        _: *TxnConfig,
        data: []const u8,
    ) u32 {
        const mock = self(context);
        mock.imported_lengths[mock.import_calls] = data.len;
        mock.import_calls += 1;
        return mock.import_result;
    }

    fn verifyDigests(
        context: ?*anyopaque,
        _: *FileHandle,
        outcome: *c_int,
    ) c_int {
        const mock = self(context);
        mock.digest_calls += 1;
        outcome.* = mock.digest_outcome;
        return mock.digest_rc;
    }

    fn isSigned(context: ?*anyopaque, _: *FileHandle) c_int {
        return self(context).signed;
    }

    fn verifySignatures(
        context: ?*anyopaque,
        _: *FileHandle,
        _: *TxnConfig,
        _: ?[*]const ?*const anyopaque,
        lengths: ?[*]const usize,
        count: usize,
        outcome: *c_int,
    ) c_int {
        const mock = self(context);
        mock.signature_calls += 1;
        if (mock.signature_calls == 2) {
            std.debug.assert(count == mock.import_calls);
            for (0..count) |index|
                std.debug.assert(lengths.?[index] == mock.imported_lengths[index]);
        }
        outcome.* = if (mock.signature_calls == 1)
            mock.initial_signature
        else
            mock.final_signature;
        return mock.signature_rc;
    }

    fn openFile(
        context: ?*anyopaque,
        _: [*:0]const u8,
    ) ?*FileHandle {
        return self(context).open_result;
    }

    fn closeFile(context: ?*anyopaque, _: ?*FileHandle) void {
        self(context).close_calls += 1;
    }

    fn ops(mock: *Mock) Ops {
        return .{
            .context = mock,
            .allocate = &allocate,
            .free = &free,
            .free_strings = &freeStrings,
            .is_dir = &isDir,
            .read_all = &readAll,
            .get_keys = &getKeys,
            .yes_no = &yesNo,
            .path_from_uri = &pathFromUri,
            .fetch_remote = &fetchRemote,
            .import_key = &importKey,
            .verify_digests = &verifyDigests,
            .is_signed = &isSigned,
            .verify_signatures = &verifySignatures,
            .open_file = &openFile,
            .close_file = &closeFile,
        };
    }
};

const TestContext = struct {
    conf: abi.Conf = .{},
    tdnf: Tdnf = .{},
    repo: Repo = std.mem.zeroes(Repo),

    fn init() TestContext {
        var result = TestContext{};
        result.repo.nGPGCheck = 1;
        return result;
    }

    fn bind(self: *TestContext) void {
        self.tdnf.pConf = &self.conf;
        self.tdnf.pRpmConfig = @ptrFromInt(0x2000);
    }
};

fn fakeFile() *FileHandle {
    return @ptrFromInt(0x1000);
}

test "gpg policy bypass and typed failures preserve rejection semantics" {
    var context = TestContext.init();
    context.bind();
    var mock = Mock{};
    const ops = mock.ops();
    var rejected: c_int = 9;

    context.repo.nGPGCheck = 0;
    try std.testing.expectEqual(@as(u32, 0), gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        &rejected,
    ));
    try std.testing.expectEqual(@as(c_int, 0), rejected);
    try std.testing.expectEqual(@as(usize, 0), mock.digest_calls);

    context.repo.nGPGCheck = 1;
    mock.digest_outcome = @intFromEnum(rpm.Outcome.bad);
    try std.testing.expectEqual(ERROR_TDNF_RPM_CHECK, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        &rejected,
    ));
    try std.testing.expectEqual(@as(c_int, 1), rejected);

    mock.digest_outcome = @intFromEnum(rpm.Outcome.internal);
    try std.testing.expectEqual(ERROR_TDNF_RPM_CHECK, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        &rejected,
    ));
    try std.testing.expectEqual(@as(c_int, 0), rejected);
}

test "signature policy handles unsigned skip and trusted rpmdb key" {
    var context = TestContext.init();
    context.bind();
    var mock = Mock{};
    const ops = mock.ops();
    var rejected: c_int = 0;

    mock.signed = 0;
    try std.testing.expectEqual(ERROR_TDNF_RPM_UNSIGNED, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        &rejected,
    ));
    try std.testing.expectEqual(@as(c_int, 1), rejected);

    context.conf.nSkipSignature = 1;
    try std.testing.expectEqual(@as(u32, 0), gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        &rejected,
    ));

    context.conf.nSkipSignature = 0;
    mock.signed = 1;
    mock.initial_signature = @intFromEnum(rpm.Outcome.ok);
    try std.testing.expectEqual(@as(u32, 0), gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        &rejected,
    ));
    try std.testing.expectEqual(@as(usize, 1), mock.signature_calls);
    try std.testing.expectEqual(@as(usize, 0), mock.import_calls);
}

test "RepoSync key import acquires the shared pinned target lock" {
    const Probe = struct {
        contender: *const TxnConfig,
        lock_directory: []const u8,
        pinned: bool = false,
        blocked: bool = false,

        fn run(
            self: *@This(),
            config: *TxnConfig,
            _: []const u8,
        ) u32 {
            self.pinned = config.pinnedInstallRootFd() != null;
            var contender = transaction_lock.tryAcquireInDirectory(
                std.testing.allocator,
                self.contender,
                self.lock_directory,
            ) catch |err| {
                self.blocked = err == error.WouldBlock;
                return @intFromBool(!self.pinned or !self.blocked);
            };
            contender.deinit();
            return 1;
        }
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "locks");
    try tmp.dir.createDirPath(std.testing.io, "root");
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const lock_directory = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "locks" },
    );
    defer std.testing.allocator.free(lock_directory);
    var config = try TxnConfig.init(std.testing.allocator, root);
    defer config.deinit();
    var contender = try TxnConfig.init(std.testing.allocator, root);
    defer contender.deinit();
    var probe = Probe{
        .contender = &contender,
        .lock_directory = lock_directory,
    };

    try std.testing.expectEqual(
        @as(u32, 0),
        importKeyWithTargetLock(
            &config,
            "key",
            lock_directory,
            &probe,
            Probe.run,
        ),
    );
    try std.testing.expect(probe.pinned);
    try std.testing.expect(probe.blocked);

    var outer = try transaction_lock.acquireInDirectory(
        std.testing.allocator,
        &config,
        lock_directory,
        true,
    );
    defer outer.deinit();
    probe.pinned = false;
    probe.blocked = false;
    try std.testing.expectEqual(
        @as(u32, 0),
        importKeyWithTargetLock(
            outer.config(),
            "key",
            lock_directory,
            &probe,
            Probe.run,
        ),
    );
    try std.testing.expect(probe.pinned);
    try std.testing.expect(probe.blocked);
}

test "approved keys retain binary lengths duplicates and verify after all imports" {
    var context = TestContext.init();
    context.bind();
    var mock = Mock{
        .keys = &.{ "file:///one", "file:///one", "file:///two" },
        .initial_signature = @intFromEnum(rpm.Outcome.missing),
        .final_signature = @intFromEnum(rpm.Outcome.ok),
    };
    const ops = mock.ops();
    var rejected: c_int = 0;

    try std.testing.expectEqual(@as(u32, 0), gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        &rejected,
    ));
    try std.testing.expectEqual(@as(usize, 3), mock.prompt_calls);
    try std.testing.expectEqual(@as(usize, 3), mock.import_calls);
    try std.testing.expectEqual(@as(usize, 2), mock.signature_calls);
    try std.testing.expectEqual(@as(usize, "binary\x00key".len), mock.imported_lengths[0]);
}

test "key acquisition failures preserve ordering and exact errors" {
    var context = TestContext.init();
    context.bind();
    var mock = Mock{
        .initial_signature = @intFromEnum(rpm.Outcome.missing),
    };
    var ops = mock.ops();

    mock.get_keys_result = ERROR_TDNF_NO_GPGKEY_CONF_ENTRY;
    try std.testing.expectEqual(ERROR_TDNF_NO_GPGKEY_CONF_ENTRY, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        null,
    ));

    mock.get_keys_result = 0;
    mock.keys = &.{"file:///key"};
    mock.answer = 0;
    mock.signature_calls = 0;
    try std.testing.expectEqual(errors.ERROR_TDNF_OPERATION_ABORTED, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        null,
    ));
    try std.testing.expectEqual(@as(usize, 0), mock.import_calls);

    mock.answer = 1;
    mock.import_result = ERROR_TDNF_INVALID_PUBKEY_FILE;
    mock.signature_calls = 0;
    try std.testing.expectEqual(ERROR_TDNF_INVALID_PUBKEY_FILE, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        null,
    ));

    mock.import_result = 0;
    mock.keys = &.{"https://example/key"};
    mock.fetch_result = errors.ERROR_TDNF_REPO_PERFORM;
    mock.signature_calls = 0;
    const prompts_before_fetch = mock.prompt_calls;
    try std.testing.expectEqual(errors.ERROR_TDNF_REPO_PERFORM, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        null,
    ));
    try std.testing.expectEqual(@as(usize, 1), mock.fetch_calls);
    try std.testing.expectEqual(prompts_before_fetch, mock.prompt_calls);

    mock.keys = &.{"file:///key"};
    mock.fetch_result = 0;
    mock.fail_allocation = mock.allocation_calls + 1;
    mock.signature_calls = 0;
    ops = mock.ops();
    try std.testing.expectEqual(errors.ERROR_TDNF_OUT_OF_MEMORY, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        null,
    ));
}

test "key URL policy rejects plaintext before prompt fetch or import" {
    var context = TestContext.init();
    context.bind();
    var mock = Mock{
        .keys = &.{"HtTp://example.invalid/repository-key"},
        .initial_signature = @intFromEnum(rpm.Outcome.missing),
    };
    const ops = mock.ops();

    try std.testing.expectEqual(ERROR_TDNF_KEYURL_INVALID, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        null,
    ));
    try std.testing.expectEqual(@as(usize, 0), mock.prompt_calls);
    try std.testing.expectEqual(@as(usize, 0), mock.fetch_calls);
    try std.testing.expectEqual(@as(usize, 0), mock.import_calls);

    mock.keys = &.{"https:/example.invalid/repository-key"};
    mock.signature_calls = 0;
    try std.testing.expectEqual(ERROR_TDNF_KEYURL_INVALID, gpgCheckPackage(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        fakeFile(),
        null,
    ));
    try std.testing.expectEqual(@as(usize, 0), mock.prompt_calls);
    try std.testing.expectEqual(@as(usize, 0), mock.fetch_calls);
    try std.testing.expectEqual(@as(usize, 0), mock.import_calls);
}

test "key URL classification is case robust and rejects malformed schemes" {
    try std.testing.expectEqual(
        KeyLocation.https,
        try classifyKeyLocation("hTtPs://example.invalid/key"),
    );
    try std.testing.expectEqual(
        KeyLocation.https,
        try classifyKeyLocation("https://example.invalid"),
    );
    try std.testing.expectEqual(
        KeyLocation.file_uri,
        try classifyKeyLocation("FiLe:///etc/pki/key"),
    );
    try std.testing.expectEqual(
        KeyLocation.local_path,
        try classifyKeyLocation("/etc/pki/key"),
    );
    try std.testing.expectError(
        error.InvalidKeyLocation,
        classifyKeyLocation("HTTP://example.invalid/key"),
    );
    try std.testing.expectError(
        error.InvalidKeyLocation,
        classifyKeyLocation("https:/example.invalid/key"),
    );
    try std.testing.expectError(
        error.InvalidKeyLocation,
        classifyKeyLocation("https:///key"),
    );
    try std.testing.expectError(
        error.InvalidKeyLocation,
        classifyKeyLocation("ftp://example.invalid/key"),
    );
    try std.testing.expectError(
        error.InvalidKeyLocation,
        classifyKeyLocation("https://user:password@example.invalid/key"),
    );
}

test "both entry points reset outputs and transfer parsed file ownership" {
    var context = TestContext.init();
    context.bind();
    var mock = Mock{};
    const ops = mock.ops();
    var file: ?*FileHandle = @ptrFromInt(0x3000);
    var rejected: c_int = 7;

    try std.testing.expectEqual(errors.ERROR_TDNF_INVALID_PARAMETER, gpgCheckPackageEx(
        &ops,
        null,
        &context.repo,
        "/package.rpm",
        &file,
        &rejected,
    ));
    try std.testing.expect(file == null);
    try std.testing.expectEqual(@as(c_int, 0), rejected);

    try std.testing.expectEqual(@as(u32, 0), gpgCheckPackageEx(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        &file,
        &rejected,
    ));
    try std.testing.expect(file == fakeFile());
    try std.testing.expectEqual(@as(usize, 0), mock.close_calls);

    mock.initial_signature = @intFromEnum(rpm.Outcome.bad);
    mock.signature_calls = 0;
    file = @ptrFromInt(0x3000);
    try std.testing.expectEqual(ERROR_TDNF_RPM_GPG_NO_MATCH, gpgCheckPackageEx(
        &ops,
        &context.tdnf,
        &context.repo,
        "/package.rpm",
        &file,
        &rejected,
    ));
    try std.testing.expect(file == null);
    try std.testing.expectEqual(@as(usize, 1), mock.close_calls);
}
