//! Exclude policy behaviour, ported from `pytests/tests/test_excludes.py`.
//!
//! `test_with_minversion_existing` is not ported yet: the pytest command uses
//! `--exclude=` with no value, which tdnf rejects during argument parsing
//! before the minversion setup can matter, and pytest masks that by never
//! asserting the exit code.

const std = @import("std");
const harness = @import("harness.zig");

const multiversion = "tdnf-test-multiversion";
const multiversion_lower = "1.0.1-1";
const multiversion_higher = "1.0.2-1";
const leaf = "tdnf-test-cleanreq-leaf1";
const required = "tdnf-test-cleanreq-required";

/// `ERROR_TDNF_SOLV`, as the shell sees it.
const solv_code: u8 = 1301 % 256;

fn eraseBestEffort(root: *harness.Root, name: []const u8) void {
    var result = root.run(&.{ "erase", "-y", name }) catch return;
    defer result.deinit();
}

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

test "an excluded package is not installed even with a version suffix" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    var result = try root.run(&.{
        "install",
        "--exclude=" ++ multiversion,
        "-y",
        "--nogpgcheck",
        multiversion ++ "-" ++ multiversion_lower,
    });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("Nothing to do");
    try std.testing.expect(!try root.isInstalled(multiversion));
}

test "an excluded package is not installed by name" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    var result = try root.run(&.{
        "install",
        "--exclude=" ++ multiversion,
        "-y",
        "--nogpgcheck",
        multiversion,
    });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("Nothing to do");
    try std.testing.expect(!try root.isInstalled(multiversion));
}

test "a package with an excluded dependency is not installed" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, leaf);
    defer eraseBestEffort(&root, required);

    var result = try root.run(&.{
        "install",
        "--exclude=" ++ required,
        "-y",
        "--nogpgcheck",
        leaf,
    });
    defer result.deinit();
    try result.expectCode(solv_code);
    try result.expectStderrContains(required ++ "-0:1.0.1-3");
    try result.expectStderrContains("is disabled");
    try std.testing.expect(!try root.isInstalled(leaf));
    try std.testing.expect(!try root.isInstalled(required));
}

test "update skips an excluded package" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    try install(&root, multiversion ++ "-" ++ multiversion_lower);
    try std.testing.expect(try root.isInstalledVersion(multiversion, multiversion_lower));

    var result = try root.run(&.{
        "update",
        "--exclude=" ++ multiversion,
        "-y",
        "--nogpgcheck",
        multiversion ++ "-" ++ multiversion_higher,
    });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("Nothing to do");
    try std.testing.expect(!try root.isInstalledVersion(multiversion, multiversion_higher));
    try std.testing.expect(try root.isInstalledVersion(multiversion, multiversion_lower));
}

test "remove skips an excluded package" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    try install(&root, multiversion);
    try std.testing.expect(try root.isInstalled(multiversion));

    var result = try root.run(&.{
        "remove",
        "--exclude=" ++ multiversion,
        "-y",
        "--nogpgcheck",
        multiversion,
    });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains("Nothing to do");
    try std.testing.expect(try root.isInstalled(multiversion));
}
