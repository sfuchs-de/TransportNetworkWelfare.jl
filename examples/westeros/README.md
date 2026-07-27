# Westeros economic-geography example

This example applies the package's economic-geography model to the public
Westeros locations and roads in CreativeCarto's ArcGIS web map. It is a
synthetic calibration, not an empirical reconstruction of the Westerosi
economy. The ArcGIS layers identify geography but contain no labor, income,
trade, or traffic observations.

The builder:

1. verifies hash-pinned ArcGIS responses and selects occupied locations inside
   the Westeros polygon;
2. joins road components separated by at most 10 km and retains the largest
   resulting component;
3. keeps settlements within 50 km of that road system and forms a sparse
   settlement graph from road-network distances;
4. assigns common labor and income shares from location-type weights;
5. balances symmetric bilateral trade values to that economic-activity margin
   and routes nonlocal trade over the settlement graph; and
6. checks the resulting node-level trade-flow identity before writing model
   inputs.

Run from the repository root:

```bash
python3 examples/westeros/prepare.py
julia --project=. bin/tnw.jl validate examples/westeros/generated/config.toml
julia --project=. bin/tnw.jl decompose examples/westeros/generated/config.toml
julia --project=. examples/westeros/verify.jl
python3 examples/westeros/plot.py
```

The final command requires the packages in `plots/requirements.txt`. It writes
PDF and transparent PNG versions of a geographic welfare map and comparison
scatter, together with a ranked-link table. The map retains the full Westeros
polygon and source-road network. Evaluated model links follow the source-road
paths used to construct their costs; those paths can overlap because several
reduced links may use the same road segment.

All thresholds and calibration choices are recorded in
`generated/network_summary.json`. Downloaded and derived data remain ignored by
Git because the ArcGIS item lists no reuse license. See `sources.toml` for the
item identity, URLs, hashes, and feature counts.

The example uses the paper's economic-geography parameters, choice logsum, and
edge-local road-congestion elasticity. It exercises the full closure
decomposition. Its welfare rankings illustrate the package; they are not claims
about the fictional economy.
