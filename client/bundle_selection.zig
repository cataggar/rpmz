//! Deriving what a bundle must contain from a canonical plan.
//!
//! This is the part of the export that has nothing to do with the network:
//! given a plan, which files must the bundle hold, where does each one go, and
//! which repository does it belong to. Keeping it separate from the fetch loop
//! means the two rules that are easiest to get quietly wrong -- D1 and D4 --
//! can be tested against a plan alone, with no server, no cache, and no
//! install root.
//!
//! **D1: only available action targets are fetched.** Installed packages are
//! *required* to carry no source and a non-null rpmdb header number, so the
//! prior rows of an upgrade have no fetch coordinates by construction. They
//! remain in `plan.json` as a replay precondition; they are not files. An
//! exporter that tried to bundle them would either invent coordinates or
//! silently skip them, and both are wrong in a way a consumer could not see.
//!
//! **D4: command-line packages are rejected.** A command-line RPM has a null
//! `location` by design, so it has no reproducible coordinates. Exporting one
//! would require inventing a synthetic repository, producing a bundle that
//! claims to be reproducible and is not. It is refused with a distinct error.

const std = @import("std");
const bundle_paths = @import("bundle_paths");
const transaction_bundle = @import("transaction_bundle");
const transaction_plan = @import("transaction_plan");

pub const SelectError = error{
    /// The plan selects a command-line package, which has no reproducible
    /// fetch coordinates (D4).
    CommandLinePackageUnsupported,
    /// An action names a target the plan does not contain, or a package names
    /// a repository the plan does not declare.
    PlanInconsistent,
    /// A repository id or a declared href cannot be mapped to a safe bundle
    /// path.
    UnmappablePath,
    /// The plan reports solver problems, so there is nothing to export.
    PlanHasProblems,
    /// A repository in the plan carries no repomd identity, so its metadata
    /// cannot be pinned.
    RepositoryNotPinnable,
    OutOfMemory,
};

/// One RPM the bundle must contain.
pub const PackageItem = struct {
    /// Capture-time package handle used only while materializing native order.
    capture_package_id: []const u8 = "",
    /// The plan's `package-N` reference.
    plan_package_id: []const u8,
    repository_id: []const u8,
    identity: transaction_plan.PackageIdentity,
    checksum: transaction_plan.Checksum,
    size: ?u64,
    /// Declared coordinates, recorded verbatim so a consumer can check the
    /// mapping rather than recompute it.
    href: []const u8,
    xml_base: ?[]const u8,
    /// Where it goes inside the bundle. Derived from `href`'s path component
    /// only.
    path: []const u8,
};

/// One metadata file the bundle must contain.
pub const MetadataItem = struct {
    repository_id: []const u8,
    record_type: []const u8,
    href: []const u8,
    xml_base: ?[]const u8,
    checksum: transaction_plan.Checksum,
    size: ?u64,
    open_checksum: ?transaction_plan.Checksum,
    open_size: ?u64,
    path: []const u8,
};

/// One repository whose metadata must be captured.
pub const RepositoryItem = struct {
    id: []const u8,
    cost: u32,
    priority: i32,
    revision: ?[]const u8,
    snapshot_id: []const u8,
    /// The plan's pin for `repomd.xml`. The root of the metadata trust chain.
    repomd_sha256: []const u8,
    /// Where `repomd.xml` goes inside the bundle.
    repomd_path: []const u8,
};

/// Everything the fetch loop has to do, decided before it starts.
pub const Selection = struct {
    arena: std.heap.ArenaAllocator,
    packages: []PackageItem,
    metadata: []const MetadataItem,
    repositories: []const RepositoryItem,

    pub fn deinit(self: *Selection) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Where `repomd.xml` always lives for a repository, relative to the bundle.
pub const repomd_relative = "repodata/repomd.xml";

/// Decide the complete contents of a bundle from a plan.
///
/// Fails rather than producing a partial answer: a selection that silently
/// omitted a file would produce a bundle that validates and cannot be
/// replayed.
pub fn select(
    allocator: std.mem.Allocator,
    plan: *const transaction_plan.Data,
) SelectError!Selection {
    if (plan.problems.len != 0) return error.PlanHasProblems;

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();

    var packages: std.ArrayList(PackageItem) = .empty;
    var metadata: std.ArrayList(MetadataItem) = .empty;
    var repositories: std.ArrayList(RepositoryItem) = .empty;

    // Which repositories are actually reachable from the selected packages.
    // A declared repository that contributes nothing is still recorded,
    // because its metadata is part of what made the resolve reproducible.
    for (plan.repositories) |repository| {
        if (repository.kind != .available) continue;
        const repomd = repository.repomd orelse return error.RepositoryNotPinnable;
        const snapshot = repository.snapshot orelse return error.RepositoryNotPinnable;
        if (!bundle_paths.isSafeComponent(repository.id)) return error.UnmappablePath;

        const repomd_path = bundle_paths.joinRepoScoped(
            scratch,
            transaction_bundle.repositories_prefix,
            repository.id,
            repomd_relative,
        ) catch |err| return mapPathError(err);

        try repositories.append(scratch, .{
            .id = repository.id,
            .cost = repository.cost,
            .priority = repository.priority,
            .revision = repomd.revision,
            .snapshot_id = snapshot.metadata_sha256,
            .repomd_sha256 = repomd.checksum_sha256,
            .repomd_path = repomd_path,
        });

        for (repomd.records) |record| {
            // A record whose checksum is absent or unusable fails the export.
            // Bundling bytes nobody can verify is exactly what this feature
            // exists to prevent.
            const checksum = record.checksum orelse return error.RepositoryNotPinnable;
            const mapped = bundle_paths.mapHref(scratch, record.location.href) catch |err|
                return mapPathError(err);
            const path = bundle_paths.joinRepoScoped(
                scratch,
                transaction_bundle.repositories_prefix,
                repository.id,
                mapped,
            ) catch |err| return mapPathError(err);
            try metadata.append(scratch, .{
                .repository_id = repository.id,
                .record_type = record.record_type,
                .href = record.location.href,
                .xml_base = record.location.xml_base,
                .checksum = checksum,
                .size = record.size,
                .open_checksum = record.open_checksum,
                .open_size = record.open_size,
                .path = path,
            });
        }
    }

    // D1: action *targets* only. Prior rows are installed packages and carry
    // no coordinates, so they are never candidates.
    for (plan.actions) |action| {
        const package = findPackage(plan.packages, action.target_package_id) orelse
            return error.PlanInconsistent;
        // An erase action's target is an installed package: nothing to fetch.
        if (package.state == .installed) continue;

        const source = package.source orelse return error.PlanInconsistent;
        // D4: a command-line package has no location by design.
        const location = source.location orelse
            return error.CommandLinePackageUnsupported;

        if (findRepositoryKind(plan.repositories, package.repository_id) == null) {
            return error.PlanInconsistent;
        }
        if (!bundle_paths.isSafeComponent(package.repository_id)) return error.UnmappablePath;

        const mapped = bundle_paths.mapHref(scratch, location.href) catch |err|
            return mapPathError(err);
        const path = bundle_paths.joinRepoScoped(
            scratch,
            transaction_bundle.packages_prefix,
            package.repository_id,
            mapped,
        ) catch |err| return mapPathError(err);

        // The same package can be the target of more than one action; it is
        // still one file.
        if (containsPackage(packages.items, package.id)) continue;
        try packages.append(scratch, .{
            .capture_package_id = package.id,
            .plan_package_id = package.id,
            .repository_id = package.repository_id,
            .identity = package.identity,
            .checksum = source.checksum,
            .size = source.size,
            .href = location.href,
            .xml_base = location.xml_base,
            .path = path,
        });
    }

    return .{
        .arena = arena,
        .packages = try packages.toOwnedSlice(scratch),
        .metadata = try metadata.toOwnedSlice(scratch),
        .repositories = try repositories.toOwnedSlice(scratch),
    };
}

fn mapPathError(err: bundle_paths.MapError) SelectError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.UnmappablePath,
    };
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

fn findRepositoryKind(
    repositories: []const transaction_plan.Repository,
    id: []const u8,
) ?transaction_plan.RepositoryKind {
    for (repositories) |repository| {
        if (std.mem.eql(u8, repository.id, id)) return repository.kind;
    }
    return null;
}

fn containsPackage(items: []const PackageItem, id: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item.plan_package_id, id)) return true;
    }
    return false;
}

const testing = std.testing;

const test_sha_a = "1" ** 64;
const test_sha_b = "2" ** 64;
const test_sha_c = "3" ** 64;

const Builder = struct {
    packages: std.ArrayList(transaction_plan.Package) = .empty,
    actions: std.ArrayList(transaction_plan.Action) = .empty,
    repositories: std.ArrayList(transaction_plan.Repository) = .empty,

    fn deinit(self: *Builder) void {
        self.packages.deinit(testing.allocator);
        self.actions.deinit(testing.allocator);
        self.repositories.deinit(testing.allocator);
    }

    fn availableRepository(self: *Builder, id: []const u8) !void {
        try self.repositories.append(testing.allocator, .{
            .cost = 1000,
            .id = id,
            .kind = .available,
            .priority = 50,
            .repomd = .{
                .checksum_sha256 = test_sha_a,
                .records = &.{.{
                    .checksum = .{ .kind = "sha256", .value = test_sha_b },
                    .database_version = null,
                    .location = .{ .href = "repodata/primary.xml.zst", .xml_base = null },
                    .open_checksum = null,
                    .open_size = null,
                    .record_type = "primary",
                    .size = 12,
                    .timestamp = 42,
                }},
                .revision = "rev-1",
                .timestamp = 42,
            },
            .snapshot = .{ .id = "snapshot", .metadata_sha256 = test_sha_b },
        });
    }

    fn installedRepository(self: *Builder) !void {
        try self.repositories.append(testing.allocator, .{
            .cost = 1000,
            .id = "@System",
            .kind = .installed,
            .priority = 50,
            .repomd = null,
            .snapshot = null,
        });
    }

    fn available(
        self: *Builder,
        id: []const u8,
        name: []const u8,
        repository_id: []const u8,
        href: ?[]const u8,
    ) !void {
        try self.packages.append(testing.allocator, .{
            .id = id,
            .identity = .{
                .arch = "noarch",
                .epoch = null,
                .name = name,
                .release = "1",
                .version = "1.0",
            },
            .repository_id = repository_id,
            .rpmdb_hnum = null,
            .state = .available,
            .source = .{
                .checksum = .{ .kind = "sha256", .value = test_sha_c },
                .location = if (href) |value|
                    .{ .href = value, .xml_base = null }
                else
                    null,
                .size = 99,
            },
        });
    }

    fn installed(self: *Builder, id: []const u8, name: []const u8) !void {
        try self.packages.append(testing.allocator, .{
            .id = id,
            .identity = .{
                .arch = "noarch",
                .epoch = null,
                .name = name,
                .release = "1",
                .version = "0.9",
            },
            .repository_id = "@System",
            .rpmdb_hnum = 7,
            .source = null,
            .state = .installed,
        });
    }

    fn action(
        self: *Builder,
        kind: transaction_plan.ActionKind,
        target: []const u8,
        priors: []const []const u8,
    ) !void {
        try self.actions.append(testing.allocator, .{
            .kind = kind,
            .prior_package_ids = priors,
            .reason = .user,
            .requested_by_job_id = null,
            .target_package_id = target,
        });
    }

    fn data(self: *Builder) transaction_plan.Data {
        return .{
            .actions = self.actions.items,
            .environment = undefined,
            .hidden_packages = &.{},
            .jobs = &.{},
            .packages = self.packages.items,
            .problems = &.{},
            .repositories = self.repositories.items,
            .requests = &.{},
            .selected = &.{},
            .skipped = &.{},
        };
    }
};

test "an install selects the target rpm and its repository metadata" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    try builder.installedRepository();
    try builder.available("package-0", "a", "base", "Packages/a-1.0-1.noarch.rpm");
    try builder.action(.install, "package-0", &.{});

    const plan = builder.data();
    var selection = try select(testing.allocator, &plan);
    defer selection.deinit();

    try testing.expectEqual(@as(usize, 1), selection.packages.len);
    try testing.expectEqualStrings(
        "packages/base/Packages/a-1.0-1.noarch.rpm",
        selection.packages[0].path,
    );
    try testing.expectEqualStrings("package-0", selection.packages[0].plan_package_id);

    try testing.expectEqual(@as(usize, 1), selection.repositories.len);
    try testing.expectEqualStrings(
        "repos/base/repodata/repomd.xml",
        selection.repositories[0].repomd_path,
    );
    try testing.expectEqual(@as(usize, 1), selection.metadata.len);
    try testing.expectEqualStrings(
        "repos/base/repodata/primary.xml.zst",
        selection.metadata[0].path,
    );
}

test "an upgrade bundles the new rpm and nothing for the installed prior row" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    try builder.installedRepository();
    try builder.available("package-0", "a", "base", "Packages/a-2.0-1.noarch.rpm");
    try builder.installed("package-1", "a");
    try builder.action(.upgrade, "package-0", &.{"package-1"});

    const plan = builder.data();
    var selection = try select(testing.allocator, &plan);
    defer selection.deinit();

    // D1: exactly one file, the new one. The prior identity stays in the plan
    // as a replay precondition.
    try testing.expectEqual(@as(usize, 1), selection.packages.len);
    try testing.expectEqualStrings("package-0", selection.packages[0].plan_package_id);
}

test "an erase bundles no rpm at all" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    try builder.installedRepository();
    try builder.installed("package-0", "a");
    try builder.action(.erase, "package-0", &.{});

    const plan = builder.data();
    var selection = try select(testing.allocator, &plan);
    defer selection.deinit();
    try testing.expectEqual(@as(usize, 0), selection.packages.len);
    // The repository metadata is still captured: it is what made the resolve
    // reproducible, even when nothing is installed.
    try testing.expectEqual(@as(usize, 1), selection.repositories.len);
}

test "a command-line package is refused rather than given a synthetic repository" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    try builder.available("package-0", "a", "base", null);
    try builder.action(.install, "package-0", &.{});

    const plan = builder.data();
    try testing.expectError(
        error.CommandLinePackageUnsupported,
        select(testing.allocator, &plan),
    );
}

test "a package targeted by two actions is bundled once" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    try builder.installedRepository();
    try builder.available("package-0", "a", "base", "Packages/a.rpm");
    try builder.installed("package-1", "a");
    try builder.action(.upgrade, "package-0", &.{"package-1"});
    try builder.action(.obsolete, "package-0", &.{"package-1"});

    const plan = builder.data();
    var selection = try select(testing.allocator, &plan);
    defer selection.deinit();
    try testing.expectEqual(@as(usize, 1), selection.packages.len);
}

test "a plan with problems exports nothing" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    var plan = builder.data();
    plan.problems = &.{.{
        .id = "problem-0",
        .capability = null,
        .count = 1,
        .job_id = null,
        .kind = .conflict,
        .package_id = null,
        .related_package_id = null,
    }};
    try testing.expectError(error.PlanHasProblems, select(testing.allocator, &plan));
}

test "an action naming an unknown package is a plan inconsistency" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    try builder.action(.install, "package-9", &.{});

    const plan = builder.data();
    try testing.expectError(error.PlanInconsistent, select(testing.allocator, &plan));
}

test "a repository without a repomd pin cannot be bundled" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.repositories.append(testing.allocator, .{
        .cost = 1000,
        .id = "base",
        .kind = .available,
        .priority = 50,
        .repomd = null,
        .snapshot = null,
    });

    const plan = builder.data();
    try testing.expectError(error.RepositoryNotPinnable, select(testing.allocator, &plan));
}

test "a metadata record without a checksum fails the export" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.repositories.append(testing.allocator, .{
        .cost = 1000,
        .id = "base",
        .kind = .available,
        .priority = 50,
        .repomd = .{
            .checksum_sha256 = test_sha_a,
            .records = &.{.{
                .checksum = null,
                .database_version = null,
                .location = .{ .href = "repodata/other", .xml_base = null },
                .open_checksum = null,
                .open_size = null,
                .record_type = "other",
                .size = null,
                .timestamp = null,
            }},
            .revision = null,
            .timestamp = 1,
        },
        .snapshot = .{ .id = "snapshot", .metadata_sha256 = test_sha_b },
    });

    // Silently skipping an unverifiable record would put a file in the bundle
    // that nothing proves, or leave a gap a consumer cannot detect.
    const plan = builder.data();
    try testing.expectError(error.RepositoryNotPinnable, select(testing.allocator, &plan));
}

test "a repository cannot steer a write through an href" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    try builder.installedRepository();
    try builder.available("package-0", "a", "base", "../../../etc/passwd");
    try builder.action(.install, "package-0", &.{});

    const plan = builder.data();
    try testing.expectError(error.UnmappablePath, select(testing.allocator, &plan));
}

test "an absolute package href keeps only its path and stays repo-scoped" {
    var builder: Builder = .{};
    defer builder.deinit();
    try builder.availableRepository("base");
    try builder.installedRepository();
    try builder.available(
        "package-0",
        "a",
        "base",
        "https://mirror.invalid/pub/Packages/a.rpm?token=secret",
    );
    try builder.action(.install, "package-0", &.{});

    const plan = builder.data();
    var selection = try select(testing.allocator, &plan);
    defer selection.deinit();
    try testing.expectEqualStrings(
        "packages/base/pub/Packages/a.rpm",
        selection.packages[0].path,
    );
    // The declared coordinates are still recorded verbatim, so a consumer
    // checks the mapping instead of trusting it.
    try testing.expectEqualStrings(
        "https://mirror.invalid/pub/Packages/a.rpm?token=secret",
        selection.packages[0].href,
    );
}
