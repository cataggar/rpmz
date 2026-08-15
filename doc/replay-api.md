# Offline transaction replay

Replay applies one previously exported transaction exactly as recorded. It
does not resolve dependencies, select alternatives, refresh metadata, enter a
cache, or request a remote URL. The supported interfaces are the public Zig
namespace `@import("tdnf").replay` and the `tdnf replay` command.

Replay accepts only a `tdnf.transaction-bundle/v2` whose `plan.json` is a
canonical `tdnf.transaction-plan/v2` with a materialized native execution
order. Version 1 bundles and plans remain parseable by their format modules for
compatibility, but replay rejects them as `non_replayable_bundle`.

## Zig API

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

const json = try result.canonicalJsonAlloc(allocator);
defer allocator.free(json);
```

### Input and ownership

`tdnf.replay.Input` has exactly two members:

- `bundle_directory` is the closed bundle directory to validate and execute.
- `target` supplies the explicit `install_root`, `rpmdb_path`, and
  `architecture`.

All input strings are borrowed for the duration of `run`. On every
non-allocation outcome, `run` returns an owned `*tdnf.replay.Result`; the
caller must call `Result.deinit`. `RunError` contains only `OutOfMemory`.
Validation and transaction failures are data, not Zig errors. Bytes returned
by `canonicalJsonAlloc` belong to the allocator passed to that method.

`bundle_directory`, `install_root`, and `rpmdb_path` must already be exact,
lexically canonical absolute paths. Replay rejects embedded NUL, surrounding
whitespace, trailing separators, repeated separators, and `.` or `..`
components rather than normalizing them before filesystem or C-ABI use.

`rpmdb_path` is the absolute, install-root-relative `_dbpath` understood by the
native RPM configuration, normally `/var/lib/rpm`. Its bytes are literal:
RPM macros and environment expressions such as `%{getenv:HOME}` are not
expanded. The caller must supply all target values. Replay never infers an
architecture, install root, `_dbpath`, or installed state from the host.

The target architecture must equal the architecture recorded in the plan
environment, and every selected package architecture must be compatible with
it. The target rpmdb must match the plan's recorded snapshot and every exact
installed prior row, including header number and effective package identity.
An omitted RPM epoch compares as epoch zero while the canonical plan continues
to preserve the distinction between omitted epoch and explicit zero.

### Validation precedes mutation

Replay completes all fallible preflight work before invoking the native
executor:

1. validate the exact input paths;
2. open the bundle as a closed, no-follow directory and require canonical v2
   manifest and plan bytes with matching schema and digests;
3. reject missing, additional, unsafe, substituted, or mis-sized files;
4. one-to-one bind every manifest RPM to its plan-selected package identity,
   repository, source coordinates, checksum, size, and bundle path;
5. verify bundled repository metadata, RPM bytes and headers, bundled-key
   signatures, and architecture compatibility;
6. acquire the install-root-wide transaction lock, pin the explicit rpmdb,
   and verify its exact snapshot and all prior rows;
7. build and validate the fixed-order native transaction while keeping every
   verified RPM handle pinned.

A failure in these stages has status `validation_failed`. Replay does not
create, remove, or modify a target file for such a failure. The only exception
to "all fallible work" is work that inherently belongs to execution or final
inventory capture; failures after the mutation boundary are reported as
`transaction_failed`, never recast as validation failures.

If the pinned target has no rpmdb main file, that absence is authoritative.
Replay prepares the confined SQLite write, revalidates the absence immediately
before mutation, and creates the main file exclusively. The main, WAL, and SHM
present-or-absent identities remain pinned through initialization, execution,
and final inventory capture. If another database or sidecar appears first,
replay returns `rpmdb_mismatch` without adopting it. A zero-action replay also
revalidates authoritative absence.

Replay and ordinary tdnf transactions use the same install-root-wide lock.
Aliases and different `_dbpath` values under one root contend, while distinct
roots do not. Replay retains the pinned root and rpmdb state through final
inventory capture.

### Exact execution order

The plan's semantic `actions` are not used to reconstruct an order. Replay
submits the v2 plan's `execution_steps` to the fixed-order native executor in
their recorded sequence. Install, erase, reinstall, upgrade, downgrade, and
obsolete work therefore retains the exported low-level interleaving. Shared
priors and the recorded identity and position of downgrade or obsolete erases
are preserved.

Bundle export refuses any transaction order or multi-prior replacement graph
that the native fixed-order item model cannot represent. Replay independently
validates the stored shape and refuses a malformed order rather than sorting,
coalescing, re-solving, or choosing another package.

### Canonical result contract

`Result.canonicalJsonAlloc` emits `schema`
`tdnf.replay-result/v1` with members in this fixed order:

```json
{
  "actions": [
    {"index": 0, "kind": "install", "status": "applied"}
  ],
  "applied_plan_digest": "64 lowercase hex characters or null",
  "final_inventory": [
    {
      "hnum": 1,
      "identity": {
        "arch": "x86_64",
        "epoch": 0,
        "name": "example",
        "release": "1",
        "version": "1"
      }
    }
  ],
  "plan_digest": "64 lowercase hex characters or null",
  "schema": "tdnf.replay-result/v1",
  "status": "succeeded",
  "transaction_failure": null,
  "validation_failure": null
}
```

The actual serialization is compact canonical UTF-8 JSON. Array order is
also canonical:

- `actions` orders outcomes by each action's first appearance in
  `execution_steps`. Any action with no execution step follows in action-index
  order. Each outcome aggregates all low-level steps belonging to that action;
  the exact low-level order remains in the v2 plan.
- `final_inventory` is sorted by package identity and then rpmdb header
  number.

#### Status values

The `Status` values are `validation_failed`, `transaction_failed`, and
`succeeded`.

The fields have these invariants:

- `status` is `validation_failed`, `transaction_failed`, or `succeeded`.
- `validation_failure` is non-null only for `validation_failed`.
- `transaction_failure` is non-null only for `transaction_failed`.
- `plan_digest` becomes available after the canonical plan has been read and
  bound; early validation failures may leave it null.
- `applied_plan_digest` equals `plan_digest` only on success and is null for
  every failure.
- `final_inventory` is the best authoritative inventory available. It may be
  null before the target snapshot is captured or when final capture fails.

#### Validation failure values

The public `ValidationFailure` values are:
`invalid_input`, `bundle_unreadable`, `manifest_not_canonical`,
`missing_bundle_file`, `additional_bundle_file`, `unsafe_bundle_entry`,
`checksum_mismatch`, `size_mismatch`, `non_replayable_bundle`,
`plan_mismatch`, `repository_mismatch`, `metadata_mismatch`, `rpm_mismatch`,
`signature_mismatch`, `architecture_mismatch`, `rpmdb_mismatch`,
`prior_mismatch`, `action_shape_mismatch`, `lock_failed`, and
`target_unreadable`.

#### Transaction failure values

The public `TransactionFailure` values are:
`invalid_context`, `invalid_item`, `malformed_order`, `prior_mismatch`,
`package_open_failed`, `package_identity_mismatch`, `rpm_check_failed`,
`transaction_failed`, `execution_failed`, `expected_inventory_mismatch`, and
`final_inventory_unreadable`.

#### Action status values

The public `ActionStatus` values are `not_attempted`, `applied`, and
`indeterminate`.

### Transaction failure semantics

Replay makes no rollback claim. Once mutation can have begun, any executor,
rpmdb initialization, expected-inventory, or final-capture failure is
`transaction_failed`. Actions whose complete recorded low-level work was
observed retain `applied`; every other action becomes `indeterminate`.
`not_attempted` is used only before execution has crossed into an uncertain
transaction outcome.

Replay attempts to capture and return the actual final inventory after a
transaction failure. If that capture fails, `final_inventory` is null and the
failure is `final_inventory_unreadable`. A failed result never carries
`applied_plan_digest` and must never be represented to a caller as a
successful replay.

For a plan that captured the installed set, success requires exact semantic
equality with the plan's selected set. For `include_installed=false`, replay
projects the expected inventory from the locked initial snapshot plus the
exact actions, retaining installed packages the plan did not mention.

## Command-line interface

```text
tdnf replay [--json] --installroot <absolute-path> \
  --rpmdb-path <absolute-path> --forcearch <arch> <bundle-directory>
```

The replay command accepts only the following spellings:

| Purpose | Accepted spellings |
| --- | --- |
| Install root | `--installroot PATH`, `--installroot=PATH`, `-installroot PATH`, `-installroot=PATH`, `-i PATH`, `-iPATH` |
| RPM database path | `--rpmdb-path PATH`, `--rpmdb-path=PATH`, `-rpmdb-path PATH`, `-rpmdb-path=PATH` |
| Architecture | `--forcearch ARCH`, `--forcearch=ARCH`, `-forcearch ARCH`, `-forcearch=ARCH` |
| JSON invocation errors | `-j`, `--j`, `-js`, `--js`, `-jso`, `--jso`, `-json`, `--json`, or the `tdnfj` alias |
| Help | `--help`, `-h` |

The JSON abbreviations are the unique non-empty prefixes accepted by tdnf's
legacy long-option matcher. They do not accept attached values.

The three target options and the one bundle operand are required exactly once.
Replay rejects other legacy tdnf options instead of allowing configuration,
repository, plugin, cache, proxy, or download state to enter the operation.
Options may precede or follow the `replay` word unless `--` ended option
parsing.

Example:

```sh
tdnf replay \
  --installroot /srv/images/root \
  --rpmdb-path /var/lib/rpm \
  --forcearch x86_64 \
  /srv/bundles/update-2026-08
```

For defense in depth, run the same command inside the operating system's
network-isolation mechanism, for example a container or namespace with no
network interface:

```sh
unshare --net -- \
  tdnf replay --installroot /srv/images/root \
  --rpmdb-path /var/lib/rpm --forcearch x86_64 \
  /srv/bundles/update-2026-08
```

Replay itself never requests remote URLs, but callers **should still enforce
OS-level network isolation**. This protects the surrounding process and future
dependencies as well as replay.

### Exit status and output channels

| Status | Meaning |
| ---: | --- |
| `0` | Replay succeeded, or `--help` was requested. |
| `1` | Internal allocation, output-channel, or output-write failure. |
| `2` | Invocation or option error. |
| `3` | Replay returned `validation_failed`. |
| `4` | Replay returned `transaction_failed`. |

A valid invocation writes exactly one canonical
`tdnf.replay-result/v1` document to stdout for success and for both failure
statuses. This is true with or without `--json`; replay is always
machine-readable. During execution, ordinary diagnostics and scriptlet
descendant output are redirected to stderr so they cannot corrupt the single
stdout document.

An invocation error writes diagnostics and usage to stderr. In ordinary mode
stdout is empty. With `--json` or `tdnfj`, stdout additionally contains one
`tdnf.replay-invocation-error/v1` document with stable `error` and
human-readable `message` fields. `--help` writes usage to stderr, leaves
stdout empty, and exits zero.

Callers should select behavior from the exit status and the versioned stdout
document, not by parsing human-readable stderr.

## Network confinement

The replay API exposes no URL, repository configuration, proxy, credential,
cache, mirror, fetch callback, or solver job. Its bundle metadata
decompression and checksum verification operate only on already-opened local
bundle bytes. A static confinement audit pins that dependency boundary and
rejects direct or aliased standard-library networking plus C imports and
socket-related extern declarations; binary-level replay tests own the
behavioral zero-request proof.

This design is deliberately narrower than `--cacheonly`: cache-only mode still
performs an ordinary solve over cached repository state, while replay treats
the canonical v2 plan and closed v2 bundle as the complete authority.
