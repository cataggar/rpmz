const std = @import("std");

const abi = @import("transaction_plan_capture_abi");
const capture = @import("transaction_plan_libsolv");
const request_trace = @import("transaction_plan_request_trace");

const c = capture.libsolv;
const testing = std.testing;

const checksum_a =
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const checksum_b =
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

const PackageSpec = struct {
    name: [:0]const u8,
    evr: [:0]const u8 = "1-1",
    arch: [:0]const u8 = "x86_64",
    location: [:0]const u8 = "packages/test.rpm",
    xml_base: ?[:0]const u8 = null,
    checksum: [:0]const u8 = checksum_a,
    checksum_is_pkgid: bool = true,
    hnum: ?u32 = null,
    size: u64 = 100,
};

const Fixture = struct {
    pool: *c.Pool,
    repositories: [16]?*c.Repo = [_]?*c.Repo{null} ** 16,
    repository_count: usize = 0,
    considered: ?*c.Map = null,

    fn init() !Fixture {
        const pool = c.pool_create() orelse return error.OutOfMemory;
        errdefer c.pool_free(pool);
        if (c.pool_setdisttype(pool, c.DISTTYPE_RPM) != 0) {
            return error.TestUnexpectedResult;
        }
        c.pool_setarch(pool, "x86_64");
        return .{ .pool = pool };
    }

    fn deinit(self: *Fixture) void {
        if (self.considered) |considered| {
            self.pool.considered = null;
            c.map_free(considered);
            testing.allocator.destroy(considered);
        }
        c.pool_free(self.pool);
        self.* = undefined;
    }

    fn addRepository(
        self: *Fixture,
        name: [:0]const u8,
        installed: bool,
    ) !*c.Repo {
        if (self.repository_count == self.repositories.len) {
            return error.TestUnexpectedResult;
        }
        const raw = c.repo_create(self.pool, name);
        if (raw == null) return error.OutOfMemory;
        const repository: *c.Repo = @ptrCast(raw);
        self.repositories[self.repository_count] = repository;
        self.repository_count += 1;
        if (installed) self.pool.installed = repository;
        return repository;
    }

    fn addPackage(
        self: *Fixture,
        repository: *c.Repo,
        spec: PackageSpec,
    ) !c.Id {
        const solvid = c.repo_add_solvable(repository);
        const raw = c.pool_id2solvable(self.pool, solvid);
        if (raw == null) return error.OutOfMemory;
        const solvable: *c.Solvable = @ptrCast(raw);
        solvable.name = c.pool_str2id(self.pool, spec.name, 1);
        solvable.arch = c.pool_str2id(self.pool, spec.arch, 1);
        solvable.evr = c.pool_str2id(self.pool, spec.evr, 1);
        const self_provide = c.pool_rel2id(
            self.pool,
            solvable.name,
            solvable.evr,
            c.REL_EQ,
            1,
        );
        solvable.provides = c.repo_addid_dep(
            repository,
            solvable.provides,
            self_provide,
            0,
        );

        const data = c.repo_add_repodata(repository, 0) orelse
            return error.OutOfMemory;
        if (repository == installedRepository(self.pool)) {
            c.solvable_set_num(
                solvable,
                c.RPM_RPMDBID,
                spec.hnum orelse return error.TestExpectedEqual,
            );
        } else {
            c.repodata_set_checksum(
                data,
                solvid,
                c.SOLVABLE_CHECKSUM,
                c.REPOKEY_TYPE_SHA256,
                spec.checksum,
            );
            if (spec.checksum_is_pkgid) {
                c.repodata_set_checksum(
                    data,
                    solvid,
                    c.SOLVABLE_PKGID,
                    c.REPOKEY_TYPE_SHA256,
                    spec.checksum,
                );
            }
            c.repodata_set_location(
                data,
                solvid,
                0,
                null,
                spec.location,
            );
            if (spec.xml_base) |xml_base| {
                c.repodata_set_str(
                    data,
                    solvid,
                    c.SOLVABLE_MEDIABASE,
                    xml_base,
                );
            }
            c.repodata_set_num(
                data,
                solvid,
                c.SOLVABLE_DOWNLOADSIZE,
                spec.size,
            );
        }
        c.repodata_internalize(data);
        return solvid;
    }

    fn addDependency(
        self: *Fixture,
        package: c.Id,
        name: [:0]const u8,
        kind: c.Id,
    ) !void {
        const raw = c.pool_id2solvable(self.pool, package);
        if (raw == null) return error.TestUnexpectedResult;
        const solvable: *c.Solvable = @ptrCast(raw);
        const repository = solvableRepository(solvable);
        const dependency = c.pool_str2id(self.pool, name, 1);
        if (kind == c.SOLVABLE_REQUIRES) {
            solvable.requires = c.repo_addid_dep(
                repository,
                solvable.requires,
                dependency,
                0,
            );
        } else if (kind == c.SOLVABLE_RECOMMENDS) {
            solvable.recommends = c.repo_addid_dep(
                repository,
                solvable.recommends,
                dependency,
                0,
            );
        } else if (kind == c.SOLVABLE_CONFLICTS) {
            solvable.conflicts = c.repo_addid_dep(
                repository,
                solvable.conflicts,
                dependency,
                0,
            );
        } else if (kind == c.SOLVABLE_OBSOLETES) {
            solvable.obsoletes = c.repo_addid_dep(
                repository,
                solvable.obsoletes,
                dependency,
                0,
            );
        } else {
            return error.TestUnexpectedResult;
        }
    }

    fn addProvide(
        self: *Fixture,
        package: c.Id,
        name: [:0]const u8,
        evr: [:0]const u8,
    ) !c.Id {
        const raw = c.pool_id2solvable(self.pool, package);
        if (raw == null) return error.TestUnexpectedResult;
        const solvable: *c.Solvable = @ptrCast(raw);
        const repository = solvableRepository(solvable);
        const relation = c.pool_rel2id(
            self.pool,
            c.pool_str2id(self.pool, name, 1),
            c.pool_str2id(self.pool, evr, 1),
            c.REL_EQ,
            1,
        );
        solvable.provides = c.repo_addid_dep(
            repository,
            solvable.provides,
            relation,
            0,
        );
        return relation;
    }

    fn finish(self: *Fixture) void {
        for (self.repositories[0..self.repository_count]) |raw| {
            c.repo_internalize(raw.?);
        }
        c.pool_createwhatprovides(self.pool);
    }

    fn hide(self: *Fixture, solvids: []const c.Id) !void {
        const considered = try testing.allocator.create(c.Map);
        errdefer testing.allocator.destroy(considered);
        c.map_init(considered, self.pool.nsolvables);
        c.map_setall(considered);
        for (solvids) |solvid| c.map_clr(considered, solvid);
        self.pool.considered = considered;
        self.considered = considered;
    }
};

const Solved = struct {
    solver: *c.Solver,
    transaction: ?*c.Transaction,
    problems: u32,

    fn deinit(self: *Solved) void {
        if (self.transaction) |transaction| c.transaction_free(transaction);
        c.solver_free(self.solver);
        self.* = undefined;
    }
};

fn solve(
    pool: *c.Pool,
    jobs: *c.Queue,
    make_transaction: bool,
) !Solved {
    const solver = c.solver_create(pool) orelse return error.OutOfMemory;
    errdefer c.solver_free(solver);
    _ = c.solver_set_flag(solver, c.SOLVER_FLAG_ALLOW_DOWNGRADE, 1);
    _ = c.solver_set_flag(solver, c.SOLVER_FLAG_ALLOW_VENDORCHANGE, 1);
    _ = c.solver_set_flag(solver, c.SOLVER_FLAG_KEEP_ORPHANS, 1);
    _ = c.solver_set_flag(solver, c.SOLVER_FLAG_BEST_OBEY_POLICY, 1);
    _ = c.solver_set_flag(solver, c.SOLVER_FLAG_YUM_OBSOLETES, 1);
    _ = c.solver_set_flag(solver, c.SOLVER_FLAG_INSTALL_ALSO_UPDATES, 1);
    const raw_problems = c.solver_solve(solver, jobs);
    if (raw_problems < 0) return error.TestUnexpectedResult;
    const transaction = if (make_transaction)
        c.solver_create_transaction(solver) orelse return error.OutOfMemory
    else
        null;
    return .{
        .solver = solver,
        .transaction = transaction,
        .problems = @intCast(raw_problems),
    };
}

fn queueSlice(queue: *const c.Queue) []const i32 {
    if (queue.count == 0) return &.{};
    return queue.elements[0..@intCast(queue.count)];
}

fn addUserPackageJob(
    trace: *request_trace.Trace,
    pair: u32,
    request_ref: u32,
    action: u32,
    solvid: c.Id,
    how: c.Id,
) !void {
    try trace.recordPackageJob(
        pair,
        action,
        solvid,
        how,
        0,
        abi.request_reason.user,
        request_ref,
    );
}

fn packageByName(
    facts: *const abi.Capture,
    name: []const u8,
    state: u32,
) ?struct { ref: u32, package: *const abi.Package } {
    const packages = if (facts.package_count == 0)
        return null
    else
        facts.packages.?[0..facts.package_count];
    for (packages, 0..) |*package, index| {
        if (package.state == state and
            std.mem.eql(u8, bytes(package.identity.name), name))
        {
            return .{ .ref = @intCast(index), .package = package };
        }
    }
    return null;
}

fn repositoryById(
    facts: *const abi.Capture,
    id: []const u8,
) ?*const abi.Repository {
    const repositories = if (facts.repository_count == 0)
        return null
    else
        facts.repositories.?[0..facts.repository_count];
    for (repositories) |*repository| {
        if (std.mem.eql(u8, bytes(repository.id), id)) return repository;
    }
    return null;
}

fn bytes(value: abi.Bytes) []const u8 {
    return if (value.length == 0) "" else value.data.?[0..value.length];
}

fn installedRepository(pool: *c.Pool) ?*c.Repo {
    if (pool.installed == null) return null;
    return @ptrCast(pool.installed);
}

fn solvableRepository(solvable: *c.Solvable) *c.Repo {
    return @ptrCast(solvable.repo);
}

test "install capture owns jobs dependencies selected providers hidden metadata and hnums" {
    var fixture = try Fixture.init();
    var fixture_live = true;
    defer if (fixture_live) fixture.deinit();
    const installed = try fixture.addRepository("@System", true);
    const available = try fixture.addRepository("base", false);
    const provider = try fixture.addPackage(installed, .{
        .name = "provider",
        .evr = "0:1-1",
        .hnum = 41,
    });
    const app = try fixture.addPackage(available, .{
        .name = "app",
        .evr = "2-3",
        .location = "packages/app.rpm",
        .xml_base = "https://example.invalid/repo/",
        .checksum = checksum_a,
        .size = 321,
    });
    const dependency = try fixture.addPackage(available, .{
        .name = "dependency",
        .evr = "1:4-5",
        .location = "packages/dependency.rpm",
        .checksum = checksum_b,
    });
    const hidden = try fixture.addPackage(available, .{
        .name = "hidden",
        .location = "packages/hidden.rpm",
        .checksum = checksum_b,
        .checksum_is_pkgid = false,
    });
    try fixture.addDependency(app, "provider", c.SOLVABLE_REQUIRES);
    try fixture.addDependency(app, "dependency", c.SOLVABLE_REQUIRES);
    fixture.finish();
    try fixture.hide(&.{ hidden, provider });

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        app,
    );

    var trace = request_trace.Trace.init(testing.allocator);
    var trace_live = true;
    defer if (trace_live) trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "app",
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        abi.job_action.install,
        app,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), c.SOLVER_CLEANDEPS, c.SOLVER_FORCEBEST);

    var solved = try solve(fixture.pool, &jobs, true);
    var solved_live = true;
    defer if (solved_live) solved.deinit();
    try testing.expectEqual(@as(u32, 0), solved.problems);
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    });
    defer owner.destroy();

    trace.deinit();
    trace_live = false;
    solved.deinit();
    solved_live = false;
    fixture.deinit();
    fixture_live = false;

    const facts = owner.view();
    try testing.expectEqual(abi.abi_version, facts.abi_version);
    try testing.expectEqual(
        @as(u32, @intCast(@sizeOf(abi.Capture))),
        facts.struct_size,
    );
    try testing.expectEqual(
        abi.resolution_status.resolved,
        facts.environment.resolution_status,
    );
    try testing.expectEqual(@as(u32, 1), facts.job_count);
    try testing.expectEqual(@as(u32, 2), facts.action_count);
    try testing.expectEqual(@as(u32, 3), facts.selected_package_ref_count);
    try testing.expectEqual(@as(u32, 1), facts.hidden_package_ref_count);

    const installed_provider = packageByName(
        facts,
        "provider",
        abi.package_state.installed,
    ).?;
    try testing.expectEqual(@as(u32, 41), installed_provider.package.rpmdb_hnum);
    try testing.expectEqual(
        @as(u32, 1),
        installed_provider.package.identity.has_epoch,
    );
    try testing.expectEqual(@as(u32, 0), installed_provider.package.identity.epoch);
    const app_package = packageByName(
        facts,
        "app",
        abi.package_state.available,
    ).?;
    try testing.expectEqual(@as(u32, 0), app_package.package.identity.has_epoch);
    try testing.expectEqual(@as(u32, 1), app_package.package.has_source);
    try testing.expectEqual(@as(u32, 1), app_package.package.source.checksum.is_pkgid);
    try testing.expectEqualStrings(
        "packages/app.rpm",
        bytes(app_package.package.source.location.href),
    );
    try testing.expectEqualStrings(
        "https://example.invalid/repo/",
        bytes(app_package.package.source.location.xml_base),
    );
    try testing.expectEqual(@as(u64, 321), app_package.package.source.size);
    const dependency_package = packageByName(
        facts,
        "dependency",
        abi.package_state.available,
    ).?;
    try testing.expectEqual(@as(u32, 1), dependency_package.package.identity.epoch);
    try testing.expectEqual(@as(u32, 1), dependency_package.package.identity.has_epoch);
    const hidden_ref = facts.hidden_package_refs.?[0];
    try testing.expectEqualStrings(
        "hidden",
        bytes(facts.packages.?[hidden_ref].identity.name),
    );
    try testing.expectEqual(
        @as(u32, 0),
        facts.packages.?[hidden_ref].source.checksum.is_pkgid,
    );

    const actions = facts.actions.?[0..facts.action_count];
    var saw_user = false;
    var saw_dependency = false;
    for (actions) |action| {
        const target = facts.packages.?[action.target_package_ref];
        if (std.mem.eql(u8, bytes(target.identity.name), "app")) {
            try testing.expectEqual(abi.action_kind.install, action.kind);
            try testing.expectEqual(abi.action_reason.user, action.reason);
            try testing.expectEqual(@as(u32, 1), action.has_requested_job_ref);
            saw_user = true;
        } else if (std.mem.eql(
            u8,
            bytes(target.identity.name),
            "dependency",
        )) {
            try testing.expectEqual(abi.action_reason.dependency, action.reason);
            saw_dependency = true;
        }
    }
    try testing.expect(saw_user);
    try testing.expect(saw_dependency);
    _ = dependency;
}

test "package and capability EVRs recognize only complete decimal epochs" {
    {
        const vectors = [_]struct {
            name: [:0]const u8,
            evr: [:0]const u8,
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

        var fixture = try Fixture.init();
        defer fixture.deinit();
        const available = try fixture.addRepository("base", false);
        var package_ids: [vectors.len]c.Id = undefined;
        for (vectors, &package_ids) |vector, *package_id| {
            package_id.* = try fixture.addPackage(available, .{
                .name = vector.name,
                .evr = vector.evr,
            });
        }
        fixture.finish();

        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        for (vectors, package_ids, 0..) |vector, package_id, index| {
            c.queue_push2(
                &jobs,
                c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
                package_id,
            );
            const request_ref = try trace.addRequest(
                abi.request_kind.install,
                vector.name,
                false,
            );
            try addUserPackageJob(
                &trace,
                @intCast(index),
                request_ref,
                abi.job_action.install,
                package_id,
                c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            );
        }
        try trace.finalize(queueSlice(&jobs), 0, 0);

        var solved = try solve(fixture.pool, &jobs, true);
        defer solved.deinit();
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
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
            try testing.expectEqual(
                vector.epoch orelse 0,
                package.identity.epoch,
            );
            try testing.expectEqualStrings(
                vector.version,
                bytes(package.identity.version),
            );
            try testing.expectEqualStrings(
                vector.release,
                bytes(package.identity.release),
            );
        }
    }

    {
        const vectors = [_]struct {
            package_name: [:0]const u8,
            capability_name: [:0]const u8,
            evr: [:0]const u8,
            epoch: ?u64,
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

        var fixture = try Fixture.init();
        defer fixture.deinit();
        const available = try fixture.addRepository("base", false);
        var relations: [vectors.len]c.Id = undefined;
        for (vectors, &relations) |vector, *relation| {
            const package = try fixture.addPackage(available, .{
                .name = vector.package_name,
            });
            relation.* = try fixture.addProvide(
                package,
                vector.capability_name,
                vector.evr,
            );
        }
        fixture.finish();

        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        for (vectors, relations, 0..) |vector, relation, index| {
            c.queue_push2(
                &jobs,
                c.SOLVER_SOLVABLE_PROVIDES | c.SOLVER_INSTALL,
                relation,
            );
            const request_ref = try trace.addRequest(
                abi.request_kind.install,
                vector.capability_name,
                false,
            );
            try trace.recordCapabilityJob(
                @intCast(index),
                abi.job_action.install,
                .{
                    .name = vector.capability_name,
                    .flags = "EQ",
                    .version = vector.version,
                    .release = vector.release,
                    .epoch = vector.epoch,
                    .comparison = abi.compare_op.eq,
                },
                c.SOLVER_SOLVABLE_PROVIDES | c.SOLVER_INSTALL,
                0,
                abi.request_reason.user,
                request_ref,
            );
        }
        try trace.finalize(queueSlice(&jobs), 0, 0);

        var solved = try solve(fixture.pool, &jobs, true);
        defer solved.deinit();
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
        });
        defer owner.destroy();

        const captured_jobs = owner.view().jobs.?[0..owner.view().job_count];
        for (vectors, captured_jobs) |vector, job| {
            const capability = job.capability;
            try testing.expectEqualStrings(
                vector.capability_name,
                bytes(capability.name),
            );
            try testing.expectEqual(
                @as(u32, @intFromBool(vector.epoch != null)),
                capability.has_epoch,
            );
            try testing.expectEqual(vector.epoch orelse 0, capability.epoch);
            try testing.expectEqualStrings(
                vector.version,
                bytes(capability.version),
            );
            try testing.expectEqual(
                @as(u32, @intFromBool(vector.release != null)),
                capability.has_release,
            );
            if (vector.release) |release| {
                try testing.expectEqualStrings(
                    release,
                    bytes(capability.release),
                );
            }
        }
    }
}

test "job queue mismatch fails closed without publishing partial facts" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const available = try fixture.addRepository("base", false);
    const package = try fixture.addPackage(available, .{ .name = "app" });
    const stale_package = try fixture.addPackage(
        available,
        .{ .name = "stale-app" },
    );
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        package,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "app",
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        abi.job_action.install,
        package,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);

    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    jobs.elements[1] = stale_package;
    var stale_job = trace.getView().?.jobs.?[0];
    stale_job.selection_id = stale_package;
    var stale_view = trace.getView().?.*;
    stale_view.jobs = @ptrCast(&stale_job);
    try testing.expectError(error.JobMismatch, capture.create(
        testing.allocator,
        .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = &stale_view,
            .solve_status = 0,
            .problem_count = 0,
        },
    ));
}

test "solver pool-job prefixes do not shift submitted job attribution" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const available = try fixture.addRepository("base", false);
    const package = try fixture.addPackage(available, .{ .name = "app" });
    fixture.finish();
    const name_id = c.pool_str2id(fixture.pool, "app", 0);
    c.queue_push2(
        &fixture.pool.pooljobs,
        c.SOLVER_SOLVABLE_NAME | c.SOLVER_MULTIVERSION,
        name_id,
    );

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        package,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "app",
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        abi.job_action.install,
        package,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);

    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    try testing.expectEqual(@as(c_int, 2), solved.solver.pooljobcnt);
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    });
    defer owner.destroy();

    var saw_app = false;
    for (owner.view().actions.?[0..owner.view().action_count]) |action| {
        const target = owner.view().packages.?[action.target_package_ref];
        if (std.mem.eql(u8, bytes(target.identity.name), "app")) {
            try testing.expectEqual(@as(u32, 1), action.has_requested_job_ref);
            try testing.expectEqual(@as(u32, 0), action.requested_job_ref);
            saw_app = true;
        }
    }
    try testing.expect(saw_app);
}

test "unresolved input fails closed and C outputs are always cleared" {
    var sentinel_storage: usize = 0;
    var facts_output: ?*const abi.Capture = @ptrCast(&sentinel_storage);
    var owner_output: ?*anyopaque = @ptrCast(&sentinel_storage);
    const invalid_parameter = capture.mapCaptureError(error.InvalidInput);

    try testing.expectEqual(
        invalid_parameter,
        capture.libsolvCaptureCreate(
            null,
            null,
            null,
            null,
            null,
            0,
            0,
            0,
            0,
            null,
            0,
            &facts_output,
            null,
        ),
    );
    try testing.expect(facts_output == null);

    owner_output = @ptrCast(&sentinel_storage);
    try testing.expectEqual(
        invalid_parameter,
        capture.libsolvCaptureCreate(
            null,
            null,
            null,
            null,
            null,
            0,
            0,
            0,
            0,
            null,
            0,
            null,
            &owner_output,
        ),
    );
    try testing.expect(owner_output == null);

    var fixture = try Fixture.init();
    defer fixture.deinit();
    const available = try fixture.addRepository("base", false);
    const package = try fixture.addPackage(available, .{ .name = "app" });
    fixture.finish();
    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        package,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "app",
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        abi.job_action.install,
        package,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();

    const input = capture.Input{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
        .unresolved_count = 1,
    };
    try testing.expectError(
        error.UnsupportedResult,
        capture.create(testing.allocator, input),
    );

    facts_output = @ptrCast(&sentinel_storage);
    owner_output = @ptrCast(&sentinel_storage);
    try testing.expectEqual(
        capture.mapCaptureError(error.UnsupportedResult),
        capture.libsolvCaptureCreate(
            fixture.pool,
            solved.solver,
            solved.transaction,
            &jobs,
            trace.getView().?,
            0,
            0,
            0,
            1,
            null,
            0,
            &facts_output,
            &owner_output,
        ),
    );
    try testing.expect(facts_output == null);
    try testing.expect(owner_output == null);
}

test "malformed solvable string relation and repository IDs fail safely" {
    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const available = try fixture.addRepository("base", false);
        const package = try fixture.addPackage(available, .{ .name = "app" });
        fixture.finish();
        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            package,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const request_ref = try trace.addRequest(
            abi.request_kind.install,
            "app",
            false,
        );
        try addUserPackageJob(
            &trace,
            0,
            request_ref,
            abi.job_action.install,
            package,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        );
        try trace.finalize(queueSlice(&jobs), 0, 0);
        var solved = try solve(fixture.pool, &jobs, true);
        defer solved.deinit();
        const input = capture.Input{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
        };

        const solver_what_index: usize =
            @intCast(solved.solver.pooljobcnt + 1);
        const invalid_solvid = fixture.pool.nsolvables;
        jobs.elements[1] = invalid_solvid;
        solved.solver.job.elements[solver_what_index] = invalid_solvid;
        var malformed_job = trace.getView().?.jobs.?[0];
        malformed_job.selection_id = invalid_solvid;
        var malformed_view = trace.getView().?.*;
        malformed_view.jobs = @ptrCast(&malformed_job);
        var malformed_input = input;
        malformed_input.trace = &malformed_view;
        try testing.expectError(
            error.UnsupportedResult,
            capture.create(testing.allocator, malformed_input),
        );
        jobs.elements[1] = package;
        solved.solver.job.elements[solver_what_index] = package;

        const raw_solvable = c.pool_id2solvable(fixture.pool, package);
        const solvable: *c.Solvable = @ptrCast(raw_solvable);
        const valid_name = solvable.name;
        solvable.name = fixture.pool.ss.nstrings;
        try testing.expectError(
            error.UnsupportedResult,
            capture.create(testing.allocator, input),
        );
        solvable.name = valid_name;

        const valid_end = available.end;
        available.end = package;
        try testing.expectError(
            error.UnsupportedResult,
            capture.create(testing.allocator, input),
        );
        available.end = valid_end;
    }

    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const available = try fixture.addRepository("base", false);
        const package = try fixture.addPackage(
            available,
            .{ .name = "provider" },
        );
        const relation = try fixture.addProvide(
            package,
            "capability",
            "1:2-3",
        );
        fixture.finish();
        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE_PROVIDES | c.SOLVER_INSTALL,
            relation,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const request_ref = try trace.addRequest(
            abi.request_kind.install,
            "capability",
            false,
        );
        try trace.recordCapabilityJob(
            0,
            abi.job_action.install,
            .{
                .name = "capability",
                .flags = "EQ",
                .version = "2",
                .release = "3",
                .epoch = 1,
                .comparison = abi.compare_op.eq,
            },
            c.SOLVER_SOLVABLE_PROVIDES | c.SOLVER_INSTALL,
            0,
            abi.request_reason.user,
            request_ref,
        );
        try trace.finalize(queueSlice(&jobs), 0, 0);
        var solved = try solve(fixture.pool, &jobs, true);
        defer solved.deinit();

        var malformed_job = trace.getView().?.jobs.?[0];
        var byte: u8 = 0;
        malformed_job.capability.version = .{
            .data = @ptrCast(&byte),
            .length = std.math.maxInt(usize),
        };
        var malformed_view = trace.getView().?.*;
        malformed_view.jobs = @ptrCast(&malformed_job);
        try testing.expectError(error.InvalidTrace, capture.create(
            testing.allocator,
            .{
                .pool = fixture.pool,
                .solver = solved.solver,
                .transaction = solved.transaction,
                .jobs = &jobs,
                .trace = &malformed_view,
                .solve_status = 0,
                .problem_count = 0,
            },
        ));

        const invalid_relation: c.Id = @bitCast(
            @as(u32, @intCast(fixture.pool.nrels)) | 0x80000000,
        );
        jobs.elements[1] = invalid_relation;
        const solver_what_index: usize =
            @intCast(solved.solver.pooljobcnt + 1);
        solved.solver.job.elements[solver_what_index] = invalid_relation;
        try testing.expectError(error.UnsupportedResult, capture.create(
            testing.allocator,
            .{
                .pool = fixture.pool,
                .solver = solved.solver,
                .transaction = solved.transaction,
                .jobs = &jobs,
                .trace = trace.getView().?,
                .solve_status = 0,
                .problem_count = 0,
            },
        ));
    }
}

test "borrowed spans reject oversized lengths with 32-bit-safe arithmetic" {
    const address_limit: usize = std.math.maxInt(i32);
    const max_u64_count = address_limit / @sizeOf(u64);
    try testing.expect(capture.sliceCountFitsAddressLimit(
        u64,
        max_u64_count,
        address_limit,
    ));
    try testing.expect(!capture.sliceCountFitsAddressLimit(
        u64,
        max_u64_count + 1,
        address_limit,
    ));
    try testing.expect(!capture.sliceCountFitsAddressLimit(
        u8,
        address_limit + 1,
        address_limit,
    ));

    var fixture = try Fixture.init();
    defer fixture.deinit();
    const available = try fixture.addRepository("base", false);
    const package = try fixture.addPackage(available, .{ .name = "app" });
    fixture.finish();
    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        package,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "app",
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        abi.job_action.install,
        package,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();

    var malformed_request = trace.getView().?.requests.?[0];
    var byte: u8 = 0;
    malformed_request.id = .{
        .data = @ptrCast(&byte),
        .length = std.math.maxInt(usize),
    };
    var malformed_view = trace.getView().?.*;
    malformed_view.requests = @ptrCast(&malformed_request);
    try testing.expectError(error.InvalidTrace, capture.create(
        testing.allocator,
        .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = &malformed_view,
            .solve_status = 0,
            .problem_count = 0,
        },
    ));
}

test "satisfied selections are captured and validated independently of jobs" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const installed = try fixture.addRepository("@System", true);
    const package = try fixture.addPackage(installed, .{
        .name = "installed",
        .hnum = 1,
    });
    fixture.finish();
    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "installed*",
        false,
    );
    const selections = [_]i32{package};
    try trace.recordGoalRange(
        &selections,
        0,
        1,
        5,
        abi.request_reason.user,
        request_ref,
    );
    try trace.commitGoal(package, 5, &.{}, 0, 0);
    try trace.finalize(&.{}, 0, 0);
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    const input = capture.Input{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    };
    const owner = try capture.create(testing.allocator, input);
    defer owner.destroy();
    try testing.expectEqual(@as(u32, 1), owner.view().package_count);
    try testing.expectEqual(@as(u32, 0), owner.view().job_count);

    var invalid_selection = trace.getView().?.satisfied_selections.?[0];
    invalid_selection.request_ref = 1;
    var invalid_view = trace.getView().?.*;
    invalid_view.satisfied_selections = @ptrCast(&invalid_selection);
    var invalid_input = input;
    invalid_input.trace = &invalid_view;
    try testing.expectError(
        error.InvalidTrace,
        capture.create(testing.allocator, invalid_input),
    );

    const duplicate_selections = [_]abi.RequestTraceSatisfiedSelection{
        trace.getView().?.satisfied_selections.?[0],
        trace.getView().?.satisfied_selections.?[0],
    };
    var duplicate_view = trace.getView().?.*;
    duplicate_view.satisfied_selections = &duplicate_selections;
    duplicate_view.satisfied_selection_count = duplicate_selections.len;
    var duplicate_input = input;
    duplicate_input.trace = &duplicate_view;
    try testing.expectError(
        error.InvalidTrace,
        capture.create(testing.allocator, duplicate_input),
    );
}

test "command-line package paths and hidden candidates never enter facts" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const command_line = try fixture.addRepository("@cmdline", false);
    const selected = try fixture.addPackage(command_line, .{
        .name = "local",
        .location = "/private/build/local.rpm",
    });
    const hidden = try fixture.addPackage(command_line, .{
        .name = "hidden-local",
        .location = "/private/build/hidden.rpm",
    });
    fixture.finish();
    try fixture.hide(&.{hidden});

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        selected,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        null,
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        abi.job_action.install,
        selected,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    });
    defer owner.destroy();

    const facts = owner.view();
    try testing.expectEqual(@as(u32, 1), facts.repository_count);
    try testing.expectEqual(
        abi.repository_kind.command_line,
        facts.repositories.?[0].kind,
    );
    try testing.expectEqual(@as(u32, 1), facts.package_count);
    try testing.expectEqual(@as(u32, 0), facts.hidden_package_ref_count);
    try testing.expectEqual(@as(u32, 1), facts.packages.?[0].has_source);
    try testing.expectEqual(
        @as(u32, 0),
        facts.packages.?[0].source.has_location,
    );
}

test "repository priorities use tdnf semantics by repository kind" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const installed = try fixture.addRepository("@System", true);
    const available = try fixture.addRepository("base", false);
    const command_line = try fixture.addRepository("@cmdline", false);
    installed.priority = 91;
    available.priority = -23;
    command_line.priority = -77;
    const old = try fixture.addPackage(installed, .{
        .name = "old",
        .hnum = 1,
    });
    const remote = try fixture.addPackage(available, .{ .name = "remote" });
    const local = try fixture.addPackage(command_line, .{ .name = "local" });
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(&jobs, c.SOLVER_SOLVABLE | c.SOLVER_ERASE, old);
    c.queue_push2(&jobs, c.SOLVER_SOLVABLE | c.SOLVER_INSTALL, remote);
    c.queue_push2(&jobs, c.SOLVER_SOLVABLE | c.SOLVER_INSTALL, local);

    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const erase_request = try trace.addRequest(
        abi.request_kind.erase,
        "old",
        false,
    );
    const remote_request = try trace.addRequest(
        abi.request_kind.install,
        "remote",
        false,
    );
    const local_request = try trace.addRequest(
        abi.request_kind.install,
        null,
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        erase_request,
        abi.job_action.erase,
        old,
        c.SOLVER_SOLVABLE | c.SOLVER_ERASE,
    );
    try addUserPackageJob(
        &trace,
        1,
        remote_request,
        abi.job_action.install,
        remote,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try addUserPackageJob(
        &trace,
        2,
        local_request,
        abi.job_action.install,
        local,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);

    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    const input = capture.Input{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    };
    const owner = try capture.create(testing.allocator, input);
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

    available.priority = std.math.minInt(i32);
    defer available.priority = -23;
    try testing.expectError(
        error.UnsupportedResult,
        capture.create(testing.allocator, input),
    );
}

fn replacementCase(
    installed_evr: [:0]const u8,
    available_evr: [:0]const u8,
    action: u32,
    expected_kind: u32,
) !void {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const installed_repo = try fixture.addRepository("@System", true);
    const available_repo = try fixture.addRepository("base", false);
    const old = try fixture.addPackage(installed_repo, .{
        .name = "pkg",
        .evr = installed_evr,
        .hnum = 9,
    });
    const new = try fixture.addPackage(available_repo, .{
        .name = "pkg",
        .evr = available_evr,
    });
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        new,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_kind = if (action == abi.job_action.downgrade)
        abi.request_kind.downgrade
    else if (action == abi.job_action.reinstall)
        abi.request_kind.reinstall
    else
        abi.request_kind.update;
    const request_ref = try trace.addRequest(request_kind, "pkg", false);
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        action,
        new,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);

    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    try testing.expectEqual(@as(u32, 0), solved.problems);
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
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
        bytes(facts.packages.?[prior_ref].identity.name),
    );
    _ = old;
}

test "upgrade downgrade and reinstall use authoritative EVR and priors" {
    try replacementCase(
        "1-1",
        "2-1",
        abi.job_action.update,
        abi.action_kind.upgrade,
    );
    try replacementCase(
        "2-1",
        "1-1",
        abi.job_action.downgrade,
        abi.action_kind.downgrade,
    );
    try replacementCase(
        "1-1",
        "1-1",
        abi.job_action.reinstall,
        abi.action_kind.reinstall,
    );
}

test "update-all attributes solver policy actions without inventing a request" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const installed = try fixture.addRepository("@System", true);
    const available = try fixture.addRepository("base", false);
    _ = try fixture.addPackage(installed, .{
        .name = "pkg",
        .evr = "1-1",
        .hnum = 8,
    });
    _ = try fixture.addPackage(available, .{
        .name = "pkg",
        .evr = "2-1",
    });
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE_ALL | c.SOLVER_UPDATE,
        0,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.update_all,
        null,
        false,
    );
    try trace.recordAllJob(
        0,
        abi.job_action.update,
        c.SOLVER_SOLVABLE_ALL | c.SOLVER_UPDATE,
        0,
        abi.request_reason.user,
        request_ref,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    });
    defer owner.destroy();
    try testing.expectEqual(@as(u32, 1), owner.view().action_count);
    const action = owner.view().actions.?[0];
    try testing.expectEqual(abi.action_kind.upgrade, action.kind);
    try testing.expectEqual(abi.action_reason.policy, action.reason);
    try testing.expectEqual(@as(u32, 0), action.has_requested_job_ref);
}

test "erase and installonly retry erase retain exact reasons" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const installed = try fixture.addRepository("@System", true);
    const available = try fixture.addRepository("base", false);
    const old = try fixture.addPackage(installed, .{
        .name = "kernel",
        .evr = "1-1",
        .hnum = 10,
    });
    const new = try fixture.addPackage(available, .{
        .name = "kernel",
        .evr = "2-1",
    });
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    const kernel_name = c.pool_str2id(fixture.pool, "kernel", 1);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE_NAME | c.SOLVER_MULTIVERSION,
        kernel_name,
    );
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        new,
    );
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_ERASE,
        old,
    );

    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "kernel",
        false,
    );
    try trace.recordNameJob(
        0,
        abi.job_action.multiversion,
        "kernel",
        c.SOLVER_SOLVABLE_NAME | c.SOLVER_MULTIVERSION,
        0,
        abi.request_reason.policy,
        abi.request_trace_no_request,
    );
    try addUserPackageJob(
        &trace,
        1,
        request_ref,
        abi.job_action.install,
        new,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.recordPackageJob(
        2,
        abi.job_action.erase,
        old,
        c.SOLVER_SOLVABLE | c.SOLVER_ERASE,
        0,
        abi.request_reason.installonly_limit,
        abi.request_trace_no_request,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);

    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    try testing.expectEqual(@as(u32, 0), solved.problems);
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
        .installonly_retry_erases = &.{old},
    });
    defer owner.destroy();
    const facts = owner.view();
    var saw_erase = false;
    var saw_install = false;
    for (facts.actions.?[0..facts.action_count]) |action_value| {
        if (action_value.kind == abi.action_kind.erase) {
            try testing.expectEqual(
                abi.action_reason.installonly_limit,
                action_value.reason,
            );
            try testing.expectEqual(@as(u32, 1), action_value.has_requested_job_ref);
            try testing.expectEqual(@as(u32, 2), action_value.requested_job_ref);
            saw_erase = true;
        } else if (action_value.kind == abi.action_kind.install) {
            saw_install = true;
        }
    }
    try testing.expect(saw_erase);
    try testing.expect(saw_install);

    try testing.expectError(error.JobMismatch, capture.create(
        testing.allocator,
        .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
            .installonly_retry_erases = &.{new},
        },
    ));
}

test "installonly terminal accepts only an attributed erase tail" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const installed = try fixture.addRepository("@System", true);
    const available = try fixture.addRepository("base", false);
    const old = try fixture.addPackage(installed, .{
        .name = "kernel",
        .evr = "1-1",
        .hnum = 10,
    });
    const new = try fixture.addPackage(available, .{
        .name = "kernel",
        .evr = "2-1",
    });
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    const kernel_name = c.pool_str2id(fixture.pool, "kernel", 1);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE_NAME | c.SOLVER_MULTIVERSION,
        kernel_name,
    );
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        new,
    );
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    try testing.expectEqual(@as(u32, 0), solved.problems);

    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_ERASE,
        old,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "kernel",
        false,
    );
    try trace.recordNameJob(
        0,
        abi.job_action.multiversion,
        "kernel",
        c.SOLVER_SOLVABLE_NAME | c.SOLVER_MULTIVERSION,
        0,
        abi.request_reason.policy,
        abi.request_trace_no_request,
    );
    try addUserPackageJob(
        &trace,
        1,
        request_ref,
        abi.job_action.install,
        new,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.recordPackageJob(
        2,
        abi.job_action.erase,
        old,
        c.SOLVER_SOLVABLE | c.SOLVER_ERASE,
        0,
        abi.request_reason.installonly_limit,
        abi.request_trace_no_request,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);

    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
        .job_queue_mutation = .installonly_erase_tail,
        .installonly_names = &.{"kernel"},
    });
    owner.destroy();

    jobs.elements[1] = new;
    try testing.expectError(error.JobMismatch, capture.create(
        testing.allocator,
        .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
            .job_queue_mutation = .installonly_erase_tail,
            .installonly_names = &.{"kernel"},
        },
    ));
    jobs.elements[1] = kernel_name;

    var trace_jobs: [3]abi.RequestTraceJob = undefined;
    @memcpy(&trace_jobs, trace.getView().?.jobs.?[0..3]);
    trace_jobs[2].reason = abi.request_reason.user;
    var divergent_trace = trace.getView().?.*;
    divergent_trace.jobs = &trace_jobs;
    try testing.expectError(error.JobMismatch, capture.create(
        testing.allocator,
        .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = &divergent_trace,
            .solve_status = 0,
            .problem_count = 0,
            .job_queue_mutation = .installonly_erase_tail,
            .installonly_names = &.{"kernel"},
        },
    ));
}

test "obsoletes retain multiple priors and permit a shared prior" {
    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const installed = try fixture.addRepository("@System", true);
        const available = try fixture.addRepository("base", false);
        const old_a = try fixture.addPackage(installed, .{
            .name = "old-a",
            .hnum = 11,
        });
        const old_b = try fixture.addPackage(installed, .{
            .name = "old-b",
            .hnum = 12,
        });
        const replacement = try fixture.addPackage(available, .{
            .name = "replacement",
            .evr = "2-1",
        });
        try fixture.addDependency(
            replacement,
            "old-a",
            c.SOLVABLE_OBSOLETES,
        );
        try fixture.addDependency(
            replacement,
            "old-b",
            c.SOLVABLE_OBSOLETES,
        );
        fixture.finish();

        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            replacement,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const request_ref = try trace.addRequest(
            abi.request_kind.install,
            "replacement",
            false,
        );
        try addUserPackageJob(
            &trace,
            0,
            request_ref,
            abi.job_action.install,
            replacement,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        );
        try trace.finalize(queueSlice(&jobs), 0, 0);
        var solved = try solve(fixture.pool, &jobs, true);
        defer solved.deinit();
        try testing.expectEqual(@as(u32, 0), solved.problems);
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
        });
        defer owner.destroy();
        const facts = owner.view();
        try testing.expectEqual(@as(u32, 1), facts.action_count);
        try testing.expectEqual(
            abi.action_kind.obsolete,
            facts.actions.?[0].kind,
        );
        try testing.expectEqual(
            abi.action_reason.obsoletes,
            facts.actions.?[0].reason,
        );
        try testing.expectEqual(@as(u32, 2), facts.actions.?[0].prior_count);
        _ = old_a;
        _ = old_b;
    }

    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const installed = try fixture.addRepository("@System", true);
        const available = try fixture.addRepository("base", false);
        const old = try fixture.addPackage(installed, .{
            .name = "old",
            .hnum = 21,
        });
        const first = try fixture.addPackage(available, .{
            .name = "first",
        });
        const second = try fixture.addPackage(available, .{
            .name = "second",
        });
        try fixture.addDependency(first, "old", c.SOLVABLE_OBSOLETES);
        try fixture.addDependency(second, "old", c.SOLVABLE_OBSOLETES);
        fixture.finish();

        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            first,
        );
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            second,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const first_request = try trace.addRequest(
            abi.request_kind.install,
            "first",
            false,
        );
        const second_request = try trace.addRequest(
            abi.request_kind.install,
            "second",
            false,
        );
        try addUserPackageJob(
            &trace,
            0,
            first_request,
            abi.job_action.install,
            first,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        );
        try addUserPackageJob(
            &trace,
            1,
            second_request,
            abi.job_action.install,
            second,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        );
        try trace.finalize(queueSlice(&jobs), 0, 0);
        var solved = try solve(fixture.pool, &jobs, true);
        defer solved.deinit();
        try testing.expectEqual(@as(u32, 0), solved.problems);
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
        });
        defer owner.destroy();
        const facts = owner.view();
        try testing.expectEqual(@as(u32, 2), facts.action_count);
        try testing.expectEqual(@as(u32, 2), facts.job_count);
        try testing.expectEqualStrings(
            "first",
            bytes(facts.packages.?[
                facts.jobs.?[0].selection_package_ref
            ].identity.name),
        );
        try testing.expectEqualStrings(
            "second",
            bytes(facts.packages.?[
                facts.jobs.?[1].selection_package_ref
            ].identity.name),
        );
        var shared_ref: ?u32 = null;
        for (facts.actions.?[0..facts.action_count]) |action_value| {
            try testing.expectEqual(
                abi.action_kind.obsolete,
                action_value.kind,
            );
            try testing.expectEqual(@as(u32, 1), action_value.prior_count);
            const prior = facts.prior_package_refs.?[
                action_value.prior_offset
            ];
            if (shared_ref) |expected| {
                try testing.expectEqual(expected, prior);
            } else {
                shared_ref = prior;
            }
        }
        try testing.expectEqualStrings(
            "old",
            bytes(facts.packages.?[shared_ref.?].identity.name),
        );
        _ = old;
    }
}

test "highest same-name prior determines replacement kind with extra obsoletes" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const installed = try fixture.addRepository("@System", true);
    const available = try fixture.addRepository("base", false);
    const low = try fixture.addPackage(installed, .{
        .name = "pkg",
        .evr = "1-1",
        .hnum = 31,
    });
    const high = try fixture.addPackage(installed, .{
        .name = "pkg",
        .evr = "3-1",
        .hnum = 32,
    });
    const legacy = try fixture.addPackage(installed, .{
        .name = "legacy",
        .hnum = 33,
    });
    const replacement = try fixture.addPackage(available, .{
        .name = "pkg",
        .evr = "2-1",
    });
    try fixture.addDependency(
        replacement,
        "legacy",
        c.SOLVABLE_OBSOLETES,
    );
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        replacement,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.downgrade,
        "pkg",
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        abi.job_action.downgrade,
        replacement,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    try testing.expectEqual(@as(u32, 0), solved.problems);
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    });
    defer owner.destroy();
    const facts = owner.view();
    try testing.expectEqual(@as(u32, 1), facts.action_count);
    try testing.expectEqual(
        abi.action_kind.downgrade,
        facts.actions.?[0].kind,
    );
    try testing.expectEqual(@as(u32, 3), facts.actions.?[0].prior_count);
    _ = low;
    _ = high;
    _ = legacy;
}

test "weak dependency and clean-dependency erases have exact reasons" {
    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const available = try fixture.addRepository("base", false);
        const app = try fixture.addPackage(available, .{ .name = "app" });
        const weak = try fixture.addPackage(available, .{ .name = "weak" });
        try fixture.addDependency(app, "weak", c.SOLVABLE_RECOMMENDS);
        fixture.finish();

        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            app,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const request_ref = try trace.addRequest(
            abi.request_kind.install,
            "app",
            false,
        );
        try addUserPackageJob(
            &trace,
            0,
            request_ref,
            abi.job_action.install,
            app,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        );
        try trace.finalize(queueSlice(&jobs), 0, 0);
        var solved = try solve(fixture.pool, &jobs, true);
        defer solved.deinit();
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
        });
        defer owner.destroy();
        const facts = owner.view();
        var saw_weak = false;
        for (facts.actions.?[0..facts.action_count]) |action_value| {
            const target = facts.packages.?[action_value.target_package_ref];
            if (std.mem.eql(u8, bytes(target.identity.name), "weak")) {
                try testing.expectEqual(
                    abi.action_reason.weak_dependency,
                    action_value.reason,
                );
                saw_weak = true;
            }
        }
        try testing.expect(saw_weak);
        _ = weak;
    }

    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const installed = try fixture.addRepository("@System", true);
        const dependency = try fixture.addPackage(installed, .{
            .name = "dependency",
            .hnum = 51,
        });
        const app = try fixture.addPackage(installed, .{
            .name = "app",
            .hnum = 52,
        });
        try fixture.addDependency(app, "dependency", c.SOLVABLE_REQUIRES);
        fixture.finish();

        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_USERINSTALLED,
            app,
        );
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_ERASE | c.SOLVER_CLEANDEPS,
            app,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const request_ref = try trace.addRequest(
            abi.request_kind.erase,
            "app",
            false,
        );
        try trace.recordPackageJob(
            0,
            abi.job_action.user_installed,
            app,
            c.SOLVER_SOLVABLE | c.SOLVER_USERINSTALLED,
            0,
            abi.request_reason.policy,
            abi.request_trace_no_request,
        );
        try addUserPackageJob(
            &trace,
            1,
            request_ref,
            abi.job_action.erase,
            app,
            c.SOLVER_SOLVABLE | c.SOLVER_ERASE,
        );
        try trace.finalize(
            queueSlice(&jobs),
            c.SOLVER_CLEANDEPS,
            c.SOLVER_FORCEBEST,
        );
        var solved = try solve(fixture.pool, &jobs, true);
        defer solved.deinit();
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = solved.transaction,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = 0,
            .problem_count = 0,
        });
        defer owner.destroy();
        const facts = owner.view();
        try testing.expectEqual(@as(u32, 1), facts.jobs.?[1].clean_deps);
        var saw_cleanup = false;
        var saw_user_erase = false;
        for (facts.actions.?[0..facts.action_count]) |action_value| {
            const target = facts.packages.?[action_value.target_package_ref];
            if (std.mem.eql(
                u8,
                bytes(target.identity.name),
                "dependency",
            )) {
                try testing.expectEqual(
                    abi.action_reason.cleanup,
                    action_value.reason,
                );
                saw_cleanup = true;
            } else if (std.mem.eql(
                u8,
                bytes(target.identity.name),
                "app",
            )) {
                try testing.expectEqual(
                    abi.action_kind.erase,
                    action_value.kind,
                );
                try testing.expectEqual(
                    abi.action_reason.user,
                    action_value.reason,
                );
                saw_user_erase = true;
            }
        }
        try testing.expect(saw_cleanup);
        try testing.expect(saw_user_erase);
        _ = dependency;
    }
}

test "no-candidate unsatisfied and conflict problems are structured" {
    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        _ = try fixture.addRepository("base", false);
        const missing = c.pool_str2id(fixture.pool, "missing", 1);
        fixture.finish();
        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE_NAME | c.SOLVER_INSTALL,
            missing,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const request_ref = try trace.addRequest(
            abi.request_kind.install,
            "missing",
            false,
        );
        try trace.recordNameJob(
            0,
            abi.job_action.install,
            "missing",
            c.SOLVER_SOLVABLE_NAME | c.SOLVER_INSTALL,
            0,
            abi.request_reason.user,
            request_ref,
        );
        try trace.finalize(queueSlice(&jobs), 0, 0);
        var solved = try solve(fixture.pool, &jobs, false);
        defer solved.deinit();
        try testing.expect(solved.problems > 0);
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = null,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = @intCast(solved.problems),
            .problem_count = solved.problems,
        });
        defer owner.destroy();
        const facts = owner.view();
        try testing.expectEqual(
            abi.resolution_status.problems,
            facts.environment.resolution_status,
        );
        try testing.expectEqual(@as(u32, 0), facts.action_count);
        try testing.expectEqual(@as(u32, 0), facts.selected_package_ref_count);
        var saw_no_candidate = false;
        for (facts.problems.?[0..facts.problem_count]) |problem| {
            if (problem.kind == abi.problem_kind.no_candidate) {
                try testing.expectEqual(@as(u32, 1), problem.has_job_ref);
                try testing.expectEqual(@as(u32, 1), problem.has_capability);
                try testing.expectEqualStrings(
                    "missing",
                    bytes(problem.capability.name),
                );
                saw_no_candidate = true;
            }
        }
        try testing.expect(saw_no_candidate);
    }

    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const available = try fixture.addRepository("base", false);
        const broken = try fixture.addPackage(available, .{
            .name = "broken",
        });
        try fixture.addDependency(
            broken,
            "missing-dependency",
            c.SOLVABLE_REQUIRES,
        );
        fixture.finish();
        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            broken,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const request_ref = try trace.addRequest(
            abi.request_kind.install,
            "broken",
            false,
        );
        try addUserPackageJob(
            &trace,
            0,
            request_ref,
            abi.job_action.install,
            broken,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        );
        try trace.finalize(queueSlice(&jobs), 0, 0);
        var solved = try solve(fixture.pool, &jobs, false);
        defer solved.deinit();
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = null,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = @intCast(solved.problems),
            .problem_count = solved.problems,
        });
        defer owner.destroy();
        var saw_unsatisfied = false;
        for (owner.view().problems.?[0..owner.view().problem_count]) |problem| {
            if (problem.kind == abi.problem_kind.unsatisfied_requirement) {
                try testing.expectEqual(@as(u32, 1), problem.has_package_ref);
                try testing.expectEqual(@as(u32, 1), problem.has_capability);
                try testing.expectEqualStrings(
                    "missing-dependency",
                    bytes(problem.capability.name),
                );
                saw_unsatisfied = true;
            }
        }
        try testing.expect(saw_unsatisfied);
    }

    {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const available = try fixture.addRepository("base", false);
        const first = try fixture.addPackage(available, .{ .name = "first" });
        const second = try fixture.addPackage(available, .{ .name = "second" });
        try fixture.addDependency(first, "second", c.SOLVABLE_CONFLICTS);
        fixture.finish();
        var jobs: c.Queue = undefined;
        c.queue_init(&jobs);
        defer c.queue_free(&jobs);
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            first,
        );
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            second,
        );
        var trace = request_trace.Trace.init(testing.allocator);
        defer trace.deinit();
        const first_request = try trace.addRequest(
            abi.request_kind.install,
            "first",
            false,
        );
        const second_request = try trace.addRequest(
            abi.request_kind.install,
            "second",
            false,
        );
        try addUserPackageJob(
            &trace,
            0,
            first_request,
            abi.job_action.install,
            first,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        );
        try addUserPackageJob(
            &trace,
            1,
            second_request,
            abi.job_action.install,
            second,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        );
        try trace.finalize(queueSlice(&jobs), 0, 0);
        var solved = try solve(fixture.pool, &jobs, false);
        defer solved.deinit();
        const owner = try capture.create(testing.allocator, .{
            .pool = fixture.pool,
            .solver = solved.solver,
            .transaction = null,
            .jobs = &jobs,
            .trace = trace.getView().?,
            .solve_status = @intCast(solved.problems),
            .problem_count = solved.problems,
        });
        defer owner.destroy();
        var saw_conflict = false;
        for (owner.view().problems.?[0..owner.view().problem_count]) |problem| {
            if (problem.kind == abi.problem_kind.conflict and
                problem.has_package_ref != 0)
            {
                saw_conflict = true;
            }
        }
        try testing.expect(saw_conflict);
    }
}

test "accepted solver problems produce only authoritative skipped jobs" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const available = try fixture.addRepository("base", false);
    const good = try fixture.addPackage(available, .{ .name = "good" });
    const broken = try fixture.addPackage(available, .{ .name = "broken" });
    try fixture.addDependency(broken, "missing", c.SOLVABLE_REQUIRES);
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        good,
    );
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        broken,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const good_request = try trace.addRequest(
        abi.request_kind.install,
        "good",
        false,
    );
    const broken_request = try trace.addRequest(
        abi.request_kind.install,
        "broken",
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        good_request,
        abi.job_action.install,
        good,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try addUserPackageJob(
        &trace,
        1,
        broken_request,
        abi.job_action.install,
        broken,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);

    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    try testing.expect(solved.problems > 0);
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = @intCast(solved.problems),
        .problem_count = solved.problems,
        .problems_accepted = true,
    });
    defer owner.destroy();
    const facts = owner.view();
    try testing.expectEqual(
        abi.resolution_status.resolved_with_skips,
        facts.environment.resolution_status,
    );
    try testing.expectEqual(@as(u32, 1), facts.skipped_job_ref_count);
    try testing.expectEqual(@as(u32, 1), facts.skipped_job_refs.?[0]);
    try testing.expect(facts.action_count > 0);
    for (facts.problems.?[0..facts.problem_count]) |problem| {
        try testing.expectEqual(@as(u32, 1), problem.has_job_ref);
        try testing.expectEqual(@as(u32, 1), problem.job_ref);
    }
}

test "thousands of selected actions capture without quadratic deduplication" {
    const package_count = 2048;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const available = try fixture.addRepository("base", false);
    const package_ids = try testing.allocator.alloc(c.Id, package_count);
    defer testing.allocator.free(package_ids);
    for (package_ids, 0..) |*package_id, index| {
        var name_buffer: [64]u8 = undefined;
        const name = try std.fmt.bufPrintZ(
            &name_buffer,
            "scale-package-{d}",
            .{index},
        );
        package_id.* = try fixture.addPackage(available, .{ .name = name });
    }
    fixture.finish();

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    for (package_ids, 0..) |package_id, index| {
        c.queue_push2(
            &jobs,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            package_id,
        );
        try trace.recordPackageJob(
            @intCast(index),
            abi.job_action.install,
            package_id,
            c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
            0,
            abi.request_reason.policy,
            abi.request_trace_no_request,
        );
    }
    try trace.finalize(queueSlice(&jobs), 0, 0);

    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    });
    defer owner.destroy();

    try testing.expectEqual(
        @as(u32, package_count),
        owner.view().package_count,
    );
    try testing.expectEqual(
        @as(u32, package_count),
        owner.view().selected_package_ref_count,
    );
    try testing.expectEqual(
        @as(u32, package_count),
        owner.view().action_count,
    );
}

fn captureNameOrder(reverse: bool) ![]u8 {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const installed = try fixture.addRepository("@System", true);
    const available = try fixture.addRepository("base", false);
    _ = try fixture.addPackage(installed, .{
        .name = "installed",
        .hnum = 61,
    });
    const first = if (reverse) "zeta" else "alpha";
    const second = if (reverse) "alpha" else "zeta";
    const first_id = try fixture.addPackage(
        available,
        .{ .name = first, .location = "packages/first.rpm" },
    );
    const second_id = try fixture.addPackage(
        available,
        .{ .name = second, .location = "packages/second.rpm" },
    );
    fixture.finish();
    try fixture.hide(&.{ first_id, second_id });

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    try trace.finalize(&.{}, 0, 0);
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    const owner = try capture.create(testing.allocator, .{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    });
    defer owner.destroy();
    var output = std.ArrayList(u8).empty;
    defer output.deinit(testing.allocator);
    for (owner.view().packages.?[0..owner.view().package_count]) |package| {
        if (output.items.len != 0)
            try output.append(testing.allocator, ',');
        try output.appendSlice(
            testing.allocator,
            bytes(package.identity.name),
        );
    }
    return output.toOwnedSlice(testing.allocator);
}

test "package order is independent of libsolv insertion permutations" {
    const forward = try captureNameOrder(false);
    defer testing.allocator.free(forward);
    const reverse = try captureNameOrder(true);
    defer testing.allocator.free(reverse);
    try testing.expectEqualStrings(forward, reverse);
    try testing.expectEqualStrings("installed,alpha,zeta", forward);
}

test "ambiguous package mappings and every allocation failure fail cleanly" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const available = try fixture.addRepository("base", false);
    const app = try fixture.addPackage(available, .{ .name = "app" });
    const duplicate_a = try fixture.addPackage(available, .{
        .name = "duplicate",
        .location = "packages/duplicate.rpm",
    });
    const duplicate_b = try fixture.addPackage(available, .{
        .name = "duplicate",
        .location = "packages/duplicate.rpm",
    });
    fixture.finish();
    try fixture.hide(&.{ duplicate_a, duplicate_b });

    var jobs: c.Queue = undefined;
    c.queue_init(&jobs);
    defer c.queue_free(&jobs);
    c.queue_push2(
        &jobs,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        app,
    );
    var trace = request_trace.Trace.init(testing.allocator);
    defer trace.deinit();
    const request_ref = try trace.addRequest(
        abi.request_kind.install,
        "app",
        false,
    );
    try addUserPackageJob(
        &trace,
        0,
        request_ref,
        abi.job_action.install,
        app,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
    );
    try trace.finalize(queueSlice(&jobs), 0, 0);
    var solved = try solve(fixture.pool, &jobs, true);
    defer solved.deinit();
    const input = capture.Input{
        .pool = fixture.pool,
        .solver = solved.solver,
        .transaction = solved.transaction,
        .jobs = &jobs,
        .trace = trace.getView().?,
        .solve_status = 0,
        .problem_count = 0,
    };
    try testing.expectError(
        error.AmbiguousPackageMapping,
        capture.create(testing.allocator, input),
    );

    c.map_set(fixture.considered.?, duplicate_b);
    try testing.checkAllAllocationFailures(
        testing.allocator,
        allocationFailureCase,
        .{input},
    );
}

fn allocationFailureCase(
    allocator: std.mem.Allocator,
    input: capture.Input,
) !void {
    const owner = try capture.create(allocator, input);
    owner.destroy();
}
