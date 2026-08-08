#
# Copyright (C) 2019 - 2022 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2 (the "License");
# you may not use this file except in compliance with the License. The terms
# of the License are located in the COPYING file of this distribution.

import os
import socket
import ssl
import time
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, HTTPServer
from multiprocessing import Process, Value

import pytest

from conftest import (
    StopTestRepoServer,
    TestRepoServer,
    write_self_signed_https_material,
)

DIST = os.environ.get('DIST')
if DIST == 'fedora':
    DEFAULT_KEY = 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-rawhide-primary'
else:
    DEFAULT_KEY = 'file:///etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY-4096'

original_gpg_keys = []


def get_host_gpg_keys(utils):
    host_gpg_keys = []
    ret = utils._run("rpm -qa 'gpg-pubkey*'")
    if ret['retval'] == 0:
        host_gpg_keys = ret['stdout']

    return host_gpg_keys


def get_new_gpg_keys(current_gpg_keys, baseline_gpg_keys):
    return [k for k in set(current_gpg_keys) - set(baseline_gpg_keys) if not any(
        k.split('-')[2].endswith(orig.split('-')[2]) or orig.split('-')[2].endswith(k.split('-')[2])
        for orig in baseline_gpg_keys)]


@pytest.fixture(scope='function', autouse=True)
def setup_test_function(utils):
    global original_gpg_keys
    if not original_gpg_keys:
        original_gpg_keys = get_host_gpg_keys(utils)

    new_gpg_key = get_new_gpg_keys(get_host_gpg_keys(utils), original_gpg_keys)
    for key in new_gpg_key:
        ret = utils._run(f"rpm -ev {key}")
        assert ret['retval'] == 0

    pkgname = utils.config["sglversion_pkgname"]
    utils.run(['tdnf', 'erase', '-y', pkgname])
    yield
    teardown_test(utils)


def teardown_test(utils):
    set_gpgcheck(utils, False)
    set_gpgcheck(utils, False, None)

    new_gpg_key = get_new_gpg_keys(get_host_gpg_keys(utils), original_gpg_keys)
    for key in new_gpg_key:
        ret = utils._run(f"rpm -ev {key}")
        assert ret['retval'] == 0

    pkgname = utils.config["sglversion_pkgname"]
    utils.run(['tdnf', 'erase', '-y', pkgname])


def set_gpgcheck(utils, enabled, repo='photon-test'):
    if enabled is not None:
        utils.edit_config({'gpgcheck': '1' if enabled else '0'}, repo)
    else:
        utils.edit_config({'gpgcheck': None}, repo)


def set_repo_key(utils, url):
    utils.edit_config({'gpgkey': url}, repo='photon-test')


@contextmanager
def https_key_server(utils):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]

    workdir = os.path.join(utils.config['build_dir'], 'signature-https')
    os.makedirs(workdir, exist_ok=True)
    certfile = os.path.join(workdir, 'cert.pem')
    keyfile = os.path.join(workdir, 'key.pem')
    server = Process(
        target=TestRepoServer,
        args=(utils.config['repo_path'],),
        kwargs={
            'port': port,
            'enable_https': True,
            'certfile': certfile,
            'keyfile': keyfile,
        },
    )
    server.start()
    deadline = time.time() + 10
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            if probe.connect_ex(('127.0.0.1', port)) == 0:
                break
        time.sleep(0.1)
    else:
        StopTestRepoServer(server)
        raise AssertionError('HTTPS key server failed to start')

    try:
        utils.edit_config({'sslcacert': certfile}, repo='photon-test')
        yield f'https://localhost:{port}'
    finally:
        StopTestRepoServer(server)


def _redirect_https_server(port, certfile, keyfile, location, requests):
    class RedirectHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            with requests.get_lock():
                requests.value += 1
            self.send_response(302)
            self.send_header('Location', location)
            self.end_headers()

        def log_message(self, _format, *_args):
            pass

    server = HTTPServer(('127.0.0.1', port), RedirectHandler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=certfile, keyfile=keyfile)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


def _counting_https_key_server(port, certfile, keyfile, key_data, requests):
    class KeyHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            with requests.get_lock():
                requests.value += 1
            self.send_response(200)
            self.send_header('Content-Length', str(len(key_data)))
            self.end_headers()
            self.wfile.write(key_data)

        def log_message(self, _format, *_args):
            pass

    server = HTTPServer(('127.0.0.1', port), KeyHandler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=certfile, keyfile=keyfile)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


def _unused_local_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def _wait_for_server(port):
    deadline = time.time() + 10
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            if probe.connect_ex(('127.0.0.1', port)) == 0:
                return
        time.sleep(0.1)
    raise AssertionError(f'HTTPS server on port {port} failed to start')


@contextmanager
def cross_origin_key_servers(utils):
    workdir = os.path.join(utils.config['build_dir'], 'signature-redirect')
    os.makedirs(workdir, exist_ok=True)
    certfile = os.path.join(workdir, 'cert.pem')
    keyfile = os.path.join(workdir, 'key.pem')
    write_self_signed_https_material(certfile, keyfile)

    with open(
            os.path.join(
                utils.config['repo_path'],
                'photon-test',
                'keys',
                'pubkey.asc',
            ),
            'rb') as key:
        key_data = key.read()

    origin_port = _unused_local_port()
    target_port = _unused_local_port()
    origin_requests = Value('i', 0)
    target_requests = Value('i', 0)
    target = Process(
        target=_counting_https_key_server,
        args=(
            target_port,
            certfile,
            keyfile,
            key_data,
            target_requests,
        ),
    )
    origin = Process(
        target=_redirect_https_server,
        args=(
            origin_port,
            certfile,
            keyfile,
            f'https://localhost:{target_port}/replaced-key.asc',
            origin_requests,
        ),
    )
    target.start()
    origin.start()
    try:
        _wait_for_server(target_port)
        _wait_for_server(origin_port)
        utils.edit_config({'sslcacert': certfile}, repo='photon-test')
        yield (
            f'https://localhost:{origin_port}',
            origin_requests,
            target_requests,
        )
    finally:
        StopTestRepoServer(origin)
        StopTestRepoServer(target)


# install unsigned package with gpgcheck enabled in repo,
# expect failure
def test_install_unsigned(utils):
    set_gpgcheck(utils, None, repo=None)
    set_gpgcheck(utils, True, repo='photon-test-unsigned')
    set_repo_key(utils, DEFAULT_KEY)
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', '--repoid', 'photon-test-unsigned', 'install', '-y', pkgname])
    assert ret['retval'] == 1531
    assert not utils.check_package(pkgname)


# install unsigned package with gpgcheck enabled in global config,
# expect failure
def test_install_unsigned_global_gpgcheck(utils):
    set_gpgcheck(utils, True, repo=None)
    set_gpgcheck(utils, None, repo='photon-test-unsigned')
    set_repo_key(utils, DEFAULT_KEY)
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', '--repoid', 'photon-test-unsigned', 'install', '-y', pkgname])
    assert ret['retval'] == 1531
    assert not utils.check_package(pkgname)


# install unsigned package with gpgcheck enabled in repo,
# but disabled on command line,
# expect success
def test_install_unsigned_nogpgcheck(utils):
    set_gpgcheck(utils, True, repo='photon-test-unsigned')
    set_repo_key(utils, DEFAULT_KEY)
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', '--nogpgcheck', '--repoid', 'photon-test-unsigned', 'install', '-y', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# install unsigned package with gpgcheck enabled in repo,
# but skipsignature on command line,
# expect success
def test_install_unsigned_skipsignature(utils):
    set_gpgcheck(utils, True, repo='photon-test-unsigned')
    set_repo_key(utils, DEFAULT_KEY)
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', '--skipsignature', '--repoid', 'photon-test-unsigned', 'install', '-y', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# 'wrong' key in repo config, but skip signature, expect success
def test_install_skipsignature(utils):
    set_gpgcheck(utils, True)
    set_repo_key(utils, DEFAULT_KEY)
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', 'install', '-y', '--skipsignature', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


def test_install_skipdigest(utils):
    set_gpgcheck(utils, True)
    keypath = os.path.join(utils.config['repo_path'], 'photon-test', 'keys', 'pubkey.asc')
    utils.run(['rpm', '--import', keypath])
    set_repo_key(utils, DEFAULT_KEY)
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', 'install', '-y', '--skipdigest', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# import key prior to install, expect success
def test_install_with_key(utils):
    set_gpgcheck(utils, True)
    keypath = os.path.join(utils.config['repo_path'], 'photon-test', 'keys', 'pubkey.asc')
    set_repo_key(utils, DEFAULT_KEY)
    utils.run(['rpm', '--import', keypath])
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', 'install', '-y', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# import local, correct key during install from repo config, expect success
def test_install_local_key(utils):
    set_gpgcheck(utils, True)
    keypath = os.path.join(utils.config['repo_path'], 'photon-test', 'keys', 'pubkey.asc')
    set_repo_key(utils, 'file://{}'.format(keypath))
    host_gpg_keys = get_host_gpg_keys(utils)
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', 'install', '-y', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)
    assert get_new_gpg_keys(get_host_gpg_keys(utils), host_gpg_keys)


def test_install_imports_all_configured_keys_before_verifying(utils):
    set_gpgcheck(utils, True)
    keydir = os.path.join(utils.config['repo_path'], 'photon-test', 'keys')
    correct_key = os.path.join(keydir, 'pubkey.asc')
    wrong_key = os.path.join(keydir, 'pubkey.wrong.asc')
    set_repo_key(utils, 'file://{} file://{}'.format(wrong_key, correct_key))
    host_gpg_keys = get_host_gpg_keys(utils)
    pkgname = utils.config["sglversion_pkgname"]

    ret = utils.run(['tdnf', 'install', '-y', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)
    assert len(get_new_gpg_keys(get_host_gpg_keys(utils), host_gpg_keys)) >= 2


def test_install_rejects_malformed_repo_keyring(utils):
    set_gpgcheck(utils, True)
    keypath = os.path.join(
        utils.config['repo_path'], 'photon-test', 'keys', 'malformed.asc')
    with open(keypath, 'w') as keyfile:
        keyfile.write('not an OpenPGP public key\n')

    try:
        set_repo_key(utils, 'file://{}'.format(keypath))
        pkgname = utils.config["sglversion_pkgname"]
        ret = utils.run(['tdnf', 'install', '-y', pkgname])
        assert ret['retval'] == 1505
        assert not utils.check_package(pkgname)
    finally:
        if os.path.exists(keypath):
            os.remove(keypath)


# import remote, correct key during install from repo config, expect success
def test_install_remote_key(utils):
    set_gpgcheck(utils, True)
    with https_key_server(utils) as origin:
        set_repo_key(utils, f'{origin}/photon-test/keys/pubkey.asc')
        pkgname = utils.config["sglversion_pkgname"]
        ret = utils.run(['tdnf', 'install', '-y', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


def test_install_http_key_rejected_before_prompt_fetch_or_import(utils):
    set_gpgcheck(utils, True)
    set_repo_key(utils, 'http://127.0.0.1:9/replaced-key.asc')
    host_gpg_keys = get_host_gpg_keys(utils)
    pkgname = utils.config["sglversion_pkgname"]

    ret = utils.run(['tdnf', 'install', '-y', pkgname])

    assert ret['retval'] == 1507
    output = '\n'.join(ret['stdout'] + ret['stderr'])
    assert 'Is this ok [y/N]:' not in output
    assert get_new_gpg_keys(get_host_gpg_keys(utils), host_gpg_keys) == []
    assert not utils.check_package(pkgname)


def test_install_cross_origin_key_redirect_rejected_before_prompt_or_import(
        utils):
    set_gpgcheck(utils, True)
    host_gpg_keys = get_host_gpg_keys(utils)
    pkgname = utils.config["sglversion_pkgname"]

    with cross_origin_key_servers(utils) as (
            origin,
            origin_requests,
            target_requests):
        set_repo_key(utils, f'{origin}/repository-key.asc')
        ret = utils.run(['tdnf', 'install', '-y', pkgname])

        assert origin_requests.value == 1
        assert target_requests.value == 0

    assert ret['retval'] == 1507
    output = '\n'.join(ret['stdout'] + ret['stderr'])
    assert 'Is this ok [y/N]:' not in output
    assert get_new_gpg_keys(get_host_gpg_keys(utils), host_gpg_keys) == []
    assert not utils.check_package(pkgname)


# -v (verbose) prints progress data
def test_install_remote_key_verbose(utils):
    set_gpgcheck(utils, True)
    with https_key_server(utils) as origin:
        set_repo_key(utils, f'{origin}/photon-test/keys/pubkey.asc')
        pkgname = utils.config["sglversion_pkgname"]
        ret = utils.run(['tdnf', 'install', '-v', '-y', pkgname])
    assert ret['retval'] == 0
    assert utils.check_package(pkgname)


# import remote key with url containing a directory traversal, expect fail
def test_install_remote_key_no_traversal(utils):
    set_gpgcheck(utils, True)
    with https_key_server(utils) as origin:
        set_repo_key(utils, f'{origin}/../photon-test/keys/pubkey.asc')
        pkgname = utils.config["sglversion_pkgname"]
        ret = utils.run(['tdnf', 'install', '-y', pkgname])
    assert ret['retval'] != 0


# import remote key with url containing a directory traversal, expect fail
def test_install_remote_key_no_traversal2(utils):
    set_gpgcheck(utils, True)
    with https_key_server(utils) as origin:
        set_repo_key(
            utils,
            f'{origin}/photon-test/keys/../../../pubkey.asc',
        )
        pkgname = utils.config["sglversion_pkgname"]
        ret = utils.run(['tdnf', 'install', '-y', pkgname])
    assert ret['retval'] != 0


# test with gpgcheck enabled but no key entry, expect fail
def test_install_nokey(utils):
    set_gpgcheck(utils, True)
    set_repo_key(utils, None)
    pkgname = utils.config["sglversion_pkgname"]
    ret = utils.run(['tdnf', 'install', '-y', pkgname])
    assert ret['retval'] == 1523
    assert not utils.check_package(pkgname)


# 'wrong' key in repo config, expect fail
def test_install_nokey1(utils):
    set_gpgcheck(utils, True)
    keypath = os.path.join(utils.config['repo_path'], 'photon-test', 'keys', 'pubkey.wrong.asc')
    set_repo_key(utils, f"file://{keypath}")
    pkgname = utils.config["sglversion_pkgname"]
    utils.run(['rpm', '--import', keypath])
    ret = utils.run(['tdnf', 'install', '-y', pkgname])
    assert ret['retval'] == 1514
    assert not utils.check_package(pkgname)
