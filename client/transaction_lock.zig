//! Shared target lock for ordinary and replay transactions.

const std = @import("std");
const builtin = @import("builtin");
const txn_config = @import("rpm_txn_config");

const Allocator = std.mem.Allocator;
const mode_type_mask: u16 = 0o170000;
const mode_directory: u16 = 0o040000;
const mode_regular: u16 = 0o100000;
const lock_exclusive: c_int = 2;
const lock_nonblocking: c_int = 4;
const lock_unlock: c_int = 8;
// Root targets lock directly here. Non-root target owners use a private
// uid-scoped child created by a privileged caller.
const default_lock_parent = "/var/lib/tdnf/locks";

extern fn flock(fd: c_int, operation: c_int) callconv(.c) c_int;
extern fn fork() callconv(.c) c_int;
extern fn waitpid(pid: c_int, status: *c_int, options: c_int) callconv(.c) c_int;
extern fn setgid(gid: u32) callconv(.c) c_int;
extern fn setuid(uid: u32) callconv(.c) c_int;
extern fn chown(path: [*:0]const u8, uid: u32, gid: u32) callconv(.c) c_int;
extern fn fchown(fd: c_int, uid: u32, gid: u32) callconv(.c) c_int;
const Passwd = extern struct {
    name: ?[*:0]u8,
    passwd: ?[*:0]u8,
    uid: u32,
    gid: u32,
    gecos: ?[*:0]u8,
    dir: ?[*:0]u8,
    shell: ?[*:0]u8,
};
extern fn getpwuid_r(
    uid: u32,
    pwd: *Passwd,
    buffer: [*]u8,
    buffer_len: usize,
    result: *?*Passwd,
) callconv(.c) c_int;
extern fn _exit(status: c_int) callconv(.c) noreturn;

pub const Error = error{
    InvalidTarget,
    LockFailed,
    WouldBlock,
    OutOfMemory,
};

pub const Guard = struct {
    pinned_config: txn_config.TxnConfig,
    lock_fd: c_int,

    pub fn config(self: *Guard) *txn_config.TxnConfig {
        return &self.pinned_config;
    }

    pub fn deinit(self: *Guard) void {
        self.pinned_config.deinit();
        _ = flock(self.lock_fd, lock_unlock);
        _ = std.c.close(self.lock_fd);
        self.lock_fd = -1;
    }
};

pub fn acquire(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
) Error!Guard {
    return acquireInDirectoryMode(allocator, config, "", true, true);
}

pub fn tryAcquire(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
) Error!Guard {
    return acquireInDirectoryMode(allocator, config, "", false, true);
}

pub fn acquireRoot(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
) Error!Guard {
    return acquireInDirectoryMode(allocator, config, "", true, false);
}

pub fn tryAcquireInDirectory(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
    lock_directory: []const u8,
) Error!Guard {
    return acquireInDirectoryMode(
        allocator,
        config,
        lock_directory,
        false,
        true,
    );
}

pub fn acquireInDirectory(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
    lock_directory: []const u8,
    wait: bool,
) Error!Guard {
    return acquireInDirectoryMode(
        allocator,
        config,
        lock_directory,
        wait,
        true,
    );
}

fn acquireInDirectoryMode(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
    lock_directory: []const u8,
    wait: bool,
    finalize_rpmdb: bool,
) Error!Guard {
    const root_path = try allocator.dupeZ(u8, config.installRoot());
    defer allocator.free(root_path);
    const root_fd = std.c.open(root_path.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    if (root_fd < 0) return error.InvalidTarget;
    defer _ = std.c.close(root_fd);
    const target = try fdTarget(root_fd);
    const euid: u32 = @intCast(std.c.geteuid());
    if (!privilegedRoot() and euid != target.owner_uid)
        return error.InvalidTarget;
    const lock_fd = if (lock_directory.len != 0)
        try openProtectedLock(
            allocator,
            lock_directory,
            target.identity,
            euid,
            wait,
        )
    else blk: {
        if (openDefaultProtectedLock(allocator, target, wait)) |fd| {
            break :blk fd;
        } else |err| {
            if (!builtin.is_test or privilegedRoot() or
                err != error.LockFailed)
            {
                return err;
            }
        }
        const test_directory = try testLockDirectoryAlloc(allocator, euid);
        defer allocator.free(test_directory);
        break :blk try openProtectedLock(
            allocator,
            test_directory,
            target.identity,
            euid,
            wait,
        );
    };
    errdefer _ = std.c.close(lock_fd);
    errdefer _ = flock(lock_fd, lock_unlock);

    var pinned_config = (if (finalize_rpmdb)
        config.cloneWithPinnedInstallRoot(
            allocator,
            config.installRoot(),
            root_fd,
        )
    else
        config.cloneWithPinnedInstallRootDeferredRpmDb(
            allocator,
            config.installRoot(),
            root_fd,
        )) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidTarget,
    };
    errdefer pinned_config.deinit();
    pinned_config.markTargetLockHeld();
    return .{
        .pinned_config = pinned_config,
        .lock_fd = lock_fd,
    };
}

fn defaultLockDirectoryAlloc(
    allocator: Allocator,
    owner_uid: u32,
) Error![]u8 {
    if (owner_uid == systemRootUid()) {
        return allocator.dupe(u8, default_lock_parent) catch
            error.OutOfMemory;
    }
    return std.fmt.allocPrint(
        allocator,
        "{s}/uid-{d}",
        .{ default_lock_parent, owner_uid },
    ) catch error.OutOfMemory;
}

fn testLockDirectoryAlloc(
    allocator: Allocator,
    owner_uid: u32,
) Error![]u8 {
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    switch (std.os.linux.errno(std.os.linux.getcwd(
        cwd_buffer[0..].ptr,
        cwd_buffer.len,
    ))) {
        .SUCCESS => {},
        else => return error.LockFailed,
    }
    const cwd_length = std.mem.findScalar(u8, &cwd_buffer, 0) orelse
        return error.LockFailed;
    return std.fmt.allocPrint(
        allocator,
        "{s}/.zig-cache/tdnf-test-locks-{d}",
        .{ cwd_buffer[0..cwd_length], owner_uid },
    ) catch error.OutOfMemory;
}

fn safeComponent(component: []const u8) bool {
    return component.len != 0 and
        component.len <= std.fs.max_name_bytes and
        !std.mem.eql(u8, component, ".") and
        !std.mem.eql(u8, component, "..") and
        std.mem.indexOfScalar(u8, component, 0) == null;
}

fn systemRootUid() u32 {
    var stat = std.mem.zeroes(std.os.linux.Statx);
    if (std.c.statx(
        std.os.linux.AT.FDCWD,
        "/",
        std.os.linux.AT.SYMLINK_NOFOLLOW,
        .{ .TYPE = true, .UID = true },
        &stat,
    ) != 0) return 0;
    return stat.uid;
}

fn privilegedRoot() bool {
    return std.c.geteuid() == 0 and systemRootUid() == 0;
}

fn directoryStat(fd: c_int) Error!std.os.linux.Statx {
    var stat = std.mem.zeroes(std.os.linux.Statx);
    if (std.c.statx(
        fd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        std.os.linux.STATX.BASIC_STATS,
        &stat,
    ) != 0 or (stat.mode & mode_type_mask) != mode_directory) {
        return error.LockFailed;
    }
    return stat;
}

fn openPrivateLockDirectory(path: []const u8) Error!c_int {
    if (path.len < 2 or path[0] != '/' or path[path.len - 1] == '/')
        return error.LockFailed;
    const euid: u32 = @intCast(std.c.geteuid());
    var current = std.c.open("/", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    if (current < 0) return error.LockFailed;
    errdefer _ = std.c.close(current);

    var components = std.mem.splitScalar(u8, path[1..], '/');
    var component = components.next() orelse return error.LockFailed;
    while (true) {
        if (!safeComponent(component)) return error.LockFailed;
        var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
        @memcpy(name_buffer[0..component.len], component);
        name_buffer[component.len] = 0;
        const name: [*:0]const u8 = @ptrCast(&name_buffer);
        const next_component = components.next();
        var next = std.c.openat(current, name, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (next < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
        {
            if (std.c.mkdirat(current, name, 0o700) != 0 and
                std.c._errno().* != @intFromEnum(std.posix.E.EXIST))
                return error.LockFailed;
            next = std.c.openat(current, name, .{
                .ACCMODE = .RDONLY,
                .DIRECTORY = true,
                .CLOEXEC = true,
                .NOFOLLOW = true,
            });
        }
        if (next < 0) return error.LockFailed;
        const stat = directoryStat(next) catch |err| {
            _ = std.c.close(next);
            return err;
        };
        if (next_component == null) {
            if (stat.uid != euid or (stat.mode & 0o7777) != 0o700) {
                _ = std.c.close(next);
                return error.LockFailed;
            }
        }
        _ = std.c.close(current);
        current = next;
        component = next_component orelse break;
    }
    return current;
}

fn openDedicatedLockDirectoryAt(
    parent_fd: c_int,
    name: [*:0]const u8,
    owner_uid: u32,
    create_missing: bool,
) Error!c_int {
    var directory_fd = std.c.openat(parent_fd, name, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    var created = false;
    if (directory_fd < 0 and
        std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
    {
        if (!create_missing) return error.LockFailed;
        if (std.c.mkdirat(parent_fd, name, 0o755) == 0) {
            created = true;
        } else if (std.c._errno().* != @intFromEnum(std.posix.E.EXIST)) {
            return error.LockFailed;
        }
        directory_fd = std.c.openat(parent_fd, name, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
    }
    if (directory_fd < 0) return error.LockFailed;
    errdefer _ = std.c.close(directory_fd);
    if (created and std.c.fchmod(directory_fd, 0o755) != 0)
        return error.LockFailed;
    const stat = try directoryStat(directory_fd);
    if (stat.uid != owner_uid or (stat.mode & 0o7777) != 0o755)
        return error.LockFailed;
    return directory_fd;
}

fn openRootLockParentAt(path: []const u8) Error!c_int {
    if (path.len < 2 or path[0] != '/' or path[path.len - 1] == '/')
        return error.LockFailed;
    const root_uid = systemRootUid();
    var current = std.c.open("/", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    if (current < 0) return error.LockFailed;
    errdefer _ = std.c.close(current);

    var components = std.mem.splitScalar(u8, path[1..], '/');
    var component = components.next() orelse return error.LockFailed;
    while (true) {
        if (!safeComponent(component)) return error.LockFailed;
        var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
        @memcpy(name_buffer[0..component.len], component);
        name_buffer[component.len] = 0;
        const name: [*:0]const u8 = @ptrCast(&name_buffer);
        const next_component = components.next();
        if (next_component == null) {
            const next = try openDedicatedLockDirectoryAt(
                current,
                name,
                root_uid,
                privilegedRoot(),
            );
            _ = std.c.close(current);
            return next;
        }
        var next = std.c.openat(current, name, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (next < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
        {
            if (!privilegedRoot()) return error.LockFailed;
            if (std.c.mkdirat(current, name, 0o755) != 0 and
                std.c._errno().* != @intFromEnum(std.posix.E.EXIST))
            {
                return error.LockFailed;
            }
            next = std.c.openat(current, name, .{
                .ACCMODE = .RDONLY,
                .DIRECTORY = true,
                .CLOEXEC = true,
                .NOFOLLOW = true,
            });
        }
        if (next < 0) return error.LockFailed;
        const stat = directoryStat(next) catch |err| {
            _ = std.c.close(next);
            return err;
        };
        if (stat.uid != root_uid or (stat.mode & 0o022) != 0) {
            _ = std.c.close(next);
            return error.LockFailed;
        }
        _ = std.c.close(current);
        current = next;
        component = next_component.?;
    }
}

fn openRootLockParent() Error!c_int {
    return openRootLockParentAt(default_lock_parent);
}

fn ownerDirectoryName(
    target: Target,
    buffer: *[64]u8,
) Error![:0]u8 {
    return std.fmt.bufPrintZ(
        buffer,
        "uid-{d}",
        .{target.owner_uid},
    ) catch error.LockFailed;
}

fn openGlobalOwnerDirectoryIfExists(
    parent_fd: c_int,
    target: Target,
) Error!?c_int {
    var name_buffer: [64]u8 = undefined;
    const name = try ownerDirectoryName(target, &name_buffer);
    const directory_fd = std.c.openat(parent_fd, name, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    if (directory_fd < 0) {
        if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
            return null;
        return error.LockFailed;
    }
    errdefer _ = std.c.close(directory_fd);
    const stat = try directoryStat(directory_fd);
    if (stat.uid != target.owner_uid or (stat.mode & 0o7777) != 0o700)
        return error.LockFailed;
    return directory_fd;
}

fn createGlobalOwnerDirectory(
    parent_fd: c_int,
    target: Target,
) Error!c_int {
    if (!privilegedRoot()) return error.LockFailed;
    var name_buffer: [64]u8 = undefined;
    const name = try ownerDirectoryName(target, &name_buffer);
    const created = std.c.mkdirat(parent_fd, name, 0o700) == 0;
    if (!created and std.c._errno().* != @intFromEnum(std.posix.E.EXIST))
        return error.LockFailed;
    const directory_fd = std.c.openat(parent_fd, name, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    if (directory_fd < 0) return error.LockFailed;
    errdefer _ = std.c.close(directory_fd);
    if (created and
        (fchown(directory_fd, target.owner_uid, target.owner_gid) != 0 or
            std.c.fchmod(directory_fd, 0o700) != 0))
    {
        return error.LockFailed;
    }
    const stat = try directoryStat(directory_fd);
    if (stat.uid != target.owner_uid or (stat.mode & 0o7777) != 0o700)
        return error.LockFailed;
    return directory_fd;
}

fn openOwnerHomeLockDirectory(target: Target) Error!c_int {
    var pwd = std.mem.zeroes(Passwd);
    var passwd_buffer: [16 * 1024]u8 = undefined;
    var result: ?*Passwd = null;
    if (getpwuid_r(
        target.owner_uid,
        &pwd,
        &passwd_buffer,
        passwd_buffer.len,
        &result,
    ) != 0 or result == null or pwd.dir == null) {
        return error.LockFailed;
    }
    const home = std.mem.span(pwd.dir.?);
    if (home.len < 2 or home[0] != '/' or home[home.len - 1] == '/')
        return error.LockFailed;

    var current = std.c.open("/", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    if (current < 0) return error.LockFailed;
    errdefer _ = std.c.close(current);
    var components = std.mem.splitScalar(u8, home[1..], '/');
    var component = components.next() orelse return error.LockFailed;
    while (true) {
        if (!safeComponent(component)) return error.LockFailed;
        var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
        @memcpy(name_buffer[0..component.len], component);
        name_buffer[component.len] = 0;
        const name: [*:0]const u8 = @ptrCast(&name_buffer);
        const next_component = components.next();
        const next = std.c.openat(current, name, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (next < 0) return error.LockFailed;
        const stat = directoryStat(next) catch |err| {
            _ = std.c.close(next);
            return err;
        };
        if (next_component == null) {
            if (stat.uid != target.owner_uid or (stat.mode & 0o022) != 0) {
                _ = std.c.close(next);
                return error.LockFailed;
            }
        } else if (stat.uid != systemRootUid() or (stat.mode & 0o022) != 0) {
            _ = std.c.close(next);
            return error.LockFailed;
        }
        _ = std.c.close(current);
        current = next;
        component = next_component orelse break;
    }

    const children = [_][*:0]const u8{ ".tdnf", "locks" };
    for (children) |child| {
        var next = std.c.openat(current, child, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        var created = false;
        if (next < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
        {
            if (std.c.mkdirat(current, child, 0o700) == 0) {
                created = true;
            } else if (std.c._errno().* != @intFromEnum(std.posix.E.EXIST)) {
                return error.LockFailed;
            }
            next = std.c.openat(current, child, .{
                .ACCMODE = .RDONLY,
                .DIRECTORY = true,
                .CLOEXEC = true,
                .NOFOLLOW = true,
            });
        }
        if (next < 0) return error.LockFailed;
        if (created and privilegedRoot() and
            (fchown(next, target.owner_uid, target.owner_gid) != 0 or
                std.c.fchmod(next, 0o700) != 0))
        {
            _ = std.c.close(next);
            return error.LockFailed;
        }
        const stat = directoryStat(next) catch |err| {
            _ = std.c.close(next);
            return err;
        };
        const permissions = stat.mode & 0o7777;
        if (stat.uid != target.owner_uid or permissions != 0o700) {
            _ = std.c.close(next);
            return error.LockFailed;
        }
        _ = std.c.close(current);
        current = next;
    }
    return current;
}

fn openDefaultTargetDirectory(target: Target) Error!c_int {
    if (target.owner_uid == systemRootUid())
        return openRootLockParent();

    var parent_fd: c_int = -1;
    if (openRootLockParent()) |fd| {
        parent_fd = fd;
        if (try openGlobalOwnerDirectoryIfExists(fd, target)) |directory_fd| {
            _ = std.c.close(fd);
            parent_fd = -1;
            return directory_fd;
        }
    } else |_| {}
    defer {
        if (parent_fd >= 0) _ = std.c.close(parent_fd);
    }

    if (openOwnerHomeLockDirectory(target)) |directory_fd| {
        return directory_fd;
    } else |home_err| {
        if (!privilegedRoot()) return home_err;
    }
    if (parent_fd < 0) parent_fd = try openRootLockParent();
    return createGlobalOwnerDirectory(parent_fd, target);
}

const LockFileStat = struct {
    identity: TargetIdentity,
    uid: u32,
    mode: u16,
    nlink: u32,
    size: u64,
};

fn lockFileStatAt(
    directory_fd: c_int,
    name: [*:0]const u8,
) ?LockFileStat {
    var stat = std.mem.zeroes(std.os.linux.Statx);
    if (std.c.statx(
        directory_fd,
        name,
        std.os.linux.AT.SYMLINK_NOFOLLOW,
        std.os.linux.STATX.BASIC_STATS,
        &stat,
    ) != 0) return null;
    return .{
        .identity = .{
            .dev_major = stat.dev_major,
            .dev_minor = stat.dev_minor,
            .inode = stat.ino,
        },
        .uid = stat.uid,
        .mode = stat.mode,
        .nlink = stat.nlink,
        .size = stat.size,
    };
}

fn lockFileStatFd(fd: c_int) ?LockFileStat {
    var stat = std.mem.zeroes(std.os.linux.Statx);
    if (std.c.statx(
        fd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        std.os.linux.STATX.BASIC_STATS,
        &stat,
    ) != 0) return null;
    return .{
        .identity = .{
            .dev_major = stat.dev_major,
            .dev_minor = stat.dev_minor,
            .inode = stat.ino,
        },
        .uid = stat.uid,
        .mode = stat.mode,
        .nlink = stat.nlink,
        .size = stat.size,
    };
}

fn validLockFile(
    stat: LockFileStat,
    owner_uid: u32,
) bool {
    return (stat.mode & mode_type_mask) == mode_regular and
        (stat.mode & 0o7777) == 0o600 and
        stat.nlink == 1 and
        stat.size == 0 and
        stat.uid == owner_uid;
}

fn openExistingLock(
    directory_fd: c_int,
    name: [*:0]const u8,
) c_int {
    return std.c.openat(directory_fd, name, .{
        .ACCMODE = .RDWR,
        .CLOEXEC = true,
        .NOFOLLOW = true,
        .NONBLOCK = true,
    });
}

fn flockForMode(fd: c_int, wait: bool) Error!void {
    const operation = lock_exclusive |
        (if (wait) @as(c_int, 0) else lock_nonblocking);
    if (flock(fd, operation) == 0) return;
    if (!wait and
        (std.c._errno().* == @intFromEnum(std.posix.E.AGAIN) or
            std.c._errno().* == @intFromEnum(std.posix.E.ACCES)))
    {
        return error.WouldBlock;
    }
    return error.LockFailed;
}

fn openProtectedLockAt(
    allocator: Allocator,
    directory_fd: c_int,
    root: TargetIdentity,
    owner_uid: u32,
    owner_gid: u32,
    wait: bool,
) Error!c_int {
    const name = std.fmt.allocPrintSentinel(
        allocator,
        "root-{x}-{x}-{x}.lock",
        .{ root.dev_major, root.dev_minor, root.inode },
        0,
    ) catch return error.OutOfMemory;
    defer allocator.free(name);

    while (true) {
        var fd = std.c.openat(directory_fd, name.ptr, .{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        }, @as(std.c.mode_t, 0o600));
        const created = fd >= 0;
        if (fd < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.EXIST))
        {
            fd = openExistingLock(directory_fd, name.ptr);
        }
        if (fd < 0) return error.LockFailed;
        if (created) {
            if (privilegedRoot() and owner_uid != systemRootUid() and
                fchown(fd, owner_uid, owner_gid) != 0)
            {
                _ = std.c.close(fd);
                return error.LockFailed;
            }
            if (std.c.fchmod(fd, 0o600) != 0) {
                _ = std.c.close(fd);
                return error.LockFailed;
            }
        }

        const opened = lockFileStatFd(fd) orelse {
            _ = std.c.close(fd);
            return error.LockFailed;
        };
        const named = lockFileStatAt(directory_fd, name.ptr) orelse {
            _ = std.c.close(fd);
            continue;
        };
        if (!opened.identity.eql(named.identity)) {
            _ = std.c.close(fd);
            continue;
        }
        if (!validLockFile(opened, owner_uid)) {
            _ = std.c.close(fd);
            return error.LockFailed;
        }

        flockForMode(fd, wait) catch |err| {
            _ = std.c.close(fd);
            return err;
        };
        const after = lockFileStatAt(directory_fd, name.ptr) orelse {
            _ = flock(fd, lock_unlock);
            _ = std.c.close(fd);
            continue;
        };
        if (!opened.identity.eql(after.identity) or
            !validLockFile(after, owner_uid))
        {
            _ = flock(fd, lock_unlock);
            _ = std.c.close(fd);
            continue;
        }
        return fd;
    }
}

fn openProtectedLock(
    allocator: Allocator,
    directory_path: []const u8,
    root: TargetIdentity,
    owner_uid: u32,
    wait: bool,
) Error!c_int {
    const directory_fd = try openPrivateLockDirectory(directory_path);
    defer _ = std.c.close(directory_fd);
    return openProtectedLockAt(
        allocator,
        directory_fd,
        root,
        owner_uid,
        @intCast(std.c.getegid()),
        wait,
    );
}

fn openDefaultProtectedLock(
    allocator: Allocator,
    target: Target,
    wait: bool,
) Error!c_int {
    const directory_fd = try openDefaultTargetDirectory(target);
    defer _ = std.c.close(directory_fd);
    return openProtectedLockAt(
        allocator,
        directory_fd,
        target.identity,
        target.owner_uid,
        target.owner_gid,
        wait,
    );
}

const TargetIdentity = struct {
    dev_major: u32,
    dev_minor: u32,
    inode: u64,

    fn eql(left: TargetIdentity, right: TargetIdentity) bool {
        return left.dev_major == right.dev_major and
            left.dev_minor == right.dev_minor and
            left.inode == right.inode;
    }
};

const Target = struct {
    identity: TargetIdentity,
    owner_uid: u32,
    owner_gid: u32,
};

fn fdTarget(fd: c_int) Error!Target {
    var stat = std.mem.zeroes(std.os.linux.Statx);
    if (std.c.statx(
        fd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        .{ .TYPE = true, .INO = true, .UID = true, .GID = true },
        &stat,
    ) != 0 or (stat.mode & mode_type_mask) != mode_directory) {
        return error.InvalidTarget;
    }
    return .{
        .identity = .{
            .dev_major = stat.dev_major,
            .dev_minor = stat.dev_minor,
            .inode = stat.ino,
        },
        .owner_uid = stat.uid,
        .owner_gid = stat.gid,
    };
}

fn fdIdentity(fd: c_int) Error!TargetIdentity {
    return (try fdTarget(fd)).identity;
}

test "global fallback lock namespace is environment independent" {
    const first = try defaultLockDirectoryAlloc(std.testing.allocator, 42);
    defer std.testing.allocator.free(first);
    const second = try defaultLockDirectoryAlloc(std.testing.allocator, 42);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings("/var/lib/tdnf/locks/uid-42", first);
    try std.testing.expectEqualStrings(first, second);
    const root = try defaultLockDirectoryAlloc(
        std.testing.allocator,
        systemRootUid(),
    );
    defer std.testing.allocator.free(root);
    try std.testing.expectEqualStrings(default_lock_parent, root);
}

test "default lock parent is root owned and not writable by local users" {
    const parent_fd = openRootLockParent() catch {
        if (!privilegedRoot()) return error.SkipZigTest;
        return error.TestUnexpectedResult;
    };
    defer _ = std.c.close(parent_fd);
    const stat = try directoryStat(parent_fd);
    try std.testing.expectEqual(systemRootUid(), stat.uid);
    try std.testing.expectEqual(@as(u16, 0o755), stat.mode & 0o7777);
    try std.testing.expectEqual(@as(u16, 0), stat.mode & 0o022);
}

test "new root lock parent works with restrictive umask" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
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
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    const target = try fdTarget(root_fd);
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const base_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    try std.testing.expect(base_fd >= 0);
    defer _ = std.c.close(base_fd);
    const owner_uid: u32 = @intCast(std.c.geteuid());

    const old_mask = std.c.umask(@as(std.c.mode_t, 0o077));
    defer _ = std.c.umask(old_mask);

    const first_directory_fd = try openDedicatedLockDirectoryAt(
        base_fd,
        "locks",
        owner_uid,
        true,
    );
    const first_stat = try directoryStat(first_directory_fd);
    try std.testing.expectEqual(
        @as(u16, 0o755),
        first_stat.mode & 0o7777,
    );
    const first_lock_fd = try openProtectedLockAt(
        std.testing.allocator,
        first_directory_fd,
        target.identity,
        target.owner_uid,
        target.owner_gid,
        false,
    );
    _ = flock(first_lock_fd, lock_unlock);
    _ = std.c.close(first_lock_fd);
    _ = std.c.close(first_directory_fd);

    const second_directory_fd = try openDedicatedLockDirectoryAt(
        base_fd,
        "locks",
        owner_uid,
        true,
    );
    defer _ = std.c.close(second_directory_fd);
    const second_lock_fd = try openProtectedLockAt(
        std.testing.allocator,
        second_directory_fd,
        target.identity,
        target.owner_uid,
        target.owner_gid,
        false,
    );
    _ = flock(second_lock_fd, lock_unlock);
    _ = std.c.close(second_lock_fd);
}

test "pre-existing root lock parent with wrong mode fails closed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "locks");
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const lock_directory = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "locks" },
    );
    defer std.testing.allocator.free(lock_directory);
    const lock_directory_z = try std.testing.allocator.dupeZ(
        u8,
        lock_directory,
    );
    defer std.testing.allocator.free(lock_directory_z);
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.chmod(lock_directory_z.ptr, 0o700),
    );
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const base_fd = std.c.open(base_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    try std.testing.expect(base_fd >= 0);
    defer _ = std.c.close(base_fd);

    try std.testing.expectError(
        error.LockFailed,
        openDedicatedLockDirectoryAt(
            base_fd,
            "locks",
            @intCast(std.c.geteuid()),
            true,
        ),
    );
    var stat = std.mem.zeroes(std.os.linux.Statx);
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.statx(
            std.os.linux.AT.FDCWD,
            lock_directory_z.ptr,
            std.os.linux.AT.SYMLINK_NOFOLLOW,
            std.os.linux.STATX.BASIC_STATS,
            &stat,
        ),
    );
    try std.testing.expectEqual(@as(u16, 0o700), stat.mode & 0o7777);
}

fn protectTestLockDirectory(path: []const u8) !void {
    const path_z = try std.testing.allocator.dupeZ(u8, path);
    defer std.testing.allocator.free(path_z);
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.chmod(path_z.ptr, 0o700),
    );
}

test "existing lock directory is validated without chmod" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "locks");
    try tmp.dir.createDirPath(std.testing.io, "root");
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const locks = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "locks" },
    );
    defer std.testing.allocator.free(locks);
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const locks_z = try std.testing.allocator.dupeZ(u8, locks);
    defer std.testing.allocator.free(locks_z);
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.chmod(locks_z.ptr, 0o755),
    );
    var config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer config.deinit();
    try std.testing.expectError(
        error.LockFailed,
        acquireInDirectory(
            std.testing.allocator,
            &config,
            locks,
            true,
        ),
    );
    var stat = std.mem.zeroes(std.os.linux.Statx);
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.statx(
            std.os.linux.AT.FDCWD,
            locks_z.ptr,
            std.os.linux.AT.SYMLINK_NOFOLLOW,
            std.os.linux.STATX.BASIC_STATS,
            &stat,
        ),
    );
    try std.testing.expectEqual(@as(u16, 0o755), stat.mode & 0o7777);
}

test "aliases and database paths share one install-root lock" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "locks");
    try tmp.dir.createDirPath(std.testing.io, "root-a/var/lib/rpm");
    try tmp.dir.createDirPath(std.testing.io, "root-b/var/lib/rpm");
    try tmp.dir.symLink(std.testing.io, "root-a", "root-link", .{});

    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const lock_directory = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "locks" },
    );
    defer std.testing.allocator.free(lock_directory);
    try protectTestLockDirectory(lock_directory);
    const root_a = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root-a" },
    );
    defer std.testing.allocator.free(root_a);
    const root_dot = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root-a", "." },
    );
    defer std.testing.allocator.free(root_dot);
    const root_trailing = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/",
        .{root_a},
    );
    defer std.testing.allocator.free(root_trailing);
    const root_link = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root-link" },
    );
    defer std.testing.allocator.free(root_link);
    const root_b = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root-b" },
    );
    defer std.testing.allocator.free(root_b);

    var normal_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root_a,
    );
    defer normal_config.deinit();
    try std.testing.expectError(
        error.InvalidInstallRoot,
        txn_config.TxnConfig.init(std.testing.allocator, root_dot),
    );
    var replay_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root_link,
    );
    defer replay_config.deinit();
    var trailing_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root_trailing,
    );
    defer trailing_config.deinit();
    try std.testing.expectEqualStrings(
        normal_config.installRoot(),
        trailing_config.installRoot(),
    );
    var distinct_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root_b,
    );
    defer distinct_config.deinit();
    var distinct_db_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root_a,
    );
    defer distinct_db_config.deinit();
    try distinct_db_config.setMacro(.dbpath, "/var/lib/other-rpm");

    var normal = try acquireInDirectory(
        std.testing.allocator,
        &normal_config,
        lock_directory,
        true,
    );
    defer normal.deinit();
    const root_probe_z = try std.testing.allocator.dupeZ(u8, root_a);
    defer std.testing.allocator.free(root_probe_z);
    const root_probe = std.c.open(root_probe_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_probe >= 0);
    defer _ = std.c.close(root_probe);
    try std.testing.expectEqual(
        @as(c_int, 0),
        flock(root_probe, lock_exclusive | lock_nonblocking),
    );
    _ = flock(root_probe, lock_unlock);

    const lock_dir_z = try std.testing.allocator.dupeZ(u8, lock_directory);
    defer std.testing.allocator.free(lock_dir_z);
    const lock_dir_fd = std.c.open(lock_dir_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    try std.testing.expect(lock_dir_fd >= 0);
    defer _ = std.c.close(lock_dir_fd);
    const root_identity = try fdIdentity(root_probe);
    const lock_name = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "root-{x}-{x}-{x}.lock",
        .{
            root_identity.dev_major,
            root_identity.dev_minor,
            root_identity.inode,
        },
        0,
    );
    defer std.testing.allocator.free(lock_name);
    const lock_stat = lockFileStatAt(lock_dir_fd, lock_name.ptr) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(validLockFile(
        lock_stat,
        @intCast(std.c.geteuid()),
    ));
    try std.testing.expectError(
        error.WouldBlock,
        tryAcquireInDirectory(
            std.testing.allocator,
            &replay_config,
            lock_directory,
        ),
    );
    try std.testing.expectError(
        error.WouldBlock,
        tryAcquireInDirectory(
            std.testing.allocator,
            &trailing_config,
            lock_directory,
        ),
    );

    var distinct = try tryAcquireInDirectory(
        std.testing.allocator,
        &distinct_config,
        lock_directory,
    );
    distinct.deinit();
    try std.testing.expectError(
        error.WouldBlock,
        tryAcquireInDirectory(
            std.testing.allocator,
            &distinct_db_config,
            lock_directory,
        ),
    );
}

test "resolved symlink target stays pinned after alias retarget" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "locks");
    try tmp.dir.createDirPath(std.testing.io, "root-a");
    try tmp.dir.createDirPath(std.testing.io, "root-b");
    try tmp.dir.symLink(std.testing.io, "root-a", "root-link", .{});

    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const lock_directory = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "locks" },
    );
    defer std.testing.allocator.free(lock_directory);
    try protectTestLockDirectory(lock_directory);
    const root_a = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root-a" },
    );
    defer std.testing.allocator.free(root_a);
    const root_b = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root-b" },
    );
    defer std.testing.allocator.free(root_b);
    const root_link = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root-link" },
    );
    defer std.testing.allocator.free(root_link);

    var alias_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root_link,
    );
    defer alias_config.deinit();
    var guard = try acquireInDirectory(
        std.testing.allocator,
        &alias_config,
        lock_directory,
        true,
    );
    defer guard.deinit();

    try tmp.dir.deleteFile(std.testing.io, "root-link");
    try tmp.dir.symLink(std.testing.io, "root-b", "root-link", .{});

    const pinned_fd = guard.config().pinnedInstallRootFd().?;
    const root_a_z = try std.testing.allocator.dupeZ(u8, root_a);
    defer std.testing.allocator.free(root_a_z);
    const root_b_z = try std.testing.allocator.dupeZ(u8, root_b);
    defer std.testing.allocator.free(root_b_z);
    const root_a_fd = std.c.open(root_a_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_a_fd >= 0);
    defer _ = std.c.close(root_a_fd);
    const root_b_fd = std.c.open(root_b_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_b_fd >= 0);
    defer _ = std.c.close(root_b_fd);
    const pinned_identity = try fdIdentity(pinned_fd);
    const root_a_identity = try fdIdentity(root_a_fd);
    const root_b_identity = try fdIdentity(root_b_fd);
    try std.testing.expectEqual(root_a_identity, pinned_identity);
    try std.testing.expect(
        root_b_identity.dev_major != pinned_identity.dev_major or
            root_b_identity.dev_minor != pinned_identity.dev_minor or
            root_b_identity.inode != pinned_identity.inode,
    );
}

test "protected lock object rejects a preplaced symlink" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "locks");
    try tmp.dir.createDirPath(std.testing.io, "root");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside",
        .data = "",
    });
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
    const locks = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "locks" },
    );
    defer std.testing.allocator.free(locks);
    try protectTestLockDirectory(locks);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    const identity = try fdIdentity(root_fd);
    const lock_name = try std.fmt.allocPrint(
        std.testing.allocator,
        "locks/root-{x}-{x}-{x}.lock",
        .{ identity.dev_major, identity.dev_minor, identity.inode },
    );
    defer std.testing.allocator.free(lock_name);
    try tmp.dir.symLink(
        std.testing.io,
        "../outside",
        lock_name,
        .{},
    );

    var config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer config.deinit();
    try std.testing.expectError(
        error.LockFailed,
        acquireInDirectory(
            std.testing.allocator,
            &config,
            locks,
            true,
        ),
    );
}

fn lockNameAlloc(
    allocator: Allocator,
    identity: TargetIdentity,
) Error![:0]u8 {
    return std.fmt.allocPrintSentinel(
        allocator,
        "root-{x}-{x}-{x}.lock",
        .{ identity.dev_major, identity.dev_minor, identity.inode },
        0,
    ) catch error.OutOfMemory;
}

test "authorized target owner uses a private owner-scoped namespace" {
    if (privilegedRoot()) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root");
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = root_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &root_buffer,
    )];
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    const target = try fdTarget(root_fd);
    const directory_fd = try openDefaultTargetDirectory(target);
    defer _ = std.c.close(directory_fd);
    const directory_stat = try directoryStat(directory_fd);
    try std.testing.expectEqual(
        @as(u32, @intCast(std.c.geteuid())),
        directory_stat.uid,
    );
    try std.testing.expectEqual(
        @as(u16, 0o700),
        directory_stat.mode & 0o7777,
    );

    const name = try lockNameAlloc(std.testing.allocator, target.identity);
    defer std.testing.allocator.free(name);
    _ = std.c.unlinkat(directory_fd, name.ptr, 0);
    defer _ = std.c.unlinkat(directory_fd, name.ptr, 0);
    var config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer config.deinit();
    var guard = try acquire(std.testing.allocator, &config);
    defer guard.deinit();
    const lock_stat = lockFileStatAt(directory_fd, name.ptr) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(directory_stat.uid, lock_stat.uid);
    try std.testing.expectEqual(@as(u16, 0o600), lock_stat.mode & 0o7777);
}

test "root target lock blocks unprivileged opens and precreation" {
    if (!privilegedRoot()) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
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
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(base_z.ptr, 0o755));
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(root_z.ptr, 0o755));

    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    const identity = try fdIdentity(root_fd);
    const parent_fd = try openRootLockParent();
    defer _ = std.c.close(parent_fd);
    const name = try lockNameAlloc(std.testing.allocator, identity);
    defer std.testing.allocator.free(name);
    _ = std.c.unlinkat(parent_fd, name.ptr, 0);
    defer _ = std.c.unlinkat(parent_fd, name.ptr, 0);

    var config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer config.deinit();
    var guard = try acquire(std.testing.allocator, &config);
    defer guard.deinit();
    const stat = lockFileStatAt(parent_fd, name.ptr) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(systemRootUid(), stat.uid);
    try std.testing.expectEqual(@as(u16, 0o600), stat.mode & 0o7777);

    const child = fork();
    try std.testing.expect(child >= 0);
    if (child == 0) {
        _ = std.c.close(guard.lock_fd);
        if (setgid(65534) != 0 or setuid(65534) != 0) _exit(2);
        const existing = openExistingLock(parent_fd, name.ptr);
        if (existing >= 0) {
            _ = std.c.close(existing);
            _exit(3);
        }
        const attack_name = ".tdnf-unprivileged-precreate";
        const attack_fd = std.c.openat(parent_fd, attack_name, .{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        }, @as(std.c.mode_t, 0o600));
        if (attack_fd >= 0) {
            _ = std.c.close(attack_fd);
            _exit(4);
        }
        const attempted = tryAcquire(std.heap.c_allocator, &config);
        if (attempted) |unexpected_value| {
            var unexpected = unexpected_value;
            unexpected.deinit();
            _exit(5);
        } else |err| {
            _exit(if (err == error.InvalidTarget) 0 else 6);
        }
    }
    var status: c_int = 0;
    try std.testing.expectEqual(child, waitpid(child, &status, 0));
    try std.testing.expectEqual(@as(c_int, 0), status);
}

test "root and authorized target owner share one protected lock namespace" {
    if (!privilegedRoot()) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
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
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(base_z.ptr, 0o755));
    try std.testing.expectEqual(
        @as(c_int, 0),
        chown(root_z.ptr, 65534, 65534),
    );
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(root_z.ptr, 0o755));

    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    const target = try fdTarget(root_fd);
    const directory_fd = try openDefaultTargetDirectory(target);
    defer _ = std.c.close(directory_fd);
    const directory_stat = try directoryStat(directory_fd);
    try std.testing.expectEqual(@as(u32, 65534), directory_stat.uid);
    try std.testing.expectEqual(
        @as(u16, 0o700),
        directory_stat.mode & 0o7777,
    );
    const name = try lockNameAlloc(std.testing.allocator, target.identity);
    defer std.testing.allocator.free(name);
    _ = std.c.unlinkat(directory_fd, name.ptr, 0);
    defer _ = std.c.unlinkat(directory_fd, name.ptr, 0);

    var config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer config.deinit();
    var guard = try acquire(std.testing.allocator, &config);
    defer guard.deinit();
    const lock_stat = lockFileStatAt(directory_fd, name.ptr) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 65534), lock_stat.uid);
    try std.testing.expectEqual(@as(u16, 0o600), lock_stat.mode & 0o7777);

    const owner_child = fork();
    try std.testing.expect(owner_child >= 0);
    if (owner_child == 0) {
        _ = std.c.close(guard.lock_fd);
        if (setgid(65534) != 0 or setuid(65534) != 0) _exit(2);
        const attempted = tryAcquire(std.heap.c_allocator, &config);
        if (attempted) |unexpected_value| {
            var unexpected = unexpected_value;
            unexpected.deinit();
            _exit(3);
        } else |err| {
            _exit(if (err == error.WouldBlock) 0 else 4);
        }
    }
    var status: c_int = 0;
    try std.testing.expectEqual(owner_child, waitpid(owner_child, &status, 0));
    try std.testing.expectEqual(@as(c_int, 0), status);

    const unrelated_child = fork();
    try std.testing.expect(unrelated_child >= 0);
    if (unrelated_child == 0) {
        _ = std.c.close(guard.lock_fd);
        if (setgid(65533) != 0 or setuid(65533) != 0) _exit(2);
        const attempted = tryAcquire(std.heap.c_allocator, &config);
        if (attempted) |unexpected_value| {
            var unexpected = unexpected_value;
            unexpected.deinit();
            _exit(3);
        } else |err| {
            _exit(if (err == error.InvalidTarget) 0 else 4);
        }
    }
    status = 0;
    try std.testing.expectEqual(
        unrelated_child,
        waitpid(unrelated_child, &status, 0),
    );
    try std.testing.expectEqual(@as(c_int, 0), status);
}

test "exclusive locking never falls back to a read-only descriptor" {
    if (!privilegedRoot()) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "locks");
    try tmp.dir.createDirPath(std.testing.io, "root");
    var base_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const base = base_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &base_buffer,
    )];
    const locks = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "locks" },
    );
    defer std.testing.allocator.free(locks);
    const root = try std.fs.path.join(
        std.testing.allocator,
        &.{ base, "root" },
    );
    defer std.testing.allocator.free(root);
    const base_z = try std.testing.allocator.dupeZ(u8, base);
    defer std.testing.allocator.free(base_z);
    const locks_z = try std.testing.allocator.dupeZ(u8, locks);
    defer std.testing.allocator.free(locks_z);
    const root_z = try std.testing.allocator.dupeZ(u8, root);
    defer std.testing.allocator.free(root_z);
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(base_z.ptr, 0o755));
    try std.testing.expectEqual(
        @as(c_int, 0),
        chown(locks_z.ptr, 65534, 65534),
    );
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(locks_z.ptr, 0o700));
    try std.testing.expectEqual(
        @as(c_int, 0),
        chown(root_z.ptr, 65534, 65534),
    );
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(root_z.ptr, 0o755));

    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    const identity = try fdIdentity(root_fd);
    const name = try lockNameAlloc(std.testing.allocator, identity);
    defer std.testing.allocator.free(name);
    const directory_fd = std.c.open(locks_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    });
    try std.testing.expect(directory_fd >= 0);
    defer _ = std.c.close(directory_fd);
    const planted_fd = std.c.openat(directory_fd, name.ptr, .{
        .ACCMODE = .RDWR,
        .CREAT = true,
        .EXCL = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    }, @as(std.c.mode_t, 0o600));
    try std.testing.expect(planted_fd >= 0);
    try std.testing.expectEqual(
        @as(c_int, 0),
        fchown(planted_fd, 65534, 65534),
    );
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.fchmod(planted_fd, 0o400),
    );
    _ = std.c.close(planted_fd);
    defer _ = std.c.unlinkat(directory_fd, name.ptr, 0);

    var config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root,
    );
    defer config.deinit();
    const child = fork();
    try std.testing.expect(child >= 0);
    if (child == 0) {
        if (setgid(65534) != 0 or setuid(65534) != 0) _exit(2);
        const attempted = tryAcquireInDirectory(
            std.heap.c_allocator,
            &config,
            locks,
        );
        if (attempted) |unexpected_value| {
            var unexpected = unexpected_value;
            unexpected.deinit();
            _exit(3);
        } else |err| {
            _exit(if (err == error.LockFailed) 0 else 4);
        }
    }
    var status: c_int = 0;
    try std.testing.expectEqual(child, waitpid(child, &status, 0));
    try std.testing.expectEqual(@as(c_int, 0), status);
}
