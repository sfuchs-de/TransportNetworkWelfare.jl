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

Each closure Jacobian is constructed as

```math
J_S=D_S+u_Sv_S^\top+\Delta_{edge,S}+\Delta_{terminal,S}.
```

Road and terminal gaps use the exact structured parallel-sum identity. Mode and route gaps use the mixed update

```math
\widetilde K_{A:F}=J_F+S_{A:F}+C_{A:F},\qquad
J_A=\widetilde K_{A:F}+R_{A:F}Q_{A:F}^\top,
```

and report allocation, scarcity, and Woodbury equilibrium-correction channels separately. In the current common-baseline model, ``D_S``, ``u_S``, and ``v_S`` do not vary across the transport closures. The allocation and equilibrium-correction channels are therefore exact structural zeros, while the mode and route gaps enter through the analytically constructed congestion blocks. The code evaluates the general formulas and tests the Jacobian and channel reconstructions; it does not assign the zeros by convention.

Directed-arc shocks are separate policies. A physical-link result sums the two opposite directed elasticities and every additive component before calculating normalized link multipliers. Normalized channel contributions are aggregated using the two directions' traffic weights.

The urban model uses the same `H`, `NC`, `NT`, `F`, `FM`, and `FR` transport
closures and reports their exact road, terminal, mode, and route gaps. Its
normalization is commuter traffic rather than $\rho$ times trade traffic. The
allocation/scarcity/equilibrium subchannel split is currently reported only
for the economic-geography closure.
