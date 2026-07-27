# Adversarial Writing and Theory Review

Date: 2026-07-26

## Verdict

The guide now has a coherent central argument and is suitable for circulation
as a practitioner guide with a technical reference layer. The revision did
not change the maintained model or reported results. It repaired one omitted
substitution in the exposition, narrowed two claims whose scope was broader
than the available theory, and corrected the worked example's interpretation
of baseline modal shares.

## Remaining high-priority limitations

### S1: The urban closure is executable but not proof-self-contained here

The guide defines the urban state, commuting exposure, welfare row, and shared
transport derivative. It does not reproduce the full residence-workplace
residual system and derive each block of \(J_U^0\) line by line. The package's
independent one-mode oracle and nonlinear multimodal tests support the
implementation claim, but they do not make this PDF a standalone proof of the
urban model.

**Disposition:** retain the current explicit boundary. Add a public derivation
note before describing the guide itself as proof-self-contained for the urban
extension.

### S1: Finite project accuracy is not verified for the economic-geography grid

The guide verifies the local derivative and the nonlinear
route-mode-congestion response. It does not solve a global nonlinear
economic-geography equilibrium for the one- and five-percent projects.

**Disposition:** do not add a finite-size chart for that closure until an
independent nonlinear solver exists. The current diagnostics section states
this limitation correctly.

### S1: Seattle remains a candidate application

The shared urban derivative, network accounting, GTFS geometry, and policy
bundles are implemented. Route-level ridership, Seattle generalized costs,
local modal substitution, congestion parameters, and untargeted validation
remain incomplete.

**Disposition:** the candidate label is necessary. Maps from the module should
be described as model illustrations until those inputs are established.

## Moderate limitations

### S2: The guide summarizes the finest analytical decomposition

The main text derives the closure ladder and Hulten-gap accounting. Appendix B
states the structured parallel-sum and analytical rank-two updates but omits
the full allocation-scarcity-equilibrium proof.

**Disposition:** appropriate for a practitioner guide. Link a separate
technical derivation note if public proof-level self-containment becomes a
release requirement.

### S2: Preparing model-ready flows remains the main empirical judgment

The guide states the required margins, units, balancing diagnostics, and
provenance. It cannot supply a universal conversion from vehicles, passengers,
tonnage, or schedules to model-consistent value or commuter flows.

**Disposition:** a future public preprocessing tutorial should begin with raw
synthetic records and preserve each geographic, unit, and balancing step as a
versioned artifact.

## Minor limitations

- The PDF has language metadata, bookmarks, redundant visual encodings, and
  web linearization, but it is not semantically tagged.
- The build does not extract and execute every printed code listing.
- The strict prose scanner continues to flag low lexical diversity in theory
  sections and passive voice in verification statements as nonblocking
  statistical prompts. Close reading found no actorless causal claim that
  required a rewrite.

## Checks

An incremental code-to-theory reconciliation corrected the decomposition
discussion. The general mixed update remains part of the implementation, but
the current common-baseline specification keeps the sparse spatial allocation
and aggregate-feedback blocks fixed across closures. The guide now reports the
resulting allocation and equilibrium contributions as structural zeros and
assigns each closure difference to the congestion-scarcity term, matching
\code{mixed\_channels} and the manuscript's computational appendix. The same
pass made explicit the substitution of the reduced transport-case Jacobian and
primitive forcing into the adjoint welfare formula.

- Expanded-source structural skeleton rebuilt after revision: 2,042 nodes and
  3,432 containment and sequence edges.
- Semantic nodes, dependencies, equation cards, connectivity ledger, and
  orphan audit recorded in this directory.
- Strict academic AI-prose gate: zero actionable findings.
- LaTeX and BibTeX build: 80 pages, no errors, undefined citations or
  references, duplicate labels, or overfull boxes.
- Bibliography: 19 entries and no duplicate keys.
- Figure and guide shell checks: passed.
- `git diff --check`: passed.

The Julia-generated asset and package test suite were not rerun in this prose
pass because the sandbox cannot acquire the Juliaup lock. The committed
generated assets were not changed, and the TeX build used the existing
hash-bound result macros.

## Final vocabulary review

The review found no use of `canonical`. The pass removed all uses of
`benchmark`, `conditional`, and `maintained` from the guide, because the
surrounding sentences could state the exact model, assumption, or comparison
instead. It also sharply reduced reader-facing uses of `closure`, `object`,
`mechanism`, and `channel`. Technical uses remain where the text refers to the
defined closure ladder, a Jacobian case, the adjoint projection, or an actual
code field. Replacing those terms further would make the mathematical
crosswalk less precise.

The vocabulary-specific strict scan failed initially on two formulaic
subsection headings, then passed after revision. The final paragraph scan and
full-file scan contain zero actionable P0, P1, or P2 findings.
