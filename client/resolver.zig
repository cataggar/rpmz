//! The supported Zig resolver: explicit inputs in, one canonical plan out.
//!
//! `resolvePlan` is the only supported way to obtain a
//! `transaction_plan.Plan` without going through the private handle API. It
//! runs the same `resolve_service` pipeline `tdnf plan` uses, so the canonical
//! bytes and digest produced here are the bytes and digest the CLI prints.
//!
//! Every fact the resolve depends on is declared by the caller. The resolver
//! never reads a host `.repo` file, a host `tdnf.conf`, a host cache
//! directory, or a host repository-enablement decision: it materializes a
//! private, single-use configuration from `ResolveInput` alone and points the
//! resolve at that. Values it cannot discover -- architecture, distro, release
//! version, policy -- are required inputs rather than defaults.
//!
//! Nothing here executes a transaction. The resolve reads the declared rpmdb
//! and writes only into the declared scratch and metadata-cache directories.
//! When the process runs as root it takes tdnf's process-wide instance lock for
//! the duration of the call, exactly as the CLI does.
//!
//! Ownership contract:
//!
//! * Every string and slice reachable from `ResolveInput` is borrowed for the
//!   duration of the call and may be released the moment it returns.
//! * On success the caller owns the returned `*transaction_plan.Plan` and must
//!   call `Plan.destroy`. The plan is a deep copy allocated from `allocator`;
//!   it shares no storage with the resolver's scratch state.
//! * A solver contradiction is a successful call. It returns a plan whose
//!   `environment.resolution_status` is `.problems`, with structured
//!   `problems` and no actions.
//! * Invalid input, repository or rpmdb I/O failure, integrity failure, and
//!   allocation failure return a `ResolveError` and no plan.

const std = @import("std");
const abi = @import("client_abi");
const errors = @import("tdnf_error");
const integration = @import("transaction_plan_integration");
const resolve_service = @import("resolve_service.zig");

pub const transaction_plan = @import("transaction_plan");

const Allocator = std.mem.Allocator;
const CmdArgs = abi.CmdArgs;
const RepoData = abi.RepoData;
const Tdnf = abi.Tdnf;

extern fn TDNFOpenHandle(args: ?*CmdArgs, handle: *?*Tdnf) callconv(.c) u32;
extern fn TDNFCloseHandle(handle: ?*Tdnf) callconv(.c) void;
extern fn TDNFFreeSolvedPackageInfo(solved: ?*anyopaque) callconv(.c) void;
extern fn TDNFAllocateString(
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFFreeMemory(memory: ?*anyopaque) callconv(.c) void;
extern fn create_cnfnode(name: ?[*:0]const u8) callconv(.c) ?*anyopaque;
extern fn destroy_cnftree(node: ?*anyopaque) callconv(.c) void;

/// The transaction the caller wants planned.
///
/// `obsoleted` is deliberately absent: obsoletion is an authoritative outcome
/// the solver reports as an action, never something a caller requests.
pub const Operation = enum {
    install,
    erase,
    upgrade,
    upgrade_all,
    downgrade,
    downgrade_all,
    distro_sync,
    reinstall,
    autoerase,
    autoerase_all,

    fn service(self: Operation) resolve_service.Operation {
        return switch (self) {
            .install => .install,
            .erase => .erase,
            .upgrade => .upgrade,
            .upgrade_all => .upgrade_all,
            .downgrade => .downgrade,
            .downgrade_all => .downgrade_all,
            .distro_sync => .distro_sync,
            .reinstall => .reinstall,
            .autoerase => .autoerase,
            .autoerase_all => .autoerase_all,
        };
    }

    /// The `tdnf` verb this operation resolves as. The verb occupies slot 0 of
    /// the resolver's command vector exactly as it does on the command line,
    /// so the request identity recorded in the plan matches the CLI's.
    fn verb(self: Operation) [:0]const u8 {
        return switch (self) {
            .install => "install",
            .erase => "erase",
            .upgrade, .upgrade_all => "upgrade",
            .downgrade, .downgrade_all => "downgrade",
            .distro_sync => "distro-sync",
            .reinstall => "reinstall",
            .autoerase, .autoerase_all => "autoremove",
        };
    }

    /// True when the operation is meaningless without subjects.
    pub fn requiresSubjects(self: Operation) bool {
        return switch (self) {
            .install, .erase, .reinstall => true,
            else => false,
        };
    }

    /// True when the operation acts on the whole installed set. Passing
    /// subjects to one of these would silently change its meaning, so they are
    /// rejected instead.
    pub fn isSingleton(self: Operation) bool {
        return switch (self) {
            .upgrade_all, .downgrade_all, .autoerase_all => true,
            else => false,
        };
    }
};

/// Secret material a repository needs but that must never reach the plan.
///
/// The resolver asks the provider for a value, installs it directly on the
/// private in-memory repository record, and forgets it. Secrets are never
/// written to the scratch configuration, never appear in a filename, and are
/// not part of any captured repository fact, so they cannot enter the plan,
/// its digest, or diagnostics.
pub const SecretField = enum { username, password };

pub const SecretProvider = struct {
    context: ?*anyopaque = null,
    /// Returns borrowed secret material for `repository_id`/`field`, or null
    /// when the repository does not use that credential.
    lookup: *const fn (
        context: ?*anyopaque,
        repository_id: []const u8,
        field: SecretField,
    ) ?[]const u8,
};

/// Where a repository's metadata comes from.
pub const MetadataSource = union(enum) {
    /// An absolute path to a caller-selected directory that already holds a
    /// `repodata/` tree. Nothing is downloaded for this repository.
    local_snapshot: []const u8,
    /// Caller-supplied remote configuration. Metadata is fetched into the
    /// caller-selected cache directory.
    remote: Remote,
};

pub const Remote = struct {
    /// Base URLs, in caller order. Credentials embedded in a URL are rejected.
    base_urls: []const []const u8 = &.{},
    metalink: ?[]const u8 = null,
    secrets: ?SecretProvider = null,
    ssl_verify: bool = true,
};

/// The only repository cost the canonical plan currently records.
pub const default_repository_cost: u32 = 1000;

pub const Repository = struct {
    /// Stable identity. It is the repository's name in the plan, so it must be
    /// non-empty and unique within one call.
    id: []const u8,
    priority: i32 = 50,
    /// Only `default_repository_cost` is representable today; any other value
    /// is rejected rather than silently normalized.
    cost: u32 = default_repository_cost,
    metadata: MetadataSource,
    gpg_check: bool = false,
    /// Absolute paths or `file://` URLs of the keys that sign this repository.
    gpg_keys: []const []const u8 = &.{},
    skip_if_unavailable: bool = false,
};

/// The installed set the resolve plans against.
pub const InstalledState = union(enum) {
    /// An absolute install root. Its rpm configuration selects the rpmdb, and
    /// the resolver captures that rpmdb's backend, cookie, package-set digest,
    /// header numbers, and exact installed identities.
    install_root: []const u8,
};

pub const Environment = struct {
    /// Target architecture, e.g. `x86_64`. Never taken from the host kernel.
    architecture: []const u8,
    /// Distro identity recorded in the plan, e.g. `photon`.
    distro: []const u8,
    /// Release version used for `$releasever` and recorded in the plan.
    release_version: []const u8,
};

pub const MinVersion = struct {
    name: []const u8,
    evr: []const u8,
};

/// Caller-declared solver policy. Mirrors `transaction_plan.Policy` minus the
/// values the resolver derives authoritatively (`allow_multilib`,
/// `include_installed`, `install_weak_dependencies`, `keep_orphans`, and
/// `force_architecture`).
pub const Policy = struct {
    allow_erasing: bool = false,
    all_deps: bool = false,
    best: bool = false,
    clean_requirements_on_remove: bool = false,
    excludes: []const []const u8 = &.{},
    installonly_limit: u32 = 3,
    installonly_names: []const []const u8 = &.{},
    locked_names: []const []const u8 = &.{},
    min_versions: []const MinVersion = &.{},
    protected_names: []const []const u8 = &.{},
    skip_broken: bool = false,
};

pub const ResolveInput = struct {
    operation: Operation,
    /// Package or capability subjects, in caller order. Required for
    /// `install`, `erase`, and `reinstall`; rejected for the `*_all`
    /// operations.
    subjects: []const []const u8 = &.{},
    /// The complete set of repositories the resolve may see.
    repositories: []const Repository = &.{},
    installed: InstalledState,
    environment: Environment,
    policy: Policy = .{},
    /// Metadata cache location, interpreted inside the install root exactly as
    /// `cachedir` is. Must be absolute.
    cache_dir: []const u8 = "/var/cache/tdnf",
    /// An absolute directory the resolver may create a private, single-use
    /// subdirectory in. The subdirectory holds the generated configuration and
    /// is removed before `resolvePlan` returns.
    scratch_dir: []const u8,
};

pub const ResolveError = error{
    /// A `*_all` operation was given subjects, or a subject-taking operation
    /// was given none.
    InvalidSubjects,
    /// A repository id, metadata source, or cost is unusable.
    InvalidRepository,
    /// Two repositories declared the same id.
    DuplicateRepositoryId,
    /// A repository URL embedded credentials. Use `SecretProvider` instead.
    CredentialsInUrl,
    /// The install root, cache directory, or scratch directory is not an
    /// absolute path.
    InvalidPath,
    /// Architecture, distro, or release version is empty.
    InvalidEnvironment,
    /// The scratch configuration could not be created or removed.
    ScratchStorageFailed,
    /// A declared repository could not be read.
    RepositoryUnavailable,
    /// Repository metadata or the rpmdb changed underneath the capture, so no
    /// mixed-state plan was published.
    IntegrityMismatch,
    /// The declared install root's rpmdb could not be opened or captured.
    RpmdbUnavailable,
    /// The resolve failed for a reason the plan cannot represent.
    ResolveFailed,
    OutOfMemory,
};

fn mapError(code: u32) ResolveError {
    return switch (code) {
        errors.ERROR_TDNF_OUT_OF_MEMORY => error.OutOfMemory,
        errors.ERROR_TDNF_REPO_PERFORM,
        errors.ERROR_TDNF_REPO_NOT_FOUND,
        errors.ERROR_TDNF_REPO_DIR_OPEN,
        errors.ERROR_TDNF_INVALID_REPO_FILE,
        => error.RepositoryUnavailable,
        errors.ERROR_TDNF_DUPLICATE_REPO_ID => error.DuplicateRepositoryId,
        errors.ERROR_TDNF_PACKAGE_REQUIRED => error.InvalidSubjects,
        else => error.ResolveFailed,
    };
}

/// Resolves `input` into an owned canonical transaction plan.
///
/// See the module documentation for the full ownership and error contract.
/// `io` is used only for the private scratch directory; the resolve itself
/// performs no I/O through it.
pub fn resolvePlan(
    allocator: Allocator,
    io: std.Io,
    input: ResolveInput,
) ResolveError!*transaction_plan.Plan {
    try validate(input);

    var scratch = try Scratch.create(allocator, io, input);
    defer scratch.destroy();
    try scratch.materialize(input);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const install_root = switch (input.installed) {
        .install_root => |path| path,
    };
    const root_z = try arena.dupeZ(u8, install_root);
    const arch_z = try arena.dupeZ(u8, input.environment.architecture);
    const releasever_z = try arena.dupeZ(u8, input.environment.release_version);

    var commands = try arena.alloc(?[*:0]u8, input.subjects.len + 2);
    commands[0] = @constCast(input.operation.verb().ptr);
    for (input.subjects, 0..) |subject, index| {
        commands[index + 1] = (try arena.dupeZ(u8, subject)).ptr;
    }
    commands[input.subjects.len + 1] = null;

    const setopts = create_cnfnode("(setopts)") orelse return error.OutOfMemory;
    defer destroy_cnftree(setopts);
    const repoopts = create_cnfnode("(repoopts)") orelse return error.OutOfMemory;
    defer destroy_cnftree(repoopts);

    var args = CmdArgs{
        .nAllDeps = @intFromBool(input.policy.all_deps),
        .nAllowErasing = @intFromBool(input.policy.allow_erasing),
        .nBest = @intFromBool(input.policy.best),
        .nQuiet = 1,
        .nSkipBroken = @intFromBool(input.policy.skip_broken),
        .pszArch = arch_z.ptr,
        .pszInstallRoot = root_z.ptr,
        .pszConfFile = scratch.config.ptr,
        .pszReleaseVer = releasever_z.ptr,
        .ppszCmds = commands.ptr,
        .nCmdCount = @intCast(input.subjects.len + 1),
        .cn_setopts = @ptrCast(@alignCast(setopts)),
        .cn_repoopts = @ptrCast(@alignCast(repoopts)),
    };

    var handle_opt: ?*Tdnf = null;
    const open_result = TDNFOpenHandle(&args, &handle_opt);
    if (open_result != 0) return mapError(open_result);
    const handle = handle_opt orelse return error.ResolveFailed;
    defer TDNFCloseHandle(handle);

    try applySecrets(handle, input);
    try declareEnvironment(handle, input.environment);

    const state = integration.State.create(allocator) catch
        return error.OutOfMemory;
    state.setEnabled(true);
    // The handle must not outlive or free a state this function owns.
    handle.pTransactionPlanState = @ptrCast(state);
    defer {
        handle.pTransactionPlanState = null;
        state.destroy();
    }

    var solved: ?*abi.SolvedPackageInfo = null;
    const resolve_result = resolve_service.resolve(
        .{ .handle = handle, .operation = input.operation.service() },
        &solved,
    );
    if (solved != null) TDNFFreeSolvedPackageInfo(@ptrCast(solved));

    // A solver contradiction publishes a structured problem plan and still
    // reports a resolve error. The published plan is the answer in that case,
    // exactly as it is for `tdnf plan`.
    if (state.takePublished()) |plan| return plan;
    if (resolve_result == 0) return error.ResolveFailed;
    return mapError(resolve_result);
}

fn validate(input: ResolveInput) ResolveError!void {
    if (input.operation.isSingleton() and input.subjects.len != 0)
        return error.InvalidSubjects;
    if (input.operation.requiresSubjects() and input.subjects.len == 0)
        return error.InvalidSubjects;
    for (input.subjects) |subject| {
        if (subject.len == 0) return error.InvalidSubjects;
    }

    const environment = input.environment;
    if (environment.architecture.len == 0 or environment.distro.len == 0 or
        environment.release_version.len == 0)
        return error.InvalidEnvironment;

    switch (input.installed) {
        .install_root => |path| {
            if (!std.fs.path.isAbsolute(path) or
                std.mem.eql(u8, path, "/"))
                return error.InvalidPath;
        },
    }
    if (!std.fs.path.isAbsolute(input.cache_dir) or
        !std.fs.path.isAbsolute(input.scratch_dir))
        return error.InvalidPath;

    for (input.repositories, 0..) |repository, index| {
        try validateRepository(repository);
        for (input.repositories[index + 1 ..]) |other| {
            if (std.mem.eql(u8, repository.id, other.id))
                return error.DuplicateRepositoryId;
        }
    }
}

fn validateRepository(repository: Repository) ResolveError!void {
    if (repository.id.len == 0) return error.InvalidRepository;
    for (repository.id) |byte| {
        if (byte <= ' ' or byte == '/' or byte == 0x7f)
            return error.InvalidRepository;
    }
    // `@cmdline` is the resolver's own staging repository.
    if (repository.id[0] == '@') return error.InvalidRepository;
    if (repository.cost != default_repository_cost)
        return error.InvalidRepository;

    switch (repository.metadata) {
        .local_snapshot => |path| {
            if (!std.fs.path.isAbsolute(path)) return error.InvalidPath;
        },
        .remote => |remote| {
            if (remote.base_urls.len == 0 and remote.metalink == null)
                return error.InvalidRepository;
            for (remote.base_urls) |url| try rejectCredentials(url);
            if (remote.metalink) |url| try rejectCredentials(url);
        },
    }
    for (repository.gpg_keys) |key| try rejectCredentials(key);
}

/// `scheme://user:secret@host/...` would put credentials in the scratch
/// configuration and in every diagnostic that echoes the URL.
fn rejectCredentials(url: []const u8) ResolveError!void {
    if (url.len == 0) return error.InvalidRepository;
    if (std.mem.indexOf(u8, url, "\n") != null) return error.InvalidRepository;
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return;
    const rest = url[scheme_end + 3 ..];
    const authority_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
    if (std.mem.indexOfScalar(u8, rest[0..authority_end], '@') != null)
        return error.CredentialsInUrl;
}

/// Overwrites whatever the generated configuration derived with the caller's
/// declared environment, so no host `os-release`, kernel architecture, or
/// `distroverpkg` lookup can reach the plan.
fn declareEnvironment(handle: *Tdnf, environment: Environment) ResolveError!void {
    const conf = handle.pConf orelse return error.ResolveFailed;
    try replaceOwned(&conf.pszOSName, environment.distro);
    try replaceOwned(&conf.pszVarReleaseVer, environment.release_version);
    try replaceOwned(&conf.pszVarBaseArch, environment.architecture);
    try replaceOwned(&conf.pszBaseArch, environment.architecture);
}

fn applySecrets(handle: *Tdnf, input: ResolveInput) ResolveError!void {
    for (input.repositories) |repository| {
        const remote = switch (repository.metadata) {
            .remote => |value| value,
            .local_snapshot => continue,
        };
        const provider = remote.secrets orelse continue;
        const data = findRepository(handle, repository.id) orelse
            return error.InvalidRepository;
        if (provider.lookup(provider.context, repository.id, .username)) |value|
            try replaceOwned(&data.pszUser, value);
        if (provider.lookup(provider.context, repository.id, .password)) |value|
            try replaceOwned(&data.pszPass, value);
    }
}

fn findRepository(handle: *Tdnf, id: []const u8) ?*RepoData {
    var current = handle.pRepos;
    while (current) |data| : (current = data.pNext) {
        const raw = data.pszId orelse continue;
        if (std.mem.eql(u8, std.mem.span(raw), id)) return data;
    }
    return null;
}

/// Replaces a private-ABI owned string. The replacement is allocated by the
/// same allocator the handle teardown frees with.
fn replaceOwned(slot: *?[*:0]u8, value: []const u8) ResolveError!void {
    var buffer: [512]u8 = undefined;
    var storage: []u8 = &buffer;
    var heap: ?[]u8 = null;
    defer if (heap) |owned| std.heap.c_allocator.free(owned);
    if (value.len + 1 > buffer.len) {
        const owned = std.heap.c_allocator.alloc(u8, value.len + 1) catch
            return error.OutOfMemory;
        heap = owned;
        storage = owned;
    }
    @memcpy(storage[0..value.len], value);
    storage[value.len] = 0;

    var replacement: ?[*:0]u8 = null;
    const result = TDNFAllocateString(
        @ptrCast(storage.ptr),
        &replacement,
    );
    if (result != 0) return mapError(result);
    if (slot.*) |previous| TDNFFreeMemory(@ptrCast(previous));
    slot.* = replacement;
}

/// The private, single-use configuration tree the resolve reads.
///
/// It exists so the resolve can be driven entirely by `ResolveInput`: the
/// generated `tdnf.conf` names a repository directory, a locks/protected/
/// minversions tree, and a persist directory that all live inside this
/// directory, so no host configuration is reachable.
const Scratch = struct {
    allocator: Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    name: []u8,
    config: [:0]u8,

    fn create(
        allocator: Allocator,
        io: std.Io,
        input: ResolveInput,
    ) ResolveError!Scratch {
        var suffix: [16]u8 = undefined;
        io.random(&suffix);
        const name = std.fmt.allocPrint(
            allocator,
            "tdnf-resolve-{x}",
            .{&suffix},
        ) catch return error.OutOfMemory;
        errdefer allocator.free(name);

        std.Io.Dir.cwd().createDirPath(io, input.scratch_dir) catch
            return error.ScratchStorageFailed;
        var parent = std.Io.Dir.cwd().openDir(io, input.scratch_dir, .{}) catch
            return error.ScratchStorageFailed;
        errdefer parent.close(io);
        parent.createDirPath(io, name) catch return error.ScratchStorageFailed;

        const config = std.fmt.allocPrintSentinel(
            allocator,
            "{s}/{s}/tdnf.conf",
            .{ input.scratch_dir, name },
            0,
        ) catch return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .io = io,
            .parent = parent,
            .name = name,
            .config = config,
        };
    }

    fn destroy(self: *Scratch) void {
        self.parent.deleteTree(self.io, self.name) catch {};
        self.parent.close(self.io);
        self.allocator.free(self.config);
        self.allocator.free(self.name);
        self.* = undefined;
    }

    fn write(self: *Scratch, relative: []const u8, data: []const u8) ResolveError!void {
        const path = std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.name, relative },
        ) catch return error.OutOfMemory;
        defer self.allocator.free(path);
        self.parent.writeFile(self.io, .{
            .sub_path = path,
            .data = data,
        }) catch return error.ScratchStorageFailed;
    }

    fn createDir(self: *Scratch, relative: []const u8) ResolveError!void {
        const path = std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.name, relative },
        ) catch return error.OutOfMemory;
        defer self.allocator.free(path);
        self.parent.createDirPath(self.io, path) catch
            return error.ScratchStorageFailed;
    }

    fn materialize(self: *Scratch, input: ResolveInput) ResolveError!void {
        inline for (.{ "repos", "persist", "locks.d", "protected.d", "minversions.d" }) |dir| {
            try self.createDir(dir);
        }

        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(self.allocator);
        try self.renderConfig(&body, input);
        try self.write("tdnf.conf", body.items);

        try self.writeNameList("locks.d/policy.conf", input.policy.locked_names);
        try self.writeNameList(
            "protected.d/policy.conf",
            input.policy.protected_names,
        );

        body.clearRetainingCapacity();
        for (input.policy.min_versions) |constraint| {
            appendFmt(self.allocator, &body, "{s}={s}\n", .{
                constraint.name,
                constraint.evr,
            }) catch return error.OutOfMemory;
        }
        try self.write("minversions.d/policy.conf", body.items);

        for (input.repositories) |repository| {
            body.clearRetainingCapacity();
            try self.renderRepository(&body, repository);
            const relative = std.fmt.allocPrint(
                self.allocator,
                "repos/{s}.repo",
                .{repository.id},
            ) catch return error.OutOfMemory;
            defer self.allocator.free(relative);
            try self.write(relative, body.items);
        }
    }

    fn writeNameList(
        self: *Scratch,
        relative: []const u8,
        names: []const []const u8,
    ) ResolveError!void {
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(self.allocator);
        for (names) |name| {
            appendFmt(self.allocator, &body, "{s}\n", .{name}) catch
                return error.OutOfMemory;
        }
        try self.write(relative, body.items);
    }

    fn renderConfig(
        self: *Scratch,
        body: *std.ArrayList(u8),
        input: ResolveInput,
    ) ResolveError!void {
        const allocator = self.allocator;
        appendFmt(allocator, body,
            \\[main]
            \\gpgcheck=0
            \\plugins=0
            \\installonly_limit={d}
            \\clean_requirements_on_remove={d}
            \\distrosync_reinstall_changed=0
            \\repodir={s}/{s}/repos
            \\cachedir={s}
            \\persistdir={s}/{s}/persist
            \\varsdir=
            \\
        , .{
            input.policy.installonly_limit,
            @intFromBool(input.policy.clean_requirements_on_remove),
            self.rootPath(),
            self.name,
            input.cache_dir,
            self.rootPath(),
            self.name,
        }) catch return error.OutOfMemory;
        for (input.policy.excludes) |value| {
            appendFmt(allocator, body, "excludepkgs={s}\n", .{value}) catch
                return error.OutOfMemory;
        }
        for (input.policy.installonly_names) |value| {
            appendFmt(allocator, body, "installonlypkgs={s}\n", .{value}) catch
                return error.OutOfMemory;
        }
    }

    fn rootPath(self: *const Scratch) []const u8 {
        // `config` is "<scratch_dir>/<name>/tdnf.conf".
        const without_file = std.fs.path.dirname(self.config) orelse ".";
        return std.fs.path.dirname(without_file) orelse ".";
    }

    fn renderRepository(
        self: *Scratch,
        body: *std.ArrayList(u8),
        repository: Repository,
    ) ResolveError!void {
        const allocator = self.allocator;
        appendFmt(allocator, body,
            \\[{s}]
            \\name={s}
            \\enabled=1
            \\priority={d}
            \\gpgcheck={d}
            \\skip_if_unavailable={d}
            \\
        , .{
            repository.id,
            repository.id,
            repository.priority,
            @intFromBool(repository.gpg_check),
            @intFromBool(repository.skip_if_unavailable),
        }) catch return error.OutOfMemory;

        switch (repository.metadata) {
            .local_snapshot => |path| {
                // A local snapshot is already the caller's chosen state, so it
                // must never expire and be silently refetched.
                appendFmt(allocator, body,
                    \\baseurl=file://{s}
                    \\metadata_expire=never
                    \\sslverify=1
                    \\
                , .{path}) catch return error.OutOfMemory;
            },
            .remote => |remote| {
                for (remote.base_urls) |url| {
                    appendFmt(allocator, body, "baseurl={s}\n", .{url}) catch
                        return error.OutOfMemory;
                }
                if (remote.metalink) |url| {
                    appendFmt(allocator, body, "metalink={s}\n", .{url}) catch
                        return error.OutOfMemory;
                }
                appendFmt(allocator, body, "sslverify={d}\n", .{
                    @intFromBool(remote.ssl_verify),
                }) catch return error.OutOfMemory;
            },
        }
        for (repository.gpg_keys) |key| {
            appendFmt(allocator, body, "gpgkey={s}\n", .{key}) catch
                return error.OutOfMemory;
        }
    }
};

fn appendFmt(
    allocator: Allocator,
    body: *std.ArrayList(u8),
    comptime format: []const u8,
    arguments: anytype,
) Allocator.Error!void {
    const rendered = try std.fmt.allocPrint(allocator, format, arguments);
    defer allocator.free(rendered);
    try body.appendSlice(allocator, rendered);
}

const testing = std.testing;

test "resolver: singleton operations reject subjects and subject operations require them" {
    const base = ResolveInput{
        .operation = .upgrade_all,
        .subjects = &.{"pkg"},
        .installed = .{ .install_root = "/scratch/root" },
        .environment = .{
            .architecture = "x86_64",
            .distro = "photon",
            .release_version = "5.0",
        },
        .scratch_dir = "/scratch/work",
    };
    try testing.expectError(error.InvalidSubjects, validate(base));

    var empty = base;
    empty.operation = .install;
    empty.subjects = &.{};
    try testing.expectError(error.InvalidSubjects, validate(empty));

    var ok = base;
    ok.subjects = &.{};
    try validate(ok);
}

test "resolver: explicit environment values are required" {
    var input = ResolveInput{
        .operation = .upgrade_all,
        .installed = .{ .install_root = "/scratch/root" },
        .environment = .{
            .architecture = "",
            .distro = "photon",
            .release_version = "5.0",
        },
        .scratch_dir = "/scratch/work",
    };
    try testing.expectError(error.InvalidEnvironment, validate(input));
    input.environment.architecture = "x86_64";
    input.environment.distro = "";
    try testing.expectError(error.InvalidEnvironment, validate(input));
    input.environment.distro = "photon";
    input.environment.release_version = "";
    try testing.expectError(error.InvalidEnvironment, validate(input));
}

test "resolver: relative install roots, caches, and scratch directories are rejected" {
    var input = ResolveInput{
        .operation = .upgrade_all,
        .installed = .{ .install_root = "root" },
        .environment = .{
            .architecture = "x86_64",
            .distro = "photon",
            .release_version = "5.0",
        },
        .scratch_dir = "/scratch/work",
    };
    try testing.expectError(error.InvalidPath, validate(input));
    input.installed = .{ .install_root = "/" };
    try testing.expectError(error.InvalidPath, validate(input));
    input.installed = .{ .install_root = "/scratch/root" };
    input.cache_dir = "cache";
    try testing.expectError(error.InvalidPath, validate(input));
    input.cache_dir = "/var/cache/tdnf";
    input.scratch_dir = "work";
    try testing.expectError(error.InvalidPath, validate(input));
}

test "resolver: repository identity, cost, and credential rules" {
    const remote = Repository{
        .id = "base",
        .metadata = .{ .remote = .{ .base_urls = &.{"https://example.invalid/base"} } },
    };
    try validateRepository(remote);

    var anonymous = remote;
    anonymous.id = "";
    try testing.expectError(error.InvalidRepository, validateRepository(anonymous));

    var reserved = remote;
    reserved.id = "@cmdline";
    try testing.expectError(error.InvalidRepository, validateRepository(reserved));

    var spaced = remote;
    spaced.id = "base repo";
    try testing.expectError(error.InvalidRepository, validateRepository(spaced));

    var costed = remote;
    costed.cost = 1;
    try testing.expectError(error.InvalidRepository, validateRepository(costed));

    var credentialed = remote;
    credentialed.metadata = .{ .remote = .{
        .base_urls = &.{"https://user:secret@example.invalid/base"},
    } };
    try testing.expectError(
        error.CredentialsInUrl,
        validateRepository(credentialed),
    );

    var sourceless = remote;
    sourceless.metadata = .{ .remote = .{} };
    try testing.expectError(
        error.InvalidRepository,
        validateRepository(sourceless),
    );

    var relative = remote;
    relative.metadata = .{ .local_snapshot = "snapshot" };
    try testing.expectError(error.InvalidPath, validateRepository(relative));
}

test "resolver: duplicate repository ids are rejected" {
    const repositories = [_]Repository{
        .{ .id = "base", .metadata = .{ .local_snapshot = "/snapshot/base" } },
        .{ .id = "base", .metadata = .{ .local_snapshot = "/snapshot/other" } },
    };
    const input = ResolveInput{
        .operation = .upgrade_all,
        .repositories = &repositories,
        .installed = .{ .install_root = "/scratch/root" },
        .environment = .{
            .architecture = "x86_64",
            .distro = "photon",
            .release_version = "5.0",
        },
        .scratch_dir = "/scratch/work",
    };
    try testing.expectError(error.DuplicateRepositoryId, validate(input));
}

test "resolver: credential detection only inspects the authority" {
    try rejectCredentials("https://example.invalid/base@2024");
    try rejectCredentials("file:///snapshot/base");
    try rejectCredentials("/snapshot/key.gpg");
    try testing.expectError(
        error.CredentialsInUrl,
        rejectCredentials("https://user@example.invalid/base"),
    );
    try testing.expectError(
        error.CredentialsInUrl,
        rejectCredentials("https://user:pass@example.invalid"),
    );
}

test "resolver: every public operation maps onto exactly one service operation" {
    var seen = std.EnumSet(resolve_service.Operation).initEmpty();
    inline for (comptime std.enums.values(Operation)) |operation| {
        const mapped = operation.service();
        try testing.expect(!seen.contains(mapped));
        seen.insert(mapped);
        try testing.expect(operation.verb().len != 0);
    }
    // `obsoleted` is an outcome, never a request.
    try testing.expect(!seen.contains(.obsoleted));
}
