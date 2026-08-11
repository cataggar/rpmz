//! The supported way to export a reproducible bundle for a resolved
//! transaction.
//!
//! `exportBundle` is a composition, not an implementation. Each rule it
//! depends on already lives somewhere it can be tested without a network:
//! what the bundle must contain is decided by `bundle_selection` from the plan
//! alone, where each file may land is decided by `bundle_paths` from a
//! declared href alone, and what is verified and in what order is decided by
//! `bundle_writer` against an injected transport. This file supplies the three
//! things only a real client can: a plan, a way to reach a repository, and a
//! verdict on a package's signature.
//!
//! The export is all-or-nothing. Every byte is staged and verified before the
//! destination exists, so a failure leaves nothing behind rather than leaving
//! a bundle that is almost right and cannot be told apart from one that is.
//!
//! A solver contradiction is not a failure. It returns the same owned plan
//! `resolvePlan` would, with its problems intact and no bundle written, so a
//! caller can report why the transaction is impossible without having to
//! resolve twice.

const std = @import("std");
const bundle_selection = @import("bundle_selection");
const bundle_writer = @import("bundle_writer");
const download = @import("client_download");
const resolver = @import("resolver.zig");
const transaction_bundle = @import("transaction_bundle");
const transaction_plan = @import("transaction_plan");
const uri_sanitize = @import("uri_sanitize");

const Allocator = std.mem.Allocator;

pub const ExportError = error{
    /// The plan selects a package that has no reproducible coordinates.
    CommandLinePackageUnsupported,
    /// The plan and the declared repositories disagree, or a declared href
    /// cannot be mapped to a safe path inside the bundle.
    PlanInconsistent,
    /// A repository could not be reached.
    FetchFailed,
    /// A repository served bytes other than the ones the plan promised.
    IntegrityFailure,
    /// A package's signature did not permit a bundle claim.
    SignatureRejected,
    /// A declared key blob could not be read.
    KeyUnreadable,
    /// The destination exists, or the bundle could not be published.
    PublishFailed,
    /// The exporter produced a manifest a consumer would reject.
    ManifestInvalid,
    OutOfMemory,
} || resolver.ResolveError;

/// A public key the caller is willing to have a bundle cite.
///
/// Keys are declared rather than discovered. A bundle that cited a key merely
/// because it happened to sit in the local rpmdb would attest to trust the
/// bundle does not carry.
pub const KeyInput = struct {
    /// Absolute path to an OpenPGP public key blob.
    path: []const u8,
};

pub const ExportInput = struct {
    /// The resolve to perform. Reused verbatim, so the plan in the bundle is
    /// the plan `tdnf plan` would print for the same inputs.
    resolve: resolver.ResolveInput,
    /// Where the finished bundle goes. Must not exist.
    destination: []const u8,
    /// Keys a package may be attested against.
    keys: []const KeyInput = &.{},
    /// When false, packages are recorded as `unsigned` and no signature is
    /// required. Mirrors the repository's own `gpgcheck`.
    gpg_check: bool = true,
};

pub const Exported = struct {
    allocator: Allocator,
    /// The resolved plan, owned by the caller.
    plan: *transaction_plan.Plan,
    /// Canonical bundle digest.
    bundle_digest: [64]u8,
    /// Canonical plan digest, as recorded in the manifest.
    plan_digest: [64]u8,
    /// Number of files the manifest describes.
    file_count: usize,

    pub fn deinit(self: *Exported) void {
        self.plan.destroy();
        self.* = undefined;
    }
};

pub const ExportResult = union(enum) {
    exported: Exported,
    /// The solver found the transaction impossible. No bundle was written and
    /// the caller owns the plan describing why.
    problems: *transaction_plan.Plan,

    pub fn deinit(self: *ExportResult) void {
        switch (self.*) {
            .exported => |*value| value.deinit(),
            .problems => |plan| plan.destroy(),
        }
        self.* = undefined;
    }
};

/// Resolve, fetch, verify, and publish.
pub fn exportBundle(
    allocator: Allocator,
    io: std.Io,
    input: ExportInput,
) ExportError!ExportResult {
    const plan = try resolver.resolvePlan(allocator, io, input.resolve);
    errdefer plan.destroy();

    if (plan.model().environment.resolution_status == .problems) {
        return .{ .problems = plan };
    }

    var selection = bundle_selection.select(allocator, plan.model()) catch |err|
        return mapSelectError(err);
    defer selection.deinit();

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const plan_json = try plan.canonicalJsonAlloc(arena);
    const plan_digest = try plan.digest(arena);

    var transport: Transport = .{ .io = io, .allocator = arena, .input = input };
    var attestor_state: Attestor = .{
        .allocator = arena,
        .io = io,
        .gpg_check = input.gpg_check,
        .keys = &.{},
    };
    attestor_state.keys = try loadKeys(arena, io, input.keys);

    const repositories = try describeRepositories(arena, input.resolve.repositories);

    const written = bundle_writer.write(allocator, io, .{
        .selection = &selection,
        .plan_json = plan_json,
        .plan_digest = plan_digest[0..],
        .plan_schema = transaction_plan.schema,
        .repositories = repositories,
        .attestor = attestor_state.interface(),
        .keys = attestor_state.manifestKeys(),
        .fetcher = transport.fetcher(),
        .locator = transport.locator(),
        .destination = input.destination,
    }) catch |err| return mapWriteError(err);

    return .{ .exported = .{
        .allocator = allocator,
        .plan = plan,
        .bundle_digest = written.digest,
        .plan_digest = plan_digest,
        .file_count = written.file_count,
    } };
}

fn mapSelectError(err: bundle_selection.SelectError) ExportError {
    return switch (err) {
        error.CommandLinePackageUnsupported => error.CommandLinePackageUnsupported,
        error.OutOfMemory => error.OutOfMemory,
        // A plan whose repositories cannot be pinned, whose actions name
        // unknown packages, or whose hrefs cannot be mapped is not something
        // the exporter can repair; reporting one cause keeps the failure
        // honest.
        else => error.PlanInconsistent,
    };
}

fn mapWriteError(err: bundle_writer.WriteError) ExportError {
    return switch (err) {
        error.FetchFailed => error.FetchFailed,
        error.IntegrityFailure => error.IntegrityFailure,
        error.SignatureRejected => error.SignatureRejected,
        error.KeyUnreadable => error.KeyUnreadable,
        error.PublishFailed => error.PublishFailed,
        error.ManifestInvalid => error.ManifestInvalid,
        error.OutOfMemory => error.OutOfMemory,
    };
}

/// Records what the caller declared, not what answered.
///
/// Recording the mirror that responded would make two identical exports
/// produce different bundle digests, which is exactly the property this
/// feature exists to provide.
fn describeRepositories(
    arena: Allocator,
    repositories: []const resolver.Repository,
) Allocator.Error![]const bundle_writer.RepositoryInput {
    const out = try arena.alloc(bundle_writer.RepositoryInput, repositories.len);
    var count: usize = 0;
    for (repositories) |repository| {
        const sources: []const []const u8 = switch (repository.metadata) {
            .remote => |remote| remote.base_urls,
            // A local snapshot has no URL to record. The bundle still carries
            // its files; it simply cannot claim a source it never had.
            .local_snapshot => &.{},
        };
        out[count] = .{
            .id = repository.id,
            .gpg_check = repository.gpg_check,
            .sources = sources,
        };
        count += 1;
    }
    return out[0..count];
}

/// Reaches a repository the same way the resolve did.
const Transport = struct {
    io: std.Io,
    allocator: Allocator,
    input: ExportInput,

    fn fetcher(self: *Transport) @TypeOf(@as(bundle_writer.Options, undefined).fetcher) {
        return .{ .context = self, .fetchFn = fetch };
    }

    fn locator(self: *Transport) bundle_writer.Locator {
        return .{ .context = self, .locateFn = locate };
    }

    fn locate(
        context: *anyopaque,
        allocator: Allocator,
        repository_id: []const u8,
        href: []const u8,
    ) Allocator.Error![]u8 {
        const self: *Transport = @ptrCast(@alignCast(context));
        for (self.input.resolve.repositories) |repository| {
            if (!std.mem.eql(u8, repository.id, repository_id)) continue;
            switch (repository.metadata) {
                .remote => |remote| {
                    if (remote.base_urls.len == 0) break;
                    // An absolute href overrides the base entirely: that is
                    // what the metadata means, and rewriting it would fetch
                    // something other than what the plan recorded.
                    if (isAbsolute(href)) return allocator.dupe(u8, href);
                    return joinUrl(allocator, remote.base_urls[0], href);
                },
                .local_snapshot => |root| {
                    if (isAbsolute(href)) return allocator.dupe(u8, href);
                    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, href });
                },
            }
        }
        return allocator.dupe(u8, href);
    }

    fn fetch(
        context: *anyopaque,
        location: []const u8,
        dir: std.Io.Dir,
        sub_path: []const u8,
    ) anyerror!void {
        const self: *Transport = @ptrCast(@alignCast(context));
        const io = self.io;

        var file = try dir.createFile(io, sub_path, .{ .truncate = true });
        defer file.close(io);

        if (std.mem.startsWith(u8, location, "/")) {
            const bytes = try std.Io.Dir.cwd().readFileAlloc(
                io,
                location,
                self.allocator,
                .limited(bundle_writer.max_file_bytes),
            );
            defer self.allocator.free(bytes);
            try file.writeStreamingAll(io, bytes);
            return;
        }

        const url = try self.allocator.dupeZ(u8, location);
        defer self.allocator.free(url);
        const status = try download.client_download_to_fd(
            self.allocator,
            io,
            .{ .url = url },
            file.handle,
        );
        if (status != 0 and (status < 200 or status >= 300)) return error.HttpStatus;
    }
};

fn isAbsolute(href: []const u8) bool {
    return std.mem.indexOf(u8, href, "://") != null or std.mem.startsWith(u8, href, "/");
}

fn joinUrl(allocator: Allocator, base: []const u8, href: []const u8) Allocator.Error![]u8 {
    const trimmed = std.mem.trimEnd(u8, base, "/");
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ trimmed, href });
}

extern fn tdnf_rpm_file_open(path: [*:0]const u8) callconv(.c) ?*anyopaque;
extern fn tdnf_rpm_file_close(handle: ?*anyopaque) callconv(.c) void;
extern fn tdnf_rpm_file_verify_signatures_keys(
    handle: ?*anyopaque,
    key_blobs: ?[*]const ?*const anyopaque,
    key_lens: ?[*]const usize,
    key_count: usize,
    outcome_out: ?*i32,
    signer_index_out: ?*isize,
    signer_fingerprint_out: ?[*]u8,
    signer_fingerprint_len_out: ?*usize,
) callconv(.c) i32;

const LoadedKey = struct {
    path: []const u8,
    blob: []const u8,
    /// Filled in once a package is attested against this key.
    fingerprint: ?[]const u8 = null,
};

fn loadKeys(
    arena: Allocator,
    io: std.Io,
    inputs: []const KeyInput,
) ExportError![]LoadedKey {
    const out = try arena.alloc(LoadedKey, inputs.len);
    for (inputs, out) |input, *slot| {
        const blob = std.Io.Dir.cwd().readFileAlloc(
            io,
            input.path,
            arena,
            .limited(1 << 24),
        ) catch return error.KeyUnreadable;
        slot.* = .{ .path = input.path, .blob = blob };
    }
    return out;
}

/// Decides what the bundle may claim about a staged package.
///
/// It verifies against the declared keys **and nothing else**. The `_config`
/// entry point folds in the install root's rpmdb keyring, whose contents are
/// ambient state: a package signed by a key that merely happens to be
/// installed locally has not been vouched for by anything the bundle carries,
/// so a bundle must not cite it.
const Attestor = struct {
    allocator: Allocator,
    io: std.Io,
    gpg_check: bool,
    keys: []LoadedKey,

    fn interface(self: *Attestor) bundle_writer.Attestor {
        return .{ .context = self, .attestFn = attest };
    }

    /// Only keys that actually validated something are recorded, so a bundle
    /// never carries a key it cannot justify.
    fn manifestKeys(self: *Attestor) []const bundle_writer.KeyInput {
        var count: usize = 0;
        for (self.keys) |key| {
            if (key.fingerprint != null) count += 1;
        }
        const out = self.allocator.alloc(bundle_writer.KeyInput, count) catch return &.{};
        var index: usize = 0;
        for (self.keys) |key| {
            const fingerprint = key.fingerprint orelse continue;
            out[index] = .{ .fingerprint = fingerprint, .source_path = key.path };
            index += 1;
        }
        return out;
    }

    fn attest(
        context: *anyopaque,
        dir: std.Io.Dir,
        sub_path: []const u8,
        _: []const u8,
    ) anyerror!bundle_writer.Attestation {
        const self: *Attestor = @ptrCast(@alignCast(context));
        if (!self.gpg_check) return .{ .outcome = .unsigned };

        const path = try dirFilePathAlloc(self.allocator, self.io, dir, sub_path);
        defer self.allocator.free(path);

        const handle = tdnf_rpm_file_open(path.ptr) orelse return error.PackageUnreadable;
        defer tdnf_rpm_file_close(handle);

        var blobs = try self.allocator.alloc(?*const anyopaque, self.keys.len);
        defer self.allocator.free(blobs);
        var lens = try self.allocator.alloc(usize, self.keys.len);
        defer self.allocator.free(lens);
        for (self.keys, 0..) |key, index| {
            blobs[index] = key.blob.ptr;
            lens[index] = key.blob.len;
        }

        var outcome: i32 = -1;
        var signer_index: isize = -1;
        var fingerprint_bytes: [32]u8 = undefined;
        var fingerprint_len: usize = 0;
        if (tdnf_rpm_file_verify_signatures_keys(
            handle,
            blobs.ptr,
            lens.ptr,
            blobs.len,
            &outcome,
            &signer_index,
            &fingerprint_bytes,
            &fingerprint_len,
        ) != 0) return error.VerificationFailed;

        // Anything other than a clean pass by exactly one identified key is a
        // refusal. A bundle records which key vouched for a package or makes
        // no claim at all; there is no partial credit.
        if (outcome != 0) return error.BadSignature;
        if (signer_index < 0 or fingerprint_len == 0) return error.UnidentifiedSigner;

        const hex = try std.fmt.allocPrint(
            self.allocator,
            "{x}",
            .{fingerprint_bytes[0..fingerprint_len]},
        );
        self.keys[@intCast(signer_index)].fingerprint = hex;
        return .{ .outcome = .verified, .key_fingerprint = hex };
    }
};

/// Resolves a staged file to an absolute path, because the verifier's ABI
/// takes a pathname rather than a descriptor.
fn dirFilePathAlloc(
    allocator: Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
) ![:0]u8 {
    const base = try dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(base);
    return std.fmt.allocPrintSentinel(allocator, "{s}/{s}", .{ base, sub_path }, 0);
}

test {
    // Nothing in the product calls `exportBundle`, so without this the
    // compiler never analyzes the bodies in this file and a type error here
    // ships as a green build. The acceptance tests exercise the behaviour;
    // this exists so a mistake is caught by `zig build test` rather than by
    // the first caller.
    @import("std").testing.refAllDecls(@This());
}
