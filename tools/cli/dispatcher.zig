// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");

const compatibility_command = "tdnf";
const system_compatibility_path = "/usr/bin/tdnf";
const alternate_compatibility_path = "/opt/rpmz/bin/tdnf/";

pub const Action = union(enum) {
    compatibility: usize,
    help,
    version,
    missing,
    unknown,
};

pub fn classify(argv0: []const u8, first_arg: ?[]const u8) Action {
    if (std.mem.eql(u8, std.fs.path.basename(argv0), compatibility_command)) {
        return .{ .compatibility = 1 };
    }

    const command = first_arg orelse return .missing;
    if (std.mem.eql(u8, command, compatibility_command)) {
        return .{ .compatibility = 2 };
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
    try std.testing.expectEqual(
        Action{ .compatibility = 2 },
        classify("rpmz", compatibility_command),
    );
}

test "classifies compatibility invocation paths" {
    try std.testing.expectEqual(
        Action{ .compatibility = 1 },
        classify(compatibility_command, null),
    );
    try std.testing.expectEqual(
        Action{ .compatibility = 1 },
        classify(system_compatibility_path, "--version"),
    );
    try std.testing.expectEqual(
        Action{ .compatibility = 1 },
        classify(alternate_compatibility_path, "--help"),
    );
    try std.testing.expectEqual(Action.unknown, classify("/usr/bin/rpmz", "install"));
}
