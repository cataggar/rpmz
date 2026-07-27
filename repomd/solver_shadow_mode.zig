//! Opt-in gate for the diagnostic native-vs-libsolv solver crosscheck.
//!
//! The crosscheck is driven by the `TDNF_NATIVE_SOLVER_SHADOW` environment
//! variable rather than a CLI flag so an entire test corpus can opt in once
//! without rewriting every invocation.
//!
//! The shadow never influences package selection. `strict` only promotes an
//! already-reported mismatch into an error so a crosscheck run can fail loudly.

const std = @import("std");

pub const variable = "TDNF_NATIVE_SOLVER_SHADOW";

pub const Mode = enum(u32) {
    off = 0,
    observe = 1,
    strict = 2,
};

/// Parses a raw environment value into a mode.
///
/// Unrecognized non-empty values resolve to `.observe` rather than `.off` so a
/// typo can never silently disable the crosscheck.
pub fn parse(raw: ?[]const u8) Mode {
    const value = std.mem.trim(u8, raw orelse return .off, " \t\r\n");
    if (value.len == 0) return .off;

    if (eqlIgnoreCase(value, "0") or
        eqlIgnoreCase(value, "off") or
        eqlIgnoreCase(value, "false") or
        eqlIgnoreCase(value, "no"))
    {
        return .off;
    }
    if (eqlIgnoreCase(value, "strict")) return .strict;
    return .observe;
}

fn eqlIgnoreCase(value: []const u8, expected: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, expected);
}

/// Reads the current mode from the process environment.
pub fn current() Mode {
    const raw = std.c.getenv(variable) orelse return .off;
    return parse(std.mem.span(raw));
}

test "unset and empty values disable the crosscheck" {
    try std.testing.expectEqual(Mode.off, parse(null));
    try std.testing.expectEqual(Mode.off, parse(""));
    try std.testing.expectEqual(Mode.off, parse("   "));
}

test "explicit falsey values disable the crosscheck" {
    for ([_][]const u8{
        "0",
        "off",
        "OFF",
        "false",
        "False",
        "no",
        "NO",
        "  off  ",
    }) |value| {
        try std.testing.expectEqual(Mode.off, parse(value));
    }
}

test "truthy values enable observation" {
    for ([_][]const u8{
        "1",
        "on",
        "true",
        "TRUE",
        "yes",
        "observe",
        "OBSERVE",
        "  1  ",
    }) |value| {
        try std.testing.expectEqual(Mode.observe, parse(value));
    }
}

test "strict is recognized case insensitively" {
    for ([_][]const u8{ "strict", "STRICT", "Strict", "  strict  " }) |value| {
        try std.testing.expectEqual(Mode.strict, parse(value));
    }
}

test "unrecognized values fall back to observation rather than off" {
    // A typo must never silently disable the crosscheck.
    for ([_][]const u8{ "stict", "2", "enabled", "-1" }) |value| {
        try std.testing.expectEqual(Mode.observe, parse(value));
    }
}

test "mode values match the published C enum" {
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(Mode.off));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(Mode.observe));
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum(Mode.strict));
}
