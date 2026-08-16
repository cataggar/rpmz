// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");

const io = std.testing.io;
const compatibility_command = "tdnf";

fn run(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) !std.process.RunResult {
    return std.process.run(allocator, io, .{ .argv = argv });
}

fn runWithPath(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    path: []const u8,
) !std.process.RunResult {
    var environment = std.process.Environ.Map.init(allocator);
    defer environment.deinit();
    try environment.put("PATH", path);
    return std.process.run(allocator, io, .{
        .argv = argv,
        .environ_map = &environment,
    });
}

fn exitCode(result: std.process.RunResult) u8 {
    return switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
}

fn realPathAlloc(allocator: std.mem.Allocator, dir: std.Io.Dir) ![]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try dir.realPath(io, &buffer);
    return allocator.dupe(u8, buffer[0..len]);
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
    compatibility_cli: []const u8,
    rpmz: []const u8,
    args: []const []const u8,
) !void {
    var compatibility_argv: std.ArrayList([]const u8) = .empty;
    defer compatibility_argv.deinit(allocator);
    try compatibility_argv.ensureTotalCapacity(allocator, args.len + 1);
    compatibility_argv.appendAssumeCapacity(compatibility_cli);
    compatibility_argv.appendSliceAssumeCapacity(args);

    var rpmz_argv: std.ArrayList([]const u8) = .empty;
    defer rpmz_argv.deinit(allocator);
    try rpmz_argv.ensureTotalCapacity(allocator, args.len + 2);
    rpmz_argv.appendAssumeCapacity(rpmz);
    rpmz_argv.appendAssumeCapacity(compatibility_command);
    rpmz_argv.appendSliceAssumeCapacity(args);

    const compatibility_result = try run(allocator, compatibility_argv.items);
    defer allocator.free(compatibility_result.stdout);
    defer allocator.free(compatibility_result.stderr);
    const rpmz_result = try run(allocator, rpmz_argv.items);
    defer allocator.free(rpmz_result.stdout);
    defer allocator.free(rpmz_result.stderr);

    try expectTermEqual(rpmz_result.term, compatibility_result.term);
    try std.testing.expectEqualStrings(compatibility_result.stdout, rpmz_result.stdout);
    try std.testing.expectEqualStrings(compatibility_result.stderr, rpmz_result.stderr);
}

test "rpmz dispatches compatibility commands" {
    const allocator = std.testing.allocator;
    const prefix = std.testing.environ.getAlloc(
        allocator,
        "RPMZ_DISPATCHER_TEST_PREFIX",
    ) catch try allocator.dupe(u8, "zig-out");
    defer allocator.free(prefix);

    const rpmz = try std.fs.path.join(allocator, &.{ prefix, "bin", "rpmz" });
    defer allocator.free(rpmz);
    const installed_compatibility_cli = try std.fs.path.join(
        allocator,
        &.{ prefix, "bin", compatibility_command },
    );
    defer allocator.free(installed_compatibility_cli);
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, installed_compatibility_cli, .{}),
    );

    const rpmz_absolute = try std.Io.Dir.cwd().realPathFileAlloc(io, rpmz, allocator);
    defer allocator.free(rpmz_absolute);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, rpmz_absolute, compatibility_command, .{});

    var tmp_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const tmp_path_len = try tmp.dir.realPath(io, &tmp_path_buffer);
    const compatibility_cli = try std.fs.path.join(
        allocator,
        &.{ tmp_path_buffer[0..tmp_path_len], compatibility_command },
    );
    defer allocator.free(compatibility_cli);

    try expectCompatibilityParity(allocator, compatibility_cli, rpmz, &.{"--version"});
    try expectCompatibilityParity(allocator, compatibility_cli, rpmz, &.{"--help"});
    try expectCompatibilityParity(allocator, compatibility_cli, rpmz, &.{"--invalid-option"});
    try expectCompatibilityParity(allocator, compatibility_cli, rpmz, &.{"not-a-command"});
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
    try std.testing.expect(std.mem.indexOf(u8, bare.stdout, "  auto     Run the automatic updater") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        bare.stdout,
        "  repo-config Configure repository files",
    ) != null);

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

test "rpmz auto is private and does not need a compatibility executable in PATH" {
    const allocator = std.testing.allocator;
    const prefix = std.testing.environ.getAlloc(
        allocator,
        "RPMZ_DISPATCHER_TEST_PREFIX",
    ) catch try allocator.dupe(u8, "zig-out");
    defer allocator.free(prefix);

    const rpmz = try std.fs.path.join(allocator, &.{ prefix, "bin", "rpmz" });
    defer allocator.free(rpmz);
    const retired_automatic = try std.fs.path.join(
        allocator,
        &.{ prefix, "bin", "rpmz-automatic" },
    );
    defer allocator.free(retired_automatic);
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, retired_automatic, .{}),
    );

    const helper = try std.fs.path.join(
        allocator,
        &.{ prefix, "libexec", "rpmz", "rpmz-auto" },
    );
    defer allocator.free(helper);
    try std.Io.Dir.cwd().access(io, helper, .{});

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, "/bin/bash", "bash", .{});
    var tmp_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const tmp_path_len = try tmp.dir.realPath(io, &tmp_path_buffer);

    const result = try runWithPath(
        allocator,
        &.{ rpmz, "auto", "--help" },
        tmp_path_buffer[0..tmp_path_len],
    );
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (std.os.linux.geteuid() == 0) {
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "rpmz auto help:") != null);
    } else {
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 13 }, result.term);
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "must be run as root") != null);
    }
}

test "rpmz dispatches repo-config arguments" {
    const allocator = std.testing.allocator;
    const prefix = std.testing.environ.getAlloc(
        allocator,
        "RPMZ_DISPATCHER_TEST_PREFIX",
    ) catch try allocator.dupe(u8, "zig-out");
    defer allocator.free(prefix);

    const rpmz = try std.fs.path.join(allocator, &.{ prefix, "bin", "rpmz" });
    defer allocator.free(rpmz);
    const retired_config = try std.fs.path.join(
        allocator,
        &.{ prefix, "bin", "rpmz-config" },
    );
    defer allocator.free(retired_config);
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().access(io, retired_config, .{}),
    );

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try realPathAlloc(allocator, tmp.dir);
    defer allocator.free(root);
    try tmp.dir.createDirPath(io, "repos");

    const config = try std.fs.path.join(allocator, &.{ root, "rpmz.conf" });
    defer allocator.free(config);
    const config_contents = try std.fmt.allocPrint(
        allocator,
        "[main]\nrepodir={s}/repos\n",
        .{root},
    );
    defer allocator.free(config_contents);
    try tmp.dir.writeFile(io, .{
        .sub_path = "rpmz.conf",
        .data = config_contents,
    });

    const create = try run(allocator, &.{
        rpmz,
        "repo-config",
        "--config",
        config,
        "create",
        "foo",
        "name=Foo",
        "baseurl=http://foo.bar.com",
        "enabled=1",
    });
    defer allocator.free(create.stdout);
    defer allocator.free(create.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(create));

    const dump = try run(allocator, &.{
        rpmz,
        "repo-config",
        "--config",
        config,
        "--json",
        "dump",
        "foo",
    });
    defer allocator.free(dump.stdout);
    defer allocator.free(dump.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(dump));
    try std.testing.expectEqualStrings(
        "{\"foo\":{\"name\":\"Foo\",\"baseurl\":\"http://foo.bar.com\",\"enabled\":\"1\"}}",
        dump.stdout,
    );

    const override = try std.fs.path.join(allocator, &.{ root, "override.repo" });
    defer allocator.free(override);
    const file_override = try run(allocator, &.{
        rpmz,
        "repo-config",
        "--config",
        config,
        "--file",
        override,
        "create",
        "bar",
        "name=Bar",
    });
    defer allocator.free(file_override.stdout);
    defer allocator.free(file_override.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(file_override));
    try std.Io.Dir.cwd().access(io, override, .{});

    const invalid_option = try run(
        allocator,
        &.{ rpmz, "repo-config", "--bad-option" },
    );
    defer allocator.free(invalid_option.stdout);
    defer allocator.free(invalid_option.stderr);
    try std.testing.expectEqual(@as(u8, 1), exitCode(invalid_option));
    try std.testing.expectEqualStrings(
        "repo-config: unrecognized option '--bad-option'\n",
        invalid_option.stderr,
    );

    const invalid_action = try run(
        allocator,
        &.{ rpmz, "repo-config", "-c", config, "frobnicate", "foo" },
    );
    defer allocator.free(invalid_action.stdout);
    defer allocator.free(invalid_action.stderr);
    try std.testing.expectEqual(@as(u8, 1), exitCode(invalid_action));
    try std.testing.expectEqualStrings(
        "Unknown command 'frobnicate'\n",
        invalid_action.stderr,
    );
}
