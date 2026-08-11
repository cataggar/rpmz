//! Versioned, canonical manifest for a reproducible transaction input closure.
//!
//! A bundle is the immutable set of bytes required to reapply one resolved
//! transaction without a repository or a network: the canonical plan, every
//! repository metadata object the solve read, every RPM the plan installs, and
//! the trust material that validated them.
//!
//! This module is the schema only. It owns validation, canonical ordering,
//! serialization, and identity; it performs no I/O and never touches a network
//! or a package. The exporter and the reader are layered on top of it.
//!
//! Identity mirrors `transaction_plan` exactly: `digest` hashes
//! `schema ++ NUL ++ canonical document without the digest`, and
//! `canonicalJsonAlloc` then emits that same document *with* the digest
//! embedded. A bundle therefore cannot list a hash of its own manifest, which
//! is why `bundle.json` carries no entry in its own file table. Every other
//! bundled file, `plan.json` included, is an ordinary entry.

const std = @import("std");
const Allocator = std.mem.Allocator;

const canonical_json = @import("canonical_json");
const secret_shape = @import("secret_shape");
const transaction_plan = @import("transaction_plan");

pub const schema = "tdnf.transaction-bundle/v1";
const digest_prefix = schema ++ "\x00";

/// The manifest's own filename. It is excluded from the file table by
/// construction, not by convention.
pub const manifest_name = "bundle.json";
/// Where the canonical plan is always written.
pub const plan_name = "plan.json";

pub const repositories_prefix = "repos/";
pub const packages_prefix = "packages/";
pub const keys_prefix = "keys/";

pub const ValidationError = error{
    DuplicateEntry,
    EmptyId,
    InvalidChecksum,
    InvalidDigest,
    InvalidPath,
    InvalidSchema,
    InvalidSignature,
    InvalidSource,
    InvalidString,
    MisplacedFile,
    OutOfMemory,
    SecretShapedValue,
    UnknownReference,
    UntrackedFile,
};

pub const InitError = ValidationError || Allocator.Error;
pub const CanonicalError = Allocator.Error;

/// What verification concluded about a package's signature. `unsigned` is a
/// distinct outcome from a failure: it is only reachable when the repository
/// does not require a signature, and it is recorded so a consumer can tell
/// "nobody signed this" from "somebody signed this and we checked".
pub const SignatureOutcome = enum {
    unsigned,
    verified,

    fn text(self: SignatureOutcome) []const u8 {
        return switch (self) {
            .unsigned => "unsigned",
            .verified => "verified",
        };
    }
};

pub const Signature = struct {
    outcome: SignatureOutcome,
    /// The full fingerprint of the key that validated this package. Required
    /// when `outcome` is `verified` and forbidden otherwise, so a bundle can
    /// never claim verification without naming the key that performed it.
    key_fingerprint: ?[]const u8,
};

/// One byte-exact file in the bundle. `sha256` is the bundle's own integrity
/// domain and is recorded for every file regardless of what checksum kind the
/// originating repository happened to declare.
pub const File = struct {
    path: []const u8,
    sha256: []const u8,
    size: u64,
};

/// The plan this bundle was built for. `digest` is the plan's own identity,
/// which is not the same value as the `plan.json` file hash; both are recorded
/// and a reader checks both.
pub const PlanReference = struct {
    digest: []const u8,
    path: []const u8,
    schema: []const u8,
};

/// A repository as the bundle records it. `sources` is the caller's *declared*
/// source set after sanitization, never the mirror that happened to answer:
/// recording the responding mirror would make two identical exports produce
/// different digests.
pub const Repository = struct {
    cost: u32,
    gpg_check: bool,
    id: []const u8,
    priority: i32,
    repomd_sha256: []const u8,
    revision: ?[]const u8,
    snapshot_id: []const u8,
    sources: []const []const u8,
};

/// One RPM in the closure. The declared coordinates are kept verbatim so a
/// consumer can check the mapping to `path` rather than recompute it, and so a
/// repository can never steer a write through `xml_base` or an absolute href.
pub const Package = struct {
    checksum: transaction_plan.Checksum,
    href: []const u8,
    identity: transaction_plan.PackageIdentity,
    path: []const u8,
    /// The `package-N` reference this package has in the canonical plan.
    plan_package_id: []const u8,
    repository_id: []const u8,
    signature: Signature,
    size: ?u64,
    xml_base: ?[]const u8,
};

pub const Key = struct {
    fingerprint: []const u8,
    path: []const u8,
};

pub const Data = struct {
    files: []const File,
    keys: []const Key,
    packages: []const Package,
    plan: PlanReference,
    repositories: []const Repository,
};

/// Owns one immutable snapshot of a validated bundle manifest.
pub const Bundle = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    data: Data,

    pub fn create(allocator: Allocator, input: Data) InitError!*Bundle {
        try validate(input);

        const self = try allocator.create(Bundle);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .data = undefined,
        };
        errdefer self.arena.deinit();
        self.data = try cloneData(self.arena.allocator(), input);
        return self;
    }

    pub fn destroy(self: *Bundle) void {
        const allocator = self.allocator;
        self.arena.deinit();
        allocator.destroy(self);
    }

    pub fn model(self: *const Bundle) *const Data {
        return &self.data;
    }

    pub fn digest(self: *const Bundle, allocator: Allocator) CanonicalError![64]u8 {
        const document = try canonicalDocument(allocator, &self.data, null);
        defer allocator.free(document);
        var bytes: [32]u8 = undefined;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(digest_prefix);
        hasher.update(document);
        hasher.final(&bytes);
        return lowerHex(bytes);
    }

    pub fn canonicalJsonAlloc(self: *const Bundle, allocator: Allocator) CanonicalError![]u8 {
        const value = try self.digest(allocator);
        return canonicalDocument(allocator, &self.data, &value);
    }

    /// Looks up a file table entry by exact bundle-relative path.
    pub fn findFile(self: *const Bundle, path: []const u8) ?*const File {
        for (self.data.files) |*file| {
            if (std.mem.eql(u8, file.path, path)) return file;
        }
        return null;
    }
};

pub fn validate(data: Data) ValidationError!void {
    try validatePlanReference(data.plan);
    try validateRepositories(data.repositories);
    try validateKeys(data.keys);
    try validatePackages(data.packages, data.repositories, data.keys);
    try validateFiles(data);
}

fn validatePlanReference(plan: PlanReference) ValidationError!void {
    if (!std.mem.eql(u8, plan.schema, transaction_plan.schema)) {
        return error.InvalidSchema;
    }
    if (!std.mem.eql(u8, plan.path, plan_name)) return error.InvalidPath;
    try validateSha256(plan.digest);
}

fn validateRepositories(repositories: []const Repository) ValidationError!void {
    for (repositories, 0..) |repository, index| {
        transaction_plan.validateRepositoryId(repository.id) catch |err| return switch (err) {
            error.EmptyId => error.EmptyId,
            // The plan's identifier rules are a superset of what a bundle path
            // can express; anything else it rejects is a malformed string.
            else => error.InvalidString,
        };
        if (!isSafeComponent(repository.id)) return error.InvalidPath;
        for (repositories[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.id, repository.id)) return error.DuplicateEntry;
        }
        try validateSha256(repository.repomd_sha256);
        try validateOpaque(repository.snapshot_id);
        if (repository.snapshot_id.len == 0) return error.EmptyId;
        if (repository.revision) |revision| try validateOpaque(revision);
        if (repository.sources.len == 0) return error.InvalidSource;
        for (repository.sources, 0..) |source, source_index| {
            try validateSource(source);
            for (repository.sources[0..source_index]) |earlier| {
                if (std.mem.eql(u8, earlier, source)) return error.DuplicateEntry;
            }
        }
    }
}

/// A sanitized source has already had userinfo, query, and fragment removed.
/// Rejecting them here means a sanitizer regression fails closed at model
/// construction rather than publishing a credential.
fn validateSource(value: []const u8) ValidationError!void {
    if (value.len == 0) return error.InvalidSource;
    try validateOpaque(value);
    for (value) |byte| {
        if (byte == '@' or byte == '?' or byte == '#') return error.InvalidSource;
    }
    if (secret_shape.containsSecretShape(value)) return error.SecretShapedValue;
    const scheme_end = std.mem.indexOf(u8, value, "://") orelse return;
    if (secret_shape.decodedUriHasSecretShape(value[scheme_end + 3 ..], null)) {
        return error.SecretShapedValue;
    }
}

fn validateKeys(keys: []const Key) ValidationError!void {
    for (keys, 0..) |key, index| {
        try validateFingerprint(key.fingerprint);
        for (keys[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.fingerprint, key.fingerprint)) {
                return error.DuplicateEntry;
            }
            if (std.mem.eql(u8, earlier.path, key.path)) return error.DuplicateEntry;
        }
        try validateBundlePath(key.path);
        if (!std.mem.startsWith(u8, key.path, keys_prefix)) return error.MisplacedFile;
    }
}

fn validatePackages(
    packages: []const Package,
    repositories: []const Repository,
    keys: []const Key,
) ValidationError!void {
    for (packages, 0..) |package, index| {
        if (findRepository(repositories, package.repository_id) == null) {
            return error.UnknownReference;
        }
        try validateOpaque(package.plan_package_id);
        if (package.plan_package_id.len == 0) return error.EmptyId;
        try validateIdentity(package.identity);
        try validateChecksumText(package.checksum.kind);
        try validateChecksumText(package.checksum.value);
        try validateUriText(package.href);
        if (package.xml_base) |xml_base| try validateUriText(xml_base);

        try validateBundlePath(package.path);
        const expected_prefix = packages_prefix;
        if (!std.mem.startsWith(u8, package.path, expected_prefix)) {
            return error.MisplacedFile;
        }
        // The path must live under this package's own repository, so moving a
        // file between repository trees cannot go unnoticed.
        const remainder = package.path[expected_prefix.len..];
        if (!std.mem.startsWith(u8, remainder, package.repository_id) or
            remainder.len <= package.repository_id.len or
            remainder[package.repository_id.len] != '/')
        {
            return error.MisplacedFile;
        }

        try validateSignature(package.signature, keys);

        for (packages[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.path, package.path)) return error.DuplicateEntry;
            if (std.mem.eql(u8, earlier.plan_package_id, package.plan_package_id)) {
                return error.DuplicateEntry;
            }
        }
    }
}

fn validateSignature(signature: Signature, keys: []const Key) ValidationError!void {
    switch (signature.outcome) {
        .verified => {
            const fingerprint = signature.key_fingerprint orelse
                return error.InvalidSignature;
            try validateFingerprint(fingerprint);
            for (keys) |key| {
                if (std.mem.eql(u8, key.fingerprint, fingerprint)) return;
            }
            return error.UnknownReference;
        },
        .unsigned => {
            if (signature.key_fingerprint != null) return error.InvalidSignature;
        },
    }
}

/// The file table must describe the bundle exactly: every file the manifest
/// references elsewhere must appear, nothing may appear twice, and the
/// manifest may not describe itself.
fn validateFiles(data: Data) ValidationError!void {
    for (data.files, 0..) |file, index| {
        try validateBundlePath(file.path);
        if (std.mem.eql(u8, file.path, manifest_name)) return error.UntrackedFile;
        try validateSha256(file.sha256);
        for (data.files[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.path, file.path)) return error.DuplicateEntry;
        }
    }

    if (findFile(data.files, data.plan.path) == null) return error.UntrackedFile;
    for (data.packages) |package| {
        if (findFile(data.files, package.path) == null) return error.UntrackedFile;
    }
    for (data.keys) |key| {
        if (findFile(data.files, key.path) == null) return error.UntrackedFile;
    }

    // Anything under a structured prefix must be accounted for by a package,
    // a key, or a repository tree; a stray entry means the manifest and the
    // tree disagree about what the closure is.
    for (data.files) |file| {
        if (std.mem.startsWith(u8, file.path, packages_prefix)) {
            if (findPackage(data.packages, file.path) == null) return error.UntrackedFile;
        } else if (std.mem.startsWith(u8, file.path, keys_prefix)) {
            if (findKey(data.keys, file.path) == null) return error.UntrackedFile;
        } else if (std.mem.startsWith(u8, file.path, repositories_prefix)) {
            const remainder = file.path[repositories_prefix.len..];
            const slash = std.mem.indexOfScalar(u8, remainder, '/') orelse
                return error.MisplacedFile;
            if (findRepository(data.repositories, remainder[0..slash]) == null) {
                return error.UnknownReference;
            }
        } else if (!std.mem.eql(u8, file.path, data.plan.path)) {
            return error.MisplacedFile;
        }
    }
}

fn findFile(files: []const File, path: []const u8) ?*const File {
    for (files) |*file| if (std.mem.eql(u8, file.path, path)) return file;
    return null;
}

fn findPackage(packages: []const Package, path: []const u8) ?*const Package {
    for (packages) |*package| if (std.mem.eql(u8, package.path, path)) return package;
    return null;
}

fn findKey(keys: []const Key, path: []const u8) ?*const Key {
    for (keys) |*key| if (std.mem.eql(u8, key.path, path)) return key;
    return null;
}

fn findRepository(repositories: []const Repository, id: []const u8) ?*const Repository {
    for (repositories) |*repository| {
        if (std.mem.eql(u8, repository.id, id)) return repository;
    }
    return null;
}

fn validateIdentity(identity: transaction_plan.PackageIdentity) ValidationError!void {
    try validateOpaque(identity.arch);
    try validateOpaque(identity.name);
    try validateOpaque(identity.release);
    try validateOpaque(identity.version);
    if (identity.arch.len == 0 or identity.name.len == 0 or
        identity.release.len == 0 or identity.version.len == 0)
    {
        return error.InvalidString;
    }
}

fn validateFingerprint(value: []const u8) ValidationError!void {
    if (value.len == 0 or value.len > 64) return error.InvalidSignature;
    for (value) |byte| {
        if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) {
            return error.InvalidSignature;
        }
    }
}

fn validateSha256(value: []const u8) ValidationError!void {
    if (value.len != 64) return error.InvalidChecksum;
    for (value) |byte| {
        if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) {
            return error.InvalidChecksum;
        }
    }
}

fn validateChecksumText(value: []const u8) ValidationError!void {
    if (value.len == 0 or value.len > 4096) return error.InvalidChecksum;
    try validateOpaque(value);
}

fn validateUriText(value: []const u8) ValidationError!void {
    if (value.len == 0) return error.InvalidPath;
    try validateOpaque(value);
    if (secret_shape.containsSecretShape(value)) return error.SecretShapedValue;
}

/// Text that is stored verbatim: printable, UTF-8, no control characters, and
/// no embedded NUL.
fn validateOpaque(value: []const u8) ValidationError!void {
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidString;
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f) return error.InvalidString;
    }
}

/// A bundle-relative path. This is the single chokepoint that keeps a hostile
/// repository from writing outside the bundle, so it rejects absolute paths,
/// traversal, empty and dot segments, backslashes, and Windows drive letters
/// rather than trying to normalize them.
fn validateBundlePath(value: []const u8) ValidationError!void {
    if (value.len == 0 or value.len > 4096) return error.InvalidPath;
    try validateOpaque(value);
    if (value[0] == '/' or value[value.len - 1] == '/') return error.InvalidPath;
    if (std.mem.indexOfScalar(u8, value, '\\') != null) return error.InvalidPath;
    if (secret_shape.containsSecretShape(value)) return error.SecretShapedValue;

    var segments = std.mem.splitScalar(u8, value, '/');
    while (segments.next()) |segment| {
        if (!isSafeComponent(segment)) return error.InvalidPath;
    }
}

fn isSafeComponent(value: []const u8) bool {
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, ".") or std.mem.eql(u8, value, "..")) return false;
    if (std.mem.indexOfScalar(u8, value, '/') != null) return false;
    if (std.mem.indexOfScalar(u8, value, ':') != null) return false;
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f) return false;
    }
    return true;
}

fn lowerHex(bytes: [32]u8) [64]u8 {
    const alphabet = "0123456789abcdef";
    var result: [64]u8 = undefined;
    for (bytes, 0..) |byte, index| {
        result[index * 2] = alphabet[byte >> 4];
        result[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return result;
}

fn cloneData(arena: Allocator, input: Data) Allocator.Error!Data {
    return .{
        .files = try cloneFiles(arena, input.files),
        .keys = try cloneKeys(arena, input.keys),
        .packages = try clonePackages(arena, input.packages),
        .plan = .{
            .digest = try arena.dupe(u8, input.plan.digest),
            .path = try arena.dupe(u8, input.plan.path),
            .schema = try arena.dupe(u8, input.plan.schema),
        },
        .repositories = try cloneRepositories(arena, input.repositories),
    };
}

fn cloneFiles(arena: Allocator, input: []const File) Allocator.Error![]const File {
    const files = try arena.alloc(File, input.len);
    for (input, 0..) |file, index| {
        files[index] = .{
            .path = try arena.dupe(u8, file.path),
            .sha256 = try arena.dupe(u8, file.sha256),
            .size = file.size,
        };
    }
    std.mem.sort(File, files, {}, lessFile);
    return files;
}

fn cloneKeys(arena: Allocator, input: []const Key) Allocator.Error![]const Key {
    const keys = try arena.alloc(Key, input.len);
    for (input, 0..) |key, index| {
        keys[index] = .{
            .fingerprint = try arena.dupe(u8, key.fingerprint),
            .path = try arena.dupe(u8, key.path),
        };
    }
    std.mem.sort(Key, keys, {}, lessKey);
    return keys;
}

fn clonePackages(arena: Allocator, input: []const Package) Allocator.Error![]const Package {
    const packages = try arena.alloc(Package, input.len);
    for (input, 0..) |package, index| {
        packages[index] = .{
            .checksum = .{
                .kind = try arena.dupe(u8, package.checksum.kind),
                .is_pkgid = package.checksum.is_pkgid,
                .value = try arena.dupe(u8, package.checksum.value),
            },
            .href = try arena.dupe(u8, package.href),
            .identity = .{
                .arch = try arena.dupe(u8, package.identity.arch),
                .epoch = package.identity.epoch,
                .name = try arena.dupe(u8, package.identity.name),
                .release = try arena.dupe(u8, package.identity.release),
                .version = try arena.dupe(u8, package.identity.version),
            },
            .path = try arena.dupe(u8, package.path),
            .plan_package_id = try arena.dupe(u8, package.plan_package_id),
            .repository_id = try arena.dupe(u8, package.repository_id),
            .signature = .{
                .outcome = package.signature.outcome,
                .key_fingerprint = if (package.signature.key_fingerprint) |value|
                    try arena.dupe(u8, value)
                else
                    null,
            },
            .size = package.size,
            .xml_base = if (package.xml_base) |value|
                try arena.dupe(u8, value)
            else
                null,
        };
    }
    std.mem.sort(Package, packages, {}, lessPackage);
    return packages;
}

fn cloneRepositories(
    arena: Allocator,
    input: []const Repository,
) Allocator.Error![]const Repository {
    const repositories = try arena.alloc(Repository, input.len);
    for (input, 0..) |repository, index| {
        const sources = try arena.alloc([]const u8, repository.sources.len);
        for (repository.sources, 0..) |source, source_index| {
            sources[source_index] = try arena.dupe(u8, source);
        }
        repositories[index] = .{
            .cost = repository.cost,
            .gpg_check = repository.gpg_check,
            .id = try arena.dupe(u8, repository.id),
            .priority = repository.priority,
            .repomd_sha256 = try arena.dupe(u8, repository.repomd_sha256),
            .revision = if (repository.revision) |value|
                try arena.dupe(u8, value)
            else
                null,
            .snapshot_id = try arena.dupe(u8, repository.snapshot_id),
            // Source order is the caller's declared preference order and is
            // meaningful, so it is preserved rather than sorted.
            .sources = sources,
        };
    }
    std.mem.sort(Repository, repositories, {}, lessRepository);
    return repositories;
}

fn lessFile(_: void, left: File, right: File) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

fn lessKey(_: void, left: Key, right: Key) bool {
    return std.mem.lessThan(u8, left.fingerprint, right.fingerprint);
}

fn lessRepository(_: void, left: Repository, right: Repository) bool {
    return std.mem.lessThan(u8, left.id, right.id);
}

/// Packages are ordered by their bundle path, which is unique by validation
/// and already scoped by repository. Using the path rather than EVR keeps the
/// manifest ordering a pure function of the file layout.
fn lessPackage(_: void, left: Package, right: Package) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

fn canonicalDocument(
    allocator: Allocator,
    data: *const Data,
    digest_value: ?*const [64]u8,
) Allocator.Error![]u8 {
    var writer = canonical_json.Writer.init(allocator);
    errdefer writer.deinit();

    try writer.append("{");
    if (digest_value) |value| {
        try writer.append("\"digest\":{\"algorithm\":\"sha256\",\"domain\":");
        try writer.writeString(schema);
        try writer.append(",\"value\":");
        try writer.writeString(value);
        try writer.append("},");
    }

    try writer.append("\"files\":");
    try writeFiles(&writer, data.files);
    try writer.append(",\"keys\":");
    try writeKeys(&writer, data.keys);
    try writer.append(",\"packages\":");
    try writePackages(&writer, data.packages);
    try writer.append(",\"plan\":");
    try writePlanReference(&writer, data.plan);
    try writer.append(",\"repositories\":");
    try writeRepositories(&writer, data.repositories);
    try writer.append(",\"schema\":");
    try writer.writeString(schema);
    try writer.append("}");
    return writer.finish();
}

fn writeFiles(writer: *canonical_json.Writer, files: []const File) Allocator.Error!void {
    try writer.appendByte('[');
    for (files, 0..) |file, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"path\":");
        try writer.writeString(file.path);
        try writer.append(",\"sha256\":");
        try writer.writeString(file.sha256);
        try writer.append(",\"size\":");
        try writer.writeUint(file.size);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeKeys(writer: *canonical_json.Writer, keys: []const Key) Allocator.Error!void {
    try writer.appendByte('[');
    for (keys, 0..) |key, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"fingerprint\":");
        try writer.writeString(key.fingerprint);
        try writer.append(",\"path\":");
        try writer.writeString(key.path);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writePackages(
    writer: *canonical_json.Writer,
    packages: []const Package,
) Allocator.Error!void {
    try writer.appendByte('[');
    for (packages, 0..) |package, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"checksum\":{\"is_pkgid\":");
        try writer.writeBool(package.checksum.is_pkgid);
        try writer.append(",\"kind\":");
        try writer.writeString(package.checksum.kind);
        try writer.append(",\"value\":");
        try writer.writeString(package.checksum.value);
        try writer.append("},\"href\":");
        try writer.writeString(package.href);
        try writer.append(",\"identity\":");
        try writeIdentity(writer, package.identity);
        try writer.append(",\"path\":");
        try writer.writeString(package.path);
        try writer.append(",\"plan_package_id\":");
        try writer.writeString(package.plan_package_id);
        try writer.append(",\"repository_id\":");
        try writer.writeString(package.repository_id);
        try writer.append(",\"signature\":{\"key_fingerprint\":");
        try writer.writeOptionalString(package.signature.key_fingerprint);
        try writer.append(",\"outcome\":");
        try writer.writeString(package.signature.outcome.text());
        try writer.append("},\"size\":");
        if (package.size) |size| try writer.writeUint(size) else try writer.append("null");
        try writer.append(",\"xml_base\":");
        try writer.writeOptionalString(package.xml_base);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeIdentity(
    writer: *canonical_json.Writer,
    identity: transaction_plan.PackageIdentity,
) Allocator.Error!void {
    try writer.append("{\"arch\":");
    try writer.writeString(identity.arch);
    try writer.append(",\"epoch\":");
    if (identity.epoch) |epoch| try writer.writeUint(epoch) else try writer.append("null");
    try writer.append(",\"name\":");
    try writer.writeString(identity.name);
    try writer.append(",\"release\":");
    try writer.writeString(identity.release);
    try writer.append(",\"version\":");
    try writer.writeString(identity.version);
    try writer.appendByte('}');
}

fn writePlanReference(
    writer: *canonical_json.Writer,
    plan: PlanReference,
) Allocator.Error!void {
    try writer.append("{\"digest\":");
    try writer.writeString(plan.digest);
    try writer.append(",\"path\":");
    try writer.writeString(plan.path);
    try writer.append(",\"schema\":");
    try writer.writeString(plan.schema);
    try writer.appendByte('}');
}

fn writeRepositories(
    writer: *canonical_json.Writer,
    repositories: []const Repository,
) Allocator.Error!void {
    try writer.appendByte('[');
    for (repositories, 0..) |repository, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"cost\":");
        try writer.writeUint(repository.cost);
        try writer.append(",\"gpg_check\":");
        try writer.writeBool(repository.gpg_check);
        try writer.append(",\"id\":");
        try writer.writeString(repository.id);
        try writer.append(",\"priority\":");
        try writer.writeInt(repository.priority);
        try writer.append(",\"repomd_sha256\":");
        try writer.writeString(repository.repomd_sha256);
        try writer.append(",\"revision\":");
        try writer.writeOptionalString(repository.revision);
        try writer.append(",\"snapshot_id\":");
        try writer.writeString(repository.snapshot_id);
        try writer.append(",\"sources\":[");
        for (repository.sources, 0..) |source, source_index| {
            if (source_index != 0) try writer.appendByte(',');
            try writer.writeString(source);
        }
        try writer.append("]}");
    }
    try writer.appendByte(']');
}

pub const ParseError = error{
    NotCanonical,
    MalformedJson,
} || ValidationError || Allocator.Error;

/// Rebuilds a bundle from manifest bytes.
///
/// The parse is deliberately strict rather than lenient: after the model is
/// rebuilt and validated it is re-serialized and required to be byte-identical
/// to the input. That single check subsumes rejecting reordered keys, unknown
/// keys, altered whitespace, alternate number spellings, and a `digest` that
/// disagrees with the document it covers, because any of those produce
/// different canonical bytes. A reader therefore never accepts a manifest it
/// would not itself have written.
pub fn parse(allocator: Allocator, bytes: []const u8) ParseError!*Bundle {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch |err| switch (err) {
        // An allocator failure says nothing about the manifest, so it must not
        // be reported as a syntax error.
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.MalformedJson,
    };
    defer parsed.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const root = try expectObject(parsed.value);
    if (!std.mem.eql(u8, try expectString(root.get("schema")), schema)) {
        return error.InvalidSchema;
    }

    const digest_object = try expectObject(root.get("digest") orelse return error.MalformedJson);
    if (!std.mem.eql(u8, try expectString(digest_object.get("algorithm")), "sha256")) {
        return error.InvalidDigest;
    }
    if (!std.mem.eql(u8, try expectString(digest_object.get("domain")), schema)) {
        return error.InvalidDigest;
    }
    try validateSha256(try expectString(digest_object.get("value")));

    const data = Data{
        .files = try parseFiles(scratch, root.get("files")),
        .keys = try parseKeys(scratch, root.get("keys")),
        .packages = try parsePackages(scratch, root.get("packages")),
        .plan = try parsePlanReference(root.get("plan")),
        .repositories = try parseRepositories(scratch, root.get("repositories")),
    };

    const bundle = try Bundle.create(allocator, data);
    errdefer bundle.destroy();

    const round_trip = try bundle.canonicalJsonAlloc(allocator);
    defer allocator.free(round_trip);
    if (!std.mem.eql(u8, round_trip, bytes)) return error.NotCanonical;
    return bundle;
}

fn parseFiles(scratch: Allocator, value: ?std.json.Value) ParseError![]const File {
    const items = try expectArray(value);
    const files = try scratch.alloc(File, items.len);
    for (items, 0..) |item, index| {
        const object = try expectObject(item);
        files[index] = .{
            .path = try expectString(object.get("path")),
            .sha256 = try expectString(object.get("sha256")),
            .size = try expectUint(object.get("size")),
        };
    }
    return files;
}

fn parseKeys(scratch: Allocator, value: ?std.json.Value) ParseError![]const Key {
    const items = try expectArray(value);
    const keys = try scratch.alloc(Key, items.len);
    for (items, 0..) |item, index| {
        const object = try expectObject(item);
        keys[index] = .{
            .fingerprint = try expectString(object.get("fingerprint")),
            .path = try expectString(object.get("path")),
        };
    }
    return keys;
}

fn parsePackages(scratch: Allocator, value: ?std.json.Value) ParseError![]const Package {
    const items = try expectArray(value);
    const packages = try scratch.alloc(Package, items.len);
    for (items, 0..) |item, index| {
        const object = try expectObject(item);
        const checksum = try expectObject(object.get("checksum") orelse
            return error.MalformedJson);
        const identity = try expectObject(object.get("identity") orelse
            return error.MalformedJson);
        const signature = try expectObject(object.get("signature") orelse
            return error.MalformedJson);
        packages[index] = .{
            .checksum = .{
                .kind = try expectString(checksum.get("kind")),
                .is_pkgid = try expectBool(checksum.get("is_pkgid")),
                .value = try expectString(checksum.get("value")),
            },
            .href = try expectString(object.get("href")),
            .identity = .{
                .arch = try expectString(identity.get("arch")),
                .epoch = try expectOptionalUint(u32, identity.get("epoch")),
                .name = try expectString(identity.get("name")),
                .release = try expectString(identity.get("release")),
                .version = try expectString(identity.get("version")),
            },
            .path = try expectString(object.get("path")),
            .plan_package_id = try expectString(object.get("plan_package_id")),
            .repository_id = try expectString(object.get("repository_id")),
            .signature = .{
                .outcome = try parseOutcome(signature.get("outcome")),
                .key_fingerprint = try expectOptionalString(signature.get("key_fingerprint")),
            },
            .size = try expectOptionalUint(u64, object.get("size")),
            .xml_base = try expectOptionalString(object.get("xml_base")),
        };
    }
    return packages;
}

fn parsePlanReference(value: ?std.json.Value) ParseError!PlanReference {
    const object = try expectObject(value orelse return error.MalformedJson);
    return .{
        .digest = try expectString(object.get("digest")),
        .path = try expectString(object.get("path")),
        .schema = try expectString(object.get("schema")),
    };
}

fn parseRepositories(scratch: Allocator, value: ?std.json.Value) ParseError![]const Repository {
    const items = try expectArray(value);
    const repositories = try scratch.alloc(Repository, items.len);
    for (items, 0..) |item, index| {
        const object = try expectObject(item);
        const source_items = try expectArray(object.get("sources"));
        const sources = try scratch.alloc([]const u8, source_items.len);
        for (source_items, 0..) |source, source_index| {
            sources[source_index] = try expectString(source);
        }
        repositories[index] = .{
            .cost = std.math.cast(u32, try expectUint(object.get("cost"))) orelse
                return error.MalformedJson,
            .gpg_check = try expectBool(object.get("gpg_check")),
            .id = try expectString(object.get("id")),
            .priority = try expectInt(object.get("priority")),
            .repomd_sha256 = try expectString(object.get("repomd_sha256")),
            .revision = try expectOptionalString(object.get("revision")),
            .snapshot_id = try expectString(object.get("snapshot_id")),
            .sources = sources,
        };
    }
    return repositories;
}

fn parseOutcome(value: ?std.json.Value) ParseError!SignatureOutcome {
    const text = try expectString(value);
    inline for (@typeInfo(SignatureOutcome).@"enum".fields) |field| {
        const outcome: SignatureOutcome = @enumFromInt(field.value);
        if (std.mem.eql(u8, outcome.text(), text)) return outcome;
    }
    return error.InvalidSignature;
}

fn expectObject(value: ?std.json.Value) ParseError!std.json.ObjectMap {
    const inner = value orelse return error.MalformedJson;
    return switch (inner) {
        .object => |object| object,
        else => error.MalformedJson,
    };
}

fn expectArray(value: ?std.json.Value) ParseError![]const std.json.Value {
    const inner = value orelse return error.MalformedJson;
    return switch (inner) {
        .array => |array| array.items,
        else => error.MalformedJson,
    };
}

fn expectString(value: ?std.json.Value) ParseError![]const u8 {
    const inner = value orelse return error.MalformedJson;
    return switch (inner) {
        .string => |text| text,
        else => error.MalformedJson,
    };
}

fn expectOptionalString(value: ?std.json.Value) ParseError!?[]const u8 {
    const inner = value orelse return error.MalformedJson;
    return switch (inner) {
        .null => null,
        .string => |text| text,
        else => error.MalformedJson,
    };
}

fn expectBool(value: ?std.json.Value) ParseError!bool {
    const inner = value orelse return error.MalformedJson;
    return switch (inner) {
        .bool => |flag| flag,
        else => error.MalformedJson,
    };
}

fn expectUint(value: ?std.json.Value) ParseError!u64 {
    const inner = value orelse return error.MalformedJson;
    return switch (inner) {
        .integer => |number| std.math.cast(u64, number) orelse error.MalformedJson,
        else => error.MalformedJson,
    };
}

fn expectInt(value: ?std.json.Value) ParseError!i32 {
    const inner = value orelse return error.MalformedJson;
    return switch (inner) {
        .integer => |number| std.math.cast(i32, number) orelse error.MalformedJson,
        else => error.MalformedJson,
    };
}

fn expectOptionalUint(comptime T: type, value: ?std.json.Value) ParseError!?T {
    const inner = value orelse return error.MalformedJson;
    return switch (inner) {
        .null => null,
        .integer => |number| std.math.cast(T, number) orelse error.MalformedJson,
        else => error.MalformedJson,
    };
}

const testing = std.testing;

const test_sha_a = "1" ** 64;
const test_sha_b = "2" ** 64;
const test_sha_c = "3" ** 64;
const test_sha_d = "4" ** 64;
const test_sha_e = "5" ** 64;
const test_plan_digest = "6" ** 64;
const test_fingerprint = "abcdef0123456789abcdef0123456789abcdef01";

fn testData() Data {
    return .{
        .files = &.{
            .{ .path = "packages/base/b-2.0-1.noarch.rpm", .sha256 = test_sha_b, .size = 22 },
            .{ .path = plan_name, .sha256 = test_sha_a, .size = 11 },
            .{ .path = "keys/base.asc", .sha256 = test_sha_d, .size = 44 },
            .{ .path = "repos/base/repodata/repomd.xml", .sha256 = test_sha_e, .size = 55 },
            .{ .path = "packages/base/a-1.0-1.noarch.rpm", .sha256 = test_sha_c, .size = 33 },
        },
        .keys = &.{
            .{ .fingerprint = test_fingerprint, .path = "keys/base.asc" },
        },
        .packages = &.{
            .{
                .checksum = .{ .kind = "sha256", .is_pkgid = true, .value = test_sha_b },
                .href = "Packages/b-2.0-1.noarch.rpm",
                .identity = .{
                    .arch = "noarch",
                    .epoch = null,
                    .name = "b",
                    .release = "1",
                    .version = "2.0",
                },
                .path = "packages/base/b-2.0-1.noarch.rpm",
                .plan_package_id = "package-1",
                .repository_id = "base",
                .signature = .{ .outcome = .unsigned, .key_fingerprint = null },
                .size = 22,
                .xml_base = null,
            },
            .{
                .checksum = .{ .kind = "sha256", .is_pkgid = true, .value = test_sha_c },
                .href = "Packages/a-1.0-1.noarch.rpm",
                .identity = .{
                    .arch = "noarch",
                    .epoch = 1,
                    .name = "a",
                    .release = "1",
                    .version = "1.0",
                },
                .path = "packages/base/a-1.0-1.noarch.rpm",
                .plan_package_id = "package-0",
                .repository_id = "base",
                .signature = .{ .outcome = .verified, .key_fingerprint = test_fingerprint },
                .size = null,
                .xml_base = "https://example.invalid/base/",
            },
        },
        .plan = .{
            .digest = test_plan_digest,
            .path = plan_name,
            .schema = transaction_plan.schema,
        },
        .repositories = &.{
            .{
                .cost = 1000,
                .gpg_check = true,
                .id = "base",
                .priority = -5,
                .repomd_sha256 = test_sha_e,
                .revision = "1700000000",
                .snapshot_id = test_sha_e,
                .sources = &.{
                    "https://example.invalid/base/",
                    "https://mirror.invalid/base/",
                },
            },
        },
    };
}

test "bundle canonical form is byte-stable and input-order independent" {
    const allocator = testing.allocator;

    const forward = try Bundle.create(allocator, testData());
    defer forward.destroy();

    var shuffled = testData();
    var files: [5]File = undefined;
    for (shuffled.files, 0..) |file, index| files[files.len - 1 - index] = file;
    shuffled.files = &files;
    var packages: [2]Package = .{ shuffled.packages[1], shuffled.packages[0] };
    shuffled.packages = &packages;

    const reverse = try Bundle.create(allocator, shuffled);
    defer reverse.destroy();

    const forward_json = try forward.canonicalJsonAlloc(allocator);
    defer allocator.free(forward_json);
    const reverse_json = try reverse.canonicalJsonAlloc(allocator);
    defer allocator.free(reverse_json);
    try testing.expectEqualStrings(forward_json, reverse_json);

    try testing.expectEqual(
        try forward.digest(allocator),
        try reverse.digest(allocator),
    );
}

test "bundle digest is pinned" {
    const allocator = testing.allocator;
    const bundle = try Bundle.create(allocator, testData());
    defer bundle.destroy();

    // Pinned so any change to the canonical byte layout fails loudly. If this
    // test fails, confirm the schema change is intended before updating it:
    // the value is the bundle's published identity.
    const expected = "51691933b3cd17ffee3ccfaca4023cfc3786ed973bc0a5b31d654fcda18c05d0";
    const actual = try bundle.digest(allocator);
    try testing.expectEqualStrings(expected, &actual);
}

test "bundle digest covers the digest-free document" {
    const allocator = testing.allocator;
    const bundle = try Bundle.create(allocator, testData());
    defer bundle.destroy();

    const json = try bundle.canonicalJsonAlloc(allocator);
    defer allocator.free(json);
    const value = try bundle.digest(allocator);

    // The embedded digest is the hash of the document without it, so the
    // literal must appear exactly once and removing it must not change it.
    try testing.expect(std.mem.indexOf(u8, json, &value) != null);
    try testing.expect(std.mem.startsWith(u8, json, "{\"digest\":{\"algorithm\":\"sha256\","));
}

test "manifest round-trips through the strict parser" {
    const allocator = testing.allocator;
    const bundle = try Bundle.create(allocator, testData());
    defer bundle.destroy();
    const json = try bundle.canonicalJsonAlloc(allocator);
    defer allocator.free(json);

    const reparsed = try parse(allocator, json);
    defer reparsed.destroy();
    const again = try reparsed.canonicalJsonAlloc(allocator);
    defer allocator.free(again);
    try testing.expectEqualStrings(json, again);
    try testing.expectEqual(try bundle.digest(allocator), try reparsed.digest(allocator));

    try testing.expectEqual(@as(usize, 5), reparsed.model().files.len);
    try testing.expectEqualStrings("keys/base.asc", reparsed.model().files[0].path);
    try testing.expectEqualStrings("package-0", reparsed.model().packages[0].plan_package_id);
    try testing.expect(reparsed.findFile(plan_name) != null);
    try testing.expect(reparsed.findFile("nope") == null);
}

test "parser rejects non-canonical encodings of an otherwise valid manifest" {
    const allocator = testing.allocator;
    const bundle = try Bundle.create(allocator, testData());
    defer bundle.destroy();
    const json = try bundle.canonicalJsonAlloc(allocator);
    defer allocator.free(json);

    const padded = try std.mem.concat(allocator, u8, &.{ json, " " });
    defer allocator.free(padded);
    try testing.expectError(error.NotCanonical, parse(allocator, padded));

    const spaced = try std.mem.replaceOwned(u8, allocator, json, "\":", "\" :");
    defer allocator.free(spaced);
    try testing.expectError(error.NotCanonical, parse(allocator, spaced));

    const extra = try std.mem.replaceOwned(u8, allocator, json, "{\"digest\":", "{\"aaa\":1,\"digest\":");
    defer allocator.free(extra);
    try testing.expectError(error.NotCanonical, parse(allocator, extra));

    const reordered = try std.mem.replaceOwned(
        u8,
        allocator,
        json,
        "{\"fingerprint\":\"" ++ test_fingerprint ++ "\",\"path\":\"keys/base.asc\"}",
        "{\"path\":\"keys/base.asc\",\"fingerprint\":\"" ++ test_fingerprint ++ "\"}",
    );
    defer allocator.free(reordered);
    try testing.expect(!std.mem.eql(u8, reordered, json));
    try testing.expectError(error.NotCanonical, parse(allocator, reordered));

    try testing.expectError(error.MalformedJson, parse(allocator, "{"));
    try testing.expectError(error.MalformedJson, parse(allocator, "[]"));
}

test "parser rejects a digest that does not cover the document" {
    const allocator = testing.allocator;
    const bundle = try Bundle.create(allocator, testData());
    defer bundle.destroy();
    const json = try bundle.canonicalJsonAlloc(allocator);
    defer allocator.free(json);

    const tampered = try std.mem.replaceOwned(u8, allocator, json, "\"size\":22", "\"size\":23");
    defer allocator.free(tampered);
    try testing.expect(!std.mem.eql(u8, tampered, json));
    try testing.expectError(error.NotCanonical, parse(allocator, tampered));

    const forged = try std.mem.replaceOwned(u8, allocator, json, "\"algorithm\":\"sha256\"", "\"algorithm\":\"sha512\"");
    defer allocator.free(forged);
    try testing.expectError(error.InvalidDigest, parse(allocator, forged));

    const rebranded = try std.mem.replaceOwned(u8, allocator, json, "\"domain\":\"" ++ schema ++ "\"", "\"domain\":\"other\"");
    defer allocator.free(rebranded);
    try testing.expectError(error.InvalidDigest, parse(allocator, rebranded));
}

fn expectInvalid(expected: anyerror, mutate: fn (*Data) void) !void {
    var data = testData();
    mutate(&data);
    try testing.expectError(expected, validate(data));
}

test "validate rejects a plan reference that is not this schema" {
    try expectInvalid(error.InvalidSchema, struct {
        fn f(data: *Data) void {
            data.plan.schema = "tdnf.transaction-plan/v99";
        }
    }.f);
    try expectInvalid(error.InvalidPath, struct {
        fn f(data: *Data) void {
            data.plan.path = "elsewhere.json";
        }
    }.f);
    try expectInvalid(error.InvalidChecksum, struct {
        fn f(data: *Data) void {
            data.plan.digest = "short";
        }
    }.f);
    try expectInvalid(error.InvalidChecksum, struct {
        fn f(data: *Data) void {
            data.plan.digest = "A" ** 64;
        }
    }.f);
}

test "validate rejects repository entries that break identity or provenance" {
    try expectInvalid(error.DuplicateEntry, struct {
        fn f(data: *Data) void {
            const repositories = struct {
                var storage: [2]Repository = undefined;
            };
            repositories.storage[0] = data.repositories[0];
            repositories.storage[1] = data.repositories[0];
            data.repositories = &repositories.storage;
        }
    }.f);
    try expectInvalid(error.InvalidChecksum, struct {
        fn f(data: *Data) void {
            const repositories = struct {
                var storage: [1]Repository = undefined;
            };
            repositories.storage[0] = data.repositories[0];
            repositories.storage[0].repomd_sha256 = "nope";
            data.repositories = &repositories.storage;
        }
    }.f);
    try expectInvalid(error.EmptyId, struct {
        fn f(data: *Data) void {
            const repositories = struct {
                var storage: [1]Repository = undefined;
            };
            repositories.storage[0] = data.repositories[0];
            repositories.storage[0].snapshot_id = "";
            data.repositories = &repositories.storage;
        }
    }.f);
    try expectInvalid(error.InvalidSource, struct {
        fn f(data: *Data) void {
            const repositories = struct {
                var storage: [1]Repository = undefined;
            };
            repositories.storage[0] = data.repositories[0];
            repositories.storage[0].sources = &.{};
            data.repositories = &repositories.storage;
        }
    }.f);
    try expectInvalid(error.DuplicateEntry, struct {
        fn f(data: *Data) void {
            const repositories = struct {
                var storage: [1]Repository = undefined;
            };
            repositories.storage[0] = data.repositories[0];
            repositories.storage[0].sources = &.{
                "https://example.invalid/base/",
                "https://example.invalid/base/",
            };
            data.repositories = &repositories.storage;
        }
    }.f);
}

test "validate rejects sources that still carry credentials or secrets" {
    try expectInvalid(error.InvalidSource, struct {
        fn f(data: *Data) void {
            const repositories = struct {
                var storage: [1]Repository = undefined;
            };
            repositories.storage[0] = data.repositories[0];
            repositories.storage[0].sources = &.{"https://user:pw@example.invalid/base/"};
            data.repositories = &repositories.storage;
        }
    }.f);
    try expectInvalid(error.InvalidSource, struct {
        fn f(data: *Data) void {
            const repositories = struct {
                var storage: [1]Repository = undefined;
            };
            repositories.storage[0] = data.repositories[0];
            repositories.storage[0].sources = &.{"https://example.invalid/base/?token=abc"};
            data.repositories = &repositories.storage;
        }
    }.f);
    try expectInvalid(error.SecretShapedValue, struct {
        fn f(data: *Data) void {
            const repositories = struct {
                var storage: [1]Repository = undefined;
            };
            repositories.storage[0] = data.repositories[0];
            // Percent-encoded so only the decoding scan can see it. A raw
            // substring check passes this string.
            repositories.storage[0].sources = &.{"https://example.invalid/base/%74oken=abc/"};
            data.repositories = &repositories.storage;
        }
    }.f);
}

test "validate rejects signatures that claim more than the key set supports" {
    try expectInvalid(error.InvalidSignature, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[1];
            packages.storage[1].signature.key_fingerprint = null;
            data.packages = &packages.storage;
        }
    }.f);
    try expectInvalid(error.InvalidSignature, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[1];
            packages.storage[0].signature.key_fingerprint = test_fingerprint;
            data.packages = &packages.storage;
        }
    }.f);
    try expectInvalid(error.UnknownReference, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[1];
            packages.storage[1].signature.key_fingerprint = "0" ** 40;
            data.packages = &packages.storage;
        }
    }.f);
}

test "validate rejects packages that escape or misattribute their tree" {
    try expectInvalid(error.MisplacedFile, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[1];
            packages.storage[0].path = "keys/b-2.0-1.noarch.rpm";
            data.packages = &packages.storage;
        }
    }.f);
    try expectInvalid(error.MisplacedFile, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[1];
            packages.storage[0].path = "packages/other/b-2.0-1.noarch.rpm";
            data.packages = &packages.storage;
        }
    }.f);
    try expectInvalid(error.InvalidPath, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[1];
            packages.storage[0].path = "packages/base/../../etc/passwd";
            data.packages = &packages.storage;
        }
    }.f);
    try expectInvalid(error.UnknownReference, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[1];
            packages.storage[0].repository_id = "missing";
            data.packages = &packages.storage;
        }
    }.f);
    try expectInvalid(error.DuplicateEntry, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[0];
            data.packages = &packages.storage;
        }
    }.f);
    try expectInvalid(error.InvalidString, struct {
        fn f(data: *Data) void {
            const packages = struct {
                var storage: [2]Package = undefined;
            };
            packages.storage[0] = data.packages[0];
            packages.storage[1] = data.packages[1];
            packages.storage[0].identity.name = "";
            data.packages = &packages.storage;
        }
    }.f);
}

test "validate requires the file table to describe the tree exactly" {
    try expectInvalid(error.UntrackedFile, struct {
        fn f(data: *Data) void {
            // Drop the plan.json entry.
            const files = struct {
                var storage: [4]File = undefined;
            };
            var next: usize = 0;
            for (data.files) |file| {
                if (std.mem.eql(u8, file.path, plan_name)) continue;
                files.storage[next] = file;
                next += 1;
            }
            data.files = &files.storage;
        }
    }.f);
    try expectInvalid(error.UntrackedFile, struct {
        fn f(data: *Data) void {
            // The manifest may never describe itself.
            const files = struct {
                var storage: [6]File = undefined;
            };
            for (data.files, 0..) |file, index| files.storage[index] = file;
            files.storage[5] = .{ .path = manifest_name, .sha256 = test_sha_a, .size = 1 };
            data.files = &files.storage;
        }
    }.f);
    try expectInvalid(error.UntrackedFile, struct {
        fn f(data: *Data) void {
            // A package tree entry with no package behind it.
            const files = struct {
                var storage: [6]File = undefined;
            };
            for (data.files, 0..) |file, index| files.storage[index] = file;
            files.storage[5] = .{ .path = "packages/base/ghost.rpm", .sha256 = test_sha_a, .size = 1 };
            data.files = &files.storage;
        }
    }.f);
    try expectInvalid(error.UnknownReference, struct {
        fn f(data: *Data) void {
            // A repository tree entry for a repository that is not declared.
            const files = struct {
                var storage: [6]File = undefined;
            };
            for (data.files, 0..) |file, index| files.storage[index] = file;
            files.storage[5] = .{ .path = "repos/ghost/repomd.xml", .sha256 = test_sha_a, .size = 1 };
            data.files = &files.storage;
        }
    }.f);
    try expectInvalid(error.MisplacedFile, struct {
        fn f(data: *Data) void {
            // A file outside every structured prefix.
            const files = struct {
                var storage: [6]File = undefined;
            };
            for (data.files, 0..) |file, index| files.storage[index] = file;
            files.storage[5] = .{ .path = "stray.txt", .sha256 = test_sha_a, .size = 1 };
            data.files = &files.storage;
        }
    }.f);
    try expectInvalid(error.DuplicateEntry, struct {
        fn f(data: *Data) void {
            const files = struct {
                var storage: [6]File = undefined;
            };
            for (data.files, 0..) |file, index| files.storage[index] = file;
            files.storage[5] = data.files[0];
            data.files = &files.storage;
        }
    }.f);
}

test "validate rejects key entries outside the key tree" {
    try expectInvalid(error.MisplacedFile, struct {
        fn f(data: *Data) void {
            const keys = struct {
                var storage: [1]Key = undefined;
            };
            keys.storage[0] = data.keys[0];
            keys.storage[0].path = "packages/base.asc";
            data.keys = &keys.storage;
        }
    }.f);
    try expectInvalid(error.InvalidSignature, struct {
        fn f(data: *Data) void {
            const keys = struct {
                var storage: [1]Key = undefined;
            };
            keys.storage[0] = data.keys[0];
            keys.storage[0].fingerprint = "NOTHEX";
            data.keys = &keys.storage;
        }
    }.f);
    try expectInvalid(error.DuplicateEntry, struct {
        fn f(data: *Data) void {
            const keys = struct {
                var storage: [2]Key = undefined;
            };
            keys.storage[0] = data.keys[0];
            keys.storage[1] = data.keys[0];
            data.keys = &keys.storage;
        }
    }.f);
}

test "bundle construction releases everything on allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            const bundle = try Bundle.create(allocator, testData());
            defer bundle.destroy();
            const json = try bundle.canonicalJsonAlloc(allocator);
            defer allocator.free(json);
        }
    }.run, .{});
}

test "parsing releases everything on allocation failure" {
    const allocator = testing.allocator;
    const bundle = try Bundle.create(allocator, testData());
    defer bundle.destroy();
    const json = try bundle.canonicalJsonAlloc(allocator);
    defer allocator.free(json);

    try testing.checkAllAllocationFailures(allocator, struct {
        fn run(inner: Allocator, bytes: []const u8) !void {
            const reparsed = try parse(inner, bytes);
            reparsed.destroy();
        }
    }.run, .{json});
}
