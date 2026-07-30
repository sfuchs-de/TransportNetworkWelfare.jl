#!/usr/bin/env python3
"""Check release metadata and exclude local agent helper artifacts."""

from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import re
import subprocess
import sys
import tomllib


ROOT = pathlib.Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
REQUIRED_RELEASE_FILES = (
    "LICENSE",
    "README.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "CHANGELOG.md",
    "CITATION.cff",
    "PROVENANCE.md",
    "RELEASE_CHECKLIST.md",
    "THIRD_PARTY_NOTICES.md",
    "docs/practitioner-guide/README.md",
)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def cff_scalar(text: str, key: str) -> str:
    prefix = f"{key}:"
    for line in text.splitlines():
        if line.startswith(prefix):
            return line.removeprefix(prefix).strip().strip("\"'")
    raise ValueError(f"CITATION.cff is missing top-level {key}")


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def helper_artifact(path: str) -> bool:
    parts = pathlib.PurePosixPath(path).parts
    name = pathlib.PurePosixPath(path).name.lower()
    lower = path.lower()
    return (
        ".claude" in parts
        or ".codex" in parts
        or name in {"claude.md", "codex.md"}
        or name.startswith("claude-helper-")
        or name.startswith("codex-helper-")
        or "docs/audits/practitioner-guide-reasoning-" in lower
        or re.search(r"docs/audits/(figure-design|practitioner-guide-writing)-audit-", lower)
        is not None
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", help="Expected Git tag, for example v0.2.0")
    args = parser.parse_args()

    errors: list[str] = []
    for path in REQUIRED_RELEASE_FILES:
        if not (ROOT / path).is_file():
            errors.append(f"required release file is missing: {path}")

    project = tomllib.loads(read("Project.toml"))
    version = str(project.get("version", ""))
    if not SEMVER.fullmatch(version):
        errors.append(f"Project.toml version is not semantic: {version!r}")

    cff = read("CITATION.cff")
    try:
        cff_version = cff_scalar(cff, "version")
        release_date = cff_scalar(cff, "date-released")
    except ValueError as exc:
        errors.append(str(exc))
        cff_version = ""
        release_date = ""

    if cff_version != version:
        errors.append(f"CITATION.cff version {cff_version!r} != Project.toml {version!r}")
    try:
        dt.date.fromisoformat(release_date)
    except ValueError:
        errors.append(f"CITATION.cff date-released is not ISO format: {release_date!r}")

    preamble = read("docs/practitioner-guide/preamble.tex")
    guide_match = re.search(r"\\newcommand\{\\PackageVersion\}\{([^}]+)\}", preamble)
    guide_version = guide_match.group(1) if guide_match else ""
    if guide_version != version:
        errors.append(f"practitioner guide version {guide_version!r} != {version!r}")

    changelog_heading = f"## [{version}] - {release_date}"
    if changelog_heading not in read("CHANGELOG.md"):
        errors.append(f"CHANGELOG.md is missing {changelog_heading!r}")

    manifest = read("replication/rsue/environment/Manifest.toml")
    package_entry = re.search(
        r"\[\[deps\.TransportNetworkWelfare\]\](.*?)(?=\n\[\[deps\.|\Z)",
        manifest,
        re.DOTALL,
    )
    manifest_version = ""
    if package_entry:
        match = re.search(r'^version = "([^"]+)"$', package_entry.group(1), re.MULTILINE)
        manifest_version = match.group(1) if match else ""
    if manifest_version != version:
        errors.append(f"locked RSUE environment version {manifest_version!r} != {version!r}")

    if args.tag and args.tag != f"v{version}":
        errors.append(f"tag {args.tag!r} != expected 'v{version}'")

    tracked = set(tracked_files())
    missing_tracked = [path for path in REQUIRED_RELEASE_FILES if path not in tracked]
    if missing_tracked:
        errors.append(
            "required release files are not tracked:\n  "
            + "\n  ".join(missing_tracked)
        )

    forbidden = [path for path in tracked if helper_artifact(path)]
    if forbidden:
        errors.append("tracked agent helper artifacts:\n  " + "\n  ".join(forbidden))

    if "Manifest.toml" in tracked:
        errors.append(
            "the root Manifest.toml must remain untracked; "
            "only replication/rsue/environment/Manifest.toml is release source"
        )

    if errors:
        print("Release metadata check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Release metadata is consistent for v{version} ({release_date}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
