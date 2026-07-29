//! Entry point for the Zig integration test binary.
//!
//! Every test module is pulled in here so one `zig build ztest` runs the whole
//! suite. Tests are isolated by install root rather than by ordering, so
//! nothing here needs to impose a sequence.

comptime {
    _ = @import("harness.zig");
    _ = @import("autoremove_test.zig");
    _ = @import("downgrade_test.zig");
    _ = @import("erase_test.zig");
    _ = @import("install_test.zig");
    _ = @import("multiinstall_test.zig");
}
