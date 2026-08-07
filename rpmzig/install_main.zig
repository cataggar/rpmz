const std = @import("std");
const header = @import("rpm_header");
const install = @import("install.zig");
const pkgfile = @import("rpm_pkgfile");
const flags = @import("trans_flags.zig");
const common = @import("transaction_tool_common.zig");

fn parseTsflag(text: []const u8) u32 {
    if (std.mem.eql(u8, text, "justdb")) return flags.TDNF_RPMTRANS_FLAG_JUSTDB;
    if (std.mem.eql(u8, text, "nodocs")) return flags.TDNF_RPMTRANS_FLAG_NODOCS;
    if (std.mem.eql(u8, text, "nocaps")) return flags.TDNF_RPMTRANS_FLAG_NOCAPS;
    if (std.mem.eql(u8, text, "noconfigs")) return flags.TDNF_RPMTRANS_FLAG_NOCONFIGS;
    return flags.TDNF_RPMTRANS_FLAG_NONE;
}

fn usage(argv0: [*:0]const u8) u8 {
    std.debug.print(
        "usage: {s} --root <root> [--upgrade|--reinstall] " ++
            "[--prior <old.rpm> ...] " ++
            "[--tsflag justdb|nodocs|nocaps|noconfigs ...] <new.rpm>\n",
        .{argv0},
    );
    return 2;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    var install_root: ?[]const u8 = null;
    var rpm_path: ?[*:0]const u8 = null;
    var install_kind: install.InstallKind = .install;
    var trans_flags: u32 = flags.TDNF_RPMTRANS_FLAG_NONE;
    var prior_files: std.ArrayList(pkgfile.RpmFile) = .empty;
    defer {
        for (prior_files.items) |*rpm| rpm.close(std.heap.c_allocator);
        prior_files.deinit(std.heap.c_allocator);
    }
    var prior_headers: std.ArrayList(header.Header) = .empty;
    defer prior_headers.deinit(std.heap.c_allocator);

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = std.mem.span(argv[i]);
        if (std.mem.eql(u8, arg, "--root")) {
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for --root\n", .{});
                return 2;
            }
            i += 1;
            install_root = std.mem.span(argv[i]);
        } else if (std.mem.eql(u8, arg, "--upgrade")) {
            install_kind = .upgrade;
        } else if (std.mem.eql(u8, arg, "--reinstall")) {
            install_kind = .reinstall;
        } else if (std.mem.eql(u8, arg, "--prior")) {
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for --prior\n", .{});
                return 2;
            }
            i += 1;
            const path: [*:0]const u8 = argv[i];
            var prior = common.openRpm(path) catch |err| {
                std.debug.print(
                    "tdnf-rpm-install: open prior rpm: rpm_file_open({s}): {t}\n",
                    .{ std.mem.span(path), err },
                );
                return 1;
            };
            prior_files.append(std.heap.c_allocator, prior) catch {
                prior.close(std.heap.c_allocator);
                std.debug.print("tdnf-rpm-install: out of memory\n", .{});
                return 1;
            };
            prior_headers.append(
                std.heap.c_allocator,
                prior_files.items[prior_files.items.len - 1].main,
            ) catch {
                std.debug.print("tdnf-rpm-install: out of memory\n", .{});
                return 1;
            };
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
        } else if (rpm_path == null) {
            rpm_path = argv[i];
        } else {
            std.debug.print("unexpected positional argument: {s}\n", .{arg});
            return 2;
        }
    }

    const root = install_root orelse return usage(argv[0]);
    const path = rpm_path orelse return usage(argv[0]);
    var rpm = common.openRpm(path) catch |err| {
        std.debug.print(
            "tdnf-rpm-install: open: rpm_file_open({s}): {t}\n",
            .{ std.mem.span(path), err },
        );
        return 1;
    };
    defer rpm.close(std.heap.c_allocator);

    var ctx = install.Context.init(std.heap.c_allocator, &rpm, .{
        .install_root = root,
        .trans_flags = trans_flags,
        .install_kind = install_kind,
        .prior_headers = prior_headers.items,
    }) catch |err| {
        std.debug.print("tdnf-rpm-install: install: install init: {t}\n", .{err});
        return 1;
    };
    defer ctx.deinit();
    ctx.install() catch |err| {
        if (ctx.last_path) |last_path| {
            std.debug.print(
                "tdnf-rpm-install: install: rpm_file_install({s}): {t}\n",
                .{ last_path, err },
            );
        } else {
            std.debug.print(
                "tdnf-rpm-install: install: rpm_file_install: {t}\n",
                .{err},
            );
        }
        return 1;
    };
    return 0;
}

test "install transaction flags" {
    try std.testing.expectEqual(flags.TDNF_RPMTRANS_FLAG_JUSTDB, parseTsflag("justdb"));
    try std.testing.expectEqual(flags.TDNF_RPMTRANS_FLAG_NODOCS, parseTsflag("nodocs"));
    try std.testing.expectEqual(flags.TDNF_RPMTRANS_FLAG_NONE, parseTsflag("noscripts"));
}
