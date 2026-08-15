#!/usr/bin/env python3
"""Keep replay's published documentation synchronized with its public tags."""

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPLAY_SOURCE = ROOT / "client" / "replay.zig"
REPLAY_DOC = ROOT / "doc" / "replay-api.md"


def enum_members(source: str, name: str) -> list[str]:
    match = re.search(
        r"\bpub\s+const\s+" + re.escape(name) + r"\s*=\s*enum\s*\{(.*?)\n\};",
        source,
        flags=re.S,
    )
    if match is None:
        raise RuntimeError(f"unable to find public {name} enum")
    return re.findall(r"(?m)^\s*([a-z][a-z0-9_]*)\s*,", match.group(1))


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


def main() -> int:
    try:
        source = REPLAY_SOURCE.read_text(encoding="utf-8")
        document = REPLAY_DOC.read_text(encoding="utf-8")

        for enum_name in (
            "Status",
            "ValidationFailure",
            "TransactionFailure",
            "ActionStatus",
        ):
            for member in enum_members(source, enum_name):
                require(document, f"`{member}`", f"{enum_name}.{member}")

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

        canonical_section = document.split(
            "### Canonical result contract", 1
        )[1].split("### Transaction failure semantics", 1)[0]
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

        for option in (
            "--installroot",
            "--rpmdb-path",
            "--forcearch",
            "--json",
            "--help",
            "-i",
            "-h",
        ):
            require(document, option, f"CLI option {option}")
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
            "never requests remote URLs",
            "validation precedes mutation",
            "recorded sequence",
        ):
            require(document.lower(), term.lower(), term)

        plan_doc = (ROOT / "doc" / "transaction-plan-api.md").read_text(
            encoding="utf-8"
        )
        bundle_doc = (ROOT / "doc" / "transaction-bundle.md").read_text(
            encoding="utf-8"
        )
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for text, name in (
            (plan_doc, "transaction plan documentation"),
            (bundle_doc, "transaction bundle documentation"),
        ):
            require(text, "execution_steps", f"{name} execution order")
            require(text, "replay-api.md", f"{name} replay relationship")
            require(text, "v1", f"{name} v1 compatibility")
            require(text, "v2", f"{name} v2 requirement")
        require(readme, "doc/replay-api.md", "README replay reference")
        require(readme, ".replay", "README public replay namespace")
    except (IndexError, OSError, RuntimeError) as error:
        print(f"replay docs audit failed: {error}", file=sys.stderr)
        return 1

    print("Replay documentation audit passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
