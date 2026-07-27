#!/usr/bin/env python3
"""Render the Westeros geographic welfare map, scatter, and ranked table."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parents[1]))

from plots import figure_style, westeros_example  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--generated",
        type=Path,
        default=ROOT / "generated",
        help="prepared Westeros directory containing data, results, and sources",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "generated" / "figures",
        help="destination for PDF and transparent PNG figures",
    )
    parser.add_argument(
        "--tables",
        type=Path,
        default=ROOT / "generated" / "tables",
        help="destination for the ranked-link table and CSV",
    )
    arguments = parser.parse_args()
    outputs = westeros_example.build_assets(
        arguments.generated,
        arguments.output,
        arguments.tables,
    )
    for path in outputs:
        print(path)


if __name__ == "__main__":
    main()
