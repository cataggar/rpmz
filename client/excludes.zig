// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const common = @import("rpmz_common");
const errors = @import("rpmz_error");
const abi = @import("client_abi");
const CnfNode = abi.CnfNode;
const CmdArgs = abi.CmdArgs;
const Conf = abi.Conf;
const Tdnf = abi.Tdnf;

extern fn TDNFAllocateMemory(
    count: usize,
    size: usize,
    output: *?*anyopaque,
) callconv(.c) u32;
extern fn TDNFAllocateString(
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFFreeStringArray(values: ?[*]?[*:0]u8) callconv(.c) void;

const LOG_INFO: c_int = 0;

const Ops = struct {
    context: ?*anyopaque = null,
    allocateMemory: *const fn (
        context: ?*anyopaque,
        count: usize,
        size: usize,
        output: *?*anyopaque,
    ) u32,
    allocateString: *const fn (
        context: ?*anyopaque,
        source: ?[*:0]const u8,
        output: *?[*:0]u8,
    ) u32,
    freeStringArray: *const fn (
        context: ?*anyopaque,
        values: ?[*]?[*:0]u8,
    ) void,
    logConfiguredHeader: *const fn (context: ?*anyopaque) void,
    logConfiguredValue: *const fn (
        context: ?*anyopaque,
        value: [*:0]const u8,
    ) void,
};

fn productionAllocateMemory(
    _: ?*anyopaque,
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32 {
    return TDNFAllocateMemory(count, size, output);
}

fn productionAllocateString(
    _: ?*anyopaque,
    source: ?[*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    return TDNFAllocateString(source, output);
}

fn productionFreeStringArray(
    _: ?*anyopaque,
    values: ?[*]?[*:0]u8,
) void {
    TDNFFreeStringArray(values);
}

fn productionLogConfiguredHeader(_: ?*anyopaque) void {
    common.log(LOG_INFO, "Warning: The following packages are excluded from rpmz.conf:\n", .{});
}

fn productionLogConfiguredValue(_: ?*anyopaque, value: [*:0]const u8) void {
    common.log(LOG_INFO, "  %s\n", .{value});
}

const production_ops = Ops{
    .allocateMemory = productionAllocateMemory,
    .allocateString = productionAllocateString,
    .freeStringArray = productionFreeStringArray,
    .logConfiguredHeader = productionLogConfiguredHeader,
    .logConfiguredValue = productionLogConfiguredValue,
};

fn isExcludeOption(name: [*:0]const u8) bool {
    return std.ascii.eqlIgnoreCase(std.mem.span(name), "exclude");
}

fn pkgsToExcludeWithOps(
    handle_opt: ?*Tdnf,
    count_out: ?*u32,
    values_out: ?*?[*]?[*:0]u8,
    ops: Ops,
) u32 {
    const handle = handle_opt orelse {
        if (count_out) |output| output.* = 0;
        if (values_out) |output| output.* = null;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (handle.pArgs == null or count_out == null or values_out == null) {
        if (count_out) |output| output.* = 0;
        if (values_out) |output| output.* = null;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    const args = handle.pArgs.?;
    const conf = handle.pConf.?;
    var count: usize = 0;

    if (args.nDisableExcludes == 0) {
        if (conf.ppszExcludes) |configured| {
            ops.logConfiguredHeader(ops.context);
            while (configured[count]) |value| : (count += 1) {
                ops.logConfiguredValue(ops.context, value);
            }
        }
    }

    var node = args.cn_setopts.?.first_child;
    while (node) |current| : (node = current.next) {
        if (isExcludeOption(current.name.?)) count += 1;
    }

    var values: ?[*]?[*:0]u8 = null;
    if (count != 0) {
        var raw: ?*anyopaque = null;
        var result = ops.allocateMemory(
            ops.context,
            count + 1,
            @sizeOf(?[*:0]u8),
            &raw,
        );
        if (result != 0) {
            count_out.?.* = 0;
            values_out.?.* = null;
            return result;
        }
        values = @ptrCast(@alignCast(raw.?));

        var output_index: usize = 0;
        if (args.nDisableExcludes == 0) {
            if (conf.ppszExcludes) |configured| {
                while (configured[output_index]) |value| : (output_index += 1) {
                    result = ops.allocateString(
                        ops.context,
                        value,
                        &values.?[output_index],
                    );
                    if (result != 0) {
                        ops.freeStringArray(ops.context, values);
                        count_out.?.* = 0;
                        values_out.?.* = null;
                        return result;
                    }
                }
            }
        }

        node = args.cn_setopts.?.first_child;
        while (node) |current| : (node = current.next) {
            if (isExcludeOption(current.name.?)) {
                result = ops.allocateString(
                    ops.context,
                    current.value,
                    &values.?[output_index],
                );
                if (result != 0) {
                    ops.freeStringArray(ops.context, values);
                    count_out.?.* = 0;
                    values_out.?.* = null;
                    return result;
                }
                output_index += 1;
            }
        }
    }

    // client.c incremented the count again while copying configured values.
    // That made the reported count larger than both the allocation and the
    // NULL-terminated contents. Return the number counted before allocation.
    count_out.?.* = @intCast(count);
    values_out.?.* = values;
    return 0;
}

export fn TDNFPkgsToExclude(
    handle: ?*Tdnf,
    count_out: ?*u32,
    values_out: ?*?[*]?[*:0]u8,
) callconv(.c) u32 {
    return pkgsToExcludeWithOps(handle, count_out, values_out, production_ops);
}

extern fn create_cnfnode(name: ?[*:0]const u8) callconv(.c) ?*CnfNode;
extern fn cnfnode_setval(
    node: ?*CnfNode,
    value: ?[*:0]const u8,
) callconv(.c) void;
extern fn append_node(parent: ?*CnfNode, node: ?*CnfNode) callconv(.c) void;
extern fn destroy_cnftree(node: ?*CnfNode) callconv(.c) void;
extern fn calloc(count: usize, size: usize) callconv(.c) ?*anyopaque;
extern fn free(memory: ?*anyopaque) callconv(.c) void;

const testing = std.testing;

const Fixture = struct {
    args: CmdArgs = .{},
    conf: Conf = .{},
    handle: Tdnf = .{},
    setopts: *CnfNode,

    fn init() !Fixture {
        const root = create_cnfnode("(root)") orelse
            return error.TestUnexpectedNull;
        var fixture = Fixture{ .setopts = root };
        fixture.args.cn_setopts = root;
        fixture.handle.pArgs = &fixture.args;
        fixture.handle.pConf = &fixture.conf;
        return fixture;
    }

    fn rebind(self: *Fixture) void {
        self.args.cn_setopts = self.setopts;
        self.handle.pArgs = &self.args;
        self.handle.pConf = &self.conf;
    }

    fn deinit(self: *Fixture) void {
        destroy_cnftree(self.setopts);
    }

    fn addSetopt(
        self: *Fixture,
        name: [*:0]const u8,
        value: [*:0]const u8,
    ) !void {
        const node = create_cnfnode(name) orelse
            return error.TestUnexpectedNull;
        cnfnode_setval(node, value);
        append_node(self.setopts, node);
    }
};

fn expectValues(
    values: ?[*]?[*:0]u8,
    expected: []const []const u8,
) !void {
    const actual = values orelse return error.TestUnexpectedNull;
    for (expected, 0..) |value, index| {
        try testing.expectEqualStrings(value, std.mem.span(actual[index].?));
    }
    try testing.expect(actual[expected.len] == null);
}

test "invalid arguments clear available outputs" {
    var count: u32 = 99;
    var values: ?[*]?[*:0]u8 = @ptrFromInt(@alignOf(?[*:0]u8));
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFPkgsToExclude(null, &count, &values),
    );
    try testing.expectEqual(@as(u32, 0), count);
    try testing.expect(values == null);

    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.rebind();
    fixture.handle.pArgs = null;
    count = 99;
    values = @ptrFromInt(@alignOf(?[*:0]u8));
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFPkgsToExclude(&fixture.handle, &count, &values),
    );
    try testing.expectEqual(@as(u32, 0), count);
    try testing.expect(values == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFPkgsToExclude(&fixture.handle, null, &values),
    );
    try testing.expect(values == null);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFPkgsToExclude(&fixture.handle, &count, null),
    );
    try testing.expectEqual(@as(u32, 0), count);
}

test "no exclusions returns an empty owned result" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.rebind();

    var count: u32 = 99;
    var values: ?[*]?[*:0]u8 = @ptrFromInt(@alignOf(?[*:0]u8));
    try testing.expectEqual(
        @as(u32, 0),
        TDNFPkgsToExclude(&fixture.handle, &count, &values),
    );
    try testing.expectEqual(@as(u32, 0), count);
    try testing.expect(values == null);
}

const LogCapture = struct {
    headers: usize = 0,
    count: usize = 0,
    values: [4]?[*:0]const u8 = .{ null, null, null, null },
};

fn captureHeader(context: ?*anyopaque) void {
    const capture: *LogCapture = @ptrCast(@alignCast(context.?));
    capture.headers += 1;
}

fn captureValue(context: ?*anyopaque, value: [*:0]const u8) void {
    const capture: *LogCapture = @ptrCast(@alignCast(context.?));
    capture.values[capture.count] = value;
    capture.count += 1;
}

fn captureOps(capture: *LogCapture) Ops {
    return .{
        .context = capture,
        .allocateMemory = productionAllocateMemory,
        .allocateString = productionAllocateString,
        .freeStringArray = productionFreeStringArray,
        .logConfiguredHeader = captureHeader,
        .logConfiguredValue = captureValue,
    };
}

test "configured exclusions are logged copied counted and NULL terminated" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.rebind();
    var configured = [_]?[*:0]u8{ @constCast("alpha"), @constCast("beta"), null };
    fixture.conf.ppszExcludes = &configured;

    var capture = LogCapture{};
    var count: u32 = 0;
    var values: ?[*]?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        pkgsToExcludeWithOps(
            &fixture.handle,
            &count,
            &values,
            captureOps(&capture),
        ),
    );
    defer TDNFFreeStringArray(values);

    // The old C returned 4 here after counting these two entries twice.
    // Count-based consumers could then walk beyond the three-pointer array.
    try testing.expectEqual(@as(u32, 2), count);
    try expectValues(values, &.{ "alpha", "beta" });
    try testing.expect(values.?[0].? != configured[0].?);
    try testing.expectEqual(@as(usize, 1), capture.headers);
    try testing.expectEqual(@as(usize, 2), capture.count);
    try testing.expectEqualStrings("alpha", std.mem.span(capture.values[0].?));
    try testing.expectEqualStrings("beta", std.mem.span(capture.values[1].?));
}

test "disable-excludes suppresses only configured exclusions" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.rebind();
    var configured = [_]?[*:0]u8{ @constCast("configured"), null };
    fixture.conf.ppszExcludes = &configured;
    fixture.args.nDisableExcludes = 1;
    try fixture.addSetopt("exclude", "setopt");

    var capture = LogCapture{};
    var count: u32 = 0;
    var values: ?[*]?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        pkgsToExcludeWithOps(
            &fixture.handle,
            &count,
            &values,
            captureOps(&capture),
        ),
    );
    defer TDNFFreeStringArray(values);

    try testing.expectEqual(@as(u32, 1), count);
    try expectValues(values, &.{"setopt"});
    try testing.expectEqual(@as(usize, 0), capture.headers);
    try testing.expectEqual(@as(usize, 0), capture.count);
}

test "setopt exclusion matching is case insensitive" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.rebind();
    try fixture.addSetopt("EXCLUDE", "upper");
    try fixture.addSetopt("Exclude", "mixed");
    try fixture.addSetopt("other", "ignored");

    var count: u32 = 0;
    var values: ?[*]?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        TDNFPkgsToExclude(&fixture.handle, &count, &values),
    );
    defer TDNFFreeStringArray(values);

    try testing.expectEqual(@as(u32, 2), count);
    try expectValues(values, &.{ "upper", "mixed" });
}

test "configured exclusions precede setopt exclusions" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.rebind();
    var configured = [_]?[*:0]u8{ @constCast("configured-a"), @constCast("configured-b"), null };
    fixture.conf.ppszExcludes = &configured;
    try fixture.addSetopt("exclude", "setopt-a");
    try fixture.addSetopt("exclude", "setopt-b");

    var capture = LogCapture{};
    var count: u32 = 0;
    var values: ?[*]?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        pkgsToExcludeWithOps(
            &fixture.handle,
            &count,
            &values,
            captureOps(&capture),
        ),
    );
    defer TDNFFreeStringArray(values);

    try testing.expectEqual(@as(u32, 4), count);
    try expectValues(
        values,
        &.{ "configured-a", "configured-b", "setopt-a", "setopt-b" },
    );
}

const FailingAllocator = struct {
    fail_at: usize,
    calls: usize = 0,
    live: usize = 0,

    fn shouldFail(self: *FailingAllocator) bool {
        defer self.calls += 1;
        return self.calls == self.fail_at;
    }
};

fn failingAllocateMemory(
    context: ?*anyopaque,
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32 {
    const state: *FailingAllocator = @ptrCast(@alignCast(context.?));
    output.* = null;
    if (state.shouldFail()) return errors.ERROR_TDNF_OUT_OF_MEMORY;
    const memory = calloc(count, size) orelse
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    state.live += 1;
    output.* = memory;
    return 0;
}

fn failingAllocateString(
    context: ?*anyopaque,
    source_opt: ?[*:0]const u8,
    output: *?[*:0]u8,
) u32 {
    const source = source_opt orelse {
        output.* = null;
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    };
    const state: *FailingAllocator = @ptrCast(@alignCast(context.?));
    if (state.shouldFail()) return errors.ERROR_TDNF_OUT_OF_MEMORY;
    const len = std.mem.len(source);
    const raw = calloc(len + 1, 1) orelse
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    const value: [*]u8 = @ptrCast(raw);
    @memcpy(value[0..len], source[0..len]);
    state.live += 1;
    output.* = @ptrCast(value);
    return 0;
}

fn failingFreeStringArray(
    context: ?*anyopaque,
    values_opt: ?[*]?[*:0]u8,
) void {
    const values = values_opt orelse return;
    const state: *FailingAllocator = @ptrCast(@alignCast(context.?));
    var index: usize = 0;
    while (values[index]) |value| : (index += 1) {
        free(value);
        state.live -= 1;
    }
    free(@ptrCast(values));
    state.live -= 1;
}

fn ignoreHeader(_: ?*anyopaque) void {}
fn ignoreValue(_: ?*anyopaque, _: [*:0]const u8) void {}

fn failingOps(state: *FailingAllocator) Ops {
    return .{
        .context = state,
        .allocateMemory = failingAllocateMemory,
        .allocateString = failingAllocateString,
        .freeStringArray = failingFreeStringArray,
        .logConfiguredHeader = ignoreHeader,
        .logConfiguredValue = ignoreValue,
    };
}

test "every allocation failure cleans partial output and reports OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.rebind();
    var configured = [_]?[*:0]u8{ @constCast("configured-a"), @constCast("configured-b"), null };
    fixture.conf.ppszExcludes = &configured;
    try fixture.addSetopt("exclude", "setopt");

    var fail_at: usize = 0;
    while (fail_at < 4) : (fail_at += 1) {
        var state = FailingAllocator{ .fail_at = fail_at };
        var count: u32 = 99;
        var values: ?[*]?[*:0]u8 = @ptrFromInt(@alignOf(?[*:0]u8));
        try testing.expectEqual(
            errors.ERROR_TDNF_OUT_OF_MEMORY,
            pkgsToExcludeWithOps(
                &fixture.handle,
                &count,
                &values,
                failingOps(&state),
            ),
        );
        try testing.expectEqual(@as(u32, 0), count);
        try testing.expect(values == null);
        try testing.expectEqual(@as(usize, 0), state.live);
    }

    var state = FailingAllocator{ .fail_at = 4 };
    var count: u32 = 0;
    var values: ?[*]?[*:0]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        pkgsToExcludeWithOps(
            &fixture.handle,
            &count,
            &values,
            failingOps(&state),
        ),
    );
    try testing.expectEqual(@as(u32, 3), count);
    try expectValues(values, &.{ "configured-a", "configured-b", "setopt" });
    failingFreeStringArray(&state, values);
    try testing.expectEqual(@as(usize, 0), state.live);
}
