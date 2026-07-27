#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

try:
    from plots.figure_style import (
        BLUE, INK, MUTED, correlations, save_figure,
        shared_identity_limits, style_axis,
    )
except ModuleNotFoundError:
    from figure_style import (
        BLUE, INK, MUTED, correlations, save_figure,
        shared_identity_limits, style_axis,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--physical", action="store_true")
    args = parser.parse_args()

    with args.input.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    hulten = np.array([float(row["hulten"]) for row in rows])
    welfare = np.array([float(row["primitive_F"]) for row in rows])

    figure, axis = plt.subplots(figsize=(4.8, 4.4))
    axis.scatter(
        hulten, welfare, s=19, alpha=0.46, color=BLUE,
        edgecolors="none", zorder=2,
    )
    limits = shared_identity_limits(hulten, welfare)
    axis.plot(
        limits, limits, color=MUTED, linewidth=0.8,
        linestyle=(0, (3, 2)), zorder=1,
    )
    pearson, spearman = correlations(hulten, welfare)
    pearson_text = f"{pearson:.3f}" if np.isfinite(pearson) else "n/a"
    spearman_text = f"{spearman:.3f}" if np.isfinite(spearman) else "n/a"
    axis.text(
        0.03, 0.97,
        f"Pearson {pearson_text}\nRank {spearman_text}",
        transform=axis.transAxes, ha="left", va="top", fontsize=7.5,
        color=INK,
    )
    axis.set_xlim(*limits)
    axis.set_ylim(*limits)
    axis.set_xlabel("Traditional approach")
    axis.set_ylabel("Extended approach")
    style_axis(axis, grid_axis="both")
    figure.tight_layout()
    save_figure(figure, args.output)


if __name__ == "__main__":
    main()
