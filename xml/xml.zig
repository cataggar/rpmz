//! Shared XML parsing helpers for metalink and future repo metadata parsers.

pub const sax = @import("sax.zig");
pub const uri = @import("uri.zig");

comptime {
    _ = @import("sax.zig");
    _ = @import("uri.zig");
}
