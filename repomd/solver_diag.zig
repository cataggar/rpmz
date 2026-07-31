//! Native rendering of solver failure diagnostics.
//!
//! Turns the structured, unsatisfiable-core problems the native solver
//! enumerates (`solver_result`, in core *discovery* order) into the exact
//! human-readable strings that libsolv's `solver_problemruleinfo2str` produced,
//! so libtdnf can report a failed resolution without any libsolv solver state.
//!
//! libsolv walks its problem list from `solver_problem_count()` down to 1, so
//! it reports problems in the reverse of the order it discovered the cores.
//! `renderProblems` receives the problems in discovery order and reverses them,
//! reproducing libsolv's report order.
//!
//! Package names render as `name-[epoch:]version-release.arch`, showing the
//! epoch whenever the package carries one (including epoch 0, as repository
//! packages do) and omitting it for installed packages that have none — the
//! same per-package distinction libsolv's `pool_solvid2str` makes. Capability
//! strings are rendered locally (see `formatRelation`) to match libsolv's
//! `pool_dep2str`, e.g. `name < 0:9`.
//!
//! The single `unsatisfied_requirement` kind covers three of libsolv's
//! requirement rules; `classifyRequirement` inspects the pool to select between
//! "nothing provides Y needed by X" (no provider at all), "package X requires
//! Y, but none of the providers can be installed" (visible providers exist),
//! and "package P is disabled" (the sole provider is `--exclude`-hidden), the
//! way libsolv splits `SOLVER_RULE_PKG_NOTHING_PROVIDES_DEP`,
//! `SOLVER_RULE_PKG_REQUIRES`, and `SOLVER_RULE_PKG_NOT_INSTALLABLE`.

const std = @import("std");
const metadata = @import("model.zig");
const solver_model = @import("solver_model.zig");
const index = @import("index.zig");

pub const RenderError = error{ OutOfMemory, InvalidInput, UnsupportedProblem };

/// Category used to reproduce libsolv's `SkipBasedOnType` filtering. The
/// classes are consumed entirely within the native solver: `root.zig`'s
/// refuted-problem accessor maps the active `TDNF_SKIPPROBLEM_TYPE` mask onto
/// them (and gates a `requires` survivor through `check_for_providers`) so the
/// C caller never sees the raw libsolv rule taxonomy.
pub const SkipClass = enum(u32) {
    other = 0,
    conflict = 1,
    obsoletes = 2,
    requires = 3,
    not_installable = 4,
    not_installable_disabled = 5,
    nothing_provides = 6,
    /// SOLVER_RULE_PKG_SAME_NAME. SkipBasedOnType did not list it under
    /// --skipconflicts or --skipobsoletes, but it is inside the
    /// SOLVER_RULE_PKG range that --skip-broken filters.
    same_name = 7,
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

/// An empty rendered set, for failure branches that have no core to render.
pub fn emptyRendered(allocator: std.mem.Allocator) OwnedRenderedProblems {
    return .{
        .arena_state = std.heap.ArenaAllocator.init(allocator),
        .items = &.{},
    };
}

/// Render every enumerated problem into libsolv-style diagnostic strings,
/// ordered exactly as libsolv would report them.
///
/// `problems` are in core discovery order; libsolv reports in reverse, so the
/// list is walked backwards. `universe` is the full retained package set the
/// refute was built from (used to render names and to look up providers), and
/// `hidden` is the packages an `--exclude`-style filter kept out of the solve.
pub fn renderProblems(
    allocator: std.mem.Allocator,
    problems: []const solver_model.Problem,
    universe: *const solver_model.Universe,
    hidden: []const solver_model.PackageId,
) RenderError!OwnedRenderedProblems {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();

    var rendered = std.array_list.Managed(RenderedProblem).init(arena);
    try rendered.ensureTotalCapacity(problems.len);

    var i: usize = problems.len;
    while (i > 0) {
        i -= 1;
        const problem = problems[i];
        const cls = classify(universe, hidden, problem);
        const message = try renderProblem(arena, universe, problem, cls);
        rendered.appendAssumeCapacity(.{
            .message = message,
            .skip_class = skipClassFor(problem, cls),
        });
    }

    return .{
        .arena_state = arena_state,
        .items = try rendered.toOwnedSlice(),
    };
}

/// How libsolv would render an unsatisfied requirement. The pool splits it into
/// three distinct rules depending on the state of the providers.
const RequirementClass = enum {
    /// No package in the pool provides the capability at all
    /// (`SOLVER_RULE_PKG_NOTHING_PROVIDES_DEP`).
    nothing_provides,
    /// Providers exist and are visible, but none can be installed
    /// (`SOLVER_RULE_PKG_REQUIRES`).
    requires_no_install,
    /// The only providers are `--exclude`-hidden, so libsolv blames the
    /// disabled provider directly (`SOLVER_RULE_PKG_NOT_INSTALLABLE`).
    disabled,
};

/// Pre-computed, kind-specific classification shared by the message renderer
/// and the skip-class mapper so both agree on how a problem is categorised.
const Classification = struct {
    req: RequirementClass = .nothing_provides,
    disabled_provider: ?solver_model.PackageId = null,
    not_installable_disabled: bool = false,
};

fn classify(
    universe: *const solver_model.Universe,
    hidden: []const solver_model.PackageId,
    problem: solver_model.Problem,
) Classification {
    return switch (problem.kind) {
        .unsatisfied_requirement => classifyRequirement(universe, hidden, problem.capability),
        .not_installable => .{
            .not_installable_disabled = packageHidden(hidden, problem.package),
        },
        else => .{},
    };
}

fn renderProblem(
    arena: std.mem.Allocator,
    universe: *const solver_model.Universe,
    problem: solver_model.Problem,
    cls: Classification,
) RenderError![:0]const u8 {
    switch (problem.kind) {
        .unsatisfied_requirement => switch (cls.req) {
            .disabled => {
                const source = try renderPackage(arena, universe, cls.disabled_provider);
                return std.fmt.allocPrintSentinel(arena, "package {s} is disabled", .{source}, 0);
            },
            .requires_no_install => {
                const dep = try renderCapability(arena, problem.capability);
                const source = try renderPackage(arena, universe, problem.package);
                return std.fmt.allocPrintSentinel(arena, "package {s} requires {s}, but none of the providers can be installed", .{ source, dep }, 0);
            },
            .nothing_provides => {
                const dep = try renderCapability(arena, problem.capability);
                const source = try renderPackage(arena, universe, problem.package);
                return std.fmt.allocPrintSentinel(arena, "nothing provides {s} needed by {s}", .{ dep, source }, 0);
            },
        },
        .conflict => {
            const source = try renderPackage(arena, universe, problem.package);
            const dep = try renderCapability(arena, problem.capability);
            const target = try renderPackage(arena, universe, problem.related_package);
            return std.fmt.allocPrintSentinel(arena, "package {s} conflicts with {s} provided by {s}", .{ source, dep, target }, 0);
        },
        .same_name => {
            const source = try renderPackage(arena, universe, problem.package);
            const target = try renderPackage(arena, universe, problem.related_package);
            return std.fmt.allocPrintSentinel(arena, "cannot install both {s} and {s}", .{ source, target }, 0);
        },
        .obsoletes => {
            const source = try renderPackage(arena, universe, problem.package);
            const dep = try renderCapability(arena, problem.capability);
            const target = try renderPackage(arena, universe, problem.related_package);
            return std.fmt.allocPrintSentinel(arena, "package {s} obsoletes {s} provided by {s}", .{ source, dep, target }, 0);
        },
        .not_installable => {
            const source = try renderPackage(arena, universe, problem.package);
            if (cls.not_installable_disabled) {
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
    problem: solver_model.Problem,
    cls: Classification,
) SkipClass {
    return switch (problem.kind) {
        .conflict => .conflict,
        .same_name => .same_name,
        .obsoletes => .obsoletes,
        // libsolv splits an unsatisfied requirement into three rules:
        // SOLVER_RULE_PKG_REQUIRES ("requires X, but none of the providers can
        // be installed", when providers exist and are visible),
        // SOLVER_RULE_PKG_NOTHING_PROVIDES_DEP ("nothing provides X"), and
        // SOLVER_RULE_PKG_NOT_INSTALLABLE ("<provider> is disabled", when the
        // sole provider is --exclude-hidden). Only the REQUIRES rule was gated
        // by check_for_providers, so they need distinct skip classes even
        // though SkipBasedOnType treats all three as package rules.
        .unsatisfied_requirement => switch (cls.req) {
            .requires_no_install => .requires,
            .nothing_provides => .nothing_provides,
            .disabled => .not_installable_disabled,
        },
        .not_installable => if (cls.not_installable_disabled)
            .not_installable_disabled
        else
            .not_installable,
        else => .other,
    };
}

/// Classify an unsatisfied requirement the way libsolv's problem rules do. A
/// requirement with no provider at all is NOTHING_PROVIDES; one whose sole
/// providers are `--exclude`-hidden is blamed on the disabled provider
/// (NOT_INSTALLABLE); anything else is REQUIRES. This scans the whole universe
/// (installed and available, ignoring visibility, exactly as libsolv's
/// whatprovides index does) and honours the capability's version range.
fn classifyRequirement(
    universe: *const solver_model.Universe,
    hidden: []const solver_model.PackageId,
    capability: ?metadata.Relation,
) Classification {
    const relation = capability orelse return .{ .req = .nothing_provides };
    const query = index.DependencyQuery{
        .name = relation.name,
        .comparison = relation.comparison,
        .epoch = relation.epoch,
        .version = relation.version,
        .release = relation.release,
    };
    const is_file_dep = relation.name.len != 0 and relation.name[0] == '/';
    var any_provider = false;
    var visible_provider = false;
    var first_hidden: ?solver_model.PackageId = null;
    for (universe.packages) |package| {
        var provides = false;
        for (package.relationEntries(universe, .provides)) |provide| {
            if (index.relationMatchesQuery(provide, query)) {
                provides = true;
                break;
            }
        }
        if (!provides and index.relationMatchesQuery(selfProvide(package.source.*), query)) {
            provides = true;
        }
        if (!provides and is_file_dep) {
            for (package.fileEntries(universe)) |file| {
                if (std.mem.eql(u8, file.path, relation.name)) {
                    provides = true;
                    break;
                }
            }
        }
        if (!provides) continue;
        any_provider = true;
        if (packageHidden(hidden, package.id)) {
            if (first_hidden == null) first_hidden = package.id;
        } else {
            visible_provider = true;
        }
    }
    if (!any_provider) return .{ .req = .nothing_provides };
    if (!visible_provider and first_hidden != null) {
        return .{ .req = .disabled, .disabled_provider = first_hidden };
    }
    return .{ .req = .requires_no_install };
}

/// The `name = EVR` capability every package implicitly provides, matching the
/// self-provide libsolv synthesises for each solvable.
fn selfProvide(package: metadata.Package) metadata.Relation {
    return .{
        .name = package.nevra.name,
        .comparison = .eq,
        .epoch = package.nevra.epoch,
        .version = package.nevra.version,
        .release = if (package.nevra.release.len == 0) null else package.nevra.release,
    };
}

fn packageHidden(
    hidden: []const solver_model.PackageId,
    package_id: ?solver_model.PackageId,
) bool {
    const id = package_id orelse return false;
    for (hidden) |candidate| {
        if (candidate == id) return true;
    }
    return false;
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
