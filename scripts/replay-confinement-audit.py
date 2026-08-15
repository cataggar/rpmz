#!/usr/bin/env python3
"""Pin the public replay entry point to its local-only dependency boundary."""

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPLAY = ROOT / "client" / "replay.zig"
ALLOWED_IMPORTS = {
    "std",
    "builtin",
    "client_abi",
    "bundle_reader",
    "bundle_selection",
    "canonical_json",
    "content_digest",
    "transaction.zig",
    "repomd_client_exports",
    "rpm_gpgcheck",
    "rpm_header",
    "transaction_bundle",
    "transaction_lock",
    "transaction_plan",
    "rpm_txn_config",
    "verified_fetch",
}
ALLOWED_VERIFIED_FETCH_MEMBERS = {"verifyOpen"}
ALLOWED_REPOMD_MEMBERS = {
    "available_repository_loader",
    "solver_rules",
}
FORBIDDEN_IDENTIFIERS = {
    "client_download",
    "remoterepo",
    "fetchVerified",
    "fetchToFile",
    "curl",
}


def production_source(source: str) -> str:
    first_test = re.search(r'(?m)^test\s+"', source)
    return source if first_test is None else source[:first_test.start()]


def strip_comments_and_literals(source: str) -> str:
    def preserve_lines(match):
        return "\n" * match.group(0).count("\n")

    source = re.sub(r"/\*.*?\*/", preserve_lines, source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    return source


def struct_fields(source: str, name: str) -> list[str]:
    match = re.search(
        r"\bpub\s+const\s+" + re.escape(name) + r"\s*=\s*struct\s*\{(.*?)\n\};",
        source,
        flags=re.S,
    )
    if match is None:
        raise RuntimeError(f"unable to find public {name} struct")
    return re.findall(r"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", match.group(1))


def main() -> int:
    try:
        source = production_source(REPLAY.read_text(encoding="utf-8"))
        imports = set(re.findall(r'@import\(\s*"([^"]+)"\s*\)', source))
        if imports != ALLOWED_IMPORTS:
            added = sorted(imports - ALLOWED_IMPORTS)
            removed = sorted(ALLOWED_IMPORTS - imports)
            raise RuntimeError(
                f"replay import boundary changed; added={added}, removed={removed}"
            )

        if struct_fields(source, "Input") != ["bundle_directory", "target"]:
            raise RuntimeError("replay Input gained an ambient input")
        if struct_fields(source, "Target") != [
            "install_root",
            "rpmdb_path",
            "architecture",
        ]:
            raise RuntimeError("replay Target gained an ambient input")

        verified_members = set(
            re.findall(r"\bverified_fetch\.([A-Za-z_][A-Za-z0-9_]*)", source)
        )
        if verified_members != ALLOWED_VERIFIED_FETCH_MEMBERS:
            raise RuntimeError(
                "replay verified-fetch usage changed: {}".format(
                    ", ".join(sorted(verified_members))
                )
            )

        repomd_members = set(
            re.findall(r"\brepomd\.([A-Za-z_][A-Za-z0-9_]*)", source)
        )
        if repomd_members != ALLOWED_REPOMD_MEMBERS:
            raise RuntimeError(
                "replay repomd usage changed: {}".format(
                    ", ".join(sorted(repomd_members))
                )
            )

        lexical = strip_comments_and_literals(source)
        for identifier in sorted(FORBIDDEN_IDENTIFIERS):
            if re.search(r"\b" + re.escape(identifier) + r"\b", lexical):
                raise RuntimeError(
                    f"replay reaches forbidden network dependency: {identifier}"
                )
        if re.search(r"\bstd\s*\.\s*http\b", lexical):
            raise RuntimeError("replay reaches std.http")
    except (OSError, RuntimeError) as error:
        print(f"replay confinement audit failed: {error}", file=sys.stderr)
        return 1

    print(
        "Replay confinement audit passed "
        "(direct imports and network-adjacent calls)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
