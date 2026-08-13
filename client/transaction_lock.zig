//! Shared target lock for ordinary and replay transactions.

const std = @import("std");
const txn_config = @import("rpm_txn_config");

const Allocator = std.mem.Allocator;
const mode_type_mask: u16 = 0o170000;
const mode_directory: u16 = 0o040000;
const mode_regular: u16 = 0o100000;
const lock_exclusive: c_int = 2;
const lock_nonblocking: c_int = 4;
const lock_unlock: c_int = 8;
const rename_exchange: c_uint = 2;
const at_removedir: c_int = 0x200;
// The shared object is promoted to root ownership before a privileged
// transaction uses this root-owned sticky namespace.
const default_lock_directory = "/dev/shm";

extern fn flock(fd: c_int, operation: c_int) callconv(.c) c_int;
extern fn fork() callconv(.c) c_int;
extern fn waitpid(pid: c_int, status: *c_int, options: c_int) callconv(.c) c_int;
extern fn setgid(gid: u32) callconv(.c) c_int;
extern fn setuid(uid: u32) callconv(.c) c_int;
extern fn chown(path: [*:0]const u8, uid: u32, gid: u32) callconv(.c) c_int;
extern fn renameat2(
    old_dir_fd: c_int,
    old_path: [*:0]const u8,
    new_dir_fd: c_int,
    new_path: [*:0]const u8,
    flags: c_uint,
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
    const identity = try fdIdentity(root_fd);
    const runtime_directory = if (lock_directory.len != 0)
        try allocator.dupe(u8, lock_directory)
    else
        try defaultLockDirectoryAlloc(allocator);
    defer allocator.free(runtime_directory);
    const lock_fd = try openProtectedLock(
        allocator,
        runtime_directory,
        identity,
        wait,
        lock_directory.len == 0,
        lock_directory.len == 0,
    );
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

fn defaultLockDirectoryAlloc(allocator: Allocator) Error![]u8 {
    return allocator.dupe(u8, default_lock_directory) catch
        error.OutOfMemory;
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

fn trustedDirectoryStat(
    fd: c_int,
    final: bool,
    shared_namespace: bool,
) Error!void {
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
    const euid: u32 = @intCast(std.c.geteuid());
    const root_uid = systemRootUid();
    const permissions = stat.mode & 0o7777;
    if (final and shared_namespace) {
        if (stat.uid != root_uid or permissions != 0o1777)
            return error.LockFailed;
        return;
    }
    if (stat.uid != root_uid and stat.uid != euid) return error.LockFailed;
    const writable_by_others = (permissions & 0o022) != 0;
    const root_sticky = stat.uid == root_uid and
        (permissions & 0o1000) != 0;
    if (writable_by_others and !root_sticky) return error.LockFailed;
    if (final and (stat.uid != euid or permissions != 0o700))
        return error.LockFailed;
}

fn openTrustedLockDirectory(
    path: []const u8,
    strict_ancestors: bool,
    shared_namespace: bool,
) Error!c_int {
    if (path.len < 2 or path[0] != '/' or path[path.len - 1] == '/')
        return error.LockFailed;
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
    var component_index: usize = 0;
    while (true) {
        if (!safeComponent(component)) return error.LockFailed;
        var name_buffer: [std.fs.max_name_bytes + 1]u8 = undefined;
        @memcpy(name_buffer[0..component.len], component);
        name_buffer[component.len] = 0;
        const name: [*:0]const u8 = @ptrCast(&name_buffer);
        const next_component = components.next();
        var created = false;
        var next = std.c.openat(current, name, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
        if (next < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
        {
            const mode: std.c.mode_t = if (shared_namespace)
                if (next_component == null) 0o1777 else 0o755
            else
                0o700;
            if (std.c.mkdirat(current, name, mode) != 0 and
                std.c._errno().* != @intFromEnum(std.posix.E.EXIST))
            {
                return error.LockFailed;
            }
            created = true;
            next = std.c.openat(current, name, .{
                .ACCMODE = .RDONLY,
                .DIRECTORY = true,
                .CLOEXEC = true,
                .NOFOLLOW = true,
            });
        }
        if (next < 0) return error.LockFailed;
        const desired_mode: ?std.c.mode_t = if (next_component == null)
            if (shared_namespace) 0o1777 else 0o700
        else if (shared_namespace and strict_ancestors and
            component_index != 0 and
            privilegedRoot())
            0o755
        else
            null;
        if (desired_mode) |mode| {
            if ((created or !shared_namespace or privilegedRoot()) and
                std.c.fchmod(next, mode) != 0)
            {
                _ = std.c.close(next);
                return error.LockFailed;
            }
        }
        if (strict_ancestors or next_component == null) {
            trustedDirectoryStat(
                next,
                next_component == null,
                shared_namespace,
            ) catch |err| {
                _ = std.c.close(next);
                return err;
            };
        }
        _ = std.c.close(current);
        current = next;
        component = next_component orelse break;
        component_index += 1;
    }
    return current;
}

const LockFileStat = struct {
    identity: TargetIdentity,
    uid: u32,
    mode: u16,
    nlink: u32,
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
    };
}

fn validLockFile(
    stat: LockFileStat,
    shared_namespace: bool,
) bool {
    const euid: u32 = @intCast(std.c.geteuid());
    const root_uid = systemRootUid();
    const privileged = privilegedRoot();
    return (stat.mode & mode_type_mask) == mode_regular and
        (stat.mode & 0o7777) ==
            (if (shared_namespace) @as(u16, 0o644) else @as(u16, 0o600)) and
        stat.nlink == 1 and
        (if (shared_namespace)
            stat.uid == root_uid or (!privileged and stat.uid == euid)
        else
            stat.uid == euid);
}

fn openExistingLock(
    directory_fd: c_int,
    name: [*:0]const u8,
) c_int {
    var fd = std.c.openat(directory_fd, name, .{
        .ACCMODE = .RDWR,
        .CLOEXEC = true,
        .NOFOLLOW = true,
        .NONBLOCK = true,
    });
    if (fd < 0 and
        std.c._errno().* == @intFromEnum(std.posix.E.ACCES))
    {
        fd = std.c.openat(directory_fd, name, .{
            .ACCMODE = .RDONLY,
            .CLOEXEC = true,
            .NOFOLLOW = true,
            .NONBLOCK = true,
        });
    }
    return fd;
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

fn randomPromotionName(buffer: *[96]u8) Error![*:0]const u8 {
    var random: [16]u8 = undefined;
    var offset: usize = 0;
    while (offset < random.len) {
        const count = std.c.getrandom(
            random[offset..].ptr,
            random.len - offset,
            0,
        );
        if (count < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.INTR))
        {
            continue;
        }
        if (count <= 0) return error.LockFailed;
        offset += @intCast(count);
    }
    const encoded = std.fmt.bytesToHex(random, .lower);
    return std.fmt.bufPrintZ(
        buffer,
        ".tdnf-lock-promote-{d}-{s}",
        .{ std.c.getpid(), &encoded },
    ) catch error.LockFailed;
}

fn promoteSharedLock(
    directory_fd: c_int,
    name: [*:0]const u8,
    existing_fd: c_int,
    wait: bool,
) Error!?c_int {
    const old_fd = existing_fd;
    var old_locked = false;
    defer {
        if (old_fd >= 0) {
            if (old_locked) _ = flock(old_fd, lock_unlock);
            _ = std.c.close(old_fd);
        }
    }
    var old_identity: ?TargetIdentity = null;
    if (old_fd >= 0) {
        const opened = lockFileStatFd(old_fd) orelse
            return error.LockFailed;
        if ((opened.mode & mode_type_mask) != mode_regular or
            opened.nlink != 1)
            return error.LockFailed;
        try flockForMode(old_fd, wait);
        old_locked = true;
        const named = lockFileStatAt(directory_fd, name) orelse
            return null;
        if (!opened.identity.eql(named.identity)) return null;
        old_identity = opened.identity;
    }

    var temp_name_buffer: [96]u8 = undefined;
    var replacement_fd: c_int = -1;
    var temp_name: [*:0]const u8 = undefined;
    var attempts: usize = 0;
    while (attempts < 64) : (attempts += 1) {
        temp_name = try randomPromotionName(&temp_name_buffer);
        replacement_fd = std.c.openat(directory_fd, temp_name, .{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        }, @as(std.c.mode_t, 0o644));
        if (replacement_fd >= 0) break;
        if (std.c._errno().* != @intFromEnum(std.posix.E.EXIST))
            return error.LockFailed;
    }
    if (replacement_fd < 0) return error.LockFailed;
    var replacement_locked = false;
    var keep_replacement = false;
    defer {
        if (!keep_replacement) {
            if (replacement_locked)
                _ = flock(replacement_fd, lock_unlock);
            _ = std.c.close(replacement_fd);
            _ = std.c.unlinkat(directory_fd, temp_name, 0);
        }
    }
    if (std.c.fchmod(replacement_fd, 0o644) != 0)
        return error.LockFailed;
    const replacement = lockFileStatFd(replacement_fd) orelse
        return error.LockFailed;
    if (!validLockFile(replacement, true) or
        replacement.uid != systemRootUid())
        return error.LockFailed;
    try flockForMode(replacement_fd, wait);
    replacement_locked = true;

    const identity = old_identity orelse return error.LockFailed;
    const current = lockFileStatAt(directory_fd, name) orelse return null;
    if (!identity.eql(current.identity)) return null;
    if (renameat2(
        directory_fd,
        temp_name,
        directory_fd,
        name,
        rename_exchange,
    ) != 0) {
        if (std.c._errno().* == @intFromEnum(std.posix.E.NOENT))
            return null;
        return error.LockFailed;
    }
    const named = lockFileStatAt(directory_fd, name) orelse
        return error.LockFailed;
    if (!replacement.identity.eql(named.identity) or
        !validLockFile(named, true) or named.uid != systemRootUid())
    {
        return error.LockFailed;
    }

    if (lockFileStatAt(directory_fd, temp_name)) |displaced| {
        if (!identity.eql(displaced.identity)) {
            if (renameat2(
                directory_fd,
                temp_name,
                directory_fd,
                name,
                rename_exchange,
            ) != 0) return error.LockFailed;
            return null;
        }
        _ = std.c.unlinkat(
            directory_fd,
            temp_name,
            if ((displaced.mode & mode_type_mask) == mode_directory)
                at_removedir
            else
                0,
        );
    } else return error.LockFailed;
    keep_replacement = true;
    return replacement_fd;
}

fn openProtectedLock(
    allocator: Allocator,
    directory_path: []const u8,
    root: TargetIdentity,
    wait: bool,
    strict_ancestors: bool,
    shared_namespace: bool,
) Error!c_int {
    const directory_fd = try openTrustedLockDirectory(
        directory_path,
        strict_ancestors,
        shared_namespace,
    );
    defer _ = std.c.close(directory_fd);
    const name = if (shared_namespace)
        std.fmt.allocPrintSentinel(
            allocator,
            "tdnf-root-{x}-{x}-{x}.lock",
            .{ root.dev_major, root.dev_minor, root.inode },
            0,
        ) catch return error.OutOfMemory
    else
        std.fmt.allocPrintSentinel(
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
        }, @as(std.c.mode_t, if (shared_namespace) 0o644 else 0o600));
        const created = fd >= 0;
        if (fd < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.EXIST))
        {
            fd = openExistingLock(directory_fd, name.ptr);
        }
        if (fd < 0) {
            if (shared_namespace and privilegedRoot()) {
                return error.LockFailed;
            }
            return error.LockFailed;
        }
        if (created and std.c.fchmod(
            fd,
            if (shared_namespace) 0o644 else 0o600,
        ) != 0) {
            _ = std.c.close(fd);
            return error.LockFailed;
        }

        var opened = lockFileStatFd(fd) orelse {
            _ = std.c.close(fd);
            return error.LockFailed;
        };
        var named = lockFileStatAt(directory_fd, name.ptr) orelse {
            _ = std.c.close(fd);
            continue;
        };
        if (!opened.identity.eql(named.identity)) {
            _ = std.c.close(fd);
            continue;
        }
        const expected_mode: u16 = if (shared_namespace) 0o644 else 0o600;
        if ((opened.mode & mode_type_mask) == mode_regular and
            opened.nlink == 1 and
            opened.uid == @as(u32, @intCast(std.c.geteuid())) and
            (opened.mode & 0o7777) != expected_mode)
        {
            if (std.c.fchmod(fd, expected_mode) != 0) {
                _ = std.c.close(fd);
                return error.LockFailed;
            }
            opened = lockFileStatFd(fd) orelse {
                _ = std.c.close(fd);
                return error.LockFailed;
            };
            named = lockFileStatAt(directory_fd, name.ptr) orelse {
                _ = std.c.close(fd);
                continue;
            };
            if (!opened.identity.eql(named.identity)) {
                _ = std.c.close(fd);
                continue;
            }
        }
        if (!validLockFile(opened, shared_namespace)) {
            if (shared_namespace and privilegedRoot()) {
                if (try promoteSharedLock(
                    directory_fd,
                    name.ptr,
                    fd,
                    wait,
                )) |promoted| return promoted;
                continue;
            }
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
            !validLockFile(after, shared_namespace))
        {
            _ = flock(fd, lock_unlock);
            _ = std.c.close(fd);
            continue;
        }
        return fd;
    }
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

fn fdIdentity(fd: c_int) Error!TargetIdentity {
    var stat = std.mem.zeroes(std.os.linux.Statx);
    if (std.c.statx(
        fd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        .{ .TYPE = true, .INO = true },
        &stat,
    ) != 0 or (stat.mode & mode_type_mask) != mode_directory) {
        return error.InvalidTarget;
    }
    return .{
        .dev_major = stat.dev_major,
        .dev_minor = stat.dev_minor,
        .inode = stat.ino,
    };
}

test "default lock namespace is environment independent" {
    const first = try defaultLockDirectoryAlloc(std.testing.allocator);
    defer std.testing.allocator.free(first);
    const second = try defaultLockDirectoryAlloc(std.testing.allocator);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings(default_lock_directory, first);
    try std.testing.expectEqualStrings(first, second);
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
        false,
    ));
    try std.testing.expectError(
        error.WouldBlock,
        tryAcquireInDirectory(
            std.testing.allocator,
            &replay_config,
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

test "shared namespace lock is visible to the target owner across uid" {
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
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(locks_z.ptr, 0o1777));
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

    const lock_fd = try openProtectedLock(
        std.testing.allocator,
        locks,
        identity,
        true,
        false,
        true,
    );
    defer {
        _ = flock(lock_fd, lock_unlock);
        _ = std.c.close(lock_fd);
    }

    const child = fork();
    try std.testing.expect(child >= 0);
    if (child == 0) {
        _ = std.c.close(lock_fd);
        if (setgid(65534) != 0 or setuid(65534) != 0) _exit(2);
        const result = openProtectedLock(
            std.heap.c_allocator,
            locks,
            identity,
            false,
            false,
            true,
        );
        if (result) |fd| {
            _ = std.c.close(fd);
            _exit(3);
        } else |err| {
            _exit(if (err == error.WouldBlock) 0 else 4);
        }
    }
    var status: c_int = 0;
    try std.testing.expectEqual(child, waitpid(child, &status, 0));
    try std.testing.expectEqual(@as(c_int, 0), status);
}

test "privileged shared lock safely replaces a held unprivileged precreation" {
    if (!privilegedRoot()) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root");
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root_path = root_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &root_buffer,
    )];
    const root_z = try std.testing.allocator.dupeZ(u8, root_path);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    const identity = try fdIdentity(root_fd);

    const directory_fd = try openTrustedLockDirectory(
        default_lock_directory,
        true,
        true,
    );
    defer _ = std.c.close(directory_fd);
    const name = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "tdnf-root-{x}-{x}-{x}.lock",
        .{ identity.dev_major, identity.dev_minor, identity.inode },
        0,
    );
    defer std.testing.allocator.free(name);
    _ = std.c.unlinkat(directory_fd, name.ptr, 0);
    defer _ = std.c.unlinkat(directory_fd, name.ptr, 0);

    var ready = [_]c_int{ -1, -1 };
    var release = [_]c_int{ -1, -1 };
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&ready));
    defer {
        _ = std.c.close(ready[0]);
        _ = std.c.close(ready[1]);
    }
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&release));
    defer {
        _ = std.c.close(release[0]);
        _ = std.c.close(release[1]);
    }

    const child = fork();
    try std.testing.expect(child >= 0);
    if (child == 0) {
        _ = std.c.close(ready[0]);
        _ = std.c.close(release[1]);
        if (setgid(65534) != 0 or setuid(65534) != 0) _exit(2);
        const fd = std.c.openat(directory_fd, name.ptr, .{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        }, @as(std.c.mode_t, 0o644));
        if (fd < 0 or std.c.fchmod(fd, 0o644) != 0 or
            flock(fd, lock_exclusive) != 0)
        {
            _exit(3);
        }
        var byte: [1]u8 = .{1};
        if (std.c.write(ready[1], &byte, 1) != 1) _exit(4);
        if (std.c.read(release[0], &byte, 1) != 1) _exit(5);
        _ = flock(fd, lock_unlock);
        _ = std.c.close(fd);
        _exit(0);
    }
    _ = std.c.close(ready[1]);
    ready[1] = -1;
    _ = std.c.close(release[0]);
    release[0] = -1;
    var byte: [1]u8 = undefined;
    try std.testing.expectEqual(
        @as(isize, 1),
        std.c.read(ready[0], &byte, 1),
    );
    try std.testing.expectError(
        error.WouldBlock,
        openProtectedLock(
            std.testing.allocator,
            default_lock_directory,
            identity,
            false,
            true,
            true,
        ),
    );
    byte[0] = 1;
    try std.testing.expectEqual(
        @as(isize, 1),
        std.c.write(release[1], &byte, 1),
    );
    var status: c_int = 0;
    try std.testing.expectEqual(child, waitpid(child, &status, 0));
    try std.testing.expectEqual(@as(c_int, 0), status);

    const lock_fd = try openProtectedLock(
        std.testing.allocator,
        default_lock_directory,
        identity,
        true,
        true,
        true,
    );
    defer {
        _ = flock(lock_fd, lock_unlock);
        _ = std.c.close(lock_fd);
    }
    const stat = lockFileStatAt(directory_fd, name.ptr) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 0), stat.uid);
    try std.testing.expectEqual(@as(u16, 0o644), stat.mode & 0o7777);
}

test "unprivileged process cannot unlink or replace a privileged shared lock" {
    if (!privilegedRoot()) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "root");
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root_path = root_buffer[0..try tmp.dir.realPath(
        std.testing.io,
        &root_buffer,
    )];
    const root_z = try std.testing.allocator.dupeZ(u8, root_path);
    defer std.testing.allocator.free(root_z);
    const root_fd = std.c.open(root_z.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    try std.testing.expect(root_fd >= 0);
    defer _ = std.c.close(root_fd);
    const identity = try fdIdentity(root_fd);
    const directory_fd = try openTrustedLockDirectory(
        default_lock_directory,
        true,
        true,
    );
    defer _ = std.c.close(directory_fd);
    const name = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "tdnf-root-{x}-{x}-{x}.lock",
        .{ identity.dev_major, identity.dev_minor, identity.inode },
        0,
    );
    defer std.testing.allocator.free(name);
    _ = std.c.unlinkat(directory_fd, name.ptr, 0);
    defer _ = std.c.unlinkat(directory_fd, name.ptr, 0);

    const lock_fd = try openProtectedLock(
        std.testing.allocator,
        default_lock_directory,
        identity,
        true,
        true,
        true,
    );
    defer {
        _ = flock(lock_fd, lock_unlock);
        _ = std.c.close(lock_fd);
    }
    const child = fork();
    try std.testing.expect(child >= 0);
    if (child == 0) {
        _ = std.c.close(lock_fd);
        if (setgid(65534) != 0 or setuid(65534) != 0) _exit(2);
        if (std.c.unlinkat(directory_fd, name.ptr, 0) == 0) _exit(3);
        const replacement = ".tdnf-lock-attacker";
        _ = std.c.unlinkat(directory_fd, replacement, 0);
        const replacement_fd = std.c.openat(directory_fd, replacement, .{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        }, @as(std.c.mode_t, 0o644));
        if (replacement_fd < 0) _exit(4);
        _ = std.c.close(replacement_fd);
        if (std.c.renameat(
            directory_fd,
            replacement,
            directory_fd,
            name.ptr,
        ) == 0) {
            _exit(5);
        }
        _ = std.c.unlinkat(directory_fd, replacement, 0);
        const contender = openExistingLock(directory_fd, name.ptr);
        if (contender < 0) _exit(6);
        const blocked = flock(
            contender,
            lock_exclusive | lock_nonblocking,
        ) != 0;
        _ = std.c.close(contender);
        _exit(if (blocked) 0 else 7);
    }
    var status: c_int = 0;
    try std.testing.expectEqual(child, waitpid(child, &status, 0));
    try std.testing.expectEqual(@as(c_int, 0), status);
    const fd_stat = lockFileStatFd(lock_fd) orelse
        return error.TestUnexpectedResult;
    const path_stat = lockFileStatAt(directory_fd, name.ptr) orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(fd_stat.identity.eql(path_stat.identity));
    try std.testing.expectEqual(@as(u32, 0), path_stat.uid);
}
