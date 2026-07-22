# Outputs

`analyze` writes welfare results. `analyze-edge-local` writes the same compact
welfare-result schema using the scalable edge-local Jacobian. `decompose` writes
the full closure decomposition. All three commands also write
`run_manifest.json`.

## Files

- `welfare_directed.csv` and `welfare_physical.csv` are written by `analyze`.
- `decomposition_directed.csv` and `decomposition_physical.csv` are written by `decompose`.
- `run_manifest.json` records the code, configuration, inputs, parameters, diagnostics, transformations, and output hashes.

The edge-local command reports `closure_level="edge_local_sparse"` and
`decomposition_available=false`. It solves the spatial-equilibrium adjoint and
reports the primitive-cost welfare derivative. Because it does not construct
the route-consistent transport operators, `realized_F`, `chi_effective`, and
`primitive_pass_through` are `missing`; it also omits the fixed-mode and
fixed-route decomposition closures.

Directed rows are indexed by `edge_id`. Physical rows are indexed by `physical_link_id`. Under a bidirectional policy, physical elasticities and additive components are sums across the two directions; normalized multipliers are calculated after aggregation.

## Sign and policy scale

The reported welfare elasticity uses

```math
-\frac{d\ln W}{d\ln\bar\kappa}.
```

A positive value is therefore a welfare gain from a primitive-cost reduction. For a small reduction of size $s$, the approximate percentage welfare gain is `100 * s * elasticity`. With a one-percent reduction, the elasticity's numeric value is also the approximate percentage gain.

## Welfare and closure columns

- `hulten` is the traffic-only benchmark.
- `realized_NC`, `realized_NT`, and `realized_F` use no congestion, road congestion, and the full configured congestion system.
- `realized_FM` freezes baseline modal shares; `realized_FR` freezes baseline route use.
- `primitive_F` applies the full primitive-cost forcing.
- `chi_effective` is `primitive_F / realized_F` where that ratio is numerically defined; otherwise it is missing. The additive pass-through component remains defined as `realized_F - primitive_F`.
- `m_NC`, `m_NT`, `m_F`, `m_FM`, and `m_FR` are normalized equilibrium multipliers.
- `d_edge`, `d_road`, `d_terminal`, `d_mode`, and `d_route` are closure differences under the common-baseline ladder.

The allocation, scarcity, and equilibrium subcolumns implement the analytical Jacobian decomposition. Exact structural zeros are reported as zero. The `channel_residual_*`, inverse-gap, and Jacobian-block diagnostics must remain below the configured tolerance; the run fails otherwise.

## Reproducibility manifest

The manifest records the package version and Git state, Julia version, command, hashes of the configuration and inputs, declared transformations, model variant, parameter values, condition diagnostics, verification status, and hashes of all generated outputs. Machine-specific absolute configuration paths are excluded so identical projects can produce deterministic artifacts on different systems.
