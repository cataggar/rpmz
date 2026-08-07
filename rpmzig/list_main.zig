const std = @import("std");
const rpmdb = @import("rpmdb");

pub fn main(init: std.process.Init) u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.flush() catch {};

    const argv = init.minimal.args.vector;
    const root = if (argv.len > 1) std.mem.span(argv[1]) else "/";
    const iterator = rpmdb.Iter.openRoot(root) catch |err| {
        std.debug.print("tdnf-rpmdb-list: open: rpmdb_iter_open: {t}\n", .{err});
        return 1;
    };
    defer iterator.close();

    while (true) {
        const package_header = iterator.nextHeader() catch |err| {
            std.debug.print("tdnf-rpmdb-list: iter.nextHeader: {t}\n", .{err});
            return 1;
        } orelse break;
        const nevra = package_header.allocNevra(std.heap.c_allocator) catch {
            std.debug.print("tdnf-rpmdb-list: out of memory building NEVRA\n", .{});
            return 1;
        } orelse {
            std.debug.print("tdnf-rpmdb-list: header missing required tag for NEVRA\n", .{});
            return 1;
        };
        stdout.interface.print("{s}\n", .{nevra}) catch {};
        std.heap.c_allocator.free(nevra);
    }
    return 0;
}
