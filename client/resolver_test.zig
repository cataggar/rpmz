//! End-to-end proof that the supported resolver is driven by its inputs alone.
//!
//! The fixture is a self-contained file repository and an empty scratch
//! install root, so every fact in the resulting plan traces back to a value
//! this test declared. The repository is deliberately poisoned with host-shaped
//! configuration the resolver must ignore.

const std = @import("std");
const client = @import("client_root");

comptime {
    _ = client;
}

const resolver = client.resolver;
const transaction_plan = resolver.transaction_plan;
const io = std.testing.io;

const primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common"
    \\              xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="2">
    \\  <package type="rpm">
    \\    <name>app</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</checksum>
    \\    <size package="123"/>
    \\    <location href="packages/app.rpm"/>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>broken</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb</checksum>
    \\    <size package="123"/>
    \\    <location href="packages/broken.rpm"/>
    \\    <format>
    \\      <rpm:requires><rpm:entry name="missing-capability"/></rpm:requires>
    \\    </format>
    \\  </package>
    \\</metadata>
    \\
;

/// Metadata for a repository the caller never declares. Nothing from it may
/// reach the plan.
const undeclared_primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common"
    \\              xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="1">
    \\  <package type="rpm">
    \\    <name>app</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="9" rel="9"/>
    \\    <checksum type="sha256" pkgid="YES">cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc</checksum>
    \\    <size package="123"/>
    \\    <location href="packages/app.rpm"/>
    \\  </package>
    \\</metadata>
    \\
;

fn digestHex(bytes: []const u8) [64]u8 {
    var value: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &value, .{});
    var hex: [64]u8 = undefined;
    for (value, 0..) |byte, index| {
        _ = std.fmt.bufPrint(
            hex[index * 2 .. index * 2 + 2],
            "{x:0>2}",
            .{byte},
        ) catch unreachable;
    }
    return hex;
}

fn repomdFor(allocator: std.mem.Allocator, primary: []const u8) ![]u8 {
    const primary_digest = digestHex(primary);
    return std.fmt.allocPrint(allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
        \\  <revision>public-resolver-test</revision>
        \\  <data type="primary">
        \\    <checksum type="sha256">{s}</checksum>
        \\    <open-checksum type="sha256">{s}</open-checksum>
        \\    <location href="repodata/primary.xml"/>
        \\    <timestamp>123</timestamp>
        \\    <size>{d}</size>
        \\    <open-size>{d}</open-size>
        \\  </data>
        \\</repomd>
        \\
    , .{ &primary_digest, &primary_digest, primary.len, primary.len });
}

const Fixture = struct {
    tmp: std.testing.TmpDir,
    base: []u8,
    root: []u8,
    snapshot: []u8,
    undeclared: []u8,
    scratch: []u8,

    fn create() !Fixture {
        const allocator = std.testing.allocator;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();

        try tmp.dir.createDirPath(io, "root");
        try tmp.dir.createDirPath(io, "work");
        try tmp.dir.createDirPath(io, "snapshot/repodata");
        try tmp.dir.createDirPath(io, "undeclared/repodata");

        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        const base = try allocator.dupe(u8, buffer[0..length]);
        errdefer allocator.free(base);

        const repomd = try repomdFor(allocator, primary_xml);
        defer allocator.free(repomd);
        try tmp.dir.writeFile(io, .{
            .sub_path = "snapshot/repodata/primary.xml",
            .data = primary_xml,
        });
        try tmp.dir.writeFile(io, .{
            .sub_path = "snapshot/repodata/repomd.xml",
            .data = repomd,
        });

        const undeclared_repomd = try repomdFor(allocator, undeclared_primary_xml);
        defer allocator.free(undeclared_repomd);
        try tmp.dir.writeFile(io, .{
            .sub_path = "undeclared/repodata/primary.xml",
            .data = undeclared_primary_xml,
        });
        try tmp.dir.writeFile(io, .{
            .sub_path = "undeclared/repodata/repomd.xml",
            .data = undeclared_repomd,
        });

        var self = Fixture{
            .tmp = tmp,
            .base = base,
            .root = undefined,
            .snapshot = undefined,
            .undeclared = undefined,
            .scratch = undefined,
        };
        self.root = try std.fmt.allocPrint(allocator, "{s}/root", .{base});
        errdefer allocator.free(self.root);
        self.snapshot = try std.fmt.allocPrint(allocator, "{s}/snapshot", .{base});
        errdefer allocator.free(self.snapshot);
        self.undeclared = try std.fmt.allocPrint(
            allocator,
            "{s}/undeclared",
            .{base},
        );
        errdefer allocator.free(self.undeclared);
        self.scratch = try std.fmt.allocPrint(allocator, "{s}/work", .{base});
        return self;
    }

    fn destroy(self: *Fixture) void {
        const allocator = std.testing.allocator;
        allocator.free(self.scratch);
        allocator.free(self.undeclared);
        allocator.free(self.snapshot);
        allocator.free(self.root);
        allocator.free(self.base);
        self.tmp.cleanup();
        self.* = undefined;
    }

    fn input(self: *const Fixture, repositories: []const resolver.Repository) resolver.ResolveInput {
        return .{
            .operation = .install,
            .subjects = &.{"app"},
            .repositories = repositories,
            .installed = .{ .install_root = self.root },
            .environment = .{
                .architecture = "x86_64",
                .distro = "fixture-distro",
                .release_version = "42",
            },
            .cache_dir = "/cache",
            .scratch_dir = self.scratch,
        };
    }

    fn declared(self: *const Fixture) resolver.Repository {
        return .{
            .id = "base",
            .metadata = .{ .local_snapshot = self.snapshot },
        };
    }
};

/// A sorted `path\0size\n` inventory of every file under `sub_path`, skipping
/// the metadata cache the resolve is allowed to populate.
fn inventory(
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    sub_path: []const u8,
) ![]u8 {
    var target = try dir.openDir(io, sub_path, .{ .iterate = true });
    defer target.close(io);

    var entries: std.ArrayList([]u8) = .empty;
    defer {
        for (entries.items) |item| allocator.free(item);
        entries.deinit(allocator);
    }

    var walker = try target.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (std.mem.startsWith(u8, entry.path, "cache")) continue;
        const stat = switch (entry.kind) {
            .file => try target.statFile(io, entry.path, .{}),
            else => null,
        };
        const line = try std.fmt.allocPrint(allocator, "{s}\t{s}\t{d}\n", .{
            entry.path,
            @tagName(entry.kind),
            if (stat) |value| value.size else 0,
        });
        errdefer allocator.free(line);
        try entries.append(allocator, line);
    }

    std.mem.sort([]u8, entries.items, {}, struct {
        fn lessThan(_: void, left: []u8, right: []u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.lessThan);

    var joined: std.ArrayList(u8) = .empty;
    errdefer joined.deinit(allocator);
    for (entries.items) |item| try joined.appendSlice(allocator, item);
    return joined.toOwnedSlice(allocator);
}

test "public resolver returns an owned plan built only from declared inputs" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.create();
    defer fixture.destroy();

    const before = try inventory(allocator, fixture.tmp.dir, "root");
    defer allocator.free(before);

    // Every borrowed input lives in freshly allocated storage that is released
    // before the plan is inspected, proving the plan owns its own copy.
    const subject = try allocator.dupe(u8, "app");
    const repository_id = try allocator.dupe(u8, "base");
    const snapshot = try allocator.dupe(u8, fixture.snapshot);
    const root = try allocator.dupe(u8, fixture.root);
    const scratch = try allocator.dupe(u8, fixture.scratch);
    const architecture = try allocator.dupe(u8, "x86_64");
    const distro = try allocator.dupe(u8, "fixture-distro");
    const releasever = try allocator.dupe(u8, "42");

    const repositories = [_]resolver.Repository{.{
        .id = repository_id,
        .priority = 17,
        .metadata = .{ .local_snapshot = snapshot },
    }};
    const subjects = [_][]const u8{subject};

    const plan = try resolver.resolvePlan(allocator, io, .{
        .operation = .install,
        .subjects = &subjects,
        .repositories = &repositories,
        .installed = .{ .install_root = root },
        .environment = .{
            .architecture = architecture,
            .distro = distro,
            .release_version = releasever,
        },
        .cache_dir = "/cache",
        .scratch_dir = scratch,
    });
    defer plan.destroy();

    for ([_][]u8{
        subject,     repository_id, snapshot, root,
        scratch,     architecture,  distro,   releasever,
    }) |borrowed| {
        @memset(borrowed, 0xaa);
        allocator.free(borrowed);
    }

    const model = plan.model();
    try std.testing.expectEqual(
        transaction_plan.ResolutionStatus.resolved,
        model.environment.resolution_status,
    );
    try std.testing.expectEqualStrings("x86_64", model.environment.architecture);
    try std.testing.expectEqualStrings(
        "fixture-distro",
        model.environment.distro,
    );
    try std.testing.expectEqualStrings("42", model.environment.releasever);

    // Only the declared repository may appear, and `app` must be selected.
    var saw_base = false;
    for (model.repositories) |repository| {
        if (std.mem.eql(u8, repository.id, "base")) saw_base = true;
        try std.testing.expect(!std.mem.eql(u8, repository.id, "undeclared"));
    }
    try std.testing.expect(saw_base);

    var saw_app = false;
    for (model.packages) |package| {
        if (std.mem.eql(u8, package.identity.name, "app")) saw_app = true;
    }
    try std.testing.expect(saw_app);
    try std.testing.expect(model.selected.len != 0);

    const json = try plan.canonicalJsonAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(
        u8,
        json,
        "\"schema\":\"tdnf.transaction-plan/v1\"",
    ) != null);
    // No scratch or fixture path may leak into the canonical document.
    try std.testing.expect(std.mem.indexOf(u8, json, "tdnf-resolve-") == null);

    // Planning is read-only outside the declared metadata cache, and the
    // scratch tree is removed before the call returns.
    const after = try inventory(allocator, fixture.tmp.dir, "root");
    defer allocator.free(after);
    try std.testing.expectEqualStrings(before, after);

    const work = try inventory(allocator, fixture.tmp.dir, "work");
    defer allocator.free(work);
    try std.testing.expectEqualStrings("", work);
}

test "undeclared host repositories and caches cannot change the plan digest" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.create();
    defer fixture.destroy();

    const declared = [_]resolver.Repository{fixture.declared()};
    const first = try resolver.resolvePlan(
        allocator,
        io,
        fixture.input(&declared),
    );
    defer first.destroy();
    const baseline = try first.digest(allocator);

    // Plant exactly the state an implicitly discovering resolver would pick
    // up: a system config, a `.repo` drop-in, and a stale metadata cache for a
    // repository that offers a newer `app`.
    try fixture.tmp.dir.createDirPath(io, "root/etc/tdnf");
    try fixture.tmp.dir.createDirPath(io, "root/etc/yum.repos.d");
    const poisoned_repo = try std.fmt.allocPrint(allocator,
        \\[undeclared]
        \\name=Undeclared
        \\baseurl=file://{s}
        \\enabled=1
        \\gpgcheck=0
        \\priority=1
        \\
    , .{fixture.undeclared});
    defer allocator.free(poisoned_repo);
    try fixture.tmp.dir.writeFile(io, .{
        .sub_path = "root/etc/yum.repos.d/undeclared.repo",
        .data = poisoned_repo,
    });
    try fixture.tmp.dir.writeFile(io, .{
        .sub_path = "root/etc/tdnf/tdnf.conf",
        .data =
        \\[main]
        \\gpgcheck=1
        \\installonly_limit=99
        \\excludepkgs=app
        \\repodir=/etc/yum.repos.d
        \\
        ,
    });

    const second = try resolver.resolvePlan(
        allocator,
        io,
        fixture.input(&declared),
    );
    defer second.destroy();
    const poisoned = try second.digest(allocator);
    try std.testing.expectEqualStrings(&baseline, &poisoned);
}

test "repeating identical inputs produces identical canonical bytes" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const declared = [_]resolver.Repository{fixture.declared()};

    const first = try resolver.resolvePlan(
        allocator,
        io,
        fixture.input(&declared),
    );
    defer first.destroy();
    const first_json = try first.canonicalJsonAlloc(allocator);
    defer allocator.free(first_json);

    const second = try resolver.resolvePlan(
        allocator,
        io,
        fixture.input(&declared),
    );
    defer second.destroy();
    const second_json = try second.canonicalJsonAlloc(allocator);
    defer allocator.free(second_json);

    try std.testing.expectEqualStrings(first_json, second_json);
}

test "a solver contradiction is a problem plan, not a Zig error" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const declared = [_]resolver.Repository{fixture.declared()};

    var request = fixture.input(&declared);
    request.subjects = &.{"broken"};
    const plan = try resolver.resolvePlan(allocator, io, request);
    defer plan.destroy();

    const model = plan.model();
    try std.testing.expectEqual(
        transaction_plan.ResolutionStatus.problems,
        model.environment.resolution_status,
    );
    try std.testing.expect(model.problems.len != 0);
    try std.testing.expectEqual(@as(usize, 0), model.actions.len);
}

test "declared policy reaches the plan environment" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.create();
    defer fixture.destroy();
    const declared = [_]resolver.Repository{fixture.declared()};

    var request = fixture.input(&declared);
    request.policy = .{
        .best = true,
        .clean_requirements_on_remove = true,
        .installonly_limit = 7,
        .installonly_names = &.{"kernel"},
        .locked_names = &.{"locked-package"},
        .protected_names = &.{"protected-package"},
        .excludes = &.{"excluded-package"},
    };
    const plan = try resolver.resolvePlan(allocator, io, request);
    defer plan.destroy();

    const policy = plan.model().environment.policy;
    try std.testing.expect(policy.best);
    try std.testing.expect(policy.clean_requirements_on_remove);
    try std.testing.expectEqual(@as(u32, 7), policy.installonly_limit);
    try std.testing.expectEqual(@as(usize, 1), policy.installonly_names.len);
    try std.testing.expectEqualStrings("kernel", policy.installonly_names[0]);
    try std.testing.expectEqual(@as(usize, 1), policy.locked_names.len);
    try std.testing.expectEqualStrings(
        "locked-package",
        policy.locked_names[0],
    );
    try std.testing.expectEqual(@as(usize, 1), policy.protected_names.len);
    try std.testing.expectEqualStrings(
        "protected-package",
        policy.protected_names[0],
    );
    try std.testing.expectEqual(@as(usize, 1), policy.excludes.len);
    try std.testing.expectEqualStrings(
        "excluded-package",
        policy.excludes[0],
    );
}
