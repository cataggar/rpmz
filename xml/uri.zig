//! URI-reference resolution used by XML Base and repository locations.
//!
//! The resolver intentionally keeps URI components byte-for-byte intact apart
//! from the dot-segment removal required by RFC 3986 section 5.2.4. It also
//! works when the document has only a relative base, which is common for
//! repodata cached without the repository's original URL.

const std = @import("std");

pub const Error = error{
    InvalidUri,
    OutOfMemory,
};

const Reference = struct {
    scheme: ?[]const u8 = null,
    has_authority: bool = false,
    authority: []const u8 = "",
    path: []const u8 = "",
    query: ?[]const u8 = null,
    fragment: ?[]const u8 = null,
};

const NormalizedPath = struct {
    allocation: []u8,
    path: []const u8,
};

/// Resolve `reference` against `base` according to RFC 3986 section 5.
///
/// A null base is the empty URI reference. This is useful for XML documents
/// whose external document URI is deliberately not retained by the parser.
pub fn resolve(
    allocator: std.mem.Allocator,
    base: ?[]const u8,
    reference: []const u8,
) Error![]const u8 {
    const base_ref = if (base) |value|
        try parseReference(value)
    else
        Reference{};
    const reference_ref = try parseReference(reference);

    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();

    var normalized_path: ?NormalizedPath = null;
    defer if (normalized_path) |value| allocator.free(value.allocation);
    var merged_path: ?[]u8 = null;
    defer if (merged_path) |value| allocator.free(value);

    var scheme: ?[]const u8 = null;
    var has_authority = false;
    var authority: []const u8 = "";
    var path: []const u8 = "";
    var query: ?[]const u8 = null;

    if (reference_ref.scheme != null) {
        scheme = reference_ref.scheme;
        has_authority = reference_ref.has_authority;
        authority = reference_ref.authority;
        normalized_path = try normalizePath(
            allocator,
            reference_ref.path,
            false,
        );
        path = normalized_path.?.path;
        query = reference_ref.query;
    } else if (reference_ref.has_authority) {
        scheme = base_ref.scheme;
        has_authority = true;
        authority = reference_ref.authority;
        normalized_path = try normalizePath(
            allocator,
            reference_ref.path,
            false,
        );
        path = normalized_path.?.path;
        query = reference_ref.query;
    } else {
        scheme = base_ref.scheme;
        has_authority = base_ref.has_authority;
        authority = base_ref.authority;

        if (reference_ref.path.len == 0) {
            path = base_ref.path;
            query = reference_ref.query orelse base_ref.query;
        } else {
            if (reference_ref.path[0] == '/') {
                normalized_path = try normalizePath(
                    allocator,
                    reference_ref.path,
                    scheme == null and !has_authority,
                );
            } else {
                merged_path = try mergePaths(
                    allocator,
                    base_ref,
                    reference_ref.path,
                );
                normalized_path = try normalizePath(
                    allocator,
                    merged_path.?,
                    scheme == null and !has_authority,
                );
            }
            path = normalized_path.?.path;
            query = reference_ref.query;
        }
    }

    if (scheme) |value| {
        try output.appendSlice(value);
        try output.append(':');
    }
    if (has_authority) {
        try output.appendSlice("//");
        try output.appendSlice(authority);
    }
    try output.appendSlice(path);
    if (query) |value| {
        try output.append('?');
        try output.appendSlice(value);
    }
    if (reference_ref.fragment) |value| {
        try output.append('#');
        try output.appendSlice(value);
    }

    return output.toOwnedSlice() catch error.OutOfMemory;
}

fn parseReference(text: []const u8) Error!Reference {
    var result = Reference{};
    var end = text.len;

    if (std.mem.indexOfScalar(u8, text, '#')) |fragment_start| {
        result.fragment = text[fragment_start + 1 ..];
        end = fragment_start;
    }

    const before_fragment = text[0..end];
    if (std.mem.indexOfScalar(u8, before_fragment, '?')) |query_start| {
        result.query = before_fragment[query_start + 1 ..];
        end = query_start;
    }

    const path_and_authority = text[0..end];
    var path_start: usize = 0;
    if (findSchemeEnd(path_and_authority)) |scheme_end| {
        result.scheme = path_and_authority[0..scheme_end];
        path_start = scheme_end + 1;
    }

    if (path_and_authority.len - path_start >= 2 and
        std.mem.eql(
            u8,
            path_and_authority[path_start .. path_start + 2],
            "//",
        ))
    {
        result.has_authority = true;
        const authority_start = path_start + 2;
        const authority_end = std.mem.indexOfScalarPos(
            u8,
            path_and_authority,
            authority_start,
            '/',
        ) orelse path_and_authority.len;
        result.authority = path_and_authority[authority_start..authority_end];
        path_start = authority_end;
    }

    result.path = path_and_authority[path_start..];
    try validatePercentEscapes(text);
    return result;
}

fn findSchemeEnd(text: []const u8) ?usize {
    const colon = std.mem.indexOfScalar(u8, text, ':') orelse return null;
    const first_slash = std.mem.indexOfScalar(u8, text, '/') orelse text.len;
    if (colon > first_slash or colon == 0) return null;
    if (!std.ascii.isAlphabetic(text[0])) return null;
    for (text[1..colon]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and
            byte != '+' and
            byte != '-' and
            byte != '.')
        {
            return null;
        }
    }
    return colon;
}

fn validatePercentEscapes(text: []const u8) Error!void {
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        if (text[index] != '%') continue;
        if (index + 2 >= text.len or
            !isHex(text[index + 1]) or
            !isHex(text[index + 2]))
        {
            return error.InvalidUri;
        }
        index += 2;
    }
}

fn mergePaths(
    allocator: std.mem.Allocator,
    base: Reference,
    reference_path: []const u8,
) Error![]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();

    if (base.has_authority and base.path.len == 0) {
        try output.append('/');
    } else if (std.mem.lastIndexOfScalar(u8, base.path, '/')) |slash| {
        try output.appendSlice(base.path[0 .. slash + 1]);
    }
    try output.appendSlice(reference_path);
    return output.toOwnedSlice() catch error.OutOfMemory;
}

fn normalizePath(
    allocator: std.mem.Allocator,
    input: []const u8,
    preserve_leading_parent: bool,
) Error!NormalizedPath {
    var segments = std.array_list.Managed([]const u8).init(allocator);
    defer segments.deinit();

    const absolute = input.len != 0 and input[0] == '/';
    const body = if (absolute) input[1..] else input;
    var segment_start: usize = 0;
    while (true) {
        const slash = std.mem.indexOfScalarPos(
            u8,
            body,
            segment_start,
            '/',
        );
        const segment_end = slash orelse body.len;
        const segment = body[segment_start..segment_end];
        const terminal = slash == null;

        if (std.mem.eql(u8, segment, ".")) {
            if (terminal) try segments.append("");
        } else if (std.mem.eql(u8, segment, "..")) {
            var retained_parent = false;
            if (segments.items.len != 0 and
                !std.mem.eql(u8, segments.getLast(), ".."))
            {
                _ = segments.pop();
            } else if (!absolute and preserve_leading_parent) {
                try segments.append(segment);
                retained_parent = true;
            }

            if (terminal and !retained_parent) {
                try segments.append("");
            }
        } else {
            try segments.append(segment);
        }

        if (slash) |index| {
            segment_start = index + 1;
        } else {
            break;
        }
    }

    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();

    // A leading empty segment can remain after cancelling a relative path.
    // Preserve the delimiter left by the removed dot segment. This follows
    // RFC 3986 section 5.2.4 instead of inventing a "./" path prefix.
    if (!absolute and
        segments.items.len > 1 and
        segments.items[0].len == 0)
    {
        try output.append('/');
    }
    if (absolute) {
        try output.append('/');
    }
    for (segments.items, 0..) |segment, index| {
        if (index != 0) try output.append('/');
        try output.appendSlice(segment);
    }

    const allocation = output.toOwnedSlice() catch return error.OutOfMemory;
    return .{ .allocation = allocation, .path = allocation };
}

fn isHex(byte: u8) bool {
    return std.ascii.isDigit(byte) or
        (byte >= 'a' and byte <= 'f') or
        (byte >= 'A' and byte <= 'F');
}

fn resolutionAllocationFailureCase(allocator: std.mem.Allocator) !void {
    const resolved = try resolve(
        allocator,
        "../a/b/",
        "../../c///../d",
    );
    defer allocator.free(resolved);
}

test "resolves RFC 3986 normal and abnormal reference examples" {
    const testing = std.testing;
    const base = "http://a/b/c/d;p?q";
    const cases = [_]struct {
        reference: []const u8,
        expected: []const u8,
    }{
        .{ .reference = "g:h", .expected = "g:h" },
        .{ .reference = "g", .expected = "http://a/b/c/g" },
        .{ .reference = "./g", .expected = "http://a/b/c/g" },
        .{ .reference = "g/", .expected = "http://a/b/c/g/" },
        .{ .reference = "/g", .expected = "http://a/g" },
        .{ .reference = "//g", .expected = "http://g" },
        .{ .reference = "?y", .expected = "http://a/b/c/d;p?y" },
        .{ .reference = "g?y", .expected = "http://a/b/c/g?y" },
        .{ .reference = "#s", .expected = "http://a/b/c/d;p?q#s" },
        .{ .reference = "g#s", .expected = "http://a/b/c/g#s" },
        .{ .reference = "g?y#s", .expected = "http://a/b/c/g?y#s" },
        .{ .reference = ";x", .expected = "http://a/b/c/;x" },
        .{ .reference = "g;x", .expected = "http://a/b/c/g;x" },
        .{ .reference = "g;x?y#s", .expected = "http://a/b/c/g;x?y#s" },
        .{ .reference = "", .expected = "http://a/b/c/d;p?q" },
        .{ .reference = ".", .expected = "http://a/b/c/" },
        .{ .reference = "./", .expected = "http://a/b/c/" },
        .{ .reference = "..", .expected = "http://a/b/" },
        .{ .reference = "../", .expected = "http://a/b/" },
        .{ .reference = "../g", .expected = "http://a/b/g" },
        .{ .reference = "../..", .expected = "http://a/" },
        .{ .reference = "../../", .expected = "http://a/" },
        .{ .reference = "../../g", .expected = "http://a/g" },
        .{ .reference = "../../../g", .expected = "http://a/g" },
        .{ .reference = "../../../../g", .expected = "http://a/g" },
        .{ .reference = "/./g", .expected = "http://a/g" },
        .{ .reference = "/../g", .expected = "http://a/g" },
        .{ .reference = "g.", .expected = "http://a/b/c/g." },
        .{ .reference = ".g", .expected = "http://a/b/c/.g" },
        .{ .reference = "g..", .expected = "http://a/b/c/g.." },
        .{ .reference = "..g", .expected = "http://a/b/c/..g" },
        .{ .reference = "./../g", .expected = "http://a/b/g" },
        .{ .reference = "./g/.", .expected = "http://a/b/c/g/" },
        .{ .reference = "g/..", .expected = "http://a/b/c/" },
        .{ .reference = "g/./h", .expected = "http://a/b/c/g/h" },
        .{ .reference = "g/../h", .expected = "http://a/b/c/h" },
        .{ .reference = "g;x=1/./y", .expected = "http://a/b/c/g;x=1/y" },
        .{ .reference = "g;x=1/../y", .expected = "http://a/b/c/y" },
        .{ .reference = "g//h", .expected = "http://a/b/c/g//h" },
        .{ .reference = "g///h", .expected = "http://a/b/c/g///h" },
        .{ .reference = "g//../h", .expected = "http://a/b/c/g/h" },
        .{ .reference = "g///../h", .expected = "http://a/b/c/g//h" },
        .{ .reference = "/dir//../pkg", .expected = "http://a/dir/pkg" },
        .{ .reference = "/dir///../pkg", .expected = "http://a/dir//pkg" },
        .{ .reference = "g?y/./x", .expected = "http://a/b/c/g?y/./x" },
        .{ .reference = "g?y/../x", .expected = "http://a/b/c/g?y/../x" },
        .{ .reference = "g#s/./x", .expected = "http://a/b/c/g#s/./x" },
        .{ .reference = "g#s/../x", .expected = "http://a/b/c/g#s/../x" },
        .{ .reference = "http:g", .expected = "http:g" },
    };

    for (cases) |case| {
        const actual = try resolve(testing.allocator, base, case.reference);
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(case.expected, actual);
    }
}

test "resolves relative XML bases without inventing a document path" {
    const testing = std.testing;
    const base = try resolve(testing.allocator, null, "../repo/./");
    defer testing.allocator.free(base);
    try testing.expectEqualStrings("../repo/", base);

    const child = try resolve(testing.allocator, base, "../pool/");
    defer testing.allocator.free(child);
    try testing.expectEqualStrings("../pool/", child);

    const package = try resolve(testing.allocator, child, "pkg.rpm");
    defer testing.allocator.free(package);
    try testing.expectEqualStrings("../pool/pkg.rpm", package);

    const beyond_base = try resolve(
        testing.allocator,
        "a/b/",
        "../../../c/",
    );
    defer testing.allocator.free(beyond_base);
    try testing.expectEqualStrings("../c/", beyond_base);

    const cancelled = try resolve(testing.allocator, null, "a/../b");
    defer testing.allocator.free(cancelled);
    try testing.expectEqualStrings("b", cancelled);

    const current_directory = try resolve(
        testing.allocator,
        null,
        "a/../",
    );
    defer testing.allocator.free(current_directory);
    try testing.expectEqualStrings("", current_directory);

    const cancelled_base = try resolve(
        testing.allocator,
        "a/",
        "../b",
    );
    defer testing.allocator.free(cancelled_base);
    try testing.expectEqualStrings("b", cancelled_base);

    const retained_empty = try resolve(
        testing.allocator,
        null,
        "a/..//b",
    );
    defer testing.allocator.free(retained_empty);
    try testing.expectEqualStrings("//b", retained_empty);
}

test "terminal parents retain absolute directory paths" {
    const testing = std.testing;
    const absolute = try resolve(testing.allocator, null, "/a/b/..");
    defer testing.allocator.free(absolute);
    try testing.expectEqualStrings("/a/", absolute);

    const authority = try resolve(
        testing.allocator,
        "https://example.test/a/b/",
        "c/..",
    );
    defer testing.allocator.free(authority);
    try testing.expectEqualStrings(
        "https://example.test/a/b/",
        authority,
    );
}

test "URI resolution releases all intermediate allocations on failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        resolutionAllocationFailureCase,
        .{},
    );
}
