const std = @import("std");
const Allocator = std.mem.Allocator;

const abi = @import("transaction_plan_capture_abi");
const error_codes = @import("tdnf_error");
const repomd = @import("repomd");

pub const libsolv = repomd.solv_bridge.libsolv;
const c = libsolv;

extern fn pool_evrcmp(
    pool: *const c.Pool,
    evr1: c.Id,
    evr2: c.Id,
    mode: c_int,
) c_int;
const evrcmp_compare: c_int = 0;

pub const CaptureError = Allocator.Error || error{
    AmbiguousPackageMapping,
    InvalidInput,
    InvalidTrace,
    JobMismatch,
    SolverFailed,
    UnsupportedResult,
};

pub const Input = struct {
    pool: *c.Pool,
    solver: *c.Solver,
    transaction: ?*c.Transaction,
    jobs: *const c.Queue,
    trace: *const abi.RequestTraceView,
    solve_status: c_int,
    problem_count: u32,
    problems_accepted: bool = false,
    unresolved_count: u32 = 0,
    /// When supplied, this is cross-checked against the install-only erase
    /// jobs in the trace. The trace remains the authoritative attribution.
    installonly_retry_erases: ?[]const c.Id = null,
};

pub const Owner = struct {
    backing_allocator: Allocator,
    arena_state: std.heap.ArenaAllocator,
    facts: abi.Capture,

    pub fn destroy(self: *Owner) void {
        const allocator = self.backing_allocator;
        self.arena_state.deinit();
        allocator.destroy(self);
    }

    pub fn view(self: *const Owner) *const abi.Capture {
        return &self.facts;
    }
};

const JobBinding = struct {
    trace_job_ref: u32,
    how: u32,
    what: c.Id,
};

const RawRepository = struct {
    pointer: *c.Repo,
    value: abi.Repository,
};

const RawPackage = struct {
    solvid: c.Id,
    repository: *c.Repo,
    repository_name: []const u8,
    value: abi.Package,
};

const RawAction = struct {
    target: c.Id,
    priors: []const c.Id,
    kind: u32,
    reason: u32,
    requested_job_ref: ?u32,
};

const RawProblem = struct {
    capability: ?abi.Capability = null,
    kind: u32,
    job_ref: ?u32 = null,
    package: ?c.Id = null,
    related_package: ?c.Id = null,
    count: u32 = 1,
};

const BuildState = struct {
    arena: Allocator,
    input: Input,
    queue: []const c.Id,
    trace_requests: []const abi.Request,
    trace_jobs: []const abi.RequestTraceJob,
    bindings: []JobBinding,
    trace_to_pair: []u32,
    referenced: []bool,
    selected_seen: []bool,
    hidden_seen: []bool,
    raw_actions: std.ArrayList(RawAction) = .empty,
    raw_selected: std.ArrayList(c.Id) = .empty,
    raw_hidden: std.ArrayList(c.Id) = .empty,
    raw_problems: std.ArrayList(RawProblem) = .empty,
    skipped_pairs: []bool,
    solver_job_prefix: usize,
    resolution_status: u32,

    fn init(arena: Allocator, input: Input) CaptureError!BuildState {
        if (input.unresolved_count != 0) return error.UnsupportedResult;
        if (input.pool.nsolvables < 2 or input.solver.pool != input.pool) {
            return error.InvalidInput;
        }
        try validateInstalledRepository(input.pool);
        if (input.solve_status < 0) return error.SolverFailed;
        const solve_count: u32 = std.math.cast(
            u32,
            input.solve_status,
        ) orelse return error.InvalidInput;
        const actual_count: u32 = @intCast(
            c.solver_problem_count(input.solver),
        );
        if (solve_count != input.problem_count or
            actual_count != input.problem_count)
        {
            return error.InvalidInput;
        }
        if (input.problem_count == 0 and input.problems_accepted) {
            return error.InvalidInput;
        }
        if ((input.problem_count == 0 or input.problems_accepted) and
            input.transaction == null)
        {
            return error.InvalidInput;
        }
        if (input.transaction) |transaction| {
            if (transaction.pool != input.pool) return error.InvalidInput;
        }

        const queue = try queueElements(input.jobs);
        if (queue.len % 2 != 0) return error.JobMismatch;
        const solver_queue = try queueElements(&input.solver.job);
        if (input.solver.pooljobcnt < 0) return error.JobMismatch;
        const solver_job_prefix: usize = @intCast(input.solver.pooljobcnt);
        if (solver_job_prefix > solver_queue.len or
            solver_job_prefix % 2 != 0 or
            !std.mem.eql(c.Id, queue, solver_queue[solver_job_prefix..]))
        {
            return error.JobMismatch;
        }
        const requests = try borrowedArray(
            abi.Request,
            input.trace.requests,
            input.trace.request_count,
        );
        const jobs = try borrowedArray(
            abi.RequestTraceJob,
            input.trace.jobs,
            input.trace.job_count,
        );
        if (jobs.len != queue.len / 2) return error.JobMismatch;

        const referenced = try arena.alloc(
            bool,
            @intCast(input.pool.nsolvables),
        );
        @memset(referenced, false);
        const selected_seen = try arena.alloc(bool, referenced.len);
        @memset(selected_seen, false);
        const hidden_seen = try arena.alloc(bool, referenced.len);
        @memset(hidden_seen, false);
        const bindings = try arena.alloc(JobBinding, jobs.len);
        const trace_to_pair = try arena.alloc(u32, jobs.len);
        @memset(trace_to_pair, std.math.maxInt(u32));
        const skipped_pairs = try arena.alloc(bool, jobs.len);
        @memset(skipped_pairs, false);

        return .{
            .arena = arena,
            .input = input,
            .queue = queue,
            .trace_requests = requests,
            .trace_jobs = jobs,
            .bindings = bindings,
            .trace_to_pair = trace_to_pair,
            .referenced = referenced,
            .selected_seen = selected_seen,
            .hidden_seen = hidden_seen,
            .skipped_pairs = skipped_pairs,
            .solver_job_prefix = solver_job_prefix,
            .resolution_status = if (input.problem_count == 0)
                abi.resolution_status.resolved
            else if (input.problems_accepted)
                abi.resolution_status.resolved_with_skips
            else
                abi.resolution_status.problems,
        };
    }

    fn build(self: *BuildState) CaptureError!abi.Capture {
        try self.captureTrace();
        try self.captureProblems();
        if (self.resolution_status != abi.resolution_status.problems) {
            try self.captureSelected();
            try self.captureActions();
        }
        try self.captureHidden();
        try self.crossCheckInstallonlyRetries();

        const repositories = try self.captureRepositories();
        const raw_packages = try self.capturePackages(repositories);
        const package_refs = try self.buildPackageRefMap(raw_packages);
        const requests = try self.captureRequests();
        const jobs = try self.captureJobs(package_refs);
        const actions = try self.materializeActions(package_refs);
        const selected = try self.materializePackageRefs(
            self.raw_selected.items,
            package_refs,
        );
        const hidden = try self.materializePackageRefs(
            self.raw_hidden.items,
            package_refs,
        );
        const skipped = try self.materializeSkipped();
        const problems = try self.materializeProblems(package_refs);
        const packages = try self.packageValues(raw_packages);
        const repository_values = try self.repositoryValues(repositories);

        return .{
            .environment = .{
                .resolution_status = self.resolution_status,
            },
            .repositories = optionalPointer(abi.Repository, repository_values),
            .requests = optionalPointer(abi.Request, requests),
            .jobs = optionalPointer(abi.Job, jobs),
            .packages = optionalPointer(abi.Package, packages),
            .actions = optionalPointer(abi.Action, actions.values),
            .prior_package_refs = optionalPointer(u32, actions.priors),
            .selected_package_refs = optionalPointer(u32, selected),
            .skipped_job_refs = optionalPointer(u32, skipped),
            .hidden_package_refs = optionalPointer(u32, hidden),
            .problems = optionalPointer(abi.Problem, problems),
            .repository_count = try countU32(repository_values.len),
            .request_count = try countU32(requests.len),
            .job_count = try countU32(jobs.len),
            .package_count = try countU32(packages.len),
            .action_count = try countU32(actions.values.len),
            .prior_package_ref_count = try countU32(actions.priors.len),
            .selected_package_ref_count = try countU32(selected.len),
            .skipped_job_ref_count = try countU32(skipped.len),
            .hidden_package_ref_count = try countU32(hidden.len),
            .problem_count = try countU32(problems.len),
        };
    }

    fn captureTrace(self: *BuildState) CaptureError!void {
        const origins = try borrowedArray(
            abi.RequestTraceQueueOrigin,
            self.input.trace.queue_origins,
            self.input.trace.queue_origin_count,
        );
        _ = try borrowedArray(
            abi.RequestTracePolicyFact,
            self.input.trace.policy_facts,
            self.input.trace.policy_fact_count,
        );
        if (origins.len != self.bindings.len) return error.JobMismatch;
        _ = try flagValue(self.input.trace.allow_erasing);

        for (self.trace_requests) |request| {
            _ = try bytesSlice(request.id);
            if (try flagValue(request.has_subject)) {
                _ = try bytesSlice(request.subject);
            } else if (!bytesEmpty(request.subject)) {
                return error.InvalidTrace;
            }
            if (request.kind > abi.request_kind.update_all) {
                return error.InvalidTrace;
            }
        }

        for (origins, 0..) |origin, pair_index| {
            if (origin.queue_pair_index != pair_index or
                origin.job_ref >= self.trace_jobs.len or
                self.trace_to_pair[origin.job_ref] != std.math.maxInt(u32))
            {
                return error.JobMismatch;
            }
            const trace_job = self.trace_jobs[origin.job_ref];
            if (try flagValue(origin.has_request_ref)) {
                if (!try flagValue(trace_job.has_request_ref) or
                    origin.request_ref != trace_job.request_ref)
                {
                    return error.JobMismatch;
                }
            } else if (origin.request_ref != 0 or
                try flagValue(trace_job.has_request_ref))
            {
                return error.JobMismatch;
            }

            const how: u32 = @bitCast(self.queue[pair_index * 2]);
            const what = self.queue[pair_index * 2 + 1];
            if (trace_job.effective_how != how or
                (trace_job.raw_how & semanticHowMask()) !=
                    (how & semanticHowMask()))
            {
                return error.JobMismatch;
            }
            try self.validateTraceJob(trace_job, how, what);
            self.bindings[pair_index] = .{
                .trace_job_ref = origin.job_ref,
                .how = how,
                .what = what,
            };
            self.trace_to_pair[origin.job_ref] = @intCast(pair_index);
        }
        for (self.trace_to_pair) |pair| {
            if (pair == std.math.maxInt(u32)) return error.JobMismatch;
        }
    }

    fn validateTraceJob(
        self: *BuildState,
        job: abi.RequestTraceJob,
        how: u32,
        what: c.Id,
    ) CaptureError!void {
        if (job.action > abi.job_action.allow_uninstall or
            job.reason > abi.request_reason.policy or
            job.selection_kind > abi.selection_kind.capability)
        {
            return error.InvalidTrace;
        }
        if (try flagValue(job.has_request_ref)) {
            if (job.request_ref >= self.trace_requests.len or
                job.reason != abi.request_reason.user)
            {
                return error.InvalidTrace;
            }
        } else if (job.request_ref != 0) {
            return error.InvalidTrace;
        }

        const known_trace_flags = abi.request_trace_flag.clean_deps |
            abi.request_trace_flag.force_best |
            abi.request_trace_flag.targeted |
            abi.request_trace_flag.not_by_user |
            abi.request_trace_flag.weak;
        if (job.raw_flags & ~known_trace_flags != 0 or
            job.effective_flags & ~known_trace_flags != 0)
        {
            return error.InvalidTrace;
        }
        var expected_flags = job.raw_flags;
        if (how & intConstant(c.SOLVER_CLEANDEPS) != 0)
            expected_flags |= abi.request_trace_flag.clean_deps;
        if (how & intConstant(c.SOLVER_FORCEBEST) != 0)
            expected_flags |= abi.request_trace_flag.force_best;
        if (how & intConstant(c.SOLVER_TARGETED) != 0)
            expected_flags |= abi.request_trace_flag.targeted;
        if (how & intConstant(c.SOLVER_NOTBYUSER) != 0)
            expected_flags |= abi.request_trace_flag.not_by_user;
        if (how & intConstant(c.SOLVER_WEAK) != 0)
            expected_flags |= abi.request_trace_flag.weak;
        if (job.effective_flags != expected_flags or
            !jobActionMatchesHow(job.action, how))
        {
            return error.JobMismatch;
        }

        const selection = how & intConstant(c.SOLVER_SELECTMASK);
        switch (job.selection_kind) {
            abi.selection_kind.all => {
                if (selection != intConstant(c.SOLVER_SOLVABLE_ALL) or
                    what != 0 or job.selection_id != 0 or
                    !bytesEmpty(job.selection_value) or
                    !capabilityEmpty(job.capability))
                {
                    return error.JobMismatch;
                }
            },
            abi.selection_kind.package => {
                if (selection != intConstant(c.SOLVER_SOLVABLE) or
                    what <= c.SYSTEMSOLVABLE or job.selection_id != what or
                    !bytesEmpty(job.selection_value) or
                    !capabilityEmpty(job.capability))
                {
                    return error.JobMismatch;
                }
                try self.markPackage(what);
            },
            abi.selection_kind.name => {
                const value = try bytesSlice(job.selection_value);
                if (selection != intConstant(c.SOLVER_SOLVABLE_NAME) or
                    job.selection_id != 0 or
                    !capabilityEmpty(job.capability) or
                    !std.mem.eql(u8, value, try poolString(self.input.pool, what)))
                {
                    return error.JobMismatch;
                }
            },
            abi.selection_kind.capability => {
                if (selection != intConstant(c.SOLVER_SOLVABLE_PROVIDES) or
                    job.selection_id != 0 or
                    !bytesEmpty(job.selection_value))
                {
                    return error.JobMismatch;
                }
                const actual = try captureCapability(
                    self.arena,
                    self.input.pool,
                    what,
                );
                const expected = try cloneCapability(
                    self.arena,
                    job.capability,
                );
                if (!capabilitiesEqual(actual, expected)) {
                    return error.JobMismatch;
                }
            },
            else => unreachable,
        }
    }

    fn captureProblems(self: *BuildState) CaptureError!void {
        if (self.input.problem_count == 0) return;

        var rules: c.Queue = undefined;
        c.queue_init(&rules);
        defer c.queue_free(&rules);
        var empty_jobs: [0]bool = .{};
        const jobs_in_problem: []bool = if (self.input.problems_accepted)
            try self.arena.alloc(bool, self.bindings.len)
        else
            empty_jobs[0..];

        var problem_number: c.Id = 1;
        while (problem_number <= self.input.problem_count) : (problem_number += 1) {
            c.solver_findallproblemrules(
                self.input.solver,
                problem_number,
                &rules,
            );
            const problem_rules = try queueElements(&rules);
            if (problem_rules.len == 0) return error.UnsupportedResult;

            const start = self.raw_problems.items.len;
            if (self.input.problems_accepted) {
                @memset(jobs_in_problem, false);
            }

            for (problem_rules) |rule| {
                const job_ref = try self.jobPairForRule(rule);
                if (self.input.problems_accepted) {
                    if (job_ref) |value| jobs_in_problem[value] = true;
                }
                const problem = try self.problemForRule(rule, job_ref);
                if (problem.package) |package| try self.markPackage(package);
                if (problem.related_package) |package|
                    try self.markPackage(package);
                try self.raw_problems.append(self.arena, problem);
            }

            if (!self.input.problems_accepted) continue;
            var job_count: usize = 0;
            for (jobs_in_problem) |present| {
                if (present) job_count += 1;
            }
            if (job_count == 0) return error.UnsupportedResult;
            for (jobs_in_problem, 0..) |present, pair| {
                if (present) self.skipped_pairs[pair] = true;
            }

            const end = self.raw_problems.items.len;
            var index = start;
            while (index < end) : (index += 1) {
                if (self.raw_problems.items[index].job_ref != null) continue;
                var assigned = false;
                for (jobs_in_problem, 0..) |present, pair| {
                    if (!present) continue;
                    if (!assigned) {
                        self.raw_problems.items[index].job_ref =
                            @intCast(pair);
                        assigned = true;
                    } else {
                        var duplicate = self.raw_problems.items[index];
                        duplicate.job_ref = @intCast(pair);
                        try self.raw_problems.append(self.arena, duplicate);
                    }
                }
            }
        }
        if (self.input.problems_accepted) {
            var any_skipped = false;
            for (self.skipped_pairs) |skipped| any_skipped = any_skipped or skipped;
            if (!any_skipped) return error.UnsupportedResult;
        }
    }

    fn problemForRule(
        self: *BuildState,
        rule: c.Id,
        raw_job_ref: ?u32,
    ) CaptureError!RawProblem {
        var source: c.Id = 0;
        var target: c.Id = 0;
        var dep: c.Id = 0;
        const rule_type = c.solver_ruleinfo(
            self.input.solver,
            rule,
            &source,
            &target,
            &dep,
        );
        var problem = RawProblem{ .kind = undefined, .job_ref = raw_job_ref };

        if (rule_type == c.SOLVER_RULE_PKG_NOT_INSTALLABLE) {
            problem.kind = abi.problem_kind.not_installable;
            problem.package = try requiredPackageId(self.input.pool, source);
        } else if (rule_type == c.SOLVER_RULE_PKG_NOTHING_PROVIDES_DEP or
            rule_type == c.SOLVER_RULE_PKG_REQUIRES or
            rule_type == c.SOLVER_RULE_PKG_RECOMMENDS or
            rule_type == c.SOLVER_RULE_PKG_SUPPLEMENTS)
        {
            problem.kind = abi.problem_kind.unsatisfied_requirement;
            problem.package = try requiredPackageId(self.input.pool, source);
            problem.capability = try captureOptionalCapability(
                self.arena,
                self.input.pool,
                dep,
            );
            if (rule_type == c.SOLVER_RULE_PKG_SUPPLEMENTS and target > 0) {
                problem.related_package = try requiredPackageId(
                    self.input.pool,
                    target,
                );
            }
        } else if (rule_type == c.SOLVER_RULE_PKG_SELF_CONFLICT or
            rule_type == c.SOLVER_RULE_PKG_CONFLICTS or
            rule_type == c.SOLVER_RULE_PKG_SAME_NAME or
            rule_type == c.SOLVER_RULE_PKG_CONSTRAINS)
        {
            problem.kind = abi.problem_kind.conflict;
            problem.package = try requiredPackageId(self.input.pool, source);
            if (target > 0 and target != source) {
                problem.related_package = try requiredPackageId(
                    self.input.pool,
                    target,
                );
            }
            problem.capability = try captureOptionalCapability(
                self.arena,
                self.input.pool,
                dep,
            );
        } else if (rule_type == c.SOLVER_RULE_PKG_OBSOLETES or
            rule_type == c.SOLVER_RULE_PKG_IMPLICIT_OBSOLETES or
            rule_type == c.SOLVER_RULE_PKG_INSTALLED_OBSOLETES or
            rule_type == c.SOLVER_RULE_YUMOBS)
        {
            problem.kind = abi.problem_kind.obsoletes;
            problem.package = try requiredPackageId(self.input.pool, source);
            if (target > 0) {
                problem.related_package = try requiredPackageId(
                    self.input.pool,
                    target,
                );
            }
            problem.capability = try captureOptionalCapability(
                self.arena,
                self.input.pool,
                dep,
            );
        } else if (rule_type == c.SOLVER_RULE_DISTUPGRADE or
            rule_type == c.SOLVER_RULE_INFARCH or
            rule_type == c.SOLVER_RULE_UPDATE or
            rule_type == c.SOLVER_RULE_FEATURE or
            rule_type == c.SOLVER_RULE_BLACK or
            rule_type == c.SOLVER_RULE_STRICT_REPO_PRIORITY or
            (rule_type == c.SOLVER_RULE_BEST and source > 0))
        {
            problem.kind = abi.problem_kind.not_installable;
            problem.package = try requiredPackageId(self.input.pool, source);
            problem.capability = try captureOptionalCapability(
                self.arena,
                self.input.pool,
                dep,
            );
            if (rule_type == c.SOLVER_RULE_BEST and problem.job_ref == null and
                target > 0)
            {
                problem.job_ref = try self.jobPairForRule(target);
            }
        } else if (rule_type == c.SOLVER_RULE_JOB or
            rule_type == c.SOLVER_RULE_JOB_PROVIDED_BY_SYSTEM)
        {
            problem.kind = abi.problem_kind.conflict;
            problem.job_ref = problem.job_ref orelse
                try self.jobPairForQueueOffset(source);
            problem.capability = try self.capabilityForJob(problem.job_ref);
        } else if (rule_type == c.SOLVER_RULE_JOB_NOTHING_PROVIDES_DEP or
            rule_type == c.SOLVER_RULE_JOB_UNKNOWN_PACKAGE or
            rule_type == c.SOLVER_RULE_JOB_UNSUPPORTED or
            (rule_type == c.SOLVER_RULE_BEST and source == 0))
        {
            problem.kind = abi.problem_kind.no_candidate;
            if (rule_type == c.SOLVER_RULE_BEST) {
                if (problem.job_ref == null and target > 0) {
                    problem.job_ref = try self.jobPairForRule(target);
                }
                if (problem.job_ref == null) return error.UnsupportedResult;
            } else {
                problem.job_ref = problem.job_ref orelse
                    try self.jobPairForQueueOffset(source);
            }
            problem.capability = try self.capabilityForJob(problem.job_ref);
        } else if ((rule_type == c.SOLVER_RULE_CHOICE or
            rule_type == c.SOLVER_RULE_RECOMMENDS) and source > 0)
        {
            return self.problemForRule(source, raw_job_ref);
        } else {
            return error.UnsupportedResult;
        }
        return problem;
    }

    fn capabilityForJob(
        self: *BuildState,
        raw_pair: ?u32,
    ) CaptureError!?abi.Capability {
        const pair = raw_pair orelse return null;
        if (pair >= self.bindings.len) return error.UnsupportedResult;
        const job = self.trace_jobs[
            self.bindings[pair].trace_job_ref
        ];
        return switch (job.selection_kind) {
            abi.selection_kind.name => .{
                .name = try ownBytes(
                    self.arena,
                    try bytesSlice(job.selection_value),
                ),
                .comparison = abi.compare_op.none,
            },
            abi.selection_kind.capability => try cloneCapability(
                self.arena,
                job.capability,
            ),
            else => null,
        };
    }

    fn jobPairForRule(
        self: *BuildState,
        rule: c.Id,
    ) CaptureError!?u32 {
        const raw_index = c.solver_rule2jobidx(self.input.solver, rule);
        if (raw_index == 0) return null;
        return try self.jobPairForQueueOffset(raw_index - 1);
    }

    fn jobPairForQueueOffset(
        self: *BuildState,
        offset: c.Id,
    ) CaptureError!?u32 {
        if (offset < 0) return error.UnsupportedResult;
        const full_offset: usize = @intCast(offset);
        if (full_offset & 1 != 0) return error.UnsupportedResult;
        if (full_offset < self.solver_job_prefix) return null;
        const relevant_offset = full_offset - self.solver_job_prefix;
        if (relevant_offset >= self.queue.len) return error.UnsupportedResult;
        const pair = relevant_offset / 2;
        if (pair >= self.bindings.len) return error.UnsupportedResult;
        return @intCast(pair);
    }

    fn captureSelected(self: *BuildState) CaptureError!void {
        var selected: c.Queue = undefined;
        c.queue_init(&selected);
        defer c.queue_free(&selected);
        _ = c.transaction_installedresult(
            self.input.transaction.?,
            &selected,
        );
        for (try queueElements(&selected)) |solvid| {
            if (isResultSentinel(solvid)) continue;
            try self.markPackage(solvid);
            try appendUniquePoolId(
                self.arena,
                &self.raw_selected,
                self.selected_seen,
                solvid,
            );
        }
    }

    fn captureActions(self: *BuildState) CaptureError!void {
        const transaction = self.input.transaction.?;
        const mode = c.SOLVER_TRANSACTION_SHOW_ACTIVE |
            c.SOLVER_TRANSACTION_SHOW_ALL |
            c.SOLVER_TRANSACTION_SHOW_OBSOLETES |
            c.SOLVER_TRANSACTION_CHANGE_IS_REINSTALL;
        const prior_seen = try self.arena.alloc(bool, self.referenced.len);
        @memset(prior_seen, false);

        for (try queueElements(&transaction.steps)) |solvid| {
            if (isResultSentinel(solvid)) continue;
            const solvable = try packageSolvable(self.input.pool, solvid);
            if (!(try isRealPackage(self.input.pool, solvable))) {
                return error.UnsupportedResult;
            }
            const raw_type = c.transaction_type(transaction, solvid, mode);
            if (raw_type == c.SOLVER_TRANSACTION_IGNORE) continue;
            if (isPastTransactionType(raw_type)) {
                if (!isInstalledRepository(
                    self.input.pool,
                    try solvableRepository(
                        self.input.pool,
                        solvid,
                        solvable,
                    ),
                )) {
                    return error.UnsupportedResult;
                }
                continue;
            }

            var prior_queue: c.Queue = undefined;
            c.queue_init(&prior_queue);
            defer c.queue_free(&prior_queue);
            if (raw_type != c.SOLVER_TRANSACTION_ERASE and
                raw_type != c.SOLVER_TRANSACTION_INSTALL and
                raw_type != c.SOLVER_TRANSACTION_MULTIINSTALL)
            {
                c.transaction_all_obs_pkgs(
                    transaction,
                    solvid,
                    &prior_queue,
                );
            }
            var priors = std.ArrayList(c.Id).empty;
            defer for (priors.items) |prior| {
                prior_seen[@intCast(prior)] = false;
            };
            for (try queueElements(&prior_queue)) |prior| {
                if (isResultSentinel(prior)) continue;
                const prior_solvable = try packageSolvable(
                    self.input.pool,
                    prior,
                );
                if (!isInstalledRepository(
                    self.input.pool,
                    try solvableRepository(
                        self.input.pool,
                        prior,
                        prior_solvable,
                    ),
                ) or
                    !(try isRealPackage(self.input.pool, prior_solvable)))
                {
                    return error.UnsupportedResult;
                }
                const prior_index: usize = @intCast(prior);
                if (prior_seen[prior_index]) continue;
                prior_seen[prior_index] = true;
                try priors.append(self.arena, prior);
                try self.markPackage(prior);
            }

            const kind = try self.actionKind(
                solvid,
                raw_type,
                priors.items,
            );
            if (kind == null) continue;
            if (kind.? == abi.action_kind.erase) {
                if (!isInstalledRepository(
                    self.input.pool,
                    try solvableRepository(
                        self.input.pool,
                        solvid,
                        solvable,
                    ),
                ) or
                    priors.items.len != 0)
                {
                    return error.UnsupportedResult;
                }
            } else if (isInstalledRepository(
                self.input.pool,
                try solvableRepository(
                    self.input.pool,
                    solvid,
                    solvable,
                ),
            )) {
                return error.UnsupportedResult;
            }

            try self.markPackage(solvid);
            const decision = try self.actionReason(solvid, kind.?);
            try self.raw_actions.append(self.arena, .{
                .target = solvid,
                .priors = try self.arena.dupe(c.Id, priors.items),
                .kind = kind.?,
                .reason = decision.reason,
                .requested_job_ref = decision.job_ref,
            });
        }

        const prior_targets = try self.arena.alloc(
            bool,
            self.referenced.len,
        );
        @memset(prior_targets, false);
        const action_targets = try self.arena.alloc(
            bool,
            self.referenced.len,
        );
        @memset(action_targets, false);
        for (self.raw_actions.items) |action| {
            for (action.priors) |prior| prior_targets[@intCast(prior)] = true;
        }
        var write_index: usize = 0;
        for (self.raw_actions.items) |action| {
            if (action.kind == abi.action_kind.erase and
                prior_targets[@intCast(action.target)])
            {
                continue;
            }
            const target_index: usize = @intCast(action.target);
            if (action_targets[target_index]) return error.UnsupportedResult;
            action_targets[target_index] = true;
            self.raw_actions.items[write_index] = action;
            write_index += 1;
        }
        self.raw_actions.items.len = write_index;
        for (self.raw_actions.items) |action| {
            if (action.requested_job_ref) |job_ref| {
                if (job_ref >= self.skipped_pairs.len or
                    self.skipped_pairs[job_ref])
                {
                    return error.UnsupportedResult;
                }
            }
        }
    }

    fn actionKind(
        self: *BuildState,
        target: c.Id,
        raw_type: c.Id,
        priors: []const c.Id,
    ) CaptureError!?u32 {
        if (raw_type == c.SOLVER_TRANSACTION_ERASE) {
            if (priors.len != 0) return error.UnsupportedResult;
            return abi.action_kind.erase;
        }
        if (raw_type == c.SOLVER_TRANSACTION_INSTALL or
            raw_type == c.SOLVER_TRANSACTION_MULTIINSTALL)
        {
            if (priors.len != 0) return error.UnsupportedResult;
            return abi.action_kind.install;
        }
        if (!isReplacementTransactionType(raw_type) or priors.len == 0) {
            return error.UnsupportedResult;
        }

        const target_solvable = try packageSolvable(self.input.pool, target);
        var highest_same_name: ?c.Id = null;
        for (priors) |prior| {
            const candidate = try packageSolvable(self.input.pool, prior);
            if (candidate.name != target_solvable.name) continue;
            if (highest_same_name == null) {
                highest_same_name = prior;
                continue;
            }
            const current = try packageSolvable(
                self.input.pool,
                highest_same_name.?,
            );
            const comparison = pool_evrcmp(
                self.input.pool,
                candidate.evr,
                current.evr,
                evrcmp_compare,
            );
            if (comparison > 0 or
                (comparison == 0 and
                    try packageTieLess(
                        self.input.pool,
                        highest_same_name.?,
                        prior,
                    )))
            {
                highest_same_name = prior;
            }
        }
        const prior = highest_same_name orelse return abi.action_kind.obsolete;
        const prior_solvable = try packageSolvable(self.input.pool, prior);
        const comparison = pool_evrcmp(
            self.input.pool,
            target_solvable.evr,
            prior_solvable.evr,
            evrcmp_compare,
        );
        return if (comparison > 0)
            abi.action_kind.upgrade
        else if (comparison < 0)
            abi.action_kind.downgrade
        else
            abi.action_kind.reinstall;
    }

    const Decision = struct {
        reason: u32,
        job_ref: ?u32,
    };

    fn actionReason(
        self: *BuildState,
        solvid: c.Id,
        kind: u32,
    ) CaptureError!Decision {
        if (self.installonlyJobFor(solvid)) |job_ref| {
            return .{
                .reason = abi.action_reason.installonly_limit,
                .job_ref = job_ref,
            };
        }

        var info: c.Id = 0;
        const raw_reason = c.solver_describe_decision(
            self.input.solver,
            solvid,
            &info,
        );
        var job_ref: ?u32 = null;
        if (info > 0) {
            job_ref = try self.jobPairForRule(info);
            if (job_ref == null) {
                var source: c.Id = 0;
                var target: c.Id = 0;
                var dep: c.Id = 0;
                const rule_type = c.solver_ruleinfo(
                    self.input.solver,
                    info,
                    &source,
                    &target,
                    &dep,
                );
                if (rule_type == c.SOLVER_RULE_BEST and target > 0) {
                    job_ref = try self.jobPairForRule(target);
                }
            }
        }

        if (kind == abi.action_kind.obsolete) {
            return .{
                .reason = abi.action_reason.obsoletes,
                .job_ref = job_ref,
            };
        }
        if (raw_reason == c.SOLVER_REASON_WEAKDEP) {
            return .{
                .reason = abi.action_reason.weak_dependency,
                .job_ref = null,
            };
        }
        if (raw_reason == c.SOLVER_REASON_CLEANDEPS_ERASE) {
            return .{
                .reason = abi.action_reason.cleanup,
                .job_ref = job_ref,
            };
        }
        if (raw_reason == c.SOLVER_REASON_UPDATE_INSTALLED or
            raw_reason == c.SOLVER_REASON_KEEP_INSTALLED or
            raw_reason == c.SOLVER_REASON_RESOLVE_ORPHAN)
        {
            return .{
                .reason = abi.action_reason.policy,
                .job_ref = null,
            };
        }
        if (job_ref) |pair| {
            const trace_job = self.trace_jobs[
                self.bindings[pair].trace_job_ref
            ];
            return .{
                .reason = actionReasonFromRequest(trace_job.reason),
                .job_ref = pair,
            };
        }
        if (raw_reason == c.SOLVER_REASON_RESOLVE_JOB) {
            return error.UnsupportedResult;
        }
        return .{
            .reason = abi.action_reason.dependency,
            .job_ref = null,
        };
    }

    fn installonlyJobFor(self: *BuildState, solvid: c.Id) ?u32 {
        for (self.bindings, 0..) |binding, pair| {
            const job = self.trace_jobs[binding.trace_job_ref];
            if (job.reason == abi.request_reason.installonly_limit and
                job.action == abi.job_action.erase and
                job.selection_kind == abi.selection_kind.package and
                binding.what == solvid)
            {
                return @intCast(pair);
            }
        }
        return null;
    }

    fn captureHidden(self: *BuildState) CaptureError!void {
        const raw_considered = self.input.pool.considered orelse return;
        const considered: *c.Map = @ptrCast(raw_considered);
        if (considered.size < 0 or considered.map == null) {
            return error.UnsupportedResult;
        }
        const required_map_bytes =
            (@as(usize, @intCast(self.input.pool.nsolvables)) + 7) / 8;
        if (@as(usize, @intCast(considered.size)) < required_map_bytes) {
            return error.UnsupportedResult;
        }
        var solvid: c.Id = 2;
        while (solvid < self.input.pool.nsolvables) : (solvid += 1) {
            const raw_solvable = try solvableAt(self.input.pool, solvid);
            if (raw_solvable.repo == null) continue;
            const solvable = try packageSolvable(self.input.pool, solvid);
            const repository = try solvableRepository(
                self.input.pool,
                solvid,
                solvable,
            );
            if (isInstalledRepository(self.input.pool, repository) or
                repositoryIsCommandLine(repository) or
                !(try isRealPackage(self.input.pool, solvable)) or
                c.map_tst(considered, solvid) != 0)
            {
                continue;
            }
            try self.markPackage(solvid);
            try appendUniquePoolId(
                self.arena,
                &self.raw_hidden,
                self.hidden_seen,
                solvid,
            );
        }
    }

    fn crossCheckInstallonlyRetries(self: *BuildState) CaptureError!void {
        const expected = self.input.installonly_retry_erases orelse return;
        const seen = try self.arena.alloc(bool, self.bindings.len);
        @memset(seen, false);
        var trace_count: usize = 0;
        for (self.bindings, 0..) |binding, pair| {
            const job = self.trace_jobs[binding.trace_job_ref];
            if (job.reason != abi.request_reason.installonly_limit) continue;
            if (job.action != abi.job_action.erase or
                job.selection_kind != abi.selection_kind.package)
            {
                return error.JobMismatch;
            }
            seen[pair] = true;
            trace_count += 1;
        }
        if (trace_count != expected.len) return error.JobMismatch;
        for (expected, 0..) |solvid, index| {
            _ = packageSolvable(self.input.pool, solvid) catch
                return error.JobMismatch;
            for (expected[0..index]) |prior| {
                if (prior == solvid) return error.JobMismatch;
            }
            var found = false;
            for (self.bindings, 0..) |binding, pair| {
                if (seen[pair] and binding.what == solvid) {
                    found = true;
                    break;
                }
            }
            if (!found) return error.JobMismatch;
        }
    }

    fn captureRepositories(
        self: *BuildState,
    ) CaptureError![]RawRepository {
        var repositories = std.ArrayList(RawRepository).empty;
        var solvid: usize = 2;
        while (solvid < self.referenced.len) : (solvid += 1) {
            if (!self.referenced[solvid]) continue;
            const solvable = try packageSolvable(
                self.input.pool,
                @intCast(solvid),
            );
            const repository = try solvableRepository(
                self.input.pool,
                @intCast(solvid),
                solvable,
            );
            var found = false;
            for (repositories.items) |existing| {
                if (existing.pointer == repository) {
                    found = true;
                    break;
                }
            }
            if (found) continue;
            const name = try repositoryName(repository);
            try repositories.append(self.arena, .{
                .pointer = repository,
                .value = .{
                    .id = try ownBytes(self.arena, name),
                    .priority = try repositoryPriority(
                        self.input.pool,
                        repository,
                    ),
                    .kind = repositoryKind(self.input.pool, repository),
                },
            });
        }
        std.sort.pdq(
            RawRepository,
            repositories.items,
            {},
            repositoryLessThan,
        );
        for (repositories.items, 0..) |repository, index| {
            for (repositories.items[0..index]) |prior| {
                if (std.mem.eql(
                    u8,
                    try bytesSlice(repository.value.id),
                    try bytesSlice(prior.value.id),
                )) {
                    return error.AmbiguousPackageMapping;
                }
            }
        }
        return repositories.toOwnedSlice(self.arena);
    }

    fn capturePackages(
        self: *BuildState,
        repositories: []const RawRepository,
    ) CaptureError![]RawPackage {
        var packages = std.ArrayList(RawPackage).empty;
        var solvid: usize = 2;
        while (solvid < self.referenced.len) : (solvid += 1) {
            if (!self.referenced[solvid]) continue;
            const raw_id: c.Id = @intCast(solvid);
            const solvable = try packageSolvable(self.input.pool, raw_id);
            const repository = try solvableRepository(
                self.input.pool,
                raw_id,
                solvable,
            );
            const repository_ref = findRepositoryRef(
                repositories,
                repository,
            ) orelse return error.UnsupportedResult;
            const raw_repository_name = try repositoryName(repository);
            try packages.append(self.arena, .{
                .solvid = raw_id,
                .repository = repository,
                .repository_name = try self.arena.dupe(
                    u8,
                    raw_repository_name,
                ),
                .value = try capturePackage(
                    self.arena,
                    self.input.pool,
                    raw_id,
                    repository_ref,
                ),
            });
        }
        std.sort.pdq(RawPackage, packages.items, {}, packageLessThan);
        if (packages.items.len > 1) {
            for (packages.items[1..], 1..) |package, index| {
                if (packageMappingsEqual(
                    packages.items[index - 1],
                    package,
                )) {
                    return error.AmbiguousPackageMapping;
                }
            }
        }
        return packages.toOwnedSlice(self.arena);
    }

    fn buildPackageRefMap(
        self: *BuildState,
        packages: []const RawPackage,
    ) CaptureError![]u32 {
        const refs = try self.arena.alloc(u32, self.referenced.len);
        @memset(refs, std.math.maxInt(u32));
        for (packages, 0..) |package, index| {
            refs[@intCast(package.solvid)] = try countU32(index);
        }
        return refs;
    }

    fn captureRequests(self: *BuildState) CaptureError![]abi.Request {
        const output = try self.arena.alloc(
            abi.Request,
            self.trace_requests.len,
        );
        for (self.trace_requests, output) |request, *destination| {
            destination.* = .{
                .id = try ownBytes(
                    self.arena,
                    try bytesSlice(request.id),
                ),
                .kind = request.kind,
            };
            if (try flagValue(request.has_subject)) {
                destination.subject = try ownBytes(
                    self.arena,
                    try bytesSlice(request.subject),
                );
                destination.has_subject = 1;
            }
        }
        return output;
    }

    fn captureJobs(
        self: *BuildState,
        package_refs: []const u32,
    ) CaptureError![]abi.Job {
        const output = try self.arena.alloc(abi.Job, self.bindings.len);
        for (self.bindings, output) |binding, *destination| {
            const source = self.trace_jobs[binding.trace_job_ref];
            destination.* = .{
                .action = source.action,
                .selection_kind = source.selection_kind,
                .reason = source.reason,
                .clean_deps = flag(
                    source.effective_flags,
                    abi.request_trace_flag.clean_deps,
                ),
                .force_best = flag(
                    source.effective_flags,
                    abi.request_trace_flag.force_best,
                ),
                .targeted = flag(
                    source.effective_flags,
                    abi.request_trace_flag.targeted,
                ),
                .not_by_user = flag(
                    source.effective_flags,
                    abi.request_trace_flag.not_by_user,
                ),
                .weak = flag(
                    source.effective_flags,
                    abi.request_trace_flag.weak,
                ),
            };
            switch (source.selection_kind) {
                abi.selection_kind.package => {
                    destination.selection_package_ref = try packageRef(
                        package_refs,
                        binding.what,
                    );
                },
                abi.selection_kind.name => {
                    destination.selection_value = try ownBytes(
                        self.arena,
                        try bytesSlice(source.selection_value),
                    );
                },
                abi.selection_kind.capability => {
                    destination.capability = try cloneCapability(
                        self.arena,
                        source.capability,
                    );
                },
                abi.selection_kind.all => {},
                else => unreachable,
            }
            if (try flagValue(source.has_request_ref)) {
                destination.request_ref = source.request_ref;
                destination.has_request_ref = 1;
            }
        }
        return output;
    }

    const MaterializedActions = struct {
        values: []abi.Action,
        priors: []u32,
    };

    fn materializeActions(
        self: *BuildState,
        package_refs: []const u32,
    ) CaptureError!MaterializedActions {
        for (self.raw_actions.items) |*action| {
            std.sort.pdq(c.Id, @constCast(action.priors), package_refs, solvidRefLess);
        }
        std.sort.pdq(
            RawAction,
            self.raw_actions.items,
            package_refs,
            actionLessThan,
        );

        var prior_count: usize = 0;
        for (self.raw_actions.items) |action| {
            prior_count = std.math.add(
                usize,
                prior_count,
                action.priors.len,
            ) catch return error.UnsupportedResult;
        }
        const output = try self.arena.alloc(
            abi.Action,
            self.raw_actions.items.len,
        );
        const priors = try self.arena.alloc(u32, prior_count);
        var prior_offset: usize = 0;
        for (self.raw_actions.items, output) |action, *destination| {
            destination.* = .{
                .target_package_ref = try packageRef(
                    package_refs,
                    action.target,
                ),
                .kind = action.kind,
                .reason = action.reason,
                .prior_offset = try countU32(prior_offset),
                .prior_count = try countU32(action.priors.len),
            };
            if (action.requested_job_ref) |job_ref| {
                if (job_ref >= self.bindings.len)
                    return error.UnsupportedResult;
                destination.requested_job_ref = job_ref;
                destination.has_requested_job_ref = 1;
            }
            for (action.priors) |prior| {
                priors[prior_offset] = try packageRef(package_refs, prior);
                prior_offset += 1;
            }
        }
        return .{ .values = output, .priors = priors };
    }

    fn materializePackageRefs(
        self: *BuildState,
        raw: []const c.Id,
        package_refs: []const u32,
    ) CaptureError![]u32 {
        const output = try self.arena.alloc(u32, raw.len);
        for (raw, output) |solvid, *destination| {
            destination.* = try packageRef(package_refs, solvid);
        }
        std.mem.sort(u32, output, {}, std.sort.asc(u32));
        if (output.len > 1) {
            for (output[1..], 1..) |value, index| {
                if (output[index - 1] == value)
                    return error.AmbiguousPackageMapping;
            }
        }
        return output;
    }

    fn materializeSkipped(self: *BuildState) CaptureError![]u32 {
        var output = std.ArrayList(u32).empty;
        for (self.skipped_pairs, 0..) |skipped, pair| {
            if (skipped) try output.append(self.arena, try countU32(pair));
        }
        return output.toOwnedSlice(self.arena);
    }

    fn materializeProblems(
        self: *BuildState,
        package_refs: []const u32,
    ) CaptureError![]abi.Problem {
        var output = std.ArrayList(abi.Problem).empty;
        for (self.raw_problems.items) |problem| {
            var value = abi.Problem{
                .kind = problem.kind,
                .count = problem.count,
            };
            if (problem.capability) |capability| {
                value.capability = capability;
                value.has_capability = 1;
            }
            if (problem.job_ref) |job_ref| {
                if (job_ref >= self.bindings.len)
                    return error.UnsupportedResult;
                value.job_ref = job_ref;
                value.has_job_ref = 1;
            }
            if (problem.package) |package| {
                value.package_ref = try packageRef(package_refs, package);
                value.has_package_ref = 1;
            }
            if (problem.related_package) |package| {
                value.related_package_ref = try packageRef(
                    package_refs,
                    package,
                );
                value.has_related_package_ref = 1;
            }
            try output.append(self.arena, value);
        }
        std.sort.pdq(abi.Problem, output.items, {}, problemLessThan);
        var write_index: usize = 0;
        for (output.items) |problem| {
            if (write_index != 0 and
                problemsEqual(output.items[write_index - 1], problem))
            {
                output.items[write_index - 1].count = std.math.add(
                    u32,
                    output.items[write_index - 1].count,
                    problem.count,
                ) catch return error.UnsupportedResult;
                continue;
            }
            output.items[write_index] = problem;
            write_index += 1;
        }
        output.items.len = write_index;
        return output.toOwnedSlice(self.arena);
    }

    fn packageValues(
        self: *BuildState,
        raw: []const RawPackage,
    ) CaptureError![]abi.Package {
        const output = try self.arena.alloc(abi.Package, raw.len);
        for (raw, output) |package, *destination| {
            destination.* = package.value;
        }
        return output;
    }

    fn repositoryValues(
        self: *BuildState,
        raw: []const RawRepository,
    ) CaptureError![]abi.Repository {
        const output = try self.arena.alloc(abi.Repository, raw.len);
        for (raw, output) |repository, *destination| {
            destination.* = repository.value;
        }
        return output;
    }

    fn markPackage(self: *BuildState, solvid: c.Id) CaptureError!void {
        if (solvid <= c.SYSTEMSOLVABLE or
            solvid >= self.input.pool.nsolvables)
        {
            return error.UnsupportedResult;
        }
        const solvable = try packageSolvable(self.input.pool, solvid);
        if (!(try isRealPackage(
            self.input.pool,
            solvable,
        ))) {
            return error.UnsupportedResult;
        }
        self.referenced[@intCast(solvid)] = true;
    }
};

pub fn create(
    backing_allocator: Allocator,
    input: Input,
) CaptureError!*Owner {
    const owner = try backing_allocator.create(Owner);
    owner.* = .{
        .backing_allocator = backing_allocator,
        .arena_state = std.heap.ArenaAllocator.init(backing_allocator),
        .facts = .{},
    };
    errdefer owner.destroy();

    var state = try BuildState.init(owner.arena_state.allocator(), input);
    owner.facts = try state.build();
    return owner;
}

pub fn mapCaptureError(err: anyerror) u32 {
    return switch (err) {
        error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        error.UnsupportedResult => error_codes.ERROR_TDNF_CALL_NOT_SUPPORTED,
        error.SolverFailed => error_codes.ERROR_TDNF_SOLV_FAILED,
        else => error_codes.ERROR_TDNF_INVALID_PARAMETER,
    };
}

pub fn libsolvCaptureCreate(
    raw_pool: ?*anyopaque,
    raw_solver: ?*anyopaque,
    raw_transaction: ?*anyopaque,
    raw_jobs: ?*const anyopaque,
    trace: ?*const abi.RequestTraceView,
    solve_status: c_int,
    problem_count: u32,
    problems_accepted: u32,
    unresolved_count: u32,
    raw_installonly_erases: ?[*]const c.Id,
    installonly_erase_count: u32,
    raw_facts: ?*?*const abi.Capture,
    raw_owner: ?*?*anyopaque,
) callconv(.c) u32 {
    if (raw_facts) |output| output.* = null;
    if (raw_owner) |output| output.* = null;
    const facts_out = raw_facts orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const owner_out = raw_owner orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (unresolved_count != 0) {
        return mapCaptureError(error.UnsupportedResult);
    }
    const accepted = flagValue(problems_accepted) catch
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const installonly_erases = borrowedArray(
        c.Id,
        raw_installonly_erases,
        installonly_erase_count,
    ) catch |err| return mapCaptureError(err);
    const owner = create(std.heap.c_allocator, .{
        .pool = @ptrCast(@alignCast(raw_pool orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER)),
        .solver = @ptrCast(@alignCast(raw_solver orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER)),
        .transaction = if (raw_transaction) |value|
            @ptrCast(@alignCast(value))
        else
            null,
        .jobs = @ptrCast(@alignCast(raw_jobs orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER)),
        .trace = trace orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER,
        .solve_status = solve_status,
        .problem_count = problem_count,
        .problems_accepted = accepted,
        .unresolved_count = unresolved_count,
        .installonly_retry_erases = installonly_erases,
    }) catch |err| return mapCaptureError(err);
    facts_out.* = owner.view();
    owner_out.* = @ptrCast(owner);
    return 0;
}

fn libsolvCaptureDestroy(raw_owner: ?*anyopaque) callconv(.c) void {
    const pointer = raw_owner orelse return;
    const owner: *Owner = @ptrCast(@alignCast(pointer));
    owner.destroy();
}

comptime {
    @export(&libsolvCaptureCreate, .{
        .name = "TDNFTransactionPlanLibsolvCaptureCreate",
        .visibility = .hidden,
    });
    @export(&libsolvCaptureDestroy, .{
        .name = "TDNFTransactionPlanLibsolvCaptureDestroy",
        .visibility = .hidden,
    });
}

fn capturePackage(
    allocator: Allocator,
    pool: *c.Pool,
    solvid: c.Id,
    repository_ref: u32,
) CaptureError!abi.Package {
    const solvable = try packageSolvable(pool, solvid);
    const repository = try solvableRepository(pool, solvid, solvable);
    const identity = try parseIdentity(
        allocator,
        pool,
        solvable,
    );
    var output = abi.Package{
        .identity = identity,
        .repository_ref = repository_ref,
        .state = if (repository == pool.installed)
            abi.package_state.installed
        else
            abi.package_state.available,
    };
    if (repository == pool.installed) {
        const missing = std.math.maxInt(u64);
        const hnum = c.solvable_lookup_num(
            solvable,
            c.RPM_RPMDBID,
            missing,
        );
        if (hnum == missing or hnum == 0 or hnum > std.math.maxInt(u32)) {
            return error.UnsupportedResult;
        }
        output.rpmdb_hnum = @intCast(hnum);
        output.has_rpmdb_hnum = 1;
        return output;
    }

    output.source = try capturePackageSource(
        allocator,
        pool,
        solvable,
        repositoryIsCommandLine(repository),
    );
    output.has_source = 1;
    return output;
}

fn capturePackageSource(
    allocator: Allocator,
    pool: *c.Pool,
    solvable: *c.Solvable,
    command_line: bool,
) CaptureError!abi.PackageSource {
    var checksum_type: c.Id = 0;
    var checksum = c.solvable_lookup_checksum(
        solvable,
        c.SOLVABLE_PKGID,
        &checksum_type,
    );
    var is_pkgid = checksum != null;
    if (checksum == null) {
        checksum = c.solvable_lookup_checksum(
            solvable,
            c.SOLVABLE_CHECKSUM,
            &checksum_type,
        );
        is_pkgid = false;
    }
    const checksum_value = checksum orelse return error.UnsupportedResult;
    const raw_kind = try poolString(pool, checksum_type);
    const separator = std.mem.lastIndexOfScalar(u8, raw_kind, ':');
    const checksum_kind = if (separator) |index|
        raw_kind[index + 1 ..]
    else
        raw_kind;
    if (checksum_kind.len == 0) return error.UnsupportedResult;

    var output = abi.PackageSource{
        .checksum = .{
            .kind = try ownBytes(allocator, checksum_kind),
            .value = try ownBytes(allocator, std.mem.span(checksum_value)),
            .is_pkgid = @intFromBool(is_pkgid),
        },
    };
    if (!command_line) {
        var media_number: c_uint = 0;
        const location = c.solvable_lookup_location(
            solvable,
            &media_number,
        ) orelse return error.UnsupportedResult;
        output.location.href = try ownBytes(allocator, std.mem.span(location));
        if (c.solvable_lookup_str(solvable, c.SOLVABLE_MEDIABASE)) |xml_base| {
            output.location.xml_base = try ownBytes(
                allocator,
                std.mem.span(xml_base),
            );
            output.location.has_xml_base = 1;
        }
        output.has_location = 1;
    }

    const missing = std.math.maxInt(u64);
    const size = c.solvable_lookup_num(
        solvable,
        c.SOLVABLE_DOWNLOADSIZE,
        missing,
    );
    if (size != missing) {
        output.size = size;
        output.has_size = 1;
    }
    return output;
}

fn parseIdentity(
    allocator: Allocator,
    pool: *c.Pool,
    solvable: *c.Solvable,
) CaptureError!abi.PackageIdentity {
    const name = try poolString(pool, solvable.name);
    const arch = try poolString(pool, solvable.arch);
    const evr = try poolString(pool, solvable.evr);
    if (name.len == 0 or arch.len == 0 or evr.len == 0) {
        return error.UnsupportedResult;
    }

    const parsed_evr = try splitEvrEpoch(evr);
    const version_release = parsed_evr.version_release;
    const epoch: ?u32 = if (parsed_evr.epoch) |value|
        std.math.cast(u32, value) orelse return error.UnsupportedResult
    else
        null;
    const release_separator = std.mem.lastIndexOfScalar(
        u8,
        version_release,
        '-',
    ) orelse return error.UnsupportedResult;
    if (release_separator == 0 or
        release_separator + 1 == version_release.len)
    {
        return error.UnsupportedResult;
    }

    var output = abi.PackageIdentity{
        .name = try ownBytes(allocator, name),
        .arch = try ownBytes(allocator, arch),
        .version = try ownBytes(
            allocator,
            version_release[0..release_separator],
        ),
        .release = try ownBytes(
            allocator,
            version_release[release_separator + 1 ..],
        ),
    };
    if (epoch) |value| {
        output.epoch = value;
        output.has_epoch = 1;
    }
    return output;
}

fn captureOptionalCapability(
    allocator: Allocator,
    pool: *c.Pool,
    dep: c.Id,
) CaptureError!?abi.Capability {
    if (dep == 0) return null;
    return try captureCapability(allocator, pool, dep);
}

fn captureCapability(
    allocator: Allocator,
    pool: *c.Pool,
    dep: c.Id,
) CaptureError!abi.Capability {
    if (!isRelationId(dep)) {
        const name = try poolString(pool, dep);
        if (name.len == 0) return error.UnsupportedResult;
        return .{
            .name = try ownBytes(allocator, name),
            .comparison = abi.compare_op.none,
        };
    }
    const relation_index = relationIndex(dep);
    if (relation_index <= 0 or relation_index >= pool.nrels or
        pool.rels == null)
    {
        return error.UnsupportedResult;
    }
    const relation = pool.rels[@intCast(relation_index)];
    if (isRelationId(relation.name) or isRelationId(relation.evr)) {
        return error.UnsupportedResult;
    }
    const comparison = comparisonFromRelation(relation.flags) orelse
        return error.UnsupportedResult;
    const name = try poolString(pool, relation.name);
    const evr = try poolString(pool, relation.evr);
    if (name.len == 0) return error.UnsupportedResult;
    var output = abi.Capability{
        .name = try ownBytes(allocator, name),
        .comparison = comparison.value,
        .flags = try ownBytes(allocator, comparison.flags),
        .has_flags = 1,
    };
    if (evr.len == 0) return output;

    const parsed_evr = try splitEvrEpoch(evr);
    const version_release = parsed_evr.version_release;
    if (parsed_evr.epoch) |epoch| {
        output.epoch = epoch;
        output.has_epoch = 1;
    }
    if (std.mem.lastIndexOfScalar(u8, version_release, '-')) |separator| {
        if (separator == 0 or separator + 1 == version_release.len) {
            return error.UnsupportedResult;
        }
        output.version = try ownBytes(
            allocator,
            version_release[0..separator],
        );
        output.release = try ownBytes(
            allocator,
            version_release[separator + 1 ..],
        );
        output.has_version = 1;
        output.has_release = 1;
    } else {
        if (version_release.len == 0) return error.UnsupportedResult;
        output.version = try ownBytes(allocator, version_release);
        output.has_version = 1;
    }
    return output;
}

const EvrEpoch = struct {
    epoch: ?u64,
    version_release: []const u8,
};

fn splitEvrEpoch(evr: []const u8) CaptureError!EvrEpoch {
    const colon = std.mem.indexOfScalar(u8, evr, ':') orelse
        return .{ .epoch = null, .version_release = evr };
    if (colon == 0 or colon + 1 == evr.len) {
        return .{ .epoch = null, .version_release = evr };
    }
    for (evr[0..colon]) |byte| {
        if (!std.ascii.isDigit(byte)) {
            return .{ .epoch = null, .version_release = evr };
        }
    }
    return .{
        .epoch = std.fmt.parseUnsigned(u64, evr[0..colon], 10) catch
            return error.UnsupportedResult,
        .version_release = evr[colon + 1 ..],
    };
}

const RelationComparison = struct {
    value: u32,
    flags: []const u8,
};

fn comparisonFromRelation(flags: c_int) ?RelationComparison {
    return switch (flags) {
        c.REL_EQ => .{ .value = abi.compare_op.eq, .flags = "EQ" },
        c.REL_GT => .{ .value = abi.compare_op.gt, .flags = "GT" },
        c.REL_LT => .{ .value = abi.compare_op.lt, .flags = "LT" },
        c.REL_GT | c.REL_EQ => .{
            .value = abi.compare_op.ge,
            .flags = "GE",
        },
        c.REL_LT | c.REL_EQ => .{
            .value = abi.compare_op.le,
            .flags = "LE",
        },
        else => null,
    };
}

fn cloneCapability(
    allocator: Allocator,
    source: abi.Capability,
) CaptureError!abi.Capability {
    var output = abi.Capability{
        .name = try ownBytes(allocator, try bytesSlice(source.name)),
        .comparison = source.comparison,
        .sense = source.sense,
        .epoch = source.epoch,
        .pre = @intFromBool(try flagValue(source.pre)),
    };
    if (source.comparison > abi.compare_op.none) return error.InvalidTrace;
    if (try flagValue(source.has_flags)) {
        output.flags = try ownBytes(
            allocator,
            try bytesSlice(source.flags),
        );
        output.has_flags = 1;
    } else if (!bytesEmpty(source.flags)) return error.InvalidTrace;
    if (try flagValue(source.has_version)) {
        output.version = try ownBytes(
            allocator,
            try bytesSlice(source.version),
        );
        output.has_version = 1;
    } else if (!bytesEmpty(source.version)) return error.InvalidTrace;
    if (try flagValue(source.has_release)) {
        output.release = try ownBytes(
            allocator,
            try bytesSlice(source.release),
        );
        output.has_release = 1;
    } else if (!bytesEmpty(source.release)) return error.InvalidTrace;
    if (try flagValue(source.has_epoch)) {
        output.has_epoch = 1;
    } else if (source.epoch != 0) return error.InvalidTrace;
    return output;
}

fn capabilitiesEqual(left: abi.Capability, right: abi.Capability) bool {
    if (left.comparison != right.comparison or
        left.sense != right.sense or
        left.epoch != right.epoch or
        left.has_epoch != right.has_epoch or
        left.has_flags != right.has_flags or
        left.has_version != right.has_version or
        left.has_release != right.has_release or
        left.pre != right.pre)
    {
        return false;
    }
    return abiBytesEqual(left.name, right.name) and
        abiBytesEqual(left.flags, right.flags) and
        abiBytesEqual(left.version, right.version) and
        abiBytesEqual(left.release, right.release);
}

fn capabilityEmpty(value: abi.Capability) bool {
    return bytesEmpty(value.name) and bytesEmpty(value.flags) and
        bytesEmpty(value.version) and bytesEmpty(value.release) and
        value.epoch == 0 and value.comparison == 0 and value.sense == 0 and
        value.has_epoch == 0 and value.has_flags == 0 and
        value.has_version == 0 and value.has_release == 0 and
        value.pre == 0;
}

fn queueElements(queue: *const c.Queue) CaptureError![]const c.Id {
    if (queue.count < 0) return error.InvalidInput;
    const count: usize = @intCast(queue.count);
    if (!sliceCountFitsAddressLimit(
        c.Id,
        count,
        @intCast(std.math.maxInt(isize)),
    )) {
        return error.InvalidInput;
    }
    if (count == 0) return &.{};
    if (queue.elements == null) return error.InvalidInput;
    return queue.elements[0..count];
}

fn borrowedArray(
    comptime T: type,
    pointer: ?[*]const T,
    count: u32,
) CaptureError![]const T {
    if (count == 0) {
        if (pointer != null) return error.InvalidTrace;
        return &.{};
    }
    const value_count = std.math.cast(usize, count) orelse
        return error.InvalidTrace;
    if (!sliceCountFitsAddressLimit(
        T,
        value_count,
        @intCast(std.math.maxInt(isize)),
    )) {
        return error.InvalidTrace;
    }
    const values = pointer orelse return error.InvalidTrace;
    return values[0..value_count];
}

fn bytesSlice(value: abi.Bytes) CaptureError![]const u8 {
    if (value.length == 0) {
        if (value.data != null) return error.InvalidTrace;
        return "";
    }
    if (value.length > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return error.InvalidTrace;
    }
    const pointer = value.data orelse return error.InvalidTrace;
    return pointer[0..value.length];
}

pub fn sliceCountFitsAddressLimit(
    comptime T: type,
    count: usize,
    address_limit: usize,
) bool {
    if (count > address_limit) return false;
    const byte_length = std.math.mul(usize, count, @sizeOf(T)) catch
        return false;
    return byte_length <= address_limit;
}

fn bytesEmpty(value: abi.Bytes) bool {
    return value.data == null and value.length == 0;
}

fn ownBytes(allocator: Allocator, value: []const u8) CaptureError!abi.Bytes {
    if (value.len == 0) return .{};
    const owned = try allocator.dupe(u8, value);
    return .{ .data = owned.ptr, .length = owned.len };
}

fn optionalPointer(comptime T: type, values: []const T) ?[*]const T {
    return if (values.len == 0) null else values.ptr;
}

fn countU32(value: usize) CaptureError!u32 {
    return std.math.cast(u32, value) orelse error.UnsupportedResult;
}

fn flagValue(value: u32) CaptureError!bool {
    return switch (value) {
        0 => false,
        1 => true,
        else => error.InvalidTrace,
    };
}

fn flag(flags: u32, mask: u32) u32 {
    return @intFromBool(flags & mask != 0);
}

fn intConstant(value: anytype) u32 {
    return @intCast(value);
}

fn semanticHowMask() u32 {
    return intConstant(c.SOLVER_SELECTMASK) |
        intConstant(c.SOLVER_JOBMASK) |
        intConstant(c.SOLVER_SETMASK);
}

fn jobActionMatchesHow(action: u32, how: u32) bool {
    const raw_action = how & intConstant(c.SOLVER_JOBMASK);
    return switch (action) {
        abi.job_action.install,
        abi.job_action.downgrade,
        abi.job_action.reinstall,
        => raw_action == intConstant(c.SOLVER_INSTALL),
        abi.job_action.erase => raw_action == intConstant(c.SOLVER_ERASE),
        abi.job_action.update => raw_action == intConstant(c.SOLVER_UPDATE) or
            raw_action == intConstant(c.SOLVER_INSTALL),
        abi.job_action.dist_sync => raw_action ==
            intConstant(c.SOLVER_DISTUPGRADE),
        abi.job_action.lock => raw_action == intConstant(c.SOLVER_LOCK),
        abi.job_action.multiversion => raw_action ==
            intConstant(c.SOLVER_MULTIVERSION),
        abi.job_action.user_installed => raw_action ==
            intConstant(c.SOLVER_USERINSTALLED),
        abi.job_action.allow_uninstall => raw_action ==
            intConstant(c.SOLVER_ALLOWUNINSTALL),
        else => false,
    };
}

fn actionReasonFromRequest(reason: u32) u32 {
    return switch (reason) {
        abi.request_reason.user => abi.action_reason.user,
        abi.request_reason.dependency => abi.action_reason.dependency,
        abi.request_reason.weak_dependency => abi.action_reason.weak_dependency,
        abi.request_reason.cleanup => abi.action_reason.cleanup,
        abi.request_reason.installonly_limit => abi.action_reason.installonly_limit,
        abi.request_reason.policy => abi.action_reason.policy,
        else => unreachable,
    };
}

fn packageSolvable(
    pool: *c.Pool,
    solvid: c.Id,
) CaptureError!*c.Solvable {
    const solvable = try solvableAt(pool, solvid);
    _ = try poolString(pool, solvable.name);
    _ = try poolString(pool, solvable.arch);
    _ = try poolString(pool, solvable.evr);
    _ = try solvableRepository(pool, solvid, solvable);
    return solvable;
}

fn solvableAt(
    pool: *c.Pool,
    solvid: c.Id,
) CaptureError!*c.Solvable {
    if (solvid <= c.SYSTEMSOLVABLE or solvid >= pool.nsolvables) {
        return error.UnsupportedResult;
    }
    if (pool.solvables == null) return error.UnsupportedResult;
    const raw = c.pool_id2solvable(pool, solvid);
    if (raw == null) return error.UnsupportedResult;
    return @ptrCast(raw);
}

fn solvableRepository(
    pool: *c.Pool,
    solvid: c.Id,
    solvable: *c.Solvable,
) CaptureError!*c.Repo {
    const raw = solvable.*.repo orelse return error.UnsupportedResult;
    const repository: *c.Repo = @ptrCast(raw);
    const index = try repositoryIndex(pool, repository);
    if (repository.pool != pool or
        repository.repoid != index or
        repository.start < 2 or
        repository.end <= repository.start or
        repository.end > pool.nsolvables or
        repository.nsolvables <= 0 or
        solvid < repository.start or
        solvid >= repository.end)
    {
        return error.UnsupportedResult;
    }
    return repository;
}

fn repositoryIndex(
    pool: *c.Pool,
    repository: *c.Repo,
) CaptureError!c.Id {
    if (pool.nrepos <= 0 or pool.repos == null) {
        return error.UnsupportedResult;
    }
    if (!sliceCountFitsAddressLimit(
        ?*c.Repo,
        @intCast(pool.nrepos),
        @intCast(std.math.maxInt(isize)),
    )) {
        return error.UnsupportedResult;
    }
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        if (pool.repos[@intCast(index)] == repository) return index;
    }
    return error.UnsupportedResult;
}

fn validateInstalledRepository(pool: *c.Pool) CaptureError!void {
    const raw = pool.installed orelse return;
    const repository: *c.Repo = @ptrCast(raw);
    const index = try repositoryIndex(pool, repository);
    if (repository.pool != pool or
        repository.repoid != index or
        repository.start < 0 or
        repository.end < repository.start or
        repository.end > pool.nsolvables or
        repository.nsolvables < 0)
    {
        return error.UnsupportedResult;
    }
}

fn isInstalledRepository(pool: *c.Pool, repository: *c.Repo) bool {
    return pool.installed != null and
        repository == @as(*c.Repo, @ptrCast(pool.installed));
}

fn requiredPackageId(pool: *c.Pool, solvid: c.Id) CaptureError!c.Id {
    _ = try packageSolvable(pool, solvid);
    return solvid;
}

fn poolString(pool: *c.Pool, id: c.Id) CaptureError![]const u8 {
    if (id <= 0 or isRelationId(id) or
        pool.ss.nstrings <= 0 or
        id >= pool.ss.nstrings or
        pool.ss.strings == null or
        pool.ss.stringspace == null)
    {
        return error.UnsupportedResult;
    }
    const offset = pool.ss.strings[@intCast(id)];
    if (offset >= pool.ss.sstrings) return error.UnsupportedResult;
    const raw = c.pool_id2str(pool, id);
    if (raw == null) return error.UnsupportedResult;
    return std.mem.span(raw);
}

fn repositoryName(repository: *c.Repo) CaptureError![]const u8 {
    const raw = repository.*.name orelse return error.UnsupportedResult;
    const name = std.mem.span(raw);
    if (name.len == 0) return error.UnsupportedResult;
    return name;
}

fn repositoryIsCommandLine(repository: *c.Repo) bool {
    const raw = repository.*.name orelse return false;
    return std.mem.eql(u8, std.mem.span(raw), "@cmdline");
}

fn repositoryKind(pool: *c.Pool, repository: *c.Repo) u32 {
    if (isInstalledRepository(pool, repository))
        return abi.repository_kind.installed;
    if (repositoryIsCommandLine(repository))
        return abi.repository_kind.command_line;
    return abi.repository_kind.available;
}

fn repositoryPriority(
    pool: *c.Pool,
    repository: *c.Repo,
) CaptureError!i32 {
    return switch (repositoryKind(pool, repository)) {
        abi.repository_kind.available => {
            if (repository.priority == std.math.minInt(i32)) {
                return error.UnsupportedResult;
            }
            return -repository.priority;
        },
        abi.repository_kind.installed,
        abi.repository_kind.command_line,
        => 0,
        else => unreachable,
    };
}

fn isRealPackage(
    pool: *c.Pool,
    solvable: *c.Solvable,
) CaptureError!bool {
    return !std.mem.startsWith(
        u8,
        try poolString(pool, solvable.name),
        "patch:",
    );
}

fn isResultSentinel(solvid: c.Id) bool {
    return solvid == 0 or solvid == c.SYSTEMSOLVABLE;
}

fn isPastTransactionType(raw_type: c.Id) bool {
    return raw_type == c.SOLVER_TRANSACTION_REINSTALLED or
        raw_type == c.SOLVER_TRANSACTION_DOWNGRADED or
        raw_type == c.SOLVER_TRANSACTION_CHANGED or
        raw_type == c.SOLVER_TRANSACTION_UPGRADED or
        raw_type == c.SOLVER_TRANSACTION_OBSOLETED;
}

fn isReplacementTransactionType(raw_type: c.Id) bool {
    return raw_type == c.SOLVER_TRANSACTION_REINSTALL or
        raw_type == c.SOLVER_TRANSACTION_MULTIREINSTALL or
        raw_type == c.SOLVER_TRANSACTION_DOWNGRADE or
        raw_type == c.SOLVER_TRANSACTION_CHANGE or
        raw_type == c.SOLVER_TRANSACTION_UPGRADE or
        raw_type == c.SOLVER_TRANSACTION_OBSOLETES;
}

fn isRelationId(id: c.Id) bool {
    const bits: u32 = @bitCast(id);
    return bits & 0x80000000 != 0;
}

fn relationIndex(id: c.Id) c.Id {
    const bits: u32 = @bitCast(id);
    return @bitCast(bits ^ 0x80000000);
}

fn findRepositoryRef(
    repositories: []const RawRepository,
    pointer: *c.Repo,
) ?u32 {
    for (repositories, 0..) |repository, index| {
        if (repository.pointer == pointer) return @intCast(index);
    }
    return null;
}

fn packageRef(refs: []const u32, solvid: c.Id) CaptureError!u32 {
    if (solvid < 0 or solvid >= refs.len) return error.UnsupportedResult;
    const value = refs[@intCast(solvid)];
    if (value == std.math.maxInt(u32)) return error.UnsupportedResult;
    return value;
}

fn appendUniquePoolId(
    allocator: Allocator,
    list: *std.ArrayList(c.Id),
    seen: []bool,
    value: c.Id,
) CaptureError!void {
    if (value < 0 or value >= seen.len) return error.UnsupportedResult;
    const index: usize = @intCast(value);
    if (seen[index]) return;
    seen[index] = true;
    try list.append(allocator, value);
}

fn repositoryLessThan(
    _: void,
    left: RawRepository,
    right: RawRepository,
) bool {
    if (left.value.kind != right.value.kind)
        return left.value.kind < right.value.kind;
    return abiBytesOrder(left.value.id, right.value.id) == .lt;
}

fn packageLessThan(_: void, left: RawPackage, right: RawPackage) bool {
    return packageOrder(left, right) == .lt;
}

fn packageOrder(left: RawPackage, right: RawPackage) std.math.Order {
    var order: std.math.Order = .eq;
    if (left.value.state != right.value.state) {
        return if (left.value.state == abi.package_state.installed)
            .lt
        else
            .gt;
    }
    order = std.mem.order(u8, left.repository_name, right.repository_name);
    if (order != .eq) return order;
    if (left.value.has_rpmdb_hnum != right.value.has_rpmdb_hnum) {
        return std.math.order(
            left.value.has_rpmdb_hnum,
            right.value.has_rpmdb_hnum,
        );
    }
    if (left.value.has_rpmdb_hnum != 0) {
        order = std.math.order(
            left.value.rpmdb_hnum,
            right.value.rpmdb_hnum,
        );
        if (order != .eq) return order;
    }
    order = abiBytesOrder(
        left.value.identity.name,
        right.value.identity.name,
    );
    if (order != .eq) return order;
    if (left.value.state == abi.package_state.available) {
        order = std.math.order(
            if (left.value.identity.has_epoch != 0)
                left.value.identity.epoch
            else
                0,
            if (right.value.identity.has_epoch != 0)
                right.value.identity.epoch
            else
                0,
        );
        if (order != .eq) return order;
    }
    inline for (.{ "version", "release", "arch" }) |field| {
        order = abiBytesOrder(
            @field(left.value.identity, field),
            @field(right.value.identity, field),
        );
        if (order != .eq) return order;
    }
    order = std.math.order(left.value.has_source, right.value.has_source);
    if (order != .eq) return order;
    if (left.value.has_source != 0) {
        order = abiBytesOrder(
            left.value.source.checksum.kind,
            right.value.source.checksum.kind,
        );
        if (order != .eq) return order;
        order = abiBytesOrder(
            left.value.source.checksum.value,
            right.value.source.checksum.value,
        );
        if (order != .eq) return order;
        order = std.math.order(
            left.value.source.checksum.is_pkgid,
            right.value.source.checksum.is_pkgid,
        );
        if (order != .eq) return order;
    }
    order = std.math.order(
        left.value.identity.has_epoch,
        right.value.identity.has_epoch,
    );
    if (order != .eq) return order;
    order = std.math.order(
        left.value.identity.epoch,
        right.value.identity.epoch,
    );
    if (order != .eq) return order;
    if (left.value.has_source != 0) {
        order = std.math.order(
            left.value.source.has_location,
            right.value.source.has_location,
        );
        if (order != .eq) return order;
        if (left.value.source.has_location != 0) {
            order = abiBytesOrder(
                left.value.source.location.href,
                right.value.source.location.href,
            );
            if (order != .eq) return order;
            order = abiBytesOrder(
                left.value.source.location.xml_base,
                right.value.source.location.xml_base,
            );
            if (order != .eq) return order;
        }
        order = std.math.order(
            left.value.source.has_size,
            right.value.source.has_size,
        );
        if (order != .eq) return order;
        order = std.math.order(
            left.value.source.size,
            right.value.source.size,
        );
    }
    return order;
}

fn packageMappingsEqual(left: RawPackage, right: RawPackage) bool {
    if (left.value.state != right.value.state or
        !std.mem.eql(u8, left.repository_name, right.repository_name))
    {
        return false;
    }
    if (left.value.state == abi.package_state.installed) {
        return left.value.has_rpmdb_hnum != 0 and
            right.value.has_rpmdb_hnum != 0 and
            left.value.rpmdb_hnum == right.value.rpmdb_hnum;
    }
    if (!abiBytesEqual(
        left.value.identity.name,
        right.value.identity.name,
    ) or
        (if (left.value.identity.has_epoch != 0)
            left.value.identity.epoch
        else
            0) != (if (right.value.identity.has_epoch != 0)
            right.value.identity.epoch
        else
            0) or
        !abiBytesEqual(
            left.value.identity.version,
            right.value.identity.version,
        ) or
        !abiBytesEqual(
            left.value.identity.release,
            right.value.identity.release,
        ) or
        !abiBytesEqual(left.value.identity.arch, right.value.identity.arch) or
        left.value.has_source == 0 or right.value.has_source == 0)
    {
        return false;
    }
    return abiBytesEqual(
        left.value.source.checksum.kind,
        right.value.source.checksum.kind,
    ) and abiBytesEqual(
        left.value.source.checksum.value,
        right.value.source.checksum.value,
    ) and left.value.source.checksum.is_pkgid ==
        right.value.source.checksum.is_pkgid;
}

fn packageTieLess(
    pool: *c.Pool,
    left: c.Id,
    right: c.Id,
) CaptureError!bool {
    const left_solvable = try packageSolvable(pool, left);
    const right_solvable = try packageSolvable(pool, right);
    if (left_solvable.arch != right_solvable.arch) {
        return std.mem.order(
            u8,
            try poolString(pool, left_solvable.arch),
            try poolString(pool, right_solvable.arch),
        ) == .lt;
    }
    return std.mem.order(
        u8,
        try repositoryName(try solvableRepository(
            pool,
            left,
            left_solvable,
        )),
        try repositoryName(try solvableRepository(
            pool,
            right,
            right_solvable,
        )),
    ) == .lt;
}

fn solvidRefLess(refs: []const u32, left: c.Id, right: c.Id) bool {
    return refs[@intCast(left)] < refs[@intCast(right)];
}

fn actionLessThan(
    refs: []const u32,
    left: RawAction,
    right: RawAction,
) bool {
    const left_ref = refs[@intCast(left.target)];
    const right_ref = refs[@intCast(right.target)];
    if (left_ref != right_ref) return left_ref < right_ref;
    if (left.kind != right.kind) return left.kind < right.kind;
    return left.reason < right.reason;
}

fn problemLessThan(_: void, left: abi.Problem, right: abi.Problem) bool {
    return problemOrder(left, right) == .lt;
}

fn problemOrder(left: abi.Problem, right: abi.Problem) std.math.Order {
    var order = std.math.order(left.kind, right.kind);
    if (order != .eq) return order;
    inline for (.{
        .{ "has_package_ref", "package_ref" },
        .{ "has_related_package_ref", "related_package_ref" },
        .{ "has_job_ref", "job_ref" },
    }) |fields| {
        order = std.math.order(
            @field(left, fields[0]),
            @field(right, fields[0]),
        );
        if (order != .eq) return order;
        order = std.math.order(
            @field(left, fields[1]),
            @field(right, fields[1]),
        );
        if (order != .eq) return order;
    }
    order = std.math.order(left.has_capability, right.has_capability);
    if (order != .eq) return order;
    if (left.has_capability != 0) {
        order = capabilityOrder(left.capability, right.capability);
    }
    return order;
}

fn problemsEqual(left: abi.Problem, right: abi.Problem) bool {
    return problemOrder(left, right) == .eq;
}

fn capabilityOrder(
    left: abi.Capability,
    right: abi.Capability,
) std.math.Order {
    var order = abiBytesOrder(left.name, right.name);
    if (order != .eq) return order;
    inline for (.{ "comparison", "has_epoch", "epoch", "has_flags" }) |field| {
        order = std.math.order(@field(left, field), @field(right, field));
        if (order != .eq) return order;
    }
    order = abiBytesOrder(left.flags, right.flags);
    if (order != .eq) return order;
    inline for (.{ "has_version", "has_release" }) |field| {
        order = std.math.order(@field(left, field), @field(right, field));
        if (order != .eq) return order;
    }
    order = abiBytesOrder(left.version, right.version);
    if (order != .eq) return order;
    order = abiBytesOrder(left.release, right.release);
    if (order != .eq) return order;
    order = std.math.order(left.sense, right.sense);
    if (order != .eq) return order;
    return std.math.order(left.pre, right.pre);
}

fn abiBytesOrder(left: abi.Bytes, right: abi.Bytes) std.math.Order {
    const left_bytes = if (left.length == 0)
        ""
    else
        left.data.?[0..left.length];
    const right_bytes = if (right.length == 0)
        ""
    else
        right.data.?[0..right.length];
    return std.mem.order(u8, left_bytes, right_bytes);
}

fn abiBytesEqual(left: abi.Bytes, right: abi.Bytes) bool {
    return abiBytesOrder(left, right) == .eq and
        left.length == right.length;
}
