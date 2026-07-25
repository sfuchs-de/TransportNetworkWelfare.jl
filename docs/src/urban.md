# Urban commuting model

## Scope

The urban specification follows the residence-workplace model in Allen and
Arkolakis, *The Welfare Effects of Transportation Infrastructure
Improvements*. It combines their urban equilibrium closure with the package's
recursive multimodal transport block.

The transport equations are shared with the economic-geography model:

```math
\kappa_e=\left(\sum_m\kappa_{e,m}^{-\eta}\right)^{-1/\eta},
\qquad
s_{e,m}=\frac{\kappa_{e,m}^{-\eta}}
{\sum_n\kappa_{e,n}^{-\eta}},
```

```math
\tau_{ij}^{-\theta}
=\mathbf 1\{i=j\}+\sum_k\kappa_{ik}^{-\theta}\tau_{kj}^{-\theta}.
```

Here the urban commuting elasticity $\theta$ is the route curvature; the
economic-geography model supplies $\sigma-1$. Flexible and fixed routes,
flexible and fixed modes, edge congestion, terminal congestion, and
primitive-cost pass-through use the same code in both spatial closures.

The spatial equilibrium remains distinct. Its state is

```math
z_U=(d\log l^R,d\log l^F,d\log\chi),
\qquad
d\log W=-d\log\chi/\theta.
```

Residence and workplace choices therefore use an urban Jacobian and welfare
row. They are not relabeled trade-model variables.

## Data contract

Urban `nodes.csv` uses:

```text
node_id,residents,employment,longitude,latitude
```

`edge_modes.csv` uses the generic edge-mode schema. Multiple rows may share an
edge when they represent different modes. Terminal identifiers are required
for every mode with positive endpoint-terminal congestion.

Let $l_i^R$ and $l_i^F$ denote normalized residence and workplace masses, and
let $\Xi_{ij}$ be total directed edge traffic. The recursive stock must satisfy

```math
\mathcal T_i
=l_i^F+\sum_j\Xi_{ij}
=l_i^R+\sum_j\Xi_{ji}.
```

The loader then constructs

```math
s_i^x=\frac{l_i^F}{\mathcal T_i},\quad
s_i^y=\frac{l_i^R}{\mathcal T_i},\quad
\mu_{ij}=\frac{\Xi_{ij}}{\mathcal T_i},\quad
\lambda_{ij}=\frac{\Xi_{ij}}{\mathcal T_j}.
```

The package does not balance inconsistent empirical margins. A preprocessing
pipeline may apply a documented balancing transformation, but its transformed
CSV files and hashes must be the inputs supplied to the package.

## Urban IFT

At zero congestion, the first $N$ residuals are the workplace-side recursive
equations, the next $N-1$ are their residence-side counterparts, and the final
two hold aggregate residence and workplace masses fixed. This defines
$G_U^0(z_U,\kappa)=0$, with Jacobian $J_U^0$, aggregate-edge-cost loading $B_U$,
and welfare row

```math
q_U^\top=(0,\ldots,0,-1/\theta).
```

For each transport closure $S$, the package eliminates route, mode, and
congestion quantities with the same Schur-complement operator used by the
economic-geography model. Realized and primitive edge-mode elasticities are

```math
E_{U,p}^r=q_U^\top J_{U,S}^{-1}b_{U,p}^r,
\qquad
E_{U,p}^{\theta}=q_U^\top J_{U,S}^{-1}b_{U,p}^{\theta}.
```

`decompose` reports the common-baseline closures:

- `NC`: no congestion;
- `NT`: edge congestion;
- `F`: edge and endpoint-terminal congestion;
- `FM`: full congestion with observed modal shares fixed;
- `FR`: full congestion with baseline OD-edge use fixed.

The urban output reports the exact road, terminal, mode, and route closure
gaps. The finer allocation/scarcity/equilibrium split remains limited to the
economic-geography decomposition.

## Configuration

```toml
[model]
spatial_specification = "urban_commuting"
alpha = -0.08
beta = -0.12
theta = 6.0
modal_specification = "choice_logsum"
eta = 1.4
route_curvature = "theorem"

[congestion]
specification = "composite"
endpoint_scale = 1.0

[congestion.edge]
road = 0.06

[congestion.terminal]
transit = 0.04
```

Older one-road-mode projects may continue to specify `model.lambda`. The
loader maps that value to road-edge congestion. It rejects simultaneous use of
`model.lambda` and a modular `[congestion]` specification.

## Verification

The one-mode regression fixture compares the shared system with the independent
Allen-Arkolakis kernel. Their residual Jacobians use different nonsingular row
parameterizations, but their state responses and welfare derivatives agree
below $10^{-10}$.

The multimodal fixture checks primitive and realized shocks against an
independently solved nonlinear equilibrium under `NC`, `NT`, `F`, `FM`, and
`FR`. It also tests the one-mode, unique-route, zero-terminal, and
zero-congestion limits, along with mode permutation and strict accounting
failures.

The synthetic example is in `examples/urban_multimodal`. Seattle GTFS and
ridership integration is a later empirical step. The existing Seattle adapter
remains a one-mode replication interface until a documented modal calibration
and balancing transformation are supplied.

Sources: [Allen and Arkolakis paper](https://par.nsf.gov/servlets/purl/10383104),
[replication archive](https://dl.dropbox.com/s/mmux9ys035xi6iu/RESTUD26454_Replication.zip).
