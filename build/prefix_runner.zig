const std = @import("std");

const marker = "@RPMZ_INSTALL_PREFIX@";

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(allocator);
    const prefix = args[1];
    const mode = args[2];
    if (std.mem.eql(u8, mode, "exec")) {
        const argv = try allocator.alloc([]const u8, args.len - 3);
        for (args[3..], argv) |arg, *output| output.* = try replace(allocator, arg, prefix);
        var environ = try init.environ_map.clone(allocator);
        const entries = try allocator.alloc(struct { key: []const u8, value: []const u8 }, environ.count());
        var it = environ.iterator();
        var index: usize = 0;
        while (it.next()) |entry| : (index += 1) {
            entries[index] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* };
        }
        for (entries) |entry| {
            if (std.mem.indexOf(u8, entry.value, marker) != null)
                try environ.put(entry.key, try replace(allocator, entry.value, prefix));
        }
        var child = try std.process.spawn(io, .{ .argv = argv, .environ_map = &environ });
        const term = try child.wait(io);
        std.process.exit(switch (term) {
            .exited => |code| code,
            .signal => |signal| @intCast(@min(255, 128 + @backingInt(signal))),
            else => 1,
        });
    }
    const input = try std.Io.Dir.cwd().readFileAlloc(io, args[3], allocator, .limited(4 * 1024 * 1024));
    const output = if (std.mem.eql(u8, mode, "options"))
        try replaceOptions(allocator, input, prefix)
    else
        try replace(allocator, input, prefix);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[4], .data = output });
    if (!std.mem.eql(u8, mode, "options")) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = args[5], .data = output });
        if (std.mem.eql(u8, mode, "executable")) {
            try std.Io.Dir.cwd().setFilePermissions(io, args[4], .executable_file, .{});
            try std.Io.Dir.cwd().setFilePermissions(io, args[5], .executable_file, .{});
        }
    }
}

fn replace(allocator: std.mem.Allocator, input: []const u8, prefix: []const u8) ![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    var parts = std.mem.splitSequence(u8, input, marker);
    try output.writer.writeAll(parts.first());
    while (parts.next()) |part| {
        try output.writer.writeAll(prefix);
        try output.writer.writeAll(part);
    }
    return output.toOwnedSlice();
}

fn replaceOptions(allocator: std.mem.Allocator, input: []const u8, prefix: []const u8) ![]const u8 {
    const escaped = try std.fmt.allocPrint(allocator, "{f}", .{std.zig.fmtString(prefix)});
    defer allocator.free(escaped);
    return replace(allocator, input, escaped);
}

test "prefix substitution preserves bytes and replaces every marker" {
    const allocator = std.testing.allocator;
    const output = try replace(allocator, "a@RPMZ_INSTALL_PREFIX@/b:@RPMZ_INSTALL_PREFIX@", "/root with \"quotes\"");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("a/root with \"quotes\"/b:/root with \"quotes\"", output);
    const untouched = try replace(allocator, "@RPMZ_OTHER@/keep", "/changed");
    defer allocator.free(untouched);
    try std.testing.expectEqualStrings("@RPMZ_OTHER@/keep", untouched);
}

test "options prefix substitution escapes quotes backslashes and control bytes" {
    const allocator = std.testing.allocator;
    const output = try replaceOptions(allocator, "pub const prefix = \"@RPMZ_INSTALL_PREFIX@/bin\";\n", "/root \"quoted\"\\path\n");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("pub const prefix = \"/root \\\"quoted\\\"\\\\path\\n/bin\";\n", output);
}
