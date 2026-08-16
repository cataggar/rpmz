//! Content digest primitives shared by every path that must decide whether a
//! run of bytes is the run of bytes it was promised.
//!
//! This file deliberately imports nothing from the repository-metadata model
//! (or from anything else in the tree). Two very differently shaped callers
//! need it:
//!
//!   * `repomd/metadata_integrity.zig`, whose checksums arrive as the C
//!     strings of a parsed `repomd.xml`, and
//!   * `client/verified_fetch.zig`, whose checksums arrive as Zig slices out
//!     of a canonical transaction plan.
//!
//! Keeping the hashing and the accept/reject decision in one place means the
//! two cannot drift -- in particular, they cannot come to disagree about which
//! checksum algorithms are acceptable, which is the property an attacker would
//! attack first.
//!
//! It is a standalone Zig module rather than a plain file import because Zig
//! forbids one source file from belonging to two modules.

const std = @import("std");

pub const Kind = enum {
    md5,
    sha1,
    sha224,
    sha256,
    sha384,
    sha512,
};

/// Map a repository-advertised checksum name onto an algorithm.
///
/// Returns null for anything unrecognised. libsolv spells SHA-1 as bare
/// "sha", so that alias is accepted; nothing else is.
pub fn kindFromName(raw: []const u8) ?Kind {
    if (std.ascii.eqlIgnoreCase(raw, "md5")) return .md5;
    if (std.ascii.eqlIgnoreCase(raw, "sha")) return .sha1;
    if (std.ascii.eqlIgnoreCase(raw, "sha1")) return .sha1;
    if (std.ascii.eqlIgnoreCase(raw, "sha224")) return .sha224;
    if (std.ascii.eqlIgnoreCase(raw, "sha256")) return .sha256;
    if (std.ascii.eqlIgnoreCase(raw, "sha384")) return .sha384;
    if (std.ascii.eqlIgnoreCase(raw, "sha512")) return .sha512;
    return null;
}

/// Verify `bytes` against `expected_hex` under the algorithm named by
/// `checksum_type`.
///
/// Fails closed: an unknown algorithm, an empty expectation, or a
/// wrong-length expectation all return false rather than an error, so a
/// caller that merely checks for the absence of an error cannot accidentally
/// treat "could not verify" as "verified".
pub fn matchesName(
    checksum_type: []const u8,
    expected_hex: []const u8,
    bytes: []const u8,
) bool {
    return matches(kindFromName(checksum_type) orelse return false, expected_hex, bytes);
}

/// Verify `bytes` against `expected_hex` under an already-resolved algorithm.
pub fn matches(kind: Kind, expected_hex: []const u8, bytes: []const u8) bool {
    return switch (kind) {
        .md5 => eqlHex(std.crypto.hash.Md5, expected_hex, bytes),
        .sha1 => eqlHex(std.crypto.hash.Sha1, expected_hex, bytes),
        .sha224 => eqlHex(std.crypto.hash.sha2.Sha224, expected_hex, bytes),
        .sha256 => eqlHex(std.crypto.hash.sha2.Sha256, expected_hex, bytes),
        .sha384 => eqlHex(std.crypto.hash.sha2.Sha384, expected_hex, bytes),
        .sha512 => eqlHex(std.crypto.hash.sha2.Sha512, expected_hex, bytes),
    };
}

fn eqlHex(comptime Hash: type, expected_hex: []const u8, bytes: []const u8) bool {
    var digest: [Hash.digest_length]u8 = undefined;
    var hasher = Hash.init(.{});
    hasher.update(bytes);
    hasher.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    if (expected_hex.len != hex.len) return false;
    return std.ascii.eqlIgnoreCase(expected_hex, &hex);
}

/// Lower-case hex SHA-256 of `bytes`.
///
/// A transaction bundle records every file it captures by SHA-256 regardless
/// of which algorithm the source repository advertised, so that a bundle has
/// exactly one integrity domain instead of inheriting whichever weaker digest
/// the upstream repomd happened to use.
pub fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(bytes);
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}

test "recognises the checksum names repositories actually publish" {
    const testing = std.testing;
    try testing.expectEqual(Kind.sha1, kindFromName("sha").?);
    try testing.expectEqual(Kind.sha1, kindFromName("SHA1").?);
    try testing.expectEqual(Kind.sha256, kindFromName("sha256").?);
    try testing.expectEqual(Kind.sha512, kindFromName("SHA512").?);
    try testing.expect(kindFromName("sha3-256") == null);
    try testing.expect(kindFromName("") == null);
    try testing.expect(kindFromName("none") == null);
}

test "matchesName fails closed on unusable expectations" {
    const testing = std.testing;
    const bytes = "repository metadata";
    const hex = sha256Hex(bytes);

    try testing.expect(matchesName("sha256", &hex, bytes));
    try testing.expect(matchesName("SHA256", &hex, bytes));

    // An algorithm we do not implement must never verify. Otherwise a
    // repository could switch off verification just by naming one.
    try testing.expect(!matchesName("sha3-256", &hex, bytes));
    try testing.expect(!matchesName("", &hex, bytes));
    // A truncated expectation must not match by prefix.
    try testing.expect(!matchesName("sha256", hex[0..32], bytes));
    try testing.expect(!matchesName("sha256", "", bytes));
    try testing.expect(!matchesName("sha256", &hex, "other bytes"));
}

test "sha256Hex matches published vectors" {
    const testing = std.testing;
    try testing.expectEqualStrings(
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        &sha256Hex(""),
    );
    try testing.expectEqualStrings(
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        &sha256Hex("abc"),
    );
}

test "every supported algorithm verifies its own digest and rejects others" {
    const testing = std.testing;
    const bytes = "rpmz transaction bundle";
    const names = [_][]const u8{ "md5", "sha1", "sha224", "sha256", "sha384", "sha512" };
    for (names) |name| {
        const kind = kindFromName(name).?;
        const hex = switch (kind) {
            .md5 => &hexOf(std.crypto.hash.Md5, bytes),
            .sha1 => &hexOf(std.crypto.hash.Sha1, bytes),
            .sha224 => &hexOf(std.crypto.hash.sha2.Sha224, bytes),
            .sha256 => &hexOf(std.crypto.hash.sha2.Sha256, bytes),
            .sha384 => &hexOf(std.crypto.hash.sha2.Sha384, bytes),
            .sha512 => &hexOf(std.crypto.hash.sha2.Sha512, bytes),
        };
        try testing.expect(matchesName(name, hex, bytes));
        try testing.expect(!matchesName(name, hex, "rpmz transaction bundlf"));
    }
}

fn hexOf(comptime Hash: type, bytes: []const u8) [Hash.digest_length * 2]u8 {
    var digest: [Hash.digest_length]u8 = undefined;
    var hasher = Hash.init(.{});
    hasher.update(bytes);
    hasher.final(&digest);
    return std.fmt.bytesToHex(digest, .lower);
}
