# Theory, Code, and Self-Containment Audit

**Audit date:** 2026-07-28

**Release candidate:** `v0.2.0`

**Package baseline:** `origin/main` at
`ffe0d296339eae7bdf7c5b451a121b1af243fdc2`, plus release-metadata changes
that do not alter the numerical implementation

**Paper baseline:** Overleaf `7fab4d5a91b1b06a2ebc4f94dcd6d451ebf9bf1d`

**Theory-library baseline:** Mathdown
`82a7cb3194a470d1fca001615d513d3d8822de36`

## Decisions

| Dimension | Decision |
| --- | --- |
| Paper theory implemented by the active economic-geography path | **Accepted** |
| Negative-power multimodal derivative | **Accepted** |
| Exact closure and decomposition identities | **Accepted** |
| Synthetic guide results | **Accepted and self-contained** |
| Accepted RSUE aggregate claims | **Accepted and hash-bound** |
| Generic package reproducibility | **Accepted** |
| Practitioner-guide release artifact | **Accepted and built from tracked source** |
| Restricted RSUE microdata replication | **External data required** |
| Seattle empirical replication | **External data required; candidate extension** |
| Offline Julia and registry installation | **Not claimed** |

The guide and package compute model-implied economic benefits from marginal
transport-cost changes. They do not constitute a complete social
cost-benefit analysis. Construction costs, financing, safety, pollution,
local disamenities, displacement, and distributional incidence require
additional data and welfare terms.

## Authority and provenance

The journal manuscript governs paper-facing equations and claims. The package
governs executable behavior and tested interfaces. The Mathdown project
curates derivations and unresolved decisions. Restricted empirical adapters
remain downstream of their source manifests.

This release audit compares the implementation directly with the synchronized
paper source at `7fab4d5`. The paper changes since the earlier guide audit
clarify assumptions, foreign-region treatment, and the omission of explicit
transshipment costs. They do not change the active modal index, route
recursion, Proposition 1, or Proposition 2. No Overleaf source or private
snapshot is part of the package or guide build.

## Model states

| Model state | Modal index | Congestion | Status |
| --- | --- | --- | --- |
| Active paper application | `ChoiceLogsum(1.099)` | Edge-local road | Accepted |
| Generic economic-geography model | `ChoiceLogsum` | Modular edge and terminal | Accepted |
| Endpoint-terminal extension | `ChoiceLogsum` | Edge plus endpoint terminal | Verified extension |
| Urban commuting extension | `ChoiceLogsum` | Shared transport block, urban welfare row | Verified synthetic extension |
| Historical replication helper | `ComponentCES` | Legacy reduced system | Legacy-only |
| Explicit mode-to-mode transshipment costs | Not implemented | Extension boundary |

The active index is

\[
\kappa_e=\left(\sum_m\kappa_{e,m}^{-\eta}\right)^{-1/\eta},
\qquad
s_{e,m}=\frac{\kappa_{e,m}^{-\eta}}
{\sum_n\kappa_{e,n}^{-\eta}}.
\]

The package implements this convention through
`modal_power(ChoiceLogsum) = -eta`. `ComponentCES` and the positive-power
helpers in `AdjointRSUE.jl` remain available for historical regression tests.
The guide labels them legacy-only and excludes them from the paper and urban
choice-logsum paths.

## Theory-code crosswalk

| Paper object or result | Implementation | Verification | Status |
| --- | --- | --- | --- |
| Negative-power modal logsum | `Specifications.jl`, `CompleteEngine.jl` | modal analytic and nonlinear finite differences | Accepted |
| Recursive route kernel and curvature \(\sigma-1\) | `CompleteEngine.jl`, `SharedTransport.jl` | contraction, absorption, margins, edge traffic | Accepted |
| Edge-mode traffic \(\Xi_{e,m}=s_{e,m}\Xi_e\) | route reconstruction and modal lift | traffic factorization and mode permutation | Accepted |
| World-income traffic normalization | `DataIO.jl`, route reconstruction | accounting and coherent rescaling | Accepted |
| Spatial coefficients \(e\) and \(\rho\) | `Specifications.jl`, `AdjointRSUE.jl` | coefficient and singular-boundary tests | Accepted |
| No-congestion Jacobian \(J^0\) | `assemble_J`, `build_closures` | Python oracle and dense-Jacobian checks | Accepted |
| Welfare row and adjoint | `welfare_gradient`, adjoint solve | direct-solve equivalence and efficient collapse | Accepted |
| Market-access exposure \(\mathcal T\) | exposure reconstruction | traffic-factorization identities | Accepted |
| Realized-friction forcing | `realized_forcing` | closure identities and finite differences | Accepted |
| Primitive forcing, \(\zeta\), and \(\chi=\zeta/s\) | `primitive_forcing`, `effective_ratio` | nonlinear finite differences | Accepted |
| Proposition 1 | `H` closure | efficient fixtures and Python oracle | Accepted |
| Proposition 2 | adjoint solve plus primitive forcing | Python oracle, synthetic and RSUE finite differences | Accepted |
| Schur transport elimination | `build_transport_closure` | eliminated and block-system equality | Accepted |
| `H`, `NC`, `NT`, `F`, `FM`, `FR` | `build_closures` | ladder and inverse-gap identities | Accepted |
| Exact decomposition channels | `structured_gap`, `mixed_channels` | Jacobian and channel reconstruction | Accepted |
| Bidirectional physical-link policy | `PolicySpecification`, `aggregate_physical` | reciprocal pairing and independent aggregation | Accepted |
| Urban commuting extension | `UrbanEngine.jl`, `UrbanNonlinear.jl` | one-mode oracle and multimodal nonlinear checks | Verified extension |
| RSUE foreign regions | `RSUEAdapter.jl` | adapter and paper-source cross-check | Accepted stylized integrated closure |

The active paper model aggregates modes on each physical edge. It does not
represent an explicit cost of switching from mode \(m\) to mode \(m'\) at a
node. Such costs require a node-mode network and new flow inputs. The generic
transport machinery can be extended in that direction, but the release does
not claim that the paper estimates or tests that extension.

The RSUE adapter assigns each of the six foreign regions the mean domestic
labor and income before renormalizing all 234 locations. They therefore enter
mobility, world income, and the common welfare derivative. This matches the
paper's current disclosure. The reported quantity is not a U.S.-only welfare
effect with exogenous foreign supply and demand.

### Proposition 1

At an efficient baseline, induced changes in prices, allocations, routes, and
modes have no first-order welfare effect under the maintained welfare
criterion. The derivative therefore reduces to observed edge-mode traffic:

\[
-\frac{d\log W}{d\log\bar\kappa_{kl,m}}=\Xi_{kl,m}.
\]

The implementation tests this collapse directly. The statement depends on the
efficient allocation and welfare aggregation; it is not automatically valid
under omitted distortions or alternative incidence rules.

### Proposition 2

For equilibrium residual \(G(z,\theta)=0\) and nonsingular
\(J=G_z\), the Implicit Function Theorem gives

\[
\frac{dz}{d\theta_{klm}}=-J^{-1}G_{\theta_{klm}}.
\]

The code solves \(J^\top a=q\) once and evaluates each welfare derivative from
the corresponding forcing vector. This is algebraically equivalent to a
separate state solve for each policy, but is much cheaper when the policy set
is large.

The paper's economics-facing statistic is

\[
-\frac{d\log W}{d\theta_{klm}}
=\chi_{klm}\rho\Xi_{kl,m}
\left(\mathcal M_k^{in}+\mathcal M_l^{out}\right).
\]

The package constructs the primitive forcing through the route, modal, and
congestion system. It does not impose \(\chi\) as a calibrated scalar. When the
realized derivative is nonzero, the output also records the effective ratio
between primitive and realized effects.

### Closure decomposition

All closures use the same observed baseline and policy forcing:

- `NC`: flexible routes and modes, no congestion;
- `NT`: flexible routes and modes, edge congestion;
- `F`: all declared congestion channels;
- `FM`: full congestion with modal shares fixed;
- `FR`: full congestion with baseline origin-destination edge incidence fixed;
- `H`: observed traffic only.

The package verifies

\[
m_F=m_{NC}-d_{edge}-d_{terminal}
=m_{FM}+d_{mode}
=m_{FR}+d_{route}.
\]

It reconstructs each closure Jacobian from analytical allocation, aggregate
feedback, road, and terminal blocks. The mode and route comparisons use the
mixed update and Woodbury correction. No fitted rank reduction, ridge
regularization, or silent route deletion is used.

## Worked-example audit

The guide now uses one example throughout: 25 economic locations on a
five-by-five reciprocal road grid, with transit available on the four central
east-west links. Each location has positive activity. The input builder
creates balanced margins and directed flows from the same recursive
accounting system used by the model. No private data or hidden balancing step
is involved.

The committed example has:

- 25 nodes;
- 80 directed road arcs and 40 reciprocal physical road links;
- eight directed transit edge-mode observations on the central spine;
- 88 positive-flow edge-mode pairs;
- route-kernel spectral radius 0.369;
- full-Jacobian condition number \(9.16\times10^3\);
- maximum inverse-gap residual \(1.10\times10^{-15}\);
- maximum channel-reconstruction residual \(1.65\times10^{-13}\).

The mean traditional and primitive extended elasticities are 0.010520 and
0.005425. Their Pearson and rank correlations are 0.990 and 0.909. One
horizontal link rises from rank 26 to 17, while one vertical link falls from
rank 17 to 28. These changes are modest at the top of the ranking. They are
larger among links with similar direct traffic.

The signed mean components of traditional minus extended welfare are:

| Component | Mean contribution |
| --- | ---: |
| Externality scale | 0.027352 |
| Equilibrium propagation | -0.027426 |
| Road congestion | -0.001543 |
| Terminal congestion | -0.000142 |
| Primitive-cost pass-through | 0.006855 |

The positive externality term and negative propagation term nearly cancel.
The guide reports signed levels because percentage shares would be unstable
relative to the smaller net gap.

All example statistics, the top-link table, and four figures are generated by
`scripts/build_practitioner_guide_assets.jl`. A separate check regenerates the
sources and figures in temporary directories and rejects byte-level drift.
Representative road and transit shocks pass independent central finite
differences below \(10^{-6}\). The efficient, one-mode, unique-route, and
zero-terminal limits are tested explicitly.

## RSUE result audit

The accepted aggregate result vintage has 234 nodes, 704 directed policies,
and 352 bidirectional physical-link experiments. The public-safe ledger
reports:

| Statistic | Value |
| --- | ---: |
| Mean traditional elasticity | 0.0003872368807309085 |
| Mean realized full-model elasticity | 0.0005133741112112903 |
| Mean primitive extended elasticity | 0.00022309500106786957 |
| Median primitive extended elasticity | 0.00018070218508596492 |
| Maximum primitive extended elasticity | 0.0008718749697784064 |
| Pearson correlation with traditional statistic | 0.9474377146863426 |
| Spearman rank correlation | 0.9591921172385324 |
| Top-ten overlap | 4 |

The tracked aggregate ledger is bound to the accepted configuration, Census
overlay, directed output, physical output, and restricted source claim ledger
by SHA-256. Its numerical values are checked against
`expected_summary.toml`. When the restricted output files are present, the
guide asset generator verifies their hashes too. A fresh clone can therefore
verify and display the accepted aggregate claims without containing the
restricted result table or raw inputs.

The accepted RSUE decomposition also contains large offsetting signed terms:
externality scale \(0.0010068\), equilibrium propagation \(-0.0011017\), road
congestion \(-0.0000313\), terminal congestion zero in the headline
specification, and primitive-cost pass-through \(0.0002903\).

## Verification performed

- Full Julia suite on Julia 1.10 and 1.12: 656 passes and three documented
  expected failures for external-data integration gates on each version.
- Independent Proposition 2 oracle: 55 of 55 checks passed.
- Grid example: analysis and decomposition passed all algebraic,
  contraction, conditioning, finite-difference, and limiting-case gates.
- Generated source assets and standalone figures reproduced byte for byte.
- HTML documentation built with doctests and cross-reference checks.
- Practitioner guide: 80 pages, no undefined citations or references, no
  duplicate bibliography keys, no LaTeX errors, and no overfull boxes.
- Visual inspection covered the title page, complete worked example, RSUE
  summary, provenance appendix, and references.
- A fresh worktree from `origin/main`, after `Pkg.instantiate()`, built the
  guide without Dropbox, Overleaf, credentials, or restricted data. Python is
  used only by the release-time asset drift checks. The PDF has SHA-256
  `15579449bc32a1101fe58b693f30683dbbf5eb58f330f56b170b0fee3a789a2f`.
- Provenance validation checked nine kernel records.
- Secret scan and `git diff --check` passed.
- Release metadata checks confirm that `Project.toml`, `CITATION.cff`, the
  guide, changelog, and locked RSUE environment all identify version `0.2.0`.
- Intermediate writing, reasoning, figure-review, Claude, and Codex helper
  logs are excluded from the release source.

## Remaining release gates

1. Version `0.2.0` is a release candidate. Tag `v0.2.0` should be created only
   after review and coauthor approval. The tag workflow will rerun the tests
   and attach the compiled practitioner guide and checksum.
2. The public-safe RSUE ledger permits aggregate verification, not
   reconstruction of restricted microdata or link-level empirical results.
3. The Seattle module is an external-data extension. Historical GTFS records
   routes and schedules, not passenger counts; route-level ridership requires
   additional data or assumptions.
4. The package resolves Julia dependencies from the standard registry. It
   does not vendor Julia or an offline registry.
