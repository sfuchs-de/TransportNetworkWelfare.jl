# Changelog

All notable changes are documented here. The project follows semantic versioning.

## [Unreleased]

- Add a symmetric multimodal urban IFT with shared route, mode, edge
  congestion, terminal congestion, and pass-through operators.
- Add urban `NC`, `NT`, `F`, `FM`, and `FR` closure results, an independent
  nonlinear finite-difference solver, and a distributable road/transit example.
- Support edge-mode-specific congestion elasticities supplied by a validated
  input column, including common-scale sensitivity and manifest diagnostics.
- Add self-contained Braess-style and three-dimensional cow networks, plus a pinned, on-demand
  Sioux Falls adaptation with local BPR elasticities.
- Add deterministic generic network plotting and an examples guide that marks
  the Seattle urban-model extension as a separate model boundary.
- Add an ASCII PLY surface renderer and a hash-pinned, on-demand cow mesh with
  explicit third-party licensing metadata.
- Add a separate Allen--Arkolakis urban commuting closure with residence and
  workplace distributions, an analytic adjoint, nonlinear exact-hat checks,
  a self-contained toy example, and a hash-pinned Seattle replication adapter.
- Add an on-demand Westeros example that converts hash-pinned public ArcGIS
  geography into a transparent synthetic economic-geography baseline.
- Add a sparse edge-local adjoint solver and an all-vertex cow-mesh builder for
  networks whose exact fixed-route decomposition is too large to construct.
- Validate congestion keys, inactive modes, terminal identifiers, and the RSUE
  matrix mode order before model construction.
- Give `directed_arc`, `physical_link`, and `both` policy units distinct output
  behavior, and permit valid zero welfare derivatives with nullable effective
  pass-through ratios.
- Add exact analytical allocation, scarcity, and equilibrium channels for the
  road, terminal, fixed-mode, and fixed-route closure rungs, with fail-closed
  Jacobian and channel reconstruction checks.
- Keep ordinary welfare analysis on the lightweight flexible-route closure and
  report a preflight memory estimate for the full fixed-route decomposition.
- Add a nonlinear choice-logsum finite-difference harness, a locked RSUE Julia
  environment, hashed Python verification dependencies, and machine-readable
  kernel provenance.
- Pin the Census CBSA archive hash and record GDAL, Python, configuration,
  input, source, environment, and verification-report hashes in paper artifacts.
- Add `tnw init` for portable external CSV/TOML projects.
- Document the own-data accounting contract and directed/physical output schema.
- Reject nonfinite parameters, diagnostics, sensitivity values, and ill-conditioned transport closures.
- Fail CLI runs when numerical verification fails and record sensitivity outputs in run manifests.
- Record dynamic package/Git state without machine-specific configuration paths.
- Verify frozen RSUE artifact hashes and all mapped directed-result fields.
- Pin CI actions and broaden repository secret scanning.
- Reserve the choice-consistent RSUE configuration for theory and coauthor review.
- Add a credential-safe Census port-trade pipeline and a separate balanced,
  directional 2017 imports/exports candidate adapter.
- Add external-data replication once redistribution and specification gates pass.

## [0.1.0] - 2026-07-17

- Add the typed Julia API and configuration-driven CLI.
- Add schema-versioned CSV inputs and a distributable toy network.
- Add choice-logsum and legacy component-CES modal specifications.
- Add edge, endpoint-terminal, composite, and no-congestion specifications.
- Port the audited adjoint and route-resolvent kernels from the frozen July 12 package.
- Add the exact `H`, `NC`, `NT`, `F`, `FM`, and `FR` closure ladder.
- Add sensitivity paths, manifests, documentation, CI, and the external RSUE adapter contract.
