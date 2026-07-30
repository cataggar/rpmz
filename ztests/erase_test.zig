//! Erase behaviour, ported from `pytests/tests/test_erase.py`.
//!
//! The pytest module needs a teardown fixture to remove whatever a test left in
//! the host rpmdb. Here each test owns its root, so there is nothing to undo.
//!
//! `test_erase_memcheck` is not ported: valgrind coverage stays in pytest,
//! which already knows how to find and configure it.

const std = @import("std");
const harness = @import("harness.zig");

const multiversion = "tdnf-test-multiversion";
const multiversion_lower = "1.0.1-1";

/// `ERROR_TDNF_CLI_NO_ARGS`, as the shell sees it.
const no_args_code: u8 = 1001 % 256;
/// `ERROR_TDNF_NO_MATCH`.
const no_match_code: u8 = 1011 % 256;

fn eraseBestEffort(root: *harness.Root) void {
    var result = root.run(&.{ "erase", "-y", multiversion }) catch return;
    defer result.deinit();
}

test "erase with no argument is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{"erase"});
    defer result.deinit();
    try result.expectCode(no_args_code);
}

test "erase of an unknown package reports no match" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "erase", "invalid_package" });
    defer result.deinit();
    try result.expectCode(no_match_code);
}

test "a package erases by name with a version suffix" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root);

    const versioned = multiversion ++ "-" ++ multiversion_lower;

    var install = try root.run(&.{ "install", "-y", "--nogpgcheck", versioned });
    defer install.deinit();
    try install.expectOk();
    try std.testing.expect(try root.isInstalled(multiversion));

    var erase = try root.run(&.{ "erase", "-y", versioned });
    defer erase.deinit();
    try erase.expectOk();
    try std.testing.expect(!try root.isInstalled(multiversion));
}

test "a package erases by name without a version suffix" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root);

    var install = try root.run(&.{ "install", "-y", "--nogpgcheck", multiversion });
    defer install.deinit();
    try install.expectOk();
    try std.testing.expect(try root.isInstalled(multiversion));

    var erase = try root.run(&.{ "erase", "-y", multiversion });
    defer erase.deinit();
    try erase.expectOk();
    try std.testing.expect(!try root.isInstalled(multiversion));
}
