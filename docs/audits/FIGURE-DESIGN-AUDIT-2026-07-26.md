# Figure design audit

## Scope and verdict

This review covers the current practitioner-guide figures, the RSUE paper
artifacts, the generic example renderers, and the Seattle and Westeros plotting
code. The guide examples and RSUE assets were inspected as full-resolution
PNGs and in the compiled 60-page guide. Generic scatter, decomposition,
two-dimensional network, and three-dimensional network outputs were rendered
from committed example results and inspected separately.

The current rendering paths now share one visual contract. The figures use
consistent typography, semantic colors, axis treatment, welfare scales, and
deterministic transparent output. The numerical estimator was not changed.

| Asset family | Evidence reviewed | Status |
|---|---|---|
| Practitioner guide | Grid map, scatter, table, and decomposition; three appendix map/scatter/table sets; compiled PDF pages 30--33 and 52--54 | Accepted |
| RSUE paper artifacts | Two maps, scatter, decomposition, and sensitivity PDF/PNG pairs | Accepted |
| Generic examples | Toy scatter and decomposition; Braess, grid, and cow networks | Accepted |
| Seattle extension | Plotting source and deterministic fixture test | Accepted for code; empirical assets require external data |
| Westeros extension | Plotting source and CLI smoke test | Accepted for code; rendering requires external geography |

## Design contract

[`plots/figure_style.py`](../../plots/figure_style.py) is the shared rendering
layer. It defines the portable serif typeface, restrained palette, axis
formatting, ordered and signed welfare scales, identity-plot limits,
correlations, economics-facing metric labels, and deterministic file writer.
The guide's TikZ generator uses the same blue, teal, orange, gold, and muted-gray
values.

Ordered welfare magnitudes use `viridis`. Signed effects use a zero-centered
blue-orange scale. Comparison maps share a normalization. Scatterplots use
equal axes, a 45-degree line, and the labels “Traditional approach” and
“Extended approach.” Internal names such as `primitive_F` do not appear in
public figures.

## Corrections made

The former RSUE maps used separate rainbow scales, which prevented direct
comparison. They now share one ordered welfare scale, and both colorbars
identify welfare elasticities. The RSUE scatter now reports Pearson and rank
correlations and labels three large effects while preserving complete CBSA
names. The decomposition now moves in economic order from the traditional
measure through the no-congestion, road-congestion, and realized-cost cases to
the extended measure. Fixed-mode and fixed-route comparisons appear separately.

The former sensitivity layout placed two series on different y-axes in seven
small panels. The revised figure uses one column for mean welfare gains and one
for rank stability, with a visible parameter scale in every row. This removes
the dual-axis ambiguity and makes flat rank responses distinguishable from
missing responses.

The generic plotting scripts now use the same color and file-writing
infrastructure. Their decomposition output uses direct dot-and-line encoding
rather than bars, and their colorbars translate result fields into economic
language. The Seattle and Westeros modules now call the same style and output
functions instead of maintaining separate palettes and save routines.

The four self-contained examples used by the guide now pass through one
visualization contract. Julia writes normalized node activity, coordinates,
terminal status, physical-link endpoints, modal availability, and the two
welfare measures. `plots/example_assets.py` produces a welfare map, an
equal-axis Traditional-versus-Extended scatter, a combined comparison panel,
and the same ranked-link table for every example. The grid figures in the main
text use this path rather than a separate TikZ implementation.

## Computational path

The Julia CLI remains responsible for validated result generation.
`analyze` builds only the full welfare closure, whereas `decompose` constructs
the additional closures needed for the exact decomposition. Plotting consumes
validated CSV outputs and does not recompute welfare effects. The RSUE artifact
builder generates figures before writing the run manifest, so the figure hashes
are recorded with the configuration, numerical outputs, and verification
status.

## Verification

The plotting suite passes 23 tests, including deterministic PDF/PNG output,
transparent and dimensionally consistent raster output, shared scale behavior,
common table semantics, clean handling of constant series, and source checks
against rainbow colormaps. The practitioner-guide figure check and the 60-page
PDF check pass. The RSUE artifact tests,
provenance validation, secret scan, Python compilation, CLI smoke tests, and
`git diff --check` also pass.

The sandbox did not permit Julia to acquire its user-level launcher lock, so
the full Julia asset-regeneration target could not be rerun in this session.
The numerical Julia source was not modified. The new visualization contracts
were created from the previously verified example outputs, and the plotting,
byte-drift, TeX figure, PDF, provenance, and secret checks passed. A full Julia
asset rebuild remains part of the clean-clone CI gate.
