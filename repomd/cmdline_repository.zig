//! Builds a repository model from `.rpm` files named on the command line.
//!
//! libsolv models `tdnf install ./pkg.rpm` by adding the file's header to a
//! pseudo-repository (`@cmdline`) and issuing a normal install job against the
//! resulting solvable. The native solver has no such special case: it just
//! needs a repository whose packages come from those files rather than from a
//! downloaded `primary.xml`. `rpmpkg.buildFromRpmFile` already produces the
//! same `model.Package` shape from a `.rpm`, so the command-line repository is
//! an ordinary available repository built from a list of local paths.

const std = @import("std");

const model = @import("model.zig");
const repository_builder = @import("repository_builder.zig");
const rpm_pkgfile = @import("rpm_pkgfile");
const rpmpkg = @import("rpmpkg.zig");

pub const LoadError = error{
    OutOfMemory,
    RpmFileOpenFailed,
    InvalidRpmHeader,
};

/// The allocator owns all returned storage and must have arena lifetime.
/// `paths` may repeat a path; each entry yields one package, mirroring
/// libsolv, which adds one solvable per command-line argument.
pub fn loadModel(
    allocator: std.mem.Allocator,
    paths: []const [:0]const u8,
) LoadError!model.RepositoryModel {
    return loadModelWithFds(allocator, paths, null);
}

/// Build the command-line repository from paths and optional retained file
/// descriptors. A nonnegative descriptor is authoritative for that entry;
/// the corresponding path remains its logical package location.
pub fn loadModelWithFds(
    allocator: std.mem.Allocator,
    paths: []const [:0]const u8,
    fds: ?[]const c_int,
) LoadError!model.RepositoryModel {
    if (fds) |values| {
        if (values.len != paths.len) return error.RpmFileOpenFailed;
    }
    var builder = repository_builder.RepositoryBuilder.init(allocator);
    defer builder.deinit();

    for (paths, 0..) |path, index| {
        if (path.len == 0) return error.RpmFileOpenFailed;
        const fd = if (fds) |values| values[index] else -1;
        var rpm = if (fd >= 0)
            rpm_pkgfile.RpmFile.openFd(allocator, fd) catch
                return error.RpmFileOpenFailed
        else
            rpm_pkgfile.RpmFile.open(allocator, path) catch
                return error.RpmFileOpenFailed;
        defer rpm.close(allocator);
        var built = rpmpkg.buildFromRpmFile(
            allocator,
            &rpm,
            path,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidRpmHeader,
        };
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(rpm.bytes, &digest, .{});
        const digest_hex = std.fmt.bytesToHex(digest, .lower);
        const owned_digest = try allocator.dupe(u8, &digest_hex);
        built.package.pkg_id = owned_digest;
        built.package.checksum = .{
            .kind = try allocator.dupe(u8, "sha256"),
            .value = owned_digest,
            .is_pkgid = true,
            .header_only = false,
        };
        try builder.appendBuiltPackage(built);
    }

    var repository = try builder.finish();
    // Every package carries its full file list, so file provides resolve the
    // same way they do for a repository with a filelists index.
    repository.has_filelists = true;
    return repository;
}

test "builds a command-line repository from rpm files" {
    const testing = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var paths = std.array_list.Managed([:0]const u8).init(arena);
    for ([_][]const u8{ "alpha", "beta" }) |name| {
        const bytes = try rpmpkg.makeMinimalRpmBytesForTest(
            arena,
            name,
            "1.0",
            "1",
            "x86_64",
        );
        const file_name = try std.fmt.allocPrint(
            arena,
            "{s}.rpm",
            .{name},
        );
        try tmp.dir.writeFile(testing.io, .{
            .sub_path = file_name,
            .data = bytes,
        });
        try paths.append(try std.fmt.allocPrintSentinel(
            arena,
            ".zig-cache/tmp/{s}/{s}",
            .{ &tmp.sub_path, file_name },
            0,
        ));
    }

    const repository = try loadModel(arena, paths.items);
    try testing.expectEqual(@as(usize, 2), repository.packages.len);
    try testing.expectEqualStrings("alpha", repository.packages[0].nevra.name);
    try testing.expectEqualStrings("beta", repository.packages[1].nevra.name);
    try testing.expectEqualStrings(
        paths.items[1],
        repository.packages[1].location.href,
    );
    try testing.expectEqualStrings(
        "sha256",
        repository.packages[1].checksum.kind,
    );
    try testing.expectEqual(@as(usize, 64), repository.packages[1].checksum.value.len);
    try testing.expect(!repository.packages[1].checksum.header_only);
    try testing.expectEqual(
        @as(?u64, @intCast((try tmp.dir.statFile(
            testing.io,
            "beta.rpm",
            .{},
        )).size)),
        repository.packages[1].size.package,
    );
    try testing.expect(repository.has_filelists);
}
