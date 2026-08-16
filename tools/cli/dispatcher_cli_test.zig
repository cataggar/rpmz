// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");

const io = std.testing.io;

fn run(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) !std.process.RunResult {
    return std.process.run(allocator, io, .{ .argv = argv });
}

fn expectTermEqual(actual: std.process.Child.Term, expected: std.process.Child.Term) !void {
    switch (expected) {
        .exited => |expected_code| switch (actual) {
            .exited => |actual_code| try std.testing.expectEqual(expected_code, actual_code),
            else => return error.TestUnexpectedResult,
        },
        else => try std.testing.expectEqual(expected, actual),
    }
}

fn expectCompatibilityParity(
    allocator: std.mem.Allocator,
    tdnf: []const u8,
    rpmz: []const u8,
    args: []const []const u8,
) !void {
    var tdnf_argv: std.ArrayList([]const u8) = .empty;
    defer tdnf_argv.deinit(allocator);
    try tdnf_argv.ensureTotalCapacity(allocator, args.len + 1);
    tdnf_argv.appendAssumeCapacity(tdnf);
    tdnf_argv.appendSliceAssumeCapacity(args);

    var rpmz_argv: std.ArrayList([]const u8) = .empty;
    defer rpmz_argv.deinit(allocator);
    try rpmz_argv.ensureTotalCapacity(allocator, args.len + 2);
    rpmz_argv.appendAssumeCapacity(rpmz);
    rpmz_argv.appendAssumeCapacity("tdnf");
    rpmz_argv.appendSliceAssumeCapacity(args);

    const tdnf_result = try run(allocator, tdnf_argv.items);
    defer allocator.free(tdnf_result.stdout);
    defer allocator.free(tdnf_result.stderr);
    const rpmz_result = try run(allocator, rpmz_argv.items);
    defer allocator.free(rpmz_result.stdout);
    defer allocator.free(rpmz_result.stderr);

    try expectTermEqual(rpmz_result.term, tdnf_result.term);
    try std.testing.expectEqualStrings(tdnf_result.stdout, rpmz_result.stdout);
    try std.testing.expectEqualStrings(tdnf_result.stderr, rpmz_result.stderr);
}

test "rpmz dispatches tdnf compatibility commands" {
    const allocator = std.testing.allocator;
    const prefix = std.testing.environ.getAlloc(
        allocator,
        "RPMZ_DISPATCHER_TEST_PREFIX",
    ) catch try allocator.dupe(u8, "zig-out");
    defer allocator.free(prefix);

    const rpmz = try std.fs.path.join(allocator, &.{ prefix, "bin", "rpmz" });
    defer allocator.free(rpmz);
    const installed_tdnf = try std.fs.path.join(allocator, &.{ prefix, "bin", "tdnf" });
    defer allocator.free(installed_tdnf);
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, installed_tdnf, .{}),
    );

    const rpmz_absolute = try std.Io.Dir.cwd().realPathFileAlloc(io, rpmz, allocator);
    defer allocator.free(rpmz_absolute);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, rpmz_absolute, "tdnf", .{});

    var tmp_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const tmp_path_len = try tmp.dir.realPath(io, &tmp_path_buffer);
    const tdnf = try std.fs.path.join(
        allocator,
        &.{ tmp_path_buffer[0..tmp_path_len], "tdnf" },
    );
    defer allocator.free(tdnf);

    try expectCompatibilityParity(allocator, tdnf, rpmz, &.{"--version"});
    try expectCompatibilityParity(allocator, tdnf, rpmz, &.{"--help"});
    try expectCompatibilityParity(allocator, tdnf, rpmz, &.{"--invalid-option"});
    try expectCompatibilityParity(allocator, tdnf, rpmz, &.{"not-a-command"});
}

test "rpmz reserves top-level help and version" {
    const allocator = std.testing.allocator;
    const prefix = std.testing.environ.getAlloc(
        allocator,
        "RPMZ_DISPATCHER_TEST_PREFIX",
    ) catch try allocator.dupe(u8, "zig-out");
    defer allocator.free(prefix);

    const rpmz = try std.fs.path.join(allocator, &.{ prefix, "bin", "rpmz" });
    defer allocator.free(rpmz);

    const bare = try run(allocator, &.{rpmz});
    defer allocator.free(bare.stdout);
    defer allocator.free(bare.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, bare.term);
    try std.testing.expect(std.mem.startsWith(u8, bare.stdout, "Usage: rpmz COMMAND\n"));

    const help = try run(allocator, &.{ rpmz, "--help" });
    defer allocator.free(help.stdout);
    defer allocator.free(help.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, help.term);
    try std.testing.expectEqualStrings(bare.stdout, help.stdout);
    try std.testing.expectEqualStrings(bare.stderr, help.stderr);

    const version = try run(allocator, &.{ rpmz, "--version" });
    defer allocator.free(version.stdout);
    defer allocator.free(version.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, version.term);
    try std.testing.expect(std.mem.startsWith(u8, version.stdout, "rpmz: "));

    const legacy_root = try run(allocator, &.{ rpmz, "install" });
    defer allocator.free(legacy_root.stdout);
    defer allocator.free(legacy_root.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, legacy_root.term);
    try std.testing.expect(std.mem.indexOf(u8, legacy_root.stdout, "Unknown rpmz command: install") != null);
}
