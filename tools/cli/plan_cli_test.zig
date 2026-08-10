//! Binary-level transaction-plan CLI test.
//!
//! The fixture is deliberately local and tiny: the test consumes only the
//! installed `tdnf` executable's stdout, then parses the versioned JSON.

const std = @import("std");

const io = std.testing.io;
const schema = "tdnf.transaction-plan/v1";

const primary_xml =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common"
    \\              xmlns:rpm="http://linux.duke.edu/metadata/rpm" packages="2">
    \\  <package type="rpm">
    \\    <name>app</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</checksum>
    \\    <size package="123"/>
    \\    <location href="packages/app.rpm"/>
    \\  </package>
    \\  <package type="rpm">
    \\    <name>broken</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="0" ver="1" rel="1"/>
    \\    <checksum type="sha256" pkgid="YES">bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb</checksum>
    \\    <size package="123"/>
    \\    <location href="packages/broken.rpm"/>
    \\    <format>
    \\      <rpm:requires><rpm:entry name="missing-capability"/></rpm:requires>
    \\    </format>
    \\  </package>
    \\</metadata>
    \\
;

fn digestHex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    for (digest, 0..) |byte, index| {
        _ = std.fmt.bufPrint(hex[index * 2 .. index * 2 + 2], "{x:0>2}", .{byte}) catch unreachable;
    }
    return hex;
}

fn realPathAlloc(allocator: std.mem.Allocator, dir: std.Io.Dir) ![]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try dir.realPath(io, &buffer);
    return allocator.dupe(u8, buffer[0..len]);
}

fn expectLowerHexDigest(value: []const u8) !void {
    try std.testing.expectEqual(@as(usize, 64), value.len);
    for (value) |byte| {
        try std.testing.expect((byte >= '0' and byte <= '9') or
            (byte >= 'a' and byte <= 'f'));
    }
}

fn expectExitedZero(result: anytype) !void {
    try std.testing.expectEqual(@as(u8, 0), switch (result.term) {
        .exited => |code| code,
        else => 255,
    });
}

fn expectPlanJson(stdout: []const u8) !std.json.Parsed(std.json.Value) {
    try std.testing.expect(!std.mem.endsWith(u8, stdout, "\n"));
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        stdout,
        .{},
    );
    const object = parsed.value.object;
    try std.testing.expectEqualStrings(schema, object.get("schema").?.string);
    const digest = object.get("digest").?.object;
    try std.testing.expectEqualStrings("sha256", digest.get("algorithm").?.string);
    try std.testing.expectEqualStrings(schema, digest.get("domain").?.string);
    try expectLowerHexDigest(digest.get("value").?.string);
    return parsed;
}

test "plan command emits parseable versioned JSON" {
    const allocator = std.testing.allocator;
    const prefix = std.testing.environ.getAlloc(
        allocator,
        "TDNF_CLI_TEST_PREFIX",
    ) catch try allocator.dupe(u8, "out");
    defer allocator.free(prefix);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try realPathAlloc(allocator, tmp.dir);
    defer allocator.free(root);

    try tmp.dir.createDirPath(io, "etc");
    try tmp.dir.createDirPath(io, "repos");
    try tmp.dir.createDirPath(io, "cache");
    try tmp.dir.createDirPath(io, "persist");
    try tmp.dir.createDirPath(io, "source/repodata");

    const primary_digest = digestHex(primary_xml);
    const repomd = try std.fmt.allocPrint(allocator,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
        \\  <revision>plan-cli-test</revision>
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
    , .{ &primary_digest, &primary_digest, primary_xml.len, primary_xml.len });
    defer allocator.free(repomd);
    try tmp.dir.writeFile(io, .{ .sub_path = "source/repodata/primary.xml", .data = primary_xml });
    try tmp.dir.writeFile(io, .{ .sub_path = "source/repodata/repomd.xml", .data = repomd });
    const repo_file = try std.fmt.allocPrint(allocator,
        \\[base]
        \\name=Base
        \\baseurl=file://{s}/source
        \\enabled=1
        \\gpgcheck=0
        \\metadata_expire=-1
        \\skip_if_unavailable=0
        \\
    , .{root});
    defer allocator.free(repo_file);
    try tmp.dir.writeFile(io, .{ .sub_path = "repos/base.repo", .data = repo_file });

    try tmp.dir.writeFile(io, .{
        .sub_path = "tdnf.conf",
        .data =
        \\[main]
        \\gpgcheck=0
        \\installonly_limit=3
        \\clean_requirements_on_remove=0
        \\repodir=/repos
        \\cachedir=/cache
        \\persistdir=/persist
        \\plugins=0
        \\
        ,
    });

    const tdnf = try std.fs.path.join(allocator, &.{ prefix, "bin", "tdnf" });
    defer allocator.free(tdnf);
    const config = try std.fs.path.join(allocator, &.{ root, "tdnf.conf" });
    defer allocator.free(config);

    var environ: std.process.Environ.Map = .init(allocator);
    defer environ.deinit();
    try environ.putPosixBlock(std.testing.environ.block.view());

    const run_result = try std.process.run(allocator, io, .{
        .argv = &.{
            tdnf,
            "-c",
            config,
            "--installroot",
            root,
            "--releasever",
            "1",
            "--forcearch",
            "x86_64",
            "plan",
            "install",
            "app",
        },
        .environ_map = &environ,
    });
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);
    try expectExitedZero(run_result);
    try std.testing.expect(std.mem.indexOf(
        u8,
        run_result.stderr,
        "Warning: '",
    ) != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        run_result.stderr,
        "Refreshing metadata for: 'Base'",
    ) != null);

    var parsed = try expectPlanJson(run_result.stdout);
    defer parsed.deinit();

    const broken_result = try std.process.run(allocator, io, .{
        .argv = &.{
            tdnf,
            "-c",
            config,
            "--installroot",
            root,
            "--releasever",
            "1",
            "--forcearch",
            "x86_64",
            "plan",
            "install",
            "broken",
        },
        .environ_map = &environ,
    });
    defer allocator.free(broken_result.stdout);
    defer allocator.free(broken_result.stderr);
    try expectExitedZero(broken_result);

    var broken = try expectPlanJson(broken_result.stdout);
    defer broken.deinit();
    const broken_object = broken.value.object;
    try std.testing.expectEqualStrings(
        "problems",
        broken_object.get("environment").?.object
            .get("resolution_status").?.string,
    );
    const problems = broken_object.get("problems").?.array.items;
    try std.testing.expect(problems.len != 0);
    try std.testing.expectEqualStrings(
        "unsatisfied_requirement",
        problems[0].object.get("kind").?.string,
    );
}
