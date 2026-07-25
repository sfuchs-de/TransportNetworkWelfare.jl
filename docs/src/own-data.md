# Use your own data

The generic adapter lets an application supply a network through two CSV files and one TOML configuration. It expects model-ready value flows, not arbitrary traffic observations.

## Initialize a project

From the package repository, create a project anywhere on the filesystem:

```bash
julia --project=. bin/tnw.jl init /path/to/my-network
```

The command writes `config.toml`, `data/nodes.csv`, `data/edge_modes.csv`, and a short project README. It refuses to overwrite a nonempty directory. The new project is independent of the package source and can be versioned separately.

## Define nodes

For `economic_geography`, each `nodes.csv` row needs a unique `node_id`,
positive labor, and positive income. For `urban_commuting`, replace those
columns with positive `residents` and `employment`. Coordinates are optional
metadata.

## Define edge-mode flows

Each `edge_modes.csv` row is one active mode on one directed physical edge. `edge_id` identifies the direction and is repeated across modes. `physical_link_id` groups the two opposite policy directions. Missing mode rows mean that the mode is unavailable. Listed flows must be strictly positive.

The route representation permits several modes on an ordered node pair, but not several physical edge IDs with the same origin and destination. Represent parallel physical routes using explicit intermediate route nodes.

## Choose compatible units

- `flow_conversion = "none"` means `flow` is already a share of world income.
- `flow_conversion = "divide_by_world_income"` means `flow` and node `income` use the same currency and price basis; the loader divides flows by total income.
- Vehicle counts, passenger trips, tons, and container counts are not value flows. Convert them outside the generic adapter using prices or values appropriate to the application and document that conversion.

At every node, the supplied baseline must satisfy

```math
\sum_{j,m}\Xi_{ij,m}=\sum_{j,m}\Xi_{ji,m}.
```

Together with node income, this identity gives the same market-access exposure stock from outgoing and incoming traffic. The loader checks it and fails if it does not hold. It does not balance, symmetrize, pad, impute, or mode-rescale generic inputs.

For the urban closure, the corresponding identity is

```math
l_i^F+\sum_{j,m}\Xi_{ij,m}
=l_i^R+\sum_{j,m}\Xi_{ji,m}.
```

The left side is workplace absorption plus outgoing route traffic; the right
side is residence supply plus incoming route traffic. Urban inputs that do not
satisfy this identity must be balanced explicitly before loading.

## Configure congestion and policy units

Edge congestion elasticities can be keyed by mode or read from a complete
edge-mode input column. The column specification is useful for local BPR
elasticities and other heterogeneous baselines:

```toml
[congestion]
specification = "edge"
source = "input_column"
column = "congestion_elasticity"
scale = 1.0
```

The selected column must be finite and nonnegative for every active row. It
cannot be combined with `[congestion.edge]`. Endpoint-terminal congestion
additionally requires `origin_terminal_id` and `destination_terminal_id` on
every affected mode row. Modes absent from a mode-level congestion table have
zero congestion in that channel.

For `policy.unit = "directed_arc"`, the package writes only directed-policy results. `physical_link` writes only bidirectional physical-link results, and `both` writes both files. A physical link must contain exactly two opposite policy-mode edges; its elasticity sums the simultaneous directional derivatives before normalizing the link multiplier.

## Validate and run

Use absolute paths when the data project is outside the package checkout:

```bash
julia --project=/path/to/TransportNetworkWelfare.jl \
  /path/to/TransportNetworkWelfare.jl/bin/tnw.jl validate /path/to/my-network/config.toml
julia --project=/path/to/TransportNetworkWelfare.jl \
  /path/to/TransportNetworkWelfare.jl/bin/tnw.jl decompose /path/to/my-network/config.toml
```

Validation checks schemas, identifiers, congestion-mode names, units, flow accounting, modal interiority, route contraction, policy pairing, and basic model regularity. It reports the approximate memory required by the dense fixed-route incidence object. `analyze` builds only the flexible full-model welfare closure. `decompose` additionally constructs the fixed-mode and fixed-route closures and is intended for moderate networks; its route-incidence memory grows as ``8N^2E`` bytes. The output directory is resolved relative to `config.toml`.

## Coordinated policy bundles

Sparse policy bundles combine directed primitive-cost derivatives without
re-solving the equilibrium:

```julia
entries = load_policy_bundles("route_bundles.csv")
results = bundle_welfare_effects(model, entries)
```

The CSV requires `bundle_id`, `edge_id`, `mode`, and a finite positive
`weight`. A model-level evaluation requires one mode matching the project's
policy mode. Duplicate components, missing edge-mode pairs, mixed modes, and
invalid weights fail before aggregation. A unit weight applies the configured
proportional primitive-cost shock to that edge-mode. The bundle elasticity is
the exact first-order weighted sum of its component elasticities.

For very large networks that use only edge-local congestion, run
`analyze-edge-local`. It constructs the Proposition-2 Jacobian as a sparse core
plus exact low-rank equilibrium terms and avoids route-incidence matrices. It
reports the primitive-cost welfare derivative but not the route-consistent
realized-friction diagnostic. It does not support endpoint-terminal congestion
or the `FM`/`FR` decomposition.

Validation and run manifests report whether edge congestion comes from a mode
table or an input column, together with the column name, scale, count, and
elasticity distribution. Use `edge_congestion_scale` for sensitivity analysis
when column-based values are active.

The generic CSV adapter covers applications that already fit this contract. A raw-data source with special balancing, geographic matching, or unit conversion should use a separate preprocessing script or adapter so every transformation remains explicit and reproducible.
