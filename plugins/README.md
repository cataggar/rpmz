# Built-in rpmz plugins

rpmz composes two plugins directly into the executable; no plugin shared
objects are loaded:

- `rpmzmetalink` downloads metalink metadata, selects mirrors by preference,
  and validates `repomd.xml` with the strongest supported metalink checksum.
- `rpmzrepogpgcheck` verifies detached `repomd.xml.asc` signatures with the
  pure-Zig OpenPGP verifier. As before, keys come from the ambient GnuPG home
  (`GNUPGHOME`, or `$HOME/.gnupg`), not from the repository's `gpgkey=`.

The existing yum-compatible controls still select these built-ins:

- `plugins=1` in `rpmz.conf` enables plugin processing globally.
- `/etc/rpmz/pluginconf.d/rpmzmetalink.conf` and
  `rpmzrepogpgcheck.conf` each use `[main] enabled=0|1`.
- `--enableplugin=<name-or-glob>` and `--disableplugin=<name-or-glob>` apply
  sequentially, so later options override earlier matching options.
- `--noplugins` disables both built-ins.

`pluginconfpath=` may relocate the two configuration files. `pluginpath=` is
accepted for configuration compatibility but is not used because there are no
loadable plugin libraries or third-party plugin ABI.
