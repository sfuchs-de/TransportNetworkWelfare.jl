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

The legacy adapter records six historical operations: domestic-node count, foreign-node padding, modal symmetrization, within-mode normalization, RSUE modal weights, and terminal-based rail filtering. Generic projects do none of these operations.

Aggregate acceptance values and frozen output hashes are in `expected_summary.toml`. The full result comparison runs only when the external data are present.
