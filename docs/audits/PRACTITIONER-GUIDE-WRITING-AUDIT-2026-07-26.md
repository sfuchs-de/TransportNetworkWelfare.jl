# Practitioner Guide Writing and Reasoning Audit

Date: 2026-07-26

## Scope and verdict

This audit evaluates the guide's practitioner journey, argument structure,
mathematical exposition, notation, empirical instructions, output
interpretation, citations, appendices, and rendered PDF. It does not replace
the paper's proof audit or the package's numerical verification.

The revised guide is suitable for circulation as a combined practitioner guide
and technical reference. Part I now takes an analyst from suitability screening
through model choice, data preparation, configuration, execution, one output
row, and acceptance checks. Part II develops the models and welfare calculation
in dependency order. Part III covers implementation, the worked example, and
the external-data applications. Part IV contains schemas, algorithms,
verification, additional examples, and provenance. The remaining limitations
are stated in the adversarial findings below.

## Response to the external assessment

The assessment identified a genre problem: the earlier guide combined
onboarding, theory, software reference, and provenance without a sufficiently
direct applied path. The revision retains one PDF but separates those functions
visibly.

### Practitioner journey

- The title page now states the policy question, output, worked example, and
  boundary to a complete appraisal.
- A separate reading guide gives applied, theoretical, urban, contributor, and
  audit paths. Diagnostics are mandatory for empirical users.
- Part I is a four-page stand-alone quick start. It begins with a policy
  suitability screen, distinguishes local policy size from the adjustment
  horizon, compares the economic-geography and urban closures, and reports the
  maturity of each package feature.
- The quick start states the software prerequisites, package API version,
  typical grid runtime, and generated decomposition-memory estimate. It gives
  copy-safe commands for installation, initialization, validation, analysis,
  decomposition, and later package updates.
- The data-to-result workflow now appears in Part I. The more detailed build
  stages refer back to that diagram.
- The quick start interprets one generated output row. It distinguishes the
  Traditional approach, full realized-cost effect, and full primitive-cost effect,
  then converts the configured one-percent shock into a log-welfare and
  percentage-welfare approximation.

### Economic interpretation

- Section 2 introduces the four-factor welfare formula before the derivation:
  traffic, primitive-to-user pass-through, the common spatial scale, and the
  two endpoint access multipliers.
- An early mechanism diagram links the primitive edge-mode cost to realized
  cost, routes and modes, the spatial equilibrium, and welfare, with traffic
  and congestion feedback shown explicitly.
- The guide explains how a welfare elasticity enters a conventional appraisal.
  It states the conditions for a money-metric conversion and gives a separate
  net-present-value expression for project timing, costs, and omitted benefits.
- The efficient limiting substitutions are displayed immediately after
  Proposition 2. They recover the traffic statistic and connect the extended
  result directly to the Hulten benchmark.
- The numerical values of the transformation scalar and common spatial scale
  were moved from the general theorem discussion to the freight application.

### Data and outputs

- A boxed explanation states why the generic schema has flows but no baseline
  cost column. It separates observed margins and flows, reconstructed shares,
  calibrated elasticities, and adjoint-computed multipliers.
- The guide states every normalization explicitly. It warns that edge traffic
  generally does not sum to one because a shipment or commuter can traverse
  several edges.
- A data-availability matrix maps common raw sources to the missing empirical
  construction. A generic balancing procedure records target margins,
  structural zeros, projection method, tolerance, iterations, errors, input
  distance, and hashes.
- The output dictionary documents headline fields, units, sign conventions,
  nullable pass-through, decomposition residuals, physical-link aggregation,
  and the merge to engineering cost data.
- The reporting template requires level and rank statistics, numerical
  diagnostics, sensitivity, and a gross-benefit scope statement.

### Terminology and notation

- The three welfare objects use consistent labels throughout:
  `Traditional approach` for the traffic benchmark, `full realized-cost
  effect`, and `Extended approach` for the full primitive-cost effect.
- Congestion is denoted by `gamma` in the theory. Historical configuration
  fields such as `lambda_road` are identified as compatibility names.
- Each `(edge_id, mode)` pair must be unique; modal rows on the same directed
  connection share an `edge_id`.
- Node shares are strictly positive in the accepted interior baseline. The
  guide no longer alternates between positive and nonnegative requirements.
- The urban welfare normalizer is written as `varpi_U`, leaving `chi` for
  primitive-cost pass-through. Appendix A records `chi_U` as the historical
  implementation name.
- `ComponentCES` is marked legacy-only wherever it appears. The active paper
  and guide use the negative-power `ChoiceLogsum`.

### Technical layering and provenance

- The main text retains the closure ladder, signed Hulten-gap identity, and
  economic interpretation. Low-rank update formulas and pseudocode are in
  Appendix B.
- The internal module inventory and kernel history were removed from the main
  practitioner path. Appendix F gives a concise authority and reproducibility
  boundary and points to the tracked technical audits for line-level history.
- The guide identifies the public grid as fully distributable. Freight and
  Seattle are external-data modules; Seattle is labeled a candidate
  application at the start of its discussion.

### PDF and visual presentation

- Tables are numbered sequentially. References begin on a new page.
- The PDF has document language metadata, section and subsection bookmarks,
  and a web-linearized release copy.
- Figures use direct labels, line widths, marker shapes, and terminal rings in
  addition to color. All generated figures are available as PDF and transparent
  PNG files.
- The final PDF is not yet a semantically tagged PDF. This is recorded as a
  remaining accessibility task rather than described as completed.

## Reasoning chain

The guide now follows one dependency chain:

1. Decide whether a marginal derivative is appropriate for the policy.
2. Select the economic-geography or urban spatial closure.
3. Construct model-ready margins and directed edge-mode flows.
4. Define the primitive cost change, mode, and policy unit.
5. Validate accounting, route contraction, modal support, and regularity.
6. Establish the traffic benchmark and the conditions under which it is exact.
7. Add routing, modal, congestion, and spatial responses to obtain the
   realized- and primitive-cost derivatives.
8. Decompose the difference into modeled mechanisms.
9. Interpret one link result, test numerical accuracy, and examine parameter
   sensitivity.
10. Combine the gross-benefit derivative with application-specific project
    costs and omitted effects outside the package.

Sections and subsections now announce the object they need, define it before
using it, and close by stating what the next step adds. Short qualifications
were absorbed into the paragraph whose claim they restrict.

## Mathematical exposition and appendix alignment

- The economic-geography and urban states are column vectors before they enter
  their Jacobians. Their transport operators are shared; their equilibrium
  residuals and welfare projections remain distinct.
- The route curvature is separated from the primitive policy shock. Traffic
  and realized-cost changes use notation distinct from the transformed spatial
  state.
- The IFT discussion proceeds from the residual system to the state derivative,
  welfare row, adjoint solve, and all-policy welfare projection.
- Aggregate-cost pass-through `zeta`, modal-normalized pass-through `chi`, and
  the welfare-effective output ratio are separate objects.
- Proposition 2 is identified as an economic-geography factorization. The
  urban model uses the same transport differentiation and adjoint method but
  its residence-workplace Jacobian and welfare row.
- Appendix A uses the main text's closure, shock, pass-through, exposure, and
  sign conventions. It records code aliases only in the crosswalk.
- Appendix B follows the computational substitution chain: validate, reconstruct
  routes, build closures, form realized and primitive shock loadings, solve the
  adjoint, aggregate policy units, and verify decomposition identities.
- Appendices C through F state the main-text contract they support instead of
  beginning as detached reference material.

## Adversarial findings

### S1: No finite-size accuracy chart for the economic-geography grid

The assessment requested nonlinear and first-order welfare changes for 0.1,
1, and 5 percent shocks. The package has a nonlinear urban solver, but the
economic-geography grid verification re-solves the nonlinear route-mode-
congestion block around a local spatial representation. Presenting that
exercise as a full nonlinear economic-geography counterfactual would overstate
the available check.

**Disposition:** the diagnostics section distinguishes derivative verification
from finite-policy accuracy and requires a full nonlinear counterfactual for
large projects. Add the requested chart only after a nonlinear
economic-geography equilibrium solver is part of the verified package.

### S2: Model-ready flow construction remains application-specific

The guide now gives a data-availability matrix and a generic balancing recipe,
but it does not convert one public set of raw vehicle counts, tonnage,
ridership, or schedules into welfare-consistent value or commuter flows.
That conversion is usually the most judgment-intensive part of a new
application.

**Recommended next artifact:** a public preprocessing tutorial with synthetic
raw records, geographic matching, unit conversion, balancing, versioned
intermediates, and input hashes.

### S2: The PDF is not semantically tagged

Language metadata, bookmarks, redundant visual cues, and web linearization are
present. `pdfinfo` still reports `Tagged: no`. Full heading, list, table, and
figure tagging requires a tagged-PDF LaTeX toolchain and alternative
descriptions that can be validated for PDF/UA.

**Recommended next step:** migrate the guide build to the LaTeX tagging
toolchain in a separate change and add a PDF accessibility validator to CI.

### S2: The guide summarizes rather than reproduces the full proofs

The guide shows the general IFT chain, states and interprets Proposition 2, and
documents the decomposition algorithm. It does not reproduce the paper
appendix's line-by-line scalar collapse or the complete Woodbury derivation.

**Disposition:** appropriate for the combined guide/reference format. A public
technical derivation note should be linked if full theorem self-containment
becomes a release requirement.

### S3: Not every printed command is an extracted documentation test

The guide build checks generated assets, figures, references, logs, private
paths, and PDF length. The principal quick-start workflow has been smoke-tested,
but the build does not extract and execute every shell and Julia listing.

**Recommended next step:** maintain a small manifest of executable listings and
bind each to an integration test; exclude explanatory pseudocode.

### S3: Current Julia regeneration was unavailable in this sandbox

The current environment prevented Juliaup from creating its lock file, and an
escalated run was not approved. The Julia asset generator and generated memory
macro were updated together; the displayed grid memory value also equals the
package formula directly. The full generated-source drift check and package
suite were not rerun in this final writing pass.

**Required release gate:** run `make practitioner-guide-check` and the full
Julia suite in a normal clone before committing a release artifact. The last
completed package run preceding these writing edits reported 621 passing tests
and three documented expected failures.

## Verification completed in this pass

- `make practitioner-guide`: passed.
- PDF: 58 pages; web-linearized; the main guide ends on page 39 and references
  begin on a separate final page.
- LaTeX log: no errors, undefined citations or references, duplicate
  destinations, or overfull boxes. One harmless underfull line remains in a
  long ArcGIS bibliography URL.
- Figure build/check: passed for the network, welfare map, scatter, and
  decomposition in PDF and transparent PNG formats.
- Strict academic AI-prose gate: passed with zero actionable findings after
  the revision pass.
- Bibliography: 19 entries and no duplicate keys. Metadata for Allen and
  Arkolakis, Fuchs and Wong, Redding and Turner, Donaldson, and Small, Verhoef,
  and Lindsey matches the journal, NBER, Elsevier, and Routledge records.
- Static checks: no typographic quotation marks in code listings, no private
  local paths or credentials in guide source, and `git diff --check` passed.
- Visual inspection: title page, contents, reading guide, quick start,
  mechanism and computation diagrams, worked-example network, welfare map,
  scatter, decomposition, tables, appendix transition, and references render
  legibly without overlap.

## Reasoning-graph and theory-writing pass

A second close review applied the academic-writing reasoning protocol to the
assembled guide. The final structural graph contains 1,672 nodes and 2,812
edges, including 344 paragraphs, 1,143 sentences, 13 displayed equations, one
proposition, six figures, and five tables. The accompanying semantic graph
records section contracts and logical dependencies rather than treating
adjacency as argument.

The main theory repair occurs in the transport elimination. The guide now
substitutes
\[
dh=(I-\Gamma^SC^S)^{-1}
\left(d\theta+\Gamma^SQ_{z_c}^Sdz_c\right)
\]
before setting \(d\theta=0\). This displays both outputs of the same transport
system: the \(dz_c\) term modifies the equilibrium Jacobian, whereas the
\(d\theta\) term forms the primitive policy forcing. Appendix B already
implemented the latter operation; the main text now shows the missing
substitution that connects the two.

The pass also:

- labels the four-factor expression as the economic-geography result rather
  than a formula for both spatial closures;
- motivates Proposition 2 as an explanation for welfare differences among
  links with similar traffic;
- explains why the urban model shares the adjoint method but not the scalar
  trade-market-access factorization;
- removes an invalid inference from modal shares to relative generalized costs
  in the grid example;
- separates plotted elasticities from the welfare gain produced by a
  one-percent shock;
- makes the grid and freight cancellation arguments explicit in signed levels;
- merges repeated Seattle and provenance qualifications;
- replaces formulaic headings and generic handoffs with their actual
  argumentative task.

The reasoning map, semantic node and edge files, mathematical result cards,
paragraph chains, orphan audit, connectivity ledger, and adversarial findings
are stored under
`docs/audits/practitioner-guide-reasoning-2026-07-26/`.

After these edits, the strict academic AI-prose gate passes with zero
actionable findings. The scanner's remaining prompts concern statistical
sentence regularity, repeated technical vocabulary, and passive constructions
in verification statements; close review found these non-substantive. The
guide again compiles with no errors, undefined citations or
references, duplicate labels, or overfull boxes. Figure checks, the static
guide check, bibliography duplicate-key check, and `git diff --check` pass.

## Vocabulary and jargon pass

A final contextual pass removed words that had become substitutes for the
underlying economic statement. Across the guide source, `benchmark` fell from
38 occurrences to zero, `conditional` from nine to zero, and `maintained` from
six to zero. The draft did not use `canonical`. Reader-facing uses of
`closure` were replaced by the economic-geography model, urban model, welfare
formula, or decomposition case. The remaining 35 source occurrences identify
the formally defined closure ladder, code fields, matrix systems, or numerical
checks.

The same pass replaced generic nouns such as `object`, `mechanism`, and
`channel` with the relevant input, variable, economic response, congestion
effect, or decomposition component. It retained `projection`, `mapping`, and
`flexible` where they name a mathematical operation or declared model case.
The strict paragraph and full-file gates both pass with zero actionable
findings. The vocabulary-specific scan and iteration report are stored in the
reasoning audit's `slop-trace` directory.

## Prose presentation pass

The final presentation pass removed all 23 `itemize`, `enumerate`, and
`description` environments from the guide source. Sequential arguments now
state the dependency between steps in prose. Reference material uses short
labeled sentences or tables where readers need to compare fields. The quick
start expresses acceptance in terms of data, policy, model, and result
readiness rather than a numbered checklist.

This change shortens the guide to 58 pages without altering its equations,
tables, figures, numerical claims, or citations. A refreshed structural graph
contains 1,703 nodes and 2,867 edges. The strict paragraph scan initially found
eight overbroad uses of “every”; after narrowing those statements, the
paragraph and full-file gates passed with no actionable findings. The final
build has no overfull boxes. Its only layout warning remains the long ArcGIS
URL in the bibliography.
