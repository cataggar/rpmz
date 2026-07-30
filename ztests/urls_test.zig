//! `--urls` install planning behaviour, ported from
//! `pytests/tests/test_urls.py`.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

const single = "tdnf-test-one";
const leaf = "tdnf-test-cleanreq-leaf1";
const required = "tdnf-test-cleanreq-required";

/// `ERROR_TDNF_CLI_ALLDEPS_REQUIRES_DOWNLOADONLY`.
const alldeps_requires_urls_code: u8 = 915 % 256;
/// `ERROR_TDNF_CLI_NODEPS_REQUIRES_DOWNLOADONLY`.
const nodeps_requires_urls_code: u8 = 916 % 256;

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

fn seedOsRelease(root: *harness.Root) !void {
    // The pytest format check runs with a host /etc/os-release and warm cache;
    // seed both so stdout contains only the URL lines being validated.
    try root.tmp.dir.writeFile(io, .{
        .sub_path = "etc/os-release",
        .data = "ID=photon\nVERSION_ID=4.0\n",
    });
}

fn makecache(root: *harness.Root) !void {
    var result = try root.run(&.{"makecache"});
    defer result.deinit();
    try result.expectOk();
}

fn expectLastNonEmptyLineEndsWith(result: *const harness.Result, suffix: []const u8) !void {
    var last: []const u8 = "";
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len != 0) last = trimmed;
    }

    if (last.len != 0 and std.mem.endsWith(u8, last, suffix)) return;
    std.debug.print("last non-empty stdout line did not end with {s}\nstdout:\n{s}\n", .{
        suffix,
        result.stdout,
    });
    return error.TestUnexpectedResult;
}

fn expectEveryNonEmptyLineIsUrl(result: *const harness.Result) !void {
    var found = false;
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        found = true;
        if (std.mem.startsWith(u8, trimmed, "http://") or
            std.mem.startsWith(u8, trimmed, "https://") or
            std.mem.startsWith(u8, trimmed, "file://") or
            std.mem.startsWith(u8, trimmed, "/"))
        {
            continue;
        }
        std.debug.print("unexpected URL format: {s}\nstdout:\n{s}\n", .{ trimmed, result.stdout });
        return error.TestUnexpectedResult;
    }
    try std.testing.expect(found);
}

test "--urls prints package URLs without installing" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "install", "-y", "--urls", single });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(single);
    try expectLastNonEmptyLineEndsWith(&result, ".rpm");
    try std.testing.expect(!try root.isInstalled(single));
}

test "--urls prints one URL per non-empty line" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try seedOsRelease(&root);
    try makecache(&root);

    var result = try root.run(&.{ "install", "-y", "--urls", single });
    defer result.deinit();
    try result.expectOk();
    try expectEveryNonEmptyLineIsUrl(&result);
    try std.testing.expect(!try root.isInstalled(single));
}

test "--urls includes uninstalled requirements" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try std.testing.expect(!try root.isInstalled(required));

    var result = try root.run(&.{ "install", "-y", "--urls", leaf });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(required);
    try std.testing.expect(!try root.isInstalled(leaf));
    try std.testing.expect(!try root.isInstalled(required));
}

test "--urls --alldeps includes an already-installed requirement" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try install(&root, required);
    try std.testing.expect(try root.isInstalled(required));

    var result = try root.run(&.{ "install", "-y", "--urls", "--alldeps", leaf });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(required);
    try std.testing.expect(!try root.isInstalled(leaf));
}

test "--urls --nodeps omits requirements" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    try std.testing.expect(!try root.isInstalled(required));

    var result = try root.run(&.{ "install", "-y", "--urls", "--nodeps", leaf });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(!result.stdoutContains(required));
    try std.testing.expect(!try root.isInstalled(leaf));
}

test "--alldeps requires --urls or --downloadonly" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "install", "-y", "--alldeps", single });
    defer result.deinit();
    try result.expectCode(alldeps_requires_urls_code);
    try std.testing.expect(!try root.isInstalled(single));
}

test "--nodeps requires --urls or --downloadonly" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "install", "-y", "--nodeps", single });
    defer result.deinit();
    try result.expectCode(nodeps_requires_urls_code);
    try std.testing.expect(!try root.isInstalled(single));
}
