import csv
import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

import matplotlib.image as mpimg


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "seattle_transit_impacts", ROOT / "plots" / "seattle_transit_impacts.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def write_rows(path, fields, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


class SeattleTransitFigureTests(unittest.TestCase):
    def test_complete_transparent_figure_set(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            nodes = root / "nodes.csv"
            write_rows(nodes, ["node_id", "longitude", "latitude", "income"], [
                {"node_id": "1", "longitude": -122.35, "latitude": 47.58, "income": 1},
                {"node_id": "2", "longitude": -122.30, "latitude": 47.62, "income": 1},
                {"node_id": "3", "longitude": -122.25, "latitude": 47.57, "income": 1},
            ])
            link_fields = [
                "corridor_id", "origin", "destination", "mode", "hulten",
                "primitive_F", "traditional_gain_pct", "extended_gain_pct",
                "extended_minus_traditional_pct",
            ]
            directed_fields = [
                "edge_id", "origin", "destination", "mode", "hulten", "primitive_F",
            ]
            mode_links = {}
            mode_directed = {}
            for offset, mode in enumerate(("bus", "rail", "ferry"), start=1):
                links = [
                    {"corridor_id": "1_2", "origin": "1", "destination": "2",
                     "mode": mode, "hulten": 0.01*offset,
                     "primitive_F": 0.008*offset,
                     "traditional_gain_pct": 0.01*offset,
                     "extended_gain_pct": 0.008*offset,
                     "extended_minus_traditional_pct": -0.002*offset},
                    {"corridor_id": "2_3", "origin": "2", "destination": "3",
                     "mode": mode, "hulten": 0.006*offset,
                     "primitive_F": 0.009*offset,
                     "traditional_gain_pct": 0.006*offset,
                     "extended_gain_pct": 0.009*offset,
                     "extended_minus_traditional_pct": 0.003*offset},
                ]
                directed = [
                    {"edge_id": row["corridor_id"], "origin": row["origin"],
                     "destination": row["destination"], "mode": mode,
                     "hulten": row["hulten"], "primitive_F": row["primitive_F"]}
                    for row in links
                ]
                mode_links[mode] = links
                mode_directed[mode] = directed
                write_rows(root / f"links_{mode}.csv", link_fields, links)
                write_rows(root / f"directed_{mode}.csv", directed_fields, directed)

            all_links = []
            all_directed = []
            for index in range(2):
                source = mode_links["bus"][index]
                hulten = sum(float(mode_links[mode][index]["hulten"])
                             for mode in mode_links)
                primitive = sum(float(mode_links[mode][index]["primitive_F"])
                                for mode in mode_links)
                all_links.append({
                    "corridor_id": source["corridor_id"], "origin": source["origin"],
                    "destination": source["destination"], "mode": "all_transit",
                    "hulten": hulten, "primitive_F": primitive,
                    "traditional_gain_pct": hulten,
                    "extended_gain_pct": primitive,
                    "extended_minus_traditional_pct": primitive-hulten,
                })
                all_directed.append({
                    "edge_id": source["corridor_id"], "origin": source["origin"],
                    "destination": source["destination"], "mode": "all_transit",
                    "hulten": hulten, "primitive_F": primitive,
                })
            write_rows(root / "links_all_transit.csv", link_fields, all_links)
            write_rows(root / "directed_all_transit.csv",
                       directed_fields, all_directed)

            write_rows(
                root / "routes_all_transit.csv",
                ["route_name", "mode", "primitive_F", "extended_gain_pct"],
                [{"route_name": f"Route {index}", "mode": mode,
                  "primitive_F": 0.01*index, "extended_gain_pct": 0.01*index}
                 for index, mode in enumerate(
                     ("bus", "rail", "ferry", "bus"), start=1)])
            sensitivity = []
            for mode in ("bus", "rail", "ferry", "all_transit"):
                for eta in (0.75, 0.90, 1.099, 1.25, 1.40):
                    sensitivity.append({
                        "mode": mode, "eta": eta,
                        "mean_extended_gain_pct": 0.01*eta,
                        "spearman_vs_eta_1_099": 1-0.02*abs(eta-1.099),
                    })
            write_rows(
                root / "eta_sensitivity.csv",
                ["mode", "eta", "mean_extended_gain_pct",
                 "spearman_vs_eta_1_099"],
                sensitivity)

            geography = os.environ.get("SEATTLE_TEST_GEOGRAPHY_ROOT")
            outputs = MODULE.build_figures(
                root, nodes, Path(geography) if geography else None)
            self.assertEqual(len(outputs), 12)
            self.assertTrue(all(path.is_file() for path in outputs))
            first_hashes = {
                path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                for path in outputs
            }
            repeated_outputs = MODULE.build_figures(
                root, nodes, Path(geography) if geography else None)
            repeated_hashes = {
                path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                for path in repeated_outputs
            }
            self.assertEqual(first_hashes, repeated_hashes)
            png = mpimg.imread(root / "seattle_transit_welfare_map.png")
            self.assertEqual(png.shape[-1], 4)


if __name__ == "__main__":
    unittest.main()
