#!/usr/bin/env python3
"""Pin the public replay entry point to its local-only dependency boundary."""

import argparse
from dataclasses import dataclass
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
    "rpm_package_test",
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
FORBIDDEN_REFLECTION_BUILTINS = (
    "field",
    "fieldParentPtr",
    "hasDecl",
    "hasField",
    "typeInfo",
    "Type",
    "TypeOf",
    "unionInit",
)
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
SOCKET_SYMBOL_PATTERN = (
    "(?:__)?(?:WSA)?" + SOCKET_CALL_PATTERN + "(?:A|W)?"
)
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


@dataclass(frozen=True)
class StringToken:
    start: int
    end: int
    value: str


@dataclass(frozen=True)
class Lexed:
    code: str
    strings: tuple[StringToken, ...]


def masked(text: str) -> str:
    return "".join("\n" if character == "\n" else " " for character in text)


def decode_escape(source: str, index: int) -> tuple[str, int]:
    if index >= len(source):
        return "", index
    character = source[index]
    escapes = {
        "n": "\n",
        "r": "\r",
        "t": "\t",
        "\\": "\\",
        '"': '"',
        "'": "'",
        "0": "\0",
    }
    if character in escapes:
        return escapes[character], index + 1
    if character == "x" and index + 2 < len(source):
        digits = source[index + 1:index + 3]
        if re.fullmatch(r"[0-9A-Fa-f]{2}", digits):
            return chr(int(digits, 16)), index + 3
    if character == "u" and index + 1 < len(source) and source[index + 1] == "{":
        close = source.find("}", index + 2)
        if close >= 0:
            digits = source[index + 2:close]
            if digits and re.fullmatch(r"[0-9A-Fa-f]+", digits):
                value = int(digits, 16)
                if value <= 0x10FFFF:
                    return chr(value), close + 1
    return character, index + 1


def read_quoted(
    source: str,
    quote_index: int,
    quote: str,
) -> tuple[int, str]:
    value = []
    index = quote_index + 1
    while index < len(source):
        character = source[index]
        if character == quote:
            return index + 1, "".join(value)
        if character == "\\":
            decoded, index = decode_escape(source, index + 1)
            value.append(decoded)
            continue
        value.append(character)
        index += 1
    return len(source), "".join(value)


def lex_zig(source: str) -> Lexed:
    output = []
    strings = []
    index = 0
    while index < len(source):
        if source.startswith("//", index):
            end = source.find("\n", index + 2)
            if end < 0:
                end = len(source)
            output.append(masked(source[index:end]))
            index = end
            continue
        if source.startswith("/*", index):
            depth = 1
            end = index + 2
            while end < len(source) and depth != 0:
                if source.startswith("/*", end):
                    depth += 1
                    end += 2
                elif source.startswith("*/", end):
                    depth -= 1
                    end += 2
                else:
                    end += 1
            output.append(masked(source[index:end]))
            index = end
            continue
        if source.startswith("\\\\", index):
            end = source.find("\n", index + 2)
            if end < 0:
                end = len(source)
            output.append(masked(source[index:end]))
            index = end
            continue
        if source.startswith('@"', index):
            end, value = read_quoted(source, index + 1, '"')
            length = end - index
            rendered = value if re.fullmatch(
                r"[A-Za-z_][A-Za-z0-9_]*",
                value,
            ) else ""
            output.append(rendered[:length].ljust(length))
            index = end
            continue
        if source[index] == '"':
            end, value = read_quoted(source, index, '"')
            strings.append(StringToken(index, end, value))
            output.append(masked(source[index:end]))
            index = end
            continue
        if source[index] == "'":
            end, _ = read_quoted(source, index, "'")
            output.append(masked(source[index:end]))
            index = end
            continue
        output.append(source[index])
        index += 1
    return Lexed("".join(output), tuple(strings))


def import_calls(lexed: Lexed) -> list[tuple[int, int, str]]:
    calls = []
    for match in re.finditer(r"@import\s*\(", lexed.code):
        opening = lexed.code.find("(", match.start(), match.end())
        close = matching_parenthesis(lexed.code, opening)
        if close is None:
            raise RuntimeError("replay closure contains malformed @import")
        tokens = [
            token
            for token in lexed.strings
            if opening < token.start and token.end <= close
        ]
        body = lexed.code[opening + 1:close]
        if len(tokens) != 1 or body.strip():
            raise RuntimeError(
                "every replay @import must contain exactly one literal string"
            )
        calls.append((match.start(), close + 1, tokens[0].value))
    return calls


def expand_std_imports(
    code: str,
    calls: list[tuple[int, int, str]],
) -> str:
    output = list(code)
    for start, end, value in calls:
        if value != "std":
            continue
        output[start:end] = list("std".ljust(end - start))
    return "".join(output)


def struct_fields(source: str, name: str) -> list[str]:
    match = re.search(
        r"\bpub\s+const\s+" + re.escape(name) + r"\s*=\s*struct\s*\{(.*?)\n\};",
        source,
        flags=re.S,
    )
    if match is None:
        raise RuntimeError(f"unable to find public {name} struct")
    return re.findall(r"(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:", match.group(1))


def unwrap_parentheses(expression: str) -> str:
    expression = re.sub(r"\s+", "", expression)
    while expression.startswith("(") and expression.endswith(")"):
        depth = 0
        wraps_all = True
        for index, character in enumerate(expression):
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0 and index != len(expression) - 1:
                    wraps_all = False
                    break
            if depth < 0:
                wraps_all = False
                break
        if not wraps_all or depth != 0:
            break
        expression = expression[1:-1]
    previous = None
    while previous != expression:
        previous = expression
        expression = re.sub(
            r"\(([A-Za-z_][A-Za-z0-9_]*)\)",
            r"\1",
            expression,
        )
    return expression


def simple_const_aliases(source: str) -> dict[str, str]:
    aliases = {}
    pattern = re.compile(
        r"(?m)^\s*(?:pub\s+)?const\s+"
        r"([A-Za-z_][A-Za-z0-9_]*)"
        r"(?:\s*:\s*[^=;\n]+)?\s*=\s*"
        r"([^;\n]+)\s*;"
    )
    for name, value in pattern.findall(source):
        value = unwrap_parentheses(value)
        if re.fullmatch(
            r"[A-Za-z_][A-Za-z0-9_]*"
            r"(?:\.[A-Za-z_][A-Za-z0-9_]*)*",
            value,
        ):
            aliases[name] = value
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


def normalize_member_parentheses(source: str) -> str:
    pattern = re.compile(
        r"\(\s*("
        r"[A-Za-z_][A-Za-z0-9_]*"
        r"(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*"
        r")\s*\)"
    )
    previous = None
    while previous != source:
        previous = source
        source = pattern.sub(
            lambda match: re.sub(r"\s+", "", match.group(1)),
            source,
        )
    return source


def reject_network_paths(lexical: str) -> None:
    normalized = normalize_member_parentheses(lexical)
    aliases = simple_const_aliases(normalized)
    for path in dotted_paths(normalized):
        resolved = resolve_alias(path, aliases)
        for pattern, description in FORBIDDEN_STD_PATTERNS:
            if pattern.search(resolved):
                raise RuntimeError(
                    f"replay reaches forbidden {description} via {path}"
                )


def matching_parenthesis(code: str, opening: int) -> int | None:
    if opening < 0:
        return None
    depth = 0
    for index in range(opening, len(code)):
        if code[index] == "(":
            depth += 1
        elif code[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


def reject_foreign_socket_apis(lexical: str) -> None:
    if re.search(r"@cImport\s*\(", lexical):
        raise RuntimeError("replay closure contains @cImport")
    if re.search(r"@extern\s*\(", lexical):
        raise RuntimeError("replay closure contains @extern")
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
    lexed = lex_zig(source)
    calls = import_calls(lexed)
    imports = {value for _, _, value in calls}
    if imports != ALLOWED_IMPORTS:
        added = sorted(imports - ALLOWED_IMPORTS)
        removed = sorted(ALLOWED_IMPORTS - imports)
        raise RuntimeError(
            f"replay import boundary changed; added={added}, removed={removed}"
        )

    lexical = expand_std_imports(lexed.code, calls)
    if struct_fields(lexical, "Input") != ["bundle_directory", "target"]:
        raise RuntimeError("replay Input gained an ambient input")
    if struct_fields(lexical, "Target") != [
        "install_root",
        "rpmdb_path",
        "architecture",
    ]:
        raise RuntimeError("replay Target gained an ambient input")

    verified_members = set(
        re.findall(r"\bverified_fetch\.([A-Za-z_][A-Za-z0-9_]*)", lexical)
    )
    if verified_members != ALLOWED_VERIFIED_FETCH_MEMBERS:
        raise RuntimeError(
            "replay verified-fetch usage changed: {}".format(
                ", ".join(sorted(verified_members))
            )
        )

    repomd_members = set(
        re.findall(r"\brepomd\.([A-Za-z_][A-Za-z0-9_]*)", lexical)
    )
    if repomd_members != ALLOWED_REPOMD_MEMBERS:
        raise RuntimeError(
            "replay repomd usage changed: {}".format(
                ", ".join(sorted(repomd_members))
            )
        )

    for identifier in sorted(FORBIDDEN_IDENTIFIERS):
        if re.search(r"\b" + re.escape(identifier) + r"\b", lexical):
            raise RuntimeError(
                f"replay reaches forbidden network dependency: {identifier}"
            )
    for builtin in FORBIDDEN_REFLECTION_BUILTINS:
        if re.search(r"@" + re.escape(builtin) + r"\s*\(", lexical):
            raise RuntimeError(
                f"replay closure contains dynamic reflection builtin @{builtin}"
            )
    reject_network_paths(lexical)
    reject_foreign_socket_apis(lexical)


def expect_rejected(source: str, fixture: str, description: str) -> None:
    try:
        audit_source(source + "\n" + fixture)
    except RuntimeError:
        return
    raise RuntimeError(f"socket self-test was accepted: {description}")


def self_test(source: str) -> None:
    audit_source(source)
    harmless = source + (
        "\n// std.posix.socket is documentation, not a call.\n"
        'const harmless_text = "std.Io.net // @cImport extern fn socket";\n'
        'const escaped_text = "quote: \\" // std.net.connect";\n'
        "const multiline_text =\n"
        "    \\\\std.posix.socket // remains string content\n"
        "    \\\\extern fn @\"connect\" and @cImport\n"
        ";\n"
        'const @"socket" = 1;\n'
        "const fmt_alias = std.fmt;\n"
        'const harmless_name = .{ .name = "socket" };\n'
        'const extern_text = "@extern name = \\"WSASocketW\\"";\n'
        'const field_text = "@field(std.posix, \\"socket\\")";\n'
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
            "parenthesized std.posix alias",
            "const posix = (std.posix);\nconst attempt = posix.socket;",
        ),
        (
            "parenthesized member base",
            "const attempt = (std.posix).connect;",
        ),
        (
            "parenthesized alias member base",
            "const posix = std.posix;\nconst attempt = (posix).socket;",
        ),
        (
            "nested parenthesized member base",
            "const posix = (std.posix);\n"
            "const attempt = ((((posix)))).getaddrinfo;",
        ),
        (
            "chained std.posix alias",
            "const standard = ((std));\n"
            "const posix = (standard.posix);\n"
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
            "computed std import concatenation",
            'const standard = @import("st" ++ "d");',
        ),
        (
            "computed std import name",
            'const module_name = "std";\n'
            "const standard = @import(module_name);",
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
            "const libc = c;\n"
            "const attempt = libc.socket;",
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
            "extern fn getaddrinfo",
            "extern fn getaddrinfo(node: [*:0]const u8) c_int;",
        ),
        (
            'extern "c" fn connect',
            'extern "c" fn connect(fd: c_int) c_int;',
        ),
        (
            'extern fn @"socket"',
            'extern fn @"socket"(domain: c_int, kind: c_int) c_int;',
        ),
        (
            'extern fn @"connect"',
            'extern fn @"connect"(fd: c_int) c_int;',
        ),
        (
            'extern fn @"getaddrinfo"',
            'extern fn @"getaddrinfo"(node: [*:0]const u8) c_int;',
        ),
        (
            'extern fn @"sock\\x65t"',
            'extern fn @"sock\\x65t"(domain: c_int) c_int;',
        ),
        (
            'extern fn @"WSASocketW"',
            'extern fn @"WSASocketW"(af: c_int) c_int;',
        ),
        (
            'extern fn @"WSAConnectA"',
            'extern fn @"WSAConnectA"(socket_handle: usize) c_int;',
        ),
        (
            'extern fn @"GetAddrInfoW"',
            'extern fn @"GetAddrInfoW"(node: [*:0]const u16) c_int;',
        ),
        (
            "double slash inside string before socket code",
            'const text = "not // a comment"; '
            "const attempt = std.posix.socket;",
        ),
        (
            "escaped quote inside string before socket code",
            'const text = "escaped \\" // still text"; '
            "const attempt = std.posix.connect;",
        ),
        (
            "multiline string before socket code",
            "const text =\n"
            "    \\\\std.posix.socket // string content\n"
            ";\n"
            "const attempt = std.posix.connect;",
        ),
        (
            "@extern socket",
            "const attempt = @extern(*const fn () c_int, .{\n"
            '    .name = "socket",\n'
            "});",
        ),
        (
            "@extern escaped connect",
            "const attempt = @extern(*const fn () c_int, .{\n"
            '    .name = "conn\\x65ct",\n'
            "});",
        ),
        (
            "@extern getaddrinfo",
            "const attempt = @extern(*const fn () c_int, .{\n"
            '    .name = "getaddrinfo",\n'
            "});",
        ),
        (
            "@extern WSASocketW",
            "const attempt = @extern(*const fn () c_int, .{\n"
            '    .name = "WSASocketW",\n'
            "});",
        ),
        (
            "@extern WSAConnectA",
            "const attempt = @extern(*const fn () c_int, .{\n"
            '    .name = "WSAConnectA",\n'
            "});",
        ),
        (
            "@extern escaped GetAddrInfoW",
            "const attempt = @extern(*const fn () c_int, .{\n"
            '    .name = "GetAddrInfo\\x57",\n'
            "});",
        ),
        (
            "computed @extern socket name",
            'const symbol_name = "socket";\n'
            "const attempt = @extern(*const fn () c_int, .{\n"
            "    .name = symbol_name,\n"
            "});",
        ),
        (
            "@field networking",
            'const attempt = @field(std.posix, "socket");',
        ),
        (
            "@field networking through alias",
            "const posix = std.posix;\n"
            'const attempt = @field(posix, "connect");',
        ),
        (
            "@hasDecl networking reflection",
            'const attempt = @hasDecl(std.posix, "getaddrinfo");',
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
