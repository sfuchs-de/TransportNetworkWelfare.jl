#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

try:
    from plots.figure_style import (
        BLUE, INK, MUTED, ORANGE, save_figure, style_axis,
    )
except ModuleNotFoundError:
    from figure_style import (
        BLUE, INK, MUTED, ORANGE, save_figure, style_axis,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    with args.input.open(newline="") as handle:
        rows = list(csv.DictReader(handle))

    fields = [
        ("primitive_externality", "Externalities"),
        ("primitive_propagation", "GE propagation"),
        ("primitive_edge", "Road congestion"),
        ("primitive_terminal", "Terminal congestion"),
        ("primitive_pass_through", "Pass-through"),
    ]
    values = np.array([np.mean([float(row[field]) for row in rows]) for field, _ in fields])
    labels = [label for _, label in fields]
    positions = np.arange(len(fields))
    colors = [BLUE if value >= 0 else ORANGE for value in values]

    figure, axis = plt.subplots(figsize=(6.2, 3.4))
    for position, value, color in zip(positions, values, colors):
        axis.plot(
            [0.0, value], [position, position], color=color,
            linewidth=1.35, zorder=2,
        )
        axis.scatter(
            [value], [position], s=28, color=color, edgecolor="white",
            linewidth=0.45, zorder=3,
        )
        axis.annotate(
            f"{value:.3g}", (value, position),
            xytext=(5, 0), textcoords="offset points",
            ha="left", va="center",
            fontsize=7, color=INK,
        )
    axis.set_yticks(positions, labels=labels)
    axis.invert_yaxis()
    axis.set_xlabel("Mean signed welfare-gap component")
    style_axis(axis, grid_axis="x", zero_line=True)
    axis.spines["left"].set_visible(False)
    axis.tick_params(axis="y", length=0)
    figure.tight_layout()
    save_figure(figure, args.output)


if __name__ == "__main__":
    main()
