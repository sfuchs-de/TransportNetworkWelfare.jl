import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "examples" / "westeros" / "prepare.py"
SPEC = importlib.util.spec_from_file_location("westeros_prepare", MODULE_PATH)
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)

from plots import westeros_example


class WesterosBuilderTests(unittest.TestCase):
    def test_polygon_and_hole(self):
        geometry = {
            "type": "Polygon",
            "coordinates": [
                [[0, 0], [4, 0], [4, 4], [0, 4], [0, 0]],
                [[1, 1], [2, 1], [2, 2], [1, 2], [1, 1]],
            ],
        }
        self.assertTrue(PREPARE.point_in_geometry((3, 3), geometry))
        self.assertFalse(PREPARE.point_in_geometry((1.5, 1.5), geometry))
        self.assertFalse(PREPARE.point_in_geometry((5, 5), geometry))

    def test_trade_margins_and_symmetry(self):
        activity = [0.4, 0.35, 0.25]
        distances = [[0, 1, 2], [1, 0, 1], [2, 1, 0]]
        matrix, error, symmetry_error, _ = PREPARE.trade_matrix(
            activity, distances, decay=2.0, local_weight=2.0)
        self.assertLess(error, 1e-10)
        self.assertLess(symmetry_error, 1e-10)
        for index, value in enumerate(activity):
            self.assertAlmostEqual(sum(matrix[index]), value, places=11)
        for index, value in enumerate(activity):
            self.assertAlmostEqual(sum(row[index] for row in matrix), value, places=11)

    def test_routing_conservation(self):
        activity = [0.5, 0.3, 0.2]
        distances = [[0, 1, 2], [1, 0, 1], [2, 1, 0]]
        trade, _, _, _ = PREPARE.trade_matrix(
            activity, distances, decay=2.0, local_weight=2.0)
        traffic, active = PREPARE.route_trade(trade, [(0, 1), (1, 2)], distances)
        self.assertEqual(active, [(0, 1), (1, 2)])
        outgoing = [0.0, 0.0, 0.0]
        incoming = [0.0, 0.0, 0.0]
        for (origin, destination), flow in traffic.items():
            outgoing[origin] += flow
            incoming[destination] += flow
        error = max(abs(outgoing[i] - incoming[i]) for i in range(3))
        self.assertLess(error, 1e-10)

    def test_visual_labels_and_ranks(self):
        self.assertEqual(
            westeros_example.display_name({
                "name": "",
                "location_type": "Castle",
            }),
            "Unnamed castle",
        )
        rows = westeros_example.rank_rows([
            {"physical_link_id": "a", "hulten": 2.0, "primitive_F": 1.0},
            {"physical_link_id": "b", "hulten": 1.0, "primitive_F": 3.0},
        ])
        by_id = {row["physical_link_id"]: row for row in rows}
        self.assertEqual(by_id["a"]["traditional_rank"], 1)
        self.assertEqual(by_id["a"]["extended_rank"], 2)
        self.assertEqual(by_id["b"]["rank_change"], 1)


if __name__ == "__main__":
    unittest.main()
