//! Owning live-input adapter for native live solves.

const std = @import("std");
const builtin = @import("builtin");
const available_loader = @import("available_loader.zig");
const cmdline_repository = @import("cmdline_repository.zig");
const directory_repository = @import("directory_repository.zig");
const installed_repository = @import("installed_repository.zig");
const model = @import("model.zig");
const rpmpkg = if (builtin.is_test) @import("rpmpkg.zig") else struct {};
const sqlite = if (builtin.is_test) @import("sqlite") else struct {};
const solver_identity = @import("solver_identity.zig");
const solver_model = @import("solver_model.zig");
const solver_native = @import("solver_native.zig");
const solver_result_abi = @import("solver_result_abi.zig");
const solver_result_c = @import("solver_result_c.zig");
const solver_legacy_abi = @import("solver_legacy_abi.zig");
const solver_legacy_result = @import("solver_legacy_result.zig");
const solver_visibility = @import("solver_visibility.zig");

pub const system_repository_id = "@System";

/// libsolv's pseudo-repository for packages named directly on the command
/// line. Job selectors carrying this repository id resolve against the
/// synthetic repository built from `Input.cmdline_rpm_paths`.
pub const cmdline_repository_id = "@cmdline";

pub const RepositoryInput = struct {
    id: []const u8,
    /// Directory holding the repository's downloaded metadata. Empty when
    /// `rpm_directory` is set, because such a repository has no metadata.
    cache_dir: []const u8,
    /// Directory of `.rpm` files backing the repository, as `--repofromdir`
    /// declares. Null for an ordinary metadata-backed repository.
    rpm_directory: ?[]const u8 = null,
    snapshot_file: ?[]const u8 = null,
    priority: i32 = solver_model.default_repository_priority,
    cost: u32 = solver_model.default_repository_cost,
};

pub const JobInput = struct {
    selector: solver_identity.AvailableSelector,
    /// The libsolv job-queue pair this job was built from, which is how the
    /// published transaction plan numbers jobs. Null for a job the request
    /// layer never queued.
    queue_pair: ?u32 = null,
};

pub const EraseJobInput = struct {
    selector: solver_identity.AvailableSelector,
    /// See `JobInput.queue_pair`. An erase names a NEVRA the rpmdb may hold
    /// more than once, so a single pair can expand into several jobs.
    queue_pair: ?u32 = null,
};

pub const Input = struct {
    repositories: []const RepositoryInput,
    rpmdb: installed_repository.Source,
    native_arch: []const u8,
    jobs: []const JobInput,
    /// Filesystem path of the `.rpm` file backing each entry of `jobs`, or
    /// null when that job targets an ordinary repository. Either empty or
    /// exactly as long as `jobs`.
    cmdline_rpm_paths: []const ?[:0]const u8 = &.{},
    erase_jobs: []const EraseJobInput = &.{},
    /// Null means the caller did not provide install-reason data, so every
    /// installed package keeps `.unknown` and stays a clean-deps root.
    user_installed_names: ?[]const []const u8 = null,
    /// Parallel to `user_installed_names`: the job-queue pair each mark came
    /// from. Either empty or exactly as long as `user_installed_names`. When
    /// supplied, every mark also becomes a `.user_installed` job so the
    /// published plan can name the package behind its queue pair; the marks
    /// already reach the solve as install reasons either way, so the jobs
    /// only restate what `applyInstallReasons` decided.
    ///
    /// Only a caller that publishes a transaction plan should supply these.
    /// The jobs are inert to the search but not to the skip-broken policy,
    /// which admits a goal only when every job is an exact install, so a
    /// request that never needed the pairs must not pay for them.
    user_installed_queue_pairs: []const ?u32 = &.{},
    /// Null means the caller did not provide an authoritative considered map.
    hidden_available: ?[]const JobInput = null,
    include_installed: bool = true,
    update_all: bool = false,
    dist_sync_all: bool = false,
    locked_names: []const []const u8 = &.{},
    /// Parallel to `locked_names`: the job-queue pair each lock came from.
    /// Either empty or exactly as long as `locked_names`.
    locked_queue_pairs: []const ?u32 = &.{},
    /// The job-queue pair the `update_all` or `dist_sync_all` job came from.
    global_queue_pair: ?u32 = null,
    installonly_names: []const []const u8 = &.{},
    /// Maximum simultaneously installed versions of an `installonly_names`
    /// package. The native solver derives the evictions that keep the count
    /// at or below this, exactly as the libsolv retry loop in TDNFSolv did.
    installonly_limit: u32 = std.math.maxInt(u32),
    best: bool = false,
    allow_erasing: bool = false,
    clean_deps: bool = false,
    skip_broken: bool = false,
    protected_names: []const []const u8 = &.{},
};

pub const ProduceError =
    available_loader.LoadError ||
    cmdline_repository.LoadError ||
    directory_repository.LoadError ||
    installed_repository.LoadError ||
    solver_model.UniverseInitError ||
    solver_identity.InitError ||
    solver_identity.ResolveError ||
    solver_visibility.BuildError ||
    solver_native.ProjectedSolveError ||
    error{
        InvalidInput,
        UnsupportedInput,
    };

/// Move-only owner for every model used by a native live solve.
pub const OwnedSolve = struct {
    /// Heap-allocated so the arena keeps one address for its whole life.
    /// `universe` is built from this arena and `solver_model.Universe`
    /// retains the `std.mem.Allocator` it was given, whose `.ptr` is the
    /// arena itself. This owner is returned by value and moved again by
    /// `produce`, so an inline arena would strand that retained pointer in
    /// a dead stack frame.
    arena_state: *std.heap.ArenaAllocator,
    universe: *solver_model.Universe,
    solved: solver_native.OwnedSolveResult,
    /// The jobs the solve ran, in the order they were queued. Callers that
    /// snapshot the solve need them; the solver itself reads them off `solved`.
    jobs: []const solver_model.Job,
    /// Available packages an `--exclude`-style filter kept out of the solve.
    /// Empty when nothing was filtered.
    hidden: []const solver_model.PackageId,
    /// Parallel to `jobs`: the libsolv job-queue pair each job was built
    /// from, which is how the published transaction plan numbers jobs. Null
    /// marks a job the request layer never queued.
    job_origins: []const ?u32,

    pub fn deinit(self: *OwnedSolve) void {
        self.solved.deinit();
        // Universe arrays share the enclosing arena and are released below.
        const child_allocator = self.arena_state.child_allocator;
        self.arena_state.deinit();
        child_allocator.destroy(self.arena_state);
        self.* = undefined;
    }

    pub fn buildOwnedC(
        self: *const OwnedSolve,
    ) solver_result_c.BuildError!*solver_result_abi.Result {
        return self.solved.buildOwnedC();
    }
};

/// Move-only owner for a native live universe that has not been solved yet.
/// The capture layer needs one of these to describe a request that failed
/// before, or instead of, a solve.
pub const Prepared = struct {
    /// Heap-allocated for the same reason as `OwnedSolve.arena_state`: the
    /// retained `universe.allocator` points at the arena, and this owner is
    /// returned by value and then moved into an `OwnedSolve`.
    arena_state: *std.heap.ArenaAllocator,
    universe: *solver_model.Universe,
    /// The jobs the request translated to, in the order they would be queued.
    jobs: []const solver_model.Job,
    /// Available packages an `--exclude`-style filter would keep out of the
    /// solve. Empty when nothing was filtered.
    hidden: []const solver_model.PackageId,
    /// Parallel to `jobs`: the libsolv job-queue pair each job was built
    /// from. Null marks a job the request layer never queued.
    job_origins: []const ?u32,
    /// What the filtered universe looks like to the solver.
    visibility: solver_visibility.Projection,
    /// Owned by the arena, so it outlives `input`.
    native_arch: []const u8,

    pub fn deinit(self: *Prepared) void {
        self.visibility.deinit();
        // Universe arrays share the enclosing arena and are released below.
        const child_allocator = self.arena_state.child_allocator;
        self.arena_state.deinit();
        child_allocator.destroy(self.arena_state);
        self.* = undefined;
    }
};

/// Builds the universe and translates the request into jobs, stopping short
/// of the solve itself.
pub fn prepare(
    parent_allocator: std.mem.Allocator,
    input: Input,
) ProduceError!Prepared {
    const global_job_count: usize =
        @as(usize, @intFromBool(input.update_all)) +
        @as(usize, @intFromBool(input.dist_sync_all));
    // A universe with no repositories is still solvable when the installed set
    // is included: that is what `--disablerepo=*` produces. A request with no
    // jobs at all is likewise solvable, and its answer is an empty
    // transaction: `history undo` and `history rollback` reach a target whose
    // delta is already satisfied and issue nothing.
    if ((input.repositories.len == 0 and !input.include_installed) or
        input.native_arch.len == 0)
    {
        return error.InvalidInput;
    }
    if (global_job_count != 0 and
        (global_job_count != 1 or
            input.jobs.len != 0 or
            input.erase_jobs.len != 0 or
            !input.include_installed or
            (input.clean_deps and input.dist_sync_all)))
    {
        return error.UnsupportedInput;
    }
    if (input.locked_names.len != 0 and
        (!input.include_installed or
            (global_job_count != 0 and input.best)))
    {
        return error.UnsupportedInput;
    }
    if (input.installonly_names.len != 0 and
        (!input.include_installed or
            input.skip_broken))
    {
        return error.UnsupportedInput;
    }
    if (input.cmdline_rpm_paths.len != 0 and
        input.cmdline_rpm_paths.len != input.jobs.len)
    {
        return error.InvalidInput;
    }

    const arena_state = try parent_allocator.create(std.heap.ArenaAllocator);
    errdefer parent_allocator.destroy(arena_state);
    arena_state.* = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();
    const cmdline_paths = try collectCmdlineRpmPaths(arena, input);
    const available_offset: usize = @intFromBool(input.include_installed);
    const cmdline_count: usize = @intFromBool(cmdline_paths.len != 0);
    const repository_inputs = try arena.alloc(
        solver_model.RepositoryInput,
        input.repositories.len + available_offset + cmdline_count,
    );
    const models = try arena.alloc(
        @import("model.zig").RepositoryModel,
        input.repositories.len + available_offset + cmdline_count,
    );

    if (input.include_installed) {
        const installed = try installed_repository.loadModel(
            arena,
            input.rpmdb,
            .{
                .include_relations = true,
                .include_files = true,
                .include_changelogs = false,
            },
        );
        var installed_states = installed.installed_states;
        models[0] = installed.repository;
        if (input.user_installed_names) |user_installed_names| {
            try applyInstallReasons(
                arena,
                models[0].packages,
                &installed_states,
                user_installed_names,
            );
        }
        repository_inputs[0] = .{
            .id = system_repository_id,
            .model = &models[0],
            .kind = .installed,
            .installed_states = installed_states,
        };
    }

    const available_models =
        models[available_offset..][0..input.repositories.len];
    for (input.repositories, available_models, 0..) |
        repository,
        *loaded,
        index,
    | {
        if (repository.id.len == 0) {
            return error.InvalidInput;
        }
        if (repository.rpm_directory) |directory| {
            if (directory.len == 0) return error.InvalidInput;
        } else if (repository.cache_dir.len == 0) {
            return error.InvalidInput;
        }
        if (repository.snapshot_file != null and
            input.hidden_available == null)
        {
            return error.UnsupportedInput;
        }
        if (repository.priority == std.math.minInt(i32)) {
            return error.UnsupportedInput;
        }
        loaded.* = if (repository.rpm_directory) |directory|
            // `.read` matches libsolv's `readRpmsFromDir`, which the
            // transaction-plan path still uses for the same directory.
            // Package order decides which problem the solver reports, so a
            // sorted walk here answered differently than the plan did (#266).
            try directory_repository.loadModelOrdered(arena, directory, .read)
        else
            try available_loader.loadCacheModel(
                arena,
                repository.cache_dir,
                .{
                    .include_filelists = true,
                    .include_updateinfo = false,
                    .include_other = false,
                },
            );
        repository_inputs[index + available_offset] = .{
            .id = try arena.dupe(u8, repository.id),
            .model = loaded,
            .priority = repository.priority,
            .cost = repository.cost,
        };
    }

    if (cmdline_count != 0) {
        const last = repository_inputs.len - 1;
        models[last] = try cmdline_repository.loadModel(arena, cmdline_paths);
        repository_inputs[last] = .{
            .id = cmdline_repository_id,
            .model = &models[last],
            // libsolv gives the command-line repository the default priority
            // and cost; only the explicit job makes its packages reachable.
            .priority = solver_model.default_repository_priority,
            .cost = solver_model.default_repository_cost,
        };
    }

    const universe = try arena.create(solver_model.Universe);
    universe.* = try solver_model.Universe.init(arena, repository_inputs);
    errdefer universe.deinit();

    var identity = try solver_identity.Index.init(
        parent_allocator,
        universe,
    );
    defer identity.deinit();
    // An erase names a NEVRA, and the rpmdb may hold several rows under it.
    // Each row becomes its own erase job, so resolve them before sizing the
    // job list.
    const erase_targets = try arena.alloc(
        []const solver_model.PackageId,
        input.erase_jobs.len,
    );
    var erase_job_count: usize = 0;
    for (input.erase_jobs, erase_targets) |job, *targets| {
        targets.* = try identity.resolveInstalledNevraAll(arena, job.selector);
        erase_job_count += targets.len;
    }
    if (input.locked_queue_pairs.len != 0 and
        input.locked_queue_pairs.len != input.locked_names.len)
    {
        return error.InvalidInput;
    }
    // A user-installed mark names an installed package, and the rpmdb may
    // hold several rows under that name, so size them the same way erases
    // are sized.
    const user_installed_names = input.user_installed_names orelse &.{};
    if (input.user_installed_queue_pairs.len != 0 and
        input.user_installed_queue_pairs.len != user_installed_names.len)
    {
        return error.InvalidInput;
    }
    const user_installed_targets = try arena.alloc(
        []const solver_model.PackageId,
        input.user_installed_queue_pairs.len,
    );
    var user_installed_job_count: usize = 0;
    for (user_installed_targets, 0..) |*targets, index| {
        targets.* = try installedPackagesNamed(
            arena,
            universe,
            user_installed_names[index],
        );
        user_installed_job_count += targets.len;
    }
    const jobs = try arena.alloc(
        solver_model.Job,
        input.jobs.len + erase_job_count + input.locked_names.len +
            user_installed_job_count + global_job_count,
    );
    // Mirrors `jobs` exactly, so every branch below fills both.
    const job_origins = try arena.alloc(?u32, jobs.len);
    @memset(job_origins, null);
    for (input.jobs, job_origins[0..input.jobs.len]) |job, *origin| {
        origin.* = job.queue_pair;
    }
    for (input.jobs, jobs[0..input.jobs.len]) |job, *translated| {
        translated.* = .{
            .action = .install,
            .selection = .{
                .package = try identity.resolveAvailable(job.selector),
            },
            .reason = .user,
        };
    }
    var erase_index = input.jobs.len;
    for (input.erase_jobs, erase_targets) |job, targets| {
        for (targets) |package| {
            jobs[erase_index] = .{
                .action = .erase,
                .selection = .{ .package = package },
                .reason = .user,
            };
            // Every row this NEVRA expanded to came from the one pair.
            job_origins[erase_index] = job.queue_pair;
            erase_index += 1;
        }
    }
    const exact_job_count = input.jobs.len + erase_job_count;
    if (input.locked_queue_pairs.len != 0) {
        @memcpy(
            job_origins[exact_job_count .. exact_job_count +
                input.locked_names.len],
            input.locked_queue_pairs,
        );
    }
    for (
        input.locked_names,
        jobs[exact_job_count .. exact_job_count + input.locked_names.len],
    ) |name, *translated| {
        if (name.len == 0) return error.InvalidInput;
        translated.* = .{
            .action = .lock,
            .selection = .{ .name = try arena.dupe(u8, name) },
            .reason = .policy,
        };
    }
    var user_installed_index = exact_job_count + input.locked_names.len;
    for (user_installed_targets, 0..) |targets, index| {
        if (user_installed_names[index].len == 0) return error.InvalidInput;
        for (targets) |package| {
            jobs[user_installed_index] = .{
                .action = .user_installed,
                .selection = .{ .package = package },
                .reason = .policy,
            };
            // Every row this name expanded to came from the one pair.
            job_origins[user_installed_index] =
                input.user_installed_queue_pairs[index];
            user_installed_index += 1;
        }
    }
    if (input.update_all) {
        jobs[jobs.len - 1] = .{
            .action = .update,
            .selection = .all,
            .reason = .user,
        };
        job_origins[jobs.len - 1] = input.global_queue_pair;
    } else if (input.dist_sync_all) {
        jobs[jobs.len - 1] = .{
            .action = .dist_sync,
            .selection = .all,
            .reason = .user,
        };
        job_origins[jobs.len - 1] = input.global_queue_pair;
    }

    var hidden_packages: []const solver_model.PackageId = &.{};
    var visibility = if (input.hidden_available) |hidden| blk: {
        const considered = try arena.alloc(bool, universe.packages.len);
        @memset(considered, true);
        const hidden_ids = try arena.alloc(solver_model.PackageId, hidden.len);
        for (hidden, hidden_ids) |item, *hidden_id| {
            const package = try identity.resolveAvailable(item.selector);
            const package_index: usize = @intFromEnum(package);
            if (!considered[package_index]) return error.InvalidInput;
            considered[package_index] = false;
            hidden_id.* = package;
        }
        hidden_packages = hidden_ids;
        break :blk try solver_visibility.Projection.initConsidered(
            parent_allocator,
            universe,
            considered,
        );
    } else try solver_visibility.Projection.init(
        parent_allocator,
        universe,
        .{},
    );
    errdefer visibility.deinit();

    return .{
        .arena_state = arena_state,
        .universe = universe,
        .jobs = jobs,
        .job_origins = job_origins,
        .hidden = hidden_packages,
        .visibility = visibility,
        .native_arch = try arena.dupe(u8, input.native_arch),
    };
}

pub const DirectoryCheckInput = struct {
    /// Directory of `.rpm` files to check. Every package found under it is
    /// requested; nothing else is in the universe.
    directory: []const u8,
    native_arch: []const u8,
};

/// Builds the universe `tdnf check-local <dir>` checks and the request it
/// makes of it.
///
/// The command is deliberately **directory-only**: libsolv built a fresh
/// command-line pool holding just the `.rpm` files under the directory and
/// never read the rpmdb or any configured repository into it, so a
/// requirement satisfied only by an installed package is still a problem.
/// The request is one install job per package, queued in the order the
/// directory walk produced them, which is the order libsolv pushed its jobs
/// in and therefore the order its problems came back in.
pub fn prepareDirectoryCheck(
    parent_allocator: std.mem.Allocator,
    input: DirectoryCheckInput,
) ProduceError!Prepared {
    if (input.directory.len == 0 or input.native_arch.len == 0) {
        return error.InvalidInput;
    }

    const arena_state = try parent_allocator.create(std.heap.ArenaAllocator);
    errdefer parent_allocator.destroy(arena_state);
    arena_state.* = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();

    const models = try arena.alloc(model.RepositoryModel, 1);
    models[0] = try directory_repository.loadModelOrdered(
        arena,
        input.directory,
        .read,
    );
    const repository_inputs = try arena.alloc(
        solver_model.RepositoryInput,
        1,
    );
    repository_inputs[0] = .{
        .id = cmdline_repository_id,
        .model = &models[0],
        .priority = solver_model.default_repository_priority,
        .cost = solver_model.default_repository_cost,
    };

    const universe = try arena.create(solver_model.Universe);
    universe.* = try solver_model.Universe.init(arena, repository_inputs);
    errdefer universe.deinit();

    // One install job per package, addressed by package id: the directory may
    // hold the same NEVRA under two file names, and libsolv requested both.
    const jobs = try arena.alloc(solver_model.Job, universe.packages.len);
    for (universe.packages, jobs) |package, *job| {
        job.* = .{
            .action = .install,
            .selection = .{ .package = package.id },
            .reason = .user,
        };
    }
    const job_origins = try arena.alloc(?u32, jobs.len);
    @memset(job_origins, null);

    var visibility = try solver_visibility.Projection.init(
        parent_allocator,
        universe,
        .{},
    );
    errdefer visibility.deinit();

    return .{
        .arena_state = arena_state,
        .universe = universe,
        .jobs = jobs,
        .job_origins = job_origins,
        .hidden = &.{},
        .visibility = visibility,
        .native_arch = try arena.dupe(u8, input.native_arch),
    };
}

pub fn produce(
    parent_allocator: std.mem.Allocator,
    input: Input,
) ProduceError!OwnedSolve {
    var prepared = try prepare(parent_allocator, input);
    var solved = solver_native.solveProjected(
        parent_allocator,
        prepared.universe,
        &prepared.visibility,
        .{ .jobs = prepared.jobs },
        .{
            .architecture = .{ .native_arch = prepared.native_arch },
            .best = input.best,
            .allow_erasing = input.allow_erasing or input.erase_jobs.len != 0,
            .clean_deps = input.clean_deps,
            .skip_broken = input.skip_broken,
            .protected_names = input.protected_names,
            .installonly_limit = input.installonly_limit,
            .installonly_names = input.installonly_names,
        },
    ) catch |err| {
        prepared.deinit();
        return err;
    };
    errdefer solved.deinit();

    // The projection is only an input to the solve, and a retained solve is
    // held for as long as the caller reads the plan, so drop it here rather
    // than carrying it.
    prepared.visibility.deinit();
    return .{
        .arena_state = prepared.arena_state,
        .universe = prepared.universe,
        .solved = solved,
        .jobs = prepared.jobs,
        .job_origins = prepared.job_origins,
        .hidden = prepared.hidden,
    };
}

/// Mirrors the libsolv `SOLVER_USERINSTALLED` feed: names present in
/// `user_installed_names` were requested by the user, everything else on the
/// system arrived as a dependency and is therefore clean-deps eligible.
/// Collects the distinct `.rpm` paths named on the command line, preserving
/// argument order. Duplicates are folded because libsolv resolves repeated
/// arguments to the same solvable, and two identical NEVRAs in one repository
/// would make the job selector ambiguous.
fn collectCmdlineRpmPaths(
    arena: std.mem.Allocator,
    input: Input,
) ProduceError![]const [:0]const u8 {
    if (input.cmdline_rpm_paths.len == 0) return &.{};
    var paths = try std.ArrayList([:0]const u8).initCapacity(
        arena,
        input.cmdline_rpm_paths.len,
    );
    for (input.cmdline_rpm_paths, input.jobs) |maybe_path, job| {
        const is_cmdline_job = std.mem.eql(
            u8,
            job.selector.repository,
            cmdline_repository_id,
        );
        const path = maybe_path orelse "";
        if (!is_cmdline_job) {
            // A path is meaningless for any other repository, so the caller
            // and the selector disagree about where this package came from.
            if (path.len != 0) return error.InvalidInput;
            continue;
        }
        // libsolv can hold a command-line solvable with no recorded location;
        // the native side simply has no way to rebuild it.
        if (path.len == 0) return error.UnsupportedInput;
        for (paths.items) |seen| {
            if (std.mem.eql(u8, seen, path)) break;
        } else {
            paths.appendAssumeCapacity(path);
        }
    }
    return paths.items;
}

/// Every installed row the universe holds under `name`, in universe order.
fn installedPackagesNamed(
    arena: std.mem.Allocator,
    universe: *const solver_model.Universe,
    name: []const u8,
) ![]const solver_model.PackageId {
    var found: std.ArrayList(solver_model.PackageId) = .empty;
    for (universe.packages, 0..) |package, index| {
        if (package.installed == null) continue;
        if (!std.mem.eql(u8, package.source.nevra.name, name)) continue;
        try found.append(arena, @enumFromInt(index));
    }
    return found.items;
}

fn applyInstallReasons(
    arena: std.mem.Allocator,
    packages: []const model.Package,
    installed_states: *[]const solver_model.InstalledState,
    user_installed_names: []const []const u8,
) !void {
    if (packages.len != installed_states.len) return error.InvalidInput;
    const states = try arena.alloc(solver_model.InstalledState, packages.len);
    for (packages, installed_states.*, states) |package, state, *updated| {
        var user_installed = false;
        for (user_installed_names) |name| {
            if (std.mem.eql(u8, name, package.nevra.name)) {
                user_installed = true;
                break;
            }
        }
        updated.* = state;
        updated.reason = if (user_installed) .user else .automatic;
    }
    installed_states.* = states;
}

/// Produce the native transaction for `input` in the C ABI result shape and
/// hand ownership to the caller, who must release it with
/// `solver_result_c.freeOwnedResult`.
pub fn solveOwnedC(
    parent_allocator: std.mem.Allocator,
    input: Input,
) (ProduceError || solver_result_c.BuildError)!*solver_result_abi.Result {
    var solved = try produce(parent_allocator, input);
    defer solved.deinit();
    return solved.buildOwnedC();
}

const fixture_repomd =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
    \\  <data type="primary">
    \\    <checksum type="sha256">153e9e69f56e580f4a30074888431cf7297ccdc821a603d6b0fc7cddc84ed4a0</checksum>
    \\    <location href="repodata/primary.xml"/>
    \\    <size>927</size>
    \\  </data>
    \\</repomd>
;

const fixture_primary =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common" xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="2">
    \\  <package type="rpm">
    \\    <name>candidate</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1.0" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">abcdef</checksum>
    \\    <summary>candidate</summary>
    \\    <location href="packages/candidate.rpm"/>
    \\    <format>
    \\      <rpm:conflicts>
    \\        <rpm:entry name="installed-blocker"/>
    \\      </rpm:conflicts>
    \\    </format>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>broken</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1.0" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">fedcba</checksum>
    \\    <summary>broken</summary>
    \\    <location href="packages/broken.rpm"/>
    \\    <format>
    \\      <rpm:requires>
    \\        <rpm:entry name="missing-capability"/>
    \\      </rpm:requires>
    \\    </format>
    \\  </package>
    \\</metadata>
;

const Fixture = struct {
    tmp: std.testing.TmpDir,

    fn create() !Fixture {
        var fixture = Fixture{ .tmp = std.testing.tmpDir(.{}) };
        errdefer fixture.tmp.cleanup();
        try fixture.tmp.dir.createDirPath(
            std.testing.io,
            "cache/repodata",
        );
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{
                .sub_path = "cache/repodata/repomd.xml",
                .data = fixture_repomd,
            },
        );
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{
                .sub_path = "cache/repodata/primary.xml",
                .data = fixture_primary,
            },
        );
        return fixture;
    }

    fn cleanup(self: *Fixture) void {
        self.tmp.cleanup();
        self.* = undefined;
    }

    fn addInstalled(self: *Fixture, hnum: u32, name: []const u8) !void {
        return self.addInstalledVersion(hnum, name, "1.0");
    }

    fn addInstalledVersion(
        self: *Fixture,
        hnum: u32,
        name: []const u8,
        version: []const u8,
    ) !void {
        const blob = try rpmpkg.makeMinimalHeaderForTest(
            std.testing.allocator,
            name,
            version,
            "1",
            "x86_64",
        );
        defer std.testing.allocator.free(blob);
        try self.tmp.dir.createDirPath(std.testing.io, "var/lib/rpm");
        var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const db = try sqlite.Database.open(.{
            .path = self.path(&path_buffer, "var/lib/rpm/rpmdb.sqlite"),
        });
        defer db.close();
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS Packages (
            \\    hnum INTEGER PRIMARY KEY,
            \\    blob BLOB NOT NULL
            \\)
        , .{});
        const blob_hex = try hexLower(std.testing.allocator, blob);
        defer std.testing.allocator.free(blob_hex);
        const sql = try std.fmt.allocPrint(
            std.testing.allocator,
            "INSERT INTO Packages (hnum, blob) VALUES ({d}, x'{s}')",
            .{ hnum, blob_hex },
        );
        defer std.testing.allocator.free(sql);
        try db.exec(sql, .{});
    }

    fn addCmdlineRpm(
        self: *Fixture,
        buffer: *[std.Io.Dir.max_path_bytes]u8,
        name: []const u8,
    ) ![:0]const u8 {
        const bytes = try rpmpkg.makeMinimalRpmBytesForTest(
            std.testing.allocator,
            name,
            "1.0",
            "1",
            "x86_64",
        );
        defer std.testing.allocator.free(bytes);
        var sub_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const sub_path = try std.fmt.bufPrint(
            &sub_path_buffer,
            "{s}.rpm",
            .{name},
        );
        try self.tmp.dir.writeFile(std.testing.io, .{
            .sub_path = sub_path,
            .data = bytes,
        });
        return self.path(buffer, sub_path);
    }

    fn path(
        self: *const Fixture,
        buffer: *[std.Io.Dir.max_path_bytes]u8,
        suffix: []const u8,
    ) [:0]const u8 {
        return std.fmt.bufPrintZ(
            buffer,
            ".zig-cache/tmp/{s}/{s}",
            .{ &self.tmp.sub_path, suffix },
        ) catch @panic("fixture path too long");
    }
};

fn hexLower(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) std.mem.Allocator.Error![]u8 {
    const digits = "0123456789abcdef";
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, index| {
        out[index * 2] = digits[byte >> 4];
        out[index * 2 + 1] = digits[byte & 0x0f];
    }
    return out;
}

fn fixtureInput(
    fixture: *const Fixture,
    root_buffer: *[std.Io.Dir.max_path_bytes]u8,
    cache_buffer: *[std.Io.Dir.max_path_bytes]u8,
    repositories: *[1]RepositoryInput,
    jobs: *[1]JobInput,
) Input {
    repositories[0] = .{
        .id = "repo",
        .cache_dir = fixture.path(cache_buffer, "cache"),
    };
    jobs[0] = .{
        .selector = .{
            .repository = "repo",
            .name = "candidate",
            .epoch = null,
            .version = "1.0",
            .release = "1",
            .arch = "x86_64",
        },
    };
    return .{
        .repositories = repositories,
        .rpmdb = .{ .root_dir = fixture.path(root_buffer, "") },
        .native_arch = "x86_64",
        .jobs = jobs,
    };
}

test "live producer owns loaded inputs and exact install result" {
    var fixture = try Fixture.create();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var solved = try produce(
        std.testing.allocator,
        fixtureInput(
            &fixture,
            &root_buffer,
            &cache_buffer,
            &repositories,
            &jobs,
        ),
    );
    fixture.cleanup();
    defer solved.deinit();

    try std.testing.expectEqual(
        @as(usize, 1),
        solved.solved.result.selected.len,
    );
    const selected = solved.universe.package(
        solved.solved.result.selected[0],
    ).?;
    try std.testing.expectEqualStrings(
        "candidate",
        selected.source.nevra.name,
    );
    const c_result = try solved.buildOwnedC();
    defer solver_result_c.freeOwnedResult(c_result);
    try std.testing.expectEqual(
        @as(u32, 1),
        c_result.dwSelectedPackageCount,
    );
}

test "live producer can omit the installed repository" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.rpmdb = .{ .root_dir = "/native-solver-alldeps-no-rpmdb" };
    input.include_installed = false;
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    try std.testing.expectEqual(@as(usize, 1), solved.universe.repositories.len);
    try std.testing.expectEqual(
        solver_model.RepositoryKind.available,
        solved.universe.repositories[0].kind,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        solved.solved.result.selected.len,
    );
}

test "live producer translates a single update-all job" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalledVersion(41, "candidate", "0.9");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.jobs = &.{};
    input.update_all = true;
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), actions.len);
    try std.testing.expectEqual(solver_model.ActionKind.upgrade, actions[0].kind);

    input.jobs = &jobs;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );
    input.jobs = &.{};
    input.clean_deps = true;
    var cleaned = try produce(std.testing.allocator, input);
    defer cleaned.deinit();
    const cleaned_actions = cleaned.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), cleaned_actions.len);
    try std.testing.expectEqual(
        solver_model.ActionKind.upgrade,
        cleaned_actions[0].kind,
    );
}

test "live producer translates a single distro-sync-all job" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalledVersion(41, "candidate", "2.0");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.jobs = &.{};
    input.dist_sync_all = true;
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), actions.len);
    try std.testing.expectEqual(
        solver_model.ActionKind.downgrade,
        actions[0].kind,
    );

    input.update_all = true;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );
}

test "live producer translates installed package locks by name" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalledVersion(41, "candidate", "0.9");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.jobs = &.{};
    input.update_all = true;
    input.locked_names = &.{"candidate"};
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    try std.testing.expectEqual(
        @as(usize, 0),
        solved.solved.result.outcome.actions.len,
    );

    input.best = true;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );
    input.best = false;
    input.include_installed = false;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );
}

test "live producer retains installed multiversion packages" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalledVersion(41, "candidate", "0.9");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.installonly_names = &.{"candidate"};
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    try std.testing.expectEqual(
        @as(usize, 2),
        solved.solved.result.selected.len,
    );
    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), actions.len);
    try std.testing.expectEqual(solver_model.ActionKind.install, actions[0].kind);
    try std.testing.expectEqual(@as(usize, 0), actions[0].priors.len);

    input.include_installed = false;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );
    input.include_installed = true;
    input.clean_deps = true;
    // clean-deps cannot seed a removal without an erase job, so an
    // install-only install stays supported and keeps the same projection
    var cleaned = try produce(std.testing.allocator, input);
    defer cleaned.deinit();
    try std.testing.expectEqual(
        @as(usize, 2),
        cleaned.solved.result.selected.len,
    );
    const cleaned_actions = cleaned.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), cleaned_actions.len);
    try std.testing.expectEqual(
        solver_model.ActionKind.install,
        cleaned_actions[0].kind,
    );
    try std.testing.expectEqual(@as(usize, 0), cleaned_actions[0].priors.len);

    input.skip_broken = true;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );
}

fn testPackageNamed(name: []const u8) model.Package {
    return .{
        .pkg_id = name,
        .nevra = .{
            .name = name,
            .version = "1.0",
            .release = "1",
            .arch = "x86_64",
        },
        .checksum = .{ .kind = "sha256", .value = "00", .is_pkgid = true },
        .location = .{ .href = name },
    };
}

test "install reasons follow the user-installed name feed" {
    const packages = [_]model.Package{
        testPackageNamed("user-picked"),
        testPackageNamed("pulled-in"),
    };
    const initial = [_]solver_model.InstalledState{
        .{ .rpmdb_hnum = 11, .reason = .unknown, .install_order = 1 },
        .{ .rpmdb_hnum = 12, .reason = .unknown, .install_order = 2 },
    };
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var states: []const solver_model.InstalledState = &initial;
    try applyInstallReasons(
        arena_state.allocator(),
        &packages,
        &states,
        &.{"user-picked"},
    );

    try std.testing.expectEqual(@as(usize, 2), states.len);
    try std.testing.expectEqual(solver_model.InstallReason.user, states[0].reason);
    try std.testing.expectEqual(
        solver_model.InstallReason.automatic,
        states[1].reason,
    );
    // unrelated state must survive the rewrite
    try std.testing.expectEqual(@as(u32, 11), states[0].rpmdb_hnum);
    try std.testing.expectEqual(@as(u32, 12), states[1].rpmdb_hnum);
    try std.testing.expectEqual(@as(u64, 2), states[1].install_order);

    // an empty feed means nothing was user requested
    states = &initial;
    try applyInstallReasons(
        arena_state.allocator(),
        &packages,
        &states,
        &.{},
    );
    for (states) |state| {
        try std.testing.expectEqual(
            solver_model.InstallReason.automatic,
            state.reason,
        );
    }

    var mismatched: []const solver_model.InstalledState = initial[0..1];
    try std.testing.expectError(
        error.InvalidInput,
        applyInstallReasons(
            arena_state.allocator(),
            &packages,
            &mismatched,
            &.{},
        ),
    );
}

test "live producer records the queue pair every job was built from" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    jobs[0].queue_pair = 3;
    const erase_jobs = [_]EraseJobInput{.{
        .selector = .{
            .repository = system_repository_id,
            .name = "leaf",
            .epoch = null,
            .version = "1.0",
            .release = "1",
            .arch = "x86_64",
        },
        .queue_pair = 7,
    }};
    // Locking the package the erase targets would make the request
    // unsatisfiable, so lock an unrelated name.
    const locked_names = [_][]const u8{"unrelated"};
    const locked_pairs = [_]?u32{11};
    input.jobs = jobs[0..];
    input.erase_jobs = &erase_jobs;
    input.locked_names = &locked_names;
    input.locked_queue_pairs = &locked_pairs;

    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    // Install, then the erase rows, then the locks: the origins array mirrors
    // the job list position for position.
    try std.testing.expectEqual(solved.jobs.len, solved.job_origins.len);
    try std.testing.expectEqual(@as(?u32, 3), solved.job_origins[0]);
    try std.testing.expectEqual(@as(?u32, 7), solved.job_origins[1]);
    try std.testing.expectEqual(
        @as(?u32, 11),
        solved.job_origins[solved.job_origins.len - 1],
    );
    try std.testing.expectEqual(
        solver_model.JobAction.lock,
        solved.jobs[solved.jobs.len - 1].action,
    );
}

test "live producer names the package behind every user-installed pair" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    const user_installed_names = [_][]const u8{"leaf"};
    const user_installed_pairs = [_]?u32{5};
    input.jobs = &.{};
    input.user_installed_names = &user_installed_names;
    input.user_installed_queue_pairs = &user_installed_pairs;

    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    // The mark reaches the solve as an install reason either way; the job
    // exists so the published plan can name the package behind pair 5.
    try std.testing.expectEqual(@as(usize, 1), solved.jobs.len);
    try std.testing.expectEqual(
        solver_model.JobAction.user_installed,
        solved.jobs[0].action,
    );
    try std.testing.expectEqual(
        std.meta.Tag(solver_model.Selection).package,
        std.meta.activeTag(solved.jobs[0].selection),
    );
    try std.testing.expectEqual(@as(?u32, 5), solved.job_origins[0]);

    // Without the pairs the marks stay install-reason only, exactly as every
    // caller that predates the published plan saw them.
    input.user_installed_queue_pairs = &.{};
    var bare = try produce(std.testing.allocator, input);
    defer bare.deinit();
    try std.testing.expectEqual(@as(usize, 0), bare.jobs.len);

    // A pair list that does not cover the names is a caller bug.
    const short_pairs = [_]?u32{ 5, 6 };
    input.user_installed_queue_pairs = &short_pairs;
    try std.testing.expectError(
        error.InvalidInput,
        produce(std.testing.allocator, input),
    );
}

test "preparing a request builds the universe and jobs without solving" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    jobs[0].queue_pair = 4;
    input.jobs = jobs[0..];

    var prepared = try prepare(std.testing.allocator, input);
    defer prepared.deinit();

    // The installed row and the candidate are both reachable, which is what
    // a capture of a request that never solved has to describe.
    try std.testing.expect(prepared.universe.packages.len >= 2);
    try std.testing.expectEqual(@as(usize, 1), prepared.jobs.len);
    try std.testing.expectEqual(
        solver_model.JobAction.install,
        prepared.jobs[0].action,
    );
    try std.testing.expectEqual(prepared.jobs.len, prepared.job_origins.len);
    try std.testing.expectEqual(@as(?u32, 4), prepared.job_origins[0]);
    try std.testing.expectEqual(@as(usize, 0), prepared.hidden.len);
    // The architecture is copied into the arena so it outlives the caller's
    // input.
    try std.testing.expectEqualStrings("x86_64", prepared.native_arch);
    try std.testing.expect(prepared.native_arch.ptr != input.native_arch.ptr);
}

test "a prepared universe retains an allocator that survives the move" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.jobs = jobs[0..];

    var prepared = try prepare(std.testing.allocator, input);
    defer prepared.deinit();

    // `solver_model.Universe` retains the allocator it was built with, and
    // `Prepared` is returned by value and moved again by `produce`. The
    // retained `.ptr` therefore has to be the heap arena rather than a slot
    // in `prepare`'s frame, or freeing through it would touch a dead frame
    // -- a ReleaseSafe-only crash that a Debug build cannot see.
    try std.testing.expectEqual(
        @as(*anyopaque, @ptrCast(prepared.arena_state)),
        prepared.universe.allocator.ptr,
    );

    // `Universe.deinit` is public, so freeing through the retained allocator
    // after the move has to stay safe. The arena still owns the memory, so
    // the enclosing `prepared.deinit()` remains correct afterwards.
    prepared.universe.deinit();
}

test "a prepared request matches what the producer would solve" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    const input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );

    var prepared = try prepare(std.testing.allocator, input);
    defer prepared.deinit();
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    try std.testing.expectEqual(solved.jobs.len, prepared.jobs.len);
    for (solved.jobs, prepared.jobs) |solved_job, prepared_job| {
        try std.testing.expectEqual(solved_job.action, prepared_job.action);
        try std.testing.expectEqual(solved_job.reason, prepared_job.reason);
    }
    try std.testing.expectEqual(
        solved.universe.packages.len,
        prepared.universe.packages.len,
    );
}

test "live producer rejects lock origins that do not match the lock names" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    const locked_names = [_][]const u8{ "leaf", "other" };
    const locked_pairs = [_]?u32{11};
    input.jobs = &.{};
    input.locked_names = &locked_names;
    input.locked_queue_pairs = &locked_pairs;

    try std.testing.expectError(
        error.InvalidInput,
        produce(std.testing.allocator, input),
    );
}

test "live producer translates erase jobs with clean deps" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    const erase_jobs = [_]EraseJobInput{.{
        .selector = .{
            .repository = system_repository_id,
            .name = "leaf",
            .epoch = null,
            .version = "1.0",
            .release = "1",
            .arch = "x86_64",
        },
    }};
    input.jobs = &.{};
    input.erase_jobs = &erase_jobs;
    input.clean_deps = true;

    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), actions.len);
    try std.testing.expectEqual(solver_model.ActionKind.erase, actions[0].kind);
    try std.testing.expectEqual(@as(usize, 0), actions[0].priors.len);

    // `history rollback` reaches its target by installing and erasing in one
    // request, so an erase job alongside an install job is a real shape.
    input.jobs = jobs[0..];
    var mixed = try produce(std.testing.allocator, input);
    defer mixed.deinit();
    const mixed_actions = mixed.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 2), mixed_actions.len);
    var saw_install = false;
    var saw_erase = false;
    for (mixed_actions) |action| {
        switch (action.kind) {
            .install => saw_install = true,
            .erase => saw_erase = true,
            else => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expect(saw_install and saw_erase);

    input.jobs = &.{};
    input.installonly_names = &.{"leaf"};
    input.skip_broken = true;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );
}

test "live producer erases every install-only instance" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalledVersion(51, "leaf", "1.0");
    try fixture.addInstalledVersion(52, "leaf", "2.0");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    const erase_jobs = [_]EraseJobInput{ .{
        .selector = .{
            .repository = system_repository_id,
            .name = "leaf",
            .epoch = null,
            .version = "1.0",
            .release = "1",
            .arch = "x86_64",
        },
    }, .{
        .selector = .{
            .repository = system_repository_id,
            .name = "leaf",
            .epoch = null,
            .version = "2.0",
            .release = "1",
            .arch = "x86_64",
        },
    } };
    input.jobs = &.{};
    input.erase_jobs = &erase_jobs;
    input.clean_deps = true;
    input.allow_erasing = true;
    input.installonly_names = &.{"leaf"};

    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 2), actions.len);
    for (actions) |action| {
        try std.testing.expectEqual(solver_model.ActionKind.erase, action.kind);
    }
}

test "live producer erases from an installed-only universe" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    const erase_jobs = [_]EraseJobInput{.{
        .selector = .{
            .repository = system_repository_id,
            .name = "leaf",
            .epoch = null,
            .version = "1.0",
            .release = "1",
            .arch = "x86_64",
        },
    }};
    input.jobs = &.{};
    input.erase_jobs = &erase_jobs;
    // `--disablerepo=*` leaves no available repository at all.
    input.repositories = &.{};

    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), actions.len);
    try std.testing.expectEqual(solver_model.ActionKind.erase, actions[0].kind);

    // Dropping the installed repository too leaves nothing to solve against.
    input.include_installed = false;
    try std.testing.expectError(
        error.InvalidInput,
        produce(std.testing.allocator, input),
    );
}

test "live producer accepts force-best cleanup protection and allow erasing" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.best = true;
    input.clean_deps = true;
    input.protected_names = &.{"missing-protected"};
    {
        var solved = try produce(std.testing.allocator, input);
        defer solved.deinit();

        try std.testing.expectEqual(
            @as(usize, 1),
            solved.solved.result.selected.len,
        );
    }
    input.clean_deps = false;
    input.allow_erasing = true;
    var allowed = try produce(std.testing.allocator, input);
    defer allowed.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        allowed.solved.result.selected.len,
    );
}

test "live allow-erasing changes an installed conflict from unsatisfiable" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(41, "installed-blocker");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );

    try std.testing.expectError(
        error.Unsatisfiable,
        produce(std.testing.allocator, input),
    );
    input.allow_erasing = true;
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();
    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 2), actions.len);
    var saw_install = false;
    var saw_erase = false;
    for (actions) |action| {
        saw_install = saw_install or action.kind == .install;
        saw_erase = saw_erase or action.kind == .erase;
    }
    try std.testing.expect(saw_install);
    try std.testing.expect(saw_erase);
}

test "live producer records broken exact jobs under skip-broken policy" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var base_jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &base_jobs,
    );
    var jobs = [_]JobInput{
        base_jobs[0],
        .{ .selector = .{
            .repository = "repo",
            .name = "broken",
            .epoch = null,
            .version = "1.0",
            .release = "1",
            .arch = "x86_64",
        } },
    };
    input.jobs = &jobs;
    input.skip_broken = true;
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    try std.testing.expectEqual(
        @as(usize, 1),
        solved.solved.result.outcome.skipped_jobs.len,
    );
    try std.testing.expectEqual(
        @as(solver_model.JobId, @enumFromInt(1)),
        solved.solved.result.outcome.skipped_jobs[0],
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        solved.solved.result.selected.len,
    );
}

test "live solve projects the install into the legacy result" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    const input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );

    var solved: [*c]solver_legacy_abi.LegacyResult = null;
    try legacyResultCase(std.testing.allocator, input, &solved);
    defer solver_legacy_result.free(solved);

    const install = solved[0].pPkgsToInstall;
    try std.testing.expect(install != null);
    try std.testing.expect(install[0].pNext == null);
    try std.testing.expectEqualStrings(
        "candidate",
        std.mem.span(install[0].pszName.?),
    );
    try std.testing.expectEqualStrings(
        "1.0",
        std.mem.span(install[0].pszVersion.?),
    );
    try std.testing.expectEqualStrings(
        "1",
        std.mem.span(install[0].pszRelease.?),
    );
    try std.testing.expectEqualStrings(
        "x86_64",
        std.mem.span(install[0].pszArch.?),
    );
}

/// Run the exact sequence `TDNFRepoMdNativeSolverLiveSolve` runs: solve, hand
/// the native result to the legacy projection, and own the outcome.
fn legacyResultCase(
    allocator: std.mem.Allocator,
    input: Input,
    output: *[*c]solver_legacy_abi.LegacyResult,
) !void {
    const native = try solveOwnedC(allocator, input);
    defer solver_result_c.freeOwnedResult(native);
    try solver_legacy_result.build(allocator, native, true, output);
}

test "live producer fails closed on unsupported and ambiguous input" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    const input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    var repository = input.repositories[0];
    repository.snapshot_file = "snapshot";
    repositories[0] = repository;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );

    repository.snapshot_file = null;
    repository.cost = solver_model.default_repository_cost + 1;
    repositories[0] = repository;
    try std.testing.expectError(
        error.UnsupportedRepositoryCost,
        produce(std.testing.allocator, input),
    );

    repository.cost = solver_model.default_repository_cost;
    repository.priority = std.math.minInt(i32);
    repositories[0] = repository;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );

    repository.priority = solver_model.default_repository_priority;
    repositories[0] = repository;
    var job = input.jobs[0];
    job.selector.name = "missing";
    jobs[0] = job;
    try std.testing.expectError(
        error.PackageNotFound,
        produce(std.testing.allocator, input),
    );
}

test "live producer applies an authoritative considered projection" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.hidden_available = input.jobs;
    try std.testing.expectError(
        error.Unsatisfiable,
        produce(std.testing.allocator, input),
    );

    var repository = input.repositories[0];
    repository.snapshot_file = "authoritative-considered";
    repositories[0] = repository;
    input.hidden_available = &.{};
    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        solved.solved.result.selected.len,
    );

    input.hidden_available = &.{ jobs[0], jobs[0] };
    try std.testing.expectError(
        error.InvalidInput,
        produce(std.testing.allocator, input),
    );
}

fn allocationFailureCase(
    allocator: std.mem.Allocator,
    input: Input,
) !void {
    var solved = try produce(allocator, input);
    defer solved.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        solved.solved.result.selected.len,
    );
}

fn prepareAllocationFailureCase(
    allocator: std.mem.Allocator,
    input: Input,
) !void {
    var prepared = try prepare(allocator, input);
    defer prepared.deinit();
    try std.testing.expectEqual(@as(usize, 1), prepared.jobs.len);
}

fn legacyResultAllocationFailureCase(
    allocator: std.mem.Allocator,
    input: Input,
) !void {
    var solved: [*c]solver_legacy_abi.LegacyResult = null;
    try legacyResultCase(allocator, input, &solved);
    defer solver_legacy_result.free(solved);
    try std.testing.expect(solved[0].pPkgsToInstall != null);
}

test "live producer cleans every allocation failure" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.hidden_available = &.{};
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailureCase,
        .{input},
    );
}

test "preparing a request cleans every allocation failure" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.hidden_available = &.{};
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        prepareAllocationFailureCase,
        .{input},
    );
}

test "live legacy projection cleans every allocation failure" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    input.hidden_available = &.{};

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        legacyResultAllocationFailureCase,
        .{input},
    );
}

test "live producer installs a package named on the command line" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var rpm_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    const rpm_path = try fixture.addCmdlineRpm(&rpm_buffer, "cmdline-pkg");
    jobs[0] = .{ .selector = .{
        .repository = cmdline_repository_id,
        .name = "cmdline-pkg",
        .epoch = null,
        .version = "1.0",
        .release = "1",
        .arch = "x86_64",
    } };
    const cmdline_rpm_paths = [_]?[:0]const u8{rpm_path};
    input.cmdline_rpm_paths = &cmdline_rpm_paths;

    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), actions.len);
    try std.testing.expectEqual(
        solver_model.ActionKind.install,
        actions[0].kind,
    );
    try std.testing.expectEqualStrings(
        "cmdline-pkg",
        solved.universe.package(actions[0].package).?.source.nevra.name,
    );
}

test "live producer rejects inconsistent command-line paths" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var rpm_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    const rpm_path = try fixture.addCmdlineRpm(&rpm_buffer, "cmdline-pkg");

    // A path handed to an ordinary repository job is a bridge bug.
    const stray = [_]?[:0]const u8{rpm_path};
    input.cmdline_rpm_paths = &stray;
    try std.testing.expectError(
        error.InvalidInput,
        produce(std.testing.allocator, input),
    );

    // A command-line job with no backing file cannot be rebuilt.
    jobs[0].selector.repository = cmdline_repository_id;
    const missing = [_]?[:0]const u8{null};
    input.cmdline_rpm_paths = &missing;
    try std.testing.expectError(
        error.UnsupportedInput,
        produce(std.testing.allocator, input),
    );

    // The array must be parallel to the job list.
    input.cmdline_rpm_paths = &.{};
    try std.testing.expectError(
        error.PackageNotFound,
        produce(std.testing.allocator, input),
    );
}

test "live producer installs from a repository backed by a directory" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var rpm_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var dir_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    const input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    _ = try fixture.addCmdlineRpm(&rpm_buffer, "dir-pkg");

    // --repofromdir: no metadata cache, just the .rpm files in the directory.
    repositories[0] = .{
        .id = "fromdir",
        .cache_dir = "",
        .rpm_directory = fixture.path(&dir_buffer, ""),
    };
    jobs[0] = .{ .selector = .{
        .repository = "fromdir",
        .name = "dir-pkg",
        .epoch = null,
        .version = "1.0",
        .release = "1",
        .arch = "x86_64",
    } };

    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    const actions = solved.solved.result.outcome.actions;
    try std.testing.expectEqual(@as(usize, 1), actions.len);
    try std.testing.expectEqual(
        solver_model.ActionKind.install,
        actions[0].kind,
    );
    try std.testing.expectEqualStrings(
        "dir-pkg",
        solved.universe.package(actions[0].package).?.source.nevra.name,
    );
}

test "live producer rejects an empty repository directory path" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    const input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    repositories[0].rpm_directory = "";
    try std.testing.expectError(
        error.InvalidInput,
        produce(std.testing.allocator, input),
    );
}

test "live producer answers an empty request with an empty transaction" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    try fixture.addInstalled(51, "leaf");
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var cache_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var repositories: [1]RepositoryInput = undefined;
    var jobs: [1]JobInput = undefined;
    var input = fixtureInput(
        &fixture,
        &root_buffer,
        &cache_buffer,
        &repositories,
        &jobs,
    );
    // `history undo` and `history rollback` reach a target whose delta is
    // already satisfied and hand the solver nothing to do.
    input.jobs = &.{};

    var solved = try produce(std.testing.allocator, input);
    defer solved.deinit();

    try std.testing.expectEqual(
        @as(usize, 0),
        solved.solved.result.outcome.actions.len,
    );
    // Nothing is touched, so the installed package is simply kept.
    try std.testing.expectEqual(
        @as(usize, 1),
        solved.solved.result.selected.len,
    );
    try std.testing.expectEqualStrings(
        "leaf",
        solved.universe.package(
            solved.solved.result.selected[0],
        ).?.source.nevra.name,
    );
}
