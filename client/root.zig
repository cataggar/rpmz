pub const updateinfo = @import("client_updateinfo");
pub const goal = @import("goal.zig");
pub const resolve = @import("resolve.zig");
pub const resolve_service = @import("resolve_service.zig");
pub const api = @import("api.zig");

comptime {
    _ = api;
    _ = resolve_service;
    _ = @import("repoutils.zig");
    _ = @import("remoterepo.zig");
    _ = @import("utils.zig");
    _ = @import("repomd_client_exports").query_native;
    _ = @import("repomd_client_exports").repo_cache;
    _ = @import("transaction_plan_capture");
    _ = @import("transaction_plan_integration");
    _ = @import("client_init");
    _ = @import("builtin_plugins");
    _ = @import("client_plugins");
    _ = @import("client_history");
    _ = @import("config.zig");
    _ = @import("excludes.zig");
    _ = @import("gpgcheck.zig");
    _ = @import("package_query.zig");
    _ = @import("repositories.zig");
    _ = goal;
    _ = resolve;
    _ = @import("transaction.zig");
    _ = updateinfo;
    _ = @import("client_varsdir");
}
