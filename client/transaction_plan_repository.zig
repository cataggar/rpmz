const std = @import("std");
const Allocator = std.mem.Allocator;

const repository_metadata = @import("repository_metadata");
const available_loader = repository_metadata.available_loader;
const solver_identity = repository_metadata.solver_identity;
const transaction_plan = @import("transaction_plan");

/// Domain separator for SnapshotIdentity.id. The ID is lower-case hexadecimal
/// SHA-256 over `snapshot_identity_domain ++ "\x00" ++
/// SHA256(exact repodata/repomd.xml bytes)`, prefixed by `snapshot-v1-`.
///
/// repomd.xml binds every advertised sidecar checksum, so this identifies the
/// exact loaded metadata snapshot without retaining a cache path or URL.
pub const snapshot_identity_domain = "tdnf.repository-snapshot/v1";

pub const Input = struct {
    /// Borrowed repository identity. It is copied into Owner on success.
    repository_id: []const u8,
    priority: i32,
    cost: u32,
    /// Input-only cache root. It is never retained or serialized.
    cache_dir: []const u8,
    options: available_loader.CacheOptions = .{},
};

pub const CaptureError = available_loader.LoadError ||
    solver_identity.InitError ||
    transaction_plan.ValidationError ||
    Allocator.Error;

const KeyEntry = struct {
    key: solver_identity.AvailableKey,
    package_index: usize,
};

/// Borrowed transaction-plan facts. The view remains valid until its Owner is
/// destroyed and can be supplied directly to the future capture adapter.
pub const View = struct {
    repository: *const transaction_plan.Repository,
    packages: []const transaction_plan.Package,
};

/// Move-only owner for one independently captured available repository.
pub const Owner = struct {
    allocator: Allocator,
    arena_state: std.heap.ArenaAllocator,
    repository: transaction_plan.Repository,
    packages: []transaction_plan.Package,
    entries: []const KeyEntry,

    pub fn destroy(self: *Owner) void {
        const allocator = self.allocator;
        self.arena_state.deinit();
        allocator.destroy(self);
    }

    pub fn view(self: *const Owner) View {
        return .{
            .repository = &self.repository,
            .packages = self.packages,
        };
    }

    /// Resolve the exact key used by solver_identity.AvailableKey. The index
    /// cannot be ambiguous because capture rejects duplicate normalized keys.
    pub fn findPackage(
        self: *const Owner,
        key: solver_identity.AvailableKey,
    ) ?*const transaction_plan.Package {
        var low: usize = 0;
        var high = self.entries.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            switch (solver_identity.compareAvailableKeys(
                self.entries[middle].key,
                key,
            )) {
                .lt => low = middle + 1,
                .gt => high = middle,
                .eq => return &self.packages[
                    self.entries[middle].package_index
                ],
            }
        }
        return null;
    }
};

/// Load, verify, and deeply own one available cache. The exact repomd bytes
/// are returned by available_loader from the same opened cache root and are
/// hashed before that temporary loader arena is released.
pub fn capture(
    parent_allocator: Allocator,
    input: Input,
) CaptureError!*Owner {
    try transaction_plan.validateRepositoryId(input.repository_id);

    var loaded_arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer loaded_arena.deinit();
    const loaded = try available_loader.loadCacheModelWithRepomd(
        loaded_arena.allocator(),
        input.cache_dir,
        input.options,
    );

    const owner = try parent_allocator.create(Owner);
    owner.* = .{
        .allocator = parent_allocator,
        .arena_state = std.heap.ArenaAllocator.init(parent_allocator),
        .repository = undefined,
        .packages = undefined,
        .entries = undefined,
    };
    errdefer {
        owner.arena_state.deinit();
        parent_allocator.destroy(owner);
    }

    const arena = owner.arena_state.allocator();
    owner.repository = try captureRepository(arena, input, loaded);
    owner.packages = try capturePackages(
        arena,
        owner.repository.id,
        loaded.repository.packages,
    );
    owner.entries = try buildKeyIndex(
        arena,
        owner.repository.id,
        owner.packages,
    );
    try transaction_plan.validateRepositoryPackageFacts(
        owner.repository,
        owner.packages,
    );
    return owner;
}

fn captureRepository(
    allocator: Allocator,
    input: Input,
    loaded: available_loader.CacheModel,
) CaptureError!transaction_plan.Repository {
    if (loaded.record_xml_bases.len != loaded.repository.records.len) {
        return error.InvalidRepoMetadata;
    }

    const repomd_digest = sha256(loaded.repomd_bytes);
    const repomd_hex = lowerHex(repomd_digest);
    const records = try cloneRecords(
        allocator,
        loaded.repository.records,
        loaded.record_xml_bases,
    );

    var timestamp: u64 = 0;
    for (loaded.repository.records) |record| {
        if (record.nHasTimestamp != 0) {
            timestamp = @max(timestamp, record.nTimestamp);
        }
    }

    return .{
        .cost = input.cost,
        .id = try allocator.dupe(u8, input.repository_id),
        .kind = .available,
        .priority = input.priority,
        .repomd = .{
            .checksum_sha256 = try allocator.dupe(u8, &repomd_hex),
            .records = records,
            .revision = try cloneOptionalZ(
                allocator,
                loaded.repository.pszRevision,
            ),
            .timestamp = timestamp,
        },
        .snapshot = .{
            .id = try snapshotId(allocator, repomd_digest),
            .metadata_sha256 = try allocator.dupe(u8, &repomd_hex),
        },
    };
}

fn cloneRecords(
    allocator: Allocator,
    input: anytype,
    xml_bases: []const ?[]const u8,
) CaptureError![]transaction_plan.MetadataRecord {
    const output = try allocator.alloc(transaction_plan.MetadataRecord, input.len);
    for (input, output, xml_bases) |record, *destination, xml_base| {
        destination.* = .{
            .checksum = try cloneOptionalRecordChecksum(
                allocator,
                record.checksum,
            ),
            .database_version = if (record.nHasDatabaseVersion != 0)
                record.nDatabaseVersion
            else
                null,
            .location = .{
                .href = try cloneRequiredZ(
                    allocator,
                    record.pszLocationHref,
                ),
                .xml_base = try cloneOptionalString(allocator, xml_base),
            },
            .open_checksum = try cloneOptionalRecordChecksum(
                allocator,
                record.openChecksum,
            ),
            .open_size = if (record.nHasOpenSize != 0)
                record.nOpenSize
            else
                null,
            .record_type = try cloneRequiredZ(allocator, record.pszType),
            .size = if (record.nHasSize != 0) record.nSize else null,
            .timestamp = if (record.nHasTimestamp != 0)
                record.nTimestamp
            else
                null,
        };
    }
    return output;
}

fn cloneOptionalRecordChecksum(
    allocator: Allocator,
    input: anytype,
) CaptureError!?transaction_plan.Checksum {
    const kind = optionalZ(input.pszType);
    const value = optionalZ(input.pszValue);
    if (kind == null and value == null) return null;
    return .{
        .kind = try allocator.dupe(
            u8,
            kind orelse return error.InvalidRepoMetadata,
        ),
        .value = try allocator.dupe(
            u8,
            value orelse return error.InvalidRepoMetadata,
        ),
    };
}

fn capturePackages(
    allocator: Allocator,
    repository_id: []const u8,
    input: anytype,
) CaptureError![]transaction_plan.Package {
    const output = try allocator.alloc(transaction_plan.Package, input.len);
    for (input, output) |package, *destination| {
        destination.* = .{
            .id = "",
            .identity = .{
                .arch = try allocator.dupe(u8, package.nevra.arch),
                .epoch = package.nevra.epoch,
                .name = try allocator.dupe(u8, package.nevra.name),
                .release = try allocator.dupe(u8, package.nevra.release),
                .version = try allocator.dupe(u8, package.nevra.version),
            },
            .repository_id = repository_id,
            .rpmdb_hnum = null,
            .source = .{
                .checksum = .{
                    .kind = try allocator.dupe(u8, package.checksum.kind),
                    .is_pkgid = package.checksum.is_pkgid,
                    .value = try allocator.dupe(u8, package.checksum.value),
                },
                .location = .{
                    .href = try allocator.dupe(
                        u8,
                        package.location.href,
                    ),
                    .xml_base = try cloneOptionalString(
                        allocator,
                        package.location.xml_base,
                    ),
                },
                .size = package.size.package,
            },
            .state = .available,
        };
    }
    return output;
}

fn buildKeyIndex(
    allocator: Allocator,
    repository_id: []const u8,
    packages: []transaction_plan.Package,
) CaptureError![]const KeyEntry {
    const entries = try allocator.alloc(KeyEntry, packages.len);
    for (packages, entries, 0..) |package, *entry, index| {
        entry.* = .{
            .key = .{
                .repository = repository_id,
                .name = package.identity.name,
                .epoch = package.identity.epoch orelse 0,
                .version = package.identity.version,
                .release = package.identity.release,
                .arch = package.identity.arch,
                .checksum = .{
                    .kind = package.source.?.checksum.kind,
                    .value = package.source.?.checksum.value,
                    .is_pkgid = package.source.?.checksum.is_pkgid,
                },
            },
            .package_index = index,
        };
    }
    std.mem.sort(KeyEntry, entries, {}, keyEntryLessThan);
    if (entries.len > 1) {
        for (entries[1..], entries[0 .. entries.len - 1]) |current, prior| {
            if (solver_identity.compareAvailableKeys(
                prior.key,
                current.key,
            ) == .eq) {
                return error.DuplicatePackageKey;
            }
        }
    }
    for (entries, 0..) |entry, index| {
        packages[entry.package_index].id = try std.fmt.allocPrint(
            allocator,
            "available-{d}",
            .{index},
        );
    }
    return entries;
}

fn keyEntryLessThan(_: void, left: KeyEntry, right: KeyEntry) bool {
    return solver_identity.compareAvailableKeys(left.key, right.key) == .lt;
}

fn cloneRequiredZ(
    allocator: Allocator,
    value: ?[*:0]const u8,
) CaptureError![]const u8 {
    return allocator.dupe(u8, optionalZ(value) orelse
        return error.InvalidRepoMetadata);
}

fn cloneOptionalZ(
    allocator: Allocator,
    value: ?[*:0]const u8,
) Allocator.Error!?[]const u8 {
    return cloneOptionalString(allocator, optionalZ(value));
}

fn optionalZ(value: ?[*:0]const u8) ?[]const u8 {
    const pointer = value orelse return null;
    return std.mem.span(pointer);
}

fn cloneOptionalString(
    allocator: Allocator,
    value: ?[]const u8,
) Allocator.Error!?[]const u8 {
    return if (value) |text| try allocator.dupe(u8, text) else null;
}

fn sha256(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(bytes);
    hasher.final(&digest);
    return digest;
}

fn snapshotId(
    allocator: Allocator,
    repomd_digest: [32]u8,
) Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(snapshot_identity_domain);
    hasher.update("\x00");
    hasher.update(&repomd_digest);
    hasher.final(&digest);
    const hex = lowerHex(digest);
    return std.fmt.allocPrint(allocator, "snapshot-v1-{s}", .{&hex});
}

fn lowerHex(bytes: [32]u8) [64]u8 {
    const alphabet = "0123456789abcdef";
    var output: [64]u8 = undefined;
    for (bytes, 0..) |byte, index| {
        output[index * 2] = alphabet[byte >> 4];
        output[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return output;
}

const primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common" packages="2">
    \\  <package type="rpm">
    \\    <name>alpha</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="7" ver="1.2" rel="3"/>
    \\    <checksum type="SHA256" pkgid="YES">AbCdEf01</checksum>
    \\    <size package="123"/>
    \\    <location xml:base="../pool" href="packages/alpha-1.2-3.x86_64.rpm"/>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>beta</name>
    \\    <arch>noarch</arch>
    \\    <version ver="4.5" rel="6"/>
    \\    <checksum type="sha512" pkgid="YES">BETA-CHECKSUM</checksum>
    \\    <location href="packages/beta-4.5-6.noarch.rpm"/>
    \\  </package>
    \\</metadata>
;

const filelists_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<filelists xmlns="http://linux.duke.edu/metadata/filelists" packages="2">
    \\  <package pkgid="AbCdEf01" name="alpha" arch="x86_64">
    \\    <version epoch="7" ver="1.2" rel="3"/>
    \\    <file>/usr/bin/alpha</file>
    \\  </package>
    \\  <package pkgid="BETA-CHECKSUM" name="beta" arch="noarch">
    \\    <version ver="4.5" rel="6"/>
    \\    <file>/usr/share/beta</file>
    \\  </package>
    \\</filelists>
;

const duplicate_primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common" packages="2">
    \\  <package type="rpm">
    \\    <name>duplicate</name>
    \\    <arch>x86_64</arch>
    \\    <version ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">same</checksum>
    \\    <location href="packages/one.rpm"/>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>duplicate</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">same</checksum>
    \\    <location href="packages/two.rpm"/>
    \\  </package>
    \\</metadata>
;

const no_pkgid_primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common" packages="2">
    \\  <package type="rpm">
    \\    <name>header-only</name>
    \\    <arch>x86_64</arch>
    \\    <version ver="1" rel="1"/>
    \\    <checksum type="sha" pkgid="NO">header-checksum</checksum>
    \\    <location href="packages/header-only.rpm"/>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>header-only</name>
    \\    <arch>x86_64</arch>
    \\    <version ver="1" rel="1"/>
    \\    <checksum type="sha" pkgid="YES">header-checksum</checksum>
    \\    <location href="packages/header-only-pkgid.rpm"/>
    \\  </package>
    \\</metadata>
;

const FixtureOptions = struct {
    include_filelists: bool = true,
    primary_checksum: ?[]const u8 = null,
};

const Fixture = struct {
    tmp: std.testing.TmpDir,
    repomd_sha256: [64]u8,

    fn create(primary: []const u8, options: FixtureOptions) !Fixture {
        var fixture = Fixture{
            .tmp = std.testing.tmpDir(.{}),
            .repomd_sha256 = undefined,
        };
        errdefer fixture.tmp.cleanup();

        const primary_sha = lowerHex(sha256(primary));
        const filelists_sha = lowerHex(sha256(filelists_xml));
        const expected_primary_sha = options.primary_checksum orelse
            primary_sha[0..];
        const repomd = if (options.include_filelists)
            try std.fmt.allocPrint(
                std.testing.allocator,
                \\<?xml version="1.0" encoding="UTF-8"?>
                \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
                \\  <revision>snapshot-revision</revision>
                \\  <data type="primary">
                \\    <checksum type="SHA256">{s}</checksum>
                \\    <open-checksum type="sha256">{s}</open-checksum>
                \\    <location href="repodata/primary.xml"/>
                \\    <timestamp>42</timestamp>
                \\    <size>{d}</size>
                \\    <open-size>{d}</open-size>
                \\    <database_version>10</database_version>
                \\  </data>
                \\  <data type="filelists">
                \\    <checksum type="sha256">{s}</checksum>
                \\    <open-checksum type="sha256">{s}</open-checksum>
                \\    <location xml:base="../metadata" href="repodata/filelists.xml"/>
                \\    <timestamp>77</timestamp>
                \\    <size>{d}</size>
                \\    <open-size>{d}</open-size>
                \\  </data>
                \\</repomd>
            ,
                .{
                    expected_primary_sha,
                    primary_sha[0..],
                    primary.len,
                    primary.len,
                    filelists_sha[0..],
                    filelists_sha[0..],
                    filelists_xml.len,
                    filelists_xml.len,
                },
            )
        else
            try std.fmt.allocPrint(
                std.testing.allocator,
                \\<?xml version="1.0" encoding="UTF-8"?>
                \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
                \\  <revision>snapshot-revision</revision>
                \\  <data type="primary">
                \\    <checksum type="SHA256">{s}</checksum>
                \\    <open-checksum type="sha256">{s}</open-checksum>
                \\    <location href="repodata/primary.xml"/>
                \\    <timestamp>42</timestamp>
                \\    <size>{d}</size>
                \\    <open-size>{d}</open-size>
                \\    <database_version>10</database_version>
                \\  </data>
                \\</repomd>
            ,
                .{
                    expected_primary_sha,
                    primary_sha[0..],
                    primary.len,
                    primary.len,
                },
            );
        defer std.testing.allocator.free(repomd);

        try fixture.tmp.dir.createDirPath(
            std.testing.io,
            "cache-api_key=cache-credential/repodata",
        );
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{
                .sub_path = "cache-api_key=cache-credential/repodata/repomd.xml",
                .data = repomd,
            },
        );
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{
                .sub_path = "cache-api_key=cache-credential/repodata/primary.xml",
                .data = primary,
            },
        );
        if (options.include_filelists) {
            try fixture.tmp.dir.writeFile(
                std.testing.io,
                .{
                    .sub_path = "cache-api_key=cache-credential/repodata/filelists.xml",
                    .data = filelists_xml,
                },
            );
        }
        fixture.repomd_sha256 = lowerHex(sha256(repomd));
        return fixture;
    }

    fn cleanup(self: *Fixture) void {
        self.tmp.cleanup();
        self.* = undefined;
    }

    fn cachePath(
        self: *const Fixture,
        buffer: *[std.Io.Dir.max_path_bytes]u8,
    ) []u8 {
        return std.fmt.bufPrint(
            buffer,
            ".zig-cache/tmp/{s}/cache-api_key=cache-credential",
            .{&self.tmp.sub_path},
        ) catch @panic("cache path too long");
    }

    fn mutatePrimary(self: *Fixture, bytes: []const u8) !void {
        try self.tmp.dir.writeFile(
            std.testing.io,
            .{
                .sub_path = "cache-api_key=cache-credential/repodata/primary.xml",
                .data = bytes,
            },
        );
    }

    fn makeRepomdMalformed(self: *Fixture) !void {
        try self.tmp.dir.writeFile(
            std.testing.io,
            .{
                .sub_path = "cache-api_key=cache-credential/repodata/repomd.xml",
                .data = "<repomd>",
            },
        );
    }
};

fn testEnvironment() transaction_plan.Environment {
    const sha =
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    return .{
        .architecture = "x86_64",
        .distro = "test",
        .policy = .{
            .allow_erasing = false,
            .allow_multilib = false,
            .all_deps = false,
            .best = false,
            .clean_requirements_on_remove = false,
            .excludes = &.{},
            .force_architecture = null,
            .include_installed = false,
            .installonly_limit = 0,
            .installonly_names = &.{},
            .install_weak_dependencies = false,
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
            .cookie_sha256 = sha,
            .package_set_sha256 = sha,
        },
    };
}

fn createPlan(
    allocator: Allocator,
    repository: transaction_plan.Repository,
    packages: []const transaction_plan.Package,
) !*transaction_plan.Plan {
    return transaction_plan.Plan.create(allocator, .{
        .actions = &.{},
        .environment = testEnvironment(),
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = packages,
        .problems = &.{},
        .repositories = &.{repository},
        .requests = &.{},
        .selected = &.{},
        .skipped = &.{},
    });
}

test "captures owned available repository and package facts" {
    var fixture = try Fixture.create(primary_xml, .{});
    defer fixture.cleanup();
    var cache_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cache_dir = fixture.cachePath(&cache_path_buffer);
    const original_cache_dir = try std.testing.allocator.dupe(u8, cache_dir);
    defer std.testing.allocator.free(original_cache_dir);
    var repository_id = [_]u8{ 'r', 'e', 'p', 'o', '-', 'a' };

    var owner = try capture(std.testing.allocator, .{
        .repository_id = &repository_id,
        .priority = 11,
        .cost = 777,
        .cache_dir = cache_dir,
    });
    defer owner.destroy();
    const captured = owner.view();
    const repomd = captured.repository.repomd.?;
    const snapshot = captured.repository.snapshot.?;

    try std.testing.expectEqualStrings("repo-a", captured.repository.id);
    try std.testing.expectEqual(@as(i32, 11), captured.repository.priority);
    try std.testing.expectEqual(@as(u32, 777), captured.repository.cost);
    try std.testing.expectEqual(transaction_plan.RepositoryKind.available, captured.repository.kind);
    try std.testing.expectEqualStrings(&fixture.repomd_sha256, repomd.checksum_sha256);
    try std.testing.expectEqualStrings(
        repomd.checksum_sha256,
        snapshot.metadata_sha256,
    );
    const expected_snapshot = try snapshotId(
        std.testing.allocator,
        sha256FromHex(repomd.checksum_sha256),
    );
    defer std.testing.allocator.free(expected_snapshot);
    try std.testing.expectEqualStrings(expected_snapshot, snapshot.id);
    try std.testing.expectEqual(@as(u64, 77), repomd.timestamp);
    try std.testing.expectEqualStrings("snapshot-revision", repomd.revision.?);
    try std.testing.expectEqual(@as(usize, 2), repomd.records.len);
    const primary_sha = lowerHex(sha256(primary_xml));
    const filelists_sha = lowerHex(sha256(filelists_xml));
    try std.testing.expectEqualStrings("primary", repomd.records[0].record_type);
    try std.testing.expectEqualStrings(
        "SHA256",
        repomd.records[0].checksum.?.kind,
    );
    try std.testing.expectEqualStrings(
        &primary_sha,
        repomd.records[0].checksum.?.value,
    );
    try std.testing.expectEqualStrings(
        "sha256",
        repomd.records[0].open_checksum.?.kind,
    );
    try std.testing.expectEqualStrings(
        &primary_sha,
        repomd.records[0].open_checksum.?.value,
    );
    try std.testing.expectEqualStrings(
        "repodata/primary.xml",
        repomd.records[0].location.href,
    );
    try std.testing.expect(repomd.records[0].location.xml_base == null);
    try std.testing.expectEqual(
        @as(?u64, @intCast(primary_xml.len)),
        repomd.records[0].size,
    );
    try std.testing.expectEqual(
        @as(?u64, @intCast(primary_xml.len)),
        repomd.records[0].open_size,
    );
    try std.testing.expectEqual(@as(?u64, 42), repomd.records[0].timestamp);
    try std.testing.expectEqualStrings(
        "../metadata",
        repomd.records[1].location.xml_base.?,
    );
    try std.testing.expectEqualStrings(
        "filelists",
        repomd.records[1].record_type,
    );
    try std.testing.expectEqualStrings(
        "repodata/filelists.xml",
        repomd.records[1].location.href,
    );
    try std.testing.expectEqualStrings(
        &filelists_sha,
        repomd.records[1].checksum.?.value,
    );
    try std.testing.expectEqualStrings(
        &filelists_sha,
        repomd.records[1].open_checksum.?.value,
    );
    try std.testing.expectEqual(
        @as(?u64, @intCast(filelists_xml.len)),
        repomd.records[1].size,
    );
    try std.testing.expectEqual(
        @as(?u64, @intCast(filelists_xml.len)),
        repomd.records[1].open_size,
    );
    try std.testing.expectEqual(@as(?u64, 77), repomd.records[1].timestamp);
    try std.testing.expectEqual(@as(?u64, 10), repomd.records[0].database_version);
    try std.testing.expect(repomd.records[1].database_version == null);

    try std.testing.expectEqual(@as(usize, 2), captured.packages.len);
    const alpha = owner.findPackage(.{
        .repository = "repo-a",
        .name = "alpha",
        .epoch = 7,
        .version = "1.2",
        .release = "3",
        .arch = "x86_64",
        .checksum = .{
            .kind = "SHA256",
            .value = "AbCdEf01",
            .is_pkgid = true,
        },
    }).?;
    try std.testing.expectEqualStrings("available-0", alpha.id);
    try std.testing.expectEqual(transaction_plan.PackageState.available, alpha.state);
    try std.testing.expectEqualStrings("repo-a", alpha.repository_id);
    try std.testing.expectEqual(@as(?u32, 7), alpha.identity.epoch);
    try std.testing.expectEqualStrings("SHA256", alpha.source.?.checksum.kind);
    try std.testing.expectEqualStrings(
        "AbCdEf01",
        alpha.source.?.checksum.value,
    );
    try std.testing.expect(alpha.source.?.checksum.is_pkgid);
    try std.testing.expectEqual(@as(?u64, 123), alpha.source.?.size);
    try std.testing.expectEqualStrings(
        "packages/alpha-1.2-3.x86_64.rpm",
        alpha.source.?.location.?.href,
    );
    try std.testing.expectEqualStrings(
        "../pool",
        alpha.source.?.location.?.xml_base.?,
    );
    try std.testing.expect(owner.findPackage(.{
        .repository = "repo-a",
        .name = "alpha",
        .epoch = 7,
        .version = "1.2",
        .release = "3",
        .arch = "x86_64",
        .checksum = .{
            .kind = "sha256",
            .value = "AbCdEf01",
            .is_pkgid = true,
        },
    }) == null);

    const beta = owner.findPackage(.{
        .repository = "repo-a",
        .name = "beta",
        .epoch = 0,
        .version = "4.5",
        .release = "6",
        .arch = "noarch",
        .checksum = .{
            .kind = "sha512",
            .value = "BETA-CHECKSUM",
            .is_pkgid = true,
        },
    }).?;
    try std.testing.expect(beta.identity.epoch == null);
    try std.testing.expect(beta.source.?.size == null);
    try std.testing.expect(beta.source.?.location.?.xml_base == null);

    repository_id[0] = 'x';
    @memset(cache_dir, 'x');
    try fixture.tmp.dir.deleteTree(
        std.testing.io,
        "cache-api_key=cache-credential",
    );

    const plan = try createPlan(
        std.testing.allocator,
        captured.repository.*,
        captured.packages,
    );
    defer plan.destroy();
    const json = try plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, original_cache_dir) == null);
    try std.testing.expect(
        std.mem.indexOf(u8, json, "api_key=cache-credential") == null,
    );
    try std.testing.expect(std.mem.indexOf(u8, json, "available-0") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"xml_base\":\"../pool\"") != null);
}

test "repeated captures and record permutations remain canonical" {
    var fixture = try Fixture.create(primary_xml, .{});
    defer fixture.cleanup();
    var cache_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cache_dir = fixture.cachePath(&cache_path_buffer);

    var first = try capture(std.testing.allocator, .{
        .repository_id = "repo-a",
        .priority = 11,
        .cost = 777,
        .cache_dir = cache_dir,
    });
    defer first.destroy();
    var second = try capture(std.testing.allocator, .{
        .repository_id = "repo-a",
        .priority = 11,
        .cost = 777,
        .cache_dir = cache_dir,
    });
    defer second.destroy();
    const first_view = first.view();
    const second_view = second.view();

    const first_plan = try createPlan(
        std.testing.allocator,
        first_view.repository.*,
        first_view.packages,
    );
    defer first_plan.destroy();
    const second_plan = try createPlan(
        std.testing.allocator,
        second_view.repository.*,
        second_view.packages,
    );
    defer second_plan.destroy();
    const first_json = try first_plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(first_json);
    const second_json = try second_plan.canonicalJsonAlloc(std.testing.allocator);
    defer std.testing.allocator.free(second_json);
    try std.testing.expectEqualStrings(first_json, second_json);

    var records = [_]transaction_plan.MetadataRecord{
        first_view.repository.repomd.?.records[1],
        first_view.repository.repomd.?.records[0],
    };
    var permuted_repository = first_view.repository.*;
    var permuted_repomd = permuted_repository.repomd.?;
    permuted_repomd.records = &records;
    permuted_repository.repomd = permuted_repomd;
    const permuted_plan = try createPlan(
        std.testing.allocator,
        permuted_repository,
        first_view.packages,
    );
    defer permuted_plan.destroy();
    const permuted_json = try permuted_plan.canonicalJsonAlloc(
        std.testing.allocator,
    );
    defer std.testing.allocator.free(permuted_json);
    try std.testing.expectEqualStrings(first_json, permuted_json);
}

test "captures packages whose checksum is not their package id" {
    var fixture = try Fixture.create(no_pkgid_primary_xml, .{
        .include_filelists = false,
    });
    defer fixture.cleanup();
    var cache_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;

    var owner = try capture(std.testing.allocator, .{
        .repository_id = "repo-a",
        .priority = 11,
        .cost = 777,
        .cache_dir = fixture.cachePath(&cache_path_buffer),
        .options = .{ .include_filelists = false },
    });
    defer owner.destroy();

    try std.testing.expectEqual(@as(usize, 2), owner.view().packages.len);
    const package = owner.view().packages[0];
    try std.testing.expect(!package.source.?.checksum.is_pkgid);
    try std.testing.expectEqualStrings(
        "sha",
        package.source.?.checksum.kind,
    );
    try std.testing.expect(owner.findPackage(.{
        .repository = "repo-a",
        .name = "header-only",
        .epoch = 0,
        .version = "1",
        .release = "1",
        .arch = "x86_64",
        .checksum = .{
            .kind = "sha",
            .value = "header-checksum",
            .is_pkgid = false,
        },
    }) != null);
    try std.testing.expect(owner.findPackage(.{
        .repository = "repo-a",
        .name = "header-only",
        .epoch = 0,
        .version = "1",
        .release = "1",
        .arch = "x86_64",
        .checksum = .{
            .kind = "sha",
            .value = "header-checksum",
            .is_pkgid = true,
        },
    }) != null);
}

test "rejects malformed metadata, invalid checksums, and duplicate keys" {
    var bad_primary = try Fixture.create(primary_xml, .{});
    defer bad_primary.cleanup();
    var bad_primary_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try bad_primary.mutatePrimary("mutated-primary");
    try std.testing.expectError(error.InvalidRepoMetadata, capture(
        std.testing.allocator,
        .{
            .repository_id = "repo-a",
            .priority = 11,
            .cost = 777,
            .cache_dir = bad_primary.cachePath(&bad_primary_path_buffer),
        },
    ));

    var malformed_repomd = try Fixture.create(primary_xml, .{});
    defer malformed_repomd.cleanup();
    var malformed_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try malformed_repomd.makeRepomdMalformed();
    try std.testing.expectError(error.InvalidRepoMetadata, capture(
        std.testing.allocator,
        .{
            .repository_id = "repo-a",
            .priority = 11,
            .cost = 777,
            .cache_dir = malformed_repomd.cachePath(&malformed_path_buffer),
        },
    ));

    var bad_checksum = try Fixture.create(primary_xml, .{
        .include_filelists = false,
        .primary_checksum = "0000000000000000000000000000000000000000000000000000000000000000",
    });
    defer bad_checksum.cleanup();
    var checksum_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try std.testing.expectError(error.InvalidRepoMetadata, capture(
        std.testing.allocator,
        .{
            .repository_id = "repo-a",
            .priority = 11,
            .cost = 777,
            .cache_dir = bad_checksum.cachePath(&checksum_path_buffer),
            .options = .{ .include_filelists = false },
        },
    ));

    var duplicate = try Fixture.create(duplicate_primary_xml, .{
        .include_filelists = false,
    });
    defer duplicate.cleanup();
    var duplicate_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try std.testing.expectError(error.DuplicatePackageKey, capture(
        std.testing.allocator,
        .{
            .repository_id = "repo-a",
            .priority = 11,
            .cost = 777,
            .cache_dir = duplicate.cachePath(&duplicate_path_buffer),
            .options = .{ .include_filelists = false },
        },
    ));
}

fn allocationFailureCase(
    allocator: Allocator,
    cache_dir: []const u8,
) !void {
    var owner = try capture(allocator, .{
        .repository_id = "repo-a",
        .priority = 11,
        .cost = 777,
        .cache_dir = cache_dir,
    });
    defer owner.destroy();
    try std.testing.expectEqual(@as(usize, 2), owner.view().packages.len);
}

test "capture cleans every allocation failure" {
    var fixture = try Fixture.create(primary_xml, .{});
    defer fixture.cleanup();
    var cache_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cache_dir = fixture.cachePath(&cache_path_buffer);
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailureCase,
        .{cache_dir},
    );
}

fn sha256FromHex(value: []const u8) [32]u8 {
    var result: [32]u8 = undefined;
    for (&result, 0..) |*byte, index| {
        byte.* = hexByte(value[index * 2]) * 16 +
            hexByte(value[index * 2 + 1]);
    }
    return result;
}

fn hexByte(value: u8) u8 {
    return if (std.ascii.isDigit(value))
        value - '0'
    else
        std.ascii.toLower(value) - 'a' + 10;
}
