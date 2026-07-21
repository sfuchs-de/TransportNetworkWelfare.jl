from __future__ import annotations

import csv
import hashlib
import json
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import build_port_overlay as overlay  # noqa: E402
import fetch_port_trade as fetcher  # noqa: E402


def record(flow: str, month: str, port: str, port_name: str, country: str,
           country_name: str, value: int) -> dict[str, str | int]:
    return {
        "flow": flow,
        "month": month,
        "PORT": port,
        "PORT_NAME": port_name,
        "CTY_CODE": country,
        "CTY_NAME": country_name,
        "TRADE_VAL_MO": value,
        "AIR_VAL_MO": 0,
        "VES_VAL_MO": value,
        "CNT_VAL_MO": value,
        "AIR_WGT_MO": 0,
        "VES_WGT_MO": value,
        "CNT_WGT_MO": value,
    }


class CensusPortPipelineTests(unittest.TestCase):
    def test_query_never_places_key_in_public_url(self) -> None:
        private, public = fetcher.query_urls("imports", "2017-01", "secret-value")
        self.assertIn("secret-value", private)
        self.assertNotIn("secret-value", public)
        self.assertNotIn("key=", public)

    def test_fetch_failure_does_not_chain_secret_url(self) -> None:
        key = "test-key-that-must-not-leak"
        private, _ = fetcher.query_urls("imports", "2017-01", key)
        failure = urllib.error.URLError(private)
        with mock.patch.object(fetcher.urllib.request, "urlopen", side_effect=failure):
            with self.assertRaises(RuntimeError) as caught:
                fetcher.fetch(private, retries=1, timeout=1)
        self.assertIsNone(caught.exception.__cause__)
        self.assertIsNone(caught.exception.__context__)
        self.assertNotIn(key, str(caught.exception))

    def test_api_parser_filters_aggregate_rows_and_renames_value(self) -> None:
        header = [
            "PORT", "PORT_NAME", "CTY_CODE", "CTY_NAME", "GEN_VAL_MO",
            *fetcher.MEASURES, "time",
        ]
        payload = [
            header,
            ["0101", "PORT ONE", "1010", "COUNTRY ONE", "7", "0", "7", "7", "0", "1", "1", "2017-01"],
            ["0000", "TOTAL FOR ALL PORTS", "1010", "COUNTRY ONE", "7", "0", "7", "7", "0", "1", "1", "2017-01"],
        ]
        rows = fetcher.parse_response(json.dumps(payload).encode(), "imports", "2017-01")
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["TRADE_VAL_MO"], 7)
        self.assertNotIn("GEN_VAL_MO", rows[0])

    def test_balanced_directional_overlay_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = root / "cache"
            cache.mkdir()
            ports = root / "ports.csv"
            ports.write_text(
                "census_port_code,census_port_name,rsue_node_id,rsue_port_group\n"
                "0101,PORT ONE,1,Port One\n"
                "0201,PORT TWO,2,Port Two\n",
                encoding="utf-8",
            )
            regions = root / "regions.csv"
            regions.write_text(
                "foreign_region,rsue_node_id,schedule_c_min,schedule_c_max\n"
                "North America,229,1000,1999\n"
                "South and Central America,230,2000,3999\n",
                encoding="utf-8",
            )
            values = {
                "imports": ((80, 20), (20, 80)),
                "exports": ((20, 80), (80, 20)),
            }
            for flow, matrix in values.items():
                rows = []
                for port, name, row in zip(("0101", "0201"), ("PORT ONE", "PORT TWO"), matrix):
                    rows.append(record(flow, "2017-01", port, name, "1010", "COUNTRY ONE", row[0]))
                    rows.append(record(flow, "2017-01", port, name, "2010", "COUNTRY TWO", row[1]))
                path = cache / f"census_{flow}_port_country_2017-01.csv.gz"
                path.write_bytes(fetcher.csv_gzip_bytes(rows))

            output = root / "output"
            first = overlay.build_overlay(
                cache, ports, regions, "2017-01", "2017-01", "CNT_VAL_MO", output
            )
            output_path = output / "census_port_region_overlay.csv"
            first_hash = hashlib.sha256(output_path.read_bytes()).hexdigest()
            second = overlay.build_overlay(
                cache, ports, regions, "2017-01", "2017-01", "CNT_VAL_MO", output
            )
            second_hash = hashlib.sha256(output_path.read_bytes()).hexdigest()

            self.assertEqual(first_hash, second_hash)
            self.assertEqual(first["output_sha256"], second["output_sha256"])
            self.assertLess(first["max_node_balance_residual"], 1e-12)
            self.assertAlmostEqual(first["model_share_total"], 1.0)
            with output_path.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            direction_totals: dict[str, float] = {}
            for row in rows:
                direction_totals[row["direction"]] = (
                    direction_totals.get(row["direction"], 0.0)
                    + float(row["model_share"])
                )
            self.assertAlmostEqual(direction_totals["foreign_to_domestic"], 0.5)
            self.assertAlmostEqual(direction_totals["domestic_to_foreign"], 0.5)
            self.assertNotEqual(
                [row["raw_direction_share"] for row in rows if row["direction"] == "foreign_to_domestic"],
                [row["raw_direction_share"] for row in rows if row["direction"] == "domestic_to_foreign"],
            )

    def test_positive_trade_outside_declared_schedule_c_ranges_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            cache = root / "cache"
            cache.mkdir()
            ports = root / "ports.csv"
            ports.write_text(
                "census_port_code,census_port_name,rsue_node_id,rsue_port_group\n"
                "0101,PORT ONE,1,Port One\n",
                encoding="utf-8",
            )
            regions = root / "regions.csv"
            regions.write_text(
                "foreign_region,rsue_node_id,schedule_c_min,schedule_c_max\n"
                "North America,229,1000,1999\n",
                encoding="utf-8",
            )
            for flow in ("imports", "exports"):
                rows = [record(flow, "2017-01", "0101", "PORT ONE", "9001", "OUTSIDE", 1)]
                path = cache / f"census_{flow}_port_country_2017-01.csv.gz"
                path.write_bytes(fetcher.csv_gzip_bytes(rows))
            with self.assertRaisesRegex(ValueError, "outside the declared Schedule C ranges"):
                overlay.build_overlay(
                    cache, ports, regions, "2017-01", "2017-01", "CNT_VAL_MO", root / "out"
                )


if __name__ == "__main__":
    unittest.main()
