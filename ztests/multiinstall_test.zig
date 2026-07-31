//! Install-only (multiversion) behaviour, ported from
//! `pytests/tests/test_multiinstall.py`.
//!
//! `--debugsolver` is dropped from the eviction test: it writes a `debugdata`
//! directory into the working directory, which every test in the binary
//! shares, and it is not what any of these assertions are about.

const std = @import("std");
const harness = @import("harness.zig");

const multi = "tdnf-multi";
/// Sorted ascending.
const versions = [_][]const u8{ "1.0.1-1", "1.0.1-2", "1.0.1-3", "1.0.1-4" };

/// `ERROR_TDNF_INSTALLONLY_LIMIT_EXCEEDED`, as the shell sees it.
const installonly_limit_code: u8 = 1530 % 256;

fn installOnlyRoot(h: *harness.Harness) !harness.Root {
    var root = try h.root();
    errdefer root.deinit();
    try root.setMainOption("installonlypkgs", multi);
    try root.setMainOption("installonly_limit", "3");
    return root;
}

fn installVersion(root: *harness.Root, version: ?[]const u8) !void {
    var buffer: [64]u8 = undefined;
    const spec = if (version) |v|
        try std.fmt.bufPrint(&buffer, "{s}={s}", .{ multi, v })
    else
        multi;

    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", spec });
    defer result.deinit();
    try result.expectOk();
}

test "an install-only package can be installed twice" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, null);
    try std.testing.expect(try root.isInstalledVersion(multi, versions[3]));

    try installVersion(&root, versions[0]);
    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(try root.isInstalledVersion(multi, versions[3]));
}

test "an install-only package can be installed three times" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, null);
    try installVersion(&root, versions[0]);
    try installVersion(&root, versions[1]);

    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(try root.isInstalledVersion(multi, versions[1]));
    try std.testing.expect(try root.isInstalledVersion(multi, versions[3]));
}

test "the fourth install evicts the oldest instance" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, null);
    try installVersion(&root, versions[0]);
    try installVersion(&root, versions[1]);
    try installVersion(&root, versions[2]);

    try std.testing.expect(try root.isInstalledVersion(multi, versions[2]));
    // installonly_limit is 3, so the latest -- installed first -- is gone.
    try std.testing.expect(!try root.isInstalledVersion(multi, versions[3]));
}

test "upgrading an install-only package adds nothing while under the limit" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, versions[0]);

    var named = try root.run(&.{
        "upgrade", "-y", "--nogpgcheck", "--testonly", "--noautoremove", multi,
    });
    defer named.deinit();
    try named.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(!try root.isInstalledVersion(multi, versions[3]));

    var all = try root.run(&.{
        "upgrade", "-y", "--nogpgcheck", "--testonly", "--noautoremove",
    });
    defer all.deinit();
    try all.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(!try root.isInstalledVersion(multi, versions[3]));

    // Lowering the limit below the installed count must evict the excess
    // versions; the solver derives those evictions from installonly_limit.
    try root.setMainOption("installonly_limit", "1");
    var lowered = try root.run(&.{
        "upgrade", "-y", "--nogpgcheck", "--testonly", "--noautoremove", multi,
    });
    defer lowered.deinit();
    try lowered.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(!try root.isInstalledVersion(multi, versions[3]));
}

// Eviction can only free instances that already exist, so a single request
// that installs more new instances than `installonly_limit` allows cannot be
// brought back under the limit by evicting: the request is refused with
// `ERROR_TDNF_INSTALLONLY_LIMIT_EXCEEDED` and nothing changes.
//
// This is the terminal outcome of the limit check and its bounded retry --
// the other direction from "the fourth install evicts the oldest instance",
// which exercises the retry succeeding. Nothing pinned it before.
test "an install that eviction cannot bring under the limit is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();
    try root.setMainOption("installonly_limit", "1");

    try installVersion(&root, versions[0]);
    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));

    // One installed instance plus two new ones is three, and evicting the one
    // installed instance still leaves two against a limit of one.
    var result = try root.run(&.{
        "install",                       "-y",
        "--nogpgcheck",                  multi ++ "=" ++ versions[1],
        multi ++ "=" ++ versions[2],
    });
    defer result.deinit();
    try result.expectCode(installonly_limit_code);

    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(!try root.isInstalledVersion(multi, versions[1]));
    try std.testing.expect(!try root.isInstalledVersion(multi, versions[2]));
}

test "removing without a version removes every instance" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, versions[0]);
    try installVersion(&root, versions[1]);

    var result = try root.run(&.{ "remove", "-y", multi });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(!try root.isInstalledVersion(multi, versions[1]));
}

test "removing with a version removes only that instance" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, versions[0]);
    try installVersion(&root, versions[1]);

    var result = try root.run(&.{ "remove", "-y", multi ++ "=" ++ versions[0] });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(try root.isInstalledVersion(multi, versions[1]));
}

test "reinstalling one instance leaves the others intact" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, versions[0]);
    try installVersion(&root, versions[1]);

    var result = try root.run(&.{
        "reinstall", "-y", "--nogpgcheck", multi ++ "=" ++ versions[0],
    });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));
    try std.testing.expect(try root.isInstalledVersion(multi, versions[1]));
}

test "autoremove keeps both instances when the package is user installed" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, versions[0]);

    var upgrade = try root.run(&.{ "upgrade", "-y", "--nogpgcheck" });
    defer upgrade.deinit();
    try upgrade.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multi, versions[3]));

    var result = try root.run(&.{ "autoremove", "-y" });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(try root.isInstalledVersion(multi, versions[3]));
    try std.testing.expect(try root.isInstalledVersion(multi, versions[0]));
}

test "autoremove sheds both instances when the package is auto installed" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try installOnlyRoot(&h);
    defer root.deinit();

    try installVersion(&root, versions[0]);

    var mark = try root.run(&.{ "mark", "remove", multi });
    defer mark.deinit();
    try mark.expectOk();

    var upgrade = try root.run(&.{ "upgrade", "-y", "--nogpgcheck" });
    defer upgrade.deinit();
    try upgrade.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multi, versions[3]));

    var result = try root.run(&.{ "autoremove", "-y" });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalledVersion(multi, versions[3]));
    try std.testing.expect(!try root.isInstalledVersion(multi, versions[0]));
}
