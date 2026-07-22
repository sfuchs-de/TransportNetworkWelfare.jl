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
from mpl_toolkits.mplot3d.art3d import Line3DCollection, Poly3DCollection
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
        elevation = float(row.get("elevation") or 0.0)
        income = float(row["income"])
        if not np.isfinite([longitude, latitude, elevation, income]).all() or income <= 0:
            raise ValueError(f"node {identifier} has invalid coordinates or income")
        nodes[identifier] = (longitude, latitude, elevation, income)
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


def add_cow_surface(axis):
    """Add an original low-detail cow assembled from analytic primitives."""
    surface_color = "#B8BDC4"

    def ellipsoid(center, radii, alpha=0.13):
        u = np.linspace(0, 2*np.pi, 36)
        v = np.linspace(0, np.pi, 22)
        x = center[0]+radii[0]*np.outer(np.cos(u), np.sin(v))
        depth = center[1]+radii[1]*np.outer(np.sin(u), np.sin(v))
        height = center[2]+radii[2]*np.outer(np.ones_like(u), np.cos(v))
        axis.plot_surface(
            x, depth, height, color=surface_color, alpha=alpha,
            linewidth=0, antialiased=True, shade=True, zorder=0,
        )

    def leg(center_x, center_depth, top, bottom, radius=0.16):
        theta = np.linspace(0, 2*np.pi, 24)
        height = np.linspace(bottom, top, 8)
        x = center_x+radius*np.outer(np.cos(theta), np.ones_like(height))
        depth = center_depth+radius*np.outer(np.sin(theta), np.ones_like(height))
        z = np.outer(np.ones_like(theta), height)
        axis.plot_surface(
            x, depth, z, color=surface_color, alpha=0.14,
            linewidth=0, antialiased=True, shade=True, zorder=0,
        )

    ellipsoid((3.0, 0.0, 2.0), (3.0, 0.88, 1.32), alpha=0.11)
    ellipsoid((6.45, 0.0, 2.5), (0.72, 0.62, 0.88), alpha=0.12)
    ellipsoid((7.65, 0.0, 2.62), (0.98, 0.72, 0.76), alpha=0.14)
    ellipsoid((8.42, 0.0, 2.30), (0.68, 0.56, 0.46), alpha=0.15)
    ellipsoid((7.20, -0.72, 3.15), (0.42, 0.18, 0.20), alpha=0.16)
    ellipsoid((8.10, 0.72, 3.12), (0.42, 0.18, 0.20), alpha=0.16)
    for center_x, center_depth, top, bottom in (
        (1.4, -0.58, 0.75, -1.42),
        (2.6, 0.58, 0.72, -1.50),
        (4.0, -0.58, 0.72, -1.50),
        (5.1, 0.58, 0.82, -1.35),
    ):
        leg(center_x, center_depth, top, bottom)
    axis.plot(
        [0.1, -0.5, -1.2], [0.0, 0.2, 0.55], [2.2, 2.7, 3.2],
        color="#777777", linewidth=3.0, alpha=0.45, zorder=0,
    )
    axis.plot(
        [7.25, 7.15], [-0.48, -0.70], [3.20, 3.92],
        color="#777777", linewidth=3.0, alpha=0.45, zorder=0,
    )
    axis.plot(
        [8.15, 8.30], [0.48, 0.68], [3.20, 3.82],
        color="#777777", linewidth=3.0, alpha=0.45, zorder=0,
    )


def read_ascii_ply(path: Path):
    """Read vertex coordinates and polygon faces from an ASCII PLY mesh."""
    with path.open(encoding="ascii") as handle:
        if handle.readline().strip() != "ply":
            raise ValueError(f"{path} is not a PLY file")
        vertex_count = face_count = None
        ascii_format = False
        while True:
            raw = handle.readline()
            if not raw:
                raise ValueError(f"{path} has no end_header marker")
            line = raw.strip()
            if line == "format ascii 1.0":
                ascii_format = True
            elif line.startswith("element vertex "):
                vertex_count = int(line.split()[-1])
            elif line.startswith("element face "):
                face_count = int(line.split()[-1])
            elif line == "end_header":
                break
        if not ascii_format or not vertex_count or not face_count:
            raise ValueError(f"{path} must be a nonempty ASCII PLY 1.0 mesh")
        vertices = []
        for _ in range(vertex_count):
            values = handle.readline().split()
            if len(values) < 3:
                raise ValueError(f"{path} has an incomplete vertex table")
            vertices.append([float(value) for value in values[:3]])
        faces = []
        for _ in range(face_count):
            values = handle.readline().split()
            if not values:
                raise ValueError(f"{path} has an incomplete face table")
            count = int(values[0])
            if count < 3 or len(values) != count+1:
                raise ValueError(f"{path} contains an invalid polygon face")
            face = [int(value) for value in values[1:]]
            if min(face) < 0 or max(face) >= vertex_count:
                raise ValueError(f"{path} contains an out-of-range vertex index")
            faces.append(face)
    vertices = np.asarray(vertices, dtype=float)
    if not np.isfinite(vertices).all():
        raise ValueError(f"{path} contains nonfinite vertices")
    return vertices, faces


def add_ply_surface(axis, path: Path, target_coordinates):
    """Scale a cow PLY mesh to the plotted network's x/depth/height bounds."""
    vertices, faces = read_ascii_ply(path)
    # The source cow uses x=length, y=height, and z=depth.
    source = vertices[:, (0, 2, 1)]
    source_min, source_span = source.min(axis=0), np.ptp(source, axis=0)
    target_min, target_span = target_coordinates.min(axis=0), np.ptp(
        target_coordinates, axis=0)
    if np.any(source_span <= 0) or np.any(target_span <= 0):
        raise ValueError("PLY and network coordinates must span all three dimensions")
    mapped = target_min+(source-source_min)/source_span*target_span
    surface = Poly3DCollection(
        [mapped[face] for face in faces],
        facecolor="#9BA2AA", edgecolor="#555B62", linewidth=0.04,
        alpha=0.16, zorder=0,
    )
    axis.add_collection3d(surface)


def plot_network(nodes_path: Path, edges_path: Path, results_path: Path,
                 output_path: Path, *, metric="primitive_F", label_top=0,
                 transparent=False, three_dimensional=False,
                 cow_surface=False, surface_ply=None, elevation_angle=18.0,
                 azimuth=-62.0, dpi=240):
    nodes = read_nodes(nodes_path)
    links = read_physical_edges(edges_path, nodes)
    values = read_results(results_path, metric, links)
    ordered = sorted(links)
    def plotted_coordinate(node):
        x, y, depth, _ = nodes[node]
        return (x, depth, y) if three_dimensional else (x, y)

    segments = [[plotted_coordinate(links[link][0]),
                 plotted_coordinate(links[link][1])]
                for link in ordered]
    coordinates = np.array([plotted_coordinate(node) for node in sorted(nodes)])
    incomes = np.array([nodes[node][3] for node in sorted(nodes)])
    weights = np.array([values[link] for link in ordered])
    absolute = np.abs(weights)
    scale = absolute.max()
    link_density = min(1.0, np.sqrt(500/max(len(ordered), 1)))
    widths = link_density*(0.8+3.2*(
        absolute/scale if scale > 0 else np.ones_like(absolute)))
    if weights.min() < 0 < weights.max():
        limit = max(abs(weights.min()), abs(weights.max()))
        normalization = Normalize(-limit, limit)
        color_map = "coolwarm"
    else:
        lower, upper = weights.min(), weights.max()
        normalization = Normalize(lower, upper if upper > lower else lower+1)
        color_map = "viridis"

    if three_dimensional:
        figure = plt.figure(figsize=(8.0, 5.2))
        axis = figure.add_subplot(111, projection="3d", proj_type="ortho")
        collection_class = Line3DCollection
        if cow_surface:
            add_cow_surface(axis)
        elif surface_ply is not None:
            add_ply_surface(axis, Path(surface_ply), coordinates)
    else:
        figure, axis = plt.subplots(figsize=(7.2, 4.8))
        collection_class = LineCollection
    collection = collection_class(
        segments, array=weights, cmap=color_map, norm=normalization,
        linewidths=widths, alpha=0.86, zorder=1,
    )
    axis.add_collection(collection)
    node_density = min(1.0, np.sqrt(200/max(len(nodes), 1)))
    sizes = node_density*(8+45*incomes/incomes.max())
    if three_dimensional:
        axis.scatter(
            coordinates[:, 0], coordinates[:, 1], coordinates[:, 2], s=sizes,
            facecolor="white", edgecolor="#222222", linewidth=0.65,
            depthshade=False, zorder=2,
        )
    else:
        axis.scatter(
            coordinates[:, 0], coordinates[:, 1], s=sizes,
            facecolor="white", edgecolor="#222222", linewidth=0.65, zorder=2,
        )
    for link in sorted(ordered, key=lambda key: abs(values[key]), reverse=True)[:label_top]:
        origin, destination = links[link]
        x = (nodes[origin][0]+nodes[destination][0])/2
        y = (nodes[origin][1]+nodes[destination][1])/2
        if three_dimensional:
            depth = (nodes[origin][2]+nodes[destination][2])/2
            axis.text(x, depth, y, link, fontsize=7, color="#222222", zorder=3)
        else:
            axis.annotate(link, (x, y), xytext=(3, 3), textcoords="offset points",
                          fontsize=7, color="#222222", zorder=3)
    axis.autoscale()
    if three_dimensional:
        spans = np.ptp(coordinates, axis=0)
        axis.set_box_aspect((spans[0], spans[1], max(spans[2], 0.25*spans[1])))
        axis.view_init(elev=elevation_angle, azim=azimuth)
    else:
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
    parser.add_argument("--three-dimensional", action="store_true")
    parser.add_argument("--cow-surface", action="store_true")
    parser.add_argument("--surface-ply", type=Path)
    parser.add_argument("--elevation-angle", type=float, default=18.0)
    parser.add_argument("--azimuth", type=float, default=-62.0)
    args = parser.parse_args()
    if args.label_top < 0:
        parser.error("--label-top must be nonnegative")
    if args.cow_surface and not args.three_dimensional:
        parser.error("--cow-surface requires --three-dimensional")
    if args.surface_ply is not None and not args.three_dimensional:
        parser.error("--surface-ply requires --three-dimensional")
    if args.cow_surface and args.surface_ply is not None:
        parser.error("choose either --cow-surface or --surface-ply")
    plot_network(
        args.nodes, args.edge_modes, args.results, args.output,
        metric=args.metric, label_top=args.label_top, transparent=args.transparent,
        three_dimensional=args.three_dimensional,
        cow_surface=args.cow_surface, surface_ply=args.surface_ply,
        elevation_angle=args.elevation_angle, azimuth=args.azimuth,
    )


if __name__ == "__main__":
    main()
