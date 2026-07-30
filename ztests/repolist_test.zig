//! Repository listing behaviour, ported from `pytests/tests/test_repolist.py`.
//!
//! `test_repolist_memcheck` is intentionally left in pytest with the other
//! valgrind coverage.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

/// `ERROR_TDNF_CLI_NO_MATCH`.
const cli_no_match_code: u8 = 901 % 256;
/// `ERROR_TDNF_DUPLICATE_REPO`, as the shell sees it.
const duplicate_repo_code: u8 = 1037 % 256;

const Repo = struct {
    id: []const u8,
    name: []const u8,
    baseurl: []const u8,
    enabled: bool,
};

fn addFixtureRepos(root: *harness.Root) !void {
    try writeRepo(root, "etc/yum.repos.d/foo.repo", &.{
        .{
            .id = "foo",
            .name = "Foo Repo",
            .baseurl = "http://pkgs.foo.org/foo",
            .enabled = true,
        },
        .{
            .id = "foo-debug",
            .name = "Foo Debug Repo",
            .baseurl = "http://pkgs.foo.org/foo-debug",
            .enabled = false,
        },
    });
    try writeRepo(root, "etc/yum.repos.d/bar.repo", &.{
        .{
            .id = "bar",
            .name = "Bar Repo",
            .baseurl = "http://pkgs.bar.org/bar",
            .enabled = true,
        },
    });
    try writeRepo(root, "etc/yum.repos.d/example.repo", &.{
        .{
            .id = "example-test",
            .name = "Example Repo",
            .baseurl = "http://pkgs.example.org/example",
            .enabled = true,
        },
        .{
            .id = "example-debug",
            .name = "Example Debug Repo",
            .baseurl = "http://pkgs.example.org/example-debug",
            .enabled = false,
        },
        .{
            .id = "example-updates",
            .name = "Example Updates Repo",
            .baseurl = "http://pkgs.example.org/example-updates",
            .enabled = false,
        },
    });
}

fn writeRepo(root: *harness.Root, sub_path: []const u8, repos: []const Repo) !void {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(root.allocator);

    for (repos) |repo| {
        try body.print(root.allocator,
            \\[{s}]
            \\name={s}
            \\baseurl={s}
            \\enabled={d}
            \\gpgcheck=0
            \\
        , .{
            repo.id,
            repo.name,
            repo.baseurl,
            @intFromBool(repo.enabled),
        });
    }

    try root.tmp.dir.writeFile(io, .{ .sub_path = sub_path, .data = body.items });
}

fn expectOk(root: *harness.Root, args: []const []const u8) !void {
    var result = try root.run(args);
    defer result.deinit();
    try result.expectOk();
}

fn expectRepos(
    root: *harness.Root,
    args: []const []const u8,
    present: []const []const u8,
    absent: []const []const u8,
) !void {
    var result = try root.run(args);
    defer result.deinit();
    try result.expectOk();

    var parsed = try std.json.parseFromSlice(std.json.Value, root.allocator, result.stdout, .{});
    defer parsed.deinit();

    for (present) |id| {
        try std.testing.expect(repoInJson(parsed.value, id));
    }
    for (absent) |id| {
        try std.testing.expect(!repoInJson(parsed.value, id));
    }
}

fn repoInJson(value: std.json.Value, id: []const u8) bool {
    for (value.array.items) |item| {
        const repo = item.object.get("Repo") orelse continue;
        if (std.mem.eql(u8, repo.string, id)) return true;
    }
    return false;
}

test "repolist succeeds" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectOk(&root, &.{"repolist"});
}

test "repolist json shows enabled repos" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectRepos(&root, &.{ "repolist", "-j" }, &.{ "foo", "bar" }, &.{"foo-debug"});
}

test "repolist can enable one disabled repo" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectRepos(
        &root,
        &.{ "repolist", "--enablerepo=foo-debug", "-j" },
        &.{ "foo", "foo-debug", "bar" },
        &.{},
    );
}

test "repolist all and basic selectors succeed" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectOk(&root, &.{ "repolist", "all" });
    try expectOk(&root, &.{ "repolist", "enabled" });
    try expectOk(&root, &.{ "repolist", "disabled" });
}

test "repolist all json includes disabled repos" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectRepos(
        &root,
        &.{ "repolist", "all", "-j" },
        &.{ "foo", "foo-debug", "bar" },
        &.{},
    );
}

test "repolist disabled json includes only disabled repos" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectRepos(
        &root,
        &.{ "repolist", "disabled", "-j" },
        &.{"foo-debug"},
        &.{ "foo", "bar" },
    );
}

test "repolist rejects an invalid selector" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    var result = try root.run(&.{ "repolist", "invalid_repo" });
    defer result.deinit();
    try result.expectCode(cli_no_match_code);
}

test "duplicate repo ids are rejected before metadata sync" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try writeRepo(&root, "etc/yum.repos.d/test.repo", &.{
        .{
            .id = "test",
            .name = "Test Repo",
            .baseurl = "http://pkgs.test.org/test",
            .enabled = true,
        },
    });
    try writeRepo(&root, "etc/yum.repos.d/test1.repo", &.{
        .{
            .id = "test",
            .name = "Test Repo",
            .baseurl = "http://pkgs.test1.org/test1",
            .enabled = true,
        },
    });

    var result = try root.run(&.{ "--disablerepo=*", "--enablerepo=test1.repo", "makecache" });
    defer result.deinit();
    try result.expectCode(duplicate_repo_code);
}

test "comma-separated enablerepo and disablerepo selectors work" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectRepos(
        &root,
        &.{ "repolist", "--enablerepo=foo-debug,bar", "-j" },
        &.{ "foo", "foo-debug", "bar" },
        &.{},
    );
    try expectRepos(
        &root,
        &.{ "repolist", "--disablerepo=foo,bar", "-j" },
        &.{},
        &.{ "foo", "bar", "foo-debug" },
    );
}

test "comma-separated repoid and repo selectors enable only those repos" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    for ([_][]const u8{ "--repoid=foo-debug,bar", "--repo=foo-debug,bar" }) |selector| {
        try expectRepos(
            &root,
            &.{ "repolist", selector, "-j" },
            &.{ "foo-debug", "bar" },
            &.{ "foo", "example-test", "example-debug" },
        );
    }
}

test "glob repo selectors work" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectRepos(
        &root,
        &.{ "repolist", "--enablerepo=example*", "-j" },
        &.{ "example-test", "example-debug", "example-updates" },
        &.{},
    );
    try expectRepos(
        &root,
        &.{ "repolist", "--disablerepo=foo*", "-j" },
        &.{"bar"},
        &.{ "foo", "foo-debug" },
    );
}

test "comma-separated glob repo selectors work" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectRepos(
        &root,
        &.{ "repolist", "--enablerepo=example*,foo*", "-j" },
        &.{ "example-test", "example-debug", "example-updates", "foo", "foo-debug" },
        &.{},
    );
    try expectRepos(
        &root,
        &.{ "repolist", "--disablerepo=example*,foo*", "-j" },
        &.{"bar"},
        &.{ "example-test", "example-debug", "example-updates", "foo", "foo-debug" },
    );
}

test "mixed repo selectors work" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try addFixtureRepos(&root);

    try expectRepos(
        &root,
        &.{ "repolist", "--enablerepo=example*,bar", "-j" },
        &.{ "example-test", "example-debug", "example-updates", "bar" },
        &.{},
    );
    try expectRepos(
        &root,
        &.{ "repolist", "--disablerepo=foo*,bar", "-j" },
        &.{},
        &.{ "foo", "foo-debug", "bar" },
    );
}
