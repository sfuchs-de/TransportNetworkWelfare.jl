# Examples

## Urban commuting

`examples/urban_toy` is the self-contained one-mode Allen-Arkolakis regression
fixture. `examples/urban_multimodal` adds road and transit, alternative routes,
edge congestion, and terminal congestion. `examples/seattle_urban` converts
the published 217-location Seattle inputs after verifying their hashes. The
Seattle source archive remains external to Git.

The repository includes eight examples with different purposes. All use the
same public API and TOML schema.

| Example | Purpose | Size | Typical command | External data |
| --- | --- | ---: | --- | --- |
| `toy` | Fast API, modal, terminal, and decomposition smoke test | 3 nodes, 6 directed edges | `decompose examples/toy/config.toml` | None |
| `braess` | Flexible- versus fixed-route comparison | 4 nodes, 10 directed edges | `decompose examples/braess/config.toml` | None |
| `cow` | Mechanism-rich 3D synthetic geography and ranking comparison | 30 nodes, 72 directed edges | `decompose examples/cow/config.toml` | None |
| `sioux_falls` | Standard traffic-network adaptation with heterogeneous BPR elasticities | 24 nodes, 76 directed edges | `decompose examples/sioux_falls/config_extended.toml` | On-demand academic-use files |
| `urban_toy` | Allen-Arkolakis residence-workplace IFT and exact-hat checks | 3 nodes, 6 directed edges | `analyze examples/urban_toy/config.toml` | None |
| `urban_multimodal` | Shared recursive road/transit urban IFT | 4 nodes, 10 directed edges, 20 edge-modes | `decompose examples/urban_multimodal/config.toml` | None |
| `seattle_urban` | Published urban commuting application | 217 nodes, 1,384 directed edges | `analyze examples/seattle_urban/generated/config.toml` | External replication archive |
| `westeros_urban` | Synthetic urban application on fictional geography | Generated on demand | `analyze examples/westeros_urban/generated/config.toml` | Public ArcGIS queries |

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

## Seattle urban commuting

The 217-location Seattle replication for [Allen and
Arkolakis](https://academic.oup.com/restud/article-abstract/89/6/2911/6519332)
uses the package's separate urban closure with residential and workplace
distributions. Run `examples/seattle_urban/prepare.jl` after setting
`AA_REPLICATION_ROOT`. The adapter verifies the published hashes and does not
commit or download the 458 MB source archive. See [Urban commuting
model](urban.md) for the derivation and model boundary.

## Westeros urban commuting

The Westeros example uses CreativeCarto's public ArcGIS locations, roads, and
continent polygon. Those layers identify geography but do not provide
population, employment, or traffic. The example therefore constructs a fully
disclosed synthetic baseline: location types determine residence and workplace
weights, a doubly constrained gravity model balances commuting flows, and
shortest paths assign nonlocal commuters to a reduced road graph.

```bash
python3 examples/westeros_urban/prepare.py
julia --project=. bin/tnw.jl validate examples/westeros_urban/generated/config.toml
julia --project=. bin/tnw.jl analyze examples/westeros_urban/generated/config.toml
python3 examples/westeros_urban/plot.py
```

The source responses are hash-pinned but remain outside Git because the ArcGIS
item does not list a reuse license. The generated summary records every network,
gravity, and economic-mass assumption. Results illustrate the urban model and
are not empirical claims about the fictional economy.
