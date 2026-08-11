//! Canonical JSON writing shared by every versioned tdnf artifact.
//!
//! The canonical form is deliberately narrow: no insignificant whitespace, no
//! alternative escapes, and a fixed integer spelling. Two artifacts that share
//! a digest domain must share this writer, because a second implementation
//! would be free to drift and would silently change digests.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Writer = struct {
    allocator: Allocator,
    bytes: std.ArrayList(u8) = .empty,

    pub fn init(allocator: Allocator) Writer {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Writer) void {
        self.bytes.deinit(self.allocator);
    }
    pub fn finish(self: *Writer) Allocator.Error![]u8 {
        return self.bytes.toOwnedSlice(self.allocator);
    }
    pub fn appendByte(self: *Writer, byte: u8) Allocator.Error!void {
        try self.bytes.append(self.allocator, byte);
    }
    pub fn append(self: *Writer, value: []const u8) Allocator.Error!void {
        try self.bytes.appendSlice(self.allocator, value);
    }
    pub fn writeBool(self: *Writer, value: bool) Allocator.Error!void {
        try self.append(if (value) "true" else "false");
    }
    pub fn writeUint(self: *Writer, value: u64) Allocator.Error!void {
        var buffer: [20]u8 = undefined;
        var cursor = buffer.len;
        var remaining = value;
        while (true) {
            cursor -= 1;
            buffer[cursor] = @as(u8, @intCast(remaining % 10)) + '0';
            remaining /= 10;
            if (remaining == 0) break;
        }
        try self.append(buffer[cursor..]);
    }
    pub fn writeInt(self: *Writer, value: i64) Allocator.Error!void {
        if (value < 0) {
            try self.appendByte('-');
            try self.writeUint(@intCast(-value));
        } else try self.writeUint(@intCast(value));
    }
    pub fn writeString(self: *Writer, value: []const u8) Allocator.Error!void {
        const hex = "0123456789abcdef";
        try self.appendByte('"');
        for (value) |byte| switch (byte) {
            '"' => try self.append("\\\""),
            '\\' => try self.append("\\\\"),
            0x08 => try self.append("\\b"),
            0x09 => try self.append("\\t"),
            0x0a => try self.append("\\n"),
            0x0c => try self.append("\\f"),
            0x0d => try self.append("\\r"),
            0x00...0x07, 0x0b, 0x0e...0x1f => {
                try self.append("\\u00");
                try self.appendByte(hex[byte >> 4]);
                try self.appendByte(hex[byte & 0x0f]);
            },
            else => try self.appendByte(byte),
        };
        try self.appendByte('"');
    }
    pub fn writeOptionalString(self: *Writer, value: ?[]const u8) Allocator.Error!void {
        if (value) |text| try self.writeString(text) else try self.append("null");
    }
};

test "canonical json: integers use the shortest fixed spelling" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeUint(0);
    try writer.appendByte(',');
    try writer.writeUint(std.math.maxInt(u64));
    try writer.appendByte(',');
    try writer.writeInt(-1);
    try writer.appendByte(',');
    try writer.writeInt(std.math.minInt(i64) + 1);
    const bytes = try writer.finish();
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings(
        "0,18446744073709551615,-1,-9223372036854775807",
        bytes,
    );
}

test "canonical json: strings escape exactly the required set" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeString("\"\\\x08\x09\x0a\x0c\x0d\x00\x1f/\u{00e9}");
    const bytes = try writer.finish();
    defer std.testing.allocator.free(bytes);
    // Forward slash and non-ASCII stay literal; only the mandatory set escapes.
    try std.testing.expectEqualStrings(
        "\"\\\"\\\\\\b\\t\\n\\f\\r\\u0000\\u001f/\u{00e9}\"",
        bytes,
    );
}

test "canonical json: optional strings distinguish null from empty" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeOptionalString(null);
    try writer.appendByte(',');
    try writer.writeOptionalString("");
    const bytes = try writer.finish();
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("null,\"\"", bytes);
}
