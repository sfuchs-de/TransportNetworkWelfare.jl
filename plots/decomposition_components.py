#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


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
        ("primitive_edge", "Edge congestion"),
        ("primitive_terminal", "Terminal congestion"),
        ("primitive_pass_through", "Pass-through"),
    ]
    values = np.array([np.mean([float(row[field]) for row in rows]) for field, _ in fields])
    colors = ["#4C78A8" if value >= 0 else "#E45756" for value in values]

    figure, axis = plt.subplots(figsize=(6.2, 3.4))
    axis.barh([label for _, label in fields], values, color=colors, height=0.62)
    axis.axvline(0, color="#333333", linewidth=0.8)
    axis.set_xlabel("Mean signed welfare-gap component")
    axis.spines[["top", "right", "left"]].set_visible(False)
    axis.tick_params(axis="y", length=0)
    figure.tight_layout()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(args.output, dpi=220, transparent=True)
    plt.close(figure)


if __name__ == "__main__":
    main()
