const std = @import("std");
const scriptlet = @import("scriptlet.zig");
const flags = @import("trans_flags.zig");
const common = @import("transaction_tool_common.zig");

fn parseTsflag(text: []const u8) u32 {
    if (std.mem.eql(u8, text, "noscripts")) return flags.TDNF_RPMTRANS_FLAG_NOSCRIPTS;
    if (std.mem.eql(u8, text, "nopre")) return flags.TDNF_RPMTRANS_FLAG_NOPRE;
    if (std.mem.eql(u8, text, "nopost")) return flags.TDNF_RPMTRANS_FLAG_NOPOST;
    if (std.mem.eql(u8, text, "nopreun")) return flags.TDNF_RPMTRANS_FLAG_NOPREUN;
    if (std.mem.eql(u8, text, "nopostun")) return flags.TDNF_RPMTRANS_FLAG_NOPOSTUN;
    if (std.mem.eql(u8, text, "nopretrans")) return flags.TDNF_RPMTRANS_FLAG_NOPRETRANS;
    if (std.mem.eql(u8, text, "noposttrans")) return flags.TDNF_RPMTRANS_FLAG_NOPOSTTRANS;
    return flags.TDNF_RPMTRANS_FLAG_NONE;
}

fn parsePhase(text: []const u8) ?scriptlet.Phase {
    if (std.mem.eql(u8, text, "pre")) return .pre;
    if (std.mem.eql(u8, text, "post")) return .post;
    if (std.mem.eql(u8, text, "preun")) return .preun;
    if (std.mem.eql(u8, text, "postun")) return .postun;
    if (std.mem.eql(u8, text, "pretrans")) return .pretrans;
    if (std.mem.eql(u8, text, "posttrans")) return .posttrans;
    return null;
}

fn usage(argv0: [*:0]const u8) u8 {
    std.debug.print(
        "usage: {s} --root <root> --phase pre|post|preun|postun|pretrans|posttrans " ++
            "[--arg1 N] [--arg2 N] [--rpmdefine TEXT ...] " ++
            "[--tsflag noscripts|nopre|nopost|nopreun|nopostun|nopretrans|noposttrans ...] " ++
            "[--script-fd N] [--redirect-stdout-to-stderr] <package.rpm>\n",
        .{argv0},
    );
    return 2;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    var install_root: ?[]const u8 = null;
    var rpm_path: ?[*:0]const u8 = null;
    var phase: scriptlet.Phase = .pre;
    var phase_set = false;
    var trans_flags: u32 = flags.TDNF_RPMTRANS_FLAG_NONE;
    var rpmdefines: std.ArrayList([]const u8) = .empty;
    defer rpmdefines.deinit(std.heap.c_allocator);
    var arg1: ?i32 = null;
    var arg2: ?i32 = null;
    var script_fd: ?c_int = null;
    var redirect_stdout_to_stderr = false;

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
        } else if (std.mem.eql(u8, arg, "--phase")) {
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for --phase\n", .{});
                return 2;
            }
            i += 1;
            const value = std.mem.span(argv[i]);
            phase = parsePhase(value) orelse {
                std.debug.print("unsupported --phase value: {s}\n", .{value});
                return 2;
            };
            phase_set = true;
        } else if (std.mem.eql(u8, arg, "--arg1") or
            std.mem.eql(u8, arg, "--arg2"))
        {
            const is_arg1 = std.mem.eql(u8, arg, "--arg1");
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for {s}\n", .{arg});
                return 2;
            }
            i += 1;
            const value_text = std.mem.span(argv[i]);
            const value = common.parseLong(value_text) orelse {
                std.debug.print("invalid {s} value: {s}\n", .{ arg, value_text });
                return 2;
            };
            const narrowed: i32 = @truncate(value);
            const effective = if (narrowed >= 0) narrowed else null;
            if (is_arg1) arg1 = effective else arg2 = effective;
        } else if (std.mem.eql(u8, arg, "--script-fd")) {
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for --script-fd\n", .{});
                return 2;
            }
            i += 1;
            const value_text = std.mem.span(argv[i]);
            const value = common.parseLong(value_text) orelse {
                std.debug.print("invalid --script-fd value: {s}\n", .{value_text});
                return 2;
            };
            if (value < 0) {
                std.debug.print("invalid --script-fd value: {s}\n", .{value_text});
                return 2;
            }
            const narrowed: c_int = @truncate(value);
            script_fd = if (narrowed >= 0) narrowed else null;
        } else if (std.mem.eql(u8, arg, "--redirect-stdout-to-stderr")) {
            redirect_stdout_to_stderr = true;
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
        } else if (std.mem.eql(u8, arg, "--rpmdefine")) {
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for --rpmdefine\n", .{});
                return 2;
            }
            i += 1;
            rpmdefines.append(std.heap.c_allocator, std.mem.span(argv[i])) catch {
                std.debug.print("tdnf-rpm-scriptlet: out of memory\n", .{});
                return 1;
            };
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
    if (!phase_set) return usage(argv[0]);
    const path = rpm_path orelse return usage(argv[0]);
    var rpm = common.openRpm(path) catch |err| {
        std.debug.print(
            "tdnf-rpm-scriptlet: open: rpm_file_open({s}): {t}\n",
            .{ std.mem.span(path), err },
        );
        return 1;
    };
    defer rpm.close(std.heap.c_allocator);

    const result = scriptlet.runHeaderScript(std.heap.c_allocator, rpm.main, phase, .{
        .install_root = root,
        .trans_flags = trans_flags,
        .rpmdefines = rpmdefines.items,
        .arg1 = arg1,
        .arg2 = arg2,
        .script_fd = script_fd,
        .redirect_stdout_to_stderr = redirect_stdout_to_stderr,
    }) catch |err| {
        std.debug.print(
            "tdnf-rpm-scriptlet: run: header_run_scriptlet: {t}\n",
            .{err},
        );
        return 1;
    };
    return switch (result.outcome) {
        .not_run, .ok => 0,
        .exited => if (result.critical) 41 else 40,
        .signaled => if (result.critical) 43 else 42,
    };
}

test "scriptlet phase and transaction flag parsing" {
    try std.testing.expectEqual(scriptlet.Phase.posttrans, parsePhase("posttrans").?);
    try std.testing.expectEqual(flags.TDNF_RPMTRANS_FLAG_NOPRE, parseTsflag("nopre"));
    try std.testing.expectEqual(@as(?scriptlet.Phase, null), parsePhase("triggerin"));
}
