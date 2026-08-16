#!/usr/bin/env python3

import argparse
import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

from release_common import parse_semver


ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / ".github/release-assets.json"


class CommandRunner:
    def ghr_install(self, spec, env):
        return subprocess.run(
            ["ghr", "install", spec],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

    def rpmz_version(self, path, env):
        return subprocess.run(
            [path, "--version"],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

    def native_audit(self, prefix, env):
        return subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts/librpm-audit.py"),
                "--prefix",
                str(prefix),
            ],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

    def release_assets(self, repo, tag, env):
        return subprocess.run(
            [
                "gh", "release", "view", tag,
                "--repo", repo, "--json", "assets",
            ],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

def expected_assets(manifest, version):
    return {
        name.format(version=version)
        for name in manifest["public_release_assets"]
    }


def validate_arguments(args, manifest):
    if args.repo != manifest["repository"]:
        raise SystemExit(f"unexpected release repository: {args.repo}")
    try:
        parse_semver(args.version)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    if args.tag != "v" + args.version:
        raise SystemExit(
            f"tag {args.tag!r} does not match version {args.version!r}"
        )
    if args.platform not in manifest["platforms"]:
        raise SystemExit(f"unsupported release platform: {args.platform}")


def run_smoke(args, runner=None):
    if runner is None:
        runner = CommandRunner()
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    validate_arguments(args, manifest)
    prefix = Path(args.prefix).resolve()
    tool_dir = prefix / "tools"
    bin_dir = prefix / "bin"
    cache_dir = prefix / "cache"
    for directory in (tool_dir, bin_dir, cache_dir):
        directory.mkdir(parents=True, exist_ok=False)

    env = os.environ.copy()
    env.update({
        "GHR_TOOL_DIR": str(tool_dir),
        "GHR_BIN_DIR": str(bin_dir),
        "GHR_CACHE_DIR": str(cache_dir),
        "PATH": str(bin_dir) + os.pathsep + env.get("PATH", ""),
    })
    install_spec = f"{args.repo}@{args.tag}"
    install_result = runner.ghr_install(install_spec, env)
    archive_name = manifest["binary_archive"].format(
        version=args.version, platform=args.platform
    )
    install_output = install_result.stdout + install_result.stderr
    if archive_name not in install_output:
        raise SystemExit(
            f"ghr did not report selecting {archive_name}"
        )

    rpmz_path = shutil.which("rpmz", path=env["PATH"])
    expected_path = str(bin_dir / "rpmz")
    if rpmz_path is None or str(Path(rpmz_path).resolve()) != str(
        Path(expected_path).resolve()
    ):
        raise SystemExit("rpmz was not installed on the controlled PATH")
    version_result = runner.rpmz_version(rpmz_path, env)
    if version_result.stdout.strip() != f"rpmz: {args.version}":
        raise SystemExit("installed rpmz reported the wrong version")

    install_roots = [
        path.parent.parent
        for path in tool_dir.rglob("bin/rpmz")
        if path.is_file()
    ]
    if len(install_roots) != 1:
        raise SystemExit("expected exactly one installed rpmz layout")
    install_root = install_roots[0]
    for relative in ("lib", "libexec", "etc", "COPYING", "README.md"):
        if not (install_root / relative).exists():
            raise SystemExit(f"installed release is missing {relative}")
    runner.native_audit(install_root, env)

    assets_result = runner.release_assets(args.repo, args.tag, env)
    release_data = json.loads(assets_result.stdout)
    actual_assets = {
        asset["name"] for asset in release_data.get("assets", [])
    }
    expected = expected_assets(manifest, args.version)
    if actual_assets != expected:
        raise SystemExit(
            "published release assets differ: "
            f"expected {sorted(expected)}, got {sorted(actual_assets)}"
        )

    print(
        f"release smoke passed for {args.repo}@{args.tag} "
        f"({args.platform})"
    )


class FakeResult:
    def __init__(self, stdout="", stderr=""):
        self.stdout = stdout
        self.stderr = stderr


class FakeRunner:
    def __init__(self, args, manifest, asset_names=None):
        self.args = args
        self.manifest = manifest
        self.asset_names = asset_names
        self.commands = []

    def ghr_install(self, spec, env):
        self.commands.append(["ghr", "install", spec])
        package = f"rpmz-{self.args.version}-{self.args.platform}"
        install_root = (
            Path(env["GHR_TOOL_DIR"]) / "cataggar/rpmz" / package
        )
        for relative in ("bin", "lib", "libexec", "etc"):
            (install_root / relative).mkdir(parents=True)
        (install_root / "COPYING").write_text("license", encoding="utf-8")
        (install_root / "README.md").write_text("readme", encoding="utf-8")
        installed = install_root / "bin/rpmz"
        installed.write_text("#!/bin/sh\n", encoding="utf-8")
        installed.chmod(0o755)
        linked = Path(env["GHR_BIN_DIR"]) / "rpmz"
        linked.symlink_to(installed)
        archive = self.manifest["binary_archive"].format(
            version=self.args.version,
            platform=self.args.platform,
        )
        return FakeResult(stdout=f"downloading {archive}\n")

    def rpmz_version(self, path, env):
        del env
        self.commands.append([path, "--version"])
        return FakeResult(stdout=f"rpmz: {self.args.version}\n")

    def native_audit(self, prefix, env):
        del env
        self.commands.append(["native-audit", str(prefix)])
        return FakeResult()

    def release_assets(self, repo, tag, env):
        del env
        self.commands.append(["gh", "release", "view", tag, repo])
        names = self.asset_names
        if names is None:
            names = expected_assets(self.manifest, self.args.version)
        assets = [
            {"name": name}
            for name in sorted(names)
        ]
        return FakeResult(stdout=json.dumps({"assets": assets}))


def self_test():
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    scratch = ROOT / f".release-smoke-self-test-{uuid.uuid4()}"
    args = argparse.Namespace(
        repo="cataggar/rpmz",
        tag="v0.1.0",
        version="0.1.0",
        platform="linux-x64",
        prefix=str(scratch),
    )
    fake = FakeRunner(args, manifest)
    try:
        run_smoke(args, fake)
        if fake.commands[0] != [
            "ghr", "install", "cataggar/rpmz@v0.1.0"
        ]:
            raise AssertionError("smoke did not begin with exact ghr install")
        if any(
            command[:2] == ["ghr", "download"]
            for command in fake.commands
        ):
            raise AssertionError("smoke used ghr download")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    expected = expected_assets(manifest, args.version)
    for suffix in (".sha256", ".sbom.spdx.json"):
        scratch = ROOT / f".release-smoke-self-test-{uuid.uuid4()}"
        bad_assets = set(expected)
        bad_assets.add(f"rpmz-{args.version}-linux-x64{suffix}")
        try:
            run_smoke(
                argparse.Namespace(**{**vars(args), "prefix": str(scratch)}),
                FakeRunner(args, manifest, bad_assets),
            )
        except SystemExit as error:
            if "published release assets differ" not in str(error):
                raise
        else:
            raise AssertionError(
                f"smoke accepted published metadata asset {suffix}"
            )
        finally:
            shutil.rmtree(scratch, ignore_errors=True)
    print("release smoke self-test passed")


def parser():
    result = argparse.ArgumentParser()
    result.add_argument("--self-test", action="store_true")
    result.add_argument("--repo")
    result.add_argument("--tag")
    result.add_argument("--version")
    result.add_argument("--platform")
    result.add_argument("--prefix")
    return result


def main():
    args = parser().parse_args()
    if args.self_test:
        self_test()
        return 0
    missing = [
        name for name in ("repo", "tag", "version", "platform", "prefix")
        if vars(args)[name] is None
    ]
    if missing:
        raise SystemExit(f"missing required arguments: {', '.join(missing)}")
    run_smoke(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
