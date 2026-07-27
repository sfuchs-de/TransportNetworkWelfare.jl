# RSUE replication

The RSUE inputs are external. The repository contains their filenames and SHA-256 hashes, not the data.

```bash
export RSUE_DATA_ROOT=/absolute/path/to/rsue/Input
julia --project=. bin/tnw.jl replicate-rsue \
  replication/rsue/rsue_legacy_audited.toml
```

`RSUE_DATA_ROOT` may identify the input directory or a parent containing `Input/`. The adapter fails before analysis when a file is absent or a hash differs.

## Configurations

`rsue_legacy_audited.toml` uses `ComponentCES(1.099)`, road edge congestion `0.092`, endpoint rail-terminal congestion `0.096` at each endpoint, and the historical active transport subset needed to reproduce the frozen July 12 package.

`rsue_candidate_choice.toml` retains the original research-candidate comparison.

`rsue_census_ports_2017_candidate.toml` keeps the legacy component-CES convention but replaces the symmetrized foreign-water proxy with separate Census port-level imports and exports. It uses 2017 containerized vessel value, explicit Schedule C/D crosswalks, and a documented balanced-trade projection. It also activates all four modes. This is a data-and-model candidate, not the paper specification.

Use `rsue_legacy_ports_all_modes_control.toml` for a like-for-like comparison. It activates the same four modes under the same component-CES and congestion specifications but retains the legacy symmetrized port layer.

The July 2026 paper specification is `rsue_paper_choice_edge_census_2017.toml`. It combines `ChoiceLogsum(1.099)`, all four transport modes, road edge congestion of `0.092`, and the directional Census port layer. The policy unit is a simultaneous one-percent primitive-cost reduction in both directions of a physical road link. `rsue_paper_terminal_extension_census_2017.toml` adds endpoint rail-terminal congestion only for the extension sensitivity panels. `rsue_paper_choice_edge_legacy_ports_control.toml` holds the paper model fixed and restores the legacy port layer as a data robustness check.

The legacy adapter records six historical operations: domestic-node count, foreign-node padding, modal symmetrization, within-mode normalization, RSUE modal weights, and terminal-based rail filtering. Generic projects do none of these operations.

The Census candidate preserves those operations for the domestic layers but does not symmetrize foreign water. Raw directional Census trade is not model-ready because imports and exports do not satisfy the current location-level balanced-flow identity. The builder RAS-projects both directions onto common port and foreign-region margins, records the adjustment, and fails if balancing requires support absent from the raw matrices. See `replication/rsue/census_ports/README.md` for refresh and build commands.

Run the candidate with:

```bash
julia --project=. bin/tnw.jl decompose \
  replication/rsue/rsue_census_ports_2017_candidate.toml
```

Build the complete paper result vintage, claim ledger, TeX macros, CBSA labels, and figures with:

```bash
export RSUE_DATA_ROOT=/absolute/path/to/rsue/Input
julia --project=replication/rsue/environment -e 'using Pkg; Pkg.instantiate()'
julia --project=replication/rsue/environment replication/rsue/build_paper_artifacts.jl
```

The private artifact directory also contains `paper_sensitivity_links.csv`.
It reports every physical-link result, welfare rank, and rank change for each
of the 35 sensitivity points. The builder requires 352 links in every group
and checks its means and rank correlations against `paper_sensitivity.csv`.
The link-level file is derived from restricted inputs and is not committed.
The generated top-10 and top-30 comparison tables are drawn from the same
ranked result object.

The builder also writes `paper_mechanism_path_links.csv`. This file supports
the main decomposition figure with a nested sequence of welfare calculations.
It begins from the Traditional traffic statistic, verifies the efficient
fixed-route and flexible route-modal collapses, then adds road congestion,
net spatial externalities, and primitive-cost pass-through. The original
`H`/`NC`/`NT`/`F`/`FM`/`FR` closure outputs remain unchanged and continue to
support the more detailed appendix identities. Terminal congestion is absent
from the headline path and remains an extension.

The tracked replication manifest fixes the Julia package environment. The artifact manifest also records the Julia and BLAS configuration, Python version, GDAL version, lockfile hashes, input hashes, and source hashes.

The builder requires an accepted report from the independent nonlinear choice-logsum finite-difference harness. The report is bound to the paper configuration, restricted inputs, and derivative source files. Regenerate it after any of those change:

```bash
export RSUE_DATA_ROOT=/absolute/path/to/rsue/Input
julia --project=replication/rsue/environment \
  replication/rsue/verify_choice_logsum_fd.jl
```

The builder uses the official 2018 Census CBSA archive with a pinned SHA-256. With both the verified archive and its derived GeoJSON in the cache, it can run offline without GDAL. A fresh conversion requires `ogr2ogr`, whose version is recorded. No corridor name is written unless the public polygon file assigns it. Generated maps and scatterplots have no internal title and are saved as PDF and transparent PNG.

Legacy acceptance values and frozen output hashes are in `expected_summary.toml`; the corresponding Census-candidate targets are in `census_ports/expected_summary.toml`. The full result comparisons run only when the external data are present:

```bash
export RSUE_FROZEN_RESULTS_ROOT=/absolute/path/to/Output_complete_decomposition
julia --project=. replication/rsue/verify_legacy.jl
```

This gate verifies the three archived artifact hashes and compares every directed-arc result field against the frozen table. Public CI reports the restricted acceptance test as skipped rather than passed when `RSUE_DATA_ROOT` is absent.
