//! Builds a repository model from the `.rpm` files under a directory.
//!
//! `--repofromdir=<id>,<path>` declares a repository that has no downloaded
//! metadata: the packages are simply the `.rpm` files living under `<path>`.
//! libsolv loads it by walking the directory and adding each file's header to
//! the repository (`readRpmsFromDir` in `solv/rpmzrepo.c`), which is the same
//! thing `cmdline_repository.loadModel` does for a list of paths. This module
//! is therefore only the directory walk: collect the paths, then hand them to
//! the existing loader.

const std = @import("std");

const cmdline_repository = @import("cmdline_repository.zig");
const model = @import("model.zig");

pub const LoadError = cmdline_repository.LoadError || error{
    DirectoryOpenFailed,
};

/// Order the collected `.rpm` paths are handed to the model loader in, which
/// becomes the repository's package order and therefore decides every tie the
/// solver breaks by package order -- including which rule a problem is
/// reported against and in what order.
pub const Order = enum {
    /// Sorted by path, so the package order does not depend on the
    /// filesystem's readdir order.
    sorted,
    /// Exactly the order the filesystem hands entries back in, which is what
    /// libsolv's `readRpmsFromDir` walked.
    read,
};

/// `errno` the failing directory open would have set, for the most recent
/// `error.DirectoryOpenFailed` produced on this thread. libsolv's
/// `readRpmsFromDir` reported `opendir`'s errno as
/// `ERROR_TDNF_SYSTEM_BASE + errno`, so a caller reproducing its error codes
/// needs the raw value rather than the Zig error name.
pub threadlocal var last_open_errno: c_int = 0;

/// The directory entry whose `stat` failed, when `DirectoryOpenFailed` came
/// from classifying an entry rather than from opening a directory. libsolv
/// named that entry in a `ReadRpms:` diagnostic before it bailed, so callers
/// that reproduce the diagnostic need the path; it is empty when the failure
/// was an `opendir`, which libsolv reported without a message.
threadlocal var last_stat_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
threadlocal var last_stat_path_len: usize = 0;

pub fn lastStatPath() ?[]const u8 {
    if (last_stat_path_len == 0) return null;
    return last_stat_path_buffer[0..last_stat_path_len];
}

/// The allocator owns all returned storage and must have arena lifetime.
///
/// The walk mirrors libsolv's: it descends into subdirectories, skips any
/// entry whose name starts with `.`, and takes every remaining file ending in
/// `.rpm`.
///
/// There is deliberately no default `order`. Package order decides every tie
/// the solver breaks by package order -- including which rule a problem is
/// reported against -- so a caller that walks a directory in one order while
/// another walks it in a second produces two different answers for the same
/// repository. That is exactly what issue #266 was: `--repofromdir` reached
/// this module sorted on the solve and query paths while the transaction-plan
/// path went through libsolv's readdir walk. Making the order an explicit
/// argument keeps the two from drifting apart silently again.
pub fn loadModelOrdered(
    allocator: std.mem.Allocator,
    directory: []const u8,
    order: Order,
) LoadError!model.RepositoryModel {
    last_stat_path_len = 0;

    var paths: std.array_list.Managed([:0]const u8) = .init(allocator);
    defer paths.deinit();

    var io_state: std.Io.Threaded = .init(allocator, .{});
    defer io_state.deinit();
    const io = io_state.io();

    try collectRpmPaths(allocator, io, directory, &paths);
    if (order == .sorted) {
        std.mem.sort([:0]const u8, paths.items, {}, lessThanPath);
    }

    return cmdline_repository.loadModel(allocator, paths.items);
}

/// Translate a directory-open failure back to the errno `opendir` would have
/// reported for it, which is the error code libsolv's walk surfaced.
fn openErrno(err: anytype) c_int {
    const value: std.posix.E = switch (err) {
        error.FileNotFound => .NOENT,
        error.NotDir => .NOTDIR,
        error.AccessDenied, error.PermissionDenied => .ACCES,
        error.SymLinkLoop => .LOOP,
        error.NameTooLong => .NAMETOOLONG,
        error.ProcessFdQuotaExceeded => .MFILE,
        error.SystemFdQuotaExceeded => .NFILE,
        error.SystemResources => .NOMEM,
        error.NoDevice, error.NetworkNotFound => .NXIO,
        else => .IO,
    };
    return @intFromEnum(value);
}

fn lessThanPath(_: void, lhs: [:0]const u8, rhs: [:0]const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

fn collectRpmPaths(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: []const u8,
    paths: *std.array_list.Managed([:0]const u8),
) LoadError!void {
    var dir = std.Io.Dir.cwd().openDir(
        io,
        directory,
        .{ .iterate = true },
    ) catch |err| {
        last_open_errno = openErrno(err);
        return error.DirectoryOpenFailed;
    };
    defer dir.close(io);

    var it = dir.iterateAssumeFirstIteration();
    while (it.next(io) catch return error.DirectoryOpenFailed) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        const path = try std.fs.path.joinZ(
            allocator,
            &.{ directory, entry.name },
        );
        if (try entryIsDirectory(dir, io, entry, path)) {
            try collectRpmPaths(allocator, io, path, paths);
        } else if (std.mem.endsWith(u8, entry.name, ".rpm")) {
            try paths.append(path);
        }
    }
}

/// libsolv classified every entry with `TDNFIsDir`, which stats through
/// symlinks, so a symlinked subdirectory was walked and a symlinked `.rpm` was
/// read. `readdir`'s type is enough for the common cases; anything that could
/// be a symlink is stat'ed the way libsolv did. A stat failure -- a dangling
/// symlink, say -- was fatal to libsolv's walk, so it is fatal here too rather
/// than quietly shrinking the universe.
fn entryIsDirectory(
    dir: std.Io.Dir,
    io: std.Io,
    entry: std.Io.Dir.Entry,
    path: []const u8,
) LoadError!bool {
    return switch (entry.kind) {
        .directory => true,
        .sym_link, .unknown => {
            const stat = dir.statFile(io, entry.name, .{}) catch |err| {
                last_open_errno = openErrno(err);
                rememberStatPath(path);
                return error.DirectoryOpenFailed;
            };
            return stat.kind == .directory;
        },
        else => false,
    };
}

fn rememberStatPath(path: []const u8) void {
    if (path.len > last_stat_path_buffer.len) {
        last_stat_path_len = 0;
        return;
    }
    @memcpy(last_stat_path_buffer[0..path.len], path);
    last_stat_path_len = path.len;
}

test "builds a repository from a directory of rpm files" {
    const testing = std.testing;
    const rpmpkg = @import("rpmpkg.zig");

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "nested");
    // A non-.rpm file and a dot-directory must both be ignored.
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "README",
        .data = "ignored",
    });
    try tmp.dir.createDirPath(testing.io, ".hidden");

    for ([_][2][]const u8{
        .{ "b-tool", "b-tool.rpm" },
        .{ "a-lib", "nested/a-lib.rpm" },
    }) |entry| {
        const bytes = try rpmpkg.makeMinimalRpmBytesForTest(
            arena,
            entry[0],
            "1.0",
            "1",
            "x86_64",
        );
        try tmp.dir.writeFile(testing.io, .{
            .sub_path = entry[1],
            .data = bytes,
        });
    }

    const root = try std.fmt.allocPrint(
        arena,
        ".zig-cache/tmp/{s}",
        .{&tmp.sub_path},
    );

    const repository = try loadModelOrdered(arena, root, .sorted);
    try testing.expectEqual(@as(usize, 2), repository.packages.len);
    try testing.expect(repository.has_filelists);
    // Ordered by full path -- "b-tool.rpm" before "nested/a-lib.rpm" -- and
    // not by whatever order the filesystem reported the entries in.
    try testing.expectEqualStrings("b-tool", repository.packages[0].nevra.name);
    try testing.expectEqualStrings("a-lib", repository.packages[1].nevra.name);
}

test "missing directory is reported" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    try testing.expectError(
        error.DirectoryOpenFailed,
        loadModelOrdered(arena_state.allocator(), "/nonexistent/repofromdir", .read),
    );
    try testing.expectEqual(
        @intFromEnum(std.posix.E.NOENT),
        last_open_errno,
    );
}

test "a path that is a file reports ENOTDIR" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "plain",
        .data = "not a directory",
    });
    const path = try std.fmt.allocPrint(
        arena,
        ".zig-cache/tmp/{s}/plain",
        .{&tmp.sub_path},
    );

    try testing.expectError(
        error.DirectoryOpenFailed,
        loadModelOrdered(arena, path, .read),
    );
    try testing.expectEqual(
        @intFromEnum(std.posix.E.NOTDIR),
        last_open_errno,
    );
}

test "a symlinked subdirectory is walked like libsolv's stat-based walk did" {
    const testing = std.testing;
    const rpmpkg = @import("rpmpkg.zig");

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(testing.io, "real");
    try tmp.dir.createDirPath(testing.io, "root");
    const bytes = try rpmpkg.makeMinimalRpmBytesForTest(
        arena,
        "linked-tool",
        "1.0",
        "1",
        "x86_64",
    );
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "real/linked-tool.rpm",
        .data = bytes,
    });

    const base = try std.fmt.allocPrint(
        arena,
        ".zig-cache/tmp/{s}",
        .{&tmp.sub_path},
    );
    try tmp.dir.symLink(
        testing.io,
        "../real",
        "root/linked",
        .{ .is_directory = true },
    );

    const root = try std.fs.path.join(arena, &.{ base, "root" });
    const repository = try loadModelOrdered(arena, root, .read);
    try testing.expectEqual(@as(usize, 1), repository.packages.len);
    try testing.expectEqualStrings(
        "linked-tool",
        repository.packages[0].nevra.name,
    );
}

test "read order keeps the packages the filesystem walk produced" {
    const testing = std.testing;
    const rpmpkg = @import("rpmpkg.zig");

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    for ([_][2][]const u8{
        .{ "b-tool", "b-tool.rpm" },
        .{ "a-lib", "a-lib.rpm" },
    }) |entry| {
        const bytes = try rpmpkg.makeMinimalRpmBytesForTest(
            arena,
            entry[0],
            "1.0",
            "1",
            "x86_64",
        );
        try tmp.dir.writeFile(testing.io, .{
            .sub_path = entry[1],
            .data = bytes,
        });
    }

    const root = try std.fmt.allocPrint(
        arena,
        ".zig-cache/tmp/{s}",
        .{&tmp.sub_path},
    );

    // The readdir order itself is the filesystem's business, so assert on the
    // set rather than the sequence: what this pins is that `.read` collects
    // exactly the same packages `.sorted` does.
    const read = try loadModelOrdered(arena, root, .read);
    const sorted = try loadModelOrdered(arena, root, .sorted);
    try testing.expectEqual(@as(usize, 2), read.packages.len);
    try testing.expectEqual(sorted.packages.len, read.packages.len);
    try testing.expectEqualStrings("a-lib", sorted.packages[0].nevra.name);
    try testing.expectEqualStrings("b-tool", sorted.packages[1].nevra.name);
    for (sorted.packages) |package| {
        var found = false;
        for (read.packages) |candidate| {
            if (std.mem.eql(u8, candidate.nevra.name, package.nevra.name)) {
                found = true;
            }
        }
        try testing.expect(found);
    }
}
