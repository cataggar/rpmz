# Offline replay Zig API

`@import("tdnf").replay` is the supported API for applying one exact
`tdnf.transaction-bundle/v2` transaction without resolving dependencies or
entering a repository, cache, URL, download, or other network-capable path.

```zig
const tdnf = @import("tdnf");

const result = try tdnf.replay.run(allocator, io, .{
    .bundle_directory = "/inputs/transaction-bundle",
    .target = .{
        .install_root = "/image-root",
        .rpmdb_path = "/var/lib/rpm",
        .architecture = "x86_64",
    },
});
defer result.deinit();
```

`rpmdb_path` is the absolute install-root-relative `_dbpath` supported by the
native RPM configuration. The caller must provide all three target values;
replay does not infer architecture or RPM state from the host.

The returned `tdnf.replay.Result` uses schema `tdnf.replay-result/v1` and has
canonical JSON serialization through `canonicalJsonAlloc`. Its status is one
of `validation_failed`, `transaction_failed`, or `succeeded`. Only a successful
result carries `applied_plan_digest`. Transaction failures retain truthful
action states in the plan's authoritative execution order and do not claim
rollback. Final inventory is sorted by package identity and then rpmdb header
number.

Replay validates the v2 bundle closure, plan binding, metadata and RPM bytes,
RPM headers, bundled-key signatures, architecture, exact rpmdb snapshot and
prior rows before mutation. Verified RPM handles remain pinned through native
fixed-order execution. Downgrade, upgrade, reinstall, and obsolete actions are
submitted as one semantic item carrying every recorded prior; unsupported
split orders or projected final inventories are rejected before mutation.

Replay and ordinary tdnf transactions use the same per-target lock. The target
key is derived from the opened install-root directory identity plus normalized
`_dbpath`, so `/root`, `/root/.`, and symlink aliases contend while distinct
targets do not. The resolved root is pinned for the transaction, lock files are
opened without following links, and replay retains the lock from its initial
rpmdb snapshot through execution and final inventory capture.

RPM identity comparisons use the effective epoch (`epoch orelse 0`). Canonical
plans still preserve the metadata distinction between an omitted epoch and an
explicit zero, while replay accepts an RPM or rpmdb header that omits
`RPMTAG_EPOCH` when plan metadata records epoch zero. Success requires exact
semantic equality with the plan's selected set.

Callers should additionally enforce OS-level network isolation as defense in
depth. The replay API itself accepts no repository or network input.
