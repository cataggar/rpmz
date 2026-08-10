# tdnf - Copilot instructions

tdnf is a Zig implementation of a dnf/yum-compatible package manager. It
uses vendored `libsolv`, the native Zig RPM stack under `rpmzig/`, and Zig
HTTP/TLS downloads. The supported distribution surfaces are the `tdnf` Zig
package module and executable/tools; there is no public C SDK or installed
`libtdnf*` shared library.

## Build, test, lint

The build requires Zig 0.16+ and is driven by `build.zig`.

```sh
zig build -Doptimize=ReleaseSafe install --prefix ./out
zig build test
zig build -Doptimize=ReleaseSafe test
zig build check
zig build lint
```

The full pytest suite needs an rpm-aware host with `rpmbuild`,
`createrepo_c`, pytest, requests, and pyOpenSSL. For one pytest, run from
`pytests/` so `config.json` is found:

```sh
cd pytests && pytest -v tests/test_install.py::test_install_no_arg
```

The pytest `utils` fixture rewrites `tdnf`/`tdnf-config` commands to the
build tree and injects the test configuration. Use `utils.run([...])` rather
than invoking those commands directly. Tests must remove packages they
install because the consistency fixture checks host state.

CI builds without RPM development files, runs Debug and ReleaseSafe Zig
tests, lint, migration and dependency audits, the external public Zig
consumer, installed-ELF checks, and native smoke helpers. The default branch
is `main`.

## Architecture

`build.zig` composes private Zig modules directly into the executables:

| Component | Purpose |
|---|---|
| `common/` | logging, memory wrappers, strings, file locking |
| `llconf/` | vendored ini/config parser |
| `jsondump/` | CLI JSON output |
| `history/` | sqlite-backed transaction history |
| `repomd/` | repository models, query engine, authoritative solver |
| `rpmzig/` | RPM parsing, rpmdb, verification, transactions, scriptlets |
| `client/` | package-manager orchestration |
| `tools/cli/` | CLI parsing, output, and subcommand dispatch |
| `tools/config/` | `tdnf-config` |
| `plugins/` | built-in metalink and repository-signature modules |

Dependency direction is `tools/cli` → `client` → `repomd`/`rpmzig` →
foundational modules. Cross-component implementation dependencies use Zig
modules registered in `build.zig`, not public C headers.

The public package boundary is `b.addModule("tdnf", ...)` in `build.zig`.
Consumers import `@import("tdnf").transaction_plan`; files under component
directories are private.

`abi/internal.zig` contains private transitional declarations for internal
symbols still linked with the C calling convention. It is not installed or
part of the public Zig module. Do not recreate an installed C header,
pkg-config, or shared-library surface.

## Generated files

`build.zig` writes `pytests/config.json`, `pytests/mount-small-cache`, and
`bin/tdnf-automatic` into the source tree. Edit their templates, not generated
outputs.

Edit the corresponding templates, not generated outputs.

## Native RPM implementation

`rpmzig/` owns package parsing, rpmdb access, OpenPGP verification,
configuration, pubkey import, source extraction, file install/erase,
scriptlets, triggers, and transaction execution. The composed native
executor is unconditional; there is no host implementation fallback.
Multi-instance upgrades are refused explicitly.

System RPM and Lua headers, symbols, runtime loads, and link declarations
are forbidden by `scripts/librpm-audit.py`. Host RPM commands remain
test-only fixture generators and behavior oracles. Vendored SQLite and
libsolv may compile C internally, but no project-owned `.c` file may be
tracked.

Native smoke helpers are installed under `libexec/tdnf/`, including the
rpmdb, package inspection, verification, install, erase, scriptlet, and
trigger tools. `tdnf-test-support` is also installed there as the private
command bridge used by pytest; a normal install must remain sufficient before
running the integration suite.

## Zig conventions

- Prefer typed Zig errors for new internal APIs. Preserve existing numeric
  `ERROR_TDNF_*` behavior where tests or CLI output expose it.
- Allocate into locals and transfer ownership only on success.
- Avoid broad catches and silent fallback behavior.
- Use `common.log`/existing logging helpers rather than ad-hoc output from
  package-manager code.
- Match surrounding naming while converting legacy code; internal exported
  symbols may retain `TDNF*` names until their callers are migrated.
- Keep remaining `@cImport` declarations private and narrow. Prefer canonical
  Zig declarations over adding another header.

See `doc/coding-guidelines.md`.

## Audits

Run:

```sh
zig build migration-audit
zig build dead-errdefer-audit
zig build -Doptimize=ReleaseSafe install --prefix ./out
zig build -Doptimize=ReleaseSafe native-dependency-audit --prefix ./out
zig build -Doptimize=ReleaseSafe public-zig-api-audit --prefix ./out
zig build -Doptimize=ReleaseSafe libsolv-confinement-audit --prefix ./out
```

The migration audit permanently rejects project-owned C, public C headers,
retired C SDK files, dynamic-library declarations, and removal of the public
Zig module/audit. The native dependency audit validates the final install
layout and rejects `libtdnf*`, installed headers, `.pc` files, and forbidden
dynamic dependencies.

When changing libsolv-facing code, read `doc/migration-verification.md` and
run the opt-in oracle:

```sh
zig build -Dlibsolv-oracle=true libsolv-oracle-test
```

Version defaults live in both `build.zig` and `build.zig.zon`.

## Commits and PRs

Open PRs against `main`. Keep commits as logical, independently mergeable
units and squash fixups into the commit that introduced them.
