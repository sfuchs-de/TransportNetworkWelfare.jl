# Examples

## Urban commuting

`examples/urban_toy` is the self-contained one-mode Allen-Arkolakis regression
fixture. `examples/urban_multimodal` adds road and transit, alternative routes,
edge congestion, and terminal congestion. `examples/seattle_urban` diagnoses
the published 217-location Seattle inputs after verifying their hashes.
`examples/seattle_multimodal` constructs a separate candidate from LODES
commuters, ACS commute-mode shares, and historical GTFS service. The Seattle
sources remain external to Git.

The repository includes nine examples with different purposes. All use the
same public API and TOML schema.

| Example | Purpose | Size | Typical command | External data |
| --- | --- | ---: | --- | --- |
| `toy` | Fast API, modal, terminal, and decomposition smoke test | 3 nodes, 6 directed edges | `decompose examples/toy/config.toml` | None |
| `braess` | Flexible- versus fixed-route comparison | 4 nodes, 10 directed edges | `decompose examples/braess/config.toml` | None |
| `cow` | Mechanism-rich 3D synthetic geography and ranking comparison | 30 nodes, 72 directed edges | `decompose examples/cow/config.toml` | None |
| `sioux_falls` | Standard traffic-network adaptation with heterogeneous BPR elasticities | 24 nodes, 76 directed edges | `decompose examples/sioux_falls/config_extended.toml` | On-demand academic-use files |
| `urban_toy` | Allen-Arkolakis residence-workplace IFT and exact-hat checks | 3 nodes, 6 directed edges | `analyze examples/urban_toy/config.toml` | None |
| `urban_multimodal` | Shared recursive road/transit urban IFT | 4 nodes, 10 directed edges, 20 edge-modes | `decompose examples/urban_multimodal/config.toml` | None |
| `seattle_urban` | Published road-input accounting diagnostic | 217 nodes, 1,384 directed road edges | `validate examples/seattle_urban/generated/config.toml` | External replication archive |
| `seattle_multimodal` | Seattle road/transit candidate on a common commuter population | 217 nodes; generated edge-modes | `analyze examples/seattle_multimodal/generated/config.toml` | Replication archive, ACS API/cache, pinned 2017 GTFS |
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

The 217-location Seattle exercise in [Allen and
Arkolakis](https://academic.oup.com/restud/article-abstract/89/6/2911/6519332)
combines 2017 LODES residence/workplace data with 2016 HPMS/HERE road inputs.
It contains no route-level public-transit network or ridership input. The
hash-verified `seattle_urban` adapter preserves those inputs as a diagnostic,
but it fails the strict recursive-flow accounting gate because AADT and LODES
measure different traffic populations.

The `seattle_multimodal` adapter instead routes the same LODES commuter matrix
over road and transit networks. Origin transit shares come from 2017 ACS table
B08301, while the exact June 2017 King County GTFS version supplies service,
mode labels, and paths. This construction passes the accounting gate by design.
It is a candidate model rather than a reproduction: GTFS does not contain
ridership, ACS does not identify routes, and the modal elasticity must be
supplied explicitly. The builder records transit-path failures, source and
output hashes, and all transformations. See its README and [Urban commuting
model](urban.md) for the data contract and model boundary.

The exact-2017 workflow has a credential-safe acquisition command and produces
separate road, bus, rail/streetcar, and ferry policy configurations. The baseline
uses `ChoiceLogsum(1.099)`, transferred from the economic-geography
application and labeled as such rather than as a Seattle estimate. It evaluates
one-percent edge-mode improvements, reciprocal corridor sums, and coordinated
GTFS route-corridor bundles. The public Mobility Database copy of the exact
June 2017 TransitFeeds archive is hash-pinned; current service is never
substituted for that feed.

The artifact builder also produces Allen--Arkolakis-style maps of the observed
and constructed networks, mode-specific welfare effects on a common scale, and
traditional versus extended transit effects. These maps use the full 2017 GTFS
shape geometry for the observed network and the model's edge-mode support for
the constructed network.

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
