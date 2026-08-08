// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU General Public License v2 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");

pub fn mapAddFormatted(
    allocator: std.mem.Allocator,
    add_string: anytype,
    jd: anytype,
    key: [*:0]const u8,
    comptime format: []const u8,
    args: anytype,
) c_int {
    const value = std.fmt.allocPrintSentinel(
        allocator,
        format,
        args,
        0,
    ) catch return -1;
    defer allocator.free(value);

    return add_string(jd, key, value.ptr);
}
