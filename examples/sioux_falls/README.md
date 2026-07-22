# Sioux Falls benchmark adaptation

Sioux Falls is a standard 24-node, 76-directed-link traffic-assignment test
network. The upstream maintainers describe it as a debugging benchmark rather
than a realistic urban network.

The upstream files are for academic research and are not distributed under
this package's MIT license. Prepare the example on demand:

```bash
julia --project=. examples/sioux_falls/prepare.jl
julia --project=. bin/tnw.jl validate examples/sioux_falls/config_extended.toml
julia --project=. bin/tnw.jl decompose examples/sioux_falls/config_extended.toml
```

`prepare.jl` downloads four files from the commit pinned in `sources.toml`,
checks their SHA-256 hashes, and writes ignored model-ready CSVs under
`generated/`. Use `--offline` to rebuild from an already verified `raw/`
cache, or `--source-dir PATH` to use a separate cache.

## Economic conversion

The builder uses the benchmark's best-known assigned link flows; it does not
solve the Wardrop assignment. The published OD table has zone-level production
and attraction differences of up to 100 trips, and the assigned flows reproduce
those net differences. The builder therefore averages production with
attraction and averages each pair of reciprocal assigned flows. It records the
raw imbalances and verifies exact conservation after balancing. The balanced OD
margin becomes both synthetic income and labor, and balanced link flow is
divided by total OD trips. Thus the example is an explicit adaptation to the
recursive-routing spatial model, not a replication of the original
traffic-assignment objective.

For the extended configuration, each BPR link is represented by its exact
local log congestion elasticity at the balanced assigned-flow baseline:

```math
\lambda_e = \frac{p_e B_e(v_e/c_e)^{p_e}}
                   {1+B_e(v_e/c_e)^{p_e}}.
```

`config_efficient.toml` removes congestion and externalities and should
reproduce the Hulten collapse. `config_extended.toml` uses the heterogeneous
BPR elasticities and a stable dispersive spatial calibration.
