//! Cache cleaning behaviour, ported from `pytests/tests/test_clean.py`.

const std = @import("std");
const harness = @import("harness.zig");

const multiversion = "tdnf-test-multiversion";

/// `ERROR_TDNF_CLI_CLEAN_REQUIRES_OPTION`, as the shell sees it.
const clean_requires_option_code: u8 = 903 % 256;
/// `ERROR_TDNF_CLI_NO_MATCH`.
const cli_no_match_code: u8 = 901 % 256;
/// `ERROR_TDNF_CLEAN_UNSUPPORTED`.
const clean_unsupported_code: u8 = 1016 % 256;

fn expectCleanOk(args: []const []const u8) !void {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(args);
    defer result.deinit();
    try result.expectOk();
}

test "clean with no argument is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{"clean"});
    defer result.deinit();
    try result.expectCode(clean_requires_option_code);
}

test "clean with an invalid argument is refused" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "clean", "abcde" });
    defer result.deinit();
    try result.expectCode(cli_no_match_code);
}

test "clean packages succeeds" {
    try expectCleanOk(&.{ "clean", "packages" });
}

test "clean dbcache succeeds" {
    try expectCleanOk(&.{ "clean", "dbcache" });
}

test "clean metadata succeeds" {
    try expectCleanOk(&.{ "clean", "metadata" });
}

test "clean expire-cache succeeds" {
    try expectCleanOk(&.{ "clean", "expire-cache" });
}

test "clean plugins reports plugin cleanup is unavailable" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "clean", "plugins" });
    defer result.deinit();
    try result.expectCode(clean_unsupported_code);
}

test "clean all succeeds after makecache" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var cache = try root.run(&.{"makecache"});
    defer cache.deinit();
    try cache.expectOk();

    var result = try root.run(&.{ "clean", "all" });
    defer result.deinit();
    try result.expectOk();
}

test "clean all succeeds when cache is already clean" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var cache = try root.run(&.{"makecache"});
    defer cache.deinit();
    try cache.expectOk();

    var first = try root.run(&.{ "clean", "all" });
    defer first.deinit();
    try first.expectOk();

    var second = try root.run(&.{ "clean", "all" });
    defer second.deinit();
    try second.expectOk();
}

test "clean all after an install leaves the package installed" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var cache = try root.run(&.{"makecache"});
    defer cache.deinit();
    try cache.expectOk();

    var install = try root.run(&.{ "install", "-y", "--nogpgcheck", multiversion });
    defer install.deinit();
    try install.expectOk();

    var result = try root.run(&.{ "clean", "all" });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(try root.isInstalled(multiversion));
}
