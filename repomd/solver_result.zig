//! Canonical result materialization for completed native solver models.

const std = @import("std");
const query_index = @import("index.zig");
const metadata = @import("model.zig");
const solver_model = @import("solver_model.zig");
const solver_policy = @import("solver_policy.zig");
const solver_rules = @import("solver_rules.zig");
const solver_search = @import("solver_search.zig");

const ActionList = std.array_list.Managed(solver_model.Action);
const PackageIdList = std.array_list.Managed(solver_model.PackageId);

pub const Input = struct {
    prepared: *const solver_policy.Prepared,
    model: solver_search.Model,
    accepted_weak: []const solver_policy.AcceptedWeak = &.{},
    eviction_packages: []const solver_model.PackageId = &.{},
    skipped_jobs: []const solver_model.JobId = &.{},
    problems: []const solver_model.Problem = &.{},
};

pub const OwnedResult = struct {
    arena_state: std.heap.ArenaAllocator,
    selected: []const solver_model.PackageId,
    outcome: solver_model.Outcome,

    pub fn deinit(self: *OwnedResult) void {
        self.arena_state.deinit();
        self.* = undefined;
    }
};

pub const OwnedProblems = struct {
    arena_state: std.heap.ArenaAllocator,
    problems: []const solver_model.Problem,

    pub fn deinit(self: *OwnedProblems) void {
        self.arena_state.deinit();
        self.* = undefined;
    }
};

pub const MaterializeError = error{
    OutOfMemory,
    InvalidInput,
};

pub const DeriveProblemsError = solver_search.SolveError || error{
    Satisfiable,
    InvalidInput,
    UnsupportedProblem,
    TooManyUnsatCores,
    UnblockableCore,
    AmbiguousProblemRule,
};

/// Independent UNSAT cores enumerated before a request is declared hopeless.
///
/// libsolv enumerates cores by disabling the job rules of each core and
/// re-solving, so the count is bounded by the number of job rules in practice
/// but not in theory. This mirrors `solver_model.max_skip_broken_jobs`: any
/// request needing more than this many distinct explanations is reported as a
/// hard error rather than truncated, because a truncated problem list is
/// indistinguishable from a complete one at the call site.
pub const max_unsat_cores: usize = 64;

/// Convert a complete satisfiable model into canonical package actions.
///
/// This does not derive transaction execution order. Verified RPM inputs
/// continue through transaction_native.zig after result materialization.
pub fn materialize(
    allocator: std.mem.Allocator,
    input: Input,
) MaterializeError!OwnedResult {
    const formula = &input.prepared.formula;
    const universe = formula.universe;
    const package_count = universe.packages.len;
    if (input.model.values.len != package_count or
        formula.package_states.len != package_count)
    {
        return error.InvalidInput;
    }
    try validatePackageIds(
        universe,
        input.prepared.cleanup_packages,
        true,
    );
    try validatePackageIds(universe, input.eviction_packages, true);
    for (input.accepted_weak) |accepted| {
        if (universe.package(accepted.package) == null) {
            return error.InvalidInput;
        }
    }
    for (input.skipped_jobs) |job_id| {
        if (@intFromEnum(job_id) >= formula.jobs.len) {
            return error.InvalidInput;
        }
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();

    var selected = PackageIdList.init(arena);
    var removed = try arena.alloc(bool, package_count);
    @memset(removed, false);
    for (universe.packages) |package| {
        const package_index: usize = @intFromEnum(package.id);
        if (input.model.values[package_index]) {
            try selected.append(package.id);
        } else if (package.installed != null) {
            removed[package_index] = true;
        }
    }

    var referenced_priors = try arena.alloc(bool, package_count);
    @memset(referenced_priors, false);
    var actions = ActionList.init(arena);
    for (universe.packages) |package| {
        const package_index: usize = @intFromEnum(package.id);
        if (package.installed != null or
            !input.model.values[package_index])
        {
            continue;
        }

        var priors = PackageIdList.init(arena);
        var has_same_name_prior = false;
        var has_exact_multiversion_prior = false;
        const multiversion =
            formula.package_states[package_index].multiversion;
        if (!multiversion) {
            for (universe.packages) |installed| {
                const installed_index: usize =
                    @intFromEnum(installed.id);
                if (!removed[installed_index]) continue;
                if (packageObsoletes(
                    universe,
                    package,
                    installed,
                )) {
                    referenced_priors[installed_index] = true;
                    try priors.append(installed.id);
                }
            }
        }
        if (multiversion) {
            for (universe.packages) |installed| {
                const installed_index: usize = @intFromEnum(installed.id);
                if (!removed[installed_index] or
                    !sameMultiversionIdentity(package, installed))
                {
                    continue;
                }
                referenced_priors[installed_index] = true;
                has_exact_multiversion_prior = true;
                has_same_name_prior = true;
                if (!containsPackage(priors.items, installed.id)) {
                    try priors.append(installed.id);
                }
            }
            if (!has_exact_multiversion_prior) priors.clearRetainingCapacity();
        } else {
            for (universe.packages) |installed| {
                const installed_index: usize = @intFromEnum(installed.id);
                if (!removed[installed_index] or
                    solver_rules.isSource(
                        package.source.nevra.arch,
                    ) or
                    solver_rules.isSource(
                        installed.source.nevra.arch,
                    ) or
                    !std.mem.eql(
                        u8,
                        package.source.nevra.name,
                        installed.source.nevra.name,
                    ))
                {
                    continue;
                }
                referenced_priors[installed_index] = true;
                has_same_name_prior = true;
                if (!containsPackage(priors.items, installed.id)) {
                    try priors.append(installed.id);
                }
            }
            if (!has_same_name_prior) {
                for (priors.items) |prior_id| {
                    const prior = universe.package(prior_id) orelse
                        return error.InvalidInput;
                    if (std.mem.eql(
                        u8,
                        package.source.nevra.name,
                        prior.source.nevra.name,
                    )) {
                        has_same_name_prior = true;
                        break;
                    }
                }
            }
        }
        std.sort.pdq(
            solver_model.PackageId,
            priors.items,
            {},
            packageIdLessThan,
        );

        const kind = if (priors.items.len == 0)
            solver_model.ActionKind.install
        else if (!has_same_name_prior)
            solver_model.ActionKind.obsolete
        else
            try replacementKind(universe, package, priors.items);
        const decision = decisionReason(input, package.id);
        const policy_replacement = decisionPolicyReason(
            formula,
            decision,
        );
        try actions.append(.{
            .package = package.id,
            .priors = try priors.toOwnedSlice(),
            .kind = kind,
            .reason = if (kind == .obsolete)
                .obsoletes
            else if (policy_replacement)
                .policy
            else
                decision.reason,
            .requested_by = if (policy_replacement)
                null
            else
                decision.requested_by,
        });
    }

    for (universe.packages) |package| {
        const package_index: usize = @intFromEnum(package.id);
        if (!removed[package_index] or referenced_priors[package_index]) {
            continue;
        }
        const decision = decisionReason(input, package.id);
        try actions.append(.{
            .package = package.id,
            .kind = .erase,
            .reason = if (containsPackage(
                input.eviction_packages,
                package.id,
            ))
                .installonly_limit
            else if (containsPackage(
                input.prepared.cleanup_packages,
                package.id,
            ))
                .cleanup
            else
                decision.reason,
            .requested_by = if (containsPackage(
                input.eviction_packages,
                package.id,
            ) or containsPackage(
                input.prepared.cleanup_packages,
                package.id,
            ))
                null
            else
                decision.requested_by,
        });
    }
    std.sort.pdq(
        solver_model.Action,
        actions.items,
        {},
        actionLessThan,
    );

    const owned_selected = try selected.toOwnedSlice();
    const owned_actions = try actions.toOwnedSlice();
    const owned_skipped = try arena.dupe(
        solver_model.JobId,
        input.skipped_jobs,
    );
    const owned_problems = try arena.dupe(
        solver_model.Problem,
        input.problems,
    );
    for (owned_problems) |*problem| {
        if (problem.capability) |relation| {
            problem.capability = try cloneRelation(arena, relation);
        }
    }
    return .{
        .arena_state = arena_state,
        .selected = owned_selected,
        .outcome = .{
            .actions = owned_actions,
            .problems = owned_problems,
            .skipped_jobs = owned_skipped,
        },
    };
}

/// Derive every canonical structured problem of an unsatisfiable formula.
///
/// One problem is derived per independent UNSAT core, the way libsolv's
/// `analyze_unsolvable` does it: refute, name the core, disable the core's
/// non-package rules, and refute again until the remainder is satisfiable.
/// The result is sorted and deduplicated into the same canonical multiset
/// libsolv's problem list collapses to. This is not yet a runtime path.
pub fn deriveUnsatProblems(
    allocator: std.mem.Allocator,
    formula: *const solver_rules.OwnedFormula,
) DeriveProblemsError!OwnedProblems {
    return deriveEnumeratedProblems(allocator, formula, false);
}

/// Derive every canonical problem and attribute package-origin failures to
/// the single job in their own UNSAT core when one exists.
pub fn deriveUnsatProblemsWithCoreJobs(
    allocator: std.mem.Allocator,
    formula: *const solver_rules.OwnedFormula,
) DeriveProblemsError!OwnedProblems {
    return deriveEnumeratedProblems(allocator, formula, true);
}

fn deriveEnumeratedProblems(
    allocator: std.mem.Allocator,
    formula: *const solver_rules.OwnedFormula,
    attribute_core_jobs: bool,
) DeriveProblemsError!OwnedProblems {
    var cores = CoreProblemList.init(allocator);
    defer cores.deinit();
    try enumerateCoreProblems(allocator, formula, &cores);
    if (cores.items.len == 0) return error.Satisfiable;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();

    const problems = try arena.alloc(solver_model.Problem, cores.items.len);
    for (cores.items, problems) |core, *problem| {
        problem.* = core.problem;
        if (attribute_core_jobs and problem.job == null) {
            problem.job = core.core_job;
        }
        if (problem.capability) |relation| {
            problem.capability = try cloneRelation(arena, relation);
        }
    }

    return .{
        .arena_state = arena_state,
        .problems = canonicalizeProblems(problems),
    };
}

/// Collapse a derived problem list the way the libsolv oracle collapses its
/// own: sort canonically, then merge identical problems into one `count`.
fn canonicalizeProblems(
    problems: []solver_model.Problem,
) []const solver_model.Problem {
    std.sort.pdq(solver_model.Problem, problems, {}, problemLessThan);
    var write_index: usize = 0;
    for (problems) |problem| {
        if (write_index != 0 and
            sameProblem(problems[write_index - 1], problem))
        {
            problems[write_index - 1].count += problem.count;
            continue;
        }
        problems[write_index] = problem;
        write_index += 1;
    }
    return problems[0..write_index];
}

/// Explain every job a skip-broken solve dropped.
///
/// Each job is diagnosed against its own isolated formula, because the full
/// formula holds one core per broken job and a core can only be named when it
/// stands alone. Diagnosis is best effort: a job whose core does not reduce to
/// a single canonical problem is simply left unexplained rather than failing
/// the solve, which is the same latitude libsolv takes.
pub fn deriveSkippedJobProblems(
    allocator: std.mem.Allocator,
    prepared: *const solver_policy.Prepared,
    skipped_jobs: []const solver_model.JobId,
) error{OutOfMemory}!OwnedProblems {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();

    var problems = std.array_list.Managed(solver_model.Problem).init(arena);
    for (skipped_jobs) |job| {
        var isolated = solver_policy.isolateJob(
            prepared,
            allocator,
            job,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        defer isolated.deinit();

        var problem = deriveCoreProblem(
            allocator,
            &isolated.formula,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        problem.job = job;
        if (problem.capability) |relation| {
            problem.capability = try cloneRelation(arena, relation);
        }
        try problems.append(problem);
    }

    return .{
        .arena_state = arena_state,
        .problems = try problems.toOwnedSlice(),
    };
}

/// Reduce one independent unsatisfiable core to one canonical problem.
///
/// Errors when the formula holds more than one core, because the callers of
/// this helper diagnose one isolated request at a time and have no place to
/// put a second explanation.
///
/// The returned problem borrows its capability strings from `formula`.
fn deriveCoreProblem(
    allocator: std.mem.Allocator,
    formula: *const solver_rules.OwnedFormula,
) DeriveProblemsError!solver_model.Problem {
    var cores = CoreProblemList.init(allocator);
    defer cores.deinit();
    try enumerateCoreProblems(allocator, formula, &cores);
    if (cores.items.len == 0) return error.Satisfiable;
    if (cores.items.len != 1) return error.UnsupportedProblem;
    return cores.items[0].problem;
}

const CoreProblem = struct {
    problem: solver_model.Problem,
    core_job: ?solver_model.JobId,
};

const CoreProblemList = std.array_list.Managed(CoreProblem);

/// Enumerate every independent UNSAT core of `formula` as one problem each.
///
/// This is libsolv's `analyze_unsolvable` loop (`src/solver.c:955`) expressed
/// over the native formula. libsolv records only the *non-package* rules of a
/// proof as the problem's rule set, disables exactly those with
/// `solver_disableproblemset`, and re-solves; package rules are never
/// disabled. `.job` and `.installed_keep` are the native origins that
/// correspond to libsolv's non-package rules (job rules and update rules), so
/// they are the ones this loop blocks.
///
/// Leaves `out` empty when the formula is satisfiable.
fn enumerateCoreProblems(
    allocator: std.mem.Allocator,
    formula: *const solver_rules.OwnedFormula,
    out: *CoreProblemList,
) DeriveProblemsError!void {
    const clause_count = formula.clauses.len;
    const active = try allocator.alloc(bool, clause_count);
    defer allocator.free(active);
    @memset(active, true);
    try disableReplacedRetentionRules(formula, active);

    const included = try allocator.alloc(bool, clause_count);
    defer allocator.free(included);

    while (true) {
        const core = try refuteIncludedClauses(
            allocator,
            formula,
            active,
        ) orelse return;
        defer allocator.free(core);

        // The refutation is a proof core, not a minimal one, so it is still
        // shrunk one clause at a time below. The point of extracting it first
        // is that the shrink then costs one solve per *proof* clause instead
        // of one per formula clause, and a proof core does not grow with the
        // repository.
        @memset(included, false);
        for (core) |clause_index| {
            if (clause_index >= clause_count) return error.InvalidInput;
            if (!active[clause_index]) return error.InvalidInput;
            included[clause_index] = true;
        }
        for (core) |clause_index| {
            included[clause_index] = false;
            var probe = try solveIncludedClauses(
                allocator,
                formula,
                included,
            );
            const remains_unsatisfiable = probe == .unsatisfiable;
            probe.deinit();
            if (!remains_unsatisfiable) included[clause_index] = true;
        }

        try out.append(try classifyCore(allocator, formula, included));
        if (out.items.len > max_unsat_cores) {
            return error.TooManyUnsatCores;
        }

        // Block this core the way libsolv does: disable its non-package
        // rules, keep every package rule, and refute what is left
        // (`analyze_unsolvable`, `src/solver.c:955`).
        var blocked: usize = 0;
        for (formula.clauses, included, 0..) |clause, keep, clause_index| {
            if (!keep) continue;
            switch (clause.origin) {
                .job, .installed_keep => {
                    active[clause_index] = false;
                    blocked += 1;
                },
                else => {},
            }
        }
        if (blocked == 0) return error.UnblockableCore;
    }
}

/// libsolv disables the update rule of an installed package that an install
/// job replaces: `jobtodisablelist` (`src/rules.c:2593`) pushes a
/// `DISABLE_UPDATE` for every installed package obsoleted by a job solvable,
/// and `solver_disablepolicyrules` applies it before the first solve.
///
/// Native rules instead keep a retention clause `p or <replacements>` for
/// every installed package. Both models agree while the job clause is
/// present, but a refutation sub-formula that drops the job clause still has
/// the retention clause forcing a replacement, which invents cores libsolv
/// never reports. Deactivating those clauses up front restores parity. This
/// only affects problem derivation - the solve path keeps the clause.
fn disableReplacedRetentionRules(
    formula: *const solver_rules.OwnedFormula,
    active: []bool,
) DeriveProblemsError!void {
    for (formula.clauses, 0..) |clause, clause_index| {
        const retained = switch (clause.origin) {
            .installed_keep => |package_id| package_id,
            else => continue,
        };
        const literals = try checkedClauseLiterals(formula, clause);
        for (literals) |literal| {
            if (!literal.positive()) continue;
            const replacement = literal.package();
            if (replacement == retained) continue;
            if (!installJobAsserts(formula, replacement)) continue;
            active[clause_index] = false;
            break;
        }
    }
}

/// True when some install job unconditionally requests `package_id`. Native
/// install jobs are unit positive clauses, which is the shape libsolv's
/// `SOLVER_INSTALL` job rule takes for a resolved single solvable.
fn installJobAsserts(
    formula: *const solver_rules.OwnedFormula,
    package_id: solver_model.PackageId,
) bool {
    for (formula.clauses) |clause| {
        if (clause.origin != .job) continue;
        const literals = formula.clauseLiterals(clause);
        if (literals.len != 1) continue;
        if (!literals[0].positive()) continue;
        if (literals[0].package() == package_id) return true;
    }
    return false;
}

/// Name one minimal core with libsolv's representative-rule priority.
///
/// `solver_findproblemrule` (`src/problems.c:1284`) prefers, in order: a
/// requires-class package rule, then a conflicts-class package rule, then an
/// update rule, then a job rule. The native origins map onto those classes
/// exactly, so the same order is applied here.
///
/// Within the requires class libsolv applies `findproblemrule_internal`'s
/// `reqset` ranking (`src/problems.c:1146`): an assertion rule outranks a rule
/// on the package a job asserted, which outranks a rule on an installed
/// package, which outranks anything else. Within the conflicts class it
/// prefers a conflict that touches an installed package. libsolv breaks
/// remaining ties on its own proof order, which the native core does not
/// preserve; ascending clause index is used instead, which is package-id
/// order because rules are generated per package.
fn classifyCore(
    allocator: std.mem.Allocator,
    formula: *const solver_rules.OwnedFormula,
    included: []const bool,
) DeriveProblemsError!CoreProblem {
    const core_jobs = try allocator.alloc(bool, formula.jobs.len);
    defer allocator.free(core_jobs);
    @memset(core_jobs, false);

    var job_assert: ?solver_model.PackageId = null;
    for (formula.clauses, included) |clause, keep| {
        if (!keep) continue;
        const job_id = switch (clause.origin) {
            .job => |value| value,
            else => continue,
        };
        const job_index: usize = @intFromEnum(job_id);
        if (job_index >= core_jobs.len) return error.InvalidInput;
        core_jobs[job_index] = true;
        if (job_assert != null) continue;
        const literals = try checkedClauseLiterals(formula, clause);
        if (literals.len == 1 and literals[0].positive()) {
            job_assert = literals[0].package();
        }
    }

    var requires_best: ?Representative = null;
    var conflicts_best: ?Representative = null;
    var keep_count: usize = 0;
    for (formula.clauses, included, 0..) |clause, keep, clause_index| {
        if (!keep) continue;
        const literals = try checkedClauseLiterals(formula, clause);
        switch (clause.origin) {
            .job => {},
            .installed_keep => keep_count += 1,
            .not_installable, .requirement => takeBetter(
                &requires_best,
                .{
                    .origin = clause.origin,
                    .clause_index = clause_index,
                    .tier = requiresTier(
                        formula,
                        clause.origin,
                        literals,
                        job_assert,
                    ),
                },
            ),
            .conflict, .same_name, .obsoletes => takeBetter(
                &conflicts_best,
                .{
                    .origin = clause.origin,
                    .clause_index = clause_index,
                    .tier = conflictsTier(formula, clause.origin),
                },
            ),
        }
    }

    var core_job_count: usize = 0;
    var only_core_job: ?solver_model.JobId = null;
    for (core_jobs, 0..) |in_core, job_index| {
        if (!in_core) continue;
        core_job_count += 1;
        only_core_job = @enumFromInt(@as(u32, @intCast(job_index)));
    }
    const single_core_job = if (core_job_count == 1)
        only_core_job
    else
        null;

    if (requires_best) |requires_rule| {
        const origin = try preferInstalledConflict(
            formula,
            included,
            requires_rule,
        );
        return .{
            .problem = try problemForOrigin(formula, origin),
            .core_job = single_core_job,
        };
    }
    if (conflicts_best) |conflicts_rule| {
        return .{
            .problem = try problemForOrigin(formula, conflicts_rule.origin),
            .core_job = single_core_job,
        };
    }
    // A core held together only by retention rules would be named by
    // libsolv's update rule, which has no native problem representation yet.
    if (keep_count != 0) return error.UnsupportedProblem;
    const job_id = single_core_job orelse return error.AmbiguousProblemRule;
    return .{
        .problem = try noCandidateProblem(formula, job_id),
        .core_job = job_id,
    };
}

const Representative = struct {
    origin: solver_rules.RuleOrigin,
    clause_index: usize,
    tier: u8,
};

fn takeBetter(best: *?Representative, candidate: Representative) void {
    const current = best.* orelse {
        best.* = candidate;
        return;
    };
    if (candidate.tier > current.tier) best.* = candidate;
}

fn requiresTier(
    formula: *const solver_rules.OwnedFormula,
    origin: solver_rules.RuleOrigin,
    literals: []const solver_rules.Literal,
    job_assert: ?solver_model.PackageId,
) u8 {
    if (literals.len == 1) return 3;
    const subject = switch (origin) {
        .requirement => |dependency| dependency.package,
        .not_installable => |package_id| package_id,
        else => return 0,
    };
    if (job_assert) |asserted| {
        if (asserted == subject) return 2;
    }
    if (isInstalled(formula, subject)) return 1;
    return 0;
}

fn conflictsTier(
    formula: *const solver_rules.OwnedFormula,
    origin: solver_rules.RuleOrigin,
) u8 {
    const sides: [2]?solver_model.PackageId = switch (origin) {
        .conflict => |conflict| .{ conflict.dependency.package, conflict.target },
        .obsoletes => |obsoletes| .{ obsoletes.dependency.package, obsoletes.target },
        .same_name => |same_name| .{ same_name.left, same_name.right },
        else => return 0,
    };
    for (sides) |side| {
        const package_id = side orelse continue;
        if (isInstalled(formula, package_id)) return 1;
    }
    return 0;
}

/// libsolv's `solver_findproblemrule` tail (`src/problems.c:1293`): a request
/// for an uninstalled package that requires an installed package conflicting
/// with it is reported as the conflict, not as the requirement.
/// Transcribes the tail special case of libsolv's `solver_findproblemrule`
/// (`problems.c:1284`): when an uninstalled package requires something that
/// only an installed package provides, and the same package is blocked
/// against that installed package by a conflicts-class rule, libsolv names
/// the conflicts-class rule instead of the requires rule.
///
/// libsolv applies the test to the single conflicts-class representative it
/// picked from its proof order. The native core is sorted by clause index and
/// cannot reproduce that order, so every conflicts-class clause in the core is
/// tested and the best match wins. Measured against libsolv this is a strictly
/// closer match than testing only the tier-best conflict.
fn preferInstalledConflict(
    formula: *const solver_rules.OwnedFormula,
    included: []const bool,
    requires_rule: Representative,
) DeriveProblemsError!solver_rules.RuleOrigin {
    const requires_subject = switch (requires_rule.origin) {
        .requirement => |dependency| dependency.package,
        else => return requires_rule.origin,
    };
    if (isInstalled(formula, requires_subject)) return requires_rule.origin;

    const requires_clause = formula.clauses[requires_rule.clause_index];
    const requires_literals = try checkedClauseLiterals(
        formula,
        requires_clause,
    );

    var best: ?Representative = null;
    for (formula.clauses, included, 0..) |clause, keep, clause_index| {
        if (!keep) continue;
        const sides = conflictSides(clause.origin) orelse continue;
        const installed_side = if (requires_subject == sides.left and
            isInstalled(formula, sides.right))
            sides.right
        else if (requires_subject == sides.right and
            isInstalled(formula, sides.left))
            sides.left
        else
            continue;
        if (samePackageName(formula, sides.left, sides.right)) continue;
        if (!requiresPackage(requires_literals, installed_side)) continue;
        takeBetter(&best, .{
            .origin = clause.origin,
            .clause_index = clause_index,
            .tier = conflictsTier(formula, clause.origin),
        });
    }
    if (best) |conflicts_rule| return conflicts_rule.origin;
    return requires_rule.origin;
}

const ConflictSides = struct {
    left: solver_model.PackageId,
    right: solver_model.PackageId,
};

/// libsolv models conflicts, obsoletes and same-name rules alike as a binary
/// all-negative rule over two packages, which is what its special case reads
/// through `rule->p` and `rule->w2`.
fn conflictSides(origin: solver_rules.RuleOrigin) ?ConflictSides {
    return switch (origin) {
        .conflict => |value| .{
            .left = value.dependency.package,
            .right = value.target orelse return null,
        },
        .obsoletes => |value| .{
            .left = value.dependency.package,
            .right = value.target,
        },
        .same_name => |value| .{ .left = value.left, .right = value.right },
        else => null,
    };
}

fn requiresPackage(
    literals: []const solver_rules.Literal,
    package_id: solver_model.PackageId,
) bool {
    for (literals) |literal| {
        if (literal.positive() and literal.package() == package_id) return true;
    }
    return false;
}

fn isInstalled(
    formula: *const solver_rules.OwnedFormula,
    package_id: solver_model.PackageId,
) bool {
    const package = formula.universe.package(package_id) orelse return false;
    return package.installed != null;
}

fn samePackageName(
    formula: *const solver_rules.OwnedFormula,
    left_id: solver_model.PackageId,
    right_id: solver_model.PackageId,
) bool {
    const left = formula.universe.package(left_id) orelse return false;
    const right = formula.universe.package(right_id) orelse return false;
    return std.mem.eql(
        u8,
        left.source.nevra.name,
        right.source.nevra.name,
    );
}

const FilteredFormula = struct {
    allocator: std.mem.Allocator,
    formula: solver_rules.OwnedFormula,
    clauses: []solver_rules.Clause,
    literals: []solver_rules.Literal,
    source_index: []usize,

    fn deinit(self: *FilteredFormula) void {
        self.allocator.free(self.clauses);
        self.allocator.free(self.literals);
        self.allocator.free(self.source_index);
        self.* = undefined;
    }
};

fn buildFilteredFormula(
    allocator: std.mem.Allocator,
    source: *const solver_rules.OwnedFormula,
    included: []const bool,
) DeriveProblemsError!FilteredFormula {
    if (included.len != source.clauses.len) {
        return error.InvalidInput;
    }
    var clauses =
        std.array_list.Managed(solver_rules.Clause).init(allocator);
    errdefer clauses.deinit();
    var literals =
        std.array_list.Managed(solver_rules.Literal).init(allocator);
    errdefer literals.deinit();
    var source_index = std.array_list.Managed(usize).init(allocator);
    errdefer source_index.deinit();

    for (source.clauses, included, 0..) |clause, keep, clause_index| {
        if (!keep) continue;
        const source_literals = try checkedClauseLiterals(
            source,
            clause,
        );
        if (literals.items.len > std.math.maxInt(u32) or
            source_literals.len >
                std.math.maxInt(u32) - literals.items.len)
        {
            return error.InvalidInput;
        }
        const start = literals.items.len;
        try literals.appendSlice(source_literals);
        var copied = clause;
        copied.literals = .{
            .start = @intCast(start),
            .len = @intCast(source_literals.len),
        };
        try clauses.append(copied);
        try source_index.append(clause_index);
    }

    const owned_clauses = try clauses.toOwnedSlice();
    errdefer allocator.free(owned_clauses);
    const owned_literals = try literals.toOwnedSlice();
    errdefer allocator.free(owned_literals);
    const owned_source_index = try source_index.toOwnedSlice();

    return .{
        .allocator = allocator,
        .formula = .{
            .allocator = allocator,
            .universe = source.universe,
            .jobs = source.jobs,
            .architecture = source.architecture,
            .replacement_kind = source.replacement_kind,
            .clauses = owned_clauses,
            .literals = owned_literals,
            .weak_requests = source.weak_requests,
            .weak_candidates = source.weak_candidates,
            .package_states = source.package_states,
        },
        .clauses = owned_clauses,
        .literals = owned_literals,
        .source_index = owned_source_index,
    };
}

fn solveIncludedClauses(
    allocator: std.mem.Allocator,
    source: *const solver_rules.OwnedFormula,
    included: []const bool,
) DeriveProblemsError!solver_search.Result {
    var filtered = try buildFilteredFormula(allocator, source, included);
    defer filtered.deinit();
    return solver_search.solve(allocator, &filtered.formula);
}

/// Refute only the still-active clauses, reporting the core in source indices.
///
/// Returns `null` when the active clauses are satisfiable.
fn refuteIncludedClauses(
    allocator: std.mem.Allocator,
    source: *const solver_rules.OwnedFormula,
    included: []const bool,
) DeriveProblemsError!?[]usize {
    var filtered = try buildFilteredFormula(allocator, source, included);
    defer filtered.deinit();
    var refutation = (try solver_search.refute(
        allocator,
        &filtered.formula,
        &.{},
    )) orelse return null;
    defer refutation.deinit();

    const mapped = try allocator.alloc(usize, refutation.clauses.len);
    errdefer allocator.free(mapped);
    for (refutation.clauses, mapped) |filtered_index, *target| {
        if (filtered_index >= filtered.source_index.len) {
            return error.InvalidInput;
        }
        target.* = filtered.source_index[filtered_index];
    }
    std.sort.pdq(usize, mapped, {}, std.sort.asc(usize));
    return mapped;
}

fn checkedClauseLiterals(
    formula: *const solver_rules.OwnedFormula,
    clause: solver_rules.Clause,
) DeriveProblemsError![]const solver_rules.Literal {
    const start: usize = @intCast(clause.literals.start);
    const len: usize = @intCast(clause.literals.len);
    if (start > formula.literals.len or
        len > formula.literals.len - start)
    {
        return error.InvalidInput;
    }
    return formula.literals[start .. start + len];
}

fn problemForOrigin(
    formula: *const solver_rules.OwnedFormula,
    origin: solver_rules.RuleOrigin,
) DeriveProblemsError!solver_model.Problem {
    return switch (origin) {
        .not_installable => |package_id| .{
            .kind = .not_installable,
            .package = try validPackageId(formula, package_id),
            .count = 1,
        },
        .requirement => |dependency| .{
            .kind = .unsatisfied_requirement,
            .package = try validPackageId(
                formula,
                dependency.package,
            ),
            .capability = try dependencyRelation(
                formula,
                dependency,
                .requires,
            ),
            .count = 1,
        },
        .conflict => |conflict| .{
            .kind = .conflict,
            .package = try validPackageId(
                formula,
                conflict.dependency.package,
            ),
            .related_package = if (conflict.target) |target|
                try validPackageId(formula, target)
            else
                null,
            .capability = try dependencyRelation(
                formula,
                conflict.dependency,
                .conflicts,
            ),
            .count = 1,
        },
        .obsoletes => |obsoletes| .{
            .kind = .obsoletes,
            .package = try validPackageId(
                formula,
                obsoletes.dependency.package,
            ),
            .related_package = try validPackageId(
                formula,
                obsoletes.target,
            ),
            .capability = try dependencyRelation(
                formula,
                obsoletes.dependency,
                .obsoletes,
            ),
            .count = 1,
        },
        .same_name => |same_name| .{
            .kind = .conflict,
            .package = try validPackageId(formula, same_name.right),
            .related_package = try validPackageId(
                formula,
                same_name.left,
            ),
            .count = 1,
        },
        .job, .installed_keep => return error.UnsupportedProblem,
    };
}

fn noCandidateProblem(
    formula: *const solver_rules.OwnedFormula,
    job_id: solver_model.JobId,
) DeriveProblemsError!solver_model.Problem {
    const job_index: usize = @intFromEnum(job_id);
    if (job_index >= formula.jobs.len) return error.InvalidInput;
    return .{
        .kind = .no_candidate,
        .capability = switch (formula.jobs[job_index].selection) {
            .name => |name| metadata.Relation{ .name = name },
            .capability => |capability| capability,
            else => null,
        },
        .job = job_id,
        .count = 1,
    };
}

fn validPackageId(
    formula: *const solver_rules.OwnedFormula,
    package_id: solver_model.PackageId,
) DeriveProblemsError!solver_model.PackageId {
    if (formula.universe.package(package_id) == null) {
        return error.InvalidInput;
    }
    return package_id;
}

fn dependencyRelation(
    formula: *const solver_rules.OwnedFormula,
    dependency: solver_rules.DependencyRef,
    expected_kind: metadata.DependencyKind,
) DeriveProblemsError!metadata.Relation {
    if (dependency.kind != expected_kind) return error.InvalidInput;
    const package = formula.universe.package(dependency.package) orelse
        return error.InvalidInput;
    const relations = package.relationEntries(
        formula.universe,
        dependency.kind,
    );
    const relation_index: usize = @intCast(dependency.index);
    if (relation_index >= relations.len) return error.InvalidInput;
    return relations[relation_index];
}

fn cloneRelation(
    allocator: std.mem.Allocator,
    relation: metadata.Relation,
) error{OutOfMemory}!metadata.Relation {
    var cloned = relation;
    cloned.name = try allocator.dupe(u8, relation.name);
    cloned.flags = if (relation.flags) |value|
        try allocator.dupe(u8, value)
    else
        null;
    cloned.version = if (relation.version) |value|
        try allocator.dupe(u8, value)
    else
        null;
    cloned.release = if (relation.release) |value|
        try allocator.dupe(u8, value)
    else
        null;
    return cloned;
}

const DecisionReason = struct {
    reason: solver_model.TransactionReason,
    requested_by: ?solver_model.JobId = null,
};

fn decisionReason(
    input: Input,
    package_id: solver_model.PackageId,
) DecisionReason {
    if (containsAcceptedWeak(input.accepted_weak, package_id)) {
        return .{ .reason = .weak_dependency };
    }
    const prepared = input.prepared;
    var group_job: ?solver_model.JobId = null;
    var group_matches: usize = 0;
    for (prepared.decision_policy.groups) |group| {
        var chosen: ?solver_model.PackageId = null;
        for (group.candidates.slice(
            prepared.decision_policy.candidates,
        )) |candidate| {
            if (input.model.value(candidate) orelse false) {
                chosen = candidate;
                break;
            }
        }
        if (chosen != package_id or
            group.clause_index >= prepared.formula.clauses.len)
        {
            continue;
        }
        const job_id = switch (prepared.formula.clauses[
            group.clause_index
        ].origin) {
            .job => |value| value,
            else => continue,
        };
        if (group_job == null) group_job = job_id;
        if (group_job == job_id) group_matches += 1;
    }
    if (group_job) |job_id| {
        const job_index: usize = @intFromEnum(job_id);
        if (job_index < prepared.formula.jobs.len) {
            const job = prepared.formula.jobs[job_index];
            if (group_matches > 1 and job.action == .dist_sync) {
                return .{ .reason = .dependency };
            }
            return .{
                .reason = requestReason(job.reason),
                .requested_by = job_id,
            };
        }
    }
    for (prepared.formula.clauses, 0..) |clause, clause_index| {
        const job_id = switch (clause.origin) {
            .job => |value| value,
            else => continue,
        };
        if (isCandidateGroupClause(prepared, clause_index)) continue;
        if (!packageSatisfiesJobClause(
            prepared,
            input.model,
            package_id,
            clause,
        )) {
            continue;
        }
        const job_index: usize = @intFromEnum(job_id);
        if (job_index >= prepared.formula.jobs.len) continue;
        return .{
            .reason = requestReason(
                prepared.formula.jobs[job_index].reason,
            ),
            .requested_by = job_id,
        };
    }
    return .{ .reason = .dependency };
}

fn isCandidateGroupClause(
    prepared: *const solver_policy.Prepared,
    clause_index: usize,
) bool {
    for (prepared.decision_policy.groups) |group| {
        if (group.clause_index == clause_index) return true;
    }
    return false;
}

fn packageSatisfiesJobClause(
    prepared: *const solver_policy.Prepared,
    model: solver_search.Model,
    package_id: solver_model.PackageId,
    clause: solver_rules.Clause,
) bool {
    const value = model.value(package_id) orelse return false;
    for (prepared.formula.clauseLiterals(clause)) |literal| {
        if (literal.package() == package_id and
            literal.positive() == value)
        {
            return true;
        }
    }
    return false;
}

fn packageObsoletes(
    universe: *const solver_model.Universe,
    package: solver_model.UniversePackage,
    installed: solver_model.UniversePackage,
) bool {
    if (installed.installed == null) return false;
    for (package.relationEntries(universe, .obsoletes)) |relation| {
        if (solver_rules.packageMatchesNevr(
            installed.source.*,
            relation,
        )) {
            return true;
        }
    }
    return false;
}

fn sameMultiversionIdentity(
    package: solver_model.UniversePackage,
    installed: solver_model.UniversePackage,
) bool {
    return installed.installed != null and
        !solver_rules.isSource(package.source.nevra.arch) and
        !solver_rules.isSource(installed.source.nevra.arch) and
        std.mem.eql(
            u8,
            package.source.nevra.name,
            installed.source.nevra.name,
        ) and
        std.mem.eql(
            u8,
            package.source.nevra.arch,
            installed.source.nevra.arch,
        ) and
        comparePackageEvr(package, installed) == 0;
}

fn decisionPolicyReason(
    formula: *const solver_rules.OwnedFormula,
    decision: DecisionReason,
) bool {
    const job_id = decision.requested_by orelse return false;
    const job_index: usize = @intFromEnum(job_id);
    if (job_index >= formula.jobs.len) return false;
    return switch (formula.jobs[job_index].action) {
        .update, .dist_sync => true,
        else => false,
    };
}

fn replacementKind(
    universe: *const solver_model.Universe,
    package: solver_model.UniversePackage,
    priors: []const solver_model.PackageId,
) MaterializeError!solver_model.ActionKind {
    var reference: ?solver_model.UniversePackage = null;
    for (priors) |prior_id| {
        const prior = universe.package(prior_id) orelse
            return error.InvalidInput;
        if (!std.mem.eql(
            u8,
            package.source.nevra.name,
            prior.source.nevra.name,
        )) {
            continue;
        }
        if (reference) |current| {
            const evr_order = comparePackageEvr(prior.*, current);
            if (evr_order < 0) continue;
            if (evr_order == 0) {
                const prior_same_arch = std.mem.eql(
                    u8,
                    prior.source.nevra.arch,
                    package.source.nevra.arch,
                );
                const current_same_arch = std.mem.eql(
                    u8,
                    current.source.nevra.arch,
                    package.source.nevra.arch,
                );
                if (!prior_same_arch and current_same_arch) continue;
                if (prior_same_arch == current_same_arch and
                    @intFromEnum(prior.id) > @intFromEnum(current.id))
                {
                    continue;
                }
            }
        }
        reference = prior.*;
    }
    const prior = reference orelse return error.InvalidInput;
    return switch (std.math.sign(comparePackageEvr(package, prior))) {
        -1 => .downgrade,
        0 => .reinstall,
        1 => .upgrade,
        else => unreachable,
    };
}

fn comparePackageEvr(
    left: solver_model.UniversePackage,
    right: solver_model.UniversePackage,
) i32 {
    return query_index.compareEvr(
        left.source.nevra.epoch,
        left.source.nevra.version,
        left.source.nevra.release,
        right.source.nevra.epoch,
        right.source.nevra.version,
        right.source.nevra.release,
    );
}

fn requestReason(
    reason: solver_model.RequestReason,
) solver_model.TransactionReason {
    return switch (reason) {
        .user => .user,
        .dependency => .dependency,
        .weak_dependency => .weak_dependency,
        .cleanup => .cleanup,
        .installonly_limit => .installonly_limit,
        .policy => .policy,
    };
}

fn validatePackageIds(
    universe: *const solver_model.Universe,
    package_ids: []const solver_model.PackageId,
    require_installed: bool,
) MaterializeError!void {
    for (package_ids) |package_id| {
        const package = universe.package(package_id) orelse
            return error.InvalidInput;
        if (require_installed and package.installed == null) {
            return error.InvalidInput;
        }
    }
}

fn containsAcceptedWeak(
    accepted: []const solver_policy.AcceptedWeak,
    package_id: solver_model.PackageId,
) bool {
    for (accepted) |entry| {
        if (entry.package == package_id) return true;
    }
    return false;
}

fn containsPackage(
    packages: []const solver_model.PackageId,
    package_id: solver_model.PackageId,
) bool {
    for (packages) |candidate| {
        if (candidate == package_id) return true;
    }
    return false;
}

fn packageIdLessThan(
    _: void,
    left: solver_model.PackageId,
    right: solver_model.PackageId,
) bool {
    return @intFromEnum(left) < @intFromEnum(right);
}

fn actionLessThan(
    _: void,
    left: solver_model.Action,
    right: solver_model.Action,
) bool {
    return @intFromEnum(left.package) < @intFromEnum(right.package);
}

/// The canonical problem order the libsolv oracle collapses its list with.
fn problemLessThan(
    _: void,
    left: solver_model.Problem,
    right: solver_model.Problem,
) bool {
    if (@intFromEnum(left.kind) != @intFromEnum(right.kind)) {
        return @intFromEnum(left.kind) < @intFromEnum(right.kind);
    }
    const left_package = optionalIdValue(left.package);
    const right_package = optionalIdValue(right.package);
    if (left_package != right_package) return left_package < right_package;
    const left_related = optionalIdValue(left.related_package);
    const right_related = optionalIdValue(right.related_package);
    if (left_related != right_related) return left_related < right_related;
    const capability_order = optionalRelationOrder(
        left.capability,
        right.capability,
    );
    if (capability_order != .eq) return capability_order == .lt;
    const left_job = optionalJobValue(left.job);
    const right_job = optionalJobValue(right.job);
    return left_job < right_job;
}

fn sameProblem(
    left: solver_model.Problem,
    right: solver_model.Problem,
) bool {
    if (left.kind != right.kind or
        left.package != right.package or
        left.related_package != right.related_package or
        left.job != right.job)
    {
        return false;
    }
    return optionalRelationOrder(left.capability, right.capability) == .eq;
}

fn optionalIdValue(package_id: ?solver_model.PackageId) u32 {
    return if (package_id) |value|
        @intFromEnum(value)
    else
        std.math.maxInt(u32);
}

fn optionalJobValue(job_id: ?solver_model.JobId) u32 {
    return if (job_id) |value|
        @intFromEnum(value)
    else
        std.math.maxInt(u32);
}

fn optionalRelationOrder(
    left: ?metadata.Relation,
    right: ?metadata.Relation,
) std.math.Order {
    if (left == null or right == null) {
        if (left == null and right == null) return .eq;
        return if (left == null) .lt else .gt;
    }
    return relationOrder(left.?, right.?);
}

fn relationOrder(
    left: metadata.Relation,
    right: metadata.Relation,
) std.math.Order {
    var order = std.mem.order(u8, left.name, right.name);
    if (order != .eq) return order;
    order = std.math.order(
        @intFromEnum(left.comparison),
        @intFromEnum(right.comparison),
    );
    if (order != .eq) return order;
    order = optionalU32Order(left.epoch, right.epoch);
    if (order != .eq) return order;
    order = optionalStringOrder(left.version, right.version);
    if (order != .eq) return order;
    order = optionalStringOrder(left.release, right.release);
    if (order != .eq) return order;
    order = optionalStringOrder(left.flags, right.flags);
    if (order != .eq) return order;
    order = std.math.order(
        @intFromBool(left.pre),
        @intFromBool(right.pre),
    );
    if (order != .eq) return order;
    return std.math.order(left.sense, right.sense);
}

fn optionalU32Order(left: ?u32, right: ?u32) std.math.Order {
    if (left == null or right == null) {
        if (left == null and right == null) return .eq;
        return if (left == null) .lt else .gt;
    }
    return std.math.order(left.?, right.?);
}

fn optionalStringOrder(
    left: ?[]const u8,
    right: ?[]const u8,
) std.math.Order {
    if (left == null or right == null) {
        if (left == null and right == null) return .eq;
        return if (left == null) .lt else .gt;
    }
    return std.mem.order(u8, left.?, right.?);
}

test "materializer rejects a model with the wrong package count" {
    const repository_model = metadata.RepositoryModel{};
    var universe = try solver_model.Universe.init(
        std.testing.allocator,
        &.{.{
            .id = "available",
            .model = &repository_model,
        }},
    );
    defer universe.deinit();
    var base = try solver_rules.generateBase(
        std.testing.allocator,
        &universe,
        .{ .jobs = &.{} },
        .{ .native_arch = "x86_64" },
    );
    defer base.deinit();
    var prepared = try solver_policy.prepareInstalledRetention(
        std.testing.allocator,
        &base,
    );
    defer prepared.deinit();
    var values = [_]bool{true};

    try std.testing.expectError(
        error.InvalidInput,
        materialize(std.testing.allocator, .{
            .prepared = &prepared,
            .model = .{
                .allocator = std.testing.allocator,
                .values = &values,
            },
        }),
    );
}

fn materializerAllocationFailureCase(
    allocator: std.mem.Allocator,
) !void {
    var packages = [_]metadata.Package{.{
        .pkg_id = "application-1",
        .nevra = .{
            .name = "application",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        },
        .checksum = .{
            .kind = "sha256",
            .value = "application-1",
            .is_pkgid = true,
        },
        .location = .{ .href = "application-1" },
    }};
    const repository_model = metadata.RepositoryModel{
        .packages = &packages,
    };
    var universe = try solver_model.Universe.init(
        allocator,
        &.{.{
            .id = "available",
            .model = &repository_model,
        }},
    );
    defer universe.deinit();
    var base = try solver_rules.generateBase(
        allocator,
        &universe,
        .{ .jobs = &.{.{
            .action = .install,
            .selection = .{ .package = @enumFromInt(0) },
        }} },
        .{ .native_arch = "x86_64" },
    );
    defer base.deinit();
    var prepared = try solver_policy.prepareInstalledRetention(
        allocator,
        &base,
    );
    defer prepared.deinit();
    var solved = try prepared.solve(allocator);
    defer solved.deinit();
    var materialized = switch (solved) {
        .satisfiable => |model| try materialize(
            allocator,
            .{
                .prepared = &prepared,
                .model = model,
            },
        ),
        .unsatisfiable => return error.TestUnexpectedResult,
    };
    defer materialized.deinit();

    try std.testing.expectEqualSlices(
        solver_model.PackageId,
        &.{@enumFromInt(0)},
        materialized.selected,
    );
    try std.testing.expectEqual(@as(usize, 1), materialized.outcome.actions.len);
    const action = materialized.outcome.actions[0];
    try std.testing.expectEqual(
        solver_model.ActionKind.install,
        action.kind,
    );
    try std.testing.expectEqual(
        solver_model.TransactionReason.user,
        action.reason,
    );
    try std.testing.expectEqual(
        @as(?solver_model.JobId, @enumFromInt(0)),
        action.requested_by,
    );
}

test "materializer cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        materializerAllocationFailureCase,
        .{},
    );
}

fn problemDerivationAllocationFailureCase(
    allocator: std.mem.Allocator,
) !void {
    const repository_model = metadata.RepositoryModel{};
    var universe = try solver_model.Universe.init(
        allocator,
        &.{.{
            .id = "available",
            .model = &repository_model,
        }},
    );
    defer universe.deinit();
    var base = try solver_rules.generateBase(
        allocator,
        &universe,
        .{ .jobs = &.{.{
            .action = .install,
            .selection = .{ .name = "missing-package" },
        }} },
        .{ .native_arch = "x86_64" },
    );
    defer base.deinit();
    var prepared = try solver_policy.prepareInstalledRetention(
        allocator,
        &base,
    );
    defer prepared.deinit();
    var problems = try deriveUnsatProblems(
        allocator,
        &prepared.formula,
    );
    defer problems.deinit();

    try std.testing.expectEqual(@as(usize, 1), problems.problems.len);
    const problem = problems.problems[0];
    try std.testing.expectEqual(
        solver_model.ProblemKind.no_candidate,
        problem.kind,
    );
    try std.testing.expectEqual(
        @as(?solver_model.JobId, @enumFromInt(0)),
        problem.job,
    );
    try std.testing.expectEqualStrings(
        "missing-package",
        problem.capability.?.name,
    );
}

test "problem derivation attributes package failures to their core job" {
    const allocator = std.testing.allocator;
    var relations = [_]metadata.Relation{
        .{ .name = "missing-capability" },
    };
    var packages = [_]metadata.Package{
        .{
            .pkg_id = "broken",
            .nevra = .{
                .name = "broken",
                .version = "1",
                .release = "1",
                .arch = "x86_64",
            },
            .checksum = .{
                .kind = "sha256",
                .value = "broken",
                .is_pkgid = true,
            },
            .location = .{ .href = "broken.rpm" },
            .requires = .{ .start = 0, .len = 1 },
        },
    };
    const repository_model = metadata.RepositoryModel{
        .packages = &packages,
        .relations = &relations,
    };
    var universe = try solver_model.Universe.init(
        allocator,
        &.{.{ .id = "available", .model = &repository_model }},
    );
    defer universe.deinit();
    var base = try solver_rules.generateBase(
        allocator,
        &universe,
        .{ .jobs = &.{.{
            .action = .install,
            .selection = .{ .package = @enumFromInt(0) },
        }} },
        .{ .native_arch = "x86_64" },
    );
    defer base.deinit();
    var prepared = try solver_policy.prepareInstalledRetention(
        allocator,
        &base,
    );
    defer prepared.deinit();

    var problems = try deriveUnsatProblemsWithCoreJobs(
        allocator,
        &prepared.formula,
    );
    defer problems.deinit();

    try std.testing.expectEqual(@as(usize, 1), problems.problems.len);
    const problem = problems.problems[0];
    try std.testing.expectEqual(
        solver_model.ProblemKind.unsatisfied_requirement,
        problem.kind,
    );
    try std.testing.expectEqual(
        @as(?solver_model.PackageId, @enumFromInt(0)),
        problem.package,
    );
    try std.testing.expectEqual(
        @as(?solver_model.JobId, @enumFromInt(0)),
        problem.job,
    );
    try std.testing.expectEqualStrings(
        "missing-capability",
        problem.capability.?.name,
    );
}

test "problem derivation scales with the proof, not the repository" {
    // A repository large enough that one solve per formula clause -- what the
    // shrink loop used to do -- is not a viable error path. Only the two
    // clauses naming the missing package matter, so the proof core is tiny and
    // the number of probe solves is independent of `package_count`.
    const allocator = std.testing.allocator;
    const package_count = 2000;

    const names = try allocator.alloc([]const u8, package_count);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }
    for (names, 0..) |*name, index| {
        name.* = try std.fmt.allocPrint(allocator, "filler-{d}", .{index});
    }

    // Chain each filler onto the next so the generator emits a requirement
    // clause per package rather than an unconstrained variable.
    const relations = try allocator.alloc(metadata.Relation, package_count - 1);
    defer allocator.free(relations);
    for (relations, names[1..]) |*relation, name| {
        relation.* = .{ .name = name };
    }

    const packages = try allocator.alloc(metadata.Package, package_count);
    defer allocator.free(packages);
    for (packages, names, 0..) |*package, name, index| {
        package.* = .{
            .pkg_id = name,
            .nevra = .{
                .name = name,
                .version = "1",
                .release = "1",
                .arch = "x86_64",
            },
            .checksum = .{
                .kind = "sha256",
                .value = name,
                .is_pkgid = true,
            },
            .location = .{ .href = name },
            .provides = .{ .start = index, .len = 0 },
            .requires = if (index + 1 < package_count)
                .{ .start = index, .len = 1 }
            else
                .{},
        };
    }

    const repository_model = metadata.RepositoryModel{
        .packages = packages,
        .relations = relations,
    };
    var universe = try solver_model.Universe.init(
        allocator,
        &.{.{
            .id = "available",
            .model = &repository_model,
        }},
    );
    defer universe.deinit();
    var base = try solver_rules.generateBase(
        allocator,
        &universe,
        .{ .jobs = &.{.{
            .action = .install,
            .selection = .{ .name = "missing-package" },
        }} },
        .{ .native_arch = "x86_64" },
    );
    defer base.deinit();
    var prepared = try solver_policy.prepareInstalledRetention(
        allocator,
        &base,
    );
    defer prepared.deinit();
    try std.testing.expect(prepared.formula.clauses.len >= package_count);

    var problems = try deriveUnsatProblems(allocator, &prepared.formula);
    defer problems.deinit();

    try std.testing.expectEqual(@as(usize, 1), problems.problems.len);
    try std.testing.expectEqual(
        solver_model.ProblemKind.no_candidate,
        problems.problems[0].kind,
    );
    try std.testing.expectEqualStrings(
        "missing-package",
        problems.problems[0].capability.?.name,
    );
}

test "problem derivation cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        problemDerivationAllocationFailureCase,
        .{},
    );
}
