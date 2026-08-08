#!/usr/bin/env python3
"""Reject libsolv dependencies and implementation symbols in installed ELF files."""

import re
import subprocess
import sys
from pathlib import Path


LIBSOLV_SYMBOLS = {
    "pool_create",
    "pool_free",
    "pool_set_installed",
    "pool_setarch",
    "pool_whatprovides",
    "repo_add_rpm",
    "repo_add_rpmdb",
    "repo_add_solv",
    "repo_create",
    "repo_free",
    "repo_internalize",
    "solv_chksum_create",
    "solv_xfopen",
    "solver_create",
    "solver_free",
    "solver_problem_count",
    "solver_solve",
}


def output(command):
    result = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(
            f"{' '.join(command)} failed: {result.stderr.strip()}"
        )
    return result.stdout


def is_elf(path):
    with path.open("rb") as stream:
        return stream.read(4) == b"\x7fELF"


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} INSTALL_PREFIX")
    prefix = Path(sys.argv[1])
    elf_paths = [
        path
        for path in sorted(prefix.rglob("*"))
        if path.is_file() and is_elf(path)
    ]
    errors = []
    for path in elf_paths:
        dynamic = output(["readelf", "-d", "--", str(path)])
        if re.search(r"libsolv(?:ext)?\.so", dynamic, re.IGNORECASE):
            errors.append(f"{path}: links a libsolv shared library")
        symbols = output(["nm", "--defined-only", "--", str(path)])
        for line in symbols.splitlines():
            fields = line.split()
            if fields and fields[-1] in LIBSOLV_SYMBOLS:
                errors.append(f"{path}: contains libsolv symbol {fields[-1]}")

    if errors:
        message = "installed ELF libsolv artifact audit failed:\n  "
        raise SystemExit(message + "\n  ".join(errors))
    print(
        f"installed ELF libsolv artifact audit passed "
        f"({len(elf_paths)} ELF files)"
    )


if __name__ == "__main__":
    main()
