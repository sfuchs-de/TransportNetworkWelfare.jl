#!/usr/bin/env python3

import argparse
import csv
import hashlib
import json
import shutil
import subprocess
import urllib.request
from pathlib import Path


CBSA_URL = "https://www2.census.gov/geo/tiger/TIGER2018/CBSA/tl_2018_us_cbsa.zip"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def point_in_ring(longitude, latitude, ring):
    inside = False
    previous = ring[-1]
    for current in ring:
        x1, y1 = previous[:2]
        x2, y2 = current[:2]
        if (y1 > latitude) != (y2 > latitude):
            crossing = (x2-x1)*(latitude-y1)/(y2-y1)+x1
            if longitude < crossing:
                inside = not inside
        previous = current
    return inside


def point_in_polygon(longitude, latitude, polygon):
    if not polygon or not point_in_ring(longitude, latitude, polygon[0]):
        return False
    return not any(point_in_ring(longitude, latitude, hole) for hole in polygon[1:])


def geometry_contains(geometry, longitude, latitude):
    if geometry["type"] == "Polygon":
        return point_in_polygon(longitude, latitude, geometry["coordinates"])
    if geometry["type"] == "MultiPolygon":
        return any(
            point_in_polygon(longitude, latitude, polygon)
            for polygon in geometry["coordinates"]
        )
    return False


def geometry_bounds(geometry):
    polygons = (
        [geometry["coordinates"]]
        if geometry["type"] == "Polygon"
        else geometry["coordinates"]
    )
    points = [point for polygon in polygons for ring in polygon for point in ring]
    longitude = [point[0] for point in points]
    latitude = [point[1] for point in points]
    return min(longitude), min(latitude), max(longitude), max(latitude)


def cbsa_features(cache_dir: Path):
    cache_dir.mkdir(parents=True, exist_ok=True)
    archive = cache_dir / "tl_2018_us_cbsa.zip"
    geojson = cache_dir / "tl_2018_us_cbsa.geojson"
    if not archive.exists():
        urllib.request.urlretrieve(CBSA_URL, archive)
    if not geojson.exists():
        executable = shutil.which("ogr2ogr")
        if executable is None:
            raise RuntimeError("ogr2ogr is required to build the CBSA crosswalk")
        subprocess.run(
            [executable, "-f", "GeoJSON", str(geojson), f"/vsizip/{archive}"],
            check=True,
        )
    with geojson.open() as handle:
        collection = json.load(handle)
    features = []
    for feature in collection["features"]:
        geometry = feature["geometry"]
        features.append((
            geometry_bounds(geometry), geometry,
            str(feature["properties"]["GEOID"]),
            str(feature["properties"]["NAME"]),
        ))
    return features, archive


def assign(features, longitude, latitude):
    for (min_x, min_y, max_x, max_y), geometry, geoid, name in features:
        if min_x <= longitude <= max_x and min_y <= latitude <= max_y and \
           geometry_contains(geometry, longitude, latitude):
            return geoid, name
    return "", ""


def link_label(name_a, name_b):
    if name_a and name_b and name_a != name_b:
        return f"{name_a}--{name_b}"
    if name_a and name_b:
        return name_a
    if name_a:
        return f"Approach to {name_a}"
    if name_b:
        return f"Approach to {name_b}"
    return ""


def compact_cbsa_name(name):
    if not name:
        return ""
    return name.split(",", 1)[0].split("-", 1)[0]


def compact_link_label(name_a, name_b):
    return link_label(compact_cbsa_name(name_a), compact_cbsa_name(name_b))


def tex_escape(value):
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    return "".join(replacements.get(character, character) for character in str(value))


def write_top_link_outputs(comparison, label_rows, csv_path, tex_path):
    labels = {row["physical_link_id"]: row for row in label_rows}
    output_rows = []
    for ranking_measure in ("traditional", "extended"):
        for link in comparison[ranking_measure]:
            label_row = labels.get(link["physical_link_id"], {})
            verified_label = label_row.get("verified_label", "")
            display_label = compact_link_label(
                label_row.get("cbsa_name_a", ""), label_row.get("cbsa_name_b", ""))
            link["verified_label"] = verified_label or None
            link["display_label"] = display_label or None
            link["label_status"] = (
                "verified_point_in_polygon" if verified_label else "unavailable")
            output_rows.append({
                "ranking_measure": ranking_measure,
                "rank": link["rank"],
                "physical_link_id": link["physical_link_id"],
                "display_label": display_label,
                "verified_label": verified_label,
                "traditional_rank": link["traditional_rank"],
                "extended_rank": link["extended_rank"],
                "hulten_elasticity": link["hulten_elasticity"],
                "primitive_elasticity": link["primitive_elasticity"],
            })

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(output_rows[0]))
        writer.writeheader()
        writer.writerows(output_rows)

    lines = [
        "% Generated by replication/rsue/build_cbsa_crosswalk.py; do not edit.",
        r"\begin{revblock}",
        r"\begin{table}[p]",
        r"\color{revcol}",
        r"\centering",
        r"\caption{\rev{Top-ranked physical road links under the traditional and extended statistics}}",
        r"\label{tab:rsue_top_links}",
        r"\scriptsize",
        r"\setlength{\tabcolsep}{3.5pt}",
        r"\begin{tabularx}{\textwidth}{@{}r>{\raggedright\arraybackslash}Xrrr@{}}",
        r"\toprule",
        "Rank & Physical road link & Elasticity & Other rank & Other elasticity \\\\",
        " & & $\\times 10^{-4}$ & & $\\times 10^{-4}$ \\\\",
        r"\midrule",
        "\\multicolumn{5}{@{}l}{\\textit{Panel A. Ranked by the traditional traffic statistic}} \\\\",
    ]
    for row in output_rows[:comparison["count_per_measure"]]:
        lines.append(
            f'{row["rank"]} & {tex_escape(row["display_label"] or row["physical_link_id"])} & '
            f'{1.0e4*float(row["hulten_elasticity"]):.3f} & '
            f'{row["extended_rank"]} & '
            f'{1.0e4*float(row["primitive_elasticity"]):.3f} \\\\')
    lines.extend([
        r"\addlinespace[4pt]",
        "\\multicolumn{5}{@{}l}{\\textit{Panel B. Ranked by the extended welfare statistic}} \\\\",
    ])
    for row in output_rows[comparison["count_per_measure"]:]:
        lines.append(
            f'{row["rank"]} & {tex_escape(row["display_label"] or row["physical_link_id"])} & '
            f'{1.0e4*float(row["primitive_elasticity"]):.3f} & '
            f'{row["traditional_rank"]} & '
            f'{1.0e4*float(row["hulten_elasticity"]):.3f} \\\\')
    lines.extend([
        r"\bottomrule",
        r"\end{tabularx}",
        r"\smallskip",
        r"\begin{minipage}{0.97\textwidth}",
        r"\footnotesize \textbf{Notes:} The policy unit is a simultaneous one-percent primitive-cost reduction in both directions of a physical road link. Panel A ranks links by the sum of the two directed traffic shares. Panel B ranks them by the corresponding extended primitive-cost welfare elasticity. ``Other rank'' gives the link's rank under the other statistic. Metropolitan labels are assigned by point-in-polygon using the public 2018 Census CBSA crosswalk and shortened to the first principal city in each CBSA name. Elasticities are multiplied by $10^4$.",
        r"\end{minipage}",
        r"\end{table}",
        r"\end{revblock}",
    ])
    tex_path.parent.mkdir(parents=True, exist_ok=True)
    tex_path.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("geometry", type=Path)
    parser.add_argument("claims", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cache-dir", type=Path, required=True)
    parser.add_argument("--top-links-csv", type=Path)
    parser.add_argument("--top-links-tex", type=Path)
    args = parser.parse_args()
    features, archive = cbsa_features(args.cache_dir)
    with args.geometry.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    output_rows = []
    labels = {}
    for row in rows:
        geoid_a, name_a = assign(
            features, float(row["longitude_a"]), float(row["latitude_a"]))
        geoid_b, name_b = assign(
            features, float(row["longitude_b"]), float(row["latitude_b"]))
        label = link_label(name_a, name_b)
        output_rows.append({
            "physical_link_id": row["physical_link_id"],
            "endpoint_a": row["endpoint_a"],
            "endpoint_b": row["endpoint_b"],
            "cbsa_geoid_a": geoid_a,
            "cbsa_name_a": name_a,
            "cbsa_geoid_b": geoid_b,
            "cbsa_name_b": name_b,
            "verified_label": label,
        })
        labels[row["physical_link_id"]] = label
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(output_rows[0]))
        writer.writeheader()
        writer.writerows(output_rows)
    with args.claims.open() as handle:
        claims = json.load(handle)
    for link in claims["top_links"]:
        label = labels.get(link["physical_link_id"], "")
        link["verified_label"] = label or None
        link["label_status"] = "verified_point_in_polygon" if label else "unavailable"
    comparison = claims.get("top_link_comparison")
    if comparison is not None:
        if args.top_links_csv is None or args.top_links_tex is None:
            raise ValueError(
                "--top-links-csv and --top-links-tex are required when claims include "
                "top_link_comparison")
        write_top_link_outputs(
            comparison, output_rows, args.top_links_csv, args.top_links_tex)
    claims["cbsa_crosswalk"] = {
        "source_url": CBSA_URL,
        "source_sha256": sha256(archive),
        "vintage": 2018,
        "assignment": "point_in_polygon_only",
        "labeled_physical_links": sum(bool(value) for value in labels.values()),
    }
    with args.claims.open("w") as handle:
        json.dump(claims, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")


if __name__ == "__main__":
    main()
