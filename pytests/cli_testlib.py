#
# Copyright (C) 2026 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.
#

import os
import re
import shutil
import subprocess

ERROR_RETVAL_RE = re.compile(r'^Error\((\d+)\) :', re.MULTILINE)
RPMZ_BINARIES = {'rpmz'}
RPMZ_TOP_LEVEL_COMMANDS = {'auto', 'repo-config', 'tdnf'}


def split_output_lines(text):
    if not text:
        return []
    return text.split('\n')


def derive_retval(returncode, stderr):
    capture = ERROR_RETVAL_RE.search(stderr)
    if capture:
        return int(capture.group(1))
    return returncode


def normalize_command_result(returncode, stdout, stderr):
    stdout_text = stdout.decode().strip()
    stderr_text = stderr.decode().strip()
    return {
        'stdout': stdout_text,
        'stderr': stderr_text,
        'retval': derive_retval(returncode, stderr_text),
    }


def resolve_bindir(config):
    bindir = config.get('bindir')
    if bindir:
        return bindir
    return os.path.join(config['build_dir'], 'bin')


def build_command_env(_config):
    return os.environ.copy()


def decorate_rpmz_cmd_for_test(
        cmd, config, noconfig=False, compatibility=True):
    decorated = list(cmd)
    executable = None

    if decorated[0] in RPMZ_BINARIES:
        # Existing integration cases use the historical short argv form.
        if (compatibility and len(decorated) > 1 and
                decorated[1] not in RPMZ_TOP_LEVEL_COMMANDS):
            decorated.insert(1, 'tdnf')
        executable = os.path.join(resolve_bindir(config), decorated[0])
        if ('-c' not in decorated and '--config' not in decorated and
                not noconfig):
            config_index = (
                2 if len(decorated) > 1 and decorated[1] in {
                    'repo-config', 'tdnf',
                }
                else 1
            )
            decorated[config_index:config_index] = [
                '-c',
                os.path.join(config['repo_path'], 'rpmz.conf'),
            ]

    return decorated, executable


def run_command(
        cmd, config, cwd=None, noconfig=False, compatibility=True):
    use_shell = not isinstance(cmd, list)
    decorated = cmd
    executable = None

    if isinstance(cmd, list):
        decorated, executable = decorate_rpmz_cmd_for_test(
            cmd,
            config,
            noconfig=noconfig,
            compatibility=compatibility,
        )

    process = subprocess.Popen(
        decorated,
        shell=use_shell,
        executable=executable,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        stdin=subprocess.DEVNULL,
        cwd=cwd,
        env=build_command_env(config),
    )
    stdout, stderr = process.communicate()
    result = normalize_command_result(process.returncode, stdout, stderr)
    if isinstance(cmd, list):
        result['argv'] = list(cmd)
    else:
        result['argv'] = cmd.split()
    return result


class MinimalCliRuntime(object):
    def __init__(self, bindir, runtime_root):
        self.bindir = os.path.abspath(bindir)
        self.runtime_root = os.path.abspath(runtime_root)
        self.config = {
            'bindir': self.bindir,
            'repo_path': os.path.join(self.runtime_root, 'repo'),
        }

    def cleanup(self):
        if os.path.isdir(self.runtime_root):
            shutil.rmtree(self.runtime_root)

    def reset(self):
        self.cleanup()
        os.makedirs(self._repodir(), exist_ok=True)
        os.makedirs(self._cachedir(), exist_ok=True)
        self._write_rpmz_config()

    def capture(self, argv, cwd=None, noconfig=False):
        self.reset()
        self.prepare_case(argv)
        return run_command(
            argv,
            self.config,
            cwd=cwd,
            noconfig=noconfig,
            compatibility=False,
        )

    def prepare_case(self, argv):
        self.remove_repo_file()
        if len(argv) < 2 or argv[:2] != ['rpmz', 'repo-config']:
            return

        action = _get_repo_config_action(argv[2:])
        if action == 'edit':
            self.seed_repo_file({
                'name': 'Foo',
                'baseurl': 'http://foo.bar.com',
                'enabled': '0',
            })
        elif action == 'get':
            self.seed_repo_file({
                'name': 'Foo',
                'baseurl': 'http://foo.bar.com',
                'enabled': '0',
            })
        elif action == 'dump':
            self.seed_repo_file({
                'name': 'Foo',
                'baseurl': 'http://foo.bar.com',
                'enabled': '0',
            })
        elif action == 'remove':
            self.seed_repo_file({
                'name': 'Foo',
                'baseurl': 'http://foo.bar.com',
                'gpgcheck': '0',
            })
        elif action == 'removerepo':
            self.seed_repo_file({
                'name': 'Foo',
                'baseurl': 'http://foo.bar.com',
                'enabled': '1',
            })

    def remove_repo_file(self, repo_name='foo'):
        repo_file = self._repo_file(repo_name)
        if os.path.exists(repo_file):
            os.remove(repo_file)

    def seed_repo_file(self, options, repo_name='foo'):
        with open(self._repo_file(repo_name), 'w') as handle:
            handle.write('[{}]\n'.format(repo_name))
            for key, value in options.items():
                handle.write('{} = {}\n'.format(key, value))

    def _cachedir(self):
        return os.path.join(self.runtime_root, 'cache')

    def _repodir(self):
        return os.path.join(self.config['repo_path'], 'yum.repos.d')

    def _repo_file(self, repo_name='foo'):
        return os.path.join(self._repodir(), repo_name + '.repo')

    def _write_rpmz_config(self):
        config_path = os.path.join(self.config['repo_path'], 'rpmz.conf')
        with open(config_path, 'w') as handle:
            handle.write('[main]\n')
            handle.write('gpgcheck=0\n')
            handle.write('installonly_limit=3\n')
            handle.write('clean_requirements_on_remove=true\n')
            handle.write('repodir={}\n'.format(self._repodir()))
            handle.write('cachedir={}\n'.format(self._cachedir()))


def _get_repo_config_action(argv):
    index = 0
    while index < len(argv):
        token = argv[index]
        if token in {'-c', '--config', '-f', '--file'}:
            index += 2
            continue
        if token == '-j':
            index += 1
            continue
        if token.startswith('-'):
            index += 1
            continue
        return token
    return None
