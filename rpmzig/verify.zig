//! Typed verifier used only by the standalone `tdnf-rpm-verify` helper.
//!
//! libtdnf verifies packages through `rpmdb.zig`'s configured integrity
//! path, which evaluates every signature candidate.  This module preserves
//! the standalone helper's historical single detached-signature policy.

const std = @import("std");
const pkgfile = @import("rpm_pkgfile");
const armor = @import("pgp/armor.zig");
const pgp = @import("pgp/verify.zig");

pub const Status = pgp.Status;

pub fn verifyDetached(
    allocator: std.mem.Allocator,
    signature: []const u8,
    signed_bytes: []const u8,
    keys: []const []const u8,
) Status {
    return pgp.verifyDetached(allocator, signature, signed_bytes, keys);
}

pub fn verifyDetachedArmored(
    allocator: std.mem.Allocator,
    armored_signature: []const u8,
    signed_bytes: []const u8,
    keys: []const []const u8,
) Status {
    var decoded = armor.decode(allocator, armored_signature) catch return .bad;
    defer decoded.deinit();
    return verifyDetached(allocator, decoded.bytes, signed_bytes, keys);
}

pub fn verifyRpm(
    allocator: std.mem.Allocator,
    rpm: *const pkgfile.RpmFile,
    keys: []const []const u8,
) Status {
    const signed = rpm.signatureSlice() orelse return .no_sig;
    return verifyDetached(
        allocator,
        signed.sig,
        signed.signed,
        keys,
    );
}

test "typed verifier accepts configured key" {
    const signature = @embedFile("pgp/testdata/rsa2048-sig.bin");
    const signed_bytes = @embedFile("pgp/testdata/rsa2048-data.bin");
    const key = @embedFile("pgp/testdata/rsa2048-pubkey.bin");
    const keys = [_][]const u8{key};

    try std.testing.expectEqual(
        Status.ok,
        verifyDetached(
            std.testing.allocator,
            signature,
            signed_bytes,
            &keys,
        ),
    );
}

test "typed verifier reports no matching key" {
    const signature = @embedFile("pgp/testdata/rsa2048-sig.bin");
    const signed_bytes = @embedFile("pgp/testdata/rsa2048-data.bin");
    const wrong_key = @embedFile("pgp/testdata/microsoft-rpm-key.bin");
    const keys = [_][]const u8{wrong_key};

    try std.testing.expectEqual(
        Status.no_key,
        verifyDetached(
            std.testing.allocator,
            signature,
            signed_bytes,
            &keys,
        ),
    );
}
