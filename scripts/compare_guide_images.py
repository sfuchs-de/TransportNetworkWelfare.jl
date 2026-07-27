#!/usr/bin/env python3
"""Compare rendered guide figures while tolerating platform antialiasing."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def load_rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert("RGBA"), dtype=np.int16)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("generated", type=Path)
    parser.add_argument("committed", type=Path)
    parser.add_argument("--maximum-mean-error", type=float, default=1.0)
    parser.add_argument("--material-threshold", type=int, default=16)
    parser.add_argument("--maximum-material-share", type=float, default=0.01)
    args = parser.parse_args()

    generated = load_rgba(args.generated)
    committed = load_rgba(args.committed)
    if generated.shape != committed.shape:
        raise SystemExit(
            f"image dimensions differ: {generated.shape} != {committed.shape}"
        )

    difference = np.abs(generated - committed)
    mean_error = float(difference.mean())
    material_share = float(
        np.any(difference > args.material_threshold, axis=2).mean()
    )
    if (
        mean_error > args.maximum_mean_error
        or material_share > args.maximum_material_share
    ):
        raise SystemExit(
            "rendered guide figure differs: "
            f"mean channel error={mean_error:.6f}, "
            f"share above {args.material_threshold}={material_share:.6f}"
        )

    print(
        "rendered guide figure accepted: "
        f"mean channel error={mean_error:.6f}, "
        f"share above {args.material_threshold}={material_share:.6f}"
    )


if __name__ == "__main__":
    main()
