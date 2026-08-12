//! Produces the transaction-plan capture from a native solver result.
//!
//! Since the native solver is the authority for what tdnf actually installs,
//! the plan has to describe *that* transaction, so this module reads the
//! native result directly.
//!
//! Almost every field maps straight across, because the native model was
//! shaped for it: `abi.job_action` matches `solver_model.JobAction` element
//! for element, and `abi.request_reason` matches `RequestReason`. The
//! alphabetised enums (`action_kind`, `action_reason`, `repository_kind`,
//! `problem_kind`, `compare_op`) get explicit maps below.
//!
//! Ordering is reproduced from the libsolv producer exactly, because the plan
//! digest is part of the published schema and must not move.

const std = @import("std");
const Allocator = std.mem.Allocator;

const abi = @import("transaction_plan_capture_abi");
const error_codes = @import("tdnf_error");
const repomd = @import("repomd");

const metadata = repomd.metadata_model;
const solver_live = repomd.solver_live;
const solver_model = repomd.solver_model;

pub const CaptureError = Allocator.Error || error{
    AmbiguousPackageMapping,
    InvalidInput,
    InvalidTrace,
    JobMismatch,
    UnsupportedResult,
};

pub const Input = struct {
    universe: *const solver_model.Universe,
    jobs: []const solver_model.Job,
    outcome: *const solver_model.Outcome,
    selected: []const solver_model.PackageId,
    /// Available packages an `--exclude`-style filter kept out of the solve.
    hidden: []const solver_model.PackageId = &.{},
    /// Parallel to `jobs`: the libsolv job-queue pair each native job was
    /// built from, which is how a job is tied back to the request that
    /// produced it. `null` marks a job the request layer never queued, such
    /// as the policy jobs tdnf synthesises from `tdnf.conf`.
    job_origins: []const ?u32,
    trace: *const abi.RequestTraceView,
    /// Problems were reported and the caller chose to continue anyway.
    problems_accepted: bool = false,
    /// The caller failed the request for a reason the solver itself did not
    /// raise, so the plan records problems rather than a transaction.
    synthetic_terminal: bool = false,

    /// A request that never reached a solve has no transaction, and the
    /// caller supplies the problem that stopped it.
    const empty_outcome: solver_model.Outcome = .{
        .actions = &.{},
        .problems = &.{},
        .skipped_jobs = &.{},
    };

    /// Projects a native live universe that was never solved onto the capture
    /// inputs. The plan describes the request and the packages it names, and
    /// the caller records why it went no further.
    pub fn fromPrepared(
        prepared: *const solver_live.Prepared,
        job_origins: []const ?u32,
        trace: *const abi.RequestTraceView,
    ) Input {
        return .{
            .universe = prepared.universe,
            .jobs = prepared.jobs,
            .outcome = &empty_outcome,
            .selected = &.{},
            .hidden = prepared.hidden,
            .job_origins = job_origins,
            .trace = trace,
            .synthetic_terminal = true,
        };
    }

    /// Projects an unsatisfiable native live request onto the capture inputs.
    /// It has no transaction, but the refutation supplies solver-native
    /// problems for the jobs that could not be satisfied.
    pub fn fromRefuted(
        prepared: *const solver_live.Prepared,
        jobs: []const solver_model.Job,
        outcome: *const solver_model.Outcome,
        job_origins: []const ?u32,
        trace: *const abi.RequestTraceView,
    ) Input {
        return .{
            .universe = prepared.universe,
            .jobs = jobs,
            .outcome = outcome,
            .selected = &.{},
            .hidden = prepared.hidden,
            .job_origins = job_origins,
            .trace = trace,
        };
    }

    /// Projects a completed native live solve onto the capture inputs.
    pub fn fromSolve(
        solve: *const solver_live.OwnedSolve,
        job_origins: []const ?u32,
        trace: *const abi.RequestTraceView,
    ) Input {
        return .{
            .universe = solve.universe,
            .jobs = solve.jobs,
            .outcome = &solve.solved.result.outcome,
            .selected = solve.solved.result.selected,
            .hidden = solve.hidden,
            .job_origins = job_origins,
            .trace = trace,
        };
    }
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
        else => error_codes.ERROR_TDNF_INVALID_PARAMETER,
    };
}

const RawRepository = struct {
    id: solver_model.RepositoryId,
    value: abi.Repository,
};

const RawPackage = struct {
    id: solver_model.PackageId,
    repository_name: []const u8,
    value: abi.Package,
};

const BuildState = struct {
    arena: Allocator,
    input: Input,
    universe: *const solver_model.Universe,
    outcome: *const solver_model.Outcome,
    trace_requests: []const abi.Request,
    trace_jobs: []const abi.RequestTraceJob,
    /// Binds each libsolv job-queue pair to the trace job that queued it.
    queue_origins: []const abi.RequestTraceQueueOrigin,
    trace_satisfied_selections: []const abi.RequestTraceSatisfiedSelection,
    resolution_status: u32,
    /// One entry per universe package: whether the plan mentions it at all.
    /// Only referenced packages are published, which keeps the plan
    /// proportional to the transaction rather than to the repositories.
    referenced: []bool,

    fn init(arena: Allocator, input: Input) CaptureError!BuildState {
        if (input.job_origins.len != input.jobs.len) {
            return error.JobMismatch;
        }
        const trace = input.trace;
        const requests = try borrowedArray(
            abi.Request,
            trace.requests,
            trace.request_count,
        );
        const jobs = try borrowedArray(
            abi.RequestTraceJob,
            trace.jobs,
            trace.job_count,
        );
        const queue_origins = try borrowedArray(
            abi.RequestTraceQueueOrigin,
            trace.queue_origins,
            trace.queue_origin_count,
        );
        const satisfied = try borrowedArray(
            abi.RequestTraceSatisfiedSelection,
            trace.satisfied_selections,
            trace.satisfied_selection_count,
        );
        const problem_count = input.outcome.problems.len;
        return .{
            .arena = arena,
            .input = input,
            .universe = input.universe,
            .outcome = input.outcome,
            .trace_requests = requests,
            .trace_jobs = jobs,
            .queue_origins = queue_origins,
            .trace_satisfied_selections = satisfied,
            // A native solve that returned at all had every problem it
            // reports tolerated, because an intolerable one fails the solve
            // outright. What it dropped instead shows up as skipped jobs, so
            // those alone are enough to make the plan a partial one.
            .resolution_status = if (input.synthetic_terminal)
                abi.resolution_status.problems
            else if (problem_count == 0 and
                input.outcome.skipped_jobs.len == 0)
                abi.resolution_status.resolved
            else if (input.problems_accepted or
                input.outcome.skipped_jobs.len != 0)
                abi.resolution_status.resolved_with_skips
            else
                abi.resolution_status.problems,
            .referenced = try arena.alloc(bool, input.universe.packages.len),
        };
    }

    fn build(self: *BuildState) CaptureError!abi.Capture {
        @memset(self.referenced, false);
        try self.validateTrace();

        const resolved = self.resolution_status !=
            abi.resolution_status.problems;
        // A plan that records problems records no transaction, so only the
        // inputs and the problems themselves reference packages.
        try self.markJobSelections();
        try self.markProblems();
        if (resolved) {
            try self.markActions();
            try self.markSelected();
        }
        try self.markHidden();

        const repositories = try self.captureRepositories();
        const raw_packages = try self.capturePackages(repositories);
        const package_refs = try self.buildPackageRefMap(raw_packages);
        const requests = try self.captureRequests();
        const jobs = try self.captureJobs(package_refs);
        const actions = if (resolved)
            try self.captureActions(package_refs)
        else
            MaterializedActions{
                .values = &.{},
                .priors = &.{},
                .raw_to_captured = &.{},
            };
        const execution_inputs = if (resolved)
            try self.captureNativeExecutionInputs(
                package_refs,
                actions.raw_to_captured,
            )
        else
            &.{};
        const selected = if (resolved)
            try self.captureSelected(package_refs)
        else
            &.{};
        const hidden = try self.captureHidden(package_refs);
        const skipped = try self.captureSkipped();
        const problems = try self.captureProblems(package_refs);
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
            .native_execution_inputs = optionalPointer(
                abi.ExecutionInput,
                execution_inputs,
            ),
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
            .native_execution_input_count = try countU32(
                execution_inputs.len,
            ),
            .prior_package_ref_count = try countU32(actions.priors.len),
            .selected_package_ref_count = try countU32(selected.len),
            .skipped_job_ref_count = try countU32(skipped.len),
            .hidden_package_ref_count = try countU32(hidden.len),
            .problem_count = try countU32(problems.len),
        };
    }

    fn validateTrace(self: *BuildState) CaptureError!void {
        _ = try flagValue(self.input.trace.allow_erasing);
        for (self.trace_requests) |request| {
            _ = try bytesSlice(request.id);
            if (request.outcome == abi.request_outcome.pending or
                request.outcome > abi.request_outcome.no_candidate)
            {
                return error.InvalidTrace;
            }
            if (try flagValue(request.has_subject)) {
                _ = try bytesSlice(request.subject);
            } else if (!bytesEmpty(request.subject)) {
                return error.InvalidTrace;
            }
            if (request.kind > abi.request_kind.update_all) {
                return error.InvalidTrace;
            }
        }
        for (self.trace_jobs) |job| {
            if (try flagValue(job.has_request_ref) and
                job.request_ref >= self.trace_requests.len)
            {
                return error.InvalidTrace;
            }
        }
        for (self.input.job_origins) |origin| {
            if (origin) |value| {
                if (value >= self.queue_origins.len) return error.JobMismatch;
            }
        }
        for (self.queue_origins) |origin| {
            if (origin.job_ref >= self.trace_jobs.len) {
                return error.InvalidTrace;
            }
        }
    }

    fn markPackage(
        self: *BuildState,
        id: solver_model.PackageId,
    ) CaptureError!void {
        const index: usize = @intFromEnum(id);
        if (index >= self.referenced.len) return error.UnsupportedResult;
        self.referenced[index] = true;
    }

    fn markJobSelections(self: *BuildState) CaptureError!void {
        for (self.input.jobs) |job| {
            switch (job.selection) {
                .package => |id| try self.markPackage(id),
                else => {},
            }
        }
    }

    fn markActions(self: *BuildState) CaptureError!void {
        for (self.outcome.actions) |action| {
            try self.markPackage(action.package);
            for (action.priors) |prior| try self.markPackage(prior);
        }
    }

    fn markSelected(self: *BuildState) CaptureError!void {
        for (self.input.selected) |id| {
            try self.markPackage(id);
        }
    }

    fn markProblems(self: *BuildState) CaptureError!void {
        for (self.outcome.problems) |problem| {
            if (problem.package) |id| try self.markPackage(id);
            if (problem.related_package) |id| try self.markPackage(id);
        }
    }

    fn markHidden(self: *BuildState) CaptureError!void {
        for (self.input.hidden) |id| try self.markPackage(id);
    }

    fn captureRepositories(
        self: *BuildState,
    ) CaptureError![]RawRepository {
        var repositories = std.ArrayList(RawRepository).empty;
        for (self.referenced, 0..) |referenced, index| {
            if (!referenced) continue;
            const package = self.universe.package(
                @enumFromInt(index),
            ) orelse return error.UnsupportedResult;
            var found = false;
            for (repositories.items) |existing| {
                if (existing.id == package.repository) {
                    found = true;
                    break;
                }
            }
            if (found) continue;
            const repository = self.universe.repository(
                package.repository,
            ) orelse return error.UnsupportedResult;
            try repositories.append(self.arena, .{
                .id = package.repository,
                .value = .{
                    .id = try ownBytes(self.arena, repository.name),
                    .priority = try repositoryPriority(repository.*),
                    .kind = repositoryKind(repository.kind),
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
                if (abiBytesOrder(repository.value.id, prior.value.id) ==
                    .eq)
                {
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
        for (self.referenced, 0..) |referenced, index| {
            if (!referenced) continue;
            const id: solver_model.PackageId = @enumFromInt(index);
            const package = self.universe.package(id) orelse
                return error.UnsupportedResult;
            const repository = self.universe.repository(
                package.repository,
            ) orelse return error.UnsupportedResult;
            const repository_ref = findRepositoryRef(
                repositories,
                package.repository,
            ) orelse return error.UnsupportedResult;
            try packages.append(self.arena, .{
                .id = id,
                .repository_name = try self.arena.dupe(u8, repository.name),
                .value = try self.capturePackage(
                    package,
                    repository.kind,
                    repository_ref,
                ),
            });
        }
        std.sort.pdq(RawPackage, packages.items, {}, packageLessThan);
        if (packages.items.len > 1) {
            for (packages.items[1..], 1..) |package, index| {
                if (packageMappingsEqual(packages.items[index - 1], package)) {
                    return error.AmbiguousPackageMapping;
                }
            }
        }
        return packages.toOwnedSlice(self.arena);
    }

    fn capturePackage(
        self: *BuildState,
        package: *const solver_model.UniversePackage,
        kind: solver_model.RepositoryKind,
        repository_ref: u32,
    ) CaptureError!abi.Package {
        const source = package.source;
        const nevra = source.nevra;
        if (nevra.name.len == 0 or nevra.arch.len == 0 or
            nevra.version.len == 0 or nevra.release.len == 0)
        {
            return error.UnsupportedResult;
        }
        var output = abi.Package{
            .identity = .{
                .name = try ownBytes(self.arena, nevra.name),
                .arch = try ownBytes(self.arena, nevra.arch),
                .version = try ownBytes(self.arena, nevra.version),
                .release = try ownBytes(self.arena, nevra.release),
            },
            .repository_ref = repository_ref,
            .state = if (kind == .installed)
                abi.package_state.installed
            else
                abi.package_state.available,
        };
        if (nevra.epoch) |epoch| {
            output.identity.epoch = epoch;
            output.identity.has_epoch = 1;
        }
        if (kind == .installed) {
            const installed = package.installed orelse
                return error.UnsupportedResult;
            if (installed.rpmdb_hnum == 0) return error.UnsupportedResult;
            output.rpmdb_hnum = installed.rpmdb_hnum;
            output.has_rpmdb_hnum = 1;
            return output;
        }

        if (source.checksum.kind.len == 0 or
            source.checksum.value.len == 0)
        {
            return error.UnsupportedResult;
        }
        output.source = .{
            .checksum = .{
                .kind = try ownBytes(self.arena, source.checksum.kind),
                .value = try ownBytes(self.arena, source.checksum.value),
                .is_pkgid = @intFromBool(source.checksum.is_pkgid),
            },
        };
        // A command-line package is named by path, not by a location relative
        // to a repository, so libsolv publishes no location for it either.
        if (kind != .command_line) {
            if (source.location.href.len == 0) {
                return error.UnsupportedResult;
            }
            output.source.location.href = try ownBytes(
                self.arena,
                source.location.href,
            );
            if (source.location.xml_base) |xml_base| {
                output.source.location.xml_base = try ownBytes(
                    self.arena,
                    xml_base,
                );
                output.source.location.has_xml_base = 1;
            }
            output.source.has_location = 1;
        }
        if (source.size.package) |size| {
            output.source.size = size;
            output.source.has_size = 1;
        }
        output.has_source = 1;
        return output;
    }

    fn buildPackageRefMap(
        self: *BuildState,
        packages: []const RawPackage,
    ) CaptureError![]u32 {
        const refs = try self.arena.alloc(u32, self.referenced.len);
        @memset(refs, std.math.maxInt(u32));
        for (packages, 0..) |package, index| {
            refs[@intFromEnum(package.id)] = try countU32(index);
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
                .id = try ownBytes(self.arena, try bytesSlice(request.id)),
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

    /// The published plan numbers jobs by libsolv job-queue pair, and the
    /// trace binds each pair to the request job that queued it. The native
    /// job list is deliberately shaped differently -- tdnf lifts locks,
    /// install-only marks and user-installed marks out into policy jobs,
    /// folds `update-all` into a single global job, and orders installs
    /// ahead of erases -- so keying on the queue keeps the plan describing
    /// what was asked for rather than how the solver encoded it.
    fn captureJobs(
        self: *BuildState,
        package_refs: []const u32,
    ) CaptureError![]abi.Job {
        const output = try self.arena.alloc(abi.Job, self.queue_origins.len);
        for (self.queue_origins, output, 0..) |origin, *destination, pair| {
            const source = self.trace_jobs[origin.job_ref];
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
                    // The trace names a package the way the request layer saw
                    // it; the identity it resolved to is on the native job
                    // built from this queue pair.
                    const package = self.originPackage(
                        try countU32(pair),
                    ) orelse return error.JobMismatch;
                    destination.selection_package_ref = try packageRef(
                        package_refs,
                        package,
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
                else => return error.InvalidTrace,
            }
            if (try flagValue(source.has_request_ref)) {
                destination.request_ref = source.request_ref;
                destination.has_request_ref = 1;
            }
        }
        return output;
    }

    /// The package identity the native solver resolved for a queue pair. An
    /// erase naming a NEVRA the rpmdb holds more than once expands into one
    /// native job per row; they share the identity the plan reports.
    fn originPackage(
        self: *BuildState,
        pair: u32,
    ) ?solver_model.PackageId {
        for (self.input.jobs, self.input.job_origins) |job, origin| {
            const value = origin orelse continue;
            if (value != pair) continue;
            switch (job.selection) {
                .package => |id| return id,
                else => {},
            }
        }
        return null;
    }

    fn captureCapability(
        self: *BuildState,
        relation: metadata.Relation,
    ) CaptureError!abi.Capability {
        if (relation.name.len == 0) return error.UnsupportedResult;
        var output = abi.Capability{
            .name = try ownBytes(self.arena, relation.name),
            .comparison = compareOp(relation.comparison),
            .sense = relation.sense,
            .pre = @intFromBool(relation.pre),
        };
        if (relation.flags) |flags| {
            output.flags = try ownBytes(self.arena, flags);
            output.has_flags = 1;
        }
        if (relation.epoch) |epoch| {
            output.epoch = epoch;
            output.has_epoch = 1;
        }
        if (relation.version) |version| {
            output.version = try ownBytes(self.arena, version);
            output.has_version = 1;
        }
        if (relation.release) |release| {
            output.release = try ownBytes(self.arena, release);
            output.has_release = 1;
        }
        return output;
    }

    const MaterializedActions = struct {
        values: []abi.Action,
        priors: []u32,
        raw_to_captured: []u32,
    };

    fn captureActions(
        self: *BuildState,
        package_refs: []const u32,
    ) CaptureError!MaterializedActions {
        const actions = self.outcome.actions;
        const order = try self.arena.alloc(u32, actions.len);
        for (order, 0..) |*slot, index| slot.* = try countU32(index);
        std.sort.pdq(u32, order, ActionSort{
            .actions = actions,
            .package_refs = package_refs,
        }, actionOrderLessThan);

        var prior_count: usize = 0;
        for (actions) |action| {
            prior_count = std.math.add(
                usize,
                prior_count,
                action.priors.len,
            ) catch return error.UnsupportedResult;
        }
        const values = try self.arena.alloc(abi.Action, actions.len);
        const raw_to_captured = try self.arena.alloc(u32, actions.len);
        const priors = try self.arena.alloc(u32, prior_count);
        var prior_offset: usize = 0;
        for (order, values, 0..) |source_index, *destination, captured_index| {
            const action = actions[source_index];
            raw_to_captured[source_index] = try countU32(captured_index);
            destination.* = .{
                .target_package_ref = try packageRef(
                    package_refs,
                    action.package,
                ),
                .kind = actionKind(action.kind),
                .reason = actionReason(action.reason),
                .prior_offset = try countU32(prior_offset),
                .prior_count = try countU32(action.priors.len),
            };
            // `requested_by` indexes the native job list, but the published
            // plan numbers jobs by queue pair, so translate through the
            // origins. A native policy job was never queued and leaves the
            // action unattributed.
            if (action.requested_by) |job_id| {
                if (try self.queuePairRef(job_id)) |pair| {
                    destination.requested_job_ref = pair;
                    destination.has_requested_job_ref = 1;
                }
            }
            const sorted_priors = try self.arena.dupe(
                solver_model.PackageId,
                action.priors,
            );
            std.sort.pdq(
                solver_model.PackageId,
                sorted_priors,
                package_refs,
                priorRefLessThan,
            );
            for (sorted_priors) |prior| {
                priors[prior_offset] = try packageRef(package_refs, prior);
                prior_offset += 1;
            }
        }
        return .{
            .values = values,
            .priors = priors,
            .raw_to_captured = raw_to_captured,
        };
    }

    const ExecutionCandidate = struct {
        action_index: usize,
        operation: u32,
        package: solver_model.PackageId,
        requested_by: ?solver_model.JobId,
    };

    fn captureNativeExecutionInputs(
        self: *BuildState,
        package_refs: []const u32,
        raw_to_captured: []const u32,
    ) CaptureError![]abi.ExecutionInput {
        var output = std.ArrayList(abi.ExecutionInput).empty;
        var erased = std.ArrayList(solver_model.PackageId).empty;

        try self.appendExecutionBucket(
            &output,
            &erased,
            package_refs,
            raw_to_captured,
            &.{ .install, .obsolete },
            false,
            abi.execution_operation.install,
            false,
        );
        try self.appendExecutionBucket(
            &output,
            &erased,
            package_refs,
            raw_to_captured,
            &.{.reinstall},
            false,
            abi.execution_operation.reinstall,
            false,
        );
        try self.appendExecutionBucket(
            &output,
            &erased,
            package_refs,
            raw_to_captured,
            &.{.upgrade},
            false,
            abi.execution_operation.upgrade,
            false,
        );
        try self.appendExecutionBucket(
            &output,
            &erased,
            package_refs,
            raw_to_captured,
            &.{ .erase, .obsolete },
            true,
            abi.execution_operation.erase,
            true,
        );
        // The legacy executor receives obsoleted priors in a second bucket,
        // but recordItem deduplicates erases by rpmdb hnum.
        try self.appendExecutionBucket(
            &output,
            &erased,
            package_refs,
            raw_to_captured,
            &.{.obsolete},
            true,
            abi.execution_operation.erase,
            true,
        );
        try self.appendExecutionBucket(
            &output,
            &erased,
            package_refs,
            raw_to_captured,
            &.{.downgrade},
            false,
            abi.execution_operation.install,
            false,
        );
        try self.appendExecutionBucket(
            &output,
            &erased,
            package_refs,
            raw_to_captured,
            &.{.downgrade},
            true,
            abi.execution_operation.erase,
            true,
        );
        return output.toOwnedSlice(self.arena);
    }

    fn appendExecutionBucket(
        self: *BuildState,
        output: *std.ArrayList(abi.ExecutionInput),
        erased: *std.ArrayList(solver_model.PackageId),
        package_refs: []const u32,
        raw_to_captured: []const u32,
        kinds: []const solver_model.ActionKind,
        use_prior: bool,
        operation: u32,
        dedupe_erase: bool,
    ) CaptureError!void {
        var candidates = std.ArrayList(ExecutionCandidate).empty;
        for (self.outcome.actions, 0..) |action, action_index| {
            if (!containsActionKind(kinds, action.kind)) continue;
            const package = if (use_prior and action.kind != .erase)
                if (action.priors.len == 0) return error.UnsupportedResult else action.priors[0]
            else
                action.package;
            try candidates.append(self.arena, .{
                .action_index = action_index,
                .operation = operation,
                .package = package,
                .requested_by = action.requested_by,
            });
        }
        std.sort.pdq(
            ExecutionCandidate,
            candidates.items,
            self.universe,
            executionCandidateLessThan,
        );
        var index = candidates.items.len;
        while (index > 0) {
            index -= 1;
            const candidate = candidates.items[index];
            if (dedupe_erase and containsPackageId(erased.items, candidate.package)) {
                continue;
            }
            if (dedupe_erase) try erased.append(self.arena, candidate.package);
            try output.append(self.arena, .{
                .action_ref = raw_to_captured[candidate.action_index],
                .operation = candidate.operation,
                .package_ref = try packageRef(package_refs, candidate.package),
            });
        }
    }

    fn capturePackageRefs(
        self: *BuildState,
        raw: []const solver_model.PackageId,
        package_refs: []const u32,
    ) CaptureError![]u32 {
        const output = try self.arena.alloc(u32, raw.len);
        for (raw, output) |id, *destination| {
            destination.* = try packageRef(package_refs, id);
        }
        std.mem.sort(u32, output, {}, std.sort.asc(u32));
        if (output.len > 1) {
            for (output[1..], 1..) |value, index| {
                if (output[index - 1] == value) {
                    return error.AmbiguousPackageMapping;
                }
            }
        }
        return output;
    }

    fn captureSelected(
        self: *BuildState,
        package_refs: []const u32,
    ) CaptureError![]u32 {
        return self.capturePackageRefs(
            self.input.selected,
            package_refs,
        );
    }

    /// Translates a native job id into the queue pair the published plan
    /// numbers jobs by. A policy job tdnf synthesised was never queued, so it
    /// has no published number.
    fn queuePairRef(
        self: *BuildState,
        job_id: solver_model.JobId,
    ) CaptureError!?u32 {
        const job_ref: usize = @intFromEnum(job_id);
        if (job_ref >= self.input.job_origins.len) {
            return error.UnsupportedResult;
        }
        return self.input.job_origins[job_ref];
    }

    fn captureHidden(
        self: *BuildState,
        package_refs: []const u32,
    ) CaptureError![]u32 {
        return self.capturePackageRefs(self.input.hidden, package_refs);
    }

    fn captureSkipped(self: *BuildState) CaptureError![]u32 {
        const skipped = self.outcome.skipped_jobs;
        var values = try std.ArrayList(u32).initCapacity(
            self.arena,
            skipped.len,
        );
        for (skipped) |job_id| {
            // A skipped policy job is invisible to the request layer, so it
            // has nothing to report against.
            const pair = try self.queuePairRef(job_id) orelse continue;
            values.appendAssumeCapacity(pair);
        }
        const output = values.items;
        std.mem.sort(u32, output, {}, std.sort.asc(u32));
        if (output.len > 1) {
            for (output[1..], 1..) |value, index| {
                if (output[index - 1] == value) return error.JobMismatch;
            }
        }
        return output;
    }

    fn captureProblems(
        self: *BuildState,
        package_refs: []const u32,
    ) CaptureError![]abi.Problem {
        var output = std.ArrayList(abi.Problem).empty;
        for (self.outcome.problems) |problem| {
            var value = abi.Problem{
                .kind = problemKind(problem.kind),
                .count = problem.count,
            };
            if (problem.capability) |capability| {
                value.capability = try self.captureCapability(capability);
                value.has_capability = 1;
            }
            if (problem.job) |job_id| {
                if (try self.queuePairRef(job_id)) |pair| {
                    value.job_ref = pair;
                    value.has_job_ref = 1;
                }
            }
            if (problem.package) |id| {
                value.package_ref = try packageRef(package_refs, id);
                value.has_package_ref = 1;
            }
            if (problem.related_package) |id| {
                value.related_package_ref = try packageRef(package_refs, id);
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
};

fn jobAction(action: solver_model.JobAction) u32 {
    return switch (action) {
        .install => abi.job_action.install,
        .erase => abi.job_action.erase,
        .update => abi.job_action.update,
        .downgrade => abi.job_action.downgrade,
        .dist_sync => abi.job_action.dist_sync,
        .reinstall => abi.job_action.reinstall,
        .lock => abi.job_action.lock,
        .multiversion => abi.job_action.multiversion,
        .user_installed => abi.job_action.user_installed,
        .allow_uninstall => abi.job_action.allow_uninstall,
    };
}

fn requestReason(reason: solver_model.RequestReason) u32 {
    return switch (reason) {
        .user => abi.request_reason.user,
        .dependency => abi.request_reason.dependency,
        .weak_dependency => abi.request_reason.weak_dependency,
        .cleanup => abi.request_reason.cleanup,
        .installonly_limit => abi.request_reason.installonly_limit,
        .policy => abi.request_reason.policy,
    };
}

fn actionKind(kind: solver_model.ActionKind) u32 {
    return switch (kind) {
        .install => abi.action_kind.install,
        .upgrade => abi.action_kind.upgrade,
        .downgrade => abi.action_kind.downgrade,
        .erase => abi.action_kind.erase,
        .reinstall => abi.action_kind.reinstall,
        .obsolete => abi.action_kind.obsolete,
    };
}

fn actionReason(reason: solver_model.TransactionReason) u32 {
    return switch (reason) {
        .user => abi.action_reason.user,
        .dependency => abi.action_reason.dependency,
        .weak_dependency => abi.action_reason.weak_dependency,
        .cleanup => abi.action_reason.cleanup,
        .obsoletes => abi.action_reason.obsoletes,
        .installonly_limit => abi.action_reason.installonly_limit,
        .policy => abi.action_reason.policy,
    };
}

fn problemKind(kind: solver_model.ProblemKind) u32 {
    return switch (kind) {
        .unsatisfied_requirement => abi.problem_kind.unsatisfied_requirement,
        .conflict => abi.problem_kind.conflict,
        .same_name => abi.problem_kind.same_name,
        .obsoletes => abi.problem_kind.obsoletes,
        .no_candidate => abi.problem_kind.no_candidate,
        .not_installable => abi.problem_kind.not_installable,
        .protected_package => abi.problem_kind.protected_package,
        .installonly_limit => abi.problem_kind.installonly_limit,
    };
}

fn repositoryKind(kind: solver_model.RepositoryKind) u32 {
    return switch (kind) {
        .available => abi.repository_kind.available,
        .installed => abi.repository_kind.installed,
        .command_line => abi.repository_kind.command_line,
    };
}

fn repositoryPriority(
    repository: solver_model.UniverseRepository,
) CaptureError!i32 {
    if (repository.priority == std.math.minInt(i32)) {
        return error.UnsupportedResult;
    }
    return switch (repository.kind) {
        .available => repository.priority,
        .installed, .command_line => 0,
    };
}

fn compareOp(comparison: metadata.CompareOp) u32 {
    return switch (comparison) {
        .none => abi.compare_op.none,
        .eq => abi.compare_op.eq,
        .lt => abi.compare_op.lt,
        .le => abi.compare_op.le,
        .gt => abi.compare_op.gt,
        .ge => abi.compare_op.ge,
    };
}

fn findRepositoryRef(
    repositories: []const RawRepository,
    id: solver_model.RepositoryId,
) ?u32 {
    for (repositories, 0..) |repository, index| {
        if (repository.id == id) return @intCast(index);
    }
    return null;
}

fn packageRef(
    refs: []const u32,
    id: solver_model.PackageId,
) CaptureError!u32 {
    const index: usize = @intFromEnum(id);
    if (index >= refs.len) return error.UnsupportedResult;
    const ref = refs[index];
    if (ref == std.math.maxInt(u32)) return error.UnsupportedResult;
    return ref;
}

fn priorRefLessThan(
    refs: []const u32,
    left: solver_model.PackageId,
    right: solver_model.PackageId,
) bool {
    return refs[@intFromEnum(left)] < refs[@intFromEnum(right)];
}

const ActionSort = struct {
    actions: []const solver_model.Action,
    package_refs: []const u32,
};

fn containsActionKind(
    kinds: []const solver_model.ActionKind,
    candidate: solver_model.ActionKind,
) bool {
    for (kinds) |kind| if (kind == candidate) return true;
    return false;
}

fn containsPackageId(
    packages: []const solver_model.PackageId,
    candidate: solver_model.PackageId,
) bool {
    for (packages) |package| if (package == candidate) return true;
    return false;
}

fn executionCandidateLessThan(
    universe: *const solver_model.Universe,
    left: BuildState.ExecutionCandidate,
    right: BuildState.ExecutionCandidate,
) bool {
    if ((left.requested_by == null) != (right.requested_by == null)) {
        return left.requested_by == null;
    }
    if (left.requested_by) |left_job| {
        const right_job = right.requested_by.?;
        if (left_job != right_job) {
            return @intFromEnum(left_job) < @intFromEnum(right_job);
        }
    }
    const left_package = universe.package(left.package).?;
    const right_package = universe.package(right.package).?;
    const left_nevra = left_package.source.nevra;
    const right_nevra = right_package.source.nevra;
    inline for (.{
        .{ left_nevra.name, right_nevra.name },
        .{ left_nevra.arch, right_nevra.arch },
    }) |pair| {
        const order = std.mem.order(u8, pair[0], pair[1]);
        if (order != .eq) return order == .lt;
    }
    const left_epoch = left_nevra.epoch orelse 0;
    const right_epoch = right_nevra.epoch orelse 0;
    if (left_epoch != right_epoch) return left_epoch < right_epoch;
    inline for (.{
        .{ left_nevra.version, right_nevra.version },
        .{ left_nevra.release, right_nevra.release },
    }) |pair| {
        const order = std.mem.order(u8, pair[0], pair[1]);
        if (order != .eq) return order == .lt;
    }
    return @intFromEnum(left.package) < @intFromEnum(right.package);
}

fn actionOrderLessThan(context: ActionSort, left: u32, right: u32) bool {
    const a = context.actions[left];
    const b = context.actions[right];
    const left_ref = context.package_refs[@intFromEnum(a.package)];
    const right_ref = context.package_refs[@intFromEnum(b.package)];
    if (left_ref != right_ref) return left_ref < right_ref;
    const left_kind = actionKind(a.kind);
    const right_kind = actionKind(b.kind);
    if (left_kind != right_kind) return left_kind < right_kind;
    return actionReason(a.reason) < actionReason(b.reason);
}

fn repositoryLessThan(
    _: void,
    left: RawRepository,
    right: RawRepository,
) bool {
    if (left.value.kind != right.value.kind) {
        return left.value.kind < right.value.kind;
    }
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
            effectiveEpoch(left.value.identity),
            effectiveEpoch(right.value.identity),
        );
        if (order != .eq) return order;
        order = abiBytesOrder(
            left.value.identity.version,
            right.value.identity.version,
        );
        if (order != .eq) return order;
        order = abiBytesOrder(
            left.value.identity.release,
            right.value.identity.release,
        );
        if (order != .eq) return order;
        order = abiBytesOrder(
            left.value.identity.arch,
            right.value.identity.arch,
        );
        if (order != .eq) return order;
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
    }
    return order;
}

fn effectiveEpoch(identity: abi.PackageIdentity) u32 {
    return if (identity.has_epoch != 0) identity.epoch else 0;
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
        effectiveEpoch(left.value.identity) !=
            effectiveEpoch(right.value.identity) or
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
    return std.mem.order(u8, bytesOrEmpty(left), bytesOrEmpty(right));
}

fn abiBytesEqual(left: abi.Bytes, right: abi.Bytes) bool {
    return abiBytesOrder(left, right) == .eq;
}

fn bytesOrEmpty(value: abi.Bytes) []const u8 {
    return if (value.length == 0) "" else value.data.?[0..value.length];
}

fn bytesEmpty(value: abi.Bytes) bool {
    return value.length == 0;
}

fn bytesSlice(value: abi.Bytes) CaptureError![]const u8 {
    if (value.length == 0) return "";
    const data = value.data orelse return error.InvalidTrace;
    return data[0..value.length];
}

fn borrowedArray(
    comptime T: type,
    pointer: ?[*]const T,
    count: u32,
) CaptureError![]const T {
    if (count == 0) return &.{};
    const values = pointer orelse return error.InvalidTrace;
    return values[0..count];
}

fn flag(flags: u32, mask: u32) u32 {
    return @intFromBool(flags & mask != 0);
}

/// Copies a capability the request layer recorded, rejecting a trace whose
/// optional parts disagree with their presence flags.
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
        output.flags = try ownBytes(allocator, try bytesSlice(source.flags));
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

const testing = std.testing;

fn testPackage(
    name: []const u8,
    version: []const u8,
    arch: []const u8,
) metadata.Package {
    return .{
        .pkg_id = name,
        .nevra = .{
            .name = name,
            .version = version,
            .release = "1",
            .arch = arch,
        },
        .checksum = .{
            .kind = "sha256",
            .value = name,
            .is_pkgid = true,
        },
        .location = .{ .href = name },
        .size = .{ .package = 1024 },
    };
}

/// `Universe` stores the allocator it was built with and frees through it in
/// `deinit`, so that allocator must not point at anything this function owns:
/// an `ArenaAllocator` held by value here would be copied into the returned
/// `Harness`, leaving `universe.allocator.ptr` aimed at the dead stack frame.
/// `Universe` allocates exactly what it frees, so hand it the test allocator
/// directly -- that removes the escape and gets leak checking on `deinit`.
const Harness = struct {
    universe: solver_model.Universe,

    fn deinit(self: *Harness) void {
        self.universe.deinit();
    }
};

fn buildUniverse(
    inputs: []const solver_model.RepositoryInput,
) !Harness {
    return .{
        .universe = try solver_model.Universe.init(testing.allocator, inputs),
    };
}

fn emptyTrace() abi.RequestTraceView {
    return .{};
}

const one_install_requests = [_]abi.Request{
    .{
        .id = .{ .data = "request-0".ptr, .length = "request-0".len },
        .subject = .{ .data = "wanted".ptr, .length = "wanted".len },
        .kind = abi.request_kind.install,
        .has_subject = 1,
        .outcome = abi.request_outcome.satisfied,
    },
};

const one_install_jobs = [_]abi.RequestTraceJob{
    .{
        .action = abi.job_action.install,
        .selection_kind = abi.selection_kind.package,
        .reason = abi.request_reason.user,
        .request_ref = 0,
        .has_request_ref = 1,
    },
};

const one_install_queue_origins = [_]abi.RequestTraceQueueOrigin{
    .{ .queue_pair_index = 0, .job_ref = 0, .request_ref = 0, .has_request_ref = 1 },
};

/// A trace for a single `install` request that queued exactly one job.
fn oneInstallTrace() abi.RequestTraceView {
    return .{
        .requests = &one_install_requests,
        .jobs = &one_install_jobs,
        .queue_origins = &one_install_queue_origins,
        .request_count = one_install_requests.len,
        .job_count = one_install_jobs.len,
        .queue_origin_count = one_install_queue_origins.len,
    };
}

const one_name_requests = [_]abi.Request{
    .{
        .id = .{ .data = "request-0".ptr, .length = "request-0".len },
        .subject = .{ .data = "broken".ptr, .length = "broken".len },
        .kind = abi.request_kind.install,
        .has_subject = 1,
        .outcome = abi.request_outcome.no_candidate,
    },
};

const one_name_jobs = [_]abi.RequestTraceJob{
    .{
        .action = abi.job_action.install,
        .selection_kind = abi.selection_kind.name,
        .selection_value = .{ .data = "broken".ptr, .length = "broken".len },
        .reason = abi.request_reason.user,
        .request_ref = 0,
        .has_request_ref = 1,
    },
};

const one_name_queue_origins = [_]abi.RequestTraceQueueOrigin{
    .{ .queue_pair_index = 0, .job_ref = 0, .request_ref = 0, .has_request_ref = 1 },
};

/// A trace for a single `install` request that resolved to a bare name.
fn oneNameTrace() abi.RequestTraceView {
    return .{
        .requests = &one_name_requests,
        .jobs = &one_name_jobs,
        .queue_origins = &one_name_queue_origins,
        .request_count = one_name_requests.len,
        .job_count = one_name_jobs.len,
        .queue_origin_count = one_name_queue_origins.len,
    };
}

const install_pair_requests = [_]abi.Request{
    .{
        .id = .{ .data = "request-0".ptr, .length = "request-0".len },
        .subject = .{ .data = "wanted".ptr, .length = "wanted".len },
        .kind = abi.request_kind.install,
        .has_subject = 1,
        .outcome = abi.request_outcome.satisfied,
    },
    .{
        .id = .{ .data = "request-1".ptr, .length = "request-1".len },
        .subject = .{ .data = "absent".ptr, .length = "absent".len },
        .kind = abi.request_kind.install,
        .has_subject = 1,
        .outcome = abi.request_outcome.no_candidate,
    },
};

const install_pair_jobs = [_]abi.RequestTraceJob{
    .{
        .action = abi.job_action.install,
        .selection_kind = abi.selection_kind.package,
        .reason = abi.request_reason.user,
        .request_ref = 0,
        .has_request_ref = 1,
    },
    .{
        .action = abi.job_action.install,
        .selection_kind = abi.selection_kind.name,
        .selection_value = .{ .data = "absent".ptr, .length = "absent".len },
        .reason = abi.request_reason.user,
        .request_ref = 1,
        .has_request_ref = 1,
    },
};

const install_pair_queue_origins = [_]abi.RequestTraceQueueOrigin{
    .{ .queue_pair_index = 0, .job_ref = 0, .request_ref = 0, .has_request_ref = 1 },
    .{ .queue_pair_index = 1, .job_ref = 1, .request_ref = 1, .has_request_ref = 1 },
};

/// A trace for two `install` requests, one resolved to a package and one left
/// as a bare name the repositories do not provide.
fn installPairTrace() abi.RequestTraceView {
    return .{
        .requests = &install_pair_requests,
        .jobs = &install_pair_jobs,
        .queue_origins = &install_pair_queue_origins,
        .request_count = install_pair_requests.len,
        .job_count = install_pair_jobs.len,
        .queue_origin_count = install_pair_queue_origins.len,
    };
}

test "a capture publishes only the packages the transaction references" {
    var installed = [_]metadata.Package{
        testPackage("kept", "1", "x86_64"),
    };
    var available = [_]metadata.Package{
        testPackage("wanted", "2", "x86_64"),
        testPackage("untouched", "3", "x86_64"),
    };
    const installed_model = metadata.RepositoryModel{ .packages = &installed };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    const installed_states = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 7, .reason = .user },
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@System",
            .model = &installed_model,
            .kind = .installed,
            .installed_states = &installed_states,
        },
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const wanted: solver_model.PackageId = @enumFromInt(1);
    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .{ .package = wanted } },
    };
    const actions = [_]solver_model.Action{
        .{
            .package = wanted,
            .kind = .install,
            .reason = .user,
            .requested_by = @enumFromInt(0),
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const selected = [_]solver_model.PackageId{wanted};
    const origins = [_]?u32{0};
    const trace = oneInstallTrace();

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &origins,
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(
        abi.resolution_status.resolved,
        facts.environment.resolution_status,
    );
    // "untouched" is never named, so it stays out of the plan entirely.
    try testing.expectEqual(@as(u32, 1), facts.package_count);
    try testing.expectEqual(@as(u32, 1), facts.repository_count);
    try testing.expectEqualStrings(
        "base",
        bytesOrEmpty(facts.repositories.?[0].id),
    );
    try testing.expectEqual(
        abi.repository_kind.available,
        facts.repositories.?[0].kind,
    );
    const package = facts.packages.?[0];
    try testing.expectEqualStrings("wanted", bytesOrEmpty(package.identity.name));
    try testing.expectEqual(abi.package_state.available, package.state);
    try testing.expectEqual(@as(u32, 1), package.has_source);
    try testing.expectEqualStrings(
        "wanted",
        bytesOrEmpty(package.source.location.href),
    );
    try testing.expectEqual(@as(u64, 1024), package.source.size);
    try testing.expectEqual(@as(u32, 1), facts.action_count);
    try testing.expectEqual(abi.action_kind.install, facts.actions.?[0].kind);
    try testing.expectEqual(abi.action_reason.user, facts.actions.?[0].reason);
    try testing.expectEqual(@as(u32, 1), facts.native_execution_input_count);
    try testing.expectEqual(
        abi.execution_operation.install,
        facts.native_execution_inputs.?[0].operation,
    );
    try testing.expectEqual(
        facts.actions.?[0].target_package_ref,
        facts.native_execution_inputs.?[0].package_ref,
    );
    try testing.expectEqual(
        @as(u32, 1),
        facts.actions.?[0].has_requested_job_ref,
    );
    try testing.expectEqual(@as(u32, 1), facts.selected_package_ref_count);
    try testing.expectEqual(@as(u32, 1), facts.job_count);
    try testing.expectEqual(abi.job_action.install, facts.jobs.?[0].action);
    try testing.expectEqual(
        abi.selection_kind.package,
        facts.jobs.?[0].selection_kind,
    );
}

test "installed packages sort ahead of available ones and carry their rpmdb row" {
    var installed = [_]metadata.Package{
        testPackage("zzz-installed", "1", "x86_64"),
    };
    var available = [_]metadata.Package{
        testPackage("aaa-available", "2", "x86_64"),
    };
    const installed_model = metadata.RepositoryModel{ .packages = &installed };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    const installed_states = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 42, .reason = .user },
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@System",
            .model = &installed_model,
            .kind = .installed,
            .installed_states = &installed_states,
        },
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const old: solver_model.PackageId = @enumFromInt(0);
    const new: solver_model.PackageId = @enumFromInt(1);
    const priors = [_]solver_model.PackageId{old};
    const actions = [_]solver_model.Action{
        .{
            .package = new,
            .priors = &priors,
            .kind = .upgrade,
            .reason = .user,
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const selected = [_]solver_model.PackageId{new};
    const trace = emptyTrace();

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &.{},
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &.{},
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(@as(u32, 2), facts.package_count);
    // Installed first regardless of name, matching the published ordering.
    try testing.expectEqual(
        abi.package_state.installed,
        facts.packages.?[0].state,
    );
    try testing.expectEqual(@as(u32, 42), facts.packages.?[0].rpmdb_hnum);
    try testing.expectEqual(@as(u32, 1), facts.packages.?[0].has_rpmdb_hnum);
    try testing.expectEqual(@as(u32, 0), facts.packages.?[0].has_source);
    try testing.expectEqual(
        abi.package_state.available,
        facts.packages.?[1].state,
    );
    // Repositories sort by kind, and `installed` sorts after `available`.
    try testing.expectEqual(@as(u32, 2), facts.repository_count);
    try testing.expectEqual(
        abi.repository_kind.available,
        facts.repositories.?[0].kind,
    );
    try testing.expectEqual(@as(u32, 1), facts.prior_package_ref_count);
    try testing.expectEqual(@as(u32, 0), facts.prior_package_refs.?[0]);
    try testing.expectEqual(abi.action_kind.upgrade, facts.actions.?[0].kind);
}

test "a problem transaction publishes problems and no actions" {
    var available = [_]metadata.Package{
        testPackage("broken", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const broken: solver_model.PackageId = @enumFromInt(0);
    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .{ .name = "broken" } },
    };
    const problems = [_]solver_model.Problem{
        .{
            .kind = .unsatisfied_requirement,
            .package = broken,
            .capability = .{ .name = "missing-capability" },
            .job = @enumFromInt(0),
            .count = 1,
        },
    };
    const actions = [_]solver_model.Action{
        .{ .package = broken, .kind = .install, .reason = .user },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &problems,
        .skipped_jobs = &.{},
    };
    const origins = [_]?u32{0};
    const trace = oneNameTrace();

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &.{},
        .job_origins = &origins,
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(
        abi.resolution_status.problems,
        facts.environment.resolution_status,
    );
    try testing.expectEqual(@as(u32, 0), facts.action_count);
    try testing.expectEqual(@as(u32, 0), facts.selected_package_ref_count);
    try testing.expectEqual(@as(u32, 1), facts.problem_count);
    const problem = facts.problems.?[0];
    try testing.expectEqual(
        abi.problem_kind.unsatisfied_requirement,
        problem.kind,
    );
    try testing.expectEqual(@as(u32, 1), problem.has_capability);
    try testing.expectEqualStrings(
        "missing-capability",
        bytesOrEmpty(problem.capability.name),
    );
    try testing.expectEqual(@as(u32, 1), problem.has_job_ref);
    try testing.expectEqual(
        abi.selection_kind.name,
        facts.jobs.?[0].selection_kind,
    );
    try testing.expectEqualStrings(
        "broken",
        bytesOrEmpty(facts.jobs.?[0].selection_value),
    );
}

test "accepted problems resolve with skips and keep the transaction" {
    var available = [_]metadata.Package{
        testPackage("wanted", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const wanted: solver_model.PackageId = @enumFromInt(0);
    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .{ .package = wanted } },
        .{ .action = .install, .selection = .{ .name = "absent" } },
    };
    const problems = [_]solver_model.Problem{
        .{ .kind = .no_candidate, .job = @enumFromInt(1), .count = 1 },
    };
    const actions = [_]solver_model.Action{
        .{ .package = wanted, .kind = .install, .reason = .user },
    };
    const skipped = [_]solver_model.JobId{@enumFromInt(1)};
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &problems,
        .skipped_jobs = &skipped,
    };
    const selected = [_]solver_model.PackageId{wanted};
    const origins = [_]?u32{ 0, 1 };
    const trace = installPairTrace();

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &origins,
        .trace = &trace,
        .problems_accepted = true,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(
        abi.resolution_status.resolved_with_skips,
        facts.environment.resolution_status,
    );
    try testing.expectEqual(@as(u32, 1), facts.action_count);
    try testing.expectEqual(@as(u32, 1), facts.skipped_job_ref_count);
    try testing.expectEqual(@as(u32, 1), facts.skipped_job_refs.?[0]);
}

test "a solve that only skipped a job still records a partial plan" {
    var available = [_]metadata.Package{
        testPackage("wanted", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const wanted: solver_model.PackageId = @enumFromInt(0);
    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .{ .package = wanted } },
        .{ .action = .install, .selection = .{ .name = "absent" } },
    };
    const actions = [_]solver_model.Action{
        .{ .package = wanted, .kind = .install, .reason = .user },
    };
    const skipped = [_]solver_model.JobId{@enumFromInt(1)};
    // `--skip-broken` drops the job without raising a problem for it.
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &skipped,
    };
    const selected = [_]solver_model.PackageId{wanted};
    const origins = [_]?u32{ 0, 1 };
    const trace = installPairTrace();

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &origins,
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(
        abi.resolution_status.resolved_with_skips,
        facts.environment.resolution_status,
    );
    // The transaction is still published: the plan is partial, not absent.
    try testing.expectEqual(@as(u32, 1), facts.action_count);
    try testing.expectEqual(@as(u32, 1), facts.skipped_job_ref_count);
}

test "a request that never solved publishes its jobs and no transaction" {
    var available = [_]metadata.Package{
        testPackage("wanted", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const wanted: solver_model.PackageId = @enumFromInt(0);
    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .{ .package = wanted } },
    };
    const origins = [_]?u32{0};
    const trace = oneInstallTrace();
    var prepared = solver_live.Prepared{
        .arena_state = undefined,
        .universe = &harness.universe,
        .jobs = &jobs,
        .hidden = &.{},
        .job_origins = &origins,
        .visibility = undefined,
        .native_arch = "x86_64",
    };

    const owner = try create(
        testing.allocator,
        .fromPrepared(&prepared, prepared.job_origins, &trace),
    );
    defer owner.destroy();

    const facts = owner.view();
    // The package the request names is still published, which is what the
    // problem the caller records has to point at.
    try testing.expectEqual(@as(u32, 1), facts.job_count);
    try testing.expectEqual(@as(u32, 1), facts.package_count);
    try testing.expectEqual(@as(u32, 0), facts.action_count);
    try testing.expectEqual(@as(u32, 0), facts.skipped_job_ref_count);
    try testing.expectEqual(
        abi.resolution_status.problems,
        facts.environment.resolution_status,
    );
}

test "a refuted native request publishes derived problems and no transaction" {
    var available = [_]metadata.Package{
        testPackage("broken", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const broken: solver_model.PackageId = @enumFromInt(0);
    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .{ .package = broken } },
    };
    const origins = [_]?u32{0};
    const problems = [_]solver_model.Problem{
        .{
            .kind = .unsatisfied_requirement,
            .package = broken,
            .capability = .{ .name = "missing-capability" },
            .job = @enumFromInt(0),
            .count = 1,
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &.{},
        .problems = &problems,
        .skipped_jobs = &.{},
    };
    const trace = oneInstallTrace();
    var prepared = solver_live.Prepared{
        .arena_state = undefined,
        .universe = &harness.universe,
        .jobs = &jobs,
        .hidden = &.{},
        .job_origins = &origins,
        .visibility = undefined,
        .native_arch = "x86_64",
    };

    const owner = try create(
        testing.allocator,
        .fromRefuted(
            &prepared,
            prepared.jobs,
            &outcome,
            prepared.job_origins,
            &trace,
        ),
    );
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(
        abi.resolution_status.problems,
        facts.environment.resolution_status,
    );
    try testing.expectEqual(@as(u32, 0), facts.action_count);
    try testing.expectEqual(@as(u32, 0), facts.selected_package_ref_count);
    try testing.expectEqual(@as(u32, 1), facts.problem_count);
    try testing.expectEqual(
        abi.problem_kind.unsatisfied_requirement,
        facts.problems.?[0].kind,
    );
    try testing.expectEqual(@as(u32, 1), facts.problems.?[0].has_job_ref);
    try testing.expectEqual(@as(u32, 1), facts.problems.?[0].has_package_ref);
}

test "hidden packages are published even though no action names them" {
    var available = [_]metadata.Package{
        testPackage("excluded", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const excluded: solver_model.PackageId = @enumFromInt(0);
    const hidden = [_]solver_model.PackageId{excluded};
    const outcome = solver_model.Outcome{
        .actions = &.{},
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const trace = emptyTrace();

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &.{},
        .outcome = &outcome,
        .selected = &.{},
        .hidden = &hidden,
        .job_origins = &.{},
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(@as(u32, 1), facts.hidden_package_ref_count);
    try testing.expectEqual(@as(u32, 0), facts.hidden_package_refs.?[0]);
    try testing.expectEqual(@as(u32, 1), facts.package_count);
}

test "a policy job the request layer never queued is absent from the plan" {
    var available = [_]metadata.Package{
        testPackage("wanted", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const wanted: solver_model.PackageId = @enumFromInt(0);
    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .{ .package = wanted } },
        .{ .action = .lock, .selection = .{ .name = "wanted" }, .reason = .policy },
    };
    const actions = [_]solver_model.Action{
        .{
            .package = wanted,
            .kind = .install,
            .reason = .user,
            .requested_by = @enumFromInt(1),
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const selected = [_]solver_model.PackageId{wanted};
    const trace = oneInstallTrace();
    // The lock comes from tdnf.conf, so the request layer never queued it.
    const origins = [_]?u32{ 0, null };

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &origins,
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(@as(u32, 1), facts.request_count);
    try testing.expectEqualStrings(
        "request-0",
        bytesOrEmpty(facts.requests.?[0].id),
    );
    // The plan numbers jobs by queue pair, so the synthesised lock adds none.
    try testing.expectEqual(@as(u32, 1), facts.job_count);
    try testing.expectEqual(abi.job_action.install, facts.jobs.?[0].action);
    try testing.expectEqual(@as(u32, 1), facts.jobs.?[0].has_request_ref);
    try testing.expectEqual(@as(u32, 0), facts.jobs.?[0].request_ref);
    // An action the lock caused has no published job to point at.
    try testing.expectEqual(
        @as(u32, 0),
        facts.actions.?[0].has_requested_job_ref,
    );
}

test "an erase expanded across duplicate rpmdb rows keeps one published job" {
    var installed = [_]metadata.Package{
        testPackage("doomed", "1", "x86_64"),
        testPackage("doomed", "1", "x86_64"),
    };
    const installed_model = metadata.RepositoryModel{ .packages = &installed };
    const installed_states = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 1 },
        .{ .rpmdb_hnum = 2 },
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@System",
            .model = &installed_model,
            .kind = .installed,
            .installed_states = &installed_states,
        },
    });
    defer harness.deinit();

    const first: solver_model.PackageId = @enumFromInt(0);
    const second: solver_model.PackageId = @enumFromInt(1);
    // One erase request naming a NEVRA the rpmdb holds twice becomes two
    // native jobs, both built from the same queue pair.
    const jobs = [_]solver_model.Job{
        .{ .action = .erase, .selection = .{ .package = first } },
        .{ .action = .erase, .selection = .{ .package = second } },
    };
    const actions = [_]solver_model.Action{
        .{
            .package = first,
            .kind = .erase,
            .reason = .user,
            .requested_by = @enumFromInt(0),
        },
        .{
            .package = second,
            .kind = .erase,
            .reason = .user,
            .requested_by = @enumFromInt(1),
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const trace = oneInstallTrace();
    const origins = [_]?u32{ 0, 0 };

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &.{},
        .job_origins = &origins,
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(@as(u32, 1), facts.job_count);
    try testing.expectEqual(@as(u32, 2), facts.action_count);
    // Both erases attribute to the single request that asked for them.
    for (facts.actions.?[0..2]) |action| {
        try testing.expectEqual(@as(u32, 1), action.has_requested_job_ref);
        try testing.expectEqual(@as(u32, 0), action.requested_job_ref);
    }
}

test "a job origin outside the trace is rejected" {
    var available = [_]metadata.Package{
        testPackage("wanted", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .all },
    };
    const outcome = solver_model.Outcome{
        .actions = &.{},
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const origins = [_]?u32{3};
    const trace = emptyTrace();

    try testing.expectError(error.JobMismatch, create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &.{},
        .job_origins = &origins,
        .trace = &trace,
    }));
}

test "job origins must line up with the jobs the solve ran" {
    var available = [_]metadata.Package{
        testPackage("wanted", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const jobs = [_]solver_model.Job{
        .{ .action = .install, .selection = .all },
    };
    const outcome = solver_model.Outcome{
        .actions = &.{},
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const trace = emptyTrace();

    try testing.expectError(error.JobMismatch, create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &.{},
        .job_origins = &.{},
        .trace = &trace,
    }));
}

test "duplicate problems fold into a single entry with a summed count" {
    var available = [_]metadata.Package{
        testPackage("wanted", "1", "x86_64"),
    };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const problems = [_]solver_model.Problem{
        .{ .kind = .no_candidate, .count = 2 },
        .{ .kind = .no_candidate, .count = 3 },
    };
    const outcome = solver_model.Outcome{
        .actions = &.{},
        .problems = &problems,
        .skipped_jobs = &.{},
    };
    const trace = emptyTrace();

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &.{},
        .outcome = &outcome,
        .selected = &.{},
        .job_origins = &.{},
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(@as(u32, 1), facts.problem_count);
    try testing.expectEqual(@as(u32, 5), facts.problems.?[0].count);
}

test "a command line package publishes a checksum but no location" {
    var command_line = [_]metadata.Package{
        testPackage("local", "1", "x86_64"),
    };
    const command_line_model = metadata.RepositoryModel{
        .packages = &command_line,
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@commandline",
            .model = &command_line_model,
            .kind = .command_line,
        },
    });
    defer harness.deinit();

    const local: solver_model.PackageId = @enumFromInt(0);
    const actions = [_]solver_model.Action{
        .{ .package = local, .kind = .install, .reason = .user },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const selected = [_]solver_model.PackageId{local};
    const trace = emptyTrace();

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &.{},
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &.{},
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    const package = facts.packages.?[0];
    try testing.expectEqual(@as(u32, 1), package.has_source);
    try testing.expectEqual(@as(u32, 0), package.source.has_location);
    try testing.expectEqualStrings(
        "sha256",
        bytesOrEmpty(package.source.checksum.kind),
    );
    try testing.expectEqual(
        abi.repository_kind.command_line,
        facts.repositories.?[0].kind,
    );
}

test "repository priorities use tdnf semantics by repository kind" {
    var installed = [_]metadata.Package{
        testPackage("old", "1", "x86_64"),
    };
    var available = [_]metadata.Package{
        testPackage("remote", "1", "x86_64"),
    };
    var command_line = [_]metadata.Package{
        testPackage("local", "1", "x86_64"),
    };
    const installed_model = metadata.RepositoryModel{ .packages = &installed };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    const command_line_model = metadata.RepositoryModel{
        .packages = &command_line,
    };
    const installed_states = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 1 },
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@System",
            .model = &installed_model,
            .kind = .installed,
            .priority = 91,
            .installed_states = &installed_states,
        },
        .{
            .id = "base",
            .model = &available_model,
            .kind = .available,
            .priority = 23,
        },
        .{
            .id = "@cmdline",
            .model = &command_line_model,
            .kind = .command_line,
            .priority = -77,
        },
    });
    defer harness.deinit();

    const old: solver_model.PackageId = @enumFromInt(0);
    const remote: solver_model.PackageId = @enumFromInt(1);
    const local: solver_model.PackageId = @enumFromInt(2);
    const jobs = [_]solver_model.Job{
        .{ .action = .erase, .selection = .{ .package = old } },
        .{ .action = .install, .selection = .{ .package = remote } },
        .{ .action = .install, .selection = .{ .package = local } },
    };
    const actions = [_]solver_model.Action{
        .{ .package = old, .kind = .erase, .reason = .user },
        .{ .package = remote, .kind = .install, .reason = .user },
        .{ .package = local, .kind = .install, .reason = .user },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const selected = [_]solver_model.PackageId{ remote, local };
    const requests = [_]abi.Request{
        testRequest("erase-old", abi.request_kind.erase, "old", .satisfied),
        testRequest(
            "install-remote",
            abi.request_kind.install,
            "remote",
            .satisfied,
        ),
        testRequest("install-local", abi.request_kind.install, null, .satisfied),
    };
    const trace_jobs = [_]abi.RequestTraceJob{
        testTracePackageJob(abi.job_action.erase, abi.request_reason.user, 0, 0),
        testTracePackageJob(
            abi.job_action.install,
            abi.request_reason.user,
            1,
            0,
        ),
        testTracePackageJob(
            abi.job_action.install,
            abi.request_reason.user,
            2,
            0,
        ),
    };
    const origins = [_]abi.RequestTraceQueueOrigin{
        testQueueOrigin(0, 0, 0),
        testQueueOrigin(1, 1, 1),
        testQueueOrigin(2, 2, 2),
    };
    const trace = testTrace(&requests, &trace_jobs, &origins);
    const job_origins = [_]?u32{ 0, 1, 2 };

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &job_origins,
        .trace = &trace,
    });
    defer owner.destroy();

    try testing.expectEqual(
        @as(i32, 23),
        repositoryById(owner.view(), "base").?.priority,
    );
    try testing.expectEqual(
        @as(i32, 0),
        repositoryById(owner.view(), "@System").?.priority,
    );
    try testing.expectEqual(
        @as(i32, 0),
        repositoryById(owner.view(), "@cmdline").?.priority,
    );

    var invalid = [_]metadata.Package{
        testPackage("invalid-priority", "1", "x86_64"),
    };
    const invalid_model = metadata.RepositoryModel{ .packages = &invalid };
    var invalid_harness = try buildUniverse(&.{
        .{
            .id = "invalid",
            .model = &invalid_model,
            .kind = .available,
            .priority = std.math.minInt(i32),
        },
    });
    defer invalid_harness.deinit();
    const invalid_id: solver_model.PackageId = @enumFromInt(0);
    const invalid_actions = [_]solver_model.Action{
        .{ .package = invalid_id, .kind = .install, .reason = .user },
    };
    const invalid_outcome = solver_model.Outcome{
        .actions = &invalid_actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const invalid_trace = emptyTrace();
    try testing.expectError(error.UnsupportedResult, create(testing.allocator, .{
        .universe = &invalid_harness.universe,
        .jobs = &.{},
        .outcome = &invalid_outcome,
        .selected = &.{},
        .job_origins = &.{},
        .trace = &invalid_trace,
    }));
}

fn replacementCaseNative(
    installed_evr: []const u8,
    available_evr: []const u8,
    job_action: u32,
    expected_kind: u32,
) !void {
    var installed = [_]metadata.Package{
        testPackageFromEvr("pkg", installed_evr, "x86_64"),
    };
    var available = [_]metadata.Package{
        testPackageFromEvr("pkg", available_evr, "x86_64"),
    };
    const installed_model = metadata.RepositoryModel{ .packages = &installed };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    const installed_states = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 9 },
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@System",
            .model = &installed_model,
            .kind = .installed,
            .installed_states = &installed_states,
        },
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const old: solver_model.PackageId = @enumFromInt(0);
    const new: solver_model.PackageId = @enumFromInt(1);
    const priors = [_]solver_model.PackageId{old};
    const native_action = switch (job_action) {
        abi.job_action.downgrade => solver_model.JobAction.downgrade,
        abi.job_action.reinstall => solver_model.JobAction.reinstall,
        else => solver_model.JobAction.update,
    };
    const jobs = [_]solver_model.Job{
        .{ .action = native_action, .selection = .{ .package = new } },
    };
    const actions = [_]solver_model.Action{
        .{
            .package = new,
            .priors = &priors,
            .kind = switch (expected_kind) {
                abi.action_kind.downgrade => .downgrade,
                abi.action_kind.reinstall => .reinstall,
                else => .upgrade,
            },
            .reason = .user,
            .requested_by = @enumFromInt(0),
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const selected = [_]solver_model.PackageId{new};
    const request_kind = if (job_action == abi.job_action.downgrade)
        abi.request_kind.downgrade
    else if (job_action == abi.job_action.reinstall)
        abi.request_kind.reinstall
    else
        abi.request_kind.update;
    const requests = [_]abi.Request{
        testRequest("replace-pkg", request_kind, "pkg", .satisfied),
    };
    const trace_jobs = [_]abi.RequestTraceJob{
        testTracePackageJob(job_action, abi.request_reason.user, 0, 0),
    };
    const origins = [_]abi.RequestTraceQueueOrigin{
        testQueueOrigin(0, 0, 0),
    };
    const trace = testTrace(&requests, &trace_jobs, &origins);
    const job_origins = [_]?u32{0};

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &job_origins,
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(@as(u32, 1), facts.action_count);
    const captured = facts.actions.?[0];
    try testing.expectEqual(expected_kind, captured.kind);
    try testing.expectEqual(@as(u32, 1), captured.prior_count);
    const prior_ref = facts.prior_package_refs.?[captured.prior_offset];
    try testing.expectEqualStrings(
        "pkg",
        bytesOrEmpty(facts.packages.?[prior_ref].identity.name),
    );
    try expectPackageEvr(
        &facts.packages.?[prior_ref],
        metadata.splitEvrQuery(installed_evr),
    );
    try expectPackageEvr(
        &facts.packages.?[captured.target_package_ref],
        metadata.splitEvrQuery(available_evr),
    );
}

test "upgrade downgrade and reinstall use authoritative EVR and priors" {
    try replacementCaseNative(
        "1-1",
        "2-1",
        abi.job_action.update,
        abi.action_kind.upgrade,
    );
    try replacementCaseNative(
        "2-1",
        "1-1",
        abi.job_action.downgrade,
        abi.action_kind.downgrade,
    );
    try replacementCaseNative(
        "1-1",
        "1-1",
        abi.job_action.reinstall,
        abi.action_kind.reinstall,
    );
}

test "highest same-name prior determines replacement kind with extra obsoletes" {
    var installed = [_]metadata.Package{
        testPackageFromEvr("pkg", "1-1", "x86_64"),
        testPackageFromEvr("pkg", "3-1", "x86_64"),
        testPackage("legacy", "1", "x86_64"),
    };
    var available = [_]metadata.Package{
        testPackageFromEvr("pkg", "2-1", "x86_64"),
    };
    const installed_model = metadata.RepositoryModel{ .packages = &installed };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    const installed_states = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 31 },
        .{ .rpmdb_hnum = 32 },
        .{ .rpmdb_hnum = 33 },
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@System",
            .model = &installed_model,
            .kind = .installed,
            .installed_states = &installed_states,
        },
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const low: solver_model.PackageId = @enumFromInt(0);
    const high: solver_model.PackageId = @enumFromInt(1);
    const legacy: solver_model.PackageId = @enumFromInt(2);
    const replacement: solver_model.PackageId = @enumFromInt(3);
    const priors = [_]solver_model.PackageId{ low, high, legacy };
    const jobs = [_]solver_model.Job{
        .{ .action = .downgrade, .selection = .{ .package = replacement } },
    };
    const actions = [_]solver_model.Action{
        .{
            .package = replacement,
            .priors = &priors,
            .kind = .downgrade,
            .reason = .user,
            .requested_by = @enumFromInt(0),
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const selected = [_]solver_model.PackageId{replacement};
    const requests = [_]abi.Request{
        testRequest("downgrade-pkg", abi.request_kind.downgrade, "pkg", .satisfied),
    };
    const trace_jobs = [_]abi.RequestTraceJob{
        testTracePackageJob(
            abi.job_action.downgrade,
            abi.request_reason.user,
            0,
            0,
        ),
    };
    const origins = [_]abi.RequestTraceQueueOrigin{
        testQueueOrigin(0, 0, 0),
    };
    const trace = testTrace(&requests, &trace_jobs, &origins);
    const job_origins = [_]?u32{0};

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &job_origins,
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(@as(u32, 1), facts.action_count);
    try testing.expectEqual(abi.action_kind.downgrade, facts.actions.?[0].kind);
    try testing.expectEqual(@as(u32, 3), facts.actions.?[0].prior_count);
    try expectPriorNames(facts, facts.actions.?[0], &.{ "pkg", "pkg", "legacy" });
}

test "obsoletes retain multiple priors and permit a shared prior" {
    {
        var installed = [_]metadata.Package{
            testPackage("old-a", "1", "x86_64"),
            testPackage("old-b", "1", "x86_64"),
        };
        var available = [_]metadata.Package{
            testPackageFromEvr("replacement", "2-1", "x86_64"),
        };
        const installed_model = metadata.RepositoryModel{
            .packages = &installed,
        };
        const available_model = metadata.RepositoryModel{
            .packages = &available,
        };
        const installed_states = [_]solver_model.InstalledState{
            .{ .rpmdb_hnum = 11 },
            .{ .rpmdb_hnum = 12 },
        };
        var harness = try buildUniverse(&.{
            .{
                .id = "@System",
                .model = &installed_model,
                .kind = .installed,
                .installed_states = &installed_states,
            },
            .{ .id = "base", .model = &available_model, .kind = .available },
        });
        defer harness.deinit();

        const old_a: solver_model.PackageId = @enumFromInt(0);
        const old_b: solver_model.PackageId = @enumFromInt(1);
        const replacement: solver_model.PackageId = @enumFromInt(2);
        const priors = [_]solver_model.PackageId{ old_b, old_a };
        const jobs = [_]solver_model.Job{
            .{ .action = .install, .selection = .{ .package = replacement } },
        };
        const actions = [_]solver_model.Action{
            .{
                .package = replacement,
                .priors = &priors,
                .kind = .obsolete,
                .reason = .obsoletes,
                .requested_by = @enumFromInt(0),
            },
        };
        const outcome = solver_model.Outcome{
            .actions = &actions,
            .problems = &.{},
            .skipped_jobs = &.{},
        };
        const selected = [_]solver_model.PackageId{replacement};
        const requests = [_]abi.Request{
            testRequest(
                "install-replacement",
                abi.request_kind.install,
                "replacement",
                .satisfied,
            ),
        };
        const trace_jobs = [_]abi.RequestTraceJob{
            testTracePackageJob(
                abi.job_action.install,
                abi.request_reason.user,
                0,
                0,
            ),
        };
        const origins = [_]abi.RequestTraceQueueOrigin{
            testQueueOrigin(0, 0, 0),
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const job_origins = [_]?u32{0};

        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &selected,
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        const facts = owner.view();
        try testing.expectEqual(@as(u32, 1), facts.action_count);
        try testing.expectEqual(abi.action_kind.obsolete, facts.actions.?[0].kind);
        try testing.expectEqual(
            abi.action_reason.obsoletes,
            facts.actions.?[0].reason,
        );
        try testing.expectEqual(@as(u32, 2), facts.actions.?[0].prior_count);
        try expectPriorNames(facts, facts.actions.?[0], &.{ "old-a", "old-b" });
    }

    {
        var installed = [_]metadata.Package{
            testPackage("old", "1", "x86_64"),
        };
        var available = [_]metadata.Package{
            testPackage("first", "1", "x86_64"),
            testPackage("second", "1", "x86_64"),
        };
        const installed_model = metadata.RepositoryModel{
            .packages = &installed,
        };
        const available_model = metadata.RepositoryModel{
            .packages = &available,
        };
        const installed_states = [_]solver_model.InstalledState{
            .{ .rpmdb_hnum = 21 },
        };
        var harness = try buildUniverse(&.{
            .{
                .id = "@System",
                .model = &installed_model,
                .kind = .installed,
                .installed_states = &installed_states,
            },
            .{ .id = "base", .model = &available_model, .kind = .available },
        });
        defer harness.deinit();

        const old: solver_model.PackageId = @enumFromInt(0);
        const first: solver_model.PackageId = @enumFromInt(1);
        const second: solver_model.PackageId = @enumFromInt(2);
        const first_priors = [_]solver_model.PackageId{old};
        const second_priors = [_]solver_model.PackageId{old};
        const jobs = [_]solver_model.Job{
            .{ .action = .install, .selection = .{ .package = first } },
            .{ .action = .install, .selection = .{ .package = second } },
        };
        const actions = [_]solver_model.Action{
            .{
                .package = first,
                .priors = &first_priors,
                .kind = .obsolete,
                .reason = .obsoletes,
                .requested_by = @enumFromInt(0),
            },
            .{
                .package = second,
                .priors = &second_priors,
                .kind = .obsolete,
                .reason = .obsoletes,
                .requested_by = @enumFromInt(1),
            },
        };
        const outcome = solver_model.Outcome{
            .actions = &actions,
            .problems = &.{},
            .skipped_jobs = &.{},
        };
        const selected = [_]solver_model.PackageId{ first, second };
        const requests = [_]abi.Request{
            testRequest("install-first", abi.request_kind.install, "first", .satisfied),
            testRequest(
                "install-second",
                abi.request_kind.install,
                "second",
                .satisfied,
            ),
        };
        const trace_jobs = [_]abi.RequestTraceJob{
            testTracePackageJob(
                abi.job_action.install,
                abi.request_reason.user,
                0,
                0,
            ),
            testTracePackageJob(
                abi.job_action.install,
                abi.request_reason.user,
                1,
                0,
            ),
        };
        const origins = [_]abi.RequestTraceQueueOrigin{
            testQueueOrigin(0, 0, 0),
            testQueueOrigin(1, 1, 1),
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const job_origins = [_]?u32{ 0, 1 };

        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &selected,
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        const facts = owner.view();
        try testing.expectEqual(@as(u32, 2), facts.action_count);
        try testing.expectEqual(@as(u32, 2), facts.job_count);
        try testing.expectEqualStrings(
            "first",
            bytesOrEmpty(facts.packages.?[
                facts.jobs.?[0].selection_package_ref
            ].identity.name),
        );
        try testing.expectEqualStrings(
            "second",
            bytesOrEmpty(facts.packages.?[
                facts.jobs.?[1].selection_package_ref
            ].identity.name),
        );
        var shared_ref: ?u32 = null;
        for (facts.actions.?[0..facts.action_count]) |action| {
            try testing.expectEqual(abi.action_kind.obsolete, action.kind);
            try testing.expectEqual(@as(u32, 1), action.prior_count);
            const prior = facts.prior_package_refs.?[action.prior_offset];
            if (shared_ref) |expected| {
                try testing.expectEqual(expected, prior);
            } else {
                shared_ref = prior;
            }
        }
        try testing.expectEqualStrings(
            "old",
            bytesOrEmpty(facts.packages.?[shared_ref.?].identity.name),
        );
        try testing.expectEqual(
            @as(u32, 3),
            facts.native_execution_input_count,
        );
        var erase_count: usize = 0;
        for (facts.native_execution_inputs.?[0..facts.native_execution_input_count]) |input| {
            if (input.operation == abi.execution_operation.erase)
                erase_count += 1;
        }
        try testing.expectEqual(@as(usize, 1), erase_count);
    }
}

test "weak dependency and clean-dependency erases have exact reasons" {
    {
        var available = [_]metadata.Package{
            testPackage("app", "1", "x86_64"),
            testPackage("weak", "1", "x86_64"),
        };
        const available_model = metadata.RepositoryModel{ .packages = &available };
        var harness = try buildUniverse(&.{
            .{ .id = "base", .model = &available_model, .kind = .available },
        });
        defer harness.deinit();

        const app: solver_model.PackageId = @enumFromInt(0);
        const weak: solver_model.PackageId = @enumFromInt(1);
        const jobs = [_]solver_model.Job{
            .{ .action = .install, .selection = .{ .package = app } },
        };
        const actions = [_]solver_model.Action{
            .{
                .package = app,
                .kind = .install,
                .reason = .user,
                .requested_by = @enumFromInt(0),
            },
            .{
                .package = weak,
                .kind = .install,
                .reason = .weak_dependency,
            },
        };
        const outcome = solver_model.Outcome{
            .actions = &actions,
            .problems = &.{},
            .skipped_jobs = &.{},
        };
        const selected = [_]solver_model.PackageId{ app, weak };
        const requests = [_]abi.Request{
            testRequest("install-app", abi.request_kind.install, "app", .satisfied),
        };
        const trace_jobs = [_]abi.RequestTraceJob{
            testTracePackageJob(
                abi.job_action.install,
                abi.request_reason.user,
                0,
                0,
            ),
        };
        const origins = [_]abi.RequestTraceQueueOrigin{
            testQueueOrigin(0, 0, 0),
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const job_origins = [_]?u32{0};

        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &selected,
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        var saw_weak = false;
        for (owner.view().actions.?[0..owner.view().action_count]) |action| {
            const target = owner.view().packages.?[action.target_package_ref];
            if (std.mem.eql(u8, bytesOrEmpty(target.identity.name), "weak")) {
                try testing.expectEqual(
                    abi.action_reason.weak_dependency,
                    action.reason,
                );
                saw_weak = true;
            }
        }
        try testing.expect(saw_weak);
    }

    {
        var installed = [_]metadata.Package{
            testPackage("dependency", "1", "x86_64"),
            testPackage("app", "1", "x86_64"),
        };
        const installed_model = metadata.RepositoryModel{ .packages = &installed };
        const installed_states = [_]solver_model.InstalledState{
            .{ .rpmdb_hnum = 51 },
            .{ .rpmdb_hnum = 52 },
        };
        var harness = try buildUniverse(&.{
            .{
                .id = "@System",
                .model = &installed_model,
                .kind = .installed,
                .installed_states = &installed_states,
            },
        });
        defer harness.deinit();

        const dependency: solver_model.PackageId = @enumFromInt(0);
        const app: solver_model.PackageId = @enumFromInt(1);
        const jobs = [_]solver_model.Job{
            .{ .action = .user_installed, .selection = .{ .package = app } },
            .{
                .action = .erase,
                .selection = .{ .package = app },
                .flags = .{ .clean_deps = true },
            },
        };
        const actions = [_]solver_model.Action{
            .{
                .package = dependency,
                .kind = .erase,
                .reason = .cleanup,
            },
            .{
                .package = app,
                .kind = .erase,
                .reason = .user,
                .requested_by = @enumFromInt(1),
            },
        };
        const outcome = solver_model.Outcome{
            .actions = &actions,
            .problems = &.{},
            .skipped_jobs = &.{},
        };
        const requests = [_]abi.Request{
            testRequest("erase-app", abi.request_kind.erase, "app", .satisfied),
        };
        const trace_jobs = [_]abi.RequestTraceJob{
            testTracePackageJob(
                abi.job_action.user_installed,
                abi.request_reason.policy,
                null,
                0,
            ),
            testTracePackageJob(
                abi.job_action.erase,
                abi.request_reason.user,
                0,
                abi.request_trace_flag.clean_deps,
            ),
        };
        const origins = [_]abi.RequestTraceQueueOrigin{
            testQueueOrigin(0, 0, null),
            testQueueOrigin(1, 1, 0),
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const job_origins = [_]?u32{ 0, 1 };

        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &.{},
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        const facts = owner.view();
        try testing.expectEqual(@as(u32, 1), facts.jobs.?[1].clean_deps);
        var saw_cleanup = false;
        var saw_user_erase = false;
        for (facts.actions.?[0..facts.action_count]) |action| {
            const target = facts.packages.?[action.target_package_ref];
            if (std.mem.eql(u8, bytesOrEmpty(target.identity.name), "dependency")) {
                try testing.expectEqual(abi.action_reason.cleanup, action.reason);
                saw_cleanup = true;
            } else if (std.mem.eql(u8, bytesOrEmpty(target.identity.name), "app")) {
                try testing.expectEqual(abi.action_kind.erase, action.kind);
                try testing.expectEqual(abi.action_reason.user, action.reason);
                saw_user_erase = true;
            }
        }
        try testing.expect(saw_cleanup);
        try testing.expect(saw_user_erase);
    }
}

test "erase and installonly retry erase retain exact reasons" {
    var installed = [_]metadata.Package{
        testPackageFromEvr("kernel", "1-1", "x86_64"),
    };
    var available = [_]metadata.Package{
        testPackageFromEvr("kernel", "2-1", "x86_64"),
    };
    const installed_model = metadata.RepositoryModel{ .packages = &installed };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    const installed_states = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 10 },
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@System",
            .model = &installed_model,
            .kind = .installed,
            .installed_states = &installed_states,
        },
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const old: solver_model.PackageId = @enumFromInt(0);
    const new: solver_model.PackageId = @enumFromInt(1);
    const jobs = [_]solver_model.Job{
        .{ .action = .multiversion, .selection = .{ .name = "kernel" } },
        .{ .action = .install, .selection = .{ .package = new } },
        .{
            .action = .erase,
            .selection = .{ .package = old },
            .reason = .installonly_limit,
        },
    };
    const actions = [_]solver_model.Action{
        .{
            .package = new,
            .kind = .install,
            .reason = .user,
            .requested_by = @enumFromInt(1),
        },
        .{
            .package = old,
            .kind = .erase,
            .reason = .installonly_limit,
            .requested_by = @enumFromInt(2),
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const selected = [_]solver_model.PackageId{new};
    const requests = [_]abi.Request{
        testRequest(
            "install-kernel",
            abi.request_kind.install,
            "kernel",
            .satisfied,
        ),
    };
    const trace_jobs = [_]abi.RequestTraceJob{
        testTraceNameJob(
            abi.job_action.multiversion,
            "kernel",
            abi.request_reason.policy,
            null,
            0,
        ),
        testTracePackageJob(
            abi.job_action.install,
            abi.request_reason.user,
            0,
            0,
        ),
        testTracePackageJob(
            abi.job_action.erase,
            abi.request_reason.installonly_limit,
            null,
            0,
        ),
    };
    const origins = [_]abi.RequestTraceQueueOrigin{
        testQueueOrigin(0, 0, null),
        testQueueOrigin(1, 1, 0),
        testQueueOrigin(2, 2, null),
    };
    const trace = testTrace(&requests, &trace_jobs, &origins);
    const job_origins = [_]?u32{ 0, 1, 2 };

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &selected,
        .job_origins = &job_origins,
        .trace = &trace,
    });
    defer owner.destroy();

    var saw_erase = false;
    var saw_install = false;
    for (owner.view().actions.?[0..owner.view().action_count]) |action| {
        if (action.kind == abi.action_kind.erase) {
            try testing.expectEqual(
                abi.action_reason.installonly_limit,
                action.reason,
            );
            try testing.expectEqual(@as(u32, 1), action.has_requested_job_ref);
            try testing.expectEqual(@as(u32, 2), action.requested_job_ref);
            saw_erase = true;
        } else if (action.kind == abi.action_kind.install) {
            saw_install = true;
        }
    }
    try testing.expect(saw_erase);
    try testing.expect(saw_install);
}

test "installonly terminal accepts only an attributed erase tail" {
    var installed = [_]metadata.Package{
        testPackageFromEvr("kernel", "1-1", "x86_64"),
    };
    var available = [_]metadata.Package{
        testPackageFromEvr("kernel", "2-1", "x86_64"),
    };
    const installed_model = metadata.RepositoryModel{ .packages = &installed };
    const available_model = metadata.RepositoryModel{ .packages = &available };
    const installed_states = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 10 },
    };
    var harness = try buildUniverse(&.{
        .{
            .id = "@System",
            .model = &installed_model,
            .kind = .installed,
            .installed_states = &installed_states,
        },
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const old: solver_model.PackageId = @enumFromInt(0);
    const new: solver_model.PackageId = @enumFromInt(1);
    const jobs = [_]solver_model.Job{
        .{ .action = .multiversion, .selection = .{ .name = "kernel" } },
        .{ .action = .install, .selection = .{ .package = new } },
        .{
            .action = .erase,
            .selection = .{ .package = old },
            .reason = .installonly_limit,
        },
    };
    const problems = [_]solver_model.Problem{
        .{
            .kind = .installonly_limit,
            .package = old,
            .job = @enumFromInt(2),
            .count = 1,
        },
    };
    const outcome = solver_model.Outcome{
        .actions = &.{},
        .problems = &problems,
        .skipped_jobs = &.{},
    };
    const requests = [_]abi.Request{
        testRequest(
            "install-kernel",
            abi.request_kind.install,
            "kernel",
            .satisfied,
        ),
    };
    const trace_jobs = [_]abi.RequestTraceJob{
        testTraceNameJob(
            abi.job_action.multiversion,
            "kernel",
            abi.request_reason.policy,
            null,
            0,
        ),
        testTracePackageJob(
            abi.job_action.install,
            abi.request_reason.user,
            0,
            0,
        ),
        testTracePackageJob(
            abi.job_action.erase,
            abi.request_reason.installonly_limit,
            null,
            0,
        ),
    };
    const origins = [_]abi.RequestTraceQueueOrigin{
        testQueueOrigin(0, 0, null),
        testQueueOrigin(1, 1, 0),
        testQueueOrigin(2, 2, null),
    };
    const trace = testTrace(&requests, &trace_jobs, &origins);
    const job_origins = [_]?u32{ 0, 1, 2 };

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = &jobs,
        .outcome = &outcome,
        .selected = &.{},
        .job_origins = &job_origins,
        .trace = &trace,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(
        abi.resolution_status.problems,
        facts.environment.resolution_status,
    );
    try testing.expectEqual(@as(u32, 0), facts.action_count);
    try testing.expectEqual(@as(u32, 3), facts.job_count);
    try testing.expectEqual(
        abi.request_reason.installonly_limit,
        facts.jobs.?[2].reason,
    );
    try testing.expectEqual(@as(u32, 1), facts.problem_count);
    try testing.expectEqual(
        abi.problem_kind.installonly_limit,
        facts.problems.?[0].kind,
    );
    try testing.expectEqual(@as(u32, 1), facts.problems.?[0].has_job_ref);
    try testing.expectEqual(@as(u32, 2), facts.problems.?[0].job_ref);
    try testing.expectEqual(@as(u32, 1), facts.problems.?[0].has_package_ref);
}

test "no-candidate unsatisfied and conflict problems are structured" {
    {
        const available_model = metadata.RepositoryModel{ .packages = &.{} };
        var harness = try buildUniverse(&.{
            .{ .id = "base", .model = &available_model, .kind = .available },
        });
        defer harness.deinit();

        const jobs = [_]solver_model.Job{
            .{ .action = .install, .selection = .{ .name = "missing" } },
        };
        const problems = [_]solver_model.Problem{
            .{
                .kind = .no_candidate,
                .capability = .{ .name = "missing" },
                .job = @enumFromInt(0),
                .count = 1,
            },
        };
        const outcome = solver_model.Outcome{
            .actions = &.{},
            .problems = &problems,
            .skipped_jobs = &.{},
        };
        const requests = [_]abi.Request{
            testRequest(
                "install-missing",
                abi.request_kind.install,
                "missing",
                .no_candidate,
            ),
        };
        const trace_jobs = [_]abi.RequestTraceJob{
            testTraceNameJob(
                abi.job_action.install,
                "missing",
                abi.request_reason.user,
                0,
                0,
            ),
        };
        const origins = [_]abi.RequestTraceQueueOrigin{
            testQueueOrigin(0, 0, 0),
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const job_origins = [_]?u32{0};

        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &.{},
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        const facts = owner.view();
        try testing.expectEqual(
            abi.resolution_status.problems,
            facts.environment.resolution_status,
        );
        try testing.expectEqual(@as(u32, 0), facts.action_count);
        try testing.expectEqual(@as(u32, 0), facts.selected_package_ref_count);
        try testing.expectEqual(@as(u32, 1), facts.problem_count);
        const problem = facts.problems.?[0];
        try testing.expectEqual(abi.problem_kind.no_candidate, problem.kind);
        try testing.expectEqual(@as(u32, 1), problem.has_job_ref);
        try testing.expectEqual(@as(u32, 1), problem.has_capability);
        try testing.expectEqualStrings(
            "missing",
            bytesOrEmpty(problem.capability.name),
        );
    }

    {
        var available = [_]metadata.Package{
            testPackage("broken", "1", "x86_64"),
        };
        const available_model = metadata.RepositoryModel{ .packages = &available };
        var harness = try buildUniverse(&.{
            .{ .id = "base", .model = &available_model, .kind = .available },
        });
        defer harness.deinit();

        const broken: solver_model.PackageId = @enumFromInt(0);
        const jobs = [_]solver_model.Job{
            .{ .action = .install, .selection = .{ .package = broken } },
        };
        const problems = [_]solver_model.Problem{
            .{
                .kind = .unsatisfied_requirement,
                .package = broken,
                .capability = .{ .name = "missing-dependency" },
                .job = @enumFromInt(0),
                .count = 1,
            },
        };
        const outcome = solver_model.Outcome{
            .actions = &.{},
            .problems = &problems,
            .skipped_jobs = &.{},
        };
        const requests = [_]abi.Request{
            testRequest(
                "install-broken",
                abi.request_kind.install,
                "broken",
                .satisfied,
            ),
        };
        const trace_jobs = [_]abi.RequestTraceJob{
            testTracePackageJob(
                abi.job_action.install,
                abi.request_reason.user,
                0,
                0,
            ),
        };
        const origins = [_]abi.RequestTraceQueueOrigin{
            testQueueOrigin(0, 0, 0),
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const job_origins = [_]?u32{0};

        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &.{},
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        const problem = owner.view().problems.?[0];
        try testing.expectEqual(
            abi.problem_kind.unsatisfied_requirement,
            problem.kind,
        );
        try testing.expectEqual(@as(u32, 1), problem.has_package_ref);
        try testing.expectEqual(@as(u32, 1), problem.has_capability);
        try testing.expectEqualStrings(
            "missing-dependency",
            bytesOrEmpty(problem.capability.name),
        );
    }

    {
        var available = [_]metadata.Package{
            testPackage("first", "1", "x86_64"),
            testPackage("second", "1", "x86_64"),
        };
        const available_model = metadata.RepositoryModel{ .packages = &available };
        var harness = try buildUniverse(&.{
            .{ .id = "base", .model = &available_model, .kind = .available },
        });
        defer harness.deinit();

        const first: solver_model.PackageId = @enumFromInt(0);
        const second: solver_model.PackageId = @enumFromInt(1);
        const jobs = [_]solver_model.Job{
            .{ .action = .install, .selection = .{ .package = first } },
            .{ .action = .install, .selection = .{ .package = second } },
        };
        const problems = [_]solver_model.Problem{
            .{
                .kind = .conflict,
                .package = first,
                .related_package = second,
                .job = @enumFromInt(0),
                .count = 1,
            },
        };
        const outcome = solver_model.Outcome{
            .actions = &.{},
            .problems = &problems,
            .skipped_jobs = &.{},
        };
        const requests = [_]abi.Request{
            testRequest("install-first", abi.request_kind.install, "first", .satisfied),
            testRequest(
                "install-second",
                abi.request_kind.install,
                "second",
                .satisfied,
            ),
        };
        const trace_jobs = [_]abi.RequestTraceJob{
            testTracePackageJob(
                abi.job_action.install,
                abi.request_reason.user,
                0,
                0,
            ),
            testTracePackageJob(
                abi.job_action.install,
                abi.request_reason.user,
                1,
                0,
            ),
        };
        const origins = [_]abi.RequestTraceQueueOrigin{
            testQueueOrigin(0, 0, 0),
            testQueueOrigin(1, 1, 1),
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const job_origins = [_]?u32{ 0, 1 };

        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &.{},
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        const problem = owner.view().problems.?[0];
        try testing.expectEqual(abi.problem_kind.conflict, problem.kind);
        try testing.expectEqual(@as(u32, 1), problem.has_package_ref);
        try testing.expectEqual(@as(u32, 1), problem.has_related_package_ref);
    }
}

test "package and capability EVRs recognize only complete decimal epochs" {
    {
        const vectors = [_]struct {
            name: []const u8,
            evr: []const u8,
            epoch: ?u32,
            version: []const u8,
            release: []const u8,
        }{
            .{ .name = "pkg-decimal", .evr = "1:2-3", .epoch = 1, .version = "2", .release = "3" },
            .{ .name = "pkg-leading-zero", .evr = "01:2:3-4", .epoch = 1, .version = "2:3", .release = "4" },
            .{ .name = "pkg-zero", .evr = "0:2-3", .epoch = 0, .version = "2", .release = "3" },
            .{ .name = "pkg-empty-prefix", .evr = ":2-3", .epoch = null, .version = ":2", .release = "3" },
            .{ .name = "pkg-alpha-prefix", .evr = "x:2-3", .epoch = null, .version = "x:2", .release = "3" },
            .{ .name = "pkg-mixed-prefix", .evr = "1x:2-3", .epoch = null, .version = "1x:2", .release = "3" },
            .{ .name = "pkg-release-colon", .evr = "2-3:4", .epoch = null, .version = "2", .release = "3:4" },
        };
        var packages: [vectors.len]metadata.Package = undefined;
        var jobs: [vectors.len]solver_model.Job = undefined;
        var actions: [vectors.len]solver_model.Action = undefined;
        var selected: [vectors.len]solver_model.PackageId = undefined;
        var requests: [vectors.len]abi.Request = undefined;
        var trace_jobs: [vectors.len]abi.RequestTraceJob = undefined;
        var origins: [vectors.len]abi.RequestTraceQueueOrigin = undefined;
        var job_origins: [vectors.len]?u32 = undefined;
        for (vectors, 0..) |vector, index| {
            const package_id: solver_model.PackageId =
                @enumFromInt(@as(u32, @intCast(index)));
            packages[index] = testPackageFromEvr(
                vector.name,
                vector.evr,
                "x86_64",
            );
            jobs[index] = .{
                .action = .install,
                .selection = .{ .package = package_id },
            };
            actions[index] = .{
                .package = package_id,
                .kind = .install,
                .reason = .user,
                .requested_by = @enumFromInt(@as(u32, @intCast(index))),
            };
            selected[index] = package_id;
            requests[index] = testRequest(
                vector.name,
                abi.request_kind.install,
                vector.name,
                .satisfied,
            );
            trace_jobs[index] = testTracePackageJob(
                abi.job_action.install,
                abi.request_reason.user,
                @intCast(index),
                0,
            );
            origins[index] = testQueueOrigin(
                @intCast(index),
                @intCast(index),
                @intCast(index),
            );
            job_origins[index] = @intCast(index);
        }
        const available_model = metadata.RepositoryModel{ .packages = &packages };
        var harness = try buildUniverse(&.{
            .{ .id = "base", .model = &available_model, .kind = .available },
        });
        defer harness.deinit();

        const outcome = solver_model.Outcome{
            .actions = &actions,
            .problems = &.{},
            .skipped_jobs = &.{},
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &selected,
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        for (vectors) |vector| {
            const package = packageByName(
                owner.view(),
                vector.name,
                abi.package_state.available,
            ).?.package;
            try testing.expectEqual(
                @as(u32, @intFromBool(vector.epoch != null)),
                package.identity.has_epoch,
            );
            try testing.expectEqual(vector.epoch orelse 0, package.identity.epoch);
            try testing.expectEqualStrings(
                vector.version,
                bytesOrEmpty(package.identity.version),
            );
            try testing.expectEqualStrings(
                vector.release,
                bytesOrEmpty(package.identity.release),
            );
        }
    }

    {
        const vectors = [_]struct {
            package_name: []const u8,
            capability_name: []const u8,
            evr: []const u8,
            epoch: ?u32,
            version: []const u8,
            release: ?[]const u8,
        }{
            .{ .package_name = "provider-decimal", .capability_name = "cap-decimal", .evr = "1:2-3", .epoch = 1, .version = "2", .release = "3" },
            .{ .package_name = "provider-leading-zero", .capability_name = "cap-leading-zero", .evr = "01:2:3-4", .epoch = 1, .version = "2:3", .release = "4" },
            .{ .package_name = "provider-empty-prefix", .capability_name = "cap-empty-prefix", .evr = ":2-3", .epoch = null, .version = ":2", .release = "3" },
            .{ .package_name = "provider-alpha-prefix", .capability_name = "cap-alpha-prefix", .evr = "x:2-3", .epoch = null, .version = "x:2", .release = "3" },
            .{ .package_name = "provider-mixed-prefix", .capability_name = "cap-mixed-prefix", .evr = "1x:2-3", .epoch = null, .version = "1x:2", .release = "3" },
            .{ .package_name = "provider-empty-suffix", .capability_name = "cap-empty-suffix", .evr = "1:", .epoch = null, .version = "1:", .release = null },
            .{ .package_name = "provider-colon", .capability_name = "cap-colon", .evr = ":", .epoch = null, .version = ":", .release = null },
        };
        var packages: [vectors.len]metadata.Package = undefined;
        var jobs: [vectors.len]solver_model.Job = undefined;
        var actions: [vectors.len]solver_model.Action = undefined;
        var selected: [vectors.len]solver_model.PackageId = undefined;
        var requests: [vectors.len]abi.Request = undefined;
        var trace_jobs: [vectors.len]abi.RequestTraceJob = undefined;
        var origins: [vectors.len]abi.RequestTraceQueueOrigin = undefined;
        var job_origins: [vectors.len]?u32 = undefined;
        for (vectors, 0..) |vector, index| {
            const package_id: solver_model.PackageId =
                @enumFromInt(@as(u32, @intCast(index)));
            const relation = capabilityRelation(
                vector.capability_name,
                vector.epoch,
                vector.version,
                vector.release,
            );
            packages[index] = testPackage(vector.package_name, "1", "x86_64");
            jobs[index] = .{ .action = .install, .selection = .{
                .capability = relation,
            } };
            actions[index] = .{
                .package = package_id,
                .kind = .install,
                .reason = .user,
                .requested_by = @enumFromInt(@as(u32, @intCast(index))),
            };
            selected[index] = package_id;
            requests[index] = testRequest(
                vector.capability_name,
                abi.request_kind.install,
                vector.capability_name,
                .satisfied,
            );
            trace_jobs[index] = testTraceCapabilityJob(
                abi.job_action.install,
                relation,
                abi.request_reason.user,
                @intCast(index),
            );
            origins[index] = testQueueOrigin(
                @intCast(index),
                @intCast(index),
                @intCast(index),
            );
            job_origins[index] = @intCast(index);
        }
        const available_model = metadata.RepositoryModel{ .packages = &packages };
        var harness = try buildUniverse(&.{
            .{ .id = "base", .model = &available_model, .kind = .available },
        });
        defer harness.deinit();

        const outcome = solver_model.Outcome{
            .actions = &actions,
            .problems = &.{},
            .skipped_jobs = &.{},
        };
        const trace = testTrace(&requests, &trace_jobs, &origins);
        const owner = try create(testing.allocator, .{
            .universe = &harness.universe,
            .jobs = &jobs,
            .outcome = &outcome,
            .selected = &selected,
            .job_origins = &job_origins,
            .trace = &trace,
        });
        defer owner.destroy();

        const captured_jobs = owner.view().jobs.?[0..owner.view().job_count];
        for (vectors, captured_jobs) |vector, job| {
            const capability = job.capability;
            try testing.expectEqualStrings(
                vector.capability_name,
                bytesOrEmpty(capability.name),
            );
            try testing.expectEqual(
                @as(u32, @intFromBool(vector.epoch != null)),
                capability.has_epoch,
            );
            try testing.expectEqual(vector.epoch orelse 0, capability.epoch);
            try testing.expectEqualStrings(
                vector.version,
                bytesOrEmpty(capability.version),
            );
            try testing.expectEqual(
                @as(u32, @intFromBool(vector.release != null)),
                capability.has_release,
            );
            if (vector.release) |release| {
                try testing.expectEqualStrings(
                    release,
                    bytesOrEmpty(capability.release),
                );
            }
        }
    }
}

test "thousands of selected actions capture without quadratic deduplication" {
    const package_count = 2048;
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const packages = try arena.alloc(metadata.Package, package_count);
    const jobs = try arena.alloc(solver_model.Job, package_count);
    const actions = try arena.alloc(solver_model.Action, package_count);
    const selected = try arena.alloc(solver_model.PackageId, package_count);
    const requests = try arena.alloc(abi.Request, package_count);
    const trace_jobs = try arena.alloc(abi.RequestTraceJob, package_count);
    const origins = try arena.alloc(abi.RequestTraceQueueOrigin, package_count);
    const job_origins = try arena.alloc(?u32, package_count);
    for (0..package_count) |index| {
        const name = try std.fmt.allocPrint(
            arena,
            "scale-package-{d}",
            .{index},
        );
        const package_id: solver_model.PackageId =
            @enumFromInt(@as(u32, @intCast(index)));
        packages[index] = testPackage(name, "1", "x86_64");
        jobs[index] = .{
            .action = .install,
            .selection = .{ .package = package_id },
        };
        actions[index] = .{
            .package = package_id,
            .kind = .install,
            .reason = .policy,
            .requested_by = @enumFromInt(@as(u32, @intCast(index))),
        };
        selected[index] = package_id;
        requests[index] = testRequest(
            name,
            abi.request_kind.install,
            name,
            .satisfied,
        );
        trace_jobs[index] = testTracePackageJob(
            abi.job_action.install,
            abi.request_reason.policy,
            null,
            0,
        );
        origins[index] = testQueueOrigin(
            @intCast(index),
            @intCast(index),
            null,
        );
        job_origins[index] = @intCast(index);
    }
    const available_model = metadata.RepositoryModel{ .packages = packages };
    var harness = try buildUniverse(&.{
        .{ .id = "base", .model = &available_model, .kind = .available },
    });
    defer harness.deinit();

    const outcome = solver_model.Outcome{
        .actions = actions,
        .problems = &.{},
        .skipped_jobs = &.{},
    };
    const trace = abi.RequestTraceView{
        .requests = requests.ptr,
        .jobs = trace_jobs.ptr,
        .queue_origins = origins.ptr,
        .request_count = @intCast(requests.len),
        .job_count = @intCast(trace_jobs.len),
        .queue_origin_count = @intCast(origins.len),
    };

    const owner = try create(testing.allocator, .{
        .universe = &harness.universe,
        .jobs = jobs,
        .outcome = &outcome,
        .selected = selected,
        .job_origins = job_origins,
        .trace = &trace,
    });
    defer owner.destroy();

    try testing.expectEqual(@as(u32, package_count), owner.view().package_count);
    try testing.expectEqual(
        @as(u32, package_count),
        owner.view().selected_package_ref_count,
    );
    try testing.expectEqual(@as(u32, package_count), owner.view().action_count);
}

const TestRequestOutcome = enum {
    satisfied,
    no_candidate,
};

fn testRequest(
    id: []const u8,
    kind: u32,
    subject: ?[]const u8,
    outcome: TestRequestOutcome,
) abi.Request {
    return .{
        .id = testBytes(id),
        .subject = if (subject) |value| testBytes(value) else .{},
        .kind = kind,
        .has_subject = @intFromBool(subject != null),
        .outcome = switch (outcome) {
            .satisfied => abi.request_outcome.satisfied,
            .no_candidate => abi.request_outcome.no_candidate,
        },
    };
}

fn testTracePackageJob(
    action: u32,
    reason: u32,
    request_ref: ?u32,
    flags: u32,
) abi.RequestTraceJob {
    return .{
        .action = action,
        .selection_kind = abi.selection_kind.package,
        .effective_flags = flags,
        .reason = reason,
        .request_ref = request_ref orelse 0,
        .has_request_ref = @intFromBool(request_ref != null),
    };
}

fn testTraceNameJob(
    action: u32,
    name: []const u8,
    reason: u32,
    request_ref: ?u32,
    flags: u32,
) abi.RequestTraceJob {
    return .{
        .selection_value = testBytes(name),
        .action = action,
        .selection_kind = abi.selection_kind.name,
        .effective_flags = flags,
        .reason = reason,
        .request_ref = request_ref orelse 0,
        .has_request_ref = @intFromBool(request_ref != null),
    };
}

fn testTraceCapabilityJob(
    action: u32,
    relation: metadata.Relation,
    reason: u32,
    request_ref: ?u32,
) abi.RequestTraceJob {
    return .{
        .capability = testCapability(relation),
        .action = action,
        .selection_kind = abi.selection_kind.capability,
        .reason = reason,
        .request_ref = request_ref orelse 0,
        .has_request_ref = @intFromBool(request_ref != null),
    };
}

fn testQueueOrigin(
    pair: u32,
    job_ref: u32,
    request_ref: ?u32,
) abi.RequestTraceQueueOrigin {
    return .{
        .queue_pair_index = pair,
        .job_ref = job_ref,
        .request_ref = request_ref orelse 0,
        .has_request_ref = @intFromBool(request_ref != null),
    };
}

fn testTrace(
    requests: []const abi.Request,
    jobs: []const abi.RequestTraceJob,
    origins: []const abi.RequestTraceQueueOrigin,
) abi.RequestTraceView {
    return .{
        .requests = optionalPointer(abi.Request, requests),
        .jobs = optionalPointer(abi.RequestTraceJob, jobs),
        .queue_origins = optionalPointer(abi.RequestTraceQueueOrigin, origins),
        .request_count = @intCast(requests.len),
        .job_count = @intCast(jobs.len),
        .queue_origin_count = @intCast(origins.len),
    };
}

fn testBytes(value: []const u8) abi.Bytes {
    if (value.len == 0) return .{};
    return .{ .data = value.ptr, .length = value.len };
}

fn testPackageFromEvr(
    name: []const u8,
    evr: []const u8,
    arch: []const u8,
) metadata.Package {
    const parts = metadata.splitEvrQuery(evr);
    var package = testPackage(name, parts.version, arch);
    package.nevra.epoch = parts.epoch;
    package.nevra.release = parts.release orelse "";
    return package;
}

fn capabilityRelation(
    name: []const u8,
    epoch: ?u32,
    version: []const u8,
    release: ?[]const u8,
) metadata.Relation {
    return .{
        .name = name,
        .flags = "EQ",
        .comparison = .eq,
        .epoch = epoch,
        .version = version,
        .release = release,
    };
}

fn testCapability(relation: metadata.Relation) abi.Capability {
    return .{
        .name = testBytes(relation.name),
        .flags = if (relation.flags) |value| testBytes(value) else .{},
        .version = if (relation.version) |value| testBytes(value) else .{},
        .release = if (relation.release) |value| testBytes(value) else .{},
        .epoch = relation.epoch orelse 0,
        .comparison = compareOp(relation.comparison),
        .sense = relation.sense,
        .has_epoch = @intFromBool(relation.epoch != null),
        .has_flags = @intFromBool(relation.flags != null),
        .has_version = @intFromBool(relation.version != null),
        .has_release = @intFromBool(relation.release != null),
        .pre = @intFromBool(relation.pre),
    };
}

const PackageLookup = struct {
    ref: u32,
    package: *const abi.Package,
};

fn packageByName(
    facts: *const abi.Capture,
    name: []const u8,
    state: u32,
) ?PackageLookup {
    const packages = facts.packages orelse return null;
    for (packages[0..facts.package_count], 0..) |*package, index| {
        if (package.state == state and
            std.mem.eql(u8, bytesOrEmpty(package.identity.name), name))
        {
            return .{ .ref = @intCast(index), .package = package };
        }
    }
    return null;
}

fn repositoryById(
    facts: *const abi.Capture,
    id: []const u8,
) ?abi.Repository {
    const repositories = facts.repositories orelse return null;
    for (repositories[0..facts.repository_count]) |repository| {
        if (std.mem.eql(u8, bytesOrEmpty(repository.id), id)) {
            return repository;
        }
    }
    return null;
}

fn expectPackageEvr(
    package: *const abi.Package,
    parts: metadata.EvrQueryParts,
) !void {
    try testing.expectEqual(
        @as(u32, @intFromBool(parts.epoch != null)),
        package.identity.has_epoch,
    );
    try testing.expectEqual(parts.epoch orelse 0, package.identity.epoch);
    try testing.expectEqualStrings(
        parts.version,
        bytesOrEmpty(package.identity.version),
    );
    try testing.expectEqualStrings(
        parts.release.?,
        bytesOrEmpty(package.identity.release),
    );
}

fn expectPriorNames(
    facts: *const abi.Capture,
    action: abi.Action,
    expected_names: []const []const u8,
) !void {
    try testing.expectEqual(
        @as(u32, @intCast(expected_names.len)),
        action.prior_count,
    );
    var seen = try testing.allocator.alloc(bool, expected_names.len);
    defer testing.allocator.free(seen);
    @memset(seen, false);
    for (0..action.prior_count) |offset| {
        const package_ref = facts.prior_package_refs.?[
            action.prior_offset + @as(u32, @intCast(offset))
        ];
        const name = bytesOrEmpty(facts.packages.?[package_ref].identity.name);
        for (expected_names, 0..) |expected, index| {
            if (!seen[index] and std.mem.eql(u8, name, expected)) {
                seen[index] = true;
                break;
            }
        } else return error.TestUnexpectedResult;
    }
    for (seen) |value| try testing.expect(value);
}
