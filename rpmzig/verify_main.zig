const std = @import("std");
const pkgfile = @import("rpm_pkgfile");
const rpmdb = @import("rpmdb");
const verifier = rpmdb.standalone_verifier;

const Key = union(enum) {
    file: []u8,
    rpmdb: rpmdb.PubkeyRecord,

    fn bytes(self: Key) []const u8 {
        return switch (self) {
            .file => |value| value,
            .rpmdb => |value| value.key,
        };
    }

    fn deinit(self: *Key, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .file => |value| allocator.free(value),
            .rpmdb => |*value| value.deinit(allocator),
        }
    }
};

fn keyOpenError(error_value: anyerror) []const u8 {
    return switch (error_value) {
        error.FileNotFound => "No such file or directory",
        error.AccessDenied => "Permission denied",
        error.IsDir => "Is a directory",
        error.NameTooLong => "File name too long",
        error.NotDir => "Not a directory",
        error.SystemResources => "Too many open files",
        else => @errorName(error_value),
    };
}

pub fn main(init: std.process.Init) u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &stdout_buffer);
    defer stdout.flush() catch {};

    const allocator = std.heap.c_allocator;
    const argv = init.minimal.args.vector;
    if (argv.len < 2) {
        std.debug.print(
            "usage: {s} <file.rpm> [--key <key.asc> ...] [--rpmdb [root]]\n",
            .{std.mem.span(argv[0])},
        );
        return 4;
    }

    var keys = std.ArrayList(Key).empty;
    defer {
        for (keys.items) |*key| key.deinit(allocator);
        keys.deinit(allocator);
    }
    var use_rpmdb = false;
    var rpmdb_root: [*:0]const u8 = "/";

    var index: usize = 2;
    while (index < argv.len) : (index += 1) {
        const arg = std.mem.span(argv[index]);
        if (std.mem.eql(u8, arg, "--key") and index + 1 < argv.len) {
            index += 1;
            const path = std.mem.span(argv[index]);
            const bytes = read: {
                var file = std.Io.Dir.cwd().openFile(
                    init.io,
                    path,
                    .{ .allow_directory = true },
                ) catch |err| {
                    std.debug.print(
                        "rpmz-rpm-verify: open key {s}: {s}\n",
                        .{ path, keyOpenError(err) },
                    );
                    return 4;
                };
                defer file.close(init.io);
                var file_reader = file.reader(init.io, &.{});
                // The C helper diagnosed fopen failures but silently returned
                // for every later seek, allocation, or read failure.
                break :read file_reader.interface.allocRemaining(
                    allocator,
                    .unlimited,
                ) catch return 4;
            };
            keys.append(allocator, .{ .file = bytes }) catch {
                allocator.free(bytes);
                return 4;
            };
        } else if (std.mem.eql(u8, arg, "--rpmdb")) {
            use_rpmdb = true;
            if (index + 1 < argv.len and argv[index + 1][0] != '-') {
                index += 1;
                rpmdb_root = argv[index];
            }
        } else {
            std.debug.print("unknown arg: {s}\n", .{arg});
            return 4;
        }
    }

    const path = std.mem.span(argv[1]);
    var rpm = pkgfile.RpmFile.open(allocator, path) catch |err| {
        std.debug.print(
            "rpmz-rpm-verify: open: rpm_file_open({s}): {t}\n",
            .{ path, err },
        );
        return 4;
    };
    defer rpm.close(allocator);

    stdout.interface.print(
        "Verifier: pure-Zig\nSignature: {s}\n",
        .{rpm.signatureKind().name()},
    ) catch {};
    stdout.flush() catch {};

    if (use_rpmdb) {
        var loaded: usize = 0;
        const source = rpmdb.openPubkeysRoot(
            std.mem.span(rpmdb_root),
        ) catch {
            std.debug.print(
                "rpmz-rpm-verify: rpmdb open {s}: {s}\n",
                .{ std.mem.span(rpmdb_root), rpmdb.lastErrorMessage() },
            );
            return 4;
        };
        defer rpmdb.closePubkeys(source);
        while (true) {
            var key = rpmdb.nextPubkey(allocator, source) catch {
                std.debug.print(
                    "rpmz-rpm-verify: rpmdb walk: {s}\n",
                    .{rpmdb.lastErrorMessage()},
                );
                return 4;
            } orelse break;
            keys.append(allocator, .{ .rpmdb = key }) catch {
                key.deinit(allocator);
                return 4;
            };
            loaded += 1;
        }
        stdout.interface.print(
            "RpmDB:     {d} key(s) under {s}\n",
            .{ loaded, std.mem.span(rpmdb_root) },
        ) catch {};
    }

    var key_slices = std.ArrayList([]const u8).empty;
    defer key_slices.deinit(allocator);
    key_slices.ensureTotalCapacity(allocator, keys.items.len) catch return 4;
    for (keys.items) |key| key_slices.appendAssumeCapacity(key.bytes());

    const status = verifier.verifyRpm(
        allocator,
        &rpm,
        key_slices.items,
    );
    const result: struct { text: []const u8, exit_code: u8 } = switch (status) {
        .ok => .{ .text = "OK", .exit_code = 0 },
        .no_sig => .{ .text = "no signature", .exit_code = 1 },
        .no_key => .{
            .text = "signature present, NO matching key",
            .exit_code = 2,
        },
        .bad => .{ .text = "BAD signature", .exit_code = 3 },
        .internal => .{
            .text = "internal error / unsupported input",
            .exit_code = 4,
        },
    };
    stdout.interface.print("Result:    {s}\n", .{result.text}) catch {};
    return result.exit_code;
}
