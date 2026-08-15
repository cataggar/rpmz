#!/usr/bin/env python3
"""Keep replay's published documentation synchronized with its public tags."""

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPLAY_SOURCE = ROOT / "client" / "replay.zig"
REPLAY_OPTIONS = ROOT / "tools" / "cli" / "replay_options.zig"
REPLAY_DOC = ROOT / "doc" / "replay-api.md"
PLAN_DOC = ROOT / "doc" / "transaction-plan-api.md"
BUNDLE_DOC = ROOT / "doc" / "transaction-bundle.md"
README = ROOT / "README.md"

ENUM_SECTIONS = {
    "Status": ("#### Status values", "#### Validation failure values"),
    "ValidationFailure": (
        "#### Validation failure values",
        "#### Transaction failure values",
    ),
    "TransactionFailure": (
        "#### Transaction failure values",
        "#### Action status values",
    ),
    "ActionStatus": (
        "#### Action status values",
        "### Transaction failure semantics",
    ),
}


def enum_members(source: str, name: str) -> list[str]:
    match = re.search(
        r"\bpub\s+const\s+" + re.escape(name) + r"\s*=\s*enum\s*\{(.*?)\n\};",
        source,
        flags=re.S,
    )
    if match is None:
        raise RuntimeError(f"unable to find public {name} enum")
    return re.findall(r"(?m)^\s*([a-z][a-z0-9_]*)\s*,", match.group(1))


def const_string(source: str, name: str) -> str:
    match = re.search(
        "".join((
            r"\bpub\s+const\s+",
            re.escape(name),
            r'\s*=\s*"([^"]+)"\s*;',
        )),
        source,
    )
    if match is None:
        raise RuntimeError(f"unable to find replay option constant {name}")
    return match.group(1)


def require(text: str, needle: str, description: str) -> None:
    if needle not in text:
        raise RuntimeError(f"replay documentation is missing {description}")


def require_order(text: str, values: list[str], description: str) -> None:
    offset = 0
    for value in values:
        index = text.find(value, offset)
        if index < 0:
            raise RuntimeError(
                f"replay documentation is missing ordered {description}: {value}"
            )
        offset = index + len(value)


def section(text: str, start: str, end: str) -> str:
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError(f"replay documentation section boundary changed: {start}")
    return text.split(start, 1)[1].split(end, 1)[0]


def option_spellings(options_source: str) -> list[str]:
    names = [
        (const_string(options_source, "install_root_name"), "PATH"),
        (const_string(options_source, "rpmdb_path_name"), "PATH"),
        (const_string(options_source, "architecture_name"), "ARCH"),
    ]
    spellings = []
    for name, placeholder in names:
        spellings.extend([
            f"--{name} {placeholder}",
            f"--{name}={placeholder}",
            f"-{name} {placeholder}",
            f"-{name}={placeholder}",
        ])

    short_match = re.search(
        r"\bpub\s+const\s+install_root\s*=\s*ValueOption\s*\{"
        r'.*?\.short\s*=\s*"([^"]+)"',
        options_source,
        flags=re.S,
    )
    if short_match is None:
        raise RuntimeError("unable to find installroot short option")
    short = short_match.group(1)
    spellings.extend([f"{short} PATH", f"{short}PATH"])

    json_name = const_string(options_source, "json_name")
    for length in range(1, len(json_name) + 1):
        prefix = json_name[:length]
        spellings.extend([f"-{prefix}", f"--{prefix}"])
    spellings.extend([
        const_string(options_source, "help_long"),
        const_string(options_source, "help_short"),
    ])
    return spellings


def audit_contract(
    source: str,
    options_source: str,
    document: str,
    plan_doc: str,
    bundle_doc: str,
    readme: str,
) -> None:
    for enum_name, boundaries in ENUM_SECTIONS.items():
        enum_section = section(document, *boundaries)
        for member in enum_members(source, enum_name):
            require(
                enum_section,
                f"`{member}`",
                f"{enum_name}.{member} in its own section",
            )

    for field in (
        "actions",
        "applied_plan_digest",
        "final_inventory",
        "plan_digest",
        "schema",
        "status",
        "transaction_failure",
        "validation_failure",
    ):
        require(document, f"`{field}`", f"result field {field}")

    canonical_section = section(
        document,
        "### Canonical result contract",
        "### Transaction failure semantics",
    )
    require_order(
        canonical_section,
        [
            '"actions"',
            '"applied_plan_digest"',
            '"final_inventory"',
            '"plan_digest"',
            '"schema"',
            '"status"',
            '"transaction_failure"',
            '"validation_failure"',
        ],
        "canonical result field",
    )

    for spelling in option_spellings(options_source):
        require(document, f"`{spelling}`", f"CLI option spelling {spelling}")
    require(document, "`tdnfj`", "tdnfj JSON alias")

    for status in range(5):
        require(document, f"| `{status}` |", f"exit status {status}")
    for term in (
        "tdnf.transaction-bundle/v2",
        "tdnf.transaction-plan/v2",
        "tdnf.replay-result/v1",
        "tdnf.replay-invocation-error/v1",
        "stdout",
        "stderr",
        "OS-level network isolation",
        "project-owned replay implementation",
        "RPM payload scriptlets",
        "outside that static guarantee",
        "no-network namespace",
        "descendant processes",
        "validation precedes mutation",
        "recorded sequence",
        "first appearance in",
    ):
        require(document.lower(), term.lower(), term)

    for text, name in (
        (plan_doc, "transaction plan documentation"),
        (bundle_doc, "transaction bundle documentation"),
    ):
        require(text, "execution_steps", f"{name} execution order")
        require(text, "replay-api.md", f"{name} replay relationship")
        require(text, "v1", f"{name} v1 compatibility")
        require(text, "v2", f"{name} v2 requirement")
    require(
        plan_doc.lower(),
        "first appearance in `execution_steps`",
        "transaction plan result ordering",
    )
    require(readme, "doc/replay-api.md", "README replay reference")
    require(readme, ".replay", "README public replay namespace")
    require(readme, "RPM payload scriptlets", "README payload caveat")
    require(readme, "no-network namespace", "README isolation requirement")
    require(
        bundle_doc,
        "outside that guarantee",
        "transaction bundle payload caveat",
    )


def remove_from_section(
    document: str,
    start: str,
    end: str,
    value: str,
) -> str:
    start_index = document.index(start) + len(start)
    end_index = document.index(end, start_index)
    body = document[start_index:end_index]
    if value not in body:
        raise RuntimeError(f"self-test fixture value is missing: {value}")
    body = body.replace(value, "REMOVED")
    return document[:start_index] + body + document[end_index:]


def expect_rejected(run, description: str) -> None:
    try:
        run()
    except RuntimeError:
        return
    raise RuntimeError(f"negative self-test was accepted: {description}")


def self_test(inputs: tuple[str, str, str, str, str, str]) -> None:
    source, options_source, document, plan_doc, bundle_doc, readme = inputs
    audit_contract(*inputs)

    for enum_name, tag in (
        ("Status", "transaction_failed"),
        ("ValidationFailure", "prior_mismatch"),
        ("TransactionFailure", "prior_mismatch"),
        ("ActionStatus", "applied"),
    ):
        start, end = ENUM_SECTIONS[enum_name]
        changed = remove_from_section(document, start, end, f"`{tag}`")
        expect_rejected(
            lambda changed=changed: audit_contract(
                source,
                options_source,
                changed,
                plan_doc,
                bundle_doc,
                readme,
            ),
            f"{enum_name}.{tag} missing from its own section",
        )

    spelling = f"-{const_string(options_source, 'install_root_name')}=PATH"
    changed = document.replace(f"`{spelling}`", "`REMOVED`", 1)
    expect_rejected(
        lambda: audit_contract(
            source,
            options_source,
            changed,
            plan_doc,
            bundle_doc,
            readme,
        ),
        f"accepted option spelling {spelling} omitted",
    )

    changed = document.replace("outside that static guarantee", "REMOVED")
    expect_rejected(
        lambda: audit_contract(
            source,
            options_source,
            changed,
            plan_doc,
            bundle_doc,
            readme,
        ),
        "RPM payload confinement caveat omitted",
    )


def load_inputs() -> tuple[str, str, str, str, str, str]:
    return (
        REPLAY_SOURCE.read_text(encoding="utf-8"),
        REPLAY_OPTIONS.read_text(encoding="utf-8"),
        REPLAY_DOC.read_text(encoding="utf-8"),
        PLAN_DOC.read_text(encoding="utf-8"),
        BUNDLE_DOC.read_text(encoding="utf-8"),
        README.read_text(encoding="utf-8"),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        inputs = load_inputs()
        if args.self_test:
            self_test(inputs)
            print("Replay documentation audit self-tests passed")
        else:
            audit_contract(*inputs)
            print("Replay documentation audit passed")
    except (OSError, RuntimeError) as error:
        print(f"replay docs audit failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
