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
native RPM configuration. Replay treats its bytes literally; RPM macro and
environment expressions such as `%{getenv:HOME}` are not expanded. The caller
must provide all three target values; replay does not infer architecture or
RPM state from the host.
`bundle_directory`, `install_root`, and `rpmdb_path` must already be exact,
lexically canonical absolute paths. Replay rejects embedded NUL, surrounding
whitespace, trailing separators, repeated separators, and `.` or `..`
components rather than normalizing them before filesystem or C-ABI use.

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

If the pinned target has no rpmdb main file, that absence is authoritative.
Replay completes fallible pure preparation, revalidates the absence, then
creates the new main file exclusively through the confined SQLite lease. The
lease retains the main, WAL, and SHM present-or-absent identities through
initialization, execution, and final inventory capture; a sidecar cannot be
introduced first and later adopted. If another database or sidecar appeared
before the mutation boundary, replay fails with `rpmdb_mismatch` without
opening it as a database. Once replay creates any target inode, every later
failure is a `transaction_failed` result and reports either the freshly
captured final inventory or `final_inventory_unreadable`. A zero-action replay
also revalidates authoritative absence instead of reusing its initial empty
snapshot.

Replay and ordinary tdnf transactions use the same install-root-wide lock. The
target key is derived only from the opened root directory identity, so aliases
and different `_dbpath` values under one root contend while distinct roots do
not. The publicly reachable root directory is never the lock object. A
validated, owner-only runtime lock file keyed by the pinned root's device and
inode provides serialization, while the root descriptor provides filesystem
identity. Replay retains both from its initial rpmdb snapshot through final
inventory capture. Ordinary transactions acquire them before target
configuration or rpmdb release-version reads. Configuration, os-release,
repository, variable, plugin, cache, and metadata files are then opened
descriptor-relatively with no-follow confinement. They finalize literal
`_dbpath`, pin the rpmdb, and retain the lock through the installed snapshot,
solve, preparation, native execution, and history completion. Key imports
reuse it instead of nesting locks. Standalone history and mark mutations use
the same root lock.

RPM identity comparisons use the effective epoch (`epoch orelse 0`). Canonical
plans still preserve the metadata distinction between an omitted epoch and an
explicit zero, while replay accepts an RPM or rpmdb header that omits
`RPMTAG_EPOCH` when plan metadata records epoch zero. When the plan captured
the installed set, success requires exact semantic equality with its selected
set. For `include_installed=false`, replay instead projects the expected final
inventory from the locked initial snapshot plus the plan's exact actions, so
unmentioned installed packages are retained.

Callers should additionally enforce OS-level network isolation as defense in
depth. The replay API itself accepts no repository or network input.
