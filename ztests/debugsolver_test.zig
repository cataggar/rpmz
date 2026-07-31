//! `--debugsolver` acceptance.
//!
//! The flag is documented in `tools/cli/lib/help.txt` and parsed in
//! `tools/cli/lib/parseargs.zig`, so what users depend on is that passing it
//! is accepted and does not change the outcome of the command. That is the
//! contract pinned here, together with the notice that replaced the data:
//! there is no libsolv solve left to dump, and saying so beats doing nothing.
//!
//! What is deliberately *not* pinned is the `debugdata` directory libsolv's
//! `testcase_write` used to drop into the working directory: it is an artifact
//! of one solver implementation, no test has ever asserted it exists, and
//! `pytests/tests/test_install.py` only ever deleted it. The directory is
//! removed here for the same reason pytest removed it -- every test in this
//! binary shares one working directory.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

const single = "tdnf-test-one";
const notice = "solver debug data is no longer produced";

fn clearDebugData() void {
    std.Io.Dir.cwd().deleteTree(io, "debugdata") catch {};
}

test "--debugsolver is accepted and does not change the transaction" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer clearDebugData();

    var result = try root.run(&.{
        "install", "-y", "--nogpgcheck", "--debugsolver", single,
    });
    defer result.deinit();
    try result.expectOk();
    try result.expectStderrContains(notice);
    try std.testing.expect(try root.isInstalled(single));

    var removal = try root.run(&.{ "remove", "-y", "--debugsolver", single });
    defer removal.deinit();
    try removal.expectOk();
    try std.testing.expect(!try root.isInstalled(single));
}

test "--debugsolver does not mask a solver failure" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer clearDebugData();

    var result = try root.run(&.{
        "install", "-y", "--nogpgcheck", "--debugsolver", "tdnf-missing-dep",
    });
    defer result.deinit();
    // `ERROR_TDNF_SOLV_FAILED` surfaces to the shell as `ERROR_TDNF_SOLV`.
    try result.expectCode(1301 % 256);
    try result.expectStderrContains("nothing provides missing");
    try std.testing.expect(!try root.isInstalled("tdnf-missing-dep"));
}

test "the transaction runs without --debugsolver and prints no notice" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer clearDebugData();

    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", single });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(!result.stderrContains(notice));
}
