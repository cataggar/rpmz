const std = @import("std");
const metalink_xml = @import("metalink_xml");

const c = @cImport({
    @cInclude("builtin_plugins.h");
    @cInclude("nodes.h");
});

const allocator = std.heap.c_allocator;

const ERROR_TDNF_INVALID_PARAMETER: u32 = 1622;
const ERROR_TDNF_OUT_OF_MEMORY: u32 = 1612;
const ERROR_TDNF_INVALID_REPO_FILE: u32 = 1403;
const ERROR_TDNF_ALREADY_EXISTS: u32 = 1617;
const ERROR_TDNF_CHECKSUM_VALIDATION_FAILED: u32 = 2501;
const ERROR_TDNF_GPG_SIGNATURE_CHECK: u32 = 2004;
const ERROR_TDNF_METALINK_INVALID_FILE_NAME: u32 = 2704;
const ERROR_TDNF_METALINK_MISSING_FILE_SIZE: u32 = 2705;
const ERROR_TDNF_METALINK_MISSING_HASH_CONTENT: u32 = 2707;
const ERROR_TDNF_METALINK_MISSING_URL_ATTR: u32 = 2708;
const ERROR_TDNF_METALINK_MISSING_URL_CONTENT: u32 = 2709;

const max_file_size = 64 * 1024 * 1024;
const max_kbx_blob_size = 5 * 1024 * 1024;
const repomd_name = "repomd.xml";
const repomd_path = "repodata/repomd.xml";

const MetalinkHash = struct {
    kind: []u8,
    value: []u8,

    fn deinit(self: *MetalinkHash) void {
        allocator.free(self.kind);
        allocator.free(self.value);
    }
};

const MetalinkUrl = struct {
    value: []u8,
    preference: i32,

    fn deinit(self: *MetalinkUrl) void {
        allocator.free(self.value);
    }
};

const ParsedMetalink = struct {
    hashes: std.array_list.Managed(MetalinkHash),
    urls: std.array_list.Managed(MetalinkUrl),
    filename_seen: bool = false,
    size: i64 = 0,

    fn init() ParsedMetalink {
        return .{
            .hashes = .init(allocator),
            .urls = .init(allocator),
        };
    }

    fn deinit(self: *ParsedMetalink) void {
        for (self.hashes.items) |*hash| hash.deinit();
        for (self.urls.items) |*url| url.deinit();
        self.hashes.deinit();
        self.urls.deinit();
    }
};

const MetalinkRepo = struct {
    id: []u8,
    parsed: ?ParsedMetalink = null,

    fn deinit(self: *MetalinkRepo) void {
        allocator.free(self.id);
        if (self.parsed) |*parsed| parsed.deinit();
    }
};

const MetalinkState = struct {
    tdnf: ?*anyopaque,
    repos: std.array_list.Managed(MetalinkRepo),

    fn init(tdnf: ?*anyopaque) MetalinkState {
        return .{ .tdnf = tdnf, .repos = .init(allocator) };
    }

    fn deinit(self: *MetalinkState) void {
        for (self.repos.items) |*repo| repo.deinit();
        self.repos.deinit();
    }

    fn find(self: *MetalinkState, id: []const u8) ?*MetalinkRepo {
        for (self.repos.items) |*repo| {
            if (std.mem.eql(u8, repo.id, id)) return repo;
        }
        return null;
    }
};

const RepoGPGCheckState = struct {
    tdnf: ?*anyopaque,
    repos: std.array_list.Managed([]u8),

    fn init(tdnf: ?*anyopaque) RepoGPGCheckState {
        return .{ .tdnf = tdnf, .repos = .init(allocator) };
    }

    fn deinit(self: *RepoGPGCheckState) void {
        for (self.repos.items) |id| allocator.free(id);
        self.repos.deinit();
    }

    fn has(self: *const RepoGPGCheckState, id: []const u8) bool {
        for (self.repos.items) |candidate| {
            if (std.mem.eql(u8, candidate, id)) return true;
        }
        return false;
    }
};

fn metalinkState(handle: ?*anyopaque) ?*MetalinkState {
    return @ptrCast(@alignCast(handle orelse return null));
}

fn repoGPGCheckState(handle: ?*anyopaque) ?*RepoGPGCheckState {
    return @ptrCast(@alignCast(handle orelse return null));
}

fn cSpan(ptr: anytype) []const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(ptr)));
}

fn boolValue(value: []const u8) bool {
    return std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

fn readFile(path: []const u8) ![]u8 {
    var io_state: std.Io.Threaded = .init(allocator, .{});
    defer io_state.deinit();
    return std.Io.Dir.cwd().readFileAlloc(
        io_state.io(),
        path,
        allocator,
        .limited(max_file_size),
    );
}

fn sectionHasOption(
    section: *const c.struct_cnfnode,
    option: []const u8,
    require_true: bool,
) bool {
    var node = section.first_child;
    while (node != null) : (node = node.*.next) {
        if (node.*.name == null or node.*.value == null) continue;
        const name = cSpan(node.*.name);
        if (name.len == 0 or name[0] == '.') continue;
        if (!std.mem.eql(u8, name, option)) continue;
        return !require_true or boolValue(cSpan(node.*.value));
    }
    return false;
}

export fn BuiltinMetalinkCreate(
    tdnf: ?*anyopaque,
    out_handle: ?*?*anyopaque,
) u32 {
    const out = out_handle orelse return ERROR_TDNF_INVALID_PARAMETER;
    if (tdnf == null) return ERROR_TDNF_INVALID_PARAMETER;
    const state = allocator.create(MetalinkState) catch return ERROR_TDNF_OUT_OF_MEMORY;
    state.* = .init(tdnf);
    out.* = state;
    return 0;
}

export fn BuiltinMetalinkDestroy(handle: ?*anyopaque) void {
    const state = metalinkState(handle) orelse return;
    state.deinit();
    allocator.destroy(state);
}

export fn BuiltinMetalinkRepoConfig(
    handle: ?*anyopaque,
    section_ptr: ?*const c.struct_cnfnode,
) u32 {
    const state = metalinkState(handle) orelse return ERROR_TDNF_INVALID_PARAMETER;
    const section = section_ptr orelse return ERROR_TDNF_INVALID_PARAMETER;
    if (!sectionHasOption(section, "metalink", false)) return 0;
    if (section.name == null) return ERROR_TDNF_INVALID_PARAMETER;
    const id = cSpan(section.name);
    if (state.find(id) != null) return 0;
    const copy = allocator.dupe(u8, id) catch return ERROR_TDNF_OUT_OF_MEMORY;
    state.repos.append(.{ .id = copy }) catch {
        allocator.free(copy);
        return ERROR_TDNF_OUT_OF_MEMORY;
    };
    return 0;
}

export fn BuiltinMetalinkRepoMDDownloadStart(
    handle: ?*anyopaque,
    repo_id_ptr: ?[*:0]const u8,
    repo_data_dir_ptr: ?[*:0]const u8,
) u32 {
    const state = metalinkState(handle) orelse return ERROR_TDNF_INVALID_PARAMETER;
    const repo_id_z = repo_id_ptr orelse return ERROR_TDNF_INVALID_PARAMETER;
    const repo_data_dir_z = repo_data_dir_ptr orelse return ERROR_TDNF_INVALID_PARAMETER;
    const repo_id = std.mem.span(repo_id_z);
    const entry = state.find(repo_id) orelse return 0;

    var repo: ?*anyopaque = null;
    var rc = c.BuiltinFindRepo(state.tdnf, repo_id_z, &repo);
    if (rc != 0) return rc;
    if (repo == null) return ERROR_TDNF_INVALID_PARAMETER;

    const metalink_path = std.fmt.allocPrintSentinel(
        allocator,
        "{s}/metalink",
        .{std.mem.span(repo_data_dir_z)},
        0,
    ) catch return ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(metalink_path);

    if (c.BuiltinRefreshRequested(state.tdnf) != 0 or
        c.BuiltinFileExists(metalink_path.ptr) == 0)
    {
        rc = c.BuiltinMakeDirs(repo_data_dir_z);
        if (rc != 0 and rc != ERROR_TDNF_ALREADY_EXISTS) return rc;
        rc = c.BuiltinDownloadMetalink(
            state.tdnf,
            repo,
            metalink_path.ptr,
        );
        if (rc != 0) return rc;
    }

    const bytes = readFile(metalink_path) catch return ERROR_TDNF_INVALID_REPO_FILE;
    defer allocator.free(bytes);
    var parsed = ParsedMetalink.init();
    const callbacks = metalink_xml.TDNF_METALINK_XML_CALLBACKS{
        .pfnFile = metalinkOnFile,
        .pfnSize = metalinkOnSize,
        .pfnHash = metalinkOnHash,
        .pfnUrl = metalinkOnUrl,
    };
    rc = metalink_xml.parseBuffer(
        bytes.ptr,
        bytes.len,
        &callbacks,
        &parsed,
    );
    if (rc != 0) {
        parsed.deinit();
        return rc;
    }

    std.mem.sort(MetalinkUrl, parsed.urls.items, {}, struct {
        fn lessThan(_: void, a: MetalinkUrl, b: MetalinkUrl) bool {
            return a.preference > b.preference;
        }
    }.lessThan);

    rc = installBaseUrls(repo, parsed.urls.items);
    if (rc != 0) {
        parsed.deinit();
        return rc;
    }
    if (entry.parsed) |*old| old.deinit();
    entry.parsed = parsed;
    return 0;
}

export fn BuiltinMetalinkRepoMDDownloadEnd(
    handle: ?*anyopaque,
    repo_id_ptr: ?[*:0]const u8,
    repomd_file_ptr: ?[*:0]const u8,
) u32 {
    const state = metalinkState(handle) orelse return ERROR_TDNF_INVALID_PARAMETER;
    const repo_id_z = repo_id_ptr orelse return ERROR_TDNF_INVALID_PARAMETER;
    const repomd_file_z = repomd_file_ptr orelse return ERROR_TDNF_INVALID_PARAMETER;
    const entry = state.find(std.mem.span(repo_id_z)) orelse return 0;
    const parsed = &(entry.parsed orelse return ERROR_TDNF_INVALID_PARAMETER);
    return checkMetalinkHashes(repomd_file_z, parsed.hashes.items);
}

fn metalinkOnFile(ctx: ?*anyopaque, name: [*:0]const u8) callconv(.c) u32 {
    const parsed: *ParsedMetalink = @ptrCast(@alignCast(ctx orelse
        return ERROR_TDNF_INVALID_PARAMETER));
    if (!std.mem.eql(u8, std.mem.span(name), repomd_name))
        return ERROR_TDNF_METALINK_INVALID_FILE_NAME;
    parsed.filename_seen = true;
    return 0;
}

fn metalinkOnSize(
    ctx: ?*anyopaque,
    text_ptr: [*]const u8,
    len: usize,
) callconv(.c) u32 {
    const parsed: *ParsedMetalink = @ptrCast(@alignCast(ctx orelse
        return ERROR_TDNF_INVALID_PARAMETER));
    const text = text_ptr[0..len];
    var digits: usize = 0;
    while (digits < text.len and std.ascii.isDigit(text[digits])) : (digits += 1) {}
    if (digits == 0) return ERROR_TDNF_METALINK_MISSING_FILE_SIZE;
    parsed.size = std.fmt.parseInt(i64, text[0..digits], 10) catch
        return ERROR_TDNF_METALINK_MISSING_FILE_SIZE;
    return 0;
}

fn metalinkOnHash(
    ctx: ?*anyopaque,
    kind_ptr: [*:0]const u8,
    text_ptr: [*]const u8,
    len: usize,
) callconv(.c) u32 {
    const parsed: *ParsedMetalink = @ptrCast(@alignCast(ctx orelse
        return ERROR_TDNF_INVALID_PARAMETER));
    if (len == 0) return ERROR_TDNF_METALINK_MISSING_HASH_CONTENT;
    const kind = allocator.dupe(u8, std.mem.span(kind_ptr)) catch
        return ERROR_TDNF_OUT_OF_MEMORY;
    const value = allocator.dupe(u8, text_ptr[0..len]) catch {
        allocator.free(kind);
        return ERROR_TDNF_OUT_OF_MEMORY;
    };
    parsed.hashes.append(.{ .kind = kind, .value = value }) catch {
        allocator.free(kind);
        allocator.free(value);
        return ERROR_TDNF_OUT_OF_MEMORY;
    };
    return 0;
}

fn metalinkOnUrl(
    ctx: ?*anyopaque,
    protocol: ?[*:0]const u8,
    url_type: ?[*:0]const u8,
    location: ?[*:0]const u8,
    ranking_ptr: ?[*:0]const u8,
    ranking_is_priority: bool,
    text_ptr: [*]const u8,
    len: usize,
) callconv(.c) u32 {
    _ = protocol;
    _ = url_type;
    _ = location;
    const parsed: *ParsedMetalink = @ptrCast(@alignCast(ctx orelse
        return ERROR_TDNF_INVALID_PARAMETER));
    if (len == 0) return ERROR_TDNF_METALINK_MISSING_URL_CONTENT;

    var preference: i32 = 0;
    if (ranking_ptr) |ranking_z| {
        const ranking = std.mem.span(ranking_z);
        if (ranking_is_priority) {
            const priority = std.fmt.parseInt(i32, ranking, 10) catch
                return ERROR_TDNF_INVALID_PARAMETER;
            if (priority <= 0 or priority == std.math.maxInt(i32))
                return ERROR_TDNF_METALINK_MISSING_URL_ATTR;
            preference = std.math.maxInt(i32) - priority;
        } else {
            preference = std.fmt.parseInt(i32, ranking, 10) catch
                return ERROR_TDNF_INVALID_PARAMETER;
            if (preference < 0 or preference > 100)
                return ERROR_TDNF_METALINK_MISSING_URL_ATTR;
        }
    }

    const value = allocator.dupe(u8, text_ptr[0..len]) catch
        return ERROR_TDNF_OUT_OF_MEMORY;
    parsed.urls.append(.{
        .value = value,
        .preference = preference,
    }) catch {
        allocator.free(value);
        return ERROR_TDNF_OUT_OF_MEMORY;
    };
    return 0;
}

fn installBaseUrls(repo: ?*anyopaque, urls: []const MetalinkUrl) u32 {
    var raw: ?*anyopaque = null;
    var rc = c.TDNFAllocateMemory(
        urls.len + 1,
        @sizeOf(?[*:0]u8),
        &raw,
    );
    if (rc != 0) return rc;
    const array: [*][*c]u8 = @ptrCast(@alignCast(raw.?));
    @memset(array[0 .. urls.len + 1], null);

    var count: usize = 0;
    for (urls) |url| {
        if (!std.mem.endsWith(u8, url.value, repomd_path)) {
            c.TDNFFreeStringArray(@ptrCast(array));
            return ERROR_TDNF_INVALID_REPO_FILE;
        }
        const base = url.value[0 .. url.value.len - repomd_path.len];
        const base_z = allocator.dupeZ(u8, base) catch {
            c.TDNFFreeStringArray(@ptrCast(array));
            return ERROR_TDNF_OUT_OF_MEMORY;
        };
        defer allocator.free(base_z);
        var destination: [*c]u8 = null;
        rc = c.TDNFAllocateString(base_z.ptr, &destination);
        if (rc != 0) {
            c.TDNFFreeStringArray(@ptrCast(array));
            return rc;
        }
        array[count] = destination;
        count += 1;
    }
    c.BuiltinReplaceBaseUrls(repo, @ptrCast(array));
    return 0;
}

fn hashKind(kind: []const u8) ?struct { rank: u8, c_kind: c_int, len: usize } {
    if (std.ascii.eqlIgnoreCase(kind, "md5"))
        return .{ .rank = 0, .c_kind = c.TDNF_HASH_MD5, .len = 16 };
    if (std.ascii.eqlIgnoreCase(kind, "sha1") or
        std.ascii.eqlIgnoreCase(kind, "sha-1"))
        return .{ .rank = 1, .c_kind = c.TDNF_HASH_SHA1, .len = 20 };
    if (std.ascii.eqlIgnoreCase(kind, "sha256") or
        std.ascii.eqlIgnoreCase(kind, "sha-256"))
        return .{ .rank = 2, .c_kind = c.TDNF_HASH_SHA256, .len = 32 };
    if (std.ascii.eqlIgnoreCase(kind, "sha512") or
        std.ascii.eqlIgnoreCase(kind, "sha-512"))
        return .{ .rank = 3, .c_kind = c.TDNF_HASH_SHA512, .len = 64 };
    return null;
}

fn checkMetalinkHashes(path: [*:0]const u8, hashes: []const MetalinkHash) u32 {
    var best: ?u8 = null;
    for (hashes) |hash| {
        const kind = hashKind(hash.kind) orelse continue;
        if (best == null or kind.rank > best.?) best = kind.rank;
    }
    const best_rank = best orelse return ERROR_TDNF_INVALID_REPO_FILE;

    var digest: [64]u8 = @splat(0);
    for (hashes) |hash| {
        const kind = hashKind(hash.kind) orelse continue;
        if (kind.rank != best_rank) continue;
        const value_z = allocator.dupeZ(u8, hash.value) catch
            return ERROR_TDNF_OUT_OF_MEMORY;
        defer allocator.free(value_z);
        if (c.TDNFCheckHexDigest(value_z.ptr, @intCast(kind.len)) == 0) continue;
        var rc = c.TDNFChecksumFromHexDigest(value_z.ptr, &digest);
        if (rc != 0) return rc;
        rc = c.TDNFCheckHash(path, &digest, kind.c_kind);
        if (rc == 0) return 0;
        if (rc != ERROR_TDNF_CHECKSUM_VALIDATION_FAILED) return rc;
    }
    return ERROR_TDNF_CHECKSUM_VALIDATION_FAILED;
}

export fn BuiltinRepoGPGCheckCreate(
    tdnf: ?*anyopaque,
    out_handle: ?*?*anyopaque,
) u32 {
    const out = out_handle orelse return ERROR_TDNF_INVALID_PARAMETER;
    if (tdnf == null) return ERROR_TDNF_INVALID_PARAMETER;
    const state = allocator.create(RepoGPGCheckState) catch
        return ERROR_TDNF_OUT_OF_MEMORY;
    state.* = .init(tdnf);
    out.* = state;
    return 0;
}

export fn BuiltinRepoGPGCheckDestroy(handle: ?*anyopaque) void {
    const state = repoGPGCheckState(handle) orelse return;
    state.deinit();
    allocator.destroy(state);
}

export fn BuiltinRepoGPGCheckRepoConfig(
    handle: ?*anyopaque,
    section_ptr: ?*const c.struct_cnfnode,
) u32 {
    const state = repoGPGCheckState(handle) orelse
        return ERROR_TDNF_INVALID_PARAMETER;
    const section = section_ptr orelse return ERROR_TDNF_INVALID_PARAMETER;
    if (!sectionHasOption(section, "repo_gpgcheck", true)) return 0;
    if (section.name == null) return ERROR_TDNF_INVALID_PARAMETER;
    const id = cSpan(section.name);
    if (state.has(id)) return 0;
    const copy = allocator.dupe(u8, id) catch return ERROR_TDNF_OUT_OF_MEMORY;
    state.repos.append(copy) catch {
        allocator.free(copy);
        return ERROR_TDNF_OUT_OF_MEMORY;
    };
    return 0;
}

export fn BuiltinRepoGPGCheckRepoMDDownloadEnd(
    handle: ?*anyopaque,
    repo_id_ptr: ?[*:0]const u8,
    repomd_file_ptr: ?[*:0]const u8,
) u32 {
    const state = repoGPGCheckState(handle) orelse
        return ERROR_TDNF_INVALID_PARAMETER;
    const repo_id_z = repo_id_ptr orelse return ERROR_TDNF_INVALID_PARAMETER;
    const repomd_file_z = repomd_file_ptr orelse
        return ERROR_TDNF_INVALID_PARAMETER;
    if (!state.has(std.mem.span(repo_id_z))) return 0;

    var repo: ?*anyopaque = null;
    var rc = c.BuiltinFindRepo(state.tdnf, repo_id_z, &repo);
    if (rc != 0) return rc;
    if (repo == null) return ERROR_TDNF_INVALID_PARAMETER;

    const signature_path = std.fmt.allocPrintSentinel(
        allocator,
        "{s}.asc",
        .{std.mem.span(repomd_file_z)},
        0,
    ) catch return ERROR_TDNF_OUT_OF_MEMORY;
    defer allocator.free(signature_path);
    const signature_location: [:0]const u8 = repomd_path ++ ".asc";
    rc = c.BuiltinDownloadRepoFile(
        state.tdnf,
        repo,
        signature_location.ptr,
        signature_path.ptr,
        repo_id_z,
    );
    if (rc != 0) return rc;
    defer c.BuiltinUnlink(signature_path.ptr);

    const signed_data = readFile(std.mem.span(repomd_file_z)) catch
        return ERROR_TDNF_GPG_SIGNATURE_CHECK;
    defer allocator.free(signed_data);
    const armored_signature = readFile(signature_path) catch
        return ERROR_TDNF_GPG_SIGNATURE_CHECK;
    defer allocator.free(armored_signature);
    var keys = loadAmbientKeys() catch
        return ERROR_TDNF_GPG_SIGNATURE_CHECK;
    defer keys.deinit();
    const key_ptrs = allocator.alloc(?[*]const u8, keys.blobs.items.len) catch
        return ERROR_TDNF_GPG_SIGNATURE_CHECK;
    defer allocator.free(key_ptrs);
    const key_lens = allocator.alloc(usize, keys.blobs.items.len) catch
        return ERROR_TDNF_GPG_SIGNATURE_CHECK;
    defer allocator.free(key_lens);
    for (keys.blobs.items, 0..) |key, i| {
        key_ptrs[i] = key.ptr;
        key_lens[i] = key.len;
    }
    const status = c.rpmzig_verify_detached_armored(
        armored_signature.ptr,
        armored_signature.len,
        signed_data.ptr,
        signed_data.len,
        if (key_ptrs.len == 0) null else key_ptrs.ptr,
        if (key_lens.len == 0) null else key_lens.ptr,
        key_ptrs.len,
    );
    return if (status == 0) 0 else ERROR_TDNF_GPG_SIGNATURE_CHECK;
}

const KeySet = struct {
    blobs: std.array_list.Managed([]u8),

    fn init() KeySet {
        return .{ .blobs = .init(allocator) };
    }

    fn deinit(self: *KeySet) void {
        for (self.blobs.items) |blob| allocator.free(blob);
        self.blobs.deinit();
    }
};

fn loadAmbientKeys() !KeySet {
    var keys = KeySet.init();
    errdefer keys.deinit();

    const gnupg_home = c.BuiltinGetEnv("GNUPGHOME");
    const user_home = c.BuiltinGetEnv("HOME");
    const home = if (gnupg_home != null)
        cSpan(gnupg_home)
    else if (user_home != null)
        try std.fmt.allocPrint(allocator, "{s}/.gnupg", .{cSpan(user_home)})
    else
        return keys;
    const owns_home = gnupg_home == null;
    defer if (owns_home) allocator.free(home);

    const kbx_path = try std.fmt.allocPrint(allocator, "{s}/pubring.kbx", .{home});
    defer allocator.free(kbx_path);
    if (readFile(kbx_path)) |contents| {
        defer allocator.free(contents);
        try appendKbxKeys(&keys, contents);
    } else |_| {}

    const legacy_path = try std.fmt.allocPrint(allocator, "{s}/pubring.gpg", .{home});
    defer allocator.free(legacy_path);
    if (readFile(legacy_path)) |contents| {
        try keys.blobs.append(contents);
    } else |_| {}
    return keys;
}

fn appendKbxKeys(keys: *KeySet, contents: []const u8) !void {
    var offset: usize = 0;
    while (offset < contents.len) {
        if (contents.len - offset < 5) return error.InvalidKeybox;
        const blob_len = std.mem.readInt(u32, contents[offset..][0..4], .big);
        if (blob_len < 5 or blob_len > max_kbx_blob_size)
            return error.InvalidKeybox;
        const end = std.math.add(usize, offset, blob_len) catch
            return error.InvalidKeybox;
        if (end > contents.len) return error.InvalidKeybox;
        const blob = contents[offset..end];
        if (blob[4] == 2) {
            if (blob.len < 40 or (blob[5] != 1 and blob[5] != 2))
                return error.InvalidKeybox;
            const raw_offset = std.mem.readInt(u32, blob[8..12], .big);
            const raw_len = std.mem.readInt(u32, blob[12..16], .big);
            const raw_end = std.math.add(usize, raw_offset, raw_len) catch
                return error.InvalidKeybox;
            if (raw_offset < 20 or raw_end > blob.len or blob.len - raw_end < 20)
                return error.InvalidKeybox;
            var digest: [20]u8 = undefined;
            std.crypto.hash.Sha1.hash(blob[0..raw_end], &digest, .{});
            if (!std.crypto.timing_safe.eql(
                [20]u8,
                digest,
                blob[blob.len - 20 ..][0..20].*,
            )) return error.InvalidKeybox;
            try keys.blobs.append(try allocator.dupe(
                u8,
                blob[raw_offset..raw_end],
            ));
        }
        offset = end;
    }
}
