#!/usr/bin/env python3
"""Plot a validated network and physical-link result table."""

import argparse
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.colors import Normalize
import numpy as np


def read_nodes(path: Path):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    required = {"node_id", "income", "longitude", "latitude"}
    if not rows or not required.issubset(rows[0]):
        raise ValueError(f"{path} must contain {sorted(required)}")
    nodes = {}
    for row in rows:
        identifier = row["node_id"].strip()
        if not identifier or identifier in nodes:
            raise ValueError(f"invalid or duplicate node_id {identifier!r}")
        longitude = float(row["longitude"])
        latitude = float(row["latitude"])
        income = float(row["income"])
        if not np.isfinite([longitude, latitude, income]).all() or income <= 0:
            raise ValueError(f"node {identifier} has invalid coordinates or income")
        nodes[identifier] = (longitude, latitude, income)
    return nodes


def read_physical_edges(path: Path, nodes):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    required = {"physical_link_id", "origin", "destination"}
    if not rows or not required.issubset(rows[0]):
        raise ValueError(f"{path} must contain {sorted(required)}")
    links = {}
    for row in rows:
        link = row["physical_link_id"].strip()
        origin, destination = row["origin"].strip(), row["destination"].strip()
        if origin not in nodes or destination not in nodes:
            raise ValueError(f"physical link {link} references an unknown node")
        unordered = frozenset((origin, destination))
        if len(unordered) != 2:
            raise ValueError(f"physical link {link} is a self-link")
        prior = links.get(link)
        if prior is not None and frozenset(prior) != unordered:
            raise ValueError(f"physical link {link} has inconsistent endpoints")
        links[link] = (origin, destination)
    return links


def read_results(path: Path, metric: str, links):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    required = {"physical_link_id", metric}
    if not rows or not required.issubset(rows[0]):
        raise ValueError(f"{path} must contain {sorted(required)}")
    values = {}
    for row in rows:
        link = row["physical_link_id"].strip()
        if link not in links:
            raise ValueError(f"result references unknown physical link {link}")
        if link in values:
            raise ValueError(f"duplicate result for physical link {link}")
        value = float(row[metric])
        if not np.isfinite(value):
            raise ValueError(f"physical link {link} has nonfinite {metric}")
        values[link] = value
    missing = set(links)-set(values)
    if missing:
        raise ValueError(f"results omit physical links: {sorted(missing)}")
    return values


def plot_network(nodes_path: Path, edges_path: Path, results_path: Path,
                 output_path: Path, *, metric="primitive_F", label_top=0,
                 transparent=False, dpi=240):
    nodes = read_nodes(nodes_path)
    links = read_physical_edges(edges_path, nodes)
    values = read_results(results_path, metric, links)
    ordered = sorted(links)
    segments = [[nodes[links[link][0]][:2], nodes[links[link][1]][:2]]
                for link in ordered]
    weights = np.array([values[link] for link in ordered])
    absolute = np.abs(weights)
    scale = absolute.max()
    widths = 0.8+3.2*(absolute/scale if scale > 0 else np.ones_like(absolute))
    if weights.min() < 0 < weights.max():
        limit = max(abs(weights.min()), abs(weights.max()))
        normalization = Normalize(-limit, limit)
        color_map = "coolwarm"
    else:
        lower, upper = weights.min(), weights.max()
        normalization = Normalize(lower, upper if upper > lower else lower+1)
        color_map = "viridis"

    figure, axis = plt.subplots(figsize=(7.2, 4.8))
    collection = LineCollection(
        segments, array=weights, cmap=color_map, norm=normalization,
        linewidths=widths, alpha=0.86, zorder=1,
    )
    axis.add_collection(collection)
    coordinates = np.array([nodes[node][:2] for node in sorted(nodes)])
    incomes = np.array([nodes[node][2] for node in sorted(nodes)])
    sizes = 18+115*incomes/incomes.max()
    axis.scatter(
        coordinates[:, 0], coordinates[:, 1], s=sizes,
        facecolor="white", edgecolor="#222222", linewidth=0.65, zorder=2,
    )
    for link in sorted(ordered, key=lambda key: abs(values[key]), reverse=True)[:label_top]:
        origin, destination = links[link]
        x = (nodes[origin][0]+nodes[destination][0])/2
        y = (nodes[origin][1]+nodes[destination][1])/2
        axis.annotate(link, (x, y), xytext=(3, 3), textcoords="offset points",
                      fontsize=7, color="#222222", zorder=3)
    axis.autoscale()
    axis.set_aspect("equal", adjustable="datalim")
    axis.axis("off")
    figure.colorbar(collection, ax=axis, fraction=0.035, pad=0.02, label=metric)
    figure.tight_layout(pad=0.25)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    metadata = {"Creator": "TransportNetworkWelfare.jl"}
    if output_path.suffix.lower() == ".pdf":
        metadata.update({"CreationDate": None, "ModDate": None})
    figure.savefig(
        output_path, dpi=dpi, transparent=transparent, metadata=metadata)
    plt.close(figure)
    return output_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("nodes", type=Path)
    parser.add_argument("edge_modes", type=Path)
    parser.add_argument("results", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--metric", default="primitive_F")
    parser.add_argument("--label-top", type=int, default=0)
    parser.add_argument("--transparent", action="store_true")
    args = parser.parse_args()
    if args.label_top < 0:
        parser.error("--label-top must be nonnegative")
    plot_network(
        args.nodes, args.edge_modes, args.results, args.output,
        metric=args.metric, label_top=args.label_top, transparent=args.transparent,
    )


if __name__ == "__main__":
    main()
