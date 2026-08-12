//! Shared target lock for ordinary and replay transactions.

const std = @import("std");
const txn_config = @import("rpm_txn_config");

const Allocator = std.mem.Allocator;
const runtime_lock_directory = "/var/run";
const identity_domain = "tdnf.transaction-target/v1";
const deleted_suffix = " (deleted)";
const mode_type_mask: u16 = 0o170000;
const mode_directory: u16 = 0o040000;

extern fn tdnfLockAcquireSafe(path: ?[*:0]const u8) c_int;
extern fn tdnfLockTryAcquireSafe(path: ?[*:0]const u8) c_int;
extern fn tdnfLockFree(path: ?[*:0]const u8, fd: c_int) void;

pub const Error = error{
    InvalidTarget,
    LockFailed,
    WouldBlock,
    OutOfMemory,
};

pub const Guard = struct {
    allocator: Allocator,
    pinned_config: txn_config.TxnConfig,
    lock_path: [:0]u8,
    lock_fd: c_int,

    pub fn config(self: *Guard) *txn_config.TxnConfig {
        return &self.pinned_config;
    }

    pub fn deinit(self: *Guard) void {
        tdnfLockFree(self.lock_path.ptr, self.lock_fd);
        self.pinned_config.deinit();
        self.allocator.free(self.lock_path);
        self.lock_fd = -1;
    }
};

pub fn acquire(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
) Error!Guard {
    return acquireInDirectory(allocator, config, runtime_lock_directory, true);
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
    const root_path = try allocator.dupeZ(u8, config.installRoot());
    defer allocator.free(root_path);
    const root_fd = std.c.open(root_path.ptr, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
        .CLOEXEC = true,
    });
    if (root_fd < 0) return error.InvalidTarget;
    defer _ = std.c.close(root_fd);

    const root_identity = try fdIdentity(root_fd);

    const canonical_root = try resolvedRootAlloc(allocator, root_fd);
    defer allocator.free(canonical_root);
    const dbpath = try normalizedDbPathAlloc(allocator, config);
    defer allocator.free(dbpath);
    const lock_path = try targetLockPath(
        allocator,
        lock_directory,
        root_identity,
        dbpath,
    );
    errdefer allocator.free(lock_path);

    var pinned_config = config.cloneWithPinnedInstallRoot(
        allocator,
        canonical_root,
        root_fd,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidTarget,
    };
    errdefer pinned_config.deinit();

    const lock_fd = if (wait)
        tdnfLockAcquireSafe(lock_path.ptr)
    else
        tdnfLockTryAcquireSafe(lock_path.ptr);
    if (lock_fd == -2) return error.WouldBlock;
    if (lock_fd < 0) return error.LockFailed;
    return .{
        .allocator = allocator,
        .pinned_config = pinned_config,
        .lock_path = lock_path,
        .lock_fd = lock_fd,
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

fn normalizedDbPathAlloc(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
) Error![]u8 {
    const expanded = config.expandMacroAlloc(
        allocator,
        .dbpath,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidTarget,
    };
    defer allocator.free(expanded);

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.append(allocator, '/');
    var components = std.mem.splitScalar(
        u8,
        std.mem.trim(u8, expanded, "/"),
        '/',
    );
    var count: usize = 0;
    while (components.next()) |component| {
        if (component.len == 0 or std.mem.eql(u8, component, "."))
            continue;
        if (std.mem.eql(u8, component, ".."))
            return error.InvalidTarget;
        if (count != 0) try output.append(allocator, '/');
        try output.appendSlice(allocator, component);
        count += 1;
    }
    return output.toOwnedSlice(allocator);
}

fn targetLockPath(
    allocator: Allocator,
    lock_directory: []const u8,
    identity: TargetIdentity,
    dbpath: []const u8,
) Error![:0]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(identity_domain);
    hasher.update("\x00");
    var identity_buffer: [96]u8 = undefined;
    const identity_text = std.fmt.bufPrint(
        &identity_buffer,
        "{d}:{d}:{d}",
        .{ identity.dev_major, identity.dev_minor, identity.inode },
    ) catch return error.InvalidTarget;
    hasher.update(identity_text);
    hasher.update("\x00");
    hasher.update(dbpath);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    const filename = std.fmt.allocPrint(
        allocator,
        ".tdnf-transaction-lock-{s}",
        .{&hex},
    ) catch return error.OutOfMemory;
    defer allocator.free(filename);
    return std.fs.path.joinZ(
        allocator,
        &.{ lock_directory, filename },
    ) catch return error.OutOfMemory;
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

test "normal and replay aliases share one target lock" {
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
    var distinct_db = try tryAcquireInDirectory(
        std.testing.allocator,
        &distinct_db_config,
        lock_directory,
    );
    distinct_db.deinit();
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
