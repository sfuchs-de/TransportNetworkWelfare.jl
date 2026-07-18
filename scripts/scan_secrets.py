#!/usr/bin/env python3
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "Overleaf token": re.compile(r"\bolp_[A-Za-z0-9]{20,}\b"),
    "GitHub token": re.compile(r"\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}\b"),
    "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
}


def tracked_files():
    try:
        output = subprocess.check_output(
            ["git", "-C", str(ROOT), "ls-files"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        files = [ROOT / line for line in output.splitlines()]
        if files:
            return files
        return [path for path in ROOT.rglob("*") if path.is_file() and ".git" not in path.parts]
    except subprocess.CalledProcessError:
        return [path for path in ROOT.rglob("*") if path.is_file() and ".git" not in path.parts]


def main():
    failures = []
    for path in tracked_files():
        if path.suffix.lower() in {".png", ".pdf", ".zip", ".pyc"}:
            continue
        try:
            content = path.read_text(errors="ignore")
        except OSError:
            continue
        for label, pattern in PATTERNS.items():
            if pattern.search(content):
                failures.append(f"{label}: {path.relative_to(ROOT)}")
    forbidden = [path for path in tracked_files() if path.name in {".env", "credentials.json"}]
    failures.extend(f"forbidden file: {path.relative_to(ROOT)}" for path in forbidden)
    if failures:
        raise SystemExit("Potential secrets found:\n" + "\n".join(failures))
    print("secret scan passed")


if __name__ == "__main__":
    main()
