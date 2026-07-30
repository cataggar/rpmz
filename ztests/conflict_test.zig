//! File-conflict install behaviour, ported from
//! `pytests/tests/test_conflict.py`.

const std = @import("std");
const harness = @import("harness.zig");

const pkg0 = "tdnf-conflict-file0";
const pkg1 = "tdnf-conflict-file1";

/// `ERROR_TDNF_FILE_CONFLICT`, as the shell sees it.
const file_conflict_code: u8 = 1525 % 256;

test "installing a package with a file conflict is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var first = try root.run(&.{ "install", "-y", "--nogpgcheck", pkg0 });
    defer first.deinit();
    try first.expectOk();
    try std.testing.expect(try root.isInstalled(pkg0));

    var second = try root.run(&.{ "install", "-y", "--nogpgcheck", pkg1 });
    defer second.deinit();
    try second.expectCode(file_conflict_code);
    try std.testing.expect(!try root.isInstalled(pkg1));
}

test "installing two packages with a shared file is refused atomically" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", pkg0, pkg1 });
    defer result.deinit();
    try result.expectCode(file_conflict_code);

    try std.testing.expect(!try root.isInstalled(pkg0));
    try std.testing.expect(!try root.isInstalled(pkg1));
}
