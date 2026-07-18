# TransportNetworkWelfare.jl

`TransportNetworkWelfare.jl` computes local welfare effects of transport-cost changes in spatial equilibrium. It provides a typed Julia API, a TOML-driven command line interface, route and modal adjustment, modular congestion channels, and an exact closure decomposition.

The repository is private and pre-release. The default `ChoiceLogsum` specification uses a negative-power mode-choice index. `ComponentCES` preserves the positive-power convention in the audited July 2026 RSUE package. The candidate choice configuration is not the paper specification unless the theory and coauthor gates are completed.

## Five-minute example

Install Julia 1.10 or later, clone the repository, and run:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. bin/tnw.jl validate examples/toy/config.toml
julia --project=. bin/tnw.jl analyze examples/toy/config.toml
julia --project=. bin/tnw.jl decompose examples/toy/config.toml
julia --project=. bin/tnw.jl sensitivity examples/toy/config.toml
```

The example is self-contained. It does not require Dropbox, credentials, Python, or source edits. Generated files are written below `examples/toy/output/` and include a run manifest with input, configuration, code, parameter, diagnostic, and output hashes.

## Julia API

```julia
using TransportNetworkWelfare

project = load_project("examples/toy/config.toml")
validate(project)
model = build_model(project)
welfare = welfare_effects(model)
components = decompose_welfare(model)
sensitivity = sensitivity_path(model, :alpha, [0.06, 0.10, 0.14])
write_results(welfare, "output/")
```

## Command line interface

```bash
julia --project=. bin/tnw.jl validate config.toml
julia --project=. bin/tnw.jl analyze config.toml
julia --project=. bin/tnw.jl decompose config.toml
julia --project=. bin/tnw.jl sensitivity config.toml
julia --project=. bin/tnw.jl replicate-rsue replication/rsue/rsue_legacy_audited.toml
```

## RSUE replication

Restricted inputs are not committed. Set `RSUE_DATA_ROOT` to the folder containing the six files listed in `replication/rsue/input_manifest.toml`, then run the legacy configuration. The adapter verifies every file hash and records the historical padding, symmetrization, filtering, and mode-weight transformations.

```bash
export RSUE_DATA_ROOT=/absolute/path/to/rsue/Input
julia --project=. bin/tnw.jl replicate-rsue replication/rsue/rsue_legacy_audited.toml
```

The legacy configuration reproduces the frozen July 12 directed welfare elasticities to numerical precision. `rsue_candidate_choice.toml` is an explicitly labeled research candidate and is not paper-facing.

## Documentation

The task-oriented documentation is under `docs/src/`. Build it with:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

See [PROVENANCE.md](PROVENANCE.md) for the frozen source hashes and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for the private-to-public gates.

## License

MIT, subject to coauthor approval before public release. See [LICENSE](LICENSE).
