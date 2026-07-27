"""Geographic welfare map, comparison scatter, and table for Westeros."""

from __future__ import annotations

import csv
import json
from pathlib import Path

from plots import figure_style as style

import matplotlib.pyplot as plt
from matplotlib.cm import ScalarMappable
from matplotlib.collections import LineCollection
from matplotlib.lines import Line2D
from matplotlib.ticker import MaxNLocator
import numpy as np


def _read_rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(path)
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def _read_json(path: Path) -> dict:
    if not path.is_file():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def _polygon_rings(geometry: dict):
    if geometry["type"] == "Polygon":
        yield from (geometry["coordinates"],)
    elif geometry["type"] == "MultiPolygon":
        yield from geometry["coordinates"]
    else:
        raise ValueError("Westeros geography must be Polygon or MultiPolygon")


def _road_lines(feature: dict):
    geometry = feature["geometry"]
    if geometry["type"] == "LineString":
        return [geometry["coordinates"]]
    if geometry["type"] == "MultiLineString":
        return geometry["coordinates"]
    raise ValueError("Westeros roads must be line geometries")


def display_name(row: dict[str, str]) -> str:
    name = row.get("name", "").strip()
    if name:
        return name
    kind = row.get("location_type", "location").strip().lower()
    return f"Unnamed {kind}"


def rank_rows(rows: list[dict]) -> list[dict]:
    traditional = {
        row["physical_link_id"]: rank
        for rank, row in enumerate(
            sorted(rows, key=lambda item: (-item["hulten"],
                                           item["physical_link_id"])),
            start=1,
        )
    }
    extended = {
        row["physical_link_id"]: rank
        for rank, row in enumerate(
            sorted(rows, key=lambda item: (-item["primitive_F"],
                                           item["physical_link_id"])),
            start=1,
        )
    }
    return [
        {
            **row,
            "traditional_rank": traditional[row["physical_link_id"]],
            "extended_rank": extended[row["physical_link_id"]],
            "rank_change": (
                traditional[row["physical_link_id"]]
                - extended[row["physical_link_id"]]
            ),
        }
        for row in rows
    ]


def load_westeros(generated: Path) -> dict:
    generated = Path(generated)
    nodes = _read_rows(generated / "data" / "nodes.csv")
    results = _read_rows(
        generated / "output" / "decomposition_physical.csv"
    )
    corridor_payload = _read_json(generated / "link_geometry.geojson")
    continent = _read_json(
        generated / "source_cache" / "continent.geojson"
    )
    roads = _read_json(generated / "source_cache" / "roads.geojson")

    node_index = {row["node_id"]: row for row in nodes}
    parsed_results = []
    for row in results:
        if row["endpoint_a"] not in node_index or row["endpoint_b"] not in node_index:
            raise ValueError(
                f"{row['physical_link_id']} refers to a missing Westeros node"
            )
        parsed_results.append({
            "physical_link_id": row["physical_link_id"],
            "endpoint_a": row["endpoint_a"],
            "endpoint_b": row["endpoint_b"],
            "hulten": float(row["hulten"]),
            "primitive_F": float(row["primitive_F"]),
        })

    corridor_geometry = {
        feature["properties"]["physical_link_id"]:
            feature["geometry"]["coordinates"]
        for feature in corridor_payload["features"]
    }
    missing = {
        row["physical_link_id"] for row in parsed_results
    } - set(corridor_geometry)
    if missing:
        raise ValueError(
            f"Westeros corridor geometry omits {len(missing)} model links"
        )
    return {
        "nodes": node_index,
        "results": rank_rows(parsed_results),
        "corridors": corridor_geometry,
        "continent": continent,
        "roads": roads,
    }


def _road_extent(roads: dict) -> tuple[float, float, float, float]:
    points = []
    for feature in roads["features"]:
        for line in _road_lines(feature):
            points.extend(line)
    x = np.asarray([point[0] for point in points], dtype=float)
    y = np.asarray([point[1] for point in points], dtype=float)
    return float(x.min()), float(x.max()), float(y.min()), float(y.max())


def world_map_figure(data: dict):
    figure, axis = plt.subplots(figsize=(6.15, 8.15))
    continent = data["continent"]
    for feature in continent["features"]:
        for polygon in _polygon_rings(feature["geometry"]):
            exterior = polygon[0]
            axis.fill(
                [point[0] for point in exterior],
                [point[1] for point in exterior],
                facecolor=style.PALE,
                edgecolor=style.MUTED,
                linewidth=0.75,
                zorder=0,
            )
            for hole in polygon[1:]:
                axis.fill(
                    [point[0] for point in hole],
                    [point[1] for point in hole],
                    facecolor=style.WHITE,
                    edgecolor="none",
                    zorder=0,
                )

    source_roads = []
    for feature in data["roads"]["features"]:
        source_roads.extend(_road_lines(feature))
    axis.add_collection(LineCollection(
        source_roads,
        colors=style.LIGHT,
        linewidths=0.42,
        alpha=0.80,
        zorder=1,
    ))

    rows = data["results"]
    values = np.asarray([row["primitive_F"] for row in rows], dtype=float)
    norm, cmap = style.welfare_norm(values, include_zero=True)
    color_map = plt.get_cmap(cmap) if isinstance(cmap, str) else cmap
    maximum = max(float(np.max(np.abs(values))), np.finfo(float).eps)
    for row in sorted(
        rows,
        key=lambda item: (abs(item["primitive_F"]),
                          item["physical_link_id"]),
    ):
        value = row["primitive_F"]
        width = 0.65 + 2.8 * np.sqrt(abs(value) / maximum)
        axis.plot(
            *zip(*data["corridors"][row["physical_link_id"]]),
            color=color_map(norm(value)),
            linewidth=width,
            alpha=0.90,
            solid_capstyle="round",
            solid_joinstyle="round",
            zorder=2,
        )

    nodes = list(data["nodes"].values())
    activity = np.asarray([float(row["income"]) for row in nodes])
    sizes = 8 + 43 * np.sqrt(activity / activity.max())
    axis.scatter(
        [float(row["longitude"]) for row in nodes],
        [float(row["latitude"]) for row in nodes],
        s=sizes,
        facecolor=style.WHITE,
        edgecolor=style.INK,
        linewidth=0.55,
        zorder=3,
    )

    preferred_labels = {
        "Winterfell": (5, 4),
        "King's Landing": (6, -7),
        "Oldtown": (5, -7),
        "Sunspear": (5, 3),
        "The Eyrie": (5, 4),
    }
    for row in nodes:
        name = row["name"].strip()
        if name not in preferred_labels:
            continue
        axis.annotate(
            name,
            (float(row["longitude"]), float(row["latitude"])),
            xytext=preferred_labels[name],
            textcoords="offset points",
            fontsize=6.8,
            color=style.INK,
            zorder=4,
        )

    scalar = ScalarMappable(norm=norm, cmap=color_map)
    scalar.set_array(values)
    colorbar = figure.colorbar(
        scalar,
        ax=axis,
        orientation="horizontal",
        fraction=0.027,
        pad=0.018,
        aspect=42,
    )
    colorbar.set_label(
        "Extended approach: welfare elasticity",
        labelpad=3,
    )
    colorbar.outline.set_visible(False)
    colorbar.ax.tick_params(length=2.0, width=0.45)

    legend = [
        Line2D([0], [0], color=style.LIGHT, linewidth=1.1,
               label="Source road"),
        Line2D([0], [0], color=style.TEAL, linewidth=2.4,
               label="Evaluated model corridor"),
    ]
    axis.legend(
        handles=legend,
        loc="upper left",
        bbox_to_anchor=(0.012, 0.995),
        frameon=True,
        facecolor=style.WHITE,
        edgecolor="none",
        framealpha=0.88,
        handlelength=2.4,
        borderaxespad=0.0,
        borderpad=0.35,
    )

    xmin, xmax, ymin, ymax = _road_extent(data["roads"])
    xmargin = 0.04 * (xmax - xmin)
    ymargin = 0.035 * (ymax - ymin)
    axis.set_xlim(xmin - xmargin, xmax + xmargin)
    axis.set_ylim(ymin - ymargin, ymax + ymargin)
    axis.set_aspect("equal", adjustable="box")
    axis.set_axis_off()
    figure.subplots_adjust(left=0.03, right=0.97, top=0.99, bottom=0.06)
    return figure


def _link_name(row: dict, nodes: dict[str, dict[str, str]]) -> str:
    first = display_name(nodes[row["endpoint_a"]])
    second = display_name(nodes[row["endpoint_b"]])
    return f"{first}--{second}"


def scatter_figure(data: dict):
    rows = data["results"]
    traditional = np.asarray([row["hulten"] for row in rows])
    extended = np.asarray([row["primitive_F"] for row in rows])
    lower, upper = style.shared_identity_limits(traditional, extended)
    if np.all(traditional >= 0) and np.all(extended >= 0):
        lower = 0.0
        upper *= 1.03

    figure, axis = plt.subplots(figsize=(4.55, 4.05))
    axis.plot(
        [lower, upper],
        [lower, upper],
        color=style.MUTED,
        linewidth=0.8,
        linestyle=(0, (4, 3)),
        zorder=1,
    )
    axis.scatter(
        traditional,
        extended,
        s=23,
        color=style.BLUE,
        alpha=0.62,
        edgecolor=style.WHITE,
        linewidth=0.45,
        zorder=2,
    )

    selected = []
    for candidate in (
        max(rows, key=lambda row: (row["primitive_F"],
                                   row["physical_link_id"])),
        max(rows, key=lambda row: (row["rank_change"],
                                   row["primitive_F"])),
        min(rows, key=lambda row: (row["rank_change"],
                                   -row["primitive_F"])),
    ):
        if candidate["physical_link_id"] not in {
            row["physical_link_id"] for row in selected
        }:
            selected.append(candidate)
    colors = (style.TEAL, style.ORANGE, style.PURPLE)
    label_offsets = ((0, 7), (-7, 7), (8, -7))
    key_lines = []
    for number, (row, color, offset) in enumerate(
        zip(selected, colors, label_offsets),
        start=1,
    ):
        axis.scatter(
            row["hulten"],
            row["primitive_F"],
            s=38,
            color=color,
            edgecolor=style.WHITE,
            linewidth=0.55,
            zorder=3,
        )
        axis.annotate(
            str(number),
            (row["hulten"], row["primitive_F"]),
            xytext=offset,
            textcoords="offset points",
            ha="center",
            va="center",
            fontsize=6.2,
            fontweight="bold",
            color=color,
            arrowprops={
                "arrowstyle": "-",
                "color": color,
                "linewidth": 0.55,
                "shrinkA": 1.5,
                "shrinkB": 3.0,
            },
            zorder=4,
        )
        key_lines.append(
            f"{number}  {_link_name(row, data['nodes'])}"
        )

    pearson, spearman = style.correlations(traditional, extended)
    axis.text(
        0.04,
        0.96,
        rf"Pearson $r={pearson:.3f}$" + "\n"
        + rf"Spearman $\rho={spearman:.3f}$",
        transform=axis.transAxes,
        ha="left",
        va="top",
        fontsize=7.3,
        color=style.INK,
        bbox={
            "facecolor": style.WHITE,
            "edgecolor": "none",
            "alpha": 0.88,
            "pad": 2.0,
        },
    )
    axis.text(
        0.97,
        0.93,
        "\n".join(key_lines),
        transform=axis.transAxes,
        ha="right",
        va="top",
        fontsize=6.6,
        linespacing=1.35,
        color=style.INK,
        bbox={
            "facecolor": style.WHITE,
            "edgecolor": "none",
            "alpha": 0.88,
            "pad": 2.0,
        },
    )
    axis.set(
        xlabel="Traditional approach\nWelfare elasticity",
        ylabel="Extended approach\nWelfare elasticity",
        xlim=(lower, upper),
        ylim=(lower, upper),
    )
    axis.set_aspect("equal", adjustable="box")
    axis.xaxis.set_major_locator(MaxNLocator(4))
    axis.yaxis.set_major_locator(MaxNLocator(4))
    style.style_axis(axis, grid_axis="both")
    figure.subplots_adjust(left=0.18, bottom=0.17, right=0.97, top=0.97)
    return figure


def _tex_escape(value: str) -> str:
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
    }
    return "".join(replacements.get(character, character) for character in value)


def write_table(data: dict, tex_path: Path, csv_path: Path, count: int = 8):
    rows = sorted(
        data["results"],
        key=lambda row: (-row["primitive_F"], row["physical_link_id"]),
    )
    selected = rows[:count]
    tex_lines = [
        "% Generated by plots/westeros_example.py; do not edit.",
        r"\begin{tabular}{L{0.31\textwidth}rrrr}",
        r"\toprule",
        r"Link & Traditional & Extended & Trad. rank & Ext. rank \\",
        r"\midrule",
    ]
    for row in selected:
        tex_lines.append(
            f"{_tex_escape(_link_name(row, data['nodes']))} & "
            f"{row['hulten']:.6f} & {row['primitive_F']:.6f} & "
            f"{row['traditional_rank']} & {row['extended_rank']} \\\\"
        )
    tex_lines.extend((r"\bottomrule", r"\end{tabular}", ""))
    tex_path.parent.mkdir(parents=True, exist_ok=True)
    tex_path.write_text("\n".join(tex_lines), encoding="utf-8")

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow((
            "physical_link_id",
            "link_name",
            "hulten",
            "primitive_F",
            "traditional_rank",
            "extended_rank",
            "rank_change",
        ))
        for row in rows:
            writer.writerow((
                row["physical_link_id"],
                _link_name(row, data["nodes"]),
                f"{row['hulten']:.17g}",
                f"{row['primitive_F']:.17g}",
                row["traditional_rank"],
                row["extended_rank"],
                row["rank_change"],
            ))


def build_assets(generated: Path, figures: Path, tables: Path) -> list[Path]:
    data = load_westeros(generated)
    outputs = []
    outputs.extend(style.save_figure_pair(
        world_map_figure(data),
        figures,
        "westeros-world-map",
        tight=False,
    ))
    outputs.extend(style.save_figure_pair(
        scatter_figure(data),
        figures,
        "westeros-scatter",
        tight=False,
    ))
    tex_path = Path(tables) / "westeros-top-links.tex"
    csv_path = Path(tables) / "westeros-link-comparison.csv"
    write_table(data, tex_path, csv_path)
    outputs.extend((tex_path, csv_path))
    return outputs
