# Changelog

The project follows semantic versioning. Notable user-facing changes are
recorded here.

## [Unreleased]

## [0.2.0] - 2026-07-30

### Models and welfare calculations

- Adopt the negative-power `ChoiceLogsum` as the paper-facing modal
  specification while retaining `ComponentCES` for legacy reproduction.
- Add a multimodal urban commuting IFT that shares the economic-geography
  route, mode, congestion, and pass-through operators.
- Add edge-mode-specific congestion elasticities, endpoint-terminal
  congestion, sparse policy bundles, and directed or bidirectional policies.
- Complete the exact `H`, `NC`, `NT`, `F`, `FM`, and `FR` closure ladder and
  its analytical allocation, scarcity, and equilibrium channels.
- Add a lightweight edge-local solver for networks whose fixed-route
  decomposition is too large to construct.

### Data, examples, and plotting

- Add `tnw init` and a documented own-data CSV/TOML workflow.
- Add self-contained grid, Braess-style, cow, one-mode urban, and multimodal
  urban examples.
- Add hash-pinned, on-demand Sioux Falls, Seattle, and Westeros adapters with
  explicit source and licensing metadata.
- Add a credential-safe Census port-trade pipeline and a balanced directional
  2017 imports/exports adapter.
- Add deterministic maps, welfare scatters, ranking tables, and decomposition
  figures with a common visual design.

### Verification and reproducibility

- Add nonlinear choice-logsum finite differences, exact closure and
  decomposition checks, route-reconstruction tests, policy aggregation tests,
  and deterministic output hashes.
- Validate congestion keys, mode order, terminal identifiers, accounting
  identities, finite inputs, condition numbers, and unsupported policy units
  before analysis.
- Add a locked RSUE environment, hashed Python verification dependencies,
  machine-readable kernel provenance, and release secret scanning.
- Bind paper artifacts to code, configuration, input, environment,
  finite-difference, and output hashes.

### Documentation and release

- Add task-oriented package documentation, a self-contained practitioner
  guide, a theory-code audit, a citation file, and reproducible release
  artifacts.
- Add standard Make targets for testing, documentation, guide builds,
  plotting checks, and release verification.

## [0.1.0] - 2026-07-17

- Add the typed Julia API and TOML-driven CLI.
- Add schema-versioned CSV inputs and a distributable toy network.
- Add choice-logsum and legacy component-CES modal specifications.
- Add edge, endpoint-terminal, composite, and no-congestion specifications.
- Port the audited adjoint and route-resolvent kernels from the frozen July
  2026 package.
- Add the initial closure ladder, sensitivity paths, manifests,
  documentation, CI, and external RSUE adapter contract.

[Unreleased]: https://github.com/sfuchs-de/TransportNetworkWelfare.jl/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/sfuchs-de/TransportNetworkWelfare.jl/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sfuchs-de/TransportNetworkWelfare.jl/releases/tag/v0.1.0
