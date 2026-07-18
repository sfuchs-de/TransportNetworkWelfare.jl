# Changelog

All notable changes are documented here. The project follows semantic versioning.

## [Unreleased]

- Reject nonfinite parameters, diagnostics, sensitivity values, and ill-conditioned transport closures.
- Fail CLI runs when numerical verification fails and record sensitivity outputs in run manifests.
- Record dynamic package/Git state without machine-specific configuration paths.
- Verify frozen RSUE artifact hashes and all mapped directed-result fields.
- Pin CI actions and broaden repository secret scanning.
- Reserve the choice-consistent RSUE configuration for theory and coauthor review.
- Add external-data replication once redistribution and specification gates pass.

## [0.1.0] - 2026-07-17

- Add the typed Julia API and configuration-driven CLI.
- Add schema-versioned CSV inputs and a distributable toy network.
- Add choice-logsum and legacy component-CES modal specifications.
- Add edge, endpoint-terminal, composite, and no-congestion specifications.
- Port the audited adjoint and route-resolvent kernels from the frozen July 12 package.
- Add the exact `H`, `NC`, `NT`, `F`, `FM`, and `FR` closure ladder.
- Add sensitivity paths, manifests, documentation, CI, and the external RSUE adapter contract.
