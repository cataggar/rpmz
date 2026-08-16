# Migration from tdnf

rpmz is derived from upstream [tdnf](https://github.com/vmware/tdnf). The
product-facing names changed as follows:

| tdnf name | rpmz name |
|---|---|
| `tdnf` | `rpmz` |
| `tdnf-config` | `rpmz repo-config` |
| `tdnf-automatic` | `rpmz-automatic` |
| `tdnfmetalink` | `rpmzmetalink` |
| `tdnfrepogpgcheck` | `rpmzrepogpgcheck` |
| `tdnfmetalink.conf` | `rpmzmetalink.conf` |
| `tdnfrepogpgcheck.conf` | `rpmzrepogpgcheck.conf` |
| Zig dependency/module and `@import("tdnf")` | dependency/module and `@import("rpmz")` |
| `/etc/tdnf` | `/etc/rpmz` |
| `<prefix>/libexec/tdnf` | `<prefix>/libexec/rpmz` |
| `<prefix>/lib/systemd/system/tdnf-automatic*` | `<prefix>/lib/systemd/system/rpmz-automatic*` |
| `<prefix>/share/bash-completion/completions/tdnf` | `<prefix>/share/bash-completion/completions/rpmz` |

The systemd directory can be changed with `-Dsystemd-dir`; the table shows the
default installed path. Configuration files, plugin configuration, and
automatic-update configuration now live below `/etc/rpmz`.

`--enableplugin` and `--disableplugin` values, plus copied files under
`/etc/rpmz/pluginconf.d`, must use the rpmz names because no legacy plugin
aliases exist.

## Intentional compatibility remnants

The command and configuration rebrand does not rename compatibility data:

- Serialized `tdnf.*` protocol, schema, and hash identifiers remain stable
  across the rebrand. This includes transaction plans, bundles, replay results,
  repository snapshots, rpmdb package sets, and hash/cache identities such as
  `tdnf-solv-content-v3` and `tdnf-solv-cache-options/v1`.
- `/var/lib/tdnf` remains the persistent history and transaction-lock state
  location and must be preserved.
- `/var/cache/tdnf` remains the shared package and repository cache and must be
  preserved.
- Private `TDNF_*` and `ERROR_TDNF_*` ABI identifiers remain in internal code;
  they are not a public C SDK.
- tdnf-named test fixtures retain their names so historical behavior and
  migration expectations stay comparable.

Do not delete, rename, or move legacy state or cache directories merely because
commands and configuration paths were rebranded. Keeping them in place
preserves history, package marks, locks, and reusable cache data across the
upgrade.
