# Examples

The repository contains ten examples. Six are self-contained, three construct
model inputs from hash-pinned external sources, and one preserves an
inconsistent empirical baseline as a validation diagnostic.

| Directory | Spatial model | Purpose | Data requirement |
| --- | --- | --- | --- |
| `toy` | Economic geography | Fast API, modal, terminal, decomposition, and sensitivity check | Self-contained |
| `grid_multimodal` | Economic geography | Practitioner-guide grid with a central transit spine | Self-contained |
| `braess` | Economic geography | Flexible- versus fixed-route comparison | Self-contained |
| `cow` | Economic geography | Irregular three-dimensional geography and ranking comparison | Self-contained; optional PLY download |
| `sioux_falls` | Economic geography | Adaptation of the 24-node traffic benchmark | Pinned academic-use download |
| `urban_toy` | Urban commuting | One-mode residence--workplace IFT and exact-hat check | Self-contained |
| `urban_multimodal` | Urban commuting | Shared recursive road/transit transport block | Self-contained |
| `seattle_urban` | Urban commuting | Diagnostic for the published road and commuting inputs | External replication archive |
| `seattle_multimodal` | Urban commuting | Seattle road/transit candidate on one commuter population | Replication archive, ACS response, pinned 2017 GTFS |
| `westeros` | Economic geography | Synthetic application on irregular public geography | Pinned public ArcGIS queries |

Run a self-contained example from the repository root:

```bash
julia --project=. bin/tnw.jl validate examples/braess/config.toml
julia --project=. bin/tnw.jl decompose examples/braess/config.toml
```

Prepare Sioux Falls before running its configurations:

```bash
julia --project=. examples/sioux_falls/prepare.jl
```

The Seattle road adapter is expected to fail validation because HPMS vehicle
traffic and LODES commuter flows do not describe one conserved population. The
multimodal Seattle builder instead routes the LODES OD population over road
and transit networks. The Westeros builder creates synthetic activity and
trade because the source map contains geography but no economic data.

Construction details, source identities, hashes, terms, commands, and
interpretive limits are documented in
[`docs/src/examples.md`](../docs/src/examples.md) and in each example's README.
