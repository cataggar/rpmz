# Configuration and usage

rpmz reads `/etc/rpmz/rpmz.conf`. A minimal configuration is:

```ini
[main]
gpgcheck=1
installonly_limit=3
clean_requirements_on_remove=true
repodir=/etc/yum.repos.d
cachedir=/var/cache/tdnf
```

Place `.repo` files in `/etc/yum.repos.d`, or in the directory selected by
`repodir`. The legacy cache path is intentional; see the
[migration notes](migrating-from-tdnf.md).

After installing to `./out`, for example:

```sh
./out/bin/rpmz list installed
./out/bin/rpmz install PACKAGE
./out/bin/rpmz remove PACKAGE
./out/bin/rpmz --help
```

`rpmz-config` manages repository configuration, and `rpmz-automatic` supports
scheduled operations using `/etc/rpmz/automatic.conf`.
