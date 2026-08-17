# rpmz

rpmz is a Zig dnf/yum-compatible RPM package manager.
It is derived from upstream [tdnf](https://github.com/vmware/tdnf).

## Install

```sh
ghr install cataggar/rpmz@v0.1.0
```

## Build from source

```sh
zig build -Doptimize=ReleaseSafe install --prefix ./out
```

## Command model

The install publishes one executable: `rpmz`. Use `rpmz tdnf [options] COMMAND` for
dnf/yum-compatible package operations, `rpmz repo-config` to manage repository files,
and `rpmz auto` for scheduled updates.
To retain `tdnf [options] COMMAND`, create a user-managed `tdnf -> rpmz`
symlink in a directory on `PATH`; rpmz does not install that symlink.

## Documentation

- [Configuration and usage](doc/configuration.md)
- [Public Zig API and transaction plans](doc/transaction-plan-api.md)
- [Transaction bundles](doc/transaction-bundle.md) and [replay](doc/replay-api.md)
- [Contributing](CONTRIBUTING.md), [building, and testing](doc/building-and-testing.md)
- [Migration from tdnf](doc/migrating-from-tdnf.md)
