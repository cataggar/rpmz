#!/usr/bin/env python3
"""Confine libsolv include spellings to the components build.zig pins.

build.zig pins libsolv headers with -I so the vendored copy wins over a
host libsolv-devel, but that pin is attached per module, by
addLibsolvIncludes. A source file in a module that never calls it can
still write `#include <solv/pool.h>`: /usr/include is on the default
search path, so the include resolves against whatever the host has, the
version assert in repomd/solver_oracle_bridge.zig is not in that
translation unit, and nothing fails. The bridge is test-only and belongs
exclusively to the opt-in solver oracle.

This audit narrows that: only the files that are compiled into pinned
modules may spell a libsolv header at all.

It is a lint, not a proof. It reads text, so a sufficiently determined
include -- one assembled from a runtime-computed constant, or split
across a line continuation -- can still evade it. It is sized to catch
the accident (someone adds an include to a new file), which is the only
way this has ever gone wrong. Symlinked directories are not descended;
symlinked files are read like any other.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Exactly the files that may reach libsolv, not the directories they live
# in. A directory exemption would be wrong on both counts: the pin is
# attached per *module*, and only 2 of the 15 module roots under repomd/
# are passed LibsolvIncludes, so `repomd/**` would exempt files that
# compile with /usr/include on the search path and no version assert in
# scope. Keeping this a file list also makes it fail loudly rather than
# silently when the oracle bridge is renamed or deleted.
ALLOWED = {
    # The test-only pinned Zig @cImport; carries the comptime assert.
    "repomd/solver_oracle_bridge.zig",
}

# Walked from the repository root and pruned, rather than an allowlist of
# component directories: a new top-level component must be covered on the
# day it is created, not on the day someone remembers to list it. abi/ and
# ztests/ were missed exactly that way.
SKIP_DIRS = {
    ".git", ".zig-cache", "zig-cache", "zig-out", "zig-pkg", "node_modules",
}
SKIP_PREFIXES = ("out",)

SUFFIXES = {".c", ".h", ".zig"}

PATTERNS = (
    # #include <solv/pool.h> / #include "solv/pool.h"
    re.compile(r'#\s*include\s*[<"](solv/[\w./-]+\.h)'),
    # @cInclude("solv/pool.h"), and @cInclude("solv/" ++ "pool.h")
    re.compile(r'@cInclude\s*\(\s*"(solv/[\w./-]*)'),
    # #define TDNF_HDR <solv/pool.h>, then #include TDNF_HDR
    re.compile(r'#\s*define\s+\w+\s+[<"](solv/[\w./-]+\.h)'),
)

# The macro build.zig defines alongside the include paths. A file that
# names it is compiling its own version assert.
ASSERT_TOKEN = "TDNF_VENDORED_LIBSOLV_VERSION_PATCH"

# __has_include(<solv/pool.h>) is deliberately NOT matched: it is a
# predicate, brings no declaration into the translation unit, and
# client/includes.h uses it as a negative control that must keep working.


def sources():
    stack = [ROOT]
    while stack:
        current = stack.pop()
        for entry in sorted(current.iterdir()):
            if entry.is_dir():
                if entry.is_symlink():
                    continue
                if entry.name in SKIP_DIRS or entry.name.startswith("."):
                    continue
                if entry.name.startswith(SKIP_PREFIXES):
                    continue
                stack.append(entry)
            elif entry.suffix in SUFFIXES:
                yield entry


def main() -> int:
    client_c_sources = sorted(
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "client").glob("*.c")
        if path.is_file()
    )
    if client_c_sources:
        print(
            "error: client/ must remain free of C translation units:",
            file=sys.stderr,
        )
        for rel in client_c_sources:
            print(f"  {rel}", file=sys.stderr)
        return 1

    violations = []
    seen_allowed = set()
    for path in sources():
        rel = path.relative_to(ROOT).as_posix()
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"error: cannot read {rel}: {exc}", file=sys.stderr)
            return 1
        for lineno, line in enumerate(text.splitlines(), 1):
            for pattern in PATTERNS:
                match = pattern.search(line)
                if not match:
                    continue
                if rel in ALLOWED:
                    seen_allowed.add(rel)
                else:
                    violations.append((rel, lineno, match.group(1)))
                break

    stale = sorted(ALLOWED - seen_allowed)

    # An exemption is only safe if the assert compiles in every module
    # the file lands in. Files that carry the assert satisfy that
    # themselves; the rest must import one that does, or a module that
    # never calls addLibsolvIncludes could pull the fixture in and
    # resolve its includes against /usr/include with nothing to notice.
    asserting = set()
    unguarded = []
    texts = {}
    for rel in sorted(ALLOWED):
        path = ROOT / rel
        if not path.is_file():
            continue
        texts[rel] = path.read_text(encoding="utf-8", errors="replace")
        if ASSERT_TOKEN in texts[rel]:
            asserting.add(rel)
    for rel, text in texts.items():
        if rel in asserting:
            continue
        names = [Path(other).name for other in asserting]
        if not any(name in text for name in names):
            unguarded.append(rel)

    if violations:
        print(
            "error: libsolv headers are spelled outside the files "
            "build.zig pins them for.",
            file=sys.stderr,
        )
        for rel, lineno, header in violations:
            print(f"  {rel}:{lineno}: {header}", file=sys.stderr)
        print(
            "\nThese translation units are not handed the vendored include "
            "tree, so the\ninclude resolves against /usr/include on any host "
            "with libsolv-devel and the\nversion asserts are not in scope. "
            "Reach libsolv through one of:\n  "
            + "\n  ".join(sorted(ALLOWED))
            + "\ninstead, or add the module to addLibsolvIncludes in "
            "build.zig and this file\nto ALLOWED here.",
            file=sys.stderr,
        )
        return 1

    if stale:
        print(
            "error: ALLOWED lists files that no longer spell a libsolv "
            "header:",
            file=sys.stderr,
        )
        for rel in stale:
            print(f"  {rel}", file=sys.stderr)
        print(
            "\nRemove them from ALLOWED so the exemption cannot outlive the "
            "consumer.",
            file=sys.stderr,
        )
        return 1

    if unguarded:
        print(
            "error: these permitted consumers neither carry the libsolv "
            "version assert nor\nimport a file that does:",
            file=sys.stderr,
        )
        for rel in unguarded:
            print(f"  {rel}", file=sys.stderr)
        print(
            "\nWithout it they can be compiled into a module that was never "
            "passed the\nvendored include tree, and resolve against "
            "/usr/include silently.",
            file=sys.stderr,
        )
        return 1

    print(
        f"libsolv include audit: zero client C sources, "
        f"{len(seen_allowed)} permitted consumers, "
        "no other libsolv spellings in the tree"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
