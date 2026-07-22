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

## All-vertex mesh equilibrium

The larger variant assigns a model location to every PLY vertex and turns every
mesh edge into a reciprocal physical road link. It therefore contains 2,903
locations, 8,706 physical links, and 17,412 directed arcs. The builder assigns
positive labor and income to every location and uses symmetric matrix scaling
to construct model-consistent value flows. Each location's outgoing traffic is
75 percent of its income share, and incoming and outgoing traffic balance to
machine precision.

```bash
python examples/cow/prepare_surface.py
julia --project=. examples/cow/build_mesh_network.jl
julia --project=. bin/tnw.jl analyze-edge-local \
  examples/cow/config_mesh_edge_local.toml
python plots/network_example.py \
  examples/cow/mesh_data/nodes.csv examples/cow/mesh_data/edge_modes.csv \
  examples/cow/mesh_output/welfare_physical.csv \
  examples/cow/mesh_output/cow-mesh-welfare.png \
  --metric primitive_F --transparent --three-dimensional \
  --surface-ply examples/cow/assets/cow.ply \
  --elevation-angle 14 --azimuth -70
```

`analyze-edge-local` solves the local spatial-equilibrium adjoint using a sparse
Jacobian core and an exact low-rank correction. It evaluates the same
Proposition-2 primitive-cost derivative for every mesh link. It does not report
the route-consistent realized-friction diagnostic or construct the `FM` and
`FR` decomposition closures: their dense OD-by-edge incidence object would
require approximately 1.09 TiB for this mesh. This is a calibrated sufficient-
statistic equilibrium around the generated baseline, not a global level
solution recovered from productivity and amenity primitives.
