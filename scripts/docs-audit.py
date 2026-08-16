#!/usr/bin/env python3
"""Keep the landing page small and migration guidance durable."""

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
MIGRATION = ROOT / "doc" / "migrating-from-tdnf.md"
MAX_README_LINES = 32
MAX_README_BYTES = 1200
README_REQUIRED = (
    "# rpmz",
    "Zig dnf/yum-compatible RPM package manager",
    "ghr install cataggar/rpmz@v0.1.0",
    "zig build -Doptimize=ReleaseSafe install --prefix ./out",
    "(doc/configuration.md)",
    "(doc/transaction-plan-api.md)",
    "(doc/transaction-bundle.md)",
    "(doc/replay-api.md)",
    "(CONTRIBUTING.md)",
    "(doc/building-and-testing.md)",
    "(doc/migrating-from-tdnf.md)",
)
MIGRATION_REQUIRED = (
    "`tdnf` | `rpmz`",
    "`tdnf-config` | `rpmz-config`",
    "`tdnf-automatic` | `rpmz-automatic`",
    "`tdnfmetalink` | `rpmzmetalink`",
    "`tdnfrepogpgcheck` | `rpmzrepogpgcheck`",
    "`tdnfmetalink.conf` | `rpmzmetalink.conf`",
    "`tdnfrepogpgcheck.conf` | `rpmzrepogpgcheck.conf`",
    '`@import("tdnf")`',
    '`@import("rpmz")`',
    "`/etc/tdnf` | `/etc/rpmz`",
    "`<prefix>/libexec/tdnf` | `<prefix>/libexec/rpmz`",
    "systemd/system/tdnf-automatic",
    "systemd/system/rpmz-automatic",
    "bash-completion/completions/tdnf",
    "bash-completion/completions/rpmz",
    "`tdnf-solv-content-v3`",
    "`tdnf-solv-cache-options/v1`",
    "Private `TDNF_*` and `ERROR_TDNF_*` ABI identifiers",
    "tdnf-named test fixtures",
)
README_CLAUSES = (
    "It is derived from upstream "
    "[tdnf](https://github.com/vmware/tdnf).",
)
MIGRATION_CLAUSES = (
    (
        "`--enableplugin` and `--disableplugin` values, plus copied files "
        "under `/etc/rpmz/pluginconf.d`, must use the rpmz names because "
        "no legacy plugin aliases exist."
    ),
    (
        "Serialized `tdnf.*` protocol, schema, and hash identifiers remain "
        "stable across the rebrand."
    ),
    (
        "`/var/lib/tdnf` remains the persistent history and transaction-lock "
        "state location and must be preserved."
    ),
    (
        "`/var/cache/tdnf` remains the shared package and repository cache "
        "and must be preserved."
    ),
    (
        "Do not delete, rename, or move legacy state or cache directories "
        "merely because commands and configuration paths were rebranded."
    ),
)
CONTRADICTIONS = (
    (
        "upstream derivation negation",
        r"\b(?:is|was)\s+(?:not|never)\s+derived\s+from\s+upstream\s+"
        r"\[?tdnf\b|\bdoes\s+not\s+derive\s+from\s+upstream\s+\[?tdnf\b",
    ),
    (
        "unstable protocol identifiers",
        r"(?:protocol|schema|hash).{0,120}identifiers?.{0,100}"
        r"(?:do not|does not|need not|may not|might not|are not|"
        r"not guaranteed to)\s+remain stable|"
        r"(?:protocol|schema|hash).{0,120}identifiers?.{0,80}"
        r"(?:are|may be|can be)\s+unstable",
    ),
    (
        "optional protocol stability",
        r"(?:protocol|schema|hash).{0,120}identifier.{0,100}"
        r"(?:stability|preservation).{0,30}(?:is\s+)?"
        r"(?:optional|not required|unnecessary)",
    ),
    (
        "movable persistent state",
        r"/var/lib/tdnf.{0,140}(?:may|can|could|is safe to)\s+"
        r"(?:be\s+)?(?:deleted?|moved?|renamed?)|"
        r"/var/lib/tdnf.{0,140}(?:need not|does not need to|"
        r"is not required to)\s+(?:remain|stay|be kept|be preserved)|"
        r"/var/lib/tdnf.{0,140}(?:preservation|keeping it in place)"
        r".{0,30}(?:is\s+)?(?:optional|not required|unnecessary)",
    ),
    (
        "movable shared cache",
        r"/var/cache/tdnf.{0,140}(?:may|can|could|is safe to)\s+"
        r"(?:be\s+)?(?:deleted?|moved?|renamed?)|"
        r"/var/cache/tdnf.{0,140}(?:need not|does not need to|"
        r"is not required to)\s+(?:remain|stay|be kept|be preserved)|"
        r"/var/cache/tdnf.{0,140}(?:preservation|keeping it in place)"
        r".{0,30}(?:is\s+)?(?:optional|not required|unnecessary)",
    ),
    (
        "optional legacy state preservation",
        r"(?:legacy state|legacy cache|state or cache directories).{0,140}"
        r"(?:may|can|could|is safe to|are safe to)\s+(?:be\s+)?"
        r"(?:deleted?|moved?|renamed?)|"
        r"(?:legacy state|legacy cache|state or cache directories).{0,140}"
        r"(?:preservation|keeping them in place).{0,30}"
        r"(?:is\s+)?(?:optional|not required|unnecessary)|"
        r"(?:legacy state|legacy cache|state or cache directories).{0,140}"
        r"(?:do not need to|need not|are not required to)\s+"
        r"(?:remain|stay|be preserved|be kept)",
    ),
)
README_PROTECTED = (
    (
        README_CLAUSES[0],
        r"(?:rpmz|it).{0,80}(?:derived|derivation).{0,80}"
        r"upstream.{0,40}tdnf|upstream.{0,40}tdnf.{0,80}"
        r"(?:derived|derivation)",
    ),
)
MIGRATION_NAME_PROTECTED = (
    (
        MIGRATION_CLAUSES[0],
        r"\b(?:legacy\s+)?plugin aliases?\b",
    ),
)
MIGRATION_COMPAT_PROTECTED = (
    (
        MIGRATION_CLAUSES[1],
        r"\b(?:protocol|schema|hash).{0,80}identifiers?\b",
    ),
    (
        MIGRATION_CLAUSES[2],
        r"/var/lib/tdnf",
    ),
    (
        MIGRATION_CLAUSES[3],
        r"/var/cache/tdnf",
    ),
    (
        MIGRATION_CLAUSES[4],
        r"(?:legacy state|legacy cache|state or cache directories)",
    ),
)
NEGATION_OR_QUALIFICATION = re.compile(
    r"\b(?:not|never|no|false|untrue|incorrect|misleading|isn't|aren't|"
    r"wasn't|weren't|doesn't|don't|mustn't|shouldn't|needn't|cannot|"
    r"can't|contrary to|supposedly|allegedly|purportedly|quotation|"
    r"quotations|quoted|example|examples|non-operational|not guidance|"
    r"informational only|hypothetical|disclaimer)\b"
)
BLANKET_CLAIM_SCOPE = re.compile(
    r"\b(?:migration claims?|these claims?|these statements?|"
    r"preceding claims?|above claims?|statements? in this section|"
    r"documentation in this section|this section|"
    r"(?:all|everything|material|content|text)\s+"
    r"(?:above|below|in this section))\b"
)
BLANKET_DISCLAIMER = re.compile(
    r"\b(?:quotation|quotations|quoted|example|examples|non-operational|"
    r"not operational|not guidance|informational only|hypothetical|"
    r"not instructions?|not requirements?)\b"
)


def normalize(text: str) -> str:
    apostrophes = str.maketrans({
        "\u2018": "'",
        "\u2019": "'",
        "\u02bc": "'",
        "\uff07": "'",
    })
    return " ".join(text.translate(apostrophes).split()).casefold()


def prose_clauses(text: str) -> list[str]:
    blocks = []
    current = []
    in_fence = False

    def flush() -> None:
        if current:
            blocks.append(" ".join(current))
            current.clear()

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("```"):
            flush()
            in_fence = not in_fence
            continue
        if in_fence or not line:
            flush()
            continue
        if line.startswith("#") or line.startswith("|"):
            flush()
            continue
        if line.startswith("- "):
            flush()
            current.append(line[2:])
            continue
        current.append(line)
    flush()

    clauses = []
    for block in blocks:
        for clause in re.split(r"(?<=[.!?])\s+", block):
            normalized = normalize(clause)
            if normalized:
                clauses.append(normalized)
    return clauses


def before_heading(text: str, heading: str) -> str:
    marker = f"## {heading}"
    if text.count(marker) != 1:
        raise RuntimeError(f"documentation heading changed: {marker}")
    return text.split(marker, 1)[0]


def after_heading(text: str, heading: str) -> str:
    marker = f"## {heading}"
    if text.count(marker) != 1:
        raise RuntimeError(f"documentation heading changed: {marker}")
    return text.split(marker, 1)[1]


def suspicious_clause(clause: str) -> bool:
    qualified = NEGATION_OR_QUALIFICATION.search(clause) is not None
    quoted = clause.startswith(("\"", "'", ">", "\u201c", "\u2018"))
    inverted = re.search(r"\b(?:do|does)\s+exist\b", clause) is not None
    return qualified or quoted or inverted


def validate_protected_section(
    errors: list[str],
    document: str,
    section: str,
    protected: tuple[tuple[str, str], ...],
) -> None:
    clauses = prose_clauses(section)
    for required, subject_pattern in protected:
        target = normalize(required)
        count = clauses.count(target)
        if count != 1:
            errors.append(
                f"{document} must contain exactly one affirmative clause "
                f"{required!r} in its designated section; found {count}"
            )
        for clause in clauses:
            if clause == target:
                continue
            if re.search(subject_pattern, clause) and suspicious_clause(clause):
                errors.append(
                    f"{document} contradicts or disclaims protected subject "
                    f"in clause {clause!r}"
                )


def reject_blanket_disclaimers(errors: list[str], migration: str) -> None:
    for clause in prose_clauses(migration):
        scoped = BLANKET_CLAIM_SCOPE.search(clause) is not None
        disclaimed = BLANKET_DISCLAIMER.search(clause) is not None
        if scoped and disclaimed:
            errors.append(
                "doc/migrating-from-tdnf.md contains a blanket migration "
                f"disclaimer in clause {clause!r}"
            )


def remove_normalized_clause(text: str, clause: str) -> str:
    parts = re.split(r"\s+", clause.strip())
    pattern = r"\s+".join(re.escape(part) for part in parts)
    changed, count = re.subn(pattern, "REMOVED", text, count=1)
    if count != 1:
        raise AssertionError(f"self-test clause is missing: {clause}")
    return changed


def insert_before_heading(text: str, heading: str, addition: str) -> str:
    marker = f"## {heading}"
    if text.count(marker) != 1:
        raise AssertionError(f"self-test heading is missing: {marker}")
    return text.replace(marker, addition.rstrip() + "\n\n" + marker, 1)


def audit(readme: str, migration: str) -> list[str]:
    errors = []
    if not readme.startswith("# rpmz\n"):
        errors.append("README.md must begin with the exact '# rpmz' title")
    line_count = len(readme.splitlines())
    byte_count = len(readme.encode("utf-8"))
    if line_count > MAX_README_LINES:
        errors.append(
            f"README.md has {line_count} lines; limit is {MAX_README_LINES}"
        )
    if byte_count > MAX_README_BYTES:
        errors.append(
            f"README.md has {byte_count} bytes; limit is {MAX_README_BYTES}"
        )
    for required in README_REQUIRED:
        if required not in readme:
            errors.append(f"README.md is missing {required!r}")
    if "upcoming v0.1.0" in normalize(readme):
        errors.append("README.md describes the published v0.1.0 release as upcoming")
    for command in (
        "ghr install cataggar/rpmz@v0.1.0",
        "zig build -Doptimize=ReleaseSafe install --prefix ./out",
    ):
        if readme.count(command) != 1:
            errors.append(
                f"README.md must contain exactly one copy of {command!r}"
            )
    for required in MIGRATION_REQUIRED:
        if required not in migration:
            errors.append(
                f"doc/migrating-from-tdnf.md is missing {required!r}"
            )
    readme_intro = before_heading(readme, "Install")
    migration_names = before_heading(
        migration,
        "Intentional compatibility remnants",
    )
    migration_compat = after_heading(
        migration,
        "Intentional compatibility remnants",
    )
    validate_protected_section(
        errors,
        "README.md",
        readme_intro,
        README_PROTECTED,
    )
    validate_protected_section(
        errors,
        "doc/migrating-from-tdnf.md",
        migration_names,
        MIGRATION_NAME_PROTECTED,
    )
    validate_protected_section(
        errors,
        "doc/migrating-from-tdnf.md",
        migration_compat,
        MIGRATION_COMPAT_PROTECTED,
    )
    reject_blanket_disclaimers(errors, migration)
    combined = normalize(readme + "\n" + migration)
    for description, pattern in CONTRADICTIONS:
        if re.search(pattern, combined):
            errors.append(f"documentation contains {description}")
    return errors


def self_test(readme: str, migration: str) -> None:
    if audit(readme, migration):
        raise AssertionError("repository documentation does not pass audit")
    for required in README_REQUIRED:
        changed = readme.replace(required, "REMOVED", 1)
        if not audit(changed, migration):
            raise AssertionError(
                f"missing README requirement accepted: {required}"
            )
    if not audit(
        readme.replace(
            "## Install",
            "## Install\n\nFor the upcoming v0.1.0 tagged release:",
            1,
        ),
        migration,
    ):
        raise AssertionError("stale upcoming v0.1.0 wording accepted")
    for required in MIGRATION_REQUIRED:
        changed = migration.replace(required, "REMOVED", 1)
        if not audit(readme, changed):
            raise AssertionError(
                f"missing migration requirement accepted: {required}"
            )
    for clause in README_CLAUSES:
        changed = remove_normalized_clause(readme, clause)
        if not audit(changed, migration):
            raise AssertionError(
                f"missing README clause accepted: {clause}"
            )
    for clause in MIGRATION_CLAUSES:
        changed = remove_normalized_clause(migration, clause)
        if not audit(readme, changed):
            raise AssertionError(
                f"missing migration clause accepted: {clause}"
            )
    contradiction_cases = (
        (
            insert_before_heading(
                readme,
                "Install",
                "rpmz is not derived from upstream tdnf.",
            ),
            migration,
            "README upstream derivation negation",
        ),
        (
            readme,
            migration + "\n\nProtocol identifiers do not remain stable.\n",
            "protocol stability negation",
        ),
        (
            readme,
            migration + "\n\nSchema identifier stability is optional.\n",
            "optional schema stability",
        ),
        (
            readme,
            migration + "\n\n/var/lib/tdnf may be moved after upgrading.\n",
            "movable persistent state",
        ),
        (
            readme,
            migration + "\n\n/var/lib/tdnf need not be preserved.\n",
            "optional persistent state",
        ),
        (
            readme,
            migration + "\n\n/var/lib/tdnf preservation is optional.\n",
            "optional persistent state preservation",
        ),
        (
            readme,
            migration + "\n\n/var/cache/tdnf can be deleted after upgrading.\n",
            "deletable shared cache",
        ),
        (
            readme,
            migration + "\n\n/var/cache/tdnf does not need to be preserved.\n",
            "optional shared cache",
        ),
        (
            readme,
            migration + (
                "\n\n/var/cache/tdnf is not required to remain in place.\n"
            ),
            "movable shared cache location",
        ),
        (
            readme,
            migration + "\n\nLegacy state preservation is optional.\n",
            "optional legacy preservation",
        ),
        (
            readme,
            migration + "\n\nLegacy cache directories are safe to move.\n",
            "movable legacy cache",
        ),
        (
            readme,
            migration + (
                "\n\nLegacy state directories do not need to stay in place.\n"
            ),
            "optional legacy state location",
        ),
        (
            insert_before_heading(
                readme,
                "Install",
                "It is false that "
                f"{README_CLAUSES[0]}",
            ),
            migration,
            "wrapped upstream derivation",
        ),
        (
            readme,
            migration + (
                "\n\nIt is untrue that "
                f"{MIGRATION_CLAUSES[1]}\n"
            ),
            "wrapped protocol stability",
        ),
        (
            readme,
            migration + (
                "\n\nIt is not the case that "
                f"{MIGRATION_CLAUSES[2]}\n"
            ),
            "wrapped persistent state preservation",
        ),
        (
            readme,
            migration + (
                "\n\nContrary to the claim that "
                f"{MIGRATION_CLAUSES[3]}\n"
            ),
            "qualified shared cache preservation",
        ),
        (
            readme,
            insert_before_heading(
                migration,
                "Intentional compatibility remnants",
                'The following statement is false: "'
                f'{MIGRATION_CLAUSES[0]}"',
            ),
            "quoted plugin alias disclaimer",
        ),
    )
    for changed_readme, changed_migration, description in contradiction_cases:
        if not audit(changed_readme, changed_migration):
            raise AssertionError(
                f"contradictory guidance accepted: {description}"
            )
    demonstrated_cases = []
    for apostrophe in ("'", "\u2019"):
        demonstrated_cases.extend((
            (
                insert_before_heading(
                    readme,
                    "Install",
                    f"rpmz isn{apostrophe}t derived from upstream tdnf.",
                ),
                migration,
                "contracted upstream derivation negation",
            ),
            (
                readme,
                migration + (
                    f"\n\n/var/lib/tdnf mustn{apostrophe}t be preserved.\n"
                ),
                "contracted persistent state negation",
            ),
            (
                readme,
                migration + (
                    f"\n\n/var/cache/tdnf mustn{apostrophe}t be preserved.\n"
                ),
                "contracted shared cache negation",
            ),
        ))
    demonstrated_cases.extend((
        (
            readme,
            insert_before_heading(
                migration,
                "Intentional compatibility remnants",
                "Legacy plugin aliases do exist.",
            ),
            "legacy plugin alias inversion",
        ),
        (
            readme,
            migration + "\n\nMigration claims are quotations.\n",
            "blanket quotation disclaimer",
        ),
        (
            readme,
            migration + "\n\nMigration claims are examples.\n",
            "blanket example disclaimer",
        ),
        (
            readme,
            migration + "\n\nThese statements are non-operational.\n",
            "blanket operational disclaimer",
        ),
        (
            readme,
            migration + "\n\nAbove claims are not guidance.\n",
            "blanket guidance disclaimer",
        ),
    ))
    for changed_readme, changed_migration, description in demonstrated_cases:
        if not audit(changed_readme, changed_migration):
            raise AssertionError(
                f"demonstrated bypass accepted: {description}"
            )
    allowed_repetitions = migration + (
        "\n\nThe `/var/lib/tdnf` and `/var/cache/tdnf` paths are listed "
        "above for migration planning.\n"
    )
    if audit(readme, allowed_repetitions):
        raise AssertionError("legitimate compatibility path repetition rejected")
    if not audit(readme + "\nextra\n" * MAX_README_LINES, migration):
        raise AssertionError("README line growth was accepted")
    padding = "x" * (MAX_README_BYTES + 1)
    if not audit(readme + padding, migration):
        raise AssertionError("README byte growth was accepted")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    readme = README.read_text(encoding="utf-8")
    migration = MIGRATION.read_text(encoding="utf-8")
    try:
        if args.self_test:
            self_test(readme, migration)
            print("Documentation audit self-tests passed")
            return 0
        errors = audit(readme, migration)
        if errors:
            raise RuntimeError("\n".join(errors))
        print("Documentation audit passed")
        return 0
    except (AssertionError, RuntimeError) as error:
        print(f"Documentation audit failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
