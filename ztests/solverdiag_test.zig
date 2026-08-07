//! Solver failure-path diagnostics: the text `SolvReportProblems`
//! (`solv/tdnfpackage.c`) writes when a solve cannot be satisfied.
//!
//! These assertions exist because `libsolv-oracle-test` **structurally cannot**
//! cover this output. The oracle crosschecks *successful* solves against
//! libsolv; every message here is produced only when a solve **fails**, so the
//! entire diagnostic path is invisible to it. Before this file, the only thing
//! pinning it anywhere in the tree was `protected_test.zig` asserting one
//! `requires <name>` fragment — the numbering and the summary line had no
//! coverage at all.
//!
//! Two properties are easy to lose in a port and are therefore asserted
//! directly rather than incidentally:
//!
//!   * problems are numbered from 1 and **renumbered contiguously after
//!     skipping**, because the counter is `++total_prblms` over the *reported*
//!     problems, not the solver's problem index. A port that numbered by
//!     solver index would print `7. 8. 9.` where tdnf prints `1. 2. 3.`.
//!   * the `Found N problem(s)` summary counts *reported* problems, so it
//!     agrees with the last number printed.
//!
//! Package identifiers in these messages carry the build architecture
//! (`…-0:1.0.1-2.aarch64`), so assertions stop at the arch separator rather
//! than hardcoding a machine.

const std = @import("std");
const harness = @import("harness.zig");

/// `ERROR_TDNF_SOLV_FAILED` surfaces to the shell as `ERROR_TDNF_SOLV`.
const solv_code: u8 = 1301 % 256;

const missing_dep = "tdnf-missing-dep";
const conflicts_0 = "tdnf-test-dummy-conflicts-0";
const conflicts_1 = "tdnf-test-dummy-conflicts-1";
const leaf = "tdnf-test-cleanreq-leaf1";
const required = "tdnf-test-cleanreq-required";
/// A package with no unsatisfiable dependency, used as the half of a request
/// that has to survive when the other half is skipped.
const satisfiable = "tdnf-test-one";

const summary_prefix = "Found ";
const summary_suffix = " problem(s) while resolving";

/// The parsed diagnostic block: the `N. <text>` lines and the count the
/// summary line reported.
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

/// Parses the diagnostic block out of stderr and asserts its self-consistency:
/// the numbers run `1..N` with no gaps, and the summary reports exactly `N`.
///
/// Checking the numbering against the summary rather than against a hardcoded
/// total keeps the contract pinned without making the test brittle to fixture
/// packages being added to the repository.
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

        // The counter is `++total_prblms`, so the first reported problem is 1
        // and every later one is exactly one more than the last.
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

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

fn eraseBestEffort(root: *harness.Root, name: []const u8) void {
    var result = root.run(&.{ "erase", "-y", name }) catch return;
    defer result.deinit();
}

test "an unsatisfiable requirement is reported as a numbered problem" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", missing_dep });
    defer result.deinit();
    try result.expectCode(solv_code);

    var diagnostics = try parse(std.testing.allocator, &result);
    defer diagnostics.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagnostics.reported);
    // Arch-independent: the identifier ends `…-0:1.0.1-2.<arch>`.
    try diagnostics.expectContains(
        "nothing provides missing needed by " ++ missing_dep ++ "-0:1.0.1-2.",
    );
    try std.testing.expect(!try root.isInstalled(missing_dep));
}

test "a package conflict is reported as a numbered problem" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{
        "install", "-y", "--nogpgcheck", conflicts_0, conflicts_1,
    });
    defer result.deinit();
    try result.expectCode(solv_code);

    var diagnostics = try parse(std.testing.allocator, &result);
    defer diagnostics.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagnostics.reported);
    try diagnostics.expectContains(
        "package " ++ conflicts_1 ++ "-0:0.1-1.",
    );
    try diagnostics.expectContains(
        "conflicts with " ++ conflicts_0 ++ " provided by " ++ conflicts_0 ++ "-0:0.1-1.",
    );
    try std.testing.expect(!try root.isInstalled(conflicts_0));
    try std.testing.expect(!try root.isInstalled(conflicts_1));
}

test "refusing to erase a locked dependent reports the full diagnostic" {
    // A locked dependent is used rather than a protected one because
    // protection is now reported as ERROR_TDNF_PROTECTED with its own
    // message (see protected_test.zig); locking produces the same
    // unsatisfiable solve and therefore still exercises this diagnostic.
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, leaf);
    defer eraseBestEffort(&root, required);
    defer root.tmp.dir.deleteTree(std.testing.io, "locks.d") catch {};

    try install(&root, leaf);
    try root.tmp.dir.createDirPath(std.testing.io, "locks.d");
    try root.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "locks.d/test.conf",
        .data = leaf,
    });

    var result = try root.run(&.{ "-y", "--nogpgcheck", "remove", required });
    defer result.deinit();
    try result.expectCode(solv_code);

    var diagnostics = try parse(std.testing.allocator, &result);
    defer diagnostics.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagnostics.reported);
    // `protected_test.zig` pins the `requires <name>` fragment; this pins the
    // whole line, including the "none of the providers" tail that explains why
    // the locked dependent blocks the erase.
    try diagnostics.expectContains("package " ++ leaf ++ "-1.0.1-3.");
    try diagnostics.expectContains(
        "requires " ++ required ++ ", but none of the providers can be installed",
    );
    try std.testing.expect(try root.isInstalled(leaf));
    try std.testing.expect(try root.isInstalled(required));
}

test "a solve that fails for its own reasons keeps its diagnostic when packages are protected" {
    // The protected-package probe re-solves with protection dropped and only
    // renames the error when that made the request solvable. A request that
    // is unsatisfiable regardless must keep its solver error and its
    // problem text.
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, leaf);
    defer eraseBestEffort(&root, required);
    defer root.tmp.dir.deleteTree(std.testing.io, "protected.d") catch {};

    try install(&root, leaf);
    try root.tmp.dir.createDirPath(std.testing.io, "protected.d");
    try root.tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "protected.d/test.conf",
        .data = leaf,
    });

    var result = try root.run(&.{
        "-y",           "--nogpgcheck", "install",
        conflicts_0, conflicts_1,
    });
    defer result.deinit();
    try result.expectCode(solv_code);

    var diagnostics = try parse(std.testing.allocator, &result);
    defer diagnostics.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagnostics.reported);
    try diagnostics.expectContains(
        "conflicts with " ++ conflicts_0 ++ " provided by " ++ conflicts_0 ++ "-0:0.1-1.",
    );
    try result.expectStderrContains("Error(1301)");
    try std.testing.expect(try root.isInstalled(leaf));
}

test "multiple problems are numbered and counted together" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{
        "install",   "-y",        "--nogpgcheck",
        missing_dep, conflicts_0, conflicts_1,
    });
    defer result.deinit();
    try result.expectCode(solv_code);

    var diagnostics = try parse(std.testing.allocator, &result);
    defer diagnostics.deinit();

    // Both failures are reported in one run rather than the solve stopping at
    // the first. `parse` has already checked they are numbered 1 then 2 and
    // that the summary agrees.
    try std.testing.expectEqual(@as(usize, 2), diagnostics.reported);
    try diagnostics.expectContains("nothing provides missing needed by " ++ missing_dep);
    try diagnostics.expectContains("conflicts with " ++ conflicts_0);
}

// `--skip-broken` reaches the solver rather than the reporter: the request is
// unsatisfiable as written, but the unsatisfiable job is dropped and the rest
// of it resolves. Nothing is reported and the command succeeds.
test "--skip-broken drops the unsatisfiable job and resolves the rest" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, satisfiable);

    var result = try root.run(&.{
        "install", "-y", "--nogpgcheck", "--skip-broken", satisfiable, missing_dep,
    });
    defer result.deinit();
    try result.expectOk();

    // No diagnostic block at all: a skipped job is not a reported problem.
    try std.testing.expect(!result.stderrContains(summary_suffix));
    try std.testing.expect(try root.isInstalled(satisfiable));
    try std.testing.expect(!try root.isInstalled(missing_dep));
}

// A skip filter removes problems from the *report*; it does not make the
// request satisfiable. With the only problem skipped there is nothing to
// print, and the request must still fail without changing anything.
test "a request whose only problem is skipped still fails and installs nothing" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{
        "install", "-y", "--nogpgcheck", "--skipconflicts", conflicts_0, conflicts_1,
    });
    defer result.deinit();

    if (result.code == 0) {
        std.debug.print(
            "a skipped conflict must not make the request succeed\nstdout:\n{s}\nstderr:\n{s}\n",
            .{ result.stdout, result.stderr },
        );
        return error.TestUnexpectedResult;
    }
    try std.testing.expect(!result.stderrContains("conflicts with"));
    try std.testing.expect(!try root.isInstalled(conflicts_0));
    try std.testing.expect(!try root.isInstalled(conflicts_1));
}

test "skipped problems are excluded from the count and the rest renumbered" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var all = try root.run(&.{"check"});
    defer all.deinit();
    try all.expectCode(solv_code);

    var everything = try parse(std.testing.allocator, &all);
    defer everything.deinit();

    // The seed repository has conflicts and obsoletes problems as well as
    // unsatisfiable requires, which is what makes the skip meaningful.
    try everything.expectContains("conflicts with");
    try everything.expectContains("obsoletes");
    try everything.expectContains("nothing provides");

    var skipped = try root.run(&.{ "check", "--skipconflicts", "--skipobsoletes" });
    defer skipped.deinit();
    try skipped.expectCode(solv_code);

    var remaining = try parse(std.testing.allocator, &skipped);
    defer remaining.deinit();

    try remaining.expectExcludes("conflicts with");
    try remaining.expectExcludes("obsoletes");
    try remaining.expectContains("nothing provides");

    // Skipping must remove problems from the report, not merely silence them:
    // the summary shrinks, and `parse` has already asserted that what remains
    // is numbered `1..N` with no gap where a skipped problem used to sit.
    try std.testing.expect(remaining.reported < everything.reported);
}
