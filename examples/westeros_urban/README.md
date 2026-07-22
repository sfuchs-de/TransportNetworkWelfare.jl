# Westeros urban commuting example

This example applies the Allen--Arkolakis urban welfare derivative to the
public Westeros locations and roads in CreativeCarto's ArcGIS web map. It is a
synthetic calibration, not an empirical reconstruction of Westerosi commuting.
The ArcGIS layers identify geography but contain no population, employment, or
traffic observations.

The builder:

1. verifies hash-pinned ArcGIS responses and selects occupied locations inside
   the Westeros polygon;
2. joins road components separated by at most 10 km and retains the largest
   resulting component;
3. keeps settlements within 50 km of that road system and forms a sparse
   settlement graph from road-network distances;
4. assigns residence mass from location-type weights and concentrates
   employment by raising those weights to the power 1.25;
5. balances a gravity commuting matrix to those two margins and routes every
   nonlocal trip over the settlement graph; and
6. checks the resulting node-level flow-conservation identity before writing
   model inputs.

Run from the repository root:

```bash
python3 examples/westeros_urban/prepare.py
julia --project=. bin/tnw.jl validate examples/westeros_urban/generated/config.toml
julia --project=. bin/tnw.jl analyze examples/westeros_urban/generated/config.toml
julia --project=. examples/westeros_urban/verify_finite_differences.jl
python3 examples/westeros_urban/plot.py
python3 examples/westeros_urban/plot.py --corridors
```

The final command requires the packages in `plots/requirements.txt`. It writes
PDF and transparent PNG figures without internal titles. The default figure
draws the model's reduced settlement links. `--corridors` follows the source
roads used to construct each link's cost; those paths can overlap because
several reduced links may use the same road segment.

All thresholds and calibration choices are recorded in
`generated/network_summary.json`. Downloaded and derived data remain ignored by
Git because the ArcGIS item lists no reuse license. See `sources.toml` for the
item identity, URLs, hashes, and feature counts.

The example uses the same `theta`, `alpha`, `beta`, and congestion calibration
as the Seattle adapter. Its welfare rankings illustrate the package; they are
not claims about the fictional economy.
