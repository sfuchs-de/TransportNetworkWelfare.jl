#!/usr/bin/env python3
"""Build a model-ready directional Census port-trade overlay.

Raw imports and exports generally violate the model's location-level balanced-
flow identity. The default transformation therefore RAS-projects each direction
onto common U.S.-port and foreign-region margins. It preserves the within-margin
directional composition and records the size of the projection.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
from collections import defaultdict
from decimal import Decimal, InvalidOperation
from pathlib import Path

from fetch_port_trade import MEASURES, month_range


HERE = Path(__file__).resolve().parent
DEFAULT_PORT_CROSSWALK = HERE / "port_crosswalk.csv"
DEFAULT_FOREIGN_REGIONS = HERE / "foreign_regions.csv"
VALID_MEASURES = ("TRADE_VAL_MO", *MEASURES)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_nonnegative_integer(value: object, label: str) -> int:
    text = str(value).strip()
    if not text:
        return 0
    try:
        number = Decimal(text)
    except InvalidOperation as exc:
        raise ValueError(f"invalid {label}={text!r}") from exc
    if number != number.to_integral_value() or number < 0:
        raise ValueError(f"{label} must be a nonnegative integer, got {text!r}")
    return int(number)


def load_port_crosswalk(path: Path) -> tuple[dict[str, dict[str, object]], list[int]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    required = {
        "census_port_code",
        "census_port_name",
        "rsue_node_id",
        "rsue_port_group",
    }
    if not rows or not required.issubset(rows[0]):
        raise ValueError(f"invalid port crosswalk schema: {path}")
    result: dict[str, dict[str, object]] = {}
    node_groups: dict[int, str] = {}
    for row in rows:
        code = str(row["census_port_code"]).zfill(4)
        if not (len(code) == 4 and code.isdigit()):
            raise ValueError(f"invalid Census port code: {code!r}")
        if code in result:
            raise ValueError(f"duplicate Census port code: {code}")
        node = parse_nonnegative_integer(row["rsue_node_id"], "rsue_node_id")
        if not 1 <= node <= 228:
            raise ValueError(f"domestic RSUE node must be in 1:228, got {node}")
        group = str(row["rsue_port_group"]).strip()
        name = str(row["census_port_name"]).strip()
        if not group or not name:
            raise ValueError(f"empty port name or group for {code}")
        previous = node_groups.setdefault(node, group)
        if previous != group:
            raise ValueError(f"RSUE node {node} maps to multiple port groups")
        result[code] = {"node": node, "group": group, "name": name}
    return result, sorted(node_groups)


def load_foreign_regions(
    path: Path,
) -> tuple[list[dict[str, int | str]], dict[str, int], list[int]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    required = {
        "foreign_region",
        "rsue_node_id",
        "schedule_c_min",
        "schedule_c_max",
    }
    if not rows or not required.issubset(rows[0]):
        raise ValueError(f"invalid foreign-region schema: {path}")
    ranges: list[dict[str, int | str]] = []
    nodes: dict[str, int] = {}
    covered: set[int] = set()
    for row in rows:
        region = str(row["foreign_region"]).strip()
        node = parse_nonnegative_integer(row["rsue_node_id"], "rsue_node_id")
        lower = parse_nonnegative_integer(row["schedule_c_min"], "schedule_c_min")
        upper = parse_nonnegative_integer(row["schedule_c_max"], "schedule_c_max")
        if not region or not 229 <= node <= 234 or lower > upper:
            raise ValueError(f"invalid foreign-region row: {row}")
        if region in nodes or node in nodes.values():
            raise ValueError(f"duplicate foreign region or node: {row}")
        overlap = covered.intersection(range(lower, upper + 1))
        if overlap:
            raise ValueError(f"overlapping Schedule C ranges near {min(overlap)}")
        covered.update(range(lower, upper + 1))
        nodes[region] = node
        ranges.append({"region": region, "node": node, "lower": lower, "upper": upper})
    return ranges, nodes, sorted(nodes.values())


def foreign_region(code: str, ranges: list[dict[str, int | str]]) -> str | None:
    if not (len(code) == 4 and code.isdigit()):
        return None
    number = int(code)
    for row in ranges:
        if int(row["lower"]) <= number <= int(row["upper"]):
            return str(row["region"])
    return None


def read_source_month(path: Path, flow: str, month: str) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(f"missing Census cache file: {path}")
    with gzip.open(path, "rt", newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    required = {"flow", "month", "PORT", "PORT_NAME", "CTY_CODE", "CTY_NAME", *VALID_MEASURES}
    if not rows or not required.issubset(rows[0]):
        raise ValueError(f"invalid Census cache schema: {path}")
    seen: set[tuple[str, str]] = set()
    for row in rows:
        if row["flow"] != flow or row["month"] != month:
            raise ValueError(f"source identity mismatch in {path}")
        key = (str(row["PORT"]).zfill(4), str(row["CTY_CODE"]).zfill(4))
        if key in seen:
            raise ValueError(f"duplicate port-country row in {path}: {key}")
        seen.add(key)
    return rows


def zero_matrix(rows: int, columns: int) -> list[list[float]]:
    return [[0.0 for _ in range(columns)] for _ in range(rows)]


def margins(matrix: list[list[float]]) -> tuple[list[float], list[float]]:
    row = [sum(values) for values in matrix]
    column = [sum(matrix[i][j] for i in range(len(matrix))) for j in range(len(matrix[0]))]
    return row, column


def normalize(matrix: list[list[float]]) -> list[list[float]]:
    total = sum(sum(row) for row in matrix)
    if total <= 0:
        raise ValueError("directional Census matrix has zero mass")
    return [[value / total for value in row] for row in matrix]


def max_margin_error(
    matrix: list[list[float]], row_target: list[float], column_target: list[float]
) -> float:
    row, column = margins(matrix)
    return max(
        max(abs(value - target) for value, target in zip(row, row_target)),
        max(abs(value - target) for value, target in zip(column, column_target)),
    )


def ras_project(
    matrix: list[list[float]],
    row_target: list[float],
    column_target: list[float],
    tolerance: float,
    max_iterations: int,
) -> tuple[list[list[float]], int, float]:
    if abs(sum(row_target) - 1.0) > tolerance or abs(sum(column_target) - 1.0) > tolerance:
        raise ValueError("RAS targets must each sum to one")
    result = [row[:] for row in normalize(matrix)]
    for i, target in enumerate(row_target):
        if target > tolerance and not any(value > 0 for value in result[i]):
            raise ValueError(f"RAS row {i} has a positive target but no support")
    for j, target in enumerate(column_target):
        if target > tolerance and not any(result[i][j] > 0 for i in range(len(result))):
            raise ValueError(f"RAS column {j} has a positive target but no support")

    for iteration in range(1, max_iterations + 1):
        row_margin, _ = margins(result)
        for i, target in enumerate(row_target):
            if target == 0:
                result[i] = [0.0] * len(result[i])
            else:
                if row_margin[i] <= 0:
                    raise ValueError(f"RAS lost support in row {i}")
                scale = target / row_margin[i]
                result[i] = [value * scale for value in result[i]]
        _, column_margin = margins(result)
        for j, target in enumerate(column_target):
            if target == 0:
                for i in range(len(result)):
                    result[i][j] = 0.0
            else:
                if column_margin[j] <= 0:
                    raise ValueError(f"RAS lost support in column {j}")
                scale = target / column_margin[j]
                for i in range(len(result)):
                    result[i][j] *= scale
        error = max_margin_error(result, row_target, column_target)
        if error <= tolerance:
            return result, iteration, error
    raise RuntimeError(
        f"RAS failed to converge within {max_iterations} iterations; "
        f"residual={max_margin_error(result, row_target, column_target):.3e}"
    )


def total_variation(left: list[list[float]], right: list[list[float]]) -> float:
    return 0.5 * sum(
        abs(left[i][j] - right[i][j])
        for i in range(len(left))
        for j in range(len(left[0]))
    )


def format_float(value: float) -> str:
    return f"{value:.17g}"


def csv_bytes(fieldnames: list[str], rows: list[dict[str, object]]) -> bytes:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue().encode("utf-8")


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def build_overlay(
    cache_root: Path,
    port_crosswalk_path: Path,
    foreign_regions_path: Path,
    start: str,
    end: str,
    measure: str,
    output_dir: Path,
    tolerance: float = 1e-12,
    max_iterations: int = 10_000,
) -> dict:
    if measure not in VALID_MEASURES:
        raise ValueError(f"unsupported measure: {measure}")
    if not (0 < tolerance < 1):
        raise ValueError("tolerance must lie in (0, 1)")
    if max_iterations <= 0:
        raise ValueError("max_iterations must be positive")

    ports, domestic_nodes = load_port_crosswalk(port_crosswalk_path)
    ranges, foreign_nodes_by_region, foreign_nodes = load_foreign_regions(foreign_regions_path)
    port_groups = {int(value["node"]): str(value["group"]) for value in ports.values()}
    domestic_index = {node: index for index, node in enumerate(domestic_nodes)}
    foreign_index = {node: index for index, node in enumerate(foreign_nodes)}
    region_by_node = {node: region for region, node in foreign_nodes_by_region.items()}

    raw = {
        "imports": zero_matrix(len(domestic_nodes), len(foreign_nodes)),
        "exports": zero_matrix(len(domestic_nodes), len(foreign_nodes)),
    }
    source_totals = defaultdict(int)
    selected_totals = defaultdict(int)
    excluded_totals = defaultdict(int)
    source_hashes: dict[str, str] = {}
    observed_names: dict[str, set[str]] = defaultdict(set)

    months = month_range(start, end)
    for flow in ("imports", "exports"):
        for month in months:
            path = cache_root / f"census_{flow}_port_country_{month}.csv.gz"
            source_hashes[path.name] = sha256_file(path)
            for row in read_source_month(path, flow, month):
                value = parse_nonnegative_integer(row[measure], measure)
                source_totals[flow] += value
                code = str(row["PORT"]).zfill(4)
                if code not in ports:
                    continue
                selected_totals[flow] += value
                observed_names[code].add(str(row["PORT_NAME"]).strip())
                country = str(row["CTY_CODE"]).zfill(4)
                region = foreign_region(country, ranges)
                if region is None:
                    excluded_totals[flow] += value
                    continue
                domestic_node = int(ports[code]["node"])
                foreign_node = foreign_nodes_by_region[region]
                raw[flow][domestic_index[domestic_node]][foreign_index[foreign_node]] += value

    for code, metadata in ports.items():
        if code not in observed_names:
            raise ValueError(f"crosswalk port {code} is absent from the requested Census period")
        expected = str(metadata["name"]).upper()
        names = {name.upper() for name in observed_names[code]}
        if names != {expected}:
            raise ValueError(
                f"Schedule D name changed for {code}: expected {expected!r}, observed {sorted(names)!r}"
            )
    if any(excluded_totals.values()):
        raise ValueError(
            "positive selected-port trade lies outside the declared Schedule C ranges: "
            + ", ".join(f"{flow}={value}" for flow, value in sorted(excluded_totals.items()))
        )

    normalized = {flow: normalize(matrix) for flow, matrix in raw.items()}
    import_rows, import_columns = margins(normalized["imports"])
    export_rows, export_columns = margins(normalized["exports"])
    target_rows = [(left + right) / 2 for left, right in zip(import_rows, export_rows)]
    target_columns = [(left + right) / 2 for left, right in zip(import_columns, export_columns)]
    balanced: dict[str, list[list[float]]] = {}
    ras_details: dict[str, dict[str, float | int]] = {}
    for flow in ("imports", "exports"):
        projected, iterations, error = ras_project(
            normalized[flow], target_rows, target_columns, tolerance, max_iterations
        )
        balanced[flow] = projected
        ras_details[flow] = {
            "iterations": iterations,
            "max_margin_error": error,
            "total_variation_from_raw_direction_share": total_variation(
                normalized[flow], projected
            ),
        }

    output_rows: list[dict[str, object]] = []
    for flow in ("imports", "exports"):
        direction_total = sum(sum(row) for row in raw[flow])
        for domestic_i, domestic_node in enumerate(domestic_nodes):
            for foreign_j, foreign_node in enumerate(foreign_nodes):
                projected = balanced[flow][domestic_i][foreign_j]
                if projected <= 0:
                    continue
                raw_value = int(raw[flow][domestic_i][foreign_j])
                if flow == "imports":
                    origin, destination = foreign_node, domestic_node
                    direction = "foreign_to_domestic"
                else:
                    origin, destination = domestic_node, foreign_node
                    direction = "domestic_to_foreign"
                output_rows.append(
                    {
                        "origin_node": origin,
                        "destination_node": destination,
                        "domestic_node": domestic_node,
                        "foreign_node": foreign_node,
                        "port_group": port_groups[domestic_node],
                        "foreign_region": region_by_node[foreign_node],
                        "direction": direction,
                        "raw_value_usd": raw_value,
                        "raw_direction_share": format_float(raw_value / direction_total),
                        "balanced_direction_share": format_float(projected),
                        "model_share": format_float(0.5 * projected),
                    }
                )
    output_rows.sort(
        key=lambda row: (
            str(row["direction"]),
            int(row["domestic_node"]),
            int(row["foreign_node"]),
        )
    )

    fields = [
        "origin_node",
        "destination_node",
        "domestic_node",
        "foreign_node",
        "port_group",
        "foreign_region",
        "direction",
        "raw_value_usd",
        "raw_direction_share",
        "balanced_direction_share",
        "model_share",
    ]
    overlay_path = output_dir / "census_port_region_overlay.csv"
    atomic_write(overlay_path, csv_bytes(fields, output_rows))

    node_balance = defaultdict(float)
    for row in output_rows:
        share = float(row["model_share"])
        node_balance[int(row["origin_node"])] += share
        node_balance[int(row["destination_node"])] -= share
    max_node_balance = max(abs(value) for value in node_balance.values())
    model_share_total = sum(float(row["model_share"]) for row in output_rows)
    if abs(model_share_total - 1.0) > 10 * tolerance:
        raise RuntimeError(f"model shares sum to {model_share_total}, not one")
    if max_node_balance > 10 * tolerance:
        raise RuntimeError(f"balanced overlay violates node flow identity by {max_node_balance}")

    source_hashes[port_crosswalk_path.name] = sha256_file(port_crosswalk_path)
    source_hashes[foreign_regions_path.name] = sha256_file(foreign_regions_path)
    diagnostics = {
        "schema_version": 1,
        "source": "U.S. Census International Trade porths API",
        "source_endpoints": {
            "imports": "https://api.census.gov/data/timeseries/intltrade/imports/porths",
            "exports": "https://api.census.gov/data/timeseries/intltrade/exports/porths",
        },
        "period": {"start": start, "end": end, "months": len(months)},
        "measure": measure,
        "direction_mapping": {
            "imports": "foreign_region_to_us_port",
            "exports": "us_port_to_foreign_region",
        },
        "balance_method": "ras_common_normalized_port_and_region_margins",
        "raw_totals_usd": dict(source_totals),
        "selected_port_totals_usd": dict(selected_totals),
        "selected_port_coverage": {
            flow: selected_totals[flow] / source_totals[flow]
            for flow in ("imports", "exports")
        },
        "domestic_nodes": domestic_nodes,
        "foreign_nodes": foreign_nodes,
        "common_port_margins": {
            str(node): target_rows[index] for index, node in enumerate(domestic_nodes)
        },
        "common_foreign_region_margins": {
            region_by_node[node]: target_columns[index]
            for index, node in enumerate(foreign_nodes)
        },
        "ras": ras_details,
        "model_share_total": model_share_total,
        "max_node_balance_residual": max_node_balance,
        "output_rows": len(output_rows),
        "source_hashes": dict(sorted(source_hashes.items())),
        "output_file": overlay_path.name,
        "output_sha256": sha256_file(overlay_path),
        "transformations": [
            "select explicit Schedule D ports from port_crosswalk.csv",
            "map Schedule C codes 1000:7999 into six declared foreign regions",
            f"aggregate {measure} over the requested months",
            "normalize imports and exports separately",
            "set common port and region margins to the mean directional margins",
            "RAS-project each direction without adding support",
            "assign one half of foreign-water mode mass to each direction",
        ],
    }
    diagnostics_path = output_dir / "census_port_region_diagnostics.json"
    atomic_write(
        diagnostics_path,
        (json.dumps(diagnostics, indent=2, sort_keys=True) + "\n").encode("utf-8"),
    )
    return diagnostics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-root", type=Path, required=True)
    parser.add_argument("--port-crosswalk", type=Path, default=DEFAULT_PORT_CROSSWALK)
    parser.add_argument("--foreign-regions", type=Path, default=DEFAULT_FOREIGN_REGIONS)
    parser.add_argument("--start", default="2017-01")
    parser.add_argument("--end", default="2017-12")
    parser.add_argument("--measure", choices=VALID_MEASURES, default="CNT_VAL_MO")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--tolerance", type=float, default=1e-12)
    parser.add_argument("--max-iterations", type=int, default=10_000)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    diagnostics = build_overlay(
        args.cache_root.expanduser().resolve(),
        args.port_crosswalk.expanduser().resolve(),
        args.foreign_regions.expanduser().resolve(),
        args.start,
        args.end,
        args.measure,
        args.output_dir.expanduser().resolve(),
        args.tolerance,
        args.max_iterations,
    )
    print(
        json.dumps(
            {
                "status": "ok",
                "output_rows": diagnostics["output_rows"],
                "selected_port_coverage": diagnostics["selected_port_coverage"],
                "max_node_balance_residual": diagnostics["max_node_balance_residual"],
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
