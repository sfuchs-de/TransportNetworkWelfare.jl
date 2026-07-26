import csv
import hashlib
import importlib.util
import json
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
    def test_common_welfare_width_scale(self):
        MODULE.np.testing.assert_allclose(
            MODULE.welfare_widths([0.0, 0.064], 0.064),
            [0.35, 3.50])
        MODULE.np.testing.assert_allclose(
            MODULE.welfare_legend_levels(0.0647),
            [0.005, 0.025, 0.05])
        with self.assertRaises(ValueError):
            MODULE.welfare_widths([0.0], 0.0)

    def test_gtfs_distinguishes_link_from_streetcar(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_rows(
                root / "calendar.txt",
                ["service_id", "monday", "tuesday", "wednesday", "thursday",
                 "friday", "saturday", "sunday", "start_date", "end_date"],
                [{"service_id": "weekday", "monday": 1, "tuesday": 1,
                  "wednesday": 1, "thursday": 1, "friday": 1,
                  "saturday": 0, "sunday": 0, "start_date": "20170601",
                  "end_date": "20170630"}])
            write_rows(
                root / "calendar_dates.txt",
                ["service_id", "date", "exception_type"], [])
            write_rows(
                root / "routes.txt",
                ["route_id", "route_short_name", "route_long_name",
                 "route_type"], [
                    {"route_id": "link", "route_short_name": "LINK",
                     "route_long_name": "", "route_type": 0},
                    {"route_id": "streetcar", "route_short_name": "Stcr SLU",
                     "route_long_name": "", "route_type": 0},
                ])
            write_rows(
                root / "trips.txt",
                ["route_id", "service_id", "trip_id"], [
                    {"route_id": "link", "service_id": "weekday",
                     "trip_id": "link_trip"},
                    {"route_id": "streetcar", "service_id": "weekday",
                     "trip_id": "streetcar_trip"},
                ])
            write_rows(
                root / "stops.txt",
                ["stop_id", "stop_lon", "stop_lat", "location_type"], [
                    {"stop_id": "one", "stop_lon": -122.35,
                     "stop_lat": 47.58, "location_type": 0},
                    {"stop_id": "two", "stop_lon": -122.30,
                     "stop_lat": 47.62, "location_type": 0},
                    {"stop_id": "three", "stop_lon": -122.25,
                     "stop_lat": 47.57, "location_type": 0},
                ])
            write_rows(
                root / "stop_times.txt",
                ["trip_id", "stop_id", "stop_sequence"], [
                    {"trip_id": "link_trip", "stop_id": "one",
                     "stop_sequence": 1},
                    {"trip_id": "link_trip", "stop_id": "two",
                     "stop_sequence": 2},
                    {"trip_id": "streetcar_trip", "stop_id": "two",
                     "stop_sequence": 1},
                    {"trip_id": "streetcar_trip", "stop_id": "three",
                     "stop_sequence": 2},
                ])
            classes = MODULE.gtfs_rail_corridor_classes(root, {
                "1": (-122.35, 47.58),
                "2": (-122.30, 47.62),
                "3": (-122.25, 47.57),
            })
            self.assertEqual(classes[("1", "2")], {"subway"})
            self.assertEqual(classes[("2", "3")], {"streetcar"})

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
            for offset, mode in enumerate(
                    ("road", "bus", "rail", "ferry"), start=1):
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
            transit_modes = ("bus", "rail", "ferry")
            for index in range(2):
                source = mode_links["bus"][index]
                hulten = sum(float(mode_links[mode][index]["hulten"])
                             for mode in transit_modes)
                primitive = sum(float(mode_links[mode][index]["primitive_F"])
                                for mode in transit_modes)
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
            self.assertEqual(len(outputs), 14)
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
            combined_png = mpimg.imread(
                root / "seattle_combined_road_transit_welfare.png")
            self.assertEqual(combined_png.shape[-1], 4)
            self.assertLess(combined_png[..., -1].min(), 1.0)

            edge_modes = root / "edge_modes.csv"
            edge_rows = []
            for mode in ("road", "bus", "rail", "ferry"):
                for row in mode_directed[mode]:
                    edge_rows.append({
                        "edge_id": row["edge_id"],
                        "origin": row["origin"],
                        "destination": row["destination"],
                        "mode": mode,
                        "flow": 10.0,
                    })
            write_rows(
                edge_modes,
                ["edge_id", "origin", "destination", "mode", "flow"],
                edge_rows)
            gtfs = root / "gtfs"
            gtfs.mkdir()
            write_rows(
                gtfs / "calendar.txt",
                ["service_id", "monday", "tuesday", "wednesday", "thursday",
                 "friday", "saturday", "sunday", "start_date", "end_date"],
                [{"service_id": "weekday", "monday": 1, "tuesday": 1,
                  "wednesday": 1, "thursday": 1, "friday": 1,
                  "saturday": 0, "sunday": 0, "start_date": "20170601",
                  "end_date": "20170630"}])
            write_rows(
                gtfs / "calendar_dates.txt",
                ["service_id", "date", "exception_type"], [])
            write_rows(
                gtfs / "routes.txt", ["route_id", "route_type"], [
                    {"route_id": "bus", "route_type": 3},
                    {"route_id": "rail", "route_type": 0},
                    {"route_id": "ferry", "route_type": 4},
                ])
            write_rows(
                gtfs / "trips.txt",
                ["route_id", "service_id", "trip_id", "shape_id"], [
                    {"route_id": mode, "service_id": "weekday",
                     "trip_id": mode, "shape_id": mode}
                    for mode in ("bus", "rail", "ferry")
                ])
            shape_rows = []
            for offset, mode in enumerate(("bus", "rail", "ferry")):
                shape_rows.extend([
                    {"shape_id": mode, "shape_pt_lat": 47.58+0.01*offset,
                     "shape_pt_lon": -122.35,
                     "shape_pt_sequence": 1},
                    {"shape_id": mode, "shape_pt_lat": 47.62-0.01*offset,
                     "shape_pt_lon": -122.25,
                     "shape_pt_sequence": 2},
                ])
            write_rows(
                gtfs / "shapes.txt",
                ["shape_id", "shape_pt_lat", "shape_pt_lon",
                 "shape_pt_sequence"], shape_rows)
            observed_roads = root / "roads.geojson"
            observed_roads.write_text(json.dumps({
                "type": "FeatureCollection",
                "features": [{
                    "type": "Feature",
                    "properties": {},
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [[-122.35, 47.58], [-122.25, 47.57]],
                    },
                }],
            }), encoding="utf-8")
            detailed_outputs = MODULE.build_figures(
                root, nodes, Path(geography) if geography else None,
                edge_modes_path=edge_modes, gtfs_root=gtfs,
                observed_roads=observed_roads)
            self.assertEqual(len(detailed_outputs), 20)
            aa_png = mpimg.imread(root / "seattle_aa_mode_welfare.png")
            self.assertEqual(aa_png.shape[-1], 4)


if __name__ == "__main__":
    unittest.main()
