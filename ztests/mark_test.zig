//! Mark install/remove behaviour, ported from `pytests/tests/test_mark.py`.

const std = @import("std");
const harness = @import("harness.zig");

const leaf = "tdnf-test-cleanreq-leaf1";
const required = "tdnf-test-cleanreq-required";

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

test "mark install keeps an autoinstalled dependency" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, leaf);
    try std.testing.expect(try root.isInstalled(required));

    var mark = try root.run(&.{ "mark", "install", required });
    defer mark.deinit();
    try mark.expectOk();

    var result = try root.run(&.{ "-y", "autoremove", leaf });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf));
    try std.testing.expect(try root.isInstalled(required));
}

test "mark remove lets autoremove shed a user-installed dependency" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, required);
    try install(&root, leaf);
    try std.testing.expect(try root.isInstalled(required));

    var mark = try root.run(&.{ "mark", "remove", required });
    defer mark.deinit();
    try mark.expectOk();

    var result = try root.run(&.{ "-y", "autoremove", leaf });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf));
    try std.testing.expect(!try root.isInstalled(required));
}
