const std = @import("std");
const model = @import("model.zig");

pub fn digestMatches(checksum: model.Checksum, bytes: []const u8) bool {
    const checksum_type = model.spanZ(checksum.pszType) orelse return false;
    const expected = model.spanZ(checksum.pszValue) orelse return false;
    return switch (hashKind(checksum_type) orelse return false) {
        .md5 => blk: {
            var digest: [16]u8 = undefined;
            var hasher = std.crypto.hash.Md5.init(.{});
            hasher.update(bytes);
            hasher.final(&digest);
            const hex = std.fmt.bytesToHex(digest, .lower);
            break :blk std.ascii.eqlIgnoreCase(expected, &hex);
        },
        .sha1 => blk: {
            var digest: [20]u8 = undefined;
            var hasher = std.crypto.hash.Sha1.init(.{});
            hasher.update(bytes);
            hasher.final(&digest);
            const hex = std.fmt.bytesToHex(digest, .lower);
            break :blk std.ascii.eqlIgnoreCase(expected, &hex);
        },
        .sha224 => blk: {
            var digest: [28]u8 = undefined;
            var hasher = std.crypto.hash.sha2.Sha224.init(.{});
            hasher.update(bytes);
            hasher.final(&digest);
            const hex = std.fmt.bytesToHex(digest, .lower);
            break :blk std.ascii.eqlIgnoreCase(expected, &hex);
        },
        .sha256 => blk: {
            var digest: [32]u8 = undefined;
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update(bytes);
            hasher.final(&digest);
            const hex = std.fmt.bytesToHex(digest, .lower);
            break :blk std.ascii.eqlIgnoreCase(expected, &hex);
        },
        .sha384 => blk: {
            var digest: [48]u8 = undefined;
            var hasher = std.crypto.hash.sha2.Sha384.init(.{});
            hasher.update(bytes);
            hasher.final(&digest);
            const hex = std.fmt.bytesToHex(digest, .lower);
            break :blk std.ascii.eqlIgnoreCase(expected, &hex);
        },
        .sha512 => blk: {
            var digest: [64]u8 = undefined;
            var hasher = std.crypto.hash.sha2.Sha512.init(.{});
            hasher.update(bytes);
            hasher.final(&digest);
            const hex = std.fmt.bytesToHex(digest, .lower);
            break :blk std.ascii.eqlIgnoreCase(expected, &hex);
        },
    };
}

const HashKind = enum {
    md5,
    sha1,
    sha224,
    sha256,
    sha384,
    sha512,
};

fn hashKind(raw: []const u8) ?HashKind {
    if (std.ascii.eqlIgnoreCase(raw, "md5")) return .md5;
    if (std.ascii.eqlIgnoreCase(raw, "sha")) return .sha1;
    if (std.ascii.eqlIgnoreCase(raw, "sha1")) return .sha1;
    if (std.ascii.eqlIgnoreCase(raw, "sha224")) return .sha224;
    if (std.ascii.eqlIgnoreCase(raw, "sha256")) return .sha256;
    if (std.ascii.eqlIgnoreCase(raw, "sha384")) return .sha384;
    if (std.ascii.eqlIgnoreCase(raw, "sha512")) return .sha512;
    return null;
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
