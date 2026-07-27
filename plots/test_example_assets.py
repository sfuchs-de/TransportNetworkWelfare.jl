from pathlib import Path
import tempfile
import unittest

try:
    from plots import example_assets
except ModuleNotFoundError:
    import example_assets

import matplotlib.image as mpimg


class ExampleAssetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="tnw-example-asset-tests-")
        cls.root = Path(cls.temporary.name)
        cls.figures = cls.root / "figures"
        cls.tables = cls.root / "tables"
        cls.outputs = example_assets.build_assets(
            example_assets.DEFAULT_DATA, cls.figures, cls.tables)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_every_example_has_the_same_asset_inventory(self):
        for stem in example_assets.EXAMPLE_STEMS:
            for suffix in (
                "welfare-map.pdf", "welfare-map.png",
                "scatter.pdf", "scatter.png",
                "comparison.pdf", "comparison.png",
            ):
                self.assertTrue((self.figures / f"{stem}-{suffix}").is_file())
            self.assertTrue((self.tables / f"{stem}-top-links.tex").is_file())
            self.assertTrue(
                (self.tables / f"{stem}-link-comparison.csv").is_file())

    def test_maps_and_scatters_are_transparent_and_dimensionally_consistent(self):
        shapes = {"welfare-map": set(), "scatter": set(), "comparison": set()}
        for stem in example_assets.EXAMPLE_STEMS:
            for kind in shapes:
                raster = mpimg.imread(self.figures / f"{stem}-{kind}.png")
                self.assertEqual(raster.shape[-1], 4)
                self.assertLess(float(raster[..., -1].min()), 1.0)
                shapes[kind].add(raster.shape)
        for kind, observed in shapes.items():
            self.assertEqual(len(observed), 1, (kind, observed))

    def test_tables_use_common_economic_labels_and_valid_ranks(self):
        for stem in example_assets.EXAMPLE_STEMS:
            tex = (self.tables / f"{stem}-top-links.tex").read_text()
            self.assertIn(
                "Traditional & Extended & Traditional rank & Extended rank",
                tex,
            )
            comparison = example_assets._read_rows(
                self.tables / f"{stem}-link-comparison.csv")
            link_count = len(comparison)
            for row in comparison:
                self.assertGreaterEqual(float(row["traditional_rank"]), 1)
                self.assertLessEqual(float(row["traditional_rank"]), link_count)
                self.assertGreaterEqual(float(row["extended_rank"]), 1)
                self.assertLessEqual(float(row["extended_rank"]), link_count)

    def test_renderer_is_byte_deterministic(self):
        before = {path.relative_to(self.root): path.read_bytes()
                  for path in self.outputs}
        outputs = example_assets.build_assets(
            example_assets.DEFAULT_DATA, self.figures, self.tables)
        after = {path.relative_to(self.root): path.read_bytes()
                 for path in outputs}
        self.assertEqual(before, after)

    def test_renderer_accepts_an_explicit_example_subset(self):
        with tempfile.TemporaryDirectory(
            prefix="tnw-example-subset-tests-"
        ) as temporary:
            root = Path(temporary)
            example_assets.build_assets(
                example_assets.DEFAULT_DATA,
                root / "figures",
                root / "tables",
                ("braess",),
            )
            self.assertTrue((root / "figures" / "braess-comparison.pdf").is_file())
            self.assertFalse((root / "figures" / "cow-comparison.pdf").exists())
            manifest = (
                root / "tables" / "example-assets.json"
            ).read_text(encoding="utf-8")
            self.assertIn('"braess"', manifest)
            self.assertNotIn('"cow"', manifest)


if __name__ == "__main__":
    unittest.main()
