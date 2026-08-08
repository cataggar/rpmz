comptime {
    _ = @import("repomd_client_exports").query_native;
    _ = @import("repomd_client_exports").repo_cache;
    _ = @import("transaction_plan_capture");
    _ = @import("transaction_plan_integration");
    _ = @import("builtin_plugins");
    _ = @import("client_history");
    _ = @import("excludes.zig");
    _ = @import("varsdir.zig");
}
