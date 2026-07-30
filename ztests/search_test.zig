//! Search command behaviour, ported from `pytests/tests/test_search.py`.

const std = @import("std");
const harness = @import("harness.zig");

/// `ERROR_TDNF_NO_SEARCH_RESULTS`, as the shell sees it.
const no_search_results_code: u8 = 1599 % 256;

test "search with no argument reports no results" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{"search"});
    defer result.deinit();
    try result.expectCode(no_search_results_code);
}

test "search of an unknown term reports no results" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "search", "invalid_arg" });
    defer result.deinit();
    try result.expectCode(no_search_results_code);
}

test "search finds fixture packages" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "search", "tdnf" });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains("tdnf-test-one");
}

test "search accepts multiple terms" {
    var h = try harness.open(std.testing.allocator);
    defer h.deinit();
    var root = try h.root();
    defer root.deinit();

    var result = try root.run(&.{ "search", "tdnf", "wget", "gzip" });
    defer result.deinit();
    try result.expectOk();
    try result.expectStdoutContains("tdnf-test-one");
}
