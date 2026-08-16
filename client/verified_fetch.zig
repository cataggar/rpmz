//! The single place where downloaded bytes become bytes rpmz is allowed to
//! use, and the single place where a transaction bundle learns what it
//! captured.
//!
//! Today `TDNFDownloadMetadata` writes every record named by a `repomd.xml`
//! straight into the repository cache without checking a single checksum;
//! verification happens much later, and only for the records the loader
//! happens to read. Anything that fetches on behalf of a bundle export must
//! not inherit that shape, because a bundle is a *claim* about content --
//! recording a digest computed over bytes nobody checked would launder an
//! unverified download into an authoritative-looking artifact.
//!
//! Two rules follow, and both are enforced by the types here rather than by
//! convention:
//!
//!   1. **No expectation, no acceptance.** `verify` refuses to return a
//!      capture when the plan carried no checksum for the file. There is no
//!      "verify if we happen to know how" mode and no boolean to switch
//!      checking off.
//!   2. **The recorded digest is computed over the verified bytes.** A
//!      `Capture` can only be produced by a function that has already
//!      compared the content against its expectation, so a caller cannot
//!      obtain one for bytes that failed or were never checked.
//!
//! Hashing and the set of acceptable algorithm names come from
//! `content_digest`, shared with the repomd loader path, so the two cannot
//! come to disagree about what counts as verified.

const std = @import("std");
const content_digest = @import("content_digest");
const transaction_plan = @import("transaction_plan");

pub const Checksum = transaction_plan.Checksum;

/// What authoritative metadata promised about a file, in the shape a
/// canonical transaction plan carries it.
pub const Expectation = struct {
    /// Checksum over the bytes exactly as transferred. Required.
    checksum: Checksum,
    /// Declared transfer size, when the metadata published one.
    size: ?u64 = null,
    /// Checksum over the decompressed bytes, for compressed metadata records.
    open_checksum: ?Checksum = null,
    /// Declared decompressed size. Only consulted when no open checksum is
    /// available: a verified open checksum already proves the exact bytes, and
    /// a disagreeing open size then indicts the metadata rather than the
    /// content. This mirrors the repomd loader, which in turn mirrors what
    /// every other package manager tolerates in the wild.
    open_size: ?u64 = null,
};

/// Proof that a specific run of bytes was compared against an expectation and
/// matched. Only `verify` and `verifyFile` can construct one.
pub const Capture = struct {
    /// Lower-case hex SHA-256 of the verified bytes. A bundle records this
    /// regardless of which algorithm the repository advertised, so that the
    /// bundle has exactly one integrity domain.
    sha256: [64]u8,
    /// Byte length of the verified content.
    size: u64,

    pub fn sha256Slice(self: *const Capture) []const u8 {
        return self.sha256[0..];
    }
};

pub const VerifyError = error{
    /// The transferred bytes do not hash to the promised value.
    ChecksumMismatch,
    /// The transferred byte count does not match the promised size.
    SizeMismatch,
    /// The decompressed bytes do not hash to the promised open value.
    OpenChecksumMismatch,
    /// The decompressed byte count does not match the promised open size.
    OpenSizeMismatch,
    /// The metadata named a checksum algorithm this build cannot compute, or
    /// supplied a malformed expectation. Refused rather than skipped: an
    /// unknown algorithm is exactly how an attacker would ask for a file to
    /// go unchecked.
    UnsupportedChecksum,
};

pub const FileVerifyError = VerifyError || error{
    /// The staged file could not be read back, or exceeded `max_bytes`.
    UnreadableStagedFile,
    /// The staged file is larger than the caller is willing to hold.
    StagedFileTooLarge,
    OutOfMemory,
};

/// Verify transferred bytes against `expectation` and capture their SHA-256.
///
/// `open_bytes` carries the decompressed content when the caller has already
/// decompressed the record, and null otherwise. Passing null when the
/// expectation carries an open checksum is not an error: an open checksum
/// constrains bytes this function was not shown, and the caller that does the
/// decompression is responsible for calling `verifyOpen` on the result. The
/// asymmetry is deliberate -- refusing here would force every package
/// download, which never has an open checksum, through a decompression path
/// it does not need.
pub fn verify(
    bytes: []const u8,
    expectation: Expectation,
    open_bytes: ?[]const u8,
) VerifyError!Capture {
    if (expectation.size) |size| {
        if (bytes.len != size) return error.SizeMismatch;
    }
    const kind = content_digest.kindFromName(expectation.checksum.kind) orelse
        return error.UnsupportedChecksum;
    if (!content_digest.matches(kind, expectation.checksum.value, bytes)) {
        return error.ChecksumMismatch;
    }
    if (open_bytes) |open| try verifyOpen(open, expectation);
    return .{
        .sha256 = content_digest.sha256Hex(bytes),
        .size = bytes.len,
    };
}

/// Verify decompressed bytes against the open constraints of `expectation`.
///
/// A no-op when the metadata published neither an open checksum nor an open
/// size, which is the common case for uncompressed records.
pub fn verifyOpen(open_bytes: []const u8, expectation: Expectation) VerifyError!void {
    if (expectation.open_checksum) |open_checksum| {
        const kind = content_digest.kindFromName(open_checksum.kind) orelse
            return error.UnsupportedChecksum;
        if (!content_digest.matches(kind, open_checksum.value, open_bytes)) {
            return error.OpenChecksumMismatch;
        }
        return;
    }
    if (expectation.open_size) |open_size| {
        if (open_bytes.len != open_size) return error.OpenSizeMismatch;
    }
}

/// Verify a file staged on disk and capture its SHA-256.
///
/// The file is read whole so that the bytes hashed are the bytes stored,
/// closing the gap in which a staged file could be replaced between an
/// on-the-fly hash and its later use.
pub fn verifyFile(
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
    allocator: std.mem.Allocator,
    expectation: Expectation,
    max_bytes: usize,
) FileVerifyError!Capture {
    const bytes = dir.readFileAlloc(
        io,
        sub_path,
        allocator,
        .limited(max_bytes),
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.StreamTooLong => return error.StagedFileTooLarge,
        else => return error.UnreadableStagedFile,
    };
    defer allocator.free(bytes);
    return verify(bytes, expectation, null);
}

/// Verify a fetched `repomd.xml` against the SHA-256 the plan pinned for it.
///
/// This is the root of the metadata trust chain: every record checksum a
/// caller later relies on is only as trustworthy as the `repomd.xml` it was
/// read from. The plan pins `repomd.checksum_sha256` specifically -- not
/// whatever algorithm the repository prefers -- so this takes a bare hex
/// digest rather than a `Checksum`.
pub fn verifyRepomd(bytes: []const u8, pinned_sha256: []const u8) VerifyError!Capture {
    if (pinned_sha256.len != 64) return error.UnsupportedChecksum;
    const actual = content_digest.sha256Hex(bytes);
    if (!std.ascii.eqlIgnoreCase(pinned_sha256, &actual)) return error.ChecksumMismatch;
    return .{ .sha256 = actual, .size = bytes.len };
}

/// How `fetchVerified` obtains bytes.
///
/// The transfer itself is injected rather than implemented here. Downloading
/// needs a `TDNF_HANDLE` (proxies, mirrors, TLS policy, progress reporting),
/// and taking that dependency would drag this module into the client handle
/// graph and make the verification rules untestable in isolation -- which is
/// precisely how the current unverified metadata download came to be
/// unnoticed. The staging-and-verification protocol lives here; the transport
/// is the caller's.
pub const Fetcher = struct {
    context: *anyopaque,
    /// Place the bytes named by `location` at `dir`/`sub_path`, replacing any
    /// existing file there.
    fetchFn: *const fn (
        context: *anyopaque,
        location: []const u8,
        dir: std.Io.Dir,
        sub_path: []const u8,
    ) anyerror!void,

    fn fetch(
        self: Fetcher,
        location: []const u8,
        dir: std.Io.Dir,
        sub_path: []const u8,
    ) anyerror!void {
        return self.fetchFn(self.context, location, dir, sub_path);
    }
};

pub const StageError = FileVerifyError || error{
    /// The transfer itself failed. Kept distinct from a verification failure
    /// so a caller can tell "could not reach the repository" from "the
    /// repository served something other than what it promised".
    FetchFailed,
};

/// Fetch `location` into the staging directory and verify it before anyone
/// else can see it.
///
/// On any failure the staged file is removed. Leaving unverified bytes behind
/// under their final name is how a rejected download becomes a poisoned cache:
/// a later step that merely checks for the file's existence would consume
/// content that failed verification.
pub fn fetchVerified(
    io: std.Io,
    fetcher: Fetcher,
    location: []const u8,
    staging_dir: std.Io.Dir,
    sub_path: []const u8,
    allocator: std.mem.Allocator,
    expectation: Expectation,
    max_bytes: usize,
) StageError!Capture {
    fetcher.fetch(location, staging_dir, sub_path) catch {
        discardStaged(io, staging_dir, sub_path);
        return error.FetchFailed;
    };
    return verifyFile(io, staging_dir, sub_path, allocator, expectation, max_bytes) catch |err| {
        discardStaged(io, staging_dir, sub_path);
        return err;
    };
}

fn discardStaged(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) void {
    dir.deleteFile(io, sub_path) catch {};
}

/// Build the expectation for one repomd record of a plan repository.
pub fn expectationForRecord(record: transaction_plan.MetadataRecord) ?Expectation {
    const checksum = record.checksum orelse return null;
    return .{
        .checksum = checksum,
        .size = record.size,
        .open_checksum = record.open_checksum,
        .open_size = record.open_size,
    };
}

/// Build the expectation for a plan package source.
///
/// Packages always carry a checksum in a valid plan, so this cannot fail --
/// the plan validator rejects a `PackageSource` without one.
pub fn expectationForPackage(source: transaction_plan.PackageSource) Expectation {
    return .{ .checksum = source.checksum, .size = source.size };
}

const testing = std.testing;

fn sha256Of(bytes: []const u8) [64]u8 {
    return content_digest.sha256Hex(bytes);
}

test "verify accepts matching content and reports its sha256" {
    const bytes = "primary.xml.zst payload";
    const hex = sha256Of(bytes);
    const capture = try verify(
        bytes,
        .{ .checksum = .{ .kind = "sha256", .value = &hex }, .size = bytes.len },
        null,
    );
    try testing.expectEqualStrings(&hex, capture.sha256Slice());
    try testing.expectEqual(@as(u64, bytes.len), capture.size);
}

test "verify rejects a one-bit content change" {
    const bytes = "primary.xml.zst payload";
    const hex = sha256Of(bytes);
    try testing.expectError(error.ChecksumMismatch, verify(
        "primary.xml.zst paylozd",
        .{ .checksum = .{ .kind = "sha256", .value = &hex } },
        null,
    ));
}

test "verify checks the declared size before hashing" {
    const bytes = "payload";
    const hex = sha256Of(bytes);
    try testing.expectError(error.SizeMismatch, verify(
        bytes,
        .{ .checksum = .{ .kind = "sha256", .value = &hex }, .size = bytes.len + 1 },
        null,
    ));
}

test "verify refuses an algorithm it cannot compute instead of skipping it" {
    const bytes = "payload";
    const hex = sha256Of(bytes);
    // The digest is correct; only the advertised name is unknown. Accepting
    // this would let a repository disable verification by renaming it.
    try testing.expectError(error.UnsupportedChecksum, verify(
        bytes,
        .{ .checksum = .{ .kind = "sha3-256", .value = &hex } },
        null,
    ));
    try testing.expectError(error.UnsupportedChecksum, verify(
        bytes,
        .{ .checksum = .{ .kind = "", .value = &hex } },
        null,
    ));
}

test "verify refuses a truncated expectation rather than matching a prefix" {
    const bytes = "payload";
    const hex = sha256Of(bytes);
    try testing.expectError(error.ChecksumMismatch, verify(
        bytes,
        .{ .checksum = .{ .kind = "sha256", .value = hex[0..32] } },
        null,
    ));
}

test "there is no way to obtain a capture without an expectation" {
    // Expectation.checksum has no default, so a caller cannot construct one
    // that opts out of verification. This test exists to fail loudly if that
    // field is ever given a default or made optional.
    const info = @typeInfo(Expectation).@"struct";
    inline for (info.fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "checksum")) {
            try testing.expect(field.default_value_ptr == null);
            try testing.expectEqual(Checksum, field.type);
        }
    }
}

test "open checksum governs decompressed bytes" {
    const raw = "compressed";
    const open = "decompressed";
    const raw_hex = sha256Of(raw);
    const open_hex = sha256Of(open);
    const expectation: Expectation = .{
        .checksum = .{ .kind = "sha256", .value = &raw_hex },
        .open_checksum = .{ .kind = "sha256", .value = &open_hex },
    };

    const capture = try verify(raw, expectation, open);
    // The capture describes the transferred bytes, never the decompressed
    // ones: that is what a replay would have to re-download.
    try testing.expectEqualStrings(&raw_hex, capture.sha256Slice());

    try testing.expectError(
        error.OpenChecksumMismatch,
        verify(raw, expectation, "decompresseD"),
    );
}

test "open size is consulted only when no open checksum was published" {
    const raw = "compressed";
    const open = "decompressed";
    const raw_hex = sha256Of(raw);
    const open_hex = sha256Of(open);

    // Size-only: a disagreement is fatal, because nothing else constrains the
    // decompressed bytes.
    try testing.expectError(error.OpenSizeMismatch, verify(
        raw,
        .{ .checksum = .{ .kind = "sha256", .value = &raw_hex }, .open_size = open.len + 5 },
        open,
    ));

    // With a verified open checksum, a stale open size does not reject the
    // repository -- the checksum already proved the exact bytes.
    _ = try verify(
        raw,
        .{
            .checksum = .{ .kind = "sha256", .value = &raw_hex },
            .open_checksum = .{ .kind = "sha256", .value = &open_hex },
            .open_size = open.len + 5,
        },
        open,
    );
}

test "an unsupported open algorithm is refused, not ignored" {
    const raw = "compressed";
    const open = "decompressed";
    const raw_hex = sha256Of(raw);
    const open_hex = sha256Of(open);
    try testing.expectError(error.UnsupportedChecksum, verify(
        raw,
        .{
            .checksum = .{ .kind = "sha256", .value = &raw_hex },
            .open_checksum = .{ .kind = "sha3-256", .value = &open_hex },
        },
        open,
    ));
}

test "verifyRepomd pins the root of the metadata trust chain" {
    const bytes = "<repomd/>";
    const hex = sha256Of(bytes);
    const capture = try verifyRepomd(bytes, &hex);
    try testing.expectEqualStrings(&hex, capture.sha256Slice());
    try testing.expectEqual(@as(u64, bytes.len), capture.size);

    try testing.expectError(error.ChecksumMismatch, verifyRepomd("<repomd />", &hex));
    // A short or empty pin must not be treated as "no pin required".
    try testing.expectError(error.UnsupportedChecksum, verifyRepomd(bytes, hex[0..63]));
    try testing.expectError(error.UnsupportedChecksum, verifyRepomd(bytes, ""));
}

test "verifyFile hashes the bytes that are actually on disk" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const bytes = "staged record bytes";
    const hex = sha256Of(bytes);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "record", .data = bytes });

    const capture = try verifyFile(
        testing.io,
        tmp.dir,
        "record",
        testing.allocator,
        .{ .checksum = .{ .kind = "sha256", .value = &hex }, .size = bytes.len },
        1 << 20,
    );
    try testing.expectEqualStrings(&hex, capture.sha256Slice());

    // Replace the staged file behind the caller's back: the next verification
    // must fail, which is the whole point of hashing what is on disk.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "record", .data = "tampered record byte" });
    try testing.expectError(error.ChecksumMismatch, verifyFile(
        testing.io,
        tmp.dir,
        "record",
        testing.allocator,
        .{ .checksum = .{ .kind = "sha256", .value = &hex } },
        1 << 20,
    ));
}

test "verifyFile reports a missing staged file distinctly from a mismatch" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const hex = sha256Of("anything");
    try testing.expectError(error.UnreadableStagedFile, verifyFile(
        testing.io,
        tmp.dir,
        "absent",
        testing.allocator,
        .{ .checksum = .{ .kind = "sha256", .value = &hex } },
        1 << 20,
    ));
}

test "verifyFile refuses a staged file larger than the caller's limit" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const bytes = "0123456789";
    const hex = sha256Of(bytes);
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "record", .data = bytes });
    try testing.expectError(error.StagedFileTooLarge, verifyFile(
        testing.io,
        tmp.dir,
        "record",
        testing.allocator,
        .{ .checksum = .{ .kind = "sha256", .value = &hex } },
        4,
    ));
}

test "plan records without a checksum yield no expectation" {
    const record: transaction_plan.MetadataRecord = .{
        .checksum = null,
        .database_version = null,
        .location = .{ .href = "repodata/other", .xml_base = null },
        .open_checksum = null,
        .open_size = null,
        .record_type = "other",
        .size = null,
        .timestamp = null,
    };
    // Returning null forces the caller to decide explicitly. It must never
    // become an Expectation with verification disabled.
    try testing.expect(expectationForRecord(record) == null);
}

test "plan record and package expectations carry every published constraint" {
    const hex = sha256Of("x");
    const open_hex = sha256Of("y");
    const record: transaction_plan.MetadataRecord = .{
        .checksum = .{ .kind = "sha256", .value = &hex },
        .database_version = null,
        .location = .{ .href = "repodata/primary.xml.zst", .xml_base = null },
        .open_checksum = .{ .kind = "sha256", .value = &open_hex },
        .open_size = 9,
        .record_type = "primary",
        .size = 7,
        .timestamp = 42,
    };
    const expectation = expectationForRecord(record).?;
    try testing.expectEqualStrings("sha256", expectation.checksum.kind);
    try testing.expectEqualStrings(&hex, expectation.checksum.value);
    try testing.expectEqual(@as(?u64, 7), expectation.size);
    try testing.expectEqualStrings(&open_hex, expectation.open_checksum.?.value);
    try testing.expectEqual(@as(?u64, 9), expectation.open_size);

    const package = expectationForPackage(.{
        .checksum = .{ .kind = "sha256", .value = &hex },
        .location = .{ .href = "p.rpm", .xml_base = null },
        .size = 11,
    });
    try testing.expectEqualStrings(&hex, package.checksum.value);
    try testing.expectEqual(@as(?u64, 11), package.size);
    // A package has no compressed/decompressed distinction.
    try testing.expect(package.open_checksum == null);
    try testing.expect(package.open_size == null);
}

test "every checksum algorithm the loader accepts is accepted here too" {
    const bytes = "shared algorithm set";
    for ([_][]const u8{ "md5", "sha", "sha1", "sha224", "sha256", "sha384", "sha512" }) |name| {
        const kind = content_digest.kindFromName(name).?;
        var buffer: [128]u8 = undefined;
        const hex = hexFor(kind, bytes, &buffer);
        const capture = try verify(
            bytes,
            .{ .checksum = .{ .kind = name, .value = hex } },
            null,
        );
        // Whatever the repository advertised, the capture is SHA-256.
        try testing.expectEqualStrings(&sha256Of(bytes), capture.sha256Slice());
    }
}

fn hexFor(kind: content_digest.Kind, bytes: []const u8, buffer: []u8) []const u8 {
    return switch (kind) {
        .md5 => writeHex(std.crypto.hash.Md5, bytes, buffer),
        .sha1 => writeHex(std.crypto.hash.Sha1, bytes, buffer),
        .sha224 => writeHex(std.crypto.hash.sha2.Sha224, bytes, buffer),
        .sha256 => writeHex(std.crypto.hash.sha2.Sha256, bytes, buffer),
        .sha384 => writeHex(std.crypto.hash.sha2.Sha384, bytes, buffer),
        .sha512 => writeHex(std.crypto.hash.sha2.Sha512, bytes, buffer),
    };
}

fn writeHex(comptime Hash: type, bytes: []const u8, buffer: []u8) []const u8 {
    var digest: [Hash.digest_length]u8 = undefined;
    var hasher = Hash.init(.{});
    hasher.update(bytes);
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    @memcpy(buffer[0..hex.len], &hex);
    return buffer[0..hex.len];
}

const StagingFixture = struct {
    bytes: []const u8,
    fail: bool = false,
    calls: usize = 0,

    fn fetch(
        context: *anyopaque,
        location: []const u8,
        dir: std.Io.Dir,
        sub_path: []const u8,
    ) anyerror!void {
        const self: *StagingFixture = @ptrCast(@alignCast(context));
        self.calls += 1;
        _ = location;
        if (self.fail) return error.Unreachable;
        try dir.writeFile(testing.io, .{ .sub_path = sub_path, .data = self.bytes });
    }

    fn fetcher(self: *StagingFixture) Fetcher {
        return .{ .context = self, .fetchFn = StagingFixture.fetch };
    }
};

test "fetchVerified stages, verifies, and captures" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const bytes = "repodata/primary.xml.zst bytes";
    const hex = sha256Of(bytes);
    var fixture: StagingFixture = .{ .bytes = bytes };

    const capture = try fetchVerified(
        testing.io,
        fixture.fetcher(),
        "https://example.invalid/repodata/primary.xml.zst",
        tmp.dir,
        "primary.xml.zst",
        testing.allocator,
        .{ .checksum = .{ .kind = "sha256", .value = &hex }, .size = bytes.len },
        1 << 20,
    );
    try testing.expectEqualStrings(&hex, capture.sha256Slice());
    try testing.expectEqual(@as(usize, 1), fixture.calls);
    // The verified file survives for the caller to publish.
    const staged = try tmp.dir.readFileAlloc(testing.io, "primary.xml.zst", testing.allocator, .unlimited);
    defer testing.allocator.free(staged);
    try testing.expectEqualStrings(bytes, staged);
}

test "fetchVerified deletes bytes that failed verification" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const hex = sha256Of("what was promised");
    var fixture: StagingFixture = .{ .bytes = "what was served" };

    try testing.expectError(error.ChecksumMismatch, fetchVerified(
        testing.io,
        fixture.fetcher(),
        "https://example.invalid/record",
        tmp.dir,
        "record",
        testing.allocator,
        .{ .checksum = .{ .kind = "sha256", .value = &hex } },
        1 << 20,
    ));

    // Nothing may remain under the final name; otherwise a later step that
    // only checks for existence would consume rejected content.
    try testing.expectError(
        error.FileNotFound,
        tmp.dir.readFileAlloc(testing.io, "record", testing.allocator, .unlimited),
    );
}

test "fetchVerified reports transport failure distinctly from tampering" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const hex = sha256Of("payload");
    var fixture: StagingFixture = .{ .bytes = "payload", .fail = true };

    try testing.expectError(error.FetchFailed, fetchVerified(
        testing.io,
        fixture.fetcher(),
        "https://example.invalid/record",
        tmp.dir,
        "record",
        testing.allocator,
        .{ .checksum = .{ .kind = "sha256", .value = &hex } },
        1 << 20,
    ));
    try testing.expectEqual(@as(usize, 1), fixture.calls);
}

test "fetchVerified rejects an oversized staged file without keeping it" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const bytes = "0123456789abcdef";
    const hex = sha256Of(bytes);
    var fixture: StagingFixture = .{ .bytes = bytes };

    try testing.expectError(error.StagedFileTooLarge, fetchVerified(
        testing.io,
        fixture.fetcher(),
        "https://example.invalid/record",
        tmp.dir,
        "record",
        testing.allocator,
        .{ .checksum = .{ .kind = "sha256", .value = &hex } },
        4,
    ));
    try testing.expectError(
        error.FileNotFound,
        tmp.dir.readFileAlloc(testing.io, "record", testing.allocator, .unlimited),
    );
}
