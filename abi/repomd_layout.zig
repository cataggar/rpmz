const std = @import("std");
const solver_result_abi = @import("solver_result_abi");
const solver_shadow_abi = @import("solver_shadow_abi");
const solver_live_abi = @import("solver_live_abi");
const capture_abi = @import("transaction_plan_capture_abi");
const c = @cImport({
    @cInclude("tdnf.h");
    @cInclude("tdnfrepomd.h");
    @cInclude("transaction_plan_capture_abi.inc");
});

fn expectSameLayout(
    comptime zig_type: type,
    comptime c_type: type,
    comptime fields: anytype,
) !void {
    try std.testing.expectEqual(@sizeOf(c_type), @sizeOf(zig_type));
    try std.testing.expectEqual(@alignOf(c_type), @alignOf(zig_type));
    inline for (fields) |field| {
        try std.testing.expectEqual(
            @offsetOf(c_type, field),
            @offsetOf(zig_type, field),
        );
    }
}

fn assertSameCaptureLayout(comptime zig_type: type, comptime c_type: type) void {
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
    assertSameCaptureLayout(capture_abi.Bytes, c.TDNF_TRANSACTION_PLAN_CAPTURE_BYTES);
    assertSameCaptureLayout(capture_abi.Checksum, c.TDNF_TRANSACTION_PLAN_CAPTURE_CHECKSUM);
    assertSameCaptureLayout(capture_abi.Location, c.TDNF_TRANSACTION_PLAN_CAPTURE_LOCATION);
    assertSameCaptureLayout(capture_abi.Capability, c.TDNF_TRANSACTION_PLAN_CAPTURE_CAPABILITY);
    assertSameCaptureLayout(capture_abi.MinVersion, c.TDNF_TRANSACTION_PLAN_CAPTURE_MIN_VERSION);
    assertSameCaptureLayout(capture_abi.Policy, c.TDNF_TRANSACTION_PLAN_CAPTURE_POLICY);
    assertSameCaptureLayout(capture_abi.Rpmdb, c.TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB);
    assertSameCaptureLayout(capture_abi.Environment, c.TDNF_TRANSACTION_PLAN_CAPTURE_ENVIRONMENT);
    assertSameCaptureLayout(capture_abi.MetadataRecord, c.TDNF_TRANSACTION_PLAN_CAPTURE_METADATA_RECORD);
    assertSameCaptureLayout(capture_abi.Repomd, c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOMD);
    assertSameCaptureLayout(capture_abi.Snapshot, c.TDNF_TRANSACTION_PLAN_CAPTURE_SNAPSHOT);
    assertSameCaptureLayout(capture_abi.Repository, c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY);
    assertSameCaptureLayout(capture_abi.Request, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST);
    assertSameCaptureLayout(capture_abi.Job, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB);
    assertSameCaptureLayout(capture_abi.PackageIdentity, c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_IDENTITY);
    assertSameCaptureLayout(capture_abi.PackageSource, c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_SOURCE);
    assertSameCaptureLayout(capture_abi.Package, c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE);
    assertSameCaptureLayout(capture_abi.Action, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION);
    assertSameCaptureLayout(capture_abi.Problem, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM);
    assertSameCaptureLayout(capture_abi.Capture, c.TDNF_TRANSACTION_PLAN_CAPTURE);
    assertSameCaptureLayout(capture_abi.RequestTraceJob, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_JOB);
    assertSameCaptureLayout(capture_abi.RequestTraceQueueOrigin, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_QUEUE_ORIGIN);
    assertSameCaptureLayout(capture_abi.RequestTracePolicyFact, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_FACT);
    assertSameCaptureLayout(capture_abi.RequestTraceView, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_VIEW);
    assertSameCaptureLayout(capture_abi.RequestTracePackageRef, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_PACKAGE_REF);
    assertSameCaptureLayout(capture_abi.RequestTraceCaptureFacts, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_FACTS);
}

test "private transaction capture constants match C declarations" {
    inline for (.{
        .{ capture_abi.abi_version, c.TDNF_TRANSACTION_PLAN_CAPTURE_ABI_VERSION },
        .{ capture_abi.request_kind.distro_sync, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_DISTRO_SYNC },
        .{ capture_abi.request_kind.downgrade, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_DOWNGRADE },
        .{ capture_abi.request_kind.erase, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_ERASE },
        .{ capture_abi.request_kind.install, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_INSTALL },
        .{ capture_abi.request_kind.lock, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_LOCK },
        .{ capture_abi.request_kind.reinstall, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_REINSTALL },
        .{ capture_abi.request_kind.update, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_UPDATE },
        .{ capture_abi.request_kind.update_all, c.TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_UPDATE_ALL },
        .{ capture_abi.job_action.install, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_INSTALL },
        .{ capture_abi.job_action.erase, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ERASE },
        .{ capture_abi.job_action.update, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_UPDATE },
        .{ capture_abi.job_action.downgrade, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_DOWNGRADE },
        .{ capture_abi.job_action.dist_sync, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_DIST_SYNC },
        .{ capture_abi.job_action.reinstall, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_REINSTALL },
        .{ capture_abi.job_action.lock, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_LOCK },
        .{ capture_abi.job_action.multiversion, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_MULTIVERSION },
        .{ capture_abi.job_action.user_installed, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_USER_INSTALLED },
        .{ capture_abi.job_action.allow_uninstall, c.TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ALLOW_UNINSTALL },
        .{ capture_abi.request_reason.user, c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_USER },
        .{ capture_abi.request_reason.dependency, c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_DEPENDENCY },
        .{ capture_abi.request_reason.weak_dependency, c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_WEAK_DEPENDENCY },
        .{ capture_abi.request_reason.cleanup, c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_CLEANUP },
        .{ capture_abi.request_reason.installonly_limit, c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_INSTALLONLY_LIMIT },
        .{ capture_abi.request_reason.policy, c.TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY },
        .{ capture_abi.package_state.available, c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_AVAILABLE },
        .{ capture_abi.package_state.installed, c.TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_INSTALLED },
        .{ capture_abi.action_kind.downgrade, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_DOWNGRADE },
        .{ capture_abi.action_kind.erase, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_ERASE },
        .{ capture_abi.action_kind.install, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_INSTALL },
        .{ capture_abi.action_kind.obsolete, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_OBSOLETE },
        .{ capture_abi.action_kind.reinstall, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REINSTALL },
        .{ capture_abi.action_kind.upgrade, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_UPGRADE },
        .{ capture_abi.action_reason.cleanup, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_CLEANUP },
        .{ capture_abi.action_reason.dependency, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_DEPENDENCY },
        .{ capture_abi.action_reason.installonly_limit, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_INSTALLONLY_LIMIT },
        .{ capture_abi.action_reason.obsoletes, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_OBSOLETES },
        .{ capture_abi.action_reason.policy, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_POLICY },
        .{ capture_abi.action_reason.user, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_USER },
        .{ capture_abi.action_reason.weak_dependency, c.TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_WEAK_DEPENDENCY },
        .{ capture_abi.problem_kind.conflict, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_CONFLICT },
        .{ capture_abi.problem_kind.installonly_limit, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_INSTALLONLY_LIMIT },
        .{ capture_abi.problem_kind.no_candidate, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_NO_CANDIDATE },
        .{ capture_abi.problem_kind.not_installable, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_NOT_INSTALLABLE },
        .{ capture_abi.problem_kind.obsoletes, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_OBSOLETES },
        .{ capture_abi.problem_kind.protected_package, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_PROTECTED_PACKAGE },
        .{ capture_abi.problem_kind.unsatisfied_requirement, c.TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_UNSATISFIED_REQUIREMENT },
        .{ capture_abi.compare_op.eq, c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_EQ },
        .{ capture_abi.compare_op.ge, c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_GE },
        .{ capture_abi.compare_op.gt, c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_GT },
        .{ capture_abi.compare_op.le, c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_LE },
        .{ capture_abi.compare_op.lt, c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_LT },
        .{ capture_abi.compare_op.none, c.TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_NONE },
        .{ capture_abi.resolution_status.problems, c.TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_PROBLEMS },
        .{ capture_abi.resolution_status.resolved, c.TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_RESOLVED },
        .{ capture_abi.resolution_status.resolved_with_skips, c.TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_RESOLVED_WITH_SKIPS },
        .{ capture_abi.rpmdb_backend.bdb, c.TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_BDB },
        .{ capture_abi.rpmdb_backend.ndb, c.TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_NDB },
        .{ capture_abi.rpmdb_backend.sqlite, c.TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_SQLITE },
        .{ capture_abi.repository_kind.available, c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_AVAILABLE },
        .{ capture_abi.repository_kind.installed, c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_INSTALLED },
        .{ capture_abi.repository_kind.command_line, c.TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_COMMAND_LINE },
        .{ capture_abi.selection_kind.all, c.TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_ALL },
        .{ capture_abi.selection_kind.package, c.TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_PACKAGE },
        .{ capture_abi.selection_kind.name, c.TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_NAME },
        .{ capture_abi.selection_kind.capability, c.TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_CAPABILITY },
        .{ capture_abi.request_trace_no_request, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST },
        .{ capture_abi.request_trace_flag.clean_deps, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_CLEAN_DEPS },
        .{ capture_abi.request_trace_flag.force_best, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_FORCE_BEST },
        .{ capture_abi.request_trace_flag.targeted, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_TARGETED },
        .{ capture_abi.request_trace_flag.not_by_user, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_NOT_BY_USER },
        .{ capture_abi.request_trace_flag.weak, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_WEAK },
        .{ capture_abi.request_trace_policy.exclude, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_EXCLUDE },
        .{ capture_abi.request_trace_policy.installonly, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_INSTALLONLY },
        .{ capture_abi.request_trace_policy.lock, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_LOCK },
        .{ capture_abi.request_trace_policy.min_version, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_MIN_VERSION },
        .{ capture_abi.request_trace_policy.protected, c.TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_PROTECTED },
    }) |values| {
        try std.testing.expectEqual(values[1], values[0]);
    }
}

test "public configuration layout remains stable" {
    const pointer_size = @sizeOf(*anyopaque);
    const expected_size: usize = if (pointer_size == 8) 216 else 136;
    const expected_alignment: usize = if (pointer_size == 8) 8 else 4;

    try std.testing.expect(pointer_size == 4 or pointer_size == 8);
    try std.testing.expectEqual(expected_size, @sizeOf(c.TDNF_CONF));
    try std.testing.expectEqual(expected_alignment, @alignOf(c.TDNF_CONF));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(
        c.TDNF_CONF,
        "rpmTransFlags",
    ));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(
        @TypeOf(@as(c.TDNF_CONF, undefined).rpmTransFlags),
    ));
}

test "legacy native transaction item layout remains stable" {
    const pointer_size = @sizeOf(*anyopaque);
    const first_pointer_offset: usize = if (pointer_size == 8) 8 else 4;
    const legacy_size: usize = if (pointer_size == 8) 40 else 20;
    const v2_size: usize = if (pointer_size == 8) 48 else 24;

    try std.testing.expect(pointer_size == 4 or pointer_size == 8);
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM,
        "dwOperation",
    ));
    try std.testing.expectEqual(first_pointer_offset, @offsetOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM,
        "pszPath",
    ));
    try std.testing.expectEqual(first_pointer_offset + pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM,
        "pszName",
    ));
    try std.testing.expectEqual(first_pointer_offset + 2 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM,
        "pszEVR",
    ));
    try std.testing.expectEqual(first_pointer_offset + 3 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM,
        "pszArch",
    ));
    try std.testing.expectEqual(legacy_size, @sizeOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM,
    ));

    try std.testing.expectEqual(first_pointer_offset + 3 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2,
        "pszArch",
    ));
    try std.testing.expectEqual(legacy_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2,
        "dwRpmDbHnum",
    ));
    try std.testing.expectEqual(v2_size, @sizeOf(
        c.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2,
    ));
}

test "native solver package layout remains stable" {
    const pointer_size = @sizeOf(*anyopaque);
    const scalar_offset = 10 * pointer_size;
    const expected_size: usize = if (pointer_size == 8) 136 else 96;

    try std.testing.expect(pointer_size == 4 or pointer_size == 8);
    try std.testing.expectEqual(pointer_size, @alignOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
    ));
    try std.testing.expectEqual(expected_size, @sizeOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
    ));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszRepository",
    ));
    try std.testing.expectEqual(pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszName",
    ));
    try std.testing.expectEqual(2 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszVersion",
    ));
    try std.testing.expectEqual(3 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszRelease",
    ));
    try std.testing.expectEqual(4 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszArch",
    ));
    try std.testing.expectEqual(5 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszChecksumType",
    ));
    try std.testing.expectEqual(6 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszChecksumValue",
    ));
    try std.testing.expectEqual(7 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszLocationHref",
    ));
    try std.testing.expectEqual(8 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszLocationBase",
    ));
    try std.testing.expectEqual(9 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "pszSummary",
    ));
    try std.testing.expectEqual(scalar_offset, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "nPackageSize",
    ));
    try std.testing.expectEqual(scalar_offset + 8, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "nInstalledSize",
    ));
    try std.testing.expectEqual(scalar_offset + 16, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "dwPackageId",
    ));
    try std.testing.expectEqual(scalar_offset + 20, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "dwRepositoryId",
    ));
    try std.testing.expectEqual(scalar_offset + 24, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "dwEpoch",
    ));
    try std.testing.expectEqual(scalar_offset + 28, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "dwRpmDbHnum",
    ));
    try std.testing.expectEqual(scalar_offset + 32, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "nRepositoryKind",
    ));
    try std.testing.expectEqual(scalar_offset + 36, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "nHasEpoch",
    ));
    try std.testing.expectEqual(scalar_offset + 40, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "nHasRpmDbHnum",
    ));
    try std.testing.expectEqual(scalar_offset + 44, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "nChecksumIsPkgId",
    ));
    try std.testing.expectEqual(scalar_offset + 48, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "nHasPackageSize",
    ));
    try std.testing.expectEqual(scalar_offset + 52, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        "nHasInstalledSize",
    ));
}

test "native solver action and relation layouts remain stable" {
    const pointer_size = @sizeOf(*anyopaque);
    const relation_scalar_offset = 4 * pointer_size;
    const relation_size: usize = if (pointer_size == 8) 56 else 36;

    try std.testing.expect(pointer_size == 4 or pointer_size == 8);
    try std.testing.expectEqual(@as(usize, 28), @sizeOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_ACTION,
    ));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_ACTION,
    ));
    inline for (.{
        .{ "dwPackageRef", 0 },
        .{ "dwKind", 4 },
        .{ "dwReason", 8 },
        .{ "dwPriorOffset", 12 },
        .{ "dwPriorCount", 16 },
        .{ "dwRequestedJobId", 20 },
        .{ "nHasRequestedJobId", 24 },
    }) |field| {
        try std.testing.expectEqual(
            @as(usize, field[1]),
            @offsetOf(c.TDNF_REPOMD_NATIVE_SOLVER_ACTION, field[0]),
        );
    }

    try std.testing.expectEqual(pointer_size, @alignOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_RELATION,
    ));
    try std.testing.expectEqual(relation_size, @sizeOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_RELATION,
    ));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_RELATION,
        "pszName",
    ));
    try std.testing.expectEqual(pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_RELATION,
        "pszVersion",
    ));
    try std.testing.expectEqual(2 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_RELATION,
        "pszRelease",
    ));
    try std.testing.expectEqual(3 * pointer_size, @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_RELATION,
        "pszFlags",
    ));
    inline for (.{
        .{ "dwComparison", 0 },
        .{ "dwEpoch", 4 },
        .{ "dwSense", 8 },
        .{ "nHasEpoch", 12 },
        .{ "nPre", 16 },
    }) |field| {
        try std.testing.expectEqual(
            relation_scalar_offset + field[1],
            @offsetOf(c.TDNF_REPOMD_NATIVE_SOLVER_RELATION, field[0]),
        );
    }
}

test "native solver problem and result layouts remain stable" {
    const pointer_size = @sizeOf(*anyopaque);
    const relation_size: usize = if (pointer_size == 8) 56 else 36;
    const problem_size: usize = if (pointer_size == 8) 96 else 72;
    const result_count_offset = 7 * pointer_size;

    try std.testing.expect(pointer_size == 4 or pointer_size == 8);
    try std.testing.expectEqual(pointer_size, @alignOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PROBLEM,
    ));
    try std.testing.expectEqual(problem_size, @sizeOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PROBLEM,
    ));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_PROBLEM,
        "capability",
    ));
    inline for (.{
        .{ "dwKind", 0 },
        .{ "dwPackageRef", 4 },
        .{ "dwRelatedPackageRef", 8 },
        .{ "dwJobId", 12 },
        .{ "dwCount", 16 },
        .{ "nHasPackageRef", 20 },
        .{ "nHasRelatedPackageRef", 24 },
        .{ "nHasCapability", 28 },
        .{ "nHasJobId", 32 },
    }) |field| {
        try std.testing.expectEqual(
            relation_size + field[1],
            @offsetOf(c.TDNF_REPOMD_NATIVE_SOLVER_PROBLEM, field[0]),
        );
    }

    try std.testing.expectEqual(pointer_size, @alignOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_RESULT,
    ));
    try std.testing.expectEqual(result_count_offset + 24, @sizeOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_RESULT,
    ));
    inline for (.{
        .{ "pPackages", 0 },
        .{ "pdwSelectedPackageRefs", 1 },
        .{ "pActions", 2 },
        .{ "pdwPriorPackageRefs", 3 },
        .{ "pdwPriorHnums", 4 },
        .{ "pProblems", 5 },
        .{ "pdwSkippedJobIds", 6 },
    }) |field| {
        try std.testing.expectEqual(
            field[1] * pointer_size,
            @offsetOf(c.TDNF_REPOMD_NATIVE_SOLVER_RESULT, field[0]),
        );
    }
    inline for (.{
        .{ "dwPackageCount", 0 },
        .{ "dwSelectedPackageCount", 4 },
        .{ "dwActionCount", 8 },
        .{ "dwPriorPackageRefCount", 12 },
        .{ "dwProblemCount", 16 },
        .{ "dwSkippedJobCount", 20 },
    }) |field| {
        try std.testing.expectEqual(
            result_count_offset + field[1],
            @offsetOf(c.TDNF_REPOMD_NATIVE_SOLVER_RESULT, field[0]),
        );
    }
}

test "native solver Zig ABI mirror matches the public C layouts" {
    try expectSameLayout(
        solver_result_abi.Package,
        c.TDNF_REPOMD_NATIVE_SOLVER_PACKAGE,
        .{
            "pszRepository",
            "pszName",
            "pszVersion",
            "pszRelease",
            "pszArch",
            "pszChecksumType",
            "pszChecksumValue",
            "pszLocationHref",
            "pszLocationBase",
            "pszSummary",
            "nPackageSize",
            "nInstalledSize",
            "dwPackageId",
            "dwRepositoryId",
            "dwEpoch",
            "dwRpmDbHnum",
            "nRepositoryKind",
            "nHasEpoch",
            "nHasRpmDbHnum",
            "nChecksumIsPkgId",
            "nHasPackageSize",
            "nHasInstalledSize",
        },
    );
    try expectSameLayout(
        solver_result_abi.Action,
        c.TDNF_REPOMD_NATIVE_SOLVER_ACTION,
        .{
            "dwPackageRef",
            "dwKind",
            "dwReason",
            "dwPriorOffset",
            "dwPriorCount",
            "dwRequestedJobId",
            "nHasRequestedJobId",
        },
    );
    try expectSameLayout(
        solver_result_abi.Relation,
        c.TDNF_REPOMD_NATIVE_SOLVER_RELATION,
        .{
            "pszName",
            "pszVersion",
            "pszRelease",
            "pszFlags",
            "dwComparison",
            "dwEpoch",
            "dwSense",
            "nHasEpoch",
            "nPre",
        },
    );
    try expectSameLayout(
        solver_result_abi.Problem,
        c.TDNF_REPOMD_NATIVE_SOLVER_PROBLEM,
        .{
            "capability",
            "dwKind",
            "dwPackageRef",
            "dwRelatedPackageRef",
            "dwJobId",
            "dwCount",
            "nHasPackageRef",
            "nHasRelatedPackageRef",
            "nHasCapability",
            "nHasJobId",
        },
    );
    try expectSameLayout(
        solver_result_abi.Result,
        c.TDNF_REPOMD_NATIVE_SOLVER_RESULT,
        .{
            "pPackages",
            "pdwSelectedPackageRefs",
            "pActions",
            "pdwPriorPackageRefs",
            "pdwPriorHnums",
            "pProblems",
            "pdwSkippedJobIds",
            "dwPackageCount",
            "dwSelectedPackageCount",
            "dwActionCount",
            "dwPriorPackageRefCount",
            "dwProblemCount",
            "dwSkippedJobCount",
        },
    );
}

test "native solver shadow ABI mirror matches the public C layouts" {
    try expectSameLayout(
        solver_shadow_abi.LegacyPackage,
        c.TDNF_PKG_INFO,
        .{
            "dwEpoch",
            "dwInstallSizeBytes",
            "dwDownloadSizeBytes",
            "nChecksumType",
            "pszName",
            "pszRepoName",
            "pszVersion",
            "pszArch",
            "pszEVR",
            "pszSummary",
            "pszURL",
            "pszLicense",
            "pszDescription",
            "pszFormattedSize",
            "pszFormattedDownloadSize",
            "pszRelease",
            "pszLocation",
            "pppszDependencies",
            "ppszFileList",
            "pszSourcePkg",
            "pbChecksum",
            "pChangeLogEntries",
            "pNext",
        },
    );
    try expectSameLayout(
        solver_shadow_abi.LegacyResult,
        c.TDNF_SOLVED_PKG_INFO,
        .{
            "nNeedAction",
            "nNeedDownload",
            "nAlterType",
            "pPkgsNotAvailable",
            "pPkgsExisting",
            "pPkgsToInstall",
            "pPkgsToDowngrade",
            "pPkgsToUpgrade",
            "pPkgsToRemove",
            "pPkgsUnNeeded",
            "pPkgsToReinstall",
            "pPkgsObsoleted",
            "pPkgsRemovedByDowngrade",
            "ppszPkgsNotResolved",
            "ppszPkgsUserInstall",
        },
    );
    try expectSameLayout(
        solver_shadow_abi.Comparison,
        c.TDNF_REPOMD_NATIVE_SOLVER_COMPARE_RESULT,
        .{
            "dwStatus",
            "dwReason",
            "dwActionKind",
            "dwDifferenceIndex",
            "dwNativeCount",
            "dwLegacyCount",
        },
    );
}

test "native solver live ABI mirrors match the public C layouts" {
    try expectSameLayout(
        solver_live_abi.Repository,
        c.TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY,
        .{
            "pszId",
            "pszCacheDir",
            "pszSnapshotFile",
            "nPriority",
            "dwCost",
        },
    );
    try expectSameLayout(
        solver_live_abi.Job,
        c.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
        .{
            "pszRepository",
            "pszName",
            "pszVersion",
            "pszRelease",
            "pszArch",
            "pszChecksumType",
            "pszChecksumValue",
            "dwEpoch",
            "nChecksumIsPkgId",
        },
    );
}

test "native solver shadow C layouts remain stable" {
    const pointer_size = @sizeOf(*anyopaque);
    const package_size: usize = if (pointer_size == 8) 168 else 92;
    const result_pointer_offset: usize = if (pointer_size == 8) 16 else 12;
    const result_size: usize = if (pointer_size == 8) 112 else 60;

    try std.testing.expect(pointer_size == 4 or pointer_size == 8);
    try std.testing.expectEqual(pointer_size, @alignOf(c.TDNF_PKG_INFO));
    try std.testing.expectEqual(package_size, @sizeOf(c.TDNF_PKG_INFO));
    inline for (.{
        .{ "dwEpoch", 0 },
        .{ "dwInstallSizeBytes", 4 },
        .{ "dwDownloadSizeBytes", 8 },
        .{ "nChecksumType", 12 },
    }) |field| {
        try std.testing.expectEqual(
            @as(usize, field[1]),
            @offsetOf(c.TDNF_PKG_INFO, field[0]),
        );
    }
    inline for (.{
        .{ "pszName", 0 },
        .{ "pszRepoName", 1 },
        .{ "pszVersion", 2 },
        .{ "pszArch", 3 },
        .{ "pszEVR", 4 },
        .{ "pszSummary", 5 },
        .{ "pszURL", 6 },
        .{ "pszLicense", 7 },
        .{ "pszDescription", 8 },
        .{ "pszFormattedSize", 9 },
        .{ "pszFormattedDownloadSize", 10 },
        .{ "pszRelease", 11 },
        .{ "pszLocation", 12 },
        .{ "pppszDependencies", 13 },
        .{ "ppszFileList", 14 },
        .{ "pszSourcePkg", 15 },
        .{ "pbChecksum", 16 },
        .{ "pChangeLogEntries", 17 },
        .{ "pNext", 18 },
    }) |field| {
        try std.testing.expectEqual(
            16 + field[1] * pointer_size,
            @offsetOf(c.TDNF_PKG_INFO, field[0]),
        );
    }

    try std.testing.expectEqual(pointer_size, @alignOf(
        c.TDNF_SOLVED_PKG_INFO,
    ));
    try std.testing.expectEqual(result_size, @sizeOf(
        c.TDNF_SOLVED_PKG_INFO,
    ));
    inline for (.{
        .{ "nNeedAction", 0 },
        .{ "nNeedDownload", 4 },
        .{ "nAlterType", 8 },
    }) |field| {
        try std.testing.expectEqual(
            @as(usize, field[1]),
            @offsetOf(c.TDNF_SOLVED_PKG_INFO, field[0]),
        );
    }
    inline for (.{
        .{ "pPkgsNotAvailable", 0 },
        .{ "pPkgsExisting", 1 },
        .{ "pPkgsToInstall", 2 },
        .{ "pPkgsToDowngrade", 3 },
        .{ "pPkgsToUpgrade", 4 },
        .{ "pPkgsToRemove", 5 },
        .{ "pPkgsUnNeeded", 6 },
        .{ "pPkgsToReinstall", 7 },
        .{ "pPkgsObsoleted", 8 },
        .{ "pPkgsRemovedByDowngrade", 9 },
        .{ "ppszPkgsNotResolved", 10 },
        .{ "ppszPkgsUserInstall", 11 },
    }) |field| {
        try std.testing.expectEqual(
            result_pointer_offset + field[1] * pointer_size,
            @offsetOf(c.TDNF_SOLVED_PKG_INFO, field[0]),
        );
    }

    try std.testing.expectEqual(@as(usize, 24), @sizeOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_COMPARE_RESULT,
    ));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(
        c.TDNF_REPOMD_NATIVE_SOLVER_COMPARE_RESULT,
    ));
    inline for (.{
        .{ "dwStatus", 0 },
        .{ "dwReason", 4 },
        .{ "dwActionKind", 8 },
        .{ "dwDifferenceIndex", 12 },
        .{ "dwNativeCount", 16 },
        .{ "dwLegacyCount", 20 },
    }) |field| {
        try std.testing.expectEqual(
            @as(usize, field[1]),
            @offsetOf(c.TDNF_REPOMD_NATIVE_SOLVER_COMPARE_RESULT, field[0]),
        );
    }
}
