//! `--assumeno` behaviour, ported from `pytests/tests/test_assumeno.py`.

const std = @import("std");
const harness = @import("harness.zig");

const package = "tdnf-test-one";

/// `ERROR_TDNF_OPERATION_ABORTED`, as the shell sees it.
const operation_aborted_code: u8 = 1032 % 256;

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

test "--assumeno refuses an install transaction" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "--assumeno", "install", package });
    defer result.deinit();
    try result.expectCode(operation_aborted_code);

    try std.testing.expect(!try root.isInstalled(package));
}

test "--assumeno refuses an erase transaction" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, package);
    try std.testing.expect(try root.isInstalled(package));

    var result = try root.run(&.{ "--assumeno", "erase", package });
    defer result.deinit();
    try result.expectCode(operation_aborted_code);

    try std.testing.expect(try root.isInstalled(package));
}
