#!/usr/bin/env python3

import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOTS = ("pytests/repo/", "scripts/fixtures/")
FIXTURE_EXPECTATION_ROOTS = (
    "pytests/tests/",
    "ztests/",
    "repomd/",
    "tools/cli/lib/",
    "pytests/config.json.in",
)
AMBIGUOUS_FIXTURE_TOKENS = {
    # This fixture directory also names the native implementation in prose.
    "tdnf-native",
}
FIXTURE_QUERY_FILES = {
    "pytests/tests/test_glob.py",
    "pytests/tests/test_pretrans.py",
    "pytests/tests/test_provides.py",
    "pytests/tests/test_search.py",
    "ztests/glob_test.zig",
    "ztests/search_test.zig",
}
DYNAMIC_SPEC_FILES = {
    "pytests/tests/test_native_scriptlets.py",
    "pytests/tests/test_native_transaction_execute.py",
    "pytests/tests/test_native_triggers.py",
    "pytests/tests/test_replay_acceptance.py",
    "pytests/tests/test_srpms.py",
    "pytests/tests/test_transaction_order.py",
}
DYNAMIC_FIXTURE_RENAME = re.compile(
    r"\brpmz-(?:native-|phase[0-9]+|replay(?:-|(?=\b)))"
    r"[A-Za-z0-9_.+*/?-]*"
)
POLICY_FILES = {
    "README.md",
    "doc/migrating-from-tdnf.md",
    "scripts/c-to-zig-audit.py",
    "scripts/docs-audit.py",
    "scripts/librpm-audit.py",
    "scripts/public-zig-api-audit.py",
    "scripts/rebrand-audit.py",
}
PROTOCOL = re.compile(
    r"tdnf\.(?:transaction-plan|transaction-bundle|replay-result|"
    r"replay-invocation-error|rpmdb-package-set|repository-snapshot|"
    r"repository-visible-snapshot|repository-load-record|"
    r"test-sack-snapshot)(?:/[A-Za-z0-9._-]+)?"
)
LEGACY_PRODUCT = re.compile(r"(?i)(?<![A-Za-z0-9_])tdnf(?![A-Za-z0-9_])")
FIXTURE_TOKEN = re.compile(r"\btdnf-[A-Za-z0-9_.+*?/-]+")
RENAMED_FIXTURE_TOKEN = re.compile(r"\brpmz-[A-Za-z0-9_.+*?/-]+")
COMPATIBILITY_CLI_ALLOWANCES = {
    "tools/cli/dispatcher.zig": (
        'const compatibility_command = "tdnf";',
        'const system_compatibility_path = "/usr/bin/tdnf";',
        'const alternate_compatibility_path = "/opt/rpmz/bin/tdnf/";',
    ),
    "tools/cli/dispatcher_cli_test.zig": (
        'const compatibility_command = "tdnf";',
    ),
    "tools/cli/main.zig": (
        'const compatibility_command: [*:0]const u8 = "tdnf";',
        r"\\  tdnf     Run the compatibility package manager",
    ),
    "tools/cli/plan_cli_test.zig": (
        'const compatibility_command = "tdnf";',
    ),
    "tools/cli/replay_cli_test.zig": (
        'const compatibility_command = "tdnf";',
    ),
    "libexec/rpmz-auto.in": (
        '  "${RPMZ_AUTO_EXECUTABLE}" tdnf "$@"',
    ),
    "ztests/harness.zig": (
        'const compatibility_command = "tdnf";',
    ),
    "pytests/cli_testlib.py": (
        "'tdnf'",
    ),
    "pytests/tests/test_cli_golden.py": (
        "'tdnf',",
    ),
    "doc/configuration.md": (
        "tdnf [options]\nCOMMAND",
        "tdnf -> rpmz",
    ),
    "etc/bash_completion.d/rpmz-completion.bash": (
        'compatibility_command="tdnf"',
        '"auto repo-config replay tdnf --help --version -h"',
    ),
    "pytests/tests/test_bash_completion.py": (
        "COMPATIBILITY_COMMAND = 'tdnf'",
        "rpmz tdnf",
    ),
    "scripts/librpm-audit.py": (
        '"tdnf",',
    ),
    "scripts/release.py": (
        '"tdnf",',
    ),
    "scripts/release-smoke.py": (
        '[path, "tdnf", "--version"]',
    ),
    "scripts/release-audit.py": (
        'constant("tdnf")',
    ),
    "pytests/scripts/refresh_cli_golden.py": (
        "case['argv'].insert(1, 'tdnf')",
    ),
    "pytests/tests/test_configutil.py": (
        "['rpmz', 'tdnf', 'repolist']",
    ),
}


def repository_files():
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [
        Path(value.decode())
        for value in result.stdout.split(b"\0")
        if value and (ROOT / value.decode()).is_file()
    ]


def fixture_package_names(files):
    names = set()
    for relative in files:
        path = relative.as_posix()
        if not path.startswith(FIXTURE_ROOTS):
            continue
        if relative.name.endswith(".spec.in"):
            names.add(relative.name.removesuffix(".spec.in"))
        elif relative.suffix == ".spec":
            names.add(relative.stem)
        try:
            source = (ROOT / relative).read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        names.update(re.findall(r"^Name:\s*(\S+)", source, re.MULTILINE))
    return sorted(names, key=len, reverse=True)


def fixture_tokens(files):
    tokens = set()
    for relative in files:
        if not relative.as_posix().startswith("pytests/repo/"):
            continue
        if relative.suffix != ".spec" and not relative.name.endswith(".spec.in"):
            continue
        tokens.update(FIXTURE_TOKEN.findall(
            (ROOT / relative).read_text(encoding="utf-8")
        ))
    return tokens


def renamed_fixture_expectations(files, legacy_tokens):
    errors = []
    for relative in files:
        name = relative.as_posix()
        if not name.startswith(FIXTURE_EXPECTATION_ROOTS):
            continue
        try:
            source = (ROOT / relative).read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(source.splitlines(), 1):
            for renamed in RENAMED_FIXTURE_TOKEN.findall(line):
                legacy = "tdnf-" + renamed.removeprefix("rpmz-")
                if legacy in AMBIGUOUS_FIXTURE_TOKENS:
                    continue
                if legacy in legacy_tokens or (
                    any(character in legacy for character in "*?")
                    and any(
                        fnmatch.fnmatchcase(token, legacy)
                        for token in legacy_tokens
                    )
                ):
                    errors.append(
                        f"{name}:{line_number}: fixture expectation "
                        f"{renamed!r} must retain {legacy!r}"
                    )
    return errors


def config_fixture_errors(source, fixture_names, source_name):
    config = json.loads(source)
    errors = []
    for key, value in config.items():
        if not (
            key.endswith("_pkgname")
            or key in {"requiring_package", "required_package"}
        ):
            continue
        if value not in fixture_names:
            errors.append(
                f"{source_name}: configured fixture {key}={value!r} "
                "does not name a retained fixture RPM"
            )
    return errors


def fixture_query_errors(source, source_name):
    errors = []
    for line_number, line in enumerate(source.splitlines(), 1):
        literals = re.findall(r"""["']([^"']*)["']""", line)
        for index, literal in enumerate(literals):
            if source_name.startswith("pytests/"):
                if index == 0 and literal == "rpmz":
                    continue
                words = literal.split()
                if len(words) > 1 and words[0] == "rpmz":
                    offenders = [word for word in words[1:] if "rpmz" in word]
                    for offender in offenders:
                        errors.append(
                            f"{source_name}:{line_number}: fixture query "
                            f"{offender!r} must retain its legacy tdnf "
                            "search identity"
                        )
                    continue
            if "rpmz" not in literal:
                continue
            errors.append(
                f"{source_name}:{line_number}: fixture query {literal!r} "
                "must retain its legacy tdnf search identity"
            )
    return errors


def dynamic_fixture_errors(source, source_name):
    errors = []
    for line_number, line in enumerate(source.splitlines(), 1):
        for renamed in DYNAMIC_FIXTURE_RENAME.findall(line):
            errors.append(
                f"{source_name}:{line_number}: generated fixture identity "
                f"{renamed!r} must retain its legacy tdnf prefix"
            )
        if re.search(r"""replace\(["']rpmz-["']""", line):
            errors.append(
                f"{source_name}:{line_number}: generated fixture prefix "
                "normalization must retain legacy tdnf-"
            )
    return errors


def scrub_compatibility_allowances(source, relative):
    for allowed in COMPATIBILITY_CLI_ALLOWANCES.get(
        relative.as_posix(), ()
    ):
        source = source.replace(allowed, "")
    return source


def scrub_golden_compatibility_argv(source, relative):
    if not (
        relative.as_posix().startswith("pytests/fixtures/cli-golden/rpmz-")
        and relative.suffix == ".json"
    ):
        return source
    return re.sub(
        r'("argv"\s*:\s*\[\s*"rpmz"\s*,\s*)"tdnf"(\s*,)',
        r"\1\2",
        source,
        count=1,
    )


def self_test():
    errors = config_fixture_errors(
        '{"requiring_package": "rpmz-test-not-a-fixture"}',
        {"tdnf-test-cleanreq-leaf1"},
        "negative-self-test.json",
    )
    if len(errors) != 1:
        raise AssertionError("fake rpmz fixture token was not rejected")
    errors = fixture_query_errors(
        'root.run(&.{ "install", "rpmz*multi*" });',
        "ztests/glob_test.zig",
    )
    if len(errors) != 1:
        raise AssertionError("fake rpmz fixture glob was not rejected")
    errors = fixture_query_errors(
        "utils.run(['rpmz', 'search', 'rpmz'])",
        "pytests/tests/test_search.py",
    )
    if len(errors) != 1:
        raise AssertionError("fake Python rpmz fixture search was not rejected")
    errors = fixture_query_errors(
        'cmd = "rpmz install -y rpmz*multi*"',
        "pytests/tests/test_glob.py",
    )
    if len(errors) != 1:
        raise AssertionError("fake Python rpmz fixture glob was not rejected")
    errors = fixture_query_errors(
        'utils.run("rpmz remove -y rpmz*pretrans*")',
        "pytests/tests/test_pretrans.py",
    )
    if len(errors) != 1:
        raise AssertionError(
            "fake Python rpmz pretrans fixture glob was not rejected"
        )
    errors = fixture_query_errors(
        "utils.run(['rpmz', 'provides', 'rpmz'])",
        "pytests/tests/test_provides.py",
    )
    if len(errors) != 1:
        raise AssertionError("fake Python rpmz provides query was not rejected")
    for renamed in (
        "rpmz-native-generated",
        "rpmz-phase6-generated",
        "rpmz-replay-generated",
    ):
        errors = dynamic_fixture_errors(
            f'name = "{renamed}"',
            "negative-dynamic-spec-test.py",
        )
        if len(errors) != 1:
            raise AssertionError(
                f"fake generated fixture {renamed!r} was not rejected"
            )
    compatibility_source = (
        'const compatibility_command = "tdnf";\n'
        'const system_compatibility_path = "/usr/bin/tdnf";\n'
        'const alternate_compatibility_path = "/opt/rpmz/bin/tdnf/";'
    )
    scrubbed = scrub_allowed(
        compatibility_source,
        Path("tools/cli/dispatcher.zig"),
        set(),
        set(),
    )
    if LEGACY_PRODUCT.search(scrubbed):
        raise AssertionError("explicit compatibility CLI tokens were rejected")
    private_auto_source = '  "${RPMZ_AUTO_EXECUTABLE}" tdnf "$@"'
    scrubbed = scrub_allowed(
        private_auto_source,
        Path("libexec/rpmz-auto.in"),
        set(),
        set(),
    )
    if LEGACY_PRODUCT.search(scrubbed):
        raise AssertionError("private automatic compatibility token was rejected")
    stale_source = 'const obsolete_product = "tdnf";'
    scrubbed = scrub_allowed(
        stale_source,
        Path("tools/cli/dispatcher.zig"),
        set(),
        set(),
    )
    if not LEGACY_PRODUCT.search(scrubbed):
        raise AssertionError("unrelated stale product token was accepted")
    golden_compatibility_source = (
        '{"argv": ["rpmz", "tdnf", "list"]}'
    )
    scrubbed = scrub_allowed(
        golden_compatibility_source,
        Path("pytests/fixtures/cli-golden/rpmz-list-help.json"),
        set(),
        set(),
    )
    if LEGACY_PRODUCT.search(scrubbed):
        raise AssertionError("compatibility golden argv was rejected")
    stale_golden_source = '{"argv": ["rpmz", "list"], "stderr": "tdnf"}'
    scrubbed = scrub_allowed(
        stale_golden_source,
        Path("pytests/fixtures/cli-golden/rpmz-list-help.json"),
        set(),
        set(),
    )
    if not LEGACY_PRODUCT.search(scrubbed):
        raise AssertionError("non-argv golden product token was accepted")


def scrub_allowed(source, relative, fixture_names, legacy_fixture_tokens):
    source = PROTOCOL.sub("", source)
    source = re.sub(
        r"\b[A-Za-z0-9_]*(?:TDNF|Tdnf)[A-Za-z0-9_]*",
        "",
        source,
    )
    source = source.replace("tdnf_internal_abi", "")
    source = source.replace("github.com/vmware/tdnf-cli-libs", "")
    source = source.replace("github.com/vmware/tdnf", "")
    source = source.replace("migrating-from-tdnf.md", "")
    source = source.replace("rpmzig-smoke@tdnf.invalid", "")
    source = source.replace("/var/lib/tdnf/locks", "")
    source = source.replace("/var/lib/tdnf", "")
    source = source.replace("/var/cache/tdnf", "")
    source = source.replace("/var/run/.tdnf-instance-lockfile", "")
    source = source.replace("/usr/lib/sysimage/tdnf", "")
    source = source.replace('".tdnf", "locks"', "")
    source = source.replace("/root/tdnf/tests/testroot/RPMS/", "")
    source = source.replace("tdnf-solv-content-v3", "")
    source = source.replace("tdnf-solv-cache-options/v1", "")
    source = source.replace("tdnf-libsolv-oracle-v1", "")
    source = source.replace("var/cache/tdnf", "")
    source = source.replace("tdnf-repoquery-", "")
    source = source.replace("tdnf-phase7", "")
    source = source.replace("tdnf-old-pretrans", "")
    source = source.replace("tdnf test spec", "")
    source = re.sub(r"\brpmz\s+tdnf\b", "rpmz", source)
    if relative.as_posix() == "repomd/cache.zig":
        source = source.replace('"tdnf"', "")
    if relative.as_posix() in FIXTURE_QUERY_FILES:
        source = re.sub(
            r"""(["'])[^"']*tdnf[^"']*\1""",
            '""',
            source,
        )
    if relative.as_posix() in DYNAMIC_SPEC_FILES:
        source = re.sub(
            r"\btdnf-(?:native-|phase[0-9]+|replay(?:-|(?=\b)))"
            r"[A-Za-z0-9_.+*/?-]*",
            "",
            source,
        )
        source = re.sub(r"""replace\(["']tdnf-["']""", "replace(", source)
    for name in fixture_names:
        source = source.replace(name, "")
    for token in sorted(legacy_fixture_tokens, key=len, reverse=True):
        source = source.replace(token, "")
    for token in FIXTURE_TOKEN.findall(source):
        if any(character in token for character in "*?") and any(
            fnmatch.fnmatchcase(fixture_token, token)
            for fixture_token in legacy_fixture_tokens
        ):
            source = source.replace(token, "")
    if relative.as_posix() in POLICY_FILES:
        source = source.replace("libtdnf", "")
        source = source.replace("tdnf-cli-libs.pc", "")
        source = source.replace("tdnf.pc", "")
    if relative.as_posix() in {
        "README.md",
        "doc/migrating-from-tdnf.md",
        "scripts/docs-audit.py",
    }:
        source = LEGACY_PRODUCT.sub("", source)
    source = scrub_golden_compatibility_argv(source, relative)
    source = scrub_compatibility_allowances(source, relative)
    return source


def main():
    self_test()
    files = repository_files()
    fixture_names = fixture_package_names(files)
    legacy_fixture_tokens = fixture_tokens(files)
    errors = renamed_fixture_expectations(files, legacy_fixture_tokens)
    errors.extend(config_fixture_errors(
        (ROOT / "pytests/config.json.in").read_text(encoding="utf-8"),
        set(fixture_names),
        "pytests/config.json.in",
    ))
    for relative in files:
        name = relative.as_posix()
        if name in FIXTURE_QUERY_FILES:
            errors.extend(fixture_query_errors(
                (ROOT / relative).read_text(encoding="utf-8"),
                name,
            ))
        if name in DYNAMIC_SPEC_FILES:
            errors.extend(dynamic_fixture_errors(
                (ROOT / relative).read_text(encoding="utf-8"),
                name,
            ))
    for relative in files:
        name = relative.as_posix()
        legacy_path = "tdnf" in name and not name.startswith(FIXTURE_ROOTS)
        if legacy_path and name != "doc/migrating-from-tdnf.md":
            errors.append(f"{name}: stale product name in tracked path")
        if name.startswith(FIXTURE_ROOTS) and (
            relative.suffix in {".spec", ".xml"}
            or relative.name.endswith(".spec.in")
        ):
            continue
        try:
            source = (ROOT / relative).read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if name == "scripts/rebrand-audit.py":
            continue
        if "github.com/cataggar/tdnf" in source:
            errors.append(f"{name}: stale cataggar/tdnf URL")
        scrubbed = scrub_allowed(
            source,
            relative,
            fixture_names,
            legacy_fixture_tokens,
        )
        for line_number, line in enumerate(scrubbed.splitlines(), 1):
            if LEGACY_PRODUCT.search(line):
                errors.append(
                    f"{name}:{line_number}: unintended legacy product name"
                )
    if errors:
        print("rpmz rebrand audit failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    print(
        "rpmz rebrand audit passed "
        f"({len(fixture_names)} fixture package identities allowed)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
