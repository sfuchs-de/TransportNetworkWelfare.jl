# Figure design and generation

The plotting layer uses [`figure_style.py`](figure_style.py) as its single visual
contract. The guide, examples, RSUE replication, Seattle extension, and
Westeros application use the same serif typography, semantic colors, axis
treatment, welfare scales, and deterministic PDF/PNG writer. Blue identifies
the extended measure or a primary series, gray identifies the traditional
measure or network context, teal and orange distinguish mechanisms, and red is
reserved for pass-through or a warning. Ordered welfare magnitudes use
`viridis`; signed effects use a zero-centered blue-orange scale.

Comparison maps must share a scale. Scatterplots use equal axes, an identity
line, the terms “Traditional approach” and “Extended approach,” and correlations
when enough observations are available. Titles belong in document captions.
Panels may carry short direct labels, and important observations may be labeled
selectively. Raw column names such as `primitive_F` must not appear in a
colorbar or axis label.

[`example_assets.py`](example_assets.py) applies this contract to the grid,
Braess-style, cow, multimodal urban, and Sioux Falls calculations.
Julia writes the node-and-link visualization schema for the self-contained
examples. The external-asset builder constructs the same schema in a temporary
directory from validated Sioux Falls outputs. The renderer then
produces a welfare map, comparison scatter, combined map-and-scatter panel,
ranked-link table, and machine-readable ranking file for each example.
[`westeros_example.py`](westeros_example.py) retains the same typography,
welfare scale, scatter, and table rules while tracing model links over the
full source polygon and road network. Seattle likewise retains a specialized
mode-aware map.

Run `make practitioner-guide-example-assets` to rebuild the common
self-contained layer. The full `make practitioner-guide-assets` target first
recomputes the numerical inputs and then renders them. A user with the
hash-pinned external data can run `make practitioner-guide-external-assets`;
clean-clone checks instead verify the committed external asset hashes.

Run `make plot-check` to test the design contract, deterministic rendering, and
all plotting modules. The RSUE artifact builder includes its ten figure files
in the numerical run manifest, so figure hashes remain tied to the accepted
configuration and result tables. Seattle and external-data figures are
generated only after their validated CSV inputs are available.
