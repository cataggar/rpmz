#
# Copyright (C) 2026 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.
#

import glob
import json
import os
import sys

import pytest

PYTESTS_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
if PYTESTS_DIR not in sys.path:
    sys.path.insert(0, PYTESTS_DIR)

from cli_testlib import (  # noqa: E402
    MinimalCliRuntime,
    decorate_rpmz_cmd_for_test,
)

REPO_ROOT = os.path.dirname(PYTESTS_DIR)
FIXTURE_DIR = os.path.join(PYTESTS_DIR, 'fixtures', 'cli-golden')
FIXTURE_PATHS = sorted(glob.glob(os.path.join(FIXTURE_DIR, '*.json')))
BINDIR_ENV = 'RPMZ_CLI_GOLDEN_BINDIR'

pytestmark = pytest.mark.skipif(
    not FIXTURE_PATHS,
    reason='CLI golden fixtures are missing',
)


def _resolve_bindir():
    candidates = [
        os.environ.get(BINDIR_ENV),
        os.path.join(REPO_ROOT, 'out', 'bin'),
        os.path.join(REPO_ROOT, 'zig-out', 'bin'),
    ]
    for candidate in candidates:
        if candidate and os.path.isdir(candidate):
            return os.path.abspath(candidate)
    return None


@pytest.fixture(scope='module')
def cli_runtime():
    bindir = _resolve_bindir()
    if bindir is None:
        pytest.skip('built rpmz bindir not found')

    runtime = MinimalCliRuntime(
        bindir,
        os.path.join(os.path.dirname(bindir), 'cli-golden-test-runtime'),
    )
    yield runtime
    runtime.cleanup()


def _fixture_id(path):
    return os.path.splitext(os.path.basename(path))[0]


def test_test_harness_inserts_compatibility_command():
    config = {
        'bindir': 'bin',
        'repo_path': 'repo',
    }
    argv, executable = decorate_rpmz_cmd_for_test(
        ['rpmz', 'install', 'package'],
        config,
    )
    assert argv == [
        'rpmz',
        'tdnf',
        '-c',
        os.path.join('repo', 'rpmz.conf'),
        'install',
        'package',
    ]
    assert executable == os.path.join('bin', 'rpmz')


def test_test_harness_preserves_replay_command():
    config = {
        'bindir': 'bin',
        'repo_path': 'repo',
    }
    argv, executable = decorate_rpmz_cmd_for_test(
        ['rpmz', 'replay', '--help'],
        config,
        noconfig=True,
    )
    assert argv == [
        'rpmz',
        'replay',
        '--help',
    ]
    assert executable == os.path.join('bin', 'rpmz')


@pytest.mark.parametrize('fixture_path', FIXTURE_PATHS, ids=_fixture_id)
def test_cli_golden(cli_runtime, fixture_path):
    with open(fixture_path) as handle:
        expected = json.load(handle)

    actual = cli_runtime.capture(expected['argv'])

    assert actual['stdout'] == expected['stdout']
    assert actual['stderr'] == expected['stderr']
    assert actual['retval'] == expected['retval']
