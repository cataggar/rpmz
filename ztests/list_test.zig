//! List command behaviour, ported from `pytests/tests/test_list.py`.

const std = @import("std");
const harness = @import("harness.zig");

const single = "tdnf-test-one";
const multiversion = "tdnf-test-multiversion";
const multiversion_lower = "1.0.1-1";
const multiversion_higher = "1.0.2-1";
const multiversion_arch = harness.basearch;
const lower_nevra = multiversion ++ "-" ++ multiversion_lower ++ "." ++ multiversion_arch;
const higher_nevra = multiversion ++ "-" ++ multiversion_higher ++ "." ++ multiversion_arch;

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
    // The exit code alone does not say the command listed nothing; a run that
    // printed rows *and* failed would satisfy it.
    try result.expectStdoutEmpty();
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
    // Only the higher version is an upgrade; listing both would mean the
    // installed one was not filtered out.
    try upgrades.expectPackageSet(std.testing.allocator, &.{higher_nevra});

    for ([_][]const u8{ "updates", "upgrades", "downgrades", "--updates", "--upgrades", "--downgrades" }) |sub_cmd| {
        try expectListNoMatch(&root, &.{ "list", sub_cmd, "invalid_package" });
        try expectListNoMatch(&root, &.{ "list", sub_cmd, single });
    }
}

test "list accepts partial EVR package specs" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const Case = struct { spec: []const u8, expected: []const []const u8 };
    // `>=1.0.1` legitimately matches *both* versions, so a
    // `expectStdoutContains(higher)` assertion here would pass just as well if
    // the comparison were ignored and everything returned (#253). The exact
    // set distinguishes the two.
    const available_cases = [_]Case{
        .{ .spec = multiversion ++ "=1.0.1", .expected = &.{lower_nevra} },
        .{ .spec = multiversion ++ "=0:1.0.1", .expected = &.{lower_nevra} },
        .{ .spec = multiversion ++ "<=1.0.1", .expected = &.{lower_nevra} },
        .{ .spec = multiversion ++ ">=1.0.1", .expected = &.{ lower_nevra, higher_nevra } },
        .{ .spec = multiversion ++ ">1.0.1", .expected = &.{higher_nevra} },
    };

    for (available_cases) |case| {
        var result = try root.run(&.{ "list", "available", case.spec });
        defer result.deinit();
        try result.expectOk();
        try result.expectPackageSet(std.testing.allocator, case.expected);
    }

    try install(&root, multiversion ++ "-" ++ multiversion_lower);
    var installed = try root.run(&.{ "list", "installed", multiversion ++ "=0:1.0.1" });
    defer installed.deinit();
    try installed.expectOk();
    try installed.expectPackageSet(std.testing.allocator, &.{lower_nevra});
}
