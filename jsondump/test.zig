// Copyright (C) 2022-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const jsondump = @import("jsondump");
const testing = std.testing;

const JsonDump = jsondump.JsonDump;

extern fn jd_map_add_fmt(
    jd: ?*JsonDump,
    key: [*:0]const u8,
    format: [*:0]const u8,
    ...,
) c_int;

extern fn jd_list_add_fmt(
    jd: ?*JsonDump,
    format: [*:0]const u8,
    ...,
) c_int;

const flat_map =
    "{\"foo\":\"bar\",\"goo\":\"car\",\"hoo\":\"\\tdar\\n\"," ++
    "\"ioo\":\"2 ears\",\"nothing\":null,\"yes\":true,\"no\":false}";
const nested_map = "{\"nested\":" ++ flat_map ++ "}";
const string_list = "[\"0\",\"1\",\"2\",\"3\",\"4\",\"5\",\"6\",\"7\",\"8\",\"9\",null]";
const format_list = "[\"i=0\",\"i=1\",\"i=2\",\"i=3\",\"i=4\",\"i=5\",\"i=6\",\"i=7\",\"i=8\",\"i=9\"]";
const int_list = "[0,1,2,3,4,5,6,7,8,9]";
const bool_list = "[true,false]";
const expected_output =
    flat_map ++ "\n" ++
    nested_map ++ "\n" ++
    string_list ++ "\n" ++
    format_list ++ "\n" ++
    int_list ++ "\n" ++
    bool_list ++ "\n";

fn create(size: c_uint) !*JsonDump {
    return jsondump.jd_create(size) orelse error.OutOfMemory;
}

fn expectSuccess(rc: c_int) !void {
    try testing.expectEqual(@as(c_int, 0), rc);
}

fn buffer(jd: *const JsonDump) []const u8 {
    const ptr: [*:0]const u8 = @ptrCast(jd.buf.?);
    return std.mem.span(ptr);
}

fn expectBuffer(expected: []const u8, jd: *const JsonDump) !void {
    try testing.expectEqualStrings(expected, buffer(jd));
}

fn buildFlatMap() !*JsonDump {
    const jd = try create(0);
    errdefer jsondump.jd_destroy(jd);

    try expectSuccess(jsondump.jd_map_start(jd));
    try expectSuccess(jsondump.jd_map_add_string(jd, "foo", "bar"));
    try expectSuccess(jsondump.jd_map_add_string(jd, "goo", "car"));
    try expectSuccess(jsondump.jd_map_add_string(jd, "hoo", "\tdar\n"));
    try expectSuccess(jd_map_add_fmt(jd, "ioo", "%d ears", @as(c_int, 2)));
    try expectSuccess(jsondump.jd_map_add_null(jd, "nothing"));
    try expectSuccess(jsondump.jd_map_add_bool(jd, "yes", 1));
    try expectSuccess(jsondump.jd_map_add_bool(jd, "no", 0));

    return jd;
}

fn buildNestedMap() !*JsonDump {
    const child = try buildFlatMap();
    defer jsondump.jd_destroy(child);

    const jd = try create(0);
    errdefer jsondump.jd_destroy(jd);
    try expectSuccess(jsondump.jd_map_start(jd));
    try expectSuccess(jsondump.jd_map_add_child(jd, "nested", child));
    return jd;
}

fn buildStringList() !*JsonDump {
    const jd = try create(0);
    errdefer jsondump.jd_destroy(jd);
    try expectSuccess(jsondump.jd_list_start(jd));

    for (0..10) |i| {
        var item: [3]u8 = undefined;
        const value = try std.fmt.bufPrintZ(&item, "{d}", .{i});
        try expectSuccess(jsondump.jd_list_add_string(jd, value));
    }
    try expectSuccess(jsondump.jd_list_add_null(jd));
    return jd;
}

fn buildFormatList() !*JsonDump {
    const jd = try create(0);
    errdefer jsondump.jd_destroy(jd);
    try expectSuccess(jsondump.jd_list_start(jd));

    for (0..10) |i| {
        try expectSuccess(jd_list_add_fmt(jd, "i=%d", @as(c_int, @intCast(i))));
    }
    return jd;
}

fn buildIntList() !*JsonDump {
    const jd = try create(0);
    errdefer jsondump.jd_destroy(jd);
    try expectSuccess(jsondump.jd_list_start(jd));

    for (0..10) |i| {
        try expectSuccess(jsondump.jd_list_add_int(jd, @intCast(i)));
    }
    return jd;
}

fn buildBoolList() !*JsonDump {
    const jd = try create(0);
    errdefer jsondump.jd_destroy(jd);
    try expectSuccess(jsondump.jd_list_start(jd));
    try expectSuccess(jsondump.jd_list_add_bool(jd, 1));
    try expectSuccess(jsondump.jd_list_add_bool(jd, 0));
    return jd;
}

fn emitAll(writer: *std.Io.Writer) !void {
    {
        const jd = try buildFlatMap();
        defer jsondump.jd_destroy(jd);
        try expectBuffer(flat_map, jd);
        try writer.print("{s}\n", .{buffer(jd)});
    }
    {
        const jd = try buildNestedMap();
        defer jsondump.jd_destroy(jd);
        try expectBuffer(nested_map, jd);
        try writer.print("{s}\n", .{buffer(jd)});
    }
    {
        const jd = try buildStringList();
        defer jsondump.jd_destroy(jd);
        try expectBuffer(string_list, jd);
        try writer.print("{s}\n", .{buffer(jd)});
    }
    {
        const jd = try buildFormatList();
        defer jsondump.jd_destroy(jd);
        try expectBuffer(format_list, jd);
        try writer.print("{s}\n", .{buffer(jd)});
    }
    {
        const jd = try buildIntList();
        defer jsondump.jd_destroy(jd);
        try expectBuffer(int_list, jd);
        try writer.print("{s}\n", .{buffer(jd)});
    }
    {
        const jd = try buildBoolList();
        defer jsondump.jd_destroy(jd);
        try expectBuffer(bool_list, jd);
        try writer.print("{s}\n", .{buffer(jd)});
    }
}

pub fn main(init: std.process.Init) u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);

    emitAll(&stdout.interface) catch |err| {
        std.debug.print("FAIL: {t}\n", .{err});
        return 1;
    };
    stdout.flush() catch return 1;
    return 0;
}

test "flat map preserves strings, formatting, null, and boolean values" {
    const jd = try buildFlatMap();
    defer jsondump.jd_destroy(jd);
    try expectBuffer(flat_map, jd);
}

test "nested map preserves child JSON boundaries" {
    const jd = try buildNestedMap();
    defer jsondump.jd_destroy(jd);
    try expectBuffer(nested_map, jd);
}

test "string list preserves element boundaries and trailing null" {
    const jd = try buildStringList();
    defer jsondump.jd_destroy(jd);
    try expectBuffer(string_list, jd);
}

test "formatted list preserves every formatted value" {
    const jd = try buildFormatList();
    defer jsondump.jd_destroy(jd);
    try expectBuffer(format_list, jd);
}

test "integer and boolean lists preserve JSON scalar formatting" {
    const ints = try buildIntList();
    defer jsondump.jd_destroy(ints);
    try expectBuffer(int_list, ints);

    const bools = try buildBoolList();
    defer jsondump.jd_destroy(bools);
    try expectBuffer(bool_list, bools);
}

test "all JSON string escapes survive buffer growth" {
    const jd = try create(2);
    defer jsondump.jd_destroy(jd);
    try expectSuccess(jsondump.jd_list_start(jd));
    try expectSuccess(jsondump.jd_list_add_string(
        jd,
        "quote\" slash\\ backspace\x08 formfeed\x0c newline\n return\r tab\t",
    ));
    try expectBuffer(
        "[\"quote\\\" slash\\\\ backspace\\b formfeed\\f newline\\n return\\r tab\\t\"]",
        jd,
    );
}

test "executable output remains byte-for-byte compatible" {
    var output = std.Io.Writer.Allocating.init(testing.allocator);
    defer output.deinit();
    try emitAll(&output.writer);
    try testing.expectEqualStrings(
        expected_output,
        output.writer.buffer[0..output.writer.end],
    );
}
