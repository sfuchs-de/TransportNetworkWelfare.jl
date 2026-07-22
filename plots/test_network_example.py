import csv
import importlib.util
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).with_name("network_example.py")
SPEC = importlib.util.spec_from_file_location("network_example", MODULE_PATH)
network_example = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(network_example)


class NetworkExamplePlotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.nodes = self.root / "nodes.csv"
        self.edges = self.root / "edges.csv"
        self.results = self.root / "results.csv"
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

    def test_missing_link_fails(self):
        with self.results.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(("physical_link_id", "primitive_F"))
            writer.writerow(("AB", 0.2))
        with self.assertRaises(ValueError):
            network_example.plot_network(
                self.nodes, self.edges, self.results, self.root / "network.png")


if __name__ == "__main__":
    unittest.main()
