const std = @import("std");
const model = @import("model.zig");
const content_digest = @import("content_digest");

/// Verify `bytes` against a checksum carried in the C-shaped repomd model.
///
/// The hashing itself, and the decision about which algorithm names are
/// acceptable, live in `content_digest` so that this loader path and the
/// slice-shaped transaction-bundle fetch path cannot drift apart.
pub fn digestMatches(checksum: model.Checksum, bytes: []const u8) bool {
    const checksum_type = model.spanZ(checksum.pszType) orelse return false;
    const expected = model.spanZ(checksum.pszValue) orelse return false;
    return content_digest.matchesName(checksum_type, expected, bytes);
}

test "accepts libsolv checksum aliases without changing their raw kind" {
    const testing = std.testing;
    const bytes = "repository metadata";

    var sha1_digest: [20]u8 = undefined;
    var sha1_hasher = std.crypto.hash.Sha1.init(.{});
    sha1_hasher.update(bytes);
    sha1_hasher.final(&sha1_digest);
    const sha1_hex = std.fmt.bytesToHex(sha1_digest, .lower);

    var sha224_digest: [28]u8 = undefined;
    var sha224_hasher = std.crypto.hash.sha2.Sha224.init(.{});
    sha224_hasher.update(bytes);
    sha224_hasher.final(&sha224_digest);
    const sha224_hex = std.fmt.bytesToHex(sha224_digest, .lower);

    for ([_][]const u8{ "sha", "sha1" }) |kind| {
        const kind_z = try model.dupZ(testing.allocator, kind);
        defer testing.allocator.free(kind_z);
        const value_z = try model.dupZ(testing.allocator, sha1_hex[0..]);
        defer testing.allocator.free(value_z);
        try testing.expect(digestMatches(
            .{
                .pszType = kind_z.ptr,
                .pszValue = value_z.ptr,
            },
            bytes,
        ));
    }
    const sha224_kind_z = try model.dupZ(testing.allocator, "sha224");
    defer testing.allocator.free(sha224_kind_z);
    const sha224_value_z = try model.dupZ(
        testing.allocator,
        sha224_hex[0..],
    );
    defer testing.allocator.free(sha224_value_z);
    try testing.expect(digestMatches(
        .{
            .pszType = sha224_kind_z.ptr,
            .pszValue = sha224_value_z.ptr,
        },
        bytes,
    ));
}
