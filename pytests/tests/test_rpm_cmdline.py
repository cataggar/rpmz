#
# Copyright (C) 2020-2022 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.

import os
import glob
import pytest
import platform
import shutil

ARCH = platform.machine()


@pytest.fixture(scope='function', autouse=True)
def setup_test_function(utils):
    pkgname = utils.config["sglversion_pkgname"]
    utils.run(['rpmz', 'erase', '-y', pkgname])
    os.mkdir(os.path.join(utils.config['repo_path'], 'dummydir'))
    yield
    teardown_test(utils)


def teardown_test(utils):
    pkgname = utils.config["sglversion_pkgname"]
    utils.run(['rpmz', 'erase', '-y', pkgname])
    os.rmdir(os.path.join(utils.config['repo_path'], 'dummydir'))


def get_pkg_file_path(utils, pkgname):
    dir = os.path.join(utils.config['repo_path'], 'photon-test', 'RPMS', ARCH)
    matches = glob.glob('{}/{}-*.rpm'.format(dir, pkgname))
    return matches[0]


def get_pkg_file_path_with_doubledots(utils, pkgname):
    dir = os.path.join(utils.config['repo_path'], 'dummydir', '..', 'photon-test', 'RPMS', ARCH)
    matches = glob.glob('{}/{}-*.rpm'.format(dir, pkgname))
    return matches[0]


def get_pkg_remote_url(utils, pkgname):
    path = get_pkg_file_path(utils, pkgname)
    url = "http://localhost:8080/{}".format(path[len(utils.config['repo_path']) + 1:])
    return url


def get_pkg_remote_url_with_doubledots(utils, pkgname):
    path = get_pkg_file_path(utils, pkgname)
    url = "http://localhost:8080/dummydir/../{}".format(path[len(utils.config['repo_path']) + 1:])
    return url


# test something like "rpmz tdnf install /path/to/pkg.rpm"
def test_install_as_file(utils):
    pkgname = utils.config["sglversion_pkgname"]
    path = get_pkg_file_path(utils, pkgname)
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', path])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# test something like "rpmz tdnf install ../path/to/pkg.rpm" (relative path)
def test_install_as_file_relpath1(utils):
    pkgname = utils.config["sglversion_pkgname"]
    tmpdir = 'rpmtmp'
    path = get_pkg_file_path(utils, pkgname)
    filename = os.path.basename(path)
    if os.path.isdir(tmpdir):
        shutil.rmtree(tmpdir)
    os.makedirs(tmpdir, exist_ok=True)
    shutil.copy(path, tmpdir)
    relpath = os.path.join('..', tmpdir, filename)
    cwd = os.getcwd()
    os.chdir(tmpdir)
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', relpath])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)
    os.chdir(cwd)
    shutil.rmtree(tmpdir)


# test something like "rpmz tdnf install /somepath/../path/to/pkg.rpm"
def test_install_as_file_with_doubledots(utils):
    pkgname = utils.config["sglversion_pkgname"]
    path = get_pkg_file_path_with_doubledots(utils, pkgname)
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', path])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# test something like "rpmz tdnf install pkg.rpm"
def test_install_as_file_relpath2(utils):
    pkgname = utils.config["sglversion_pkgname"]
    path = os.path.relpath(get_pkg_file_path(utils, pkgname))
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', path])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# test something like "rpmz tdnf install file:///path/to/pkg.rpm"
def test_install_as_file_uri(utils):
    pkgname = utils.config["sglversion_pkgname"]
    path = get_pkg_file_path(utils, pkgname)
    uri = 'file://{}'.format(path)
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', uri])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# test something like "rpmz tdnf install http://server.com/path/to/pkg.rpm"
def test_install_remote(utils):
    pkgname = utils.config["sglversion_pkgname"]
    uri = get_pkg_remote_url(utils, pkgname)
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', uri])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# test something like "rpmz tdnf install http://server.com/otherpath/../path/to/pkg.rpm"
def test_install_remote_with_doubledots(utils):
    pkgname = utils.config["sglversion_pkgname"]
    uri = get_pkg_remote_url_with_doubledots(utils, pkgname)
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', uri])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# test something like "rpmz tdnf install http://server.com/path/to/pkg.rpm",
# but file doesn't exist, expect failure
def test_install_remote_notfound(utils):
    uri = 'http://localhost:8080/doesnotexist.rpm'
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', uri])
    assert ret['retval'] == 1622


# test something like "rpmz tdnf install /path/to/pkg.rpm otherpkg"
def test_install_as_mixed(utils):
    pkgname = utils.config["sglversion_pkgname"]
    pkgname2 = utils.config["sglversion2_pkgname"]
    path = get_pkg_file_path(utils, pkgname)
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', path, pkgname2])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)
    assert utils.check_package(pkgname2)
    ret = utils.run(f"rpmz remove -y {path} {pkgname2}")
    assert ret['retval'] == 0


# test installing a package that has the same name as a file
# example: touch foo; rpmz tdnf install foo
# (file needs to have "*.rpm" extension to qualify)
def test_install_same_as_filname(utils):
    pkgname = utils.config["sglversion_pkgname"]
    utils.run(['touch', pkgname])
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# test "rpmz tdnf reinstall /path/to/pkg.rpm". See PR #300.
def test_reinstall_as_file(utils):
    pkgname = utils.config["sglversion_pkgname"]
    path = get_pkg_file_path(utils, pkgname)

    # prepare by installing package
    ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck', path])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)

    # actual test
    ret = utils.run(['rpmz', 'reinstall', '-y', '--nogpgcheck', path])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)
    assert "Nothing to do" not in "\n".join(ret['stderr'])
    assert "Reinstalling" in "\n".join(ret['stdout'])


# test something like "rpmz tdnf install /path/to/pkg.rpm"
# with nocmdlinegpgcheck option
def test_install_as_file_nocmdlinegpgcheck(utils):
    pkgname = utils.config["sglversion_pkgname"]
    path = get_pkg_file_path(utils, pkgname)

    # make sure we will fail if option isn't set
    ret = utils.run(['rpmz', 'install', '-y', '--setopt=gpgcheck=1', path])
    assert ret['retval'] != 0
    assert not utils.check_package(pkgname)

    ret = utils.run(['rpmz', 'install', '-y', '--setopt=gpgcheck=1', '--nocligpgcheck', path])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# test something like "rpmz tdnf install /path/to/pkg.rpm"
# with gpgcheck set to 1, but cligpgcheck set to 0
def test_install_as_file_nocmdlinegpgcheck_conf(utils):
    pkgname = utils.config["sglversion_pkgname"]
    path = get_pkg_file_path(utils, pkgname)

    # make sure we will fail if option isn't set
    ret = utils.run(['rpmz', 'install', '-y', '--setopt=gpgcheck=1', path])
    assert ret['retval'] != 0
    assert not utils.check_package(pkgname)

    ret = utils.run(['rpmz', 'install', '-y', '--setopt=gpgcheck=1', '--setopt=cligpgcheck=0', path])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# Packages that are known to co-install cleanly, used to build a single
# transaction from many command line rpms at once.
MANY_FILE_PKGS = [
    'tdnf-dummy-pretrans',
    'tdnf-native-order-helper',
    'tdnf-native-order-post',
    'tdnf-native-order-postun',
    'tdnf-native-order-pre',
    'tdnf-native-order-preun',
    'tdnf-repoquery-changelog',
    'tdnf-repoquery-enhances',
    'tdnf-repoquery-recommends',
    'tdnf-repoquery-requires',
    'tdnf-repoquery-suggests',
    'tdnf-repoquery-supplements',
    'tdnf-test-cleanreq-leaf1',
    'tdnf-test-cleanreq-leaf2',
    'tdnf-test-cleanreq-required',
    'tdnf-test-doc',
    'tdnf-test-one',
    'tdnf-test-two',
    'tdnf-test3',
    'tdnf-test4',
]


# test "rpmz tdnf install a.rpm b.rpm ... " with many files in one transaction.
#
# This began as a regression test for a libsolv ring-buffer bug: the paths came
# from solvable_get_location(), which returns pool scratch memory
# (POOL_TMPSPACEBUF, 16 slots), so a borrowed 17th path recycled the slot the
# 1st still pointed at and the solve failed with PackageNotFound.
#
# That mechanism is gone -- the path of a command line rpm is now recorded when
# the file is added and never re-derived from the pool -- so what this pins is
# no longer the wraparound. It is that every one of many @cmdline packages in a
# single transaction gets its own correct path, which is what the recorder's
# grow-by-one array has to get right. The threshold below is kept as a fixed
# size rather than a claim about libsolv.
def test_install_many_files_at_once(utils):
    dir = os.path.join(utils.config['repo_path'], 'photon-test', 'RPMS', ARCH)
    paths = []
    for pkgname in MANY_FILE_PKGS:
        # sorted() so the file picked never depends on readdir order, which
        # differs between filesystems (tmpfs yields creation order, ext4 hash
        # order). The overall order is fixed by MANY_FILE_PKGS.
        matches = sorted(glob.glob('{}/{}-[0-9]*.rpm'.format(dir, pkgname)))
        if matches:
            paths.append(matches[0])

    # Guard against the test quietly becoming vacuous: with only a file or
    # two, a recorder that mixed up paths could still pass by luck.
    assert len(paths) > 16, \
        "need more than 16 rpm files to exercise many @cmdline paths at once"

    before = utils.list_installed_packages()
    try:
        ret = utils.run(['rpmz', 'install', '-y', '--nogpgcheck'] + paths)
        assert ret['retval'] == 0
        for pkgname in MANY_FILE_PKGS:
            if any(os.path.basename(p).startswith(pkgname + '-') for p in paths):
                assert utils.check_package(pkgname)
    finally:
        added = [p for p in utils.list_installed_packages() if p not in before]
        if added:
            utils.run(['rpmz', 'erase', '-y'] + added)
