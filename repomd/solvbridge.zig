const std = @import("std");
const c = @cImport({
    @cInclude("errno.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("time.h");
    @cInclude("rpmdb.h");
    @cInclude("tdnferror.h");
    @cInclude("tdnfrepomd.h");
    @cInclude("solv/chksum.h");
    @cInclude("solv/poolarch.h");
    @cInclude("solv/repodata.h");
    @cInclude("solv/solver.h");
});

pub const libsolv = c;

// The Zig side reaches libsolv through this @cImport, so it needs the
// same pin as solv/includes.h: zig cc searches /usr/include before user
// -isystem directories, and this module used to be handed libsolv with
// -isystem, which meant a host libsolv-devel silently supplied the
// headers while the vendored libsolv was linked. Measured, 0.7.28 and
// 0.7.39 agree on every public field offset reachable from here (the
// declarations this @cImport pulls in differ by nine additions -- eight
// prototypes and the static inline allochashtable -- and one removal,
// stringpool_resize_hash, none of them used): struct s_Dirpool grew, but
// .dirpool is the last
// member outside LIBSOLV_INTERNAL, so only sizeof(Repodata) and
// sizeof(Dirpool) differ, and the *c.Repodata pointers this file holds
// were all allocated by libsolv itself (the .start/.end reads below sit
// at identical offsets in both). So that mismatch was accidentally
// harmless, not harmless by design, and the next .libsolv bump could
// change that with no diagnostic. build.zig now uses -I; this is what
// makes an include-path regression loud rather than silent. It detects
// the vendored tree being off the path, not every host header in scope
// -- see the known-boundary comment on addLibsolvIncludes.
comptime {
    if (c.LIBSOLV_VERSION_PATCH != c.TDNF_VENDORED_LIBSOLV_VERSION_PATCH) {
        @compileError(
            "libsolv headers are not the vendored ones build.zig links; " ++
                "a host libsolv-devel is shadowing the vendored copy (.libsolv in build.zig.zon)",
        );
    }
}

const available_loader = @import("available_loader.zig");
const model = @import("model.zig");
const rpmpkg = @import("rpmpkg.zig");
const rpm_header = @import("rpm_header");
const rpm_pkgfile = @import("rpm_pkgfile");

threadlocal var last_native_error_buf: [512]u8 = undefined;
threadlocal var last_native_error_len: usize = 0;

pub const LoadError = available_loader.LoadError;

pub const BuildError = error{
    InvalidRepoMetadata,
    OutOfMemory,
};

const NativeRpmError = error{
    InvalidRpmHeader,
    OutOfMemory,
    InvalidParameter,
    FileSystemIo,
    InvalidRpmFile,
    UnsupportedCompressor,
    DecompressFailed,
    RpmDbOpenFailed,
    RpmDbReadFailed,
};

pub export fn TDNFRepoMdNativeLastError() [*:0]const u8 {
    if (last_native_error_len >= last_native_error_buf.len) {
        last_native_error_len = last_native_error_buf.len - 1;
    }
    last_native_error_buf[last_native_error_len] = 0;
    return @ptrCast(&last_native_error_buf);
}

pub export fn TDNFRepoMdNativeLoadSolvRepo(
    raw_repo: ?*c.Repo,
    repomd_path: ?[*:0]const u8,
    primary_path: ?[*:0]const u8,
    filelists_path: ?[*:0]const u8,
    updateinfo_path: ?[*:0]const u8,
    other_path: ?[*:0]const u8,
) u32 {
    return loadSolvRepo(
        raw_repo,
        repomd_path,
        primary_path,
        filelists_path,
        updateinfo_path,
        other_path,
        null,
    );
}

fn transactionPlanLoadSolvRepo(
    raw_repo: ?*c.Repo,
    repomd_path: ?[*:0]const u8,
    primary_path: ?[*:0]const u8,
    filelists_path: ?[*:0]const u8,
    updateinfo_path: ?[*:0]const u8,
    other_path: ?[*:0]const u8,
    cookie_sha256: ?[*]u8,
) callconv(.c) u32 {
    if (cookie_sha256 == null) return c.ERROR_TDNF_INVALID_PARAMETER;
    return loadSolvRepo(
        raw_repo,
        repomd_path,
        primary_path,
        filelists_path,
        updateinfo_path,
        other_path,
        cookie_sha256,
    );
}

fn loadSolvRepo(
    raw_repo: ?*c.Repo,
    repomd_path: ?[*:0]const u8,
    primary_path: ?[*:0]const u8,
    filelists_path: ?[*:0]const u8,
    updateinfo_path: ?[*:0]const u8,
    other_path: ?[*:0]const u8,
    cookie_sha256: ?[*]u8,
) u32 {
    clearError();

    const repo = raw_repo orelse {
        setError("null repo", .{});
        return c.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (repo.pool == null) {
        setError("repo has no pool", .{});
        return c.ERROR_TDNF_INVALID_PARAMETER;
    }

    const repomd_slice = spanRequiredPath(repomd_path, "repomd") orelse return c.ERROR_TDNF_INVALID_PARAMETER;
    const primary_slice = spanRequiredPath(primary_path, "primary") orelse return c.ERROR_TDNF_INVALID_PARAMETER;

    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const paths = available_loader.Paths{
        .repomd = repomd_slice,
        .primary = primary_slice,
        .filelists = spanOptionalPath(filelists_path),
        .updateinfo = spanOptionalPath(updateinfo_path),
        .other = spanOptionalPath(other_path),
    };
    const loaded = (if (cookie_sha256 == null)
        available_loader.loadLegacyModelWithRepomd(arena, paths)
    else
        available_loader.loadModelWithRepomd(arena, paths)) catch |err| {
        return mapLoadError(err, repomd_slice);
    };

    buildRepositoryIntoRepo(arena, repo, &loaded.repository) catch |err| {
        return mapBuildError(err);
    };
    if (cookie_sha256) |destination| {
        const digest = available_loader.solvCacheCookie(
            loaded.repomd_bytes,
            .{
                .include_filelists = filelists_path != null,
                .include_updateinfo = updateinfo_path != null,
                .include_other = other_path != null,
            },
        );
        @memcpy(destination[0..32], &digest);
    }

    return 0;
}

fn transactionPlanBindSolvCookie(
    raw_cookie: ?*const [32]u8,
    include_filelists: u32,
    include_updateinfo: u32,
    include_other: u32,
    output: ?*[32]u8,
) callconv(.c) c_int {
    const input = raw_cookie orelse return -1;
    const destination = output orelse return -1;
    if (include_filelists > 1 or include_updateinfo > 1 or
        include_other > 1)
    {
        return -1;
    }
    destination.* = available_loader.bindSolvCacheCookie(input.*, .{
        .include_filelists = include_filelists != 0,
        .include_updateinfo = include_updateinfo != 0,
        .include_other = include_other != 0,
    });
    return 0;
}

comptime {
    @export(&transactionPlanLoadSolvRepo, .{
        .name = "TDNFTransactionPlanLoadSolvRepo",
        .visibility = .hidden,
    });
    @export(&transactionPlanBindSolvCookie, .{
        .name = "TDNFTransactionPlanBindSolvCookie",
        .visibility = .hidden,
    });
}

pub export fn TDNFRepoMdNativeLoadInstalledSolvRepo(
    raw_repo: ?*c.Repo,
    root_dir: ?[*:0]const u8,
    flags: c_int,
) u32 {
    clearError();

    const repo = raw_repo orelse {
        setError("null repo", .{});
        return c.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (repo.pool == null) {
        setError("repo has no pool", .{});
        return c.ERROR_TDNF_INVALID_PARAMETER;
    }

    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var bridge = NativeRpmBridge.init(arena, repo, optionsFromRpmFlags(flags)) catch |err| {
        return mapBuildError(err);
    };

    loadInstalledPackagesIntoBridge(arena, &bridge, root_dir, null, flags) catch |err| {
        return mapNativeRpmError(err);
    };

    bridge.finish() catch |err| {
        return mapBuildError(err);
    };

    return 0;
}

pub export fn TDNFRepoMdNativeLoadInstalledSolvRepoConfig(
    raw_repo: ?*c.Repo,
    config: ?*const c.tdnf_rpm_config,
    flags: c_int,
) u32 {
    clearError();

    const repo = raw_repo orelse {
        setError("null repo", .{});
        return c.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (repo.pool == null or config == null) {
        setError("repo or rpm config is null", .{});
        return c.ERROR_TDNF_INVALID_PARAMETER;
    }

    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var bridge = NativeRpmBridge.init(arena, repo, optionsFromRpmFlags(flags)) catch |err| {
        return mapBuildError(err);
    };

    loadInstalledPackagesIntoBridge(arena, &bridge, null, config, flags) catch |err| {
        return mapNativeRpmError(err);
    };

    bridge.finish() catch |err| {
        return mapBuildError(err);
    };

    return 0;
}

pub export fn TDNFRepoMdNativeAddRpm(
    raw_repo: ?*c.Repo,
    rpm_path: ?[*:0]const u8,
    flags: c_int,
    out_solvid: ?*u32,
) u32 {
    clearError();

    if (out_solvid) |out| {
        out.* = 0;
    }

    const repo = raw_repo orelse {
        setError("null repo", .{});
        return c.ERROR_TDNF_INVALID_PARAMETER;
    };
    if (repo.pool == null) {
        setError("repo has no pool", .{});
        return c.ERROR_TDNF_INVALID_PARAMETER;
    }

    const rpm_path_slice = spanRequiredPath(rpm_path, "rpm") orelse return c.ERROR_TDNF_INVALID_PARAMETER;

    var arena_state = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const rpm_path_z = arena.dupeZ(u8, rpm_path_slice) catch {
        setError("out of memory", .{});
        return c.ERROR_TDNF_OUT_OF_MEMORY;
    };

    var rpm = rpm_pkgfile.RpmFile.open(arena, rpm_path_z) catch |err| {
        setError("failed to open rpm file {s}: {t}", .{ rpm_path_slice, err });
        return mapNativeRpmFileError(err);
    };

    const built = rpmpkg.buildFromRpmFile(arena, &rpm, rpm_path_slice) catch |err| {
        return mapNativeRpmPackageError(err);
    };
    const header_id = if ((flags & c.RPM_ADD_WITH_HDRID) != 0)
        buildRpmFileHdrid(arena, &rpm) catch |err| {
            return mapBuildError(err);
        }
    else
        null;
    const arch_override = rpmHeaderArchOverride(rpm.main);

    var bridge = NativeRpmBridge.init(arena, repo, optionsFromRpmFlags(flags)) catch |err| {
        return mapBuildError(err);
    };

    const solvid = bridge.addBuiltPackage(
        built,
        if (rpm.main.getU32(.install_time)) |value| value else null,
        null,
        rpm.bytes,
        header_id,
        arch_override,
    ) catch |err| {
        return mapBuildError(err);
    };

    bridge.finish() catch |err| {
        return mapBuildError(err);
    };

    if (out_solvid) |out| {
        out.* = @intCast(solvid);
    }

    return 0;
}

fn clearError() void {
    last_native_error_len = 0;
}

fn setError(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&last_native_error_buf, fmt, args) catch blk: {
        const fallback = "(native repomd bridge error truncated)";
        @memcpy(last_native_error_buf[0..fallback.len], fallback);
        break :blk last_native_error_buf[0..fallback.len];
    };
    last_native_error_len = msg.len;
}

fn spanRequiredPath(raw_path: ?[*:0]const u8, comptime label: []const u8) ?[]const u8 {
    const path = raw_path orelse {
        setError("null {s} path", .{label});
        return null;
    };
    const slice = std.mem.span(path);
    if (slice.len == 0) {
        setError("empty {s} path", .{label});
        return null;
    }
    return slice;
}

fn spanOptionalPath(raw_path: ?[*:0]const u8) ?[]const u8 {
    const path = raw_path orelse return null;
    const slice = std.mem.span(path);
    return if (slice.len == 0) null else slice;
}

fn mapLoadError(err: LoadError, repomd_path: []const u8) u32 {
    return switch (err) {
        error.InvalidRepoMetadata => blk: {
            setError("invalid repository metadata under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_INVALID_REPO_FILE;
        },
        error.OutOfMemory => blk: {
            setError("out of memory", .{});
            break :blk c.ERROR_TDNF_OUT_OF_MEMORY;
        },
        error.FileNotFound => blk: {
            setError("file not found under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_FILE_NOT_FOUND;
        },
        error.AccessDenied => blk: {
            setError("access denied under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_ACCESS_DENIED;
        },
        error.NameTooLong => blk: {
            setError("path too long under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_NAME_TOO_LONG;
        },
        error.BadPathName => blk: {
            setError("bad path under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_INVALID_PARAMETER;
        },
        error.NotDir, error.IsDir => blk: {
            setError("invalid directory under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_INVALID_DIR;
        },
        error.FileTooBig, error.StreamTooLong => blk: {
            setError("metadata file too large under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_OVERFLOW;
        },
        error.UnsupportedCompressor, error.DecompressFailed => blk: {
            setError("failed to decompress metadata under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_INVALID_REPO_FILE;
        },
        error.FileSystemIo => blk: {
            setError("filesystem IO error under {s}", .{repomd_path});
            break :blk c.ERROR_TDNF_FILESYS_IO;
        },
    };
}

test "resource policy and backing OOM map distinctly" {
    try std.testing.expectEqual(
        @as(u32, c.ERROR_TDNF_OVERFLOW),
        mapLoadError(error.StreamTooLong, "fixture"),
    );
    try std.testing.expectEqual(
        @as(u32, c.ERROR_TDNF_OUT_OF_MEMORY),
        mapLoadError(error.OutOfMemory, "fixture"),
    );
}

fn mapBuildError(err: BuildError) u32 {
    return switch (err) {
        error.InvalidRepoMetadata => blk: {
            setError("invalid repository metadata model", .{});
            break :blk c.ERROR_TDNF_INVALID_REPO_FILE;
        },
        error.OutOfMemory => blk: {
            setError("out of memory", .{});
            break :blk c.ERROR_TDNF_OUT_OF_MEMORY;
        },
    };
}

fn mapNativeRpmError(err: NativeRpmError) u32 {
    return switch (err) {
        error.InvalidParameter => c.ERROR_TDNF_INVALID_PARAMETER,
        error.OutOfMemory => c.ERROR_TDNF_OUT_OF_MEMORY,
        error.InvalidRpmHeader => c.ERROR_TDNF_RPM_HEADER_CONVERT_FAILED,
        error.InvalidRpmFile => c.ERROR_TDNF_INVALID_REPO_FILE,
        error.UnsupportedCompressor, error.DecompressFailed => c.ERROR_TDNF_INVALID_REPO_FILE,
        error.RpmDbOpenFailed => c.ERROR_TDNF_RPMTS_OPENDB_FAILED,
        error.RpmDbReadFailed => c.ERROR_TDNF_SOLV_IO,
        error.FileSystemIo => c.ERROR_TDNF_FILESYS_IO,
    };
}

fn mapNativeRpmFileError(err: rpm_pkgfile.Error) u32 {
    return switch (err) {
        error.OutOfMemory => c.ERROR_TDNF_OUT_OF_MEMORY,
        error.BadLeadMagic, error.HeaderParseFailed => c.ERROR_TDNF_INVALID_REPO_FILE,
        error.UnsupportedCompressor, error.DecompressFailed => c.ERROR_TDNF_INVALID_REPO_FILE,
        else => c.ERROR_TDNF_FILESYS_IO,
    };
}

fn mapNativeRpmPackageError(err: rpmpkg.Error) u32 {
    return switch (err) {
        error.OutOfMemory => blk: {
            setError("out of memory", .{});
            break :blk c.ERROR_TDNF_OUT_OF_MEMORY;
        },
        error.InvalidRpmHeader => blk: {
            setError("invalid rpm header", .{});
            break :blk c.ERROR_TDNF_RPM_HEADER_CONVERT_FAILED;
        },
    };
}

pub fn loadRepositoryModel(
    allocator: std.mem.Allocator,
    repomd_path: []const u8,
    primary_path: []const u8,
    filelists_path: ?[]const u8,
    updateinfo_path: ?[]const u8,
    other_path: ?[]const u8,
) LoadError!model.RepositoryModel {
    return available_loader.loadModel(allocator, .{
        .repomd = repomd_path,
        .primary = primary_path,
        .filelists = filelists_path,
        .updateinfo = updateinfo_path,
        .other = other_path,
    }) catch |err| {
        setError(
            "failed to load repository metadata under {s}: {t}",
            .{ repomd_path, err },
        );
        return err;
    };
}

const BuildRepoOptions = struct {
    set_package_checksum: bool = true,
    set_empty_locations: bool = true,
};

const SolvBuilder = struct {
    arena: std.mem.Allocator,
    repo: *c.Repo,
    pool: *c.Pool,
    repository: *const model.RepositoryModel,
    package_solvids: []c.Id,
    options: BuildRepoOptions,

    fn init(
        arena: std.mem.Allocator,
        repo: *c.Repo,
        repository: *const model.RepositoryModel,
        options: BuildRepoOptions,
    ) BuildError!SolvBuilder {
        const pool = repo.pool orelse return error.InvalidRepoMetadata;
        return .{
            .arena = arena,
            .repo = repo,
            .pool = pool,
            .repository = repository,
            .package_solvids = try arena.alloc(c.Id, repository.packages.len),
            .options = options,
        };
    }

    fn build(self: *SolvBuilder) BuildError!void {
        try self.addRepomdMetadata();
        try self.addPrimary();
        if (self.repository.has_filelists) {
            try self.addFilelists();
        }
        if (self.repository.has_updateinfo) {
            try self.addUpdateinfo();
        }
        if (self.repository.has_other) {
            try self.addOther();
        }
    }

    fn addRepomdMetadata(self: *SolvBuilder) BuildError!void {
        const data = c.repo_add_repodata(self.repo, 0) orelse return error.OutOfMemory;
        var newest_timestamp: u64 = 0;

        if (self.repository.pszRevision) |revision| {
            c.repodata_set_str(data, c.SOLVID_META, c.REPOSITORY_REVISION, revision);
        }

        for (self.repository.records) |record| {
            const handle = c.repodata_new_handle(data);
            if (record.pszType) |raw_type| {
                c.repodata_set_poolstr(data, handle, c.REPOSITORY_REPOMD_TYPE, raw_type);
            }
            if (record.pszLocationHref) |href| {
                c.repodata_set_str(data, handle, c.REPOSITORY_REPOMD_LOCATION, href);
            }
            if (record.checksum.pszType != null and record.checksum.pszValue != null) {
                try setChecksumZ(data, handle, c.REPOSITORY_REPOMD_CHECKSUM, record.checksum);
            }
            if (record.openChecksum.pszType != null and record.openChecksum.pszValue != null) {
                try setChecksumZ(data, handle, c.REPOSITORY_REPOMD_OPENCHECKSUM, record.openChecksum);
            }
            if (record.nHasTimestamp != 0) {
                c.repodata_set_num(data, handle, c.REPOSITORY_REPOMD_TIMESTAMP, record.nTimestamp);
                if (record.nTimestamp > newest_timestamp) {
                    newest_timestamp = record.nTimestamp;
                }
            }
            if (record.nHasSize != 0) {
                c.repodata_set_num(data, handle, c.REPOSITORY_REPOMD_SIZE, record.nSize);
            }
            c.repodata_add_flexarray(data, c.SOLVID_META, c.REPOSITORY_REPOMD, handle);
        }

        if (newest_timestamp != 0) {
            c.repodata_set_num(data, c.SOLVID_META, c.REPOSITORY_TIMESTAMP, newest_timestamp);
        }

        c.repodata_internalize(data);
    }

    fn addPrimary(self: *SolvBuilder) BuildError!void {
        const data = c.repo_add_repodata(self.repo, 0) orelse return error.OutOfMemory;

        for (self.repository.packages, 0..) |pkg, index| {
            const solvid = c.repo_add_solvable(self.repo);
            self.package_solvids[index] = solvid;
            const solvable = c.pool_id2solvable(self.pool, solvid) orelse return error.InvalidRepoMetadata;

            solvable.*.name = c.pool_str2id(self.pool, try z(self.arena, pkg.nevra.name), 1);
            solvable.*.arch = c.pool_str2id(self.pool, try z(self.arena, pkg.nevra.arch), 1);
            solvable.*.evr = try evrId(self.arena, self.pool, pkg.nevra.epoch, pkg.nevra.version, pkg.nevra.release);
            if (pkg.rpm.vendor) |vendor| {
                solvable.*.vendor = c.pool_str2id(self.pool, try z(self.arena, vendor), 1);
            }

            if (pkg.summary) |summary| {
                c.repodata_set_str(data, solvid, c.SOLVABLE_SUMMARY, try z(self.arena, summary));
            }
            if (pkg.description) |description| {
                c.repodata_set_str(data, solvid, c.SOLVABLE_DESCRIPTION, try z(self.arena, description));
            }
            if (pkg.packager) |packager| {
                c.repodata_set_poolstr(data, solvid, c.SOLVABLE_PACKAGER, try z(self.arena, packager));
            }
            if (pkg.url) |url| {
                c.repodata_set_str(data, solvid, c.SOLVABLE_URL, try z(self.arena, url));
            }
            if (pkg.time.build) |build_time| {
                c.repodata_set_num(data, solvid, c.SOLVABLE_BUILDTIME, build_time);
            }
            if (pkg.size.installed) |installed_size| {
                c.repodata_set_num(data, solvid, c.SOLVABLE_INSTALLSIZE, installed_size);
            }
            if (pkg.size.package) |download_size| {
                c.repodata_set_num(data, solvid, c.SOLVABLE_DOWNLOADSIZE, download_size);
            }
            if (pkg.rpm.group) |group| {
                c.repodata_set_poolstr(data, solvid, c.SOLVABLE_GROUP, try z(self.arena, group));
            }
            if (pkg.rpm.license) |license| {
                c.repodata_set_poolstr(data, solvid, c.SOLVABLE_LICENSE, try z(self.arena, license));
            }
            if (pkg.rpm.buildhost) |buildhost| {
                c.repodata_set_str(data, solvid, c.SOLVABLE_BUILDHOST, try z(self.arena, buildhost));
            }
            if (pkg.rpm.source_rpm) |source_rpm| {
                c.repodata_set_sourcepkg(data, solvid, try z(self.arena, source_rpm));
            }
            if (pkg.rpm.header_range) |header_range| {
                c.repodata_set_num(data, solvid, c.SOLVABLE_HEADEREND, header_range.end);
            }
            if (pkg.location.href.len != 0 or self.options.set_empty_locations) {
                c.repodata_set_location(data, solvid, 0, null, try z(self.arena, pkg.location.href));
            }
            if (pkg.location.xml_base) |xml_base| {
                c.repodata_set_poolstr(data, solvid, c.SOLVABLE_MEDIABASE, try z(self.arena, xml_base));
            }
            if (self.options.set_package_checksum) {
                try setChecksumSlice(self.arena, data, solvid, c.SOLVABLE_CHECKSUM, pkg.checksum.kind, pkg.checksum.value);
                if (pkg.checksum.is_pkgid) {
                    try setChecksumSlice(self.arena, data, solvid, c.SOLVABLE_PKGID, pkg.checksum.kind, pkg.checksum.value);
                }
            }

            inline for ([_]struct { kind: model.DependencyKind, key: c.Id }{
                .{ .kind = .provides, .key = c.SOLVABLE_PROVIDES },
                .{ .kind = .requires, .key = c.SOLVABLE_REQUIRES },
                .{ .kind = .conflicts, .key = c.SOLVABLE_CONFLICTS },
                .{ .kind = .obsoletes, .key = c.SOLVABLE_OBSOLETES },
                .{ .kind = .recommends, .key = c.SOLVABLE_RECOMMENDS },
                .{ .kind = .suggests, .key = c.SOLVABLE_SUGGESTS },
                .{ .kind = .supplements, .key = c.SOLVABLE_SUPPLEMENTS },
                .{ .kind = .enhances, .key = c.SOLVABLE_ENHANCES },
            }) |entry| {
                const relations = pkg.relationsFor(entry.kind, self.repository.relations);
                for (relations) |relation| {
                    const dep = try relationId(self.arena, self.pool, relation);
                    const marker: c.Id = if (entry.kind == .requires)
                        if (relation.pre) c.SOLVABLE_PREREQMARKER else -c.SOLVABLE_PREREQMARKER
                    else
                        0;
                    c.repo_add_deparray(self.repo, solvid, entry.key, dep, marker);
                }
            }

            if (solvable.*.name != 0 and solvable.*.arch != c.ARCH_SRC and solvable.*.arch != c.ARCH_NOSRC) {
                const self_provide = c.pool_rel2id(self.pool, solvable.*.name, solvable.*.evr, c.REL_EQ, 1);
                c.repo_add_deparray(self.repo, solvid, c.SOLVABLE_PROVIDES, self_provide, 0);
            }

            // `primary.xml` carries the subset of each package's file list that
            // matches libsolv's standard filter, and the repodata below is
            // marked as that filtered list. `pool_addfileprovides()` treats a
            // filtered repodata as authoritative for every path the filter
            // accepts and never consults the `filelists.xml` extension for
            // them, so leaving this empty erases every file provide the
            // repository has. The model keeps only the full list, so the
            // filtered subset is reconstructed here with libsolv's own filter.
            for (pkg.fileEntries(self.repository.files)) |file_entry| {
                const path = try z(self.arena, file_entry.path);
                if (c.repodata_filelistfilter_matches(null, path) == 0) continue;
                try addFileEntry(self.arena, data, solvid, file_entry.path);
            }
        }

        if (data.*.end > data.*.start) {
            c.repodata_set_filelisttype(data, c.REPODATA_FILELIST_FILTERED);
            c.repodata_set_void(data, c.SOLVID_META, c.REPOSITORY_FILTEREDFILELIST);
        }

        c.repodata_internalize(data);
    }

    fn addFilelists(self: *SolvBuilder) BuildError!void {
        const data = c.repo_add_repodata(self.repo, c.REPO_EXTEND_SOLVABLES) orelse return error.OutOfMemory;

        for (self.repository.packages, 0..) |pkg, index| {
            const solvid = self.package_solvids[index];
            const files = pkg.fileEntries(self.repository.files);
            for (files) |file_entry| {
                var dir_buf: []const u8 = "/";
                var name_buf: []const u8 = file_entry.path;
                if (std.mem.lastIndexOfScalar(u8, file_entry.path, '/')) |separator| {
                    if (separator == 0) {
                        dir_buf = "/";
                        name_buf = file_entry.path[1..];
                    } else {
                        dir_buf = file_entry.path[0..separator];
                        name_buf = file_entry.path[separator + 1 ..];
                    }
                }
                const dir_id = c.repodata_str2dir(data, try z(self.arena, dir_buf), 1);
                c.repodata_add_dirstr(data, solvid, c.SOLVABLE_FILELIST, dir_id, try z(self.arena, name_buf));
            }
        }

        c.repodata_set_filelisttype(data, c.REPODATA_FILELIST_EXTENSION);
        c.repodata_internalize(data);
    }

    fn addUpdateinfo(self: *SolvBuilder) BuildError!void {
        const data = c.repo_add_repodata(self.repo, 0) orelse return error.OutOfMemory;

        for (self.repository.advisories) |advisory| {
            const solvid = c.repo_add_solvable(self.repo);
            const solvable = c.pool_id2solvable(self.pool, solvid) orelse return error.InvalidRepoMetadata;
            const patch_name = try fmtZ(self.arena, "patch:{s}", .{advisory.id});
            solvable.*.name = c.pool_str2id(self.pool, patch_name, 1);
            solvable.*.arch = c.ARCH_NOARCH;
            solvable.*.evr = if (advisory.version) |version|
                c.pool_str2id(self.pool, try z(self.arena, version), 1)
            else
                0;
            if (advisory.from) |from| {
                solvable.*.vendor = c.pool_str2id(self.pool, try z(self.arena, from), 1);
            }

            c.repodata_set_str(data, solvid, c.SOLVABLE_PATCHCATEGORY, try z(self.arena, advisory.raw_type));
            if (advisory.status) |status| {
                c.repodata_set_poolstr(data, solvid, c.UPDATE_STATUS, try z(self.arena, status));
            }
            if (advisory.title) |title| {
                c.repodata_set_str(data, solvid, c.SOLVABLE_SUMMARY, try z(self.arena, title));
            }
            if (advisory.severity) |severity| {
                c.repodata_set_poolstr(data, solvid, c.UPDATE_SEVERITY, try z(self.arena, severity));
            }
            if (advisory.rights) |rights| {
                c.repodata_set_poolstr(data, solvid, c.UPDATE_RIGHTS, try z(self.arena, rights));
            }
            if (advisory.description) |description| {
                c.repodata_set_str(data, solvid, c.SOLVABLE_DESCRIPTION, try z(self.arena, description));
            }
            const build_time = advisoryBuildTime(advisory);
            if (build_time != 0) {
                c.repodata_set_num(data, solvid, c.SOLVABLE_BUILDTIME, build_time);
            }
            if (advisory.reboot_suggested) {
                c.repodata_set_void(data, solvid, c.UPDATE_REBOOT);
            }

            for (advisory.referenceEntries(self.repository.advisory_references)) |reference| {
                const ref_handle = c.repodata_new_handle(data);
                if (reference.href) |href| {
                    c.repodata_set_str(data, ref_handle, c.UPDATE_REFERENCE_HREF, try z(self.arena, href));
                }
                if (reference.id) |ref_id| {
                    c.repodata_set_str(data, ref_handle, c.UPDATE_REFERENCE_ID, try z(self.arena, ref_id));
                }
                if (reference.title) |title| {
                    c.repodata_set_str(data, ref_handle, c.UPDATE_REFERENCE_TITLE, try z(self.arena, title));
                }
                if (reference.raw_type) |raw_type| {
                    c.repodata_set_poolstr(data, ref_handle, c.UPDATE_REFERENCE_TYPE, try z(self.arena, raw_type));
                }
                c.repodata_add_flexarray(data, solvid, c.UPDATE_REFERENCE, ref_handle);
            }

            var collection_started = false;
            var collection_short: ?[]const u8 = null;
            var collection_name: ?[]const u8 = null;
            var collection_handle: c.Id = 0;
            for (advisory.packageEntries(self.repository.advisory_packages)) |pkg| {
                if (!collection_started or !sameOptional(pkg.collection_short, collection_short) or !sameOptional(pkg.collection_name, collection_name)) {
                    if (collection_started) {
                        c.repodata_add_flexarray(data, solvid, c.UPDATE_COLLECTIONLIST, collection_handle);
                    }
                    collection_started = true;
                    collection_short = pkg.collection_short;
                    collection_name = pkg.collection_name;
                    collection_handle = c.repodata_new_handle(data);
                }

                const pkg_handle = c.repodata_new_handle(data);
                const name_id = c.pool_str2id(self.pool, try z(self.arena, pkg.nevra.name), 1);
                const evr_id = try evrId(self.arena, self.pool, pkg.nevra.epoch, pkg.nevra.version, pkg.nevra.release);
                const arch_id = c.pool_str2id(self.pool, try z(self.arena, pkg.nevra.arch), 1);
                c.repodata_set_id(data, pkg_handle, c.UPDATE_COLLECTION_NAME, name_id);
                c.repodata_set_id(data, pkg_handle, c.UPDATE_COLLECTION_EVR, evr_id);
                if (arch_id != 0) {
                    c.repodata_set_id(data, pkg_handle, c.UPDATE_COLLECTION_ARCH, arch_id);
                }
                if (pkg.filename) |filename| {
                    c.repodata_set_str(data, pkg_handle, c.UPDATE_COLLECTION_FILENAME, try z(self.arena, filename));
                }
                if (pkg.reboot_suggested) {
                    c.repodata_set_void(data, solvid, c.UPDATE_REBOOT);
                    c.repodata_set_void(data, pkg_handle, c.UPDATE_REBOOT);
                }
                c.repodata_add_flexarray(data, solvid, c.UPDATE_COLLECTION, pkg_handle);
                c.repodata_add_flexarray(data, collection_handle, c.UPDATE_COLLECTION, pkg_handle);
                addAdvisoryConflict(self.repo, self.pool, solvid, name_id, arch_id, evr_id);
            }
            if (collection_started) {
                c.repodata_add_flexarray(data, solvid, c.UPDATE_COLLECTIONLIST, collection_handle);
            }

            const self_provide = c.pool_rel2id(self.pool, solvable.*.name, solvable.*.evr, c.REL_EQ, 1);
            c.repo_add_deparray(self.repo, solvid, c.SOLVABLE_PROVIDES, self_provide, 0);
        }

        c.repodata_internalize(data);
    }

    fn addOther(self: *SolvBuilder) BuildError!void {
        const data = c.repo_add_repodata(self.repo, c.REPO_EXTEND_SOLVABLES) orelse return error.OutOfMemory;

        for (self.repository.packages, 0..) |pkg, index| {
            const solvid = self.package_solvids[index];
            const changelogs = pkg.changelogEntries(self.repository.changelogs);
            for (changelogs) |entry| {
                const handle = c.repodata_new_handle(data);
                c.repodata_set_num(data, handle, c.SOLVABLE_CHANGELOG_TIME, entry.timestamp);
                c.repodata_set_str(data, handle, c.SOLVABLE_CHANGELOG_AUTHOR, try z(self.arena, entry.author));
                c.repodata_set_str(data, handle, c.SOLVABLE_CHANGELOG_TEXT, try z(self.arena, entry.text));
                c.repodata_add_flexarray(data, solvid, c.SOLVABLE_CHANGELOG, handle);
            }
        }

        c.repodata_internalize(data);
    }
};

const NativeRpmBridgeOptions = struct {
    repodata_flags: c_int = 0,
    include_filelists: bool = true,
    include_changelogs: bool = false,
    add_hdrid: bool = false,
    checksum_kind: ?[]const u8 = null,
};

const NativeRpmBridge = struct {
    arena: std.mem.Allocator,
    repo: *c.Repo,
    pool: *c.Pool,
    options: NativeRpmBridgeOptions,
    primary_data: *c.Repodata,

    fn init(
        arena: std.mem.Allocator,
        repo: *c.Repo,
        options: NativeRpmBridgeOptions,
    ) BuildError!NativeRpmBridge {
        const pool = repo.pool orelse return error.InvalidRepoMetadata;
        const primary_data = c.repo_add_repodata(repo, options.repodata_flags) orelse return error.OutOfMemory;

        return .{
            .arena = arena,
            .repo = repo,
            .pool = pool,
            .options = options,
            .primary_data = primary_data,
        };
    }

    fn addBuiltPackage(
        self: *NativeRpmBridge,
        built: rpmpkg.BuiltPackage,
        install_time: ?u32,
        rpmdb_hnum: ?u32,
        file_bytes: ?[]const u8,
        header_id: ?model.PackageChecksum,
        arch_override: ?c.Id,
    ) BuildError!c.Id {
        const pkg = built.package;
        const solvid = c.repo_add_solvable(self.repo);
        const solvable = c.pool_id2solvable(self.pool, solvid) orelse return error.InvalidRepoMetadata;

        solvable.*.name = c.pool_str2id(self.pool, try z(self.arena, pkg.nevra.name), 1);
        solvable.*.arch = arch_override orelse c.pool_str2id(self.pool, try z(self.arena, pkg.nevra.arch), 1);
        solvable.*.evr = try evrIdOptional(
            self.arena,
            self.pool,
            normalizeRpmEpoch(pkg.nevra.epoch),
            if (pkg.nevra.version.len == 0) null else pkg.nevra.version,
            if (pkg.nevra.release.len == 0) null else pkg.nevra.release,
        );
        if (pkg.rpm.vendor) |vendor| {
            solvable.*.vendor = c.pool_str2id(self.pool, try z(self.arena, vendor), 1);
        }

        if (pkg.summary) |summary| {
            c.repodata_set_str(self.primary_data, solvid, c.SOLVABLE_SUMMARY, try z(self.arena, summary));
        }
        if (pkg.description) |description| {
            c.repodata_set_str(self.primary_data, solvid, c.SOLVABLE_DESCRIPTION, try z(self.arena, description));
        }
        if (pkg.packager) |packager| {
            c.repodata_set_poolstr(self.primary_data, solvid, c.SOLVABLE_PACKAGER, try z(self.arena, packager));
        }
        if (pkg.url) |url| {
            c.repodata_set_str(self.primary_data, solvid, c.SOLVABLE_URL, try z(self.arena, url));
        }
        if (pkg.time.build) |build_time| {
            c.repodata_set_num(self.primary_data, solvid, c.SOLVABLE_BUILDTIME, build_time);
        }
        if (install_time) |value| {
            c.repodata_set_num(self.primary_data, solvid, c.SOLVABLE_INSTALLTIME, value);
        }
        if (rpmdb_hnum) |value| {
            c.solvable_set_num(solvable, c.RPM_RPMDBID, value);
        }
        if (pkg.size.installed) |installed_size| {
            c.repodata_set_num(self.primary_data, solvid, c.SOLVABLE_INSTALLSIZE, installed_size);
        }
        if (pkg.size.package) |download_size| {
            c.repodata_set_num(self.primary_data, solvid, c.SOLVABLE_DOWNLOADSIZE, download_size);
        }
        if (pkg.rpm.group) |group| {
            c.repodata_set_poolstr(self.primary_data, solvid, c.SOLVABLE_GROUP, try z(self.arena, group));
        }
        if (pkg.rpm.license) |license| {
            c.repodata_set_poolstr(self.primary_data, solvid, c.SOLVABLE_LICENSE, try z(self.arena, license));
        }
        if (pkg.rpm.buildhost) |buildhost| {
            c.repodata_set_str(self.primary_data, solvid, c.SOLVABLE_BUILDHOST, try z(self.arena, buildhost));
        }
        if (pkg.rpm.source_rpm) |source_rpm| {
            c.repodata_set_sourcepkg(self.primary_data, solvid, try z(self.arena, source_rpm));
        }
        if (pkg.rpm.header_range) |header_range| {
            c.repodata_set_num(
                self.primary_data,
                solvid,
                c.SOLVABLE_HEADEREND,
                if (file_bytes != null) header_range.end + 8 else header_range.end,
            );
        }
        if (pkg.location.href.len != 0) {
            c.repodata_set_location(self.primary_data, solvid, 0, null, try z(self.arena, pkg.location.href));
        }
        if (self.options.add_hdrid) {
            const hdrid = header_id orelse pkg.checksum;
            try setChecksumSlice(self.arena, self.primary_data, solvid, c.SOLVABLE_HDRID, hdrid.kind, hdrid.value);
        }
        if (self.options.checksum_kind) |checksum_kind| {
            const bytes = file_bytes orelse return error.InvalidRepoMetadata;
            const checksum_value = try checksumHexLower(self.arena, checksum_kind, bytes);
            try setChecksumSlice(self.arena, self.primary_data, solvid, c.SOLVABLE_CHECKSUM, checksum_kind, checksum_value);
        }

        try nativeRpmSetDeps(self.arena, self.pool, self.repo, &solvable.*.provides, pkg.relationsFor(.provides, built.relations), false);
        try nativeRpmSetDeps(self.arena, self.pool, self.repo, &solvable.*.requires, pkg.relationsFor(.requires, built.relations), true);
        try nativeRpmSetDeps(self.arena, self.pool, self.repo, &solvable.*.conflicts, pkg.relationsFor(.conflicts, built.relations), false);
        try nativeRpmSetDeps(self.arena, self.pool, self.repo, &solvable.*.obsoletes, pkg.relationsFor(.obsoletes, built.relations), false);
        try nativeRpmSetDeps(self.arena, self.pool, self.repo, &solvable.*.recommends, pkg.relationsFor(.recommends, built.relations), false);
        try nativeRpmSetDeps(self.arena, self.pool, self.repo, &solvable.*.suggests, pkg.relationsFor(.suggests, built.relations), false);
        try nativeRpmSetDeps(self.arena, self.pool, self.repo, &solvable.*.supplements, pkg.relationsFor(.supplements, built.relations), false);
        try nativeRpmSetDeps(self.arena, self.pool, self.repo, &solvable.*.enhances, pkg.relationsFor(.enhances, built.relations), false);

        if (solvable.*.name != 0 and solvable.*.arch != c.ARCH_SRC and solvable.*.arch != c.ARCH_NOSRC) {
            const self_provide = c.pool_rel2id(self.pool, solvable.*.name, solvable.*.evr, c.REL_EQ, 1);
            solvable.*.provides = c.repo_addid_dep(self.repo, solvable.*.provides, self_provide, 0);
        }

        if (self.options.include_filelists) {
            const files = pkg.fileEntries(built.files);
            for (files) |file_entry| {
                try addFileEntry(self.arena, self.primary_data, solvid, file_entry.path);
            }
        }

        if (self.options.include_changelogs) {
            const changelogs = pkg.changelogEntries(built.changelogs);
            for (changelogs) |entry| {
                const handle = c.repodata_new_handle(self.primary_data);
                c.repodata_set_num(self.primary_data, handle, c.SOLVABLE_CHANGELOG_TIME, entry.timestamp);
                c.repodata_set_str(self.primary_data, handle, c.SOLVABLE_CHANGELOG_AUTHOR, try z(self.arena, entry.author));
                c.repodata_set_str(self.primary_data, handle, c.SOLVABLE_CHANGELOG_TEXT, try z(self.arena, entry.text));
                c.repodata_add_flexarray(self.primary_data, solvid, c.SOLVABLE_CHANGELOG, handle);
            }
        }

        return solvid;
    }

    fn finish(self: *NativeRpmBridge) BuildError!void {
        c.repodata_internalize(self.primary_data);
    }
};

fn optionsFromRpmFlags(flags: c_int) NativeRpmBridgeOptions {
    return .{
        .repodata_flags = flags,
        .include_filelists = (flags & c.RPM_ADD_NO_FILELIST) == 0,
        .include_changelogs = (flags & c.RPM_ADD_WITH_CHANGELOG) != 0,
        .add_hdrid = (flags & c.RPM_ADD_WITH_HDRID) != 0,
        .checksum_kind = if ((flags & c.RPM_ADD_WITH_SHA256SUM) != 0)
            "sha256"
        else if ((flags & c.RPM_ADD_WITH_SHA1SUM) != 0)
            "sha1"
        else
            null,
    };
}

pub const InstalledHeaderBatch = struct {
    allocator: std.mem.Allocator,
    bridge: NativeRpmBridge,
    scratch_peak: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        repo: *c.Repo,
    ) !InstalledHeaderBatch {
        return .{
            .allocator = allocator,
            .bridge = try NativeRpmBridge.init(allocator, repo, .{
                .include_filelists = true,
                .include_changelogs = false,
            }),
        };
    }

    pub fn add(
        self: *InstalledHeaderBatch,
        header: rpm_header.Header,
        rpmdb_hnum: u32,
    ) !c.Id {
        var scratch_state = std.heap.ArenaAllocator.init(self.allocator);
        defer {
            self.scratch_peak = @max(
                self.scratch_peak,
                scratch_state.queryCapacity(),
            );
            scratch_state.deinit();
        }
        const prior_allocator = self.bridge.arena;
        self.bridge.arena = scratch_state.allocator();
        defer self.bridge.arena = prior_allocator;
        const built = try rpmpkg.buildFromHeader(
            scratch_state.allocator(),
            header,
            .{
                .include_relations = true,
                .include_files = true,
                .include_changelogs = false,
            },
        );
        return self.bridge.addBuiltPackage(
            built,
            null,
            rpmdb_hnum,
            null,
            null,
            null,
        );
    }

    pub fn finish(self: *InstalledHeaderBatch) !void {
        try self.bridge.finish();
    }
};

test "installed header batch scratch memory is package bounded" {
    const rpmdb_test = @import("rpmdb_test");
    const blob = try rpmdb_test.transactionPlanTestFileProviderBlob(
        std.testing.allocator,
    );
    defer std.testing.allocator.free(blob);
    const header = try rpm_header.Header.parse(blob);
    const pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(pool);
    const repo: *c.Repo = @ptrCast(
        c.repo_create(pool, "@System") orelse return error.OutOfMemory,
    );
    c.pool_set_installed(pool, repo);
    var batch = try InstalledHeaderBatch.init(std.testing.allocator, repo);
    _ = try batch.add(header, 1);
    const one_package_peak = batch.scratch_peak;
    for (2..502) |hnum| _ = try batch.add(header, @intCast(hnum));
    try batch.finish();
    try std.testing.expect(one_package_peak != 0);
    try std.testing.expectEqual(one_package_peak, batch.scratch_peak);
}

pub fn buildInstalledHeaderIntoRepo(
    allocator: std.mem.Allocator,
    repo: *c.Repo,
    header: rpm_header.Header,
    rpmdb_hnum: u32,
) !c.Id {
    var batch = try InstalledHeaderBatch.init(allocator, repo);
    const solvid = try batch.add(header, rpmdb_hnum);
    try batch.finish();
    return solvid;
}

pub fn seedFileProvideDependencies(
    allocator: std.mem.Allocator,
    source_pool: *c.Pool,
    target_pool: *c.Pool,
    target_repo: *c.Repo,
) BuildError!void {
    var dummy: ?*c.Solvable = null;
    for ([_]c.Id{
        c.SOLVABLE_REQUIRES,
        c.SOLVABLE_RECOMMENDS,
        c.SOLVABLE_SUGGESTS,
        c.SOLVABLE_SUPPLEMENTS,
        c.SOLVABLE_ENHANCES,
        c.SOLVABLE_CONFLICTS,
        c.SOLVABLE_OBSOLETES,
    }) |key| {
        var paths = std.ArrayList([]const u8).empty;
        defer paths.deinit(allocator);
        var seen = std.StringHashMapUnmanaged(void).empty;
        defer seen.deinit(allocator);
        var solvid: c.Id = 2;
        while (solvid < source_pool.nsolvables) : (solvid += 1) {
            const raw = c.pool_id2solvable(source_pool, solvid) orelse continue;
            const solvable: *c.Solvable = @ptrCast(raw);
            if (solvable.repo == null) continue;
            var dependencies: c.Queue = undefined;
            c.queue_init(&dependencies);
            defer c.queue_free(&dependencies);
            _ = c.solvable_lookup_deparray(
                solvable,
                key,
                &dependencies,
                0,
            );
            if (dependencies.count != 0) {
                for (dependencies.elements[0..@intCast(dependencies.count)]) |id| {
                    try collectFileProvideDependency(
                        allocator,
                        source_pool,
                        id,
                        0,
                        &seen,
                        &paths,
                    );
                }
            }
        }
        if (paths.items.len == 0) continue;
        if (dummy == null) {
            const dummy_id = c.repo_add_solvable(target_repo);
            dummy = @ptrCast(c.pool_id2solvable(
                target_pool,
                dummy_id,
            ) orelse return error.InvalidRepoMetadata);
        }
        const destination = dependencyOffset(dummy.?, key) orelse
            return error.InvalidRepoMetadata;
        for (paths.items) |path| {
            const path_id = c.pool_strn2id(
                target_pool,
                path.ptr,
                @intCast(path.len),
                1,
            );
            destination.* = c.repo_addid_dep(
                target_repo,
                destination.*,
                path_id,
                0,
            );
        }
    }
    c.repo_internalize(target_repo);
}

fn collectFileProvideDependency(
    allocator: std.mem.Allocator,
    source_pool: *c.Pool,
    dependency: c.Id,
    depth: u8,
    seen: *std.StringHashMapUnmanaged(void),
    paths: *std.ArrayList([]const u8),
) BuildError!void {
    if (depth == 64) return error.InvalidRepoMetadata;
    const bits: u32 = @bitCast(dependency);
    if (bits & 0x80000000 != 0) {
        const index: c.Id = @bitCast(bits ^ 0x80000000);
        if (index <= 0 or index >= source_pool.nrels or
            source_pool.rels == null)
        {
            return error.InvalidRepoMetadata;
        }
        const relation = source_pool.rels[@intCast(index)];
        try collectFileProvideDependency(
            allocator,
            source_pool,
            relation.name,
            depth + 1,
            seen,
            paths,
        );
        try collectFileProvideDependency(
            allocator,
            source_pool,
            relation.evr,
            depth + 1,
            seen,
            paths,
        );
        return;
    }
    if (dependency <= 0) return;
    const raw = c.pool_id2str(source_pool, dependency) orelse
        return error.InvalidRepoMetadata;
    const path = std.mem.span(raw);
    if (path.len == 0 or path[0] != '/') return;
    const entry = try seen.getOrPut(allocator, path);
    if (!entry.found_existing) try paths.append(allocator, path);
}

fn dependencyOffset(solvable: *c.Solvable, key: c.Id) ?*c.Offset {
    return if (key == c.SOLVABLE_REQUIRES)
        &solvable.requires
    else if (key == c.SOLVABLE_RECOMMENDS)
        &solvable.recommends
    else if (key == c.SOLVABLE_SUGGESTS)
        &solvable.suggests
    else if (key == c.SOLVABLE_SUPPLEMENTS)
        &solvable.supplements
    else if (key == c.SOLVABLE_ENHANCES)
        &solvable.enhances
    else if (key == c.SOLVABLE_CONFLICTS)
        &solvable.conflicts
    else if (key == c.SOLVABLE_OBSOLETES)
        &solvable.obsoletes
    else
        null;
}

test "file dependency bridge seeds ten thousand paths by kind" {
    const source_pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(source_pool);
    const target_pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(target_pool);
    const source_repo: *c.Repo = @ptrCast(
        c.repo_create(source_pool, "source") orelse return error.OutOfMemory,
    );
    const target_repo: *c.Repo = @ptrCast(
        c.repo_create(target_pool, "target") orelse return error.OutOfMemory,
    );
    const source_id = c.repo_add_solvable(source_repo);
    const source: *c.Solvable = @ptrCast(
        c.pool_id2solvable(source_pool, source_id) orelse
            return error.OutOfMemory,
    );
    source.name = c.pool_str2id(source_pool, "source", 1);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    inline for (.{
        c.SOLVABLE_REQUIRES,
        c.SOLVABLE_RECOMMENDS,
        c.SOLVABLE_SUGGESTS,
        c.SOLVABLE_SUPPLEMENTS,
        c.SOLVABLE_ENHANCES,
        c.SOLVABLE_CONFLICTS,
        c.SOLVABLE_OBSOLETES,
    }, 0..) |key, key_index| {
        const destination = dependencyOffset(source, key).?;
        var index = key_index;
        while (index < 10_000) : (index += 7) {
            const path = try std.fmt.allocPrintSentinel(
                arena,
                "/bridge/path-{d}",
                .{index},
                0,
            );
            const path_id = c.pool_str2id(source_pool, path.ptr, 1);
            destination.* = c.repo_addid_dep(
                source_repo,
                destination.*,
                path_id,
                0,
            );
        }
    }
    c.repo_internalize(source_repo);
    try seedFileProvideDependencies(
        arena,
        source_pool,
        target_pool,
        target_repo,
    );
    const dummy: *c.Solvable = @ptrCast(
        c.pool_id2solvable(target_pool, target_repo.start) orelse
            return error.TestUnexpectedResult,
    );
    var total: usize = 0;
    inline for (.{
        c.SOLVABLE_REQUIRES,
        c.SOLVABLE_RECOMMENDS,
        c.SOLVABLE_SUGGESTS,
        c.SOLVABLE_SUPPLEMENTS,
        c.SOLVABLE_ENHANCES,
        c.SOLVABLE_CONFLICTS,
        c.SOLVABLE_OBSOLETES,
    }) |key| {
        var queue: c.Queue = undefined;
        c.queue_init(&queue);
        defer c.queue_free(&queue);
        _ = c.solvable_lookup_deparray(dummy, key, &queue, 0);
        total += @intCast(queue.count);
    }
    try std.testing.expectEqual(@as(usize, 10_000), total);
}

test "bridged repository keeps the file provides libsolv reads from the filtered filelist" {
    // Regression pin for the `tdnf plan` failure in #268. `addPrimary` marks
    // its repodata `REPODATA_FILELIST_FILTERED`, and `pool_addfileprovides()`
    // then treats that repodata as the only source for any path the standard
    // filter accepts. When it held no files at all, every file provide in the
    // repository disappeared, so a package requiring `/usr/bin/...` became
    // unresolvable in the rebuilt pool even though the model carried the file.
    const pool = c.pool_create() orelse return error.OutOfMemory;
    defer c.pool_free(pool);
    _ = c.pool_set_flag(pool, c.POOL_FLAG_ADDFILEPROVIDESFILTERED, 1);
    const repo: *c.Repo = @ptrCast(
        c.repo_create(pool, "bridged") orelse return error.OutOfMemory,
    );

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var files = [_]model.FileEntry{
        .{ .path = "/usr/bin/helper" },
        .{ .path = "/usr/share/doc/helper/README" },
    };
    var relations = [_]model.Relation{
        .{ .name = "/usr/bin/helper" },
    };
    var packages = [_]model.Package{
        .{
            .pkg_id = "pkg-helper",
            .nevra = .{ .name = "helper", .epoch = 0, .version = "1.0", .release = "1", .arch = "noarch" },
            .checksum = .{ .kind = "sha256", .value = "11111111111111111111111111111111" },
            .location = .{ .href = "Packages/helper-1.0-1.noarch.rpm" },
            .files = .{ .start = 0, .len = 2 },
        },
        .{
            .pkg_id = "pkg-consumer",
            .nevra = .{ .name = "consumer", .epoch = 0, .version = "1.0", .release = "1", .arch = "noarch" },
            .checksum = .{ .kind = "sha256", .value = "22222222222222222222222222222222" },
            .location = .{ .href = "Packages/consumer-1.0-1.noarch.rpm" },
            .requires = .{ .start = 0, .len = 1 },
        },
    };
    var repository = model.RepositoryModel{
        .packages = packages[0..],
        .relations = relations[0..],
        .files = files[0..],
        .has_filelists = true,
    };

    try buildRepositoryIntoRepo(arena_state.allocator(), repo, &repository);
    c.pool_addfileprovides(pool);
    c.pool_createwhatprovides(pool);

    const path_id = c.pool_str2id(pool, "/usr/bin/helper", 0);
    try std.testing.expect(path_id != 0);
    const pool_ref: *c.Pool = @ptrCast(pool);
    var provider_count: usize = 0;
    var offset = c.pool_whatprovides(pool, path_id);
    while (pool_ref.whatprovidesdata[@intCast(offset)] != 0) : (offset += 1) {
        const provider = c.pool_id2solvable(
            pool,
            pool_ref.whatprovidesdata[@intCast(offset)],
        ) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(
            "helper",
            std.mem.span(c.pool_id2str(pool, provider.*.name).?),
        );
        provider_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), provider_count);
}

fn loadInstalledPackagesIntoBridge(
    arena: std.mem.Allocator,
    bridge: *NativeRpmBridge,
    root_dir: ?[*:0]const u8,
    config: ?*const c.tdnf_rpm_config,
    flags: c_int,
) NativeRpmError!void {
    const iter = (if (config) |cfg|
        c.tdnf_rpmdb_iter_open_config(cfg)
    else
        c.tdnf_rpmdb_iter_open(root_dir)) orelse {
        setError("failed to open rpmdb iterator: {s}", .{std.mem.span(c.tdnf_rpmdb_last_error())});
        return error.RpmDbOpenFailed;
    };
    defer c.tdnf_rpmdb_iter_close(iter);

    while (true) {
        var hnum: u32 = 0;
        var blob_ptr: ?[*]const u8 = null;
        var blob_len: usize = 0;
        const rc = c.tdnf_rpmdb_iter_next_header_blob_hnum(
            iter,
            &hnum,
            &blob_ptr,
            &blob_len,
        );
        if (rc == 0) {
            break;
        }
        if (rc < 0) {
            setError("failed to read rpmdb iterator: {s}", .{std.mem.span(c.tdnf_rpmdb_last_error())});
            return error.RpmDbReadFailed;
        }
        const ptr = blob_ptr orelse continue;
        if (blob_len == 0) {
            continue;
        }

        const blob = ptr[0..blob_len];
        const header = rpm_header.Header.parse(blob) catch {
            setError("failed to parse rpmdb header blob", .{});
            return error.InvalidRpmHeader;
        };
        if ((flags & c.RPMDB_KEEP_GPG_PUBKEY) == 0) {
            if (header.getString(.name)) |name| {
                if (std.mem.eql(u8, name, "gpg-pubkey")) {
                    continue;
                }
            }
        }
        const built = rpmpkg.buildFromHeader(arena, header, .{}) catch |err| {
            setError("failed to build package from rpmdb header: {t}", .{err});
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidRpmHeader,
            };
        };
        _ = bridge.addBuiltPackage(built, header.getU32(.install_time), hnum, null, null, rpmHeaderArchOverride(header)) catch |err| {
            setError("failed to bridge rpmdb package into libsolv: {t}", .{err});
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.InvalidRpmHeader,
            };
        };
    }
}

fn addFileEntry(
    allocator: std.mem.Allocator,
    data: *c.Repodata,
    solvid: c.Id,
    path: []const u8,
) BuildError!void {
    var dir_buf: []const u8 = "/";
    var name_buf: []const u8 = path;
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |separator| {
        if (separator == 0) {
            dir_buf = "/";
            name_buf = path[1..];
        } else {
            dir_buf = path[0..separator];
            name_buf = path[separator + 1 ..];
        }
    }
    const dir_id = c.repodata_str2dir(data, try z(allocator, dir_buf), 1);
    c.repodata_add_dirstr(data, solvid, c.SOLVABLE_FILELIST, dir_id, try z(allocator, name_buf));
}

pub fn buildRepositoryIntoRepo(arena: std.mem.Allocator, repo: *c.Repo, repository: *const model.RepositoryModel) BuildError!void {
    var builder = try SolvBuilder.init(arena, repo, repository, .{});
    return builder.build();
}

fn buildRpmFileHdrid(
    allocator: std.mem.Allocator,
    rpm: *const rpm_pkgfile.RpmFile,
) BuildError!model.PackageChecksum {
    if (rpm.sig.getString(@enumFromInt(@intFromEnum(rpm_header.SigTagId.sha1)))) |value| {
        if (value.len == 40) {
            return .{
                .kind = "sha1",
                .value = value,
            };
        }
    }
    if (rpm.sig.getString(@enumFromInt(@intFromEnum(rpm_header.SigTagId.sha256)))) |value| {
        if (value.len == 64) {
            return .{
                .kind = "sha256",
                .value = value,
            };
        }
    }
    return .{
        .kind = "sha1",
        .value = try checksumHexLower(allocator, "sha1", rpm.main.bytes),
    };
}

fn rpmHeaderArchOverride(hdr: rpm_header.Header) ?c.Id {
    const sourcepackage_tag: rpm_header.TagId = @enumFromInt(1106);
    const nosource_tag: rpm_header.TagId = @enumFromInt(1051);
    const source_rpm = hdr.getString(.source_rpm);

    if ((source_rpm == null or source_rpm.?.len == 0) and hdr.getU32(sourcepackage_tag) != null) {
        if (hdr.getU32(nosource_tag) != null) {
            return c.ARCH_NOSRC;
        }
        return c.ARCH_SRC;
    }
    return null;
}

fn setChecksumZ(data: *c.Repodata, solvid: c.Id, keyname: c.Id, checksum: model.Checksum) BuildError!void {
    const kind = checksum.pszType orelse return error.InvalidRepoMetadata;
    const value = checksum.pszValue orelse return error.InvalidRepoMetadata;
    const chksum_type = c.solv_chksum_str2type(kind);
    if (chksum_type == 0) {
        return error.InvalidRepoMetadata;
    }
    c.repodata_set_checksum(data, solvid, keyname, chksum_type, value);
}

fn setChecksumSlice(allocator: std.mem.Allocator, data: *c.Repodata, solvid: c.Id, keyname: c.Id, kind: []const u8, value: []const u8) BuildError!void {
    const kind_z = try z(allocator, kind);
    const value_z = try z(allocator, value);
    const chksum_type = c.solv_chksum_str2type(kind_z);
    if (chksum_type == 0) {
        return error.InvalidRepoMetadata;
    }
    c.repodata_set_checksum(data, solvid, keyname, chksum_type, value_z);
}

fn checksumHexLower(
    allocator: std.mem.Allocator,
    kind: []const u8,
    bytes: []const u8,
) BuildError![]const u8 {
    if (std.mem.eql(u8, kind, "sha1")) {
        var digest: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(bytes, &digest, .{});
        return hexLower(allocator, &digest);
    }
    if (std.mem.eql(u8, kind, "sha256")) {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        return hexLower(allocator, &digest);
    }
    return error.InvalidRepoMetadata;
}

fn hexLower(allocator: std.mem.Allocator, bytes: []const u8) BuildError![]const u8 {
    const out = allocator.alloc(u8, bytes.len * 2) catch return error.OutOfMemory;
    for (bytes, 0..) |byte, index| {
        out[index * 2] = hexDigit(byte >> 4);
        out[index * 2 + 1] = hexDigit(byte & 0x0f);
    }
    return out;
}

fn hexDigit(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}

fn z(allocator: std.mem.Allocator, value: []const u8) BuildError![*:0]const u8 {
    const duped = allocator.dupeZ(u8, value) catch return error.OutOfMemory;
    return duped.ptr;
}

fn fmtZ(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) BuildError![*:0]const u8 {
    const text = std.fmt.allocPrint(allocator, fmt, args) catch return error.OutOfMemory;
    return z(allocator, text);
}

fn evrId(
    allocator: std.mem.Allocator,
    pool: *c.Pool,
    epoch: ?u32,
    version: []const u8,
    release: []const u8,
) BuildError!c.Id {
    return evrIdOptional(
        allocator,
        pool,
        epoch,
        if (version.len == 0) null else version,
        if (release.len == 0) null else release,
    );
}

fn evrIdOptional(
    allocator: std.mem.Allocator,
    pool: *c.Pool,
    epoch: ?u32,
    version: ?[]const u8,
    release: ?[]const u8,
) BuildError!c.Id {
    if (epoch == null and version == null and release == null) {
        return 0;
    }

    const use_epoch = epoch orelse if (version) |ver|
        if (needsZeroEpoch(ver)) @as(?u32, 0) else null
    else
        null;

    const evr = try fmtZ(
        allocator,
        "{s}{s}{s}",
        .{
            if (use_epoch) |value| try std.fmt.allocPrint(allocator, "{d}:", .{value}) else "",
            version orelse "",
            if (release) |value| try std.fmt.allocPrint(allocator, "-{s}", .{value}) else "",
        },
    );
    if (std.mem.len(evr) == 0) {
        return 0;
    }
    return c.pool_str2id(pool, evr, 1);
}

fn needsZeroEpoch(version: []const u8) bool {
    var index: usize = 0;
    while (index < version.len and version[index] >= '0' and version[index] <= '9') : (index += 1) {}
    return index > 0 and index < version.len and version[index] == ':';
}

fn relationId(
    allocator: std.mem.Allocator,
    pool: *c.Pool,
    relation: model.Relation,
) BuildError!c.Id {
    const name_id = c.pool_str2id(pool, try z(allocator, relation.name), 1);
    if (relation.flags == null or relation.comparison == .none) {
        return name_id;
    }
    const evr = try evrIdOptional(allocator, pool, relation.epoch, relation.version, relation.release);
    return c.pool_rel2id(pool, name_id, evr, compareOpToSolv(relation.comparison), 1);
}

fn relationIdRpmHeader(
    allocator: std.mem.Allocator,
    pool: *c.Pool,
    relation: model.Relation,
) BuildError!c.Id {
    const name_id = c.pool_str2id(pool, try z(allocator, relation.name), 1);
    if (relation.flags == null or relation.comparison == .none) {
        return name_id;
    }
    const evr = try evrIdOptional(
        allocator,
        pool,
        normalizeRpmEpoch(relation.epoch),
        relation.version,
        relation.release,
    );
    return c.pool_rel2id(pool, name_id, evr, compareOpToSolv(relation.comparison), 1);
}

pub fn normalizeRpmEpoch(epoch: ?u32) ?u32 {
    if (epoch) |value| {
        return if (value == 0) null else value;
    }
    return null;
}

fn nativeRpmSetDeps(
    allocator: std.mem.Allocator,
    pool: *c.Pool,
    repo: *c.Repo,
    deps: *c.Offset,
    relations: []const model.Relation,
    is_requires: bool,
) BuildError!void {
    var has_pre = false;
    var out: [*]c.Id = undefined;
    var count: usize = relations.len;

    if (relations.len == 0) {
        return;
    }

    if (is_requires) {
        for (relations) |relation| {
            if (relation.pre) {
                has_pre = true;
                break;
            }
        }
        if (has_pre) {
            count += 1;
        }
    }

    deps.* = c.repo_reserve_ids(repo, 0, @intCast(count));
    out = repo.idarraydata + deps.*;

    if (!has_pre) {
        for (relations) |relation| {
            out[0] = try relationIdRpmHeader(allocator, pool, relation);
            out += 1;
        }
    } else {
        for (relations) |relation| {
            if (relation.pre) {
                continue;
            }
            out[0] = try relationIdRpmHeader(allocator, pool, relation);
            out += 1;
        }
        out[0] = c.SOLVABLE_PREREQMARKER;
        out += 1;
        for (relations) |relation| {
            if (!relation.pre) {
                continue;
            }
            out[0] = try relationIdRpmHeader(allocator, pool, relation);
            out += 1;
        }
    }

    out[0] = 0;
    repo.idarraysize += @intCast(count + 1);
}

fn compareOpToSolv(op: model.CompareOp) c_int {
    return switch (op) {
        .none => 0,
        .eq => c.REL_EQ,
        .lt => c.REL_LT,
        .le => c.REL_LT | c.REL_EQ,
        .gt => c.REL_GT,
        .ge => c.REL_GT | c.REL_EQ,
    };
}

fn addAdvisoryConflict(repo: *c.Repo, pool: *c.Pool, solvid: c.Id, name_id: c.Id, arch_id: c.Id, evr_id: c.Id) void {
    var conflict: c.Id = 0;
    if (arch_id != 0 and arch_id != c.ARCH_NOARCH) {
        conflict = c.pool_rel2id(pool, name_id, arch_id, c.REL_ARCH, 1);
        conflict = c.pool_rel2id(pool, conflict, evr_id, c.REL_LT, 1);
        c.repo_add_deparray(repo, solvid, c.SOLVABLE_CONFLICTS, conflict, 0);
        conflict = c.pool_rel2id(pool, name_id, c.ARCH_NOARCH, c.REL_ARCH, 1);
        conflict = c.pool_rel2id(pool, conflict, evr_id, c.REL_LT, 1);
        c.repo_add_deparray(repo, solvid, c.SOLVABLE_CONFLICTS, conflict, 0);
    } else {
        conflict = c.pool_rel2id(pool, name_id, evr_id, c.REL_LT, 1);
        c.repo_add_deparray(repo, solvid, c.SOLVABLE_CONFLICTS, conflict, 0);
    }
}

fn advisoryBuildTime(advisory: model.Advisory) u64 {
    const issued = if (advisory.issued) |text| parseDateToTimestamp(text) else 0;
    const updated = if (advisory.updated) |text| parseDateToTimestamp(text) else 0;
    return if (updated > issued) updated else issued;
}

fn parseDateToTimestamp(text: []const u8) u64 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);

    if (trimmed.len == 0) {
        return 0;
    }
    const numeric = std.fmt.parseInt(u64, trimmed, 10) catch null;
    if (numeric) |value| {
        return value;
    }

    const parts = parseIsoDateTime(trimmed) orelse return 0;
    tm.tm_year = @intCast(parts.year - 1900);
    tm.tm_mon = @intCast(parts.month - 1);
    tm.tm_mday = @intCast(parts.day);
    tm.tm_hour = @intCast(parts.hour);
    tm.tm_min = @intCast(parts.minute);
    tm.tm_sec = @intCast(parts.second);

    const stamp = c.timegm(&tm);
    return if (stamp >= 0) @intCast(stamp) else 0;
}

const ParsedDateTime = struct {
    year: u32,
    month: u32,
    day: u32,
    hour: u32,
    minute: u32,
    second: u32,
};

fn parseIsoDateTime(text: []const u8) ?ParsedDateTime {
    if (text.len != 19 or (text[10] != ' ' and text[10] != 'T')) {
        return null;
    }
    if (text[4] != '-' or text[7] != '-' or text[13] != ':' or text[16] != ':') {
        return null;
    }

    const year = std.fmt.parseInt(u32, text[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u32, text[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u32, text[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u32, text[11..13], 10) catch return null;
    const minute = std.fmt.parseInt(u32, text[14..16], 10) catch return null;
    const second = std.fmt.parseInt(u32, text[17..19], 10) catch return null;

    if (year < 1900 or month < 1 or month > 12 or day < 1 or day > 31 or
        hour > 23 or minute > 59 or second > 60)
    {
        return null;
    }

    return .{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
    };
}

fn sameOptional(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null and right == null) return true;
    if (left == null or right == null) return false;
    return std.mem.eql(u8, left.?, right.?);
}
