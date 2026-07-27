# Practitioner Guide Organization Review

Date: 2026-07-26

## Diagnosis

The earlier contents page showed only sections. It concealed the guide's real
structure, even though most of the argument was organized at subsection level.
The single detailed-guide part also combined theory, implementation, examples,
and external-data applications. Section 2 repeated the two-model overview that
Section 3 developed in full. Several section titles described topics rather
than the work performed by the section.

## Revised hierarchy

The guide now has four parts:

1. **Quick start.** A stand-alone path from an admissible policy question to
   validated results.
2. **Detailed guide: theory and welfare.** The policy experiment, the two
   spatial models and common transport equations, and the welfare calculation.
3. **Detailed guide: implementation and applications.** Data, software,
   numerical checks, the public grid, and external-data modules.
4. **Reference appendices.** Notation, algorithms, schemas, verification,
   additional examples, and provenance.

The contents page displays subsections for Parts II and III, where the reader
needs a map of the argument. It omits the eight procedural subsections of the
quick start and the lower-level appendix headings, which keeps the contents on
one page.

## Section contracts

| Section | Incoming question | Job | Output and handoff |
| --- | --- | --- | --- |
| 1. Start a new application | Can the package answer this policy question with the available data? | Screen the policy, prepare inputs, run the code, and inspect the output. | A validated first run and pointers to the relevant detailed sections. |
| 2. Policy experiment and scope | What derivative is being reported? | Define directed and physical-link policies, the three welfare measures, and the appraisal boundary. | A common policy and welfare vocabulary for both spatial models. |
| 3. Spatial models and shared transport technology | Which equilibrium responds to the transport change? | Define economic geography, urban commuting, and their common route-mode-congestion equations. | Model-specific Jacobian and welfare inputs plus the shared transport response. |
| 4. From traffic to spatial-equilibrium welfare | When is traffic sufficient, and what replaces it when wedges matter? | Derive the Traditional approach, the IFT and adjoint calculation, and the exact decomposition. | Welfare elasticities and decomposition identities ready for empirical implementation. |
| 5. Implementation and verification | What data and computations are required? | State the data contract, follow the software workflow, and specify numerical and reporting checks. | A reproducible calculation with explicit acceptance conditions. |
| 6. Worked example | How do the inputs, formulas, and diagnostics operate together? | Apply the complete workflow to the public multimodal grid. | Generated rankings, maps, and decomposition results that can be rebuilt in a clean clone. |
| 7. Applications and extensions | What changes in the freight and urban modules? | Separate the verified freight application from the urban method and Seattle data candidate. | Application-specific results and clearly stated empirical limits. |
| 8. Interpretation, scope, and reporting | What may an analyst claim from the output? | Combine accounting, derivative, validation, and appraisal limits. | A reporting standard and a handoff to the technical appendices. |

## Structural edits

- Removed the duplicate two-model subsection from Section 2.
- Moved the full model comparison to Section 3, where the equations are
  introduced.
- Split the former detailed-guide part into theory/welfare and
  implementation/applications.
- Renamed sections and subsections by their argumentative task.
- Rewrote the reading guide around dependencies and reader tasks.
- Added explicit handoffs from the Seattle discussion to the reporting section
  and from the conclusion to the reference appendices.
- Renamed appendix headings to match their reference function.
- Replaced all list environments with connected prose. Sequential material now
  states why one operation follows another, while field definitions remain
  available in compact tables or labeled sentences.

## Verification

- PDF build: 58 pages.
- Contents: one page with main-text subsection navigation.
- Reading guide: one page.
- No undefined citations, references, or duplicate labels.
- No overfull boxes; one accepted underfull bibliography line remains for a
  long ArcGIS URL.
- Strict academic prose gate: zero actionable findings.
- Figure check, guide shell check, bibliography duplicate-key check, and
  `git diff --check`: passed.
- List-environment scan: zero `itemize`, `enumerate`, or `description`
  environments in the guide source.
