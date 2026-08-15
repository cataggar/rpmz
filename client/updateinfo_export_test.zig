const std = @import("std");
const client = @import("client_root");
const errors = @import("rpmz_error");
const c = client.updateinfo.c;

extern fn TDNFGetSecuritySeverityOption(
    ?*c.RPMZ,
    [*c]u32,
    [*c][*c]u8,
) callconv(.c) u32;
extern fn TDNFGetRebootRequiredOption(
    ?*c.RPMZ,
    [*c]u32,
) callconv(.c) u32;
extern fn TDNFGetUpdatePkgs(
    ?*c.RPMZ,
    [*c][*c][*c]u8,
    [*c]u32,
) callconv(.c) u32;
extern fn TDNFUpdateInfoSummary(
    ?*c.RPMZ,
    [*c][*c]u8,
    [*c]c.PTDNF_UPDATEINFO_SUMMARY,
) callconv(.c) u32;
extern fn TDNFFreeMemory(?*anyopaque) callconv(.c) void;

fn node(name: [*:0]const u8, value: ?[*:0]const u8) c.cnfnode {
    var result = std.mem.zeroes(c.cnfnode);
    result.name = @constCast(name);
    result.value = if (value) |text| @constCast(text) else null;
    return result;
}

test "production updateinfo exports reset invalid outputs" {
    var security: u32 = 99;
    var severity: [*c]u8 = @ptrFromInt(8);
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetSecuritySeverityOption(null, &security, &severity),
    );
    try std.testing.expectEqual(@as(u32, 0), security);
    try std.testing.expectEqual(@as([*c]u8, null), severity);

    var packages: [*c][*c]u8 = @ptrFromInt(16);
    var count: u32 = 99;
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFGetUpdatePkgs(null, &packages, &count),
    );
    try std.testing.expectEqual(@as([*c][*c]u8, null), packages);
    try std.testing.expectEqual(@as(u32, 0), count);

    var summary: c.PTDNF_UPDATEINFO_SUMMARY = @ptrFromInt(24);
    try std.testing.expectEqual(
        errors.ERROR_TDNF_INVALID_PARAMETER,
        TDNFUpdateInfoSummary(null, null, &summary),
    );
    try std.testing.expectEqual(@as(c.PTDNF_UPDATEINFO_SUMMARY, null), summary);
}

test "production setopt exports use real allocation and last severity" {
    var security_node = node("security", null);
    var severity_one = node("SEC-SEVERITY", "moderate");
    var severity_two = node("sec-severity", "critical");
    var reboot_node = node("REBOOT-REQUIRED", null);
    security_node.next = &severity_one;
    severity_one.next = &severity_two;
    severity_two.next = &reboot_node;

    var root = std.mem.zeroes(c.cnfnode);
    root.first_child = &security_node;
    var args = std.mem.zeroes(c.TDNF_CMD_ARGS);
    args.cn_setopts = &root;
    var handle = std.mem.zeroes(c.RPMZ);
    handle.pArgs = &args;

    var security: u32 = 0;
    var severity: [*c]u8 = null;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFGetSecuritySeverityOption(&handle, &security, &severity),
    );
    defer TDNFFreeMemory(@ptrCast(severity));
    try std.testing.expectEqual(@as(u32, 1), security);
    try std.testing.expectEqualStrings(
        "critical",
        std.mem.span(@as([*:0]const u8, @ptrCast(severity))),
    );

    var reboot: u32 = 0;
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFGetRebootRequiredOption(&handle, &reboot),
    );
    try std.testing.expectEqual(@as(u32, 1), reboot);
}
