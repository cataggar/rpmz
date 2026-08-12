const std = @import("std");
const sqlite = @import("sqlite");

pub const c = sqlite.c;

pub const Error = error{
    InvalidPath,
    NotFound,
    OutOfMemory,
    PathChanged,
    SqliteOpenFailed,
    SyscallFailed,
    UnsafeFile,
    VfsFailed,
};

pub const Mode = enum(c_int) {
    read_only = 0,
    read_write = 1,
};

pub const OpenOptions = struct {
    mode: Mode,
    create: bool = false,
    pinned_main_fd: ?c_int = null,
    before_sqlite_open: ?*const fn (?*anyopaque) void = null,
    mutation_context: ?*anyopaque = null,
};

const RawConnection = extern struct {
    db: ?*c.sqlite3,
    handle: ?*anyopaque,
};

extern fn tdnf_sqlite_confined_open_at(
    dir_fd: c_int,
    basename: [*]const u8,
    basename_len: usize,
    mode: c_int,
    create: c_int,
    pinned_main_fd: c_int,
    output: *RawConnection,
) callconv(.c) c_int;
extern fn tdnf_sqlite_confined_close(
    connection: *RawConnection,
) callconv(.c) c_int;
extern fn tdnf_sqlite_confined_verify(
    connection: *const RawConnection,
) callconv(.c) c_int;
extern fn tdnf_sqlite_confined_duplicate_main_fd(
    connection: *const RawConnection,
) callconv(.c) c_int;

pub const Connection = struct {
    db: ?*c.sqlite3,
    handle: ?*anyopaque,

    pub fn close(self: *Connection) void {
        _ = self.tryClose();
    }

    pub fn tryClose(self: *Connection) bool {
        var raw = RawConnection{ .db = self.db, .handle = self.handle };
        if (tdnf_sqlite_confined_close(&raw) != c.SQLITE_OK)
            return false;
        self.* = .{ .db = null, .handle = null };
        return true;
    }

    pub fn verify(self: *const Connection) Error!void {
        const raw = RawConnection{ .db = self.db, .handle = self.handle };
        try statusError(tdnf_sqlite_confined_verify(&raw));
    }

    pub fn duplicateMainFd(self: *const Connection) Error!c_int {
        const raw = RawConnection{ .db = self.db, .handle = self.handle };
        const fd = tdnf_sqlite_confined_duplicate_main_fd(&raw);
        if (fd < 0) return error.SyscallFailed;
        return fd;
    }
};

pub fn openAt(
    _: std.mem.Allocator,
    dir_fd: c_int,
    basename: []const u8,
    options: OpenOptions,
) Error!Connection {
    if (options.before_sqlite_open) |callback| {
        callback(options.mutation_context);
    }
    var raw = RawConnection{ .db = null, .handle = null };
    try statusError(tdnf_sqlite_confined_open_at(
        dir_fd,
        basename.ptr,
        basename.len,
        @intFromEnum(options.mode),
        @intFromBool(options.create),
        options.pinned_main_fd orelse -1,
        &raw,
    ));
    return .{ .db = raw.db, .handle = raw.handle };
}

fn statusError(status: c_int) Error!void {
    return switch (status) {
        0 => {},
        1 => error.InvalidPath,
        2 => error.NotFound,
        3 => error.OutOfMemory,
        4 => error.PathChanged,
        5 => error.SqliteOpenFailed,
        6 => error.SyscallFailed,
        7 => error.UnsafeFile,
        8 => error.VfsFailed,
        else => error.VfsFailed,
    };
}
