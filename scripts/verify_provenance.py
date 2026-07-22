#!/usr/bin/env python3

import hashlib
import sys
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "provenance.toml"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    with MANIFEST.open("rb") as handle:
        manifest = tomllib.load(handle)
    failures = []
    for entry in manifest.get("kernel", []):
        path = ROOT / entry["path"]
        if not path.is_file():
            failures.append(f"missing: {entry['path']}")
            continue
        actual = sha256(path)
        if actual != entry["current_sha256"]:
            failures.append(
                f"hash mismatch for {entry['path']}: expected "
                f"{entry['current_sha256']}, got {actual}")
        if not entry.get("relationship"):
            failures.append(f"missing relationship for {entry['path']}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"verified {len(manifest.get('kernel', []))} provenance entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
