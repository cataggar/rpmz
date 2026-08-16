//! `rpmz check-local <dir>`: the dependency check over a directory of `.rpm`
//! files rather than over a repository.
//!
//! This command is the last caller of `SolvReportProblems`
//! (`client/api.c`, `TDNFCheckLocalPackages`). Unlike the goal path — whose
//! diagnostics are now rendered natively and are pinned by
//! `solverdiag_test.zig` — `check-local` builds its **own** command-line
//! libsolv pool over a directory, so none of the existing coverage touches it.
//! Before this file nothing in the tree asserted its output at all; the only
//! coverage was `pytests/tests/test_check_local.py`, which checks exit codes
//! for the trivial cases and is not run in CI.
//!
//! Three properties are pinned because they are easy to lose in a port:
//!
//!   * package identifiers render **without an epoch**
//!     (`tdnf-missing-dep-1.0.1-2.<arch>`), because these solvables come from
//!     `.rpm` headers in a command-line pool. The repository-backed messages in
//!     `solverdiag_test.zig` render the *same* packages **with** one
//!     (`-0:1.0.1-2.`). A port that applied one epoch rule everywhere would
//!     pass one of these two files and fail the other.
//!   * skipping every problem is **silent success**: `SolvReportProblems`
//!     assigns its error inside the report loop, so when the skip mask
//!     suppresses everything it returns 0 having printed nothing, and
//!     `check-local` then reports `Check completed without issues`.
//!   * problems are numbered from 1, contiguously, and the `Found N` summary
//!     agrees with the last number printed.
//!
//! Assertions stop at the architecture separator so they hold on any builder.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

/// `ERROR_TDNF_SOLV_FAILED` surfaces to the shell as `ERROR_TDNF_SOLV`.
const solv_code: u8 = 1301 % 256;
/// `ERROR_TDNF_FILE_NOT_FOUND` for a directory that does not exist.
const not_found_code: u8 = 1602 % 256;

const missing_dep = "tdnf-missing-dep";
const dummy_requires = "tdnf-test-dummy-requires";
const conflicts_0 = "tdnf-test-dummy-conflicts-0";
const conflicts_1 = "tdnf-test-dummy-conflicts-1";
const standalone = "tdnf-repoquery-base";

const summary_prefix = "Found ";
const summary_suffix = " problem(s) while resolving";
const clean_message = "Check completed without issues";

const Diagnostics = struct {
    problems: std.ArrayList([]const u8),
    reported: usize,
    allocator: std.mem.Allocator,

    fn deinit(self: *Diagnostics) void {
        self.problems.deinit(self.allocator);
        self.* = undefined;
    }

    fn contains(self: *const Diagnostics, needle: []const u8) bool {
        for (self.problems.items) |problem| {
            if (std.mem.indexOf(u8, problem, needle) != null) return true;
        }
        return false;
    }

    fn expectContains(self: *const Diagnostics, needle: []const u8) !void {
        if (self.contains(needle)) return;
        std.debug.print("no problem line contained \"{s}\"\n", .{needle});
        for (self.problems.items, 1..) |problem, n| {
            std.debug.print("  {d}. {s}\n", .{ n, problem });
        }
        return error.TestUnexpectedResult;
    }

    fn expectExcludes(self: *const Diagnostics, needle: []const u8) !void {
        if (!self.contains(needle)) return;
        std.debug.print("a problem line unexpectedly contained \"{s}\"\n", .{needle});
        for (self.problems.items, 1..) |problem, n| {
            std.debug.print("  {d}. {s}\n", .{ n, problem });
        }
        return error.TestUnexpectedResult;
    }
};

/// Parses the diagnostic block and asserts its self-consistency: numbers run
/// `1..N` with no gaps and the summary reports exactly `N`. Checking the two
/// against each other rather than against a hardcoded total keeps the contract
/// pinned without breaking when fixture packages are added.
fn parse(allocator: std.mem.Allocator, result: *const harness.Result) !Diagnostics {
    var problems: std.ArrayList([]const u8) = .empty;
    errdefer problems.deinit(allocator);

    var reported: ?usize = null;

    var lines = std.mem.splitScalar(u8, result.stderr, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");

        if (std.mem.startsWith(u8, line, summary_prefix) and
            std.mem.endsWith(u8, line, summary_suffix))
        {
            const digits = line[summary_prefix.len .. line.len - summary_suffix.len];
            if (reported != null) {
                std.debug.print("more than one summary line:\n{s}\n", .{result.stderr});
                return error.TestUnexpectedResult;
            }
            reported = std.fmt.parseInt(usize, digits, 10) catch {
                std.debug.print("unparsable problem count \"{s}\"\n", .{digits});
                return error.TestUnexpectedResult;
            };
            continue;
        }

        const dot = std.mem.indexOfScalar(u8, line, '.') orelse continue;
        if (dot == 0 or dot + 2 > line.len or line[dot + 1] != ' ') continue;
        const number = std.fmt.parseInt(usize, line[0..dot], 10) catch continue;

        if (number != problems.items.len + 1) {
            std.debug.print(
                "problem numbering is not contiguous: expected {d}, found {d}\nstderr:\n{s}\n",
                .{ problems.items.len + 1, number, result.stderr },
            );
            return error.TestUnexpectedResult;
        }
        try problems.append(allocator, line[dot + 2 ..]);
    }

    const count = reported orelse {
        std.debug.print(
            "stderr had no \"{s}N{s}\" summary\nstderr:\n{s}\n",
            .{ summary_prefix, summary_suffix, result.stderr },
        );
        return error.TestUnexpectedResult;
    };

    if (count != problems.items.len) {
        std.debug.print(
            "summary reported {d} problem(s) but {d} were printed\nstderr:\n{s}\n",
            .{ count, problems.items.len, result.stderr },
        );
        return error.TestUnexpectedResult;
    }

    return .{ .problems = problems, .reported = count, .allocator = allocator };
}

/// True when `file_name` is an rpm of package `name` — the basename is
/// `<name>-<version>-…`, so the character after the name must be the `-`
/// introducing a digit. Without the digit check `tdnf-repoquery-base` would
/// also match `tdnf-repoquery-base-extra`.
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
/// absolute path, which is what `check-local` takes as its argument.
///
/// The rpms are copied out of the generated repository seed rather than built
/// here, so these tests use exactly the packages the rest of the suite does.
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

test "check-local reports unsatisfiable requirements as numbered problems" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "broken", &.{ missing_dep, dummy_requires });
    defer std.testing.allocator.free(dir);

    var result = try root.run(&.{ "check-local", dir });
    defer result.deinit();
    try result.expectCode(solv_code);
    try result.expectStdoutContains("Found 2 packages");

    var diagnostics = try parse(std.testing.allocator, &result);
    defer diagnostics.deinit();

    try std.testing.expectEqual(@as(usize, 2), diagnostics.reported);

    // A command-line pool renders these **without** an epoch. The
    // repository-backed assertions in `solverdiag_test.zig` cover the same
    // packages rendered **with** one, so the two files together pin that the
    // epoch rule is per-solvable rather than global.
    try diagnostics.expectContains(
        "nothing provides missing needed by " ++ missing_dep ++ "-1.0.1-2.",
    );
    try diagnostics.expectContains(
        "nothing provides dummy-requirement needed by " ++ dummy_requires ++ "-0.1-1.",
    );
    try diagnostics.expectExcludes(missing_dep ++ "-0:");
    try diagnostics.expectExcludes(dummy_requires ++ "-0:");
}

test "check-local reports a package conflict" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "conflicting", &.{ conflicts_0, conflicts_1 });
    defer std.testing.allocator.free(dir);

    var result = try root.run(&.{ "check-local", dir });
    defer result.deinit();
    try result.expectCode(solv_code);

    var diagnostics = try parse(std.testing.allocator, &result);
    defer diagnostics.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagnostics.reported);
    try diagnostics.expectContains("conflicts with " ++ conflicts_0 ++ " provided by ");
    try diagnostics.expectContains(conflicts_0 ++ "-0.1-1.");
}

test "check-local skipping every problem is silent success" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "conflicting", &.{ conflicts_0, conflicts_1 });
    defer std.testing.allocator.free(dir);

    var result = try root.run(&.{ "--setopt=skipconflicts=1", "check-local", dir });
    defer result.deinit();

    // `SolvReportProblems` assigns its error inside the report loop, so a run
    // whose every problem is skipped returns 0 having printed nothing at all --
    // not merely a run that prints an empty problem list.
    try result.expectOk();
    try result.expectStdoutContains(clean_message);
    try std.testing.expect(!result.stderrContains(summary_suffix));
    try std.testing.expect(!result.stderrContains("conflicts with"));
}

test "check-local skip mask leaves unrelated problems reported" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "broken", &.{ missing_dep, dummy_requires });
    defer std.testing.allocator.free(dir);

    // The mask suppresses conflicts; these problems are unsatisfied
    // requirements, so all of them must still be reported and renumbered from 1.
    var result = try root.run(&.{ "--setopt=skipconflicts=1", "check-local", dir });
    defer result.deinit();
    try result.expectCode(solv_code);

    var diagnostics = try parse(std.testing.allocator, &result);
    defer diagnostics.deinit();

    try std.testing.expectEqual(@as(usize, 2), diagnostics.reported);
}

test "check-local on a satisfiable directory succeeds" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageRpms(&root, "clean", &.{standalone});
    defer std.testing.allocator.free(dir);

    var result = try root.run(&.{ "check-local", dir });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains("Found 1 packages");
    try result.expectStdoutContains(clean_message);
}

test "check-local on an empty directory succeeds" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try root.tmp.dir.createDirPath(io, "empty");
    const dir = try std.fs.path.join(std.testing.allocator, &.{ root.path, "empty" });
    defer std.testing.allocator.free(dir);

    var result = try root.run(&.{ "check-local", dir });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains("Found 0 packages");
    try result.expectStdoutContains(clean_message);
}

test "check-local on a missing directory fails" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "check-local", "/nonexistent-check-local-dir" });
    defer result.deinit();
    try result.expectCode(not_found_code);
    try std.testing.expect(!result.stderrContains(summary_suffix));
}
