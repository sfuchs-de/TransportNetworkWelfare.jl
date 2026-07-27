#!/usr/bin/env python3
"""Build a synthetic economic-geography baseline on the Westeros road map."""

from __future__ import annotations

import argparse
import csv
import hashlib
import heapq
import json
import math
import shutil
import statistics
import urllib.request
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE_DEFINITIONS = {
    "locations": {
        "url": "https://services8.arcgis.com/bq7onQo4vkjSA8x6/arcgis/rest/services/GameofThronesMapDataLayers_WFL1/FeatureServer/0/query?where=1%3D1&outFields=*&returnGeometry=true&outSR=4326&f=geojson",
        "sha256": "2c5794dc82d1c497141c3e5ddd9864a717b167ca4d3d4a141cd3e64bdc4e3394",
        "features": 319,
    },
    "roads": {
        "url": "https://services8.arcgis.com/bq7onQo4vkjSA8x6/arcgis/rest/services/GameofThronesMapDataLayers_WFL1/FeatureServer/2/query?where=continent%3D%27Westeros%27&outFields=*&returnGeometry=true&outSR=4326&f=geojson",
        "sha256": "a7d732f9f0254513d8bb558c1c261a413bffb6bf5ca3b10921124936f5208720",
        "features": 169,
    },
    "continent": {
        "url": "https://services8.arcgis.com/bq7onQo4vkjSA8x6/arcgis/rest/services/GameofThronesMapDataLayers_WFL1/FeatureServer/7/query?where=name%3D%27Westeros%27&outFields=*&returnGeometry=true&outSR=4326&f=geojson",
        "sha256": "9b4f9be357d6ce76cc22c591121a763bdd34533563b06b6d94be9a0cac05d4f9",
        "features": 1,
    },
}

TYPE_WEIGHT = {
    "Great House": 12.0,
    "City": 10.0,
    "Town": 6.0,
    "Castle": 6.0,
    "Village": 4.0,
    "House": 3.0,
    "Inn": 2.0,
    "Tower": 2.0,
    "Stop": 1.5,
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def fetch_sources(cache_dir: Path, *, allow_download: bool = True) -> dict[str, Path]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    paths = {}
    for name, source in SOURCE_DEFINITIONS.items():
        path = cache_dir / f"{name}.geojson"
        if not path.exists():
            if not allow_download:
                raise RuntimeError(f"missing cached source: {path}")
            request = urllib.request.Request(
                source["url"], headers={"User-Agent": "TransportNetworkWelfare.jl/0.1"})
            with urllib.request.urlopen(request, timeout=60) as response, path.open("wb") as output:
                shutil.copyfileobj(response, output)
        observed = sha256_file(path)
        if observed != source["sha256"]:
            raise RuntimeError(
                f"{name} source hash mismatch: expected {source['sha256']}, got {observed}")
        payload = json.loads(path.read_text(encoding="utf-8"))
        if len(payload.get("features", [])) != source["features"]:
            raise RuntimeError(f"{name} feature count changed")
        paths[name] = path
    return paths


def point_in_ring(point, ring) -> bool:
    x, y = point
    inside = False
    for index in range(len(ring)):
        x1, y1 = ring[index - 1][:2]
        x2, y2 = ring[index][:2]
        if (y1 > y) != (y2 > y):
            crossing = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < crossing:
                inside = not inside
    return inside


def point_in_geometry(point, geometry) -> bool:
    kind = geometry["type"]
    if kind not in ("Polygon", "MultiPolygon"):
        raise ValueError("continent geometry must be Polygon or MultiPolygon")
    polygons = [geometry["coordinates"]] if kind == "Polygon" else geometry["coordinates"]
    return any(
        point_in_ring(point, polygon[0])
        and not any(point_in_ring(point, hole) for hole in polygon[1:])
        for polygon in polygons
    )


def geographic_distance_km(first, second) -> float:
    mean_latitude = math.radians((first[1] + second[1]) / 2)
    dx = (first[0] - second[0]) * math.cos(mean_latitude)
    dy = first[1] - second[1]
    return 111.32 * math.hypot(dx, dy)


def add_edge(adjacency, first, second, distance=None):
    if first == second:
        return
    weight = geographic_distance_km(first, second) if distance is None else distance
    previous = adjacency[first].get(second, math.inf)
    if weight < previous:
        adjacency[first][second] = weight
        adjacency[second][first] = weight


def road_graph(roads):
    adjacency = defaultdict(dict)
    for feature in roads["features"]:
        geometry = feature["geometry"]
        lines = [geometry["coordinates"]] if geometry["type"] == "LineString" else geometry["coordinates"]
        for line in lines:
            vertices = [(round(point[0], 6), round(point[1], 6)) for point in line]
            for first, second in zip(vertices, vertices[1:]):
                add_edge(adjacency, first, second)
    return adjacency


def connected_components(adjacency):
    unseen = set(adjacency)
    components = []
    while unseen:
        start = min(unseen)
        stack = [start]
        unseen.remove(start)
        component = []
        while stack:
            node = stack.pop()
            component.append(node)
            for neighbor in adjacency[node]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    stack.append(neighbor)
        components.append(component)
    return sorted(components, key=lambda values: (-len(values), min(values)))


def bridge_nearby_components(adjacency, maximum_km: float):
    bridges = []
    while True:
        components = connected_components(adjacency)
        if len(components) == 1:
            break
        main = components[0]
        best = None
        for component in components[1:]:
            candidate = min(
                (geographic_distance_km(first, second), first, second)
                for first in main for second in component)
            if best is None or candidate < best:
                best = candidate
        if best is None or best[0] > maximum_km:
            break
        distance, first, second = best
        add_edge(adjacency, first, second, distance)
        bridges.append((first, second, distance))
    return bridges


def dijkstra(adjacency, source):
    distances = {source: 0.0}
    predecessor = {}
    queue = [(0.0, source)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        for neighbor in sorted(adjacency[node]):
            candidate = distance + adjacency[node][neighbor]
            if candidate < distances.get(neighbor, math.inf) - 1e-12:
                distances[neighbor] = candidate
                predecessor[neighbor] = node
                heapq.heappush(queue, (candidate, neighbor))
    return distances, predecessor


def select_settlements(locations, continent, road_vertices, maximum_km: float):
    selected = []
    for feature in locations["features"]:
        properties = feature["properties"]
        kind = properties.get("type")
        name = properties.get("name")
        point = tuple(feature["geometry"]["coordinates"][:2])
        if kind not in TYPE_WEIGHT or not name or not point_in_geometry(point, continent):
            continue
        distance, attachment = min(
            (geographic_distance_km(point, vertex), vertex) for vertex in road_vertices)
        if distance <= maximum_km:
            selected.append({
                "object_id": int(properties["OBJECTID"]),
                "name": str(name),
                "type": kind,
                "point": point,
                "attachment": attachment,
                "attachment_km": distance,
            })
    selected.sort(key=lambda row: (row["name"], row["object_id"]))
    for row in selected:
        safe_name = "".join(
            character.lower() if character.isalnum() else "-" for character in row["name"])
        row["node_id"] = f"{safe_name.strip('-')}-{row['object_id']}"
    return selected


def settlement_distances(settlements, road_adjacency):
    matrix = [[0.0] * len(settlements) for _ in settlements]
    cache = {}
    for i, origin in enumerate(settlements):
        attachment = origin["attachment"]
        if attachment not in cache:
            cache[attachment] = dijkstra(road_adjacency, attachment)[0]
        distances = cache[attachment]
        for j, destination in enumerate(settlements):
            if i == j:
                continue
            matrix[i][j] = (
                origin["attachment_km"]
                + distances[destination["attachment"]]
                + destination["attachment_km"]
            )
    return matrix


def reduced_links(distance_matrix, nearest_neighbors: int):
    count = len(distance_matrix)
    links = set()
    for origin in range(count):
        nearest = sorted(
            (distance_matrix[origin][destination], destination)
            for destination in range(count) if destination != origin)
        for _, destination in nearest[:nearest_neighbors]:
            links.add(tuple(sorted((origin, destination))))

    reached = {0}
    while len(reached) < count:
        _, origin, destination = min(
            (distance_matrix[origin][destination], origin, destination)
            for origin in reached for destination in range(count) if destination not in reached)
        links.add(tuple(sorted((origin, destination))))
        reached.add(destination)
    return sorted(links)


def normalize(values):
    total = sum(values)
    return [value / total for value in values]


def trade_matrix(activity, distances, decay: float, local_weight: float):
    positive = [distances[i][j] for i in range(len(distances))
                for j in range(i + 1, len(distances))]
    scale = statistics.median(positive)
    kernel = [
        [local_weight if i == j else math.exp(-decay * distances[i][j] / scale)
         for j in range(len(distances))]
        for i in range(len(distances))
    ]
    column_scale = [1.0] * len(activity)
    for _ in range(10000):
        row_scale = [
            activity[i] / sum(kernel[i][j] * column_scale[j] for j in range(len(activity)))
            for i in range(len(activity))
        ]
        new_column_scale = [
            activity[j] / sum(row_scale[i] * kernel[i][j] for i in range(len(activity)))
            for j in range(len(activity))
        ]
        if max(abs(new_column_scale[j] - column_scale[j])
               for j in range(len(activity))) < 1e-13:
            column_scale = new_column_scale
            break
        column_scale = new_column_scale
    else:
        raise RuntimeError("trade balancing did not converge")
    matrix = [
        [row_scale[i] * kernel[i][j] * column_scale[j] for j in range(len(activity))]
        for i in range(len(activity))
    ]
    row_error = max(abs(sum(matrix[i]) - activity[i]) for i in range(len(activity)))
    column_error = max(abs(sum(matrix[i][j] for i in range(len(activity))) - activity[j])
                       for j in range(len(activity)))
    symmetry_error = max(
        abs(matrix[i][j] - matrix[j][i])
        for i in range(len(activity)) for j in range(len(activity))
    )
    if max(row_error, column_error) > 1e-10:
        raise RuntimeError("trade margins failed")
    if symmetry_error > 1e-10:
        raise RuntimeError("balanced bilateral trade is not symmetric")
    return matrix, max(row_error, column_error), symmetry_error, scale


def route_trade(trade, links, distances):
    adjacency = defaultdict(dict)
    for first, second in links:
        add_edge(adjacency, first, second, distances[first][second])
    traffic = defaultdict(float)
    for origin in range(len(trade)):
        _, predecessor = dijkstra(adjacency, origin)
        for destination in range(origin + 1, len(trade)):
            flow = 0.5 * (trade[origin][destination] + trade[destination][origin])
            if flow == 0:
                continue
            node = destination
            while node != origin:
                prior = predecessor[node]
                traffic[(prior, node)] += flow
                traffic[(node, prior)] += flow
                node = prior
    active_links = [link for link in links
                    if traffic[(link[0], link[1])] > 0 or traffic[(link[1], link[0])] > 0]
    return traffic, active_links


def corridor_geometries(settlements, links, road_adjacency):
    geometries = []
    cache = {}
    for first, second in links:
        origin = settlements[first]
        destination = settlements[second]
        source = origin["attachment"]
        target = destination["attachment"]
        if source not in cache:
            cache[source] = dijkstra(road_adjacency, source)[1]
        predecessor = cache[source]
        path = [target]
        while path[-1] != source:
            path.append(predecessor[path[-1]])
        path.reverse()
        coordinates = [origin["point"]]
        coordinates.extend(path)
        coordinates.append(destination["point"])
        geometries.append(coordinates)
    return geometries


def write_project(output_dir: Path, settlements, activity, traffic, links,
                  geometries, summary):
    data_dir = output_dir / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    with (data_dir / "nodes.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["node_id", "labor", "income", "longitude", "latitude",
                         "name", "location_type"])
        for row, share in zip(settlements, activity):
            writer.writerow([row["node_id"], f"{share:.17g}", f"{share:.17g}",
                             row["point"][0], row["point"][1], row["name"], row["type"]])
    with (data_dir / "edge_modes.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["edge_id", "physical_link_id", "origin", "destination", "mode",
                         "flow", "origin_name", "destination_name"])
        for index, (first, second) in enumerate(links, start=1):
            physical = f"westeros-{index:04d}"
            for origin, destination in ((first, second), (second, first)):
                writer.writerow([
                    f"{physical}-{origin}-{destination}", physical,
                    settlements[origin]["node_id"], settlements[destination]["node_id"],
                    "road", f"{traffic[(origin, destination)]:.17g}",
                    settlements[origin]["name"], settlements[destination]["name"],
                ])
    features = []
    for index, ((first, second), coordinates) in enumerate(zip(links, geometries), start=1):
        features.append({
            "type": "Feature",
            "properties": {
                "physical_link_id": f"westeros-{index:04d}",
                "origin_name": settlements[first]["name"],
                "destination_name": settlements[second]["name"],
            },
            "geometry": {"type": "LineString", "coordinates": coordinates},
        })
    (output_dir / "link_geometry.geojson").write_text(
        json.dumps({"type": "FeatureCollection", "features": features},
                   separators=(",", ":")) + "\n",
        encoding="utf-8")
    shutil.copyfile(ROOT / "config.template.toml", output_dir / "config.toml")
    (output_dir / "network_summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def build(paths, output_dir: Path, *, component_snap_km: float = 10.0,
          settlement_road_km: float = 50.0, nearest_neighbors: int = 3,
          gravity_decay: float = 3.0, local_weight: float = 3.0):
    sources = {name: json.loads(path.read_text(encoding="utf-8"))
               for name, path in paths.items()}
    continent_feature = sources["continent"]["features"][0]
    adjacency = road_graph(sources["roads"])
    initial_components = len(connected_components(adjacency))
    bridges = bridge_nearby_components(adjacency, component_snap_km)
    components = connected_components(adjacency)
    main_vertices = set(components[0])
    main_adjacency = defaultdict(dict)
    for vertex in main_vertices:
        for neighbor, distance in adjacency[vertex].items():
            if neighbor in main_vertices:
                main_adjacency[vertex][neighbor] = distance
    settlements = select_settlements(
        sources["locations"], continent_feature["geometry"], main_vertices,
        settlement_road_km)
    if len(settlements) < 3:
        raise RuntimeError("fewer than three settlements survived selection")
    distances = settlement_distances(settlements, main_adjacency)
    links = reduced_links(distances, nearest_neighbors)
    activity = normalize([TYPE_WEIGHT[row["type"]] for row in settlements])
    trade, trade_margin_error, trade_symmetry_error, distance_scale = trade_matrix(
        activity, distances, gravity_decay, local_weight)
    traffic, active_links = route_trade(trade, links, distances)
    geometries = corridor_geometries(settlements, active_links, main_adjacency)

    outgoing = [0.0] * len(settlements)
    incoming = [0.0] * len(settlements)
    for (origin, destination), flow in traffic.items():
        outgoing[origin] += flow
        incoming[destination] += flow
    conservation_error = max(
        abs(outgoing[i] - incoming[i]) for i in range(len(settlements)))
    if conservation_error > 1e-10:
        raise RuntimeError("routed trade violates flow conservation")
    openness = [
        (activity[i] - trade[i][i]) / activity[i]
        for i in range(len(settlements))
    ]

    summary = {
        "status": "synthetic_calibration",
        "spatial_specification": "economic_geography",
        "source_hashes": {name: sha256_file(path) for name, path in paths.items()},
        "source_feature_counts": {name: len(sources[name]["features"]) for name in sources},
        "initial_road_components": initial_components,
        "retained_road_components": 1,
        "retained_road_vertices": len(main_vertices),
        "component_bridges": [
            {"origin": first, "destination": second, "distance_km": distance}
            for first, second, distance in bridges],
        "occupied_settlements": len(settlements),
        "candidate_links": len(links),
        "active_physical_links": len(active_links),
        "directed_arcs": 2 * len(active_links),
        "maximum_settlement_attachment_km": max(row["attachment_km"] for row in settlements),
        "trade_margin_error": trade_margin_error,
        "trade_symmetry_error": trade_symmetry_error,
        "flow_conservation_error": conservation_error,
        "trade_distance_scale_km": distance_scale,
        "minimum_trade_openness": min(openness),
        "maximum_trade_openness": max(openness),
        "assumptions": {
            "component_snap_km": component_snap_km,
            "settlement_road_km": settlement_road_km,
            "nearest_neighbors": nearest_neighbors,
            "gravity_decay": gravity_decay,
            "local_trade_weight": local_weight,
            "labor_and_income": "common normalized location-type weight",
            "trade": "symmetric doubly constrained gravity values routed over the reduced road graph",
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    write_project(
        output_dir, settlements, activity, traffic, active_links,
        geometries, summary)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "generated")
    parser.add_argument("--cache", type=Path, default=ROOT / "generated" / "source_cache")
    parser.add_argument("--no-download", action="store_true")
    parser.add_argument("--component-snap-km", type=float, default=10.0)
    parser.add_argument("--settlement-road-km", type=float, default=50.0)
    parser.add_argument("--nearest-neighbors", type=int, default=3)
    parser.add_argument("--gravity-decay", type=float, default=3.0)
    parser.add_argument("--local-weight", type=float, default=3.0)
    arguments = parser.parse_args()
    paths = fetch_sources(arguments.cache, allow_download=not arguments.no_download)
    summary = build(
        paths, arguments.output,
        component_snap_km=arguments.component_snap_km,
        settlement_road_km=arguments.settlement_road_km,
        nearest_neighbors=arguments.nearest_neighbors,
        gravity_decay=arguments.gravity_decay,
        local_weight=arguments.local_weight,
    )
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
