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
    return plan.withExecutionSteps(allocator, ordered) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidInput,
    };
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
