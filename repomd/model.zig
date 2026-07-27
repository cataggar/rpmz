const std = @import("std");

pub const RecordKind = enum(u32) {
    unknown = 0,
    primary = 1,
    filelists = 2,
    other = 3,
    updateinfo = 4,
};

pub const Checksum = extern struct {
    pszType: ?[*:0]const u8 = null,
    pszValue: ?[*:0]const u8 = null,
};

pub const Record = extern struct {
    pszType: ?[*:0]const u8 = null,
    dwKind: u32 = @intFromEnum(RecordKind.unknown),
    pszLocationHref: ?[*:0]const u8 = null,
    checksum: Checksum = .{},
    openChecksum: Checksum = .{},
    nTimestamp: u64 = 0,
    nSize: u64 = 0,
    nOpenSize: u64 = 0,
    nDatabaseVersion: u64 = 0,
    nHasTimestamp: c_int = 0,
    nHasSize: c_int = 0,
    nHasOpenSize: c_int = 0,
    nHasDatabaseVersion: c_int = 0,
};

pub const ParsedRepoMd = struct {
    pszRevision: ?[*:0]const u8 = null,
    pRecords: []Record = &[_]Record{},
    /// Parallel to pRecords. This is parser-only metadata so Record keeps
    /// its stable C ABI layout.
    pRecordXmlBases: []?[]const u8 = &[_]?[]const u8{},
};

pub const DependencyKind = enum {
    provides,
    requires,
    conflicts,
    obsoletes,
    recommends,
    suggests,
    supplements,
    enhances,
};

pub const CompareOp = enum {
    none,
    eq,
    lt,
    le,
    gt,
    ge,
};

pub const RelationRange = struct {
    start: usize = 0,
    len: usize = 0,

    pub fn slice(self: RelationRange, relations: []const Relation) []const Relation {
        return relations[self.start .. self.start + self.len];
    }
};

pub const FileKind = enum {
    plain,
    dir,
    ghost,
};

pub const FileRange = struct {
    start: usize = 0,
    len: usize = 0,

    pub fn slice(self: FileRange, files: []const FileEntry) []const FileEntry {
        return files[self.start .. self.start + self.len];
    }
};

pub const ChangelogRange = struct {
    start: usize = 0,
    len: usize = 0,

    pub fn slice(self: ChangelogRange, changelogs: []const ChangelogEntry) []const ChangelogEntry {
        return changelogs[self.start .. self.start + self.len];
    }
};

pub const AdvisoryKind = enum {
    unknown,
    security,
    bugfix,
    enhancement,
};

pub const AdvisoryReferenceKind = enum {
    other,
    bugzilla,
    cve,
    vendor,
};

pub const AdvisoryReferenceRange = struct {
    start: usize = 0,
    len: usize = 0,

    pub fn slice(self: AdvisoryReferenceRange, references: []const AdvisoryReference) []const AdvisoryReference {
        return references[self.start .. self.start + self.len];
    }
};

pub const AdvisoryPackageRange = struct {
    start: usize = 0,
    len: usize = 0,

    pub fn slice(self: AdvisoryPackageRange, packages: []const AdvisoryPackage) []const AdvisoryPackage {
        return packages[self.start .. self.start + self.len];
    }
};

pub const PackageChecksum = struct {
    kind: []const u8,
    value: []const u8,
    is_pkgid: bool = false,
};

pub const Nevra = struct {
    name: []const u8 = "",
    epoch: ?u32 = null,
    version: []const u8 = "",
    release: []const u8 = "",
    arch: []const u8 = "",
};

pub const EvrQueryParts = struct {
    epoch: ?u32,
    version: []const u8,
    release: ?[]const u8,
};

pub fn splitEvrQuery(evr: []const u8) EvrQueryParts {
    if (evr.len == 0) {
        return .{ .epoch = null, .version = "", .release = null };
    }
    var epoch: ?u32 = null;
    var body = evr;
    if (std.mem.indexOfScalar(u8, evr, ':')) |separator| {
        if (separator != 0) {
            epoch = std.fmt.parseInt(u32, evr[0..separator], 10) catch null;
            if (epoch != null) body = evr[separator + 1 ..];
        }
    }
    if (body.len == 0) {
        return .{ .epoch = epoch, .version = "", .release = null };
    }
    if (std.mem.lastIndexOfScalar(u8, body, '-')) |separator| {
        if (separator != 0 and separator + 1 < body.len) {
            return .{
                .epoch = epoch,
                .version = body[0..separator],
                .release = body[separator + 1 ..],
            };
        }
    }
    return .{ .epoch = epoch, .version = body, .release = null };
}

pub const PackageTime = struct {
    file: ?u64 = null,
    build: ?u64 = null,
};

pub const PackageSize = struct {
    package: ?u64 = null,
    installed: ?u64 = null,
    archive: ?u64 = null,
};

pub const PackageLocation = struct {
    href: []const u8 = "",
    xml_base: ?[]const u8 = null,

    pub fn resolve(self: PackageLocation, allocator: std.mem.Allocator) ![]const u8 {
        return resolveUriReference(
            allocator,
            self.xml_base,
            self.href,
            true,
        );
    }
};

pub const HeaderRange = struct {
    start: u64,
    end: u64,
};

pub const RpmMetadata = struct {
    license: ?[]const u8 = null,
    vendor: ?[]const u8 = null,
    group: ?[]const u8 = null,
    buildhost: ?[]const u8 = null,
    source_rpm: ?[]const u8 = null,
    header_range: ?HeaderRange = null,
};

pub const Relation = struct {
    name: []const u8,
    flags: ?[]const u8 = null,
    comparison: CompareOp = .none,
    epoch: ?u32 = null,
    version: ?[]const u8 = null,
    release: ?[]const u8 = null,
    pre: bool = false,
    sense: u32 = 0,
};

pub const FileEntry = struct {
    path: []const u8,
    kind: FileKind = .plain,
};

pub const ChangelogEntry = struct {
    author: []const u8,
    timestamp: u64,
    text: []const u8,
};

pub const AdvisoryReference = struct {
    kind: AdvisoryReferenceKind = .other,
    raw_type: ?[]const u8 = null,
    id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    href: ?[]const u8 = null,
};

pub const AdvisoryPackage = struct {
    collection_short: ?[]const u8 = null,
    collection_name: ?[]const u8 = null,
    nevra: Nevra = .{},
    src: ?[]const u8 = null,
    filename: ?[]const u8 = null,
    reboot_suggested: bool = false,
};

pub const Advisory = struct {
    id: []const u8,
    raw_type: []const u8,
    kind: AdvisoryKind = .unknown,
    from: ?[]const u8 = null,
    status: ?[]const u8 = null,
    version: ?[]const u8 = null,
    title: ?[]const u8 = null,
    severity: ?[]const u8 = null,
    release: ?[]const u8 = null,
    rights: ?[]const u8 = null,
    issued: ?[]const u8 = null,
    updated: ?[]const u8 = null,
    description: ?[]const u8 = null,
    reboot_suggested: bool = false,
    references: AdvisoryReferenceRange = .{},
    packages: AdvisoryPackageRange = .{},

    pub fn referenceEntries(self: Advisory, references: []const AdvisoryReference) []const AdvisoryReference {
        return self.references.slice(references);
    }

    pub fn packageEntries(self: Advisory, packages: []const AdvisoryPackage) []const AdvisoryPackage {
        return self.packages.slice(packages);
    }
};

pub const Package = struct {
    pkg_id: []const u8,
    nevra: Nevra,
    checksum: PackageChecksum,
    summary: ?[]const u8 = null,
    description: ?[]const u8 = null,
    packager: ?[]const u8 = null,
    url: ?[]const u8 = null,
    time: PackageTime = .{},
    size: PackageSize = .{},
    location: PackageLocation,
    rpm: RpmMetadata = .{},
    provides: RelationRange = .{},
    requires: RelationRange = .{},
    conflicts: RelationRange = .{},
    obsoletes: RelationRange = .{},
    recommends: RelationRange = .{},
    suggests: RelationRange = .{},
    supplements: RelationRange = .{},
    enhances: RelationRange = .{},
    files: FileRange = .{},
    changelogs: ChangelogRange = .{},

    pub fn range(self: Package, kind: DependencyKind) RelationRange {
        return switch (kind) {
            .provides => self.provides,
            .requires => self.requires,
            .conflicts => self.conflicts,
            .obsoletes => self.obsoletes,
            .recommends => self.recommends,
            .suggests => self.suggests,
            .supplements => self.supplements,
            .enhances => self.enhances,
        };
    }

    pub fn rangePtr(self: *Package, kind: DependencyKind) *RelationRange {
        return switch (kind) {
            .provides => &self.provides,
            .requires => &self.requires,
            .conflicts => &self.conflicts,
            .obsoletes => &self.obsoletes,
            .recommends => &self.recommends,
            .suggests => &self.suggests,
            .supplements => &self.supplements,
            .enhances => &self.enhances,
        };
    }

    pub fn relationsFor(self: Package, kind: DependencyKind, relations: []const Relation) []const Relation {
        return self.range(kind).slice(relations);
    }

    pub fn fileEntries(self: Package, files: []const FileEntry) []const FileEntry {
        return self.files.slice(files);
    }

    pub fn changelogEntries(self: Package, changelogs: []const ChangelogEntry) []const ChangelogEntry {
        return self.changelogs.slice(changelogs);
    }
};

pub const ParsedPrimary = struct {
    declared_package_count: ?u64 = null,
    packages: []Package = &[_]Package{},
    relations: []Relation = &[_]Relation{},
    files: []FileEntry = &[_]FileEntry{},
    changelogs: []ChangelogEntry = &[_]ChangelogEntry{},
};

pub const ParsedUpdateInfo = struct {
    advisories: []Advisory = &[_]Advisory{},
    references: []AdvisoryReference = &[_]AdvisoryReference{},
    packages: []AdvisoryPackage = &[_]AdvisoryPackage{},
};

pub const RepositoryModel = struct {
    pszRevision: ?[*:0]const u8 = null,
    records: []Record = &[_]Record{},
    packages: []Package = &[_]Package{},
    relations: []Relation = &[_]Relation{},
    files: []FileEntry = &[_]FileEntry{},
    changelogs: []ChangelogEntry = &[_]ChangelogEntry{},
    advisories: []Advisory = &[_]Advisory{},
    advisory_references: []AdvisoryReference = &[_]AdvisoryReference{},
    advisory_packages: []AdvisoryPackage = &[_]AdvisoryPackage{},
    has_filelists: bool = false,
    has_other: bool = false,
    has_updateinfo: bool = false,
};

pub fn repositoryModelFromParts(
    parsed_repomd: ParsedRepoMd,
    parsed_primary: ParsedPrimary,
    parsed_updateinfo: ParsedUpdateInfo,
) RepositoryModel {
    var repo = RepositoryModel{
        .pszRevision = parsed_repomd.pszRevision,
        .records = parsed_repomd.pRecords,
        .packages = parsed_primary.packages,
        .relations = parsed_primary.relations,
        .files = parsed_primary.files,
        .changelogs = parsed_primary.changelogs,
        .advisories = parsed_updateinfo.advisories,
        .advisory_references = parsed_updateinfo.references,
        .advisory_packages = parsed_updateinfo.packages,
    };

    for (parsed_repomd.pRecords) |record| {
        const raw_type = spanZ(record.pszType) orelse continue;
        switch (kindFromRawType(raw_type)) {
            .filelists => repo.has_filelists = true,
            .other => repo.has_other = true,
            .updateinfo => repo.has_updateinfo = true,
            else => {},
        }
    }

    return repo;
}

pub fn kindFromRawType(raw_type: []const u8) RecordKind {
    if (std.mem.eql(u8, raw_type, "primary")) return .primary;
    if (std.mem.eql(u8, raw_type, "filelists")) return .filelists;
    if (std.mem.eql(u8, raw_type, "other")) return .other;
    if (std.mem.startsWith(u8, raw_type, "updateinfo")) return .updateinfo;
    return .unknown;
}

pub fn advisoryKindFromType(raw_type: []const u8) AdvisoryKind {
    if (std.ascii.eqlIgnoreCase(raw_type, "security")) return .security;
    if (std.ascii.eqlIgnoreCase(raw_type, "bugfix")) return .bugfix;
    if (std.ascii.eqlIgnoreCase(raw_type, "enhancement")) return .enhancement;
    return .unknown;
}

pub fn advisoryReferenceKindFromType(raw_type: []const u8) AdvisoryReferenceKind {
    if (std.ascii.eqlIgnoreCase(raw_type, "bugzilla")) return .bugzilla;
    if (std.ascii.eqlIgnoreCase(raw_type, "cve")) return .cve;
    if (std.ascii.eqlIgnoreCase(raw_type, "vendor")) return .vendor;
    return .other;
}

pub fn dupZ(allocator: std.mem.Allocator, bytes: []const u8) ![:0]const u8 {
    const out = try allocator.allocSentinel(u8, bytes.len, 0);
    @memcpy(out[0..bytes.len], bytes);
    return out;
}

pub fn dup(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    return allocator.dupe(u8, bytes);
}

pub fn spanZ(value: ?[*:0]const u8) ?[]const u8 {
    const ptr = value orelse return null;
    return std.mem.span(ptr);
}

pub fn compareOpFromFlags(raw_flags: []const u8) ?CompareOp {
    if (std.ascii.eqlIgnoreCase(raw_flags, "EQ")) return .eq;
    if (std.ascii.eqlIgnoreCase(raw_flags, "LT")) return .lt;
    if (std.ascii.eqlIgnoreCase(raw_flags, "LE")) return .le;
    if (std.ascii.eqlIgnoreCase(raw_flags, "GT")) return .gt;
    if (std.ascii.eqlIgnoreCase(raw_flags, "GE")) return .ge;
    return null;
}

const UriReference = struct {
    scheme: ?[]const u8 = null,
    has_authority: bool = false,
    authority: []const u8 = "",
    path: []const u8 = "",
    query: ?[]const u8 = null,
    fragment: ?[]const u8 = null,
};

const NormalizedUriPath = struct {
    allocation: []u8,
    path: []const u8,
};

fn resolveUriReference(
    allocator: std.mem.Allocator,
    base: ?[]const u8,
    reference: []const u8,
    base_as_directory: bool,
) ![]const u8 {
    const base_ref = if (base) |value|
        try parseUriReference(value)
    else
        UriReference{};
    const reference_ref = try parseUriReference(reference);

    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();
    var normalized_path: ?NormalizedUriPath = null;
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
        normalized_path = try normalizeUriPath(
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
        normalized_path = try normalizeUriPath(
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
            const preserve_parent = scheme == null and !has_authority;
            if (reference_ref.path[0] == '/') {
                normalized_path = try normalizeUriPath(
                    allocator,
                    reference_ref.path,
                    preserve_parent,
                );
            } else {
                merged_path = try mergeUriPaths(
                    allocator,
                    base_ref,
                    reference_ref.path,
                    base_as_directory,
                );
                normalized_path = try normalizeUriPath(
                    allocator,
                    merged_path.?,
                    preserve_parent,
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
    return output.toOwnedSlice();
}

fn parseUriReference(text: []const u8) !UriReference {
    var result = UriReference{};
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
    if (findUriSchemeEnd(path_and_authority)) |scheme_end| {
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
    try validateUriPercentEscapes(text);
    return result;
}

fn findUriSchemeEnd(text: []const u8) ?usize {
    const colon = std.mem.indexOfScalar(u8, text, ':') orelse return null;
    const first_slash = std.mem.indexOfScalar(u8, text, '/') orelse text.len;
    if (colon > first_slash or colon == 0 or
        !std.ascii.isAlphabetic(text[0]))
    {
        return null;
    }
    for (text[1..colon]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and
            byte != '+' and byte != '-' and byte != '.')
        {
            return null;
        }
    }
    return colon;
}

fn validateUriPercentEscapes(text: []const u8) !void {
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        if (text[index] != '%') continue;
        if (index + 2 >= text.len or
            !isUriHex(text[index + 1]) or
            !isUriHex(text[index + 2]))
        {
            return error.InvalidUri;
        }
        index += 2;
    }
}

fn mergeUriPaths(
    allocator: std.mem.Allocator,
    base: UriReference,
    reference_path: []const u8,
    base_as_directory: bool,
) ![]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();
    if (base.has_authority and base.path.len == 0) {
        try output.append('/');
    } else if (base_as_directory) {
        try output.appendSlice(base.path);
        if (base.path.len != 0 and !std.mem.endsWith(u8, base.path, "/")) {
            try output.append('/');
        }
    } else if (std.mem.lastIndexOfScalar(u8, base.path, '/')) |slash| {
        try output.appendSlice(base.path[0 .. slash + 1]);
    }
    try output.appendSlice(reference_path);
    return output.toOwnedSlice();
}

fn normalizeUriPath(
    allocator: std.mem.Allocator,
    input: []const u8,
    preserve_leading_parent: bool,
) !NormalizedUriPath {
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

    const allocation = try output.toOwnedSlice();
    return .{ .allocation = allocation, .path = allocation };
}

fn isUriHex(byte: u8) bool {
    return std.ascii.isDigit(byte) or
        (byte >= 'a' and byte <= 'f') or
        (byte >= 'A' and byte <= 'F');
}

fn uriResolutionAllocationFailureCase(
    allocator: std.mem.Allocator,
) !void {
    const resolved = try resolveUriReference(
        allocator,
        "../a/b/",
        "../../c///../d",
        false,
    );
    defer allocator.free(resolved);
}

test "package location resolver matches RFC 3986 normal and abnormal references" {
    const base = "http://a/b/c/d;p?q";
    // This table intentionally mirrors xml/uri.zig. model.zig must remain
    // independently importable by the standalone solver test modules.
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
        const actual = try resolveUriReference(
            std.testing.allocator,
            base,
            case.reference,
            false,
        );
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(case.expected, actual);
    }
}

test "package location resolver preserves terminal and relative parent paths" {
    const terminal_parent = try (PackageLocation{
        .href = "g/..",
        .xml_base = "http://a/b/c/",
    }).resolve(std.testing.allocator);
    defer std.testing.allocator.free(terminal_parent);
    try std.testing.expectEqualStrings("http://a/b/c/", terminal_parent);

    const terminal_current = try (PackageLocation{
        .href = "g/.",
        .xml_base = "http://a/b/c/",
    }).resolve(std.testing.allocator);
    defer std.testing.allocator.free(terminal_current);
    try std.testing.expectEqualStrings("http://a/b/c/g/", terminal_current);

    const beyond_relative_base = try (PackageLocation{
        .href = "../../../c/",
        .xml_base = "a/b/",
    }).resolve(std.testing.allocator);
    defer std.testing.allocator.free(beyond_relative_base);
    try std.testing.expectEqualStrings("../c/", beyond_relative_base);

    const cancelled = try resolveUriReference(
        std.testing.allocator,
        null,
        "a/../b",
        false,
    );
    defer std.testing.allocator.free(cancelled);
    try std.testing.expectEqualStrings("b", cancelled);

    const current_directory = try resolveUriReference(
        std.testing.allocator,
        null,
        "a/../",
        false,
    );
    defer std.testing.allocator.free(current_directory);
    try std.testing.expectEqualStrings("", current_directory);

    const cancelled_base = try resolveUriReference(
        std.testing.allocator,
        "a/",
        "../b",
        false,
    );
    defer std.testing.allocator.free(cancelled_base);
    try std.testing.expectEqualStrings("b", cancelled_base);

    const retained_empty = try resolveUriReference(
        std.testing.allocator,
        null,
        "a/..//b",
        false,
    );
    defer std.testing.allocator.free(retained_empty);
    try std.testing.expectEqualStrings("//b", retained_empty);

    const absolute_parent = try resolveUriReference(
        std.testing.allocator,
        null,
        "/a/b/..",
        false,
    );
    defer std.testing.allocator.free(absolute_parent);
    try std.testing.expectEqualStrings("/a/", absolute_parent);
}

test "package location resolution releases intermediate allocations" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        uriResolutionAllocationFailureCase,
        .{},
    );
}
