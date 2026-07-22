import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "examples" / "westeros_urban" / "prepare.py"
SPEC = importlib.util.spec_from_file_location("westeros_prepare", MODULE_PATH)
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)


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

    def test_gravity_margins(self):
        residence = [0.4, 0.35, 0.25]
        workplace = [0.3, 0.45, 0.25]
        distances = [[0, 1, 2], [1, 0, 1], [2, 1, 0]]
        matrix, error, _ = PREPARE.gravity_matrix(
            residence, workplace, distances, decay=2.0, local_weight=2.0)
        self.assertLess(error, 1e-10)
        for index, value in enumerate(residence):
            self.assertAlmostEqual(sum(matrix[index]), value, places=11)
        for index, value in enumerate(workplace):
            self.assertAlmostEqual(sum(row[index] for row in matrix), value, places=11)

    def test_routing_conservation(self):
        residence = [0.5, 0.3, 0.2]
        workplace = [0.2, 0.4, 0.4]
        distances = [[0, 1, 2], [1, 0, 1], [2, 1, 0]]
        commuting, _, _ = PREPARE.gravity_matrix(
            residence, workplace, distances, decay=2.0, local_weight=2.0)
        traffic, active = PREPARE.route_commuting(commuting, [(0, 1), (1, 2)], distances)
        self.assertEqual(active, [(0, 1), (1, 2)])
        outgoing = [0.0, 0.0, 0.0]
        incoming = [0.0, 0.0, 0.0]
        for (origin, destination), flow in traffic.items():
            outgoing[origin] += flow
            incoming[destination] += flow
        error = max(abs(workplace[i] + outgoing[i] - residence[i] - incoming[i])
                    for i in range(3))
        self.assertLess(error, 1e-10)


if __name__ == "__main__":
    unittest.main()
