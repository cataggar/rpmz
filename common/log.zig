// Copyright (C) 2019-2023 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const libc = std.c;
const common = @import("api.zig");
const variadic = @import("variadic.zig");

extern var stdout: *libc.FILE;
extern var stderr: *libc.FILE;
extern fn commonVfprintf(
    stream: ?*anyopaque,
    format: [*:0]const u8,
    args: *variadic.VaList,
) c_int;
extern fn open_memstream(
    buffer: *?[*]u8,
    size: *usize,
) ?*libc.FILE;
extern fn fclose(stream: *libc.FILE) c_int;
extern fn free(memory: ?*anyopaque) void;
extern fn fflush(stream: *libc.FILE) c_int;

const LOG_INFO: c_int = 0;
const LOG_ERR: c_int = 1;
const LOG_CRIT: c_int = 2;
const LOG_NOTICE: c_int = 3;

var gbQuiet = false;
var gbJson = false;
var gbDnfCheckUpdateCompat = false;
var stdout_override: ?*libc.FILE = null;
var stderr_override: ?*libc.FILE = null;

fn resetGlobalStateForTest() void {
    gbQuiet = false;
    gbJson = false;
    gbDnfCheckUpdateCompat = false;
    stdout_override = null;
    stderr_override = null;
}

fn outputStream(default_stream: *libc.FILE, override: ?*libc.FILE) *libc.FILE {
    return override orelse default_stream;
}

fn rpmzLogGetStream(nLogLevel: c_int) ?*libc.FILE {
    switch (nLogLevel) {
        LOG_INFO, LOG_CRIT => {
            if (gbJson) {
                return null;
            }
            if (nLogLevel == LOG_INFO and gbQuiet) {
                return null;
            }
            return outputStream(stdout, stdout_override);
        },
        LOG_ERR => {
            return outputStream(stderr, stderr_override);
        },
        LOG_NOTICE => {
            if (gbJson or gbQuiet) {
                return null;
            }
            return outputStream(stderr, stderr_override);
        },
        else => {
            return null;
        },
    }
}

const AtomicLogContext = struct {
    id: c_int,
    count: usize,
};

fn emitAtomicLogMessages(context: *const AtomicLogContext) void {
    for (0..context.count) |sequence| {
        common.log(
            LOG_ERR,
            "thread=%d sequence=%d end\n",
            .{ context.id, @as(c_int, @intCast(sequence)) },
        );
    }
}

export fn GlobalSetQuiet(nValue: i32) void {
    if (nValue > 0) {
        gbQuiet = true;
    }
}

export fn GlobalSetJson(nValue: i32) void {
    if (nValue > 0) {
        gbJson = true;
    }
}

export fn GlobalSetDnfCheckUpdateCompat(nValue: i32) void {
    if (nValue > 0) {
        gbDnfCheckUpdateCompat = true;
    }
}

export fn GlobalGetDnfCheckUpdateCompat() bool {
    return gbDnfCheckUpdateCompat;
}

export fn TDNFLogGetStream(nLogLevel: c_int) ?*libc.FILE {
    return rpmzLogGetStream(nLogLevel);
}

export fn log_console(nLogLevel: c_int, pszFormatOpt: ?[*:0]const u8, ...) callconv(.c) void {
    const pszFormat = pszFormatOpt orelse return;
    const stream = rpmzLogGetStream(nLogLevel) orelse return;

    var args: variadic.VaList = undefined;
    if (comptime variadic.needs_manual_start) {
        variadic.startManual(&args);
    } else {
        args = @cVaStart();
    }
    defer variadic.end(&args);
    _ = commonVfprintf(stream, pszFormat, &args);
    _ = fflush(stream);
}

test "GlobalSetQuiet only suppresses info logs" {
    resetGlobalStateForTest();
    defer resetGlobalStateForTest();

    try std.testing.expect(rpmzLogGetStream(LOG_INFO) == stdout);
    try std.testing.expect(rpmzLogGetStream(LOG_CRIT) == stdout);
    try std.testing.expect(rpmzLogGetStream(LOG_ERR) == stderr);

    GlobalSetQuiet(1);
    try std.testing.expect(rpmzLogGetStream(LOG_INFO) == null);
    try std.testing.expect(rpmzLogGetStream(LOG_CRIT) == stdout);
    try std.testing.expect(rpmzLogGetStream(LOG_ERR) == stderr);

    GlobalSetQuiet(0);
    try std.testing.expect(rpmzLogGetStream(LOG_INFO) == null);
}

test "notice logs go to stderr but obey quiet and json suppression" {
    resetGlobalStateForTest();
    defer resetGlobalStateForTest();

    try std.testing.expect(rpmzLogGetStream(LOG_NOTICE) == stderr);

    GlobalSetQuiet(1);
    try std.testing.expect(rpmzLogGetStream(LOG_NOTICE) == null);

    resetGlobalStateForTest();
    GlobalSetJson(1);
    try std.testing.expect(rpmzLogGetStream(LOG_NOTICE) == null);
}

test "GlobalSetJson suppresses stdout logs and is one way" {
    resetGlobalStateForTest();
    defer resetGlobalStateForTest();

    GlobalSetJson(1);
    try std.testing.expect(rpmzLogGetStream(LOG_INFO) == null);
    try std.testing.expect(rpmzLogGetStream(LOG_CRIT) == null);
    try std.testing.expect(rpmzLogGetStream(LOG_ERR) == stderr);

    GlobalSetJson(0);
    try std.testing.expect(rpmzLogGetStream(LOG_INFO) == null);
    try std.testing.expect(rpmzLogGetStream(LOG_CRIT) == null);
}

test "GlobalSetDnfCheckUpdateCompat is one way" {
    resetGlobalStateForTest();
    defer resetGlobalStateForTest();

    try std.testing.expect(!GlobalGetDnfCheckUpdateCompat());

    GlobalSetDnfCheckUpdateCompat(0);
    try std.testing.expect(!GlobalGetDnfCheckUpdateCompat());

    GlobalSetDnfCheckUpdateCompat(1);
    try std.testing.expect(GlobalGetDnfCheckUpdateCompat());

    GlobalSetDnfCheckUpdateCompat(0);
    try std.testing.expect(GlobalGetDnfCheckUpdateCompat());
}

test "log setters ignore non positive values and unknown levels are suppressed" {
    resetGlobalStateForTest();
    defer resetGlobalStateForTest();

    GlobalSetQuiet(-1);
    GlobalSetJson(0);
    try std.testing.expect(rpmzLogGetStream(LOG_INFO) == stdout);
    try std.testing.expect(rpmzLogGetStream(99) == null);
}

test "log_console preserves levels, quiet, json, streams, and formatting" {
    resetGlobalStateForTest();
    defer resetGlobalStateForTest();

    var stdout_buffer: ?[*]u8 = null;
    var stdout_size: usize = 0;
    const stdout_memory = open_memstream(
        &stdout_buffer,
        &stdout_size,
    ) orelse return error.OutOfMemory;
    defer {
        _ = fclose(stdout_memory);
        free(stdout_buffer);
    }

    var stderr_buffer: ?[*]u8 = null;
    var stderr_size: usize = 0;
    const stderr_memory = open_memstream(
        &stderr_buffer,
        &stderr_size,
    ) orelse return error.OutOfMemory;
    defer {
        _ = fclose(stderr_memory);
        free(stderr_buffer);
    }

    stdout_override = stdout_memory;
    stderr_override = stderr_memory;

    common.log(LOG_INFO, "info %s %d\n", .{ "value", @as(c_int, 7) });
    common.log(LOG_NOTICE, "notice\n", .{});
    common.log(LOG_ERR, "error\n", .{});
    common.log(LOG_CRIT, "critical\n", .{});
    log_console(
        LOG_ERR,
        "compat %s %d %s\n",
        @as([*:0]const u8, "varargs"),
        @as(c_int, 7),
        @as(?[*:0]const u8, null),
    );

    try std.testing.expectEqualStrings(
        "info value 7\ncritical\n",
        stdout_buffer.?[0..stdout_size],
    );
    try std.testing.expectEqualStrings(
        "notice\nerror\ncompat varargs 7 (null)\n",
        stderr_buffer.?[0..stderr_size],
    );

    GlobalSetQuiet(1);
    common.log(LOG_INFO, "suppressed info\n", .{});
    common.log(LOG_NOTICE, "suppressed notice\n", .{});
    common.log(LOG_CRIT, "quiet critical\n", .{});
    common.log(LOG_ERR, "quiet error\n", .{});

    try std.testing.expectEqualStrings(
        "info value 7\ncritical\nquiet critical\n",
        stdout_buffer.?[0..stdout_size],
    );
    try std.testing.expectEqualStrings(
        "notice\nerror\ncompat varargs 7 (null)\nquiet error\n",
        stderr_buffer.?[0..stderr_size],
    );

    resetGlobalStateForTest();
    stdout_override = stdout_memory;
    stderr_override = stderr_memory;
    GlobalSetJson(1);
    common.log(LOG_INFO, "suppressed json info\n", .{});
    common.log(LOG_NOTICE, "suppressed json notice\n", .{});
    common.log(LOG_CRIT, "suppressed json critical\n", .{});
    common.log(LOG_ERR, "json error\n", .{});

    try std.testing.expectEqualStrings(
        "info value 7\ncritical\nquiet critical\n",
        stdout_buffer.?[0..stdout_size],
    );
    try std.testing.expectEqualStrings(
        "notice\nerror\ncompat varargs 7 (null)\nquiet error\njson error\n",
        stderr_buffer.?[0..stderr_size],
    );
}

test "typed logging holds the stream lock across complete messages" {
    resetGlobalStateForTest();
    defer resetGlobalStateForTest();

    var buffer: ?[*]u8 = null;
    var size: usize = 0;
    const stream = open_memstream(&buffer, &size) orelse
        return error.OutOfMemory;
    defer {
        _ = fclose(stream);
        free(buffer);
    }
    stderr_override = stream;

    const thread_count = 4;
    const message_count = 2_000;
    var contexts: [thread_count]AtomicLogContext = undefined;
    var threads: [thread_count]?std.Thread = @splat(null);
    defer for (&threads) |*thread| {
        if (thread.*) |running| {
            running.join();
        }
    };

    for (&threads, &contexts, 0..) |*thread, *context, id| {
        context.* = .{
            .id = @intCast(id),
            .count = message_count,
        };
        thread.* = try std.Thread.spawn(
            .{},
            emitAtomicLogMessages,
            .{context},
        );
    }
    for (&threads) |*thread| {
        thread.*.?.join();
        thread.* = null;
    }

    var seen = [_][message_count]bool{
        [_]bool{false} ** message_count,
    } ** thread_count;
    var line_count: usize = 0;
    var lines = std.mem.splitScalar(u8, buffer.?[0..size], '\n');
    while (lines.next()) |line| {
        if (line.len == 0) {
            continue;
        }

        const prefix = "thread=";
        const separator = " sequence=";
        const suffix = " end";
        try std.testing.expect(std.mem.startsWith(u8, line, prefix));
        try std.testing.expect(std.mem.endsWith(u8, line, suffix));

        const separator_index =
            std.mem.indexOf(u8, line, separator) orelse
            return error.TestUnexpectedResult;
        const id = try std.fmt.parseInt(
            usize,
            line[prefix.len..separator_index],
            10,
        );
        const sequence = try std.fmt.parseInt(
            usize,
            line[separator_index + separator.len .. line.len - suffix.len],
            10,
        );
        try std.testing.expect(id < thread_count);
        try std.testing.expect(sequence < message_count);
        try std.testing.expect(!seen[id][sequence]);
        seen[id][sequence] = true;
        line_count += 1;
    }

    try std.testing.expectEqual(
        @as(usize, thread_count * message_count),
        line_count,
    );
}
