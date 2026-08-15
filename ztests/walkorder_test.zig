//! The order `--repofromdir` walks its directory in.
//!
//! Package order is not cosmetic. It becomes the repository's solvable order,
//! solvable order becomes rule order, and `solver_findproblemrule` picks its
//! representative by rule order -- so the walk decides *which* problem is
//! reported, in what order, and with which operand first in a
//! `cannot install both A and B` message.
//!
//! `--repofromdir` had two different walks. `repomd/directory_repository.zig`
//! sorted the collected paths on the solve and query paths, while the
//! transaction-plan path loads the same directory through libsolv's
//! `readRpmsFromDir` (`solv/rpmzrepo.c`), which takes them in readdir order.
//! Two orders for one repository is two answers for one question (#266).
//!
//! Readdir order is now authoritative on every path, matching libsolv and
//! matching what `check-local` was already pinned to. `repoquery` emits the
//! repository's packages in model order, so this file asserts that emission
//! against the directory's *own* readdir order, read at test time. That keeps
//! the assertion exact without hard-coding an order the filesystem chooses:
//! ext4 hands entries back in hash order and tmpfs in creation order, and the
//! test is correct on both.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

const staged_dir = "walkorder";

/// Copies every `.rpm` under `source` into `target`, flattening the seed's
/// per-arch subdirectories so the staged directory has exactly one readdir
/// order to compare against.
fn flattenRpms(
    allocator: std.mem.Allocator,
    source: []const u8,
    target: *std.Io.Dir,
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
            try flattenRpms(allocator, path, target, copied);
            continue;
        }
        if (!std.mem.endsWith(u8, entry.name, ".rpm")) continue;

        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
        defer allocator.free(bytes);
        try target.writeFile(io, .{ .sub_path = entry.name, .data = bytes });
        copied.* += 1;
    }
}

/// Stages the whole fixture corpus flat and returns its absolute path.
///
/// The corpus is used whole rather than a hand-picked pair because a two-file
/// directory can trivially come back in sorted order by accident, which would
/// make the assertion below agree with a sorted walk as well.
fn stageCorpus(root: *harness.Root) ![]const u8 {
    const allocator = root.allocator;

    try root.tmp.dir.createDirPath(io, staged_dir);
    var target = try root.tmp.dir.openDir(io, staged_dir, .{});
    defer target.close(io);

    const source = try std.fs.path.join(
        allocator,
        &.{ root.layout.repo_dir, "photon-test", "RPMS" },
    );
    defer allocator.free(source);

    var copied: usize = 0;
    try flattenRpms(allocator, source, &target, &copied);
    if (copied < 8) {
        std.debug.print("staged only {d} rpm(s) from {s}\n", .{ copied, source });
        return error.TestUnexpectedResult;
    }

    return std.fs.path.join(allocator, &.{ root.path, staged_dir });
}

/// The staged directory's readdir order, as `<name>-<version>-<release>.<arch>`
/// -- the `.rpm` suffix stripped, which is exactly what `repoquery` prints.
///
/// Caller owns the returned list and every string in it.
fn readdirNevras(allocator: std.mem.Allocator, dir_path: []const u8) !std.ArrayList([]const u8) {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit(allocator);
    }

    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterateAssumeFirstIteration();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".rpm")) continue;
        const nevra = entry.name[0 .. entry.name.len - ".rpm".len];
        try out.append(allocator, try allocator.dupe(u8, nevra));
    }

    return out;
}

fn freeList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit(allocator);
}

fn isSorted(items: []const []const u8) bool {
    var index: usize = 1;
    while (index < items.len) : (index += 1) {
        if (std.mem.order(u8, items[index - 1], items[index]) == .gt) return false;
    }
    return true;
}

test "repoquery emits a directory repository in the filesystem's readdir order" {
    const allocator = std.testing.allocator;

    var h = try harness.open(allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageCorpus(&root);
    defer allocator.free(dir);

    var expected = try readdirNevras(allocator, dir);
    defer freeList(allocator, &expected);

    // A directory that readdir happens to hand back sorted would agree with a
    // sorted walk too, so the assertion would stop discriminating. The fixture
    // corpus is large enough that this does not happen on ext4 or tmpfs, but
    // say so rather than report a vacuous pass.
    if (isSorted(expected.items)) {
        std.debug.print(
            "readdir returned {d} entries already sorted; this run cannot tell the two walks apart\n",
            .{expected.items.len},
        );
        return error.TestUnexpectedResult;
    }

    const arg = try std.fmt.allocPrint(allocator, "--repofromdir=fromdir,{s}", .{dir});
    defer allocator.free(arg);

    var result = try root.run(&.{ arg, "--repo=fromdir", "repoquery" });
    defer result.deinit();
    try result.expectOk();

    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    var index: usize = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (index >= expected.items.len) {
            std.debug.print(
                "repoquery printed more packages than the directory holds:\n{s}\n",
                .{result.stdout},
            );
            return error.TestUnexpectedResult;
        }
        if (!std.mem.eql(u8, expected.items[index], line)) {
            std.debug.print(
                "package {d} is '{s}' but the directory's readdir order has '{s}'\n",
                .{ index, line, expected.items[index] },
            );
            return error.TestUnexpectedResult;
        }
        index += 1;
    }

    try std.testing.expectEqual(expected.items.len, index);
}

test "check-local walks the same directory in the same order" {
    const allocator = std.testing.allocator;

    var h = try harness.open(allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    const dir = try stageCorpus(&root);
    defer allocator.free(dir);

    var expected = try readdirNevras(allocator, dir);
    defer freeList(allocator, &expected);

    // `check-local` builds its own libsolv pool over the directory and was
    // already pinned to the readdir walk. It and `--repofromdir` are the two
    // consumers of `directory_repository`, so a divergence between them is the
    // regression this file guards.
    var check = try root.run(&.{ "check-local", dir });
    defer check.deinit();
    try check.expectStdoutContains("Checking all packages from: ");

    const found = try std.fmt.allocPrint(allocator, "Found {d} packages", .{expected.items.len});
    defer allocator.free(found);
    try check.expectStdoutContains(found);

    // The walk order is observable through `repoquery`, which emits packages
    // in model order. Pick a pair that readdir returns *out* of lexical order:
    // a sorted walk would print them the other way round, so the assertion
    // fails against the walk this change removed. Deriving the pair from the
    // directory rather than naming packages keeps it correct on every
    // architecture -- the fixture corpus is built by `rpmbuild` on the host,
    // so the NEVRAs carry `aarch64` on an arm64 runner.
    var inverted: ?[2][]const u8 = null;
    outer: for (expected.items, 0..) |earlier, position| {
        for (expected.items[position + 1 ..]) |later| {
            if (std.mem.order(u8, earlier, later) == .gt) {
                inverted = .{ earlier, later };
                break :outer;
            }
        }
    }

    const pair = inverted orelse {
        std.debug.print(
            "readdir returned {d} entries already sorted; this run cannot tell the two walks apart\n",
            .{expected.items.len},
        );
        return error.TestUnexpectedResult;
    };

    const arg = try std.fmt.allocPrint(allocator, "--repofromdir=fromdir,{s}", .{dir});
    defer allocator.free(arg);

    var query = try root.run(&.{ arg, "--repo=fromdir", "repoquery" });
    defer query.deinit();
    try query.expectOk();

    var first: ?usize = null;
    var second: ?usize = null;
    var lines = std.mem.tokenizeScalar(u8, query.stdout, '\n');
    var index: usize = 0;
    while (lines.next()) |raw| : (index += 1) {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, pair[0])) first = index;
        if (std.mem.eql(u8, line, pair[1])) second = index;
    }

    if (first == null or second == null) {
        std.debug.print(
            "repoquery did not list '{s}' and '{s}':\n{s}\n",
            .{ pair[0], pair[1], query.stdout },
        );
        return error.TestUnexpectedResult;
    }

    if (first.? > second.?) {
        std.debug.print(
            "repoquery put '{s}' after '{s}', but readdir returns it first\n",
            .{ pair[0], pair[1] },
        );
        return error.TestUnexpectedResult;
    }
}
