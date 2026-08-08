#!/usr/bin/env python3

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile


PRODUCT_DEPENDENCIES = ("sqlite", "tls", "zlua")


def dependency_hashes(manifest):
    text = manifest.read_text()
    hashes = {}
    for name in PRODUCT_DEPENDENCIES:
        match = re.search(
            rf"\.{name}\s*=\s*\.\{{.*?\.hash\s*=\s*\"([^\"]+)\"",
            text,
            re.DOTALL,
        )
        if match is None:
            raise RuntimeError(f"unable to find {name} hash in {manifest}")
        hashes[name] = match.group(1)
    return hashes


def extract_dependency_closure(package_cache, system_packages, initial_hashes):
    pending = list(initial_hashes)
    extracted = set()
    while pending:
        package_hash = pending.pop()
        if package_hash in extracted:
            continue
        if package_hash.startswith("libsolv-"):
            raise RuntimeError("product dependency closure requested libsolv")
        archive = package_cache / f"{package_hash}.tar.gz"
        if not archive.is_file():
            raise RuntimeError(f"missing cached package archive: {archive}")
        with tarfile.open(archive, "r:gz") as package:
            package.extractall(system_packages, filter="data")
        extracted.add(package_hash)
        manifest = system_packages / package_hash / "build.zig.zon"
        if manifest.is_file():
            pending.extend(
                match.group(1)
                for match in re.finditer(
                    r'\.hash\s*=\s*"([^"]+)"',
                    manifest.read_text(),
                )
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zig", default="zig")
    parser.add_argument("--package-cache")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    package_cache_arg = (
        args.package_cache or os.environ.get("TDNF_ZIG_PACKAGE_CACHE")
    )
    package_cache = (
        Path(package_cache_arg)
        if package_cache_arg
        else Path(os.environ["ZIG_GLOBAL_CACHE_DIR"]) / "p"
    )
    scratch = root / ".product-no-libsolv-fetch"
    shutil.rmtree(scratch, ignore_errors=True)
    system_packages = scratch / "system-packages"
    system_packages.mkdir(parents=True)

    try:
        extract_dependency_closure(
            package_cache,
            system_packages,
            dependency_hashes(root / "build.zig.zon").values(),
        )

        environment = os.environ.copy()
        environment.pop("ZIG_LOCAL_CACHE_DIR", None)
        environment["ZIG_GLOBAL_CACHE_DIR"] = str(scratch / "global-cache")
        subprocess.run(
            [
                args.zig,
                "build",
                "--system",
                str(system_packages),
                "-Doptimize=ReleaseSafe",
                "install",
                "--prefix",
                str(scratch / "out"),
                "--cache-dir",
                str(scratch / "local-cache"),
                "--global-cache-dir",
                str(scratch / "global-cache"),
            ],
            cwd=root,
            env=environment,
            check=True,
        )
        if any(path.name.startswith("libsolv-") for path in system_packages.iterdir()):
            raise RuntimeError("libsolv was present in the product system package set")
        print("fetch-disabled clean product build passed without libsolv")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()
