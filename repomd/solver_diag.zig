//! Native rendering of solver diagnostics.
//!
//! Turns the structured, unsatisfiable-core problems enumerated by
//! `solver_result.collectCores` into the exact human-readable strings that
//! libsolv's `solver_problemruleinfo2str` produced, so libtdnf can report
//! resolution failures without any libsolv solver state.
//!
//! Package names render as `name-[epoch:]version-release.arch`, showing the
//! epoch whenever the package carries one (including epoch 0, as repository
//! packages do) and omitting it for installed packages that have none — the
//! same per-package distinction libsolv's `pool_solvid2str` makes. Capability
//! strings are rendered locally (see `formatRelation`) to match libsolv's
//! `pool_dep2str`, e.g. `name < 0:9`.
//!
//! Problems render in libsolv's report order, which is the reverse of the
//! order the solver discovers the cores (libsolv walks its problem list from
//! `solver_problem_count()` down to 1). The transposition of two problems on a
//! single capability with multiple providers (the only case tdnf's corpus
//! exercises) is not reproduced; see `solver_result.collectCores`.

const std = @import("std");
const metadata = @import("model.zig");
const solver_model = @import("solver_model.zig");
const solver_result = @import("solver_result.zig");
const solver_rules = @import("solver_rules.zig");

pub const RenderError = solver_result.DeriveProblemsError;

/// Category used to reproduce `SkipBasedOnType`. The numeric values are part
/// of the C ABI (see `TDNF_NATIVE_PROBLEM_SKIP_*` in tdnfrepomd.h).
pub const SkipClass = enum(u32) {
    other = 0,
    conflict = 1,
    obsoletes = 2,
    requires = 3,
    not_installable = 4,
    not_installable_disabled = 5,
};

pub const RenderedProblem = struct {
    message: [:0]const u8,
    skip_class: SkipClass,
};

pub const OwnedRenderedProblems = struct {
    arena_state: std.heap.ArenaAllocator,
    items: []const RenderedProblem,

    pub fn deinit(self: *OwnedRenderedProblems) void {
        self.arena_state.deinit();
        self.* = undefined;
    }
};

/// An empty rendered set, for failure branches that have no formula core.
pub fn emptyRendered(allocator: std.mem.Allocator) OwnedRenderedProblems {
    return .{
        .arena_state = std.heap.ArenaAllocator.init(allocator),
        .items = &.{},
    };
}

/// Render every independent unsatisfiable core of `formula` into libsolv-style
/// diagnostic strings, ordered exactly as libsolv would report them.
pub fn renderUnsatProblems(
    allocator: std.mem.Allocator,
    formula: *const solver_rules.OwnedFormula,
) RenderError!OwnedRenderedProblems {
    const records = try solver_result.collectCores(allocator, formula);
    defer allocator.free(records);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();

    var rendered = std.array_list.Managed(RenderedProblem).init(arena);

    // libsolv walks its problem list in reverse; the search discovers cores in
    // forward order, so reverse to match the reported ordering.
    var index: usize = records.len;
    while (index > 0) {
        index -= 1;
        const record = records[index];
        const message = try renderProblem(arena, formula.universe, record);
        try rendered.append(.{
            .message = message,
            .skip_class = skipClassFor(record),
        });
    }

    return .{
        .arena_state = arena_state,
        .items = try rendered.toOwnedSlice(),
    };
}

fn renderProblem(
    arena: std.mem.Allocator,
    universe: *const solver_model.Universe,
    record: solver_result.CoreRecord,
) RenderError![:0]const u8 {
    const problem = record.problem;
    switch (problem.kind) {
        .unsatisfied_requirement => {
            const dep = try renderCapability(arena, problem.capability);
            const source = try renderPackage(arena, universe, problem.package);
            if (record.requires_has_providers) {
                return std.fmt.allocPrintSentinel(arena, "package {s} requires {s}, but none of the providers can be installed", .{ source, dep }, 0);
            }
            return std.fmt.allocPrintSentinel(arena, "nothing provides {s} needed by {s}", .{ dep, source }, 0);
        },
        .conflict => {
            const source = try renderPackage(arena, universe, problem.package);
            const dep = try renderCapability(arena, problem.capability);
            const target = try renderPackage(arena, universe, problem.related_package);
            return std.fmt.allocPrintSentinel(arena, "package {s} conflicts with {s} provided by {s}", .{ source, dep, target }, 0);
        },
        .obsoletes => {
            const source = try renderPackage(arena, universe, problem.package);
            const dep = try renderCapability(arena, problem.capability);
            const target = try renderPackage(arena, universe, problem.related_package);
            return std.fmt.allocPrintSentinel(arena, "package {s} obsoletes {s} provided by {s}", .{ source, dep, target }, 0);
        },
        .not_installable => {
            const source = try renderPackage(arena, universe, problem.package);
            if (record.not_installable_disabled) {
                return std.fmt.allocPrintSentinel(arena, "package {s} is disabled", .{source}, 0);
            }
            return std.fmt.allocPrintSentinel(arena, "package {s} is not installable", .{source}, 0);
        },
        .no_candidate => {
            const dep = try renderCapability(arena, problem.capability);
            return std.fmt.allocPrintSentinel(arena, "nothing provides requested {s}", .{dep}, 0);
        },
        // These are policy problems that never originate from a formula core;
        // the diagnostics path only renders solver-core problems.
        .protected_package, .installonly_limit => return error.UnsupportedProblem,
    }
}

fn skipClassFor(
    record: solver_result.CoreRecord,
) SkipClass {
    return switch (record.problem.kind) {
        .conflict => .conflict,
        .obsoletes => .obsoletes,
        .unsatisfied_requirement => .requires,
        .not_installable => if (record.not_installable_disabled)
            .not_installable_disabled
        else
            .not_installable,
        else => .other,
    };
}

fn renderCapability(
    arena: std.mem.Allocator,
    capability: ?metadata.Relation,
) RenderError![]const u8 {
    const relation = capability orelse return error.InvalidInput;
    return formatRelation(arena, relation);
}

/// Render a dependency capability the way libsolv's `pool_dep2str` does — a
/// bare name, or `name <op> [epoch:]version[-release]` when the capability is
/// versioned. Kept local so the diagnostics renderer does not pull in the
/// package-query module (and its rpm/xml dependency chain).
fn formatRelation(
    arena: std.mem.Allocator,
    relation: metadata.Relation,
) RenderError![]const u8 {
    const has_evr = relation.epoch != null or
        relation.version != null or
        relation.release != null;
    if (!has_evr or relation.comparison == .none) {
        return arena.dupe(u8, relation.name);
    }
    const evr = try formatEvrText(
        arena,
        relation.epoch,
        relation.version,
        relation.release,
    );
    return std.fmt.allocPrint(arena, "{s} {s} {s}", .{
        relation.name,
        compareOpText(relation.comparison),
        evr,
    });
}

fn formatEvrText(
    arena: std.mem.Allocator,
    maybe_epoch: ?u32,
    maybe_version: ?[]const u8,
    maybe_release: ?[]const u8,
) RenderError![]const u8 {
    const version_text = maybe_version orelse "";
    const release_text = maybe_release orelse "";
    if (maybe_epoch) |value| {
        if (maybe_release != null) {
            return std.fmt.allocPrint(arena, "{d}:{s}-{s}", .{ value, version_text, release_text });
        }
        return std.fmt.allocPrint(arena, "{d}:{s}", .{ value, version_text });
    }
    if (maybe_release != null) {
        if (maybe_version != null and version_text.len != 0) {
            return std.fmt.allocPrint(arena, "{s}-{s}", .{ version_text, release_text });
        }
        return arena.dupe(u8, release_text);
    }
    return arena.dupe(u8, version_text);
}

fn compareOpText(op: metadata.CompareOp) []const u8 {
    return switch (op) {
        .none => "",
        .eq => "=",
        .lt => "<",
        .le => "<=",
        .gt => ">",
        .ge => ">=",
    };
}

fn renderPackage(
    arena: std.mem.Allocator,
    universe: *const solver_model.Universe,
    package_id: ?solver_model.PackageId,
) RenderError![]const u8 {
    const id = package_id orelse return error.InvalidInput;
    const package = universe.package(id) orelse return error.InvalidInput;
    const nevra = package.source.nevra;
    const has_arch = nevra.arch.len != 0;
    if (nevra.epoch) |epoch_value| {
        if (has_arch) {
            return std.fmt.allocPrint(arena, "{s}-{d}:{s}-{s}.{s}", .{ nevra.name, epoch_value, nevra.version, nevra.release, nevra.arch });
        }
        return std.fmt.allocPrint(arena, "{s}-{d}:{s}-{s}", .{ nevra.name, epoch_value, nevra.version, nevra.release });
    }
    if (has_arch) {
        return std.fmt.allocPrint(arena, "{s}-{s}-{s}.{s}", .{ nevra.name, nevra.version, nevra.release, nevra.arch });
    }
    return std.fmt.allocPrint(arena, "{s}-{s}-{s}", .{ nevra.name, nevra.version, nevra.release });
}
