//! Protected package behaviour, ported from `pytests/tests/test_protected.py`.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

const single = "tdnf-test-one";
const leaf = "tdnf-test-cleanreq-leaf1";
const required = "tdnf-test-cleanreq-required";
const multiversion = "tdnf-test-multiversion";
const obsoleted_versioned = "tdnf-test-dummy-obsoleted=0.1";
const obsoleted = "tdnf-test-dummy-obsoleted";
const obsoleting = "tdnf-test-dummy-obsoleting";

/// `ERROR_TDNF_PROTECTED`, as the shell sees it.
const protected_code: u8 = 1030 % 256;
/// `ERROR_TDNF_SOLV`, as the shell sees it.
const solv_code: u8 = 1301 % 256;

fn eraseBestEffort(root: *harness.Root, name: []const u8) void {
    var result = root.run(&.{ "erase", "-y", name }) catch return;
    defer result.deinit();
}

fn clearProtected(root: *harness.Root) void {
    root.tmp.dir.deleteTree(io, "protected.d") catch {};
}

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

fn writeProtected(root: *harness.Root, contents: []const u8) !void {
    try root.tmp.dir.createDirPath(io, "protected.d");
    try root.tmp.dir.writeFile(io, .{ .sub_path = "protected.d/test.conf", .data = contents });
}

test "a protected package cannot be erased directly" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, single);
    defer clearProtected(&root);

    try writeProtected(&root, single);
    try install(&root, single);
    try std.testing.expect(try root.isInstalled(single));

    var result = try root.run(&.{ "-y", "--nogpgcheck", "remove", single });
    defer result.deinit();
    try result.expectCode(protected_code);
    try std.testing.expect(try root.isInstalled(single));
}

test "removing a dependency is refused when it would erase a protected dependent" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, leaf);
    defer eraseBestEffort(&root, required);
    defer clearProtected(&root);

    try install(&root, leaf);
    try std.testing.expect(try root.isInstalled(leaf));
    try std.testing.expect(try root.isInstalled(required));
    try writeProtected(&root, leaf);

    var result = try root.run(&.{ "-y", "--nogpgcheck", "remove", required });
    defer result.deinit();
    try result.expectCode(solv_code);
    try result.expectStderrContains("requires " ++ required);
    try std.testing.expect(try root.isInstalled(leaf));
    try std.testing.expect(try root.isInstalled(required));
}

test "autoremove keeps a protected dependency" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, leaf);
    defer eraseBestEffort(&root, required);
    defer clearProtected(&root);

    try install(&root, leaf);
    try std.testing.expect(try root.isInstalled(leaf));
    try std.testing.expect(try root.isInstalled(required));
    try writeProtected(&root, required);

    var result = try root.run(&.{ "-y", "--nogpgcheck", "autoremove", leaf });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(!try root.isInstalled(leaf));
    try std.testing.expect(try root.isInstalled(required));
}

test "an install that would obsolete a protected package is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, obsoleting);
    defer eraseBestEffort(&root, obsoleted);
    defer clearProtected(&root);

    try install(&root, obsoleted_versioned);
    try std.testing.expect(try root.isInstalled(obsoleted));
    try writeProtected(&root, obsoleted);

    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", obsoleting });
    defer result.deinit();
    try result.expectCode(protected_code);
    try std.testing.expect(try root.isInstalled(obsoleted));
    try std.testing.expect(!try root.isInstalled(obsoleting));
}

test "history rollback can revert a protected package upgrade" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);
    defer clearProtected(&root);

    try install(&root, multiversion ++ "-1.0.1-1");
    try std.testing.expect(try root.isInstalledVersion(multiversion, "1.0.1-1"));
    try writeProtected(&root, multiversion);

    var history = try root.run(&.{"history"});
    defer history.deinit();
    try history.expectOk();

    const baseline = lastHistoryId(history.stdout) orelse return error.TestUnexpectedResult;

    var update = try root.run(&.{ "update", "-y", "--nogpgcheck", multiversion });
    defer update.deinit();
    try update.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multiversion, "1.0.2-1"));

    var rollback = try root.run(&.{ "history", "-y", "rollback", "--to", baseline });
    defer rollback.deinit();
    try rollback.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multiversion, "1.0.1-1"));
}

fn lastHistoryId(stdout: []const u8) ?[]const u8 {
    var last: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        var columns = std.mem.tokenizeAny(u8, line, " \t");
        const first = columns.next() orelse continue;
        if (std.fmt.parseInt(u32, first, 10)) |_| {
            last = first;
        } else |_| {}
    }
    return last;
}
