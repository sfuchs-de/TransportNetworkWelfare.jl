import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).with_name("network_example.py")
SPEC = importlib.util.spec_from_file_location("network_example", MODULE_PATH)
network_example = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(network_example)

PREPARE_PATH = MODULE_PATH.parents[1] / "examples" / "cow" / "prepare_surface.py"
PREPARE_SPEC = importlib.util.spec_from_file_location("prepare_surface", PREPARE_PATH)
prepare_surface = importlib.util.module_from_spec(PREPARE_SPEC)
PREPARE_SPEC.loader.exec_module(prepare_surface)


class NetworkExamplePlotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.nodes = self.root / "nodes.csv"
        self.edges = self.root / "edges.csv"
        self.results = self.root / "results.csv"
        self.surface = self.root / "surface.ply"
        self.nodes.write_text(
            "node_id,labor,income,longitude,latitude,elevation\n"
            "A,1,2,0,0,-0.5\nB,1,1,1,1,0.5\nC,1,1,2,0,0\n",
            encoding="utf-8",
        )
        self.edges.write_text(
            "edge_id,physical_link_id,origin,destination,mode,flow\n"
            "AB,AB,A,B,road,0.1\nBA,AB,B,A,road,0.1\n"
            "BC,BC,B,C,road,0.1\nCB,BC,C,B,road,0.1\n",
            encoding="utf-8",
        )
        self.results.write_text(
            "physical_link_id,primitive_F,hulten\nAB,0.2,0.1\nBC,0.05,0.1\n",
            encoding="utf-8",
        )
        self.surface.write_text(
            "ply\nformat ascii 1.0\n"
            "element vertex 4\nproperty float32 x\nproperty float32 y\n"
            "property float32 z\nelement face 4\n"
            "property list uint8 int32 vertex_indices\nend_header\n"
            "0 0 0\n1 0 0\n0 1 0\n0 0 1\n"
            "3 0 1 2\n3 0 1 3\n3 0 2 3\n3 1 2 3\n",
            encoding="ascii",
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_transparent_png_and_pdf(self):
        for extension in ("png", "pdf"):
            output = self.root / f"network-a.{extension}"
            duplicate = self.root / f"network-b.{extension}"
            network_example.plot_network(
                self.nodes, self.edges, self.results, output,
                label_top=1, transparent=True,
            )
            network_example.plot_network(
                self.nodes, self.edges, self.results, duplicate,
                label_top=1, transparent=True,
            )
            self.assertTrue(output.is_file())
            self.assertGreater(output.stat().st_size, 1000)
            self.assertEqual(output.read_bytes(), duplicate.read_bytes())

    def test_deterministic_three_dimensional_cow_render(self):
        for extension in ("png", "pdf"):
            output = self.root / f"cow-3d-a.{extension}"
            duplicate = self.root / f"cow-3d-b.{extension}"
            for path in (output, duplicate):
                network_example.plot_network(
                    self.nodes, self.edges, self.results, path,
                    label_top=0, transparent=True, three_dimensional=True,
                    cow_surface=True, elevation_angle=14.0, azimuth=-70.0,
                )
            self.assertTrue(output.is_file())
            self.assertGreater(output.stat().st_size, 1000)
            self.assertEqual(output.read_bytes(), duplicate.read_bytes())

    def test_deterministic_ply_surface_render(self):
        output = self.root / "cow-ply-a.png"
        duplicate = self.root / "cow-ply-b.png"
        for path in (output, duplicate):
            network_example.plot_network(
                self.nodes, self.edges, self.results, path,
                transparent=True, three_dimensional=True,
                surface_ply=self.surface,
            )
        self.assertGreater(output.stat().st_size, 1000)
        self.assertEqual(output.read_bytes(), duplicate.read_bytes())

    def test_invalid_ply_fails(self):
        self.surface.write_text("ply\nformat binary_little_endian 1.0\nend_header\n")
        with self.assertRaises(ValueError):
            network_example.plot_network(
                self.nodes, self.edges, self.results, self.root / "bad.png",
                three_dimensional=True, surface_ply=self.surface,
            )

    def test_cached_surface_hash_is_required(self):
        payload = self.surface.read_bytes()
        expected = hashlib.sha256(payload).hexdigest()
        manifest = self.root / "sources.toml"
        manifest.write_text(
            "[mesh]\nurl = \"https://example.invalid/cow.ply\"\n"
            f"sha256 = \"{expected}\"\n",
            encoding="utf-8",
        )
        self.assertEqual(
            prepare_surface.prepare(
                self.surface, offline=True, manifest=manifest),
            self.surface,
        )
        self.surface.write_bytes(payload+b"corrupt")
        with self.assertRaises(ValueError):
            prepare_surface.prepare(
                self.surface, offline=True, manifest=manifest)
        self.surface.unlink()
        with self.assertRaises(FileNotFoundError):
            prepare_surface.prepare(
                self.surface, offline=True, manifest=manifest)

    def test_policy_result_subset_is_allowed(self):
        with self.results.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(("physical_link_id", "primitive_F"))
            writer.writerow(("AB", 0.2))
        output = self.root / "network.png"
        network_example.plot_network(
            self.nodes, self.edges, self.results, output)
        self.assertGreater(output.stat().st_size, 1000)

    def test_unknown_result_link_fails(self):
        self.results.write_text(
            "physical_link_id,primitive_F\nUNKNOWN,0.2\n",
            encoding="utf-8",
        )
        with self.assertRaises(ValueError):
            network_example.plot_network(
                self.nodes, self.edges, self.results, self.root / "network.png")

    def test_urban_nodes_and_geojson_geometry(self):
        urban_nodes = self.root / "urban_nodes.csv"
        urban_nodes.write_text(
            "node_id,residents,employment,longitude,latitude\n"
            "A,0.3,0.2,0,0\nB,0.4,0.5,1,1\nC,0.3,0.3,2,0\n",
            encoding="utf-8",
        )
        links = self.root / "links.geojson"
        links.write_text(json.dumps({
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "properties": {"physical_link_id": "AB"},
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [[0, 0], [0.4, 0.7], [1, 1]],
                    },
                },
                {
                    "type": "Feature",
                    "properties": {"physical_link_id": "BC"},
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [[1, 1], [1.6, 0.7], [2, 0]],
                    },
                },
            ],
        }), encoding="utf-8")
        basemap = self.root / "basemap.geojson"
        basemap.write_text(json.dumps({
            "type": "Polygon",
            "coordinates": [[[-0.2, -0.2], [2.2, -0.2], [2.2, 1.2],
                             [-0.2, 1.2], [-0.2, -0.2]]],
        }), encoding="utf-8")
        output = self.root / "urban-map.png"
        network_example.plot_network(
            urban_nodes, self.edges, self.results, output,
            link_geometry=links, basemap=basemap, transparent=True,
        )
        self.assertGreater(output.stat().st_size, 1000)


if __name__ == "__main__":
    unittest.main()
