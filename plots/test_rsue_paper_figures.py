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
            "domestic_efficient": "0.00102",
            "spatial_no_congestion": "0.0011",
            "extended": "0.0007",
            "boundary_adjustment": "0.00002",
            "spatial_externality_adjustment": "0.00008",
            "direct_externality_adjustment": "-0.0002",
            "market_access_propagation_adjustment": "0.00028",
            "road_congestion_adjustment": "-0.0001",
            "terminal_congestion_adjustment": "0.0",
            "pass_through_adjustment": "-0.0003",
            "spatial_adjustment": "0.0001",
            "road_congestion_policy_adjustment": "-0.0004",
            "congestion_pass_through_change": "-0.0004",
            "net_change": "-0.0003",
        }]

    def test_summary_reconstructs_policy_relevant_welfare_path(self):
        summary = FIGURES.decomposition_summary(self.rows())
        self.assertAlmostEqual(summary["spatial_no_congestion"], 0.0011)
        self.assertAlmostEqual(summary["extended"], 0.0007)
        self.assertAlmostEqual(
            summary["boundary_adjustment"]+
            summary["spatial_externality_adjustment"]+
            summary["road_congestion_policy_adjustment"],
            summary["net_change"],
        )
        self.assertAlmostEqual(
            summary["direct_externality_adjustment"]+
            summary["market_access_propagation_adjustment"],
            summary["spatial_externality_adjustment"],
        )

    def test_summary_fails_on_identity_error(self):
        rows = self.rows()
        rows[0]["extended"] = "0.00075"
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


class SensitivityFigureTests(unittest.TestCase):
    def test_headline_paths_render_and_extension_rows_are_ignored(self):
        self.assertEqual(
            FIGURES.PAPER_SENSITIVITY_PARAMETERS,
            ("alpha", "beta", "net_dispersion", "lambda_road"),
        )
        rows = []
        for parameter in (
                "alpha", "beta", "net_dispersion", "eta", "lambda_road",
                "lambda_terminal"):
            for index, value in enumerate((0.5, 1.0, 1.5)):
                rows.append({
                    "parameter": parameter,
                    "value": str(value),
                    "mean_physical_gain_pct": str(0.0002+index*0.00001),
                    "spearman_vs_baseline": str(0.99+0.005*index),
                    "is_baseline": "true" if index == 1 else "false",
                })
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "sensitivity"
            FIGURES.sensitivity_figure(rows, output)
            self.assertTrue(output.with_suffix(".pdf").is_file())
            self.assertTrue(output.with_suffix(".png").is_file())


if __name__ == "__main__":
    unittest.main()
