const std = @import("std");

const available_loader = @import("available_loader.zig");
const cmdline_repository = @import("cmdline_repository.zig");
const directory_repository = @import("directory_repository.zig");
const installed_repository = @import("installed_repository.zig");
const model = @import("model.zig");
const rpmpkg = @import("rpmpkg.zig");

const abi = @import("tdnf_internal_abi");

const IdList = extern struct {
    elements: ?[*]i32,
    count: u32,
    capacity: u32,
};

extern fn TDNFIdListPush(list: *IdList, value: i32) u32;
extern fn TDNFAllocateString(value: [*:0]const u8, output: *?[*:0]u8) u32;
extern fn TDNFAllocateMemory(
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32;
extern fn TDNFFreeMemory(value: ?*anyopaque) void;

pub const RepositoryKind = enum {
    installed,
    available,
    command_line,
};

pub const PackageFields = struct {
    repository: [*:0]const u8,
    name: [*:0]const u8,
    arch: [*:0]const u8,
    evr: [*:0]const u8,
    nevra: [*:0]const u8,
};

pub const Repository = struct {
    arena_state: std.heap.ArenaAllocator,
    id: [:0]const u8,
    kind: RepositoryKind,
    owner: ?*anyopaque,
    priority: i32,
    model: model.RepositoryModel,
    installed_states: []const installed_repository.InstalledState,
    fields: []const PackageFields,
    handles: []u32,
    cookie_sha256: [32]u8 = [_]u8{0} ** 32,
    cache_options: available_loader.CacheOptions = .{},
    has_cookie: bool = false,
    cmdline_paths: std.ArrayList([:0]u8) = .empty,

    fn deinit(self: *Repository, allocator: std.mem.Allocator) void {
        for (self.cmdline_paths.items) |path| allocator.free(path);
        self.cmdline_paths.deinit(allocator);
        self.arena_state.deinit();
        allocator.destroy(self);
    }
};

const Impl = struct {
    allocator: std.mem.Allocator,
    cache_dir: ?[:0]u8,
    root_dir: ?[:0]u8,
    architecture: [:0]u8,
    repositories: std.ArrayList(*Repository) = .empty,
    package_slots: std.ArrayList(?PackageView) = .empty,
    installed: ?*Repository = null,
    command_line: ?*Repository = null,

    fn deinit(self: *Impl) void {
        for (self.repositories.items) |repository| {
            repository.deinit(self.allocator);
        }
        self.repositories.deinit(self.allocator);
        self.package_slots.deinit(self.allocator);
        if (self.cache_dir) |value| self.allocator.free(value);
        if (self.root_dir) |value| self.allocator.free(value);
        self.allocator.free(self.architecture);
        self.allocator.destroy(self);
    }
};

pub const Context = struct {
    impl: *Impl,
};

const PackageView = struct {
    repository: *Repository,
    index: usize,
};

pub fn create(
    allocator: std.mem.Allocator,
    cache_dir: ?[]const u8,
    root_dir: ?[]const u8,
    requested_architecture: []const u8,
) error{OutOfMemory}!*Context {
    const context = try allocator.create(Context);
    errdefer allocator.destroy(context);
    const impl = try allocator.create(Impl);
    errdefer allocator.destroy(impl);
    const owned_cache_dir = if (cache_dir) |value|
        try allocator.dupeZ(u8, value)
    else
        null;
    errdefer if (owned_cache_dir) |value| allocator.free(value);
    const owned_root_dir = if (root_dir) |value|
        try allocator.dupeZ(u8, value)
    else
        null;
    errdefer if (owned_root_dir) |value| allocator.free(value);
    const owned_architecture = try allocator.dupeZ(u8, requested_architecture);
    errdefer allocator.free(owned_architecture);
    impl.* = .{
        .allocator = allocator,
        .cache_dir = owned_cache_dir,
        .root_dir = owned_root_dir,
        .architecture = owned_architecture,
    };
    context.* = .{ .impl = impl };
    return context;
}

pub fn destroy(context: *Context) void {
    const allocator = context.impl.allocator;
    context.impl.deinit();
    allocator.destroy(context);
}

pub fn swap(left: *Context, right: *Context) error{OutOfMemory}!void {
    try remapReplacementHandles(left.impl, right.impl);
    std.mem.swap(*Impl, &left.impl, &right.impl);
}

pub fn cacheDir(context: *const Context) ?[*:0]const u8 {
    return if (context.impl.cache_dir) |value| value.ptr else null;
}

pub fn rootDir(context: *const Context) ?[*:0]const u8 {
    return if (context.impl.root_dir) |value| value.ptr else null;
}

pub fn architecture(context: *const Context) [*:0]const u8 {
    return context.impl.architecture.ptr;
}

pub fn identity(context: *const Context) usize {
    return @intFromPtr(context.impl);
}

pub fn loadInstalled(
    context: *Context,
    source: installed_repository.Source,
) installed_repository.LoadError!void {
    const loaded = try installed_repository.load(
        context.impl.allocator,
        source,
        .{},
    );
    var arena_state = loaded.arena_state;
    errdefer arena_state.deinit();
    const repository = try context.impl.allocator.create(Repository);
    errdefer context.impl.allocator.destroy(repository);
    const id = try arena_state.allocator().dupeZ(u8, "@System");
    const fields = try buildFields(
        arena_state.allocator(),
        id,
        loaded.repository,
    );
    repository.* = .{
        .arena_state = arena_state,
        .id = id,
        .kind = .installed,
        .owner = null,
        .priority = 0,
        .model = loaded.repository,
        .installed_states = loaded.installed_states,
        .fields = fields,
        .handles = &.{},
    };
    try replaceRepository(context, repository);
}

pub fn createCommandLine(context: *Context) error{OutOfMemory}!*Repository {
    if (context.impl.command_line) |repository| return repository;
    var arena_state = std.heap.ArenaAllocator.init(context.impl.allocator);
    errdefer arena_state.deinit();
    const repository = try context.impl.allocator.create(Repository);
    errdefer context.impl.allocator.destroy(repository);
    const id = try arena_state.allocator().dupeZ(u8, "@cmdline");
    repository.* = .{
        .arena_state = arena_state,
        .id = id,
        .kind = .command_line,
        .owner = null,
        .priority = 0,
        .model = .{},
        .installed_states = &.{},
        .fields = &.{},
        .handles = &.{},
    };
    try context.impl.repositories.ensureUnusedCapacity(
        context.impl.allocator,
        1,
    );
    try bindRepositoryHandles(context.impl, repository, null, repository);
    context.impl.repositories.appendAssumeCapacity(repository);
    context.impl.command_line = repository;
    return repository;
}

pub fn commandLineRepository(context: *const Context) ?*Repository {
    return context.impl.command_line;
}

pub fn loadAvailableMetadata(
    context: *Context,
    id: []const u8,
    owner: ?*anyopaque,
    priority: i32,
    paths: available_loader.Paths,
    verify_integrity: bool,
) available_loader.LoadError!*Repository {
    var arena_state = std.heap.ArenaAllocator.init(context.impl.allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();
    const loaded = if (verify_integrity)
        try available_loader.loadModelWithRepomd(arena, paths)
    else
        try available_loader.loadLegacyModelWithRepomd(arena, paths);
    const repository = try finishAvailable(
        context,
        arena_state,
        id,
        owner,
        priority,
        loaded.repository,
    );
    repository.cache_options = .{
        .include_filelists = paths.filelists != null,
        .include_updateinfo = paths.updateinfo != null,
        .include_other = paths.other != null,
    };
    repository.cookie_sha256 = available_loader.solvCacheCookie(
        loaded.repomd_bytes,
        repository.cache_options,
    );
    repository.has_cookie = true;
    return repository;
}

pub fn loadAvailableDirectory(
    context: *Context,
    id: []const u8,
    owner: ?*anyopaque,
    priority: i32,
    directory: []const u8,
) directory_repository.LoadError!*Repository {
    var arena_state = std.heap.ArenaAllocator.init(context.impl.allocator);
    errdefer arena_state.deinit();
    const repository_model = try directory_repository.loadModelOrdered(
        arena_state.allocator(),
        directory,
        .read,
    );
    return finishAvailable(
        context,
        arena_state,
        id,
        owner,
        priority,
        repository_model,
    );
}

fn finishAvailable(
    context: *Context,
    arena_state: std.heap.ArenaAllocator,
    id_value: []const u8,
    owner: ?*anyopaque,
    priority: i32,
    repository_model: model.RepositoryModel,
) error{OutOfMemory}!*Repository {
    var owned_arena = arena_state;
    errdefer owned_arena.deinit();
    const repository = try context.impl.allocator.create(Repository);
    errdefer context.impl.allocator.destroy(repository);
    const id = try owned_arena.allocator().dupeZ(u8, id_value);
    const fields = try buildFields(
        owned_arena.allocator(),
        id,
        repository_model,
    );
    repository.* = .{
        .arena_state = owned_arena,
        .id = id,
        .kind = .available,
        .owner = owner,
        .priority = priority,
        .model = repository_model,
        .installed_states = &.{},
        .fields = fields,
        .handles = &.{},
    };
    try replaceRepository(context, repository);
    return repository;
}

fn replaceRepository(
    context: *Context,
    replacement: *Repository,
) error{OutOfMemory}!void {
    for (context.impl.repositories.items, 0..) |current, index| {
        if (!repositoriesMatch(current, replacement)) continue;
        try bindRepositoryHandles(
            context.impl,
            replacement,
            current,
            replacement,
        );
        context.impl.repositories.items[index] = replacement;
        if (current == context.impl.installed) context.impl.installed = replacement;
        if (current == context.impl.command_line) context.impl.command_line = replacement;
        current.deinit(context.impl.allocator);
        return;
    }
    try context.impl.repositories.ensureUnusedCapacity(
        context.impl.allocator,
        1,
    );
    try bindRepositoryHandles(context.impl, replacement, null, replacement);
    context.impl.repositories.appendAssumeCapacity(replacement);
    if (replacement.kind == .installed) context.impl.installed = replacement;
    if (replacement.kind == .command_line) context.impl.command_line = replacement;
}

pub fn removeRepository(context: *Context, repository: *Repository) bool {
    for (context.impl.repositories.items, 0..) |candidate, index| {
        if (candidate != repository) continue;
        _ = context.impl.repositories.orderedRemove(index);
        invalidateRepositoryHandles(context.impl, candidate);
        if (candidate == context.impl.installed) context.impl.installed = null;
        if (candidate == context.impl.command_line) context.impl.command_line = null;
        candidate.deinit(context.impl.allocator);
        return true;
    }
    return false;
}

pub fn findRepositoryByOwner(
    context: *const Context,
    owner: ?*anyopaque,
) ?*Repository {
    if (owner == null) return null;
    for (context.impl.repositories.items) |repository| {
        if (repository.owner == owner) return repository;
    }
    return null;
}

pub fn repositories(context: *const Context) []const *Repository {
    return context.impl.repositories.items;
}

pub fn packageCount(context: *const Context) usize {
    var count: usize = 0;
    for (context.impl.repositories.items) |repository| {
        count += repository.model.packages.len;
    }
    return count;
}

pub fn addCommandLineRpm(
    context: *Context,
    repository: *Repository,
    path: []const u8,
) cmdline_repository.LoadError!u32 {
    if (repository != context.impl.command_line or
        repository.kind != .command_line)
    {
        return error.RpmFileOpenFailed;
    }
    const owned_path = try context.impl.allocator.dupeZ(u8, path);
    errdefer context.impl.allocator.free(owned_path);
    try repository.cmdline_paths.append(context.impl.allocator, owned_path);
    errdefer _ = repository.cmdline_paths.pop();

    var arena_state = std.heap.ArenaAllocator.init(context.impl.allocator);
    errdefer arena_state.deinit();
    const repository_model = try cmdline_repository.loadModel(
        arena_state.allocator(),
        repository.cmdline_paths.items,
    );
    const id = try arena_state.allocator().dupeZ(u8, repository.id);
    const fields = try buildFields(
        arena_state.allocator(),
        id,
        repository_model,
    );
    var replacement = Repository{
        .arena_state = arena_state,
        .id = id,
        .kind = .command_line,
        .owner = null,
        .priority = repository.priority,
        .model = repository_model,
        .installed_states = &.{},
        .fields = fields,
        .handles = &.{},
    };
    try bindRepositoryHandles(
        context.impl,
        &replacement,
        repository,
        repository,
    );
    repository.arena_state.deinit();
    repository.arena_state = arena_state;
    repository.id = id;
    repository.model = repository_model;
    repository.fields = fields;
    repository.handles = replacement.handles;
    return packageIdFor(repository, repository_model.packages.len - 1);
}

pub fn resetCommandLine(context: *Context) error{OutOfMemory}!*Repository {
    const current = context.impl.command_line orelse return createCommandLine(context);
    var replacement_arena = std.heap.ArenaAllocator.init(context.impl.allocator);
    errdefer replacement_arena.deinit();
    const replacement_id = try replacement_arena.allocator().dupeZ(
        u8,
        "@cmdline",
    );
    for (current.cmdline_paths.items) |path| context.impl.allocator.free(path);
    current.cmdline_paths.clearRetainingCapacity();
    invalidateRepositoryHandles(context.impl, current);
    current.arena_state.deinit();
    current.arena_state = replacement_arena;
    current.id = replacement_id;
    current.model = .{};
    current.fields = &.{};
    current.handles = &.{};
    return current;
}

pub fn installedPackageIds(
    context: *const Context,
    output: *std.ArrayList(i32),
) error{OutOfMemory}!void {
    const repository = context.impl.installed orelse return;
    for (repository.handles) |handle| {
        try output.append(context.impl.allocator, @intCast(handle));
    }
}

pub fn allPackageIds(
    context: *const Context,
    output: *std.ArrayList(i32),
) error{OutOfMemory}!void {
    if (context.impl.installed) |repository| {
        for (repository.handles) |handle| {
            try output.append(context.impl.allocator, @intCast(handle));
        }
    }
    for (context.impl.repositories.items) |repository| {
        if (repository.kind != .available) continue;
        for (repository.handles) |handle| {
            try output.append(context.impl.allocator, @intCast(handle));
        }
    }
    if (context.impl.command_line) |repository| {
        for (repository.handles) |handle| {
            try output.append(context.impl.allocator, @intCast(handle));
        }
    }
}

pub fn packageFields(
    context: *const Context,
    package_id: i32,
) ?PackageFields {
    const view = packageView(context, package_id) orelse return null;
    return view.repository.fields[view.index];
}

pub fn packageModel(
    context: *const Context,
    package_id: i32,
) ?*const model.Package {
    const view = packageView(context, package_id) orelse return null;
    return &view.repository.model.packages[view.index];
}

pub fn packageRepository(
    context: *const Context,
    package_id: i32,
) ?*Repository {
    return (packageView(context, package_id) orelse return null).repository;
}

pub fn packageInstalledState(
    context: *const Context,
    package_id: i32,
) ?installed_repository.InstalledState {
    const view = packageView(context, package_id) orelse return null;
    if (view.repository.kind != .installed or
        view.index >= view.repository.installed_states.len)
    {
        return null;
    }
    return view.repository.installed_states[view.index];
}

fn packageView(context: *const Context, raw_id: i32) ?PackageView {
    if (raw_id <= 0) return null;
    const index: usize = @intCast(raw_id - 1);
    if (index >= context.impl.package_slots.items.len) return null;
    return context.impl.package_slots.items[index];
}

fn packageIdFor(
    target: *const Repository,
    package_index: usize,
) u32 {
    return target.handles[package_index];
}

fn repositoriesMatch(left: *const Repository, right: *const Repository) bool {
    if (left.kind != right.kind) return false;
    return switch (right.kind) {
        .installed, .command_line => true,
        .available => (right.owner != null and left.owner == right.owner) or
            std.mem.eql(u8, left.id, right.id),
    };
}

fn samePackageIdentity(left: model.Package, right: model.Package) bool {
    return std.mem.eql(u8, left.pkg_id, right.pkg_id) and
        std.mem.eql(u8, left.nevra.name, right.nevra.name) and
        left.nevra.epoch == right.nevra.epoch and
        std.mem.eql(u8, left.nevra.version, right.nevra.version) and
        std.mem.eql(u8, left.nevra.release, right.nevra.release) and
        std.mem.eql(u8, left.nevra.arch, right.nevra.arch);
}

fn sameRetainedIdentity(
    prior: *const Repository,
    prior_index: usize,
    replacement: *const Repository,
    replacement_index: usize,
) bool {
    if (!samePackageIdentity(
        prior.model.packages[prior_index],
        replacement.model.packages[replacement_index],
    )) return false;
    if (prior.kind != .installed) return true;
    if (prior_index >= prior.installed_states.len or
        replacement_index >= replacement.installed_states.len)
    {
        return false;
    }
    return prior.installed_states[prior_index].rpmdb_hnum ==
        replacement.installed_states[replacement_index].rpmdb_hnum;
}

fn retainedHandle(
    prior: *const Repository,
    replacement: *const Repository,
    replacement_index: usize,
) ?u32 {
    for (prior.model.packages, 0..) |_, prior_index| {
        if (!sameRetainedIdentity(
            prior,
            prior_index,
            replacement,
            replacement_index,
        )) continue;
        const handle = prior.handles[prior_index];
        var already_retained = false;
        for (replacement.handles[0..replacement_index]) |assigned| {
            if (assigned == handle) {
                already_retained = true;
                break;
            }
        }
        if (!already_retained) return handle;
    }
    return null;
}

fn bindRepositoryHandles(
    impl: *Impl,
    repository: *Repository,
    prior: ?*const Repository,
    binding: *Repository,
) error{OutOfMemory}!void {
    const handles = try repository.arena_state.allocator().alloc(
        u32,
        repository.model.packages.len,
    );
    repository.handles = handles;
    var new_count: usize = 0;
    for (repository.model.packages, 0..) |_, index| {
        handles[index] = if (prior) |value|
            retainedHandle(value, repository, index) orelse blk: {
                new_count += 1;
                break :blk 0;
            }
        else blk: {
            new_count += 1;
            break :blk 0;
        };
    }
    try impl.package_slots.ensureUnusedCapacity(impl.allocator, new_count);

    if (prior) |value| invalidateRepositoryHandles(impl, value);
    for (handles, 0..) |*handle, index| {
        if (handle.* == 0) {
            handle.* = @intCast(impl.package_slots.items.len + 1);
            impl.package_slots.appendAssumeCapacity(null);
        }
        impl.package_slots.items[handle.* - 1] = .{
            .repository = binding,
            .index = index,
        };
    }
}

fn invalidateRepositoryHandles(impl: *Impl, repository: *const Repository) void {
    for (repository.handles) |handle| {
        const index = handle - 1;
        if (index < impl.package_slots.items.len) {
            impl.package_slots.items[index] = null;
        }
    }
}

fn matchingRepository(
    repositories_list: []const *Repository,
    replacement: *const Repository,
) ?*const Repository {
    for (repositories_list) |candidate| {
        if (repositoriesMatch(candidate, replacement)) return candidate;
    }
    return null;
}

fn remapReplacementHandles(
    stable: *const Impl,
    replacement: *Impl,
) error{OutOfMemory}!void {
    var new_count: usize = 0;
    for (replacement.repositories.items) |repository| {
        const prior = matchingRepository(stable.repositories.items, repository);
        @memset(repository.handles, 0);
        for (repository.model.packages, 0..) |_, index| {
            repository.handles[index] = if (prior) |value|
                retainedHandle(value, repository, index) orelse blk: {
                    new_count += 1;
                    break :blk 0;
                }
            else blk: {
                new_count += 1;
                break :blk 0;
            };
        }
    }

    var slots: std.ArrayList(?PackageView) = .empty;
    errdefer slots.deinit(replacement.allocator);
    try slots.resize(
        replacement.allocator,
        stable.package_slots.items.len + new_count,
    );
    @memset(slots.items, null);
    var next_handle: u32 = @intCast(stable.package_slots.items.len + 1);
    for (replacement.repositories.items) |repository| {
        for (repository.handles, 0..) |*handle, index| {
            if (handle.* == 0) {
                handle.* = next_handle;
                next_handle += 1;
            }
            slots.items[handle.* - 1] = .{
                .repository = repository,
                .index = index,
            };
        }
    }
    replacement.package_slots.deinit(replacement.allocator);
    replacement.package_slots = slots;
}

fn buildFields(
    allocator: std.mem.Allocator,
    repository_id: [:0]const u8,
    repository: model.RepositoryModel,
) error{OutOfMemory}![]const PackageFields {
    const fields = try allocator.alloc(PackageFields, repository.packages.len);
    for (repository.packages, fields) |package, *field| {
        const evr = try formatEvr(allocator, package.nevra);
        field.* = .{
            .repository = repository_id.ptr,
            .name = (try allocator.dupeZ(u8, package.nevra.name)).ptr,
            .arch = (try allocator.dupeZ(u8, package.nevra.arch)).ptr,
            .evr = evr.ptr,
            .nevra = (try std.fmt.allocPrintSentinel(
                allocator,
                "{s}-{s}.{s}",
                .{ package.nevra.name, evr, package.nevra.arch },
                0,
            )).ptr,
        };
    }
    return fields;
}

fn formatEvr(
    allocator: std.mem.Allocator,
    nevra: model.Nevra,
) error{OutOfMemory}![:0]u8 {
    const epoch = nevra.epoch orelse if (needsZeroEpoch(nevra.version))
        @as(?u32, 0)
    else
        null;
    return std.fmt.allocPrintSentinel(
        allocator,
        "{s}{s}{s}",
        .{
            if (epoch) |value|
                try std.fmt.allocPrint(allocator, "{d}:", .{value})
            else
                "",
            nevra.version,
            if (nevra.release.len != 0)
                try std.fmt.allocPrint(allocator, "-{s}", .{nevra.release})
            else
                "",
        },
        0,
    );
}

fn needsZeroEpoch(version: []const u8) bool {
    var index: usize = 0;
    while (index < version.len and std.ascii.isDigit(version[index])) : (index += 1) {}
    return index > 0 and index < version.len and version[index] == ':';
}

fn nativeArchitecture() error{SystemResources}![]const u8 {
    var info: std.posix.utsname = undefined;
    if (std.c.uname(&info) != 0) return error.SystemResources;
    return std.mem.sliceTo(&info.machine, 0);
}

fn createWithInstalled(
    allocator: std.mem.Allocator,
    cache_dir: ?[]const u8,
    root_dir: ?[]const u8,
    requested_architecture: []const u8,
    source: installed_repository.Source,
    include_installed: bool,
) (error{OutOfMemory} || installed_repository.LoadError)!*Context {
    const context = try create(
        allocator,
        cache_dir,
        root_dir,
        requested_architecture,
    );
    if (include_installed) {
        loadInstalled(context, source) catch |err| {
            destroy(context);
            return err;
        };
    }
    return context;
}

fn TDNFPackageContextCreate(
    cache_dir: ?[*:0]const u8,
    root_dir: ?[*:0]const u8,
    raw_architecture: ?[*:0]const u8,
    rpm_config: ?*const anyopaque,
    include_installed: c_int,
    output: ?*?*Context,
) callconv(.c) u32 {
    const slot = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    slot.* = null;
    const arch = if (raw_architecture) |value|
        std.mem.span(value)
    else
        nativeArchitecture() catch return abi.ERROR_TDNF_SOLV_IO;
    const context = createWithInstalled(
        std.heap.c_allocator,
        if (cache_dir) |value| std.mem.span(value) else null,
        if (root_dir) |value| std.mem.span(value) else null,
        arch,
        if (rpm_config) |config|
            .{ .config = config }
        else
            .{ .root_dir = root_dir },
        include_installed != 0,
    ) catch |err| return switch (err) {
        error.OutOfMemory => abi.ERROR_TDNF_OUT_OF_MEMORY,
        error.InvalidRpmHeader => abi.ERROR_TDNF_RPM_HEADER_CONVERT_FAILED,
        error.RpmDbOpenFailed => abi.ERROR_TDNF_RPMTS_OPENDB_FAILED,
        error.RpmDbReadFailed => abi.ERROR_TDNF_SOLV_IO,
    };
    slot.* = context;
    return 0;
}

fn TDNFPackageContextFree(context: ?*Context) callconv(.c) void {
    if (context) |value| destroy(value);
}

fn TDNFPackageContextCacheDir(
    context: ?*const Context,
) callconv(.c) ?[*:0]const u8 {
    return cacheDir(context orelse return null);
}

fn TDNFPackageContextRootDir(
    context: ?*const Context,
) callconv(.c) ?[*:0]const u8 {
    return rootDir(context orelse return null);
}

fn TDNFPackageContextInitCommandLine(
    context: ?*Context,
    output: ?*?*Repository,
) callconv(.c) u32 {
    const slot = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    slot.* = null;
    const repository = createCommandLine(context orelse
        return abi.ERROR_TDNF_INVALID_PARAMETER) catch
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    slot.* = repository;
    return 0;
}

fn TDNFPackageContextResetCommandLine(
    context: ?*Context,
    output: ?*?*Repository,
) callconv(.c) u32 {
    const slot = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    slot.* = null;
    const repository = resetCommandLine(context orelse
        return abi.ERROR_TDNF_INVALID_PARAMETER) catch
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    slot.* = repository;
    return 0;
}

fn TDNFPackageContextAddRpm(
    context: ?*Context,
    repository: ?*Repository,
    raw_path: ?[*:0]const u8,
    package_id: ?*u32,
) callconv(.c) u32 {
    if (package_id) |value| value.* = 0;
    const path = raw_path orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const id = addCommandLineRpm(
        context orelse return abi.ERROR_TDNF_INVALID_PARAMETER,
        repository orelse return abi.ERROR_TDNF_INVALID_PARAMETER,
        std.mem.span(path),
    ) catch |err| return switch (err) {
        error.OutOfMemory => abi.ERROR_TDNF_OUT_OF_MEMORY,
        error.RpmFileOpenFailed => abi.ERROR_TDNF_FILE_NOT_FOUND,
        error.InvalidRpmHeader => abi.ERROR_TDNF_INVALID_REPO_FILE,
    };
    if (package_id) |value| value.* = id;
    return 0;
}

fn TDNFPackageContextGetFields(
    context: ?*const Context,
    package_id: i32,
    output: ?*extern struct {
        name: ?[*:0]const u8,
        arch: ?[*:0]const u8,
        evr: ?[*:0]const u8,
        repository: ?[*:0]const u8,
    },
) callconv(.c) u32 {
    const destination = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const fields = packageFields(
        context orelse return abi.ERROR_TDNF_INVALID_PARAMETER,
        package_id,
    ) orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    destination.* = .{
        .name = fields.name,
        .arch = fields.arch,
        .evr = fields.evr,
        .repository = fields.repository,
    };
    return 0;
}

fn TDNFPackageContextGetRepoNevra(
    context: ?*const Context,
    package_id: i32,
    repository: ?*?[*:0]const u8,
    nevra: ?*?[*:0]u8,
) callconv(.c) u32 {
    const repository_slot = repository orelse
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    const nevra_slot = nevra orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    repository_slot.* = null;
    nevra_slot.* = null;
    const fields = packageFields(
        context orelse return abi.ERROR_TDNF_INVALID_PARAMETER,
        package_id,
    ) orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    var copy: ?[*:0]u8 = null;
    const result = TDNFAllocateString(fields.nevra, &copy);
    if (result != 0) return result;
    repository_slot.* = fields.repository;
    nevra_slot.* = copy;
    return 0;
}

fn TDNFPackageContextGetInstalledPkgIds(
    context: ?*const Context,
    output: ?*IdList,
) callconv(.c) u32 {
    const value = context orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const list = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const repository = value.impl.installed orelse return 0;
    for (repository.handles) |handle| {
        const result = TDNFIdListPush(
            list,
            @intCast(handle),
        );
        if (result != 0) return result;
    }
    return 0;
}

fn TDNFPackageContextGetAllPkgIds(
    context: ?*const Context,
    output: ?*IdList,
) callconv(.c) u32 {
    const value = context orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const list = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    if (value.impl.installed) |repository| {
        for (repository.handles) |handle| {
            const result = TDNFIdListPush(list, @intCast(handle));
            if (result != 0) return result;
        }
    }
    for (value.impl.repositories.items) |repository| {
        if (repository.kind != .available) continue;
        for (repository.handles) |handle| {
            const result = TDNFIdListPush(list, @intCast(handle));
            if (result != 0) return result;
        }
    }
    if (value.impl.command_line) |repository| {
        for (repository.handles) |handle| {
            const result = TDNFIdListPush(list, @intCast(handle));
            if (result != 0) return result;
        }
    }
    return 0;
}

fn TDNFPackageContextGetRepoDataList(
    context: ?*const Context,
    output: ?*?[*]?*anyopaque,
    count: ?*u32,
) callconv(.c) u32 {
    const value = context orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const output_slot = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const count_slot = count orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    output_slot.* = null;
    count_slot.* = 0;
    var owner_count: usize = 0;
    for (value.impl.repositories.items) |repository| {
        if (repository.owner != null) owner_count += 1;
    }
    if (owner_count == 0) return 0;
    var raw: ?*anyopaque = null;
    const result = TDNFAllocateMemory(
        owner_count,
        @sizeOf(?*anyopaque),
        &raw,
    );
    if (result != 0) return result;
    const owners: [*]?*anyopaque = @ptrCast(@alignCast(raw.?));
    var index: usize = 0;
    for (value.impl.repositories.items) |repository| {
        const owner = repository.owner orelse continue;
        owners[index] = owner;
        index += 1;
    }
    output_slot.* = owners;
    count_slot.* = @intCast(owner_count);
    return 0;
}

pub export fn SolvCreateSack(output: ?*?*Context) u32 {
    return TDNFPackageContextCreate(null, null, null, null, 0, output);
}

pub export fn SolvFreeSack(context: ?*Context) void {
    TDNFPackageContextFree(context);
}

pub export fn SolvInitSack(
    output: ?*?*Context,
    cache_dir: ?[*:0]const u8,
    root_dir: ?[*:0]const u8,
    raw_architecture: ?[*:0]const u8,
) u32 {
    return TDNFPackageContextCreate(
        cache_dir,
        root_dir,
        raw_architecture,
        null,
        0,
        output,
    );
}

pub export fn SolvGetPkgNameFromId(
    context: ?*const Context,
    package_id: u32,
    output: ?*?[*:0]u8,
) u32 {
    const slot = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    slot.* = null;
    const fields = packageFields(
        context orelse return abi.ERROR_TDNF_INVALID_PARAMETER,
        @intCast(package_id),
    ) orelse return abi.ERROR_TDNF_NO_DATA;
    return TDNFAllocateString(fields.name, slot);
}

fn allocateSlice(value: []const u8, output: *?[*:0]u8) u32 {
    const copy = std.heap.c_allocator.dupeZ(u8, value) catch
        return abi.ERROR_TDNF_OUT_OF_MEMORY;
    defer std.heap.c_allocator.free(copy);
    return TDNFAllocateString(copy, output);
}

pub export fn SolvSplitEvr(
    context: ?*const Context,
    raw_evr: ?[*:0]const u8,
    epoch_output: ?*?[*:0]u8,
    version_output: ?*?[*:0]u8,
    release_output: ?*?[*:0]u8,
) u32 {
    _ = context orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const epoch_slot = epoch_output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const version_slot = version_output orelse
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    const release_slot = release_output orelse
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    epoch_slot.* = null;
    version_slot.* = null;
    release_slot.* = null;
    const evr = std.mem.span(raw_evr orelse
        return abi.ERROR_TDNF_INVALID_PARAMETER);
    if (evr.len == 0) return abi.ERROR_TDNF_INVALID_PARAMETER;

    var version_start: usize = 0;
    if (std.mem.indexOfScalar(u8, evr, ':')) |colon| {
        if (colon != 0) {
            const result = allocateSlice(evr[0..colon], epoch_slot);
            if (result != 0) return result;
        }
        version_start = colon + 1;
    }
    var version_end = evr.len;
    if (std.mem.lastIndexOfScalar(u8, evr, '-')) |hyphen| {
        if (hyphen > version_start) {
            version_end = hyphen;
            if (hyphen + 1 < evr.len) {
                const result = allocateSlice(evr[hyphen + 1 ..], release_slot);
                if (result != 0) {
                    TDNFFreeMemory(epoch_slot.*);
                    epoch_slot.* = null;
                    return result;
                }
            }
        }
    }
    if (version_end > version_start) {
        const result = allocateSlice(evr[version_start..version_end], version_slot);
        if (result != 0) {
            TDNFFreeMemory(epoch_slot.*);
            TDNFFreeMemory(release_slot.*);
            epoch_slot.* = null;
            release_slot.* = null;
            return result;
        }
    }
    return 0;
}

pub export fn SolvGetNevraFromId(
    context: ?*const Context,
    package_id: u32,
    epoch_output: ?*u32,
    name_output: ?*?[*:0]u8,
    version_output: ?*?[*:0]u8,
    release_output: ?*?[*:0]u8,
    arch_output: ?*?[*:0]u8,
    evr_output: ?*?[*:0]u8,
) u32 {
    const value = context orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const epoch_slot = epoch_output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const name_slot = name_output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const version_slot = version_output orelse
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    const release_slot = release_output orelse
        return abi.ERROR_TDNF_INVALID_PARAMETER;
    const arch_slot = arch_output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    epoch_slot.* = 0;
    name_slot.* = null;
    version_slot.* = null;
    release_slot.* = null;
    arch_slot.* = null;
    if (evr_output) |slot| slot.* = null;
    const fields = packageFields(value, @intCast(package_id)) orelse
        return abi.ERROR_TDNF_NO_DATA;

    var epoch: ?[*:0]u8 = null;
    var result = TDNFAllocateString(fields.name, name_slot);
    if (result == 0) result = TDNFAllocateString(fields.arch, arch_slot);
    if (result == 0) result = SolvSplitEvr(
        value,
        fields.evr,
        &epoch,
        version_slot,
        release_slot,
    );
    if (result == 0 and evr_output != null) {
        result = TDNFAllocateString(fields.evr, evr_output.?);
    }
    if (result == 0) {
        if (epoch) |raw_epoch| {
            epoch_slot.* = std.fmt.parseUnsigned(
                u32,
                std.mem.span(raw_epoch),
                10,
            ) catch 0;
        }
    }
    TDNFFreeMemory(epoch);
    if (result != 0) {
        TDNFFreeMemory(name_slot.*);
        TDNFFreeMemory(version_slot.*);
        TDNFFreeMemory(release_slot.*);
        TDNFFreeMemory(arch_slot.*);
        name_slot.* = null;
        version_slot.* = null;
        release_slot.* = null;
        arch_slot.* = null;
        if (evr_output) |slot| {
            TDNFFreeMemory(slot.*);
            slot.* = null;
        }
    }
    return result;
}

pub export fn SolvGetRepoDataList(
    context: ?*const Context,
    output: ?*?[*]?*anyopaque,
    count: ?*u32,
) u32 {
    return TDNFPackageContextGetRepoDataList(context, output, count);
}

pub export fn TDNFPkgHandleGetFields(
    context: ?*const Context,
    package_id: i32,
    output: ?*extern struct {
        name: ?[*:0]const u8,
        arch: ?[*:0]const u8,
        evr: ?[*:0]const u8,
        repository: ?[*:0]const u8,
    },
) u32 {
    const destination = output orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    const fields = packageFields(
        context orelse return abi.ERROR_TDNF_INVALID_PARAMETER,
        package_id,
    ) orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    destination.* = .{
        .name = fields.name,
        .arch = fields.arch,
        .evr = fields.evr,
        .repository = fields.repository,
    };
    return 0;
}

pub export fn TDNFPkgHandleGetRepoNevra(
    context: ?*const Context,
    package_id: i32,
    repository: ?*?[*:0]const u8,
    nevra: ?*?[*:0]u8,
) u32 {
    return TDNFPackageContextGetRepoNevra(
        context,
        package_id,
        repository,
        nevra,
    );
}

pub export fn TDNFPoolGetPkgIds(
    context: ?*const Context,
    output: ?*IdList,
) u32 {
    return TDNFPackageContextGetAllPkgIds(context, output);
}

pub export fn TDNFInstalledGetPkgIds(
    context: ?*const Context,
    output: ?*IdList,
) u32 {
    return TDNFPackageContextGetInstalledPkgIds(context, output);
}

pub export fn SolvSackReadInstalledRpms(
    context: ?*Context,
    cache_file: ?[*:0]const u8,
    rpm_config: ?*const anyopaque,
) u32 {
    _ = cache_file;
    const value = context orelse return abi.ERROR_TDNF_INVALID_PARAMETER;
    loadInstalled(
        value,
        if (rpm_config) |config|
            .{ .config = config }
        else
            .{ .root_dir = rootDir(value) },
    ) catch |err| return switch (err) {
        error.OutOfMemory => abi.ERROR_TDNF_OUT_OF_MEMORY,
        error.InvalidRpmHeader => abi.ERROR_TDNF_RPM_HEADER_CONVERT_FAILED,
        error.RpmDbOpenFailed => abi.ERROR_TDNF_RPMTS_OPENDB_FAILED,
        error.RpmDbReadFailed => abi.ERROR_TDNF_SOLV_IO,
    };
    return 0;
}

fn unsupported() u32 {
    return abi.ERROR_TDNF_CALL_NOT_SUPPORTED;
}

pub export fn SolvCreatePool(output: ?*?*anyopaque) u32 {
    if (output) |slot| slot.* = null;
    return unsupported();
}

pub export fn SolvReadRpmsFromDirectory(
    repository: ?*anyopaque,
    directory: ?[*:0]const u8,
) u32 {
    _ = repository;
    _ = directory;
    return unsupported();
}

pub export fn SolvReadInstalledRpms(
    repository: ?*anyopaque,
    cache_file: ?[*:0]const u8,
    rpm_config: ?*const anyopaque,
) u32 {
    _ = repository;
    _ = cache_file;
    _ = rpm_config;
    return unsupported();
}

pub export fn SolvReadInstalledRpmsNative(
    repository: ?*anyopaque,
    root_dir: ?[*:0]const u8,
    rpm_config: ?*const anyopaque,
    flags: c_int,
) u32 {
    _ = repository;
    _ = root_dir;
    _ = rpm_config;
    _ = flags;
    return unsupported();
}

pub export fn SolvAddRpmNative(
    repository: ?*anyopaque,
    path: ?[*:0]const u8,
    flags: c_int,
    package_id: ?*i32,
) u32 {
    _ = repository;
    _ = path;
    _ = flags;
    if (package_id) |slot| slot.* = 0;
    return unsupported();
}

pub export fn SolvGetMetaDataCachePath(
    repository_info: ?*anyopaque,
    output: ?*?[*:0]u8,
) u32 {
    _ = repository_info;
    if (output) |slot| slot.* = null;
    return unsupported();
}

pub export fn SolvAddSolvMetaData(
    repository_info: ?*anyopaque,
    path: ?[*:0]const u8,
) u32 {
    _ = repository_info;
    _ = path;
    return unsupported();
}

pub export fn SolvCreateMetaDataCache(
    context: ?*Context,
    repository_info: ?*anyopaque,
) u32 {
    _ = context;
    _ = repository_info;
    return unsupported();
}

pub export fn SolvUseMetaDataCache(
    context: ?*Context,
    repository_info: ?*anyopaque,
    use_cache: ?*c_int,
) u32 {
    _ = context;
    _ = repository_info;
    if (use_cache) |slot| slot.* = 0;
    return unsupported();
}

pub export fn TDNFRepoMdNativeLastError() [*:0]const u8 {
    return "libsolv compatibility entry point is not supported";
}

pub export fn TDNFRepoMdNativeLoadSolvRepo(
    repository: ?*anyopaque,
    repomd: ?[*:0]const u8,
    primary: ?[*:0]const u8,
    filelists: ?[*:0]const u8,
    updateinfo: ?[*:0]const u8,
    other: ?[*:0]const u8,
) u32 {
    _ = repository;
    _ = repomd;
    _ = primary;
    _ = filelists;
    _ = updateinfo;
    _ = other;
    return unsupported();
}

pub export fn TDNFRepoMdNativeLoadInstalledSolvRepo(
    repository: ?*anyopaque,
    root_dir: ?[*:0]const u8,
    flags: c_int,
) u32 {
    _ = repository;
    _ = root_dir;
    _ = flags;
    return unsupported();
}

pub export fn TDNFRepoMdNativeLoadInstalledSolvRepoConfig(
    repository: ?*anyopaque,
    rpm_config: ?*const anyopaque,
    flags: c_int,
) u32 {
    _ = repository;
    _ = rpm_config;
    _ = flags;
    return unsupported();
}

pub export fn TDNFRepoMdNativeAddRpm(
    repository: ?*anyopaque,
    path: ?[*:0]const u8,
    flags: c_int,
    package_id: ?*u32,
) u32 {
    _ = repository;
    _ = path;
    _ = flags;
    if (package_id) |slot| slot.* = 0;
    return unsupported();
}

comptime {
    for (.{
        .{ &TDNFPackageContextCreate, "TDNFPackageContextCreate" },
        .{ &TDNFPackageContextFree, "TDNFPackageContextFree" },
        .{ &TDNFPackageContextCacheDir, "TDNFPackageContextCacheDir" },
        .{ &TDNFPackageContextRootDir, "TDNFPackageContextRootDir" },
        .{ &TDNFPackageContextInitCommandLine, "TDNFPackageContextInitCommandLine" },
        .{ &TDNFPackageContextResetCommandLine, "TDNFPackageContextResetCommandLine" },
        .{ &TDNFPackageContextAddRpm, "TDNFPackageContextAddRpm" },
        .{ &TDNFPackageContextGetFields, "TDNFPackageContextGetFields" },
        .{ &TDNFPackageContextGetRepoNevra, "TDNFPackageContextGetRepoNevra" },
        .{ &TDNFPackageContextGetInstalledPkgIds, "TDNFPackageContextGetInstalledPkgIds" },
        .{ &TDNFPackageContextGetAllPkgIds, "TDNFPackageContextGetAllPkgIds" },
        .{ &TDNFPackageContextGetRepoDataList, "TDNFPackageContextGetRepoDataList" },
    }) |item| {
        @export(item[0], .{ .name = item[1], .visibility = .hidden });
    }
}

fn appendTestRepository(
    context: *Context,
    kind: RepositoryKind,
    id_value: []const u8,
    package: model.Package,
) !*Repository {
    return appendTestRepositoryPackages(
        context,
        kind,
        id_value,
        &.{package},
    );
}

fn appendTestRepositoryPackages(
    context: *Context,
    kind: RepositoryKind,
    id_value: []const u8,
    package_values: []const model.Package,
) !*Repository {
    return appendTestRepositoryPackagesWithStates(
        context,
        kind,
        id_value,
        package_values,
        &.{},
    );
}

fn appendTestRepositoryPackagesWithStates(
    context: *Context,
    kind: RepositoryKind,
    id_value: []const u8,
    package_values: []const model.Package,
    installed_state_values: []const installed_repository.InstalledState,
) !*Repository {
    var arena_state = std.heap.ArenaAllocator.init(context.impl.allocator);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();
    const packages = try arena.dupe(model.Package, package_values);
    const installed_states = try arena.dupe(
        installed_repository.InstalledState,
        installed_state_values,
    );
    const repository_model = model.RepositoryModel{ .packages = packages };
    const id = try arena.dupeZ(u8, id_value);
    const fields = try buildFields(arena, id, repository_model);
    const repository = try context.impl.allocator.create(Repository);
    errdefer context.impl.allocator.destroy(repository);
    repository.* = .{
        .arena_state = arena_state,
        .id = id,
        .kind = kind,
        .owner = null,
        .priority = 0,
        .model = repository_model,
        .installed_states = installed_states,
        .fields = fields,
        .handles = &.{},
    };
    try replaceRepository(context, repository);
    return repository;
}

fn testPackage(name: []const u8) model.Package {
    return .{
        .pkg_id = "00",
        .nevra = .{
            .name = name,
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        },
        .checksum = .{ .kind = "sha256", .value = "00", .is_pkgid = true },
        .location = .{},
    };
}

test "package handles keep installed available and command-line order" {
    const context = try create(std.testing.allocator, null, null, "x86_64");
    defer destroy(context);
    _ = try appendTestRepository(
        context,
        .installed,
        "@System",
        testPackage("installed"),
    );
    _ = try appendTestRepository(
        context,
        .available,
        "available",
        testPackage("available"),
    );
    _ = try appendTestRepository(
        context,
        .command_line,
        "@cmdline",
        testPackage("command-line"),
    );

    try std.testing.expectEqualStrings(
        "installed",
        packageModel(context, 1).?.nevra.name,
    );
    try std.testing.expectEqualStrings(
        "available",
        packageModel(context, 2).?.nevra.name,
    );
    try std.testing.expectEqualStrings(
        "command-line",
        packageModel(context, 3).?.nevra.name,
    );
    try std.testing.expectEqualStrings("x86_64", std.mem.span(architecture(context)));
}

test "context swap replaces repository lifetime atomically" {
    const live = try create(std.testing.allocator, "cache", "root", "x86_64");
    defer destroy(live);
    const replacement = try create(
        std.testing.allocator,
        "cache",
        "root",
        "x86_64",
    );
    defer destroy(replacement);
    _ = try appendTestRepository(
        live,
        .available,
        "repo",
        testPackage("before"),
    );
    _ = try appendTestRepository(
        replacement,
        .available,
        "repo",
        testPackage("after"),
    );
    const prior_identity = identity(live);

    try swap(live, replacement);

    try std.testing.expect(prior_identity != identity(live));
    try std.testing.expect(packageModel(live, 1) == null);
    try std.testing.expectEqualStrings(
        "after",
        packageModel(live, 2).?.nevra.name,
    );
    try std.testing.expectEqualStrings(
        "before",
        packageModel(replacement, 1).?.nevra.name,
    );
}

test "command-line rpm handles append and reset" {
    const testing = std.testing;
    const context = try create(testing.allocator, null, null, "x86_64");
    defer destroy(context);
    _ = try appendTestRepository(
        context,
        .available,
        "available",
        testPackage("available"),
    );
    const command_line = try createCommandLine(context);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const bytes = try rpmpkg.makeMinimalRpmBytesForTest(
        testing.allocator,
        "local",
        "1",
        "1",
        "x86_64",
    );
    defer testing.allocator.free(bytes);
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "local.rpm",
        .data = bytes,
    });
    const path = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/local.rpm",
        .{&tmp.sub_path},
        0,
    );
    defer testing.allocator.free(path);

    const id = try addCommandLineRpm(context, command_line, path);
    try testing.expectEqual(@as(u32, 2), id);
    try testing.expectEqualStrings("local", packageModel(context, 2).?.nevra.name);
    _ = try resetCommandLine(context);
    try testing.expect(packageModel(context, 2) == null);
    try testing.expectEqual(@as(usize, 0), command_line.cmdline_paths.items.len);
}

test "repository replacement never retargets stable package handles" {
    const testing = std.testing;
    const context = try create(testing.allocator, null, null, "x86_64");
    defer destroy(context);
    const repo_a = try appendTestRepository(
        context,
        .available,
        "repo-a",
        testPackage("a-one"),
    );
    const repo_b = try appendTestRepository(
        context,
        .available,
        "repo-b",
        testPackage("b-one"),
    );
    const command_line = try createCommandLine(context);
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const bytes = try rpmpkg.makeMinimalRpmBytesForTest(
        testing.allocator,
        "local",
        "1",
        "1",
        "x86_64",
    );
    defer testing.allocator.free(bytes);
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "local.rpm",
        .data = bytes,
    });
    const path = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/local.rpm",
        .{&tmp.sub_path},
        0,
    );
    defer testing.allocator.free(path);
    const cmdline_id = try addCommandLineRpm(context, command_line, path);
    const repo_a_id = packageIdFor(repo_a, 0);
    const repo_b_id = packageIdFor(repo_b, 0);

    const grown_a = try appendTestRepositoryPackages(
        context,
        .available,
        "repo-a",
        &.{ testPackage("a-one"), testPackage("a-two") },
    );
    const grown_id = packageIdFor(grown_a, 1);
    try testing.expectEqual(repo_b_id, packageIdFor(repo_b, 0));
    try testing.expectEqualStrings(
        "b-one",
        packageModel(context, @intCast(repo_b_id)).?.nevra.name,
    );
    try testing.expectEqualStrings(
        "local",
        packageModel(context, @intCast(cmdline_id)).?.nevra.name,
    );

    const shrunk_a = try appendTestRepository(
        context,
        .available,
        "repo-a",
        testPackage("a-two"),
    );
    try testing.expect(packageModel(context, @intCast(repo_a_id)) == null);
    try testing.expectEqual(grown_id, packageIdFor(shrunk_a, 0));
    try testing.expectEqualStrings(
        "b-one",
        packageModel(context, @intCast(repo_b_id)).?.nevra.name,
    );
    try testing.expectEqualStrings(
        "local",
        packageModel(context, @intCast(cmdline_id)).?.nevra.name,
    );

    const regrown_a = try appendTestRepositoryPackages(
        context,
        .available,
        "repo-a",
        &.{ testPackage("a-two"), testPackage("a-three") },
    );
    try testing.expect(packageIdFor(regrown_a, 1) > grown_id);
    try testing.expect(packageModel(context, @intCast(repo_a_id)) == null);
}

test "installed duplicate refresh retains handles by rpmdb hnum" {
    const testing = std.testing;
    const context = try create(testing.allocator, null, null, "x86_64");
    defer destroy(context);
    const duplicate = testPackage("duplicate-installed");
    const original = try appendTestRepositoryPackagesWithStates(
        context,
        .installed,
        "@System",
        &.{ duplicate, duplicate },
        &.{
            .{ .rpmdb_hnum = 41 },
            .{ .rpmdb_hnum = 73 },
        },
    );
    const removed_handle = packageIdFor(original, 0);
    const survivor_handle = packageIdFor(original, 1);

    const refreshed = try appendTestRepositoryPackagesWithStates(
        context,
        .installed,
        "@System",
        &.{duplicate},
        &.{.{ .rpmdb_hnum = 73 }},
    );

    try testing.expect(packageModel(
        context,
        @intCast(removed_handle),
    ) == null);
    try testing.expectEqual(survivor_handle, packageIdFor(refreshed, 0));
    try testing.expectEqual(
        @as(u32, 73),
        packageInstalledState(context, @intCast(survivor_handle)).?.rpmdb_hnum,
    );
}

fn testRootPath(
    tmp: *const std.testing.TmpDir,
    buffer: *[std.Io.Dir.max_path_bytes]u8,
) [:0]const u8 {
    return std.fmt.bufPrintZ(
        buffer,
        ".zig-cache/tmp/{s}",
        .{&tmp.sub_path},
    ) catch @panic("test root path too long");
}

fn contextCreationAllocationFailureCase(
    allocator: std.mem.Allocator,
    root: [*:0]const u8,
) !void {
    const context = try createWithInstalled(
        allocator,
        "cache",
        std.mem.span(root),
        "x86_64",
        .{ .root_dir = root },
        true,
    );
    destroy(context);
}

test "context creation releases every allocation on installed load failures" {
    const testing = std.testing;
    var malformed = testing.tmpDir(.{});
    defer malformed.cleanup();
    try malformed.dir.createDirPath(testing.io, "var/lib/rpm");
    try malformed.dir.writeFile(testing.io, .{
        .sub_path = "var/lib/rpm/rpmdb.sqlite",
        .data = "not a sqlite database",
    });
    var malformed_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const malformed_root = testRootPath(&malformed, &malformed_buffer);
    try testing.expectError(
        error.RpmDbOpenFailed,
        createWithInstalled(
            testing.allocator,
            null,
            malformed_root,
            "x86_64",
            .{ .root_dir = malformed_root },
            true,
        ),
    );

    const package_blob = try rpmpkg.makeMinimalHeaderForTest(
        testing.allocator,
        "allocation-loaded-package",
        "1.0",
        "1",
        "noarch",
    );
    defer testing.allocator.free(package_blob);
    var populated = try installed_repository.TestFixture.create(&.{
        .{ .hnum = 19, .blob = package_blob },
    });
    defer populated.cleanup();
    var populated_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const populated_root = populated.rootPath(&populated_buffer);
    try testing.checkAllAllocationFailures(
        testing.allocator,
        contextCreationAllocationFailureCase,
        .{populated_root},
    );
}

test "legacy installed loading honors the context install root" {
    const testing = std.testing;
    const sentinel_name = "tdnf-scratch-root-sentinel-41";
    const package_blob = try rpmpkg.makeMinimalHeaderForTest(
        testing.allocator,
        sentinel_name,
        "1.0",
        "1",
        "noarch",
    );
    defer testing.allocator.free(package_blob);
    var scratch = try installed_repository.TestFixture.create(&.{
        .{ .hnum = 91, .blob = package_blob },
    });
    defer scratch.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const scratch_root = scratch.rootPath(&root_buffer);
    const context = try create(
        testing.allocator,
        null,
        scratch_root,
        "x86_64",
    );
    defer destroy(context);

    try testing.expectEqual(
        @as(u32, 0),
        SolvSackReadInstalledRpms(context, null, null),
    );
    try testing.expect(context.impl.installed != null);
    try testing.expectEqual(@as(usize, 1), packageCount(context));
    try testing.expectEqualStrings(
        sentinel_name,
        packageModel(context, 1).?.nevra.name,
    );
    try testing.expectEqual(
        @as(u32, 91),
        packageInstalledState(context, 1).?.rpmdb_hnum,
    );
    try testing.expectEqualStrings(
        scratch_root,
        std.mem.span(rootDir(context).?),
    );
}
