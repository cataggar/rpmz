#!/usr/bin/env python3

import argparse
import datetime
import gzip
import hashlib
import json
import lzma
import os
import platform
import shutil
import subprocess
import tarfile
import uuid
from pathlib import Path, PurePosixPath

from release_common import parse_semver


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / ".github/release-assets.json"
REQUIRED_DIRS = ("bin", "lib", "libexec", "etc")
REQUIRED_FILES = ("bin/rpmz", "COPYING", "README.md")
def validated_version(value):
    try:
        return parse_semver(value)[0]
    except ValueError as error:
        raise SystemExit(str(error)) from error


def emit_version(args):
    if not args.tag.startswith("v"):
        raise SystemExit(f"release tag must start with 'v': {args.tag!r}")
    try:
        version, prerelease = parse_semver(args.tag[1:])
    except ValueError as error:
        raise SystemExit(str(error)) from error
    print(f"version={version}")
    print(f"prerelease={'true' if prerelease else 'false'}")


def manifest():
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def generated_asset_names(version, platform_name=None):
    data = manifest()
    result = [
        data["source_archive"].format(version=version),
    ]
    for current in data["platforms"]:
        if platform_name is not None and current != platform_name:
            continue
        archive = data["binary_archive"].format(
            version=version, platform=current
        )
        result.extend([
            archive,
            archive + ".sha256",
            data["internal_sbom"].format(
                version=version, platform=current
            ),
        ])
    result.append(result[0] + ".sha256")
    return result


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_checksum(path):
    path.with_name(path.name + ".sha256").write_text(
        f"{sha256(path)}  {path.name}\n", encoding="ascii"
    )


def safe_relative(path):
    value = PurePosixPath(path)
    return (
        not value.is_absolute()
        and ".." not in value.parts
        and value.parts
        and value.parts[0] not in ("", ".")
    )


def add_tree(archive, source, arcname):
    def filter_member(member):
        member.uid = member.gid = 0
        member.uname = member.gname = ""
        return member

    archive.add(source, arcname=arcname, recursive=True, filter=filter_member)


def copy_install_tree(prefix, staging):
    staging.mkdir()
    for child in sorted(prefix.iterdir()):
        destination = staging / child.name
        if child.is_dir() and not child.is_symlink():
            shutil.copytree(child, destination, symlinks=True)
        else:
            shutil.copy2(child, destination, follow_symlinks=False)
    shutil.copy2(ROOT / "COPYING", staging / "COPYING")
    shutil.copy2(ROOT / "README.md", staging / "README.md")


def package_binary(args):
    prefix = Path(args.prefix).resolve()
    destination = Path(args.output).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    for required in REQUIRED_DIRS:
        if not (prefix / required).is_dir():
            raise SystemExit(f"missing installed directory: {required}")
    if not os.access(prefix / "bin/rpmz", os.X_OK):
        raise SystemExit("installed bin/rpmz is not executable")
    expected = f"rpmz: {args.version}"
    actual = subprocess.run(
        [prefix / "bin/rpmz", "--version"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if actual != expected:
        raise SystemExit(f"expected {expected!r}, got {actual!r}")

    data = manifest()
    archive_name = data["binary_archive"].format(
        version=args.version, platform=args.platform
    )
    package_name = archive_name.removesuffix(".tar.gz")
    archive_path = destination / archive_name
    staging = destination / f".{package_name}.staging"
    if staging.exists():
        shutil.rmtree(staging)
    try:
        copy_install_tree(prefix, staging)
        with archive_path.open("wb") as raw:
            with gzip.GzipFile(
                filename="", mode="wb", fileobj=raw, mtime=0
            ) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as archive:
                    add_tree(archive, staging, package_name)
        write_checksum(archive_path)
        write_sbom(
            staging,
            destination,
            args.version,
            args.platform,
            package_name,
        )
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def package_source(args):
    destination = Path(args.output).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    archive_name = manifest()["source_archive"].format(version=args.version)
    package_name = archive_name.removesuffix(".tar.xz")
    archive_path = destination / archive_name
    git_archive = subprocess.run(
        [
            "git", "archive", "--format=tar",
            f"--prefix={package_name}/", "HEAD",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    with lzma.open(archive_path, "wb", preset=9) as output:
        output.write(git_archive.stdout)
    write_checksum(archive_path)


def write_sbom(
    staging, destination, version, platform_name, package_name
):
    data = manifest()
    sbom_name = data["internal_sbom"].format(
        version=version, platform=platform_name
    )
    files = []
    relationships = [{
        "spdxElementId": "SPDXRef-DOCUMENT",
        "relationshipType": "DESCRIBES",
        "relatedSpdxElement": "SPDXRef-Package-rpmz",
    }]
    index = 0
    for path in sorted(staging.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        index += 1
        spdx_id = f"SPDXRef-File-{index}"
        files.append({
            "fileName": (
                "./" + package_name + "/"
                + path.relative_to(staging).as_posix()
            ),
            "SPDXID": spdx_id,
            "checksums": [{
                "algorithm": "SHA256",
                "checksumValue": sha256(path),
            }],
        })
        relationships.append({
            "spdxElementId": "SPDXRef-Package-rpmz",
            "relationshipType": "CONTAINS",
            "relatedSpdxElement": spdx_id,
        })
    document = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"rpmz-{version}-{platform_name}",
        "documentNamespace": (
            "https://github.com/cataggar/rpmz/sbom/"
            f"{version}/{platform_name}/{uuid.uuid4()}"
        ),
        "creationInfo": {
            "created": datetime.datetime.now(
                datetime.timezone.utc
            ).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "creators": ["Tool: rpmz-release.py"],
        },
        "packages": [{
            "name": "rpmz",
            "SPDXID": "SPDXRef-Package-rpmz",
            "versionInfo": version,
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": True,
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION",
            "copyrightText": "NOASSERTION",
        }],
        "files": files,
        "relationships": relationships,
    }
    (destination / sbom_name).write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def archive_members(path):
    with tarfile.open(path, "r:*") as archive:
        return archive.getmembers()


def verify_archive(path, version, platform_name):
    package_name = f"rpmz-{version}-{platform_name}"
    members = archive_members(path)
    member_names = {member.name.rstrip("/") for member in members}
    for member in members:
        if not safe_relative(member.name):
            raise SystemExit(f"{path.name}: unsafe member {member.name!r}")
        if member.issym() or member.islnk():
            parent = PurePosixPath(member.name).parent
            target = parent / member.linkname
            if not safe_relative(target.as_posix()):
                raise SystemExit(
                    f"{path.name}: unsafe link {member.name!r}"
                )
    for relative in REQUIRED_FILES:
        expected = f"{package_name}/{relative}"
        if expected not in member_names:
            raise SystemExit(f"{path.name}: missing {expected}")
    rpmz_member = next(
        member for member in members
        if member.name.rstrip("/") == f"{package_name}/bin/rpmz"
    )
    if rpmz_member.mode & 0o111 == 0:
        raise SystemExit(f"{path.name}: bin/rpmz is not executable")
    for directory in REQUIRED_DIRS:
        prefix = f"{package_name}/{directory}/"
        if not any(name.startswith(prefix) for name in member_names):
            raise SystemExit(f"{path.name}: empty/missing {directory}/")
    legacy = "td" + "nf"
    offenders = [
        name for name in member_names
        if legacy in PurePosixPath(name).name.lower()
    ]
    if offenders:
        raise SystemExit(
            f"{path.name}: legacy installed artifact: {offenders[0]}"
        )


def verify_checksum(path):
    sidecar = path.with_name(path.name + ".sha256")
    fields = sidecar.read_text(encoding="ascii").strip().split()
    if fields != [sha256(path), path.name]:
        raise SystemExit(f"{sidecar.name}: invalid checksum")


def verify_assets(args):
    directory = Path(args.directory).resolve()
    expected = set(generated_asset_names(args.version, args.platform))
    actual = {
        path.name for path in directory.iterdir()
        if path.is_file() and path.name.startswith(f"rpmz-{args.version}")
    }
    if actual != expected:
        raise SystemExit(
            "generated release files differ:\n"
            f"  expected: {sorted(expected)}\n  actual: {sorted(actual)}"
        )
    platforms = (
        [args.platform] if args.platform else manifest()["platforms"]
    )
    for current in platforms:
        archive = directory / manifest()["binary_archive"].format(
            version=args.version, platform=current
        )
        verify_archive(archive, args.version, current)
        verify_checksum(archive)
        sbom_path = directory / manifest()["internal_sbom"].format(
            version=args.version, platform=current
        )
        sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
        if (
            sbom.get("spdxVersion") != "SPDX-2.3"
            or sbom.get("SPDXID") != "SPDXRef-DOCUMENT"
            or not sbom.get("packages")
            or not sbom.get("files")
        ):
            raise SystemExit(f"{sbom_path.name}: invalid SPDX document")
        archive_files = {
            member.name for member in archive_members(archive)
            if member.isfile()
        }
        sbom_checksums = {}
        for file_entry in sbom["files"]:
            file_name = file_entry.get("fileName", "")
            if not file_name.startswith("./"):
                raise SystemExit(
                    f"{sbom_path.name}: invalid SPDX path {file_name!r}"
                )
            checksums = file_entry.get("checksums", [])
            if len(checksums) != 1 or checksums[0].get(
                "algorithm"
            ) != "SHA256":
                raise SystemExit(
                    f"{sbom_path.name}: missing file SHA256"
                )
            sbom_checksums[file_name.removeprefix("./")] = (
                checksums[0].get("checksumValue")
            )
        sbom_files = set(sbom_checksums)
        if archive_files != sbom_files:
            raise SystemExit(
                f"{sbom_path.name}: archive/SBOM file sets differ:\n"
                f"  archive only: {sorted(archive_files - sbom_files)}\n"
                f"  SBOM only: {sorted(sbom_files - archive_files)}"
            )
        with tarfile.open(archive, "r:*") as tar:
            for member in tar.getmembers():
                if not member.isfile():
                    continue
                stream = tar.extractfile(member)
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
                if digest.hexdigest() != sbom_checksums[member.name]:
                    raise SystemExit(
                        f"{sbom_path.name}: checksum mismatch for "
                        f"{member.name}"
                    )
    source = directory / manifest()["source_archive"].format(
        version=args.version
    )
    verify_checksum(source)
    for member in archive_members(source):
        if not safe_relative(member.name):
            raise SystemExit(
                f"{source.name}: unsafe member {member.name!r}"
            )


def host_platform():
    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        return "linux-x64"
    if machine in ("aarch64", "arm64"):
        return "linux-arm64"
    raise SystemExit(f"unsupported release host architecture: {machine}")


def dry_run(args):
    output = Path(args.output).resolve()
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    current = host_platform()
    package_binary(argparse.Namespace(
        prefix=args.prefix,
        output=output,
        version=args.version,
        platform=current,
    ))
    package_source(argparse.Namespace(
        output=output,
        version=args.version,
    ))
    verify_assets(argparse.Namespace(
        directory=output,
        version=args.version,
        platform=current,
    ))
    print(
        "release dry-run passed (generated files): "
        f"{', '.join(generated_asset_names(args.version, current))}"
    )


def parser():
    result = argparse.ArgumentParser()
    subparsers = result.add_subparsers(dest="command", required=True)
    version = subparsers.add_parser("version")
    version.add_argument("--tag", required=True)
    version.set_defaults(function=emit_version)
    binary = subparsers.add_parser("binary")
    binary.add_argument("--prefix", required=True)
    binary.add_argument("--output", required=True)
    binary.add_argument("--version", required=True)
    binary.add_argument("--platform", choices=manifest()["platforms"],
                        required=True)
    binary.set_defaults(function=package_binary)
    source = subparsers.add_parser("source")
    source.add_argument("--output", required=True)
    source.add_argument("--version", required=True)
    source.set_defaults(function=package_source)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--directory", required=True)
    verify.add_argument("--version", required=True)
    verify.add_argument("--platform", choices=manifest()["platforms"])
    verify.set_defaults(function=verify_assets)
    dry = subparsers.add_parser("dry-run")
    dry.add_argument("--prefix", required=True)
    dry.add_argument("--output", required=True)
    dry.add_argument("--version", required=True)
    dry.set_defaults(function=dry_run)
    listing = subparsers.add_parser("names")
    listing.add_argument("--version", required=True)
    listing.set_defaults(
        function=lambda args: print(
            "\n".join(generated_asset_names(args.version))
        )
    )
    return result


def main():
    args = parser().parse_args()
    if hasattr(args, "version"):
        args.version = validated_version(args.version)
    args.function(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
