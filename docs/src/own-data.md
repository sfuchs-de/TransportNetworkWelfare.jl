# Use your own data

The generic adapter lets an application supply a network through two CSV files and one TOML configuration. It expects model-ready value flows, not arbitrary traffic observations.

## Install and update the package

Clone the package and instantiate the committed Julia environment:

```bash
git clone https://github.com/sfuchs-de/TransportNetworkWelfare.jl.git
cd TransportNetworkWelfare.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Keep each data project outside this checkout. Package updates can then change
the solver and documentation without mixing those changes with application
inputs or outputs.

Before updating, record the commit used for existing results. Update by
fast-forwarding the tracked branch, reinstantiating the environment, and
running the tests:

```bash
git rev-parse HEAD
git switch main
git pull --ff-only
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Rerun `validate` after any package, configuration, or data update. A new run
manifest will record the new code, configuration, input, and output hashes.
Retain the earlier commit and manifest when old results must remain
reproducible.

## Initialize a project

From the package repository, create a project anywhere on the filesystem:

```bash
julia --project=. bin/tnw.jl init /path/to/my-network economic_geography
# Or use urban_commuting for a residence-workplace application.
```

The command writes model-specific seed CSVs, `config.toml`, `sources.toml`,
`scripts/prepare_inputs.jl`, and a short project README. It refuses to
overwrite a nonempty directory. The seed files are runnable, so installation
can be checked before empirical data are introduced. The new project is
independent of the package source and can be versioned separately.

Record each raw source under `[sources.<source_id>]` in `sources.toml`, including
its logical locator, vintage, retrieval date, license, and checksum. Put
source-specific geocoding, unit conversion, balancing, and OD assignment in
`scripts/prepare_inputs.jl`. The package automates the model calculation after
that script writes the two model-ready CSVs; it does not infer those
transformations. When `sources.toml` is present at the project root, each run
manifest records its SHA-256.

## Define nodes

For `economic_geography`, each `nodes.csv` row needs a unique `node_id`,
positive labor, and positive income. For `urban_commuting`, replace those
columns with positive `residents` and `employment`. Coordinates are optional
metadata.

If some nodes represent foreign markets rather than mobile-worker locations,
list them under `model.external_nodes`. Supply positive `external_supply` and
`external_demand` values for those rows and zeros or missing values elsewhere.
The package then fixes those foreign schedules, removes the foreign nodes from
the labor-allocation equations, and evaluates welfare over endogenous
residents. It does not infer external schedules from placeholder labor or
income values.

## Define edge-mode flows

Each `edge_modes.csv` row is one active mode on one directed physical edge. `edge_id` identifies the direction and is repeated across modes. `physical_link_id` groups the two opposite policy directions. Missing mode rows mean that the mode is unavailable. Listed flows must be strictly positive.

The route representation permits several modes on an ordered node pair, but not several physical edge IDs with the same origin and destination. Represent parallel physical routes using explicit intermediate route nodes.

## Choose compatible units

- `flow_conversion = "none"` means `flow` is already a share of world income.
- `flow_conversion = "divide_by_world_income"` means `flow` and node `income` use the same currency and price basis; the loader divides flows by total income.
- Vehicle counts, passenger trips, tons, and container counts are not value flows. Convert them outside the generic adapter using prices or values appropriate to the application and document that conversion.

For each node, the supplied baseline must satisfy

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

The selected column must be finite and nonnegative for all active rows. It
cannot be combined with `[congestion.edge]`. Endpoint-terminal congestion
additionally requires `origin_terminal_id` and `destination_terminal_id` on
all affected mode rows. Modes absent from a mode-level congestion table have
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
elasticity distribution. For column-based congestion, use
`edge_congestion_scale` for sensitivity analysis.

## Map the results

Coordinates in `nodes.csv` are sufficient for a schematic map. Geographic
applications can provide GeoJSON line features keyed by `physical_link_id` and
an optional GeoJSON polygon or line basemap. All layers must use the same
coordinate reference system; the plotter does not reproject them.

```bash
python3 /path/to/TransportNetworkWelfare.jl/plots/network_example.py \
  data/nodes.csv data/edge_modes.csv output/welfare_physical.csv \
  figures/welfare-map.pdf \
  --metric primitive_F \
  --link-geometry data/link_geometry.geojson \
  --basemap data/basemap.geojson
python3 /path/to/TransportNetworkWelfare.jl/plots/hulten_vs_welfare.py \
  output/welfare_physical.csv figures/traditional-versus-extended.pdf
```

Shapefiles and GeoPackages may be joined directly to the result CSV in QGIS.
For the generic plotter, convert them to GeoJSON with `ogr2ogr` and preserve a
`physical_link_id` field. Geometry determines where a link is drawn; welfare
values always come from the validated result table.

## Updating an application

Treat the raw-data transformation, model-ready CSV files, and welfare run as
separate stages:

1. update the raw source through a versioned preprocessing script;
2. write new model-ready CSV files rather than editing an accepted vintage in
   place;
3. rerun `validate` and inspect accounting and route diagnostics;
4. run `analyze`, followed by `decompose` only when its memory estimate is
   feasible;
5. compare the new and old manifests before replacing tables or figures.

The generic CSV adapter covers applications that already fit this contract. A
raw-data source with special balancing, geographic matching, or unit
conversion should use a separate preprocessing script or adapter so its
transformations remain explicit and reproducible.
