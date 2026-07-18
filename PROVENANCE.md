# Provenance

`TransportNetworkWelfare.jl` was initialized from the isolated audit package:

```text
working/IFT_Complete_Decomposition_2026-07-12/
deliverables/IFT_Complete_Decomposition_2026-07-12.zip
SHA-256: 0ba8a28c75987529ab77c882d55da3559c494bbbfa6adc2908feef7defed2a0d
```

The following kernels were copied byte-for-byte before being wrapped in the package API:

| Package file | Frozen SHA-256 |
| --- | --- |
| `src/kernels/AdjointRSUE.jl` | `d843f3ed260f2af56aa5e163d0d3b144498507a48c0edf90313b6d5c9603fd7d` |
| `src/kernels/IFTDecomposition.jl` | `99d87f8cad942c5c744138a5446df540a6e14b9ee57ecbd484ad96c7855625c7` |
| `src/kernels/IFTCompleteDecomposition.jl` | `a1d6e3d7dc08f66ddcabbcad1060abccaf3954e34ef961bb578815706cf84341` |
| `src/kernels/RSUEParameterSensitivity.jl` | `9d5392b5ecec331615ce5e47c5d09e7a66954cad9a2ab7ca7c693d37b1e7ddbc` |
| `src/kernels/RSUETerminalCongestion.jl` | `4cc3c2eb97f18d1df440d8b441d6193f5806c8a158027a40fb6673c2d5013e55` |

Historical lineage is available in the private repositories `sfuchs-de/RSUE_AFW_2025_v2` and `sfuchs-de/Multimodal_FW_2023`. Those repositories are provenance only; neither is a runtime dependency.

The RSUE manuscript remains in Overleaf. Restricted data remain outside Git and are located through `RSUE_DATA_ROOT`. No manuscript source or restricted input is vendored here.
