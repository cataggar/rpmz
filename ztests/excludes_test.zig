//! Exclude policy behaviour, ported from `pytests/tests/test_excludes.py`.
//!
//! `test_with_minversion_existing` is not ported yet: the pytest command uses
//! `--exclude=` with no value, which rpmz rejects during argument parsing
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

// An exclude that names the requested package is short-circuited by the job
// builder, so it never reaches the package visibility list. Excluding a
// *dependency* is what forces the solver to see the package as hidden, which is
// why every test below excludes `required` and asks for `leaf`.
test "a glob exclude pattern hides a matching dependency" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, leaf);
    defer eraseBestEffort(&root, required);

    var result = try root.run(&.{
        "install",
        "--exclude=tdnf-test-cleanreq-requir*",
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

// Overlapping patterns select the same package more than once. The native
// visibility list rejects a duplicate entry outright, so a lost dedup shows up
// here as a hard error rather than as a subtly wrong package set.
test "overlapping exclude patterns select the same dependency only once" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, leaf);
    defer eraseBestEffort(&root, required);

    var result = try root.run(&.{
        "install",
        "--exclude=" ++ required,
        "--exclude=tdnf-test-cleanreq-requir*",
        "--exclude=*-cleanreq-required",
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

// The exclude list and the minversion list are built independently and then
// merged; here they overlap on `multiversion_lower`, which the same duplicate
// check would reject.
test "an exclude overlapping a minversion selects the package only once" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    try root.setMainOption("minversions", multiversion ++ "=" ++ multiversion_higher);

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

// Without the exclude the same minversion setting must still take effect, so
// the test above cannot pass merely because minversions were dropped.
test "a minversion alone hides the lower version" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    try root.setMainOption("minversions", multiversion ++ "=" ++ multiversion_higher);

    var result = try root.run(&.{
        "install",
        "-y",
        "--nogpgcheck",
        multiversion ++ "-" ++ multiversion_lower,
    });
    defer result.deinit();
    try result.expectCode(solv_code);
    try std.testing.expect(!try root.isInstalled(multiversion));
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
