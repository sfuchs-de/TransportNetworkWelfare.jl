# Cow network

This original synthetic network shows that the package accepts arbitrary
three-dimensional economic geographies for visualization. The body and head
carry most economic activity.
Two routes through the neck connect them, so improvements at the neck combine
traffic, congestion, route adjustment, and market-access exposure.

The node geometry and the translucent procedural fallback surface were written
for this package. The `elevation` column supplies the third node coordinate; it
does not enter the economic model. For a more detailed surface, the plotting
script can use John Burkardt's 2,903-vertex PLY example as an optional,
hash-verified download. The mesh is not distributed with this repository; see
[`THIRD_PARTY.md`](THIRD_PARTY.md) for its source and license notice.

```bash
julia --project=. bin/tnw.jl decompose examples/cow/config.toml
python examples/cow/prepare_surface.py
python plots/network_example.py \
  examples/cow/data/nodes.csv examples/cow/data/edge_modes.csv \
  examples/cow/output/decomposition_physical.csv examples/cow/output/cow-welfare.png \
  --metric primitive_F --transparent --three-dimensional \
  --surface-ply examples/cow/assets/cow.ply \
  --elevation-angle 14 --azimuth -70
```

Use `--cow-surface` instead of `--surface-ply ...` for the fully distributable
procedural fallback.

The example is pedagogical rather than empirical. In particular, its flows
are model-ready value-flow shares, not observed vehicle counts. Under the
included calibration, `H3_H4` enters the extended top five but not the
traffic-only top five. Its nonzero road-scarcity and route-scarcity components
show how the closure decomposition accounts for that change.
