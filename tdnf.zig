//! Public Zig API for tdnf.
//!
//! Import this module through `dependency.module("tdnf")`. Files under the
//! implementation component directories are private and may change without
//! notice.

/// Versioned, canonical resolve-only transaction plans.
pub const transaction_plan = @import("transaction_plan");

/// The supported resolver: explicit inputs in, one owned canonical plan out.
/// See `doc/transaction-plan-api.md`.
pub const resolver = @import("client_root").resolver;

test {
    @import("std").testing.refAllDecls(@This());
}
