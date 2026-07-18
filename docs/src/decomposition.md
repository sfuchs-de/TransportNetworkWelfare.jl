# Welfare and analytical decomposition

The full model uses a common route-modal-terminal residual system. Its closures are:

| Closure | Routing | Modal allocation | Congestion |
| --- | --- | --- | --- |
| `H` | Not used | Not used | Traffic-only Hulten benchmark |
| `NC` | Flexible | Flexible | None |
| `NT` | Flexible | Flexible | Edge only |
| `F` | Flexible | Flexible | Edge and terminal |
| `FM` | Flexible | Fixed at observed shares | Full |
| `FR` | Fixed OD-edge incidence | Flexible | Full |

For each policy arc, the realized-friction multiplier satisfies

```math
m_F=m_{NC}-d_{edge}-d_{terminal}
   =m_{FM}+d_{mode}
   =m_{FR}+d_{route}.
```

Primitive-cost pass-through is computed through the full transport operator. The output reports ``\chi_e=E^\theta_{e,F}/E^r_{e,F}``, so nonlocal terminal feedback is part of pass-through.

The realized Hulten gap is

```math
\Xi_e-E^r_{e,F}=\Xi_e(1-\rho)+\rho\Xi_e(1-m_F),
```

where ``\rho=(1+\alpha+\beta)/e``. The primitive gap adds propagation, edge congestion, terminal congestion, and pass-through. Modal and route wedges are alternative closure comparisons; they are not added again to the Hulten accounting identity.

The current reduced model implies zero allocation and equilibrium-correction subchannels for the edge, terminal, modal, and route comparisons; their signed wedge is reported as the scarcity component. These zeros are explicit fields and are tested, not fitted residuals.

Directed-arc shocks are separate policies. A physical-link result sums the two opposite directed elasticities and every additive component before calculating normalized link multipliers.
