#!/usr/bin/env python3
"""Render deterministic Seattle transit-welfare figures from validated CSVs."""

import argparse
import csv
import datetime as dt
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
from matplotlib.colors import LinearSegmentedColormap, Normalize, TwoSlopeNorm
from matplotlib.lines import Line2D
import numpy as np

try:
    import shapefile
except ImportError:  # Geography is optional for fixture tests.
    shapefile = None


COLORS = {
    "road": "#656D73",
    "bus": "#26734D",
    "rail": "#B5483A",
    "subway": "#7A4DA3",
    "streetcar": "#C64E36",
    "ferry": "#2B6EA6",
    "all_transit": "#343A40",
}
LABELS = {
    "road": "Road",
    "bus": "Bus",
    "rail": "Rail / streetcar",
    "subway": "Link light rail",
    "streetcar": "Seattle Streetcar",
    "ferry": "Ferry",
    "all_transit": "All transit",
}
AA_CMAP = LinearSegmentedColormap.from_list(
    "aa_blue_red", ("#2166AC", "#7B6CB4", "#D6604D", "#B2182B"))


def iter_rows(path):
    with Path(path).open(newline="", encoding="utf-8") as handle:
        yield from csv.DictReader(handle)


def read_rows(path):
    return list(iter_rows(path))


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


def read_node_mass(path):
    rows = read_rows(path)
    masses = {}
    for row in rows:
        identifier = row["node_id"].strip()
        resident = float(row.get("residents", row.get("income", 1.0)))
        employment = float(row.get("employment", 0.0))
        mass = resident + employment
        if identifier in masses or not np.isfinite(mass) or mass < 0:
            raise ValueError(f"invalid Seattle node mass {identifier!r}")
        masses[identifier] = mass
    return masses


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


def map_limits(nodes):
    coordinates = np.asarray(list(nodes.values()))
    return (
        (coordinates[:, 0].min()-0.02, coordinates[:, 0].max()+0.02),
        (coordinates[:, 1].min()-0.02, coordinates[:, 1].max()+0.02),
    )


def finish_map(axis, nodes):
    xlim, ylim = map_limits(nodes)
    axis.set_xlim(*xlim)
    axis.set_ylim(*ylim)
    axis.set_aspect("equal", adjustable="box")
    axis.axis("off")


def node_sizes(masses, maximum=34.0, minimum=2.0):
    values = np.asarray(list(masses.values()), dtype=float)
    scale = np.sqrt(values/max(values.max(), 1.0))
    return dict(zip(masses, minimum+(maximum-minimum)*scale))


def add_nodes(axis, nodes, masses, *, alpha=0.78, zorder=5):
    sizes = node_sizes(masses)
    axis.scatter(
        [nodes[key][0] for key in nodes],
        [nodes[key][1] for key in nodes],
        s=[sizes[key] for key in nodes],
        color="#111111", edgecolors="white", linewidths=0.18,
        alpha=alpha, zorder=zorder)


def unique_mode_segments(rows, nodes, mode=None):
    grouped = {}
    endpoints = {}
    for row in rows:
        if mode is not None and row["mode"] != mode:
            continue
        origin, destination = row["origin"], row["destination"]
        key = (*sorted((origin, destination)), row["mode"])
        grouped[key] = grouped.get(key, 0.0) + float(row.get("flow", 1.0))
        endpoints.setdefault(key, (origin, destination))
    segments = []
    values = []
    for key in sorted(grouped):
        origin, destination = endpoints[key]
        if origin not in nodes or destination not in nodes:
            raise ValueError(f"edge {origin}_{destination} has an unknown endpoint")
        segments.append([nodes[origin], nodes[destination]])
        values.append(grouped[key])
    return segments, np.asarray(values, dtype=float)


def add_road_context(axis, edge_rows, nodes):
    segments, _ = unique_mode_segments(edge_rows, nodes, "road")
    axis.add_collection(LineCollection(
        segments, colors="#C5C9CC", linewidths=0.38,
        alpha=0.72, zorder=2))


def geojson_lines(path):
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    output = []
    for feature in payload.get("features", []):
        geometry = feature.get("geometry") or {}
        coordinates = geometry.get("coordinates", [])
        kind = geometry.get("type")
        if kind == "LineString":
            candidates = [coordinates]
        elif kind == "MultiLineString":
            candidates = coordinates
        else:
            continue
        for line in candidates:
            array = np.asarray(line, dtype=float)
            if array.ndim == 2 and array.shape[0] >= 2:
                output.append(array[:, :2])
    return output


def gtfs_date(value):
    return dt.datetime.strptime(value, "%Y%m%d").date()


def active_gtfs_services(root, service_date=dt.date(2017, 6, 14)):
    root = Path(root)
    weekday = service_date.strftime("%A").lower()
    services = set()
    for row in read_rows(root / "calendar.txt"):
        if (gtfs_date(row["start_date"]) <= service_date <=
                gtfs_date(row["end_date"]) and row[weekday] == "1"):
            services.add(row["service_id"])
    for row in read_rows(root / "calendar_dates.txt"):
        if gtfs_date(row["date"]) != service_date:
            continue
        if row["exception_type"] == "1":
            services.add(row["service_id"])
        elif row["exception_type"] == "2":
            services.discard(row["service_id"])
        else:
            raise ValueError("invalid GTFS calendar exception")
    if not services:
        raise ValueError(f"GTFS has no service on {service_date}")
    return services


def route_type_mode(value):
    route_type = int(value)
    if route_type in (0, 1, 2):
        return "rail"
    if route_type == 3:
        return "bus"
    if route_type == 4:
        return "ferry"
    return None


def rail_route_category(row):
    if route_type_mode(row["route_type"]) != "rail":
        return None
    short_name = row.get("route_short_name", "").strip().upper()
    long_name = row.get("route_long_name", "").strip().upper()
    if short_name == "LINK" or "LINK LIGHT RAIL" in long_name:
        return "subway"
    if short_name.startswith("STCR") or "STREETCAR" in long_name:
        return "streetcar"
    return "rail"


def nearest_model_node(longitude, latitude, nodes, max_distance_km=2.0):
    identifiers = list(nodes)
    coordinates = np.asarray([nodes[key] for key in identifiers], dtype=float)
    phi = np.deg2rad(latitude)
    node_phi = np.deg2rad(coordinates[:, 1])
    delta_phi = node_phi - phi
    delta_lambda = np.deg2rad(coordinates[:, 0] - longitude)
    haversine = (
        np.sin(delta_phi/2)**2 +
        np.cos(phi)*np.cos(node_phi)*np.sin(delta_lambda/2)**2
    )
    distances = 2*6371.0088*np.arcsin(
        np.minimum(1.0, np.sqrt(haversine)))
    index = int(np.argmin(distances))
    return identifiers[index] if distances[index] <= max_distance_km else None


def gtfs_rail_corridor_classes(root, nodes):
    root = Path(root)
    required = ("routes.txt", "trips.txt", "stops.txt", "stop_times.txt")
    if any(not (root / name).is_file() for name in required):
        return {}

    services = active_gtfs_services(root)
    route_classes = {}
    for row in read_rows(root / "routes.txt"):
        category = rail_route_category(row)
        if category is not None:
            route_classes[row["route_id"]] = category
    trips = {
        row["trip_id"]: route_classes[row["route_id"]]
        for row in read_rows(root / "trips.txt")
        if row["service_id"] in services and row["route_id"] in route_classes
    }

    stop_nodes = {}
    for row in read_rows(root / "stops.txt"):
        location_type = row.get("location_type", "").strip()
        if location_type not in ("", "0"):
            continue
        stop_nodes[row["stop_id"]] = nearest_model_node(
            float(row["stop_lon"]), float(row["stop_lat"]), nodes)

    corridors = {}
    previous = {}
    for row in iter_rows(root / "stop_times.txt"):
        trip = row["trip_id"]
        if trip not in trips:
            continue
        sequence = int(row["stop_sequence"])
        node = stop_nodes.get(row["stop_id"])
        prior = previous.get(trip)
        if prior is not None and sequence <= prior[0]:
            raise ValueError(f"GTFS stop_sequence is not increasing for {trip}")
        if prior is not None and prior[1] is not None and node is not None:
            if prior[1] != node:
                key = tuple(sorted((prior[1], node)))
                corridors.setdefault(key, set()).add(trips[trip])
        previous[trip] = (sequence, node)
    return corridors


def gtfs_shapes(root):
    root = Path(root)
    services = active_gtfs_services(root)
    route_modes = {
        row["route_id"]: route_type_mode(row["route_type"])
        for row in read_rows(root / "routes.txt")
    }
    shape_modes = {}
    for row in read_rows(root / "trips.txt"):
        if row["service_id"] not in services or not row.get("shape_id"):
            continue
        mode = route_modes.get(row["route_id"])
        if mode is None:
            continue
        prior = shape_modes.setdefault(row["shape_id"], mode)
        if prior != mode:
            raise ValueError(f"GTFS shape {row['shape_id']} spans multiple modes")
    points = {shape_id: [] for shape_id in shape_modes}
    for row in read_rows(root / "shapes.txt"):
        shape_id = row["shape_id"]
        if shape_id not in points:
            continue
        points[shape_id].append((
            int(row["shape_pt_sequence"]),
            float(row["shape_pt_lon"]),
            float(row["shape_pt_lat"]),
        ))
    output = {mode: [] for mode in ("bus", "rail", "ferry")}
    for shape_id, rows in points.items():
        rows.sort()
        if len(rows) >= 2:
            output[shape_modes[shape_id]].append(
                np.asarray([(lon, lat) for _, lon, lat in rows]))
    return output


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


def welfare_widths(values, maximum):
    values = np.asarray(values, dtype=float)
    if maximum <= 0 or not np.isfinite(maximum):
        raise ValueError("the common welfare scale must be positive and finite")
    if not np.isfinite(values).all():
        raise ValueError("welfare effects contain nonfinite values")
    return 0.35 + 3.15 * np.sqrt(np.clip(np.abs(values) / maximum, 0, 1))


def welfare_legend_levels(maximum):
    exponent = 10 ** np.floor(np.log10(maximum))
    candidates = exponent * np.asarray((1, 2, 5, 10), dtype=float)
    top = float(candidates[candidates <= maximum][-1])
    return np.asarray((top/10, top/2, top), dtype=float)


def combined_road_transit_map(
        artifacts, nodes, masses, geography_root, gtfs_root=None):
    rail_rows = read_rows(Path(artifacts) / "links_rail.csv")
    rail_classes = (
        gtfs_rail_corridor_classes(gtfs_root, nodes)
        if gtfs_root is not None else {})
    rows = {
        mode: read_rows(Path(artifacts) / f"links_{mode}.csv")
        for mode in ("road", "bus", "ferry")
    }
    for category in ("subway", "streetcar", "rail"):
        rows[category] = []
    for row in rail_rows:
        categories = rail_classes.get(
            tuple(sorted((row["origin"], row["destination"]))), set())
        if "subway" in categories:
            category = "subway"
        elif "streetcar" in categories:
            category = "streetcar"
        else:
            category = "rail"
        rows[category].append(row)
    rows = {category: category_rows for category, category_rows in rows.items()
            if category_rows}
    values = {
        category: numeric(category_rows, "extended_gain_pct")
        for category, category_rows in rows.items()
    }
    maximum = max(float(np.max(np.abs(item))) for item in values.values())

    figure, axis = plt.subplots(figsize=(6.1, 6.7))
    add_geography(axis, geography_root)

    road_widths = welfare_widths(values["road"], maximum)
    axis.add_collection(LineCollection(
        corridor_segments(rows["road"], nodes),
        colors=COLORS["road"], linewidths=road_widths,
        alpha=0.64, zorder=2))

    transit_categories = [
        mode for mode in ("bus", "ferry", "streetcar", "rail", "subway")
        if mode in rows
    ]
    for layer, mode in enumerate(transit_categories):
        transit_segments = corridor_segments(rows[mode], nodes)
        transit_widths = welfare_widths(values[mode], maximum)
        axis.add_collection(LineCollection(
            transit_segments, colors="white",
            linewidths=transit_widths + 1.15,
            alpha=0.88, zorder=3 + 2*layer))
        for negative, linestyle in ((False, "solid"), (True, (0, (3, 2)))):
            indices = np.flatnonzero((values[mode] < 0) == negative)
            if len(indices) == 0:
                continue
            axis.add_collection(LineCollection(
                [transit_segments[index] for index in indices],
                colors=COLORS[mode], linewidths=transit_widths[indices],
                linestyles=linestyle, alpha=0.96,
                zorder=4 + 2*layer))

    add_nodes(axis, nodes, masses, alpha=0.56, zorder=10)
    finish_map(axis, nodes)

    category_handles = [
        Line2D([0], [0], color=COLORS[mode], linewidth=2.0,
               label=LABELS[mode])
        for mode in ("road", "bus", "subway", "streetcar", "rail", "ferry")
        if mode in rows
    ]
    if any(np.any(values[mode] < 0) for mode in transit_categories):
        category_handles.append(
            Line2D([0], [0], color="#202428", linewidth=2.0,
                   linestyle=(0, (3, 2)), label="Negative effect"))
    category_legend = axis.legend(
        handles=category_handles,
        loc="upper left", frameon=True, facecolor="white",
        edgecolor="none", framealpha=0.82, fontsize=7.2,
        handlelength=2.6)
    axis.add_artist(category_legend)

    levels = welfare_legend_levels(maximum)
    width_legend = [
        Line2D(
            [0], [0], color="#202428",
            linewidth=float(welfare_widths([level], maximum)[0]),
            label=f"{level:.3g}%")
        for level in levels
    ]
    axis.legend(
        handles=width_legend, loc="lower right", frameon=True,
        facecolor="white", edgecolor="none", framealpha=0.82,
        title="Extended welfare gain", fontsize=7.2, title_fontsize=7.2,
        handlelength=2.8)
    figure.subplots_adjust(left=0.01, right=0.99, bottom=0.01, top=0.99)
    return save_pair(
        figure, artifacts, "seattle_combined_road_transit_welfare")


def add_corridors(axis, rows, nodes, field, norm, cmap, geography_root):
    add_geography(axis, geography_root)
    segments = corridor_segments(rows, nodes)
    values = numeric(rows, field)
    collection = LineCollection(
        segments, array=values, cmap=cmap, norm=norm,
        linewidths=1.3, alpha=0.92, zorder=3,
    )
    axis.add_collection(collection)
    finish_map(axis, nodes)
    return collection


def aa_multimodal_network_map(artifacts, nodes, masses, geography_root,
                              edge_modes_path, gtfs_root, observed_roads):
    edge_rows = read_rows(edge_modes_path)
    raw_shapes = gtfs_shapes(gtfs_root)
    road_geometry = geojson_lines(observed_roads)
    figure, axes = plt.subplots(
        1, 2, figsize=(8.0, 5.1), sharex=True, sharey=True)

    add_geography(axes[0], geography_root)
    axes[0].add_collection(LineCollection(
        road_geometry, colors="#BEC3C6", linewidths=0.22,
        alpha=0.58, zorder=2))
    for mode in ("bus", "rail", "ferry"):
        axes[0].add_collection(LineCollection(
            raw_shapes[mode], colors=COLORS[mode],
            linewidths={"bus": 0.28, "rail": 1.05, "ferry": 1.15}[mode],
            alpha={"bus": 0.22, "rail": 0.82, "ferry": 0.88}[mode],
            linestyles="dashed" if mode == "ferry" else "solid",
            zorder=3))
    add_nodes(axes[0], nodes, masses, alpha=0.58)
    finish_map(axes[0], nodes)

    add_geography(axes[1], geography_root)
    for mode in ("road", "bus", "rail", "ferry"):
        segments, flows = unique_mode_segments(edge_rows, nodes, mode)
        if not segments:
            continue
        positive = np.log1p(flows)
        span = float(positive.max()-positive.min())
        widths = 0.32 + 1.45 * (
            (positive-positive.min())/span if span > 0 else
            np.ones_like(positive))
        axes[1].add_collection(LineCollection(
            segments, colors=COLORS[mode], linewidths=widths,
            alpha=0.68 if mode == "road" else 0.88, zorder=3))
    add_nodes(axes[1], nodes, masses)
    finish_map(axes[1], nodes)

    for axis, label in zip(
            axes, ("Observed 2017 networks", "Constructed multimodal network")):
        axis.text(
            0.02, 0.98, label, transform=axis.transAxes,
            ha="left", va="top", fontsize=8.5, fontweight="bold")
    legend = [
        Line2D([0], [0], color=COLORS[mode], linewidth=1.6,
               linestyle="dashed" if mode == "ferry" else "solid",
               label=LABELS[mode])
        for mode in ("road", "bus", "rail", "ferry")
    ]
    axes[1].legend(
        handles=legend, loc="lower right", frameon=False,
        fontsize=7, handlelength=2.5)
    figure.subplots_adjust(
        left=0.01, right=0.99, bottom=0.01, top=0.99, wspace=0.025)
    return save_pair(figure, artifacts, "seattle_aa_multimodal_network")


def aa_mode_welfare_map(artifacts, nodes, masses, geography_root,
                        edge_modes_path):
    modes = ("road", "bus", "rail", "ferry")
    rows = {
        mode: read_rows(Path(artifacts) / f"links_{mode}.csv")
        for mode in modes
    }
    values = np.concatenate([
        numeric(rows[mode], "extended_gain_pct") for mode in modes])
    norm = Normalize(vmin=min(0.0, float(values.min())),
                     vmax=float(values.max()))
    edge_rows = read_rows(edge_modes_path)
    figure, axes = plt.subplots(
        2, 2, figsize=(7.6, 8.4), sharex=True, sharey=True)
    collection = None
    for axis, mode in zip(axes.flat, modes):
        add_geography(axis, geography_root)
        add_road_context(axis, edge_rows, nodes)
        collection = LineCollection(
            corridor_segments(rows[mode], nodes),
            array=numeric(rows[mode], "extended_gain_pct"),
            cmap=AA_CMAP, norm=norm, linewidths=1.35,
            alpha=0.95, zorder=3)
        axis.add_collection(collection)
        add_nodes(axis, nodes, masses, alpha=0.68)
        finish_map(axis, nodes)
        axis.text(
            0.02, 0.98, LABELS[mode], transform=axis.transAxes,
            ha="left", va="top", fontsize=8.5, fontweight="bold")
    figure.colorbar(
        collection, ax=axes, fraction=0.025, pad=0.015,
        label="Welfare gain from a 1% improvement (%)")
    figure.subplots_adjust(
        left=0.01, right=0.90, bottom=0.01, top=0.99,
        wspace=0.025, hspace=0.025)
    return save_pair(figure, artifacts, "seattle_aa_mode_welfare")


def aa_transit_comparison_map(artifacts, nodes, masses, geography_root,
                              edge_modes_path):
    rows = read_rows(Path(artifacts) / "links_all_transit.csv")
    fields = ("traditional_gain_pct", "extended_gain_pct")
    values = np.concatenate([numeric(rows, field) for field in fields])
    norm = Normalize(vmin=min(0.0, float(values.min())),
                     vmax=float(values.max()))
    edge_rows = read_rows(edge_modes_path)
    figure, axes = plt.subplots(
        1, 2, figsize=(8.0, 5.1), sharex=True, sharey=True)
    collection = None
    for axis, field, label in zip(
            axes, fields, ("Traditional approach", "Extended approach")):
        add_geography(axis, geography_root)
        add_road_context(axis, edge_rows, nodes)
        collection = LineCollection(
            corridor_segments(rows, nodes), array=numeric(rows, field),
            cmap=AA_CMAP, norm=norm, linewidths=1.35,
            alpha=0.95, zorder=3)
        axis.add_collection(collection)
        add_nodes(axis, nodes, masses, alpha=0.68)
        finish_map(axis, nodes)
        axis.text(
            0.02, 0.98, label, transform=axis.transAxes,
            ha="left", va="top", fontsize=8.5, fontweight="bold")
    figure.colorbar(
        collection, ax=axes, fraction=0.03, pad=0.015,
        label="Welfare gain from a 1% transit improvement (%)")
    figure.subplots_adjust(
        left=0.01, right=0.90, bottom=0.01, top=0.99, wspace=0.025)
    return save_pair(
        figure, artifacts, "seattle_aa_transit_traditional_extended")


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


def build_figures(artifacts, nodes_path, geography_root=None, *,
                  edge_modes_path=None, gtfs_root=None,
                  observed_roads=None):
    artifacts = Path(artifacts)
    nodes = read_nodes(nodes_path)
    masses = read_node_mass(nodes_path)
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
    outputs.extend(combined_road_transit_map(
        artifacts, nodes, masses, geography_root, gtfs_root))
    outputs.extend(scatter_figure(artifacts))
    outputs.extend(route_figure(artifacts))
    outputs.extend(sensitivity_figure(artifacts))
    detailed = (edge_modes_path, gtfs_root, observed_roads)
    if any(item is not None for item in detailed):
        if not all(item is not None for item in detailed):
            raise ValueError(
                "AA-style figures require edge modes, GTFS, and observed roads")
        outputs.extend(aa_multimodal_network_map(
            artifacts, nodes, masses, geography_root,
            edge_modes_path, gtfs_root, observed_roads))
        outputs.extend(aa_mode_welfare_map(
            artifacts, nodes, masses, geography_root, edge_modes_path))
        outputs.extend(aa_transit_comparison_map(
            artifacts, nodes, masses, geography_root, edge_modes_path))
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--nodes", type=Path, required=True)
    parser.add_argument("--geography-root", type=Path)
    parser.add_argument("--edge-modes", type=Path)
    parser.add_argument("--gtfs-root", type=Path)
    parser.add_argument("--observed-roads", type=Path)
    args = parser.parse_args()
    build_figures(
        args.artifacts, args.nodes, args.geography_root,
        edge_modes_path=args.edge_modes, gtfs_root=args.gtfs_root,
        observed_roads=args.observed_roads)


if __name__ == "__main__":
    main()
