#!/usr/bin/env python3

import argparse
import csv
import json
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.colors import Normalize
import numpy as np


BLUE = "#0D66A6"
ORANGE = "#C55A11"
GRAY = "#666666"
GREEN = "#4C956C"
RED = "#C14953"
PURPLE = "#8E6C9F"
MAP_EXTENT = (-125.0, -66.0, 24.0, 50.0)
MAP_ASSET_DIR = Path(__file__).resolve().parent / "assets"


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


def geometry_rings(geometry):
    if geometry["type"] == "Polygon":
        yield from geometry["coordinates"]
    elif geometry["type"] == "MultiPolygon":
        for polygon in geometry["coordinates"]:
            yield from polygon
    else:
        raise ValueError(f"Unsupported basemap geometry: {geometry['type']}")


def add_us_context(axis):
    relief_path = MAP_ASSET_DIR / "conus_relief_50m.jpg"
    states_path = MAP_ASSET_DIR / "conus_states_2018.geojson"
    if not relief_path.is_file() or not states_path.is_file():
        raise FileNotFoundError(
            "The pinned CONUS map assets are missing from plots/assets/."
        )

    relief = plt.imread(relief_path)
    axis.imshow(
        relief, extent=MAP_EXTENT, origin="upper", interpolation="bilinear",
        alpha=0.72, zorder=0,
    )

    with states_path.open(encoding="utf-8") as handle:
        states = json.load(handle)
    boundaries = [
        ring
        for feature in states["features"]
        for ring in geometry_rings(feature["geometry"])
    ]
    axis.add_collection(LineCollection(
        boundaries, colors="#4F5B63", linewidths=0.38, alpha=0.62,
        zorder=2,
    ))

    west, east, south, north = MAP_EXTENT
    axis.set_xlim(west, east)
    axis.set_ylim(south, north)
    axis.set_aspect(1.0 / np.cos(np.deg2rad((south + north) / 2.0)))
    axis.set_xticks([-120, -110, -100, -90, -80, -70])
    axis.set_yticks([25, 30, 35, 40, 45, 50])
    axis.set_xticklabels([r"120$^{\circ}$W", r"110$^{\circ}$W", r"100$^{\circ}$W",
                          r"90$^{\circ}$W", r"80$^{\circ}$W", r"70$^{\circ}$W"])
    axis.set_yticklabels([r"25$^{\circ}$N", r"30$^{\circ}$N", r"35$^{\circ}$N",
                          r"40$^{\circ}$N", r"45$^{\circ}$N", r"50$^{\circ}$N"])
    axis.tick_params(axis="both", length=0, pad=3, labelsize=7,
                     colors="#4F5B63")
    axis.grid(color="#4F5B63", linewidth=0.35, alpha=0.20, zorder=1)
    for spine in axis.spines.values():
        spine.set_visible(False)


def shared_map_norm(rows, fields, scale=1.0):
    values = np.asarray([
        scale*float(row[field])
        for row in rows
        for field in fields
    ])
    if values.size == 0 or not np.all(np.isfinite(values)):
        raise ValueError("Map values must be finite and nonempty.")
    lower = min(0.0, float(np.quantile(values, 0.02)))
    upper = max(0.0, float(np.quantile(values, 0.98)))
    if upper <= lower:
        upper = lower + max(abs(lower), 1.0) * np.finfo(float).eps
    return Normalize(lower, upper, clip=True)


def map_figure(rows, field, label, output, *, norm=None, scale=1.0):
    segments, values = [], []
    for row in rows:
        coordinates = [row[key] for key in (
            "longitude_a", "latitude_a", "longitude_b", "latitude_b")]
        if any(value == "" for value in coordinates):
            continue
        lon_a, lat_a, lon_b, lat_b = map(float, coordinates)
        segments.append(((lon_a, lat_a), (lon_b, lat_b)))
        values.append(scale*float(row[field]))
    values = np.asarray(values)
    if norm is None:
        norm = shared_map_norm(rows, (field,), scale=scale)
    lower, upper = norm.vmin, norm.vmax
    widths = 0.35 + 2.4*np.sqrt(np.clip((values-lower)/(upper-lower), 0, 1))
    figure, axis = plt.subplots(figsize=(9.0, 5.2))
    add_us_context(axis)
    axis.add_collection(LineCollection(
        segments, colors="white", linewidths=widths + 1.0, alpha=0.72,
        zorder=3,
    ))
    collection = LineCollection(
        segments, array=values, cmap="turbo", norm=norm, linewidths=widths,
        alpha=0.96, zorder=4,
    )
    axis.add_collection(collection)
    nodes = sorted({point for segment in segments for point in segment})
    axis.scatter(
        [point[0] for point in nodes], [point[1] for point in nodes],
        s=4.0, color="#20272B", linewidths=0, alpha=0.78, zorder=5,
    )
    colorbar = figure.colorbar(collection, ax=axis, fraction=0.024, pad=0.018)
    colorbar.set_label(label, fontsize=8)
    colorbar.ax.tick_params(labelsize=7)
    colorbar.outline.set_linewidth(0.5)
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


def interval_plot(axis, rows, specifications, scale=1.0, zero_line=False):
    for position, (field, label, color) in enumerate(specifications):
        values = scale*np.asarray([float(row[field]) for row in rows])
        q05, q25, q50, q75, q95 = np.quantile(
            values, [0.05, 0.25, 0.50, 0.75, 0.95])
        axis.plot([q05, q95], [position, position], color=color,
                  linewidth=1.0, alpha=0.65)
        axis.plot([q25, q75], [position, position], color=color,
                  linewidth=5.0, alpha=0.78, solid_capstyle="round")
        axis.scatter([q50], [position], s=27, facecolor="white",
                     edgecolor=color, linewidth=1.4, zorder=3)
    axis.set_yticks(range(len(specifications)))
    axis.set_yticklabels([label for _, label, _ in specifications])
    axis.invert_yaxis()
    axis.tick_params(axis="both", labelsize=8, length=0)
    axis.spines[["top", "right", "left"]].set_visible(False)
    axis.spines["bottom"].set_color("#888888")
    axis.grid(axis="x", color="#DDDDDD", linewidth=0.5, alpha=0.55)
    if zero_line:
        axis.axvline(0.0, color="#777777", linewidth=0.75, zorder=0)


def decomposition_ladder_rows(rows, tolerance=1.0e-12):
    ladder_rows = []
    for row in rows:
        enriched = dict(row)
        traditional = float(row["hulten"])
        after_externalities = (
            traditional - float(row["primitive_externality"])
        )
        after_propagation = (
            after_externalities - float(row["primitive_propagation"])
        )
        after_congestion = (
            after_propagation - float(row["primitive_edge"])
        )
        extended = (
            after_congestion - float(row["primitive_pass_through"])
        )
        if abs(extended - float(row["primitive_F"])) > tolerance:
            raise ValueError(
                "The cumulative Hulten-to-extended ladder does not "
                "reconstruct primitive_F."
            )
        enriched.update({
            "ladder_traditional": traditional,
            "ladder_externalities": after_externalities,
            "ladder_propagation": after_propagation,
            "ladder_congestion": after_congestion,
            "ladder_extended": extended,
        })
        ladder_rows.append(enriched)
    return ladder_rows


def decomposition_figure(rows, output):
    ladder_rows = decomposition_ladder_rows(rows)
    figure, axes = plt.subplots(1, 3, figsize=(11.8, 4.5))
    interval_plot(
        axes[0], ladder_rows,
        [
            ("ladder_traditional", "Traditional approach", GRAY),
            ("ladder_externalities", "+ externalities", PURPLE),
            ("ladder_propagation", "+ equilibrium propagation", BLUE),
            ("ladder_congestion", "+ road congestion", GREEN),
            ("ladder_extended", "Extended approach (+ pass-through)", RED),
        ],
        scale=1.0e4,
    )
    axes[0].set_title("A. From traditional to extended", loc="left", fontsize=10)
    axes[0].set_xlabel(r"Welfare elasticity ($\times 10^{-4}$)", fontsize=8)

    interval_plot(
        axes[1], rows,
        [
            ("d_edge", "Road congestion", GREEN),
            ("d_mode", "Modal adjustment", PURPLE),
            ("d_route", "Route adjustment", ORANGE),
        ],
        zero_line=True,
    )
    axes[1].set_title("B. Alternative adjustment margins", loc="left", fontsize=10)
    axes[1].set_xlabel("Normalized multiplier difference", fontsize=8)

    component_rows = []
    for row in rows:
        enriched = dict(row)
        enriched["primitive_net_gap"] = (
            float(row["hulten"])-float(row["primitive_F"]))
        component_rows.append(enriched)
    interval_plot(
        axes[2], component_rows,
        [
            ("primitive_externality", "Externalities", BLUE),
            ("primitive_propagation", "Equilibrium propagation", ORANGE),
            ("primitive_edge", "Road congestion", GREEN),
            ("primitive_pass_through", "Primitive pass-through", RED),
            ("primitive_net_gap", "Net Hulten gap", GRAY),
        ],
        scale=1.0e4,
        zero_line=True,
    )
    axes[2].set_title("C. Additive Hulten gap", loc="left", fontsize=10)
    axes[2].set_xlabel(r"Signed elasticity component ($\times 10^{-4}$)", fontsize=8)

    figure.subplots_adjust(wspace=0.48)
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
    figure.supylabel(
        "Mean welfare effect of a 1% improvement (ppm)",
        x=0.015, fontsize=8,
    )
    axes[2, 1].text(
        0.0, 0.65, "Solid: mean welfare effect", color=BLUE,
        transform=axes[2, 1].transAxes, fontsize=8,
    )
    axes[2, 1].text(
        0.0, 0.48, "Dashed: rank correlation with baseline", color=ORANGE,
        transform=axes[2, 1].transAxes, fontsize=8,
    )
    axes[2, 1].axis("off")
    figure.subplots_adjust(left=0.10, wspace=0.42, hspace=0.48)
    save_figure(figure, output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    geometry = read_rows(args.input_dir / "paper_link_geometry.csv")
    physical = read_rows(args.input_dir / "decomposition_physical.csv")
    sensitivity = read_rows(args.input_dir / "paper_sensitivity.csv")
    traffic_norm = shared_map_norm(
        geometry, ("hulten",), scale=1.0e4,
    )
    map_norm = shared_map_norm(
        geometry, ("hulten", "primitive_F"), scale=1.0e4,
    )
    map_figure(
        geometry, "hulten", r"World-income traffic share ($\times 10^{-4}$)",
        args.output_dir / "rsue_traffic_map",
        norm=traffic_norm, scale=1.0e4,
    )
    map_figure(
        geometry, "hulten", r"Welfare elasticity ($\times 10^{-4}$)",
        args.output_dir / "rsue_hulten_map", norm=map_norm, scale=1.0e4,
    )
    map_figure(
        geometry, "primitive_F", r"Welfare elasticity ($\times 10^{-4}$)",
        args.output_dir / "rsue_ift_map", norm=map_norm, scale=1.0e4,
    )
    scatter_figure(physical, args.output_dir / "rsue_hulten_vs_ift")
    decomposition_figure(physical, args.output_dir / "rsue_decomposition")
    sensitivity_figure(sensitivity, args.output_dir / "rsue_sensitivity")


if __name__ == "__main__":
    main()
