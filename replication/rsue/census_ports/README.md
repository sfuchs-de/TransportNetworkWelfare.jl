# Census port-trade layer

This directory builds the directional foreign-water layer used by the current
RSUE paper configuration from the U.S. Census International Trade API. The
legacy frozen replication remains available separately.

## What was already in RSUE

The legacy `bilateral_port_sparse.csv` appears to be a 2017 container-import
allocation across 20 RSUE gateway nodes and six foreign regions. Several cells
match the current Census `CNT_VAL_MO` series nearly exactly. The legacy loader then
symmetrizes that matrix, so imports and exports have identical geography.

The paper layer keeps imports and exports separate:

- imports run from a foreign-region node to a U.S. gateway;
- exports run from a U.S. gateway to a foreign-region node;
- Schedule D port codes are mapped explicitly in `port_crosswalk.csv`;
- Schedule C codes are mapped by the declared geographic ranges in
  `foreign_regions.csv`.

The source endpoints and variable definitions are documented by the Census
Bureau:

- <https://api.census.gov/data/timeseries/intltrade/imports/porths.html>
- <https://api.census.gov/data/timeseries/intltrade/exports/porths.html>
- <https://www.census.gov/foreign-trade/schedules/c/countrycodes.html>
- <https://www.census.gov/foreign-trade/schedules/d/distcode.html>

## Refresh the source cache

The downloader uses only the Python standard library. The API key is read from
the environment and is never written to a query manifest or output file.

```bash
export CENSUS_API_KEY=...
python3 replication/rsue/census_ports/fetch_port_trade.py \
  --start 2017-01 \
  --end 2017-12 \
  --output /absolute/path/to/census-port-cache
```

Each month writes a deterministic compressed CSV, a compressed raw response,
and metadata containing sanitized URLs and hashes. Existing complete files are
hash-checked and reused.

## Build the overlay

```bash
python3 replication/rsue/census_ports/build_port_overlay.py \
  --cache-root /absolute/path/to/census-port-cache \
  --start 2017-01 \
  --end 2017-12 \
  --measure CNT_VAL_MO \
  --output-dir replication/rsue/census_ports/derived/2017
```

`CNT_VAL_MO` is the default because it matches the economic object in the
legacy port layer: containerized vessel value. The checked-in aggregate covers
93.79 percent of Census containerized imports and 93.62 percent of
containerized exports in 2017.

## Why the RAS projection is required

Raw port-level imports and exports do not satisfy the manuscript model's
location-level balanced-flow identity. Inserting them directly would make the
incoming and outgoing market-access stocks disagree and invalidate the current
IFT derivation.

The builder therefore normalizes imports and exports separately, averages their
U.S.-port margins and foreign-region margins, and RAS-projects each directional
matrix onto those common margins. It does not add support to zero cells. The
model then assigns one half of the fixed foreign-water mode mass to each
direction. Raw values, coverage, projection distance, source hashes, and the
node-balance residual remain in `census_port_region_diagnostics.json`.

This is a transparent balanced-trade projection, not a claim that measured
imports equal measured exports. A model with trade deficits would require a
different equilibrium closure and a new theory audit.

## Run the paper specification

The restricted domestic RSUE inputs remain external:

```bash
export RSUE_DATA_ROOT=/absolute/path/to/rsue/Input
julia --project=. bin/tnw.jl replicate-rsue \
  replication/rsue/rsue_paper_choice_edge_census_2017.toml
```

The paper configuration preserves the frozen road, rail, barge, mode-weight, and
foreign-node-padding transformations. It replaces only the foreign-water
distribution, activates all four transport modes, uses the negative-power
choice logsum, and keeps congestion edge-local in the main application. The
aggregate foreign-water weight remains the legacy value.

`expected_summary.toml` records the checked-in overlay hash, source coverage,
network dimensions, candidate result moments, and deterministic output hashes.
`../rsue_legacy_ports_all_modes_control.toml` provides the like-for-like control:
it changes only the port layer while holding the component-CES convention and
all-four-mode basis fixed.

In that comparison, the directional Census layer raises the mean road-policy
elasticity by 0.0073 percent; the arc-level correlation is 0.999994. Thus the
data extension materially improves the interpretation of foreign flows but has
almost no effect on the current road rankings or average welfare derivative.

## Tests

```bash
python3 -m unittest discover \
  -s replication/rsue/census_ports -p 'test_*.py'
```

The tests cover credential sanitization, API parsing, deterministic output,
directional accounting, RAS balance, and unsupported Schedule C codes. Julia
tests independently validate the checked-in overlay and, when
`RSUE_DATA_ROOT` is set, run the complete candidate decomposition.
