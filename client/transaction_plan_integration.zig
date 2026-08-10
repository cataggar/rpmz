const std = @import("std");
const common = @import("tdnf_common");
const Allocator = std.mem.Allocator;

const integration_options = @import("transaction_plan_integration_options");
const abi = @import("transaction_plan_capture_abi");
const capture_adapter = @import("transaction_plan_capture");
const error_codes = @import("tdnf_error");
const native_capture = @import("transaction_plan_native");
const repository_capture = @import("transaction_plan_repository");
const repository_metadata = @import("repository_metadata");
const transaction_plan = @import("transaction_plan");

const package_context = repository_metadata.package_context;
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

extern fn tdnf_rpmdb_string_free(value: ?[*:0]u8) void;
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
    context: *package_context.Context,
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

    /// Transfers ownership of the published plan to the caller.
    ///
    /// The state stops owning the plan, so a resolver can hand a completed
    /// immutable plan to its caller and then release every piece of resolver
    /// scratch storage — including this state — without invalidating it. The
    /// caller becomes responsible for `Plan.destroy`.
    ///
    /// Returns null when no plan has been published. A pending, unpublished
    /// plan is never transferred; it stays owned by the state and is released
    /// by `clear`/`destroy`.
    pub fn takePublished(self: *State) ?*transaction_plan.Plan {
        const plan = self.plan orelse return null;
        self.plan = null;
        return plan;
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

const RefreshEntry = struct {
    data: *anyopaque,
    view: abi.RepositoryRefreshView,
};

extern fn TDNFGetCachePath(?*anyopaque, ?*anyopaque, ?[*:0]const u8, ?[*:0]const u8, *?[*:0]u8) u32;
extern fn TDNFShouldSyncMetadata(?[*:0]const u8, c_long, *c_int) u32;
extern fn TDNFRepoRemoveCache(?*anyopaque, ?*anyopaque) u32;
extern fn TDNFRemoveSolvCache(?*anyopaque, ?*anyopaque) u32;
extern fn TDNFFreeMemory(?*anyopaque) void;
extern fn TDNFBuildRefreshInput(?*anyopaque, ?*anyopaque, *abi.RepositoryRefreshInput) u32;
extern fn TDNFRemoveLastRefreshMarker(?*anyopaque, ?*anyopaque) u32;

const IdList = extern struct {
    pnElements: ?[*]i32,
    dwCount: u32,
    dwCapacity: u32,
};
extern fn TDNFIdListInit(*IdList) void;
extern fn TDNFIdListFree(*IdList) void;
extern fn TDNFPkgsToExclude(?*anyopaque, *u32, *?[*]?[*:0]u8) u32;
extern fn TDNFAddGoal(?*anyopaque, c_int, *IdList, i32, u32, ?[*]?[*:0]u8) u32;
extern fn TDNFSolv(?*anyopaque, *IdList, ?[*]?[*:0]u8, u32, c_int, c_int, c_int, c_int, *?*anyopaque) u32;
extern fn TDNFAddUserInstall(?*anyopaque, *const IdList, ?*anyopaque) u32;
extern fn TDNFFreeStringArray(?[*]?[*:0]u8) void;
extern fn TDNFReadFileToStringArray(?[*:0]const u8, *?[*]?[*:0]u8) u32;

fn refreshState(input: *const abi.RepositoryRefreshInput) ?*State {
    const slot = input.state_slot orelse return null;
    return @ptrCast(@alignCast(slot.* orelse return null));
}

fn repositoryState(input: *const abi.RepositoryInitInput) ?*State {
    const slot = input.state_slot orelse return null;
    return @ptrCast(@alignCast(slot.* orelse return null));
}

fn describeRepository(
    input: *const abi.RepositoryRefreshInput,
    data: *anyopaque,
) abi.RepositoryRefreshView {
    var view = abi.RepositoryRefreshView{};
    input.describe_repository.?(data, &view);
    return view;
}

fn consumeFailure(raw: ?*u32, stage: u32) bool {
    const value = raw orelse return false;
    if (value.* != stage) return false;
    value.* = 0;
    return true;
}

fn refreshEntryLessThan(_: void, left: RefreshEntry, right: RefreshEntry) bool {
    return left.view.priority < right.view.priority;
}

fn isCommandLineRepositoryId(raw: ?[*:0]const u8) bool {
    return if (raw) |id| std.mem.eql(u8, std.mem.span(id), "@cmdline") else false;
}

fn collectRefreshEntries(
    input: *const abi.RepositoryRefreshInput,
    allocator: Allocator,
) Allocator.Error![]RefreshEntry {
    var count: usize = 0;
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(input, data);
        if (view.enabled != 0 and !isCommandLineRepositoryId(view.id)) count += 1;
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

fn mapMetadataLoadError(err: anyerror) u32 {
    return switch (err) {
        error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        error.FileNotFound => error_codes.ERROR_TDNF_FILE_NOT_FOUND,
        error.AccessDenied => error_codes.fromErrno(.ACCES),
        error.NameTooLong => error_codes.fromErrno(.NAMETOOLONG),
        error.BadPathName => error_codes.fromErrno(.INVAL),
        error.NotDir => error_codes.fromErrno(.NOTDIR),
        error.IsDir => error_codes.fromErrno(.ISDIR),
        error.FileTooBig, error.StreamTooLong => error_codes.fromErrno(.FBIG),
        error.FileSystemIo => error_codes.fromErrno(.IO),
        else => error_codes.ERROR_TDNF_INVALID_REPO_FILE,
    };
}

fn mapDirectoryLoadError(err: anyerror) u32 {
    return switch (err) {
        error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        error.DirectoryOpenFailed => error_codes.fromErrno(
            @enumFromInt(repository_metadata.directory_repository.last_open_errno),
        ),
        error.RpmFileOpenFailed => error_codes.ERROR_TDNF_FILE_NOT_FOUND,
        else => error_codes.ERROR_TDNF_INVALID_REPO_FILE,
    };
}

fn loadRepository(
    input: *const abi.RepositoryInitInput,
    context: *package_context.Context,
) u32 {
    const callbacks = input.callbacks orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    var cache_dir: ?[*:0]u8 = null;
    var metadata: ?*RepoMetadata = null;
    var result = callbacks.get_cache_path.?(
        input.tdnf_handle,
        input.repo_data,
        null,
        null,
        &cache_dir,
    );
    if (result != 0) return result;
    const cache_path = cache_dir orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    defer callbacks.free_memory.?(@ptrCast(cache_path));
    const repository_id = input.repository_id orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;

    if (input.has_metadata != 0) {
        const repo_data_dir = std.fmt.allocPrintSentinel(
            std.heap.c_allocator,
            "{s}/repodata",
            .{std.mem.span(cache_path)},
            0,
        ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
        defer std.heap.c_allocator.free(repo_data_dir);
        result = callbacks.make_dirs.?(repo_data_dir.ptr);
        if (result != 0 and result != error_codes.fromErrno(.EXIST)) return result;
        result = callbacks.get_repo_md.?(
            input.tdnf_handle,
            input.repo_data,
            repo_data_dir.ptr,
            @ptrCast(&metadata),
        );
        if (result != 0) return result;
        defer callbacks.free_repo_metadata.?(
            if (metadata) |value| @ptrCast(value) else null,
        );
        const paths = metadata orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
        var content_cookie = [_]u8{0} ** 32;
        result = callbacks.calculate_cookie.?(
            paths.repomd,
            &content_cookie,
        );
        if (result != 0) return result;
        const state = repositoryState(input);
        if (state) |value| {
            if (value.enabled and value.fail_next_repository_record) {
                value.fail_next_repository_record = false;
                return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
            }
        }
        const prior = package_context.findRepositoryByOwner(context, input.repo_data);
        const repository = package_context.loadAvailableMetadata(
            context,
            std.mem.span(repository_id),
            input.repo_data,
            input.priority,
            .{
                .repomd = std.mem.span(paths.repomd orelse
                    return error_codes.ERROR_TDNF_INVALID_PARAMETER),
                .primary = std.mem.span(paths.primary orelse
                    return error_codes.ERROR_TDNF_INVALID_PARAMETER),
                .filelists = if (paths.filelists) |path| std.mem.span(path) else null,
                .updateinfo = if (paths.updateinfo) |path| std.mem.span(path) else null,
                .other = if (paths.other) |path| std.mem.span(path) else null,
            },
            if (state) |value| value.enabled else false,
        ) catch |err| return mapMetadataLoadError(err);
        if (state) |value| {
            if (value.enabled) value.replaceRepositoryRecord(
                if (prior) |old| @ptrCast(old) else null,
                @ptrCast(repository),
                repository.cookie_sha256,
                repository.cache_options,
            ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
        }
        if (input.live_repository_slot) |slot| slot.* = @ptrCast(repository);
        return 0;
    }

    const repository = package_context.loadAvailableDirectory(
        context,
        std.mem.span(repository_id),
        input.repo_data,
        input.priority,
        std.mem.span(input.base_url orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER),
    ) catch |err| return mapDirectoryLoadError(err);
    if (input.live_repository_slot) |slot| slot.* = @ptrCast(repository);
    return 0;
}

fn initRepository(
    raw_input: ?*const abi.RepositoryInitInput,
    loaded_repo: ?*?*anyopaque,
) callconv(.c) u32 {
    if (loaded_repo) |output| output.* = null;
    const input = raw_input orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const callbacks = input.callbacks orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (input.has_metadata > 1 or input.priority == std.math.minInt(i32) or
        callbacks.free_memory == null or callbacks.make_dirs == null or
        callbacks.get_cache_path == null or callbacks.get_repo_md == null or
        callbacks.free_repo_metadata == null or callbacks.calculate_cookie == null or
        input.repository_id == null or input.repo_data == null or
        input.tdnf_handle == null or input.context == null)
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (input.failure_stage) |stage| {
        if (stage.* >= 1 and stage.* <= 7) {
            stage.* = 0;
            return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
        }
    }
    const context: *package_context.Context = @ptrCast(@alignCast(input.context.?));
    const result = loadRepository(input, context);
    if (result != 0) return result;
    const repository = package_context.findRepositoryByOwner(
        context,
        input.repo_data,
    ) orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (loaded_repo) |output| output.* = @ptrCast(repository);
    return 0;
}

fn bindLiveRepositories(
    input: *const abi.RepositoryRefreshInput,
    context: *package_context.Context,
) void {
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(input, data);
        if (view.live_repository_slot) |slot| {
            slot.* = if (package_context.findRepositoryByOwner(context, data)) |repository|
                @ptrCast(repository)
            else
                null;
        }
        raw = view.next;
    }
    if (input.command_line_repository_slot) |slot| {
        slot.* = if (package_context.commandLineRepository(context)) |repository|
            @ptrCast(repository)
        else
            null;
    }
}

fn refreshContext(
    input: *const abi.RepositoryRefreshInput,
    target: *package_context.Context,
    clean_metadata: c_int,
    bind_live: bool,
) u32 {
    const prior_refresh = input.refresh_flag.?.*;
    if (clean_metadata == 1) input.refresh_flag.?.* = 1;
    var committed = false;
    defer {
        if (!committed) input.refresh_flag.?.* = prior_refresh;
    }
    if (consumeFailure(input.failure_stage, 1))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    const replacement = package_context.create(
        std.heap.c_allocator,
        if (input.cache_dir) |value| std.mem.span(value) else null,
        if (input.root_dir) |value| std.mem.span(value) else null,
        if (input.architecture) |value|
            std.mem.span(value)
        else
            std.mem.span(package_context.architecture(target)),
    ) catch return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    defer package_context.destroy(replacement);
    if (input.all_deps == 0) {
        package_context.loadInstalled(
            replacement,
            .{ .config = input.rpm_config orelse
                return error_codes.ERROR_TDNF_INVALID_PARAMETER },
        ) catch |err| return switch (err) {
            error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
            error.InvalidRpmHeader => error_codes.ERROR_TDNF_RPM_HEADER_CONVERT_FAILED,
            error.RpmDbOpenFailed => error_codes.ERROR_TDNF_RPMTS_OPENDB_FAILED,
            error.RpmDbReadFailed => error_codes.ERROR_TDNF_SOLV_IO,
        };
    }
    _ = package_context.createCommandLine(replacement) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    const state = refreshState(input);
    var refresh_started = false;
    if (bind_live) {
        if (state) |value| {
            if (value.enabled) {
                value.beginRepositoryRefresh(@ptrCast(replacement)) catch
                    return error_codes.ERROR_TDNF_INVALID_PARAMETER;
                refresh_started = true;
            }
        }
    }
    defer if (refresh_started)
        state.?.rollbackRepositoryRefresh(@ptrCast(replacement));

    const entries = collectRefreshEntries(input, std.heap.c_allocator) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    defer std.heap.c_allocator.free(entries);
    if (entries.len != 0 and consumeFailure(input.failure_stage, 2))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    const disabled = std.heap.c_allocator.alloc(bool, entries.len) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    defer std.heap.c_allocator.free(disabled);
    @memset(disabled, false);

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
            var result = TDNFRepoRemoveCache(input.tdnf_handle, entry.data);
            if (result == error_codes.fromErrno(.NOENT)) result = 0;
            if (result != 0) return result;
            result = TDNFRemoveSolvCache(input.tdnf_handle, entry.data);
            if (result == error_codes.fromErrno(.NOENT)) result = 0;
            if (result != 0) return result;
        }
        const init_input = abi.RepositoryInitInput{
            .tdnf_handle = input.tdnf_handle,
            .repo_data = entry.data,
            .context = replacement,
            .callbacks = input.repository_init_callbacks,
            .refresh_input = input,
            .state_slot = input.state_slot,
            .failure_stage = input.failure_stage,
            .repository_id = entry.view.id,
            .base_url = entry.view.base_url,
            .priority = entry.view.priority,
            .has_metadata = @intFromBool(entry.view.has_metadata != 0),
        };
        const result = initRepository(&init_input, null);
        if (result != 0 and entry.view.skip_if_unavailable != 0 and
            result != error_codes.ERROR_TDNF_OUT_OF_MEMORY and
            result != error_codes.fromErrno(.ACCES))
        {
            disabled[index] = true;
        } else if (result != 0) return result;
    }
    if (consumeFailure(input.failure_stage, 4) or consumeFailure(input.failure_stage, 5))
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    package_context.swap(target, replacement) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
    if (bind_live) bindLiveRepositories(input, target);
    for (entries, disabled) |entry, disable| {
        if (disable) input.set_repository_enabled.?(entry.data, 0);
    }
    if (refresh_started) {
        state.?.commitRepositoryRefresh(@ptrCast(replacement));
        refresh_started = false;
    }
    committed = true;
    return 0;
}

fn refreshSack(
    raw_input: ?*const abi.RepositoryRefreshInput,
    clean_metadata: c_int,
) callconv(.c) u32 {
    const input = raw_input orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (input.tdnf_handle == null or input.live_sack == null or
        input.repository_head == null or input.command_line_repository_slot == null or
        input.state_slot == null or input.failure_stage == null or
        input.refresh_flag == null or input.cache_dir == null or
        input.rpm_config == null or input.describe_repository == null or
        input.set_repository_enabled == null)
    {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }
    const raw_target = input.sack orelse input.live_sack.?;
    const target: *package_context.Context = @ptrCast(@alignCast(raw_target));
    return refreshContext(input, target, clean_metadata, raw_target == input.live_sack.?);
}

fn refreshSackFromHandle(
    handle: ?*anyopaque,
    context: ?*anyopaque,
    clean_metadata: c_int,
) callconv(.c) u32 {
    var input = abi.RepositoryRefreshInput{};
    const result = TDNFBuildRefreshInput(handle, context, &input);
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

fn initRepoFromHandle(
    handle: ?*anyopaque,
    raw_data: ?*anyopaque,
    raw_context: ?*anyopaque,
    loaded_repo: ?*?*anyopaque,
) u32 {
    if (loaded_repo) |output| output.* = null;
    const data = raw_data orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const context = raw_context orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    var refresh = abi.RepositoryRefreshInput{};
    var result = TDNFBuildRefreshInput(handle, context, &refresh);
    if (result != 0) return result;
    const view = describeRepository(&refresh, data);
    const input = abi.RepositoryInitInput{
        .tdnf_handle = handle,
        .repo_data = data,
        .context = context,
        .callbacks = refresh.repository_init_callbacks,
        .refresh_input = &refresh,
        .state_slot = if (context == refresh.live_sack)
            refresh.state_slot
        else
            null,
        .live_repository_slot = if (context == refresh.live_sack)
            view.live_repository_slot
        else
            null,
        .failure_stage = refresh.failure_stage,
        .repository_id = view.id,
        .base_url = view.base_url,
        .priority = view.priority,
        .has_metadata = @intFromBool(view.has_metadata != 0),
    };
    result = initRepository(&input, loaded_repo);
    if (result != 0) {
        common.log(1, "Error: Failed to synchronize cache for repo '%s'\n", .{view.name orelse view.id orelse "(unknown)"});
        if (result != error_codes.ERROR_TDNF_OUT_OF_MEMORY) {
            _ = TDNFRepoRemoveCache(handle, data);
            _ = TDNFRemoveSolvCache(handle, data);
            _ = TDNFRemoveLastRefreshMarker(handle, data);
        }
    }
    return result;
}

fn initRepo(handle: ?*anyopaque, data: ?*anyopaque, context: ?*anyopaque) callconv(.c) u32 {
    return initRepoFromHandle(handle, data, context, null);
}

fn initRepoWithResult(
    handle: ?*anyopaque,
    data: ?*anyopaque,
    context: ?*anyopaque,
    loaded_repo: ?*?*anyopaque,
) callconv(.c) u32 {
    return initRepoFromHandle(handle, data, context, loaded_repo);
}

fn initCommandLineRepository(
    context: ?*anyopaque,
    slot: ?*?*anyopaque,
) callconv(.c) u32 {
    const destination = slot orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const value: *package_context.Context = @ptrCast(@alignCast(context orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    destination.* = @ptrCast(package_context.createCommandLine(value) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY);
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
    const environment = try captureEnvironment(
        arena,
        input.environment,
        input.trace,
        solver_data.environment.resolution_status,
    );

    var repository_owners = std.ArrayList(*repository_capture.Owner).empty;
    defer for (repository_owners.items) |owner| owner.destroy();
    try validateRepositoryInputs(input.repositories);
    const hidden_identities = try collectHiddenIdentities(arena, solver_data);
    const repositories = try captureRepositories(
        arena,
        state,
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
        input.context,
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
    context: *package_context.Context,
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
            selection.selection_id <= 0 or
            package_context.packageModel(
                context,
                selection.selection_id,
            ) == null)
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
                        context,
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
    context: *package_context.Context,
    data: transaction_plan.Data,
    solvid: i32,
) IntegrationError![]const u8 {
    const source_package = package_context.packageModel(
        context,
        solvid,
    ) orelse return error.InvalidPolicyTrace;
    const source_repository = package_context.packageRepository(
        context,
        solvid,
    ) orelse return error.InvalidPolicyTrace;
    const installed_state = package_context.packageInstalledState(
        context,
        solvid,
    );
    var match: ?[]const u8 = null;
    for (data.packages) |package| {
        if (std.mem.eql(u8, package.repository_id, source_repository.id) and
            packageIdentityMatchesModel(package.identity, source_package.nevra) and
            (if (installed_state) |state|
                package.rpmdb_hnum != null and
                    package.rpmdb_hnum.? == state.rpmdb_hnum
            else
                packageSourceMatchesModel(package.source, source_package.*)))
        {
            if (match != null) return error.InvalidPolicyTrace;
            match = package.id;
        }
    }
    return match orelse error.InvalidPolicyTrace;
}

fn packageSourceMatchesModel(
    source: ?transaction_plan.PackageSource,
    raw: metadata_model.Package,
) bool {
    const value = source orelse return false;
    return raw.checksum.is_pkgid == value.checksum.is_pkgid and
        std.ascii.eqlIgnoreCase(
            value.checksum.kind,
            raw.checksum.kind,
        ) and
        std.ascii.eqlIgnoreCase(
            value.checksum.value,
            raw.checksum.value,
        );
}

fn packageIdentityMatchesModel(
    identity: transaction_plan.PackageIdentity,
    raw: metadata_model.Nevra,
) bool {
    return std.mem.eql(u8, identity.name, raw.name) and
        std.mem.eql(u8, identity.arch, raw.arch) and
        std.mem.eql(u8, identity.version, raw.version) and
        std.mem.eql(u8, identity.release, raw.release) and
        identity.epoch == raw.epoch;
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
        const load_record = state.repositoryRecord(live_repository) orelse
            return error.InvalidRepository;
        if (!std.mem.eql(
            u8,
            &load_record.cookie_sha256,
            owner.loadCookieSha256(),
        )) return error.RepositoryIntegrityMismatch;
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
/// This is the same set `TDNFGoalAddHiddenPackages` resolves for the native
/// solver: both derive from `pTdnf->ppszHiddenRefs`, so resolving it here reads
/// the decision rather than a round-trip of it.
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
/// Each hashed field comes directly from the authoritative native model.
/// `nativeChecksumFields` and `nativeLocation` retain the established
/// normalization rules so snapshot identities remain stable.
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

/// An empty component is absent, an all-absent EVR is an empty string, and a
/// version that already carries its own `digits:` prefix forces an explicit
/// zero epoch.
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
    var directory = href[0..if (separator == 0) 1 else separator];
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

/// Orders two solver fact keys. Only the A4a differential visibility oracle
/// uses this now; it is kept beside its sole caller rather than with the
/// deleted verification harness.
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
    // The reverse direction. Without it a captured repository the solver never
    // saw is copied into the plan below as a package-less repository, silently.
    // Plain set equality is wrong: the native solver legitimately omits a
    // repository that contributed no package, so absence is only acceptable
    // when the capture contributed none either.
    for (available_repositories) |captured| {
        if (findRepository(solver_data.repositories, captured.id)) |solver_repository| {
            if (solver_repository.kind != .available) {
                return error.InvalidRepository;
            }
            continue;
        }
        for (solver_data.packages) |package| {
            if (std.mem.eql(u8, package.repository_id, captured.id)) {
                return error.InvalidRepository;
            }
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

/// Validates the repository inputs the capture was handed, without consulting
/// the pool.
///
/// Its predecessor `validateRepositoryUniverse` walked `pool->repos` and
/// required the input list to cover the pool's available repositories exactly.
/// Two of its checks are re-anchored rather than dropped:
///
///   * set equality now lives in `composeData`, which compares the capture
///     against the *native solver's* repository list in both directions. That
///     is the list the plan is actually built from, so it is the meaningful
///     counterpart;
///   * the `priority` sign convention (`input.priority == -pointer.priority`,
///     the bug class of #251) is deliberately NOT reproduced. Priority reaches
///     the native solver unnegated (`repomd/root.zig:851`,
///     `solver_model.zig:177`, `solver_policy.zig:3666`); the sole surviving
///     negation is the libsolv adapter in `repomd/solver_oracle.zig:348`, and
///     `libsolv-oracle-test` covers it with a differential test that pits
///     priority 10 against 90 for a contested name. A wrong sign changes which
///     package wins, so that test fails loudly — a far stronger guard than the
///     structural identity check was.
///
/// The `cost` check is kept here because this is its only site in the repo.
fn validateRepositoryInputs(
    inputs: []const abi.IntegrationRepository,
) IntegrationError!void {
    for (inputs, 0..) |input, index| {
        if (input.repository == null) return error.InvalidRepository;
        if (input.priority == std.math.minInt(i32)) {
            return error.InvalidRepository;
        }
        if (input.cost != default_repository_cost) {
            return error.InvalidRepository;
        }
        const id = requiredZ(input.id) catch return error.InvalidRepository;
        for (inputs[0..index]) |prior| {
            const prior_id = requiredZ(prior.id) catch
                return error.InvalidRepository;
            if (std.mem.eql(u8, id, prior_id)) {
                return error.AmbiguousRepository;
            }
            if (prior.repository == input.repository) {
                return error.AmbiguousRepository;
            }
        }
    }
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
            input.rpm_config orelse return error.RpmdbIdentityFailed,
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
/// carries as `force_architecture` (`transaction_plan_capture_abi.zig`).
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
    config: *const anyopaque,
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
        record_count = std.math.add(u64, record_count, 1) catch
            return error.RpmdbIdentityFailed;
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

fn handleLiveContext(
    input: *const abi.RepositoryRefreshInput,
) ?*package_context.Context {
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
    const context = handleLiveContext(&input) orelse return 0;
    return package_context.identity(context);
}

fn testPoolSolvableCount(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const context = handleLiveContext(&input) orelse return 0;
    return @intCast(package_context.packageCount(context));
}

fn testPoolRepoCount(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const context = handleLiveContext(&input) orelse return 0;
    return @intCast(package_context.repositories(context).len);
}

fn testRepoDataCount(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const context = handleLiveContext(&input) orelse return 0;
    var count: u32 = 0;
    for (package_context.repositories(context)) |repository| {
        if (repository.kind == .available and repository.has_cookie) count += 1;
    }
    return count;
}

/// Counts the solvables an arbitrary sack holds. Replaces `SolvCountPackages`,
/// whose only distinguishing behaviour was skipping solvables cleared in
/// `pool->considered`.
fn testSackSolvableCount(
    raw_sack: ?*anyopaque,
    raw_count: ?*u32,
) callconv(.c) u32 {
    const context: *package_context.Context = @ptrCast(@alignCast(raw_sack orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER));
    const count = raw_count orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    count.* = @intCast(package_context.packageCount(context));
    return 0;
}

/// Counts the solvables the live sack still holds. This used to also honour
/// `pool->considered`; with that bitmap retired it is the reload-preserves-the-
/// solvable-set probe the handle tests actually assert on.
fn testVisibleSolvableCount(handle: ?*anyopaque) callconv(.c) u32 {
    const input = handleRefreshInput(handle) orelse return 0;
    const context = handleLiveContext(&input) orelse return 0;
    return @intCast(package_context.packageCount(context));
}

fn testRetireNullSack(handle: ?*anyopaque) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const context = handleLiveContext(&input) orelse return 0;
    var raw = input.repository_head;
    while (raw) |data| {
        const view = describeRepository(&input, data);
        if (view.live_repository) |raw_repository| {
            const repository: *package_context.Repository =
                @ptrCast(@alignCast(raw_repository));
            if (!package_context.removeRepository(context, repository)) return 0;
            if (view.live_repository_slot) |slot| slot.* = null;
            return 1;
        }
        raw = view.next;
    }
    return 0;
}

fn testPublicInitRepo(handle: ?*anyopaque) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, "extras") orelse return 0;
    const context = handleLiveContext(&input) orelse return 0;
    const result = initRepo(handle, entry.data, context);
    if (result != 0) return result;
    return 1;
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
    const repository: *package_context.Repository = @ptrCast(@alignCast(raw));
    const context = handleLiveContext(&input) orelse return 0;
    for (package_context.repositories(context), 1..) |candidate, index| {
        if (candidate == repository) return @intCast(index);
    }
    return 0;
}

fn testRepoPackageCount(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    const raw = entry.view.live_repository orelse return 0;
    const repository: *package_context.Repository = @ptrCast(@alignCast(raw));
    return @intCast(repository.model.packages.len);
}

fn testRepoBindingCount(
    handle: ?*anyopaque,
    id: ?[*:0]const u8,
) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 0;
    const entry = findHandleRepository(&input, id) orelse return 0;
    const context = handleLiveContext(&input) orelse return 0;
    var count: u32 = 0;
    for (package_context.repositories(context)) |repository| {
        if (repository.owner == entry.data) count += 1;
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
    const context = handleLiveContext(&input) orelse return 0;
    return @intFromBool(
        initRepo(null, data, context) ==
            error_codes.ERROR_TDNF_INVALID_PARAMETER and
            initRepo(handle, null, context) ==
                error_codes.ERROR_TDNF_INVALID_PARAMETER and
            initRepo(handle, data, null) ==
                error_codes.ERROR_TDNF_INVALID_PARAMETER and
            initRepo(null, null, null) ==
                error_codes.ERROR_TDNF_INVALID_PARAMETER,
    );
}

fn testPoolIndexesHealthy(handle: ?*anyopaque) callconv(.c) u32 {
    var input = handleRefreshInput(handle) orelse return 2;
    const context = handleLiveContext(&input) orelse return 2;
    const command_line = input.command_line_repository_slot.?.*;
    const repositories = package_context.repositories(context);
    for (repositories, 0..) |repository, index| {
        var managed = repository.kind == .installed or
            command_line == @as(*anyopaque, @ptrCast(repository));
        var data = input.repository_head;
        while (data) |value| {
            managed = managed or repository.owner == value;
            const view = describeRepository(&input, value);
            data = view.next;
        }
        if (!managed) return 3;
        for (repositories[index + 1 ..]) |candidate| {
            if (repository.owner != null and
                repository.owner == candidate.owner)
            {
                return 4;
            }
        }
    }
    return 1;
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
    indexes_identity: usize = 0,
    solvable_count: u32 = 0,
    repository_count: u32 = 0,
    digest: [32]u8 = [_]u8{0} ** 32,
};

fn testSackSnapshot(
    raw_sack: ?*anyopaque,
    raw_repository_id: ?[*:0]const u8,
    raw_output: ?*TestSackSnapshot,
) callconv(.c) u32 {
    const context: *package_context.Context =
        @ptrCast(@alignCast(raw_sack orelse return 0));
    const repository_id = std.mem.span(raw_repository_id orelse return 0);
    const output = raw_output orelse return 0;
    var repository_match: ?*package_context.Repository = null;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("tdnf.test-sack-snapshot/v1\x00");
    const repositories = package_context.repositories(context);
    for (repositories) |repository| {
        if (std.mem.eql(u8, repository.id, repository_id)) {
            if (repository_match != null) return 0;
            repository_match = repository;
        }
        for (repository.model.packages) |package| {
            inline for (.{
                repository.id,
                package.nevra.name,
                package.nevra.arch,
                package.nevra.version,
                package.nevra.release,
                package.checksum.kind,
                package.checksum.value,
            }) |value| {
                var length_bytes: [8]u8 = undefined;
                writeBigEndian(&length_bytes, value.len);
                hasher.update(&length_bytes);
                hasher.update(value);
            }
        }
    }
    const repository = repository_match orelse return 0;
    output.* = .{
        .pool_identity = package_context.identity(context),
        .repository_identity = @intFromPtr(repository),
        .indexes_identity = package_context.identity(context),
        .solvable_count = @intCast(package_context.packageCount(context)),
        .repository_count = @intCast(repositories.len),
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
        .context = @ptrCast(@alignCast(raw_pool orelse
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
    @export(&initCommandLineRepository, .{
        .name = "TDNFTransactionPlanInitCommandLineRepository",
        .visibility = .hidden,
    });
    if (!integration_options.standalone_test) {
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
        @export(&testVisibleSolvableCount, .{
            .name = "TDNFTransactionPlanTestVisibleSolvableCount",
            .visibility = .hidden,
        });
        @export(&testSackSolvableCount, .{
            .name = "TDNFTransactionPlanTestSackSolvableCount",
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

fn testPlanData(architecture: []const u8) transaction_plan.Data {
    const zero_sha = "0" ** 64;
    return .{
        .actions = &.{},
        .environment = .{
            .architecture = architecture,
            .distro = "test",
            .policy = .{
                .allow_erasing = false,
                .allow_multilib = true,
                .all_deps = false,
                .best = true,
                .clean_requirements_on_remove = false,
                .excludes = &.{},
                .force_architecture = null,
                .include_installed = true,
                .installonly_limit = 3,
                .installonly_names = &.{},
                .install_weak_dependencies = true,
                .keep_orphans = false,
                .locked_names = &.{},
                .min_versions = &.{},
                .protected_names = &.{},
                .skip_broken = false,
            },
            .releasever = "1",
            .resolution_status = .resolved,
            .rpmdb = .{
                .backend = .sqlite,
                .cookie_sha256 = zero_sha,
                .package_set_sha256 = zero_sha,
            },
        },
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &.{},
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{},
        .skipped = &.{},
    };
}

test "takePublished transfers plan ownership out of resolver scratch state" {
    const allocator = std.testing.allocator;
    const state = try State.create(allocator);
    state.setEnabled(true);
    try std.testing.expectEqual(
        @as(?*transaction_plan.Plan, null),
        state.takePublished(),
    );

    state.pending_plan = try transaction_plan.Plan.create(
        allocator,
        testPlanData("aarch64"),
    );
    try state.publish();

    const plan = state.takePublished() orelse return error.MissingPlan;
    defer plan.destroy();
    try std.testing.expectEqual(@as(?*transaction_plan.Plan, null), state.plan);
    try std.testing.expectEqual(
        @as(?*const transaction_plan.Data, null),
        state.model(),
    );

    // Releasing every piece of resolver scratch storage must leave the
    // transferred plan intact and canonically readable.
    state.destroy();
    try std.testing.expectEqualStrings(
        "aarch64",
        plan.model().environment.architecture,
    );
    const json = try plan.canonicalJsonAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "\"schema\":\"" ++ transaction_plan.schema ++ "\"",
    ) != null);
}

test "takePublished never transfers an unpublished pending plan" {
    const allocator = std.testing.allocator;
    const state = try State.create(allocator);
    defer state.destroy();
    state.setEnabled(true);

    state.pending_plan = try transaction_plan.Plan.create(
        allocator,
        testPlanData("x86_64"),
    );
    try std.testing.expectEqual(
        @as(?*transaction_plan.Plan, null),
        state.takePublished(),
    );
    try std.testing.expect(state.pending_plan != null);
}

test "takePublished leaves a republished plan owned by the state" {
    const allocator = std.testing.allocator;
    const state = try State.create(allocator);
    defer state.destroy();
    state.setEnabled(true);

    state.pending_plan = try transaction_plan.Plan.create(
        allocator,
        testPlanData("x86_64"),
    );
    try state.publish();
    const first = state.takePublished() orelse return error.MissingPlan;
    first.destroy();

    state.pending_plan = try transaction_plan.Plan.create(
        allocator,
        testPlanData("riscv64"),
    );
    try state.publish();
    try std.testing.expectEqualStrings(
        "riscv64",
        state.model().?.environment.architecture,
    );
}
