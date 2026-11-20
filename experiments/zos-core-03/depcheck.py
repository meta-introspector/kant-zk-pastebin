"""Compare installed crate sources and archives against the locked packages."""
import hashlib
import os
from pathlib import Path
import tarfile
import tomllib

registry = Path(os.environ.get("CARGO_HOME", Path.home() / ".cargo")) / "registry"
lock = tomllib.loads(Path("Cargo.lock").read_text())
for package in lock["package"]:
    if "checksum" not in package:
        continue
    stem = f'{package["name"]}-{package["version"]}'
    archives = list((registry / "cache").glob(f"*/{stem}.crate"))
    assert len(archives) == 1, (stem, archives)
    archive = archives[0]
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == package["checksum"], stem
    source = registry / "src" / archive.parent.name / stem
    # Some locked packages are platform-conditional and may never be unpacked.
    if source.exists():
        expected = set()
        with tarfile.open(archive, "r:gz") as package_tar:
            for member in package_tar:
                if member.isdir():
                    continue
                assert member.isfile(), member.name
                relative = Path(member.name).relative_to(stem)
                assert ".." not in relative.parts
                path = source / relative
                assert not path.is_symlink() and path.is_file(), path
                assert path.read_bytes() == package_tar.extractfile(member).read(), path
                expected.add(relative)
        present = {path.relative_to(source) for path in source.rglob("*") if path.is_file()}
        assert present - {Path(".cargo-ok")} == expected, stem
    print("PASS locked crate", stem, package["checksum"])
