const std = @import("std");
const builtin = @import("builtin");
const sqlite = @import("sqlite");
const confined_sqlite = @import("confined_sqlite");
const txn_config = @import("rpm_txn_config");

extern fn mkdirat(
    dir_fd: c_int,
    path: [*:0]const u8,
    mode: c_uint,
) callconv(.c) c_int;

pub const busy_timeout_ms: c_int = 5000;

var test_dir_close_probe: ?*const fn (?*anyopaque, c_int) void = null;
var test_dir_close_probe_context: ?*anyopaque = null;

pub const Error = sqlite.Error || error{
    BusyTimeoutFailed,
    InvalidDirectory,
    NotFound,
    OutOfMemory,
    SyscallFailed,
    UnsafePath,
};

pub const Database = struct {
    raw: sqlite.Database,
    dir_fd: c_int,
    connection: ?confined_sqlite.Connection,

    pub fn init(path: [*:0]const u8) Error!Database {
        return initWithBusyTimeout(path, applyDefaultBusyTimeout);
    }

    fn initWithBusyTimeout(
        path: [*:0]const u8,
        apply_timeout: *const fn (*Database) Error!void,
    ) Error!Database {
        const path_slice = std.mem.span(path);
        const slash = std.mem.lastIndexOfScalar(u8, path_slice, '/');
        const absolute = path_slice.len != 0 and path_slice[0] == '/';
        const parent_start: usize = if (absolute) 1 else 0;
        const parent_path = if (slash) |index|
            if (index <= parent_start)
                ""
            else
                path_slice[parent_start..index]
        else
            "";
        const basename = if (slash) |index|
            path_slice[index + 1 ..]
        else
            path_slice;
        if (basename.len == 0 or
            std.mem.indexOfScalar(u8, basename, '/') != null)
        {
            return error.UnsafePath;
        }
        const start_fd = std.c.open(if (absolute) "/" else ".", .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (start_fd < 0) return error.SyscallFailed;
        var dir_fd = start_fd;
        var owns_dir_fd = true;
        errdefer {
            if (owns_dir_fd) _ = std.c.close(dir_fd);
        }
        var components = std.mem.splitScalar(u8, parent_path, '/');
        while (components.next()) |component| {
            if (component.len == 0 or
                std.mem.eql(u8, component, ".") or
                std.mem.eql(u8, component, ".."))
            {
                return error.UnsafePath;
            }
            const component_z = try std.heap.c_allocator.dupeZ(
                u8,
                component,
            );
            defer std.heap.c_allocator.free(component_z);
            const next_fd = std.c.openat(dir_fd, component_z.ptr, .{
                .ACCMODE = .RDONLY,
                .DIRECTORY = true,
                .CLOEXEC = true,
                .NOFOLLOW = true,
            });
            if (next_fd < 0) return error.UnsafePath;
            _ = std.c.close(dir_fd);
            dir_fd = next_fd;
        }
        owns_dir_fd = false;
        var db = try openOwnedDirectory(dir_fd, basename, true);
        errdefer db.close();
        try apply_timeout(&db);
        return db;
    }

    pub fn initConfig(
        config: *const txn_config.TxnConfig,
        persist_dir: []const u8,
        must_exist: bool,
    ) Error!Database {
        const root_fd = openConfigRoot(config) catch
            return error.InvalidDirectory;
        defer _ = std.c.close(root_fd);
        const dir_fd = (openDirectoryTree(
            root_fd,
            persist_dir,
            !must_exist,
        ) catch return error.InvalidDirectory) orelse return error.NotFound;
        var db = openOwnedDirectory(
            dir_fd,
            "history.db",
            !must_exist,
        ) catch |err| return switch (err) {
            error.NotFound => error.NotFound,
            else => err,
        };
        errdefer db.close();
        try db.busyTimeout(busy_timeout_ms);
        return db;
    }

    pub fn fromPtr(ptr: ?*sqlite.c.sqlite3) Database {
        return .{
            .raw = .{ .ptr = ptr },
            .dir_fd = -1,
            .connection = null,
        };
    }

    pub fn close(self: *Database) void {
        _ = self.tryClose();
    }

    pub fn tryClose(self: *Database) bool {
        if (self.connection) |*connection| {
            if (!connection.tryClose()) return false;
            self.connection = null;
            self.raw.ptr = null;
        } else {
            if (self.raw.ptr != null and
                sqlite.c.sqlite3_close(self.raw.ptr) != sqlite.c.SQLITE_OK)
            {
                return false;
            }
            self.raw.ptr = null;
        }
        if (self.dir_fd >= 0) {
            const closed_fd = self.dir_fd;
            _ = std.c.close(closed_fd);
            self.dir_fd = -1;
            if (builtin.is_test) {
                if (test_dir_close_probe) |probe|
                    probe(test_dir_close_probe_context, closed_fd);
            }
        }
        return true;
    }

    pub fn busyTimeout(self: Database, milliseconds: c_int) Error!void {
        const rc = sqlite.c.sqlite3_busy_timeout(self.raw.ptr, milliseconds);
        if (rc != sqlite.c.SQLITE_OK) {
            return error.BusyTimeoutFailed;
        }
    }

    pub fn lastInsertRowId(self: Database) i64 {
        return sqlite.c.sqlite3_last_insert_rowid(self.raw.ptr);
    }

    pub fn begin(self: Database) !void {
        try self.raw.exec("BEGIN TRANSACTION;", .{});
    }

    pub fn commit(self: Database) !void {
        try self.raw.exec("COMMIT;", .{});
    }

    pub fn rollback(self: Database) !void {
        try self.raw.exec("ROLLBACK;", .{});
    }

    pub fn exec(self: Database, sql: []const u8, params: anytype) !void {
        try self.raw.exec(sql, params);
    }

    pub inline fn prepare(
        self: Database,
        comptime Params: type,
        comptime Result: type,
        sql: []const u8,
    ) !sqlite.Statement(Params, Result) {
        return self.raw.prepare(Params, Result, sql);
    }

    pub fn errmsg(self: Database) []const u8 {
        return if (self.raw.errmsg()) |msg| std.mem.span(msg) else "";
    }
};

fn applyDefaultBusyTimeout(db: *Database) Error!void {
    try db.busyTimeout(busy_timeout_ms);
}

fn duplicateFdCloexec(fd: c_int) c_int {
    return std.c.fcntl(
        fd,
        std.c.F.DUPFD_CLOEXEC,
        @as(c_int, 0),
    );
}

fn openOwnedDirectory(
    dir_fd: c_int,
    basename: []const u8,
    create: bool,
) Error!Database {
    errdefer _ = std.c.close(dir_fd);
    var connection = confined_sqlite.openAt(
        std.heap.c_allocator,
        dir_fd,
        basename,
        .{ .mode = .read_write, .create = create },
    ) catch |err| return switch (err) {
        error.NotFound => error.NotFound,
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidPath,
        error.PathChanged,
        error.UnsafeFile,
        => error.UnsafePath,
        error.SqliteOpenFailed,
        error.VfsFailed,
        => error.SQLITE_CANTOPEN,
        error.SyscallFailed => error.SyscallFailed,
    };
    errdefer connection.close();
    return .{
        .raw = .{ .ptr = connection.db },
        .dir_fd = dir_fd,
        .connection = connection,
    };
}

fn openConfigRoot(config: *const txn_config.TxnConfig) Error!c_int {
    if (config.pinnedInstallRootFd()) |fd| {
        const duplicate = duplicateFdCloexec(fd);
        if (duplicate < 0) return error.SyscallFailed;
        return duplicate;
    }
    const root = config.installRoot();
    if (root.len == 0 or root[0] != '/') return error.UnsafePath;
    const filesystem_root = std.c.open("/", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    if (filesystem_root < 0) return error.SyscallFailed;
    if (std.mem.eql(u8, root, "/")) return filesystem_root;
    defer _ = std.c.close(filesystem_root);
    return (try openDirectoryTree(filesystem_root, root, false)) orelse
        return error.NotFound;
}

fn openDirectoryTree(
    root_fd: c_int,
    raw_path: []const u8,
    create: bool,
) Error!?c_int {
    const path = std.mem.trim(u8, raw_path, "/");
    if (path.len == 0) {
        const duplicate = duplicateFdCloexec(root_fd);
        if (duplicate < 0) return error.SyscallFailed;
        return duplicate;
    }
    var current = duplicateFdCloexec(root_fd);
    if (current < 0) return error.SyscallFailed;
    errdefer _ = std.c.close(current);
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (component.len == 0 or
            std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, ".."))
        {
            return error.UnsafePath;
        }
        const component_z = std.heap.c_allocator.dupeZ(
            u8,
            component,
        ) catch return error.OutOfMemory;
        defer std.heap.c_allocator.free(component_z);
        var next = std.c.openat(current, component_z.ptr, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (next < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.NOENT) and create)
        {
            if (mkdirat(current, component_z.ptr, 0o755) != 0 and
                std.c._errno().* != @intFromEnum(std.posix.E.EXIST))
            {
                return error.SyscallFailed;
            }
            next = std.c.openat(current, component_z.ptr, .{
                .ACCMODE = .RDONLY,
                .DIRECTORY = true,
                .CLOEXEC = true,
                .NOFOLLOW = true,
            });
        }
        if (next < 0) {
            if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT)) {
                _ = std.c.close(current);
                return null;
            }
            return error.UnsafePath;
        }
        _ = std.c.close(current);
        current = next;
    }
    return current;
}

pub fn dupeZ(bytes: []const u8) ![*:0]u8 {
    return (try std.heap.c_allocator.dupeZ(u8, bytes)).ptr;
}

pub fn freeZ(value: ?[*:0]u8) void {
    if (value) |ptr| {
        std.heap.c_allocator.free(std.mem.span(ptr));
    }
}

pub fn textFromPtr(value: ?[*:0]const u8) ?sqlite.Text {
    return if (value) |ptr| sqlite.text(std.mem.span(ptr)) else null;
}

pub fn dupeOptionalText(value: ?sqlite.Text) !?[*:0]u8 {
    return if (value) |text| try dupeZ(text.data) else null;
}

pub fn errorToRc(err: anyerror) c_int {
    return switch (err) {
        else => -1,
    };
}

pub fn errorToDwError(err: anyerror) u32 {
    return switch (err) {
        else => 1,
    };
}

test "history init transfers its directory before a later timeout failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/history.db",
        .{base},
        0,
    );
    defer std.testing.allocator.free(path);
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const source_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(source_fd >= 0);
    defer _ = std.c.close(source_fd);

    const ProbeContext = struct {
        source_fd: c_int,
        reused_fd: c_int = -1,
    };
    const Probe = struct {
        fn run(raw: ?*anyopaque, closed_fd: c_int) void {
            const context: *ProbeContext = @ptrCast(@alignCast(raw.?));
            context.reused_fd = std.c.fcntl(
                context.source_fd,
                std.c.F.DUPFD_CLOEXEC,
                closed_fd,
            );
        }

        fn fail(_: *Database) Error!void {
            return error.BusyTimeoutFailed;
        }
    };
    var context = ProbeContext{ .source_fd = source_fd };
    test_dir_close_probe = Probe.run;
    test_dir_close_probe_context = &context;
    defer {
        test_dir_close_probe = null;
        test_dir_close_probe_context = null;
    }
    try std.testing.expectError(
        error.BusyTimeoutFailed,
        Database.initWithBusyTimeout(path.ptr, Probe.fail),
    );
    try std.testing.expect(context.reused_fd >= 0);
    defer _ = std.c.close(context.reused_fd);
    try std.testing.expect(
        std.c.fcntl(context.reused_fd, std.c.F.GETFD) >= 0,
    );
}

test "history database stays in pinned no-follow parent" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root/db");
    try tmp.dir.createDirPath(std.testing.io, "outside");
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(std.testing.io, &cwd_buf);
    const cwd = cwd_buf[0..cwd_len];
    const base = try std.fmt.allocPrint(
        allocator,
        "{s}/.zig-cache/tmp/{s}",
        .{ cwd, tmp.sub_path },
    );
    defer allocator.free(base);
    const db_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/root/db",
        .{base},
    );
    defer allocator.free(db_dir);
    const parked = try std.fmt.allocPrint(
        allocator,
        "{s}/root/parked",
        .{base},
    );
    defer allocator.free(parked);
    const outside = try std.fmt.allocPrint(
        allocator,
        "{s}/outside",
        .{base},
    );
    defer allocator.free(outside);
    const db_path = try std.fmt.allocPrintSentinel(
        allocator,
        "{s}/history.db",
        .{db_dir},
        0,
    );
    defer allocator.free(db_path);
    var database = try Database.init(db_path.ptr);
    const db_dir_z = try allocator.dupeZ(u8, db_dir);
    defer allocator.free(db_dir_z);
    const parked_z = try allocator.dupeZ(u8, parked);
    defer allocator.free(parked_z);
    const outside_z = try allocator.dupeZ(u8, outside);
    defer allocator.free(outside_z);
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.rename(db_dir_z.ptr, parked_z.ptr),
    );
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.symlink(outside_z.ptr, db_dir_z.ptr),
    );
    database.exec(
        "CREATE TABLE pinned(value INTEGER);",
        .{},
    ) catch {};
    database.close();
    try tmp.dir.access(
        std.testing.io,
        "root/parked/history.db",
        .{},
    );
    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.access(std.testing.io, "outside/history.db", .{}),
    );

    const escaped_path = try std.fmt.allocPrintSentinel(
        allocator,
        "{s}/root/db/escaped.db",
        .{base},
        0,
    );
    defer allocator.free(escaped_path);
    try std.testing.expectError(
        error.UnsafePath,
        Database.init(escaped_path.ptr),
    );
}

test "history config stays under pinned root and rejects database symlinks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root");
    try tmp.dir.createDirPath(std.testing.io, "outside");
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const root = try std.fs.path.join(allocator, &.{ base, "root" });
    defer allocator.free(root);
    const parked = try std.fs.path.join(allocator, &.{ base, "parked" });
    defer allocator.free(parked);
    const outside = try std.fs.path.join(allocator, &.{ base, "outside" });
    defer allocator.free(outside);
    const root_z = try allocator.dupeZ(u8, root);
    defer allocator.free(root_z);
    const parked_z = try allocator.dupeZ(u8, parked);
    defer allocator.free(parked_z);
    const outside_z = try allocator.dupeZ(u8, outside);
    defer allocator.free(outside_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    var base_config = try txn_config.TxnConfig.init(allocator, root);
    defer base_config.deinit();
    var pinned = try base_config.cloneWithPinnedInstallRoot(
        allocator,
        root,
        root_fd,
    );
    defer pinned.deinit();

    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.rename(root_z.ptr, parked_z.ptr),
    );
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.symlink(outside_z.ptr, root_z.ptr),
    );

    var db = try Database.initConfig(&pinned, "/var/lib/tdnf", false);
    try std.testing.expect(
        (std.c.fcntl(db.dir_fd, std.c.F.GETFD) & std.c.FD_CLOEXEC) != 0,
    );
    const main_fd = try db.connection.?.duplicateMainFd();
    defer _ = std.c.close(main_fd);
    try std.testing.expect(
        (std.c.fcntl(main_fd, std.c.F.GETFD) & std.c.FD_CLOEXEC) != 0,
    );
    var timeout_statement: ?*sqlite.c.sqlite3_stmt = null;
    try std.testing.expectEqual(
        sqlite.c.SQLITE_OK,
        sqlite.c.sqlite3_prepare_v2(
            db.raw.ptr,
            "PRAGMA busy_timeout;",
            -1,
            &timeout_statement,
            null,
        ),
    );
    try std.testing.expectEqual(
        sqlite.c.SQLITE_ROW,
        sqlite.c.sqlite3_step(timeout_statement),
    );
    try std.testing.expectEqual(
        busy_timeout_ms,
        sqlite.c.sqlite3_column_int(timeout_statement, 0),
    );
    try db.exec("CREATE TABLE pinned(value INTEGER);", .{});
    const retained_dir_fd = db.dir_fd;
    try std.testing.expect(!db.tryClose());
    try std.testing.expect(
        std.c.fcntl(retained_dir_fd, std.c.F.GETFD) >= 0,
    );
    try std.testing.expectEqual(
        sqlite.c.SQLITE_OK,
        sqlite.c.sqlite3_finalize(timeout_statement),
    );
    timeout_statement = null;
    try std.testing.expect(db.tryClose());
    try std.testing.expectEqual(
        @as(c_int, -1),
        std.c.fcntl(retained_dir_fd, std.c.F.GETFD),
    );
    try std.testing.expectEqual(
        @intFromEnum(std.posix.E.BADF),
        std.c._errno().*,
    );
    try tmp.dir.access(
        std.testing.io,
        "parked/var/lib/tdnf/history.db",
        .{},
    );
    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.access(
            std.testing.io,
            "outside/var/lib/tdnf/history.db",
            .{},
        ),
    );

    try tmp.dir.rename(
        "parked/var/lib/tdnf/history.db",
        tmp.dir,
        "parked/var/lib/tdnf/history.real",
        std.testing.io,
    );
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside/history.db",
        .data = "outside",
    });
    try tmp.dir.symLink(
        std.testing.io,
        "../../../../outside/history.db",
        "parked/var/lib/tdnf/history.db",
        .{},
    );
    try std.testing.expectError(
        error.UnsafePath,
        Database.initConfig(&pinned, "/var/lib/tdnf", false),
    );
    const outside_bytes = try tmp.dir.readFileAlloc(
        std.testing.io,
        "outside/history.db",
        allocator,
        .unlimited,
    );
    defer allocator.free(outside_bytes);
    try std.testing.expectEqualStrings("outside", outside_bytes);
}
