//! `tdnf plan` acceptance against the real fixture repository.
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
