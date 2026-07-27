from pathlib import Path
import tempfile
import unittest

import numpy as np

try:
    from plots import figure_style as style
except ModuleNotFoundError:
    import figure_style as style

import matplotlib.image as mpimg
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[1]


class FigureStyleTests(unittest.TestCase):
    def test_welfare_scales_are_ordered_and_zero_centered_when_signed(self):
        positive, positive_cmap = style.welfare_norm([0.1, 0.4])
        signed, signed_cmap = style.welfare_norm([-0.2, 0.1])
        self.assertEqual(positive_cmap, "viridis")
        self.assertEqual(positive.vmin, 0.0)
        self.assertEqual(signed_cmap.name, "tnw_orange_blue")
        self.assertAlmostEqual(signed.vmin, -0.2)
        self.assertAlmostEqual(signed.vmax, 0.2)

    def test_semantic_labels_do_not_expose_internal_column_names(self):
        self.assertEqual(
            style.metric_label("hulten"),
            "Traditional approach: welfare elasticity",
        )
        self.assertEqual(
            style.metric_label("primitive_F"),
            "Extended approach: welfare elasticity",
        )

    def test_correlations_fail_cleanly_for_a_constant_series(self):
        pearson, spearman = style.correlations([1, 1, 1], [1, 2, 3])
        self.assertTrue(np.isnan(pearson))
        self.assertTrue(np.isnan(spearman))

    def test_pair_output_is_deterministic_and_transparent(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            figure, axis = plt.subplots(figsize=(2.4, 1.8))
            axis.plot([0, 1], [0, 1], color=style.BLUE)
            style.style_axis(axis, grid_axis="both")
            paths = style.save_figure_pair(figure, output, "test")
            first = {path.name: path.read_bytes() for path in paths}

            figure, axis = plt.subplots(figsize=(2.4, 1.8))
            axis.plot([0, 1], [0, 1], color=style.BLUE)
            style.style_axis(axis, grid_axis="both")
            paths = style.save_figure_pair(figure, output, "test")
            second = {path.name: path.read_bytes() for path in paths}
            self.assertEqual(first, second)
            raster = mpimg.imread(output / "test.png")
            self.assertEqual(raster.shape[-1], 4)
            self.assertLess(float(np.min(raster[..., -1])), 1.0)

    def test_generators_use_shared_style_and_avoid_rainbow_scales(self):
        generators = [
            ROOT / "plots" / "hulten_vs_welfare.py",
            ROOT / "plots" / "decomposition_components.py",
            ROOT / "plots" / "network_example.py",
            ROOT / "plots" / "example_assets.py",
            ROOT / "plots" / "rsue_paper_figures.py",
            ROOT / "plots" / "seattle_transit_impacts.py",
            ROOT / "examples" / "westeros" / "plot.py",
        ]
        for path in generators:
            source = path.read_text(encoding="utf-8")
            self.assertIn("figure_style", source, path)
            self.assertNotIn('"turbo"', source, path)
            self.assertNotIn('"coolwarm"', source, path)


if __name__ == "__main__":
    unittest.main()
