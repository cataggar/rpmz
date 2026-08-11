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
