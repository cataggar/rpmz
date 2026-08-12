//! Shared target lock for ordinary and replay transactions.

const std = @import("std");
const txn_config = @import("rpm_txn_config");

const Allocator = std.mem.Allocator;
const deleted_suffix = " (deleted)";
const mode_type_mask: u16 = 0o170000;
const mode_directory: u16 = 0o040000;
const lock_exclusive: c_int = 2;
const lock_nonblocking: c_int = 4;
const lock_unlock: c_int = 8;

extern fn flock(fd: c_int, operation: c_int) callconv(.c) c_int;

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
    return acquireInDirectory(allocator, config, "", true);
}

pub fn tryAcquireInDirectory(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
    lock_directory: []const u8,
) Error!Guard {
    return acquireInDirectory(allocator, config, lock_directory, false);
}

pub fn acquireInDirectory(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
    lock_directory: []const u8,
    wait: bool,
) Error!Guard {
    _ = lock_directory;
    const root_path = try allocator.dupeZ(u8, config.installRoot());
    defer allocator.free(root_path);
    const root_fd = std.c.open(root_path.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    if (root_fd < 0) return error.InvalidTarget;
    var owns_root_fd = true;
    defer {
        if (owns_root_fd) _ = std.c.close(root_fd);
    }
    _ = try fdIdentity(root_fd);

    const canonical_root = try resolvedRootAlloc(allocator, root_fd);
    defer allocator.free(canonical_root);
    const operation = lock_exclusive |
        (if (wait) @as(c_int, 0) else lock_nonblocking);
    if (flock(root_fd, operation) != 0) {
        if (!wait and
            std.c._errno().* == @intFromEnum(std.posix.E.AGAIN))
        {
            return error.WouldBlock;
        }
        return error.LockFailed;
    }
    errdefer _ = flock(root_fd, lock_unlock);

    var pinned_config = config.cloneWithPinnedInstallRoot(
        allocator,
        canonical_root,
        root_fd,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidTarget,
    };
    errdefer pinned_config.deinit();
    pinned_config.markTargetLockHeld();
    owns_root_fd = false;
    return .{
        .pinned_config = pinned_config,
        .lock_fd = root_fd,
    };
}

fn resolvedRootAlloc(
    allocator: Allocator,
    root_fd: c_int,
) Error![]u8 {
    var proc_buffer: [64]u8 = undefined;
    const proc_path = std.fmt.bufPrintZ(
        &proc_buffer,
        "/proc/self/fd/{d}",
        .{root_fd},
    ) catch return error.InvalidTarget;
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const length = std.c.readlink(
        proc_path.ptr,
        &path_buffer,
        path_buffer.len,
    );
    if (length <= 0 or length >= path_buffer.len)
        return error.InvalidTarget;
    const resolved = path_buffer[0..@intCast(length)];
    if (std.mem.endsWith(u8, resolved, deleted_suffix))
        return error.InvalidTarget;
    return allocator.dupe(u8, resolved);
}

const TargetIdentity = struct {
    dev_major: u32,
    dev_minor: u32,
    inode: u64,
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
    var dot_config = try txn_config.TxnConfig.init(
        std.testing.allocator,
        root_dot,
    );
    defer dot_config.deinit();
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
    try std.testing.expectError(
        error.WouldBlock,
        tryAcquireInDirectory(
            std.testing.allocator,
            &dot_config,
            lock_directory,
        ),
    );
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
