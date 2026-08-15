#!/usr/bin/env python3
"""Pin the public replay entry point to its local-only dependency boundary."""

import argparse
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
SOCKET_CALLS = (
    "socket",
    "socketpair",
    "connect",
    "bind",
    "listen",
    "accept",
    "accept4",
    "send",
    "sendto",
    "sendmsg",
    "recv",
    "recvfrom",
    "recvmsg",
    "shutdown",
    "getsockname",
    "getpeername",
    "getsockopt",
    "setsockopt",
    "getaddrinfo",
    "getnameinfo",
    "inet_pton",
    "inet_ntop",
)
SOCKET_CALL_PATTERN = "(?:" + "|".join(SOCKET_CALLS) + ")"
FORBIDDEN_STD_PATTERNS = (
    (
        re.compile(r"\bstd\s*\.\s*Io\s*\.\s*net\b"),
        "std.Io.net network namespace",
    ),
    (
        re.compile(r"\bstd\s*\.\s*net\b"),
        "std.net network namespace",
    ),
    (
        re.compile(
            "".join((
                r"\bstd\s*\.\s*posix\s*\.\s*",
                r"(?:system\s*\.\s*)?",
                SOCKET_CALL_PATTERN,
                r"\b",
            )),
            re.IGNORECASE,
        ),
        "std.posix socket API",
    ),
    (
        re.compile(
            r"\bstd\s*\.\s*c\s*\.\s*" + SOCKET_CALL_PATTERN + r"\b",
            re.IGNORECASE,
        ),
        "std.c socket API",
    ),
    (
        re.compile(
            "".join((
                r"\bstd\s*\.\s*os\s*\.\s*linux\s*\.\s*",
                SOCKET_CALL_PATTERN,
                r"\b",
            )),
            re.IGNORECASE,
        ),
        "std.os.linux socket API",
    ),
    (
        re.compile(
            "".join((
                r"\bstd\s*\.\s*os\s*\.\s*windows\s*\.\s*",
                r"(?:ws2_32\s*\.\s*)?",
                r"(?:WSA)?",
                SOCKET_CALL_PATTERN,
                r"\b",
            )),
            re.IGNORECASE,
        ),
        "std.os.windows socket API",
    ),
)


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


def audit_source(source: str) -> None:
    source = production_source(source)
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
    for pattern, description in FORBIDDEN_STD_PATTERNS:
        if pattern.search(lexical):
            raise RuntimeError(f"replay reaches forbidden {description}")


def expect_rejected(source: str, fixture: str, description: str) -> None:
    try:
        audit_source(production_source(source) + "\n" + fixture)
    except RuntimeError:
        return
    raise RuntimeError(f"socket self-test was accepted: {description}")


def self_test(source: str) -> None:
    audit_source(source)
    harmless = production_source(source) + (
        "\n// std.posix.socket is documentation, not a call.\n"
        'const harmless_text = "std.Io.net and std.net";\n'
    )
    audit_source(harmless)

    fixtures = (
        ("std.Io.net", "const attempt = std.Io.net;"),
        ("std.net", "const attempt = std.net;"),
        ("std.posix.socket", "const attempt = std.posix.socket;"),
        ("std.posix.connect", "const attempt = std.posix.connect;"),
        (
            "std.posix.system.socket",
            "const attempt = std.posix.system.socket;",
        ),
        ("std.c.socket", "const attempt = std.c.socket;"),
        ("std.c.connect", "const attempt = std.c.connect;"),
        ("std.os.linux.socket", "const attempt = std.os.linux.socket;"),
        ("std.os.linux.sendmsg", "const attempt = std.os.linux.sendmsg;"),
        (
            "std.os.windows.ws2_32.WSAConnect",
            "const attempt = std.os.windows.ws2_32.WSAConnect;",
        ),
    )
    for description, fixture in fixtures:
        expect_rejected(source, fixture, description)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        source = REPLAY.read_text(encoding="utf-8")
        if args.self_test:
            self_test(source)
            print("Replay confinement audit self-tests passed")
        else:
            audit_source(source)
            print(
                "Replay confinement audit passed "
                "(direct imports, network namespaces, and socket APIs)"
            )
    except (OSError, RuntimeError) as error:
        print(f"replay confinement audit failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
