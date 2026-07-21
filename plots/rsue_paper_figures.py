#!/usr/bin/env python3

import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.colors import Normalize
import numpy as np


BLUE = "#0D66A6"
ORANGE = "#C55A11"
GRAY = "#666666"


def read_rows(path: Path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def save_figure(figure, base: Path):
    base.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(
        base.with_suffix(".pdf"), bbox_inches="tight", transparent=True,
        metadata={"CreationDate": None, "ModDate": None},
    )
    figure.savefig(
        base.with_suffix(".png"), dpi=300, bbox_inches="tight", transparent=True,
        metadata={"Software": "TransportNetworkWelfare.jl"},
    )
    plt.close(figure)


def map_figure(rows, field, label, output):
    segments, values = [], []
    for row in rows:
        coordinates = [row[key] for key in (
            "longitude_a", "latitude_a", "longitude_b", "latitude_b")]
        if any(value == "" for value in coordinates):
            continue
        lon_a, lat_a, lon_b, lat_b = map(float, coordinates)
        segments.append(((lon_a, lat_a), (lon_b, lat_b)))
        values.append(float(row[field]))
    values = np.asarray(values)
    lower, upper = np.quantile(values, [0.02, 0.98])
    norm = Normalize(lower, upper, clip=True)
    widths = 0.35 + 2.4*np.sqrt(np.clip((values-lower)/(upper-lower), 0, 1))
    figure, axis = plt.subplots(figsize=(8.0, 4.4))
    collection = LineCollection(
        segments, array=values, cmap="viridis", norm=norm, linewidths=widths,
        alpha=0.88,
    )
    axis.add_collection(collection)
    axis.autoscale()
    axis.set_aspect("equal", adjustable="box")
    axis.set_axis_off()
    colorbar = figure.colorbar(collection, ax=axis, fraction=0.028, pad=0.015)
    colorbar.set_label(label, fontsize=8)
    colorbar.ax.tick_params(labelsize=7)
    save_figure(figure, output)


def scatter_figure(rows, output):
    hulten = np.asarray([float(row["hulten"]) for row in rows])
    welfare = np.asarray([float(row["primitive_F"]) for row in rows])
    scale = 1.0e4
    x, y = scale*hulten, scale*welfare
    lower = min(x.min(), y.min())
    upper = max(x.max(), y.max())
    padding = 0.04*(upper-lower)
    figure, axis = plt.subplots(figsize=(4.8, 4.4))
    axis.scatter(x, y, s=18, alpha=0.38, color=BLUE, edgecolors="none")
    axis.plot(
        [lower-padding, upper+padding], [lower-padding, upper+padding],
        color="#333333", linewidth=0.9, linestyle="--",
    )
    axis.set_xlim(lower-padding, upper+padding)
    axis.set_ylim(lower-padding, upper+padding)
    axis.set_xlabel(r"Traditional statistic ($\times 10^{-4}$)")
    axis.set_ylabel(r"Extended statistic ($\times 10^{-4}$)")
    axis.spines[["top", "right"]].set_visible(False)
    axis.grid(color="#DDDDDD", linewidth=0.5, alpha=0.6)
    save_figure(figure, output)


def sensitivity_figure(rows, output):
    parameters = [
        "alpha", "beta", "net_dispersion", "eta", "lambda_road",
        "common_congestion", "lambda_terminal",
    ]
    labels = {
        "alpha": r"Productivity externality $\alpha$",
        "beta": r"Amenity externality $\beta$",
        "net_dispersion": "Net dispersion",
        "eta": r"Mode substitution $\eta$",
        "lambda_road": "Road congestion",
        "common_congestion": "Common congestion scale",
        "lambda_terminal": "Terminal congestion extension",
    }
    grouped = {parameter: [] for parameter in parameters}
    for row in rows:
        grouped[row["parameter"]].append(row)
    figure, axes = plt.subplots(3, 3, figsize=(9.2, 7.2))
    for axis, parameter in zip(axes.flat, parameters):
        data = sorted(grouped[parameter], key=lambda row: float(row["value"]))
        x = np.asarray([float(row["value"]) for row in data])
        mean_gain = 1.0e4*np.asarray(
            [float(row["mean_physical_gain_pct"]) for row in data])
        rank = np.asarray([float(row["spearman_vs_baseline"]) for row in data])
        axis.plot(x, mean_gain, color=BLUE, linewidth=1.4, marker="o", markersize=3.5)
        axis.set_title(labels[parameter], fontsize=9)
        axis.tick_params(labelsize=7)
        axis.spines[["top", "right"]].set_visible(False)
        axis.grid(axis="y", color="#DDDDDD", linewidth=0.5, alpha=0.6)
        rank_axis = axis.twinx()
        rank_axis.plot(x, rank, color=ORANGE, linewidth=1.0, linestyle="--")
        rank_axis.set_ylim(min(0.8, rank.min()-0.01), 1.005)
        rank_axis.set_yticks([0.8, 0.9, 1.0])
        rank_axis.tick_params(labelsize=7, colors=GRAY)
        rank_axis.spines["top"].set_visible(False)
        rank_axis.spines["right"].set_color("#BBBBBB")
    for axis in axes.flat[len(parameters):]:
        axis.axis("off")
    axes[1, 0].set_ylabel(
        r"Mean gain from a 1% improvement ($\%\times 10^{4}$)", fontsize=8)
    axes[2, 1].text(
        0.0, 0.65, "Solid: mean model-implied gain", color=BLUE,
        transform=axes[2, 1].transAxes, fontsize=8,
    )
    axes[2, 1].text(
        0.0, 0.48, "Dashed: rank correlation with baseline", color=ORANGE,
        transform=axes[2, 1].transAxes, fontsize=8,
    )
    axes[2, 1].axis("off")
    figure.subplots_adjust(wspace=0.42, hspace=0.48)
    save_figure(figure, output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    geometry = read_rows(args.input_dir / "paper_link_geometry.csv")
    physical = read_rows(args.input_dir / "decomposition_physical.csv")
    sensitivity = read_rows(args.input_dir / "paper_sensitivity.csv")
    map_figure(
        geometry, "hulten", "Traffic share",
        args.output_dir / "rsue_hulten_map",
    )
    map_figure(
        geometry, "primitive_F", "Welfare elasticity",
        args.output_dir / "rsue_ift_map",
    )
    scatter_figure(physical, args.output_dir / "rsue_hulten_vs_ift")
    sensitivity_figure(sensitivity, args.output_dir / "rsue_sensitivity")


if __name__ == "__main__":
    main()
