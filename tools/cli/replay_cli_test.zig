//! Binary-level offline replay CLI coverage.

const std = @import("std");
const rpmz = @import("rpmz");
const replay_options = @import("replay_options.zig");

const allocator = std.testing.allocator;
const compatibility_command = "tdnf";
const io = std.testing.io;
const replay = rpmz.replay;
const resolver = rpmz.resolver;
const bundle_export = rpmz.bundle_export;

fn appendBe32(list: *std.array_list.Managed(u8), value: u32) !void {
    try list.append(@intCast((value >> 24) & 0xff));
    try list.append(@intCast((value >> 16) & 0xff));
    try list.append(@intCast((value >> 8) & 0xff));
    try list.append(@intCast(value & 0xff));
}

fn readBe32(bytes: []const u8) u32 {
    return @as(u32, bytes[0]) << 24 |
        @as(u32, bytes[1]) << 16 |
        @as(u32, bytes[2]) << 8 |
        @as(u32, bytes[3]);
}

fn writeBe32(bytes: []u8, value: u32) void {
    bytes[0] = @intCast((value >> 24) & 0xff);
    bytes[1] = @intCast((value >> 16) & 0xff);
    bytes[2] = @intCast((value >> 8) & 0xff);
    bytes[3] = @intCast(value & 0xff);
}

fn stringHeaderBlob(
    tags: []const u32,
    values: []const []const u8,
) ![]u8 {
    var data = std.array_list.Managed(u8).init(allocator);
    defer data.deinit();
    var index = std.array_list.Managed(u8).init(allocator);
    defer index.deinit();
    for (tags, values) |tag, value| {
        try appendBe32(&index, tag);
        try appendBe32(&index, 6);
        try appendBe32(&index, @intCast(data.items.len));
        try appendBe32(&index, 1);
        try data.appendSlice(value);
        try data.append(0);
    }
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try appendBe32(&out, @intCast(tags.len));
    try appendBe32(&out, @intCast(data.items.len));
    try out.appendSlice(index.items);
    try out.appendSlice(data.items);
    return out.toOwnedSlice();
}

fn binaryHeaderBlob(tag: u32, value: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try appendBe32(&out, 1);
    try appendBe32(&out, @intCast(value.len));
    try appendBe32(&out, tag);
    try appendBe32(&out, 7);
    try appendBe32(&out, 0);
    try appendBe32(&out, @intCast(value.len));
    try out.appendSlice(value);
    return out.toOwnedSlice();
}

fn standaloneHeader(blob: []const u8, region_tag: u32) ![]u8 {
    const count = readBe32(blob[0..4]);
    const data_size = readBe32(blob[4..8]);
    const new_count = count + 1;
    const bytes = try allocator.alloc(
        u8,
        8 + 8 + @as(usize, new_count) * 16 + data_size + 16,
    );
    @memcpy(bytes[0..8], &[_]u8{ 0x8e, 0xad, 0xe8, 0x01, 0, 0, 0, 0 });
    const raw = bytes[8..];
    writeBe32(raw[0..4], new_count);
    writeBe32(raw[4..8], data_size + 16);
    writeBe32(raw[8..12], region_tag);
    writeBe32(raw[12..16], 7);
    writeBe32(raw[16..20], data_size);
    writeBe32(raw[20..24], 16);
    const old_index_len = @as(usize, count) * 16;
    @memcpy(raw[24 .. 24 + old_index_len], blob[8 .. 8 + old_index_len]);
    const data_start = 8 + @as(usize, new_count) * 16;
    @memcpy(
        raw[data_start .. data_start + data_size],
        blob[8 + old_index_len ..][0..data_size],
    );
    const trailer = raw[data_start + data_size ..][0..16];
    writeBe32(trailer[0..4], region_tag);
    writeBe32(trailer[4..8], 7);
    writeBe32(
        trailer[8..12],
        @bitCast(-@as(i32, @intCast(new_count * 16))),
    );
    writeBe32(trailer[12..16], 16);
    return bytes;
}

fn minimalRpm(
    preinstall: ?[]const u8,
    preinstall_interpreter: ?[]const u8,
) ![]u8 {
    var tags: [8]u32 = undefined;
    var values: [8][]const u8 = undefined;
    var count: usize = 0;
    for ([_]struct { u32, []const u8 }{
        .{ 1000, "replay-app" },
        .{ 1001, "1" },
        .{ 1002, "1" },
        .{ 1022, "x86_64" },
    }) |entry| {
        tags[count] = entry[0];
        values[count] = entry[1];
        count += 1;
    }
    if (preinstall) |script| {
        tags[count] = 1023;
        values[count] = script;
        count += 1;
        if (preinstall_interpreter) |interpreter| {
            tags[count] = 1085;
            values[count] = interpreter;
            count += 1;
        }
    }
    tags[count] = 1124;
    values[count] = "cpio";
    count += 1;
    tags[count] = 1125;
    values[count] = "none";
    count += 1;

    const payload =
        "070701" ++
        "00000000" ++
        "00000000" ++
        "00000000" ++
        "00000000" ++
        "00000001" ++
        "00000000" ++
        "00000000" ++
        "00000000" ++
        "00000000" ++
        "00000000" ++
        "00000000" ++
        "0000000b" ++
        "00000000" ++
        "TRAILER!!!\x00\x00\x00\x00";
    const main_blob = try stringHeaderBlob(tags[0..count], values[0..count]);
    defer allocator.free(main_blob);
    const main_header = try standaloneHeader(main_blob, 63);
    defer allocator.free(main_header);
    const signed_bytes = try allocator.alloc(u8, main_header.len + payload.len);
    defer allocator.free(signed_bytes);
    @memcpy(signed_bytes[0..main_header.len], main_header);
    @memcpy(signed_bytes[main_header.len..], payload);
    var md5: [std.crypto.hash.Md5.digest_length]u8 = undefined;
    std.crypto.hash.Md5.hash(signed_bytes, &md5, .{});
    const signature_blob = try binaryHeaderBlob(1004, &md5);
    defer allocator.free(signature_blob);
    const signature = try standaloneHeader(signature_blob, 62);
    defer allocator.free(signature);

    const padding = (8 - (signature.len % 8)) % 8;
    const bytes = try allocator.alloc(
        u8,
        96 + signature.len + padding + main_header.len + payload.len,
    );
    @memset(bytes, 0);
    @memcpy(bytes[0..4], &[_]u8{ 0xed, 0xab, 0xee, 0xdb });
    @memcpy(bytes[96 .. 96 + signature.len], signature);
    const main_offset = 96 + signature.len + padding;
    @memcpy(bytes[main_offset .. main_offset + main_header.len], main_header);
    @memcpy(bytes[main_offset + main_header.len ..], payload);
    return bytes;
}

fn digestHex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    for (digest, 0..) |byte, index| {
        _ = std.fmt.bufPrint(
            hex[index * 2 .. index * 2 + 2],
            "{x:0>2}",
            .{byte},
        ) catch unreachable;
    }
    return hex;
}

fn primaryXml(rpm: []const u8) ![]u8 {
    const digest = digestHex(rpm);
    return std.fmt.allocPrint(allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<metadata xmlns="http://linux.duke.edu/metadata/common"
        \\              xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="1">
        \\  <package type="rpm">
        \\    <name>replay-app</name>
        \\    <arch>x86_64</arch>
        \\    <version epoch="0" ver="1" rel="1"/>
        \\    <checksum type="sha256" pkgid="YES">{s}</checksum>
        \\    <size package="{d}"/>
        \\    <location href="packages/replay-app.rpm"/>
        \\  </package>
        \\</metadata>
        \\
    , .{ &digest, rpm.len });
}

fn repomdXml(primary: []const u8) ![]u8 {
    const digest = digestHex(primary);
    return std.fmt.allocPrint(allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
        \\  <revision>replay-cli-test</revision>
        \\  <data type="primary">
        \\    <checksum type="sha256">{s}</checksum>
        \\    <open-checksum type="sha256">{s}</open-checksum>
        \\    <location href="repodata/primary.xml"/>
        \\    <timestamp>123</timestamp>
        \\    <size>{d}</size>
        \\    <open-size>{d}</open-size>
        \\  </data>
        \\</repomd>
        \\
    , .{ &digest, &digest, primary.len, primary.len });
}

const Fixture = struct {
    tmp: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    base: []const u8,
    snapshot: []const u8,
    repositories: [1]resolver.Repository,

    fn create(preinstall: ?[]const u8) !Fixture {
        return createWithInterpreter(preinstall, null);
    }

    fn createWithInterpreter(
        preinstall: ?[]const u8,
        preinstall_interpreter: ?[]const u8,
    ) !Fixture {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        try tmp.dir.createDirPath(io, "snapshot/repodata");
        try tmp.dir.createDirPath(io, "snapshot/packages");
        try tmp.dir.createDirPath(io, "work");

        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const length = try tmp.dir.realPath(io, &buffer);
        const base = try arena.allocator().dupe(u8, buffer[0..length]);
        const snapshot = try std.fmt.allocPrint(
            arena.allocator(),
            "{s}/snapshot",
            .{base},
        );

        const rpm = try minimalRpm(preinstall, preinstall_interpreter);
        defer allocator.free(rpm);
        const primary = try primaryXml(rpm);
        defer allocator.free(primary);
        const repomd = try repomdXml(primary);
        defer allocator.free(repomd);
        try tmp.dir.writeFile(io, .{
            .sub_path = "snapshot/packages/replay-app.rpm",
            .data = rpm,
        });
        try tmp.dir.writeFile(io, .{
            .sub_path = "snapshot/repodata/primary.xml",
            .data = primary,
        });
        try tmp.dir.writeFile(io, .{
            .sub_path = "snapshot/repodata/repomd.xml",
            .data = repomd,
        });

        return .{
            .tmp = tmp,
            .arena = arena,
            .base = base,
            .snapshot = snapshot,
            .repositories = .{.{
                .id = "replay-cli",
                .metadata = .{ .local_snapshot = snapshot },
            }},
        };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.tmp.cleanup();
        self.* = undefined;
    }

    fn createDir(self: *Fixture, name: []const u8) ![]const u8 {
        try self.tmp.dir.createDirPath(io, name);
        return std.fmt.allocPrint(
            self.arena.allocator(),
            "{s}/{s}",
            .{ self.base, name },
        );
    }

    fn exportBundle(self: *Fixture, name: []const u8) ![]const u8 {
        const root_name = try std.fmt.allocPrint(
            self.arena.allocator(),
            "plan-root-{s}",
            .{name},
        );
        const work_name = try std.fmt.allocPrint(
            self.arena.allocator(),
            "work/{s}",
            .{name},
        );
        const root = try self.createDir(root_name);
        const work = try self.createDir(work_name);
        const destination = try std.fmt.allocPrint(
            self.arena.allocator(),
            "{s}/bundle-{s}",
            .{ self.base, name },
        );
        var exported = try bundle_export.exportBundle(allocator, io, .{
            .resolve = .{
                .operation = .install,
                .subjects = &.{"replay-app"},
                .repositories = self.repositories[0..],
                .installed = .{ .install_root = root },
                .environment = .{
                    .architecture = "x86_64",
                    .distro = "replay-cli-test",
                    .release_version = "1",
                },
                .cache_dir = "/cache",
                .scratch_dir = work,
            },
            .destination = destination,
            .gpg_check = false,
        });
        defer exported.deinit();
        switch (exported) {
            .exported => |value| {
                try std.testing.expect(value.plan.isReplayable());
            },
            .problems => return error.UnresolvedPlan,
        }
        return destination;
    }
};

fn rpmzPath() ![]u8 {
    const prefix = std.testing.environ.getAlloc(
        allocator,
        "RPMZ_CLI_TEST_PREFIX",
    ) catch try allocator.dupe(u8, "out");
    defer allocator.free(prefix);
    return std.fs.path.join(allocator, &.{ prefix, "bin", "rpmz" });
}

fn runCli(binary: []const u8, args: []const []const u8) !std.process.RunResult {
    const argv = try allocator.alloc([]const u8, args.len + 1);
    defer allocator.free(argv);
    argv[0] = binary;
    @memcpy(argv[1..], args);
    return std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
}

fn runLegacyCli(binary: []const u8, args: []const []const u8) !std.process.RunResult {
    const argv = try allocator.alloc([]const u8, args.len + 2);
    defer allocator.free(argv);
    argv[0] = binary;
    argv[1] = compatibility_command;
    @memcpy(argv[2..], args);
    return std.process.run(allocator, io, .{
        .argv = argv,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    });
}

const ClosedStderrResult = struct {
    term: std.process.Child.Term,
    stdout: []u8,
};

fn runCliClosedStderr(
    binary: []const u8,
    args: []const []const u8,
) !ClosedStderrResult {
    const argv = try allocator.alloc([]const u8, args.len + 1);
    defer allocator.free(argv);
    argv[0] = binary;
    @memcpy(argv[1..], args);

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .close,
    });
    errdefer child.kill(io);
    var stdout_reader = child.stdout.?.readerStreaming(io, &.{});
    const stdout = try stdout_reader.interface.allocRemaining(
        allocator,
        .limited(1024 * 1024),
    );
    errdefer allocator.free(stdout);
    return .{
        .term = try child.wait(io),
        .stdout = stdout,
    };
}

fn installHostRuntime(
    fixture: *Fixture,
    root_name: []const u8,
    executable: []const u8,
) !void {
    const copyFile = struct {
        fn call(
            target: *Fixture,
            target_root: []const u8,
            source: []const u8,
        ) !void {
            const destination = try std.fmt.allocPrint(
                allocator,
                "{s}{s}",
                .{ target_root, source },
            );
            defer allocator.free(destination);
            try std.Io.Dir.copyFile(
                .cwd(),
                source,
                target.tmp.dir,
                destination,
                io,
                .{ .make_path = true },
            );
        }
    }.call;
    try copyFile(fixture, root_name, executable);
    try copyFile(fixture, root_name, executable);

    const dependencies = try runCli("ldd", &.{executable});
    defer allocator.free(dependencies.stdout);
    defer allocator.free(dependencies.stderr);
    if (exitCode(dependencies) != 0) {
        const source = try std.Io.Dir.cwd().readFileAlloc(
            io,
            executable,
            allocator,
            .limited(4096),
        );
        defer allocator.free(source);
        if (!std.mem.startsWith(u8, source, "#!"))
            return error.RuntimeInspectionFailed;
        const line_end = std.mem.indexOfScalar(u8, source, '\n') orelse
            source.len;
        var fields = std.mem.tokenizeScalar(u8, source[2..line_end], ' ');
        const interpreter = fields.next() orelse
            return error.RuntimeInspectionFailed;
        if (!std.mem.startsWith(u8, interpreter, "/"))
            return error.RuntimeInspectionFailed;
        return installHostRuntime(fixture, root_name, interpreter);
    }

    var tokens = std.mem.tokenizeAny(u8, dependencies.stdout, " \t\r\n");
    while (tokens.next()) |token| {
        if (!std.mem.startsWith(u8, token, "/")) continue;
        try copyFile(fixture, root_name, token);
    }
}

fn exitCode(result: std.process.RunResult) u8 {
    return switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
}

fn parseResult(
    bytes: []const u8,
    expected_status: []const u8,
) !std.json.Parsed(std.json.Value) {
    try std.testing.expect(bytes.len != 0);
    try std.testing.expect(!std.mem.endsWith(u8, bytes, "\n"));
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        bytes,
        .{},
    );
    errdefer parsed.deinit();
    try std.testing.expectEqualStrings(
        replay.result_schema,
        parsed.value.object.get("schema").?.string,
    );
    try std.testing.expectEqualStrings(
        expected_status,
        parsed.value.object.get("status").?.string,
    );
    return parsed;
}

fn expectLegacyOptionJson(
    binary: []const u8,
    args: []const []const u8,
    expected_code: u8,
    expected_error: i64,
    expected_message: []const u8,
    expected_stderr: ?[]const u8,
) !void {
    const result = try runLegacyCli(binary, args);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqual(expected_code, exitCode(result));
    try std.testing.expect(result.stdout.len != 0);
    try std.testing.expect(!std.mem.endsWith(u8, result.stdout, "\n"));

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        result.stdout,
        .{},
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.count());
    try std.testing.expectEqual(
        expected_error,
        parsed.value.object.get("Error").?.integer,
    );
    try std.testing.expectEqualStrings(
        expected_message,
        parsed.value.object.get("ErrorMessage").?.string,
    );
    if (expected_stderr) |message| {
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, message) != null);
    } else {
        try std.testing.expectEqual(@as(usize, 0), result.stderr.len);
    }
}

test "legacy parser JSON failures keep diagnostics off stdout" {
    const binary = try rpmzPath();
    defer allocator.free(binary);

    const cases = [_]struct {
        args: []const []const u8,
        exit_code: u8,
        error_code: i64,
        message: []const u8,
        stderr_diagnostic: ?[]const u8,
    }{
        .{
            .args = &.{ "--json", "--unknown" },
            .exit_code = 140,
            .error_code = 908,
            .message = "Command line error: option is invalid.",
            .stderr_diagnostic = "No such option: --unknown",
        },
        .{
            .args = &.{ "--json", "--installroot", "relative", "list" },
            .exit_code = 86,
            .error_code = 1622,
            .message = "Invalid argument",
            .stderr_diagnostic = "Install root must be an absolute path.",
        },
        .{
            .args = &.{ "--json", "--config" },
            .exit_code = 141,
            .error_code = 909,
            .message = "Command line error: expected one argument.",
            .stderr_diagnostic = "Option --config requires an argument",
        },
        .{
            .args = &.{"--json=invalid"},
            .exit_code = 140,
            .error_code = 908,
            .message = "Command line error: option is invalid.",
            .stderr_diagnostic = "No such option: --json=invalid",
        },
        .{
            .args = &.{ "--json", "--setopt", "invalid", "list" },
            .exit_code = 143,
            .error_code = 911,
            .message = "Missing equal sign in setopt argument. setopt requires an argument of the form key=value.",
            .stderr_diagnostic = null,
        },
        .{
            .args = &.{ "--json", "--setopt", "bad/repo.option=1", "list" },
            .exit_code = 14,
            .error_code = 1038,
            .message = "repo name is invalid",
            .stderr_diagnostic = null,
        },
        .{
            .args = &.{ "--json", "--rpmdb-path", "/var/lib/rpm", "list" },
            .exit_code = 140,
            .error_code = 908,
            .message = "Command line error: option is invalid.",
            .stderr_diagnostic = "--rpmdb-path is only valid with the replay command",
        },
    };

    for (cases) |case| {
        try expectLegacyOptionJson(
            binary,
            case.args,
            case.exit_code,
            case.error_code,
            case.message,
            case.stderr_diagnostic,
        );
    }
}

test "legacy parser diagnostics retain non-JSON channels" {
    const binary = try rpmzPath();
    defer allocator.free(binary);

    const cases = [_]struct {
        args: []const []const u8,
        stdout_diagnostic: []const u8,
    }{
        .{
            .args = &.{"--unknown"},
            .stdout_diagnostic = "No such option: --unknown",
        },
        .{
            .args = &.{ "--installroot", "relative", "list" },
            .stdout_diagnostic = "Install root must be an absolute path.",
        },
    };

    for (cases) |case| {
        const result = try runLegacyCli(binary, case.args);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try std.testing.expect(std.mem.indexOf(
            u8,
            result.stdout,
            case.stdout_diagnostic,
        ) != null);
    }
}

fn apiCanonical(
    bundle: []const u8,
    root: []const u8,
    architecture: []const u8,
) ![]u8 {
    const result = try replay.run(allocator, io, .{
        .bundle_directory = bundle,
        .target = .{
            .install_root = root,
            .rpmdb_path = "/var/lib/rpm",
            .architecture = architecture,
        },
    });
    defer result.deinit();
    return result.canonicalJsonAlloc(allocator);
}

const ProbeContext = struct {
    server: *std.Io.net.Server,
    done: std.atomic.Value(bool) = .init(false),
    attempts: std.atomic.Value(usize) = .init(0),

    fn monitor(self: *ProbeContext) void {
        while (true) {
            var descriptors = [_]std.posix.pollfd{.{
                .fd = self.server.socket.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            }};
            const ready = std.posix.poll(&descriptors, 25) catch return;
            if (ready != 0) {
                const stream = self.server.accept(io) catch continue;
                _ = self.attempts.fetchAdd(1, .monotonic);
                stream.close(io);
                continue;
            }
            if (self.done.load(.acquire)) return;
        }
    }
};

const NetworkProbe = struct {
    context: *ProbeContext,
    thread: std.Thread,
    port: u16,

    fn start() !NetworkProbe {
        const address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
        const server = try allocator.create(std.Io.net.Server);
        errdefer allocator.destroy(server);
        server.* = try address.listen(io, .{ .reuse_address = true });
        errdefer server.deinit(io);
        const context = try allocator.create(ProbeContext);
        errdefer allocator.destroy(context);
        context.* = .{ .server = server };
        const thread = try std.Thread.spawn(.{}, ProbeContext.monitor, .{context});
        return .{
            .context = context,
            .thread = thread,
            .port = server.socket.address.getPort(),
        };
    }

    fn stop(self: *NetworkProbe) usize {
        self.context.done.store(true, .release);
        self.thread.join();
        const attempts = self.context.attempts.load(.acquire);
        self.context.server.deinit(io);
        allocator.destroy(self.context.server);
        allocator.destroy(self.context);
        self.* = undefined;
        return attempts;
    }
};

fn configureNetworkRepository(
    fixture: *Fixture,
    root_name: []const u8,
    port: u16,
) !void {
    const config_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/etc/rpmz",
        .{root_name},
    );
    defer allocator.free(config_dir);
    const repo_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/etc/yum.repos.d",
        .{root_name},
    );
    defer allocator.free(repo_dir);
    try fixture.tmp.dir.createDirPath(io, config_dir);
    try fixture.tmp.dir.createDirPath(io, repo_dir);
    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/rpmz.conf",
        .{config_dir},
    );
    defer allocator.free(config_path);
    try fixture.tmp.dir.writeFile(io, .{
        .sub_path = config_path,
        .data =
        \\[main]
        \\gpgcheck=0
        \\plugins=0
        \\repodir=/etc/yum.repos.d
        \\cachedir=/var/cache/rpmz
        \\persistdir=/var/lib/rpmz
        \\
        ,
    });
    const repo_path = try std.fmt.allocPrint(
        allocator,
        "{s}/network.repo",
        .{repo_dir},
    );
    defer allocator.free(repo_path);
    const repo_data = try std.fmt.allocPrint(allocator,
        \\[network]
        \\name=network
        \\baseurl=http://127.0.0.1:{d}/repo
        \\enabled=1
        \\gpgcheck=0
        \\
    , .{port});
    defer allocator.free(repo_data);
    try fixture.tmp.dir.writeFile(io, .{
        .sub_path = repo_path,
        .data = repo_data,
    });
}

fn configureRepositoryTrap(
    fixture: *Fixture,
    root_name: []const u8,
) !void {
    const config_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/etc/rpmz",
        .{root_name},
    );
    defer allocator.free(config_dir);
    try fixture.tmp.dir.createDirPath(io, config_dir);
    const config_path = try std.fmt.allocPrint(
        allocator,
        "{s}/rpmz.conf",
        .{config_dir},
    );
    defer allocator.free(config_path);
    try fixture.tmp.dir.writeFile(io, .{
        .sub_path = config_path,
        .data =
        \\[main]
        \\gpgcheck=0
        \\plugins=0
        \\repodir=/repo-trap
        \\cachedir=/var/cache/rpmz
        \\persistdir=/var/lib/rpmz
        \\
        ,
    });
    const trap_path = try std.fmt.allocPrint(
        allocator,
        "{s}/repo-trap",
        .{root_name},
    );
    defer allocator.free(trap_path);
    try fixture.tmp.dir.writeFile(io, .{
        .sub_path = trap_path,
        .data = "repository initialization must not open this as a directory",
    });
}

fn expectUsage(binary: []const u8, args: []const []const u8) !void {
    const result = try runCli(binary, args);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqual(@as(u8, 2), exitCode(result));
    try std.testing.expectEqual(@as(usize, 0), result.stdout.len);
    try std.testing.expect(std.mem.indexOf(
        u8,
        result.stderr,
        "Usage: rpmz replay",
    ) != null);
}

const ValueOptionStyle = enum {
    double_separate,
    double_equals,
    single_separate,
    single_equals,
    short_separate,
    short_attached,
};

fn appendValueOption(
    args: *std.array_list.Managed([]const u8),
    owned: *std.array_list.Managed([]u8),
    option: replay_options.ValueOption,
    value: []const u8,
    style: ValueOptionStyle,
) !void {
    switch (style) {
        .double_separate, .single_separate, .short_separate => {
            const spelling = switch (style) {
                .double_separate => try std.fmt.allocPrint(
                    allocator,
                    "--{s}",
                    .{option.name},
                ),
                .single_separate => try std.fmt.allocPrint(
                    allocator,
                    "-{s}",
                    .{option.name},
                ),
                .short_separate => try allocator.dupe(
                    u8,
                    option.short orelse return error.MissingShortOption,
                ),
                else => unreachable,
            };
            owned.append(spelling) catch |err| {
                allocator.free(spelling);
                return err;
            };
            try args.append(spelling);
            try args.append(value);
        },
        .double_equals, .single_equals, .short_attached => {
            const spelling = switch (style) {
                .double_equals => try std.fmt.allocPrint(
                    allocator,
                    "--{s}={s}",
                    .{ option.name, value },
                ),
                .single_equals => try std.fmt.allocPrint(
                    allocator,
                    "-{s}={s}",
                    .{ option.name, value },
                ),
                .short_attached => try std.fmt.allocPrint(
                    allocator,
                    "{s}{s}",
                    .{
                        option.short orelse return error.MissingShortOption,
                        value,
                    },
                ),
                else => unreachable,
            };
            owned.append(spelling) catch |err| {
                allocator.free(spelling);
                return err;
            };
            try args.append(spelling);
        },
    }
}

fn freeGeneratedArgs(args: []const []u8) void {
    for (args) |arg| allocator.free(arg);
}

fn expectValueOptionAccepted(
    binary: []const u8,
    selected: replay_options.ValueOption,
    value: []const u8,
    style: ValueOptionStyle,
) !void {
    var args = std.array_list.Managed([]const u8).init(allocator);
    defer args.deinit();
    var owned = std.array_list.Managed([]u8).init(allocator);
    defer {
        freeGeneratedArgs(owned.items);
        owned.deinit();
    }
    try args.append("replay");
    try appendValueOption(&args, &owned, selected, value, style);

    for (replay_options.value_options) |option| {
        if (std.mem.eql(u8, option.name, selected.name)) continue;
        try appendValueOption(
            &args,
            &owned,
            option,
            if (std.mem.eql(
                u8,
                option.name,
                replay_options.install_root.name,
            ))
                "/"
            else if (std.mem.eql(
                u8,
                option.name,
                replay_options.rpmdb_path.name,
            ))
                "/var/lib/rpm"
            else
                "x86_64",
            .double_separate,
        );
    }
    try args.append("/replay-option-spelling-does-not-exist");

    const result = try runCli(binary, args.items);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqual(@as(u8, 3), exitCode(result));
    try std.testing.expect(std.mem.indexOf(
        u8,
        result.stderr,
        "Usage: rpmz replay",
    ) == null);
}

fn expectJsonUsage(
    binary: []const u8,
    args: []const []const u8,
    expected_error: []const u8,
) !void {
    return expectJsonUsageArgv0(binary, binary, args, expected_error);
}

fn expectJsonUsageArgv0(
    binary: []const u8,
    argv0: []const u8,
    args: []const []const u8,
    expected_error: []const u8,
) !void {
    const result = if (std.mem.eql(u8, binary, argv0))
        try runCli(binary, args)
    else result: {
        const binary_absolute = try std.Io.Dir.cwd().realPathFileAlloc(
            io,
            binary,
            allocator,
        );
        defer allocator.free(binary_absolute);
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        try tmp.dir.symLink(io, binary_absolute, argv0, .{});
        var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const path_length = try tmp.dir.realPath(io, &path_buffer);
        const alias_binary = try std.fs.path.join(
            allocator,
            &.{ path_buffer[0..path_length], argv0 },
        );
        defer allocator.free(alias_binary);
        break :result try runCli(alias_binary, args);
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqual(@as(u8, 2), exitCode(result));
    try std.testing.expect(result.stdout.len != 0);
    try std.testing.expect(!std.mem.endsWith(u8, result.stdout, "\n"));
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        result.stdout,
        .{},
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 3), parsed.value.object.count());
    try std.testing.expectEqualStrings(
        "tdnf.replay-invocation-error/v1",
        parsed.value.object.get("schema").?.string,
    );
    try std.testing.expectEqualStrings(
        expected_error,
        parsed.value.object.get("error").?.string,
    );
    try std.testing.expect(
        parsed.value.object.get("message").?.string.len != 0,
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        result.stderr,
        "Usage: rpmz replay",
    ) != null);
}

test "replay CLI accepts every documented option spelling" {
    const binary = try rpmzPath();
    defer allocator.free(binary);
    const ordinary_styles = [_]ValueOptionStyle{
        .double_separate,
        .double_equals,
        .single_separate,
        .single_equals,
    };
    for (replay_options.value_options) |option| {
        const value = if (std.mem.eql(
            u8,
            option.name,
            replay_options.install_root.name,
        ))
            "/"
        else if (std.mem.eql(
            u8,
            option.name,
            replay_options.rpmdb_path.name,
        ))
            "/var/lib/rpm"
        else
            "x86_64";
        for (ordinary_styles) |style|
            try expectValueOptionAccepted(binary, option, value, style);
        if (option.short != null) {
            try expectValueOptionAccepted(
                binary,
                option,
                value,
                .short_separate,
            );
            try expectValueOptionAccepted(
                binary,
                option,
                value,
                .short_attached,
            );
        }
    }

    var prefix_length: usize = 1;
    while (prefix_length <= replay_options.json_name.len) : (prefix_length += 1) {
        const prefix = replay_options.json_name[0..prefix_length];
        for ([_][]const u8{ "-", "--" }) |dash| {
            const spelling = try std.fmt.allocPrint(
                allocator,
                "{s}{s}",
                .{ dash, prefix },
            );
            defer allocator.free(spelling);
            try expectJsonUsage(
                binary,
                &.{ spelling, "replay" },
                "missing_bundle",
            );
        }
    }

    for ([_][]const u8{
        replay_options.help_long,
        replay_options.help_short,
    }) |spelling| {
        const help = try runCli(binary, &.{ "replay", spelling });
        defer allocator.free(help.stdout);
        defer allocator.free(help.stderr);
        try std.testing.expectEqual(@as(u8, 0), exitCode(help));
        try std.testing.expectEqual(@as(usize, 0), help.stdout.len);
        try std.testing.expect(std.mem.indexOf(
            u8,
            help.stderr,
            "Usage: rpmz replay",
        ) != null);
    }
}

test "replay-only options preserve legacy JSON and diagnostic channels" {
    const binary = try rpmzPath();
    defer allocator.free(binary);

    try expectLegacyOptionJson(binary, &.{
        "--json",
        "--rpmdb-path",
        "/var/lib/rpm",
        "list",
    }, 140, 908, "Command line error: option is invalid.", "--rpmdb-path is only valid");
    try expectLegacyOptionJson(binary, &.{
        "--json",
        "--rpmdb-path",
        "/var/lib/rpm",
        "unknown-command",
    }, 140, 908, "Command line error: option is invalid.", "--rpmdb-path is only valid");
    try expectLegacyOptionJson(binary, &.{
        "--json",
        "--rpmdb-path",
        "/var/lib/rpm",
    }, 140, 908, "Command line error: option is invalid.", "--rpmdb-path is only valid");
    try expectLegacyOptionJson(binary, &.{
        "--json",
        "--rpmdb-path",
        "/var/lib/rpm",
        "list",
        "extra",
    }, 140, 908, "Command line error: option is invalid.", "--rpmdb-path is only valid");

    const malformed = [_][]const []const u8{
        &.{ "--json", "--rpmdb-path" },
        &.{ "list", "--json", "--rpmdb-path" },
        &.{ "--json", "--config" },
        &.{ "list", "--json", "--config" },
    };
    for (malformed) |args| {
        try expectLegacyOptionJson(
            binary,
            args,
            141,
            909,
            "Command line error: expected one argument.",
            "requires an argument",
        );
    }

    const empty = [_][]const []const u8{
        &.{ "--json", "--rpmdb-path=", "list" },
        &.{ "list", "--json", "--rpmdb-path=" },
        &.{ "--json", "--config=", "list" },
        &.{ "list", "--json", "--config=" },
    };
    for (empty) |args| {
        try expectLegacyOptionJson(
            binary,
            args,
            141,
            909,
            "Command line error: expected one argument.",
            null,
        );
    }

    const json_operands = [_][]const []const u8{
        &.{ "--rpmdb-path", "--json", "list" },
        &.{ "list", "--rpmdb-path", "--json" },
    };
    for (json_operands) |args| {
        const non_json = try runLegacyCli(binary, args);
        defer allocator.free(non_json.stdout);
        defer allocator.free(non_json.stderr);
        try std.testing.expectEqual(@as(u8, 140), exitCode(non_json));
        try std.testing.expectEqual(@as(usize, 0), non_json.stdout.len);
        try std.testing.expect(std.mem.indexOf(
            u8,
            non_json.stderr,
            "--rpmdb-path is only valid with the replay command",
        ) != null);
        try std.testing.expect(std.mem.indexOf(
            u8,
            non_json.stderr,
            "Error(908) : Command line error: option is invalid.",
        ) != null);
    }
}

test "replay CLI success is canonical offline and bypasses normal initialization" {
    var fixture = try Fixture.create(null);
    defer fixture.deinit();
    const bundle = try fixture.exportBundle("success");
    const api_root = try fixture.createDir("api-root");
    const network_root = try fixture.createDir("network-root");
    const parity_root = try fixture.createDir("parity-root");
    const json_root = try fixture.createDir("json-root");
    const alias_root = try fixture.createDir("alias-root");
    const trap_root = try fixture.createDir("trap-root");

    const expected = try apiCanonical(bundle, api_root, "x86_64");
    defer allocator.free(expected);
    var expected_parsed = try parseResult(expected, "succeeded");
    defer expected_parsed.deinit();

    var probe = try NetworkProbe.start();
    var probe_stopped = false;
    defer {
        if (!probe_stopped) _ = probe.stop();
    }
    try configureNetworkRepository(&fixture, "network-root", probe.port);
    const binary = try rpmzPath();
    defer allocator.free(binary);
    const network_result = try runCli(binary, &.{
        "replay",
        "--installroot",
        network_root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    const network_attempts = probe.stop();
    probe_stopped = true;
    defer allocator.free(network_result.stdout);
    defer allocator.free(network_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(network_result));
    try std.testing.expectEqualStrings(expected, network_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), network_attempts);

    const options_first = try runCli(binary, &.{
        "--installroot",
        parity_root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        "replay",
        bundle,
    });
    defer allocator.free(options_first.stdout);
    defer allocator.free(options_first.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(options_first));
    try std.testing.expectEqualStrings(network_result.stdout, options_first.stdout);

    const json_result = try runCli(binary, &.{
        "--json",
        "replay",
        "--installroot",
        json_root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    defer allocator.free(json_result.stdout);
    defer allocator.free(json_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(json_result));
    try std.testing.expectEqualStrings(network_result.stdout, json_result.stdout);

    const binary_absolute = try std.Io.Dir.cwd().realPathFileAlloc(
        io,
        binary,
        allocator,
    );
    defer allocator.free(binary_absolute);
    try fixture.tmp.dir.symLink(io, binary_absolute, "rpmzj", .{});
    const alias_binary = try std.fs.path.join(
        allocator,
        &.{ fixture.base, "rpmzj" },
    );
    defer allocator.free(alias_binary);
    const alias_result = try runCli(alias_binary, &.{
        "replay",
        "--installroot",
        alias_root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    defer allocator.free(alias_result.stdout);
    defer allocator.free(alias_result.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(alias_result));
    try std.testing.expectEqualStrings(network_result.stdout, alias_result.stdout);

    try configureRepositoryTrap(&fixture, "trap-root");
    const ordinary = try runCli(binary, &.{
        "--installroot",
        trap_root,
        "--forcearch",
        "x86_64",
        "repolist",
    });
    defer allocator.free(ordinary.stdout);
    defer allocator.free(ordinary.stderr);
    try std.testing.expect(exitCode(ordinary) != 0);

    const trapped_replay = try runCli(binary, &.{
        "--installroot",
        trap_root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        "replay",
        bundle,
    });
    defer allocator.free(trapped_replay.stdout);
    defer allocator.free(trapped_replay.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(trapped_replay));
    try std.testing.expectEqualStrings(expected, trapped_replay.stdout);
}

test "replay CLI preserves validation and transaction failure contracts" {
    var valid_fixture = try Fixture.create(null);
    defer valid_fixture.deinit();
    const valid_bundle = try valid_fixture.exportBundle("validation");
    const api_validation_root = try valid_fixture.createDir("api-validation-root");
    const cli_validation_root = try valid_fixture.createDir("cli-validation-root");
    try valid_fixture.tmp.dir.writeFile(io, .{
        .sub_path = "api-validation-root/marker",
        .data = "unchanged",
    });
    try valid_fixture.tmp.dir.writeFile(io, .{
        .sub_path = "cli-validation-root/marker",
        .data = "unchanged",
    });

    const expected_validation = try apiCanonical(
        valid_bundle,
        api_validation_root,
        "aarch64",
    );
    defer allocator.free(expected_validation);
    var validation_parsed = try parseResult(
        expected_validation,
        "validation_failed",
    );
    defer validation_parsed.deinit();

    const binary = try rpmzPath();
    defer allocator.free(binary);
    const validation = try runCli(binary, &.{
        "replay",
        "--installroot",
        cli_validation_root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "aarch64",
        valid_bundle,
    });
    defer allocator.free(validation.stdout);
    defer allocator.free(validation.stderr);
    try std.testing.expectEqual(@as(u8, 3), exitCode(validation));
    try std.testing.expectEqualStrings(expected_validation, validation.stdout);
    const marker = try valid_fixture.tmp.dir.readFileAlloc(
        io,
        "cli-validation-root/marker",
        allocator,
        .limited(32),
    );
    defer allocator.free(marker);
    try std.testing.expectEqualStrings("unchanged", marker);
    try std.testing.expectError(
        error.FileNotFound,
        valid_fixture.tmp.dir.access(
            io,
            "cli-validation-root/var/lib/rpm/rpmdb.sqlite",
            .{},
        ),
    );

    var failing_fixture = try Fixture.create("exit 9\n");
    defer failing_fixture.deinit();
    const failing_bundle = try failing_fixture.exportBundle("transaction");
    const cli_failure_root = try failing_fixture.createDir("cli-failure-root");

    const failure = try runCli(binary, &.{
        "replay",
        "--installroot",
        cli_failure_root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        failing_bundle,
    });
    defer allocator.free(failure.stdout);
    defer allocator.free(failure.stderr);
    try std.testing.expectEqual(@as(u8, 4), exitCode(failure));
    var cli_failure_parsed = try parseResult(
        failure.stdout,
        "transaction_failed",
    );
    defer cli_failure_parsed.deinit();
    try std.testing.expect(
        cli_failure_parsed.value.object.get("validation_failure").? == .null,
    );
    try std.testing.expect(
        cli_failure_parsed.value.object.get("transaction_failure").? != .null,
    );
}

test "replay CLI rejects missing ambiguous extra and unsafe inputs" {
    var fixture = try Fixture.create(null);
    defer fixture.deinit();
    const bundle = try fixture.exportBundle("arguments");
    const root = try fixture.createDir("argument-root");
    const binary = try rpmzPath();
    defer allocator.free(binary);

    const ordinary_version = try runCli(
        binary,
        &.{ "--version", "install", "replay" },
    );
    defer allocator.free(ordinary_version.stdout);
    defer allocator.free(ordinary_version.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(ordinary_version));
    try std.testing.expect(std.mem.indexOf(
        u8,
        ordinary_version.stderr,
        "Usage: rpmz replay",
    ) == null);

    const config_value_replay = try runLegacyCli(
        binary,
        &.{ "--config", "replay", "--version" },
    );
    defer allocator.free(config_value_replay.stdout);
    defer allocator.free(config_value_replay.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(config_value_replay));
    try std.testing.expect(std.mem.indexOf(
        u8,
        config_value_replay.stderr,
        "Usage: rpmz replay",
    ) == null);

    const inline_config_value_replay = try runLegacyCli(
        binary,
        &.{ "--config=replay", "--version" },
    );
    defer allocator.free(inline_config_value_replay.stdout);
    defer allocator.free(inline_config_value_replay.stderr);
    try std.testing.expectEqual(
        @as(u8, 0),
        exitCode(inline_config_value_replay),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        inline_config_value_replay.stderr,
        "Usage: rpmz replay",
    ) == null);

    const short_config_value_replay = try runLegacyCli(
        binary,
        &.{ "-c", "replay", "--version" },
    );
    defer allocator.free(short_config_value_replay.stdout);
    defer allocator.free(short_config_value_replay.stderr);
    try std.testing.expectEqual(
        @as(u8, 0),
        exitCode(short_config_value_replay),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        short_config_value_replay.stderr,
        "Usage: rpmz replay",
    ) == null);

    const attached_short_config_value_replay = try runLegacyCli(
        binary,
        &.{ "-creplay", "--version" },
    );
    defer allocator.free(attached_short_config_value_replay.stdout);
    defer allocator.free(attached_short_config_value_replay.stderr);
    try std.testing.expectEqual(
        @as(u8, 0),
        exitCode(attached_short_config_value_replay),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        attached_short_config_value_replay.stderr,
        "Usage: rpmz replay",
    ) == null);

    try expectUsage(binary, &.{"replay"});
    try expectUsage(binary, &.{ "--config", "", "replay" });
    try expectUsage(binary, &.{ "--config=", "replay" });
    try expectUsage(binary, &.{ "-c", "", "replay" });
    try expectUsage(binary, &.{ "-q", "replay" });
    try expectUsage(binary, &.{ "--", "replay" });
    try expectUsage(binary, &.{ "--config", "--", "replay" });
    try expectUsage(binary, &.{ "replay", "--installroot" });
    try expectUsage(binary, &.{
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
    });
    try expectUsage(binary, &.{
        "replay",
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    try expectUsage(binary, &.{
        "replay",
        "--installroot",
        root,
        "--forcearch",
        "x86_64",
        bundle,
    });
    try expectUsage(binary, &.{
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        bundle,
    });
    try expectUsage(binary, &.{
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
        "extra",
    });
    try expectUsage(binary, &.{
        "replay",
        "--installroot",
        root,
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    try expectUsage(binary, &.{
        "replay",
        "--config",
        "/does/not/apply",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    try expectUsage(binary, &.{
        "--config",
        "/does/not/apply",
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    try expectUsage(binary, &.{
        "--unknown-replay-option",
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    const option_like_installroot_value = try runCli(binary, &.{
        "--installroot",
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        "replay",
        bundle,
    });
    defer allocator.free(option_like_installroot_value.stdout);
    defer allocator.free(option_like_installroot_value.stderr);
    try std.testing.expect(exitCode(option_like_installroot_value) != 2);
    try std.testing.expect(std.mem.indexOf(
        u8,
        option_like_installroot_value.stderr,
        "Usage: rpmz replay",
    ) == null);
    try expectUsage(binary, &.{
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        "",
    });
    try expectUsage(binary, &.{
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        "replay",
        "",
    });
    try expectJsonUsage(binary, &.{
        "--json",
        "replay",
    }, "missing_bundle");
    try expectJsonUsage(binary, &.{
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        "--json",
        "replay",
    }, "missing_bundle");
    try expectJsonUsage(binary, &.{
        "--json",
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
    }, "missing_bundle");
    try expectJsonUsage(binary, &.{
        "replay",
        "--json",
        bundle,
    }, "missing_install_root");
    try expectUsage(binary, &.{
        "replay",
        "--downloaddir",
        root,
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });

    try expectJsonUsageArgv0(
        binary,
        "rpmzj",
        &.{"replay"},
        "missing_bundle",
    );

    const unsafe = try runCli(binary, &.{
        "replay",
        "--installroot",
        "relative-root",
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    defer allocator.free(unsafe.stdout);
    defer allocator.free(unsafe.stderr);
    try std.testing.expectEqual(@as(u8, 3), exitCode(unsafe));
    var unsafe_parsed = try parseResult(unsafe.stdout, "validation_failed");
    defer unsafe_parsed.deinit();
    try std.testing.expectEqualStrings(
        "invalid_input",
        unsafe_parsed.value.object.get("validation_failure").?.string,
    );

    const help = try runCli(binary, &.{ "replay", "--help" });
    defer allocator.free(help.stdout);
    defer allocator.free(help.stderr);
    try std.testing.expectEqual(@as(u8, 0), exitCode(help));
    try std.testing.expectEqual(@as(usize, 0), help.stdout.len);
    try std.testing.expect(std.mem.indexOf(
        u8,
        help.stderr,
        "Usage: rpmz replay",
    ) != null);
}

test "replay CLI fails without stderr before reserving canonical stdout" {
    var fixture = try Fixture.create(null);
    defer fixture.deinit();
    const bundle = try fixture.exportBundle("closed-stderr");
    const root = try fixture.createDir("closed-stderr-root");
    const binary = try rpmzPath();
    defer allocator.free(binary);

    const result = try runCliClosedStderr(binary, &.{
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    defer allocator.free(result.stdout);

    try std.testing.expectEqual(
        std.process.Child.Term{ .exited = 1 },
        result.term,
    );
    try std.testing.expectEqual(@as(usize, 0), result.stdout.len);
}

test "replay CLI isolates canonical stdout from scriptlet descendants" {
    var fixture = try Fixture.createWithInterpreter(
        \\print("scriptlet stdout")
        \\local ok, status, code =
        \\  os.execute("/bin/sleep 2 >/dev/null 2>&1 &")
        \\assert(ok == true and status == "exit" and code == 0)
        \\
    ,
        "<lua>",
    );
    defer fixture.deinit();
    const bundle = try fixture.exportBundle("scriptlet-output");
    const root = try fixture.createDir("scriptlet-root");
    try installHostRuntime(&fixture, "scriptlet-root", "/bin/sh");
    try installHostRuntime(&fixture, "scriptlet-root", "/bin/sleep");
    try fixture.tmp.dir.createDirPath(io, "scriptlet-root/dev");
    try fixture.tmp.dir.writeFile(io, .{
        .sub_path = "scriptlet-root/dev/null",
        .data = "",
        .flags = .{
            .permissions = .fromMode(0o666),
        },
    });

    const binary = try rpmzPath();
    defer allocator.free(binary);
    const started = std.Io.Clock.awake.now(io);
    const result = try runCli(binary, &.{
        "replay",
        "--installroot",
        root,
        "--rpmdb-path",
        "/var/lib/rpm",
        "--forcearch",
        "x86_64",
        bundle,
    });
    const elapsed_ms = started.durationTo(
        std.Io.Clock.awake.now(io),
    ).toMilliseconds();
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), exitCode(result));
    var parsed = try parseResult(result.stdout, "succeeded");
    defer parsed.deinit();
    try std.testing.expect(std.mem.indexOf(
        u8,
        result.stderr,
        "scriptlet stdout",
    ) != null);
    try std.testing.expect(elapsed_ms < 1500);
}
