const std = @import("std");
const rpmdb = @import("rpmdb");

pub fn main(init: std.process.Init) u8 {
    var stdout_buffer: [128]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.flush() catch {};

    const argv = init.minimal.args.vector;
    const root = if (argv.len > 1) std.mem.span(argv[1]) else "/";
    const count = rpmdb.countPackages(root) catch {
        const message = rpmdb.lastErrorMessage();
        std.debug.print(
            "rpmz-rpmdb-count: {s}\n",
            .{if (message.len == 0) "unknown error" else message},
        );
        return 1;
    };
    stdout.interface.print("{d}\n", .{count}) catch {};
    return 0;
}
