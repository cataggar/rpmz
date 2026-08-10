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
    "pytests/config.json",
    "pytests/mount-small-cache",
)
REQUIRED_PUBLIC_FILES = (
    "build.zig",
    "build.zig.zon",
    "tdnf.zig",
    "client/transaction_plan.zig",
    "doc/transaction-plan-api.md",
)
# Every source file a dependency consumer can reach through the public module
# graph. `build.zig` returns before it registers anything private, so this is
# the whole supported surface; a file that is not listed here is an
# implementation detail regardless of whether it happens to be packaged.
PUBLIC_SOURCE_FILES = (
    "tdnf.zig",
    "client/transaction_plan.zig",
)
# Modules the toolchain always provides. Every other module a public source
# file imports must be registered on the public module in `build.zig`, which
# the audit reads rather than restates.
TOOLCHAIN_MODULES = frozenset({"std", "builtin"})
PUBLIC_MODULE_VARIABLE = "public_tdnf_mod"
RETIRED_PUBLIC_C_FILES = (
    "client/libtdnf.map",
    "client/tdnf.pc.in",
    "client/history_abi.inc",
    "client/transaction_plan_capture_abi.inc",
    "scripts/abi-audit.py",
    "scripts/abi-baseline.json",
    "scripts/public-api-audit.py",
    "tools/cli/lib/tdnf-cli-libs.pc.in",
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


# The packages the resolve module graph cannot build without. Naming them
# keeps the audit honest if the closure is ever supplied from somewhere that
# happens to be empty.
REQUIRED_DEPENDENCY_NAMES = ("sqlite", "tls", "zlua")


def pinned_hashes(manifest: Path) -> set[str]:
    """Return the dependency hashes a `build.zig.zon` pins."""
    if not manifest.is_file():
        return set()
    text = manifest.read_text(encoding="utf-8")
    return set(re.findall(r'\.hash\s*=\s*"([^"]+)"', text))


def provide_system_packages(source_root: Path, destination: Path) -> set[str]:
    """Materialize the pinned closure into a `--system` package directory.

    `zig-pkg/` is where the root build extracts what it resolved, so it is the
    closure this checkout actually built against, transitive entries included.
    Every entry must be pinned by a manifest somewhere in that closure: an
    unpinned package would mean the consumer's build depends on something no
    manifest records.

    Not every pinned dependency has to be present. `libsolv` is lazy and only
    the opt-in parity oracle asks for it, which is the point of the separate
    `product-no-libsolv-fetch-audit`.
    """
    extracted = source_root / "zig-pkg"
    if not extracted.is_dir():
        raise RuntimeError(
            "zig-pkg/ is missing; run a root build before the audit"
        )
    entries = sorted(
        entry for entry in extracted.iterdir() if entry.is_dir()
    )
    pinned = pinned_hashes(source_root / "build.zig.zon")
    for entry in entries:
        pinned |= pinned_hashes(entry / "build.zig.zon")

    provided = set()
    for entry in entries:
        shutil.copytree(entry, destination / entry.name, symlinks=True)
        provided.add(entry.name)

    unpinned = sorted(provided - pinned)
    if unpinned:
        raise RuntimeError(
            "extracted closure contains unpinned packages: "
            + ", ".join(unpinned)
        )
    for name in REQUIRED_DEPENDENCY_NAMES:
        if not any(entry.startswith(name + "-") for entry in provided):
            raise RuntimeError(
                f"closure is missing the required dependency: {name}"
            )
    return provided


def package_name(manifest: Path) -> str:
    text = manifest.read_text(encoding="utf-8")
    match = re.search(r"(?m)^\s*\.name\s*=\s*\.([A-Za-z0-9_]+),", text)
    if match is None:
        raise RuntimeError(f"unable to find .name in {manifest}")
    return match.group(1)


def tracked_files(source_root: Path, paths: list[str]) -> list[Path]:
    result = subprocess.run(
        [
            "git",
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            *paths,
        ],
        cwd=source_root,
        check=True,
        stdout=subprocess.PIPE,
    )
    files = [
        Path(value.decode("utf-8"))
        for value in result.stdout.split(b"\0")
        if value and (source_root / Path(value.decode("utf-8"))).is_file()
    ]
    for package_path in paths:
        prefix = Path(package_path)
        if not any(path == prefix or prefix in path.parents for path in files):
            raise RuntimeError(
                f"build.zig.zon .paths entry has no tracked files: {package_path}"
            )
    return files


def registered_public_modules(build_script: Path) -> set[str]:
    """Return the module names `build.zig` registers on the public module.

    Reading them instead of listing them here keeps the audit from drifting:
    the set a consumer can resolve is exactly the set `build.zig` publishes.
    """
    text = build_script.read_text(encoding="utf-8")
    names = set(
        re.findall(
            re.escape(PUBLIC_MODULE_VARIABLE) + r'\.addImport\(\s*"([^"]+)"',
            text,
        )
    )
    if not names:
        raise RuntimeError(
            f"{build_script} registers no imports on {PUBLIC_MODULE_VARIABLE}"
        )
    return names


def check_public_closure(package_root: Path) -> None:
    """Fail if the public module graph reaches beyond its declared surface.

    A private import would still build here -- the audit consumer only calls
    into the public module -- but it would make an implementation file part of
    the package's compatibility promise without anyone deciding to.
    """
    allowed_modules = TOOLCHAIN_MODULES | registered_public_modules(
        package_root / "build.zig"
    )
    public_files = set(PUBLIC_SOURCE_FILES)
    pending = sorted(public_files)
    while pending:
        relative = pending.pop()
        source = package_root / relative
        if not source.is_file():
            raise RuntimeError(f"public source file is missing: {relative}")
        text = source.read_text(encoding="utf-8")
        for target in re.findall(r'@import\(\s*"([^"]+)"\s*\)', text):
            if not target.endswith(".zig"):
                if target not in allowed_modules:
                    raise RuntimeError(
                        f"{relative} imports unregistered module: {target}"
                    )
                continue
            resolved = os.path.normpath(
                str(Path(relative).parent / target)
            )
            if resolved not in public_files:
                raise RuntimeError(
                    f"{relative} imports non-public source file: {resolved}"
                )
    unreachable = public_files - set(PUBLIC_SOURCE_FILES)
    if unreachable:
        raise RuntimeError(
            "public source list is stale: " + ", ".join(sorted(unreachable))
        )


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
        if "include" in paths:
            raise RuntimeError(
                "distributable package still exposes the retired include tree"
            )
        packaged_files = tracked_files(source_root, paths)
        for relative in packaged_files:
            copy_file(source_root / relative, package_root / relative)

        packaged_names = {path.as_posix() for path in packaged_files}
        forbidden = sorted(set(RETIRED_PUBLIC_C_FILES) & packaged_names)
        if forbidden:
            raise RuntimeError(
                "distributable package contains retired public C files: "
                + ", ".join(forbidden)
            )

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

        check_public_closure(package_root)

        make_read_only(package_root)
        before = source_snapshot(package_root)

        global_cache = audit_root / "global-cache"
        (global_cache / "tmp").mkdir(parents=True)
        system_packages = audit_root / "system-packages"
        system_packages.mkdir()
        provided_packages = provide_system_packages(
            source_root,
            system_packages,
        )
        make_read_only(system_packages)
        environment = os.environ.copy()
        environment["ZIG_GLOBAL_CACHE_DIR"] = str(global_cache)
        environment.pop("ZIG_LOCAL_CACHE_DIR", None)
        # Zig 0.16's --system disables fetching and resolves every dependency
        # from this directory alone. It holds exactly the closure pinned in the
        # project manifest, so a build that reached for anything else -- an
        # unpinned package, or a transitive dependency nobody declared --
        # aborts before its build logic can execute.
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

        provided = {entry.name for entry in system_packages.iterdir()}
        if provided != provided_packages:
            raise RuntimeError(
                "Zig modified the system package directory: "
                + ", ".join(
                    sorted(provided.symmetric_difference(provided_packages))
                )
            )

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
        # Nothing may be fetched into the consumer's own cache: every
        # dependency has to have come from the pinned closure above.
        if resolved_packages:
            raise RuntimeError(
                "public module import fetched packages outside the pinned "
                "closure: " + ", ".join(sorted(resolved_packages))
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
