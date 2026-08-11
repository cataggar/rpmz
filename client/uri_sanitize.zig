//! One implementation of "make this URI safe to print or record".
//!
//! Three parts of a URI can carry a secret: the userinfo (`user:password@`),
//! the query (`?token=…`), and the fragment. Two near-identical copies of a
//! redactor previously lived in `remoterepo.zig` and `repositories.zig` and
//! both removed only userinfo, so a `?token=` query reached diagnostics,
//! logs, and anything else that echoed a repository URL.
//!
//! Everything that prints, logs, or records a URI goes through here.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// The text substituted for each removed part. It is deliberately visible so
/// a reader can tell "this URI had a secret in it" from "this URI was plain",
/// which matters when diagnosing a fetch failure against a credentialed
/// mirror.
pub const marker = "<redacted>";

/// The three secret-carrying parts of a URI, as offsets into the input.
pub const Parts = struct {
    /// Byte just past the `://`, or null when the value has no scheme.
    authority_start: ?usize = null,
    /// Offset of the `@` that ends the userinfo, when there is one.
    userinfo_end: ?usize = null,
    /// Offset of the first `?` or `#` after the authority.
    tail_start: ?usize = null,

    pub fn hasUserinfo(self: Parts) bool {
        return self.userinfo_end != null;
    }

    pub fn hasSecretCapableParts(self: Parts) bool {
        return self.userinfo_end != null or self.tail_start != null;
    }
};

/// Splits a URI without allocating or validating it.
///
/// A value with no `://` is treated as an opaque local path: a filesystem
/// path may legitimately contain `?` or `#`, and it has no authority, so
/// there is nothing here that could be a credential.
pub fn split(value: []const u8) Parts {
    const scheme = std.mem.indexOf(u8, value, "://") orelse return .{};
    const authority_start = scheme + 3;
    const authority_end = indexOfAnyPos(value, authority_start, "/?#") orelse value.len;
    const authority = value[authority_start..authority_end];

    return .{
        .authority_start = authority_start,
        .userinfo_end = if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at|
            authority_start + at
        else
            null,
        .tail_start = indexOfAnyPos(value, authority_end, "?#"),
    };
}

/// True when the URI carries userinfo. This is the credential shape callers
/// refuse outright, as opposed to the ones they strip.
pub fn hasUserinfo(value: []const u8) bool {
    return split(value).hasUserinfo();
}

/// Returns the URI with userinfo, query, and fragment replaced by `marker`.
///
/// The delimiter is kept so the result stays recognizable as a URI and the
/// reader can see *which* part was removed: `https://h/p?<redacted>` is
/// unambiguous where a bare truncation would not be.
pub fn redactAlloc(allocator: Allocator, value: []const u8) Allocator.Error![]u8 {
    const parts = split(value);
    if (!parts.hasSecretCapableParts()) return allocator.dupe(u8, value);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    const body_start = if (parts.userinfo_end) |at| blk: {
        try out.appendSlice(allocator, value[0 .. parts.authority_start.?]);
        try out.appendSlice(allocator, marker);
        try out.append(allocator, '@');
        break :blk at + 1;
    } else 0;

    const body_end = parts.tail_start orelse value.len;
    try out.appendSlice(allocator, value[body_start..body_end]);
    if (parts.tail_start) |tail| {
        try out.append(allocator, value[tail]);
        try out.appendSlice(allocator, marker);
    }
    return out.toOwnedSlice(allocator);
}

/// Returns the URI with only the parts a bundle may record: scheme,
/// authority without userinfo, and path. A query or fragment is dropped
/// entirely rather than marked, because the result is a fetch coordinate
/// that gets written into a manifest, not a diagnostic for a human.
///
/// Callers must not use this to build a request. Dropping a query changes
/// what the URI addresses; it is only safe on a value that is being recorded.
pub fn recordableAlloc(allocator: Allocator, value: []const u8) Allocator.Error![]u8 {
    const parts = split(value);
    if (!parts.hasSecretCapableParts()) return allocator.dupe(u8, value);

    const body_start = if (parts.userinfo_end) |at| at + 1 else 0;
    const body_end = parts.tail_start orelse value.len;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    if (parts.userinfo_end != null) {
        try out.appendSlice(allocator, value[0 .. parts.authority_start.?]);
    }
    try out.appendSlice(allocator, value[body_start..body_end]);
    return out.toOwnedSlice(allocator);
}

fn indexOfAnyPos(value: []const u8, start: usize, set: []const u8) ?usize {
    if (start >= value.len) return null;
    const found = std.mem.indexOfAny(u8, value[start..], set) orelse return null;
    return start + found;
}

const testing = std.testing;

fn expectRedacted(expected: []const u8, input: []const u8) !void {
    const actual = try redactAlloc(testing.allocator, input);
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(expected, actual);
}

fn expectRecordable(expected: []const u8, input: []const u8) !void {
    const actual = try recordableAlloc(testing.allocator, input);
    defer testing.allocator.free(actual);
    try testing.expectEqualStrings(expected, actual);
}

test "a URI with nothing to hide is returned unchanged" {
    try expectRedacted("https://example.invalid/base/", "https://example.invalid/base/");
    try expectRedacted("/snapshot/base", "/snapshot/base");
    try expectRedacted("", "");
    try expectRecordable("https://example.invalid/base/", "https://example.invalid/base/");
}

test "userinfo is removed but the URI stays recognizable" {
    try expectRedacted(
        "https://" ++ marker ++ "@example.invalid/base/",
        "https://user:pw@example.invalid/base/",
    );
    // Only the last `@` in the authority ends the userinfo; an `@` later in
    // the path is ordinary data.
    try expectRedacted(
        "https://" ++ marker ++ "@example.invalid/base@2024",
        "https://a@b@example.invalid/base@2024",
    );
    try expectRecordable(
        "https://example.invalid/base/",
        "https://user:pw@example.invalid/base/",
    );
}

test "query and fragment are removed, which the old redactor did not do" {
    try expectRedacted(
        "https://example.invalid/base/?" ++ marker,
        "https://example.invalid/base/?token=secret",
    );
    try expectRedacted(
        "https://example.invalid/base/#" ++ marker,
        "https://example.invalid/base/#secret",
    );
    // A fragment after a query is already covered by cutting at the query.
    try expectRedacted(
        "https://example.invalid/base/?" ++ marker,
        "https://example.invalid/base/?token=secret#frag",
    );
    // A `?` inside the authority still ends it.
    try expectRedacted(
        "https://example.invalid?" ++ marker,
        "https://example.invalid?token=secret",
    );
    try expectRecordable(
        "https://example.invalid/base/",
        "https://example.invalid/base/?token=secret#frag",
    );
}

test "userinfo and query are removed together" {
    try expectRedacted(
        "https://" ++ marker ++ "@example.invalid/base/?" ++ marker,
        "https://user:pw@example.invalid/base/?token=secret",
    );
    try expectRecordable(
        "https://example.invalid/base/",
        "https://user:pw@example.invalid/base/?token=secret",
    );
}

test "an opaque local path is never reinterpreted as a URI" {
    // `?` and `#` are legal in a filename and there is no authority to carry
    // a credential, so a schemeless value is left alone.
    try expectRedacted("/snapshot/odd?name#1", "/snapshot/odd?name#1");
    try expectRecordable("/snapshot/odd?name#1", "/snapshot/odd?name#1");
    try testing.expect(!hasUserinfo("/snapshot/a@b"));
}

test "split classifies each secret-carrying part" {
    try testing.expect(hasUserinfo("https://user@example.invalid/"));
    try testing.expect(!hasUserinfo("https://example.invalid/base@2024"));
    try testing.expect(!hasUserinfo("https://example.invalid/?token=x"));

    try testing.expect(split("https://example.invalid/?token=x").hasSecretCapableParts());
    try testing.expect(!split("https://example.invalid/base/").hasSecretCapableParts());
    try testing.expect(!split("file:///snapshot/base").hasSecretCapableParts());
}

test "redaction never leaks any byte of a removed part" {
    const secret = "sup3rs3cr3t";
    const inputs = [_][]const u8{
        "https://user:" ++ secret ++ "@example.invalid/base/",
        "https://example.invalid/base/?token=" ++ secret,
        "https://example.invalid/base/#" ++ secret,
        "https://" ++ secret ++ "@example.invalid/base/?k=" ++ secret,
    };
    for (inputs) |input| {
        const redacted = try redactAlloc(testing.allocator, input);
        defer testing.allocator.free(redacted);
        const recordable = try recordableAlloc(testing.allocator, input);
        defer testing.allocator.free(recordable);
        try testing.expect(std.mem.indexOf(u8, redacted, secret) == null);
        try testing.expect(std.mem.indexOf(u8, recordable, secret) == null);
    }
}

test "redaction releases everything on allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            const redacted = try redactAlloc(
                allocator,
                "https://user:pw@example.invalid/base/?token=secret",
            );
            allocator.free(redacted);
            const recordable = try recordableAlloc(
                allocator,
                "https://user:pw@example.invalid/base/?token=secret",
            );
            allocator.free(recordable);
        }
    }.run, .{});
}
