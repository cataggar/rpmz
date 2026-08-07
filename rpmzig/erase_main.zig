const std = @import("std");
const erase = @import("erase.zig");
const header = @import("rpm_header");
const rpmdb_write = @import("rpmdb_write.zig");
const flags = @import("trans_flags.zig");
const common = @import("transaction_tool_common.zig");

const KeepPathContext = struct {
    writer: *rpmdb_write.Writer,
    hnum: u32,
};

fn keepPath(ctx: ?*anyopaque, path: []const u8) i32 {
    const keep_ctx: *KeepPathContext = @ptrCast(@alignCast(ctx orelse return -1));
    const owned = keep_ctx.writer.pathOwnedByOtherPackage(
        keep_ctx.hnum,
        path,
    ) catch return -1;
    return if (owned) 1 else 0;
}

fn parseTsflag(text: []const u8) u32 {
    if (std.mem.eql(u8, text, "justdb")) return flags.TDNF_RPMTRANS_FLAG_JUSTDB;
    return flags.TDNF_RPMTRANS_FLAG_NONE;
}

fn usage(argv0: [*:0]const u8) u8 {
    std.debug.print(
        "usage: {s} --root <root> [--tsflag justdb] <hnum>\n",
        .{argv0},
    );
    return 2;
}

fn eraseFiles(root: []const u8, hnum: u32, trans_flags: u32) bool {
    var writer = rpmdb_write.Writer.openRoot(root) catch |err| {
        std.debug.print(
            "tdnf-rpm-erase: erase: Writer.openRoot: {t}\n",
            .{err},
        );
        return false;
    };
    defer writer.close();
    const blob = writer.readHeaderBlobCopy(std.heap.c_allocator, hnum) catch |err| {
        std.debug.print(
            "tdnf-rpm-erase: erase: Writer.readHeaderBlobCopy({d}): {t}\n",
            .{ hnum, err },
        );
        return false;
    };
    defer std.heap.c_allocator.free(blob);
    const hdr = header.Header.parse(blob) catch |err| {
        std.debug.print(
            "tdnf-rpm-erase: erase: header.parse({d}): {t}\n",
            .{ hnum, err },
        );
        return false;
    };
    var keep_ctx = KeepPathContext{
        .writer = &writer,
        .hnum = hnum,
    };
    var ctx = erase.Context.init(std.heap.c_allocator, hdr, .{
        .install_root = root,
        .trans_flags = trans_flags,
        .keep_path_fn = keepPath,
        .keep_path_ctx = &keep_ctx,
    }) catch |err| {
        std.debug.print("tdnf-rpm-erase: erase: erase init: {t}\n", .{err});
        return false;
    };
    defer ctx.deinit();
    ctx.erase() catch |err| {
        if (ctx.last_path) |last_path| {
            std.debug.print(
                "tdnf-rpm-erase: erase: rpm_erase_hnum({s}): {t}\n",
                .{ last_path, err },
            );
        } else {
            std.debug.print(
                "tdnf-rpm-erase: erase: rpm_erase_hnum: {t}\n",
                .{err},
            );
        }
        return false;
    };
    return true;
}

fn eraseDbRow(root: []const u8, hnum: u32) bool {
    var writer = rpmdb_write.Writer.openRoot(root) catch |err| {
        std.debug.print(
            "tdnf-rpm-erase: erase-hnum: Writer.openRoot: {t}\n",
            .{err},
        );
        return false;
    };
    defer writer.close();
    writer.eraseHnum(hnum) catch |err| {
        std.debug.print(
            "tdnf-rpm-erase: erase-hnum: Writer.eraseHnum({d}): {t}\n",
            .{ hnum, err },
        );
        return false;
    };
    return true;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    var root: ?[]const u8 = null;
    var hnum: u32 = 0;
    var trans_flags: u32 = flags.TDNF_RPMTRANS_FLAG_NONE;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = std.mem.span(argv[i]);
        if (std.mem.eql(u8, arg, "--root")) {
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for --root\n", .{});
                return 2;
            }
            i += 1;
            root = std.mem.span(argv[i]);
        } else if (std.mem.eql(u8, arg, "--tsflag")) {
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for --tsflag\n", .{});
                return 2;
            }
            i += 1;
            const value = std.mem.span(argv[i]);
            const flag = parseTsflag(value);
            if (flag == flags.TDNF_RPMTRANS_FLAG_NONE) {
                std.debug.print("unsupported --tsflag value: {s}\n", .{value});
                return 2;
            }
            trans_flags |= flag;
        } else if (arg.len != 0 and arg[0] == '-') {
            std.debug.print("unsupported option: {s}\n", .{arg});
            return 2;
        } else if (hnum == 0) {
            hnum = common.parseU32(arg) orelse {
                std.debug.print("invalid hnum: {s}\n", .{arg});
                return 2;
            };
        } else {
            std.debug.print("unexpected positional argument: {s}\n", .{arg});
            return 2;
        }
    }

    const install_root = root orelse return usage(argv[0]);
    if (hnum == 0) return usage(argv[0]);
    if (!eraseFiles(install_root, hnum, trans_flags)) return 1;
    if (!eraseDbRow(install_root, hnum)) return 1;
    return 0;
}

test "erase transaction flag parsing" {
    try std.testing.expectEqual(flags.TDNF_RPMTRANS_FLAG_JUSTDB, parseTsflag("justdb"));
    try std.testing.expectEqual(flags.TDNF_RPMTRANS_FLAG_NONE, parseTsflag("nodocs"));
}
