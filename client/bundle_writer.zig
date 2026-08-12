//! Turning a selection into a published bundle.
//!
//! This is the whole export except for two things it deliberately does not
//! own: where a plan comes from, and how bytes arrive. Both are injected, so
//! the rules that matter -- what is verified, in what order, and what happens
//! when verification fails -- are testable without a repository server.
//!
//! The order is not incidental. Within a repository, `repomd.xml` is fetched
//! and pinned against the plan's `repomd_sha256` **before any record named by
//! it is fetched**. A record's checksum is only trustworthy because it came
//! from a repomd the plan already vouched for; fetching a record first and
//! checking the repomd afterwards would mean deciding to trust bytes on the
//! strength of a document nobody had verified yet.
//!
//! Nothing is written where a consumer could see it. Every byte lands in a
//! staging tree, and the tree is published with a single non-replacing rename
//! only after the manifest is complete. A failure at any point -- a bad
//! checksum, a short read, an unmappable path -- leaves the destination
//! untouched rather than leaving a bundle that is almost right.

const std = @import("std");
const atomic_publish = @import("atomic_publish");
const bundle_selection = @import("bundle_selection");
const transaction_bundle = @import("transaction_bundle");
const transaction_plan = @import("transaction_plan");
const uri_sanitize = @import("uri_sanitize");
const verified_fetch = @import("verified_fetch");

const Allocator = std.mem.Allocator;

/// Cap on a single bundled file. Large enough for any real RPM or metadata
/// blob; small enough that a repository cannot exhaust memory by claiming a
/// size it then exceeds.
pub const max_file_bytes: usize = 4 << 30;

pub const plan_relative = "plan.json";
pub const manifest_relative = transaction_bundle.manifest_name;

pub const WriteError = error{
    /// A transfer failed. Distinct from a verification failure so "could not
    /// reach the repository" is never reported as "the repository lied".
    FetchFailed,
    /// Bytes arrived but did not match what the plan or the repomd promised.
    IntegrityFailure,
    /// A key blob named by the caller could not be read.
    KeyUnreadable,
    /// Signature verification of a staged package did not permit a claim.
    /// Kept distinct from an integrity failure: the bytes were what the
    /// metadata promised, and were still not acceptable to ship.
    SignatureRejected,
    /// The destination exists, or the staging tree could not be created or
    /// published.
    PublishFailed,
    /// The manifest the export produced is not a valid bundle. This is an
    /// internal contradiction, not a repository fault.
    ManifestInvalid,
    OutOfMemory,
};

/// Resolves a declared href to something the transport can fetch.
///
/// The exporter never guesses a base: a plan records what a repository
/// declared, not where the caller configured it, so the caller supplies the
/// mapping it used for the resolve.
pub const Locator = struct {
    context: *anyopaque,
    /// Returns an allocated location for `href` within `repository_id`.
    locateFn: *const fn (
        context: *anyopaque,
        allocator: Allocator,
        repository_id: []const u8,
        href: []const u8,
    ) Allocator.Error![]u8,

    fn locate(
        self: Locator,
        allocator: Allocator,
        repository_id: []const u8,
        href: []const u8,
    ) Allocator.Error![]u8 {
        return self.locateFn(self.context, allocator, repository_id, href);
    }
};

/// A public key that validated at least one package in this transaction.
pub const KeyInput = struct {
    /// Full fingerprint of the key, as the verifier reported it.
    fingerprint: []const u8,
    /// Absolute path to the key blob to copy into the bundle.
    source_path: []const u8,
};

/// What a repository contributed, beyond what the plan records.
pub const RepositoryInput = struct {
    id: []const u8,
    gpg_check: bool,
    /// Declared source URLs, in caller order. Sanitized before recording:
    /// userinfo in a configured URL is a credential, and a bundle is a
    /// shareable artifact.
    sources: []const []const u8,
};

/// What verification concluded about one staged package.
pub const Attestation = struct {
    outcome: transaction_bundle.SignatureOutcome,
    /// Lower-case hex fingerprint of the key that validated the package.
    /// Borrowed for the duration of the call; the writer copies it.
    key_fingerprint: ?[]const u8 = null,
};

/// Decides what a bundle may claim about a package's signature.
///
/// It is handed the staged file, not the URL and not a pre-computed verdict,
/// because the only bytes worth attesting are the bytes that will ship. A
/// signature checked against an earlier copy proves nothing about the file in
/// the bundle.
pub const Attestor = struct {
    context: *anyopaque,
    attestFn: *const fn (
        context: *anyopaque,
        dir: std.Io.Dir,
        sub_path: []const u8,
        repository_id: []const u8,
    ) anyerror!Attestation,

    fn attest(
        self: Attestor,
        dir: std.Io.Dir,
        sub_path: []const u8,
        repository_id: []const u8,
    ) anyerror!Attestation {
        return self.attestFn(self.context, dir, sub_path, repository_id);
    }
};

pub const MaterializedPlan = struct {
    json: []const u8,
    digest: []const u8,
    schema: []const u8,
};

pub const PlanMaterializer = struct {
    context: *anyopaque,
    materializeFn: *const fn (
        context: *anyopaque,
        allocator: Allocator,
        staging_root: []const u8,
    ) anyerror!MaterializedPlan,

    fn materialize(
        self: PlanMaterializer,
        allocator: Allocator,
        staging_root: []const u8,
    ) anyerror!MaterializedPlan {
        return self.materializeFn(self.context, allocator, staging_root);
    }
};

pub const Options = struct {
    selection: *const bundle_selection.Selection,
    /// Canonical fixed plan bytes used when `plan_materializer` is null.
    plan_json: []const u8,
    plan_digest: []const u8,
    plan_schema: []const u8,
    /// When present, the verified staged RPMs are used to produce a v2 plan
    /// after package fetch and before publication. The fixed v1 fields above
    /// remain available for resolve-only writer tests and legacy callers.
    plan_materializer: ?PlanMaterializer = null,
    repositories: []const RepositoryInput,
    attestor: Attestor,
    keys: []const KeyInput,
    fetcher: verified_fetch.Fetcher,
    locator: Locator,
    /// Absolute or cwd-relative path the finished bundle takes. Must not exist.
    destination: []const u8,
};

pub const Written = struct {
    /// The bundle's own digest, over its canonical manifest.
    digest: [64]u8,
    /// Number of files recorded in the manifest, excluding `bundle.json`.
    file_count: usize,
};

/// Fetch, verify, record, and publish. Publishes nothing on any failure.
pub fn write(
    allocator: Allocator,
    io: std.Io,
    options: Options,
) WriteError!Written {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var staging = atomic_publish.Staging.create(allocator, io, options.destination) catch
        return error.PublishFailed;
    defer staging.deinit();

    var files: std.ArrayList(transaction_bundle.File) = .empty;

    var plan_json = options.plan_json;
    var plan_digest = options.plan_digest;
    var plan_schema = options.plan_schema;
    if (options.plan_materializer == null) {
        try writeStaged(io, staging.dir, plan_relative, plan_json);
        try recordFile(arena, &files, plan_relative, plan_json);
    }

    var repositories: std.ArrayList(transaction_bundle.Repository) = .empty;
    for (options.selection.repositories) |repository| {
        const inputs = findRepository(options.repositories, repository.id) orelse
            return error.ManifestInvalid;

        // Pin repomd before trusting anything it names.
        const repomd_location = try options.locator.locate(
            arena,
            repository.id,
            bundle_selection.repomd_relative,
        );
        const repomd_bytes = try fetchInto(
            io,
            arena,
            options,
            staging.dir,
            repomd_location,
            repository.repomd_path,
        );
        _ = verified_fetch.verifyRepomd(repomd_bytes, repository.repomd_sha256) catch
            return error.IntegrityFailure;
        try recordFile(arena, &files, repository.repomd_path, repomd_bytes);

        const sources = try sanitizeSources(arena, inputs.sources);
        try repositories.append(arena, .{
            .cost = repository.cost,
            .gpg_check = inputs.gpg_check,
            .id = repository.id,
            .priority = repository.priority,
            .repomd_sha256 = repository.repomd_sha256,
            .revision = repository.revision,
            .snapshot_id = repository.snapshot_id,
            .sources = sources,
        });
    }

    for (options.selection.metadata) |record| {
        const location = try options.locator.locate(arena, record.repository_id, record.href);
        const capture = try fetchVerify(io, arena, options, staging.dir, location, record.path, .{
            .checksum = record.checksum,
            .size = record.size,
            .open_checksum = record.open_checksum,
            .open_size = record.open_size,
        });
        try files.append(arena, .{
            .path = record.path,
            .sha256 = try arena.dupe(u8, capture.sha256Slice()),
            .size = capture.size,
        });
    }

    var packages: std.ArrayList(transaction_bundle.Package) = .empty;
    for (options.selection.packages) |package| {
        const location = try options.locator.locate(arena, package.repository_id, package.href);
        const capture = try fetchVerify(io, arena, options, staging.dir, location, package.path, .{
            .checksum = package.checksum,
            .size = package.size,
        });
        try files.append(arena, .{
            .path = package.path,
            .sha256 = try arena.dupe(u8, capture.sha256Slice()),
            .size = capture.size,
        });

        // Attested on the staged bytes, after they matched the plan's
        // checksum, so the claim in the manifest is about the file that ships.
        const attestation = options.attestor.attest(
            staging.dir,
            package.path,
            package.repository_id,
        ) catch return error.SignatureRejected;
        const fingerprint = if (attestation.key_fingerprint) |value|
            try arena.dupe(u8, value)
        else
            null;
        try packages.append(arena, .{
            .checksum = package.checksum,
            .href = package.href,
            .identity = package.identity,
            .path = package.path,
            .plan_package_id = package.plan_package_id,
            .repository_id = package.repository_id,
            .signature = .{
                .outcome = attestation.outcome,
                .key_fingerprint = fingerprint,
            },
            .size = package.size,
            .xml_base = package.xml_base,
        });
    }

    if (options.plan_materializer) |materializer| {
        const staging_root = staging.realPathAlloc(arena) catch
            return error.PublishFailed;
        const materialized = materializer.materialize(
            arena,
            staging_root,
        ) catch return error.ManifestInvalid;
        plan_json = materialized.json;
        plan_digest = materialized.digest;
        plan_schema = materialized.schema;
        try writeStaged(io, staging.dir, plan_relative, plan_json);
        try recordFile(arena, &files, plan_relative, plan_json);
    }

    var keys: std.ArrayList(transaction_bundle.Key) = .empty;
    for (options.keys) |key| {
        const path = try std.fmt.allocPrint(
            arena,
            "{s}{s}.asc",
            .{ transaction_bundle.keys_prefix, key.fingerprint },
        );
        const bytes = std.Io.Dir.cwd().readFileAlloc(
            io,
            key.source_path,
            arena,
            .limited(max_file_bytes),
        ) catch return error.KeyUnreadable;
        try writeStaged(io, staging.dir, path, bytes);
        try recordFile(arena, &files, path, bytes);
        try keys.append(arena, .{ .fingerprint = key.fingerprint, .path = path });
    }

    const data: transaction_bundle.Data = .{
        .files = files.items,
        .keys = keys.items,
        .packages = packages.items,
        .plan = .{
            .digest = plan_digest,
            .path = plan_relative,
            .schema = plan_schema,
        },
        .repositories = repositories.items,
    };

    const bundle = transaction_bundle.Bundle.create(allocator, data) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        // A schema violation here means the exporter built something the
        // reader would reject. Refusing to publish it is the only honest
        // outcome: a bundle nobody can open is worse than no bundle.
        else => return error.ManifestInvalid,
    };
    defer bundle.destroy();

    const manifest = bundle.canonicalJsonAlloc(arena) catch return error.OutOfMemory;
    try writeStaged(io, staging.dir, manifest_relative, manifest);

    staging.publish() catch return error.PublishFailed;
    return .{
        .digest = bundle.digest(arena) catch return error.OutOfMemory,
        .file_count = files.items.len,
    };
}

fn fetchVerify(
    io: std.Io,
    arena: Allocator,
    options: Options,
    dir: std.Io.Dir,
    location: []const u8,
    sub_path: []const u8,
    expectation: verified_fetch.Expectation,
) WriteError!verified_fetch.Capture {
    try makeParents(io, dir, sub_path);
    return verified_fetch.fetchVerified(
        io,
        options.fetcher,
        location,
        dir,
        sub_path,
        arena,
        expectation,
        max_file_bytes,
    ) catch |err| switch (err) {
        error.FetchFailed => error.FetchFailed,
        error.OutOfMemory => error.OutOfMemory,
        else => error.IntegrityFailure,
    };
}

/// Fetch without an expectation, for `repomd.xml`, whose only pin is the
/// plan's own hash of it.
fn fetchInto(
    io: std.Io,
    arena: Allocator,
    options: Options,
    dir: std.Io.Dir,
    location: []const u8,
    sub_path: []const u8,
) WriteError![]u8 {
    try makeParents(io, dir, sub_path);
    options.fetcher.fetchFn(options.fetcher.context, location, dir, sub_path) catch {
        dir.deleteFile(io, sub_path) catch {};
        return error.FetchFailed;
    };
    return dir.readFileAlloc(io, sub_path, arena, .limited(max_file_bytes)) catch {
        dir.deleteFile(io, sub_path) catch {};
        return error.FetchFailed;
    };
}

fn writeStaged(
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
    bytes: []const u8,
) WriteError!void {
    try makeParents(io, dir, sub_path);
    dir.writeFile(io, .{ .sub_path = sub_path, .data = bytes }) catch
        return error.PublishFailed;
}

fn makeParents(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) WriteError!void {
    const parent = std.fs.path.dirname(sub_path) orelse return;
    dir.createDirPath(io, parent) catch return error.PublishFailed;
}

fn recordFile(
    arena: Allocator,
    files: *std.ArrayList(transaction_bundle.File),
    path: []const u8,
    bytes: []const u8,
) WriteError!void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{&digest}) catch unreachable;
    try files.append(arena, .{
        .path = try arena.dupe(u8, path),
        .sha256 = try arena.dupe(u8, hex[0..]),
        .size = bytes.len,
    });
}

fn sanitizeSources(arena: Allocator, sources: []const []const u8) WriteError![]const []const u8 {
    const out = try arena.alloc([]const u8, sources.len);
    for (sources, out) |source, *slot| {
        slot.* = uri_sanitize.recordableAlloc(arena, source) catch return error.OutOfMemory;
    }
    return out;
}

fn findRepository(inputs: []const RepositoryInput, id: []const u8) ?RepositoryInput {
    for (inputs) |input| {
        if (std.mem.eql(u8, input.id, id)) return input;
    }
    return null;
}

const testing = std.testing;

/// A transport backed by a directory tree, so an export can be driven
/// end-to-end with no server, no TLS, and no network timing.
const DirFetcher = struct {
    io: std.Io,
    root: std.Io.Dir,
    /// Locations that should fail rather than serve, to exercise the
    /// unreachable-repository path.
    unreachable_location: ?[]const u8 = null,

    fn fetcher(self: *DirFetcher) verified_fetch.Fetcher {
        return .{ .context = self, .fetchFn = fetch };
    }

    fn locator(self: *DirFetcher) Locator {
        return .{ .context = self, .locateFn = locate };
    }

    fn locate(
        _: *anyopaque,
        allocator: Allocator,
        repository_id: []const u8,
        href: []const u8,
    ) Allocator.Error![]u8 {
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ repository_id, href });
    }

    fn fetch(
        context: *anyopaque,
        location: []const u8,
        dir: std.Io.Dir,
        sub_path: []const u8,
    ) anyerror!void {
        const self: *DirFetcher = @ptrCast(@alignCast(context));
        if (self.unreachable_location) |bad| {
            if (std.mem.eql(u8, bad, location)) return error.ConnectionRefused;
        }
        var buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const bytes = try self.root.readFileAlloc(
            self.io,
            location,
            fba.allocator(),
            .limited(2048),
        );
        try dir.writeFile(self.io, .{ .sub_path = sub_path, .data = bytes });
    }
};

fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x}", .{&digest}) catch unreachable;
    return hex;
}

const repomd_body = "<repomd/>";
const primary_body = "<primary/>";
const rpm_body = "fake rpm bytes";
const key_body = "-----BEGIN PGP PUBLIC KEY BLOCK-----\n";
const plan_body = "{\"schema\":\"tdnf.transaction-plan/v1\"}";
const test_fingerprint = "abcdef0123456789abcdef0123456789abcdef01";

/// Builds a served tree plus a matching selection, so a test changes one fact
/// at a time instead of restating the whole export.
const Harness = struct {
    tmp: std.testing.TmpDir,
    root: std.Io.Dir,
    io: std.Io,
    arena: std.heap.ArenaAllocator,
    selection: bundle_selection.Selection,
    fetcher_state: DirFetcher,
    /// Held by the harness rather than built inline: an `Options` built from a
    /// runtime array literal would point at a dead stack temporary.
    keys_storage: [1]KeyInput = undefined,
    /// When set, attestation refuses instead of vouching.
    reject_signature: bool = false,

    fn attestor(self: *Harness) Attestor {
        return .{ .context = self, .attestFn = attest };
    }

    fn attest(
        context: *anyopaque,
        dir: std.Io.Dir,
        sub_path: []const u8,
        _: []const u8,
    ) anyerror!Attestation {
        const self: *Harness = @ptrCast(@alignCast(context));
        if (self.reject_signature) return error.BadSignature;
        // Attestation must see the staged file, so prove it is readable here.
        var buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        _ = try dir.readFileAlloc(self.io, sub_path, fba.allocator(), .limited(2048));
        return .{ .outcome = .verified, .key_fingerprint = test_fingerprint };
    }

    fn init(io: std.Io) !Harness {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        const path = try tmp.dir.realPathFileAlloc(io, ".", testing.allocator);
        defer testing.allocator.free(path);
        const root = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });

        try root.createDirPath(io, "base/repodata");
        try root.createDirPath(io, "base/Packages");
        try root.writeFile(io, .{ .sub_path = "base/repodata/repomd.xml", .data = repomd_body });
        try root.writeFile(io, .{ .sub_path = "base/repodata/primary.xml", .data = primary_body });
        try root.writeFile(io, .{ .sub_path = "base/Packages/a.rpm", .data = rpm_body });
        try root.writeFile(io, .{ .sub_path = "base.asc", .data = key_body });

        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        errdefer arena.deinit();
        const scratch = arena.allocator();

        const primary_hex = sha256Hex(primary_body);
        const rpm_hex = sha256Hex(rpm_body);
        const repomd_hex = sha256Hex(repomd_body);

        const metadata = try scratch.alloc(bundle_selection.MetadataItem, 1);
        metadata[0] = .{
            .repository_id = "base",
            .record_type = "primary",
            .href = "repodata/primary.xml",
            .xml_base = null,
            .checksum = .{ .kind = "sha256", .value = try scratch.dupe(u8, &primary_hex) },
            .size = primary_body.len,
            .open_checksum = null,
            .open_size = null,
            .path = "repos/base/repodata/primary.xml",
        };
        const packages = try scratch.alloc(bundle_selection.PackageItem, 1);
        packages[0] = .{
            .plan_package_id = "package-0",
            .repository_id = "base",
            .identity = .{
                .arch = "noarch",
                .epoch = null,
                .name = "a",
                .release = "1",
                .version = "1.0",
            },
            .checksum = .{ .kind = "sha256", .value = try scratch.dupe(u8, &rpm_hex) },
            .size = rpm_body.len,
            .href = "Packages/a.rpm",
            .xml_base = null,
            .path = "packages/base/Packages/a.rpm",
        };
        const repositories = try scratch.alloc(bundle_selection.RepositoryItem, 1);
        repositories[0] = .{
            .id = "base",
            .cost = 1000,
            .priority = 50,
            .revision = "rev-1",
            .snapshot_id = try scratch.dupe(u8, &primary_hex),
            .repomd_sha256 = try scratch.dupe(u8, &repomd_hex),
            .repomd_path = "repos/base/repodata/repomd.xml",
        };

        return .{
            .tmp = tmp,
            .root = root,
            .io = io,
            .arena = arena,
            .selection = .{
                .arena = std.heap.ArenaAllocator.init(testing.allocator),
                .packages = packages,
                .metadata = metadata,
                .repositories = repositories,
            },
            .fetcher_state = .{ .io = io, .root = root },
        };
    }

    fn deinit(self: *Harness) void {
        self.selection.arena.deinit();
        self.arena.deinit();
        self.root.close(self.io);
        self.tmp.cleanup();
    }

    fn keyPath(self: *Harness, allocator: Allocator) ![]u8 {
        const base = try self.tmp.dir.realPathFileAlloc(self.io, ".", allocator);
        defer allocator.free(base);
        return std.fmt.allocPrint(allocator, "{s}/base.asc", .{base});
    }

    fn destination(self: *Harness, allocator: Allocator) ![]u8 {
        const base = try self.tmp.dir.realPathFileAlloc(self.io, ".", allocator);
        defer allocator.free(base);
        return std.fmt.allocPrint(allocator, "{s}/bundle", .{base});
    }

    fn options(self: *Harness, key_path: []const u8, dest: []const u8) Options {
        self.keys_storage[0] = .{ .fingerprint = test_fingerprint, .source_path = key_path };
        return .{
            .selection = &self.selection,
            .plan_json = plan_body,
            .plan_digest = "a" ** 64,
            .plan_schema = transaction_plan.schema,
            .repositories = &.{.{
                .id = "base",
                .gpg_check = true,
                .sources = &.{"https://user:pw@mirror.invalid/base"},
            }},
            .attestor = self.attestor(),
            .keys = self.keys_storage[0..],
            .fetcher = self.fetcher_state.fetcher(),
            .locator = self.fetcher_state.locator(),
            .destination = dest,
        };
    }
};

test "a successful export publishes a complete, self-describing bundle" {
    const io = testing.io;
    var harness = try Harness.init(io);
    defer harness.deinit();

    const key_path = try harness.keyPath(testing.allocator);
    defer testing.allocator.free(key_path);
    const dest = try harness.destination(testing.allocator);
    defer testing.allocator.free(dest);

    const written = try write(testing.allocator, io, harness.options(key_path, dest));
    // plan, repomd, primary, rpm, key.
    try testing.expectEqual(@as(usize, 5), written.file_count);

    var bundle_dir = try std.Io.Dir.cwd().openDir(io, dest, .{ .iterate = true });
    defer bundle_dir.close(io);
    const manifest = try bundle_dir.readFileAlloc(
        io,
        "bundle.json",
        testing.allocator,
        .limited(1 << 20),
    );
    defer testing.allocator.free(manifest);

    // The manifest must round-trip through the same validator a consumer uses.
    const parsed = try transaction_bundle.parse(testing.allocator, manifest);
    defer parsed.destroy();
    try testing.expect(parsed.findFile("packages/base/Packages/a.rpm") != null);
    try testing.expect(parsed.findFile("repos/base/repodata/repomd.xml") != null);
    // bundle.json cannot list itself.
    try testing.expect(parsed.findFile("bundle.json") == null);
}

test "a configured credential never reaches the published manifest" {
    const io = testing.io;
    var harness = try Harness.init(io);
    defer harness.deinit();
    const key_path = try harness.keyPath(testing.allocator);
    defer testing.allocator.free(key_path);
    const dest = try harness.destination(testing.allocator);
    defer testing.allocator.free(dest);

    _ = try write(testing.allocator, io, harness.options(key_path, dest));

    var bundle_dir = try std.Io.Dir.cwd().openDir(io, dest, .{ .iterate = true });
    defer bundle_dir.close(io);
    const manifest = try bundle_dir.readFileAlloc(
        io,
        "bundle.json",
        testing.allocator,
        .limited(1 << 20),
    );
    defer testing.allocator.free(manifest);
    // A bundle is a shareable artifact; the password in the configured source
    // URL must be redacted rather than recorded.
    try testing.expect(std.mem.indexOf(u8, manifest, "pw@") == null);
    try testing.expect(std.mem.indexOf(u8, manifest, "mirror.invalid") != null);
}

test "a repomd that does not match the plan publishes nothing" {
    const io = testing.io;
    var harness = try Harness.init(io);
    defer harness.deinit();
    const key_path = try harness.keyPath(testing.allocator);
    defer testing.allocator.free(key_path);
    const dest = try harness.destination(testing.allocator);
    defer testing.allocator.free(dest);

    // The repository serves a different repomd than the one the plan pinned.
    try harness.root.writeFile(io, .{
        .sub_path = "base/repodata/repomd.xml",
        .data = "<repomd tampered=\"1\"/>",
    });

    try testing.expectError(
        error.IntegrityFailure,
        write(testing.allocator, io, harness.options(key_path, dest)),
    );
    // Nothing partial survives: the destination was never created.
    try testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, dest, .{}),
    );
}

test "a package whose bytes do not match its checksum publishes nothing" {
    const io = testing.io;
    var harness = try Harness.init(io);
    defer harness.deinit();
    const key_path = try harness.keyPath(testing.allocator);
    defer testing.allocator.free(key_path);
    const dest = try harness.destination(testing.allocator);
    defer testing.allocator.free(dest);

    try harness.root.writeFile(io, .{
        .sub_path = "base/Packages/a.rpm",
        .data = "substituted payload",
    });

    try testing.expectError(
        error.IntegrityFailure,
        write(testing.allocator, io, harness.options(key_path, dest)),
    );
    try testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, dest, .{}),
    );
}

test "an unreachable repository is reported as a fetch failure, not a lie" {
    const io = testing.io;
    var harness = try Harness.init(io);
    defer harness.deinit();
    const key_path = try harness.keyPath(testing.allocator);
    defer testing.allocator.free(key_path);
    const dest = try harness.destination(testing.allocator);
    defer testing.allocator.free(dest);

    harness.fetcher_state.unreachable_location = "base/Packages/a.rpm";
    try testing.expectError(
        error.FetchFailed,
        write(testing.allocator, io, harness.options(key_path, dest)),
    );
}

test "exporting onto an existing path is refused" {
    const io = testing.io;
    var harness = try Harness.init(io);
    defer harness.deinit();
    const key_path = try harness.keyPath(testing.allocator);
    defer testing.allocator.free(key_path);
    const dest = try harness.destination(testing.allocator);
    defer testing.allocator.free(dest);

    try std.Io.Dir.cwd().createDirPath(io, dest);
    try testing.expectError(
        error.PublishFailed,
        write(testing.allocator, io, harness.options(key_path, dest)),
    );
}

test "a package whose signature is refused is never published" {
    const io = testing.io;
    var harness = try Harness.init(io);
    defer harness.deinit();
    const key_path = try harness.keyPath(testing.allocator);
    defer testing.allocator.free(key_path);
    const dest = try harness.destination(testing.allocator);
    defer testing.allocator.free(dest);

    harness.reject_signature = true;
    // Distinct from an integrity failure: the bytes were exactly what the
    // metadata promised, and were still not acceptable to ship.
    try testing.expectError(
        error.SignatureRejected,
        write(testing.allocator, io, harness.options(key_path, dest)),
    );
    try testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, dest, .{}),
    );
}

test "an unreadable key blob fails the export" {
    const io = testing.io;
    var harness = try Harness.init(io);
    defer harness.deinit();
    const dest = try harness.destination(testing.allocator);
    defer testing.allocator.free(dest);

    try testing.expectError(
        error.KeyUnreadable,
        write(testing.allocator, io, harness.options("/nonexistent/key.asc", dest)),
    );
}
