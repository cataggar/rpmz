// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const errors = @import("rpmz_error");

const File = opaque {};
const default_max_string_len = 16_384_000;
const spaces = "                                                                ";

extern fn TDNFAllocateMemory(
    nNumElements: usize,
    nSize: usize,
    ppMemory: ?*?*anyopaque,
) u32;
extern fn TDNFFreeMemory(pMemory: ?*anyopaque) void;
extern fn TDNFJoinPathFromArray(
    ppszPath: ?*?[*:0]u8,
    ppszNodes: [*]const ?[*:0]const u8,
    nCount: c_int,
) u32;
extern fn TDNFLogGetStream(nLogLevel: c_int) ?*File;
extern fn fwrite(
    ptr: ?*const anyopaque,
    size: usize,
    count: usize,
    stream: *File,
) usize;
extern fn fflush(stream: *File) c_int;
extern fn flockfile(stream: *File) void;
extern fn funlockfile(stream: *File) void;
extern fn __errno_location() *c_int;

const AllocOps = struct {
    ctx: ?*anyopaque = null,
    allocateFn: *const fn (
        ctx: ?*anyopaque,
        size: usize,
        out: *?*anyopaque,
    ) u32,
};

const production_alloc_ops = AllocOps{
    .allocateFn = productionAllocate,
};

fn productionAllocate(
    _: ?*anyopaque,
    size: usize,
    out: *?*anyopaque,
) u32 {
    return TDNFAllocateMemory(1, size, out);
}

const CountingSink = struct {
    count: usize = 0,

    fn writeAll(self: *@This(), bytes: []const u8) void {
        self.count +|= bytes.len;
    }

    fn writeSpaces(self: *@This(), count: usize) void {
        self.count +|= count;
    }
};

const BufferSink = struct {
    bytes: []u8,
    index: usize = 0,

    fn writeAll(self: *@This(), bytes: []const u8) void {
        @memcpy(self.bytes[self.index .. self.index + bytes.len], bytes);
        self.index += bytes.len;
    }

    fn writeSpaces(self: *@This(), count: usize) void {
        @memset(self.bytes[self.index .. self.index + count], ' ');
        self.index += count;
    }
};

const LogSink = struct {
    stream: *File,

    fn writeAll(self: *@This(), bytes: []const u8) void {
        if (bytes.len != 0) {
            _ = fwrite(bytes.ptr, 1, bytes.len, self.stream);
        }
    }

    fn writeSpaces(self: *@This(), count: usize) void {
        var remaining = count;
        while (remaining != 0) {
            const chunk = @min(remaining, spaces.len);
            self.writeAll(spaces[0..chunk]);
            remaining -= chunk;
        }
    }
};

fn tupleFieldCount(comptime T: type) usize {
    const info = @typeInfo(T);
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("format arguments must be a tuple");
    }
    return info.@"struct".fields.len;
}

fn cString(value: anytype) []const u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        .optional => if (value) |present| cString(present) else "(null)",
        .pointer => |pointer| switch (pointer.size) {
            .slice => value,
            .c => if (value == null)
                "(null)"
            else
                std.mem.span(@as([*:0]const u8, @ptrCast(value))),
            .many => std.mem.span(
                @as([*:0]const u8, @ptrCast(value)),
            ),
            .one => switch (@typeInfo(pointer.child)) {
                .array => |array| value.*[0..array.len],
                else => @compileError("unsupported %s pointer type"),
            },
        },
        else => @compileError("unsupported %s argument type"),
    };
}

fn boundedString(bytes: []const u8, limit: usize) []const u8 {
    const bounded = bytes[0..@min(bytes.len, limit)];
    const nul = std.mem.indexOfScalar(u8, bounded, 0) orelse bounded.len;
    return bounded[0..nul];
}

fn boundedCString(value: anytype, limit: usize) []const u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        .optional => if (value) |present|
            boundedCString(present, limit)
        else
            boundedString("(null)", limit),
        .pointer => |pointer| switch (pointer.size) {
            .slice => boundedString(value, limit),
            .c => if (value == null)
                boundedString("(null)", limit)
            else
                boundedString(
                    @as([*]const u8, @ptrCast(value))[0..limit],
                    limit,
                ),
            .many => boundedString(
                @as([*]const u8, @ptrCast(value))[0..limit],
                limit,
            ),
            .one => switch (@typeInfo(pointer.child)) {
                .array => |array| boundedString(
                    value.*[0..array.len],
                    limit,
                ),
                else => @compileError("unsupported %s pointer type"),
            },
        },
        else => @compileError("unsupported %s argument type"),
    };
}

fn integerValue(value: anytype) switch (@typeInfo(@TypeOf(value))) {
    .int, .comptime_int => @TypeOf(value),
    .@"enum" => @typeInfo(@TypeOf(value)).@"enum".tag_type,
    else => @compileError("integer format requires an integer argument"),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => value,
        .@"enum" => @intFromEnum(value),
        else => unreachable,
    };
}

fn widthValue(value: anytype) isize {
    return @intCast(integerValue(value));
}

fn writePadded(
    sink: anytype,
    text: []const u8,
    width_opt: ?isize,
    left_flag: bool,
) void {
    var left = left_flag;
    var width: usize = 0;
    if (width_opt) |signed_width| {
        if (signed_width < 0) {
            left = true;
            width = @intCast(-signed_width);
        } else {
            width = @intCast(signed_width);
        }
    }

    const padding = width -| text.len;
    if (!left) {
        sink.writeSpaces(padding);
    }
    sink.writeAll(text);
    if (left) {
        sink.writeSpaces(padding);
    }
}

fn writeString(
    sink: anytype,
    value: anytype,
    width: ?isize,
    left: bool,
    precision: ?isize,
) void {
    const text = if (precision) |signed_precision|
        if (signed_precision < 0)
            cString(value)
        else
            boundedCString(value, @intCast(signed_precision))
    else
        cString(value);
    writePadded(sink, text, width, left);
}

fn writeInteger(
    sink: anytype,
    value: anytype,
    width: ?isize,
    left: bool,
) void {
    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{integerValue(value)}) catch
        unreachable;
    writePadded(sink, text, width, left);
}

fn writeCharacter(
    sink: anytype,
    value: anytype,
    width: ?isize,
    left: bool,
) void {
    const character: u8 = @intCast(integerValue(value));
    writePadded(sink, &.{character}, width, left);
}

fn formatToSink(
    sink: anytype,
    comptime format: []const u8,
    args: anytype,
    comptime format_index: usize,
    comptime arg_index: usize,
) void {
    comptime var percent = format_index;
    inline while (percent < format.len and format[percent] != '%') {
        percent += 1;
    }
    sink.writeAll(format[format_index..percent]);

    if (percent == format.len) {
        if (comptime arg_index != tupleFieldCount(@TypeOf(args))) {
            @compileError("too many format arguments");
        }
        return;
    }

    if (percent + 1 < format.len and format[percent + 1] == '%') {
        sink.writeAll("%");
        return formatToSink(
            sink,
            format,
            args,
            percent + 2,
            arg_index,
        );
    }

    comptime var cursor = percent + 1;
    comptime var left = false;
    if (cursor < format.len and format[cursor] == '-') {
        left = true;
        cursor += 1;
    }

    comptime var next_arg = arg_index;
    var width: ?isize = null;
    if (cursor < format.len and format[cursor] == '*') {
        if (comptime next_arg >= tupleFieldCount(@TypeOf(args))) {
            @compileError("missing dynamic width argument");
        }
        width = widthValue(args[next_arg]);
        next_arg += 1;
        cursor += 1;
    } else {
        comptime var parsed_width: usize = 0;
        comptime var has_width = false;
        inline while (cursor < format.len and
            format[cursor] >= '0' and format[cursor] <= '9')
        {
            has_width = true;
            parsed_width = parsed_width * 10 + format[cursor] - '0';
            cursor += 1;
        }
        if (has_width) {
            width = @intCast(parsed_width);
        }
    }

    var precision: ?isize = null;
    if (cursor < format.len and format[cursor] == '.') {
        cursor += 1;
        if (cursor < format.len and format[cursor] == '*') {
            if (comptime next_arg >= tupleFieldCount(@TypeOf(args))) {
                @compileError("missing dynamic precision argument");
            }
            precision = widthValue(args[next_arg]);
            next_arg += 1;
            cursor += 1;
        } else {
            comptime var parsed_precision: usize = 0;
            inline while (cursor < format.len and
                format[cursor] >= '0' and format[cursor] <= '9')
            {
                parsed_precision =
                    parsed_precision * 10 + format[cursor] - '0';
                cursor += 1;
            }
            precision = @intCast(parsed_precision);
        }
    }

    if (cursor < format.len and
        (format[cursor] == 'h' or format[cursor] == 'l'))
    {
        const modifier = format[cursor];
        cursor += 1;
        if (cursor < format.len and format[cursor] == modifier) {
            cursor += 1;
        }
    } else if (cursor < format.len and
        (format[cursor] == 'j' or
            format[cursor] == 'z' or
            format[cursor] == 't' or
            format[cursor] == 'L'))
    {
        cursor += 1;
    }

    if (comptime cursor >= format.len) {
        @compileError("unterminated format specifier");
    }
    if (comptime next_arg >= tupleFieldCount(@TypeOf(args))) {
        @compileError("missing format argument");
    }

    switch (format[cursor]) {
        's' => writeString(
            sink,
            args[next_arg],
            width,
            left,
            precision,
        ),
        'd', 'i', 'u' => writeInteger(
            sink,
            args[next_arg],
            width,
            left,
        ),
        'c' => writeCharacter(
            sink,
            args[next_arg],
            width,
            left,
        ),
        else => @compileError("unsupported printf conversion"),
    }

    return formatToSink(
        sink,
        format,
        args,
        cursor + 1,
        next_arg + 1,
    );
}

fn formattedLength(comptime format: []const u8, args: anytype) usize {
    var sink = CountingSink{};
    formatToSink(&sink, format, args, 0, 0);
    return sink.count;
}

fn allocPrintWithOps(
    ops: AllocOps,
    out: ?*?[*:0]u8,
    comptime format: []const u8,
    args: anytype,
    max_string_len: usize,
) u32 {
    if (out == null) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    out.?.* = null;

    const length = formattedLength(format, args);
    if (length == 0) {
        return errors.ERROR_TDNF_SYSTEM_BASE +
            @as(u32, @intCast(__errno_location().*));
    }
    if (length == std.math.maxInt(usize) or
        length + 1 > max_string_len)
    {
        return errors.ERROR_TDNF_STRING_TOO_LONG;
    }

    var raw: ?*anyopaque = null;
    const result = ops.allocateFn(ops.ctx, length + 1, &raw);
    if (result != 0) {
        return result;
    }

    const bytes: [*]u8 = @ptrCast(raw.?);
    var sink = BufferSink{ .bytes = bytes[0..length] };
    formatToSink(&sink, format, args, 0, 0);
    bytes[length] = 0;
    out.?.* = @ptrCast(bytes);
    return 0;
}

pub fn allocPrint(
    out: ?*?[*:0]u8,
    comptime format: []const u8,
    args: anytype,
) u32 {
    return allocPrintWithOps(
        production_alloc_ops,
        out,
        format,
        args,
        default_max_string_len,
    );
}

pub fn joinPath(
    out: ?*?[*:0]u8,
    nodes: []const ?[*:0]const u8,
) u32 {
    if (nodes.len > std.math.maxInt(c_int)) {
        if (out) |present| {
            present.* = null;
        }
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }
    return TDNFJoinPathFromArray(out, nodes.ptr, @intCast(nodes.len));
}

pub fn log(
    level: c_int,
    comptime format: []const u8,
    args: anytype,
) void {
    const stream = TDNFLogGetStream(level) orelse return;
    flockfile(stream);
    defer funlockfile(stream);

    var sink = LogSink{ .stream = stream };
    formatToSink(&sink, format, args, 0, 0);
    _ = fflush(stream);
}

fn alwaysFailAllocate(
    _: ?*anyopaque,
    _: usize,
    _: *?*anyopaque,
) u32 {
    return errors.ERROR_TDNF_OUT_OF_MEMORY;
}

test "typed formatting preserves C string, width, precision, and newline behavior" {
    const null_string: ?[*:0]const u8 = null;
    var buffer: [256]u8 = undefined;
    var sink = BufferSink{ .bytes = &buffer };
    formatToSink(
        &sink,
        "%-9s %.*s %4d %u%% %s\n",
        .{ "name", @as(c_int, 3), "abcdef", -7, @as(u32, 42), null_string },
        0,
        0,
    );
    try std.testing.expectEqualStrings(
        "name      abc   -7 42% (null)\n",
        buffer[0..sink.index],
    );
}

test "bounded string precision does not scan past a non-sentinel allocation" {
    const page_size = std.heap.pageSize();
    const mapped = try std.posix.mmap(
        null,
        page_size * 2,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
        -1,
        0,
    );
    defer std.posix.munmap(mapped);

    const guard: []align(std.heap.page_size_min) u8 =
        @alignCast(mapped[page_size..]);
    try std.process.protectMemory(guard, .{});

    const safe_url = mapped[page_size - 3 .. page_size];
    @memcpy(safe_url, "url");

    var buffer: [16]u8 = undefined;
    var sink = BufferSink{ .bytes = &buffer };
    formatToSink(
        &sink,
        "[%5.*s][%-5.*s]",
        .{
            @as(c_int, 3),
            safe_url.ptr,
            @as(c_int, 3),
            safe_url.ptr,
        },
        0,
        0,
    );
    try std.testing.expectEqualStrings(
        "[  url][url  ]",
        buffer[0..sink.index],
    );
}

test "bounded string precision stops at NUL and negative precision scans" {
    const early_nul = [_]u8{ 'a', 'b', 0, 'x', 'y' };
    const terminated: [*:0]const u8 = "abcdef";
    const null_string: ?[*:0]const u8 = null;
    var buffer: [48]u8 = undefined;
    var sink = BufferSink{ .bytes = &buffer };
    formatToSink(
        &sink,
        "%.*s|%.*s|%8.*s",
        .{
            @as(c_int, early_nul.len),
            early_nul[0..].ptr,
            @as(c_int, -1),
            terminated,
            @as(c_int, 6),
            null_string,
        },
        0,
        0,
    );
    try std.testing.expectEqualStrings(
        "ab|abcdef|  (null)",
        buffer[0..sink.index],
    );
}

test "typed formatting preserves dynamic alignment and C integer lengths" {
    var buffer: [128]u8 = undefined;
    var sink = BufferSink{ .bytes = &buffer };
    formatToSink(
        &sink,
        "%-*s %*s %10ld %lu %zu\r",
        .{
            @as(c_int, 5),
            "a",
            @as(c_int, 4),
            "b",
            @as(c_long, -12),
            @as(c_ulong, 13),
            @as(usize, 14),
        },
        0,
        0,
    );
    try std.testing.expectEqualStrings(
        "a        b        -12 13 14\r",
        buffer[0..sink.index],
    );
}

test "allocPrint uses RPMZ ownership and preserves null output on errors" {
    var output: ?[*:0]u8 = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        allocPrint(&output, "%s-%u", .{ "value", @as(u32, 7) }),
    );
    defer TDNFFreeMemory(@ptrCast(output.?));
    try std.testing.expectEqualStrings("value-7", std.mem.span(output.?));

    const fail_ops = AllocOps{ .allocateFn = alwaysFailAllocate };
    var stale: ?[*:0]u8 = @ptrFromInt(1);
    try std.testing.expectEqual(
        errors.ERROR_TDNF_OUT_OF_MEMORY,
        allocPrintWithOps(fail_ops, &stale, "%s", .{"value"}, 100),
    );
    try std.testing.expect(stale == null);

    const saved_errno = __errno_location().*;
    defer __errno_location().* = saved_errno;
    __errno_location().* = 5;
    try std.testing.expectEqual(
        @as(u32, errors.ERROR_TDNF_SYSTEM_BASE + 5),
        allocPrint(&stale, "%s", .{""}),
    );
    try std.testing.expect(stale == null);

    try std.testing.expectEqual(
        errors.ERROR_TDNF_STRING_TOO_LONG,
        allocPrintWithOps(
            production_alloc_ops,
            &stale,
            "%s",
            .{"too long"},
            3,
        ),
    );
    try std.testing.expect(stale == null);
}

test "typed path joining canonicalizes separators and preserves ownership" {
    var output: ?[*:0]u8 = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        joinPath(&output, &.{ "/var/", "/lib/", "rpmz/" }),
    );
    defer TDNFFreeMemory(@ptrCast(output.?));
    try std.testing.expectEqualStrings(
        "/var/lib/rpmz",
        std.mem.span(output.?),
    );

    var root_only: ?[*:0]u8 = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        joinPath(&root_only, &.{ "/", "/" }),
    );
    defer TDNFFreeMemory(@ptrCast(root_only.?));
    try std.testing.expectEqualStrings("/", std.mem.span(root_only.?));
}
