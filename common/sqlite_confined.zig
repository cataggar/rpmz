//! SQLite opening constrained to one already-open directory.
//!
//! SQLite's Unix VFS normally reopens the database and its journal/WAL
//! sidecars by pathname. This wrapper preserves the native Unix locking and
//! shared-memory implementation while replacing those pathname syscalls with
//! openat/fstatat/unlinkat operations relative to a pinned directory FD.

const std = @import("std");
const sqlite = @import("sqlite");

pub const c = sqlite.c;
const linux = std.os.linux;

extern fn openat(
    dir_fd: c_int,
    path: [*:0]const u8,
    flags: c_int,
    mode: c_uint,
) callconv(.c) c_int;
extern fn unlinkat(
    dir_fd: c_int,
    path: [*:0]const u8,
    flags: c_int,
) callconv(.c) c_int;
extern fn fsync(fd: c_int) callconv(.c) c_int;
extern fn renameat(
    old_dir_fd: c_int,
    old_path: [*:0]const u8,
    new_dir_fd: c_int,
    new_path: [*:0]const u8,
) callconv(.c) c_int;
extern fn fork() callconv(.c) c_int;
extern fn waitpid(pid: c_int, status: *c_int, options: c_int) callconv(.c) c_int;
extern fn _exit(status: c_int) callconv(.c) noreturn;
extern fn lockf(fd: c_int, command: c_int, length: i64) callconv(.c) c_int;

const Allocator = std.mem.Allocator;
const OpenFn = *const fn ([*:0]const u8, c_int, c_int) callconv(.c) c_int;
const AccessFn = *const fn ([*:0]const u8, c_int) callconv(.c) c_int;
const UnlinkFn = *const fn ([*:0]const u8) callconv(.c) c_int;
const OpenDirectoryFn = *const fn (
    [*:0]const u8,
    *c_int,
) callconv(.c) c_int;
const o_rdonly: c_int = 0;
const o_rdwr: c_int = 2;
const o_accmode: c_int = 3;
const o_creat: c_int = 0x40;
const o_directory: c_int = 0x10000;
const o_nofollow: c_int = 0x20000;
const o_cloexec: c_int = 0x80000;
const s_ifmt: u16 = 0o170000;
const s_ifreg: u16 = 0o100000;
const s_ifdir: u16 = 0o040000;
const f_ok: c_int = 0;
const r_ok: c_int = 4;
const w_ok: c_int = 2;

pub const Error = error{
    InvalidPath,
    NotFound,
    OutOfMemory,
    PathChanged,
    SqliteOpenFailed,
    SyscallFailed,
    UnsafeFile,
    VfsFailed,
};

pub const Mode = enum {
    read_only,
    read_write,
};

pub const OpenOptions = struct {
    mode: Mode,
    create: bool = false,
    pinned_main_fd: ?c_int = null,
    before_sqlite_open: ?*const fn (?*anyopaque) void = null,
    mutation_context: ?*anyopaque = null,
};

const Identity = struct {
    dev_major: u32,
    dev_minor: u32,
    ino: u64,

    fn fromStat(st: FileStat) Identity {
        return .{
            .dev_major = st.dev_major,
            .dev_minor = st.dev_minor,
            .ino = st.ino,
        };
    }

    fn eql(left: Identity, right: Identity) bool {
        return left.dev_major == right.dev_major and
            left.dev_minor == right.dev_minor and
            left.ino == right.ino;
    }
};

const FileStat = struct {
    dev_major: u32,
    dev_minor: u32,
    ino: u64,
    mode: u16,
    nlink: u32,
};

const SidecarKind = enum {
    journal,
    wal,
    shm,
};

const Match = struct {
    route: *Route,
    relative: []const u8,
};

const DirectoryPin = struct {
    allocator: Allocator,
    fd: c_int,
    identity: Identity,
    refs: usize = 1,
    next: ?*DirectoryPin = null,
};

const DatabaseState = struct {
    allocator: Allocator,
    directory: *DirectoryPin,
    main_identity: Identity,
    basename: [:0]u8,
    tracked_sidecars: [3]?Identity = .{ null, null, null },
    routes: ?*Route = null,
    refs: usize = 1,
    next: ?*DatabaseState = null,
};

const Route = struct {
    allocator: Allocator,
    database: *DatabaseState,
    main_fd: c_int,
    route_fd: c_int,
    writable: bool,
    active: bool = false,
    route_prefix: [:0]u8,
    synthetic_path: [:0]u8,
    next: ?*Route = null,
    database_next: ?*Route = null,
};

const Handle = struct {
    allocator: Allocator,
    database: *DatabaseState,
    route: *Route,
    main_fd: c_int,
    route_fd: c_int,
    writable: bool,
    route_prefix: [:0]u8,
    synthetic_path: [:0]u8,
    vfs_name: [:0]u8,
    base: *c.sqlite3_vfs,
    vfs: c.sqlite3_vfs,
};

const FileBinding = struct {
    allocator: Allocator,
    file: *c.sqlite3_file,
    handle: *Handle,
    original: *const c.sqlite3_io_methods,
    methods: c.sqlite3_io_methods,
    next: ?*FileBinding = null,
};

const VfsContext = struct {
    handle: *Handle,
    shared_node: bool,
};

pub const MainFdPin = struct {
    database: ?*DatabaseState,
    fd: c_int,

    pub fn deinit(self: *MainFdPin) void {
        const database = self.database orelse return;
        self.database = null;
        self.fd = -1;
        releaseDatabaseState(database);
    }
};

pub const Connection = struct {
    db: ?*c.sqlite3,
    handle: *Handle,

    pub fn close(self: *Connection) void {
        _ = self.tryClose();
    }

    pub fn tryClose(self: *Connection) bool {
        if (self.db != null and c.sqlite3_close(self.db) != c.SQLITE_OK)
            return false;
        self.db = null;
        destroyHandle(self.handle);
        self.* = undefined;
        return true;
    }

    pub fn verify(self: *const Connection) Error!void {
        lockRegistry();
        defer unlockRegistry();
        if (!verifyTrackedLocked(self.handle)) return error.PathChanged;
    }

    pub fn pinMainFd(self: *const Connection) MainFdPin {
        retainDatabaseState(self.handle.database);
        return .{
            .database = self.handle.database,
            .fd = self.handle.main_fd,
        };
    }
};

var registry_mutex: std.atomic.Mutex = .unlocked;
threadlocal var registry_lock_depth: usize = 0;
var registry_head: ?*Route = null;
var directory_head: ?*DirectoryPin = null;
var database_head: ?*DatabaseState = null;
var file_head: ?*FileBinding = null;
threadlocal var vfs_context: ?VfsContext = null;
var hooks_installed = false;
var next_vfs_id: u64 = 1;
var original_open: c.sqlite3_syscall_ptr = null;
var original_access: c.sqlite3_syscall_ptr = null;
var original_unlink: c.sqlite3_syscall_ptr = null;
var original_open_directory: c.sqlite3_syscall_ptr = null;

fn lockRegistry() void {
    if (registry_lock_depth != 0) {
        registry_lock_depth += 1;
        return;
    }
    while (!registry_mutex.tryLock()) std.atomic.spinLoopHint();
    registry_lock_depth = 1;
}

fn unlockRegistry() void {
    std.debug.assert(registry_lock_depth != 0);
    registry_lock_depth -= 1;
    if (registry_lock_depth != 0) return;
    registry_mutex.unlock();
}

fn duplicateFdCloexec(fd: c_int) c_int {
    return std.c.fcntl(
        fd,
        std.c.F.DUPFD_CLOEXEC,
        @as(c_int, 0),
    );
}

pub fn openAt(
    allocator: Allocator,
    dir_fd: c_int,
    basename: []const u8,
    options: OpenOptions,
) Error!Connection {
    if (!validBasename(basename) or
        (options.mode == .read_only and options.create))
    {
        return error.InvalidPath;
    }
    const base = try installHooks();
    const directory = try acquireDirectoryPin(allocator, dir_fd);
    var owns_directory = true;
    errdefer if (owns_directory) releaseDirectoryPin(directory);

    const basename_z = allocator.dupeZ(u8, basename) catch
        return error.OutOfMemory;
    defer allocator.free(basename_z);
    if (statRelativeFd(directory.fd, basename_z.ptr)) |existing| {
        if ((existing.mode & s_ifmt) != s_ifreg or existing.nlink != 1)
            return error.UnsafeFile;
    }
    const database_basename = allocator.dupeZ(u8, basename) catch
        return error.OutOfMemory;
    var owns_database_basename = true;
    errdefer if (owns_database_basename)
        allocator.free(database_basename);
    const database_candidate = allocator.create(DatabaseState) catch
        return error.OutOfMemory;
    var owns_database_candidate = true;
    errdefer if (owns_database_candidate)
        allocator.destroy(database_candidate);
    const route_fd = duplicateFdCloexec(directory.fd);
    if (route_fd < 0) return error.SyscallFailed;
    var owns_route_fd = true;
    errdefer {
        if (owns_route_fd) _ = std.c.close(route_fd);
    }
    const route_prefix = std.fmt.allocPrintSentinel(
        allocator,
        "/proc/self/fd/{d}/",
        .{route_fd},
        0,
    ) catch return error.OutOfMemory;
    var owns_route_prefix = true;
    errdefer if (owns_route_prefix) allocator.free(route_prefix);
    const synthetic_path = std.fmt.allocPrintSentinel(
        allocator,
        "{s}{s}",
        .{ route_prefix, basename },
        0,
    ) catch return error.OutOfMemory;
    var owns_synthetic_path = true;
    errdefer if (owns_synthetic_path) allocator.free(synthetic_path);
    const vfs_id = allocateVfsId();
    const vfs_name = std.fmt.allocPrintSentinel(
        allocator,
        "tdnf-confined-{x}",
        .{vfs_id},
        0,
    ) catch return error.OutOfMemory;
    errdefer allocator.free(vfs_name);
    const route = allocator.create(Route) catch return error.OutOfMemory;
    var owns_route = true;
    errdefer if (owns_route) allocator.destroy(route);
    const handle = allocator.create(Handle) catch return error.OutOfMemory;
    errdefer allocator.destroy(handle);

    const open_flags = switch (options.mode) {
        .read_only => o_rdonly,
        .read_write => o_rdwr,
    } | o_cloexec | o_nofollow |
        (if (options.create) o_creat else 0);
    const pinned_stat = if (options.pinned_main_fd) |pinned|
        try regularSingleLinkStat(pinned)
    else
        null;
    const main_fd = if (options.pinned_main_fd) |pinned|
        if (options.mode == .read_only)
            duplicateFdCloexec(pinned)
        else
            openat(
                directory.fd,
                basename_z.ptr,
                open_flags,
                0o644,
            )
    else
        openat(
            directory.fd,
            basename_z.ptr,
            open_flags,
            0o644,
        );
    if (main_fd < 0) {
        if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
            return error.NotFound;
        if (std.c._errno().* == @intFromEnum(std.posix.E.LOOP))
            return error.UnsafeFile;
        return error.SyscallFailed;
    }
    route.* = .{
        .allocator = allocator,
        .database = undefined,
        .main_fd = main_fd,
        .route_fd = route_fd,
        .writable = options.mode == .read_write,
        .route_prefix = route_prefix,
        .synthetic_path = synthetic_path,
    };
    owns_directory = false;
    owns_database_basename = false;
    owns_database_candidate = false;
    owns_route_fd = false;
    owns_route_prefix = false;
    owns_synthetic_path = false;
    owns_route = false;
    const database = try registerMainRoute(
        directory,
        basename,
        database_candidate,
        database_basename,
        route,
    );
    errdefer releaseDatabaseState(database);

    const main_stat = try regularSingleLinkStat(main_fd);
    if (options.pinned_main_fd != null) {
        const path_stat = statRelativeFd(
            directory.fd,
            basename_z.ptr,
        ) orelse return error.PathChanged;
        if ((path_stat.mode & s_ifmt) != s_ifreg or
            path_stat.nlink != 1 or
            !Identity.fromStat(path_stat).eql(Identity.fromStat(main_stat)) or
            !Identity.fromStat(pinned_stat.?).eql(Identity.fromStat(main_stat)))
        {
            return error.PathChanged;
        }
    }

    try trackExistingWalSidecars(database);
    publishRoute(route);
    var route_published = true;
    errdefer {
        if (route_published) retireRoute(route);
    }
    handle.* = .{
        .allocator = allocator,
        .database = database,
        .route = route,
        .main_fd = main_fd,
        .route_fd = route_fd,
        .writable = options.mode == .read_write,
        .route_prefix = route_prefix,
        .synthetic_path = synthetic_path,
        .vfs_name = vfs_name,
        .base = base,
        .vfs = makeVfs(base, vfs_name.ptr, handle),
    };

    if (c.sqlite3_vfs_register(&handle.vfs, 0) != c.SQLITE_OK)
        return error.VfsFailed;
    var registered = true;
    errdefer {
        if (registered) _ = c.sqlite3_vfs_unregister(&handle.vfs);
    }

    if (options.before_sqlite_open) |callback|
        callback(options.mutation_context);

    var db: ?*c.sqlite3 = null;
    const sqlite_flags = switch (options.mode) {
        .read_only => c.SQLITE_OPEN_READONLY,
        .read_write => c.SQLITE_OPEN_READWRITE,
    } | c.SQLITE_OPEN_NOMUTEX | c.SQLITE_OPEN_NOFOLLOW |
        (if (options.create) c.SQLITE_OPEN_CREATE else 0);
    if (c.sqlite3_open_v2(
        handle.synthetic_path.ptr,
        &db,
        sqlite_flags,
        handle.vfs_name.ptr,
    ) != c.SQLITE_OK) {
        if (db != null) _ = c.sqlite3_close(db);
        return error.SqliteOpenFailed;
    }
    errdefer _ = c.sqlite3_close(db);
    if (!verifyHandle(handle)) return error.PathChanged;
    _ = c.sqlite3_commit_hook(db, commitHook, handle);

    registered = false;
    route_published = false;
    return .{ .db = db, .handle = handle };
}

const RawConnection = extern struct {
    db: ?*c.sqlite3,
    handle: ?*anyopaque,
};

const RawMainFdPin = extern struct {
    fd: c_int,
    database: ?*anyopaque,
};

fn bridgeStatus(err: Error) c_int {
    return switch (err) {
        error.InvalidPath => 1,
        error.NotFound => 2,
        error.OutOfMemory => 3,
        error.PathChanged => 4,
        error.SqliteOpenFailed => 5,
        error.SyscallFailed => 6,
        error.UnsafeFile => 7,
        error.VfsFailed => 8,
    };
}

pub export fn tdnf_sqlite_confined_open_at(
    dir_fd: c_int,
    basename: [*]const u8,
    basename_len: usize,
    mode: c_int,
    create: c_int,
    pinned_main_fd: c_int,
    output: *RawConnection,
) callconv(.c) c_int {
    output.* = .{ .db = null, .handle = null };
    const connection = openAt(
        std.heap.c_allocator,
        dir_fd,
        basename[0..basename_len],
        .{
            .mode = switch (mode) {
                0 => .read_only,
                1 => .read_write,
                else => return 1,
            },
            .create = create != 0,
            .pinned_main_fd = if (pinned_main_fd >= 0)
                pinned_main_fd
            else
                null,
        },
    ) catch |err| return bridgeStatus(err);
    output.* = .{
        .db = connection.db,
        .handle = connection.handle,
    };
    return 0;
}

pub export fn tdnf_sqlite_confined_close(
    raw: *RawConnection,
) callconv(.c) c_int {
    const handle = raw.handle orelse return c.SQLITE_OK;
    var connection = Connection{
        .db = raw.db,
        .handle = @ptrCast(@alignCast(handle)),
    };
    if (!connection.tryClose()) return c.SQLITE_BUSY;
    raw.* = .{ .db = null, .handle = null };
    return c.SQLITE_OK;
}

pub export fn tdnf_sqlite_confined_verify(
    raw: *const RawConnection,
) callconv(.c) c_int {
    const handle = raw.handle orelse return 1;
    const connection = Connection{
        .db = raw.db,
        .handle = @ptrCast(@alignCast(handle)),
    };
    connection.verify() catch |err| return bridgeStatus(err);
    return 0;
}

pub export fn tdnf_sqlite_confined_pin_main_fd(
    raw: *const RawConnection,
) callconv(.c) RawMainFdPin {
    const handle = raw.handle orelse return .{
        .fd = -1,
        .database = null,
    };
    const connection = Connection{
        .db = raw.db,
        .handle = @ptrCast(@alignCast(handle)),
    };
    const pin = connection.pinMainFd();
    return .{
        .fd = pin.fd,
        .database = pin.database,
    };
}

pub export fn tdnf_sqlite_confined_release_main_fd_pin(
    raw_database: ?*anyopaque,
) callconv(.c) void {
    const database: *DatabaseState = @ptrCast(@alignCast(
        raw_database orelse return,
    ));
    releaseDatabaseState(database);
}

pub export fn tdnf_sqlite_confined_registry_anchor() callconv(.c) usize {
    return @intFromPtr(&registry_head);
}

fn makeVfs(
    base: *c.sqlite3_vfs,
    name: [*:0]const u8,
    handle: *Handle,
) c.sqlite3_vfs {
    var vfs = base.*;
    vfs.pNext = null;
    vfs.zName = name;
    vfs.pAppData = handle;
    vfs.xOpen = vfsOpen;
    vfs.xDelete = vfsDelete;
    vfs.xAccess = vfsAccess;
    vfs.xFullPathname = vfsFullPathname;
    vfs.xDlOpen = vfsDlOpen;
    vfs.xDlError = vfsDlError;
    vfs.xDlSym = vfsDlSym;
    vfs.xDlClose = vfsDlClose;
    vfs.xRandomness = vfsRandomness;
    vfs.xSleep = vfsSleep;
    vfs.xCurrentTime = vfsCurrentTime;
    vfs.xGetLastError = vfsGetLastError;
    vfs.xCurrentTimeInt64 = vfsCurrentTimeInt64;
    vfs.xSetSystemCall = vfsSetSystemCall;
    vfs.xGetSystemCall = vfsGetSystemCall;
    vfs.xNextSystemCall = vfsNextSystemCall;
    return vfs;
}

fn destroyHandle(handle: *Handle) void {
    _ = c.sqlite3_vfs_unregister(&handle.vfs);
    retireRoute(handle.route);
    releaseDatabaseState(handle.database);
    const allocator = handle.allocator;
    allocator.free(handle.vfs_name);
    allocator.destroy(handle);
}

fn acquireDirectoryPin(
    allocator: Allocator,
    dir_fd: c_int,
) Error!*DirectoryPin {
    const duplicate = duplicateFdCloexec(dir_fd);
    if (duplicate < 0) return error.SyscallFailed;
    errdefer _ = std.c.close(duplicate);
    const stat = statFd(duplicate) orelse return error.SyscallFailed;
    if ((stat.mode & s_ifmt) != s_ifdir) return error.UnsafeFile;
    const identity = Identity.fromStat(stat);

    lockRegistry();
    var cursor = directory_head;
    while (cursor) |pin| : (cursor = pin.next) {
        if (pin.identity.eql(identity)) {
            pin.refs += 1;
            unlockRegistry();
            _ = std.c.close(duplicate);
            return pin;
        }
    }
    unlockRegistry();

    const pin = allocator.create(DirectoryPin) catch
        return error.OutOfMemory;
    errdefer allocator.destroy(pin);
    pin.* = .{
        .allocator = allocator,
        .fd = duplicate,
        .identity = identity,
    };

    lockRegistry();
    cursor = directory_head;
    while (cursor) |existing| : (cursor = existing.next) {
        if (existing.identity.eql(identity)) {
            existing.refs += 1;
            unlockRegistry();
            allocator.destroy(pin);
            _ = std.c.close(duplicate);
            return existing;
        }
    }
    pin.next = directory_head;
    directory_head = pin;
    unlockRegistry();
    return pin;
}

fn releaseDirectoryPin(pin: *DirectoryPin) void {
    lockRegistry();
    std.debug.assert(pin.refs != 0);
    pin.refs -= 1;
    if (pin.refs != 0) {
        unlockRegistry();
        return;
    }
    var cursor = &directory_head;
    while (cursor.*) |current| {
        if (current == pin) {
            cursor.* = current.next;
            break;
        }
        cursor = &current.next;
    }
    unlockRegistry();
    _ = std.c.close(pin.fd);
    const allocator = pin.allocator;
    allocator.destroy(pin);
}

fn registerMainRoute(
    directory: *DirectoryPin,
    basename: []const u8,
    candidate: *DatabaseState,
    owned_basename: [:0]u8,
    route: *Route,
) Error!*DatabaseState {
    const allocator = route.allocator;
    lockRegistry();
    var cursor = database_head;
    while (cursor) |database| : (cursor = database.next) {
        if (!database.directory.identity.eql(directory.identity) or
            !std.mem.eql(u8, database.basename, basename))
        {
            continue;
        }
        database.refs += 1;
        route.database = database;
        route.database_next = database.routes;
        database.routes = route;
        unlockRegistry();
        allocator.destroy(candidate);
        allocator.free(owned_basename);
        releaseDirectoryPin(directory);
        const main_stat = regularSingleLinkStat(route.main_fd) catch |err| {
            releaseDatabaseState(database);
            return err;
        };
        if (!database.main_identity.eql(Identity.fromStat(main_stat))) {
            releaseDatabaseState(database);
            return error.PathChanged;
        }
        return database;
    }

    const main_stat = statFd(route.main_fd) orelse {
        _ = std.c.close(route.main_fd);
        route.main_fd = -1;
        unlockRegistry();
        _ = std.c.close(route.route_fd);
        allocator.free(route.route_prefix);
        allocator.free(route.synthetic_path);
        allocator.destroy(route);
        allocator.destroy(candidate);
        allocator.free(owned_basename);
        releaseDirectoryPin(directory);
        return error.SyscallFailed;
    };
    if ((main_stat.mode & s_ifmt) != s_ifreg or main_stat.nlink != 1) {
        _ = std.c.close(route.main_fd);
        route.main_fd = -1;
        unlockRegistry();
        _ = std.c.close(route.route_fd);
        allocator.free(route.route_prefix);
        allocator.free(route.synthetic_path);
        allocator.destroy(route);
        allocator.destroy(candidate);
        allocator.free(owned_basename);
        releaseDirectoryPin(directory);
        return error.UnsafeFile;
    }
    candidate.* = .{
        .allocator = allocator,
        .directory = directory,
        .main_identity = Identity.fromStat(main_stat),
        .basename = owned_basename,
    };
    route.database = candidate;
    route.database_next = candidate.routes;
    candidate.routes = route;
    candidate.next = database_head;
    database_head = candidate;
    unlockRegistry();
    return candidate;
}

fn retainDatabaseState(database: *DatabaseState) void {
    lockRegistry();
    defer unlockRegistry();
    std.debug.assert(database.refs != 0);
    database.refs += 1;
}

fn releaseDatabaseState(database: *DatabaseState) void {
    lockRegistry();
    std.debug.assert(database.refs != 0);
    database.refs -= 1;
    if (database.refs != 0) {
        unlockRegistry();
        return;
    }
    var cursor = &database_head;
    while (cursor.*) |current| {
        if (current == database) {
            cursor.* = current.next;
            break;
        }
        cursor = &current.next;
    }
    var routes = database.routes;
    database.routes = null;
    var route_cursor = routes;
    while (route_cursor) |route| : (route_cursor = route.database_next) {
        var registered = &registry_head;
        while (registered.*) |current| {
            if (current == route) {
                registered.* = current.next;
                break;
            }
            registered = &current.next;
        }
        route.next = null;
    }
    unlockRegistry();
    while (routes) |route| {
        routes = route.database_next;
        _ = std.c.close(route.main_fd);
        _ = std.c.close(route.route_fd);
        const route_allocator = route.allocator;
        route_allocator.free(route.route_prefix);
        route_allocator.free(route.synthetic_path);
        route_allocator.destroy(route);
    }
    releaseDirectoryPin(database.directory);
    const allocator = database.allocator;
    allocator.free(database.basename);
    allocator.destroy(database);
}

fn trackExistingWalSidecars(database: *DatabaseState) Error!void {
    lockRegistry();
    defer unlockRegistry();
    for ([_]SidecarKind{ .wal, .shm }) |kind| {
        var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
        const name = std.fmt.bufPrint(
            &name_buffer,
            "{s}-{s}",
            .{ database.basename, @tagName(kind) },
        ) catch return error.InvalidPath;
        const slot = &database.tracked_sidecars[sidecarIndex(kind)];
        const st = statRelativeDatabase(database, name) orelse {
            if (slot.* != null) return error.PathChanged;
            continue;
        };
        if ((st.mode & s_ifmt) != s_ifreg or st.nlink != 1)
            return error.UnsafeFile;
        const identity = Identity.fromStat(st);
        if (slot.*) |expected| {
            if (!expected.eql(identity)) return error.PathChanged;
        } else {
            slot.* = identity;
        }
    }
}

fn allocateVfsId() u64 {
    lockRegistry();
    defer unlockRegistry();
    const result = next_vfs_id;
    next_vfs_id +%= 1;
    return result;
}

fn publishRoute(route: *Route) void {
    lockRegistry();
    defer unlockRegistry();
    std.debug.assert(!route.active);
    route.active = true;
    route.next = registry_head;
    registry_head = route;
}

fn retireRoute(route: *Route) void {
    lockRegistry();
    defer unlockRegistry();
    route.active = false;
}

fn installHooks() Error!*c.sqlite3_vfs {
    lockRegistry();
    defer unlockRegistry();
    const base = c.sqlite3_vfs_find(null);
    if (base == null or base.*.xGetSystemCall == null or
        base.*.xSetSystemCall == null)
    {
        return error.VfsFailed;
    }
    if (hooks_installed) return base;

    original_open = base.*.xGetSystemCall.?(base, "open");
    original_access = base.*.xGetSystemCall.?(base, "access");
    original_unlink = base.*.xGetSystemCall.?(base, "unlink");
    original_open_directory = base.*.xGetSystemCall.?(
        base,
        "openDirectory",
    );
    if (original_open == null or original_access == null or
        original_unlink == null or original_open_directory == null)
    {
        return error.VfsFailed;
    }
    const Hook = struct {
        name: [*:0]const u8,
        function: c.sqlite3_syscall_ptr,
        previous: c.sqlite3_syscall_ptr,
    };
    const hooks = [_]Hook{
        .{
            .name = "open",
            .function = @ptrCast(&confinedOpen),
            .previous = original_open,
        },
        .{
            .name = "access",
            .function = @ptrCast(&confinedAccess),
            .previous = original_access,
        },
        .{
            .name = "unlink",
            .function = @ptrCast(&confinedUnlink),
            .previous = original_unlink,
        },
        .{
            .name = "openDirectory",
            .function = @ptrCast(&confinedOpenDirectory),
            .previous = original_open_directory,
        },
    };
    var installed: usize = 0;
    for (hooks) |hook| {
        if (base.*.xSetSystemCall.?(
            base,
            hook.name,
            hook.function,
        ) != c.SQLITE_OK) {
            while (installed > 0) {
                installed -= 1;
                _ = base.*.xSetSystemCall.?(
                    base,
                    hooks[installed].name,
                    hooks[installed].previous,
                );
            }
            return error.VfsFailed;
        }
        installed += 1;
    }
    hooks_installed = true;
    return base;
}

const PathClassification = union(enum) {
    match: Match,
    rejected,
    unrelated,
};

fn classifyPathLocked(
    path: []const u8,
) PathClassification {
    var recognized = false;
    var cursor = registry_head;
    while (cursor) |route| : (cursor = route.next) {
        const prefix = route.route_prefix;
        if (std.mem.startsWith(u8, path, prefix)) {
            recognized = true;
            const relative = path[prefix.len..];
            if (allowedRelative(route, relative)) {
                return .{ .match = .{
                    .route = route,
                    .relative = relative,
                } };
            }
        }
    }
    return if (recognized) .rejected else .unrelated;
}

const DirectoryClassification = union(enum) {
    match: *Route,
    rejected,
    unrelated,
};

fn classifyDirectoryLocked(
    path: []const u8,
) DirectoryClassification {
    var recognized = false;
    var cursor = registry_head;
    while (cursor) |route| : (cursor = route.next) {
        const prefix = route.route_prefix;
        const directory = prefix[0 .. prefix.len - 1];
        if (!std.mem.eql(u8, path, directory)) continue;
        recognized = true;
        return .{ .match = route };
    }
    return if (recognized) .rejected else .unrelated;
}

fn allowedRelative(route: *const Route, relative: []const u8) bool {
    const basename = route.database.basename;
    if (relative.len == 0 or std.mem.indexOfScalar(u8, relative, '/') != null)
        return false;
    if (std.mem.eql(u8, relative, basename)) return true;
    if (!std.mem.startsWith(u8, relative, basename)) return false;
    const suffix = relative[basename.len..];
    return std.mem.eql(u8, suffix, "-journal") or
        std.mem.eql(u8, suffix, "-wal") or
        std.mem.eql(u8, suffix, "-shm");
}

fn sidecarKind(route: *const Route, relative: []const u8) ?SidecarKind {
    const basename = route.database.basename;
    if (!std.mem.startsWith(u8, relative, basename)) return null;
    const suffix = relative[basename.len..];
    if (std.mem.eql(u8, suffix, "-journal")) return .journal;
    if (std.mem.eql(u8, suffix, "-wal")) return .wal;
    if (std.mem.eql(u8, suffix, "-shm")) return .shm;
    return null;
}

fn sidecarIndex(kind: SidecarKind) usize {
    return @intFromEnum(kind);
}

fn trackedWalSidecar(
    route: *const Route,
    kind: ?SidecarKind,
) bool {
    const sidecar = kind orelse return false;
    if (sidecar != .wal and sidecar != .shm) return false;
    return route.database.tracked_sidecars[sidecarIndex(sidecar)] != null;
}

fn validBasename(value: []const u8) bool {
    return value.len != 0 and
        !std.mem.eql(u8, value, ".") and
        !std.mem.eql(u8, value, "..") and
        std.mem.indexOfAny(u8, value, "/\x00") == null;
}

fn regularSingleLinkStat(fd: c_int) Error!FileStat {
    const st = statFd(fd) orelse return error.SyscallFailed;
    if ((st.mode & s_ifmt) != s_ifreg or st.nlink != 1)
        return error.UnsafeFile;
    return st;
}

fn statFd(fd: c_int) ?FileStat {
    var st = std.mem.zeroes(linux.Statx);
    if (std.c.statx(
        fd,
        "",
        linux.AT.EMPTY_PATH,
        linux.STATX.BASIC_STATS,
        &st,
    ) != 0) return null;
    return fileStat(st);
}

fn statRelativeFd(
    dir_fd: c_int,
    name: [*:0]const u8,
) ?FileStat {
    var st = std.mem.zeroes(linux.Statx);
    if (std.c.statx(
        dir_fd,
        name,
        linux.AT.SYMLINK_NOFOLLOW,
        linux.STATX.BASIC_STATS,
        &st,
    ) != 0) return null;
    return fileStat(st);
}

fn fileStat(st: linux.Statx) FileStat {
    return .{
        .dev_major = st.dev_major,
        .dev_minor = st.dev_minor,
        .ino = st.ino,
        .mode = st.mode,
        .nlink = st.nlink,
    };
}

fn statRelative(
    route: *const Route,
    relative: []const u8,
) ?FileStat {
    return statRelativeDatabase(route.database, relative);
}

fn statRelativeDatabase(
    database: *const DatabaseState,
    relative: []const u8,
) ?FileStat {
    var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
    if (relative.len >= name_buffer.len) return null;
    @memcpy(name_buffer[0..relative.len], relative);
    name_buffer[relative.len] = 0;
    return statRelativeFd(
        database.directory.fd,
        @ptrCast(&name_buffer),
    );
}

fn verifyTrackedLocked(handle: *const Handle) bool {
    const database = handle.database;
    const main = statRelative(handle.route, database.basename) orelse
        return false;
    if ((main.mode & s_ifmt) != s_ifreg or
        main.nlink != 1 or
        !Identity.fromStat(main).eql(database.main_identity))
    {
        return false;
    }
    inline for (.{ SidecarKind.journal, .wal, .shm }) |kind| {
        if (database.tracked_sidecars[sidecarIndex(kind)]) |identity| {
            var name_buffer: [std.fs.max_name_bytes]u8 = undefined;
            const name = std.fmt.bufPrint(
                &name_buffer,
                "{s}-{s}",
                .{ database.basename, @tagName(kind) },
            ) catch return false;
            const st = statRelative(handle.route, name) orelse return false;
            if ((st.mode & s_ifmt) != s_ifreg or
                st.nlink != 1 or
                !Identity.fromStat(st).eql(identity))
            {
                return false;
            }
        }
    }
    return true;
}

fn verifyHandle(handle: *const Handle) bool {
    lockRegistry();
    defer unlockRegistry();
    return verifyTrackedLocked(handle);
}

fn commitHook(context: ?*anyopaque) callconv(.c) c_int {
    const handle: *Handle = @ptrCast(@alignCast(context orelse return 1));
    return @intFromBool(!verifyHandle(handle));
}

fn setErrno(value: c_int) void {
    std.c._errno().* = value;
}

fn contextMatches(route: *const Route) bool {
    const context = vfs_context orelse return false;
    return context.handle.database == route.database;
}

fn routeCanWrite(route: *const Route) bool {
    if (vfs_context) |context| {
        return context.handle.database == route.database and
            context.handle.writable;
    }
    return route.active and route.writable;
}

fn original(comptime T: type, pointer: c.sqlite3_syscall_ptr) T {
    return @ptrCast(pointer.?);
}

fn confinedOpen(
    raw_path: [*:0]const u8,
    flags: c_int,
    mode: c_int,
) callconv(.c) c_int {
    lockRegistry();
    defer unlockRegistry();
    const require_writable = (flags & o_accmode) != o_rdonly or
        (flags & o_creat) != 0;
    const match = switch (classifyPathLocked(std.mem.span(raw_path))) {
        .match => |value| value,
        .rejected => {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        },
        .unrelated => return original(OpenFn, original_open)(
            raw_path,
            flags,
            mode,
        ),
    };
    const route = match.route;
    const kind = sidecarKind(route, match.relative);
    if (!route.active and !contextMatches(route)) {
        setErrno(@intFromEnum(std.posix.E.ACCES));
        return -1;
    }
    // SQLite's process-shared unixShmNode requests O_RDWR|O_CREAT even when
    // the connection that first maps an existing SHM file is read-only.
    // Grant that narrowly scoped internal map access only after the sidecar
    // identity has been pinned, and never grant creation through a reader.
    const context = vfs_context;
    const read_only_shared_shm = require_writable and !routeCanWrite(route) and
        context != null and context.?.shared_node and
        context.?.handle.database == route.database and
        !context.?.handle.writable and kind == .shm and
        trackedWalSidecar(route, kind);
    if (require_writable and
        !routeCanWrite(route) and
        !read_only_shared_shm)
    {
        setErrno(@intFromEnum(std.posix.E.ACCES));
        return -1;
    }
    const database = route.database;
    if (std.mem.eql(u8, match.relative, database.basename)) {
        const current = statRelative(route, database.basename) orelse {
            setErrno(@intFromEnum(std.posix.E.STALE));
            return -1;
        };
        if ((current.mode & s_ifmt) != s_ifreg or
            current.nlink != 1 or
            !Identity.fromStat(current).eql(database.main_identity))
        {
            setErrno(@intFromEnum(std.posix.E.STALE));
            return -1;
        }
        const owns_route = if (context) |call_context|
            call_context.handle.route == route
        else
            route.active;
        if (!owns_route or
            ((flags & o_accmode) != o_rdonly and !routeCanWrite(route)))
        {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        }
        return duplicateFdCloexec(route.main_fd);
    }

    var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
    if (match.relative.len >= name_buffer.len) {
        setErrno(@intFromEnum(std.posix.E.NAMETOOLONG));
        return -1;
    }
    @memcpy(name_buffer[0..match.relative.len], match.relative);
    name_buffer[match.relative.len] = 0;
    const fd = openat(
        database.directory.fd,
        @ptrCast(&name_buffer),
        (if (read_only_shared_shm) flags & ~o_creat else flags) |
            o_cloexec | o_nofollow,
        @intCast(mode),
    );
    if (fd < 0) return fd;
    const st = regularSingleLinkStat(fd) catch {
        _ = std.c.close(fd);
        setErrno(@intFromEnum(std.posix.E.LOOP));
        return -1;
    };
    if (kind) |sidecar| {
        const identity = Identity.fromStat(st);
        const slot = &database.tracked_sidecars[sidecarIndex(sidecar)];
        if (slot.*) |expected| {
            if (!expected.eql(identity)) {
                _ = std.c.close(fd);
                setErrno(@intFromEnum(std.posix.E.STALE));
                return -1;
            }
        } else {
            slot.* = identity;
        }
    }
    return fd;
}

fn confinedAccess(
    raw_path: [*:0]const u8,
    mode: c_int,
) callconv(.c) c_int {
    lockRegistry();
    defer unlockRegistry();
    const path = std.mem.span(raw_path);
    switch (classifyDirectoryLocked(path)) {
        .match => |route| {
            if ((!route.active and !contextMatches(route)) or
                (mode == w_ok and !routeCanWrite(route)))
            {
                setErrno(@intFromEnum(std.posix.E.ACCES));
                return -1;
            }
            return 0;
        },
        .rejected => {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        },
        .unrelated => {},
    }
    const match = switch (classifyPathLocked(path)) {
        .match => |value| value,
        .rejected => {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        },
        .unrelated => return original(AccessFn, original_access)(
            raw_path,
            mode,
        ),
    };
    if (!match.route.active and !contextMatches(match.route)) {
        setErrno(@intFromEnum(std.posix.E.ACCES));
        return -1;
    }
    const st = statRelative(match.route, match.relative) orelse return -1;
    if ((st.mode & s_ifmt) != s_ifreg or st.nlink != 1) {
        setErrno(@intFromEnum(std.posix.E.LOOP));
        return -1;
    }
    if (mode == w_ok and !routeCanWrite(match.route)) {
        const context = vfs_context;
        const kind = sidecarKind(match.route, match.relative);
        const shared_reader = context != null and context.?.shared_node and
            context.?.handle.database == match.route.database and
            !context.?.handle.writable and kind == .shm and
            trackedWalSidecar(match.route, kind);
        if (!shared_reader) {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        }
    }
    return 0;
}

fn confinedUnlink(raw_path: [*:0]const u8) callconv(.c) c_int {
    lockRegistry();
    defer unlockRegistry();
    const match = switch (classifyPathLocked(std.mem.span(raw_path))) {
        .match => |value| value,
        .rejected => {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        },
        .unrelated => return original(UnlinkFn, original_unlink)(raw_path),
    };
    if ((!match.route.active and !contextMatches(match.route)) or
        !routeCanWrite(match.route))
    {
        setErrno(@intFromEnum(std.posix.E.ACCES));
        return -1;
    }
    if (std.mem.eql(
        u8,
        match.relative,
        match.route.database.basename,
    )) {
        setErrno(@intFromEnum(std.posix.E.PERM));
        return -1;
    }
    if (statRelative(match.route, match.relative)) |st| {
        if ((st.mode & s_ifmt) != s_ifreg or st.nlink != 1) {
            setErrno(@intFromEnum(std.posix.E.LOOP));
            return -1;
        }
    }
    var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
    if (match.relative.len >= name_buffer.len) {
        setErrno(@intFromEnum(std.posix.E.NAMETOOLONG));
        return -1;
    }
    @memcpy(name_buffer[0..match.relative.len], match.relative);
    name_buffer[match.relative.len] = 0;
    const rc = unlinkat(
        match.route.database.directory.fd,
        @ptrCast(&name_buffer),
        0,
    );
    if (rc == 0) {
        if (sidecarKind(match.route, match.relative)) |kind|
            match.route.database.tracked_sidecars[sidecarIndex(kind)] = null;
    }
    return rc;
}

fn confinedOpenDirectory(
    raw_path: [*:0]const u8,
    out: *c_int,
) callconv(.c) c_int {
    lockRegistry();
    defer unlockRegistry();
    const route = switch (classifyDirectoryLocked(std.mem.span(raw_path))) {
        .match => |value| value,
        .rejected => {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        },
        .unrelated => return original(OpenDirectoryFn, original_open_directory)(
            raw_path,
            out,
        ),
    };
    if (!route.active and !contextMatches(route)) {
        setErrno(@intFromEnum(std.posix.E.ACCES));
        return -1;
    }
    const fd = duplicateFdCloexec(route.database.directory.fd);
    if (fd < 0) return -1;
    out.* = fd;
    return 0;
}

fn vfsHandle(vfs: [*c]c.sqlite3_vfs) *Handle {
    return @ptrCast(@alignCast(vfs.*.pAppData.?));
}

fn addFileBinding(binding: *FileBinding) void {
    lockRegistry();
    defer unlockRegistry();
    binding.next = file_head;
    file_head = binding;
}

fn findFileBinding(file: *c.sqlite3_file) ?*FileBinding {
    lockRegistry();
    defer unlockRegistry();
    var cursor = file_head;
    while (cursor) |binding| : (cursor = binding.next) {
        if (binding.file == file) return binding;
    }
    return null;
}

fn takeFileBinding(file: *c.sqlite3_file) ?*FileBinding {
    lockRegistry();
    defer unlockRegistry();
    var cursor = &file_head;
    while (cursor.*) |binding| {
        if (binding.file == file) {
            cursor.* = binding.next;
            binding.next = null;
            return binding;
        }
        cursor = &binding.next;
    }
    return null;
}

fn bindMainFile(
    handle: *Handle,
    raw_file: [*c]c.sqlite3_file,
) c_int {
    const file: *c.sqlite3_file = @ptrCast(raw_file);
    const original_methods = file.pMethods;
    if (original_methods == null or original_methods.*.iVersion < 2 or
        original_methods.*.xClose == null or
        original_methods.*.xShmMap == null or
        original_methods.*.xShmUnmap == null)
    {
        return c.SQLITE_IOERR;
    }
    const binding = handle.allocator.create(FileBinding) catch {
        _ = original_methods.*.xClose.?(raw_file);
        file.pMethods = null;
        return c.SQLITE_NOMEM;
    };
    binding.* = .{
        .allocator = handle.allocator,
        .file = file,
        .handle = handle,
        .original = original_methods,
        .methods = original_methods.*,
    };
    binding.methods.xClose = boundClose;
    binding.methods.xShmMap = boundShmMap;
    binding.methods.xShmUnmap = boundShmUnmap;
    addFileBinding(binding);
    file.pMethods = &binding.methods;
    return c.SQLITE_OK;
}

fn boundClose(raw_file: [*c]c.sqlite3_file) callconv(.c) c_int {
    const file: *c.sqlite3_file = @ptrCast(raw_file);
    const binding = takeFileBinding(file) orelse return c.SQLITE_IOERR_CLOSE;
    file.pMethods = binding.original;
    const result = binding.original.xClose.?(raw_file);
    binding.allocator.destroy(binding);
    return result;
}

fn boundShmMap(
    raw_file: [*c]c.sqlite3_file,
    page: c_int,
    page_size: c_int,
    extend: c_int,
    output: [*c]?*volatile anyopaque,
) callconv(.c) c_int {
    const binding = findFileBinding(@ptrCast(raw_file)) orelse
        return c.SQLITE_IOERR_SHMMAP;
    const previous = vfs_context;
    vfs_context = .{ .handle = binding.handle, .shared_node = true };
    defer vfs_context = previous;
    return binding.original.xShmMap.?(
        raw_file,
        page,
        page_size,
        extend,
        output,
    );
}

fn boundShmUnmap(
    raw_file: [*c]c.sqlite3_file,
    delete_flag: c_int,
) callconv(.c) c_int {
    const binding = findFileBinding(@ptrCast(raw_file)) orelse
        return c.SQLITE_IOERR_SHMOPEN;
    const previous = vfs_context;
    vfs_context = .{ .handle = binding.handle, .shared_node = true };
    defer vfs_context = previous;
    return binding.original.xShmUnmap.?(raw_file, delete_flag);
}

fn pathAllowedForHandle(handle: *const Handle, path: []const u8) bool {
    const prefix = handle.route_prefix;
    return std.mem.startsWith(u8, path, prefix) and
        allowedRelative(handle.route, path[prefix.len..]);
}

fn vfsOpen(
    raw_vfs: [*c]c.sqlite3_vfs,
    name: c.sqlite3_filename,
    file: [*c]c.sqlite3_file,
    flags: c_int,
    out_flags: [*c]c_int,
) callconv(.c) c_int {
    const handle = vfsHandle(raw_vfs);
    if (name == null or
        !pathAllowedForHandle(handle, std.mem.span(name)))
    {
        return c.SQLITE_CANTOPEN;
    }
    const previous = vfs_context;
    vfs_context = .{ .handle = handle, .shared_node = false };
    defer vfs_context = previous;
    const result = handle.base.xOpen.?(
        handle.base,
        name,
        file,
        flags | c.SQLITE_OPEN_NOFOLLOW,
        out_flags,
    );
    if (result != c.SQLITE_OK or
        (flags & c.SQLITE_OPEN_MAIN_DB) == 0)
    {
        return result;
    }
    return bindMainFile(handle, file);
}

fn vfsDelete(
    raw_vfs: [*c]c.sqlite3_vfs,
    name: [*c]const u8,
    sync_dir: c_int,
) callconv(.c) c_int {
    const handle = vfsHandle(raw_vfs);
    if (name == null or
        !pathAllowedForHandle(handle, std.mem.span(name)))
    {
        return c.SQLITE_CANTOPEN;
    }
    if (!handle.writable) return c.SQLITE_READONLY;
    const previous = vfs_context;
    vfs_context = .{ .handle = handle, .shared_node = false };
    defer vfs_context = previous;
    if (confinedUnlink(@ptrCast(name)) != 0) {
        if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
            return c.SQLITE_OK;
        return c.SQLITE_IOERR_DELETE;
    }
    if (sync_dir != 0 and fsync(handle.database.directory.fd) != 0)
        return c.SQLITE_IOERR_DIR_FSYNC;
    return c.SQLITE_OK;
}

fn vfsAccess(
    raw_vfs: [*c]c.sqlite3_vfs,
    name: [*c]const u8,
    flags: c_int,
    out: [*c]c_int,
) callconv(.c) c_int {
    const handle = vfsHandle(raw_vfs);
    if (name == null or
        !pathAllowedForHandle(handle, std.mem.span(name)))
    {
        return c.SQLITE_CANTOPEN;
    }
    const mode = switch (flags) {
        c.SQLITE_ACCESS_READWRITE => w_ok,
        c.SQLITE_ACCESS_READ => r_ok,
        else => f_ok,
    };
    if (mode == w_ok and !handle.writable) {
        out.* = 0;
        return c.SQLITE_OK;
    }
    const previous = vfs_context;
    vfs_context = .{ .handle = handle, .shared_node = false };
    defer vfs_context = previous;
    out.* = @intFromBool(confinedAccess(@ptrCast(name), mode) == 0);
    return c.SQLITE_OK;
}

fn vfsFullPathname(
    raw_vfs: [*c]c.sqlite3_vfs,
    name: [*c]const u8,
    out_len: c_int,
    out: [*c]u8,
) callconv(.c) c_int {
    if (name == null or out == null or out_len <= 0) return c.SQLITE_CANTOPEN;
    const path = std.mem.span(name);
    if (!pathAllowedForHandle(vfsHandle(raw_vfs), path))
        return c.SQLITE_CANTOPEN;
    if (path.len + 1 > @as(usize, @intCast(out_len)))
        return c.SQLITE_CANTOPEN;
    @memcpy(out[0..path.len], path);
    out[path.len] = 0;
    return c.SQLITE_OK;
}

fn vfsDlOpen(
    raw_vfs: [*c]c.sqlite3_vfs,
    name: [*c]const u8,
) callconv(.c) ?*anyopaque {
    const base = vfsHandle(raw_vfs).base;
    return if (base.xDlOpen) |function| function(base, name) else null;
}

fn vfsDlError(
    raw_vfs: [*c]c.sqlite3_vfs,
    len: c_int,
    message: [*c]u8,
) callconv(.c) void {
    const base = vfsHandle(raw_vfs).base;
    if (base.xDlError) |function| function(base, len, message);
}

fn vfsDlSym(
    raw_vfs: [*c]c.sqlite3_vfs,
    library: ?*anyopaque,
    symbol: [*c]const u8,
) callconv(.c) ?*const fn () callconv(.c) void {
    const base = vfsHandle(raw_vfs).base;
    return if (base.xDlSym) |function|
        function(base, library, symbol)
    else
        null;
}

fn vfsDlClose(
    raw_vfs: [*c]c.sqlite3_vfs,
    library: ?*anyopaque,
) callconv(.c) void {
    const base = vfsHandle(raw_vfs).base;
    if (base.xDlClose) |function| function(base, library);
}

fn vfsRandomness(
    raw_vfs: [*c]c.sqlite3_vfs,
    len: c_int,
    out: [*c]u8,
) callconv(.c) c_int {
    const base = vfsHandle(raw_vfs).base;
    return base.xRandomness.?(base, len, out);
}

fn vfsSleep(
    raw_vfs: [*c]c.sqlite3_vfs,
    microseconds: c_int,
) callconv(.c) c_int {
    const base = vfsHandle(raw_vfs).base;
    return base.xSleep.?(base, microseconds);
}

fn vfsCurrentTime(
    raw_vfs: [*c]c.sqlite3_vfs,
    out: [*c]f64,
) callconv(.c) c_int {
    const base = vfsHandle(raw_vfs).base;
    return base.xCurrentTime.?(base, out);
}

fn vfsGetLastError(
    raw_vfs: [*c]c.sqlite3_vfs,
    len: c_int,
    out: [*c]u8,
) callconv(.c) c_int {
    const base = vfsHandle(raw_vfs).base;
    return if (base.xGetLastError) |function|
        function(base, len, out)
    else
        0;
}

fn vfsCurrentTimeInt64(
    raw_vfs: [*c]c.sqlite3_vfs,
    out: [*c]c.sqlite3_int64,
) callconv(.c) c_int {
    const base = vfsHandle(raw_vfs).base;
    return if (base.xCurrentTimeInt64) |function|
        function(base, out)
    else
        c.SQLITE_NOTFOUND;
}

fn vfsSetSystemCall(
    raw_vfs: [*c]c.sqlite3_vfs,
    name: [*c]const u8,
    function: c.sqlite3_syscall_ptr,
) callconv(.c) c_int {
    const base = vfsHandle(raw_vfs).base;
    return if (base.xSetSystemCall) |delegate|
        delegate(base, name, function)
    else
        c.SQLITE_NOTFOUND;
}

fn vfsGetSystemCall(
    raw_vfs: [*c]c.sqlite3_vfs,
    name: [*c]const u8,
) callconv(.c) c.sqlite3_syscall_ptr {
    const base = vfsHandle(raw_vfs).base;
    return if (base.xGetSystemCall) |delegate|
        delegate(base, name)
    else
        null;
}

fn vfsNextSystemCall(
    raw_vfs: [*c]c.sqlite3_vfs,
    name: [*c]const u8,
) callconv(.c) [*c]const u8 {
    const base = vfsHandle(raw_vfs).base;
    return if (base.xNextSystemCall) |delegate|
        delegate(base, name)
    else
        null;
}

fn createPersistentWal(path: [*:0]const u8) !void {
    var db: ?*c.sqlite3 = null;
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_open_v2(
            path,
            &db,
            c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE,
            null,
        ),
    );
    var persist: c_int = 1;
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_file_control(
            db,
            "main",
            c.SQLITE_FCNTL_PERSIST_WAL,
            @ptrCast(&persist),
        ),
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            db,
            "PRAGMA journal_mode=WAL;" ++
                "PRAGMA wal_autocheckpoint=0;" ++
                "CREATE TABLE values_table(value INTEGER);" ++
                "INSERT INTO values_table VALUES (1);",
            null,
            null,
            null,
        ),
    );
    try std.testing.expectEqual(c.SQLITE_OK, c.sqlite3_close(db));
}

fn sidecarExists(dir_fd: c_int, name: [*:0]const u8) bool {
    return statRelativeFd(dir_fd, name) != null;
}

test "confined SQLite rejects main replacement between pin and VFS open" {
    const Mutation = struct {
        dir_fd: c_int,

        fn run(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = renameat(
                self.dir_fd,
                "db.sqlite",
                self.dir_fd,
                "pinned.sqlite",
            );
            _ = renameat(
                self.dir_fd,
                "outside.sqlite",
                self.dir_fd,
                "db.sqlite",
            );
        }
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "db.sqlite",
        .data = "",
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside.sqlite",
        .data = "outside",
    });
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);
    var mutation = Mutation{ .dir_fd = dir_fd };
    try std.testing.expectError(
        error.SqliteOpenFailed,
        openAt(std.testing.allocator, dir_fd, "db.sqlite", .{
            .mode = .read_write,
            .before_sqlite_open = Mutation.run,
            .mutation_context = &mutation,
        }),
    );
    const outside = try tmp.dir.readFileAlloc(
        std.testing.io,
        "db.sqlite",
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(outside);
    try std.testing.expectEqualStrings("outside", outside);
}

test "failed concurrent open cannot release a live POSIX database lock" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);

    var first = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write, .create = true },
    );
    defer first.close();
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            first.db,
            "PRAGMA journal_mode=DELETE;" ++
                "CREATE TABLE values_table(value INTEGER);" ++
                "BEGIN EXCLUSIVE;",
            null,
            null,
            null,
        ),
    );
    const pinned_fd = openat(
        dir_fd,
        "db.sqlite",
        o_rdonly | o_cloexec | o_nofollow,
        0,
    );
    try std.testing.expect(pinned_fd >= 0);
    defer _ = std.c.close(pinned_fd);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside.sqlite",
        .data = "outside",
    });
    try std.testing.expectEqual(
        @as(c_int, 0),
        renameat(dir_fd, "db.sqlite", dir_fd, "locked.sqlite"),
    );
    try std.testing.expectEqual(
        @as(c_int, 0),
        renameat(dir_fd, "outside.sqlite", dir_fd, "db.sqlite"),
    );
    try std.testing.expectError(
        error.PathChanged,
        openAt(std.testing.allocator, dir_fd, "db.sqlite", .{
            .mode = .read_only,
            .pinned_main_fd = pinned_fd,
        }),
    );

    const child = fork();
    try std.testing.expect(child >= 0);
    if (child == 0) {
        const fd = openat(
            dir_fd,
            "locked.sqlite",
            o_rdwr | o_cloexec | o_nofollow,
            0,
        );
        if (fd < 0) _exit(2);
        const rc = lockf(fd, 2, 0);
        const blocked = rc < 0 and
            (std.c._errno().* == @intFromEnum(std.posix.E.AGAIN) or
                std.c._errno().* == @intFromEnum(std.posix.E.ACCES));
        _exit(if (blocked) 0 else 3);
    }
    var status: c_int = 0;
    try std.testing.expectEqual(child, waitpid(child, &status, 0));
    try std.testing.expectEqual(@as(c_int, 0), status);
}

test "confined SQLite keeps WAL and journal sidecars no-follow" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside",
        .data = "outside",
    });
    {
        var connection = try openAt(
            std.testing.allocator,
            dir_fd,
            "db.sqlite",
            .{ .mode = .read_write, .create = true },
        );
        defer connection.close();
        try std.testing.expectEqual(
            c.SQLITE_OK,
            c.sqlite3_exec(
                connection.db,
                "CREATE TABLE values_table(value INTEGER);",
                null,
                null,
                null,
            ),
        );
        try tmp.dir.symLink(
            std.testing.io,
            "outside",
            "db.sqlite-wal",
            .{},
        );
        const mode_rc = c.sqlite3_exec(
            connection.db,
            "PRAGMA journal_mode=WAL;",
            null,
            null,
            null,
        );
        const write_rc = if (mode_rc == c.SQLITE_OK)
            c.sqlite3_exec(
                connection.db,
                "BEGIN; INSERT INTO values_table VALUES (1); COMMIT;",
                null,
                null,
                null,
            )
        else
            mode_rc;
        try std.testing.expect(write_rc != c.SQLITE_OK);
    }
    try tmp.dir.deleteFile(std.testing.io, "db.sqlite-wal");
    {
        var connection = try openAt(
            std.testing.allocator,
            dir_fd,
            "db.sqlite",
            .{ .mode = .read_write },
        );
        defer connection.close();
        try std.testing.expectEqual(
            c.SQLITE_OK,
            c.sqlite3_exec(
                connection.db,
                "PRAGMA journal_mode=DELETE;",
                null,
                null,
                null,
            ),
        );
        try tmp.dir.symLink(
            std.testing.io,
            "outside",
            "db.sqlite-journal",
            .{},
        );
        try std.testing.expect(
            c.sqlite3_exec(
                connection.db,
                "BEGIN; INSERT INTO values_table VALUES (1); COMMIT;",
                null,
                null,
                null,
            ) != c.SQLITE_OK,
        );
    }

    const outside = try tmp.dir.readFileAlloc(
        std.testing.io,
        "outside",
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(outside);
    try std.testing.expectEqualStrings("outside", outside);
}

test "confined VFS rejects every non-allowlisted synthetic path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);
    var connection = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write, .create = true },
    );
    defer connection.close();

    const suffixes = [_][]const u8{
        "../outside",
        "nested/db.sqlite",
        "other.sqlite",
        "db.sqlite-wal.evil",
        "db.sqlite-mj escape",
        "db.sqlite/../outside",
    };
    for (suffixes) |suffix| {
        const path = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}{s}",
            .{ connection.handle.route_prefix, suffix },
            0,
        );
        defer std.testing.allocator.free(path);

        try std.testing.expectEqual(
            @as(c_int, -1),
            confinedOpen(path.ptr, o_rdonly, 0),
        );
        try std.testing.expectEqual(
            @intFromEnum(std.posix.E.ACCES),
            std.c._errno().*,
        );
        try std.testing.expectEqual(
            @as(c_int, -1),
            confinedAccess(path.ptr, f_ok),
        );
        try std.testing.expectEqual(
            @intFromEnum(std.posix.E.ACCES),
            std.c._errno().*,
        );
        try std.testing.expectEqual(
            @as(c_int, -1),
            confinedUnlink(path.ptr),
        );
        try std.testing.expectEqual(
            @intFromEnum(std.posix.E.ACCES),
            std.c._errno().*,
        );

        try std.testing.expectEqual(
            c.SQLITE_CANTOPEN,
            vfsOpen(
                &connection.handle.vfs,
                path.ptr,
                null,
                c.SQLITE_OPEN_READONLY,
                null,
            ),
        );
        var access_out: c_int = 1;
        try std.testing.expectEqual(
            c.SQLITE_CANTOPEN,
            vfsAccess(
                &connection.handle.vfs,
                path.ptr,
                c.SQLITE_ACCESS_EXISTS,
                &access_out,
            ),
        );
        try std.testing.expectEqual(
            c.SQLITE_CANTOPEN,
            vfsDelete(&connection.handle.vfs, path.ptr, 0),
        );
        var full_path: [std.fs.max_path_bytes]u8 = undefined;
        try std.testing.expectEqual(
            c.SQLITE_CANTOPEN,
            vfsFullPathname(
                &connection.handle.vfs,
                path.ptr,
                full_path.len,
                &full_path,
            ),
        );
    }
}

test "WAL connections share a stable CLOEXEC directory pin" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "outside");
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);

    var first = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write, .create = true },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            first.db,
            "PRAGMA journal_mode=WAL;" ++
                "CREATE TABLE values_table(value INTEGER);",
            null,
            null,
            null,
        ),
    );
    var second = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write },
    );
    try std.testing.expect(first.handle.database == second.handle.database);
    try std.testing.expect(
        first.handle.database.directory == second.handle.database.directory,
    );
    const shared_fd = first.handle.database.directory.fd;
    try std.testing.expect(
        (std.c.fcntl(shared_fd, std.c.F.GETFD) & std.c.FD_CLOEXEC) != 0,
    );
    var main_pin = second.pinMainFd();
    defer main_pin.deinit();
    try std.testing.expect(
        (std.c.fcntl(main_pin.fd, std.c.F.GETFD) & std.c.FD_CLOEXEC) != 0,
    );

    first.close();
    try std.testing.expect(std.c.fcntl(shared_fd, std.c.F.GETFD) >= 0);
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            second.db,
            "INSERT INTO values_table VALUES (1);",
            null,
            null,
            null,
        ),
    );
    second.close();
    main_pin.deinit();
    try std.testing.expectEqual(@as(c_int, -1), std.c.fcntl(
        shared_fd,
        std.c.F.GETFD,
    ));
    try std.testing.expectEqual(
        @intFromEnum(std.posix.E.BADF),
        std.c._errno().*,
    );

    const reused = std.c.fcntl(
        dir_fd,
        std.c.F.DUPFD_CLOEXEC,
        shared_fd,
    );
    try std.testing.expectEqual(shared_fd, reused);
    defer _ = std.c.close(reused);
    const stale = try std.fmt.allocPrint(
        std.testing.allocator,
        "/proc/self/fd/{d}/db.sqlite-wal",
        .{shared_fd},
    );
    defer std.testing.allocator.free(stale);
    lockRegistry();
    const classification = classifyPathLocked(stale);
    unlockRegistry();
    try std.testing.expect(classification == .unrelated);
    try std.testing.expect(registry_head == null);
    try std.testing.expect(directory_head == null);
    try std.testing.expect(database_head == null);

    var third = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write },
    );
    var fourth = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            third.db,
            "INSERT INTO values_table VALUES (2);",
            null,
            null,
            null,
        ),
    );
    var reader = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_only },
    );
    try std.testing.expect(
        reader.handle.database == third.handle.database,
    );
    try std.testing.expect(
        reader.handle.route_fd != third.handle.route_fd,
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        reader.handle.route_prefix,
        third.handle.route_prefix,
    ));
    try std.testing.expectEqual(
        @as(c_int, -1),
        confinedOpen(reader.handle.synthetic_path.ptr, o_rdwr, 0),
    );
    try std.testing.expectEqual(
        @intFromEnum(std.posix.E.ACCES),
        std.c._errno().*,
    );
    const writer_main = confinedOpen(
        third.handle.synthetic_path.ptr,
        o_rdwr,
        0,
    );
    try std.testing.expect(writer_main >= 0);
    _ = std.c.close(writer_main);
    const reader_journal = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}db.sqlite-journal",
        .{reader.handle.route_prefix},
        0,
    );
    defer std.testing.allocator.free(reader_journal);
    try std.testing.expectEqual(
        @as(c_int, -1),
        confinedOpen(reader_journal.ptr, o_rdwr | o_creat, 0o644),
    );
    try std.testing.expectEqual(
        @intFromEnum(std.posix.E.ACCES),
        std.c._errno().*,
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            reader.db,
            "SELECT * FROM values_table;",
            null,
            null,
            null,
        ),
    );
    try std.testing.expect(
        c.sqlite3_exec(
            reader.db,
            "INSERT INTO values_table VALUES (99);",
            null,
            null,
            null,
        ) != c.SQLITE_OK,
    );
    reader.close();
    const reverse_fd = third.handle.database.directory.fd;
    fourth.close();
    try std.testing.expect(std.c.fcntl(reverse_fd, std.c.F.GETFD) >= 0);
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            third.db,
            "INSERT INTO values_table VALUES (3);",
            null,
            null,
            null,
        ),
    );
    third.close();
}

test "read-only WAL opens existing sidecars before and after a writer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const db_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/db.sqlite",
        .{base},
        0,
    );
    defer std.testing.allocator.free(db_path);
    try createPersistentWal(db_path.ptr);

    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);
    try std.testing.expect(sidecarExists(dir_fd, "db.sqlite-wal"));
    try std.testing.expect(sidecarExists(dir_fd, "db.sqlite-shm"));

    var reader = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_only },
    );
    const reader_shm = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}db.sqlite-shm",
        .{reader.handle.route_prefix},
        0,
    );
    defer std.testing.allocator.free(reader_shm);
    inline for (.{ o_rdwr, o_rdwr | o_creat }) |flags| {
        try std.testing.expectEqual(
            @as(c_int, -1),
            confinedOpen(reader_shm.ptr, flags, 0o644),
        );
        try std.testing.expectEqual(
            @intFromEnum(std.posix.E.ACCES),
            std.c._errno().*,
        );
    }
    try std.testing.expectEqual(
        @as(c_int, -1),
        confinedUnlink(reader_shm.ptr),
    );
    try std.testing.expectEqual(
        @intFromEnum(std.posix.E.ACCES),
        std.c._errno().*,
    );
    try std.testing.expect(sidecarExists(dir_fd, "db.sqlite-shm"));
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            reader.db,
            "SELECT * FROM values_table;",
            null,
            null,
            null,
        ),
    );

    var writer = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            writer.db,
            "INSERT INTO values_table VALUES (2);",
            null,
            null,
            null,
        ),
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            reader.db,
            "SELECT * FROM values_table;",
            null,
            null,
            null,
        ),
    );
    reader.close();
    writer.close();

    var writer_first = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            writer_first.db,
            "SELECT * FROM values_table;",
            null,
            null,
            null,
        ),
    );
    var reader_second = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_only },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            reader_second.db,
            "SELECT * FROM values_table;",
            null,
            null,
            null,
        ),
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            writer_first.db,
            "INSERT INTO values_table VALUES (3);",
            null,
            null,
            null,
        ),
    );
    reader_second.close();
    writer_first.close();
}

test "read-only WAL identity-checks existing sidecars" {
    const Mutation = struct {
        dir_fd: c_int,

        fn run(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            _ = renameat(
                self.dir_fd,
                "db.sqlite-shm",
                self.dir_fd,
                "saved.sqlite-shm",
            );
            _ = renameat(
                self.dir_fd,
                "outside.sqlite-shm",
                self.dir_fd,
                "db.sqlite-shm",
            );
        }
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const db_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/db.sqlite",
        .{base},
        0,
    );
    defer std.testing.allocator.free(db_path);
    try createPersistentWal(db_path.ptr);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside.sqlite-shm",
        .data = "outside",
    });

    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);
    var mutation = Mutation{ .dir_fd = dir_fd };
    try std.testing.expectError(
        error.PathChanged,
        openAt(std.testing.allocator, dir_fd, "db.sqlite", .{
            .mode = .read_only,
            .before_sqlite_open = Mutation.run,
            .mutation_context = &mutation,
        }),
    );
    const outside = try tmp.dir.readFileAlloc(
        std.testing.io,
        "db.sqlite-shm",
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(outside);
    try std.testing.expectEqualStrings("outside", outside);
}

test "read-only WAL never creates absent sidecars" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const db_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/db.sqlite",
        .{base},
        0,
    );
    defer std.testing.allocator.free(db_path);
    try createPersistentWal(db_path.ptr);

    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);
    try tmp.dir.deleteFile(std.testing.io, "db.sqlite-wal");
    try tmp.dir.deleteFile(std.testing.io, "db.sqlite-shm");
    try std.testing.expect(!sidecarExists(dir_fd, "db.sqlite-wal"));
    try std.testing.expect(!sidecarExists(dir_fd, "db.sqlite-shm"));

    var reader = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_only },
    );
    defer reader.close();
    _ = c.sqlite3_exec(
        reader.db,
        "SELECT * FROM values_table;",
        null,
        null,
        null,
    );
    inline for (.{ "db.sqlite-wal", "db.sqlite-shm" }) |name| {
        const path = try std.fmt.allocPrintSentinel(
            std.testing.allocator,
            "{s}{s}",
            .{ reader.handle.route_prefix, name },
            0,
        );
        defer std.testing.allocator.free(path);
        try std.testing.expectEqual(
            @as(c_int, -1),
            confinedOpen(path.ptr, o_rdwr | o_creat, 0o644),
        );
        try std.testing.expectEqual(
            @intFromEnum(std.posix.E.ACCES),
            std.c._errno().*,
        );
        try std.testing.expect(!sidecarExists(dir_fd, name));
    }
}

test "WAL cleanup retains its route across deterministic FD reuse" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "first");
    try tmp.dir.createDirPath(std.testing.io, "second");
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const first_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/first",
        .{base},
        0,
    );
    defer std.testing.allocator.free(first_path);
    const second_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/second",
        .{base},
        0,
    );
    defer std.testing.allocator.free(second_path);
    const first_dir_fd = std.c.open(first_path.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(first_dir_fd >= 0);
    defer _ = std.c.close(first_dir_fd);
    const second_dir_fd = std.c.open(second_path.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(second_dir_fd >= 0);
    defer _ = std.c.close(second_dir_fd);

    var first = try openAt(
        std.testing.allocator,
        first_dir_fd,
        "db.sqlite",
        .{ .mode = .read_write, .create = true },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            first.db,
            "PRAGMA journal_mode=WAL;" ++
                "CREATE TABLE values_table(value INTEGER);",
            null,
            null,
            null,
        ),
    );
    var first_peer = try openAt(
        std.testing.allocator,
        first_dir_fd,
        "db.sqlite",
        .{ .mode = .read_write },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            first_peer.db,
            "SELECT * FROM values_table;",
            null,
            null,
            null,
        ),
    );
    var second = try openAt(
        std.testing.allocator,
        second_dir_fd,
        "db.sqlite",
        .{ .mode = .read_write, .create = true },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            second.db,
            "PRAGMA journal_mode=WAL;" ++
                "CREATE TABLE values_table(value INTEGER);",
            null,
            null,
            null,
        ),
    );
    const second_shm_before = statRelativeFd(
        second_dir_fd,
        "db.sqlite-shm",
    ) orelse return error.TestUnexpectedResult;
    const retained_fd = first.handle.route_fd;
    const retained_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}db.sqlite-shm",
        .{first.handle.route_prefix},
    );
    defer std.testing.allocator.free(retained_path);

    first.close();
    try std.testing.expect(std.c.fcntl(retained_fd, std.c.F.GETFD) >= 0);
    lockRegistry();
    const retained_classification = classifyPathLocked(retained_path);
    const retained_authorization = switch (retained_classification) {
        .match => |match| match.route.database == first_peer.handle.database,
        else => false,
    };
    unlockRegistry();
    try std.testing.expect(retained_authorization);
    const blocked_reuse = std.c.fcntl(
        second_dir_fd,
        std.c.F.DUPFD_CLOEXEC,
        retained_fd,
    );
    try std.testing.expect(blocked_reuse > retained_fd);
    _ = std.c.close(blocked_reuse);
    try std.testing.expect(
        Identity.fromStat(second_shm_before).eql(Identity.fromStat(
            statRelativeFd(second_dir_fd, "db.sqlite-shm") orelse
                return error.TestUnexpectedResult,
        )),
    );

    first_peer.close();
    try std.testing.expectEqual(
        @as(c_int, -1),
        std.c.fcntl(retained_fd, std.c.F.GETFD),
    );
    const reused = std.c.fcntl(
        second_dir_fd,
        std.c.F.DUPFD_CLOEXEC,
        retained_fd,
    );
    try std.testing.expectEqual(retained_fd, reused);
    defer _ = std.c.close(reused);
    lockRegistry();
    const classification = classifyPathLocked(retained_path);
    unlockRegistry();
    try std.testing.expect(classification == .unrelated);
    try std.testing.expect(
        Identity.fromStat(second_shm_before).eql(Identity.fromStat(
            statRelativeFd(second_dir_fd, "db.sqlite-shm") orelse
                return error.TestUnexpectedResult,
        )),
    );
    second.close();
}

test "outstanding statements retain VFS state until a successful close" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const dir_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(dir_fd >= 0);
    defer _ = std.c.close(dir_fd);

    var connection = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_write, .create = true },
    );
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_exec(
            connection.db,
            "CREATE TABLE values_table(value INTEGER);",
            null,
            null,
            null,
        ),
    );
    var statement: ?*c.sqlite3_stmt = null;
    try std.testing.expectEqual(
        c.SQLITE_OK,
        c.sqlite3_prepare_v2(
            connection.db,
            "SELECT * FROM values_table;",
            -1,
            &statement,
            null,
        ),
    );
    const route_fd = connection.handle.route_fd;
    const stale_path = try std.testing.allocator.dupe(
        u8,
        connection.handle.synthetic_path,
    );
    defer std.testing.allocator.free(stale_path);
    try std.testing.expect(!connection.tryClose());
    try std.testing.expect(connection.db != null);
    try std.testing.expect(std.c.fcntl(route_fd, std.c.F.GETFD) >= 0);
    try std.testing.expect(registry_head != null);
    try std.testing.expect(database_head != null);
    try std.testing.expect(file_head != null);

    try std.testing.expectEqual(c.SQLITE_OK, c.sqlite3_finalize(statement));
    statement = null;
    try std.testing.expect(connection.tryClose());
    try std.testing.expectEqual(
        @as(c_int, -1),
        std.c.fcntl(route_fd, std.c.F.GETFD),
    );
    try std.testing.expectEqual(
        @intFromEnum(std.posix.E.BADF),
        std.c._errno().*,
    );
    const reused = std.c.fcntl(
        dir_fd,
        std.c.F.DUPFD_CLOEXEC,
        route_fd,
    );
    try std.testing.expectEqual(route_fd, reused);
    defer _ = std.c.close(reused);
    lockRegistry();
    const classification = classifyPathLocked(stale_path);
    unlockRegistry();
    try std.testing.expect(classification == .unrelated);
    try std.testing.expect(registry_head == null);
    try std.testing.expect(database_head == null);
    try std.testing.expect(directory_head == null);
    try std.testing.expect(file_head == null);
}
