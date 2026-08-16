# The transaction-bundle format

A [transaction plan](transaction-plan-api.md) says *what* a transaction would
do. It does not carry the bytes needed to do it. A **transaction bundle** is
the closure of those bytes: the plan, the repository metadata it was resolved
against, every RPM the plan's actions install, and every public key that
verified them, laid out in a fixed directory structure under a manifest that
names and hashes each file.

New exports use `tdnf.transaction-bundle/v2` and reference a
`tdnf.transaction-plan/v2`. The v1 manifest and plan remain strictly parseable
for compatibility, but are resolve-only and must not be treated as replayable.
The module documentation in `client/transaction_bundle.zig` is the reference.
[`rpmz.replay`](replay-api.md) requires both v2 schemas and rejects v1 rather
than reconstructing a missing execution order.

## What a bundle is

A bundle is a directory. Its manifest, `bundle.json`, is the only entry point.

```
bundle/
  bundle.json                     the manifest (never lists itself)
  plan.json                       the canonical transaction plan
  repos/<repository-id>/...       the metadata snapshot, as fetched
  packages/<repository-id>/...    one RPM per install-side action target
  keys/<fingerprint>.asc          the public keys that verified them
```

The manifest has six top-level members, emitted in this order:

- **`digest`** — SHA-256 over the canonical bytes of the manifest *without*
  this member, under the domain named by `schema`.
- **`files`** — every file in the bundle except `bundle.json`, each with its
  bundle-relative `path`, `sha256`, and `size`.
- **`keys`** — the public keys, by full lowercase-hex `fingerprint` and
  `path`.
- **`packages`** — one entry per RPM: its `identity`, declared `checksum`,
  declared `href` and `xml_base`, the `repository_id` it came from, the
  `plan_package_id` that ties it back to the plan, its bundle `path`, and the
  `signature` outcome.
- **`plan`** — the plan's own `digest`, its `schema`, and its `path`.
- **`repositories`** — per repository: `id`, `cost`, `priority`, `gpg_check`,
  the `repomd_sha256` and `snapshot_id` that pin the metadata, the metadata
  `revision` when the repository declares one, and the sanitized `sources`.
- **`schema`** — `tdnf.transaction-bundle/v2` for new replay-capable exports;
  legacy v1 manifests remain readable.

## Guarantees

**The digest is the bundle's identity.** Two exports of the same resolve
against the same metadata produce the same digest. This is why the manifest
records the repository's *declared* source list rather than whichever mirror
happened to answer: recording the responding mirror would make two identical
exports differ.

**The file table describes the tree exactly.** Every file the manifest
references elsewhere must appear in `files`; nothing may appear twice; and
anything under `packages/`, `keys/`, or `repos/` must be accounted for by a
package, a key, or a declared repository. A file outside every structured
prefix other than `plan.json` is rejected. A bundle therefore cannot carry a
payload the manifest does not describe.

**The manifest never describes itself.** `bundle.json` carries the digest of
the document it is embedded in, so its own SHA-256 could not be stated inside
it without circularity. A reader verifies the manifest by re-canonicalizing
it, not by hashing the file.

**A package cannot escape its own tree.** `packages/<repository-id>/...` is
enforced, so a repository cannot place a file into another repository's tree,
and paths are checked against absolute prefixes, traversal, dot segments,
backslashes, and drive letters rather than normalized.

**A verified signature must name its key.** `signature.outcome` is `verified`
or `unsigned`. `verified` requires a `key_fingerprint` that is present in
`keys`; `unsigned` forbids one. A bundle can never claim verification without
shipping the key that performed it.

**Every v2 RPM is bound to its plan package.** The reader requires the
manifest's identity, repository, repository checksum, href, XML base, and size
to match the available `package-N` exactly. Every install-side execution step
must have exactly one manifest RPM, and no other package entry is accepted.

**Sources are sanitized at the model boundary.** Userinfo, query strings, and
fragments are rejected outright, and both the raw and percent-decoded forms
are scanned for secret-shaped text. A sanitizer regression fails closed at
construction rather than publishing a credential.

## Reading a bundle

`transaction_bundle.parse` is strict rather than lenient. It rebuilds the
model, validates it, re-serializes it, and requires the result to be
byte-identical to the input. That single check subsumes rejecting reordered
keys, unknown keys, altered whitespace, alternate number spellings, and a
`digest` that disagrees with the document it covers — any of those produce
different canonical bytes. A reader therefore never accepts a manifest it
would not itself have written.

```zig
const rpmz = @import("rpmz");

const bundle = try rpmz.transaction_bundle.parse(allocator, manifest_bytes);
defer bundle.destroy();

for (bundle.model().files) |file| {
    // verify file.sha256 against the byte content at file.path
}
```

`Bundle.findFile` looks an entry up by exact bundle-relative path.
`Bundle.isReplayable()` is true only for a v2 manifest referencing a v2 plan.
It is still necessary for replay to validate the plan's materialized execution
shape, every file, the target architecture, and the exact rpmdb state before
mutation; `isReplayable` is a schema capability check, not execution.

## Relationship to the plan

The plan's `digest` and the `plan.json` file's `sha256` are different values
and both are recorded: the former is the plan's identity as computed over its
own digest-free document, the latter is the hash of the bytes on disk. A
reader checks both.

Only install-side action targets are bundled. Installed packages in a plan
carry no fetch coordinates by construction — they have no `source` and are
identified by their rpmdb header number — so there is nothing to fetch for the
prior rows of an upgrade. A plan containing a command-line package, which has
no `location`, cannot be bundled and is rejected.

The v2 plan's `execution_steps` preserve the exact low-level order returned by
the native planner after package headers are available. Replay uses those
steps directly; it does not derive an order from the semantic `actions` array.
The manifest's one-to-one package binding ensures every install-side step has
exactly the RPM whose header was used when that order was captured.

## How bytes are verified before they enter a bundle

A bundle is a claim about content, so recording a digest computed over bytes
nobody checked would launder an unverified download into an
authoritative-looking artifact. `client/verified_fetch.zig` is the only place
that turns a downloaded file into a bundle `files` entry, and it enforces two
rules in the type system rather than by convention:

1. **No expectation, no acceptance.** `Expectation.checksum` is not optional
   and has no default, so there is no "verify if we happen to know how" mode
   and no flag that switches checking off. A plan metadata record without a
   checksum yields no expectation at all, forcing the caller to decide
   explicitly.
2. **The recorded digest is computed over the verified bytes.** A `Capture` —
   which carries the SHA-256 a `files` entry records — can only be produced by
   a function that has already compared the content against its expectation.

An unrecognised checksum algorithm is refused (`UnsupportedChecksum`), never
skipped: naming an algorithm rpmz cannot compute is exactly how an attacker
would ask for a file to go unchecked. Hashing and the set of acceptable
algorithm names live in `repomd/content_digest.zig`, shared with the repomd
loader, so the two paths cannot come to disagree about what counts as
verified.

Every failure mode is a distinct error — `ChecksumMismatch`, `SizeMismatch`,
`OpenChecksumMismatch`, `OpenSizeMismatch`, `UnsupportedChecksum`,
`StagedFileTooLarge`, `UnreadableStagedFile`, and `FetchFailed` — so a caller
can tell "could not reach the repository" from "the repository served
something other than what it promised".

`fetchVerified` stages into a scratch directory and **deletes the staged file
on any failure**, because leaving unverified bytes behind under their final
name is how a rejected download becomes a poisoned cache. The transfer itself
is injected as a `Fetcher`: downloading needs a `TDNF_HANDLE` (proxies,
mirrors, TLS policy), and taking that dependency would make the verification
rules untestable in isolation.

`verifyRepomd` pins a fetched `repomd.xml` against the plan's
`repomd.checksum_sha256`. That check is the root of the metadata trust chain —
every record checksum relied on afterwards is only as trustworthy as the
`repomd.xml` it was read from — so it takes a bare 64-character hex SHA-256
rather than a repository-chosen algorithm, and a short or empty pin is refused
rather than treated as "no pin required".

An advertised open size is consulted only when the metadata published no open
checksum. A verified open checksum already proves the exact decompressed
bytes, so a disagreeing open size indicts the metadata rather than the
content; this matches the repomd loader, which in turn matches what every
other package manager tolerates in the wild.

## URIs in a bundle never carry secrets

`client/uri_sanitize.zig` is the single chokepoint for making a URI safe to
show or to store. It distinguishes two operations that used to be conflated:

- `redactAlloc` marks the removed parts, for diagnostics a human reads.
- `recordableAlloc` drops userinfo, query, and fragment outright, for URIs
  written into a manifest.

Repository configuration may legitimately carry a `?token=` query, so such a
repository must keep working while leaking nothing. Only userinfo is refused
outright; query and fragment are stripped. `transaction_bundle.validateSource`
then rejects any remaining `?` or `#`, so an unsanitised URI cannot reach a
manifest even if a future call site forgets.

## Exporting a bundle

`rpmz.bundle_export.exportBundle` resolves a transaction and publishes the
bundle for it. It takes the same `resolver.ResolveInput` as `resolvePlan`.
The resolve-only result is v1; after verified RPM headers are staged, export
passes the captured native transaction inputs through the production native
transaction planner and records its returned order in the bundled v2 plan.
That order is captured, not reconstructed from canonical action sorting.

```zig
var result = try rpmz.bundle_export.exportBundle(allocator, io, .{
    .resolve = resolve_input,
    .destination = "/var/tmp/tx-bundle",
    .keys = &.{.{ .path = "/etc/pki/rpm-gpg/RPM-GPG-KEY-example" }},
});
defer result.deinit();

switch (result) {
    .exported => |exported| { /* exported.bundle_digest, exported.plan */ },
    .problems => |plan| { /* nothing was written; report plan.problems */ },
}
```

### What ends up in a bundle

Only the packages the transaction must **fetch**. An upgrade's prior row is an
installed package: it has no repository, no href, and no checksum, because the
plan schema requires installed packages to carry none. It stays in `plan.json`
as a precondition a replay must check, and it is not a file. An erase
therefore produces a bundle with no RPMs at all, while still capturing the
repository metadata that made the resolve reproducible.

A command-line RPM is refused rather than exported. Its location is null by
design, so there is nothing to record that another host could act on; giving
it a synthetic repository would produce a bundle that claims a
reproducibility it does not have.

### Failure is all-or-nothing

Every byte is staged outside the destination and the tree is moved into place
with a single non-replacing rename, so a partially fetched export leaves
nothing behind and an export onto an existing path is refused by the kernel
rather than by a check that could race. There is no state in which a
destination exists and is incomplete.

The failures are kept distinct because they call for different responses:

| Outcome | Meaning |
| --- | --- |
| `FetchFailed` | A repository could not be reached. |
| `IntegrityFailure` | A repository served bytes other than the plan's. |
| `SignatureRejected` | The bytes were as promised and still not shippable. |
| `CommandLinePackageUnsupported` | The plan has no coordinates for a package. |
| `PublishFailed` | The destination exists, or the tree could not be published. |

### Which key a bundle may cite

Signature verification for an export uses the **declared** keys and nothing
else. The verification path used during a normal install folds in the install
root's rpmdb keyring, which is ambient local state; a package signed by a key
that merely happens to be installed on the exporting host has not been vouched
for by anything the bundle carries. A bundle names the key that validated a
package or makes no claim about it, and only keys that actually validated
something are copied into `keys/`.

Attestation runs on the staged file, after its checksum matched, so the claim
in the manifest is a claim about the bytes a consumer will open rather than
about some earlier copy.

## Replaying a bundle

Pass the published directory to `rpmz.replay.run` or `rpmz replay`. Replay
opens it as a closed local input set, rechecks canonical manifest and plan
bytes, metadata and RPM content, signatures, architecture, rpmdb snapshot, and
prior rows, then executes the v2 steps in their recorded order.

The project-owned replay implementation never follows the manifest's sanitized
source records to a repository; those records are provenance, not replay
inputs. RPM payload scriptlets, triggers, interpreters, and their descendants
are outside that guarantee and can use the network. Callers must enforce an
OS-level no-network namespace or equivalent isolation for exact offline
execution. The full API, result, failure, and CLI contract is in [Offline
transaction replay](replay-api.md).
