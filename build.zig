//! rpmz build script (replacement for the former CMake build).
//!
//! Produces the rpmz executable, support tools, and built-in plugins. The
//! reusable package surface is the public `rpmz` Zig module registered below;
//! there are no installed C libraries or headers.
//!
//! All compilation goes through `zig cc` (clang from Zig's bundled LLVM).
//! GCC-only warnings from the former cmake/CFlags.cmake were removed; the
//! retained set is the strict subset clang accepts.

const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

const project_name = "rpmz";
const default_project_version = "0.1.0";

/// Patch level of the vendored libsolv (see `.libsolv` in build.zig.zon).
/// Used only by the opt-in libsolv solver oracle.
const vendored_libsolv_version_patch = "39";

/// Warnings + hardening flags from the former cmake/CFlags.cmake, filtered
/// to the strict set clang accepts. GCC-only warnings have been removed.
const rpmz_cflags = [_][]const u8{
    // Vendored libsolv's headers are reached with -I rather than
    // -isystem, because zig cc orders /usr/include *ahead* of user
    // -isystem directories: with -isystem, a host libsolv-devel silently
    // wins and the build compiles against the host's headers while
    // linking the vendored .a. -I restores the intended precedence, and
    // this flag restores the warning suppression that -isystem used to
    // provide, without exempting any of rpmz's own sources -- every
    // libsolv header is spelled <solv/...>, and a
    // header included from a system header is itself a system header, so
    // libsolv's internal quoted includes are covered too.
    "--system-header-prefix=solv/",
    "-Wall",
    "-Wundef",
    "-Wstrict-prototypes",
    "-Wno-trigraphs",
    "-Werror-implicit-function-declaration",
    "-Wdeclaration-after-statement",
    "-Wvla",
    "-Wno-format-security",
    "-Wno-sign-compare",
    "-Wextra",
    "-Werror",
    "-Wformat=2",
    "-Wshadow",
    "-Wmissing-prototypes",
    "-Wold-style-definition",
    "-Wmissing-declarations",
    "-Wredundant-decls",
    "-Wcast-align",
    "-Wpointer-arith",
    "-Wwrite-strings",
    "-Waggregate-return",
    "-Winit-self",
    "-Wnull-dereference",
    "-Walloca",
    "-fno-strict-aliasing",
    "-fno-common",
    "-fno-delete-null-pointer-checks",
    "-fstack-protector-strong",
    "-D_XOPEN_SOURCE=500",
    "-D_DEFAULT_SOURCE",
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_libsolv_oracle = b.option(
        bool,
        "libsolv-oracle",
        "Enable the opt-in vendored libsolv parity oracle",
    ) orelse false;
    const canonical_json_mod = b.createModule(.{
        .root_source_file = b.path("client/canonical_json.zig"),
        .target = target,
        .optimize = optimize,
    });
    const secret_shape_mod = b.createModule(.{
        .root_source_file = b.path("client/secret_shape.zig"),
        .target = target,
        .optimize = optimize,
    });
    const uri_sanitize_mod = b.createModule(.{
        .root_source_file = b.path("client/uri_sanitize.zig"),
        .target = target,
        .optimize = optimize,
    });
    const content_digest_mod = b.createModule(.{
        .root_source_file = b.path("repomd/content_digest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bundle_paths_mod = b.createModule(.{
        .root_source_file = b.path("client/bundle_paths.zig"),
        .target = target,
        .optimize = optimize,
    });
    const atomic_publish_mod = b.createModule(.{
        .root_source_file = b.path("client/atomic_publish.zig"),
        .target = target,
        .optimize = optimize,
    });
    const transaction_plan_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_plan.zig"),
        .target = target,
        .optimize = optimize,
    });
    transaction_plan_mod.addImport("canonical_json", canonical_json_mod);
    const verified_fetch_mod = b.createModule(.{
        .root_source_file = b.path("client/verified_fetch.zig"),
        .target = target,
        .optimize = optimize,
    });
    verified_fetch_mod.addImport("content_digest", content_digest_mod);
    verified_fetch_mod.addImport("transaction_plan", transaction_plan_mod);
    transaction_plan_mod.addImport("secret_shape", secret_shape_mod);
    const transaction_bundle_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_bundle.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bundle_reader_mod = b.createModule(.{
        .root_source_file = b.path("client/bundle_reader.zig"),
        .target = target,
        .optimize = optimize,
    });
    bundle_reader_mod.addImport("content_digest", content_digest_mod);
    bundle_reader_mod.addImport("transaction_bundle", transaction_bundle_mod);
    bundle_reader_mod.addImport("transaction_plan", transaction_plan_mod);
    const bundle_selection_mod = b.createModule(.{
        .root_source_file = b.path("client/bundle_selection.zig"),
        .target = target,
        .optimize = optimize,
    });
    bundle_selection_mod.addImport("bundle_paths", bundle_paths_mod);
    bundle_selection_mod.addImport("transaction_bundle", transaction_bundle_mod);
    bundle_selection_mod.addImport("transaction_plan", transaction_plan_mod);
    const bundle_writer_mod = b.createModule(.{
        .root_source_file = b.path("client/bundle_writer.zig"),
        .target = target,
        .optimize = optimize,
    });
    bundle_writer_mod.addImport("atomic_publish", atomic_publish_mod);
    bundle_writer_mod.addImport("bundle_selection", bundle_selection_mod);
    bundle_writer_mod.addImport("transaction_bundle", transaction_bundle_mod);
    bundle_writer_mod.addImport("transaction_plan", transaction_plan_mod);
    bundle_writer_mod.addImport("uri_sanitize", uri_sanitize_mod);
    bundle_writer_mod.addImport("verified_fetch", verified_fetch_mod);
    transaction_bundle_mod.addImport("canonical_json", canonical_json_mod);
    transaction_bundle_mod.addImport("secret_shape", secret_shape_mod);
    transaction_bundle_mod.addImport("transaction_plan", transaction_plan_mod);
    const public_rpmz_mod = b.addModule("rpmz", .{
        .root_source_file = b.path("rpmz.zig"),
        .target = target,
        .optimize = optimize,
    });
    public_rpmz_mod.addImport("transaction_plan", transaction_plan_mod);
    public_rpmz_mod.addImport("transaction_bundle", transaction_bundle_mod);
    public_rpmz_mod.addImport("bundle_reader", bundle_reader_mod);
    // Registered so the public-API audit can see the whole compiled closure,
    // not because `rpmz.zig` re-exports them. They are shared implementation
    // detail with no stability promise of their own.
    public_rpmz_mod.addImport("canonical_json", canonical_json_mod);
    public_rpmz_mod.addImport("secret_shape", secret_shape_mod);

    // Zig 0.16 documents an empty Build.pkg_hash as the root package. A
    // dependency consumer needs the resolve module graph, which is built
    // below, but none of the product artifacts, test steps, audits, or
    // generated source files. It returns once the public modules are
    // registered.
    const root_build = b.pkg_hash.len == 0;

    // -Dversion overrides the version baked into the artifacts. Used by the
    // release workflow to pin the binary's version to the git tag.
    const version_override = b.option(
        []const u8,
        "version",
        "Override project version (default: " ++ default_project_version ++ ")",
    );
    const project_version: []const u8 = version_override orelse default_project_version;
    if (version_override) |v| {
        _ = std.SemanticVersion.parse(v) catch
            std.debug.panic("invalid -Dversion='{s}' (expected semantic version)", .{v});
    }

    const history_db_dir = b.option(
        []const u8,
        "history-db-dir",
        "Directory for rpmz history database (compatibility default: /var/lib/tdnf)",
    ) orelse "/var/lib/tdnf";
    const systemd_dir = b.option(
        []const u8,
        "systemd-dir",
        "systemd unit install directory (relative to prefix, default: lib/systemd/system)",
    ) orelse "lib/systemd/system";
    const motdgen_dir = b.option(
        []const u8,
        "motdgen-dir",
        "motd generator directory (relative to prefix, default: etc/motdgen.d)",
    ) orelse "etc/motdgen.d";
    const sysconf_dir = b.option(
        []const u8,
        "sysconfdir",
        "System configuration directory (relative to prefix, default: etc)",
    ) orelse "etc";
    const plugin_dir_rel = b.option(
        []const u8,
        "plugin-dir",
        "Plugin install directory (relative to prefix, default: lib/rpmz-plugins)",
    ) orelse "lib/rpmz-plugins";
    const prefix = b.install_prefix;
    const libdir = "lib";
    // `b.install_prefix` is the literal `--prefix` argument (e.g. `./out`)
    // and is left relative when the caller passes a relative path — unlike
    // the default `zig-out`, which build.zig resolves to an absolute path
    // itself. pytest runs with cwd=`pytests/`, so a relative prefix baked
    // into pytests/config.json (`build_dir`, `bin_dir`, ...) would resolve
    // against the wrong directory. Make it absolute, anchored at the
    // build root (zig build is always invoked from there in practice).
    const abs_prefix = if (std.fs.path.isAbsolute(prefix))
        prefix
    else
        b.pathJoin(&.{ b.build_root.path.?, prefix });
    const replay_acceptance_export_path = b.pathJoin(&.{
        b.build_root.path.?,
        ".zig-cache",
        "replay-acceptance",
        "rpmz-replay-export",
    });
    const full_libdir = b.fmt("{s}/{s}", .{ abs_prefix, libdir });
    const client_config_options = b.addOptions();
    client_config_options.addOption([]const u8, "history_db_dir", history_db_dir);
    client_config_options.addOption([]const u8, "source_root", b.build_root.path.?);
    client_config_options.addOption([]const u8, "system_libdir", full_libdir);
    client_config_options.addOption([]const u8, "project_name", project_name);
    client_config_options.addOption([]const u8, "project_version", project_version);
    // Vendored sqlite backs the Zig-side history and rpmdb code paths.
    const sqlite_dep_optional = b.lazyDependency("sqlite", .{});
    const tls_dep_optional = b.lazyDependency("tls", .{});
    const zlua_dep_optional = b.lazyDependency("zlua", .{
        .target = target,
        .optimize = optimize,
    });
    if (sqlite_dep_optional == null or
        tls_dep_optional == null or
        zlua_dep_optional == null)
    {
        return;
    }
    const client_updateinfo_test_step = b.step(
        "client-updateinfo-test",
        "Run client updateinfo production-logic tests",
    );
    const sqlite_dep = sqlite_dep_optional.?;
    const sqlite_confined_mod = b.createModule(.{
        .root_source_file = b.path("common/sqlite_confined.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
        },
    });
    const sqlite_confined_lib = b.addLibrary(.{
        .name = "rpmzsqliteconfined",
        .linkage = .static,
        .root_module = sqlite_confined_mod,
    });
    const sqlite_confined_api_mod = b.createModule(.{
        .root_source_file = b.path("common/sqlite_confined_api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
        },
    });
    sqlite_confined_api_mod.linkLibrary(sqlite_confined_lib);
    const tls_dep = tls_dep_optional.?;
    const zlua_mod = zlua_dep_optional.?.module("zlua");

    // Generated into the source tree, so only the root build may write
    // them: a dependency's copy of this package is read-only.
    if (root_build) {
        // pytests/mount-small-cache is referenced by tests/test_cache.py; ship a
        // ready-to-run copy in the source tree (gitignored) so `pytest -v` works
        // without an extra configure step.
        writeTemplate(b, "pytests/mount-small-cache.in", "pytests/mount-small-cache", &.{
            .{ .key = "CMAKE_CURRENT_BINARY_DIR", .value = abs_prefix },
        });

        // pytests/config.json: written directly into the source tree (gitignored,
        // via writeTemplate rather than addConfigHeader, for two reasons:
        // (1) addConfigHeader's autoconf_at
        // style prepends a "generated by ConfigHeader" comment line, which is
        // valid in a C header but makes the output invalid JSON — conftest.py's
        // `json.load()` can't parse a leading `/* ... */` comment; (2) conftest.py
        // (`TestUtils.__init__`) reads config.json from the same directory as
        // conftest.py itself (`pytests/config.json`), not from the install
        // prefix, so installing it under `<prefix>/pytests-runtime/` (the old
        // approach) left pytest unable to find it at all. `abs_prefix` (an
        // absolute form of `b.install_prefix`, the resolved `--prefix` value) is
        // used here rather than a hardcoded `zig-out` so this works with the
        // documented `--prefix ./out` build invocation, not just the default
        // `zig-out`, and resolves correctly regardless of pytest's cwd.
        writeTemplate(b, "pytests/config.json.in", "pytests/config.json", &.{
            .{ .key = "PROJECT_NAME", .value = project_name },
            .{ .key = "VERSION", .value = project_version },
            .{ .key = "CMAKE_SOURCE_DIR", .value = b.build_root.path.? },
            .{ .key = "CMAKE_CURRENT_BINARY_DIR", .value = abs_prefix },
            .{ .key = "CMAKE_BINARY_DIR", .value = abs_prefix },
            .{ .key = "PLUGIN_PATH", .value = b.fmt("{s}/{s}", .{ abs_prefix, plugin_dir_rel }) },
            .{ .key = "NATIVE_FILE_INSTALL_BINARY", .value = b.fmt("{s}/libexec/rpmz/rpmz-rpm-install", .{abs_prefix}) },
            .{ .key = "NATIVE_FILE_ERASE_BINARY", .value = b.fmt("{s}/libexec/rpmz/rpmz-rpm-erase", .{abs_prefix}) },
            .{ .key = "HISTORY_UTIL_BINARY", .value = b.fmt("{s}/libexec/rpmz/rpmz-history-util", .{abs_prefix}) },
            .{ .key = "TEST_SUPPORT_BINARY", .value = b.fmt("{s}/libexec/rpmz/rpmz-test-support", .{abs_prefix}) },
            .{ .key = "REPLAY_EXPORT_BINARY", .value = replay_acceptance_export_path },
            .{ .key = "RPMDB_LIST_BINARY", .value = b.fmt("{s}/libexec/rpmz/rpmz-rpmdb-list", .{abs_prefix}) },
            .{ .key = "RPMDB_WRITE_BINARY", .value = b.fmt("{s}/libexec/rpmz/rpmz-rpmdb-write", .{abs_prefix}) },
            .{ .key = "AUTOMATIC_SCRIPT", .value = b.fmt("{s}/bin/rpmz-automatic", .{abs_prefix}) },
        });

        writeTemplateExecutable(
            b,
            "bin/rpmz-automatic.in",
            "bin/rpmz-automatic",
            &.{.{ .key = "VERSION", .value = project_version }},
        );
    }

    const zig_test_step = b.step("test", "Run Zig unit tests");
    const replay_docs_audit_step = b.step(
        "replay-docs-audit",
        "Verify the published replay contract covers every public result tag",
    );
    const run_replay_docs_audit = b.addSystemCommand(
        &.{ "python3", "scripts/replay-docs-audit.py" },
    );
    run_replay_docs_audit.setCwd(b.path("."));
    const test_replay_docs_audit = b.addSystemCommand(
        &.{ "python3", "scripts/replay-docs-audit.py", "--self-test" },
    );
    test_replay_docs_audit.setCwd(b.path("."));
    replay_docs_audit_step.dependOn(&run_replay_docs_audit.step);
    replay_docs_audit_step.dependOn(&test_replay_docs_audit.step);
    const replay_confinement_audit_step = b.step(
        "replay-confinement-audit",
        "Audit replay.zig direct imports and denied API tokens",
    );
    const run_replay_confinement_audit = b.addSystemCommand(
        &.{ "python3", "scripts/replay-confinement-audit.py" },
    );
    run_replay_confinement_audit.setCwd(b.path("."));
    const test_replay_confinement_audit = b.addSystemCommand(
        &.{
            "python3",
            "scripts/replay-confinement-audit.py",
            "--self-test",
        },
    );
    test_replay_confinement_audit.setCwd(b.path("."));
    replay_confinement_audit_step.dependOn(
        &run_replay_confinement_audit.step,
    );
    replay_confinement_audit_step.dependOn(
        &test_replay_confinement_audit.step,
    );
    const migration_audit_step = b.step(
        "migration-audit",
        "Reject increases in the remaining C-to-Zig migration surface",
    );
    const run_migration_audit = b.addSystemCommand(
        &.{ "python3", "scripts/c-to-zig-audit.py" },
    );
    run_migration_audit.setCwd(b.path("."));
    migration_audit_step.dependOn(&run_migration_audit.step);
    migration_audit_step.dependOn(&run_replay_docs_audit.step);
    migration_audit_step.dependOn(&test_replay_docs_audit.step);
    migration_audit_step.dependOn(&run_replay_confinement_audit.step);
    migration_audit_step.dependOn(&test_replay_confinement_audit.step);
    const rebrand_audit_step = b.step(
        "rebrand-audit",
        "Reject stale public and installable legacy product naming",
    );
    const run_rebrand_audit = b.addSystemCommand(
        &.{ "python3", "scripts/rebrand-audit.py" },
    );
    run_rebrand_audit.setCwd(b.path("."));
    rebrand_audit_step.dependOn(&run_rebrand_audit.step);
    migration_audit_step.dependOn(&run_rebrand_audit.step);
    const dead_errdefer_audit_step = b.step(
        "dead-errdefer-audit",
        "Reject errdefer in functions that cannot return an error",
    );
    const run_dead_errdefer_audit = b.addSystemCommand(
        &.{ "python3", "scripts/dead-errdefer-audit.py" },
    );
    run_dead_errdefer_audit.setCwd(b.path("."));
    dead_errdefer_audit_step.dependOn(&run_dead_errdefer_audit.step);
    const native_dependency_audit_step = b.step(
        "native-dependency-audit",
        "Reject system RPM source and ELF dependencies",
    );
    const run_native_dependency_audit = b.addSystemCommand(
        &.{
            "python3",
            "scripts/librpm-audit.py",
            "--prefix",
            b.getInstallPath(.prefix, ""),
        },
    );
    run_native_dependency_audit.setCwd(b.path("."));
    run_native_dependency_audit.step.dependOn(b.getInstallStep());
    native_dependency_audit_step.dependOn(&run_native_dependency_audit.step);
    const sqlite_singleton_audit_step = b.step(
        "sqlite-confined-singleton-audit",
        "Require one confined SQLite registry in each installed consumer",
    );
    const run_sqlite_singleton_audit = b.addSystemCommand(
        &.{
            "python3",
            "scripts/sqlite-confined-singleton-audit.py",
            "--prefix",
            b.getInstallPath(.prefix, ""),
        },
    );
    run_sqlite_singleton_audit.setCwd(b.path("."));
    run_sqlite_singleton_audit.step.dependOn(b.getInstallStep());
    sqlite_singleton_audit_step.dependOn(
        &run_sqlite_singleton_audit.step,
    );
    native_dependency_audit_step.dependOn(
        &run_sqlite_singleton_audit.step,
    );
    const product_no_libsolv_fetch_audit_step = b.step(
        "product-no-libsolv-fetch-audit",
        "Build the product cleanly with fetching disabled and no libsolv",
    );
    const run_product_no_libsolv_fetch_audit = b.addSystemCommand(
        &.{
            "python3",
            "scripts/product-no-libsolv-fetch-audit.py",
            "--zig",
            b.graph.zig_exe,
        },
    );
    run_product_no_libsolv_fetch_audit.setCwd(b.path("."));
    product_no_libsolv_fetch_audit_step.dependOn(
        &run_product_no_libsolv_fetch_audit.step,
    );
    const public_zig_api_audit_step = b.step(
        "public-zig-api-audit",
        "Build and run an external consumer of the public Zig module",
    );
    const run_public_zig_api_audit = b.addSystemCommand(
        &.{
            "python3",
            "scripts/public-zig-api-audit.py",
            "--zig",
            b.graph.zig_exe,
            "--optimize",
            @tagName(optimize),
        },
    );
    run_public_zig_api_audit.setCwd(b.path("."));
    public_zig_api_audit_step.dependOn(&run_public_zig_api_audit.step);
    const replay_acceptance_export_step = b.step(
        "replay-acceptance-export",
        "Build the external public-API replay export test driver",
    );
    const run_replay_acceptance_export = b.addSystemCommand(
        &.{
            "python3",
            "scripts/public-zig-api-audit.py",
            "--zig",
            b.graph.zig_exe,
            "--optimize",
            @tagName(optimize),
            "--replay-export-output",
            replay_acceptance_export_path,
        },
    );
    run_replay_acceptance_export.setCwd(b.path("."));
    replay_acceptance_export_step.dependOn(
        &run_replay_acceptance_export.step,
    );
    const rpmz_error_mod = b.createModule(.{
        .root_source_file = b.path("abi/error_codes.zig"),
        .target = target,
        .optimize = optimize,
    });
    const common_api_mod = b.createModule(.{
        .root_source_file = b.path("common/api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    common_api_mod.addImport("rpmz_error", rpmz_error_mod);
    const internal_abi_mod = b.createModule(.{
        .root_source_file = b.path("abi/internal.zig"),
        .target = target,
        .optimize = optimize,
    });
    const jsondump_abi_mod = b.createModule(.{
        .root_source_file = b.path("jsondump/abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const client_abi_mod = b.createModule(.{
        .root_source_file = b.path("client/abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    client_abi_mod.addImport("tdnf_internal_abi", internal_abi_mod);
    const transaction_plan_execution_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_plan_execution.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    transaction_plan_execution_mod.addImport(
        "tdnf_internal_abi",
        internal_abi_mod,
    );
    transaction_plan_execution_mod.addImport(
        "bundle_selection",
        bundle_selection_mod,
    );
    transaction_plan_execution_mod.addImport(
        "transaction_plan",
        transaction_plan_mod,
    );
    const rpmtrans_flags_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/trans_flags.zig"),
        .target = target,
        .optimize = optimize,
    });
    const client_varsdir_mod = b.createModule(.{
        .root_source_file = b.path("client/varsdir.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    client_abi_mod.addIncludePath(b.path("client"));
    client_abi_mod.addIncludePath(b.path("rpmzig"));
    client_varsdir_mod.addImport("client_abi", client_abi_mod);
    {
        const tests = b.addTest(.{ .root_module = rpmz_error_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const tests = b.addTest(.{ .root_module = public_rpmz_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/updateinfo.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addIncludePath(b.path("client"));
        test_mod.addIncludePath(b.path("rpmzig"));
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_updateinfo_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = canonical_json_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = secret_shape_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = uri_sanitize_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = content_digest_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = bundle_paths_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = atomic_publish_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = bundle_writer_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = bundle_selection_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = bundle_reader_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = verified_fetch_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = transaction_plan_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = transaction_bundle_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    const transaction_plan_capture_abi_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_plan_capture_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const transaction_plan_request_trace_mod = b.createModule(.{
        .root_source_file = b.path(
            "client/transaction_plan_request_trace.zig",
        ),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    transaction_plan_request_trace_mod.addImport(
        "transaction_plan_capture_abi",
        transaction_plan_capture_abi_mod,
    );
    transaction_plan_request_trace_mod.addImport(
        "rpmz_error",
        rpmz_error_mod,
    );
    const transaction_plan_capture_test_step = b.step(
        "transaction-plan-capture-test",
        "Run private transaction plan capture ABI and adapter tests",
    );
    {
        const tests = b.addTest(.{
            .root_module = transaction_plan_request_trace_mod,
        });
        const run_tests = b.addRunArtifact(tests);
        transaction_plan_capture_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }
    const transaction_plan_capture_test_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_plan_capture.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    transaction_plan_capture_test_mod.addImport(
        "transaction_plan_capture_abi",
        transaction_plan_capture_abi_mod,
    );
    transaction_plan_capture_test_mod.addImport(
        "transaction_plan",
        transaction_plan_mod,
    );
    transaction_plan_capture_test_mod.addImport(
        "transaction_plan_request_trace",
        transaction_plan_request_trace_mod,
    );
    transaction_plan_capture_test_mod.addImport("rpmz_error", rpmz_error_mod);
    {
        const tests = b.addTest(.{
            .root_module = transaction_plan_capture_test_mod,
        });
        const run_tests = b.addRunArtifact(tests);
        transaction_plan_capture_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const repomd_abi_mod = b.createModule(.{
        .root_source_file = b.path("abi/repomd_layout.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const solver_result_abi_mod = b.createModule(.{
        .root_source_file = b.path("repomd/solver_result_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const solver_legacy_abi_mod = b.createModule(.{
        .root_source_file = b.path("repomd/solver_legacy_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const solver_live_abi_mod = b.createModule(.{
        .root_source_file = b.path("repomd/solver_live_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    repomd_abi_mod.addImport("solver_result_abi", solver_result_abi_mod);
    repomd_abi_mod.addImport("solver_legacy_abi", solver_legacy_abi_mod);
    repomd_abi_mod.addImport("solver_live_abi", solver_live_abi_mod);
    repomd_abi_mod.addImport("tdnf_internal_abi", internal_abi_mod);
    {
        const tests = b.addTest(.{ .root_module = repomd_abi_mod });
        const run_tests = b.addRunArtifact(tests);
        transaction_plan_capture_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const xml_mod = b.createModule(.{
        .root_source_file = b.path("xml/xml.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const metalink_xml_mod = b.createModule(.{
        .root_source_file = b.path("plugins/metalink/xml.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    metalink_xml_mod.addImport("xml", xml_mod);
    const plugin_metadata_mod = b.createModule(.{
        .root_source_file = b.path("client/plugin_metadata.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    const repository_metadata_mod = b.createModule(.{
        .root_source_file = b.path(
            "repomd/transaction_plan_repository_dependencies.zig",
        ),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    repository_metadata_mod.addImport("xml", xml_mod);
    repository_metadata_mod.addImport("content_digest", content_digest_mod);
    const transaction_plan_repository_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_plan_repository.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    transaction_plan_repository_mod.addImport(
        "repository_metadata",
        repository_metadata_mod,
    );
    transaction_plan_repository_mod.addImport(
        "transaction_plan",
        transaction_plan_mod,
    );
    const transaction_plan_repository_test_step = b.step(
        "transaction-plan-repository-test",
        "Run repository transaction-plan identity capture tests",
    );
    {
        const tests = b.addTest(.{
            .root_module = transaction_plan_repository_mod,
        });
        const run_tests = b.addRunArtifact(tests);
        transaction_plan_repository_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const rpmzig_header_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/header.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const rpm_evr_mod = b.createModule(.{
        .root_source_file = b.path("client/rpm_evr.zig"),
        .target = target,
        .optimize = optimize,
    });

    const rpmzig_pkgfile_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/pkgfile.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    rpmzig_pkgfile_mod.addImport("rpm_header", rpmzig_header_mod);

    const rpmzig_txn_config_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/txn_config.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const rpmzig_file_handle_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/file_handle.zig"),
        .target = target,
        .optimize = optimize,
    });
    rpmzig_file_handle_mod.addImport("rpm_header", rpmzig_header_mod);
    rpmzig_file_handle_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);

    const rpmzig_verify_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/verify.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    rpmzig_verify_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);

    const rpmzig_gpgcheck_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/gpgcheck.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    rpmzig_gpgcheck_mod.addImport("rpm_header", rpmzig_header_mod);
    rpmzig_gpgcheck_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
    rpmzig_gpgcheck_mod.addImport("rpm_file_handle", rpmzig_file_handle_mod);

    const rpmzig_cpio_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/cpio.zig"),
        .target = target,
        .optimize = optimize,
    });

    const rpmzig_rpmdb_test_mod = b.createModule(.{
        .root_source_file = b.path("rpmzig/rpmdb.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            .{ .name = "confined_sqlite", .module = sqlite_confined_api_mod },
        },
    });
    rpmzig_rpmdb_test_mod.addImport("rpm_header", rpmzig_header_mod);
    rpmzig_rpmdb_test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
    rpmzig_rpmdb_test_mod.addImport("rpm_file_handle", rpmzig_file_handle_mod);
    configureLuaScriptletSupport(b, rpmzig_rpmdb_test_mod, zlua_mod);

    const repomd_mod = b.createModule(.{
        .root_source_file = b.path("repomd/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    repomd_mod.addImport("xml", xml_mod);
    repomd_mod.addImport("content_digest", content_digest_mod);
    repomd_mod.addImport("rpm_header", rpmzig_header_mod);
    repomd_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
    repomd_mod.addImport("rpmz_error", rpmz_error_mod);
    repomd_mod.addImport("tdnf_internal_abi", internal_abi_mod);
    repomd_mod.addIncludePath(b.path("rpmzig"));

    const transaction_plan_native_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_plan_native.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    transaction_plan_native_mod.addImport(
        "transaction_plan_capture_abi",
        transaction_plan_capture_abi_mod,
    );
    transaction_plan_native_mod.addImport("rpmz_error", rpmz_error_mod);
    transaction_plan_native_mod.addImport("repomd", repomd_mod);
    const transaction_plan_repository_integration_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_plan_repository.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    transaction_plan_repository_integration_mod.addImport(
        "repository_metadata",
        repomd_mod,
    );
    transaction_plan_repository_integration_mod.addImport(
        "transaction_plan",
        transaction_plan_mod,
    );
    const transaction_plan_integration_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_plan_integration.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    const transaction_plan_integration_options = b.addOptions();
    transaction_plan_integration_options.addOption(
        bool,
        "standalone_test",
        false,
    );
    transaction_plan_integration_mod.addOptions(
        "transaction_plan_integration_options",
        transaction_plan_integration_options,
    );
    transaction_plan_integration_mod.addImport(
        "transaction_plan_capture_abi",
        transaction_plan_capture_abi_mod,
    );
    transaction_plan_integration_mod.addImport(
        "transaction_plan_capture",
        transaction_plan_capture_test_mod,
    );
    transaction_plan_integration_mod.addImport(
        "transaction_plan_native",
        transaction_plan_native_mod,
    );
    transaction_plan_integration_mod.addImport(
        "transaction_plan_repository",
        transaction_plan_repository_integration_mod,
    );
    transaction_plan_integration_mod.addImport(
        "repository_metadata",
        repomd_mod,
    );
    transaction_plan_integration_mod.addImport(
        "transaction_plan",
        transaction_plan_mod,
    );
    transaction_plan_integration_mod.addImport(
        "transaction_plan_request_trace",
        transaction_plan_request_trace_mod,
    );
    transaction_plan_integration_mod.addImport(
        "rpmz_common",
        common_api_mod,
    );
    transaction_plan_integration_mod.addImport(
        "rpm_txn_config",
        rpmzig_txn_config_mod,
    );
    transaction_plan_integration_mod.addImport("rpmz_error", rpmz_error_mod);

    // ----- static libraries ----- //

    const common_lib = blk: {
        const mod = b.createModule(.{
            .root_source_file = b.path("common/common.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addIncludePath(b.path("common"));
        mod.addImport("rpmz_error", rpmz_error_mod);
        mod.addImport("tdnf_internal_abi", internal_abi_mod);
        const lib = b.addLibrary(.{
            .name = "common",
            .linkage = .static,
            .root_module = mod,
        });
        break :blk lib;
    };

    const llconf_lib = blk: {
        const mod = b.createModule(.{
            .root_source_file = b.path("llconf/llconf.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addIncludePath(b.path("llconf"));
        const lib = b.addLibrary(.{
            .name = "rpmzllconf",
            .linkage = .static,
            .root_module = mod,
        });
        break :blk lib;
    };

    const jsondump_lib = blk: {
        const mod = b.createModule(.{
            .root_source_file = b.path("jsondump/jsondump.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        const lib = b.addLibrary(.{
            .name = "jsondump",
            .linkage = .static,
            .root_module = mod,
        });
        break :blk lib;
    };

    const history_lib = blk: {
        const mod = b.createModule(.{
            .root_source_file = b.path("history/history_zig.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
                .{ .name = "confined_sqlite", .module = sqlite_confined_api_mod },
                .{ .name = "rpm_txn_config", .module = rpmzig_txn_config_mod },
            },
        });
        const lib = b.addLibrary(.{
            .name = "rpmzhistory",
            .linkage = .static,
            .root_module = mod,
        });
        break :blk lib;
    };

    const history_zig_lib = history_lib;

    // ----- rpmzig (native RPM implementation) ----- //

    const rpmzig_lib = blk: {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/rpmdb.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
                .{ .name = "confined_sqlite", .module = sqlite_confined_api_mod },
            },
        });
        mod.addImport("rpm_header", rpmzig_header_mod);
        mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        mod.addImport("rpm_file_handle", rpmzig_file_handle_mod);
        configureLuaScriptletSupport(b, mod, zlua_mod);
        const lib = b.addLibrary(.{
            .name = "rpmzrpmzig",
            .linkage = .static,
            .root_module = mod,
        });
        break :blk lib;
    };

    const transaction_plan_native_test_step = b.step(
        "transaction-plan-native-test",
        "Run native solver transaction plan capture tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/transaction_plan_native.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport(
            "transaction_plan_capture_abi",
            transaction_plan_capture_abi_mod,
        );
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addImport("repomd", repomd_mod);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        transaction_plan_native_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    // `repomd/query_native.zig` is deliberately excluded from `repomd/root.zig`'s
    // test aggregation (it needs the client allocators at link time), so its unit
    // tests need a root of their own or they never run.
    const query_native_test_step = b.step(
        "query-native-test",
        "Run native repoquery/exclude line builder tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/query_native.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("xml", xml_mod);
        test_mod.addImport("content_digest", content_digest_mod);
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addImport("tdnf_internal_abi", internal_abi_mod);
        test_mod.addImport("sqlite", sqlite_dep.module("sqlite"));
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        test_mod.addIncludePath(b.path("rpmzig"));
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        query_native_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_download_mod = b.createModule(.{
        .root_source_file = b.path("client/download/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
        .imports = &.{
            .{ .name = "client_abi", .module = client_abi_mod },
            .{ .name = "tls", .module = tls_dep.module("tls") },
            .{ .name = "rpmz_error", .module = rpmz_error_mod },
        },
    });

    const client_repoutils_test_step = b.step(
        "client-repoutils-test",
        "Run client repository utility production tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/repoutils.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
        test_mod.addImport("rpmz_common", common_api_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addIncludePath(b.path("client"));
        test_mod.addIncludePath(b.path("rpmzig"));
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_repoutils_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_utils_test_step = b.step(
        "client-utils-test",
        "Run client utility production tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/utils.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("rpmz_common", common_api_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        test_mod.addIncludePath(b.path("client"));
        test_mod.addIncludePath(b.path("rpmzig"));
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_utils_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_remoterepo_test_step = b.step(
        "client-remoterepo-test",
        "Run client remote repository production tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/remoterepo.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "client_abi", .module = client_abi_mod },
                .{ .name = "client_download", .module = client_download_mod },
                .{ .name = "rpmz_common", .module = common_api_mod },
                .{ .name = "rpmz_error", .module = rpmz_error_mod },
                .{ .name = "uri_sanitize", .module = uri_sanitize_mod },
                .{ .name = "rpm_txn_config", .module = rpmzig_txn_config_mod },
            },
        });
        test_mod.addIncludePath(b.path("client"));
        test_mod.addIncludePath(b.path("rpmzig"));
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_remoterepo_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const transaction_plan_integration_test_step = b.step(
        "transaction-plan-integration-test",
        "Run authoritative stored transaction plan integration tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(
                "client/transaction_plan_integration.zig",
            ),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport(
            "transaction_plan_capture_abi",
            transaction_plan_capture_abi_mod,
        );
        test_mod.addImport(
            "transaction_plan_capture",
            transaction_plan_capture_test_mod,
        );
        test_mod.addImport(
            "transaction_plan_native",
            transaction_plan_native_mod,
        );
        test_mod.addImport(
            "transaction_plan_repository",
            transaction_plan_repository_integration_mod,
        );
        test_mod.addImport("repository_metadata", repomd_mod);
        test_mod.addImport("transaction_plan", transaction_plan_mod);
        test_mod.addImport(
            "transaction_plan_request_trace",
            transaction_plan_request_trace_mod,
        );
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
        test_mod.addImport("rpmz_common", common_api_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        const test_options = b.addOptions();
        test_options.addOption(bool, "standalone_test", true);
        test_mod.addOptions(
            "transaction_plan_integration_options",
            test_options,
        );
        const tests = b.addTest(.{
            .root_module = test_mod,
        });
        tests.root_module.linkLibrary(common_lib);
        tests.root_module.linkLibrary(llconf_lib);
        tests.root_module.linkLibrary(rpmzig_lib);
        const run_tests = b.addRunArtifact(tests);
        transaction_plan_integration_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("common/common.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addIncludePath(b.path("common"));
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addImport("tdnf_internal_abi", internal_abi_mod);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const common_test_step = b.step(
            "common-test",
            "Run common Zig unit tests",
        );
        common_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("llconf/llconf.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addIncludePath(b.path("llconf"));
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    // `zig build test` runs the rpmzig Zig unit tests (path-building,
    // txn-config resolution, plus the pure-Zig parser/verifier submodules).
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/rpmdb.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
                .{ .name = "confined_sqlite", .module = sqlite_confined_api_mod },
            },
        });
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpm_file_handle", rpmzig_file_handle_mod);
        configureLuaScriptletSupport(b, test_mod, zlua_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("tools/cli/lib/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addIncludePath(b.path("llconf"));
        test_mod.addIncludePath(b.path("tools/cli"));
        test_mod.addIncludePath(b.path("tools/cli/lib"));
        test_mod.addImport("jsondump_abi", jsondump_abi_mod);
        test_mod.addImport("rpmz_common", common_api_mod);
        test_mod.addImport("tdnf_internal_abi", internal_abi_mod);
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(jsondump_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/config.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("client_config_options", client_config_options.createModule());
        test_mod.addImport("client_varsdir", client_varsdir_mod);
        test_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
        test_mod.addImport("rpmtrans_flags", rpmtrans_flags_mod);
        test_mod.addImport("rpmz_common", common_api_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        run_tests.argv.items.len = 1;
        run_tests.stdio = .inherit;
        const client_config_test_step = b.step(
            "client-config-test",
            "Run client configuration tests",
        );
        client_config_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/excludes.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("rpmz_common", common_api_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const client_excludes_test_step = b.step(
            "client-excludes-test",
            "Run package exclusion collection tests",
        );
        client_excludes_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/varsdir.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.linkLibrary(llconf_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("tools/config/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addIncludePath(b.path("."));
        test_mod.addImport("jsondump_abi", jsondump_abi_mod);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(jsondump_lib);
        linkSystem(test_mod, &.{"dl"});
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    // Smoke-test the vendored zig-sqlite dependency in isolation.
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("history/sqlite_smoke_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            },
        });
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{ .root_module = sqlite_confined_mod });
        const run_tests = b.addRunArtifact(tests);
        const step = b.step(
            "sqlite-confined-test",
            "Run confined SQLite VFS tests",
        );
        step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_download_test_step = b.step(
        "client-download-test",
        "Run Zig HTTP/TLS transport tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/download/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "client_abi", .module = client_abi_mod },
                .{ .name = "tls", .module = tls_dep.module("tls") },
                .{ .name = "rpmz_error", .module = rpmz_error_mod },
            },
        });
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_download_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    // Build and exercise the Zig history backend unit tests.
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("history/history_zig_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
                .{ .name = "confined_sqlite", .module = sqlite_confined_api_mod },
                .{ .name = "rpm_txn_config", .module = rpmzig_txn_config_mod },
            },
        });
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const history_zig_test_step = b.step(
            "history-zig-test",
            "Run standalone Zig history backend unit tests",
        );
        history_zig_test_step.dependOn(&history_zig_lib.step);
        history_zig_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&history_zig_lib.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    var read_tool_install_steps: [4]*std.Build.Step = undefined;

    // rpmz-rpmdb-count: smoke-test exe for the native rpmdb reader.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/count_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpmdb", rpmzig_lib.root_module);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpmdb-count",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
        read_tool_install_steps[0] = &install.step;
    }

    // rpmz-rpmdb-list: smoke-test exe for the rpmzig iterator.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/list_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpmdb", rpmzig_lib.root_module);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpmdb-list",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
        read_tool_install_steps[1] = &install.step;
    }

    // rpmz-rpm-info: smoke-test exe for the rpmzig `.rpm` file parser.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/info_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpm-info",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
        read_tool_install_steps[2] = &install.step;
    }

    var key_tool_install_steps: [3]*std.Build.Step = undefined;

    // rpmz-rpmdb-pubkeys: smoke-test exe for the rpmdb gpg-pubkey
    // iterator. Lists every rpm-imported public key.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/pubkeys_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpmdb", rpmzig_lib.root_module);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpmdb-pubkeys",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
        key_tool_install_steps[0] = &install.step;
    }

    // rpmz-rpmdb-import-pubkeys: smoke-test exe for atomic native
    // OpenPGP certificate import.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/pubkey_import_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpmdb", rpmzig_lib.root_module);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpmdb-import-pubkeys",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
        key_tool_install_steps[1] = &install.step;
    }

    // rpmz-rpmdb-write: smoke-test exe for the native sqlite rpmdb
    // write path.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/write_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpmdb", rpmzig_lib.root_module);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpmdb-write",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
        key_tool_install_steps[2] = &install.step;
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/key_tools_cli_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        run_tests.setEnvironmentVariable(
            "TDNF_RPMDB_PUBKEYS_TEST_BINARY",
            b.getInstallPath(
                .{ .custom = "libexec/rpmz" },
                "rpmz-rpmdb-pubkeys",
            ),
        );
        run_tests.setEnvironmentVariable(
            "TDNF_RPMDB_IMPORT_PUBKEYS_TEST_BINARY",
            b.getInstallPath(
                .{ .custom = "libexec/rpmz" },
                "rpmz-rpmdb-import-pubkeys",
            ),
        );
        run_tests.setEnvironmentVariable(
            "TDNF_RPMDB_WRITE_TEST_BINARY",
            b.getInstallPath(
                .{ .custom = "libexec/rpmz" },
                "rpmz-rpmdb-write",
            ),
        );
        run_tests.setEnvironmentVariable(
            "TDNF_RPMDB_KEY_FIXTURE",
            "rpmzig/pgp/testdata/microsoft-rpm-key.asc",
        );
        run_tests.setCwd(b.path("."));
        for (&key_tool_install_steps) |install_step| {
            run_tests.step.dependOn(install_step);
        }
        const key_tools_test_step = b.step(
            "rpmzig-key-tools-test",
            "Run rpmzig key tool CLI tests",
        );
        key_tools_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    // rpmz-rpm-files: smoke-test exe for the cpio walker + payload
    // decompressor.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/files_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpm_cpio", rpmzig_cpio_mod);
        mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpm-files",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
        read_tool_install_steps[3] = &install.step;
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/read_tools_cli_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const cpio_tests = b.addTest(.{ .root_module = rpmzig_cpio_mod });
        const run_cpio_tests = b.addRunArtifact(cpio_tests);
        inline for (
            .{
                "rpmz-rpmdb-count",
                "rpmz-rpmdb-list",
                "rpmz-rpm-info",
                "rpmz-rpm-files",
            },
            .{
                "TDNF_RPMDB_COUNT_TEST_BINARY",
                "TDNF_RPMDB_LIST_TEST_BINARY",
                "TDNF_RPM_INFO_TEST_BINARY",
                "TDNF_RPM_FILES_TEST_BINARY",
            },
        ) |binary, environment_name| {
            run_tests.setEnvironmentVariable(
                environment_name,
                b.getInstallPath(.{ .custom = "libexec/rpmz" }, binary),
            );
        }
        for (&read_tool_install_steps) |install_step| {
            run_tests.step.dependOn(install_step);
        }
        const read_tools_test_step = b.step(
            "rpmzig-read-tools-test",
            "Run rpmzig read-tool CLI tests",
        );
        read_tools_test_step.dependOn(&run_tests.step);
        read_tools_test_step.dependOn(&run_cpio_tests.step);
        zig_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_cpio_tests.step);
    }

    // rpmz-rpm-install: smoke-test exe for the native file-install
    // engine.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/install_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpm_header", rpmzig_header_mod);
        mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpm-install",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
    }

    // rpmz-rpm-scriptlet: smoke-test exe for the native
    // scriptlet executor.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/scriptlet_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpm_header", rpmzig_header_mod);
        mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        configureLuaScriptletSupport(b, mod, zlua_mod);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpm-scriptlet",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
    }

    // rpmz-rpm-trigger: smoke-test exe for the native trigger
    // executor.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/trigger_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
                .{ .name = "confined_sqlite", .module = sqlite_confined_api_mod },
            },
        });
        mod.addImport("rpm_header", rpmzig_header_mod);
        mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        configureLuaScriptletSupport(b, mod, zlua_mod);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpm-trigger",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
    }

    // rpmz-rpm-erase: smoke-test exe for the native file-erase
    // engine.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/erase_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
                .{ .name = "confined_sqlite", .module = sqlite_confined_api_mod },
            },
        });
        mod.addImport("rpm_header", rpmzig_header_mod);
        mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpm-erase",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);
    }

    // rpmz-rpm-verify: smoke-test exe for the pure-Zig signature
    // verifier. Builds the same in-memory --key / --rpmdb keyring
    // path the client uses.
    {
        const mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/verify_main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        });
        mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        mod.addImport("rpmdb", rpmzig_lib.root_module);
        const exe = b.addExecutable(.{
            .name = "rpmz-rpm-verify",
            .root_module = mod,
        });
        hardenExe(exe);
        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
        });
        b.getInstallStep().dependOn(&install.step);

        const verify_tests = b.addTest(.{
            .root_module = rpmzig_verify_mod,
        });
        const run_verify_tests = b.addRunArtifact(verify_tests);
        const cli_test_mod = b.createModule(.{
            .root_source_file = b.path("rpmzig/verify_cli_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        const cli_tests = b.addTest(.{ .root_module = cli_test_mod });
        const run_cli_tests = b.addRunArtifact(cli_tests);
        run_cli_tests.setEnvironmentVariable(
            "TDNF_RPM_VERIFY_TEST_BINARY",
            b.getInstallPath(
                .{ .custom = "libexec/rpmz" },
                "rpmz-rpm-verify",
            ),
        );
        run_cli_tests.step.dependOn(&install.step);
        const verifier_tools_test_step = b.step(
            "rpmzig-verifier-tools-test",
            "Run rpmzig verifier bridge and CLI tests",
        );
        verifier_tools_test_step.dependOn(&run_verify_tests.step);
        verifier_tools_test_step.dependOn(&run_cli_tests.step);
        zig_test_step.dependOn(&run_verify_tests.step);
        zig_test_step.dependOn(&run_cli_tests.step);
    }

    const builtin_plugins_mod = b.createModule(.{
        .root_source_file = b.path("plugins/builtin.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    builtin_plugins_mod.addImport("metalink_xml", metalink_xml_mod);
    builtin_plugins_mod.addImport("plugin_metadata", plugin_metadata_mod);
    builtin_plugins_mod.addIncludePath(b.path("client"));
    builtin_plugins_mod.addIncludePath(b.path("llconf"));
    builtin_plugins_mod.addIncludePath(b.path("rpmzig"));
    builtin_plugins_mod.addCMacro("TDNF_CLIENT_LIBSOLV_IN_SCOPE", "1");

    // ----- client implementation module ----- //

    const client_plugins_mod = b.createModule(.{
        .root_source_file = b.path("client/plugins.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    client_plugins_mod.addImport("client_abi", client_abi_mod);
    client_plugins_mod.addImport("rpmz_common", common_api_mod);
    client_plugins_mod.addImport("rpmz_error", rpmz_error_mod);
    client_plugins_mod.addImport("builtin_plugins", builtin_plugins_mod);
    client_plugins_mod.addImport("plugin_metadata", plugin_metadata_mod);
    client_plugins_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);

    const client_history_mod = b.createModule(.{
        .root_source_file = b.path("client/history.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    client_history_mod.addImport("client_abi", client_abi_mod);
    client_history_mod.addImport("rpmz_error", rpmz_error_mod);

    const client_updateinfo_mod = b.createModule(.{
        .root_source_file = b.path("client/updateinfo_exports.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    client_updateinfo_mod.addImport("rpmz_error", rpmz_error_mod);
    client_updateinfo_mod.addImport("client_abi", client_abi_mod);
    client_updateinfo_mod.addIncludePath(b.path("client"));
    client_updateinfo_mod.addIncludePath(b.path("rpmzig"));

    const client_init_mod = b.createModule(.{
        .root_source_file = b.path("client/init.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    client_init_mod.addImport(
        "transaction_plan_capture_abi",
        transaction_plan_capture_abi_mod,
    );
    client_init_mod.addImport("client_init_abi", client_abi_mod);
    client_init_mod.addImport("rpmz_common", common_api_mod);
    client_init_mod.addImport("rpmz_error", rpmz_error_mod);

    const transaction_lock_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction_lock.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    transaction_lock_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
    transaction_lock_mod.linkLibrary(common_lib);
    transaction_lock_mod.linkLibrary(llconf_lib);
    transaction_lock_mod.linkLibrary(rpmzig_lib);

    const client_mod = b.createModule(.{
        .root_source_file = b.path("client/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    const client_transaction_options = b.addOptions();
    client_transaction_options.addOption(bool, "export_entry_points", true);
    client_mod.addImport(
        "client_transaction_options",
        client_transaction_options.createModule(),
    );
    client_mod.addImport(
        "transaction_plan_capture",
        transaction_plan_capture_test_mod,
    );
    client_mod.addImport(
        "transaction_plan_capture_abi",
        transaction_plan_capture_abi_mod,
    );
    client_mod.addImport(
        "transaction_plan_integration",
        transaction_plan_integration_mod,
    );
    client_mod.addImport("transaction_plan", transaction_plan_mod);
    client_mod.addImport("transaction_bundle", transaction_bundle_mod);
    client_mod.addImport(
        "transaction_plan_execution",
        transaction_plan_execution_mod,
    );
    client_mod.addImport("uri_sanitize", uri_sanitize_mod);
    client_mod.addImport("verified_fetch", verified_fetch_mod);
    client_mod.addImport("bundle_paths", bundle_paths_mod);
    client_mod.addImport("atomic_publish", atomic_publish_mod);
    client_mod.addImport("bundle_reader", bundle_reader_mod);
    client_mod.addImport("bundle_selection", bundle_selection_mod);
    client_mod.addImport("bundle_writer", bundle_writer_mod);
    client_mod.addImport("client_init", client_init_mod);
    client_mod.addImport("repomd_client_exports", repomd_mod);
    client_mod.addImport("builtin_plugins", builtin_plugins_mod);
    client_mod.addImport("client_plugins", client_plugins_mod);
    client_mod.addImport("plugin_metadata", plugin_metadata_mod);
    client_mod.addImport("client_history", client_history_mod);
    client_mod.addImport("client_abi", client_abi_mod);
    client_mod.addImport("client_download", client_download_mod);
    client_mod.addImport("client_config_options", client_config_options.createModule());
    client_mod.addImport("client_varsdir", client_varsdir_mod);
    client_mod.addImport("rpmtrans_flags", rpmtrans_flags_mod);
    client_mod.addImport("rpm_header", rpmzig_header_mod);
    client_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
    client_mod.addImport("transaction_lock", transaction_lock_mod);
    client_mod.addImport("canonical_json", canonical_json_mod);
    client_mod.addImport("content_digest", content_digest_mod);
    client_mod.addImport("rpm_evr", rpm_evr_mod);
    client_mod.addImport("rpmz_common", common_api_mod);
    client_mod.addImport("rpmz_error", rpmz_error_mod);
    client_mod.addImport("client_updateinfo", client_updateinfo_mod);
    client_mod.addImport("rpm_gpgcheck", rpmzig_gpgcheck_mod);
    const client_gpgcheck_options = b.addOptions();
    client_gpgcheck_options.addOption(bool, "test_mode", false);
    client_mod.addImport(
        "client_gpgcheck_options",
        client_gpgcheck_options.createModule(),
    );
    client_mod.addIncludePath(b.path("client"));
    client_mod.addIncludePath(b.path("rpmzig"));
    // The native target may expose host headers, so this production build
    // declares only that the confinement negative control is not armed.
    client_mod.addCMacro("TDNF_CLIENT_LIBSOLV_IN_SCOPE", "1");
    client_mod.linkLibrary(common_lib);
    client_mod.linkLibrary(history_lib);
    client_mod.linkLibrary(llconf_lib);
    client_mod.linkLibrary(rpmzig_lib);

    // `client/root.zig` is the whole private implementation; only the
    // `resolver` namespace it re-exports is public. Registering the module
    // under a name `rpmz.zig` narrows keeps the consumer from compiling the
    // graph twice.
    public_rpmz_mod.addImport("client_root", client_mod);

    // Everything past this point is the product build: artifacts, test steps,
    // audits, and packaging. A dependency consumer needs none of it.
    if (!root_build) return;

    const transaction_rpm_package_test_mod = b.createModule(.{
        .root_source_file = b.path("repomd/rpmpkg.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    transaction_rpm_package_test_mod.addImport("rpm_header", rpmzig_header_mod);
    transaction_rpm_package_test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);

    const transaction_test_mod = b.createModule(.{
        .root_source_file = b.path("client/transaction.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    transaction_test_mod.addImport("client_abi", client_abi_mod);
    const client_transaction_test_options = b.addOptions();
    client_transaction_test_options.addOption(bool, "export_entry_points", false);
    transaction_test_mod.addImport(
        "client_transaction_options",
        client_transaction_test_options.createModule(),
    );
    transaction_test_mod.addImport("rpmtrans_flags", rpmtrans_flags_mod);
    transaction_test_mod.addImport("rpm_header", rpmzig_header_mod);
    transaction_test_mod.addImport("rpm_evr", rpm_evr_mod);
    transaction_test_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
    transaction_test_mod.addImport("transaction_lock", transaction_lock_mod);
    transaction_test_mod.addImport(
        "rpm_package_test",
        transaction_rpm_package_test_mod,
    );
    transaction_test_mod.addImport("rpmz_common", common_api_mod);
    transaction_test_mod.addImport("rpmz_error", rpmz_error_mod);
    transaction_test_mod.addIncludePath(b.path("client"));
    transaction_test_mod.addIncludePath(b.path("rpmzig"));
    transaction_test_mod.linkLibrary(common_lib);
    transaction_test_mod.linkLibrary(llconf_lib);
    transaction_test_mod.linkLibrary(rpmzig_lib);
    const transaction_tests = b.addTest(.{ .root_module = transaction_test_mod });
    const run_transaction_tests = b.addRunArtifact(transaction_tests);
    const transaction_test_step = b.step(
        "client-transaction-test",
        "Run client native transaction tests",
    );
    transaction_test_step.dependOn(&run_transaction_tests.step);
    zig_test_step.dependOn(&run_transaction_tests.step);

    const replay_test_mod = b.createModule(.{
        .root_source_file = b.path("client/replay.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    replay_test_mod.addImport("client_abi", client_abi_mod);
    replay_test_mod.addImport(
        "client_transaction_options",
        client_transaction_test_options.createModule(),
    );
    replay_test_mod.addImport("bundle_reader", bundle_reader_mod);
    replay_test_mod.addImport("bundle_selection", bundle_selection_mod);
    replay_test_mod.addImport("canonical_json", canonical_json_mod);
    replay_test_mod.addImport("content_digest", content_digest_mod);
    replay_test_mod.addImport("repomd_client_exports", repomd_mod);
    replay_test_mod.addImport("rpm_gpgcheck", rpmzig_gpgcheck_mod);
    replay_test_mod.addImport("rpm_header", rpmzig_header_mod);
    replay_test_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
    replay_test_mod.addImport("transaction_lock", transaction_lock_mod);
    replay_test_mod.addImport("rpmtrans_flags", rpmtrans_flags_mod);
    replay_test_mod.addImport("rpm_evr", rpm_evr_mod);
    const replay_rpm_package_test_mod = b.createModule(.{
        .root_source_file = b.path("client/replay_rpm_package_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    replay_rpm_package_test_mod.addImport(
        "repomd_client_exports",
        repomd_mod,
    );
    replay_test_mod.addImport(
        "rpm_package_test",
        replay_rpm_package_test_mod,
    );
    replay_test_mod.addImport("rpmz_common", common_api_mod);
    replay_test_mod.addImport("rpmz_error", rpmz_error_mod);
    replay_test_mod.addImport("transaction_bundle", transaction_bundle_mod);
    replay_test_mod.addImport("transaction_plan", transaction_plan_mod);
    replay_test_mod.addImport("verified_fetch", verified_fetch_mod);
    replay_test_mod.addIncludePath(b.path("client"));
    replay_test_mod.addIncludePath(b.path("rpmzig"));
    replay_test_mod.linkLibrary(common_lib);
    replay_test_mod.linkLibrary(llconf_lib);
    replay_test_mod.linkLibrary(rpmzig_lib);
    const replay_tests = b.addTest(.{ .root_module = replay_test_mod });
    const run_replay_tests = b.addRunArtifact(replay_tests);
    const replay_test_step = b.step(
        "client-replay-test",
        "Run offline replay preflight and result tests",
    );
    replay_test_step.dependOn(&run_replay_tests.step);
    zig_test_step.dependOn(&run_replay_tests.step);

    const transaction_lock_tests = b.addTest(.{
        .root_module = transaction_lock_mod,
    });
    const run_transaction_lock_tests = b.addRunArtifact(
        transaction_lock_tests,
    );
    const transaction_lock_test_step = b.step(
        "client-transaction-lock-test",
        "Run shared transaction target lock tests",
    );
    transaction_lock_test_step.dependOn(&run_transaction_lock_tests.step);
    zig_test_step.dependOn(&run_transaction_lock_tests.step);

    const client_repositories_test_step = b.step(
        "client-repositories-test",
        "Run direct repository management production tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/repositories_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_root", client_mod);
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        const tests = b.addTest(.{
            .name = "client-repositories-integration-test",
            .root_module = test_mod,
        });
        const run_tests = b.addRunArtifact(tests);
        client_repositories_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const tests = b.addTest(.{
            .name = "client-repositories-production-test",
            .root_module = client_mod,
            .filters = &.{"repositories production:"},
        });
        const run_tests = b.addRunArtifact(tests);
        client_repositories_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_resolver_test_step = b.step(
        "client-resolver-test",
        "Run public resolver input validation and resolve tests",
    );
    {
        const tests = b.addTest(.{
            .name = "client-resolver-validation-test",
            .root_module = client_mod,
            .filters = &.{"resolver:"},
        });
        const run_tests = b.addRunArtifact(tests);
        client_resolver_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/resolver_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_root", client_mod);
        const tests = b.addTest(.{
            .name = "client-resolver-test",
            .root_module = test_mod,
        });
        const run_tests = b.addRunArtifact(tests);
        run_tests.has_side_effects = true;
        client_resolver_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const bundle_export_test_step = b.step(
        "bundle-export-test",
        "Run transaction-bundle export acceptance tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/bundle_export_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_root", client_mod);
        test_mod.addImport("bundle_reader", bundle_reader_mod);
        test_mod.addImport("transaction_bundle", transaction_bundle_mod);
        test_mod.addImport("transaction_plan", transaction_plan_mod);
        test_mod.addImport("repository_metadata", repomd_mod);
        const tests = b.addTest(.{
            .name = "bundle-export-test",
            .root_module = test_mod,
        });
        const run_tests = b.addRunArtifact(tests);
        run_tests.has_side_effects = true;
        bundle_export_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_gpgcheck_test_step = b.step(
        "client-gpgcheck-test",
        "Run direct client package-signature policy tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/gpgcheck.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("rpmz_common", common_api_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addImport("rpm_gpgcheck", rpmzig_gpgcheck_mod);
        test_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
        test_mod.addImport("transaction_lock", transaction_lock_mod);
        const test_options = b.addOptions();
        test_options.addOption(bool, "test_mode", true);
        test_mod.addImport(
            "client_gpgcheck_options",
            test_options.createModule(),
        );
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        run_tests.argv.items.len = 1;
        run_tests.stdio = .inherit;
        client_gpgcheck_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    // client/ has no C translation units left. Keep that a hard invariant
    // in the include audit while continuing to reject libsolv spellings
    // outside the one pinned test-only oracle module.
    const libsolv_confinement_step = b.step(
        "libsolv-confinement-audit",
        "Reject client C sources and unconfined libsolv headers",
    );
    // The -I pin is attached per module by addLibsolvIncludes, so a file
    // in a module that never calls it can still spell <solv/pool.h> and
    // resolve it from /usr/include with no version assert in scope --
    // exactly the bug the pin exists to prevent, reachable everywhere
    // outside the oracle module. Nothing in the build graph can catch
    // that, because such a file compiles cleanly; only the spelling
    // gives it away.
    const run_libsolv_include_audit = b.addSystemCommand(
        &.{ "python3", "scripts/libsolv-include-audit.py" },
    );
    run_libsolv_include_audit.setCwd(b.path("."));
    libsolv_confinement_step.dependOn(&run_libsolv_include_audit.step);

    const run_libsolv_artifact_audit = b.addSystemCommand(
        &.{
            "python3",
            "scripts/libsolv-artifact-audit.py",
            b.getInstallPath(.prefix, ""),
        },
    );
    run_libsolv_artifact_audit.setCwd(b.path("."));
    run_libsolv_artifact_audit.step.dependOn(b.getInstallStep());
    libsolv_confinement_step.dependOn(&run_libsolv_artifact_audit.step);

    const client_history_test_step = b.step(
        "client-history-test",
        "Run private client history context tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/history_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_history", client_history_mod);
        test_mod.addImport("client_root", client_mod);
        test_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_history_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_api_test_step = b.step(
        "client-api-test",
        "Run migrated public API ownership and behavior tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/api_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_root", client_mod);
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_api_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_package_query_test_step = b.step(
        "client-package-query-test",
        "Run direct production package/query conversion tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/package_query_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_root", client_mod);
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("repository_metadata", repomd_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_package_query_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_plugins_test_step = b.step(
        "client-plugins-test",
        "Run private production built-in plugin dispatcher tests",
    );
    {
        const test_backend_mod = b.createModule(.{
            .root_source_file = b.path("client/plugins_test_backend.zig"),
            .target = target,
            .optimize = optimize,
        });
        test_backend_mod.addImport("plugin_metadata", plugin_metadata_mod);
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/plugins.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_abi", client_abi_mod);
        test_mod.addImport("rpmz_common", common_api_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addImport("builtin_plugins", test_backend_mod);
        test_mod.addImport("plugin_metadata", plugin_metadata_mod);
        test_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        test_mod.linkLibrary(rpmzig_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        run_tests.argv.items.len = 1;
        run_tests.stdio = .inherit;
        client_plugins_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const transaction_plan_handle_test_step = b.step(
        "transaction-plan-handle-test",
        "Run private production handle transaction plan integration test",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(
                "client/transaction_plan_handle_test.zig",
            ),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_root", client_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        transaction_plan_handle_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    const client_init_test_step = b.step(
        "client-init-test",
        "Run private production client refresh-input tests",
    );
    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/init_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_root", client_mod);
        test_mod.addImport(
            "transaction_plan_capture_abi",
            transaction_plan_capture_abi_mod,
        );
        test_mod.addImport("client_init_abi", client_abi_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_init_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("client/updateinfo_export_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("client_root", client_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        client_updateinfo_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    // ----- CLI implementation module ----- //

    const cli_mod = b.createModule(.{
        .root_source_file = b.path("tools/cli/lib/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    cli_mod.addIncludePath(b.path("llconf"));
    cli_mod.addIncludePath(b.path("tools/cli"));
    cli_mod.addIncludePath(b.path("tools/cli/lib"));
    cli_mod.addImport("jsondump_abi", jsondump_abi_mod);
    cli_mod.addImport("rpmz_common", common_api_mod);
    cli_mod.addImport("tdnf_internal_abi", internal_abi_mod);
    cli_mod.linkLibrary(jsondump_lib);

    // ----- executables ----- //

    // rpmz
    const rpmz_mod = b.createModule(.{
        .root_source_file = b.path("tools/cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    rpmz_mod.addIncludePath(b.path("tools/cli"));
    rpmz_mod.addImport("jsondump_abi", jsondump_abi_mod);
    rpmz_mod.addImport("rpmz_common", common_api_mod);
    rpmz_mod.addImport("tdnf_internal_abi", internal_abi_mod);
    rpmz_mod.addImport("rpmz_client", client_mod);
    rpmz_mod.addImport("rpmz_cli", cli_mod);
    rpmz_mod.addImport("rpmz", public_rpmz_mod);
    rpmz_mod.linkLibrary(jsondump_lib);
    const rpmz_exe = b.addExecutable(.{
        .name = "rpmz",
        .root_module = rpmz_mod,
    });
    hardenExe(rpmz_exe);
    b.installArtifact(rpmz_exe);

    {
        const plan_cli_test_mod = b.createModule(.{
            .root_source_file = b.path("tools/cli/plan_cli_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        plan_cli_test_mod.addImport("client_root", client_mod);
        const plan_cli_tests = b.addTest(.{ .root_module = plan_cli_test_mod });
        const run_plan_cli_tests = b.addRunArtifact(plan_cli_tests);
        run_plan_cli_tests.setEnvironmentVariable(
            "RPMZ_CLI_TEST_PREFIX",
            b.getInstallPath(.prefix, ""),
        );
        run_plan_cli_tests.step.dependOn(b.getInstallStep());
        run_plan_cli_tests.has_side_effects = true;
        zig_test_step.dependOn(&run_plan_cli_tests.step);
    }

    const replay_cli_test_step = b.step(
        "replay-cli-test",
        "Run binary-level offline replay CLI tests",
    );
    {
        const replay_cli_test_mod = b.createModule(.{
            .root_source_file = b.path("tools/cli/replay_cli_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        replay_cli_test_mod.addImport("rpmz", public_rpmz_mod);
        const replay_cli_tests = b.addTest(.{
            .root_module = replay_cli_test_mod,
        });
        const run_replay_cli_tests = b.addRunArtifact(replay_cli_tests);
        run_replay_cli_tests.setEnvironmentVariable(
            "RPMZ_CLI_TEST_PREFIX",
            b.getInstallPath(.prefix, ""),
        );
        run_replay_cli_tests.step.dependOn(b.getInstallStep());
        run_replay_cli_tests.has_side_effects = true;
        replay_cli_test_step.dependOn(&run_replay_cli_tests.step);
        zig_test_step.dependOn(&run_replay_cli_tests.step);
    }

    // rpmz-config
    const rpmz_config_mod = b.createModule(.{
        .root_source_file = b.path("tools/config/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    rpmz_config_mod.addIncludePath(b.path("."));
    rpmz_config_mod.addImport("jsondump_abi", jsondump_abi_mod);
    rpmz_config_mod.linkLibrary(llconf_lib);
    rpmz_config_mod.linkLibrary(jsondump_lib);
    linkSystem(rpmz_config_mod, &.{"dl"});
    const rpmz_config_exe = b.addExecutable(.{
        .name = "rpmz-config",
        .root_module = rpmz_config_mod,
    });
    hardenExe(rpmz_config_exe);
    b.installArtifact(rpmz_config_exe);

    // rpmz-history-util links the vendored-SQLite history and rpmzig libs.
    const history_util_options = b.addOptions();
    history_util_options.addOption([]const u8, "db_dir", history_db_dir);
    const history_util_mod = b.createModule(.{
        .root_source_file = b.path("history/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    history_util_mod.addImport("history", history_lib.root_module);
    history_util_mod.addImport(
        "history_config",
        history_util_options.createModule(),
    );
    history_util_mod.addImport("rpm_txn_config", rpmzig_txn_config_mod);
    history_util_mod.addImport("transaction_lock", transaction_lock_mod);
    history_util_mod.linkLibrary(rpmzig_lib);
    const history_util_exe = b.addExecutable(.{
        .name = "rpmz-history-util",
        .root_module = history_util_mod,
    });
    hardenExe(history_util_exe);
    const install_history_util = b.addInstallArtifact(history_util_exe, .{
        .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
    });
    b.getInstallStep().dependOn(&install_history_util.step);

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("history/main_cli_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        run_tests.setEnvironmentVariable(
            "TDNF_HISTORY_UTIL_TEST_BINARY",
            b.getInstallPath(
                .{ .custom = "libexec/rpmz" },
                "rpmz-history-util",
            ),
        );
        run_tests.step.dependOn(&install_history_util.step);
        const history_util_test_step = b.step(
            "history-util-test",
            "Run rpmz-history-util CLI tests",
        );
        history_util_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    // jsondumptest
    const jsondump_test_mod = b.createModule(.{
        .root_source_file = b.path("jsondump/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    jsondump_test_mod.addImport("jsondump", jsondump_lib.root_module);
    const jsondump_test_exe = b.addExecutable(.{
        .name = "jsondumptest",
        .root_module = jsondump_test_mod,
    });
    hardenExe(jsondump_test_exe);
    b.installArtifact(jsondump_test_exe);
    {
        const tests = b.addTest(.{ .root_module = jsondump_test_mod });
        const run_tests = b.addRunArtifact(tests);
        const jsondump_test_step = b.step(
            "jsondump-test",
            "Run jsondump unit tests",
        );
        jsondump_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const tests = b.addTest(.{ .root_module = xml_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/available_loader.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("xml", xml_mod);
        test_mod.addImport("content_digest", content_digest_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/cmdline_repository.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            },
        });
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/directory_repository.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            },
        });
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/installed_repository.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            },
        });
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const installed_loader_test_step = b.step(
            "installed-loader-test",
            "Run the standalone installed repository loader tests",
        );
        installed_loader_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/package_context.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            },
        });
        test_mod.addImport("xml", xml_mod);
        test_mod.addImport("content_digest", content_digest_mod);
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        test_mod.addImport("tdnf_internal_abi", internal_abi_mod);
        test_mod.linkLibrary(common_lib);
        test_mod.linkLibrary(llconf_lib);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const package_context_test_step = b.step(
            "package-context-test",
            "Run native package context lifetime and stable handle tests",
        );
        package_context_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/solver_identity.zig"),
            .target = target,
            .optimize = optimize,
        });
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const identity_test_step = b.step(
            "solver-identity-test",
            "Run stable native solver package identity tests",
        );
        identity_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/solver_visibility.zig"),
            .target = target,
            .optimize = optimize,
        });
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const visibility_test_step = b.step(
            "solver-visibility-test",
            "Run native solver visibility projection tests",
        );
        visibility_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/solver_native.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const native_solve_test_step = b.step(
            "native-solve-test",
            "Run reusable native solver entry point tests",
        );
        native_solve_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/solver_live.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            },
        });
        test_mod.addImport("xml", xml_mod);
        test_mod.addImport("content_digest", content_digest_mod);
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        const live_solve_test_step = b.step(
            "live-solve-test",
            "Run strict native live-input solve tests",
        );
        live_solve_test_step.dependOn(&run_tests.step);
        zig_test_step.dependOn(&run_tests.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            },
        });
        test_mod.addImport("xml", xml_mod);
        test_mod.addImport("content_digest", content_digest_mod);
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        test_mod.addImport("rpmz_error", rpmz_error_mod);
        test_mod.addImport("tdnf_internal_abi", internal_abi_mod);
        test_mod.addIncludePath(b.path("rpmzig"));
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    const oracle_test_step = b.step(
        "libsolv-oracle-test",
        "Run the opt-in canonical libsolv solver oracle tests",
    );
    if (enable_libsolv_oracle) {
        // libsolv's C sources intentionally rely on wraparound in a few
        // internal hash paths; match packaged libsolv's release behaviour.
        const libsolv_dep_optional = b.lazyDependency("libsolv", .{
            .target = target,
            .optimize = OptimizeMode.ReleaseFast,
            .ext = true,
            .zlib = false,
        });
        if (libsolv_dep_optional == null) return;
        const libsolv_dep = libsolv_dep_optional.?;
        const libsolv = libsolv_dep.artifact("solv");
        const libsolvext = libsolv_dep.artifact("solvext");
        const libsolv_includes = LibsolvIncludes.init(
            b,
            libsolv,
            libsolvext,
        );
        const test_mod = b.createModule(.{
            .root_source_file = b.path("repomd/solver_oracle_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite_dep.module("sqlite") },
            },
        });
        test_mod.addImport("xml", xml_mod);
        test_mod.addImport("content_digest", content_digest_mod);
        test_mod.addImport("rpm_header", rpmzig_header_mod);
        test_mod.addImport("rpm_pkgfile", rpmzig_pkgfile_mod);
        test_mod.addImport("rpmdb_test", rpmzig_rpmdb_test_mod);
        test_mod.addImport("tdnf_internal_abi", internal_abi_mod);
        test_mod.addIncludePath(b.path("rpmzig"));
        addLibsolvIncludes(
            test_mod,
            libsolv_includes,
        );
        test_mod.addObjectFile(libsolv.getEmittedBin());
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        oracle_test_step.dependOn(&run_tests.step);
    } else {
        const disabled = b.addSystemCommand(&.{
            "sh",
            "-c",
            "echo 'error: libsolv oracle disabled; rerun with -Dlibsolv-oracle=true' >&2; exit 1",
        });
        oracle_test_step.dependOn(&disabled.step);
    }

    {
        const test_mod = b.createModule(.{
            .root_source_file = b.path("plugins/metalink/xml.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        test_mod.addImport("xml", xml_mod);
        test_mod.addImport("content_digest", content_digest_mod);
        const tests = b.addTest(.{ .root_module = test_mod });
        const run_tests = b.addRunArtifact(tests);
        zig_test_step.dependOn(&run_tests.step);
    }

    const install_automatic = b.addInstallFileWithDir(
        b.path("bin/rpmz-automatic"),
        .bin,
        "rpmz-automatic",
    );
    b.getInstallStep().dependOn(&install_automatic.step);
    const chmod_automatic = b.addSystemCommand(&.{ "chmod", "+x", b.getInstallPath(.bin, "rpmz-automatic") });
    chmod_automatic.step.dependOn(&install_automatic.step);
    b.getInstallStep().dependOn(&chmod_automatic.step);

    // ----- static config files ----- //

    const rpmz_conf_dir: Build.InstallDir = .{ .custom = b.fmt("{s}/rpmz", .{sysconf_dir}) };
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path("etc/rpmz/rpmz.conf"), rpmz_conf_dir, "rpmz.conf").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path("etc/rpmz/automatic.conf"), rpmz_conf_dir, "automatic.conf").step);

    const pluginconf_dir: Build.InstallDir = .{ .custom = b.fmt("{s}/rpmz/pluginconf.d", .{sysconf_dir}) };
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path("etc/rpmz/pluginconf.d/rpmzmetalink.conf"), pluginconf_dir, "rpmzmetalink.conf").step);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path("etc/rpmz/pluginconf.d/rpmzrepogpgcheck.conf"), pluginconf_dir, "rpmzrepogpgcheck.conf").step);

    const systemd_install_dir: Build.InstallDir = .{ .custom = systemd_dir };
    for ([_][]const u8{
        "rpmz-automatic.service",
        "rpmz-automatic.timer",
        "rpmz-automatic-notifyonly.service",
        "rpmz-automatic-notifyonly.timer",
        "rpmz-automatic-install.service",
        "rpmz-automatic-install.timer",
    }) |fname| {
        b.getInstallStep().dependOn(
            &b.addInstallFileWithDir(b.path(b.fmt("etc/systemd/{s}", .{fname})), systemd_install_dir, fname).step,
        );
    }

    const motd_install_dir: Build.InstallDir = .{ .custom = motdgen_dir };
    b.getInstallStep().dependOn(
        &b.addInstallFileWithDir(b.path("etc/motdgen.d/02-rpmz-updateinfo.sh"), motd_install_dir, "02-rpmz-updateinfo.sh").step,
    );

    const completion_dir: Build.InstallDir = .{ .custom = "share/bash-completion/completions" };
    b.getInstallStep().dependOn(
        &b.addInstallFileWithDir(b.path("etc/bash_completion.d/rpmz-completion.bash"), completion_dir, "rpmz").step,
    );

    // pytests/config.json is written directly into the source tree by
    // writeTemplate() above writes this into the source tree; no install step
    // is needed because it is not an installable artifact.

    // ----- check + lint steps ----- //

    const check_step = b.step("check", "Run pytest integration tests");
    const pytest_support_mod = b.createModule(.{
        .root_source_file = b.path("pytests/test_support.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    pytest_support_mod.addImport("client", client_mod);
    pytest_support_mod.addImport("repomd", repomd_mod);
    pytest_support_mod.addImport("tdnf_internal_abi", internal_abi_mod);
    pytest_support_mod.linkLibrary(common_lib);
    pytest_support_mod.linkLibrary(llconf_lib);
    pytest_support_mod.linkLibrary(rpmzig_lib);
    const pytest_support_exe = b.addExecutable(.{
        .name = "rpmz-test-support",
        .root_module = pytest_support_mod,
    });
    zig_test_step.dependOn(&pytest_support_exe.step);
    const install_pytest_support = b.addInstallArtifact(pytest_support_exe, .{
        .dest_dir = .{ .override = .{ .custom = "libexec/rpmz" } },
    });
    b.getInstallStep().dependOn(&install_pytest_support.step);
    const pytest_support_step = b.step(
        "pytest-support",
        "Install the private pytest support executable",
    );
    pytest_support_step.dependOn(&install_pytest_support.step);
    const run_pytest = b.addSystemCommand(&.{ "python3", "-m", "pytest", "-v" });
    run_pytest.setCwd(b.path("pytests"));
    run_pytest.step.dependOn(b.getInstallStep());
    run_pytest.step.dependOn(&install_pytest_support.step);
    run_pytest.step.dependOn(&run_replay_acceptance_export.step);
    check_step.dependOn(&run_pytest.step);

    // The Zig integration suite. It drives the same installed binaries as
    // `check`, but each test owns an install root instead of sharing the
    // host's, so it neither mutates the machine it runs on nor has to run
    // serially. It reuses the RPM fixtures `pytests/repo/setup-repo.sh`
    // generates. The preflight fails loudly when those fixtures or root
    // privileges are absent so an all-skipped suite is never reported as
    // success.
    const ztest_step = b.step(
        "ztest",
        "Run Zig integration tests against the installed tree",
    );
    {
        const ztest_prefix = b.getInstallPath(.prefix, "");
        const ztest_preflight_script =
            \\prefix=$1
            \\repo_script=$2
            \\repo_src=$3
            \\status=0
            \\
            \\if [ "$(id -u)" -ne 0 ]; then
            \\  echo "error: ztest must run as root (package file ownership checks require uid 0)." >&2
            \\  echo 'help: re-run with: sudo -E env "PATH=$PATH" zig build ztest --prefix ./out --summary all' >&2
            \\  status=1
            \\fi
            \\
            \\rpmz="$prefix/bin/rpmz"
            \\if [ ! -x "$rpmz" ]; then
            \\  echo "error: ztest binary missing: $rpmz" >&2
            \\  echo "help: build it first with: zig build install --prefix \"$prefix\"" >&2
            \\  echo 'help: for the documented ztest layout, use: zig build install --prefix ./out' >&2
            \\  status=1
            \\fi
            \\
            \\seed="$prefix/repo/photon-test/repodata/repomd.xml"
            \\if [ ! -f "$seed" ]; then
            \\  echo "error: ztest repo seed missing: $seed" >&2
            \\  echo "help: generate it with: bash \"$repo_script\" \"$prefix/repo\" \"$repo_src\"" >&2
            \\  echo 'help: for the documented ztest layout, generate ./out/repo and run ztest with --prefix ./out' >&2
            \\  status=1
            \\fi
            \\
            \\if [ "$status" -ne 0 ]; then
            \\  echo "error: ztest preflight failed; refusing to report an all-skipped suite as passing." >&2
            \\  exit "$status"
            \\fi
        ;
        const run_ztest_preflight = b.addSystemCommand(&.{
            "bash",
            "-eu",
            "-c",
            ztest_preflight_script,
            "ztest-preflight",
            ztest_prefix,
            b.pathJoin(&.{ b.build_root.path.?, "pytests/repo/setup-repo.sh" }),
            b.pathJoin(&.{ b.build_root.path.?, "pytests/repo" }),
        });
        run_ztest_preflight.setCwd(b.path("."));

        const ztest_install_rpmz = b.addInstallArtifact(rpmz_exe, .{});
        ztest_install_rpmz.step.dependOn(&run_ztest_preflight.step);

        const ztest_mod = b.createModule(.{
            .root_source_file = b.path("ztests/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const ztests = b.addTest(.{ .root_module = ztest_mod });
        const run_ztests = b.addRunArtifact(ztests);
        run_ztests.setEnvironmentVariable(
            "TDNF_ZTEST_PREFIX",
            ztest_prefix,
        );
        run_ztests.setEnvironmentVariable(
            "TDNF_ZTEST_PLUGIN_DIR",
            b.getInstallPath(.{ .custom = plugin_dir_rel }, ""),
        );
        run_ztests.step.dependOn(&ztest_install_rpmz.step);
        run_ztests.has_side_effects = true;
        ztest_step.dependOn(&run_ztests.step);

        const plugin_ztest_step = b.step(
            "plugin-ztest",
            "Run focused built-in plugin Zig integration tests",
        );
        const plugin_ztest_mod = b.createModule(.{
            .root_source_file = b.path("ztests/plugin_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const plugin_ztests = b.addTest(.{
            .root_module = plugin_ztest_mod,
            .filters = &.{"plugin contract:"},
        });
        const run_plugin_ztests = b.addRunArtifact(plugin_ztests);
        run_plugin_ztests.setEnvironmentVariable(
            "TDNF_ZTEST_PREFIX",
            ztest_prefix,
        );
        run_plugin_ztests.setEnvironmentVariable(
            "TDNF_ZTEST_PLUGIN_DIR",
            b.getInstallPath(.{ .custom = plugin_dir_rel }, ""),
        );
        run_plugin_ztests.step.dependOn(&ztest_install_rpmz.step);
        run_plugin_ztests.has_side_effects = true;
        plugin_ztest_step.dependOn(&run_plugin_ztests.step);
    }

    const lint_step = b.step("lint", "Run flake8 on pytests/");
    const run_flake8 = b.addSystemCommand(&.{ "flake8", "pytests" });
    run_flake8.setCwd(b.path("."));
    lint_step.dependOn(&run_flake8.step);
    const run_source_dependency_audit = b.addSystemCommand(
        &.{ "python3", "scripts/librpm-audit.py" },
    );
    run_source_dependency_audit.setCwd(b.path("."));
    lint_step.dependOn(&run_source_dependency_audit.step);
}

// -------------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------------

const StaticLibOpts = struct {
    name: []const u8,
    root: []const u8,
    files: []const []const u8,
};

fn staticLib(
    b: *Build,
    target: ResolvedTarget,
    optimize: OptimizeMode,
    opts: StaticLibOpts,
) *Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    mod.addIncludePath(b.path(opts.root));
    mod.addCSourceFiles(.{
        .root = b.path(opts.root),
        .files = opts.files,
        .flags = &rpmz_cflags,
    });
    return b.addLibrary(.{
        .name = opts.name,
        .linkage = .static,
        .root_module = mod,
    });
}

fn linkSystem(mod: *Build.Module, names: []const []const u8) void {
    for (names) |n| mod.linkSystemLibrary(n, .{});
}

const LibsolvIncludes = struct {
    /// Emitted tree; supplies <solv/*.h>.
    core: LazyPath,
    /// The same tree's solv/ subdir. Derived in init() rather than set by
    /// the caller: as a third field it could be pointed at a different
    /// tree, or at the core root, with no diagnostic. Nothing spells a
    /// flat include today, and nothing should: --system-header-prefix
    /// matches the written spelling, so <pool.h> gets no system
    /// exemption and brings back the 18 -Wextra -Werror failures in
    /// libsolv's own headers.
    flat: LazyPath,
    /// libsolvext's tree; supplies <solv/{solv_xfopen,testcase,tools_util}.h>.
    ext: LazyPath,

    fn init(
        b: *Build,
        libsolv: *Build.Step.Compile,
        libsolvext: *Build.Step.Compile,
    ) LibsolvIncludes {
        const core = libsolv.getEmittedIncludeTree();
        return .{
            .core = core,
            .flat = core.path(b, "solv"),
            .ext = libsolvext.getEmittedIncludeTree(),
        };
    }
};

fn addLibsolvIncludes(mod: *Build.Module, trees: LibsolvIncludes) void {
    // -I, not -isystem: zig cc searches /usr/include *before* user
    // -isystem directories, so with -isystem a host libsolv-devel wins
    // and the build compiles against the host's headers while linking the
    // vendored .a. rpmz_cflags carries --system-header-prefix=solv/ to
    // keep libsolv's own warnings suppressed, and both the C and Zig
    // sides assert on TDNF_VENDORED_LIBSOLV_VERSION_PATCH below so a
    // regression here fails the build instead of passing quietly.
    //
    // Known boundary -- read this before trusting the asserts. They
    // detect "the vendored tree is not on the include path at all". They
    // are NOT a per-header leakage detector, and cannot be made into one:
    // libsolv's headers are guard-macro protected, so once any vendored
    // header has been included, a host header that wins a later lookup
    // has its own #include "pool.h" skipped by the already-defined guard.
    // LIBSOLV_VERSION_PATCH stays 39 and the asserts stay silent while
    // host declarations are in scope. Only a host header included
    // *before* every vendored one trips them.
    //
    // This matters because -I pins a header only if the vendored tree
    // emits a file of that name. The pinned set is 31: the fork installs
    // libsolv's public set from src/CMakeLists.txt (27 + generated
    // solvversion.h) plus libsolvext's 3. A distro libsolv-devel also
    // ships feature headers such as repo_rpmdb.h and pool_fileconflicts.h
    // that the fork does not build, and spelling one would resolve
    // against /usr/include silently. If the translation unit calls one of
    // the functions such a header declares, the link then fails on the
    // missing symbol; macro-, enum- or typedef-only use (RPM_ADD_*,
    // FINDFILECONFLICTS_*) produces no diagnostic anywhere. Nothing in
    // the tree spells one today. Do not add such an include without
    // first making the fork emit the header.
    mod.addIncludePath(trees.core);
    mod.addIncludePath(trees.flat);
    // The ext tree goes to every consumer, not just the ones that spell
    // an ext header today. It is <dir>/solv/{solv_xfopen,testcase,
    // tools_util}.h, so omitting it did not merely leave those three
    // unavailable -- it left them resolvable from /usr/include/solv, and
    // a host testcase.h then drags in the whole host core set through
    // includer-relative quoted lookup, without -I ordering ever being
    // consulted.
    mod.addIncludePath(trees.ext);
    mod.addCMacro(
        "TDNF_VENDORED_LIBSOLV_VERSION_PATCH",
        vendored_libsolv_version_patch,
    );
}

fn configureLuaScriptletSupport(
    b: *Build,
    mod: *Build.Module,
    zlua_mod: *Build.Module,
) void {
    mod.addIncludePath(b.path("rpmzig"));
    mod.addImport("zlua", zlua_mod);
}

fn hardenExe(exe: *Build.Step.Compile) void {
    exe.pie = true;
    // link_z_relro is true by default in 0.16; -z now is not directly
    // exposed by the Compile step API, so it relies on the linker default.
    exe.link_z_relro = true;
}

const TemplateVar = struct {
    key: []const u8,
    value: []const u8,
};

/// Reads a `*.in` file from `<repo>/<in_rel>`, substitutes each `@KEY@`
/// (cmake-style `@VAR@`) and `#cmakedefine FOO …` directive, and writes the
/// result to `<repo>/<out_rel>`. Output files are gitignored.
///
/// This is configure-time generation and runs every time `build.zig` is
/// evaluated. It is used only for source-tree runtime fixtures and scripts.
fn writeTemplate(
    b: *Build,
    in_rel: []const u8,
    out_rel: []const u8,
    vars: []const TemplateVar,
) void {
    const io = b.graph.io;
    const root = b.build_root.handle;
    const in_bytes = root.readFileAlloc(io, in_rel, b.allocator, .limited(2 * 1024 * 1024)) catch |err|
        std.debug.panic("unable to read template '{s}': {t}", .{ in_rel, err });
    defer b.allocator.free(in_bytes);

    var out: std.array_list.Managed(u8) = .init(b.allocator);
    defer out.deinit();

    var line_it = std.mem.splitScalar(u8, in_bytes, '\n');
    var first = true;
    while (line_it.next()) |line| {
        if (!first) out.append('\n') catch @panic("OOM");
        first = false;
        renderTemplateLine(&out, line, vars);
    }

    root.writeFile(io, .{ .sub_path = out_rel, .data = out.items }) catch |err|
        std.debug.panic("unable to write generated file '{s}': {t}", .{ out_rel, err });
}

fn writeTemplateExecutable(
    b: *Build,
    in_rel: []const u8,
    out_rel: []const u8,
    vars: []const TemplateVar,
) void {
    writeTemplate(b, in_rel, out_rel, vars);
    b.build_root.handle.setFilePermissions(
        b.graph.io,
        out_rel,
        .executable_file,
        .{},
    ) catch |err|
        std.debug.panic(
            "unable to mark generated file '{s}' executable: {t}",
            .{ out_rel, err },
        );
}

fn renderTemplateLine(
    out: *std.array_list.Managed(u8),
    line: []const u8,
    vars: []const TemplateVar,
) void {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    const prefix = "#cmakedefine";
    if (std.mem.startsWith(u8, trimmed, prefix) and
        (trimmed.len == prefix.len or trimmed[prefix.len] == ' ' or trimmed[prefix.len] == '\t'))
    {
        const rest = std.mem.trim(u8, trimmed[prefix.len..], " \t");
        var name_end: usize = 0;
        while (name_end < rest.len and !std.ascii.isWhitespace(rest[name_end])) : (name_end += 1) {}
        const name = rest[0..name_end];
        const value_template = std.mem.trim(u8, rest[name_end..], " \t");

        const value = lookup(name, vars);
        if (value) |_| {
            if (value_template.len == 0) {
                appendFmt(out, "#define {s}", .{name});
            } else {
                var expanded: std.array_list.Managed(u8) = .init(out.allocator);
                defer expanded.deinit();
                substituteAtAt(&expanded, value_template, vars);
                appendFmt(out, "#define {s} {s}", .{ name, expanded.items });
            }
        } else {
            appendFmt(out, "/* #undef {s} */", .{name});
        }
        return;
    }
    substituteAtAt(out, line, vars);
}

fn appendFmt(out: *std.array_list.Managed(u8), comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.allocPrint(out.allocator, fmt, args) catch @panic("OOM");
    defer out.allocator.free(s);
    out.appendSlice(s) catch @panic("OOM");
}

fn substituteAtAt(out: *std.array_list.Managed(u8), text: []const u8, vars: []const TemplateVar) void {
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '@') {
            if (std.mem.indexOfScalarPos(u8, text, i + 1, '@')) |end| {
                const key = text[i + 1 .. end];
                if (isValidKey(key)) {
                    if (lookup(key, vars)) |v| {
                        out.appendSlice(v) catch @panic("OOM");
                        i = end + 1;
                        continue;
                    }
                }
            }
        }
        out.append(text[i]) catch @panic("OOM");
        i += 1;
    }
}

fn isValidKey(key: []const u8) bool {
    if (key.len == 0) return false;
    for (key) |c| {
        switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9', '_' => {},
            else => return false,
        }
    }
    return true;
}

fn lookup(key: []const u8, vars: []const TemplateVar) ?[]const u8 {
    for (vars) |v| if (std.mem.eql(u8, v.key, key)) return v.value;
    return null;
}
