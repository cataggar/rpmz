const std = @import("std");

const api = @import("api.zig");
const history_db = @import("db.zig");
const history_store = @import("store.zig");

const rpmz_rpmdb_iter = opaque {};
const rpmz_rpm_config = @import("rpm_txn_config").TxnConfig;

fn transactionPlanTestWriteHistoryFixture(
    raw_path: ?[*:0]const u8,
) callconv(.c) c_int {
    const path = raw_path orelse return -1;
    var db = history_db.Database.init(path) catch return -1;
    defer db.close();
    history_store.ensureAllTables(db) catch return -1;
    inline for (.{
        "DELETE FROM flag_set;",
        "DELETE FROM names;",
        "DELETE FROM trans_items;",
        "DELETE FROM transactions;",
        "DELETE FROM rpms;",
    }) |statement| db.exec(statement, .{}) catch return -1;
    db.exec(
        "INSERT INTO rpms(Id, nevra) VALUES " ++
            "(1, 'app-1-1.x86_64'), " ++
            "(2, 'missing-history-1-1.x86_64'), " ++
            "(3, 'installed-file-provider-1-1.x86_64'), " ++
            "(4, 'absent-history-1-1.x86_64'), " ++
            "(5, 'excluded-1-1.x86_64');",
        .{},
    ) catch return -1;
    db.exec(
        "INSERT INTO transactions(Id, cookie, cmdline, timestamp, type) " ++
            "VALUES (1, '', 'history fixture', 1, 0), " ++
            "(2, '', 'history fixture current', 2, 1);",
        .{},
    ) catch return -1;
    db.exec(
        "INSERT INTO trans_items(trans_id, type, rpm_id) VALUES " ++
            "(1, 0, 3), (1, 0, 4), (2, 2, 3), (2, 2, 4), " ++
            "(2, 1, 1), (2, 1, 2), (2, 1, 5);",
        .{},
    ) catch return -1;
    db.exec("INSERT INTO names(Id, name) VALUES (1, 'app');", .{}) catch
        return -1;
    db.exec(
        "INSERT INTO flag_set(trans_id, name_id, value) VALUES " ++
            "(1, 1, 0), (2, 1, 0);",
        .{},
    ) catch return -1;
    return 0;
}

fn transactionPlanTestWriteExcludedHistoryFixture(
    raw_path: ?[*:0]const u8,
) callconv(.c) c_int {
    if (transactionPlanTestWriteHistoryFixture(raw_path) != 0) return -1;
    const path = raw_path orelse return -1;
    var db = history_db.Database.init(path) catch return -1;
    defer db.close();
    db.exec("DELETE FROM trans_items;", .{}) catch return -1;
    db.exec("DELETE FROM rpms;", .{}) catch return -1;
    db.exec(
        "INSERT INTO rpms(Id, nevra) VALUES " ++
            "(1, 'installed-file-provider-1-1.x86_64'), " ++
            "(2, 'excluded-1-1.x86_64');",
        .{},
    ) catch return -1;
    db.exec(
        "INSERT INTO trans_items(trans_id, type, rpm_id) VALUES " ++
            "(1, 0, 1), (2, 1, 2);",
        .{},
    ) catch return -1;
    return 0;
}

comptime {
    @export(&transactionPlanTestWriteHistoryFixture, .{
        .name = "TDNFTransactionPlanTestWriteHistoryFixture",
        .visibility = .hidden,
    });
    @export(&transactionPlanTestWriteExcludedHistoryFixture, .{
        .name = "TDNFTransactionPlanTestWriteExcludedHistoryFixture",
        .visibility = .hidden,
    });
}

extern fn rpmz_rpmdb_cookie(root: ?[*:0]const u8) ?[*:0]u8;
extern fn rpmz_rpmdb_cookie_config(config: *const rpmz_rpm_config) ?[*:0]u8;
extern fn rpmz_rpmdb_iter_open(root: ?[*:0]const u8) ?*rpmz_rpmdb_iter;
extern fn rpmz_rpmdb_iter_open_config(config: *const rpmz_rpm_config) ?*rpmz_rpmdb_iter;
extern fn rpmz_rpmdb_iter_close(it: ?*rpmz_rpmdb_iter) void;
extern fn rpmz_rpmdb_iter_next_nevra(it: *rpmz_rpmdb_iter, nevra_out: *?[*:0]u8) c_int;
extern fn rpmz_rpmdb_string_free(s: ?[*:0]u8) void;

const RealRpmdb = struct {
    pub const Source = ?[*:0]const u8;

    pub fn cookie(root: ?[*:0]const u8) ![:0]u8 {
        const raw = rpmz_rpmdb_cookie(root) orelse return error.RpmdbError;
        defer rpmz_rpmdb_string_free(raw);
        return try std.heap.c_allocator.dupeZ(u8, std.mem.span(raw));
    }

    pub fn collectNevras(allocator: std.mem.Allocator, root: ?[*:0]const u8) ![][:0]u8 {
        const iter = rpmz_rpmdb_iter_open(root) orelse return error.RpmdbError;
        defer rpmz_rpmdb_iter_close(iter);
        return collectNevrasFromIter(allocator, iter);
    }
};

const ConfigRpmdb = struct {
    pub const Source = *const rpmz_rpm_config;

    pub fn cookie(config: Source) ![:0]u8 {
        const raw = rpmz_rpmdb_cookie_config(config) orelse return error.RpmdbError;
        defer rpmz_rpmdb_string_free(raw);
        return try std.heap.c_allocator.dupeZ(u8, std.mem.span(raw));
    }

    pub fn collectNevras(allocator: std.mem.Allocator, config: Source) ![][:0]u8 {
        const iter = rpmz_rpmdb_iter_open_config(config) orelse return error.RpmdbError;
        defer rpmz_rpmdb_iter_close(iter);
        return collectNevrasFromIter(allocator, iter);
    }
};

fn collectNevrasFromIter(
    allocator: std.mem.Allocator,
    iter: *rpmz_rpmdb_iter,
) ![][:0]u8 {
    var nevras: std.ArrayList([:0]u8) = .empty;
    errdefer {
        for (nevras.items) |nevra| {
            allocator.free(nevra);
        }
        nevras.deinit(allocator);
    }

    while (true) {
        var raw: ?[*:0]u8 = null;
        const rc = rpmz_rpmdb_iter_next_nevra(iter, &raw);
        if (rc == 0) break;
        if (rc < 0 or raw == null) return error.RpmdbError;

        defer rpmz_rpmdb_string_free(raw);
        try nevras.append(allocator, try allocator.dupeZ(u8, std.mem.span(raw.?)));
    }
    return try nevras.toOwnedSlice(allocator);
}

const Impl = api.Api(RealRpmdb);
const ConfigImpl = api.Api(ConfigRpmdb);

pub const HistoryCtx = api.HistoryCtx;
pub const HistoryDelta = api.HistoryDelta;
pub const HistoryFlagsDelta = api.HistoryFlagsDelta;
pub const HistoryTransaction = api.HistoryTransaction;
pub const HistoryNevraMap = api.HistoryNevraMap;

pub export fn create_history_ctx(db_filename: ?[*:0]const u8) ?*HistoryCtx {
    const path = db_filename orelse return null;
    return Impl.createHistoryCtx(path) catch null;
}

pub export fn history_open_config(
    config: ?*const rpmz_rpm_config,
    persist_dir: ?[*:0]const u8,
    must_exist: c_int,
    output: ?*?*HistoryCtx,
) c_int {
    const out = output orelse return -1;
    out.* = null;
    const rpm_config = config orelse return -1;
    const persist = persist_dir orelse return -1;
    const context = ConfigImpl.createHistoryCtxConfig(
        rpm_config,
        std.mem.span(persist),
        must_exist != 0,
    ) catch |err| return switch (err) {
        error.NotFound => 1,
        error.InvalidDirectory => 2,
        else => -1,
    };
    out.* = context;
    return 0;
}

pub export fn destroy_history_ctx(ctx: ?*HistoryCtx) void {
    Impl.destroyHistoryCtx(ctx);
}

pub export fn history_get_current_transaction_id(ctx: ?*HistoryCtx) c_int {
    const value = ctx orelse return 0;
    return Impl.historyGetCurrentTransactionId(value);
}

pub export fn history_sync(ctx: ?*HistoryCtx, root: ?[*:0]const u8) c_int {
    const value = ctx orelse return -1;
    Impl.historySync(value, root) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_sync_config(
    ctx: ?*HistoryCtx,
    config: ?*const rpmz_rpm_config,
) c_int {
    const value = ctx orelse return -1;
    const rpm_config = config orelse return -1;
    ConfigImpl.historySync(value, rpm_config) catch |err| {
        return @import("db.zig").errorToRc(err);
    };
    return 0;
}

pub export fn history_nevra_from_id(ctx: ?*HistoryCtx, id: c_int) ?[*:0]u8 {
    const value = ctx orelse return null;
    return Impl.historyNevraFromId(value, id) catch null;
}

pub export fn history_nevra_map(ctx: ?*HistoryCtx) ?*HistoryNevraMap {
    const value = ctx orelse return null;
    return Impl.historyNevraMap(value) catch null;
}

pub export fn history_free_nevra_map(map: ?*HistoryNevraMap) void {
    Impl.historyFreeNevraMap(map);
}

pub export fn history_get_nevra(map: ?*HistoryNevraMap, id: c_int) ?[*:0]u8 {
    return Impl.historyGetNevra(map, id);
}

pub export fn history_free_delta(delta: ?*HistoryDelta) void {
    Impl.historyFreeDelta(delta);
}

pub export fn history_get_delta(ctx: ?*HistoryCtx, trans_id: c_int) ?*HistoryDelta {
    const value = ctx orelse return null;
    return Impl.historyGetDelta(value, trans_id) catch null;
}

pub export fn history_get_delta_range(
    ctx: ?*HistoryCtx,
    trans_id0: c_int,
    trans_id1: c_int,
) ?*HistoryDelta {
    const value = ctx orelse return null;
    return Impl.historyGetDeltaRange(value, trans_id0, trans_id1) catch null;
}

pub export fn history_add_transaction(ctx: ?*HistoryCtx, cmdline: ?[*:0]const u8) c_int {
    const value = ctx orelse return -1;
    const line = cmdline orelse return -1;
    Impl.historyAddTransaction(value, line) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_record_state(ctx: ?*HistoryCtx) c_int {
    const value = ctx orelse return -1;
    Impl.historyRecordState(value) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_update_state(
    ctx: ?*HistoryCtx,
    root: ?[*:0]const u8,
    cmdline: ?[*:0]const u8,
) c_int {
    const value = ctx orelse return -1;
    const line = cmdline orelse return -1;
    Impl.historyUpdateState(value, root, line) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_update_state_config(
    ctx: ?*HistoryCtx,
    config: ?*const rpmz_rpm_config,
    cmdline: ?[*:0]const u8,
) c_int {
    const value = ctx orelse return -1;
    const rpm_config = config orelse return -1;
    const line = cmdline orelse return -1;
    ConfigImpl.historyUpdateState(value, rpm_config, line) catch |err| {
        return @import("db.zig").errorToRc(err);
    };
    return 0;
}
pub export fn history_get_transactions(
    ctx: ?*HistoryCtx,
    ptas: *?[*]HistoryTransaction,
    pcount: *c_int,
    reverse: c_int,
    from: c_int,
    to: c_int,
) c_int {
    const value = ctx orelse return -1;
    Impl.historyGetTransactions(value, ptas, pcount, reverse, from, to) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_free_transactions(tas: ?[*]HistoryTransaction, count: c_int) void {
    Impl.historyFreeTransactions(tas, count);
}

pub export fn history_set_auto_flag(
    ctx: ?*HistoryCtx,
    name: ?[*:0]const u8,
    value: c_int,
) c_int {
    const value_ctx = ctx orelse return -1;
    const value_name = name orelse return -1;
    Impl.historySetAutoFlag(value_ctx, value_name, value) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_get_auto_flag(
    ctx: ?*HistoryCtx,
    name: ?[*:0]const u8,
    pvalue: *c_int,
) c_int {
    const value_ctx = ctx orelse return -1;
    const value_name = name orelse return -1;
    Impl.historyGetAutoFlag(value_ctx, value_name, pvalue) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_restore_auto_flags(ctx: ?*HistoryCtx, trans_id: c_int) c_int {
    const value = ctx orelse return -1;
    Impl.historyRestoreAutoFlags(value, trans_id) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_replay_auto_flags(ctx: ?*HistoryCtx, from: c_int, to: c_int) c_int {
    const value = ctx orelse return -1;
    Impl.historyReplayAutoFlags(value, from, to) catch |err| return @import("db.zig").errorToRc(err);
    return 0;
}

pub export fn history_free_flags_delta(hfd: ?*HistoryFlagsDelta) void {
    Impl.historyFreeFlagsDelta(hfd);
}

pub export fn history_get_flags_delta(
    ctx: ?*HistoryCtx,
    from: c_int,
    to: c_int,
) ?*HistoryFlagsDelta {
    const value = ctx orelse return null;
    return Impl.historyGetFlagsDelta(value, from, to) catch null;
}
