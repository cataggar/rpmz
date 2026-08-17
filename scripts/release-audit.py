#!/usr/bin/env python3

import ast
import importlib.util
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/release.yml"
CI_WORKFLOW = ROOT / ".github/workflows/ci.yml"
MANIFEST = ROOT / ".github/release-assets.json"
PACKAGER = ROOT / "scripts/release.py"
SMOKE = ROOT / "scripts/release-smoke.py"
COMMON = ROOT / "scripts/release_common.py"
PLATFORMS = [
    {"os": "ubuntu-24.04", "platform": "linux-x64"},
    {"os": "ubuntu-24.04-arm", "platform": "linux-arm64"},
]
SIGNING_COMMANDS = {"gpg", "cosign", "minisign", "signify", "openssl"}


class YamlError(ValueError):
    pass


def indentation(line):
    if "\t" in line[:len(line) - len(line.lstrip())]:
        raise YamlError("tabs are not supported in workflow indentation")
    return len(line) - len(line.lstrip(" "))


def strip_comment(value):
    quote = None
    escaped = False
    for index, character in enumerate(value):
        if escaped:
            escaped = False
            continue
        if quote == '"' and character == "\\":
            escaped = True
            continue
        if character in ("'", '"'):
            if quote is None:
                quote = character
            elif quote == character:
                quote = None
            continue
        if (
            character == "#"
            and quote is None
            and (index == 0 or value[index - 1].isspace())
        ):
            return value[:index].rstrip()
    return value.rstrip()


def parse_scalar(value):
    value = strip_comment(value).strip()
    if not value:
        return None
    if value[0:1] in ("'", '"') and value[-1:] == value[0]:
        return ast.literal_eval(value)
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(item) for item in inner.split(",")]
    if value == "true":
        return True
    if value == "false":
        return False
    if value == "null":
        return None
    return value


class WorkflowParser:
    def __init__(self, source):
        self.lines = source.splitlines()

    def next_content(self, index):
        while index < len(self.lines):
            stripped = self.lines[index].strip()
            if stripped and not stripped.startswith("#"):
                return index
            index += 1
        return index

    def parse(self):
        index = self.next_content(0)
        if index == len(self.lines):
            return {}
        value, index = self.parse_block(index, indentation(self.lines[index]))
        if self.next_content(index) != len(self.lines):
            raise YamlError("unexpected trailing workflow content")
        return value

    def parse_block(self, index, indent):
        index = self.next_content(index)
        line = self.lines[index]
        if indentation(line) != indent:
            raise YamlError(f"unexpected indentation at line {index + 1}")
        if line[indent:].startswith("- "):
            return self.parse_list(index, indent)
        return self.parse_map(index, indent)

    def split_mapping(self, text, line_number):
        if ":" not in text:
            raise YamlError(f"missing mapping colon at line {line_number}")
        key, value = text.split(":", 1)
        key = parse_scalar(key.strip())
        if not isinstance(key, str) or not key:
            raise YamlError(f"invalid mapping key at line {line_number}")
        return key, value.strip()

    def nested_value(self, index, indent):
        child = self.next_content(index)
        if (
            child >= len(self.lines)
            or indentation(self.lines[child]) <= indent
        ):
            return {}, index
        return self.parse_block(child, indentation(self.lines[child]))

    def block_scalar(self, index, indent):
        output = []
        while index < len(self.lines):
            line = self.lines[index]
            if line.strip() and indentation(line) <= indent:
                break
            remove = min(len(line), indent + 2)
            output.append(line[remove:] if line.strip() else "")
            index += 1
        return "\n".join(output) + "\n", index

    def mapping_value(self, raw, index, indent):
        if raw in ("|", "|-", "|+"):
            return self.block_scalar(index, indent)
        if raw == "":
            return self.nested_value(index, indent)
        return parse_scalar(raw), index

    def parse_map(self, index, indent):
        result = {}
        while True:
            index = self.next_content(index)
            if index >= len(self.lines):
                break
            line = self.lines[index]
            current = indentation(line)
            if current < indent:
                break
            if current != indent or line[indent:].startswith("- "):
                break
            key, raw = self.split_mapping(line[indent:], index + 1)
            if key in result:
                raise YamlError(f"duplicate key {key!r} at line {index + 1}")
            value, index = self.mapping_value(raw, index + 1, indent)
            result[key] = value
        return result, index

    def parse_list(self, index, indent):
        result = []
        while True:
            index = self.next_content(index)
            if index >= len(self.lines):
                break
            line = self.lines[index]
            if (
                indentation(line) != indent
                or not line[indent:].startswith("- ")
            ):
                break
            raw_item = line[indent + 2:].strip()
            index += 1
            if ":" not in raw_item:
                result.append(parse_scalar(raw_item))
                continue
            key, raw = self.split_mapping(raw_item, index)
            value, index = self.mapping_value(raw, index, indent + 2)
            item = {key: value}
            continuation = self.next_content(index)
            if (
                continuation < len(self.lines)
                and indentation(self.lines[continuation]) == indent + 2
                and not self.lines[continuation][indent + 2:].startswith("- ")
            ):
                extra, index = self.parse_map(continuation, indent + 2)
                overlap = item.keys() & extra.keys()
                if overlap:
                    raise YamlError(
                        f"duplicate list mapping keys: {sorted(overlap)}"
                    )
                item.update(extra)
            result.append(item)
        return result, index


def parse_workflow(source):
    document = WorkflowParser(source).parse()
    if not isinstance(document, dict):
        raise YamlError("workflow root must be a mapping")
    return document


def expect(errors, condition, message):
    if not condition:
        errors.append(message)


def job_steps(job):
    steps = job.get("steps", []) if isinstance(job, dict) else []
    return steps if isinstance(steps, list) else []


def named_step(job, name):
    matches = [
        step for step in job_steps(job)
        if isinstance(step, dict) and step.get("name") == name
    ]
    return matches[0] if len(matches) == 1 else None


def action_step(job, prefix):
    matches = [
        step for step in job_steps(job)
        if isinstance(step, dict)
        and isinstance(step.get("uses"), str)
        and step["uses"].startswith(prefix)
    ]
    return matches[0] if len(matches) == 1 else None


def scalar_lines(value):
    if not isinstance(value, str):
        return []
    return [line.strip() for line in value.splitlines() if line.strip()]


def shell_lines(value):
    return [
        line for line in scalar_lines(value)
        if not line.startswith("#")
    ]


def matrix(job):
    try:
        return job["strategy"]["matrix"]["include"]
    except (KeyError, TypeError):
        return None


def walk_scalars(value):
    if isinstance(value, dict):
        for key, child in value.items():
            yield str(key)
            yield from walk_scalars(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_scalars(child)
    elif isinstance(value, str):
        yield value


def step_identities(job):
    result = []
    for step in job_steps(job):
        if not isinstance(step, dict):
            result.append(("invalid", None))
        elif "uses" in step:
            result.append(("uses", step["uses"]))
        else:
            result.append(("name", step.get("name")))
    return result


def constant(value):
    return ("constant", value)


def name(value):
    return ("name", value)


def sequence(*values):
    return ("list", values)


def attribute(value, field):
    return ("attribute", value, field)


def binop(operator, left, right):
    return ("binop", operator, left, right)


def call(function, *arguments):
    return ("call", function, arguments)


def fstring(*values):
    return ("fstring", values)


def formatted(value):
    return ("formatted", value)


def ast_shape(node):
    if isinstance(node, ast.Constant):
        return constant(node.value)
    if isinstance(node, ast.Name):
        return name(node.id)
    if isinstance(node, ast.List):
        return sequence(*(ast_shape(value) for value in node.elts))
    if isinstance(node, ast.Attribute):
        return attribute(ast_shape(node.value), node.attr)
    if isinstance(node, ast.BinOp):
        return binop(
            type(node.op).__name__,
            ast_shape(node.left),
            ast_shape(node.right),
        )
    if isinstance(node, ast.Call):
        if (
            node.keywords
            or not isinstance(node.func, ast.Name)
        ):
            return ("unsupported-call",)
        return call(
            node.func.id,
            *(ast_shape(argument) for argument in node.args),
        )
    if isinstance(node, ast.JoinedStr):
        return fstring(*(ast_shape(value) for value in node.values))
    if isinstance(node, ast.FormattedValue):
        if node.conversion != -1 or node.format_spec is not None:
            return ("unsupported-formatted",)
        return formatted(ast_shape(node.value))
    return ("unsupported", type(node).__name__)


def audit_packager(errors, manifest, packager):
    if manifest.get("repository") != "cataggar/rpmz":
        errors.append("release manifest repository is not cataggar/rpmz")
    if manifest.get("platforms") != ["linux-x64", "linux-arm64"]:
        errors.append("release manifest platforms are not the supported pair")
    templates = {
        "binary_archive": "rpmz-{version}-{platform}.tar.gz",
        "source_archive": "rpmz-{version}.tar.xz",
        "sbom": "rpmz-{version}-{platform}.sbom.spdx.json",
        "install_command": "ghr install cataggar/rpmz@v{version}",
    }
    for key, value in templates.items():
        if manifest.get(key) != value:
            errors.append(f"release manifest {key} is inconsistent")

    tree = ast.parse(packager)
    audit_script_signing(errors, tree, "release packager")
    audit_imports(
        errors,
        tree,
        "release packager",
        {
            "argparse", "datetime", "gzip", "hashlib", "json", "lzma",
            "os", "platform", "shutil", "subprocess", "tarfile", "uuid",
        },
        {
            "pathlib": {"Path", "PurePosixPath"},
            "release_common": {"parse_semver"},
        },
    )
    audit_process_execution(errors, tree, "release packager", {
        "rpmz_version": (
            sequence(
                binop(
                    "Div", name("prefix"), constant("bin/rpmz")
                ),
                constant("--version"),
            ),
            {"check", "capture_output", "text"},
        ),
        "compatibility_version": (
            sequence(
                binop(
                    "Div", name("prefix"), constant("bin/rpmz")
                ),
                constant("tdnf"),
                constant("--version"),
            ),
            {"check", "capture_output", "text"},
        ),
        "package_source": (
            sequence(
                constant("git"),
                constant("archive"),
                constant("--format=tar"),
                fstring(
                    constant("--prefix="),
                    formatted(name("package_name")),
                    constant("/"),
                ),
                constant("HEAD"),
            ),
            {"cwd", "check", "capture_output"},
        ),
    })
    calls = {}
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            calls[node.name] = {
                call.func.id
                for call in ast.walk(node)
                if isinstance(call, ast.Call)
                and isinstance(call.func, ast.Name)
            }
    expected_calls = {
        "package_binary": {
            "verify_public_bin", "rpmz_version", "compatibility_version",
            "copy_install_tree", "add_tree", "write_checksum", "write_sbom",
        },
        "package_source": {"write_checksum"},
        "verify_assets": {
            "verify_archive", "verify_checksum", "archive_members",
        },
        "dry_run": {"package_binary", "package_source", "verify_assets"},
        "self_test": {"verify_public_archive_bin"},
    }
    for function, required_calls in expected_calls.items():
        missing = required_calls - calls.get(function, set())
        if missing:
            errors.append(
                f"release packager {function} missing calls {sorted(missing)}"
            )


def audit_script_signing(errors, tree, label):
    for node in ast.walk(tree):
        if not (
            isinstance(node, ast.Constant)
            and isinstance(node.value, str)
        ):
            continue
        tokens = set(re.findall(r"[a-z0-9_.-]+", node.value.lower()))
        matches = SIGNING_COMMANDS & tokens
        if matches:
            errors.append(
                f"{label} contains signing capability {sorted(matches)}"
            )
            return


def audit_imports(
    errors, tree, label, allowed_imports, allowed_from
):
    parents = {}
    for parent in ast.walk(tree):
        for child in ast.iter_child_nodes(parent):
            parents[child] = parent
    actual_imports = set()
    actual_from = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if not isinstance(parents.get(node), ast.Module):
                errors.append(f"{label} must not use local imports")
            for alias in node.names:
                if alias.asname is not None:
                    errors.append(f"{label} must not alias imports")
                actual_imports.add(alias.name)
        elif isinstance(node, ast.ImportFrom):
            if not isinstance(parents.get(node), ast.Module):
                errors.append(f"{label} must not use local imports")
            names = actual_from.setdefault(node.module, set())
            for alias in node.names:
                if alias.asname is not None or alias.name == "*":
                    errors.append(f"{label} has an unsafe from-import")
                names.add(alias.name)
    if actual_imports != allowed_imports or actual_from != allowed_from:
        errors.append(f"{label} import allowlist changed")


def enclosing_function(node, parents):
    node = parents.get(node)
    while node is not None and not isinstance(node, ast.FunctionDef):
        node = parents.get(node)
    return node.name if node is not None else None


def audit_process_execution(errors, tree, label, allowed_argv):
    parents = {}
    for parent in ast.walk(tree):
        for child in ast.iter_child_nodes(parent):
            parents[child] = parent
    denied_imports = {"ctypes", "importlib", "runpy"}
    denied_os_calls = {
        "system", "popen", "posix_spawn", "posix_spawnp",
        "spawnl", "spawnle", "spawnlp", "spawnlpe",
        "spawnv", "spawnve", "spawnvp", "spawnvpe",
        "execl", "execle", "execlp", "execlpe",
        "execv", "execve", "execvp", "execvpe",
    }
    process_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported = {alias.name.split(".", 1)[0] for alias in node.names}
            if imported & denied_imports:
                errors.append(f"{label} imports an execution-capable loader")
        elif isinstance(node, ast.ImportFrom):
            if (node.module or "").split(".", 1)[0] in denied_imports:
                errors.append(f"{label} imports an execution-capable loader")
        elif (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id in {
                "eval", "exec", "compile", "__import__", "getattr",
            }
        ):
            errors.append(f"{label} uses dynamic code execution")
        elif (
            isinstance(node, ast.Attribute)
            and isinstance(node.value, ast.Name)
            and node.value.id == "os"
            and node.attr in denied_os_calls
        ):
            errors.append(f"{label} references forbidden os.{node.attr}")
        elif (
            isinstance(node, ast.Attribute)
            and isinstance(node.value, ast.Name)
            and node.value.id == "subprocess"
            and not (
                isinstance(parents.get(node), ast.Call)
                and parents[node].func is node
            )
        ):
            errors.append(f"{label} aliases a subprocess capability")
        elif (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "os"
            and node.func.attr in denied_os_calls
        ):
            errors.append(f"{label} uses forbidden os.{node.func.attr}")
        elif (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "subprocess"
        ):
            if node.func.attr != "run":
                errors.append(
                    f"{label} uses forbidden subprocess.{node.func.attr}"
                )
                continue
            process_calls.append(node)
    seen = set()
    for call in process_calls:
        function = enclosing_function(call, parents)
        argv = (
            ast_shape(call.args[0])
            if len(call.args) == 1 else None
        )
        expected = allowed_argv.get(function)
        keywords = {keyword.arg for keyword in call.keywords}
        if (
            expected is None
            or argv != expected[0]
            or keywords != expected[1]
        ):
            errors.append(
                f"{label} has unapproved subprocess argv in {function}"
            )
        seen.add(function)
        if "shell" in keywords:
            errors.append(f"{label} must not use subprocess shell mode")
    if seen != set(allowed_argv):
        errors.append(
            f"{label} subprocess function allowlist changed: "
            f"{sorted(value for value in seen if value)}"
        )


def audit_smoke_source(errors, smoke_source):
    try:
        tree = ast.parse(smoke_source)
    except SyntaxError as error:
        errors.append(f"release smoke script does not parse: {error}")
        return
    audit_script_signing(errors, tree, "release smoke script")
    audit_imports(
        errors,
        tree,
        "release smoke script",
        {
            "argparse", "hashlib", "json", "os", "shutil",
            "subprocess", "sys", "uuid",
        },
        {
            "pathlib": {"Path"},
            "release_common": {"parse_semver"},
        },
    )
    audit_process_execution(errors, tree, "release smoke script", {
        "ghr_install": (
            sequence(
                constant("ghr"), constant("install"), name("spec")
            ),
            {"check", "capture_output", "text", "env"},
        ),
        "rpmz_version": (
            sequence(name("path"), constant("--version")),
            {"check", "capture_output", "text", "env"},
        ),
        "compatibility_version": (
            sequence(name("path"), constant("tdnf"), constant("--version")),
            {"check", "capture_output", "text", "env"},
        ),
        "native_audit": (
            sequence(
                attribute(name("sys"), "executable"),
                call(
                    "str",
                    binop(
                        "Div",
                        name("ROOT"),
                        constant("scripts/librpm-audit.py"),
                    ),
                ),
                constant("--prefix"),
                call("str", name("prefix")),
            ),
            {"check", "capture_output", "text", "env"},
        ),
        "release_assets": (
            sequence(
                constant("gh"),
                constant("release"),
                constant("view"),
                name("tag"),
                constant("--repo"),
                name("repo"),
                constant("--json"),
                constant("assets"),
            ),
            {"check", "capture_output", "text", "env"},
        ),
        "download_assets": (
            sequence(
                constant("gh"),
                constant("release"),
                constant("download"),
                name("tag"),
                constant("--repo"),
                name("repo"),
                constant("--dir"),
                call("str", name("directory")),
                constant("--pattern"),
                name("archive_name"),
                constant("--pattern"),
                binop(
                    "Add",
                    name("archive_name"),
                    constant(".sha256"),
                ),
            ),
            {"check", "capture_output", "text", "env"},
        ),
    })
    parents = {}
    for parent in ast.walk(tree):
        for child in ast.iter_child_nodes(parent):
            parents[child] = parent
    functions = {
        node.name: node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    function = functions.get("run_smoke")
    if function is None:
        errors.append("release smoke script is missing run_smoke")
        return
    runner_methods = [
        call for call in ast.walk(function)
        if isinstance(call, ast.Call)
        and isinstance(call.func, ast.Attribute)
        and isinstance(call.func.value, ast.Name)
        and call.func.value.id == "runner"
    ]
    method_names = [call.func.attr for call in runner_methods]
    expected_methods = [
        "ghr_install", "rpmz_version", "compatibility_version", "native_audit",
        "release_assets", "download_assets",
    ]
    if sorted(method_names) != sorted(expected_methods):
        errors.append(
            "release smoke runner method allowlist changed"
        )
    conditional_nodes = (
        ast.If, ast.For, ast.AsyncFor, ast.While, ast.Try, ast.Match,
        ast.IfExp,
    )
    ghr_calls = [
        call for call in runner_methods
        if call.func.attr == "ghr_install"
    ]
    node = parents.get(ghr_calls[0])
    while node is not None and node is not function:
        if isinstance(node, conditional_nodes):
            errors.append(
                "release smoke ghr install call must be unconditional"
            )
            break
        node = parents.get(node)
    main_function = functions.get("main")
    main_calls = [
        call for call in ast.walk(main_function)
        if isinstance(call, ast.Call)
        and isinstance(call.func, ast.Name)
        and call.func.id == "run_smoke"
    ] if main_function is not None else []
    if len(main_calls) != 1:
        errors.append("release smoke main must call run_smoke exactly once")
    else:
        node = parents.get(main_calls[0])
        while node is not None and node is not main_function:
            if isinstance(node, conditional_nodes):
                errors.append(
                    "release smoke main call must be unconditional"
                )
                break
            node = parents.get(node)
    call_names = {
        call.func.id
        for call in ast.walk(function)
        if isinstance(call, ast.Call)
        and isinstance(call.func, ast.Name)
    }
    for required in ("validate_arguments", "expected_assets",
                     "verify_checksum"):
        if required not in call_names:
            errors.append(
                f"release smoke is missing {required} verification"
            )


def audit_release_workflow(errors, document):
    expect(
        errors,
        set(document) == {"name", "on", "permissions", "jobs"},
        "release workflow root key allowlist changed",
    )
    expect(errors, document.get("name") == "Release",
           "release workflow name must be Release")
    expect(
        errors,
        document.get("on") == {"push": {"tags": ["v*"]}},
        "release workflow must trigger only on pushed v* tags",
    )
    expect(
        errors,
        document.get("permissions") == {"contents": "read"},
        "release workflow default permissions must be contents: read",
    )
    jobs = document.get("jobs")
    if not isinstance(jobs, dict):
        errors.append("release workflow jobs must be a mapping")
        return
    expected_jobs = {"build", "source", "release", "post-release-smoke"}
    expect(errors, set(jobs) == expected_jobs,
           "release workflow job set changed")

    for name in ("build", "source", "post-release-smoke"):
        job = jobs.get(name, {})
        expect(
            errors,
            "permissions" not in job,
            f"{name} must inherit read-only workflow permissions",
        )
        checkout = action_step(job, "actions/checkout@")
        expect(
            errors,
            checkout is not None and "with" not in checkout,
            f"{name} checkout must retain only the read-scoped token",
        )
    release = jobs.get("release", {})
    expect(
        errors,
        release.get("permissions") == {
            "contents": "write",
            "id-token": "write",
            "attestations": "write",
        },
        "release job must have the only write/OIDC/attestation permissions",
    )
    expect(errors, release.get("needs") == ["build", "source"],
           "release job must need build and source")
    release_checkout = action_step(release, "actions/checkout@")
    expect(
        errors,
        release_checkout is not None
        and release_checkout.get("with") == {
            "persist-credentials": False,
        },
        "release checkout must not retain its write-scoped token",
    )

    build = jobs.get("build", {})
    source = jobs.get("source", {})
    smoke = jobs.get("post-release-smoke", {})
    expect(errors, build.get("runs-on") == "${{ matrix.os }}",
           "build must run on its matrix OS")
    expect(errors, matrix(build) == PLATFORMS,
           "build platform matrix changed")
    expect(errors, smoke.get("runs-on") == "${{ matrix.os }}",
           "smoke must run on its matrix OS")
    expect(errors, matrix(smoke) == PLATFORMS,
           "smoke platform matrix changed")
    expect(errors, smoke.get("needs") == "release",
           "post-release smoke must need release")
    expected_steps = {
        "build": [
            ("uses", "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"),
            ("uses", "mlugg/setup-zig@d1434d08867e3ee9daa34448df10607b98908d29"),
            ("uses", "./.github/actions/zig-cache"),
            ("name", "Get version"),
            ("name", "Build normal install layout"),
            ("name", "Package binary archive, checksum, and SBOM"),
            ("uses", "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"),
        ],
        "source": [
            ("uses", "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"),
            ("name", "Get version"),
            ("name", "Package source archive and checksum"),
            ("uses", "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"),
        ],
        "release": [
            ("uses", "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"),
            ("uses", "actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093"),
            ("name", "Get version"),
            ("uses", "actions/attest-build-provenance@c074443f1aee8d4aeeae555aebba3282517141b2"),
            ("uses", "softprops/action-gh-release@da05d552573ad5aba039eaac05058a918a7bf631"),
        ],
        "post-release-smoke": [
            ("uses", "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"),
            ("name", "Install pinned ghr"),
            ("name", "Get version"),
            ("name", "Install and audit published release"),
        ],
    }
    expected_job_keys = {
        "build": {"name", "runs-on", "strategy", "steps"},
        "source": {"name", "runs-on", "steps"},
        "release": {
            "name", "needs", "runs-on", "permissions", "steps",
        },
        "post-release-smoke": {
            "name", "needs", "runs-on", "strategy", "steps",
        },
    }
    for name, identities in expected_steps.items():
        expect(
            errors,
            step_identities(jobs.get(name, {})) == identities,
            f"{name} step/action allowlist changed",
        )
        expect(
            errors,
            set(jobs.get(name, {})) == expected_job_keys[name],
            f"{name} job key allowlist changed",
        )
        expect(
            errors,
            "env" not in jobs.get(name, {}),
            f"{name} must not define job-level environment variables",
        )
        for step in job_steps(jobs.get(name, {})):
            if "uses" in step:
                if step["uses"].startswith("actions/checkout@"):
                    expected_keys = (
                        {"uses", "with"}
                        if name == "release"
                        else {"uses"}
                    )
                elif step["uses"] == "./.github/actions/zig-cache":
                    expected_keys = {"uses"}
                elif step["uses"].startswith(
                    ("actions/attest-build-provenance@",
                     "softprops/action-gh-release@")
                ):
                    expected_keys = {"name", "uses", "with"}
                else:
                    expected_keys = {"uses", "with"}
            elif step.get("name") == "Get version":
                expected_keys = {"name", "id", "run"}
            elif (
                name == "post-release-smoke"
                and step.get("name")
                == "Install and audit published release"
            ):
                expected_keys = {"name", "env", "run"}
            else:
                expected_keys = {"name", "run"}
            expect(
                errors,
                set(step) == expected_keys,
                f"{name}/{step.get('name', step.get('uses'))} "
                "step key allowlist changed",
            )

    version_command = (
        'python3 scripts/release.py version --tag "$GITHUB_REF_NAME" \\',
        '>> "$GITHUB_OUTPUT"',
    )
    for name in ("build", "source", "release", "post-release-smoke"):
        step = named_step(jobs.get(name, {}), "Get version")
        expect(
            errors,
            step is not None
            and step.get("id") == "version"
            and tuple(shell_lines(step.get("run"))) == version_command,
            f"{name} must use the shared tag version parser",
        )

    binary = named_step(build, "Package binary archive, checksum, and SBOM")
    expect(
        errors,
        binary is not None
        and shell_lines(binary.get("run")) == [
            "python3 scripts/release.py binary \\",
            "--prefix ./release-install \\",
            "--output ./release-assets \\",
            '--version "${{ steps.version.outputs.version }}" \\',
            '--platform "${{ matrix.platform }}"',
        ],
        "build must package binaries with scripts/release.py",
    )
    build_step = named_step(build, "Build normal install layout")
    expect(
        errors,
        build_step is not None
        and shell_lines(build_step.get("run")) == [
            "zig build -Doptimize=ReleaseSafe \\",
            '"-Dversion=${{ steps.version.outputs.version }}" \\',
            "install --prefix ./release-install",
        ],
        "release build command changed",
    )
    setup_zig = action_step(build, "mlugg/setup-zig@")
    expect(
        errors,
        setup_zig is not None
        and setup_zig.get("with") == {
            "version": "0.16.0",
            "use-cache": False,
        },
        "release Zig setup inputs changed",
    )
    source_package = named_step(source, "Package source archive and checksum")
    expect(
        errors,
        source_package is not None
        and shell_lines(source_package.get("run")) == [
            "python3 scripts/release.py source \\",
            "--output ./release-assets \\",
            '--version "${{ steps.version.outputs.version }}"',
        ],
        "source must package with scripts/release.py",
    )
    build_upload = action_step(build, "actions/upload-artifact@")
    expect(
        errors,
        build_upload is not None
        and build_upload.get("with") == {
            "name": "${{ matrix.platform }}",
            "path": "release-assets/",
        },
        "build artifact upload layout changed",
    )
    source_upload = action_step(source, "actions/upload-artifact@")
    expect(
        errors,
        source_upload is not None
        and source_upload.get("with") == {
            "name": "source",
            "path": "release-assets/",
        },
        "source artifact upload layout changed",
    )
    download = action_step(release, "actions/download-artifact@")
    expect(
        errors,
        download is not None
        and download.get("with") == {
            "path": "release-assets",
            "merge-multiple": True,
        },
        "release artifact download layout changed",
    )
    attestation = action_step(
        release, "actions/attest-build-provenance@"
    )
    expect(errors, attestation is not None,
           "release must contain one provenance attestation action")
    if attestation is not None:
        expected_subjects = (
            "release-assets/rpmz-*.tar.gz\n"
            "release-assets/rpmz-*.tar.xz\n"
        )
        expect(
            errors,
            attestation.get("with") == {
                "subject-path": expected_subjects,
            },
            "attestation subjects must be binary and source archives",
        )

    create = action_step(release, "softprops/action-gh-release@")
    expect(errors, create is not None,
           "release must contain one GitHub release action")
    if create is not None:
        inputs = create.get("with", {})
        expected_body = (
            "**Install:**\n\n"
            "```sh\n"
            "ghr install cataggar/rpmz@v${{ "
            "steps.version.outputs.version }}\n"
            "```\n\n"
            "Binary archives expose one public executable: `bin/rpmz`. Use\n"
            "`rpmz tdnf [options] COMMAND` for dnf/yum-compatible "
            "operations,\n"
            "`rpmz repo-config` for repository configuration, and `rpmz "
            "auto`\n"
            "for scheduled updates. The archives also contain `lib/`,\n"
            "`libexec/`, and `etc/`, plus COPYING and README.md. SHA-256\n"
            "sidecars, SPDX SBOMs, and GitHub provenance attestations are\n"
            "published with the archives.\n"
        )
        expected_files = (
            "release-assets/rpmz-*.tar.gz\n"
            "release-assets/rpmz-*.tar.xz\n"
            "release-assets/rpmz-*.sha256\n"
            "release-assets/rpmz-*.sbom.spdx.json\n"
        )
        expect(
            errors,
            set(inputs) == {
                "name", "body", "files", "prerelease",
            },
            "release action inputs must use the exact allowlist",
        )
        expect(
            errors,
            inputs.get("name") == (
                "rpmz ${{ steps.version.outputs.version }}"
            ),
            "release name must be derived from the parsed version",
        )
        expect(
            errors,
            inputs.get("body") == expected_body,
            "release body changed",
        )
        expect(
            errors,
            inputs.get("files") == expected_files,
            "release asset patterns changed",
        )
        expect(
            errors,
            inputs.get("prerelease") == (
                "${{ steps.version.outputs.prerelease }}"
            ),
            "release prerelease input must use parsed SemVer output",
        )

    pinned_ghr = named_step(smoke, "Install pinned ghr")
    expect(
        errors,
        pinned_ghr is not None
        and shell_lines(pinned_ghr.get("run")) == [
            "pipx install ghr-bin==0.7.0"
        ],
        "smoke must install exactly ghr-bin 0.7.0",
    )
    smoke_run = named_step(smoke, "Install and audit published release")
    expect(
        errors,
        smoke_run is not None
        and shell_lines(smoke_run.get("run")) == [
            "python3 scripts/release-smoke.py \\",
            "--repo cataggar/rpmz \\",
            '--tag "$GITHUB_REF_NAME" \\',
            '--version "${{ steps.version.outputs.version }}" \\',
            '--platform "${{ matrix.platform }}" \\',
            '--prefix "$RUNNER_TEMP/rpmz-ghr-smoke"',
        ],
        "smoke workflow step must invoke only the audited smoke script",
    )
    expect(
        errors,
        smoke_run is not None
        and smoke_run.get("env", {}).get("GH_TOKEN")
        == "${{ secrets.GITHUB_TOKEN }}",
        "smoke may use only the read-scoped GitHub token",
    )
    for name, job in jobs.items():
        for step in job_steps(job):
            expected_env = (
                {"GH_TOKEN": "${{ secrets.GITHUB_TOKEN }}"}
                if name == "post-release-smoke"
                and step.get("name") == "Install and audit published release"
                else None
            )
            expect(
                errors,
                step.get("env") == expected_env
                if expected_env is not None
                else "env" not in step,
                f"{name}/{step.get('name', step.get('uses'))} env allowlist changed",
            )

    forbidden = (
        "cataggar/" + "td" + "nf",
        "td" + "nf-",
        "minisign",
        ".minisig",
        "signing_secret",
        "signing secret",
    )
    for scalar in walk_scalars(document):
        lowered = scalar.lower()
        for token in forbidden:
            if token in lowered:
                errors.append(
                    f"release workflow contains forbidden token {token!r}"
                )
                return
        command_tokens = set(re.findall(r"[a-z0-9_.-]+", lowered))
        matches = SIGNING_COMMANDS & command_tokens
        if matches:
            errors.append(
                f"release workflow contains signing capability {sorted(matches)}"
            )
            return
        if "secrets." in lowered and scalar != "${{ secrets.GITHUB_TOKEN }}":
            errors.append("release workflow contains an unapproved secret")
            return


def audit_ci_workflow(errors, document):
    expect(
        errors,
        set(document) == {"name", "on", "permissions", "jobs"},
        "CI workflow root key allowlist changed",
    )
    expect(
        errors,
        document.get("permissions") == {"contents": "read"},
        "CI workflow default permissions must be contents: read",
    )
    jobs = document.get("jobs", {})
    dry_run = jobs.get("release-dry-run", {})
    expect(errors, "permissions" not in dry_run,
           "release dry-run must inherit read-only CI permissions")
    checkout = action_step(dry_run, "actions/checkout@")
    expect(
        errors,
        checkout is not None and "with" not in checkout,
        "release dry-run checkout must retain only the read-scoped token",
    )
    step = named_step(dry_run, "Package and verify v0.1.0 locally")
    expect(
        errors,
        step is not None
        and shell_lines(step.get("run")) == [
            "zig build -Doptimize=ReleaseSafe -Dversion=0.1.0 \\",
            "release-dry-run --prefix ./release-install",
        ],
        "CI release dry-run command changed",
    )


def audit(
    release_source, ci_source, manifest, packager, smoke_source,
    common_source,
):
    errors = []
    try:
        release_document = parse_workflow(release_source)
        ci_document = parse_workflow(ci_source)
    except (YamlError, ValueError, SyntaxError) as error:
        return [f"workflow YAML parse failed: {error}"]
    audit_release_workflow(errors, release_document)
    audit_ci_workflow(errors, ci_document)
    audit_packager(errors, manifest, packager)
    audit_smoke_source(errors, smoke_source)
    common_tree = ast.parse(common_source)
    audit_script_signing(errors, common_tree, "release common helper")
    audit_imports(
        errors,
        common_tree,
        "release common helper",
        {"re"},
        {},
    )
    audit_process_execution(
        errors, common_tree, "release common helper", {}
    )
    return errors


def test_semver():
    spec = importlib.util.spec_from_file_location(
        "rpmz_release_common_test", COMMON
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    cases = {
        "0.1.0": False,
        "0.1.0+build-7": False,
        "0.1.0-rc.1": True,
        "0.1.0-rc.1+build-7": True,
    }
    for version, expected in cases.items():
        parsed, prerelease = module.parse_semver(version)
        if parsed != version or prerelease is not expected:
            raise AssertionError(f"SemVer case failed: {version}")
    for invalid in ("01.1.0", "0.1", "0.1.0-", "0.1.0+"):
        try:
            module.parse_semver(invalid)
        except ValueError:
            continue
        raise AssertionError(f"invalid SemVer accepted: {invalid}")


def self_test(
    release_source, ci_source, manifest, packager, smoke_source,
    common_source,
):
    commented_permissions = release_source.replace(
        "permissions:\n  contents: read",
        "permissions:\n  contents: write\n# contents: read",
        1,
    )
    missing_job_permissions = release_source.replace(
        "    permissions:\n"
        "      contents: write\n"
        "      id-token: write\n"
        "      attestations: write\n",
        "",
        1,
    ) + (
        "\n# permissions:\n#   contents: write\n"
        "#   id-token: write\n#   attestations: write\n"
    )
    write_build_permissions = release_source.replace(
        "  build:\n    name:",
        "  build:\n    permissions:\n      contents: write\n    name:",
        1,
    )
    retained_write_checkout = release_source.replace(
        "          persist-credentials: false",
        "          persist-credentials: true  # false",
        1,
    )
    wrong_needs = release_source.replace(
        "    needs: release",
        "    needs: build  # needs: release",
        1,
    )
    wrong_asset = release_source.replace(
        "            release-assets/rpmz-*.sha256\n",
        "            release-assets/rpmz-checksums.txt\n"
        "            # release-assets/rpmz-*.sha256\n",
        1,
    )
    wrong_smoke_script = release_source.replace(
        "          python3 scripts/release-smoke.py \\",
        "          python3 scripts/release-smoke-decoy.py \\\n"
        "          # python3 scripts/release-smoke.py \\",
        1,
    )
    wrong_matrix = release_source.replace(
        "          - os: ubuntu-24.04-arm\n"
        "            platform: linux-arm64",
        "          - os: ubuntu-24.04\n"
        "            platform: linux-arm64",
        1,
    )
    signing_step = release_source.replace(
        "      - name: Create release",
        "      - name: Signing secret decoy\n"
        "        run: echo minisign\n"
        "      - name: Create release",
        1,
    )
    hardcoded_tag = release_source.replace(
        "        with:\n"
        "          name: rpmz ${{ steps.version.outputs.version }}",
        "        with:\n"
        "          tag_name: v0.1.0\n"
        "          name: rpmz ${{ steps.version.outputs.version }}",
        1,
    )
    draft_override = release_source.replace(
        "          prerelease: ${{ steps.version.outputs.prerelease }}",
        "          draft: false\n"
        "          prerelease: ${{ steps.version.outputs.prerelease }}",
        1,
    )
    gpg_secret_step = release_source.replace(
        "      - name: Create release",
        "      - name: GPG sign release\n"
        "        env:\n"
        "          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}\n"
        "        run: gpg --sign release-assets/rpmz.tar.gz\n"
        "      - name: Create release",
        1,
    )
    wrong_ci_permissions = ci_source.replace(
        "permissions:\n  contents: read",
        "permissions:\n  contents: write\n# contents: read",
        1,
    )
    global_token_env = release_source.replace(
        "permissions:\n  contents: read",
        "env:\n"
        "  GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}\n\n"
        "permissions:\n  contents: read",
        1,
    )
    cases = [
        (commented_permissions, ci_source),
        (missing_job_permissions, ci_source),
        (write_build_permissions, ci_source),
        (retained_write_checkout, ci_source),
        (wrong_needs, ci_source),
        (wrong_asset, ci_source),
        (wrong_smoke_script, ci_source),
        (wrong_matrix, ci_source),
        (signing_step, ci_source),
        (hardcoded_tag, ci_source),
        (draft_override, ci_source),
        (gpg_secret_step, ci_source),
        (release_source, wrong_ci_permissions),
        (global_token_env, ci_source),
    ]
    for release_case, ci_case in cases:
        if not audit(
            release_case, ci_case, manifest, packager, smoke_source,
            common_source,
        ):
            raise AssertionError(
                "structural negative workflow self-test was accepted"
            )
    broken = dict(manifest)
    broken["platforms"] = ["linux-x64"]
    if not audit(
        release_source, ci_source, broken, packager, smoke_source,
        common_source,
    ):
        raise AssertionError("negative manifest self-test was accepted")

    def assert_packager_probe(lines, description):
        probe = packager.replace(
            "def package_binary(args):",
            "def package_binary(args):\n" + "\n".join(
                "    " + line for line in lines
            ),
            1,
        )
        if not audit(
            release_source, ci_source, manifest, probe,
            smoke_source, common_source,
        ):
            raise AssertionError(f"{description} probe was accepted")

    packager_probe = packager.replace(
        "def package_binary(args):",
        "def package_binary(args):\n"
        '    subprocess.run(["gp" + "g", "--sign"], check=True)',
        1,
    )
    if not audit(
        release_source, ci_source, manifest, packager_probe,
        smoke_source, common_source,
    ):
        raise AssertionError("dynamic package signing probe was accepted")
    assert_packager_probe(
        [
            "import subprocess as sp",
            'sp.run(["gp" + "g", "--sign"], check=True)',
        ],
        "local aliased subprocess import",
    )
    assert_packager_probe(
        [
            "from subprocess import run as x",
            'x(["gp" + "g", "--sign"], check=True)',
        ],
        "local aliased subprocess from-import",
    )
    assert_packager_probe(
        [
            "runner = subprocess.run",
            'runner(["gp" + "g", "--sign"], check=True)',
        ],
        "subprocess assignment alias",
    )
    assert_packager_probe(
        [
            'getattr(subprocess, "run")(',
            '    ["gp" + "g", "--sign"], check=True',
            ")",
        ],
        "dynamic subprocess getattr",
    )
    smoke_probe = smoke_source.replace(
        "def run_smoke(args, runner=None):",
        "def run_smoke(args, runner=None):\n"
        '    subprocess.run(["gp" + "g", "--sign"], check=True)',
        1,
    )
    if not audit(
        release_source, ci_source, manifest, packager,
        smoke_probe, common_source,
    ):
        raise AssertionError("dynamic smoke signing probe was accepted")
    download_source = smoke_source.replace(
        '["ghr", "install", spec]',
        '["ghr", "download", spec]',
        1,
    ) + '\n# ["ghr", "install", spec]\n'
    smoke_errors = []
    audit_smoke_source(smoke_errors, download_source)
    if not smoke_errors:
        raise AssertionError("ghr download smoke decoy was accepted")
    conditional_source = """
def run_smoke(args, runner):
    validate_arguments(args, {})
    expected_assets({}, "0.1.0")
    verify_checksum(None, "archive")
    if False:
        runner.ghr_install("cataggar/rpmz@v0.1.0", {})
"""
    smoke_errors = []
    audit_smoke_source(smoke_errors, conditional_source)
    if not any("unconditional" in error for error in smoke_errors):
        raise AssertionError("conditional ghr install smoke was accepted")
    test_semver()
    smoke_spec = importlib.util.spec_from_file_location(
        "rpmz_release_smoke_self_test", SMOKE
    )
    smoke_module = importlib.util.module_from_spec(smoke_spec)
    smoke_spec.loader.exec_module(smoke_module)
    smoke_module.self_test()


def main():
    release_source = WORKFLOW.read_text(encoding="utf-8")
    ci_source = CI_WORKFLOW.read_text(encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    packager = PACKAGER.read_text(encoding="utf-8")
    smoke_source = SMOKE.read_text(encoding="utf-8")
    common_source = COMMON.read_text(encoding="utf-8")
    self_test(
        release_source, ci_source, manifest, packager, smoke_source,
        common_source,
    )
    errors = audit(
        release_source, ci_source, manifest, packager, smoke_source,
        common_source,
    )
    if errors:
        print("rpmz release audit failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    print("rpmz release audit passed (structural YAML and SemVer self-tests)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
