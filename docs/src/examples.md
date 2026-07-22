# Examples

The repository includes four examples with different purposes. All use the
same public API and TOML schema.

| Example | Purpose | Size | Typical command | External data |
| --- | --- | ---: | --- | --- |
| `toy` | Fast API, modal, terminal, and decomposition smoke test | 3 nodes, 6 directed edges | `decompose examples/toy/config.toml` | None |
| `braess` | Flexible- versus fixed-route comparison | 4 nodes, 10 directed edges | `decompose examples/braess/config.toml` | None |
| `cow` | Mechanism-rich 3D synthetic geography and ranking comparison | 30 nodes, 72 directed edges | `decompose examples/cow/config.toml` | None |
| `sioux_falls` | Standard traffic-network adaptation with heterogeneous BPR elasticities | 24 nodes, 76 directed edges | `decompose examples/sioux_falls/config_extended.toml` | On-demand academic-use files |

Replace `decompose ...` above with
`julia --project=. bin/tnw.jl decompose ...` at the repository root. The
self-contained examples ordinarily finish in under a minute after Julia has
precompiled the package. Runtime depends on Julia version and hardware.

## Braess-style network

The Braess-style example has two parallel routes and a connector. It produces
a nonzero route wedge by comparing flexible routing with the `FR` closure that
holds baseline physical-edge use fixed. It is not a Wardrop assignment and does
not claim to reproduce Braess's paradox.

## Sioux Falls

Sioux Falls is the standard small transportation benchmark: 24 nodes, 76
directed arcs, and 38 reciprocal physical links. The builder pins the upstream
TransportationNetworks commit and four file hashes. The source files are not
redistributed because their terms limit use to academic research.

```bash
julia --project=. examples/sioux_falls/prepare.jl
julia --project=. bin/tnw.jl validate examples/sioux_falls/config_extended.toml
julia --project=. bin/tnw.jl decompose examples/sioux_falls/config_extended.toml
```

The published OD and assigned-flow files have small, matching node imbalances.
The builder averages production with attraction and reciprocal link flows,
records the raw imbalances, and verifies exact accounting after balancing. It
then computes each link's local BPR log elasticity. This imports an assigned
baseline into the package's recursive-routing model; it does not re-solve the
original Wardrop problem.

## Cow network

The cow-shaped example uses original deterministic three-dimensional node
geometry. Alternative neck routes connect a high-activity head and body. Its
traffic-only and extended top-five rankings differ, and the exact route and
congestion channels explain the change. The plotting script can add either an
original procedural surface or a hash-verified, on-demand PLY mesh behind the
network. The third-party mesh is not distributed with the repository.

Render any example from validated CSV outputs:

```bash
python examples/cow/prepare_surface.py
python plots/network_example.py \
  examples/cow/data/nodes.csv examples/cow/data/edge_modes.csv \
  examples/cow/output/decomposition_physical.csv examples/cow/output/cow.pdf \
  --metric primitive_F --label-top 5 --transparent \
  --three-dimensional --surface-ply examples/cow/assets/cow.ply \
  --elevation-angle 14 --azimuth -70
```

The plotting script writes PDF or transparent PNG output and adds no title or
subtitle. `elevation` is plotting metadata and does not enter the model. Use
`--cow-surface` in place of `--surface-ply ...` for the offline procedural
fallback.

### All 2,903 mesh vertices

An optional larger variant makes every PLY vertex a model location and every
mesh edge a bidirectional road link. The generated baseline has 2,903 locations,
8,706 physical links, and 17,412 directed arcs. Positive body/head activity
weights provide labor and income. Symmetric matrix scaling constructs balanced
value flows with a common traffic-to-income ratio.

```bash
python examples/cow/prepare_surface.py
julia --project=. examples/cow/build_mesh_network.jl
julia --project=. bin/tnw.jl analyze-edge-local \
  examples/cow/config_mesh_edge_local.toml
```

The sparse edge-local command computes the primitive-cost spatial-equilibrium
derivative for every link. It does not report the route-consistent realized-
friction diagnostic or build the `FM` and `FR` closures: the dense OD-by-edge
incidence matrix would occupy about 1.09 TiB. The generated baseline is a
calibrated sufficient-statistic equilibrium rather than a global level solution
from exogenous productivity and amenity primitives.

## Why Seattle is deferred

The 217-location Seattle replication for [Allen and
Arkolakis](https://academic.oup.com/restud/article-abstract/89/6/2911/6519332)
uses a different urban closure with separate residential and workplace labor
allocations and commuting flows. Those objects are not inputs to the current
economic-geography model. A faithful Seattle example therefore requires an
urban solver and a separate schema; the 458 MB replication archive is neither
downloaded nor bundled here.
