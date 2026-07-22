# Urban Commuting IFT Verification

## Decision

The Allen-Arkolakis urban model requires a new equilibrium and welfare block. It
is not a relabeling of the economic-geography IFT. The package shares file I/O,
policy aggregation, traffic orientation, and output code, while keeping the
urban Jacobian and welfare row in `src/kernels/UrbanCommutingIFT.jl`.

## Source ledger

| Source | Role | SHA-256 |
|---|---|---|
| `RESTUD26454_Replication.zip` | Published replication archive | `87c43d59be197c38c657625aca53cd3b5cfba19ec7177b8bcd3813e10b3429e1` |
| `node_lr_lf_seattle.csv` | Residence, workplace, coordinates | `be2e30db8e32890e939a7f1e6fe5f6f893e7140ecac74fd2ddec41d83684796f` |
| `sparse_adjmat_seattle.csv` | Directed Seattle traffic | `c8264f6e94c9a87084313cca19f297ebafc7253bb1b3ed054c7f6c079ffc47d7` |

The equations were mapped from
`fn_AA_calc_eqm_commuting_counterfactual.m` and
`fn_AA_eqm_lr_lf_counterfactual.m`. No MATLAB source or data are committed.

## Equation-to-code map

| Object | Julia implementation |
|---|---|
| Residence-workplace transformation | `UrbanCommutingIFT.coefficients` |
| Baseline residual Jacobian | `UrbanCommutingIFT.jacobian` |
| Primitive edge-cost loading | `UrbanCommutingIFT.cost_loading` |
| Welfare row, (d\log W=-d\log\chi/\theta) | `UrbanCommutingIFT.welfare_gradient` |
| Nonlinear exact-hat equations | `UrbanCommutingIFT.exact_hat_residual` |
| Analytic nonlinear Jacobian | `UrbanCommutingIFT.exact_hat_jacobian` |
| Independent central difference | `urban_finite_difference` |

## Checks

- Synthetic analytic Jacobian versus central numerical Jacobian: below `2e-9`.
- Synthetic analytic shock loading versus central numerical loading: below `2e-9`.
- All six synthetic edge elasticities versus nonlinear central differences:
  below `2e-7`.
- Efficient synthetic benchmark: Hulten collapse below `1e-10`.
- Seattle counts: 217 nodes, 1,384 directed arcs, 692 physical links.
- Seattle equilibrium Jacobian condition number: approximately `3741.02`.
- Seattle central differences at a low-effect arc, the maximum-effect arc, and
  an arc whose destination is the normalization node: maximum error
  `3.4e-10`; nonlinear residual below `1.5e-13`.
- Published one-percent Seattle counterfactuals matched by edge ID: 1,384 of
  1,384; correlation with the local IFT is approximately `0.99955`.
- Full package suite: 382 passed, 2 expected restricted-data skips.

## Boundary

The urban implementation is accepted for single-mode local welfare derivatives.
The multimodal transport block and exact `NC`/`NT`/`F`/`FM`/`FR` decomposition
have not been rederived for the urban residence-workplace closure. The package
fails closed for `decompose` and `analyze-edge-local` under `urban_commuting`.
