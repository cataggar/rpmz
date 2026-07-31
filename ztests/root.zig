//! Entry point for the Zig integration test binary.
//!
//! Every test module is pulled in here so one `zig build ztest` runs the whole
//! suite. Tests are isolated by install root rather than by ordering, so
//! nothing here needs to impose a sequence.

comptime {
    _ = @import("harness.zig");
    _ = @import("assumeno_test.zig");
    _ = @import("autoremove_test.zig");
    _ = @import("checklocal_test.zig");
    _ = @import("clean_test.zig");
    _ = @import("conflict_test.zig");
    _ = @import("count_test.zig");
    _ = @import("debugsolver_test.zig");
    _ = @import("downgrade_test.zig");
    _ = @import("erase_test.zig");
    _ = @import("excludes_test.zig");
    _ = @import("glob_test.zig");
    _ = @import("install_test.zig");
    _ = @import("list_test.zig");
    _ = @import("mark_test.zig");
    _ = @import("multiinstall_test.zig");
    _ = @import("plan_test.zig");
    _ = @import("provides_test.zig");
    _ = @import("protected_test.zig");
    _ = @import("repolist_test.zig");
    _ = @import("search_test.zig");
    _ = @import("solverdiag_test.zig");
    _ = @import("update_test.zig");
    _ = @import("urls_test.zig");
    _ = @import("whatprovides_test.zig");
}
