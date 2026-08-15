//! Publishing a bundle so that a reader never sees a partial one.
//!
//! An exporter that writes directly into its destination has three failure
//! modes that all look like success to a later reader: a crash mid-write
//! leaves a truncated tree, a failure after some files leaves a
//! bundle-shaped directory whose manifest is missing entries, and a retry
//! silently merges into whatever was there before.
//!
//! So nothing is ever written at the destination. Everything is built in a
//! sibling staging directory, made durable bottom-up, and then moved into
//! place with a **non-replacing** rename. The destination therefore only ever
//! comes into existence complete, and an export onto an existing path is
//! refused by the kernel rather than by a check that could race.
//!
//! The staging directory is a sibling rather than a temp directory so that the
//! rename stays within one filesystem -- a cross-device rename is not atomic
//! and would degrade into a copy.

const std = @import("std");

pub const CreateError = error{
    /// The destination already exists. Refused up front for a clear message;
    /// the authoritative check is the non-replacing rename in `publish`.
    DestinationExists,
    /// The destination path names no parent directory, or names one that
    /// cannot be opened or written to.
    DestinationUnusable,
    /// The staging directory could not be created.
    StagingUnavailable,
    OutOfMemory,
};

pub const PublishError = error{
    /// Another process created the destination between staging and publish.
    DestinationExists,
    /// The staged tree could not be made durable, so publishing it would
    /// promise more than the filesystem does.
    SyncFailed,
    /// The rename into place failed for any other reason.
    PublishFailed,
    /// The platform cannot perform a non-replacing rename. Publishing without
    /// one could silently overwrite an existing bundle, so it is refused.
    AtomicPublishUnsupported,
    OutOfMemory,
};

/// A staging directory that becomes the destination, or becomes nothing.
///
/// `deinit` removes the staging tree unless `publish` succeeded, so every
/// early return on the export path cleans up without the caller remembering
/// to. There is no way to leave a half-written destination behind, and a
/// leftover staging directory is named so that it can never be mistaken for a
/// bundle.
pub const Staging = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    staging_name: []u8,
    destination_name: []u8,
    dir: std.Io.Dir,
    published: bool,

    /// Prefix for staging directories. The leading dot keeps it out of casual
    /// listings, and the name is deliberately not a plausible bundle name.
    pub const staging_prefix = ".rpmz-bundle-staging-";

    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        destination: []const u8,
    ) CreateError!Staging {
        const parent_path = std.fs.path.dirname(destination) orelse ".";
        const base = std.fs.path.basename(destination);
        if (base.len == 0 or std.mem.eql(u8, base, ".") or std.mem.eql(u8, base, "..")) {
            return error.DestinationUnusable;
        }

        // `iterate` is required, not cosmetic: without it Zig opens the
        // directory with O_PATH, and fsync on an O_PATH descriptor fails with
        // EBADF -- so the parent could never be made durable after the
        // rename.
        var parent = std.Io.Dir.cwd().openDir(io, parent_path, .{ .iterate = true }) catch
            return error.DestinationUnusable;
        errdefer parent.close(io);

        // An existing destination -- including an empty directory -- is a
        // refusal, not something to merge into.
        if (parent.access(io, base, .{})) |_| {
            return error.DestinationExists;
        } else |_| {}

        var suffix: [16]u8 = undefined;
        io.random(&suffix);
        const staging_name = std.fmt.allocPrint(
            allocator,
            staging_prefix ++ "{x}",
            .{&suffix},
        ) catch return error.OutOfMemory;
        errdefer allocator.free(staging_name);

        const destination_name = allocator.dupe(u8, base) catch return error.OutOfMemory;
        errdefer allocator.free(destination_name);

        parent.createDir(io, staging_name, .default_dir) catch return error.StagingUnavailable;
        errdefer parent.deleteTree(io, staging_name) catch {};

        const dir = parent.openDir(io, staging_name, .{
            .iterate = true,
            .follow_symlinks = false,
        }) catch return error.StagingUnavailable;

        return .{
            .allocator = allocator,
            .io = io,
            .parent = parent,
            .staging_name = staging_name,
            .destination_name = destination_name,
            .dir = dir,
            .published = false,
        };
    }

    /// Make the staged tree durable and move it into place.
    ///
    /// Files are synced before the directories that name them, and the parent
    /// is synced after the rename, so a reader that sees the destination sees
    /// every byte of it even across a power loss.
    pub fn publish(self: *Staging) PublishError!void {
        try self.syncTree();
        self.parent.renamePreserve(
            self.staging_name,
            self.parent,
            self.destination_name,
            self.io,
        ) catch |err| switch (err) {
            error.PathAlreadyExists => return error.DestinationExists,
            error.OperationUnsupported => return error.AtomicPublishUnsupported,
            else => return error.PublishFailed,
        };
        self.published = true;
        syncDir(self.io, self.parent) catch return error.SyncFailed;
    }

    pub fn realPathAlloc(
        self: *const Staging,
        allocator: std.mem.Allocator,
    ) anyerror![:0]u8 {
        return self.parent.realPathFileAlloc(
            self.io,
            self.staging_name,
            allocator,
        );
    }

    /// Remove the staged tree. Safe to call more than once.
    pub fn abandon(self: *Staging) void {
        if (self.published) return;
        self.parent.deleteTree(self.io, self.staging_name) catch {};
        self.published = true;
    }

    pub fn deinit(self: *Staging) void {
        self.dir.close(self.io);
        self.abandon();
        self.parent.close(self.io);
        self.allocator.free(self.staging_name);
        self.allocator.free(self.destination_name);
        self.* = undefined;
    }

    fn syncTree(self: *Staging) PublishError!void {
        var walker = self.dir.walk(self.allocator) catch return error.OutOfMemory;
        defer walker.deinit();

        // Collect directory paths as we go so they can be synced after the
        // files they contain. Depth ordering is what makes the tree durable
        // rather than merely written.
        var directories: std.ArrayList([]u8) = .empty;
        defer {
            for (directories.items) |item| self.allocator.free(item);
            directories.deinit(self.allocator);
        }

        while (walker.next(self.io) catch return error.SyncFailed) |entry| {
            switch (entry.kind) {
                .file => {
                    var file = entry.dir.openFile(self.io, entry.basename, .{}) catch
                        return error.SyncFailed;
                    defer file.close(self.io);
                    file.sync(self.io) catch return error.SyncFailed;
                },
                .directory => {
                    const owned = self.allocator.dupe(u8, entry.path) catch
                        return error.OutOfMemory;
                    directories.append(self.allocator, owned) catch {
                        self.allocator.free(owned);
                        return error.OutOfMemory;
                    };
                },
                // A bundle contains regular files and directories only. The
                // export path never creates anything else, so encountering
                // one means something outside the exporter wrote here.
                else => return error.SyncFailed,
            }
        }

        std.mem.sort([]u8, directories.items, {}, deeperFirst);
        for (directories.items) |relative| {
            var sub = self.dir.openDir(self.io, relative, .{
                .iterate = true,
                .follow_symlinks = false,
            }) catch return error.SyncFailed;
            defer sub.close(self.io);
            syncDir(self.io, sub) catch return error.SyncFailed;
        }
        syncDir(self.io, self.dir) catch return error.SyncFailed;
    }
};

fn deeperFirst(_: void, left: []u8, right: []u8) bool {
    const left_depth = std.mem.count(u8, left, "/");
    const right_depth = std.mem.count(u8, right, "/");
    if (left_depth != right_depth) return left_depth > right_depth;
    return std.mem.lessThan(u8, left, right);
}

/// Make a directory entry itself durable.
///
/// A directory has no `sync` of its own in `std.Io`, but a directory handle is
/// a file handle: syncing it is what guarantees that the names it contains
/// survive, which is exactly the property a published bundle needs.
fn syncDir(io: std.Io, dir: std.Io.Dir) std.Io.File.SyncError!void {
    const as_file: std.Io.File = .{ .handle = dir.handle, .flags = .{ .nonblocking = false } };
    try as_file.sync(io);
}

const testing = std.testing;

fn writeStaged(staging: *Staging, sub_path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(sub_path)) |parent| {
        try staging.dir.createDirPath(testing.io, parent);
    }
    try staging.dir.writeFile(testing.io, .{ .sub_path = sub_path, .data = data });
}

test "a published bundle appears complete or not at all" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const destination = try std.fs.path.join(testing.allocator, &.{ root, "bundle" });
    defer testing.allocator.free(destination);

    var staging = try Staging.create(testing.allocator, testing.io, destination);
    defer staging.deinit();

    try writeStaged(&staging, "bundle.json", "{}");
    try writeStaged(&staging, "repos/base/repodata/repomd.xml", "<repomd/>");

    // Before publish the destination does not exist at all.
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "bundle", .{}));

    try staging.publish();

    const manifest = try tmp.dir.readFileAlloc(
        testing.io,
        "bundle/bundle.json",
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(manifest);
    try testing.expectEqualStrings("{}", manifest);

    const nested = try tmp.dir.readFileAlloc(
        testing.io,
        "bundle/repos/base/repodata/repomd.xml",
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(nested);
    try testing.expectEqualStrings("<repomd/>", nested);
}

test "abandoning leaves neither a destination nor a bundle-shaped directory" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const destination = try std.fs.path.join(testing.allocator, &.{ root, "bundle" });
    defer testing.allocator.free(destination);

    {
        var staging = try Staging.create(testing.allocator, testing.io, destination);
        defer staging.deinit();
        try writeStaged(&staging, "bundle.json", "{}");
        try writeStaged(&staging, "packages/base/a.rpm", "rpm");
        // Simulate a recoverable failure: return without publishing.
    }

    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "bundle", .{}));

    // And nothing at all is left behind, so no later run can pick up a
    // partially written tree.
    var listing = try std.Io.Dir.cwd().openDir(testing.io, root, .{ .iterate = true });
    defer listing.close(testing.io);
    var it = listing.iterate();
    var count: usize = 0;
    while (try it.next(testing.io)) |_| count += 1;
    try testing.expectEqual(@as(usize, 0), count);
}

test "an existing destination is refused, including an empty directory" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const destination = try std.fs.path.join(testing.allocator, &.{ root, "bundle" });
    defer testing.allocator.free(destination);

    try tmp.dir.createDir(testing.io, "bundle", .default_dir);
    try testing.expectError(
        error.DestinationExists,
        Staging.create(testing.allocator, testing.io, destination),
    );

    try tmp.dir.deleteDir(testing.io, "bundle");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "bundle", .data = "not a bundle" });
    try testing.expectError(
        error.DestinationExists,
        Staging.create(testing.allocator, testing.io, destination),
    );
}

test "a destination created during staging still cannot be overwritten" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const destination = try std.fs.path.join(testing.allocator, &.{ root, "bundle" });
    defer testing.allocator.free(destination);

    var staging = try Staging.create(testing.allocator, testing.io, destination);
    defer staging.deinit();
    try writeStaged(&staging, "bundle.json", "{}");

    // Another process wins the race after the up-front check.
    try tmp.dir.createDir(testing.io, "bundle", .default_dir);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "bundle/other", .data = "theirs" });

    try testing.expectError(error.DestinationExists, staging.publish());

    // Their content is untouched, and ours is cleaned up by deinit.
    const theirs = try tmp.dir.readFileAlloc(
        testing.io,
        "bundle/other",
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(theirs);
    try testing.expectEqualStrings("theirs", theirs);
}

test "publish is idempotent with deinit and does not delete what it published" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const destination = try std.fs.path.join(testing.allocator, &.{ root, "bundle" });
    defer testing.allocator.free(destination);

    {
        var staging = try Staging.create(testing.allocator, testing.io, destination);
        defer staging.deinit();
        try writeStaged(&staging, "bundle.json", "{}");
        try staging.publish();
        // An explicit abandon after a successful publish must be a no-op.
        staging.abandon();
    }

    const manifest = try tmp.dir.readFileAlloc(
        testing.io,
        "bundle/bundle.json",
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(manifest);
    try testing.expectEqualStrings("{}", manifest);
}

test "a staging directory is never named like a bundle" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const destination = try std.fs.path.join(testing.allocator, &.{ root, "bundle" });
    defer testing.allocator.free(destination);

    var staging = try Staging.create(testing.allocator, testing.io, destination);
    defer staging.deinit();
    try testing.expect(std.mem.startsWith(u8, staging.staging_name, Staging.staging_prefix));
    try testing.expect(!std.mem.eql(u8, staging.staging_name, "bundle"));
    try testing.expectEqualStrings("bundle", staging.destination_name);
}

test "an unusable destination path is refused before anything is created" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);

    const missing_parent = try std.fs.path.join(
        testing.allocator,
        &.{ root, "absent", "bundle" },
    );
    defer testing.allocator.free(missing_parent);
    try testing.expectError(
        error.DestinationUnusable,
        Staging.create(testing.allocator, testing.io, missing_parent),
    );

    const dot = try std.fs.path.join(testing.allocator, &.{ root, "." });
    defer testing.allocator.free(dot);
    try testing.expectError(
        error.DestinationUnusable,
        Staging.create(testing.allocator, testing.io, dot),
    );
}

test "syncing walks the whole tree and refuses anything that is not a file or directory" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
    defer testing.allocator.free(root);
    const destination = try std.fs.path.join(testing.allocator, &.{ root, "bundle" });
    defer testing.allocator.free(destination);

    var staging = try Staging.create(testing.allocator, testing.io, destination);
    defer staging.deinit();
    try writeStaged(&staging, "a/b/c/deep.txt", "deep");
    // A symlink is not something the exporter creates, so its presence means
    // the staging area was tampered with. Publishing it would put a
    // non-regular file into an input closure.
    try staging.dir.symLink(testing.io, "a/b/c/deep.txt", "link", .{});

    try testing.expectError(error.SyncFailed, staging.publish());
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, "bundle", .{}));
}
