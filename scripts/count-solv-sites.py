#!/usr/bin/env python3
"""Count calls from client/ into solv/ -- the libsolv-decoupling metric.

The long-running campaign to remove libsolv from client/ reports its
progress as a single number: how many times a client/*.c file calls a
function that solv/ exports.  Commit messages cite that number, so the
measurement has to live in the repository where anyone can re-run it:

    python3 scripts/count-solv-sites.py .

DENOMINATOR HAZARD -- read before quoting the number.

The set of names this looks for is harvested from solv/prototypes.h *in
the tree being measured*.  That makes the metric a proxy, and the proxy
is gameable in a way that looks like progress: delete a prototype and
its call sites stop being counted, whether or not any coupling was
actually removed.  Deleting solv/prototypes.h outright would report a
perfect score of zero.

Two things guard against quoting a fall that is really a shrinking
denominator.  This prints the size of the name set alongside the total,
so a change in the denominator is visible in the output rather than
hidden in it.  And --names-from pins the name set to another tree or
git ref, so a change can be measured against a fixed denominator:

    python3 scripts/count-solv-sites.py . --names-from origin/main

If the two disagree, the honest number is the pinned one.  See
doc/migration-verification.md for why a raw proxy is not evidence on
its own.
"""

import argparse
import glob
import os
import re
import subprocess
import sys

KEYWORDS = frozenset(('if', 'for', 'while', 'switch', 'return', 'sizeof'))


def harvest_names(text):
    """Function names solv/ exports, taken from a prototypes.h body.

    Prototypes are written with the name in column 0 on its own line,
    so an anchored match picks up definitions without also picking up
    calls.  C keywords can match that shape in other contexts and are
    dropped.
    """
    names = set(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*)\(', text, re.M))
    return names - KEYWORDS


def strip_noise(src):
    """Blank comments and string literals, preserving offsets and lines.

    A name inside a comment or a literal is not a call.  Earlier
    increments of this campaign were misled by exactly that, so the
    text is neutralised rather than the matches filtered afterwards.
    """
    out = []
    i = 0
    n = len(src)
    while i < n:
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
        elif src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == '\\' else 1
            j = min(j + 1, n)
        else:
            out.append(src[i])
            i += 1
            continue
        out.append(''.join(c if c == '\n' else ' ' for c in src[i:j]))
        i = j
    return ''.join(out)


def read_names_source(spec, tree):
    """Read a prototypes.h from a path, a directory, or a git ref."""
    if spec is None:
        spec = tree
    if os.path.isdir(spec):
        with open(os.path.join(spec, 'solv/prototypes.h')) as handle:
            return handle.read(), spec
    if os.path.isfile(spec):
        with open(spec) as handle:
            return handle.read(), spec
    done = subprocess.run(
        ['git', 'show', '%s:solv/prototypes.h' % spec],
        capture_output=True, text=True, cwd=tree)
    if done.returncode != 0:
        raise SystemExit(
            'cannot read solv/prototypes.h from %r: not a directory, not a '
            'file, and not a git ref' % spec)
    return done.stdout, spec


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('tree', nargs='?', default='.',
                        help='repository root to measure (default: .)')
    parser.add_argument('--names-from', default=None, metavar='SPEC',
                        help='pin the name set to another tree, file or git '
                             'ref instead of harvesting it from TREE')
    args = parser.parse_args()

    proto, origin = read_names_source(args.names_from, args.tree)
    names = harvest_names(proto)
    patterns = [re.compile(r'\b%s\s*\(' % re.escape(n)) for n in names]

    total = 0
    per_file = {}
    for path in sorted(glob.glob(os.path.join(args.tree, 'client/*.c'))):
        with open(path) as handle:
            text = strip_noise(handle.read())
        count = sum(len(p.findall(text)) for p in patterns)
        if count:
            per_file[os.path.basename(path)] = count
            total += count

    print('%s TOTAL %d' % (args.tree, total))
    print('    (name set: %d names from %s)' % (len(names), origin))
    for name, count in sorted(per_file.items(), key=lambda kv: -kv[1]):
        print('   ', name, count)
    return 0


if __name__ == '__main__':
    sys.exit(main())
