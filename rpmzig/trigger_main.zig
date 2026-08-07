const std = @import("std");
const trigger = @import("trigger.zig");
const flags = @import("trans_flags.zig");
const common = @import("transaction_tool_common.zig");

fn parseTsflag(text: []const u8) u32 {
    if (std.mem.eql(u8, text, "noscripts")) return flags.TDNF_RPMTRANS_FLAG_NOSCRIPTS;
    if (std.mem.eql(u8, text, "notriggers")) return flags.TDNF_RPMTRANS_FLAG_NOTRIGGERS;
    if (std.mem.eql(u8, text, "notriggerin")) return flags.TDNF_RPMTRANS_FLAG_NOTRIGGERIN;
    if (std.mem.eql(u8, text, "notriggerun")) return flags.TDNF_RPMTRANS_FLAG_NOTRIGGERUN;
    if (std.mem.eql(u8, text, "notriggerpostun")) return flags.TDNF_RPMTRANS_FLAG_NOTRIGGERPOSTUN;
    return flags.TDNF_RPMTRANS_FLAG_NONE;
}

fn parsePhase(text: []const u8) ?trigger.Phase {
    if (std.mem.eql(u8, text, "triggerin") or std.mem.eql(u8, text, "in")) return .triggerin;
    if (std.mem.eql(u8, text, "triggerun") or std.mem.eql(u8, text, "un")) return .triggerun;
    if (std.mem.eql(u8, text, "triggerpostun") or std.mem.eql(u8, text, "postun")) return .triggerpostun;
    return null;
}

fn usage(argv0: [*:0]const u8) u8 {
    std.debug.print(
        "usage: {s} --db-root <root> [--install-root <root>] [--root <root>] " ++
            "--phase triggerin|triggerun|triggerpostun " ++
            "[--rpmdefine TEXT ...] " ++
            "[--tsflag noscripts|notriggers|notriggerin|notriggerun|notriggerpostun ...] " ++
            "[--script-fd N] [--redirect-stdout-to-stderr] [--arg2 N] <package.rpm>\n",
        .{argv0},
    );
    return 2;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    var db_root: ?[]const u8 = null;
    var install_root: ?[]const u8 = null;
    var shared_root: ?[]const u8 = null;
    var rpm_path: ?[*:0]const u8 = null;
    var phase: trigger.Phase = .triggerin;
    var phase_set = false;
    var trans_flags: u32 = flags.TDNF_RPMTRANS_FLAG_NONE;
    var rpmdefines: std.ArrayList([]const u8) = .empty;
    defer rpmdefines.deinit(std.heap.c_allocator);
    var script_fd: ?c_int = null;
    var redirect_stdout_to_stderr = false;
    var arg2: ?i32 = null;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = std.mem.span(argv[i]);
        if (std.mem.eql(u8, arg, "--root") or
            std.mem.eql(u8, arg, "--db-root") or
            std.mem.eql(u8, arg, "--install-root"))
        {
            if (i + 1 >= argv.len) {
                std.debug.print("missing argument for {s}\n", .{arg});
                return 2;
            }
            i += 1;
            const value = std.mem.span(argv[i]);
            if (std.mem.eql(u8, arg, "--root")) {
                shared_root = value;
            } else if (std.mem.eql(u8, arg, "--db-root")) {
                db_root = value;
            } else {
                install_root = value;
            }
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
        } else if (std.mem.eql(u8, arg, "--script-fd") or
            std.mem.eql(u8, arg, "--arg2"))
        {
            const is_script_fd = std.mem.eql(u8, arg, "--script-fd");
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
            if (is_script_fd) {
                if (value < 0) {
                    std.debug.print("invalid --script-fd value: {s}\n", .{value_text});
                    return 2;
                }
                const narrowed: c_int = @truncate(value);
                script_fd = if (narrowed >= 0) narrowed else null;
            } else {
                arg2 = @truncate(value);
            }
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
                std.debug.print("tdnf-rpm-trigger: out of memory\n", .{});
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

    const effective_db_root = db_root orelse shared_root orelse install_root;
    const effective_install_root = install_root orelse shared_root orelse "/";
    const root = effective_db_root orelse return usage(argv[0]);
    if (!phase_set) return usage(argv[0]);
    const path = rpm_path orelse return usage(argv[0]);
    var rpm = common.openRpm(path) catch |err| {
        std.debug.print(
            "tdnf-rpm-trigger: open: rpm_file_open({s}): {t}\n",
            .{ std.mem.span(path), err },
        );
        return 1;
    };
    defer rpm.close(std.heap.c_allocator);

    const result = trigger.runHeaderTriggers(std.heap.c_allocator, rpm.main, phase, .{
        .db_root = root,
        .install_root = effective_install_root,
        .trans_flags = trans_flags,
        .rpmdefines = rpmdefines.items,
        .script_fd = script_fd,
        .redirect_stdout_to_stderr = redirect_stdout_to_stderr,
        .arg2_override = arg2,
    }) catch |err| {
        std.debug.print(
            "tdnf-rpm-trigger: run: header_run_triggers: {t}\n",
            .{err},
        );
        return 1;
    };
    return switch (result.outcome) {
        .not_run, .ok => 0,
        .exited => 40,
        .signaled => 42,
    };
}

test "trigger phase aliases and transaction flags" {
    try std.testing.expectEqual(trigger.Phase.triggerin, parsePhase("in").?);
    try std.testing.expectEqual(trigger.Phase.triggerpostun, parsePhase("postun").?);
    try std.testing.expectEqual(
        flags.TDNF_RPMTRANS_FLAG_NOTRIGGERUN,
        parseTsflag("notriggerun"),
    );
}
