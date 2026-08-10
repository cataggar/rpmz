//! Proves the supported package boundary from outside the repository.
//!
//! This program is built as a real dependency consumer: it sees only what
//! `build.zig.zon` packages and only what `build.zig` registers as a public
//! module. It builds a self-contained repository and an empty install root,
//! resolves a transaction against them, and checks the guarantees
//! `doc/transaction-plan-api.md` makes.

const std = @import("std");
const tdnf = @import("tdnf");

const resolver = tdnf.resolver;
const transaction_plan = tdnf.transaction_plan;

const primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common"
    \\              xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="1">
    \\  <package type="rpm">
    \\    <name>consumer-app</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</checksum>
    \\    <size package="123"/>
    \\    <location href="packages/consumer-app.rpm"/>
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
        \\  <revision>public-consumer</revision>
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

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    var io_state: std.Io.Threaded = .init(allocator, .{});
    defer io_state.deinit();
    const io = io_state.io();

    // A fixture the consumer owns end to end, so every fact in the resulting
    // plan traces back to a value this program declared.
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "fixture");
    var tmp = try cwd.openDir(io, "fixture", .{ .iterate = true });
    defer tmp.close(io);
    try tmp.createDirPath(io, "root");
    try tmp.createDirPath(io, "work");
    try tmp.createDirPath(io, "snapshot/repodata");

    const repomd = try repomdFor(allocator, primary_xml);
    try tmp.writeFile(io, .{
        .sub_path = "snapshot/repodata/primary.xml",
        .data = primary_xml,
    });
    try tmp.writeFile(io, .{
        .sub_path = "snapshot/repodata/repomd.xml",
        .data = repomd,
    });

    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const base = buffer[0..try tmp.realPath(io, &buffer)];
    const root = try std.fmt.allocPrint(allocator, "{s}/root", .{base});
    const snapshot = try std.fmt.allocPrint(allocator, "{s}/snapshot", .{base});
    const scratch = try std.fmt.allocPrint(allocator, "{s}/work", .{base});

    const repositories = [_]resolver.Repository{.{
        .id = "consumer-base",
        .metadata = .{ .local_snapshot = snapshot },
    }};
    const request = resolver.ResolveInput{
        .operation = .install,
        .subjects = &.{"consumer-app"},
        .repositories = &repositories,
        .installed = .{ .install_root = root },
        .environment = .{
            .architecture = "x86_64",
            .distro = "public-consumer",
            .release_version = "1",
        },
        .cache_dir = "/cache",
        .scratch_dir = scratch,
    };

    const plan = try resolver.resolvePlan(allocator, io, request);
    defer plan.destroy();

    const model = plan.model();
    if (model.environment.resolution_status != .resolved)
        return error.UnresolvedPlan;
    if (model.actions.len == 0) return error.NoActions;

    var saw_app = false;
    for (model.packages) |package| {
        if (std.mem.eql(u8, package.identity.name, "consumer-app"))
            saw_app = true;
    }
    if (!saw_app) return error.MissingRequestedPackage;

    // Only the declared repository may appear.
    for (model.repositories) |repository| {
        if (std.mem.eql(u8, repository.id, "consumer-base")) continue;
        if (std.mem.eql(u8, repository.id, "@System")) continue;
        return error.UndeclaredRepository;
    }

    const digest = try plan.digest(allocator);
    if (digest.len != 64) return error.InvalidDigest;

    const canonical_json = try plan.canonicalJsonAlloc(allocator);
    const schema_field =
        "\"schema\":\"" ++ transaction_plan.schema ++ "\"";
    if (std.mem.indexOf(u8, canonical_json, schema_field) == null)
        return error.MissingCanonicalSchema;

    // The same request must reproduce the same document, byte for byte.
    const again = try resolver.resolvePlan(allocator, io, request);
    defer again.destroy();
    const again_json = try again.canonicalJsonAlloc(allocator);
    if (!std.mem.eql(u8, canonical_json, again_json))
        return error.NondeterministicPlan;

    const again_digest = try again.digest(allocator);
    if (!std.mem.eql(u8, &digest, &again_digest))
        return error.NondeterministicDigest;

    // A different request must not reproduce it.
    var other = request;
    other.environment.architecture = "aarch64";
    const other_plan = try resolver.resolvePlan(allocator, io, other);
    defer other_plan.destroy();
    const other_digest = try other_plan.digest(allocator);
    if (std.mem.eql(u8, &digest, &other_digest))
        return error.InsensitiveDigest;

    // Resolving executes nothing and leaves no scratch state behind.
    var work = try tmp.openDir(io, "work", .{ .iterate = true });
    defer work.close(io);
    var iterator = work.iterate();
    if (try iterator.next(io) != null) return error.ScratchNotRemoved;
}
