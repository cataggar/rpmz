//! Provides command behaviour, ported from `pytests/tests/test_provides.py`.

const std = @import("std");
const harness = @import("harness.zig");

/// `ERROR_TDNF_CLI_PROVIDES_EXPECT_ARG`.
const provides_expect_arg_code: u8 = 907 % 256;

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

    var result = try root.run(&.{ "provides", "tdnf" });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains("tdnf");
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
