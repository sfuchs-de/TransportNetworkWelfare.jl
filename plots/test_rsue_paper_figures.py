import importlib.util
from pathlib import Path
import tempfile
import unittest

import matplotlib.pyplot as plt
import numpy as np


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "rsue_paper_figures", HERE / "rsue_paper_figures.py"
)
FIGURES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIGURES)


class MapFigureTests(unittest.TestCase):
    def test_map_assets_are_loadable(self):
        figure, axis = plt.subplots()
        FIGURES.add_us_context(axis)
        self.assertGreaterEqual(len(axis.images), 1)
        self.assertGreaterEqual(len(axis.collections), 1)
        plt.close(figure)

    def test_map_figure_writes_pdf_and_png(self):
        rows = [
            {
                "longitude_a": "-118.2", "latitude_a": "34.1",
                "longitude_b": "-112.1", "latitude_b": "33.5",
                "primitive_F": "0.0002",
            },
            {
                "longitude_a": "-90.2", "latitude_a": "38.6",
                "longitude_b": "-87.6", "latitude_b": "41.9",
                "primitive_F": "0.0004",
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "map"
            FIGURES.map_figure(rows, "primitive_F", "Welfare elasticity", output)
            for suffix in (".pdf", ".png"):
                rendered = output.with_suffix(suffix)
                self.assertTrue(rendered.is_file())
                self.assertGreater(rendered.stat().st_size, 10_000)

    def test_shared_map_norm_uses_common_zero_based_scale(self):
        rows = [
            {"hulten": "0.0004", "primitive_F": "0.0002"},
            {"hulten": "0.0008", "primitive_F": "0.0003"},
        ]
        norm = FIGURES.shared_map_norm(
            rows, ("hulten", "primitive_F"), scale=1.0e4,
        )
        self.assertEqual(norm.vmin, 0.0)
        self.assertGreater(norm.vmax, 3.0)
        self.assertLess(norm.vmax, 8.1)


class DecompositionFigureTests(unittest.TestCase):
    def test_cumulative_ladder_reconstructs_extended_effect(self):
        rows = [{
            "hulten": "0.0010",
            "primitive_externality": "0.0002",
            "primitive_propagation": "-0.0001",
            "primitive_edge": "0.00005",
            "primitive_pass_through": "0.00015",
            "primitive_F": "0.0007",
        }]
        ladder = FIGURES.decomposition_ladder_rows(rows)[0]
        self.assertTrue(np.isclose(ladder["ladder_traditional"], 0.0010))
        self.assertTrue(np.isclose(ladder["ladder_externalities"], 0.0008))
        self.assertTrue(np.isclose(ladder["ladder_propagation"], 0.0009))
        self.assertTrue(np.isclose(ladder["ladder_congestion"], 0.00085))
        self.assertTrue(np.isclose(ladder["ladder_extended"], 0.0007))

    def test_cumulative_ladder_fails_on_identity_error(self):
        rows = [{
            "hulten": "0.0010",
            "primitive_externality": "0.0002",
            "primitive_propagation": "-0.0001",
            "primitive_edge": "0.00005",
            "primitive_pass_through": "0.00015",
            "primitive_F": "0.0008",
        }]
        with self.assertRaisesRegex(ValueError, "does not reconstruct"):
            FIGURES.decomposition_ladder_rows(rows)


if __name__ == "__main__":
    unittest.main()
