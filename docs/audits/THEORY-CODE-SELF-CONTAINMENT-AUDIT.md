# Theory, Code, and Self-Containment Audit

**Audit date:** 2026-07-26

**Package branch:** `codex/practitioner-guide`

**Package baseline:** `b6e08398a9e49e720f8594743a604197a50bbe33`

**Paper baseline:** Overleaf `cef3a13b539555bd568cb13332b5835d074afe18`

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

The private Overleaf `overleaf/live` cache was stale at the start of this
audit. It was rebuilt from `git show` at `cef3a13` rather than copied from a
working directory. All 11 cached files now match the corresponding Git objects
byte for byte, and their SHA-256 values and commit timestamp are recorded in
the private snapshot manifest. No Overleaf file, commit, or branch was
modified.

The guide reads paper-facing theory from that fixed snapshot. The snapshot is
evidence for the audit and is absent from the guide build dependency graph.

## Model states

| Model state | Modal index | Congestion | Status |
| --- | --- | --- | --- |
| Active paper application | `ChoiceLogsum(1.099)` | Edge-local road | Accepted |
| Generic economic-geography model | `ChoiceLogsum` | Modular edge and terminal | Accepted |
| Endpoint-terminal extension | `ChoiceLogsum` | Edge plus endpoint terminal | Verified extension |
| Urban commuting extension | `ChoiceLogsum` | Shared transport block, urban welfare row | Verified synthetic extension |
| Historical replication helper | `ComponentCES` | Legacy reduced system | Legacy-only |

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

- Full Julia suite: 621 passes and three documented expected failures for
  external-data integration gates.
- Independent Proposition 2 oracle: 55 of 55 checks passed.
- Grid example: analysis and decomposition passed all algebraic,
  contraction, conditioning, finite-difference, and limiting-case gates.
- Generated source assets and standalone figures reproduced byte for byte.
- HTML documentation built with doctests and cross-reference checks.
- Practitioner guide: 44 pages, no undefined citations or references, no
  duplicate bibliography keys, no LaTeX errors, and no overfull boxes.
- Visual inspection covered the title page, complete worked example, RSUE
  summary, provenance appendix, and references.
- A clean source clone, after `Pkg.instantiate()`, built and checked the guide
  without Dropbox, Overleaf, credentials, Python, or restricted data. Its PDF
  matched the workspace build byte for byte (SHA-256
  `69b4c991bc01ec5743f042a80d4624ea3487d4d1a3d0b864ea15ef14bfd1d7b3`).
- Provenance validation checked nine kernel records.
- Secret scan and `git diff --check` passed.
- Strict prose lint passed for authored guide prose. The schema appendix
  retains one technical repetition warning caused by repeated field
  requirements in a reference table.

## Remaining release gates

1. The package remains version `0.1.0` on a feature branch. A public release
   requires review, integration, a tag, and coauthor approval.
2. The public-safe RSUE ledger permits aggregate verification, not
   reconstruction of restricted microdata or link-level empirical results.
3. The Seattle module is an external-data extension. Historical GTFS records
   routes and schedules, not passenger counts; route-level ridership requires
   additional data or assumptions.
4. The package resolves Julia dependencies from the standard registry. It
   does not vendor Julia or an offline registry.
