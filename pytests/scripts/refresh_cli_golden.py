#!/usr/bin/env python3
#
# Copyright (C) 2026 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.
#

import argparse
import json
import os
import re
import sys

PYTESTS_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
if PYTESTS_DIR not in sys.path:
    sys.path.insert(0, PYTESTS_DIR)

from cli_testlib import MinimalCliRuntime  # noqa: E402

CMD_RE = re.compile(
    r'^\s*\.{\s*\.pszCmdName\s*=\s*"([^"]+)",'
    r"\s*\.pFnCmd\s*=\s*(?:[A-Za-z_][A-Za-z0-9_]*\.)?TDNFCli[^,]+,"
    r"\s*\.ReqRoot\s*=\s*(?:true|false)\s*},\s*$",
    re.MULTILINE,
)
BINDIR_ENV = 'RPMZ_CLI_GOLDEN_BINDIR'
TOP_LEVEL_CASES = {
    'rpmz-help-long',
    'rpmz-no-args',
    'rpmz-bad-command',
    'rpmz-bad-option',
    'rpmz-version',
}


def parse_args():
    parser = argparse.ArgumentParser(
        description='Refresh CLI golden-output fixtures.',
    )
    parser.add_argument(
        '--bindir',
        default=os.environ.get(BINDIR_ENV),
        help='Directory containing built rpmz binaries.',
    )
    parser.add_argument(
        '--fixtures-dir',
        default=os.path.join(PYTESTS_DIR, 'fixtures', 'cli-golden'),
        help='Directory where JSON fixtures are written.',
    )
    parser.add_argument(
        '--main-c',
        default=os.path.join(
            os.path.dirname(PYTESTS_DIR),
            'tools',
            'cli',
            'main.zig',
        ),
        help='Path to tools/cli/main.c.',
    )
    parser.add_argument(
        '--runtime-root',
        help='Directory for the temporary runtime tree.',
    )
    args = parser.parse_args()

    if not args.bindir:
        for candidate in _default_bindir_candidates():
            if os.path.isdir(candidate):
                args.bindir = candidate
                break

    if not args.bindir:
        parser.error(
            '--bindir is required or {} must be set'.format(BINDIR_ENV),
        )

    args.bindir = os.path.abspath(args.bindir)
    args.fixtures_dir = os.path.abspath(args.fixtures_dir)
    if args.runtime_root:
        args.runtime_root = os.path.abspath(args.runtime_root)
    else:
        args.runtime_root = os.path.join(
            os.path.dirname(args.bindir),
            'cli-golden-runtime',
        )
    args.main_c = os.path.abspath(args.main_c)
    return args


def _default_bindir_candidates():
    repo_root = os.path.dirname(PYTESTS_DIR)
    return [
        os.path.join(repo_root, 'out', 'bin'),
        os.path.join(repo_root, 'zig-out', 'bin'),
    ]


def load_command_names(main_c_path):
    with open(main_c_path) as handle:
        content = handle.read()
    return CMD_RE.findall(content)


def build_cases(commands):
    cases = [
        {'name': 'rpmz-help-long', 'argv': ['rpmz', '--help']},
        {'name': 'rpmz-help-command', 'argv': ['rpmz', 'help']},
        {'name': 'rpmz-no-args', 'argv': ['rpmz']},
        {
            'name': 'rpmz-bad-command',
            'argv': ['rpmz', 'definitely-not-a-command'],
        },
        {'name': 'rpmz-bad-option', 'argv': ['rpmz', '--bad-option']},
        {'name': 'rpmz-missing-config-arg', 'argv': ['rpmz', '--config']},
        {
            'name': 'rpmz-missing-installroot-arg',
            'argv': ['rpmz', '--installroot'],
        },
        {'name': 'rpmz-missing-setopt-arg', 'argv': ['rpmz', '--setopt']},
        {
            'name': 'rpmz-relative-installroot',
            'argv': ['rpmz', '--installroot', 'relative-root', 'list'],
        },
        {'name': 'rpmz-version', 'argv': ['rpmz', '--version']},
    ]

    for command in commands:
        cases.append({
            'name': 'rpmz-{}-help'.format(command),
            'argv': ['rpmz', command, '--help'],
        })

    cases.extend([
        {'name': 'rpmz-clean-no-arg', 'argv': ['rpmz', 'clean']},
        {
            'name': 'rpmz-clean-invalid-arg',
            'argv': ['rpmz', 'clean', 'abcde'],
        },
        {'name': 'rpmz-provides-no-arg', 'argv': ['rpmz', 'provides']},
        {
            'name': 'rpmz-whatprovides-no-arg',
            'argv': ['rpmz', 'whatprovides'],
        },
        {'name': 'rpmz-search-no-arg', 'argv': ['rpmz', 'search']},
        {
            'name': 'rpmz-install-no-arg',
            'argv': ['rpmz', 'install'],
            'skip_if_nonroot': True,
            'skip_reason': (
                'requires root to reach the parser-specific no-arg path'
            ),
        },
        {
            'name': 'rpmz-erase-no-arg',
            'argv': ['rpmz', 'erase'],
            'skip_if_nonroot': True,
            'skip_reason': (
                'requires root to reach the parser-specific no-arg path'
            ),
        },
        {
            'name': 'rpmz-list-invalid-package',
            'argv': ['rpmz', 'list', 'invalid_package'],
        },
        {
            'name': 'rpmz-updateinfo-invalid-package',
            'argv': ['rpmz', 'updateinfo', 'invalid_package'],
        },
        {
            'name': 'rpmz-reposync-norepopath-delete',
            'argv': ['rpmz', 'reposync', '--norepopath', '--delete'],
        },
        {
            'name': 'rpmz-repo-config-create',
            'argv': [
                'rpmz',
                'repo-config',
                'create',
                'foo',
                'name=Foo',
                'baseurl=http://foo.bar.com',
                'enabled=1',
            ],
        },
        {
            'name': 'rpmz-repo-config-edit',
            'argv': ['rpmz', 'repo-config', 'edit', 'foo', 'enabled=true'],
        },
        {
            'name': 'rpmz-repo-config-get',
            'argv': ['rpmz', 'repo-config', 'get', 'foo', 'baseurl'],
        },
        {
            'name': 'rpmz-repo-config-dump',
            'argv': ['rpmz', 'repo-config', '-j', 'dump', 'foo'],
        },
        {
            'name': 'rpmz-repo-config-remove',
            'argv': ['rpmz', 'repo-config', 'remove', 'foo', 'gpgcheck'],
        },
        {
            'name': 'rpmz-repo-config-removerepo',
            'argv': ['rpmz', 'repo-config', 'removerepo', 'foo'],
        },
        {
            'name': 'rpmz-repo-config-bad-option',
            'argv': ['rpmz', 'repo-config', '--bad-option'],
        },
        {
            'name': 'rpmz-repo-config-bad-action',
            'argv': ['rpmz', 'repo-config', 'frobnicate'],
        },
    ])
    for case in cases:
        if case['name'] not in TOP_LEVEL_CASES and (
                case['argv'][0] == 'rpmz' and
                case['argv'][1] != 'repo-config'):
            case['argv'].insert(1, 'tdnf')
    return cases


def write_fixture(fixtures_dir, case_name, capture):
    fixture_path = os.path.join(fixtures_dir, case_name + '.json')
    payload = {
        'argv': capture['argv'],
        'stdout': capture['stdout'],
        'stderr': capture['stderr'],
        'retval': capture['retval'],
    }
    with open(fixture_path, 'w') as handle:
        json.dump(payload, handle, indent=2)
        handle.write('\n')


def remove_stale_fixtures(fixtures_dir, captured_names):
    expected = {name + '.json' for name in captured_names}
    for entry in os.listdir(fixtures_dir):
        if entry.endswith('.json') and entry not in expected:
            os.remove(os.path.join(fixtures_dir, entry))


def should_skip(case):
    if case.get('skip_if_nonroot') and os.geteuid() != 0:
        return case['skip_reason']
    return None


def main():
    args = parse_args()
    command_names = load_command_names(args.main_c)
    cases = build_cases(command_names)
    os.makedirs(args.fixtures_dir, exist_ok=True)

    runtime = MinimalCliRuntime(args.bindir, args.runtime_root)
    captured_names = []
    skipped = []
    try:
        for case in cases:
            skip_reason = should_skip(case)
            if skip_reason:
                skipped.append((case['name'], skip_reason))
                continue

            capture = runtime.capture(case['argv'])
            write_fixture(args.fixtures_dir, case['name'], capture)
            captured_names.append(case['name'])

        remove_stale_fixtures(args.fixtures_dir, captured_names)
    finally:
        runtime.cleanup()

    print('Captured {} fixtures in {}'.format(
        len(captured_names),
        args.fixtures_dir,
    ))
    for name, reason in skipped:
        print('Skipped {}: {}'.format(name, reason))


if __name__ == '__main__':
    main()
