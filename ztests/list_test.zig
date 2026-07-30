//! List command behaviour, ported from `pytests/tests/test_list.py`.

const std = @import("std");
const harness = @import("harness.zig");

const single = "tdnf-test-one";
const multiversion = "tdnf-test-multiversion";
const multiversion_lower = "1.0.1-1";
const multiversion_higher = "1.0.2-1";

/// `ERROR_TDNF_NO_MATCH`.
const no_match_code: u8 = 1011 % 256;

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

fn expectListOk(root: *harness.Root, args: []const []const u8) !void {
    var result = try root.run(args);
    defer result.deinit();
    try result.expectOk();
}

fn expectListNoMatch(root: *harness.Root, args: []const []const u8) !void {
    var result = try root.run(args);
    defer result.deinit();
    try result.expectCode(no_match_code);
}

fn expectSubCommand(root: *harness.Root, sub_cmd: []const u8) !void {
    try expectListOk(root, &.{ "list", sub_cmd });
    try expectListOk(root, &.{ "list", sub_cmd, single });
    try expectListNoMatch(root, &.{ "list", sub_cmd, "invalid_package" });
}

test "list top-level forms work" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, single);
    try std.testing.expect(try root.isInstalled(single));

    try expectListOk(&root, &.{"list"});
    try expectListOk(&root, &.{ "list", single });
    try expectListNoMatch(&root, &.{ "list", "invalid_package" });
}

test "list subcommands accept valid and reject invalid package names" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, single);

    for ([_][]const u8{ "all", "installed", "available", "obsoletes", "extras", "recent" }) |sub_cmd| {
        try expectSubCommand(&root, sub_cmd);
    }
}

test "list option aliases accept valid and reject invalid package names" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, single);

    for ([_][]const u8{ "--all", "--installed", "--available", "--obsoletes", "--extras", "--recent" }) |sub_cmd| {
        try expectSubCommand(&root, sub_cmd);
    }
}

test "list update-related subcommands handle installed state" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try expectListOk(&root, &.{ "list", "upgrades" });

    try install(&root, multiversion ++ "-" ++ multiversion_lower);
    var upgrades = try root.run(&.{ "list", "upgrades", multiversion });
    defer upgrades.deinit();
    try upgrades.expectOk();
    try upgrades.expectStdoutContains(multiversion);
    try upgrades.expectStdoutContains(multiversion_higher);

    for ([_][]const u8{ "updates", "upgrades", "downgrades", "--updates", "--upgrades", "--downgrades" }) |sub_cmd| {
        try expectListNoMatch(&root, &.{ "list", sub_cmd, "invalid_package" });
        try expectListNoMatch(&root, &.{ "list", sub_cmd, single });
    }
}
