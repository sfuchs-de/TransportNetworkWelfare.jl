# Paragraph and Sentence Chains

This file records the close sentence-level review of the paragraphs with the
highest mathematical or interpretive load. The exhaustive structural graph in
`structural-final/` contains every paragraph and sentence in the assembled
guide.

## Spatial and transport blocks

Source: `sections/05-ift.tex`, Subsection 4.2.3.

1. The opening sentence inherits the closure-specific Jacobian and identifies
   the common transport block.
2. The next sentence defines the stacked traffic and realized-cost changes.
3. The displayed pair of equations states the two-way traffic-cost system.
4. The following sentence defines \(Q_{z_c}^S\), \(C^S\), and \(\Gamma^S\)
   before any matrix is used again.
5. The substitution solves for \(dh\) with both \(d\theta\) and \(dz_c\)
   present.
6. Two sentences assign separate jobs to the resulting terms: state feedback
   augments the Jacobian; direct policy transmission forms the primitive
   forcing.
7. The realized-cost sentence contrasts the alternative policy experiment.
8. The next paragraph defines \(J_{c,0}\), \(B_{\kappa,c}\), and
   \(S_{\mathrm{agg}}\), sets \(d\theta=0\) for the Jacobian calculation, and
   derives the reduced system.
9. The closing paragraph names the Schur complement, states why its transport
   matrices are shared across closures, and hands the full operation to
   Appendix B and the verification suite.

The pre-edit chain skipped step 5 for \(d\theta\), so the reader saw the state
feedback but not the primitive forcing that later distinguishes the headline
policy measure.

## Economic-geography factorization

Source: `sections/05-ift.tex`, Subsection 4.2.5.

1. The opening contrast inherits the adjoint result and identifies its
   interpretive limitation.
2. The next sentence restricts the factorization to the paper's
   economic-geography assumptions.
3. The definition of \(\rho\) introduces the common scale using the previously
   defined regularity scalar \(e\).
4. The multiplier sentence introduces the only new link-specific objects.
5. The displayed equation combines the four previously named factors.
6. The description list interprets each factor without changing the result.
7. The appendix sentence defers the full scalar proof and code mapping.
8. The limiting substitutions recover Proposition 1 and explain why the
   factorization is an extension of, rather than a replacement for, the
   traffic benchmark.
9. The urban subsection then rejects an invalid relabeling and returns to the
   general adjoint formula with the urban welfare row.

## Worked-example economic setting

Source: `sections/09-worked-example.tex`, Subsection 6.1.

1. The paragraph identifies the economic-geography closure and excludes an
   urban interpretation.
2. It defines the 25-node road grid.
3. It adds transit on the central spine and states the baseline modal-share
   fact.
4. It assigns baseline shares to committed mode shifters and assigns
   \(\eta\) only the local substitution role.
5. It defines terminal identifiers and the optional terminal-congestion
   channel.
6. It hands the geometry to the network figure.

The revision removes an invalid inference from a larger modal share to a lower
relative generalized cost when mode shifters are also present.

## Worked-example decomposition

Source: `sections/09-worked-example.tex`, Subsection 6.6.

1. The first paragraph reads Panel (a) as a sequence of closure changes and
   Panel (b) as an accounting of the traffic-to-primitive gap.
2. It reports each signed component and states that they reconstruct the mean
   gap.
3. The next paragraph first uses the numerical residuals to rule out a failed
   identity.
4. It then distinguishes the common spatial scale from link-specific
   market-access propagation.
5. It interprets road and terminal terms as congestion exposure.
6. It interprets pass-through as attenuation before the primitive improvement
   reaches aggregate edge costs.
7. The final sentence explains why signed levels, rather than shares of a
   small net gap, are the appropriate display.

## Seattle empirical boundary

Source: `sections/12-extensions.tex`, Remaining empirical work.

1. The opening clause inherits the verified multimodal urban derivative.
2. The contrasting clause states that an empirical transit appraisal requires
   additional evidence.
3. The list identifies ridership, generalized costs, substitution,
   congestion, and untargeted validation as distinct missing inputs.
4. The final paragraph classifies these as measurement and calibration
   requirements rather than changes to the IFT.
5. It then states the strongest supported claim: the module demonstrates the
   implemented derivative but does not yet provide an empirical appraisal.

## Conclusion

Source: `sections/13-conclusion.tex`.

1. Paragraph 1 returns to the policy shock and derives the efficient traffic
   benchmark through the envelope theorem.
2. Paragraph 2 reintroduces wedges, Proposition 2, the adjoint, and the
   closure decomposition as successive corrections to that benchmark.
3. Paragraph 3 uses the shared transport block to compare, rather than merge,
   the economic-geography and urban closures.
4. Paragraph 4 maps accounting, mathematical, and empirical checks to the
   claims each can support.
5. Paragraph 5 restricts the output to local modeled benefits, lists omitted
   appraisal channels, and states the reporting information required for the
   spatial-equilibrium correction to be interpretable.

This sequence closes each of the guide's main branches: theory, computation,
verification, applications, and appraisal scope.
