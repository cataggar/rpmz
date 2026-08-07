// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const rpmdb = @import("rpmdb");

extern fn printf(format: [*:0]const u8, ...) c_int;

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    if (argv.len != 3) {
        std.debug.print(
            "usage: {s} <root> <key-file>\n",
            .{std.mem.span(argv[0])},
        );
        return 2;
    }

    const key_path = std.mem.span(argv[2]);
    var threaded = std.Io.Threaded.init(std.heap.c_allocator, .{});
    defer threaded.deinit();
    const data = std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        key_path,
        std.heap.c_allocator,
        .unlimited,
    ) catch {
        std.debug.print(
            "{s}: unable to read {s}\n",
            .{ std.mem.span(argv[0]), key_path },
        );
        return 1;
    };
    defer std.heap.c_allocator.free(data);
    if (data.len == 0) {
        std.debug.print(
            "{s}: unable to read {s}\n",
            .{ std.mem.span(argv[0]), key_path },
        );
        return 1;
    }

    const timestamp = rpmdb.currentRpmTimestamp() catch {
        std.debug.print(
            "{s}: system time is outside the rpm timestamp range\n",
            .{std.mem.span(argv[0])},
        );
        return 1;
    };
    const imported = rpmdb.importPubkeysRoot(
        std.heap.c_allocator,
        std.mem.span(argv[1]),
        data,
        timestamp,
    ) catch |err| {
        std.debug.print(
            "{s}: pubkey import failed: {t}\n",
            .{ std.mem.span(argv[0]), err },
        );
        return 1;
    };

    _ = printf("%zu\n", imported);
    return 0;
}
