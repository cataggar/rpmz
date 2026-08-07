// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const rpmdb = @import("rpmdb");

extern fn printf(format: [*:0]const u8, ...) c_int;
extern fn strtoul(
    text: [*:0]const u8,
    end: *?[*:0]u8,
    base: c_int,
) c_ulong;
extern fn time(timer: ?*c_long) c_long;

fn usage(argv0: []const u8) void {
    std.debug.print(
        "usage:\n" ++
            "  {s} install <root> <file.rpm> [install_tid [install_time [install_color]]]\n" ++
            "  {s} replace <root> <old_hnum> <file.rpm> [install_tid [install_time [install_color]]]\n" ++
            "  {s} erase-hnum <root> <hnum>\n" ++
            "  {s} find-hnum <root> <nevra>\n",
        .{ argv0, argv0, argv0, argv0 },
    );
}

fn parseU32(text: [*:0]const u8) ?u32 {
    var end: ?[*:0]u8 = null;
    const value = strtoul(text, &end, 10);
    if (text[0] == 0 or end == null or end.?[0] != 0 or
        value > std.math.maxInt(u32))
    {
        return null;
    }
    return @intCast(value);
}

fn currentTimeU32() u32 {
    return @truncate(@as(c_ulong, @bitCast(time(null))));
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    const argv0 = std.mem.span(argv[0]);
    if (argv.len < 2) {
        usage(argv0);
        return 2;
    }

    const command = std.mem.span(argv[1]);
    if (std.mem.eql(u8, command, "install")) {
        if (argv.len < 4 or argv.len > 7) {
            usage(argv0);
            return 2;
        }
        var tid = if (argv.len > 4) 0 else currentTimeU32();
        var when = tid;
        var color: u32 = rpmdb.DEFAULT_INSTALL_COLOR;
        if (argv.len > 4) {
            tid = parseU32(argv[4]) orelse {
                std.debug.print(
                    "invalid install_tid: {s}\n",
                    .{std.mem.span(argv[4])},
                );
                return 2;
            };
        }
        if (argv.len > 5) {
            when = parseU32(argv[5]) orelse {
                std.debug.print(
                    "invalid install_time: {s}\n",
                    .{std.mem.span(argv[5])},
                );
                return 2;
            };
        }
        if (argv.len > 6) {
            color = parseU32(argv[6]) orelse {
                std.debug.print(
                    "invalid install_color: {s}\n",
                    .{std.mem.span(argv[6])},
                );
                return 2;
            };
        }
        if (argv.len == 5) when = tid;

        var writer = rpmdb.RpmDbWriter.openRoot(
            std.mem.span(argv[2]),
        ) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write install: Writer.openRoot: {t}\n",
                .{err},
            );
            return 1;
        };
        defer writer.close();
        const rpm_path = std.mem.span(argv[3]);
        const rpm_path_z = argv[3][0..rpm_path.len :0];
        const hnum = writer.installRpmPath(rpm_path_z, .{
            .install_tid = tid,
            .install_time = if (when == 0) null else when,
            .install_color = color,
        }) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write install: Writer.installRpmPath({s}): {t}\n",
                .{ rpm_path, err },
            );
            return 1;
        };
        _ = printf("%u\n", hnum);
        return 0;
    }

    if (std.mem.eql(u8, command, "replace")) {
        if (argv.len < 5 or argv.len > 8) {
            usage(argv0);
            return 2;
        }
        const old_hnum = parseU32(argv[3]) orelse {
            std.debug.print(
                "invalid old_hnum: {s}\n",
                .{std.mem.span(argv[3])},
            );
            return 2;
        };
        var tid = if (argv.len > 5) 0 else currentTimeU32();
        var when = tid;
        var color: u32 = rpmdb.DEFAULT_INSTALL_COLOR;
        if (argv.len > 5) {
            tid = parseU32(argv[5]) orelse {
                std.debug.print(
                    "invalid install_tid: {s}\n",
                    .{std.mem.span(argv[5])},
                );
                return 2;
            };
        }
        if (argv.len > 6) {
            when = parseU32(argv[6]) orelse {
                std.debug.print(
                    "invalid install_time: {s}\n",
                    .{std.mem.span(argv[6])},
                );
                return 2;
            };
        }
        if (argv.len > 7) {
            color = parseU32(argv[7]) orelse {
                std.debug.print(
                    "invalid install_color: {s}\n",
                    .{std.mem.span(argv[7])},
                );
                return 2;
            };
        }
        if (argv.len == 6) when = tid;

        var writer = rpmdb.RpmDbWriter.openRoot(
            std.mem.span(argv[2]),
        ) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write replace: Writer.openRoot: {t}\n",
                .{err},
            );
            return 1;
        };
        defer writer.close();
        const rpm_path = std.mem.span(argv[4]);
        var rpm = rpmdb.RpmFile.open(
            std.heap.c_allocator,
            argv[4][0..rpm_path.len :0],
        ) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write replace: RpmFile.open({s}): {t}\n",
                .{ rpm_path, err },
            );
            return 1;
        };
        defer rpm.close(std.heap.c_allocator);
        const hnum = writer.replaceRpm(old_hnum, &rpm, .{
            .install_tid = tid,
            .install_time = if (when == 0) null else when,
            .install_color = color,
        }) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write replace: Writer.replaceRpm({s}): {t}\n",
                .{ rpm_path, err },
            );
            return 1;
        };
        _ = printf("%u\n", hnum);
        return 0;
    }

    if (std.mem.eql(u8, command, "erase-hnum")) {
        if (argv.len != 4) {
            usage(argv0);
            return 2;
        }
        const hnum = parseU32(argv[3]) orelse {
            std.debug.print(
                "invalid hnum: {s}\n",
                .{std.mem.span(argv[3])},
            );
            return 2;
        };
        var writer = rpmdb.RpmDbWriter.openRoot(
            std.mem.span(argv[2]),
        ) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write erase-hnum: Writer.openRoot: {t}\n",
                .{err},
            );
            return 1;
        };
        defer writer.close();
        writer.eraseHnum(hnum) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write erase-hnum: Writer.eraseHnum({d}): {t}\n",
                .{ hnum, err },
            );
            return 1;
        };
        return 0;
    }

    if (std.mem.eql(u8, command, "find-hnum")) {
        if (argv.len != 4) {
            usage(argv0);
            return 2;
        }
        var writer = rpmdb.RpmDbWriter.openRoot(
            std.mem.span(argv[2]),
        ) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write find-hnum: Writer.openRoot: {t}\n",
                .{err},
            );
            return 1;
        };
        defer writer.close();
        const hnum = writer.findHnumByNevra(
            std.heap.c_allocator,
            std.mem.span(argv[3]),
        ) catch |err| {
            std.debug.print(
                "tdnf-rpmdb-write find-hnum: Writer.findHnumByNevra: {t}\n",
                .{err},
            );
            return 1;
        } orelse return 3;
        _ = printf("%u\n", hnum);
        return 0;
    }

    usage(argv0);
    return 2;
}
