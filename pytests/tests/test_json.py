#
# Copyright (C) 2022 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.
#

import pytest
import json
import os


PKGNAME_VERBOSE_SCRIPTS = "tdnf-verbose-scripts"


@pytest.fixture(scope='function', autouse=True)
def setup_test(utils):
    rpmzj = os.path.join(utils.config['bin_dir'], 'rpmzj')
    if not os.path.lexists(rpmzj):
        os.symlink('rpmz', rpmzj)
    yield
    teardown_test(utils)


def teardown_test(utils):
    pkgname = utils.config["mulversion_pkgname"]
    utils.erase_package(pkgname)


def test_list(utils):
    ret = utils.run(['rpmz', '-j', 'list'])
    infolist = json.loads("\n".join(ret['stdout']))

    glibc_found = False
    for info in infolist:
        if info['Name'] == "glibc":
            glibc_found = True
            break
    assert glibc_found


def test_list_rpmzj(utils):
    rpmzj = os.path.join(utils.config['bin_dir'], 'rpmzj')
    ret = utils.run([rpmzj, '-c', os.path.join(utils.config['repo_path'], 'rpmz.conf'), 'list'])
    infolist = json.loads("\n".join(ret['stdout']))

    glibc_found = False
    for info in infolist:
        if info['Name'] == "glibc":
            glibc_found = True
            break
    assert glibc_found


def test_info(utils):
    ret = utils.run(['rpmz', '-j', 'info'])
    infolist = json.loads("\n".join(ret['stdout']))

    glibc_found = False
    for info in infolist:
        if info['Name'] == "glibc":
            glibc_found = True
            break
    assert glibc_found


def test_install(utils):
    pkgname = utils.config["mulversion_pkgname"]
    utils.erase_package(pkgname)
    ret = utils.run(['rpmz',
                     '-j', '-y', '--nogpgcheck',
                     'install', pkgname])
    assert utils.check_package(pkgname)
    install_info = json.loads("\n".join(ret['stdout']))

    pkg_found = False
    install_pkgs = install_info["Install"]
    for p in install_pkgs:
        if p['Name'] == pkgname:
            pkg_found = True
            break
    assert pkg_found


def test_erase(utils):
    pkgname = utils.config["mulversion_pkgname"]
    utils.install_package(pkgname)
    ret = utils.run(['rpmz',
                     '-j', '-y', '--nogpgcheck',
                     'erase', pkgname])
    assert not utils.check_package(pkgname)
    install_info = json.loads("\n".join(ret['stdout']))

    pkg_found = False
    install_pkgs = install_info["Remove"]
    for p in install_pkgs:
        if p['Name'] == pkgname:
            pkg_found = True
            break
    assert pkg_found


# verbose rpm scriplets should not interfer with json output
def test_install_verbose(utils):
    pkgname = PKGNAME_VERBOSE_SCRIPTS
    utils.erase_package(pkgname)
    ret = utils.run(['rpmz',
                     '-j', '-y', '--nogpgcheck',
                     'install', pkgname])
    assert utils.check_package(pkgname)
    install_info = json.loads("\n".join(ret['stdout']))

    pkg_found = False
    install_pkgs = install_info["Install"]
    for p in install_pkgs:
        if p['Name'] == pkgname:
            pkg_found = True
            break
    assert pkg_found


def test_erase_verbose(utils):
    pkgname = PKGNAME_VERBOSE_SCRIPTS
    utils.install_package(pkgname)
    ret = utils.run(['rpmz',
                     '-j', '-y', '--nogpgcheck',
                     'erase', pkgname])
    assert not utils.check_package(pkgname)
    install_info = json.loads("\n".join(ret['stdout']))

    pkg_found = False
    install_pkgs = install_info["Remove"]
    for p in install_pkgs:
        if p['Name'] == pkgname:
            pkg_found = True
            break
    assert pkg_found


def test_check_update(utils):
    ret = utils.run(['rpmz', '-j', 'check-update'])
    d = json.loads("\n".join(ret['stdout']))
    assert type(d) is list


def test_repolist(utils):
    ret = utils.run(['rpmz', '-j', 'repolist'])
    repolist = json.loads("\n".join(ret['stdout']))

    repo_found = False
    for repo in repolist:
        if repo['Repo'] == 'photon-test':
            repo_found = True
            assert repo['Enabled']
            break
    assert repo_found


def test_repoquery(utils):
    ret = utils.run(['rpmz', '-j', 'repoquery'])
    d = json.loads("\n".join(ret['stdout']))
    assert type(d) is list


def test_updateinfo(utils):
    ret = utils.run(['rpmz', '-j', 'updateinfo'])
    d = json.loads("\n".join(ret['stdout']))
    assert type(d) is dict


def test_updateinfo_info(utils):
    ret = utils.run(['rpmz', '-j', 'updateinfo', '--info'])
    d = json.loads("\n".join(ret['stdout']))
    assert type(d) is list


def test_history_info(utils):
    ret = utils.run(['rpmz', '-j', 'history', '--info'])
    d = json.loads("\n".join(ret['stdout']))
    assert type(d) is list
