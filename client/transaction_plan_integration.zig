const std = @import("std");
const Allocator = std.mem.Allocator;

const integration_options = @import("transaction_plan_integration_options");
const abi = @import("transaction_plan_capture_abi");
const capture_adapter = @import("transaction_plan_capture");
const error_codes = @import("tdnf_error");
const native_capture = @import("transaction_plan_native");
const repository_capture = @import("transaction_plan_repository");
const repository_metadata = @import("repository_metadata");
const rpm_header = @import("rpm_header");
const transaction_plan = @import("transaction_plan");

const c = repository_metadata.solv_bridge.libsolv;
const metadata_model = repository_metadata.metadata_model;
const solver_live = repository_metadata.solver_live;
const solver_model = repository_metadata.solver_model;
const solver_native = repository_metadata.solver_native;
const solver_result = repository_metadata.solver_result;

const IntegrationError = native_capture.CaptureError ||
    repository_capture.CaptureError ||
    transaction_plan.InitError ||
    Allocator.Error ||
    error{
        AmbiguousRepository,
        InvalidEnvironment,
        InvalidAbi,
        InvalidPackageMapping,
        InvalidPolicyTrace,
        InvalidRepository,
        RepositoryIntegrityMismatch,
        RpmdbIdentityFailed,
        UnsupportedResult,
    };

const rpmdb_package_set_domain = "tdnf.rpmdb-package-set/v1";
const default_repository_cost: u32 = 1000;
const visible_snapshot_identity_domain =
    "tdnf.repository-visible-snapshot/v2";

const RpmdbIterator = opaque {};

const RepoMetadata = extern struct {
    cache_dir: ?[*:0]u8 = null,
    repository: ?[*:0]u8 = null,
    repomd: ?[*:0]u8 = null,
    primary: ?[*:0]u8 = null,
    filelists: ?[*:0]u8 = null,
    updateinfo: ?[*:0]u8 = null,
    other: ?[*:0]u8 = null,
};

const SolvRepoInfo = extern struct {
    repository: ?*c.Repo = null,
    cookie: [32]u8 = [_]u8{0} ** 32,
    cookie_set: c_int = 0,
    cache_dir: ?[*:0]u8 = null,
};

const InstalledSolverPair = struct {
    live: c.Id,
    rebuilt: c.Id,
};

const file_dependency_keys = [_]c.Id{
    c.SOLVABLE_REQUIRES,
    c.SOLVABLE_RECOMMENDS,
    c.SOLVABLE_SUGGESTS,
    c.SOLVABLE_SUPPLEMENTS,
    c.SOLVABLE_ENHANCES,
    c.SOLVABLE_CONFLICTS,
    c.SOLVABLE_OBSOLETES,
};

const FileDependency = struct {
    path: []const u8,
    key: c.Id,
};

extern fn tdnf_rpmdb_string_free(value: ?[*:0]u8) void;
extern fn TDNFTransactionPlanLoadSolvRepo(
    repository: ?*c.Repo,
    repomd_path: ?[*:0]const u8,
    primary_path: ?[*:0]const u8,
    filelists_path: ?[*:0]const u8,
    updateinfo_path: ?[*:0]const u8,
    other_path: ?[*:0]const u8,
    cookie_sha256: ?[*]u8,
) u32;
extern fn TDNFTransactionPlanBindSolvCookie(
    raw_cookie: ?*const [32]u8,
    include_filelists: u32,
    include_updateinfo: u32,
    include_other: u32,
    output: ?*[32]u8,
) c_int;
extern fn TDNFTransactionPlanRpmdbSnapshotOpenConfig(
    config: ?*const anyopaque,
    cookie: ?*?[*:0]u8,
) ?*RpmdbIterator;
extern fn tdnf_rpmdb_iter_close(iterator: ?*RpmdbIterator) void;
extern fn tdnf_rpmdb_iter_next_header_blob_hnum(
    iterator: ?*RpmdbIterator,
    hnum: ?*u32,
    blob: ?*?[*]const u8,
    length: ?*usize,
) c_int;

pub const Input = struct {
    pool: *c.Pool,
    /// The native solve that produced the transaction tdnf is about to run.
    native_solve: *const repository_metadata.RetainedSolve,
    trace: *const abi.RequestTraceView,
    problems_accepted: bool,
    unresolved_count: u32,
    terminal_problem_kind: ?transaction_plan.ProblemKind = null,
    repositories: []const abi.IntegrationRepository,
    environment: *const abi.IntegrationEnvironment,
};

pub const State = struct {
    allocator: Allocator,
    enabled: bool = false,
    plan: ?*transaction_plan.Plan = null,
    pending_plan: ?*transaction_plan.Plan = null,
    repository_records: std.ArrayList(RepositoryLoadRecord) = .empty,
    pending_repository_records: std.ArrayList(RepositoryLoadRecord) = .empty,
    repository_refresh_active: bool = false,
    repository_refresh_owner: ?*anyopaque = null,
    fail_next_repository_record: bool = false,
    fail_next_capture: bool = false,
    fail_next_capture_integrity: bool = false,

    pub fn create(allocator: Allocator) Allocator.Error!*State {
        const self = try allocator.create(State);
        self.* = .{ .allocator = allocator };
        return self;
    }

    pub fn clear(self: *State) void {
        if (self.plan) |plan| plan.destroy();
        if (self.pending_plan) |plan| plan.destroy();
        self.plan = null;
        self.pending_plan = null;
    }

    pub fn destroy(self: *State) void {
        const allocator = self.allocator;
        self.clear();
        self.repository_records.deinit(allocator);
        self.pending_repository_records.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn setEnabled(self: *State, enabled: bool) void {
        self.clear();
        self.enabled = enabled;
    }

    pub fn publish(self: *State) error{NoPendingPlan}!void {
        if (!self.enabled) return;
        const pending = self.pending_plan orelse return error.NoPendingPlan;
        if (self.plan) |plan| plan.destroy();
        self.plan = pending;
        self.pending_plan = null;
    }

    pub fn hasPendingProblem(self: *const State) bool {
        const pending = self.pending_plan orelse return false;
        return pending.model().environment.resolution_status == .problems;
    }

    pub fn publishProblem(self: *State) bool {
        if (!self.enabled or !self.hasPendingProblem()) return false;
        if (self.plan) |plan| plan.destroy();
        self.plan = self.pending_plan;
        self.pending_plan = null;
        return true;
    }

    pub fn model(self: *const State) ?*const transaction_plan.Data {
        return if (self.plan) |plan| plan.model() else null;
    }

    pub fn canonicalJsonAlloc(
        self: *const State,
        allocator: Allocator,
    ) (transaction_plan.CanonicalError || error{NoPlan})![]u8 {
        const plan = self.plan orelse return error.NoPlan;
        return plan.canonicalJsonAlloc(allocator);
    }

    pub fn digestHex(
        self: *const State,
        allocator: Allocator,
    ) (transaction_plan.CanonicalError || error{NoPlan})![64]u8 {
        const plan = self.plan orelse return error.NoPlan;
        return plan.digest(allocator);
    }

    pub fn recordRepository(
        self: *State,
        repository: *anyopaque,
        cookie_sha256: [32]u8,
        options: repository_metadata.available_repository_loader.CacheOptions,
    ) Allocator.Error!void {
        return self.replaceRepositoryRecord(
            null,
            repository,
            cookie_sha256,
            options,
        );
    }

    fn replaceRepositoryRecord(
        self: *State,
        prior_repository: ?*anyopaque,
        repository: *anyopaque,
        cookie_sha256: [32]u8,
        options: repository_metadata.available_repository_loader.CacheOptions,
    ) Allocator.Error!void {
        if (self.fail_next_repository_record) {
            self.fail_next_repository_record = false;
            return error.OutOfMemory;
        }
        const records = if (self.repository_refresh_active)
            &self.pending_repository_records
        else
            &self.repository_records;
        for (records.items) |*record| {
            if (record.repository == prior_repository or
                record.repository == repository)
            {
                record.repository = repository;
                record.cookie_sha256 = cookie_sha256;
                record.options = options;
                return;
            }
        }
        try records.append(self.allocator, .{
            .repository = repository,
            .cookie_sha256 = cookie_sha256,
            .options = options,
        });
    }

    fn rebindRepository(
        self: *State,
        prior_repository: ?*anyopaque,
        repository: *anyopaque,
    ) void {
        const prior = prior_repository orelse return;
        for (self.repository_records.items) |*record| {
            if (record.repository == prior) record.repository = repository;
        }
        for (self.pending_repository_records.items) |*record| {
            if (record.repository == prior) record.repository = repository;
        }
    }

    pub fn beginRepositoryRefresh(
        self: *State,
        owner: *anyopaque,
    ) error{RefreshAlreadyActive}!void {
        if (self.repository_refresh_active)
            return error.RefreshAlreadyActive;
        self.pending_repository_records.clearRetainingCapacity();
        self.repository_refresh_active = true;
        self.repository_refresh_owner = owner;
    }

    pub fn commitRepositoryRefresh(self: *State, owner: *anyopaque) void {
        std.debug.assert(
            self.repository_refresh_active and
                self.repository_refresh_owner == owner,
        );
        std.mem.swap(
            std.ArrayList(RepositoryLoadRecord),
            &self.repository_records,
            &self.pending_repository_records,
        );
        self.pending_repository_records.clearRetainingCapacity();
        self.repository_refresh_active = false;
        self.repository_refresh_owner = null;
    }

    pub fn rollbackRepositoryRefresh(self: *State, owner: *anyopaque) void {
        if (!self.repository_refresh_active) return;
        std.debug.assert(self.repository_refresh_owner == owner);
        self.pending_repository_records.clearRetainingCapacity();
        self.repository_refresh_active = false;
        self.repository_refresh_owner = null;
    }

    fn copyRepositoryRecord(
        self: *State,
        prior_repository: *anyopaque,
        repository: *anyopaque,
    ) Allocator.Error!void {
        if (!self.repository_refresh_active) return;
        for (self.repository_records.items) |record| {
            if (record.repository != prior_repository) continue;
            try self.pending_repository_records.append(self.allocator, .{
                .repository = repository,
                .cookie_sha256 = record.cookie_sha256,
                .options = record.options,
            });
            return;
        }
    }

    fn repositoryRecord(
        self: *const State,
        repository: *anyopaque,
    ) ?*const RepositoryLoadRecord {
        const records = if (self.repository_refresh_active)
            self.pending_repository_records.items
        else
            self.repository_records.items;
        for (records) |*record| {
            if (record.repository == repository) return record;
        }
        return null;
    }

    fn repositoryRecordCount(
        self: *const State,
        repository: *anyopaque,
    ) u32 {
        const records = if (self.repository_refresh_active)
            self.pending_repository_records.items
        else
            self.repository_records.items;
        var count: u32 = 0;
        for (records) |record| {
            if (record.repository == repository) count += 1;
        }
        return count;
    }
};

const RepositoryLoadRecord = struct {
    repository: *anyopaque,
    cookie_sha256: [32]u8,
    options: repository_metadata.available_repository_loader.CacheOptions,
};

const LoadedRepository = struct {
    has_metadata: bool = false,
    cookie_sha256: [32]u8 = [_]u8{0} ** 32,
    options: repository_metadata.available_repository_loader.CacheOptions = .{},
};

const RepositoryStage = struct {
    pool: *c.Pool,
    prior: ?*c.Repo,
    repository: *c.Repo,
    created: bool,
    original_appdata: ?*anyopaque,
    original_disabled: c_int,
    original_priority: c_int,
    original_subpriority: c_int,
    prior_considered: ?*c.Map = null,
    staged_considered: ?*c.Map = null,
    committed: bool = false,

    fn stageConsidered(
        self: *RepositoryStage,
        force_map: bool,
    ) Allocator.Error!void {
        const prior = if (self.pool.considered) |raw|
            @as(*c.Map, @ptrCast(raw))
        else
            null;
        if (prior == null and !force_map) return;

        const staged = try std.heap.c_allocator.create(c.Map);
        if (prior) |value| {
            c.map_init_clone(staged, value);
            c.map_grow(staged, self.pool.nsolvables);
        } else {
            c.map_init(staged, self.pool.nsolvables);
            c.map_setall(staged);
        }
        var solvid = self.repository.start;
        while (solvid < self.repository.end) : (solvid += 1) {
            const raw = c.pool_id2solvable(self.pool, solvid) orelse
                continue;
            const solvable: *c.Solvable = @ptrCast(raw);
            if (solvable.repo == self.repository)
                c.map_set(staged, solvid);
        }
        self.prior_considered = prior;
        self.staged_considered = staged;
        self.pool.considered = staged;
    }

    fn rollback(self: *RepositoryStage) void {
        if (self.committed) return;
        if (self.staged_considered) |staged| {
            self.pool.considered = self.prior_considered;
            freeConsidered(staged);
        }
        if (self.created) {
            self.repository.appdata = null;
            c.repo_free(self.repository, 1);
        } else {
            c.repo_empty(self.repository, 1);
            self.repository.appdata = self.original_appdata;
            self.repository.disabled = self.original_disabled;
            self.repository.priority = self.original_priority;
            self.repository.subpriority = self.original_subpriority;
        }
        rebuildPoolIndexes(self.pool);
    }

    fn commit(
        self: *RepositoryStage,
        input: *const abi.RepositoryInitInput,
        state: ?*State,
        loaded_repo: ?*?*anyopaque,
    ) void {
        const replacing = if (self.prior) |prior|
            prior != self.repository
        else
            false;
        if (replacing) {
            const prior = self.prior.?;
            if (self.pool.considered) |raw_map| {
                const considered: *c.Map = @ptrCast(raw_map);
                var solvid = prior.start;
                while (solvid < prior.end) : (solvid += 1) {
                    const raw = c.pool_id2solvable(
                        self.pool,
                        solvid,
                    ) orelse continue;
                    const solvable: *c.Solvable = @ptrCast(raw);
                    if (solvable.repo == prior)
                        c.map_clr(considered, solvid);
                }
            }
        }

        self.repository.appdata = input.repo_data;
        if (liveRepositorySlot(input)) |slot|
            slot.* = self.repository;
        if (loaded_repo) |output|
            output.* = @ptrCast(self.repository);
        if (state) |value| {
            value.rebindRepository(
                if (replacing) @ptrCast(self.prior.?) else null,
                @ptrCast(self.repository),
            );
        }
        if (replacing) {
            const prior = self.prior.?;
            prior.appdata = null;
            c.repo_free(prior, 1);
        }
        if (self.staged_considered != null) {
            if (self.prior_considered) |prior| freeConsidered(prior);
        }
        rebuildPoolIndexes(self.pool);
        self.committed = true;
    }
};

fn initRepository(
    raw_input: ?*const abi.RepositoryInitInput,
    loaded_repo: ?*?*anyopaque,
) callconv(.c) u32 {
    if (loaded_repo) |output| output.* = null;
    const input = raw_input orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const callbacks = input.callbacks orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (input.has_metadata > 1 or input.apply_snapshot > 1 or
        input.reuse_empty_repository > 1 or
        input.priority == std.math.minInt(i32) or
        callbacks.free_memory == null or callbacks.make_dirs == null or
        callbacks.get_cache_path == null or callbacks.get_repo_md == null or
        callbacks.free_repo_metadata == null or
        callbacks.calculate_cookie == null or
        callbacks.use_metadata_cache == null or
        callbacks.create_metadata_cache == null or
        callbacks.init_from_metadata == null or
        callbacks.read_rpms_from_directory == null or
        callbacks.apply_snapshot == null)
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }
    const pool: *c.Pool = @ptrCast(@alignCast(input.pool orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    const repository_id = input.repository_id orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (repository_id[0] == 0 or input.repo_data == null or
        input.tdnf_handle == null or input.sack == null)
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }

    const prior = findLoadedRepository(input, pool) catch
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (loaded_repo) |output| {
        output.* = if (prior) |repository|
            @ptrCast(repository)
        else
            null;
    }
    if (consumeReloadFailure(input, 3))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    const reuse = input.reuse_empty_repository != 0 and prior != null;
    if (reuse and prior.?.nsolvables != 0)
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const repository: *c.Repo = if (reuse)
        prior.?
    else
        @ptrCast(c.repo_create(pool, repository_id) orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER);
    var stage = RepositoryStage{
        .pool = pool,
        .prior = prior,
        .repository = repository,
        .created = !reuse,
        .original_appdata = repository.appdata,
        .original_disabled = repository.disabled,
        .original_priority = repository.priority,
        .original_subpriority = repository.subpriority,
    };
    defer stage.rollback();

    repository.priority = -input.priority;
    if (prior) |value| {
        repository.disabled = value.disabled;
        repository.subpriority = value.subpriority;
    }
    var repo_info = SolvRepoInfo{ .repository = repository };
    repository.appdata = @ptrCast(&repo_info);
    var loaded = LoadedRepository{};
    var result = loadRepository(input, repository, &repo_info, &loaded);
    if (result != 0) return result;
    if (consumeReloadFailure(input, 6))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    stage.stageConsidered(
        input.apply_snapshot != 0 and input.snapshot_file != null,
    ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    c.pool_createwhatprovides(pool);
    if (input.apply_snapshot != 0 and input.snapshot_file != null) {
        result = callbacks.apply_snapshot.?(
            input.tdnf_handle,
            input.repo_data,
            input.sack,
            @ptrCast(repository),
        );
        if (result != 0) return result;
        c.pool_createwhatprovides(pool);
    }
    if (!validateStagedRepository(
        input,
        pool,
        repository,
        @ptrCast(&repo_info),
    )) return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (consumeReloadFailure(input, 7))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    const state = repositoryState(input);
    if (loaded.has_metadata) {
        if (state) |value| {
            if (value.enabled) {
                value.replaceRepositoryRecord(
                    if (prior) |repository_value|
                        @ptrCast(repository_value)
                    else
                        null,
                    @ptrCast(repository),
                    loaded.cookie_sha256,
                    loaded.options,
                ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
            }
        }
    }
    stage.commit(input, state, loaded_repo);
    return 0;
}

fn loadRepository(
    input: *const abi.RepositoryInitInput,
    repository: *c.Repo,
    repo_info: *SolvRepoInfo,
    loaded: *LoadedRepository,
) u32 {
    var cache_dir: ?[*:0]u8 = null;
    var metadata: ?*RepoMetadata = null;
    const callbacks = input.callbacks orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const allocator = std.heap.c_allocator;
    var result = callbacks.get_cache_path.?(
        input.tdnf_handle,
        input.repo_data,
        null,
        null,
        &cache_dir,
    );
    if (result != 0) return result;
    const cache_path = cache_dir orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    defer callbacks.free_memory.?(@ptrCast(cache_path));
    const repo_data_dir = std.fmt.allocPrintSentinel(
        allocator,
        "{s}/repodata",
        .{std.mem.span(cache_path)},
        0,
    ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(repo_data_dir);

    if (input.has_metadata != 0) {
        result = callbacks.make_dirs.?(repo_data_dir.ptr);
        if (result != 0 and
            result != error_codes.fromErrno(.EXIST))
        {
            return result;
        }
        result = callbacks.get_repo_md.?(
            input.tdnf_handle,
            input.repo_data,
            repo_data_dir.ptr,
            @ptrCast(&metadata),
        );
        if (result != 0) return result;
    }
    defer callbacks.free_repo_metadata.?(
        if (metadata) |value| @ptrCast(value) else null,
    );

    repo_info.cache_dir = cache_path;
    defer repo_info.cache_dir = null;
    if (metadata) |repo_metadata| {
        loaded.has_metadata = true;
        loaded.options = .{
            .include_filelists = repo_metadata.filelists != null,
            .include_updateinfo = repo_metadata.updateinfo != null,
            .include_other = repo_metadata.other != null,
        };
        result = callbacks.calculate_cookie.?(
            repo_metadata.repomd,
            repo_info.cookie[0..].ptr,
        );
        if (result != 0) return result;
        const state = repositoryState(input);
        const capture_enabled = if (state) |value| value.enabled else false;
        if (capture_enabled and TDNFTransactionPlanBindSolvCookie(
            &repo_info.cookie,
            @intFromBool(loaded.options.include_filelists),
            @intFromBool(loaded.options.include_updateinfo),
            @intFromBool(loaded.options.include_other),
            &repo_info.cookie,
        ) != 0) return error_codes.ERROR_TDNF_INVALID_PARAMETER;
        repo_info.cookie_set = 1;

        var used_cache: c_int = 0;
        result = callbacks.use_metadata_cache.?(
            input.sack,
            @ptrCast(repo_info),
            &used_cache,
        );
        if (result != 0) return result;
        if (used_cache == 0) {
            if (capture_enabled) {
                var plan_cookie = [_]u8{0} ** 32;
                result = TDNFTransactionPlanLoadSolvRepo(
                    repository,
                    repo_metadata.repomd,
                    repo_metadata.primary,
                    repo_metadata.filelists,
                    repo_metadata.updateinfo,
                    repo_metadata.other,
                    plan_cookie[0..].ptr,
                );
                if (result != 0) return result;
                repo_info.cookie = plan_cookie;
            } else {
                result = callbacks.init_from_metadata.?(
                    @ptrCast(repository),
                    input.repository_id,
                    @ptrCast(repo_metadata),
                );
                if (result != 0) return result;
            }
            result = callbacks.create_metadata_cache.?(
                input.sack,
                @ptrCast(repo_info),
            );
            if (result != 0) return result;
        }
        loaded.cookie_sha256 = repo_info.cookie;
        return 0;
    }

    const base_url = input.base_url orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    return callbacks.read_rpms_from_directory.?(
        @ptrCast(repository),
        base_url,
    );
}

fn findLoadedRepository(
    input: *const abi.RepositoryInitInput,
    pool: *c.Pool,
) error{InvalidRepository}!?*c.Repo {
    if (pool.nrepos <= 0 or pool.repos == null)
        return error.InvalidRepository;
    const live = if (liveRepositorySlot(input)) |slot| slot.* else null;
    const command_line: ?*c.Repo =
        if (input.command_line_repository) |raw|
            @ptrCast(@alignCast(raw))
        else
            null;
    var match: ?*c.Repo = null;
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const raw = pool.repos[@intCast(index)] orelse continue;
        const candidate: *c.Repo = @ptrCast(raw);
        if (candidate == pool.installed or candidate == command_line)
            continue;
        if (candidate != live and candidate.appdata != input.repo_data)
            continue;
        if (match != null) return error.InvalidRepository;
        match = candidate;
    }
    return match;
}

fn validateStagedRepository(
    input: *const abi.RepositoryInitInput,
    pool: *c.Pool,
    repository: *c.Repo,
    expected_appdata: *anyopaque,
) bool {
    if (repository.pool != pool or repository.appdata != expected_appdata or
        repository.repoid <= 0 or repository.repoid >= pool.nrepos or
        pool.repos[@intCast(repository.repoid)] != repository or
        pool.whatprovides == null)
    {
        return false;
    }
    const name = repository.name orelse return false;
    if (!std.mem.eql(
        u8,
        std.mem.span(name),
        std.mem.span(input.repository_id orelse return false),
    )) return false;
    if (pool.considered) |raw_map| {
        const considered: *c.Map = @ptrCast(raw_map);
        if (considered.size < 0 or
            @as(i64, considered.size) * 8 < pool.nsolvables)
        {
            return false;
        }
    }

    var count: c_int = 0;
    var solvid: c.Id = 1;
    while (solvid < pool.nsolvables) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse return false;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo != repository) continue;
        if (solvid < repository.start or solvid >= repository.end)
            return false;
        count += 1;
    }
    return count == repository.nsolvables;
}

fn liveRepositorySlot(
    input: *const abi.RepositoryInitInput,
) ?*?*c.Repo {
    const raw = input.live_repository_slot orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn repositoryState(
    input: *const abi.RepositoryInitInput,
) ?*State {
    const slot = input.state_slot orelse return null;
    const raw = slot.* orelse return null;
    const state: *State = @ptrCast(@alignCast(raw));
    const refresh = input.refresh_input orelse return null;
    const sack = input.sack orelse return null;
    if (refresh.tdnf_handle != input.tdnf_handle) return null;
    if (sack == refresh.live_sack) return state;
    if (state.repository_refresh_active and
        state.repository_refresh_owner == sack)
    {
        return state;
    }
    return null;
}

fn consumeReloadFailure(
    input: *const abi.RepositoryInitInput,
    stage: u32,
) bool {
    const value = input.failure_stage orelse return false;
    if (value.* != stage) return false;
    value.* = 0;
    return true;
}

fn freeConsidered(considered: *c.Map) void {
    c.map_free(considered);
    std.heap.c_allocator.destroy(considered);
}

fn rebuildPoolIndexes(pool: *c.Pool) void {
    pool.pos = std.mem.zeroes(@TypeOf(pool.pos));
    c.pool_addfileprovides(pool);
    c.pool_createwhatprovides(pool);
}

const SolvSack = extern struct {
    pool: ?*c.Pool,
    command_package_count: u32,
    cache_dir: ?[*:0]u8,
    root_dir: ?[*:0]u8,
};

const NativeRepoInput = extern struct {
    id: ?[*:0]const u8 = null,
    cache_dir: ?[*:0]const u8 = null,
    snapshot_file: ?[*:0]const u8 = null,
};

const RefreshEntry = struct {
    data: *anyopaque,
    view: abi.RepositoryRefreshView,
};

const SolvableVisibility = struct {
    destination: c.Id,
    visible: bool,
};

extern fn SolvInitSack(
    sack: *?*SolvSack,
    cache_dir: ?[*:0]const u8,
    root_dir: ?[*:0]const u8,
    architecture: ?[*:0]const u8,
) u32;
extern fn SolvFreeSack(sack: ?*SolvSack) void;
extern fn SolvReadInstalledRpms(
    repository: ?*c.Repo,
    cache_dir: ?[*:0]const u8,
    rpm_config: ?*const anyopaque,
) u32;
extern fn TDNFGetCachePath(
    handle: ?*anyopaque,
    repository: ?*anyopaque,
    subdirectory: ?[*:0]const u8,
    filename: ?[*:0]const u8,
    path: *?[*:0]u8,
) u32;
extern fn TDNFShouldSyncMetadata(
    repository_data_dir: ?[*:0]const u8,
    metadata_expire: c_long,
    should_sync: *c_int,
) u32;
extern fn TDNFRepoRemoveCache(
    handle: ?*anyopaque,
    repository: ?*anyopaque,
) u32;
extern fn TDNFRemoveSolvCache(
    handle: ?*anyopaque,
    repository: ?*anyopaque,
) u32;
extern fn TDNFApplySnapshot(
    handle: ?*anyopaque,
    repository_data: ?*anyopaque,
    sack: ?*anyopaque,
    repository: ?*anyopaque,
) u32;
extern fn TDNFFreeMemory(memory: ?*anyopaque) void;
extern fn repo_write(repository: *c.Repo, stream: *c.FILE) c_int;
extern fn repo_add_solv(
    repository: *c.Repo,
    stream: *c.FILE,
    flags: c_int,
) c_int;
extern fn open_memstream(
    buffer: *?[*]u8,
    length: *usize,
) ?*c.FILE;
extern fn fmemopen(
    buffer: ?*anyopaque,
    length: usize,
    mode: [*:0]const u8,
) ?*c.FILE;
extern fn TDNFBuildRefreshInput(
    handle: ?*anyopaque,
    sack: ?*anyopaque,
    input: *abi.RepositoryRefreshInput,
) u32;
extern fn TDNFRemoveLastRefreshMarker(
    handle: ?*anyopaque,
    repository: ?*anyopaque,
) u32;
extern fn log_console(level: c_int, format: [*:0]const u8, ...) void;
/// Mirrors `TDNF_ID_LIST` in `common/structs.h`, the container `client/` uses
/// in place of libsolv's `Queue` for package selections and solver jobs.
/// Declared here rather than imported through the libsolv C-import binding:
/// this module already reaches C through explicit `extern` declarations, and
/// that binding is deliberately confined to libsolv's own headers.
const IdList = extern struct {
    pnElements: ?[*]i32,
    dwCount: u32,
    dwCapacity: u32,
};

extern fn TDNFIdListInit(list: *IdList) void;
extern fn TDNFIdListFree(list: *IdList) void;

extern fn TDNFPkgsToExclude(
    handle: ?*anyopaque,
    exclude_count: *u32,
    excludes: *?[*]?[*:0]u8,
) u32;
extern fn TDNFAddGoal(
    handle: ?*anyopaque,
    alter_type: c_int,
    jobs: *IdList,
    package: c.Id,
    exclude_count: u32,
    excludes: ?[*]?[*:0]u8,
) u32;
extern fn TDNFSolv(
    handle: ?*anyopaque,
    jobs: *IdList,
    excludes: ?[*]?[*:0]u8,
    exclude_count: u32,
    allow_erasing: c_int,
    auto_erase: c_int,
    reinstall: c_int,
    unresolved_count: c_int,
    solved_info: *?*anyopaque,
) u32;
extern fn TDNFAddUserInstall(
    handle: ?*anyopaque,
    install: *const IdList,
    solved_info: ?*anyopaque,
) u32;
extern fn TDNFFreeStringArray(values: ?[*]?[*:0]u8) void;
extern fn TDNFReadFileToStringArray(
    path: ?[*:0]const u8,
    values: *?[*]?[*:0]u8,
) u32;
extern fn TDNFNativeQueryBuildSingleRepoInput(
    handle: ?*anyopaque,
    repository_data: ?*anyopaque,
    repository: *NativeRepoInput,
) u32;
extern fn TDNFNativeQueryFreeRepoInputs(
    repositories: ?*NativeRepoInput,
    repository_count: u32,
) void;
extern fn TDNFRepoMdNativeFindNameEvrMatches(
    repositories: ?*const NativeRepoInput,
    repository_count: u32,
    name_evr: ?[*:0]const u8,
    matches: *?[*]?[*:0]u8,
    match_count: *u32,
) u32;
extern fn TDNFNativeQueryResolvePackageRefArrayToQueue(
    sack: ?*anyopaque,
    package_refs: ?[*]?[*:0]u8,
    package_count: u32,
    installed_only: c_int,
    queue: *IdList,
) u32;

fn refreshState(input: *const abi.RepositoryRefreshInput) ?*State {
    const slot = input.state_slot orelse return null;
    const raw = slot.* orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn describeRepository(
    input: *const abi.RepositoryRefreshInput,
    data: *anyopaque,
) abi.RepositoryRefreshView {
    var view = abi.RepositoryRefreshView{};
    input.describe_repository.?(data, &view);
    return view;
}

fn refreshEntryLessThan(
    _: void,
    left: RefreshEntry,
    right: RefreshEntry,
) bool {
    return left.view.priority < right.view.priority;
}

fn isCommandLineRepositoryId(raw_id: ?[*:0]const u8) bool {
    const id = raw_id orelse return false;
    return std.mem.eql(u8, std.mem.span(id), "@cmdline");
}

fn collectRefreshEntries(
    input: *const abi.RepositoryRefreshInput,
    allocator: Allocator,
) Allocator.Error![]RefreshEntry {
    var count: usize = 0;
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(input, data);
        if (view.enabled != 0 and !isCommandLineRepositoryId(view.id))
            count += 1;
        raw = view.next;
    }
    const entries = try allocator.alloc(RefreshEntry, count);
    var index: usize = 0;
    raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(input, data);
        if (view.enabled != 0 and !isCommandLineRepositoryId(view.id)) {
            entries[index] = .{ .data = data, .view = view };
            index += 1;
        }
        raw = view.next;
    }
    std.mem.sort(RefreshEntry, entries, {}, refreshEntryLessThan);
    return entries;
}

fn repositoryIsManaged(
    input: *const abi.RepositoryRefreshInput,
    repository: *c.Repo,
) bool {
    if (input.command_line_repository_slot) |slot| {
        if (slot.* == @as(*anyopaque, @ptrCast(repository))) return true;
    }
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(input, data);
        if (view.live_repository == @as(*anyopaque, @ptrCast(repository)) or
            repository.appdata == data)
        {
            return true;
        }
        raw = view.next;
    }
    return false;
}

fn preparePoolRefresh(
    input: *const abi.RepositoryRefreshInput,
    sack: *SolvSack,
) u32 {
    const pool = sack.pool orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    c.pool_freewhatprovides(pool);
    if (pool.considered) |raw_considered| {
        freeConsidered(@ptrCast(raw_considered));
        pool.considered = null;
    }
    while (true) {
        var highest: ?*c.Repo = null;
        var index: c.Id = 1;
        while (index < pool.nrepos) : (index += 1) {
            const raw_repository = pool.repos[@intCast(index)] orelse
                continue;
            const repository: *c.Repo = @ptrCast(raw_repository);
            if (repository == pool.installed or
                repository.nsolvables == 0 or
                !repositoryIsManaged(input, repository))
            {
                continue;
            }
            if (highest == null or repository.end > highest.?.end)
                highest = repository;
        }
        const repository = highest orelse break;
        c.repo_empty(repository, 1);
    }
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const raw_repository = pool.repos[@intCast(index)] orelse continue;
        const repository: *c.Repo = @ptrCast(raw_repository);
        if (repository != pool.installed and
            repository.nsolvables == 0 and
            repositoryIsManaged(input, repository))
        {
            c.repo_empty(repository, 1);
        }
    }
    const installed: *c.Repo = @ptrCast(pool.installed orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER);
    c.repo_empty(installed, 1);
    if (input.all_deps == 0) {
        return SolvReadInstalledRpms(
            installed,
            input.cache_dir,
            input.rpm_config,
        );
    }
    return 0;
}

fn retireRepository(
    entry: RefreshEntry,
    sack: *SolvSack,
    raw_repository: ?*anyopaque,
) void {
    if (raw_repository) |raw| {
        const repository: *c.Repo = @ptrCast(@alignCast(raw));
        const pool = repository.pool;
        c.repo_free(repository, 1);
        if (entry.view.live_repository_slot) |slot| {
            if (slot.* == raw) slot.* = null;
        }
        if (pool) |value| c.pool_createwhatprovides(value);
    } else if (sack.pool) |pool| {
        c.pool_createwhatprovides(pool);
    }
}

fn refreshSackInPlace(
    input: *const abi.RepositoryRefreshInput,
    raw_sack: ?*SolvSack,
    clean_metadata: c_int,
) u32 {
    var finalize_pool = false;
    if (raw_sack) |sack| {
        const result = preparePoolRefresh(input, sack);
        if (result != 0) {
            if (sack.pool) |pool| rebuildPoolIndexes(pool);
            return result;
        }
        finalize_pool = true;
    }
    defer if (finalize_pool) {
        if (raw_sack.?.pool) |pool| rebuildPoolIndexes(pool);
    };
    if (clean_metadata == 1) input.refresh_flag.?.* = 1;

    if (consumeRefreshFailure(input, 1))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    const entries = collectRefreshEntries(
        input,
        std.heap.c_allocator,
    ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    defer std.heap.c_allocator.free(entries);
    if (entries.len != 0 and consumeRefreshFailure(input, 2))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    const loaded = std.heap.c_allocator.alloc(
        ?*anyopaque,
        entries.len,
    ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    defer std.heap.c_allocator.free(loaded);
    @memset(loaded, null);

    for (entries, 0..) |entry, index| {
        var metadata_expired: c_int = 0;
        if (entry.view.metadata_expire >= 0 and input.cache_only == 0) {
            var cache_path: ?[*:0]u8 = null;
            var result = TDNFGetCachePath(
                input.tdnf_handle,
                entry.data,
                null,
                null,
                &cache_path,
            );
            if (result != 0) return result;
            defer if (cache_path) |path| TDNFFreeMemory(path);
            result = TDNFShouldSyncMetadata(
                cache_path,
                entry.view.metadata_expire,
                &metadata_expired,
            );
            if (result != 0) return result;
        }
        if (metadata_expired != 0) {
            var result = TDNFRepoRemoveCache(
                input.tdnf_handle,
                entry.data,
            );
            if (result == error_codes.fromErrno(.NOENT)) result = 0;
            if (result != 0) return result;
            result = TDNFRemoveSolvCache(
                input.tdnf_handle,
                entry.data,
            );
            if (result == error_codes.fromErrno(.NOENT)) result = 0;
            if (result != 0) return result;
        }
        if (raw_sack) |sack| {
            const result = initRepoWithResult(
                input.tdnf_handle,
                entry.data,
                sack,
                &loaded[index],
            );
            if (result != 0 and entry.view.skip_if_unavailable != 0 and
                result != error_codes.ERROR_TDNF_OUT_OF_MEMORY and
                result != error_codes.fromErrno(.ACCES))
            {
                retireRepository(entry, sack, loaded[index]);
                loaded[index] = null;
            } else if (result != 0) {
                return result;
            }
        }
    }
    if (raw_sack != null and consumeRefreshFailure(input, 4))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    if (raw_sack) |sack| {
        rebuildPoolIndexes(sack.pool.?);
        finalize_pool = false;
    }
    if (raw_sack != null and consumeRefreshFailure(input, 5))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    if (raw_sack) |sack| {
        for (entries, loaded) |entry, repository| {
            if (repository != null and entry.view.snapshot_file != null) {
                const result = TDNFApplySnapshot(
                    input.tdnf_handle,
                    entry.data,
                    sack,
                    repository,
                );
                if (result != 0) return result;
            }
        }
        for (entries, loaded) |entry, repository| {
            if (repository == null)
                input.set_repository_enabled.?(entry.data, 0);
        }
    }
    return 0;
}

fn validateReplacementSack(
    input: *const abi.RepositoryRefreshInput,
    sack: *SolvSack,
    command_line_repository: *c.Repo,
) bool {
    const pool = sack.pool orelse return false;
    if (pool.installed == null or pool.whatprovides == null or
        command_line_repository.pool != pool)
    {
        return false;
    }
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(input, data);
        if (!isCommandLineRepositoryId(view.id)) {
            var matches: usize = 0;
            var index: c.Id = 1;
            while (index < pool.nrepos) : (index += 1) {
                const raw_candidate = pool.repos[@intCast(index)] orelse
                    continue;
                const candidate: *c.Repo = @ptrCast(raw_candidate);
                if (candidate.appdata == data) matches += 1;
            }
            if ((view.enabled != 0 and matches != 1) or
                (view.enabled == 0 and matches != 0))
            {
                return false;
            }
        }
        raw = view.next;
    }
    return true;
}

fn bindLiveRepositories(
    input: *const abi.RepositoryRefreshInput,
    sack: *SolvSack,
) void {
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(input, data);
        if (view.live_repository_slot) |slot| slot.* = null;
        raw = view.next;
    }
    const pool = sack.pool.?;
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const raw_repository = pool.repos[@intCast(index)] orelse continue;
        const repository: *c.Repo = @ptrCast(raw_repository);
        raw = input.repository_head;
        while (raw) |data| {
            const view = describeRepository(input, data);
            if (repository.appdata == data) {
                if (view.live_repository_slot) |slot|
                    slot.* = @ptrCast(repository);
                break;
            }
            raw = view.next;
        }
    }
}

fn refreshLiveSack(
    input: *const abi.RepositoryRefreshInput,
    clean_metadata: c_int,
) u32 {
    const live: *SolvSack = @ptrCast(@alignCast(input.live_sack orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    if (live.pool == null) return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const command_line_slot = input.command_line_repository_slot orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const prior_command_line = command_line_slot.*;
    const prior_refresh = input.refresh_flag.?.*;
    var replacement: ?*SolvSack = null;
    var result = SolvInitSack(
        &replacement,
        input.cache_dir,
        input.root_dir,
        input.architecture,
    );
    if (result != 0) return result;
    defer if (replacement) |value| SolvFreeSack(value);
    const replacement_value = replacement.?;
    const replacement_pool = replacement_value.pool.?;
    const raw_command_line = c.repo_create(
        replacement_pool,
        "@cmdline",
    ) orelse return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    const command_line: *c.Repo = @ptrCast(raw_command_line);
    command_line.appdata = null;
    command_line_slot.* = @ptrCast(command_line);
    var refresh_started = false;
    var committed = false;
    const state = refreshState(input);
    if (state) |value| {
        if (value.enabled) {
            value.beginRepositoryRefresh(replacement_value) catch {
                command_line_slot.* = prior_command_line;
                return error_codes.ERROR_TDNF_INVALID_PARAMETER;
            };
            refresh_started = true;
        }
    }
    defer if (!committed) {
        if (refresh_started)
            state.?.rollbackRepositoryRefresh(replacement_value);
        command_line_slot.* = prior_command_line;
        input.refresh_flag.?.* = prior_refresh;
    };

    var staged_input = input.*;
    staged_input.sack = replacement_value;
    result = refreshSackInPlace(
        &staged_input,
        replacement_value,
        clean_metadata,
    );
    if (result != 0) return result;
    if (!validateReplacementSack(
        input,
        replacement_value,
        command_line,
    )) return error_codes.ERROR_TDNF_INVALID_PARAMETER;

    std.mem.swap(SolvSack, live, replacement_value);
    command_line_slot.* = @ptrCast(command_line);
    bindLiveRepositories(input, live);
    if (refresh_started) {
        state.?.commitRepositoryRefresh(replacement_value);
        refresh_started = false;
    }
    SolvFreeSack(replacement_value);
    replacement = null;
    committed = true;
    return 0;
}

fn cloneSackContents(
    source: *SolvSack,
    destination: *SolvSack,
) u32 {
    const source_pool = source.pool orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const destination_pool = destination.pool orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const source_installed: *c.Repo = @ptrCast(source_pool.installed orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER);
    const destination_installed: *c.Repo = @ptrCast(
        destination_pool.installed orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER,
    );
    var visibility = std.ArrayList(SolvableVisibility).empty;
    defer visibility.deinit(std.heap.c_allocator);
    var saw_installed = false;
    var index: c.Id = 1;
    while (index < source_pool.nrepos) : (index += 1) {
        const raw_source = source_pool.repos[@intCast(index)] orelse continue;
        const source_repository: *c.Repo = @ptrCast(raw_source);
        const destination_repository = if (source_repository == source_installed)
            destination_installed
        else blk: {
            const name = source_repository.name orelse
                return error_codes.ERROR_TDNF_INVALID_PARAMETER;
            break :blk @as(*c.Repo, @ptrCast(c.repo_create(
                destination_pool,
                name,
            ) orelse return error_codes.ERROR_TDNF_OUT_OF_MEMORY));
        };
        cloneRepository(
            source_repository,
            destination_repository,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
            error.InvalidRepository => error_codes.ERROR_TDNF_INVALID_PARAMETER,
        };
        appendClonedVisibility(
            std.heap.c_allocator,
            source_pool,
            source_repository,
            destination_repository,
            &visibility,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
            error.InvalidRepository => error_codes.ERROR_TDNF_INVALID_PARAMETER,
        };
        if (source_repository == source_installed) saw_installed = true;
    }
    if (!saw_installed) return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    installVisibilityMap(
        destination_pool,
        visibility.items,
        source_pool.considered != null,
    ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    destination.command_package_count = source.command_package_count;
    rebuildPoolIndexes(destination_pool);
    return 0;
}

fn refreshAlternateSack(
    input: *const abi.RepositoryRefreshInput,
    sack: *SolvSack,
    clean_metadata: c_int,
) u32 {
    const prior_refresh = input.refresh_flag.?.*;
    var replacement: ?*SolvSack = null;
    var result = SolvInitSack(
        &replacement,
        sack.cache_dir,
        sack.root_dir,
        input.architecture,
    );
    if (result != 0) return result;
    defer if (replacement) |value| SolvFreeSack(value);
    const replacement_value = replacement.?;
    var committed = false;
    defer if (!committed) {
        input.refresh_flag.?.* = prior_refresh;
    };

    result = cloneSackContents(sack, replacement_value);
    if (result != 0) return result;
    var staged_input = input.*;
    staged_input.sack = replacement_value;
    result = refreshSackInPlace(
        &staged_input,
        replacement_value,
        clean_metadata,
    );
    if (result != 0) return result;

    std.mem.swap(SolvSack, sack, replacement_value);
    SolvFreeSack(replacement_value);
    replacement = null;
    committed = true;
    return 0;
}

fn refreshSack(
    raw_input: ?*const abi.RepositoryRefreshInput,
    clean_metadata: c_int,
) callconv(.c) u32 {
    const input = raw_input orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (input.tdnf_handle == null or input.live_sack == null or
        input.repository_head == null or
        input.command_line_repository_slot == null or
        input.state_slot == null or input.failure_stage == null or
        input.refresh_flag == null or input.cache_dir == null or
        input.rpm_config == null or input.describe_repository == null or
        input.set_repository_enabled == null)
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (input.sack == input.live_sack)
        return refreshLiveSack(input, clean_metadata);
    const sack: ?*SolvSack = if (input.sack) |raw|
        @ptrCast(@alignCast(raw))
    else
        null;
    if (sack) |value| {
        if (value.pool == null) return error_codes.ERROR_TDNF_INVALID_PARAMETER;
        return refreshAlternateSack(input, value, clean_metadata);
    }
    const prior_refresh = input.refresh_flag.?.*;
    const result = refreshSackInPlace(input, null, clean_metadata);
    if (result != 0) input.refresh_flag.?.* = prior_refresh;
    return result;
}

fn refreshSackFromHandle(
    handle: ?*anyopaque,
    sack: ?*anyopaque,
    clean_metadata: c_int,
) callconv(.c) u32 {
    var input = abi.RepositoryRefreshInput{};
    const result = TDNFBuildRefreshInput(handle, sack, &input);
    if (result != 0) return result;
    return refreshSack(&input, clean_metadata);
}

fn refreshHandle(handle: ?*anyopaque) callconv(.c) u32 {
    var input = abi.RepositoryRefreshInput{};
    const result = TDNFBuildRefreshInput(handle, null, &input);
    if (result != 0) return result;
    input.sack = input.live_sack;
    return refreshSack(&input, input.refresh_flag.?.*);
}

fn consumeRefreshFailure(
    input: *const abi.RepositoryRefreshInput,
    stage: u32,
) bool {
    const value = input.failure_stage orelse return false;
    if (value.* != stage) return false;
    value.* = 0;
    return true;
}

fn initRepoFromHandle(
    handle: ?*anyopaque,
    raw_data: ?*anyopaque,
    raw_sack: ?*anyopaque,
    loaded_repo: ?*?*anyopaque,
    apply_snapshot: bool,
) u32 {
    if (loaded_repo) |output| output.* = null;
    const data = raw_data orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const sack: *SolvSack = @ptrCast(@alignCast(raw_sack orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    const pool = sack.pool orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    var refresh = abi.RepositoryRefreshInput{};
    var result = TDNFBuildRefreshInput(handle, sack, &refresh);
    if (result != 0) return result;
    const view = describeRepository(&refresh, data);
    const repository_id = view.id orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (repository_id[0] == 0)
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;

    const input = abi.RepositoryInitInput{
        .tdnf_handle = handle,
        .repo_data = data,
        .sack = sack,
        .pool = pool,
        .callbacks = refresh.repository_init_callbacks,
        .refresh_input = &refresh,
        .state_slot = refresh.state_slot,
        .command_line_repository = refresh.command_line_repository_slot.?.*,
        .live_repository_slot = if (raw_sack == refresh.live_sack)
            view.live_repository_slot
        else
            null,
        .failure_stage = refresh.failure_stage,
        .repository_id = repository_id,
        .base_url = view.base_url,
        .snapshot_file = view.snapshot_file,
        .priority = view.priority,
        .has_metadata = @intFromBool(view.has_metadata != 0),
        .apply_snapshot = @intFromBool(apply_snapshot),
        .reuse_empty_repository = @intFromBool(!apply_snapshot),
    };
    result = if (apply_snapshot)
        reloadRepository(&input, loaded_repo)
    else
        initRepository(&input, loaded_repo);
    if (result != 0) {
        const name = view.name orelse repository_id;
        log_console(
            1,
            "Error: Failed to synchronize cache for repo '%s'\n",
            name,
        );
        if (result != error_codes.ERROR_TDNF_OUT_OF_MEMORY) {
            _ = TDNFRepoRemoveCache(handle, data);
            _ = TDNFRemoveSolvCache(handle, data);
            _ = TDNFRemoveLastRefreshMarker(handle, data);
        }
    }
    return result;
}

fn initRepo(
    handle: ?*anyopaque,
    data: ?*anyopaque,
    sack: ?*anyopaque,
) callconv(.c) u32 {
    return initRepoFromHandle(handle, data, sack, null, true);
}

fn initRepoWithResult(
    handle: ?*anyopaque,
    data: ?*anyopaque,
    sack: ?*anyopaque,
    loaded_repo: ?*?*anyopaque,
) callconv(.c) u32 {
    return initRepoFromHandle(
        handle,
        data,
        sack,
        loaded_repo,
        false,
    );
}

fn applySnapshot(
    handle: ?*anyopaque,
    raw_data: ?*anyopaque,
    raw_sack: ?*anyopaque,
    raw_repository: ?*anyopaque,
) callconv(.c) u32 {
    const data = raw_data orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const sack: *SolvSack = @ptrCast(@alignCast(raw_sack orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    const pool = sack.pool orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const repository: *c.Repo = @ptrCast(@alignCast(raw_repository orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    if (repository.pool != pool)
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    var refresh = abi.RepositoryRefreshInput{};
    var result = TDNFBuildRefreshInput(handle, sack, &refresh);
    if (result != 0) return result;
    const view = describeRepository(&refresh, data);
    const snapshot_file = view.snapshot_file orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;

    var packages: ?[*]?[*:0]u8 = null;
    defer TDNFFreeStringArray(packages);
    result = TDNFReadFileToStringArray(snapshot_file, &packages);
    if (result != 0) return result;
    const repo_input = std.heap.c_allocator.create(NativeRepoInput) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    repo_input.* = .{};
    defer TDNFNativeQueryFreeRepoInputs(repo_input, 1);
    result = TDNFNativeQueryBuildSingleRepoInput(
        handle,
        data,
        repo_input,
    );
    if (result != 0) return result;

    var queue: IdList = undefined;
    TDNFIdListInit(&queue);
    defer TDNFIdListFree(&queue);
    var matches: ?[*]?[*:0]u8 = null;
    defer TDNFFreeStringArray(matches);
    var index: usize = 0;
    const package_values = packages orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    while (package_values[index]) |package| : (index += 1) {
        if (package[0] == '#') continue;
        TDNFFreeStringArray(matches);
        matches = null;
        var match_count: u32 = 0;
        result = TDNFRepoMdNativeFindNameEvrMatches(
            repo_input,
            1,
            package,
            &matches,
            &match_count,
        );
        if (result != 0) return result;
        result = TDNFNativeQueryResolvePackageRefArrayToQueue(
            sack,
            matches,
            match_count,
            0,
            &queue,
        );
        if (result != 0) return result;
    }

    if (pool.considered == null) {
        const considered = std.heap.c_allocator.create(c.Map) catch
            return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
        c.map_init(considered, pool.nsolvables);
        c.map_setall(considered);
        pool.considered = considered;
    } else {
        c.map_grow(@ptrCast(pool.considered), pool.nsolvables);
    }
    const considered: *c.Map = @ptrCast(pool.considered.?);
    var solvid = repository.start;
    while (solvid < repository.end) : (solvid += 1) {
        const raw_solvable = c.pool_id2solvable(pool, solvid) orelse
            continue;
        const solvable: *c.Solvable = @ptrCast(raw_solvable);
        if (solvable.repo == repository) c.map_clr(considered, solvid);
    }
    index = 0;
    while (index < queue.dwCount) : (index += 1) {
        const selected = queue.pnElements.?[index];
        const raw_solvable = c.pool_id2solvable(pool, selected) orelse
            continue;
        const solvable: *c.Solvable = @ptrCast(raw_solvable);
        if (solvable.repo == repository) c.map_set(considered, selected);
    }
    return 0;
}

fn historyGoalImpl(
    handle: ?*anyopaque,
    install: *IdList,
    erase: *IdList,
    unresolved_count: u32,
    solved_info: *?*anyopaque,
) u32 {
    if (install.dwCount > std.math.maxInt(c_int) or
        erase.dwCount > std.math.maxInt(c_int) or
        unresolved_count > std.math.maxInt(c_int))
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }
    var jobs: IdList = undefined;
    TDNFIdListInit(&jobs);
    defer TDNFIdListFree(&jobs);
    var excludes: ?[*]?[*:0]u8 = null;
    defer TDNFFreeStringArray(excludes);
    var exclude_count: u32 = 0;
    var result = TDNFPkgsToExclude(
        handle,
        &exclude_count,
        &excludes,
    );
    if (result != 0) return result;
    var index: u32 = 0;
    while (index < install.dwCount) : (index += 1) {
        const package = install.pnElements.?[index];
        result = TDNFAddGoal(
            handle,
            5,
            &jobs,
            package,
            exclude_count,
            excludes,
        );
        if (result != 0) return result;
    }
    index = 0;
    while (index < erase.dwCount) : (index += 1) {
        const package = erase.pnElements.?[index];
        result = TDNFAddGoal(
            handle,
            4,
            &jobs,
            package,
            exclude_count,
            excludes,
        );
        if (result != 0) return result;
    }
    result = TDNFSolv(
        handle,
        &jobs,
        excludes,
        exclude_count,
        1,
        0,
        0,
        @intCast(unresolved_count),
        solved_info,
    );
    if (result != 0) return result;
    return TDNFAddUserInstall(handle, install, solved_info.*);
}

fn historyGoal(
    handle: ?*anyopaque,
    install: ?*IdList,
    erase: ?*IdList,
    solved_info: ?*?*anyopaque,
) callconv(.c) u32 {
    return historyGoalImpl(
        handle,
        install orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER,
        erase orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER,
        0,
        solved_info orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER,
    );
}

fn historyGoalWithUnresolved(
    handle: ?*anyopaque,
    raw_install: ?*anyopaque,
    raw_erase: ?*anyopaque,
    unresolved_count: u32,
    raw_solved_info: ?*anyopaque,
) callconv(.c) u32 {
    const install: *IdList = @ptrCast(@alignCast(raw_install orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    const erase: *IdList = @ptrCast(@alignCast(raw_erase orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    const solved_info: *?*anyopaque = @ptrCast(@alignCast(
        raw_solved_info orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER,
    ));
    return historyGoalImpl(
        handle,
        install,
        erase,
        unresolved_count,
        solved_info,
    );
}

fn cloneRepository(
    source: *c.Repo,
    destination: *c.Repo,
) error{ OutOfMemory, InvalidRepository }!void {
    var buffer: ?[*]u8 = null;
    var length: usize = 0;
    const writer = open_memstream(&buffer, &length) orelse
        return error.OutOfMemory;
    if (repo_write(source, writer) != 0) {
        _ = c.fclose(writer);
        if (buffer) |value| c.free(value);
        return error.InvalidRepository;
    }
    if (c.fclose(writer) != 0) {
        if (buffer) |value| c.free(value);
        return error.InvalidRepository;
    }
    const bytes = buffer orelse return error.OutOfMemory;
    defer c.free(bytes);
    const reader = fmemopen(bytes, length, "rb") orelse
        return error.OutOfMemory;
    defer _ = c.fclose(reader);
    if (repo_add_solv(destination, reader, 0) != 0)
        return error.InvalidRepository;
    destination.appdata = source.appdata;
    destination.disabled = source.disabled;
    destination.priority = source.priority;
    destination.subpriority = source.subpriority;
}

fn appendClonedVisibility(
    allocator: Allocator,
    source_pool: *c.Pool,
    source: *c.Repo,
    destination: *c.Repo,
    visibility: *std.ArrayList(SolvableVisibility),
) (Allocator.Error || error{InvalidRepository})!void {
    var destination_id = destination.start;
    var source_id = source.start;
    while (source_id < source.end) : (source_id += 1) {
        const raw_source = c.pool_id2solvable(
            source_pool,
            source_id,
        ) orelse continue;
        const source_solvable: *c.Solvable = @ptrCast(raw_source);
        if (source_solvable.repo != source) continue;
        while (destination_id < destination.end) : (destination_id += 1) {
            const raw_destination = c.pool_id2solvable(
                destination.pool,
                destination_id,
            ) orelse continue;
            const destination_solvable: *c.Solvable =
                @ptrCast(raw_destination);
            if (destination_solvable.repo != destination) continue;
            try visibility.append(allocator, .{
                .destination = destination_id,
                .visible = if (source_pool.considered) |raw_map|
                    c.map_tst(@ptrCast(raw_map), source_id) != 0
                else
                    true,
            });
            destination_id += 1;
            break;
        } else {
            return error.InvalidRepository;
        }
    }
    while (destination_id < destination.end) : (destination_id += 1) {
        const raw_destination = c.pool_id2solvable(
            destination.pool,
            destination_id,
        ) orelse continue;
        const destination_solvable: *c.Solvable = @ptrCast(raw_destination);
        if (destination_solvable.repo == destination)
            return error.InvalidRepository;
    }
}

const StableSolvableKey = struct {
    package: SolverPackageFact,
    source_name: ?[]const u8,
    source_evr: ?[]const u8,
    source_arch: ?[]const u8,
    rpmdb_hnum: ?u64,
};

const ReloadVisibilityFact = struct {
    key: StableSolvableKey,
    solvid: c.Id,
    visible: bool,
};

fn optionalStableSourceValue(
    allocator: Allocator,
    solvable: *c.Solvable,
    key: c.Id,
) Allocator.Error!?[]const u8 {
    const value = c.solvable_lookup_str(solvable, key) orelse return null;
    return try allocator.dupe(u8, std.mem.span(value));
}

fn stableSolvableKey(
    allocator: Allocator,
    pool: *c.Pool,
    repository: *c.Repo,
    solvid: c.Id,
) (Allocator.Error || error{InvalidRepository})!StableSolvableKey {
    const raw = c.pool_id2solvable(pool, solvid) orelse
        return error.InvalidRepository;
    const solvable: *c.Solvable = @ptrCast(raw);
    if (solvable.repo != repository) return error.InvalidRepository;
    const repository_name = rawRepositoryName(repository) catch
        return error.InvalidRepository;
    const package = solverFactKeyForSolvid(
        allocator,
        pool,
        repository_name,
        solvid,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidRepository,
    };
    const missing = std.math.maxInt(u64);
    const raw_hnum = c.solvable_lookup_num(
        solvable,
        c.RPM_RPMDBID,
        missing,
    );
    const rpmdb_hnum = if (repository == pool.installed) blk: {
        if (raw_hnum == missing or raw_hnum == 0)
            return error.InvalidRepository;
        break :blk raw_hnum;
    } else null;
    return .{
        .package = package,
        .source_name = try optionalStableSourceValue(
            allocator,
            solvable,
            c.SOLVABLE_SOURCENAME,
        ),
        .source_evr = try optionalStableSourceValue(
            allocator,
            solvable,
            c.SOLVABLE_SOURCEEVR,
        ),
        .source_arch = try optionalStableSourceValue(
            allocator,
            solvable,
            c.SOLVABLE_SOURCEARCH,
        ),
        .rpmdb_hnum = rpmdb_hnum,
    };
}

fn compareOptionalStableValue(
    left: ?[]const u8,
    right: ?[]const u8,
) std.math.Order {
    const presence = std.math.order(
        @intFromBool(left != null),
        @intFromBool(right != null),
    );
    if (presence != .eq) return presence;
    return if (left) |value|
        std.mem.order(u8, value, right.?)
    else
        .eq;
}

fn compareStableSolvableKeys(
    left: StableSolvableKey,
    right: StableSolvableKey,
) std.math.Order {
    const package_order = compareSolverFactKeys(left.package, right.package);
    if (package_order != .eq) return package_order;
    inline for (.{
        .{ left.source_name, right.source_name },
        .{ left.source_evr, right.source_evr },
        .{ left.source_arch, right.source_arch },
    }) |values| {
        const order = compareOptionalStableValue(values[0], values[1]);
        if (order != .eq) return order;
    }
    const hnum_presence = std.math.order(
        @intFromBool(left.rpmdb_hnum != null),
        @intFromBool(right.rpmdb_hnum != null),
    );
    if (hnum_presence != .eq) return hnum_presence;
    return if (left.rpmdb_hnum) |hnum|
        std.math.order(hnum, right.rpmdb_hnum.?)
    else
        .eq;
}

fn reloadVisibilityFactLessThan(
    _: void,
    left: ReloadVisibilityFact,
    right: ReloadVisibilityFact,
) bool {
    return compareStableSolvableKeys(left.key, right.key) == .lt;
}

fn collectReloadVisibilityFacts(
    allocator: Allocator,
    pool: *c.Pool,
    repository: *c.Repo,
) (Allocator.Error || error{InvalidRepository})![]ReloadVisibilityFact {
    var facts = std.ArrayList(ReloadVisibilityFact).empty;
    var solvid = repository.start;
    while (solvid < repository.end) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse continue;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo != repository or solvable.name == 0) continue;
        try facts.append(allocator, .{
            .key = try stableSolvableKey(
                allocator,
                pool,
                repository,
                solvid,
            ),
            .solvid = solvid,
            .visible = if (pool.considered) |raw_map|
                c.map_tst(@ptrCast(raw_map), solvid) != 0
            else
                true,
        });
    }
    const output = try facts.toOwnedSlice(allocator);
    std.mem.sort(
        ReloadVisibilityFact,
        output,
        {},
        reloadVisibilityFactLessThan,
    );
    return output;
}

fn appendReloadedVisibility(
    allocator: Allocator,
    source_pool: *c.Pool,
    source: *c.Repo,
    destination: *c.Repo,
    visibility: *std.ArrayList(SolvableVisibility),
) (Allocator.Error || error{InvalidRepository})!void {
    const destination_pool: *c.Pool = @ptrCast(destination.pool);
    if (source.pool != source_pool or destination.pool != destination_pool)
        return error.InvalidRepository;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const source_facts = try collectReloadVisibilityFacts(
        arena,
        source_pool,
        source,
    );
    const destination_facts = try collectReloadVisibilityFacts(
        arena,
        destination_pool,
        destination,
    );
    var source_index: usize = 0;
    var destination_index: usize = 0;
    while (destination_index < destination_facts.len) {
        while (source_index < source_facts.len and
            compareStableSolvableKeys(
                source_facts[source_index].key,
                destination_facts[destination_index].key,
            ) == .lt)
        {
            source_index += 1;
        }
        if (source_index == source_facts.len or
            compareStableSolvableKeys(
                source_facts[source_index].key,
                destination_facts[destination_index].key,
            ) != .eq)
        {
            try visibility.append(allocator, .{
                .destination = destination_facts[destination_index].solvid,
                .visible = destination_facts[destination_index].visible,
            });
            destination_index += 1;
            continue;
        }

        var source_end = source_index + 1;
        var old_visible = source_facts[source_index].visible;
        while (source_end < source_facts.len and
            compareStableSolvableKeys(
                source_facts[source_index].key,
                source_facts[source_end].key,
            ) == .eq) : (source_end += 1)
        {
            old_visible = old_visible and source_facts[source_end].visible;
        }
        var destination_end = destination_index + 1;
        while (destination_end < destination_facts.len and
            compareStableSolvableKeys(
                destination_facts[destination_index].key,
                destination_facts[destination_end].key,
            ) == .eq) : (destination_end += 1)
        {}
        for (destination_facts[destination_index..destination_end]) |fact| {
            try visibility.append(allocator, .{
                .destination = fact.solvid,
                .visible = old_visible and fact.visible,
            });
        }
        source_index = source_end;
        destination_index = destination_end;
    }
}

fn installVisibilityMap(
    pool: *c.Pool,
    visibility: []const SolvableVisibility,
    needed: bool,
) Allocator.Error!void {
    const prior: ?*c.Map = if (pool.considered) |raw|
        @ptrCast(raw)
    else
        null;
    if (!needed) {
        if (prior) |map| freeConsidered(map);
        pool.considered = null;
        return;
    }
    const considered = try std.heap.c_allocator.create(c.Map);
    c.map_init(considered, pool.nsolvables);
    c.map_setall(considered);
    for (visibility) |entry| {
        if (!entry.visible) c.map_clr(considered, entry.destination);
    }
    pool.considered = considered;
    if (prior) |map| freeConsidered(map);
}

fn cloneReplacementSack(
    input: *const abi.RepositoryInitInput,
    refresh: *const abi.RepositoryRefreshInput,
    source_sack: *SolvSack,
    replacement: *SolvSack,
    source_target: *c.Repo,
    capture_state: ?*State,
    visibility: *std.ArrayList(SolvableVisibility),
    loaded_repo: ?*?*anyopaque,
) u32 {
    const source_pool = source_sack.pool.?;
    const destination_pool = replacement.pool.?;
    const source_command_line: ?*c.Repo = blk: {
        const raw = refresh.command_line_repository_slot.?.* orelse
            break :blk null;
        const candidate: *c.Repo = @ptrCast(@alignCast(raw));
        break :blk if (candidate.pool == source_pool) candidate else null;
    };
    var destination_command_line: ?*c.Repo = null;
    var destination_target: ?*c.Repo = null;
    var saw_installed = false;
    var index: c.Id = 1;
    while (index < source_pool.nrepos) : (index += 1) {
        const raw_source = source_pool.repos[@intCast(index)] orelse continue;
        const source: *c.Repo = @ptrCast(raw_source);
        if (source == source_target) {
            var staged_input = input.*;
            staged_input.sack = replacement;
            staged_input.pool = destination_pool;
            staged_input.live_repository_slot = null;
            staged_input.command_line_repository = if (destination_command_line) |repo|
                @ptrCast(repo)
            else
                null;
            staged_input.reuse_empty_repository = 0;
            var raw_loaded: ?*anyopaque = null;
            const result = initRepository(&staged_input, &raw_loaded);
            if (result != 0) return result;
            const target: *c.Repo = @ptrCast(@alignCast(raw_loaded orelse
                return error_codes.ERROR_TDNF_INVALID_PARAMETER));
            target.disabled = source.disabled;
            target.subpriority = source.subpriority;
            destination_target = target;
            continue;
        }

        const destination: *c.Repo = if (source == source_pool.installed)
            @ptrCast(destination_pool.installed orelse
                return error_codes.ERROR_TDNF_INVALID_PARAMETER)
        else blk: {
            const name = source.name orelse
                return error_codes.ERROR_TDNF_INVALID_PARAMETER;
            break :blk @ptrCast(c.repo_create(
                destination_pool,
                name,
            ) orelse return error_codes.ERROR_TDNF_OUT_OF_MEMORY);
        };
        cloneRepository(source, destination) catch |err| return switch (err) {
            error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
            error.InvalidRepository => error_codes.ERROR_TDNF_INVALID_PARAMETER,
        };
        appendClonedVisibility(
            std.heap.c_allocator,
            source_pool,
            source,
            destination,
            visibility,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
            error.InvalidRepository => error_codes.ERROR_TDNF_INVALID_PARAMETER,
        };
        if (source == source_pool.installed) saw_installed = true;
        if (source_command_line != null and source == source_command_line.?)
            destination_command_line = destination;
        if (capture_state) |state| {
            state.copyRepositoryRecord(
                @ptrCast(source),
                @ptrCast(destination),
            ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
        }
    }
    const target = destination_target orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (!saw_installed) return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    appendReloadedVisibility(
        std.heap.c_allocator,
        source_pool,
        source_target,
        target,
        visibility,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        error.InvalidRepository => error_codes.ERROR_TDNF_INVALID_PARAMETER,
    };
    replacement.command_package_count = source_sack.command_package_count;
    if (source_command_line != null and destination_command_line == null)
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (loaded_repo) |output| output.* = @ptrCast(target);
    return 0;
}

fn reloadRepository(
    raw_input: ?*const abi.RepositoryInitInput,
    loaded_repo: ?*?*anyopaque,
) callconv(.c) u32 {
    if (loaded_repo) |output| output.* = null;
    const input = raw_input orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const refresh = input.refresh_input orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const source_sack: *SolvSack = @ptrCast(@alignCast(input.sack orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    const source_pool = source_sack.pool orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (input.pool != @as(*anyopaque, @ptrCast(source_pool)) or
        refresh.live_sack == null or
        refresh.command_line_repository_slot == null or
        refresh.describe_repository == null)
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }
    const source_target = findLoadedRepository(input, source_pool) catch
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const target = source_target orelse
        return initRepository(input, loaded_repo);
    if (target == source_pool.installed)
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (consumeReloadFailure(input, 1))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    var replacement: ?*SolvSack = null;
    var result = SolvInitSack(
        &replacement,
        source_sack.cache_dir,
        source_sack.root_dir,
        refresh.architecture,
    );
    if (result != 0) return result;
    defer if (replacement) |value| SolvFreeSack(value);
    const replacement_value = replacement.?;
    const is_live = input.sack == refresh.live_sack;
    const state = if (is_live) repositoryState(input) else null;
    var refresh_started = false;
    if (state) |value| {
        if (value.enabled) {
            value.beginRepositoryRefresh(replacement_value) catch
                return error_codes.ERROR_TDNF_INVALID_PARAMETER;
            refresh_started = true;
        }
    }
    defer if (refresh_started)
        state.?.rollbackRepositoryRefresh(replacement_value);
    if (consumeReloadFailure(input, 2))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    var visibility = std.ArrayList(SolvableVisibility).empty;
    defer visibility.deinit(std.heap.c_allocator);
    var staged_loaded: ?*anyopaque = null;
    result = cloneReplacementSack(
        input,
        refresh,
        source_sack,
        replacement_value,
        target,
        if (refresh_started) state else null,
        &visibility,
        &staged_loaded,
    );
    if (result != 0) return result;
    if (consumeReloadFailure(input, 4))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    const destination_pool = replacement_value.pool.?;
    installVisibilityMap(
        destination_pool,
        visibility.items,
        source_pool.considered != null or destination_pool.considered != null,
    ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    rebuildPoolIndexes(destination_pool);
    const destination_target: *c.Repo = @ptrCast(@alignCast(staged_loaded.?));
    if (!validateStagedRepository(
        input,
        destination_pool,
        destination_target,
        input.repo_data.?,
    )) return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (consumeReloadFailure(input, 5))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    const prior_command_line = refresh.command_line_repository_slot.?.*;
    var replacement_command_line: ?*anyopaque = null;
    if (prior_command_line) |raw_prior| {
        const prior: *c.Repo = @ptrCast(@alignCast(raw_prior));
        var index: c.Id = 1;
        while (index < source_pool.nrepos) : (index += 1) {
            const raw_source = source_pool.repos[@intCast(index)] orelse
                continue;
            const source: *c.Repo = @ptrCast(raw_source);
            if (source != prior) continue;
            var destination_index: c.Id = 1;
            while (destination_index < destination_pool.nrepos) : (destination_index += 1) {
                const raw_candidate = destination_pool.repos[
                    @intCast(destination_index)
                ] orelse continue;
                const candidate: *c.Repo = @ptrCast(raw_candidate);
                if (candidate.name != null and source.name != null and
                    std.mem.eql(
                        u8,
                        std.mem.span(candidate.name.?),
                        std.mem.span(source.name.?),
                    ) and candidate.appdata == source.appdata)
                {
                    replacement_command_line = @ptrCast(candidate);
                    break;
                }
            }
            break;
        }
    }
    if (is_live and prior_command_line != null and
        replacement_command_line == null)
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }

    std.mem.swap(SolvSack, source_sack, replacement_value);
    if (is_live) {
        refresh.command_line_repository_slot.?.* = replacement_command_line;
        bindLiveRepositories(refresh, source_sack);
        if (refresh_started) {
            state.?.commitRepositoryRefresh(replacement_value);
            refresh_started = false;
        }
    }
    if (loaded_repo) |output| output.* = staged_loaded;
    SolvFreeSack(replacement_value);
    replacement = null;
    return 0;
}

pub fn capturePending(state: *State, input: Input) IntegrationError!void {
    state.clear();
    if (!state.enabled) return error.InvalidEnvironment;
    if (state.fail_next_capture) {
        state.fail_next_capture = false;
        return error.OutOfMemory;
    }
    if (state.fail_next_capture_integrity) {
        state.fail_next_capture_integrity = false;
        return error.RepositoryIntegrityMismatch;
    }
    const plan = try composePlan(state, input);
    state.pending_plan = plan;
}

fn captureSolverFacts(
    allocator: Allocator,
    input: Input,
) IntegrationError!*native_capture.Owner {
    var native_input: native_capture.Input = switch (input.native_solve.*) {
        .solved => |*solve| .fromSolve(
            solve,
            solve.job_origins,
            input.trace,
        ),
        .prepared => |*prepared| .fromPrepared(
            prepared,
            prepared.job_origins,
            input.trace,
        ),
        .refuted => |*refuted| .fromRefuted(
            &refuted.prepared,
            refuted.refutation.jobs,
            &refuted.outcome,
            refuted.job_origins,
            input.trace,
        ),
    };
    native_input.problems_accepted = input.problems_accepted;
    return try native_capture.create(allocator, native_input);
}

fn composePlan(state: *State, input: Input) IntegrationError!*transaction_plan.Plan {
    const allocator = state.allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const solver_owner = try captureSolverFacts(
        allocator,
        input,
    );
    defer solver_owner.destroy();

    const solver_data = try capture_adapter.decodeData(
        arena,
        solver_owner.view(),
    );
    var live_digest_context = try SolverDigestContext.init(
        arena,
        input.pool,
    );
    defer live_digest_context.deinit();
    const environment = try captureEnvironment(
        arena,
        input.pool,
        &live_digest_context,
        input.environment,
        input.trace,
        solver_data.environment.resolution_status,
    );

    var repository_owners = std.ArrayList(*repository_capture.Owner).empty;
    defer for (repository_owners.items) |owner| owner.destroy();
    try validateRepositoryUniverse(input.pool, input.repositories);
    const hidden_identities = try collectHiddenIdentities(arena, solver_data);
    const repositories = try captureRepositories(
        arena,
        state,
        input.pool,
        &live_digest_context,
        input.repositories,
        hidden_identities,
        &repository_owners,
    );
    var data = try composeData(
        arena,
        solver_data,
        environment,
        repositories,
        repository_owners.items,
    );
    try applyRequestOutcomes(
        arena,
        input.pool,
        &data,
        input.trace,
        input.unresolved_count,
    );
    if (input.terminal_problem_kind) |kind| {
        const reference = terminalProblemReference(data, kind);
        var duplicate = false;
        for (data.problems) |problem| {
            if (problem.kind == kind and
                optionalBytesEqual(problem.job_id, reference.job_id) and
                optionalBytesEqual(problem.package_id, reference.package_id))
            {
                duplicate = true;
            }
        }
        if (!duplicate) {
            const problems = try arena.alloc(
                transaction_plan.Problem,
                data.problems.len + 1,
            );
            @memcpy(problems[0..data.problems.len], data.problems);
            problems[data.problems.len] = .{
                .id = "terminal-policy-problem",
                .capability = null,
                .count = 1,
                .job_id = reference.job_id,
                .kind = kind,
                .package_id = reference.package_id,
                .related_package_id = null,
            };
            data.problems = problems;
        }
        data.actions = &.{};
        data.environment.resolution_status = .problems;
        data.selected = &.{};
        data.skipped = &.{};
    }
    return transaction_plan.Plan.create(allocator, data);
}

fn optionalBytesEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if ((left == null) != (right == null)) return false;
    return if (left) |value| std.mem.eql(u8, value, right.?) else true;
}

fn applyRequestOutcomes(
    allocator: Allocator,
    pool: *c.Pool,
    data: *transaction_plan.Data,
    trace: *const abi.RequestTraceView,
    expected_no_candidates: u32,
) IntegrationError!void {
    const requests = try borrowedArray(abi.Request, trace.requests, trace.request_count);
    const satisfied_selections = try borrowedArray(
        abi.RequestTraceSatisfiedSelection,
        trace.satisfied_selections,
        trace.satisfied_selection_count,
    );
    if (requests.len != data.requests.len) return error.InvalidPolicyTrace;
    const selection_counts = try allocator.alloc(usize, requests.len);
    @memset(selection_counts, 0);
    for (satisfied_selections, 0..) |selection, index| {
        if (selection.request_ref >= requests.len or
            (requests[selection.request_ref].outcome !=
                abi.request_outcome.satisfied and
                requests[selection.request_ref].outcome !=
                    abi.request_outcome.queued) or
            selection.selection_id <= c.SYSTEMSOLVABLE or
            selection.selection_id >= pool.nsolvables)
        {
            return error.InvalidPolicyTrace;
        }
        if (index != 0) {
            const prior = satisfied_selections[index - 1];
            if (selection.request_ref < prior.request_ref or
                (selection.request_ref == prior.request_ref and
                    selection.selection_id <= prior.selection_id))
            {
                return error.InvalidPolicyTrace;
            }
        }
        selection_counts[selection.request_ref] += 1;
    }
    var synthetic_count: usize = 0;
    var no_candidate_count: usize = 0;
    for (requests, selection_counts) |request, selection_count| {
        switch (request.outcome) {
            abi.request_outcome.queued => synthetic_count = std.math.add(
                usize,
                synthetic_count,
                selection_count,
            ) catch return error.InvalidPolicyTrace,
            abi.request_outcome.satisfied => synthetic_count = std.math.add(
                usize,
                synthetic_count,
                @max(selection_count, 1),
            ) catch return error.InvalidPolicyTrace,
            abi.request_outcome.no_candidate => {
                if (selection_count != 0 or
                    synthetic_count == std.math.maxInt(usize) or
                    no_candidate_count == std.math.maxInt(usize))
                {
                    return error.InvalidPolicyTrace;
                }
                synthetic_count += 1;
                no_candidate_count += 1;
            },
            else => return error.InvalidPolicyTrace,
        }
    }
    if (no_candidate_count != expected_no_candidates)
        return error.InvalidPolicyTrace;

    const jobs = try allocator.alloc(
        transaction_plan.Job,
        data.jobs.len + synthetic_count,
    );
    @memcpy(jobs[0..data.jobs.len], data.jobs);
    const problems = try allocator.alloc(
        transaction_plan.Problem,
        data.problems.len + no_candidate_count,
    );
    @memcpy(problems[0..data.problems.len], data.problems);
    const include_skips =
        data.environment.resolution_status != .problems;
    const skipped = try allocator.alloc(
        transaction_plan.Skipped,
        data.skipped.len + if (include_skips) no_candidate_count else 0,
    );
    @memcpy(skipped[0..data.skipped.len], data.skipped);
    var synthetic_index: usize = 0;
    var problem_index: usize = 0;
    var selection_cursor: usize = 0;
    for (requests, 0..) |request, request_index| {
        if (request.outcome == abi.request_outcome.queued) {
            if (!requestHasJob(data.*, data.requests[request_index].id))
                return error.InvalidPolicyTrace;
            if (selection_counts[request_index] == 0) continue;
        }
        const has_subject = try flagValue(request.has_subject);
        const subject = if (has_subject)
            try bytesSlice(request.subject)
        else
            "";
        const selection_count = selection_counts[request_index];
        const outcome_job_count = if (selection_count == 0)
            @as(usize, 1)
        else
            selection_count;
        var problem_job_id: ?[]const u8 = null;
        for (0..outcome_job_count) |outcome_index| {
            const job_id = if (outcome_job_count == 1)
                try std.fmt.allocPrint(
                    allocator,
                    "outcome-job-{d}",
                    .{request_index},
                )
            else
                try std.fmt.allocPrint(
                    allocator,
                    "outcome-job-{d}-{d}",
                    .{ request_index, outcome_index },
                );
            const selection: transaction_plan.Selection =
                if (selection_count != 0)
                    .{ .package = try planPackageIdForSolvid(
                        pool,
                        data.*,
                        satisfied_selections[
                            selection_cursor + outcome_index
                        ].selection_id,
                    ) }
                else if (has_subject)
                    .{ .name = subject }
                else
                    .{ .name = data.requests[request_index].id };
            jobs[data.jobs.len + synthetic_index] = .{
                .id = job_id,
                .action = jobActionForRequest(
                    data.requests[request_index].kind,
                ),
                .selection = selection,
                .reason = .user,
                .request_id = data.requests[request_index].id,
            };
            synthetic_index += 1;
            if (problem_job_id == null) problem_job_id = job_id;
        }
        selection_cursor += selection_count;
        if (request.outcome != abi.request_outcome.no_candidate) continue;
        problems[data.problems.len + problem_index] = .{
            .id = try std.fmt.allocPrint(
                allocator,
                "no-candidate-problem-{d}",
                .{request_index},
            ),
            .capability = null,
            .count = 1,
            .job_id = problem_job_id.?,
            .kind = .no_candidate,
            .package_id = null,
            .related_package_id = null,
        };
        if (include_skips) {
            skipped[data.skipped.len + problem_index] = .{
                .job_id = problem_job_id.?,
            };
        }
        problem_index += 1;
    }
    if (selection_cursor != satisfied_selections.len)
        return error.InvalidPolicyTrace;
    data.jobs = jobs;
    data.problems = problems;
    data.skipped = skipped;
    if (include_skips and no_candidate_count != 0)
        data.environment.resolution_status = .resolved_with_skips;
}

fn planPackageIdForSolvid(
    pool: *c.Pool,
    data: transaction_plan.Data,
    solvid: c.Id,
) IntegrationError![]const u8 {
    const raw = c.pool_id2solvable(pool, solvid) orelse
        return error.InvalidPolicyTrace;
    const solvable: *c.Solvable = @ptrCast(raw);
    const identity = try solvableIdentity(pool, solvable);
    const repository_id = try rawRepositoryName(
        @ptrCast(solvable.repo orelse return error.InvalidPolicyTrace),
    );
    const missing = std.math.maxInt(u64);
    const raw_hnum = c.solvable_lookup_num(
        solvable,
        c.RPM_RPMDBID,
        missing,
    );
    const installed = raw_hnum != missing;
    const command_line = for (data.repositories) |repository| {
        if (std.mem.eql(u8, repository.id, repository_id))
            break repository.kind == .command_line;
    } else return error.InvalidPolicyTrace;
    const source = if (!installed)
        try solvableSource(pool, solvable, command_line)
    else
        null;
    var match: ?[]const u8 = null;
    for (data.packages) |package| {
        if (std.mem.eql(u8, package.repository_id, repository_id) and
            packageIdentityMatchesSolvable(package.identity, identity) and
            (if (installed)
                package.rpmdb_hnum != null and
                    package.rpmdb_hnum.? == raw_hnum
            else
                packageSourceMatchesSolvable(package.source, source.?)))
        {
            if (match != null) return error.InvalidPolicyTrace;
            match = package.id;
        }
    }
    return match orelse error.InvalidPolicyTrace;
}

const SolvableIdentity = struct {
    name: []const u8,
    arch: []const u8,
    epoch: ?u32,
    version: []const u8,
    release: []const u8,
};

const SolvableSource = struct {
    checksum_kind: []const u8,
    checksum_value: []const u8,
    is_pkgid: bool,
};

fn packageSourceMatchesSolvable(
    source: ?transaction_plan.PackageSource,
    raw: SolvableSource,
) bool {
    const value = source orelse return false;
    return raw.is_pkgid == value.checksum.is_pkgid and
        std.ascii.eqlIgnoreCase(
            value.checksum.kind,
            raw.checksum_kind,
        ) and
        std.ascii.eqlIgnoreCase(
            value.checksum.value,
            raw.checksum_value,
        );
}

fn packageIdentityMatchesSolvable(
    identity: transaction_plan.PackageIdentity,
    raw: SolvableIdentity,
) bool {
    return std.mem.eql(u8, identity.name, raw.name) and
        std.mem.eql(u8, identity.arch, raw.arch) and
        std.mem.eql(u8, identity.version, raw.version) and
        std.mem.eql(u8, identity.release, raw.release) and
        identity.epoch == raw.epoch;
}

fn solvableIdentity(
    pool: *c.Pool,
    solvable: *c.Solvable,
) IntegrationError!SolvableIdentity {
    const name = try poolString(pool, solvable.name);
    const arch = try poolString(pool, solvable.arch);
    const evr = try poolString(pool, solvable.evr);
    const parts = repository_metadata.metadata_model.splitEvrQuery(evr);
    const release = parts.release orelse return error.UnsupportedResult;
    if (name.len == 0 or arch.len == 0 or parts.version.len == 0 or
        release.len == 0)
    {
        return error.UnsupportedResult;
    }
    return .{
        .name = name,
        .arch = arch,
        .epoch = parts.epoch,
        .version = parts.version,
        .release = release,
    };
}

fn solvableSource(
    pool: *c.Pool,
    solvable: *c.Solvable,
    command_line: bool,
) IntegrationError!SolvableSource {
    var checksum_type: c.Id = 0;
    var checksum = c.solvable_lookup_checksum(
        solvable,
        c.SOLVABLE_PKGID,
        &checksum_type,
    );
    var is_pkgid = checksum != null;
    if (checksum == null) {
        checksum = c.solvable_lookup_checksum(
            solvable,
            c.SOLVABLE_CHECKSUM,
            &checksum_type,
        );
        is_pkgid = false;
    }
    const checksum_value = checksum orelse return error.UnsupportedResult;
    const raw_kind = try poolString(pool, checksum_type);
    const separator = std.mem.lastIndexOfScalar(u8, raw_kind, ':');
    const checksum_kind = if (separator) |index|
        raw_kind[index + 1 ..]
    else
        raw_kind;
    if (checksum_kind.len == 0) return error.UnsupportedResult;
    if (!command_line) {
        var media_number: c_uint = 0;
        _ = c.solvable_lookup_location(solvable, &media_number) orelse
            return error.UnsupportedResult;
    }
    return .{
        .checksum_kind = checksum_kind,
        .checksum_value = std.mem.span(checksum_value),
        .is_pkgid = is_pkgid,
    };
}

fn poolString(pool: *c.Pool, id: c.Id) IntegrationError![]const u8 {
    const value = c.pool_id2str(pool, id) orelse
        return error.UnsupportedResult;
    return std.mem.span(value);
}

fn requestHasJob(data: transaction_plan.Data, request_id: []const u8) bool {
    return for (data.jobs) |job| {
        if (job.request_id) |value| {
            if (std.mem.eql(u8, request_id, value)) break true;
        }
    } else false;
}

fn jobActionForRequest(kind: transaction_plan.RequestKind) transaction_plan.JobAction {
    return switch (kind) {
        .distro_sync => .dist_sync,
        .downgrade => .downgrade,
        .erase => .erase,
        .install => .install,
        .lock => .lock,
        .reinstall => .reinstall,
        .update, .update_all => .update,
    };
}

fn terminalProblemReference(
    data: transaction_plan.Data,
    kind: transaction_plan.ProblemKind,
) struct { job_id: ?[]const u8, package_id: ?[]const u8 } {
    for (data.actions) |action| {
        const relevant = switch (kind) {
            .installonly_limit => action.reason == .installonly_limit,
            .protected_package => blk: {
                if (action.kind == .obsolete) {
                    for (action.prior_package_ids) |package_id| {
                        if (isProtectedPackage(data, package_id)) return .{
                            .job_id = action.requested_by_job_id,
                            .package_id = package_id,
                        };
                    }
                }
                break :blk action.kind == .erase and
                    isProtectedPackage(data, action.target_package_id);
            },
            else => false,
        };
        if (relevant) return .{
            .job_id = action.requested_by_job_id,
            .package_id = action.target_package_id,
        };
    }
    if (kind == .protected_package) {
        for (data.jobs) |job| {
            if (job.action != .erase) continue;
            const package_id = switch (job.selection) {
                .package => |package_id| package_id,
                .name => |name| for (data.packages) |package| {
                    if (package.state == .installed and
                        std.mem.eql(u8, name, package.identity.name))
                    {
                        break package.id;
                    }
                } else continue,
                else => continue,
            };
            if (isProtectedPackage(data, package_id)) return .{
                .job_id = job.id,
                .package_id = package_id,
            };
        }
    }
    if (kind == .installonly_limit) {
        for (data.jobs) |job| {
            if (job.reason == .installonly_limit) return .{
                .job_id = job.id,
                .package_id = null,
            };
        }
    }
    return .{ .job_id = null, .package_id = null };
}

fn isProtectedPackage(data: transaction_plan.Data, package_id: []const u8) bool {
    const package = for (data.packages) |package| {
        if (std.mem.eql(u8, package.id, package_id)) break package;
    } else return false;
    return for (data.environment.policy.protected_names) |name| {
        if (std.mem.eql(u8, name, package.identity.name)) break true;
    } else false;
}

fn captureRepositories(
    allocator: Allocator,
    state: *const State,
    pool: *c.Pool,
    live_digest_context: *SolverDigestContext,
    inputs: []const abi.IntegrationRepository,
    hidden: []const HiddenIdentity,
    owners: *std.ArrayList(*repository_capture.Owner),
) IntegrationError![]const transaction_plan.Repository {
    const repositories = try allocator.alloc(transaction_plan.Repository, inputs.len);
    for (inputs, repositories, 0..) |input, *destination, index| {
        const id = requiredZ(input.id) catch return error.InvalidRepository;
        const cache_dir = requiredZ(input.cache_dir) catch
            return error.InvalidRepository;
        for (inputs[0..index]) |prior| {
            if (std.mem.eql(
                u8,
                id,
                requiredZ(prior.id) catch return error.InvalidRepository,
            )) return error.AmbiguousRepository;
        }
        const owner = repository_capture.capture(std.heap.c_allocator, .{
            .repository_id = id,
            .priority = input.priority,
            .cost = input.cost,
            .cache_dir = cache_dir,
            .options = (state.repositoryRecord(
                input.repository orelse return error.InvalidRepository,
            ) orelse return error.InvalidRepository).options,
        }) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.RepositoryIntegrityMismatch,
        };
        var owner_owned = true;
        errdefer if (owner_owned) owner.destroy();
        const live_repository = input.repository orelse
            return error.InvalidRepository;
        const expected_repository = try findPoolAvailableRepository(pool, id);
        if (live_repository != expected_repository) {
            return error.InvalidRepository;
        }
        const load_record = state.repositoryRecord(live_repository) orelse
            return error.InvalidRepository;
        if (!std.mem.eql(
            u8,
            &load_record.cookie_sha256,
            owner.loadCookieSha256(),
        )) return error.RepositoryIntegrityMismatch;
        verifyAvailableSolverRepository(
            allocator,
            @ptrCast(@alignCast(live_repository)),
            owner,
            live_digest_context,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.RepositoryIntegrityMismatch,
        };
        // The repository id is the same string the libsolv readback used as the
        // fact-key repository: `findPoolAvailableRepository` selected this repo
        // by `rawRepositoryName(repo) == id`, and the identity check above
        // pinned it to this owner.
        const bound_repository = bindRepositoryVisibility(
            allocator,
            owner.view().repository.id,
            owner.solverRepository(),
            hidden,
            owner.view().repository.*,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.RepositoryIntegrityMismatch,
        };
        try owners.append(allocator, owner);
        owner_owned = false;
        destination.* = bound_repository;
    }
    return repositories;
}

const VisibilityFact = struct {
    package: SolverPackageFact,
    considered: bool,
};

fn bindRepositoryVisibility(
    allocator: Allocator,
    repository_id: []const u8,
    repository: *const metadata_model.RepositoryModel,
    hidden: []const HiddenIdentity,
    captured: transaction_plan.Repository,
) IntegrationError!transaction_plan.Repository {
    const snapshot = captured.snapshot orelse return error.InvalidRepository;
    if (!std.mem.startsWith(
        u8,
        snapshot.id,
        repository_capture.snapshot_id_prefix,
    ) or snapshot.id.len != repository_capture.snapshot_id_prefix.len + 64) {
        return error.InvalidRepository;
    }
    var facts = std.ArrayList(VisibilityFact).empty;
    defer facts.deinit(allocator);
    defer for (facts.items) |fact|
        deinitSolverPackageFact(allocator, fact.package);
    try collectNativeVisibilityFacts(
        allocator,
        repository_id,
        repository,
        hidden,
        &facts,
    );
    var output = captured;
    output.snapshot = .{
        .id = try visibilitySnapshotId(allocator, snapshot.id, facts.items),
        .metadata_sha256 = snapshot.metadata_sha256,
    };
    return output;
}

/// Hash a visibility fact set into the repository snapshot id. Sorting lives
/// here so the caller never has to care what order it produced facts in.
fn visibilitySnapshotId(
    allocator: Allocator,
    captured_id: []const u8,
    facts: []VisibilityFact,
) IntegrationError![]const u8 {
    std.mem.sort(VisibilityFact, facts, {}, visibilityFactLessThan);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(visible_snapshot_identity_domain ++ "\x00");
    try hashFramedBytes(&hasher, captured_id);
    for (facts) |fact| {
        try hashSolverFactKey(&hasher, fact.package);
        hasher.update(&.{@intFromBool(fact.considered)});
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex = try lowerHexAlloc(allocator, digest);
    defer allocator.free(hex);
    return std.fmt.allocPrint(
        allocator,
        "{s}{s}",
        .{ repository_capture.snapshot_id_prefix, hex },
    );
}

/// One package hidden from the solver, in a form that can be compared against
/// the native repository model without a libsolv bitmap.
///
/// This is the same set that stamps `pool->considered` in
/// `TDNFGoalAddHiddenPackages`: both derive from `pTdnf->ppszHiddenRefs`, so
/// resolving it here reads the decision rather than a round-trip of it.
const HiddenIdentity = struct {
    repository_id: []const u8,
    name: []const u8,
    arch: []const u8,
    version: []const u8,
    release: []const u8,
    epoch: u32,
};

fn collectHiddenIdentities(
    allocator: Allocator,
    data: transaction_plan.Data,
) IntegrationError![]const HiddenIdentity {
    const output = try allocator.alloc(
        HiddenIdentity,
        data.hidden_packages.len,
    );
    for (data.hidden_packages, output) |reference, *destination| {
        const package = for (data.packages) |candidate| {
            if (std.mem.eql(u8, candidate.id, reference)) break candidate;
        } else return error.InvalidPackageMapping;
        destination.* = .{
            .repository_id = package.repository_id,
            .name = package.identity.name,
            .arch = package.identity.arch,
            .version = package.identity.version,
            .release = package.identity.release,
            .epoch = package.identity.epoch orelse 0,
        };
    }
    return output;
}

fn isHiddenPackage(
    hidden: []const HiddenIdentity,
    repository_id: []const u8,
    nevra: metadata_model.Nevra,
) bool {
    return for (hidden) |candidate| {
        if (std.mem.eql(u8, candidate.repository_id, repository_id) and
            std.mem.eql(u8, candidate.name, nevra.name) and
            std.mem.eql(u8, candidate.arch, nevra.arch) and
            std.mem.eql(u8, candidate.version, nevra.version) and
            std.mem.eql(u8, candidate.release, nevra.release) and
            candidate.epoch == (nevra.epoch orelse 0)) break true;
    } else false;
}

/// Rebuild the visibility fact set from the native repository model.
///
/// The pool this used to read is not an independent source: every available
/// repository is loaded by `repomd/solvbridge.zig` **from this same model**
/// (`SolvReadYumRepo` -> `TDNFRepoMdNativeLoadSolvRepo` ->
/// `buildRepositoryIntoRepo`), so each hashed field is reproducible here. It is
/// not reproducible *naively*, though: libsolv normalizes three of them on the
/// way in, and the snapshot id must keep hashing the normalized bytes.
/// `nativeChecksumFields` and `nativeLocation` document each rule, and the
/// differential test below pins this function against the libsolv readback for
/// as long as libsolv is still linked.
///
/// `SolvBuilder.build` creates solvables in exactly two places: one per model
/// package, then one `patch:<id>` pseudo-solvable per advisory when the
/// repository carries updateinfo. Both landed in the same repo and therefore
/// both were hashed, so both are rebuilt here.
fn collectNativeVisibilityFacts(
    allocator: Allocator,
    repository_id: []const u8,
    repository: *const metadata_model.RepositoryModel,
    hidden: []const HiddenIdentity,
    facts: *std.ArrayList(VisibilityFact),
) IntegrationError!void {
    try facts.ensureUnusedCapacity(
        allocator,
        repository.packages.len +
            if (repository.has_updateinfo) repository.advisories.len else 0,
    );
    for (repository.packages) |package| {
        const fact = try nativePackageFact(
            allocator,
            repository_id,
            package,
        );
        facts.appendAssumeCapacity(.{
            .package = fact,
            .considered = !isHiddenPackage(
                hidden,
                repository_id,
                package.nevra,
            ),
        });
    }
    if (!repository.has_updateinfo) return;
    for (repository.advisories) |advisory| {
        const fact = try nativeAdvisoryFact(
            allocator,
            repository_id,
            advisory,
        );
        facts.appendAssumeCapacity(.{ .package = fact, .considered = true });
    }
}

fn nativePackageFact(
    allocator: Allocator,
    repository_id: []const u8,
    package: metadata_model.Package,
) IntegrationError!SolverPackageFact {
    var fact = SolverPackageFact{
        .repository = "",
        .name = "",
        .arch = "",
        .evr = "",
        .pkgid_kind = "",
        .pkgid_value = "",
        .checksum_kind = "",
        .checksum_value = "",
        .location = null,
        .xml_base = null,
        .download_size = package.size.package,
        .digest = undefined,
    };
    errdefer deinitSolverPackageFact(allocator, fact);
    fact.repository = try allocator.dupe(u8, repository_id);
    fact.name = try allocator.dupe(u8, package.nevra.name);
    fact.arch = try allocator.dupe(u8, package.nevra.arch);
    fact.evr = try nativeEvrString(
        allocator,
        package.nevra.epoch,
        package.nevra.version,
        package.nevra.release,
    );
    const checksum = try nativeChecksumFields(
        allocator,
        package.checksum.kind,
        package.checksum.value,
    );
    fact.checksum_kind = checksum.kind;
    fact.checksum_value = checksum.value;
    if (package.checksum.is_pkgid) {
        const pkgid = try nativeChecksumFields(
            allocator,
            package.checksum.kind,
            package.checksum.value,
        );
        fact.pkgid_kind = pkgid.kind;
        fact.pkgid_value = pkgid.value;
    }
    fact.location = try nativeLocation(allocator, package.location.href);
    if (package.location.xml_base) |xml_base| {
        fact.xml_base = try allocator.dupe(u8, xml_base);
    }
    return fact;
}

/// `SolvBuilder.addUpdateinfo` gives an advisory solvable a `patch:` name, the
/// `noarch` architecture and nothing else, so every remaining field reads back
/// empty and `solvable_lookup_location` reports no location at all.
fn nativeAdvisoryFact(
    allocator: Allocator,
    repository_id: []const u8,
    advisory: metadata_model.Advisory,
) IntegrationError!SolverPackageFact {
    var fact = SolverPackageFact{
        .repository = "",
        .name = "",
        .arch = "",
        .evr = "",
        .pkgid_kind = "",
        .pkgid_value = "",
        .checksum_kind = "",
        .checksum_value = "",
        .location = null,
        .xml_base = null,
        .download_size = null,
        .digest = undefined,
    };
    errdefer deinitSolverPackageFact(allocator, fact);
    fact.repository = try allocator.dupe(u8, repository_id);
    fact.name = try std.fmt.allocPrint(
        allocator,
        "patch:{s}",
        .{advisory.id},
    );
    fact.arch = try allocator.dupe(u8, "noarch");
    if (advisory.version) |version| {
        if (version.len != 0) fact.evr = try allocator.dupe(u8, version);
    }
    return fact;
}

/// Mirror of `repomd/solvbridge.zig`'s `evrIdOptional`: an empty component is
/// absent, an all-absent EVR interns as id 0 (which `poolIdSlice` reports as an
/// empty string), and a version that already carries its own `digits:` prefix
/// forces an explicit zero epoch so libsolv does not read the version as one.
fn nativeEvrString(
    allocator: Allocator,
    epoch: ?u32,
    raw_version: []const u8,
    raw_release: []const u8,
) IntegrationError![]const u8 {
    const version: ?[]const u8 =
        if (raw_version.len == 0) null else raw_version;
    const release: ?[]const u8 =
        if (raw_release.len == 0) null else raw_release;
    if (epoch == null and version == null and release == null) return "";
    const effective_epoch: ?u32 = epoch orelse blk: {
        if (version) |value| {
            if (nativeNeedsZeroEpoch(value)) break :blk 0;
        }
        break :blk null;
    };
    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(allocator);
    if (effective_epoch) |value| {
        try buffer.print(allocator, "{d}:", .{value});
    }
    if (version) |value| try buffer.appendSlice(allocator, value);
    if (release) |value| {
        try buffer.append(allocator, '-');
        try buffer.appendSlice(allocator, value);
    }
    if (buffer.items.len == 0) {
        buffer.deinit(allocator);
        return "";
    }
    return buffer.toOwnedSlice(allocator);
}

fn nativeNeedsZeroEpoch(version: []const u8) bool {
    var index: usize = 0;
    while (index < version.len and
        version[index] >= '0' and version[index] <= '9') : (index += 1)
    {}
    return index > 0 and index < version.len and version[index] == ':';
}

const NativeChecksum = struct {
    kind: []const u8 = "",
    value: []const u8 = "",
};

const native_checksum_types = [_]struct {
    name: []const u8,
    knownid: []const u8,
    digest_len: usize,
}{
    .{ .name = "md5", .knownid = "repokey:type:md5", .digest_len = 16 },
    .{ .name = "sha", .knownid = "repokey:type:sha1", .digest_len = 20 },
    .{ .name = "sha1", .knownid = "repokey:type:sha1", .digest_len = 20 },
    .{ .name = "sha224", .knownid = "repokey:type:sha224", .digest_len = 28 },
    .{ .name = "sha256", .knownid = "repokey:type:sha256", .digest_len = 32 },
    .{ .name = "sha384", .knownid = "repokey:type:sha384", .digest_len = 48 },
    .{ .name = "sha512", .knownid = "repokey:type:sha512", .digest_len = 64 },
};

/// Reproduce what a checksum looks like *after* a libsolv round trip.
///
/// Three rules, none of them obvious from the metadata:
///   * the fact key records the knownid spelling (`repokey:type:sha256`), not
///     the spelling from the metadata, and `solv_chksum_str2type` matches
///     case-insensitively and folds `sha` onto sha1;
///   * `repodata_set_checksum` silently stores nothing when the value does not
///     begin with a full digest worth of hex, so a short or malformed value
///     reads back as no checksum at all rather than as itself;
///   * `repodata_chk2str` re-emits lowercase hex and ignores trailing bytes.
///
/// An unrecognised kind yields no checksum, matching `repodata_set_checksum`'s
/// own early return for an unknown type. In practice it never gets that far:
/// `SolvBuilder.addPrimary` rejects the whole repository for an unknown kind,
/// so no such package can reach a pool at all.
fn nativeChecksumFields(
    allocator: Allocator,
    kind: []const u8,
    value: []const u8,
) IntegrationError!NativeChecksum {
    const entry = for (native_checksum_types) |candidate| {
        if (std.ascii.eqlIgnoreCase(kind, candidate.name)) break candidate;
    } else return .{};
    const hex_len = entry.digest_len * 2;
    if (value.len < hex_len) return .{};
    for (value[0..hex_len]) |byte| {
        if (!std.ascii.isHex(byte)) return .{};
    }
    const lowered = try allocator.alloc(u8, hex_len);
    errdefer allocator.free(lowered);
    for (value[0..hex_len], lowered) |byte, *destination| {
        destination.* = std.ascii.toLower(byte);
    }
    return .{
        .kind = try allocator.dupe(u8, entry.knownid),
        .value = lowered,
    };
}

/// Reproduce `repodata_set_location(data, solvid, 0, NULL, href)` followed by
/// `solvable_lookup_location`.
///
/// libsolv splits the href at its last separator, strips one leading `./` from
/// the directory and drops a bare `.`, then re-joins the two halves on read. It
/// also elides a directory equal to the architecture and a file equal to the
/// canonical `name-vr.arch.rpm`, but both are regenerated from the same
/// solvable fields, so those two elisions are output-neutral and are not
/// replayed here. The `./` normalization is not output-neutral, which is why it
/// is.
fn nativeLocation(
    allocator: Allocator,
    href: []const u8,
) IntegrationError![]const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, href, '/') orelse
        return allocator.dupe(u8, href);
    const file = href[separator + 1 ..];
    var directory = href[0 .. if (separator == 0) 1 else separator];
    if (directory.len >= 2 and directory[0] == '.' and directory[1] == '/' and
        (directory.len == 2 or directory[2] != '/'))
    {
        directory = directory[2..];
    }
    if (directory.len == 1 and directory[0] == '.') directory = directory[0..0];
    if (directory.len == 0) return allocator.dupe(u8, file);
    return std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ directory, file },
    );
}

fn deinitSolverPackageFact(
    allocator: Allocator,
    fact: SolverPackageFact,
) void {
    inline for (.{
        fact.repository,
        fact.name,
        fact.arch,
        fact.evr,
        fact.pkgid_kind,
        fact.pkgid_value,
        fact.checksum_kind,
        fact.checksum_value,
    }) |value| if (value.len != 0) allocator.free(value);
    if (fact.location) |value| allocator.free(value);
    if (fact.xml_base) |value| allocator.free(value);
}

fn visibilityFactLessThan(_: void, left: VisibilityFact, right: VisibilityFact) bool {
    return compareSolverFactKeys(left.package, right.package) == .lt;
}

fn hashSolverFactKey(
    hasher: *std.crypto.hash.sha2.Sha256,
    fact: SolverPackageFact,
) IntegrationError!void {
    inline for (.{
        fact.repository,
        fact.name,
        fact.arch,
        fact.evr,
        fact.pkgid_kind,
        fact.pkgid_value,
        fact.checksum_kind,
        fact.checksum_value,
    }) |value| try hashFramedBytes(hasher, value);
    inline for (.{ fact.location, fact.xml_base }) |value| {
        hasher.update(&.{@intFromBool(value != null)});
        if (value) |bytes| try hashFramedBytes(hasher, bytes);
    }
    hasher.update(&.{@intFromBool(fact.download_size != null)});
    if (fact.download_size) |size| {
        var size_bytes: [8]u8 = undefined;
        writeBigEndian(size_bytes[0..], size);
        hasher.update(&size_bytes);
    }
}

fn hashFramedBytes(
    hasher: *std.crypto.hash.sha2.Sha256,
    value: []const u8,
) IntegrationError!void {
    var length_bytes: [8]u8 = undefined;
    writeBigEndian(length_bytes[0..], value.len);
    hasher.update(&length_bytes);
    hasher.update(value);
}

fn verifyAvailableSolverRepository(
    allocator: Allocator,
    live_repo: *c.Repo,
    owner: *const repository_capture.Owner,
    live_context: *SolverDigestContext,
) IntegrationError!void {
    const scratch_pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(scratch_pool);
    if (c.pool_setdisttype(scratch_pool, c.DISTTYPE_RPM) != 0) {
        return error.InvalidRepository;
    }
    _ = c.pool_set_flag(
        scratch_pool,
        c.POOL_FLAG_ADDFILEPROVIDESFILTERED,
        1,
    );
    const repository_id = owner.view().repository.id;
    const repository_id_z = try allocator.dupeZ(u8, repository_id);
    const scratch_repo_raw = c.repo_create(
        scratch_pool,
        repository_id_z.ptr,
    ) orelse return error.OutOfMemory;
    const scratch_repo: *c.Repo = @ptrCast(scratch_repo_raw);
    repository_metadata.solv_bridge.buildRepositoryIntoRepo(
        allocator,
        scratch_repo,
        owner.solverRepository(),
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidRepository,
    };
    live_context.seedScratch(
        scratch_pool,
        scratch_repo,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidRepository,
    };
    c.pool_addfileprovides(scratch_pool);
    c.pool_createwhatprovides(scratch_pool);

    var rebuilt_context = try SolverDigestContext.init(
        allocator,
        scratch_pool,
    );
    defer rebuilt_context.deinit();
    const live = try repositorySolverFacts(
        allocator,
        live_context,
        live_repo,
    );
    const rebuilt = try repositorySolverFacts(
        allocator,
        &rebuilt_context,
        scratch_repo,
    );
    if (live.len != rebuilt.len) return error.InvalidRepository;
    for (live, rebuilt) |left, right| {
        if (compareSolverFactKeys(left, right) != .eq or
            !std.mem.eql(u8, &left.digest, &right.digest))
        {
            return error.InvalidRepository;
        }
    }
}

const SolverPackageFact = struct {
    repository: []const u8,
    name: []const u8,
    arch: []const u8,
    evr: []const u8,
    pkgid_kind: []const u8,
    pkgid_value: []const u8,
    checksum_kind: []const u8,
    checksum_value: []const u8,
    location: ?[]const u8,
    xml_base: ?[]const u8,
    download_size: ?u64,
    digest: [32]u8,
};

fn repositorySolverFacts(
    allocator: Allocator,
    context: *SolverDigestContext,
    repository: *c.Repo,
) IntegrationError![]SolverPackageFact {
    const pool = context.pool;
    var values = std.ArrayList(SolverPackageFact).empty;
    const repository_name = try rawRepositoryName(repository);
    var solvid = repository.start;
    while (solvid < repository.end) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse continue;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo != repository or solvable.name == 0) continue;
        try values.append(
            allocator,
            try solverFactForSolvid(
                context,
                repository_name,
                solvid,
            ),
        );
    }
    const output = try values.toOwnedSlice(allocator);
    std.mem.sort(SolverPackageFact, output, {}, solverFactLessThan);
    if (output.len > 1) {
        for (output[1..], output[0 .. output.len - 1]) |current, prior| {
            if (compareSolverFactKeys(prior, current) == .eq) {
                return error.InvalidRepository;
            }
        }
    }
    return output;
}

fn solverFactForSolvid(
    context: *SolverDigestContext,
    repository_name: []const u8,
    solvid: c.Id,
) IntegrationError!SolverPackageFact {
    const pool = context.pool;
    var fact = try solverFactKeyForSolvid(
        context.allocator,
        pool,
        repository_name,
        solvid,
    );
    fact.digest = try solverPackageDigest(context, solvid);
    return fact;
}

fn solverFactKeyForSolvid(
    allocator: Allocator,
    pool: *c.Pool,
    repository_name: []const u8,
    solvid: c.Id,
) IntegrationError!SolverPackageFact {
    const raw = c.pool_id2solvable(pool, solvid) orelse
        return error.InvalidRepository;
    const solvable: *c.Solvable = @ptrCast(raw);
    var pkgid_type: c.Id = 0;
    const pkgid = c.solvable_lookup_checksum(
        solvable,
        c.SOLVABLE_PKGID,
        &pkgid_type,
    );
    const pkgid_value = if (pkgid) |value|
        try allocator.dupe(u8, std.mem.span(value))
    else
        "";
    errdefer if (pkgid_value.len != 0) allocator.free(pkgid_value);
    var checksum_type: c.Id = 0;
    const checksum = c.solvable_lookup_checksum(
        solvable,
        c.SOLVABLE_CHECKSUM,
        &checksum_type,
    );
    const checksum_value = if (checksum) |value|
        try allocator.dupe(u8, std.mem.span(value))
    else
        "";
    errdefer if (checksum_value.len != 0) allocator.free(checksum_value);
    const location = if (c.solvable_lookup_location(
        solvable,
        null,
    )) |value|
        try allocator.dupe(u8, std.mem.span(value))
    else
        null;
    errdefer if (location) |value| allocator.free(value);
    const xml_base = if (c.solvable_lookup_str(
        solvable,
        c.SOLVABLE_MEDIABASE,
    )) |value|
        try allocator.dupe(u8, std.mem.span(value))
    else
        null;
    errdefer if (xml_base) |value| allocator.free(value);
    const repository_value = try allocator.dupe(u8, repository_name);
    errdefer allocator.free(repository_value);
    const name = try allocator.dupe(
        u8,
        try poolIdSlice(pool, solvable.name),
    );
    errdefer if (name.len != 0) allocator.free(name);
    const arch = try allocator.dupe(
        u8,
        try poolIdSlice(pool, solvable.arch),
    );
    errdefer if (arch.len != 0) allocator.free(arch);
    const evr = try allocator.dupe(
        u8,
        try poolIdSlice(pool, solvable.evr),
    );
    errdefer if (evr.len != 0) allocator.free(evr);
    const pkgid_kind = try allocator.dupe(
        u8,
        try poolIdSlice(pool, pkgid_type),
    );
    errdefer if (pkgid_kind.len != 0) allocator.free(pkgid_kind);
    const checksum_kind = try allocator.dupe(
        u8,
        try poolIdSlice(pool, checksum_type),
    );
    errdefer if (checksum_kind.len != 0) allocator.free(checksum_kind);
    return .{
        .repository = repository_value,
        .name = name,
        .arch = arch,
        .evr = evr,
        .pkgid_kind = pkgid_kind,
        .pkgid_value = pkgid_value,
        .checksum_kind = checksum_kind,
        .checksum_value = checksum_value,
        .location = location,
        .xml_base = xml_base,
        .download_size = blk: {
            const missing = std.math.maxInt(u64);
            const value = c.solvable_lookup_num(
                solvable,
                c.SOLVABLE_DOWNLOADSIZE,
                missing,
            );
            break :blk if (value == missing) null else value;
        },
        .digest = undefined,
    };
}
fn solverFactLessThan(_: void, left: SolverPackageFact, right: SolverPackageFact) bool {
    return compareSolverFactKeys(left, right) == .lt;
}

fn compareSolverFactKeys(
    left: SolverPackageFact,
    right: SolverPackageFact,
) std.math.Order {
    inline for (.{
        .{ left.repository, right.repository },
        .{ left.name, right.name },
        .{ left.arch, right.arch },
        .{ left.evr, right.evr },
    }) |values| {
        const order = std.mem.order(u8, values[0], values[1]);
        if (order != .eq) return order;
    }
    inline for (.{
        .{ left.pkgid_kind, right.pkgid_kind },
        .{ left.checksum_kind, right.checksum_kind },
    }) |values| {
        const order = std.mem.order(u8, values[0], values[1]);
        if (order != .eq) return order;
    }
    inline for (.{
        .{ left.pkgid_value, right.pkgid_value },
        .{ left.checksum_value, right.checksum_value },
    }) |values| {
        const order = asciiOrderIgnoreCase(values[0], values[1]);
        if (order != .eq) return order;
    }
    inline for (.{
        .{ left.location, right.location },
        .{ left.xml_base, right.xml_base },
    }) |values| {
        const presence_order = std.math.order(
            @intFromBool(values[0] != null),
            @intFromBool(values[1] != null),
        );
        if (presence_order != .eq) return presence_order;
        if (values[0]) |left_value| {
            const order = std.mem.order(u8, left_value, values[1].?);
            if (order != .eq) return order;
        }
    }
    const size_presence = std.math.order(
        @intFromBool(left.download_size != null),
        @intFromBool(right.download_size != null),
    );
    if (size_presence != .eq) return size_presence;
    return if (left.download_size) |left_size|
        std.math.order(left_size, right.download_size.?)
    else
        .eq;
}

fn poolIdSlice(pool: *c.Pool, id: c.Id) IntegrationError![]const u8 {
    if (id == 0) return "";
    const raw = c.pool_id2str(pool, id) orelse
        return error.InvalidRepository;
    return std.mem.span(raw);
}

fn asciiOrderIgnoreCase(left: []const u8, right: []const u8) std.math.Order {
    const length = @min(left.len, right.len);
    for (left[0..length], right[0..length]) |left_byte, right_byte| {
        const left_lower = std.ascii.toLower(left_byte);
        const right_lower = std.ascii.toLower(right_byte);
        if (left_lower != right_lower) {
            return std.math.order(left_lower, right_lower);
        }
    }
    return std.math.order(left.len, right.len);
}

fn findPoolAvailableRepository(
    pool: *c.Pool,
    id: []const u8,
) IntegrationError!*anyopaque {
    var match: ?*anyopaque = null;
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const raw = pool.repos[@intCast(index)] orelse continue;
        const repository: *c.Repo = @ptrCast(raw);
        if (repositoryKind(pool, repository) != .available or
            !std.mem.eql(u8, try rawRepositoryName(repository), id))
        {
            continue;
        }
        if (match != null) return error.InvalidRepository;
        match = @ptrCast(repository);
    }
    return match orelse error.InvalidRepository;
}

fn composeData(
    allocator: Allocator,
    solver_data: transaction_plan.Data,
    environment: transaction_plan.Environment,
    available_repositories: []const transaction_plan.Repository,
    repository_owners: []const *repository_capture.Owner,
) IntegrationError!transaction_plan.Data {
    if (available_repositories.len != repository_owners.len) {
        return error.InvalidRepository;
    }

    var non_available_count: usize = 0;
    for (solver_data.repositories) |repository| {
        if (repository.kind != .available) non_available_count += 1;
    }
    const combined = try allocator.alloc(
        transaction_plan.Repository,
        non_available_count + available_repositories.len,
    );

    var output_index: usize = 0;
    for (solver_data.repositories) |repository| {
        if (repository.kind != .available) {
            combined[output_index] = repository;
            output_index += 1;
            continue;
        }
        const captured = findRepository(available_repositories, repository.id) orelse
            return error.InvalidRepository;
        if (repository.priority != captured.priority) {
            return error.InvalidRepository;
        }
    }
    for (available_repositories) |repository| {
        combined[output_index] = repository;
        output_index += 1;
    }

    const packages = try allocator.alloc(
        transaction_plan.Package,
        solver_data.packages.len,
    );
    for (solver_data.packages, packages) |package, *destination| {
        const repository = findRepository(combined, package.repository_id) orelse
            return error.InvalidRepository;
        switch (repository.kind) {
            .installed => {
                if (package.state != .installed or package.rpmdb_hnum == null or
                    package.source != null)
                {
                    return error.InvalidPackageMapping;
                }
                destination.* = package;
            },
            .command_line => {
                const source = package.source orelse
                    return error.InvalidPackageMapping;
                if (package.state != .available or source.location != null) {
                    return error.InvalidPackageMapping;
                }
                destination.* = package;
            },
            .available => {
                const source = package.source orelse
                    return error.InvalidPackageMapping;
                const owner = findRepositoryOwner(
                    repository_owners,
                    package.repository_id,
                ) orelse return error.InvalidRepository;
                const authoritative = owner.findSolverPackage(
                    package.repository_id,
                    package.identity,
                    source.checksum.value,
                    source.checksum.is_pkgid,
                ) orelse return error.InvalidPackageMapping;
                _ = authoritative.source orelse
                    return error.InvalidPackageMapping;
                destination.* = .{
                    .id = package.id,
                    .identity = authoritative.identity,
                    .repository_id = authoritative.repository_id,
                    .rpmdb_hnum = authoritative.rpmdb_hnum,
                    .source = authoritative.source,
                    .state = authoritative.state,
                };
            },
        }
    }
    return .{
        .actions = solver_data.actions,
        .environment = environment,
        .hidden_packages = solver_data.hidden_packages,
        .jobs = solver_data.jobs,
        .packages = packages,
        .problems = solver_data.problems,
        .repositories = combined,
        .requests = solver_data.requests,
        .selected = solver_data.selected,
        .skipped = solver_data.skipped,
    };
}

fn validateRepositoryUniverse(
    pool: *c.Pool,
    inputs: []const abi.IntegrationRepository,
) IntegrationError!void {
    if (pool.nrepos <= 0 or pool.repos == null) {
        return error.InvalidRepository;
    }
    var available_count: usize = 0;
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const repository = pool.repos[@intCast(index)] orelse continue;
        const pointer: *c.Repo = @ptrCast(repository);
        if (repositoryKind(pool, pointer) != .available) continue;
        const name = try rawRepositoryName(pointer);
        const input = findRepositoryInput(inputs, name) orelse {
            if (pointer.nsolvables == 0) continue;
            return error.InvalidRepository;
        };
        available_count += 1;
        if (pointer.priority == std.math.minInt(i32) or
            input.repository != @as(*anyopaque, @ptrCast(pointer)) or
            input.priority != -pointer.priority or
            input.cost != default_repository_cost)
        {
            return error.InvalidRepository;
        }
    }
    if (available_count != inputs.len) return error.InvalidRepository;
}

fn findRepositoryInput(
    inputs: []const abi.IntegrationRepository,
    id: []const u8,
) ?*const abi.IntegrationRepository {
    var match: ?*const abi.IntegrationRepository = null;
    for (inputs) |*input| {
        const input_id = requiredZ(input.id) catch return null;
        if (!std.mem.eql(u8, input_id, id)) continue;
        if (match != null) return null;
        match = input;
    }
    return match;
}

fn repositoryKind(
    pool: *c.Pool,
    repository: *c.Repo,
) transaction_plan.RepositoryKind {
    if (pool.installed != null and
        repository == @as(*c.Repo, @ptrCast(pool.installed)))
    {
        return .installed;
    }
    const name = rawRepositoryName(repository) catch return .available;
    return if (std.mem.eql(u8, name, "@cmdline"))
        .command_line
    else
        .available;
}

fn rawRepositoryName(
    repository: *c.Repo,
) IntegrationError![]const u8 {
    const name = repository.name orelse return error.InvalidRepository;
    const value = std.mem.span(name);
    if (value.len == 0) return error.InvalidRepository;
    return value;
}

fn findRepository(
    repositories: []const transaction_plan.Repository,
    id: []const u8,
) ?*const transaction_plan.Repository {
    for (repositories) |*repository| {
        if (std.mem.eql(u8, repository.id, id)) return repository;
    }
    return null;
}

fn findRepositoryOwner(
    owners: []const *repository_capture.Owner,
    id: []const u8,
) ?*repository_capture.Owner {
    for (owners) |owner| {
        if (std.mem.eql(u8, owner.view().repository.id, id)) return owner;
    }
    return null;
}

const RawPolicy = struct {
    excludes: []const []const u8,
    installonly_names: []const []const u8,
    locked_names: []const []const u8,
    min_version_values: []const []const u8,
    protected_names: []const []const u8,
};

fn captureEnvironment(
    allocator: Allocator,
    pool: *c.Pool,
    live_digest_context: *SolverDigestContext,
    input: *const abi.IntegrationEnvironment,
    trace: *const abi.RequestTraceView,
    resolution_status: transaction_plan.ResolutionStatus,
) IntegrationError!transaction_plan.Environment {
    const include_installed = try flagValue(input.include_installed);
    const architecture = try effectiveArchitecture(allocator, input);
    const policy = RawPolicy{
        .excludes = try dedupeStrings(
            allocator,
            try cStringArray(allocator, input.excludes),
        ),
        .installonly_names = try dedupeStrings(
            allocator,
            try cStringArray(allocator, input.installonly_names),
        ),
        .locked_names = try dedupeStrings(
            allocator,
            try cStringArray(allocator, input.locked_names),
        ),
        .min_version_values = try dedupeStrings(
            allocator,
            try cStringArray(allocator, input.min_versions),
        ),
        .protected_names = try dedupeStrings(
            allocator,
            try cStringArray(allocator, input.protected_names),
        ),
    };
    try validatePolicyTrace(trace, policy, try flagValue(input.allow_erasing));
    return .{
        .architecture = architecture,
        .distro = requiredZ(input.distro) catch
            return error.InvalidEnvironment,
        .policy = .{
            .allow_erasing = try flagValue(input.allow_erasing),
            .allow_multilib = try flagValue(input.allow_multilib),
            .all_deps = try flagValue(input.all_deps),
            .best = try flagValue(input.best),
            .clean_requirements_on_remove = try flagValue(
                input.clean_requirements_on_remove,
            ),
            .excludes = policy.excludes,
            .force_architecture = optionalZ(input.force_architecture),
            .include_installed = include_installed,
            .installonly_limit = input.installonly_limit,
            .installonly_names = policy.installonly_names,
            .install_weak_dependencies = try flagValue(
                input.install_weak_dependencies,
            ),
            .keep_orphans = try flagValue(input.keep_orphans),
            .locked_names = policy.locked_names,
            .min_versions = try parseMinVersions(
                allocator,
                policy.min_version_values,
            ),
            .protected_names = policy.protected_names,
            .skip_broken = try flagValue(input.skip_broken),
        },
        .releasever = requiredZ(input.releasever) catch
            return error.InvalidEnvironment,
        .resolution_status = resolution_status,
        .rpmdb = try captureRpmdbIdentity(
            allocator,
            pool,
            live_digest_context,
            input.rpm_config orelse return error.RpmdbIdentityFailed,
            include_installed,
        ),
    };
}

fn dedupeStrings(
    allocator: Allocator,
    input: []const []const u8,
) Allocator.Error![]const []const u8 {
    var output = std.ArrayList([]const u8).empty;
    for (input) |value| {
        const duplicate = for (output.items) |prior| {
            if (std.mem.eql(u8, prior, value)) break true;
        } else false;
        if (!duplicate) try output.append(allocator, value);
    }
    return output.toOwnedSlice(allocator);
}

/// The architecture the plan reports, derived the same way the pool's was.
///
/// `SolvInitSack` is the only thing that ever calls `pool_setarch`, and it
/// passes `pTdnf->pArgs->pszArch` verbatim when that pointer is non-NULL and
/// `uname().machine` otherwise -- the identical expression this environment
/// carries as `force_architecture` (`transaction_plan_capture_abi.inc`).
///
/// The pool read that this replaces recovered the lowest-scoring architecture
/// above the noarch class from `pool->id2arch`, which is the first token of the
/// policy string `pool_setarchpolicy` walked (score starts at 0x10001 and only
/// ever rises). Every key in `poolarch.c`'s `archpolicies` table is the head of
/// its own policy, and an unlisted architecture is used as a one-token policy,
/// so that first token is always exactly the string `pool_setarch` was handed.
///
/// An empty `--arch` is preserved as an error rather than quietly falling back
/// to the kernel: `pool_setarch(pool, "")` leaves `id2arch` holding nothing but
/// the noarch class, which the pool read rejected. Note that the native solver
/// treats the same input as absent (`client/goal.c` uses `IsNullOrEmptyString`
/// where `SolvInitSack` tests only for NULL), so `--arch=` is inconsistent
/// today; this keeps that inconsistency rather than silently changing it.
fn effectiveArchitecture(
    allocator: Allocator,
    input: *const abi.IntegrationEnvironment,
) IntegrationError![]const u8 {
    if (input.force_architecture) |raw| {
        const forced = std.mem.span(raw);
        if (forced.len == 0) return error.InvalidEnvironment;
        return forced;
    }
    const host = std.posix.uname();
    const machine = std.mem.sliceTo(&host.machine, 0);
    if (machine.len == 0) return error.InvalidEnvironment;
    return allocator.dupe(u8, machine);
}

fn validatePolicyTrace(
    trace: *const abi.RequestTraceView,
    policy: RawPolicy,
    allow_erasing: bool,
) IntegrationError!void {
    if (try flagValue(trace.allow_erasing) != allow_erasing) {
        return error.InvalidPolicyTrace;
    }
    const raw_facts = try borrowedArray(
        abi.RequestTracePolicyFact,
        trace.policy_facts,
        trace.policy_fact_count,
    );
    var index: usize = 0;
    inline for (.{
        .{ abi.request_trace_policy.exclude, policy.excludes },
        .{ abi.request_trace_policy.installonly, policy.installonly_names },
        .{ abi.request_trace_policy.lock, policy.locked_names },
        .{ abi.request_trace_policy.min_version, policy.min_version_values },
        .{ abi.request_trace_policy.protected, policy.protected_names },
    }) |group| {
        for (group[1]) |expected| {
            if (index >= raw_facts.len or raw_facts[index].kind != group[0] or
                !std.mem.eql(
                    u8,
                    try bytesSlice(raw_facts[index].value),
                    expected,
                ))
            {
                return error.InvalidPolicyTrace;
            }
            index += 1;
        }
    }
    if (index != raw_facts.len) return error.InvalidPolicyTrace;
}

fn parseMinVersions(
    allocator: Allocator,
    raw_values: []const []const u8,
) IntegrationError![]const transaction_plan.MinVersionConstraint {
    var values = std.ArrayList(transaction_plan.MinVersionConstraint).empty;
    for (raw_values) |raw| {
        var tokens = std.mem.tokenizeAny(u8, raw, " \t\r\n");
        while (tokens.next()) |token| {
            const value = try parseMinVersion(token);
            const duplicate = for (values.items) |prior| {
                if (minVersionConstraintEqual(prior, value)) break true;
            } else false;
            if (!duplicate) try values.append(allocator, value);
        }
    }

    return values.toOwnedSlice(allocator);
}

fn minVersionConstraintEqual(
    left: transaction_plan.MinVersionConstraint,
    right: transaction_plan.MinVersionConstraint,
) bool {
    return std.mem.eql(u8, left.name, right.name) and
        left.epoch == right.epoch and
        optionalBytesEqual(left.arch, right.arch) and
        std.mem.eql(u8, left.version, right.version) and
        optionalBytesEqual(left.release, right.release);
}

fn parseMinVersion(
    token: []const u8,
) IntegrationError!transaction_plan.MinVersionConstraint {
    const separator = std.mem.indexOfScalar(u8, token, '=') orelse
        return error.InvalidEnvironment;
    const name = token[0..separator];
    const evr = token[separator + 1 ..];
    if (name.len == 0 or evr.len == 0) return error.InvalidEnvironment;

    const parts = repository_metadata.metadata_model.splitEvrQuery(evr);
    return .{
        .arch = null,
        .epoch = if (parts.epoch) |epoch| @as(u64, epoch) else null,
        .name = name,
        .release = parts.release,
        .version = parts.version,
    };
}

fn captureRpmdbIdentity(
    allocator: Allocator,
    pool: *c.Pool,
    live_digest_context: *SolverDigestContext,
    config: *const anyopaque,
    include_installed: bool,
) IntegrationError!transaction_plan.RpmdbIdentity {
    var cookie_raw: ?[*:0]u8 = null;
    const iterator = TDNFTransactionPlanRpmdbSnapshotOpenConfig(
        config,
        &cookie_raw,
    ) orelse
        return error.RpmdbIdentityFailed;
    defer tdnf_rpmdb_iter_close(iterator);
    const cookie_pointer = cookie_raw orelse return error.RpmdbIdentityFailed;
    defer tdnf_rpmdb_string_free(cookie_pointer);
    const cookie = std.mem.span(cookie_pointer);

    var installed = std.AutoHashMapUnmanaged(u32, c.Id).empty;
    defer installed.deinit(allocator);
    try captureInstalledPackageMap(allocator, pool, include_installed, &installed);
    const scratch_pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(scratch_pool);
    if (c.pool_setdisttype(scratch_pool, c.DISTTYPE_RPM) != 0) {
        return error.RpmdbIdentityFailed;
    }
    _ = c.pool_set_flag(
        scratch_pool,
        c.POOL_FLAG_ADDFILEPROVIDESFILTERED,
        1,
    );
    const scratch_repo_raw = c.repo_create(scratch_pool, "@System") orelse
        return error.OutOfMemory;
    const scratch_repo: *c.Repo = @ptrCast(scratch_repo_raw);
    c.pool_set_installed(scratch_pool, scratch_repo);
    var scratch_builder = repository_metadata.solv_bridge
        .InstalledHeaderBatch.init(
        allocator,
        scratch_repo,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.RpmdbIdentityFailed,
    };
    var solver_pairs = std.ArrayList(InstalledSolverPair).empty;
    defer solver_pairs.deinit(allocator);
    var package_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    package_hasher.update(rpmdb_package_set_domain);
    package_hasher.update("\x00");
    var record_count: u64 = 0;
    while (true) {
        var hnum: u32 = 0;
        var blob_pointer: ?[*]const u8 = null;
        var blob_length: usize = 0;
        const result = tdnf_rpmdb_iter_next_header_blob_hnum(
            iterator,
            &hnum,
            &blob_pointer,
            &blob_length,
        );
        if (result < 0) return error.RpmdbIdentityFailed;
        if (result == 0) break;
        if (hnum == 0 or blob_pointer == null or blob_length == 0) {
            return error.RpmdbIdentityFailed;
        }
        var hnum_bytes: [4]u8 = undefined;
        writeBigEndian(hnum_bytes[0..], hnum);
        var length_bytes: [8]u8 = undefined;
        writeBigEndian(length_bytes[0..], blob_length);
        package_hasher.update(&hnum_bytes);
        package_hasher.update(&length_bytes);
        const blob = blob_pointer.?[0..blob_length];
        package_hasher.update(blob);
        try crossCheckInstalledPackage(
            allocator,
            pool,
            &scratch_builder,
            &installed,
            &solver_pairs,
            hnum,
            blob,
            include_installed,
        );
        record_count = std.math.add(u64, record_count, 1) catch
            return error.RpmdbIdentityFailed;
    }
    if (installed.count() != 0) {
        return error.RpmdbIdentityFailed;
    }
    scratch_builder.finish() catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.RpmdbIdentityFailed,
    };
    live_digest_context.seedScratch(
        scratch_pool,
        scratch_repo,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.RpmdbIdentityFailed,
    };
    c.pool_addfileprovides(scratch_pool);
    c.pool_createwhatprovides(scratch_pool);
    var rebuilt_context = try SolverDigestContext.init(
        allocator,
        scratch_pool,
    );
    defer rebuilt_context.deinit();
    for (solver_pairs.items) |pair| {
        const live_digest = try solverPackageDigest(
            live_digest_context,
            pair.live,
        );
        const rebuilt_digest = try solverPackageDigest(
            &rebuilt_context,
            pair.rebuilt,
        );
        if (!std.mem.eql(u8, &live_digest, &rebuilt_digest)) {
            return error.RpmdbIdentityFailed;
        }
    }
    var count_bytes: [8]u8 = undefined;
    writeBigEndian(count_bytes[0..], record_count);
    package_hasher.update(&count_bytes);
    var cookie_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cookie, &cookie_digest, .{});
    var package_digest: [32]u8 = undefined;
    package_hasher.final(&package_digest);
    return .{
        .backend = .sqlite,
        .cookie_sha256 = try lowerHexAlloc(allocator, cookie_digest),
        .package_set_sha256 = try lowerHexAlloc(allocator, package_digest),
    };
}

fn captureInstalledPackageMap(
    allocator: Allocator,
    pool: *c.Pool,
    include_installed: bool,
    output: *std.AutoHashMapUnmanaged(u32, c.Id),
) IntegrationError!void {
    const raw_repository = pool.installed orelse
        return error.RpmdbIdentityFailed;
    const repository: *c.Repo = @ptrCast(raw_repository);
    var solvid = repository.start;
    while (solvid < repository.end) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse continue;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo != repository) continue;
        if (!include_installed) return error.RpmdbIdentityFailed;
        const missing = std.math.maxInt(u64);
        const raw_hnum = c.solvable_lookup_num(
            solvable,
            c.RPM_RPMDBID,
            missing,
        );
        const hnum = std.math.cast(u32, raw_hnum) orelse
            return error.RpmdbIdentityFailed;
        if (hnum == 0) return error.RpmdbIdentityFailed;
        const entry = try output.getOrPut(allocator, hnum);
        if (entry.found_existing) return error.RpmdbIdentityFailed;
        entry.value_ptr.* = solvid;
    }
}

fn crossCheckInstalledPackage(
    allocator: Allocator,
    pool: *c.Pool,
    scratch_builder: *repository_metadata.solv_bridge.InstalledHeaderBatch,
    installed: *std.AutoHashMapUnmanaged(u32, c.Id),
    solver_pairs: *std.ArrayList(InstalledSolverPair),
    hnum: u32,
    blob: []const u8,
    include_installed: bool,
) IntegrationError!void {
    const header = rpm_header.Header.parse(blob) catch
        return error.RpmdbIdentityFailed;
    const name = header.getString(.name) orelse
        return error.RpmdbIdentityFailed;
    if (std.mem.eql(u8, name, "gpg-pubkey")) return;
    if (!include_installed) return;
    const entry = installed.fetchRemove(hnum) orelse
        return error.RpmdbIdentityFailed;
    const raw = c.pool_id2solvable(pool, entry.value) orelse
        return error.RpmdbIdentityFailed;
    const solvable: *c.Solvable = @ptrCast(raw);
    const identity = try solvableIdentity(pool, solvable);
    if (!std.mem.eql(u8, identity.name, name) or
        !std.mem.eql(
            u8,
            identity.version,
            header.getString(.version) orelse
                return error.RpmdbIdentityFailed,
        ) or
        !std.mem.eql(
            u8,
            identity.release,
            header.getString(.release) orelse
                return error.RpmdbIdentityFailed,
        ) or
        !std.mem.eql(
            u8,
            identity.arch,
            header.getString(.arch) orelse
                return error.RpmdbIdentityFailed,
        ))
    {
        return error.RpmdbIdentityFailed;
    }
    const epoch = repository_metadata.solv_bridge.normalizeRpmEpoch(
        header.getU32(.epoch),
    );
    if (identity.epoch != epoch) {
        return error.RpmdbIdentityFailed;
    }
    const rebuilt = scratch_builder.add(header, hnum) catch |err|
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.RpmdbIdentityFailed,
        };
    try solver_pairs.append(allocator, .{
        .live = entry.value,
        .rebuilt = rebuilt,
    });
}

const SolverDigestContext = struct {
    allocator: Allocator,
    pool: *c.Pool,
    provider_paths: std.AutoHashMapUnmanaged(
        c.Id,
        std.ArrayList([]const u8),
    ) = .empty,
    file_dependencies: []const FileDependency = &.{},
    universe_scans: u32 = 0,
    digest_calls: u64 = 0,
    scratch_seed_calls: u32 = 0,

    fn init(
        allocator: Allocator,
        pool: *c.Pool,
    ) IntegrationError!SolverDigestContext {
        var self = SolverDigestContext{
            .allocator = allocator,
            .pool = pool,
        };
        errdefer self.deinit();
        self.universe_scans = 1;

        var atoms = std.StringHashMapUnmanaged(u32).empty;
        defer atoms.deinit(allocator);
        var candidate: c.Id = 2;
        while (candidate < pool.nsolvables) : (candidate += 1) {
            const raw = c.pool_id2solvable(pool, candidate) orelse continue;
            const solvable: *c.Solvable = @ptrCast(raw);
            if (solvable.repo == null) continue;
            inline for (file_dependency_keys, 0..) |key, key_index| {
                var dependencies: c.Queue = undefined;
                c.queue_init(&dependencies);
                defer c.queue_free(&dependencies);
                _ = c.solvable_lookup_deparray(
                    solvable,
                    key,
                    &dependencies,
                    0,
                );
                if (dependencies.count != 0) {
                    for (dependencies.elements[0..@intCast(dependencies.count)]) |id| {
                        try collectFileAtoms(
                            allocator,
                            pool,
                            id,
                            0,
                            @as(u32, 1) << @intCast(key_index),
                            &atoms,
                        );
                    }
                }
            }
        }
        var paths = std.ArrayList([]const u8).empty;
        defer paths.deinit(allocator);
        var iterator = atoms.iterator();
        while (iterator.next()) |entry| {
            try paths.append(allocator, entry.key_ptr.*);
        }
        std.mem.sort([]const u8, paths.items, {}, stringLessThan);
        var file_dependencies = std.ArrayList(FileDependency).empty;
        defer file_dependencies.deinit(allocator);
        for (paths.items) |path| {
            const origins = atoms.get(path).?;
            inline for (file_dependency_keys, 0..) |key, key_index| {
                if (origins & (@as(u32, 1) << @intCast(key_index)) != 0) {
                    try file_dependencies.append(allocator, .{
                        .path = path,
                        .key = key,
                    });
                }
            }
            if (pool.whatprovides == null or pool.whatprovidesdata == null) {
                return error.RpmdbIdentityFailed;
            }
            const path_id = c.pool_strn2id(
                pool,
                path.ptr,
                @intCast(path.len),
                0,
            );
            if (path_id <= 0) continue;
            var offset: usize = @intCast(
                pool.whatprovides[@intCast(path_id)],
            );
            while (pool.whatprovidesdata[offset] != 0) : (offset += 1) {
                const provider = pool.whatprovidesdata[offset];
                const entry = try self.provider_paths.getOrPut(
                    allocator,
                    provider,
                );
                if (!entry.found_existing) entry.value_ptr.* = .empty;
                try entry.value_ptr.append(allocator, path);
            }
        }
        self.file_dependencies = try file_dependencies.toOwnedSlice(allocator);
        return self;
    }

    fn deinit(self: *SolverDigestContext) void {
        var iterator = self.provider_paths.valueIterator();
        while (iterator.next()) |paths| paths.deinit(self.allocator);
        self.provider_paths.deinit(self.allocator);
        if (self.file_dependencies.len != 0) {
            self.allocator.free(self.file_dependencies);
        }
    }

    fn pathsFor(self: *const SolverDigestContext, solvid: c.Id) []const []const u8 {
        const paths = self.provider_paths.get(solvid) orelse return &.{};
        return paths.items;
    }

    fn seedScratch(
        self: *SolverDigestContext,
        target_pool: *c.Pool,
        target_repo: *c.Repo,
    ) IntegrationError!void {
        self.scratch_seed_calls += 1;
        var dummy: ?*c.Solvable = null;
        for (file_dependency_keys) |key| {
            for (self.file_dependencies) |dependency| {
                if (dependency.key != key) continue;
                if (dummy == null) {
                    const dummy_id = c.repo_add_solvable(target_repo);
                    dummy = @ptrCast(c.pool_id2solvable(
                        target_pool,
                        dummy_id,
                    ) orelse return error.RpmdbIdentityFailed);
                }
                const path_id = c.pool_strn2id(
                    target_pool,
                    dependency.path.ptr,
                    @intCast(dependency.path.len),
                    1,
                );
                const destination = dependencyOffset(
                    dummy.?,
                    key,
                ) orelse return error.RpmdbIdentityFailed;
                destination.* = c.repo_addid_dep(
                    target_repo,
                    destination.*,
                    path_id,
                    0,
                );
            }
        }
        c.repo_internalize(target_repo);
    }
};

fn dependencyOffset(solvable: *c.Solvable, key: c.Id) ?*c.Offset {
    return if (key == c.SOLVABLE_REQUIRES)
        &solvable.requires
    else if (key == c.SOLVABLE_RECOMMENDS)
        &solvable.recommends
    else if (key == c.SOLVABLE_SUGGESTS)
        &solvable.suggests
    else if (key == c.SOLVABLE_SUPPLEMENTS)
        &solvable.supplements
    else if (key == c.SOLVABLE_ENHANCES)
        &solvable.enhances
    else if (key == c.SOLVABLE_CONFLICTS)
        &solvable.conflicts
    else if (key == c.SOLVABLE_OBSOLETES)
        &solvable.obsoletes
    else
        null;
}

fn solverPackageDigest(
    context: *SolverDigestContext,
    solvid: c.Id,
) IntegrationError![32]u8 {
    context.digest_calls += 1;
    const pool = context.pool;
    const raw = c.pool_id2solvable(pool, solvid) orelse
        return error.RpmdbIdentityFailed;
    const solvable: *c.Solvable = @ptrCast(raw);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("tdnf.installed-solver-input/v1\x00");
    inline for (.{
        solvable.name,
        solvable.arch,
        solvable.evr,
        solvable.vendor,
    }) |id| {
        try hashPoolString(&hasher, pool, id, false);
    }
    inline for (.{
        c.SOLVABLE_PROVIDES,
        c.SOLVABLE_REQUIRES,
        c.SOLVABLE_CONFLICTS,
        c.SOLVABLE_OBSOLETES,
        c.SOLVABLE_RECOMMENDS,
        c.SOLVABLE_SUGGESTS,
        c.SOLVABLE_SUPPLEMENTS,
        c.SOLVABLE_ENHANCES,
    }) |key| {
        var dependencies: c.Queue = undefined;
        c.queue_init(&dependencies);
        defer c.queue_free(&dependencies);
        _ = c.solvable_lookup_deparray(
            solvable,
            key,
            &dependencies,
            0,
        );
        if (dependencies.count != 0)
            canonicalizeDependencySegments(
                pool,
                key,
                dependencies.elements[0..@intCast(dependencies.count)],
            );
        var count_bytes: [8]u8 = undefined;
        writeBigEndian(count_bytes[0..], @intCast(dependencies.count));
        hasher.update(&count_bytes);
        if (dependencies.count != 0) {
            for (dependencies.elements[0..@intCast(dependencies.count)]) |id| {
                try hashPoolString(&hasher, pool, id, true);
            }
        }
    }
    const file_paths = context.pathsFor(solvid);
    var count_bytes: [8]u8 = undefined;
    writeBigEndian(count_bytes[0..], file_paths.len);
    hasher.update(&count_bytes);
    for (file_paths) |path| {
        var length_bytes: [8]u8 = undefined;
        writeBigEndian(length_bytes[0..], path.len);
        hasher.update(&length_bytes);
        hasher.update(path);
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

fn collectFileAtoms(
    allocator: Allocator,
    pool: *c.Pool,
    dependency: c.Id,
    depth: u8,
    origin: u32,
    atoms: *std.StringHashMapUnmanaged(u32),
) IntegrationError!void {
    if (depth == 64) return error.RpmdbIdentityFailed;
    const bits: u32 = @bitCast(dependency);
    if (bits & 0x80000000 != 0) {
        const index: c.Id = @bitCast(bits ^ 0x80000000);
        if (index <= 0 or index >= pool.nrels or pool.rels == null) {
            return error.RpmdbIdentityFailed;
        }
        const relation = pool.rels[@intCast(index)];
        try collectFileAtoms(
            allocator,
            pool,
            relation.name,
            depth + 1,
            origin,
            atoms,
        );
        try collectFileAtoms(
            allocator,
            pool,
            relation.evr,
            depth + 1,
            origin,
            atoms,
        );
        return;
    }
    if (dependency <= 0) return;
    const raw = c.pool_id2str(pool, dependency) orelse
        return error.RpmdbIdentityFailed;
    const path = std.mem.span(raw);
    if (path.len == 0 or path[0] != '/') return;
    const entry = try atoms.getOrPut(allocator, path);
    if (!entry.found_existing) entry.value_ptr.* = 0;
    entry.value_ptr.* |= origin;
}

fn stringLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

fn dependencyLessThan(pool: *c.Pool, left: c.Id, right: c.Id) bool {
    const left_raw = c.pool_dep2str(pool, left);
    const right_raw = c.pool_dep2str(pool, right);
    if (left_raw == null or right_raw == null) {
        if (left_raw == null and right_raw == null) return left < right;
        return left_raw == null;
    }
    return std.mem.order(
        u8,
        std.mem.span(left_raw.?),
        std.mem.span(right_raw.?),
    ) == .lt;
}

fn canonicalizeDependencySegments(
    pool: *c.Pool,
    key: c.Id,
    dependencies: []c.Id,
) void {
    var segment_start: usize = 0;
    for (dependencies, 0..) |dependency, index| {
        const is_boundary =
            (key == c.SOLVABLE_REQUIRES and
                dependency == c.SOLVABLE_PREREQMARKER) or
            (key == c.SOLVABLE_PROVIDES and
                dependency == c.SOLVABLE_FILEMARKER);
        if (!is_boundary) continue;
        std.mem.sort(
            c.Id,
            dependencies[segment_start..index],
            pool,
            dependencyLessThan,
        );
        segment_start = index + 1;
    }
    std.mem.sort(
        c.Id,
        dependencies[segment_start..],
        pool,
        dependencyLessThan,
    );
}

fn hashPoolString(
    hasher: *std.crypto.hash.sha2.Sha256,
    pool: *c.Pool,
    id: c.Id,
    dependency: bool,
) IntegrationError!void {
    const value: []const u8 = if (id == 0)
        ""
    else if (dependency)
        std.mem.span(c.pool_dep2str(pool, id) orelse
            return error.RpmdbIdentityFailed)
    else
        std.mem.span(c.pool_id2str(pool, id) orelse
            return error.RpmdbIdentityFailed);
    var length_bytes: [8]u8 = undefined;
    writeBigEndian(length_bytes[0..], value.len);
    hasher.update(&length_bytes);
    hasher.update(value);
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

fn lowerHexAlloc(
    allocator: Allocator,
    bytes: [32]u8,
) Allocator.Error![]const u8 {
    const output = try allocator.alloc(u8, 64);
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, index| {
        output[index * 2] = alphabet[byte >> 4];
        output[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return output;
}

fn cStringArray(
    allocator: Allocator,
    raw: ?[*]const ?[*:0]const u8,
) IntegrationError![]const []const u8 {
    const values = raw orelse return &.{};
    var count: usize = 0;
    while (values[count] != null) : (count += 1) {}
    const output = try allocator.alloc([]const u8, count);
    for (output, 0..) |*destination, index| {
        destination.* = std.mem.span(values[index].?);
    }
    return output;
}

fn borrowedArray(
    comptime T: type,
    pointer: ?[*]const T,
    raw_count: u32,
) IntegrationError![]const T {
    const count: usize = raw_count;
    if (count == 0) {
        if (pointer != null) return error.InvalidPolicyTrace;
        return &.{};
    }
    return (pointer orelse return error.InvalidPolicyTrace)[0..count];
}

fn bytesSlice(value: abi.Bytes) IntegrationError![]const u8 {
    if (value.length == 0) {
        if (value.data != null) return error.InvalidPolicyTrace;
        return "";
    }
    return (value.data orelse return error.InvalidPolicyTrace)[0..value.length];
}

fn requiredZ(value: ?[*:0]const u8) error{InvalidEnvironment}![]const u8 {
    const output = optionalZ(value) orelse return error.InvalidEnvironment;
    if (output.len == 0) return error.InvalidEnvironment;
    return output;
}

fn optionalZ(value: ?[*:0]const u8) ?[]const u8 {
    return if (value) |pointer| std.mem.span(pointer) else null;
}

fn flagValue(raw: u32) error{InvalidEnvironment}!bool {
    return switch (raw) {
        0 => false,
        1 => true,
        else => error.InvalidEnvironment,
    };
}

fn mapIntegrationError(err: anyerror) u32 {
    return switch (err) {
        error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        error.InvalidEnvironment,
        error.InvalidPolicyTrace,
        error.InvalidRepository,
        => error_codes.ERROR_TDNF_INVALID_PARAMETER,
        error.RepositoryIntegrityMismatch => error_codes.ERROR_TDNF_REPO_PERFORM,
        error.UnsupportedResult => error_codes.ERROR_TDNF_CALL_NOT_SUPPORTED,
        else => error_codes.ERROR_TDNF_SOLV_FAILED,
    };
}

fn stateSetEnabled(
    raw_state: ?*?*State,
    raw_enabled: u32,
) callconv(.c) u32 {
    const state_out = raw_state orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const enabled = flagValue(raw_enabled) catch
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (!enabled and state_out.* == null) return 0;
    const state = state_out.* orelse State.create(std.heap.c_allocator) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    state_out.* = state;
    state.setEnabled(enabled);
    return 0;
}

fn stateIsEnabled(state: ?*const State) callconv(.c) u32 {
    return @intFromBool(if (state) |value| value.enabled else false);
}

fn stateRecordRepository(
    raw_state: ?*?*State,
    repository: ?*anyopaque,
    raw_cookie: ?*const [32]u8,
    include_filelists: u32,
    include_updateinfo: u32,
    include_other: u32,
) callconv(.c) u32 {
    const state_out = raw_state orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const pointer = repository orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const cookie = raw_cookie orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const state = state_out.* orelse return 0;
    if (!state.enabled) return 0;
    if (include_filelists > 1 or include_updateinfo > 1 or
        include_other > 1)
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }
    state.recordRepository(pointer, cookie.*, .{
        .include_filelists = include_filelists != 0,
        .include_updateinfo = include_updateinfo != 0,
        .include_other = include_other != 0,
    }) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    return 0;
}

fn stateRepositoryRecordCount(
    state: ?*const State,
    repository: ?*anyopaque,
) callconv(.c) u32 {
    const value = state orelse return 0;
    const pointer = repository orelse return 0;
    return value.repositoryRecordCount(pointer);
}

fn stateFailNextRepositoryRecord(state: ?*State) callconv(.c) void {
    const value = state orelse return;
    if (value.enabled) value.fail_next_repository_record = true;
}

fn stateFailNextCapture(state: ?*State) callconv(.c) void {
    const value = state orelse return;
    if (value.enabled) value.fail_next_capture = true;
}

fn stateFailNextCaptureIntegrity(state: ?*State) callconv(.c) void {
    const value = state orelse return;
    if (value.enabled) value.fail_next_capture_integrity = true;
}

fn stateClear(state: ?*State) callconv(.c) void {
    if (state) |value| value.clear();
}

fn statePublish(state: ?*State) callconv(.c) u32 {
    const value = state orelse return 0;
    if (!value.enabled) return 0;
    value.publish() catch return error_codes.ERROR_TDNF_CALL_NOT_SUPPORTED;
    return 0;
}

fn stateHasPendingProblem(state: ?*const State) callconv(.c) u32 {
    return @intFromBool(if (state) |value| value.hasPendingProblem() else false);
}

fn statePublishProblem(state: ?*State) callconv(.c) u32 {
    return @intFromBool(if (state) |value| value.publishProblem() else false);
}

fn stateDestroy(state: ?*State) callconv(.c) void {
    if (state) |value| value.destroy();
}

fn stateGetCanonicalJson(
    state: ?*const State,
    raw_data: ?*?[*]const u8,
    raw_length: ?*usize,
) callconv(.c) u32 {
    const data_out = raw_data orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const length_out = raw_length orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    data_out.* = null;
    length_out.* = 0;
    const value = state orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const json = value.canonicalJsonAlloc(std.heap.c_allocator) catch |err| {
        return switch (err) {
            error.NoPlan => error_codes.ERROR_TDNF_CALL_NOT_SUPPORTED,
            error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        };
    };
    data_out.* = json.ptr;
    length_out.* = json.len;
    return 0;
}

fn stateFreeCanonicalJson(
    raw_data: ?[*]const u8,
    length: usize,
) callconv(.c) void {
    if (raw_data) |data| {
        if (length != 0) std.heap.c_allocator.free(data[0..length]);
    }
}

fn handleRefreshInput(
    handle: ?*anyopaque,
) ?abi.RepositoryRefreshInput {
    var input = abi.RepositoryRefreshInput{};
    if (TDNFBuildRefreshInput(handle, null, &input) != 0) return null;
    return input;
}

fn handleState(input: *const abi.RepositoryRefreshInput) ?*State {
    const slot = input.state_slot orelse return null;
    const raw = slot.* orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn findHandleRepository(
    input: *const abi.RepositoryRefreshInput,
    raw_id: ?[*:0]const u8,
) ?RefreshEntry {
    const id = raw_id orelse return null;
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(input, data);
        if (view.id) |candidate| {
            if (std.mem.eql(
                u8,
                std.mem.span(candidate),
                std.mem.span(id),
            )) return .{ .data = data, .view = view };
        }
        raw = view.next;
    }
    return null;
}

fn handleLiveSack(
    input: *const abi.RepositoryRefreshInput,
) ?*SolvSack {
    const raw = input.live_sack orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn captureSetEnabled(
    handle: ?*anyopaque,
    enabled: u32,
) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const slot: *?*State = @ptrCast(@alignCast(input.state_slot.?));
    return stateSetEnabled(slot, enabled);
}

fn captureGetCanonicalJson(
    handle: ?*anyopaque,
    data: ?*?[*]const u8,
    length: ?*usize,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    return stateGetCanonicalJson(handleState(&input), data, length);
}

fn publicSetEnabled(
    handle: ?*anyopaque,
    enabled: u32,
) callconv(.c) u32 {
    return captureSetEnabled(handle, enabled);
}

fn publicGetCanonicalJson(
    handle: ?*anyopaque,
    raw_json: ?*?[*:0]u8,
) callconv(.c) u32 {
    const json_out = raw_json orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    json_out.* = null;
    var input = handleRefreshInput(handle) orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const state = handleState(&input) orelse
        return error_codes.ERROR_TDNF_CALL_NOT_SUPPORTED;
    const json = state.canonicalJsonAlloc(std.heap.c_allocator) catch |err| {
        return switch (err) {
            error.NoPlan => error_codes.ERROR_TDNF_CALL_NOT_SUPPORTED,
            error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        };
    };
    defer std.heap.c_allocator.free(json);
    const sentinel = std.heap.c_allocator.allocSentinel(
        u8,
        json.len,
        0,
    ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    @memcpy(sentinel[0..json.len], json);
    json_out.* = sentinel.ptr;
    return 0;
}

fn publicFreeCanonicalJson(raw_json: ?[*:0]u8) callconv(.c) void {
    if (raw_json) |json| TDNFFreeMemory(@ptrCast(json));
}

fn publicGetDigestHex(
    handle: ?*anyopaque,
    raw_digest: ?[*]u8,
) callconv(.c) u32 {
    const digest_out = raw_digest orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    digest_out[0] = 0;
    var input = handleRefreshInput(handle) orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const state = handleState(&input) orelse
        return error_codes.ERROR_TDNF_CALL_NOT_SUPPORTED;
    const digest = state.digestHex(std.heap.c_allocator) catch |err| {
        return switch (err) {
            error.NoPlan => error_codes.ERROR_TDNF_CALL_NOT_SUPPORTED,
            error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        };
    };
    @memcpy(digest_out[0..64], &digest);
    digest_out[64] = 0;
    return 0;
}

fn captureFailNextRepositoryRecord(handle: ?*anyopaque) callconv(.c) void {
    var input = handleRefreshInput(handle) orelse return;
    stateFailNextRepositoryRecord(handleState(&input));
}

fn captureFailNextComposition(handle: ?*anyopaque) callconv(.c) void {
    var input = handleRefreshInput(handle) orelse return;
    stateFailNextCapture(handleState(&input));
}

fn captureFailNextIntegrity(handle: ?*anyopaque) callconv(.c) void {
    var input = handleRefreshInput(handle) orelse return;
    stateFailNextCaptureIntegrity(handleState(&input));
}

fn testFailNextReload(
    handle: ?*anyopaque,
    stage: u32,
) callconv(.c) void {
    const input = handleRefreshInput(handle) orelse return;
    input.failure_stage.?.* = stage;
}

fn testPoolIdentity(handle: ?*anyopaque) callconv(.c) usize {
    const input = handleRefreshInput(handle) orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    return @intFromPtr(sack.pool orelse return 0);
}

fn testPoolSolvableCount(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    const pool = sack.pool orelse return 0;
    return @intCast(pool.nsolvables);
}

fn testPoolRepoCount(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    const pool = sack.pool orelse return 0;
    return @intCast(pool.nrepos);
}

fn testRepoDataCount(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    const pool = sack.pool orelse return 0;
    var count: u32 = 0;
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const raw = pool.repos[@intCast(index)] orelse continue;
        const repository: *c.Repo = @ptrCast(raw);
        if (repository != pool.installed)
            count += @intCast(repository.nrepodata);
    }
    return count;
}

fn testConsideredCount(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    const pool = sack.pool orelse return 0;
    var count: u32 = 0;
    var solvid: c.Id = 1;
    while (solvid < pool.nsolvables) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse continue;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo != null and
            (pool.considered == null or
                c.map_tst(@ptrCast(pool.considered), solvid) != 0))
        {
            count += 1;
        }
    }
    return count;
}

fn testConsideredIdentity(handle: ?*anyopaque) callconv(.c) usize {
    const input = handleRefreshInput(handle) orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    const pool = sack.pool orelse return 0;
    return if (pool.considered) |value| @intFromPtr(value) else 0;
}

fn testGrowCmdlineConsidered(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    const pool = sack.pool orelse return 0;
    const raw_repository = input.command_line_repository_slot.?.* orelse
        return 0;
    const repository: *c.Repo = @ptrCast(@alignCast(raw_repository));
    if (pool.considered == null) {
        const considered = std.heap.c_allocator.create(c.Map) catch return 0;
        c.map_init(considered, pool.nsolvables);
        c.map_setall(considered);
        pool.considered = considered;
    }
    const solvid = c.repo_add_solvable(repository);
    if (solvid <= 0) return 0;
    const considered: *c.Map = @ptrCast(pool.considered.?);
    c.map_grow(considered, pool.nsolvables);
    c.map_set(considered, solvid);
    return @intFromBool(c.map_tst(considered, solvid) != 0);
}

fn testRetireNullSack(handle: ?*anyopaque) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(&input, data);
        if (view.live_repository) |raw_repository| {
            const repository: *c.Repo =
                @ptrCast(@alignCast(raw_repository));
            const pool: *c.Pool = @ptrCast(repository.pool);
            c.repo_free(repository, 1);
            if (view.live_repository_slot) |slot| slot.* = null;
            rebuildPoolIndexes(pool);
            return 1;
        }
        raw = view.next;
    }
    return 0;
}

fn testPublicInitRepo(handle: ?*anyopaque) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, "extras") orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    const result = initRepo(handle, entry.data, sack);
    if (result != 0) return result;
    return @intFromBool(sack.pool.?.whatprovides != null);
}

fn testReloadRepo(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const entry = findHandleRepository(&input, id) orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    return initRepo(handle, entry.data, input.live_sack);
}

fn testInitRepoInSack(
    handle: ?*anyopaque,
    sack: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const entry = findHandleRepository(&input, id) orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    return initRepo(handle, entry.data, sack);
}

fn testRepoIdentity(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) usize {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    return if (entry.view.live_repository) |repository|
        @intFromPtr(repository)
    else
        0;
}

fn testRepoId(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    const raw = entry.view.live_repository orelse return 0;
    const repository: *c.Repo = @ptrCast(@alignCast(raw));
    return @intCast(repository.repoid);
}

fn testRepoPackageCount(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    const raw = entry.view.live_repository orelse return 0;
    const repository: *c.Repo = @ptrCast(@alignCast(raw));
    return @intCast(repository.nsolvables);
}

fn testRepoBindingCount(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    const pool = sack.pool orelse return 0;
    var count: u32 = 0;
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const raw = pool.repos[@intCast(index)] orelse continue;
        const repository: *c.Repo = @ptrCast(raw);
        if (repository.appdata == entry.data) count += 1;
    }
    return count;
}

fn testRepoRecordCount(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    const repository = entry.view.live_repository orelse return 0;
    const state = handleState(&input) orelse return 0;
    return state.repositoryRecordCount(repository);
}

fn testRepoRecordDigest(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
    output: ?[*]u8,
) callconv(.c) u32 {
    const destination = output orelse return 0;
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    const repository = entry.view.live_repository orelse return 0;
    const state = handleState(&input) orelse return 0;
    const record = state.repositoryRecord(repository) orelse return 0;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("tdnf.repository-load-record/v1\x00");
    hasher.update(&record.cookie_sha256);
    hasher.update(&.{
        @intFromBool(record.options.include_filelists),
        @intFromBool(record.options.include_updateinfo),
        @intFromBool(record.options.include_other),
    });
    hasher.final(destination[0..32]);
    return 1;
}

fn testInitRepoValidation(handle: ?*anyopaque) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const data = input.repository_head orelse return 0;
    const sack = handleLiveSack(&input) orelse return 0;
    var empty = SolvSack{
        .pool = null,
        .command_package_count = 0,
        .cache_dir = null,
        .root_dir = null,
    };
    return @intFromBool(
        initRepo(null, data, sack) ==
            error_codes.ERROR_TDNF_INVALID_PARAMETER and
            initRepo(handle, null, sack) ==
                error_codes.ERROR_TDNF_INVALID_PARAMETER and
            initRepo(handle, data, null) ==
                error_codes.ERROR_TDNF_INVALID_PARAMETER and
            initRepo(handle, data, &empty) ==
                error_codes.ERROR_TDNF_INVALID_PARAMETER and
            initRepo(null, null, null) ==
                error_codes.ERROR_TDNF_INVALID_PARAMETER,
    );
}

fn testPoolIndexesHealthy(handle: ?*anyopaque) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 2;
    const sack = handleLiveSack(&input) orelse return 2;
    const pool = sack.pool orelse return 2;
    if (pool.whatprovides == null) return 2;
    const command_line = input.command_line_repository_slot.?.*;
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const raw = pool.repos[@intCast(index)] orelse continue;
        const repository: *c.Repo = @ptrCast(raw);
        var managed = repository == pool.installed or
            command_line == @as(*anyopaque, @ptrCast(repository));
        var data = input.repository_head;
        while (data) |value| {
            const view = describeRepository(&input, value);
            managed = managed or repository.appdata == value;
            data = view.next;
        }
        if (!managed) return 3;
        var other = index + 1;
        while (other < pool.nrepos) : (other += 1) {
            const raw_candidate = pool.repos[@intCast(other)] orelse continue;
            const candidate: *c.Repo = @ptrCast(raw_candidate);
            if (repository.appdata != null and
                repository.appdata == candidate.appdata)
            {
                return 4;
            }
        }
    }
    const id = c.pool_str2id(pool, "installed-file-provider", 0);
    if (id == 0) return 5;
    const providers = c.pool_whatprovides(pool, id);
    return if (pool.whatprovidesdata[@intCast(providers)] != 0) 1 else 5;
}

fn testEnableRepo(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    input.set_repository_enabled.?(entry.data, 1);
    return 1;
}

const TestSackSnapshot = extern struct {
    pool_identity: usize = 0,
    repository_identity: usize = 0,
    considered_identity: usize = 0,
    indexes_identity: usize = 0,
    solvable_count: u32 = 0,
    repository_count: u32 = 0,
    considered_count: u32 = 0,
    digest: [32]u8 = [_]u8{0} ** 32,
};

fn testSackSnapshot(
    raw_sack: ?*anyopaque,
    raw_repository_id: ?[*:0]const u8,
    raw_output: ?*TestSackSnapshot,
) callconv(.c) u32 {
    const sack: *SolvSack = @ptrCast(@alignCast(raw_sack orelse return 0));
    const pool = sack.pool orelse return 0;
    const repository_id = std.mem.span(raw_repository_id orelse return 0);
    const output = raw_output orelse return 0;
    var repository_match: ?*c.Repo = null;
    var repository_count: u32 = 0;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("tdnf.test-sack-snapshot/v1\x00");
    var index: c.Id = 1;
    while (index < pool.nrepos) : (index += 1) {
        const raw_repository = pool.repos[@intCast(index)] orelse continue;
        const repository: *c.Repo = @ptrCast(raw_repository);
        repository_count += 1;
        if (repository.name) |name| {
            if (std.mem.eql(u8, std.mem.span(name), repository_id)) {
                if (repository_match != null) return 0;
                repository_match = repository;
            }
        }
        var buffer: ?[*]u8 = null;
        var length: usize = 0;
        const writer = open_memstream(&buffer, &length) orelse return 0;
        const write_result = repo_write(repository, writer);
        const close_result = c.fclose(writer);
        if (write_result != 0 or close_result != 0) {
            if (buffer) |value| c.free(value);
            return 0;
        }
        const bytes = buffer orelse return 0;
        var length_bytes: [8]u8 = undefined;
        writeBigEndian(&length_bytes, length);
        hasher.update(&length_bytes);
        hasher.update(bytes[0..length]);
        c.free(bytes);
    }
    const repository = repository_match orelse return 0;
    var solvable_count: u32 = 0;
    var considered_count: u32 = 0;
    var solvid: c.Id = 1;
    while (solvid < pool.nsolvables) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse return 0;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo == null) continue;
        solvable_count += 1;
        const considered = pool.considered == null or
            c.map_tst(@ptrCast(pool.considered), solvid) != 0;
        if (considered) considered_count += 1;
        hasher.update(&.{@intFromBool(considered)});
    }
    output.* = .{
        .pool_identity = @intFromPtr(pool),
        .repository_identity = @intFromPtr(repository),
        .considered_identity = if (pool.considered) |value|
            @intFromPtr(value)
        else
            0,
        .indexes_identity = if (pool.whatprovides) |value|
            @intFromPtr(value)
        else
            0,
        .solvable_count = solvable_count,
        .repository_count = repository_count,
        .considered_count = considered_count,
    };
    hasher.final(&output.digest);
    return 1;
}

fn integrationCapturePending(
    state: ?*State,
    raw_pool: ?*anyopaque,
    raw_native_solve: ?*const anyopaque,
    trace: ?*const abi.RequestTraceView,
    raw_problems_accepted: u32,
    unresolved_count: u32,
    raw_terminal_problem_kind: u32,
    raw_repositories: ?[*]const abi.IntegrationRepository,
    repository_count: u32,
    environment: ?*const abi.IntegrationEnvironment,
) callconv(.c) u32 {
    const value = state orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    value.clear();
    if (!value.enabled) return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const repositories = borrowedIntegrationRepositories(
        raw_repositories,
        repository_count,
    ) catch |err| return mapIntegrationError(err);
    const problems_accepted = flagValue(raw_problems_accepted) catch
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    capturePending(value, .{
        .pool = @ptrCast(@alignCast(raw_pool orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER)),
        .native_solve = @ptrCast(@alignCast(raw_native_solve orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER)),
        .trace = trace orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER,
        .problems_accepted = problems_accepted,
        .unresolved_count = unresolved_count,
        .terminal_problem_kind = decodeTerminalProblemKind(
            raw_terminal_problem_kind,
        ) catch return error_codes.ERROR_TDNF_INVALID_PARAMETER,
        .repositories = repositories,
        .environment = environment orelse
            return error_codes.ERROR_TDNF_INVALID_PARAMETER,
    }) catch |err| return mapIntegrationError(err);
    return 0;
}

fn decodeTerminalProblemKind(raw: u32) error{InvalidProblemKind}!?transaction_plan.ProblemKind {
    if (raw == std.math.maxInt(u32)) return null;
    return switch (raw) {
        abi.problem_kind.conflict => .conflict,
        abi.problem_kind.installonly_limit => .installonly_limit,
        abi.problem_kind.no_candidate => .no_candidate,
        abi.problem_kind.not_installable => .not_installable,
        abi.problem_kind.obsoletes => .obsoletes,
        abi.problem_kind.protected_package => .protected_package,
        abi.problem_kind.unsatisfied_requirement => .unsatisfied_requirement,
        abi.problem_kind.same_name => .same_name,
        else => error.InvalidProblemKind,
    };
}

fn borrowedIntegrationRepositories(
    pointer: ?[*]const abi.IntegrationRepository,
    raw_count: u32,
) IntegrationError![]const abi.IntegrationRepository {
    const count: usize = raw_count;
    if (count == 0) return &.{};
    return (pointer orelse return error.InvalidRepository)[0..count];
}

comptime {
    @export(&stateSetEnabled, .{
        .name = "TDNFTransactionPlanStateSetEnabled",
        .visibility = .hidden,
    });
    @export(&stateIsEnabled, .{
        .name = "TDNFTransactionPlanStateIsEnabled",
        .visibility = .hidden,
    });
    @export(&initRepository, .{
        .name = "TDNFTransactionPlanInitRepository",
        .visibility = .hidden,
    });
    if (!integration_options.standalone_test) {
        @export(&reloadRepository, .{
            .name = "TDNFTransactionPlanReloadRepository",
            .visibility = .hidden,
        });
        @export(&refreshSack, .{
            .name = "TDNFTransactionPlanRefreshSack",
            .visibility = .hidden,
        });
        @export(&refreshSackFromHandle, .{
            .name = "TDNFRefreshSack",
            .visibility = .default,
        });
        @export(&refreshHandle, .{
            .name = "TDNFRefresh",
            .visibility = .default,
        });
        @export(&initRepo, .{
            .name = "TDNFInitRepo",
            .visibility = .default,
        });
        @export(&initRepoWithResult, .{
            .name = "TDNFInitRepoWithResult",
            .visibility = .hidden,
        });
        @export(&applySnapshot, .{
            .name = "TDNFApplySnapshot",
            .visibility = .default,
        });
        @export(&historyGoal, .{
            .name = "TDNFHistoryGoal",
            .visibility = .default,
        });
        @export(&historyGoalWithUnresolved, .{
            .name = "TDNFHistoryGoalWithUnresolved",
            .visibility = .hidden,
        });
    }
    @export(&stateRecordRepository, .{
        .name = "TDNFTransactionPlanStateRecordRepository",
        .visibility = .hidden,
    });
    @export(&stateRepositoryRecordCount, .{
        .name = "TDNFTransactionPlanStateRepositoryRecordCount",
        .visibility = .hidden,
    });
    @export(&stateFailNextRepositoryRecord, .{
        .name = "TDNFTransactionPlanStateFailNextRepositoryRecord",
        .visibility = .hidden,
    });
    @export(&stateFailNextCapture, .{
        .name = "TDNFTransactionPlanStateFailNextCapture",
        .visibility = .hidden,
    });
    @export(&stateFailNextCaptureIntegrity, .{
        .name = "TDNFTransactionPlanStateFailNextCaptureIntegrity",
        .visibility = .hidden,
    });
    @export(&stateClear, .{
        .name = "TDNFTransactionPlanStateClear",
        .visibility = .hidden,
    });
    @export(&statePublish, .{
        .name = "TDNFTransactionPlanStatePublish",
        .visibility = .hidden,
    });
    @export(&stateHasPendingProblem, .{
        .name = "TDNFTransactionPlanStateHasPendingProblem",
        .visibility = .hidden,
    });
    @export(&statePublishProblem, .{
        .name = "TDNFTransactionPlanStatePublishProblem",
        .visibility = .hidden,
    });
    @export(&stateDestroy, .{
        .name = "TDNFTransactionPlanStateDestroy",
        .visibility = .hidden,
    });
    @export(&stateGetCanonicalJson, .{
        .name = "TDNFTransactionPlanStateGetCanonicalJson",
        .visibility = .hidden,
    });
    @export(&stateFreeCanonicalJson, .{
        .name = "TDNFTransactionPlanStateFreeCanonicalJson",
        .visibility = .hidden,
    });
    if (!integration_options.standalone_test) {
        @export(&publicSetEnabled, .{
            .name = "TDNFTransactionPlanSetEnabled",
            .visibility = .default,
        });
        @export(&publicGetCanonicalJson, .{
            .name = "TDNFTransactionPlanGetCanonicalJson",
            .visibility = .default,
        });
        @export(&publicFreeCanonicalJson, .{
            .name = "TDNFTransactionPlanFreeCanonicalJson",
            .visibility = .default,
        });
        @export(&publicGetDigestHex, .{
            .name = "TDNFTransactionPlanGetDigestHex",
            .visibility = .default,
        });
        @export(&captureSetEnabled, .{
            .name = "TDNFTransactionPlanCaptureSetEnabled",
            .visibility = .hidden,
        });
        @export(&captureGetCanonicalJson, .{
            .name = "TDNFTransactionPlanCaptureGetCanonicalJson",
            .visibility = .hidden,
        });
        @export(&captureFailNextRepositoryRecord, .{
            .name = "TDNFTransactionPlanCaptureFailNextRepositoryRecord",
            .visibility = .hidden,
        });
        @export(&captureFailNextComposition, .{
            .name = "TDNFTransactionPlanCaptureFailNextComposition",
            .visibility = .hidden,
        });
        @export(&captureFailNextIntegrity, .{
            .name = "TDNFTransactionPlanCaptureFailNextIntegrity",
            .visibility = .hidden,
        });
        @export(&testFailNextReload, .{
            .name = "TDNFTransactionPlanTestFailNextReload",
            .visibility = .hidden,
        });
        @export(&testPoolIdentity, .{
            .name = "TDNFTransactionPlanTestPoolIdentity",
            .visibility = .hidden,
        });
        @export(&testPoolSolvableCount, .{
            .name = "TDNFTransactionPlanTestPoolSolvableCount",
            .visibility = .hidden,
        });
        @export(&testPoolRepoCount, .{
            .name = "TDNFTransactionPlanTestPoolRepoCount",
            .visibility = .hidden,
        });
        @export(&testRepoDataCount, .{
            .name = "TDNFTransactionPlanTestRepoDataCount",
            .visibility = .hidden,
        });
        @export(&testConsideredCount, .{
            .name = "TDNFTransactionPlanTestConsideredCount",
            .visibility = .hidden,
        });
        @export(&testConsideredIdentity, .{
            .name = "TDNFTransactionPlanTestConsideredIdentity",
            .visibility = .hidden,
        });
        @export(&testGrowCmdlineConsidered, .{
            .name = "TDNFTransactionPlanTestGrowCmdlineConsidered",
            .visibility = .hidden,
        });
        @export(&testRetireNullSack, .{
            .name = "TDNFTransactionPlanTestRetireNullSack",
            .visibility = .hidden,
        });
        @export(&testPublicInitRepo, .{
            .name = "TDNFTransactionPlanTestPublicInitRepo",
            .visibility = .hidden,
        });
        @export(&testReloadRepo, .{
            .name = "TDNFTransactionPlanTestReloadRepo",
            .visibility = .hidden,
        });
        @export(&testInitRepoInSack, .{
            .name = "TDNFTransactionPlanTestInitRepoInSack",
            .visibility = .hidden,
        });
        @export(&testRepoIdentity, .{
            .name = "TDNFTransactionPlanTestRepoIdentity",
            .visibility = .hidden,
        });
        @export(&testRepoId, .{
            .name = "TDNFTransactionPlanTestRepoId",
            .visibility = .hidden,
        });
        @export(&testRepoPackageCount, .{
            .name = "TDNFTransactionPlanTestRepoPackageCount",
            .visibility = .hidden,
        });
        @export(&testRepoBindingCount, .{
            .name = "TDNFTransactionPlanTestRepoBindingCount",
            .visibility = .hidden,
        });
        @export(&testRepoRecordCount, .{
            .name = "TDNFTransactionPlanTestRepoRecordCount",
            .visibility = .hidden,
        });
        @export(&testRepoRecordDigest, .{
            .name = "TDNFTransactionPlanTestRepoRecordDigest",
            .visibility = .hidden,
        });
        @export(&testInitRepoValidation, .{
            .name = "TDNFTransactionPlanTestInitRepoValidation",
            .visibility = .hidden,
        });
        @export(&testPoolIndexesHealthy, .{
            .name = "TDNFTransactionPlanTestPoolIndexesHealthy",
            .visibility = .hidden,
        });
        @export(&testEnableRepo, .{
            .name = "TDNFTransactionPlanTestEnableRepo",
            .visibility = .hidden,
        });
        @export(&testSackSnapshot, .{
            .name = "TDNFTransactionPlanTestSackSnapshot",
            .visibility = .hidden,
        });
    }
    @export(&integrationCapturePending, .{
        .name = "TDNFTransactionPlanIntegrationCapturePending",
        .visibility = .hidden,
    });
}

extern fn tdnf_rpm_config_create(root: ?[*:0]const u8) ?*anyopaque;
extern fn tdnf_rpm_config_destroy(config: ?*anyopaque) void;

const test_checksum =
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

const test_primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common"
    \\          xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="2">
    \\  <package type="rpm">
    \\    <name>app</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="2" ver="1" rel="3"/>
    \\    <checksum type="SHA256" pkgid="YES">aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</checksum>
    \\    <size package="321"/>
    \\    <location href="packages/app.rpm"/>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>file-consumer</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd</checksum>
    \\    <size package="111"/>
    \\    <location href="packages/file-consumer.rpm"/>
    \\    <format>
    \\      <rpm:requires><rpm:entry name="/usr/bin/app"/></rpm:requires>
    \\    </format>
    \\  </package>
    \\</metadata>
;

const test_filelists_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<filelists xmlns="http://linux.duke.edu/metadata/filelists" packages="1">
    \\  <package pkgid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    \\           name="app" arch="x86_64">
    \\    <version epoch="2" ver="1" rel="3"/>
    \\    <file>/usr/bin/app</file>
    \\  </package>
    \\</filelists>
;

const test_other_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<otherdata xmlns="http://linux.duke.edu/metadata/other" packages="1">
    \\  <package pkgid="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    \\           name="app" arch="x86_64">
    \\    <version epoch="2" ver="1" rel="3"/>
    \\    <changelog author="Tester" date="123">created</changelog>
    \\  </package>
    \\</otherdata>
;

const test_updateinfo_xml =
    \\<updates>
    \\  <update type="enhancement">
    \\    <id>UP-2026-0001</id>
    \\    <title>metadata-only advisory</title>
    \\    <issued date="2026-07-11 00:00:00"/>
    \\    <description/>
    \\  </update>
    \\</updates>
;

const TestCache = struct {
    tmp: std.testing.TmpDir,
    load_cookie_sha256: [32]u8,

    fn create() !TestCache {
        var self = TestCache{
            .tmp = std.testing.tmpDir(.{}),
            .load_cookie_sha256 = undefined,
        };
        errdefer self.tmp.cleanup();
        const primary_digest = digestHex(test_primary_xml);
        const filelists_digest = digestHex(test_filelists_xml);
        const other_digest = digestHex(test_other_xml);
        const updateinfo_digest = digestHex(test_updateinfo_xml);
        const repomd = try std.fmt.allocPrint(
            std.testing.allocator,
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
            \\  <revision>integration-revision</revision>
            \\  <data type="primary">
            \\    <checksum type="SHA256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/primary.xml"/>
            \\    <timestamp>77</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\  <data type="filelists">
            \\    <checksum type="sha256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/filelists.xml"/>
            \\    <timestamp>78</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\  <data type="other">
            \\    <checksum type="sha256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/other.xml"/>
            \\    <timestamp>79</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\  <data type="updateinfo">
            \\    <checksum type="sha256">{s}</checksum>
            \\    <open-checksum type="sha256">{s}</open-checksum>
            \\    <location href="repodata/updateinfo.xml"/>
            \\    <timestamp>80</timestamp>
            \\    <size>{d}</size>
            \\    <open-size>{d}</open-size>
            \\  </data>
            \\</repomd>
        ,
            .{
                &primary_digest,
                &primary_digest,
                test_primary_xml.len,
                test_primary_xml.len,
                &filelists_digest,
                &filelists_digest,
                test_filelists_xml.len,
                test_filelists_xml.len,
                &other_digest,
                &other_digest,
                test_other_xml.len,
                test_other_xml.len,
                &updateinfo_digest,
                &updateinfo_digest,
                test_updateinfo_xml.len,
                test_updateinfo_xml.len,
            },
        );
        defer std.testing.allocator.free(repomd);
        self.load_cookie_sha256 =
            repository_metadata.available_repository_loader.solvCacheCookie(
                repomd,
                .{
                    .include_filelists = true,
                    .include_updateinfo = true,
                    .include_other = true,
                },
            );
        try self.tmp.dir.createDirPath(
            std.testing.io,
            "cache-token=never-store/repodata",
        );
        try self.tmp.dir.createDirPath(std.testing.io, "root");
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "cache-token=never-store/repodata/repomd.xml",
            .data = repomd,
        });
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "cache-token=never-store/repodata/primary.xml",
            .data = test_primary_xml,
        });
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "cache-token=never-store/repodata/filelists.xml",
            .data = test_filelists_xml,
        });
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "cache-token=never-store/repodata/other.xml",
            .data = test_other_xml,
        });
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = "cache-token=never-store/repodata/updateinfo.xml",
            .data = test_updateinfo_xml,
        });
        return self;
    }

    fn cleanup(self: *TestCache) void {
        self.tmp.cleanup();
        self.* = undefined;
    }

    fn path(
        self: *const TestCache,
        buffer: *[std.Io.Dir.max_path_bytes]u8,
        suffix: []const u8,
    ) ![]u8 {
        return std.fmt.bufPrint(
            buffer,
            ".zig-cache/tmp/{s}/{s}",
            .{ &self.tmp.sub_path, suffix },
        );
    }
};

const TestUniverse = struct {
    pool: *c.Pool,

    fn create() !TestUniverse {
        const pool = c.pool_create() orelse return error.OutOfMemory;
        errdefer c.pool_free(pool);
        if (c.pool_setdisttype(pool, c.DISTTYPE_RPM) != 0) {
            return error.TestUnexpectedResult;
        }
        _ = c.pool_set_flag(
            pool,
            c.POOL_FLAG_ADDFILEPROVIDESFILTERED,
            1,
        );
        c.pool_setarch(pool, "x86_64");
        return .{ .pool = pool };
    }

    fn destroy(self: *TestUniverse) void {
        c.pool_free(self.pool);
        self.* = undefined;
    }

    fn addRepository(
        self: *TestUniverse,
        name: [:0]const u8,
        installed: bool,
        priority: i32,
    ) !*c.Repo {
        const raw = c.repo_create(self.pool, name) orelse
            return error.OutOfMemory;
        const repository: *c.Repo = @ptrCast(raw);
        repository.priority = priority;
        if (installed) c.pool_set_installed(self.pool, repository);
        return repository;
    }

    fn addPackage(
        self: *TestUniverse,
        repository: *c.Repo,
        name: [:0]const u8,
        evr: [:0]const u8,
        hnum: ?u32,
        location: [:0]const u8,
        size: u64,
    ) !c.Id {
        return self.addPackageChecksum(
            repository,
            name,
            evr,
            hnum,
            location,
            size,
            test_checksum,
        );
    }

    fn addPackageChecksum(
        self: *TestUniverse,
        repository: *c.Repo,
        name: [:0]const u8,
        evr: [:0]const u8,
        hnum: ?u32,
        location: [:0]const u8,
        size: u64,
        checksum: [:0]const u8,
    ) !c.Id {
        return self.addPackageChecksums(
            repository,
            name,
            evr,
            hnum,
            location,
            size,
            checksum,
            checksum,
        );
    }

    fn addPackageChecksums(
        self: *TestUniverse,
        repository: *c.Repo,
        name: [:0]const u8,
        evr: [:0]const u8,
        hnum: ?u32,
        location: [:0]const u8,
        size: u64,
        pkgid: [:0]const u8,
        checksum: [:0]const u8,
    ) !c.Id {
        const solvid = c.repo_add_solvable(repository);
        const solvable: *c.Solvable = @ptrCast(
            c.pool_id2solvable(self.pool, solvid) orelse
                return error.OutOfMemory,
        );
        solvable.name = c.pool_str2id(self.pool, name, 1);
        solvable.arch = c.pool_str2id(self.pool, "x86_64", 1);
        solvable.evr = c.pool_str2id(self.pool, evr, 1);
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
        const repodata = c.repo_add_repodata(repository, 0) orelse
            return error.OutOfMemory;
        if (hnum) |value| {
            c.solvable_set_num(solvable, c.RPM_RPMDBID, value);
        } else {
            c.repodata_set_checksum(
                repodata,
                solvid,
                c.SOLVABLE_CHECKSUM,
                c.REPOKEY_TYPE_SHA256,
                checksum,
            );
            c.repodata_set_checksum(
                repodata,
                solvid,
                c.SOLVABLE_PKGID,
                c.REPOKEY_TYPE_SHA256,
                pkgid,
            );
            c.repodata_set_location(repodata, solvid, 0, null, location);
            c.repodata_set_num(
                repodata,
                solvid,
                c.SOLVABLE_DOWNLOADSIZE,
                size,
            );
        }
        c.repodata_internalize(repodata);
        return solvid;
    }

    fn require(
        self: *TestUniverse,
        repository: *c.Repo,
        package: c.Id,
        name: [:0]const u8,
    ) !void {
        const solvable: *c.Solvable = @ptrCast(
            c.pool_id2solvable(self.pool, package) orelse
                return error.TestUnexpectedResult,
        );
        solvable.requires = c.repo_addid_dep(
            repository,
            solvable.requires,
            c.pool_str2id(self.pool, name, 1),
            0,
        );
    }

    fn setRequires(
        self: *TestUniverse,
        repository: *c.Repo,
        package: c.Id,
        normal: []const []const u8,
        prerequisites: []const []const u8,
    ) !void {
        const solvable: *c.Solvable = @ptrCast(
            c.pool_id2solvable(self.pool, package) orelse
                return error.TestUnexpectedResult,
        );
        const count = normal.len + prerequisites.len +
            @intFromBool(prerequisites.len != 0);
        solvable.requires = c.repo_reserve_ids(
            repository,
            0,
            @intCast(count),
        );
        var output = repository.idarraydata + solvable.requires;
        for (normal) |name| {
            output[0] = c.pool_strn2id(
                self.pool,
                name.ptr,
                @intCast(name.len),
                1,
            );
            output += 1;
        }
        if (prerequisites.len != 0) {
            output[0] = c.SOLVABLE_PREREQMARKER;
            output += 1;
        }
        for (prerequisites) |name| {
            output[0] = c.pool_strn2id(
                self.pool,
                name.ptr,
                @intCast(name.len),
                1,
            );
            output += 1;
        }
        output[0] = 0;
        repository.idarraysize += @intCast(count + 1);
    }

    fn setProvides(
        self: *TestUniverse,
        repository: *c.Repo,
        package: c.Id,
        explicit: []const []const u8,
        generated_files: []const []const u8,
    ) !void {
        const solvable: *c.Solvable = @ptrCast(
            c.pool_id2solvable(self.pool, package) orelse
                return error.TestUnexpectedResult,
        );
        const count = explicit.len + generated_files.len +
            @intFromBool(generated_files.len != 0);
        solvable.provides = c.repo_reserve_ids(
            repository,
            0,
            @intCast(count),
        );
        var output = repository.idarraydata + solvable.provides;
        for (explicit) |name| {
            output[0] = c.pool_strn2id(
                self.pool,
                name.ptr,
                @intCast(name.len),
                1,
            );
            output += 1;
        }
        if (generated_files.len != 0) {
            output[0] = c.SOLVABLE_FILEMARKER;
            output += 1;
        }
        for (generated_files) |name| {
            output[0] = c.pool_strn2id(
                self.pool,
                name.ptr,
                @intCast(name.len),
                1,
            );
            output += 1;
        }
        output[0] = 0;
        repository.idarraysize += @intCast(count + 1);
    }

    fn provide(
        self: *TestUniverse,
        repository: *c.Repo,
        package: c.Id,
        name: [:0]const u8,
    ) !void {
        const solvable: *c.Solvable = @ptrCast(
            c.pool_id2solvable(self.pool, package) orelse
                return error.TestUnexpectedResult,
        );
        solvable.provides = c.repo_addid_dep(
            repository,
            solvable.provides,
            c.pool_str2id(self.pool, name, 1),
            0,
        );
    }

    fn requireRichFile(
        self: *TestUniverse,
        repository: *c.Repo,
        package: c.Id,
        file: [:0]const u8,
        companion: [:0]const u8,
    ) !void {
        const solvable: *c.Solvable = @ptrCast(
            c.pool_id2solvable(self.pool, package) orelse
                return error.TestUnexpectedResult,
        );
        const relation = c.pool_rel2id(
            self.pool,
            c.pool_str2id(self.pool, file, 1),
            c.pool_str2id(self.pool, companion, 1),
            c.REL_AND,
            1,
        );
        solvable.requires = c.repo_addid_dep(
            repository,
            solvable.requires,
            relation,
            0,
        );
    }

    fn addFile(
        self: *TestUniverse,
        repository: *c.Repo,
        package: c.Id,
        directory: [:0]const u8,
        basename: [:0]const u8,
    ) !void {
        const repodata = c.repo_add_repodata(repository, 0) orelse
            return error.OutOfMemory;
        const dir_id = c.repodata_str2dir(repodata, directory, 1);
        c.repodata_add_dirstr(
            repodata,
            package,
            c.SOLVABLE_FILELIST,
            dir_id,
            basename,
        );
        c.repodata_internalize(repodata);
        _ = self;
    }

    fn finish(self: *TestUniverse, repositories: []const *c.Repo) void {
        for (repositories) |repository| c.repo_internalize(repository);
        c.pool_createwhatprovides(self.pool);
    }
};

const TestNativeSolve = struct {
    retained: *repository_metadata.RetainedSolve,
    app: solver_model.PackageId,
    local: solver_model.PackageId,

    fn create(
        allocator: Allocator,
        available: *const metadata_model.RepositoryModel,
        cache_repository_id: []const u8,
        cache_priority: i32,
        local_checksum: []const u8,
        excluded_checksum: []const u8,
    ) !TestNativeSolve {
        const retained = try allocator.create(repository_metadata.RetainedSolve);
        errdefer allocator.destroy(retained);

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();
        const arena = arena_state.allocator();

        const command_line_packages = try arena.alloc(metadata_model.Package, 3);
        command_line_packages[0] = testNativePackage(
            "local",
            "4",
            "5",
            local_checksum,
            99,
        );
        command_line_packages[1] = testNativePackage(
            "excluded-local",
            "1",
            "1",
            local_checksum,
            77,
        );
        command_line_packages[2] = testNativePackage(
            "excluded-local",
            "1",
            "1",
            excluded_checksum,
            78,
        );
        const command_line_model = try arena.create(
            metadata_model.RepositoryModel,
        );
        command_line_model.* = .{ .packages = command_line_packages };

        const repositories = try arena.alloc(solver_model.RepositoryInput, 3);
        repositories[0] = .{
            .id = cache_repository_id,
            .model = available,
            .priority = cache_priority,
            .cost = default_repository_cost,
        };
        repositories[1] = .{
            .id = "extras",
            .model = available,
            .priority = 20,
            .cost = default_repository_cost,
        };
        repositories[2] = .{
            .id = solver_live.cmdline_repository_id,
            .model = command_line_model,
            .kind = .command_line,
        };

        const universe = try arena.create(solver_model.Universe);
        universe.* = try solver_model.Universe.init(arena, repositories);
        const app = try findNativePackage(
            universe,
            cache_repository_id,
            "app",
            test_checksum,
        );
        const local = try findNativePackage(
            universe,
            solver_live.cmdline_repository_id,
            "local",
            local_checksum,
        );
        const excluded = try findNativePackage(
            universe,
            solver_live.cmdline_repository_id,
            "excluded-local",
            local_checksum,
        );
        const excluded_twin = try findNativePackage(
            universe,
            solver_live.cmdline_repository_id,
            "excluded-local",
            excluded_checksum,
        );

        const jobs = try arena.alloc(solver_model.Job, 2);
        jobs[0] = .{
            .action = .install,
            .selection = .{ .package = app },
            .reason = .user,
        };
        jobs[1] = .{
            .action = .install,
            .selection = .{ .package = local },
            .reason = .user,
        };
        const job_origins = try arena.alloc(?u32, 2);
        job_origins[0] = 0;
        job_origins[1] = 1;
        const hidden = try arena.alloc(solver_model.PackageId, 2);
        hidden[0] = excluded;
        hidden[1] = excluded_twin;

        var result_arena_state = std.heap.ArenaAllocator.init(allocator);
        errdefer result_arena_state.deinit();
        const result_arena = result_arena_state.allocator();
        const selected = try result_arena.alloc(solver_model.PackageId, 2);
        selected[0] = app;
        selected[1] = local;
        const actions = try result_arena.alloc(solver_model.Action, 2);
        actions[0] = .{
            .package = app,
            .kind = .install,
            .reason = .user,
            .requested_by = @enumFromInt(0),
        };
        actions[1] = .{
            .package = local,
            .kind = .install,
            .reason = .user,
            .requested_by = @enumFromInt(1),
        };
        const result = solver_result.OwnedResult{
            .arena_state = result_arena_state,
            .selected = selected,
            .outcome = .{
                .actions = actions,
                .problems = &.{},
                .skipped_jobs = &.{},
            },
        };

        retained.* = .{ .solved = .{
            .arena_state = arena_state,
            .universe = universe,
            .solved = .{
                .universe = universe,
                .result = result,
                .effective_job_count = jobs.len,
            },
            .jobs = jobs,
            .hidden = hidden,
            .job_origins = job_origins,
        } };
        return .{
            .retained = retained,
            .app = app,
            .local = local,
        };
    }

    fn destroy(self: *TestNativeSolve, allocator: Allocator) void {
        self.retained.deinit();
        allocator.destroy(self.retained);
        self.* = undefined;
    }
};

fn testNativePackage(
    name: []const u8,
    version: []const u8,
    release: []const u8,
    checksum: []const u8,
    size: u64,
) metadata_model.Package {
    return .{
        .pkg_id = checksum,
        .nevra = .{
            .name = name,
            .version = version,
            .release = release,
            .arch = "x86_64",
        },
        .checksum = .{
            .kind = "sha256",
            .value = checksum,
            .is_pkgid = true,
        },
        .size = .{ .package = size },
        .location = .{ .href = name },
    };
}

fn findNativePackage(
    universe: *const solver_model.Universe,
    repository_name: []const u8,
    package_name: []const u8,
    checksum: []const u8,
) !solver_model.PackageId {
    for (universe.packages) |package| {
        const repository = universe.repository(package.repository) orelse
            return error.TestUnexpectedResult;
        if (std.mem.eql(u8, repository.name, repository_name) and
            std.mem.eql(u8, package.source.nevra.name, package_name) and
            std.mem.eql(u8, package.source.checksum.value, checksum))
        {
            return package.id;
        }
    }
    return error.TestUnexpectedResult;
}

fn digestHex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var output: [64]u8 = undefined;
    const alphabet = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        output[index * 2] = alphabet[byte >> 4];
        output[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return output;
}

fn queueValues(queue: *const c.Queue) []const i32 {
    if (queue.count == 0) return &.{};
    return queue.elements[0..@intCast(queue.count)];
}

fn modelPackageByName(
    model: *const transaction_plan.Data,
    name: []const u8,
) ?*const transaction_plan.Package {
    for (model.packages) |*package| {
        if (std.mem.eql(u8, package.identity.name, name)) return package;
    }
    return null;
}

fn modelRepositoryByKind(
    model: *const transaction_plan.Data,
    kind: transaction_plan.RepositoryKind,
) ?*const transaction_plan.Repository {
    for (model.repositories) |*repository| {
        if (repository.kind == kind) return repository;
    }
    return null;
}

fn findSolvableByName(
    pool: *c.Pool,
    repository: *c.Repo,
    name: []const u8,
) !c.Id {
    var solvid = repository.start;
    while (solvid < repository.end) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse continue;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo != repository) continue;
        const raw_name = c.pool_id2str(pool, solvable.name) orelse continue;
        if (std.mem.eql(u8, std.mem.span(raw_name), name)) return solvid;
    }
    return error.TestUnexpectedResult;
}

fn poolHasPlainRequirement(pool: *c.Pool, expected: []const u8) bool {
    var solvid: c.Id = 2;
    while (solvid < pool.nsolvables) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse continue;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo == null) continue;
        var dependencies: c.Queue = undefined;
        c.queue_init(&dependencies);
        defer c.queue_free(&dependencies);
        _ = c.solvable_lookup_deparray(
            solvable,
            c.SOLVABLE_REQUIRES,
            &dependencies,
            0,
        );
        if (dependencies.count == 0) continue;
        for (dependencies.elements[0..@intCast(dependencies.count)]) |id| {
            const value = c.pool_dep2str(pool, id) orelse continue;
            if (std.mem.eql(u8, std.mem.span(value), expected)) return true;
        }
    }
    return false;
}

fn testSolverPackageDigest(
    pool: *c.Pool,
    solvid: c.Id,
) ![32]u8 {
    var context = try SolverDigestContext.init(
        std.testing.allocator,
        pool,
    );
    defer context.deinit();
    return solverPackageDigest(&context, solvid);
}

test "minimum versions use production u32 epoch semantics" {
    const maximum = try parseMinVersion("pkg=4294967295:2-3");
    try std.testing.expectEqual(
        @as(?u64, std.math.maxInt(u32)),
        maximum.epoch,
    );
    try std.testing.expectEqualStrings("2", maximum.version);
    try std.testing.expectEqualStrings("3", maximum.release.?);

    const overflow = try parseMinVersion("pkg=4294967296:2-3");
    try std.testing.expectEqual(@as(?u64, null), overflow.epoch);
    try std.testing.expectEqualStrings("4294967296:2", overflow.version);
    try std.testing.expectEqualStrings("3", overflow.release.?);
    const epoch_only = try parseMinVersion("pkg=1:");
    try std.testing.expectEqual(@as(?u64, 1), epoch_only.epoch);
    try std.testing.expectEqualStrings("", epoch_only.version);
    try std.testing.expectEqual(@as(?[]const u8, null), epoch_only.release);
}

test "rpmdb epoch zero uses production absent-epoch normalization" {
    try std.testing.expectEqual(
        @as(?u32, null),
        repository_metadata.solv_bridge.normalizeRpmEpoch(0),
    );
    try std.testing.expectEqual(
        @as(?u32, 1),
        repository_metadata.solv_bridge.normalizeRpmEpoch(1),
    );
}

test "solv cache identity binds every optional metadata mask" {
    const loader = repository_metadata.available_repository_loader;
    const base = loader.solvCacheCookie(
        "repomd",
        .{ .include_filelists = false },
    );
    const filelists = loader.solvCacheCookie(
        "repomd",
        .{ .include_filelists = true },
    );
    const updateinfo = loader.solvCacheCookie(
        "repomd",
        .{ .include_updateinfo = true },
    );
    const other = loader.solvCacheCookie(
        "repomd",
        .{ .include_other = true },
    );
    try std.testing.expect(!std.mem.eql(u8, &base, &filelists));
    try std.testing.expect(!std.mem.eql(u8, &base, &updateinfo));
    try std.testing.expect(!std.mem.eql(u8, &base, &other));
    try std.testing.expect(!std.mem.eql(u8, &filelists, &updateinfo));
}

test "integration error mapping preserves OOM and repository integrity" {
    try std.testing.expectEqual(
        error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        mapIntegrationError(error.OutOfMemory),
    );
    try std.testing.expectEqual(
        error_codes.ERROR_TDNF_REPO_PERFORM,
        mapIntegrationError(error.RepositoryIntegrityMismatch),
    );
    try std.testing.expectEqual(
        error_codes.ERROR_TDNF_INVALID_PARAMETER,
        mapIntegrationError(error.InvalidRepository),
    );
}

test "protected terminal references only forbidden transaction actions" {
    const packages = [_]transaction_plan.Package{
        .{
            .id = "allowed-old",
            .identity = .{
                .arch = "x86_64",
                .epoch = null,
                .name = "protected-upgrade",
                .release = "1",
                .version = "1",
            },
            .repository_id = "@System",
            .rpmdb_hnum = 1,
            .source = null,
            .state = .installed,
        },
        .{
            .id = "allowed-new",
            .identity = .{
                .arch = "x86_64",
                .epoch = null,
                .name = "protected-upgrade",
                .release = "1",
                .version = "2",
            },
            .repository_id = "base",
            .rpmdb_hnum = null,
            .source = null,
            .state = .available,
        },
        .{
            .id = "forbidden-old",
            .identity = .{
                .arch = "x86_64",
                .epoch = null,
                .name = "protected-obsolete",
                .release = "1",
                .version = "1",
            },
            .repository_id = "@System",
            .rpmdb_hnum = 2,
            .source = null,
            .state = .installed,
        },
        .{
            .id = "replacement",
            .identity = .{
                .arch = "x86_64",
                .epoch = null,
                .name = "replacement",
                .release = "1",
                .version = "1",
            },
            .repository_id = "base",
            .rpmdb_hnum = null,
            .source = null,
            .state = .available,
        },
        .{
            .id = "forbidden-erase",
            .identity = .{
                .arch = "x86_64",
                .epoch = null,
                .name = "protected-erase",
                .release = "1",
                .version = "1",
            },
            .repository_id = "@System",
            .rpmdb_hnum = 3,
            .source = null,
            .state = .installed,
        },
    };
    const allowed_upgrade = transaction_plan.Action{
        .kind = .upgrade,
        .prior_package_ids = &.{"allowed-old"},
        .reason = .user,
        .requested_by_job_id = "allowed-job",
        .target_package_id = "allowed-new",
    };
    var data = transaction_plan.Data{
        .actions = &.{},
        .environment = .{
            .architecture = "x86_64",
            .distro = "test",
            .policy = .{
                .allow_erasing = true,
                .allow_multilib = true,
                .all_deps = false,
                .best = false,
                .clean_requirements_on_remove = false,
                .excludes = &.{},
                .force_architecture = null,
                .include_installed = true,
                .installonly_limit = 3,
                .installonly_names = &.{},
                .install_weak_dependencies = true,
                .keep_orphans = true,
                .locked_names = &.{},
                .min_versions = &.{},
                .protected_names = &.{
                    "protected-upgrade",
                    "protected-obsolete",
                    "protected-erase",
                },
                .skip_broken = false,
            },
            .releasever = "1",
            .resolution_status = .resolved,
            .rpmdb = .{
                .backend = .sqlite,
                .cookie_sha256 = "",
                .package_set_sha256 = "",
            },
        },
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &packages,
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{},
        .skipped = &.{},
    };
    data.actions = &.{
        allowed_upgrade,
        .{
            .kind = .obsolete,
            .prior_package_ids = &.{"forbidden-old"},
            .reason = .obsoletes,
            .requested_by_job_id = "obsolete-job",
            .target_package_id = "replacement",
        },
    };
    var reference = terminalProblemReference(data, .protected_package);
    try std.testing.expectEqualStrings("obsolete-job", reference.job_id.?);
    try std.testing.expectEqualStrings(
        "forbidden-old",
        reference.package_id.?,
    );

    data.actions = &.{
        allowed_upgrade,
        .{
            .kind = .erase,
            .prior_package_ids = &.{},
            .reason = .user,
            .requested_by_job_id = "erase-job",
            .target_package_id = "forbidden-erase",
        },
    };
    reference = terminalProblemReference(data, .protected_package);
    try std.testing.expectEqualStrings("erase-job", reference.job_id.?);
    try std.testing.expectEqualStrings(
        "forbidden-erase",
        reference.package_id.?,
    );
}

fn repositoryRecordAllocationCase(allocator: Allocator) !void {
    const state = try State.create(allocator);
    defer state.destroy();
    state.setEnabled(true);
    const repository: *anyopaque = @ptrFromInt(0x1000);
    const refresh_owner: *anyopaque = @ptrFromInt(0x4000);
    try state.recordRepository(repository, [_]u8{1} ** 32, .{});
    try state.beginRepositoryRefresh(refresh_owner);
    try state.recordRepository(repository, [_]u8{2} ** 32, .{});
    try std.testing.expectEqual(
        [_]u8{2} ** 32,
        state.repositoryRecord(repository).?.cookie_sha256,
    );
    state.rollbackRepositoryRefresh(refresh_owner);
    try std.testing.expectEqual(@as(usize, 1), state.repository_records.items.len);
    try std.testing.expectEqual(
        [_]u8{1} ** 32,
        state.repositoryRecord(repository).?.cookie_sha256,
    );
    try state.beginRepositoryRefresh(refresh_owner);
    try state.recordRepository(repository, [_]u8{2} ** 32, .{});
    state.commitRepositoryRefresh(refresh_owner);
    try std.testing.expectEqual(@as(usize, 1), state.repository_records.items.len);
    try std.testing.expectEqual(
        [_]u8{2} ** 32,
        state.repositoryRecord(repository).?.cookie_sha256,
    );
    const replacement: *anyopaque = @ptrFromInt(0x2000);
    try state.replaceRepositoryRecord(
        repository,
        replacement,
        [_]u8{3} ** 32,
        .{},
    );
    try std.testing.expect(state.repositoryRecord(repository) == null);
    try std.testing.expectEqual(
        [_]u8{3} ** 32,
        state.repositoryRecord(replacement).?.cookie_sha256,
    );
    const rebound: *anyopaque = @ptrFromInt(0x3000);
    state.rebindRepository(replacement, rebound);
    try std.testing.expect(state.repositoryRecord(replacement) == null);
    try std.testing.expect(state.repositoryRecord(rebound) != null);
}

test "repository record OOM propagates without poisoning refresh state" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        repositoryRecordAllocationCase,
        .{},
    );
}

test "authoritative plan is stored, fail-closed, and owned past teardown" {
    var cache = try TestCache.create();
    var cache_live = true;
    defer if (cache_live) cache.cleanup();
    var cache_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cache_path = try cache.path(
        &cache_path_buffer,
        "cache-token=never-store",
    );
    const cache_path_z = try std.testing.allocator.dupeZ(u8, cache_path);
    defer std.testing.allocator.free(cache_path_z);
    var root_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_path = try cache.path(&root_path_buffer, "root");
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    switch (std.os.linux.errno(std.os.linux.getcwd(
        cwd_buffer[0..].ptr,
        cwd_buffer.len,
    ))) {
        .SUCCESS => {},
        else => return error.TestUnexpectedResult,
    }
    const cwd_length = std.mem.findScalar(u8, &cwd_buffer, 0) orelse
        return error.TestUnexpectedResult;
    const root_path_z = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/{s}",
        .{ cwd_buffer[0..cwd_length], root_path },
        0,
    );
    defer std.testing.allocator.free(root_path_z);
    const rpm_config = tdnf_rpm_config_create(root_path_z.ptr) orelse
        return error.TestUnexpectedResult;
    var config_live = true;
    defer if (config_live) tdnf_rpm_config_destroy(rpm_config);

    var universe = try TestUniverse.create();
    var universe_live = true;
    defer if (universe_live) universe.destroy();
    const installed = try universe.addRepository("@System", true, 0);
    const available = try universe.addRepository("base", false, -10);
    const unreferenced = try universe.addRepository("extras", false, -20);
    const command_line = try universe.addRepository("@cmdline", false, 0);
    var live_metadata_arena = std.heap.ArenaAllocator.init(
        std.testing.allocator,
    );
    defer live_metadata_arena.deinit();
    const live_metadata = try repository_metadata.available_repository_loader
        .loadCacheModelWithRepomd(
        live_metadata_arena.allocator(),
        cache_path,
        .{
            .include_filelists = true,
            .include_updateinfo = true,
            .include_other = true,
        },
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        live_metadata.repository.advisories.len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        live_metadata.repository.changelogs.len,
    );
    try repository_metadata.solv_bridge.buildRepositoryIntoRepo(
        live_metadata_arena.allocator(),
        available,
        &live_metadata.repository,
    );
    try repository_metadata.solv_bridge.buildRepositoryIntoRepo(
        live_metadata_arena.allocator(),
        unreferenced,
        &live_metadata.repository,
    );
    const app = try findSolvableByName(universe.pool, available, "app");
    const local = try universe.addPackage(
        command_line,
        "local",
        "4-5",
        null,
        "/credential-cache/private/local.rpm",
        99,
    );
    const excluded_local = try universe.addPackage(
        command_line,
        "excluded-local",
        "1-1",
        null,
        "/credential-cache/private/excluded-local.rpm",
        77,
    );
    const excluded_local_twin = try universe.addPackageChecksum(
        command_line,
        "excluded-local",
        "1-1",
        null,
        "/credential-cache/private/excluded-local-twin.rpm",
        78,
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    );
    universe.finish(&.{ installed, available, unreferenced, command_line });
    c.pool_addfileprovides(universe.pool);
    c.pool_createwhatprovides(universe.pool);

    const jobs = [_]i32{
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        app,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        local,
    };

    const request_trace = @import("transaction_plan_request_trace");
    var trace = request_trace.Trace.init(std.testing.allocator);
    var trace_live = true;
    defer if (trace_live) trace.deinit();
    const app_request = try trace.addRequest(
        abi.request_kind.install,
        "app",
        false,
    );
    try trace.recordPackageJob(
        0,
        abi.job_action.install,
        app,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        0,
        abi.request_reason.user,
        app_request,
    );
    const local_request = try trace.addRequest(
        abi.request_kind.install,
        "/credential-cache/private/local.rpm",
        true,
    );
    try trace.recordPackageJob(
        1,
        abi.job_action.install,
        local,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        0,
        abi.request_reason.user,
        local_request,
    );
    const excluded_glob_request = try trace.addRequest(
        abi.request_kind.install,
        "excluded-local*",
        false,
    );
    const excluded_glob_ids = [_]i32{
        excluded_local_twin,
        excluded_local,
        excluded_local_twin,
    };
    try trace.recordGoalRange(
        &excluded_glob_ids,
        0,
        excluded_glob_ids.len,
        5,
        abi.request_reason.user,
        excluded_glob_request,
    );
    for (excluded_glob_ids) |selection_id| {
        try trace.commitGoal(
            selection_id,
            5,
            &jobs,
            jobs.len,
            jobs.len,
        );
    }
    const excluded_capability_request = try trace.addRequest(
        abi.request_kind.install,
        "virtual(excluded-local)",
        false,
    );
    const excluded_capability_ids = [_]i32{
        excluded_local,
        excluded_local_twin,
    };
    try trace.recordGoalRange(
        &excluded_capability_ids,
        0,
        excluded_capability_ids.len,
        5,
        abi.request_reason.user,
        excluded_capability_request,
    );
    for (excluded_capability_ids) |selection_id| {
        try trace.commitGoal(
            selection_id,
            5,
            &jobs,
            jobs.len,
            jobs.len,
        );
    }
    try trace.recordPolicies(
        &.{ "ignored-*", "ignored-*" },
        &.{ "kernel", "kernel" },
        &.{},
        &.{
            "unrelated=1:2-3",
            "unrelated=1:2-3",
            "unrelated=1:3-1",
            "epoch-only=1:",
        },
        &.{ "protected-package", "protected-package" },
        false,
    );
    try trace.finalize(
        &jobs,
        c.SOLVER_CLEANDEPS,
        c.SOLVER_FORCEBEST,
    );

    var solved = try TestNativeSolve.create(
        std.testing.allocator,
        &live_metadata.repository,
        "base",
        10,
        test_checksum,
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    );
    var solved_live = true;
    defer if (solved_live) solved.destroy(std.testing.allocator);
    var exclude_values = [_]?[*:0]const u8{
        "ignored-*",
        "ignored-*",
        null,
    };
    var installonly_values = [_]?[*:0]const u8{
        "kernel",
        "kernel",
        null,
    };
    var min_version_values = [_]?[*:0]const u8{
        "unrelated=1:2-3",
        "unrelated=1:2-3",
        "unrelated=1:3-1",
        "epoch-only=1:",
        null,
    };
    var protected_values = [_]?[*:0]const u8{
        "protected-package",
        "protected-package",
        null,
    };
    const environment = abi.IntegrationEnvironment{
        .architecture = "x86_64",
        .distro = "integration-os",
        .releasever = "9",
        .force_architecture = "x86_64",
        .excludes = &exclude_values,
        .installonly_names = &installonly_values,
        .min_versions = &min_version_values,
        .protected_names = &protected_values,
        .rpm_config = rpm_config,
        .installonly_limit = 3,
        .allow_multilib = 1,
        .include_installed = 1,
        .install_weak_dependencies = 1,
        .keep_orphans = 1,
    };
    const repositories = [_]abi.IntegrationRepository{
        .{
            .repository = available,
            .id = "base",
            .cache_dir = cache_path_z.ptr,
            .priority = 10,
            .cost = default_repository_cost,
        },
        .{
            .repository = unreferenced,
            .id = "extras",
            .cache_dir = cache_path_z.ptr,
            .priority = 20,
            .cost = default_repository_cost,
        },
    };
    const input = Input{
        .pool = universe.pool,
        .native_solve = solved.retained,
        .trace = trace.getView().?,
        .problems_accepted = false,
        .unresolved_count = 0,
        .repositories = &repositories,
        .environment = &environment,
    };

    var state_storage: ?*State = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        stateSetEnabled(&state_storage, 1),
    );
    const state = state_storage.?;
    var state_live = true;
    defer if (state_live) stateDestroy(state_storage);
    try state.recordRepository(
        available,
        cache.load_cookie_sha256,
        .{
            .include_filelists = true,
            .include_updateinfo = true,
            .include_other = true,
        },
    );
    try state.recordRepository(
        unreferenced,
        cache.load_cookie_sha256,
        .{
            .include_filelists = true,
            .include_updateinfo = true,
            .include_other = true,
        },
    );
    try capturePending(state, input);
    try std.testing.expect(state.model() == null);
    try std.testing.expectError(
        error.NoPlan,
        state.canonicalJsonAlloc(std.testing.allocator),
    );
    try std.testing.expectEqual(@as(u32, 0), statePublish(state));
    const model = state.model().?;
    try std.testing.expectEqual(@as(usize, 2), model.actions.len);
    try std.testing.expectEqual(@as(usize, 2), model.selected.len);
    try std.testing.expectEqualStrings("x86_64", model.environment.architecture);
    try std.testing.expectEqualStrings("integration-os", model.environment.distro);
    try std.testing.expectEqualStrings("9", model.environment.releasever);
    try std.testing.expectEqualStrings(
        "x86_64",
        model.environment.policy.force_architecture.?,
    );
    try std.testing.expectEqual(@as(u32, 3), model.environment.policy.installonly_limit);
    try std.testing.expectEqual(
        @as(usize, 1),
        model.environment.policy.excludes.len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        model.environment.policy.installonly_names.len,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        model.environment.policy.min_versions.len,
    );
    try std.testing.expectEqualStrings(
        "unrelated",
        model.environment.policy.min_versions[0].name,
    );
    try std.testing.expectEqualStrings(
        "",
        model.environment.policy.min_versions[2].version,
    );
    try std.testing.expectEqual(@as(usize, 64), model.environment.rpmdb.cookie_sha256.len);
    try std.testing.expectEqual(@as(usize, 64), model.environment.rpmdb.package_set_sha256.len);
    const expected_cookie_sha256 = digestHex("0:0");
    try std.testing.expectEqualStrings(
        &expected_cookie_sha256,
        model.environment.rpmdb.cookie_sha256,
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        model.environment.rpmdb.cookie_sha256,
        model.environment.rpmdb.package_set_sha256,
    ));

    const available_model = modelRepositoryByKind(model, .available).?;
    try std.testing.expectEqual(@as(i32, 10), available_model.priority);
    try std.testing.expectEqual(@as(u32, 1000), available_model.cost);
    try std.testing.expectEqualStrings(
        "integration-revision",
        available_model.repomd.?.revision.?,
    );
    try std.testing.expect(available_model.snapshot != null);
    try std.testing.expect(modelRepositoryByKind(model, .installed) == null);
    try std.testing.expect(modelRepositoryByKind(model, .command_line) != null);
    try std.testing.expect(findRepository(model.repositories, "extras") != null);
    const app_model = modelPackageByName(model, "app").?;
    try std.testing.expectEqualStrings("SHA256", app_model.source.?.checksum.kind);
    try std.testing.expectEqualStrings(
        "packages/app.rpm",
        app_model.source.?.location.?.href,
    );
    try std.testing.expectEqual(@as(?u64, 321), app_model.source.?.size);
    const local_model = modelPackageByName(model, "local").?;
    try std.testing.expect(local_model.source.?.location == null);
    var glob_package_ids: [2][]const u8 = undefined;
    var glob_package_count: usize = 0;
    var capability_package_ids: [2][]const u8 = undefined;
    var capability_package_count: usize = 0;
    for (model.jobs) |job| {
        if (job.request_id) |request_id| {
            if (std.mem.eql(
                u8,
                request_id,
                model.requests[2].id,
            )) {
                if (glob_package_count >= glob_package_ids.len)
                    return error.TestUnexpectedResult;
                glob_package_ids[glob_package_count] = job.selection.package;
                glob_package_count += 1;
            } else if (std.mem.eql(
                u8,
                request_id,
                model.requests[3].id,
            )) {
                if (capability_package_count >= capability_package_ids.len)
                    return error.TestUnexpectedResult;
                capability_package_ids[capability_package_count] =
                    job.selection.package;
                capability_package_count += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 2), glob_package_count);
    try std.testing.expectEqual(@as(usize, 2), capability_package_count);
    try std.testing.expect(!std.mem.eql(
        u8,
        glob_package_ids[0],
        glob_package_ids[1],
    ));
    for (glob_package_ids) |package_id| {
        const matched = for (capability_package_ids) |capability_package_id| {
            if (std.mem.eql(u8, package_id, capability_package_id))
                break true;
        } else false;
        try std.testing.expect(matched);
    }
    var saw_original_checksum = false;
    var saw_twin_checksum = false;
    for (glob_package_ids) |package_id| {
        const package = for (model.packages) |candidate| {
            if (std.mem.eql(u8, package_id, candidate.id)) break candidate;
        } else return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(
            "excluded-local",
            package.identity.name,
        );
        try std.testing.expect(package.source.?.location == null);
        if (std.mem.eql(
            u8,
            package.source.?.checksum.value,
            test_checksum,
        )) {
            saw_original_checksum = true;
        } else if (std.mem.eql(
            u8,
            package.source.?.checksum.value,
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        )) {
            saw_twin_checksum = true;
        } else {
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expect(saw_original_checksum);
    try std.testing.expect(saw_twin_checksum);
    try std.testing.expectEqualStrings(
        "excluded-local*",
        model.requests[2].subject.?,
    );
    try std.testing.expectEqualStrings(
        "virtual(excluded-local)",
        model.requests[3].subject.?,
    );
    const outcome_json = try state.canonicalJsonAlloc(
        std.testing.allocator,
    );
    defer std.testing.allocator.free(outcome_json);
    var outcome_document = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        outcome_json,
        .{},
    );
    defer outcome_document.deinit();
    const outcome_object = outcome_document.value.object;
    var glob_request_id: ?[]const u8 = null;
    var capability_request_id: ?[]const u8 = null;
    for (outcome_object.get("requests").?.array.items) |request| {
        const subject = request.object.get("subject").?;
        if (subject == .string and
            std.mem.eql(u8, subject.string, "excluded-local*"))
        {
            glob_request_id = request.object.get("id").?.string;
        } else if (subject == .string and
            std.mem.eql(u8, subject.string, "virtual(excluded-local)"))
        {
            capability_request_id = request.object.get("id").?.string;
        }
    }
    try std.testing.expect(glob_request_id != null);
    try std.testing.expect(capability_request_id != null);
    var noop_job_ids: [4][]const u8 = undefined;
    var noop_job_count: usize = 0;
    var canonical_glob_count: usize = 0;
    var canonical_capability_count: usize = 0;
    for (outcome_object.get("jobs").?.array.items) |job| {
        const request_id = job.object.get("request_id").?;
        if (request_id != .string) continue;
        const is_glob = std.mem.eql(
            u8,
            request_id.string,
            glob_request_id.?,
        );
        const is_capability = std.mem.eql(
            u8,
            request_id.string,
            capability_request_id.?,
        );
        if (!is_glob and !is_capability) continue;
        try std.testing.expectEqualStrings(
            "package",
            job.object.get("selection").?.object.get("kind").?.string,
        );
        noop_job_ids[noop_job_count] = job.object.get("id").?.string;
        noop_job_count += 1;
        if (is_glob) canonical_glob_count += 1;
        if (is_capability) canonical_capability_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), canonical_glob_count);
    try std.testing.expectEqual(@as(usize, 2), canonical_capability_count);
    for (outcome_object.get("actions").?.array.items) |action| {
        const requested_by = action.object.get("requested_by_job_id").?;
        if (requested_by != .string) continue;
        for (noop_job_ids[0..noop_job_count]) |noop_job_id| {
            try std.testing.expect(!std.mem.eql(
                u8,
                requested_by.string,
                noop_job_id,
            ));
        }
    }

    var saw_app = false;
    var saw_local = false;
    for (model.actions) |action| {
        try std.testing.expectEqual(
            transaction_plan.ActionKind.install,
            action.kind,
        );
        const package = for (model.packages) |package| {
            if (std.mem.eql(u8, package.id, action.target_package_id))
                break package;
        } else return error.TestUnexpectedResult;
        if (std.mem.eql(u8, package.identity.name, "app")) saw_app = true;
        if (std.mem.eql(u8, package.identity.name, "local")) saw_local = true;
    }
    try std.testing.expect(saw_app);
    try std.testing.expect(saw_local);
    try std.testing.expectEqual(
        @as(usize, 2),
        solved.retained.solved.solved.result.outcome.actions.len,
    );
    var native_saw_app = false;
    var native_saw_local = false;
    for (solved.retained.solved.solved.result.outcome.actions) |action| {
        if (action.package == solved.app) {
            native_saw_app = true;
        } else if (action.package == solved.local) {
            native_saw_local = true;
        } else {
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(saw_app, native_saw_app);
    try std.testing.expectEqual(saw_local, native_saw_local);

    const terminal_retry_jobs = [_]i32{
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        app,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        local,
        c.SOLVER_SOLVABLE | c.SOLVER_ERASE,
        app,
    };
    var terminal_retry_trace = request_trace.Trace.init(
        std.testing.allocator,
    );
    defer terminal_retry_trace.deinit();
    const terminal_app_request = try terminal_retry_trace.addRequest(
        abi.request_kind.install,
        "app",
        false,
    );
    try terminal_retry_trace.recordPackageJob(
        0,
        abi.job_action.install,
        app,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        0,
        abi.request_reason.user,
        terminal_app_request,
    );
    const terminal_local_request = try terminal_retry_trace.addRequest(
        abi.request_kind.install,
        "/credential-cache/private/local.rpm",
        true,
    );
    try terminal_retry_trace.recordPackageJob(
        1,
        abi.job_action.install,
        local,
        c.SOLVER_SOLVABLE | c.SOLVER_INSTALL,
        0,
        abi.request_reason.user,
        terminal_local_request,
    );
    try terminal_retry_trace.recordPackageJob(
        2,
        abi.job_action.erase,
        app,
        c.SOLVER_SOLVABLE | c.SOLVER_ERASE,
        0,
        abi.request_reason.installonly_limit,
        abi.request_trace_no_request,
    );
    try terminal_retry_trace.recordPolicies(
        &.{ "ignored-*", "ignored-*" },
        &.{ "kernel", "kernel" },
        &.{},
        &.{
            "unrelated=1:2-3",
            "unrelated=1:2-3",
            "unrelated=1:3-1",
            "epoch-only=1:",
        },
        &.{ "protected-package", "protected-package" },
        false,
    );
    try terminal_retry_trace.finalize(
        &terminal_retry_jobs,
        c.SOLVER_CLEANDEPS,
        c.SOLVER_FORCEBEST,
    );
    var terminal_retry_input = input;
    terminal_retry_input.trace = terminal_retry_trace.getView().?;
    terminal_retry_input.terminal_problem_kind = .installonly_limit;
    try std.testing.expectError(
        error.JobMismatch,
        capturePending(state, terminal_retry_input),
    );
    terminal_retry_input.terminal_problem_kind = .protected_package;
    try std.testing.expectError(
        error.JobMismatch,
        capturePending(state, terminal_retry_input),
    );

    var terminal_input = input;
    terminal_input.terminal_problem_kind = .protected_package;
    try capturePending(state, terminal_input);
    try std.testing.expect(state.hasPendingProblem());
    try std.testing.expect(state.publishProblem());
    const terminal_model = state.model().?;
    try std.testing.expectEqual(
        .problems,
        terminal_model.environment.resolution_status,
    );
    try std.testing.expectEqual(@as(usize, 0), terminal_model.actions.len);
    try std.testing.expectEqual(@as(usize, 1), terminal_model.problems.len);
    try std.testing.expectEqual(
        transaction_plan.ProblemKind.protected_package,
        terminal_model.problems[0].kind,
    );

    var invalid_environment = environment;
    invalid_environment.allow_multilib = 2;
    var invalid_input = input;
    invalid_input.environment = &invalid_environment;
    try std.testing.expectError(
        error.InvalidEnvironment,
        capturePending(state, invalid_input),
    );
    try std.testing.expect(state.model() == null);
    try capturePending(state, input);
    try std.testing.expectEqual(@as(u32, 0), statePublish(state));
    try std.testing.expect(state.model() != null);
    try std.testing.expectEqual(
        @as(u32, 0),
        stateSetEnabled(&state_storage, 1),
    );
    try std.testing.expect(state.model() == null);
    try state.recordRepository(
        available,
        [_]u8{0} ** 32,
        .{
            .include_filelists = true,
            .include_updateinfo = true,
            .include_other = true,
        },
    );
    try std.testing.expectError(
        error.RepositoryIntegrityMismatch,
        capturePending(state, input),
    );
    try std.testing.expect(state.model() == null);
    try state.recordRepository(
        available,
        cache.load_cookie_sha256,
        .{
            .include_filelists = true,
            .include_updateinfo = true,
            .include_other = true,
        },
    );
    const app_solvable: *c.Solvable = @ptrCast(
        c.pool_id2solvable(universe.pool, app) orelse
            return error.TestUnexpectedResult,
    );
    const original_requires = app_solvable.requires;
    try universe.require(available, app, "stale-cache-semantics");
    try std.testing.expectError(
        error.RepositoryIntegrityMismatch,
        capturePending(state, input),
    );
    try std.testing.expect(state.model() == null);
    app_solvable.requires = original_requires;
    const stale_checksum = c.repo_add_repodata(available, 0) orelse
        return error.OutOfMemory;
    c.repodata_set_checksum(
        stale_checksum,
        app,
        c.SOLVABLE_CHECKSUM,
        c.REPOKEY_TYPE_SHA256,
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    );
    c.repodata_internalize(stale_checksum);
    try std.testing.expectError(
        error.RepositoryIntegrityMismatch,
        capturePending(state, input),
    );
    const restored_checksum = c.repo_add_repodata(available, 0) orelse
        return error.OutOfMemory;
    c.repodata_set_checksum(
        restored_checksum,
        app,
        c.SOLVABLE_CHECKSUM,
        c.REPOKEY_TYPE_SHA256,
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    );
    c.repodata_internalize(restored_checksum);
    try capturePending(state, input);
    try std.testing.expectEqual(@as(u32, 0), statePublish(state));

    trace.deinit();
    trace_live = false;
    solved.destroy(std.testing.allocator);
    solved_live = false;
    universe.destroy();
    universe_live = false;
    tdnf_rpm_config_destroy(rpm_config);
    config_live = false;
    cache.cleanup();
    cache_live = false;

    var json_pointer: ?[*]const u8 = null;
    var json_length: usize = 0;
    try std.testing.expectEqual(
        @as(u32, 0),
        stateGetCanonicalJson(state, &json_pointer, &json_length),
    );
    defer stateFreeCanonicalJson(json_pointer, json_length);
    const json = json_pointer.?[0..json_length];
    try std.testing.expect(std.mem.indexOf(u8, json, "\"app\"") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "cache-token=never-store",
    ) == null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "/credential-cache/private/local.rpm",
    ) == null);
    stateClear(state);
    try std.testing.expectError(
        error.NoPlan,
        state.canonicalJsonAlloc(std.testing.allocator),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        stateSetEnabled(&state_storage, 0),
    );
    try std.testing.expect(!state.enabled);
    stateDestroy(state_storage);
    state_storage = null;
    state_live = false;
    try std.testing.expect(std.mem.indexOf(u8, json, "\"app\"") != null);
}

test "rpmdb snapshot rejects a divergent live installed repository" {
    var cache = try TestCache.create();
    defer cache.cleanup();
    var root_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_path = try cache.path(&root_path_buffer, "root");
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    switch (std.os.linux.errno(std.os.linux.getcwd(
        cwd_buffer[0..].ptr,
        cwd_buffer.len,
    ))) {
        .SUCCESS => {},
        else => return error.TestUnexpectedResult,
    }
    const cwd_length = std.mem.findScalar(u8, &cwd_buffer, 0) orelse
        return error.TestUnexpectedResult;
    const root_path_z = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        "{s}/{s}",
        .{ cwd_buffer[0..cwd_length], root_path },
        0,
    );
    defer std.testing.allocator.free(root_path_z);
    const rpm_config = tdnf_rpm_config_create(root_path_z.ptr) orelse
        return error.TestUnexpectedResult;
    defer tdnf_rpm_config_destroy(rpm_config);

    var universe = try TestUniverse.create();
    defer universe.destroy();
    const installed = try universe.addRepository("@System", true, 0);
    _ = try universe.addPackage(
        installed,
        "not-in-rpmdb",
        "1-1",
        77,
        "unused",
        0,
    );
    universe.finish(&.{installed});
    var live_context = try SolverDigestContext.init(
        std.testing.allocator,
        universe.pool,
    );
    defer live_context.deinit();
    try std.testing.expectError(
        error.RpmdbIdentityFailed,
        captureRpmdbIdentity(
            std.testing.allocator,
            universe.pool,
            &live_context,
            rpm_config,
            true,
        ),
    );
}

test "installed solver digest detects relation-only mutation" {
    var original = try TestUniverse.create();
    defer original.destroy();
    const original_repo = try original.addRepository("@System", true, 0);
    const original_package = try original.addPackage(
        original_repo,
        "installed",
        "1-1",
        42,
        "unused",
        0,
    );
    original.finish(&.{original_repo});

    var mutated = try TestUniverse.create();
    defer mutated.destroy();
    const mutated_repo = try mutated.addRepository("@System", true, 0);
    const mutated_package = try mutated.addPackage(
        mutated_repo,
        "installed",
        "1-1",
        42,
        "unused",
        0,
    );
    try mutated.require(
        mutated_repo,
        mutated_package,
        "relation-only-mutation",
    );
    mutated.finish(&.{mutated_repo});

    const original_digest = try testSolverPackageDigest(
        original.pool,
        original_package,
    );
    const mutated_digest = try testSolverPackageDigest(
        mutated.pool,
        mutated_package,
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        &original_digest,
        &mutated_digest,
    ));
}

fn dependencyBoundaryFixtureDigest(
    normal: []const []const u8,
    prerequisites: []const []const u8,
) ![32]u8 {
    var universe = try TestUniverse.create();
    defer universe.destroy();
    const repository = try universe.addRepository(
        "@System",
        true,
        0,
    );
    const package = try universe.addPackage(
        repository,
        "dependency-boundaries",
        "1-1",
        42,
        "unused",
        0,
    );
    try universe.setRequires(
        repository,
        package,
        normal,
        prerequisites,
    );
    universe.finish(&.{repository});
    return testSolverPackageDigest(universe.pool, package);
}

test "solver digest canonicalizes within prerequisite boundaries" {
    const original = try dependencyBoundaryFixtureDigest(
        &.{ "normal-b", "normal-a", "normal-a" },
        &.{ "pre-y", "pre-x" },
    );
    const permuted = try dependencyBoundaryFixtureDigest(
        &.{ "normal-a", "normal-a", "normal-b" },
        &.{ "pre-x", "pre-y" },
    );
    const swapped_pre_flags = try dependencyBoundaryFixtureDigest(
        &.{ "pre-x", "normal-a", "normal-b" },
        &.{ "pre-y", "normal-a" },
    );
    try std.testing.expectEqualSlices(u8, &original, &permuted);
    try std.testing.expect(!std.mem.eql(
        u8,
        &original,
        &swapped_pre_flags,
    ));
}

fn fileProvideBoundaryFixtureDigest(
    explicit: []const []const u8,
    generated_files: []const []const u8,
) ![32]u8 {
    var universe = try TestUniverse.create();
    defer universe.destroy();
    const repository = try universe.addRepository(
        "@System",
        true,
        0,
    );
    const package = try universe.addPackage(
        repository,
        "file-provide-boundaries",
        "1-1",
        42,
        "unused",
        0,
    );
    try universe.setProvides(
        repository,
        package,
        explicit,
        generated_files,
    );
    universe.finish(&.{repository});
    return testSolverPackageDigest(universe.pool, package);
}

test "solver digest preserves file provide boundaries and duplicates" {
    const original = try fileProvideBoundaryFixtureDigest(
        &.{
            "/usr/bin/shared",
            "/usr/bin/explicit",
            "/usr/bin/shared",
        },
        &.{ "/usr/bin/generated-b", "/usr/bin/generated-a" },
    );
    const permuted = try fileProvideBoundaryFixtureDigest(
        &.{
            "/usr/bin/shared",
            "/usr/bin/shared",
            "/usr/bin/explicit",
        },
        &.{ "/usr/bin/generated-a", "/usr/bin/generated-b" },
    );
    const reclassified = try fileProvideBoundaryFixtureDigest(
        &.{
            "/usr/bin/shared",
            "/usr/bin/explicit",
            "/usr/bin/shared",
            "/usr/bin/generated-a",
        },
        &.{"/usr/bin/generated-b"},
    );
    const duplicate_mismatch = try fileProvideBoundaryFixtureDigest(
        &.{ "/usr/bin/shared", "/usr/bin/explicit" },
        &.{ "/usr/bin/generated-b", "/usr/bin/generated-a" },
    );

    try std.testing.expectEqualSlices(u8, &original, &permuted);
    try std.testing.expect(!std.mem.eql(
        u8,
        &original,
        &reclassified,
    ));
    try std.testing.expect(!std.mem.eql(
        u8,
        &original,
        &duplicate_mismatch,
    ));
}

const ProviderOrderFixture = enum {
    forward,
    reverse,
    mismatch,
};

const ProviderOrderFixtureDigest = struct {
    canonical: [32]u8,
    discovery_order: [32]u8,
};

fn providerOrderFixtureDigest(
    installed: bool,
    fixture: ProviderOrderFixture,
) !ProviderOrderFixtureDigest {
    var universe = try TestUniverse.create();
    defer universe.destroy();
    const repository = try universe.addRepository(
        if (installed) "@System" else "available",
        installed,
        0,
    );
    const package = try universe.addPackage(
        repository,
        "provider-order",
        "1-1",
        if (installed) 42 else null,
        "provider-order.rpm",
        1,
    );
    switch (fixture) {
        .forward => {
            try universe.provide(repository, package, "alpha-capability");
            try universe.provide(repository, package, "beta-capability");
        },
        .reverse => {
            try universe.provide(repository, package, "beta-capability");
            try universe.provide(repository, package, "alpha-capability");
        },
        .mismatch => {
            try universe.provide(repository, package, "alpha-capability");
            try universe.provide(repository, package, "gamma-capability");
        },
    }
    universe.finish(&.{repository});
    const solvable: *c.Solvable = @ptrCast(
        c.pool_id2solvable(universe.pool, package) orelse
            return error.TestUnexpectedResult,
    );
    var provides: c.Queue = undefined;
    c.queue_init(&provides);
    defer c.queue_free(&provides);
    _ = c.solvable_lookup_deparray(
        solvable,
        c.SOLVABLE_PROVIDES,
        &provides,
        0,
    );
    var discovery_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (provides.elements[0..@intCast(provides.count)]) |id|
        try hashPoolString(
            &discovery_hasher,
            universe.pool,
            id,
            true,
        );
    var discovery_order: [32]u8 = undefined;
    discovery_hasher.final(&discovery_order);
    return .{
        .canonical = try testSolverPackageDigest(
            universe.pool,
            package,
        ),
        .discovery_order = discovery_order,
    };
}

test "provider digests canonicalize order for available and rpmdb snapshots" {
    inline for (.{ false, true }) |installed| {
        const forward = try providerOrderFixtureDigest(
            installed,
            .forward,
        );
        const reverse = try providerOrderFixtureDigest(
            installed,
            .reverse,
        );
        const mismatch = try providerOrderFixtureDigest(
            installed,
            .mismatch,
        );
        try std.testing.expect(!std.mem.eql(
            u8,
            &forward.discovery_order,
            &reverse.discovery_order,
        ));
        try std.testing.expectEqualSlices(
            u8,
            &forward.canonical,
            &reverse.canonical,
        );
        try std.testing.expect(!std.mem.eql(
            u8,
            &forward.canonical,
            &mismatch.canonical,
        ));
    }
}

test "solver digest context scans package universe once" {
    var universe = try TestUniverse.create();
    defer universe.destroy();
    const repositories = [_]*c.Repo{
        try universe.addRepository("@System", true, 0),
        try universe.addRepository("repo-a", false, 0),
        try universe.addRepository("repo-b", false, 0),
        try universe.addRepository("repo-c", false, 0),
    };
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var packages: [128]c.Id = undefined;
    for (&packages, 0..) |*package, index| {
        const name = try std.fmt.allocPrintSentinel(
            arena,
            "scale-package-{d}",
            .{index},
            0,
        );
        package.* = try universe.addPackage(
            repositories[index % repositories.len],
            name,
            "1-1",
            @intCast(index + 1),
            "unused",
            0,
        );
    }
    universe.finish(&repositories);
    var context = try SolverDigestContext.init(
        std.testing.allocator,
        universe.pool,
    );
    defer context.deinit();
    try std.testing.expectEqual(@as(u32, 1), context.universe_scans);
    var scratch_pools: [4]?*c.Pool = [_]?*c.Pool{null} ** 4;
    defer for (scratch_pools) |scratch| {
        if (scratch) |pool| c.pool_free(pool);
    };
    for (&scratch_pools, 0..) |*scratch, index| {
        const pool = c.pool_create() orelse return error.OutOfMemory;
        scratch.* = pool;
        _ = c.pool_setdisttype(pool, c.DISTTYPE_RPM);
        const name = try std.fmt.allocPrintSentinel(
            arena,
            "scratch-{d}",
            .{index},
            0,
        );
        const repo: *c.Repo = @ptrCast(
            c.repo_create(pool, name.ptr) orelse return error.OutOfMemory,
        );
        try context.seedScratch(pool, repo);
    }
    try std.testing.expectEqual(@as(u32, 4), context.scratch_seed_calls);
    for (packages) |package| {
        _ = try solverPackageDigest(&context, package);
    }
    try std.testing.expectEqual(
        @as(u64, packages.len),
        context.digest_calls,
    );
    try std.testing.expectEqual(@as(u32, 1), context.universe_scans);
}

/// The architecture read back out of `pool->id2arch`, exactly the way
/// `captureEnvironment` used to read it. Kept as the oracle for
/// `effectiveArchitecture` for as long as libsolv is linked.
fn libsolvPoolArchitecture(pool: *c.Pool) IntegrationError![]const u8 {
    if (pool.id2arch == null or pool.lastarch <= 1) {
        return error.InvalidEnvironment;
    }
    var best_id: c.Id = 0;
    var best_score: c.Id = std.math.maxInt(c.Id);
    var id: c.Id = 1;
    while (id < pool.lastarch) : (id += 1) {
        const score = pool.id2arch[@intCast(id)];
        if (score > 1 and score < best_score) {
            best_score = score;
            best_id = id;
        }
    }
    if (best_id == 0) return error.InvalidEnvironment;
    const raw = c.pool_id2str(pool, best_id) orelse
        return error.InvalidEnvironment;
    const architecture = std.mem.span(raw);
    if (architecture.len == 0) return error.InvalidEnvironment;
    return architecture;
}

test "native architecture matches the libsolv arch policy readback" {
    // Heads of multi-token policies, an architecture absent from the policy
    // table, and one that is only ever a tail of somebody else's policy.
    const cases = [_][]const u8{
        "x86_64",  "x86_64_v2", "x86_64_v3", "x86_64_v4",
        "i686",    "i586",      "i486",      "i386",
        "s390x",   "ppc64",     "ppc64p7",   "ia64",
        "armv7hl", "armv8l",    "sparcv9",   "e2kv4",
        "aarch64", "riscv64",   "ppc64le",   "loongarch64",
    };
    for (cases) |arch| {
        errdefer std.debug.print("\narchitecture case {s}\n", .{arch});
        const pool = c.pool_create() orelse return error.OutOfMemory;
        defer c.pool_free(pool);
        const arch_z = try std.testing.allocator.dupeZ(u8, arch);
        defer std.testing.allocator.free(arch_z);
        c.pool_setarch(pool, arch_z.ptr);
        const environment = abi.IntegrationEnvironment{
            .force_architecture = arch_z.ptr,
        };
        try std.testing.expectEqualStrings(
            try libsolvPoolArchitecture(pool),
            try effectiveArchitecture(std.testing.allocator, &environment),
        );
    }
}

test "an empty forced architecture is rejected on both paths" {
    const pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(pool);
    c.pool_setarch(pool, "");
    try std.testing.expectError(
        error.InvalidEnvironment,
        libsolvPoolArchitecture(pool),
    );
    try std.testing.expectError(
        error.InvalidEnvironment,
        effectiveArchitecture(
            std.testing.allocator,
            &.{ .force_architecture = "" },
        ),
    );
}

test "an absent forced architecture reports the kernel machine" {
    const host = std.posix.uname();
    const machine = std.mem.sliceTo(&host.machine, 0);
    const pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(pool);
    c.pool_setarch(pool, &host.machine);
    const native = try effectiveArchitecture(
        std.testing.allocator,
        &.{ .force_architecture = null },
    );
    defer std.testing.allocator.free(native);
    try std.testing.expectEqualStrings(machine, native);
    try std.testing.expectEqualStrings(
        try libsolvPoolArchitecture(pool),
        native,
    );
}

/// Every field the snapshot id hashes, read back out of libsolv exactly the way
/// `bindRepositoryVisibility` used to read it.
fn libsolvVisibilityFacts(
    allocator: Allocator,
    pool: *c.Pool,
    repository: *c.Repo,
    repository_name: []const u8,
) IntegrationError![]VisibilityFact {
    var facts = std.ArrayList(VisibilityFact).empty;
    errdefer facts.deinit(allocator);
    errdefer for (facts.items) |fact|
        deinitSolverPackageFact(allocator, fact.package);
    var solvid = repository.start;
    while (solvid < repository.end) : (solvid += 1) {
        const raw = c.pool_id2solvable(pool, solvid) orelse continue;
        const solvable: *c.Solvable = @ptrCast(raw);
        if (solvable.repo != repository or solvable.name == 0) continue;
        const fact = try solverFactKeyForSolvid(
            allocator,
            pool,
            repository_name,
            solvid,
        );
        facts.append(allocator, .{
            .package = fact,
            .considered = if (pool.considered) |raw_map|
                c.map_tst(@ptrCast(raw_map), solvid) != 0
            else
                true,
        }) catch |err| {
            deinitSolverPackageFact(allocator, fact);
            return err;
        };
    }
    return facts.toOwnedSlice(allocator);
}

fn expectEqualOptionalStrings(
    expected: ?[]const u8,
    actual: ?[]const u8,
) !void {
    if (expected == null or actual == null) {
        return std.testing.expectEqual(expected == null, actual == null);
    }
    return std.testing.expectEqualStrings(expected.?, actual.?);
}

/// Packages chosen to exercise every normalization libsolv applies between
/// `SolvBuilder.addPrimary` and the fact-key readback. Each entry is a case
/// that a naive native reimplementation gets wrong.
fn differentialVisibilityPackages() []const metadata_model.Package {
    const sha256_lower = "0123456789abcdef" ** 4;
    const sha256_upper = "0123456789ABCDEF" ** 4;
    const sha1_hex = "0123456789abcdef0123456789abcdef01234567";
    const S = struct {
        const packages = [_]metadata_model.Package{
            // Ordinary case: canonical href, pkgid, explicit size.
            .{
                .pkg_id = "p1",
                .nevra = .{
                    .name = "alpha",
                    .version = "1.2",
                    .release = "3",
                    .arch = "x86_64",
                },
                .checksum = .{
                    .kind = "sha256",
                    .value = sha256_lower,
                    .is_pkgid = true,
                },
                .location = .{
                    .href = "packages/alpha-1.2-3.x86_64.rpm",
                },
                .size = .{ .package = 4096 },
            },
            // Uppercase kind and value: both fold on the way through libsolv.
            .{
                .pkg_id = "p2",
                .nevra = .{
                    .name = "beta",
                    .epoch = 2,
                    .version = "4.5",
                    .release = "6",
                    .arch = "noarch",
                },
                .checksum = .{
                    .kind = "SHA256",
                    .value = sha256_upper,
                    .is_pkgid = true,
                },
                .location = .{ .href = "beta-4.5-6.noarch.rpm" },
            },
            // "sha" is an alias for sha1, not a distinct identity.
            .{
                .pkg_id = "p3",
                .nevra = .{
                    .name = "gamma",
                    .version = "7",
                    .release = "8",
                    .arch = "i686",
                },
                .checksum = .{ .kind = "sha", .value = sha1_hex },
                .location = .{
                    .href = "./gamma-7-8.i686.rpm",
                    .xml_base = "../pool",
                },
                .size = .{ .package = 1 },
            },
            // Too short for its declared type: libsolv stores no checksum.
            .{
                .pkg_id = "p4",
                .nevra = .{
                    .name = "delta",
                    .epoch = 0,
                    .version = "9",
                    .release = "10",
                    .arch = "x86_64",
                },
                .checksum = .{ .kind = "sha256", .value = "abcd" },
                .location = .{ .href = "" },
            },
            // Directory equal to the architecture, and a rooted href.
            .{
                .pkg_id = "p5",
                .nevra = .{
                    .name = "epsilon",
                    .version = "11",
                    .release = "12",
                    .arch = "x86_64",
                },
                .checksum = .{ .kind = "sha256", .value = sha256_lower },
                .location = .{ .href = "x86_64/epsilon-11-12.x86_64.rpm" },
                .size = .{ .package = 0 },
            },
            .{
                .pkg_id = "p6",
                .nevra = .{
                    .name = "zeta",
                    .version = "13",
                    .release = "14",
                    .arch = "noarch",
                },
                .checksum = .{ .kind = "md5", .value = "0123456789abcdef" ** 2 },
                .location = .{ .href = "/zeta-13-14.noarch.rpm" },
            },
            // A version that already looks epoch-prefixed forces a zero epoch.
            .{
                .pkg_id = "p7",
                .nevra = .{
                    .name = "eta",
                    .version = "15:16",
                    .release = "17",
                    .arch = "noarch",
                },
                .checksum = .{ .kind = "sha512", .value = "0123456789abcdef" ** 8 },
                .location = .{ .href = "./deep/eta.rpm" },
            },
            // No version, no release, no epoch: the EVR interns as nothing.
            .{
                .pkg_id = "p8",
                .nevra = .{ .name = "theta", .arch = "noarch" },
                .checksum = .{ .kind = "sha224", .value = "0123456789abcdef" ** 4 },
                .location = .{ .href = "theta.rpm" },
            },
        };
    };
    return &S.packages;
}

fn differentialVisibilityAdvisories() []const metadata_model.Advisory {
    const S = struct {
        const advisories = [_]metadata_model.Advisory{
            .{ .id = "TDNF-2026-0001", .raw_type = "security", .version = "3" },
            .{ .id = "TDNF-2026-0002", .raw_type = "bugfix" },
        };
    };
    return &S.advisories;
}

test "native visibility facts reproduce the libsolv readback byte for byte" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const model = metadata_model.RepositoryModel{
        .packages = @constCast(differentialVisibilityPackages()),
        .advisories = @constCast(differentialVisibilityAdvisories()),
        .has_updateinfo = true,
    };

    const pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(pool);
    if (c.pool_setdisttype(pool, c.DISTTYPE_RPM) != 0) {
        return error.TestUnexpectedResult;
    }
    c.pool_setarch(pool, "x86_64");
    const raw_repo = c.repo_create(pool, "available") orelse
        return error.OutOfMemory;
    const repo: *c.Repo = @ptrCast(raw_repo);
    try repository_metadata.solv_bridge.buildRepositoryIntoRepo(
        arena,
        repo,
        &model,
    );
    c.pool_createwhatprovides(pool);

    const libsolv_facts = try libsolvVisibilityFacts(
        arena,
        pool,
        repo,
        "available",
    );
    var native_facts = std.ArrayList(VisibilityFact).empty;
    try collectNativeVisibilityFacts(
        arena,
        "available",
        &model,
        &.{},
        &native_facts,
    );

    try std.testing.expectEqual(libsolv_facts.len, native_facts.items.len);
    std.mem.sort(VisibilityFact, libsolv_facts, {}, visibilityFactLessThan);
    std.mem.sort(
        VisibilityFact,
        native_facts.items,
        {},
        visibilityFactLessThan,
    );
    for (libsolv_facts, native_facts.items) |expected, actual| {
        errdefer std.debug.print(
            "\nvisibility fact mismatch for {s}\n",
            .{expected.package.name},
        );
        try std.testing.expectEqualStrings(
            expected.package.repository,
            actual.package.repository,
        );
        try std.testing.expectEqualStrings(
            expected.package.name,
            actual.package.name,
        );
        try std.testing.expectEqualStrings(
            expected.package.arch,
            actual.package.arch,
        );
        try std.testing.expectEqualStrings(
            expected.package.evr,
            actual.package.evr,
        );
        try std.testing.expectEqualStrings(
            expected.package.pkgid_kind,
            actual.package.pkgid_kind,
        );
        try std.testing.expectEqualStrings(
            expected.package.pkgid_value,
            actual.package.pkgid_value,
        );
        try std.testing.expectEqualStrings(
            expected.package.checksum_kind,
            actual.package.checksum_kind,
        );
        try std.testing.expectEqualStrings(
            expected.package.checksum_value,
            actual.package.checksum_value,
        );
        try expectEqualOptionalStrings(
            expected.package.location,
            actual.package.location,
        );
        try expectEqualOptionalStrings(
            expected.package.xml_base,
            actual.package.xml_base,
        );
        try std.testing.expectEqual(
            expected.package.download_size,
            actual.package.download_size,
        );
        try std.testing.expectEqual(expected.considered, actual.considered);
    }

    const captured = transaction_plan.Repository{
        .cost = default_repository_cost,
        .id = "available",
        .kind = .available,
        .priority = 0,
        .repomd = null,
        .snapshot = .{
            .id = "snapshot-v2-" ++ "a" ** 64,
            .metadata_sha256 = "a" ** 64,
        },
    };
    const libsolv_id = try visibilitySnapshotId(
        arena,
        captured.snapshot.?.id,
        libsolv_facts,
    );
    const native = try bindRepositoryVisibility(
        arena,
        "available",
        &model,
        &.{},
        captured,
    );
    try std.testing.expectEqualStrings(libsolv_id, native.snapshot.?.id);
}

test "advisory pseudo solvables stay inside the snapshot identity" {
    try std.testing.expectEqualStrings(
        "tdnf.repository-visible-snapshot/v2",
        visible_snapshot_identity_domain,
    );
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const captured = transaction_plan.Repository{
        .cost = default_repository_cost,
        .id = "available",
        .kind = .available,
        .priority = 0,
        .repomd = null,
        .snapshot = .{
            .id = "snapshot-v2-" ++ "a" ** 64,
            .metadata_sha256 = "a" ** 64,
        },
    };
    var with_updateinfo = metadata_model.RepositoryModel{
        .packages = @constCast(differentialVisibilityPackages()),
        .advisories = @constCast(differentialVisibilityAdvisories()),
        .has_updateinfo = true,
    };
    var without_updateinfo = with_updateinfo;
    without_updateinfo.has_updateinfo = false;
    const bound = try bindRepositoryVisibility(
        arena,
        "available",
        &with_updateinfo,
        &.{},
        captured,
    );
    const unbound = try bindRepositoryVisibility(
        arena,
        "available",
        &without_updateinfo,
        &.{},
        captured,
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        bound.snapshot.?.id,
        unbound.snapshot.?.id,
    ));
}

test "hiding a package changes the repository snapshot identity" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const model = metadata_model.RepositoryModel{
        .packages = @constCast(differentialVisibilityPackages()),
    };
    const captured = transaction_plan.Repository{
        .cost = default_repository_cost,
        .id = "available",
        .kind = .available,
        .priority = 0,
        .repomd = null,
        .snapshot = .{
            .id = "snapshot-v2-" ++ "a" ** 64,
            .metadata_sha256 = "a" ** 64,
        },
    };
    var legacy_labeled = captured;
    legacy_labeled.snapshot.?.id = "snapshot-v1-" ++ "a" ** 64;
    try std.testing.expectError(
        error.InvalidRepository,
        bindRepositoryVisibility(
            arena,
            "available",
            &model,
            &.{},
            legacy_labeled,
        ),
    );
    const all_visible = try bindRepositoryVisibility(
        arena,
        "available",
        &model,
        &.{},
        captured,
    );
    const hidden = [_]HiddenIdentity{.{
        .repository_id = "available",
        .name = "alpha",
        .arch = "x86_64",
        .version = "1.2",
        .release = "3",
        .epoch = 0,
    }};
    const one_hidden = try bindRepositoryVisibility(
        arena,
        "available",
        &model,
        &hidden,
        captured,
    );
    // A hidden package in another repository must not move this one.
    const other_repository = [_]HiddenIdentity{.{
        .repository_id = "other",
        .name = "alpha",
        .arch = "x86_64",
        .version = "1.2",
        .release = "3",
        .epoch = 0,
    }};
    const unaffected = try bindRepositoryVisibility(
        arena,
        "available",
        &model,
        &other_repository,
        captured,
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        all_visible.snapshot.?.id,
        repository_capture.snapshot_id_prefix,
    ));
    try std.testing.expect(!std.mem.eql(
        u8,
        all_visible.snapshot.?.id,
        one_hidden.snapshot.?.id,
    ));
    try std.testing.expectEqualStrings(
        all_visible.snapshot.?.id,
        unaffected.snapshot.?.id,
    );
}

fn visibilityBindingAllocationCase(
    allocator: Allocator,
    model: *const metadata_model.RepositoryModel,
) !void {
    const output = try bindRepositoryVisibility(
        allocator,
        "available",
        model,
        &.{},
        .{
            .cost = default_repository_cost,
            .id = "available",
            .kind = .available,
            .priority = 0,
            .repomd = null,
            .snapshot = .{
                .id = "snapshot-v2-" ++ "a" ** 64,
                .metadata_sha256 = "a" ** 64,
            },
        },
    );
    allocator.free(output.snapshot.?.id);
}

test "visibility binding cleans every allocation failure" {
    const model = metadata_model.RepositoryModel{
        .packages = @constCast(differentialVisibilityPackages()),
        .advisories = @constCast(differentialVisibilityAdvisories()),
        .has_updateinfo = true,
    };
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        visibilityBindingAllocationCase,
        .{&model},
    );
}

fn setTestConsidered(
    pool: *c.Pool,
    hidden: []const c.Id,
) !void {
    if (pool.considered != null) return error.TestUnexpectedResult;
    const considered = try std.heap.c_allocator.create(c.Map);
    c.map_init(considered, pool.nsolvables);
    c.map_setall(considered);
    for (hidden) |solvid| c.map_clr(considered, solvid);
    pool.considered = considered;
}

fn clearTestConsidered(pool: *c.Pool) void {
    if (pool.considered) |raw| {
        pool.considered = null;
        freeConsidered(@ptrCast(raw));
    }
}

fn mappedVisibility(
    visibility: []const SolvableVisibility,
    solvid: c.Id,
) ?bool {
    for (visibility) |entry| {
        if (entry.destination == solvid) return entry.visible;
    }
    return null;
}

test "reload visibility uses stable source keys across reorder and removal" {
    const checksum_a =
        "1111111111111111111111111111111111111111111111111111111111111111";
    const checksum_b =
        "2222222222222222222222222222222222222222222222222222222222222222";
    const checksum_c =
        "3333333333333333333333333333333333333333333333333333333333333333";
    const checksum_d =
        "4444444444444444444444444444444444444444444444444444444444444444";
    const checksum_e =
        "5555555555555555555555555555555555555555555555555555555555555555";
    var source = try TestUniverse.create();
    defer source.destroy();
    const source_repo = try source.addRepository("available", false, 0);
    const removed = try source.addPackageChecksum(
        source_repo,
        "removed",
        "1-1",
        null,
        "removed.rpm",
        1,
        checksum_a,
    );
    const duplicate_a = try source.addPackageChecksum(
        source_repo,
        "duplicate",
        "1-1",
        null,
        "duplicate-a.rpm",
        1,
        checksum_b,
    );
    _ = try source.addPackageChecksum(
        source_repo,
        "duplicate",
        "1-1",
        null,
        "duplicate-b.rpm",
        1,
        checksum_c,
    );
    const keep = try source.addPackageChecksum(
        source_repo,
        "keep",
        "1-1",
        null,
        "keep.rpm",
        1,
        checksum_d,
    );
    const exact_hidden = try source.addPackageChecksum(
        source_repo,
        "exact",
        "1-1",
        null,
        "exact.rpm",
        1,
        checksum_e,
    );
    _ = try source.addPackageChecksum(
        source_repo,
        "exact",
        "1-1",
        null,
        "exact.rpm",
        1,
        checksum_e,
    );
    source.finish(&.{source_repo});
    try setTestConsidered(
        source.pool,
        &.{ removed, duplicate_a, keep, exact_hidden },
    );
    defer clearTestConsidered(source.pool);

    var destination = try TestUniverse.create();
    defer destination.destroy();
    const destination_repo = try destination.addRepository(
        "available",
        false,
        0,
    );
    const destination_duplicate_b = try destination.addPackageChecksum(
        destination_repo,
        "duplicate",
        "1-1",
        null,
        "duplicate-b.rpm",
        1,
        checksum_c,
    );
    const new_hidden = try destination.addPackageChecksum(
        destination_repo,
        "new-hidden",
        "1-1",
        null,
        "new-hidden.rpm",
        1,
        checksum_a,
    );
    const destination_keep = try destination.addPackageChecksum(
        destination_repo,
        "keep",
        "1-1",
        null,
        "keep.rpm",
        1,
        checksum_d,
    );
    const destination_duplicate_a = try destination.addPackageChecksum(
        destination_repo,
        "duplicate",
        "1-1",
        null,
        "duplicate-a.rpm",
        1,
        checksum_b,
    );
    const exact_first = try destination.addPackageChecksum(
        destination_repo,
        "exact",
        "1-1",
        null,
        "exact.rpm",
        1,
        checksum_e,
    );
    const new_visible = try destination.addPackageChecksum(
        destination_repo,
        "new-visible",
        "1-1",
        null,
        "new-visible.rpm",
        1,
        checksum_a,
    );
    const exact_second = try destination.addPackageChecksum(
        destination_repo,
        "exact",
        "1-1",
        null,
        "exact.rpm",
        1,
        checksum_e,
    );
    destination.finish(&.{destination_repo});
    try setTestConsidered(destination.pool, &.{new_hidden});
    defer clearTestConsidered(destination.pool);

    var visibility = std.ArrayList(SolvableVisibility).empty;
    defer visibility.deinit(std.testing.allocator);
    try appendReloadedVisibility(
        std.testing.allocator,
        source.pool,
        source_repo,
        destination_repo,
        &visibility,
    );
    try std.testing.expectEqual(@as(usize, 7), visibility.items.len);
    try std.testing.expectEqual(
        true,
        mappedVisibility(visibility.items, destination_duplicate_b).?,
    );
    try std.testing.expectEqual(
        false,
        mappedVisibility(visibility.items, destination_duplicate_a).?,
    );
    try std.testing.expectEqual(
        false,
        mappedVisibility(visibility.items, destination_keep).?,
    );
    try std.testing.expectEqual(
        false,
        mappedVisibility(visibility.items, new_hidden).?,
    );
    try std.testing.expectEqual(
        true,
        mappedVisibility(visibility.items, new_visible).?,
    );
    try std.testing.expectEqual(
        false,
        mappedVisibility(visibility.items, exact_first).?,
    );
    try std.testing.expectEqual(
        false,
        mappedVisibility(visibility.items, exact_second).?,
    );
}

test "reload visibility distinguishes installed hnums" {
    var source = try TestUniverse.create();
    defer source.destroy();
    const source_repo = try source.addRepository("@System", true, 0);
    const source_ten = try source.addPackage(
        source_repo,
        "duplicate",
        "1-1",
        10,
        "unused",
        0,
    );
    _ = try source.addPackage(
        source_repo,
        "duplicate",
        "1-1",
        20,
        "unused",
        0,
    );
    source.finish(&.{source_repo});
    try setTestConsidered(source.pool, &.{source_ten});
    defer clearTestConsidered(source.pool);

    var destination = try TestUniverse.create();
    defer destination.destroy();
    const destination_repo = try destination.addRepository(
        "@System",
        true,
        0,
    );
    const destination_twenty = try destination.addPackage(
        destination_repo,
        "duplicate",
        "1-1",
        20,
        "unused",
        0,
    );
    const destination_ten = try destination.addPackage(
        destination_repo,
        "duplicate",
        "1-1",
        10,
        "unused",
        0,
    );
    destination.finish(&.{destination_repo});

    var visibility = std.ArrayList(SolvableVisibility).empty;
    defer visibility.deinit(std.testing.allocator);
    try appendReloadedVisibility(
        std.testing.allocator,
        source.pool,
        source_repo,
        destination_repo,
        &visibility,
    );
    try std.testing.expectEqual(
        true,
        mappedVisibility(visibility.items, destination_twenty).?,
    );
    try std.testing.expectEqual(
        false,
        mappedVisibility(visibility.items, destination_ten).?,
    );
}

test "repository solver facts key same-nevra packages by checksum" {
    const checksum_one =
        "1111111111111111111111111111111111111111111111111111111111111111";
    const checksum_two =
        "2222222222222222222222222222222222222222222222222222222222222222";
    var live = try TestUniverse.create();
    defer live.destroy();
    const live_repo = try live.addRepository("available", false, 0);
    const live_one = try live.addPackageChecksum(
        live_repo,
        "duplicate",
        "1-1",
        null,
        "one.rpm",
        1,
        checksum_one,
    );
    const live_two = try live.addPackageChecksum(
        live_repo,
        "duplicate",
        "1-1",
        null,
        "two.rpm",
        1,
        checksum_two,
    );
    try live.require(live_repo, live_one, "dependency-one");
    try live.require(live_repo, live_two, "dependency-two");
    live.finish(&.{live_repo});

    var swapped = try TestUniverse.create();
    defer swapped.destroy();
    const swapped_repo = try swapped.addRepository("available", false, 0);
    const swapped_one = try swapped.addPackageChecksum(
        swapped_repo,
        "duplicate",
        "1-1",
        null,
        "one.rpm",
        1,
        checksum_one,
    );
    const swapped_two = try swapped.addPackageChecksum(
        swapped_repo,
        "duplicate",
        "1-1",
        null,
        "two.rpm",
        1,
        checksum_two,
    );
    try swapped.require(swapped_repo, swapped_one, "dependency-two");
    try swapped.require(swapped_repo, swapped_two, "dependency-one");
    swapped.finish(&.{swapped_repo});

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var live_context = try SolverDigestContext.init(arena, live.pool);
    defer live_context.deinit();
    var swapped_context = try SolverDigestContext.init(arena, swapped.pool);
    defer swapped_context.deinit();
    const live_facts = try repositorySolverFacts(
        arena,
        &live_context,
        live_repo,
    );
    const swapped_facts = try repositorySolverFacts(
        arena,
        &swapped_context,
        swapped_repo,
    );
    try std.testing.expectEqual(live_facts.len, swapped_facts.len);
    var saw_mismatch = false;
    for (live_facts, swapped_facts) |left, right| {
        try std.testing.expectEqual(
            std.math.Order.eq,
            compareSolverFactKeys(left, right),
        );
        saw_mismatch = saw_mismatch or
            !std.mem.eql(u8, &left.digest, &right.digest);
    }
    try std.testing.expect(saw_mismatch);
}

test "repository solver key detects changed download checksum with same pkgid" {
    const pkgid =
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const checksum_one =
        "1111111111111111111111111111111111111111111111111111111111111111";
    const checksum_two =
        "2222222222222222222222222222222222222222222222222222222222222222";
    var first = try TestUniverse.create();
    defer first.destroy();
    const first_repo = try first.addRepository("available", false, 0);
    _ = try first.addPackageChecksums(
        first_repo,
        "package",
        "1-1",
        null,
        "package.rpm",
        1,
        pkgid,
        checksum_one,
    );
    first.finish(&.{first_repo});
    var second = try TestUniverse.create();
    defer second.destroy();
    const second_repo = try second.addRepository("available", false, 0);
    _ = try second.addPackageChecksums(
        second_repo,
        "package",
        "1-1",
        null,
        "package.rpm",
        1,
        pkgid,
        checksum_two,
    );
    second.finish(&.{second_repo});
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var first_context = try SolverDigestContext.init(arena, first.pool);
    defer first_context.deinit();
    var second_context = try SolverDigestContext.init(arena, second.pool);
    defer second_context.deinit();
    const first_facts = try repositorySolverFacts(
        arena,
        &first_context,
        first_repo,
    );
    const second_facts = try repositorySolverFacts(
        arena,
        &second_context,
        second_repo,
    );
    try std.testing.expectEqual(@as(usize, 1), first_facts.len);
    try std.testing.expectEqual(@as(usize, 1), second_facts.len);
    try std.testing.expect(
        compareSolverFactKeys(first_facts[0], second_facts[0]) != .eq,
    );
}

test "solver fact keys own lookup ring strings beyond sixteen packages" {
    var universe = try TestUniverse.create();
    var universe_live = true;
    defer if (universe_live) universe.destroy();
    const repository = try universe.addRepository("available", false, 0);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for (0..32) |index| {
        const name = try std.fmt.allocPrintSentinel(
            arena,
            "package-{d:0>2}",
            .{index},
            0,
        );
        const location = try std.fmt.allocPrintSentinel(
            arena,
            "packages/{d:0>2}.rpm",
            .{index},
            0,
        );
        const checksum = try std.fmt.allocPrintSentinel(
            arena,
            "{x:0>64}",
            .{index + 1},
            0,
        );
        _ = try universe.addPackageChecksum(
            repository,
            name,
            "1-1",
            null,
            location,
            index + 1,
            checksum,
        );
    }
    universe.finish(&.{repository});
    var context = try SolverDigestContext.init(arena, universe.pool);
    const facts = try repositorySolverFacts(
        arena,
        &context,
        repository,
    );
    context.deinit();
    universe.destroy();
    universe_live = false;
    try std.testing.expectEqual(@as(usize, 32), facts.len);
    for (facts, 0..) |fact, index| {
        const checksum = try std.fmt.allocPrint(
            arena,
            "{x:0>64}",
            .{index + 1},
        );
        const location = try std.fmt.allocPrint(
            arena,
            "packages/{d:0>2}.rpm",
            .{index},
        );
        try std.testing.expectEqualStrings(checksum, fact.pkgid_value);
        try std.testing.expectEqualStrings(location, fact.location.?);
    }
}

test "file dependency seeding stays linear across ten thousand mixed kinds" {
    var universe = try TestUniverse.create();
    defer universe.destroy();
    const repository = try universe.addRepository("scratch", false, 0);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const dependencies = try arena.alloc(FileDependency, 10_000);
    for (dependencies, 0..) |*dependency, index| {
        dependency.* = .{
            .key = file_dependency_keys[index % file_dependency_keys.len],
            .path = try std.fmt.allocPrint(
                arena,
                "/scaled/path-{d}",
                .{index},
            ),
        };
    }
    var context = SolverDigestContext{
        .allocator = arena,
        .pool = universe.pool,
        .file_dependencies = dependencies,
    };
    try context.seedScratch(universe.pool, repository);
    const dummy: *c.Solvable = @ptrCast(
        c.pool_id2solvable(universe.pool, repository.start) orelse
            return error.TestUnexpectedResult,
    );
    var total: usize = 0;
    for (file_dependency_keys) |key| {
        var queue: c.Queue = undefined;
        c.queue_init(&queue);
        defer c.queue_free(&queue);
        _ = c.solvable_lookup_deparray(dummy, key, &queue, 0);
        total += @intCast(queue.count);
    }
    try std.testing.expectEqual(@as(usize, 10_000), total);
    try std.testing.expectEqual(@as(u32, 1), context.scratch_seed_calls);
}

test "installed solver digest includes synthesized file provides" {
    var production = try TestUniverse.create();
    defer production.destroy();
    const production_repo = try production.addRepository("@System", true, 0);
    const production_package = try production.addPackage(
        production_repo,
        "file-provider",
        "1-1",
        1,
        "unused",
        0,
    );
    try production.addFile(
        production_repo,
        production_package,
        "/usr/bin",
        "tool",
    );
    try production.addFile(
        production_repo,
        production_package,
        "/opt/nonstandard",
        "nested-tool",
    );
    const consumer_repo = try production.addRepository("available", false, 0);
    const consumer = try production.addPackage(
        consumer_repo,
        "consumer",
        "1-1",
        null,
        "consumer.rpm",
        1,
    );
    try production.require(consumer_repo, consumer, "/usr/bin/tool");
    try production.requireRichFile(
        consumer_repo,
        consumer,
        "/opt/nonstandard/nested-tool",
        "companion-capability",
    );
    production.finish(&.{ production_repo, consumer_repo });
    c.pool_addfileprovides(production.pool);
    c.pool_createwhatprovides(production.pool);

    var rebuilt = try TestUniverse.create();
    defer rebuilt.destroy();
    const rebuilt_repo = try rebuilt.addRepository("@System", true, 0);
    const rebuilt_package = try rebuilt.addPackage(
        rebuilt_repo,
        "file-provider",
        "1-1",
        1,
        "unused",
        0,
    );
    try rebuilt.addFile(
        rebuilt_repo,
        rebuilt_package,
        "/usr/bin",
        "tool",
    );
    try rebuilt.addFile(
        rebuilt_repo,
        rebuilt_package,
        "/opt/nonstandard",
        "nested-tool",
    );
    rebuilt.finish(&.{rebuilt_repo});
    var seed_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer seed_arena.deinit();
    var seed_context = try SolverDigestContext.init(
        seed_arena.allocator(),
        production.pool,
    );
    defer seed_context.deinit();
    try seed_context.seedScratch(
        rebuilt.pool,
        rebuilt_repo,
    );
    try std.testing.expectEqual(@as(u32, 1), seed_context.universe_scans);
    try std.testing.expectEqual(@as(u32, 1), seed_context.scratch_seed_calls);
    try std.testing.expect(poolHasPlainRequirement(
        rebuilt.pool,
        "/opt/nonstandard/nested-tool",
    ));
    c.pool_addfileprovides(rebuilt.pool);
    c.pool_createwhatprovides(rebuilt.pool);
    const production_digest = try testSolverPackageDigest(
        production.pool,
        production_package,
    );
    const rebuilt_digest = try testSolverPackageDigest(
        rebuilt.pool,
        rebuilt_package,
    );
    try std.testing.expectEqualSlices(
        u8,
        &production_digest,
        &rebuilt_digest,
    );
}
