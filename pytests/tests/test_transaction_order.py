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
import platform
import shutil
import sqlite3
import subprocess

import pytest

HELPER = 'tdnf-native-order-helper'
PRE = 'tdnf-native-order-pre'
POST = 'tdnf-native-order-post'
PREUN = 'tdnf-native-order-preun'
POSTUN = 'tdnf-native-order-postun'
SHELL_PROVIDER = 'tdnf-native-shell-provider'
PRETRANS_ONE = 'tdnf-test-pretrans-one'
PRETRANS_TWO = 'tdnf-test-pretrans-two'
PRETRANS_PROVIDER = 'tdnf-dummy-pretrans'
CONFLICT_FILE0 = 'tdnf-conflict-file0'
CONFLICT_FILE1 = 'tdnf-conflict-file1'
DUMMY_CONFLICT0 = 'tdnf-test-dummy-conflicts-0'
DUMMY_CONFLICT1 = 'tdnf-test-dummy-conflicts-1'
DUMMY_REQUIRES = 'tdnf-test-dummy-requires'
OBSOLETED = 'tdnf-test-dummy-obsoleted'
OBSOLETING = 'tdnf-test-dummy-obsoleting'
MULTIVERSION = 'tdnf-test-multiversion'
MULTIVERSION_LOWER = 'tdnf-test-multiversion@1.0.1-1'
MULTIVERSION_HIGHER = 'tdnf-test-multiversion@1.0.2-1'

OP_INSTALL = 1
OP_REINSTALL = 2
OP_ERASE = 3
OP_UPGRADE = 4

PROBLEM_DEPENDENCY = 1
PROBLEM_PRETRANS = 2
PROBLEM_CONFLICT = 3
PROBLEM_OBSOLETES = 4
PROBLEM_FILE_CONFLICT = 5
PROBLEM_UNSUPPORTED_MULTIPLE = 6


@pytest.fixture(scope='module', autouse=True)
def check_packages_consistency():
    yield


class NativeTransactionSolver(object):
    def __init__(self, support_binary):
        self.support_binary = support_binary

    def solve(self, root, items):
        result = self._run('transaction-v2', root, items)
        return result['order'], result['problems'], result['priors']

    def solve_legacy(self, root, items):
        result = self._run('transaction-legacy', root, items)
        return result['order'], result['problems']

    def _run(self, mode, root, items):
        completed = run_cmd([
            self.support_binary,
            mode,
            root,
            json.dumps(items),
        ])
        result = json.loads(completed.stdout)
        if result['rc'] != 0:
            pytest.fail(
                'native transaction solve failed: '
                f"rc={result['rc']} err={result.get('error')}"
            )
        return result


def run_cmd(cmd):
    return subprocess.run(
        cmd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def load_config():
    with open(os.path.join(os.path.dirname(__file__), '..', 'config.json')) as fp:
        return json.load(fp)


def ensure_repo(repo_path, specs_dir):
    if os.path.isdir(repo_path):
        shutil.rmtree(repo_path)
    run_cmd(['bash', os.path.join(specs_dir, 'setup-repo.sh'), repo_path, specs_dir])


def find_rpm(repo_path, name):
    matches = glob.glob(os.path.join(repo_path, 'photon-test', 'RPMS', '*', f'{name}-*.rpm'))
    assert len(matches) == 1, f'expected one RPM for {name}, found {matches}'
    return matches[0]


def find_rpm_with_evr(repo_path, name, evr):
    matches = glob.glob(os.path.join(repo_path, 'photon-test', 'RPMS', '*', f'{name}-{evr}.*.rpm'))
    assert len(matches) == 1, f'expected one RPM for {name}-{evr}, found {matches}'
    return matches[0]


def query_nevra(rpm_path):
    result = run_cmd([
        'rpm',
        '-qp',
        '--queryformat',
        '%{NAME}\n%{VERSION}-%{RELEASE}\n%{ARCH}\n',
        rpm_path,
    ])
    name, evr, arch = result.stdout.strip().splitlines()
    return {
        'name': name,
        'evr': evr,
        'arch': arch,
    }


def nevra_text(meta):
    return f"{meta['name']}-{meta['evr']}.{meta['arch']}"


def init_local_root(work_dir):
    root = os.path.join(work_dir, 'root')
    dbpath = os.path.join(root, 'var', 'lib', 'rpm')
    os.makedirs(dbpath, exist_ok=True)
    run_cmd(['rpm', '--dbpath', dbpath, '--initdb'])
    return root, dbpath


def rpmdb_install(dbpath, rpm_paths):
    run_cmd([
        'rpm',
        '--dbpath', dbpath,
        '-ivh',
        '--justdb',
        '--nodeps',
        '--noscripts',
        *rpm_paths,
    ])


def rpmdb_hnums(root, name):
    db_path = os.path.join(root, 'var', 'lib', 'rpm', 'rpmdb.sqlite')
    with sqlite3.connect(db_path) as db:
        return [
            row[0]
            for row in db.execute(
                'SELECT hnum FROM Name WHERE key=? ORDER BY hnum',
                (name,),
            )
        ]


def native_rpmdb_install(build_dir, root, rpm_path):
    run_cmd([
        os.path.join(build_dir, 'libexec', 'tdnf', 'tdnf-rpmdb-write'),
        'install',
        root,
        rpm_path,
    ])


def build_multilib_rpms(work_dir, name, version):
    build_dir = os.path.join(work_dir, 'multilib-' + version)
    shutil.rmtree(build_dir, ignore_errors=True)
    for directory in ['BUILD', 'BUILDROOT', 'RPMS', 'SRPMS',
                      'SOURCES', 'SPECS']:
        os.makedirs(os.path.join(build_dir, directory))
    spec_path = os.path.join(build_dir, 'SPECS', name + '.spec')
    with open(spec_path, 'w', encoding='utf-8') as spec:
        spec.write(
            'Name: {0}\n'
            'Version: {1}\n'
            'Release: 1\n'
            'Summary: Phase 7 multilib prior fixture\n'
            'License: MIT\n'
            '\n'
            '%description\n'
            'Phase 7 multilib prior fixture.\n'
            '\n'
            '%files\n'.format(name, version)
        )
    rpms = {}
    for arch in [platform.machine(), 'noarch']:
        run_cmd([
            'rpmbuild',
            '-D', '_topdir ' + build_dir,
            '--target', arch,
            '-bb', spec_path,
        ])
        rpms[arch] = os.path.join(
            build_dir,
            'RPMS',
            arch,
            '{}-{}-1.{}.rpm'.format(name, version, arch),
        )
    return rpms


def rpmdb_hnums_by_arch(root, name):
    dbpath = os.path.join(root, 'var', 'lib', 'rpm')
    result = run_cmd([
        'rpm',
        '--dbpath', dbpath,
        '-q',
        '--qf', '%{ARCH} %{DBINSTANCE}\n',
        name,
    ])
    return {
        arch: int(hnum)
        for arch, hnum in (
            line.split() for line in result.stdout.splitlines()
        )
    }


def build_install_items(*rpm_paths):
    return [{'op': OP_INSTALL, 'path': rpm_path} for rpm_path in rpm_paths]


def build_erase_items(rpm_meta):
    return [{
        'op': OP_ERASE,
        'name': meta['name'],
        'evr': meta['evr'],
        'arch': meta['arch'],
    } for meta in rpm_meta]


@pytest.fixture(scope='module')
def native_ctx():
    config = load_config()
    repo_path = os.path.join(config['build_dir'], 'native-transaction-test-repo')
    specs_dir = config['specs_dir']
    ensure_repo(repo_path, specs_dir)

    packages = {
        name: find_rpm(repo_path, name)
        for name in (
            HELPER,
            PRE,
            POST,
            PREUN,
            POSTUN,
            SHELL_PROVIDER,
            PRETRANS_ONE,
            PRETRANS_TWO,
            PRETRANS_PROVIDER,
            CONFLICT_FILE0,
            CONFLICT_FILE1,
            DUMMY_CONFLICT0,
            DUMMY_CONFLICT1,
            DUMMY_REQUIRES,
            OBSOLETED,
            OBSOLETING,
        )
    }
    packages[MULTIVERSION_LOWER] = find_rpm_with_evr(repo_path, MULTIVERSION, config['mulversion_lower'])
    packages[MULTIVERSION_HIGHER] = find_rpm_with_evr(repo_path, MULTIVERSION, config['mulversion_higher'])
    package_meta = {
        name: query_nevra(path)
        for name, path in packages.items()
    }
    work_dir = os.path.join(config['build_dir'], 'native-transaction-work')
    if os.path.isdir(work_dir):
        shutil.rmtree(work_dir)
    os.makedirs(work_dir)

    yield {
        'packages': packages,
        'package_meta': package_meta,
        'solver': NativeTransactionSolver(config['test_support_binary']),
        'work_dir': work_dir,
    }

    shutil.rmtree(repo_path, ignore_errors=True)
    shutil.rmtree(work_dir, ignore_errors=True)


def create_root(native_ctx, name, installed_packages):
    root_dir = os.path.join(native_ctx['work_dir'], name)
    if os.path.isdir(root_dir):
        shutil.rmtree(root_dir)
    os.makedirs(root_dir)
    root, dbpath = init_local_root(root_dir)
    if installed_packages:
        rpmdb_install(dbpath, [native_ctx['packages'][pkg] for pkg in installed_packages])
    return root


def order_names(order, names):
    return [names[index] for index in order]


def test_legacy_solver_consumes_old_stride_arrays(native_ctx):
    root = create_root(native_ctx, 'legacy-item-stride', [SHELL_PROVIDER])
    items = build_install_items(
        native_ctx['packages'][PRE],
        native_ctx['packages'][HELPER],
    )

    order, problems = native_ctx['solver'].solve_legacy(root, items)

    assert order == [1, 0]
    assert problems == []


def test_install_requires_pre_post_ordering(native_ctx):
    root = create_root(native_ctx, 'install-order', [SHELL_PROVIDER])
    items = build_install_items(
        native_ctx['packages'][POST],
        native_ctx['packages'][PRE],
        native_ctx['packages'][HELPER],
    )
    order, problems, priors = native_ctx['solver'].solve(root, items)
    assert problems == []
    assert priors == [[], [], []]

    ordered = order_names(order, [POST, PRE, HELPER])
    assert ordered.index(HELPER) < ordered.index(PRE)
    assert ordered.index(HELPER) < ordered.index(POST)


def test_erase_requires_preun_postun_ordering(native_ctx):
    root = create_root(native_ctx, 'erase-order', [SHELL_PROVIDER, HELPER, PREUN, POSTUN])
    items = build_erase_items([
        native_ctx['package_meta'][HELPER],
        native_ctx['package_meta'][PREUN],
        native_ctx['package_meta'][POSTUN],
    ])
    order, problems, priors = native_ctx['solver'].solve(root, items)
    assert problems == []
    assert priors == [[], [], []]

    ordered = order_names(order, [HELPER, PREUN, POSTUN])
    assert ordered.index(PREUN) < ordered.index(HELPER)
    assert ordered.index(POSTUN) < ordered.index(HELPER)


@pytest.mark.parametrize(
    'package_name, expected_requirement',
    [
        (PRETRANS_ONE, 'tdnf-dummy-pretrans >= 1.0-1'),
        (PRETRANS_TWO, 'tdnf-dummy-pretrans < 1.0-2'),
    ],
)
def test_pretrans_requires_missing_problem_has_guidance(native_ctx, package_name, expected_requirement):
    root = create_root(native_ctx, f'pretrans-missing-{package_name}', [SHELL_PROVIDER])
    order, problems, priors = native_ctx['solver'].solve(
        root,
        build_install_items(native_ctx['packages'][package_name]),
    )
    assert order == [0]
    assert priors == [[]]
    assert len(problems) == 1
    assert problems[0]['type'] == PROBLEM_PRETRANS
    assert problems[0]['subject'] == expected_requirement
    assert problems[0]['package'].startswith(package_name + '-')


@pytest.mark.parametrize('package_name', [PRETRANS_ONE, PRETRANS_TWO])
def test_pretrans_requires_satisfied_by_local_rpmdb(native_ctx, package_name):
    root = create_root(native_ctx, f'pretrans-satisfied-{package_name}', [SHELL_PROVIDER, PRETRANS_PROVIDER])
    order, problems, priors = native_ctx['solver'].solve(
        root,
        build_install_items(native_ctx['packages'][package_name]),
    )
    assert order == [0]
    assert problems == []
    assert priors == [[]]


def test_dependency_problem_is_typed(native_ctx):
    root = create_root(native_ctx, 'dependency-problem', [SHELL_PROVIDER])
    order, problems, priors = native_ctx['solver'].solve(
        root,
        build_install_items(native_ctx['packages'][DUMMY_REQUIRES]),
    )

    assert order == [0]
    assert priors == [[]]
    assert len(problems) == 1
    assert problems[0]['type'] == PROBLEM_DEPENDENCY
    assert problems[0]['subject'] == 'dummy-requirement'
    assert problems[0]['package'].startswith(DUMMY_REQUIRES + '-')


def test_file_conflict_atonce_detected(native_ctx):
    root = create_root(native_ctx, 'file-conflict-atonce', [SHELL_PROVIDER])
    order, problems, priors = native_ctx['solver'].solve(
        root,
        build_install_items(
            native_ctx['packages'][CONFLICT_FILE0],
            native_ctx['packages'][CONFLICT_FILE1],
        ),
    )
    assert order == [0, 1]
    assert priors == [[], []]
    assert problems == [{
        'type': PROBLEM_FILE_CONFLICT,
        'input': 0,
        'package': nevra_text(native_ctx['package_meta'][CONFLICT_FILE0]),
        'related': nevra_text(native_ctx['package_meta'][CONFLICT_FILE1]),
        'subject': '/usr/lib/conflict/conflicting-file',
        'count': 0,
    }]


def test_file_conflict_against_installed_rpmdb_detected(native_ctx):
    root = create_root(native_ctx, 'file-conflict-installed', [SHELL_PROVIDER, CONFLICT_FILE0])
    order, problems, priors = native_ctx['solver'].solve(
        root,
        build_install_items(native_ctx['packages'][CONFLICT_FILE1]),
    )
    assert order == [0]
    assert priors == [[]]
    assert problems == [{
        'type': PROBLEM_FILE_CONFLICT,
        'input': 0,
        'package': nevra_text(native_ctx['package_meta'][CONFLICT_FILE1]),
        'related': nevra_text(native_ctx['package_meta'][CONFLICT_FILE0]),
        'subject': '/usr/lib/conflict/conflicting-file',
        'count': 0,
    }]


@pytest.mark.parametrize(
    'packages, expected_type',
    [
        ((DUMMY_CONFLICT0, DUMMY_CONFLICT1), PROBLEM_CONFLICT),
        ((OBSOLETED, OBSOLETING), PROBLEM_OBSOLETES),
    ],
)
def test_relation_conflicts_and_obsoletes_detected(
        native_ctx, packages, expected_type):
    root = create_root(native_ctx, 'relation-problems-' + '-'.join(packages), [SHELL_PROVIDER])
    order, problems, priors = native_ctx['solver'].solve(
        root,
        build_install_items(*(native_ctx['packages'][name] for name in packages)),
    )
    assert order == [0, 1]
    assert priors == [[], []]
    assert len(problems) == 1
    assert problems[0]['type'] == expected_type
    assert problems[0]['related']


def test_upgrade_orders_install_before_erase_same_name(native_ctx):
    root = create_root(native_ctx, 'upgrade-order', [SHELL_PROVIDER, MULTIVERSION_LOWER])
    order, problems, priors = native_ctx['solver'].solve(
        root,
        build_install_items(native_ctx['packages'][MULTIVERSION_HIGHER]) +
        build_erase_items([native_ctx['package_meta'][MULTIVERSION_LOWER]]),
    )
    assert order == [0, 1]
    assert problems == []
    assert priors == [[], []]


def test_upgrade_plan_carries_exact_prior_hnum(native_ctx):
    root = create_root(
        native_ctx,
        'upgrade-exact-prior',
        [SHELL_PROVIDER, MULTIVERSION_LOWER],
    )
    expected = rpmdb_hnums(root, MULTIVERSION)
    assert len(expected) == 1

    order, problems, priors = native_ctx['solver'].solve(root, [{
        'op': OP_UPGRADE,
        'path': native_ctx['packages'][MULTIVERSION_HIGHER],
    }])

    assert order == [0]
    assert problems == []
    assert priors == [expected]


def test_upgrade_plan_rejects_same_arch_multiplicity(native_ctx):
    root = create_root(
        native_ctx,
        'upgrade-unsupported-multiplicity',
        [SHELL_PROVIDER, MULTIVERSION_LOWER, MULTIVERSION_HIGHER],
    )
    expected = rpmdb_hnums(root, MULTIVERSION)
    assert len(expected) == 2

    order, problems, priors = native_ctx['solver'].solve(root, [{
        'op': OP_UPGRADE,
        'path': native_ctx['packages'][MULTIVERSION_HIGHER],
    }])

    assert order == [0]
    assert priors == [expected]
    assert len(problems) == 1
    assert problems[0]['type'] == PROBLEM_UNSUPPORTED_MULTIPLE
    assert problems[0]['count'] == 2


def test_reinstall_plan_supports_duplicate_nevra_rows(native_ctx):
    root = create_root(native_ctx, 'reinstall-duplicate-nevra', [SHELL_PROVIDER])
    rpm_path = native_ctx['packages'][MULTIVERSION_LOWER]
    native_rpmdb_install(load_config()['build_dir'], root, rpm_path)
    native_rpmdb_install(load_config()['build_dir'], root, rpm_path)
    expected = rpmdb_hnums(root, MULTIVERSION)
    assert len(expected) == 2

    order, problems, priors = native_ctx['solver'].solve(root, [{
        'op': OP_REINSTALL,
        'path': rpm_path,
    }])

    assert order == [0]
    assert problems == []
    assert priors == [expected]


def test_multilib_upgrades_select_prior_from_matching_arch(native_ctx):
    name = 'tdnf-phase7-multilib-prior'
    v1 = build_multilib_rpms(native_ctx['work_dir'], name, '1.0')
    v2 = build_multilib_rpms(native_ctx['work_dir'], name, '2.0')
    root = create_root(native_ctx, 'multilib-exact-prior', [])
    for arch in [platform.machine(), 'noarch']:
        native_rpmdb_install(load_config()['build_dir'], root, v1[arch])
    expected = rpmdb_hnums_by_arch(root, name)

    items = [
        {'op': OP_UPGRADE, 'path': v2['noarch']},
        {'op': OP_UPGRADE, 'path': v2[platform.machine()]},
    ]
    order, problems, priors = native_ctx['solver'].solve(root, items)

    assert sorted(order) == [0, 1]
    assert problems == []
    assert priors == [
        [expected['noarch']],
        [expected[platform.machine()]],
    ]
