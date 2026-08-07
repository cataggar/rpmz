const std = @import("std");
const pkgfile = @import("rpm_pkgfile");

pub fn parseLong(text: []const u8) ?c_long {
    const trimmed = std.mem.trimStart(u8, text, " \t\n\r\x0b\x0c");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(c_long, trimmed, 10) catch null;
}

pub fn parseU32(text: []const u8) ?u32 {
    const trimmed = std.mem.trimStart(u8, text, " \t\n\r\x0b\x0c");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(u32, trimmed, 10) catch null;
}

pub fn openRpm(path: [*:0]const u8) pkgfile.Error!pkgfile.RpmFile {
    return pkgfile.RpmFile.open(std.heap.c_allocator, std.mem.span(path));
}

test "integer parsers preserve command line behavior" {
    try std.testing.expectEqual(@as(?c_long, -12), parseLong(" \t-12"));
    try std.testing.expectEqual(@as(?u32, 42), parseU32("\n42"));
    try std.testing.expectEqual(@as(?c_long, null), parseLong("12 "));
    try std.testing.expectEqual(@as(?u32, null), parseU32("4294967296"));
}
