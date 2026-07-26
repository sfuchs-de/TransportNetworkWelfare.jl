# Theory, Code, and Self-Containment Audit

**Audit date:** 2026-07-26

**Package baseline:** `de708f21eccfc18b36f1c3502ae2c932cca59d8f`

**Paper baseline:** Overleaf `cef3a13b539555bd568cb13332b5835d074afe18`

**Theory-library baseline:** Mathdown `23f350a4de16eb842803f53267278deccb724f5d`

**Theory-library reconciliation:** Mathdown `82a7cb3194a470d1fca001615d513d3d8822de36`
([draft PR #94](https://github.com/sfuchs-de/mathdown-library/pull/94))

## Executive findings

### Theory: accepted with stated scope

The active economic-geography implementation matches the paper's maintained
model: a negative-power modal logsum, recursive routing with curvature
\(\sigma-1\), world-income-normalized value traffic, edge-local road
congestion in the headline application, and an adjoint/IFT welfare derivative.
The endpoint-terminal and urban commuting systems are extensions and are
identified as such.

The package does not establish that the model is a complete social
cost-benefit analysis. Construction costs, financing, pollution, safety,
neighborhood effects, displacement, and distributional incidence are outside
the welfare derivative. The code computes the model-implied economic benefit
of the declared transport-cost shock.

### Implementation: accepted

The active path uses `modal_power(ChoiceLogsum)=-eta` throughout the common
route-modal-congestion system. It builds the no-congestion spatial Jacobian,
eliminates the transport block by a Schur complement, forms primitive and
realized shock vectors, and projects the resulting state derivative with the
welfare row. Closure and decomposition identities are checked before results
are released.

Two exported functions in `AdjointRSUE.jl`, `congestion_J` and `chi_wedge`,
implement the older positive-power `ComponentCES` formulas. They are retained
for legacy verification and are now labeled accordingly. They are not called
by the active paper configuration.

### Numerical results: accepted

An isolated run of the current branch on the hash-verified restricted inputs
reproduces the paper's 352 physical-link results to machine precision:

| Statistic | Paper ledger | Current branch | Absolute difference |
| --- | ---: | ---: | ---: |
| Mean extended elasticity | 0.0002230950010678702 | 0.0002230950010678695 | \(7.0\times10^{-19}\) |
| Median extended elasticity | 0.0001807021850859650 | 0.0001807021850859649 | \(5.4\times10^{-20}\) |
| Maximum extended elasticity | 0.0008718749697784170 | 0.0008718749697784064 | \(1.1\times10^{-17}\) |
| Pearson correlation with Hulten | 0.9474377146863427 | 0.9474377146863426 | \(1.1\times10^{-16}\) |
| Spearman rank correlation | 0.9591921172385324 | 0.9591921172385319 | \(4.4\times10^{-16}\) |

The independently solved nonlinear choice-logsum system gives a maximum
absolute finite-difference error of \(1.61\times10^{-15}\) on the stratified
RSUE policy sample. This is well below the \(10^{-6}\) acceptance threshold.

### Generic reproducibility: accepted

A fresh local clone can instantiate the Julia environment, validate and
decompose the toy project, build the HTML documentation, and run the full test
suite. The restricted-data test run reports 628 passes and two expected skips:
the pinned Sioux Falls integration source and the complete Seattle external
data bundle. The toy, Braess, cow, urban-toy, and urban-multimodal inputs are
committed and require no private data.

The package resolves its declared Julia dependencies from the standard
registry. Self-containment therefore covers source, configuration, and
reproducible dependency resolution; it does not include an offline copy of
Julia or the package registry.

### Restricted empirical replication: accepted with external-data boundary

The RSUE and Seattle adapters are reproducible but not self-contained data
bundles. They require external files whose names and hashes are declared in
their source manifests. Missing, stale, or inconsistent files cause an
explicit failure. Credentials and restricted raw inputs are not committed.

## Authority and model states

| Model state | Modal index | Congestion | Status |
| --- | --- | --- | --- |
| Active paper application | `ChoiceLogsum(1.099)` | Edge-local road, 0.092 | Accepted |
| Corrected generalized implementation | `ChoiceLogsum` | Modular edge/terminal | Accepted |
| Endpoint-terminal extension | `ChoiceLogsum` | Edge plus endpoint-terminal | Verified extension |
| Urban commuting extension | `ChoiceLogsum` | Shared transport block, urban welfare row | Verified synthetic extension |
| Frozen legacy replication | `ComponentCES` | Historical reduced system | Provenance only |

Overleaf governs the journal-facing statement. This repository governs
executable behavior. The practitioner guide is downstream of both and names
the governing source for each claim.

## Equation-to-code ledger

| Paper object or result | Paper anchor | Implementation anchor | Main verification | Status |
| --- | --- | --- | --- | --- |
| Negative-power modal logsum and mode shares | `2_Model.tex`, eq. `mode-ces` | `Specifications.jl:21-44`; `CompleteEngine.jl:257-267` | `test/test_modal.jl` nonlinear central differences | Accepted |
| Route recursion and curvature \(\sigma-1\) | `2_Model.tex`, eqs. `tau-soft`, `tau-recursive` | `CompleteEngine.jl:115-137`; `SharedTransport.jl:28-47` | route contraction, bilateral margins, edge traffic | Accepted |
| World-income traffic share | `2_Model.tex`, eq. `traffic` | `DataIO.jl`; `IFTDecomposition.reconstruct_route_kernel` | accounting and coherent-rescaling tests | Accepted |
| Spatial regularity \(e\) and \(\rho\) | Proposition 2 | `Specifications.jl:130-151`; `AdjointRSUE.jl:32-55` | coefficient and singular-boundary tests | Accepted |
| No-congestion Jacobian \(J^0\) | Appendix A residual system | `AdjointRSUE.assemble_J`; `CompleteEngine.build_closures` | Python oracle and dense-Jacobian tests | Accepted |
| Welfare row \(q\) | Appendix A welfare closure | `AdjointRSUE.welfare_gradient` | oracle and efficient-collapse tests | Accepted |
| Market-access exposure \(\mathcal T\) | Proposition 2 and traffic lemma | `AdjointRSUE.node_visit_stock`; generic data loader | traffic-factorization and stock-agreement tests | Accepted; technical alias retained |
| Realized cost forcing | Appendix A \(b^r\) | `decomposition_rows`, `realized_forcing` | inverse-gap and closure-ladder identities | Accepted |
| Primitive cost forcing and \(\chi\) | Proposition 2 \(\zeta,\chi\) | `CompleteEngine.primitive_forcing`; `effective_ratio` | independent nonlinear finite differences | Accepted |
| Proposition 1/Hulten collapse | Proposition 1 and corollary | `decomposition_rows`, H closure | efficient fixtures and Python oracle | Accepted |
| Proposition 2 edge elasticity | Proposition 2 | adjoint solve plus primitive forcing | RSUE finite differences and edge-local/full agreement | Accepted |
| Schur transport elimination | Computational Appendix C | `build_transport_closure`, lines 270-302 | eliminated versus uneliminated systems | Accepted |
| `H`, `NC`, `NT`, `F`, `FM`, `FR` | Computational Appendix C | `build_closures`, lines 324-381 | ladder and inverse-gap residuals | Accepted |
| Exact decomposition channels | Computational Appendix C | `structured_gap`; `mixed_channels` | Jacobian and channel reconstruction | Accepted |
| Physical-link policy | Data and quantitative sections | `PolicySpecification`; `aggregate_physical` | reciprocal-pair and aggregation tests | Accepted |
| Urban commuting extension | Package documentation, not active paper | `UrbanEngine.jl`; `UrbanNonlinear.jl` | one-mode oracle and nonlinear multimodal checks | Verified extension |

## Proposition 1 audit

The paper's first proposition is an envelope result. With
\(\alpha=\beta=\lambda_m=0\), the competitive allocation is efficient under
the maintained mobile-labor model. The first-order effects of induced changes
in prices, locations, routes, and modal allocations vanish. Differentiating
the resource cost with respect to the primitive edge-mode cost leaves the
observed edge-mode traffic share:

\[
-\frac{d\log W}{d\log\bar\kappa_{kl,m}}=\Xi_{kl,m}.
\]

The implementation checks this result in efficient fixtures and requires the
error to be below \(10^{-8}\). The result should not be carried mechanically
to a model with a distorted baseline, omitted incidence terms, or a welfare
aggregator that does not represent the planner's objective.

## Proposition 2 audit

Let \(z\) denote the transformed spatial state and write the equilibrium
residual as \(G(z,\theta)=0\). At an interior baseline with nonsingular
Jacobian \(J=G_z\), the Implicit Function Theorem gives

\[
\frac{dz}{d\theta_{klm}}=-J^{-1}G_{\theta_{klm}}.
\]

The code solves the adjoint system \(J^\top a=q\), where \(q\) is the welfare
row, and evaluates the derivative as \(-a^\top G_{\theta_{klm}}\). This is
algebraically equivalent to solving once for every policy shock, but it
requires one adjoint solve followed by sparse products.

The paper's economics-facing expression is

\[
-\frac{d\log W}{d\theta_{klm}}
=\chi_{klm}\rho\Xi_{kl,m}
\left(\mathcal M_k^{in}+\mathcal M_l^{out}\right).
\]

The implementation does not insert \(\chi\) as an independently chosen scalar.
It constructs the primitive edge-mode shock, lets route, modal, and congestion
quantities respond through the transport system, and records the effective
ratio when the realized derivative is nonzero.

## Decomposition audit

Every closure uses the same observed baseline and policy forcing. The code
constructs:

- `NC`: flexible routes and modes, no congestion;
- `NT`: flexible routes and modes, edge congestion;
- `F`: all declared congestion channels;
- `FM`: full congestion with modal shares fixed;
- `FR`: full congestion with baseline origin-destination edge incidence fixed;
- `H`: observed traffic only.

The reported wedges obey

\[
m_F=m_{NC}-d_{edge}-d_{terminal}
=m_{FM}+d_{mode}
=m_{FR}+d_{route}.
\]

The inverse-gap identity is checked directly for every policy arc. The code
also reconstructs each closure Jacobian from its sparse allocation block,
aggregate feedback term, edge block, and terminal block. Mode and route
comparisons use the explicit mixed update and Woodbury correction. No
rank-reduction fit or ridge regularization is used.

## Reproducibility boundary

### Included in a clone

- Julia source, tests, schemas, CLI, and documentation;
- complete toy, Braess, cow, and synthetic urban inputs;
- expected aggregate RSUE metrics and non-sensitive hashes;
- data acquisition and adapter code for the external examples.

### Required externally

- a Julia installation and registry access for first-time dependency
  resolution;
- restricted domestic RSUE inputs for the paper replication;
- the Allen--Arkolakis archive and pinned external sources for Seattle;
- Python only for optional publication plotting, not for Julia analysis or the
  practitioner-guide PDF build.

## Verification performed

- The full Julia suite passed 628 tests. The two expected skips require the
  pinned Sioux Falls source files and the complete Seattle external-data
  bundle.
- The independent Proposition 2 oracle passed all 55 checks.
- The restricted RSUE builder reproduced the accepted numerical summary twice.
  All generated analytical tables, claims, TeX macros, and figures had
  identical hashes. The run manifest itself differed only because it records
  its creation time; its embedded output-hash map was unchanged.
- The compact practitioner guide compiled to 43 pages without undefined
  citations or references. Visual inspection covered the title page, theory, worked
  example, code crosswalk, and provenance appendix.
- The prose lint found no P0 or P1 issues. Its strict technical-source scan
  flags repeated TOML section names, schema headings, and quantified words such
  as “every” in validation requirements. These are retained because they state
  exact configuration and domain conditions rather than serving as prose
  scaffolding.

## Residual risks and release gates

1. The package is still version `0.1.0` on stacked draft feature branches.
   Public release should wait until those branches are integrated and tagged.
2. The active paper result table is numerically reproduced and the expected
   summary now binds the current CSV and claim-ledger hashes. A release tag
   should freeze these files again after the stacked feature branches merge.
3. Mathdown commit `82a7cb3` reconciles the synthesis, claim ledger, source
   manifest, and urban extension with the accepted negative-power modal choice
   and 234-node result vintage. This documentation remains a release gate until
   draft PR #94 is reviewed and merged.
4. Seattle GTFS supplies routes and schedules, not passenger counts. ACS
   residential mode shares and the external Metro route table do not identify
   route-level commuter flows without additional assumptions.

## Acceptance decision

| Dimension | Decision |
| --- | --- |
| Paper theory implemented by active economic-geography path | **Accepted** |
| Choice-logsum analytical derivative | **Accepted** |
| Exact closure and decomposition implementation | **Accepted** |
| Accepted RSUE numerical claims | **Accepted** |
| Generic package self-containment | **Accepted** |
| Offline-vendored installation | **Not claimed** |
| Restricted RSUE and Seattle data self-containment | **Not applicable; external-data modules** |
| Current explanatory and Mathdown documentation | **Reconciled on draft branches; merge pending** |
