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
prior rows before mutation. Before any RPM is opened as a package, manifest
packages must one-to-one exact-match the plan-selected source coordinates,
identity, repository, checksum, size, and bundle path. Verified RPM handles
remain pinned through native fixed-order execution. The plan retains the
native low-level sequence: downgrade and obsolete erases keep their recorded
identity and position, including interleaving and shared priors. Upgrade and
reinstall priors must be exactly representable by the native replacement item;
export rejects any order or multi-prior graph it cannot preserve.

Replay and ordinary tdnf transactions use the same install-root-wide lock. The
target key is derived only from the opened root directory identity, so aliases
and different `_dbpath` values under one root contend while distinct roots do
not. The opened root directory itself is locked and pinned, and replay retains
the lock from its initial rpmdb snapshot through final inventory capture.
Ordinary transactions acquire it
for the handle before the installed snapshot and solve, retain it through
preparation, native execution, and history completion, and reuse it for key
imports instead of nesting locks. Standalone history and mark mutations use
the same root lock.

RPM identity comparisons use the effective epoch (`epoch orelse 0`). Canonical
plans still preserve the metadata distinction between an omitted epoch and an
explicit zero, while replay accepts an RPM or rpmdb header that omits
`RPMTAG_EPOCH` when plan metadata records epoch zero. Success requires exact
semantic equality with the plan's selected set.

Callers should additionally enforce OS-level network isolation as defense in
depth. The replay API itself accepts no repository or network input.
