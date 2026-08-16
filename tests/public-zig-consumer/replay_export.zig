//! Test driver for the supported public bundle export API.
//!
//! The pytest replay acceptance suite invokes the installed copy of this
//! program so export and replay meet at the same boundary a real caller uses:
//! `@import("rpmz")` and the installed `rpmz` executable.

const std = @import("std");
const rpmz = @import("rpmz");

const resolver = rpmz.resolver;

const Arguments = struct {
    operation: resolver.Operation,
    repository_id: []const u8,
    base_url: []const u8,
    install_root: []const u8,
    cache_dir: []const u8,
    scratch_dir: []const u8,
    destination: []const u8,
    architecture: []const u8,
    release_version: []const u8,
    installonly_name: ?[]const u8,
    installonly_limit: u32,
    subjects: []const []const u8,
};

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();

    const arguments = parseArguments(allocator, init.minimal.args.vector) catch {
        printUsage();
        return error.InvalidArguments;
    };

    var base_urls = [_][]const u8{arguments.base_url};
    const repositories = [_]resolver.Repository{.{
        .id = arguments.repository_id,
        .metadata = .{ .remote = .{ .base_urls = &base_urls } },
    }};
    var installonly_names: [1][]const u8 = undefined;
    const policy_installonly_names: []const []const u8 =
        if (arguments.installonly_name) |name| blk: {
            installonly_names[0] = name;
            break :blk &installonly_names;
        } else &.{};

    var result = try rpmz.bundle_export.exportBundle(allocator, init.io, .{
        .resolve = .{
            .operation = arguments.operation,
            .subjects = arguments.subjects,
            .repositories = &repositories,
            .installed = .{ .install_root = arguments.install_root },
            .environment = .{
                .architecture = arguments.architecture,
                .distro = "replay-acceptance",
                .release_version = arguments.release_version,
            },
            .policy = .{
                .installonly_limit = arguments.installonly_limit,
                .installonly_names = policy_installonly_names,
            },
            .cache_dir = arguments.cache_dir,
            .scratch_dir = arguments.scratch_dir,
        },
        .destination = arguments.destination,
        .gpg_check = false,
    });
    defer result.deinit();

    const exported = switch (result) {
        .exported => |value| value,
        .problems => return error.UnresolvedTransaction,
    };
    var stdout_buffer: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.flush() catch {};
    try stdout.interface.print(
        "{{\"bundle_digest\":\"{s}\",\"plan_digest\":\"{s}\"}}\n",
        .{ &exported.bundle_digest, &exported.plan_digest },
    );
}

fn parseArguments(
    allocator: std.mem.Allocator,
    argv: []const [*:0]const u8,
) !Arguments {
    var operation: ?resolver.Operation = null;
    var repository_id: ?[]const u8 = null;
    var base_url: ?[]const u8 = null;
    var install_root: ?[]const u8 = null;
    var cache_dir: ?[]const u8 = null;
    var scratch_dir: ?[]const u8 = null;
    var destination: ?[]const u8 = null;
    var architecture: ?[]const u8 = null;
    var release_version: ?[]const u8 = null;
    var installonly_name: ?[]const u8 = null;
    var installonly_limit: u32 = 3;
    var subjects: std.ArrayList([]const u8) = .empty;
    defer subjects.deinit(allocator);

    var index: usize = 1;
    var subject_mode = false;
    while (index < argv.len) : (index += 1) {
        const argument = std.mem.span(argv[index]);
        if (subject_mode) {
            try subjects.append(allocator, argument);
            continue;
        }
        if (std.mem.eql(u8, argument, "--")) {
            subject_mode = true;
            continue;
        }
        const value = blk: {
            index += 1;
            if (index >= argv.len) return error.InvalidArguments;
            break :blk std.mem.span(argv[index]);
        };
        if (std.mem.eql(u8, argument, "--operation")) {
            operation = parseOperation(value) orelse
                return error.InvalidArguments;
        } else if (std.mem.eql(u8, argument, "--repo-id")) {
            repository_id = value;
        } else if (std.mem.eql(u8, argument, "--base-url")) {
            base_url = value;
        } else if (std.mem.eql(u8, argument, "--install-root")) {
            install_root = value;
        } else if (std.mem.eql(u8, argument, "--cache-dir")) {
            cache_dir = value;
        } else if (std.mem.eql(u8, argument, "--scratch-dir")) {
            scratch_dir = value;
        } else if (std.mem.eql(u8, argument, "--destination")) {
            destination = value;
        } else if (std.mem.eql(u8, argument, "--architecture")) {
            architecture = value;
        } else if (std.mem.eql(u8, argument, "--release-version")) {
            release_version = value;
        } else if (std.mem.eql(u8, argument, "--installonly-name")) {
            installonly_name = value;
        } else if (std.mem.eql(u8, argument, "--installonly-limit")) {
            installonly_limit = std.fmt.parseInt(
                u32,
                value,
                10,
            ) catch return error.InvalidArguments;
        } else {
            return error.InvalidArguments;
        }
    }

    const selected_operation = operation orelse return error.InvalidArguments;
    const owned_subjects = try subjects.toOwnedSlice(allocator);
    if (selected_operation.requiresSubjects() and owned_subjects.len == 0)
        return error.InvalidArguments;
    if (selected_operation.isSingleton() and owned_subjects.len != 0)
        return error.InvalidArguments;
    return .{
        .operation = selected_operation,
        .repository_id = repository_id orelse return error.InvalidArguments,
        .base_url = base_url orelse return error.InvalidArguments,
        .install_root = install_root orelse return error.InvalidArguments,
        .cache_dir = cache_dir orelse return error.InvalidArguments,
        .scratch_dir = scratch_dir orelse return error.InvalidArguments,
        .destination = destination orelse return error.InvalidArguments,
        .architecture = architecture orelse return error.InvalidArguments,
        .release_version = release_version orelse
            return error.InvalidArguments,
        .installonly_name = installonly_name,
        .installonly_limit = installonly_limit,
        .subjects = owned_subjects,
    };
}

fn parseOperation(value: []const u8) ?resolver.Operation {
    inline for (std.meta.tags(resolver.Operation)) |operation| {
        if (std.mem.eql(u8, value, @tagName(operation))) return operation;
    }
    return null;
}

fn printUsage() void {
    std.debug.print(
        \\usage: rpmz-replay-export
        \\  --operation <operation> --repo-id <id> --base-url <url>
        \\  --install-root <path> --cache-dir <path> --scratch-dir <path>
        \\  --destination <path> --architecture <arch>
        \\  --release-version <version>
        \\  [--installonly-name <name> --installonly-limit <count>]
        \\  -- [subjects...]
        \\
    , .{});
}
