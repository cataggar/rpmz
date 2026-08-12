const std = @import("std");
const Allocator = std.mem.Allocator;

const canonical_json = @import("canonical_json");
const secret_shape = @import("secret_shape");

pub const schema_v1 = "tdnf.transaction-plan/v1";
pub const schema_v2 = "tdnf.transaction-plan/v2";
/// The resolve-only schema retained for source compatibility. Replay-capable
/// callers must inspect `Plan.schemaName()` or `Plan.isReplayable()`.
pub const schema = schema_v1;
const snapshot_id_prefix = "snapshot-v2-";

pub const ValidationError = error{
    AmbiguousPackageIdentity,
    AmbiguousPrior,
    AmbiguousProblem,
    AmbiguousJob,
    DuplicateId,
    EmptyId,
    IncompletePackageSource,
    InconsistentResolution,
    InvalidAction,
    InvalidChecksum,
    InvalidDigest,
    InvalidExecutionOrder,
    InvalidLocation,
    InvalidSchema,
    InvalidString,
    OutOfMemory,
    UnknownReference,
};

pub const InitError = ValidationError || Allocator.Error;
pub const CanonicalError = Allocator.Error;

pub const RequestKind = enum {
    distro_sync,
    downgrade,
    erase,
    install,
    lock,
    reinstall,
    update,
    update_all,
};

pub const JobAction = enum {
    install,
    erase,
    update,
    downgrade,
    dist_sync,
    reinstall,
    lock,
    multiversion,
    user_installed,
    allow_uninstall,
};

pub const RequestReason = enum {
    user,
    dependency,
    weak_dependency,
    cleanup,
    installonly_limit,
    policy,
};

pub const PackageState = enum {
    available,
    installed,
};

pub const ActionKind = enum {
    downgrade,
    erase,
    install,
    obsolete,
    reinstall,
    upgrade,
};

pub const ActionReason = enum {
    cleanup,
    dependency,
    installonly_limit,
    obsoletes,
    policy,
    user,
    weak_dependency,
};

pub const ExecutionOperation = enum {
    erase,
    install,
    reinstall,
    upgrade,
};

pub const ProblemKind = enum {
    conflict,
    /// Two packages with the same name that cannot be installed together
    /// (libsolv's SOLVER_RULE_PKG_SAME_NAME).
    same_name,
    installonly_limit,
    no_candidate,
    not_installable,
    obsoletes,
    protected_package,
    unsatisfied_requirement,
};

pub const CompareOp = enum {
    eq,
    ge,
    gt,
    le,
    lt,
    none,
};

pub const ResolutionStatus = enum {
    problems,
    resolved,
    resolved_with_skips,
};

pub const RpmdbBackend = enum {
    bdb,
    ndb,
    sqlite,
};

pub const RepositoryKind = enum {
    available,
    installed,
    command_line,
};

pub const Request = struct {
    /// Request IDs are caller-stable semantic identifiers and are serialized.
    id: []const u8,
    kind: RequestKind,
    subject: ?[]const u8,
};

pub const Job = struct {
    /// Capture handle used by action/problem attribution, never serialized.
    id: []const u8,
    action: JobAction,
    selection: Selection,
    flags: JobFlags = .{},
    reason: RequestReason,
    request_id: ?[]const u8,
};

pub const Selection = union(enum) {
    all,
    package: []const u8,
    name: []const u8,
    capability: Capability,
};

pub const JobFlags = struct {
    clean_deps: bool = false,
    force_best: bool = false,
    targeted: bool = false,
    not_by_user: bool = false,
    weak: bool = false,
};

pub const PackageIdentity = struct {
    arch: []const u8,
    /// The metadata distinguishes a missing epoch from an explicit zero.
    epoch: ?u32,
    name: []const u8,
    release: []const u8,
    version: []const u8,
};

pub const Checksum = struct {
    /// Raw checksum kind from the authoritative metadata. This is deliberately
    /// opaque: aliases such as "sha" and "sha1" are distinct identities.
    kind: []const u8,
    is_pkgid: bool = false,
    value: []const u8,
};

/// Both fields retain URI references from authoritative metadata. xml_base is
/// kept distinct from href because callers need the effective XML Base.
pub const PackageLocation = struct {
    href: []const u8,
    xml_base: ?[]const u8,
};

pub const PackageSource = struct {
    checksum: Checksum,
    /// Repository packages retain their replay-safe URI reference. Command-line
    /// packages leave this null so a local capture path never enters the plan.
    location: ?PackageLocation,
    /// The primary metadata package size is optional.
    size: ?u64,
};

pub const Package = struct {
    /// A capture handle only; canonical references are package-N semantic refs.
    id: []const u8,
    identity: PackageIdentity,
    repository_id: []const u8,
    /// Installed packages must carry the exact rpmdb header number. Available
    /// packages must leave it unset.
    rpmdb_hnum: ?u32,
    source: ?PackageSource,
    state: PackageState,
};

pub const Action = struct {
    kind: ActionKind,
    prior_package_ids: []const []const u8,
    reason: ActionReason,
    requested_by_job_id: ?[]const u8,
    target_package_id: []const u8,
};

/// One low-level item in the exact order accepted by the native transaction
/// engine. `action_index` refers to `Data.actions`; canonical v2 documents
/// remap it to a stable `action-N` reference.
pub const ExecutionStep = struct {
    action_index: usize,
    operation: ExecutionOperation,
    package_id: []const u8,
};

pub const Selected = struct {
    /// One member of the final selected package set. This intentionally carries
    /// no request attribution: dependencies and unchanged providers are peers.
    package_id: []const u8,
};

pub const Skipped = struct {
    /// Authoritative solver job capture handle; no inferred skip reason exists.
    job_id: []const u8,
};

pub const Capability = struct {
    /// Solver-neutral owned equivalent of repomd.model.Relation.
    comparison: CompareOp,
    epoch: ?u64,
    flags: ?[]const u8 = null,
    name: []const u8,
    pre: bool = false,
    release: ?[]const u8,
    sense: u32 = 0,
    version: ?[]const u8,
};

pub const Problem = struct {
    /// A capture handle only; canonical problem references are problem-N.
    id: []const u8,
    capability: ?Capability,
    count: u32,
    job_id: ?[]const u8,
    kind: ProblemKind,
    package_id: ?[]const u8,
    related_package_id: ?[]const u8,
};

pub const MinVersionConstraint = struct {
    arch: ?[]const u8,
    epoch: ?u64,
    name: []const u8,
    release: ?[]const u8,
    version: []const u8,
};

pub const Policy = struct {
    allow_erasing: bool,
    allow_multilib: bool,
    all_deps: bool,
    best: bool,
    clean_requirements_on_remove: bool,
    excludes: []const []const u8,
    force_architecture: ?[]const u8,
    include_installed: bool,
    installonly_limit: u32,
    installonly_names: []const []const u8,
    install_weak_dependencies: bool,
    keep_orphans: bool,
    locked_names: []const []const u8,
    min_versions: []const MinVersionConstraint,
    protected_names: []const []const u8,
    skip_broken: bool,
};

pub const RpmdbIdentity = struct {
    backend: RpmdbBackend,
    cookie_sha256: []const u8,
    package_set_sha256: []const u8,
};

pub const Environment = struct {
    architecture: []const u8,
    distro: []const u8,
    policy: Policy,
    releasever: []const u8,
    resolution_status: ResolutionStatus,
    rpmdb: RpmdbIdentity,
};

pub const RepomdIdentity = struct {
    /// The raw repomd checksum, not a digest of this model.
    checksum_sha256: []const u8,
    records: []const MetadataRecord,
    revision: ?[]const u8,
    timestamp: u64,
};

pub const MetadataRecord = struct {
    checksum: ?Checksum,
    database_version: ?u64,
    location: PackageLocation,
    open_checksum: ?Checksum,
    open_size: ?u64,
    record_type: []const u8,
    size: ?u64,
    timestamp: ?u64,
};

pub const SnapshotIdentity = struct {
    id: []const u8,
    metadata_sha256: []const u8,
};

pub const Repository = struct {
    cost: u32,
    id: []const u8,
    kind: RepositoryKind,
    priority: i32,
    repomd: ?RepomdIdentity,
    snapshot: ?SnapshotIdentity,
};

pub const Data = struct {
    actions: []const Action,
    environment: Environment,
    /// Null is the resolve-only v1 representation. A non-null complete native
    /// item permutation is the replay-capable v2 representation.
    execution_steps: ?[]const ExecutionStep = null,
    /// Authoritative native transaction input sequence captured before the
    /// v1 semantic action sort. It is an in-memory bridge to bundle export and
    /// is never serialized; parsed plans therefore leave it empty.
    native_execution_inputs: []const ExecutionStep = &.{},
    hidden_packages: []const []const u8,
    jobs: []const Job,
    packages: []const Package,
    problems: []const Problem,
    repositories: []const Repository,
    requests: []const Request,
    selected: []const Selected,
    skipped: []const Skipped,
};

/// Precomputed capture-handle lookup and canonical semantic package order.
/// The map keys borrow package IDs; callers must keep the package slice alive.
const PackageIndex = struct {
    allocator: Allocator,
    by_id: std.StringHashMapUnmanaged(usize) = .empty,
    sorted: []usize = &.{},
    ranks: []usize = &.{},

    fn init(
        allocator: Allocator,
        packages: []const Package,
    ) ValidationError!PackageIndex {
        var self = PackageIndex{ .allocator = allocator };
        errdefer self.deinit();

        self.sorted = try allocator.alloc(usize, packages.len);
        self.ranks = try allocator.alloc(usize, packages.len);
        for (packages, 0..) |package, index| {
            const entry = try self.by_id.getOrPut(allocator, package.id);
            if (entry.found_existing) return error.DuplicateId;
            entry.value_ptr.* = index;
            self.sorted[index] = index;
        }
        std.mem.sort(usize, self.sorted, packages, packageIndexLessThan);
        for (self.sorted, 0..) |package_index, rank_index| {
            self.ranks[package_index] = rank_index;
        }
        return self;
    }

    fn deinit(self: *PackageIndex) void {
        self.by_id.deinit(self.allocator);
        self.allocator.free(self.sorted);
        self.allocator.free(self.ranks);
        self.* = undefined;
    }

    fn find(
        self: *const PackageIndex,
        packages: []const Package,
        id: []const u8,
    ) ?*const Package {
        const index = self.by_id.get(id) orelse return null;
        return &packages[index];
    }

    fn rank(self: *const PackageIndex, id: []const u8) usize {
        return self.ranks[self.by_id.get(id).?];
    }
};

/// Precomputed capture-handle lookup and canonical semantic job order.
/// The map keys borrow job IDs; callers must keep the job slice alive.
const JobIndex = struct {
    allocator: Allocator,
    by_id: std.StringHashMapUnmanaged(usize) = .empty,
    sorted: []usize = &.{},
    ranks: []usize = &.{},

    fn init(
        allocator: Allocator,
        jobs: []const Job,
        packages: []const Package,
        package_index: *const PackageIndex,
    ) ValidationError!JobIndex {
        var self = JobIndex{ .allocator = allocator };
        errdefer self.deinit();

        self.sorted = try allocator.alloc(usize, jobs.len);
        self.ranks = try allocator.alloc(usize, jobs.len);
        for (jobs, 0..) |job, index| {
            const entry = try self.by_id.getOrPut(allocator, job.id);
            if (entry.found_existing) return error.DuplicateId;
            entry.value_ptr.* = index;
            self.sorted[index] = index;
        }

        const context = JobCompareContext{
            .jobs = jobs,
            .packages = packages,
            .package_index = package_index,
        };

        std.mem.sort(usize, self.sorted, context, jobIndexLessThan);
        for (self.sorted, 0..) |job_index, rank_index| {
            self.ranks[job_index] = rank_index;
        }
        if (self.sorted.len > 1) {
            for (self.sorted[1..], 1..) |job_index, rank_index| {
                const prior_index = self.sorted[rank_index - 1];
                if (compareJob(
                    packages,
                    package_index,
                    jobs[prior_index],
                    jobs[job_index],
                ) == .eq) return error.AmbiguousJob;
            }
        }
        return self;
    }

    fn deinit(self: *JobIndex) void {
        self.by_id.deinit(self.allocator);
        self.allocator.free(self.sorted);
        self.allocator.free(self.ranks);
        self.* = undefined;
    }

    fn find(
        self: *const JobIndex,
        jobs: []const Job,
        id: []const u8,
    ) ?*const Job {
        const index = self.by_id.get(id) orelse return null;
        return &jobs[index];
    }

    fn rank(self: *const JobIndex, id: []const u8) usize {
        return self.ranks[self.by_id.get(id).?];
    }
};

const ActionIndex = struct {
    allocator: Allocator,
    sorted: []usize = &.{},
    ranks: []usize = &.{},

    fn init(
        allocator: Allocator,
        actions: []const Action,
        package_index: *const PackageIndex,
        job_index: *const JobIndex,
    ) Allocator.Error!ActionIndex {
        var self = ActionIndex{ .allocator = allocator };
        errdefer self.deinit();
        self.sorted = try allocator.alloc(usize, actions.len);
        self.ranks = try allocator.alloc(usize, actions.len);
        for (self.sorted, 0..) |*entry, index| entry.* = index;
        std.mem.sort(usize, self.sorted, ActionCompareContext{
            .actions = actions,
            .package_index = package_index,
            .job_index = job_index,
        }, actionIndexLessThan);
        for (self.sorted, 0..) |action_index, rank_index| {
            self.ranks[action_index] = rank_index;
        }
        return self;
    }

    fn deinit(self: *ActionIndex) void {
        self.allocator.free(self.sorted);
        self.allocator.free(self.ranks);
        self.* = undefined;
    }

    fn rank(self: *const ActionIndex, action_index: usize) usize {
        return self.ranks[action_index];
    }
};

/// Owns one immutable snapshot of a validated v1 or v2 plan.
pub const Plan = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    data: Data,
    package_index: PackageIndex,
    job_index: JobIndex,
    action_index: ActionIndex,

    pub fn create(allocator: Allocator, input: Data) InitError!*Plan {
        try validateWithAllocator(allocator, input);

        const self = try allocator.create(Plan);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .data = undefined,
            .package_index = undefined,
            .job_index = undefined,
            .action_index = undefined,
        };
        errdefer self.arena.deinit();
        self.data = try cloneData(self.arena.allocator(), input);
        self.package_index = try PackageIndex.init(
            self.arena.allocator(),
            self.data.packages,
        );
        self.job_index = try JobIndex.init(
            self.arena.allocator(),
            self.data.jobs,
            self.data.packages,
            &self.package_index,
        );
        self.action_index = try ActionIndex.init(
            self.arena.allocator(),
            self.data.actions,
            &self.package_index,
            &self.job_index,
        );
        return self;
    }

    pub fn destroy(self: *Plan) void {
        const allocator = self.allocator;
        self.arena.deinit();
        allocator.destroy(self);
    }

    pub fn model(self: *const Plan) *const Data {
        return &self.data;
    }

    pub fn schemaName(self: *const Plan) []const u8 {
        return if (self.data.execution_steps == null) schema_v1 else schema_v2;
    }

    pub fn isReplayable(self: *const Plan) bool {
        return self.data.execution_steps != null;
    }

    pub fn withExecutionSteps(
        self: *const Plan,
        allocator: Allocator,
        steps: []const ExecutionStep,
    ) InitError!*Plan {
        var data = self.data;
        data.execution_steps = steps;
        return Plan.create(allocator, data);
    }

    pub fn digest(self: *const Plan, allocator: Allocator) CanonicalError![64]u8 {
        const document = try canonicalDocument(
            allocator,
            &self.data,
            &self.package_index,
            &self.job_index,
            &self.action_index,
            false,
            null,
        );
        defer allocator.free(document);
        var bytes: [32]u8 = undefined;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(self.schemaName());
        hasher.update("\x00");
        hasher.update(document);
        hasher.final(&bytes);
        return lowerHex(bytes);
    }

    pub fn canonicalJsonAlloc(self: *const Plan, allocator: Allocator) CanonicalError![]u8 {
        const value = try self.digest(allocator);
        return canonicalDocument(
            allocator,
            &self.data,
            &self.package_index,
            &self.job_index,
            &self.action_index,
            true,
            &value,
        );
    }
};

pub fn validate(data: Data) ValidationError!void {
    return validateWithAllocator(std.heap.page_allocator, data);
}

/// Validate independently captured available-repository facts before they are
/// combined with authoritative solver output into a complete plan.
pub fn validateRepositoryPackageFacts(
    repository: Repository,
    packages: []const Package,
) ValidationError!void {
    try validateRepositories(&.{repository});
    return validatePackages(packages, &.{repository});
}

fn validateWithAllocator(allocator: Allocator, data: Data) ValidationError!void {
    var package_index = try PackageIndex.init(allocator, data.packages);
    defer package_index.deinit();

    try validateEnvironment(data.environment);
    try validateRequests(data.requests);
    try validateRepositories(data.repositories);
    try validatePackagesIndexed(
        allocator,
        data.packages,
        data.repositories,
    );
    var job_index = try validateJobs(
        allocator,
        data.jobs,
        data.packages,
        &package_index,
        data.requests,
    );
    defer job_index.deinit();
    try validateHiddenPackages(
        allocator,
        data.hidden_packages,
        data.packages,
        &package_index,
    );
    try validateActions(
        data.actions,
        data.packages,
        &package_index,
        data.jobs,
        &job_index,
    );
    try validateExecution(
        allocator,
        data.execution_steps,
        data.actions,
        data.packages,
        &package_index,
    );
    try validateSelected(
        allocator,
        data.selected,
        data.packages,
        &package_index,
        data.actions,
        data.environment.resolution_status,
    );
    try validateSkipped(data.skipped, data.actions, data.jobs, &job_index);
    try validateProblems(
        data.problems,
        data.packages,
        &package_index,
        data.jobs,
        &job_index,
    );
    try validateResolution(data);
}

fn validateEnvironment(environment: Environment) ValidationError!void {
    try validateOpaqueText(environment.architecture);
    try validateOpaqueText(environment.distro);
    try validateOpaqueText(environment.releasever);
    try validateExcludeGlobs(environment.policy.excludes);
    try validatePolicyNames(environment.policy.installonly_names);
    try validatePolicyNames(environment.policy.locked_names);
    try validatePolicyNames(environment.policy.protected_names);
    if (environment.policy.force_architecture) |arch| try validateOpaqueText(arch);
    try validateMinVersions(environment.policy.min_versions);
    try validateSha256(environment.rpmdb.cookie_sha256);
    try validateSha256(environment.rpmdb.package_set_sha256);
}

fn validateMinVersions(values: []const MinVersionConstraint) ValidationError!void {
    for (values, 0..) |value, index| {
        try validateOpaqueText(value.name);
        if (value.version.len == 0) {
            if (value.epoch == null or value.release != null) {
                return error.InvalidString;
            }
        } else {
            try validateOpaqueText(value.version);
        }
        if (value.arch) |arch| try validateOpaqueText(arch);
        if (value.release) |release| try validateOpaqueText(release);
        for (values[0..index]) |prior| {
            if (minVersionEqual(prior, value)) return error.DuplicateId;
        }
    }
}

fn validatePolicyNames(names: []const []const u8) ValidationError!void {
    for (names, 0..) |name, index| {
        try validateOpaqueText(name);
        for (names[0..index]) |prior| {
            if (std.mem.eql(u8, prior, name)) return error.DuplicateId;
        }
    }
}

fn validateExcludeGlobs(globs: []const []const u8) ValidationError!void {
    for (globs, 0..) |glob, index| {
        try validateExcludeGlob(glob);
        for (globs[0..index]) |prior| {
            if (std.mem.eql(u8, prior, glob)) return error.DuplicateId;
        }
    }
}

fn validateExcludeGlob(value: []const u8) ValidationError!void {
    try validateOpaqueText(value);

    var in_bracket = false;
    var bracket_has_content = false;
    for (value) |byte| {
        switch (byte) {
            '[' => {
                if (in_bracket) return error.InvalidString;
                in_bracket = true;
                bracket_has_content = false;
            },
            ']' => {
                if (!in_bracket or !bracket_has_content) return error.InvalidString;
                in_bracket = false;
            },
            else => {
                if (in_bracket) bracket_has_content = true;
            },
        }
    }
    if (in_bracket) return error.InvalidString;
}

fn validateRequests(requests: []const Request) ValidationError!void {
    for (requests, 0..) |request, index| {
        try validateId(request.id);
        if (request.subject) |subject| try validateOpaqueText(subject);
        for (requests[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, request.id)) return error.DuplicateId;
        }
    }
}

fn validateJobs(
    allocator: Allocator,
    jobs: []const Job,
    packages: []const Package,
    package_index: *const PackageIndex,
    requests: []const Request,
) ValidationError!JobIndex {
    for (jobs) |job| {
        try validateHandle(job.id);
        try validateSelection(job.selection, packages, package_index);
        if (!validJobSelection(job.action, job.selection)) return error.InconsistentResolution;
        if (job.request_id) |request_id| {
            const request = findRequest(requests, request_id) orelse return error.UnknownReference;
            if (job.reason != .user or !jobMatchesRequest(job, request.*)) {
                return error.InconsistentResolution;
            }
        }
    }

    var job_index = try JobIndex.init(allocator, jobs, packages, package_index);
    errdefer job_index.deinit();
    for (requests) |request| {
        var matched = false;
        for (jobs) |job| {
            if (job.reason == .user and job.request_id != null and
                std.mem.eql(u8, request.id, job.request_id.?) and
                jobMatchesRequest(job, request))
            {
                matched = true;
                break;
            }
        }
        if (!matched) return error.InconsistentResolution;
    }
    return job_index;
}

fn validateSelection(
    selection: Selection,
    packages: []const Package,
    package_index: *const PackageIndex,
) ValidationError!void {
    switch (selection) {
        .all => {},
        .package => |id| {
            try validateHandle(id);
            if (package_index.find(packages, id) == null) return error.UnknownReference;
        },
        .name => |name| try validateOpaqueText(name),
        .capability => |capability| try validateCapability(capability),
    }
}

fn validJobSelection(action: JobAction, selection: Selection) bool {
    return switch (action) {
        .update, .dist_sync, .user_installed => true,
        .allow_uninstall => selection == .package,
        .install, .erase, .downgrade, .reinstall, .lock, .multiversion => selection != .all,
    };
}

fn jobMatchesRequest(job: Job, request: Request) bool {
    return switch (request.kind) {
        .distro_sync => job.action == .dist_sync,
        .downgrade => job.action == .downgrade,
        .erase => job.action == .erase,
        .install => job.action == .install,
        .lock => job.action == .lock,
        .reinstall => job.action == .reinstall,
        .update => job.action == .update,
        .update_all => job.action == .update and job.selection == .all,
    };
}

fn validateRepositories(repositories: []const Repository) ValidationError!void {
    for (repositories, 0..) |repository, index| {
        try validateRepositoryId(repository.id);
        if (repository.priority == std.math.minInt(i32)) return error.InconsistentResolution;
        switch (repository.kind) {
            .available => {
                const repomd = repository.repomd orelse return error.IncompletePackageSource;
                const snapshot = repository.snapshot orelse return error.IncompletePackageSource;
                try validateSha256(repomd.checksum_sha256);
                if (repomd.revision) |revision| try validateOpaqueText(revision);
                if (repomd.records.len == 0) return error.IncompletePackageSource;
                try validateMetadataRecords(repomd.records);
                try validateSnapshotId(snapshot.id);
                try validateSha256(snapshot.metadata_sha256);
            },
            .installed => {
                if (repository.repomd != null or repository.snapshot != null)
                    return error.InconsistentResolution;
            },
            .command_line => {
                if (repository.repomd != null or repository.snapshot != null)
                    return error.InconsistentResolution;
            },
        }
        for (repositories[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, repository.id)) return error.DuplicateId;
        }
    }
}

fn validateMetadataRecords(records: []const MetadataRecord) ValidationError!void {
    for (records, 0..) |record, index| {
        try validateOpaqueText(record.record_type);
        try validateLocation(record.location);
        if (record.checksum) |checksum| try validateChecksum(checksum);
        if (record.open_checksum) |checksum| try validateChecksum(checksum);
        for (records[0..index]) |prior| {
            if (metadataRecordEqual(prior, record)) return error.DuplicateId;
        }
    }
}

fn validatePackages(
    packages: []const Package,
    repositories: []const Repository,
) ValidationError!void {
    return validatePackagesIndexed(
        std.heap.page_allocator,
        packages,
        repositories,
    );
}

fn validatePackagesIndexed(
    allocator: Allocator,
    packages: []const Package,
    repositories: []const Repository,
) ValidationError!void {
    for (packages) |package| {
        try validateHandle(package.id);
        try validatePackageIdentity(package.identity);
        try validateRepositoryId(package.repository_id);
        const repository = findRepository(repositories, package.repository_id) orelse
            return error.UnknownReference;
        switch (package.state) {
            .available => {
                if (package.rpmdb_hnum != null) return error.IncompletePackageSource;
                const source = package.source orelse return error.IncompletePackageSource;
                try validateChecksum(source.checksum);
                switch (repository.kind) {
                    .available => try validateLocation(
                        source.location orelse
                            return error.IncompletePackageSource,
                    ),
                    .command_line => if (source.location != null)
                        return error.IncompletePackageSource,
                    .installed => return error.IncompletePackageSource,
                }
            },
            .installed => {
                const hnum = package.rpmdb_hnum orelse return error.IncompletePackageSource;
                if (repository.kind != .installed or hnum == 0 or package.source != null) {
                    return error.IncompletePackageSource;
                }
            },
        }
    }

    const package_positions = try allocator.alloc(usize, packages.len);
    defer allocator.free(package_positions);
    for (package_positions, 0..) |*position, index| position.* = index;
    std.mem.sort(
        usize,
        package_positions,
        packages,
        authoritativePackageKeyLessThan,
    );
    if (package_positions.len > 1) {
        for (package_positions[1..], 1..) |package_position, rank| {
            const prior_position = package_positions[rank - 1];
            if (ambiguousPackageIdentity(
                packages[prior_position],
                packages[package_position],
            )) return error.AmbiguousPackageIdentity;
        }
    }
}

fn validateHiddenPackages(
    allocator: Allocator,
    hidden: []const []const u8,
    packages: []const Package,
    package_index: *const PackageIndex,
) ValidationError!void {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(allocator);
    for (hidden) |id| {
        try validateHandle(id);
        _ = package_index.find(packages, id) orelse
            return error.UnknownReference;
        const entry = try seen.getOrPut(allocator, id);
        if (entry.found_existing) return error.DuplicateId;
    }
}

fn validateActions(
    actions: []const Action,
    packages: []const Package,
    package_index: *const PackageIndex,
    jobs: []const Job,
    job_index: *const JobIndex,
) ValidationError!void {
    for (actions, 0..) |action, action_index| {
        try validateHandle(action.target_package_id);
        const target = package_index.find(packages, action.target_package_id) orelse
            return error.UnknownReference;
        if (action.requested_by_job_id) |job_id| {
            const job = job_index.find(jobs, job_id) orelse return error.UnknownReference;
            if (action.reason != .obsoletes and !actionReasonMatchesJob(action.reason, job.reason))
                return error.InvalidAction;
        } else if (action.reason == .user) {
            return error.InvalidAction;
        }

        for (action.prior_package_ids, 0..) |prior_id, prior_index| {
            const prior = package_index.find(packages, prior_id) orelse
                return error.UnknownReference;
            if (prior.state != .installed) return error.InvalidAction;
            for (action.prior_package_ids[0..prior_index]) |earlier| {
                if (std.mem.eql(u8, earlier, prior_id)) return error.AmbiguousPrior;
            }
        }

        switch (action.kind) {
            .install => if (target.state != .available or action.prior_package_ids.len != 0) return error.InvalidAction,
            .erase => if (target.state != .installed or action.prior_package_ids.len != 0) return error.InvalidAction,
            .downgrade, .obsolete, .reinstall, .upgrade => {
                if (target.state != .available or action.prior_package_ids.len == 0) return error.InvalidAction;
                try validateActionRelation(
                    action.kind,
                    target.*,
                    action.prior_package_ids,
                    packages,
                    package_index,
                );
            },
        }

        for (actions[0..action_index]) |earlier_action| {
            if (std.mem.eql(u8, action.target_package_id, earlier_action.target_package_id))
                return error.InvalidAction;
            if (compareAction(
                package_index,
                job_index,
                action,
                earlier_action,
            ) == .eq)
                return error.InvalidAction;
        }
    }
}

fn validateExecution(
    allocator: Allocator,
    execution_steps: ?[]const ExecutionStep,
    actions: []const Action,
    packages: []const Package,
    package_index: *const PackageIndex,
) ValidationError!void {
    const steps = execution_steps orelse return;
    var expected_count: usize = 0;
    for (actions) |action| {
        expected_count += 1;
        if ((action.kind == .obsolete or action.kind == .downgrade) and
            action.prior_package_ids.len != 0)
        {
            expected_count += 1;
        }
    }
    if (steps.len != expected_count) return error.InvalidExecutionOrder;

    const seen = try allocator.alloc(bool, expected_count);
    defer allocator.free(seen);
    @memset(seen, false);

    for (steps) |step| {
        if (step.action_index >= actions.len) return error.InvalidExecutionOrder;
        const action = actions[step.action_index];
        _ = package_index.find(packages, step.package_id) orelse
            return error.UnknownReference;

        var ordinal: ?usize = null;
        if (std.mem.eql(u8, step.package_id, action.target_package_id) and
            step.operation == targetExecutionOperation(action.kind))
        {
            ordinal = executionOrdinal(actions, step.action_index, 0);
        } else if (step.operation == .erase and
            (action.kind == .obsolete or action.kind == .downgrade))
        {
            if (std.mem.eql(
                u8,
                action.prior_package_ids[0],
                step.package_id,
            )) {
                ordinal = executionOrdinal(actions, step.action_index, 1);
            }
        }
        const index = ordinal orelse return error.InvalidExecutionOrder;
        if (seen[index]) return error.InvalidExecutionOrder;
        seen[index] = true;
    }
}

fn targetExecutionOperation(kind: ActionKind) ExecutionOperation {
    return switch (kind) {
        .erase => .erase,
        .reinstall => .reinstall,
        .upgrade => .upgrade,
        .downgrade, .install, .obsolete => .install,
    };
}

fn executionOrdinal(
    actions: []const Action,
    action_index: usize,
    offset: usize,
) usize {
    var ordinal: usize = 0;
    for (actions[0..action_index]) |action| {
        ordinal += 1;
        if ((action.kind == .obsolete or action.kind == .downgrade) and
            action.prior_package_ids.len != 0)
        {
            ordinal += 1;
        }
    }
    return ordinal + offset;
}

fn actionReasonMatchesJob(action: ActionReason, job: RequestReason) bool {
    return switch (action) {
        .cleanup => job == .cleanup,
        .dependency => job == .dependency,
        .installonly_limit => job == .installonly_limit,
        .policy => job == .policy,
        .user => job == .user,
        .weak_dependency => job == .weak_dependency,
        .obsoletes => false,
    };
}

fn validateActionRelation(
    kind: ActionKind,
    result: Package,
    prior_ids: []const []const u8,
    packages: []const Package,
    package_index: *const PackageIndex,
) ValidationError!void {
    var reference: ?*const Package = null;
    for (prior_ids) |prior_id| {
        const prior = package_index.find(packages, prior_id).?;
        if (!std.mem.eql(u8, result.identity.name, prior.identity.name)) continue;
        if (reference == null or sameNamePriorPreferred(result, prior.*, reference.?.*)) {
            reference = prior;
        }
    }

    if (kind == .obsolete) {
        if (reference != null) return error.InvalidAction;
        return;
    }

    const prior = reference orelse return error.InvalidAction;
    const cmp = comparePackageEvr(result.identity, prior.identity);
    switch (kind) {
        .reinstall => if (cmp != 0) return error.InvalidAction,
        .upgrade => if (cmp <= 0) return error.InvalidAction,
        .downgrade => if (cmp >= 0) return error.InvalidAction,
        .obsolete, .install, .erase => unreachable,
    }
}

fn sameNamePriorPreferred(
    result: Package,
    candidate: Package,
    current: Package,
) bool {
    const evr = comparePackageEvr(candidate.identity, current.identity);
    if (evr != 0) return evr > 0;

    const candidate_same_arch = std.mem.eql(
        u8,
        candidate.identity.arch,
        result.identity.arch,
    );
    const current_same_arch = std.mem.eql(
        u8,
        current.identity.arch,
        result.identity.arch,
    );
    if (candidate_same_arch != current_same_arch) return candidate_same_arch;

    // All remaining fields are serialized semantics, never capture handles.
    return comparePackage(candidate, current) == .gt;
}

fn validateSelected(
    allocator: Allocator,
    selected: []const Selected,
    packages: []const Package,
    package_index: *const PackageIndex,
    actions: []const Action,
    resolution_status: ResolutionStatus,
) ValidationError!void {
    var selected_ids: std.StringHashMapUnmanaged(void) = .empty;
    defer selected_ids.deinit(allocator);
    var removed_installed_ids: std.StringHashMapUnmanaged(void) = .empty;
    defer removed_installed_ids.deinit(allocator);
    var install_target_ids: std.StringHashMapUnmanaged(void) = .empty;
    defer install_target_ids.deinit(allocator);

    for (selected) |selection| {
        try validateHandle(selection.package_id);
        if (package_index.find(packages, selection.package_id) == null)
            return error.UnknownReference;
        const entry = try selected_ids.getOrPut(allocator, selection.package_id);
        if (entry.found_existing) return error.DuplicateId;
    }

    for (actions) |action| {
        switch (action.kind) {
            .erase => {
                if (selected_ids.contains(action.target_package_id)) {
                    return error.InconsistentResolution;
                }
                try removed_installed_ids.put(
                    allocator,
                    action.target_package_id,
                    {},
                );
            },
            .downgrade, .install, .obsolete, .reinstall, .upgrade => {
                if (!selected_ids.contains(action.target_package_id)) {
                    return error.InconsistentResolution;
                }
                try install_target_ids.put(
                    allocator,
                    action.target_package_id,
                    {},
                );
            },
        }
        for (action.prior_package_ids) |prior_id| {
            if (selected_ids.contains(prior_id)) {
                return error.InconsistentResolution;
            }
            try removed_installed_ids.put(allocator, prior_id, {});
        }
    }

    // transaction_installedresult contains the whole final installed set,
    // including unchanged and policy-hidden installed packages. Problem
    // outcomes have no authoritative final transaction state.
    if (resolution_status == .problems) return;
    for (packages) |package| {
        if (package.state == .installed) {
            if (selected_ids.contains(package.id) ==
                removed_installed_ids.contains(package.id))
            {
                return error.InconsistentResolution;
            }
        } else if (selected_ids.contains(package.id) and
            !install_target_ids.contains(package.id))
        {
            return error.InconsistentResolution;
        }
    }
}

fn validateSkipped(
    skipped: []const Skipped,
    actions: []const Action,
    jobs: []const Job,
    job_index: *const JobIndex,
) ValidationError!void {
    for (skipped, 0..) |skip, index| {
        try validateHandle(skip.job_id);
        if (job_index.find(jobs, skip.job_id) == null) return error.UnknownReference;
        for (actions) |action| {
            if (action.requested_by_job_id) |job_id| {
                if (std.mem.eql(u8, job_id, skip.job_id))
                    return error.InconsistentResolution;
            }
        }
        for (skipped[0..index]) |prior| {
            if (std.mem.eql(u8, prior.job_id, skip.job_id)) return error.DuplicateId;
        }
    }
}

fn validateProblems(
    problems: []const Problem,
    packages: []const Package,
    package_index: *const PackageIndex,
    jobs: []const Job,
    job_index: *const JobIndex,
) ValidationError!void {
    for (problems, 0..) |problem, index| {
        try validateHandle(problem.id);
        if (problem.capability) |capability| try validateCapability(capability);
        if (problem.package_id) |id| {
            try validateHandle(id);
            if (package_index.find(packages, id) == null)
                return error.UnknownReference;
        }
        if (problem.related_package_id) |id| {
            try validateHandle(id);
            if (package_index.find(packages, id) == null)
                return error.UnknownReference;
        }
        if (problem.job_id) |id| {
            try validateHandle(id);
            if (job_index.find(jobs, id) == null) return error.UnknownReference;
        }
        for (problems[0..index]) |prior| {
            if (std.mem.eql(u8, prior.id, problem.id)) return error.DuplicateId;
            if (problemSemanticEqual(
                package_index,
                job_index,
                prior,
                problem,
            )) return error.AmbiguousProblem;
        }
    }
}

fn validateCapability(capability: Capability) ValidationError!void {
    try validateOpaqueText(capability.name);
    if (capability.flags) |flags| try validateOpaqueText(flags);
    if (capability.version) |version| try validateOpaqueText(version);
    if (capability.release) |release| try validateOpaqueText(release);
}

fn validateResolution(data: Data) ValidationError!void {
    switch (data.environment.resolution_status) {
        .resolved => {
            if (data.problems.len != 0 or data.skipped.len != 0) return error.InconsistentResolution;
        },
        .resolved_with_skips => {
            if (data.skipped.len == 0) return error.InconsistentResolution;
            for (data.problems) |problem| {
                const job_id = problem.job_id orelse return error.InconsistentResolution;
                var linked = false;
                for (data.skipped) |skip| {
                    if (std.mem.eql(u8, job_id, skip.job_id)) linked = true;
                }
                if (!linked) return error.InconsistentResolution;
            }
        },
        .problems => {
            if (data.problems.len == 0 or data.actions.len != 0 or
                data.selected.len != 0 or data.skipped.len != 0) return error.InconsistentResolution;
        },
    }
}

fn validateIdList(ids: []const []const u8, requests: []const Request) ValidationError!void {
    for (ids, 0..) |id, index| {
        try validateId(id);
        if (findRequest(requests, id) == null) return error.UnknownReference;
        for (ids[0..index]) |prior| if (std.mem.eql(u8, prior, id)) return error.DuplicateId;
    }
}

fn validatePackageIdentity(identity: PackageIdentity) ValidationError!void {
    try validateOpaqueText(identity.arch);
    try validateOpaqueText(identity.name);
    try validateOpaqueText(identity.release);
    try validateOpaqueText(identity.version);
}

fn validateChecksum(checksum: Checksum) ValidationError!void {
    try validateChecksumText(checksum.kind);
    try validateChecksumText(checksum.value);
}

fn validateSha256(value: []const u8) ValidationError!void {
    try validateLowerHex(value, 64);
}

fn validateLowerHex(value: []const u8, expected_length: usize) ValidationError!void {
    if (value.len != expected_length) return error.InvalidChecksum;
    for (value) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return error.InvalidChecksum;
}

fn validateChecksumText(value: []const u8) ValidationError!void {
    if (value.len > 4096 or !isOpaqueText(value)) return error.InvalidChecksum;
}

fn validateId(value: []const u8) ValidationError!void {
    if (value.len == 0) return error.EmptyId;
    if (!std.unicode.utf8ValidateSlice(value) or std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidString;
    for (value) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '.' and byte != '_' and byte != '+' and byte != '-') return error.InvalidString;
    }
}

fn validateSnapshotId(value: []const u8) ValidationError!void {
    if (!std.mem.startsWith(u8, value, snapshot_id_prefix) or
        value.len != snapshot_id_prefix.len + 64)
    {
        return error.InvalidString;
    }
    for (value[snapshot_id_prefix.len..]) |byte| {
        if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) {
            return error.InvalidString;
        }
    }
}

pub fn validateRepositoryId(value: []const u8) ValidationError!void {
    if (value.len == 0) return error.EmptyId;
    try validateOpaqueText(value);
    if (isAbsoluteHostPath(value) or
        decodedRepositoryIdHasForbiddenShape(value))
    {
        return error.InvalidString;
    }
}

fn validateHandle(value: []const u8) ValidationError!void {
    if (value.len == 0) return error.EmptyId;
    if (!std.unicode.utf8ValidateSlice(value) or std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidString;
    for (value) |byte| if (byte < 0x20 or byte == 0x7f) return error.InvalidString;
}

fn validateOpaqueText(value: []const u8) ValidationError!void {
    if (!isOpaqueText(value)) return error.InvalidString;
}

fn isOpaqueText(value: []const u8) bool {
    if (value.len == 0 or !std.unicode.utf8ValidateSlice(value) or
        std.mem.indexOfScalar(u8, value, 0) != null or
        secret_shape.containsSecretShape(value))
    {
        return false;
    }
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f) return false;
    }
    var codepoints = std.unicode.Utf8View.initUnchecked(value).iterator();
    while (codepoints.nextCodepoint()) |codepoint| {
        if (isUnicodeControl(codepoint)) return false;
    }
    return true;
}

fn isUnicodeControl(codepoint: u21) bool {
    return codepoint <= 0x1f or (codepoint >= 0x7f and codepoint <= 0x9f);
}

fn isUnicodeWhitespace(codepoint: u21) bool {
    return (codepoint >= 0x09 and codepoint <= 0x0d) or
        codepoint == 0x20 or codepoint == 0x85 or codepoint == 0xa0 or
        codepoint == 0x1680 or (codepoint >= 0x2000 and codepoint <= 0x200a) or
        codepoint == 0x2028 or codepoint == 0x2029 or codepoint == 0x202f or
        codepoint == 0x205f or codepoint == 0x3000;
}

fn isAbsoluteHostPath(value: []const u8) bool {
    if (value.len == 0) return false;
    if (value[0] == '/' or value[0] == '\\') return true;
    return value.len >= 3 and std.ascii.isAlphabetic(value[0]) and
        value[1] == ':' and (value[2] == '/' or value[2] == '\\');
}

fn decodedRepositoryIdHasForbiddenShape(value: []const u8) bool {
    var history: [64]u8 = undefined;
    var history_len: usize = 0;
    var next_slot: usize = 0;
    var value_index: usize = 0;
    var decoded_index: usize = 0;
    var first_bytes: [3]u8 = undefined;
    var segment: [16]u8 = undefined;
    var segment_len: usize = 0;
    var segment_has_colon = false;
    var segment_has_at = false;

    while (value_index < value.len) {
        const byte = nextDecodedRepositoryByte(value, &value_index);
        if (decoded_index < first_bytes.len) {
            first_bytes[decoded_index] = byte;
        }
        decoded_index += 1;

        history[next_slot] = std.ascii.toLower(byte);
        next_slot = (next_slot + 1) % history.len;
        if (history_len < history.len) history_len += 1;
        if (secret_shape.decodedRingEndsWith(
            history[0..],
            next_slot,
            history_len,
            "://",
        )) {
            return true;
        }
        for (secret_shape.markers) |marker| {
            if (secret_shape.decodedRingEndsWith(
                history[0..],
                next_slot,
                history_len,
                marker,
            )) {
                return true;
            }
        }

        if (byte == '/' or byte == '\\') {
            if (decoded_index == 1) return true;
            if (segment_has_at) return true;
            segment_len = 0;
            segment_has_colon = false;
            segment_has_at = false;
        } else if (byte == ':') {
            if (isKnownUriScheme(segment[0..segment_len])) return true;
            segment_has_colon = true;
        } else if (byte == '@') {
            if (segment_len != 0 or segment_has_colon) return true;
            segment_has_at = true;
        } else if (!segment_has_colon and segment_len < segment.len) {
            segment[segment_len] = std.ascii.toLower(byte);
            segment_len += 1;
        }
    }

    if (decoded_index >= 3 and
        std.ascii.isAlphabetic(first_bytes[0]) and
        first_bytes[1] == ':' and
        (first_bytes[2] == '/' or first_bytes[2] == '\\'))
    {
        return true;
    }
    return false;
}

fn nextDecodedRepositoryByte(value: []const u8, index: *usize) u8 {
    const byte = value[index.*];
    if (byte == '%' and index.* + 2 < value.len and
        secret_shape.isHex(value[index.* + 1]) and secret_shape.isHex(value[index.* + 2]))
    {
        const decoded = secret_shape.hexByte(value[index.* + 1], value[index.* + 2]);
        index.* += 3;
        return decoded;
    }
    index.* += 1;
    return byte;
}

fn isKnownUriScheme(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "http") or
        std.ascii.eqlIgnoreCase(value, "https") or
        std.ascii.eqlIgnoreCase(value, "file") or
        std.ascii.eqlIgnoreCase(value, "ftp") or
        std.ascii.eqlIgnoreCase(value, "media");
}

fn validateLocation(location: PackageLocation) ValidationError!void {
    try validateUriReference(location.href);
    if (location.xml_base) |xml_base| try validateUriReference(xml_base);
}

/// Validate a raw repository URI reference without retaining credentials or
/// non-replayable URL parts. xml:base accepts absolute HTTP(S) references;
/// href also accepts them because repomd models retain raw URI references.
fn validateUriReference(value: []const u8) ValidationError!void {
    if (value.len == 0 or !std.unicode.utf8ValidateSlice(value) or
        std.mem.indexOfScalar(u8, value, 0) != null)
    {
        return error.InvalidLocation;
    }

    var codepoints = std.unicode.Utf8View.initUnchecked(value).iterator();
    while (codepoints.nextCodepoint()) |codepoint| {
        if (isUnicodeControl(codepoint) or isUnicodeWhitespace(codepoint)) {
            return error.InvalidLocation;
        }
    }

    var first_slash: ?usize = null;
    for (value, 0..) |byte, index| {
        if (byte < 0x20 or byte == 0x7f or byte == ' ' or byte == '\\' or
            byte == '?' or byte == '#')
        {
            return error.InvalidLocation;
        }
        if (byte == '%') {
            if (index + 2 >= value.len or !secret_shape.isHex(value[index + 1]) or !secret_shape.isHex(value[index + 2])) {
                return error.InvalidLocation;
            }
            const decoded = secret_shape.hexByte(value[index + 1], value[index + 2]);
            if (decoded < 0x20 or decoded == 0x7f or decoded == '\\') {
                return error.InvalidLocation;
            }
        }
        if (byte == '/' and first_slash == null) first_slash = index;
    }
    const segment_end = first_slash orelse value.len;
    if (std.mem.indexOfScalar(u8, value[0..segment_end], ':')) |colon| {
        if (colon != 0 and isSchemePrefix(value[0..colon])) {
            const scheme = value[0..colon];
            const is_http = std.ascii.eqlIgnoreCase(scheme, "http") or
                std.ascii.eqlIgnoreCase(scheme, "https");
            const is_media = std.ascii.eqlIgnoreCase(scheme, "media");
            if (!is_http and !is_media) {
                return error.InvalidLocation;
            }
            const after_scheme = value[colon + 1 ..];
            if (!std.mem.startsWith(u8, after_scheme, "//")) return error.InvalidLocation;
            const authority_and_path = after_scheme[2..];
            const path_start = std.mem.indexOfScalar(u8, authority_and_path, '/') orelse authority_and_path.len;
            const authority = authority_and_path[0..path_start];
            if ((is_http and !validHttpAuthority(authority)) or
                (is_media and !validMediaAuthority(authority)))
            {
                return error.InvalidLocation;
            }
            if (secret_shape.decodedUriHasSecretShape(authority_and_path, authority.len)) {
                return error.InvalidLocation;
            }
            return;
        }
    }
    if (value[0] == '/' or std.mem.startsWith(u8, value, "//") or
        secret_shape.decodedUriHasSecretShape(value, null))
    {
        return error.InvalidLocation;
    }
}

fn validHttpAuthority(authority: []const u8) bool {
    if (authority.len == 0 or std.mem.indexOfScalar(u8, authority, '@') != null) {
        return false;
    }

    if (authority[0] == '[') {
        const closing = std.mem.indexOfScalar(u8, authority, ']') orelse return false;
        if (closing == 1) return false;
        const remainder = authority[closing + 1 ..];
        if (std.mem.indexOfScalar(u8, remainder, '[') != null or
            std.mem.indexOfScalar(u8, remainder, ']') != null)
        {
            return false;
        }
        return remainder.len == 0 or
            (remainder[0] == ':' and validHttpPort(remainder[1..]));
    }

    if (std.mem.indexOfAny(u8, authority, "[]") != null) return false;
    const colon = std.mem.indexOfScalar(u8, authority, ':') orelse return true;
    if (colon == 0 or std.mem.indexOfScalar(u8, authority[colon + 1 ..], ':') != null) {
        return false;
    }
    return validHttpPort(authority[colon + 1 ..]);
}

fn validMediaAuthority(authority: []const u8) bool {
    if (authority.len == 0 or
        std.mem.indexOfAny(u8, authority, "[]@") != null)
    {
        return false;
    }
    for (authority) |byte| {
        if (byte == '\\' or byte < 0x20 or byte == 0x7f) {
            return false;
        }
    }
    return true;
}

fn validHttpPort(value: []const u8) bool {
    if (value.len == 0) return false;
    var port: u32 = 0;
    for (value) |byte| {
        if (!std.ascii.isDigit(byte)) return false;
        port = std.math.mul(u32, port, 10) catch return false;
        port = std.math.add(u32, port, byte - '0') catch return false;
        if (port > std.math.maxInt(u16)) return false;
    }
    return true;
}

fn isSchemePrefix(prefix: []const u8) bool {
    if (prefix.len == 0 or !std.ascii.isAlphabetic(prefix[0])) return false;
    for (prefix[1..]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '+' and byte != '-' and byte != '.') return false;
    return true;
}

fn findRequest(requests: []const Request, id: []const u8) ?*const Request {
    for (requests) |*request| if (std.mem.eql(u8, request.id, id)) return request;
    return null;
}

fn findRepository(repositories: []const Repository, id: []const u8) ?*const Repository {
    for (repositories) |*repository| if (std.mem.eql(u8, repository.id, id)) return repository;
    return null;
}

fn comparePackageEvr(left: PackageIdentity, right: PackageIdentity) i32 {
    // RPM EVR ordering normalizes an omitted epoch to zero, while package
    // identity and canonical serialization retain the original null.
    return compareEvr(
        left.epoch orelse 0,
        left.version,
        left.release,
        right.epoch orelse 0,
        right.version,
        right.release,
    );
}

fn compareEvr(
    left_epoch: u32,
    left_version: []const u8,
    left_release: []const u8,
    right_epoch: u32,
    right_version: []const u8,
    right_release: []const u8,
) i32 {
    if (left_epoch < right_epoch) return -1;
    if (left_epoch > right_epoch) return 1;
    const version = compareRpmVersion(left_version, right_version);
    if (version != 0) return version;
    return compareRpmVersion(left_release, right_release);
}

// This is the rpmvercmp algorithm used by repomd/index.zig. It lives here so
// `zig test client/transaction_plan.zig` remains a standalone test target.
fn compareRpmVersion(left_raw: []const u8, right_raw: []const u8) i32 {
    var left = left_raw;
    var right = right_raw;
    while (true) {
        while (left.len != 0 and !isRpmTokenByte(left[0])) left = left[1..];
        while (right.len != 0 and !isRpmTokenByte(right[0])) right = right[1..];
        if ((left.len != 0 and left[0] == '~') or (right.len != 0 and right[0] == '~')) {
            if (left.len == 0 or left[0] != '~') return 1;
            if (right.len == 0 or right[0] != '~') return -1;
            left = left[1..];
            right = right[1..];
            continue;
        }
        if ((left.len != 0 and left[0] == '^') or (right.len != 0 and right[0] == '^')) {
            if (left.len == 0) return -1;
            if (right.len == 0) return 1;
            if (left[0] != '^') return 1;
            if (right[0] != '^') return -1;
            left = left[1..];
            right = right[1..];
            continue;
        }
        if (left.len == 0 and right.len == 0) return 0;
        if (left.len == 0) return -1;
        if (right.len == 0) return 1;
        const left_digit = std.ascii.isDigit(left[0]);
        const right_digit = std.ascii.isDigit(right[0]);
        if (left_digit != right_digit) return if (left_digit) 1 else -1;
        if (left_digit) {
            const left_end = digitRunEnd(left);
            const right_end = digitRunEnd(right);
            const left_digits = trimLeadingZeros(left[0..left_end]);
            const right_digits = trimLeadingZeros(right[0..right_end]);
            left = left[left_end..];
            right = right[right_end..];
            if (left_digits.len < right_digits.len) return -1;
            if (left_digits.len > right_digits.len) return 1;
            const order = std.mem.order(u8, left_digits, right_digits);
            if (order != .eq) return if (order == .lt) -1 else 1;
        } else {
            const left_end = alphaRunEnd(left);
            const right_end = alphaRunEnd(right);
            const order = std.mem.order(u8, left[0..left_end], right[0..right_end]);
            left = left[left_end..];
            right = right[right_end..];
            if (order != .eq) return if (order == .lt) -1 else 1;
        }
    }
}

fn trimLeadingZeros(value: []const u8) []const u8 {
    var index: usize = 0;
    while (index < value.len and value[index] == '0') : (index += 1) {}
    return value[index..];
}

fn digitRunEnd(value: []const u8) usize {
    var index: usize = 0;
    while (index < value.len and std.ascii.isDigit(value[index])) : (index += 1) {}
    return index;
}

fn alphaRunEnd(value: []const u8) usize {
    var index: usize = 0;
    while (index < value.len and std.ascii.isAlphabetic(value[index])) : (index += 1) {}
    return index;
}

fn isRpmTokenByte(value: u8) bool {
    return std.ascii.isAlphanumeric(value) or value == '~' or value == '^';
}

fn ambiguousPackageIdentity(left: Package, right: Package) bool {
    return compareAuthoritativePackageKeys(left, right) == .eq;
}

/// Mirrors repomd/solver_identity.zig's PackageKey sort exactly. The source
/// location and package size are replay data, not solver package identity.
fn authoritativePackageKeyLessThan(
    packages: []const Package,
    left_index: usize,
    right_index: usize,
) bool {
    return compareAuthoritativePackageKeys(
        packages[left_index],
        packages[right_index],
    ) == .lt;
}

fn compareAuthoritativePackageKeys(
    left: Package,
    right: Package,
) std.math.Order {
    if (left.state != right.state) {
        return if (left.state == .installed) .lt else .gt;
    }
    var order = std.mem.order(u8, left.repository_id, right.repository_id);
    if (order != .eq) return order;
    switch (left.state) {
        .installed => return std.math.order(
            left.rpmdb_hnum.?,
            right.rpmdb_hnum.?,
        ),
        .available => {},
    }

    inline for ([_]struct {
        left: []const u8,
        right: []const u8,
    }{
        .{ .left = left.identity.name, .right = right.identity.name },
    }) |pair| {
        order = std.mem.order(u8, pair.left, pair.right);
        if (order != .eq) return order;
    }
    // AvailableKey normalizes an absent epoch for its solver lookup key. The
    // PackageIdentity above deliberately does not do so.
    order = std.math.order(
        left.identity.epoch orelse 0,
        right.identity.epoch orelse 0,
    );
    if (order != .eq) return order;
    inline for ([_]struct {
        left: []const u8,
        right: []const u8,
    }{
        .{ .left = left.identity.version, .right = right.identity.version },
        .{ .left = left.identity.release, .right = right.identity.release },
        .{ .left = left.identity.arch, .right = right.identity.arch },
    }) |pair| {
        order = std.mem.order(u8, pair.left, pair.right);
        if (order != .eq) return order;
    }
    return compareAuthoritativeChecksum(
        left.source.?.checksum,
        right.source.?.checksum,
    );
}

fn compareAuthoritativeChecksum(
    left: Checksum,
    right: Checksum,
) std.math.Order {
    var order = std.mem.order(u8, left.kind, right.kind);
    if (order != .eq) return order;
    order = std.mem.order(u8, left.value, right.value);
    if (order != .eq) return order;
    return compareBool(left.is_pkgid, right.is_pkgid);
}

fn cloneData(allocator: Allocator, input: Data) Allocator.Error!Data {
    return .{
        .actions = try cloneActions(allocator, input.actions),
        .environment = try cloneEnvironment(allocator, input.environment),
        .execution_steps = if (input.execution_steps) |steps|
            try cloneExecutionSteps(allocator, steps)
        else
            null,
        .native_execution_inputs = try cloneExecutionSteps(
            allocator,
            input.native_execution_inputs,
        ),
        .hidden_packages = try cloneStrings(allocator, input.hidden_packages),
        .jobs = try cloneJobs(allocator, input.jobs),
        .packages = try clonePackages(allocator, input.packages),
        .problems = try cloneProblems(allocator, input.problems),
        .repositories = try cloneRepositories(allocator, input.repositories),
        .requests = try cloneRequests(allocator, input.requests),
        .selected = try cloneSelected(allocator, input.selected),
        .skipped = try cloneSkipped(allocator, input.skipped),
    };
}

fn cloneExecutionSteps(
    allocator: Allocator,
    input: []const ExecutionStep,
) Allocator.Error![]ExecutionStep {
    const output = try allocator.alloc(ExecutionStep, input.len);
    for (input, output) |source, *destination| {
        destination.* = .{
            .action_index = source.action_index,
            .operation = source.operation,
            .package_id = try allocator.dupe(u8, source.package_id),
        };
    }
    return output;
}

fn cloneRequests(allocator: Allocator, input: []const Request) Allocator.Error![]Request {
    const output = try allocator.alloc(Request, input.len);
    for (input, output) |source, *destination| destination.* = .{ .id = try allocator.dupe(u8, source.id), .kind = source.kind, .subject = try cloneOptionalString(allocator, source.subject) };
    return output;
}

fn cloneJobs(allocator: Allocator, input: []const Job) Allocator.Error![]Job {
    const output = try allocator.alloc(Job, input.len);
    for (input, output) |source, *destination| destination.* = .{
        .action = source.action,
        .flags = source.flags,
        .id = try allocator.dupe(u8, source.id),
        .reason = source.reason,
        .request_id = try cloneOptionalString(allocator, source.request_id),
        .selection = try cloneSelection(allocator, source.selection),
    };
    return output;
}

fn cloneSelection(allocator: Allocator, input: Selection) Allocator.Error!Selection {
    return switch (input) {
        .all => .all,
        .package => |id| .{ .package = try allocator.dupe(u8, id) },
        .name => |name| .{ .name = try allocator.dupe(u8, name) },
        .capability => |capability| .{ .capability = try cloneCapability(allocator, capability) },
    };
}

fn cloneCapability(allocator: Allocator, capability: Capability) Allocator.Error!Capability {
    return .{
        .comparison = capability.comparison,
        .epoch = capability.epoch,
        .flags = try cloneOptionalString(allocator, capability.flags),
        .name = try allocator.dupe(u8, capability.name),
        .pre = capability.pre,
        .release = try cloneOptionalString(allocator, capability.release),
        .sense = capability.sense,
        .version = try cloneOptionalString(allocator, capability.version),
    };
}

fn clonePackages(allocator: Allocator, input: []const Package) Allocator.Error![]Package {
    const output = try allocator.alloc(Package, input.len);
    for (input, output) |source, *destination| {
        destination.* = .{
            .id = try allocator.dupe(u8, source.id),
            .identity = .{ .arch = try allocator.dupe(u8, source.identity.arch), .epoch = source.identity.epoch, .name = try allocator.dupe(u8, source.identity.name), .release = try allocator.dupe(u8, source.identity.release), .version = try allocator.dupe(u8, source.identity.version) },
            .repository_id = try allocator.dupe(u8, source.repository_id),
            .rpmdb_hnum = source.rpmdb_hnum,
            .source = if (source.source) |package_source| .{ .checksum = .{ .kind = try allocator.dupe(u8, package_source.checksum.kind), .is_pkgid = package_source.checksum.is_pkgid, .value = try allocator.dupe(u8, package_source.checksum.value) }, .location = if (package_source.location) |location| try cloneLocation(allocator, location) else null, .size = package_source.size } else null,
            .state = source.state,
        };
    }
    return output;
}

fn cloneLocation(allocator: Allocator, input: PackageLocation) Allocator.Error!PackageLocation {
    return .{ .href = try allocator.dupe(u8, input.href), .xml_base = try cloneOptionalString(allocator, input.xml_base) };
}

fn cloneActions(allocator: Allocator, input: []const Action) Allocator.Error![]Action {
    const output = try allocator.alloc(Action, input.len);
    for (input, output) |source, *destination| destination.* = .{
        .kind = source.kind,
        .prior_package_ids = try cloneStrings(allocator, source.prior_package_ids),
        .reason = source.reason,
        .requested_by_job_id = try cloneOptionalString(allocator, source.requested_by_job_id),
        .target_package_id = try allocator.dupe(u8, source.target_package_id),
    };
    return output;
}

fn cloneSelected(allocator: Allocator, input: []const Selected) Allocator.Error![]Selected {
    const output = try allocator.alloc(Selected, input.len);
    for (input, output) |source, *destination| destination.* = .{
        .package_id = try allocator.dupe(u8, source.package_id),
    };
    return output;
}

fn cloneSkipped(allocator: Allocator, input: []const Skipped) Allocator.Error![]Skipped {
    const output = try allocator.alloc(Skipped, input.len);
    for (input, output) |source, *destination| {
        destination.* = .{ .job_id = try allocator.dupe(u8, source.job_id) };
    }
    return output;
}

fn cloneProblems(allocator: Allocator, input: []const Problem) Allocator.Error![]Problem {
    const output = try allocator.alloc(Problem, input.len);
    for (input, output) |source, *destination| destination.* = .{
        .capability = if (source.capability) |capability| try cloneCapability(allocator, capability) else null,
        .count = source.count,
        .id = try allocator.dupe(u8, source.id),
        .job_id = try cloneOptionalString(allocator, source.job_id),
        .kind = source.kind,
        .package_id = try cloneOptionalString(allocator, source.package_id),
        .related_package_id = try cloneOptionalString(allocator, source.related_package_id),
    };
    return output;
}

fn cloneEnvironment(allocator: Allocator, input: Environment) Allocator.Error!Environment {
    return .{ .architecture = try allocator.dupe(u8, input.architecture), .distro = try allocator.dupe(u8, input.distro), .policy = try clonePolicy(allocator, input.policy), .releasever = try allocator.dupe(u8, input.releasever), .resolution_status = input.resolution_status, .rpmdb = .{ .backend = input.rpmdb.backend, .cookie_sha256 = try allocator.dupe(u8, input.rpmdb.cookie_sha256), .package_set_sha256 = try allocator.dupe(u8, input.rpmdb.package_set_sha256) } };
}

fn clonePolicy(allocator: Allocator, input: Policy) Allocator.Error!Policy {
    return .{ .allow_erasing = input.allow_erasing, .allow_multilib = input.allow_multilib, .all_deps = input.all_deps, .best = input.best, .clean_requirements_on_remove = input.clean_requirements_on_remove, .excludes = try cloneStrings(allocator, input.excludes), .force_architecture = try cloneOptionalString(allocator, input.force_architecture), .include_installed = input.include_installed, .installonly_limit = input.installonly_limit, .installonly_names = try cloneStrings(allocator, input.installonly_names), .install_weak_dependencies = input.install_weak_dependencies, .keep_orphans = input.keep_orphans, .locked_names = try cloneStrings(allocator, input.locked_names), .min_versions = try cloneMinVersions(allocator, input.min_versions), .protected_names = try cloneStrings(allocator, input.protected_names), .skip_broken = input.skip_broken };
}

fn cloneMinVersions(allocator: Allocator, input: []const MinVersionConstraint) Allocator.Error![]MinVersionConstraint {
    const output = try allocator.alloc(MinVersionConstraint, input.len);
    for (input, output) |source, *destination| destination.* = .{ .arch = try cloneOptionalString(allocator, source.arch), .epoch = source.epoch, .name = try allocator.dupe(u8, source.name), .release = try cloneOptionalString(allocator, source.release), .version = try allocator.dupe(u8, source.version) };
    return output;
}

fn cloneRepositories(allocator: Allocator, input: []const Repository) Allocator.Error![]Repository {
    const output = try allocator.alloc(Repository, input.len);
    for (input, output) |source, *destination| destination.* = .{
        .cost = source.cost,
        .id = try allocator.dupe(u8, source.id),
        .kind = source.kind,
        .priority = source.priority,
        .repomd = if (source.repomd) |repomd| .{
            .checksum_sha256 = try allocator.dupe(u8, repomd.checksum_sha256),
            .records = try cloneMetadataRecords(allocator, repomd.records),
            .revision = try cloneOptionalString(allocator, repomd.revision),
            .timestamp = repomd.timestamp,
        } else null,
        .snapshot = if (source.snapshot) |snapshot| .{
            .id = try allocator.dupe(u8, snapshot.id),
            .metadata_sha256 = try allocator.dupe(u8, snapshot.metadata_sha256),
        } else null,
    };
    return output;
}

fn cloneMetadataRecords(allocator: Allocator, input: []const MetadataRecord) Allocator.Error![]MetadataRecord {
    const output = try allocator.alloc(MetadataRecord, input.len);
    for (input, output) |source, *destination| destination.* = .{ .checksum = try cloneOptionalChecksum(allocator, source.checksum), .database_version = source.database_version, .location = try cloneLocation(allocator, source.location), .open_checksum = try cloneOptionalChecksum(allocator, source.open_checksum), .open_size = source.open_size, .record_type = try allocator.dupe(u8, source.record_type), .size = source.size, .timestamp = source.timestamp };
    return output;
}

fn cloneOptionalChecksum(allocator: Allocator, input: ?Checksum) Allocator.Error!?Checksum {
    return if (input) |checksum| .{ .kind = try allocator.dupe(u8, checksum.kind), .is_pkgid = checksum.is_pkgid, .value = try allocator.dupe(u8, checksum.value) } else null;
}

fn cloneStrings(allocator: Allocator, input: []const []const u8) Allocator.Error![][]const u8 {
    const output = try allocator.alloc([]const u8, input.len);
    for (input, output) |source, *destination| destination.* = try allocator.dupe(u8, source);
    return output;
}

fn cloneOptionalString(allocator: Allocator, input: ?[]const u8) Allocator.Error!?[]const u8 {
    return if (input) |value| try allocator.dupe(u8, value) else null;
}

fn lowerHex(bytes: [32]u8) [64]u8 {
    const alphabet = "0123456789abcdef";
    var result: [64]u8 = undefined;
    for (bytes, 0..) |byte, index| {
        result[index * 2] = alphabet[byte >> 4];
        result[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return result;
}

fn canonicalDocument(
    allocator: Allocator,
    data: *const Data,
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
    action_index: *const ActionIndex,
    include_digest: bool,
    digest_value: ?*const [64]u8,
) Allocator.Error![]u8 {
    var writer = canonical_json.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.append("{\"actions\":");
    try writeActions(
        &writer,
        data,
        package_index,
        job_index,
        action_index,
    );
    const document_schema = if (data.execution_steps == null)
        schema_v1
    else
        schema_v2;
    if (include_digest) {
        try writer.append(",\"digest\":{\"algorithm\":\"sha256\",\"domain\":");
        try writer.writeString(document_schema);
        try writer.append(",\"value\":");
        try writer.writeString(digest_value.?);
        try writer.appendByte('}');
    }
    try writer.append(",\"environment\":");
    try writeEnvironment(&writer, data.environment);
    try writer.append(",\"execution\":");
    try writeExecution(&writer, data, package_index, action_index);
    try writer.append(",\"hidden_packages\":");
    try writePackageRefs(&writer, package_index, data.hidden_packages);
    try writer.append(",\"jobs\":");
    try writeJobs(&writer, data, package_index, job_index);
    try writer.append(",\"packages\":");
    try writePackages(&writer, data, package_index);
    try writer.append(",\"problems\":");
    try writeProblems(&writer, data, package_index, job_index);
    try writer.append(",\"repositories\":");
    try writeRepositories(&writer, data.repositories);
    try writer.append(",\"requests\":");
    try writeRequests(&writer, data.requests);
    try writer.append(",\"schema\":");
    try writer.writeString(document_schema);
    try writer.append(",\"selected\":");
    try writeSelected(&writer, data, package_index);
    try writer.append(",\"skipped\":");
    try writeSkipped(&writer, job_index, data.skipped);
    try writer.appendByte('}');
    return writer.finish();
}

fn writeActions(
    writer: *canonical_json.Writer,
    data: *const Data,
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
    action_index: *const ActionIndex,
) Allocator.Error!void {
    try writer.appendByte('[');
    for (action_index.sorted, 0..) |position, index| {
        const action = data.actions[position];
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"kind\":");
        try writer.writeString(@tagName(action.kind));
        if (data.execution_steps != null) {
            try writer.append(",\"id\":\"action-");
            try writer.writeUint(index);
            try writer.appendByte('"');
        }
        try writer.append(",\"prior_package_ids\":");
        try writePackageRefs(writer, package_index, action.prior_package_ids);
        try writer.append(",\"reason\":");
        try writer.writeString(@tagName(action.reason));
        try writer.append(",\"requested_by_job_id\":");
        if (action.requested_by_job_id) |id| try writeJobRef(
            writer,
            job_index,
            id,
        ) else try writer.append("null");
        try writer.append(",\"target_package_id\":");
        try writePackageRef(writer, package_index, action.target_package_id);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeExecution(
    writer: *canonical_json.Writer,
    data: *const Data,
    package_index: *const PackageIndex,
    action_index: *const ActionIndex,
) Allocator.Error!void {
    const steps = data.execution_steps orelse {
        try writer.append("{\"status\":\"unmaterialized\"}");
        return;
    };
    try writer.append("{\"status\":\"materialized\",\"steps\":[");
    for (steps, 0..) |step, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"action_id\":\"action-");
        try writer.writeUint(action_index.rank(step.action_index));
        try writer.append("\",\"operation\":");
        try writer.writeString(@tagName(step.operation));
        try writer.append(",\"package_id\":");
        try writePackageRef(writer, package_index, step.package_id);
        try writer.appendByte('}');
    }
    try writer.append("]}");
}

fn writeEnvironment(writer: *canonical_json.Writer, environment: Environment) Allocator.Error!void {
    try writer.append("{\"architecture\":");
    try writer.writeString(environment.architecture);
    try writer.append(",\"distro\":");
    try writer.writeString(environment.distro);
    try writer.append(",\"policy\":");
    try writePolicy(writer, environment.policy);
    try writer.append(",\"releasever\":");
    try writer.writeString(environment.releasever);
    try writer.append(",\"resolution_status\":");
    try writer.writeString(@tagName(environment.resolution_status));
    try writer.append(",\"rpmdb\":{\"backend\":");
    try writer.writeString(@tagName(environment.rpmdb.backend));
    try writer.append(",\"cookie_sha256\":");
    try writer.writeString(environment.rpmdb.cookie_sha256);
    try writer.append(",\"package_set_sha256\":");
    try writer.writeString(environment.rpmdb.package_set_sha256);
    try writer.append("}}");
}

fn writePolicy(writer: *canonical_json.Writer, policy: Policy) Allocator.Error!void {
    try writer.append("{\"all_deps\":");
    try writer.writeBool(policy.all_deps);
    try writer.append(",\"allow_erasing\":");
    try writer.writeBool(policy.allow_erasing);
    try writer.append(",\"allow_multilib\":");
    try writer.writeBool(policy.allow_multilib);
    try writer.append(",\"best\":");
    try writer.writeBool(policy.best);
    try writer.append(",\"clean_requirements_on_remove\":");
    try writer.writeBool(policy.clean_requirements_on_remove);
    try writer.append(",\"excludes\":");
    try writeStringArray(writer, policy.excludes);
    try writer.append(",\"force_architecture\":");
    try writer.writeOptionalString(policy.force_architecture);
    try writer.append(",\"include_installed\":");
    try writer.writeBool(policy.include_installed);
    try writer.append(",\"install_weak_dependencies\":");
    try writer.writeBool(policy.install_weak_dependencies);
    try writer.append(",\"installonly_limit\":");
    try writer.writeUint(policy.installonly_limit);
    try writer.append(",\"installonly_names\":");
    try writeStringArray(writer, policy.installonly_names);
    try writer.append(",\"keep_orphans\":");
    try writer.writeBool(policy.keep_orphans);
    try writer.append(",\"locked_names\":");
    try writeStringArray(writer, policy.locked_names);
    try writer.append(",\"min_versions\":");
    try writeMinVersions(writer, policy.min_versions);
    try writer.append(",\"protected_names\":");
    try writeStringArray(writer, policy.protected_names);
    try writer.append(",\"skip_broken\":");
    try writer.writeBool(policy.skip_broken);
    try writer.appendByte('}');
}

fn writeMinVersions(writer: *canonical_json.Writer, input: []const MinVersionConstraint) Allocator.Error!void {
    const values = try writer.allocator.dupe(MinVersionConstraint, input);
    defer writer.allocator.free(values);
    std.mem.sort(MinVersionConstraint, values, {}, minVersionLessThan);
    try writer.appendByte('[');
    for (values, 0..) |value, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"arch\":");
        try writer.writeOptionalString(value.arch);
        try writer.append(",\"epoch\":");
        if (value.epoch) |epoch| try writer.writeUint(epoch) else try writer.append("null");
        try writer.append(",\"name\":");
        try writer.writeString(value.name);
        try writer.append(",\"release\":");
        try writer.writeOptionalString(value.release);
        try writer.append(",\"version\":");
        try writer.writeString(value.version);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeJobs(
    writer: *canonical_json.Writer,
    data: *const Data,
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
) Allocator.Error!void {
    try writer.appendByte('[');
    for (job_index.sorted, 0..) |job_position, index| {
        const job = data.jobs[job_position];
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"action\":");
        try writer.writeString(@tagName(job.action));
        try writer.append(",\"flags\":{\"clean_deps\":");
        try writer.writeBool(job.flags.clean_deps);
        try writer.append(",\"force_best\":");
        try writer.writeBool(job.flags.force_best);
        try writer.append(",\"not_by_user\":");
        try writer.writeBool(job.flags.not_by_user);
        try writer.append(",\"targeted\":");
        try writer.writeBool(job.flags.targeted);
        try writer.append(",\"weak\":");
        try writer.writeBool(job.flags.weak);
        try writer.append("},\"id\":\"job-");
        try writer.writeUint(index);
        try writer.append("\",\"reason\":");
        try writer.writeString(@tagName(job.reason));
        try writer.append(",\"request_id\":");
        try writer.writeOptionalString(job.request_id);
        try writer.append(",\"selection\":");
        try writeSelection(writer, package_index, job.selection);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeSelection(
    writer: *canonical_json.Writer,
    package_index: *const PackageIndex,
    selection: Selection,
) Allocator.Error!void {
    switch (selection) {
        .all => try writer.append("{\"kind\":\"all\"}"),
        .package => |id| {
            try writer.append("{\"kind\":\"package\",\"package_id\":");
            try writePackageRef(writer, package_index, id);
            try writer.appendByte('}');
        },
        .name => |name| {
            try writer.append("{\"kind\":\"name\",\"name\":");
            try writer.writeString(name);
            try writer.appendByte('}');
        },
        .capability => |capability| {
            try writer.append("{\"capability\":");
            try writeCapability(writer, capability);
            try writer.append(",\"kind\":\"capability\"}");
        },
    }
}

fn writePackages(
    writer: *canonical_json.Writer,
    data: *const Data,
    package_index: *const PackageIndex,
) Allocator.Error!void {
    try writer.appendByte('[');
    for (package_index.sorted, 0..) |package_position, index| {
        const package = data.packages[package_position];
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"id\":\"package-");
        try writer.writeUint(index);
        try writer.append("\",\"identity\":{\"arch\":");
        try writer.writeString(package.identity.arch);
        try writer.append(",\"epoch\":");
        if (package.identity.epoch) |epoch| {
            try writer.writeUint(epoch);
        } else {
            try writer.append("null");
        }
        try writer.append(",\"name\":");
        try writer.writeString(package.identity.name);
        try writer.append(",\"release\":");
        try writer.writeString(package.identity.release);
        try writer.append(",\"version\":");
        try writer.writeString(package.identity.version);
        try writer.append("},\"repository_id\":");
        try writer.writeString(package.repository_id);
        try writer.append(",\"rpmdb_hnum\":");
        if (package.rpmdb_hnum) |hnum| try writer.writeUint(hnum) else try writer.append("null");
        try writer.append(",\"source\":");
        try writePackageSource(writer, package.source);
        try writer.append(",\"state\":");
        try writer.writeString(@tagName(package.state));
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writePackageSource(writer: *canonical_json.Writer, source: ?PackageSource) Allocator.Error!void {
    if (source) |value| {
        try writer.append("{\"checksum\":{\"is_pkgid\":");
        try writer.writeBool(value.checksum.is_pkgid);
        try writer.append(",\"kind\":");
        try writer.writeString(value.checksum.kind);
        try writer.append(",\"value\":");
        try writer.writeString(value.checksum.value);
        try writer.append("},\"location\":");
        if (value.location) |location| {
            try writer.append("{\"href\":");
            try writer.writeString(location.href);
            try writer.append(",\"xml_base\":");
            try writer.writeOptionalString(location.xml_base);
            try writer.appendByte('}');
        } else try writer.append("null");
        try writer.append(",\"size\":");
        if (value.size) |size| {
            try writer.writeUint(size);
        } else {
            try writer.append("null");
        }
        try writer.appendByte('}');
    } else try writer.append("null");
}

fn writeProblems(
    writer: *canonical_json.Writer,
    data: *const Data,
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
) Allocator.Error!void {
    const problems = try writer.allocator.dupe(Problem, data.problems);
    defer writer.allocator.free(problems);
    const context = CompareContext{
        .package_index = package_index,
        .job_index = job_index,
    };
    std.mem.sort(Problem, problems, context, problemLessThan);
    try writer.appendByte('[');
    for (problems, 0..) |problem, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"capability\":");
        try writeCapability(writer, problem.capability);
        try writer.append(",\"count\":");
        try writer.writeUint(problem.count);
        try writer.append(",\"id\":\"problem-");
        try writer.writeUint(index);
        try writer.append("\",\"job_id\":");
        if (problem.job_id) |id| try writeJobRef(
            writer,
            job_index,
            id,
        ) else try writer.append("null");
        try writer.append(",\"kind\":");
        try writer.writeString(@tagName(problem.kind));
        try writer.append(",\"package_id\":");
        if (problem.package_id) |id| try writePackageRef(
            writer,
            package_index,
            id,
        ) else try writer.append("null");
        try writer.append(",\"related_package_id\":");
        if (problem.related_package_id) |id| try writePackageRef(
            writer,
            package_index,
            id,
        ) else try writer.append("null");
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeCapability(writer: *canonical_json.Writer, capability: ?Capability) Allocator.Error!void {
    if (capability) |value| {
        try writer.append("{\"comparison\":");
        try writer.writeString(@tagName(value.comparison));
        try writer.append(",\"epoch\":");
        if (value.epoch) |epoch| try writer.writeUint(epoch) else try writer.append("null");
        try writer.append(",\"flags\":");
        try writer.writeOptionalString(value.flags);
        try writer.append(",\"name\":");
        try writer.writeString(value.name);
        try writer.append(",\"pre\":");
        try writer.writeBool(value.pre);
        try writer.append(",\"release\":");
        try writer.writeOptionalString(value.release);
        try writer.append(",\"sense\":");
        try writer.writeUint(value.sense);
        try writer.append(",\"version\":");
        try writer.writeOptionalString(value.version);
        try writer.appendByte('}');
    } else try writer.append("null");
}

fn writeRepositories(writer: *canonical_json.Writer, input: []const Repository) Allocator.Error!void {
    const repositories = try writer.allocator.dupe(Repository, input);
    defer writer.allocator.free(repositories);
    std.mem.sort(Repository, repositories, {}, repositoryLessThan);
    try writer.appendByte('[');
    for (repositories, 0..) |repository, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"cost\":");
        try writer.writeUint(repository.cost);
        try writer.append(",\"id\":");
        try writer.writeString(repository.id);
        try writer.append(",\"kind\":");
        try writer.writeString(@tagName(repository.kind));
        try writer.append(",\"priority\":");
        try writer.writeInt(repository.priority);
        try writer.append(",\"repomd\":");
        if (repository.repomd) |repomd| {
            try writer.append("{\"checksum_sha256\":");
            try writer.writeString(repomd.checksum_sha256);
            try writer.append(",\"records\":");
            try writeMetadataRecords(writer, repomd.records);
            try writer.append(",\"revision\":");
            try writer.writeOptionalString(repomd.revision);
            try writer.append(",\"timestamp\":");
            try writer.writeUint(repomd.timestamp);
            try writer.appendByte('}');
        } else try writer.append("null");
        try writer.append(",\"snapshot\":");
        if (repository.snapshot) |snapshot| {
            try writer.append("{\"id\":");
            try writer.writeString(snapshot.id);
            try writer.append(",\"metadata_sha256\":");
            try writer.writeString(snapshot.metadata_sha256);
            try writer.appendByte('}');
        } else try writer.append("null");
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeMetadataRecords(writer: *canonical_json.Writer, input: []const MetadataRecord) Allocator.Error!void {
    const records = try writer.allocator.dupe(MetadataRecord, input);
    defer writer.allocator.free(records);
    std.mem.sort(MetadataRecord, records, {}, metadataRecordLessThan);
    try writer.appendByte('[');
    for (records, 0..) |record, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"checksum\":");
        try writeOptionalChecksum(writer, record.checksum);
        try writer.append(",\"database_version\":");
        if (record.database_version) |value| try writer.writeUint(value) else try writer.append("null");
        try writer.append(",\"location\":{\"href\":");
        try writer.writeString(record.location.href);
        try writer.append(",\"xml_base\":");
        try writer.writeOptionalString(record.location.xml_base);
        try writer.append("},\"open_checksum\":");
        try writeOptionalChecksum(writer, record.open_checksum);
        try writer.append(",\"open_size\":");
        if (record.open_size) |value| try writer.writeUint(value) else try writer.append("null");
        try writer.append(",\"record_type\":");
        try writer.writeString(record.record_type);
        try writer.append(",\"size\":");
        if (record.size) |value| try writer.writeUint(value) else try writer.append("null");
        try writer.append(",\"timestamp\":");
        if (record.timestamp) |value| try writer.writeUint(value) else try writer.append("null");
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeOptionalChecksum(writer: *canonical_json.Writer, checksum: ?Checksum) Allocator.Error!void {
    if (checksum) |value| {
        try writer.append("{\"is_pkgid\":");
        try writer.writeBool(value.is_pkgid);
        try writer.append(",\"kind\":");
        try writer.writeString(value.kind);
        try writer.append(",\"value\":");
        try writer.writeString(value.value);
        try writer.appendByte('}');
    } else try writer.append("null");
}

fn writeRequests(writer: *canonical_json.Writer, input: []const Request) Allocator.Error!void {
    const requests = try writer.allocator.dupe(Request, input);
    defer writer.allocator.free(requests);
    std.mem.sort(Request, requests, {}, requestLessThan);
    try writer.appendByte('[');
    for (requests, 0..) |request, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"id\":");
        try writer.writeString(request.id);
        try writer.append(",\"kind\":");
        try writer.writeString(@tagName(request.kind));
        try writer.append(",\"subject\":");
        try writer.writeOptionalString(request.subject);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeSelected(
    writer: *canonical_json.Writer,
    data: *const Data,
    package_index: *const PackageIndex,
) Allocator.Error!void {
    const selected = try writer.allocator.dupe(Selected, data.selected);
    defer writer.allocator.free(selected);
    std.mem.sort(Selected, selected, package_index, selectedLessThan);
    try writer.appendByte('[');
    for (selected, 0..) |selection, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"package_id\":");
        try writePackageRef(writer, package_index, selection.package_id);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeSkipped(
    writer: *canonical_json.Writer,
    job_index: *const JobIndex,
    input: []const Skipped,
) Allocator.Error!void {
    const skipped = try writer.allocator.dupe(Skipped, input);
    defer writer.allocator.free(skipped);
    std.mem.sort(Skipped, skipped, job_index, skippedLessThan);
    try writer.appendByte('[');
    for (skipped, 0..) |skip, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.append("{\"job_id\":");
        try writeJobRef(writer, job_index, skip.job_id);
        try writer.appendByte('}');
    }
    try writer.appendByte(']');
}

fn writeStringArray(writer: *canonical_json.Writer, input: []const []const u8) Allocator.Error!void {
    const strings = try writer.allocator.dupe([]const u8, input);
    defer writer.allocator.free(strings);
    std.mem.sort([]const u8, strings, {}, stringLessThan);
    try writer.appendByte('[');
    for (strings, 0..) |value, index| {
        if (index != 0) try writer.appendByte(',');
        try writer.writeString(value);
    }
    try writer.appendByte(']');
}

fn writePackageRefs(
    writer: *canonical_json.Writer,
    package_index: *const PackageIndex,
    input: []const []const u8,
) Allocator.Error!void {
    const ids = try writer.allocator.dupe([]const u8, input);
    defer writer.allocator.free(ids);
    std.mem.sort([]const u8, ids, package_index, packageIdLessThan);
    try writer.appendByte('[');
    for (ids, 0..) |id, index| {
        if (index != 0) try writer.appendByte(',');
        try writePackageRef(writer, package_index, id);
    }
    try writer.appendByte(']');
}

fn packageIdLessThan(
    package_index: *const PackageIndex,
    left_id: []const u8,
    right_id: []const u8,
) bool {
    return package_index.rank(left_id) < package_index.rank(right_id);
}

fn writePackageRef(
    writer: *canonical_json.Writer,
    package_index: *const PackageIndex,
    id: []const u8,
) Allocator.Error!void {
    try writer.append("\"package-");
    try writer.writeUint(package_index.rank(id));
    try writer.appendByte('"');
}

fn writeJobRef(
    writer: *canonical_json.Writer,
    job_index: *const JobIndex,
    id: []const u8,
) Allocator.Error!void {
    try writer.append("\"job-");
    try writer.writeUint(job_index.rank(id));
    try writer.appendByte('"');
}

pub const ParseError = error{
    MalformedJson,
    NotCanonical,
} || ValidationError || Allocator.Error;

const WireDigest = struct {
    algorithm: []const u8,
    domain: []const u8,
    value: []const u8,
};

const WireAction = struct {
    kind: ActionKind,
    id: ?[]const u8 = null,
    prior_package_ids: []const []const u8,
    reason: ActionReason,
    requested_by_job_id: ?[]const u8,
    target_package_id: []const u8,
};

const WireSelectionKind = enum {
    all,
    package,
    name,
    capability,
};

const WireSelection = struct {
    capability: ?Capability = null,
    kind: WireSelectionKind,
    name: ?[]const u8 = null,
    package_id: ?[]const u8 = null,
};

const WireJob = struct {
    action: JobAction,
    flags: JobFlags,
    id: []const u8,
    reason: RequestReason,
    request_id: ?[]const u8,
    selection: WireSelection,
};

const WireExecutionStatus = enum {
    materialized,
    unmaterialized,
};

const WireExecutionStep = struct {
    action_id: []const u8,
    operation: ExecutionOperation,
    package_id: []const u8,
};

const WireExecution = struct {
    status: WireExecutionStatus,
    steps: []const WireExecutionStep = &.{},
};

const WireDocument = struct {
    actions: []const WireAction,
    digest: WireDigest,
    environment: Environment,
    execution: WireExecution,
    hidden_packages: []const []const u8,
    jobs: []const WireJob,
    packages: []const Package,
    problems: []const Problem,
    repositories: []const Repository,
    requests: []const Request,
    schema: []const u8,
    selected: []const Selected,
    skipped: []const Skipped,
};

/// Parses only canonical v1 or v2 bytes. Re-serialization is required to match
/// byte-for-byte, so alternate whitespace, key order, unknown fields, forged
/// digests, and non-canonical references are all refused.
pub fn parse(allocator: Allocator, bytes: []const u8) ParseError!*Plan {
    var parsed = std.json.parseFromSlice(
        WireDocument,
        allocator,
        bytes,
        .{},
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.MalformedJson,
    };
    defer parsed.deinit();
    const wire = parsed.value;

    const is_v1 = std.mem.eql(u8, wire.schema, schema_v1);
    const is_v2 = std.mem.eql(u8, wire.schema, schema_v2);
    if (!is_v1 and !is_v2) return error.InvalidSchema;
    if (!std.mem.eql(u8, wire.digest.algorithm, "sha256") or
        !std.mem.eql(u8, wire.digest.domain, wire.schema))
    {
        return error.InvalidDigest;
    }
    validateSha256(wire.digest.value) catch return error.InvalidDigest;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const scratch = arena_state.allocator();
    const actions = try parseActions(scratch, wire.actions, is_v2);
    const data: Data = .{
        .actions = actions,
        .environment = wire.environment,
        .execution_steps = try parseExecution(
            scratch,
            wire.execution,
            wire.actions,
            actions,
            is_v2,
        ),
        .native_execution_inputs = &.{},
        .hidden_packages = wire.hidden_packages,
        .jobs = try parseJobs(scratch, wire.jobs),
        .packages = wire.packages,
        .problems = wire.problems,
        .repositories = wire.repositories,
        .requests = wire.requests,
        .selected = wire.selected,
        .skipped = wire.skipped,
    };
    const plan = try Plan.create(allocator, data);
    errdefer plan.destroy();
    if (!std.mem.eql(u8, plan.schemaName(), wire.schema)) {
        return error.InvalidSchema;
    }
    const canonical = try plan.canonicalJsonAlloc(allocator);
    defer allocator.free(canonical);
    if (!std.mem.eql(u8, canonical, bytes)) return error.NotCanonical;
    return plan;
}

fn parseActions(
    allocator: Allocator,
    input: []const WireAction,
    require_ids: bool,
) ParseError![]const Action {
    const output = try allocator.alloc(Action, input.len);
    for (input, output, 0..) |source, *destination, index| {
        if (require_ids) {
            const id = source.id orelse return error.MalformedJson;
            if (try parseCanonicalRef(id, "action") != index) {
                return error.NotCanonical;
            }
        } else if (source.id != null) {
            return error.NotCanonical;
        }
        destination.* = .{
            .kind = source.kind,
            .prior_package_ids = source.prior_package_ids,
            .reason = source.reason,
            .requested_by_job_id = source.requested_by_job_id,
            .target_package_id = source.target_package_id,
        };
    }
    return output;
}

fn parseJobs(
    allocator: Allocator,
    input: []const WireJob,
) ParseError![]const Job {
    const output = try allocator.alloc(Job, input.len);
    for (input, output) |source, *destination| {
        destination.* = .{
            .id = source.id,
            .action = source.action,
            .selection = try parseSelection(source.selection),
            .flags = source.flags,
            .reason = source.reason,
            .request_id = source.request_id,
        };
    }
    return output;
}

fn parseSelection(input: WireSelection) ParseError!Selection {
    return switch (input.kind) {
        .all => if (input.capability == null and input.name == null and
            input.package_id == null)
            .all
        else
            error.MalformedJson,
        .package => if (input.capability == null and input.name == null)
            .{ .package = input.package_id orelse return error.MalformedJson }
        else
            error.MalformedJson,
        .name => if (input.capability == null and input.package_id == null)
            .{ .name = input.name orelse return error.MalformedJson }
        else
            error.MalformedJson,
        .capability => if (input.name == null and input.package_id == null)
            .{ .capability = input.capability orelse return error.MalformedJson }
        else
            error.MalformedJson,
    };
}

fn parseExecution(
    allocator: Allocator,
    input: WireExecution,
    wire_actions: []const WireAction,
    actions: []const Action,
    is_v2: bool,
) ParseError!?[]const ExecutionStep {
    if (!is_v2) {
        if (input.status != .unmaterialized or input.steps.len != 0) {
            return error.NotCanonical;
        }
        return null;
    }
    if (input.status != .materialized) return error.NotCanonical;
    const output = try allocator.alloc(ExecutionStep, input.steps.len);
    for (input.steps, output) |source, *destination| {
        const action_index = try parseCanonicalRef(source.action_id, "action");
        if (action_index >= actions.len or
            wire_actions[action_index].id == null or
            !std.mem.eql(
                u8,
                wire_actions[action_index].id.?,
                source.action_id,
            ))
        {
            return error.InvalidExecutionOrder;
        }
        destination.* = .{
            .action_index = action_index,
            .operation = source.operation,
            .package_id = source.package_id,
        };
    }
    return output;
}

fn parseCanonicalRef(
    value: []const u8,
    comptime prefix: []const u8,
) ParseError!usize {
    const marker = prefix ++ "-";
    if (!std.mem.startsWith(u8, value, marker) or value.len == marker.len) {
        return error.MalformedJson;
    }
    const digits = value[marker.len..];
    if (digits.len > 1 and digits[0] == '0') return error.NotCanonical;
    return std.fmt.parseUnsigned(usize, digits, 10) catch
        return error.MalformedJson;
}

fn stringLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
fn requestLessThan(_: void, left: Request, right: Request) bool {
    return std.mem.lessThan(u8, left.id, right.id);
}
fn repositoryLessThan(_: void, left: Repository, right: Repository) bool {
    return std.mem.lessThan(u8, left.id, right.id);
}
fn skippedLessThan(
    job_index: *const JobIndex,
    left: Skipped,
    right: Skipped,
) bool {
    return job_index.rank(left.job_id) < job_index.rank(right.job_id);
}
fn packageLessThan(_: void, left: Package, right: Package) bool {
    return comparePackage(left, right) == .lt;
}
fn packageIndexLessThan(
    packages: []const Package,
    left: usize,
    right: usize,
) bool {
    return comparePackage(packages[left], packages[right]) == .lt;
}
fn metadataRecordLessThan(_: void, left: MetadataRecord, right: MetadataRecord) bool {
    return compareMetadataRecord(left, right) == .lt;
}
fn minVersionLessThan(_: void, left: MinVersionConstraint, right: MinVersionConstraint) bool {
    return compareMinVersion(left, right) == .lt;
}

const CompareContext = struct {
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
};

const JobCompareContext = struct {
    jobs: []const Job,
    packages: []const Package,
    package_index: *const PackageIndex,
};

const ActionCompareContext = struct {
    actions: []const Action,
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
};

fn actionIndexLessThan(
    context: ActionCompareContext,
    left_index: usize,
    right_index: usize,
) bool {
    return compareAction(
        context.package_index,
        context.job_index,
        context.actions[left_index],
        context.actions[right_index],
    ) == .lt;
}

fn jobIndexLessThan(
    context: JobCompareContext,
    left_index: usize,
    right_index: usize,
) bool {
    return compareJob(
        context.packages,
        context.package_index,
        context.jobs[left_index],
        context.jobs[right_index],
    ) == .lt;
}
fn problemLessThan(context: CompareContext, left: Problem, right: Problem) bool {
    return compareProblem(
        context.package_index,
        context.job_index,
        left,
        right,
    ) == .lt;
}
fn selectedLessThan(
    package_index: *const PackageIndex,
    left: Selected,
    right: Selected,
) bool {
    return package_index.rank(left.package_id) <
        package_index.rank(right.package_id);
}
fn actionLessThan(context: CompareContext, left: Action, right: Action) bool {
    return compareAction(
        context.package_index,
        context.job_index,
        left,
        right,
    ) == .lt;
}

fn comparePackage(left: Package, right: Package) std.math.Order {
    var order = std.mem.order(u8, left.identity.name, right.identity.name);
    if (order != .eq) return order;
    order = std.mem.order(u8, left.identity.arch, right.identity.arch);
    if (order != .eq) return order;
    const evr = comparePackageEvr(left.identity, right.identity);
    if (evr != 0) return if (evr < 0) .lt else .gt;
    order = compareOptionalU32(left.identity.epoch, right.identity.epoch);
    if (order != .eq) return order;
    order = std.mem.order(u8, left.identity.version, right.identity.version);
    if (order != .eq) return order;
    order = std.mem.order(u8, left.identity.release, right.identity.release);
    if (order != .eq) return order;
    order = std.mem.order(u8, @tagName(left.state), @tagName(right.state));
    if (order != .eq) return order;
    order = std.mem.order(u8, left.repository_id, right.repository_id);
    if (order != .eq) return order;
    order = std.math.order(left.rpmdb_hnum orelse 0, right.rpmdb_hnum orelse 0);
    if (order != .eq) return order;
    if (left.source) |left_source| {
        if (right.source) |right_source| {
            order = compareOptionalLocations(
                left_source.location,
                right_source.location,
            );
            if (order != .eq) return order;
            order = compareChecksum(
                left_source.checksum,
                right_source.checksum,
            );
            if (order != .eq) return order;
            order = compareOptionalUint(left_source.size, right_source.size);
            if (order != .eq) return order;
        } else return .gt;
    } else if (right.source != null) return .lt;
    return .eq;
}

fn compareJob(
    packages: []const Package,
    package_index: *const PackageIndex,
    left: Job,
    right: Job,
) std.math.Order {
    var order = std.mem.order(u8, @tagName(left.action), @tagName(right.action));
    if (order != .eq) return order;
    order = compareSelection(
        packages,
        package_index,
        left.selection,
        right.selection,
    );
    if (order != .eq) return order;
    inline for (.{ "clean_deps", "force_best", "not_by_user", "targeted", "weak" }) |field| {
        order = compareBool(@field(left.flags, field), @field(right.flags, field));
        if (order != .eq) return order;
    }
    order = std.mem.order(u8, @tagName(left.reason), @tagName(right.reason));
    if (order != .eq) return order;
    return compareOptionalStrings(left.request_id, right.request_id);
}

fn compareSelection(
    packages: []const Package,
    package_index: *const PackageIndex,
    left: Selection,
    right: Selection,
) std.math.Order {
    _ = packages;
    const order = std.mem.order(u8, @tagName(left), @tagName(right));
    if (order != .eq) return order;
    return switch (left) {
        .all => .eq,
        .package => |left_id| std.math.order(
            package_index.rank(left_id),
            package_index.rank(right.package),
        ),
        .name => |left_name| std.mem.order(u8, left_name, right.name),
        .capability => |left_capability| compareOptionalCapability(
            left_capability,
            right.capability,
        ),
    };
}

fn compareAction(
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
    left: Action,
    right: Action,
) std.math.Order {
    var order = std.mem.order(u8, @tagName(left.kind), @tagName(right.kind));
    if (order != .eq) return order;
    order = std.math.order(
        package_index.rank(left.target_package_id),
        package_index.rank(right.target_package_id),
    );
    if (order != .eq) return order;
    order = comparePackageIdSets(
        package_index,
        left.prior_package_ids,
        right.prior_package_ids,
    );
    if (order != .eq) return order;
    order = std.mem.order(u8, @tagName(left.reason), @tagName(right.reason));
    if (order != .eq) return order;
    return compareOptionalJobIds(
        job_index,
        left.requested_by_job_id,
        right.requested_by_job_id,
    );
}

fn compareProblem(
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
    left: Problem,
    right: Problem,
) std.math.Order {
    var order = compareOptionalCapability(left.capability, right.capability);
    if (order != .eq) return order;
    order = std.math.order(left.count, right.count);
    if (order != .eq) return order;
    order = compareOptionalJobIds(
        job_index,
        left.job_id,
        right.job_id,
    );
    if (order != .eq) return order;
    order = std.mem.order(u8, @tagName(left.kind), @tagName(right.kind));
    if (order != .eq) return order;
    order = compareOptionalPackageIds(
        package_index,
        left.package_id,
        right.package_id,
    );
    if (order != .eq) return order;
    return compareOptionalPackageIds(
        package_index,
        left.related_package_id,
        right.related_package_id,
    );
}

fn compareOptionalPackageIds(
    package_index: *const PackageIndex,
    left: ?[]const u8,
    right: ?[]const u8,
) std.math.Order {
    if (left == null) return if (right == null) .eq else .lt;
    if (right == null) return .gt;
    return std.math.order(package_index.rank(left.?), package_index.rank(right.?));
}

fn compareOptionalJobIds(
    job_index: *const JobIndex,
    left: ?[]const u8,
    right: ?[]const u8,
) std.math.Order {
    if (left == null) return if (right == null) .eq else .lt;
    if (right == null) return .gt;
    return std.math.order(job_index.rank(left.?), job_index.rank(right.?));
}

fn compareOptionalCapability(left: ?Capability, right: ?Capability) std.math.Order {
    if (left == null) return if (right == null) .eq else .lt;
    if (right == null) return .gt;
    var order = std.mem.order(u8, @tagName(left.?.comparison), @tagName(right.?.comparison));
    if (order != .eq) return order;
    order = compareOptionalUint(left.?.epoch, right.?.epoch);
    if (order != .eq) return order;
    order = compareOptionalStrings(left.?.flags, right.?.flags);
    if (order != .eq) return order;
    order = std.mem.order(u8, left.?.name, right.?.name);
    if (order != .eq) return order;
    order = compareBool(left.?.pre, right.?.pre);
    if (order != .eq) return order;
    order = compareOptionalStrings(left.?.release, right.?.release);
    if (order != .eq) return order;
    order = std.math.order(left.?.sense, right.?.sense);
    if (order != .eq) return order;
    return compareOptionalStrings(left.?.version, right.?.version);
}

fn compareOptionalStrings(left: ?[]const u8, right: ?[]const u8) std.math.Order {
    if (left == null) return if (right == null) .eq else .lt;
    if (right == null) return .gt;
    return std.mem.order(u8, left.?, right.?);
}

fn compareBool(left: bool, right: bool) std.math.Order {
    if (left == right) return .eq;
    return if (left) .gt else .lt;
}

fn compareStringSets(left: []const []const u8, right: []const []const u8) std.math.Order {
    if (left.len < right.len) return .lt;
    if (left.len > right.len) return .gt;
    for (0..left.len) |index| {
        const left_value = kthString(left, index);
        const right_value = kthString(right, index);
        const order = std.mem.order(u8, left_value.?, right_value.?);
        if (order != .eq) return order;
    }
    return .eq;
}

fn kthString(values: []const []const u8, index: usize) ?[]const u8 {
    for (values) |candidate| {
        var less_count: usize = 0;
        for (values) |other| {
            if (std.mem.lessThan(u8, other, candidate)) less_count += 1;
        }
        if (less_count == index) return candidate;
    }
    return null;
}

fn comparePackageIdSets(
    package_index: *const PackageIndex,
    left: []const []const u8,
    right: []const []const u8,
) std.math.Order {
    if (left.len < right.len) return .lt;
    if (left.len > right.len) return .gt;
    for (0..left.len) |index| {
        const left_rank = kthPackageRank(package_index, left, index);
        const right_rank = kthPackageRank(package_index, right, index);
        const order = std.math.order(left_rank.?, right_rank.?);
        if (order != .eq) return order;
    }
    return .eq;
}

fn kthPackageRank(
    package_index: *const PackageIndex,
    values: []const []const u8,
    index: usize,
) ?usize {
    for (values) |candidate| {
        var less_count: usize = 0;
        const candidate_rank = package_index.rank(candidate);
        for (values) |other| {
            if (package_index.rank(other) < candidate_rank) less_count += 1;
        }
        if (less_count == index) return candidate_rank;
    }
    return null;
}

fn compareMetadataRecord(left: MetadataRecord, right: MetadataRecord) std.math.Order {
    var order = std.mem.order(u8, left.record_type, right.record_type);
    if (order != .eq) return order;
    order = compareLocation(left.location, right.location);
    if (order != .eq) return order;
    order = compareOptionalChecksum(left.checksum, right.checksum);
    if (order != .eq) return order;
    order = compareOptionalChecksum(left.open_checksum, right.open_checksum);
    if (order != .eq) return order;
    order = compareOptionalUint(left.timestamp, right.timestamp);
    if (order != .eq) return order;
    order = compareOptionalUint(left.size, right.size);
    if (order != .eq) return order;
    order = compareOptionalUint(left.open_size, right.open_size);
    if (order != .eq) return order;
    return compareOptionalUint(left.database_version, right.database_version);
}

fn compareLocation(left: PackageLocation, right: PackageLocation) std.math.Order {
    const order = std.mem.order(u8, left.href, right.href);
    if (order != .eq) return order;
    return compareOptionalStrings(left.xml_base, right.xml_base);
}
fn compareOptionalLocations(
    left: ?PackageLocation,
    right: ?PackageLocation,
) std.math.Order {
    if (left == null) return if (right == null) .eq else .lt;
    if (right == null) return .gt;
    return compareLocation(left.?, right.?);
}
fn compareOptionalChecksum(left: ?Checksum, right: ?Checksum) std.math.Order {
    if (left == null) return if (right == null) .eq else .lt;
    if (right == null) return .gt;
    return compareChecksum(left.?, right.?);
}
fn compareChecksum(left: Checksum, right: Checksum) std.math.Order {
    var order = std.mem.order(u8, left.kind, right.kind);
    if (order != .eq) return order;
    order = std.mem.order(u8, left.value, right.value);
    if (order != .eq) return order;
    return compareBool(left.is_pkgid, right.is_pkgid);
}
fn compareOptionalUint(left: ?u64, right: ?u64) std.math.Order {
    if (left == null) return if (right == null) .eq else .lt;
    if (right == null) return .gt;
    return std.math.order(left.?, right.?);
}
fn compareOptionalU32(left: ?u32, right: ?u32) std.math.Order {
    if (left == null) return if (right == null) .eq else .lt;
    if (right == null) return .gt;
    return std.math.order(left.?, right.?);
}
fn metadataRecordEqual(left: MetadataRecord, right: MetadataRecord) bool {
    return compareMetadataRecord(left, right) == .eq;
}

fn compareMinVersion(left: MinVersionConstraint, right: MinVersionConstraint) std.math.Order {
    var order = std.mem.order(u8, left.name, right.name);
    if (order != .eq) return order;
    order = compareOptionalStrings(left.arch, right.arch);
    if (order != .eq) return order;
    order = compareOptionalUint(left.epoch, right.epoch);
    if (order != .eq) return order;
    order = std.mem.order(u8, left.version, right.version);
    if (order != .eq) return order;
    return compareOptionalStrings(left.release, right.release);
}
fn minVersionEqual(left: MinVersionConstraint, right: MinVersionConstraint) bool {
    return compareMinVersion(left, right) == .eq;
}
fn problemSemanticEqual(
    package_index: *const PackageIndex,
    job_index: *const JobIndex,
    left: Problem,
    right: Problem,
) bool {
    return compareProblem(
        package_index,
        job_index,
        left,
        right,
    ) == .eq;
}

const test_sha_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const test_sha_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const test_sha_c = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

fn testPolicy() Policy {
    return .{ .allow_erasing = false, .allow_multilib = true, .all_deps = false, .best = true, .clean_requirements_on_remove = true, .excludes = &.{}, .force_architecture = null, .include_installed = true, .installonly_limit = 3, .installonly_names = &.{ "kernel", "kernel-devel" }, .install_weak_dependencies = true, .keep_orphans = true, .locked_names = &.{}, .min_versions = &.{}, .protected_names = &.{ "systemd", "tdnf" }, .skip_broken = false };
}

fn testData() Data {
    return .{
        .actions = &.{
            .{ .kind = .upgrade, .prior_package_ids = &.{ "old", "old2" }, .reason = .user, .requested_by_job_id = "job-update", .target_package_id = "new" },
            .{ .kind = .install, .prior_package_ids = &.{}, .reason = .user, .requested_by_job_id = "job-install", .target_package_id = "extra" },
        },
        .environment = .{ .architecture = "x86_64", .distro = "photon", .policy = testPolicy(), .releasever = "5.0", .resolution_status = .resolved, .rpmdb = .{ .backend = .sqlite, .cookie_sha256 = test_sha_a, .package_set_sha256 = test_sha_b } },
        .hidden_packages = &.{},
        .jobs = &.{
            .{ .id = "job-update", .action = .update, .selection = .{ .name = "alpha" }, .flags = .{ .force_best = true }, .reason = .user, .request_id = "req-update" },
            .{ .id = "job-multi", .action = .multiversion, .selection = .{ .name = "alpha" }, .reason = .policy, .request_id = null },
            .{ .id = "job-install", .action = .install, .selection = .{ .package = "extra" }, .reason = .user, .request_id = "req-install" },
        },
        .packages = &.{
            .{ .id = "new", .identity = .{ .arch = "x86_64", .epoch = 0, .name = "alpha", .release = "1", .version = "2.0" }, .repository_id = "base", .rpmdb_hnum = null, .source = .{ .checksum = .{ .kind = "sha256", .is_pkgid = true, .value = test_sha_c }, .location = .{ .href = "dir/alpha.rpm", .xml_base = "../pool" }, .size = 10 }, .state = .available },
            .{ .id = "old", .identity = .{ .arch = "x86_64", .epoch = 0, .name = "alpha", .release = "1", .version = "1.0" }, .repository_id = "@System", .rpmdb_hnum = 10, .source = null, .state = .installed },
            .{ .id = "old2", .identity = .{ .arch = "x86_64", .epoch = 0, .name = "alpha", .release = "1", .version = "0.9" }, .repository_id = "@System", .rpmdb_hnum = 11, .source = null, .state = .installed },
            .{ .id = "extra", .identity = .{ .arch = "x86_64", .epoch = 0, .name = "extra", .release = "1", .version = "1.0" }, .repository_id = "base", .rpmdb_hnum = null, .source = .{ .checksum = .{ .kind = "sha256", .is_pkgid = false, .value = test_sha_a }, .location = .{ .href = "dir/extra:tag%20.rpm", .xml_base = "base" }, .size = 11 }, .state = .available },
        },
        .problems = &.{},
        .repositories = &.{
            .{ .cost = 1000, .id = "base", .kind = .available, .priority = 10, .repomd = .{ .checksum_sha256 = test_sha_a, .records = &.{.{ .checksum = .{ .kind = "sha256", .value = test_sha_b }, .database_version = null, .location = .{ .href = "repodata/primary.xml.zst", .xml_base = null }, .open_checksum = null, .open_size = null, .record_type = "primary", .size = 12, .timestamp = 42 }}, .revision = "rev-1", .timestamp = 42 }, .snapshot = .{ .id = "snapshot-v2-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .metadata_sha256 = test_sha_b } },
            .{ .cost = 0, .id = "@System", .kind = .installed, .priority = 0, .repomd = null, .snapshot = null },
        },
        .requests = &.{
            .{ .id = "req-update", .kind = .update, .subject = "alpha" },
            .{ .id = "req-install", .kind = .install, .subject = "extra" },
        },
        .selected = &.{
            .{ .package_id = "new" },
            .{ .package_id = "extra" },
        },
        .skipped = &.{},
    };
}

fn expectJsonContains(json: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, json, needle) != null);
}

// Pins the canonical form of the fixture against accidental change. The
// digest is a compatibility promise: every published plan and every consumer
// digest depends on these exact bytes, so a diff here is either a deliberate
// schema change or a bug. It is deliberately a literal, not a recomputation.
test "canonical plan bytes and digest are pinned" {
    const pinned_digest =
        "d877e827a85ea4f3c5e0895aab0dd9c4943e424e7d5424a75bbc5c624d8eac71";
    const instance = try Plan.create(std.testing.allocator, testData());
    defer instance.destroy();
    const digest_value = try instance.digest(std.testing.allocator);
    try std.testing.expectEqualStrings(pinned_digest, &digest_value);

    const json = try instance.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    // The document embeds the digest it is hashed without.
    try expectJsonContains(json, "\"value\":\"" ++ pinned_digest ++ "\"");
    try expectJsonContains(json, "\"domain\":\"" ++ schema ++ "\"");
}

test "strict parser preserves v1 and replay-capable v2" {
    const v1 = try Plan.create(std.testing.allocator, testData());
    defer v1.destroy();
    const v1_json = try v1.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(v1_json);
    const parsed_v1 = try parse(std.testing.allocator, v1_json);
    defer parsed_v1.destroy();
    try std.testing.expect(!parsed_v1.isReplayable());
    try std.testing.expectEqualStrings(schema_v1, parsed_v1.schemaName());

    const steps = [_]ExecutionStep{
        .{ .action_index = 1, .operation = .install, .package_id = "extra" },
        .{ .action_index = 0, .operation = .upgrade, .package_id = "new" },
    };
    const v2 = try v1.withExecutionSteps(std.testing.allocator, &steps);
    defer v2.destroy();
    const v2_json = try v2.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(v2_json);
    try expectJsonContains(v2_json, "\"schema\":\"" ++ schema_v2 ++ "\"");
    try expectJsonContains(v2_json, "\"id\":\"action-0\"");
    try expectJsonContains(v2_json, "\"status\":\"materialized\"");

    const parsed_v2 = try parse(std.testing.allocator, v2_json);
    defer parsed_v2.destroy();
    try std.testing.expect(parsed_v2.isReplayable());
    try std.testing.expectEqualStrings(schema_v2, parsed_v2.schemaName());
    try std.testing.expectEqual(@as(usize, 2), parsed_v2.model().execution_steps.?.len);
    try std.testing.expectEqual(
        ExecutionOperation.install,
        parsed_v2.model().execution_steps.?[0].operation,
    );

    const padded = try std.fmt.allocPrint(
        std.testing.allocator,
        " {s}",
        .{v2_json},
    );
    defer std.testing.allocator.free(padded);
    try std.testing.expectError(error.NotCanonical, parse(std.testing.allocator, padded));

    const tampered = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        v2_json,
        "\"operation\":\"install\"",
        "\"operation\":\"erase\"",
    );
    defer std.testing.allocator.free(tampered);
    try std.testing.expectError(
        error.InvalidExecutionOrder,
        parse(std.testing.allocator, tampered),
    );
}

test "canonical plan is semantic and input-order independent" {
    const first = try Plan.create(std.testing.allocator, testData());
    defer first.destroy();
    const first_json = try first.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(first_json);

    var data = testData();
    var packages = [_]Package{ data.packages[3], data.packages[1], data.packages[0], data.packages[2] };
    packages[0].id = "renamed-extra";
    packages[1].id = "renamed-old";
    packages[2].id = "renamed-new";
    packages[3].id = "renamed-old2";
    var jobs = [_]Job{ data.jobs[2], data.jobs[1], data.jobs[0] };
    jobs[0].id = "renamed-install-job";
    jobs[0].selection = .{ .package = "renamed-extra" };
    jobs[1].id = "renamed-policy-job";
    jobs[2].id = "renamed-update-job";
    var actions = [_]Action{ data.actions[1], data.actions[0] };
    actions[0].target_package_id = "renamed-extra";
    actions[0].requested_by_job_id = "renamed-install-job";
    actions[1].target_package_id = "renamed-new";
    actions[1].prior_package_ids = &.{ "renamed-old2", "renamed-old" };
    actions[1].requested_by_job_id = "renamed-update-job";
    const selected = [_]Selected{
        .{ .package_id = "renamed-extra" },
        .{ .package_id = "renamed-new" },
    };
    data.packages = &packages;
    data.jobs = &jobs;
    data.actions = &actions;
    data.selected = &selected;
    const second = try Plan.create(std.testing.allocator, data);
    defer second.destroy();
    const second_json = try second.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(second_json);
    try std.testing.expectEqualStrings(first_json, second_json);
    try expectJsonContains(first_json, "\"target_package_id\":\"package-");
    try expectJsonContains(first_json, "\"requested_by_job_id\":\"job-");
    try expectJsonContains(first_json, "\"is_pkgid\":true");
}

test "selected is the complete solver result without request attribution" {
    var data = testData();
    const packages = [_]Package{
        data.packages[0],
        data.packages[1],
        data.packages[2],
        data.packages[3],
        .{
            .id = "dependency",
            .identity = .{
                .arch = "noarch",
                .epoch = 0,
                .name = "dependency",
                .release = "1",
                .version = "1",
            },
            .repository_id = "base",
            .rpmdb_hnum = null,
            .source = .{
                .checksum = .{
                    .kind = "sha256",
                    .value = test_sha_b,
                },
                .location = .{
                    .href = "packages/dependency.rpm",
                    .xml_base = null,
                },
                .size = 12,
            },
            .state = .available,
        },
        .{
            .id = "unchanged-provider",
            .identity = .{
                .arch = "x86_64",
                .epoch = 0,
                .name = "provider",
                .release = "1",
                .version = "1",
            },
            .repository_id = "@System",
            .rpmdb_hnum = 12,
            .source = null,
            .state = .installed,
        },
    };
    const selected = [_]Selected{
        .{ .package_id = "unchanged-provider" },
        .{ .package_id = "dependency" },
        data.selected[1],
        data.selected[0],
    };
    const actions = [_]Action{
        data.actions[0],
        data.actions[1],
        .{
            .kind = .install,
            .prior_package_ids = &.{},
            .reason = .dependency,
            .requested_by_job_id = null,
            .target_package_id = "dependency",
        },
    };
    data.packages = &packages;
    data.actions = &actions;
    data.selected = &selected;

    const plan = try Plan.create(std.testing.allocator, data);
    defer plan.destroy();
    const json = try plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try expectJsonContains(json, "\"selected\":[{\"package_id\":\"package-");

    const missing_retained = [_]Selected{
        selected[1],
        selected[2],
        selected[3],
    };
    data.selected = &missing_retained;
    try std.testing.expectError(
        error.InconsistentResolution,
        validate(data),
    );
    data.selected = &selected;

    data.actions = actions[0..2];
    try std.testing.expectError(
        error.InconsistentResolution,
        validate(data),
    );
    data.actions = &actions;

    data.hidden_packages = &.{"unchanged-provider"};
    const hidden = try Plan.create(std.testing.allocator, data);
    defer hidden.destroy();
    try std.testing.expectEqualStrings(
        "unchanged-provider",
        hidden.model().selected[0].package_id,
    );

    data.selected = &.{ selected[0], selected[0] };
    try std.testing.expectError(error.DuplicateId, validate(data));
}

test "resolved selected set covers retained, erased, and shared-obsolete packages" {
    var erase_data = testData();
    const erase_actions = [_]Action{.{
        .kind = .erase,
        .prior_package_ids = &.{},
        .reason = .installonly_limit,
        .requested_by_job_id = null,
        .target_package_id = "old",
    }};
    const erase_selected = [_]Selected{.{ .package_id = "old2" }};
    erase_data.actions = &erase_actions;
    erase_data.selected = &erase_selected;
    try validate(erase_data);

    const erased_selected = [_]Selected{
        .{ .package_id = "old" },
        .{ .package_id = "old2" },
    };
    erase_data.selected = &erased_selected;
    try std.testing.expectError(
        error.InconsistentResolution,
        validate(erase_data),
    );

    var obsolete_data = testData();
    var packages = [_]Package{
        obsolete_data.packages[0],
        obsolete_data.packages[1],
        obsolete_data.packages[2],
        obsolete_data.packages[3],
    };
    packages[0].identity.name = "replacement-a";
    const obsolete_actions = [_]Action{
        .{
            .kind = .obsolete,
            .prior_package_ids = &.{"old"},
            .reason = .obsoletes,
            .requested_by_job_id = null,
            .target_package_id = "new",
        },
        .{
            .kind = .obsolete,
            .prior_package_ids = &.{"old"},
            .reason = .obsoletes,
            .requested_by_job_id = null,
            .target_package_id = "extra",
        },
    };
    const obsolete_selected = [_]Selected{
        .{ .package_id = "new" },
        .{ .package_id = "extra" },
        .{ .package_id = "old2" },
    };
    obsolete_data.packages = &packages;
    obsolete_data.actions = &obsolete_actions;
    obsolete_data.selected = &obsolete_selected;
    try validate(obsolete_data);

    const missing_retained = [_]Selected{
        .{ .package_id = "new" },
        .{ .package_id = "extra" },
    };
    obsolete_data.selected = &missing_retained;
    try std.testing.expectError(
        error.InconsistentResolution,
        validate(obsolete_data),
    );
}

test "action targets and authoritative multi-prior classification validate" {
    const data = testData();
    var data_index = try PackageIndex.init(std.testing.allocator, data.packages);
    defer data_index.deinit();
    var data_job_index = try validateJobs(
        std.testing.allocator,
        data.jobs,
        data.packages,
        &data_index,
        data.requests,
    );
    defer data_job_index.deinit();
    try validateActions(&.{.{ .kind = .install, .prior_package_ids = &.{}, .reason = .policy, .requested_by_job_id = null, .target_package_id = "new" }}, data.packages, &data_index, data.jobs, &data_job_index);
    try validateActions(&.{.{ .kind = .erase, .prior_package_ids = &.{}, .reason = .installonly_limit, .requested_by_job_id = null, .target_package_id = "old" }}, data.packages, &data_index, data.jobs, &data_job_index);
    try std.testing.expectError(error.InvalidAction, validateActions(&.{.{ .kind = .erase, .prior_package_ids = &.{"old2"}, .reason = .policy, .requested_by_job_id = null, .target_package_id = "old" }}, data.packages, &data_index, data.jobs, &data_job_index));

    var packages = [_]Package{ data.packages[0], data.packages[1], data.packages[2], data.packages[3] };
    packages[2].identity.version = "3.0";
    var packages_index = try PackageIndex.init(std.testing.allocator, &packages);
    defer packages_index.deinit();
    var packages_job_index = try validateJobs(
        std.testing.allocator,
        data.jobs,
        &packages,
        &packages_index,
        data.requests,
    );
    defer packages_job_index.deinit();
    try validateActions(&.{.{ .kind = .downgrade, .prior_package_ids = &.{ "old", "old2" }, .reason = .policy, .requested_by_job_id = null, .target_package_id = "new" }}, &packages, &packages_index, data.jobs, &packages_job_index);
    try std.testing.expectError(error.InvalidAction, validateActions(&.{.{ .kind = .upgrade, .prior_package_ids = &.{ "old", "old2" }, .reason = .policy, .requested_by_job_id = null, .target_package_id = "new" }}, &packages, &packages_index, data.jobs, &packages_job_index));

    packages[1].identity.name = "legacy";
    packages[2].identity.name = "legacy-helper";
    const obsoletes = [_]Action{
        .{ .kind = .obsolete, .prior_package_ids = &.{ "old", "old2" }, .reason = .obsoletes, .requested_by_job_id = null, .target_package_id = "new" },
        .{ .kind = .obsolete, .prior_package_ids = &.{"old"}, .reason = .obsoletes, .requested_by_job_id = null, .target_package_id = "extra" },
    };
    try validateActions(&obsoletes, &packages, &packages_index, data.jobs, &packages_job_index);

    const duplicate = Action{ .kind = .install, .prior_package_ids = &.{}, .reason = .policy, .requested_by_job_id = null, .target_package_id = "new" };
    try std.testing.expectError(error.InvalidAction, validateActions(&.{ duplicate, duplicate }, data.packages, &data_index, data.jobs, &data_job_index));

    const base = data.actions[0];
    var changed = base;
    changed.kind = .downgrade;
    try std.testing.expect(compareAction(&data_index, &data_job_index, base, changed) != .eq);
    changed = base;
    changed.target_package_id = "extra";
    try std.testing.expect(compareAction(&data_index, &data_job_index, base, changed) != .eq);
    changed = base;
    changed.prior_package_ids = &.{"old"};
    try std.testing.expect(compareAction(&data_index, &data_job_index, base, changed) != .eq);
    changed = base;
    changed.reason = .obsoletes;
    try std.testing.expect(compareAction(&data_index, &data_job_index, base, changed) != .eq);
    changed = base;
    changed.requested_by_job_id = "job-install";
    try std.testing.expect(compareAction(&data_index, &data_job_index, base, changed) != .eq);
}

test "jobs preserve every solver semantic shape" {
    var data = testData();
    var package_index = try PackageIndex.init(std.testing.allocator, data.packages);
    defer package_index.deinit();
    const capability = Capability{ .comparison = .ge, .epoch = 1, .name = "libfoo.so.1()(64bit)", .release = "2", .version = "3" };
    const jobs = [_]Job{
        data.jobs[0],
        data.jobs[1],
        data.jobs[2],
        .{ .id = "all", .action = .update, .selection = .all, .flags = .{ .clean_deps = true, .targeted = true }, .reason = .policy, .request_id = null },
        .{ .id = "cap", .action = .lock, .selection = .{ .capability = capability }, .flags = .{ .weak = true }, .reason = .policy, .request_id = null },
        .{ .id = "user-installed", .action = .user_installed, .selection = .{ .package = "old" }, .reason = .dependency, .request_id = null },
        .{ .id = "allow", .action = .allow_uninstall, .selection = .{ .package = "old2" }, .flags = .{ .not_by_user = true }, .reason = .policy, .request_id = null },
        .{ .id = "retry-erase", .action = .erase, .selection = .{ .package = "old" }, .reason = .installonly_limit, .request_id = null },
        .{ .id = "downgrade", .action = .downgrade, .selection = .{ .name = "alpha" }, .reason = .cleanup, .request_id = null },
        .{ .id = "dist-sync", .action = .dist_sync, .selection = .all, .reason = .weak_dependency, .request_id = null },
        .{ .id = "reinstall", .action = .reinstall, .selection = .{ .package = "new" }, .reason = .dependency, .request_id = null },
    };
    var jobs_index = try validateJobs(
        std.testing.allocator,
        &jobs,
        data.packages,
        &package_index,
        data.requests,
    );
    defer jobs_index.deinit();
    data.jobs = &jobs;
    const plan = try Plan.create(std.testing.allocator, data);
    defer plan.destroy();
    const json = try plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    for ([_][]const u8{ "\"kind\":\"package\"", "\"kind\":\"all\"", "\"kind\":\"name\"", "\"kind\":\"capability\"", "\"action\":\"user_installed\"", "\"action\":\"allow_uninstall\"", "\"action\":\"multiversion\"", "\"action\":\"lock\"", "\"action\":\"downgrade\"", "\"action\":\"dist_sync\"", "\"action\":\"reinstall\"", "\"reason\":\"installonly_limit\"" }) |needle| try expectJsonContains(json, needle);

    const invalid = Job{ .id = "invalid", .action = .install, .selection = .all, .reason = .policy, .request_id = null };
    try std.testing.expectError(error.InconsistentResolution, validateJobs(std.testing.allocator, &.{ invalid, data.jobs[0], data.jobs[2] }, data.packages, &package_index, data.requests));
    try std.testing.expectError(error.InconsistentResolution, validateJobs(std.testing.allocator, &.{data.jobs[0]}, data.packages, &package_index, data.requests));
    const update_all_request = Request{ .id = "all-request", .kind = .update_all, .subject = null };
    const update_all_job = Job{ .id = "all-user-job", .action = .update, .selection = .all, .reason = .user, .request_id = "all-request" };
    var update_all_index = try validateJobs(
        std.testing.allocator,
        &.{update_all_job},
        data.packages,
        &package_index,
        &.{update_all_request},
    );
    defer update_all_index.deinit();
}

test "job index rejects duplicate and ambiguous capture jobs" {
    const data = testData();
    var package_index = try PackageIndex.init(std.testing.allocator, data.packages);
    defer package_index.deinit();

    const duplicate_ids = [_]Job{ data.jobs[0], data.jobs[0] };
    try std.testing.expectError(
        error.DuplicateId,
        validateJobs(
            std.testing.allocator,
            &duplicate_ids,
            data.packages,
            &package_index,
            data.requests,
        ),
    );

    var ambiguous = [_]Job{
        data.jobs[0],
        data.jobs[1],
        data.jobs[2],
        data.jobs[0],
    };
    ambiguous[3].id = "equivalent-update";
    try std.testing.expectError(
        error.AmbiguousJob,
        validateJobs(
            std.testing.allocator,
            &ambiguous,
            data.packages,
            &package_index,
            data.requests,
        ),
    );

    var job_index = try validateJobs(
        std.testing.allocator,
        data.jobs,
        data.packages,
        &package_index,
        data.requests,
    );
    defer job_index.deinit();
    try std.testing.expect(job_index.find(data.jobs, "job-update") != null);
    try std.testing.expect(job_index.rank("job-update") < data.jobs.len);
}

test "capabilities preserve complete relation semantics" {
    var data = testData();
    var flags = "GE".*;
    const capability_job = Job{
        .id = "relation",
        .action = .lock,
        .selection = .{ .capability = .{
            .comparison = .ge,
            .epoch = 1,
            .flags = &flags,
            .name = "virtual-api",
            .pre = true,
            .release = "3",
            .sense = 7,
            .version = "2",
        } },
        .reason = .policy,
        .request_id = null,
    };
    var jobs = [_]Job{
        data.jobs[0],
        data.jobs[1],
        data.jobs[2],
        capability_job,
    };
    data.jobs = &jobs;

    const original = try Plan.create(std.testing.allocator, data);
    defer original.destroy();
    const original_digest = try original.digest(std.testing.allocator);
    const json = try original.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try expectJsonContains(json, "\"flags\":\"GE\"");
    try expectJsonContains(json, "\"pre\":true");
    try expectJsonContains(json, "\"sense\":7");

    @memset(&flags, 'x');
    const cloned = original.model().jobs[3].selection.capability;
    try std.testing.expectEqualStrings("GE", cloned.flags.?);

    jobs[3].selection.capability.flags = "GT";
    const changed_flags = try Plan.create(std.testing.allocator, data);
    defer changed_flags.destroy();
    const flags_digest = try changed_flags.digest(std.testing.allocator);
    try std.testing.expect(!std.mem.eql(u8, &original_digest, &flags_digest));

    jobs[3].selection.capability.flags = "GE";
    jobs[3].selection.capability.pre = false;
    const changed_pre = try Plan.create(std.testing.allocator, data);
    defer changed_pre.destroy();
    const pre_digest = try changed_pre.digest(std.testing.allocator);
    try std.testing.expect(!std.mem.eql(u8, &original_digest, &pre_digest));

    jobs[3].selection.capability.pre = true;
    jobs[3].selection.capability.sense = 8;
    const changed_sense = try Plan.create(std.testing.allocator, data);
    defer changed_sense.destroy();
    const sense_digest = try changed_sense.digest(std.testing.allocator);
    try std.testing.expect(!std.mem.eql(u8, &original_digest, &sense_digest));

    jobs[3].selection.capability.flags = "token=secret";
    try std.testing.expectError(error.InvalidString, validate(data));

    jobs[3].selection.capability = .{
        .comparison = .none,
        .epoch = null,
        .flags = "versioned",
        .name = "opaque-relation",
        .pre = true,
        .release = null,
        .sense = std.math.maxInt(u32),
        .version = "raw-version",
    };
    try validate(data);
}

test "problem package roles and job attribution are lossless" {
    inline for (.{ ProblemKind.conflict, ProblemKind.obsoletes }) |kind| {
        var first_data = testData();
        first_data.environment.resolution_status = .problems;
        first_data.actions = &.{};
        first_data.selected = &.{};
        first_data.problems = &.{.{ .id = "p", .capability = null, .count = 2, .job_id = "job-update", .kind = kind, .package_id = "old", .related_package_id = "old2" }};
        const first = try Plan.create(std.testing.allocator, first_data);
        defer first.destroy();
        const first_json = try first.canonicalJsonAlloc(std.testing.allocator);
        defer std.testing.allocator.free(first_json);
        const first_digest = try first.digest(std.testing.allocator);

        var second_data = first_data;
        second_data.problems = &.{.{ .id = "other", .capability = null, .count = 2, .job_id = "job-update", .kind = kind, .package_id = "old2", .related_package_id = "old" }};
        const second = try Plan.create(std.testing.allocator, second_data);
        defer second.destroy();
        const second_json = try second.canonicalJsonAlloc(std.testing.allocator);
        defer std.testing.allocator.free(second_json);
        const second_digest = try second.digest(std.testing.allocator);
        try std.testing.expect(!std.mem.eql(u8, first_json, second_json));
        try std.testing.expect(!std.mem.eql(u8, &first_digest, &second_digest));
    }
}

test "hidden packages affect digest but not permutation" {
    var data = testData();
    data.hidden_packages = &.{ "extra", "new" };
    const first = try Plan.create(std.testing.allocator, data);
    defer first.destroy();
    const first_digest = try first.digest(std.testing.allocator);
    data.hidden_packages = &.{ "new", "extra" };
    const permuted = try Plan.create(std.testing.allocator, data);
    defer permuted.destroy();
    const permuted_digest = try permuted.digest(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &first_digest, &permuted_digest);
    data.hidden_packages = &.{"new"};
    const changed = try Plan.create(std.testing.allocator, data);
    defer changed.destroy();
    const changed_digest = try changed.digest(std.testing.allocator);
    try std.testing.expect(!std.mem.eql(u8, &first_digest, &changed_digest));
    data.hidden_packages = &.{"old"};
    try validate(data);
    data.hidden_packages = &.{ "new", "new" };
    try std.testing.expectError(error.DuplicateId, validate(data));
}

test "repository kinds and semantic IDs are enforced" {
    var data = testData();
    try validate(data);
    var repositories = [_]Repository{ data.repositories[0], data.repositories[1] };
    data.repositories = &repositories;
    repositories[0].priority = std.math.minInt(i32);
    try std.testing.expectError(error.InconsistentResolution, validate(data));
    repositories[0] = testData().repositories[0];
    repositories[1].repomd = repositories[0].repomd;
    try std.testing.expectError(error.InconsistentResolution, validate(data));
    repositories[1] = testData().repositories[1];
    repositories[0].repomd = null;
    try std.testing.expectError(error.IncompletePackageSource, validate(data));
    repositories[0] = testData().repositories[0];
    repositories[0].repomd.?.records = &.{};
    try std.testing.expectError(error.IncompletePackageSource, validate(data));
    repositories[0] = testData().repositories[0];
    repositories[0].snapshot.?.id =
        "snapshot-v1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try std.testing.expectError(error.InvalidString, validate(data));
    repositories[0].snapshot.?.id =
        "snapshot-v2-Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try std.testing.expectError(error.InvalidString, validate(data));
    repositories[0].snapshot.?.id =
        "snapshot-v2-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try std.testing.expectError(error.InvalidString, validate(data));
    repositories[0] = testData().repositories[0];
    try validate(data);

    const command_line = Repository{ .cost = 0, .id = "command-line", .kind = .command_line, .priority = 0, .repomd = null, .snapshot = null };
    const pristine = testData();
    try validateRepositories(&.{ pristine.repositories[0], pristine.repositories[1], command_line });
    var package = pristine.packages[0];
    package.repository_id = "command-line";
    package.source.?.location.?.href = "/home/user/local.rpm";
    try std.testing.expectError(error.IncompletePackageSource, validatePackages(&.{package}, &.{command_line}));
    package.source.?.location = null;
    try validatePackages(&.{package}, &.{command_line});

    var command_data = pristine;
    const command_repositories = [_]Repository{
        pristine.repositories[0],
        pristine.repositories[1],
        command_line,
    };
    var packages = [_]Package{
        package,
        pristine.packages[1],
        pristine.packages[2],
        pristine.packages[3],
    };
    packages[0].id = "local-rpm";
    var actions = [_]Action{ pristine.actions[0], pristine.actions[1] };
    actions[0].target_package_id = "local-rpm";
    const selected = [_]Selected{
        .{ .package_id = "local-rpm" },
        pristine.selected[1],
    };
    command_data.repositories = &command_repositories;
    command_data.packages = &packages;
    command_data.actions = &actions;
    command_data.selected = &selected;
    const plan = try Plan.create(std.testing.allocator, command_data);
    defer plan.destroy();
    const json = try plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try expectJsonContains(json, "\"repository_id\":\"command-line\"");
    try expectJsonContains(json, "\"location\":null");
    try std.testing.expect(std.mem.indexOf(u8, json, "/home/user") == null);
}

test "repository IDs are opaque and preserve kind semantics" {
    var data = testData();
    var repositories = [_]Repository{
        data.repositories[0],
        data.repositories[1],
    };
    repositories[0].id = "copr/user/project";
    repositories[1].id = "rpmdb-local";
    var packages = [_]Package{
        data.packages[0],
        data.packages[1],
        data.packages[2],
        data.packages[3],
    };
    packages[0].repository_id = "copr/user/project";
    packages[1].repository_id = "rpmdb-local";
    packages[2].repository_id = "rpmdb-local";
    packages[3].repository_id = "copr/user/project";
    data.repositories = &repositories;
    data.packages = &packages;
    try validate(data);

    const plan = try Plan.create(std.testing.allocator, data);
    defer plan.destroy();
    const json = try plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try expectJsonContains(json, "\"id\":\"copr/user/project\"");
    try expectJsonContains(json, "\"id\":\"rpmdb-local\"");

    for ([_][]const u8{
        "/host/repository",
        "C:/host/repository",
        "C:\\host\\repository",
        "//server/share",
        "\\\\server\\share",
    }) |path| {
        repositories[0].id = path;
        try std.testing.expectError(error.InvalidString, validate(data));
    }
}

test "repository IDs reject URI and credential-shaped values" {
    for ([_][]const u8{
        "copr/user/project",
        "repo:tag",
        "repo%3Atag",
        "@System",
    }) |safe| {
        try validateRepositoryId(safe);
    }

    for ([_][]const u8{
        "https://host/repo",
        "file:///var/cache/repo",
        "ftp://host/repo",
        "user:password@host/repo",
        "user@host/repo",
        "user@host",
        "user%3Apassword%40host%2Frepo",
        "user%40host%2Frepo",
        "https%3A%2F%2Fuser%3Apassword%40host%2Frepo",
        "api_key%3Dsecret",
        "%2Fvar%2Fcache%2Frepo",
        "C%3A%2Fcache%2Frepo",
    }) |bad| {
        try std.testing.expectError(
            error.InvalidString,
            validateRepositoryId(bad),
        );
    }
}

test "opaque resolver text preserves benign punctuation" {
    var data = testData();
    var packages = [_]Package{
        data.packages[0],
        data.packages[1],
        data.packages[2],
        data.packages[3],
    };
    packages[0].identity.arch = "x86_64@vendor";
    packages[0].identity.name = "product:package";
    packages[0].identity.release = "1%release?#";
    packages[0].identity.version = "2.0?candidate#1%";
    packages[1].identity.name = "product:package";
    packages[2].identity.name = "product:package";

    var jobs = [_]Job{ data.jobs[0], data.jobs[1], data.jobs[2] };
    jobs[0].selection = .{ .name = "product:package@vendor%?#" };
    jobs[1].selection = .{ .capability = .{
        .comparison = .ge,
        .epoch = null,
        .flags = "GE:@%?#",
        .name = "capability:provider@vendor%?#",
        .release = "1%release?#",
        .version = "2.0?candidate#1%",
    } };
    var requests = [_]Request{ data.requests[0], data.requests[1] };
    requests[0].subject = "cli-subject:product@vendor%?#";

    data.environment.architecture = "x86_64@vendor";
    data.environment.distro = "photon:stable@vendor#1";
    data.environment.releasever = "5.0%candidate?build#1";
    data.environment.policy.force_architecture = "x86_64@vendor";
    data.environment.policy.installonly_names = &.{"kernel:debug@vendor%?#"};
    data.packages = &packages;
    data.jobs = &jobs;
    data.requests = &requests;
    try validate(data);
    try validateCapability(.{
        .comparison = .ge,
        .epoch = null,
        .flags = "GE:@%?#",
        .name = "capability:provider@vendor%?#",
        .release = "1%release?#",
        .version = "2.0?candidate#1%",
    });

    const plan = try Plan.create(std.testing.allocator, data);
    defer plan.destroy();
    const json = try plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try expectJsonContains(json, "product:package");
    try expectJsonContains(json, "capability:provider@vendor%?#");
    try expectJsonContains(json, "cli-subject:product@vendor%?#");
    try expectJsonContains(json, "photon:stable@vendor#1");
    try expectJsonContains(json, "5.0%candidate?build#1");

    data.environment.distro = "bad\x01text";
    try std.testing.expectError(error.InvalidString, validate(data));
    data.environment.distro = "bad\xc2\x85text";
    try std.testing.expectError(error.InvalidString, validate(data));
}

test "package checksum pkgid participates in semantic identity" {
    const data = testData();
    const left = data.packages[0];
    var right = left;
    right.id = "same-nevra-other-source";
    right.source.?.checksum.value = test_sha_b;
    try validatePackages(&.{ left, right }, data.repositories);
    try std.testing.expect(comparePackage(left, right) != .eq);
    right.source.?.checksum.value = left.source.?.checksum.value;
    right.source.?.checksum.is_pkgid = !left.source.?.checksum.is_pkgid;
    try validatePackages(&.{ left, right }, data.repositories);
    try std.testing.expect(comparePackage(left, right) != .eq);
    right.source.?.checksum.is_pkgid = left.source.?.checksum.is_pkgid;
    try std.testing.expectError(error.AmbiguousPackageIdentity, validatePackages(&.{ left, right }, data.repositories));

    const first = try Plan.create(std.testing.allocator, data);
    defer first.destroy();
    const first_digest = try first.digest(std.testing.allocator);
    var changed_data = data;
    var packages = [_]Package{ data.packages[0], data.packages[1], data.packages[2], data.packages[3] };
    packages[0].source.?.checksum.is_pkgid = false;
    changed_data.packages = &packages;
    const changed = try Plan.create(std.testing.allocator, changed_data);
    defer changed.destroy();
    const changed_digest = try changed.digest(std.testing.allocator);
    try std.testing.expect(!std.mem.eql(u8, &first_digest, &changed_digest));
}

test "raw checksum kind and value preserve package identity" {
    var data = testData();
    var packages = [_]Package{
        data.packages[0],
        data.packages[1],
        data.packages[2],
        data.packages[3],
    };
    packages[0].source.?.checksum.kind = "sha";
    packages[0].source.?.checksum.value = "ABCDEF";
    data.packages = &packages;

    const first = try Plan.create(std.testing.allocator, data);
    defer first.destroy();
    const first_json = try first.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(first_json);
    const first_digest = try first.digest(std.testing.allocator);
    try expectJsonContains(first_json, "\"kind\":\"sha\"");
    try expectJsonContains(first_json, "\"value\":\"ABCDEF\"");

    var changed_data = data;
    var changed_packages = packages;
    changed_packages[0].source.?.checksum.kind = "sha1";
    changed_data.packages = &changed_packages;
    const changed = try Plan.create(std.testing.allocator, changed_data);
    defer changed.destroy();
    const changed_digest = try changed.digest(std.testing.allocator);
    try std.testing.expect(!std.mem.eql(u8, &first_digest, &changed_digest));

    var different_kind = packages[0];
    different_kind.id = "same-nevra-sha1";
    different_kind.source.?.checksum.kind = "sha1";
    try validatePackages(
        &.{ packages[0], different_kind },
        data.repositories,
    );
    different_kind.source.?.checksum.kind = "sha";
    try std.testing.expectError(
        error.AmbiguousPackageIdentity,
        validatePackages(
            &.{ packages[0], different_kind },
            data.repositories,
        ),
    );
}

test "package epoch and size preserve null separately from zero" {
    var null_data = testData();
    var null_packages = [_]Package{
        null_data.packages[0],
        null_data.packages[1],
        null_data.packages[2],
        null_data.packages[3],
    };
    null_packages[0].identity.epoch = null;
    null_packages[0].source.?.size = null;
    null_data.packages = &null_packages;

    const null_plan = try Plan.create(std.testing.allocator, null_data);
    defer null_plan.destroy();
    const null_json = try null_plan.canonicalJsonAlloc(
        std.testing.allocator,
    );
    defer std.testing.allocator.free(null_json);
    try expectJsonContains(
        null_json,
        "\"identity\":{\"arch\":\"x86_64\",\"epoch\":null,\"name\":\"alpha\"",
    );
    try expectJsonContains(null_json, "\"size\":null");
    try std.testing.expect(null_plan.model().packages[0].identity.epoch == null);
    try std.testing.expect(null_plan.model().packages[0].source.?.size == null);

    var zero_data = null_data;
    var zero_packages = null_packages;
    zero_packages[0].identity.epoch = 0;
    zero_packages[0].source.?.size = 0;
    zero_data.packages = &zero_packages;
    const zero_plan = try Plan.create(std.testing.allocator, zero_data);
    defer zero_plan.destroy();
    const null_digest = try null_plan.digest(std.testing.allocator);
    const zero_digest = try zero_plan.digest(std.testing.allocator);
    try std.testing.expect(!std.mem.eql(u8, &null_digest, &zero_digest));

    var duplicate_null = testData().packages[0];
    duplicate_null.id = "null-epoch";
    duplicate_null.identity.epoch = null;
    var duplicate_zero = duplicate_null;
    duplicate_zero.id = "zero-epoch";
    duplicate_zero.identity.epoch = 0;
    // solver_identity.AvailableKey intentionally normalizes its lookup key,
    // so two losslessly captured representations cannot coexist.
    try std.testing.expectError(
        error.AmbiguousPackageIdentity,
        validatePackages(
            &.{ duplicate_null, duplicate_zero },
            testData().repositories,
        ),
    );

    var location_a = testData().packages[0];
    location_a.id = "location-a";
    var location_b = location_a;
    location_b.id = "location-b";
    location_b.source.?.location.?.href = "other/alpha.rpm";
    location_b.source.?.size = null;
    try std.testing.expectError(
        error.AmbiguousPackageIdentity,
        validatePackages(
            &.{ location_a, location_b },
            testData().repositories,
        ),
    );
}

test "repository URI references reject secret markers everywhere" {
    var data = testData();
    var packages = [_]Package{ data.packages[0], data.packages[1], data.packages[2], data.packages[3] };
    data.packages = &packages;
    for ([_][]const u8{
        "https://example.test/repo",
        "../pool",
        "pool/product:package.rpm",
        "pool/product%20package.rpm",
    }) |safe| {
        packages[0].source.?.location.?.href = safe;
        try validate(data);
    }
    packages[0].source.?.location.?.href = "pool/product:package.rpm";
    packages[0].source.?.location.?.xml_base = "https://example.test/repo/base:tag";
    try validate(data);
    packages[0].source.?.location.?.xml_base =
        "media://dvd-1/Packages/";
    try validate(data);
    packages[0].source.?.location.?.xml_base = null;

    for ([_][]const u8{
        "https://api_key=secret.example/repo",
        "https://host/secret=value.rpm",
        "https://host/%73ecret=value.rpm",
        "https://host/%41CCESS%5fTOKEN%3Dvalue.rpm",
        "https://host/%63lient%5fsecret%3Dvalue.rpm",
        "https://host/%70asswd%3Dvalue.rpm",
        "https://host/%70assword%3Dvalue.rpm",
        "https://host/%70roxy%3Duser.rpm",
        "https://host/%2D%2D%2D%2D%2DBEGIN%20RSA%20PRIVATE%20KEY%2D%2D%2D%2D%2D",
        "https://host/embedded%3A%2F%2Freference",
        "https://user%40host/repo",
        "https://user@host/repo",
        "pool/has space.rpm",
        "pool/has\xc2\xa0space.rpm",
        "ftp://host/x",
        "file:///x",
        "media:///var/cache/pkg.rpm",
        "media://user:" ++ "pass" ++ "word@host/pkg.rpm",
        "media://user%3Apassword%40host/pkg.rpm",
        "media://host%2Fprivate/pkg.rpm",
        "media://host%3Fquery/pkg.rpm",
        "media://host%23fragment/pkg.rpm",
        "media://host/pkg.rpm?query",
        "media://host/pkg.rpm#fragment",
        "media://host/secret=value.rpm",
        "media://host/%73ecret%3Dvalue.rpm",
        "/absolute",
        "//host/x",
        "x?query",
        "x#fragment",
        "x%ZZ",
        "x\\y",
        "x\x01y",
        "x\x00y",
        "pool/token=value.rpm",
        "pool/api_key%3Dvalue.rpm",
    }) |bad| {
        packages[0].source.?.location.?.href = bad;
        try std.testing.expectError(error.InvalidLocation, validate(data));
    }
}

test "plan rejects empty location fields before canonical output" {
    const pristine = testData();
    var data = pristine;
    var packages = [_]Package{
        pristine.packages[0],
        pristine.packages[1],
        pristine.packages[2],
        pristine.packages[3],
    };
    data.packages = &packages;

    packages[0].source.?.location.?.xml_base = "";
    try std.testing.expectError(
        error.InvalidLocation,
        Plan.create(std.testing.allocator, data),
    );

    packages[0] = pristine.packages[0];
    packages[0].source.?.location.?.href = "";
    try std.testing.expectError(
        error.InvalidLocation,
        Plan.create(std.testing.allocator, data),
    );

    packages[0] = pristine.packages[0];
    var records = [_]MetadataRecord{
        pristine.repositories[0].repomd.?.records[0],
    };
    var repositories = [_]Repository{
        pristine.repositories[0],
        pristine.repositories[1],
    };
    repositories[0].repomd.?.records = &records;
    data.repositories = &repositories;
    records[0].location.xml_base = "";
    try std.testing.expectError(
        error.InvalidLocation,
        Plan.create(std.testing.allocator, data),
    );

    data.repositories = pristine.repositories;
    packages[0] = pristine.packages[0];
    packages[0].source.?.location.?.xml_base = null;
    const normalized = try Plan.create(std.testing.allocator, data);
    defer normalized.destroy();
    const json = try normalized.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try expectJsonContains(
        json,
        "\"href\":\"dir/alpha.rpm\",\"xml_base\":null",
    );
}

test "raw EVR ties hnum uniqueness globs records and resolved skips remain authoritative" {
    var data = testData();
    var packages = [_]Package{ data.packages[0], data.packages[1], data.packages[2], data.packages[3] };
    packages[0].identity.version = "2.00";
    packages[3].identity.name = "alpha";
    packages[3].identity.version = "2.0";
    try std.testing.expect(comparePackage(packages[0], packages[3]) != .eq);
    packages[1].rpmdb_hnum = std.math.maxInt(u32);
    packages[2].rpmdb_hnum = std.math.maxInt(u32) - 1;
    try validatePackages(&packages, data.repositories);
    packages[2].rpmdb_hnum = std.math.maxInt(u32);
    try std.testing.expectError(error.AmbiguousPackageIdentity, validatePackages(&packages, data.repositories));

    data.environment.policy.excludes = &.{ "ba?", "kernel-[0-9]*" };
    try validate(data);
    data.environment.policy.excludes = &.{"bad["};
    try std.testing.expectError(error.InvalidString, validate(data));

    data = testData();
    data.environment.resolution_status = .resolved_with_skips;
    data.actions = &.{data.actions[0]};
    data.selected = &.{data.selected[0]};
    data.skipped = &.{.{ .job_id = "job-install" }};
    data.problems = &.{.{ .id = "skip-problem", .capability = null, .count = 1, .job_id = "job-install", .kind = .no_candidate, .package_id = "extra", .related_package_id = null }};
    try validate(data);
}

test "skips identify jobs and allow mixed sibling outcomes" {
    var data = testData();
    const jobs = [_]Job{
        data.jobs[0],
        .{
            .id = "job-install-skipped",
            .action = .install,
            .selection = .{ .name = "extra" },
            .reason = .user,
            .request_id = "req-install",
        },
        .{
            .id = "job-install-succeeded",
            .action = .install,
            .selection = .{ .package = "extra" },
            .reason = .user,
            .request_id = "req-install",
        },
        data.jobs[1],
    };
    const actions = [_]Action{
        data.actions[0],
        .{
            .kind = .install,
            .prior_package_ids = &.{},
            .reason = .user,
            .requested_by_job_id = "job-install-succeeded",
            .target_package_id = "extra",
        },
    };
    data.jobs = &jobs;
    data.actions = &actions;
    data.environment.resolution_status = .resolved_with_skips;
    data.skipped = &.{.{ .job_id = "job-install-skipped" }};
    try validate(data);

    const plan = try Plan.create(std.testing.allocator, data);
    defer plan.destroy();
    const json = try plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try expectJsonContains(json, "\"skipped\":[{\"job_id\":\"job-");
    try std.testing.expect(std.mem.indexOf(u8, json, "\"reason\":\"no_candidate\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"request_id\":\"req-install\"") != null);

    data.skipped = &.{.{ .job_id = "job-install-succeeded" }};
    try std.testing.expectError(error.InconsistentResolution, validate(data));
    data.skipped = &.{.{ .job_id = "unknown-job" }};
    try std.testing.expectError(error.UnknownReference, validate(data));
}

test "metadata record identity is canonical under permutation" {
    var data = testData();
    const primary = data.repositories[0].repomd.?.records[0];
    const filelists = MetadataRecord{
        .checksum = .{ .kind = "sha256", .value = test_sha_c },
        .database_version = null,
        .location = .{ .href = "repodata/filelists.xml.zst", .xml_base = null },
        .open_checksum = null,
        .open_size = 20,
        .record_type = "filelists",
        .size = 21,
        .timestamp = 43,
    };
    var records = [_]MetadataRecord{ primary, filelists };
    var repositories = [_]Repository{ data.repositories[0], data.repositories[1] };
    repositories[0].repomd.?.records = &records;
    data.repositories = &repositories;
    const first = try Plan.create(std.testing.allocator, data);
    defer first.destroy();
    const first_json = try first.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(first_json);
    records = .{ filelists, primary };
    const second = try Plan.create(std.testing.allocator, data);
    defer second.destroy();
    const second_json = try second.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(second_json);
    try std.testing.expectEqualStrings(first_json, second_json);
}

test "indexed package validation and references scale to repository metadata" {
    const package_count = 4096;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const packages = try arena.alloc(Package, package_count);
    const reversed = try arena.alloc(Package, package_count);
    const selected = try arena.alloc(Selected, package_count);
    for (packages, 0..) |*package, index| {
        const id = try std.fmt.allocPrint(arena, "capture-{d}", .{index});
        const name = try std.fmt.allocPrint(arena, "package-{d}", .{index});
        package.* = .{
            .id = id,
            .identity = .{
                .arch = "noarch",
                .epoch = 0,
                .name = name,
                .release = "1",
                .version = "1",
            },
            .repository_id = "@System",
            .rpmdb_hnum = @intCast(index + 1),
            .source = null,
            .state = .installed,
        };
        selected[package_count - index - 1] = .{ .package_id = id };
    }
    for (packages, 0..) |package, index| {
        reversed[package_count - index - 1] = package;
    }

    var data = testData();
    data.actions = &.{};
    data.jobs = &.{};
    data.packages = packages;
    data.problems = &.{};
    data.repositories = data.repositories[1..2];
    data.requests = &.{};
    data.selected = selected;
    data.skipped = &.{};
    const first = try Plan.create(std.testing.allocator, data);
    defer first.destroy();
    try std.testing.expectEqual(package_count, first.package_index.by_id.count());
    const first_digest = try first.digest(std.testing.allocator);

    data.packages = reversed;
    const second = try Plan.create(std.testing.allocator, data);
    defer second.destroy();
    const second_digest = try second.digest(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &first_digest, &second_digest);
}

test "owned plan survives capture mutation and allocation failures" {
    var subject = [_]u8{ 'a', 'l', 'p', 'h', 'a' };
    var selected_id = "new".*;
    var data = testData();
    var requests = [_]Request{ data.requests[0], data.requests[1] };
    requests[0].subject = &subject;
    const selected = [_]Selected{
        .{ .package_id = &selected_id },
        data.selected[1],
    };
    data.requests = &requests;
    data.selected = &selected;
    const plan = try Plan.create(std.testing.allocator, data);
    defer plan.destroy();
    subject[0] = 'z';
    selected_id[0] = 'z';
    try std.testing.expectEqualStrings("alpha", plan.model().requests[0].subject.?);
    try std.testing.expectEqualStrings("new", plan.model().selected[0].package_id);
}

fn allocationFailureCase(allocator: Allocator) !void {
    const plan = try Plan.create(allocator, testData());
    defer plan.destroy();
    const json = try plan.canonicalJsonAlloc(allocator);
    defer allocator.free(json);
}

test "owned plan and canonical writer clean up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailureCase, .{});
}
