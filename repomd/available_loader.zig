const std = @import("std");
const filelists_xml = @import("filelists.zig");
const metadata_integrity = @import("metadata_integrity.zig");
const model = @import("model.zig");
const other_xml = @import("other.zig");
const primary_xml = @import("primary.zig");
const repomd_xml = @import("repomd.zig");

pub const solv_cache_identity_domain = "tdnf-solv-content-v3";
pub const solv_cache_options_domain = "tdnf-solv-cache-options/v1";
const updateinfo_xml = @import("updateinfo.zig");

const max_metadata_bytes = 256 * 1024 * 1024;
const xz_max_decoder_scratch_bytes = 256 * 1024 * 1024;
// Legacy loading ignores advertised open-size, but never these local ceilings.
const legacy_max_output_bytes = 1024 * 1024 * 1024;
const legacy_max_expansion_ratio = 4096;
const legacy_expansion_slack = 64 * 1024 * 1024;
const decompression_writer_history_bytes = 64 * 1024;
// std's zstd decoder decodes through a caller-supplied window buffer. When that
// buffer is empty the destination writer has to hold the whole window instead,
// which would push the temporary output budget far past the metadata size. Own
// the window explicitly so the output budget stays proportional to the output.
const zstd_max_decoder_scratch_bytes =
    std.compress.zstd.default_window_len +
    std.compress.zstd.block_size_max;
const xz_work_base_units = 4096;
const xz_work_input_quantum = 4096;
const xz_work_output_quantum = 1024 * 1024;
const xz_stream_work_units = 4;
const xz_block_work_units = 8;
const xz_property_reset_work_units = 4;
threadlocal var raw_scratch_live: usize = 0;
threadlocal var raw_scratch_peak: usize = 0;

fn trackRawScratchAlloc(length: usize) void {
    raw_scratch_live += length;
    raw_scratch_peak = @max(raw_scratch_peak, raw_scratch_live);
}

fn trackRawScratchFree(length: usize) void {
    raw_scratch_live -= length;
}

const DecompressError = error{
    OutOfMemory,
    StreamTooLong,
    UnsupportedCompressor,
    DecompressFailed,
};

pub const LoadError = error{
    InvalidRepoMetadata,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    NameTooLong,
    BadPathName,
    NotDir,
    IsDir,
    FileTooBig,
    StreamTooLong,
    FileSystemIo,
    UnsupportedCompressor,
    DecompressFailed,
};

const BudgetAllocator = struct {
    backing: std.mem.Allocator,
    budget: usize,
    live: usize = 0,
    peak: usize = 0,
    budget_exhausted: bool = false,
    backing_out_of_memory: bool = false,

    fn init(backing: std.mem.Allocator, budget: usize) BudgetAllocator {
        return .{ .backing = backing, .budget = budget };
    }

    fn allocator(self: *BudgetAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn alloc(
        raw: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *BudgetAllocator = @ptrCast(@alignCast(raw));
        if (len > self.budget -| self.live) {
            self.budget_exhausted = true;
            return null;
        }
        const result = self.backing.rawAlloc(
            len,
            alignment,
            ret_addr,
        ) orelse {
            self.backing_out_of_memory = true;
            return null;
        };
        self.live += len;
        self.peak = @max(self.peak, self.live);
        return result;
    }

    fn resize(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *BudgetAllocator = @ptrCast(@alignCast(raw));
        if (new_len > memory.len and
            new_len - memory.len > self.budget -| self.live)
        {
            self.budget_exhausted = true;
            return false;
        }
        if (!self.backing.rawResize(
            memory,
            alignment,
            new_len,
            ret_addr,
        )) return false;
        self.live = self.live - memory.len + new_len;
        self.peak = @max(self.peak, self.live);
        return true;
    }

    fn remap(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *BudgetAllocator = @ptrCast(@alignCast(raw));
        if (new_len > memory.len and
            new_len - memory.len > self.budget -| self.live)
        {
            self.budget_exhausted = true;
            return null;
        }
        const result = self.backing.rawRemap(
            memory,
            alignment,
            new_len,
            ret_addr,
        ) orelse return null;
        self.live = self.live - memory.len + new_len;
        self.peak = @max(self.peak, self.live);
        return result;
    }

    fn free(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) void {
        const self: *BudgetAllocator = @ptrCast(@alignCast(raw));
        self.backing.rawFree(memory, alignment, ret_addr);
        self.live -= memory.len;
    }
};

/// Zig 0.16's LZMA reset frees its literal table before allocating the
/// replacement. Reserve the maximum table so that replacement cannot fail
/// after invalidating the stdlib decoder.
const LzmaLiteralAllocator = struct {
    const max_literal_probability_elements = 0x300 * 16;

    backing: *BudgetAllocator,
    storage: []u16,
    in_use: bool = false,

    fn init(backing: *BudgetAllocator) DecompressError!LzmaLiteralAllocator {
        const storage = backing.allocator().alloc(
            u16,
            max_literal_probability_elements,
        ) catch return decoderAllocatorError(backing);
        return .{
            .backing = backing,
            .storage = storage,
        };
    }

    fn deinit(self: *LzmaLiteralAllocator) void {
        self.backing.allocator().free(self.storage);
        self.* = undefined;
    }

    fn allocator(self: *LzmaLiteralAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn isLiteralProbabilityAllocation(
        len: usize,
        alignment: std.mem.Alignment,
    ) bool {
        if (alignment != .@"2" or len < 0x300 * @sizeOf(u16) or
            len > max_literal_probability_elements * @sizeOf(u16))
        {
            return false;
        }
        const scale = len / (0x300 * @sizeOf(u16));
        return len % (0x300 * @sizeOf(u16)) == 0 and
            std.math.isPowerOfTwo(scale);
    }

    fn isStorage(self: *const LzmaLiteralAllocator, memory: []u8) bool {
        return memory.ptr == @as([*]u8, @ptrCast(self.storage.ptr));
    }

    fn alloc(
        raw: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *LzmaLiteralAllocator = @ptrCast(@alignCast(raw));
        if (isLiteralProbabilityAllocation(len, alignment) and
            !self.in_use)
        {
            self.in_use = true;
            return @ptrCast(self.storage.ptr);
        }
        return self.backing.allocator().rawAlloc(
            len,
            alignment,
            ret_addr,
        );
    }

    fn resize(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *LzmaLiteralAllocator = @ptrCast(@alignCast(raw));
        if (self.isStorage(memory)) {
            if (new_len > self.storage.len * @sizeOf(u16)) return false;
            return true;
        }
        return self.backing.allocator().rawResize(
            memory,
            alignment,
            new_len,
            ret_addr,
        );
    }

    fn remap(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *LzmaLiteralAllocator = @ptrCast(@alignCast(raw));
        if (self.isStorage(memory)) {
            if (new_len > self.storage.len * @sizeOf(u16)) return null;
            return memory.ptr;
        }
        return self.backing.allocator().rawRemap(
            memory,
            alignment,
            new_len,
            ret_addr,
        );
    }

    fn free(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) void {
        const self: *LzmaLiteralAllocator = @ptrCast(@alignCast(raw));
        if (self.isStorage(memory)) {
            self.in_use = false;
            return;
        }
        self.backing.allocator().rawFree(
            memory,
            alignment,
            ret_addr,
        );
    }
};

const DecompressedOutputBudget = struct {
    limit: usize,
    used: usize = 0,

    fn init(limit: usize) DecompressedOutputBudget {
        return .{ .limit = limit };
    }

    fn fileLimit(
        self: *const DecompressedOutputBudget,
        per_file_limit: usize,
    ) DecompressError!usize {
        const remaining = self.limit -| self.used;
        const aggregate_limit = std.math.add(
            usize,
            remaining,
            1,
        ) catch std.math.maxInt(usize);
        return @min(per_file_limit, aggregate_limit);
    }

    fn consume(
        self: *DecompressedOutputBudget,
        length: usize,
    ) DecompressError!void {
        if (length > self.limit -| self.used) return error.StreamTooLong;
        self.used += length;
    }
};

const DecoderStats = struct {
    budget: usize = 0,
    peak: usize = 0,
    max_distance: usize = 0,
};

const TemporaryOutputStats = struct {
    budget: usize = 0,
    peak: usize = 0,
    live_after_release: usize = 0,
};

pub const Paths = struct {
    repomd: []const u8,
    primary: []const u8,
    filelists: ?[]const u8 = null,
    updateinfo: ?[]const u8 = null,
    other: ?[]const u8 = null,
};

pub const CacheOptions = struct {
    include_filelists: bool = true,
    include_updateinfo: bool = false,
    include_other: bool = false,
};

pub fn bindSolvCacheCookie(
    content_cookie: [32]u8,
    options: CacheOptions,
) [32]u8 {
    var digest: [32]u8 = undefined;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(solv_cache_options_domain);
    hasher.update("\x00");
    hasher.update(&content_cookie);
    hasher.update(&.{
        @intFromBool(options.include_filelists),
        @intFromBool(options.include_updateinfo),
        @intFromBool(options.include_other),
    });
    hasher.final(&digest);
    return digest;
}

pub fn solvCacheCookie(
    repomd_bytes: []const u8,
    options: CacheOptions,
) [32]u8 {
    var content_cookie: [32]u8 = undefined;
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(solv_cache_identity_domain);
    hasher.update(repomd_bytes);
    hasher.final(&content_cookie);
    return bindSolvCacheCookie(content_cookie, options);
}

/// Cache metadata loaded under one opened cache root. repomd_bytes is the
/// exact byte sequence parsed into repository and is never re-read by users
/// that need to identify this cache snapshot.
pub const CacheModel = struct {
    repository: model.RepositoryModel,
    repomd_bytes: []const u8,
    /// Parallel to repository.records; Record itself has a stable C ABI.
    record_xml_bases: []const ?[]const u8,
};

pub const PathModel = struct {
    repository: model.RepositoryModel,
    repomd_bytes: []const u8,
};

/// Move-only owner for a repository model and every slice it borrows.
pub const LoadedRepository = struct {
    arena_state: std.heap.ArenaAllocator,
    repository: model.RepositoryModel,

    pub fn deinit(self: *LoadedRepository) void {
        self.arena_state.deinit();
        self.* = undefined;
    }
};

pub fn load(
    parent_allocator: std.mem.Allocator,
    paths: Paths,
) LoadError!LoadedRepository {
    var arena_state = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena_state.deinit();

    return .{
        .repository = try loadModel(arena_state.allocator(), paths),
        .arena_state = arena_state,
    };
}

/// The allocator owns all returned model storage and must have arena lifetime.
pub fn loadModel(
    allocator: std.mem.Allocator,
    paths: Paths,
) LoadError!model.RepositoryModel {
    return (try loadModelWithRepomd(allocator, paths)).repository;
}

pub fn loadModelWithRepomd(
    allocator: std.mem.Allocator,
    paths: Paths,
) LoadError!PathModel {
    return loadModelWithRepomdBudget(
        allocator,
        paths,
        max_metadata_bytes,
    );
}

fn loadModelWithRepomdBudget(
    allocator: std.mem.Allocator,
    paths: Paths,
    max_total_output_bytes: usize,
) LoadError!PathModel {
    var output_budget = DecompressedOutputBudget.init(
        max_total_output_bytes,
    );
    const repomd_bytes = try readMetadataFileBudget(
        allocator,
        paths.repomd,
        &output_budget,
    );
    const parsed_repomd = repomd_xml.parse(
        allocator,
        repomd_bytes,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidRepoMetadata,
    };

    const repository = try loadResolvedModel(
        allocator,
        parsed_repomd,
        .{
            .primary = paths.primary,
            .filelists = paths.filelists,
            .updateinfo = paths.updateinfo,
            .other = paths.other,
        },
        &output_budget,
    );
    return .{
        .repository = repository,
        .repomd_bytes = repomd_bytes,
    };
}

pub fn loadLegacyModelWithRepomd(
    allocator: std.mem.Allocator,
    paths: Paths,
) LoadError!PathModel {
    return loadLegacyModelWithRepomdBudget(
        allocator,
        paths,
        legacy_max_output_bytes,
    );
}

fn loadLegacyModelWithRepomdBudget(
    allocator: std.mem.Allocator,
    paths: Paths,
    max_total_output_bytes: usize,
) LoadError!PathModel {
    var output_budget = DecompressedOutputBudget.init(
        max_total_output_bytes,
    );
    const repomd_bytes = try readMetadataFileLimitBudget(
        allocator,
        paths.repomd,
        max_metadata_bytes + 1,
        legacy_max_output_bytes + 1,
        legacy_max_expansion_ratio,
        &output_budget,
    );
    const parsed_repomd = repomd_xml.parse(
        allocator,
        repomd_bytes,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidRepoMetadata,
    };
    return .{
        .repository = try parseResolvedModel(
            allocator,
            parsed_repomd,
            .{
                .primary = try readMetadataFileLimitBudget(
                    allocator,
                    paths.primary,
                    max_metadata_bytes + 1,
                    legacy_max_output_bytes + 1,
                    legacy_max_expansion_ratio,
                    &output_budget,
                ),
                .filelists = if (paths.filelists) |path|
                    try readMetadataFileLimitBudget(
                        allocator,
                        path,
                        max_metadata_bytes + 1,
                        legacy_max_output_bytes + 1,
                        legacy_max_expansion_ratio,
                        &output_budget,
                    )
                else
                    null,
                .updateinfo = if (paths.updateinfo) |path|
                    try readMetadataFileLimitBudget(
                        allocator,
                        path,
                        max_metadata_bytes + 1,
                        legacy_max_output_bytes + 1,
                        legacy_max_expansion_ratio,
                        &output_budget,
                    )
                else
                    null,
                .other = if (paths.other) |path|
                    try readMetadataFileLimitBudget(
                        allocator,
                        path,
                        max_metadata_bytes + 1,
                        legacy_max_output_bytes + 1,
                        legacy_max_expansion_ratio,
                        &output_budget,
                    )
                else
                    null,
            },
        ),
        .repomd_bytes = repomd_bytes,
    };
}

const ResolvedPaths = struct {
    primary: []const u8,
    filelists: ?[]const u8,
    updateinfo: ?[]const u8,
    other: ?[]const u8,
};

const ResolvedBytes = struct {
    primary: []const u8,
    filelists: ?[]const u8,
    updateinfo: ?[]const u8,
    other: ?[]const u8,
};

fn loadResolvedModel(
    allocator: std.mem.Allocator,
    parsed_repomd: model.ParsedRepoMd,
    paths: ResolvedPaths,
    output_budget: *DecompressedOutputBudget,
) LoadError!model.RepositoryModel {
    const primary_record = recordForKind(parsed_repomd, .primary) orelse
        return error.InvalidRepoMetadata;
    const filelists_record = recordForKind(parsed_repomd, .filelists);
    const updateinfo_record = recordForKind(parsed_repomd, .updateinfo);
    const other_record = recordForKind(parsed_repomd, .other);
    const bytes = ResolvedBytes{
        .primary = try readVerifiedMetadataFile(
            allocator,
            paths.primary,
            primary_record,
            output_budget,
        ),
        .filelists = if (paths.filelists) |path|
            try readVerifiedMetadataFile(
                allocator,
                path,
                filelists_record orelse return error.InvalidRepoMetadata,
                output_budget,
            )
        else
            null,
        .updateinfo = if (paths.updateinfo) |path|
            try readVerifiedMetadataFile(
                allocator,
                path,
                updateinfo_record orelse return error.InvalidRepoMetadata,
                output_budget,
            )
        else
            null,
        .other = if (paths.other) |path|
            try readVerifiedMetadataFile(
                allocator,
                path,
                other_record orelse return error.InvalidRepoMetadata,
                output_budget,
            )
        else
            null,
    };
    return parseResolvedModel(allocator, parsed_repomd, bytes);
}

fn recordForKind(
    parsed_repomd: model.ParsedRepoMd,
    kind: model.RecordKind,
) ?*const model.Record {
    for (parsed_repomd.pRecords) |*record| {
        const raw_type = model.spanZ(record.pszType) orelse continue;
        if (model.kindFromRawType(raw_type) == kind) return record;
    }
    return null;
}

fn readVerifiedMetadataFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    record: *const model.Record,
    output_budget: *DecompressedOutputBudget,
) LoadError![]u8 {
    const raw = readFileAlloc(
        std.heap.c_allocator,
        path,
        max_metadata_bytes,
    ) catch |err|
        return mapReadError(err);
    trackRawScratchAlloc(raw.len);
    defer {
        trackRawScratchFree(raw.len);
        std.heap.c_allocator.free(raw);
    }
    if (record.nHasSize != 0 and raw.len != record.nSize) {
        return error.InvalidRepoMetadata;
    }
    if (!metadata_integrity.digestMatches(record.checksum, raw)) {
        return error.InvalidRepoMetadata;
    }
    const open = decompressMetadata(
        allocator,
        path,
        raw,
        try output_budget.fileLimit(try metadataOutputLimit(record)),
    ) catch |err|
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.StreamTooLong => error.StreamTooLong,
            error.UnsupportedCompressor => error.UnsupportedCompressor,
            error.DecompressFailed => error.DecompressFailed,
        };
    try output_budget.consume(open.len);
    if (record.nHasOpenSize != 0 and open.len != record.nOpenSize) {
        return error.InvalidRepoMetadata;
    }

    if ((record.openChecksum.pszType != null or
        record.openChecksum.pszValue != null) and
        !metadata_integrity.digestMatches(record.openChecksum, open))
    {
        return error.InvalidRepoMetadata;
    }
    return open;
}

fn metadataOutputLimit(record: *const model.Record) LoadError!usize {
    if (record.nHasOpenSize == 0) return max_metadata_bytes + 1;
    if (record.nOpenSize > max_metadata_bytes) {
        return error.InvalidRepoMetadata;
    }
    return @intCast(record.nOpenSize + 1);
}

fn parseResolvedModel(
    allocator: std.mem.Allocator,
    parsed_repomd: model.ParsedRepoMd,
    bytes: ResolvedBytes,
) LoadError!model.RepositoryModel {
    var parsed_primary = primary_xml.parse(
        allocator,
        bytes.primary,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidRepoMetadata,
    };

    if (bytes.filelists) |filelists_bytes| {
        filelists_xml.parseAndApply(
            allocator,
            filelists_bytes,
            &parsed_primary,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidRepoMetadata,
        };
    }

    if (bytes.other) |other_bytes| {
        other_xml.parseAndApply(
            allocator,
            other_bytes,
            &parsed_primary,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidRepoMetadata,
        };
    }

    const parsed_updateinfo = if (bytes.updateinfo) |updateinfo_bytes| blk: {
        break :blk updateinfo_xml.parse(
            allocator,
            updateinfo_bytes,
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidRepoMetadata,
        };
    } else model.ParsedUpdateInfo{};

    return model.repositoryModelFromParts(
        parsed_repomd,
        parsed_primary,
        parsed_updateinfo,
    );
}

/// Load cached metadata rooted at a repository cache directory.
/// The allocator owns all returned model storage and must have arena lifetime.
pub fn loadCacheModel(
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    options: CacheOptions,
) LoadError!model.RepositoryModel {
    return (try loadCacheModelWithRepomd(
        allocator,
        cache_dir,
        options,
    )).repository;
}

/// Load a cache model and return the exact repomd.xml bytes consumed by the
/// parser. The cache directory is opened once, eliminating a repomd re-open
/// race for callers that hash the loaded metadata identity. A concurrent
/// writer can still replace a sidecar before it is opened; each sidecar
/// loaded by options has its advertised checksum and size verified against
/// these parsed repomd bytes.
pub fn loadCacheModelWithRepomd(
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    options: CacheOptions,
) LoadError!CacheModel {
    var output_budget = DecompressedOutputBudget.init(max_metadata_bytes);
    var io_state: std.Io.Threaded = .init(allocator, .{});
    defer io_state.deinit();
    const io = io_state.io();
    const cache_root = std.Io.Dir.cwd().openDir(
        io,
        cache_dir,
        .{},
    ) catch |err| return mapReadError(err);
    defer cache_root.close(io);

    const repomd_bytes = try readCacheMetadataFile(
        allocator,
        cache_root,
        io,
        "repodata/repomd.xml",
        null,
        &output_budget,
    );
    const parsed_repomd = repomd_xml.parse(
        allocator,
        repomd_bytes,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidRepoMetadata,
    };

    var primary_record: ?*const model.Record = null;
    var filelists_record: ?*const model.Record = null;
    var updateinfo_record: ?*const model.Record = null;
    var other_record: ?*const model.Record = null;
    for (parsed_repomd.pRecords) |*record| {
        const raw_type = model.spanZ(record.pszType) orelse continue;
        const href = model.spanZ(record.pszLocationHref) orelse continue;
        try validateCacheMetadataPath(href);
        switch (model.kindFromRawType(raw_type)) {
            .primary => if (primary_record == null) {
                primary_record = record;
            },
            .filelists => if (options.include_filelists and
                filelists_record == null)
            {
                filelists_record = record;
            },
            .updateinfo => if (options.include_updateinfo and
                updateinfo_record == null)
            {
                updateinfo_record = record;
            },
            .other => if (options.include_other and other_record == null) {
                other_record = record;
            },
            else => {},
        }
    }

    const primary = primary_record orelse
        return error.InvalidRepoMetadata;
    const repository = try parseResolvedModel(allocator, parsed_repomd, .{
        .primary = try readCacheMetadataFile(
            allocator,
            cache_root,
            io,
            model.spanZ(primary.pszLocationHref).?,
            primary,
            &output_budget,
        ),
        .filelists = if (filelists_record) |record|
            try readCacheMetadataFile(
                allocator,
                cache_root,
                io,
                model.spanZ(record.pszLocationHref).?,
                record,
                &output_budget,
            )
        else
            null,
        .updateinfo = if (updateinfo_record) |record|
            try readCacheMetadataFile(
                allocator,
                cache_root,
                io,
                model.spanZ(record.pszLocationHref).?,
                record,
                &output_budget,
            )
        else
            null,
        .other = if (other_record) |record|
            try readCacheMetadataFile(
                allocator,
                cache_root,
                io,
                model.spanZ(record.pszLocationHref).?,
                record,
                &output_budget,
            )
        else
            null,
    });
    if (parsed_repomd.pRecordXmlBases.len != repository.records.len) {
        return error.InvalidRepoMetadata;
    }
    return .{
        .repository = repository,
        .repomd_bytes = repomd_bytes,
        .record_xml_bases = parsed_repomd.pRecordXmlBases,
    };
}

fn validateCacheMetadataPath(
    href: []const u8,
) LoadError!void {
    if (href.len == 0 or
        std.fs.path.isAbsolute(href) or
        std.mem.indexOfScalar(u8, href, '\\') != null)
    {
        return error.InvalidRepoMetadata;
    }
    var components = std.mem.splitScalar(u8, href, '/');
    while (components.next()) |component| {
        if (std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, ".."))
        {
            return error.InvalidRepoMetadata;
        }
    }
}

fn readCacheMetadataFile(
    allocator: std.mem.Allocator,
    cache_root: std.Io.Dir,
    io: std.Io,
    path: []const u8,
    record: ?*const model.Record,
    output_budget: *DecompressedOutputBudget,
) LoadError![]u8 {
    const file = try openCacheFile(cache_root, io, path);
    defer file.close(io);
    var reader = file.reader(io, &.{});
    const raw = reader.interface.allocRemaining(
        std.heap.c_allocator,
        .limited(max_metadata_bytes),
    ) catch |err| return switch (err) {
        error.ReadFailed => mapReadError(reader.err.?),
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.StreamTooLong,
    };
    trackRawScratchAlloc(raw.len);
    defer {
        trackRawScratchFree(raw.len);
        std.heap.c_allocator.free(raw);
    }
    if (record) |metadata| {
        if (metadata.nHasSize != 0 and raw.len != metadata.nSize) {
            return error.InvalidRepoMetadata;
        }
        if (!metadata_integrity.digestMatches(metadata.checksum, raw)) {
            return error.InvalidRepoMetadata;
        }
    }
    const open = decompressMetadata(
        allocator,
        path,
        raw,
        try output_budget.fileLimit(if (record) |metadata|
            try metadataOutputLimit(metadata)
        else
            max_metadata_bytes + 1),
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.StreamTooLong,
        error.UnsupportedCompressor => error.UnsupportedCompressor,
        error.DecompressFailed => error.DecompressFailed,
    };
    try output_budget.consume(open.len);
    if (record) |metadata| {
        if (metadata.nHasOpenSize != 0 and
            open.len != metadata.nOpenSize)
        {
            return error.InvalidRepoMetadata;
        }
        if ((metadata.openChecksum.pszType != null or
            metadata.openChecksum.pszValue != null) and
            !metadata_integrity.digestMatches(
                metadata.openChecksum,
                open,
            ))
        {
            return error.InvalidRepoMetadata;
        }
    }
    return open;
}

fn openCacheFile(
    cache_root: std.Io.Dir,
    io: std.Io,
    path: []const u8,
) LoadError!std.Io.File {
    try validateCacheMetadataPath(path);
    var components = std.mem.splitScalar(u8, path, '/');
    var component = components.next() orelse
        return error.InvalidRepoMetadata;
    var current = cache_root;
    var owns_current = false;
    defer if (owns_current) current.close(io);

    while (components.next()) |next| {
        const child = current.openDir(io, component, .{
            .follow_symlinks = false,
        }) catch |err| return switch (err) {
            error.NotDir, error.SymLinkLoop => error.AccessDenied,
            else => mapReadError(err),
        };
        if (owns_current) current.close(io);
        current = child;
        owns_current = true;
        component = next;
    }

    return current.openFile(io, component, .{
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |err| return switch (err) {
        error.SymLinkLoop => error.AccessDenied,
        else => mapReadError(err),
    };
}

fn readMetadataFile(
    allocator: std.mem.Allocator,
    path: []const u8,
) LoadError![]u8 {
    var output_budget = DecompressedOutputBudget.init(max_metadata_bytes);
    return readMetadataFileBudget(allocator, path, &output_budget);
}

fn readMetadataFileBudget(
    allocator: std.mem.Allocator,
    path: []const u8,
    output_budget: *DecompressedOutputBudget,
) LoadError![]u8 {
    return readMetadataFileLimitBudget(
        allocator,
        path,
        max_metadata_bytes,
        max_metadata_bytes + 1,
        null,
        output_budget,
    );
}

fn readMetadataFileLimit(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_raw_bytes: usize,
    max_output_bytes: usize,
    max_expansion_ratio: ?usize,
) LoadError![]u8 {
    var output_budget = DecompressedOutputBudget.init(
        max_output_bytes -| 1,
    );
    return readMetadataFileLimitBudget(
        allocator,
        path,
        max_raw_bytes,
        max_output_bytes,
        max_expansion_ratio,
        &output_budget,
    );
}

fn readMetadataFileLimitBudget(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_raw_bytes: usize,
    max_output_bytes: usize,
    max_expansion_ratio: ?usize,
    output_budget: *DecompressedOutputBudget,
) LoadError![]u8 {
    const raw = readFileAlloc(
        std.heap.c_allocator,
        path,
        max_raw_bytes,
    ) catch |err| {
        return mapReadError(err);
    };
    trackRawScratchAlloc(raw.len);
    defer {
        trackRawScratchFree(raw.len);
        std.heap.c_allocator.free(raw);
    }
    const output_limit = if (max_expansion_ratio) |ratio|
        boundedOutputLimit(
            raw.len,
            max_output_bytes,
            ratio,
            legacy_expansion_slack,
        )
    else
        max_output_bytes;
    const open = decompressMetadata(
        allocator,
        path,
        raw,
        try output_budget.fileLimit(output_limit),
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.StreamTooLong => error.StreamTooLong,
        error.UnsupportedCompressor => error.UnsupportedCompressor,
        error.DecompressFailed => error.DecompressFailed,
    };
    try output_budget.consume(open.len);
    return open;
}

fn boundedOutputLimit(
    raw_size: usize,
    hard_limit: usize,
    ratio: usize,
    slack: usize,
) usize {
    return @min(
        hard_limit,
        std.math.add(
            usize,
            std.math.mul(usize, raw_size, ratio) catch hard_limit,
            slack,
        ) catch hard_limit,
    );
}

fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) ![]u8 {
    var io_state: std.Io.Threaded = .init(allocator, .{});
    defer io_state.deinit();
    return std.Io.Dir.cwd().readFileAlloc(
        io_state.io(),
        path,
        allocator,
        .limited(max_bytes),
    );
}

fn mapReadError(err: anyerror) LoadError {
    return switch (err) {
        error.FileNotFound => error.FileNotFound,
        error.AccessDenied => error.AccessDenied,
        error.NameTooLong => error.NameTooLong,
        error.BadPathName => error.BadPathName,
        error.NotDir => error.NotDir,
        error.IsDir => error.IsDir,
        error.OutOfMemory => error.OutOfMemory,
        error.FileTooBig => error.FileTooBig,
        error.StreamTooLong => error.StreamTooLong,
        else => error.FileSystemIo,
    };
}

fn decompressMetadata(
    allocator: std.mem.Allocator,
    path: []const u8,
    bytes: []const u8,
    max_output_bytes: usize,
) DecompressError![]u8 {
    return decompressMetadataTracked(
        allocator,
        path,
        bytes,
        max_output_bytes,
        null,
    );
}

fn decompressMetadataTracked(
    allocator: std.mem.Allocator,
    path: []const u8,
    bytes: []const u8,
    max_output_bytes: usize,
    stats: ?*TemporaryOutputStats,
) DecompressError![]u8 {
    const budget = temporaryOutputBudget(max_output_bytes);
    var temporary = BudgetAllocator.init(std.heap.c_allocator, budget);
    if (stats) |value| value.* = .{ .budget = budget };

    const decoded = decompressMetadataAlloc(
        temporary.allocator(),
        path,
        bytes,
        max_output_bytes,
    ) catch |err| {
        if (stats) |value| {
            value.peak = temporary.peak;
            value.live_after_release = temporary.live;
        }
        return if (err == error.OutOfMemory and temporary.budget_exhausted)
            error.StreamTooLong
        else
            err;
    };

    const output = allocator.alloc(u8, decoded.len) catch {
        temporary.allocator().free(decoded);
        if (stats) |value| {
            value.peak = temporary.peak;
            value.live_after_release = temporary.live;
        }
        return error.OutOfMemory;
    };
    @memcpy(output, decoded);
    temporary.allocator().free(decoded);
    if (stats) |value| {
        value.peak = temporary.peak;
        value.live_after_release = temporary.live;
    }
    return output;
}

fn temporaryOutputBudget(max_output_bytes: usize) usize {
    const bounded_capacity = @max(
        max_output_bytes,
        decompression_writer_history_bytes,
    );
    const maximum_growth =
        std.ArrayList(u8).growCapacity(bounded_capacity);
    return std.math.mul(usize, maximum_growth, 2) catch
        std.math.maxInt(usize);
}

fn decompressMetadataAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    bytes: []const u8,
    max_output_bytes: usize,
) DecompressError![]u8 {
    var input = std.Io.Reader.fixed(bytes);

    if (std.mem.endsWith(u8, path, ".gz")) {
        var decoder: std.compress.flate.Decompress = .init(
            &input,
            .gzip,
            &.{},
        );
        return decoder.reader.allocRemaining(
            allocator,
            .limited(max_output_bytes),
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.StreamTooLong => error.StreamTooLong,
            else => error.DecompressFailed,
        };
    }
    if (std.mem.endsWith(u8, path, ".zst") or
        std.mem.endsWith(u8, path, ".zstd"))
    {
        const window = std.heap.c_allocator.alloc(
            u8,
            zstd_max_decoder_scratch_bytes,
        ) catch return error.OutOfMemory;
        defer std.heap.c_allocator.free(window);
        var decoder: std.compress.zstd.Decompress = .init(
            &input,
            window,
            .{},
        );
        return decoder.reader.allocRemaining(
            allocator,
            .limited(max_output_bytes),
        ) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.StreamTooLong => error.StreamTooLong,
            else => error.DecompressFailed,
        };
    }
    if (std.mem.endsWith(u8, path, ".xz")) {
        return decompressXz(
            allocator,
            bytes,
            max_output_bytes,
            null,
            null,
            null,
        );
    }

    if (bytes.len >= max_output_bytes) return error.StreamTooLong;
    const out = allocator.alloc(u8, bytes.len) catch
        return error.OutOfMemory;
    @memcpy(out, bytes);
    return out;
}

fn decompressXz(
    output_allocator: std.mem.Allocator,
    bytes: []const u8,
    max_output_bytes: usize,
    stats: ?*DecoderStats,
    forced_budget: ?usize,
    scratch_backing: ?std.mem.Allocator,
) DecompressError![]u8 {
    try preflightXzWork(bytes, max_output_bytes);
    const budget = forced_budget orelse xzDecoderBudget(max_output_bytes);
    var scratch: std.heap.DebugAllocator(.{}) = .init;
    defer _ = scratch.deinit();
    var decoder_allocator = BudgetAllocator.init(
        scratch_backing orelse scratch.allocator(),
        budget,
    );
    defer if (stats) |value| {
        value.budget = budget;
        value.peak = decoder_allocator.peak;
    };
    var output = std.Io.Writer.Allocating.init(output_allocator);
    defer output.deinit();

    var input_offset: usize = 0;
    while (input_offset < bytes.len) {
        const output_offset = output.writer.end;
        _ = try parseXzHeader(bytes[input_offset..]);
        const consumed = try decompressXzStream(
            &output,
            bytes[input_offset..],
            max_output_bytes,
            &decoder_allocator,
        );
        try validateXzStream(
            bytes[input_offset..][0..consumed],
            output.writer.buffer[output_offset..output.writer.end],
            &decoder_allocator,
            stats,
        );
        input_offset += consumed;

        const padding_start = input_offset;
        while (input_offset < bytes.len and bytes[input_offset] == 0)
            input_offset += 1;
        if ((input_offset - padding_start) % 4 != 0)
            return error.DecompressFailed;
        if (input_offset < bytes.len and
            !std.mem.startsWith(
                u8,
                bytes[input_offset..],
                xz_stream_magic,
            ))
        {
            return error.DecompressFailed;
        }
    }
    if (input_offset == 0) return error.DecompressFailed;
    return output.toOwnedSlice() catch return error.OutOfMemory;
}

fn decompressXzStream(
    output: *std.Io.Writer.Allocating,
    bytes: []const u8,
    max_output_bytes: usize,
    decoder_allocator: *BudgetAllocator,
) DecompressError!usize {
    var input = std.Io.Reader.fixed(bytes);
    var lzma_allocator = try LzmaLiteralAllocator.init(decoder_allocator);
    defer lzma_allocator.deinit();
    const allocator = lzma_allocator.allocator();
    const start_buf = allocator.alloc(u8, 0) catch
        return error.OutOfMemory;
    var decoder = std.compress.xz.Decompress.init(
        &input,
        allocator,
        start_buf,
    ) catch return decoderAllocatorError(decoder_allocator);
    defer decoder.deinit();
    while (true) {
        const remaining = max_output_bytes -| output.writer.end;
        if (remaining == 0) return error.StreamTooLong;
        _ = decoder.reader.stream(
            &output.writer,
            .limited(remaining),
        ) catch |err| switch (err) {
            error.EndOfStream => return input.seek,
            error.WriteFailed => return error.OutOfMemory,
            error.ReadFailed => return decoderAllocatorError(
                decoder_allocator,
            ),
        };
        if (decoder.reader.seek == decoder.reader.end and
            decoder.reader.buffer.len != 0)
        {
            const block = decoder.takeBuffer();
            decoder.reader.seek = 0;
            decoder.reader.end = 0;
            allocator.free(block);
        }
    }
}

fn decoderAllocatorError(
    allocator: *const BudgetAllocator,
) DecompressError {
    if (allocator.budget_exhausted) return error.StreamTooLong;
    if (allocator.backing_out_of_memory) return error.OutOfMemory;
    return error.DecompressFailed;
}

fn xzDecoderBudget(max_output_bytes: usize) usize {
    _ = max_output_bytes;
    return xz_max_decoder_scratch_bytes;
}

const xz_stream_magic = "\xfd7zXZ\x00";

const XzCheck = enum {
    none,
    crc32,
    crc64,
    sha256,

    fn byteLength(self: XzCheck) usize {
        return switch (self) {
            .none => 0,
            .crc32 => 4,
            .crc64 => 8,
            .sha256 => 32,
        };
    }
};

const XzHeader = struct {
    flags: [2]u8,
    check: XzCheck,
};

const XzBlock = struct {
    next_offset: usize,
    padding_offset: usize,
    padding_size: usize,
    unpadded_size: u64,
    uncompressed_size: u64,
};

fn parseXzHeader(bytes: []const u8) DecompressError!XzHeader {
    if (bytes.len < 12 or
        !std.mem.eql(u8, bytes[0..6], xz_stream_magic))
    {
        return error.DecompressFailed;
    }
    if (bytes[6] != 0 or bytes[7] & 0xf0 != 0)
        return error.DecompressFailed;
    if (std.mem.readInt(u32, bytes[8..12], .little) !=
        std.hash.Crc32.hash(bytes[6..8]))
    {
        return error.DecompressFailed;
    }
    const check: XzCheck = switch (bytes[7] & 0x0f) {
        0 => .none,
        1 => .crc32,
        4 => .crc64,
        10 => .sha256,
        else => return error.DecompressFailed,
    };
    return .{ .flags = bytes[6..8].*, .check = check };
}

fn parseXzVli(
    bytes: []const u8,
    cursor: *usize,
) DecompressError!u64 {
    var value: u64 = 0;
    var index: usize = 0;
    while (index < 9) : (index += 1) {
        if (cursor.* >= bytes.len) return error.DecompressFailed;
        const byte = bytes[cursor.*];
        cursor.* += 1;
        value |= @as(u64, byte & 0x7f) << @intCast(index * 7);
        if (byte & 0x80 == 0) {
            if (index != 0 and byte == 0)
                return error.DecompressFailed;
            return value;
        }
    }
    return error.DecompressFailed;
}

const XzLzma2Sizes = struct {
    packed_size: usize,
    unpacked: u64,
};

const XzWorkBudget = struct {
    limit: usize,
    used: usize = 0,

    fn init(input_bytes: usize, max_output_bytes: usize) XzWorkBudget {
        const input_units = input_bytes / xz_work_input_quantum +
            @intFromBool(input_bytes % xz_work_input_quantum != 0);
        const allowed_output = max_output_bytes -| 1;
        const output_units = allowed_output / xz_work_output_quantum +
            @intFromBool(allowed_output % xz_work_output_quantum != 0);
        return .{
            .limit = std.math.add(
                usize,
                xz_work_base_units,
                std.math.add(
                    usize,
                    input_units,
                    output_units,
                ) catch std.math.maxInt(usize),
            ) catch std.math.maxInt(usize),
        };
    }

    fn consume(self: *XzWorkBudget, units: usize) DecompressError!void {
        if (units > self.limit -| self.used) return error.StreamTooLong;
        self.used += units;
    }
};

const XzLzma2Transition = struct {
    dictionary_reset: bool = false,
    state_reset: bool = false,
    properties_reset: bool = false,
    uncompressed: bool = false,
};

const XzLzma2ControlState = struct {
    need_properties: bool = true,
    need_dictionary_reset: bool = true,

    fn next(
        self: *XzLzma2ControlState,
        control: u8,
    ) DecompressError!XzLzma2Transition {
        var transition = XzLzma2Transition{};
        if (control >= 0xe0 or control == 1) {
            self.need_properties = true;
            self.need_dictionary_reset = true;
        } else if (self.need_dictionary_reset) {
            return error.DecompressFailed;
        }
        if (control >= 0x80) {
            if (control >= 0xc0) {
                self.need_properties = false;
                transition.properties_reset = true;
                transition.state_reset = true;
            } else if (self.need_properties) {
                return error.DecompressFailed;
            } else if (control >= 0xa0) {
                transition.state_reset = true;
            }
        } else {
            if (control > 2) return error.DecompressFailed;
            transition.uncompressed = true;
        }
        if (self.need_dictionary_reset) {
            self.need_dictionary_reset = false;
            transition.dictionary_reset = true;
        }
        return transition;
    }
};

fn scanXzLzma2(
    bytes: []const u8,
    start: usize,
) DecompressError!XzLzma2Sizes {
    return scanXzLzma2Work(bytes, start, null);
}

fn scanXzLzma2Work(
    bytes: []const u8,
    start: usize,
    work_budget: ?*XzWorkBudget,
) DecompressError!XzLzma2Sizes {
    var cursor = start;
    var unpacked: u64 = 0;
    var control_state = XzLzma2ControlState{};
    while (true) {
        if (cursor >= bytes.len) return error.DecompressFailed;
        const control = bytes[cursor];
        cursor += 1;
        if (control == 0) break;
        if (work_budget) |budget| try budget.consume(1);
        const transition = try control_state.next(control);
        if (transition.properties_reset) {
            if (work_budget) |budget|
                try budget.consume(xz_property_reset_work_units);
        }
        if (transition.uncompressed) {
            if (bytes.len - cursor < 2) return error.DecompressFailed;
            const size = @as(usize, std.mem.readInt(
                u16,
                bytes[cursor..][0..2],
                .big,
            )) + 1;
            cursor += 2;
            if (bytes.len - cursor < size) return error.DecompressFailed;
            cursor += size;
            unpacked = std.math.add(u64, unpacked, size) catch
                return error.DecompressFailed;
            continue;
        }
        if (bytes.len - cursor < 4) return error.DecompressFailed;
        const unpacked_chunk =
            (@as(u64, control & 0x1f) << 16) |
            std.mem.readInt(u16, bytes[cursor..][0..2], .big);
        cursor += 2;
        const packed_chunk = @as(usize, std.mem.readInt(
            u16,
            bytes[cursor..][0..2],
            .big,
        )) + 1;
        cursor += 2;
        if (transition.properties_reset) {
            if (cursor >= bytes.len or bytes[cursor] >= 225)
                return error.DecompressFailed;
            cursor += 1;
        }
        if (bytes.len - cursor < packed_chunk)
            return error.DecompressFailed;
        cursor += packed_chunk;
        unpacked = std.math.add(
            u64,
            unpacked,
            unpacked_chunk + 1,
        ) catch return error.DecompressFailed;
    }
    return .{ .packed_size = cursor - start, .unpacked = unpacked };
}

fn xzLzma2DictionarySize(property: u8) DecompressError!usize {
    if (property > 40) return error.DecompressFailed;
    const size: u64 = if (property == 40)
        std.math.maxInt(u32)
    else
        @as(u64, 2 | (property & 1)) << @intCast(property / 2 + 11);
    return std.math.cast(usize, size) orelse error.DecompressFailed;
}

fn xzLzmaProperties(
    encoded: u8,
) DecompressError!std.compress.lzma.Decode.Properties {
    if (encoded >= 225) return error.DecompressFailed;
    var value = encoded;
    const lc: u4 = @intCast(value % 9);
    value /= 9;
    const lp: u3 = @intCast(value % 5);
    value /= 5;
    const pb: u3 = @intCast(value);
    if (lc + lp > 4) return error.DecompressFailed;
    return .{ .lc = lc, .lp = lp, .pb = pb };
}

const XzDictionaryValidator = struct {
    output: []const u8,
    dictionary_size: usize,
    stats: ?*DecoderStats,
    position: usize = 0,
    dictionary_start: usize = 0,
    len: usize = 0,

    fn resetDictionary(self: *XzDictionaryValidator) void {
        self.dictionary_start = self.position;
        self.len = 0;
    }

    fn validateDistance(
        self: *XzDictionaryValidator,
        distance: usize,
    ) DecompressError!void {
        if (distance == 0 or
            distance > self.position - self.dictionary_start or
            distance > self.dictionary_size)
        {
            return error.DecompressFailed;
        }
        if (self.stats) |stats|
            stats.max_distance = @max(stats.max_distance, distance);
    }

    pub fn lastOr(self: XzDictionaryValidator, fallback: u8) u8 {
        return if (self.len == 0)
            fallback
        else
            self.output[self.position - 1];
    }

    pub fn lastN(
        self: *XzDictionaryValidator,
        distance: usize,
    ) DecompressError!u8 {
        try self.validateDistance(distance);
        return self.output[self.position - distance];
    }

    pub fn appendLiteral(
        self: *XzDictionaryValidator,
        allocator: std.mem.Allocator,
        byte: u8,
        writer: *std.Io.Writer,
    ) DecompressError!void {
        _ = allocator;
        _ = writer;
        if (self.position >= self.output.len or
            self.output[self.position] != byte)
        {
            return error.DecompressFailed;
        }
        self.position += 1;
        self.len += 1;
    }

    pub fn appendLz(
        self: *XzDictionaryValidator,
        allocator: std.mem.Allocator,
        length: usize,
        distance: usize,
        writer: *std.Io.Writer,
    ) DecompressError!void {
        _ = allocator;
        _ = writer;
        try self.validateDistance(distance);
        if (length > self.output.len -| self.position)
            return error.DecompressFailed;
        for (0..length) |_| {
            if (self.output[self.position] !=
                self.output[self.position - distance])
            {
                return error.DecompressFailed;
            }
            self.position += 1;
            self.len += 1;
        }
    }

    fn appendUncompressed(
        self: *XzDictionaryValidator,
        bytes: []const u8,
    ) DecompressError!void {
        if (bytes.len > self.output.len -| self.position or
            !std.mem.eql(
                u8,
                bytes,
                self.output[self.position..][0..bytes.len],
            ))
        {
            return error.DecompressFailed;
        }
        self.position += bytes.len;
        self.len += bytes.len;
    }
};

fn mapXzValidationError(
    err: anyerror,
    allocator: *const BudgetAllocator,
) DecompressError {
    return if (err == error.OutOfMemory)
        decoderAllocatorError(allocator)
    else
        error.DecompressFailed;
}

fn resetXzDecoder(
    decode: *std.compress.lzma.Decode,
    allocator: std.mem.Allocator,
    properties: std.compress.lzma.Decode.Properties,
    decoder_allocator: *const BudgetAllocator,
) DecompressError!void {
    if (decode.properties.lc + decode.properties.lp ==
        properties.lc + properties.lp)
    {
        decode.resetState(allocator, properties) catch |err|
            return mapXzValidationError(err, decoder_allocator);
        return;
    }

    const replacement = std.compress.lzma.Decode.init(
        allocator,
        properties,
    ) catch |err| return mapXzValidationError(err, decoder_allocator);
    decode.deinit(allocator);
    decode.* = replacement;
}

fn validateXzLzma2(
    bytes: []const u8,
    start: usize,
    dictionary_size: usize,
    output: []const u8,
    decoder_allocator: *BudgetAllocator,
    stats: ?*DecoderStats,
) DecompressError!XzLzma2Sizes {
    const allocator = decoder_allocator.allocator();
    var decode = std.compress.lzma.Decode.init(
        allocator,
        .{ .lc = 0, .lp = 0, .pb = 0 },
    ) catch |err| return mapXzValidationError(err, decoder_allocator);
    defer decode.deinit(allocator);
    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();
    var validator = XzDictionaryValidator{
        .output = output,
        .dictionary_size = dictionary_size,
        .stats = stats,
    };
    var cursor = start;
    var control_state = XzLzma2ControlState{};
    while (true) {
        if (cursor >= bytes.len) return error.DecompressFailed;
        const control = bytes[cursor];
        cursor += 1;
        if (control == 0) break;
        const transition = try control_state.next(control);
        if (transition.uncompressed) {
            if (bytes.len - cursor < 2) return error.DecompressFailed;
            const size = @as(usize, std.mem.readInt(
                u16,
                bytes[cursor..][0..2],
                .big,
            )) + 1;
            cursor += 2;
            if (bytes.len - cursor < size) return error.DecompressFailed;
            if (transition.dictionary_reset) validator.resetDictionary();
            try validator.appendUncompressed(
                bytes[cursor..][0..size],
            );
            cursor += size;
            continue;
        }
        if (bytes.len - cursor < 4) return error.DecompressFailed;
        const unpacked_size =
            @as(usize, control & 0x1f) << 16 |
            std.mem.readInt(u16, bytes[cursor..][0..2], .big);
        cursor += 2;
        const packed_size = @as(usize, std.mem.readInt(
            u16,
            bytes[cursor..][0..2],
            .big,
        )) + 1;
        cursor += 2;
        if (transition.dictionary_reset) validator.resetDictionary();
        if (transition.properties_reset) {
            if (cursor >= bytes.len) return error.DecompressFailed;
            const properties = try xzLzmaProperties(bytes[cursor]);
            cursor += 1;
            try resetXzDecoder(
                &decode,
                allocator,
                properties,
                decoder_allocator,
            );
        } else if (transition.state_reset) {
            try resetXzDecoder(
                &decode,
                allocator,
                decode.properties,
                decoder_allocator,
            );
        }
        if (bytes.len - cursor < packed_size)
            return error.DecompressFailed;
        var compressed = std.Io.Reader.fixed(
            bytes[cursor..][0..packed_size],
        );
        var bytes_read: u64 = 0;
        var range = std.compress.lzma.RangeDecoder.initCounting(
            &compressed,
            &bytes_read,
        ) catch return error.DecompressFailed;
        const expected_position = std.math.add(
            usize,
            validator.position,
            unpacked_size + 1,
        ) catch return error.DecompressFailed;
        while (validator.position < expected_position) {
            switch (decode.process(
                &compressed,
                &allocating,
                &validator,
                &range,
                &bytes_read,
            ) catch |err| return mapXzValidationError(
                err,
                decoder_allocator,
            )) {
                .more => {},
                .finished => break,
            }
        }
        if (validator.position != expected_position or
            bytes_read != packed_size or
            !range.isFinished())
        {
            return error.DecompressFailed;
        }
        cursor += packed_size;
    }
    if (validator.position != output.len) return error.DecompressFailed;
    return .{
        .packed_size = cursor - start,
        .unpacked = output.len,
    };
}

fn validateXzBlockCheck(
    check: XzCheck,
    expected: []const u8,
    output: []const u8,
) DecompressError!void {
    switch (check) {
        .none => {},
        .crc32 => {
            if (expected.len != 4 or
                std.mem.readInt(u32, expected[0..4], .little) !=
                    std.hash.Crc32.hash(output))
            {
                return error.DecompressFailed;
            }
        },
        .crc64 => {
            var hash: std.hash.crc.Crc64Xz = .init();
            hash.update(output);
            if (expected.len != 8 or
                std.mem.readInt(u64, expected[0..8], .little) !=
                    hash.final())
            {
                return error.DecompressFailed;
            }
        },
        .sha256 => {
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(output, &digest, .{});
            if (!std.mem.eql(u8, expected, &digest))
                return error.DecompressFailed;
        },
    }
}

fn parseXzBlock(
    bytes: []const u8,
    offset: usize,
    check: XzCheck,
    output: []const u8,
    output_offset: usize,
    validate_check: bool,
    decoder_allocator: ?*BudgetAllocator,
    stats: ?*DecoderStats,
) DecompressError!XzBlock {
    return parseXzBlockWork(
        bytes,
        offset,
        check,
        output,
        output_offset,
        validate_check,
        decoder_allocator,
        stats,
        null,
    );
}

fn parseXzBlockWork(
    bytes: []const u8,
    offset: usize,
    check: XzCheck,
    output: []const u8,
    output_offset: usize,
    validate_check: bool,
    decoder_allocator: ?*BudgetAllocator,
    stats: ?*DecoderStats,
    work_budget: ?*XzWorkBudget,
) DecompressError!XzBlock {
    if (work_budget) |budget| try budget.consume(xz_block_work_units);
    if (offset >= bytes.len or bytes[offset] == 0)
        return error.DecompressFailed;
    const header_prefix_size = std.math.mul(
        usize,
        bytes[offset],
        4,
    ) catch return error.DecompressFailed;
    const header_size = std.math.add(
        usize,
        header_prefix_size,
        4,
    ) catch return error.DecompressFailed;
    if (header_prefix_size < 4 or bytes.len - offset < header_size)
        return error.DecompressFailed;
    const header_crc_offset = offset + header_prefix_size;
    if (std.mem.readInt(
        u32,
        bytes[header_crc_offset..][0..4],
        .little,
    ) != std.hash.Crc32.hash(bytes[offset..header_crc_offset])) {
        return error.DecompressFailed;
    }

    var cursor = offset + 1;
    const flags = bytes[cursor];
    cursor += 1;
    if (flags & 0x3c != 0 or flags & 0x03 != 0)
        return error.DecompressFailed;
    const declared_packed = if (flags & 0x40 != 0)
        try parseXzVli(bytes[0..header_crc_offset], &cursor)
    else
        null;
    const declared_unpacked = if (flags & 0x80 != 0)
        try parseXzVli(bytes[0..header_crc_offset], &cursor)
    else
        null;
    if (try parseXzVli(bytes[0..header_crc_offset], &cursor) != 0x21)
        return error.DecompressFailed;
    if (try parseXzVli(bytes[0..header_crc_offset], &cursor) != 1 or
        cursor >= header_crc_offset)
    {
        return error.DecompressFailed;
    }
    const dictionary_size = try xzLzma2DictionarySize(bytes[cursor]);
    cursor += 1;
    for (bytes[cursor..header_crc_offset]) |byte|
        if (byte != 0) return error.DecompressFailed;

    const lzma2 = try scanXzLzma2Work(
        bytes,
        offset + header_size,
        work_budget,
    );
    if (declared_packed) |size|
        if (size != lzma2.packed_size) return error.DecompressFailed;
    if (declared_unpacked) |size|
        if (size != lzma2.unpacked) return error.DecompressFailed;
    const packed_end = offset + header_size + lzma2.packed_size;
    const padding_size = (4 - (lzma2.packed_size % 4)) % 4;
    if (bytes.len - packed_end < padding_size)
        return error.DecompressFailed;
    for (bytes[packed_end..][0..padding_size]) |byte|
        if (byte != 0) return error.DecompressFailed;
    const check_offset = packed_end + padding_size;
    const check_size = check.byteLength();
    if (bytes.len - check_offset < check_size)
        return error.DecompressFailed;
    const output_size: usize = std.math.cast(usize, lzma2.unpacked) orelse
        return error.DecompressFailed;
    if (validate_check and
        (output_offset > output.len or
            output_size > output.len - output_offset))
    {
        return error.DecompressFailed;
    }
    if (validate_check) {
        const validated = try validateXzLzma2(
            bytes,
            offset + header_size,
            dictionary_size,
            output[output_offset..][0..output_size],
            decoder_allocator orelse return error.DecompressFailed,
            stats,
        );
        if (validated.packed_size != lzma2.packed_size or
            validated.unpacked != lzma2.unpacked)
        {
            return error.DecompressFailed;
        }
        try validateXzBlockCheck(
            check,
            bytes[check_offset..][0..check_size],
            output[output_offset..][0..output_size],
        );
    }
    const unpadded_size = std.math.add(
        u64,
        header_size + lzma2.packed_size,
        check_size,
    ) catch return error.DecompressFailed;
    return .{
        .next_offset = check_offset + check_size,
        .padding_offset = packed_end,
        .padding_size = padding_size,
        .unpadded_size = unpadded_size,
        .uncompressed_size = lzma2.unpacked,
    };
}

const XzStreamScan = struct {
    consumed: usize,
    uncompressed_size: u64,
};

fn scanXzStreamWork(
    bytes: []const u8,
    work_budget: *XzWorkBudget,
) DecompressError!XzStreamScan {
    try work_budget.consume(xz_stream_work_units);
    const header = try parseXzHeader(bytes);
    var cursor: usize = 12;
    var block_count: u64 = 0;
    var uncompressed_size: u64 = 0;
    while (cursor < bytes.len and bytes[cursor] != 0) {
        const block = try parseXzBlockWork(
            bytes,
            cursor,
            header.check,
            &.{},
            0,
            false,
            null,
            null,
            work_budget,
        );
        if (block.next_offset <= cursor) return error.DecompressFailed;
        cursor = block.next_offset;
        block_count = std.math.add(u64, block_count, 1) catch
            return error.DecompressFailed;
        uncompressed_size = std.math.add(
            u64,
            uncompressed_size,
            block.uncompressed_size,
        ) catch return error.DecompressFailed;
    }
    if (cursor >= bytes.len) return error.DecompressFailed;

    const index_offset = cursor;
    cursor += 1;
    const index_count = try parseXzVli(bytes, &cursor);
    if (index_count != block_count) return error.DecompressFailed;

    var block_cursor: usize = 12;
    var record_index: u64 = 0;
    while (record_index < index_count) : (record_index += 1) {
        const indexed_unpadded = try parseXzVli(bytes, &cursor);
        const indexed_uncompressed = try parseXzVli(bytes, &cursor);
        const block = try parseXzBlock(
            bytes,
            block_cursor,
            header.check,
            &.{},
            0,
            false,
            null,
            null,
        );
        if (indexed_unpadded != block.unpadded_size or
            indexed_uncompressed != block.uncompressed_size)
        {
            return error.DecompressFailed;
        }
        if (block.next_offset <= block_cursor)
            return error.DecompressFailed;
        block_cursor = block.next_offset;
    }
    if (block_cursor != index_offset) return error.DecompressFailed;

    const index_padding = (4 - ((cursor - index_offset) % 4)) % 4;
    if (bytes.len -| cursor < index_padding + 4)
        return error.DecompressFailed;
    for (bytes[cursor..][0..index_padding]) |byte|
        if (byte != 0) return error.DecompressFailed;
    cursor += index_padding;
    if (std.mem.readInt(u32, bytes[cursor..][0..4], .little) !=
        std.hash.Crc32.hash(bytes[index_offset..cursor]))
    {
        return error.DecompressFailed;
    }
    cursor += 4;
    const index_size = cursor - index_offset;
    if (bytes.len -| cursor < 12) return error.DecompressFailed;
    const footer = bytes[cursor..][0..12];
    if (std.mem.readInt(u32, footer[0..4], .little) !=
        std.hash.Crc32.hash(footer[4..10]))
    {
        return error.DecompressFailed;
    }
    const backward_size =
        (@as(u64, std.mem.readInt(u32, footer[4..8], .little)) + 1) * 4;
    if (backward_size != index_size or
        !std.mem.eql(u8, footer[8..10], &header.flags) or
        !std.mem.eql(u8, footer[10..12], "YZ"))
    {
        return error.DecompressFailed;
    }
    return .{
        .consumed = cursor + 12,
        .uncompressed_size = uncompressed_size,
    };
}

fn preflightXzWork(
    bytes: []const u8,
    max_output_bytes: usize,
) DecompressError!void {
    var work_budget = XzWorkBudget.init(bytes.len, max_output_bytes);
    var input_offset: usize = 0;
    var output_size: u64 = 0;
    var stream_count: usize = 0;
    while (input_offset < bytes.len) {
        const scan = try scanXzStreamWork(
            bytes[input_offset..],
            &work_budget,
        );
        input_offset = std.math.add(
            usize,
            input_offset,
            scan.consumed,
        ) catch return error.DecompressFailed;
        output_size = std.math.add(
            u64,
            output_size,
            scan.uncompressed_size,
        ) catch return error.StreamTooLong;
        if (max_output_bytes == 0 or
            output_size >= max_output_bytes)
        {
            return error.StreamTooLong;
        }
        stream_count += 1;

        const padding_start = input_offset;
        while (input_offset < bytes.len and bytes[input_offset] == 0)
            input_offset += 1;
        if ((input_offset - padding_start) % 4 != 0)
            return error.DecompressFailed;
        if (input_offset < bytes.len and
            !std.mem.startsWith(
                u8,
                bytes[input_offset..],
                xz_stream_magic,
            ))
        {
            return error.DecompressFailed;
        }
    }
    if (stream_count == 0) return error.DecompressFailed;
}

fn validateXzStream(
    bytes: []const u8,
    output: []const u8,
    decoder_allocator: *BudgetAllocator,
    stats: ?*DecoderStats,
) DecompressError!void {
    const header = try parseXzHeader(bytes);
    var cursor: usize = 12;
    var output_offset: usize = 0;
    var block_count: u64 = 0;
    while (cursor < bytes.len and bytes[cursor] != 0) {
        const block = try parseXzBlock(
            bytes,
            cursor,
            header.check,
            output,
            output_offset,
            true,
            decoder_allocator,
            stats,
        );
        cursor = block.next_offset;
        const output_size: usize = std.math.cast(
            usize,
            block.uncompressed_size,
        ) orelse return error.DecompressFailed;
        output_offset += output_size;
        block_count = std.math.add(u64, block_count, 1) catch
            return error.DecompressFailed;
    }
    if (cursor >= bytes.len or output_offset != output.len)
        return error.DecompressFailed;
    const index_offset = cursor;
    cursor += 1;
    const index_count = try parseXzVli(bytes, &cursor);
    if (index_count != block_count) return error.DecompressFailed;

    var block_cursor: usize = 12;
    output_offset = 0;
    var record_index: u64 = 0;
    while (record_index < index_count) : (record_index += 1) {
        const indexed_unpadded = try parseXzVli(bytes, &cursor);
        const indexed_uncompressed = try parseXzVli(bytes, &cursor);
        const block = try parseXzBlock(
            bytes,
            block_cursor,
            header.check,
            output,
            output_offset,
            false,
            null,
            null,
        );
        if (indexed_unpadded != block.unpadded_size or
            indexed_uncompressed != block.uncompressed_size)
        {
            return error.DecompressFailed;
        }
        block_cursor = block.next_offset;
        const output_size: usize = std.math.cast(
            usize,
            block.uncompressed_size,
        ) orelse return error.DecompressFailed;
        output_offset += output_size;
    }
    if (block_cursor != index_offset) return error.DecompressFailed;
    const index_padding = (4 - ((cursor - index_offset) % 4)) % 4;
    if (bytes.len - cursor < index_padding + 4)
        return error.DecompressFailed;
    for (bytes[cursor..][0..index_padding]) |byte|
        if (byte != 0) return error.DecompressFailed;
    cursor += index_padding;
    if (std.mem.readInt(u32, bytes[cursor..][0..4], .little) !=
        std.hash.Crc32.hash(bytes[index_offset..cursor]))
    {
        return error.DecompressFailed;
    }
    cursor += 4;
    const index_size = cursor - index_offset;
    if (bytes.len - cursor != 12) return error.DecompressFailed;
    const footer = bytes[cursor..];
    if (std.mem.readInt(u32, footer[0..4], .little) !=
        std.hash.Crc32.hash(footer[4..10]))
    {
        return error.DecompressFailed;
    }
    const backward_size =
        (@as(u64, std.mem.readInt(u32, footer[4..8], .little)) + 1) * 4;
    if (backward_size != index_size or
        !std.mem.eql(u8, footer[8..10], &header.flags) or
        !std.mem.eql(u8, footer[10..12], "YZ"))
    {
        return error.DecompressFailed;
    }
}

const fixture_primary =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<metadata xmlns="http://linux.duke.edu/metadata/common" packages="1">
    \\  <package type="rpm">
    \\    <name>fixture</name>
    \\    <arch>x86_64</arch>
    \\    <version epoch="1" ver="2.0" rel="3"/>
    \\    <checksum type="sha256" pkgid="YES">abcdef</checksum>
    \\    <summary>fixture summary</summary>
    \\    <location href="packages/fixture.rpm"/>
    \\  </package>
    \\</metadata>
;

const fixture_filelists =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<filelists xmlns="http://linux.duke.edu/metadata/filelists" packages="1">
    \\  <package pkgid="abcdef" name="fixture" arch="x86_64">
    \\    <version epoch="1" ver="2.0" rel="3"/>
    \\    <file>/usr/bin/fixture</file>
    \\  </package>
    \\</filelists>
;

const fixture_other =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<otherdata xmlns="http://linux.duke.edu/metadata/other" packages="1">
    \\  <package pkgid="abcdef" name="fixture" arch="x86_64">
    \\    <version epoch="1" ver="2.0" rel="3"/>
    \\    <changelog author="Tester" date="123">created</changelog>
    \\  </package>
    \\</otherdata>
;

const fixture_updateinfo =
    \\<?xml version="1.0" encoding="UTF-8"?>
    \\<updates></updates>
;

fn metadataDigest(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

const Fixture = struct {
    tmp: std.testing.TmpDir,
    repomd_len: usize,

    fn create() !Fixture {
        var fixture = Fixture{
            .tmp = std.testing.tmpDir(.{}),
            .repomd_len = 0,
        };
        errdefer fixture.tmp.cleanup();
        const allocator = std.testing.allocator;
        const primary_digest = metadataDigest(fixture_primary);
        const filelists_digest = metadataDigest(fixture_filelists);
        const other_digest = metadataDigest(fixture_other);
        const updateinfo_digest = metadataDigest(fixture_updateinfo);
        const repomd = try std.fmt.allocPrint(
            allocator,
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
            \\  <revision>42</revision>
            \\  <data type="primary"><checksum type="sha256">{s}</checksum><open-checksum type="sha256">{s}</open-checksum><location href="primary.xml"/><size>{d}</size><open-size>{d}</open-size></data>
            \\  <data type="filelists"><checksum type="sha256">{s}</checksum><open-checksum type="sha256">{s}</open-checksum><location href="filelists.xml"/><size>{d}</size><open-size>{d}</open-size></data>
            \\  <data type="other"><checksum type="sha256">{s}</checksum><open-checksum type="sha256">{s}</open-checksum><location href="other.xml"/><size>{d}</size><open-size>{d}</open-size></data>
            \\  <data type="updateinfo"><checksum type="sha256">{s}</checksum><open-checksum type="sha256">{s}</open-checksum><location href="updateinfo.xml"/><size>{d}</size><open-size>{d}</open-size></data>
            \\</repomd>
        ,
            .{
                &primary_digest,
                &primary_digest,
                fixture_primary.len,
                fixture_primary.len,
                &filelists_digest,
                &filelists_digest,
                fixture_filelists.len,
                fixture_filelists.len,
                &other_digest,
                &other_digest,
                fixture_other.len,
                fixture_other.len,
                &updateinfo_digest,
                &updateinfo_digest,
                fixture_updateinfo.len,
                fixture_updateinfo.len,
            },
        );
        fixture.repomd_len = repomd.len;
        defer allocator.free(repomd);
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{ .sub_path = "repomd.xml", .data = repomd },
        );
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{ .sub_path = "primary.xml", .data = fixture_primary },
        );
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{ .sub_path = "filelists.xml", .data = fixture_filelists },
        );
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{ .sub_path = "other.xml", .data = fixture_other },
        );
        try fixture.tmp.dir.writeFile(
            std.testing.io,
            .{ .sub_path = "updateinfo.xml", .data = fixture_updateinfo },
        );
        return fixture;
    }

    fn cleanup(self: *Fixture) void {
        self.tmp.cleanup();
        self.* = undefined;
    }

    fn path(
        self: *const Fixture,
        buffer: *[std.Io.Dir.max_path_bytes]u8,
        name: []const u8,
    ) [:0]const u8 {
        return std.fmt.bufPrintZ(
            buffer,
            ".zig-cache/tmp/{s}/{s}",
            .{ &self.tmp.sub_path, name },
        ) catch @panic("fixture path too long");
    }
};

test "owning loader retains primary and optional metadata" {
    raw_scratch_live = 0;
    raw_scratch_peak = 0;
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var repomd_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var primary_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var filelists_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var other_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var updateinfo_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;

    var loaded = try load(std.testing.allocator, .{
        .repomd = fixture.path(&repomd_path_buffer, "repomd.xml"),
        .primary = fixture.path(&primary_path_buffer, "primary.xml"),
        .filelists = fixture.path(
            &filelists_path_buffer,
            "filelists.xml",
        ),
        .other = fixture.path(&other_path_buffer, "other.xml"),
        .updateinfo = fixture.path(
            &updateinfo_path_buffer,
            "updateinfo.xml",
        ),
    });
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 0), raw_scratch_live);
    try std.testing.expectEqual(
        @max(
            fixture.repomd_len,
            @max(
                fixture_primary.len,
                @max(
                    fixture_filelists.len,
                    @max(fixture_other.len, fixture_updateinfo.len),
                ),
            ),
        ),
        raw_scratch_peak,
    );

    try std.testing.expectEqual(@as(usize, 1), loaded.repository.packages.len);
    try std.testing.expectEqualStrings(
        "fixture",
        loaded.repository.packages[0].nevra.name,
    );
    try std.testing.expectEqualStrings(
        "fixture summary",
        loaded.repository.packages[0].summary.?,
    );
    try std.testing.expectEqual(@as(usize, 1), loaded.repository.files.len);
    try std.testing.expectEqualStrings(
        "/usr/bin/fixture",
        loaded.repository.files[0].path,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        loaded.repository.changelogs.len,
    );
    try std.testing.expect(loaded.repository.has_filelists);
    try std.testing.expect(loaded.repository.has_other);
    try std.testing.expect(loaded.repository.has_updateinfo);
}

test "advertised optional metadata flags do not require sidecar loading" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var repomd_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var primary_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;

    var loaded = try load(std.testing.allocator, .{
        .repomd = fixture.path(&repomd_path_buffer, "repomd.xml"),
        .primary = fixture.path(&primary_path_buffer, "primary.xml"),
    });
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 0), loaded.repository.files.len);
    try std.testing.expectEqual(
        @as(usize, 0),
        loaded.repository.changelogs.len,
    );
    try std.testing.expect(loaded.repository.has_filelists);
    try std.testing.expect(loaded.repository.has_other);
    try std.testing.expect(loaded.repository.has_updateinfo);
}

fn loaderAllocationFailureCase(
    allocator: std.mem.Allocator,
    paths: Paths,
) !void {
    var loaded = try load(allocator, paths);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.repository.packages.len);
}

test "owning loader cleans every allocation failure" {
    raw_scratch_live = 0;
    raw_scratch_peak = 0;
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var repomd_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var primary_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const paths = Paths{
        .repomd = fixture.path(&repomd_path_buffer, "repomd.xml"),
        .primary = fixture.path(&primary_path_buffer, "primary.xml"),
    };

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        loaderAllocationFailureCase,
        .{paths},
    );
    try std.testing.expectEqual(@as(usize, 0), raw_scratch_live);
}

test "legacy raw input cap is independent from decompressed output" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var primary_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path = fixture.path(&primary_path_buffer, "primary.xml");
    try std.testing.expectError(
        error.StreamTooLong,
        readMetadataFileLimit(
            std.testing.allocator,
            path,
            fixture_primary.len,
            legacy_max_output_bytes + 1,
            legacy_max_expansion_ratio,
        ),
    );
    const loaded = try readMetadataFileLimit(
        std.testing.allocator,
        path,
        fixture_primary.len + 1,
        legacy_max_output_bytes + 1,
        legacy_max_expansion_ratio,
    );
    defer std.testing.allocator.free(loaded);
    try std.testing.expectEqualStrings(fixture_primary, loaded);

    const compressed = @embedFile("testdata/xz-2m-singleblock.xz");
    const expanded = try decompressMetadata(
        std.testing.allocator,
        "primary.xml.xz",
        compressed,
        legacy_max_output_bytes + 1,
    );
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqual(@as(usize, 2 * 1024 * 1024), expanded.len);
    try std.testing.expect(compressed.len < expanded.len);

    const modeled_bomb = 900 * 1024 * 1024;
    const bomb_limit = boundedOutputLimit(
        1024,
        legacy_max_output_bytes + 1,
        legacy_max_expansion_ratio,
        legacy_expansion_slack,
    );
    try std.testing.expect(modeled_bomb > bomb_limit);
    const modeled_valid = 300 * 1024 * 1024;
    const valid_limit = boundedOutputLimit(
        1024 * 1024,
        legacy_max_output_bytes + 1,
        legacy_max_expansion_ratio,
        legacy_expansion_slack,
    );
    try std.testing.expect(modeled_valid < valid_limit);
}

test "repository load shares one decompressed output budget" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var repomd_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var primary_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var filelists_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var other_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const paths = Paths{
        .repomd = fixture.path(&repomd_path_buffer, "repomd.xml"),
        .primary = fixture.path(&primary_path_buffer, "primary.xml"),
        .filelists = fixture.path(
            &filelists_path_buffer,
            "filelists.xml",
        ),
        .other = fixture.path(&other_path_buffer, "other.xml"),
    };
    const aggregate_limit = fixture.repomd_len +
        fixture_primary.len +
        fixture_filelists.len +
        fixture_other.len - 1;
    try std.testing.expect(fixture.repomd_len < aggregate_limit);
    try std.testing.expect(fixture_primary.len < aggregate_limit);
    try std.testing.expect(fixture_filelists.len < aggregate_limit);
    try std.testing.expect(fixture_other.len < aggregate_limit);

    inline for (.{ false, true }) |legacy| {
        var arena_state = std.heap.ArenaAllocator.init(
            std.testing.allocator,
        );
        defer arena_state.deinit();
        if (legacy) {
            try std.testing.expectError(
                error.StreamTooLong,
                loadLegacyModelWithRepomdBudget(
                    arena_state.allocator(),
                    paths,
                    aggregate_limit,
                ),
            );
        } else {
            try std.testing.expectError(
                error.StreamTooLong,
                loadModelWithRepomdBudget(
                    arena_state.allocator(),
                    paths,
                    aggregate_limit,
                ),
            );
        }
    }
}

const xz_integrity_vector = [_]u8{
    253, 55,  122, 88,  90,  0,   0,   4,   230, 214, 180, 70,
    2,   0,   33,  1,   22,  0,   0,   0,   116, 47,  229, 163,
    1,   0,   15,  109, 101, 116, 97,  100, 97,  116, 97,  45,
    112, 97,  121, 108, 111, 97,  100, 0,   173, 101, 109, 110,
    15,  58,  191, 160, 0,   1,   40,  16,  229, 11,  108, 96,
    31,  182, 243, 125, 1,   0,   0,   0,   0,   4,   89,  90,
};

const xz_property_reset_vector = [_]u8{
    253, 55, 122, 88, 90,  0,   0,   4,   230, 214, 180, 70,
    2,   0,  33,  1,  0,   0,   0,   0,   55,  39,  151, 214,
    224, 0,  15,  0,  6,   93,  0,   32,  237, 60,  0,   0,
    0,   0,  0,   0,  244, 183, 131, 67,  145, 87,  52,  163,
    0,   1,  34,  16, 111, 227, 131, 154, 31,  182, 243, 125,
    1,   0,  0,   0,  0,   4,   89,  90,
};

test "zstd metadata decodes under a window-sized frame descriptor" {
    // Repository metadata is produced by streaming compressors, so the frame
    // advertises the compressor's window (2 MiB here, 4 MiB for createrepo_c)
    // rather than the payload size. Decoding compressed blocks needs that whole
    // window available, so the decoder must own it -- otherwise the destination
    // writer is forced to hold it and the temporary output budget, which is
    // sized from the advertised open-size, reports StreamTooLong.
    const payload = "metadata-payload " ** 128;
    const zstd_window_frame = [_]u8{
        40,  181, 47,  253, 4,   88,  205, 0,   0,  136, 109, 101,
        116, 97,  100, 97,  116, 97,  45,  112, 97, 121, 108, 111,
        97,  100, 32,  1,   0,   217, 64,  254, 92, 2,   199, 242,
        183, 33,
    };

    const decoded = try decompressMetadata(
        std.testing.allocator,
        "metadata.xml.zst",
        &zstd_window_frame,
        payload.len + 1,
    );
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings(payload, decoded);

    try std.testing.expectError(
        error.StreamTooLong,
        decompressMetadata(
            std.testing.allocator,
            "metadata.xml.zst",
            &zstd_window_frame,
            payload.len,
        ),
    );
}

test "metadata decompression supports raw gzip zstd and xz" {
    const payload = "metadata-payload";
    const gzip = [_]u8{
        31, 139, 8,  0,  0,  0,  0,   0,  0,  3,   203, 77,
        45, 73,  76, 73, 44, 73, 212, 45, 72, 172, 204, 201,
        79, 76,  1,  0,  0,  44, 40,  62, 16, 0,   0,   0,
    };
    const zstd = [_]u8{
        40,  181, 47,  253, 4,   88, 129, 0,  0,   109, 101, 116,
        97,  100, 97,  116, 97,  45, 112, 97, 121, 108, 111, 97,
        100, 163, 220, 119, 210,
    };
    const xz = xz_integrity_vector;

    inline for (.{
        .{ "metadata.xml", payload },
        .{ "metadata.xml.gz", &gzip },
        .{ "metadata.xml.zst", &zstd },
        .{ "metadata.xml.xz", &xz },
    }) |fixture| {
        const decoded = try decompressMetadata(
            std.testing.allocator,
            fixture[0],
            fixture[1],
            payload.len + 1,
        );
        defer std.testing.allocator.free(decoded);
        try std.testing.expectEqualStrings(payload, decoded);
        if (!std.mem.eql(u8, fixture[0], "metadata.xml")) {
            try std.testing.expectError(
                error.StreamTooLong,
                decompressMetadata(
                    std.testing.allocator,
                    fixture[0],
                    fixture[1],
                    payload.len,
                ),
            );
        }
    }
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        decompressMetadata(
            failing.allocator(),
            "metadata.xml.xz",
            &xz,
            payload.len + 1,
        ),
    );
}

test "metadata decompression reclaims growth before exact arena copy" {
    const compressed = @embedFile("testdata/xz-2m-singleblock.xz");
    const output_size = 2 * 1024 * 1024;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var final_allocations = BudgetAllocator.init(
        arena_state.allocator(),
        output_size,
    );
    var temporary_stats = TemporaryOutputStats{};

    const output = try decompressMetadataTracked(
        final_allocations.allocator(),
        "primary.xml.xz",
        compressed,
        output_size + 1,
        &temporary_stats,
    );

    try std.testing.expectEqual(@as(usize, output_size), output.len);
    try std.testing.expectEqual(@as(u8, 0), output[0]);
    try std.testing.expectEqual(@as(u8, 0), output[output.len - 1]);
    try std.testing.expect(temporary_stats.peak >= output.len);
    try std.testing.expect(temporary_stats.peak <= temporary_stats.budget);
    try std.testing.expectEqual(
        @as(usize, 0),
        temporary_stats.live_after_release,
    );
    try std.testing.expectEqual(output.len, final_allocations.live);
    try std.testing.expectEqual(output.len, final_allocations.peak);
    try std.testing.expect(!final_allocations.budget_exhausted);
}

fn rewriteXzTestCrc32(
    bytes: []u8,
    data_start: usize,
    data_end: usize,
    checksum_offset: usize,
) void {
    std.mem.writeInt(
        u32,
        bytes[checksum_offset..][0..4],
        std.hash.Crc32.hash(bytes[data_start..data_end]),
        .little,
    );
}

fn rewriteXzTestCrc64(
    bytes: []u8,
    output: []const u8,
    checksum_offset: usize,
) void {
    var hash: std.hash.crc.Crc64Xz = .init();
    hash.update(output);
    std.mem.writeInt(
        u64,
        bytes[checksum_offset..][0..8],
        hash.final(),
        .little,
    );
}

fn appendXzVli(
    output: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    raw_value: u64,
) !void {
    var value = raw_value;
    while (true) {
        var byte: u8 = @truncate(value & 0x7f);
        value >>= 7;
        if (value != 0) byte |= 0x80;
        try output.append(allocator, byte);
        if (value == 0) return;
    }
}

fn makeRepeatedXzBlocks(
    allocator: std.mem.Allocator,
    lzma2: []const u8,
    block_output: []const u8,
    block_count: usize,
) ![]u8 {
    var bytes = std.ArrayList(u8).empty;
    errdefer bytes.deinit(allocator);
    try bytes.appendSlice(allocator, xz_integrity_vector[0..12]);

    var block_header = [_]u8{
        2, 0, 0x21, 1, 0, 0, 0, 0, 0, 0, 0, 0,
    };
    std.mem.writeInt(
        u32,
        block_header[8..12],
        std.hash.Crc32.hash(block_header[0..8]),
        .little,
    );
    var output_hash: std.hash.crc.Crc64Xz = .init();
    output_hash.update(block_output);
    var output_check: [8]u8 = undefined;
    std.mem.writeInt(u64, &output_check, output_hash.final(), .little);
    const block_padding = (4 - (lzma2.len % 4)) % 4;
    const unpadded_size = std.math.add(
        usize,
        block_header.len + lzma2.len,
        output_check.len,
    ) catch return error.OutOfMemory;

    for (0..block_count) |_| {
        try bytes.appendSlice(allocator, &block_header);
        try bytes.appendSlice(allocator, lzma2);
        try bytes.appendNTimes(allocator, 0, block_padding);
        try bytes.appendSlice(allocator, &output_check);
    }

    const index_offset = bytes.items.len;
    try bytes.append(allocator, 0);
    try appendXzVli(&bytes, allocator, block_count);
    for (0..block_count) |_| {
        try appendXzVli(&bytes, allocator, unpadded_size);
        try appendXzVli(&bytes, allocator, block_output.len);
    }
    const index_padding =
        (4 - ((bytes.items.len - index_offset) % 4)) % 4;
    try bytes.appendNTimes(allocator, 0, index_padding);
    var index_crc: [4]u8 = undefined;
    std.mem.writeInt(
        u32,
        &index_crc,
        std.hash.Crc32.hash(bytes.items[index_offset..]),
        .little,
    );
    try bytes.appendSlice(allocator, &index_crc);

    const index_size = bytes.items.len - index_offset;
    var footer = [_]u8{0} ** 12;
    std.mem.writeInt(
        u32,
        footer[4..8],
        @intCast(index_size / 4 - 1),
        .little,
    );
    footer[8] = 0;
    footer[9] = 4;
    footer[10] = 'Y';
    footer[11] = 'Z';
    std.mem.writeInt(
        u32,
        footer[0..4],
        std.hash.Crc32.hash(footer[4..10]),
        .little,
    );
    try bytes.appendSlice(allocator, &footer);
    return bytes.toOwnedSlice(allocator);
}

fn makePropertyResetXz(
    allocator: std.mem.Allocator,
    chunk_count: usize,
) ![]u8 {
    const chunk = [_]u8{
        0xe0, 0, 15, 0, 6, 93, 0, 32, 0xed, 0x3c, 0, 0, 0,
    };
    var lzma2 = std.ArrayList(u8).empty;
    defer lzma2.deinit(allocator);
    for (0..chunk_count) |_|
        try lzma2.appendSlice(allocator, &chunk);
    try lzma2.append(allocator, 0);

    const output = try allocator.alloc(u8, chunk_count * 16);
    defer allocator.free(output);
    @memset(output, 'A');
    return makeRepeatedXzBlocks(
        allocator,
        lzma2.items,
        output,
        1,
    );
}

fn expectInvalidXz(bytes: []const u8) !void {
    try std.testing.expectError(
        error.DecompressFailed,
        decompressXz(
            std.testing.allocator,
            bytes,
            16 * 1024 * 1024,
            null,
            null,
            null,
        ),
    );
}

test "xz validates independent none crc32 crc64 and sha256 vectors" {
    const payload = "independent-xz-vector";
    inline for (.{
        @embedFile("testdata/xz-check-none.xz"),
        @embedFile("testdata/xz-check-crc32.xz"),
        @embedFile("testdata/xz-check-crc64.xz"),
        @embedFile("testdata/xz-check-sha256.xz"),
    }) |vector| {
        const output = try decompressXz(
            std.testing.allocator,
            vector,
            payload.len + 1,
            null,
            null,
            null,
        );
        defer std.testing.allocator.free(output);
        try std.testing.expectEqualStrings(payload, output);
    }
}

test "xz validates every container integrity boundary" {
    var damaged = xz_integrity_vector;
    damaged[8] ^= 1;
    try expectInvalidXz(&damaged);

    damaged = xz_integrity_vector;
    damaged[7] |= 0x10;
    rewriteXzTestCrc32(&damaged, 6, 8, 8);
    try expectInvalidXz(&damaged);

    damaged = xz_integrity_vector;
    damaged[7] = 2;
    rewriteXzTestCrc32(&damaged, 6, 8, 8);
    try expectInvalidXz(&damaged);

    damaged = xz_integrity_vector;
    damaged[20] ^= 1;
    try expectInvalidXz(&damaged);

    damaged = xz_integrity_vector;
    damaged[44] ^= 1;
    try expectInvalidXz(&damaged);

    const padded_vector = @embedFile("testdata/xz-check-crc32.xz");
    const padded_block = try parseXzBlock(
        padded_vector,
        12,
        .crc32,
        "independent-xz-vector",
        0,
        false,
        null,
        null,
    );
    try std.testing.expect(padded_block.padding_size != 0);
    var damaged_padding = padded_vector.*;
    damaged_padding[padded_block.padding_offset] = 1;
    try expectInvalidXz(&damaged_padding);

    damaged = xz_integrity_vector;
    damaged[54] += 1;
    rewriteXzTestCrc32(&damaged, 52, 56, 56);
    try expectInvalidXz(&damaged);

    damaged = xz_integrity_vector;
    damaged[56] ^= 1;
    try expectInvalidXz(&damaged);

    damaged = xz_integrity_vector;
    damaged[64] ^= 1;
    rewriteXzTestCrc32(&damaged, 64, 70, 60);
    try expectInvalidXz(&damaged);

    damaged = xz_integrity_vector;
    damaged[69] = 1;
    rewriteXzTestCrc32(&damaged, 64, 70, 60);
    try expectInvalidXz(&damaged);

    damaged = xz_integrity_vector;
    damaged[60] ^= 1;
    try expectInvalidXz(&damaged);
}

test "lzma2 validates initial and reset property transitions" {
    var malformed_initial = xz_integrity_vector;
    malformed_initial[24] = 2;
    rewriteXzTestCrc64(
        &malformed_initial,
        "metadata-payload",
        44,
    );
    try expectInvalidXz(&malformed_initial);

    const valid_transitions = [_]u8{
        1,    0,    0, 'a',
        0xc0, 0,    0, 0,
        4,    0,    0, 0,
        0,    0,    0, 0x80,
        0,    0,    0, 4,
        0,    0,    0, 0,
        0,    0xa0, 0, 0,
        0,    4,    0, 0,
        0,    0,    0, 0xe0,
        0,    0,    0, 4,
        0,    0,    0, 0,
        0,    0,    0,
    };
    _ = try scanXzLzma2(&valid_transitions, 0);

    const initial_without_reset = [_]u8{ 2, 0, 0, 'a', 0 };
    try std.testing.expectError(
        error.DecompressFailed,
        scanXzLzma2(&initial_without_reset, 0),
    );
    const compressed_without_reset = [_]u8{
        0xc0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0,
    };
    try std.testing.expectError(
        error.DecompressFailed,
        scanXzLzma2(&compressed_without_reset, 0),
    );
    const missing_properties_after_reset = [_]u8{
        1,    0, 0, 'a',
        0x80, 0, 0, 0,
        4,    0, 0, 0,
        0,    0, 0,
    };
    try std.testing.expectError(
        error.DecompressFailed,
        scanXzLzma2(&missing_properties_after_reset, 0),
    );
}

test "lzma2 enforces declared dictionary distance boundary" {
    const vector = @embedFile("testdata/xz-lzma2-distance-6k.xz");
    var expected: [12 * 1024]u8 = undefined;
    var state: u32 = 0x12345678;
    for (expected[0 .. 6 * 1024]) |*byte| {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        byte.* = @truncate(state);
    }
    @memcpy(expected[6 * 1024 ..], expected[0 .. 6 * 1024]);
    var stats = DecoderStats{};
    const output = try decompressXz(
        std.testing.allocator,
        vector,
        expected.len + 1,
        &stats,
        null,
        null,
    );
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualSlices(u8, &expected, output);
    try std.testing.expectEqual(@as(usize, 6 * 1024), stats.max_distance);

    var undersized = vector.*;
    try std.testing.expectEqual(@as(u8, 1), undersized[16]);
    undersized[16] = 0;
    rewriteXzTestCrc32(&undersized, 12, 20, 20);
    try expectInvalidXz(&undersized);

    var compressed_without_initial_reset = vector.*;
    try std.testing.expectEqual(
        @as(u8, 0xe0),
        compressed_without_initial_reset[24],
    );
    compressed_without_initial_reset[24] = 0xc0;
    try expectInvalidXz(&compressed_without_initial_reset);
}

test "lzma2 rejects noncanonical range termination" {
    const vector = @embedFile("testdata/xz-2m-singleblock.xz");
    var damaged = vector.*;
    try std.testing.expectEqual(@as(u8, 0), damaged[405]);
    damaged[405] = 1;
    try expectInvalidXz(&damaged);
}

test "xz work budget rejects empty block churn" {
    const normal = try makeRepeatedXzBlocks(
        std.testing.allocator,
        "\x00",
        "",
        8,
    );
    defer std.testing.allocator.free(normal);
    const output = try decompressXz(
        std.testing.allocator,
        normal,
        1,
        null,
        null,
        null,
    );
    defer std.testing.allocator.free(output);
    try std.testing.expectEqual(@as(usize, 0), output.len);

    const pathological = try makeRepeatedXzBlocks(
        std.testing.allocator,
        "\x00",
        "",
        1024,
    );
    defer std.testing.allocator.free(pathological);
    try std.testing.expectError(
        error.StreamTooLong,
        decompressXz(
            std.testing.allocator,
            pathological,
            1,
            null,
            null,
            null,
        ),
    );
}

test "xz work budget rejects property reset churn" {
    const normal = try makePropertyResetXz(std.testing.allocator, 8);
    defer std.testing.allocator.free(normal);
    const output = try decompressXz(
        std.testing.allocator,
        normal,
        8 * 16 + 1,
        null,
        null,
        null,
    );
    defer std.testing.allocator.free(output);
    try std.testing.expectEqual(@as(usize, 8 * 16), output.len);
    for (output) |byte| try std.testing.expectEqual(@as(u8, 'A'), byte);

    const pathological = try makePropertyResetXz(
        std.testing.allocator,
        1024,
    );
    defer std.testing.allocator.free(pathological);
    try std.testing.expectError(
        error.StreamTooLong,
        decompressXz(
            std.testing.allocator,
            pathological,
            1024 * 16 + 1,
            null,
            null,
            null,
        ),
    );
}

fn xzAllocationFailureCase(allocator: std.mem.Allocator) !void {
    const output = try decompressXz(
        allocator,
        &xz_integrity_vector,
        "metadata-payload".len + 1,
        null,
        null,
        allocator,
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("metadata-payload", output);
}

test "xz validation preserves backing allocation OOM" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        xzAllocationFailureCase,
        .{},
    );
}

fn xzPropertyResetAllocationFailureCase(
    allocator: std.mem.Allocator,
) !void {
    const output = try decompressXz(
        allocator,
        &xz_property_reset_vector,
        17,
        null,
        null,
        allocator,
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("AAAAAAAAAAAAAAAA", output);
}

test "xz property reset cleans every backing allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        xzPropertyResetAllocationFailureCase,
        .{},
    );
}

test "xz supports concatenated streams and exact stream padding" {
    const payload = "metadata-payload";
    const expected = payload ++ payload;
    const concatenated = try std.mem.concat(
        std.testing.allocator,
        u8,
        &.{
            &xz_integrity_vector,
            "\x00\x00\x00\x00",
            &xz_integrity_vector,
            "\x00\x00\x00\x00\x00\x00\x00\x00",
        },
    );
    defer std.testing.allocator.free(concatenated);
    var stats = DecoderStats{};
    const output = try decompressXz(
        std.testing.allocator,
        concatenated,
        expected.len + 1,
        &stats,
        null,
        null,
    );
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(expected, output);
    try std.testing.expect(stats.peak <= xz_max_decoder_scratch_bytes);

    const junk = try std.mem.concat(
        std.testing.allocator,
        u8,
        &.{ concatenated, "junk" },
    );
    defer std.testing.allocator.free(junk);
    try expectInvalidXz(junk);
    try expectInvalidXz(
        concatenated[0 .. xz_integrity_vector.len + 4 +
            xz_integrity_vector.len - 1],
    );
    const bad_padding = try std.mem.concat(
        std.testing.allocator,
        u8,
        &.{ &xz_integrity_vector, "\x00" },
    );
    defer std.testing.allocator.free(bad_padding);
    try expectInvalidXz(bad_padding);
    try std.testing.expectError(
        error.StreamTooLong,
        decompressXz(
            std.testing.allocator,
            concatenated,
            expected.len,
            null,
            null,
            null,
        ),
    );
}

test "decoder allocator enforces live memory budget" {
    var budget = BudgetAllocator.init(std.testing.allocator, 64);
    const allocator = budget.allocator();
    const first = try allocator.alloc(u8, 40);
    defer allocator.free(first);
    try std.testing.expectError(error.OutOfMemory, allocator.alloc(u8, 25));
    try std.testing.expect(budget.budget_exhausted);
    try std.testing.expect(!budget.backing_out_of_memory);
    try std.testing.expect(budget.peak <= 64);
}

test "xz scratch stays bounded across large multi-block streams" {
    const single = @embedFile("testdata/xz-2m-singleblock.xz");
    const multi = @embedFile("testdata/xz-2m-multiblock.xz");
    const output_size = 2 * 1024 * 1024;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var single_stats = DecoderStats{};
    const single_output = try decompressXz(
        arena,
        single,
        output_size + 1,
        &single_stats,
        null,
        null,
    );
    try std.testing.expectEqual(@as(usize, output_size), single_output.len);
    try std.testing.expect(single_stats.peak <= single_stats.budget);
    try std.testing.expectEqual(
        xzDecoderBudget(output_size + 1),
        single_stats.budget,
    );
    try std.testing.expectEqual(
        xz_max_decoder_scratch_bytes,
        single_stats.budget,
    );

    var multi_stats = DecoderStats{};
    const multi_output = try decompressXz(
        arena,
        multi,
        output_size + 1,
        &multi_stats,
        null,
        null,
    );
    try std.testing.expectEqual(@as(usize, output_size), multi_output.len);
    try std.testing.expect(multi_stats.peak <= multi_stats.budget);
    try std.testing.expect(multi_stats.budget <= max_metadata_bytes);

    const large = @embedFile("testdata/xz-300m-multiblock.xz");
    const large_output_size = 300 * 1024 * 1024;
    var large_stats = DecoderStats{};
    const large_output = try decompressXz(
        std.testing.allocator,
        large,
        large_output_size + 1,
        &large_stats,
        null,
        null,
    );
    defer std.testing.allocator.free(large_output);
    try std.testing.expectEqual(
        @as(usize, large_output_size),
        large_output.len,
    );
    try std.testing.expectEqual(@as(u8, 0), large_output[0]);
    try std.testing.expectEqual(@as(u8, 0), large_output[large_output.len - 1]);
    try std.testing.expect(large_stats.peak <= xz_max_decoder_scratch_bytes);
    try std.testing.expect(large_stats.peak < max_metadata_bytes / 2);
    try std.testing.expectEqual(
        xzDecoderBudget(output_size + 1),
        xzDecoderBudget(legacy_max_output_bytes + 1),
    );

    const boundary = @embedFile("testdata/xz-128m-singleblock.xz");
    const boundary_size = 128 * 1024 * 1024;
    var boundary_stats = DecoderStats{};
    try std.testing.expectError(
        error.StreamTooLong,
        decompressXz(
            std.testing.allocator,
            boundary,
            boundary_size + 1,
            &boundary_stats,
            null,
            null,
        ),
    );
    try std.testing.expect(boundary_stats.peak <= xz_max_decoder_scratch_bytes);
    try std.testing.expect(boundary_stats.peak <= boundary_stats.budget);

    try std.testing.expectError(
        error.StreamTooLong,
        decompressXz(
            arena,
            single,
            output_size + 1,
            null,
            1024,
            null,
        ),
    );
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        decompressXz(
            arena,
            single,
            output_size + 1,
            null,
            null,
            failing.allocator(),
        ),
    );
}

test "loader maps missing malformed and corrupt metadata" {
    var fixture = try Fixture.create();
    defer fixture.cleanup();
    var repomd_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var primary_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var missing_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const repomd_path = fixture.path(
        &repomd_path_buffer,
        "repomd.xml",
    );
    const primary_path = fixture.path(
        &primary_path_buffer,
        "primary.xml",
    );
    const missing_path = fixture.path(
        &missing_path_buffer,
        "missing.xml",
    );

    try std.testing.expectError(error.FileNotFound, load(
        std.testing.allocator,
        .{ .repomd = repomd_path, .primary = missing_path },
    ));

    try fixture.tmp.dir.writeFile(
        std.testing.io,
        .{ .sub_path = "primary.xml", .data = "<metadata>" },
    );
    try std.testing.expectError(error.InvalidRepoMetadata, load(
        std.testing.allocator,
        .{ .repomd = repomd_path, .primary = primary_path },
    ));

    try fixture.tmp.dir.writeFile(
        std.testing.io,
        .{ .sub_path = "primary.xml.gz", .data = "not gzip" },
    );
    var corrupt_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try std.testing.expectError(error.InvalidRepoMetadata, load(
        std.testing.allocator,
        .{
            .repomd = repomd_path,
            .primary = fixture.path(
                &corrupt_path_buffer,
                "primary.xml.gz",
            ),
        },
    ));
}

test "cache loader rejects metadata paths outside the cache" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "cache/repodata");
    try tmp.dir.writeFile(
        std.testing.io,
        .{
            .sub_path = "cache/repodata/repomd.xml",
            .data =
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
            \\  <data type="primary">
            \\    <location href="../primary.xml"/>
            \\  </data>
            \\</repomd>
            ,
        },
    );
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cache_dir = std.fmt.bufPrint(
        &path_buffer,
        ".zig-cache/tmp/{s}/cache",
        .{&tmp.sub_path},
    ) catch @panic("cache path too long");
    var arena_state = std.heap.ArenaAllocator.init(
        std.testing.allocator,
    );
    defer arena_state.deinit();
    try std.testing.expectError(
        error.InvalidRepoMetadata,
        loadCacheModel(arena_state.allocator(), cache_dir, .{}),
    );
}

test "cache loader rejects metadata symlink escapes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "cache/repodata");
    try tmp.dir.createDir(std.testing.io, "outside", .default_dir);
    try tmp.dir.writeFile(
        std.testing.io,
        .{
            .sub_path = "cache/repodata/repomd.xml",
            .data =
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
            \\  <data type="primary">
            \\    <location href="repodata/link/primary.xml"/>
            \\  </data>
            \\</repomd>
            ,
        },
    );
    try tmp.dir.writeFile(
        std.testing.io,
        .{
            .sub_path = "outside/primary.xml",
            .data = fixture_primary,
        },
    );
    try tmp.dir.symLink(
        std.testing.io,
        "../../outside",
        "cache/repodata/link",
        .{ .is_directory = true },
    );
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cache_dir = std.fmt.bufPrint(
        &path_buffer,
        ".zig-cache/tmp/{s}/cache",
        .{&tmp.sub_path},
    ) catch @panic("cache path too long");
    var arena_state = std.heap.ArenaAllocator.init(
        std.testing.allocator,
    );
    defer arena_state.deinit();
    try std.testing.expectError(
        error.AccessDenied,
        loadCacheModel(arena_state.allocator(), cache_dir, .{}),
    );
}

test "cache loader rejects unverified sidecars" {
    const documents = [_][]const u8{
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
        \\  <data type="primary">
        \\    <location href="repodata/primary.xml"/>
        \\  </data>
        \\</repomd>
        ,
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
        \\  <data type="primary">
        \\    <checksum type="sha256">0000000000000000000000000000000000000000000000000000000000000000</checksum>
        \\    <location href="repodata/primary.xml"/>
        \\  </data>
        \\</repomd>
        ,
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    for (documents, 0..) |document, index| {
        var cache_buffer: [64]u8 = undefined;
        const cache = std.fmt.bufPrint(
            &cache_buffer,
            "cache-{d}",
            .{index},
        ) catch unreachable;
        var repodata_buffer: [64]u8 = undefined;
        const repodata = std.fmt.bufPrint(
            &repodata_buffer,
            "{s}/repodata",
            .{cache},
        ) catch unreachable;
        try tmp.dir.createDirPath(std.testing.io, repodata);
        var repomd_buffer: [96]u8 = undefined;
        const repomd_path = std.fmt.bufPrint(
            &repomd_buffer,
            "{s}/repomd.xml",
            .{repodata},
        ) catch unreachable;
        try tmp.dir.writeFile(
            std.testing.io,
            .{ .sub_path = repomd_path, .data = document },
        );
        var primary_buffer: [96]u8 = undefined;
        const primary_path = std.fmt.bufPrint(
            &primary_buffer,
            "{s}/primary.xml",
            .{repodata},
        ) catch unreachable;
        try tmp.dir.writeFile(
            std.testing.io,
            .{ .sub_path = primary_path, .data = fixture_primary },
        );

        var absolute_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const cache_dir = std.fmt.bufPrint(
            &absolute_buffer,
            ".zig-cache/tmp/{s}/{s}",
            .{ &tmp.sub_path, cache },
        ) catch @panic("cache path too long");
        var arena_state = std.heap.ArenaAllocator.init(
            std.testing.allocator,
        );
        defer arena_state.deinit();
        try std.testing.expectError(
            error.InvalidRepoMetadata,
            loadCacheModel(arena_state.allocator(), cache_dir, .{}),
        );
    }
}

test "resolved path loader verifies selected sidecars against repomd" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(fixture_primary, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    const repomd = try std.fmt.allocPrint(
        std.testing.allocator,
        \\<repomd xmlns="http://linux.duke.edu/metadata/repo">
        \\  <data type="primary">
        \\    <checksum type="sha256">{s}</checksum>
        \\    <open-checksum type="sha256">{s}</open-checksum>
        \\    <location href="primary.xml"/>
        \\    <size>{d}</size>
        \\    <open-size>{d}</open-size>
        \\  </data>
        \\</repomd>
    ,
        .{
            &digest_hex,
            &digest_hex,
            fixture_primary.len,
            fixture_primary.len,
        },
    );
    defer std.testing.allocator.free(repomd);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "repomd.xml",
        .data = repomd,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "primary.xml",
        .data = "<metadata xmlns=\"http://linux.duke.edu/metadata/common\" packages=\"0\"/>",
    });
    var repomd_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var primary_path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const base = ".zig-cache/tmp/";
    const repomd_path = try std.fmt.bufPrint(
        &repomd_path_buffer,
        "{s}{s}/repomd.xml",
        .{ base, &tmp.sub_path },
    );
    const primary_path = try std.fmt.bufPrint(
        &primary_path_buffer,
        "{s}{s}/primary.xml",
        .{ base, &tmp.sub_path },
    );
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    try std.testing.expectError(
        error.InvalidRepoMetadata,
        loadModel(arena_state.allocator(), .{
            .repomd = repomd_path,
            .primary = primary_path,
        }),
    );
}
