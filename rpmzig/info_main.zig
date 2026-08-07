const std = @import("std");
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
        std.debug.print("tdnf-rpm-info: rpm_file_open({s}): {t}\n", .{ path, err });
        return 1;
    };
    defer rpm.close(std.heap.c_allocator);

    const nevra = rpm.allocNevra(std.heap.c_allocator) catch {
        std.debug.print("tdnf-rpm-info: nevra: out of memory\n", .{});
        return 1;
    } orelse {
        std.debug.print(
            "tdnf-rpm-info: nevra: file header missing required tag for NEVRA\n",
            .{},
        );
        return 1;
    };
    defer std.heap.c_allocator.free(nevra);

    stdout.interface.print(
        "NEVRA:       {s}\n" ++
            "Compressor:  {s}\n" ++
            "Payload at:  {d}\n" ++
            "Signature:   {s}\n",
        .{
            nevra,
            rpm.compressor.name(),
            rpm.payload_offset,
            rpm.signatureKind().name(),
        },
    ) catch {};
    return 0;
}
