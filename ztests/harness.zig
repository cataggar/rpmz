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
const compatibility_command = "tdnf";

pub const Error = error{
    MissingBuildTree,
    MissingRepoSeed,
    NotRoot,
};

/// Every install root starts empty, so nothing in it provides `distroverpkg`
/// and `$releasever` cannot be derived. `pytests/tests/test_installroot.py`
/// pins it the same way for the same reason.
pub const releasever = "4.0";

/// The rpm architecture the fixture packages were built for.
///
/// `pytests/repo/setup-repo.sh` runs `rpmbuild` on the host, so the corpus is
/// native: `x86_64` on an x64 runner and `aarch64` on an arm64 one. A test
/// that hard-codes `x86_64` in an expected NEVRA passes on one CI leg and
/// fails on the other.
pub const basearch = switch (@import("builtin").cpu.arch) {
    .x86_64 => "x86_64",
    .aarch64 => "aarch64",
    else => @compileError("add this architecture's rpm name to harness.basearch"),
};

/// Where the built binaries and the generated repository seed live. `zig build`
/// writes the same values into `pytests/config.json`, but the harness resolves
/// them from the environment so a run never depends on that file.
pub const Layout = struct {
    /// `<prefix>/bin/rpmz`.
    rpmz: []const u8,
    /// `<prefix>/lib/rpmz-plugins`.
    plugin_dir: []const u8,
    /// Absolute path to the repository seed `setup-repo.sh` produced. It has to
    /// be absolute because it becomes a `file://` URL.
    repo_dir: []const u8,

    pub fn deinit(self: Layout, allocator: std.mem.Allocator) void {
        allocator.free(self.rpmz);
        allocator.free(self.plugin_dir);
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

    const rpmz = try std.fs.path.join(allocator, &.{ prefix, "bin", "rpmz" });
    errdefer allocator.free(rpmz);
    cwd.access(io, rpmz, .{}) catch return Error.MissingBuildTree;

    const plugin_dir = std.testing.environ.getAlloc(
        allocator,
        "TDNF_ZTEST_PLUGIN_DIR",
    ) catch try std.fs.path.join(allocator, &.{ prefix, "lib", "rpmz-plugins" });
    errdefer allocator.free(plugin_dir);

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

    return .{
        .rpmz = rpmz,
        .plugin_dir = plugin_dir,
        .repo_dir = repo_dir,
    };
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

/// The outcome of one `rpmz` invocation.
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

    /// Note that rpmz's error-code descriptions ("Nothing to do.", and the rest
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

    /// Asserts the command produced no results at all.
    ///
    /// `expectStdoutContains` cannot express "and nothing else", so a command
    /// that is supposed to find nothing has to be checked this way. Both false
    /// passes #253 records were commands that printed nothing useful while an
    /// assertion looked only for a substring that happened to be present.
    pub fn expectStdoutEmpty(self: *const Result) !void {
        if (std.mem.trim(u8, self.stdout, " \t\r\n").len == 0) return;
        std.debug.print(
            "expected no output\nstdout:\n{s}\nstderr:\n{s}\n",
            .{ self.stdout, self.stderr },
        );
        return error.TestUnexpectedResult;
    }

    /// One row of `rpmz tdnf list` output: `<name>.<arch>  <evr>  <repo>`.
    pub const PackageLine = struct {
        name: []const u8,
        arch: []const u8,
        evr: []const u8,
        repo: []const u8,

        /// `<name>-<evr>.<arch>`, the form `expectPackageSet` takes.
        pub fn nevra(self: PackageLine, allocator: std.mem.Allocator) ![]u8 {
            return std.fmt.allocPrint(allocator, "{s}-{s}.{s}", .{
                self.name,
                self.evr,
                self.arch,
            });
        }
    };

    /// Parses `rpmz tdnf list`'s three-column output.
    ///
    /// The returned strings borrow `stdout`, so they live as long as the
    /// `Result`. A line that does not have exactly three columns, or whose
    /// first column carries no `.<arch>` suffix, is a parse failure rather
    /// than a skipped row: silently ignoring it is how an assertion ends up
    /// agreeing with output it never understood.
    pub fn packageLines(
        self: *const Result,
        allocator: std.mem.Allocator,
    ) !std.ArrayList(PackageLine) {
        var out: std.ArrayList(PackageLine) = .empty;
        errdefer out.deinit(allocator);

        var lines = std.mem.tokenizeScalar(u8, self.stdout, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0) continue;

            var columns = std.mem.tokenizeAny(u8, line, " \t");
            const qualified = columns.next() orelse return error.TestUnexpectedResult;
            const evr = columns.next() orelse {
                std.debug.print("list row has fewer than three columns: \"{s}\"\n", .{line});
                return error.TestUnexpectedResult;
            };
            const repo = columns.next() orelse {
                std.debug.print("list row has fewer than three columns: \"{s}\"\n", .{line});
                return error.TestUnexpectedResult;
            };
            if (columns.next() != null) {
                std.debug.print("list row has more than three columns: \"{s}\"\n", .{line});
                return error.TestUnexpectedResult;
            }

            const dot = std.mem.lastIndexOfScalar(u8, qualified, '.') orelse {
                std.debug.print("list row has no arch suffix: \"{s}\"\n", .{line});
                return error.TestUnexpectedResult;
            };

            try out.append(allocator, .{
                .name = qualified[0..dot],
                .arch = qualified[dot + 1 ..],
                .evr = evr,
                .repo = repo,
            });
        }

        return out;
    }

    /// Asserts stdout lists exactly `expected`, as `<name>-<evr>.<arch>`
    /// entries, in any order and with no extras.
    ///
    /// This is the assertion `expectStdoutContains` cannot make. `list
    /// available 'pkg>=1.0.1'` legitimately returns *both* versions of a
    /// two-version package, so asserting that the higher one appears passes
    /// just as well when the `>=` filter is ignored entirely and everything is
    /// returned -- the weak-assertion pattern #253 tracks.
    pub fn expectPackageSet(
        self: *const Result,
        allocator: std.mem.Allocator,
        expected: []const []const u8,
    ) !void {
        var parsed = try self.packageLines(allocator);
        defer parsed.deinit(allocator);

        var actual: std.ArrayList([]const u8) = .empty;
        defer {
            for (actual.items) |item| allocator.free(item);
            actual.deinit(allocator);
        }
        for (parsed.items) |line| {
            try actual.append(allocator, try line.nevra(allocator));
        }

        const wanted = try allocator.dupe([]const u8, expected);
        defer allocator.free(wanted);

        std.mem.sort([]const u8, actual.items, {}, lessThanString);
        std.mem.sort([]const u8, wanted, {}, lessThanString);

        var same = actual.items.len == wanted.len;
        if (same) {
            for (actual.items, wanted) |got, want| {
                if (!std.mem.eql(u8, got, want)) {
                    same = false;
                    break;
                }
            }
        }
        if (same) return;

        std.debug.print("expected exactly these packages:\n", .{});
        for (wanted) |want| std.debug.print("  {s}\n", .{want});
        std.debug.print("but the command listed:\n", .{});
        for (actual.items) |got| std.debug.print("  {s}\n", .{got});
        std.debug.print("stdout:\n{s}\nstderr:\n{s}\n", .{ self.stdout, self.stderr });
        return error.TestUnexpectedResult;
    }
};

fn lessThanString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

/// One test's private install root: a throwaway directory holding its own
/// `rpmz.conf`, repo definition, cache and rpmdb.
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

    /// Sets a `[main]` option and rewrites `rpmz.conf`.
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
        try self.tmp.dir.writeFile(io, .{ .sub_path = "rpmz.conf", .data = body.items });
    }

    /// Runs the package-manager compatibility command against this root.
    /// `-c <conf>`, `--installroot <root>` and `--releasever` are injected,
    /// mirroring what the pytest `utils.run` fixture does, so a test body reads
    /// like the command a user would type.
    pub fn run(self: *Root, args: []const []const u8) !Result {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(self.allocator);
        try argv.ensureTotalCapacity(self.allocator, args.len + 7);

        argv.appendAssumeCapacity(self.layout.rpmz);
        argv.appendAssumeCapacity(compatibility_command);
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

    /// True when `name` is installed in this root. It asks `rpmz`, so the
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
        try tmp.dir.createDirPath(io, "var/cache/rpmz");

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

        const conf_file = try std.fs.path.join(self.allocator, &.{ path, "rpmz.conf" });
        errdefer self.allocator.free(conf_file);

        var environ: std.process.Environ.Map = .init(self.allocator);
        errdefer environ.deinit();
        try environ.putPosixBlock(std.testing.environ.block.view());

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

/// `zig build ztest` runs an actionable preflight before the test binary. If
/// the harness is invoked directly, propagate precondition errors instead of
/// turning the whole suite into an all-skipped success.
pub fn open(allocator: std.mem.Allocator) !Harness {
    return Harness.init(allocator);
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

/// Builds a `Result` over literal output, so the parsing helpers can be tested
/// without spawning `rpmz`.
fn resultFromStdout(allocator: std.mem.Allocator, stdout: []const u8) !Result {
    return .{
        .allocator = allocator,
        .code = 0,
        .stdout = try allocator.dupe(u8, stdout),
        .stderr = try allocator.dupe(u8, ""),
    };
}

test "expectPackageSet accepts the exact set and rejects a superset" {
    const allocator = std.testing.allocator;
    var result = try resultFromStdout(allocator,
        \\tdnf-test-multiversion.x86_64                1.0.1-1               photon-test
        \\tdnf-test-multiversion.x86_64                1.0.2-1               photon-test
        \\
    );
    defer result.deinit();

    try result.expectPackageSet(allocator, &.{
        "tdnf-test-multiversion-1.0.2-1.x86_64",
        "tdnf-test-multiversion-1.0.1-1.x86_64",
    });

    // The assertion this whole helper exists for: a substring check for the
    // higher version passes here even though the lower one is present too.
    try std.testing.expectError(error.TestUnexpectedResult, result.expectPackageSet(
        allocator,
        &.{"tdnf-test-multiversion-1.0.2-1.x86_64"},
    ));
    try std.testing.expectError(error.TestUnexpectedResult, result.expectPackageSet(
        allocator,
        &.{ "tdnf-test-multiversion-1.0.1-1.x86_64", "tdnf-test-multiversion-1.0.2-1.x86_64", "tdnf-test-one-1.0.1-2.x86_64" },
    ));
}

test "packageLines rejects rows it does not understand" {
    const allocator = std.testing.allocator;

    for ([_][]const u8{
        "tdnf-test-one.x86_64  1.0.1-2\n",
        "tdnf-test-one.x86_64  1.0.1-2  photon-test  extra\n",
        "tdnf-test-one  1.0.1-2  photon-test\n",
    }) |stdout| {
        var result = try resultFromStdout(allocator, stdout);
        defer result.deinit();
        try std.testing.expectError(
            error.TestUnexpectedResult,
            result.expectPackageSet(allocator, &.{}),
        );
    }
}

test "expectStdoutEmpty tolerates trailing whitespace but not rows" {
    const allocator = std.testing.allocator;

    var blank = try resultFromStdout(allocator, "  \n\n");
    defer blank.deinit();
    try blank.expectStdoutEmpty();

    var listed = try resultFromStdout(allocator, "tdnf-test-one.x86_64 1.0.1-2 photon-test\n");
    defer listed.deinit();
    try std.testing.expectError(error.TestUnexpectedResult, listed.expectStdoutEmpty());
}
