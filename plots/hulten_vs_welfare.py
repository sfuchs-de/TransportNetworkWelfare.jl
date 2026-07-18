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
    parser.add_argument("--physical", action="store_true")
    args = parser.parse_args()

    with args.input.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    hulten = np.array([float(row["hulten"]) for row in rows])
    welfare = np.array([float(row["primitive_F"]) for row in rows])

    figure, axis = plt.subplots(figsize=(4.8, 4.4))
    axis.scatter(hulten, welfare, s=20, alpha=0.42, color="#0D66A6", edgecolors="none")
    lower = min(hulten.min(), welfare.min())
    upper = max(hulten.max(), welfare.max())
    axis.plot([lower, upper], [lower, upper], color="#333333", linewidth=0.9, linestyle="--")
    axis.set_xlabel("Traffic-share benchmark")
    axis.set_ylabel("Full-model welfare elasticity")
    axis.spines[["top", "right"]].set_visible(False)
    axis.grid(False)
    figure.tight_layout()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(args.output, dpi=220, transparent=True)
    plt.close(figure)


if __name__ == "__main__":
    main()
