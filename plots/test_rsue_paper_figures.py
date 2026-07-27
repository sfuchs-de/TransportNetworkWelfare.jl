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


class ScatterFigureTests(unittest.TestCase):
    def test_selected_labels_do_not_overlap(self):
        rows = [
            {"physical_link_id": "6_10"},
            {"physical_link_id": "6_11"},
            {"physical_link_id": "185_188"},
            {"physical_link_id": "184_200"},
        ]
        x = np.asarray([18.7, 14.5, 8.6, 13.4])
        y = np.asarray([8.7, 8.1, 6.6, 5.5])
        figure, axis = plt.subplots(figsize=(4.8, 4.4))
        annotations = FIGURES.add_scatter_labels(
            axis, rows, x, y, labels={},
        )
        axis.set_xlim(0.0, 20.0)
        axis.set_ylim(0.0, 20.0)
        figure.canvas.draw()
        renderer = figure.canvas.get_renderer()
        boxes = [
            annotation.get_bbox_patch().get_window_extent(renderer)
            for annotation in annotations
        ]
        for left_index, left in enumerate(boxes):
            for right in boxes[left_index+1:]:
                self.assertFalse(left.overlaps(right))
        plt.close(figure)


class DecompositionFigureTests(unittest.TestCase):
    @staticmethod
    def rows():
        return [{
            "traditional": "0.0010",
            "fixed_route": "0.0010",
            "flexible_efficient": "0.0010",
            "efficient_congestion": "0.0008",
            "spatial_equilibrium": "0.0011",
            "extended": "0.0007",
            "fixed_route_change": "0.0",
            "route_mode_change": "0.0",
            "congestion_change": "-0.0002",
            "spatial_externality_change": "0.0003",
            "pass_through_change": "-0.0004",
            "net_change": "-0.0003",
        }]

    def test_summary_reconstructs_nested_welfare_path(self):
        summary = FIGURES.decomposition_summary(self.rows())
        self.assertAlmostEqual(summary["fixed_route"], 0.001)
        self.assertAlmostEqual(summary["efficient_congestion"], 0.0008)
        self.assertAlmostEqual(summary["spatial_equilibrium"], 0.0011)
        self.assertAlmostEqual(summary["extended"], 0.0007)
        self.assertAlmostEqual(
            summary["fixed_route_change"]+summary["route_mode_change"]+
            summary["congestion_change"]+
            summary["spatial_externality_change"]+
            summary["pass_through_change"],
            summary["net_change"],
        )

    def test_summary_fails_on_identity_error(self):
        rows = self.rows()
        rows[0]["extended"] = "0.0008"
        with self.assertRaisesRegex(ValueError, "does not reconstruct"):
            FIGURES.decomposition_summary(rows)

    def test_figure_writes_transparent_pdf_and_png(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "decomposition"
            FIGURES.decomposition_figure(self.rows(), output)
            self.assertTrue(output.with_suffix(".pdf").is_file())
            png = output.with_suffix(".png")
            self.assertTrue(png.is_file())
            rendered = plt.imread(png)
            self.assertEqual(rendered.shape[-1], 4)
            self.assertLess(float(rendered[..., 3].min()), 1.0)


if __name__ == "__main__":
    unittest.main()
