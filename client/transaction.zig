// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1.

const std = @import("std");
const common = @import("tdnf_common");
const abi = @import("client_abi");
const transaction_options = @import("client_transaction_options");
const errors = @import("tdnf_error");
const trans_flags = @import("rpmtrans_flags");
const rpm_header = @import("rpm_header");

const c = abi.C;

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const LOG_CRIT: c_int = 2;
const F_OK: c_int = 0;

const ERROR_TDNF_RPMRC_NOTFOUND: u32 = 1471;
const ERROR_TDNF_RPM_CHECK: u32 = 1515;
const ERROR_TDNF_TRANSACTION_FAILED: u32 = 1525;
const ERROR_TDNF_SIZE_MISMATCH: u32 = 1527;
const ERROR_TDNF_CHECKSUM_MISMATCH: u32 = 1528;
const ERROR_TDNF_RPMTS_FDDUP_FAILED: u32 = 1529;
const ERROR_TDNF_OVERFLOW: u32 = 1675;

const item_install: c_uint = 1;
const item_upgrade: c_uint = 2;
const item_reinstall: c_uint = 3;
const item_erase: c_uint = 4;
const item_downgrade: c_uint = 5;
const item_obsolete: c_uint = 6;

const install_install: c_int = 0;
const install_upgrade: c_int = 1;
const install_reinstall: c_int = 2;

const package_binary: c_int = 0;
const package_source: c_int = 1;
const package_nosrc: c_int = 2;

const HistoryCtx = opaque {};
const allocator = std.heap.c_allocator;

/// Private Zig contract for replaying a preflighted transaction. Package paths
/// are local, already verified RPMs; this layer never downloads or verifies
/// them and never invokes either transaction solver.
pub const FixedOrderPackageIdentity = struct {
    name: []const u8,
    epoch: ?u32,
    version: []const u8,
    release: []const u8,
    arch: []const u8,
};

pub const FixedOrderRpmDbRow = struct {
    hnum: u32,
    identity: FixedOrderPackageIdentity,
};

pub const FixedOrderLocalRpm = struct {
    path: [:0]const u8,
    identity: FixedOrderPackageIdentity,
};

pub const FixedOrderReplacement = struct {
    package: FixedOrderLocalRpm,
    priors: []const FixedOrderRpmDbRow,
};

pub const FixedOrderItem = union(enum) {
    install: FixedOrderLocalRpm,
    erase: FixedOrderRpmDbRow,
    upgrade: FixedOrderReplacement,
    downgrade: FixedOrderReplacement,
    reinstall: FixedOrderReplacement,
    obsolete: FixedOrderReplacement,
};

pub const FixedOrderTransaction = struct {
    items: []const FixedOrderItem,
    /// Input indices in the exact order recorded by the originating run.
    order: []const u32,
};

pub const FixedOrderExecutionError = error{
    InvalidContext,
    InvalidItem,
    MalformedOrder,
    PriorMismatch,
    PackageOpenFailed,
    PackageIdentityMismatch,
    OutOfMemory,
    RpmCheckFailed,
    TransactionFailed,
    ExecutionFailed,
};

const FixedOrderValidationFailure = enum {
    none,
    invalid_item,
    malformed_order,
    prior_mismatch,
};

const FixedOrderExpectedItem = struct {
    erase: ?FixedOrderRpmDbRow = null,
    priors: []const FixedOrderRpmDbRow = &.{},
};

const PathKey = struct {
    path: []const u8,
    source: [*]const u8,
    source_len: usize,
};

const PathKeyContext = struct {
    pub fn hash(_: @This(), key: PathKey) u64 {
        var result = std.hash.Wyhash.hash(0, key.path);
        result = std.hash.Wyhash.hash(
            result,
            std.mem.asBytes(&key.source_len),
        );
        const address = @intFromPtr(key.source);
        return std.hash.Wyhash.hash(result, std.mem.asBytes(&address));
    }

    pub fn eql(_: @This(), a: PathKey, b: PathKey) bool {
        return a.source == b.source and a.source_len == b.source_len and
            std.mem.eql(u8, a.path, b.path);
    }
};

const PathEntry = struct {
    path: [:0]u8,
    trigger_path: c.tdnf_rpm_trigger_path,
};

const PathList = struct {
    entries: std.ArrayListUnmanaged(PathEntry) = .empty,
    seen: std.HashMapUnmanaged(
        PathKey,
        void,
        PathKeyContext,
        std.hash_map.default_max_load_percentage,
    ) = .empty,

    fn deinit(self: *PathList) void {
        for (self.entries.items) |entry| allocator.free(entry.path);
        self.entries.deinit(allocator);
        self.seen.deinit(allocator);
        self.* = .{};
    }

    fn append(
        self: *PathList,
        path_ptr: ?[*:0]const u8,
        source: ?[*]const u8,
        source_len: usize,
    ) u32 {
        const path_z = path_ptr orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
        const source_ptr = source orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
        const path = std.mem.span(path_z);
        if (path.len == 0 or path[0] != '/' or source_len == 0)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        const lookup = PathKey{
            .path = path,
            .source = source_ptr,
            .source_len = source_len,
        };
        if (self.seen.contains(lookup)) return 0;
        const owned = allocator.dupeZ(u8, path) catch
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        const key = PathKey{
            .path = owned,
            .source = source_ptr,
            .source_len = source_len,
        };
        self.seen.put(allocator, key, {}) catch {
            allocator.free(owned);
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        };
        self.entries.append(allocator, .{
            .path = owned,
            .trigger_path = .{
                .path = owned.ptr,
                .source_header_blob = source_ptr,
                .source_header_len = source_len,
            },
        }) catch {
            _ = self.seen.remove(key);
            allocator.free(owned);
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        };
        return 0;
    }

    fn merge(self: *PathList, other: *const PathList) u32 {
        for (other.entries.items) |entry| {
            const rc = self.append(
                entry.path.ptr,
                entry.trigger_path.source_header_blob,
                entry.trigger_path.source_header_len,
            );
            if (rc != 0) return rc;
        }
        return 0;
    }

    fn flatten(self: *const PathList) ![]c.tdnf_rpm_trigger_path {
        const result = try allocator.alloc(c.tdnf_rpm_trigger_path, self.entries.items.len);
        for (self.entries.items, 0..) |entry, index|
            result[index] = entry.trigger_path;
        return result;
    }
};

const ViewEntry = struct {
    hnum: u32,
    blob: []const u8,
    active: bool = true,
    db_visible: bool = true,
    owns_blob: bool = false,
    added: bool = false,
    removed: bool = false,
    order: u64,
    removal_order: u64 = 0,
};

const PriorEntry = struct {
    hnum: u32,
    blob: []const u8,
};

const TransactionView = struct {
    entries: std.ArrayListUnmanaged(ViewEntry) = .empty,
    alloc: std.mem.Allocator = allocator,

    fn init(config: *const anyopaque, additional: usize) struct { u32, TransactionView } {
        return initWithAllocator(config, additional, allocator);
    }

    fn initWithAllocator(
        config: *const anyopaque,
        additional: usize,
        alloc: std.mem.Allocator,
    ) struct { u32, TransactionView } {
        var result = TransactionView{ .alloc = alloc };
        const iter = c.tdnf_rpmdb_iter_open_config(@ptrCast(config)) orelse
            {
                result.deinit();
                return .{ ERROR_TDNF_TRANSACTION_FAILED, .{} };
            };
        defer c.tdnf_rpmdb_iter_close(iter);
        while (true) {
            var hnum: u32 = 0;
            var blob_ptr: [*c]const u8 = null;
            var blob_len: usize = 0;
            const next = c.tdnf_rpmdb_iter_next_header_blob_hnum(
                iter,
                &hnum,
                &blob_ptr,
                &blob_len,
            );
            if (next == 0) break;
            if (next < 0 or blob_ptr == null or blob_len == 0) {
                result.deinit();
                return .{ ERROR_TDNF_TRANSACTION_FAILED, .{} };
            }
            const rc = result.appendRpmdbEntry(hnum, blob_ptr[0..blob_len]);
            if (rc != 0) {
                result.deinit();
                return .{ rc, .{} };
            }
        }
        const reserve_rc = result.reserveExecutionCapacity(additional);
        if (reserve_rc != 0) {
            result.deinit();
            return .{ reserve_rc, .{} };
        }
        return .{ 0, result };
    }

    fn appendRpmdbEntry(self: *TransactionView, hnum: u32, blob: []const u8) u32 {
        const copy = self.alloc.dupe(u8, blob) catch
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        self.entries.append(self.alloc, .{
            .hnum = hnum,
            .blob = copy,
            .owns_blob = true,
            .order = self.entries.items.len,
        }) catch {
            self.alloc.free(copy);
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        };
        return 0;
    }

    fn reserveExecutionCapacity(self: *TransactionView, additional: usize) u32 {
        const capacity = std.math.add(
            usize,
            self.entries.items.len,
            additional,
        ) catch return ERROR_TDNF_OVERFLOW;
        self.entries.ensureTotalCapacity(self.alloc, capacity) catch
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        return 0;
    }

    fn deinit(self: *TransactionView) void {
        for (self.entries.items) |entry|
            if (entry.owns_blob) self.alloc.free(entry.blob);
        self.entries.deinit(self.alloc);
        self.* = .{};
    }

    fn find(self: *TransactionView, hnum: u32) ?*ViewEntry {
        const index = self.findIndex(hnum) orelse return null;
        return &self.entries.items[index];
    }

    fn findIndex(self: *const TransactionView, hnum: u32) ?usize {
        if (hnum == 0) return null;
        for (self.entries.items, 0..) |entry, index|
            if (entry.hnum == hnum) return index;
        return null;
    }

    fn activate(
        self: *TransactionView,
        blob: []const u8,
        hnum: u32,
        db_visible: bool,
    ) u32 {
        self.entries.append(self.alloc, .{
            .hnum = hnum,
            .blob = blob,
            .db_visible = db_visible,
            .added = true,
            .order = self.entries.items.len,
        }) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
        return 0;
    }

    fn countName(self: *TransactionView, name: ?[*:0]const u8) c_int {
        const name_ptr = name orelse return -1;
        var count: c_int = 0;
        for (self.entries.items) |entry| {
            if (!entry.active) continue;
            const matched = c.tdnf_rpm_header_name_equals(
                entry.blob.ptr,
                entry.blob.len,
                name_ptr,
            );
            if (matched < 0 or (matched != 0 and count == std.math.maxInt(c_int)))
                return -1;
            if (matched != 0) count += 1;
        }
        return count;
    }

    fn headers(self: *TransactionView, db_only: bool) ![]c.tdnf_rpm_header_view {
        var count: usize = 0;
        for (self.entries.items) |entry| {
            if ((db_only and entry.db_visible) or (!db_only and entry.active))
                count += 1;
        }
        const result = try allocator.alloc(c.tdnf_rpm_header_view, count);
        var index: usize = 0;
        for (self.entries.items) |entry| {
            if ((db_only and !entry.db_visible) or (!db_only and !entry.active))
                continue;
            result[index] = .{ .blob = entry.blob.ptr, .len = entry.blob.len };
            index += 1;
        }
        return result;
    }
};

const OwnershipContext = struct {
    view: *TransactionView,
    config: *const anyopaque,
    ignored_hnums: []const u32 = &.{},
};

const PathAppendContext = struct {
    list: *PathList,
    source: [*]const u8,
    source_len: usize,
    ownership: ?*OwnershipContext = null,
};

const InstallPathContext = struct {
    paths: *PathList,
    source: [*]const u8,
    source_len: usize,
};

const PostunOwner = struct {
    blob: []const u8,
    order: u64,
    paths: PathList = .{},
};

const PostunQueue = struct {
    owners: std.ArrayListUnmanaged(PostunOwner) = .empty,

    fn deinit(self: *PostunQueue) void {
        for (self.owners.items) |*owner| owner.paths.deinit();
        self.owners.deinit(allocator);
        self.* = .{};
    }
};

extern fn TDNFAllocateMemory(usize, usize, *?*anyopaque) callconv(.c) u32;
extern fn TDNFAllocateString(?[*:0]const u8, *?[*:0]u8) callconv(.c) u32;
extern fn TDNFFreeMemory(?*anyopaque) callconv(.c) void;
extern fn TDNFFindRepoById(?*abi.Tdnf, ?[*:0]const u8, *?*abi.RepoData) callconv(.c) u32;
extern fn TDNFDownloadPackageToCache(
    ?*abi.Tdnf,
    ?[*:0]const u8,
    ?[*:0]const u8,
    ?*abi.RepoData,
    *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFDownloadPackageToDirectory(
    ?*abi.Tdnf,
    ?[*:0]const u8,
    ?[*:0]const u8,
    ?*abi.RepoData,
    ?[*:0]const u8,
    *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFGPGCheckPackageWithFile(
    ?*abi.Tdnf,
    ?*abi.RepoData,
    ?[*:0]const u8,
    ?*c.tdnf_rpm_file,
    ?*c_int,
) callconv(.c) u32;
extern fn TDNFUtilsMakeDirs(?[*:0]const u8) callconv(.c) u32;
extern fn TDNFJoinArrayToString(
    ?[*]?[*:0]u8,
    ?[*:0]const u8,
    c_int,
    *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFGetHistoryCtx(?*abi.Tdnf, *?*HistoryCtx, c_int) callconv(.c) u32;
extern fn TDNFMarkAutoInstalled(
    ?*abi.Tdnf,
    ?*HistoryCtx,
    ?*c.TDNF_SOLVED_PKG_INFO,
    c_int,
) callconv(.c) u32;
extern fn destroy_history_ctx(?*HistoryCtx) callconv(.c) void;
extern fn history_sync_config(?*HistoryCtx, ?*anyopaque) callconv(.c) c_int;
extern fn history_update_state_config(
    ?*HistoryCtx,
    ?*anyopaque,
    ?[*:0]const u8,
) callconv(.c) c_int;
extern fn history_get_current_transaction_id(?*HistoryCtx) callconv(.c) c_int;
extern fn history_add_transaction(?*HistoryCtx, ?[*:0]const u8) callconv(.c) c_int;
extern fn history_restore_auto_flags(?*HistoryCtx, c_int) callconv(.c) c_int;
extern fn history_replay_auto_flags(?*HistoryCtx, c_int, c_int) callconv(.c) c_int;
extern fn tdnf_repomd_native_verified_transaction_solve_config(
    ?[*]const c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2,
    ?[*]const ?[*]const u8,
    ?[*]const usize,
    ?[*]const u64,
    u32,
    ?*const anyopaque,
    *?*c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
) callconv(.c) u32;
extern fn access(?[*:0]const u8, c_int) callconv(.c) c_int;
extern fn unlink(?[*:0]const u8) callconv(.c) c_int;
extern fn strerror(c_int) callconv(.c) [*:0]const u8;
extern fn dup(c_int) callconv(.c) c_int;
extern fn close(c_int) callconv(.c) c_int;
extern fn time(?*std.c.time_t) callconv(.c) std.c.time_t;

fn isEmpty(value: ?[*:0]const u8) bool {
    return value == null or value.?[0] == 0;
}

fn free(value: anytype) void {
    TDNFFreeMemory(@ptrCast(value));
}

fn allocate(comptime T: type) ?*T {
    var raw: ?*anyopaque = null;
    if (TDNFAllocateMemory(1, @sizeOf(T), &raw) != 0) return null;
    return @ptrCast(@alignCast(raw.?));
}

fn duplicate(value: ?[*:0]const u8, output: *?[*:0]u8) u32 {
    if (isEmpty(value)) {
        output.* = null;
        return 0;
    }
    return TDNFAllocateString(value, output);
}

fn systemError() u32 {
    return 1600 + @as(u32, @intCast(std.c._errno().*));
}

fn clearPlan(ts: *c.TDNFRPMTS) void {
    c.TDNFRepoMdNativeTransactionPlanFree(ts.pNativePlan);
    ts.pNativePlan = null;
}

fn freeItems(ts: *c.TDNFRPMTS) void {
    var item = ts.pTransactionItems;
    while (item) |current| {
        const current_ptr: *c.TDNF_RPM_TS_ITEM = @ptrCast(current);
        item = current_ptr.pNext;
        c.tdnf_rpm_file_close(current_ptr.pRpmFile);
        free(current_ptr.pszPath);
        free(current_ptr.pszName);
        free(current_ptr.pszEVR);
        free(current_ptr.pszArch);
        free(current_ptr);
    }
    ts.pTransactionItems = null;
    ts.pTransactionItemsTail = null;
    ts.dwTransactionItemCount = 0;
}

fn freeCached(list_opt: ?*c.TDNF_CACHED_RPM_LIST) void {
    const list = list_opt orelse return;
    var entry = list.pHead;
    while (entry) |current| {
        const current_ptr: *c.TDNF_CACHED_RPM_ENTRY = @ptrCast(current);
        entry = current_ptr.pNext;
        free(current_ptr.pszFilePath);
        free(current_ptr);
    }
    free(list);
}

fn removeCached(list: *c.TDNF_CACHED_RPM_LIST) u32 {
    var entry = list.pHead;
    while (entry) |current| : (entry = @as(*c.TDNF_CACHED_RPM_ENTRY, @ptrCast(current)).pNext) {
        const current_ptr: *c.TDNF_CACHED_RPM_ENTRY = @ptrCast(current);
        if (!isEmpty(current_ptr.pszFilePath) and unlink(current_ptr.pszFilePath) != 0)
            return systemError();
    }
    return 0;
}

fn cleanupTransaction(tdnf: *abi.Tdnf, ts: *c.TDNFRPMTS) void {
    const conf = tdnf.pConf.?;
    const args = tdnf.pArgs.?;
    if (ts.pCachedRpmsArray) |cached| {
        if (conf.nKeepCache == 0 and args.nDownloadOnly == 0)
            _ = removeCached(cached);
        freeCached(cached);
    }
    clearPlan(ts);
    freeItems(ts);
    free(ts);
}

fn recordItem(
    ts: *c.TDNFRPMTS,
    kind: c_uint,
    package_kind: c_int,
    rpm_file: ?*?*c.tdnf_rpm_file,
    path: ?[*:0]const u8,
    hnum: u32,
    name: ?[*:0]const u8,
    evr: ?[*:0]const u8,
    arch: ?[*:0]const u8,
) u32 {
    if ((kind != item_erase and
        (rpm_file == null or rpm_file.?.* == null or package_kind != package_binary)) or
        (kind == item_erase and hnum == 0))
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    if (kind == item_erase) {
        var existing = ts.pTransactionItems;
        while (existing) |item| : (existing = @as(*c.TDNF_RPM_TS_ITEM, @ptrCast(item)).pNext) {
            const item_ptr: *c.TDNF_RPM_TS_ITEM = @ptrCast(item);
            if (item_ptr.nType == item_erase and item_ptr.dwRpmDbHnum == hnum)
                return 0;
        }
    }

    const item = allocate(c.TDNF_RPM_TS_ITEM) orelse
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    var committed = false;
    defer {
        if (!committed) {
            free(item.pszPath);
            free(item.pszName);
            free(item.pszEVR);
            free(item.pszArch);
            free(item);
        }
    }
    item.nType = kind;
    item.nPackageKind = package_kind;
    item.dwRpmDbHnum = hnum;
    var rc = duplicate(path, &item.pszPath);
    if (rc != 0) return rc;
    rc = duplicate(name, &item.pszName);
    if (rc != 0) return rc;
    rc = duplicate(evr, &item.pszEVR);
    if (rc != 0) return rc;
    rc = duplicate(arch, &item.pszArch);
    if (rc != 0) return rc;
    if (rpm_file) |slot| {
        item.pRpmFile = slot.*;
        slot.* = null;
    }
    if (ts.pTransactionItemsTail) |tail|
        @as(*c.TDNF_RPM_TS_ITEM, @ptrCast(tail)).pNext = item
    else
        ts.pTransactionItems = item;
    ts.pTransactionItemsTail = item;
    ts.dwTransactionItemCount += 1;
    committed = true;
    return 0;
}

fn fixedItemPackage(item: FixedOrderItem) ?FixedOrderLocalRpm {
    return switch (item) {
        .install => |package| package,
        .erase => null,
        .upgrade, .downgrade, .reinstall, .obsolete => |replacement| replacement.package,
    };
}

fn fixedItemPriors(item: FixedOrderItem) []const FixedOrderRpmDbRow {
    return switch (item) {
        .install, .erase => &.{},
        .upgrade, .downgrade, .reinstall, .obsolete => |replacement| replacement.priors,
    };
}

fn fixedItemSharesPriors(item: FixedOrderItem) bool {
    return item == .obsolete;
}

fn fixedReplacementPrimaryIndex(item: FixedOrderItem) ?usize {
    const replacement = switch (item) {
        .upgrade, .downgrade, .reinstall => |value| value,
        else => return null,
    };
    var result: ?usize = null;
    for (replacement.priors, 0..) |prior, index| {
        if (!std.mem.eql(
            u8,
            replacement.package.identity.name,
            prior.identity.name,
        )) continue;
        if (result != null) return null;
        result = index;
    }
    return result;
}

fn copyFixedPriorsInExecutionOrder(
    item: FixedOrderItem,
    destination: []FixedOrderRpmDbRow,
) FixedOrderExecutionError!void {
    const priors = fixedItemPriors(item);
    if (destination.len != priors.len) return error.InvalidItem;
    const primary = fixedReplacementPrimaryIndex(item);
    switch (item) {
        .upgrade, .downgrade, .reinstall => if (primary == null)
            return error.InvalidItem,
        else => {},
    }
    if (primary == null) {
        @memcpy(destination, priors);
        return;
    }
    destination[0] = priors[primary.?];
    var output_index: usize = 1;
    for (priors, 0..) |prior, index| {
        if (index == primary.?) continue;
        destination[output_index] = prior;
        output_index += 1;
    }
}

fn fixedItemType(item: FixedOrderItem) c_uint {
    return switch (item) {
        .install => item_install,
        .erase => item_erase,
        .upgrade => item_upgrade,
        .downgrade => item_downgrade,
        .reinstall => item_reinstall,
        .obsolete => item_obsolete,
    };
}

fn validateFixedOrderInput(
    transaction: FixedOrderTransaction,
) FixedOrderExecutionError!void {
    if (transaction.items.len != transaction.order.len or
        transaction.items.len > std.math.maxInt(u32))
        return error.MalformedOrder;

    const seen = allocator.alloc(bool, transaction.items.len) catch
        return error.OutOfMemory;
    defer allocator.free(seen);
    @memset(seen, false);
    for (transaction.order) |index_u32| {
        const index: usize = index_u32;
        if (index >= transaction.items.len or seen[index])
            return error.MalformedOrder;
        seen[index] = true;
    }

    for (transaction.items, 0..) |item, item_index| {
        const priors = fixedItemPriors(item);
        switch (item) {
            .install => {},
            .erase => |row| if (row.hnum == 0) return error.InvalidItem,
            .upgrade, .downgrade, .reinstall => {
                if (priors.len == 0 or fixedReplacementPrimaryIndex(item) == null)
                    return error.InvalidItem;
            },
            .obsolete => if (priors.len == 0) return error.InvalidItem,
        }
        if (fixedItemPackage(item)) |package| {
            if (package.path.len == 0 or package.path[0] != '/')
                return error.InvalidItem;
        }
        for (priors, 0..) |prior, prior_index| {
            if (prior.hnum == 0) return error.InvalidItem;
            for (priors[0..prior_index]) |earlier| {
                if (earlier.hnum == prior.hnum) return error.InvalidItem;
            }
        }

        const erase_hnum = switch (item) {
            .erase => |row| row.hnum,
            else => 0,
        };
        for (transaction.items[0..item_index]) |earlier_item| {
            const earlier_erase = switch (earlier_item) {
                .erase => |row| row.hnum,
                else => 0,
            };
            if (erase_hnum != 0 and erase_hnum == earlier_erase)
                return error.InvalidItem;
            if (earlier_erase != 0 and priorListContains(priors, earlier_erase))
                return error.InvalidItem;
            for (fixedItemPriors(earlier_item)) |earlier_prior| {
                if (erase_hnum != 0 and erase_hnum == earlier_prior.hnum)
                    return error.InvalidItem;
                for (priors) |prior| {
                    if (prior.hnum == earlier_prior.hnum and
                        !(fixedItemSharesPriors(item) and
                            fixedItemSharesPriors(earlier_item)))
                        return error.InvalidItem;
                }
            }
        }
    }
}

fn priorListContains(priors: []const FixedOrderRpmDbRow, hnum: u32) bool {
    for (priors) |prior| if (prior.hnum == hnum) return true;
    return false;
}

fn identityMatchesMetadata(
    expected: FixedOrderPackageIdentity,
    metadata: c.tdnf_rpm_file_metadata,
) bool {
    const name = metadata.name orelse return false;
    const version = metadata.version orelse return false;
    const release = metadata.release orelse return false;
    const arch = metadata.arch orelse return false;
    const epoch: ?u32 = if (metadata.has_epoch != 0) metadata.epoch else null;
    return std.mem.eql(u8, expected.name, std.mem.span(name)) and
        expected.epoch == epoch and
        std.mem.eql(u8, expected.version, std.mem.span(version)) and
        std.mem.eql(u8, expected.release, std.mem.span(release)) and
        std.mem.eql(u8, expected.arch, std.mem.span(arch));
}

fn identityMatchesHeader(
    expected: FixedOrderPackageIdentity,
    blob: []const u8,
) bool {
    const header = rpm_header.Header.parseProbe(blob) catch return false;
    const name = (header.getStringChecked(.name) catch return false) orelse return false;
    const version = (header.getStringChecked(.version) catch return false) orelse return false;
    const release = (header.getStringChecked(.release) catch return false) orelse return false;
    const arch = (header.getStringChecked(.arch) catch return false) orelse return false;
    const epoch = header.getU32Checked(.epoch) catch return false;
    return std.mem.eql(u8, expected.name, name) and
        expected.epoch == epoch and
        std.mem.eql(u8, expected.version, version) and
        std.mem.eql(u8, expected.release, release) and
        std.mem.eql(u8, expected.arch, arch);
}

fn digestLength(kind: c_int) ?usize {
    return switch (kind) {
        0 => 16,
        1 => 20,
        2 => 32,
        3 => 64,
        else => null,
    };
}

fn addInstallPackage(
    ts: *c.TDNFRPMTS,
    tdnf: *abi.Tdnf,
    info: *c.TDNF_PKG_INFO,
    repo: *abi.RepoData,
    install_flag: c_int,
) u32 {
    const args = tdnf.pArgs.?;
    const conf = tdnf.pConf.?;
    const location = info.pszLocation orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const package_name = info.pszName orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var path: ?[*:0]u8 = null;
    var rpm_file: ?*c.tdnf_rpm_file = null;
    var cache_entry: ?*c.TDNF_CACHED_RPM_ENTRY = null;
    var header_evr: ?[*:0]u8 = null;
    defer {
        c.tdnf_rpm_file_close(rpm_file);
        free(header_evr);
        free(path);
        if (cache_entry) |entry| free(entry);
    }
    var rc: u32 = 0;
    if (location[0] == '/') {
        rc = TDNFAllocateString(location, &path);
        if (rc != 0) return rc;
    } else if (args.nDownloadOnly == 0 or args.pszDownloadDir == null) {
        var in_place = false;
        const location_span = std.mem.span(location);
        if (std.ascii.startsWithIgnoreCase(location_span, "file://")) {
            rc = TDNFAllocateString(location + 7, &path);
            if (rc != 0) return rc;
            if (access(path, F_OK) == 0) in_place = true else {
                free(path);
                path = null;
            }
        }
        if (!in_place and repo.ppszBaseUrls != null) {
            var i: usize = 0;
            while (repo.ppszBaseUrls.?[i]) |base| : (i += 1) {
                if (!std.ascii.startsWithIgnoreCase(std.mem.span(base), "file://"))
                    continue;
                rc = common.joinPath(&path, &.{ base + 7, location });
                if (rc != 0) return rc;
                if (access(path, F_OK) == 0) {
                    in_place = true;
                    break;
                }
                free(path);
                path = null;
            }
        }
        if (!in_place) {
            rc = TDNFDownloadPackageToCache(tdnf, location, package_name, repo, &path);
            if (rc != 0) return rc;
        }
    } else {
        rc = TDNFDownloadPackageToDirectory(
            tdnf,
            location,
            package_name,
            repo,
            args.pszDownloadDir,
            &path,
        );
        if (rc != 0) return rc;
    }

    if (path == null or access(path, F_OK) != 0) {
        const errno_value = std.c._errno().*;
        common.log(LOG_ERR, "could not access file %s: %s (%d)\n", .{ path orelse "(null)", strerror(errno_value), errno_value });
        return systemError();
    }
    rpm_file = c.tdnf_rpm_file_open(path);
    if (rpm_file == null) {
        common.log(LOG_ERR, "Unable to parse package %s: %s\n", .{ path.?, c.tdnf_rpmdb_last_error() });
        return ERROR_TDNF_RPMRC_NOTFOUND;
    }

    if (info.pbChecksum != null) {
        const len = digestLength(info.nChecksumType) orelse
            return ERROR_TDNF_CHECKSUM_MISMATCH;
        var digest = [_]u8{0} ** 64;
        if (c.tdnf_rpm_file_digest(
            rpm_file,
            info.nChecksumType,
            &digest,
            digest.len,
        ) != 0) return ERROR_TDNF_RPM_CHECK;
        if (!std.mem.eql(u8, digest[0..len], info.pbChecksum[0..len])) {
            common.log(LOG_ERR, "rpm file (%s) Checksum FAILED (digest mismatch)\n", .{path.?});
            return ERROR_TDNF_CHECKSUM_MISMATCH;
        }
    }

    var bytes: [*c]const u8 = null;
    var byte_len: usize = 0;
    if (c.tdnf_rpm_file_bytes(rpm_file, &bytes, &byte_len) != 0)
        return ERROR_TDNF_RPM_CHECK;
    if (byte_len != info.dwDownloadSizeBytes) {
        common.log(LOG_ERR, "rpm file (%s) size (%zu) does not match expected size (%u)\n", .{ path.?, byte_len, info.dwDownloadSizeBytes });
        return ERROR_TDNF_SIZE_MISMATCH;
    }
    rc = TDNFGPGCheckPackageWithFile(tdnf, repo, path, rpm_file, null);
    if (rc != 0) return rc;

    var metadata = std.mem.zeroes(c.tdnf_rpm_file_metadata);
    if (c.tdnf_rpm_file_get_metadata(rpm_file, &metadata) != 0 or
        metadata.main_header_blob == null or metadata.main_header_blob_len == 0)
        return ERROR_TDNF_RPM_CHECK;
    if (metadata.has_epoch != 0) {
        rc = common.allocPrint(&header_evr, "%u:%s-%s", .{ metadata.epoch, metadata.version, metadata.release });
    } else {
        rc = common.allocPrint(&header_evr, "%s-%s", .{ metadata.version, metadata.release });
    }
    if (rc != 0) return rc;
    if (isEmpty(metadata.name) or isEmpty(header_evr) or isEmpty(metadata.arch))
        return ERROR_TDNF_RPM_CHECK;
    if (metadata.package_kind != package_binary and
        metadata.package_kind != package_source and
        metadata.package_kind != package_nosrc)
        return ERROR_TDNF_RPM_CHECK;

    if (ts.pCachedRpmsArray != null and conf.pszCacheDir != null and
        std.mem.startsWith(u8, std.mem.span(path.?), std.mem.span(conf.pszCacheDir.?)))
    {
        cache_entry = allocate(c.TDNF_CACHED_RPM_ENTRY) orelse
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        cache_entry.?.pszFilePath = path;
    }

    if (metadata.package_kind != package_binary) {
        if (args.nDownloadOnly == 0 and args.nTestOnly == 0 and
            c.tdnf_rpm_file_extract_source_config(
                rpm_file,
                @ptrCast(tdnf.pRpmConfig),
                ts.nTransFlags,
            ) != 0)
            return ERROR_TDNF_RPM_CHECK;
    } else {
        rc = recordItem(
            ts,
            if (install_flag == install_reinstall) item_reinstall else if (install_flag == install_upgrade) item_upgrade else item_install,
            metadata.package_kind,
            &rpm_file,
            path,
            0,
            metadata.name,
            header_evr,
            metadata.arch,
        );
        if (rc != 0) return rc;
    }
    if (cache_entry) |entry| {
        const cached: *c.TDNF_CACHED_RPM_LIST = @ptrCast(ts.pCachedRpmsArray);
        entry.pNext = cached.pHead;
        cached.pHead = entry;
        cache_entry = null;
        path = null;
    }
    return 0;
}

fn addInstallPackages(
    ts: *c.TDNFRPMTS,
    tdnf: *abi.Tdnf,
    first: ?*c.TDNF_PKG_INFO,
    install_flag: c_int,
) u32 {
    var info = first orelse return 0;
    while (true) {
        var repo: ?*abi.RepoData = null;
        var rc = TDNFFindRepoById(tdnf, info.pszRepoName, &repo);
        if (rc != 0) return rc;
        rc = addInstallPackage(ts, tdnf, info, repo.?, install_flag);
        if (rc != 0) return rc;
        info = info.pNext orelse break;
    }
    return 0;
}

fn addErasePackage(
    ts: *c.TDNFRPMTS,
    tdnf: *abi.Tdnf,
    info: *c.TDNF_PKG_INFO,
) u32 {
    if (tdnf.pRpmConfig == null or isEmpty(info.pszName) or isEmpty(info.pszEVR))
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    var matches: [*c]c.tdnf_rpmdb_label_match = null;
    var count: usize = 0;
    if (c.tdnf_rpmdb_find_label_matches_config(
        @ptrCast(tdnf.pRpmConfig),
        info.pszName,
        info.pszEVR,
        &matches,
        &count,
    ) != 0) return ERROR_TDNF_RPM_CHECK;
    defer c.tdnf_rpmdb_label_matches_free(matches, count);
    for (matches[0..count]) |match| {
        if (!isEmpty(info.pszArch) and
            (isEmpty(match.arch) or !std.mem.eql(
                u8,
                std.mem.span(info.pszArch.?),
                std.mem.span(match.arch),
            ))) continue;
        const rc = recordItem(
            ts,
            item_erase,
            package_binary,
            null,
            null,
            match.hnum,
            match.name,
            match.evr,
            match.arch,
        );
        if (rc != 0) return rc;
    }
    return 0;
}

fn addErasePackages(
    ts: *c.TDNFRPMTS,
    tdnf: *abi.Tdnf,
    first: ?*c.TDNF_PKG_INFO,
) u32 {
    var info = first orelse return 0;
    while (true) {
        const rc = addErasePackage(ts, tdnf, info);
        if (rc != 0) return rc;
        info = info.pNext orelse break;
    }
    return 0;
}

fn populate(
    ts: *c.TDNFRPMTS,
    tdnf: *abi.Tdnf,
    solved: *c.TDNF_SOLVED_PKG_INFO,
) u32 {
    var rc = addInstallPackages(ts, tdnf, solved.pPkgsToInstall, install_install);
    if (rc != 0) return rc;
    rc = addInstallPackages(ts, tdnf, solved.pPkgsToReinstall, install_reinstall);
    if (rc != 0) return rc;
    rc = addInstallPackages(ts, tdnf, solved.pPkgsToUpgrade, install_upgrade);
    if (rc != 0) return rc;
    rc = addErasePackages(ts, tdnf, solved.pPkgsToRemove);
    if (rc != 0) return rc;
    rc = addErasePackages(ts, tdnf, solved.pPkgsObsoleted);
    if (rc != 0) return rc;
    rc = addInstallPackages(ts, tdnf, solved.pPkgsToDowngrade, install_install);
    if (rc != 0) return rc;
    return addErasePackages(ts, tdnf, solved.pPkgsRemovedByDowngrade);
}

fn createTransaction(
    tdnf: *abi.Tdnf,
    solved: *c.TDNF_SOLVED_PKG_INFO,
) struct { u32, ?*c.TDNFRPMTS } {
    if (tdnf.pArgs == null or tdnf.pConf == null)
        return .{ errors.ERROR_TDNF_INVALID_PARAMETER, null };
    const ts = allocate(c.TDNFRPMTS) orelse
        return .{ errors.ERROR_TDNF_OUT_OF_MEMORY, null };
    ts.nQuiet = tdnf.pArgs.?.nQuiet;
    ts.nTransFlags = tdnf.pConf.?.rpmTransFlags;
    ts.pCachedRpmsArray = allocate(c.TDNF_CACHED_RPM_LIST) orelse {
        free(ts);
        return .{ errors.ERROR_TDNF_OUT_OF_MEMORY, null };
    };
    const rc = populate(ts, tdnf, solved);
    if (rc != 0) {
        cleanupTransaction(tdnf, ts);
        return .{ rc, null };
    }
    return .{ 0, ts };
}

fn fixedEvrAlloc(
    identity: FixedOrderPackageIdentity,
) FixedOrderExecutionError![:0]u8 {
    return if (identity.epoch) |epoch|
        std.fmt.allocPrintSentinel(
            allocator,
            "{d}:{s}-{s}",
            .{ epoch, identity.version, identity.release },
            0,
        ) catch error.OutOfMemory
    else
        std.fmt.allocPrintSentinel(
            allocator,
            "{s}-{s}",
            .{ identity.version, identity.release },
            0,
        ) catch error.OutOfMemory;
}

fn mapFixedRecordError(rc: u32) FixedOrderExecutionError {
    return switch (rc) {
        errors.ERROR_TDNF_OUT_OF_MEMORY => error.OutOfMemory,
        errors.ERROR_TDNF_INVALID_PARAMETER => error.InvalidItem,
        else => error.ExecutionFailed,
    };
}

fn mapFixedExecutionError(
    rc: u32,
    validation_failure: FixedOrderValidationFailure,
) FixedOrderExecutionError {
    return switch (validation_failure) {
        .malformed_order => error.MalformedOrder,
        .invalid_item => error.InvalidItem,
        .prior_mismatch => error.PriorMismatch,
        .none => switch (rc) {
            errors.ERROR_TDNF_OUT_OF_MEMORY => error.OutOfMemory,
            ERROR_TDNF_RPM_CHECK => error.RpmCheckFailed,
            ERROR_TDNF_TRANSACTION_FAILED => error.TransactionFailed,
            errors.ERROR_TDNF_INVALID_PARAMETER => error.InvalidItem,
            else => error.ExecutionFailed,
        },
    };
}

/// Execute an already preflighted local transaction in its recorded order.
/// Ownership of the caller's paths, identities, and order remains with the
/// caller. RPM handles opened here are always closed before return.
pub fn executeFixedOrder(
    tdnf: *abi.Tdnf,
    transaction: FixedOrderTransaction,
) FixedOrderExecutionError!void {
    if (tdnf.pArgs == null or tdnf.pConf == null or tdnf.pRpmConfig == null)
        return error.InvalidContext;
    try validateFixedOrderInput(transaction);
    if (transaction.items.len == 0) return;

    var prior_count: usize = 0;
    for (transaction.items) |item| {
        prior_count = std.math.add(
            usize,
            prior_count,
            fixedItemPriors(item).len,
        ) catch return error.OutOfMemory;
    }
    if (prior_count > std.math.maxInt(u32)) return error.InvalidItem;

    const order = allocator.dupe(u32, transaction.order) catch
        return error.OutOfMemory;
    defer allocator.free(order);
    const plan_items = allocator.alloc(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM,
        transaction.items.len,
    ) catch return error.OutOfMemory;
    defer allocator.free(plan_items);
    const prior_hnums = allocator.alloc(u32, prior_count) catch
        return error.OutOfMemory;
    defer allocator.free(prior_hnums);
    const ordered_priors = allocator.alloc(FixedOrderRpmDbRow, prior_count) catch
        return error.OutOfMemory;
    defer allocator.free(ordered_priors);
    const expected_items = allocator.alloc(
        FixedOrderExpectedItem,
        transaction.items.len,
    ) catch return error.OutOfMemory;
    defer allocator.free(expected_items);

    var prior_offset: usize = 0;
    for (transaction.items, plan_items, expected_items) |item, *planned, *expected| {
        const priors = fixedItemPriors(item);
        const ordered = ordered_priors[prior_offset..][0..priors.len];
        try copyFixedPriorsInExecutionOrder(item, ordered);
        planned.* = .{
            .dwPriorOffset = @intCast(prior_offset),
            .dwPriorCount = @intCast(priors.len),
        };
        expected.* = .{
            .erase = switch (item) {
                .erase => |row| row,
                else => null,
            },
            .priors = ordered,
        };
        for (ordered) |prior| {
            prior_hnums[prior_offset] = prior.hnum;
            prior_offset += 1;
        }
    }

    const ts = allocate(c.TDNFRPMTS) orelse return error.OutOfMemory;
    defer {
        freeItems(ts);
        free(ts);
    }
    ts.nQuiet = tdnf.pArgs.?.nQuiet;
    ts.nTransFlags = tdnf.pConf.?.rpmTransFlags;

    for (transaction.items) |item| {
        if (item == .erase) {
            const row = item.erase;
            const name = allocator.dupeZ(u8, row.identity.name) catch
                return error.OutOfMemory;
            defer allocator.free(name);
            const evr = try fixedEvrAlloc(row.identity);
            defer allocator.free(evr);
            const arch = allocator.dupeZ(u8, row.identity.arch) catch
                return error.OutOfMemory;
            defer allocator.free(arch);
            const rc = recordItem(
                ts,
                item_erase,
                package_binary,
                null,
                null,
                row.hnum,
                name.ptr,
                evr.ptr,
                arch.ptr,
            );
            if (rc != 0) return mapFixedRecordError(rc);
            continue;
        }

        const package = fixedItemPackage(item).?;
        var rpm_file: ?*c.tdnf_rpm_file =
            c.tdnf_rpm_file_open(package.path.ptr) orelse
            return error.PackageOpenFailed;
        var transferred = false;
        defer if (!transferred) c.tdnf_rpm_file_close(rpm_file);
        var metadata = std.mem.zeroes(c.tdnf_rpm_file_metadata);
        if (c.tdnf_rpm_file_get_metadata(rpm_file, &metadata) != 0 or
            metadata.package_kind != package_binary)
            return error.PackageOpenFailed;
        if (!identityMatchesMetadata(package.identity, metadata))
            return error.PackageIdentityMismatch;
        const evr = try fixedEvrAlloc(package.identity);
        defer allocator.free(evr);
        const rc = recordItem(
            ts,
            fixedItemType(item),
            package_binary,
            &rpm_file,
            package.path.ptr,
            0,
            metadata.name,
            evr.ptr,
            metadata.arch,
        );
        if (rc != 0) return mapFixedRecordError(rc);
        transferred = true;
    }

    var plan = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN);
    plan.dwItemCount = @intCast(transaction.items.len);
    plan.pdwOrderIndices = order.ptr;
    plan.pItems = plan_items.ptr;
    plan.dwPriorHnumCount = @intCast(prior_count);
    if (prior_count != 0) plan.pdwPriorHnums = prior_hnums.ptr;
    var validation_failure: FixedOrderValidationFailure = .none;
    const rc = runTransactionNativeImpl(
        ts,
        tdnf,
        &plan,
        expected_items,
        &validation_failure,
    );
    if (rc != 0) return mapFixedExecutionError(rc, validation_failure);
}

fn reportProblems(ts: *c.TDNFRPMTS) void {
    const plan = ts.pNativePlan orelse return;
    const plan_ptr: *c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = @ptrCast(plan);
    if (plan_ptr.dwProblemCount == 0 or plan_ptr.pProblems == null) return;
    common.log(LOG_CRIT, "Found %u problems\n", .{plan_ptr.dwProblemCount});
    for (plan_ptr.pProblems[0..plan_ptr.dwProblemCount]) |problem| {
        const package: [*c]const u8 = if (problem.pszPackage != null)
            problem.pszPackage
        else
            "(unknown)";
        const related: [*c]const u8 = if (problem.pszRelatedPackage != null)
            problem.pszRelatedPackage
        else
            "(unknown)";
        const subject: [*c]const u8 = if (problem.pszSubject != null)
            problem.pszSubject
        else
            "(unknown)";
        switch (problem.nType) {
            1, 2 => common.log(LOG_CRIT, "nothing provides %s needed by %s\n", .{ subject, package }),
            3 => common.log(LOG_CRIT, "package %s conflicts with %s\n", .{ package, related }),
            4 => common.log(LOG_CRIT, "package %s obsoletes %s\n", .{ package, related }),
            5 => common.log(LOG_CRIT, "file %s from install of %s conflicts with file from package %s\n", .{ subject, package, related }),
            6 => common.log(LOG_CRIT, "package %s has %u installed %s instances selected for one upgrade; remove extra instances or configure the package as installonly\n", .{ package, problem.dwCount, subject }),
            else => common.log(LOG_CRIT, "unknown native transaction problem for %s\n", .{package}),
        }
    }
}

fn logRpmzigError(action: [*:0]const u8) void {
    const detail = c.tdnf_rpmdb_last_error();
    if (!isEmpty(detail))
        common.log(LOG_ERR, "rpmzig-transaction-execute: %s failed: %s\n", .{ action, detail })
    else
        common.log(LOG_ERR, "rpmzig-transaction-execute: %s failed\n", .{action});
}

fn ownershipIgnores(context: *const OwnershipContext, hnum: u32) bool {
    for (context.ignored_hnums) |ignored| if (ignored == hnum) return true;
    return false;
}

fn nativePathOwned(
    data: ?*anyopaque,
    path: [*c]const u8,
) callconv(.c) c_int {
    const context: *OwnershipContext = @ptrCast(@alignCast(data orelse return -1));
    if (path == null) return -1;
    for (context.view.entries.items) |entry| {
        if (!entry.active or ownershipIgnores(context, entry.hnum)) continue;
        const result = c.tdnf_rpm_header_owns_path_config(
            entry.blob.ptr,
            entry.blob.len,
            path,
            @ptrCast(context.config),
        );
        if (result != 0) return result;
    }
    return 0;
}

fn appendTriggerPath(
    data: ?*anyopaque,
    path: [*c]const u8,
) callconv(.c) c_int {
    const context: *PathAppendContext = @ptrCast(@alignCast(data orelse return -1));
    if (context.ownership) |ownership| {
        const owned = nativePathOwned(ownership, path);
        if (owned < 0) return -1;
        if (owned > 0) return 0;
    }
    return if (context.list.append(
        @ptrCast(path),
        context.source,
        context.source_len,
    ) == 0) 0 else -1;
}

fn appendInstalledPath(
    data: ?*anyopaque,
    path: [*c]const u8,
) callconv(.c) c_int {
    const context: *InstallPathContext = @ptrCast(@alignCast(data orelse return -1));
    return if (context.paths.append(
        @ptrCast(path),
        context.source,
        context.source_len,
    ) == 0) 0 else -1;
}

fn collectHeaderTriggerPaths(
    blob: []const u8,
    flags: u32,
    ownership: ?*OwnershipContext,
    paths: *PathList,
) u32 {
    if (blob.len == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var context = PathAppendContext{
        .list = paths,
        .source = blob.ptr,
        .source_len = blob.len,
        .ownership = ownership,
    };
    if (c.tdnf_rpm_header_foreach_trigger_file(
        blob.ptr,
        blob.len,
        flags,
        appendTriggerPath,
        &context,
    ) != 0) {
        logRpmzigError("foreach_trigger_file");
        return ERROR_TDNF_TRANSACTION_FAILED;
    }
    return 0;
}

fn collectAllDbTriggerPaths(
    view: *TransactionView,
    flags: u32,
    paths: *PathList,
) u32 {
    for (view.entries.items) |entry| {
        if (!entry.db_visible) continue;
        const rc = collectHeaderTriggerPaths(
            entry.blob,
            if (entry.added) flags else 0,
            null,
            paths,
        );
        if (rc != 0) return rc;
    }
    return 0;
}

fn schedulePostun(
    queue: *PostunQueue,
    view: *TransactionView,
    removed_paths: *const PathList,
) u32 {
    if (removed_paths.entries.items.len == 0) return 0;
    for (view.entries.items) |entry| {
        if (!entry.db_visible) continue;
        var owner: ?*PostunOwner = null;
        for (queue.owners.items) |*candidate| {
            if (candidate.blob.ptr == entry.blob.ptr) {
                owner = candidate;
                break;
            }
        }
        if (owner == null) {
            queue.owners.append(allocator, .{
                .blob = entry.blob,
                .order = entry.order,
            }) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
            owner = &queue.owners.items[queue.owners.items.len - 1];
        }
        const rc = owner.?.paths.merge(removed_paths);
        if (rc != 0) return rc;
    }
    return 0;
}

fn effectiveFlags(ts: *c.TDNFRPMTS, tdnf: *abi.Tdnf) u32 {
    var result = ts.nTransFlags;
    if (tdnf.pArgs.?.nTestOnly != 0) {
        result |= trans_flags.TDNF_RPMTRANS_FLAG_TEST |
            trans_flags.TDNF_RPMTRANS_FLAG_NOSCRIPTS |
            trans_flags.TDNF_RPMTRANS_FLAG_NOTRIGGERS |
            trans_flags.TDNF_RPMTRANS_FLAG_JUSTDB |
            trans_flags.TDNF_RPMTRANS_FLAG_NODB;
    }
    return result;
}

fn logScriptletOutcome(
    nevra: ?[*:0]const u8,
    phase: [*:0]const u8,
    result: *const c.tdnf_rpm_scriptlet_result,
) void {
    if (result.ran == 0 or
        result.outcome == c.TDNF_RPM_SCRIPTLET_OUTCOME_OK) return;
    const package = nevra orelse "(unknown)";
    if (result.outcome == c.TDNF_RPM_SCRIPTLET_OUTCOME_SIGNALED) {
        common.log(LOG_CRIT, "package %s: script %s in %s (signal %d)\n", .{ package, if (result.critical != 0)
            @as([*:0]const u8, "error")
        else
            @as([*:0]const u8, "warning"), phase, result.signal_number });
    } else {
        common.log(LOG_CRIT, "package %s: script %s in %s (exit %d)\n", .{ package, if (result.critical != 0)
            @as([*:0]const u8, "error")
        else
            @as([*:0]const u8, "warning"), phase, result.exit_status });
    }
}

fn runScriptlet(
    blob: []const u8,
    phase: c_uint,
    phase_name: [*:0]const u8,
    nevra: ?[*:0]const u8,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    arg1: c_int,
    arg2: c_int,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    var options = std.mem.zeroes(c.tdnf_rpm_scriptlet_options);
    var result = std.mem.zeroes(c.tdnf_rpm_scriptlet_result);
    const root_fd = c.tdnf_rpm_config_open_root_fd(@ptrCast(config));
    if (root_fd < 0) {
        logRpmzigError("pin scriptlet installroot");
        return ERROR_TDNF_TRANSACTION_FAILED;
    }
    defer _ = std.c.close(root_fd);
    options.install_root = install_root;
    options.config = @ptrCast(config);
    options.install_root_fd = root_fd;
    options.trans_flags = flags;
    options.arg1 = arg1;
    options.arg2 = arg2;
    options.script_fd = script_fd;
    options.redirect_stdout_to_stderr = redirect;
    if (c.tdnf_rpm_header_run_scriptlet(
        blob.ptr,
        blob.len,
        phase,
        &options,
        &result,
    ) != 0) {
        logRpmzigError(phase_name);
        return ERROR_TDNF_TRANSACTION_FAILED;
    }
    logScriptletOutcome(nevra, phase_name, &result);
    if (result.ran != 0 and result.critical != 0 and
        result.outcome != c.TDNF_RPM_SCRIPTLET_OUTCOME_OK and
        result.outcome != c.TDNF_RPM_SCRIPTLET_OUTCOME_NOT_RUN)
        return ERROR_TDNF_TRANSACTION_FAILED;
    return 0;
}

fn runTriggers(
    blob: []const u8,
    phase: c_uint,
    phase_name: [*:0]const u8,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    view: *TransactionView,
    script_fd: c_int,
    redirect: c_int,
    arg2_override: ?c_int,
) u32 {
    var options = std.mem.zeroes(c.tdnf_rpm_trigger_options);
    var result = std.mem.zeroes(c.tdnf_rpm_trigger_result);
    const root_fd = c.tdnf_rpm_config_open_root_fd(@ptrCast(config));
    if (root_fd < 0) return ERROR_TDNF_TRANSACTION_FAILED;
    defer _ = std.c.close(root_fd);
    const headers = view.headers(false) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(headers);
    const owner_headers = view.headers(true) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(owner_headers);
    options.db_root = install_root;
    options.install_root = install_root;
    options.config = @ptrCast(config);
    options.install_root_fd = root_fd;
    options.trans_flags = flags;
    options.script_fd = script_fd;
    options.redirect_stdout_to_stderr = redirect;
    options.transaction_headers = headers.ptr;
    options.transaction_header_count = headers.len;
    options.transaction_view_present = 1;
    options.trigger_owner_headers = owner_headers.ptr;
    options.trigger_owner_header_count = owner_headers.len;
    options.trigger_owner_view_present = 1;
    if (arg2_override) |value| {
        options.arg2_override_present = 1;
        options.arg2_override_value = value;
    }
    if (c.tdnf_rpm_header_run_triggers(
        blob.ptr,
        blob.len,
        phase,
        &options,
        &result,
    ) != 0) {
        logRpmzigError(phase_name);
        return ERROR_TDNF_TRANSACTION_FAILED;
    }
    return 0;
}

fn runFileTriggerOwners(
    owners: []c.tdnf_rpm_file_trigger_owner,
    phase: c_uint,
    kind: c_uint,
    priority: c_uint,
    phase_name: [*:0]const u8,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    script_fd: c_int,
    redirect: c_int,
    suppress_stdin: c_int,
) u32 {
    var output_count: usize = 0;
    for (owners) |owner| {
        const has = c.tdnf_rpm_header_has_file_trigger_metadata(
            owner.header_blob,
            owner.header_len,
            kind,
        );
        if (has < 0) {
            logRpmzigError("inspect file trigger owner");
            return ERROR_TDNF_TRANSACTION_FAILED;
        }
        if (has != 0) {
            owners[output_count] = owner;
            output_count += 1;
        }
    }
    if (output_count == 0) return 0;
    const root_fd = c.tdnf_rpm_config_open_root_fd(@ptrCast(config));
    if (root_fd < 0) return ERROR_TDNF_TRANSACTION_FAILED;
    defer _ = std.c.close(root_fd);
    var options = std.mem.zeroes(c.tdnf_rpm_file_trigger_options);
    var result = std.mem.zeroes(c.tdnf_rpm_trigger_result);
    options.install_root = install_root;
    options.config = @ptrCast(config);
    options.install_root_fd = root_fd;
    options.trans_flags = flags;
    options.script_fd = script_fd;
    options.redirect_stdout_to_stderr = redirect;
    options.suppress_stdin = suppress_stdin;
    if (c.tdnf_rpm_run_file_triggers(
        owners.ptr,
        output_count,
        phase,
        kind,
        priority,
        &options,
        &result,
    ) != 0) {
        logRpmzigError(phase_name);
        return ERROR_TDNF_TRANSACTION_FAILED;
    }
    return 0;
}

fn runOtherPackageFileTriggers(
    view: *TransactionView,
    paths: *const PathList,
    current_blob: ?[*]const u8,
    phase: c_uint,
    priority: c_uint,
    phase_name: [*:0]const u8,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    const flat = paths.flatten() catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(flat);
    var owners = allocator.alloc(
        c.tdnf_rpm_file_trigger_owner,
        view.entries.items.len,
    ) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(owners);
    var count: usize = 0;
    for (view.entries.items) |entry| {
        if (!entry.db_visible or
            (current_blob != null and entry.blob.ptr == current_blob.? and
                phase != c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN))
            continue;
        owners[count] = .{
            .header_blob = entry.blob.ptr,
            .header_len = entry.blob.len,
            .paths = flat.ptr,
            .path_count = flat.len,
            .order = entry.order,
        };
        count += 1;
    }
    return runFileTriggerOwners(
        owners[0..count],
        phase,
        c.TDNF_RPM_FILE_TRIGGER_KIND_PACKAGE,
        priority,
        phase_name,
        install_root,
        config,
        flags,
        script_fd,
        redirect,
        0,
    );
}

fn runImmediatePackageFileTriggers(
    view: *TransactionView,
    owner_blob: []const u8,
    owner_order: u64,
    phase: c_uint,
    priority: c_uint,
    phase_name: [*:0]const u8,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    const has = c.tdnf_rpm_header_has_file_trigger_metadata(
        owner_blob.ptr,
        owner_blob.len,
        c.TDNF_RPM_FILE_TRIGGER_KIND_PACKAGE,
    );
    if (has < 0) {
        logRpmzigError("inspect package file triggers");
        return ERROR_TDNF_TRANSACTION_FAILED;
    }
    if (has == 0) return 0;
    var paths = PathList{};
    defer paths.deinit();
    const rc = collectAllDbTriggerPaths(view, flags, &paths);
    if (rc != 0) return rc;
    const flat = paths.flatten() catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(flat);
    var owner = c.tdnf_rpm_file_trigger_owner{
        .header_blob = owner_blob.ptr,
        .header_len = owner_blob.len,
        .paths = flat.ptr,
        .path_count = flat.len,
        .order = owner_order,
    };
    return runFileTriggerOwners(
        @as([*]c.tdnf_rpm_file_trigger_owner, @ptrCast(&owner))[0..1],
        phase,
        c.TDNF_RPM_FILE_TRIGGER_KIND_PACKAGE,
        priority,
        phase_name,
        install_root,
        config,
        flags,
        script_fd,
        redirect,
        0,
    );
}

fn runStableTransactionFileTriggers(
    view: *TransactionView,
    paths: *const PathList,
    phase: c_uint,
    phase_name: [*:0]const u8,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    const flat = paths.flatten() catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(flat);
    var owners = allocator.alloc(
        c.tdnf_rpm_file_trigger_owner,
        view.entries.items.len,
    ) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(owners);
    var count: usize = 0;
    for (view.entries.items) |entry| {
        if (!entry.db_visible or entry.added or entry.removed) continue;
        owners[count] = .{
            .header_blob = entry.blob.ptr,
            .header_len = entry.blob.len,
            .paths = flat.ptr,
            .path_count = flat.len,
            .order = entry.order,
        };
        count += 1;
    }
    return runFileTriggerOwners(
        owners[0..count],
        phase,
        c.TDNF_RPM_FILE_TRIGGER_KIND_TRANSACTION,
        c.TDNF_RPM_TRIGGER_PRIORITY_ALL,
        phase_name,
        install_root,
        config,
        flags,
        script_fd,
        redirect,
        if (phase == c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN) 1 else 0,
    );
}

fn runRemovedImmediateTransactionFileTriggers(
    view: *TransactionView,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    var removed_count: usize = 0;
    var any_triggers = false;
    for (view.entries.items) |entry| {
        if (!entry.removed) continue;
        removed_count += 1;
        const has = c.tdnf_rpm_header_has_file_trigger_metadata(
            entry.blob.ptr,
            entry.blob.len,
            c.TDNF_RPM_FILE_TRIGGER_KIND_TRANSACTION,
        );
        if (has < 0) return ERROR_TDNF_TRANSACTION_FAILED;
        any_triggers = any_triggers or has != 0;
    }
    if (removed_count == 0 or !any_triggers) return 0;
    var paths = PathList{};
    defer paths.deinit();
    var rc = collectAllDbTriggerPaths(view, 0, &paths);
    if (rc != 0) return rc;
    const flat = paths.flatten() catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(flat);
    for (0..removed_count) |order| {
        var found: ?ViewEntry = null;
        for (view.entries.items) |entry| {
            if (entry.removed and entry.removal_order == order) {
                found = entry;
                break;
            }
        }
        const entry = found orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
        var owner = c.tdnf_rpm_file_trigger_owner{
            .header_blob = entry.blob.ptr,
            .header_len = entry.blob.len,
            .paths = flat.ptr,
            .path_count = flat.len,
            .order = entry.removal_order,
        };
        rc = runFileTriggerOwners(
            @as([*]c.tdnf_rpm_file_trigger_owner, @ptrCast(&owner))[0..1],
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
            c.TDNF_RPM_FILE_TRIGGER_KIND_TRANSACTION,
            c.TDNF_RPM_TRIGGER_PRIORITY_ALL,
            "%transfiletriggerun (transaction package)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
            0,
        );
        if (rc != 0) return rc;
    }
    return 0;
}

fn runAddedImmediateTransactionFileTriggers(
    view: *TransactionView,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    var any_triggers = false;
    for (view.entries.items) |entry| {
        if (!entry.added) continue;
        const has = c.tdnf_rpm_header_has_file_trigger_metadata(
            entry.blob.ptr,
            entry.blob.len,
            c.TDNF_RPM_FILE_TRIGGER_KIND_TRANSACTION,
        );
        if (has < 0) return ERROR_TDNF_TRANSACTION_FAILED;
        any_triggers = any_triggers or has != 0;
    }
    if (!any_triggers) return 0;
    var paths = PathList{};
    defer paths.deinit();
    var rc = collectAllDbTriggerPaths(view, flags, &paths);
    if (rc != 0) return rc;
    const flat = paths.flatten() catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(flat);
    for (view.entries.items) |entry| {
        if (!entry.added) continue;
        var owner = c.tdnf_rpm_file_trigger_owner{
            .header_blob = entry.blob.ptr,
            .header_len = entry.blob.len,
            .paths = flat.ptr,
            .path_count = flat.len,
            .order = entry.order,
        };
        rc = runFileTriggerOwners(
            @as([*]c.tdnf_rpm_file_trigger_owner, @ptrCast(&owner))[0..1],
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERIN,
            c.TDNF_RPM_FILE_TRIGGER_KIND_TRANSACTION,
            c.TDNF_RPM_TRIGGER_PRIORITY_ALL,
            "%transfiletriggerin (transaction package)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
            0,
        );
        if (rc != 0) return rc;
    }
    return 0;
}

fn runScheduledPostunTransactionFileTriggers(
    queue: *PostunQueue,
    view: *TransactionView,
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    var owners = allocator.alloc(
        c.tdnf_rpm_file_trigger_owner,
        queue.owners.items.len,
    ) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(owners);
    var flattened = allocator.alloc(
        []c.tdnf_rpm_trigger_path,
        queue.owners.items.len,
    ) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(flattened);
    var flattened_count: usize = 0;
    defer for (flattened[0..flattened_count]) |paths| allocator.free(paths);
    var owner_count: usize = 0;
    for (queue.owners.items) |*queued| {
        var still_visible = false;
        for (view.entries.items) |entry| {
            if (entry.db_visible and entry.blob.ptr == queued.blob.ptr) {
                still_visible = true;
                break;
            }
        }
        if (!still_visible) continue;
        const flat = queued.paths.flatten() catch
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
        flattened[flattened_count] = flat;
        flattened_count += 1;
        owners[owner_count] = .{
            .header_blob = queued.blob.ptr,
            .header_len = queued.blob.len,
            .paths = flat.ptr,
            .path_count = flat.len,
            .order = queued.order,
        };
        owner_count += 1;
    }
    return runFileTriggerOwners(
        owners[0..owner_count],
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN,
        c.TDNF_RPM_FILE_TRIGGER_KIND_TRANSACTION,
        c.TDNF_RPM_TRIGGER_PRIORITY_ALL,
        "%transfiletriggerpostun",
        install_root,
        config,
        flags,
        script_fd,
        redirect,
        1,
    );
}

fn planItem(
    plan: *const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
    index: usize,
) *const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM {
    return @ptrFromInt(
        @intFromPtr(plan.pItems) +
            index * @sizeOf(c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM),
    );
}

fn fixedValidationError(
    failure: ?*FixedOrderValidationFailure,
    kind: FixedOrderValidationFailure,
) u32 {
    if (failure) |out| out.* = kind;
    return errors.ERROR_TDNF_INVALID_PARAMETER;
}

fn prevalidatePlanStructure(
    ts: *c.TDNFRPMTS,
    plan: *const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
    input_items: []const *c.TDNF_RPM_TS_ITEM,
    view: *TransactionView,
    expected_items: ?[]const FixedOrderExpectedItem,
    failure: ?*FixedOrderValidationFailure,
) u32 {
    if (failure) |out| out.* = .none;
    if (plan.dwItemCount != ts.dwTransactionItemCount or
        plan.dwItemCount != input_items.len or
        plan.dwProblemCount != 0 or plan.pdwOrderIndices == null)
        return fixedValidationError(failure, .malformed_order);
    if (plan.pItems == null)
        return fixedValidationError(failure, .invalid_item);
    if (expected_items) |expected| {
        if (expected.len != input_items.len)
            return fixedValidationError(failure, .invalid_item);
    }

    const seen = allocator.alloc(bool, input_items.len) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(seen);
    @memset(seen, false);
    for (plan.pdwOrderIndices[0..plan.dwItemCount]) |input_index_u32| {
        const input_index: usize = input_index_u32;
        if (input_index >= input_items.len or seen[input_index])
            return fixedValidationError(failure, .malformed_order);
        seen[input_index] = true;
        const item = input_items[input_index];
        const planned = planItem(plan, input_index);
        if (planned.dwPriorOffset > plan.dwPriorHnumCount or
            planned.dwPriorCount >
                plan.dwPriorHnumCount - planned.dwPriorOffset or
            (planned.dwPriorCount != 0 and plan.pdwPriorHnums == null))
            return fixedValidationError(failure, .invalid_item);
        const expected = if (expected_items) |items| &items[input_index] else null;
        if (item.nType == item_erase) {
            const entry = view.find(item.dwRpmDbHnum);
            if (planned.dwPriorCount != 0 or entry == null or !entry.?.active)
                return fixedValidationError(
                    failure,
                    if (expected != null) .prior_mismatch else .invalid_item,
                );
            if (expected) |fixed| {
                const row = fixed.erase orelse
                    return fixedValidationError(failure, .invalid_item);
                if (fixed.priors.len != 0 or row.hnum != item.dwRpmDbHnum or
                    !identityMatchesHeader(row.identity, entry.?.blob))
                    return fixedValidationError(failure, .prior_mismatch);
            }
        } else if (expected) |fixed| {
            if (fixed.erase != null or fixed.priors.len != planned.dwPriorCount)
                return fixedValidationError(failure, .invalid_item);
        }
        for (0..planned.dwPriorCount) |offset| {
            const hnum = plan.pdwPriorHnums[
                planned.dwPriorOffset + offset
            ];
            const entry = view.find(hnum);
            if (entry == null or !entry.?.active)
                return fixedValidationError(
                    failure,
                    if (expected != null) .prior_mismatch else .invalid_item,
                );
            if (expected) |fixed| {
                const row = fixed.priors[offset];
                if (row.hnum != hnum or
                    !identityMatchesHeader(row.identity, entry.?.blob))
                    return fixedValidationError(failure, .prior_mismatch);
            }
        }
    }
    return 0;
}

fn prevalidatePlan(
    ts: *c.TDNFRPMTS,
    plan: *const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
    input_items: []const *c.TDNF_RPM_TS_ITEM,
    view: *TransactionView,
    config: *const anyopaque,
    expected_items: ?[]const FixedOrderExpectedItem,
    failure: ?*FixedOrderValidationFailure,
) u32 {
    const rc = prevalidatePlanStructure(
        ts,
        plan,
        input_items,
        view,
        expected_items,
        failure,
    );
    if (rc != 0) return rc;
    for (view.entries.items) |entry| {
        if (c.tdnf_rpm_header_validate_trigger_scripts_config(
            entry.blob.ptr,
            entry.blob.len,
            @ptrCast(config),
        ) != 0) {
            logRpmzigError("validate installed trigger metadata");
            return ERROR_TDNF_TRANSACTION_FAILED;
        }
    }
    for (plan.pdwOrderIndices[0..plan.dwItemCount]) |input_index_u32| {
        const input_index: usize = input_index_u32;
        const item = input_items[input_index];
        if (item.nType != item_erase) {
            const file = item.pRpmFile orelse
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            var blob_ptr: [*c]const u8 = null;
            var blob_len: usize = 0;
            if (c.tdnf_rpm_file_main_header_blob(
                file,
                &blob_ptr,
                &blob_len,
            ) != 0 or c.tdnf_rpm_header_validate_trigger_scripts_config(
                blob_ptr,
                blob_len,
                @ptrCast(config),
            ) != 0) {
                logRpmzigError("validate transaction trigger metadata");
                return ERROR_TDNF_TRANSACTION_FAILED;
            }
        }
    }
    return 0;
}

fn markRemovedEntries(
    plan: *const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
    input_items: []const *c.TDNF_RPM_TS_ITEM,
    view: *TransactionView,
) u32 {
    var removal_order: u64 = 0;
    for (plan.pdwOrderIndices[0..plan.dwItemCount]) |input_index| {
        if (input_index >= input_items.len)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        const item = input_items[input_index];
        const planned = planItem(plan, input_index);
        if (item.nType == item_erase) {
            const entry = view.find(item.dwRpmDbHnum) orelse
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            if (!entry.removed) {
                entry.removed = true;
                entry.removal_order = removal_order;
                removal_order += 1;
            }
        }
        for (0..planned.dwPriorCount) |offset| {
            const entry = view.find(plan.pdwPriorHnums[
                planned.dwPriorOffset + offset
            ]) orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
            if (!entry.removed) {
                entry.removed = true;
                entry.removal_order = removal_order;
                removal_order += 1;
            }
        }
    }
    return 0;
}

fn collectTransactionRemovedPaths(
    view: *TransactionView,
    paths: *PathList,
) u32 {
    var removed_count: usize = 0;
    for (view.entries.items) |entry| if (entry.removed) {
        removed_count += 1;
    };
    for (0..removed_count) |order| {
        var found: ?ViewEntry = null;
        for (view.entries.items) |entry| {
            if (entry.removed and entry.removal_order == order) {
                found = entry;
                break;
            }
        }
        const entry = found orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
        const rc = collectHeaderTriggerPaths(entry.blob, 0, null, paths);
        if (rc != 0) return rc;
    }
    return 0;
}

fn runTransactionScriptletPhase(
    plan: *const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
    input_items: []const *c.TDNF_RPM_TS_ITEM,
    view: *TransactionView,
    config: *const anyopaque,
    phase: c_uint,
    phase_name: [*:0]const u8,
    install_root: [*:0]const u8,
    flags: u32,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    for (plan.pdwOrderIndices[0..plan.dwItemCount], 0..) |input_index, order| {
        if (input_index >= input_items.len)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        const item = input_items[input_index];
        if (item.nType == item_erase) continue;
        const file = item.pRpmFile orelse return ERROR_TDNF_TRANSACTION_FAILED;
        var blob_ptr: [*c]const u8 = null;
        var blob_len: usize = 0;
        if (c.tdnf_rpm_file_main_header_blob(file, &blob_ptr, &blob_len) != 0)
            return ERROR_TDNF_TRANSACTION_FAILED;
        var arg1 = view.countName(@ptrCast(item.pszName));
        if (arg1 < 0) return ERROR_TDNF_TRANSACTION_FAILED;
        if (phase == c.TDNF_RPM_SCRIPTLET_PHASE_PRETRANS) {
            if (arg1 == std.math.maxInt(c_int))
                return ERROR_TDNF_TRANSACTION_FAILED;
            arg1 += 1;
            for (plan.pdwOrderIndices[0..order]) |prior_index| {
                const prior = input_items[prior_index];
                if (prior.nType != item_erase and prior.pszName != null and
                    item.pszName != null and
                    std.mem.eql(
                        u8,
                        std.mem.span(prior.pszName),
                        std.mem.span(item.pszName),
                    ))
                {
                    if (arg1 == std.math.maxInt(c_int))
                        return ERROR_TDNF_TRANSACTION_FAILED;
                    arg1 += 1;
                }
            }
        }
        const rc = runScriptlet(
            blob_ptr[0..blob_len],
            phase,
            phase_name,
            @ptrCast(item.pszName),
            install_root,
            config,
            flags,
            arg1,
            -1,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
    }
    return 0;
}

fn formatNevra(item: *const c.TDNF_RPM_TS_ITEM) struct { u32, ?[*:0]u8 } {
    if (isEmpty(@ptrCast(item.pszName)) or
        isEmpty(@ptrCast(item.pszEVR)) or
        isEmpty(@ptrCast(item.pszArch)))
        return .{ 0, null };
    var result: ?[*:0]u8 = null;
    const rc = common.allocPrint(&result, "%s-%s.%s", .{ item.pszName, item.pszEVR, item.pszArch });
    return .{ rc, result };
}

fn eraseOldAfterReplace(
    install_root: [*:0]const u8,
    config: *const anyopaque,
    flags: u32,
    view: *TransactionView,
    old_hnum: u32,
    old_blob: []const u8,
    name: ?[*:0]const u8,
    nevra: ?[*:0]const u8,
    erase_db_row: bool,
    postun_queue: *PostunQueue,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    const old_index = view.findIndex(old_hnum) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const old_entry = view.entries.items[old_index];
    if (!old_entry.active) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const current_count = view.countName(name);
    if (current_count <= 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const count_after = current_count - 1;
    var ignored = [_]u32{old_hnum};
    var ownership = OwnershipContext{
        .view = view,
        .config = config,
        .ignored_hnums = &ignored,
    };
    var removed_paths = PathList{};
    defer removed_paths.deinit();
    var transaction_paths = PathList{};
    defer transaction_paths.deinit();
    var rc = collectHeaderTriggerPaths(old_blob, 0, &ownership, &removed_paths);
    if (rc != 0) return rc;
    rc = collectHeaderTriggerPaths(old_blob, 0, null, &transaction_paths);
    if (rc != 0) return rc;

    rc = runImmediatePackageFileTriggers(
        view,
        old_blob,
        old_entry.order,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
        c.TDNF_RPM_TRIGGER_PRIORITY_HIGH,
        "%filetriggerun (removed package, high)",
        install_root,
        config,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runOtherPackageFileTriggers(
        view,
        &removed_paths,
        old_blob.ptr,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
        c.TDNF_RPM_TRIGGER_PRIORITY_HIGH,
        "%filetriggerun (high)",
        install_root,
        config,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runTriggers(
        old_blob,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
        "%triggerun",
        install_root,
        config,
        flags,
        view,
        script_fd,
        redirect,
        count_after,
    );
    if (rc != 0) return rc;
    rc = runScriptlet(
        old_blob,
        c.TDNF_RPM_SCRIPTLET_PHASE_PREUN,
        "%preun",
        nevra,
        install_root,
        config,
        flags,
        count_after,
        -1,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runImmediatePackageFileTriggers(
        view,
        old_blob,
        old_entry.order,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
        c.TDNF_RPM_TRIGGER_PRIORITY_LOW,
        "%filetriggerun (removed package, low)",
        install_root,
        config,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runOtherPackageFileTriggers(
        view,
        &removed_paths,
        old_blob.ptr,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
        c.TDNF_RPM_TRIGGER_PRIORITY_LOW,
        "%filetriggerun (low)",
        install_root,
        config,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;

    var erase_options = std.mem.zeroes(c.tdnf_rpm_erase_options);
    erase_options.config = @ptrCast(config);
    erase_options.trans_flags = flags;
    erase_options.keep_path_fn = nativePathOwned;
    erase_options.keep_path_fn_data = &ownership;
    if (c.tdnf_rpm_erase_header_blob(
        install_root,
        old_blob.ptr,
        old_blob.len,
        &erase_options,
    ) != 0) {
        logRpmzigError("rpm_erase_header_blob");
        return ERROR_TDNF_TRANSACTION_FAILED;
    }
    view.entries.items[old_index].active = false;

    rc = runOtherPackageFileTriggers(
        view,
        &removed_paths,
        old_blob.ptr,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN,
        c.TDNF_RPM_TRIGGER_PRIORITY_HIGH,
        "%filetriggerpostun (high)",
        install_root,
        config,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runScriptlet(
        old_blob,
        c.TDNF_RPM_SCRIPTLET_PHASE_POSTUN,
        "%postun",
        nevra,
        install_root,
        config,
        flags,
        count_after,
        -1,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runTriggers(
        old_blob,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN,
        "%triggerpostun",
        install_root,
        config,
        flags,
        view,
        script_fd,
        redirect,
        count_after,
    );
    if (rc != 0) return rc;
    rc = runOtherPackageFileTriggers(
        view,
        &removed_paths,
        old_blob.ptr,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN,
        c.TDNF_RPM_TRIGGER_PRIORITY_LOW,
        "%filetriggerpostun (low)",
        install_root,
        config,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = schedulePostun(postun_queue, view, &transaction_paths);
    if (rc != 0) return rc;
    if ((flags & trans_flags.TDNF_RPMTRANS_FLAG_NODB) == 0) {
        if (erase_db_row and c.tdnf_rpmdb_write_erase_hnum_config(
            @ptrCast(config),
            old_hnum,
        ) != 0) {
            logRpmzigError("rpmdb_write_erase_hnum");
            return ERROR_TDNF_TRANSACTION_FAILED;
        }
        if (!view.entries.items[old_index].db_visible)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        view.entries.items[old_index].db_visible = false;
    }
    return 0;
}

fn installKindForItemType(item_type: c_uint) ?c_uint {
    return switch (item_type) {
        item_install, item_obsolete => c.TDNF_RPM_INSTALL_KIND_INSTALL,
        item_upgrade, item_downgrade => c.TDNF_RPM_INSTALL_KIND_UPGRADE,
        item_reinstall => c.TDNF_RPM_INSTALL_KIND_REINSTALL,
        else => null,
    };
}

fn selectReplacementPriorIndex(
    item_type: c_uint,
    priors: []const PriorEntry,
    view: *TransactionView,
) error{InvalidItem}!?usize {
    return switch (item_type) {
        item_upgrade, item_downgrade, item_reinstall => blk: {
            if (priors.len == 0) return error.InvalidItem;
            const entry = view.find(priors[0].hnum) orelse
                return error.InvalidItem;
            if (!entry.active) return error.InvalidItem;
            break :blk 0;
        },
        item_install, item_obsolete => blk: {
            for (priors, 0..) |prior, index| {
                const entry = view.find(prior.hnum) orelse
                    return error.InvalidItem;
                if (entry.active) break :blk index;
            }
            break :blk null;
        },
        else => error.InvalidItem,
    };
}

fn processInstallItem(
    ts: *c.TDNFRPMTS,
    tdnf: *abi.Tdnf,
    plan: *const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
    input_index: usize,
    view: *TransactionView,
    removed_hnums: []const u32,
    transaction_added_paths: *PathList,
    postun_queue: *PostunQueue,
    item: *c.TDNF_RPM_TS_ITEM,
    flags: u32,
    install_tid: u32,
    install_time: u32,
    install_root: [*:0]const u8,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    const file = item.pRpmFile orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var blob_ptr: [*c]const u8 = null;
    var blob_len: usize = 0;
    if (c.tdnf_rpm_file_main_header_blob(file, &blob_ptr, &blob_len) != 0)
        return ERROR_TDNF_TRANSACTION_FAILED;
    const blob = blob_ptr[0..blob_len];
    const formatted = formatNevra(item);
    if (formatted[0] != 0) return formatted[0];
    const nevra = formatted[1];
    defer free(nevra);
    const install_kind = installKindForItemType(item.nType) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const planned = planItem(plan, input_index);
    const prior_count: usize = planned.dwPriorCount;
    var prior_views = allocator.alloc(
        c.tdnf_rpm_install_prior_header,
        prior_count,
    ) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(prior_views);
    var prior_entries = allocator.alloc(PriorEntry, prior_count) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(prior_entries);
    for (0..prior_count) |offset| {
        const hnum = plan.pdwPriorHnums[planned.dwPriorOffset + offset];
        const entry = view.find(hnum) orelse
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        prior_entries[offset] = .{
            .hnum = entry.hnum,
            .blob = entry.blob,
        };
        prior_views[offset] = .{
            .blob = entry.blob.ptr,
            .len = entry.blob.len,
        };
    }
    const replacement_prior_index = selectReplacementPriorIndex(
        item.nType,
        prior_entries,
        view,
    ) catch return errors.ERROR_TDNF_INVALID_PARAMETER;
    const config = tdnf.pRpmConfig orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var ownership = OwnershipContext{
        .view = view,
        .config = config,
        .ignored_hnums = removed_hnums,
    };
    var item_paths = PathList{};
    defer item_paths.deinit();
    var install_path_context = InstallPathContext{
        .paths = &item_paths,
        .source = blob.ptr,
        .source_len = blob.len,
    };
    const count = view.countName(@ptrCast(item.pszName));
    if (count < 0 or count == std.math.maxInt(c_int))
        return ERROR_TDNF_TRANSACTION_FAILED;
    const arg1 = count + 1;
    var rc: u32 = 0;
    if (tdnf.pArgs.?.nTestOnly == 0) {
        rc = runScriptlet(
            blob,
            c.TDNF_RPM_SCRIPTLET_PHASE_PRE,
            "%pre",
            nevra,
            install_root,
            config,
            flags,
            arg1,
            -1,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
    }
    if (ts.nQuiet == 0) {
        common.log(LOG_INFO, "%s: %s\n", .{ if (item.nType == item_reinstall)
            @as([*:0]const u8, "Reinstalling")
        else if (item.nType == item_downgrade)
            @as([*:0]const u8, "Downgrading")
        else if (item.nType == item_upgrade)
            @as([*:0]const u8, "Upgrading")
        else
            @as([*:0]const u8, "Installing"), nevra orelse @as(?[*:0]const u8, @ptrCast(item.pszPath)) });
    }
    if (tdnf.pArgs.?.nTestOnly == 0) {
        var options = std.mem.zeroes(c.tdnf_rpm_install_options);
        options.install_root = install_root;
        options.config = @ptrCast(config);
        options.trans_flags = flags;
        options.install_kind = install_kind;
        options.prior_headers = prior_views.ptr;
        options.prior_header_count = prior_views.len;
        options.conflict_fn = nativePathOwned;
        options.conflict_fn_data = &ownership;
        options.changed_path_fn = appendInstalledPath;
        options.changed_path_fn_data = &install_path_context;
        if (c.tdnf_rpm_file_install(file, &options) != 0) {
            logRpmzigError("rpm_file_install");
            return ERROR_TDNF_TRANSACTION_FAILED;
        }
        var new_hnum: u32 = 0;
        if ((flags & trans_flags.TDNF_RPMTRANS_FLAG_NODB) == 0) {
            if (replacement_prior_index) |replacement_index| {
                if (c.tdnf_rpmdb_write_replace_file_config(
                    @ptrCast(config),
                    prior_entries[replacement_index].hnum,
                    file,
                    install_tid,
                    install_time,
                    0,
                    null,
                    0,
                    &new_hnum,
                ) != 0) return ERROR_TDNF_TRANSACTION_FAILED;
            } else if (c.tdnf_rpmdb_write_install_file_config(
                @ptrCast(config),
                file,
                install_tid,
                install_time,
                0,
                null,
                0,
                &new_hnum,
            ) != 0) return ERROR_TDNF_TRANSACTION_FAILED;
        }
        rc = view.activate(
            blob,
            new_hnum,
            (flags & trans_flags.TDNF_RPMTRANS_FLAG_NODB) == 0,
        );
        if (rc != 0) return rc;
        const new_entry = view.entries.items[view.entries.items.len - 1];
        if (new_entry.db_visible) {
            rc = transaction_added_paths.merge(&item_paths);
            if (rc != 0) return rc;
        }
        rc = runOtherPackageFileTriggers(
            view,
            &item_paths,
            blob.ptr,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERIN,
            c.TDNF_RPM_TRIGGER_PRIORITY_HIGH,
            "%filetriggerin (high)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runImmediatePackageFileTriggers(
            view,
            blob,
            new_entry.order,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERIN,
            c.TDNF_RPM_TRIGGER_PRIORITY_HIGH,
            "%filetriggerin (installed package, high)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runScriptlet(
            blob,
            c.TDNF_RPM_SCRIPTLET_PHASE_POST,
            "%post",
            nevra,
            install_root,
            config,
            flags,
            arg1,
            -1,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runTriggers(
            blob,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERIN,
            "%triggerin",
            install_root,
            config,
            flags,
            view,
            script_fd,
            redirect,
            arg1,
        );
        if (rc != 0) return rc;
        rc = runOtherPackageFileTriggers(
            view,
            &item_paths,
            blob.ptr,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERIN,
            c.TDNF_RPM_TRIGGER_PRIORITY_LOW,
            "%filetriggerin (low)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runImmediatePackageFileTriggers(
            view,
            blob,
            new_entry.order,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERIN,
            c.TDNF_RPM_TRIGGER_PRIORITY_LOW,
            "%filetriggerin (installed package, low)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        for (prior_entries, 0..) |prior, prior_index| {
            const entry = view.find(prior.hnum) orelse
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            if (!entry.active) continue;
            rc = eraseOldAfterReplace(
                install_root,
                config,
                flags,
                view,
                prior.hnum,
                prior.blob,
                @ptrCast(item.pszName),
                nevra,
                replacement_prior_index == null or
                    prior_index != replacement_prior_index.?,
                postun_queue,
                script_fd,
                redirect,
            );
            if (rc != 0) return rc;
        }
    }
    return 0;
}

fn processEraseItem(
    ts: *c.TDNFRPMTS,
    tdnf: *abi.Tdnf,
    view: *TransactionView,
    postun_queue: *PostunQueue,
    item: *c.TDNF_RPM_TS_ITEM,
    flags: u32,
    install_root: [*:0]const u8,
    script_fd: c_int,
    redirect: c_int,
) u32 {
    if (item.dwRpmDbHnum == 0) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const formatted = formatNevra(item);
    if (formatted[0] != 0) return formatted[0];
    const nevra = formatted[1];
    defer free(nevra);
    const entry_index = view.findIndex(item.dwRpmDbHnum) orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const entry = view.entries.items[entry_index];
    if (!entry.active) return errors.ERROR_TDNF_INVALID_PARAMETER;
    const current_count = view.countName(@ptrCast(item.pszName));
    if (current_count <= 0) return ERROR_TDNF_TRANSACTION_FAILED;
    const count_after = current_count - 1;
    const config = tdnf.pRpmConfig orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    var ignored = [_]u32{item.dwRpmDbHnum};
    var ownership = OwnershipContext{
        .view = view,
        .config = config,
        .ignored_hnums = &ignored,
    };
    var removed_paths = PathList{};
    defer removed_paths.deinit();
    var transaction_paths = PathList{};
    defer transaction_paths.deinit();
    var rc = collectHeaderTriggerPaths(entry.blob, 0, &ownership, &removed_paths);
    if (rc != 0) return rc;
    rc = collectHeaderTriggerPaths(entry.blob, 0, null, &transaction_paths);
    if (rc != 0) return rc;
    if (tdnf.pArgs.?.nTestOnly == 0) {
        rc = runImmediatePackageFileTriggers(
            view,
            entry.blob,
            entry.order,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
            c.TDNF_RPM_TRIGGER_PRIORITY_HIGH,
            "%filetriggerun (removed package, high)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runOtherPackageFileTriggers(
            view,
            &removed_paths,
            entry.blob.ptr,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
            c.TDNF_RPM_TRIGGER_PRIORITY_HIGH,
            "%filetriggerun (high)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runTriggers(
            entry.blob,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
            "%triggerun",
            install_root,
            config,
            flags,
            view,
            script_fd,
            redirect,
            count_after,
        );
        if (rc != 0) return rc;
        rc = runScriptlet(
            entry.blob,
            c.TDNF_RPM_SCRIPTLET_PHASE_PREUN,
            "%preun",
            nevra,
            install_root,
            config,
            flags,
            count_after,
            -1,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runImmediatePackageFileTriggers(
            view,
            entry.blob,
            entry.order,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
            c.TDNF_RPM_TRIGGER_PRIORITY_LOW,
            "%filetriggerun (removed package, low)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runOtherPackageFileTriggers(
            view,
            &removed_paths,
            entry.blob.ptr,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
            c.TDNF_RPM_TRIGGER_PRIORITY_LOW,
            "%filetriggerun (low)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
    }
    if (ts.nQuiet == 0)
        common.log(LOG_INFO, "Removing: %s\n", .{nevra orelse @as(?[*:0]const u8, @ptrCast(item.pszName))});
    if (tdnf.pArgs.?.nTestOnly == 0) {
        var erase_options = std.mem.zeroes(c.tdnf_rpm_erase_options);
        erase_options.config = @ptrCast(config);
        erase_options.trans_flags = flags;
        erase_options.keep_path_fn = nativePathOwned;
        erase_options.keep_path_fn_data = &ownership;
        if (c.tdnf_rpm_erase_header_blob(
            install_root,
            entry.blob.ptr,
            entry.blob.len,
            &erase_options,
        ) != 0) return ERROR_TDNF_TRANSACTION_FAILED;
        view.entries.items[entry_index].active = false;
        rc = runOtherPackageFileTriggers(
            view,
            &removed_paths,
            entry.blob.ptr,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN,
            c.TDNF_RPM_TRIGGER_PRIORITY_HIGH,
            "%filetriggerpostun (high)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runScriptlet(
            entry.blob,
            c.TDNF_RPM_SCRIPTLET_PHASE_POSTUN,
            "%postun",
            nevra,
            install_root,
            config,
            flags,
            count_after,
            -1,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = runTriggers(
            entry.blob,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN,
            "%triggerpostun",
            install_root,
            config,
            flags,
            view,
            script_fd,
            redirect,
            count_after,
        );
        if (rc != 0) return rc;
        rc = runOtherPackageFileTriggers(
            view,
            &removed_paths,
            entry.blob.ptr,
            c.TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN,
            c.TDNF_RPM_TRIGGER_PRIORITY_LOW,
            "%filetriggerpostun (low)",
            install_root,
            config,
            flags,
            script_fd,
            redirect,
        );
        if (rc != 0) return rc;
        rc = schedulePostun(postun_queue, view, &transaction_paths);
        if (rc != 0) return rc;
        if ((flags & trans_flags.TDNF_RPMTRANS_FLAG_NODB) == 0) {
            if (c.tdnf_rpmdb_write_erase_hnum_config(
                @ptrCast(config),
                item.dwRpmDbHnum,
            ) != 0) return ERROR_TDNF_TRANSACTION_FAILED;
            if (!view.entries.items[entry_index].db_visible)
                return errors.ERROR_TDNF_INVALID_PARAMETER;
            view.entries.items[entry_index].db_visible = false;
        }
    }
    return 0;
}

const PlanOrderIterator = struct {
    plan: *const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
    position: usize = 0,

    fn next(self: *PlanOrderIterator) ?usize {
        if (self.position >= self.plan.dwItemCount) return null;
        defer self.position += 1;
        return self.plan.pdwOrderIndices[self.position];
    }
};

fn runTransactionNativeImpl(
    ts_opt: ?*c.TDNFRPMTS,
    tdnf_opt: ?*abi.Tdnf,
    plan_opt: ?*const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
    expected_items: ?[]const FixedOrderExpectedItem,
    validation_failure: ?*FixedOrderValidationFailure,
) u32 {
    const ts = ts_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const plan = plan_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (tdnf.pArgs == null or tdnf.pConf == null or tdnf.pRpmConfig == null or
        plan.dwItemCount != ts.dwTransactionItemCount or
        (plan.dwPriorHnumCount != 0 and plan.pdwPriorHnums == null))
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const install_root: [*:0]const u8 = if (!isEmpty(tdnf.pArgs.?.pszInstallRoot))
        tdnf.pArgs.?.pszInstallRoot.?
    else
        "/";
    const flags = effectiveFlags(ts, tdnf);
    const now = time(null);
    const install_tid: u32 = @truncate(@as(u64, @bitCast(@as(i64, now))));

    var input_items = allocator.alloc(
        *c.TDNF_RPM_TS_ITEM,
        plan.dwItemCount,
    ) catch return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(input_items);
    var current = ts.pTransactionItems;
    var input_count: usize = 0;
    while (current) |item_ptr| {
        if (input_count >= input_items.len)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        const item: *c.TDNF_RPM_TS_ITEM = @ptrCast(item_ptr);
        input_items[input_count] = item;
        input_count += 1;
        current = item.pNext;
    }
    if (input_count != input_items.len)
        return errors.ERROR_TDNF_INVALID_PARAMETER;

    var removed_hnums = std.ArrayListUnmanaged(u32).empty;
    defer removed_hnums.deinit(allocator);
    if (plan.dwPriorHnumCount != 0) {
        for (plan.pdwPriorHnums[0..plan.dwPriorHnumCount]) |hnum| {
            var present = false;
            for (removed_hnums.items) |existing| {
                if (existing == hnum) {
                    present = true;
                    break;
                }
            }
            if (!present) removed_hnums.append(allocator, hnum) catch
                return errors.ERROR_TDNF_OUT_OF_MEMORY;
        }
    }
    for (input_items) |item| {
        if (item.nType != item_erase) continue;
        var present = false;
        for (removed_hnums.items) |existing| {
            if (existing == item.dwRpmDbHnum) {
                present = true;
                break;
            }
        }
        if (!present) removed_hnums.append(allocator, item.dwRpmDbHnum) catch
            return errors.ERROR_TDNF_OUT_OF_MEMORY;
    }

    const initialized = TransactionView.init(tdnf.pRpmConfig.?, plan.dwItemCount);
    if (initialized[0] != 0) return initialized[0];
    var view = initialized[1];
    defer view.deinit();
    var added_paths = PathList{};
    defer added_paths.deinit();
    var removed_paths = PathList{};
    defer removed_paths.deinit();
    var postun_queue = PostunQueue{};
    defer postun_queue.deinit();

    var rc = prevalidatePlan(
        ts,
        plan,
        input_items,
        &view,
        tdnf.pRpmConfig.?,
        expected_items,
        validation_failure,
    );
    if (rc != 0) return rc;
    rc = markRemovedEntries(plan, input_items, &view);
    if (rc != 0) return rc;
    rc = collectTransactionRemovedPaths(&view, &removed_paths);
    if (rc != 0) return rc;

    var script_fd: c_int = -1;
    defer {
        if (script_fd >= 0) _ = close(script_fd);
    }
    var redirect: c_int = 0;
    if (tdnf.pArgs.?.nJsonOutput != 0) {
        script_fd = dup(2);
        if (script_fd < 0) return ERROR_TDNF_RPMTS_FDDUP_FAILED;
        redirect = 1;
    }
    if (ts.nQuiet == 0)
        common.log(LOG_INFO, "Running transaction (rpmzig native executor)\n", .{});

    rc = runTransactionScriptletPhase(
        plan,
        input_items,
        &view,
        tdnf.pRpmConfig.?,
        c.TDNF_RPM_SCRIPTLET_PHASE_PRETRANS,
        "%pretrans",
        install_root,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runStableTransactionFileTriggers(
        &view,
        &removed_paths,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERUN,
        "%transfiletriggerun",
        install_root,
        tdnf.pRpmConfig.?,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runRemovedImmediateTransactionFileTriggers(
        &view,
        install_root,
        tdnf.pRpmConfig.?,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;

    var order_iterator = PlanOrderIterator{ .plan = plan };
    while (order_iterator.next()) |input_index| {
        if (input_index >= input_items.len)
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        const item = input_items[input_index];
        rc = switch (item.nType) {
            item_install,
            item_upgrade,
            item_reinstall,
            item_downgrade,
            item_obsolete,
            => processInstallItem(
                ts,
                tdnf,
                plan,
                input_index,
                &view,
                removed_hnums.items,
                &added_paths,
                &postun_queue,
                item,
                flags,
                install_tid,
                install_tid,
                install_root,
                script_fd,
                redirect,
            ),
            item_erase => processEraseItem(
                ts,
                tdnf,
                &view,
                &postun_queue,
                item,
                flags,
                install_root,
                script_fd,
                redirect,
            ),
            else => errors.ERROR_TDNF_INVALID_PARAMETER,
        };
        if (rc != 0) return rc;
    }
    rc = runTransactionScriptletPhase(
        plan,
        input_items,
        &view,
        tdnf.pRpmConfig.?,
        c.TDNF_RPM_SCRIPTLET_PHASE_POSTTRANS,
        "%posttrans",
        install_root,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runStableTransactionFileTriggers(
        &view,
        &added_paths,
        c.TDNF_RPM_TRIGGER_PHASE_TRIGGERIN,
        "%transfiletriggerin",
        install_root,
        tdnf.pRpmConfig.?,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    rc = runScheduledPostunTransactionFileTriggers(
        &postun_queue,
        &view,
        install_root,
        tdnf.pRpmConfig.?,
        flags,
        script_fd,
        redirect,
    );
    if (rc != 0) return rc;
    return runAddedImmediateTransactionFileTriggers(
        &view,
        install_root,
        tdnf.pRpmConfig.?,
        flags,
        script_fd,
        redirect,
    );
}

fn runTransactionNative(
    ts_opt: ?*c.TDNFRPMTS,
    tdnf_opt: ?*abi.Tdnf,
    plan_opt: ?*const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
) callconv(.c) u32 {
    return runTransactionNativeImpl(ts_opt, tdnf_opt, plan_opt, null, null);
}

fn orderAndCheck(ts: *c.TDNFRPMTS, tdnf: *abi.Tdnf) u32 {
    clearPlan(ts);
    const count: usize = ts.dwTransactionItemCount;
    if (count == 0) return 0;
    const inputs = allocator.alloc(c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2, count) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(inputs);
    @memset(inputs, std.mem.zeroes(c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2));
    const headers = allocator.alloc(?[*]const u8, count) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(headers);
    @memset(headers, null);
    const lengths = allocator.alloc(usize, count) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(lengths);
    @memset(lengths, 0);
    const sizes = allocator.alloc(u64, count) catch
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(sizes);
    @memset(sizes, 0);

    var item = ts.pTransactionItems;
    var index: usize = 0;
    while (item) |current| : ({
        item = @as(*c.TDNF_RPM_TS_ITEM, @ptrCast(current)).pNext;
        index += 1;
    }) {
        const current_ptr: *c.TDNF_RPM_TS_ITEM = @ptrCast(current);
        if (index >= count) return errors.ERROR_TDNF_INVALID_PARAMETER;
        inputs[index].dwOperation = switch (current_ptr.nType) {
            item_install => c.TDNF_REPOMD_NATIVE_TRANSACTION_OP_INSTALL,
            item_upgrade => c.TDNF_REPOMD_NATIVE_TRANSACTION_OP_UPGRADE,
            item_reinstall => c.TDNF_REPOMD_NATIVE_TRANSACTION_OP_REINSTALL,
            item_erase => c.TDNF_REPOMD_NATIVE_TRANSACTION_OP_ERASE,
            else => return errors.ERROR_TDNF_INVALID_PARAMETER,
        };
        if (current_ptr.nType != item_erase) {
            var header: [*c]const u8 = null;
            var header_len: usize = 0;
            var rpm_bytes: [*c]const u8 = null;
            var rpm_len: usize = 0;
            if (current_ptr.pRpmFile == null or
                c.tdnf_rpm_file_main_header_blob(
                    current_ptr.pRpmFile,
                    &header,
                    &header_len,
                ) != 0 or
                c.tdnf_rpm_file_bytes(current_ptr.pRpmFile, &rpm_bytes, &rpm_len) != 0)
                return ERROR_TDNF_RPM_CHECK;
            headers[index] = header;
            lengths[index] = header_len;
            sizes[index] = rpm_len;
        }
        inputs[index].pszPath = current_ptr.pszPath;
        inputs[index].pszName = current_ptr.pszName;
        inputs[index].pszEVR = current_ptr.pszEVR;
        inputs[index].pszArch = current_ptr.pszArch;
        inputs[index].dwRpmDbHnum = current_ptr.dwRpmDbHnum;
    }
    if (index != count) return errors.ERROR_TDNF_INVALID_PARAMETER;
    var plan: ?*c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = null;
    const rc = tdnf_repomd_native_verified_transaction_solve_config(
        inputs.ptr,
        headers.ptr,
        lengths.ptr,
        sizes.ptr,
        @intCast(count),
        tdnf.pRpmConfig,
        &plan,
    );
    if (rc != 0) {
        const message = c.TDNFRepoMdNativeTransactionLastError();
        if (!isEmpty(message))
            common.log(LOG_ERR, "rpmzig-transaction-check: %s\n", .{message});
        return rc;
    }
    if (plan == null or plan.?.dwItemCount != count or
        (count != 0 and (plan.?.pdwOrderIndices == null or plan.?.pItems == null)))
    {
        c.TDNFRepoMdNativeTransactionPlanFree(plan);
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    ts.pNativePlan = plan;
    if (plan.?.dwProblemCount != 0) {
        for (plan.?.pProblems[0..plan.?.dwProblemCount]) |problem|
            if (problem.nType == 5) return ERROR_TDNF_TRANSACTION_FAILED;
        return ERROR_TDNF_RPM_CHECK;
    }
    return 0;
}

fn runTransaction(ts: *c.TDNFRPMTS, tdnf: *abi.Tdnf) u32 {
    return runNormalTransactionWith(
        ts,
        tdnf,
        orderAndCheck,
        runTransactionNative,
        reportProblems,
    );
}

fn runNormalTransactionWith(
    ts: *c.TDNFRPMTS,
    tdnf: *abi.Tdnf,
    prepare: anytype,
    execute: anytype,
    report: anytype,
) u32 {
    var rc = prepare(ts, tdnf);
    if (rc != 0) {
        report(ts);
        return rc;
    }
    if (ts.dwTransactionItemCount == 0) return 0;
    rc = execute(ts, tdnf, ts.pNativePlan);
    if (rc != 0) report(ts);
    return rc;
}

fn runWithHistory(
    tdnf: *abi.Tdnf,
    ts: *c.TDNFRPMTS,
    history: *HistoryCtx,
    command_line: ?[*:0]const u8,
) u32 {
    var data_dir: ?[*:0]u8 = null;
    defer free(data_dir);
    var rc = common.joinPath(&data_dir, &.{ tdnf.pArgs.?.pszInstallRoot, tdnf.pConf.?.pszPersistDir });
    if (rc == 0 and data_dir != null) {
        rc = TDNFUtilsMakeDirs(data_dir);
        if (rc == errors.ERROR_TDNF_ALREADY_EXISTS) rc = 0;
    }
    if (rc != 0) return rc;
    if (history_sync_config(history, tdnf.pRpmConfig) != 0)
        return errors.ERROR_TDNF_HISTORY_ERROR;
    rc = runTransaction(ts, tdnf);
    if (rc != 0) return rc;
    if (history_update_state_config(history, tdnf.pRpmConfig, command_line) != 0)
        return errors.ERROR_TDNF_HISTORY_ERROR;
    return 0;
}

fn buildCommandLine(args: *abi.CmdArgs, output: *?[*:0]u8) u32 {
    output.* = null;
    if (args.nArgc < 1 or args.ppszArgv == null) return 0;
    return TDNFJoinArrayToString(args.ppszArgv.? + 1, " ", args.nArgc, output);
}

fn rpmExecTransaction(
    tdnf_opt: ?*abi.Tdnf,
    solved_opt: ?*c.TDNF_SOLVED_PKG_INFO,
) callconv(.c) u32 {
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const solved = solved_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (tdnf.pArgs == null or tdnf.pConf == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const created = createTransaction(tdnf, solved);
    const ts = created[1] orelse return created[0];
    defer cleanupTransaction(tdnf, ts);
    const args = tdnf.pArgs.?;
    if (args.nDownloadOnly != 0) return 0;
    if (args.nTestOnly != 0) return runTransaction(ts, tdnf);

    var history: ?*HistoryCtx = null;
    var command_line: ?[*:0]u8 = null;
    defer {
        free(command_line);
        destroy_history_ctx(history);
    }
    var rc = TDNFGetHistoryCtx(tdnf, &history, 0);
    if (rc != 0) return rc;
    rc = buildCommandLine(args, &command_line);
    if (rc != 0) return rc;
    rc = runWithHistory(tdnf, ts, history.?, command_line);
    if (rc != 0) return rc;
    return TDNFMarkAutoInstalled(tdnf, history, solved, 0);
}

fn rpmExecHistoryTransaction(
    tdnf_opt: ?*abi.Tdnf,
    solved_opt: ?*c.TDNF_SOLVED_PKG_INFO,
    history_args_opt: ?*c.TDNF_HISTORY_ARGS,
) callconv(.c) u32 {
    const tdnf = tdnf_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const solved = solved_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const history_args = history_args_opt orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (tdnf.pArgs == null or tdnf.pConf == null)
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const created = createTransaction(tdnf, solved);
    const ts = created[1] orelse return created[0];
    defer cleanupTransaction(tdnf, ts);
    const args = tdnf.pArgs.?;
    if (args.nDownloadOnly != 0) return 0;
    if (args.nTestOnly != 0) return runTransaction(ts, tdnf);

    var history: ?*HistoryCtx = null;
    var command_line: ?[*:0]u8 = null;
    defer {
        free(command_line);
        destroy_history_ctx(history);
    }
    var rc = TDNFGetHistoryCtx(tdnf, &history, 0);
    if (rc != 0) return rc;
    const transaction_id = history_get_current_transaction_id(history);
    rc = buildCommandLine(args, &command_line);
    if (rc != 0) return rc;
    rc = runWithHistory(tdnf, ts, history.?, command_line);
    if (rc != 0) return rc;
    if (transaction_id == history_get_current_transaction_id(history)) {
        if (history_add_transaction(history, command_line) != 0)
            return errors.ERROR_TDNF_HISTORY_ERROR;
    } else {
        rc = TDNFMarkAutoInstalled(tdnf, history, solved, 1);
        if (rc != 0) return rc;
    }
    const history_rc = switch (history_args.nCommand) {
        2 => history_restore_auto_flags(history, history_args.nTo),
        3 => history_replay_auto_flags(history, history_args.nTo, history_args.nFrom - 1),
        4 => history_replay_auto_flags(history, history_args.nFrom - 1, history_args.nTo),
        else => 0,
    };
    return if (history_rc == 0) 0 else errors.ERROR_TDNF_HISTORY_ERROR;
}

comptime {
    if (transaction_options.export_entry_points) {
        @export(&runTransactionNative, .{ .name = "TDNFRunTransactionNative" });
        @export(&rpmExecTransaction, .{ .name = "TDNFRpmExecTransaction" });
        @export(&rpmExecHistoryTransaction, .{
            .name = "TDNFRpmExecHistoryTransaction",
        });
    }
}

fn transactionViewAllocationFailureCase(test_allocator: std.mem.Allocator) !void {
    var view = TransactionView{ .alloc = test_allocator };
    defer view.deinit();
    for (0..8) |index| {
        const rc = view.appendRpmdbEntry(
            @intCast(index + 1),
            "injected-rpmdb-header",
        );
        if (rc == errors.ERROR_TDNF_OUT_OF_MEMORY)
            return error.OutOfMemory;
        try std.testing.expectEqual(@as(u32, 0), rc);
    }
    const rc = view.reserveExecutionCapacity(128);
    if (rc == errors.ERROR_TDNF_OUT_OF_MEMORY)
        return error.OutOfMemory;
    try std.testing.expectEqual(@as(u32, 0), rc);
}

test "transaction ABI entry points retain C calling convention" {
    try std.testing.expectEqual(
        std.builtin.CallingConvention.c,
        @typeInfo(@TypeOf(rpmExecTransaction)).@"fn".calling_convention,
    );
    try std.testing.expectEqual(
        std.builtin.CallingConvention.c,
        @typeInfo(@TypeOf(rpmExecHistoryTransaction)).@"fn".calling_convention,
    );
    try std.testing.expectEqual(
        std.builtin.CallingConvention.c,
        @typeInfo(@TypeOf(runTransactionNative)).@"fn".calling_convention,
    );
}

test "transaction view grows during rpmdb iteration then reserves execution appends" {
    var view = TransactionView{ .alloc = std.testing.allocator };
    defer view.deinit();
    try view.entries.ensureTotalCapacity(std.testing.allocator, 1);
    for (0..64) |index| {
        try std.testing.expectEqual(
            @as(u32, 0),
            view.appendRpmdbEntry(
                @intCast(index + 1),
                "injected-rpmdb-header",
            ),
        );
    }
    try std.testing.expectEqual(@as(usize, 64), view.entries.items.len);
    const prior = PriorEntry{
        .hnum = view.entries.items[0].hnum,
        .blob = view.entries.items[0].blob,
    };
    try std.testing.expectEqual(
        @as(u32, 0),
        view.reserveExecutionCapacity(32),
    );
    const reserved_capacity = view.entries.capacity;
    for (0..32) |index| {
        try std.testing.expectEqual(
            @as(u32, 0),
            view.activate(
                "injected-plan-header",
                @intCast(index + 1000),
                true,
            ),
        );
    }
    try std.testing.expectEqual(reserved_capacity, view.entries.capacity);
    try std.testing.expectEqual(@as(u32, 1), prior.hnum);
    try std.testing.expectEqualStrings("injected-rpmdb-header", prior.blob);
    try std.testing.expectEqualStrings(
        prior.blob,
        view.find(prior.hnum).?.blob,
    );
    try std.testing.expectEqual(
        @as(u32, ERROR_TDNF_OVERFLOW),
        view.reserveExecutionCapacity(std.math.maxInt(usize)),
    );
}

test "transaction view maps every initialization allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        transactionViewAllocationFailureCase,
        .{},
    );
}

test "transaction view activation returns OOM instead of aborting" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    var view = TransactionView{ .alloc = failing.allocator() };
    defer view.deinit();
    try std.testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_OUT_OF_MEMORY),
        view.activate("injected-plan-header", 1, true),
    );
    try std.testing.expectEqual(@as(usize, 0), view.entries.items.len);
}

test "transaction path sets retain source identity and merge without duplicates" {
    var first = PathList{};
    defer first.deinit();
    var second = PathList{};
    defer second.deinit();
    const blob_a = "header-a";
    const blob_b = "header-b";
    try std.testing.expectEqual(
        @as(u32, 0),
        first.append("/etc/example", blob_a.ptr, blob_a.len),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        first.append("/etc/example", blob_a.ptr, blob_a.len),
    );
    try std.testing.expectEqual(@as(usize, 1), first.entries.items.len);
    try std.testing.expectEqual(
        @as(u32, 0),
        first.append("/etc/example", blob_b.ptr, blob_b.len),
    );
    try std.testing.expectEqual(@as(usize, 2), first.entries.items.len);
    try std.testing.expectEqual(
        @as(u32, 0),
        second.append("/usr/bin/example", blob_a.ptr, blob_a.len),
    );
    try std.testing.expectEqual(@as(u32, 0), first.merge(&second));
    try std.testing.expectEqual(@as(u32, 0), first.merge(&second));
    try std.testing.expectEqual(@as(usize, 3), first.entries.items.len);
}

test "transaction plan removal marking preserves native order and uniqueness" {
    var erase = std.mem.zeroes(c.TDNF_RPM_TS_ITEM);
    erase.nType = item_erase;
    erase.dwRpmDbHnum = 11;
    var upgrade = std.mem.zeroes(c.TDNF_RPM_TS_ITEM);
    upgrade.nType = item_upgrade;
    var inputs = [_]*c.TDNF_RPM_TS_ITEM{ &erase, &upgrade };
    var order = [_]u32{ 0, 1 };
    var plan_items = [_]c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM{
        .{ .dwPriorOffset = 0, .dwPriorCount = 0 },
        .{ .dwPriorOffset = 0, .dwPriorCount = 2 },
    };
    var priors = [_]u32{ 12, 11 };
    var plan = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN);
    plan.dwItemCount = inputs.len;
    plan.pdwOrderIndices = &order;
    plan.pItems = &plan_items;
    plan.dwPriorHnumCount = priors.len;
    plan.pdwPriorHnums = &priors;
    var view = TransactionView{};
    defer view.deinit();
    try view.entries.append(allocator, .{
        .hnum = 11,
        .blob = "one",
        .order = 0,
    });
    try view.entries.append(allocator, .{
        .hnum = 12,
        .blob = "two",
        .order = 1,
    });
    try std.testing.expectEqual(
        @as(u32, 0),
        markRemovedEntries(&plan, &inputs, &view),
    );
    try std.testing.expect(view.entries.items[0].removed);
    try std.testing.expect(view.entries.items[1].removed);
    try std.testing.expectEqual(@as(u64, 0), view.entries.items[0].removal_order);
    try std.testing.expectEqual(@as(u64, 1), view.entries.items[1].removal_order);
}

test "test-only transactions force all non-mutating native flags" {
    var args = abi.CmdArgs{ .nTestOnly = 1 };
    var tdnf = abi.Tdnf{ .pArgs = &args };
    var ts = std.mem.zeroes(c.TDNFRPMTS);
    ts.nTransFlags = trans_flags.TDNF_RPMTRANS_FLAG_NODOCS;
    const actual = effectiveFlags(&ts, &tdnf);
    try std.testing.expect(actual & trans_flags.TDNF_RPMTRANS_FLAG_TEST != 0);
    try std.testing.expect(actual & trans_flags.TDNF_RPMTRANS_FLAG_NOSCRIPTS != 0);
    try std.testing.expect(actual & trans_flags.TDNF_RPMTRANS_FLAG_NOTRIGGERS != 0);
    try std.testing.expect(actual & trans_flags.TDNF_RPMTRANS_FLAG_JUSTDB != 0);
    try std.testing.expect(actual & trans_flags.TDNF_RPMTRANS_FLAG_NODB != 0);
    try std.testing.expect(actual & trans_flags.TDNF_RPMTRANS_FLAG_NODOCS != 0);
}

test "fixed order transaction represents every replay action shape" {
    const target = FixedOrderPackageIdentity{
        .name = "target",
        .epoch = null,
        .version = "2",
        .release = "1",
        .arch = "noarch",
    };
    const local = FixedOrderLocalRpm{
        .path = "/bundle/target.rpm",
        .identity = target,
    };
    const replaced = FixedOrderPackageIdentity{
        .name = "target",
        .epoch = null,
        .version = "1",
        .release = "1",
        .arch = "noarch",
    };
    const obsoleted = FixedOrderPackageIdentity{
        .name = "prior",
        .epoch = null,
        .version = "1",
        .release = "1",
        .arch = "noarch",
    };
    const items = [_]FixedOrderItem{
        .{ .install = local },
        .{ .erase = .{ .hnum = 10, .identity = obsoleted } },
        .{ .upgrade = .{
            .package = local,
            .priors = &.{
                .{ .hnum = 11, .identity = obsoleted },
                .{ .hnum = 16, .identity = replaced },
            },
        } },
        .{ .downgrade = .{
            .package = local,
            .priors = &.{.{ .hnum = 12, .identity = replaced }},
        } },
        .{ .reinstall = .{
            .package = local,
            .priors = &.{.{ .hnum = 13, .identity = replaced }},
        } },
        .{ .obsolete = .{
            .package = local,
            .priors = &.{
                .{ .hnum = 14, .identity = obsoleted },
                .{ .hnum = 15, .identity = obsoleted },
            },
        } },
        .{ .obsolete = .{
            .package = local,
            .priors = &.{
                .{ .hnum = 14, .identity = obsoleted },
                .{ .hnum = 17, .identity = obsoleted },
            },
        } },
    };
    try validateFixedOrderInput(.{
        .items = &items,
        .order = &.{ 0, 1, 2, 3, 4, 5, 6 },
    });
}

test "fixed order executor compiles against the native engine" {
    var tdnf = abi.Tdnf{};
    try std.testing.expectError(error.InvalidContext, executeFixedOrder(
        &tdnf,
        .{ .items = &.{}, .order = &.{} },
    ));
}

test "fixed upgrade orders its replacement prior before extra obsoletes" {
    const target = FixedOrderPackageIdentity{
        .name = "target",
        .epoch = null,
        .version = "2",
        .release = "1",
        .arch = "noarch",
    };
    const item = FixedOrderItem{ .upgrade = .{
        .package = .{ .path = "/bundle/target.rpm", .identity = target },
        .priors = &.{
            .{ .hnum = 20, .identity = .{
                .name = "retired",
                .epoch = null,
                .version = "1",
                .release = "1",
                .arch = "noarch",
            } },
            .{ .hnum = 21, .identity = .{
                .name = "target",
                .epoch = null,
                .version = "1",
                .release = "1",
                .arch = "noarch",
            } },
        },
    } };
    try validateFixedOrderInput(.{ .items = &.{item}, .order = &.{0} });
    var ordered: [2]FixedOrderRpmDbRow = undefined;
    try copyFixedPriorsInExecutionOrder(item, &ordered);
    try std.testing.expectEqual(@as(u32, 21), ordered[0].hnum);
    try std.testing.expectEqual(@as(u32, 20), ordered[1].hnum);
}

test "shared obsolete priors are associated twice but marked once" {
    var first = std.mem.zeroes(c.TDNF_RPM_TS_ITEM);
    first.nType = item_obsolete;
    var second = std.mem.zeroes(c.TDNF_RPM_TS_ITEM);
    second.nType = item_obsolete;
    var inputs = [_]*c.TDNF_RPM_TS_ITEM{ &first, &second };
    var order = [_]u32{ 0, 1 };
    var plan_items = [_]c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM{
        .{ .dwPriorOffset = 0, .dwPriorCount = 1 },
        .{ .dwPriorOffset = 1, .dwPriorCount = 1 },
    };
    var priors = [_]u32{ 42, 42 };
    var plan = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN);
    plan.dwItemCount = inputs.len;
    plan.pdwOrderIndices = &order;
    plan.pItems = &plan_items;
    plan.dwPriorHnumCount = priors.len;
    plan.pdwPriorHnums = &priors;
    var view = TransactionView{};
    defer view.deinit();
    try view.entries.append(allocator, .{
        .hnum = 42,
        .blob = "shared",
        .order = 0,
    });
    try std.testing.expectEqual(
        @as(u32, 0),
        markRemovedEntries(&plan, &inputs, &view),
    );
    try std.testing.expect(view.entries.items[0].removed);
    try std.testing.expectEqual(@as(u64, 0), view.entries.items[0].removal_order);
    try std.testing.expectEqual(@as(u32, 42), priors[0]);
    try std.testing.expectEqual(@as(u32, 42), priors[1]);

    const execution_priors = [_]PriorEntry{
        .{ .hnum = 42, .blob = "shared" },
        .{ .hnum = 43, .blob = "unique" },
    };
    try std.testing.expectEqual(
        @as(?usize, 0),
        try selectReplacementPriorIndex(item_obsolete, &execution_priors, &view),
    );
    view.entries.items[0].active = false;
    try view.entries.append(allocator, .{
        .hnum = 43,
        .blob = "unique",
        .order = 1,
    });
    try std.testing.expectEqual(
        @as(?usize, 1),
        try selectReplacementPriorIndex(item_obsolete, &execution_priors, &view),
    );
    view.entries.items[1].active = false;
    try std.testing.expectEqual(
        @as(?usize, null),
        try selectReplacementPriorIndex(item_obsolete, &execution_priors, &view),
    );
}

test "fixed downgrade retains upgrade installation semantics" {
    const identity = FixedOrderPackageIdentity{
        .name = "target",
        .epoch = null,
        .version = "1",
        .release = "1",
        .arch = "noarch",
    };
    const item = FixedOrderItem{ .downgrade = .{
        .package = .{ .path = "/bundle/target.rpm", .identity = identity },
        .priors = &.{.{ .hnum = 7, .identity = identity }},
    } };
    try std.testing.expectEqual(item_downgrade, fixedItemType(item));
    try std.testing.expectEqual(
        @as(?c_uint, c.TDNF_RPM_INSTALL_KIND_UPGRADE),
        installKindForItemType(fixedItemType(item)),
    );
}

test "fixed order rejects missing duplicate and malformed indices" {
    const identity = FixedOrderPackageIdentity{
        .name = "installed",
        .epoch = null,
        .version = "1",
        .release = "1",
        .arch = "noarch",
    };
    const items = [_]FixedOrderItem{
        .{ .erase = .{ .hnum = 1, .identity = identity } },
        .{ .erase = .{ .hnum = 2, .identity = identity } },
    };
    try std.testing.expectError(error.MalformedOrder, validateFixedOrderInput(.{
        .items = &items,
        .order = &.{0},
    }));
    try std.testing.expectError(error.MalformedOrder, validateFixedOrderInput(.{
        .items = &items,
        .order = &.{ 0, 0 },
    }));
    try std.testing.expectError(error.MalformedOrder, validateFixedOrderInput(.{
        .items = &items,
        .order = &.{ 0, 2 },
    }));
}

test "fixed order iterator preserves the recorded execution sequence" {
    var order = [_]u32{ 2, 0, 1 };
    var plan = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN);
    plan.dwItemCount = order.len;
    plan.pdwOrderIndices = &order;
    var iterator = PlanOrderIterator{ .plan = &plan };
    try std.testing.expectEqual(@as(?usize, 2), iterator.next());
    try std.testing.expectEqual(@as(?usize, 0), iterator.next());
    try std.testing.expectEqual(@as(?usize, 1), iterator.next());
    try std.testing.expectEqual(@as(?usize, null), iterator.next());
}

test "fixed prior mismatches are rejected before transaction view mutation" {
    const rpmpkg = @import("rpm_package_test");
    const blob = try rpmpkg.makeMinimalHeaderForTest(
        std.testing.allocator,
        "installed",
        "1",
        "1",
        "noarch",
    );
    defer std.testing.allocator.free(blob);

    var item = std.mem.zeroes(c.TDNF_RPM_TS_ITEM);
    item.nType = item_install;
    var input_items = [_]*c.TDNF_RPM_TS_ITEM{&item};
    var order = [_]u32{0};
    var plan_items = [_]c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM{
        .{ .dwPriorOffset = 0, .dwPriorCount = 1 },
    };
    var prior_hnums = [_]u32{42};
    var plan = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN);
    plan.dwItemCount = 1;
    plan.pdwOrderIndices = &order;
    plan.pItems = &plan_items;
    plan.dwPriorHnumCount = 1;
    plan.pdwPriorHnums = &prior_hnums;
    var ts = std.mem.zeroes(c.TDNFRPMTS);
    ts.dwTransactionItemCount = 1;
    var view = TransactionView{};
    defer view.deinit();
    try view.entries.append(allocator, .{
        .hnum = 42,
        .blob = blob,
        .order = 0,
    });

    const mismatched = FixedOrderRpmDbRow{
        .hnum = 42,
        .identity = .{
            .name = "installed",
            .epoch = null,
            .version = "different",
            .release = "1",
            .arch = "noarch",
        },
    };
    var expected = [_]FixedOrderExpectedItem{
        .{ .priors = &.{mismatched} },
    };
    var failure: FixedOrderValidationFailure = .none;
    try std.testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        prevalidatePlanStructure(
            &ts,
            &plan,
            &input_items,
            &view,
            &expected,
            &failure,
        ),
    );
    try std.testing.expectEqual(
        FixedOrderValidationFailure.prior_mismatch,
        failure,
    );
    try std.testing.expect(view.entries.items[0].active);
    try std.testing.expect(view.entries.items[0].db_visible);
    try std.testing.expect(!view.entries.items[0].removed);

    prior_hnums[0] = 43;
    const missing = FixedOrderRpmDbRow{
        .hnum = 43,
        .identity = mismatched.identity,
    };
    expected[0].priors = &.{missing};
    failure = .none;
    try std.testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_INVALID_PARAMETER),
        prevalidatePlanStructure(
            &ts,
            &plan,
            &input_items,
            &view,
            &expected,
            &failure,
        ),
    );
    try std.testing.expectEqual(
        FixedOrderValidationFailure.prior_mismatch,
        failure,
    );
    try std.testing.expect(view.entries.items[0].active);
    try std.testing.expect(view.entries.items[0].db_visible);
    try std.testing.expect(!view.entries.items[0].removed);
}

test "normal transaction still prepares order and checks before execution" {
    const Probe = struct {
        var sequence: [2]u8 = .{ 0, 0 };
        var count: usize = 0;
        var plan = std.mem.zeroes(c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN);

        fn prepare(ts: *c.TDNFRPMTS, _: *abi.Tdnf) u32 {
            sequence[count] = 1;
            count += 1;
            ts.pNativePlan = &plan;
            return 0;
        }

        fn execute(
            _: ?*c.TDNFRPMTS,
            _: ?*abi.Tdnf,
            supplied: ?*const c.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN,
        ) u32 {
            sequence[count] = if (supplied == &plan) 2 else 9;
            count += 1;
            return 0;
        }

        fn report(_: *c.TDNFRPMTS) void {}
    };
    Probe.sequence = .{ 0, 0 };
    Probe.count = 0;
    var ts = std.mem.zeroes(c.TDNFRPMTS);
    ts.dwTransactionItemCount = 1;
    var tdnf = abi.Tdnf{};
    try std.testing.expectEqual(
        @as(u32, 0),
        runNormalTransactionWith(
            &ts,
            &tdnf,
            Probe.prepare,
            Probe.execute,
            Probe.report,
        ),
    );
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, &Probe.sequence);
}
