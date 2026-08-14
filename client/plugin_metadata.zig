const std = @import("std");

pub const PinnedDirectory = extern struct {
    fd: c_int = -1,
};

pub const PinnedFile = extern struct {
    fd: c_int = -1,
    directory_fd: c_int = -1,
    name: ?[*:0]const u8 = null,

    pub fn close(self: *PinnedFile) void {
        if (self.fd >= 0) _ = std.c.close(self.fd);
        self.fd = -1;
    }
};
