//! File data reaching the native model from `primary.xml` alone.
//!
//! `primary.xml` carries the filtered subset of every package's file list --
//! the paths libsolv's standard filter accepts (`*bin/*`, `/etc/*`,
//! `/usr/lib/sendmail`). `filelists.xml` carries the complete list, but it is
//! an *optional* extension: `repomd.xml` need not declare it, and the loader
//! only fetches it when it does.
//!
//! `repomd/primary.zig` used to have no `<file>` handling at all, so a
//! repository that published only `primary.xml` gave the native model no file
//! data whatsoever. Nothing failed loudly -- `provides` simply found nothing
//! and `repoquery --list` printed nothing, which is indistinguishable from a
//! package that genuinely owns no files. That is exactly the failure mode this
//! file exists to catch, so the assertions are on **paths and package names**
//! rather than on exit codes: every command below exits 0 either way.
//!
//! The repository is built by copying the generated seed's `repodata/` while
//! dropping `filelists.xml` and its `repomd.xml` record, which is the shape a
//! producer that omits the extension publishes.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

const repo_id = "primary-only";

/// A package whose `primary.xml` entry carries a `*bin/*` path.
const bin_owner = "tdnf-test3";
const bin_path = "/usr/bin/one";

/// A package whose `primary.xml` entry carries `/etc/*` paths.
const etc_owner = "tdnf-test-native-install";
const etc_path = "/etc/tdnf-test-native-install/plain.conf";

/// Removes the `<data type="filelists">` record from a `repomd.xml` body.
///
/// The loader only reads `filelists.xml` when `repomd.xml` declares it, so
/// deleting the file without deleting the record would leave the repository
/// merely broken rather than legitimately extension-free.
fn stripFilelistsRecord(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const open_tag = "<data type=\"filelists\">";
    const close_tag = "</data>";

    const start = std.mem.indexOf(u8, body, open_tag) orelse {
        std.debug.print("seed repomd.xml declares no filelists record\n", .{});
        return error.TestUnexpectedResult;
    };
    const close = std.mem.indexOfPos(u8, body, start, close_tag) orelse
        return error.TestUnexpectedResult;
    const end = close + close_tag.len;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, body[0..start]);
    try out.appendSlice(allocator, body[end..]);
    return out.toOwnedSlice(allocator);
}

/// Publishes a copy of the seed repository that declares no `filelists.xml`,
/// wires a repo file to it, and returns nothing -- callers reach it by id.
fn publishPrimaryOnlyRepo(root: *harness.Root) !void {
    const allocator = root.allocator;

    try root.tmp.dir.createDirPath(io, repo_id ++ "/repodata");
    var target = try root.tmp.dir.openDir(io, repo_id ++ "/repodata", .{});
    defer target.close(io);

    const source = try std.fs.path.join(
        allocator,
        &.{ root.layout.repo_dir, "photon-test", "repodata" },
    );
    defer allocator.free(source);

    var dir = try std.Io.Dir.cwd().openDir(io, source, .{ .iterate = true });
    defer dir.close(io);

    var saw_primary = false;
    var it = dir.iterateAssumeFirstIteration();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        // The detached signature no longer matches the edited `repomd.xml`,
        // and `filelists.xml` is the whole point of the exercise.
        if (std.mem.indexOf(u8, entry.name, "filelists") != null) continue;
        if (std.mem.endsWith(u8, entry.name, ".asc")) continue;
        if (std.mem.indexOf(u8, entry.name, "primary") != null) saw_primary = true;

        const path = try std.fs.path.join(allocator, &.{ source, entry.name });
        defer allocator.free(path);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
        defer allocator.free(bytes);

        if (std.mem.eql(u8, entry.name, "repomd.xml")) {
            const edited = try stripFilelistsRecord(allocator, bytes);
            defer allocator.free(edited);
            try target.writeFile(io, .{ .sub_path = entry.name, .data = edited });
            continue;
        }

        try target.writeFile(io, .{ .sub_path = entry.name, .data = bytes });
    }

    if (!saw_primary) {
        std.debug.print("seed repodata has no primary.xml to copy\n", .{});
        return error.TestUnexpectedResult;
    }

    const repo_file = try std.fmt.allocPrint(allocator,
        \\[{s}]
        \\name=Primary Only
        \\baseurl=file://{s}/{s}
        \\enabled=1
        \\gpgcheck=0
        \\
    , .{ repo_id, root.path, repo_id });
    defer allocator.free(repo_file);

    try root.tmp.dir.writeFile(io, .{
        .sub_path = "etc/yum.repos.d/" ++ repo_id ++ ".repo",
        .data = repo_file,
    });
}

test "provides resolves a bin path against a repository with no filelists.xml" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try publishPrimaryOnlyRepo(&root);

    var result = try root.run(&.{ "--disablerepo=photon-test", "provides", bin_path });
    defer result.deinit();

    try result.expectOk();
    try result.expectStdoutContains(bin_owner);
    try result.expectStdoutContains(repo_id);
}

test "provides resolves an etc path against a repository with no filelists.xml" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try publishPrimaryOnlyRepo(&root);

    var result = try root.run(&.{ "--disablerepo=photon-test", "provides", etc_path });
    defer result.deinit();

    try result.expectOk();
    try result.expectStdoutContains(etc_owner);
}

test "repoquery --list reports primary.xml's own file entries" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try publishPrimaryOnlyRepo(&root);

    var result = try root.run(&.{ "--disablerepo=photon-test", "repoquery", "--list", bin_owner });
    defer result.deinit();

    try result.expectOk();
    try result.expectStdoutContains(bin_path);
}

test "a package with no filtered files stays empty rather than borrowing another's" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try publishPrimaryOnlyRepo(&root);

    // `tdnf-repoquery-base` publishes no `*bin/*` or `/etc/*` path, so its
    // filtered list is empty. An off-by-one in the per-package file ranges
    // would hand it a neighbour's entries instead.
    var result = try root.run(&.{ "--disablerepo=photon-test", "repoquery", "--list", "tdnf-repoquery-base" });
    defer result.deinit();

    try result.expectOk();
    if (result.stdoutContains(bin_path) or result.stdoutContains(etc_path)) {
        std.debug.print("tdnf-repoquery-base reported another package's files:\n{s}\n", .{result.stdout});
        return error.TestUnexpectedResult;
    }
}

test "the full file list still wins where filelists.xml is published" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    // The seed repository does declare `filelists.xml`, whose complete list is
    // a superset of `primary.xml`'s. Parsing primary's entries must not
    // truncate it back down to the filtered subset.
    var result = try root.run(&.{ "repoquery", "--list", etc_owner });
    defer result.deinit();

    try result.expectOk();
    try result.expectStdoutContains(etc_path);
    try result.expectStdoutContains("/etc/tdnf-test-native-install/noreplace.conf");
}
