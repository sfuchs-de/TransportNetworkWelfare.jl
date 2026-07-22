# Examples

| Directory | Role | Data requirement |
| --- | --- | --- |
| `toy` | Fast API and decomposition smoke test | Self-contained |
| `braess` | Flexible- versus fixed-route comparison | Self-contained |
| `cow` | Synthetic geography and ranking comparison | Self-contained |
| `sioux_falls` | Standard 24-node benchmark adaptation | Pinned academic-use download |

Run a self-contained example from the repository root:

```bash
julia --project=. bin/tnw.jl validate examples/braess/config.toml
julia --project=. bin/tnw.jl decompose examples/braess/config.toml
```

Prepare Sioux Falls before running its configurations:

```bash
julia --project=. examples/sioux_falls/prepare.jl
```

The detailed assumptions, sizes, runtime guidance, plotting command, and
Seattle boundary are documented in [`docs/src/examples.md`](../docs/src/examples.md).
