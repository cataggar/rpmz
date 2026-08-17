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
CLI_SOURCE = ROOT / "tools" / "cli" / "main.zig"
HELP_TEXT = ROOT / "tools" / "cli" / "lib" / "help.txt"

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
MANDATORY_REPLAY_CLAUSES = (
    (
        "The replay entry-point audit reads only `client/replay.zig`; "
        "it does not inspect or prove transitive implementation dependencies."
    ),
    (
        "RPM payload scriptlets, triggers, embedded interpreters, and "
        "descendant processes are untrusted execution outside the "
        "entry-point audit."
    ),
    (
        "OS-level network isolation is required whenever offline behavior "
        "must include RPM scriptlets, triggers, interpreters, or descendant "
        "processes."
    ),
    (
        "A no-network namespace or equivalent isolation is the enforcement "
        "boundary for that payload code."
    ),
)
CONTRADICTORY_REPLAY_CLAUSES = (
    "replay cannot network",
    "replay cannot make network requests",
    "replay never makes network requests",
    "replay is guaranteed not to make network requests",
    "the audit covers the full replay closure",
    "the audit proves transitive implementation dependencies",
)
PAYLOAD_CONTEXT_TERMS = (
    "payload",
    "scriptlet",
    "trigger",
    "descendant",
    "interpreter",
)
ISOLATION_TERMS = (
    "network isolation",
    "no-network namespace",
    "network namespace",
)
ISOLATION_CONTRADICTION_PATTERNS = (
    r"\bnot required\b",
    r"\bneed not\b",
    r"\bmay omit\b",
    r"\bcan omit\b",
    r"\boptional\b",
    r"\bunnecessary\b",
    r"\bis not mandatory\b",
    r"\bdoes not require\b",
    r"\bnot need\b",
    r"\brecommended only\b",
    r"\bonly recommended\b",
    (
        r"\b(?:run|execute|operate|proceed|be run|be executed)\b"
        r".{0,80}\bwithout (?:os-level )?"
        r"(?:network isolation|a no-network namespace|isolation)\b"
    ),
)


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


def normalize_prose(text: str) -> str:
    return " ".join(text.split()).casefold()


def require_clause(text: str, clause: str, description: str) -> None:
    if normalize_prose(clause) not in normalize_prose(text):
        raise RuntimeError(f"replay documentation is missing {description}")


def prose_clauses(text: str) -> list[str]:
    return [
        normalize_prose(clause)
        for clause in re.split(r"(?<=[.!?])\s+|\n\s*\n|\|", text)
        if clause.strip()
    ]


def isolation_contradictions(text: str) -> list[str]:
    contradictions = []
    for clause in prose_clauses(text):
        if not any(term in clause for term in PAYLOAD_CONTEXT_TERMS):
            continue
        if not any(term in clause for term in ISOLATION_TERMS):
            continue
        if any(
            re.search(pattern, clause)
            for pattern in ISOLATION_CONTRADICTION_PATTERNS
        ):
            contradictions.append(clause)
    return contradictions


def zig_multiline_prose(source: str) -> str:
    return re.sub(r"(?m)^\s*\\\\", "", source)


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
    cli_source: str,
    help_text: str,
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
    require(document, "`rpmzj`", "rpmzj JSON alias")

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
        "RPM payload scriptlets",
        "descendant processes",
        "validation precedes mutation",
        "recorded sequence",
        "first appearance in",
    ):
        require(document.lower(), term.lower(), term)
    for clause in MANDATORY_REPLAY_CLAUSES:
        require_clause(document, clause, f"mandatory clause: {clause}")
    cli_prose = zig_multiline_prose(cli_source)
    semantic_documents = (
        (document, "replay documentation"),
        (plan_doc, "transaction plan documentation"),
        (bundle_doc, "transaction bundle documentation"),
        (readme, "README"),
        (cli_prose, "CLI help source"),
    )
    for clause in CONTRADICTORY_REPLAY_CLAUSES:
        for text, name in semantic_documents:
            if normalize_prose(clause) in normalize_prose(text):
                raise RuntimeError(f"{name} contains contradiction: {clause}")
    for text, name in semantic_documents:
        contradictions = isolation_contradictions(text)
        if contradictions:
            raise RuntimeError(
                f"{name} makes payload isolation optional: {contradictions[0]}"
            )

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
    require(
        bundle_doc,
        "outside that guarantee",
        "transaction bundle payload caveat",
    )
    require_clause(
        cli_prose,
        (
            "OS-level no-network isolation is required when offline behavior "
            "must include payload execution."
        ),
        "CLI mandatory payload isolation",
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


def remove_normalized_clause(text: str, clause: str) -> str:
    pattern = re.escape(clause)
    pattern = pattern.replace(r"\ ", r"\s+")
    changed, count = re.subn(
        pattern,
        "REMOVED",
        text,
        count=1,
        flags=re.IGNORECASE,
    )
    if count != 1:
        raise RuntimeError(f"self-test clause is missing: {clause}")
    return changed


def self_test(inputs: tuple[str, str, str, str, str, str, str, str]) -> None:
    (
        source,
        options_source,
        document,
        plan_doc,
        bundle_doc,
        readme,
        cli_source,
        help_text,
    ) = inputs
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
                cli_source,
                help_text,
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
            cli_source,
            help_text,
        ),
        f"accepted option spelling {spelling} omitted",
    )

    for clause in MANDATORY_REPLAY_CLAUSES:
        changed = remove_normalized_clause(document, clause)
        expect_rejected(
            lambda changed=changed: audit_contract(
                source,
                options_source,
                changed,
                plan_doc,
                bundle_doc,
                readme,
                cli_source,
                help_text,
            ),
            f"mandatory replay clause omitted: {clause}",
        )

    changed_cli = cli_source.replace("payload execution.", "REMOVED", 1)
    expect_rejected(
        lambda: audit_contract(
            source,
            options_source,
            document,
            plan_doc,
            bundle_doc,
            readme,
            changed_cli,
            help_text,
        ),
        "CLI mandatory payload isolation clause omitted",
    )

    for clause in CONTRADICTORY_REPLAY_CLAUSES:
        changed = document + "\n\n" + clause + ".\n"
        expect_rejected(
            lambda changed=changed: audit_contract(
                source,
                options_source,
                changed,
                plan_doc,
                bundle_doc,
                readme,
                cli_source,
                help_text,
            ),
            f"contradictory replay clause accepted: {clause}",
        )

    semantic_cases = (
        (
            "replay documentation: not required",
            document + "\n\nNetwork isolation is not required for RPM scriptlets.\n",
            plan_doc,
            bundle_doc,
            readme,
            help_text,
        ),
        (
            "transaction plan: need not",
            document,
            plan_doc + "\n\nTriggers need not use OS-level network isolation.\n",
            bundle_doc,
            readme,
            help_text,
        ),
        (
            "transaction bundle: may omit",
            document,
            plan_doc,
            bundle_doc + (
                "\n\nPayload descendants may omit a no-network namespace.\n"
            ),
            readme,
            help_text,
        ),
        (
            "README: without isolation",
            document,
            plan_doc,
            bundle_doc,
            readme + (
                "\n\nPayload interpreters can execute without network "
                "isolation.\n"
            ),
            help_text,
        ),
    )
    for (
        label,
        changed_doc,
        changed_plan,
        changed_bundle,
        changed_readme,
        changed_help,
    ) in semantic_cases:
        expect_rejected(
            lambda changed_doc=changed_doc,
            changed_plan=changed_plan,
            changed_bundle=changed_bundle,
            changed_readme=changed_readme,
            changed_help=changed_help: audit_contract(
                source,
                options_source,
                changed_doc,
                changed_plan,
                changed_bundle,
                changed_readme,
                cli_source,
                changed_help,
            ),
            f"semantic isolation contradiction accepted in {label}",
        )

    changed_cli = cli_source + (
        "\n// RPM scriptlets may omit a no-network namespace.\n"
    )
    expect_rejected(
        lambda: audit_contract(
            source,
            options_source,
            document,
            plan_doc,
            bundle_doc,
            readme,
            changed_cli,
            help_text,
        ),
        "semantic isolation contradiction accepted in CLI help source",
    )

    insufficient = document + (
        "\n\nThe replay entry-point audit does not provide network isolation "
        "for payload scriptlets; OS-level network isolation is required.\n"
    )
    audit_contract(
        source,
        options_source,
        insufficient,
        plan_doc,
        bundle_doc,
        readme,
        cli_source,
        help_text,
    )


def load_inputs() -> tuple[str, str, str, str, str, str, str, str]:
    return (
        REPLAY_SOURCE.read_text(encoding="utf-8"),
        REPLAY_OPTIONS.read_text(encoding="utf-8"),
        REPLAY_DOC.read_text(encoding="utf-8"),
        PLAN_DOC.read_text(encoding="utf-8"),
        BUNDLE_DOC.read_text(encoding="utf-8"),
        README.read_text(encoding="utf-8"),
        CLI_SOURCE.read_text(encoding="utf-8"),
        HELP_TEXT.read_text(encoding="utf-8"),
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
