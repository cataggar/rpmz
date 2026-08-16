# rpmz

rpmz is a Zig dnf/yum-compatible RPM package manager.
It is derived from upstream [tdnf](https://github.com/vmware/tdnf).

## Install

For the upcoming v0.1.0 tagged release:

```sh
ghr install cataggar/rpmz@v0.1.0
```

## Build from source

```sh
zig build -Doptimize=ReleaseSafe install --prefix ./out
```

## Documentation

- [Configuration and usage](doc/configuration.md)
- [Public Zig API and transaction plans](doc/transaction-plan-api.md)
- [Transaction bundles](doc/transaction-bundle.md) and [replay](doc/replay-api.md)
- [Contributing](CONTRIBUTING.md), [building, and testing](doc/building-and-testing.md)
- [Migration from tdnf](doc/migrating-from-tdnf.md)
