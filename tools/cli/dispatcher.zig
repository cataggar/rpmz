// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");

pub const Action = union(enum) {
    tdnf: usize,
    help,
    version,
    missing,
    unknown,
};

pub fn classify(argv0: []const u8, first_arg: ?[]const u8) Action {
    if (std.mem.eql(u8, std.fs.path.basename(argv0), "tdnf")) {
        return .{ .tdnf = 1 };
    }

    const command = first_arg orelse return .missing;
    if (std.mem.eql(u8, command, "tdnf")) {
        return .{ .tdnf = 2 };
    }
    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        return .help;
    }
    if (std.mem.eql(u8, command, "--version")) {
        return .version;
    }
    return .unknown;
}

test "classifies rpmz top-level invocations" {
    try std.testing.expectEqual(Action.missing, classify("rpmz", null));
    try std.testing.expectEqual(Action.help, classify("rpmz", "--help"));
    try std.testing.expectEqual(Action.help, classify("rpmz", "-h"));
    try std.testing.expectEqual(Action.version, classify("rpmz", "--version"));
    try std.testing.expectEqual(Action.unknown, classify("rpmz", "install"));
    try std.testing.expectEqual(Action{ .tdnf = 2 }, classify("rpmz", "tdnf"));
}

test "classifies tdnf paths as compatibility invocations" {
    try std.testing.expectEqual(Action{ .tdnf = 1 }, classify("tdnf", null));
    try std.testing.expectEqual(Action{ .tdnf = 1 }, classify("/usr/bin/tdnf", "--version"));
    try std.testing.expectEqual(Action{ .tdnf = 1 }, classify("/opt/rpmz/bin/tdnf/", "--help"));
    try std.testing.expectEqual(Action.unknown, classify("/usr/bin/rpmz", "install"));
}
