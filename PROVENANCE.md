# Provenance

`TransportNetworkWelfare.jl` was initialized from the frozen July 12, 2026
audit package:

```text
IFT_Complete_Decomposition_2026-07-12.zip
SHA-256: 0ba8a28c75987529ab77c882d55da3559c494bbbfa6adc2908feef7defed2a0d
```

The kernels began from the frozen package and are tracked in `provenance.toml`.
That manifest records the frozen and current package hashes together with their
relationship. `scripts/verify_provenance.py` checks the recorded current hashes
in CI.

| Package file | Relationship to frozen source |
| --- | --- |
| `src/kernels/AdjointRSUE.jl` | Extended with explicit finite-input errors, reduced endogenous-location states for fixed external markets, and legacy-only labels for positive-power helpers. |
| `src/kernels/IFTDecomposition.jl` | Extended with analytic closure factors, distinct-margin route reconstruction, reduced endogenous-location states, and explicit route-curvature entry points. |
| `src/kernels/UrbanCommutingIFT.jl` | Frozen one-mode Allen--Arkolakis regression oracle. |
| `src/UrbanEngine.jl` | Shared multimodal closure engine; replaces the one-mode builder. |
| `src/SharedTransport.jl` | New spatial-model-neutral transport basis. |
| `src/UrbanNonlinear.jl` | Independent nonlinear multimodal urban verification oracle with a direct-margin baseline Jacobian and damped congestion solve. |
| `src/kernels/IFTCompleteDecomposition.jl` | Byte-for-byte frozen. |
| `src/kernels/RSUEParameterSensitivity.jl` | Byte-for-byte frozen. |
| `src/kernels/RSUETerminalCongestion.jl` | Byte-for-byte frozen. |

Earlier internal research repositories record the historical lineage. They are
provenance only and are not runtime dependencies.

The RSUE manuscript remains in Overleaf. Restricted data remain outside Git and are located through `RSUE_DATA_ROOT`. No manuscript source or restricted input is vendored here.

The practitioner guide and theory--code audit use the active manuscript at
Overleaf commit `96283f92b4cd8fbcc68ed98b9aac32d7f5ba9343` as the authority for
the paper-facing model statement. The curated derivations use Mathdown commit
`23f350a4de16eb842803f53267278deccb724f5d` as their theory baseline. The
software repository remains authoritative for executable behavior. The audit
records differences among these sources rather than silently reconciling them.

## Seattle multimodal candidate

The published Allen-Arkolakis Seattle inputs are retained outside Git. The
candidate multimodal adapter relies on the 2017 LODES OD matrix and grid
crosswalk in that archive, 2017 ACS five-year table B08301, and King County
Metro GTFS feed version
`ad172e653aa881557a5f3cb84f2ace6819308600`. Relied-on file hashes, dates,
URLs, and the King County attribution are recorded in
`examples/seattle_multimodal/sources.toml`.

The default historical-feed source is Mobility Database dataset
`mdb-267-20170614`, migrated from TransitFeeds. Its public archive has SHA-256
`469d072cb091bb70240f9e71bfa49f74ac1b0fafadc1fa7f669e933f513da334`
and the same SHA-1 as the independently catalogued Transitland feed version.
The downloader retains a verified local-archive override and a Transitland
archive fallback. Current-feed substitution is rejected.

The official 2017 King County Metro System Evaluation is pinned as a
route-level validation source. A deterministic `pdftotext -layout` parser
extracts its Fall 2016 weekday route-ridership table and records the Poppler
version and output hash. The table is not used to infer OD-to-route ridership.
The Seattle map background uses hash-pinned 2017 Census TIGER place, King
County area-water, and county files. The acquisition command verifies the full
GTFS archive and the listed tables. The model builder records only hashes and
generated diagnostics. Raw GTFS, ACS responses, geographic files, and the
Allen-Arkolakis archive remain outside Git.

Named route results are sparse bundles of edge-mode derivatives. Their
incidence comes from the pinned GTFS trip and stop sequences. They represent a
uniform improvement to the aggregate mode cost along a named route's mapped
corridor, not route-exclusive passenger assignment on segments shared by
multiple services.

The Allen--Arkolakis-style observed-road panel is extracted directly from the
hash-pinned replication archive's `obs_seattle` FileGDB layer with GDAL. The
artifact manifest binds the resulting GeoJSON, full GTFS route-shape render,
model outputs, and figures to their output hashes. The derived geometry and
figures remain outside Git.

## Census port-trade adapter

The paper's port-trade adapter uses public monthly Census International Trade
API aggregates. Its downloader and crosswalk design were adapted from an
audited internal research pipeline. That pipeline is provenance only and is
not a runtime dependency.

The relied-on source files were not copied into this repository. Their frozen hashes are:

| Source role | Source file | SHA-256 |
| --- | --- | --- |
| Census API downloader pattern | `census_port_origin_panel.py` | `ffd781ef7902fc8399cb3b53dbb370634deb50673a38f1e6e7c4365ba799aae4` |
| Schedule D port-to-node crosswalk | `ift_port_extension/config/port_node_crosswalk.csv` | `a3ca4d084cf3839bdde88593d5196bcdf8a046b3a9099ad7dc7bff91e990cd09` |
| Schedule C region-to-node crosswalk | `ift_port_extension/config/foreign_region_crosswalk.csv` | `269f332a890f2ba9b7be40971936237349bd653fa391d3680386d221478ffdce` |

The package implementation adds stricter cache checks, sanitized metadata, deterministic gzip output, an explicit port/region crosswalk, and a reproducible aggregation-and-balancing stage. The derived 2017 overlay is tracked because it contains only aggregated public Census values. Its SHA-256 is:

```text
49bd1c9dc1aa1531933a4171cd884fa6e76cc1044b0301027307b2c562918520
```

The raw monthly API cache is not tracked. `CENSUS_API_KEY` supplies the key at
runtime; download URLs, metadata, and logs omit its value. The derived
diagnostics record the API endpoints, query fields, monthly source hashes,
coverage, balancing method, and output hashes.

The Census adapter is intentionally separate from the legacy audited RSUE configuration. The legacy matrix appears to contain 2017 containerized import values and is symmetrized. The paper adapter preserves observed import and export direction before projecting both matrices onto common normalized port and region margins required by the balanced-flow model. This projection is a model adapter, not a claim that raw port-level imports equal exports.

## Canonical benchmark examples

The Braess-style and cow networks are original synthetic inputs created for
this package. The Sioux Falls builder retrieves four files from
`bstabler/TransportationNetworks` at commit
`977ee75c6906337c0c7d229a1336107c7cdb533e`. Their URLs and SHA-256 hashes are
recorded in `examples/sioux_falls/sources.toml` and verified before parsing.
Neither the source files nor generated derivatives are tracked because the
upstream terms call for academic research use and citation.

Seattle, Westeros, and the practitioner guide's externally derived assets are
covered in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Public visibility
requires completing the redistribution review listed there and in
[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
