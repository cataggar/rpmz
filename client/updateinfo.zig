// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const errors = @import("tdnf_error");

pub const c = @import("client_abi").C;

pub const Ops = struct {
    context: ?*anyopaque = null,
    refresh: *const fn (?*anyopaque, ?*c.TDNF) u32,
    allocateMemory: *const fn (?*anyopaque, usize, usize, *?*anyopaque) u32,
    allocateString: *const fn (?*anyopaque, ?[*:0]const u8, [*c][*c]u8) u32,
    freeMemory: *const fn (?*anyopaque, ?*anyopaque) void,
    freeStringArray: *const fn (?*anyopaque, [*c][*c]u8) void,
    buildRepoInputs: *const fn (
        ?*anyopaque,
        ?*c.TDNF,
        *c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
        *u32,
    ) u32,
    freeRepoInputs: *const fn (
        ?*anyopaque,
        c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
        u32,
    ) void,
    querySummary: *const fn (
        ?*anyopaque,
        c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
        u32,
        ?*const c.tdnf_rpm_config,
        [*c][*c]u8,
        u32,
        ?[*:0]const u8,
        *[*c][*c]u8,
        *u32,
    ) u32,
    buildSummary: *const fn (
        ?*anyopaque,
        [*c][*c]u8,
        u32,
        *c.PTDNF_UPDATEINFO_SUMMARY,
    ) u32,
    freeSummary: *const fn (?*anyopaque, c.PTDNF_UPDATEINFO_SUMMARY) void,
    updateInfo: *const fn (
        ?*anyopaque,
        ?*c.TDNF,
        [*c][*c]u8,
        *c.PTDNF_UPDATEINFO,
    ) u32,
    freeUpdateInfo: *const fn (?*anyopaque, c.PTDNF_UPDATEINFO) void,
};

fn cString(value: [*c]u8) ?[*:0]const u8 {
    if (value == null) return null;
    return @ptrCast(value);
}

fn optionNameEquals(value: [*c]u8, expected: []const u8) ?bool {
    const name = cString(value) orelse return null;
    return std.ascii.eqlIgnoreCase(std.mem.span(name), expected);
}

fn clearSecuritySeverity(
    security_out: [*c]u32,
    severity_out: [*c][*c]u8,
) void {
    if (security_out != null) security_out[0] = 0;
    if (severity_out != null) severity_out[0] = null;
}

pub fn securitySeverityOptionWithOps(
    handle: ?*c.TDNF,
    security_out: [*c]u32,
    severity_out: [*c][*c]u8,
    ops: Ops,
) u32 {
    clearSecuritySeverity(security_out, severity_out);
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (security_out == null or severity_out == null or
        tdnf.pArgs == null or tdnf.pArgs[0].cn_setopts == null)
    {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var security: u32 = 0;
    var severity: [*c]u8 = null;
    var node = tdnf.pArgs[0].cn_setopts[0].first_child;
    while (node != null) : (node = node[0].next) {
        const is_severity = optionNameEquals(node[0].name, "sec-severity") orelse {
            ops.freeMemory(ops.context, @ptrCast(severity));
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        };
        if (is_severity) {
            var replacement: [*c]u8 = null;
            const result = ops.allocateString(
                ops.context,
                cString(node[0].value),
                &replacement,
            );
            if (result != 0) {
                ops.freeMemory(ops.context, @ptrCast(severity));
                return result;
            }
            ops.freeMemory(ops.context, @ptrCast(severity));
            severity = replacement;
        }

        const is_security = optionNameEquals(node[0].name, "security") orelse {
            ops.freeMemory(ops.context, @ptrCast(severity));
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        };
        if (is_security) security = 1;
    }

    security_out[0] = security;
    severity_out[0] = severity;
    return 0;
}

pub fn rebootRequiredOption(
    handle: ?*c.TDNF,
    reboot_out: [*c]u32,
) u32 {
    if (reboot_out != null) reboot_out[0] = 0;
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (reboot_out == null or tdnf.pArgs == null or
        tdnf.pArgs[0].cn_setopts == null)
    {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var node = tdnf.pArgs[0].cn_setopts[0].first_child;
    while (node != null) : (node = node[0].next) {
        const matches = optionNameEquals(node[0].name, "reboot-required") orelse
            return errors.ERROR_TDNF_INVALID_PARAMETER;
        if (matches) {
            reboot_out[0] = 1;
            break;
        }
    }
    return 0;
}

pub fn updateInfoSummaryWithOps(
    handle: ?*c.TDNF,
    package_specs: [*c][*c]u8,
    summary_out: [*c]c.PTDNF_UPDATEINFO_SUMMARY,
    ops: Ops,
) u32 {
    if (summary_out != null) summary_out[0] = null;
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (summary_out == null or tdnf.pSack == null) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var result: u32 = 0;
    var severity: [*c]u8 = null;
    var repos: c.PTDNF_REPOMD_NATIVE_REPO_INPUT = null;
    var repo_count: u32 = 0;
    var lines: [*c][*c]u8 = null;
    var line_count: u32 = 0;
    var summary: c.PTDNF_UPDATEINFO_SUMMARY = null;
    defer {
        ops.freeStringArray(ops.context, lines);
        ops.freeRepoInputs(ops.context, repos, repo_count);
        ops.freeMemory(ops.context, @ptrCast(severity));
        if (result != 0) ops.freeSummary(ops.context, summary);
    }

    result = ops.refresh(ops.context, tdnf);
    if (result != 0) return result;
    if (tdnf.pSack == null) {
        result = errors.ERROR_TDNF_INVALID_PARAMETER;
        return result;
    }

    var security: u32 = 0;
    result = securitySeverityOptionWithOps(
        tdnf,
        &security,
        &severity,
        ops,
    );
    if (result != 0) return result;

    result = ops.buildRepoInputs(ops.context, tdnf, &repos, &repo_count);
    if (result != 0) return result;

    result = ops.querySummary(
        ops.context,
        repos,
        repo_count,
        if (tdnf.pRpmConfig == null) null else @ptrCast(tdnf.pRpmConfig),
        package_specs,
        security,
        cString(severity),
        &lines,
        &line_count,
    );
    if (result != 0) return result;

    result = ops.buildSummary(
        ops.context,
        lines,
        line_count,
        &summary,
    );
    if (result != 0) return result;

    summary_out[0] = summary;
    return 0;
}

fn countUpdatePackages(info_head: c.PTDNF_UPDATEINFO) usize {
    var count: usize = 0;
    var info = info_head;
    while (info != null) : (info = info[0].pNext) {
        var package = info[0].pPackages;
        while (package != null) : (package = package[0].pNext) {
            count += 1;
        }
    }
    return count;
}

pub fn getUpdatePkgsWithOps(
    handle: ?*c.TDNF,
    packages_out: [*c][*c][*c]u8,
    count_out: [*c]u32,
    ops: Ops,
) u32 {
    if (packages_out != null) packages_out[0] = null;
    if (count_out != null) count_out[0] = 0;
    const tdnf = handle orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (packages_out == null or count_out == null) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var empty_specs = [_][*c]u8{null};
    var update_info: c.PTDNF_UPDATEINFO = null;
    var result = ops.updateInfo(
        ops.context,
        tdnf,
        @ptrCast(&empty_specs),
        &update_info,
    );
    defer ops.freeUpdateInfo(ops.context, update_info);
    if (result != 0) return result;

    const count = countUpdatePackages(update_info);
    if (count == 0) return 0;
    if (count > std.math.maxInt(u32)) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    var raw: ?*anyopaque = null;
    result = ops.allocateMemory(
        ops.context,
        count + 1,
        @sizeOf([*c]u8),
        &raw,
    );
    if (result != 0) return result;

    const packages: [*c][*c]u8 = @ptrCast(@alignCast(raw.?));
    packages[count] = null;
    var index: usize = 0;
    var info = update_info;
    while (info != null) : (info = info[0].pNext) {
        var package = info[0].pPackages;
        while (package != null) : (package = package[0].pNext) {
            result = ops.allocateString(
                ops.context,
                cString(package[0].pszName),
                &packages[index],
            );
            if (result != 0) {
                ops.freeStringArray(ops.context, packages);
                return result;
            }
            index += 1;
        }
    }

    packages_out[0] = packages;
    count_out[0] = @intCast(count);
    return 0;
}

const testing = std.testing;

const Fixture = struct {
    refresh_result: u32 = 0,
    clear_sack_on_refresh: bool = false,
    repo_result: u32 = 0,
    query_result: u32 = 0,
    summary_result: u32 = 0,
    update_result: u32 = 0,
    fail_string_at: usize = std.math.maxInt(usize),
    string_calls: usize = 0,
    memory_result: u32 = 0,
    refresh_calls: usize = 0,
    repo_free_calls: usize = 0,
    lines_free_calls: usize = 0,
    summary_free_calls: usize = 0,
    update_free_calls: usize = 0,
    memory_free_calls: usize = 0,
    string_array_free_calls: usize = 0,
    observed_security: u32 = 0,
    observed_severity: [32]u8 = undefined,
    observed_severity_len: usize = 0,
    observed_specs: [*c][*c]u8 = null,
    observed_config: ?*const c.tdnf_rpm_config = null,
    update_info: c.PTDNF_UPDATEINFO = null,
    line_storage: [2][*c]u8 = .{
        @constCast(@as([*:0]const u8, "1\x1f0")),
        null,
    },
};

fn fixture(context: ?*anyopaque) *Fixture {
    return @ptrCast(@alignCast(context.?));
}

fn testRefresh(context: ?*anyopaque, handle: ?*c.TDNF) u32 {
    const state = fixture(context);
    state.refresh_calls += 1;
    if (state.clear_sack_on_refresh and handle != null) {
        handle.?.pSack = null;
    }
    return state.refresh_result;
}

fn testAllocateMemory(
    context: ?*anyopaque,
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32 {
    const state = fixture(context);
    if (state.memory_result != 0) {
        output.* = null;
        return state.memory_result;
    }
    output.* = std.c.calloc(count, size);
    return if (output.* == null) errors.ERROR_TDNF_OUT_OF_MEMORY else 0;
}

fn testAllocateString(
    context: ?*anyopaque,
    source: ?[*:0]const u8,
    output: [*c][*c]u8,
) u32 {
    const state = fixture(context);
    const call_index = state.string_calls;
    state.string_calls += 1;
    output[0] = null;
    if (call_index == state.fail_string_at) {
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    }
    const text = source orelse return errors.ERROR_TDNF_INVALID_PARAMETER;
    const bytes = std.mem.span(text);
    const raw = std.c.calloc(bytes.len + 1, 1) orelse
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    const target: [*]u8 = @ptrCast(raw);
    @memcpy(target[0..bytes.len], bytes);
    output[0] = @ptrCast(target);
    return 0;
}

fn testFreeMemory(context: ?*anyopaque, memory: ?*anyopaque) void {
    if (memory != null) fixture(context).memory_free_calls += 1;
    std.c.free(memory);
}

fn testFreeStringArray(context: ?*anyopaque, values: [*c][*c]u8) void {
    const state = fixture(context);
    if (values == null) return;
    if (values == @as([*c][*c]u8, @ptrCast(&state.line_storage))) {
        state.lines_free_calls += 1;
        return;
    }
    state.string_array_free_calls += 1;
    var index: usize = 0;
    while (values[index] != null) : (index += 1) {
        std.c.free(@ptrCast(values[index]));
    }
    std.c.free(@ptrCast(values));
}

fn testBuildRepoInputs(
    context: ?*anyopaque,
    _: ?*c.TDNF,
    repos_out: *c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    count_out: *u32,
) u32 {
    const state = fixture(context);
    repos_out.* = if (state.repo_result == 0) @ptrFromInt(8) else null;
    count_out.* = if (state.repo_result == 0) 2 else 0;
    return state.repo_result;
}

fn testFreeRepoInputs(
    context: ?*anyopaque,
    repos: c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    _: u32,
) void {
    if (repos != null) fixture(context).repo_free_calls += 1;
}

fn testQuerySummary(
    context: ?*anyopaque,
    _: c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    _: u32,
    config: ?*const c.tdnf_rpm_config,
    specs: [*c][*c]u8,
    security: u32,
    severity: ?[*:0]const u8,
    lines_out: *[*c][*c]u8,
    count_out: *u32,
) u32 {
    const state = fixture(context);
    state.observed_config = config;
    state.observed_specs = specs;
    state.observed_security = security;
    if (severity) |value| {
        const text = std.mem.span(value);
        state.observed_severity_len = @min(text.len, state.observed_severity.len);
        @memcpy(
            state.observed_severity[0..state.observed_severity_len],
            text[0..state.observed_severity_len],
        );
    } else {
        state.observed_severity_len = 0;
    }
    lines_out.* = @ptrCast(&state.line_storage);
    count_out.* = 1;
    return state.query_result;
}

fn testBuildSummary(
    context: ?*anyopaque,
    _: [*c][*c]u8,
    _: u32,
    summary_out: *c.PTDNF_UPDATEINFO_SUMMARY,
) u32 {
    const state = fixture(context);
    const raw = std.c.calloc(4, @sizeOf(c.TDNF_UPDATEINFO_SUMMARY)) orelse {
        summary_out.* = null;
        return errors.ERROR_TDNF_OUT_OF_MEMORY;
    };
    summary_out.* = @ptrCast(@alignCast(raw));
    summary_out.*[1].nCount = 3;
    return state.summary_result;
}

fn testFreeSummary(
    context: ?*anyopaque,
    summary: c.PTDNF_UPDATEINFO_SUMMARY,
) void {
    if (summary == null) return;
    fixture(context).summary_free_calls += 1;
    std.c.free(@ptrCast(summary));
}

fn testUpdateInfo(
    context: ?*anyopaque,
    _: ?*c.TDNF,
    _: [*c][*c]u8,
    info_out: *c.PTDNF_UPDATEINFO,
) u32 {
    const state = fixture(context);
    info_out.* = state.update_info;
    return state.update_result;
}

fn testFreeUpdateInfo(
    context: ?*anyopaque,
    info: c.PTDNF_UPDATEINFO,
) void {
    if (info != null) fixture(context).update_free_calls += 1;
}

fn testOps(state: *Fixture) Ops {
    return .{
        .context = state,
        .refresh = testRefresh,
        .allocateMemory = testAllocateMemory,
        .allocateString = testAllocateString,
        .freeMemory = testFreeMemory,
        .freeStringArray = testFreeStringArray,
        .buildRepoInputs = testBuildRepoInputs,
        .freeRepoInputs = testFreeRepoInputs,
        .querySummary = testQuerySummary,
        .buildSummary = testBuildSummary,
        .freeSummary = testFreeSummary,
        .updateInfo = testUpdateInfo,
        .freeUpdateInfo = testFreeUpdateInfo,
    };
}

fn setoptNode(name: [*:0]const u8, value: ?[*:0]const u8) c.cnfnode {
    var node = std.mem.zeroes(c.cnfnode);
    node.name = @constCast(name);
    node.value = if (value) |text| @constCast(text) else null;
    return node;
}

fn testHandle(args: *c.TDNF_CMD_ARGS) c.TDNF {
    var handle = std.mem.zeroes(c.TDNF);
    handle.pSack = @ptrFromInt(8);
    handle.pArgs = args;
    handle.pRpmConfig = @ptrFromInt(16);
    return handle;
}

test "invalid arguments and null nested setopt state reset outputs" {
    var state = Fixture{};
    const ops = testOps(&state);
    var security: u32 = 99;
    var severity: [*c]u8 = @ptrFromInt(24);
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        securitySeverityOptionWithOps(null, &security, &severity, ops),
    );
    try testing.expectEqual(@as(u32, 0), security);
    try testing.expectEqual(@as([*c]u8, null), severity);

    var args = std.mem.zeroes(c.TDNF_CMD_ARGS);
    var handle = testHandle(&args);
    var reboot: u32 = 99;
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        rebootRequiredOption(&handle, &reboot),
    );
    try testing.expectEqual(@as(u32, 0), reboot);

    var summary: c.PTDNF_UPDATEINFO_SUMMARY = @ptrFromInt(32);
    handle.pSack = null;
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        updateInfoSummaryWithOps(&handle, null, &summary, ops),
    );
    try testing.expectEqual(@as(c.PTDNF_UPDATEINFO_SUMMARY, null), summary);

    var packages: [*c][*c]u8 = @ptrFromInt(40);
    var count: u32 = 99;
    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        getUpdatePkgsWithOps(null, &packages, &count, ops),
    );
    try testing.expectEqual(@as([*c][*c]u8, null), packages);
    try testing.expectEqual(@as(u32, 0), count);
}

test "setopts are case insensitive and the last severity wins" {
    var state = Fixture{};
    const ops = testOps(&state);
    var first = setoptNode("SeCuRiTy", null);
    var second = setoptNode("sec-severity", "5.0");
    var third = setoptNode("security", null);
    var fourth = setoptNode("SEC-SEVERITY", "9.8");
    var fifth = setoptNode("ReBoOt-ReQuIrEd", null);
    var sixth = setoptNode("reboot-required", null);
    first.next = &second;
    second.next = &third;
    third.next = &fourth;
    fourth.next = &fifth;
    fifth.next = &sixth;
    var root = std.mem.zeroes(c.cnfnode);
    root.first_child = &first;
    var args = std.mem.zeroes(c.TDNF_CMD_ARGS);
    args.cn_setopts = &root;
    var handle = testHandle(&args);

    var security: u32 = 0;
    var severity: [*c]u8 = null;
    try testing.expectEqual(
        @as(u32, 0),
        securitySeverityOptionWithOps(&handle, &security, &severity, ops),
    );
    defer testFreeMemory(&state, @ptrCast(severity));
    try testing.expectEqual(@as(u32, 1), security);
    try testing.expectEqualStrings("9.8", std.mem.span(cString(severity).?));
    try testing.expectEqual(@as(usize, 1), state.memory_free_calls);

    var reboot: u32 = 0;
    try testing.expectEqual(@as(u32, 0), rebootRequiredOption(&handle, &reboot));
    try testing.expectEqual(@as(u32, 1), reboot);
}

test "summary forwards native inputs and cleans all temporary ownership" {
    var state = Fixture{};
    const ops = testOps(&state);
    var security = setoptNode("security", null);
    var severity = setoptNode("sec-severity", "critical");
    security.next = &severity;
    var root = std.mem.zeroes(c.cnfnode);
    root.first_child = &security;
    var args = std.mem.zeroes(c.TDNF_CMD_ARGS);
    args.cn_setopts = &root;
    var handle = testHandle(&args);
    var specs = [_][*c]u8{
        @constCast(@as([*:0]const u8, "kernel*")),
        null,
    };
    var summary: c.PTDNF_UPDATEINFO_SUMMARY = null;

    try testing.expectEqual(
        @as(u32, 0),
        updateInfoSummaryWithOps(&handle, @ptrCast(&specs), &summary, ops),
    );
    defer testFreeSummary(&state, summary);
    try testing.expect(summary != null);
    try testing.expectEqual(@as(c_int, 3), summary[1].nCount);
    try testing.expectEqual(@as(usize, 1), state.refresh_calls);
    try testing.expectEqual(@as(u32, 1), state.observed_security);
    try testing.expectEqualStrings(
        "critical",
        state.observed_severity[0..state.observed_severity_len],
    );
    try testing.expectEqual(@as([*c][*c]u8, @ptrCast(&specs)), state.observed_specs);
    try testing.expect(state.observed_config != null);
    try testing.expectEqual(@as(usize, 1), state.repo_free_calls);
    try testing.expectEqual(@as(usize, 1), state.lines_free_calls);
    try testing.expectEqual(@as(usize, 1), state.memory_free_calls);
    try testing.expectEqual(@as(usize, 0), state.summary_free_calls);
}

test "summary errors propagate and clean partial outputs" {
    var state = Fixture{ .summary_result = 1777 };
    const ops = testOps(&state);
    var root = std.mem.zeroes(c.cnfnode);
    var args = std.mem.zeroes(c.TDNF_CMD_ARGS);
    args.cn_setopts = &root;
    var handle = testHandle(&args);
    var summary: c.PTDNF_UPDATEINFO_SUMMARY = @ptrFromInt(32);

    try testing.expectEqual(
        @as(u32, 1777),
        updateInfoSummaryWithOps(&handle, null, &summary, ops),
    );
    try testing.expectEqual(@as(c.PTDNF_UPDATEINFO_SUMMARY, null), summary);
    try testing.expectEqual(@as(usize, 1), state.repo_free_calls);
    try testing.expectEqual(@as(usize, 1), state.lines_free_calls);
    try testing.expectEqual(@as(usize, 1), state.summary_free_calls);
}

test "summary rejects a native package context lost during refresh" {
    var state = Fixture{ .clear_sack_on_refresh = true };
    const ops = testOps(&state);
    var root = std.mem.zeroes(c.cnfnode);
    var args = std.mem.zeroes(c.TDNF_CMD_ARGS);
    args.cn_setopts = &root;
    var handle = testHandle(&args);
    var summary: c.PTDNF_UPDATEINFO_SUMMARY = @ptrFromInt(32);

    try testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        updateInfoSummaryWithOps(&handle, null, &summary, ops),
    );
    try testing.expectEqual(@as(c.PTDNF_UPDATEINFO_SUMMARY, null), summary);
    try testing.expectEqual(@as(usize, 1), state.refresh_calls);
    try testing.expectEqual(@as(usize, 0), state.repo_free_calls);
}

test "no update packages returns a null zero result" {
    var state = Fixture{};
    const ops = testOps(&state);
    var handle = std.mem.zeroes(c.TDNF);
    var packages: [*c][*c]u8 = @ptrFromInt(40);
    var count: u32 = 99;

    try testing.expectEqual(
        @as(u32, 0),
        getUpdatePkgsWithOps(&handle, &packages, &count, ops),
    );
    try testing.expectEqual(@as([*c][*c]u8, null), packages);
    try testing.expectEqual(@as(u32, 0), count);
}

test "update package collection counts multiple advisories and terminates" {
    var pkg1 = std.mem.zeroes(c.TDNF_UPDATEINFO_PKG);
    var pkg2 = std.mem.zeroes(c.TDNF_UPDATEINFO_PKG);
    var pkg3 = std.mem.zeroes(c.TDNF_UPDATEINFO_PKG);
    pkg1.pszName = @constCast(@as([*:0]const u8, "alpha"));
    pkg2.pszName = @constCast(@as([*:0]const u8, "beta"));
    pkg3.pszName = @constCast(@as([*:0]const u8, "gamma"));
    pkg1.pNext = &pkg2;
    var info1 = std.mem.zeroes(c.TDNF_UPDATEINFO);
    var info2 = std.mem.zeroes(c.TDNF_UPDATEINFO);
    info1.pPackages = &pkg1;
    info1.pNext = &info2;
    info2.pPackages = &pkg3;
    var state = Fixture{ .update_info = &info1 };
    const ops = testOps(&state);
    var handle = std.mem.zeroes(c.TDNF);
    var packages: [*c][*c]u8 = null;
    var count: u32 = 0;

    try testing.expectEqual(
        @as(u32, 0),
        getUpdatePkgsWithOps(&handle, &packages, &count, ops),
    );
    defer testFreeStringArray(&state, packages);
    try testing.expectEqual(@as(u32, 3), count);
    try testing.expectEqualStrings("alpha", std.mem.span(cString(packages[0]).?));
    try testing.expectEqualStrings("beta", std.mem.span(cString(packages[1]).?));
    try testing.expectEqualStrings("gamma", std.mem.span(cString(packages[2]).?));
    try testing.expectEqual(@as([*c]u8, null), packages[3]);
    try testing.expectEqual(@as(usize, 1), state.update_free_calls);
}

test "partial package string allocation failure cleans and resets outputs" {
    var pkg1 = std.mem.zeroes(c.TDNF_UPDATEINFO_PKG);
    var pkg2 = std.mem.zeroes(c.TDNF_UPDATEINFO_PKG);
    pkg1.pszName = @constCast(@as([*:0]const u8, "alpha"));
    pkg2.pszName = @constCast(@as([*:0]const u8, "beta"));
    pkg1.pNext = &pkg2;
    var info = std.mem.zeroes(c.TDNF_UPDATEINFO);
    info.pPackages = &pkg1;
    var state = Fixture{
        .fail_string_at = 1,
        .update_info = &info,
    };
    const ops = testOps(&state);
    var handle = std.mem.zeroes(c.TDNF);
    var packages: [*c][*c]u8 = @ptrFromInt(40);
    var count: u32 = 99;

    try testing.expectEqual(
        errors.ERROR_TDNF_OUT_OF_MEMORY,
        getUpdatePkgsWithOps(&handle, &packages, &count, ops),
    );
    try testing.expectEqual(@as([*c][*c]u8, null), packages);
    try testing.expectEqual(@as(u32, 0), count);
    try testing.expectEqual(@as(usize, 1), state.string_array_free_calls);
    try testing.expectEqual(@as(usize, 1), state.update_free_calls);
}

test "canonical updateinfo ABI layouts remain C compatible" {
    try testing.expectEqual(@as(usize, 2 * @sizeOf(c_int)), @sizeOf(c.TDNF_UPDATEINFO_SUMMARY));
    try testing.expectEqual(@as(usize, 0), @offsetOf(c.TDNF_UPDATEINFO_SUMMARY, "nCount"));
    try testing.expectEqual(@as(usize, @sizeOf(c_int)), @offsetOf(c.TDNF_UPDATEINFO_SUMMARY, "nType"));
    try testing.expectEqual(@as(usize, 5 * @sizeOf(?*anyopaque)), @sizeOf(c.TDNF_UPDATEINFO_PKG));
    try testing.expectEqual(@as(usize, 4 * @sizeOf(?*anyopaque)), @offsetOf(c.TDNF_UPDATEINFO_PKG, "pNext"));
}
