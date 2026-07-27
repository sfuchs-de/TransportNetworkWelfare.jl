"""Consistent maps, comparison scatters, and tables for guide examples."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import tempfile

import numpy as np

try:
    from plots import figure_style as style
except ModuleNotFoundError:
    import figure_style as style

import matplotlib.pyplot as plt
from matplotlib.cm import ScalarMappable
from matplotlib.ticker import MaxNLocator


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATA = (
    ROOT / "docs" / "practitioner-guide" / "generated" / "example-assets"
)
DEFAULT_FIGURES = ROOT / "docs" / "practitioner-guide" / "figures"
DEFAULT_TABLES = ROOT / "docs" / "practitioner-guide" / "tables"
EXAMPLE_STEMS = ("grid", "braess", "cow", "urban")


def _read_rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(f"missing example visualization input: {path}")
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


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


def _link_label(identifier: str, *, compact: bool = False) -> str:
    import re

    westeros = re.fullmatch(r"westeros-(\d+)", identifier)
    if westeros and compact:
        return f"W{int(westeros.group(1))}"
    match = re.fullmatch(r"([HV])_r(\d+)_c(\d+)", identifier)
    if match:
        kind, row, column = match.groups()
        if compact:
            return f"{kind}{row}:{column}"
        if kind == "H":
            return f"Row {row}, columns {column}-{int(column) + 1}"
        return f"Column {column}, rows {row}-{int(row) + 1}"
    return identifier.replace("_", "-")


def load_example(data_root: Path, stem: str) -> dict:
    """Load and validate the stable visualization contract for one example."""
    source = data_root / stem
    nodes_path = source / "nodes.csv"
    links_path = source / "links.csv"
    nodes = _read_rows(nodes_path)
    links = _read_rows(links_path)
    if not nodes or not links:
        raise ValueError(f"{stem} visualization inputs must contain nodes and links")

    node_ids = [row["node_id"] for row in nodes]
    if len(node_ids) != len(set(node_ids)):
        raise ValueError(f"{stem} visualization node IDs are not unique")
    node_index = {
        row["node_id"]: {
            "x": float(row["x"]),
            "y": float(row["y"]),
            "activity": float(row["activity"]),
            "terminal": row["terminal"].lower() == "true",
        }
        for row in nodes
    }
    if not all(
        np.isfinite((row["x"], row["y"], row["activity"])).all()
        and row["activity"] > 0
        for row in node_index.values()
    ):
        raise ValueError(f"{stem} node coordinates and activity must be finite")

    parsed_links = []
    identifiers = set()
    for row in links:
        identifier = row["physical_link_id"]
        if identifier in identifiers:
            raise ValueError(f"{stem} has duplicate physical link {identifier}")
        identifiers.add(identifier)
        if row["endpoint_a"] not in node_index or row["endpoint_b"] not in node_index:
            raise ValueError(f"{stem} link {identifier} references an unknown node")
        modes = tuple(filter(None, row["modes"].split("|")))
        values = {
            "physical_link_id": identifier,
            "endpoint_a": row["endpoint_a"],
            "endpoint_b": row["endpoint_b"],
            "hulten": float(row["hulten"]),
            "primitive_F": float(row["primitive_F"]),
            "modes": modes,
        }
        if not np.isfinite((values["hulten"], values["primitive_F"])).all():
            raise ValueError(f"{stem} link {identifier} has a nonfinite result")
        parsed_links.append(values)

    return {"stem": stem, "nodes": node_index, "links": parsed_links}


def _ranked_links(example: dict) -> list[dict]:
    links = example["links"]
    traditional_ranks = {
        row["physical_link_id"]: rank
        for rank, row in enumerate(sorted(
            links,
            key=lambda item: (-item["hulten"], item["physical_link_id"]),
        ), start=1)
    }
    extended_ranks = {
        row["physical_link_id"]: rank
        for rank, row in enumerate(sorted(
            links,
            key=lambda item: (-item["primitive_F"], item["physical_link_id"]),
        ), start=1)
    }
    ranked = []
    for row in links:
        identifier = row["physical_link_id"]
        ranked.append({
            **row,
            "traditional_rank": traditional_ranks[identifier],
            "extended_rank": extended_ranks[identifier],
            "rank_change":
                traditional_ranks[identifier] - extended_ranks[identifier],
        })
    return ranked


def _draw_map(axis, example: dict):
    nodes = example["nodes"]
    links = example["links"]
    values = np.array([row["primitive_F"] for row in links], dtype=float)
    norm, cmap = style.welfare_norm(values, include_zero=True)
    color_map = plt.get_cmap(cmap) if isinstance(cmap, str) else cmap
    maximum = max(float(np.max(np.abs(values))), np.finfo(float).eps)

    for row in sorted(links, key=lambda item: item["physical_link_id"]):
        first = nodes[row["endpoint_a"]]
        second = nodes[row["endpoint_b"]]
        value = row["primitive_F"]
        width = 1.4 + 2.7 * np.sqrt(abs(value) / maximum)
        axis.plot(
            [first["x"], second["x"]],
            [first["y"], second["y"]],
            color=color_map(norm(value)),
            linewidth=width,
            solid_capstyle="round",
            zorder=2,
        )
        nonroad = sorted(mode for mode in row["modes"] if mode != "road")
        if nonroad:
            mode = nonroad[0]
            axis.plot(
                [first["x"], second["x"]],
                [first["y"], second["y"]],
                color=style.MODE_COLORS.get(mode, style.BLUE),
                linewidth=0.8,
                linestyle=(0, (2.2, 1.7)),
                solid_capstyle="round",
                zorder=3,
            )

    activity = np.array([node["activity"] for node in nodes.values()])
    activity_scale = np.sqrt(activity / activity.max())
    for (identifier, node), scale in zip(sorted(nodes.items()), activity_scale):
        if node["terminal"]:
            axis.scatter(
                node["x"], node["y"], s=45 + 52 * scale,
                facecolor=style.WHITE, edgecolor=style.BLUE, linewidth=0.85,
                zorder=4,
            )
        axis.scatter(
            node["x"], node["y"], s=13 + 31 * scale,
            facecolor=style.GOLD, edgecolor=style.INK, linewidth=0.45,
            zorder=5,
        )

    axis.set_aspect("equal", adjustable="datalim")
    axis.margins(0.10)
    axis.set_axis_off()
    scalar = ScalarMappable(norm=norm, cmap=color_map)
    scalar.set_array(values)
    return scalar


def _annotation_rows(ranked: list[dict]) -> list[dict]:
    if len(ranked) < 2:
        return ranked
    rise = max(
        ranked,
        key=lambda row: (row["rank_change"], row["primitive_F"],
                         row["physical_link_id"]),
    )
    fall = min(
        ranked,
        key=lambda row: (row["rank_change"], -row["primitive_F"],
                         row["physical_link_id"]),
    )
    if rise["physical_link_id"] == fall["physical_link_id"]:
        alternative = max(
            ranked,
            key=lambda row: (
                abs(row["rank_change"]),
                row["primitive_F"],
                row["physical_link_id"],
            ),
        )
        return [rise] if alternative is rise else [rise, alternative]
    return [rise, fall]


def _draw_scatter(axis, example: dict):
    ranked = _ranked_links(example)
    traditional = np.array([row["hulten"] for row in ranked], dtype=float)
    extended = np.array([row["primitive_F"] for row in ranked], dtype=float)
    lower, upper = style.shared_identity_limits(traditional, extended)
    if np.all(traditional >= 0) and np.all(extended >= 0):
        lower = 0.0
        upper *= 1.03

    axis.plot(
        [lower, upper], [lower, upper],
        color=style.MUTED, linewidth=0.8, linestyle=(0, (4, 3)), zorder=1,
    )
    axis.scatter(
        traditional, extended, s=24, color=style.BLUE, alpha=0.62,
        edgecolor=style.WHITE, linewidth=0.45, zorder=2,
    )
    for index, row in enumerate(_annotation_rows(ranked)):
        axis.scatter(
            row["hulten"], row["primitive_F"], s=33,
            color=style.ORANGE if index else style.TEAL,
            edgecolor=style.WHITE, linewidth=0.55, zorder=3,
        )
        horizontal_position = (row["hulten"] - lower) / (upper - lower)
        vertical_position = (row["primitive_F"] - lower) / (upper - lower)
        if horizontal_position > 0.72:
            horizontal, horizontal_offset = "right", -5
        else:
            horizontal, horizontal_offset = "left", 5
        if vertical_position > 0.72:
            vertical, vertical_offset = "top", -6
        else:
            vertical, vertical_offset = "bottom", 6
        axis.annotate(
            _link_label(row["physical_link_id"], compact=True),
            (row["hulten"], row["primitive_F"]),
            xytext=(horizontal_offset, vertical_offset),
            textcoords="offset points",
            ha=horizontal, va=vertical, fontsize=7.0,
            color=style.ORANGE if index else style.TEAL,
        )

    pearson, spearman = style.correlations(traditional, extended)
    correlation_text = (
        rf"Pearson $r={pearson:.3f}$" + "\n" +
        rf"Spearman $\rho={spearman:.3f}$"
        if np.isfinite(pearson) and np.isfinite(spearman)
        else "Correlations not defined"
    )
    axis.text(
        0.04, 0.96, correlation_text,
        transform=axis.transAxes, ha="left", va="top", fontsize=7.3,
        color=style.INK,
        bbox={"facecolor": style.WHITE, "edgecolor": "none", "alpha": 0.86,
              "pad": 2.0},
    )
    axis.set(
        xlabel="Traditional approach\nWelfare elasticity",
        ylabel="Extended approach\nWelfare elasticity",
        xlim=(lower, upper), ylim=(lower, upper),
    )
    axis.set_aspect("equal", adjustable="box")
    axis.xaxis.set_major_locator(MaxNLocator(4))
    axis.yaxis.set_major_locator(MaxNLocator(4))
    style.style_axis(axis, grid_axis="both")
    return pearson, spearman


def map_figure(example: dict):
    figure, axis = plt.subplots(figsize=(4.8, 3.45))
    scalar = _draw_map(axis, example)
    colorbar = figure.colorbar(
        scalar, ax=axis, orientation="horizontal", fraction=0.075,
        pad=0.045, aspect=28,
    )
    colorbar.set_label(style.metric_label("primitive_F"), labelpad=3)
    colorbar.outline.set_visible(False)
    colorbar.ax.tick_params(length=2.0, width=0.45)
    return figure


def scatter_figure(example: dict):
    figure, axis = plt.subplots(figsize=(4.35, 3.75))
    _draw_scatter(axis, example)
    figure.subplots_adjust(left=0.18, bottom=0.18, right=0.97, top=0.97)
    return figure


def comparison_figure(example: dict):
    figure, (map_axis, scatter_axis) = plt.subplots(
        1, 2, figsize=(7.15, 3.05), gridspec_kw={"width_ratios": (1.08, 1.0)}
    )
    scalar = _draw_map(map_axis, example)
    _draw_scatter(scatter_axis, example)
    colorbar = figure.colorbar(
        scalar, ax=map_axis, orientation="horizontal", fraction=0.08,
        pad=0.035, aspect=24,
    )
    colorbar.set_label("Extended approach: welfare elasticity", labelpad=2)
    colorbar.outline.set_visible(False)
    colorbar.ax.tick_params(length=2.0, width=0.45)
    figure.subplots_adjust(
        left=0.035, right=0.985, bottom=0.19, top=0.97, wspace=0.29
    )
    return figure


def _write_table(example: dict, tex_path: Path, csv_path: Path, rows: int = 8):
    ranked = sorted(
        _ranked_links(example),
        key=lambda row: (-row["primitive_F"], row["physical_link_id"]),
    )
    selected = ranked[:min(rows, len(ranked))]
    tex_path.parent.mkdir(parents=True, exist_ok=True)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "% Generated by plots/example_assets.py; do not edit.",
        r"\begin{tabular}{lrrrr}",
        r"\toprule",
        r"Link & Traditional & Extended & Traditional rank & Extended rank \\",
        r"\midrule",
    ]
    for row in selected:
        lines.append(
            f"{_tex_escape(_link_label(row['physical_link_id']))} & "
            f"{row['hulten']:.6f} & {row['primitive_F']:.6f} & "
            f"{row['traditional_rank']:.0f} & {row['extended_rank']:.0f} \\\\"
        )
    lines.extend((r"\bottomrule", r"\end{tabular}", ""))
    tex_path.write_text("\n".join(lines), encoding="utf-8")

    with csv_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow((
            "physical_link_id", "hulten", "primitive_F",
            "traditional_rank", "extended_rank", "rank_change",
        ))
        for row in ranked:
            writer.writerow((
                row["physical_link_id"],
                f"{row['hulten']:.17g}",
                f"{row['primitive_F']:.17g}",
                f"{row['traditional_rank']:.17g}",
                f"{row['extended_rank']:.17g}",
                f"{row['rank_change']:.17g}",
            ))


def build_assets(
    data_root: Path = DEFAULT_DATA,
    figures: Path = DEFAULT_FIGURES,
    tables: Path = DEFAULT_TABLES,
    stems: tuple[str, ...] = EXAMPLE_STEMS,
) -> list[Path]:
    """Build the complete visual triptych for every guide example."""
    outputs = []
    provenance = {"schema_version": 1, "examples": {}}
    if not stems:
        raise ValueError("at least one example stem is required")
    if len(stems) != len(set(stems)):
        raise ValueError("example stems must be unique")
    for stem in stems:
        example = load_example(data_root, stem)
        outputs.extend(style.save_figure_pair(
            map_figure(example), figures, f"{stem}-welfare-map", tight=False
        ))
        outputs.extend(style.save_figure_pair(
            scatter_figure(example), figures, f"{stem}-scatter", tight=False
        ))
        outputs.extend(style.save_figure_pair(
            comparison_figure(example), figures, f"{stem}-comparison",
            tight=False,
        ))
        tex_path = tables / f"{stem}-top-links.tex"
        csv_path = tables / f"{stem}-link-comparison.csv"
        _write_table(example, tex_path, csv_path)
        outputs.extend((tex_path, csv_path))
        provenance["examples"][stem] = {
            "nodes_sha256": _sha256(data_root / stem / "nodes.csv"),
            "links_sha256": _sha256(data_root / stem / "links.csv"),
            "link_count": len(example["links"]),
        }

    manifest = tables / "example-assets.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    outputs.append(manifest)
    return sorted(outputs)


def check_assets():
    """Rebuild in isolation and require byte-identical committed assets."""
    with tempfile.TemporaryDirectory(prefix="tnw-example-assets-") as temporary:
        root = Path(temporary)
        generated = build_assets(
            DEFAULT_DATA, root / "figures", root / "tables"
        )
        for path in generated:
            relative = path.relative_to(root)
            committed_root = (
                DEFAULT_FIGURES if relative.parts[0] == "figures"
                else DEFAULT_TABLES
            )
            committed = committed_root.joinpath(*relative.parts[1:])
            if not committed.is_file():
                raise FileNotFoundError(f"missing committed example asset: {committed}")
            if path.read_bytes() != committed.read_bytes():
                raise RuntimeError(f"example asset drift: {committed}")
    print("practitioner-guide example assets accepted")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--data-root", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--figures", type=Path, default=DEFAULT_FIGURES)
    parser.add_argument("--tables", type=Path, default=DEFAULT_TABLES)
    parser.add_argument(
        "--stems", nargs="+", default=list(EXAMPLE_STEMS),
        help="example contract directories to render",
    )
    arguments = parser.parse_args()
    if arguments.check:
        check_assets()
    else:
        for path in build_assets(
            arguments.data_root, arguments.figures, arguments.tables,
            tuple(arguments.stems),
        ):
            print(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path)


if __name__ == "__main__":
    main()
