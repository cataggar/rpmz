#
# Copyright (C) 2026 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.
#

import os
import subprocess


PYTESTS_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
REPO_ROOT = os.path.dirname(PYTESTS_DIR)
COMPLETION = os.path.join(
    REPO_ROOT, 'etc', 'bash_completion.d', 'rpmz-completion.bash',
)
COMPATIBILITY_COMMAND = 'tdnf'


def _complete(*words):
    script = r'''
source "$1"
shift
COMP_WORDS=("$@")
COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
cur="${COMP_WORDS[COMP_CWORD]}"
_rpmz
printf '%s\n' "${COMPREPLY[@]}"
'''
    result = subprocess.run(
        ['bash', '-c', script, 'bash', COMPLETION, *words],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.splitlines()


def test_completion_registers_user_managed_compatibility_symlink():
    result = subprocess.run(
        [
            'bash',
            '-c',
            'source "$1"; complete -p "$2"',
            'bash',
            COMPLETION,
            COMPATIBILITY_COMMAND,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert '-F _rpmz' in result.stdout
    assert result.stdout.rstrip().endswith('rpmz tdnf')


def test_legacy_completion_routes_rpmz_tdnf_and_tdnf_symlink():
    rpmz_commands = _complete('rpmz', COMPATIBILITY_COMMAND, '')
    rpmz_options = _complete('rpmz', COMPATIBILITY_COMMAND, '--')
    tdnf_commands = _complete(COMPATIBILITY_COMMAND, '')
    tdnf_options = _complete(COMPATIBILITY_COMMAND, '--')

    assert 'install' in rpmz_commands
    assert '--installroot' in rpmz_options
    assert 'install' in tdnf_commands
    assert '--installroot' in tdnf_options
    assert 'replay' not in tdnf_commands


def test_top_level_commands_complete_without_root_command_choices():
    top_level = _complete('rpmz', '')
    replay = _complete('rpmz', 'replay', '--')
    auto = _complete('rpmz', 'auto', '--')
    repo_config = _complete('rpmz', 'repo-config', '')

    assert {'auto', 'repo-config', 'replay', COMPATIBILITY_COMMAND} <= set(
        top_level
    )
    assert {'--installroot', '--rpmdb-path', '--forcearch'} <= set(replay)
    assert {'--conf', '--install', '--notify', '--timer'} <= set(auto)
    assert {'create', 'edit', 'get', 'remove', 'removerepo', 'dump'} <= set(
        repo_config
    )

    root_commands = {'auto', 'repo-config', 'replay', COMPATIBILITY_COMMAND}
    assert not root_commands.intersection(replay)
    assert not root_commands.intersection(auto)
    assert not root_commands.intersection(repo_config)
