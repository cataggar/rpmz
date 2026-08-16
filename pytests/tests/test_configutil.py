#
# Copyright (C) 2022-2023 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.
#
#   Author: Oliver Kurth <okurth@vmware.com>

import os
import configparser
import pytest
import json


def remove_repofile(utils, filename="foo.repo"):
    repofile = os.path.join(utils.config['repo_path'], "yum.repos.d", filename)
    if os.path.isfile(repofile):
        os.remove(repofile)


@pytest.fixture(scope='function', autouse=True)
def setup_test(utils):
    remove_repofile(utils)
    remove_repofile(utils, "test.repo")
    yield
    teardown_test(utils)


def teardown_test(utils):
    remove_repofile(utils)
    remove_repofile(utils, "test.repo")


def test_create(utils):
    ret = utils.run(['rpmz', 'repo-config', 'create', 'foo', 'name=Foo', 'baseurl=http://foo.bar.com', 'enabled=1'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'tdnf', 'repolist'])
    assert 'Foo' in "\n".join(ret['stdout'])


def test_fileoption(utils):
    test_repo = os.path.join(
        utils.config['repo_path'], "yum.repos.d", "test.repo",
    )

    ret = utils.run(['rpmz', 'repo-config', '-f', test_repo, 'create', 'foo', 'name=Foo', 'baseurl=http://foo.bar.com'])
    assert ret['retval'] == 0
    assert os.path.exists(test_repo)

    ret = utils.run(['rpmz', 'repo-config', '-f', test_repo, 'edit', 'foo', 'enabled=true'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'repo-config', '-f', test_repo, 'get', 'foo', 'enabled'])
    assert ret['retval'] == 0
    assert ret['stdout'][0].strip() == "true"

    ret = utils.run(['rpmz', 'repo-config', '-f', test_repo, '-j', 'dump', 'foo'])
    assert ret['retval'] == 0

    repomap = json.loads("\n".join(ret['stdout']))
    assert 'foo' in repomap
    assert 'enabled' in repomap['foo']
    assert repomap['foo']['enabled'] == "true"

    ret = utils.run(['rpmz', 'repo-config', '-f', test_repo, 'remove', 'foo', 'enabled'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'repo-config', '-f', test_repo, '-j', 'dump', 'foo'])
    assert ret['retval'] == 0

    repomap = json.loads("\n".join(ret['stdout']))
    assert 'foo' in repomap
    assert 'enabled' not in repomap['foo']

    ret = utils.run(['rpmz', 'repo-config', '-f', test_repo, 'removerepo', 'foo'])
    assert ret['retval'] == 0
    assert not os.path.exists(test_repo)


def test_edit(utils):
    ret = utils.run(['rpmz', 'repo-config', 'create', 'foo', 'name=Foo', 'baseurl=http://foo.bar.com', 'enabled=0'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'repo-config', 'edit', 'foo', 'enabled=1'])
    assert ret['retval'] == 0

    repo_config = configparser.ConfigParser()
    repo_config.read(os.path.join(utils.config['repo_path'], "yum.repos.d", "foo.repo"))

    value = repo_config.get('foo', 'enabled')
    assert value == '1'


def test_remove(utils):
    ret = utils.run(['rpmz', 'repo-config', 'create', 'foo', 'name=Foo', 'baseurl=http://foo.bar.com', 'gpgcheck=0'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'repo-config', 'remove', 'foo', 'gpgcheck'])
    assert ret['retval'] == 0

    repo_config = configparser.ConfigParser()
    repo_config.read(os.path.join(utils.config['repo_path'], "yum.repos.d", "foo.repo"))

    value = repo_config.get('foo', 'gpgcheck', fallback=None)
    assert value is None


def test_edit_multiple(utils):
    ret = utils.run(['rpmz', 'repo-config', 'create', 'foo', 'name=Foo', 'baseurl=http://foo.bar.com', 'enabled=0'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'repo-config', 'edit', 'foo', 'enabled=1', 'gpgcheck=0'])
    assert ret['retval'] == 0

    repo_config = configparser.ConfigParser()
    repo_config.read(os.path.join(utils.config['repo_path'], "yum.repos.d", "foo.repo"))

    value = repo_config.get('foo', 'enabled')
    assert value == '1'

    value = repo_config.get('foo', 'gpgcheck')
    assert value == '0'


def test_get(utils):
    ret = utils.run(['rpmz', 'repo-config', 'create', 'foo', 'name=Foo', 'baseurl=http://foo.bar.com', 'enabled=0'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'repo-config', 'get', 'foo', 'baseurl'])
    assert ret['retval'] == 0

    assert 'foo.bar.com' in "\n".join(ret['stdout'])


def test_removerepo(utils):
    ret = utils.run(['rpmz', 'repo-config', 'create', 'foo', 'name=Foo', 'baseurl=http://foo.bar.com', 'enabled=1'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'repo-config', 'removerepo', 'foo'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'tdnf', 'repolist'])
    assert 'Foo' not in "\n".join(ret['stdout'])


def test_json(utils):
    ret = utils.run(['rpmz', 'repo-config', 'create', 'foo', 'name=Foo', 'baseurl=http://foo.bar.com', 'enabled=0'])
    assert ret['retval'] == 0

    ret = utils.run(['rpmz', 'repo-config', '-j', 'dump', 'foo'])
    assert ret['retval'] == 0

    repomap = json.loads("\n".join(ret['stdout']))
    assert 'foo' in repomap
    assert 'enabled' in repomap['foo']
    assert repomap['foo']['enabled'] == '0'
