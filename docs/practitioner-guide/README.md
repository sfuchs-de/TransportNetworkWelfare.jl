# Practitioner guide

This directory contains the complete LaTeX source for the
`TransportNetworkWelfare.jl` practitioner guide. The guide is built from
tracked source, generated TeX fragments, and checked figure and table assets.
It does not require the paper's Overleaf project or restricted RSUE inputs.

From the repository root:

```bash
make practitioner-guide
make practitioner-guide-check
```

The first command writes
`docs/practitioner-guide/build/TransportNetworkWelfare-Practitioner-Guide.pdf`.
The second command rebuilds the PDF, regenerates public synthetic results in
temporary directories, verifies checked external-example assets against their
manifest, and checks citations, references, layout, and prohibited local
paths.

Use `make practitioner-guide-assets` after changing the worked grid example or
its numerical results. Use `make practitioner-guide-example-assets` after
changing the common example plotting code. External-example assets require the
source-specific environment variables listed by
`make practitioner-guide-external-assets`; their raw inputs remain outside
Git.

The source is organized into a quick-start section, a detailed guide,
application summaries, and technical appendices. `main.tex` is the build root,
`preamble.tex` owns formatting and release metadata, and the checked builders
own files under `generated/`, `figures/`, and `tables/`.
