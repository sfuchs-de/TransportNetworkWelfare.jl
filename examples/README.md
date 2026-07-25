# Examples

- `urban_toy`: self-contained Allen-Arkolakis residence-workplace model.
- `urban_multimodal`: self-contained recursive road/transit urban model.
- `seattle_urban`: diagnostic adapter for the published Seattle road inputs.
- `seattle_multimodal`: LODES/ACS/GTFS Seattle candidate.
- `westeros_urban`: on-demand synthetic application using public ArcGIS geography.

| Directory | Role | Data requirement |
| --- | --- | --- |
| `toy` | Fast API and decomposition smoke test | Self-contained |
| `braess` | Flexible- versus fixed-route comparison | Self-contained |
| `cow` | Synthetic geography and ranking comparison | Self-contained |
| `sioux_falls` | Standard 24-node benchmark adaptation | Pinned academic-use download |
| `urban_toy` | Residence-workplace IFT and exact-hat checks | Self-contained |
| `seattle_urban` | Published 217-location road-input diagnostic | External replication archive |
| `seattle_multimodal` | Model-consistent Seattle road/transit candidate | Replication archive, 2017 ACS, pinned 2017 GTFS |
| `westeros_urban` | Synthetic urban model on Westeros geography | Pinned public ArcGIS queries |

Run a self-contained example from the repository root:

```bash
julia --project=. bin/tnw.jl validate examples/braess/config.toml
julia --project=. bin/tnw.jl decompose examples/braess/config.toml
```

Prepare Sioux Falls before running its configurations:

```bash
julia --project=. examples/sioux_falls/prepare.jl
```

The detailed assumptions, sizes, runtime guidance, plotting command, and urban
model boundary are documented in [`docs/src/examples.md`](../docs/src/examples.md).
