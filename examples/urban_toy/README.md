# Urban commuting toy model

This three-location example exercises the Allen-Arkolakis urban closure. People
choose a residence, workplace, and route. The input records separate residence
and workplace masses and directed commuter traffic.

```bash
julia --project=. bin/tnw.jl validate examples/urban_toy/config.toml
julia --project=. bin/tnw.jl analyze examples/urban_toy/config.toml
```

The example is model-consistent by construction. Setting `alpha`, `beta`, and
`lambda` to zero reproduces the traffic-share (Hulten) benchmark. The package's
urban exact-hat solver is used in tests to check the analytic IFT by central
finite differences.
