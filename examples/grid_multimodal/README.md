# Multimodal grid

This self-contained economic-geography example has 25 locations on a regular
five-by-five grid. Reciprocal road links connect adjacent locations. A transit
mode operates on the four physical links along the central east-west axis.
Transit endpoint identifiers activate the package's terminal-congestion
extension.

The committed flows are symmetric by direction. Together with strictly
positive location income, this makes the recursive-flow accounting identities
hold without an internal balancing transformation. The example is synthetic:
its purpose is to explain the package's routing, modal, congestion, welfare,
and closure-decomposition objects.

From the repository root:

```bash
julia --project=. bin/tnw.jl validate examples/grid_multimodal/config.toml
julia --project=. bin/tnw.jl analyze examples/grid_multimodal/config.toml
julia --project=. bin/tnw.jl decompose examples/grid_multimodal/config.toml
julia --project=. bin/tnw.jl sensitivity examples/grid_multimodal/config.toml
```

Rebuild the committed CSV inputs with:

```bash
julia examples/grid_multimodal/build_inputs.jl
```

Generate the guide's checked figures, tables, and TeX result macros with:

```bash
make practitioner-guide-assets
```
