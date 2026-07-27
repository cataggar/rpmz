//! Pure dependency composition root for transaction-plan repository capture.
//! It deliberately does not import repomd/root.zig, whose C ABI exports are
//! unrelated to this private enrichment path.

pub const available_repository_loader = @import("available_loader.zig");
pub const metadata_model = @import("model.zig");
pub const solver_identity = @import("solver_identity.zig");
