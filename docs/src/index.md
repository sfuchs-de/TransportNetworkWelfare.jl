# TransportNetworkWelfare.jl

This package evaluates local transport improvements in spatial equilibrium. A
project consists of two CSV files and one TOML file. The computation returns
directed-arc effects, physical-link effects, closure decompositions, parameter
sensitivity paths, and diagnostics.

For a paper-centered treatment of the theory and a complete computational
walkthrough, build the
[practitioner guide](https://github.com/sfuchs-de/TransportNetworkWelfare.jl/tree/main/docs/practitioner-guide)
with `make practitioner-guide` from the repository root. Use
`make practitioner-guide-check` to verify its numerical assets, citations,
references, and PDF.

## Install and run the toy project

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. bin/tnw.jl validate examples/toy/config.toml
julia --project=. bin/tnw.jl decompose examples/toy/config.toml
```

The first command installs Julia dependencies. The next two commands need no external data. To adapt the example, change only `nodes.csv`, `edge_modes.csv`, and `config.toml`; source edits are not part of the workflow.

For a separate project, initialize a portable template and point the package CLI to its configuration:

```bash
julia --project=. bin/tnw.jl init /path/to/my-network
julia --project=. bin/tnw.jl validate /path/to/my-network/config.toml
julia --project=. bin/tnw.jl decompose /path/to/my-network/config.toml
```

The [own-data guide](own-data.md) states the required accounting identities and explains which raw transport measures need application-specific preprocessing.

## Output contract

Each run writes CSV results, diagnostics, and `run_manifest.json`. The manifest records the package version and commit, Julia version, command, configuration hash, input hashes, transformations, model variant, parameters, condition numbers, verification status, and output hashes.

The code repository owns source, tests, configurations, and small synthetic
fixtures. The journal manuscript remains separate. Restricted data remain
outside Git and are resolved through environment variables. External data and
derived assets retain their source terms, as described in
[`THIRD_PARTY_NOTICES.md`](https://github.com/sfuchs-de/TransportNetworkWelfare.jl/blob/main/THIRD_PARTY_NOTICES.md).
