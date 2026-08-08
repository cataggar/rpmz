// Copyright (C) 2024 Broadcom, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.
//
// dnf-compatible `$var` expansion for repository URLs. Variables are files
// under the configured varsdirs, named for the variable and containing its
// value on the first line.
//
// The buffer sizes here look arbitrary because they are: they reproduce the
// fixed-size stack buffers of the C this replaces, so a configuration that
// worked (or failed) before behaves the same way now. See MAX_* below.

const std = @import("std");
const abi = @import("client_abi");

pub const CnfNode = abi.CnfNode;

extern fn create_cnfnode(name: ?[*:0]const u8) ?*CnfNode;
extern fn cnfnode_getval(cn: ?*const CnfNode) ?[*:0]const u8;
extern fn cnfnode_setval(cn: ?*CnfNode, value: ?[*:0]const u8) void;
extern fn append_node(cn_parent: ?*CnfNode, cn: ?*CnfNode) void;
extern fn destroy_cnftree(cn_root: ?*CnfNode) void;
extern fn find_node(cn_list: ?*CnfNode, name: ?[*:0]const u8) ?*CnfNode;

/// libc bindings are declared here rather than taken from std.c because
/// std.c.dirent resolves to a translated header struct in this module and
/// loses its field names. These layouts are the Linux/glibc and musl
/// definitions tdnf targets.
const DIR = opaque {};

const Dirent = extern struct {
    ino: u64,
    off: i64,
    reclen: c_ushort,
    type: u8,
    name: [NAME_BUF_LEN]u8,
};

const NAME_BUF_LEN = 256;
const O_RDONLY = 0;

extern fn opendir(path: [*:0]const u8) ?*DIR;
extern fn readdir(dir: *DIR) ?*Dirent;
extern fn closedir(dir: *DIR) c_int;
extern fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern fn close(fd: c_int) c_int;
extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

/// Longest `<dir>/<name>` accepted, matching the C's `char path[258]` and
/// its `snprintf` truncation check. Longer paths fail with ENAMETOOLONG.
const MAX_PATH_LEN = 257;

/// Longest variable value read, matching the C's `fgets` into `char
/// buf[256]`. Longer first lines are truncated, not rejected.
const MAX_VALUE_LEN = 255;

/// Longest expansion result and longest `$name`, matching the C's
/// `char dest[256]` and `char name[256]`. Output past this is dropped.
const MAX_EXPANSION_LEN = 255;
const MAX_NAME_LEN = 255;

fn setErrno(value: c_int) void {
    std.c._errno().* = value;
}

/// dnf restricts variable file names to lowercase alphanumerics and
/// underscores, so anything else in the directory -- including `.`, `..`
/// and editor backups -- is skipped rather than treated as a variable.
/// https://dnf.readthedocs.io/en/latest/conf_ref.html#varfiles-label
///
/// The C used isdigit()/islower(); tdnf never calls setlocale(), so those
/// are plain ASCII and this is equivalent.
fn isVariableName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |ch| {
        const ok = ch == '_' or
            (ch >= '0' and ch <= '9') or
            (ch >= 'a' and ch <= 'z');
        if (!ok) return false;
    }
    return true;
}

fn trailingSpaceTrimmed(value: []const u8) []const u8 {
    var end = value.len;
    while (end > 0 and std.ascii.isWhitespace(value[end - 1])) : (end -= 1) {}
    return value[0..end];
}

/// Read a variable's value: the first line, minus trailing whitespace.
///
/// An empty file yields an empty value. The C left its `buf` uninitialized
/// when fgets() hit EOF, so an empty variable file took whichever value the
/// previously-read file had left on the stack.
fn readVariableValue(path: [*:0]const u8, out: []u8) ?usize {
    const fd = open(path, O_RDONLY);
    if (fd < 0) return null;
    defer _ = close(fd);

    var used: usize = 0;
    while (used < out.len) {
        const rc = read(fd, out.ptr + used, out.len - used);
        if (rc < 0) return null;
        if (rc == 0) break;
        used += @intCast(rc);
        if (std.mem.indexOfScalar(u8, out[0..used], '\n') != null) break;
    }

    const line_end = std.mem.indexOfScalar(u8, out[0..used], '\n') orelse used;
    return trailingSpaceTrimmed(out[0..line_end]).len;
}

fn collectDirectory(root: *CnfNode, dir_path: [*:0]const u8) bool {
    const dir = opendir(dir_path) orelse {
        // A varsdir that does not exist is not a configuration error;
        // tdnf ships defaults that are frequently absent.
        return std.c._errno().* == @intFromEnum(std.c.E.NOENT);
    };
    defer _ = closedir(dir);

    const dir_len = std.mem.len(dir_path);
    while (readdir(dir)) |entry| {
        const name = std.mem.sliceTo(&entry.name, 0);
        if (!isVariableName(name)) continue;

        if (dir_len + 1 + name.len > MAX_PATH_LEN) {
            setErrno(@intFromEnum(std.c.E.NAMETOOLONG));
            return false;
        }

        var path_buf: [MAX_PATH_LEN + 1]u8 = undefined;
        @memcpy(path_buf[0..dir_len], dir_path[0..dir_len]);
        path_buf[dir_len] = '/';
        @memcpy(path_buf[dir_len + 1 ..][0..name.len], name);
        path_buf[dir_len + 1 + name.len] = 0;
        const path: [*:0]const u8 = @ptrCast(&path_buf);

        var value_buf: [MAX_VALUE_LEN + 1]u8 = undefined;
        const value_len = readVariableValue(path, value_buf[0..MAX_VALUE_LEN]) orelse
            return false;
        value_buf[value_len] = 0;

        const node = create_cnfnode(@ptrCast(&entry.name)) orelse {
            setErrno(@intFromEnum(std.c.E.NOMEM));
            return false;
        };
        cnfnode_setval(node, @ptrCast(&value_buf));
        append_node(root, node);
    }
    return true;
}

/// Build a variable tree from every file in `dirs`, a NULL-terminated array
/// of directory paths. Returns NULL with errno set on failure.
pub export fn parse_varsdirs(dirs: ?[*:null]const ?[*:0]const u8) ?*CnfNode {
    const root = create_cnfnode("(root)") orelse {
        setErrno(@intFromEnum(std.c.E.NOMEM));
        return null;
    };

    if (dirs) |list| {
        var i: usize = 0;
        while (list[i]) |dir_path| : (i += 1) {
            if (!collectDirectory(root, dir_path)) {
                destroy_cnftree(root);
                return null;
            }
        }
    }
    return root;
}

/// Expand `$name` references in `source` against `cn_vars`.
///
/// An unknown variable expands to nothing, and a `$` not followed by a
/// valid name is dropped while the text after it is copied through. Both
/// match the C, and dnf, which treat expansion as best-effort.
///
/// Returns a malloc'd string the caller frees with TDNFFreeMemory.
pub export fn replace_vars(cn_vars: ?*CnfNode, source: ?[*:0]const u8) ?[*:0]u8 {
    const vars = cn_vars orelse return null;
    const text = source orelse return null;

    var dest: [MAX_EXPANSION_LEN]u8 = undefined;
    var used: usize = 0;
    var i: usize = 0;

    while (text[i] != 0 and used < dest.len) {
        while (text[i] != 0 and text[i] != '$' and used < dest.len) {
            dest[used] = text[i];
            used += 1;
            i += 1;
        }
        if (text[i] == 0) break;
        i += 1;

        var name: [MAX_NAME_LEN + 1]u8 = undefined;
        var name_len: usize = 0;
        while (text[i] != 0 and name_len < MAX_NAME_LEN and
            ((text[i] >= '0' and text[i] <= '9') or
                (text[i] >= 'a' and text[i] <= 'z')))
        {
            name[name_len] = text[i];
            name_len += 1;
            i += 1;
        }
        name[name_len] = 0;

        const found = find_node(vars.first_child, @ptrCast(&name)) orelse continue;
        const value = cnfnode_getval(found) orelse continue;
        var v: usize = 0;
        while (value[v] != 0 and used < dest.len) : (v += 1) {
            dest[used] = value[v];
            used += 1;
        }
    }

    const out: [*]u8 = @ptrCast(malloc(used + 1) orelse return null);
    @memcpy(out[0..used], dest[0..used]);
    out[used] = 0;
    return @ptrCast(out);
}

// ---------------------------------------------------------------------------
// Tests
//
// These pin the edge cases the C's fixed-size buffers and error paths made
// easy to get wrong: truncation limits, whitespace stripping, rejected file
// names, missing directories, and the three bugs listed above.
// ---------------------------------------------------------------------------

const testing = std.testing;

const O_WRONLY = 1;
const O_CREAT = 0o100;
const O_TRUNC = 0o1000;

extern fn mkdtemp(template: [*:0]u8) ?[*:0]u8;
extern fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
extern fn unlink(path: [*:0]const u8) c_int;
extern fn rmdir(path: [*:0]const u8) c_int;

/// A throwaway varsdir built with libc so the tests exercise the same
/// syscalls the implementation uses, and so a test can create a file name
/// long enough to trip the path limit.
const VarsDir = struct {
    path: [MAX_PATH_LEN + 1]u8 = undefined,
    path_len: usize = 0,
    files: std.ArrayList([:0]u8) = .empty,

    const template = "/tmp/tdnf-varsdir-XXXXXX";

    fn init() !VarsDir {
        var self = VarsDir{};
        @memcpy(self.path[0..template.len], template);
        self.path[template.len] = 0;
        if (mkdtemp(@ptrCast(&self.path)) == null) return error.MkdtempFailed;
        self.path_len = template.len;
        return self;
    }

    fn deinit(self: *VarsDir) void {
        for (self.files.items) |p| {
            _ = unlink(p.ptr);
            testing.allocator.free(p);
        }
        self.files.deinit(testing.allocator);
        _ = rmdir(self.cstr());
    }

    fn addFile(self: *VarsDir, name: []const u8, contents: []const u8) !void {
        const full = try std.fmt.allocPrintSentinel(
            testing.allocator,
            "{s}/{s}",
            .{ self.path[0..self.path_len], name },
            0,
        );
        errdefer testing.allocator.free(full);
        try self.files.append(testing.allocator, full);

        const fd = open(full.ptr, O_WRONLY | O_CREAT | O_TRUNC, @as(c_int, 0o600));
        if (fd < 0) return error.OpenFailed;
        defer _ = close(fd);
        var written: usize = 0;
        while (written < contents.len) {
            const rc = write(fd, contents.ptr + written, contents.len - written);
            if (rc <= 0) return error.WriteFailed;
            written += @intCast(rc);
        }
    }

    fn cstr(self: *VarsDir) [*:0]const u8 {
        return @ptrCast(&self.path);
    }

    fn parse(self: *VarsDir) ?*CnfNode {
        var dirs = [_:null]?[*:0]const u8{self.cstr()};
        return parse_varsdirs(&dirs);
    }
};

fn expectExpansion(root: *CnfNode, source: [*:0]const u8, want: []const u8) !void {
    const got = replace_vars(root, source) orelse return error.NullResult;
    defer free(got);
    try testing.expectEqualStrings(want, std.mem.sliceTo(got, 0));
}

test "values are the first line with trailing whitespace stripped" {
    var vars = try VarsDir.init();
    defer vars.deinit();
    try vars.addFile("host", "example.com\n");
    try vars.addFile("multiline", "first\nsecond\n");
    try vars.addFile("spaced", "  spaced  \n");
    try vars.addFile("noeol", "noeol");
    try vars.addFile("onlyspace", " \t\n");

    const root = vars.parse() orelse return error.ParseFailed;
    defer destroy_cnftree(root);

    try expectExpansion(root, "$host", "example.com");
    try expectExpansion(root, "$multiline", "first");
    // Leading whitespace is deliberately kept; only the tail is stripped.
    try expectExpansion(root, "$spaced|", "  spaced|");
    try expectExpansion(root, "$noeol", "noeol");
    try expectExpansion(root, "$onlyspace|", "|");
}

test "an empty variable file yields an empty value" {
    // The C read an uninitialized stack buffer here, so an empty file
    // silently took the value of whichever file was read before it.
    var vars = try VarsDir.init();
    defer vars.deinit();
    try vars.addFile("host", "example.com\n");
    try vars.addFile("empty", "");

    const root = vars.parse() orelse return error.ParseFailed;
    defer destroy_cnftree(root);

    try expectExpansion(root, "$empty|", "|");
}

test "an empty variable file does not inherit a missing directory's errno" {
    // The C checked errno after fgets() returned NULL at EOF, but nothing
    // had cleared it, so a preceding non-existent varsdir aborted the whole
    // parse with ENOENT.
    var vars = try VarsDir.init();
    defer vars.deinit();
    try vars.addFile("host", "example.com\n");
    try vars.addFile("empty", "");

    var dirs = [_:null]?[*:0]const u8{ "/nonexistent-varsdir", vars.cstr() };
    const root = parse_varsdirs(&dirs) orelse return error.ParseFailed;
    defer destroy_cnftree(root);

    try expectExpansion(root, "$host", "example.com");
}

test "file names outside dnf's allowed set are ignored" {
    var vars = try VarsDir.init();
    defer vars.deinit();
    try vars.addFile("ok1", "yes\n");
    try vars.addFile("UPPER", "no\n");
    try vars.addFile("with-dash", "no\n");
    try vars.addFile("dot.file", "no\n");

    const root = vars.parse() orelse return error.ParseFailed;
    defer destroy_cnftree(root);

    try expectExpansion(root, "$ok1", "yes");
    // `$UPPER` matches no variable, so the `$` is dropped and the rest of
    // the text passes through unchanged.
    try expectExpansion(root, "$UPPER", "UPPER");
    try expectExpansion(root, "$with-dash", "-dash");
    try expectExpansion(root, "$dot.file", ".file");
}

test "a $ reference cannot name a variable containing an underscore" {
    // dnf allows underscores in variable file names, but a `$name`
    // reference stops at the first character outside [0-9a-z], so such a
    // variable can be defined and never used. Preserved from the C, which
    // tested the name with isdigit()/islower() only.
    var vars = try VarsDir.init();
    defer vars.deinit();
    try vars.addFile("with_under", "value\n");

    const root = vars.parse() orelse return error.ParseFailed;
    defer destroy_cnftree(root);

    try expectExpansion(root, "$with_under", "_under");
}

test "unknown variables and bare dollars expand to nothing" {
    var vars = try VarsDir.init();
    defer vars.deinit();
    try vars.addFile("host", "h\n");

    const root = vars.parse() orelse return error.ParseFailed;
    defer destroy_cnftree(root);

    try expectExpansion(root, "plain text", "plain text");
    try expectExpansion(root, "$nosuch/tail", "/tail");
    try expectExpansion(root, "trailing$", "trailing");
    try expectExpansion(root, "$", "");
    try expectExpansion(root, "$$host", "h");
    try expectExpansion(root, "http://$host/x", "http://h/x");
}

test "values and expansions truncate at the historical buffer limits" {
    var vars = try VarsDir.init();
    defer vars.deinit();
    try vars.addFile("long", "L" ** 400);

    const root = vars.parse() orelse return error.ParseFailed;
    defer destroy_cnftree(root);

    try expectExpansion(root, "$long", "L" ** MAX_VALUE_LEN);
    // The trailing marker is dropped: the result is capped too.
    try expectExpansion(root, "$long|", "L" ** MAX_EXPANSION_LEN);
}

test "missing varsdirs are skipped but unusable ones fail" {
    var missing = [_:null]?[*:0]const u8{"/nonexistent-varsdir"};
    const root = parse_varsdirs(&missing) orelse return error.ParseFailed;
    destroy_cnftree(root);

    var not_a_dir = [_:null]?[*:0]const u8{"/proc/self/cmdline"};
    try testing.expect(parse_varsdirs(&not_a_dir) == null);
    try testing.expectEqual(std.c.E.NOTDIR, @as(std.c.E, @enumFromInt(std.c._errno().*)));
}

test "an over-long variable path fails with ENAMETOOLONG" {
    // The C reported this correctly but then fclose()d an already-closed
    // FILE* on the way out, aborting the process.
    var vars = try VarsDir.init();
    defer vars.deinit();
    try vars.addFile("short", "s\n");

    const name_len = MAX_PATH_LEN - vars.path_len;
    var name: [MAX_PATH_LEN]u8 = undefined;
    @memset(name[0..name_len], 'n');
    try vars.addFile(name[0..name_len], "too long\n");

    try testing.expect(vars.parse() == null);
    try testing.expectEqual(
        std.c.E.NAMETOOLONG,
        @as(std.c.E, @enumFromInt(std.c._errno().*)),
    );
}

test "an empty varsdir list yields an empty tree" {
    var dirs = [_:null]?[*:0]const u8{};
    const root = parse_varsdirs(&dirs) orelse return error.ParseFailed;
    defer destroy_cnftree(root);
    try testing.expect(root.first_child == null);
    try expectExpansion(root, "$host|", "|");
}
