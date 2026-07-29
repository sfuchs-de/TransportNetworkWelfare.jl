# Contributing

Use Julia 1.10 or later and submit changes through a focused pull request. An
interface, configuration, output, or interpretation change should include a
test, documentation update, and changelog entry.

## Development checks

Instantiate the package and run the standard checks:

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate()'
make check
```

`make check` runs the Julia suite, toy CLI smoke test, documentation build,
release-metadata check, provenance verification, secret scan, and
`git diff --check`. Run `make public-release-check` when changing figures,
guide text, release assets, or plotting behavior.

## Numerical changes

Changes to analytical kernels or to a paper-facing modal, routing, congestion,
shock, or welfare specification require:

- an independent finite-difference test;
- updated algebraic and limiting-case tests;
- an updated theory-code audit and provenance record; and
- explicit comparison with the accepted paper configuration.

Do not infer analytical decomposition channels from fitted residuals or apply
regularization to make a failed identity pass. Unsupported or singular cases
must fail with a diagnostic.

## Data and generated files

Do not commit credentials, raw RSUE or Seattle inputs, API caches,
machine-specific paths, or generated output directories. Record external
source versions and hashes, and make builders fail when required inputs are
missing or inconsistent.

Generate paper and practitioner-guide artifacts with their checked builders
rather than editing them by hand. If restricted-data checks cannot run, state
the skipped checks and the reason.

The [third-party notice](THIRD_PARTY_NOTICES.md) governs external examples and
derived assets. Confirm redistribution terms before adding an external file to
Git.
