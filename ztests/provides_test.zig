//! Provides command behaviour, ported from `pytests/tests/test_provides.py`.

const std = @import("std");
const harness = @import("harness.zig");

/// `ERROR_TDNF_CLI_PROVIDES_EXPECT_ARG`.
const provides_expect_arg_code: u8 = 907 % 256;
const file_owner_package = "tdnf-test-one";
const provided_file = "/lib/systemd/system/tdnf-test-one.service";
const provided_file_substring = "tdnf-test-one.service";

test "provides with no argument is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{"provides"});
    defer result.deinit();
    try result.expectCode(provides_expect_arg_code);
    try result.expectStderrContains("Need an item to match");
}

test "provides finds a package capability" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "provides", file_owner_package });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(file_owner_package);
}

test "provides reports no data for an unknown capability" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "provides", "invalid_pkg_name" });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("No data available");
}

test "provides reports no data for a file path substring" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "provides", provided_file_substring });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("No data available");
}

test "provides finds an exact file path" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "provides", provided_file });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(file_owner_package);
}
