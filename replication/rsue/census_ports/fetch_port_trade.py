#!/usr/bin/env python3
"""Download a resumable Census port-by-country trade panel.

The API key is read only from ``CENSUS_API_KEY``. Stored queries and metadata
never contain the credential.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


BASE_URL = "https://api.census.gov/data/timeseries/intltrade"
MEASURES = (
    "AIR_VAL_MO",
    "VES_VAL_MO",
    "CNT_VAL_MO",
    "AIR_WGT_MO",
    "VES_WGT_MO",
    "CNT_WGT_MO",
)
IDENTIFIERS = ("PORT", "PORT_NAME", "CTY_CODE", "CTY_NAME")


def month_range(start: str, end: str) -> list[str]:
    """Return inclusive YYYY-MM months after validating the endpoints."""
    try:
        start_date = datetime.strptime(start, "%Y-%m")
        end_date = datetime.strptime(end, "%Y-%m")
    except ValueError as exc:
        raise ValueError("months must use YYYY-MM") from exc
    if start_date > end_date:
        raise ValueError("start month must not follow end month")
    months: list[str] = []
    year, month = start_date.year, start_date.month
    while (year, month) <= (end_date.year, end_date.month):
        months.append(f"{year:04d}-{month:02d}")
        month += 1
        if month == 13:
            year += 1
            month = 1
    return months


def api_key() -> str:
    key = os.environ.get("CENSUS_API_KEY", "").strip()
    if not key:
        raise SystemExit("Set CENSUS_API_KEY in the environment before downloading.")
    return key


def value_field(flow: str) -> str:
    if flow == "imports":
        return "GEN_VAL_MO"
    if flow == "exports":
        return "ALL_VAL_MO"
    raise ValueError(f"unsupported flow: {flow}")


def query_urls(flow: str, month: str, key: str) -> tuple[str, str]:
    fields = (*IDENTIFIERS, value_field(flow), *MEASURES)
    public = {"get": ",".join(fields), "time": month}
    private = {**public, "key": key}
    endpoint = f"{BASE_URL}/{flow}/porths"
    return (
        endpoint + "?" + urllib.parse.urlencode(private),
        endpoint + "?" + urllib.parse.urlencode(public),
    )


def fetch(url: str, retries: int = 5, timeout: int = 90) -> bytes:
    request = urllib.request.Request(
        url, headers={"User-Agent": "TransportNetworkWelfare.jl/0.1"}
    )
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError):
            if attempt + 1 == retries:
                break
            time.sleep(2**attempt)
    # Raise outside the handler so urllib's credential-bearing request URL is
    # absent from both the message and chained exception context.
    raise RuntimeError("Census API request failed after retries")


def parse_response(body: bytes, flow: str, month: str) -> list[dict[str, str | int]]:
    payload = json.loads(body.decode("utf-8"))
    if not isinstance(payload, list) or len(payload) < 2:
        raise ValueError(f"empty Census response for {flow} {month}")
    header = [str(value) for value in payload[0]]
    expected_value = value_field(flow)
    required = {*IDENTIFIERS, expected_value, *MEASURES}
    missing = sorted(required - set(header))
    if missing:
        raise ValueError(f"Census response missing columns: {', '.join(missing)}")

    records: list[dict[str, str | int]] = []
    seen: set[tuple[str, str]] = set()
    for values in payload[1:]:
        if len(values) != len(header):
            raise ValueError(f"malformed Census row for {flow} {month}")
        source = dict(zip(header, values))
        port = str(source["PORT"]).zfill(4)
        country = str(source["CTY_CODE"]).zfill(4)
        if not (port.isdigit() and len(port) == 4):
            continue
        if not (country.isdigit() and len(country) == 4):
            continue
        if country.startswith("00"):
            continue
        if "TOTAL" in str(source["PORT_NAME"]).upper():
            continue
        if "TOTAL" in str(source["CTY_NAME"]).upper():
            continue
        key = (port, country)
        if key in seen:
            raise ValueError(f"duplicate port-country key for {flow} {month}: {key}")
        seen.add(key)

        record: dict[str, str | int] = {
            "flow": flow,
            "month": month,
            "PORT": port,
            "PORT_NAME": str(source["PORT_NAME"]),
            "CTY_CODE": country,
            "CTY_NAME": str(source["CTY_NAME"]),
        }
        for field in (expected_value, *MEASURES):
            raw = source.get(field, "0")
            try:
                value = int(raw or 0)
            except (TypeError, ValueError) as exc:
                raise ValueError(f"invalid {field}={raw!r} for {flow} {month}") from exc
            if value < 0:
                raise ValueError(f"negative {field} for {flow} {month}")
            record["TRADE_VAL_MO" if field == expected_value else field] = value
        records.append(record)
    records.sort(key=lambda row: (str(row["PORT"]), str(row["CTY_CODE"])))
    return records


def csv_gzip_bytes(records: list[dict[str, str | int]]) -> bytes:
    fields = ("flow", "month", *IDENTIFIERS, "TRADE_VAL_MO", *MEASURES)
    text = io.StringIO(newline="")
    writer = csv.DictWriter(text, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(records)
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", mtime=0) as zipped:
        zipped.write(text.getvalue().encode("utf-8"))
    return buffer.getvalue()


def gzip_bytes(data: bytes) -> bytes:
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb", mtime=0) as zipped:
        zipped.write(data)
    return buffer.getvalue()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, data: bytes) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def cached_metadata(
    flow: str, month: str, data_path: Path, raw_path: Path, metadata_path: Path
) -> dict | None:
    if not (data_path.exists() and raw_path.exists() and metadata_path.exists()):
        return None
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("flow") != flow or metadata.get("month") != month:
        raise ValueError(f"cached metadata identity mismatch: {metadata_path}")
    data_hash = sha256_bytes(data_path.read_bytes())
    raw_hash = sha256_bytes(raw_path.read_bytes())
    if data_hash != metadata.get("sha256"):
        raise ValueError(f"cached data hash mismatch: {data_path}")
    if raw_hash != metadata.get("raw_response_sha256"):
        raise ValueError(f"cached response hash mismatch: {raw_path}")
    return {**metadata, "status": "cached"}


def download_month(
    flow: str, month: str, key: str, output: Path, force: bool = False
) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    stem = f"census_{flow}_port_country_{month}"
    data_path = output / f"{stem}.csv.gz"
    raw_path = output / f"{stem}.response.json.gz"
    metadata_path = output / f"{stem}.json"
    if not force:
        cached = cached_metadata(flow, month, data_path, raw_path, metadata_path)
        if cached is not None:
            return cached

    private_url, public_url = query_urls(flow, month, key)
    body = fetch(private_url)
    records = parse_response(body, flow, month)
    encoded = csv_gzip_bytes(records)
    raw_encoded = gzip_bytes(body)
    atomic_write(data_path, encoded)
    atomic_write(raw_path, raw_encoded)
    metadata = {
        "flow": flow,
        "month": month,
        "status": "downloaded",
        "query_without_key": public_url,
        "downloaded_at_utc": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat(),
        "rows": len(records),
        "trade_value_usd": sum(int(row["TRADE_VAL_MO"]) for row in records),
        "vessel_value_usd": sum(int(row["VES_VAL_MO"]) for row in records),
        "container_value_usd": sum(int(row["CNT_VAL_MO"]) for row in records),
        "sha256": sha256_bytes(encoded),
        "raw_response_sha256": sha256_bytes(raw_encoded),
        "data_file": data_path.name,
        "raw_response_file": raw_path.name,
    }
    atomic_write(
        metadata_path,
        (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode("utf-8"),
    )
    return metadata


def write_inventory(output: Path) -> None:
    records = []
    for path in sorted(output.glob("census_*_port_country_????-??.json")):
        records.append(json.loads(path.read_text(encoding="utf-8")))
    if not records:
        return
    fields = sorted({key for record in records for key in record})
    text = io.StringIO(newline="")
    writer = csv.DictWriter(text, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(sorted(records, key=lambda row: (row["flow"], row["month"])))
    atomic_write(output / "inventory.csv", text.getvalue().encode("utf-8"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", default="2017-01")
    parser.add_argument("--end", default="2017-12")
    parser.add_argument(
        "--flows",
        nargs="+",
        choices=("imports", "exports"),
        default=("imports", "exports"),
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--sleep", type=float, default=0.15)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.sleep < 0:
        raise SystemExit("--sleep must be nonnegative")
    key = api_key()
    months = month_range(args.start, args.end)
    total = len(months) * len(args.flows)
    completed = 0
    for flow in args.flows:
        for month in months:
            result = download_month(flow, month, key, args.output, args.force)
            completed += 1
            print(f"[{completed}/{total}] {flow} {month}: {result['status']}")
            time.sleep(args.sleep)
    write_inventory(args.output)
    print(f"Wrote Census source cache to {args.output.resolve()}")


if __name__ == "__main__":
    main()
