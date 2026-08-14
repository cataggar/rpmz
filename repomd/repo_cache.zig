const std = @import("std");
const builtin = @import("builtin");
const error_codes = @import("tdnf_error");

const Io = std.Io;
const Sha256 = std.crypto.hash.sha2.Sha256;

const cookie_ident = "tdnf-solv-content-v3";
const cookie_len = Sha256.digest_length;
const hex_chars = "0123456789abcdef";

const tdnf_alloc = if (builtin.is_test) struct {} else struct {
    extern fn TDNFAllocateMemory(
        nNumElements: usize,
        nSize: usize,
        ppMemory: ?*?*anyopaque,
    ) u32;
};

pub export fn TDNFRepoMdCalculateCookieForFile(
    pszFilePath: ?[*:0]const u8,
    pszCookie: ?[*]u8,
) u32 {
    if (pszFilePath == null) {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }
    if (pszCookie == null) {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }

    var digest: [cookie_len]u8 = undefined;
    const dwError = calculateCookieForPath(std.mem.span(pszFilePath.?), &digest);
    if (dwError != 0) {
        return dwError;
    }

    @memcpy(pszCookie.?[0..cookie_len], digest[0..]);
    return 0;
}

pub export fn TDNFRepoMdCalculateCookieForFd(
    fd: c_int,
    cookie: ?[*]u8,
) u32 {
    const output = cookie orelse
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    if (fd < 0 or std.c.lseek(fd, 0, 0) < 0)
        return error_codes.ERROR_TDNF_SOLV_IO;
    var hasher = Sha256.init(.{});
    hasher.update(cookie_ident);
    var buffer: [4096]u8 = undefined;
    while (true) {
        const got = std.c.read(fd, &buffer, buffer.len);
        if (got < 0 and
            std.c._errno().* == @intFromEnum(std.posix.E.INTR))
        {
            continue;
        }
        if (got < 0) return error_codes.ERROR_TDNF_SOLV_IO;
        if (got == 0) break;
        hasher.update(buffer[0..@intCast(got)]);
    }
    var digest: [cookie_len]u8 = undefined;
    hasher.final(&digest);
    @memcpy(output[0..cookie_len], &digest);
    return 0;
}

pub export fn TDNFRepoMdCreateRepoCacheName(
    pszName: ?[*:0]const u8,
    pszUrl: ?[*:0]const u8,
    ppszCacheName: ?*?[*:0]u8,
) u32 {
    if (ppszCacheName) |out| {
        out.* = null;
    }
    if (pszName == null or pszUrl == null or ppszCacheName == null) {
        return error_codes.ERROR_TDNF_INVALID_PARAMETER;
    }

    const name = std.mem.span(pszName.?);
    const url = std.mem.span(pszUrl.?);
    const cache_name_len = std.math.add(usize, name.len, 9) catch
        return error_codes.ERROR_TDNF_OUT_OF_MEMORY;

    var pszCacheName: ?[*:0]u8 = null;
    const dwError = allocateCStringCapacity(cache_name_len, &pszCacheName);
    if (dwError != 0) {
        return dwError;
    }

    const out = pszCacheName.?;
    formatRepoCacheName(name, url, out[0..cache_name_len]);
    out[cache_name_len] = 0;
    ppszCacheName.?.* = out;
    return 0;
}

fn calculateCookieForPath(path: []const u8, digest: *[cookie_len]u8) u32 {
    var io_state: Io.Threaded = .init(std.heap.c_allocator, .{});
    defer io_state.deinit();
    const io = io_state.io();

    const file = openInputFile(io, path) catch return error_codes.ERROR_TDNF_SOLV_IO;
    defer file.close(io);

    var hasher = Sha256.init(.{});
    hasher.update(cookie_ident);

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &reader_buf);
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = reader.interface.readSliceShort(&buf) catch
            return error_codes.ERROR_TDNF_SOLV_IO;
        if (n == 0) {
            break;
        }
        hasher.update(buf[0..n]);
    }

    hasher.final(digest);
    return 0;
}

fn openInputFile(io: Io, path: []const u8) !Io.File {
    if (std.fs.path.isAbsolute(path)) {
        return Io.Dir.openFileAbsolute(io, path, .{});
    }
    return Io.Dir.cwd().openFile(io, path, .{});
}

fn allocateCStringCapacity(len: usize, ppszOut: *?[*:0]u8) u32 {
    if (builtin.is_test) {
        const out = std.heap.c_allocator.allocSentinel(u8, len, 0) catch {
            ppszOut.* = null;
            return error_codes.ERROR_TDNF_OUT_OF_MEMORY;
        };
        ppszOut.* = out.ptr;
        return 0;
    }

    var raw: ?*anyopaque = null;
    const dwError = tdnf_alloc.TDNFAllocateMemory(len + 1, 1, &raw);
    if (dwError != 0) {
        ppszOut.* = null;
        return dwError;
    }
    ppszOut.* = @ptrCast(@alignCast(raw.?));
    return 0;
}

fn formatRepoCacheName(name: []const u8, url: []const u8, out: []u8) void {
    var digest: [cookie_len]u8 = undefined;
    Sha256.hash(url, &digest, .{});

    @memcpy(out[0..name.len], name);
    out[name.len] = '-';
    digestPrefixHex(digest[0..4], out[name.len + 1 .. name.len + 9]);
}

fn digestPrefixHex(bytes: []const u8, out: []u8) void {
    for (bytes, 0..) |byte, index| {
        out[index * 2] = hex_chars[byte >> 4];
        out[index * 2 + 1] = hex_chars[byte & 0x0f];
    }
}

fn freeTestCString(value: ?[*:0]u8) void {
    if (value) |ptr| {
        std.heap.c_allocator.free(std.mem.span(ptr));
    }
}

test "repo cache names match legacy SHA256 prefix format" {
    const cases = [_]struct {
        name: [:0]const u8,
        url: [:0]const u8,
        expected: []const u8,
    }{
        .{
            .name = "empty",
            .url = "",
            .expected = "empty-e3b0c442",
        },
        .{
            .name = "base",
            .url = "http://localhost:8080/photon-test",
            .expected = "base-6e087daf",
        },
        .{
            .name = "query",
            .url = "https://example.invalid/repo/path/repodata/repomd.xml?releasever=1.0&arch=x86_64",
            .expected = "query-85f57e0c",
        },
        .{
            .name = "repo-with-dash",
            .url = "https://mirror.example.com/a/very/long/segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-segment-repodata?x=1/y=2",
            .expected = "repo-with-dash-a0a2bb8b",
        },
    };

    for (cases) |case| {
        var cache_name: ?[*:0]u8 = null;
        try std.testing.expectEqual(
            @as(u32, 0),
            TDNFRepoMdCreateRepoCacheName(
                case.name.ptr,
                case.url.ptr,
                &cache_name,
            ),
        );
        defer freeTestCString(cache_name);
        try std.testing.expectEqualStrings(
            case.expected,
            std.mem.span(cache_name.?),
        );
    }
}

test "repo cache name rejects null arguments" {
    var cache_name: ?[*:0]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, error_codes.ERROR_TDNF_INVALID_PARAMETER),
        TDNFRepoMdCreateRepoCacheName(null, "", &cache_name),
    );
    try std.testing.expect(cache_name == null);
    try std.testing.expectEqual(
        @as(u32, error_codes.ERROR_TDNF_INVALID_PARAMETER),
        TDNFRepoMdCreateRepoCacheName("repo", null, &cache_name),
    );
    try std.testing.expect(cache_name == null);
    try std.testing.expectEqual(
        @as(u32, error_codes.ERROR_TDNF_INVALID_PARAMETER),
        TDNFRepoMdCreateRepoCacheName("repo", "", null),
    );
}

test "repo cache file cookie includes legacy ident and file bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cases = [_]struct {
        sub_path: []const u8,
        data: []const u8,
        expected: [cookie_len]u8,
    }{
        .{
            .sub_path = "empty",
            .data = "",
            .expected = .{
                0x01, 0xb4, 0x25, 0x93, 0x4d, 0x31, 0xc3, 0x7f,
                0xa4, 0x1d, 0x17, 0xb7, 0x87, 0x31, 0xb8, 0x02,
                0xa4, 0xfa, 0x91, 0xd5, 0xdb, 0x11, 0x9b, 0xca,
                0xe3, 0xde, 0x85, 0x7c, 0x0e, 0x1b, 0x93, 0xd1,
            },
        },
        .{
            .sub_path = "ascii",
            .data = "abc",
            .expected = .{
                0x69, 0x97, 0xc8, 0x01, 0x30, 0x98, 0xb5, 0xc4,
                0x8a, 0x9a, 0xb0, 0x4c, 0x37, 0xd5, 0x8d, 0xe8,
                0x2e, 0xb1, 0x01, 0x6c, 0xb5, 0x33, 0xd1, 0x95,
                0x2b, 0xad, 0xa5, 0xda, 0x13, 0x71, 0x6e, 0x8e,
            },
        },
        .{
            .sub_path = "binary",
            .data = "\x00\x01\x02\x00\xff\x0atdnf",
            .expected = .{
                0x2e, 0xd7, 0xe9, 0x54, 0x06, 0x95, 0xd0, 0x8e,
                0xfd, 0xb1, 0x78, 0xc5, 0x63, 0x67, 0x0f, 0x37,
                0x53, 0xdf, 0x03, 0x77, 0x9e, 0xb4, 0x3d, 0xe8,
                0x9e, 0x26, 0xdc, 0xbd, 0x0c, 0x86, 0xb1, 0x29,
            },
        },
    };

    for (cases) |case| {
        try tmp.dir.writeFile(std.testing.io, .{
            .sub_path = case.sub_path,
            .data = case.data,
        });
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrintZ(
            &path_buf,
            ".zig-cache/tmp/{s}/{s}",
            .{ &tmp.sub_path, case.sub_path },
        );
        var actual: [cookie_len]u8 = undefined;
        try std.testing.expectEqual(
            @as(u32, 0),
            TDNFRepoMdCalculateCookieForFile(path.ptr, actual[0..].ptr),
        );
        try std.testing.expectEqualSlices(u8, case.expected[0..], actual[0..]);
    }
}

test "repo cache file cookie preserves legacy error codes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var actual: [cookie_len]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, error_codes.ERROR_TDNF_INVALID_PARAMETER),
        TDNFRepoMdCalculateCookieForFile(null, actual[0..].ptr),
    );

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const missing_path = try std.fmt.bufPrintZ(
        &path_buf,
        ".zig-cache/tmp/{s}/missing",
        .{&tmp.sub_path},
    );
    try std.testing.expectEqual(
        @as(u32, error_codes.ERROR_TDNF_SOLV_IO),
        TDNFRepoMdCalculateCookieForFile(missing_path.ptr, actual[0..].ptr),
    );
}
