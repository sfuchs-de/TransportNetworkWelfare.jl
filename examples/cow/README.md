# Cow network

This original synthetic network shows that the package accepts arbitrary
three-dimensional economic geographies for visualization. The body and head
carry most economic activity.
Two routes through the neck connect them, so improvements at the neck combine
traffic, congestion, route adjustment, and market-access exposure.

The node geometry and the translucent procedural cow surface were written for
this package. They do not use the Mathematica `ExampleData` cow mesh or any
external image asset. The `elevation` column supplies the third node coordinate;
it does not enter the economic model.

```bash
julia --project=. bin/tnw.jl decompose examples/cow/config.toml
python plots/network_example.py \
  examples/cow/data/nodes.csv examples/cow/data/edge_modes.csv \
  examples/cow/output/decomposition_physical.csv examples/cow/output/cow-welfare.png \
  --metric primitive_F --transparent --three-dimensional --cow-surface \
  --elevation-angle 14 --azimuth -70
```

The example is pedagogical rather than empirical. In particular, its flows
are model-ready value-flow shares, not observed vehicle counts. Under the
included calibration, `H3_H4` enters the extended top five but not the
traffic-only top five. Its nonzero road-scarcity and route-scarcity components
show how the closure decomposition accounts for that change.
