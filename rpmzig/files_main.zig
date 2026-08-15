const std = @import("std");
const cpio = @import("rpm_cpio");
const pkgfile = @import("rpm_pkgfile");

pub fn main(init: std.process.Init) u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.flush() catch {};

    const argv = init.minimal.args.vector;
    if (argv.len != 2) {
        std.debug.print("usage: {s} <file.rpm>\n", .{std.mem.span(argv[0])});
        return 2;
    }

    const path = std.mem.span(argv[1]);
    var rpm = pkgfile.RpmFile.open(std.heap.c_allocator, path) catch |err| {
        std.debug.print(
            "rpmz-rpm-files: open: rpm_file_open({s}): {t}\n",
            .{ path, err },
        );
        return 1;
    };
    defer rpm.close(std.heap.c_allocator);

    const payload = rpm.decompressPayload(std.heap.c_allocator) catch |err| {
        std.debug.print("rpmz-rpm-files: files_open: decompressPayload: {t}\n", .{err});
        return 1;
    };
    defer std.heap.c_allocator.free(payload);

    var walker = cpio.Walker.init(payload);
    while (true) {
        const entry = walker.next() catch |err| {
            std.debug.print("rpmz-rpm-files: cpio walker: {t}\n", .{err});
            return 1;
        } orelse break;
        stdout.interface.print("{s}\n", .{entry.name}) catch {};
    }
    return 0;
}
