//! Loadable-plugin contract coverage required before the built-in Zig port.
//!
//! These tests drive the installed CLI and shared objects. In particular,
//! repogpgcheck's current contract is that repository `gpgkey=` entries do not
//! supply keys for repository metadata signatures: GPGME uses the ambient
//! OpenPGP keyring selected by `GNUPGHOME`.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;
const metalink_plugin = "tdnfmetalink";
const repogpgcheck_plugin = "tdnfrepogpgcheck";
const signature_check_code: u8 = 2004 % 256;
const metalink_validation_code: u8 = 2501 % 256;

fn configurePlugins(
    root: *harness.Root,
    globally_enabled: bool,
    metalink_enabled: bool,
    repogpgcheck_enabled: bool,
) !void {
    try root.tmp.dir.createDirPath(io, "pluginconf.d");
    try root.tmp.dir.writeFile(io, .{
        .sub_path = "pluginconf.d/" ++ metalink_plugin ++ ".conf",
        .data = if (metalink_enabled) "[main]\nenabled=1\n" else "[main]\nenabled=0\n",
    });
    try root.tmp.dir.writeFile(io, .{
        .sub_path = "pluginconf.d/" ++ repogpgcheck_plugin ++ ".conf",
        .data = if (repogpgcheck_enabled) "[main]\nenabled=1\n" else "[main]\nenabled=0\n",
    });

    const conf_dir = try std.fs.path.join(root.allocator, &.{ root.path, "pluginconf.d" });
    defer root.allocator.free(conf_dir);
    try root.setMainOption("plugins", if (globally_enabled) "1" else "0");
    try root.setMainOption("pluginconfpath", conf_dir);
    try root.setMainOption("pluginpath", root.layout.plugin_dir);
}

fn expectLoaded(result: *const harness.Result, name: []const u8, expected: bool) !void {
    const line = try std.fmt.allocPrint(result.allocator, "Loaded plugin: {s}", .{name});
    defer result.allocator.free(line);
    try std.testing.expectEqual(expected, result.stdoutContains(line));
}

fn expectPluginSet(
    root: *harness.Root,
    args: []const []const u8,
    metalink_loaded: bool,
    repogpgcheck_loaded: bool,
) !void {
    var result = try root.run(args);
    defer result.deinit();
    try result.expectOk();
    try expectLoaded(&result, metalink_plugin, metalink_loaded);
    try expectLoaded(&result, repogpgcheck_plugin, repogpgcheck_loaded);
}

fn writeRepo(root: *harness.Root, body: []const u8) !void {
    try root.tmp.dir.writeFile(io, .{
        .sub_path = "etc/yum.repos.d/photon-test.repo",
        .data = body,
    });
}

fn writeMetalinkRepo(root: *harness.Root, valid_checksum: bool) !void {
    const repomd_path = try std.fs.path.join(
        root.allocator,
        &.{ root.layout.repo_dir, "photon-test", "repodata", "repomd.xml" },
    );
    defer root.allocator.free(repomd_path);
    const repomd = try std.Io.Dir.cwd().readFileAlloc(
        io,
        repomd_path,
        root.allocator,
        .unlimited,
    );
    defer root.allocator.free(repomd);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(repomd, &digest, .{});
    var digest_hex = std.fmt.bytesToHex(digest, .lower);
    if (!valid_checksum) digest_hex[0] = if (digest_hex[0] == '0') '1' else '0';

    const metalink_path = try std.fs.path.join(root.allocator, &.{ root.path, "metalink.xml" });
    defer root.allocator.free(metalink_path);
    const metalink = try std.fmt.allocPrint(root.allocator,
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<metalink version="3.0" xmlns="http://www.metalinker.org/">
        \\ <files>
        \\  <file name="repomd.xml">
        \\   <size>{d}</size>
        \\   <verification><hash type="sha256">{s}</hash></verification>
        \\   <resources>
        \\    <url protocol="file" type="file" preference="100">file://{s}</url>
        \\   </resources>
        \\  </file>
        \\ </files>
        \\</metalink>
        \\
    , .{ repomd.len, &digest_hex, repomd_path });
    defer root.allocator.free(metalink);
    try root.tmp.dir.writeFile(io, .{ .sub_path = "metalink.xml", .data = metalink });

    const repo = try std.fmt.allocPrint(root.allocator,
        \\[photon-test]
        \\name=Test Repo
        \\metalink=file://{s}
        \\enabled=1
        \\gpgcheck=0
        \\
    , .{metalink_path});
    defer root.allocator.free(repo);
    try writeRepo(root, repo);
}

fn writeRepoGpgCheckRepo(root: *harness.Root) !void {
    const pubkey = try std.fs.path.join(
        root.allocator,
        &.{ root.layout.repo_dir, "photon-test", "keys", "pubkey.asc" },
    );
    defer root.allocator.free(pubkey);
    const repo = try std.fmt.allocPrint(root.allocator,
        \\[photon-test]
        \\name=Test Repo
        \\baseurl=file://{s}/photon-test
        \\enabled=1
        \\gpgcheck=0
        \\repo_gpgcheck=1
        \\gpgkey=file://{s}
        \\
    , .{ root.layout.repo_dir, pubkey });
    defer root.allocator.free(repo);
    try writeRepo(root, repo);
}

fn setAmbientGpgHome(root: *harness.Root, import_repo_key: bool) !void {
    try root.tmp.dir.createDirPath(io, "gnupg");
    const home = try std.fs.path.join(root.allocator, &.{ root.path, "gnupg" });
    defer root.allocator.free(home);
    try root.environ.put("GNUPGHOME", home);

    if (!import_repo_key) return;

    const pubkey = try std.fs.path.join(
        root.allocator,
        &.{ root.layout.repo_dir, "photon-test", "keys", "pubkey.asc" },
    );
    defer root.allocator.free(pubkey);
    const imported = try std.process.run(root.allocator, io, .{
        .argv = &.{ "gpg", "--batch", "--no-tty", "--homedir", home, "--import", pubkey },
        .environ_map = &root.environ,
    });
    defer root.allocator.free(imported.stdout);
    defer root.allocator.free(imported.stderr);
    switch (imported.term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print(
        "failed to import repository key into ambient GNUPGHOME\nstdout:\n{s}\nstderr:\n{s}\n",
        .{ imported.stdout, imported.stderr },
    );
    return error.TestUnexpectedResult;
}

test "plugin contract: global, per-plugin, and CLI glob controls select loadable plugins" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();

    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, false, true, true);
        try expectPluginSet(&root, &.{ "repolist", "--enableplugin=*" }, false, false);
    }
    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, true, true, true);
        try expectPluginSet(&root, &.{ "repolist", "--noplugins" }, false, false);
    }
    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, true, true, false);
        try expectPluginSet(&root, &.{"repolist"}, true, false);
    }
    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, true, false, false);
        try expectPluginSet(&root, &.{ "repolist", "--enableplugin=tdnf*" }, true, true);
    }
    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, true, true, true);
        try expectPluginSet(&root, &.{ "repolist", "--disableplugin=*" }, false, false);
        try expectPluginSet(
            &root,
            &.{ "repolist", "--disableplugin=*", "--enableplugin=tdnfrepo*" },
            false,
            true,
        );
    }
}

test "plugin contract: metalink INIT, REPO, and REPO_MD flow supplies and validates repomd" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();

    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, true, true, false);
        try writeMetalinkRepo(&root, true);

        var result = try root.run(&.{ "makecache", "--refresh" });
        defer result.deinit();
        try result.expectOk();
        try expectLoaded(&result, metalink_plugin, true);
    }
    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, true, true, false);
        try writeMetalinkRepo(&root, false);

        var result = try root.run(&.{ "makecache", "--refresh" });
        defer result.deinit();
        try result.expectCode(metalink_validation_code);
        try expectLoaded(&result, metalink_plugin, true);
        try result.expectStderrContains(
            "Checksum Validation failed for the repomd.xml downloaded using URL from metalink",
        );
    }
}

test "plugin contract: repogpgcheck uses the ambient GnuPG keyring, not repository gpgkey" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();

    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, true, false, true);
        try writeRepoGpgCheckRepo(&root);
        try setAmbientGpgHome(&root, false);

        var result = try root.run(&.{ "makecache", "--refresh" });
        defer result.deinit();
        try result.expectCode(signature_check_code);
        try expectLoaded(&result, repogpgcheck_plugin, true);
        try result.expectStderrContains(
            "Plugin error: repogpgcheck plugin error: failed to verify signature",
        );
    }
    {
        var root = try h.root();
        defer root.deinit();
        try configurePlugins(&root, true, false, true);
        try writeRepoGpgCheckRepo(&root);
        try setAmbientGpgHome(&root, true);

        var result = try root.run(&.{ "makecache", "--refresh" });
        defer result.deinit();
        try result.expectOk();
        try expectLoaded(&result, repogpgcheck_plugin, true);
    }
}
