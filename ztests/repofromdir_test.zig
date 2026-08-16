//! `--repofromdir=<id>,<path>`: a repository with no downloaded metadata,
//! whose packages are the `.rpm` files sitting under `<path>`.
//!
//! Nothing in the tree covered this before. The only test that touched it was
//! `pytests/tests/test_repofrompath.py::test_repofromdir_created_repo`, which
//! is not a CI gate, and it had been failing since the native query layer
//! became authoritative: `TDNFNativeQueryBuildRepoInputs` admitted only
//! repositories with `nHasMetaData`, so a `--repofromdir` repository was
//! silently dropped from every query. The failure mode was not an error but an
//! empty repository, which is indistinguishable from one that simply has no
//! matching packages — see issue #325.
//!
//! These tests therefore assert on *packages*, not on exit codes. An assertion
//! that only checked `retval == 0` would have passed throughout the regression,
//! because listing an empty repository succeeds.
//!
//! The interesting property is that a directory-backed repository has to reach
//! **two** independent consumers, and the bug hit both:
//!
//!   * the query layer (`client/package_query.zig`),
//!     which serves `list`, `repoquery`, `info`, `search` and — through
//!     `TDNFResolveListPackages` — turns `install <name>` into a package;
//!   * the solver universe (`client/goal.c`), which was already correct
//!     because `TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16` carries
//!     `pszDirectory`.
//!
//! Name resolution runs first, so a test that only reached the solver would
//! never have noticed. `install` is asserted end to end for that reason.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

/// `ERROR_TDNF_SOLV_FAILED` surfaces to the shell as `ERROR_TDNF_SOLV`.
const solv_code: u8 = 1301 % 256;

const one = "tdnf-test-one";
const two = "tdnf-test-two";
const missing_dep = "tdnf-missing-dep";

/// Matches `<name>-<digit>...` so a prefix does not match a longer package
/// name: without the digit check `tdnf-test-one` would also match
/// `tdnf-test-one-extra`.
fn isRpmOf(file_name: []const u8, name: []const u8) bool {
    if (!std.mem.endsWith(u8, file_name, ".rpm")) return false;
    if (file_name.len < name.len + 2) return false;
    if (!std.mem.startsWith(u8, file_name, name)) return false;
    if (file_name[name.len] != '-') return false;
    return std.ascii.isDigit(file_name[name.len + 1]);
}

fn copyMatchingRpms(
    allocator: std.mem.Allocator,
    source: []const u8,
    target: *std.Io.Dir,
    names: []const []const u8,
    copied: *usize,
) !void {
    var dir = std.Io.Dir.cwd().openDir(io, source, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var it = dir.iterateAssumeFirstIteration();
    while (try it.next(io)) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        const path = try std.fs.path.join(allocator, &.{ source, entry.name });
        defer allocator.free(path);

        if (entry.kind == .directory) {
            try copyMatchingRpms(allocator, path, target, names, copied);
            continue;
        }

        for (names) |name| {
            if (!isRpmOf(entry.name, name)) continue;
            const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
            defer allocator.free(bytes);
            try target.writeFile(io, .{ .sub_path = entry.name, .data = bytes });
            copied.* += 1;
            break;
        }
    }
}

/// Stages `names` into `<root>/<sub_path>` and returns that directory's
/// absolute path, which is what `--repofromdir` takes.
///
/// The rpms are copied out of the generated repository seed rather than built
/// here, so these tests use exactly the packages the rest of the suite does.
/// Note that only the `.rpm` files are copied: the staged directory has no
/// `repodata/`, which is the whole point of `--repofromdir`.
fn stageRpms(
    root: *harness.Root,
    sub_path: []const u8,
    names: []const []const u8,
) ![]const u8 {
    const allocator = root.allocator;

    try root.tmp.dir.createDirPath(io, sub_path);
    var target = try root.tmp.dir.openDir(io, sub_path, .{});
    defer target.close(io);

    const source = try std.fs.path.join(
        allocator,
        &.{ root.layout.repo_dir, "photon-test", "RPMS" },
    );
    defer allocator.free(source);

    var copied: usize = 0;
    try copyMatchingRpms(allocator, source, &target, names, &copied);
    if (copied != names.len) {
        std.debug.print(
            "staged {d} rpm(s) into {s} but {d} package name(s) were requested\n",
            .{ copied, sub_path, names.len },
        );
        return error.TestUnexpectedResult;
    }

    return std.fs.path.join(allocator, &.{ root.path, sub_path });
}

/// The flags that point rpmz at the staged directory and nothing else.
/// `--repo` restricts the run to it, so a result can only have come from the
/// directory.
fn fromDir(allocator: std.mem.Allocator, dir: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "--repofromdir=fromdir,{s}", .{dir});
}

test "a directory-backed repository lists the packages in it" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "fromdir", &.{ one, two });
    defer std.testing.allocator.free(dir);
    const arg = try fromDir(std.testing.allocator, dir);
    defer std.testing.allocator.free(arg);

    var result = try root.run(&.{ arg, "--repo=fromdir", "list", "available" });
    defer result.deinit();
    try result.expectOk();

    // The regression returned 0 here with empty stdout, so the package names
    // are what the assertion has to be about.
    try result.expectStdoutContains(one);
    try result.expectStdoutContains(two);
    try result.expectStdoutContains("fromdir");
}

test "a directory-backed repository answers repoquery" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "fromdir", &.{one});
    defer std.testing.allocator.free(dir);
    const arg = try fromDir(std.testing.allocator, dir);
    defer std.testing.allocator.free(arg);

    var result = try root.run(&.{ arg, "--repo=fromdir", "repoquery" });
    defer result.deinit();
    try result.expectOk();
    // repoquery renders full NEVRA, so this also pins that the version came
    // out of the rpm header rather than being left blank.
    try result.expectStdoutContains(one ++ "-1.0.1-2.");
}

test "a package can be installed by name out of a directory-backed repository" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "fromdir", &.{one});
    defer std.testing.allocator.free(dir);
    const arg = try fromDir(std.testing.allocator, dir);
    defer std.testing.allocator.free(arg);

    // This is the assertion the regression actually broke for users: name
    // resolution runs before the solve, so `install <name>` failed with
    // ERROR_TDNF_NO_MATCH without the solver ever being consulted.
    var install = try root.run(&.{
        arg, "--repo=fromdir", "install", "-y", "--nogpgcheck", one,
    });
    defer install.deinit();
    try install.expectOk();
    try std.testing.expect(try root.isInstalled(one));

    var erase = try root.run(&.{ "erase", "-y", one });
    defer erase.deinit();
    try erase.expectOk();
    try std.testing.expect(!try root.isInstalled(one));
}

// The solver half of the path was already correct; this pins that a
// directory-backed repository reaches it rather than failing earlier in name
// resolution, which is what the regression looked like from outside.
test "an unsatisfiable package from a directory-backed repository reaches the solver" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "fromdir", &.{missing_dep});
    defer std.testing.allocator.free(dir);
    const arg = try fromDir(std.testing.allocator, dir);
    defer std.testing.allocator.free(arg);

    var result = try root.run(&.{
        arg, "--repo=fromdir", "install", "-y", "--nogpgcheck", missing_dep,
    });
    defer result.deinit();

    // A solver diagnostic, not "Package '<name>' not found": the package was
    // found, its dependency was not.
    try result.expectCode(solv_code);
    try result.expectStderrContains("nothing provides missing needed by " ++ missing_dep ++ "-1.0.1-2.");
    try std.testing.expect(!result.stderrContains("not found"));
    try std.testing.expect(!try root.isInstalled(missing_dep));
}

// A directory-backed repository has no metadata to cache, so the code path
// that builds a cache directory for it must not run. Before the fix the
// legacy sack-based builder unconditionally required
// `pSack->pszCacheDir`; a run with no metadata repository at all would have
// tripped that.
test "a directory-backed repository works as the only enabled repository" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "fromdir", &.{one});
    defer std.testing.allocator.free(dir);
    const arg = try fromDir(std.testing.allocator, dir);
    defer std.testing.allocator.free(arg);

    var result = try root.run(&.{
        arg, "--disablerepo=*", "--enablerepo=fromdir", "list", "available",
    });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(one);
}
