# Examples

The repository includes four examples with different purposes. All use the
same public API and TOML schema.

| Example | Purpose | Size | Typical command | External data |
| --- | --- | ---: | --- | --- |
| `toy` | Fast API, modal, terminal, and decomposition smoke test | 3 nodes, 6 directed edges | `decompose examples/toy/config.toml` | None |
| `braess` | Flexible- versus fixed-route comparison | 4 nodes, 10 directed edges | `decompose examples/braess/config.toml` | None |
| `cow` | Mechanism-rich synthetic geography and ranking comparison | 30 nodes, 72 directed edges | `decompose examples/cow/config.toml` | None |
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

The cow-shaped example is original deterministic geometry. Alternative neck
routes connect a high-activity head and body. Its traffic-only and extended
top-five rankings differ, and the exact route and congestion channels explain
the change. The shape is data, not a copied image or mesh.

Render any example from validated CSV outputs:

```bash
python plots/network_example.py \
  examples/cow/data/nodes.csv examples/cow/data/edge_modes.csv \
  examples/cow/output/decomposition_physical.csv examples/cow/output/cow.pdf \
  --metric primitive_F --label-top 5 --transparent
```

The plotting script writes PDF or transparent PNG output and adds no title or
subtitle.

## Why Seattle is deferred

The 217-location Seattle replication for [Allen and
Arkolakis](https://academic.oup.com/restud/article-abstract/89/6/2911/6519332)
uses a different urban closure with separate residential and workplace labor
allocations and commuting flows. Those objects are not inputs to the current
economic-geography model. A faithful Seattle example therefore requires an
urban solver and a separate schema; the 458 MB replication archive is neither
downloaded nor bundled here.
