//! Glob package matching behaviour, ported from `pytests/tests/test_glob.py`.

const std = @import("std");
const harness = @import("harness.zig");

const multi = "tdnf-multi";
const multiversion = "tdnf-test-multiversion";

test "install accepts a package glob" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", "tdnf*multi*" });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(try root.isInstalled(multi));
    try std.testing.expect(try root.isInstalled(multiversion));
}

test "remove accepts a package glob" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var install = try root.run(&.{ "install", "-y", "--nogpgcheck", multiversion });
    defer install.deinit();
    try install.expectOk();
    try std.testing.expect(try root.isInstalled(multiversion));

    var result = try root.run(&.{ "remove", "-y", "tdnf*multi*" });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(multiversion));
}

test "remove glob works with all repos disabled" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var install = try root.run(&.{ "install", "-y", "--nogpgcheck", "tdnf*multi*" });
    defer install.deinit();
    try install.expectOk();
    try std.testing.expect(try root.isInstalled(multi));
    try std.testing.expect(try root.isInstalled(multiversion));

    var result = try root.run(&.{ "remove", "-y", "tdnf*multi*", "--disablerepo=*" });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(multi));
    try std.testing.expect(!try root.isInstalled(multiversion));
}
