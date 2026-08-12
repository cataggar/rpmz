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
const bundle_export = tdnf.bundle_export;
const bundle_reader = tdnf.bundle_reader;

fn primaryXml(
    allocator: std.mem.Allocator,
    package_bytes: []const u8,
) ![]u8 {
    const package_digest = digestHex(package_bytes);
    return std.fmt.allocPrint(allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<metadata xmlns="http://linux.duke.edu/metadata/common"
        \\              xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="1">
        \\  <package type="rpm">
        \\    <name>consumer-app</name>
        \\    <arch>x86_64</arch>
        \\    <version epoch="0" ver="1" rel="1"/>
        \\    <checksum type="sha256" pkgid="YES">{s}</checksum>
        \\    <size package="{d}"/>
        \\    <location href="packages/consumer-app.rpm"/>
        \\  </package>
        \\</metadata>
        \\
    , .{ &package_digest, package_bytes.len });
}

fn minimalRpm(allocator: std.mem.Allocator) ![]u8 {
    const tags = [_]u32{ 1000, 1001, 1002, 1022 };
    const values = [_][]const u8{ "consumer-app", "1", "1", "x86_64" };
    const main_blob = try stringHeaderBlob(allocator, &tags, &values);
    defer allocator.free(main_blob);
    const signature_blob = try int32HeaderBlob(allocator, 1000, 0);
    defer allocator.free(signature_blob);
    const signature = try standaloneHeader(allocator, signature_blob, 62);
    defer allocator.free(signature);
    const main_header = try standaloneHeader(allocator, main_blob, 63);
    defer allocator.free(main_header);

    const padding = (8 - (signature.len % 8)) % 8;
    const bytes = try allocator.alloc(
        u8,
        96 + signature.len + padding + main_header.len,
    );
    @memset(bytes, 0);
    @memcpy(bytes[0..4], &[_]u8{ 0xed, 0xab, 0xee, 0xdb });
    @memcpy(bytes[96 .. 96 + signature.len], signature);
    @memcpy(bytes[96 + signature.len + padding ..], main_header);
    return bytes;
}

fn stringHeaderBlob(
    allocator: std.mem.Allocator,
    tags: []const u32,
    values: []const []const u8,
) ![]u8 {
    var data = std.array_list.Managed(u8).init(allocator);
    defer data.deinit();
    var index = std.array_list.Managed(u8).init(allocator);
    defer index.deinit();
    for (tags, values) |tag, value| {
        try appendBe32(&index, tag);
        try appendBe32(&index, 6);
        try appendBe32(&index, @intCast(data.items.len));
        try appendBe32(&index, 1);
        try data.appendSlice(value);
        try data.append(0);
    }
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try appendBe32(&out, @intCast(tags.len));
    try appendBe32(&out, @intCast(data.items.len));
    try out.appendSlice(index.items);
    try out.appendSlice(data.items);
    return out.toOwnedSlice();
}

fn int32HeaderBlob(
    allocator: std.mem.Allocator,
    tag: u32,
    value: u32,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try appendBe32(&out, 1);
    try appendBe32(&out, 4);
    try appendBe32(&out, tag);
    try appendBe32(&out, 4);
    try appendBe32(&out, 0);
    try appendBe32(&out, 1);
    try appendBe32(&out, value);
    return out.toOwnedSlice();
}

fn standaloneHeader(
    allocator: std.mem.Allocator,
    blob: []const u8,
    region_tag: u32,
) ![]u8 {
    const count = readBe32(blob[0..4]);
    const data_size = readBe32(blob[4..8]);
    const new_count = count + 1;
    const bytes = try allocator.alloc(
        u8,
        8 + 8 + @as(usize, new_count) * 16 + data_size + 16,
    );
    @memcpy(bytes[0..8], &[_]u8{ 0x8e, 0xad, 0xe8, 0x01, 0, 0, 0, 0 });
    const raw = bytes[8..];
    writeBe32(raw[0..4], new_count);
    writeBe32(raw[4..8], data_size + 16);
    writeBe32(raw[8..12], region_tag);
    writeBe32(raw[12..16], 7);
    writeBe32(raw[16..20], data_size);
    writeBe32(raw[20..24], 16);
    const old_index_len = @as(usize, count) * 16;
    @memcpy(raw[24 .. 24 + old_index_len], blob[8 .. 8 + old_index_len]);
    const data_start = 8 + @as(usize, new_count) * 16;
    @memcpy(
        raw[data_start .. data_start + data_size],
        blob[8 + old_index_len ..][0..data_size],
    );
    const trailer = raw[data_start + data_size ..][0..16];
    writeBe32(trailer[0..4], region_tag);
    writeBe32(trailer[4..8], 7);
    writeBe32(
        trailer[8..12],
        @bitCast(-@as(i32, @intCast(new_count * 16))),
    );
    writeBe32(trailer[12..16], 16);
    return bytes;
}

fn appendBe32(list: *std.array_list.Managed(u8), value: u32) !void {
    try list.append(@intCast((value >> 24) & 0xff));
    try list.append(@intCast((value >> 16) & 0xff));
    try list.append(@intCast((value >> 8) & 0xff));
    try list.append(@intCast(value & 0xff));
}

fn readBe32(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) << 24 |
        @as(u32, bytes[1]) << 16 |
        @as(u32, bytes[2]) << 8 |
        @as(u32, bytes[3]);
}

fn writeBe32(bytes: []u8, value: u32) void {
    bytes[0] = @intCast((value >> 24) & 0xff);
    bytes[1] = @intCast((value >> 16) & 0xff);
    bytes[2] = @intCast((value >> 8) & 0xff);
    bytes[3] = @intCast(value & 0xff);
}

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
    try tmp.createDirPath(io, "snapshot/packages");

    const package_bytes = try minimalRpm(allocator);
    const primary_xml = try primaryXml(allocator, package_bytes);
    const repomd = try repomdFor(allocator, primary_xml);
    try tmp.writeFile(io, .{
        .sub_path = "snapshot/repodata/primary.xml",
        .data = primary_xml,
    });
    try tmp.writeFile(io, .{
        .sub_path = "snapshot/packages/consumer-app.rpm",
        .data = package_bytes,
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

    try exportsBundle(allocator, io, tmp, base, request);

    // Resolving executes nothing and leaves no scratch state behind.
    var work = try tmp.openDir(io, "work", .{ .iterate = true });
    defer work.close(io);
    var iterator = work.iterate();
    if (try iterator.next(io) != null) return error.ScratchNotRemoved;
}

/// Exports a bundle for the same transaction and reopens it, which is the
/// whole point of the feature from outside: a consumer must be able to publish
/// an input set and later validate it without the repository it came from.
fn exportsBundle(
    allocator: std.mem.Allocator,
    io: std.Io,
    tmp: std.Io.Dir,
    base: []const u8,
    request: resolver.ResolveInput,
) !void {
    var scoped = request;
    scoped.scratch_dir = try std.fmt.allocPrint(allocator, "{s}/export-work", .{base});
    scoped.installed = .{ .install_root = try std.fmt.allocPrint(
        allocator,
        "{s}/export-root",
        .{base},
    ) };
    try tmp.createDirPath(io, "export-work");
    try tmp.createDirPath(io, "export-root");

    const destination = try std.fmt.allocPrint(allocator, "{s}/bundle", .{base});
    var result = try bundle_export.exportBundle(allocator, io, .{
        .resolve = scoped,
        .destination = destination,
        .gpg_check = false,
    });
    defer result.deinit();

    const exported = switch (result) {
        .exported => |value| value,
        .problems => return error.UnresolvedPlan,
    };
    if (exported.bundle_digest.len != 64) return error.InvalidDigest;
    if (!exported.plan.isReplayable()) return error.MissingExecutionOrder;
    if (!std.mem.eql(
        u8,
        exported.plan.schemaName(),
        transaction_plan.schema_v2,
    )) return error.MissingCanonicalSchema;

    // Reopening is what makes the export meaningful: the bundle has to be a
    // closed set on its own terms, not merely a directory the exporter liked.
    const opened = try bundle_reader.openBundle(allocator, io, destination);
    defer opened.destroy();
    if (!opened.isReplayable()) return error.MissingExecutionOrder;

    const model = opened.model();
    if (model.repositories.len == 0) return error.MissingRepository;
    if (model.files.len == 0) return error.MissingFiles;
    if (!std.mem.eql(u8, model.plan.schema, transaction_plan.schema_v2))
        return error.MissingCanonicalSchema;
}
