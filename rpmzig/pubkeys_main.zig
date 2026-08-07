// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const rpmdb = @import("rpmdb");

const File = opaque {};
extern var stdout: *File;
extern fn printf(format: [*:0]const u8, ...) c_int;
extern fn fwrite(
    ptr: *const anyopaque,
    size: usize,
    count: usize,
    stream: *File,
) usize;
extern fn fputc(ch: c_int, stream: *File) c_int;

const usage = "usage: tdnf-rpmdb-pubkeys [--dump] [root]\n";

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    var root: []const u8 = "/";
    var dump = false;

    for (argv[1..]) |arg_z| {
        const arg = std.mem.span(arg_z);
        if (std.mem.eql(u8, arg, "--dump")) {
            dump = true;
        } else if (arg.len != 0 and arg[0] == '-') {
            std.debug.print(usage, .{});
            return 2;
        } else {
            root = arg;
        }
    }

    const iter = rpmdb.openPubkeysRoot(root) catch {
        std.debug.print(
            "tdnf-rpmdb-pubkeys: open: {s}\n",
            .{rpmdb.lastErrorMessage()},
        );
        return 1;
    };
    defer rpmdb.closePubkeys(iter);

    var count: usize = 0;
    while (true) {
        var record = (rpmdb.nextPubkey(
            std.heap.c_allocator,
            iter,
        ) catch {
            std.debug.print(
                "tdnf-rpmdb-pubkeys: {s}\n",
                .{rpmdb.lastErrorMessage()},
            );
            return 1;
        }) orelse break;
        defer record.deinit(std.heap.c_allocator);

        _ = printf("%s  %zu\n", record.keyid.?.ptr, record.key.len);
        if (dump) {
            const dump_len = std.mem.indexOfScalar(
                u8,
                record.key,
                0,
            ) orelse record.key.len;
            _ = fwrite(record.key.ptr, 1, dump_len, stdout);
            if (record.key.len == 0 or
                record.key[record.key.len - 1] != '\n')
            {
                _ = fputc('\n', stdout);
            }
        }
        count += 1;
    }

    if (count == 0) {
        std.debug.print(
            "tdnf-rpmdb-pubkeys: no gpg-pubkey-* entries found " ++
                "in rpmdb under {s}\n",
            .{root},
        );
    }
    return 0;
}
