# Provenance

`TransportNetworkWelfare.jl` was initialized from the isolated audit package:

```text
working/IFT_Complete_Decomposition_2026-07-12/
deliverables/IFT_Complete_Decomposition_2026-07-12.zip
SHA-256: 0ba8a28c75987529ab77c882d55da3559c494bbbfa6adc2908feef7defed2a0d
```

The kernels began from the frozen package and are tracked in `provenance.toml`. That manifest records both the frozen source hash and the current package hash, together with the relationship between them. `scripts/verify_provenance.py` checks every current hash in CI.

| Package file | Relationship to frozen source |
| --- | --- |
| `src/kernels/AdjointRSUE.jl` | Validation-only divergence: finite-input assertions became explicit errors. |
| `src/kernels/IFTDecomposition.jl` | Extended with the package's analytic closure-factor implementation. |
| `src/kernels/IFTCompleteDecomposition.jl` | Byte-for-byte frozen. |
| `src/kernels/RSUEParameterSensitivity.jl` | Byte-for-byte frozen. |
| `src/kernels/RSUETerminalCongestion.jl` | Byte-for-byte frozen. |

Historical lineage is available in the private repositories `sfuchs-de/RSUE_AFW_2025_v2` and `sfuchs-de/Multimodal_FW_2023`. Those repositories are provenance only; neither is a runtime dependency.

The RSUE manuscript remains in Overleaf. Restricted data remain outside Git and are located through `RSUE_DATA_ROOT`. No manuscript source or restricted input is vendored here.

## Census port-trade extension

The candidate port-trade adapter uses public monthly Census International Trade API aggregates. Its downloader and crosswalk design were adapted from an audited private discussion-simulation pipeline. The source is provenance only and is not a runtime dependency.

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

The raw monthly API cache is not tracked. It can be reconstructed with `CENSUS_API_KEY`; the key is read only from the environment and is never written to URLs, metadata, or logs. The derived diagnostics record the API endpoints, query fields, monthly source hashes, coverage, balancing method, and output hashes.

The Census candidate is intentionally separate from the legacy audited RSUE configuration. The legacy matrix appears to contain 2017 containerized import values and is symmetrized. The candidate preserves observed import and export direction before projecting both matrices onto common normalized port and region margins required by the balanced-flow model. This projection is a model adapter, not a claim that raw port-level imports equal exports.

## Canonical benchmark examples

The Braess-style and cow networks are original synthetic inputs created for
this package. The Sioux Falls builder retrieves four files from
`bstabler/TransportationNetworks` at commit
`977ee75c6906337c0c7d229a1336107c7cdb533e`. Their URLs and SHA-256 hashes are
recorded in `examples/sioux_falls/sources.toml` and verified before parsing.
Neither the source files nor generated derivatives are tracked because the
upstream terms call for academic research use and citation.
