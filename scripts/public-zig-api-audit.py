#!/usr/bin/env python3
"""Build the public Zig API from a read-only distributable package copy."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile


GENERATED_SOURCE_FILES = (
    "client/config.h",
    "history/config.h",
    "plugins/metalink/config.h",
    "plugins/repogpgcheck/config.h",
    "pytests/config.json",
    "pytests/mount-small-cache",
)
REQUIRED_PUBLIC_FILES = (
    "build.zig",
    "build.zig.zon",
    "tdnf.zig",
    "client/transaction_plan.zig",
)


def package_paths(manifest: Path) -> list[str]:
    text = manifest.read_text(encoding="utf-8")
    match = re.search(r"(?ms)^\s*\.paths\s*=\s*\.\{(.*?)^\s*\},", text)
    if match is None:
        raise RuntimeError(f"unable to find .paths in {manifest}")
    paths = re.findall(r'"([^"]+)"', match.group(1))
    if not paths:
        raise RuntimeError(f"{manifest} has an empty .paths list")
    return paths


def package_name(manifest: Path) -> str:
    text = manifest.read_text(encoding="utf-8")
    match = re.search(r"(?m)^\s*\.name\s*=\s*\.([A-Za-z0-9_]+),", text)
    if match is None:
        raise RuntimeError(f"unable to find .name in {manifest}")
    return match.group(1)


def tracked_files(source_root: Path, paths: list[str]) -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", *paths],
        cwd=source_root,
        check=True,
        stdout=subprocess.PIPE,
    )
    files = [
        Path(value.decode("utf-8"))
        for value in result.stdout.split(b"\0")
        if value
    ]
    for package_path in paths:
        prefix = Path(package_path)
        if not any(path == prefix or prefix in path.parents for path in files):
            raise RuntimeError(
                f"build.zig.zon .paths entry has no tracked files: {package_path}"
            )
    return files


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        destination.symlink_to(os.readlink(source))
    else:
        shutil.copy2(source, destination)


def make_read_only(root: Path) -> None:
    for path in sorted(root.rglob("*"), reverse=True):
        if path.is_symlink():
            continue
        mode = stat.S_IMODE(path.stat().st_mode)
        path.chmod(mode & ~0o222)
    root.chmod(0o555)


def source_snapshot(root: Path) -> dict[str, tuple[int, str]]:
    snapshot = {}
    for path in root.rglob("*"):
        if path.is_symlink():
            continue
        digest = ""
        if path.is_file():
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
        snapshot[str(path.relative_to(root))] = (path.stat().st_mode, digest)
    return snapshot


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", required=True)
    parser.add_argument("--optimize", required=True)
    args = parser.parse_args()

    source_root = Path(__file__).resolve().parent.parent
    # The audit tree is a sibling of the checkout, so the dependency path
    # cannot reach unlisted files through the writable repository. tempfile
    # supplies collision-safe names and the finally block removes the tree.
    audit_root = Path(
        tempfile.mkdtemp(
            prefix=".tdnf-public-zig-api-",
            dir=source_root.parent,
        )
    )
    try:
        package_root = audit_root / "package"
        package_root.mkdir()
        paths = package_paths(source_root / "build.zig.zon")
        for relative in tracked_files(source_root, paths):
            copy_file(source_root / relative, package_root / relative)

        for relative in REQUIRED_PUBLIC_FILES:
            if not (package_root / relative).is_file():
                raise RuntimeError(
                    f"distributable package is missing public API file: {relative}"
                )

        consumer_root = audit_root / "consumer"
        consumer_root.mkdir()
        for name in ("build.zig", "build.zig.zon", "main.zig"):
            copy_file(
                source_root / "tests/public-zig-consumer" / name,
                consumer_root / name,
            )

        for relative in GENERATED_SOURCE_FILES:
            generated = package_root / relative
            if generated.exists():
                raise RuntimeError(
                    f"distributable package contains generated source file: {relative}"
                )

        make_read_only(package_root)
        before = source_snapshot(package_root)

        global_cache = audit_root / "global-cache"
        (global_cache / "tmp").mkdir(parents=True)
        system_packages = audit_root / "system-packages"
        system_packages.mkdir()
        environment = os.environ.copy()
        environment["ZIG_GLOBAL_CACHE_DIR"] = str(global_cache)
        environment.pop("ZIG_LOCAL_CACHE_DIR", None)
        # Zig 0.16's --system disables fetching. Keeping this directory empty
        # makes the build itself failure-sensitive: requesting any private
        # package aborts before its build logic can execute.
        subprocess.run(
            [
                args.zig,
                "build",
                "check",
                f"-Doptimize={args.optimize}",
                "--system",
                str(system_packages),
                "--summary",
                "all",
            ],
            cwd=consumer_root,
            env=environment,
            check=True,
        )

        if any(system_packages.iterdir()):
            raise RuntimeError("Zig modified the empty system package directory")

        after = source_snapshot(package_root)
        if after != before:
            raise RuntimeError("public module import modified package source")

        package_cache = global_cache / "p"
        resolved_packages = []
        if package_cache.exists():
            for cached_package in package_cache.iterdir():
                manifest = cached_package / "build.zig.zon"
                if not manifest.is_file():
                    raise RuntimeError(
                        f"unexpected package cache entry: {cached_package.name}"
                    )
                resolved_packages.append(package_name(manifest))
        private_packages = [
            name for name in resolved_packages if name != "tdnf"
        ]
        if private_packages:
            raise RuntimeError(
                "public module import resolved private package dependencies: "
                + ", ".join(sorted(private_packages))
            )
    finally:
        if audit_root.exists():
            for path in audit_root.rglob("*"):
                if path.is_symlink():
                    continue
                mode = stat.S_IMODE(path.stat().st_mode)
                path.chmod(mode | (0o700 if path.is_dir() else 0o200))
            package_root = audit_root / "package"
            if package_root.exists():
                package_root.chmod(0o755)
            shutil.rmtree(audit_root)


if __name__ == "__main__":
    main()
