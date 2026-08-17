const std = @import("std");
const builtin = @import("builtin");
const abi = @import("tdnf_internal_abi");
const model = @import("model.zig");
const repomd = @import("repomd.zig");

pub const primary_xml = @import("primary.zig");
pub const filelists_xml = @import("filelists.zig");
pub const other_xml = @import("other.zig");
pub const updateinfo_xml = @import("updateinfo.zig");
pub const available_repository_loader = @import("available_loader.zig");
pub const cmdline_requires = @import("cmdline_requires.zig");
pub const installed_repository_loader = @import("installed_repository.zig");
pub const metadata_cache = @import("cache.zig");
pub const metadata_model = model;
pub const package_context = @import("package_context.zig");
pub const package_query = @import("pkgquery.zig");
pub const query_index = @import("index.zig");
pub const repo_cache = @import("repo_cache.zig");
pub const rpm_package = @import("rpmpkg.zig");
pub const query_native = @import("query_native.zig");
pub const transaction_native = @import("transaction_native.zig");
pub const solver_model = @import("solver_model.zig");
pub const solver_identity = @import("solver_identity.zig");
pub const solver_live = @import("solver_live.zig");
pub const solver_live_abi = @import("solver_live_abi.zig");
pub const solver_native = @import("solver_native.zig");
pub const solver_visibility = @import("solver_visibility.zig");
pub const solver_coordinator = @import("solver_coordinator.zig");
pub const solver_policy = @import("solver_policy.zig");
pub const solver_result = @import("solver_result.zig");
pub const solver_result_c = @import("solver_result_c.zig");
pub const solver_legacy_result = @import("solver_legacy_result.zig");
pub const solver_rules = @import("solver_rules.zig");
pub const solver_search = @import("solver_search.zig");
pub const solver_diag = @import("solver_diag.zig");
pub const directory_repository = @import("directory_repository.zig");

const c_header = if (builtin.is_test) abi else struct {};

pub const TDNF_REPOMD_DOC = opaque {};
pub const TDNF_REPOMD_CHECKSUM = model.Checksum;
pub const TDNF_REPOMD_RECORD = model.Record;

const DocState = struct {
    arena_state: std.heap.ArenaAllocator,
    pszRevision: ?[*:0]const u8 = null,
    pRecords: []model.Record = &[_]model.Record{},
};

const max_repomd_bytes = 16 * 1024 * 1024;
const ProtectedNamesError = error{ OutOfMemory, InvalidInput };

threadlocal var last_error_buf: [512]u8 = undefined;
threadlocal var last_error_len: usize = 0;

fn clearError() void {
    last_error_len = 0;
}

fn setError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&last_error_buf, fmt, args) catch blk: {
        const fallback = "(repomd error truncated)";
        @memcpy(last_error_buf[0..fallback.len], fallback);
        break :blk last_error_buf[0..fallback.len];
    };
    last_error_len = msg.len;
}

pub export fn TDNFRepoMdLastError() [*:0]const u8 {
    if (last_error_len >= last_error_buf.len) {
        last_error_len = last_error_buf.len - 1;
    }
    last_error_buf[last_error_len] = 0;
    return @ptrCast(&last_error_buf);
}

pub export fn TDNFRepoMdNativeSolverResultFree(
    result: ?*abi.TDNF_REPOMD_NATIVE_SOLVER_RESULT,
) void {
    solver_result_c.freeOwnedResult(@ptrCast(result));
}

/// Produce the authoritative native transaction for a live request from cached
/// repository metadata and the rpmdb. The caller owns `*ppSolved` and releases
/// it with `TDNFFreeSolvedPackageInfo`.
pub export fn TDNFRepoMdNativeSolverLiveSolve(
    raw_repositories: ?[*]const abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16,
    repository_count: u32,
    raw_jobs: ?[*]const abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
    job_count: u32,
    raw_erase_jobs: ?[*]const abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
    erase_job_count: u32,
    raw_hidden_available: ?[*]const abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
    hidden_available_count: u32,
    all_deps: c_int,
    best: c_int,
    clean_deps: c_int,
    skip_broken: c_int,
    allow_erasing: c_int,
    update_all: c_int,
    dist_sync_all: c_int,
    raw_locked_names: ?[*:null]const ?[*:0]const u8,
    raw_locked_queue_pairs: ?[*]const u32,
    global_queue_pair: u32,
    has_global_queue_pair: c_int,
    raw_installonly_names: ?[*:null]const ?[*:0]const u8,
    installonly_limit: u32,
    raw_protected_names: ?[*:null]const ?[*:0]const u8,
    raw_user_installed_names: ?[*:null]const ?[*:0]const u8,
    raw_user_installed_queue_pairs: ?[*]const u32,
    raw_cmdline_rpm_paths: ?[*]const ?[*:0]const u8,
    reinstall: c_int,
    rpm_config: ?*const abi.rpmz_rpm_config,
    raw_native_arch: ?[*:0]const u8,
    prepare_only: c_int,
    refute_unsat: c_int,
    solved: ?*abi.PTDNF_SOLVED_PKG_INFO,
    handle: ?*?*anyopaque,
) u32 {
    if (handle) |slot| slot.* = null;
    if (prepare_only != 0 and refute_unsat != 0) {
        clearError();
        setError("native live solve cannot prepare and refute at once", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    if ((prepare_only != 0 or refute_unsat != 0) and handle == null) {
        clearError();
        setError("native live terminal capture discards its only output", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (prepare_only == 0 and refute_unsat == 0 and solved == null) {
        clearError();
        setError("null native live solve output", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    return nativeSolverLiveSolve(
        repository_count,
        raw_jobs,
        job_count,
        raw_erase_jobs,
        erase_job_count,
        raw_hidden_available,
        hidden_available_count,
        all_deps != 0,
        best != 0,
        clean_deps != 0,
        skip_broken != 0,
        allow_erasing != 0,
        raw_protected_names,
        rpm_config,
        raw_native_arch,
        update_all != 0,
        dist_sync_all != 0,
        raw_locked_names,
        raw_locked_queue_pairs,
        if (has_global_queue_pair != 0) global_queue_pair else null,
        raw_installonly_names,
        installonly_limit,
        raw_user_installed_names,
        raw_user_installed_queue_pairs,
        raw_cmdline_rpm_paths,
        raw_repositories,
        reinstall != 0,
        prepare_only != 0,
        refute_unsat != 0,
        solved,
        handle,
    );
}

/// What a retained `TDNFRepoMdNativeSolverLiveSolve` handle points at. A
/// terminal request still has a universe, a job list, and sometimes native
/// refutation problems, which is all the capture layer needs to describe it.
pub const RetainedSolve = union(enum) {
    solved: solver_live.OwnedSolve,
    prepared: solver_live.Prepared,
    refuted: RefutedSolve,

    pub fn deinit(self: *RetainedSolve) void {
        switch (self.*) {
            inline else => |*value| value.deinit(),
        }
        self.* = undefined;
    }
};

/// Where the reporting filter looks for an available package, which is what
/// `check_for_providers` in `solv/rpmzpackage.c` did with the sack.
pub const AvailableLookup = enum {
    /// Query the retained universe. The goal path solved the same set the
    /// sack held, so the two answers agree.
    universe,
    /// Answer "nothing is available". `check-local` solved a directory-only
    /// pool while the sack it queried held only the rpmdb -- `TDNFOpenHandle`
    /// reads the installed packages but no repository metadata, and
    /// `check-local` never refreshes -- so the availability query could never
    /// match anything.
    none,
};

pub const RefutedSolve = struct {
    prepared: solver_live.Prepared,
    refutation: solver_native.OwnedProjectedRefutation,
    job_origins: []const ?u32,
    outcome: solver_model.Outcome,
    /// How the report filter answers `check_for_providers`' "is this name
    /// still available?" question. libsolv asked the *sack*, not the pool it
    /// solved, so a caller whose sack held no available packages must say so.
    available_lookup: AvailableLookup = .universe,
    /// The failure diagnostics rendered from `refutation.ordered`, cached on
    /// first access. Rendering is deferred so it only runs (and only allocates)
    /// when the report path actually asks for the strings.
    rendered: ?solver_diag.OwnedRenderedProblems = null,

    pub fn init(
        prepared: solver_live.Prepared,
        refutation: solver_native.OwnedProjectedRefutation,
        job_origins: []const ?u32,
    ) RefutedSolve {
        return .{
            .prepared = prepared,
            .refutation = refutation,
            .job_origins = job_origins,
            .outcome = .{
                .actions = &.{},
                .problems = refutation.problems.problems,
                .skipped_jobs = &.{},
            },
        };
    }

    pub fn deinit(self: *RefutedSolve) void {
        if (self.rendered) |*rendered| rendered.deinit();
        self.refutation.deinit();
        self.prepared.deinit();
        self.* = undefined;
    }
};

fn refutedJobOrigins(
    prepared: *solver_live.Prepared,
    effective_jobs: []const solver_model.Job,
) error{ OutOfMemory, InvalidInput }![]const ?u32 {
    if (effective_jobs.len == prepared.job_origins.len) {
        return prepared.job_origins;
    }
    if (effective_jobs.len < prepared.job_origins.len) {
        return error.InvalidInput;
    }
    const arena = prepared.arena_state.allocator();
    const origins = try arena.alloc(?u32, effective_jobs.len);
    @memset(origins, null);
    @memcpy(origins[0..prepared.job_origins.len], prepared.job_origins);
    return origins;
}

/// Release a solve retained by `TDNFRepoMdNativeSolverLiveSolve`.
pub export fn TDNFRepoMdNativeSolverLiveSolveRelease(
    handle: ?*anyopaque,
) void {
    const raw = handle orelse return;
    const retained: *RetainedSolve = @ptrCast(@alignCast(raw));
    retained.deinit();
    std.heap.c_allocator.destroy(retained);
}

fn handleToRefuted(handle: ?*anyopaque) ?*RefutedSolve {
    const raw = handle orelse return null;
    const retained: *RetainedSolve = @ptrCast(@alignCast(raw));
    return switch (retained.*) {
        .refuted => |*value| value,
        else => null,
    };
}

/// Render the refute's problems on first access and cache them on the handle.
/// libsolv reports its problem list in the reverse of discovery order, which
/// `solver_diag.renderProblems` reproduces from `refutation.ordered`.
fn refutedEnsureRendered(refuted: *RefutedSolve) solver_diag.RenderError!*const solver_diag.OwnedRenderedProblems {
    if (refuted.rendered == null) {
        refuted.rendered = try solver_diag.renderProblems(
            std.heap.c_allocator,
            refuted.refutation.ordered.problems,
            refuted.prepared.universe,
            refuted.prepared.hidden,
        );
    }
    return &refuted.rendered.?;
}

fn refutedRenderError(err: solver_diag.RenderError) u32 {
    switch (err) {
        error.OutOfMemory => {
            setError("out of memory rendering solver diagnostics", .{});
            return abi.ERROR_TDNF_OUT_OF_MEMORY;
        },
        error.InvalidInput, error.UnsupportedProblem => {
            // No silent fallback: a problem the native renderer cannot turn
            // into libsolv's text is a hard failure, not a reason to defer to
            // libsolv.
            setError("unable to render native solver diagnostics", .{});
            return abi.ERROR_TDNF_SOLV_FAILED;
        },
    }
}

/// Number of native solver-diagnostic problems retained by a refute solve.
///
/// The handle must have been produced by `TDNFRepoMdNativeSolverLiveSolve` with
/// `nRefuteUnsat` set. Problems are ordered exactly as they must be reported.
pub export fn TDNFRepoMdNativeSolverRefutedProblemCount(
    handle: ?*anyopaque,
    out_count: ?*u32,
) u32 {
    clearError();
    const count_out = out_count orelse {
        setError("null refuted problem count output", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    count_out.* = 0;
    const refuted = handleToRefuted(handle) orelse {
        setError("handle does not retain refuted diagnostics", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    const rendered = refutedEnsureRendered(refuted) catch |err| return refutedRenderError(err);
    count_out.* = std.math.cast(u32, rendered.items.len) orelse {
        setError("refuted problem count overflow", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    return 0;
}

// TDNF_SKIPPROBLEM_TYPE bits retained by the private client ABI.
const skipproblem_conflicts: u32 = 0x01;
const skipproblem_obsoletes: u32 = 0x02;
const skipproblem_disabled: u32 = 0x04;
const skipproblem_broken: u32 = 0x08;

/// Reproduce solv/rpmzpackage.c's SkipBasedOnType over a rendered problem's
/// skip class. --skipconflicts drops conflicts, --skipobsoletes drops
/// obsoletes, --skip-broken drops every package rule (every rendered class),
/// and --skipdisabled drops a not-installable problem whose solvable libsolv
/// had disabled.
fn refutedProblemSkippedByType(skip_class: solver_diag.SkipClass, skip_mask: u32) bool {
    if (skip_mask == 0) return false;
    if ((skip_mask & skipproblem_conflicts) != 0 and skip_class == .conflict) return true;
    if ((skip_mask & skipproblem_obsoletes) != 0 and skip_class == .obsoletes) return true;
    if ((skip_mask & skipproblem_broken) != 0) {
        switch (skip_class) {
            .conflict,
            .same_name,
            .obsoletes,
            .requires,
            .nothing_provides,
            .not_installable,
            .not_installable_disabled,
            => return true,
            .other => {},
        }
    }
    if ((skip_mask & skipproblem_disabled) != 0 and skip_class == .not_installable_disabled) return true;
    return false;
}

/// Reproduce libsolv's `SolvFindAvailablePkgByName` availability check: does the
/// retained refute universe hold an available (that is, not-installed) package
/// with the given name? The query runs against `prepared.universe`, the full
/// package set the refute was built from — the same repositories and rpmdb the
/// libsolv sack held.
fn refutedAvailableByName(universe: *const solver_model.Universe, name: []const u8) bool {
    for (universe.packages) |pkg| {
        if (pkg.installed != null) continue;
        if (std.mem.eql(u8, pkg.source.nevra.name, name)) return true;
    }
    return false;
}

/// Parse the required package name out of a rendered "requires" message exactly
/// as check_for_providers did: the text between " requires " and the next ',',
/// with every space removed (so "foo < 0:9" becomes "foo<0:9", matching no
/// package name). Returns null only when the markers are absent, which never
/// happens for a native requires-with-providers message.
fn refutedRequiredName(message: []const u8, buf: []u8) ?[]const u8 {
    const marker = " requires ";
    const start = std.mem.indexOf(u8, message, marker) orelse return null;
    const rest = message[start + marker.len ..];
    const comma = std.mem.indexOfScalar(u8, rest, ',') orelse return null;
    var n: usize = 0;
    for (rest[0..comma]) |ch| {
        if (ch == ' ') continue;
        if (n >= buf.len) break;
        buf[n] = ch;
        n += 1;
    }
    return buf[0..n];
}

/// Reproduce SolvReportProblems' stateful per-problem reporting decision for the
/// problem at `target`. SkipBasedOnType filters first; then, for a
/// SOLVER_RULE_PKG_REQUIRES survivor under a non-empty mask, check_for_providers
/// suppresses it when the required name deduplicates against the previous
/// reported-requires name or still has an available candidate. The dedupe state
/// is rebuilt by replaying problems 0..=target, so the decision matches
/// libsolv's single stateful pass without the C caller holding any state.
fn refutedProblemReported(
    items: []const solver_diag.RenderedProblem,
    universe: *const solver_model.Universe,
    skip_mask: u32,
    target: u32,
    available_lookup: AvailableLookup,
) bool {
    // prev name starts empty, matching check_for_providers' {0} buffer.
    var prev_buf: [256]u8 = undefined;
    var prev_len: usize = 0;
    var i: usize = 0;
    while (i <= target) : (i += 1) {
        const item = items[i];
        if (refutedProblemSkippedByType(item.skip_class, skip_mask)) {
            if (i == target) return false;
            continue;
        }
        if (skip_mask != 0 and item.skip_class == .requires) {
            var name_buf: [256]u8 = undefined;
            const name = refutedRequiredName(item.message, &name_buf) orelse {
                // Unreachable for a native requires message; libsolv's parse
                // failure branch printed the problem, so report it.
                if (i == target) return true;
                continue;
            };
            if (std.mem.eql(u8, name, prev_buf[0..prev_len])) {
                if (i == target) return false;
                continue;
            }
            @memcpy(prev_buf[0..name.len], name);
            prev_len = name.len;
            const available = switch (available_lookup) {
                .universe => refutedAvailableByName(universe, name),
                .none => false,
            };
            const reported = !available;
            if (i == target) return reported;
            continue;
        }
        if (i == target) return true;
    }
    return true;
}

/// Fetch one rendered native solver-diagnostic problem and decide whether it is
/// reported under the active skip mask.
///
/// This folds SolvReportProblems' per-problem filtering into the native path:
/// SkipBasedOnType (via the problem's skip class) and, for a
/// SOLVER_RULE_PKG_REQUIRES survivor under a non-empty mask, check_for_providers
/// (dedupe plus availability lookup). The C caller loops indices and prints the
/// survivors, keeping the raw libsolv rule taxonomy out of client code.
///
/// The returned message points into the handle and is valid until the handle is
/// released. out_reported is set to 1 when the problem must be printed.
pub export fn TDNFRepoMdNativeSolverRefutedProblem(
    handle: ?*anyopaque,
    index_arg: u32,
    skip_mask: u32,
    out_reported: ?*u32,
    out_message: ?*?[*:0]const u8,
) u32 {
    clearError();
    const message_out = out_message orelse {
        setError("null refuted problem message output", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    message_out.* = null;
    const reported_out = out_reported orelse {
        setError("null refuted problem reported output", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    reported_out.* = 0;
    const refuted = handleToRefuted(handle) orelse {
        setError("handle does not retain refuted diagnostics", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    const rendered = refutedEnsureRendered(refuted) catch |err| return refutedRenderError(err);
    const items = rendered.items;
    if (index_arg >= items.len) {
        setError("refuted problem index out of range", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    message_out.* = items[index_arg].message.ptr;
    reported_out.* = if (refutedProblemReported(
        items,
        refuted.prepared.universe,
        skip_mask,
        index_arg,
        refuted.available_lookup,
    )) 1 else 0;
    return 0;
}

/// Storage behind the entry path `TDNFRepoMdNativeSolverCheckLocal` hands back
/// when a directory entry could not be classified. It stays valid until the
/// next call on the same thread, which is long enough for the caller to print
/// the diagnostic libsolv printed at that point.
threadlocal var check_local_error_path: [std.Io.Dir.max_path_bytes + 1]u8 = undefined;

/// Translate a `prepareDirectoryCheck` failure into the error code the
/// libsolv-backed walk produced for the same input. A directory that cannot be
/// opened surfaced as `ERROR_TDNF_SYSTEM_BASE + errno`, which is what
/// `check-local` on a missing path or on a plain file reported.
fn checkLocalPrepareError(
    err: solver_live.ProduceError,
    path_out: ?*?[*:0]const u8,
) u32 {
    switch (err) {
        error.DirectoryOpenFailed => {
            const errno_value = directory_repository.last_open_errno;
            if (directory_repository.lastStatPath()) |path| {
                if (path.len < check_local_error_path.len) {
                    @memcpy(check_local_error_path[0..path.len], path);
                    check_local_error_path[path.len] = 0;
                    if (path_out) |out| {
                        out.* = @ptrCast(&check_local_error_path);
                    }
                }
            }
            setError(
                "unable to read the check-local directory: {s}",
                .{@tagName(@as(std.posix.E, @enumFromInt(errno_value)))},
            );
            return @intCast(abi.ERROR_TDNF_SYSTEM_BASE + errno_value);
        },
        error.OutOfMemory => {
            setError("out of memory reading the check-local directory", .{});
            return abi.ERROR_TDNF_OUT_OF_MEMORY;
        },
        error.RpmFileOpenFailed => {
            setError("unreadable rpm file in the check-local directory", .{});
            return abi.ERROR_TDNF_INVALID_REPO_FILE;
        },
        error.InvalidRpmHeader => {
            setError("invalid rpm header in the check-local directory", .{});
            return abi.ERROR_TDNF_RPM_HEADER_CONVERT_FAILED;
        },
        else => {
            setError("native check-local universe unavailable: {t}", .{err});
            return abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
        },
    }
}

/// Run `rpmz tdnf check-local <dir>` natively: build a universe holding only the
/// `.rpm` files under `raw_directory`, request every one of them, and either
/// report a clean check or retain the solver's diagnostics.
///
/// `out_count` receives the number of packages found, which the caller prints
/// before any diagnostic. `out_error_path` receives, on failure, the directory
/// entry that could not be classified, so the caller can name it the way
/// libsolv's walk did; it stays null for every other failure. `out_handle` receives null when the request was
/// satisfiable; otherwise it retains the problems, is read with
/// `TDNFRepoMdNativeSolverRefutedProblem*`, and is released with
/// `TDNFRepoMdNativeSolverLiveSolveRelease`.
pub export fn TDNFRepoMdNativeSolverCheckLocal(
    raw_directory: ?[*:0]const u8,
    raw_native_arch: ?[*:0]const u8,
    out_count: ?*u32,
    out_handle: ?*?*anyopaque,
    out_error_path: ?*?[*:0]const u8,
) u32 {
    clearError();
    if (out_error_path) |out| out.* = null;
    const count_out = out_count orelse {
        setError("null check-local package count output", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    count_out.* = 0;
    const handle_out = out_handle orelse {
        setError("null check-local diagnostics output", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    handle_out.* = null;
    const directory = spanRequired(raw_directory) orelse {
        setError("null check-local directory", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    const native_arch = spanRequired(raw_native_arch) orelse {
        setError("null check-local architecture", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };

    const allocator = std.heap.c_allocator;
    var prepared = solver_live.prepareDirectoryCheck(allocator, .{
        .directory = directory,
        .native_arch = native_arch,
    }) catch |err| return checkLocalPrepareError(err, out_error_path);

    count_out.* = std.math.cast(u32, prepared.universe.packages.len) orelse {
        prepared.deinit();
        setError("check-local package count overflow", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };

    // libsolv set SOLVER_FLAG_ALLOW_UNINSTALL on this solve; every other flag
    // it set either matches the native default (KEEP_ORPHANS) or only takes
    // effect for jobs check-local never queues (BEST_OBEY_POLICY without a
    // forcebest job) or for a concept the native solver does not model
    // (ALLOW_VENDORCHANGE).
    const policy: solver_model.SolvePolicy = .{
        .architecture = .{
            .native_arch = prepared.native_arch,
            // SolvCreatePool never called pool_setarch for this pool, so
            // libsolv considered every architecture installable here.
            .allow_any_arch = true,
        },
        .allow_erasing = true,
    };

    // solveProjected's identity index rejects two packages with the same
    // NEVRA and checksum, which a check-local directory may legitimately hold
    // (the same rpm staged under two file names). Nothing is hidden here, so
    // the projected entry point would delegate to solve() anyway.
    if (solver_native.solve(
        allocator,
        prepared.universe,
        .{ .jobs = prepared.jobs },
        policy,
    )) |solve| {
        var solved = solve;
        solved.deinit();
        prepared.deinit();
        return 0;
    } else |err| if (err != error.Unsatisfiable) {
        prepared.deinit();
        setError("native check-local solve unavailable: {t}", .{err});
        return if (err == error.OutOfMemory)
            abi.ERROR_TDNF_OUT_OF_MEMORY
        else
            abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
    }

    // The request is unsatisfiable, which is the only case that produces
    // output: retain the diagnostics for the caller to filter and print.
    var refutation = solver_native.refuteProjectedWithEffectiveJobs(
        allocator,
        prepared.universe,
        &prepared.visibility,
        .{ .jobs = prepared.jobs },
        policy,
    ) catch |err| {
        prepared.deinit();
        setError("native check-local diagnostics unavailable: {t}", .{err});
        return if (err == error.OutOfMemory)
            abi.ERROR_TDNF_OUT_OF_MEMORY
        else
            abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
    };
    const job_origins = refutedJobOrigins(
        &prepared,
        refutation.jobs,
    ) catch |err| {
        refutation.deinit();
        prepared.deinit();
        setError("native check-local job origins unavailable: {t}", .{err});
        return if (err == error.OutOfMemory)
            abi.ERROR_TDNF_OUT_OF_MEMORY
        else
            abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
    };
    const owned = allocator.create(RetainedSolve) catch {
        refutation.deinit();
        prepared.deinit();
        setError("out of memory retaining check-local diagnostics", .{});
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    };
    var refuted = RefutedSolve.init(prepared, refutation, job_origins);
    // The sack check-local filtered against held no available packages.
    refuted.available_lookup = .none;
    owned.* = .{ .refuted = refuted };
    handle_out.* = @ptrCast(owned);
    return 0;
}

fn nativeSolverLiveSolve(
    repository_count: u32,
    raw_jobs: ?[*]const abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
    job_count: u32,
    raw_erase_jobs: ?[*]const abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
    erase_job_count: u32,
    raw_hidden_available: ?[*]const abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
    hidden_available_count: u32,
    all_deps: bool,
    best: bool,
    clean_deps: bool,
    skip_broken: bool,
    allow_erasing: bool,
    raw_protected_names: ?[*:null]const ?[*:0]const u8,
    rpm_config: ?*const abi.rpmz_rpm_config,
    raw_native_arch: ?[*:0]const u8,
    update_all: bool,
    dist_sync_all: bool,
    raw_locked_names: ?[*:null]const ?[*:0]const u8,
    raw_locked_queue_pairs: ?[*]const u32,
    global_queue_pair: ?u32,
    raw_installonly_names: ?[*:null]const ?[*:0]const u8,
    installonly_limit: u32,
    raw_user_installed_names: ?[*:null]const ?[*:0]const u8,
    raw_user_installed_queue_pairs: ?[*]const u32,
    raw_cmdline_rpm_paths: ?[*]const ?[*:0]const u8,
    raw_repositories: ?[*]const abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16,
    reinstall: bool,
    prepare_only: bool,
    refute_unsat: bool,
    solved: ?*abi.PTDNF_SOLVED_PKG_INFO,
    handle: ?*?*anyopaque,
) u32 {
    clearError();
    if (solved) |output| output.* = null;
    if (repository_count != 0 and raw_repositories == null) {
        setError("null native live repositories", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (job_count != 0 and raw_jobs == null) {
        setError("null native live jobs", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (erase_job_count != 0 and raw_erase_jobs == null) {
        setError("null native live erase jobs", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    const config = rpm_config orelse {
        setError("null native live rpm configuration", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    const native_arch = if (raw_native_arch) |value|
        std.mem.span(value)
    else {
        setError("null native live architecture", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (native_arch.len == 0) {
        setError("empty native live architecture", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    const allocator = std.heap.c_allocator;
    const protected_names = namesFromC(
        allocator,
        raw_protected_names,
    ) catch |err| {
        return switch (err) {
            error.OutOfMemory => blk: {
                setError(
                    "out of memory translating protected package names",
                    .{},
                );
                break :blk abi.ERROR_TDNF_OUT_OF_MEMORY;
            },
            error.InvalidInput => blk: {
                setError("invalid protected package name", .{});
                break :blk abi.ERROR_TDNF_INVALID_PARAMETER;
            },
        };
    };
    defer allocator.free(protected_names);
    const locked_names = namesFromC(
        allocator,
        raw_locked_names,
    ) catch |err| {
        return switch (err) {
            error.OutOfMemory => blk: {
                setError("out of memory translating locked package names", .{});
                break :blk abi.ERROR_TDNF_OUT_OF_MEMORY;
            },
            error.InvalidInput => blk: {
                setError("invalid locked package name", .{});
                break :blk abi.ERROR_TDNF_INVALID_PARAMETER;
            },
        };
    };
    defer allocator.free(locked_names);
    const installonly_names = namesFromC(
        allocator,
        raw_installonly_names,
    ) catch |err| {
        return switch (err) {
            error.OutOfMemory => blk: {
                setError(
                    "out of memory translating install-only package names",
                    .{},
                );
                break :blk abi.ERROR_TDNF_OUT_OF_MEMORY;
            },
            error.InvalidInput => blk: {
                setError("invalid install-only package name", .{});
                break :blk abi.ERROR_TDNF_INVALID_PARAMETER;
            },
        };
    };
    defer allocator.free(installonly_names);
    const user_installed_names = if (raw_user_installed_names) |names|
        namesFromC(allocator, names) catch |err| {
            return switch (err) {
                error.OutOfMemory => blk: {
                    setError(
                        "out of memory translating user-installed package names",
                        .{},
                    );
                    break :blk abi.ERROR_TDNF_OUT_OF_MEMORY;
                },
                error.InvalidInput => blk: {
                    setError("invalid user-installed package name", .{});
                    break :blk abi.ERROR_TDNF_INVALID_PARAMETER;
                },
            };
        }
    else
        null;
    defer if (user_installed_names) |names| allocator.free(names);
    const repositories = allocator.alloc(
        solver_live.RepositoryInput,
        repository_count,
    ) catch {
        setError("out of memory translating native live repositories", .{});
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    };
    defer allocator.free(repositories);
    if (raw_repositories) |repositories_ptr| {
        for (repositories_ptr[0..repository_count], repositories) |
            raw,
            *repository,
        | {
            const rpm_directory = spanOptional(raw.pszDirectory);
            repository.* = .{
                .id = spanRequired(raw.pszId) orelse {
                    setError("invalid native live repository id", .{});
                    return abi.ERROR_TDNF_INVALID_PARAMETER;
                },
                // A directory-backed repository has no metadata cache, so
                // pszCacheDir is expected to be absent for exactly those.
                .cache_dir = if (rpm_directory != null)
                    ""
                else
                    spanRequired(raw.pszCacheDir) orelse {
                        setError("invalid native live repository cache", .{});
                        return abi.ERROR_TDNF_INVALID_PARAMETER;
                    },
                .cache_dir_fd = if (raw.nCacheDirFd >= 0)
                    raw.nCacheDirFd
                else
                    null,
                .rpm_directory = rpm_directory,
                .snapshot_file = spanOptional(raw.pszSnapshotFile),
                .priority = raw.nPriority,
                .cost = raw.dwCost,
            };
        }
    }
    const jobs = allocator.alloc(
        solver_live.JobInput,
        job_count,
    ) catch {
        setError("out of memory translating native live jobs", .{});
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    };
    defer allocator.free(jobs);
    if (raw_jobs) |jobs_ptr| {
        for (jobs_ptr[0..job_count], jobs) |raw, *job| {
            job.* = liveJobFromC(raw) orelse {
                setError("invalid native live job selector", .{});
                return abi.ERROR_TDNF_INVALID_PARAMETER;
            };
        }
    }
    var cmdline_rpm_paths: []const ?[:0]const u8 = &.{};
    if (raw_cmdline_rpm_paths) |paths_ptr| {
        const paths = allocator.alloc(?[:0]const u8, job_count) catch {
            setError(
                "out of memory translating native live command-line paths",
                .{},
            );
            return abi.ERROR_TDNF_OUT_OF_MEMORY;
        };
        for (paths_ptr[0..job_count], paths) |raw, *path| {
            path.* = if (raw) |value| std.mem.span(value) else null;
        }
        cmdline_rpm_paths = paths;
    }
    defer if (cmdline_rpm_paths.len != 0) allocator.free(cmdline_rpm_paths);

    const erase_jobs = allocator.alloc(
        solver_live.EraseJobInput,
        erase_job_count,
    ) catch {
        setError("out of memory translating native live erase jobs", .{});
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    };
    defer allocator.free(erase_jobs);
    if (raw_erase_jobs) |erase_jobs_ptr| {
        for (erase_jobs_ptr[0..erase_job_count], erase_jobs) |raw, *job| {
            job.* = liveEraseJobFromC(raw) orelse {
                setError("invalid native live erase job selector", .{});
                return abi.ERROR_TDNF_INVALID_PARAMETER;
            };
        }
    }
    if (hidden_available_count != 0 and raw_hidden_available == null) {
        setError("null native live hidden available packages", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }
    const hidden_available = allocator.alloc(
        solver_live.JobInput,
        hidden_available_count,
    ) catch {
        setError("out of memory translating native live visibility", .{});
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    };
    defer allocator.free(hidden_available);
    if (raw_hidden_available) |hidden_ptr| {
        for (hidden_ptr[0..hidden_available_count], hidden_available) |
            raw,
            *item,
        | {
            item.* = liveJobFromC(raw) orelse {
                setError("invalid native live hidden package selector", .{});
                return abi.ERROR_TDNF_INVALID_PARAMETER;
            };
        }
    }

    const locked_queue_pairs = if (raw_locked_queue_pairs) |pairs| blk: {
        const values = allocator.alloc(?u32, locked_names.len) catch {
            setError("out of memory translating lock queue pairs", .{});
            return abi.ERROR_TDNF_OUT_OF_MEMORY;
        };
        for (pairs[0..locked_names.len], values) |pair, *value| {
            value.* = pair;
        }
        break :blk values;
    } else &.{};
    defer if (locked_queue_pairs.len != 0) allocator.free(locked_queue_pairs);

    const user_installed_queue_pairs = if (raw_user_installed_queue_pairs) |pairs| blk: {
        const names = user_installed_names orelse {
            setError(
                "user-installed queue pairs without user-installed names",
                .{},
            );
            return abi.ERROR_TDNF_INVALID_PARAMETER;
        };
        const values = allocator.alloc(?u32, names.len) catch {
            setError(
                "out of memory translating user-installed queue pairs",
                .{},
            );
            return abi.ERROR_TDNF_OUT_OF_MEMORY;
        };
        for (pairs[0..names.len], values) |pair, *value| {
            value.* = pair;
        }
        break :blk values;
    } else &.{};
    defer if (user_installed_queue_pairs.len != 0)
        allocator.free(user_installed_queue_pairs);

    const solver_input: solver_live.Input = .{
        .repositories = repositories,
        .rpmdb = .{ .config = config },
        .native_arch = native_arch,
        .jobs = jobs,
        .cmdline_rpm_paths = cmdline_rpm_paths,
        .erase_jobs = erase_jobs,
        .hidden_available = hidden_available,
        .include_installed = !all_deps,
        .update_all = update_all,
        .dist_sync_all = dist_sync_all,
        .locked_names = locked_names,
        .locked_queue_pairs = locked_queue_pairs,
        .global_queue_pair = global_queue_pair,
        .installonly_names = installonly_names,
        .installonly_limit = installonly_limit,
        .user_installed_names = user_installed_names,
        .user_installed_queue_pairs = user_installed_queue_pairs,
        .best = best,
        .allow_erasing = allow_erasing,
        .clean_deps = clean_deps,
        .skip_broken = skip_broken,
        .protected_names = protected_names,
    };

    if (prepare_only) {
        // The request is being described, not run: build the universe and
        // translate the jobs, and stop there.
        var prepared = solver_live.prepare(allocator, solver_input) catch |err| {
            setError("native live prepare unavailable: {t}", .{err});
            return if (err == error.OutOfMemory)
                abi.ERROR_TDNF_OUT_OF_MEMORY
            else
                abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
        };
        const owned = allocator.create(RetainedSolve) catch {
            prepared.deinit();
            setError("out of memory retaining the native live universe", .{});
            return abi.ERROR_TDNF_OUT_OF_MEMORY;
        };
        owned.* = .{ .prepared = prepared };
        handle.?.* = @ptrCast(owned);
        return 0;
    }

    if (refute_unsat) {
        var prepared = solver_live.prepare(allocator, solver_input) catch |err| {
            setError("native live refute prepare unavailable: {t}", .{err});
            return if (err == error.OutOfMemory)
                abi.ERROR_TDNF_OUT_OF_MEMORY
            else
                abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
        };
        var refutation = solver_native.refuteProjectedWithEffectiveJobs(
            allocator,
            prepared.universe,
            &prepared.visibility,
            .{ .jobs = prepared.jobs },
            .{
                .architecture = .{ .native_arch = prepared.native_arch },
                .best = solver_input.best,
                .allow_erasing = solver_input.allow_erasing or
                    solver_input.erase_jobs.len != 0,
                .clean_deps = solver_input.clean_deps,
                .skip_broken = solver_input.skip_broken,
                .protected_names = solver_input.protected_names,
                .installonly_limit = solver_input.installonly_limit,
                .installonly_names = solver_input.installonly_names,
            },
        ) catch |err| {
            prepared.deinit();
            setError("native live refute unavailable: {t}", .{err});
            return if (err == error.OutOfMemory)
                abi.ERROR_TDNF_OUT_OF_MEMORY
            else
                abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
        };
        const job_origins = refutedJobOrigins(
            &prepared,
            refutation.jobs,
        ) catch |err| {
            refutation.deinit();
            prepared.deinit();
            setError("native live refute job origins unavailable: {t}", .{err});
            return if (err == error.OutOfMemory)
                abi.ERROR_TDNF_OUT_OF_MEMORY
            else
                abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
        };
        const owned = allocator.create(RetainedSolve) catch {
            refutation.deinit();
            prepared.deinit();
            setError("out of memory retaining the native live refutation", .{});
            return abi.ERROR_TDNF_OUT_OF_MEMORY;
        };
        owned.* = .{
            .refuted = RefutedSolve.init(prepared, refutation, job_origins),
        };
        handle.?.* = @ptrCast(owned);
        return 0;
    }

    const output = solved orelse {
        setError("null native live solve output", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    var solve = solver_live.produce(allocator, solver_input) catch |err| switch (err) {
        // Outcomes rpmz models with error codes of its own rather than solver
        // failures. `clearError` at the top of this function has already left
        // the diagnostic empty, which is what tells `TDNFGoalSolveNative` not
        // to print a `native-solver:` line for them: the caller renders each
        // one itself, in the wording the corresponding libsolv check used.
        error.Unsatisfiable => return abi.ERROR_TDNF_SOLV_FAILED,
        error.ProtectedPackage => return abi.ERROR_TDNF_PROTECTED,
        error.InstallonlyLimit => return abi.ERROR_TDNF_INSTALLONLY_LIMIT_EXCEEDED,
        else => {
            setError("native live solve unavailable: {t}", .{err});
            return if (err == error.OutOfMemory)
                abi.ERROR_TDNF_OUT_OF_MEMORY
            else
                abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
        },
    };
    // A caller asking for the handle snapshots the solve after this returns,
    // so it outlives the call and moves to the heap.
    var retained: ?*RetainedSolve = null;
    if (handle != null) {
        const owned = allocator.create(RetainedSolve) catch {
            solve.deinit();
            setError("out of memory retaining the native live solve", .{});
            return abi.ERROR_TDNF_OUT_OF_MEMORY;
        };
        owned.* = .{ .solved = solve };
        retained = owned;
    }
    // `solve` is moved into `retained` bit for bit, so exactly one of the two
    // copies may be torn down. This flag records that the retained copy owns
    // the models now; the stack copy keeps stale arena pointers and must not
    // be deinit'd once the retained one has been released.
    const solve_owned_elsewhere = retained != null;
    defer if (!solve_owned_elsewhere) solve.deinit();
    const active = if (retained) |owned| &owned.solved else &solve;

    const native = active.buildOwnedC() catch |err| {
        if (retained) |owned| {
            owned.deinit();
            allocator.destroy(owned);
            retained = null;
        }
        setError("native live solve unavailable: {t}", .{err});
        return if (err == error.OutOfMemory)
            abi.ERROR_TDNF_OUT_OF_MEMORY
        else
            abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
    };
    defer solver_result_c.freeOwnedResult(native);
    solver_legacy_result.build(
        allocator,
        @ptrCast(native),
        reinstall,
        @ptrCast(output),
    ) catch |err| {
        if (retained) |owned| {
            owned.deinit();
            allocator.destroy(owned);
            retained = null;
        }
        setError("native live solve result unavailable: {t}", .{err});
        return if (err == error.OutOfMemory)
            abi.ERROR_TDNF_OUT_OF_MEMORY
        else
            abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
    };
    if (handle) |slot| slot.* = @ptrCast(retained);
    return 0;
}

fn namesFromC(
    allocator: std.mem.Allocator,
    raw_names_pointer: ?[*:null]const ?[*:0]const u8,
) ProtectedNamesError![][]const u8 {
    const raw_names = if (raw_names_pointer) |names|
        std.mem.span(names)
    else
        &.{};
    const translated_names = try allocator.alloc(
        []const u8,
        raw_names.len,
    );
    errdefer allocator.free(translated_names);
    for (raw_names, translated_names) |raw, *name| {
        name.* = spanRequired(raw) orelse return error.InvalidInput;
    }
    return translated_names;
}

fn liveJobFromC(
    raw: abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
) ?solver_live.JobInput {
    const checksum = if (raw.pszChecksumType == null and
        raw.pszChecksumValue == null)
        null
    else if (spanRequired(raw.pszChecksumType)) |kind|
        if (spanRequired(raw.pszChecksumValue)) |value|
            solver_identity.Checksum{
                .kind = kind,
                .value = value,
                .is_pkgid = raw.nChecksumIsPkgId != 0,
            }
        else
            return null
    else
        return null;
    const repository = spanRequired(raw.pszRepository) orelse return null;
    const command_line = std.mem.eql(
        u8,
        repository,
        solver_live.cmdline_repository_id,
    );
    if (command_line !=
        (raw.nRpmFd >= 0 and raw.dwSourcePackageHandle != 0))
    {
        return null;
    }
    return .{
        .selector = .{
            .repository = repository,
            .name = spanRequired(raw.pszName) orelse return null,
            .epoch = raw.dwEpoch,
            .version = spanRequired(raw.pszVersion) orelse return null,
            .release = spanRequired(raw.pszRelease) orelse return null,
            .arch = spanRequired(raw.pszArch) orelse return null,
            .checksum = checksum,
        },
        .queue_pair = if (raw.nHasQueuePair != 0) raw.dwQueuePair else null,
        .cmdline_rpm_fd = if (command_line) raw.nRpmFd else null,
        .source_package_handle = raw.dwSourcePackageHandle,
    };
}

fn liveEraseJobFromC(
    raw: abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB,
) ?solver_live.EraseJobInput {
    const job = liveJobFromC(raw) orelse return null;
    if (job.selector.checksum != null or
        !std.mem.eql(
            u8,
            job.selector.repository,
            solver_live.system_repository_id,
        ))
    {
        return null;
    }
    return .{ .selector = job.selector, .queue_pair = job.queue_pair };
}

fn spanRequired(value: ?[*:0]const u8) ?[]const u8 {
    const raw = value orelse return null;
    const span = std.mem.span(raw);
    return if (span.len == 0) null else span;
}

fn spanOptional(value: ?[*:0]const u8) ?[]const u8 {
    const raw = value orelse return null;
    return std.mem.span(raw);
}

pub export fn TDNFRepoMdParseBuffer(
    buf: ?[*]const u8,
    len: usize,
    out_doc: ?*?*TDNF_REPOMD_DOC,
) u32 {
    clearError();

    const doc_out = out_doc orelse {
        setError("null output document", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    doc_out.* = null;

    const data_ptr = buf orelse {
        setError("null repomd buffer", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (len == 0) {
        setError("empty repomd buffer", .{});
        return abi.ERROR_TDNF_INVALID_REPO_FILE;
    }

    return parseIntoDoc(data_ptr[0..len], doc_out);
}

pub export fn TDNFRepoMdParseFile(
    path: ?[*:0]const u8,
    out_doc: ?*?*TDNF_REPOMD_DOC,
) u32 {
    clearError();

    const doc_out = out_doc orelse {
        setError("null output document", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    doc_out.* = null;

    const path_ptr = path orelse {
        setError("null repomd path", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    };
    const path_slice = std.mem.span(path_ptr);
    if (path_slice.len == 0) {
        setError("empty repomd path", .{});
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    }

    var io_state: std.Io.Threaded = .init(std.heap.c_allocator, .{});
    defer io_state.deinit();
    const io = io_state.io();

    const data = std.Io.Dir.cwd().readFileAlloc(
        io,
        path_slice,
        std.heap.c_allocator,
        .limited(max_repomd_bytes),
    ) catch |err| {
        setError("failed to read {s}: {t}", .{ path_slice, err });
        return mapFileError(err);
    };
    defer std.heap.c_allocator.free(data);

    return parseIntoDoc(data, doc_out);
}

pub export fn TDNFRepoMdFree(raw_doc: ?*TDNF_REPOMD_DOC) void {
    const doc = raw_doc orelse return;
    freeDoc(fromOpaque(doc));
}

pub export fn TDNFRepoMdGetRevision(raw_doc: ?*const TDNF_REPOMD_DOC) ?[*:0]const u8 {
    const doc = raw_doc orelse return null;
    return fromOpaqueConst(doc).pszRevision;
}

pub export fn TDNFRepoMdGetRecordCount(raw_doc: ?*const TDNF_REPOMD_DOC) u32 {
    const doc = raw_doc orelse return 0;
    return @intCast(fromOpaqueConst(doc).pRecords.len);
}

pub export fn TDNFRepoMdGetRecord(
    raw_doc: ?*const TDNF_REPOMD_DOC,
    index: u32,
) ?*const model.Record {
    const doc = raw_doc orelse return null;
    const state = fromOpaqueConst(doc);
    const record_index: usize = @intCast(index);
    if (record_index >= state.pRecords.len) {
        return null;
    }
    return &state.pRecords[record_index];
}

fn parseIntoDoc(data: []const u8, out_doc: *?*TDNF_REPOMD_DOC) u32 {
    const state = std.heap.c_allocator.create(DocState) catch {
        setError("out of memory", .{});
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    };
    state.* = .{
        .arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator),
    };

    const parsed = repomd.parse(state.arena_state.allocator(), data) catch |err| {
        freeDoc(state);
        return switch (err) {
            error.InvalidRepoMd => blk: {
                setError("invalid repomd.xml", .{});
                break :blk abi.ERROR_TDNF_INVALID_REPO_FILE;
            },
            error.OutOfMemory => blk: {
                setError("out of memory", .{});
                break :blk abi.ERROR_TDNF_OUT_OF_MEMORY;
            },
        };
    };

    state.pszRevision = parsed.pszRevision;
    state.pRecords = parsed.pRecords;
    out_doc.* = toOpaque(state);
    return 0;
}

fn mapFileError(err: anyerror) u32 {
    return switch (err) {
        error.FileNotFound => abi.ERROR_TDNF_FILE_NOT_FOUND,
        error.AccessDenied => abi.ERROR_TDNF_ACCESS_DENIED,
        error.NameTooLong => abi.ERROR_TDNF_NAME_TOO_LONG,
        error.BadPathName => abi.ERROR_TDNF_INVALID_PARAMETER,
        error.NotDir => abi.ERROR_TDNF_INVALID_DIR,
        error.IsDir => abi.ERROR_TDNF_INVALID_DIR,
        error.OutOfMemory => abi.ERROR_TDNF_OUT_OF_MEMORY,
        error.FileTooBig => abi.ERROR_TDNF_OVERFLOW,
        error.StreamTooLong => abi.ERROR_TDNF_OVERFLOW,
        else => abi.ERROR_TDNF_FILESYS_IO,
    };
}

fn freeDoc(state: *DocState) void {
    state.arena_state.deinit();
    std.heap.c_allocator.destroy(state);
}

fn toOpaque(state: *DocState) *TDNF_REPOMD_DOC {
    return @ptrCast(state);
}

fn fromOpaque(doc: *TDNF_REPOMD_DOC) *DocState {
    return @ptrCast(@alignCast(doc));
}

fn fromOpaqueConst(doc: *const TDNF_REPOMD_DOC) *const DocState {
    return @ptrCast(@alignCast(doc));
}

fn expectOptionalString(expected: ?[]const u8, actual: ?[*:0]const u8) !void {
    const testing = std.testing;

    if (expected) |text| {
        const actual_text = actual orelse return error.TestExpectedEqual;
        try testing.expectEqualStrings(text, std.mem.span(actual_text));
    } else {
        try testing.expect(actual == null);
    }
}

comptime {
    _ = @import("available_loader.zig");
    _ = @import("cache.zig");
    _ = @import("cmdline_requires.zig");
    _ = @import("filelists.zig");
    _ = @import("index.zig");
    _ = @import("other.zig");
    _ = @import("pkgquery.zig");
    _ = @import("rpmpkg.zig");
    _ = @import("solver_coordinator.zig");
    _ = @import("solver_policy.zig");
    _ = @import("solver_result.zig");
    _ = @import("solver_result_c.zig");
    _ = @import("solver_legacy_result.zig");
    _ = @import("solver_rules.zig");
    _ = @import("solver_search.zig");
    _ = @import("transaction_native.zig");
    _ = @import("updateinfo.zig");
    if (!builtin.is_test) {
        _ = @import("query_native.zig");
    }
}

test "repomd header ABI matches Zig structs" {
    const testing = std.testing;

    try testing.expectEqual(@sizeOf(c_header.TDNF_REPOMD_CHECKSUM), @sizeOf(TDNF_REPOMD_CHECKSUM));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_CHECKSUM, "pszType"), @offsetOf(TDNF_REPOMD_CHECKSUM, "pszType"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_CHECKSUM, "pszValue"), @offsetOf(TDNF_REPOMD_CHECKSUM, "pszValue"));

    try testing.expectEqual(@sizeOf(c_header.TDNF_REPOMD_RECORD), @sizeOf(TDNF_REPOMD_RECORD));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "pszType"), @offsetOf(TDNF_REPOMD_RECORD, "pszType"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "dwKind"), @offsetOf(TDNF_REPOMD_RECORD, "dwKind"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "pszLocationHref"), @offsetOf(TDNF_REPOMD_RECORD, "pszLocationHref"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "checksum"), @offsetOf(TDNF_REPOMD_RECORD, "checksum"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "openChecksum"), @offsetOf(TDNF_REPOMD_RECORD, "openChecksum"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "nTimestamp"), @offsetOf(TDNF_REPOMD_RECORD, "nTimestamp"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "nSize"), @offsetOf(TDNF_REPOMD_RECORD, "nSize"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "nOpenSize"), @offsetOf(TDNF_REPOMD_RECORD, "nOpenSize"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "nDatabaseVersion"), @offsetOf(TDNF_REPOMD_RECORD, "nDatabaseVersion"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "nHasTimestamp"), @offsetOf(TDNF_REPOMD_RECORD, "nHasTimestamp"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "nHasSize"), @offsetOf(TDNF_REPOMD_RECORD, "nHasSize"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "nHasOpenSize"), @offsetOf(TDNF_REPOMD_RECORD, "nHasOpenSize"));
    try testing.expectEqual(@offsetOf(c_header.TDNF_REPOMD_RECORD, "nHasDatabaseVersion"), @offsetOf(TDNF_REPOMD_RECORD, "nHasDatabaseVersion"));
}

test "native live solve wrapper rejects a null output" {
    const result = TDNFRepoMdNativeSolverLiveSolve(
        null,
        0,
        null,
        0,
        null,
        0,
        null,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        null,
        null,
        0,
        0,
        null,
        0,
        null,
        null,
        null,
        null,
        0,
        null,
        null,
        0,
        0,
        null,
        null,
    );

    try std.testing.expectEqual(
        @as(u32, abi.ERROR_TDNF_INVALID_PARAMETER),
        result,
    );
}

test "native live prepare rejects a request with nowhere to put the handle" {
    const result = TDNFRepoMdNativeSolverLiveSolve(
        null,
        0,
        null,
        0,
        null,
        0,
        null,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        null,
        null,
        0,
        0,
        null,
        0,
        null,
        null,
        null,
        null,
        0,
        null,
        null,
        1,
        0,
        null,
        null,
    );

    try std.testing.expectEqual(
        @as(u32, abi.ERROR_TDNF_INVALID_PARAMETER),
        result,
    );
}

test "translates exact installed erase selectors" {
    var raw = std.mem.zeroes(abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB);
    raw.pszRepository = "@System";
    raw.pszName = "installed";
    raw.pszVersion = "1";
    raw.pszRelease = "2";
    raw.pszArch = "x86_64";
    const job = liveEraseJobFromC(raw).?;

    try std.testing.expectEqualStrings("installed", job.selector.name);
    try std.testing.expectEqual(@as(?u32, 0), job.selector.epoch);
    raw.pszRepository = "available";
    try std.testing.expect(liveEraseJobFromC(raw) == null);
}

test "carries the job queue pair across the C translation" {
    var raw = std.mem.zeroes(abi.TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB);
    raw.pszRepository = "@System";
    raw.pszName = "installed";
    raw.pszVersion = "1";
    raw.pszRelease = "2";
    raw.pszArch = "x86_64";

    // Without the flag the pair is absent, which is what the hidden-available
    // feed sends: those entries never entered the job queue.
    raw.dwQueuePair = 7;
    try std.testing.expectEqual(
        @as(?u32, null),
        liveJobFromC(raw).?.queue_pair,
    );
    try std.testing.expectEqual(
        @as(?u32, null),
        liveEraseJobFromC(raw).?.queue_pair,
    );

    raw.nHasQueuePair = 1;
    try std.testing.expectEqual(@as(?u32, 7), liveJobFromC(raw).?.queue_pair);
    try std.testing.expectEqual(
        @as(?u32, 7),
        liveEraseJobFromC(raw).?.queue_pair,
    );
}

test "translates null-terminated protected package names" {
    var raw = [_:null]?[*:0]const u8{ "first", "second" };
    const names = try namesFromC(std.testing.allocator, &raw);
    defer std.testing.allocator.free(names);

    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("first", names[0]);
    try std.testing.expectEqualStrings("second", names[1]);

    var invalid = [_:null]?[*:0]const u8{""};
    try std.testing.expectError(
        error.InvalidInput,
        namesFromC(std.testing.allocator, &invalid),
    );
}

test "parses repomd records with revision checksums sizes and database versions" {
    const testing = std.testing;
    const xml =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo" xmlns:rpm="http://linux.duke.edu/metadata/rpm">
        \\  <revision>1729778159</revision>
        \\  <data type="primary">
        \\    <checksum type="sha256">62f84034</checksum>
        \\    <open-checksum type="sha256">fe3abdf7</open-checksum>
        \\    <location href="repodata/primary.xml.zst"/>
        \\    <timestamp>1729778159</timestamp>
        \\    <size>1234</size>
        \\    <open-size>5678</open-size>
        \\  </data>
        \\  <data type="updateinfo-1">
        \\    <checksum type="sha256">9270d81b</checksum>
        \\    <open-checksum type="sha256">1e01a83e</open-checksum>
        \\    <location href="repodata/updateinfo-1.xml.zst"/>
        \\    <timestamp>1729778160</timestamp>
        \\    <size>476</size>
        \\    <open-size>1053</open-size>
        \\  </data>
        \\  <data type="primary_db">
        \\    <checksum type="sha256">dbdb</checksum>
        \\    <location href="repodata/primary.sqlite.xz"/>
        \\    <timestamp>1729778161</timestamp>
        \\    <size>222</size>
        \\    <open-size>333</open-size>
        \\    <database_version>10</database_version>
        \\  </data>
        \\</repomd>
    ;

    var doc: ?*TDNF_REPOMD_DOC = null;
    try testing.expectEqual(@as(u32, 0), TDNFRepoMdParseBuffer(xml.ptr, xml.len, &doc));
    defer TDNFRepoMdFree(doc);

    const parsed = doc orelse return error.TestExpectedEqual;
    try expectOptionalString("1729778159", TDNFRepoMdGetRevision(parsed));
    try testing.expectEqual(@as(u32, 3), TDNFRepoMdGetRecordCount(parsed));

    const primary = TDNFRepoMdGetRecord(parsed, 0) orelse return error.TestExpectedEqual;
    try expectOptionalString("primary", primary.pszType);
    try testing.expectEqual(@as(u32, abi.TDNF_REPOMD_RECORD_KIND_PRIMARY), primary.dwKind);
    try expectOptionalString("repodata/primary.xml.zst", primary.pszLocationHref);
    try expectOptionalString("sha256", primary.checksum.pszType);
    try expectOptionalString("62f84034", primary.checksum.pszValue);
    try expectOptionalString("sha256", primary.openChecksum.pszType);
    try expectOptionalString("fe3abdf7", primary.openChecksum.pszValue);
    try testing.expectEqual(@as(c_int, 1), primary.nHasTimestamp);
    try testing.expectEqual(@as(u64, 1729778159), primary.nTimestamp);
    try testing.expectEqual(@as(c_int, 1), primary.nHasSize);
    try testing.expectEqual(@as(u64, 1234), primary.nSize);
    try testing.expectEqual(@as(c_int, 1), primary.nHasOpenSize);
    try testing.expectEqual(@as(u64, 5678), primary.nOpenSize);
    try testing.expectEqual(@as(c_int, 0), primary.nHasDatabaseVersion);

    const updateinfo = TDNFRepoMdGetRecord(parsed, 1) orelse return error.TestExpectedEqual;
    try expectOptionalString("updateinfo-1", updateinfo.pszType);
    try testing.expectEqual(@as(u32, abi.TDNF_REPOMD_RECORD_KIND_UPDATEINFO), updateinfo.dwKind);
    try expectOptionalString("repodata/updateinfo-1.xml.zst", updateinfo.pszLocationHref);

    const primary_db = TDNFRepoMdGetRecord(parsed, 2) orelse return error.TestExpectedEqual;
    try expectOptionalString("primary_db", primary_db.pszType);
    try testing.expectEqual(@as(u32, abi.TDNF_REPOMD_RECORD_KIND_UNKNOWN), primary_db.dwKind);
    try testing.expectEqual(@as(c_int, 1), primary_db.nHasDatabaseVersion);
    try testing.expectEqual(@as(u64, 10), primary_db.nDatabaseVersion);
}

test "rejects missing required repomd fields" {
    const testing = std.testing;

    const cases = [_]struct {
        name: []const u8,
        xml: []const u8,
    }{
        .{
            .name = "data missing type",
            .xml =
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo"><data><location href="repodata/primary.xml.gz"/></data></repomd>
            ,
        },
        .{
            .name = "data missing location",
            .xml =
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo"><data type="primary"><checksum type="sha256">abcd</checksum></data></repomd>
            ,
        },
    };

    for (cases) |case| {
        var doc: ?*TDNF_REPOMD_DOC = null;
        const rc = TDNFRepoMdParseBuffer(case.xml.ptr, case.xml.len, &doc);
        try testing.expectEqual(@as(u32, abi.ERROR_TDNF_INVALID_REPO_FILE), rc);
        try testing.expect(doc == null);
    }
}

test "rejects malformed repomd xml" {
    const testing = std.testing;

    const cases = [_][]const u8{
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo"><data type="primary"><location href="repodata/p.xml.gz"></repomd>
        ,
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo"><data type="primary"><location href="repodata/p.xml.gz"/></dato></repomd>
        ,
    };

    for (cases) |xml| {
        var doc: ?*TDNF_REPOMD_DOC = null;
        const rc = TDNFRepoMdParseBuffer(xml.ptr, xml.len, &doc);
        try testing.expectEqual(@as(u32, abi.ERROR_TDNF_INVALID_REPO_FILE), rc);
        try testing.expect(doc == null);
    }
}

test "normalizes raw updateinfo variants to advisory kind" {
    const testing = std.testing;
    const xml =
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
        \\  <data type="updateinfo">
        \\    <location href="repodata/updateinfo.xml.gz"/>
        \\  </data>
        \\  <data type="updateinfo-2">
        \\    <location href="repodata/updateinfo-2.xml.zst"/>
        \\  </data>
        \\</repomd>
    ;

    var doc: ?*TDNF_REPOMD_DOC = null;
    try testing.expectEqual(@as(u32, 0), TDNFRepoMdParseBuffer(xml.ptr, xml.len, &doc));
    defer TDNFRepoMdFree(doc);

    const parsed = doc orelse return error.TestExpectedEqual;
    try testing.expectEqual(@as(u32, 2), TDNFRepoMdGetRecordCount(parsed));

    const first = TDNFRepoMdGetRecord(parsed, 0) orelse return error.TestExpectedEqual;
    const second = TDNFRepoMdGetRecord(parsed, 1) orelse return error.TestExpectedEqual;
    try expectOptionalString("updateinfo", first.pszType);
    try expectOptionalString("updateinfo-2", second.pszType);
    try testing.expectEqual(@as(u32, abi.TDNF_REPOMD_RECORD_KIND_UPDATEINFO), first.dwKind);
    try testing.expectEqual(@as(u32, abi.TDNF_REPOMD_RECORD_KIND_UPDATEINFO), second.dwKind);
}
