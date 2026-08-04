#!/usr/bin/env python3
"""Fail when a Zig `errdefer` sits in a function that cannot return an error.

Zig accepts `errdefer` inside a function whose return type is not an error
union, but the deferred code is unreachable: there is no error to unwind. The
C ABI shims in this tree report failure with a plain `u32`/`i32` status, so an
`errdefer` written out of habit silently leaks on every failing path.

Run standalone or via `zig build dead-errdefer-audit`.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SKIP_PREFIXES = (
    "zig-pkg/",
    "zig-out/",
    "out/",
    "out-rs/",
    ".zig-cache/",
    "build/",
)

# A function *declaration*, which always has a name. `\w+` rather than `\w*`
# deliberately excludes anonymous `fn (` function types: those appear in
# parameter and return position, and matching them would let a parameter's
# type overwrite the enclosing declaration's entry for the same body brace.
FN_RE = re.compile(r"\bfn\s+\w+\s*\(")
ERRDEFER_RE = re.compile(r"\berrdefer\b")
# A trailing `{` that opens a container type rather than a function body, e.g.
# `fn f() struct {`, `fn f() packed struct(u8) {`, `fn f() error{`.
CONTAINER_OPEN_RE = re.compile(
    r"\b(?:struct|union|enum|opaque|error)\s*(?:\([^()]*\))?\s*\{$"
)

# Return types that are error-capable or not a concrete value type.
ERROR_CAPABLE = ("type", "anyerror")


def strip_noise(line: str) -> str:
    """Remove comments and string/char literals so braces are countable.

    A single left-to-right pass: each of these constructs may legally contain
    the token that starts another, so they must be recognised in source order
    rather than by independent substitutions. `"a//b"` is a string, not a
    comment; `// "x` is a comment, not an unterminated string.
    """
    out: list[str] = []
    index = 0
    end = len(line)
    while index < end:
        char = line[index]
        if line.startswith("//", index):
            break  # line comment: nothing after it can hold a brace
        if line.startswith("\\\\", index):
            break  # multi-line string literal: runs to end of line
        if char in ('"', "'"):
            index += 1
            while index < end:
                if line[index] == "\\":
                    index += 2
                    continue
                if line[index] == char:
                    index += 1
                    break
                index += 1
            out.append(char * 2)
            continue
        out.append(char)
        index += 1
    return "".join(out)


def return_type_of(lines: list[str], index: int) -> tuple[int, str] | None:
    """Return (line_of_opening_brace, return_type) for a fn starting at index.

    A return type may itself be a container (`fn f() struct { x: u8 } {`), so
    the signature is not finished at the first line ending in `{`. Keep
    accumulating while that trailing brace opens a container type, and stop at
    the first one that leaves exactly one brace unmatched — the function body.
    """
    signature = lines[index]
    end = index
    while True:
        text = signature.rstrip()
        if text.endswith(";"):
            # A prototype or `extern fn` declaration has no body. Without this
            # the accumulator runs on and mis-attributes the next function's
            # brace, hiding every `errdefer` inside it.
            return None
        opens_body = (
            text.endswith("{") and
            text.count("{") - text.count("}") == 1 and
            not CONTAINER_OPEN_RE.search(text)
        )
        if opens_body:
            break
        end += 1
        if end >= len(lines) or end > index + 60:
            return None
        signature += " " + lines[end]
    return end, return_type_after_params(signature)


def return_type_after_params(signature: str) -> str:
    """Everything between the parameter list's closing `)` and the body `{`.

    Splitting on the *last* `)` would mangle a return type that ends in one:
    `!std.json.Parsed(std.json.Value)` would come back empty and read as a
    plain status. Walk to the paren that actually closes the parameter list.
    """
    match = FN_RE.search(signature)
    if match is None:
        return ""
    depth = 0
    for position in range(match.end() - 1, len(signature)):
        char = signature[position]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                tail = signature[position + 1:]
                return tail.rstrip()[:-1].strip()
    return ""


class Desync(Exception):
    """The brace tracker lost sync with the source, so results are unusable."""


def scan(path: Path) -> list[tuple[int, str, str]]:
    raw = path.read_text(errors="replace").split("\n")
    stripped = [strip_noise(line) for line in raw]

    fn_open: dict[int, str] = {}
    for i, line in enumerate(stripped):
        if not FN_RE.search(line):
            continue
        found = return_type_of(stripped, i)
        if found is not None:
            fn_open[found[0]] = found[1]

    findings: list[tuple[int, str, str]] = []
    stack: list[str | None] = []
    for i, line in enumerate(stripped):
        if ERRDEFER_RE.search(line):
            enclosing = next((r for r in reversed(stack) if r is not None), None)
            is_dead = (
                enclosing is not None and
                "!" not in enclosing and
                enclosing not in ERROR_CAPABLE
            )
            if is_dead:
                findings.append((i + 1, enclosing, raw[i].strip()))
        # The body brace is the *last* `{` on the signature-closing line: any
        # earlier one belongs to a braced return type (`fn f() struct {...} {`)
        # and opens a scope that closes again before the body starts.
        body_brace = line.rfind("{") if i in fn_open else -1
        for column, char in enumerate(line):
            if char == "{":
                stack.append(fn_open[i] if column == body_brace else None)
            elif char == "}":
                if not stack:
                    # A close brace with nothing open means `strip_noise` let a
                    # literal or comment through. Silently continuing would
                    # unwind real functions off the stack and hide every
                    # `errdefer` below this point, so refuse the file instead.
                    raise Desync(f"unmatched '}}' on line {i + 1}")
                stack.pop()
    if stack:
        raise Desync(f"{len(stack)} unclosed '{{' at end of file")
    return findings


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    failures = 0
    for path in sorted(root.rglob("*.zig")):
        relative = path.relative_to(root).as_posix()
        if relative.startswith(SKIP_PREFIXES):
            continue
        try:
            found = scan(path)
        except Desync as err:
            failures += 1
            print(
                f"{relative}: cannot audit, brace tracking desynchronised "
                f"({err}). Fix `strip_noise` in {Path(__file__).name}."
            )
            continue
        for line_no, return_type, text in found:
            failures += 1
            print(
                f"{relative}:{line_no}: errdefer in a function returning "
                f"'{return_type}' never runs: {text}"
            )

    if failures:
        print(
            f"\ndead-errdefer-audit: {failures} unreachable errdefer(s).\n"
            "Functions returning a plain status cannot unwind an error. Free "
            "explicitly before each failing return, or use a `defer` gated on "
            "a success flag.",
            file=sys.stderr,
        )
        return 1

    print("dead-errdefer-audit: no unreachable errdefer found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
