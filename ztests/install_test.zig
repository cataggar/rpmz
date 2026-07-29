//! Install behaviour, ported from `pytests/tests/test_install.py`.
//!
//! Each test takes its own install root, so none of them has to erase what a
//! neighbour left behind — the cleanup dance the pytest versions perform is
//! simply absent here.

const std = @import("std");
const harness = @import("harness.zig");

const multiversion = "tdnf-test-multiversion";
const multiversion_lower = "tdnf-test-multiversion-1.0.1-1";
const dummy_requires = "tdnf-test-dummy-requires";

/// `ERROR_TDNF_CLI_NO_ARGS`, as the shell sees it.
const no_args_code: u8 = 1001 % 256;
/// `ERROR_TDNF_NO_MATCH`.
const no_match_code: u8 = 1011 % 256;

test "install with no argument is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{"install"});
    defer result.deinit();
    try result.expectCode(no_args_code);
}

test "install of an unknown package reports no match" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "install", "invalid_package" });
    defer result.deinit();
    try result.expectCode(no_match_code);
}

test "a package installs with and without a version suffix" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();

    for ([_][]const u8{ multiversion, multiversion_lower }) |spec| {
        var root = try h.root();
        defer root.deinit();

        var result = try root.run(&.{ "install", "-y", "--nogpgcheck", spec });
        defer result.deinit();
        try result.expectOk();

        try std.testing.expect(try root.isInstalled(multiversion));
    }
}

test "an unsatisfiable requirement names what is missing" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "install", "-y", dummy_requires });
    defer result.deinit();

    try std.testing.expect(result.code != 0);
    try std.testing.expect(result.stderrContains("nothing provides"));
}

test "testonly resolves the transaction without installing it" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{
        "install", "-y", "--nogpgcheck", "--testonly", multiversion,
    });
    defer result.deinit();
    try result.expectOk();

    try std.testing.expect(!try root.isInstalled(multiversion));
}

test "a second install of the same package has nothing to do" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var first = try root.run(&.{ "install", "-y", "--nogpgcheck", multiversion });
    defer first.deinit();
    try first.expectOk();

    var second = try root.run(&.{ "install", "-y", "--nogpgcheck", multiversion });
    defer second.deinit();
    try second.expectOk();
    try second.expectStderrContains("Nothing to do");
}

test "erase removes what install added" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var install = try root.run(&.{ "install", "-y", "--nogpgcheck", multiversion });
    defer install.deinit();
    try install.expectOk();
    try std.testing.expect(try root.isInstalled(multiversion));

    var erase = try root.run(&.{ "erase", "-y", multiversion });
    defer erase.deinit();
    try erase.expectOk();
    try std.testing.expect(!try root.isInstalled(multiversion));
}
