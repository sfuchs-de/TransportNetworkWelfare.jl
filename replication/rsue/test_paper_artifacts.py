#!/usr/bin/env python3

import csv
import sys
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from build_cbsa_crosswalk import (  # noqa: E402
    compact_link_label,
    tex_escape,
    write_top_link_outputs,
)


class PaperArtifactTests(unittest.TestCase):
    def test_compact_link_label(self):
        self.assertEqual(
            compact_link_label(
                "Los Angeles-Long Beach-Anaheim, CA",
                "Riverside-San Bernardino-Ontario, CA",
            ),
            "Los Angeles-Long Beach-Anaheim--Riverside-San Bernardino-Ontario",
        )

    def test_tex_escape(self):
        self.assertEqual(tex_escape("A&B_1"), r"A\&B\_1")

    def test_writes_cross_ranked_csv_and_tex(self):
        comparison = {
            "count_per_measure": 2,
            "traditional": [
                {
                    "rank": 1,
                    "physical_link_id": "a_b",
                    "traditional_rank": 1,
                    "extended_rank": 2,
                    "hulten_elasticity": 0.002,
                    "primitive_elasticity": 0.001,
                },
                {
                    "rank": 2,
                    "physical_link_id": "b_c",
                    "traditional_rank": 2,
                    "extended_rank": 1,
                    "hulten_elasticity": 0.0015,
                    "primitive_elasticity": 0.0012,
                },
            ],
            "extended": [
                {
                    "rank": 1,
                    "physical_link_id": "b_c",
                    "traditional_rank": 2,
                    "extended_rank": 1,
                    "hulten_elasticity": 0.0015,
                    "primitive_elasticity": 0.0012,
                },
                {
                    "rank": 2,
                    "physical_link_id": "a_b",
                    "traditional_rank": 1,
                    "extended_rank": 2,
                    "hulten_elasticity": 0.002,
                    "primitive_elasticity": 0.001,
                },
            ],
        }
        labels = [
            {
                "physical_link_id": "a_b",
                "cbsa_name_a": "Alpha-One, ZZ",
                "cbsa_name_b": "Beta-Two, ZZ",
                "verified_label": "Alpha-One, ZZ--Beta-Two, ZZ",
            },
            {
                "physical_link_id": "b_c",
                "cbsa_name_a": "Beta-Two, ZZ",
                "cbsa_name_b": "Gamma-Three, ZZ",
                "verified_label": "Beta-Two, ZZ--Gamma-Three, ZZ",
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            csv_path = Path(directory) / "top.csv"
            tex_path = Path(directory) / "top.tex"
            write_top_link_outputs(comparison, labels, csv_path, tex_path)
            with csv_path.open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 4)
            self.assertEqual(rows[0]["extended_rank"], "2")
            self.assertEqual(rows[2]["traditional_rank"], "2")
            tex = tex_path.read_text()
            self.assertIn(r"\begin{revblock}", tex)
            self.assertIn(r"\color{revcol}", tex)
            self.assertIn(r"\caption{\rev{Top-ranked", tex)
            self.assertIn("Panel A. Ranked by the traditional", tex)
            self.assertIn("Panel B. Ranked by the extended", tex)
            self.assertIn("Alpha-One--Beta-Two", tex)


if __name__ == "__main__":
    unittest.main()
