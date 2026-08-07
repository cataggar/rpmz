// Copyright (C) 2022-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const history = @import("history");
const history_config = @import("history_config");

const File = opaque {};
const Option = extern struct {
    name: ?[*:0]const u8,
    has_arg: c_int,
    flag: ?*c_int,
    val: c_int,
};

extern var stderr: *File;
extern var optarg: ?[*:0]u8;
extern var optind: c_int;
extern var opterr: c_int;
extern var optopt: c_int;

extern fn getopt_long(
    argc: c_int,
    argv: [*c]?[*:0]u8,
    short_options: [*:0]const u8,
    long_options: [*]const Option,
    long_index: ?*c_int,
) c_int;
extern fn printf(format: [*:0]const u8, ...) c_int;
extern fn fprintf(stream: *File, format: [*:0]const u8, ...) c_int;

const ERR_CMDLINE: u8 = 1;
const default_db_file = history_config.db_dir ++ "/history.db";

fn usage(cmdname: [*:0]const u8) void {
    _ = printf(
        "tdnf history db utility\n\n" ++
            "Usage:\n\n" ++
            "%s [-f dbfile] [-r rootdir] init|update\n" ++
            "%s [-f dbfile] mark install|remove [pkg[...]]\n" ++
            "\n" ++
            "Commands:\n\n" ++
            "init   - Initialize the history db.\n" ++
            "mark   - Mark a package as user installed ('install') or auto installed ('remove').\n" ++
            "update - Update the history db using the current rpm db.\n" ++
            "\n",
        cmdname,
        cmdname,
    );
}

fn rcToExitCode(rc: c_int) u8 {
    return @truncate(@as(c_uint, @bitCast(rc)));
}

fn checkHistoryRc(rc: c_int, line: comptime_int) ?u8 {
    if (rc == 0) return null;
    _ = fprintf(
        stderr,
        "check_rc failed in main line %d\n",
        @as(c_int, line),
    );
    return rcToExitCode(rc);
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    const argc: c_int = @intCast(argv.len);
    const argv_ptr: [*c]?[*:0]u8 = @ptrCast(@constCast(argv.ptr));

    var db_file: [*:0]const u8 = default_db_file;
    var rpm_root_dir: [*:0]const u8 = "/";

    optind = 1;
    opterr = 1;
    optopt = 0;
    optarg = null;

    while (true) {
        var long_options = [_]Option{
            .{ .name = "file", .has_arg = 1, .flag = null, .val = 'f' },
            .{ .name = "rootdir", .has_arg = 1, .flag = null, .val = 'r' },
            .{ .name = null, .has_arg = 0, .flag = null, .val = 0 },
        };

        const opt = getopt_long(
            argc,
            @ptrCast(argv_ptr),
            "f:r:",
            &long_options,
            null,
        );
        if (opt == -1) break;

        switch (opt) {
            'f' => db_file = optarg.?,
            'r' => rpm_root_dir = optarg.?,
            else => {
                usage(argv[0]);
                return ERR_CMDLINE;
            },
        }
    }

    const ctx = history.create_history_ctx(db_file) orelse {
        _ = fprintf(stderr, "check_ptr failed in main line 95\n");
        return 255;
    };
    defer history.destroy_history_ctx(ctx);

    if (optind >= argc) {
        usage(argv[0]);
        _ = fprintf(stderr, "command expected\n");
        return ERR_CMDLINE;
    }

    const first_arg: usize = @intCast(optind);
    const action = argv[first_arg];
    const argcount = argv.len - first_arg;

    if (std.mem.eql(u8, std.mem.span(action), "init") or
        std.mem.eql(u8, std.mem.span(action), "update"))
    {
        if (checkHistoryRc(history.history_sync(ctx, rpm_root_dir), 112)) |rc| {
            return rc;
        }
        return 0;
    }

    if (std.mem.eql(u8, std.mem.span(action), "mark")) {
        if (argcount < 2) {
            usage(argv[0]);
            _ = fprintf(stderr, "expected 'remove' or 'install'\n");
            return ERR_CMDLINE;
        }

        const subaction = argv[first_arg + 1];
        const flag: c_int = if (std.mem.eql(u8, std.mem.span(subaction), "remove"))
            1
        else if (std.mem.eql(u8, std.mem.span(subaction), "install"))
            0
        else {
            usage(argv[0]);
            _ = fprintf(stderr, "unknown sub command '%s'\n", subaction);
            return ERR_CMDLINE;
        };

        for (argv[first_arg + 2 ..]) |package| {
            if (checkHistoryRc(history.history_set_auto_flag(ctx, package, flag), 134)) |rc| {
                return rc;
            }
        }
        return 0;
    }

    usage(argv[0]);
    _ = fprintf(stderr, "unknown command '%s'\n", action);
    return ERR_CMDLINE;
}
