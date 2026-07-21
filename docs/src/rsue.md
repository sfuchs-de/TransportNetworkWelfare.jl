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

`rsue_candidate_choice.toml` uses `ChoiceLogsum(1.099)` and all active modes. It is a research candidate. Do not describe it as the paper specification until the theory audit, nonlinear finite-difference gate, and coauthor decision are complete.

`rsue_census_ports_2017_candidate.toml` keeps the legacy component-CES convention but replaces the symmetrized foreign-water proxy with separate Census port-level imports and exports. It uses 2017 containerized vessel value, explicit Schedule C/D crosswalks, and a documented balanced-trade projection. It also activates all four modes. This is a data-and-model candidate, not the paper specification.

Use `rsue_legacy_ports_all_modes_control.toml` for a like-for-like comparison. It activates the same four modes under the same component-CES and congestion specifications but retains the legacy symmetrized port layer.

The legacy adapter records six historical operations: domestic-node count, foreign-node padding, modal symmetrization, within-mode normalization, RSUE modal weights, and terminal-based rail filtering. Generic projects do none of these operations.

The Census candidate preserves those operations for the domestic layers but does not symmetrize foreign water. Raw directional Census trade is not model-ready because imports and exports do not satisfy the current location-level balanced-flow identity. The builder RAS-projects both directions onto common port and foreign-region margins, records the adjustment, and fails if balancing requires support absent from the raw matrices. See `replication/rsue/census_ports/README.md` for refresh and build commands.

Run the candidate with:

```bash
julia --project=. bin/tnw.jl decompose \
  replication/rsue/rsue_census_ports_2017_candidate.toml
```

Legacy acceptance values and frozen output hashes are in `expected_summary.toml`; the corresponding Census-candidate targets are in `census_ports/expected_summary.toml`. The full result comparisons run only when the external data are present:

```bash
export RSUE_FROZEN_RESULTS_ROOT=/absolute/path/to/Output_complete_decomposition
julia --project=. replication/rsue/verify_legacy.jl
```

This gate verifies the three archived artifact hashes and compares every directed-arc result field against the frozen table. Public CI reports the restricted acceptance test as skipped rather than passed when `RSUE_DATA_ROOT` is absent.
