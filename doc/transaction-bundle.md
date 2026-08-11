# The transaction-bundle format

A [transaction plan](transaction-plan-api.md) says *what* a transaction would
do. It does not carry the bytes needed to do it. A **transaction bundle** is
the closure of those bytes: the plan, the repository metadata it was resolved
against, every RPM the plan's actions install, and every public key that
verified them, laid out in a fixed directory structure under a manifest that
names and hashes each file.

This document describes the manifest schema, `tdnf.transaction-bundle/v1`. The
module documentation in `client/transaction_bundle.zig` is the reference; this
is the contract.

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
  this member, under the domain `tdnf.transaction-bundle/v1`.
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
- **`schema`** — always `tdnf.transaction-bundle/v1`.

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
const tdnf = @import("tdnf");

const bundle = try tdnf.transaction_bundle.parse(allocator, manifest_bytes);
defer bundle.destroy();

for (bundle.model().files) |file| {
    // verify file.sha256 against the byte content at file.path
}
```

`Bundle.findFile` looks an entry up by exact bundle-relative path.

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
skipped: naming an algorithm tdnf cannot compute is exactly how an attacker
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
