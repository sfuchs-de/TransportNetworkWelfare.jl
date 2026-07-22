# Data and configuration

## `nodes.csv`

Required columns:

| Column | Meaning |
| --- | --- |
| `node_id` | Unique stable node identifier |
| `labor` | Positive labor level |
| `income` | Positive income level |

Optional columns are `longitude` and `latitude`. The loader normalizes labor and income only when the TOML file declares those transformations.

## `edge_modes.csv`

Required columns:

| Column | Meaning |
| --- | --- |
| `edge_id` | Directed physical edge identifier; repeated across modes |
| `physical_link_id` | Identifier shared by opposite policy directions |
| `origin`, `destination` | Existing node identifiers |
| `mode` | Mode name listed in `mode_order` |
| `flow` | Strictly positive active edge-mode flow |

`origin_terminal_id` and `destination_terminal_id` are required when that mode has endpoint-terminal congestion. An optional finite, nonnegative congestion-elasticity column can supply edge-mode-specific values. `(edge_id, mode)` must be unique. The current route representation does not admit two edge IDs with identical endpoints; represent parallel paths with explicit intermediate route nodes.

A missing `(edge_id, mode)` row means that mode is unavailable on the edge. Every listed active edge-mode must have strictly positive flow because the current derivative is evaluated at an interior baseline.

## Units and transformations

`flow_conversion="none"` treats flows as world-income shares. `flow_conversion="divide_by_world_income"` treats flows as currency levels and divides them by total node income. The configuration must also declare labor and income normalization.

For each node $i$, baseline edge-mode traffic must satisfy

```math
\sum_{j,m}\Xi_{ij,m}=\sum_{j,m}\Xi_{ji,m}.
```

This is an equilibrium accounting identity, not a numerical tolerance for arbitrary traffic counts. Vehicle counts, tons, and unbalanced origin-destination records therefore require an application-specific conversion into value-flow shares before loading.

The generic loader does not pad nodes, symmetrize edges, or rescale modes. Both policy directions must appear in the CSV. The RSUE legacy adapter is separate because it reproduces historical declared transformations and records each one in the manifest.

See [Use your own data](own-data.md) for the complete input contract and [Outputs](outputs.md) for result interpretation.

## Configuration reference

```toml
schema_version = 1

[input]
adapter = "generic_csv_v1"
nodes = "data/nodes.csv"
edge_modes = "data/edge_modes.csv"
mode_order = ["road", "rail"]

[input.transformations]
normalize_labor = true
normalize_income = true
flow_conversion = "none"
symmetrize = false
pad_nodes = 0
modal_rescale = false

[model]
alpha = 0.10
beta = -0.30
sigma = 9.0
eta = 1.099
modal_specification = "choice_logsum"
route_curvature = "theorem"

[congestion]
specification = "composite"
endpoint_scale = 1.0

[congestion.edge]
road = 0.05

[congestion.terminal]
rail = 0.03

[policy]
mode = "road"
unit = "both"
shock_fraction = 0.01
```

For heterogeneous edge-mode congestion, replace `[congestion.edge]` with:

```toml
[congestion]
specification = "edge"
source = "input_column"
column = "congestion_elasticity"
scale = 1.0
```

Every active edge-mode row must then have a finite, nonnegative value in the
configured column. Input-column and mode-level edge elasticities cannot be
mixed. `edge_congestion_scale` is the corresponding sensitivity parameter;
mode-specific paths such as `lambda_road` are rejected for this specification.

To add a mode, add rows to `edge_modes.csv`, add its name to `mode_order`, and optionally assign an edge or terminal congestion elasticity. To add a node, add its node row and all explicit directed edge-mode rows. No Julia changes are required.
