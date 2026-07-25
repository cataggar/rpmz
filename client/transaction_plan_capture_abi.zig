pub const abi_version: u32 = 1;

pub const request_kind = struct {
    pub const distro_sync: u32 = 0;
    pub const downgrade: u32 = 1;
    pub const erase: u32 = 2;
    pub const install: u32 = 3;
    pub const lock: u32 = 4;
    pub const reinstall: u32 = 5;
    pub const update: u32 = 6;
    pub const update_all: u32 = 7;
};

pub const job_action = struct {
    pub const install: u32 = 0;
    pub const erase: u32 = 1;
    pub const update: u32 = 2;
    pub const downgrade: u32 = 3;
    pub const dist_sync: u32 = 4;
    pub const reinstall: u32 = 5;
    pub const lock: u32 = 6;
    pub const multiversion: u32 = 7;
    pub const user_installed: u32 = 8;
    pub const allow_uninstall: u32 = 9;
};

pub const request_reason = struct {
    pub const user: u32 = 0;
    pub const dependency: u32 = 1;
    pub const weak_dependency: u32 = 2;
    pub const cleanup: u32 = 3;
    pub const installonly_limit: u32 = 4;
    pub const policy: u32 = 5;
};

pub const package_state = struct {
    pub const available: u32 = 0;
    pub const installed: u32 = 1;
};

pub const action_kind = struct {
    pub const downgrade: u32 = 0;
    pub const erase: u32 = 1;
    pub const install: u32 = 2;
    pub const obsolete: u32 = 3;
    pub const reinstall: u32 = 4;
    pub const upgrade: u32 = 5;
};

pub const action_reason = struct {
    pub const cleanup: u32 = 0;
    pub const dependency: u32 = 1;
    pub const installonly_limit: u32 = 2;
    pub const obsoletes: u32 = 3;
    pub const policy: u32 = 4;
    pub const user: u32 = 5;
    pub const weak_dependency: u32 = 6;
};

pub const problem_kind = struct {
    pub const conflict: u32 = 0;
    pub const installonly_limit: u32 = 1;
    pub const no_candidate: u32 = 2;
    pub const not_installable: u32 = 3;
    pub const obsoletes: u32 = 4;
    pub const protected_package: u32 = 5;
    pub const unsatisfied_requirement: u32 = 6;
};

pub const compare_op = struct {
    pub const eq: u32 = 0;
    pub const ge: u32 = 1;
    pub const gt: u32 = 2;
    pub const le: u32 = 3;
    pub const lt: u32 = 4;
    pub const none: u32 = 5;
};

pub const resolution_status = struct {
    pub const problems: u32 = 0;
    pub const resolved: u32 = 1;
    pub const resolved_with_skips: u32 = 2;
};

pub const rpmdb_backend = struct {
    pub const bdb: u32 = 0;
    pub const ndb: u32 = 1;
    pub const sqlite: u32 = 2;
};

pub const repository_kind = struct {
    pub const available: u32 = 0;
    pub const installed: u32 = 1;
    pub const command_line: u32 = 2;
};

pub const selection_kind = struct {
    pub const all: u32 = 0;
    pub const package: u32 = 1;
    pub const name: u32 = 2;
    pub const capability: u32 = 3;
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
