const std = @import("std");

const c = @cImport({
    @cInclude("transaction_plan_capture.h");
});

pub const abi_version: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ABI_VERSION;

pub const request_kind = struct {
    pub const distro_sync: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_DISTRO_SYNC;
    pub const downgrade: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_DOWNGRADE;
    pub const erase: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_ERASE;
    pub const install: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_INSTALL;
    pub const lock: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_LOCK;
    pub const reinstall: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_REINSTALL;
    pub const update: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_UPDATE;
    pub const update_all: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_UPDATE_ALL;
};

pub const job_action = struct {
    pub const install: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_INSTALL;
    pub const erase: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ERASE;
    pub const update: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_UPDATE;
    pub const downgrade: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_DOWNGRADE;
    pub const dist_sync: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_DIST_SYNC;
    pub const reinstall: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_REINSTALL;
    pub const lock: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_LOCK;
    pub const multiversion: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_MULTIVERSION;
    pub const user_installed: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_USER_INSTALLED;
    pub const allow_uninstall: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ALLOW_UNINSTALL;
};

pub const request_reason = struct {
    pub const user: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_USER;
    pub const dependency: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_DEPENDENCY;
    pub const weak_dependency: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_WEAK_DEPENDENCY;
    pub const cleanup: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_CLEANUP;
    pub const installonly_limit: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_INSTALLONLY_LIMIT;
    pub const policy: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY;
};

pub const package_state = struct {
    pub const available: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_AVAILABLE;
    pub const installed: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_INSTALLED;
};

pub const action_kind = struct {
    pub const downgrade: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_DOWNGRADE;
    pub const erase: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_ERASE;
    pub const install: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_INSTALL;
    pub const obsolete: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_OBSOLETE;
    pub const reinstall: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REINSTALL;
    pub const upgrade: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_UPGRADE;
};

pub const action_reason = struct {
    pub const cleanup: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_CLEANUP;
    pub const dependency: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_DEPENDENCY;
    pub const installonly_limit: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_INSTALLONLY_LIMIT;
    pub const obsoletes: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_OBSOLETES;
    pub const policy: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_POLICY;
    pub const user: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_USER;
    pub const weak_dependency: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_WEAK_DEPENDENCY;
};

pub const problem_kind = struct {
    pub const conflict: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_CONFLICT;
    pub const installonly_limit: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_INSTALLONLY_LIMIT;
    pub const no_candidate: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_NO_CANDIDATE;
    pub const not_installable: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_NOT_INSTALLABLE;
    pub const obsoletes: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_OBSOLETES;
    pub const protected_package: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_PROTECTED_PACKAGE;
    pub const unsatisfied_requirement: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_UNSATISFIED_REQUIREMENT;
};

pub const compare_op = struct {
    pub const eq: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_EQ;
    pub const ge: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_GE;
    pub const gt: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_GT;
    pub const le: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_LE;
    pub const lt: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_LT;
    pub const none: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_NONE;
};

pub const resolution_status = struct {
    pub const problems: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_PROBLEMS;
    pub const resolved: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_RESOLVED;
    pub const resolved_with_skips: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_RESOLVED_WITH_SKIPS;
};

pub const rpmdb_backend = struct {
    pub const bdb: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_BDB;
    pub const ndb: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_NDB;
    pub const sqlite: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_SQLITE;
};

pub const repository_kind = struct {
    pub const available: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_AVAILABLE;
    pub const installed: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_INSTALLED;
    pub const command_line: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_COMMAND_LINE;
};

pub const selection_kind = struct {
    pub const all: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_ALL;
    pub const package: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_PACKAGE;
    pub const name: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_NAME;
    pub const capability: u32 = c.TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_CAPABILITY;
};

pub const Bytes = extern struct {
    data: ?[*]const u8 = null,
    length: usize = 0,
};

pub const Checksum = extern struct {
    kind: Bytes = .{},
    value: Bytes = .{},
    is_pkgid: u32 = 0,
};

pub const Location = extern struct {
    href: Bytes = .{},
    xml_base: Bytes = .{},
    has_xml_base: u32 = 0,
};

pub const Capability = extern struct {
    name: Bytes = .{},
    flags: Bytes = .{},
    version: Bytes = .{},
    release: Bytes = .{},
    epoch: u64 = 0,
    comparison: u32 = 0,
    sense: u32 = 0,
    has_epoch: u32 = 0,
    has_flags: u32 = 0,
    has_version: u32 = 0,
    has_release: u32 = 0,
    pre: u32 = 0,
};

pub const MinVersion = extern struct {
    arch: Bytes = .{},
    name: Bytes = .{},
    release: Bytes = .{},
    version: Bytes = .{},
    epoch: u64 = 0,
    has_arch: u32 = 0,
    has_epoch: u32 = 0,
    has_release: u32 = 0,
};

pub const Policy = extern struct {
    excludes: ?[*]const Bytes = null,
    installonly_names: ?[*]const Bytes = null,
    locked_names: ?[*]const Bytes = null,
    min_versions: ?[*]const MinVersion = null,
    protected_names: ?[*]const Bytes = null,
    force_architecture: Bytes = .{},
    exclude_count: u32 = 0,
    installonly_name_count: u32 = 0,
    locked_name_count: u32 = 0,
    min_version_count: u32 = 0,
    protected_name_count: u32 = 0,
    allow_erasing: u32 = 0,
    allow_multilib: u32 = 0,
    all_deps: u32 = 0,
    best: u32 = 0,
    clean_requirements_on_remove: u32 = 0,
    has_force_architecture: u32 = 0,
    include_installed: u32 = 0,
    installonly_limit: u32 = 0,
    install_weak_dependencies: u32 = 0,
    keep_orphans: u32 = 0,
    skip_broken: u32 = 0,
};

pub const Rpmdb = extern struct {
    cookie_sha256: Bytes = .{},
    package_set_sha256: Bytes = .{},
    backend: u32 = 0,
};

pub const Environment = extern struct {
    architecture: Bytes = .{},
    distro: Bytes = .{},
    policy: Policy = .{},
    releasever: Bytes = .{},
    rpmdb: Rpmdb = .{},
    resolution_status: u32 = 0,
};

pub const MetadataRecord = extern struct {
    checksum: Checksum = .{},
    location: Location = .{},
    open_checksum: Checksum = .{},
    record_type: Bytes = .{},
    database_version: u64 = 0,
    open_size: u64 = 0,
    size: u64 = 0,
    timestamp: u64 = 0,
    has_checksum: u32 = 0,
    has_database_version: u32 = 0,
    has_open_checksum: u32 = 0,
    has_open_size: u32 = 0,
    has_size: u32 = 0,
    has_timestamp: u32 = 0,
};

pub const Repomd = extern struct {
    checksum_sha256: Bytes = .{},
    records: ?[*]const MetadataRecord = null,
    revision: Bytes = .{},
    timestamp: u64 = 0,
    record_count: u32 = 0,
    has_revision: u32 = 0,
};

pub const Snapshot = extern struct {
    id: Bytes = .{},
    metadata_sha256: Bytes = .{},
};

pub const Repository = extern struct {
    id: Bytes = .{},
    repomd: Repomd = .{},
    snapshot: Snapshot = .{},
    priority: i32 = 0,
    cost: u32 = 0,
    kind: u32 = 0,
    has_repomd: u32 = 0,
    has_snapshot: u32 = 0,
};

pub const Request = extern struct {
    id: Bytes = .{},
    subject: Bytes = .{},
    kind: u32 = 0,
    has_subject: u32 = 0,
};

pub const Job = extern struct {
    capability: Capability = .{},
    selection_value: Bytes = .{},
    action: u32 = 0,
    selection_kind: u32 = 0,
    selection_package_ref: u32 = 0,
    reason: u32 = 0,
    request_ref: u32 = 0,
    has_request_ref: u32 = 0,
    clean_deps: u32 = 0,
    force_best: u32 = 0,
    targeted: u32 = 0,
    not_by_user: u32 = 0,
    weak: u32 = 0,
};

pub const PackageIdentity = extern struct {
    arch: Bytes = .{},
    name: Bytes = .{},
    release: Bytes = .{},
    version: Bytes = .{},
    epoch: u32 = 0,
    has_epoch: u32 = 0,
};

pub const PackageSource = extern struct {
    checksum: Checksum = .{},
    location: Location = .{},
    size: u64 = 0,
    has_location: u32 = 0,
    has_size: u32 = 0,
};

pub const Package = extern struct {
    identity: PackageIdentity = .{},
    source: PackageSource = .{},
    repository_ref: u32 = 0,
    rpmdb_hnum: u32 = 0,
    state: u32 = 0,
    has_rpmdb_hnum: u32 = 0,
    has_source: u32 = 0,
};

pub const Action = extern struct {
    target_package_ref: u32 = 0,
    kind: u32 = 0,
    reason: u32 = 0,
    requested_job_ref: u32 = 0,
    has_requested_job_ref: u32 = 0,
    prior_offset: u32 = 0,
    prior_count: u32 = 0,
};

pub const Problem = extern struct {
    capability: Capability = .{},
    count: u32 = 0,
    kind: u32 = 0,
    job_ref: u32 = 0,
    package_ref: u32 = 0,
    related_package_ref: u32 = 0,
    has_capability: u32 = 0,
    has_job_ref: u32 = 0,
    has_package_ref: u32 = 0,
    has_related_package_ref: u32 = 0,
};

pub const Capture = extern struct {
    abi_version: u32 = abi_version,
    struct_size: u32 = @sizeOf(Capture),
    environment: Environment = .{},
    repositories: ?[*]const Repository = null,
    requests: ?[*]const Request = null,
    jobs: ?[*]const Job = null,
    packages: ?[*]const Package = null,
    actions: ?[*]const Action = null,
    prior_package_refs: ?[*]const u32 = null,
    selected_package_refs: ?[*]const u32 = null,
    skipped_job_refs: ?[*]const u32 = null,
    hidden_package_refs: ?[*]const u32 = null,
    problems: ?[*]const Problem = null,
    repository_count: u32 = 0,
    request_count: u32 = 0,
    job_count: u32 = 0,
    package_count: u32 = 0,
    action_count: u32 = 0,
    prior_package_ref_count: u32 = 0,
    selected_package_ref_count: u32 = 0,
    skipped_job_ref_count: u32 = 0,
    hidden_package_ref_count: u32 = 0,
    problem_count: u32 = 0,
};

fn assertSameLayout(comptime zig_type: type, comptime c_type: type) void {
    if (@sizeOf(zig_type) != @sizeOf(c_type)) {
        @compileError("C ABI size mismatch for " ++ @typeName(zig_type));
    }
    if (@alignOf(zig_type) != @alignOf(c_type)) {
        @compileError("C ABI alignment mismatch for " ++ @typeName(zig_type));
    }
    const zig_fields = @typeInfo(zig_type).@"struct".fields;
    const c_fields = @typeInfo(c_type).@"struct".fields;
    if (zig_fields.len != c_fields.len) {
        @compileError("C ABI field-count mismatch for " ++ @typeName(zig_type));
    }
    inline for (zig_fields) |field| {
        if (!@hasField(c_type, field.name)) {
            @compileError("C ABI missing field " ++ field.name);
        }
        if (@offsetOf(zig_type, field.name) != @offsetOf(c_type, field.name)) {
            @compileError("C ABI offset mismatch for " ++ field.name);
        }
        const c_field_type = @TypeOf(@field(
            @as(c_type, undefined),
            field.name,
        ));
        if (@sizeOf(field.type) != @sizeOf(c_field_type) or
            @alignOf(field.type) != @alignOf(c_field_type))
        {
            @compileError("C ABI field layout mismatch for " ++ field.name);
        }
    }
}

comptime {
    assertSameLayout(Bytes, c.TDNF_TRANSACTION_PLAN_CAPTURE_BYTES);
    assertSameLayout(Checksum, c.TDNF_TRANSACTION_PLAN_CAPTURE_CHECKSUM);
    assertSameLayout(Location, c.TDNF_TRANSACTION_PLAN_CAPTURE_LOCATION);
    assertSameLayout(Capability, c.TDNF_TRANSACTION_PLAN_CAPTURE_CAPABILITY);
    assertSameLayout(MinVersion, c.TDNF_TRANSACTION_PLAN_CAPTURE_MIN_VERSION);
    assertSameLayout(Policy, c.TDNF_TRANSACTION_PLAN_CAPTURE_POLICY);
    assertSameLayout(Rpmdb, c.TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB);
    assertSameLayout(Environment, c.TDNF_TRANSACTION_PLAN_CAPTURE_ENVIRONMENT);
    assertSameLayout(MetadataRecord, c.TDNF_TRANSACTION_PLAN_CAPTURE_METADATA_RECORD);
    assertSameLayout(Repomd, c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOMD);
    assertSameLayout(Snapshot, c.TDNF_TRANSACTION_PLAN_CAPTURE_SNAPSHOT);
    assertSameLayout(Repository, c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY);
    assertSameLayout(Request, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST);
    assertSameLayout(Job, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB);
    assertSameLayout(PackageIdentity, c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_IDENTITY);
    assertSameLayout(PackageSource, c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_SOURCE);
    assertSameLayout(Package, c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE);
    assertSameLayout(Action, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION);
    assertSameLayout(Problem, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM);
    assertSameLayout(Capture, c.TDNF_TRANSACTION_PLAN_CAPTURE);
}

test "private capture header compiles with fixed domains" {
    try std.testing.expectEqual(@as(u32, 1), abi_version);
    try std.testing.expectEqual(@as(u32, 3), selection_kind.capability);
    try std.testing.expectEqual(@as(u32, 2), repository_kind.command_line);
    try std.testing.expectEqual(@as(u32, 6), problem_kind.unsatisfied_requirement);
}
