//! Builds a repository model from the `.rpm` files under a directory.
//!
//! `--repofromdir=<id>,<path>` declares a repository that has no downloaded
//! metadata: the packages are simply the `.rpm` files living under `<path>`.
//! libsolv loads it by walking the directory and adding each file's header to
//! the repository (`readRpmsFromDir` in `solv/tdnfrepo.c`), which is the same
//! thing `cmdline_repository.loadModel` does for a list of paths. This module
//! is therefore only the directory walk: collect the paths, then hand them to
//! the existing loader.

const std = @import("std");

const cmdline_repository = @import("cmdline_repository.zig");
const model = @import("model.zig");

pub const LoadError = cmdline_repository.LoadError || error{
    DirectoryOpenFailed,
};

/// The allocator owns all returned storage and must have arena lifetime.
///
/// The walk mirrors libsolv's: it descends into subdirectories, skips any
/// entry whose name starts with `.`, and takes every remaining file ending in
/// `.rpm`. Unlike libsolv it visits the paths in sorted order, so the model's
/// package order -- and therefore every tie broken by package order -- does
/// not depend on the filesystem's readdir order.
pub fn loadModel(
    allocator: std.mem.Allocator,
    directory: []const u8,
) LoadError!model.RepositoryModel {
    var paths: std.array_list.Managed([:0]const u8) = .init(allocator);
    defer paths.deinit();

    var io_state: std.Io.Threaded = .init(allocator, .{});
    defer io_state.deinit();
    const io = io_state.io();

    try collectRpmPaths(allocator, io, directory, &paths);
    std.mem.sort([:0]const u8, paths.items, {}, lessThanPath);

    return cmdline_repository.loadModel(allocator, paths.items);
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
    ) catch return error.DirectoryOpenFailed;
    defer dir.close(io);

    var it = dir.iterateAssumeFirstIteration();
    while (it.next(io) catch return error.DirectoryOpenFailed) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        const path = try std.fs.path.joinZ(
            allocator,
            &.{ directory, entry.name },
        );
        switch (entry.kind) {
            .directory => try collectRpmPaths(allocator, io, path, paths),
            else => if (std.mem.endsWith(u8, entry.name, ".rpm")) {
                try paths.append(path);
            },
        }
    }
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

    const repository = try loadModel(arena, root);
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
        loadModel(arena_state.allocator(), "/nonexistent/repofromdir"),
    );
}
