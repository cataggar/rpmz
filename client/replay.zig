//! Supported offline transaction replay API.
//!
//! Replay accepts only a closed bundle directory and an explicit RPM target.
//! It does not accept repository configuration, solver jobs, URLs, caches, or
//! fetch callbacks, and it calls the fixed-order native executor directly.

const std = @import("std");
const abi = @import("client_abi");
const bundle_reader = @import("bundle_reader");
const bundle_selection = @import("bundle_selection");
const canonical_json = @import("canonical_json");
const content_digest = @import("content_digest");
const fixed = @import("transaction.zig");
const repomd = @import("repomd_client_exports");
const rpm_gpgcheck = @import("rpm_gpgcheck");
const rpm_header = @import("rpm_header");
const transaction_bundle = @import("transaction_bundle");
const transaction_lock = @import("transaction_lock");
const transaction_plan = @import("transaction_plan");
const txn_config = @import("rpm_txn_config");
const verified_fetch = @import("verified_fetch");

const Allocator = std.mem.Allocator;
const rpmdb_package_set_domain = "tdnf.rpmdb-package-set/v1";

const RpmdbIterator = opaque {};
extern fn TDNFTransactionPlanRpmdbSnapshotOpenConfig(
    config: *const anyopaque,
    cookie: *?[*:0]u8,
) ?*RpmdbIterator;
extern fn tdnf_rpmdb_iter_close(iterator: ?*RpmdbIterator) void;
extern fn tdnf_rpmdb_iter_next_header_blob_hnum(
    iterator: ?*RpmdbIterator,
    hnum: *u32,
    blob: *?[*]const u8,
    length: *usize,
) i32;
extern fn tdnf_rpmdb_string_free(value: ?[*:0]u8) void;

pub const result_schema = "tdnf.replay-result/v1";

/// The only target coordinates replay accepts. `rpmdb_path` is the absolute
/// install-root-relative `_dbpath` understood by the native RPM configuration
/// (normally `/var/lib/rpm`).
pub const Target = struct {
    install_root: []const u8,
    rpmdb_path: []const u8,
    architecture: []const u8,
};

pub const Input = struct {
    bundle_directory: []const u8,
    target: Target,
};

pub const Status = enum {
    validation_failed,
    transaction_failed,
    succeeded,
};

pub const ValidationFailure = enum {
    invalid_input,
    bundle_unreadable,
    manifest_not_canonical,
    missing_bundle_file,
    additional_bundle_file,
    unsafe_bundle_entry,
    checksum_mismatch,
    size_mismatch,
    non_replayable_bundle,
    plan_mismatch,
    repository_mismatch,
    metadata_mismatch,
    rpm_mismatch,
    signature_mismatch,
    architecture_mismatch,
    rpmdb_mismatch,
    prior_mismatch,
    action_shape_mismatch,
    lock_failed,
    target_unreadable,
};

pub const TransactionFailure = enum {
    invalid_context,
    invalid_item,
    malformed_order,
    prior_mismatch,
    package_open_failed,
    package_identity_mismatch,
    rpm_check_failed,
    transaction_failed,
    execution_failed,
    expected_inventory_mismatch,
    final_inventory_unreadable,
};

pub const ActionStatus = enum {
    not_attempted,
    applied,
    indeterminate,
};

pub const PackageIdentity = transaction_plan.PackageIdentity;

pub const InstalledPackage = struct {
    hnum: u32,
    identity: PackageIdentity,
};

pub const ActionOutcome = struct {
    index: usize,
    kind: transaction_plan.ActionKind,
    status: ActionStatus,
};

/// Owned, versioned result. `applied_plan_digest` is non-null only for a
/// successful replay. A transaction failure never claims rollback: completed
/// actions remain `applied`, while every other action is `indeterminate`.
pub const Result = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    status: Status,
    validation_failure: ?ValidationFailure,
    transaction_failure: ?TransactionFailure,
    plan_digest: ?[]const u8,
    applied_plan_digest: ?[]const u8,
    actions: []ActionOutcome,
    final_inventory: ?[]const InstalledPackage,

    pub fn deinit(self: *Result) void {
        const allocator = self.allocator;
        self.arena.deinit();
        allocator.destroy(self);
    }

    /// Canonical UTF-8 JSON with fixed member and array ordering.
    pub fn canonicalJsonAlloc(
        self: *const Result,
        allocator: Allocator,
    ) Allocator.Error![]u8 {
        var writer = canonical_json.Writer.init(allocator);
        errdefer writer.deinit();
        try writer.append("{\"actions\":[");
        for (self.actions, 0..) |action, index| {
            if (index != 0) try writer.appendByte(',');
            try writer.append("{\"index\":");
            try writer.writeUint(action.index);
            try writer.append(",\"kind\":");
            try writer.writeString(@tagName(action.kind));
            try writer.append(",\"status\":");
            try writer.writeString(@tagName(action.status));
            try writer.appendByte('}');
        }
        try writer.append("],\"applied_plan_digest\":");
        try writer.writeOptionalString(self.applied_plan_digest);
        try writer.append(",\"final_inventory\":");
        if (self.final_inventory) |inventory| {
            try writer.appendByte('[');
            for (inventory, 0..) |package, index| {
                if (index != 0) try writer.appendByte(',');
                try writeInstalledPackage(&writer, package);
            }
            try writer.appendByte(']');
        } else {
            try writer.append("null");
        }
        try writer.append(",\"plan_digest\":");
        try writer.writeOptionalString(self.plan_digest);
        try writer.append(",\"schema\":");
        try writer.writeString(result_schema);
        try writer.append(",\"status\":");
        try writer.writeString(@tagName(self.status));
        try writer.append(",\"transaction_failure\":");
        if (self.transaction_failure) |failure|
            try writer.writeString(@tagName(failure))
        else
            try writer.append("null");
        try writer.append(",\"validation_failure\":");
        if (self.validation_failure) |failure|
            try writer.writeString(@tagName(failure))
        else
            try writer.append("null");
        try writer.appendByte('}');
        return writer.finish();
    }
};

pub const RunError = error{OutOfMemory};

const PreflightError = error{
    InvalidInput,
    BundleUnreadable,
    ManifestNotCanonical,
    MissingBundleFile,
    AdditionalBundleFile,
    UnsafeBundleEntry,
    ChecksumMismatch,
    SizeMismatch,
    NonReplayableBundle,
    PlanMismatch,
    RepositoryMismatch,
    MetadataMismatch,
    RpmMismatch,
    SignatureMismatch,
    ArchitectureMismatch,
    RpmdbMismatch,
    PriorMismatch,
    ActionShapeMismatch,
    LockFailed,
    TargetUnreadable,
    OutOfMemory,
};

const VerifiedRpm = struct {
    plan_package_id: []const u8,
    path: [:0]const u8,
    handle: *rpm_gpgcheck.FileHandle,
};

const Snapshot = struct {
    cookie_sha256: [64]u8,
    package_set_sha256: [64]u8,
    rows: []const InstalledPackage,
    inventory: []const InstalledPackage,
};

/// Validate the complete bundle and target state before invoking the native
/// fixed-order executor. Callers should additionally enforce OS-level network
/// isolation; this function itself has no network-capable input or code path.
pub fn run(
    allocator: Allocator,
    io: std.Io,
    input: Input,
) RunError!*Result {
    const result = try allocator.create(Result);
    result.* = .{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .status = .validation_failed,
        .validation_failure = .invalid_input,
        .transaction_failure = null,
        .plan_digest = null,
        .applied_plan_digest = null,
        .actions = &.{},
        .final_inventory = null,
    };
    errdefer {
        result.arena.deinit();
        allocator.destroy(result);
    }

    runValidated(result, io, input) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            result.status = .validation_failed;
            result.validation_failure = validationFailure(err);
            result.transaction_failure = null;
            result.applied_plan_digest = null;
        },
    };
    return result;
}

fn runValidated(
    result: *Result,
    io: std.Io,
    input: Input,
) PreflightError!void {
    const arena = result.arena.allocator();
    const scratch = result.allocator;
    try validateInput(input);

    const bundle = bundle_reader.openBundle(
        scratch,
        io,
        input.bundle_directory,
    ) catch |err| return mapBundleOpenError(err);
    defer bundle.destroy();
    if (!bundle.isReplayable() or
        !std.mem.eql(u8, bundle.schemaName(), transaction_bundle.schema_v2))
    {
        return error.NonReplayableBundle;
    }

    var directory = std.Io.Dir.cwd().openDir(io, input.bundle_directory, .{
        .iterate = false,
        .follow_symlinks = false,
    }) catch return error.BundleUnreadable;
    defer directory.close(io);

    const plan_bytes = readBundleFile(
        scratch,
        io,
        directory,
        transaction_bundle.plan_name,
    ) catch return error.PlanMismatch;
    defer scratch.free(plan_bytes);
    const plan = transaction_plan.parse(scratch, plan_bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.PlanMismatch,
    };
    defer plan.destroy();
    if (!plan.isReplayable() or
        !std.mem.eql(u8, plan.schemaName(), transaction_plan.schema_v2))
    {
        return error.NonReplayableBundle;
    }
    const plan_digest = plan.digest(scratch) catch return error.OutOfMemory;
    if (!std.mem.eql(u8, &plan_digest, bundle.model().plan.digest))
        return error.PlanMismatch;
    result.plan_digest = try arena.dupe(u8, &plan_digest);
    result.actions = try initActionOutcomes(arena, plan.model());

    if (!std.mem.eql(
        u8,
        plan.model().environment.architecture,
        input.target.architecture,
    )) return error.ArchitectureMismatch;
    for (plan.model().packages) |package| {
        if (!architectureAllows(input.target.architecture, package.identity.arch))
            return error.ArchitectureMismatch;
    }

    var selection = bundle_selection.select(scratch, plan.model()) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.RepositoryMismatch,
    };
    defer selection.deinit();
    try verifyRepositories(bundle.model(), plan.model());
    try verifyMetadata(scratch, io, directory, bundle, &selection);

    const key_blobs = try scratch.alloc([]const u8, bundle.model().keys.len);
    var loaded_key_count: usize = 0;
    defer {
        for (key_blobs[0..loaded_key_count]) |blob| scratch.free(blob);
        scratch.free(key_blobs);
    }
    const used_keys = try scratch.alloc(bool, bundle.model().keys.len);
    defer scratch.free(used_keys);
    @memset(used_keys, false);
    for (bundle.model().keys, key_blobs) |key, *blob| {
        blob.* = readBundleFile(scratch, io, directory, key.path) catch
            return error.SignatureMismatch;
        loaded_key_count += 1;
        try verifyFileEntry(bundle, key.path, blob.*);
    }

    var verified: std.ArrayList(VerifiedRpm) = .empty;
    defer {
        for (verified.items) |package| rpm_gpgcheck.closeFile(package.handle);
        verified.deinit(scratch);
    }
    for (bundle.model().packages) |package| {
        const absolute = std.fs.path.joinZ(
            arena,
            &.{ input.bundle_directory, package.path },
        ) catch return error.OutOfMemory;
        const handle = rpm_gpgcheck.openFile(absolute) catch
            return error.RpmMismatch;
        errdefer rpm_gpgcheck.closeFile(handle);
        try verifyPinnedRpm(
            scratch,
            bundle,
            package,
            handle,
            key_blobs,
            used_keys,
            input.target.architecture,
        );
        try verified.append(scratch, .{
            .plan_package_id = package.plan_package_id,
            .path = absolute,
            .handle = handle,
        });
    }
    for (used_keys) |used| if (!used) return error.SignatureMismatch;

    var rpm_config = txn_config.TxnConfig.init(
        scratch,
        input.target.install_root,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidInput,
    };
    defer rpm_config.deinit();
    rpm_config.setMacro(.dbpath, input.target.rpmdb_path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidInput,
    };

    var target_guard = transaction_lock.acquire(
        scratch,
        &rpm_config,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidTarget => error.TargetUnreadable,
        error.LockFailed, error.WouldBlock => error.LockFailed,
    };
    defer target_guard.deinit();
    const locked_config = target_guard.config();

    const before = try captureSnapshot(arena, locked_config);
    result.final_inventory = before.inventory;
    try verifyRpmdbIdentity(plan.model(), before);
    try verifyInstalledRows(plan.model(), before.rows);

    const built = try buildFixedOrder(
        arena,
        plan.model(),
        before.rows,
        verified.items,
    );

    const install_root_z = arena.dupeZ(
        u8,
        locked_config.installRoot(),
    ) catch return error.OutOfMemory;
    var args = abi.CmdArgs{
        .pszInstallRoot = @constCast(install_root_z.ptr),
        .nQuiet = 1,
    };
    var conf = abi.Conf{};
    var handle = abi.Tdnf{
        .pArgs = &args,
        .pConf = &conf,
        .pRpmConfig = @ptrCast(locked_config),
    };
    var progress = Progress{
        .outcomes = result.actions,
        .item_actions = built.item_actions,
        .completed = try arena.alloc(usize, result.actions.len),
        .expected = try arena.alloc(usize, result.actions.len),
    };
    @memset(progress.completed, 0);
    @memset(progress.expected, 0);
    for (built.item_actions) |action_index| progress.expected[action_index] += 1;

    fixed.executeFixedOrderObserved(
        &handle,
        .{ .items = built.items, .order = built.order },
        .{ .context = &progress, .completedFn = progressCompleted },
    ) catch |err| {
        markIndeterminate(result.actions);
        result.status = .transaction_failed;
        result.validation_failure = null;
        result.transaction_failure = transactionFailure(err);
        const failed_snapshot = captureSnapshot(arena, locked_config) catch {
            result.transaction_failure = .final_inventory_unreadable;
            return;
        };
        result.final_inventory = failed_snapshot.inventory;
        return;
    };

    const after = captureSnapshot(arena, locked_config) catch {
        markIndeterminate(result.actions);
        result.status = .transaction_failed;
        result.validation_failure = null;
        result.transaction_failure = .final_inventory_unreadable;
        result.final_inventory = null;
        return;
    };
    result.final_inventory = after.inventory;
    const inventory_matches = inventoryMatchesPlan(
        arena,
        plan.model(),
        after.inventory,
    ) catch {
        markIndeterminate(result.actions);
        result.status = .transaction_failed;
        result.validation_failure = null;
        result.transaction_failure = .execution_failed;
        return;
    };
    if (!inventory_matches) {
        markIndeterminate(result.actions);
        result.status = .transaction_failed;
        result.validation_failure = null;
        result.transaction_failure = .expected_inventory_mismatch;
        return;
    }

    result.status = .succeeded;
    result.validation_failure = null;
    result.transaction_failure = null;
    result.applied_plan_digest = result.plan_digest;
}

fn validateInput(input: Input) PreflightError!void {
    if (input.bundle_directory.len == 0 or
        !std.fs.path.isAbsolute(input.bundle_directory) or
        input.target.install_root.len == 0 or
        !std.fs.path.isAbsolute(input.target.install_root) or
        input.target.rpmdb_path.len == 0 or
        !std.fs.path.isAbsolute(input.target.rpmdb_path) or
        input.target.architecture.len == 0)
    {
        return error.InvalidInput;
    }
}

fn mapBundleOpenError(err: bundle_reader.OpenError) PreflightError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.BundleUnreadable, error.FileTooLarge => error.BundleUnreadable,
        error.MissingFile => error.MissingBundleFile,
        error.ManifestNotCanonical => error.ManifestNotCanonical,
        error.UnlistedFile => error.AdditionalBundleFile,
        error.UnsafeEntry => error.UnsafeBundleEntry,
        error.ChecksumMismatch => error.ChecksumMismatch,
        error.SizeMismatch => error.SizeMismatch,
        error.PlanMismatch => error.PlanMismatch,
    };
}

fn validationFailure(err: PreflightError) ValidationFailure {
    return switch (err) {
        error.InvalidInput => .invalid_input,
        error.BundleUnreadable => .bundle_unreadable,
        error.ManifestNotCanonical => .manifest_not_canonical,
        error.MissingBundleFile => .missing_bundle_file,
        error.AdditionalBundleFile => .additional_bundle_file,
        error.UnsafeBundleEntry => .unsafe_bundle_entry,
        error.ChecksumMismatch => .checksum_mismatch,
        error.SizeMismatch => .size_mismatch,
        error.NonReplayableBundle => .non_replayable_bundle,
        error.PlanMismatch => .plan_mismatch,
        error.RepositoryMismatch => .repository_mismatch,
        error.MetadataMismatch => .metadata_mismatch,
        error.RpmMismatch => .rpm_mismatch,
        error.SignatureMismatch => .signature_mismatch,
        error.ArchitectureMismatch => .architecture_mismatch,
        error.RpmdbMismatch => .rpmdb_mismatch,
        error.PriorMismatch => .prior_mismatch,
        error.ActionShapeMismatch => .action_shape_mismatch,
        error.LockFailed => .lock_failed,
        error.TargetUnreadable => .target_unreadable,
        error.OutOfMemory => unreachable,
    };
}

fn readBundleFile(
    allocator: Allocator,
    io: std.Io,
    directory: std.Io.Dir,
    path: []const u8,
) ![]u8 {
    return directory.readFileAlloc(
        io,
        path,
        allocator,
        .limited(bundle_reader.max_file_bytes),
    );
}

fn verifyFileEntry(
    bundle: *const transaction_bundle.Bundle,
    path: []const u8,
    bytes: []const u8,
) PreflightError!void {
    const entry = bundle.findFile(path) orelse return error.MissingBundleFile;
    if (entry.size != bytes.len) return error.SizeMismatch;
    const digest = content_digest.sha256Hex(bytes);
    if (!std.ascii.eqlIgnoreCase(entry.sha256, &digest))
        return error.ChecksumMismatch;
}

fn verifyRepositories(
    manifest: *const transaction_bundle.Data,
    plan: *const transaction_plan.Data,
) PreflightError!void {
    var available_count: usize = 0;
    for (plan.repositories) |repository| {
        if (repository.kind != .available) continue;
        available_count += 1;
        const repomd_identity = repository.repomd orelse
            return error.RepositoryMismatch;
        const snapshot = repository.snapshot orelse
            return error.RepositoryMismatch;
        const bundled = findBundledRepository(
            manifest.repositories,
            repository.id,
        ) orelse return error.RepositoryMismatch;
        if (bundled.cost != repository.cost or
            bundled.priority != repository.priority or
            !std.mem.eql(
                u8,
                bundled.repomd_sha256,
                repomd_identity.checksum_sha256,
            ) or
            !optionalEqual(bundled.revision, repomd_identity.revision) or
            !std.mem.eql(u8, bundled.snapshot_id, snapshot.metadata_sha256))
        {
            return error.RepositoryMismatch;
        }
    }
    if (available_count != manifest.repositories.len)
        return error.RepositoryMismatch;
}

fn verifyMetadata(
    allocator: Allocator,
    io: std.Io,
    directory: std.Io.Dir,
    bundle: *const transaction_bundle.Bundle,
    selection: *const bundle_selection.Selection,
) PreflightError!void {
    var bundled_metadata_count: usize = 0;
    for (bundle.model().files) |file| {
        if (std.mem.startsWith(
            u8,
            file.path,
            transaction_bundle.repositories_prefix,
        )) bundled_metadata_count += 1;
    }
    if (bundled_metadata_count !=
        selection.repositories.len + selection.metadata.len)
    {
        return error.MetadataMismatch;
    }
    for (selection.repositories) |repository| {
        const bytes = readBundleFile(
            allocator,
            io,
            directory,
            repository.repomd_path,
        ) catch return error.MetadataMismatch;
        defer allocator.free(bytes);
        try verifyFileEntry(bundle, repository.repomd_path, bytes);
        const actual = content_digest.sha256Hex(bytes);
        if (!std.ascii.eqlIgnoreCase(repository.repomd_sha256, &actual))
            return error.MetadataMismatch;
    }
    for (selection.metadata) |record| {
        const bytes = readBundleFile(
            allocator,
            io,
            directory,
            record.path,
        ) catch return error.MetadataMismatch;
        defer allocator.free(bytes);
        try verifyFileEntry(bundle, record.path, bytes);
        if (record.size) |size| {
            if (size != bytes.len) return error.MetadataMismatch;
        }
        if (!content_digest.matchesName(
            record.checksum.kind,
            record.checksum.value,
            bytes,
        )) return error.MetadataMismatch;
        if (record.open_checksum != null or record.open_size != null) {
            const maximum = if (record.open_size) |size|
                std.math.add(
                    usize,
                    std.math.cast(usize, size) orelse
                        return error.MetadataMismatch,
                    1,
                ) catch return error.MetadataMismatch
            else
                bundle_reader.max_file_bytes;
            const open_bytes =
                repomd.available_repository_loader.decompressMetadataForReplay(
                    allocator,
                    record.path,
                    bytes,
                    maximum,
                ) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return error.MetadataMismatch,
                };
            defer allocator.free(open_bytes);
            verified_fetch.verifyOpen(open_bytes, .{
                .checksum = record.checksum,
                .size = record.size,
                .open_checksum = record.open_checksum,
                .open_size = record.open_size,
            }) catch return error.MetadataMismatch;
        }
    }
}

fn verifyPinnedRpm(
    allocator: Allocator,
    bundle: *const transaction_bundle.Bundle,
    package: transaction_bundle.Package,
    handle: *rpm_gpgcheck.FileHandle,
    key_blobs: []const []const u8,
    used_keys: []bool,
    target_architecture: []const u8,
) PreflightError!void {
    const bytes = handle.file.bytes;
    try verifyFileEntry(bundle, package.path, bytes);
    if (package.size) |size| {
        if (size != bytes.len) return error.RpmMismatch;
    }
    if (!content_digest.matchesName(
        package.checksum.kind,
        package.checksum.value,
        bytes,
    )) return error.RpmMismatch;
    const digest_outcome = rpm_gpgcheck.verifyDigests(
        allocator,
        handle,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidRpmRange => return error.RpmMismatch,
    };
    if (digest_outcome != .ok)
        return error.RpmMismatch;
    if (!headerIdentityEqual(handle.file.main, package.identity))
        return error.RpmMismatch;
    if (!architectureAllows(target_architecture, package.identity.arch))
        return error.ArchitectureMismatch;

    const repository = findBundledRepository(
        bundle.model().repositories,
        package.repository_id,
    ) orelse return error.RepositoryMismatch;
    switch (package.signature.outcome) {
        .unsigned => {
            if (repository.gpg_check)
                return error.SignatureMismatch;
        },
        .verified => {
            if (!repository.gpg_check)
                return error.SignatureMismatch;
            var report = rpm_gpgcheck.verifySignatureReport(
                allocator,
                handle,
                key_blobs,
            ) catch return error.SignatureMismatch;
            defer report.deinit(allocator);
            if (!report.coverage.fully_verified or
                report.coverage.any_enabled_unsuppressed_failure)
            {
                return error.SignatureMismatch;
            }
            const signer = report.verifiedSigner() orelse
                return error.SignatureMismatch;
            if (signer.key_index >= bundle.model().keys.len)
                return error.SignatureMismatch;
            var fingerprint: [64]u8 = undefined;
            const hex = std.fmt.bufPrint(
                &fingerprint,
                "{x}",
                .{signer.fingerprint.slice()},
            ) catch return error.SignatureMismatch;
            const expected = package.signature.key_fingerprint orelse
                return error.SignatureMismatch;
            if (!std.mem.eql(u8, expected, hex) or
                !std.mem.eql(
                    u8,
                    bundle.model().keys[signer.key_index].fingerprint,
                    hex,
                ))
            {
                return error.SignatureMismatch;
            }
            used_keys[signer.key_index] = true;
        },
    }
}

fn headerIdentityEqual(
    header: rpm_header.Header,
    expected: PackageIdentity,
) bool {
    const name = header.getStringChecked(.name) catch return false;
    const version = header.getStringChecked(.version) catch return false;
    const release = header.getStringChecked(.release) catch return false;
    const arch = header.getStringChecked(.arch) catch return false;
    const epoch = header.getU32Checked(.epoch) catch return false;
    return name != null and version != null and release != null and arch != null and
        std.mem.eql(u8, expected.name, name.?) and
        effectiveEpoch(expected.epoch) == effectiveEpoch(epoch) and
        std.mem.eql(u8, expected.version, version.?) and
        std.mem.eql(u8, expected.release, release.?) and
        std.mem.eql(u8, expected.arch, arch.?);
}

fn architectureAllows(native: []const u8, candidate: []const u8) bool {
    if (repomd.solver_rules.isSource(candidate)) return false;
    return repomd.solver_rules.architectureRank(native, candidate) != null;
}

fn captureSnapshot(
    allocator: Allocator,
    config: *const txn_config.TxnConfig,
) PreflightError!Snapshot {
    var cookie_raw: ?[*:0]u8 = null;
    const iterator = TDNFTransactionPlanRpmdbSnapshotOpenConfig(
        config,
        &cookie_raw,
    ) orelse return error.TargetUnreadable;
    defer tdnf_rpmdb_iter_close(iterator);
    const cookie_pointer = cookie_raw orelse return error.TargetUnreadable;
    defer tdnf_rpmdb_string_free(cookie_pointer);

    var rows: std.ArrayList(InstalledPackage) = .empty;
    var inventory: std.ArrayList(InstalledPackage) = .empty;
    var package_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    package_hasher.update(rpmdb_package_set_domain);
    package_hasher.update("\x00");
    var record_count: u64 = 0;
    while (true) {
        var hnum: u32 = 0;
        var blob_pointer: ?[*]const u8 = null;
        var blob_length: usize = 0;
        const rc = tdnf_rpmdb_iter_next_header_blob_hnum(
            iterator,
            &hnum,
            &blob_pointer,
            &blob_length,
        );
        if (rc < 0) return error.TargetUnreadable;
        if (rc == 0) break;
        if (hnum == 0 or blob_pointer == null or blob_length == 0)
            return error.TargetUnreadable;
        const blob = blob_pointer.?[0..blob_length];
        var hnum_bytes: [4]u8 = undefined;
        writeBigEndian(&hnum_bytes, hnum);
        var length_bytes: [8]u8 = undefined;
        writeBigEndian(&length_bytes, blob_length);
        package_hasher.update(&hnum_bytes);
        package_hasher.update(&length_bytes);
        package_hasher.update(blob);
        record_count = std.math.add(u64, record_count, 1) catch
            return error.TargetUnreadable;

        const header = rpm_header.Header.parse(blob) catch
            return error.TargetUnreadable;
        const name = header.getStringChecked(.name) catch
            return error.TargetUnreadable;
        if (name == null) return error.TargetUnreadable;
        if (std.mem.eql(u8, name.?, "gpg-pubkey")) continue;
        const identity = try cloneHeaderIdentity(allocator, header);
        const row = InstalledPackage{ .hnum = hnum, .identity = identity };
        try rows.append(allocator, row);
        try inventory.append(allocator, row);
    }
    var count_bytes: [8]u8 = undefined;
    writeBigEndian(&count_bytes, record_count);
    package_hasher.update(&count_bytes);

    std.mem.sort(InstalledPackage, inventory.items, {}, installedPackageLessThan);
    var cookie_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(
        std.mem.span(cookie_pointer),
        &cookie_digest,
        .{},
    );
    var package_digest: [32]u8 = undefined;
    package_hasher.final(&package_digest);
    return .{
        .cookie_sha256 = std.fmt.bytesToHex(cookie_digest, .lower),
        .package_set_sha256 = std.fmt.bytesToHex(package_digest, .lower),
        .rows = try rows.toOwnedSlice(allocator),
        .inventory = try inventory.toOwnedSlice(allocator),
    };
}

fn cloneHeaderIdentity(
    allocator: Allocator,
    header: rpm_header.Header,
) PreflightError!PackageIdentity {
    const name = header.getStringChecked(.name) catch return error.TargetUnreadable;
    const version = header.getStringChecked(.version) catch return error.TargetUnreadable;
    const release = header.getStringChecked(.release) catch return error.TargetUnreadable;
    const arch = header.getStringChecked(.arch) catch return error.TargetUnreadable;
    return .{
        .arch = try allocator.dupe(u8, arch orelse return error.TargetUnreadable),
        .epoch = header.getU32Checked(.epoch) catch return error.TargetUnreadable,
        .name = try allocator.dupe(u8, name orelse return error.TargetUnreadable),
        .release = try allocator.dupe(u8, release orelse return error.TargetUnreadable),
        .version = try allocator.dupe(u8, version orelse return error.TargetUnreadable),
    };
}

fn verifyRpmdbIdentity(
    plan: *const transaction_plan.Data,
    snapshot: Snapshot,
) PreflightError!void {
    if (plan.environment.rpmdb.backend != .sqlite or
        !std.mem.eql(
            u8,
            plan.environment.rpmdb.cookie_sha256,
            &snapshot.cookie_sha256,
        ) or
        !std.mem.eql(
            u8,
            plan.environment.rpmdb.package_set_sha256,
            &snapshot.package_set_sha256,
        ))
    {
        return error.RpmdbMismatch;
    }
}

fn verifyInstalledRows(
    plan: *const transaction_plan.Data,
    rows: []const InstalledPackage,
) PreflightError!void {
    for (plan.packages) |package| {
        if (package.state != .installed) continue;
        const hnum = package.rpmdb_hnum orelse return error.PriorMismatch;
        const row = findRow(rows, hnum) orelse return error.PriorMismatch;
        if (!identityEqual(package.identity, row.identity))
            return error.PriorMismatch;
    }
}

const BuiltFixedOrder = struct {
    items: []const fixed.FixedOrderItem,
    order: []const u32,
    item_actions: []const usize,
};

fn buildFixedOrder(
    allocator: Allocator,
    plan: *const transaction_plan.Data,
    rows: []const InstalledPackage,
    verified: []const VerifiedRpm,
) PreflightError!BuiltFixedOrder {
    const steps = plan.execution_steps orelse return error.ActionShapeMismatch;
    const items = try allocator.alloc(fixed.FixedOrderItem, plan.actions.len);
    errdefer allocator.free(items);
    const order = try allocator.alloc(u32, plan.actions.len);
    errdefer allocator.free(order);
    const item_actions = try allocator.alloc(usize, plan.actions.len);
    errdefer allocator.free(item_actions);
    var initialized_items: usize = 0;
    errdefer {
        for (items[0..initialized_items]) |item| freeFixedItem(allocator, item);
    }
    for (plan.actions, items, item_actions, 0..) |
        action,
        *item,
        *action_index,
        index,
    | {
        const package = findPlanPackage(
            plan.packages,
            action.target_package_id,
        ) orelse
            return error.ActionShapeMismatch;
        action_index.* = index;
        item.* = switch (action.kind) {
            .erase => blk: {
                if (package.state != .installed)
                    return error.ActionShapeMismatch;
                const hnum = package.rpmdb_hnum orelse
                    return error.ActionShapeMismatch;
                const row = findRow(rows, hnum) orelse
                    return error.PriorMismatch;
                break :blk .{ .erase = fixedRow(row.*) };
            },
            .install => blk: {
                if (package.state != .available or
                    action.prior_package_ids.len != 0)
                {
                    return error.ActionShapeMismatch;
                }
                break :blk .{ .install = try fixedRpm(package.*, verified) };
            },
            .upgrade, .downgrade, .reinstall, .obsolete => blk: {
                if (package.state != .available or
                    action.prior_package_ids.len == 0)
                    return error.ActionShapeMismatch;
                const replacement = fixed.FixedOrderReplacement{
                    .package = try fixedRpm(package.*, verified),
                    .priors = try fixedPriors(
                        allocator,
                        plan.packages,
                        rows,
                        action.prior_package_ids,
                    ),
                };
                break :blk switch (action.kind) {
                    .upgrade => .{ .upgrade = replacement },
                    .downgrade => .{ .downgrade = replacement },
                    .reinstall => .{ .reinstall = replacement },
                    .obsolete => .{ .obsolete = replacement },
                    else => unreachable,
                };
            },
        };
        initialized_items = index + 1;
    }
    try collapseExecutionOrder(allocator, plan, steps, order);
    fixed.validateFixedOrder(.{
        .items = items,
        .order = order,
    }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.PriorMismatch => error.PriorMismatch,
        else => error.ActionShapeMismatch,
    };
    if (!(try projectedInventoryMatchesPlan(allocator, plan, rows)))
        return error.ActionShapeMismatch;
    return .{
        .items = items,
        .order = order,
        .item_actions = item_actions,
    };
}

fn collapseExecutionOrder(
    allocator: Allocator,
    plan: *const transaction_plan.Data,
    steps: []const transaction_plan.ExecutionStep,
    order: []u32,
) PreflightError!void {
    if (order.len != plan.actions.len) return error.ActionShapeMismatch;
    const seen = try allocator.alloc(bool, plan.actions.len);
    defer allocator.free(seen);
    @memset(seen, false);

    var output_index: usize = 0;
    var step_index: usize = 0;
    while (step_index < steps.len) {
        const step = steps[step_index];
        if (step.action_index >= plan.actions.len or
            seen[step.action_index])
        {
            return error.ActionShapeMismatch;
        }
        const action = plan.actions[step.action_index];
        if (!std.mem.eql(
            u8,
            step.package_id,
            action.target_package_id,
        ) or step.operation != targetExecutionOperation(action.kind)) {
            return error.ActionShapeMismatch;
        }
        seen[step.action_index] = true;
        order[output_index] = @intCast(step.action_index);
        output_index += 1;

        if (action.kind == .downgrade or action.kind == .obsolete) {
            step_index += 1;
            if (step_index >= steps.len) return error.ActionShapeMismatch;
            const companion = steps[step_index];
            if (companion.action_index != step.action_index or
                companion.operation != .erase or
                action.prior_package_ids.len == 0 or
                !std.mem.eql(
                    u8,
                    companion.package_id,
                    action.prior_package_ids[0],
                ))
            {
                return error.ActionShapeMismatch;
            }
        }
        step_index += 1;
    }
    if (output_index != order.len) return error.ActionShapeMismatch;
}

fn targetExecutionOperation(
    kind: transaction_plan.ActionKind,
) transaction_plan.ExecutionOperation {
    return switch (kind) {
        .erase => .erase,
        .reinstall => .reinstall,
        .upgrade => .upgrade,
        .downgrade, .install, .obsolete => .install,
    };
}

fn fixedRpm(
    package: transaction_plan.Package,
    verified: []const VerifiedRpm,
) PreflightError!fixed.FixedOrderLocalRpm {
    const rpm = findVerifiedRpm(verified, package.id) orelse
        return error.RpmMismatch;
    return .{
        .path = rpm.path,
        .identity = fixedIdentity(package.identity),
        .handle = rpm.handle,
    };
}

fn fixedPriors(
    allocator: Allocator,
    packages: []const transaction_plan.Package,
    rows: []const InstalledPackage,
    ids: []const []const u8,
) PreflightError![]const fixed.FixedOrderRpmDbRow {
    const output = try allocator.alloc(fixed.FixedOrderRpmDbRow, ids.len);
    errdefer allocator.free(output);
    for (ids, output) |id, *destination| {
        const package = findPlanPackage(packages, id) orelse
            return error.ActionShapeMismatch;
        if (package.state != .installed)
            return error.ActionShapeMismatch;
        const row = findRow(rows, package.rpmdb_hnum orelse
            return error.ActionShapeMismatch) orelse return error.PriorMismatch;
        destination.* = fixedRow(row.*);
    }
    return output;
}

fn freeFixedItem(
    allocator: Allocator,
    item: fixed.FixedOrderItem,
) void {
    switch (item) {
        .upgrade, .downgrade, .reinstall, .obsolete => |replacement| {
            allocator.free(replacement.priors);
        },
        .install, .erase => {},
    }
}

fn projectedInventoryMatchesPlan(
    allocator: Allocator,
    plan: *const transaction_plan.Data,
    rows: []const InstalledPackage,
) Allocator.Error!bool {
    const retained = try allocator.alloc(bool, rows.len);
    defer allocator.free(retained);
    @memset(retained, true);
    var projected = std.ArrayList(InstalledPackage).empty;
    defer projected.deinit(allocator);

    for (plan.actions) |action| {
        switch (action.kind) {
            .erase => {
                const package = findPlanPackage(
                    plan.packages,
                    action.target_package_id,
                ) orelse return false;
                const hnum = package.rpmdb_hnum orelse return false;
                const index = findRowIndex(rows, hnum) orelse return false;
                retained[index] = false;
            },
            .install => {},
            .upgrade, .downgrade, .reinstall, .obsolete => {
                for (action.prior_package_ids) |prior_id| {
                    const prior = findPlanPackage(
                        plan.packages,
                        prior_id,
                    ) orelse return false;
                    const hnum = prior.rpmdb_hnum orelse return false;
                    const index = findRowIndex(rows, hnum) orelse return false;
                    retained[index] = false;
                }
            },
        }
        if (action.kind != .erase) {
            const target = findPlanPackage(
                plan.packages,
                action.target_package_id,
            ) orelse return false;
            try projected.append(allocator, .{
                .hnum = 0,
                .identity = target.identity,
            });
        }
    }
    for (rows, retained) |row, keep| {
        if (keep) try projected.append(allocator, row);
    }
    std.mem.sort(
        InstalledPackage,
        projected.items,
        {},
        installedPackageLessThan,
    );
    return inventoryMatchesPlan(allocator, plan, projected.items);
}

fn fixedRow(row: InstalledPackage) fixed.FixedOrderRpmDbRow {
    return .{ .hnum = row.hnum, .identity = fixedIdentity(row.identity) };
}

fn fixedIdentity(identity: PackageIdentity) fixed.FixedOrderPackageIdentity {
    return .{
        .name = identity.name,
        .epoch = identity.epoch,
        .version = identity.version,
        .release = identity.release,
        .arch = identity.arch,
    };
}

const Progress = struct {
    outcomes: []ActionOutcome,
    item_actions: []const usize,
    completed: []usize,
    expected: []usize,
};

fn progressCompleted(context: ?*anyopaque, input_index: usize) void {
    const progress: *Progress = @ptrCast(@alignCast(context orelse return));
    if (input_index >= progress.item_actions.len) return;
    const action_index = progress.item_actions[input_index];
    progress.completed[action_index] += 1;
    if (progress.completed[action_index] == progress.expected[action_index])
        findActionOutcome(progress.outcomes, action_index).?.status = .applied;
}

fn markIndeterminate(outcomes: []ActionOutcome) void {
    for (outcomes) |*outcome| {
        if (outcome.status != .applied) outcome.status = .indeterminate;
    }
}

fn transactionFailure(
    err: fixed.FixedOrderExecutionError,
) TransactionFailure {
    return switch (err) {
        error.InvalidContext => .invalid_context,
        error.InvalidItem => .invalid_item,
        error.MalformedOrder => .malformed_order,
        error.PriorMismatch => .prior_mismatch,
        error.PackageOpenFailed => .package_open_failed,
        error.PackageIdentityMismatch => .package_identity_mismatch,
        error.RpmCheckFailed => .rpm_check_failed,
        error.TransactionFailed => .transaction_failed,
        error.ExecutionFailed, error.OutOfMemory => .execution_failed,
    };
}

fn inventoryMatchesPlan(
    allocator: Allocator,
    plan: *const transaction_plan.Data,
    actual: []const InstalledPackage,
) Allocator.Error!bool {
    if (plan.selected.len != actual.len) return false;
    var expected = std.ArrayList(PackageIdentity).empty;
    defer expected.deinit(allocator);
    for (plan.selected) |selection| {
        const package = findPlanPackage(
            plan.packages,
            selection.package_id,
        ) orelse return false;
        try expected.append(allocator, package.identity);
    }
    std.mem.sort(PackageIdentity, expected.items, {}, identityLessThan);
    for (expected.items, actual) |identity, installed| {
        if (!identityEqual(identity, installed.identity)) return false;
    }
    return true;
}

fn initActionOutcomes(
    allocator: Allocator,
    plan: *const transaction_plan.Data,
) Allocator.Error![]ActionOutcome {
    const steps = plan.execution_steps orelse &.{};
    const output = try allocator.alloc(ActionOutcome, plan.actions.len);
    var seen = try allocator.alloc(bool, plan.actions.len);
    defer allocator.free(seen);
    @memset(seen, false);
    var output_index: usize = 0;
    for (steps) |step| {
        if (seen[step.action_index]) continue;
        seen[step.action_index] = true;
        output[output_index] = .{
            .index = step.action_index,
            .kind = plan.actions[step.action_index].kind,
            .status = .not_attempted,
        };
        output_index += 1;
    }
    for (plan.actions, 0..) |action, action_index| {
        if (seen[action_index]) continue;
        output[output_index] = .{
            .index = action_index,
            .kind = action.kind,
            .status = .not_attempted,
        };
        output_index += 1;
    }
    if (output_index != output.len) unreachable;
    return output;
}

fn findActionOutcome(
    outcomes: []ActionOutcome,
    action_index: usize,
) ?*ActionOutcome {
    for (outcomes) |*outcome| {
        if (outcome.index == action_index) return outcome;
    }
    return null;
}

fn writeInstalledPackage(
    writer: *canonical_json.Writer,
    package: InstalledPackage,
) Allocator.Error!void {
    try writer.append("{\"hnum\":");
    try writer.writeUint(package.hnum);
    try writer.append(",\"identity\":{\"arch\":");
    try writer.writeString(package.identity.arch);
    try writer.append(",\"epoch\":");
    if (package.identity.epoch) |epoch|
        try writer.writeUint(epoch)
    else
        try writer.append("null");
    try writer.append(",\"name\":");
    try writer.writeString(package.identity.name);
    try writer.append(",\"release\":");
    try writer.writeString(package.identity.release);
    try writer.append(",\"version\":");
    try writer.writeString(package.identity.version);
    try writer.append("}}");
}

fn writeBigEndian(buffer: []u8, value: u64) void {
    var remaining = value;
    var index = buffer.len;
    while (index != 0) {
        index -= 1;
        buffer[index] = @intCast(remaining & 0xff);
        remaining >>= 8;
    }
}

fn findBundledRepository(
    repositories: []const transaction_bundle.Repository,
    id: []const u8,
) ?*const transaction_bundle.Repository {
    for (repositories) |*repository| {
        if (std.mem.eql(u8, repository.id, id)) return repository;
    }
    return null;
}

fn findPlanPackage(
    packages: []const transaction_plan.Package,
    id: []const u8,
) ?*const transaction_plan.Package {
    for (packages) |*package| {
        if (std.mem.eql(u8, package.id, id)) return package;
    }
    return null;
}

fn findVerifiedRpm(
    packages: []const VerifiedRpm,
    id: []const u8,
) ?*const VerifiedRpm {
    for (packages) |*package| {
        if (std.mem.eql(u8, package.plan_package_id, id)) return package;
    }
    return null;
}

fn findRow(
    rows: []const InstalledPackage,
    hnum: u32,
) ?*const InstalledPackage {
    for (rows) |*row| if (row.hnum == hnum) return row;
    return null;
}

fn findRowIndex(
    rows: []const InstalledPackage,
    hnum: u32,
) ?usize {
    for (rows, 0..) |row, index| if (row.hnum == hnum) return index;
    return null;
}

fn optionalEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn identityEqual(left: PackageIdentity, right: PackageIdentity) bool {
    return effectiveEpoch(left.epoch) == effectiveEpoch(right.epoch) and
        std.mem.eql(u8, left.arch, right.arch) and
        std.mem.eql(u8, left.name, right.name) and
        std.mem.eql(u8, left.release, right.release) and
        std.mem.eql(u8, left.version, right.version);
}

fn identityLessThan(_: void, left: PackageIdentity, right: PackageIdentity) bool {
    return compareIdentity(left, right) == .lt;
}

fn installedPackageLessThan(
    _: void,
    left: InstalledPackage,
    right: InstalledPackage,
) bool {
    const order = compareIdentity(left.identity, right.identity);
    if (order != .eq) return order == .lt;
    return left.hnum < right.hnum;
}

fn compareIdentity(left: PackageIdentity, right: PackageIdentity) std.math.Order {
    inline for (.{ "name", "epoch", "version", "release", "arch" }) |field| {
        if (comptime std.mem.eql(u8, field, "epoch")) {
            const left_epoch = left.epoch orelse 0;
            const right_epoch = right.epoch orelse 0;
            if (left_epoch < right_epoch) return .lt;
            if (left_epoch > right_epoch) return .gt;
        } else {
            const order = std.mem.order(
                u8,
                @field(left, field),
                @field(right, field),
            );
            if (order != .eq) return order;
        }
    }
    return .eq;
}

fn effectiveEpoch(epoch: ?u32) u32 {
    return epoch orelse 0;
}

test "result serialization never represents failure as success" {
    var actions = [_]ActionOutcome{.{
        .index = 0,
        .kind = .upgrade,
        .status = .not_attempted,
    }};
    var result = Result{
        .allocator = std.testing.allocator,
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .status = .validation_failed,
        .validation_failure = .rpmdb_mismatch,
        .transaction_failure = null,
        .plan_digest = "1" ** 64,
        .applied_plan_digest = null,
        .actions = &actions,
        .final_inventory = &.{},
    };
    defer result.arena.deinit();
    const json = try result.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "\"status\":\"validation_failed\"",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "\"applied_plan_digest\":null",
    ) != null);
}

test "architecture validation accepts noarch and rejects source packages" {
    try std.testing.expect(architectureAllows("x86_64", "x86_64"));
    try std.testing.expect(architectureAllows("x86_64", "noarch"));
    try std.testing.expect(!architectureAllows("x86_64", "aarch64"));
    try std.testing.expect(!architectureAllows("x86_64", "src"));
}

test "replay semantic identity treats omitted epoch as zero" {
    const rpmpkg = @import("rpm_package_test");
    const blob = try rpmpkg.makeMinimalHeaderForTest(
        std.testing.allocator,
        "epochless",
        "1",
        "1",
        "noarch",
    );
    defer std.testing.allocator.free(blob);
    const header = try rpm_header.Header.parse(blob);
    const explicit_zero = PackageIdentity{
        .name = "epochless",
        .epoch = 0,
        .version = "1",
        .release = "1",
        .arch = "noarch",
    };
    try std.testing.expect(headerIdentityEqual(header, explicit_zero));

    var omitted = explicit_zero;
    omitted.epoch = null;
    try std.testing.expect(identityEqual(explicit_zero, omitted));
    try std.testing.expectEqual(
        std.math.Order.eq,
        compareIdentity(explicit_zero, omitted),
    );
    try std.testing.expectEqual(
        @as(?u32, null),
        fixedIdentity(omitted).epoch,
    );
}

test "bundle closure failures remain distinct replay validation outcomes" {
    try std.testing.expectEqual(
        ValidationFailure.missing_bundle_file,
        validationFailure(mapBundleOpenError(error.MissingFile)),
    );
    try std.testing.expectEqual(
        ValidationFailure.additional_bundle_file,
        validationFailure(mapBundleOpenError(error.UnlistedFile)),
    );
    try std.testing.expectEqual(
        ValidationFailure.checksum_mismatch,
        validationFailure(mapBundleOpenError(error.ChecksumMismatch)),
    );
    try std.testing.expectEqual(
        ValidationFailure.size_mismatch,
        validationFailure(mapBundleOpenError(error.SizeMismatch)),
    );
}

test "inventory comparison is exact and independent of rpmdb hnum" {
    const packages = [_]transaction_plan.Package{.{
        .id = "package-0",
        .identity = .{
            .name = "app",
            .epoch = 0,
            .version = "1",
            .release = "1",
            .arch = "noarch",
        },
        .repository_id = "base",
        .rpmdb_hnum = null,
        .source = null,
        .state = .available,
    }};
    const plan = transaction_plan.Data{
        .actions = &.{},
        .environment = undefined,
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &packages,
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{.{ .package_id = "package-0" }},
        .skipped = &.{},
    };
    var installed_identity = packages[0].identity;
    installed_identity.epoch = null;
    try std.testing.expect(try inventoryMatchesPlan(
        std.testing.allocator,
        &plan,
        &.{.{
            .hnum = 42,
            .identity = installed_identity,
        }},
    ));
    try std.testing.expect(!(try inventoryMatchesPlan(
        std.testing.allocator,
        &plan,
        &.{},
    )));
}

test "rpmdb identity and prior validation reject every substitution" {
    const identity = PackageIdentity{
        .name = "installed",
        .epoch = null,
        .version = "1",
        .release = "1",
        .arch = "noarch",
    };
    const packages = [_]transaction_plan.Package{.{
        .id = "installed-0",
        .identity = identity,
        .repository_id = "@System",
        .rpmdb_hnum = 7,
        .source = null,
        .state = .installed,
    }};
    const plan = transaction_plan.Data{
        .actions = &.{},
        .environment = .{
            .architecture = "x86_64",
            .distro = "test",
            .policy = undefined,
            .releasever = "1",
            .resolution_status = .resolved,
            .rpmdb = .{
                .backend = .sqlite,
                .cookie_sha256 = "1" ** 64,
                .package_set_sha256 = "2" ** 64,
            },
        },
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &packages,
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{.{ .package_id = "installed-0" }},
        .skipped = &.{},
    };
    const snapshot = Snapshot{
        .cookie_sha256 = @splat('1'),
        .package_set_sha256 = @splat('2'),
        .rows = &.{.{ .hnum = 7, .identity = identity }},
        .inventory = &.{.{ .hnum = 7, .identity = identity }},
    };
    try verifyRpmdbIdentity(&plan, snapshot);
    try verifyInstalledRows(&plan, snapshot.rows);

    var changed_cookie = snapshot;
    changed_cookie.cookie_sha256 = @splat('3');
    try std.testing.expectError(
        error.RpmdbMismatch,
        verifyRpmdbIdentity(&plan, changed_cookie),
    );
    try std.testing.expectError(
        error.PriorMismatch,
        verifyInstalledRows(&plan, &.{.{ .hnum = 8, .identity = identity }}),
    );
    var newer = identity;
    newer.version = "2";
    try std.testing.expectError(
        error.PriorMismatch,
        verifyInstalledRows(&plan, &.{.{ .hnum = 7, .identity = newer }}),
    );
}

test "fixed replay items preserve all authoritative action representations" {
    const installed = [_]transaction_plan.Package{
        testPackage("erase-old", "erase", "1", .installed, 1),
        testPackage("upgrade-old", "upgrade", "1", .installed, 2),
        testPackage("down-old", "down", "2", .installed, 3),
        testPackage("reinstall-old", "reinstall", "1", .installed, 4),
        testPackage("obsolete-old", "obsolete-old", "1", .installed, 5),
        testPackage("down-retired", "down-retired", "1", .installed, 6),
        testPackage("obsolete-extra", "obsolete-extra", "1", .installed, 7),
    };
    const available = [_]transaction_plan.Package{
        testPackage("install-new", "install", "1", .available, null),
        testPackage("upgrade-new", "upgrade", "2", .available, null),
        testPackage("down-new", "down", "1", .available, null),
        testPackage("reinstall-new", "reinstall", "1", .available, null),
        testPackage("obsolete-new", "replacement", "1", .available, null),
    };
    const packages = installed ++ available;
    const actions = [_]transaction_plan.Action{
        .{ .kind = .install, .prior_package_ids = &.{}, .reason = .user, .requested_by_job_id = null, .target_package_id = "install-new" },
        .{ .kind = .erase, .prior_package_ids = &.{}, .reason = .user, .requested_by_job_id = null, .target_package_id = "erase-old" },
        .{ .kind = .upgrade, .prior_package_ids = &.{"upgrade-old"}, .reason = .user, .requested_by_job_id = null, .target_package_id = "upgrade-new" },
        .{ .kind = .downgrade, .prior_package_ids = &.{ "down-old", "down-retired" }, .reason = .user, .requested_by_job_id = null, .target_package_id = "down-new" },
        .{ .kind = .reinstall, .prior_package_ids = &.{"reinstall-old"}, .reason = .user, .requested_by_job_id = null, .target_package_id = "reinstall-new" },
        .{ .kind = .obsolete, .prior_package_ids = &.{ "obsolete-old", "obsolete-extra" }, .reason = .obsoletes, .requested_by_job_id = null, .target_package_id = "obsolete-new" },
    };
    const steps = [_]transaction_plan.ExecutionStep{
        .{ .action_index = 0, .operation = .install, .package_id = "install-new" },
        .{ .action_index = 1, .operation = .erase, .package_id = "erase-old" },
        .{ .action_index = 2, .operation = .upgrade, .package_id = "upgrade-new" },
        .{ .action_index = 3, .operation = .install, .package_id = "down-new" },
        .{ .action_index = 3, .operation = .erase, .package_id = "down-old" },
        .{ .action_index = 4, .operation = .reinstall, .package_id = "reinstall-new" },
        .{ .action_index = 5, .operation = .install, .package_id = "obsolete-new" },
        .{ .action_index = 5, .operation = .erase, .package_id = "obsolete-old" },
    };
    const rows = [_]InstalledPackage{
        .{ .hnum = 1, .identity = installed[0].identity },
        .{ .hnum = 2, .identity = installed[1].identity },
        .{ .hnum = 3, .identity = installed[2].identity },
        .{ .hnum = 4, .identity = installed[3].identity },
        .{ .hnum = 5, .identity = installed[4].identity },
        .{ .hnum = 6, .identity = installed[5].identity },
        .{ .hnum = 7, .identity = installed[6].identity },
    };
    const fake: *rpm_gpgcheck.FileHandle = @ptrFromInt(
        @alignOf(rpm_gpgcheck.FileHandle),
    );
    const verified = [_]VerifiedRpm{
        .{ .plan_package_id = "install-new", .path = "/bundle/install.rpm", .handle = fake },
        .{ .plan_package_id = "upgrade-new", .path = "/bundle/upgrade.rpm", .handle = fake },
        .{ .plan_package_id = "down-new", .path = "/bundle/down.rpm", .handle = fake },
        .{ .plan_package_id = "reinstall-new", .path = "/bundle/reinstall.rpm", .handle = fake },
        .{ .plan_package_id = "obsolete-new", .path = "/bundle/obsolete.rpm", .handle = fake },
    };
    const data = transaction_plan.Data{
        .actions = &actions,
        .environment = undefined,
        .execution_steps = &steps,
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &packages,
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{
            .{ .package_id = "install-new" },
            .{ .package_id = "upgrade-new" },
            .{ .package_id = "down-new" },
            .{ .package_id = "reinstall-new" },
            .{ .package_id = "obsolete-new" },
        },
        .skipped = &.{},
    };
    const built = try buildFixedOrder(
        std.testing.allocator,
        &data,
        &rows,
        &verified,
    );
    defer {
        for (built.items) |item| freeFixedItem(std.testing.allocator, item);
        std.testing.allocator.free(built.items);
        std.testing.allocator.free(built.order);
        std.testing.allocator.free(built.item_actions);
    }
    try std.testing.expect(built.items[0] == .install);
    try std.testing.expect(built.items[1] == .erase);
    try std.testing.expect(built.items[2] == .upgrade);
    try std.testing.expect(built.items[3] == .downgrade);
    try std.testing.expect(built.items[4] == .reinstall);
    try std.testing.expect(built.items[5] == .obsolete);
    try std.testing.expectEqual(
        @as(usize, 2),
        built.items[3].downgrade.priors.len,
    );
    try std.testing.expectEqual(
        @as(u32, 6),
        built.items[3].downgrade.priors[1].hnum,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        built.items[5].obsolete.priors.len,
    );
    try std.testing.expectEqual(
        @as(u32, 7),
        built.items[5].obsolete.priors[1].hnum,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0, 1, 2, 3, 4, 5 },
        built.order,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 1, 2, 3, 4, 5 },
        built.item_actions,
    );
}

test "shared obsolete priors collapse to complete semantic items" {
    const packages = [_]transaction_plan.Package{
        testPackage("shared-old", "shared-old", "1", .installed, 11),
        testPackage("unique-old", "unique-old", "1", .installed, 12),
        testPackage("replacement-a", "replacement-a", "1", .available, null),
        testPackage("replacement-b", "replacement-b", "1", .available, null),
    };
    const actions = [_]transaction_plan.Action{
        .{
            .kind = .obsolete,
            .prior_package_ids = &.{ "shared-old", "unique-old" },
            .reason = .obsoletes,
            .requested_by_job_id = null,
            .target_package_id = "replacement-a",
        },
        .{
            .kind = .obsolete,
            .prior_package_ids = &.{"shared-old"},
            .reason = .obsoletes,
            .requested_by_job_id = null,
            .target_package_id = "replacement-b",
        },
    };
    const steps = [_]transaction_plan.ExecutionStep{
        .{ .action_index = 0, .operation = .install, .package_id = "replacement-a" },
        .{ .action_index = 0, .operation = .erase, .package_id = "shared-old" },
        .{ .action_index = 1, .operation = .install, .package_id = "replacement-b" },
        .{ .action_index = 1, .operation = .erase, .package_id = "shared-old" },
    };
    const rows = [_]InstalledPackage{
        .{ .hnum = 11, .identity = packages[0].identity },
        .{ .hnum = 12, .identity = packages[1].identity },
    };
    const fake: *rpm_gpgcheck.FileHandle = @ptrFromInt(
        @alignOf(rpm_gpgcheck.FileHandle),
    );
    const verified = [_]VerifiedRpm{
        .{ .plan_package_id = "replacement-a", .path = "/bundle/a.rpm", .handle = fake },
        .{ .plan_package_id = "replacement-b", .path = "/bundle/b.rpm", .handle = fake },
    };
    const plan = transaction_plan.Data{
        .actions = &actions,
        .environment = undefined,
        .execution_steps = &steps,
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &packages,
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{
            .{ .package_id = "replacement-a" },
            .{ .package_id = "replacement-b" },
        },
        .skipped = &.{},
    };
    const built = try buildFixedOrder(
        std.testing.allocator,
        &plan,
        &rows,
        &verified,
    );
    defer {
        for (built.items) |item| freeFixedItem(std.testing.allocator, item);
        std.testing.allocator.free(built.items);
        std.testing.allocator.free(built.order);
        std.testing.allocator.free(built.item_actions);
    }
    try std.testing.expectEqual(@as(usize, 2), built.items.len);
    try std.testing.expect(built.items[0] == .obsolete);
    try std.testing.expect(built.items[1] == .obsolete);
    try std.testing.expectEqual(
        @as(u32, 11),
        built.items[0].obsolete.priors[0].hnum,
    );
    try std.testing.expectEqual(
        @as(u32, 11),
        built.items[1].obsolete.priors[0].hnum,
    );
}

test "unmergeable action order and inventory mismatch fail preflight" {
    const packages = [_]transaction_plan.Package{
        testPackage("old", "pkg", "2", .installed, 21),
        testPackage("new", "pkg", "1", .available, null),
        testPackage("extra", "extra", "1", .available, null),
    };
    const actions = [_]transaction_plan.Action{
        .{ .kind = .downgrade, .prior_package_ids = &.{"old"}, .reason = .policy, .requested_by_job_id = null, .target_package_id = "new" },
        .{ .kind = .install, .prior_package_ids = &.{}, .reason = .policy, .requested_by_job_id = null, .target_package_id = "extra" },
    };
    const interleaved = [_]transaction_plan.ExecutionStep{
        .{ .action_index = 0, .operation = .install, .package_id = "new" },
        .{ .action_index = 1, .operation = .install, .package_id = "extra" },
        .{ .action_index = 0, .operation = .erase, .package_id = "old" },
    };
    const rows = [_]InstalledPackage{.{
        .hnum = 21,
        .identity = packages[0].identity,
    }};
    const fake: *rpm_gpgcheck.FileHandle = @ptrFromInt(
        @alignOf(rpm_gpgcheck.FileHandle),
    );
    const verified = [_]VerifiedRpm{
        .{ .plan_package_id = "new", .path = "/bundle/new.rpm", .handle = fake },
        .{ .plan_package_id = "extra", .path = "/bundle/extra.rpm", .handle = fake },
    };
    var plan = transaction_plan.Data{
        .actions = &actions,
        .environment = undefined,
        .execution_steps = &interleaved,
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &packages,
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{
            .{ .package_id = "new" },
            .{ .package_id = "extra" },
        },
        .skipped = &.{},
    };
    try std.testing.expectError(
        error.ActionShapeMismatch,
        buildFixedOrder(
            std.testing.allocator,
            &plan,
            &rows,
            &verified,
        ),
    );

    const contiguous = [_]transaction_plan.ExecutionStep{
        .{ .action_index = 0, .operation = .install, .package_id = "new" },
        .{ .action_index = 0, .operation = .erase, .package_id = "old" },
        .{ .action_index = 1, .operation = .install, .package_id = "extra" },
    };
    plan.execution_steps = &contiguous;
    plan.selected = &.{.{ .package_id = "new" }};
    try std.testing.expectError(
        error.ActionShapeMismatch,
        buildFixedOrder(
            std.testing.allocator,
            &plan,
            &rows,
            &verified,
        ),
    );
}

fn testPackage(
    id: []const u8,
    name: []const u8,
    version: []const u8,
    state: transaction_plan.PackageState,
    hnum: ?u32,
) transaction_plan.Package {
    return .{
        .id = id,
        .identity = .{
            .name = name,
            .epoch = null,
            .version = version,
            .release = "1",
            .arch = "noarch",
        },
        .repository_id = if (state == .installed) "@System" else "base",
        .rpmdb_hnum = hnum,
        .source = null,
        .state = state,
    };
}
