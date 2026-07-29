//! Integration test harness: the Zig counterpart of `pytests/conftest.py`.
//!
//! Two things make the pytest suite slow, and neither is Python. Every test
//! installs into the *host* rpmdb, so the whole corpus has to run serially and
//! each test has to undo itself; and the fixture repository is served from one
//! process bound to a fixed port, so a second runner cannot start.
//!
//! This harness removes both. Each test gets its own install root, so tests
//! share nothing and clean up by being thrown away, and the repository is
//! addressed with a `file://` base URL, so there is no server and no port to
//! collide over. HTTP transport coverage stays in pytest, where the tests that
//! are actually about downloading live.
//!
//! What this deliberately does *not* do is rebuild the RPM fixtures:
//! `pytests/repo/setup-repo.sh` needs host `rpmbuild` and `createrepo_c`, it is
//! already incremental, and reimplementing it would buy nothing.

const std = @import("std");

const io = std.testing.io;

pub const Error = error{
    MissingBuildTree,
    MissingRepoSeed,
    NotRoot,
};

/// Every install root starts empty, so nothing in it provides `distroverpkg`
/// and `$releasever` cannot be derived. `pytests/tests/test_installroot.py`
/// pins it the same way for the same reason.
pub const releasever = "4.0";

/// Where the built binaries and the generated repository seed live. `zig build`
/// writes the same values into `pytests/config.json`, but the harness resolves
/// them from the environment so a run never depends on that file.
pub const Layout = struct {
    /// `<prefix>/bin/tdnf`.
    tdnf: []const u8,
    /// `<prefix>/lib`, needed on the loader path for `libtdnf.so`.
    lib_dir: []const u8,
    /// Absolute path to the repository seed `setup-repo.sh` produced. It has to
    /// be absolute because it becomes a `file://` URL.
    repo_dir: []const u8,

    pub fn deinit(self: Layout, allocator: std.mem.Allocator) void {
        allocator.free(self.tdnf);
        allocator.free(self.lib_dir);
        allocator.free(self.repo_dir);
    }
};

/// Resolves the build tree from `TDNF_ZTEST_PREFIX`, falling back to `out`,
/// which is the prefix the project's instructions use.
pub fn resolveLayout(allocator: std.mem.Allocator) !Layout {
    // Installing a package sets each file's owner from its rpm header, which
    // is almost always uid 0, so `chown` fails for anyone but root. The pytest
    // suite has the same requirement; this only makes it explicit.
    if (std.os.linux.geteuid() != 0) return Error.NotRoot;

    const prefix = std.testing.environ.getAlloc(allocator, "TDNF_ZTEST_PREFIX") catch
        try allocator.dupe(u8, "out");
    defer allocator.free(prefix);

    const cwd = std.Io.Dir.cwd();

    const tdnf = try std.fs.path.join(allocator, &.{ prefix, "bin", "tdnf" });
    errdefer allocator.free(tdnf);
    cwd.access(io, tdnf, .{}) catch return Error.MissingBuildTree;

    const lib_dir = try std.fs.path.join(allocator, &.{ prefix, "lib" });
    errdefer allocator.free(lib_dir);

    // `photon-test/repodata/repomd.xml` is what `setup-repo.sh` publishes last,
    // so its presence means the seed finished rather than died halfway.
    const probe = try std.fs.path.join(
        allocator,
        &.{ prefix, "repo", "photon-test", "repodata", "repomd.xml" },
    );
    defer allocator.free(probe);
    cwd.access(io, probe, .{}) catch return Error.MissingRepoSeed;

    const repo_dir = try realPathAlloc(allocator, prefix, "repo");
    errdefer allocator.free(repo_dir);

    return .{ .tdnf = tdnf, .lib_dir = lib_dir, .repo_dir = repo_dir };
}

fn realPathAlloc(
    allocator: std.mem.Allocator,
    parent: []const u8,
    sub_path: []const u8,
) ![]u8 {
    var dir = try std.Io.Dir.cwd().openDir(io, parent, .{});
    defer dir.close(io);

    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try dir.realPathFile(io, sub_path, &buffer);
    return allocator.dupe(u8, buffer[0..len]);
}

/// The outcome of one `tdnf` invocation.
pub const Result = struct {
    allocator: std.mem.Allocator,
    code: u8,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: *Result) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
        self.* = undefined;
    }

    /// Reports the exit code *and* both streams on failure. A bare
    /// `expectEqual(0, code)` turns every product bug into "expected 0, found
    /// 1005", which costs a rerun to diagnose.
    pub fn expectCode(self: *const Result, expected: u8) !void {
        if (self.code == expected) return;
        std.debug.print(
            "expected exit code {d}, found {d}\nstdout:\n{s}\nstderr:\n{s}\n",
            .{ expected, self.code, self.stdout, self.stderr },
        );
        return error.TestUnexpectedResult;
    }

    pub fn expectOk(self: *const Result) !void {
        return self.expectCode(0);
    }

    pub fn stdoutContains(self: *const Result, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.stdout, needle) != null;
    }

    pub fn stderrContains(self: *const Result, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.stderr, needle) != null;
    }

    pub fn expectStdoutContains(self: *const Result, needle: []const u8) !void {
        if (self.stdoutContains(needle)) return;
        std.debug.print(
            "stdout did not contain \"{s}\"\nstdout:\n{s}\nstderr:\n{s}\n",
            .{ needle, self.stdout, self.stderr },
        );
        return error.TestUnexpectedResult;
    }

    /// Note that tdnf's error-code descriptions ("Nothing to do.", and the rest
    /// of the table in `tools/cli/lib/apimisc.zig`) are written to stderr even
    /// when the command exits 0, so assertions about them belong here.
    pub fn expectStderrContains(self: *const Result, needle: []const u8) !void {
        if (self.stderrContains(needle)) return;
        std.debug.print(
            "stderr did not contain \"{s}\"\nstdout:\n{s}\nstderr:\n{s}\n",
            .{ needle, self.stdout, self.stderr },
        );
        return error.TestUnexpectedResult;
    }
};

/// One test's private install root: a throwaway directory holding its own
/// `tdnf.conf`, repo definition, cache and rpmdb.
///
/// Nothing here touches the host rpmdb, which is what makes these tests
/// parallel-safe and lets them skip the snapshot/restore dance
/// `check_packages_consistency` performs in `conftest.py`.
pub const Root = struct {
    allocator: std.mem.Allocator,
    layout: *const Layout,
    environ: std.process.Environ.Map,
    tmp: std.testing.TmpDir,
    path: []const u8,
    conf: []const u8,
    /// The `[main]` section, kept here so a test can change one option and have
    /// the file re-rendered — the counterpart of pytest's `utils.edit_config`.
    /// Because the root is private to the test, editing in place is safe.
    main: std.StringArrayHashMapUnmanaged([]const u8),

    pub fn deinit(self: *Root) void {
        var it = self.main.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.main.deinit(self.allocator);
        self.allocator.free(self.conf);
        self.allocator.free(self.path);
        self.environ.deinit();
        self.tmp.cleanup();
        self.* = undefined;
    }

    /// Sets a `[main]` option and rewrites `tdnf.conf`.
    pub fn setMainOption(self: *Root, key: []const u8, value: []const u8) !void {
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        if (self.main.getEntry(key)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            entry.value_ptr.* = owned_value;
        } else {
            const owned_key = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(owned_key);
            try self.main.put(self.allocator, owned_key, owned_value);
        }
        try self.writeConf();
    }

    fn writeConf(self: *Root) !void {
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(self.allocator);

        try body.appendSlice(self.allocator, "[main]\n");
        var it = self.main.iterator();
        while (it.next()) |entry| {
            try body.print(
                self.allocator,
                "{s}={s}\n",
                .{ entry.key_ptr.*, entry.value_ptr.* },
            );
        }
        try self.tmp.dir.writeFile(io, .{ .sub_path = "tdnf.conf", .data = body.items });
    }

    /// Runs `tdnf` against this root. `-c <conf>`, `--installroot <root>` and
    /// `--releasever` are injected, mirroring what the pytest `utils.run`
    /// fixture does, so a test body reads like the command a user would type.
    pub fn run(self: *Root, args: []const []const u8) !Result {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(self.allocator);
        try argv.ensureTotalCapacity(self.allocator, args.len + 6);

        argv.appendAssumeCapacity(self.layout.tdnf);
        argv.appendAssumeCapacity("-c");
        argv.appendAssumeCapacity(self.conf);
        argv.appendAssumeCapacity("--installroot");
        argv.appendAssumeCapacity(self.path);
        argv.appendAssumeCapacity("--releasever=" ++ releasever);
        argv.appendSliceAssumeCapacity(args);

        const run_result = try std.process.run(self.allocator, io, .{
            .argv = argv.items,
            .environ_map = &self.environ,
        });

        return .{
            .allocator = self.allocator,
            .code = switch (run_result.term) {
                .exited => |c| c,
                else => 255,
            },
            .stdout = run_result.stdout,
            .stderr = run_result.stderr,
        };
    }

    /// True when `name` is installed in this root. It asks `tdnf`, so the
    /// assertion exercises the same code path the test is about.
    pub fn isInstalled(self: *Root, name: []const u8) !bool {
        return self.isInstalledVersion(name, null);
    }

    /// True when `name` is installed, at `version` when one is given. Versions
    /// are compared as whole whitespace-delimited columns so that `1.0.1-1`
    /// does not match `1.0.1-10`.
    pub fn isInstalledVersion(
        self: *Root,
        name: []const u8,
        version: ?[]const u8,
    ) !bool {
        var result = try self.run(&.{ "--disablerepo=*", "list", "--installed", name });
        defer result.deinit();
        if (result.code != 0) return false;

        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            var columns = std.mem.tokenizeAny(u8, line, " \t");
            const first = columns.next() orelse continue;
            // The name column is `<name>.<arch>`.
            if (!std.mem.startsWith(u8, first, name)) continue;
            if (first.len == name.len or first[name.len] != '.') continue;

            const wanted = version orelse return true;
            while (columns.next()) |column| {
                if (std.mem.eql(u8, column, wanted)) return true;
            }
        }
        return false;
    }
};

/// The session fixture: the resolved build tree plus a factory for the per-test
/// install roots.
pub const Harness = struct {
    allocator: std.mem.Allocator,
    layout: Layout,

    pub fn init(allocator: std.mem.Allocator) !Harness {
        return .{ .allocator = allocator, .layout = try resolveLayout(allocator) };
    }

    pub fn deinit(self: *Harness) void {
        self.layout.deinit(self.allocator);
        self.* = undefined;
    }

    /// A fresh, empty install root wired to this harness's repository.
    pub fn root(self: *Harness) !Root {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();

        var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const len = try tmp.dir.realPath(io, &buffer);
        const path = try self.allocator.dupe(u8, buffer[0..len]);
        errdefer self.allocator.free(path);

        try tmp.dir.createDirPath(io, "etc/yum.repos.d");
        try tmp.dir.createDirPath(io, "var/cache/tdnf");

        const repo_file = try std.fmt.allocPrint(self.allocator,
            \\[photon-test]
            \\name=Test Repo
            \\baseurl=file://{s}/photon-test
            \\enabled=1
            \\gpgcheck=0
            \\
        , .{self.layout.repo_dir});
        defer self.allocator.free(repo_file);
        try tmp.dir.writeFile(io, .{
            .sub_path = "etc/yum.repos.d/photon-test.repo",
            .data = repo_file,
        });

        const conf_file = try std.fs.path.join(self.allocator, &.{ path, "tdnf.conf" });
        errdefer self.allocator.free(conf_file);

        var environ: std.process.Environ.Map = .init(self.allocator);
        errdefer environ.deinit();
        try environ.putPosixBlock(std.testing.environ.block.view());
        try environ.put("LD_LIBRARY_PATH", self.layout.lib_dir);

        var created: Root = .{
            .allocator = self.allocator,
            .layout = &self.layout,
            .environ = environ,
            .tmp = tmp,
            .path = path,
            .conf = conf_file,
            .main = .empty,
        };
        errdefer created.main.deinit(self.allocator);

        const repodir = try std.fs.path.join(self.allocator, &.{ path, "etc/yum.repos.d" });
        defer self.allocator.free(repodir);
        const cachedir = try std.fs.path.join(self.allocator, &.{ path, "var/cache/tdnf" });
        defer self.allocator.free(cachedir);

        try created.setMainOption("gpgcheck", "0");
        try created.setMainOption("installonly_limit", "3");
        try created.setMainOption("clean_requirements_on_remove", "true");
        try created.setMainOption("repodir", repodir);
        try created.setMainOption("cachedir", cachedir);

        return created;
    }
};

/// Skips rather than fails when the build tree, the repository seed, or root
/// privilege is absent, so the step stays runnable on a host that has not
/// produced the RPM fixtures.
pub fn open(allocator: std.mem.Allocator) !Harness {
    return Harness.init(allocator) catch |err| switch (err) {
        Error.MissingBuildTree, Error.MissingRepoSeed, Error.NotRoot => error.SkipZigTest,
        else => err,
    };
}

test "the harness reaches the repository seed it was pointed at" {
    var harness = try open(std.testing.allocator);
    defer harness.deinit();

    var root = try harness.root();
    defer root.deinit();

    var result = try root.run(&.{"repolist"});
    defer result.deinit();

    try result.expectOk();
    try result.expectStdoutContains("photon-test");
}
