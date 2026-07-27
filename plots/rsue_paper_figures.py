#!/usr/bin/env python3

import argparse
import csv
import json
from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
import numpy as np

try:
    from plots.figure_style import (
        BLUE, INK, LIGHT, MUTED, ORANGE, PURPLE, RED, TEAL,
        add_panel_label, correlations, finite_range, save_figure_pair,
        shared_identity_limits, style_axis, welfare_norm,
    )
except ModuleNotFoundError:
    from figure_style import (
        BLUE, INK, LIGHT, MUTED, ORANGE, PURPLE, RED, TEAL,
        add_panel_label, correlations, finite_range, save_figure_pair,
        shared_identity_limits, style_axis, welfare_norm,
    )

MAP_EXTENT = (-125.0, -66.0, 24.0, 50.0)
MAP_ASSET_DIR = Path(__file__).resolve().parent / "assets"


def read_rows(path: Path):
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def plot_link_label(row):
    """Wrap complete CBSA names without altering their official spelling."""
    first = row.get("cbsa_name_a", "").strip()
    second = row.get("cbsa_name_b", "").strip()
    if first and second:
        return f"{first}\n{second}"
    if first or second:
        return f"Approach to {first or second}"
    return row.get("verified_label") or row["physical_link_id"]


def save_figure(figure, base: Path):
    return save_figure_pair(figure, base.parent, base.name)


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
        boundaries, colors=MUTED, linewidths=0.38, alpha=0.62,
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
                     colors=MUTED)
    axis.grid(color=MUTED, linewidth=0.35, alpha=0.20, zorder=1)
    for spine in axis.spines.values():
        spine.set_visible(False)


def map_figure(rows, field, label, output, *, norm=None, cmap=None):
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
    if norm is None or cmap is None:
        norm, cmap = welfare_norm(values, robust=True, include_zero=True)
    lower, upper = norm.vmin, norm.vmax
    widths = 0.35 + 2.4*np.sqrt(np.clip((values-lower)/(upper-lower), 0, 1))
    figure, axis = plt.subplots(figsize=(9.0, 5.2))
    add_us_context(axis)
    axis.add_collection(LineCollection(
        segments, colors="white", linewidths=widths + 1.0, alpha=0.72,
        zorder=3,
    ))
    collection = LineCollection(
        segments, array=values, cmap=cmap, norm=norm, linewidths=widths,
        alpha=0.96, zorder=4,
    )
    axis.add_collection(collection)
    nodes = sorted({point for segment in segments for point in segment})
    axis.scatter(
        [point[0] for point in nodes], [point[1] for point in nodes],
        s=4.0, color=INK, linewidths=0, alpha=0.78, zorder=5,
    )
    colorbar = figure.colorbar(collection, ax=axis, fraction=0.024, pad=0.018)
    colorbar.set_label(label, fontsize=8)
    colorbar.ax.tick_params(labelsize=7)
    colorbar.outline.set_linewidth(0.5)
    save_figure(figure, output)


def scatter_figure(rows, output, labels=None):
    hulten = np.asarray([float(row["hulten"]) for row in rows])
    welfare = np.asarray([float(row["primitive_F"]) for row in rows])
    scale = 1.0e4
    x, y = scale*hulten, scale*welfare
    limits = shared_identity_limits(x, y)
    figure, axis = plt.subplots(figsize=(4.8, 4.4))
    axis.scatter(x, y, s=18, alpha=0.38, color=BLUE, edgecolors="none")
    axis.plot(
        limits, limits, color=MUTED, linewidth=0.8, linestyle=(0, (3, 2)),
    )
    pearson, spearman = correlations(x, y)
    axis.text(
        0.03, 0.97,
        f"Pearson {pearson:.3f}\nRank {spearman:.3f}",
        transform=axis.transAxes, ha="left", va="top", fontsize=7.5,
    )
    label_lookup = labels or {}
    top = np.argsort(y)[-3:]
    placements = (
        ((7, 6), "left"),
        ((-8, 27), "right"),
        ((8, 9), "left"),
    )
    for rank, index in enumerate(top):
        row = rows[index]
        label = label_lookup.get(
            row["physical_link_id"], row["physical_link_id"])
        offset, alignment = placements[rank]
        axis.annotate(
            label, (x[index], y[index]),
            xytext=offset, textcoords="offset points",
            ha=alignment, va="bottom", fontsize=5.5, color=INK,
            linespacing=1.05,
            arrowprops={"arrowstyle": "-", "color": MUTED, "lw": 0.45},
            bbox={"facecolor": "white", "edgecolor": "none",
                  "alpha": 0.82, "pad": 0.7},
        )
    axis.set_xlim(*limits)
    axis.set_ylim(*limits)
    axis.set_xlabel(r"Traditional approach ($\times 10^{-4}$)")
    axis.set_ylabel(r"Extended approach ($\times 10^{-4}$)")
    style_axis(axis, grid_axis="both")
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
    style_axis(axis, grid_axis="x", zero_line=zero_line)
    axis.spines["left"].set_visible(False)


def decomposition_figure(rows, output):
    figure, axes = plt.subplots(1, 3, figsize=(11.8, 4.3))
    interval_plot(
        axes[0], rows,
        [
            ("hulten", "Traditional approach", MUTED),
            ("realized_NC", "No congestion", TEAL),
            ("realized_NT", "Road congestion", TEAL),
            ("realized_F", "Full realized-cost effect", TEAL),
            ("primitive_F", "Extended approach", BLUE),
        ],
        scale=1.0e4,
    )
    add_panel_label(axes[0], "A", "From traditional to extended")
    axes[0].set_xlabel(r"Welfare elasticity ($\times 10^{-4}$)", fontsize=8)

    interval_plot(
        axes[1], rows,
        [
            ("d_edge", "Road congestion", TEAL),
            ("d_mode", "Flexible modes", PURPLE),
            ("d_route", "Route adjustment", ORANGE),
        ],
        zero_line=True,
    )
    add_panel_label(axes[1], "B", "Alternative adjustments")
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
            ("primitive_edge", "Road congestion", TEAL),
            ("primitive_pass_through", "Primitive pass-through", RED),
            ("primitive_net_gap", "Net traditional gap", MUTED),
        ],
        scale=1.0e4,
        zero_line=True,
    )
    add_panel_label(axes[2], "C", "Traditional-to-extended gap")
    axes[2].set_xlabel(r"Signed elasticity component ($\times 10^{-4}$)", fontsize=8)

    figure.subplots_adjust(wspace=0.48)
    save_figure(figure, output)


def sensitivity_figure(rows, output):
    parameters = [
        "alpha", "beta", "net_dispersion", "eta", "lambda_road",
        "common_congestion", "lambda_terminal",
    ]
    labels = {
        "alpha": "Productivity externality\n" + r"$\alpha$",
        "beta": "Amenity externality\n" + r"$\beta$",
        "net_dispersion": "Net dispersion",
        "eta": "Mode substitution\n" + r"$\eta$",
        "lambda_road": "Road congestion",
        "common_congestion": "Common congestion\nscale",
        "lambda_terminal": "Terminal congestion\nextension",
    }
    grouped = {parameter: [] for parameter in parameters}
    for row in rows:
        grouped[row["parameter"]].append(row)
    figure, axes = plt.subplots(
        len(parameters), 2, figsize=(8.2, 10.0), squeeze=False)
    for row_index, parameter in enumerate(parameters):
        data = sorted(grouped[parameter], key=lambda row: float(row["value"]))
        x = np.asarray([float(row["value"]) for row in data])
        mean_gain = 1.0e4*np.asarray(
            [float(row["mean_physical_gain_pct"]) for row in data])
        rank = np.asarray([float(row["spearman_vs_baseline"]) for row in data])
        mean_axis, rank_axis = axes[row_index]
        mean_axis.plot(
            x, mean_gain, color=BLUE, marker="o", markersize=3.0)
        rank_axis.plot(
            x, rank, color=ORANGE, marker="o", markersize=3.0)
        style_axis(mean_axis, grid_axis="y")
        style_axis(rank_axis, grid_axis="y")
        rank_lower = max(0.8, float(rank.min())-0.01)
        rank_upper = min(1.005, float(rank.max())+0.005)
        rank_axis.set_ylim(rank_lower, rank_upper)
        mean_axis.tick_params(axis="x", labelsize=6.5)
        rank_axis.tick_params(axis="x", labelsize=6.5)
    axes[-1, 0].set_xlabel("Parameter value")
    axes[-1, 1].set_xlabel("Parameter value")
    add_panel_label(
        axes[0, 0], "A", r"Mean welfare gain ($\%\times 10^{4}$)")
    add_panel_label(
        axes[0, 1], "B", "Rank correlation with baseline")
    figure.subplots_adjust(
        left=0.24, right=0.99, bottom=0.07, top=0.97,
        wspace=0.34, hspace=0.38)
    for row_index, parameter in enumerate(parameters):
        bounds = axes[row_index, 0].get_position()
        figure.text(
            0.015, 0.5*(bounds.y0+bounds.y1), labels[parameter],
            ha="left", va="center", fontsize=7.3, color=INK,
            linespacing=1.05,
        )
    save_figure(figure, output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    geometry = read_rows(args.input_dir / "paper_link_geometry.csv")
    physical = read_rows(args.input_dir / "decomposition_physical.csv")
    sensitivity = read_rows(args.input_dir / "paper_sensitivity.csv")
    label_rows = read_rows(args.input_dir / "paper_link_labels.csv")
    labels = {
        row["physical_link_id"]: plot_link_label(row)
        for row in label_rows
    }
    map_values = np.concatenate((
        np.asarray([float(row["hulten"]) for row in geometry]),
        np.asarray([float(row["primitive_F"]) for row in geometry]),
    ))
    map_norm, map_cmap = welfare_norm(
        map_values, robust=True, include_zero=True)
    map_figure(
        geometry, "hulten", "Traditional approach: welfare elasticity",
        args.output_dir / "rsue_hulten_map",
        norm=map_norm, cmap=map_cmap,
    )
    map_figure(
        geometry, "primitive_F", "Extended approach: welfare elasticity",
        args.output_dir / "rsue_ift_map",
        norm=map_norm, cmap=map_cmap,
    )
    scatter_figure(
        physical, args.output_dir / "rsue_hulten_vs_ift", labels)
    decomposition_figure(physical, args.output_dir / "rsue_decomposition")
    sensitivity_figure(sensitivity, args.output_dir / "rsue_sensitivity")


if __name__ == "__main__":
    main()
