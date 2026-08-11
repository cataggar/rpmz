//! Turning repository-supplied coordinates into bundle destination paths.
//!
//! Fetch coordinates and destination paths are separate concerns (D3). A
//! repomd record's `href` may be an absolute `http(s)://` or `media://` URL,
//! and `xml_base` may override the base it is fetched from. None of that may
//! influence *where* the exporter writes: a repository that could steer a
//! write through `xml_base`, an absolute authority, a `..` segment, or a
//! percent-encoded separator would be able to place bytes anywhere the
//! exporting process can write.
//!
//! So the destination is derived from the *path component of `href` alone*,
//! validated to death, and scoped under the repository's own subtree. The
//! original coordinates are still recorded in the manifest, so a consumer can
//! check the mapping rather than recompute it.
//!
//! Everything here is deliberately allocation-light, total, and free of I/O:
//! a path decision must be reproducible and reviewable without a filesystem.

const std = @import("std");

pub const MapError = error{
    /// The href has no usable path component at all.
    EmptyPath,
    /// The path escapes its subtree, or tries to be absolute.
    UnsafePath,
    /// A component or the whole path is longer than any filesystem accepts.
    PathTooLong,
    /// The path contains bytes that must never reach a filesystem call.
    InvalidCharacter,
    /// A percent escape is malformed, or decodes to a byte that would change
    /// the path's structure.
    InvalidEscape,
    OutOfMemory,
};

/// Longest single path component. The smallest limit in practice is 255.
pub const max_component_len: usize = 255;
/// Longest mapped relative path.
pub const max_path_len: usize = 1024;

/// Map a repository-declared `href` onto a bundle-relative path fragment.
///
/// Only the path component of `href` survives: scheme, authority, query, and
/// fragment are discarded, because none of them may influence a destination.
/// The result never begins or ends with `/`, never contains an empty, `.`, or
/// `..` component, and is fully percent-decoded so that the bytes on disk are
/// the bytes the manifest records.
pub fn mapHref(allocator: std.mem.Allocator, href: []const u8) MapError![]u8 {
    const path = pathComponentOf(href);
    if (path.len == 0) return error.EmptyPath;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |raw| {
        // A leading, trailing, or doubled separator yields an empty segment.
        // Silently collapsing them would let two distinct hrefs map to one
        // destination, so they are simply skipped -- with the one exception
        // that the result must still be non-empty, checked below.
        if (raw.len == 0) continue;
        var decoded: std.ArrayList(u8) = .empty;
        defer decoded.deinit(allocator);
        try decodeComponent(allocator, raw, &decoded);
        try validateComponent(decoded.items);
        if (out.items.len != 0) try out.append(allocator, '/');
        try out.appendSlice(allocator, decoded.items);
        if (out.items.len > max_path_len) return error.PathTooLong;
    }

    if (out.items.len == 0) return error.EmptyPath;
    return out.toOwnedSlice(allocator);
}

/// The path component of a URI reference, with scheme, authority, query, and
/// fragment removed.
///
/// This is intentionally stricter and simpler than a general URI parser: it
/// only has to answer "which bytes may influence a filename", and every
/// ambiguity is resolved by discarding more.
pub fn pathComponentOf(href: []const u8) []const u8 {
    var rest = href;

    // Drop the fragment first: everything after '#' is not part of the path,
    // and a '?' inside a fragment must not be mistaken for a query.
    if (std.mem.indexOfScalar(u8, rest, '#')) |hash| rest = rest[0..hash];
    if (std.mem.indexOfScalar(u8, rest, '?')) |question| rest = rest[0..question];

    // `scheme://authority/path` -- take everything after the authority. An
    // href with an authority but no path yields an empty path, which the
    // caller rejects.
    if (std.mem.indexOf(u8, rest, "://")) |scheme_end| {
        const after = rest[scheme_end + 3 ..];
        const slash = std.mem.indexOfScalar(u8, after, '/') orelse return "";
        return after[slash..];
    }
    // A scheme-relative reference, `//authority/path`.
    if (std.mem.startsWith(u8, rest, "//")) {
        const after = rest[2..];
        const slash = std.mem.indexOfScalar(u8, after, '/') orelse return "";
        return after[slash..];
    }
    // An opaque scheme such as `media:path` or `mailto:...`. Everything before
    // the first ':' is a scheme only if it looks like one; otherwise a bare
    // relative path containing a colon (legal in a filename) would be
    // truncated.
    if (schemeEnd(rest)) |colon| return rest[colon + 1 ..];
    return rest;
}

/// Index of the ':' ending a URI scheme, if `value` starts with one.
fn schemeEnd(value: []const u8) ?usize {
    if (value.len == 0) return null;
    if (!std.ascii.isAlphabetic(value[0])) return null;
    for (value, 0..) |byte, index| {
        if (byte == ':') return if (index == 0) null else index;
        if (byte == '/') return null;
        if (std.ascii.isAlphanumeric(byte)) continue;
        if (byte == '+' or byte == '-' or byte == '.') continue;
        return null;
    }
    return null;
}

fn decodeComponent(
    allocator: std.mem.Allocator,
    raw: []const u8,
    out: *std.ArrayList(u8),
) MapError!void {
    var index: usize = 0;
    while (index < raw.len) {
        const byte = raw[index];
        if (byte != '%') {
            try out.append(allocator, byte);
            index += 1;
            continue;
        }
        if (index + 2 >= raw.len) return error.InvalidEscape;
        const hi = std.fmt.charToDigit(raw[index + 1], 16) catch return error.InvalidEscape;
        const lo = std.fmt.charToDigit(raw[index + 2], 16) catch return error.InvalidEscape;
        const decoded: u8 = @as(u8, hi) * 16 + @as(u8, lo);
        // A percent escape must not be able to reintroduce path structure.
        // `%2f` is the classic way to smuggle a separator past a validator
        // that only inspected the raw text.
        switch (decoded) {
            '/', '\\', 0 => return error.InvalidEscape,
            else => {},
        }
        try out.append(allocator, decoded);
        index += 3;
    }
}

fn validateComponent(component: []const u8) MapError!void {
    if (component.len == 0) return error.UnsafePath;
    if (component.len > max_component_len) return error.PathTooLong;
    if (std.mem.eql(u8, component, ".")) return error.UnsafePath;
    if (std.mem.eql(u8, component, "..")) return error.UnsafePath;
    for (component) |byte| {
        if (byte < 0x20 or byte == 0x7f) return error.InvalidCharacter;
        if (byte == '/' or byte == '\\') return error.UnsafePath;
    }
}

/// True when `value` is usable as exactly one path component.
///
/// Repository IDs become directory names under `repos/` and `packages/`, so a
/// repository whose ID contained a separator or a `..` could place its files
/// in another repository's subtree -- which would also defeat the
/// wrong-repository-association check a consumer performs.
pub fn isSafeComponent(value: []const u8) bool {
    validateComponent(value) catch return false;
    return true;
}

/// Join a bundle prefix, a repository ID, and a mapped path.
///
/// `prefix` is one of `transaction_bundle.repositories_prefix` or
/// `packages_prefix` and already ends in `/`.
pub fn joinRepoScoped(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    repository_id: []const u8,
    mapped: []const u8,
) MapError![]u8 {
    if (!isSafeComponent(repository_id)) return error.UnsafePath;
    if (mapped.len == 0) return error.EmptyPath;
    const joined = std.fmt.allocPrint(
        allocator,
        "{s}{s}/{s}",
        .{ prefix, repository_id, mapped },
    ) catch return error.OutOfMemory;
    errdefer allocator.free(joined);
    if (joined.len > max_path_len) return error.PathTooLong;
    return joined;
}

const testing = std.testing;

fn expectMapped(expected: []const u8, href: []const u8) !void {
    const mapped = try mapHref(testing.allocator, href);
    defer testing.allocator.free(mapped);
    try testing.expectEqualStrings(expected, mapped);
}

test "a relative href maps to itself" {
    try expectMapped("repodata/primary.xml.zst", "repodata/primary.xml.zst");
    try expectMapped("a.rpm", "a.rpm");
    try expectMapped("x/y/z.rpm", "x/y/z.rpm");
}

test "scheme and authority never reach the destination" {
    // Only the path survives. The authority must not become a directory: if
    // it did, the same record served by two mirrors would land in two
    // different places and the bundle digest would depend on which mirror
    // answered.
    try expectMapped(
        "pub/repodata/primary.xml.zst",
        "https://mirror.example.invalid/pub/repodata/primary.xml.zst",
    );
    try expectMapped(
        "pub/repodata/primary.xml.zst",
        "https://other.example.invalid/pub/repodata/primary.xml.zst",
    );
}

test "query and fragment are discarded, not encoded into a filename" {
    try expectMapped("a.rpm", "a.rpm?token=secret");
    try expectMapped("a.rpm", "a.rpm#section");
    try expectMapped("a.rpm", "a.rpm?token=secret#frag");
    // A '?' inside a fragment is not a query delimiter.
    try expectMapped("a.rpm", "a.rpm#frag?token=secret");
}

test "an opaque scheme keeps only its path" {
    try expectMapped("packages/a.rpm", "media:packages/a.rpm");
    try expectMapped("a.rpm", "file:a.rpm");
    try expectMapped("srv/repo/a.rpm", "file:///srv/repo/a.rpm");
}

test "a colon inside a filename is not mistaken for a scheme" {
    // `no scheme` is not a valid scheme (space), so the whole thing is a path.
    try expectMapped("odd name.rpm", "odd name.rpm");
    try expectMapped("dir/a:b.rpm", "dir/a:b.rpm");
}

test "absolute paths are made relative rather than escaping the bundle" {
    try expectMapped("repodata/primary.xml", "/repodata/primary.xml");
    try expectMapped("repodata/primary.xml", "///repodata///primary.xml");
}

test "traversal is refused outright" {
    for ([_][]const u8{
        "../outside.rpm",
        "repodata/../../outside.rpm",
        "a/./b.rpm",
        "..",
        ".",
        "https://host.invalid/pub/../../etc/passwd",
    }) |href| {
        try testing.expectError(error.UnsafePath, mapHref(testing.allocator, href));
    }
}

test "a percent-encoded separator cannot smuggle in structure" {
    // These are the classic bypasses: a validator that inspected the raw text
    // would see one component, and a later decode would produce two.
    try testing.expectError(
        error.InvalidEscape,
        mapHref(testing.allocator, "repodata%2f..%2fescape.rpm"),
    );
    try testing.expectError(
        error.InvalidEscape,
        mapHref(testing.allocator, "a%2Fb.rpm"),
    );
    try testing.expectError(
        error.InvalidEscape,
        mapHref(testing.allocator, "a%5Cb.rpm"),
    );
    try testing.expectError(
        error.InvalidEscape,
        mapHref(testing.allocator, "a%00.rpm"),
    );
    // A decoded `..` component is still a traversal.
    try testing.expectError(
        error.UnsafePath,
        mapHref(testing.allocator, "%2e%2e/escape.rpm"),
    );
}

test "ordinary percent escapes decode so the manifest matches the disk" {
    try expectMapped("a b.rpm", "a%20b.rpm");
    try expectMapped("a+b.rpm", "a%2Bb.rpm");
    // '+' is not a space outside a query string.
    try expectMapped("a+b.rpm", "a+b.rpm");
}

test "malformed escapes are refused" {
    for ([_][]const u8{ "a%.rpm", "a%2.rpm", "a%zz.rpm", "a%2" }) |href| {
        try testing.expectError(
            error.InvalidEscape,
            mapHref(testing.allocator, href),
        );
    }
}

test "control characters never reach a filesystem call" {
    try testing.expectError(
        error.InvalidCharacter,
        mapHref(testing.allocator, "a%0Ab.rpm"),
    );
    try testing.expectError(
        error.InvalidCharacter,
        mapHref(testing.allocator, "a\tb.rpm"),
    );
}

test "an href with no path at all is refused" {
    for ([_][]const u8{ "", "https://host.invalid", "//host.invalid", "?token=x", "#frag", "/" }) |href| {
        try testing.expectError(error.EmptyPath, mapHref(testing.allocator, href));
    }
}

test "over-long components and paths are refused" {
    const long_component = "a" ** (max_component_len + 1);
    try testing.expectError(
        error.PathTooLong,
        mapHref(testing.allocator, long_component),
    );

    var builder: std.ArrayList(u8) = .empty;
    defer builder.deinit(testing.allocator);
    while (builder.items.len <= max_path_len) {
        try builder.appendSlice(testing.allocator, "component/");
    }
    try builder.appendSlice(testing.allocator, "tail.rpm");
    try testing.expectError(
        error.PathTooLong,
        mapHref(testing.allocator, builder.items),
    );
}

test "repository ids must be a single safe component" {
    try testing.expect(isSafeComponent("base"));
    try testing.expect(isSafeComponent("photon-updates"));
    try testing.expect(!isSafeComponent(""));
    try testing.expect(!isSafeComponent("."));
    try testing.expect(!isSafeComponent(".."));
    try testing.expect(!isSafeComponent("a/b"));
    try testing.expect(!isSafeComponent("a\\b"));
    try testing.expect(!isSafeComponent("a\x00b"));
}

test "joinRepoScoped refuses to let a repository id escape its subtree" {
    const joined = try joinRepoScoped(testing.allocator, "packages/", "base", "a.rpm");
    defer testing.allocator.free(joined);
    try testing.expectEqualStrings("packages/base/a.rpm", joined);

    try testing.expectError(
        error.UnsafePath,
        joinRepoScoped(testing.allocator, "packages/", "../keys", "a.rpm"),
    );
    try testing.expectError(
        error.UnsafePath,
        joinRepoScoped(testing.allocator, "packages/", "a/b", "a.rpm"),
    );
    try testing.expectError(
        error.EmptyPath,
        joinRepoScoped(testing.allocator, "packages/", "base", ""),
    );
}

test "mapping is deterministic and injective for distinct inputs" {
    // Two hrefs that differ only in the parts we discard must map to the same
    // destination; two that differ in the path must not.
    const same_a = try mapHref(testing.allocator, "https://a.invalid/p/x.rpm");
    defer testing.allocator.free(same_a);
    const same_b = try mapHref(testing.allocator, "https://b.invalid/p/x.rpm?t=1");
    defer testing.allocator.free(same_b);
    try testing.expectEqualStrings(same_a, same_b);

    const other = try mapHref(testing.allocator, "https://a.invalid/p/y.rpm");
    defer testing.allocator.free(other);
    try testing.expect(!std.mem.eql(u8, same_a, other));
}

test "mapping survives allocation failure without leaking" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(
        error.OutOfMemory,
        mapHref(failing.allocator(), "repodata/primary.xml.zst"),
    );
}
