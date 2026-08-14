const std = @import("std");
const builtin = @import("builtin");
const result_abi = @import("solver_result_abi.zig");
const legacy_abi = @import("solver_legacy_abi.zig");

pub const LegacyResult = legacy_abi.LegacyResult;
pub const LegacyPackage = legacy_abi.LegacyPackage;

/// A bucket entry: one target or prior named by an action plus the job that
/// asked for it, which is what orders the bucket.
const BucketRef = struct {
    ref: u32,
    job: ?u32,
};

const RefList = std.array_list.Managed(BucketRef);

/// `libcommon` owns the shipped size formatter, but the repomd unit-test
/// binary does not link it. Only the rendering of a byte count is stubbed
/// there; every projection decision under test is unaffected.
const format_size = if (builtin.is_test)
    testFormatSize
else
    struct {
        extern fn TDNFUtilsFormatSize(
            unSize: u64,
            ppszFormattedSize: ?*?[*:0]u8,
        ) u32;
    }.TDNFUtilsFormatSize;

fn testFormatSize(unSize: u64, ppszFormattedSize: ?*?[*:0]u8) callconv(.c) u32 {
    var buffer: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{unSize}) catch return 1;
    const out = ppszFormattedSize orelse return 1;
    out.* = dupe(text) catch return 1;
    return 0;
}

pub const BuildError = error{
    InvalidInput,
    OutOfMemory,
};

const action_install: u32 = 1;
const action_erase: u32 = 2;
const action_upgrade: u32 = 3;
const action_downgrade: u32 = 4;
const action_reinstall: u32 = 5;
const action_obsolete: u32 = 6;

const hash_md5: c_int = 0;
const hash_sha1: c_int = 1;
const hash_sha256: c_int = 2;
const hash_sha512: c_int = 3;

/// Which package of an action a legacy bucket names: the package the action
/// installs, the installed package it displaces, or -- for the removal
/// bucket -- whichever of the two the action actually removes.
const Side = enum { target, prior, removal };

const Bucket = struct {
    kinds: []const u32,
    side: Side,
};

/// The legacy buckets, in the order `TDNF_SOLVED_PKG_INFO` declares them.
///
/// The projection the corpus-wide crosscheck validated against libsolv before
/// the native solver became authoritative. An obsoleting package reaches
/// `pPkgsToInstall` as a target, while the package it obsoletes reaches both
/// `pPkgsToRemove` and `pPkgsObsoleted` as a prior, which is how libsolv's
/// transaction reported it.
const buckets = [_]Bucket{
    .{ .kinds = &.{ action_install, action_obsolete }, .side = .target },
    .{ .kinds = &.{action_upgrade}, .side = .target },
    .{ .kinds = &.{action_downgrade}, .side = .target },
    .{ .kinds = &.{ action_erase, action_obsolete }, .side = .removal },
    .{ .kinds = &.{action_reinstall}, .side = .target },
    .{ .kinds = &.{action_obsolete}, .side = .prior },
    .{ .kinds = &.{action_downgrade}, .side = .prior },
};

/// `include_reinstall` mirrors tdnf's `nReInstall`: the legacy path only ever
/// asked libsolv for `SOLVER_TRANSACTION_REINSTALL` when the caller had asked
/// for a reinstall, so without it a reinstalled package is absent from the
/// plan entirely rather than reported in some other bucket.
pub fn build(
    allocator: std.mem.Allocator,
    result: *const result_abi.Result,
    include_reinstall: bool,
    output: *[*c]legacy_abi.LegacyResult,
) BuildError!void {
    output.* = null;

    const raw = std.c.calloc(1, @sizeOf(legacy_abi.LegacyResult)) orelse
        return error.OutOfMemory;
    const solved: *legacy_abi.LegacyResult = @ptrCast(@alignCast(raw));
    errdefer freeSolved(solved);

    const targets = [_]*[*c]legacy_abi.LegacyPackage{
        &solved.pPkgsToInstall,
        &solved.pPkgsToUpgrade,
        &solved.pPkgsToDowngrade,
        &solved.pPkgsToRemove,
        &solved.pPkgsToReinstall,
        &solved.pPkgsObsoleted,
        &solved.pPkgsRemovedByDowngrade,
    };

    for (buckets, targets) |bucket, slot| {
        if (!include_reinstall and
            bucket.kinds.len == 1 and bucket.kinds[0] == action_reinstall)
        {
            continue;
        }
        slot.* = try buildBucket(allocator, result, bucket);
    }

    output.* = solved;
}

fn buildBucket(
    allocator: std.mem.Allocator,
    result: *const result_abi.Result,
    bucket: Bucket,
) BuildError![*c]legacy_abi.LegacyPackage {
    var refs = RefList.init(allocator);
    defer refs.deinit();

    if (result.dwActionCount != 0) {
        for (result.pActions[0..result.dwActionCount]) |action| {
            if (!containsKind(bucket.kinds, action.dwKind)) continue;
            try appendBucketRefs(&refs, result, action, bucket.side);
        }
    }
    if (refs.items.len == 0) return null;

    std.mem.sort(BucketRef, refs.items, result, packageRefLessThan);

    var head: [*c]legacy_abi.LegacyPackage = null;
    var tail: [*c]legacy_abi.LegacyPackage = null;
    errdefer freePackageList(head);

    // Emit the reverse of the canonical order. TDNFPopulatePkgInfosFromRefs
    // (TDNFPopulatePkgInfos before it was taken off the solv layer) built
    // every bucket by prepending, so the list handed to the transaction
    // executor was the reverse of the order libsolv walked. That order is the
    // executor's last tie-break between packages with no dependency edge
    // between them (transaction_native.lessPhaseNode), and rpm's own tie-break
    // is likewise the reverse of the order packages entered the transaction,
    // so reversing here is what keeps the installed-file and file-trigger
    // sequence identical to what rpm itself produces.
    var index = refs.items.len;
    while (index > 0) {
        index -= 1;
        const package: *const result_abi.Package = @ptrCast(
            &result.pPackages[refs.items[index].ref],
        );
        const node = try buildPackage(package);
        if (tail) |previous| {
            previous[0].pNext = node;
        } else {
            head = node;
        }
        tail = node;
    }

    return head;
}

fn appendBucketRefs(
    refs: *RefList,
    result: *const result_abi.Result,
    action: result_abi.Action,
    side: Side,
) BuildError!void {
    const job = if (action.nHasRequestedJobId != 0)
        action.dwRequestedJobId
    else
        null;
    if (side == .target or
        (side == .removal and action.dwKind != action_obsolete))
    {
        if (action.dwPackageRef >= result.dwPackageCount)
            return error.InvalidInput;
        try refs.append(.{ .ref = action.dwPackageRef, .job = job });
        return;
    }
    if (action.dwPriorCount == 0 or
        action.dwPriorOffset > result.dwPriorPackageRefCount or
        action.dwPriorCount >
            result.dwPriorPackageRefCount - action.dwPriorOffset or
        result.pdwPriorPackageRefs == null)
    {
        return error.InvalidInput;
    }
    const offset: usize = action.dwPriorOffset;
    const count: usize = action.dwPriorCount;
    for (result.pdwPriorPackageRefs[offset..][0..count]) |ref| {
        if (ref >= result.dwPackageCount) return error.InvalidInput;
        try refs.append(.{ .ref = ref, .job = job });
    }
}

fn containsKind(kinds: []const u32, kind: u32) bool {
    for (kinds) |candidate| {
        if (candidate == kind) return true;
    }
    return false;
}

/// Orders a bucket so that reversing it reproduces the legacy list.
///
/// Packages nobody asked for by name sort first, then the packages a job named
/// in job order -- jobs are built from the command line in order, so reversing
/// the result hands the transaction executor the packages in the reverse of
/// the order the user wrote them, which is what libsolv plus
/// TDNFPopulatePkgInfosFromRefs used to produce and what rpm's own ordering
/// expects.
fn packageRefLessThan(
    result: *const result_abi.Result,
    left_ref: BucketRef,
    right_ref: BucketRef,
) bool {
    if ((left_ref.job == null) != (right_ref.job == null)) {
        return left_ref.job == null;
    }
    if (left_ref.job) |left_job| {
        const right_job = right_ref.job.?;
        if (left_job != right_job) return left_job < right_job;
    }
    const left = left_ref.ref;
    const right = right_ref.ref;
    const a: *const result_abi.Package = @ptrCast(&result.pPackages[left]);
    const b: *const result_abi.Package = @ptrCast(&result.pPackages[right]);
    const name_order = std.mem.order(u8, span(a.pszName), span(b.pszName));
    if (name_order != .eq) return name_order == .lt;
    const arch_order = std.mem.order(u8, span(a.pszArch), span(b.pszArch));
    if (arch_order != .eq) return arch_order == .lt;
    if (a.dwEpoch != b.dwEpoch) return a.dwEpoch < b.dwEpoch;
    const version_order = std.mem.order(u8, span(a.pszVersion), span(b.pszVersion));
    if (version_order != .eq) return version_order == .lt;
    const release_order = std.mem.order(u8, span(a.pszRelease), span(b.pszRelease));
    if (release_order != .eq) return release_order == .lt;
    return left < right;
}

fn buildPackage(package: *const result_abi.Package) BuildError![*c]legacy_abi.LegacyPackage {
    const raw = std.c.calloc(1, @sizeOf(legacy_abi.LegacyPackage)) orelse
        return error.OutOfMemory;
    const info: [*c]legacy_abi.LegacyPackage = @ptrCast(@alignCast(raw));
    errdefer freePackageList(info);

    info[0].dwEpoch = if (package.nHasEpoch != 0) package.dwEpoch else 0;
    info[0].pszName = try dupe(span(package.pszName));
    info[0].pszVersion = try dupe(span(package.pszVersion));
    info[0].pszRelease = try dupe(span(package.pszRelease));
    info[0].pszArch = try dupe(span(package.pszArch));
    info[0].pszRepoName = try dupe(span(package.pszRepository));
    info[0].dwSourcePackageHandle = package.dwSourcePackageHandle;
    info[0].pszEVR = try dupeEvr(
        info[0].dwEpoch,
        span(package.pszVersion),
        span(package.pszRelease),
    );

    const summary = span(package.pszSummary);
    if (summary.len != 0) {
        info[0].pszSummary = try dupe(summary);
    }

    try fillLocation(info, package);
    try fillChecksum(info, package);

    const install_size: u64 = if (package.nHasInstalledSize != 0)
        package.nInstalledSize
    else
        0;
    const download_size: u64 = if (package.nHasPackageSize != 0)
        package.nPackageSize
    else
        0;
    info[0].dwInstallSizeBytes = truncate(install_size);
    info[0].dwDownloadSizeBytes = truncate(download_size);
    var formatted_install: ?[*:0]u8 = null;
    if (format_size(install_size, &formatted_install) != 0) {
        return error.OutOfMemory;
    }
    info[0].pszFormattedSize = formatted_install;

    var formatted_download: ?[*:0]u8 = null;
    if (format_size(download_size, &formatted_download) != 0) {
        return error.OutOfMemory;
    }
    info[0].pszFormattedDownloadSize = formatted_download;

    return info;
}

fn fillLocation(
    info: [*c]legacy_abi.LegacyPackage,
    package: *const result_abi.Package,
) BuildError!void {
    const href = span(package.pszLocationHref);
    if (href.len == 0) return;

    const base = span(package.pszLocationBase);
    if (base.len == 0) {
        info[0].pszLocation = try dupe(href);
        return;
    }

    const separator: usize = if (base[base.len - 1] == '/') 0 else 1;
    const total = base.len + separator + href.len;
    const raw = std.c.calloc(total + 1, 1) orelse return error.OutOfMemory;
    const out: [*]u8 = @ptrCast(raw);
    @memcpy(out[0..base.len], base);
    if (separator != 0) out[base.len] = '/';
    @memcpy(out[base.len + separator ..][0..href.len], href);
    out[total] = 0;
    info[0].pszLocation = @ptrCast(out);
}

fn fillChecksum(
    info: [*c]legacy_abi.LegacyPackage,
    package: *const result_abi.Package,
) BuildError!void {
    // A header-only digest is not the digest of the package file, so it must
    // not reach the download verifier. Only repository metadata advertises a
    // file digest; packages recovered from an on-disk RPM or from the rpmdb
    // carry a header digest instead, which is what libsolv exposed as
    // SOLVABLE_PKGID rather than SOLVABLE_CHECKSUM.
    if (package.nChecksumIsHeaderOnly != 0) return;

    const digest = span(package.pszChecksumValue);
    if (digest.len == 0 or digest.len % 2 != 0) return;

    const kind = checksumKind(span(package.pszChecksumType)) orelse return;
    const length = digest.len / 2;

    const raw = std.c.calloc(length, 1) orelse return error.OutOfMemory;
    const bytes: [*]u8 = @ptrCast(raw);
    var index: usize = 0;
    while (index < length) : (index += 1) {
        const high = hexDigit(digest[index * 2]) orelse {
            std.c.free(raw);
            return;
        };
        const low = hexDigit(digest[index * 2 + 1]) orelse {
            std.c.free(raw);
            return;
        };
        bytes[index] = (high << 4) | low;
    }

    info[0].pbChecksum = @ptrCast(bytes);
    info[0].nChecksumType = kind;
}

fn checksumKind(name: []const u8) ?c_int {
    if (eqlIgnoreCase(name, "md5")) return hash_md5;
    if (eqlIgnoreCase(name, "sha1") or eqlIgnoreCase(name, "sha-1")) {
        return hash_sha1;
    }
    if (eqlIgnoreCase(name, "sha256") or eqlIgnoreCase(name, "sha-256")) {
        return hash_sha256;
    }
    if (eqlIgnoreCase(name, "sha512") or eqlIgnoreCase(name, "sha-512")) {
        return hash_sha512;
    }
    return null;
}

fn eqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

fn hexDigit(character: u8) ?u8 {
    return switch (character) {
        '0'...'9' => character - '0',
        'a'...'f' => character - 'a' + 10,
        'A'...'F' => character - 'A' + 10,
        else => null,
    };
}

fn dupeEvr(
    epoch: u32,
    version: []const u8,
    release: []const u8,
) BuildError![*:0]u8 {
    var buffer: [16]u8 = undefined;
    const prefix = if (epoch == 0)
        ""
    else
        std.fmt.bufPrint(&buffer, "{d}:", .{epoch}) catch
            return error.OutOfMemory;

    const total = prefix.len + version.len + 1 + release.len;
    const raw = std.c.calloc(total + 1, 1) orelse return error.OutOfMemory;
    const out: [*]u8 = @ptrCast(raw);
    @memcpy(out[0..prefix.len], prefix);
    @memcpy(out[prefix.len..][0..version.len], version);
    out[prefix.len + version.len] = '-';
    @memcpy(out[prefix.len + version.len + 1 ..][0..release.len], release);
    out[total] = 0;
    return @ptrCast(out);
}

fn dupe(text: []const u8) BuildError![*:0]u8 {
    const raw = std.c.calloc(text.len + 1, 1) orelse return error.OutOfMemory;
    const out: [*]u8 = @ptrCast(raw);
    @memcpy(out[0..text.len], text);
    out[text.len] = 0;
    return @ptrCast(out);
}

fn span(text: ?[*:0]const u8) []const u8 {
    const value = text orelse return "";
    return std.mem.span(value);
}

fn truncate(value: u64) u32 {
    return if (value > std.math.maxInt(u32))
        std.math.maxInt(u32)
    else
        @intCast(value);
}

/// Release a result. This module allocates every field it sets with `calloc`,
/// exactly as `TDNFFreePackageInfoContents` expects, so a caller is free to
/// release a returned result with `TDNFFreeSolvedPackageInfo` instead.
pub fn free(solved: [*c]legacy_abi.LegacyResult) void {
    const result: ?*legacy_abi.LegacyResult = @ptrCast(solved);
    if (result) |value| freeSolved(value);
}

fn freeSolved(solved: *legacy_abi.LegacyResult) void {
    freePackageList(solved.pPkgsToInstall);
    freePackageList(solved.pPkgsToUpgrade);
    freePackageList(solved.pPkgsToDowngrade);
    freePackageList(solved.pPkgsToRemove);
    freePackageList(solved.pPkgsToReinstall);
    freePackageList(solved.pPkgsObsoleted);
    freePackageList(solved.pPkgsRemovedByDowngrade);
    std.c.free(solved);
}

fn freePackageList(head: [*c]legacy_abi.LegacyPackage) void {
    var node = head;
    while (node != null) {
        const next = node[0].pNext;
        freeOptional(node[0].pszName);
        freeOptional(node[0].pszRepoName);
        freeOptional(node[0].pszVersion);
        freeOptional(node[0].pszRelease);
        freeOptional(node[0].pszArch);
        freeOptional(node[0].pszEVR);
        freeOptional(node[0].pszSummary);
        freeOptional(node[0].pszLocation);
        freeOptional(node[0].pszFormattedSize);
        freeOptional(node[0].pszFormattedDownloadSize);
        if (node[0].pbChecksum) |checksum| std.c.free(checksum);
        std.c.free(node);
        node = next;
    }
}

fn freeOptional(text: ?[*:0]const u8) void {
    if (text) |value| std.c.free(@constCast(value));
}

const testing = std.testing;

const TestPackage = struct {
    repository: [:0]const u8,
    name: [:0]const u8,
    version: [:0]const u8,
    release: [:0]const u8,
    arch: [:0]const u8,
    epoch: u32 = 0,
    checksum_type: [:0]const u8 = "sha256",
    checksum_value: [:0]const u8 = "",
    checksum_is_header_only: bool = false,
    location_href: [:0]const u8 = "",
    location_base: [:0]const u8 = "",
    summary: [:0]const u8 = "",
    package_size: u64 = 0,
    installed_size: u64 = 0,
};

fn testPackage(source: TestPackage) result_abi.Package {
    return .{
        .pszRepository = source.repository.ptr,
        .pszName = source.name.ptr,
        .pszVersion = source.version.ptr,
        .pszRelease = source.release.ptr,
        .pszArch = source.arch.ptr,
        .pszChecksumType = source.checksum_type.ptr,
        .pszChecksumValue = source.checksum_value.ptr,
        .pszLocationHref = source.location_href.ptr,
        .pszLocationBase = source.location_base.ptr,
        .pszSummary = source.summary.ptr,
        .nPackageSize = source.package_size,
        .nInstalledSize = source.installed_size,
        .dwPackageId = 0,
        .dwRepositoryId = 0,
        .dwEpoch = source.epoch,
        .dwRpmDbHnum = 0,
        .nRepositoryKind = 0,
        .nHasEpoch = @intFromBool(source.epoch != 0),
        .nHasRpmDbHnum = 0,
        .nChecksumIsPkgId = 0,
        .nChecksumIsHeaderOnly = @intFromBool(source.checksum_is_header_only),
        .nHasPackageSize = @intFromBool(source.package_size != 0),
        .nHasInstalledSize = @intFromBool(source.installed_size != 0),
        .dwSourcePackageHandle = 0,
    };
}

fn listNames(
    allocator: std.mem.Allocator,
    head: [*c]legacy_abi.LegacyPackage,
) ![]const []const u8 {
    var names: std.array_list.Managed([]const u8) = .init(allocator);
    errdefer names.deinit();
    var node = head;
    while (node != null) : (node = node[0].pNext) {
        try names.append(std.mem.span(node[0].pszName.?));
    }
    return names.toOwnedSlice();
}

test "projects install, erase, and upgrade actions into legacy buckets" {
    var packages = [_]result_abi.Package{
        testPackage(.{
            .repository = "base",
            .name = "zeta",
            .version = "2",
            .release = "1",
            .arch = "x86_64",
        }),
        testPackage(.{
            .repository = "base",
            .name = "alpha",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
        testPackage(.{
            .repository = "@System",
            .name = "alpha",
            .version = "0",
            .release = "1",
            .arch = "x86_64",
        }),
    };
    var priors = [_]u32{2};
    var hnums = [_]u32{0};
    var actions = [_]result_abi.Action{
        .{
            .dwPackageRef = 0,
            .dwKind = action_install,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 0,
            .dwRequestedJobId = 0,
            .nHasRequestedJobId = 0,
        },
        .{
            .dwPackageRef = 1,
            .dwKind = action_upgrade,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 1,
            .dwRequestedJobId = 0,
            .nHasRequestedJobId = 0,
        },
    };
    const result = result_abi.Result{
        .pPackages = &packages,
        .pdwSelectedPackageRefs = undefined,
        .pActions = &actions,
        .pdwPriorPackageRefs = &priors,
        .pdwPriorHnums = &hnums,
        .pProblems = undefined,
        .pdwSkippedJobIds = undefined,
        .dwPackageCount = packages.len,
        .dwSelectedPackageCount = 0,
        .dwActionCount = actions.len,
        .dwPriorPackageRefCount = priors.len,
        .dwProblemCount = 0,
        .dwSkippedJobCount = 0,
    };

    var solved: [*c]legacy_abi.LegacyResult = null;
    try build(testing.allocator, &result, true, &solved);
    defer freeSolved(solved);

    const install = try listNames(testing.allocator, solved[0].pPkgsToInstall);
    defer testing.allocator.free(install);
    try testing.expectEqual(@as(usize, 1), install.len);
    try testing.expectEqualStrings("zeta", install[0]);

    const upgrade = try listNames(testing.allocator, solved[0].pPkgsToUpgrade);
    defer testing.allocator.free(upgrade);
    try testing.expectEqual(@as(usize, 1), upgrade.len);
    try testing.expectEqualStrings("alpha", upgrade[0]);

    try testing.expect(solved[0].pPkgsToRemove == null);
    try testing.expect(solved[0].pPkgsObsoleted == null);
    try testing.expectEqualStrings(
        "2-1",
        std.mem.span(solved[0].pPkgsToInstall[0].pszEVR.?),
    );
    try testing.expectEqualStrings(
        "base",
        std.mem.span(solved[0].pPkgsToInstall[0].pszRepoName.?),
    );
}

test "an obsoleting action reaches install, remove, and obsoleted" {
    var packages = [_]result_abi.Package{
        testPackage(.{
            .repository = "base",
            .name = "successor",
            .version = "2",
            .release = "1",
            .arch = "x86_64",
            .epoch = 3,
            .location_href = "successor.rpm",
            .location_base = "https://example.test/repo",
        }),
        testPackage(.{
            .repository = "@System",
            .name = "predecessor",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
    };
    var priors = [_]u32{1};
    var hnums = [_]u32{0};
    var actions = [_]result_abi.Action{.{
        .dwPackageRef = 0,
        .dwKind = action_obsolete,
        .dwReason = 0,
        .dwPriorOffset = 0,
        .dwPriorCount = 1,
        .dwRequestedJobId = 0,
        .nHasRequestedJobId = 0,
    }};
    const result = result_abi.Result{
        .pPackages = &packages,
        .pdwSelectedPackageRefs = undefined,
        .pActions = &actions,
        .pdwPriorPackageRefs = &priors,
        .pdwPriorHnums = &hnums,
        .pProblems = undefined,
        .pdwSkippedJobIds = undefined,
        .dwPackageCount = packages.len,
        .dwSelectedPackageCount = 0,
        .dwActionCount = actions.len,
        .dwPriorPackageRefCount = priors.len,
        .dwProblemCount = 0,
        .dwSkippedJobCount = 0,
    };

    var solved: [*c]legacy_abi.LegacyResult = null;
    try build(testing.allocator, &result, true, &solved);
    defer freeSolved(solved);

    try testing.expectEqualStrings(
        "successor",
        std.mem.span(solved[0].pPkgsToInstall[0].pszName.?),
    );
    try testing.expectEqualStrings(
        "predecessor",
        std.mem.span(solved[0].pPkgsToRemove[0].pszName.?),
    );
    try testing.expectEqualStrings(
        "predecessor",
        std.mem.span(solved[0].pPkgsObsoleted[0].pszName.?),
    );
    try testing.expectEqualStrings(
        "3:2-1",
        std.mem.span(solved[0].pPkgsToInstall[0].pszEVR.?),
    );
    try testing.expectEqualStrings(
        "https://example.test/repo/successor.rpm",
        std.mem.span(solved[0].pPkgsToInstall[0].pszLocation.?),
    );
}

test "a downgrade names the displaced package in its own bucket" {
    var packages = [_]result_abi.Package{
        testPackage(.{
            .repository = "base",
            .name = "pkg",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
        testPackage(.{
            .repository = "@System",
            .name = "pkg",
            .version = "2",
            .release = "1",
            .arch = "x86_64",
        }),
    };
    var priors = [_]u32{1};
    var hnums = [_]u32{0};
    var actions = [_]result_abi.Action{.{
        .dwPackageRef = 0,
        .dwKind = action_downgrade,
        .dwReason = 0,
        .dwPriorOffset = 0,
        .dwPriorCount = 1,
        .dwRequestedJobId = 0,
        .nHasRequestedJobId = 0,
    }};
    const result = result_abi.Result{
        .pPackages = &packages,
        .pdwSelectedPackageRefs = undefined,
        .pActions = &actions,
        .pdwPriorPackageRefs = &priors,
        .pdwPriorHnums = &hnums,
        .pProblems = undefined,
        .pdwSkippedJobIds = undefined,
        .dwPackageCount = packages.len,
        .dwSelectedPackageCount = 0,
        .dwActionCount = actions.len,
        .dwPriorPackageRefCount = priors.len,
        .dwProblemCount = 0,
        .dwSkippedJobCount = 0,
    };

    var solved: [*c]legacy_abi.LegacyResult = null;
    try build(testing.allocator, &result, true, &solved);
    defer freeSolved(solved);

    try testing.expectEqualStrings(
        "1-1",
        std.mem.span(solved[0].pPkgsToDowngrade[0].pszEVR.?),
    );
    try testing.expectEqualStrings(
        "2-1",
        std.mem.span(solved[0].pPkgsRemovedByDowngrade[0].pszEVR.?),
    );
    try testing.expect(solved[0].pPkgsToRemove == null);
}

test "buckets are ordered by descending name so output does not depend on action order" {
    var packages = [_]result_abi.Package{
        testPackage(.{
            .repository = "base",
            .name = "gamma",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
        testPackage(.{
            .repository = "base",
            .name = "alpha",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
        testPackage(.{
            .repository = "base",
            .name = "beta",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
    };
    var actions = [_]result_abi.Action{
        .{
            .dwPackageRef = 0,
            .dwKind = action_install,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 0,
            .dwRequestedJobId = 0,
            .nHasRequestedJobId = 0,
        },
        .{
            .dwPackageRef = 1,
            .dwKind = action_install,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 0,
            .dwRequestedJobId = 0,
            .nHasRequestedJobId = 0,
        },
        .{
            .dwPackageRef = 2,
            .dwKind = action_install,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 0,
            .dwRequestedJobId = 0,
            .nHasRequestedJobId = 0,
        },
    };
    const result = result_abi.Result{
        .pPackages = &packages,
        .pdwSelectedPackageRefs = undefined,
        .pActions = &actions,
        .pdwPriorPackageRefs = undefined,
        .pdwPriorHnums = undefined,
        .pProblems = undefined,
        .pdwSkippedJobIds = undefined,
        .dwPackageCount = packages.len,
        .dwSelectedPackageCount = 0,
        .dwActionCount = actions.len,
        .dwPriorPackageRefCount = 0,
        .dwProblemCount = 0,
        .dwSkippedJobCount = 0,
    };

    var solved: [*c]legacy_abi.LegacyResult = null;
    try build(testing.allocator, &result, true, &solved);
    defer freeSolved(solved);

    const install = try listNames(testing.allocator, solved[0].pPkgsToInstall);
    defer testing.allocator.free(install);
    try testing.expectEqual(@as(usize, 3), install.len);
    try testing.expectEqualStrings("gamma", install[0]);
    try testing.expectEqualStrings("beta", install[1]);
    try testing.expectEqualStrings("alpha", install[2]);
}

test "requested packages are emitted in reverse job order ahead of their dependencies" {
    var packages = [_]result_abi.Package{
        testPackage(.{
            .repository = "base",
            .name = "owner",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
        testPackage(.{
            .repository = "base",
            .name = "shared-a",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
        testPackage(.{
            .repository = "base",
            .name = "shared-b",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
        testPackage(.{
            .repository = "base",
            .name = "pulled-in",
            .version = "1",
            .release = "1",
            .arch = "x86_64",
        }),
    };
    var actions = [_]result_abi.Action{
        .{
            .dwPackageRef = 3,
            .dwKind = action_install,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 0,
            .dwRequestedJobId = 0,
            .nHasRequestedJobId = 0,
        },
        .{
            .dwPackageRef = 2,
            .dwKind = action_install,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 0,
            .dwRequestedJobId = 2,
            .nHasRequestedJobId = 1,
        },
        .{
            .dwPackageRef = 0,
            .dwKind = action_install,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 0,
            .dwRequestedJobId = 0,
            .nHasRequestedJobId = 1,
        },
        .{
            .dwPackageRef = 1,
            .dwKind = action_install,
            .dwReason = 0,
            .dwPriorOffset = 0,
            .dwPriorCount = 0,
            .dwRequestedJobId = 1,
            .nHasRequestedJobId = 1,
        },
    };
    const result = result_abi.Result{
        .pPackages = &packages,
        .pdwSelectedPackageRefs = undefined,
        .pActions = &actions,
        .pdwPriorPackageRefs = undefined,
        .pdwPriorHnums = undefined,
        .pProblems = undefined,
        .pdwSkippedJobIds = undefined,
        .dwPackageCount = packages.len,
        .dwSelectedPackageCount = 0,
        .dwActionCount = actions.len,
        .dwPriorPackageRefCount = 0,
        .dwProblemCount = 0,
        .dwSkippedJobCount = 0,
    };

    var solved: [*c]legacy_abi.LegacyResult = null;
    try build(testing.allocator, &result, true, &solved);
    defer freeSolved(solved);

    const install = try listNames(testing.allocator, solved[0].pPkgsToInstall);
    defer testing.allocator.free(install);
    try testing.expectEqual(@as(usize, 4), install.len);
    try testing.expectEqualStrings("shared-b", install[0]);
    try testing.expectEqualStrings("shared-a", install[1]);
    try testing.expectEqualStrings("owner", install[2]);
    try testing.expectEqualStrings("pulled-in", install[3]);
}

test "an empty transaction produces empty buckets" {
    const result = result_abi.Result{
        .pPackages = undefined,
        .pdwSelectedPackageRefs = undefined,
        .pActions = undefined,
        .pdwPriorPackageRefs = undefined,
        .pdwPriorHnums = undefined,
        .pProblems = undefined,
        .pdwSkippedJobIds = undefined,
        .dwPackageCount = 0,
        .dwSelectedPackageCount = 0,
        .dwActionCount = 0,
        .dwPriorPackageRefCount = 0,
        .dwProblemCount = 0,
        .dwSkippedJobCount = 0,
    };

    var solved: [*c]legacy_abi.LegacyResult = null;
    try build(testing.allocator, &result, true, &solved);
    defer freeSolved(solved);

    try testing.expect(solved != null);
    try testing.expect(solved[0].pPkgsToInstall == null);
    try testing.expect(solved[0].pPkgsToRemove == null);
    try testing.expect(solved[0].pPkgsToUpgrade == null);
}

test "a checksum becomes raw digest bytes with a hash kind" {
    var packages = [_]result_abi.Package{testPackage(.{
        .repository = "base",
        .name = "pkg",
        .version = "1",
        .release = "1",
        .arch = "x86_64",
        .checksum_type = "SHA-256",
        .checksum_value = "0a1b2c",
    })};
    packages[0].dwSourcePackageHandle = 73;
    var actions = [_]result_abi.Action{.{
        .dwPackageRef = 0,
        .dwKind = action_install,
        .dwReason = 0,
        .dwPriorOffset = 0,
        .dwPriorCount = 0,
        .dwRequestedJobId = 0,
        .nHasRequestedJobId = 0,
    }};
    const result = result_abi.Result{
        .pPackages = &packages,
        .pdwSelectedPackageRefs = undefined,
        .pActions = &actions,
        .pdwPriorPackageRefs = undefined,
        .pdwPriorHnums = undefined,
        .pProblems = undefined,
        .pdwSkippedJobIds = undefined,
        .dwPackageCount = packages.len,
        .dwSelectedPackageCount = 0,
        .dwActionCount = actions.len,
        .dwPriorPackageRefCount = 0,
        .dwProblemCount = 0,
        .dwSkippedJobCount = 0,
    };

    var solved: [*c]legacy_abi.LegacyResult = null;
    try build(testing.allocator, &result, true, &solved);
    defer freeSolved(solved);

    const info = solved[0].pPkgsToInstall;
    try testing.expectEqual(hash_sha256, info[0].nChecksumType);
    const digest: [*]const u8 = @ptrCast(info[0].pbChecksum.?);
    try testing.expectEqual(@as(u8, 0x0a), digest[0]);
    try testing.expectEqual(@as(u8, 0x1b), digest[1]);
    try testing.expectEqual(@as(u8, 0x2c), digest[2]);
    try testing.expectEqual(
        @as(u32, 73),
        info[0].dwSourcePackageHandle,
    );
}

test "omits a header-only digest so it never reaches the download verifier" {
    var packages = [_]result_abi.Package{testPackage(.{
        .repository = "synced-repo",
        .name = "alpha",
        .version = "1",
        .release = "1",
        .arch = "x86_64",
        .checksum_value = "0a1b2c",
        .checksum_is_header_only = true,
    })};
    var actions = [_]result_abi.Action{.{
        .dwPackageRef = 0,
        .dwKind = 1,
        .dwReason = 0,
        .dwPriorOffset = 0,
        .dwPriorCount = 0,
        .dwRequestedJobId = 0,
        .nHasRequestedJobId = 0,
    }};
    const result = result_abi.Result{
        .pPackages = &packages,
        .pdwSelectedPackageRefs = undefined,
        .pActions = &actions,
        .pdwPriorPackageRefs = undefined,
        .pdwPriorHnums = undefined,
        .pProblems = undefined,
        .pdwSkippedJobIds = undefined,
        .dwPackageCount = packages.len,
        .dwSelectedPackageCount = 0,
        .dwActionCount = actions.len,
        .dwPriorPackageRefCount = 0,
        .dwProblemCount = 0,
        .dwSkippedJobCount = 0,
    };

    var solved: [*c]legacy_abi.LegacyResult = null;
    try build(testing.allocator, &result, true, &solved);
    defer freeSolved(solved);

    const info = solved[0].pPkgsToInstall;
    try testing.expect(info[0].pbChecksum == null);
    try testing.expectEqual(@as(c_int, 0), info[0].nChecksumType);
}
