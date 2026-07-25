#!/usr/bin/env python3
"""Render deterministic Seattle transit-welfare figures from validated CSVs."""

import argparse
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.colors import Normalize, TwoSlopeNorm
import numpy as np

try:
    import shapefile
except ImportError:  # Geography is optional for fixture tests.
    shapefile = None


COLORS = {
    "bus": "#26734D",
    "rail": "#B5483A",
    "ferry": "#2B6EA6",
    "all_transit": "#343A40",
}
LABELS = {
    "bus": "Bus",
    "rail": "Rail / streetcar",
    "ferry": "Ferry",
    "all_transit": "All transit",
}


def read_rows(path):
    with Path(path).open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def read_nodes(path):
    rows = read_rows(path)
    nodes = {}
    for row in rows:
        identifier = row["node_id"].strip()
        longitude, latitude = float(row["longitude"]), float(row["latitude"])
        if identifier in nodes or not np.isfinite([longitude, latitude]).all():
            raise ValueError(f"invalid Seattle node {identifier!r}")
        nodes[identifier] = (longitude, latitude)
    if not nodes:
        raise ValueError("Seattle node file is empty")
    return nodes


def numeric(rows, field):
    values = np.asarray([float(row[field]) for row in rows], dtype=float)
    if not np.isfinite(values).all():
        raise ValueError(f"{field} contains nonfinite values")
    return values


def average_ranks(values):
    values = np.asarray(values, dtype=float)
    order = np.argsort(values, kind="mergesort")
    ranks = np.empty(len(values), dtype=float)
    first = 0
    while first < len(values):
        last = first + 1
        while last < len(values) and values[order[last]] == values[order[first]]:
            last += 1
        ranks[order[first:last]] = 0.5 * (first + last - 1)
        first = last
    return ranks


def iter_shape_parts(shape):
    points = np.asarray(shape.points, dtype=float)
    boundaries = list(shape.parts) + [len(points)]
    for first, last in zip(boundaries[:-1], boundaries[1:]):
        yield points[first:last]


def matching_shapefile(root, token):
    matches = sorted(Path(root).glob(f"**/*{token}*.shp"))
    if len(matches) != 1:
        raise ValueError(f"expected one {token} shapefile below {root}, found {len(matches)}")
    return matches[0]


def record_dict(reader, record):
    fields = [field[0] for field in reader.fields[1:]]
    return dict(zip(fields, record))


def add_geography(axis, root):
    if root is None:
        return
    if shapefile is None:
        raise RuntimeError("pyshp is required when --geography-root is supplied")

    water_reader = shapefile.Reader(str(matching_shapefile(root, "areawater")))
    for shape in water_reader.shapes():
        for part in iter_shape_parts(shape):
            axis.fill(part[:, 0], part[:, 1], color="#DCEAF0",
                      edgecolor="none", zorder=0)

    county_reader = shapefile.Reader(str(matching_shapefile(root, "county")))
    for item in county_reader.iterShapeRecords():
        record = record_dict(county_reader, item.record)
        if str(record.get("STATEFP")) != "53" or str(record.get("COUNTYFP")) != "033":
            continue
        for part in iter_shape_parts(item.shape):
            axis.plot(part[:, 0], part[:, 1], color="#59636B",
                      linewidth=0.65, zorder=1)

    place_reader = shapefile.Reader(str(matching_shapefile(root, "place")))
    for item in place_reader.iterShapeRecords():
        record = record_dict(place_reader, item.record)
        if str(record.get("NAME")) != "Seattle":
            continue
        for part in iter_shape_parts(item.shape):
            axis.plot(part[:, 0], part[:, 1], color="#7C858C",
                      linewidth=0.6, linestyle=(0, (2, 2)), zorder=1)


def figure_paths(output, stem):
    return Path(output) / f"{stem}.pdf", Path(output) / f"{stem}.png"


def save_pair(figure, output, stem):
    pdf, png = figure_paths(output, stem)
    pdf.parent.mkdir(parents=True, exist_ok=True)
    figure.savefig(
        pdf, bbox_inches="tight", transparent=True,
        metadata={"Creator": "TransportNetworkWelfare.jl",
                  "CreationDate": None, "ModDate": None},
    )
    figure.savefig(
        png, dpi=300, bbox_inches="tight", transparent=True,
        metadata={"Software": "TransportNetworkWelfare.jl"},
    )
    plt.close(figure)
    return [pdf, png]


def corridor_segments(rows, nodes):
    segments = []
    for row in rows:
        origin, destination = row["origin"], row["destination"]
        if origin not in nodes or destination not in nodes:
            raise ValueError(f"corridor {row['corridor_id']} has an unknown endpoint")
        segments.append([nodes[origin], nodes[destination]])
    return segments


def welfare_norm(values):
    lower, upper = float(np.min(values)), float(np.max(values))
    if lower < 0 < upper:
        limit = max(abs(lower), abs(upper))
        return TwoSlopeNorm(vmin=-limit, vcenter=0, vmax=limit), "coolwarm"
    if upper == lower:
        upper = lower + max(abs(lower), 1.0) * 1e-9
    return Normalize(vmin=lower, vmax=upper), "viridis"


def add_corridors(axis, rows, nodes, field, norm, cmap, geography_root):
    add_geography(axis, geography_root)
    segments = corridor_segments(rows, nodes)
    values = numeric(rows, field)
    collection = LineCollection(
        segments, array=values, cmap=cmap, norm=norm,
        linewidths=1.3, alpha=0.92, zorder=3,
    )
    axis.add_collection(collection)
    coordinates = np.asarray(list(nodes.values()))
    axis.set_xlim(coordinates[:, 0].min()-0.02, coordinates[:, 0].max()+0.02)
    axis.set_ylim(coordinates[:, 1].min()-0.02, coordinates[:, 1].max()+0.02)
    axis.set_aspect("equal", adjustable="box")
    axis.axis("off")
    return collection


def mode_welfare_map(artifacts, nodes, geography_root):
    modes = ("bus", "rail", "ferry")
    rows = {mode: read_rows(Path(artifacts) / f"links_{mode}.csv")
            for mode in modes}
    combined = np.concatenate([
        numeric(rows[mode], "extended_gain_pct") for mode in modes])
    norm, cmap = welfare_norm(combined)
    figure, axes = plt.subplots(1, 3, figsize=(10.8, 4.2), sharex=True, sharey=True)
    collection = None
    for axis, mode in zip(axes, modes):
        collection = add_corridors(
            axis, rows[mode], nodes, "extended_gain_pct",
            norm, cmap, geography_root)
        axis.text(0.02, 0.98, LABELS[mode], transform=axis.transAxes,
                  ha="left", va="top", fontsize=9, fontweight="bold")
    figure.colorbar(
        collection, ax=axes, fraction=0.025, pad=0.015,
        label="Welfare gain from a 1% improvement (%)")
    figure.subplots_adjust(left=0.01, right=0.91, bottom=0.01, top=0.99, wspace=0.03)
    return save_pair(figure, artifacts, "seattle_transit_welfare_map")


def single_map(artifacts, nodes, geography_root, field, stem, colorbar_label):
    rows = read_rows(Path(artifacts) / "links_all_transit.csv")
    values = numeric(rows, field)
    norm, cmap = welfare_norm(values)
    figure, axis = plt.subplots(figsize=(6.4, 5.4))
    collection = add_corridors(
        axis, rows, nodes, field, norm, cmap, geography_root)
    largest = np.argsort(np.abs(values))[-5:]
    for index in largest:
        row = rows[index]
        x = (nodes[row["origin"]][0]+nodes[row["destination"]][0])/2
        y = (nodes[row["origin"]][1]+nodes[row["destination"]][1])/2
        axis.annotate(
            row["corridor_id"], (x, y), xytext=(3, 3),
            textcoords="offset points", fontsize=6, color="#202428")
    figure.colorbar(collection, ax=axis, fraction=0.035, pad=0.02,
                    label=colorbar_label)
    figure.tight_layout(pad=0.2)
    return save_pair(figure, artifacts, stem)


def scatter_figure(artifacts):
    modes = ("bus", "rail", "ferry", "all_transit")
    figure, axes = plt.subplots(2, 2, figsize=(7.6, 7.0), sharex=True, sharey=True)
    all_values = []
    loaded = {}
    for mode in modes:
        rows = read_rows(Path(artifacts) / f"directed_{mode}.csv")
        x, y = numeric(rows, "hulten"), numeric(rows, "primitive_F")
        loaded[mode] = (rows, x, y)
        all_values.extend(x)
        all_values.extend(y)
    lower, upper = min(all_values), max(all_values)
    padding = 0.04*(upper-lower if upper > lower else 1.0)
    limits = (lower-padding, upper+padding)
    for axis, mode in zip(axes.flat, modes):
        rows, x, y = loaded[mode]
        axis.scatter(
            x, y, s=15, alpha=0.48, color=COLORS[mode], edgecolors="none")
        axis.plot(limits, limits, color="#444444", linewidth=0.8,
                  linestyle=(0, (3, 2)))
        pearson = np.corrcoef(x, y)[0, 1] if len(x) > 1 else np.nan
        rx = average_ranks(x)
        ry = average_ranks(y)
        spearman = np.corrcoef(rx, ry)[0, 1] if len(x) > 1 else np.nan
        pearson_text = f"{pearson:.3f}" if np.isfinite(pearson) else "n/a"
        spearman_text = f"{spearman:.3f}" if np.isfinite(spearman) else "n/a"
        axis.text(0.03, 0.97, LABELS[mode], transform=axis.transAxes,
                  ha="left", va="top", fontsize=9, fontweight="bold")
        axis.text(
            0.03, 0.88, f"Pearson {pearson_text}\nRank {spearman_text}",
            transform=axis.transAxes, ha="left", va="top", fontsize=7)
        for index in np.argsort(y)[-3:]:
            axis.annotate(
                rows[index]["edge_id"], (x[index], y[index]),
                xytext=(3, 3), textcoords="offset points", fontsize=5.5)
        axis.set_xlim(*limits)
        axis.set_ylim(*limits)
        axis.spines[["top", "right"]].set_visible(False)
    for axis in axes[-1, :]:
        axis.set_xlabel("Traditional approach")
    for axis in axes[:, 0]:
        axis.set_ylabel("Extended approach")
    figure.tight_layout(pad=0.6)
    return save_pair(figure, artifacts, "seattle_transit_traditional_extended")


def route_figure(artifacts):
    rows = read_rows(Path(artifacts) / "routes_all_transit.csv")
    rows.sort(key=lambda row: float(row["primitive_F"]), reverse=True)
    rows = rows[:20]
    values = numeric(rows, "extended_gain_pct")
    labels = [row["route_name"] for row in rows]
    colors = [COLORS.get(row["mode"], "#59636B") for row in rows]
    figure, axis = plt.subplots(figsize=(6.6, 5.6))
    positions = np.arange(len(rows))
    axis.barh(positions, values[::-1], color=colors[::-1], height=0.72)
    axis.set_yticks(positions, labels=labels[::-1], fontsize=7)
    axis.set_xlabel("Welfare gain from a 1% route-corridor improvement (%)")
    axis.spines[["top", "right", "left"]].set_visible(False)
    axis.tick_params(axis="y", length=0)
    figure.tight_layout(pad=0.4)
    return save_pair(figure, artifacts, "seattle_route_corridor_rankings")


def sensitivity_figure(artifacts):
    rows = read_rows(Path(artifacts) / "eta_sensitivity.csv")
    figure, axes = plt.subplots(1, 2, figsize=(8.0, 3.4))
    for mode in ("bus", "rail", "ferry", "all_transit"):
        selected = sorted(
            (row for row in rows if row["mode"] == mode),
            key=lambda row: float(row["eta"]))
        eta = numeric(selected, "eta")
        mean = numeric(selected, "mean_extended_gain_pct")
        rank = np.asarray([
            float(row["spearman_vs_eta_1_099"])
            if row["spearman_vs_eta_1_099"] else np.nan
            for row in selected
        ])
        axes[0].plot(eta, mean, marker="o", markersize=3,
                     linewidth=1.1, color=COLORS[mode], label=LABELS[mode])
        axes[1].plot(eta, rank, marker="o", markersize=3,
                     linewidth=1.1, color=COLORS[mode])
    for axis in axes:
        axis.axvline(1.099, color="#555555", linewidth=0.8,
                     linestyle=(0, (3, 2)))
        axis.set_xlabel(r"Mode substitution $\eta$")
        axis.spines[["top", "right"]].set_visible(False)
    axes[0].set_ylabel("Mean welfare gain (%)")
    axes[1].set_ylabel(r"Rank correlation with $\eta=1.099$")
    axes[1].ticklabel_format(axis="y", style="plain", useOffset=False)
    axes[1].yaxis.set_major_formatter(
        matplotlib.ticker.FormatStrFormatter("%.6f"))
    axes[0].legend(frameon=False, fontsize=7)
    figure.tight_layout(pad=0.5)
    return save_pair(figure, artifacts, "seattle_eta_sensitivity")


def build_figures(artifacts, nodes_path, geography_root=None):
    artifacts = Path(artifacts)
    nodes = read_nodes(nodes_path)
    outputs = []
    outputs.extend(mode_welfare_map(artifacts, nodes, geography_root))
    outputs.extend(single_map(
        artifacts, nodes, geography_root, "extended_gain_pct",
        "seattle_all_transit_welfare_map",
        "Welfare gain from a 1% improvement (%)"))
    outputs.extend(single_map(
        artifacts, nodes, geography_root, "extended_minus_traditional_pct",
        "seattle_transit_extended_minus_traditional",
        "Extended minus traditional welfare gain (percentage points)"))
    outputs.extend(scatter_figure(artifacts))
    outputs.extend(route_figure(artifacts))
    outputs.extend(sensitivity_figure(artifacts))
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--nodes", type=Path, required=True)
    parser.add_argument("--geography-root", type=Path)
    args = parser.parse_args()
    build_figures(args.artifacts, args.nodes, args.geography_root)


if __name__ == "__main__":
    main()
