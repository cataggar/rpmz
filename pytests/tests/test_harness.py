#
# Copyright (C) 2026 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.
#

import os

import conftest


def test_test_prefix_rewrites_private_helpers(monkeypatch):
    prefix = os.path.abspath('prefix-fixture')
    monkeypatch.setenv('RPMZ_TEST_PREFIX', prefix)
    monkeypatch.setattr(
        conftest,
        '_prepare_session_repo',
        lambda config: config['repo_path'],
    )
    monkeypatch.setattr(
        conftest.TestUtils,
        'check_valgrind',
        lambda self: None,
    )

    utils = conftest.TestUtils()

    assert utils.config['history_util_binary'] == os.path.join(
        prefix,
        'libexec',
        'rpmz',
        'rpmz-history-util',
    )
    assert utils.config['test_support_binary'] == os.path.join(
        prefix,
        'libexec',
        'rpmz',
        'rpmz-test-support',
    )
