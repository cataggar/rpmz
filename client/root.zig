comptime {
    _ = @import("repomd_client_exports").query_native;
    _ = @import("transaction_plan_capture");
    _ = @import("transaction_plan_integration");
    _ = @import("transaction_plan_libsolv");
}
