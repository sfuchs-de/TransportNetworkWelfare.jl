# TransportNetworkWelfare.jl

`TransportNetworkWelfare.jl` computes the local welfare effects of transport-cost
changes in spatial equilibrium. It provides a typed Julia API, a TOML-driven
command line interface, recursive routing, multimodal choice, modular congestion
channels, and an exact closure decomposition. The default `ChoiceLogsum`
specification is the model used by the accompanying paper.

## Quick start

Install Git and Julia 1.10 or later, then run:

```bash
git clone https://github.com/sfuchs-de/TransportNetworkWelfare.jl.git
cd TransportNetworkWelfare.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. bin/tnw.jl validate examples/toy/config.toml
julia --project=. bin/tnw.jl analyze examples/toy/config.toml
julia --project=. bin/tnw.jl decompose examples/toy/config.toml
```

The toy example is self-contained. It requires no private data, credentials,
Python, or source edits. Results are written to `examples/toy/output/`, together
with a manifest that records the code, configuration, inputs, parameters,
diagnostics, and output hashes.

## Use your own data

Initialize a portable project outside the package checkout:

```bash
julia --project=/path/to/TransportNetworkWelfare.jl \
  /path/to/TransportNetworkWelfare.jl/bin/tnw.jl init \
  /path/to/my-network economic_geography
# Use urban_commuting for a residence-workplace model.
julia --project=/path/to/TransportNetworkWelfare.jl \
  /path/to/TransportNetworkWelfare.jl/bin/tnw.jl validate \
  /path/to/my-network/config.toml
julia --project=/path/to/TransportNetworkWelfare.jl \
  /path/to/TransportNetworkWelfare.jl/bin/tnw.jl decompose \
  /path/to/my-network/config.toml
```

The generated directory contains model-specific seed CSVs, a documented TOML
configuration, `sources.toml`, and a preprocessing entry point. Replace the
synthetic rows through a versioned preprocessing script and edit the
configuration; changing the Julia package is not part of the normal workflow.
The adapter does not silently balance flows, symmetrize links, pad nodes, or
rescale modes.

The [own-data guide](docs/src/own-data.md) describes the node and edge-mode
schemas, accounting identities, units, policy definitions, validation checks,
GIS inputs, and update workflow. Generic plotting accepts straight
node-to-node links or GeoJSON geometry keyed by `physical_link_id`, with an
optional polygon or line basemap.

For reproducible applications, record the package commit and run manifest.
Prefer a tagged release for published results, and retain the prior commit and
manifest when updating an existing application.

## Interfaces

The main Julia API is:

```julia
using TransportNetworkWelfare

project = load_project("examples/toy/config.toml")
validate(project)
model = build_model(project)
welfare = welfare_effects(model)
components = decompose_welfare(model)
sensitivity = sensitivity_path(model, :alpha, [0.06, 0.10, 0.14])
write_results(welfare, "output/"; project)

bundles = load_policy_bundles("route_bundles.csv")
route_effects = bundle_welfare_effects(model, bundles)
```

The command line interface exposes the same workflow:

```bash
julia --project=. bin/tnw.jl init /path/to/my-network
julia --project=. bin/tnw.jl validate config.toml
julia --project=. bin/tnw.jl analyze config.toml
julia --project=. bin/tnw.jl decompose config.toml
julia --project=. bin/tnw.jl sensitivity config.toml
```

The specialized `analyze-edge-local` and `replicate-rsue` commands remain
available for paper replication and diagnostic work. Run
`julia --project=. bin/tnw.jl --help` for the complete command list.

## Examples

The repository includes self-contained toy, Braess-style, cow-network,
economic-geography grid, and road-transit urban examples. It also provides
on-demand or external-data adapters for Sioux Falls, Seattle, and Westeros.
These applications illustrate route adjustment, modal substitution,
edge-specific congestion, urban commuting, policy bundles, and map generation.

The [examples guide](docs/src/examples.md) gives the construction, assumptions,
commands, runtime, source attribution, and data requirements for every example.
External-data builders verify pinned source hashes and fail rather than silently
reconcile incompatible flows or populations.

## RSUE replication

The paper replication requires restricted inputs that are not committed. Set
`RSUE_DATA_ROOT` to the directory containing the files in
`replication/rsue/input_manifest.toml`, instantiate the locked replication
environment, and build the artifacts:

```bash
export RSUE_DATA_ROOT=/absolute/path/to/rsue/Input
julia --project=replication/rsue/environment -e 'using Pkg; Pkg.instantiate()'
julia --project=replication/rsue/environment \
  replication/rsue/build_paper_artifacts.jl
```

The builder verifies input hashes and an independent nonlinear
finite-difference report before writing results. Restricted link-level outputs
remain untracked. The [RSUE documentation](docs/src/rsue.md) explains the
accepted paper configuration, legacy reconciliation, directional Census port
flows, sensitivity outputs, and verification commands.

## Documentation and practitioner guide

Build the task-oriented documentation with:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The self-contained practitioner guide covers the theory, adjoint and
decomposition algorithms, data contract, a worked multimodal grid, and urban
extensions:

```bash
make practitioner-guide-assets
make practitioner-guide-example-assets
make practitioner-guide
make practitioner-guide-check
```

The PDF is written to
`docs/practitioner-guide/build/TransportNetworkWelfare-Practitioner-Guide.pdf`.
Its committed source and synthetic assets require neither Overleaf nor
restricted data. Tagged [GitHub releases](https://github.com/sfuchs-de/TransportNetworkWelfare.jl/releases)
attach the checked PDF and its SHA-256 checksum. Release maintainers can produce
the same files with `make release-artifacts`.

## Model variants and release status

`ChoiceLogsum` uses the negative-power mode-choice index and is the supported
paper-facing specification. `ComponentCES` retains the positive-power convention
from the frozen July 2026 pipeline solely for legacy reproduction and
provenance.

The current release candidate is `v0.2.0`. The repository remains private until
the coauthor, citation, and data-documentation gates in
[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) are approved. See
[PROVENANCE.md](PROVENANCE.md) for source lineage and the retained
[theory-code audit](docs/audits/THEORY-CODE-SELF-CONTAINMENT-AUDIT.md) for the
paper-to-package crosswalk.

## Contributing, citation, and license

See [CONTRIBUTING.md](CONTRIBUTING.md) before changing numerical behavior or
paper-facing specifications. Cite both the software release and the associated
paper as described in [CITATION.cff](CITATION.cff).

The package is licensed under the [MIT License](LICENSE). Public distribution
remains subject to the approval gates above.
