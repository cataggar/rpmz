//! Update behaviour, ported from `pytests/tests/test_update.py`.

const std = @import("std");
const harness = @import("harness.zig");

const single = "tdnf-test-one";
const multiversion = "tdnf-test-multiversion";
const multiversion_lower = "1.0.1-1";
const multiversion_higher = "1.0.2-1";

/// `ERROR_TDNF_NO_MATCH`.
const no_match_code: u8 = 1011 % 256;

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

test "update of an unknown package reports no match" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "update", "-y", "invalid_package" });
    defer result.deinit();
    try result.expectCode(no_match_code);
}

test "update of a single-version package has nothing to do" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, single);

    var result = try root.run(&.{ "update", "-y", single });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("Nothing to do");
}

test "update walks a multi-version package to the newest version" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, multiversion ++ "-" ++ multiversion_lower);
    try std.testing.expect(try root.isInstalledVersion(multiversion, multiversion_lower));

    var update = try root.run(&.{ "update", "-y", "--nogpgcheck", multiversion });
    defer update.deinit();
    try update.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multiversion, multiversion_higher));

    var again = try root.run(&.{ "update", "-y", multiversion });
    defer again.deinit();
    try again.expectOk();
    try again.expectStderrContains("Nothing to do");
}

test "update accepts a partial EVR target" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, multiversion ++ "-" ++ multiversion_lower);

    var result = try root.run(&.{ "update", "-y", "--nogpgcheck", multiversion ++ ">=1.0.2" });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multiversion, multiversion_higher));
}
