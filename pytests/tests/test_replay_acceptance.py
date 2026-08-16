#
# Copyright (C) 2026 VMware, Inc. All Rights Reserved.
#
# Licensed under the GNU General Public License v2.1.
#

import copy
import functools
import hashlib
import json
import os
import platform
import shutil
import socket
import threading
import time
import uuid
from collections import Counter
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import BaseRequestHandler, ThreadingTCPServer
from types import SimpleNamespace

import pytest


ARCH = platform.machine()
REQUIRED_TOOLS = ("createrepo_c", "rpmbuild")

pytestmark = pytest.mark.skipif(
    os.geteuid() != 0 or any(shutil.which(tool) is None for tool in REQUIRED_TOOLS),
    reason="replay acceptance needs root, rpmbuild, and createrepo_c",
)


class CountingServer:
    def __init__(self, root, port=0):
        self._count = 0
        self._lock = threading.Lock()
        owner = self

        class Handler(SimpleHTTPRequestHandler):
            def log_message(self, _format, *_args):
                pass

            def _record(self):
                with owner._lock:
                    owner._count += 1

            def do_GET(self):
                self._record()
                super().do_GET()

            def do_HEAD(self):
                self._record()
                super().do_HEAD()

        handler = functools.partial(Handler, directory=str(root))
        self._server = ThreadingHTTPServer(("127.0.0.1", port), handler)
        self.port = self._server.server_port
        self._thread = threading.Thread(
            target=self._server.serve_forever,
            name="tdnf-replay-acceptance-http",
            daemon=True,
        )
        self._thread.start()
        self._wait_until_listening()

    @property
    def count(self):
        with self._lock:
            return self._count

    def stop(self):
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=10)
        assert not self._thread.is_alive()

    def _wait_until_listening(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=5):
            pass


class ConnectionTrap:
    def __init__(self, port):
        self._connections = 0
        self._bytes = 0
        self._active = 0
        self._generation = 0
        self._condition = threading.Condition()
        owner = self

        class TrapServer(ThreadingTCPServer):
            allow_reuse_address = True
            daemon_threads = True

            def get_request(self):
                request, address = super().get_request()
                with owner._condition:
                    owner._connections += 1
                    owner._active += 1
                    owner._condition.notify_all()
                return request, address

            def service_actions(self):
                with owner._condition:
                    owner._generation += 1
                    owner._condition.notify_all()

        class Handler(BaseRequestHandler):
            def handle(self):
                received = 0
                try:
                    self.request.settimeout(0.1)
                    while True:
                        try:
                            data = self.request.recv(65536)
                        except socket.timeout:
                            break
                        if not data:
                            break
                        received += len(data)
                    try:
                        self.request.sendall(
                            b"HTTP/1.1 503 Offline Replay Trap\r\n"
                            b"Content-Length: 0\r\n"
                            b"Connection: close\r\n\r\n"
                        )
                    except OSError:
                        pass
                finally:
                    with owner._condition:
                        owner._bytes += received
                        owner._active -= 1
                        owner._condition.notify_all()

        self._server = TrapServer(("127.0.0.1", port), Handler)
        self.port = self._server.server_address[1]
        self._thread = threading.Thread(
            target=lambda: self._server.serve_forever(
                poll_interval=0.05,
            ),
            name="tdnf-replay-connection-trap",
            daemon=True,
        )
        self._thread.start()

    def snapshot(self):
        deadline = time.monotonic() + 2
        with self._condition:
            target_generation = self._generation + 2
            while (self._generation < target_generation or
                   self._active != 0):
                remaining = deadline - time.monotonic()
                assert remaining > 0
                self._condition.wait(remaining)
            return self._connections, self._bytes

    def stop(self):
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=10)
        assert not self._thread.is_alive()


def _write_invalid_rpmz_config(root):
    (root / "etc" / "rpmz").mkdir(parents=True)
    (root / "etc" / "rpmz" / "rpmz.conf").write_text(
        "this is intentionally not valid rpmz configuration\n",
        encoding="utf-8",
    )


def _lua_scriptlet(section, label):
    return """\
%{section} -p <lua>
local file = assert(io.open("/var/lib/tdnf-replay-order.log", "a"))
file:write("{label}\\n")
file:close()
""".format(section=section, label=label)


def _package_spec(
        name, version="1.0", extra="", pre="", post="", preun=""):
    payload = "{}-{}".format(name.replace("tdnf-", ""), version)
    return """\
Name: {name}
Version: {version}
Release: 1
Summary: replay acceptance fixture
License: MIT
BuildArch: noarch
{extra}
%description
Replay acceptance fixture.

%install
mkdir -p %{{buildroot}}/usr/share/tdnf-replay
echo {payload} > %{{buildroot}}/usr/share/tdnf-replay/{payload}

{pre}
{post}
{preun}
%files
/usr/share/tdnf-replay/{payload}
""".format(
        name=name,
        version=version,
        extra=extra,
        pre=pre,
        post=post,
        preun=preun,
        payload=payload,
    )


def _build_replay_packages(utils, workspace, repository):
    topdir = workspace / "rpmbuild"
    for directory in ("BUILD", "BUILDROOT", "RPMS", "SOURCES", "SPECS", "SRPMS"):
        (topdir / directory).mkdir(parents=True, exist_ok=True)

    specs = {
        "tdnf-replay-old": _package_spec(
            "tdnf-replay-old",
            preun=_lua_scriptlet("preun", "erase:tdnf-replay-old"),
        ),
        "tdnf-replay-retired": _package_spec(
            "tdnf-replay-retired",
            preun=_lua_scriptlet("preun", "erase:tdnf-replay-retired"),
        ),
        "tdnf-replay-replacement-a": _package_spec(
            "tdnf-replay-replacement-a",
            extra=(
                "Obsoletes: tdnf-replay-old\n"
                "Obsoletes: tdnf-replay-retired\n"
            ),
            post=_lua_scriptlet(
                "post", "install:tdnf-replay-replacement-a",
            ),
        ),
        "tdnf-replay-replacement-b": _package_spec(
            "tdnf-replay-replacement-b",
            extra="Obsoletes: tdnf-replay-old\n",
            post=_lua_scriptlet(
                "post", "install:tdnf-replay-replacement-b",
            ),
        ),
        "tdnf-replay-first": _package_spec("tdnf-replay-first"),
        "tdnf-replay-fail": _package_spec(
            "tdnf-replay-fail",
            extra="Requires: tdnf-replay-first\n",
            pre=(
                "%pre -p <lua>\n"
                'error("intentional replay acceptance failure")\n'
            ),
        ),
        "tdnf-replay-installonly-1": _package_spec(
            "tdnf-replay-installonly", version="1.0",
            post=_lua_scriptlet(
                "post", "install:tdnf-replay-installonly:1.0",
            ),
            preun=_lua_scriptlet(
                "preun", "erase:tdnf-replay-installonly:1.0",
            ),
        ),
        "tdnf-replay-installonly-2": _package_spec(
            "tdnf-replay-installonly", version="2.0",
            post=_lua_scriptlet(
                "post", "install:tdnf-replay-installonly:2.0",
            ),
            preun=_lua_scriptlet(
                "preun", "erase:tdnf-replay-installonly:2.0",
            ),
        ),
        "tdnf-replay-installonly-3": _package_spec(
            "tdnf-replay-installonly", version="3.0",
            post=_lua_scriptlet(
                "post", "install:tdnf-replay-installonly:3.0",
            ),
            preun=_lua_scriptlet(
                "preun", "erase:tdnf-replay-installonly:3.0",
            ),
        ),
        "tdnf-replay-installonly-4": _package_spec(
            "tdnf-replay-installonly", version="4.0",
            post=_lua_scriptlet(
                "post", "install:tdnf-replay-installonly:4.0",
            ),
            preun=_lua_scriptlet(
                "preun", "erase:tdnf-replay-installonly:4.0",
            ),
        ),
        "tdnf-replay-plain": _package_spec(
            "tdnf-replay-plain",
            post=_lua_scriptlet("post", "install:tdnf-replay-plain"),
        ),
        "tdnf-replay-upgrade-1": _package_spec(
            "tdnf-replay-upgrade", version="1.0",
        ),
        "tdnf-replay-upgrade-2": _package_spec(
            "tdnf-replay-upgrade",
            version="2.0",
            post=_lua_scriptlet(
                "post", "upgrade:tdnf-replay-upgrade:2.0",
            ),
        ),
        "tdnf-replay-downgrade-1": _package_spec(
            "tdnf-replay-downgrade",
            version="1.0",
            post=_lua_scriptlet(
                "post", "install:tdnf-replay-downgrade:1.0",
            ),
        ),
        "tdnf-replay-downgrade-2": _package_spec(
            "tdnf-replay-downgrade",
            version="2.0",
            preun=_lua_scriptlet(
                "preun", "erase:tdnf-replay-downgrade:2.0",
            ),
        ),
        "tdnf-replay-reinstall": _package_spec(
            "tdnf-replay-reinstall",
            post=_lua_scriptlet(
                "post", "reinstall:tdnf-replay-reinstall:1.0",
            ),
        ),
    }
    for name, body in specs.items():
        spec_path = topdir / "SPECS" / (name + ".spec")
        spec_path.write_text(body, encoding="utf-8")
        result = utils.run([
            "rpmbuild",
            "-D", "_topdir {}".format(topdir),
            "-D", "__transaction_unshare %{nil}",
            "-bb", str(spec_path),
        ])
        assert result["retval"] == 0, result["stderr"]

    destination = repository / "RPMS" / "replay-acceptance"
    destination.mkdir(parents=True, exist_ok=True)
    for rpm_path in topdir.glob("RPMS/**/*.rpm"):
        shutil.copy2(rpm_path, destination / rpm_path.name)

    shutil.rmtree(repository / "repodata")
    result = utils.run([
        "createrepo_c",
        "--general-compress-type", "gz",
        "--compress-type", "gz",
        str(repository),
    ])
    assert result["retval"] == 0, result["stderr"]


def _seed_root(utils, root, repository, package_patterns):
    root.mkdir(parents=True)
    for index, pattern in enumerate(package_patterns, start=1):
        matches = list(repository.glob("RPMS/**/{}.rpm".format(pattern)))
        assert len(matches) == 1, (pattern, matches)
        result = utils.run([
            utils.config["rpmdb_write_binary"],
            "install",
            str(root),
            str(matches[0]),
            str(index),
            str(index),
        ])
        assert result["retval"] == 0, result["stderr"]


def _clone_root(source, destination):
    shutil.copytree(source, destination, symlinks=True)


def _export_bundle(
        utils, env, name, operation, root, subjects,
        installonly_name=None, installonly_limit=3):
    scratch = env.workspace / "scratch" / name
    scratch.mkdir(parents=True)
    destination = env.workspace / "bundles" / name
    destination.parent.mkdir(exist_ok=True)
    command = [
        utils.config["replay_export_binary"],
        "--operation", operation,
        "--repo-id", "replay-online",
        "--base-url", env.base_url,
        "--install-root", str(root),
        "--cache-dir", "/var/cache/tdnf-replay-{}".format(name),
        "--scratch-dir", str(scratch),
        "--destination", str(destination),
        "--architecture", ARCH,
        "--release-version", "1",
    ]
    if installonly_name is not None:
        command.extend([
            "--installonly-name", installonly_name,
            "--installonly-limit", str(installonly_limit),
        ])
    command.extend(["--", *subjects])
    prior_home = os.environ.get("HOME")
    os.environ["HOME"] = str(env.macro_home)
    try:
        result = utils.run(command)
    finally:
        if prior_home is None:
            os.environ.pop("HOME", None)
        else:
            os.environ["HOME"] = prior_home
    assert result["retval"] == 0, result["stderr"]
    exported = json.loads("\n".join(result["stdout"]))
    assert len(exported["bundle_digest"]) == 64
    assert len(exported["plan_digest"]) == 64
    return destination


@pytest.fixture(scope="module")
def replay_environment(utils):
    if not os.path.isfile(utils.config["replay_export_binary"]):
        pytest.fail(
            "acceptance export driver missing; run "
            "`zig build replay-acceptance-export --prefix ./out`"
        )
    workspace = Path(utils.config["build_dir"]) / (
        "replay-acceptance-" + uuid.uuid4().hex
    )
    http_root = workspace / "http"
    repository = http_root / "repo"
    workspace.mkdir(parents=True)
    shutil.copytree(
        Path(utils.config["repo_path"]) / "photon-test",
        repository,
        symlinks=True,
    )
    _build_replay_packages(utils, workspace, repository)

    online = CountingServer(http_root)
    guard = None
    try:
        env = SimpleNamespace(
            workspace=workspace,
            repository=repository,
            online=online,
            guard=None,
            base_url="http://127.0.0.1:{}/repo".format(online.port),
            bundles={},
            roots={},
            macro_home=workspace / "macro-home",
        )
        env.macro_home.mkdir()
        (env.macro_home / ".rpmmacros").write_text(
            "%_dbpath /var/lib/rpm\n",
            encoding="utf-8",
        )

        roots = workspace / "roots"
        roots.mkdir()
        mixed = roots / "mixed-template"
        reinstall = roots / "reinstall-template"
        unexpected = roots / "unexpected-template"
        _seed_root(
            utils,
            mixed,
            repository,
            [
                "tdnf-replay-installonly-1.0-1.*",
                "tdnf-replay-installonly-2.0-1.*",
                "tdnf-replay-installonly-3.0-1.*",
                "tdnf-replay-upgrade-1.0-1.*",
                "tdnf-replay-downgrade-2.0-1.*",
                "tdnf-replay-old-1.0-1.*",
                "tdnf-replay-retired-1.0-1.*",
            ],
        )
        _seed_root(
            utils,
            reinstall,
            repository,
            ["tdnf-replay-reinstall-1.0-1.*"],
        )
        _seed_root(
            utils, unexpected, repository, ["tdnf-test-two-1.0.1-1.*"],
        )

        for name, source in {
            "mixed": mixed,
            "reinstall": reinstall,
            "unexpected": unexpected,
        }.items():
            target = roots / (name + "-target")
            _clone_root(source, target)
            env.roots[name] = target

        clean_export = roots / "clean-export"
        clean_export.mkdir()
        alternative_export = roots / "alternative-export"
        alternative_export.mkdir()
        failure_export = roots / "failure-export"
        failure_export.mkdir()
        reinstall_export = roots / "reinstall-export"
        _clone_root(reinstall, reinstall_export)

        env.bundles["install"] = _export_bundle(
            utils,
            env,
            "install",
            "install",
            clean_export,
            ["tdnf-test-one"],
        )
        env.bundles["mixed"] = _export_bundle(
            utils,
            env,
            "mixed",
            "install",
            mixed,
            [
                "tdnf-replay-plain",
                "tdnf-replay-installonly-4.0-1",
                "tdnf-replay-upgrade-2.0-1",
                "tdnf-replay-downgrade-1.0-1",
                "tdnf-replay-replacement-a",
                "tdnf-replay-replacement-b",
            ],
            installonly_name="tdnf-replay-installonly",
            installonly_limit=3,
        )
        # The public resolver accepts one typed transaction verb. Reinstall is
        # itself a verb, so it cannot share an install request with the five
        # solver-derived action kinds captured in the mixed bundle.
        env.bundles["reinstall"] = _export_bundle(
            utils,
            env,
            "reinstall",
            "reinstall",
            reinstall_export,
            ["tdnf-replay-reinstall"],
        )
        env.bundles["failure"] = _export_bundle(
            utils,
            env,
            "failure",
            "install",
            failure_export,
            ["tdnf-replay-fail"],
        )
        env.bundles["alternative"] = _export_bundle(
            utils,
            env,
            "alternative",
            "install",
            alternative_export,
            ["tdnf-test-multiversion-1.0.1-1"],
        )
        assert online.count > 0
        port = online.port
        online.stop()
        online = None
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            assert probe.connect_ex(("127.0.0.1", port)) != 0
        finally:
            probe.close()

        closed_root = roots / "closed-replay"
        closed_root.mkdir()
        _write_invalid_rpmz_config(closed_root)
        env.closed_root = closed_root
        env.closed_result = _replay(
            utils,
            env,
            env.bundles["install"],
            closed_root,
        )

        guard = ConnectionTrap(port)
        env.guard = guard
        assert guard.snapshot() == (0, 0)
        yield env
    finally:
        if guard is not None:
            guard.stop()
        if online is not None:
            online.stop()
        shutil.rmtree(workspace, ignore_errors=True)


def _load_json(path):
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def _write_json(path, value):
    path.write_text(
        json.dumps(
            value,
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )


def _load_plan(bundle):
    return _load_json(bundle / "plan.json")


def _replay(utils, env, bundle, root, architecture=ARCH):
    return utils.run([
        "rpmz",
        "replay",
        "--installroot", str(root),
        "--rpmdb-path", "/var/lib/rpm",
        "--forcearch", architecture,
        str(bundle),
    ], noconfig=True)


def _result(result):
    assert len(result["stdout"]) == 1
    return json.loads(result["stdout"][0])


def _recorded_action_order(plan):
    ordered = []
    seen = set()
    action_indices = {
        action["id"]: index for index, action in enumerate(plan["actions"])
    }
    for step in plan["execution"]["steps"]:
        index = action_indices[step["action_id"]]
        if index not in seen:
            seen.add(index)
            ordered.append(index)
    ordered.extend(
        index for index in range(len(plan["actions"])) if index not in seen
    )
    return [
        {
            "index": index,
            "kind": plan["actions"][index]["kind"],
        }
        for index in ordered
    ]


def _recorded_effect_order(plan):
    packages = {
        package["id"]: package["identity"]
        for package in plan["packages"]
    }
    labels = []
    for step in plan["execution"]["steps"]:
        identity = packages[step["package_id"]]
        name = identity["name"]
        operation = "erase" if step["operation"] == "erase" else "install"
        if name == "tdnf-replay-installonly":
            labels.append(
                "{}:{}:{}".format(operation, name, identity["version"])
            )
        elif name in {
                "tdnf-replay-old",
                "tdnf-replay-retired",
                "tdnf-replay-replacement-a",
                "tdnf-replay-replacement-b"}:
            labels.append("{}:{}".format(operation, name))
        elif name == "tdnf-replay-plain":
            labels.append("install:tdnf-replay-plain")
        elif name == "tdnf-replay-upgrade" and identity["version"] == "2.0":
            labels.append("upgrade:tdnf-replay-upgrade:2.0")
        elif name == "tdnf-replay-downgrade":
            labels.append(
                "{}:tdnf-replay-downgrade:{}".format(
                    operation,
                    identity["version"],
                )
            )
        elif name == "tdnf-replay-reinstall":
            labels.append("reinstall:tdnf-replay-reinstall:1.0")
    return labels


def _identity_key(package):
    identity = package["identity"]
    return (
        identity["name"],
        identity["epoch"] or 0,
        identity["version"],
        identity["release"],
        identity["arch"],
        package["hnum"],
    )


def _identity_nevra(package):
    identity = package["identity"]
    epoch = ""
    if identity["epoch"] not in (None, 0):
        epoch = "{}:".format(identity["epoch"])
    return "{name}-{epoch}{version}-{release}.{arch}".format(
        epoch=epoch,
        name=identity["name"],
        version=identity["version"],
        release=identity["release"],
        arch=identity["arch"],
    )


def _assert_actual_inventory(utils, root, replay_result):
    listed = utils.run([utils.config["rpmdb_list_binary"], str(root)])
    assert listed["retval"] == 0, listed["stderr"]
    expected = sorted(
        _identity_nevra(package)
        for package in replay_result["final_inventory"]
    )
    assert sorted(listed["stdout"]) == expected


def _assert_success(utils, bundle, root, result):
    assert result["retval"] == 0, result["stderr"]
    replayed = _result(result)
    plan = _load_plan(bundle)
    assert replayed["schema"] == "tdnf.replay-result/v1"
    assert replayed["status"] == "succeeded"
    assert replayed["validation_failure"] is None
    assert replayed["transaction_failure"] is None
    assert replayed["plan_digest"] == plan["digest"]["value"]
    assert replayed["applied_plan_digest"] == plan["digest"]["value"]
    assert [
        {
            "index": action["index"],
            "kind": action["kind"],
        }
        for action in replayed["actions"]
    ] == _recorded_action_order(plan)
    assert all(action["status"] == "applied" for action in replayed["actions"])
    assert replayed["final_inventory"] is not None
    inventory_keys = [
        _identity_key(package) for package in replayed["final_inventory"]
    ]
    assert inventory_keys == sorted(inventory_keys)
    _assert_actual_inventory(utils, root, replayed)
    return replayed


def _inventory_projection(result):
    projected = copy.deepcopy(result)
    for package in projected["final_inventory"]:
        package["hnum"] = 0
    return projected


def test_http_export_replays_offline_deterministically(
        utils, replay_environment):
    env = replay_environment
    closed = _assert_success(
        utils,
        env.bundles["install"],
        env.closed_root,
        env.closed_result,
    )

    trap_root = env.workspace / "roots" / "trap-replay"
    trap_root.mkdir()
    _write_invalid_rpmz_config(trap_root)
    before_requests = env.guard.snapshot()
    trap_run = _replay(utils, env, env.bundles["install"], trap_root)
    trapped = _assert_success(
        utils,
        env.bundles["install"],
        trap_root,
        trap_run,
    )

    assert env.closed_result["stdout"] == trap_run["stdout"]
    assert _inventory_projection(closed) == _inventory_projection(trapped)
    assert env.guard.snapshot() == before_requests == (0, 0)


def test_exported_actions_replay_in_recorded_order(utils, replay_environment):
    env = replay_environment
    mixed_inventory = {
        "tdnf-replay-downgrade-1.0-1.noarch",
        "tdnf-replay-installonly-2.0-1.noarch",
        "tdnf-replay-installonly-3.0-1.noarch",
        "tdnf-replay-installonly-4.0-1.noarch",
        "tdnf-replay-plain-1.0-1.noarch",
        "tdnf-replay-replacement-a-1.0-1.noarch",
        "tdnf-replay-replacement-b-1.0-1.noarch",
        "tdnf-replay-upgrade-2.0-1.noarch",
    }
    before_requests = env.guard.snapshot()

    mixed_result = _replay(
        utils, env, env.bundles["mixed"], env.roots["mixed"],
    )
    mixed_replayed = _assert_success(
        utils,
        env.bundles["mixed"],
        env.roots["mixed"],
        mixed_result,
    )
    assert {
        _identity_nevra(package)
        for package in mixed_replayed["final_inventory"]
    } == mixed_inventory
    mixed_plan = _load_plan(env.bundles["mixed"])
    assert Counter(
        action["kind"] for action in mixed_plan["actions"]
    ) == Counter({
        "install": 2,
        "erase": 1,
        "upgrade": 1,
        "downgrade": 1,
        "obsolete": 2,
    })
    mixed_log = env.roots["mixed"] / "var/lib/tdnf-replay-order.log"
    mixed_effects = _recorded_effect_order(mixed_plan)
    assert len(mixed_effects) == len(mixed_plan["execution"]["steps"])
    assert mixed_log.read_text(
        encoding="utf-8",
    ).splitlines() == mixed_effects

    obsolete_actions = [
        action for action in mixed_plan["actions"]
        if action["kind"] == "obsolete"
    ]
    assert len(obsolete_actions) == 2
    assert any(len(action["prior_package_ids"]) == 2
               for action in obsolete_actions)
    prior_counts = {}
    for action in obsolete_actions:
        for package_id in action["prior_package_ids"]:
            prior_counts[package_id] = prior_counts.get(package_id, 0) + 1
    assert max(prior_counts.values()) == 2

    reinstall_result = _replay(
        utils,
        env,
        env.bundles["reinstall"],
        env.roots["reinstall"],
    )
    reinstall_replayed = _assert_success(
        utils,
        env.bundles["reinstall"],
        env.roots["reinstall"],
        reinstall_result,
    )
    assert [
        action["kind"] for action in reinstall_replayed["actions"]
    ] == ["reinstall"]
    assert {
        _identity_nevra(package)
        for package in reinstall_replayed["final_inventory"]
    } == {"tdnf-replay-reinstall-1.0-1.noarch"}
    reinstall_plan = _load_plan(env.bundles["reinstall"])
    reinstall_log = (
        env.roots["reinstall"] / "var/lib/tdnf-replay-order.log"
    )
    reinstall_effects = _recorded_effect_order(reinstall_plan)
    assert len(reinstall_effects) == len(
        reinstall_plan["execution"]["steps"]
    )
    assert reinstall_log.read_text(
        encoding="utf-8",
    ).splitlines() == reinstall_effects

    assert {
        action["kind"] for action in (
            mixed_plan["actions"] + reinstall_plan["actions"]
        )
    } == {
        "install", "erase", "upgrade", "downgrade", "reinstall", "obsolete",
    }
    assert env.guard.snapshot() == before_requests == (0, 0)


def _tree_snapshot(root):
    entries = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        stat_result = path.lstat()
        if path.is_symlink():
            value = ("link", os.readlink(path))
        elif path.is_file():
            if path.name in ("rpmdb.sqlite-shm", "rpmdb.sqlite-wal"):
                value = ("sqlite-sidecar", stat_result.st_size)
            else:
                value = ("file", hashlib.sha256(path.read_bytes()).hexdigest())
        else:
            value = ("directory", None)
        entries.append((relative, stat_result.st_mode, value))
    return entries


def _copy_bundle(env, source, name):
    destination = env.workspace / "mutations" / name
    destination.parent.mkdir(exist_ok=True)
    shutil.copytree(source, destination, symlinks=True)
    return destination


def _manifest_file(manifest, path):
    return next(entry for entry in manifest["files"] if entry["path"] == path)


def _refresh_manifest_file(bundle, manifest, path):
    content = (bundle / path).read_bytes()
    entry = _manifest_file(manifest, path)
    entry["sha256"] = hashlib.sha256(content).hexdigest()
    entry["size"] = len(content)


def _rewrite_manifest(bundle, mutate):
    manifest_path = bundle / "bundle.json"
    manifest = _load_json(manifest_path)
    mutate(manifest)
    unsigned = {
        key: value for key, value in manifest.items() if key != "digest"
    }
    unsigned_bytes = json.dumps(
        unsigned,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    digest = hashlib.sha256(
        manifest["schema"].encode("utf-8") + b"\0" + unsigned_bytes
    ).hexdigest()
    canonical = {
        "digest": {
            "algorithm": "sha256",
            "domain": manifest["schema"],
            "value": digest,
        },
    }
    canonical.update(unsigned)
    _write_json(manifest_path, canonical)


def _rewrite_plan(bundle, mutate):
    plan_path = bundle / "plan.json"
    plan = _load_json(plan_path)
    mutate(plan)
    _write_json(plan_path, plan)
    _rewrite_manifest(
        bundle,
        lambda manifest: _refresh_manifest_file(
            bundle,
            manifest,
            "plan.json",
        ),
    )


def _different_digest(value):
    replacement = "0" if value[0] != "0" else "1"
    return replacement + value[1:]


def _first_package_path(bundle):
    return _load_json(bundle / "bundle.json")["packages"][0]["path"]


def _first_metadata_path(bundle):
    manifest = _load_json(bundle / "bundle.json")
    return next(
        entry["path"]
        for entry in manifest["files"]
        if entry["path"].startswith("repos/") and entry["path"].endswith("/repodata/repomd.xml")
    )


def _validation_target(env, name):
    root = env.workspace / "validation-roots" / name
    root.mkdir(parents=True)
    (root / "unchanged-marker").write_text("unchanged", encoding="utf-8")
    return root


def _assert_validation_failure(
        utils, env, bundle, root, expected_failure, architecture=ARCH):
    before = _tree_snapshot(root)
    before_requests = env.guard.snapshot()
    result = _replay(utils, env, bundle, root, architecture)
    replayed = _result(result)
    assert result["retval"] == 3
    assert replayed["status"] == "validation_failed"
    assert replayed["validation_failure"] == expected_failure
    assert replayed["transaction_failure"] is None
    assert replayed["applied_plan_digest"] is None
    assert _tree_snapshot(root) == before
    assert env.guard.snapshot() == before_requests


def test_replay_preflight_rejects_every_substitution_before_mutation(
        utils, replay_environment):
    env = replay_environment
    install = env.bundles["install"]

    unsupported_bundle = _copy_bundle(
        env,
        install,
        "unsupported-bundle-schema",
    )
    _rewrite_manifest(
        unsupported_bundle,
        lambda manifest: manifest.__setitem__(
            "schema",
            "tdnf.transaction-bundle/v999",
        ),
    )
    _assert_validation_failure(
        utils,
        env,
        unsupported_bundle,
        _validation_target(env, "unsupported-bundle-schema"),
        "manifest_not_canonical",
    )

    unsupported_plan = _copy_bundle(
        env,
        install,
        "unsupported-plan-schema",
    )
    _rewrite_plan(
        unsupported_plan,
        lambda plan: plan.__setitem__(
            "schema",
            "tdnf.transaction-plan/v999",
        ),
    )
    _assert_validation_failure(
        utils,
        env,
        unsupported_plan,
        _validation_target(env, "unsupported-plan-schema"),
        "plan_mismatch",
    )

    corrupt_plan_digest = _copy_bundle(
        env,
        install,
        "corrupt-plan-digest",
    )

    def corrupt_embedded_plan_digest(plan):
        plan["digest"]["value"] = _different_digest(
            plan["digest"]["value"]
        )

    _rewrite_plan(corrupt_plan_digest, corrupt_embedded_plan_digest)
    _assert_validation_failure(
        utils,
        env,
        corrupt_plan_digest,
        _validation_target(env, "corrupt-plan-digest"),
        "plan_mismatch",
    )

    corrupt_bundle_digest = _copy_bundle(
        env,
        install,
        "corrupt-bundle-digest",
    )
    corrupt_manifest_path = corrupt_bundle_digest / "bundle.json"
    corrupt_manifest = _load_json(corrupt_manifest_path)
    corrupt_manifest["digest"]["value"] = _different_digest(
        corrupt_manifest["digest"]["value"]
    )
    _write_json(corrupt_manifest_path, corrupt_manifest)
    _assert_validation_failure(
        utils,
        env,
        corrupt_bundle_digest,
        _validation_target(env, "corrupt-bundle-digest"),
        "manifest_not_canonical",
    )

    plan_reference_mismatch = _copy_bundle(
        env,
        install,
        "bundle-plan-digest-mismatch",
    )

    def mismatch_plan_reference(manifest):
        manifest["plan"]["digest"] = _different_digest(
            manifest["plan"]["digest"]
        )

    _rewrite_manifest(plan_reference_mismatch, mismatch_plan_reference)
    _assert_validation_failure(
        utils,
        env,
        plan_reference_mismatch,
        _validation_target(env, "bundle-plan-digest-mismatch"),
        "plan_mismatch",
    )

    missing_rpm = _copy_bundle(env, install, "missing-rpm")
    (missing_rpm / _first_package_path(missing_rpm)).unlink()
    _assert_validation_failure(
        utils,
        env,
        missing_rpm,
        _validation_target(env, "missing-rpm"),
        "missing_bundle_file",
    )

    changed_rpm = _copy_bundle(env, install, "changed-rpm")
    rpm_path = changed_rpm / _first_package_path(changed_rpm)
    content = bytearray(rpm_path.read_bytes())
    content[-1] ^= 0x01
    rpm_path.write_bytes(content)
    _assert_validation_failure(
        utils,
        env,
        changed_rpm,
        _validation_target(env, "changed-rpm"),
        "checksum_mismatch",
    )

    substituted_rpm = _copy_bundle(env, install, "substituted-rpm")
    substituted_path = substituted_rpm / _first_package_path(substituted_rpm)
    substituted_bytes = bytearray(substituted_path.read_bytes())
    substituted_bytes[-1] ^= 0x01
    substituted_path.write_bytes(substituted_bytes)
    _rewrite_manifest(
        substituted_rpm,
        lambda manifest: _refresh_manifest_file(
            substituted_rpm,
            manifest,
            _first_package_path(substituted_rpm),
        ),
    )
    _assert_validation_failure(
        utils,
        env,
        substituted_rpm,
        _validation_target(env, "substituted-rpm"),
        "rpm_mismatch",
    )

    changed_metadata = _copy_bundle(env, install, "changed-metadata")
    metadata_path = _first_metadata_path(changed_metadata)
    with (changed_metadata / metadata_path).open("ab") as stream:
        stream.write(b"\n")
    _rewrite_manifest(
        changed_metadata,
        lambda manifest: _refresh_manifest_file(
            changed_metadata, manifest, metadata_path,
        ),
    )
    _assert_validation_failure(
        utils,
        env,
        changed_metadata,
        _validation_target(env, "changed-metadata"),
        "metadata_mismatch",
    )

    wrong_repository = _copy_bundle(env, install, "wrong-repository")

    def add_wrong_repository(manifest):
        original = copy.deepcopy(manifest["repositories"][0])
        original["id"] = "wrong-repository"
        manifest["repositories"].append(original)
        manifest["repositories"].sort(key=lambda repository: repository["id"])
        prefix = "repos/{}/".format(manifest["repositories"][0]["id"])
        source_entries = [
            copy.deepcopy(entry)
            for entry in manifest["files"]
            if entry["path"].startswith(prefix)
        ]
        for entry in source_entries:
            source = wrong_repository / entry["path"]
            entry["path"] = entry["path"].replace(
                prefix, "repos/wrong-repository/", 1,
            )
            target = wrong_repository / entry["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            manifest["files"].append(entry)
        manifest["files"].sort(key=lambda entry: entry["path"])

    _rewrite_manifest(wrong_repository, add_wrong_repository)
    _assert_validation_failure(
        utils,
        env,
        wrong_repository,
        _validation_target(env, "wrong-repository"),
        "repository_mismatch",
    )

    other_arch = "aarch64" if ARCH != "aarch64" else "x86_64"
    _assert_validation_failure(
        utils,
        env,
        install,
        _validation_target(env, "wrong-architecture"),
        "architecture_mismatch",
        architecture=other_arch,
    )

    _assert_validation_failure(
        utils,
        env,
        install,
        env.roots["unexpected"],
        "rpmdb_mismatch",
    )

    newer = _copy_bundle(env, env.bundles["alternative"], "newer-alternative")
    newer_rpm = next(
        env.repository.glob(
            "RPMS/**/tdnf-test-multiversion-1.0.2-1.*.rpm"
        )
    )
    package_path = _first_package_path(newer)
    shutil.copy2(newer_rpm, newer / package_path)

    def substitute_newer(manifest):
        package = manifest["packages"][0]
        package["identity"]["version"] = "1.0.2"
        package["checksum"]["value"] = hashlib.sha256(
            (newer / package_path).read_bytes()
        ).hexdigest()
        package["size"] = (newer / package_path).stat().st_size
        _refresh_manifest_file(newer, manifest, package_path)

    _rewrite_manifest(newer, substitute_newer)
    _assert_validation_failure(
        utils,
        env,
        newer,
        _validation_target(env, "newer-alternative"),
        "plan_mismatch",
    )

    missing_metadata = _copy_bundle(env, install, "missing-metadata")
    (missing_metadata / _first_metadata_path(missing_metadata)).unlink()
    _assert_validation_failure(
        utils,
        env,
        missing_metadata,
        _validation_target(env, "missing-metadata"),
        "missing_bundle_file",
    )

    additional = _copy_bundle(env, install, "additional-file")
    cached_alternative = (
        additional /
        "packages/replay-online/cache/newer-alternative.rpm"
    )
    cached_alternative.parent.mkdir(parents=True)
    shutil.copy2(newer_rpm, cached_alternative)
    _assert_validation_failure(
        utils,
        env,
        additional,
        _validation_target(env, "additional-file"),
        "additional_bundle_file",
    )

    wrong_trust = _copy_bundle(env, install, "wrong-trust")
    fingerprint = "0" * 40
    key_path = "keys/{}.asc".format(fingerprint)
    (wrong_trust / "keys").mkdir()
    shutil.copy2(
        env.repository / "keys" / "pubkey.wrong.asc",
        wrong_trust / key_path,
    )

    def require_wrong_trust(manifest):
        key_bytes = (wrong_trust / key_path).read_bytes()
        manifest["files"].append({
            "path": key_path,
            "sha256": hashlib.sha256(key_bytes).hexdigest(),
            "size": len(key_bytes),
        })
        manifest["files"].sort(key=lambda entry: entry["path"])
        manifest["keys"] = [{
            "fingerprint": fingerprint,
            "path": key_path,
        }]
        manifest["repositories"][0]["gpg_check"] = True
        manifest["packages"][0]["signature"] = {
            "key_fingerprint": fingerprint,
            "outcome": "verified",
        }

    _rewrite_manifest(wrong_trust, require_wrong_trust)
    _assert_validation_failure(
        utils,
        env,
        wrong_trust,
        _validation_target(env, "wrong-trust"),
        "signature_mismatch",
    )


def test_transaction_failure_is_truthful_and_not_success_shaped(
        utils, replay_environment):
    env = replay_environment
    root = env.workspace / "roots" / "transaction-failure"
    root.mkdir()
    before_requests = env.guard.snapshot()
    result = _replay(utils, env, env.bundles["failure"], root)
    replayed = _result(result)

    assert result["retval"] == 4
    assert replayed["status"] == "transaction_failed"
    assert replayed["validation_failure"] is None
    assert replayed["transaction_failure"] == "transaction_failed"
    assert replayed["applied_plan_digest"] is None
    plan = _load_plan(env.bundles["failure"])
    package_names = {
        package["id"]: package["identity"]["name"]
        for package in plan["packages"]
    }
    expected_status = {
        "tdnf-replay-first": "applied",
        "tdnf-replay-fail": "indeterminate",
    }
    expected_actions = []
    for ordered in _recorded_action_order(plan):
        action = plan["actions"][ordered["index"]]
        name = package_names[action["target_package_id"]]
        expected_actions.append({
            "index": ordered["index"],
            "kind": ordered["kind"],
            "status": expected_status[name],
        })
    assert replayed["actions"] == expected_actions

    expected_inventory = [{
        "hnum": 1,
        "identity": {
            "arch": "noarch",
            "epoch": None,
            "name": "tdnf-replay-first",
            "release": "1",
            "version": "1.0",
        },
    }]
    assert replayed["final_inventory"] == expected_inventory
    listed = utils.run([utils.config["rpmdb_list_binary"], str(root)])
    assert listed["retval"] == 0, listed["stderr"]
    assert listed["stdout"] == ["tdnf-replay-first-1.0-1.noarch"]
    assert env.guard.snapshot() == before_requests == (0, 0)
