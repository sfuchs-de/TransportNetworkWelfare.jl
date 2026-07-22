# Braess-style routing example

This four-location example uses the familiar two-route topology with a cross
connector. It is designed to exercise the package's flexible-route and
fixed-route closures. It is not a Wardrop traffic-assignment exercise and does
not claim to reproduce Braess's paradox.

```bash
julia --project=. bin/tnw.jl validate examples/braess/config.toml
julia --project=. bin/tnw.jl decompose examples/braess/config.toml
```

The input is synthetic, reciprocal, and expressed directly as model-ready
value-flow shares. The nonzero `d_route` output is the difference between the
full route response and the closure that freezes baseline route use.
