# Contributing

Use Julia 1.10 or later and make changes through a pull request. Keep each change
focused, add a test for every behavioral change, and update the user
documentation and `CHANGELOG.md` when an interface, configuration, output, or
interpretation changes.

Run the package and smoke tests before opening a pull request:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
julia --project=. bin/tnw.jl validate examples/toy/config.toml
julia --project=. bin/tnw.jl analyze examples/toy/config.toml
julia --project=. bin/tnw.jl decompose examples/toy/config.toml
```

Changes to analytical kernels or to a paper-facing modal, routing, congestion,
shock, or welfare specification require an independent finite-difference test,
an updated theory-code audit, and a provenance note. Do not update generated
paper or guide artifacts by hand; use their checked builders and commit only
the source assets intended for version control.

Do not commit raw RSUE or Seattle inputs, credentials, API responses,
machine-specific paths, generated `output/` directories, or local agent
instructions and helper logs. External-data code must fail clearly when a
required input is absent and must record relied-on source hashes.

For release-facing changes, also run:

```bash
python3 scripts/verify_provenance.py
make release-metadata-check
make practitioner-guide-check
julia --project=docs docs/make.jl
```

The practitioner-guide check uses the pinned plotting environment when figures
are regenerated. Pull requests that cannot run restricted-data checks should
state which checks were skipped and why.
