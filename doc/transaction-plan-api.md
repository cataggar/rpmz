# The transaction-plan API

rpmz can answer the question *"what would this transaction do?"* without doing
any of it. The answer is a **transaction plan**: a versioned, canonically
serialized document that names every package the transaction would touch, why,
and the exact inputs the answer was derived from.

This document describes the supported Zig API for producing one. It is the
contract; the module documentation in `client/resolver.zig` and
`client/transaction_plan.zig` is the reference.

## What a plan is

A plan is a complete, self-describing record of one resolve:

- **`requests`** — what the caller asked for, one entry per subject.
- **`jobs`** — what the resolver turned each request into.
- **`packages`** — every package the plan refers to, available or installed,
  with its identity, repository, and source location.
- **`actions`** — the semantic outcome: install, erase, upgrade,
  downgrade, reinstall, or obsolete, each naming its target and its exact
  prior rows.
- **`execution`** — v1 records `unmaterialized`; v2 records the exact ordered
  low-level install, erase, reinstall, and upgrade items accepted by the native
  transaction engine, each tied back to an `action-N` and `package-N`. This
  order, not the canonical ordering of `actions`, is the execution authority.
- **`problems`** — structured solver contradictions.
- **`skipped`** — jobs dropped by a skip policy.
- **`repositories`** — the metadata snapshot each repository was read at.
- **`environment`** — architecture, distro, release version, policy, rpmdb
  identity, and the resolution status.
- **`digest`** — a SHA-256 over the canonical bytes, under the domain
  the schema named by the document.

Obsoletion is one action, not two: `kind` is `obsolete`, the target is the
obsoleting package, and `prior_package_ids` names the rows it replaces.

## Producing a plan

`resolvePlan` is the only supported way to obtain a plan without the private
handle API. It is reachable from outside the repository: depend on this package
and import `rpmz`, whose `resolver` and `transaction_plan` namespaces are the
entire supported surface. Nothing else under the component directories is
public, and `public-zig-api-audit` fails the build if a public file reaches
outside that surface.

```zig
const rpmz = @import("rpmz");
const resolver = rpmz.resolver;

const plan = try resolver.resolvePlan(allocator, io, .{
    .operation = .install,
    .subjects = &.{"my-package"},
    .repositories = &.{.{
        .id = "base",
        .metadata = .{ .local_snapshot = "/path/to/repo" },
    }},
    .installed = .{ .install_root = "/path/to/root" },
    .environment = .{
        .architecture = "x86_64",
        .distro = "photon",
        .release_version = "5.0",
    },
    .scratch_dir = "/path/to/scratch",
});
defer plan.destroy();

const canonical = try plan.canonicalJsonAlloc(allocator);
defer allocator.free(canonical);
const digest = try plan.digest(allocator);
```

## Explicit inputs only

Every fact a plan depends on is declared by the caller. The resolver reads no
host `.repo` file, no host `rpmz.conf`, no host cache directory, and no host
repository-enablement decision. It materializes a private, single-use
configuration from the input alone.

Values it could plausibly guess are required rather than defaulted:
architecture is never taken from the running kernel, distro and release version
are never read from `os-release`, and policy is never inherited.

This is enforced, not merely intended: a test plants a `.repo` drop-in, a
`rpmz.conf`, and a stale metadata cache for a repository offering a newer
package inside the declared root, and asserts the plan digest does not move.

## Ownership

- Every string and slice reachable from `ResolveInput` is **borrowed** for the
  duration of the call and may be released the moment it returns.
- On success the caller owns the returned `*Plan` and must call
  `Plan.destroy`. The plan is a deep copy; it shares no storage with the
  resolver's scratch state.

## Failure is structured, or it is an error

The two are deliberately different:

- A **solver contradiction is a successful call.** It returns a plan whose
  `environment.resolution_status` is `problems`, with structured entries in
  `problems` and no actions. The plan is the answer.
- **Infrastructure failure is a Zig error** and produces no plan: invalid
  input, repository or rpmdb I/O failure, integrity failure, or allocation
  failure. See `ResolveError`.

There is no third state. A resolve never silently returns a partial or
best-effort plan.

## Identity and reproducibility

The canonical serialization is the plan's identity, and the digest is taken
over exactly those bytes.

- Repeating identical inputs produces byte-identical output.
- Permuting semantically unordered inputs — repository order, and the order
  within policy name lists — does not change the output.
- Changing the request, repository metadata, installed rpmdb state,
  architecture, distro, release version, or policy does change it.

`rpmz tdnf plan <verb>` prints exactly these bytes. The CLI is a thin adapter over
the same entry point, and a test asserts the two agree byte for byte, so a
plan captured from the command line and one produced through the API are the
same document.

## Secrets

Credentials are described as *how the caller reaches a repository*, never as
part of the transaction, so they never enter the plan.

- Credentials embedded in a URL are **rejected** with `error.CredentialsInUrl`
  rather than redacted, because a URL travels into diagnostics and scratch
  configuration.
- Credentials are supplied through an opaque `SecretProvider`. The resolver
  asks for a value, installs it on the private in-memory repository record,
  and forgets it. It is never written to the scratch configuration, never
  appears in a filename, and is not part of any captured repository fact.

## Nothing is executed

Planning never installs, erases, or verifies a package; it runs no scriptlet
and writes no rpmdb. The resolve reads the declared rpmdb and writes only into
the declared scratch and metadata-cache directories, and the scratch tree is
removed before the call returns. A test takes a full inventory of the declared
root before and after and requires it to be unchanged.

When the process runs as root the call takes rpmz's process-wide instance lock
for its duration, exactly as the CLI does.

## Scope

This layer resolves. It does not download packages and it does not execute.

- Downloading the resolved RPMs and atomically exporting a self-contained
  bundle is [#187](https://github.com/cataggar/rpmz/issues/187).
- [`rpmz.replay`](replay-api.md) executes only a closed v2 bundle. It does not
  resolve again; the v2 plan's materialized `execution_steps` are the
  authority.

`transaction_plan.parse` accepts canonical v1 and v2 documents. It validates,
re-serializes, and requires byte identity, so reordered keys, extra fields,
alternate whitespace, malformed references, and forged digests are rejected.
Use `Plan.isReplayable()` rather than assuming any parsed plan can execute.
Version 1 remains supported for resolve-only compatibility, but replay
requires v2 and rejects v1 rather than inventing an order. There is no public C
ABI for this surface.

## How this is proven

`tests/public-zig-consumer/` is built the way a real dependent is built: from a
read-only copy of exactly what `build.zig.zon` packages, with remote fetching
disabled and only the pinned dependency closure available. It creates its own
repository and install root, resolves against them, and checks that the plan
resolved, that the requested package is in it, that no undeclared repository
appears, that repeating the request reproduces the bytes and digest, that
changing the architecture does not, and that the scratch tree is gone when the
call returns.

## Exporting a plan's inputs

A plan names the packages a transaction needs; it does not carry them. To
capture the inputs themselves, hand the same declared resolve request to
`bundle_export.exportBundle`, which resolves it and publishes every metadata
file and RPM the resulting plan refers to into one directory. After those RPMs
are verified, export asks the
same native transaction planner used by execution for its authoritative order
and writes a v2 plan. A standalone resolve remains v1 because execution order
cannot be known before the RPM headers are present.

`doc/transaction-bundle.md` describes the layout, what a consumer may rely on,
and the failures a published bundle is expected to survive.

## Actions versus execution order

`actions` are the stable semantic result of solving: they say which package is
installed, erased, upgraded, downgraded, reinstalled, or obsoleted and name
the exact prior rows. Their canonical array order makes plans reproducible,
but it is not sufficient to drive the native transaction engine.

A v2 export additionally records `execution_steps` in the exact sequence
returned by the production native transaction planner after verified RPM
headers are available. Multiple low-level steps may contribute to one action,
and one shared erase may contribute to multiple downgrade or obsolete
actions. Export rejects an order or replacement graph that cannot be
represented without loss.

Replay validates that binding, keeps the selected RPMs pinned, and submits the
steps in their stored order. It never sorts actions into a guessed order,
coalesces priors, re-solves, or selects a newer package. Result outcomes are
ordered by each action's first appearance in `execution_steps`; actions with no
step follow in action-index order. Each outcome aggregates the recorded
low-level steps, while v2 `execution_steps` remain the source of truth for
exact execution order.
