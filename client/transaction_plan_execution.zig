//! Materializes a replay-capable plan from verified bundle RPMs.
//!
//! The resolve capture retains the exact transaction-item sequence handed to
//! the native executor before v1's semantic action sort. Once bundle export
//! has fetched and verified the RPMs, this module asks that same native
//! transaction planner for its authoritative dependency order and records the
//! resulting permutation in plan v2.

const std = @import("std");
const abi = @import("tdnf_internal_abi");
const bundle_selection = @import("bundle_selection");
const transaction_plan = @import("transaction_plan");

pub const MaterializeError = error{
    InvalidInput,
    NativeRejected,
    OutOfMemory,
};

pub fn materialize(
    allocator: std.mem.Allocator,
    plan: *const transaction_plan.Plan,
    selection: *const bundle_selection.Selection,
    staging_root: []const u8,
    install_root: []const u8,
) MaterializeError!*transaction_plan.Plan {
    const inputs = plan.model().native_execution_inputs;
    if (inputs.len == 0 and plan.model().actions.len != 0) {
        return error.InvalidInput;
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const native_items = try arena.alloc(
        abi.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2,
        inputs.len,
    );
    for (inputs, native_items) |step, *item| {
        const package = findPackage(
            plan.model().packages,
            step.package_id,
        ) orelse return error.InvalidInput;
        const evr_text = if (package.identity.epoch) |epoch|
            try std.fmt.allocPrint(
                arena,
                "{d}:{s}-{s}",
                .{
                    epoch,
                    package.identity.version,
                    package.identity.release,
                },
            )
        else
            try std.fmt.allocPrint(
                arena,
                "{s}-{s}",
                .{ package.identity.version, package.identity.release },
            );
        const evr = try arena.dupeZ(u8, evr_text);
        item.* = .{
            .dwOperation = operationValue(step.operation),
            .pszName = (try arena.dupeZ(u8, package.identity.name)).ptr,
            .pszEVR = evr.ptr,
            .pszArch = (try arena.dupeZ(u8, package.identity.arch)).ptr,
            .dwRpmDbHnum = package.rpmdb_hnum orelse 0,
        };
        if (step.operation != .erase) {
            const relative = findPackagePath(
                selection.packages,
                step.package_id,
            ) orelse return error.InvalidInput;
            item.pszPath = (try std.fs.path.joinZ(
                arena,
                &.{ staging_root, relative },
            )).ptr;
        }
    }

    const root_z = try arena.dupeZ(u8, install_root);
    var native_plan: [*c]abi.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = null;
    const rc = abi.TDNFRepoMdNativeTransactionPlanSolveV2(
        native_items.ptr,
        @intCast(native_items.len),
        root_z.ptr,
        &native_plan,
    );
    if (rc != 0 or native_plan == null) return error.NativeRejected;
    defer abi.TDNFRepoMdNativeTransactionPlanFree(native_plan);
    if (native_plan[0].dwProblemCount != 0 or
        native_plan[0].dwItemCount != inputs.len or
        (inputs.len != 0 and native_plan[0].pdwOrderIndices == null))
    {
        return error.NativeRejected;
    }

    const ordered = try arena.alloc(transaction_plan.ExecutionStep, inputs.len);
    const seen = try arena.alloc(bool, inputs.len);
    @memset(seen, false);
    for (native_plan[0].pdwOrderIndices[0..inputs.len], ordered) |
        raw_index,
        *destination,
    | {
        if (raw_index >= inputs.len or seen[raw_index]) {
            return error.NativeRejected;
        }
        seen[raw_index] = true;
        destination.* = inputs[raw_index];
    }
    const semantic = try semanticExecutionSteps(
        arena,
        plan.model(),
        ordered,
    );
    return plan.withExecutionSteps(allocator, semantic) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidInput,
    };
}

fn semanticExecutionSteps(
    allocator: std.mem.Allocator,
    data: *const transaction_plan.Data,
    ordered_native: []const transaction_plan.ExecutionStep,
) MaterializeError![]const transaction_plan.ExecutionStep {
    var expected_count = data.actions.len;
    for (data.actions) |action| {
        if (action.kind == .obsolete or action.kind == .downgrade) {
            if (action.prior_package_ids.len == 0) return error.InvalidInput;
            expected_count += 1;
        }
    }
    var output = try std.ArrayList(transaction_plan.ExecutionStep).initCapacity(
        allocator,
        expected_count,
    );
    errdefer output.deinit(allocator);
    const primary_seen = try allocator.alloc(bool, data.actions.len);
    defer allocator.free(primary_seen);
    @memset(primary_seen, false);
    var erased_priors: std.StringHashMapUnmanaged(void) = .empty;
    defer erased_priors.deinit(allocator);

    for (ordered_native) |step| {
        if (step.action_index >= data.actions.len) return error.InvalidInput;
        const action = data.actions[step.action_index];
        if (isPrimaryStep(action, step)) {
            if (primary_seen[step.action_index]) return error.InvalidInput;
            primary_seen[step.action_index] = true;
            output.appendAssumeCapacity(step);
            if (action.kind == .obsolete or action.kind == .downgrade) {
                output.appendAssumeCapacity(.{
                    .action_index = step.action_index,
                    .operation = .erase,
                    .package_id = action.prior_package_ids[0],
                });
            }
            continue;
        }
        if (step.operation != .erase or
            (action.kind != .obsolete and action.kind != .downgrade) or
            !containsString(action.prior_package_ids, step.package_id))
        {
            return error.InvalidInput;
        }
        const entry = try erased_priors.getOrPut(allocator, step.package_id);
        if (entry.found_existing) return error.InvalidInput;
    }
    if (output.items.len != expected_count) return error.InvalidInput;
    for (primary_seen) |was_seen| {
        if (!was_seen) return error.InvalidInput;
    }
    for (data.actions) |action| {
        if (action.kind == .obsolete or action.kind == .downgrade) {
            if (!erased_priors.contains(action.prior_package_ids[0]))
                return error.InvalidInput;
        }
    }
    return output.toOwnedSlice(allocator);
}

fn isPrimaryStep(
    action: transaction_plan.Action,
    step: transaction_plan.ExecutionStep,
) bool {
    if (!std.mem.eql(u8, action.target_package_id, step.package_id))
        return false;
    const expected: transaction_plan.ExecutionOperation = switch (action.kind) {
        .erase => .erase,
        .reinstall => .reinstall,
        .upgrade => .upgrade,
        .downgrade, .install, .obsolete => .install,
    };
    return step.operation == expected;
}

fn containsString(values: []const []const u8, wanted: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, wanted)) return true;
    }
    return false;
}

fn operationValue(operation: transaction_plan.ExecutionOperation) u32 {
    return @intCast(switch (operation) {
        .install => abi.TDNF_REPOMD_NATIVE_TRANSACTION_OP_INSTALL,
        .reinstall => abi.TDNF_REPOMD_NATIVE_TRANSACTION_OP_REINSTALL,
        .erase => abi.TDNF_REPOMD_NATIVE_TRANSACTION_OP_ERASE,
        .upgrade => abi.TDNF_REPOMD_NATIVE_TRANSACTION_OP_UPGRADE,
    });
}

fn findPackage(
    packages: []const transaction_plan.Package,
    id: []const u8,
) ?*const transaction_plan.Package {
    for (packages) |*package| {
        if (std.mem.eql(u8, package.id, id)) return package;
    }
    return null;
}

fn findPackagePath(
    packages: []const bundle_selection.PackageItem,
    id: []const u8,
) ?[]const u8 {
    for (packages) |package| {
        if (std.mem.eql(u8, package.capture_package_id, id)) {
            return package.path;
        }
    }
    return null;
}

test "deduplicated native erase expands to shared obsolete companions" {
    const packages = [_]transaction_plan.Package{
        .{
            .id = "old",
            .identity = .{
                .arch = "x86_64",
                .epoch = null,
                .name = "old",
                .release = "1",
                .version = "1",
            },
            .location = null,
            .reason = null,
            .repository_id = "@System",
            .rpmdb_hnum = 11,
            .sha256 = null,
            .size = null,
            .state = .installed,
        },
        .{
            .id = "first",
            .identity = .{
                .arch = "x86_64",
                .epoch = null,
                .name = "first",
                .release = "1",
                .version = "1",
            },
            .location = .{ .href = "first.rpm" },
            .reason = null,
            .repository_id = "base",
            .rpmdb_hnum = null,
            .sha256 = "0" ** 64,
            .size = 1,
            .state = .available,
        },
        .{
            .id = "second",
            .identity = .{
                .arch = "x86_64",
                .epoch = null,
                .name = "second",
                .release = "1",
                .version = "1",
            },
            .location = .{ .href = "second.rpm" },
            .reason = null,
            .repository_id = "base",
            .rpmdb_hnum = null,
            .sha256 = "1" ** 64,
            .size = 1,
            .state = .available,
        },
    };
    const actions = [_]transaction_plan.Action{
        .{
            .kind = .obsolete,
            .prior_package_ids = &.{"old"},
            .reason = .obsoletes,
            .requested_by_job_id = null,
            .target_package_id = "first",
        },
        .{
            .kind = .obsolete,
            .prior_package_ids = &.{"old"},
            .reason = .obsoletes,
            .requested_by_job_id = null,
            .target_package_id = "second",
        },
    };
    const data = transaction_plan.Data{
        .actions = &actions,
        .environment = undefined,
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &packages,
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{
            .{ .package_id = "first" },
            .{ .package_id = "second" },
        },
        .skipped = &.{},
    };
    const native = [_]transaction_plan.ExecutionStep{
        .{ .action_index = 0, .operation = .install, .package_id = "first" },
        .{ .action_index = 1, .operation = .install, .package_id = "second" },
        .{ .action_index = 1, .operation = .erase, .package_id = "old" },
    };
    const semantic = try semanticExecutionSteps(
        std.testing.allocator,
        &data,
        &native,
    );
    defer std.testing.allocator.free(semantic);
    try std.testing.expectEqual(@as(usize, 4), semantic.len);
    try std.testing.expectEqual(@as(usize, 0), semantic[1].action_index);
    try std.testing.expectEqual(
        transaction_plan.ExecutionOperation.erase,
        semantic[1].operation,
    );
    try std.testing.expectEqual(@as(usize, 1), semantic[3].action_index);
    try std.testing.expectEqualStrings("old", semantic[3].package_id);
}
