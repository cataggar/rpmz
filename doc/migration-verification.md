# Verifying a libsolv-to-Zig port

This document is for anyone — human or agent — porting a component off
vendored `libsolv` onto the native Zig stack. It records failure modes that
have actually shipped bugs or wasted review cycles in this repo, with the PR
numbers where they were caught.

Delete this file when `libsolv` is gone.

## 1. A green gate is not evidence of correctness

`zig build -Dlibsolv-oracle=true libsolv-oracle-test` crosschecks
**solver results only**. It does not check
query-command semantics, output formatting, cache paths, or plan field
values. `ztest` covers a broad but finite set of scenarios.

Three real production bugs passed both gates cleanly:

| Bug | PR | Why the gate missed it |
|---|---|---|
| `provides` matched on substrings | #252 | assertion was satisfied by unrelated stdout |
| `tdnf count` off by one | #252 | no test compared `count` to `list --all` |
| repository priority not normalized | #251 | oracle does not inspect plan fields |

**Therefore every port must include an explicit before/after behavioural
diff against `main`.** Build both binaries and compare real command output.
Do not substitute "the gate is green" for this.

## 2. How to compare two binaries *fairly*

Naively running the old and new binaries and diffing will produce false
differences. Two checkouts have **independently generated RPM fixtures**
(separate `rpmbuild` runs differ in compressed size), and each may be reading
a different cache.

In #255 this produced a diff that looked exactly like a regression —
`Download Size` off by 1–2 bytes on five lines — but was pure test artifact.

Pin all three of config, repository, and cache state:

```sh
# one server, one repo, serving ONE checkout's fixtures
cd <branch>/out/repo && python3 -m http.server 8080 &

# both binaries: same config file, same served repo, separate FRESH cachedirs
for pair in "<main>/out /tmp/c_main" "<branch>/out /tmp/c_branch"; do
  set -- $pair
  sudo -E env LD_LIBRARY_PATH=$1/lib $1/bin/tdnf \
      -c <branch>/out/repo/tdnf.conf --releasever=1.0 \
      --setopt=cachedir=$2 list tdnf-test-one
done
```

Stop the server with `kill <numeric PID>` (`pkill`/`killall` are unavailable
to agents).

Investigate any diff until you can explain **every line**. Do not dismiss one
as "probably fixture noise" without proving it, and do not accept one as a
real regression without ruling out the artifact above.

### Cache-affecting changes need a cross-binary check

If you touch cache naming or cache validity, a mismatch produces **no output
diff at all** — the cache is just silently rebuilt on every run, and users'
existing caches are orphaned. Prove compatibility directly (#254):

1. Let the **old** binary create the cache.
2. Run the **new** binary against it.
3. Diff `.solv` mtimes — unchanged means the cache was genuinely reused.

## 3. Call-site counts are a gameable proxy

"Remaining `Solv*` call sites" is a *proxy* for libsolv coupling. It can be
driven to zero without removing any dependency, by inlining libsolv's raw API
(`selection_make`, `Pool`, `Queue`, `Id`, `Solvable`, `FOR_REPOS`,
`SELECTION_*`) directly into the calling component — which is strictly worse,
because it also bypasses the `solv/` wrapper layer that is the designated
seam for removal.

The first attempt at #255 did this: `Solv*` went 27 → 0 while raw libsolv
symbols in `client/packageutils.c` went *up* across the board, and C lines
fell only 36 because code had been **moved from `solv/` into `client/`**.

**Report a raw-symbol diff against `main`, not just `Solv*` counts:**

```sh
for sym in selection_make queue_init queue_push2 pool_id2solvable \
           FOR_REPOS "Pool \*" "Solvable \*" "Queue " "Id " SELECTION_; do
  echo "$sym: main=$(git show origin/main:<file> | grep -c "$sym")" \
       "branch=$(grep -c "$sym" <file>)"
done
```

No symbol may exceed its `main` count. Real progress also shows up as
`solv/` shrinking and `tracked_c_lines` falling (#255 second pass: C lines
−441, `solv/` −1001 lines).

## 4. No silent fallbacks

A native path that falls back to libsolv on failure will mask its own gaps
*and* make the behavioural diff in §1 come out clean while the native
implementation is incomplete. #251 and #255 both landed with the native path
mandatory and no fallback; follow that precedent.

If you believe a fallback is required, prove whether it is even reachable
before defending it — instrument it and run the suite:

```c
/* NOTE: client/ builds with -Wdeclaration-after-statement -Werror,
   so declare with the other locals, never mid-function. */
FILE *_fbk = fopen("/tmp/fallback_hits.log", "a");

if (_fbk) { fprintf(_fbk, "HIT %s\n", pszName); fclose(_fbk); }
```

In #255 this showed **zero hits** across the full `ztest` suite and every
edge-case probe — the fallback was dead code carrying ~250 lines of raw
libsolv.

## 5. Deleting a test alongside the code it tested is not automatically safe

When you delete an implementation, split its tests into:

- assertions describing the **output contract** — these survive the
  implementation and must be rewritten natively;
- assertions describing the **deleted implementation's input contract** —
  these may go.

#251 deleted 22 tests as "obsolete". Ten described the output contract;
rewriting them exposed a real repository-priority bug. Beware sign and
normalization conventions that the old layer applied silently.

## 6. Gate hazards

- Never pipe `abi-audit` through `tail`/`head` — you read the pager's exit
  code and can miss `ABI regression:`. Redirect to a file and grep it.
- `zig build test` prints `failed command: .../test --listen=-` while exiting
  0. **Judge by exit code.**
- Always pass `--prefix ./out`.
- `sudo` runs leave root-owned files; a later `rm -rf out` fails and can
  silently leave a stale tree behind. Run
  `sudo chown -R "$(id -u):$(id -g)" .zig-cache out` first, and check the
  build actually ran.
- `rm -rf out` destroys the `ztest` repo seed; reinstall before `ztest`.
- Editing a C header may not invalidate the cached `@cImport` for
  `abi/repomd_layout.zig`; re-verify with `--cache-dir .zig-cache-verify`.
- `zig build ztest` requires root and a prior `zig build install --prefix
  ./out`. It reports `33/33 steps` — the install steps in that graph are what
  guarantee the tested binary is freshly built (#250). A much smaller step
  count means you are testing a **stale binary**.

## 7. `tracked_c_lines` is a ceiling, not a target

`scripts/c-to-zig-baseline.json` holds maximums. Porting *off* libsolv can
legitimately raise C lines before the orphaned `solv/` helpers are deleted.
Leave headroom: #242 tightened the ceiling to the exact actual and instantly
blocked an unrelated in-flight PR. Keep roughly 200 lines of slack.
