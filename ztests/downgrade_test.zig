//! Downgrade behaviour, ported from `pytests/tests/test_downgrade.py`.

const std = @import("std");
const harness = @import("harness.zig");

const multiversion = "tdnf-test-multiversion";
const multiversion_lower = "1.0.1-1";

/// `ERROR_TDNF_NO_MATCH`.
const no_match_code: u8 = 1011 % 256;
/// `ERROR_TDNF_INVALID_INPUT` - what an unanswered y/n prompt reports.
const invalid_input_code: u8 = 1033 % 256;

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

fn eraseBestEffort(root: *harness.Root) void {
    var result = root.run(&.{ "erase", "-y", multiversion }) catch return;
    defer result.deinit();
}

test "downgrade with no argument says so when there is no path down" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root);

    // The pytest version asserts `ERROR_TDNF_NO_MATCH` here, but that is an
    // artifact of running against a populated host rpmdb: none of its hundreds
    // of packages exist in the test repository. With a root holding only the
    // lowest version there is a package to consider and no version to move to,
    // which is the case the command is actually about.
    try install(&root, multiversion ++ "-" ++ multiversion_lower);

    var result = try root.run(&.{"downgrade"});
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("There is no downgrade path for " ++ multiversion);
}

test "downgrade walks the package down and then runs out of path" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root);

    try install(&root, multiversion);

    // Without -y the prompt goes unanswered, which is an input error, but the
    // plan is still printed.
    var prompted = try root.run(&.{ "downgrade", multiversion });
    defer prompted.deinit();
    try prompted.expectCode(invalid_input_code);
    // The header and the package sit on separate lines; the pytest version
    // only matches "Downgrading: <pkg>" because it joins stdout with spaces.
    try prompted.expectStdoutContains("Downgrading:");
    try prompted.expectStdoutContains(multiversion);

    var downgraded = try root.run(&.{ "downgrade", "-y", multiversion });
    defer downgraded.deinit();
    try downgraded.expectOk();
    try downgraded.expectStdoutContains("Downgrading:");
    try downgraded.expectStdoutContains(multiversion);

    var again = try root.run(&.{ "downgrade", "-y", multiversion });
    defer again.deinit();
    try again.expectOk();
    try again.expectStderrContains("There is no downgrade path for " ++ multiversion);
}

test "downgrade succeeds from the lowest installed version" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root);

    try install(&root, multiversion ++ "-" ++ multiversion_lower);

    var result = try root.run(&.{ "downgrade", "-y", multiversion });
    defer result.deinit();
    try result.expectOk();
}

test "downgrade accepts an explicit lower version" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root);

    try install(&root, multiversion);

    var result = try root.run(&.{
        "downgrade",
        "-y",
        multiversion ++ "-" ++ multiversion_lower,
    });
    defer result.deinit();
    try result.expectOk();
}

test "downgrade accepts a partial EVR target" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root);

    try install(&root, multiversion);

    var result = try root.run(&.{ "downgrade", "-y", multiversion ++ "<=1.0.1" });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multiversion, multiversion_lower));
}

test "downgrade to a version that does not exist reports no match" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "downgrade", "-y", multiversion ++ "-123.123.123" });
    defer result.deinit();
    try result.expectCode(no_match_code);
}

test "downgrade of an unknown package reports no match" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "downgrade", "-y", "invalid_pkg_name" });
    defer result.deinit();
    try result.expectCode(no_match_code);
}
