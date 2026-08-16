//! Public Zig API for rpmz.
//!
//! Import this module through `dependency.module("rpmz")`. Files under the
//! implementation component directories are private and may change without
//! notice.

/// Versioned canonical transaction plans. v1 is resolve-only; replay-capable
/// bundle exports use v2 with native execution steps.
pub const transaction_plan = @import("transaction_plan");

/// Versioned, canonical manifest for a reproducible transaction input closure.
/// See `doc/transaction-bundle.md`.
pub const transaction_bundle = @import("transaction_bundle");

/// The supported resolver: explicit inputs in, one owned canonical plan out.
/// See `doc/transaction-plan-api.md`.
pub const resolver = @import("client_root").resolver;

/// Export a reproducible repository and RPM bundle for a resolved
/// transaction. See `doc/transaction-bundle.md`.
pub const bundle_export = @import("client_root").bundle_export;

/// Open and validate a published bundle as a closed input set.
pub const bundle_reader = @import("bundle_reader");

/// Offline, preflighted execution of an exact replay-capable bundle.
/// See `doc/replay-api.md`.
pub const replay = @import("client_root").replay;

test {
    @import("std").testing.refAllDecls(@This());
}
