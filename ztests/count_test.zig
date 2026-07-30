//! Count command behaviour, ported from `pytests/tests/test_count.py`.
//!
//! The valgrind-only pytest case is intentionally left in pytest.

const std = @import("std");
const harness = @import("harness.zig");

test "count succeeds" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{"count"});
    defer result.deinit();
    try result.expectOk();
}
