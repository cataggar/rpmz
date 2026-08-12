const std = @import("std");

/// Absolute RPM EVR ordering, matching repomd/index.zig.
pub fn compareEvr(
    left_epoch: ?u32,
    left_version: []const u8,
    left_release: []const u8,
    right_epoch: ?u32,
    right_version: []const u8,
    right_release: []const u8,
) i32 {
    const left_epoch_value = left_epoch orelse 0;
    const right_epoch_value = right_epoch orelse 0;
    if (left_epoch_value < right_epoch_value) return -1;
    if (left_epoch_value > right_epoch_value) return 1;
    const version = compareRpmVersion(left_version, right_version);
    if (version != 0) return version;
    return compareRpmVersion(left_release, right_release);
}

fn compareRpmVersion(left_raw: []const u8, right_raw: []const u8) i32 {
    var left = left_raw;
    var right = right_raw;
    while (true) {
        while (left.len != 0 and !isRpmTokenByte(left[0])) left = left[1..];
        while (right.len != 0 and !isRpmTokenByte(right[0])) right = right[1..];
        if ((left.len != 0 and left[0] == '~') or
            (right.len != 0 and right[0] == '~'))
        {
            if (left.len == 0 or left[0] != '~') return 1;
            if (right.len == 0 or right[0] != '~') return -1;
            left = left[1..];
            right = right[1..];
            continue;
        }
        if ((left.len != 0 and left[0] == '^') or
            (right.len != 0 and right[0] == '^'))
        {
            if (left.len == 0) return -1;
            if (right.len == 0) return 1;
            if (left[0] != '^') return 1;
            if (right[0] != '^') return -1;
            left = left[1..];
            right = right[1..];
            continue;
        }
        if (left.len == 0 and right.len == 0) return 0;
        if (left.len == 0) return -1;
        if (right.len == 0) return 1;
        const left_digit = std.ascii.isDigit(left[0]);
        const right_digit = std.ascii.isDigit(right[0]);
        if (left_digit != right_digit) return if (left_digit) 1 else -1;
        if (left_digit) {
            const left_end = digitRunEnd(left);
            const right_end = digitRunEnd(right);
            const left_digits = trimLeadingZeros(left[0..left_end]);
            const right_digits = trimLeadingZeros(right[0..right_end]);
            left = left[left_end..];
            right = right[right_end..];
            if (left_digits.len < right_digits.len) return -1;
            if (left_digits.len > right_digits.len) return 1;
            const order = std.mem.order(u8, left_digits, right_digits);
            if (order != .eq) return if (order == .lt) -1 else 1;
        } else {
            const left_end = alphaRunEnd(left);
            const right_end = alphaRunEnd(right);
            const order = std.mem.order(
                u8,
                left[0..left_end],
                right[0..right_end],
            );
            left = left[left_end..];
            right = right[right_end..];
            if (order != .eq) return if (order == .lt) -1 else 1;
        }
    }
}

fn trimLeadingZeros(value: []const u8) []const u8 {
    var index: usize = 0;
    while (index < value.len and value[index] == '0') : (index += 1) {}
    return value[index..];
}

fn digitRunEnd(value: []const u8) usize {
    var index: usize = 0;
    while (index < value.len and std.ascii.isDigit(value[index])) : (index += 1) {}
    return index;
}

fn alphaRunEnd(value: []const u8) usize {
    var index: usize = 0;
    while (index < value.len and std.ascii.isAlphabetic(value[index])) : (index += 1) {}
    return index;
}

fn isRpmTokenByte(value: u8) bool {
    return std.ascii.isAlphanumeric(value) or value == '~' or value == '^';
}

test "absolute EVR ordering matches RPM edge cases" {
    try std.testing.expect(compareEvr(null, "1.0~rc1", "1", null, "1.0", "1") < 0);
    try std.testing.expect(compareEvr(null, "1.0^git1", "1", null, "1.0", "1") > 0);
    try std.testing.expectEqual(
        @as(i32, 0),
        compareEvr(null, "10.0001", "1", null, "10.1", "1"),
    );
}
