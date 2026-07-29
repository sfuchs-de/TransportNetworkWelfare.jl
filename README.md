# TransportNetworkWelfare.jl

[![CI](https://github.com/sfuchs-de/TransportNetworkWelfare.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/sfuchs-de/TransportNetworkWelfare.jl/actions/workflows/ci.yml)
[![Julia 1.10+](https://img.shields.io/badge/Julia-1.10%2B-9558B2.svg)](https://julialang.org/)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`TransportNetworkWelfare.jl` computes the local welfare effects of marginal
transport-cost changes in spatial equilibrium. It supports recursive routing,
multimodal choice, edge and terminal congestion, directed and bidirectional
policies, parameter sensitivity, and an exact closure decomposition. The
default `ChoiceLogsum` specification is the model used by the accompanying
paper.

The package is not registered in Julia's General registry. Install it by
cloning this repository or by pinning a Git URL and commit in your own Julia
environment.

## Install and run

Install Git and Julia 1.10 or later, then run the self-contained toy project:

```bash
git clone https://github.com/sfuchs-de/TransportNetworkWelfare.jl.git
cd TransportNetworkWelfare.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. bin/tnw.jl validate examples/toy/config.toml
julia --project=. bin/tnw.jl analyze examples/toy/config.toml
julia --project=. bin/tnw.jl decompose examples/toy/config.toml
```

Results are written to `examples/toy/output/`. Each run also writes a manifest
containing the package version and commit, configuration and input hashes,
model parameters, numerical diagnostics, and output hashes.

Run `make help` for the common development, documentation, plotting, and
release commands.

## Choose a spatial model

The package exposes two spatial closures that share the same route, mode,
congestion, and pass-through operators.

| Model | Node quantities | Main use |
| --- | --- | --- |
| `economic_geography` | Labor and income | Trade, market access, and the location of economic activity |
| `urban_commuting` | Residents and employment | Residence, workplace, and commuting improvements |

The [model documentation](docs/src/model.md) gives the economic-geography
equations. The [urban documentation](docs/src/urban.md) explains the separate
state variables and welfare projection used by the commuting model.
`ComponentCES` is retained only for reproducing the historical positive-power
specification; new applications should use `ChoiceLogsum`.

## Use your own data

Create a portable project outside the package checkout:

```bash
PKG=/absolute/path/to/TransportNetworkWelfare.jl

julia --project="$PKG" "$PKG/bin/tnw.jl" init \
  /absolute/path/to/my-network economic_geography
# Use urban_commuting for a residence-workplace application.

julia --project="$PKG" "$PKG/bin/tnw.jl" validate \
  /absolute/path/to/my-network/config.toml
julia --project="$PKG" "$PKG/bin/tnw.jl" decompose \
  /absolute/path/to/my-network/config.toml
```

The generated directory contains runnable seed CSVs, a documented TOML
configuration, `sources.toml`, and a preprocessing entry point. Replace the
seed rows through a versioned preprocessing script; editing the package source
is not part of the normal application workflow.

The package does not silently balance flows, symmetrize links, pad nodes,
geocode observations, or rescale modes. The
[own-data guide](docs/src/own-data.md) documents schemas, units, accounting
identities, policy definitions, GIS inputs, and validation failures.

## Julia API and command line

The principal Julia workflow is:

```julia
using TransportNetworkWelfare

project = load_project("examples/toy/config.toml")
validate(project)
model = build_model(project)

welfare = welfare_effects(model)
components = decompose_welfare(model)
sensitivity = sensitivity_path(model, :alpha, [0.06, 0.10, 0.14])
write_results(components, "output/"; project)
```

Sparse policy bundles are supported through `load_policy_bundles` and
`bundle_welfare_effects`. The command line exposes the same workflow:

```text
init | validate | analyze | analyze-edge-local | decompose | sensitivity | replicate-rsue
```

Run `julia --project=. bin/tnw.jl --help` for the full syntax. The
[API reference](docs/src/reference/api.md) lists the exported Julia interface.

## Examples

Six examples run from tracked synthetic inputs. Sioux Falls, Seattle, and
Westeros use hash-pinned external sources and keep downloaded data outside Git.

| Group | Examples |
| --- | --- |
| Economic geography | `toy`, `grid_multimodal`, `braess`, `cow`, `sioux_falls`, `westeros` |
| Urban commuting | `urban_toy`, `urban_multimodal`, `seattle_urban`, `seattle_multimodal` |

The [examples guide](docs/src/examples.md) records each construction, command,
runtime, source attribution, and interpretation. External builders fail when a
pinned source or accounting identity does not match; they do not substitute
current data or silently repair an empirical baseline.

## Documentation and practitioner guide

Build the HTML documentation with:

```bash
make docs
```

The self-contained practitioner guide covers the theory, the adjoint and
decomposition algorithms, the data contract, a worked multimodal grid, and the
urban extension:

```bash
make practitioner-guide
make practitioner-guide-check
```

The PDF is written to
`docs/practitioner-guide/build/TransportNetworkWelfare-Practitioner-Guide.pdf`.
See the [guide source README](docs/practitioner-guide/README.md) for asset and
build details.

## Paper replication and data boundaries

The RSUE replication adapter requires external inputs listed in
`replication/rsue/input_manifest.toml`. Point `RSUE_DATA_ROOT` to those files
and use the locked environment:

```bash
export RSUE_DATA_ROOT=/absolute/path/to/rsue/Input
julia --project=replication/rsue/environment -e 'using Pkg; Pkg.instantiate()'
julia --project=replication/rsue/environment \
  replication/rsue/build_paper_artifacts.jl
```

The builder verifies source hashes and an independent finite-difference report.
Restricted microdata and link-level paper outputs are not committed. Aggregate
acceptance targets and non-sensitive hashes remain available for verification.
See the [RSUE documentation](docs/src/rsue.md) and
[provenance record](PROVENANCE.md).

## Verification

The public test suite covers algebraic identities, nonlinear finite
differences, route reconstruction, closure decomposition, limiting cases,
schema failures, permutation invariance, policy aggregation, and deterministic
output. Run:

```bash
make check
```

`make public-release-check` additionally builds and checks the practitioner
guide and plotting assets. Empirical acceptance tests that require external
data report a documented skip when those data are unavailable.

## Contributing, citation, and license

See [CONTRIBUTING.md](CONTRIBUTING.md) before changing numerical behavior or a
paper-facing specification. Cite the software release and associated paper as
described in [CITATION.cff](CITATION.cff).

Original package code, documentation, and synthetic inputs are licensed under
the [MIT License](LICENSE). External datasets and derived example assets remain
subject to their source terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
