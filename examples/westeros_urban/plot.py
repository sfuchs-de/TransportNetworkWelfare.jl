#!/usr/bin/env python3
"""Plot the Westeros urban welfare results over the source geography."""

import argparse
import csv
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.colors import Normalize


ROOT = Path(__file__).resolve().parent


def polygon_rings(geometry):
    polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
    yield from polygons


def road_lines(feature):
    geometry = feature["geometry"]
    return [geometry["coordinates"]] if geometry["type"] == "LineString" else geometry["coordinates"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", type=Path, default=ROOT / "generated")
    parser.add_argument("--output", type=Path, default=ROOT / "generated" / "figures")
    parser.add_argument("--label-links", type=int, default=0)
    parser.add_argument("--corridors", action="store_true",
                        help="draw overlapping source-road corridors instead of reduced links")
    arguments = parser.parse_args()

    generated = arguments.generated
    cache = generated / "source_cache"
    continent = json.loads((cache / "continent.geojson").read_text(encoding="utf-8"))
    roads = json.loads((cache / "roads.geojson").read_text(encoding="utf-8"))
    with (generated / "data" / "nodes.csv").open(newline="", encoding="utf-8") as handle:
        node_rows = list(csv.DictReader(handle))
    with (generated / "data" / "edge_modes.csv").open(newline="", encoding="utf-8") as handle:
        edge_rows = list(csv.DictReader(handle))
    with (generated / "output" / "welfare_physical.csv").open(newline="", encoding="utf-8") as handle:
        result_rows = list(csv.DictReader(handle))
    corridor_payload = json.loads(
        (generated / "link_geometry.geojson").read_text(encoding="utf-8"))

    nodes = {row["node_id"]: row for row in node_rows}
    links = {}
    for row in edge_rows:
        links.setdefault(row["physical_link_id"], (row["origin"], row["destination"]))
    values = {row["physical_link_id"]: float(row["primitive_F"]) for row in result_rows}
    corridor_geometry = {
        feature["properties"]["physical_link_id"]: feature["geometry"]["coordinates"]
        for feature in corridor_payload["features"]
    }
    missing = set(links) - set(values)
    if missing:
        raise RuntimeError(f"results omit {len(missing)} Westeros links")
    missing_geometry = set(links) - set(corridor_geometry)
    if missing_geometry:
        raise RuntimeError(f"corridor geometry omits {len(missing_geometry)} Westeros links")

    figure, axis = plt.subplots(figsize=(7.6, 8.6))
    for feature in continent["features"]:
        for polygon in polygon_rings(feature["geometry"]):
            exterior = polygon[0]
            axis.fill([point[0] for point in exterior], [point[1] for point in exterior],
                      color="#f1eadc", edgecolor="#7b7468", linewidth=0.7, zorder=0)
            for hole in polygon[1:]:
                axis.fill([point[0] for point in hole], [point[1] for point in hole],
                          color="white", zorder=0)
    source_segments = []
    for feature in roads["features"]:
        source_segments.extend(road_lines(feature))
    axis.add_collection(LineCollection(
        source_segments, colors="#b9aa86", linewidths=0.55, alpha=0.45, zorder=1))

    ordered = sorted(links)
    segments = []
    weights = []
    for link in ordered:
        origin, destination = links[link]
        first, second = nodes[origin], nodes[destination]
        segments.append(corridor_geometry[link] if arguments.corridors else [
            (float(first["longitude"]), float(first["latitude"])),
            (float(second["longitude"]), float(second["latitude"])),
        ])
        weights.append(values[link])
    lower, upper = min(weights), max(weights)
    normalization = Normalize(lower, upper if upper > lower else lower + 1)
    maximum = max(map(abs, weights))
    collection = LineCollection(
        segments, array=weights, cmap="viridis", norm=normalization,
        linewidths=[0.9 + 3.5 * abs(value) / maximum for value in weights],
        alpha=0.9, zorder=2)
    axis.add_collection(collection)

    employment = [float(row["employment"]) for row in node_rows]
    axis.scatter(
        [float(row["longitude"]) for row in node_rows],
        [float(row["latitude"]) for row in node_rows],
        s=[8 + 80 * value / max(employment) for value in employment],
        facecolor="white", edgecolor="#222222", linewidth=0.55, zorder=3)
    preferred_labels = {
        "Winterfell": (4, 4),
        "King's Landing": (5, -10),
        "Oldtown": (4, -8),
        "Sunspear": (5, 3),
        "The Eyrie": (4, 4),
    }
    for row in node_rows:
        if row["name"] in preferred_labels:
            axis.annotate(row["name"], (float(row["longitude"]), float(row["latitude"])),
                          xytext=preferred_labels[row["name"]], textcoords="offset points", fontsize=7,
                          color="#222222", zorder=4)
    for link in sorted(ordered, key=lambda value: abs(values[value]), reverse=True)[:arguments.label_links]:
        origin, destination = links[link]
        first, second = nodes[origin], nodes[destination]
        x = (float(first["longitude"]) + float(second["longitude"])) / 2
        y = (float(first["latitude"]) + float(second["latitude"])) / 2
        label = f"{first['name']} - {second['name']}"
        axis.annotate(label, (x, y), xytext=(3, -6), textcoords="offset points",
                      fontsize=6, color="#333333", zorder=4)

    colorbar = figure.colorbar(
        collection, ax=axis, orientation="horizontal", fraction=0.025, pad=0.015,
        aspect=45)
    colorbar.set_label("Extended welfare elasticity", fontsize=8)
    colorbar.ax.tick_params(labelsize=7)
    axis.set_aspect("equal", adjustable="box")
    road_x = [point[0] for segment in source_segments for point in segment]
    road_y = [point[1] for segment in source_segments for point in segment]
    x_margin = 0.04 * (max(road_x) - min(road_x))
    y_margin = 0.04 * (max(road_y) - min(road_y))
    axis.set_xlim(min(road_x) - x_margin, max(road_x) + x_margin)
    axis.set_ylim(min(road_y) - y_margin, max(road_y) + y_margin)
    axis.axis("off")
    figure.tight_layout()
    arguments.output.mkdir(parents=True, exist_ok=True)
    stem = "westeros_welfare_corridors" if arguments.corridors else "westeros_welfare"
    figure.savefig(arguments.output / f"{stem}.pdf", bbox_inches="tight")
    figure.savefig(arguments.output / f"{stem}_transparent.png", dpi=260,
                   transparent=True, bbox_inches="tight")
    plt.close(figure)


if __name__ == "__main__":
    main()
