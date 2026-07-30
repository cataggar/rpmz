//! Count command behaviour, ported from `pytests/tests/test_count.py`.
//!
//! The valgrind-only pytest case is intentionally left in pytest.

const std = @import("std");
const harness = @import("harness.zig");

fn parseCount(stdout: []const u8) !usize {
    const prefix = "Package count = ";
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (std.mem.startsWith(u8, trimmed, prefix)) {
            return std.fmt.parseUnsigned(usize, trimmed[prefix.len..], 10);
        }
    }
    std.debug.print("count output did not contain \"{s}\"\nstdout:\n{s}\n", .{ prefix, stdout });
    return error.TestUnexpectedResult;
}

fn countListPackageLines(stdout: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r\n").len != 0) {
            count += 1;
        }
    }
    return count;
}

test "count succeeds" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{"count"});
    defer result.deinit();
    try result.expectOk();
}

test "count matches list all package lines" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var count_result = try root.run(&.{"count"});
    defer count_result.deinit();
    try count_result.expectOk();

    var list_result = try root.run(&.{ "list", "--all" });
    defer list_result.deinit();
    try list_result.expectOk();

    try std.testing.expectEqual(
        try parseCount(count_result.stdout),
        countListPackageLines(list_result.stdout),
    );
}
