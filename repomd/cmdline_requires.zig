const std = @import("std");

const cmdline_repository = @import("cmdline_repository.zig");
const error_codes = @import("rpmz_error");
const model = @import("model.zig");
const pkgquery = @import("pkgquery.zig");
const rpmpkg = @import("rpmpkg.zig");

pub export fn TDNFRepoMdNativeRequiresForCmdLineRpmPaths(
    raw_paths: ?[*]const ?[*:0]const u8,
    path_count: u32,
    out_deps: ?*[*c][*c]u8,
    out_count: ?*u32,
) u32 {
    if (out_deps) |out| out.* = null;
    if (out_count) |out| out.* = 0;

    const deps_out = out_deps orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    const count_out = out_count orelse return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (path_count != 0 and raw_paths == null) {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }

    const allocator = std.heap.c_allocator;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const paths = allocator.alloc([:0]const u8, path_count) catch |err| {
        return mapError(err);
    };
    defer allocator.free(paths);

    if (raw_paths) |paths_ptr| {
        for (paths, 0..) |*path, index| {
            const raw_path = paths_ptr[index] orelse {
                return error_codes.ERROR_TDNF_INVALID_PARAMETER;
            };
            path.* = std.mem.span(raw_path);
        }
    }

    const repository = cmdline_repository.loadModel(arena, paths) catch |err| {
        return mapError(err);
    };

    const lines = computeRequiresLinesForRepository(&repository) catch |err| {
        return mapError(err);
    };
    defer freeOwnedSlices(lines);

    deps_out.* = tryBuildCStringArray(lines) catch |err| {
        return mapError(err);
    };
    count_out.* = @intCast(lines.len);
    return 0;
}

fn mapError(err: anyerror) u32 {
    return switch (err) {
        error.OutOfMemory => error_codes.ERROR_TDNF_OUT_OF_MEMORY,
        error.InvalidParameter => error_codes.ERROR_TDNF_INVALID_PARAMETER,
        error.RpmFileOpenFailed => error_codes.ERROR_TDNF_FILE_NOT_FOUND,
        error.InvalidRpmHeader => error_codes.ERROR_TDNF_RPM_HEADER_CONVERT_FAILED,
        else => error_codes.ERROR_TDNF_SOLV_IO,
    };
}

fn computeRequiresLinesForRepository(repository: *const model.RepositoryModel) ![][]const u8 {
    var results = std.array_list.Managed([]const u8).init(std.heap.c_allocator);
    defer results.deinit();
    errdefer freeOwnedItems(results.items);

    var seen = std.StringHashMap(void).init(std.heap.c_allocator);
    defer seen.deinit();

    for (repository.packages) |pkg| {
        for (pkg.relationsFor(.requires, repository.relations)) |relation| {
            const dep = try pkgquery.formatRelation(std.heap.c_allocator, relation);
            const gop = seen.getOrPut(dep) catch |err| {
                std.heap.c_allocator.free(dep);
                return err;
            };
            if (gop.found_existing) {
                std.heap.c_allocator.free(dep);
                continue;
            }
            results.append(dep) catch |err| {
                std.heap.c_allocator.free(dep);
                return err;
            };
        }
    }

    return try results.toOwnedSlice();
}

fn freeOwnedItems(items: []const []const u8) void {
    for (items) |item| {
        std.heap.c_allocator.free(item);
    }
}

fn freeOwnedSlices(items: []const []const u8) void {
    freeOwnedItems(items);
    std.heap.c_allocator.free(items);
}

fn tryBuildCStringArray(items: []const []const u8) ![*c][*c]u8 {
    const raw = std.c.calloc(items.len + 1, @sizeOf([*c]u8)) orelse return error.OutOfMemory;
    const out: [*c][*c]u8 = @ptrCast(@alignCast(raw));
    var populated: usize = 0;
    errdefer {
        var index: usize = 0;
        while (index < populated) : (index += 1) {
            if (out[index] != null) {
                std.c.free(@ptrCast(out[index]));
            }
        }
        std.c.free(raw);
    }

    for (items, 0..) |item, index| {
        out[index] = try dupCString(item);
        populated += 1;
    }
    return out;
}

fn dupCString(text: []const u8) ![*c]u8 {
    const raw = std.c.calloc(text.len + 1, 1) orelse return error.OutOfMemory;
    const out: [*c]u8 = @ptrCast(raw);
    @memcpy(out[0..text.len], text);
    out[text.len] = 0;
    return out;
}

fn freeCStringArrayForTest(array: [*c][*c]u8) void {
    if (array == null) return;
    var index: usize = 0;
    while (array[index] != null) : (index += 1) {
        std.c.free(@ptrCast(array[index]));
    }
    std.c.free(@ptrCast(array));
}

test "native command-line rpm requires entry point returns formatted unique requires" {
    const testing = std.testing;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const rpm_bytes = try rpmpkg.makeMinimalRpmBytesWithRequiresForTest(
        testing.allocator,
        "cmdline-builddep",
        "1.0",
        "1",
        "x86_64",
    );
    defer testing.allocator.free(rpm_bytes);

    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "cmdline-builddep.rpm",
        .data = rpm_bytes,
    });

    const rpm_path = try std.fmt.allocPrintSentinel(
        testing.allocator,
        ".zig-cache/tmp/{s}/cmdline-builddep.rpm",
        .{&tmp.sub_path},
        0,
    );
    defer testing.allocator.free(rpm_path);

    const raw_paths = [_]?[*:0]const u8{rpm_path.ptr};
    var out_deps: [*c][*c]u8 = null;
    var out_count: u32 = 0;
    defer freeCStringArrayForTest(out_deps);

    try testing.expectEqual(
        @as(u32, 0),
        TDNFRepoMdNativeRequiresForCmdLineRpmPaths(&raw_paths, raw_paths.len, &out_deps, &out_count),
    );
    try testing.expectEqual(@as(u32, 2), out_count);
    try testing.expectEqualStrings("dep-one >= 1:1.0-2", std.mem.span(out_deps[0]));
    try testing.expectEqualStrings("dep-two < 0:3.1", std.mem.span(out_deps[1]));
}
