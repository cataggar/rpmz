const std = @import("std");
const Allocator = std.mem.Allocator;

const abi = @import("transaction_plan_capture_abi");
const error_codes = @import("tdnf_error");
const transaction_plan = @import("transaction_plan");
const request_trace = @import("transaction_plan_request_trace");

comptime {
    _ = request_trace;
}

const DecodeError = error{InvalidAbi} || Allocator.Error;
const CaptureError = DecodeError || transaction_plan.InitError;
const capture_struct_size: u32 = @intCast(@sizeOf(abi.Capture));

const Owner = struct {
    allocator: Allocator,
    plan: *transaction_plan.Plan,

    fn destroy(self: *Owner) void {
        const allocator = self.allocator;
        self.plan.destroy();
        allocator.destroy(self);
    }
};

fn transactionPlanCaptureCreate(
    raw_input: ?*const abi.Capture,
    raw_owner: ?*?*Owner,
) callconv(.c) u32 {
    const owner_out = raw_owner orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    owner_out.* = null;

    const input = raw_input orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const owner = createOwner(std.heap.c_allocator, input) catch |err|
        return mapCaptureError(err);
    owner_out.* = owner;
    return 0;
}

fn transactionPlanCaptureDestroy(owner: ?*Owner) callconv(.c) void {
    if (owner) |value| value.destroy();
}

comptime {
    @export(&transactionPlanCaptureCreate, .{
        .name = "TDNFTransactionPlanCaptureCreate",
        .visibility = .hidden,
    });
    @export(&transactionPlanCaptureDestroy, .{
        .name = "TDNFTransactionPlanCaptureDestroy",
        .visibility = .hidden,
    });
}

fn mapCaptureError(err: anyerror) u32 {
    return switch (err) {
        error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        else => error_codes.ERROR_TDNF_INVALID_PARAMETER,
    };
}

fn createOwner(
    allocator: Allocator,
    input: *const abi.Capture,
) CaptureError!*Owner {
    const plan = try buildPlan(allocator, input);
    errdefer plan.destroy();

    const owner = try allocator.create(Owner);
    owner.* = .{
        .allocator = allocator,
        .plan = plan,
    };
    return owner;
}

fn buildPlan(
    allocator: Allocator,
    input: *const abi.Capture,
) CaptureError!*transaction_plan.Plan {
    if (input.abi_version != abi.abi_version or
        input.struct_size != capture_struct_size)
    {
        return error.InvalidAbi;
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const data = try decodeData(arena_state.allocator(), input);
    return transaction_plan.Plan.create(allocator, data);
}

pub fn decodeData(
    allocator: Allocator,
    input: *const abi.Capture,
) DecodeError!transaction_plan.Data {
    const raw_repositories = try borrowedArray(
        abi.Repository,
        input.repositories,
        input.repository_count,
    );
    const raw_requests = try borrowedArray(
        abi.Request,
        input.requests,
        input.request_count,
    );
    const raw_jobs = try borrowedArray(abi.Job, input.jobs, input.job_count);
    const raw_packages = try borrowedArray(
        abi.Package,
        input.packages,
        input.package_count,
    );
    const raw_actions = try borrowedArray(
        abi.Action,
        input.actions,
        input.action_count,
    );
    const raw_priors = try borrowedArray(
        u32,
        input.prior_package_refs,
        input.prior_package_ref_count,
    );
    const raw_selected = try borrowedArray(
        u32,
        input.selected_package_refs,
        input.selected_package_ref_count,
    );
    const raw_skipped = try borrowedArray(
        u32,
        input.skipped_job_refs,
        input.skipped_job_ref_count,
    );
    const raw_hidden = try borrowedArray(
        u32,
        input.hidden_package_refs,
        input.hidden_package_ref_count,
    );
    const raw_problems = try borrowedArray(
        abi.Problem,
        input.problems,
        input.problem_count,
    );

    const repositories = try decodeRepositories(allocator, raw_repositories);
    const requests = try decodeRequests(allocator, raw_requests);
    const package_handles = try makeHandles(
        allocator,
        "package",
        input.package_count,
    );
    const job_handles = try makeHandles(allocator, "job", input.job_count);
    const problem_handles = try makeHandles(
        allocator,
        "problem",
        input.problem_count,
    );
    const packages = try decodePackages(
        allocator,
        raw_packages,
        repositories,
        package_handles,
    );
    const jobs = try decodeJobs(
        allocator,
        raw_jobs,
        requests,
        package_handles,
        job_handles,
    );

    return .{
        .actions = try decodeActions(
            allocator,
            raw_actions,
            raw_priors,
            package_handles,
            job_handles,
        ),
        .environment = try decodeEnvironment(allocator, input.environment),
        .hidden_packages = try decodeHandleRefs(
            allocator,
            raw_hidden,
            package_handles,
        ),
        .jobs = jobs,
        .packages = packages,
        .problems = try decodeProblems(
            allocator,
            raw_problems,
            package_handles,
            job_handles,
            problem_handles,
        ),
        .repositories = repositories,
        .requests = requests,
        .selected = try decodeSelected(
            allocator,
            raw_selected,
            package_handles,
        ),
        .skipped = try decodeSkipped(
            allocator,
            raw_skipped,
            job_handles,
        ),
    };
}

fn decodeEnvironment(
    allocator: Allocator,
    raw: abi.Environment,
) DecodeError!transaction_plan.Environment {
    return .{
        .architecture = try borrowedBytes(raw.architecture),
        .distro = try borrowedBytes(raw.distro),
        .policy = try decodePolicy(allocator, raw.policy),
        .releasever = try borrowedBytes(raw.releasever),
        .resolution_status = try decodeResolutionStatus(raw.resolution_status),
        .rpmdb = .{
            .backend = try decodeRpmdbBackend(raw.rpmdb.backend),
            .cookie_sha256 = try borrowedBytes(raw.rpmdb.cookie_sha256),
            .package_set_sha256 = try borrowedBytes(
                raw.rpmdb.package_set_sha256,
            ),
        },
    };
}

fn decodePolicy(
    allocator: Allocator,
    raw: abi.Policy,
) DecodeError!transaction_plan.Policy {
    return .{
        .allow_erasing = try decodeFlag(raw.allow_erasing),
        .allow_multilib = try decodeFlag(raw.allow_multilib),
        .all_deps = try decodeFlag(raw.all_deps),
        .best = try decodeFlag(raw.best),
        .clean_requirements_on_remove = try decodeFlag(
            raw.clean_requirements_on_remove,
        ),
        .excludes = try decodeStringArray(
            allocator,
            raw.excludes,
            raw.exclude_count,
        ),
        .force_architecture = try decodeOptionalBytes(
            raw.force_architecture,
            raw.has_force_architecture,
        ),
        .include_installed = try decodeFlag(raw.include_installed),
        .installonly_limit = raw.installonly_limit,
        .installonly_names = try decodeStringArray(
            allocator,
            raw.installonly_names,
            raw.installonly_name_count,
        ),
        .install_weak_dependencies = try decodeFlag(
            raw.install_weak_dependencies,
        ),
        .keep_orphans = try decodeFlag(raw.keep_orphans),
        .locked_names = try decodeStringArray(
            allocator,
            raw.locked_names,
            raw.locked_name_count,
        ),
        .min_versions = try decodeMinVersions(
            allocator,
            raw.min_versions,
            raw.min_version_count,
        ),
        .protected_names = try decodeStringArray(
            allocator,
            raw.protected_names,
            raw.protected_name_count,
        ),
        .skip_broken = try decodeFlag(raw.skip_broken),
    };
}

fn decodeStringArray(
    allocator: Allocator,
    raw_pointer: ?[*]const abi.Bytes,
    raw_count: u32,
) DecodeError![]const []const u8 {
    const raw = try borrowedArray(abi.Bytes, raw_pointer, raw_count);
    const output = try allocator.alloc([]const u8, raw.len);
    for (raw, output) |value, *destination| {
        destination.* = try borrowedBytes(value);
    }
    return output;
}

fn decodeMinVersions(
    allocator: Allocator,
    raw_pointer: ?[*]const abi.MinVersion,
    raw_count: u32,
) DecodeError![]const transaction_plan.MinVersionConstraint {
    const raw = try borrowedArray(abi.MinVersion, raw_pointer, raw_count);
    const output = try allocator.alloc(
        transaction_plan.MinVersionConstraint,
        raw.len,
    );
    for (raw, output) |value, *destination| {
        destination.* = .{
            .arch = try decodeOptionalBytes(value.arch, value.has_arch),
            .epoch = try decodeOptionalU64(value.epoch, value.has_epoch),
            .name = try borrowedBytes(value.name),
            .release = try decodeOptionalBytes(
                value.release,
                value.has_release,
            ),
            .version = try borrowedBytes(value.version),
        };
    }
    return output;
}

fn decodeRepositories(
    allocator: Allocator,
    raw: []const abi.Repository,
) DecodeError![]const transaction_plan.Repository {
    const output = try allocator.alloc(transaction_plan.Repository, raw.len);
    for (raw, output) |value, *destination| {
        destination.* = .{
            .cost = value.cost,
            .id = try borrowedBytes(value.id),
            .kind = try decodeRepositoryKind(value.kind),
            .priority = value.priority,
            .repomd = try decodeOptionalRepomd(
                allocator,
                value.repomd,
                value.has_repomd,
            ),
            .snapshot = try decodeOptionalSnapshot(
                value.snapshot,
                value.has_snapshot,
            ),
        };
    }
    return output;
}

fn decodeOptionalRepomd(
    allocator: Allocator,
    raw: abi.Repomd,
    raw_present: u32,
) DecodeError!?transaction_plan.RepomdIdentity {
    const present = try decodeFlag(raw_present);
    const records = try borrowedArray(
        abi.MetadataRecord,
        raw.records,
        raw.record_count,
    );
    const revision = try decodeOptionalBytes(raw.revision, raw.has_revision);
    if (!present) {
        try requireEmptyBytes(raw.checksum_sha256);
        if (records.len != 0 or revision != null or raw.timestamp != 0) {
            return error.InvalidAbi;
        }
        return null;
    }

    const decoded_records = try allocator.alloc(
        transaction_plan.MetadataRecord,
        records.len,
    );
    for (records, decoded_records) |record, *destination| {
        destination.* = try decodeMetadataRecord(record);
    }
    return .{
        .checksum_sha256 = try borrowedBytes(raw.checksum_sha256),
        .records = decoded_records,
        .revision = revision,
        .timestamp = raw.timestamp,
    };
}

fn decodeMetadataRecord(
    raw: abi.MetadataRecord,
) DecodeError!transaction_plan.MetadataRecord {
    return .{
        .checksum = try decodeOptionalChecksum(
            raw.checksum,
            raw.has_checksum,
        ),
        .database_version = try decodeOptionalU64(
            raw.database_version,
            raw.has_database_version,
        ),
        .location = try decodeLocation(raw.location),
        .open_checksum = try decodeOptionalChecksum(
            raw.open_checksum,
            raw.has_open_checksum,
        ),
        .open_size = try decodeOptionalU64(raw.open_size, raw.has_open_size),
        .record_type = try borrowedBytes(raw.record_type),
        .size = try decodeOptionalU64(raw.size, raw.has_size),
        .timestamp = try decodeOptionalU64(raw.timestamp, raw.has_timestamp),
    };
}

fn decodeOptionalSnapshot(
    raw: abi.Snapshot,
    raw_present: u32,
) DecodeError!?transaction_plan.SnapshotIdentity {
    if (!try decodeFlag(raw_present)) {
        try requireEmptyBytes(raw.id);
        try requireEmptyBytes(raw.metadata_sha256);
        return null;
    }
    return .{
        .id = try borrowedBytes(raw.id),
        .metadata_sha256 = try borrowedBytes(raw.metadata_sha256),
    };
}

fn decodeRequests(
    allocator: Allocator,
    raw: []const abi.Request,
) DecodeError![]const transaction_plan.Request {
    const output = try allocator.alloc(transaction_plan.Request, raw.len);
    for (raw, output) |value, *destination| {
        destination.* = .{
            .id = try borrowedBytes(value.id),
            .kind = try decodeRequestKind(value.kind),
            .subject = try decodeOptionalBytes(
                value.subject,
                value.has_subject,
            ),
        };
    }
    return output;
}

fn decodePackages(
    allocator: Allocator,
    raw: []const abi.Package,
    repositories: []const transaction_plan.Repository,
    handles: []const []const u8,
) DecodeError![]const transaction_plan.Package {
    const output = try allocator.alloc(transaction_plan.Package, raw.len);
    for (raw, output, 0..) |value, *destination, index| {
        destination.* = .{
            .id = handles[index],
            .identity = .{
                .arch = try borrowedBytes(value.identity.arch),
                .epoch = try decodeOptionalU32(
                    value.identity.epoch,
                    value.identity.has_epoch,
                ),
                .name = try borrowedBytes(value.identity.name),
                .release = try borrowedBytes(value.identity.release),
                .version = try borrowedBytes(value.identity.version),
            },
            .repository_id = (try referencedValue(
                transaction_plan.Repository,
                repositories,
                value.repository_ref,
            )).id,
            .rpmdb_hnum = try decodeOptionalU32(
                value.rpmdb_hnum,
                value.has_rpmdb_hnum,
            ),
            .source = try decodeOptionalPackageSource(
                value.source,
                value.has_source,
            ),
            .state = try decodePackageState(value.state),
        };
    }
    return output;
}

fn decodeOptionalPackageSource(
    raw: abi.PackageSource,
    raw_present: u32,
) DecodeError!?transaction_plan.PackageSource {
    const present = try decodeFlag(raw_present);
    const location = try decodeOptionalLocation(
        raw.location,
        raw.has_location,
    );
    const size = try decodeOptionalU64(raw.size, raw.has_size);
    if (!present) {
        try requireEmptyChecksum(raw.checksum);
        if (location != null or size != null) return error.InvalidAbi;
        return null;
    }
    return .{
        .checksum = try decodeChecksum(raw.checksum),
        .location = location,
        .size = size,
    };
}

fn decodeJobs(
    allocator: Allocator,
    raw: []const abi.Job,
    requests: []const transaction_plan.Request,
    package_handles: []const []const u8,
    job_handles: []const []const u8,
) DecodeError![]const transaction_plan.Job {
    const output = try allocator.alloc(transaction_plan.Job, raw.len);
    for (raw, output, 0..) |value, *destination, index| {
        destination.* = .{
            .action = try decodeJobAction(value.action),
            .flags = .{
                .clean_deps = try decodeFlag(value.clean_deps),
                .force_best = try decodeFlag(value.force_best),
                .targeted = try decodeFlag(value.targeted),
                .not_by_user = try decodeFlag(value.not_by_user),
                .weak = try decodeFlag(value.weak),
            },
            .id = job_handles[index],
            .reason = try decodeRequestReason(value.reason),
            .request_id = try decodeOptionalRequestRef(
                requests,
                value.request_ref,
                value.has_request_ref,
            ),
            .selection = try decodeSelection(value, package_handles),
        };
    }
    return output;
}

fn decodeSelection(
    raw: abi.Job,
    package_handles: []const []const u8,
) DecodeError!transaction_plan.Selection {
    return switch (raw.selection_kind) {
        abi.selection_kind.all => blk: {
            try requireEmptyBytes(raw.selection_value);
            if (raw.selection_package_ref != 0) return error.InvalidAbi;
            try requireEmptyCapability(raw.capability);
            break :blk .all;
        },
        abi.selection_kind.package => blk: {
            try requireEmptyBytes(raw.selection_value);
            try requireEmptyCapability(raw.capability);
            break :blk .{
                .package = try referencedHandle(
                    package_handles,
                    raw.selection_package_ref,
                ),
            };
        },
        abi.selection_kind.name => blk: {
            if (raw.selection_package_ref != 0) return error.InvalidAbi;
            try requireEmptyCapability(raw.capability);
            break :blk .{ .name = try borrowedBytes(raw.selection_value) };
        },
        abi.selection_kind.capability => blk: {
            try requireEmptyBytes(raw.selection_value);
            if (raw.selection_package_ref != 0) return error.InvalidAbi;
            break :blk .{
                .capability = try decodeCapability(raw.capability),
            };
        },
        else => error.InvalidAbi,
    };
}

fn decodeActions(
    allocator: Allocator,
    raw: []const abi.Action,
    raw_priors: []const u32,
    package_handles: []const []const u8,
    job_handles: []const []const u8,
) DecodeError![]const transaction_plan.Action {
    for (raw_priors) |package_ref| {
        _ = try referencedHandle(package_handles, package_ref);
    }

    const output = try allocator.alloc(transaction_plan.Action, raw.len);
    var expected_offset: u32 = 0;
    for (raw, output) |value, *destination| {
        const end = std.math.add(
            u32,
            value.prior_offset,
            value.prior_count,
        ) catch return error.InvalidAbi;
        if (value.prior_offset != expected_offset) return error.InvalidAbi;
        if (end > raw_priors.len) return error.InvalidAbi;
        expected_offset = end;

        const start_index: usize = value.prior_offset;
        const end_index: usize = end;
        const priors = try allocator.alloc(
            []const u8,
            end_index - start_index,
        );
        for (raw_priors[start_index..end_index], priors) |package_ref, *id| {
            id.* = try referencedHandle(package_handles, package_ref);
        }
        destination.* = .{
            .kind = try decodeActionKind(value.kind),
            .prior_package_ids = priors,
            .reason = try decodeActionReason(value.reason),
            .requested_by_job_id = try decodeOptionalHandleRef(
                job_handles,
                value.requested_job_ref,
                value.has_requested_job_ref,
            ),
            .target_package_id = try referencedHandle(
                package_handles,
                value.target_package_ref,
            ),
        };
    }
    if (expected_offset != raw_priors.len) return error.InvalidAbi;
    return output;
}

fn decodeSelected(
    allocator: Allocator,
    raw: []const u32,
    package_handles: []const []const u8,
) DecodeError![]const transaction_plan.Selected {
    const output = try allocator.alloc(transaction_plan.Selected, raw.len);
    for (raw, output) |package_ref, *destination| {
        destination.* = .{
            .package_id = try referencedHandle(
                package_handles,
                package_ref,
            ),
        };
    }
    return output;
}

fn decodeSkipped(
    allocator: Allocator,
    raw: []const u32,
    job_handles: []const []const u8,
) DecodeError![]const transaction_plan.Skipped {
    const output = try allocator.alloc(transaction_plan.Skipped, raw.len);
    for (raw, output) |job_ref, *destination| {
        destination.* = .{
            .job_id = try referencedHandle(job_handles, job_ref),
        };
    }
    return output;
}

fn decodeHandleRefs(
    allocator: Allocator,
    raw: []const u32,
    handles: []const []const u8,
) DecodeError![]const []const u8 {
    const output = try allocator.alloc([]const u8, raw.len);
    for (raw, output) |value, *destination| {
        destination.* = try referencedHandle(handles, value);
    }
    return output;
}

fn decodeProblems(
    allocator: Allocator,
    raw: []const abi.Problem,
    package_handles: []const []const u8,
    job_handles: []const []const u8,
    problem_handles: []const []const u8,
) DecodeError![]const transaction_plan.Problem {
    const output = try allocator.alloc(transaction_plan.Problem, raw.len);
    for (raw, output, 0..) |value, *destination, index| {
        destination.* = .{
            .capability = try decodeOptionalCapability(
                value.capability,
                value.has_capability,
            ),
            .count = value.count,
            .id = problem_handles[index],
            .job_id = try decodeOptionalHandleRef(
                job_handles,
                value.job_ref,
                value.has_job_ref,
            ),
            .kind = try decodeProblemKind(value.kind),
            .package_id = try decodeOptionalHandleRef(
                package_handles,
                value.package_ref,
                value.has_package_ref,
            ),
            .related_package_id = try decodeOptionalHandleRef(
                package_handles,
                value.related_package_ref,
                value.has_related_package_ref,
            ),
        };
    }
    return output;
}

fn decodeOptionalCapability(
    raw: abi.Capability,
    raw_present: u32,
) DecodeError!?transaction_plan.Capability {
    if (!try decodeFlag(raw_present)) {
        try requireEmptyCapability(raw);
        return null;
    }
    return try decodeCapability(raw);
}

fn decodeCapability(
    raw: abi.Capability,
) DecodeError!transaction_plan.Capability {
    return .{
        .comparison = try decodeCompareOp(raw.comparison),
        .epoch = try decodeOptionalU64(raw.epoch, raw.has_epoch),
        .flags = try decodeOptionalBytes(raw.flags, raw.has_flags),
        .name = try borrowedBytes(raw.name),
        .pre = try decodeFlag(raw.pre),
        .release = try decodeOptionalBytes(raw.release, raw.has_release),
        .sense = raw.sense,
        .version = try decodeOptionalBytes(raw.version, raw.has_version),
    };
}

fn decodeChecksum(raw: abi.Checksum) DecodeError!transaction_plan.Checksum {
    return .{
        .kind = try borrowedBytes(raw.kind),
        .is_pkgid = try decodeFlag(raw.is_pkgid),
        .value = try borrowedBytes(raw.value),
    };
}

fn decodeOptionalChecksum(
    raw: abi.Checksum,
    raw_present: u32,
) DecodeError!?transaction_plan.Checksum {
    if (!try decodeFlag(raw_present)) {
        try requireEmptyChecksum(raw);
        return null;
    }
    return try decodeChecksum(raw);
}

fn decodeLocation(raw: abi.Location) DecodeError!transaction_plan.PackageLocation {
    return .{
        .href = try borrowedBytes(raw.href),
        .xml_base = try decodeOptionalBytes(
            raw.xml_base,
            raw.has_xml_base,
        ),
    };
}

fn decodeOptionalLocation(
    raw: abi.Location,
    raw_present: u32,
) DecodeError!?transaction_plan.PackageLocation {
    if (!try decodeFlag(raw_present)) {
        try requireEmptyLocation(raw);
        return null;
    }
    return try decodeLocation(raw);
}

fn decodeOptionalRequestRef(
    requests: []const transaction_plan.Request,
    raw_ref: u32,
    raw_present: u32,
) DecodeError!?[]const u8 {
    if (!try decodeFlag(raw_present)) {
        if (raw_ref != 0) return error.InvalidAbi;
        return null;
    }
    return (try referencedValue(
        transaction_plan.Request,
        requests,
        raw_ref,
    )).id;
}

fn decodeOptionalHandleRef(
    handles: []const []const u8,
    raw_ref: u32,
    raw_present: u32,
) DecodeError!?[]const u8 {
    if (!try decodeFlag(raw_present)) {
        if (raw_ref != 0) return error.InvalidAbi;
        return null;
    }
    return try referencedHandle(handles, raw_ref);
}

fn decodeOptionalBytes(
    raw: abi.Bytes,
    raw_present: u32,
) DecodeError!?[]const u8 {
    if (!try decodeFlag(raw_present)) {
        try requireEmptyBytes(raw);
        return null;
    }
    return try borrowedBytes(raw);
}

fn decodeOptionalU64(value: u64, raw_present: u32) DecodeError!?u64 {
    if (!try decodeFlag(raw_present)) {
        if (value != 0) return error.InvalidAbi;
        return null;
    }
    return value;
}

fn decodeOptionalU32(value: u32, raw_present: u32) DecodeError!?u32 {
    if (!try decodeFlag(raw_present)) {
        if (value != 0) return error.InvalidAbi;
        return null;
    }
    return value;
}

fn requireEmptyChecksum(raw: abi.Checksum) DecodeError!void {
    try requireEmptyBytes(raw.kind);
    try requireEmptyBytes(raw.value);
    if (try decodeFlag(raw.is_pkgid)) return error.InvalidAbi;
}

fn requireEmptyLocation(raw: abi.Location) DecodeError!void {
    try requireEmptyBytes(raw.href);
    if (try decodeFlag(raw.has_xml_base)) return error.InvalidAbi;
    try requireEmptyBytes(raw.xml_base);
}

fn requireEmptyCapability(raw: abi.Capability) DecodeError!void {
    try requireEmptyBytes(raw.name);
    try requireEmptyBytes(raw.flags);
    try requireEmptyBytes(raw.version);
    try requireEmptyBytes(raw.release);
    if (raw.epoch != 0 or raw.comparison != 0 or raw.sense != 0) {
        return error.InvalidAbi;
    }
    inline for (.{
        raw.has_epoch,
        raw.has_flags,
        raw.has_version,
        raw.has_release,
        raw.pre,
    }) |raw_flag| {
        if (try decodeFlag(raw_flag)) return error.InvalidAbi;
    }
}

fn requireEmptyBytes(raw: abi.Bytes) DecodeError!void {
    const value = try borrowedBytes(raw);
    if (value.len != 0) return error.InvalidAbi;
}

fn decodeFlag(raw: u32) DecodeError!bool {
    return switch (raw) {
        0 => false,
        1 => true,
        else => error.InvalidAbi,
    };
}

fn borrowedBytes(raw: abi.Bytes) DecodeError![]const u8 {
    if (raw.length == 0) {
        if (raw.data != null) return error.InvalidAbi;
        return &.{};
    }
    if (raw.length > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return error.InvalidAbi;
    }
    const pointer = raw.data orelse return error.InvalidAbi;
    return pointer[0..raw.length];
}

fn borrowedArray(
    comptime T: type,
    raw_pointer: ?[*]const T,
    raw_count: u32,
) DecodeError![]const T {
    if (raw_count == 0) {
        if (raw_pointer != null) return error.InvalidAbi;
        return &.{};
    }
    const count = std.math.cast(usize, raw_count) orelse
        return error.InvalidAbi;
    if (count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return error.InvalidAbi;
    }
    const byte_length = std.math.mul(usize, count, @sizeOf(T)) catch
        return error.InvalidAbi;
    if (byte_length > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return error.InvalidAbi;
    }
    const pointer = raw_pointer orelse return error.InvalidAbi;
    return pointer[0..count];
}

fn makeHandles(
    allocator: Allocator,
    comptime prefix: []const u8,
    raw_count: u32,
) DecodeError![]const []const u8 {
    const count = std.math.cast(usize, raw_count) orelse
        return error.InvalidAbi;
    const output = try allocator.alloc([]const u8, count);
    for (output, 0..) |*handle, index| {
        handle.* = try std.fmt.allocPrint(
            allocator,
            prefix ++ "-{x:0>8}",
            .{@as(u32, @intCast(index))},
        );
    }
    return output;
}

fn referencedHandle(
    handles: []const []const u8,
    raw_ref: u32,
) DecodeError![]const u8 {
    const index = std.math.cast(usize, raw_ref) orelse
        return error.InvalidAbi;
    if (index >= handles.len) return error.InvalidAbi;
    return handles[index];
}

fn referencedValue(
    comptime T: type,
    values: []const T,
    raw_ref: u32,
) DecodeError!*const T {
    const index = std.math.cast(usize, raw_ref) orelse
        return error.InvalidAbi;
    if (index >= values.len) return error.InvalidAbi;
    return &values[index];
}

fn decodeRequestKind(raw: u32) DecodeError!transaction_plan.RequestKind {
    return switch (raw) {
        abi.request_kind.distro_sync => .distro_sync,
        abi.request_kind.downgrade => .downgrade,
        abi.request_kind.erase => .erase,
        abi.request_kind.install => .install,
        abi.request_kind.lock => .lock,
        abi.request_kind.reinstall => .reinstall,
        abi.request_kind.update => .update,
        abi.request_kind.update_all => .update_all,
        else => error.InvalidAbi,
    };
}

fn decodeJobAction(raw: u32) DecodeError!transaction_plan.JobAction {
    return switch (raw) {
        abi.job_action.install => .install,
        abi.job_action.erase => .erase,
        abi.job_action.update => .update,
        abi.job_action.downgrade => .downgrade,
        abi.job_action.dist_sync => .dist_sync,
        abi.job_action.reinstall => .reinstall,
        abi.job_action.lock => .lock,
        abi.job_action.multiversion => .multiversion,
        abi.job_action.user_installed => .user_installed,
        abi.job_action.allow_uninstall => .allow_uninstall,
        else => error.InvalidAbi,
    };
}

fn decodeRequestReason(raw: u32) DecodeError!transaction_plan.RequestReason {
    return switch (raw) {
        abi.request_reason.user => .user,
        abi.request_reason.dependency => .dependency,
        abi.request_reason.weak_dependency => .weak_dependency,
        abi.request_reason.cleanup => .cleanup,
        abi.request_reason.installonly_limit => .installonly_limit,
        abi.request_reason.policy => .policy,
        else => error.InvalidAbi,
    };
}

fn decodePackageState(raw: u32) DecodeError!transaction_plan.PackageState {
    return switch (raw) {
        abi.package_state.available => .available,
        abi.package_state.installed => .installed,
        else => error.InvalidAbi,
    };
}

fn decodeActionKind(raw: u32) DecodeError!transaction_plan.ActionKind {
    return switch (raw) {
        abi.action_kind.downgrade => .downgrade,
        abi.action_kind.erase => .erase,
        abi.action_kind.install => .install,
        abi.action_kind.obsolete => .obsolete,
        abi.action_kind.reinstall => .reinstall,
        abi.action_kind.upgrade => .upgrade,
        else => error.InvalidAbi,
    };
}

fn decodeActionReason(raw: u32) DecodeError!transaction_plan.ActionReason {
    return switch (raw) {
        abi.action_reason.cleanup => .cleanup,
        abi.action_reason.dependency => .dependency,
        abi.action_reason.installonly_limit => .installonly_limit,
        abi.action_reason.obsoletes => .obsoletes,
        abi.action_reason.policy => .policy,
        abi.action_reason.user => .user,
        abi.action_reason.weak_dependency => .weak_dependency,
        else => error.InvalidAbi,
    };
}

fn decodeProblemKind(raw: u32) DecodeError!transaction_plan.ProblemKind {
    return switch (raw) {
        abi.problem_kind.conflict => .conflict,
        abi.problem_kind.installonly_limit => .installonly_limit,
        abi.problem_kind.no_candidate => .no_candidate,
        abi.problem_kind.not_installable => .not_installable,
        abi.problem_kind.obsoletes => .obsoletes,
        abi.problem_kind.protected_package => .protected_package,
        abi.problem_kind.unsatisfied_requirement => .unsatisfied_requirement,
        abi.problem_kind.same_name => .same_name,
        else => error.InvalidAbi,
    };
}

fn decodeCompareOp(raw: u32) DecodeError!transaction_plan.CompareOp {
    return switch (raw) {
        abi.compare_op.eq => .eq,
        abi.compare_op.ge => .ge,
        abi.compare_op.gt => .gt,
        abi.compare_op.le => .le,
        abi.compare_op.lt => .lt,
        abi.compare_op.none => .none,
        else => error.InvalidAbi,
    };
}

fn decodeResolutionStatus(
    raw: u32,
) DecodeError!transaction_plan.ResolutionStatus {
    return switch (raw) {
        abi.resolution_status.problems => .problems,
        abi.resolution_status.resolved => .resolved,
        abi.resolution_status.resolved_with_skips => .resolved_with_skips,
        else => error.InvalidAbi,
    };
}

fn decodeRpmdbBackend(raw: u32) DecodeError!transaction_plan.RpmdbBackend {
    return switch (raw) {
        abi.rpmdb_backend.bdb => .bdb,
        abi.rpmdb_backend.ndb => .ndb,
        abi.rpmdb_backend.sqlite => .sqlite,
        else => error.InvalidAbi,
    };
}

fn decodeRepositoryKind(raw: u32) DecodeError!transaction_plan.RepositoryKind {
    return switch (raw) {
        abi.repository_kind.available => .available,
        abi.repository_kind.installed => .installed,
        abi.repository_kind.command_line => .command_line,
        else => error.InvalidAbi,
    };
}

const test_sha_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const test_sha_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const test_sha_c = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

fn testBytes(value: []const u8) abi.Bytes {
    std.debug.assert(value.len != 0);
    return .{ .data = value.ptr, .length = value.len };
}

fn testChecksum(
    kind: []const u8,
    value: []const u8,
    is_pkgid: bool,
) abi.Checksum {
    return .{
        .kind = testBytes(kind),
        .value = testBytes(value),
        .is_pkgid = @intFromBool(is_pkgid),
    };
}

fn testLocation(href: []const u8, xml_base: ?[]const u8) abi.Location {
    var result = abi.Location{ .href = testBytes(href) };
    if (xml_base) |value| {
        result.xml_base = testBytes(value);
        result.has_xml_base = 1;
    }
    return result;
}

fn testCapability(name: []const u8) abi.Capability {
    return .{
        .name = testBytes(name),
        .flags = testBytes("GE"),
        .version = testBytes("2.0"),
        .release = testBytes("1"),
        .epoch = 1,
        .comparison = abi.compare_op.ge,
        .sense = 0x104,
        .has_epoch = 1,
        .has_flags = 1,
        .has_version = 1,
        .has_release = 1,
        .pre = 1,
    };
}

const TestFixture = struct {
    excludes: [2]abi.Bytes,
    installonly_names: [2]abi.Bytes,
    locked_names: [1]abi.Bytes,
    min_versions: [2]abi.MinVersion,
    protected_names: [2]abi.Bytes,
    metadata_records: [2]abi.MetadataRecord,
    repositories: [3]abi.Repository,
    requests: [2]abi.Request,
    jobs: [4]abi.Job,
    packages: [5]abi.Package,
    actions: [2]abi.Action,
    prior_package_refs: [1]u32,
    selected_package_refs: [3]u32,
    skipped_job_refs: [1]u32,
    hidden_package_refs: [2]u32,
    problems: [2]abi.Problem,
    input: abi.Capture,

    fn init(self: *TestFixture) void {
        self.* = std.mem.zeroes(TestFixture);

        self.excludes = .{
            testBytes("debug-*"),
            testBytes("*.src"),
        };
        self.installonly_names = .{
            testBytes("kernel"),
            testBytes("kernel-devel"),
        };
        self.locked_names = .{testBytes("filesystem")};
        self.min_versions = .{
            .{
                .arch = testBytes("x86_64"),
                .name = testBytes("openssl"),
                .release = testBytes("1"),
                .version = testBytes("3.0"),
                .epoch = 0,
                .has_arch = 1,
                .has_epoch = 1,
                .has_release = 1,
            },
            .{
                .name = testBytes("zlib"),
                .version = testBytes("1.2"),
            },
        };
        self.protected_names = .{
            testBytes("systemd"),
            testBytes("tdnf"),
        };

        self.metadata_records = .{
            .{
                .checksum = testChecksum("sha256", test_sha_b, false),
                .location = testLocation("repodata/primary.xml.zst", null),
                .open_checksum = testChecksum("sha256", test_sha_c, false),
                .record_type = testBytes("primary"),
                .open_size = 1000,
                .size = 500,
                .timestamp = 42,
                .has_checksum = 1,
                .has_open_checksum = 1,
                .has_open_size = 1,
                .has_size = 1,
                .has_timestamp = 1,
            },
            .{
                .location = testLocation(
                    "repodata/filelists.sqlite",
                    "../metadata",
                ),
                .record_type = testBytes("filelists_db"),
                .database_version = 10,
                .has_database_version = 1,
            },
        };

        self.repositories = .{
            .{
                .id = testBytes("base"),
                .repomd = .{
                    .checksum_sha256 = testBytes(test_sha_a),
                    .records = self.metadata_records[0..].ptr,
                    .revision = testBytes("rev-1"),
                    .timestamp = 42,
                    .record_count = self.metadata_records.len,
                    .has_revision = 1,
                },
                .snapshot = .{
                    .id = testBytes("snapshot-v2-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
                    .metadata_sha256 = testBytes(test_sha_b),
                },
                .priority = 10,
                .cost = 1000,
                .kind = abi.repository_kind.available,
                .has_repomd = 1,
                .has_snapshot = 1,
            },
            .{
                .id = testBytes("@System"),
                .kind = abi.repository_kind.installed,
            },
            .{
                .id = testBytes("command-line"),
                .kind = abi.repository_kind.command_line,
            },
        };

        self.requests = .{
            .{
                .id = testBytes("req-update"),
                .subject = testBytes("raw alpha subject"),
                .kind = abi.request_kind.update,
                .has_subject = 1,
            },
            .{
                .id = testBytes("req-install"),
                .subject = testBytes("cli-package.rpm"),
                .kind = abi.request_kind.install,
                .has_subject = 1,
            },
        };

        self.jobs = .{
            .{
                .selection_value = testBytes("alpha"),
                .action = abi.job_action.update,
                .selection_kind = abi.selection_kind.name,
                .reason = abi.request_reason.user,
                .request_ref = 0,
                .has_request_ref = 1,
                .force_best = 1,
            },
            .{
                .action = abi.job_action.install,
                .selection_kind = abi.selection_kind.package,
                .selection_package_ref = 2,
                .reason = abi.request_reason.user,
                .request_ref = 1,
                .has_request_ref = 1,
                .clean_deps = 1,
                .targeted = 1,
            },
            .{
                .capability = testCapability("libfeature.so.1()(64bit)"),
                .action = abi.job_action.install,
                .selection_kind = abi.selection_kind.capability,
                .reason = abi.request_reason.dependency,
                .not_by_user = 1,
                .weak = 1,
            },
            .{
                .action = abi.job_action.update,
                .selection_kind = abi.selection_kind.all,
                .reason = abi.request_reason.policy,
            },
        };

        self.packages = .{
            .{
                .identity = .{
                    .arch = testBytes("x86_64"),
                    .name = testBytes("alpha"),
                    .release = testBytes("1"),
                    .version = testBytes("2.0"),
                    .epoch = 0,
                    .has_epoch = 1,
                },
                .source = .{
                    .checksum = testChecksum("sha256", test_sha_c, true),
                    .location = testLocation("pool/alpha.rpm", "../packages"),
                    .size = 10,
                    .has_location = 1,
                    .has_size = 1,
                },
                .repository_ref = 0,
                .state = abi.package_state.available,
                .has_source = 1,
            },
            .{
                .identity = .{
                    .arch = testBytes("x86_64"),
                    .name = testBytes("alpha"),
                    .release = testBytes("1"),
                    .version = testBytes("1.0"),
                    .epoch = 0,
                    .has_epoch = 1,
                },
                .repository_ref = 1,
                .rpmdb_hnum = 10,
                .state = abi.package_state.installed,
                .has_rpmdb_hnum = 1,
            },
            .{
                .identity = .{
                    .arch = testBytes("noarch"),
                    .name = testBytes("cli-extra"),
                    .release = testBytes("1"),
                    .version = testBytes("1.0"),
                },
                .source = .{
                    .checksum = testChecksum("sha256", test_sha_a, false),
                    .size = 99,
                    .has_size = 1,
                },
                .repository_ref = 2,
                .state = abi.package_state.available,
                .has_source = 1,
            },
            .{
                .identity = .{
                    .arch = testBytes("x86_64"),
                    .name = testBytes("retained"),
                    .release = testBytes("2"),
                    .version = testBytes("4.0"),
                },
                .repository_ref = 1,
                .rpmdb_hnum = 11,
                .state = abi.package_state.installed,
                .has_rpmdb_hnum = 1,
            },
            .{
                .identity = .{
                    .arch = testBytes("x86_64"),
                    .name = testBytes("candidate"),
                    .release = testBytes("1"),
                    .version = testBytes("1.0"),
                },
                .source = .{
                    .checksum = testChecksum("sha256", test_sha_b, false),
                    .location = testLocation("pool/candidate.rpm", null),
                    .has_location = 1,
                },
                .repository_ref = 0,
                .state = abi.package_state.available,
                .has_source = 1,
            },
        };

        self.actions = .{
            .{
                .target_package_ref = 0,
                .kind = abi.action_kind.upgrade,
                .reason = abi.action_reason.user,
                .requested_job_ref = 0,
                .has_requested_job_ref = 1,
                .prior_offset = 0,
                .prior_count = 1,
            },
            .{
                .target_package_ref = 2,
                .kind = abi.action_kind.install,
                .reason = abi.action_reason.user,
                .requested_job_ref = 1,
                .has_requested_job_ref = 1,
                .prior_offset = 1,
                .prior_count = 0,
            },
        };
        self.prior_package_refs = .{1};
        self.selected_package_refs = .{ 0, 2, 3 };
        self.skipped_job_refs = .{2};
        self.hidden_package_refs = .{ 4, 3 };
        self.problems = .{
            .{
                .capability = testCapability("libmissing.so.2()(64bit)"),
                .count = 2,
                .kind = abi.problem_kind.unsatisfied_requirement,
                .job_ref = 2,
                .package_ref = 4,
                .related_package_ref = 1,
                .has_capability = 1,
                .has_job_ref = 1,
                .has_package_ref = 1,
                .has_related_package_ref = 1,
            },
            .{
                .count = 1,
                .kind = abi.problem_kind.no_candidate,
                .job_ref = 2,
                .has_job_ref = 1,
            },
        };

        self.input = .{
            .abi_version = abi.abi_version,
            .struct_size = capture_struct_size,
            .environment = .{
                .architecture = testBytes("x86_64"),
                .distro = testBytes("photon"),
                .policy = .{
                    .excludes = self.excludes[0..].ptr,
                    .installonly_names = self.installonly_names[0..].ptr,
                    .locked_names = self.locked_names[0..].ptr,
                    .min_versions = self.min_versions[0..].ptr,
                    .protected_names = self.protected_names[0..].ptr,
                    .force_architecture = testBytes("x86_64"),
                    .exclude_count = self.excludes.len,
                    .installonly_name_count = self.installonly_names.len,
                    .locked_name_count = self.locked_names.len,
                    .min_version_count = self.min_versions.len,
                    .protected_name_count = self.protected_names.len,
                    .allow_erasing = 1,
                    .allow_multilib = 1,
                    .all_deps = 0,
                    .best = 1,
                    .clean_requirements_on_remove = 1,
                    .has_force_architecture = 1,
                    .include_installed = 1,
                    .installonly_limit = 3,
                    .install_weak_dependencies = 1,
                    .keep_orphans = 0,
                    .skip_broken = 1,
                },
                .releasever = testBytes("5.0"),
                .rpmdb = .{
                    .cookie_sha256 = testBytes(test_sha_a),
                    .package_set_sha256 = testBytes(test_sha_b),
                    .backend = abi.rpmdb_backend.sqlite,
                },
                .resolution_status = abi.resolution_status.resolved_with_skips,
            },
            .repositories = self.repositories[0..].ptr,
            .requests = self.requests[0..].ptr,
            .jobs = self.jobs[0..].ptr,
            .packages = self.packages[0..].ptr,
            .actions = self.actions[0..].ptr,
            .prior_package_refs = self.prior_package_refs[0..].ptr,
            .selected_package_refs = self.selected_package_refs[0..].ptr,
            .skipped_job_refs = self.skipped_job_refs[0..].ptr,
            .hidden_package_refs = self.hidden_package_refs[0..].ptr,
            .problems = self.problems[0..].ptr,
            .repository_count = self.repositories.len,
            .request_count = self.requests.len,
            .job_count = self.jobs.len,
            .package_count = self.packages.len,
            .action_count = self.actions.len,
            .prior_package_ref_count = self.prior_package_refs.len,
            .selected_package_ref_count = self.selected_package_refs.len,
            .skipped_job_ref_count = self.skipped_job_refs.len,
            .hidden_package_ref_count = self.hidden_package_refs.len,
            .problem_count = self.problems.len,
        };
    }
};

test "full borrowed fixture creates an owned lossless plan" {
    var fixture: TestFixture = undefined;
    fixture.init();
    const owner = try createOwner(std.testing.allocator, &fixture.input);
    defer owner.destroy();

    const data = owner.plan.model();
    try std.testing.expectEqual(@as(usize, 3), data.repositories.len);
    try std.testing.expectEqual(@as(usize, 2), data.requests.len);
    try std.testing.expectEqual(@as(usize, 4), data.jobs.len);
    try std.testing.expectEqual(@as(usize, 5), data.packages.len);
    try std.testing.expectEqual(@as(usize, 2), data.actions.len);
    try std.testing.expectEqual(@as(usize, 2), data.problems.len);
    try std.testing.expectEqualStrings("package-00000000", data.packages[0].id);
    try std.testing.expectEqualStrings("job-00000002", data.jobs[2].id);
    try std.testing.expectEqualStrings("problem-00000001", data.problems[1].id);
    try std.testing.expectEqualStrings(
        "raw alpha subject",
        data.requests[0].subject.?,
    );
    try std.testing.expectEqualStrings(
        "alpha",
        data.jobs[0].selection.name,
    );
    try std.testing.expectEqualStrings(
        "package-00000002",
        data.jobs[1].selection.package,
    );
    try std.testing.expectEqual(
        transaction_plan.CompareOp.ge,
        data.jobs[2].selection.capability.comparison,
    );
    try std.testing.expectEqual(@as(?u64, 1), data.jobs[2].selection.capability.epoch);
    try std.testing.expect(data.packages[2].source.?.location == null);
    try std.testing.expectEqual(@as(?u64, 99), data.packages[2].source.?.size);
    try std.testing.expect(data.packages[4].source.?.size == null);
    try std.testing.expectEqual(@as(?u32, 10), data.packages[1].rpmdb_hnum);
    try std.testing.expectEqual(@as(usize, 1), data.actions[0].prior_package_ids.len);
    try std.testing.expectEqualStrings(
        "package-00000001",
        data.actions[0].prior_package_ids[0],
    );
    try std.testing.expectEqualStrings(
        "filelists_db",
        data.repositories[0].repomd.?.records[1].record_type,
    );
    try std.testing.expectEqual(
        @as(?u64, 10),
        data.repositories[0].repomd.?.records[1].database_version,
    );
    try std.testing.expect(data.problems[1].capability == null);
}

fn remapIndex(comptime count: usize, map: [count]u32, value: u32) u32 {
    std.debug.assert(value < count);
    return map[value];
}

fn permuteFixture(fixture: *TestFixture) void {
    const repository_map = [_]u32{ 1, 2, 0 };
    for (&fixture.packages) |*package| {
        package.repository_ref = remapIndex(
            repository_map.len,
            repository_map,
            package.repository_ref,
        );
    }
    const repositories = fixture.repositories;
    fixture.repositories = .{
        repositories[2],
        repositories[0],
        repositories[1],
    };

    const request_map = [_]u32{ 1, 0 };
    for (&fixture.jobs) |*job| {
        if (job.has_request_ref == 1) {
            job.request_ref = remapIndex(
                request_map.len,
                request_map,
                job.request_ref,
            );
        }
    }
    const requests = fixture.requests;
    fixture.requests = .{ requests[1], requests[0] };

    const package_map = [_]u32{ 2, 4, 1, 3, 0 };
    for (&fixture.jobs) |*job| {
        if (job.selection_kind == abi.selection_kind.package) {
            job.selection_package_ref = remapIndex(
                package_map.len,
                package_map,
                job.selection_package_ref,
            );
        }
    }
    for (&fixture.actions) |*action| {
        action.target_package_ref = remapIndex(
            package_map.len,
            package_map,
            action.target_package_ref,
        );
    }
    for (&fixture.prior_package_refs) |*package_ref| {
        package_ref.* = remapIndex(
            package_map.len,
            package_map,
            package_ref.*,
        );
    }
    for (&fixture.selected_package_refs) |*package_ref| {
        package_ref.* = remapIndex(
            package_map.len,
            package_map,
            package_ref.*,
        );
    }
    for (&fixture.hidden_package_refs) |*package_ref| {
        package_ref.* = remapIndex(
            package_map.len,
            package_map,
            package_ref.*,
        );
    }
    for (&fixture.problems) |*problem| {
        if (problem.has_package_ref == 1) {
            problem.package_ref = remapIndex(
                package_map.len,
                package_map,
                problem.package_ref,
            );
        }
        if (problem.has_related_package_ref == 1) {
            problem.related_package_ref = remapIndex(
                package_map.len,
                package_map,
                problem.related_package_ref,
            );
        }
    }
    const packages = fixture.packages;
    fixture.packages = .{
        packages[4],
        packages[2],
        packages[0],
        packages[3],
        packages[1],
    };

    const job_map = [_]u32{ 1, 3, 0, 2 };
    for (&fixture.actions) |*action| {
        if (action.has_requested_job_ref == 1) {
            action.requested_job_ref = remapIndex(
                job_map.len,
                job_map,
                action.requested_job_ref,
            );
        }
    }
    for (&fixture.skipped_job_refs) |*job_ref| {
        job_ref.* = remapIndex(job_map.len, job_map, job_ref.*);
    }
    for (&fixture.problems) |*problem| {
        if (problem.has_job_ref == 1) {
            problem.job_ref = remapIndex(
                job_map.len,
                job_map,
                problem.job_ref,
            );
        }
    }
    const jobs = fixture.jobs;
    fixture.jobs = .{ jobs[2], jobs[0], jobs[3], jobs[1] };

    const actions = fixture.actions;
    fixture.actions = .{ actions[1], actions[0] };
    fixture.actions[0].prior_offset = 0;
    fixture.actions[1].prior_offset = 0;

    const selected = fixture.selected_package_refs;
    fixture.selected_package_refs = .{
        selected[2],
        selected[0],
        selected[1],
    };
    const hidden = fixture.hidden_package_refs;
    fixture.hidden_package_refs = .{ hidden[1], hidden[0] };
    const problems = fixture.problems;
    fixture.problems = .{ problems[1], problems[0] };
    const records = fixture.metadata_records;
    fixture.metadata_records = .{ records[1], records[0] };
    const excludes = fixture.excludes;
    fixture.excludes = .{ excludes[1], excludes[0] };
    const protected_names = fixture.protected_names;
    fixture.protected_names = .{ protected_names[1], protected_names[0] };
}

test "remapped input permutations retain canonical identity" {
    var first_fixture: TestFixture = undefined;
    first_fixture.init();
    const first = try buildPlan(std.testing.allocator, &first_fixture.input);
    defer first.destroy();
    const first_digest = try first.digest(std.testing.allocator);

    var second_fixture: TestFixture = undefined;
    second_fixture.init();
    permuteFixture(&second_fixture);
    const second = try buildPlan(std.testing.allocator, &second_fixture.input);
    defer second.destroy();
    const second_digest = try second.digest(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, &first_digest, &second_digest);
}

fn expectInvalidAbi(input: *const abi.Capture) !void {
    try std.testing.expectError(
        error.InvalidAbi,
        buildPlan(std.testing.allocator, input),
    );
}

test "capture rejects malformed ABI facts before publication" {
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.input.abi_version += 1;
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.input.struct_size -= 1;
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.input.selected_package_refs = null;
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.input.selected_package_ref_count = 0;
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.input.environment.architecture.data = null;
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.requests[0].has_subject = 2;
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.packages[1].source.checksum.kind = testBytes("sha256");
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.jobs[0].action = std.math.maxInt(u32);
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.packages[0].repository_ref = fixture.input.repository_count;
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.jobs[1].selection_package_ref = fixture.input.package_count;
        try expectInvalidAbi(&fixture.input);
    }
    {
        var fixture: TestFixture = undefined;
        fixture.init();
        fixture.actions[0].prior_offset = std.math.maxInt(u32);
        fixture.actions[0].prior_count = 2;
        try expectInvalidAbi(&fixture.input);
    }
}

test "model validation rejects invalid borrowed UTF-8" {
    var fixture: TestFixture = undefined;
    fixture.init();
    var invalid_utf8 = [_]u8{0xff};
    fixture.input.environment.architecture = testBytes(&invalid_utf8);
    try std.testing.expectError(
        error.InvalidString,
        buildPlan(std.testing.allocator, &fixture.input),
    );
}

test "capture owner is independent of borrowed input mutation" {
    var fixture: TestFixture = undefined;
    fixture.init();
    var subject = "mutable subject".*;
    fixture.requests[0].subject = testBytes(&subject);

    const owner = try createOwner(std.testing.allocator, &fixture.input);
    defer owner.destroy();
    subject[0] = 'X';
    fixture.requests[0].subject = testBytes("replacement");
    fixture.selected_package_refs[0] = 4;

    try std.testing.expectEqualStrings(
        "mutable subject",
        owner.plan.model().requests[0].subject.?,
    );
    try std.testing.expectEqualStrings(
        "package-00000000",
        owner.plan.model().selected[0].package_id,
    );
}

test "C entry points null output and map stable errors" {
    var fixture: TestFixture = undefined;
    fixture.init();
    var sentinel_storage: usize = 0;
    var output: ?*Owner = @ptrCast(&sentinel_storage);

    fixture.input.abi_version += 1;
    try std.testing.expectEqual(
        error_codes.ERROR_TDNF_INVALID_PARAMETER,
        transactionPlanCaptureCreate(&fixture.input, &output),
    );
    try std.testing.expect(output == null);

    output = @ptrCast(&sentinel_storage);
    try std.testing.expectEqual(
        error_codes.ERROR_TDNF_INVALID_PARAMETER,
        transactionPlanCaptureCreate(null, &output),
    );
    try std.testing.expect(output == null);
    try std.testing.expectEqual(
        error_codes.ERROR_TDNF_INVALID_PARAMETER,
        transactionPlanCaptureCreate(null, null),
    );
    try std.testing.expectEqual(
        error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        mapCaptureError(error.OutOfMemory),
    );

    fixture.init();
    try std.testing.expectEqual(
        @as(u32, 0),
        transactionPlanCaptureCreate(&fixture.input, &output),
    );
    try std.testing.expect(output != null);
    transactionPlanCaptureDestroy(output);
    transactionPlanCaptureDestroy(null);
}

fn captureAllocationFailureCase(allocator: Allocator) !void {
    var fixture: TestFixture = undefined;
    fixture.init();
    const owner = try createOwner(allocator, &fixture.input);
    defer owner.destroy();
    try std.testing.expectEqual(@as(usize, 5), owner.plan.model().packages.len);
}

test "capture adapter cleans every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        captureAllocationFailureCase,
        .{},
    );
}

test "request trace remaps stable capture facts without queue or path data" {
    var trace = request_trace.Trace.init(std.testing.allocator);
    defer trace.deinit();
    const update_request = try trace.addRequest(
        abi.request_kind.update,
        "raw alpha subject",
        true,
    );
    const install_request = try trace.addRequest(
        abi.request_kind.install,
        "/home/user/credential-bearing-cli-package.rpm",
        true,
    );
    try trace.recordNameJob(
        0,
        abi.job_action.update,
        "alpha",
        0x101,
        abi.request_trace_flag.force_best,
        abi.request_reason.user,
        update_request,
    );
    try trace.recordPackageJob(
        1,
        abi.job_action.install,
        200,
        0x102,
        abi.request_trace_flag.clean_deps |
            abi.request_trace_flag.targeted,
        abi.request_reason.user,
        install_request,
    );
    try trace.recordCapabilityJob(
        2,
        abi.job_action.install,
        .{
            .name = "libfeature.so.1()(64bit)",
            .flags = "GE",
            .version = "2.0",
            .release = "1",
            .epoch = 1,
            .comparison = abi.compare_op.ge,
            .sense = 0x104,
            .pre = true,
        },
        0x103,
        abi.request_trace_flag.not_by_user |
            abi.request_trace_flag.weak,
        abi.request_reason.dependency,
        abi.request_trace_no_request,
    );
    try trace.recordAllJob(
        3,
        abi.job_action.update,
        0x104,
        0,
        abi.request_reason.policy,
        abi.request_trace_no_request,
    );
    const queue = [_]i32{
        0x101, 0,
        0x102, 200,
        0x103, 0,
        0x104, 0,
    };
    try trace.finalize(&queue, 0, 0);

    const first_map = [_]abi.RequestTracePackageRef{
        .{ .selection_id = 999, .package_ref = 4 },
        .{ .selection_id = 200, .package_ref = 2 },
    };
    const first = try request_trace.CaptureFactsOwner.create(
        std.testing.allocator,
        &trace,
        &first_map,
    );
    defer first.destroy();
    const second_map = [_]abi.RequestTracePackageRef{
        .{ .selection_id = 200, .package_ref = 2 },
        .{ .selection_id = 999, .package_ref = 4 },
    };
    const second = try request_trace.CaptureFactsOwner.create(
        std.testing.allocator,
        &trace,
        &second_map,
    );
    defer second.destroy();
    try std.testing.expectEqual(
        first.facts.jobs.?[1].selection_package_ref,
        second.facts.jobs.?[1].selection_package_ref,
    );
    try std.testing.expectEqual(@as(u32, 2), first.facts.jobs.?[1].selection_package_ref);
    try std.testing.expectEqual(@as(u32, 0), first.facts.requests.?[1].has_subject);

    var fixture: TestFixture = undefined;
    fixture.init();
    @memcpy(
        fixture.requests[0..],
        first.facts.requests.?[0..first.facts.request_count],
    );
    @memcpy(
        fixture.jobs[0..],
        first.facts.jobs.?[0..first.facts.job_count],
    );
    const owner = try createOwner(std.testing.allocator, &fixture.input);
    defer owner.destroy();
    const canonical = try owner.plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(canonical);
    try std.testing.expect(std.mem.indexOf(u8, canonical, "/home/user") == null);
    try std.testing.expect(std.mem.indexOf(u8, canonical, "queue_pair") == null);
    try std.testing.expect(std.mem.indexOf(u8, canonical, "raw_how") == null);
}
