#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = ROOT / "scripts" / "abi-baseline.json"
PUBLIC_SYMBOL = re.compile(
    r"^(?:TDNF[A-Za-z0-9_]*|tdnf_rpm_config_[A-Za-z0-9_]*)$"
)
COMPATIBILITY_HEADERS = (
    ROOT / "plugins" / "metalink" / "xml.h",
)
EXPECTED_SONAMES = {
    "libtdnf": "libtdnf.so.4",
    "libtdnfcli": "libtdnfcli.so.4",
}


def artifact_paths(prefix):
    lib_dir = prefix / "lib"

    def versioned_library(stem):
        candidates = sorted(
            lib_dir.glob(f"{stem}.so.*"),
            key=lambda path: (path.name.count("."), len(path.name), path.name),
        )
        if not candidates:
            raise FileNotFoundError(f"{lib_dir}/{stem}.so.*")
        return candidates[-1]

    return {
        "libtdnf": versioned_library("libtdnf"),
        "libtdnfcli": versioned_library("libtdnfcli"),
        "libtdnfmetalink": (
            lib_dir / "tdnf-plugins" / "libtdnfmetalink.so"
        ),
        "libtdnfrepogpgcheck": (
            lib_dir / "tdnf-plugins" / "libtdnfrepogpgcheck.so"
        ),
    }


def public_symbols(path):
    result = subprocess.run(
        ["nm", "-D", "--defined-only", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    symbols = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if not fields:
            continue
        symbol = fields[-1].split("@", 1)[0]
        if PUBLIC_SYMBOL.fullmatch(symbol):
            symbols.add(symbol)
    return sorted(symbols)


def all_dynamic_symbols(path):
    result = subprocess.run(
        ["nm", "-D", "--defined-only", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    symbols = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        symbols.add(fields[-1].split("@", 1)[0])
    return symbols


# libsolv and SQLite are linked statically into libtdnf. Nothing in this
# repository references them through libtdnf, and exporting them is a
# correctness problem rather than untidiness: ELF symbol resolution is
# global and first-wins, so libtdnf.so can interpose on a real
# libsolv.so/libsqlite3.so loaded into the same process, or be
# interposed by one. Both have ABI-sensitive structs, so the failure
# mode is memory corruption, not a clean error.
#
# The guard is the "exported_symbols_libtdnf" baseline above rather than
# a pattern: a prefix rule has to guess at third-party naming, and the
# first attempt at one here matched a tdnf symbol (common/'s hash_ops)
# while missing 49 libsolv symbols. An exact snapshot cannot do either.
# client/libtdnf.map is what actually enforces the hiding.


def dynamic_soname(path):
    result = subprocess.run(
        ["readelf", "-d", "--", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    match = re.search(r"\(SONAME\).*\[([^\]]+)\]", result.stdout)
    if not match:
        raise ValueError(f"{path}: missing DT_SONAME")
    return match.group(1)


def check_history_goal_compatibility(prefix):
    cache_dir = ROOT / ".zig-cache" / "abi-history-goal"
    cache_dir.mkdir(parents=True, exist_ok=True)
    source = cache_dir / "consumer.c"
    executable = cache_dir / "consumer"
    source.write_text(
        """
#include <stdint.h>
extern uint32_t TDNFHistoryGoal(void *, void *, void *, void **);
int main(void)
{
    void *result = 0;
    return TDNFHistoryGoal(0, 0, 0, &result) == 1622 ? 0 : 1;
}
""",
        encoding="utf-8",
    )
    try:
        subprocess.run(
            [
                "zig", "cc", str(source),
                f"-L{prefix / 'lib'}", "-ltdnf",
                f"-Wl,-rpath,{prefix / 'lib'}",
                "-o", str(executable),
            ],
            check=True,
        )
        subprocess.run([str(executable)], check=True)
    finally:
        executable.unlink(missing_ok=True)
        source.unlink(missing_ok=True)
        cache_dir.rmdir()


def header_hashes(headers_dir):
    headers = sorted(headers_dir.glob("*.h"))
    if not headers:
        raise FileNotFoundError(f"{headers_dir}/*.h")
    return {
        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
        for path in headers
    }


def compatibility_header_hashes():
    return {
        str(path.relative_to(ROOT)): hashlib.sha256(
            path.read_bytes()
        ).hexdigest()
        for path in COMPATIBILITY_HEADERS
    }


def collect_snapshot(prefix, headers_dir):
    artifacts = artifact_paths(prefix)
    for path in artifacts.values():
        if not path.is_file():
            raise FileNotFoundError(path)
    for name, expected in EXPECTED_SONAMES.items():
        actual = dynamic_soname(artifacts[name])
        if actual != expected:
            raise ValueError(
                f"{artifacts[name]}: DT_SONAME is {actual}, "
                f"expected {expected}"
            )
    return {
        "compatibility_headers_sha256": compatibility_header_hashes(),
        "public_headers_sha256": header_hashes(headers_dir),
        "public_symbols": {
            name: public_symbols(path)
            for name, path in artifacts.items()
        },
        # Every dynamic symbol libtdnf exports, not just the TDNF*-named
        # ones "public_symbols" tracks. libtdnf statically links vendored
        # libsolv and SQLite, and used to re-export all 632 of their
        # symbols; client/libtdnf.map now hides them. Snapshotting the
        # whole table is what makes that enforceable -- a prefix-matching
        # rule has to guess at third-party naming, and guessing left 49
        # libsolv symbols uncovered when this was first written.
        "exported_symbols_libtdnf": sorted(
            all_dynamic_symbols(artifacts["libtdnf"])
        ),
    }


def load_snapshot(path):
    with path.open(encoding="utf-8") as stream:
        snapshot = json.load(stream)
    if set(snapshot) != {
        "compatibility_headers_sha256",
        "public_headers_sha256",
        "public_symbols",
        "exported_symbols_libtdnf",
    }:
        raise ValueError(f"{path}: invalid ABI baseline keys")
    return snapshot


def compare_maps(label, expected, actual):
    errors = []
    expected_keys = set(expected)
    actual_keys = set(actual)
    for key in sorted(expected_keys - actual_keys):
        errors.append(f"{label}: removed {key}")
    for key in sorted(actual_keys - expected_keys):
        errors.append(f"{label}: added {key}")
    for key in sorted(expected_keys & actual_keys):
        if expected[key] != actual[key]:
            errors.append(f"{label}: changed {key}")
    return errors


# Symbol families that libtdnf.map never lists as global. A couple of
# these leaking would be a real regression worth naming individually; a
# whole family leaking at once means the export filter was not applied
# to the link at all, and listing every symbol buries that fact under
# hundreds of lines that each blame the wrong thing.
FILTER_DROP_MARKERS = (
    ("sqlite3_", "SQLite"),
    ("__ubsan_handle_", "UBSan runtime"),
)

FILTER_DROP_THRESHOLD = 10


def export_filter_dropped(exports):
    """Name the symbol families proving the export filter never ran.

    Returns [] when the filter is in force, so a genuine one-off leak
    still gets its own per-symbol diagnostic below.
    """
    dropped = []
    for prefix, description in FILTER_DROP_MARKERS:
        count = sum(1 for symbol in exports if symbol.startswith(prefix))
        if count > FILTER_DROP_THRESHOLD:
            dropped.append(f"{count} {description} symbols ({prefix}*)")
    return dropped


def compare_snapshots(expected, actual):
    # A missing export filter invalidates every libtdnf comparison below,
    # producing hundreds of errors that each blame the wrong thing. Say
    # why once, first, and stop.
    dropped = export_filter_dropped(
        set(actual["exported_symbols_libtdnf"])
    )
    if dropped:
        return [
            "libtdnf exports " + ", ".join(dropped) + ". The whole export "
            "filter is missing, so client/libtdnf.map is not at fault -- "
            "the linker never received it. zig passes --version-script to "
            "`zig build-lib` but does not forward it to `zig ld`, its "
            "self-hosted ELF linker, which it selects for this library in "
            "Debug builds. Rebuild with -Doptimize=ReleaseSafe, which is "
            "what CI uses and what links libtdnf through LLD."
        ]
    errors = compare_maps(
        "compatibility header",
        expected["compatibility_headers_sha256"],
        actual["compatibility_headers_sha256"],
    )
    errors.extend(
        compare_maps(
            "public header",
            expected["public_headers_sha256"],
            actual["public_headers_sha256"],
        )
    )
    expected_symbols = expected["public_symbols"]
    actual_symbols = actual["public_symbols"]
    errors.extend(
        compare_maps("artifact", expected_symbols, actual_symbols)
    )
    for artifact in sorted(set(expected_symbols) & set(actual_symbols)):
        expected_set = set(expected_symbols[artifact])
        actual_set = set(actual_symbols[artifact])
        for symbol in sorted(expected_set - actual_set):
            errors.append(f"{artifact}: removed symbol {symbol}")
        for symbol in sorted(actual_set - expected_set):
            errors.append(f"{artifact}: added symbol {symbol}")
    # The full libtdnf export table. Catches a vendored libsolv/SQLite
    # symbol reappearing in the dynamic table, which the TDNF*-only
    # "public_symbols" comparison above is blind to by construction.
    expected_exports = set(expected["exported_symbols_libtdnf"])
    actual_exports = set(actual["exported_symbols_libtdnf"])
    for symbol in sorted(expected_exports - actual_exports):
        errors.append(f"libtdnf: no longer exports {symbol}")
    for symbol in sorted(actual_exports - expected_exports):
        errors.append(
            f"libtdnf: newly exports {symbol} -- if this is a vendored "
            "libsolv or SQLite symbol it must be hidden, see "
            "client/libtdnf.map"
        )
    return errors


def render_summary(snapshot):
    headers = len(snapshot["public_headers_sha256"])
    compatibility_headers = len(
        snapshot["compatibility_headers_sha256"]
    )
    lines = [
        "| ABI surface | Count |",
        "|---|---:|",
        f"| Public headers | {headers} |",
        f"| Internal compatibility headers | {compatibility_headers} |",
    ]
    for artifact, symbols in snapshot["public_symbols"].items():
        lines.append(f"| `{artifact}` public symbols | {len(symbols)} |")
    return "\n".join(lines)


def append_github_summary(table):
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    with open(summary_path, "a", encoding="utf-8") as stream:
        stream.write("## Public ABI audit\n\n")
        stream.write(table)
        stream.write("\n")


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Compare public TDNF headers and exported symbols with the "
            "checked-in ABI baseline."
        )
    )
    parser.add_argument(
        "--prefix",
        type=Path,
        default=ROOT / "out",
        help="installed build prefix",
    )
    parser.add_argument(
        "--headers-dir",
        type=Path,
        default=ROOT / "include",
        help="directory containing public headers",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        default=DEFAULT_BASELINE,
        help="ABI baseline JSON path",
    )
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="replace the baseline with the current snapshot",
    )
    args = parser.parse_args()

    try:
        actual = collect_snapshot(args.prefix.resolve(), args.headers_dir)
        check_history_goal_compatibility(args.prefix.resolve())
        if args.update_baseline:
            with args.baseline.open("w", encoding="utf-8") as stream:
                json.dump(actual, stream, indent=2, sort_keys=True)
                stream.write("\n")
        expected = load_snapshot(args.baseline)
    except (
        OSError,
        subprocess.CalledProcessError,
        ValueError,
    ) as error:
        print(f"ABI audit failed: {error}", file=sys.stderr)
        return 2

    table = render_summary(actual)
    append_github_summary(table)
    print(table)

    errors = compare_snapshots(expected, actual)
    if errors:
        for error in errors:
            print(f"ABI regression: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
