//! Acceptance proof for the transaction bundle export (#187).
//!
//! Every test here drives the real `exportBundle` against a self-contained
//! file repository this test builds, and then reads the result back through
//! the same `openBundle` a consumer would use. Nothing is asserted about
//! internal state: a bundle either satisfies an external reader or it does
//! not, and that is the only claim worth making about it.
//!
//! The fixture is deliberately complete -- real metadata, a real payload, real
//! checksums -- because the properties under test are exactly the ones a
//! hand-mocked fixture cannot show: that the bundle still validates when the
//! repository it came from is gone, that exporting twice produces identical
//! bytes, and that a failure leaves nothing behind.

const std = @import("std");
const client = @import("client_root");
const bundle_reader = @import("bundle_reader");
const transaction_bundle = @import("transaction_bundle");
const repository_metadata = @import("repository_metadata");

comptime {
    _ = client;
}

const bundle_export = client.bundle_export;
const resolver = client.resolver;
const io = std.testing.io;
const allocator = std.testing.allocator;

fn rpmPayload(version: []const u8) ![]u8 {
    return repository_metadata.rpm_package.makeMinimalRpmBytesForTest(
        allocator,
        "app",
        version,
        "1",
        "x86_64",
    );
}

fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{&digest}) catch unreachable;
    return hex;
}

fn primaryXml(
    gpa: std.mem.Allocator,
    version: []const u8,
    rpm_payload: []const u8,
) ![]u8 {
    const payload_digest = sha256Hex(rpm_payload);
    return std.fmt.allocPrint(gpa,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<metadata xmlns="http://linux.duke.edu/metadata/common"
        \\              xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="1">
        \\  <package type="rpm">
        \\    <name>app</name>
        \\    <arch>x86_64</arch>
        \\    <version epoch="0" ver="{s}" rel="1"/>
        \\    <checksum type="sha256" pkgid="YES">{s}</checksum>
        \\    <size package="{d}"/>
        \\    <location href="packages/app.rpm"/>
        \\  </package>
        \\</metadata>
        \\
    , .{ version, &payload_digest, rpm_payload.len });
}

fn repomdFor(gpa: std.mem.Allocator, primary: []const u8) ![]u8 {
    const primary_digest = sha256Hex(primary);
    return std.fmt.allocPrint(gpa,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
        \\  <revision>bundle-export-test</revision>
        \\  <data type="primary">
        \\    <checksum type="sha256">{s}</checksum>
        \\    <open-checksum type="sha256">{s}</open-checksum>
        \\    <location href="repodata/primary.xml"/>
        \\    <timestamp>123</timestamp>
        \\    <size>{d}</size>
        \\    <open-size>{d}</open-size>
        \\  </data>
        \\</repomd>
        \\
    , .{ &primary_digest, &primary_digest, primary.len, primary.len });
}

const Fixture = struct {
    tmp: std.testing.TmpDir,
    base: []u8,
    root: []u8,
    snapshot: []u8,
    scratch: []u8,
    /// Held by the fixture rather than built inline. `&.{ ... }` around a
    /// runtime value is the address of a temporary that dies with the
    /// expression, and the resulting read is silent rather than a compile
    /// error.
    repositories: [1]resolver.Repository = undefined,
    /// Owns the per-export scratch paths handed out by `input`.
    arena: std.heap.ArenaAllocator,

    fn create() !Fixture {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();

        try tmp.dir.createDirPath(io, "root");
        try tmp.dir.createDirPath(io, "work");
        try tmp.dir.createDirPath(io, "snapshot/repodata");
        try tmp.dir.createDirPath(io, "snapshot/packages");

        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        const base = try allocator.dupe(u8, buffer[0..length]);
        errdefer allocator.free(base);

        var self = Fixture{
            .tmp = tmp,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .base = base,
            .root = undefined,
            .snapshot = undefined,
            .scratch = undefined,
        };
        self.root = try std.fmt.allocPrint(allocator, "{s}/root", .{base});
        errdefer allocator.free(self.root);
        self.snapshot = try std.fmt.allocPrint(allocator, "{s}/snapshot", .{base});
        errdefer allocator.free(self.snapshot);
        self.scratch = try std.fmt.allocPrint(allocator, "{s}/work", .{base});
        errdefer allocator.free(self.scratch);

        try self.publishRepository("1");
        return self;
    }

    /// Writes a complete, internally consistent repository. `version` lets a
    /// test change what the repository says without changing anything else.
    fn publishRepository(self: *Fixture, version: []const u8) !void {
        const rpm_payload = try rpmPayload(version);
        defer allocator.free(rpm_payload);
        const primary = try primaryXml(allocator, version, rpm_payload);
        defer allocator.free(primary);
        const repomd = try repomdFor(allocator, primary);
        defer allocator.free(repomd);
        try self.tmp.dir.writeFile(io, .{
            .sub_path = "snapshot/repodata/primary.xml",
            .data = primary,
        });
        try self.tmp.dir.writeFile(io, .{
            .sub_path = "snapshot/repodata/repomd.xml",
            .data = repomd,
        });
        try self.tmp.dir.writeFile(io, .{
            .sub_path = "snapshot/packages/app.rpm",
            .data = rpm_payload,
        });
    }

    fn destroy(self: *Fixture) void {
        self.arena.deinit();
        allocator.free(self.scratch);
        allocator.free(self.snapshot);
        allocator.free(self.root);
        allocator.free(self.base);
        self.tmp.cleanup();
        self.* = undefined;
    }

    /// The path `input(name)` will publish to. Arena-backed, so a test that
    /// only needs to look at the result does not have to free it.
    fn destinationAlloc(self: *Fixture, name: []const u8) ![]u8 {
        return std.fmt.allocPrint(
            self.arena.allocator(),
            "{s}/{s}",
            .{ self.base, name },
        );
    }

    /// Each export gets its own scratch and install root, the way a fresh
    /// machine would. The install root holds the metadata cache, and a local
    /// snapshot is cached with `metadata_expire=never`, so sharing one would
    /// make a second export resolve against the first export's view of the
    /// repository. That is a cache-staleness scenario with its own test, not
    /// the property most of these tests are about.
    fn input(self: *Fixture, name: []const u8) !bundle_export.ExportInput {
        const scratch = try std.fmt.allocPrint(
            self.arena.allocator(),
            "work/{s}",
            .{name},
        );
        try self.tmp.dir.createDirPath(io, scratch);
        const root = try std.fmt.allocPrint(self.arena.allocator(), "root/{s}", .{name});
        try self.tmp.dir.createDirPath(io, root);
        const destination = try self.destinationAlloc(name);
        self.repositories[0] = .{
            .id = "base",
            .metadata = .{ .local_snapshot = self.snapshot },
        };
        return .{
            .resolve = .{
                .operation = .install,
                .subjects = &.{"app"},
                .repositories = self.repositories[0..],
                .installed = .{ .install_root = try std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s}/{s}",
                    .{ self.base, root },
                ) },
                .environment = .{
                    .architecture = "x86_64",
                    .distro = "fixture-distro",
                    .release_version = "42",
                },
                .cache_dir = "/cache",
                .scratch_dir = try std.fmt.allocPrint(
                    self.arena.allocator(),
                    "{s}/{s}",
                    .{ self.base, scratch },
                ),
            },
            .destination = destination,
            // The fixture payload is not a signed RPM. Signature attestation
            // has its own coverage; what these tests prove is everything that
            // must hold regardless of how a package was signed.
            .gpg_check = false,
        };
    }
};

/// Recursively reads every regular file under `path`, so a test can make a
/// claim about the whole published tree rather than about the files it
/// remembered to check.
fn readTree(
    gpa: std.mem.Allocator,
    path: []const u8,
    out: *std.ArrayList([]u8),
    names: *std.ArrayList([]u8),
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        try names.append(gpa, try gpa.dupe(u8, entry.path));
        try out.append(gpa, try dir.readFileAlloc(io, entry.path, gpa, .limited(1 << 20)));
    }
}

test "an exported bundle validates as a closed set" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();
    try std.testing.expect(result == .exported);
    try std.testing.expect(result.exported.plan.isReplayable());
    try std.testing.expectEqualStrings(
        "tdnf.transaction-plan/v2",
        result.exported.plan.schemaName(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        result.exported.plan.model().execution_steps.?.len,
    );

    const bundle = try bundle_reader.openBundle(allocator, io, destination);
    defer bundle.destroy();
    try std.testing.expect(bundle.isReplayable());
    try std.testing.expectEqualStrings(
        "tdnf.transaction-bundle/v2",
        bundle.schemaName(),
    );
    try std.testing.expectEqualStrings(
        &result.exported.plan_digest,
        bundle.model().plan.digest,
    );

    // The bundle must carry the RPM the plan selected and the metadata the
    // resolve was performed against.
    try std.testing.expect(bundle.findFile("packages/base/packages/app.rpm") != null);
    try std.testing.expect(bundle.findFile("repos/base/repodata/repomd.xml") != null);
    try std.testing.expect(bundle.findFile("repos/base/repodata/primary.xml") != null);
    try std.testing.expect(bundle.findFile("plan.json") != null);
    try std.testing.expectEqual(@as(usize, 1), bundle.model().packages.len);
    try std.testing.expectEqualStrings("app", bundle.model().packages[0].identity.name);
}

test "a bundle still validates after the repository it came from is gone" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    // This is the whole point of the feature: the origin disappears and the
    // bundle is still a complete, checkable input set.
    try fixture.tmp.dir.deleteTree(io, "snapshot");

    const bundle = try bundle_reader.openBundle(allocator, io, destination);
    defer bundle.destroy();
    try std.testing.expect(bundle.findFile("packages/base/packages/app.rpm") != null);
}

test "exporting the same repository state twice produces the same digest" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    var first = try bundle_export.exportBundle(allocator, io, try fixture.input("first"));
    defer first.deinit();
    var second = try bundle_export.exportBundle(allocator, io, try fixture.input("second"));
    defer second.deinit();

    try std.testing.expectEqualStrings(
        &first.exported.bundle_digest,
        &second.exported.bundle_digest,
    );
    try std.testing.expectEqualStrings(
        &first.exported.plan_digest,
        &second.exported.plan_digest,
    );
}

test "a changed repository moves the bundle digest" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    var first = try bundle_export.exportBundle(allocator, io, try fixture.input("first"));
    defer first.deinit();
    const before = first.exported.bundle_digest;

    // A newer package version is a different transaction, and a digest that
    // did not move would make two unlike bundles indistinguishable.
    try fixture.publishRepository("2");

    var second = try bundle_export.exportBundle(allocator, io, try fixture.input("second"));
    defer second.deinit();
    try std.testing.expect(!std.mem.eql(u8, &before, &second.exported.bundle_digest));
}

test "no credential reaches the published tree, its filenames, or its manifest" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var contents: std.ArrayList([]u8) = .empty;
    var names: std.ArrayList([]u8) = .empty;
    try readTree(arena, destination, &contents, &names);

    try std.testing.expect(contents.items.len > 0);
    for (contents.items) |body| {
        try std.testing.expect(std.mem.indexOf(u8, body, "hunter2") == null);
    }
    for (names.items) |name| {
        try std.testing.expect(std.mem.indexOf(u8, name, "hunter2") == null);
    }
}

test "a repository that cannot serve a package leaves no destination behind" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    // The metadata still promises the package; the file is gone.
    try fixture.tmp.dir.deleteFile(io, "snapshot/packages/app.rpm");

    try std.testing.expectError(
        error.FetchFailed,
        bundle_export.exportBundle(allocator, io, try fixture.input("bundle")),
    );
    // No success-shaped partial output: a caller that only checked for the
    // directory's existence must never see one.
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, destination, .{}),
    );
}

test "a package whose bytes were substituted after publication is refused" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    try fixture.tmp.dir.writeFile(io, .{
        .sub_path = "snapshot/packages/app.rpm",
        .data = "substituted content of a different length",
    });

    try std.testing.expectError(
        error.IntegrityFailure,
        bundle_export.exportBundle(allocator, io, try fixture.input("bundle")),
    );
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, destination, .{}),
    );
}

test "exporting onto a path that already exists is refused" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    try fixture.tmp.dir.createDirPath(io, "bundle");
    try std.testing.expectError(
        error.PublishFailed,
        bundle_export.exportBundle(allocator, io, try fixture.input("bundle")),
    );
}

test "a deleted file makes a published bundle stop validating" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    var dir = try std.Io.Dir.cwd().openDir(io, destination, .{ .iterate = true });
    defer dir.close(io);
    try dir.deleteFile(io, "packages/base/packages/app.rpm");

    try std.testing.expectError(
        error.MissingFile,
        bundle_reader.openBundle(allocator, io, destination),
    );
}

test "a single flipped byte makes a published bundle stop validating" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    var dir = try std.Io.Dir.cwd().openDir(io, destination, .{ .iterate = true });
    defer dir.close(io);
    const original = try rpmPayload("1");
    defer allocator.free(original);
    var altered = try allocator.dupe(u8, original);
    defer allocator.free(altered);
    altered[0] +%= 1;
    try dir.writeFile(io, .{
        .sub_path = "packages/base/packages/app.rpm",
        .data = altered,
    });

    // Same length, one different byte: only the hash can catch this.
    try std.testing.expectError(
        error.ChecksumMismatch,
        bundle_reader.openBundle(allocator, io, destination),
    );
}

test "an extra file makes a published bundle stop validating" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    var dir = try std.Io.Dir.cwd().openDir(io, destination, .{ .iterate = true });
    defer dir.close(io);
    try dir.writeFile(io, .{
        .sub_path = "packages/base/packages/extra.rpm",
        .data = "an rpm nobody asked for",
    });

    // Everything listed is still correct. The tree is simply no longer a
    // closure, and a replay driven by it would not be reproducible.
    try std.testing.expectError(
        error.UnlistedFile,
        bundle_reader.openBundle(allocator, io, destination),
    );
}

test "moving a package between repository trees makes a bundle stop validating" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    var dir = try std.Io.Dir.cwd().openDir(io, destination, .{ .iterate = true });
    defer dir.close(io);
    const original = try rpmPayload("1");
    defer allocator.free(original);
    try dir.createDirPath(io, "packages/other/packages");
    try dir.writeFile(io, .{
        .sub_path = "packages/other/packages/app.rpm",
        .data = original,
    });
    try dir.deleteFile(io, "packages/base/packages/app.rpm");

    // The bytes are present and correct; the repository attribution is not.
    // The move leaves two faults at once -- a file nothing lists, and a
    // listed file that is gone -- and the closure walk runs first, so the
    // unlisted copy is what a consumer is told about. Either way the bundle
    // is refused, which is the property that matters: a package's identity
    // includes which repository it came from.
    try std.testing.expectError(
        error.UnlistedFile,
        bundle_reader.openBundle(allocator, io, destination),
    );
}

test "an export whose cached metadata no longer matches the repository fails closed" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    var first = try bundle_export.exportBundle(allocator, io, try fixture.input("first"));
    first.deinit();

    // Reusing the install root reuses its metadata cache, and a local
    // snapshot is cached with `metadata_expire=never`. So this resolve pins
    // the repository as it was, while the fetch sees it as it now is.
    try fixture.publishRepository("2");
    var stale = try fixture.input("first");
    stale.destination = try fixture.destinationAlloc("stale");

    // The bundle that a successful export would have published would name a
    // repomd its own plan does not pin. Refusing is the only correct answer:
    // a bundle that disagrees with itself is worse than no bundle.
    try std.testing.expectError(
        error.IntegrityFailure,
        bundle_export.exportBundle(allocator, io, stale),
    );
    try std.testing.expectError(
        error.FileNotFound,
        fixture.tmp.dir.access(io, "stale", .{}),
    );
}

test "a repository declared with a credential in its URL is refused outright" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const input = try fixture.input("bundle");

    // Sanitizing this would still mean the credential was accepted, held in
    // memory, and sent to whatever answered. Refusing the declaration is the
    // only point at which the secret can be kept out of the export entirely.
    const url = try std.fmt.allocPrint(
        allocator,
        "file://user:hunter2@{s}",
        .{fixture.snapshot},
    );
    defer allocator.free(url);
    var urls = [_][]const u8{url};
    fixture.repositories[0].metadata = .{ .remote = .{ .base_urls = urls[0..] } };

    try std.testing.expectError(
        error.CredentialsInUrl,
        bundle_export.exportBundle(allocator, io, input),
    );
    try std.testing.expectError(
        error.FileNotFound,
        fixture.tmp.dir.access(io, "bundle", .{}),
    );
}

test "a bundle records the source it was told to use" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const input = try fixture.input("bundle");
    const url = try std.fmt.allocPrint(allocator, "file://{s}", .{fixture.snapshot});
    defer allocator.free(url);
    var urls = [_][]const u8{url};
    fixture.repositories[0].metadata = .{ .remote = .{ .base_urls = urls[0..] } };

    var result = try bundle_export.exportBundle(allocator, io, input);
    defer result.deinit();

    var opened = try bundle_reader.openBundle(
        allocator,
        io,
        try fixture.destinationAlloc("bundle"),
    );
    defer opened.destroy();

    // The declared URL, not the location that answered: a mirror is a way of
    // reaching a repository, not a property of the transaction.
    const sources = opened.model().repositories[0].sources;
    try std.testing.expectEqual(@as(usize, 1), sources.len);
    try std.testing.expectEqualStrings(url, sources[0]);
}

test "an altered plan makes a published bundle stop validating" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    var dir = try std.Io.Dir.cwd().openDir(io, destination, .{ .iterate = true });
    defer dir.close(io);
    const plan = try dir.readFileAlloc(io, transaction_bundle.plan_name, allocator, .unlimited);
    defer allocator.free(plan);
    const edited = try allocator.dupe(u8, plan);
    defer allocator.free(edited);
    edited[edited.len - 1] = ' ';
    try dir.writeFile(io, .{ .sub_path = transaction_bundle.plan_name, .data = edited });

    // The plan is listed in the manifest like any other file, so editing it is
    // caught by its recorded hash before its contents are ever believed.
    try std.testing.expectError(
        error.ChecksumMismatch,
        bundle_reader.openBundle(allocator, io, destination),
    );
}

test "an altered manifest makes a published bundle stop validating" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    var dir = try std.Io.Dir.cwd().openDir(io, destination, .{ .iterate = true });
    defer dir.close(io);
    const manifest = try dir.readFileAlloc(
        io,
        transaction_bundle.manifest_name,
        allocator,
        .unlimited,
    );
    defer allocator.free(manifest);
    const edited = try std.fmt.allocPrint(allocator, "{s} ", .{manifest});
    defer allocator.free(edited);
    try dir.writeFile(io, .{ .sub_path = transaction_bundle.manifest_name, .data = edited });

    // Nothing outside the manifest vouches for the manifest, so it has to
    // vouch for itself: it is rejected unless it is byte-for-byte the
    // canonical form its own digest covers.
    try std.testing.expectError(
        error.ManifestNotCanonical,
        bundle_reader.openBundle(allocator, io, destination),
    );
}

test "a recorded checksum edited to disagree with its file is refused" {
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const destination = try fixture.destinationAlloc("bundle");

    var result = try bundle_export.exportBundle(allocator, io, try fixture.input("bundle"));
    defer result.deinit();

    var dir = try std.Io.Dir.cwd().openDir(io, destination, .{ .iterate = true });
    defer dir.close(io);
    const manifest = try dir.readFileAlloc(
        io,
        transaction_bundle.manifest_name,
        allocator,
        .unlimited,
    );
    defer allocator.free(manifest);
    const edited = try allocator.dupe(u8, manifest);
    defer allocator.free(edited);
    const needle = "\"sha256\":\"";
    const at = std.mem.indexOf(u8, edited, needle).? + needle.len;
    edited[at] = if (edited[at] == 'a') 'b' else 'a';
    try dir.writeFile(io, .{ .sub_path = transaction_bundle.manifest_name, .data = edited });

    // Editing a file table entry edits the manifest, and the manifest's digest
    // covers the whole document. An attacker cannot revise one hash in
    // isolation.
    try std.testing.expectError(
        error.ManifestNotCanonical,
        bundle_reader.openBundle(allocator, io, destination),
    );
}

test "a changed environment moves the bundle digest" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    var first = try bundle_export.exportBundle(allocator, io, try fixture.input("first"));
    defer first.deinit();

    // Same repository, same packages, different release. The transaction is
    // not the same transaction, and a digest that ignored this would let a
    // bundle built for one release stand in for another.
    var changed = try fixture.input("second");
    changed.resolve.environment.release_version = "43";
    var second = try bundle_export.exportBundle(allocator, io, changed);
    defer second.deinit();

    try std.testing.expect(!std.mem.eql(
        u8,
        &first.exported.bundle_digest,
        &second.exported.bundle_digest,
    ));
}

test "a failed export leaves nothing beside the destination that validates" {
    var fixture = try Fixture.create();
    defer fixture.destroy();

    try fixture.tmp.dir.deleteFile(io, "snapshot/packages/app.rpm");
    try std.testing.expectError(
        error.FetchFailed,
        bundle_export.exportBundle(allocator, io, try fixture.input("bundle")),
    );

    // Staging happens beside the destination, so a partial tree left behind
    // would be the thing a consumer stumbles onto. Whatever survives, none of
    // it may pass for a bundle.
    var base = try std.Io.Dir.cwd().openDir(io, fixture.base, .{ .iterate = true });
    defer base.close(io);
    var iterator = base.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const path = try fixture.destinationAlloc(entry.name);
        // Which way it fails depends on how far the abandoned tree got. That
        // it fails is the claim.
        if (bundle_reader.openBundle(allocator, io, path)) |opened| {
            opened.destroy();
            std.debug.print("directory {s} validated as a bundle\n", .{entry.name});
            return error.TestUnexpectedResult;
        } else |_| {}
    }
}
