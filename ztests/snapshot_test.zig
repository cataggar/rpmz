//! `snapshot=` repository pinning.
//!
//! A repository may name a snapshot file listing `name=evr` tokens; only the
//! listed evr of a listed name is visible from that repository. The feature had
//! no automated coverage at all before this file, which is why retiring
//! `pool->considered` had to be argued rather than tested — snapshots are
//! enforced natively (`LoadedDataset.packageAllowedPkg`), never through the
//! libsolv bitmap, and these tests pin that.

const std = @import("std");
const harness = @import("harness.zig");

const multiversion = "tdnf-test-multiversion";
const pinned = "1.0.1-1";
const newest = "1.0.2-1";

/// `ERROR_TDNF_NO_MATCH`, as the shell sees it.
const no_match_code: u8 = 1011 % 256;

fn eraseBestEffort(root: *harness.Root, name: []const u8) void {
    var result = root.run(&.{ "erase", "-y", name }) catch return;
    defer result.deinit();
}

/// Rewrites the root's repository definition with a `snapshot=` line pointing
/// at `snapshot_body`, written inside the root. An absolute path is taken
/// verbatim by `TDNFInitRepoFromMetadata`, so no URL handling is involved.
fn pinRepository(root: *harness.Root, snapshot_body: []const u8) !void {
    try root.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "snapshot.txt",
        .data = snapshot_body,
    });

    const snapshot_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ root.path, "snapshot.txt" },
    );
    defer std.testing.allocator.free(snapshot_path);

    const repo_file = try std.fmt.allocPrint(std.testing.allocator,
        \\[photon-test]
        \\name=Test Repo
        \\baseurl=file://{s}/photon-test
        \\enabled=1
        \\gpgcheck=0
        \\snapshot={s}
        \\
    , .{ root.layout.repo_dir, snapshot_path });
    defer std.testing.allocator.free(repo_file);

    try root.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "etc/yum.repos.d/photon-test.repo",
        .data = repo_file,
    });
}

test "without a snapshot the newest available version is listed and installed" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    var listed = try root.run(&.{ "list", "--available", multiversion });
    defer listed.deinit();
    try listed.expectOk();
    try listed.expectStdoutContains(newest);

    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", multiversion });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multiversion, newest));
}

test "a snapshot hides every version of a pinned name except the pinned one" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try pinRepository(&root, multiversion ++ "=" ++ pinned ++ "\n");

    var result = try root.run(&.{ "list", "--available", multiversion });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(pinned);
    try std.testing.expect(!result.stdoutContains(newest));
}

test "a snapshot makes install select the pinned version over a newer one" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);
    try pinRepository(&root, multiversion ++ "=" ++ pinned ++ "\n");

    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", multiversion });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(try root.isInstalledVersion(multiversion, pinned));
    try std.testing.expect(!try root.isInstalledVersion(multiversion, newest));
}

test "a snapshot is an allow-list: unmentioned names disappear entirely" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try pinRepository(&root, "tdnf-multi=1.0.1-2\n");

    // The pinned name resolves to exactly its pinned evr.
    var pinned_name = try root.run(&.{ "list", "--available", "tdnf-multi" });
    defer pinned_name.deinit();
    try pinned_name.expectOk();
    try pinned_name.expectStdoutContains("1.0.1-2");
    try std.testing.expect(!pinned_name.stdoutContains("1.0.1-4"));

    // Every other name is hidden, not merely left unfiltered: a non-empty
    // snapshot is a whitelist of `(name, evr)` pairs, so an unmentioned
    // package has no visible version at all.
    var other = try root.run(&.{ "list", "--available", multiversion });
    defer other.deinit();
    try other.expectCode(no_match_code);
}

test "comments and blank lines in a snapshot file are ignored" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try pinRepository(&root,
        \\# a comment
        \\
        \\tdnf-test-multiversion=1.0.1-1
        \\
    );

    var result = try root.run(&.{ "list", "--available", multiversion });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(pinned);
    try std.testing.expect(!result.stdoutContains(newest));
}
