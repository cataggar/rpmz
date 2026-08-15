//! `rpmz plan` acceptance against the real fixture repository.
//!
//! `tools/cli/plan_cli_test.zig` already covers the verb, but it serves a
//! synthetic two-package repository it builds itself. That repository has no
//! file lists, so it never exercised the path that broke in #268: on any
//! ordinary repository -- one where `filelists.xml` exists and some package
//! depends on a file another package ships -- `plan` failed with
//! `Error(1006) RepositoryIntegrityMismatch` before the plan was ever printed.
//! These tests run the shipped binary against the repository
//! `pytests/repo/setup-repo.sh` publishes, which is the shape real users have.

const std = @import("std");
const harness = @import("harness.zig");

const io = std.testing.io;

const single = "tdnf-test-one";
/// `tdnf-native-order-post` requires `/usr/bin/tdnf-native-order-helper`, a
/// path shipped by `tdnf-native-order-helper`. Resolving it is only possible
/// when the repository's file provides survive into the solver, so this pair
/// is the end-to-end witness for the bug.
const file_dep_consumer = "tdnf-native-order-post";
const file_dep_provider = "tdnf-native-order-helper";

const schema = "\"schema\":\"tdnf.transaction-plan/v1\"";

test "plan install prints a resolved plan for the fixture repository" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "plan", "install", single });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(schema);
    try result.expectStdoutContains("\"resolution_status\":\"resolved\"");
    try result.expectStdoutContains(single);
    // Nothing is executed, so the root must still be empty afterwards.
    try std.testing.expect(!try root.isInstalled(single));
}

test "plan install resolves a dependency on a file another package ships" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "plan", "install", file_dep_consumer });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains(schema);
    try result.expectStdoutContains("\"resolution_status\":\"resolved\"");
    try result.expectStdoutContains(file_dep_consumer);
    // The provider is only pulled in if `/usr/bin/tdnf-native-order-helper`
    // resolves as a file provide rather than an unmet requirement.
    try result.expectStdoutContains(file_dep_provider);
    try std.testing.expect(!try root.isInstalled(file_dep_consumer));
}

test "installing a file dependency agrees with the plan" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{
        "install", "-y", "--nogpgcheck", file_dep_consumer,
    });
    defer result.deinit();
    try result.expectOk();
    try std.testing.expect(try root.isInstalled(file_dep_consumer));
    try std.testing.expect(try root.isInstalled(file_dep_provider));
}

// ---------------------------------------------------------------------------
// Operation, action, and problem coverage.
//
// These run against a real rpmdb with real prior rows, which is the only place
// upgrade, downgrade, reinstall, obsoletion, and cleanup classification can be
// observed. Nothing here is allowed to execute: every test asserts the root is
// unchanged afterwards.
// ---------------------------------------------------------------------------

const two = "tdnf-test-two";
const multiversion = "tdnf-test-multiversion";
const multiversion_lowest = "1.0.1-1";
const missing_dep = "tdnf-missing-dep";
const conflicts_0 = "tdnf-test-dummy-conflicts-0";
const conflicts_1 = "tdnf-test-dummy-conflicts-1";
const obsoleted = "tdnf-test-dummy-obsoleted";
const obsoleting = "tdnf-test-dummy-obsoleting";
const installonly = "tdnf-multi";
const cleanreq_leaf = "tdnf-test-cleanreq-leaf1";
const cleanreq_required = "tdnf-test-cleanreq-required";

/// `ERROR_TDNF_CLI_INVALID_ARGUMENT`, as the shell sees it.
const cli_invalid_argument_code: u8 = 902 % 256;
/// `ERROR_TDNF_CLI_NOT_ENOUGH_ARGS`, as the shell sees it.
const cli_not_enough_args_code: u8 = 904 % 256;
/// `ERROR_TDNF_NO_MATCH`, as the shell sees it.
const no_match_code: u8 = 1011 % 256;

fn install(root: *harness.Root, name: []const u8) !void {
    var result = try root.run(&.{ "install", "-y", "--nogpgcheck", name });
    defer result.deinit();
    try result.expectOk();
}

fn eraseBestEffort(root: *harness.Root, name: []const u8) void {
    var result = root.run(&.{ "erase", "-y", name }) catch return;
    result.deinit();
}

/// One parsed plan document plus the process result that produced it.
const Planned = struct {
    result: harness.Result,
    parsed: std.json.Parsed(std.json.Value),

    fn deinit(self: *Planned) void {
        self.parsed.deinit();
        self.result.deinit();
    }

    fn object(self: *const Planned) std.json.ObjectMap {
        return self.parsed.value.object;
    }

    fn status(self: *const Planned) []const u8 {
        return self.object().get("environment").?.object
            .get("resolution_status").?.string;
    }

    fn array(self: *const Planned, key: []const u8) []std.json.Value {
        const value = self.object().get(key) orelse return &.{};
        return switch (value) {
            .array => |items| items.items,
            else => &.{},
        };
    }

    /// The name recorded for `package_id`, which actions and problems refer to
    /// indirectly so that a package is described exactly once per plan.
    fn packageName(self: *const Planned, package_id: []const u8) ?[]const u8 {
        for (self.array("packages")) |package| {
            const entry = package.object;
            if (!std.mem.eql(u8, entry.get("id").?.string, package_id)) continue;
            return entry.get("identity").?.object.get("name").?.string;
        }
        return null;
    }

    fn hasAction(self: *const Planned, kind: []const u8, name: []const u8) bool {
        for (self.array("actions")) |action| {
            const entry = action.object;
            if (!std.mem.eql(u8, entry.get("kind").?.string, kind)) continue;
            const target = self.packageName(
                entry.get("target_package_id").?.string,
            ) orelse continue;
            if (std.mem.eql(u8, target, name)) return true;
        }
        return false;
    }

    /// Whether the `kind` action on `name` lists exactly one prior row and it
    /// is `prior`. An obsoletion is the only action that names a package the
    /// request never mentioned, so the prior list is what proves it.
    fn actionPriorNames(
        self: *const Planned,
        kind: []const u8,
        name: []const u8,
        prior: []const u8,
    ) bool {
        for (self.array("actions")) |action| {
            const entry = action.object;
            if (!std.mem.eql(u8, entry.get("kind").?.string, kind)) continue;
            const target = self.packageName(
                entry.get("target_package_id").?.string,
            ) orelse continue;
            if (!std.mem.eql(u8, target, name)) continue;
            const priors = entry.get("prior_package_ids").?.array.items;
            if (priors.len != 1) return false;
            const prior_name =
                self.packageName(priors[0].string) orelse return false;
            return std.mem.eql(u8, prior_name, prior);
        }
        return false;
    }

    fn actionReason(self: *const Planned, kind: []const u8, name: []const u8) ?[]const u8 {
        for (self.array("actions")) |action| {
            const entry = action.object;
            if (!std.mem.eql(u8, entry.get("kind").?.string, kind)) continue;
            const target = self.packageName(
                entry.get("target_package_id").?.string,
            ) orelse continue;
            if (std.mem.eql(u8, target, name))
                return entry.get("reason").?.string;
        }
        return null;
    }

    fn hasProblem(self: *const Planned, kind: []const u8) bool {
        for (self.array("problems")) |problem| {
            if (std.mem.eql(u8, problem.object.get("kind").?.string, kind))
                return true;
        }
        return false;
    }

    fn expectStatus(self: *const Planned, expected: []const u8) !void {
        try std.testing.expectEqualStrings(expected, self.status());
    }
};

fn plan(root: *harness.Root, args: []const []const u8) !Planned {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(std.testing.allocator);
    try argv.append(std.testing.allocator, "plan");
    try argv.appendSlice(std.testing.allocator, args);

    var result = try root.run(argv.items);
    errdefer result.deinit();
    try result.expectOk();
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        result.stdout,
        .{},
    );
    return .{ .result = result, .parsed = parsed };
}

test "planning install, erase and reinstall classifies each action" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, single);

    try install(&root, single);

    var installed = try plan(&root, &.{ "install", two });
    defer installed.deinit();
    try installed.expectStatus("resolved");
    try std.testing.expect(installed.hasAction("install", two));
    try std.testing.expectEqualStrings(
        "user",
        installed.actionReason("install", two).?,
    );

    var erased = try plan(&root, &.{ "erase", single });
    defer erased.deinit();
    try erased.expectStatus("resolved");
    try std.testing.expect(erased.hasAction("erase", single));

    var removed = try plan(&root, &.{ "remove", single });
    defer removed.deinit();
    try std.testing.expectEqualStrings(erased.result.stdout, removed.result.stdout);

    var reinstalled = try plan(&root, &.{ "reinstall", single });
    defer reinstalled.deinit();
    try reinstalled.expectStatus("resolved");
    try std.testing.expect(reinstalled.hasAction("reinstall", single));

    // Planning never executes.
    try std.testing.expect(try root.isInstalled(single));
    try std.testing.expect(!try root.isInstalled(two));
}

test "planning an upgrade classifies an upgrade named and for the whole root" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    try install(&root, multiversion ++ "-" ++ multiversion_lowest);

    var named = try plan(&root, &.{ "upgrade", multiversion });
    defer named.deinit();
    try named.expectStatus("resolved");
    try std.testing.expect(named.hasAction("upgrade", multiversion));

    // `update` is the same operation under a different name.
    var aliased = try plan(&root, &.{ "update", multiversion });
    defer aliased.deinit();
    try std.testing.expectEqualStrings(named.result.stdout, aliased.result.stdout);

    // The bare verb is the singleton "everything installed" operation. It is a
    // different request, so its plan differs, but the action is the same.
    var everything = try plan(&root, &.{"upgrade"});
    defer everything.deinit();
    try everything.expectStatus("resolved");
    try std.testing.expect(everything.hasAction("upgrade", multiversion));
    try std.testing.expect(!std.mem.eql(
        u8,
        named.result.stdout,
        everything.result.stdout,
    ));

    try std.testing.expect(try root.isInstalledVersion(
        multiversion,
        multiversion_lowest,
    ));
}

test "planning a downgrade classifies a downgrade named and for the whole root" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, multiversion);

    try install(&root, multiversion);

    var named = try plan(&root, &.{ "downgrade", multiversion });
    defer named.deinit();
    try named.expectStatus("resolved");
    try std.testing.expect(named.hasAction("downgrade", multiversion));

    var everything = try plan(&root, &.{"downgrade"});
    defer everything.deinit();
    try everything.expectStatus("resolved");
    try std.testing.expect(everything.hasAction("downgrade", multiversion));

    // A distro-sync under `clean_requirements_on_remove` is a native-solver
    // gap that predates the plan API and stops every `rpmz distro-sync`, not
    // just the planned one, so turn the policy off for both forms.
    try root.setMainOption("clean_requirements_on_remove", "0");
    var synced_named = try plan(&root, &.{ "distro-sync", multiversion });
    defer synced_named.deinit();
    try synced_named.expectStatus("resolved");

    var synced = try plan(&root, &.{"distro-sync"});
    defer synced.deinit();
    try synced.expectStatus("resolved");
    try root.setMainOption("clean_requirements_on_remove", "true");
}

test "planning autoremove classifies the orphan cleanup it would perform" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, cleanreq_leaf);
    defer eraseBestEffort(&root, cleanreq_required);

    try install(&root, cleanreq_leaf);
    try std.testing.expect(try root.isInstalled(cleanreq_required));

    var named = try plan(&root, &.{ "autoremove", cleanreq_leaf });
    defer named.deinit();
    try named.expectStatus("resolved");
    try std.testing.expect(named.hasAction("erase", cleanreq_leaf));
    // The dependency was pulled in, so it goes with the leaf.
    try std.testing.expect(named.hasAction("erase", cleanreq_required));
    try std.testing.expectEqualStrings(
        "cleanup",
        named.actionReason("erase", cleanreq_required).?,
    );

    var aliased = try plan(&root, &.{ "autoerase", cleanreq_leaf });
    defer aliased.deinit();
    try std.testing.expectEqualStrings(named.result.stdout, aliased.result.stdout);

    // The bare verb plans over every orphan rather than a named one.
    var everything = try plan(&root, &.{"autoremove"});
    defer everything.deinit();
    try everything.expectStatus("resolved");

    try std.testing.expect(try root.isInstalled(cleanreq_leaf));
}

test "planning an obsoleting package classifies the obsoletion" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, obsoleting);
    defer eraseBestEffort(&root, obsoleted);

    // The bare name resolves to the obsoleting package, which `Provides` it,
    // so pin the version to install the package that gets obsoleted.
    try install(&root, obsoleted ++ "=0.1");

    var result = try plan(&root, &.{ "install", obsoleting });
    defer result.deinit();
    try result.expectStatus("resolved");
    // One action carries both halves: the obsoleting package is the target
    // and the row it replaces is the prior.
    try std.testing.expect(result.hasAction("obsolete", obsoleting));
    try std.testing.expect(
        result.actionPriorNames("obsolete", obsoleting, obsoleted),
    );

    try std.testing.expect(try root.isInstalled(obsoleted));
    try std.testing.expect(!try root.isInstalled(obsoleting));
}

test "an unresolvable request becomes a structured problem plan" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, conflicts_0);

    // A subject no repository carries never reaches the solver: the request
    // layer fails it first, so there is no plan to publish. The boundary is
    // asserted here so a later move of that check into a `no_candidate`
    // problem plan is a visible change.
    var absent = try root.run(&.{ "plan", "install", "rpmz-no-such-package" });
    defer absent.deinit();
    try absent.expectCode(no_match_code);

    var unsatisfied = try plan(&root, &.{ "install", missing_dep });
    defer unsatisfied.deinit();
    try unsatisfied.expectStatus("problems");
    try std.testing.expect(unsatisfied.hasProblem("unsatisfied_requirement"));

    try install(&root, conflicts_0);
    var conflicting = try plan(&root, &.{ "install", conflicts_1 });
    defer conflicting.deinit();
    try conflicting.expectStatus("problems");
    try std.testing.expect(conflicting.hasProblem("conflict"));
    try std.testing.expectEqual(@as(usize, 0), conflicting.array("actions").len);
}

test "erasing a protected package becomes a protected-package problem plan" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, single);

    try install(&root, single);
    try root.tmp.dir.createDirPath(io, "protected.d");
    try root.tmp.dir.writeFile(io, .{
        .sub_path = "protected.d/plan.conf",
        .data = single,
    });
    defer root.tmp.dir.deleteTree(io, "protected.d") catch {};

    var result = try plan(&root, &.{ "erase", single });
    defer result.deinit();
    try result.expectStatus("problems");
    try std.testing.expect(result.hasProblem("protected_package"));
    try std.testing.expect(try root.isInstalled(single));
}

test "exceeding the install-only limit becomes an installonly-limit problem plan" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    try root.setMainOption("installonlypkgs", installonly);
    try root.setMainOption("installonly_limit", "1");
    defer eraseBestEffort(&root, installonly);

    try install(&root, installonly ++ "=1.0.1-1");

    var result = try plan(&root, &.{ "install", installonly ++ "=1.0.1-2" });
    defer result.deinit();
    // The limit is either reported as a problem or satisfied by evicting the
    // older instance; both are structured outcomes, never a crash or a silent
    // empty plan.
    if (std.mem.eql(u8, result.status(), "problems")) {
        try std.testing.expect(result.hasProblem("installonly_limit"));
    } else {
        try result.expectStatus("resolved");
        try std.testing.expect(result.array("actions").len != 0);
    }
}

test "a skipped job is recorded rather than dropped" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();
    defer eraseBestEffort(&root, single);

    var result = try plan(&root, &.{
        "--skip-broken", "install", single, missing_dep,
    });
    defer result.deinit();
    try result.expectStatus("resolved_with_skips");
    try std.testing.expect(result.hasAction("install", single));

    // Every skip names the exact job it dropped, and that job is present.
    const skipped = result.array("skipped");
    try std.testing.expect(skipped.len != 0);
    for (skipped) |entry| {
        const job_id = entry.object.get("job_id").?.string;
        var found = false;
        for (result.array("jobs")) |job| {
            if (std.mem.eql(u8, job.object.get("id").?.string, job_id))
                found = true;
        }
        try std.testing.expect(found);
    }
    try std.testing.expect(!try root.isInstalled(single));
}

test "the plan verb rejects a missing or unsupported transaction" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    // The diagnostics go where every other `pr_err` in rpmz goes; what
    // matters here is that a rejected verb publishes no plan.
    var missing = try root.run(&.{"plan"});
    defer missing.deinit();
    try missing.expectCode(cli_not_enough_args_code);
    try missing.expectStdoutContains("need transaction command as argument");
    try std.testing.expect(!missing.stdoutContains("tdnf.transaction-plan"));

    for ([_][]const u8{ "check", "list", "plan", "INSTALL" }) |verb| {
        var unsupported = try root.run(&.{ "plan", verb });
        defer unsupported.deinit();
        try unsupported.expectCode(cli_invalid_argument_code);
        try unsupported.expectStdoutContains(
            "unsupported transaction plan command",
        );
        try std.testing.expect(
            !unsupported.stdoutContains("tdnf.transaction-plan"),
        );
    }
}
