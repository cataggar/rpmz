const std = @import("std");
const abi = @import("tdnf_internal_abi");
const client = @import("client");
const repomd = @import("repomd");

const c = @cImport({
    @cInclude("stdio.h");
});

extern fn TDNFGetReleaseVersion(
    [*c]const u8,
    [*c]const u8,
    [*c][*c]u8,
) u32;
extern fn TDNFFreeMemory(?*anyopaque) void;
extern fn TDNFFreeStringArray([*c][*c]u8) void;

const InputItem = struct {
    op: u32,
    path: ?[]const u8 = null,
    name: ?[]const u8 = null,
    evr: ?[]const u8 = null,
    arch: ?[]const u8 = null,
    hnum: u32 = 0,
};

comptime {
    _ = client;
    _ = repomd.transaction_native;
}

fn spanOptional(value: [*c]const u8) ?[]const u8 {
    if (value == null) return null;
    return std.mem.span(@as([*:0]const u8, @ptrCast(value)));
}

fn writeFailure(
    writer: *std.Io.Writer,
    rc: u32,
    message: [*c]const u8,
) !void {
    try writer.print(
        "{{\"rc\":{d},\"error\":{f}}}\n",
        .{ rc, std.json.fmt(spanOptional(message), .{}) },
    );
}

fn runTransactionV2(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    root: []const u8,
    encoded_items: []const u8,
) !void {
    const parsed = try std.json.parseFromSlice(
        []InputItem,
        allocator,
        encoded_items,
        .{},
    );
    defer parsed.deinit();

    const root_z = try allocator.dupeZ(u8, root);
    defer allocator.free(root_z);
    const raw = try allocator.alloc(
        abi.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2,
        parsed.value.len,
    );
    defer allocator.free(raw);

    var owned = std.array_list.Managed([:0]u8).init(allocator);
    defer {
        for (owned.items) |value| allocator.free(value);
        owned.deinit();
    }
    for (parsed.value, raw) |item, *out| {
        out.* = .{
            .dwOperation = item.op,
            .pszPath = try optionalZ(allocator, &owned, item.path),
            .pszName = try optionalZ(allocator, &owned, item.name),
            .pszEVR = try optionalZ(allocator, &owned, item.evr),
            .pszArch = try optionalZ(allocator, &owned, item.arch),
            .dwRpmDbHnum = item.hnum,
        };
    }

    var plan: [*c]abi.TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = null;
    const rc = abi.TDNFRepoMdNativeTransactionPlanSolveV2(
        raw.ptr,
        @intCast(raw.len),
        root_z.ptr,
        &plan,
    );
    if (rc != 0) {
        return writeFailure(
            writer,
            rc,
            abi.TDNFRepoMdNativeTransactionLastError(),
        );
    }
    defer abi.TDNFRepoMdNativeTransactionPlanFree(plan);

    try writer.writeAll("{\"rc\":0,\"order\":[");
    for (0..plan[0].dwItemCount) |index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print("{d}", .{plan[0].pdwOrderIndices[index]});
    }
    try writer.writeAll("],\"problems\":[");
    for (0..plan[0].dwProblemCount) |index| {
        if (index != 0) try writer.writeByte(',');
        const problem = plan[0].pProblems[index];
        try writer.print(
            "{{\"type\":{d},\"input\":{d},\"package\":{f}," ++
                "\"related\":{f},\"subject\":{f},\"count\":{d}}}",
            .{
                problem.nType,
                problem.dwInputIndex,
                std.json.fmt(spanOptional(problem.pszPackage), .{}),
                std.json.fmt(spanOptional(problem.pszRelatedPackage), .{}),
                std.json.fmt(spanOptional(problem.pszSubject), .{}),
                problem.dwCount,
            },
        );
    }
    try writer.writeAll("],\"priors\":[");
    for (0..plan[0].dwItemCount) |index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeByte('[');
        const item = plan[0].pItems[index];
        for (0..item.dwPriorCount) |offset| {
            if (offset != 0) try writer.writeByte(',');
            try writer.print(
                "{d}",
                .{plan[0].pdwPriorHnums[item.dwPriorOffset + offset]},
            );
        }
        try writer.writeByte(']');
    }
    try writer.writeAll("]}\n");
}

fn runTransactionLegacy(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    root: []const u8,
    encoded_items: []const u8,
) !void {
    const parsed = try std.json.parseFromSlice(
        []InputItem,
        allocator,
        encoded_items,
        .{},
    );
    defer parsed.deinit();

    const root_z = try allocator.dupeZ(u8, root);
    defer allocator.free(root_z);
    const raw = try allocator.alloc(
        abi.TDNF_REPOMD_NATIVE_TRANSACTION_ITEM,
        parsed.value.len,
    );
    defer allocator.free(raw);

    var owned = std.array_list.Managed([:0]u8).init(allocator);
    defer {
        for (owned.items) |value| allocator.free(value);
        owned.deinit();
    }
    for (parsed.value, raw) |item, *out| {
        out.* = .{
            .dwOperation = item.op,
            .pszPath = try optionalZ(allocator, &owned, item.path),
            .pszName = try optionalZ(allocator, &owned, item.name),
            .pszEVR = try optionalZ(allocator, &owned, item.evr),
            .pszArch = try optionalZ(allocator, &owned, item.arch),
        };
    }

    var order_lines: [*c][*c]u8 = null;
    var order_count: u32 = 0;
    var problem_lines: [*c][*c]u8 = null;
    var problem_count: u32 = 0;
    const rc = abi.TDNFRepoMdNativeTransactionSolve(
        raw.ptr,
        @intCast(raw.len),
        root_z.ptr,
        &order_lines,
        &order_count,
        &problem_lines,
        &problem_count,
    );
    if (rc != 0) {
        return writeFailure(
            writer,
            rc,
            abi.TDNFRepoMdNativeTransactionLastError(),
        );
    }
    defer if (order_lines != null) TDNFFreeStringArray(order_lines);
    defer if (problem_lines != null) TDNFFreeStringArray(problem_lines);

    try writer.writeAll("{\"rc\":0,\"order\":[");
    for (0..order_count) |index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll(std.mem.span(order_lines[index]));
    }
    try writer.writeAll("],\"problems\":[");
    for (0..problem_count) |index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print(
            "{f}",
            .{std.json.fmt(std.mem.span(problem_lines[index]), .{})},
        );
    }
    try writer.writeAll("]}\n");
}

fn optionalZ(
    allocator: std.mem.Allocator,
    owned: *std.array_list.Managed([:0]u8),
    value: ?[]const u8,
) ![*c]const u8 {
    const text = value orelse return null;
    const copy = try allocator.dupeZ(u8, text);
    try owned.append(copy);
    return copy.ptr;
}

fn runReleaseVersion(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    root: []const u8,
    provide: []const u8,
) !void {
    const root_z = try allocator.dupeZ(u8, root);
    defer allocator.free(root_z);
    const provide_z = try allocator.dupeZ(u8, provide);
    defer allocator.free(provide_z);

    var value: [*c]u8 = null;
    const rc = TDNFGetReleaseVersion(root_z.ptr, provide_z.ptr, &value);
    defer if (value != null) TDNFFreeMemory(value);
    try writer.print(
        "{{\"rc\":{d},\"value\":{f}}}\n",
        .{ rc, std.json.fmt(spanOptional(value), .{}) },
    );
}

fn runRetainedSource(
    allocator: std.mem.Allocator,
    path: []const u8,
    target: []const u8,
) !u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const parked_z = try std.fmt.allocPrintSentinel(
        allocator,
        "{s}.verified",
        .{path},
        0,
    );
    defer allocator.free(parked_z);

    const file = abi.tdnf_rpm_file_open(path_z.ptr) orelse return 1;
    defer abi.tdnf_rpm_file_close(file);
    const config = abi.tdnf_rpm_config_create("/") orelse return 1;
    defer abi.tdnf_rpm_config_destroy(config);
    const define = try std.fmt.allocPrintSentinel(
        allocator,
        "_topdir {s}",
        .{target},
        0,
    );
    defer allocator.free(define);
    if (abi.tdnf_rpm_config_apply_define(config, define.ptr) != 0) return 1;
    if (std.c.rename(path_z.ptr, parked_z.ptr) != 0) return 1;

    const replacement = c.fopen(path_z.ptr, "wb") orelse return 1;
    defer _ = c.fclose(replacement);
    const contents = "not an rpm";
    if (c.fwrite(contents.ptr, 1, contents.len, replacement) != contents.len) {
        return 1;
    }
    return if (abi.tdnf_rpm_file_extract_source_config(
        file,
        config,
        0,
    ) == 0) 0 else 1;
}

pub fn main(init: std.process.Init) u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const argv = init.minimal.args.vector;
    if (argv.len < 2) return 2;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.flush() catch {};
    const writer = &stdout.interface;
    const command = std.mem.span(argv[1]);

    if (std.mem.eql(u8, command, "transaction-v2")) {
        if (argv.len != 4) return 2;
        runTransactionV2(
            allocator,
            writer,
            std.mem.span(argv[2]),
            std.mem.span(argv[3]),
        ) catch return 1;
        return 0;
    }
    if (std.mem.eql(u8, command, "transaction-legacy")) {
        if (argv.len != 4) return 2;
        runTransactionLegacy(
            allocator,
            writer,
            std.mem.span(argv[2]),
            std.mem.span(argv[3]),
        ) catch return 1;
        return 0;
    }
    if (std.mem.eql(u8, command, "release-version")) {
        if (argv.len != 4) return 2;
        runReleaseVersion(
            allocator,
            writer,
            std.mem.span(argv[2]),
            std.mem.span(argv[3]),
        ) catch return 1;
        return 0;
    }
    if (std.mem.eql(u8, command, "retained-source")) {
        if (argv.len != 4) return 2;
        return runRetainedSource(
            allocator,
            std.mem.span(argv[2]),
            std.mem.span(argv[3]),
        ) catch 1;
    }
    return 2;
}
