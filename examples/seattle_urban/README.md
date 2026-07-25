# Seattle urban commuting replication adapter

This adapter converts the 217-location Seattle inputs from the Allen-Arkolakis
replication archive into the package's urban CSV schema. The source files are
not committed here.

```bash
export AA_REPLICATION_ROOT=/path/to/extracted/ReplicationFinal
julia --project=. examples/seattle_urban/prepare.jl
julia --project=. bin/tnw.jl validate examples/seattle_urban/generated/config.toml
julia --project=. bin/tnw.jl analyze examples/seattle_urban/generated/config.toml
julia --project=. examples/seattle_urban/verify_finite_differences.jl
julia --project=. examples/seattle_urban/compare_counterfactuals.jl
```

The builder verifies the published source hashes and the expected 217 nodes,
1,384 directed edges, and 692 reciprocal physical links. It uses the Berlin
calibration in the replication code: `theta=6.83`, `alpha=-0.12`, `beta=-0.10`,
and `lambda=(1/theta)*0.488`.

This is a local IFT evaluation at the observed Seattle baseline. It does not
run the replication archive's 1,384 separate nonlinear counterfactual jobs.
It also remains a one-road-mode replication adapter. Adding GTFS service and
ridership requires a documented edge-mode construction, modal calibration,
and explicit balancing to the recursive urban accounting identity.
