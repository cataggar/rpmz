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

extern fn flock(fd: c_int, operation: c_int) callconv(.c) c_int;
extern fn getenv(name: [*:0]const u8) callconv(.c) ?[*:0]u8;

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
    if (std.c.geteuid() == 0) {
        return allocator.dupe(u8, "/run/tdnf/locks") catch
            error.OutOfMemory;
    }
    if (getenv("XDG_RUNTIME_DIR")) |raw| {
        const runtime = std.mem.span(raw);
        if (runtime.len != 0 and runtime[0] == '/') {
            return std.fs.path.join(
                allocator,
                &.{ runtime, "tdnf", "locks" },
            ) catch error.OutOfMemory;
        }
    }
    const home_raw = getenv("HOME") orelse return error.LockFailed;
    const home = std.mem.span(home_raw);
    if (home.len == 0 or home[0] != '/') return error.LockFailed;
    return std.fs.path.join(
        allocator,
        &.{ home, ".tdnf", "runtime-locks" },
    ) catch error.OutOfMemory;
}

fn safeComponent(component: []const u8) bool {
    return component.len != 0 and
        component.len <= std.fs.max_name_bytes and
        !std.mem.eql(u8, component, ".") and
        !std.mem.eql(u8, component, "..") and
        std.mem.indexOfScalar(u8, component, 0) == null;
}

fn trustedDirectoryStat(fd: c_int, final: bool) Error!void {
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
    if (stat.uid != 0 and stat.uid != euid) return error.LockFailed;
    const permissions = stat.mode & 0o7777;
    const writable_by_others = (permissions & 0o022) != 0;
    const root_sticky = stat.uid == 0 and (permissions & 0o1000) != 0;
    if (writable_by_others and !root_sticky) return error.LockFailed;
    if (final and (stat.uid != euid or writable_by_others))
        return error.LockFailed;
}

fn openTrustedLockDirectory(
    path: []const u8,
    strict_ancestors: bool,
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
        if (next_component == null and std.c.fchmod(next, 0o700) != 0) {
            _ = std.c.close(next);
            return error.LockFailed;
        }
        if (strict_ancestors or next_component == null) {
            trustedDirectoryStat(next, next_component == null) catch |err| {
                _ = std.c.close(next);
                return err;
            };
        }
        _ = std.c.close(current);
        current = next;
        component = next_component orelse break;
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

fn validLockFile(stat: LockFileStat) bool {
    return (stat.mode & mode_type_mask) == mode_regular and
        (stat.mode & 0o7777) == 0o600 and
        stat.nlink == 1 and
        stat.uid == @as(u32, @intCast(std.c.geteuid()));
}

fn openProtectedLock(
    allocator: Allocator,
    directory_path: []const u8,
    root: TargetIdentity,
    wait: bool,
    strict_ancestors: bool,
) Error!c_int {
    const directory_fd = try openTrustedLockDirectory(
        directory_path,
        strict_ancestors,
    );
    defer _ = std.c.close(directory_fd);
    const name = std.fmt.allocPrintSentinel(
        allocator,
        "root-{x}-{x}-{x}.lock",
        .{ root.dev_major, root.dev_minor, root.inode },
        0,
    ) catch return error.OutOfMemory;
    defer allocator.free(name);

    var fd = std.c.openat(directory_fd, name.ptr, .{
        .ACCMODE = .RDWR,
        .CREAT = true,
        .EXCL = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
    }, @as(std.c.mode_t, 0o600));
    const created = fd >= 0;
    if (fd < 0 and std.c._errno().* == @intFromEnum(std.posix.E.EXIST)) {
        fd = std.c.openat(directory_fd, name.ptr, .{
            .ACCMODE = .RDWR,
            .CLOEXEC = true,
            .NOFOLLOW = true,
        });
    }
    if (fd < 0) return error.LockFailed;
    errdefer _ = std.c.close(fd);
    if (created and std.c.fchmod(fd, 0o600) != 0)
        return error.LockFailed;

    const opened = lockFileStatFd(fd) orelse return error.LockFailed;
    const named = lockFileStatAt(directory_fd, name.ptr) orelse
        return error.LockFailed;
    if (!validLockFile(opened) or
        !opened.identity.eql(named.identity))
    {
        return error.LockFailed;
    }

    const operation = lock_exclusive |
        (if (wait) @as(c_int, 0) else lock_nonblocking);
    if (flock(fd, operation) != 0) {
        if (!wait and
            (std.c._errno().* == @intFromEnum(std.posix.E.AGAIN) or
                std.c._errno().* == @intFromEnum(std.posix.E.ACCES)))
        {
            return error.WouldBlock;
        }
        return error.LockFailed;
    }
    errdefer _ = flock(fd, lock_unlock);
    const after = lockFileStatAt(directory_fd, name.ptr) orelse
        return error.LockFailed;
    if (!opened.identity.eql(after.identity) or !validLockFile(after))
        return error.LockFailed;
    return fd;
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
    try std.testing.expect(validLockFile(lock_stat));
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
