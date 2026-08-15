#!/usr/bin/env python3

import argparse
import pathlib
import shutil
import subprocess
import sys


SYMBOLS = (
    "rpmz_sqlite_confined_registry_anchor",
    "rpmz_sqlite_confined_open_at",
    "rpmz_sqlite_confined_close",
    "rpmz_sqlite_confined_verify",
    "rpmz_sqlite_confined_pin_main_fd",
    "rpmz_sqlite_confined_release_main_fd_pin",
)


def symbols(path: pathlib.Path, nm: str) -> list[str]:
    result = subprocess.run(
        [nm, "--defined-only", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []
    return [line.split()[-1] for line in result.stdout.splitlines() if line.split()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", required=True, type=pathlib.Path)
    args = parser.parse_args()
    nm = shutil.which("nm")
    if nm is None:
        print("error: nm is required for the confined SQLite singleton audit", file=sys.stderr)
        return 1

    audited = 0
    rpmz_seen = False
    for path in sorted(args.prefix.rglob("*")):
        if not path.is_file():
            continue
        try:
            with path.open("rb") as stream:
                if stream.read(4) != b"\x7fELF":
                    continue
        except OSError:
            continue
        defined = symbols(path, nm)
        counts = {symbol: defined.count(symbol) for symbol in SYMBOLS}
        if not any(counts.values()):
            continue
        audited += 1
        if path == args.prefix / "bin" / "rpmz":
            rpmz_seen = True
        for symbol, count in counts.items():
            if count != 1:
                print(
                    f"error: {path}: expected one {symbol}, found {count}",
                    file=sys.stderr,
                )
                return 1

    if not rpmz_seen:
        print(
            "error: installed rpmz does not contain the confined SQLite singleton",
            file=sys.stderr,
        )
        return 1
    print(f"confined SQLite singleton: {audited} ELF binaries, one registry each")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
