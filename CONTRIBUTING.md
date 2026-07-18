# Contributing

Use Julia 1.10 or later. Keep changes small, add a test for every behavioral change, and run:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia --project=. bin/tnw.jl validate examples/toy/config.toml
julia --project=. bin/tnw.jl analyze examples/toy/config.toml
```

Do not commit raw RSUE inputs, credentials, machine-specific paths, or generated `output/` directories. Changes to the analytical kernels require an independent finite-difference test and a provenance note. Changes to the candidate modal convention require theory review before they can alter paper-facing outputs.

Use pull requests for reviewed work. Record user-facing changes in `CHANGELOG.md` and keep the documentation synchronized with configuration behavior.
