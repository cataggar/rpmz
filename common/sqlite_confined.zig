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
    handle: *Handle,
    relative: []const u8,
};

const DirectoryPin = struct {
    allocator: Allocator,
    fd: c_int,
    identity: Identity,
    prefix: [:0]u8,
    refs: usize = 1,
    next: ?*DirectoryPin = null,
};

const Handle = struct {
    allocator: Allocator,
    directory: *DirectoryPin,
    main_fd: c_int,
    main_identity: Identity,
    writable: bool,
    basename: [:0]u8,
    synthetic_path: [:0]u8,
    vfs_name: [:0]u8,
    base: *c.sqlite3_vfs,
    vfs: c.sqlite3_vfs,
    tracked_sidecars: [3]?Identity = .{ null, null, null },
    next: ?*Handle = null,
};

pub const Connection = struct {
    db: ?*c.sqlite3,
    handle: *Handle,

    pub fn close(self: *Connection) void {
        _ = c.sqlite3_commit_hook(self.db, null, null);
        if (self.db != null) {
            _ = c.sqlite3_close_v2(self.db);
            self.db = null;
        }
        destroyHandle(self.handle);
        self.* = undefined;
    }

    pub fn verify(self: *const Connection) Error!void {
        lockRegistry();
        defer unlockRegistry();
        if (!verifyTrackedLocked(self.handle)) return error.PathChanged;
    }

    pub fn duplicateMainFd(self: *const Connection) Error!c_int {
        const duplicate = duplicateFdCloexec(self.handle.main_fd);
        if (duplicate < 0) return error.SyscallFailed;
        return duplicate;
    }
};

var registry_mutex: std.atomic.Mutex = .unlocked;
threadlocal var registry_lock_depth: usize = 0;
var registry_head: ?*Handle = null;
var directory_head: ?*DirectoryPin = null;
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
    errdefer releaseDirectoryPin(directory);

    const basename_z = allocator.dupeZ(u8, basename) catch
        return error.OutOfMemory;
    errdefer allocator.free(basename_z);
    if (statRelativeFd(directory.fd, basename_z.ptr)) |existing| {
        if ((existing.mode & s_ifmt) != s_ifreg or existing.nlink != 1)
            return error.UnsafeFile;
    }
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
    errdefer _ = std.c.close(main_fd);
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

    const synthetic_path = std.fmt.allocPrintSentinel(
        allocator,
        "{s}{s}",
        .{ directory.prefix, basename },
        0,
    ) catch return error.OutOfMemory;
    errdefer allocator.free(synthetic_path);
    const vfs_id = allocateVfsId();
    const vfs_name = std.fmt.allocPrintSentinel(
        allocator,
        "tdnf-confined-{x}",
        .{vfs_id},
        0,
    ) catch return error.OutOfMemory;
    errdefer allocator.free(vfs_name);
    const handle = allocator.create(Handle) catch return error.OutOfMemory;
    errdefer allocator.destroy(handle);
    handle.* = .{
        .allocator = allocator,
        .directory = directory,
        .main_fd = main_fd,
        .main_identity = Identity.fromStat(main_stat),
        .writable = options.mode == .read_write,
        .basename = basename_z,
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
    addHandle(handle);
    var listed = true;
    errdefer {
        if (listed) removeHandle(handle);
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
        if (db != null) _ = c.sqlite3_close_v2(db);
        return error.SqliteOpenFailed;
    }
    errdefer _ = c.sqlite3_close_v2(db);
    if (!verifyHandle(handle)) return error.PathChanged;
    _ = c.sqlite3_commit_hook(db, commitHook, handle);

    registered = false;
    listed = false;
    return .{ .db = db, .handle = handle };
}

const RawConnection = extern struct {
    db: ?*c.sqlite3,
    handle: ?*anyopaque,
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
) callconv(.c) void {
    const handle = raw.handle orelse return;
    var connection = Connection{
        .db = raw.db,
        .handle = @ptrCast(@alignCast(handle)),
    };
    connection.close();
    raw.* = .{ .db = null, .handle = null };
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

pub export fn tdnf_sqlite_confined_duplicate_main_fd(
    raw: *const RawConnection,
) callconv(.c) c_int {
    const handle = raw.handle orelse return -1;
    const connection = Connection{
        .db = raw.db,
        .handle = @ptrCast(@alignCast(handle)),
    };
    return connection.duplicateMainFd() catch -1;
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
    removeHandle(handle);
    _ = std.c.close(handle.main_fd);
    releaseDirectoryPin(handle.directory);
    const allocator = handle.allocator;
    allocator.free(handle.basename);
    allocator.free(handle.synthetic_path);
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

    const prefix = std.fmt.allocPrintSentinel(
        allocator,
        "/proc/self/fd/{d}/",
        .{duplicate},
        0,
    ) catch return error.OutOfMemory;
    errdefer allocator.free(prefix);
    const pin = allocator.create(DirectoryPin) catch
        return error.OutOfMemory;
    errdefer allocator.destroy(pin);
    pin.* = .{
        .allocator = allocator,
        .fd = duplicate,
        .identity = identity,
        .prefix = prefix,
    };

    lockRegistry();
    cursor = directory_head;
    while (cursor) |existing| : (cursor = existing.next) {
        if (existing.identity.eql(identity)) {
            existing.refs += 1;
            unlockRegistry();
            allocator.destroy(pin);
            allocator.free(prefix);
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
    allocator.free(pin.prefix);
    allocator.destroy(pin);
}

fn allocateVfsId() u64 {
    lockRegistry();
    defer unlockRegistry();
    const result = next_vfs_id;
    next_vfs_id +%= 1;
    return result;
}

fn addHandle(handle: *Handle) void {
    lockRegistry();
    defer unlockRegistry();
    handle.next = registry_head;
    registry_head = handle;
}

fn removeHandle(handle: *Handle) void {
    lockRegistry();
    defer unlockRegistry();
    var cursor = &registry_head;
    while (cursor.*) |current| {
        if (current == handle) {
            cursor.* = current.next;
            handle.next = null;
            return;
        }
        cursor = &current.next;
    }
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
    require_writable: bool,
) PathClassification {
    var recognized = false;
    var cursor = registry_head;
    while (cursor) |handle| : (cursor = handle.next) {
        const prefix = handle.directory.prefix;
        if (std.mem.startsWith(u8, path, prefix)) {
            recognized = true;
            const relative = path[prefix.len..];
            if (allowedRelative(handle, relative) and
                (!require_writable or handle.writable))
            {
                return .{ .match = .{
                    .handle = handle,
                    .relative = relative,
                } };
            }
        }
    }
    return if (recognized) .rejected else .unrelated;
}

const DirectoryClassification = union(enum) {
    match: *Handle,
    rejected,
    unrelated,
};

fn classifyDirectoryLocked(
    path: []const u8,
    require_writable: bool,
) DirectoryClassification {
    var recognized = false;
    var cursor = registry_head;
    while (cursor) |handle| : (cursor = handle.next) {
        const prefix = handle.directory.prefix;
        const directory = prefix[0 .. prefix.len - 1];
        if (!std.mem.eql(u8, path, directory)) continue;
        recognized = true;
        if (!require_writable or handle.writable)
            return .{ .match = handle };
    }
    return if (recognized) .rejected else .unrelated;
}

fn allowedRelative(handle: *const Handle, relative: []const u8) bool {
    if (relative.len == 0 or std.mem.indexOfScalar(u8, relative, '/') != null)
        return false;
    if (std.mem.eql(u8, relative, handle.basename)) return true;
    if (!std.mem.startsWith(u8, relative, handle.basename)) return false;
    const suffix = relative[handle.basename.len..];
    return std.mem.eql(u8, suffix, "-journal") or
        std.mem.eql(u8, suffix, "-wal") or
        std.mem.eql(u8, suffix, "-shm");
}

fn sidecarKind(handle: *const Handle, relative: []const u8) ?SidecarKind {
    if (!std.mem.startsWith(u8, relative, handle.basename)) return null;
    const suffix = relative[handle.basename.len..];
    if (std.mem.eql(u8, suffix, "-journal")) return .journal;
    if (std.mem.eql(u8, suffix, "-wal")) return .wal;
    if (std.mem.eql(u8, suffix, "-shm")) return .shm;
    return null;
}

fn sidecarIndex(kind: SidecarKind) usize {
    return @intFromEnum(kind);
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
    handle: *const Handle,
    relative: []const u8,
) ?FileStat {
    var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
    if (relative.len >= name_buffer.len) return null;
    @memcpy(name_buffer[0..relative.len], relative);
    name_buffer[relative.len] = 0;
    return statRelativeFd(handle.directory.fd, @ptrCast(&name_buffer));
}

fn verifyTrackedLocked(handle: *const Handle) bool {
    const main = statRelative(handle, handle.basename) orelse return false;
    if ((main.mode & s_ifmt) != s_ifreg or
        main.nlink != 1 or
        !Identity.fromStat(main).eql(handle.main_identity))
    {
        return false;
    }
    inline for (.{ SidecarKind.journal, .wal, .shm }) |kind| {
        if (handle.tracked_sidecars[sidecarIndex(kind)]) |identity| {
            var name_buffer: [std.fs.max_name_bytes]u8 = undefined;
            const name = std.fmt.bufPrint(
                &name_buffer,
                "{s}-{s}",
                .{ handle.basename, @tagName(kind) },
            ) catch return false;
            const st = statRelative(handle, name) orelse return false;
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
    const match = switch (classifyPathLocked(
        std.mem.span(raw_path),
        require_writable,
    )) {
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
    const handle = match.handle;
    if (std.mem.eql(u8, match.relative, handle.basename)) {
        const current = statRelative(handle, handle.basename) orelse {
            setErrno(@intFromEnum(std.posix.E.STALE));
            return -1;
        };
        if ((current.mode & s_ifmt) != s_ifreg or
            current.nlink != 1 or
            !Identity.fromStat(current).eql(handle.main_identity))
        {
            setErrno(@intFromEnum(std.posix.E.STALE));
            return -1;
        }
        if (!handle.writable and (flags & o_accmode) != o_rdonly) {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        }
        return duplicateFdCloexec(handle.main_fd);
    }

    var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
    if (match.relative.len >= name_buffer.len) {
        setErrno(@intFromEnum(std.posix.E.NAMETOOLONG));
        return -1;
    }
    @memcpy(name_buffer[0..match.relative.len], match.relative);
    name_buffer[match.relative.len] = 0;
    const fd = openat(
        handle.directory.fd,
        @ptrCast(&name_buffer),
        flags | o_cloexec | o_nofollow,
        @intCast(mode),
    );
    if (fd < 0) return fd;
    const st = regularSingleLinkStat(fd) catch {
        _ = std.c.close(fd);
        setErrno(@intFromEnum(std.posix.E.LOOP));
        return -1;
    };
    if (sidecarKind(handle, match.relative)) |kind| {
        const identity = Identity.fromStat(st);
        const slot = &handle.tracked_sidecars[sidecarIndex(kind)];
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
    switch (classifyDirectoryLocked(path, mode == w_ok)) {
        .match => return 0,
        .rejected => {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        },
        .unrelated => {},
    }
    const match = switch (classifyPathLocked(path, mode == w_ok)) {
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
    const st = statRelative(match.handle, match.relative) orelse return -1;
    if ((st.mode & s_ifmt) != s_ifreg or st.nlink != 1) {
        setErrno(@intFromEnum(std.posix.E.LOOP));
        return -1;
    }
    if (mode == w_ok and !match.handle.writable) {
        setErrno(@intFromEnum(std.posix.E.ACCES));
        return -1;
    }
    return 0;
}

fn confinedUnlink(raw_path: [*:0]const u8) callconv(.c) c_int {
    lockRegistry();
    defer unlockRegistry();
    const match = switch (classifyPathLocked(
        std.mem.span(raw_path),
        true,
    )) {
        .match => |value| value,
        .rejected => {
            setErrno(@intFromEnum(std.posix.E.ACCES));
            return -1;
        },
        .unrelated => return original(UnlinkFn, original_unlink)(raw_path),
    };
    if (std.mem.eql(u8, match.relative, match.handle.basename)) {
        setErrno(@intFromEnum(std.posix.E.PERM));
        return -1;
    }
    if (statRelative(match.handle, match.relative)) |st| {
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
        match.handle.directory.fd,
        @ptrCast(&name_buffer),
        0,
    );
    if (rc == 0) {
        if (sidecarKind(match.handle, match.relative)) |kind|
            match.handle.tracked_sidecars[sidecarIndex(kind)] = null;
    }
    return rc;
}

fn confinedOpenDirectory(
    raw_path: [*:0]const u8,
    out: *c_int,
) callconv(.c) c_int {
    lockRegistry();
    defer unlockRegistry();
    const handle = switch (classifyDirectoryLocked(
        std.mem.span(raw_path),
        false,
    )) {
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
    const fd = duplicateFdCloexec(handle.directory.fd);
    if (fd < 0) return -1;
    out.* = fd;
    return 0;
}

fn vfsHandle(vfs: [*c]c.sqlite3_vfs) *Handle {
    return @ptrCast(@alignCast(vfs.*.pAppData.?));
}

fn pathAllowedForHandle(handle: *const Handle, path: []const u8) bool {
    const prefix = handle.directory.prefix;
    return std.mem.startsWith(u8, path, prefix) and
        allowedRelative(handle, path[prefix.len..]);
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
    return handle.base.xOpen.?(
        handle.base,
        name,
        file,
        flags | c.SQLITE_OPEN_NOFOLLOW,
        out_flags,
    );
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
    if (confinedUnlink(@ptrCast(name)) != 0) {
        if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
            return c.SQLITE_OK;
        return c.SQLITE_IOERR_DELETE;
    }
    if (sync_dir != 0 and fsync(handle.directory.fd) != 0)
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
            .{ connection.handle.directory.prefix, suffix },
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
    try std.testing.expect(first.handle.directory == second.handle.directory);
    const shared_fd = first.handle.directory.fd;
    try std.testing.expect(
        (std.c.fcntl(shared_fd, std.c.F.GETFD) & std.c.FD_CLOEXEC) != 0,
    );
    const duplicate_main = try second.duplicateMainFd();
    defer _ = std.c.close(duplicate_main);
    try std.testing.expect(
        (std.c.fcntl(duplicate_main, std.c.F.GETFD) & std.c.FD_CLOEXEC) != 0,
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
    const classification = classifyPathLocked(stale, false);
    unlockRegistry();
    try std.testing.expect(classification == .unrelated);
    try std.testing.expect(registry_head == null);
    try std.testing.expect(directory_head == null);

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
    var reader = try openAt(
        std.testing.allocator,
        dir_fd,
        "db.sqlite",
        .{ .mode = .read_only },
    );
    try std.testing.expect(
        reader.handle.directory == third.handle.directory,
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
    const reverse_fd = third.handle.directory.fd;
    fourth.close();
    try std.testing.expect(std.c.fcntl(reverse_fd, std.c.F.GETFD) >= 0);
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
    third.close();
}
