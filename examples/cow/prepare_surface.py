#!/usr/bin/env python3
"""Download and verify the optional third-party cow PLY surface."""

import argparse
import hashlib
from pathlib import Path
import tempfile
import tomllib
import urllib.request


ROOT = Path(__file__).resolve().parent
SOURCE_MANIFEST = ROOT / "sources.toml"
DEFAULT_OUTPUT = ROOT / "assets" / "cow.ply"


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def prepare(output=DEFAULT_OUTPUT, *, offline=False, manifest=SOURCE_MANIFEST):
    specification = tomllib.loads(Path(manifest).read_text(encoding="utf-8"))["mesh"]
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.is_file():
        if offline:
            raise FileNotFoundError(f"missing cached cow mesh: {output}")
        with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as temporary:
            temporary_path = Path(temporary.name)
        try:
            urllib.request.urlretrieve(specification["url"], temporary_path)
            actual = file_sha256(temporary_path)
            if actual != specification["sha256"]:
                raise ValueError(
                    f"downloaded cow mesh has SHA-256 {actual}; "
                    f"expected {specification['sha256']}")
            temporary_path.replace(output)
        finally:
            temporary_path.unlink(missing_ok=True)
    actual = file_sha256(output)
    if actual != specification["sha256"]:
        raise ValueError(
            f"cached cow mesh has SHA-256 {actual}; "
            f"expected {specification['sha256']}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    print(prepare(args.output, offline=args.offline))


if __name__ == "__main__":
    main()
