// Copyright (C) 2021-2023 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("api.zig");

const c = @cImport({
    @cInclude("errno.h");
    @cInclude("stdio.h");
    @cInclude("string.h");
});

extern fn flock(nFd: c_int, nOperation: c_int) c_int;
extern fn close(nFd: c_int) c_int;
extern fn geteuid() std.c.uid_t;
extern fn mkfifo(path: [*:0]const u8, mode: std.c.mode_t) c_int;
extern fn sleep(nSeconds: c_uint) c_uint;

const LOG_ERR: c_int = 1;
const LOCK_EX: c_int = 2;
const LOCK_NB: c_int = 4;
const LOCK_UN: c_int = 8;
const mode_type_mask: u16 = 0o170000;
const mode_regular: u16 = 0o100000;
const Stat = std.os.linux.Statx;

fn isNullOrEmptyString(pszValueOpt: ?[*:0]const u8) bool {
    return pszValueOpt == null or pszValueOpt.?[0] == 0;
}

fn rpmzCreateLockFile(pszLockPath: [*:0]const u8) c_int {
    const oflag: std.c.O = .{
        .ACCMODE = .RDWR,
        .CREAT = true,
        .CLOEXEC = true,
    };
    const oldmask = std.c.umask(@as(std.c.mode_t, 0o22));
    const nLockFd = std.c.open(pszLockPath, oflag, @as(std.c.mode_t, 0o644));
    _ = std.c.umask(oldmask);

    if (nLockFd < 0) {
        const nErrNo = c.__errno_location().*;
        common.log(LOG_ERR, "%s: open failed for %s (%s)\n", .{ "rpmzCreateLockFile", pszLockPath, c.strerror(nErrNo) });
        return -1;
    }

    return nLockFd;
}

fn rpmzCreateSafeLockFile(pszLockPath: [*:0]const u8) c_int {
    const oflag: std.c.O = .{
        .ACCMODE = .RDWR,
        .CREAT = true,
        .CLOEXEC = true,
        .NOFOLLOW = true,
        .NONBLOCK = true,
    };
    const nLockFd = std.c.open(pszLockPath, oflag, @as(std.c.mode_t, 0o600));
    if (nLockFd < 0) return -1;

    var fd_stat = std.mem.zeroes(Stat);
    if (std.c.statx(
        nLockFd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        .{
            .TYPE = true,
            .MODE = true,
            .NLINK = true,
            .UID = true,
            .SIZE = true,
        },
        &fd_stat,
    ) != 0 or
        (fd_stat.mode & mode_type_mask) != mode_regular or
        fd_stat.nlink != 1 or
        fd_stat.uid != geteuid() or
        fd_stat.size != 0 or
        (fd_stat.mode & 0o777) != 0o600)
    {
        _ = close(nLockFd);
        return -1;
    }
    return nLockFd;
}

fn lockPathMatchesFd(
    pszLockPath: [*:0]const u8,
    nLockFd: c_int,
) bool {
    var fd_stat = std.mem.zeroes(Stat);
    var path_stat = std.mem.zeroes(Stat);
    const mask: std.os.linux.STATX = .{ .TYPE = true, .INO = true };
    return std.c.statx(
        nLockFd,
        "",
        std.os.linux.AT.EMPTY_PATH,
        mask,
        &fd_stat,
    ) == 0 and
        std.c.statx(
            std.os.linux.AT.FDCWD,
            pszLockPath,
            std.os.linux.AT.SYMLINK_NOFOLLOW,
            mask,
            &path_stat,
        ) == 0 and
        (path_stat.mode & mode_type_mask) == mode_regular and
        fd_stat.dev_major == path_stat.dev_major and
        fd_stat.dev_minor == path_stat.dev_minor and
        fd_stat.ino == path_stat.ino;
}

export fn rpmzLockAcquire(pszLockPathOpt: ?[*:0]const u8) c_int {
    var nLockFd: c_int = -1;
    const pszLockPath = pszLockPathOpt orelse "";

    if (isNullOrEmptyString(pszLockPathOpt)) {
        common.log(LOG_ERR, "%s: lockPath is empty\n", .{"rpmzLockAcquire"});
        return -1;
    }

    nLockFd = rpmzCreateLockFile(pszLockPath);
    if (nLockFd < 0) {
        common.log(LOG_ERR, "%s: rpmzCreateLockFile failed\n", .{"rpmzLockAcquire"});
        return -1;
    }

    while (true) {
        if (flock(nLockFd, LOCK_EX | LOCK_NB) == 0) {
            break;
        }
        common.log(LOG_ERR, "WARNING: failed to acquire lock on: %s, retrying ...\n", .{pszLockPath});
        _ = sleep(1);
    }

    {
        var szPidBuf = [_]u8{0} ** 128;
        const nWritten = c.snprintf(
            &szPidBuf[0],
            szPidBuf.len,
            "%ld\n",
            @as(c_long, @intCast(std.c.getpid())),
        );
        if (nWritten > 0 and
            std.c.ftruncate(nLockFd, 0) == 0 and
            std.c.lseek(nLockFd, 0, c.SEEK_SET) == 0)
        {
            _ = std.c.write(
                nLockFd,
                szPidBuf[0..].ptr,
                @intCast(nWritten),
            );
        }
    }

    return nLockFd;
}

fn rpmzLockAcquireSafeMode(
    pszLockPathOpt: ?[*:0]const u8,
    wait: bool,
) c_int {
    const pszLockPath = pszLockPathOpt orelse "";
    if (isNullOrEmptyString(pszLockPathOpt)) return -1;

    const nLockFd = rpmzCreateSafeLockFile(pszLockPath);
    if (nLockFd < 0) return -1;

    if (wait) {
        while (true) {
            if (flock(nLockFd, LOCK_EX | LOCK_NB) == 0) break;
            _ = sleep(1);
        }
    } else if (flock(nLockFd, LOCK_EX | LOCK_NB) != 0) {
        const err = c.__errno_location().*;
        _ = close(nLockFd);
        if (err == c.EWOULDBLOCK or err == c.EAGAIN) return -2;
        return -1;
    }
    if (!lockPathMatchesFd(pszLockPath, nLockFd)) {
        _ = flock(nLockFd, LOCK_UN);
        _ = close(nLockFd);
        return -1;
    }
    return nLockFd;
}

/// Acquire a lock without following links or modifying the lock inode.
///
/// The caller must place the lock in a directory whose namespace is trusted;
/// the post-flock identity check then closes replacement races.
export fn rpmzLockAcquireSafe(pszLockPathOpt: ?[*:0]const u8) c_int {
    return rpmzLockAcquireSafeMode(pszLockPathOpt, true);
}

/// Non-blocking safe acquisition. `-2` means another process owns the lock.
export fn rpmzLockTryAcquireSafe(pszLockPathOpt: ?[*:0]const u8) c_int {
    return rpmzLockAcquireSafeMode(pszLockPathOpt, false);
}

export fn rpmzLockFree(pszLockPathOpt: ?[*:0]const u8, nLockFd: c_int) void {
    const pszLockPath = pszLockPathOpt orelse "";

    if (nLockFd >= 0) {
        if (flock(nLockFd, LOCK_UN) != 0) {
            common.log(LOG_ERR, "ERROR: failed to unlock: '%s'\n", .{pszLockPath});
        }
        _ = close(nLockFd);
    }
}

test "rpmzLockAcquire writes the pid and keeps a stable lock inode" {
    var szLockPath = [_]u8{0} ** 128;
    const pszLockPath = try std.fmt.bufPrintZ(
        &szLockPath,
        "zig-test-lock-{d}.lock",
        .{std.c.getpid()},
    );

    _ = c.remove(pszLockPath);

    const nLockFd = rpmzLockAcquire(pszLockPath);
    try std.testing.expect(nLockFd >= 0);
    defer _ = c.remove(pszLockPath);

    const pLockFile = c.fopen(pszLockPath, "rb");
    try std.testing.expect(pLockFile != null);
    defer _ = c.fclose(pLockFile);

    var szContents = [_]u8{0} ** 128;
    const nRead = c.fread(&szContents[0], 1, szContents.len - 1, pLockFile);
    const pszContents = szContents[0..nRead];

    var szExpectedPid = [_]u8{0} ** 32;
    const pszExpectedPid = try std.fmt.bufPrint(&szExpectedPid, "{d}\n", .{std.c.getpid()});
    try std.testing.expectEqualStrings(pszExpectedPid, pszContents);

    rpmzLockFree(pszLockPath, nLockFd);
    try std.testing.expect(std.c.access(pszLockPath, 0) == 0);
}

test "safe lock creates an empty stable lock inode" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrintZ(
        &path_buffer,
        ".zig-cache/tmp/{s}/lock",
        .{tmp.sub_path},
    );
    const fd = rpmzLockAcquireSafe(path);
    try std.testing.expect(fd >= 0);
    defer rpmzLockFree(path, fd);

    const contents = try tmp.dir.readFileAlloc(
        std.testing.io,
        "lock",
        std.testing.allocator,
        .limited(1),
    );
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqual(@as(usize, 0), contents.len);
}

test "safe lock rejects symlinks without altering their target" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "victim",
        .data = "untouched",
    });
    try tmp.dir.symLink(std.testing.io, "victim", "lock", .{});

    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrintZ(
        &path_buffer,
        ".zig-cache/tmp/{s}/lock",
        .{tmp.sub_path},
    );
    try std.testing.expect(rpmzLockAcquireSafe(path) < 0);

    const contents = try tmp.dir.readFileAlloc(
        std.testing.io,
        "victim",
        std.testing.allocator,
        .limited(32),
    );
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("untouched", contents);
}

test "safe lock rejects non-regular and foreign entries" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrintZ(
        &path_buffer,
        ".zig-cache/tmp/{s}/lock",
        .{tmp.sub_path},
    );
    try std.testing.expectEqual(
        @as(c_int, 0),
        mkfifo(path, @as(std.c.mode_t, 0o600)),
    );
    try std.testing.expect(rpmzLockAcquireSafe(path) < 0);

    try tmp.dir.deleteFile(std.testing.io, "lock");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "lock",
        .data = "foreign",
    });
    try std.testing.expect(rpmzLockAcquireSafe(path) < 0);
    const contents = try tmp.dir.readFileAlloc(
        std.testing.io,
        "lock",
        std.testing.allocator,
        .limited(32),
    );
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("foreign", contents);
}
