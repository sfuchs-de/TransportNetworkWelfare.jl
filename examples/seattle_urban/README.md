# Seattle urban commuting road-input diagnostic

This adapter converts the 217-location Seattle inputs from the Allen-Arkolakis
replication archive into the package's urban CSV schema. It preserves the
published LODES residence/workplace and HPMS AADT inputs for provenance. The
source files are not committed here.

```bash
export AA_REPLICATION_ROOT=/path/to/extracted/ReplicationFinal
julia --project=. examples/seattle_urban/prepare.jl
julia --project=. bin/tnw.jl validate examples/seattle_urban/generated/config.toml
```

The builder verifies the published source hashes and the expected 217 nodes,
1,384 directed edges, and 692 reciprocal physical links. It uses the parameter
values in the replication code: `theta=6.83`, `alpha=-0.12`, `beta=-0.10`, and
`lambda=(1/theta)*0.488`.

This conversion is not a valid package baseline without an external balancing
decision. LODES commuter margins and HPMS AADT measure different populations;
as provided, they imply a maximum normalized recursive-stock disagreement of
about `0.108`, and `validate` fails explicitly. The adapter remains available
to diagnose and reproduce that mismatch; analysis and finite-difference
commands should not be run on the rejected baseline.

The separate `examples/seattle_multimodal` candidate routes the LODES OD matrix
over road and historical GTFS networks. It uses ACS transit shares and thereby
constructs edge flows that satisfy the urban accounting identity without
silently balancing AADT.
