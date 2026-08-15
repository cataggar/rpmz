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
SOCKET_SYMBOL_PATTERN = "(?:__)?(?:WSA)?" + SOCKET_CALL_PATTERN
FORBIDDEN_STD_PATTERNS = (
    (
        re.compile(r"\bstd\s*\.\s*http\b"),
        "std.http network namespace",
    ),
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


def strip_comments(source: str) -> str:
    def preserve_lines(match):
        return "\n" * match.group(0).count("\n")

    source = re.sub(r"/\*.*?\*/", preserve_lines, source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def strip_literals(source: str) -> str:
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    return re.sub(r"'(?:\\.|[^'\\])*'", "''", source)


def lexical_source(source: str) -> str:
    source = strip_comments(source)
    source = re.sub(
        r'@import\(\s*"std"\s*\)',
        "std",
        source,
    )
    return strip_literals(source)


def struct_fields(source: str, name: str) -> list[str]:
    match = re.search(
        r"\bpub\s+const\s+" + re.escape(name) + r"\s*=\s*struct\s*\{(.*?)\n\};",
        source,
        flags=re.S,
    )
    if match is None:
        raise RuntimeError(f"unable to find public {name} struct")
    return re.findall(r"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", match.group(1))


def simple_const_aliases(source: str) -> dict[str, str]:
    aliases = {}
    pattern = re.compile(
        r"(?m)^\s*(?:pub\s+)?const\s+"
        r"([A-Za-z_][A-Za-z0-9_]*)"
        r"(?:\s*:\s*[^=;\n]+)?\s*=\s*"
        r"([A-Za-z_][A-Za-z0-9_]*"
        r"(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*;"
    )
    for name, value in pattern.findall(source):
        aliases[name] = re.sub(r"\s+", "", value)
    return aliases


def resolve_alias(path: str, aliases: dict[str, str]) -> str:
    parts = re.sub(r"\s+", "", path).split(".")
    visited = set()
    while parts and parts[0] in aliases and parts[0] not in visited:
        name = parts[0]
        visited.add(name)
        parts = aliases[name].split(".") + parts[1:]
    return ".".join(parts)


def dotted_paths(source: str) -> list[str]:
    return re.findall(
        r"\b[A-Za-z_][A-Za-z0-9_]*"
        r"(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)+\b",
        source,
    )


def reject_network_paths(lexical: str) -> None:
    aliases = simple_const_aliases(lexical)
    for path in dotted_paths(lexical):
        resolved = resolve_alias(path, aliases)
        for pattern, description in FORBIDDEN_STD_PATTERNS:
            if pattern.search(resolved):
                raise RuntimeError(
                    f"replay reaches forbidden {description} via {path}"
                )


def reject_foreign_socket_apis(lexical: str) -> None:
    if re.search(r"@cImport\s*\(", lexical):
        raise RuntimeError("replay closure contains @cImport")
    extern_socket = re.search(
        "".join((
            r"\bextern\s+(?:\"\"\s+)?fn\s+",
            SOCKET_SYMBOL_PATTERN,
            r"\b",
        )),
        lexical,
        flags=re.IGNORECASE,
    )
    if extern_socket:
        raise RuntimeError(
            "replay closure declares socket-related extern function {}".format(
                extern_socket.group(0)
            )
        )


def audit_source(source: str) -> None:
    source = production_source(source)
    comments_removed = strip_comments(source)
    imports = set(
        re.findall(r'@import\(\s*"([^"]+)"\s*\)', comments_removed)
    )
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

    lexical = lexical_source(source)
    for identifier in sorted(FORBIDDEN_IDENTIFIERS):
        if re.search(r"\b" + re.escape(identifier) + r"\b", lexical):
            raise RuntimeError(
                f"replay reaches forbidden network dependency: {identifier}"
            )
    reject_network_paths(lexical)
    reject_foreign_socket_apis(lexical)


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
        'const harmless_text = "std.Io.net, @cImport, and extern fn socket";\n'
        "const fmt_alias = std.fmt;\n"
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
        (
            "std.posix alias",
            "const posix = std.posix;\nconst attempt = posix.socket;",
        ),
        (
            "chained std.posix alias",
            "const standard = std;\n"
            "const posix = standard.posix;\n"
            "const attempt = posix.connect;",
        ),
        (
            "std.c alias",
            "const libc = std.c;\nconst attempt = libc.socket;",
        ),
        (
            "std.os.linux alias",
            "const linux = std.os.linux;\nconst attempt = linux.connect;",
        ),
        (
            "std.http alias",
            "const http = std.http;\nconst attempt = http.Client;",
        ),
        (
            "@import std alias",
            'const standard = @import("std");\n'
            "const attempt = standard.posix.socket;",
        ),
        (
            "std.Io.net alias",
            "const network = std.Io.net;\nconst attempt = network;",
        ),
        (
            "std.net alias",
            "const network = std.net;\nconst attempt = network;",
        ),
        (
            "@cImport c.socket",
            'const c = @cImport({ @cInclude("sys/socket.h"); });\n'
            "const attempt = c.socket;",
        ),
        (
            "@cImport c.connect",
            'const c = @cImport({ @cInclude("sys/socket.h"); });\n'
            "const attempt = c.connect;",
        ),
        (
            "extern fn socket",
            "extern fn socket(domain: c_int, kind: c_int) c_int;",
        ),
        (
            'extern "c" fn connect',
            'extern "c" fn connect(fd: c_int) c_int;',
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
                "(imports, aliases, foreign APIs, and network namespaces)"
            )
    except (OSError, RuntimeError) as error:
        print(f"replay confinement audit failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
