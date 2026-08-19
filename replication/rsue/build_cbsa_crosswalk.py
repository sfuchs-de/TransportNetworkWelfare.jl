#!/usr/bin/env python3

import argparse
import csv
import hashlib
import json
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path


CBSA_URL = "https://www2.census.gov/geo/tiger/TIGER2018/CBSA/tl_2018_us_cbsa.zip"
CBSA_SHA256 = "810b5a1d81a4c0e4bbea65c721ad7c42c578a4034d44049b783e253e0686d086"
PLACE_ARCHIVES = {
    "37": {
        "url": "https://www2.census.gov/geo/tiger/TIGER2018/PLACE/tl_2018_37_place.zip",
        "sha256": "6b9d69052ba684c4480b70aec425466d39e455601b06d3ad69b50acb4dc47e52",
    },
    "53": {
        "url": "https://www2.census.gov/geo/tiger/TIGER2018/PLACE/tl_2018_53_place.zip",
        "sha256": "3a552792edbf7333eaab902f676d1bc42c0d8a6bddb4fae41df5a7978d9916fe",
    },
}


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
    actual_hash = sha256(archive)
    if actual_hash != CBSA_SHA256:
        raise RuntimeError(
            f"Census CBSA archive hash mismatch: expected {CBSA_SHA256}, got {actual_hash}")
    executable = shutil.which("ogr2ogr")
    if not geojson.exists():
        if executable is None:
            raise RuntimeError(
                "ogr2ogr is required to build the CBSA crosswalk; install GDAL or provide "
                "the hash-verified cached GeoJSON")
        subprocess.run(
            [executable, "-f", "GeoJSON", str(geojson), f"/vsizip/{archive}"],
            check=True,
        )
    gdal_version = "not_available_cached_geojson"
    if executable is not None:
        gdal_version = subprocess.run(
            [executable, "--version"], check=True, capture_output=True, text=True,
        ).stdout.strip()
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
    return features, archive, geojson, gdal_version


def place_features(cache_dir: Path):
    executable = shutil.which("ogr2ogr")
    features = []
    sources = {}
    for state_fips, source in sorted(PLACE_ARCHIVES.items()):
        archive = cache_dir / f"tl_2018_{state_fips}_place.zip"
        geojson = cache_dir / f"tl_2018_{state_fips}_place.geojson"
        if not archive.exists():
            urllib.request.urlretrieve(source["url"], archive)
        actual_hash = sha256(archive)
        if actual_hash != source["sha256"]:
            raise RuntimeError(
                "Census Place archive hash mismatch for state "
                f"{state_fips}: expected {source['sha256']}, got {actual_hash}")
        if not geojson.exists():
            if executable is None:
                raise RuntimeError(
                    "ogr2ogr is required to build the Census Place crosswalk; "
                    "install GDAL or provide the hash-verified cached GeoJSON")
            subprocess.run(
                [executable, "-f", "GeoJSON", str(geojson),
                 f"/vsizip/{archive}"],
                check=True,
            )
        with geojson.open() as handle:
            collection = json.load(handle)
        for feature in collection["features"]:
            geometry = feature["geometry"]
            features.append((
                geometry_bounds(geometry), geometry,
                str(feature["properties"]["GEOID"]),
                str(feature["properties"]["NAME"]),
            ))
        sources[state_fips] = {
            "source_url": source["url"],
            "source_sha256": actual_hash,
            "geojson_sha256": sha256(geojson),
        }
    return features, sources


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
        return f"Within {compact_cbsa_name(name_a)} metropolitan area"
    if name_a:
        return f"{compact_cbsa_name(name_a)} metropolitan area--network boundary"
    if name_b:
        return f"{compact_cbsa_name(name_b)} metropolitan area--network boundary"
    return ""


def descriptive_link_label(
        name_a, name_b, place_a, place_b, physical_link_id):
    if name_a and name_b and name_a != name_b:
        return f"{name_a}--{name_b}", "cbsa_endpoint_pair"
    if place_a and place_b and place_a != place_b:
        return f"{place_a}--{place_b}", "place_endpoint_pair"
    if name_a and name_b:
        return (
            f"Within {compact_cbsa_name(name_a)} metropolitan area "
            f"(link {physical_link_id})",
            "same_cbsa_physical_link",
        )
    if name_a or name_b:
        name = compact_cbsa_name(name_a or name_b)
        return (
            f"{name} metropolitan area--network boundary "
            f"(link {physical_link_id})",
            "one_sided_cbsa_physical_link",
        )
    if place_a or place_b:
        return (
            f"{place_a or place_b} area (link {physical_link_id})",
            "one_sided_place_physical_link",
        )
    return f"Physical link {physical_link_id}", "physical_link_id"


def compact_cbsa_name(name):
    if not name:
        return ""
    return name.split(",", 1)[0]


def compact_link_label(
        name_a, name_b, place_a="", place_b="", physical_link_id=""):
    label, _ = descriptive_link_label(
        compact_cbsa_name(name_a), compact_cbsa_name(name_b),
        place_a, place_b, physical_link_id)
    return label


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


def ranked_link_rows(comparison, label_rows):
    labels = {row["physical_link_id"]: row for row in label_rows}
    output = {"traditional": [], "extended": []}
    for ranking_measure in ("traditional", "extended"):
        for link in comparison[ranking_measure]:
            label_row = labels.get(link["physical_link_id"], {})
            verified_label = label_row.get("verified_label", "")
            display_label = compact_link_label(
                label_row.get("cbsa_name_a", ""),
                label_row.get("cbsa_name_b", ""),
                label_row.get("place_name_a", ""),
                label_row.get("place_name_b", ""),
                link["physical_link_id"],
            )
            link["verified_label"] = verified_label or None
            link["display_label"] = display_label or None
            link["label_status"] = label_row.get(
                "label_status", "unavailable")
            output[ranking_measure].append({
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
    return output


def write_top_link_outputs(
        comparison, label_rows, csv_path, tex_path, *,
        table_label, caption, layout):
    ranked = ranked_link_rows(comparison, label_rows)
    output_rows = ranked["traditional"]+ranked["extended"]

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(output_rows[0]))
        writer.writeheader()
        writer.writerows(output_rows)

    lines = [
        "% Generated by replication/rsue/build_cbsa_crosswalk.py; do not edit.",
        r"\begin{revblock}",
    ]
    if layout == "stacked":
        lines.extend([
            r"\begin{table}[p]",
            r"\color{revcol}",
            r"\centering",
            rf"\caption{{\rev{{{caption}}}}}",
            rf"\label{{{table_label}}}",
            r"\scriptsize",
            r"\setlength{\tabcolsep}{3.5pt}",
            r"\begin{tabularx}{\textwidth}{@{}r>{\raggedright\arraybackslash}Xrrr@{}}",
            r"\toprule",
            "Rank & Physical road link & Elasticity & Other rank & Other elasticity \\\\",
            " & & $\\times 10^{-4}$ & & $\\times 10^{-4}$ \\\\",
            r"\midrule",
            "\\multicolumn{5}{@{}l}{\\textit{Panel A. Ranked by the Traditional approach}} \\\\",
        ])
        for row in ranked["traditional"]:
            lines.append(
                f'{row["rank"]} & {tex_escape(row["display_label"] or row["physical_link_id"])} & '
                f'{1.0e4*float(row["hulten_elasticity"]):.3f} & '
                f'{row["extended_rank"]} & '
                f'{1.0e4*float(row["primitive_elasticity"]):.3f} \\\\')
        lines.extend([
            r"\addlinespace[4pt]",
            "\\multicolumn{5}{@{}l}{\\textit{Panel B. Ranked by the Extended approach}} \\\\",
        ])
        for row in ranked["extended"]:
            lines.append(
                f'{row["rank"]} & {tex_escape(row["display_label"] or row["physical_link_id"])} & '
                f'{1.0e4*float(row["primitive_elasticity"]):.3f} & '
                f'{row["traditional_rank"]} & '
                f'{1.0e4*float(row["hulten_elasticity"]):.3f} \\\\')
        lines.append(r"\bottomrule")
        lines.append(r"\end{tabularx}")
    elif layout == "side_by_side":
        lines.extend([
            r"\begin{center}",
            rf"\captionof{{table}}{{\rev{{{caption}}}}}",
            rf"\label{{{table_label}}}",
            r"\fontsize{6.7}{7.2}\selectfont",
            r"\setlength{\tabcolsep}{2.0pt}",
            r"\renewcommand{\arraystretch}{0.88}",
            r"\begin{tabularx}{\linewidth}{@{}r>{\raggedright\arraybackslash}Xrr@{\hspace{8pt}}r>{\raggedright\arraybackslash}Xrr@{}}",
            r"\toprule",
            r"\multicolumn{4}{c}{\textit{Traditional approach}} & \multicolumn{4}{c}{\textit{Extended approach}} \\",
            r"\cmidrule(lr){1-4}\cmidrule(lr){5-8}",
            r"Rank & Physical road link & Elasticity & Ext. rank & Rank & Physical road link & Elasticity & Trad. rank \\",
            r" & & $\times 10^{-4}$ & & & & $\times 10^{-4}$ & \\",
            r"\midrule",
        ])
        for traditional, extended in zip(
                ranked["traditional"], ranked["extended"]):
            lines.append(
                f'{traditional["rank"]} & '
                f'{tex_escape(traditional["display_label"] or traditional["physical_link_id"])} & '
                f'{1.0e4*float(traditional["hulten_elasticity"]):.3f} & '
                f'{traditional["extended_rank"]} & '
                f'{extended["rank"]} & '
                f'{tex_escape(extended["display_label"] or extended["physical_link_id"])} & '
                f'{1.0e4*float(extended["primitive_elasticity"]):.3f} & '
                f'{extended["traditional_rank"]} \\\\')
        lines.extend([r"\bottomrule", r"\end{tabularx}"])
    else:
        raise ValueError(f"unknown top-link table layout: {layout}")
    lines.extend([
        r"\smallskip" if layout == "stacked" else r"\vspace{1pt}",
        r"\begin{minipage}{0.97\textwidth}",
        (r"\footnotesize " if layout == "stacked"
         else r"\fontsize{6.0}{6.6}\selectfont ")
        + r"\textbf{Notes:} The policy unit is a simultaneous one-percent primitive-cost reduction in both directions of a physical road link. The Traditional approach ranks links by the sum of the two directed traffic shares; the Extended approach ranks them by the corresponding primitive-cost welfare elasticity. The cross-rank gives the link's rank under the other approach. Geographic labels use point-in-polygon assignments from public 2018 Census CBSA and Place polygons. When the endpoints do not identify two places, the table reports the metropolitan area and physical-link identifier. State suffixes are omitted; hyphenated Census place names are retained. Elasticities are multiplied by $10^4$.",
        r"\end{minipage}",
    ])
    lines.append(r"\end{table}" if layout == "stacked" else r"\end{center}")
    lines.append(r"\end{revblock}")
    tex_path.parent.mkdir(parents=True, exist_ok=True)
    tex_path.write_text("\n".join(lines) + "\n")


def write_mechanism_link_outputs(mechanisms, label_rows, csv_path, tex_path):
    labels = {row["physical_link_id"]: row for row in label_rows}
    output_rows = []
    for mechanism in mechanisms:
        label_row = labels.get(mechanism["physical_link_id"], {})
        output_rows.append({
            **mechanism,
            "display_label": mechanism.get("display_label") or compact_link_label(
                label_row.get("cbsa_name_a", ""),
                label_row.get("cbsa_name_b", ""),
                label_row.get("place_name_a", ""),
                label_row.get("place_name_b", ""),
                mechanism["physical_link_id"],
            ),
            "verified_label": label_row.get("verified_label", ""),
        })
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = list(output_rows[0])
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(output_rows)

    lines = [
        "% Generated by replication/rsue/build_cbsa_crosswalk.py; do not edit.",
        r"\begin{revblock}",
        r"\begin{table}[htbp]",
        r"\color{revcol}",
        r"\centering",
        r"\caption{\rev{Why selected link rankings differ}}",
        r"\label{tab:rsue_mechanism_links}",
        r"\small",
        r"\setlength{\tabcolsep}{3.5pt}",
        r"\begin{tabularx}{\textwidth}{@{}>{\raggedright\arraybackslash}Xrrrrr@{}}",
        r"\toprule",
        r"Physical road link & \shortstack{Traditional\\gain (bp)} & "
        r"\shortstack{Cost\\transmission} & \shortstack{Market-access\\multiplier} & "
        r"\shortstack{Extended/\\traditional} & \shortstack{Ranks\\trad.$\to$ext.} \\",
        r" & & $\chi_e$ & $\rho m_{e,F}$ & & \\",
        r"\midrule",
    ]
    for row in output_rows:
        rank_gain = int(row["rank_gain"])
        rank_suffix = f"{rank_gain:+d}"
        lines.append(
            f'{tex_escape(row["display_label"] or row["physical_link_id"])} & '
            f'{float(row["traditional_gain_basis_points"]):.4f} & '
            f'{float(row["cost_transmission"]):.3f} & '
            f'{float(row["equilibrium_multiplier"]):.3f} & '
            f'{float(row["extended_to_traditional_ratio"]):.3f} & '
            f'{int(row["traditional_rank"])}$\\to${int(row["extended_rank"])} '
            f'({rank_suffix}) \\\\')
    lines.extend([
        r"\bottomrule",
        r"\end{tabularx}",
        r"\smallskip",
        r"\begin{minipage}{0.97\textwidth}",
        r"\footnotesize \textbf{Notes:} The traditional gain is the welfare gain, in basis points, from the paper's one-percent bidirectional improvement. Cost transmission is the effective ratio between the primitive-cost and realized-cost derivatives. The combined market-access multiplier includes the common externality scale $\rho$ and the two endpoint terms. The displayed ratio satisfies $E_e^{\mathrm{ext}}/E_e^{\mathrm{trad}}=\chi_e\rho m_{e,F}$. A positive rank change means that the link ranks higher under the Extended approach. Geographic labels use the public 2018 Census crosswalk.",
        r"\end{minipage}",
        r"\end{table}",
        r"\end{revblock}",
    ])
    tex_path.parent.mkdir(parents=True, exist_ok=True)
    tex_path.write_text("\n".join(lines) + "\n")


def write_rank_distribution_outputs(distribution, csv_path, tex_path):
    rows = distribution["deciles"]
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    overlaps = ", ".join(
        f'{int(row["overlap_count"])}/{int(row["k"])} at $k={int(row["k"])}$'
        for row in distribution["top_k_overlap"])
    lines = [
        "% Generated by replication/rsue/build_cbsa_crosswalk.py; do not edit.",
        r"\begin{revblock}",
        r"\begin{table}[htbp]",
        r"\color{revcol}",
        r"\centering",
        r"\caption{\rev{Rank changes and benefit ratios by traditional-traffic decile}}",
        r"\label{tab:rsue_rank_distribution}",
        r"\small",
        r"\setlength{\tabcolsep}{5pt}",
        r"\begin{tabular}{@{}rrrrr@{}}",
        r"\toprule",
        r"\shortstack{Traditional-traffic\\decile} & Links & "
        r"\shortstack{Mean absolute\\rank change} & "
        r"\shortstack{Median extended/\\traditional ratio} & "
        r"\shortstack{Interquartile range\\of the ratio} \\",
        r"\midrule",
    ]
    for row in rows:
        lines.append(
            f'{int(row["traditional_traffic_decile"])} & {int(row["count"])} & '
            f'{float(row["mean_absolute_rank_change"]):.1f} & '
            f'{float(row["median_extended_to_traditional_ratio"]):.3f} & '
            f'[{float(row["p25_extended_to_traditional_ratio"]):.3f}, '
            f'{float(row["p75_extended_to_traditional_ratio"]):.3f}] \\\\')
    lines.extend([
        r"\bottomrule",
        r"\end{tabular}",
        r"\smallskip",
        r"\begin{minipage}{0.94\textwidth}",
        r"\footnotesize \textbf{Notes:} Decile 1 contains the links with the lowest traditional traffic statistic and decile 10 the links with the highest. Links are sorted by that statistic and divided into equal-count groups, with the physical-link identifier breaking ties. Rank change is the absolute difference between a link's ranks under the two approaches. The ratio compares the Extended welfare elasticity with the Traditional traffic statistic. The top-$k$ overlaps are " + overlaps + ". Unlike correlations calculated within a selected traffic range, these columns measure ranking and proportional differences directly.",
        r"\end{minipage}",
        r"\end{table}",
        r"\end{revblock}",
    ])
    tex_path.parent.mkdir(parents=True, exist_ok=True)
    tex_path.write_text("\n".join(lines) + "\n")

def label_sensitivity_links(path, label_rows):
    labels = {row["physical_link_id"]: row for row in label_rows}
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError("sensitivity-link output is empty")
    output = []
    for row in rows:
        label_row = labels.get(row["physical_link_id"], {})
        output.append({
            **row,
            "display_label": compact_link_label(
                label_row.get("cbsa_name_a", ""),
                label_row.get("cbsa_name_b", ""),
                label_row.get("place_name_a", ""),
                label_row.get("place_name_b", ""),
                row["physical_link_id"],
            ),
            "verified_label": label_row.get("verified_label", ""),
        })
    fieldnames = list(rows[0])
    insert_at = fieldnames.index("endpoint_b")+1
    fieldnames[insert_at:insert_at] = ["display_label", "verified_label"]
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(output)
    return len(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("geometry", type=Path)
    parser.add_argument("claims", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cache-dir", type=Path, required=True)
    parser.add_argument("--sensitivity-links", type=Path)
    parser.add_argument("--top-10-links-csv", type=Path)
    parser.add_argument("--top-10-links-tex", type=Path)
    parser.add_argument("--top-30-links-csv", type=Path)
    parser.add_argument("--top-30-links-tex", type=Path)
    parser.add_argument("--mechanism-links-csv", type=Path)
    parser.add_argument("--mechanism-links-tex", type=Path)
    parser.add_argument("--rank-distribution-csv", type=Path)
    parser.add_argument("--rank-distribution-tex", type=Path)
    args = parser.parse_args()
    features, archive, geojson, gdal_version = cbsa_features(args.cache_dir)
    places, place_sources = place_features(args.cache_dir)
    with args.geometry.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    output_rows = []
    labels = {}
    label_statuses = {}
    for row in rows:
        geoid_a, name_a = assign(
            features, float(row["longitude_a"]), float(row["latitude_a"]))
        geoid_b, name_b = assign(
            features, float(row["longitude_b"]), float(row["latitude_b"]))
        place_geoid_a, place_name_a = assign(
            places, float(row["longitude_a"]), float(row["latitude_a"]))
        place_geoid_b, place_name_b = assign(
            places, float(row["longitude_b"]), float(row["latitude_b"]))
        label, label_status = descriptive_link_label(
            name_a, name_b, place_name_a, place_name_b,
            row["physical_link_id"])
        output_rows.append({
            "physical_link_id": row["physical_link_id"],
            "endpoint_a": row["endpoint_a"],
            "endpoint_b": row["endpoint_b"],
            "cbsa_geoid_a": geoid_a,
            "cbsa_name_a": name_a,
            "cbsa_geoid_b": geoid_b,
            "cbsa_name_b": name_b,
            "place_geoid_a": place_geoid_a,
            "place_name_a": place_name_a,
            "place_geoid_b": place_geoid_b,
            "place_name_b": place_name_b,
            "verified_label": label,
            "label_status": label_status,
        })
        labels[row["physical_link_id"]] = label
        label_statuses[row["physical_link_id"]] = label_status
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
        link["label_status"] = label_statuses.get(
            link["physical_link_id"], "unavailable")
    comparison = claims.get("top_link_comparison")
    appendix_comparison = claims.get("appendix_top_link_comparison")
    if comparison is not None or appendix_comparison is not None:
        required = (
            args.top_10_links_csv, args.top_10_links_tex,
            args.top_30_links_csv, args.top_30_links_tex,
        )
        if any(path is None for path in required):
            raise ValueError("both top-10 and top-30 output paths are required")
    if comparison is not None:
        write_top_link_outputs(
            comparison, output_rows,
            args.top_10_links_csv, args.top_10_links_tex,
            table_label="tab:rsue_top_10_links",
            caption="Top 10 physical road links under the traditional and extended approaches",
            layout="stacked",
        )
    if appendix_comparison is not None:
        write_top_link_outputs(
            appendix_comparison, output_rows,
            args.top_30_links_csv, args.top_30_links_tex,
            table_label="tab:rsue_top_links",
            caption="Top 30 physical road links under the traditional and extended approaches",
            layout="side_by_side",
        )
    mechanism_links = claims.get("mechanism_links")
    if mechanism_links is not None:
        if args.mechanism_links_csv is None or args.mechanism_links_tex is None:
            raise ValueError("mechanism-link CSV and TeX output paths are required")
        write_mechanism_link_outputs(
            mechanism_links, output_rows,
            args.mechanism_links_csv, args.mechanism_links_tex)
        claims["mechanism_links_sha256"] = sha256(args.mechanism_links_csv)
    rank_distribution = claims.get("rank_distribution")
    if rank_distribution is not None:
        if args.rank_distribution_csv is None or args.rank_distribution_tex is None:
            raise ValueError("rank-distribution CSV and TeX output paths are required")
        write_rank_distribution_outputs(
            rank_distribution,
            args.rank_distribution_csv, args.rank_distribution_tex)
        claims["rank_distribution_sha256"] = sha256(args.rank_distribution_csv)
    if args.sensitivity_links is not None:
        sensitivity_rows = label_sensitivity_links(
            args.sensitivity_links, output_rows)
        claims["sensitivity_link_panel"]["labeled_rows"] = sensitivity_rows
        claims["sensitivity_link_panel"]["sha256"] = sha256(
            args.sensitivity_links)
    claims["cbsa_crosswalk"] = {
        "source_url": CBSA_URL,
        "source_sha256": sha256(archive),
        "expected_source_sha256": CBSA_SHA256,
        "geojson_sha256": sha256(geojson),
        "gdal_version": gdal_version,
        "python_version": sys.version.split()[0],
        "vintage": 2018,
        "assignment": "point_in_polygon_only",
        "labeled_physical_links": sum(bool(value) for value in labels.values()),
        "place_sources": place_sources,
    }
    with args.claims.open("w") as handle:
        json.dump(claims, handle, sort_keys=True, separators=(",", ":"))
        handle.write("\n")


if __name__ == "__main__":
    main()
