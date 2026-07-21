#!/usr/bin/env python3
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "Overleaf token": re.compile(r"\bolp_[A-Za-z0-9_-]{20,}\b"),
    "GitHub token": re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b"),
    "GitHub fine-grained token": re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    "Google OAuth client secret": re.compile(r"\bGOCSPX-[0-9A-Za-z_-]{20,}\b"),
    "Census API key assignment": re.compile(
        r"(?im)^\s*(?:export\s+)?CENSUS_API_KEY\s*=\s*(?!\.\.\.|<)[\"']?[0-9A-Za-z_-]{16,}"
    ),
    "Census API key in URL": re.compile(
        r"https?://api\.census\.gov/[^\s\"']*[?&]key=[0-9A-Za-z_-]{16,}"
    ),
    "Dropbox access token": re.compile(r"\bsl\.[0-9A-Za-z_-]{20,}\b"),
    "AWS access key": re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "authorization header": re.compile(r"(?im)^\s*authorization\s*:\s*(?:bearer|basic)\s+\S+"),
    "credentialed URL": re.compile(r"https?://[^\s/@:]+:[^\s/@]+@"),
}


def tracked_files():
    try:
        output = subprocess.check_output(
            [
                "git",
                "-C",
                str(ROOT),
                "ls-files",
                "-z",
                "--cached",
                "--others",
                "--exclude-standard",
            ],
            stderr=subprocess.DEVNULL,
        )
        files = [ROOT / line for line in output.decode().split("\0") if line]
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
    forbidden_suffixes = {".gz", ".key", ".p12", ".pem", ".tar", ".zip"}
    forbidden = [
        path
        for path in tracked_files()
        if path.name == ".env"
        or path.name.startswith("credentials.")
        or path.suffix.lower() in forbidden_suffixes
    ]
    failures.extend(f"forbidden file: {path.relative_to(ROOT)}" for path in forbidden)
    if failures:
        raise SystemExit("Potential secrets found:\n" + "\n".join(failures))
    print("secret scan passed")


if __name__ == "__main__":
    main()
