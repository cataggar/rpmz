# tdnf - tiny dandified yum

A Zig implementation of a dnf/yum-compatible package manager built on
vendored `libsolv`, with native RPM handling in `rpmzig/` and downloads
through Zig's HTTP/TLS stack. tdnf is distributed as a Zig package and
executable; it does not install a C SDK or shared libraries.

The public Zig workflow resolves a canonical `transaction_plan`, publishes its
inputs with `bundle_export`, validates the closed `transaction_bundle` through
`bundle_reader`, and applies its exact v2 order with offline `replay`. See
`doc/transaction-plan-api.md`, `doc/transaction-bundle.md`, and
`doc/replay-api.md`.

## Build

Requires Zig 0.16+. SQLite and libsolv are built from the dependencies
pinned in `build.zig.zon`. No RPM development package is needed. Binary
audits additionally use `binutils`; Python lint uses `flake8`.

Then:

```sh
zig build install --prefix ./out
```

This produces `./out/bin/tdnf`, `./out/bin/tdnf-config`, and the support
tools under `./out/libexec/tdnf/`.

Debug build:
```sh
zig build -Doptimize=Debug install --prefix ./out
```

Native Lua scriptlet support (for `<lua>` RPM scriptlets) is always
enabled through the pure-Zig runtime pinned in `build.zig.zon`. No
system Lua headers or libraries are required. This is needed by real
base packages in supported distros, including Fedora
`bash`/`glibc`/`filesystem`/`setup` and Azure Linux `filesystem`.

The composed native transaction executor (rpmzig install, rpmdb-write,
file-erase, scriptlet, trigger engines) is the sole transaction-
execution path — every `tdnf install`/`erase`/`upgrade` dispatches
through it. There is no host-library fallback.

Zig consumers use the public `tdnf` module registered by this package's
`build.zig`. Its initial stable surface is the canonical transaction-plan
model from issue #186:

```zig
const tdnf_dep = b.dependency("tdnf", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("tdnf", tdnf_dep.module("tdnf"));
```

Application source can use:

- `@import("tdnf").resolver` and `.transaction_plan` to resolve and inspect a
  canonical plan;
- `.bundle_export`, `.transaction_bundle`, and `.bundle_reader` to publish and
  validate its closed input set;
- `.replay` to validate and apply one exact v2 bundle without resolving or
  entering a network-capable path.

Those namespaces are the whole supported surface. Consumers should not import
files from the component directories directly. There is no public C SDK,
header, pkg-config, or shared-library API.

`tdnf plan <verb>` prints the same document from the command line. See
[doc/transaction-plan-api.md](doc/transaction-plan-api.md) for what a plan
contains, the explicit-input and ownership rules, how failures are reported,
what makes two plans identical, and why planning never executes anything.

`tdnf replay --installroot ROOT --rpmdb-path /var/lib/rpm --forcearch ARCH
BUNDLE` validates and applies a replay-capable bundle. It always writes one
versioned canonical result to stdout for a valid invocation. See
[doc/replay-api.md](doc/replay-api.md) for the API ownership contract, v2
requirement, validation boundary, result schema, CLI exit statuses, and
network-isolation guidance.

## Configuration

Create `tdnf.conf` under `/etc/tdnf/`:

```text
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=true
repodir=/etc/yum.repos.d
cachedir=/var/cache/tdnf
```

Place `.repo` files under `/etc/yum.repos.d` (or your `repodir`).

```sh
./out/bin/tdnf list installed
```

## Testing

The pytest suite under `pytests/` exercises the binaries against a
locally-served rpm repo. It requires an rpm-aware host: `rpm`,
`rpmbuild`, `createrepo_c`, and the `python3-pytest`/`python3-requests`/
`python3-pyOpenSSL` stack. These are test fixture generators and
cross-check oracles only; production never invokes them. With those in
place:

```sh
zig build install --prefix ./out
cd pytests && pytest -v
```

The normal install includes `libexec/tdnf/tdnf-test-support`, the private
command bridge used by integration tests that need direct access to internal
Zig APIs. It ships with the other libexec helpers so the documented
install-then-pytest workflow has no hidden build prerequisite.

Or use the convenience step:

```sh
zig build check
```

The Zig integration suite under `ztests/` covers the same ground for the
commands it has been migrated to, and is much faster because each test
installs into its own throwaway root instead of the host rpmdb: a
disposable root starts empty, so a transaction has no installed packages
to validate against. It reuses the RPM fixtures `pytests` generates, and
skips itself when they are absent. Installing sets each file's owner from
its rpm header, so like pytest it needs root:

```sh
sudo -E zig build ztest --prefix ./out
```

The CI-sized native smoke suite builds signed fixture packages with the
host tools, then executes every `tdnf-rpm*` helper against scratch roots:

```sh
./scripts/smoke-rpmzig.sh ./out
```

Dependency, public-Zig-consumer, and migration gates are available as:

```sh
zig build -Doptimize=ReleaseSafe native-dependency-audit --prefix ./out
zig build -Doptimize=ReleaseSafe public-zig-api-audit --prefix ./out
zig build -Doptimize=ReleaseSafe migration-audit --prefix ./out
zig build replay-docs-audit
zig build replay-confinement-audit
zig build -Doptimize=ReleaseSafe dead-errdefer-audit --prefix ./out
zig build -Doptimize=ReleaseSafe libsolv-confinement-audit --prefix ./out
```

Use `-Doptimize=ReleaseSafe`, as CI does. The native dependency audit
inspects the installed prefix and rejects public C headers, pkg-config
metadata, `libtdnf*` artifacts, and forbidden dynamic dependencies.

`pytests/config.json`, `pytests/mount-small-cache`, and
`bin/tdnf-automatic` are generated by `build.zig` and are not source files.
Edit their templates instead.

## Static analysis (Coverity)

`ci/coverity.sh` wraps `zig build` with `cov-build`. It generates an
HTML report under `build-coverity/html/`.
