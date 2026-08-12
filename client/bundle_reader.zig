//! Reading a published bundle back, and proving it is a closed set.
//!
//! A bundle is only useful if a consumer can decide, offline and without
//! trusting the producer, whether what is on disk is exactly what the manifest
//! claims. "Exactly" is the operative word: checking that every listed file is
//! present and correct is not enough, because an *unlisted* file — an extra
//! RPM, a stray key, a symlink pointing outside — means the directory is not
//! an input closure, and a replay driven by it would be reproducible in name
//! only.
//!
//! So the walk is bidirectional. Every entry in the file table must exist with
//! the recorded size and SHA-256, and every file on disk must appear in the
//! file table. `bundle.json` is the sole exception, because a manifest cannot
//! contain its own hash.
//!
//! Nothing here opens a network path, and nothing here follows a symlink.

const std = @import("std");
const content_digest = @import("content_digest");
const transaction_bundle = @import("transaction_bundle");
const transaction_plan = @import("transaction_plan");

pub const OpenError = error{
    /// The directory, or the manifest inside it, could not be read.
    BundleUnreadable,
    /// `bundle.json` is not the canonical serialization of the model it
    /// describes. A lenient parse must not be usable to launder a
    /// non-canonical document into an authoritative one.
    ManifestNotCanonical,
    /// A file the manifest lists is absent.
    MissingFile,
    /// A file exists in the tree that the manifest does not list. The bundle
    /// is therefore not a closure.
    UnlistedFile,
    /// A listed file's bytes do not hash to the recorded value.
    ChecksumMismatch,
    /// A listed file's length does not match the recorded size.
    SizeMismatch,
    /// The tree contains a symlink, device node, or other non-regular entry.
    UnsafeEntry,
    /// `plan.json`'s embedded digest disagrees with the manifest's plan
    /// reference, or its schema does.
    PlanMismatch,
    /// A listed file is larger than this reader is willing to hold.
    FileTooLarge,
    OutOfMemory,
};

/// Largest single file the reader will hash in memory.
pub const max_file_bytes: usize = 1 << 30;

/// Open, validate, and return an owned bundle.
///
/// On success every byte under `directory` has been accounted for: the caller
/// may use the tree without re-checking it. On any failure nothing is
/// returned, so there is no partially-validated result to misuse.
pub fn openBundle(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: []const u8,
) OpenError!*transaction_bundle.Bundle {
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{
        .iterate = true,
        .follow_symlinks = false,
    }) catch return error.BundleUnreadable;
    defer dir.close(io);

    const manifest_bytes = dir.readFileAlloc(
        io,
        transaction_bundle.manifest_name,
        allocator,
        .limited(max_file_bytes),
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.BundleUnreadable,
    };
    defer allocator.free(manifest_bytes);

    const bundle = transaction_bundle.parse(allocator, manifest_bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        // Every other parse failure means the same thing to a consumer: this
        // is not a manifest this implementation would have written.
        else => return error.ManifestNotCanonical,
    };
    errdefer bundle.destroy();

    // The closure walk runs first so that a symlink is rejected before any
    // path is read through it, and so an unlisted file is reported without
    // hashing the whole tree.
    try verifyNoUnlistedEntries(allocator, io, dir, bundle);
    try verifyListedFiles(allocator, io, dir, bundle);
    try verifyPlan(allocator, io, dir, bundle);
    return bundle;
}

fn verifyListedFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    bundle: *const transaction_bundle.Bundle,
) OpenError!void {
    for (bundle.model().files) |entry| {
        const bytes = try readListed(allocator, io, dir, entry.path);
        defer allocator.free(bytes);
        if (bytes.len != entry.size) return error.SizeMismatch;
        const actual = content_digest.sha256Hex(bytes);
        if (!std.ascii.eqlIgnoreCase(entry.sha256, &actual)) return error.ChecksumMismatch;
    }
}

fn readListed(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
) OpenError![]u8 {
    // Any symlink anywhere in the tree has already been rejected by the
    // closure walk, so by the time a listed path is read it is known to name
    // a regular file inside the bundle.
    return dir.readFileAlloc(io, sub_path, allocator, .limited(max_file_bytes)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return error.MissingFile,
        error.StreamTooLong => return error.FileTooLarge,
        else => return error.BundleUnreadable,
    };
}

fn verifyNoUnlistedEntries(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    bundle: *const transaction_bundle.Bundle,
) OpenError!void {
    var walker = dir.walk(allocator) catch return error.OutOfMemory;
    defer walker.deinit();

    // A tree can be faulty in both ways at once, and directory iteration order
    // is a property of the filesystem, not of the bundle. Reporting whichever
    // fault happened to be read first would make a reproducibility tool give
    // different answers for identical trees, so the walk completes and the
    // graver fault always wins.
    var saw_unlisted = false;
    while (walker.next(io) catch return error.BundleUnreadable) |entry| {
        switch (entry.kind) {
            // Empty directories carry no content and are implied by the paths
            // in the file table, so they are not listed and not rejected.
            .directory => continue,
            .file => {},
            // A symlink is rejected even when it points at a listed file: it
            // is an instruction to read something else, and a bundle must
            // never point outside itself.
            else => return error.UnsafeEntry,
        }
        // The manifest cannot list its own hash, so it is the one file that
        // is legitimately present and unlisted.
        if (std.mem.eql(u8, entry.path, transaction_bundle.manifest_name)) continue;
        if (bundle.findFile(entry.path) == null) saw_unlisted = true;
    }
    if (saw_unlisted) return error.UnlistedFile;
}

fn verifyPlan(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    bundle: *const transaction_bundle.Bundle,
) OpenError!void {
    const reference = bundle.model().plan;
    // The plan's file entry was already hashed by `verifyListedFiles`; this
    // additionally proves the bytes are the plan the manifest names, since a
    // file hash and a plan digest are different claims.
    const bytes = try readListed(allocator, io, dir, reference.path);
    defer allocator.free(bytes);

    if (std.mem.eql(u8, reference.schema, transaction_plan.schema_v2)) {
        const plan = transaction_plan.parse(allocator, bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.PlanMismatch,
        };
        defer plan.destroy();
        const digest = plan.digest(allocator) catch return error.OutOfMemory;
        if (!std.mem.eql(u8, &digest, reference.digest) or
            !std.mem.eql(u8, plan.schemaName(), reference.schema) or
            !plan.isReplayable())
        {
            return error.PlanMismatch;
        }
        try verifyPlanPackages(plan.model(), bundle.model().packages);
        return;
    }

    // The plan carries its digest as an object -- algorithm, domain, value --
    // because a bare hex string does not say what was hashed or under which
    // schema. Only the value is comparable to the manifest's reference.
    const embedded = try embeddedPlanDigest(allocator, bytes);
    defer allocator.free(embedded);
    if (!std.mem.eql(u8, embedded, reference.digest)) return error.PlanMismatch;

    const schema = try embeddedString(allocator, bytes, &.{"schema"});
    defer allocator.free(schema);
    if (!std.mem.eql(u8, schema, reference.schema)) return error.PlanMismatch;
}

fn verifyPlanPackages(
    plan: *const transaction_plan.Data,
    packages: []const transaction_bundle.Package,
) OpenError!void {
    const steps = plan.execution_steps orelse return error.PlanMismatch;

    for (packages) |package| {
        const planned = findPlanPackage(
            plan.packages,
            package.plan_package_id,
        ) orelse return error.PlanMismatch;
        if (planned.state != .available or
            !packageIdentityEqual(package.identity, planned.identity) or
            !std.mem.eql(u8, package.repository_id, planned.repository_id))
        {
            return error.PlanMismatch;
        }
        const source = planned.source orelse return error.PlanMismatch;
        const location = source.location orelse return error.PlanMismatch;
        if (!checksumEqual(package.checksum, source.checksum) or
            !std.mem.eql(u8, package.href, location.href) or
            !optionalStringEqual(package.xml_base, location.xml_base) or
            package.size != source.size)
        {
            return error.PlanMismatch;
        }

        var target_count: usize = 0;
        for (steps) |step| {
            if (step.operation != .erase and
                std.mem.eql(u8, step.package_id, package.plan_package_id))
            {
                target_count += 1;
            }
        }
        if (target_count != 1) return error.PlanMismatch;
    }

    for (steps) |step| {
        if (step.operation == .erase) continue;
        var package_count: usize = 0;
        for (packages) |package| {
            if (std.mem.eql(u8, package.plan_package_id, step.package_id)) {
                package_count += 1;
            }
        }
        if (package_count != 1) return error.PlanMismatch;
    }
}

fn findPlanPackage(
    packages: []const transaction_plan.Package,
    id: []const u8,
) ?*const transaction_plan.Package {
    for (packages) |*package| {
        if (std.mem.eql(u8, package.id, id)) return package;
    }
    return null;
}

fn packageIdentityEqual(
    left: transaction_plan.PackageIdentity,
    right: transaction_plan.PackageIdentity,
) bool {
    return std.mem.eql(u8, left.arch, right.arch) and
        left.epoch == right.epoch and
        std.mem.eql(u8, left.name, right.name) and
        std.mem.eql(u8, left.release, right.release) and
        std.mem.eql(u8, left.version, right.version);
}

fn checksumEqual(
    left: transaction_plan.Checksum,
    right: transaction_plan.Checksum,
) bool {
    return left.is_pkgid == right.is_pkgid and
        std.mem.eql(u8, left.kind, right.kind) and
        std.mem.eql(u8, left.value, right.value);
}

fn optionalStringEqual(
    left: ?[]const u8,
    right: ?[]const u8,
) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn embeddedPlanDigest(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) OpenError![]u8 {
    return embeddedString(allocator, bytes, &.{ "digest", "value" });
}

fn embeddedString(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    path: []const []const u8,
) OpenError![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.PlanMismatch,
    };
    defer parsed.deinit();
    var current = parsed.value;
    for (path) |key| {
        const object = switch (current) {
            .object => |object| object,
            else => return error.PlanMismatch,
        };
        current = object.get(key) orelse return error.PlanMismatch;
    }
    return switch (current) {
        .string => |text| allocator.dupe(u8, text) catch error.OutOfMemory,
        else => error.PlanMismatch,
    };
}

const testing = std.testing;

/// Builds a small but genuinely valid bundle on disk for the reader tests.
///
/// It is a real manifest produced by `transaction_bundle`, not hand-written
/// JSON, so a test that corrupts it is corrupting something the exporter could
/// actually have written.
const Fixture = struct {
    tmp: testing.TmpDir,
    root: [:0]u8,
    directory: []u8,

    const plan_digest = "6" ** 64;
    const other_digest = "7" ** 64;
    const fingerprint = "abcdef0123456789abcdef0123456789abcdef01";
    const repomd_sha = "5" ** 64;

    /// Shaped exactly like a real canonical plan: the digest is an object
    /// naming its algorithm and domain, not a bare string.
    const plan_json =
        \\{"digest":{"algorithm":"sha256","domain":"tdnf.transaction-plan/v1","value":"
    ++
        plan_digest ++
        \\"},"schema":"tdnf.transaction-plan/v1"}
    ;
    const package_bytes = "fake rpm bytes";
    const key_bytes = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n";
    const repomd_bytes = "<repomd/>";

    fn create() !Fixture {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();
        const root = try tmp.dir.realPathFileAlloc(testing.io, ".", testing.allocator);
        errdefer testing.allocator.free(root);
        const directory = try std.fs.path.join(testing.allocator, &.{ root, "bundle" });
        errdefer testing.allocator.free(directory);
        try tmp.dir.createDir(testing.io, "bundle", .default_dir);
        return .{ .tmp = tmp, .root = root, .directory = directory };
    }

    fn destroy(self: *Fixture) void {
        testing.allocator.free(self.directory);
        testing.allocator.free(self.root);
        self.tmp.cleanup();
    }

    fn dir(self: *Fixture) !std.Io.Dir {
        return std.Io.Dir.cwd().openDir(testing.io, self.directory, .{
            .iterate = true,
            .follow_symlinks = false,
        });
    }

    fn write(self: *Fixture, sub_path: []const u8, data: []const u8) !void {
        var d = try self.dir();
        defer d.close(testing.io);
        if (std.fs.path.dirname(sub_path)) |parent| {
            try d.createDirPath(testing.io, parent);
        }
        try d.writeFile(testing.io, .{ .sub_path = sub_path, .data = data });
    }

    fn populate(self: *Fixture) !void {
        try self.writeContent(plan_json);
        const manifest = try buildManifest(plan_json, plan_digest);
        defer testing.allocator.free(manifest);
        try self.write(transaction_bundle.manifest_name, manifest);
    }

    fn writeContent(self: *Fixture, plan_bytes: []const u8) !void {
        try self.write(transaction_bundle.plan_name, plan_bytes);
        try self.write("packages/base/a.rpm", package_bytes);
        try self.write("keys/base.asc", key_bytes);
        try self.write("repos/base/repodata/repomd.xml", repomd_bytes);
    }

    /// Produces canonical manifest bytes describing exactly the files
    /// `writeContent` wrote, with a caller-chosen plan reference digest.
    fn buildManifest(plan_bytes: []const u8, reference_digest: []const u8) ![]u8 {
        const plan_hex = content_digest.sha256Hex(plan_bytes);
        const package_hex = content_digest.sha256Hex(package_bytes);
        const key_hex = content_digest.sha256Hex(key_bytes);
        const repomd_hex = content_digest.sha256Hex(repomd_bytes);

        const files = [_]transaction_bundle.File{
            .{ .path = "keys/base.asc", .sha256 = &key_hex, .size = key_bytes.len },
            .{ .path = "packages/base/a.rpm", .sha256 = &package_hex, .size = package_bytes.len },
            .{ .path = transaction_bundle.plan_name, .sha256 = &plan_hex, .size = plan_bytes.len },
            .{
                .path = "repos/base/repodata/repomd.xml",
                .sha256 = &repomd_hex,
                .size = repomd_bytes.len,
            },
        };
        const bundle = try transaction_bundle.Bundle.create(testing.allocator, .{
            .files = &files,
            .keys = &.{.{ .fingerprint = fingerprint, .path = "keys/base.asc" }},
            .packages = &.{.{
                .checksum = .{ .kind = "sha256", .is_pkgid = true, .value = &package_hex },
                .href = "Packages/a.rpm",
                .identity = .{
                    .arch = "noarch",
                    .epoch = null,
                    .name = "a",
                    .release = "1",
                    .version = "1.0",
                },
                .path = "packages/base/a.rpm",
                .plan_package_id = "package-0",
                .repository_id = "base",
                .signature = .{ .outcome = .verified, .key_fingerprint = fingerprint },
                .size = package_bytes.len,
                .xml_base = null,
            }},
            .plan = .{
                .digest = reference_digest,
                .path = transaction_bundle.plan_name,
                .schema = "tdnf.transaction-plan/v1",
            },
            .repositories = &.{.{
                .cost = 1000,
                .gpg_check = true,
                .id = "base",
                .priority = 50,
                .repomd_sha256 = &repomd_hex,
                .revision = "1700000000",
                .snapshot_id = repomd_sha,
                .sources = &.{"https://example.invalid/base/"},
            }},
        });
        defer bundle.destroy();
        return bundle.canonicalJsonAlloc(testing.allocator);
    }
};

test "a complete bundle opens and validates" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();

    const bundle = try openBundle(testing.allocator, testing.io, fixture.directory);
    defer bundle.destroy();
    try testing.expectEqual(@as(usize, 4), bundle.model().files.len);
    try testing.expectEqualStrings(Fixture.plan_digest, bundle.model().plan.digest);
}

test "a missing listed file is rejected" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();

    var dir = try fixture.dir();
    defer dir.close(testing.io);
    try dir.deleteFile(testing.io, "packages/base/a.rpm");

    try testing.expectError(
        error.MissingFile,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "altered bytes are rejected even when the size is unchanged" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();
    // Same length, one byte different: only the hash can catch this.
    try fixture.write("packages/base/a.rpm", "fake rpm byteS");

    try testing.expectError(
        error.ChecksumMismatch,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a size change is reported as a size mismatch" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();
    try fixture.write("packages/base/a.rpm", "fake rpm bytes and more");

    try testing.expectError(
        error.SizeMismatch,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "an unlisted file makes the bundle not a closure" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();
    try fixture.write("packages/base/extra.rpm", "smuggled");

    try testing.expectError(
        error.UnlistedFile,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a symlink is rejected even when it points at a listed file" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();

    var dir = try fixture.dir();
    defer dir.close(testing.io);
    try dir.symLink(testing.io, "packages/base/a.rpm", "alias.rpm", .{});

    try testing.expectError(
        error.UnsafeEntry,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a listed path that resolves through a symlink is not accepted" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();

    var dir = try fixture.dir();
    defer dir.close(testing.io);
    // Replace the real package with a link to identical content held outside
    // the bundle, which is the case that matters: the bytes would verify, and
    // the tree still is not a closure.
    try dir.deleteFile(testing.io, "packages/base/a.rpm");
    try fixture.tmp.dir.writeFile(testing.io, .{
        .sub_path = "elsewhere",
        .data = "fake rpm bytes",
    });
    try dir.symLink(testing.io, "../../../elsewhere", "packages/base/a.rpm", .{});

    try testing.expectError(
        error.UnsafeEntry,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a tree that is both unsafe and unlisted always reports the unsafe entry" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();

    var dir = try fixture.dir();
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "stray", .data = "extra" });
    try dir.symLink(testing.io, "packages/base/a.rpm", "alias.rpm", .{});

    // Which fault a filesystem happens to hand back first is not a property of
    // the bundle. The same tree must always produce the same verdict.
    try testing.expectError(
        error.UnsafeEntry,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a non-canonical manifest is refused rather than normalized" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();

    var dir = try fixture.dir();
    defer dir.close(testing.io);
    const manifest = try dir.readFileAlloc(
        testing.io,
        transaction_bundle.manifest_name,
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(manifest);

    // Whitespace alone changes nothing semantically and everything
    // canonically. A reader that tolerated it could be handed a document it
    // would never itself have produced.
    const padded = try std.fmt.allocPrint(testing.allocator, "{s} ", .{manifest});
    defer testing.allocator.free(padded);
    try fixture.write(transaction_bundle.manifest_name, padded);

    try testing.expectError(
        error.ManifestNotCanonical,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a manifest checksum edited to disagree with the file is refused" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();

    var dir = try fixture.dir();
    defer dir.close(testing.io);
    const manifest = try dir.readFileAlloc(
        testing.io,
        transaction_bundle.manifest_name,
        testing.allocator,
        .unlimited,
    );
    defer testing.allocator.free(manifest);

    // Flip one hex digit of a recorded sha256. The manifest's own digest now
    // no longer covers the document, so this is caught at parse time -- which
    // is the point: the digest binds the whole file table.
    const edited = try testing.allocator.dupe(u8, manifest);
    defer testing.allocator.free(edited);
    const needle = "\"sha256\":\"";
    const at = std.mem.indexOf(u8, edited, needle).? + needle.len;
    edited[at] = if (edited[at] == 'a') 'b' else 'a';
    try fixture.write(transaction_bundle.manifest_name, edited);

    try testing.expectError(
        error.ManifestNotCanonical,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a plan whose embedded digest disagrees with the manifest is refused" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    // Rewrite plan.json *and* its file-table entry so the file hash still
    // matches. Only the plan-digest cross-check can catch this, which is why
    // both a file hash and a plan digest are recorded.
    const swapped =
        \\{"digest":{"algorithm":"sha256","domain":"tdnf.transaction-plan/v1","value":"
    ++
        Fixture.other_digest ++
        \\"},"schema":"tdnf.transaction-plan/v1"}
    ;
    try fixture.writeContent(swapped);
    const manifest = try Fixture.buildManifest(swapped, Fixture.plan_digest);
    defer testing.allocator.free(manifest);
    try fixture.write(transaction_bundle.manifest_name, manifest);

    try testing.expectError(
        error.PlanMismatch,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a plan naming a different schema is refused" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    const wrong_schema =
        \\{"digest":{"algorithm":"sha256","domain":"tdnf.transaction-plan/v1","value":"
    ++
        Fixture.plan_digest ++
        \\"},"schema":"tdnf.transaction-plan/v2"}
    ;
    try fixture.writeContent(wrong_schema);
    const manifest = try Fixture.buildManifest(wrong_schema, Fixture.plan_digest);
    defer testing.allocator.free(manifest);
    try fixture.write(transaction_bundle.manifest_name, manifest);

    try testing.expectError(
        error.PlanMismatch,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}

test "a missing manifest or directory is unreadable, not empty" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    try testing.expectError(
        error.BundleUnreadable,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );

    const absent = try std.fs.path.join(testing.allocator, &.{ fixture.root, "absent" });
    defer testing.allocator.free(absent);
    try testing.expectError(
        error.BundleUnreadable,
        openBundle(testing.allocator, testing.io, absent),
    );
}

test "an empty directory in the tree is allowed but an empty file is not" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    try fixture.populate();

    var dir = try fixture.dir();
    defer dir.close(testing.io);
    try dir.createDirPath(testing.io, "repos/base/empty");

    // Directories carry no content, so an empty one is not a closure
    // violation.
    const bundle = try openBundle(testing.allocator, testing.io, fixture.directory);
    bundle.destroy();

    // A zero-byte file, on the other hand, is content nobody listed.
    try dir.writeFile(testing.io, .{ .sub_path = "keys/stray.asc", .data = "" });
    try testing.expectError(
        error.UnlistedFile,
        openBundle(testing.allocator, testing.io, fixture.directory),
    );
}
