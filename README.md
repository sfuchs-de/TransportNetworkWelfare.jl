# TransportNetworkWelfare.jl

`TransportNetworkWelfare.jl` computes local welfare effects of transport-cost changes in spatial equilibrium. It provides a typed Julia API, a TOML-driven command line interface, route and modal adjustment, modular congestion channels, and an exact closure decomposition.

The repository is private and pre-release. The default `ChoiceLogsum` specification uses a negative-power mode-choice index. `ComponentCES` preserves the positive-power convention in the audited July 2026 RSUE package. The current paper specification uses `ChoiceLogsum`; the legacy convention remains available for provenance and reconciliation.

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

## Canonical examples

Eight additional applications exercise distinct parts of the package:

- `examples/braess/`: a four-location routing example with a verified nonzero route wedge;
- `examples/sioux_falls/`: an on-demand adaptation of the standard 24-node benchmark using heterogeneous local BPR elasticities;
- `examples/cow/`: a 30-node mechanism example plus an optional sparse equilibrium with one location at each of 2,903 cow-mesh vertices;
- `examples/urban_toy/`: a self-contained Allen-Arkolakis residence-workplace model with nonlinear exact-hat checks;
- `examples/urban_multimodal/`: a self-contained road/transit urban model using the shared recursive transport block;
- `examples/seattle_urban/`: a hash-verified diagnostic adapter for the published 217-location Seattle inputs;
- `examples/seattle_multimodal/`: a candidate Seattle road/transit adapter using LODES, ACS commute-mode shares, and pinned historical GTFS service; and
- `examples/westeros/`: an on-demand synthetic economic-geography application built from hash-pinned public ArcGIS geography.

Braess, cow, and both urban toys are fully self-contained. Sioux Falls downloads
pinned, hash-verified academic-use source files and records its balancing conversion.
The Seattle adapters require external data and fail rather than silently reconcile
incompatible traffic and commuter populations.
See [Examples](docs/src/examples.md) for assumptions, commands, plotting, and
the urban model's separate equilibrium closure.

## Use your own data

Keep application data outside the package checkout. Clone and initialize the
package once:

```bash
git clone https://github.com/sfuchs-de/TransportNetworkWelfare.jl.git
cd TransportNetworkWelfare.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Create a portable data project:

```bash
julia --project=/path/to/TransportNetworkWelfare.jl \
  /path/to/TransportNetworkWelfare.jl/bin/tnw.jl init \
  /path/to/my-network economic_geography
# Use urban_commuting as the final argument for a residence-workplace model.
julia --project=/path/to/TransportNetworkWelfare.jl \
  /path/to/TransportNetworkWelfare.jl/bin/tnw.jl validate /path/to/my-network/config.toml
julia --project=/path/to/TransportNetworkWelfare.jl \
  /path/to/TransportNetworkWelfare.jl/bin/tnw.jl decompose /path/to/my-network/config.toml
```

The generated directory contains model-specific seed CSVs, a documented TOML
configuration, `sources.toml`, a preprocessing entry point, and no package
source. Replace the synthetic rows through a versioned preprocessing script and
edit the configuration; no Julia changes or RSUE/private files are required.
The generic adapter does not balance flows, symmetrize links, pad nodes, or
rescale modes. See [Use your own data](docs/src/own-data.md) for the
accounting, unit, policy, and GIS requirements. Run manifests include the
SHA-256 of a project-root `sources.toml`.

The generic figure command accepts straight node-to-node links or GeoJSON line
geometry keyed by `physical_link_id`, plus an optional polygon or line basemap:

```bash
python3 plots/network_example.py \
  /path/to/my-network/data/nodes.csv \
  /path/to/my-network/data/edge_modes.csv \
  /path/to/my-network/output/welfare_physical.csv \
  /path/to/my-network/figures/welfare-map.pdf \
  --link-geometry /path/to/my-network/data/link_geometry.geojson \
  --basemap /path/to/my-network/data/basemap.geojson
python3 plots/hulten_vs_welfare.py \
  /path/to/my-network/output/welfare_physical.csv \
  /path/to/my-network/figures/traditional-versus-extended.pdf
```

Before updating the package, record the commit used for existing results.
Fast-forward the checkout, reinstantiate, test, and validate the data project
again:

```bash
git rev-parse HEAD
git switch main
git pull --ff-only
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia --project=. bin/tnw.jl validate /path/to/my-network/config.toml
```

Each new run manifest binds the results to code, configuration, input, and
output hashes. Preserve the prior commit and manifest when reproducing an
earlier result vintage.

## Julia API

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

## Command line interface

```bash
julia --project=. bin/tnw.jl init /path/to/my-network
julia --project=. bin/tnw.jl validate config.toml
julia --project=. bin/tnw.jl analyze config.toml
julia --project=. bin/tnw.jl analyze-edge-local config.toml
julia --project=. bin/tnw.jl decompose config.toml
julia --project=. bin/tnw.jl sensitivity config.toml
julia --project=. bin/tnw.jl replicate-rsue replication/rsue/rsue_legacy_audited.toml
```

## RSUE replication

Restricted inputs are not committed. Set `RSUE_DATA_ROOT` to the folder containing the six files listed in `replication/rsue/input_manifest.toml`, then run the legacy configuration. The adapter verifies the hash of each file and records the historical padding, symmetrization, filtering, and mode-weight transformations.

```bash
export RSUE_DATA_ROOT=/absolute/path/to/rsue/Input
julia --project=. bin/tnw.jl replicate-rsue replication/rsue/rsue_legacy_audited.toml
```

The legacy configuration reproduces the frozen July 12 directed welfare elasticities to numerical precision. Run `replication/rsue/verify_legacy.jl` with both `RSUE_DATA_ROOT` and `RSUE_FROZEN_RESULTS_ROOT` to check the archived artifact hashes and the full directed table. Restricted-data tests are explicitly skipped in public CI when those paths are unavailable.

The legacy foreign-water matrix appears to use 2017 container-import geography and then symmetrizes it. The paper configuration instead uses separate Census port-level imports and exports, projected onto common margins so that the current balanced-trade theory remains valid. The credential-safe downloader, explicit crosswalks, derived overlay, diagnostics, and limitations are documented in [`replication/rsue/census_ports/README.md`](replication/rsue/census_ports/README.md). Build the paper artifact set in the locked replication environment after setting `RSUE_DATA_ROOT`:

```bash
julia --project=replication/rsue/environment -e 'using Pkg; Pkg.instantiate()'
julia --project=replication/rsue/environment replication/rsue/build_paper_artifacts.jl
```

The private artifact set includes all 352 link-level welfare effects and ranks
for 35 sensitivity values, plus generated top-10 and top-30 ranking tables.
The paper figure uses the five headline paths; common and terminal congestion
remain package diagnostics. The same build writes the traffic, welfare,
scatter, decomposition, and sensitivity figures, together with traffic-ranked
top-50 and top-100 correlations. These derived restricted-data outputs remain
untracked.

The builder requires an accepted, hash-bound nonlinear finite-difference report. Recreate that report with `replication/rsue/verify_choice_logsum_fd.jl` whenever the paper configuration, restricted inputs, or derivative sources change.

## Documentation

The task-oriented documentation is under `docs/src/`. Build it with:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The self-contained practitioner guide covers the paper's theory, the adjoint
and decomposition algorithms, the data contract, a worked multimodal grid,
and the urban extensions:

```bash
make practitioner-guide-assets
make practitioner-guide-example-assets
make practitioner-guide
make practitioner-guide-check
```

The resulting PDF is
`docs/practitioner-guide/build/TransportNetworkWelfare-Practitioner-Guide.pdf`.
Its source and figures are committed, so the PDF build itself does not require
Overleaf, restricted data, credentials, or Python. Asset regeneration and the
full drift check use the pinned plotting environment in
`plots/requirements.txt`. Every guide example receives the same welfare map,
Traditional-versus-Extended scatter, and ranked-link table.

See [PROVENANCE.md](PROVENANCE.md) for the frozen source hashes and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for the private-to-public gates.

## License

MIT, subject to coauthor approval before public release. See [LICENSE](LICENSE).
