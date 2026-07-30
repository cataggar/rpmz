//! Autoremove and clean-requirements behaviour, ported from
//! `pytests/tests/test_autoremove.py`.
//!
//! The pytest module keeps a `/tmp/cleanreq` directory for the config variants
//! and erases three packages after every test. Here the config lives in the
//! test's own root and the packages disappear with it.

const std = @import("std");
const harness = @import("harness.zig");

const leaf1 = "tdnf-test-cleanreq-leaf1";
const leaf2 = "tdnf-test-cleanreq-leaf2";
const required = "tdnf-test-cleanreq-required";

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

fn cleanup(root: *harness.Root) void {
    for ([_][]const u8{ leaf1, leaf2, required }) |name| {
        var result = root.run(&.{ "erase", "-y", name }) catch continue;
        result.deinit();
    }
}

test "autoremoving a leaf takes its dependency with it" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try install(&root, leaf1);
    try std.testing.expect(try root.isInstalled(required));

    var result = try root.run(&.{ "-y", "autoremove", leaf1 });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(!try root.isInstalled(required));
}

test "a dependency installed first is kept because it is user installed" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try install(&root, required);
    try install(&root, leaf1);

    var result = try root.run(&.{ "-y", "autoremove", leaf1 });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(try root.isInstalled(required));
}

test "installing an already-pulled-in dependency marks it user installed" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try install(&root, leaf1);
    try install(&root, required);

    var result = try root.run(&.{ "-y", "autoremove", leaf1 });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(try root.isInstalled(required));
}

test "a shared dependency survives until its last holder goes" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try install(&root, leaf1);
    try install(&root, leaf2);

    var first = try root.run(&.{ "-y", "autoremove", leaf1 });
    defer first.deinit();
    try first.expectOk();
    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(try root.isInstalled(required));

    var second = try root.run(&.{ "-y", "autoremove", leaf2 });
    defer second.deinit();
    try second.expectOk();
    try std.testing.expect(!try root.isInstalled(required));
}

test "clean_requirements_on_remove makes a plain remove clean up" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try root.setMainOption("clean_requirements_on_remove", "1");
    try install(&root, leaf1);
    try std.testing.expect(try root.isInstalled(required));

    var result = try root.run(&.{ "-y", "remove", leaf1 });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(!try root.isInstalled(required));
}

test "without clean_requirements_on_remove a plain remove keeps the dependency" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try root.setMainOption("clean_requirements_on_remove", "0");
    try install(&root, leaf1);
    try std.testing.expect(try root.isInstalled(required));

    var result = try root.run(&.{ "-y", "remove", leaf1 });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(try root.isInstalled(required));
}

test "--noautoremove overrides clean_requirements_on_remove" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try root.setMainOption("clean_requirements_on_remove", "1");
    try install(&root, leaf1);
    try std.testing.expect(try root.isInstalled(required));

    var result = try root.run(&.{ "-y", "--noautoremove", "remove", leaf1 });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(try root.isInstalled(required));
}

test "autoremove cleans up even when the config disables it" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try root.setMainOption("clean_requirements_on_remove", "0");
    try install(&root, leaf1);
    try std.testing.expect(try root.isInstalled(required));

    var result = try root.run(&.{ "-y", "autoremove", leaf1 });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(!try root.isInstalled(required));
}

test "autoremove with no argument sheds everything unneeded" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try install(&root, leaf1);
    try std.testing.expect(try root.isInstalled(required));

    var removed = try root.run(&.{ "-y", "remove", "--noautoremove", leaf1 });
    defer removed.deinit();
    try removed.expectOk();
    try std.testing.expect(try root.isInstalled(required));

    var result = try root.run(&.{ "-y", "autoremove" });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(leaf1));
    try std.testing.expect(!try root.isInstalled(required));
}

test "autoremove with no argument keeps what a user-installed package needs" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer cleanup(&root);

    try install(&root, leaf1);
    try std.testing.expect(try root.isInstalled(required));

    var result = try root.run(&.{ "-y", "autoremove" });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(try root.isInstalled(leaf1));
    try std.testing.expect(try root.isInstalled(required));
}
