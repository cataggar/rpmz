//! Whatprovides command behaviour, ported from
//! `pytests/tests/test_whatprovides.py`.

const std = @import("std");
const harness = @import("harness.zig");

const package = "tdnf-test-one";
const provided_file = "/lib/systemd/system/tdnf-test-one.service";

/// `ERROR_TDNF_CLI_PROVIDES_EXPECT_ARG`.
const provides_expect_arg_code: u8 = 907 % 256;

fn install(root: *harness.Root) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", package });
    defer result.deinit();
    try result.expectOk();
}

test "whatprovides with no argument is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{"whatprovides"});
    defer result.deinit();
    try result.expectCode(provides_expect_arg_code);
    try result.expectStderrContains("Need an item to match");
}

test "whatprovides reports no data for an unknown capability" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "whatprovides", "invalid_arg" });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("No data available");
}

test "whatprovides finds a file in the repository" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "whatprovides", provided_file });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(package);
    try result.expectStdoutContains("Repo");
    try result.expectStdoutContains("photon-test");
    try std.testing.expect(!try root.isInstalled(package));
}

test "whatprovides prefers the installed package for a provided file" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root);
    try std.testing.expect(try root.isInstalled(package));

    var result = try root.run(&.{ "whatprovides", provided_file });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(package);
    try result.expectStdoutContains("Repo");
    try result.expectStdoutContains("@System");
}
