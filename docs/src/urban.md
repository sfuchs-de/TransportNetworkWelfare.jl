# Urban commuting model

## Scope

The urban specification follows the commuting model in Allen and Arkolakis,
*The Welfare Effects of Transportation Infrastructure Improvements*. Individuals
choose a residence, workplace, and route. Production externalities depend on
workplace employment, while amenity externalities depend on residents.

The route and traffic logic is shared with the economic-geography model. The
equilibrium closure is not. The urban state contains separate residence and
workplace distributions, and aggregate welfare is recovered from a distinct
scale variable. The package therefore implements a separate analytic IFT rather
than relabeling labor and income.

The current implementation is the paper's single-mode road model. Multimodal
choice and the `NC`/`NT`/`F`/`FM`/`FR` channel decomposition remain available for
`economic_geography` only. `decompose` fails explicitly for `urban_commuting`.

## Data contract

Urban `nodes.csv` uses:

```text
node_id,residents,employment,longitude,latitude
```

Directed traffic remains in `edge_modes.csv`. The maintained orientation is from
residence toward workplace. Let $l_i^R$ and $l_i^F$ denote normalized
residence and workplace masses, and let $\Xi_{ij}$ denote traffic divided by the
total commuter scale. The baseline openness objects are

```math
s_i^x=\frac{l_i^F}{l_i^F+\sum_j\Xi_{ij}},\qquad
\mu_{ij}=\frac{\Xi_{ij}}{l_i^F+\sum_j\Xi_{ij}},
```

```math
s_i^y=\frac{l_i^R}{l_i^R+\sum_j\Xi_{ji}},\qquad
\lambda_{ji}=\frac{\Xi_{ji}}{l_i^R+\sum_j\Xi_{ji}}.
```

These are the two denominators in the Allen-Arkolakis exact-hat equations. The
loader does not impose equality between them because residence, workplace, and
traffic are separately observed in the Seattle replication.

## Local equilibrium system

Write $r_i=d\log l_i^R$, $f_i=d\log l_i^F$, and
$c=d\log\chi$. Define $d=1+\theta\lambda$ and

```math
A=\begin{bmatrix}
1-\beta\theta & \theta\lambda(1-\alpha\theta)/d\\
\theta\lambda(1-\beta\theta)/d & 1-\alpha\theta
\end{bmatrix}.
```

The first $N$ residuals linearize the workplace-side exact-hat equation. The
next $N-1$ residuals linearize its residence-side counterpart. Two final rows
impose

```math
\sum_i l_i^R r_i=0,\qquad \sum_i l_i^F f_i=0.
```

For a primitive log-cost shock on edge $i\to j$, the direct residual loading is

```math
B_{i,e}=\frac{\theta}{d}\mu_{ij},\qquad
B_{N+j,e}=\frac{\theta}{d}\lambda_{ij},
```

with the second entry omitted when that equilibrium row is replaced by a
normalization. If $J$ is the resulting $(2N+1)\times(2N+1)$ Jacobian, then

```math
dz=-J^{-1}B\,d\log\bar t.
```

The replication's $\chi$ is inverse welfare raised to $\theta$. Hence

```math
d\log W=-\frac{1}{\theta}d\log\chi,
```

and the reported benefit elasticity is

```math
-\frac{d\log W}{d\log\bar t_e}
=q^\top J^{-1}B_e,
\qquad q=(0,\ldots,0,-1/\theta)^\top.
```

When (alpha=\beta=\lambda=0) and the baseline accounting identities hold,
this expression equals the directed-edge traffic share.

## Configuration

```toml
[model]
spatial_specification = "urban_commuting"
alpha = -0.12
beta = -0.10
theta = 6.83
lambda = 0.07144948755490483
route_curvature = "theorem"

[congestion]
specification = "none"
```

`model.lambda` is the Allen-Arkolakis congestion elasticity. A separate package
`[congestion]` block is rejected for this specification to prevent double
counting.

## Verification

The synthetic example compares every analytic directed-edge derivative with a
central finite difference from the nonlinear exact-hat system. The Seattle
adapter additionally verifies the source hashes and reproduces the archive's
217 nodes, 1,384 directed edges, and 692 physical links.

Sources: [Allen and Arkolakis paper](https://par.nsf.gov/servlets/purl/10383104),
[replication archive](https://dl.dropbox.com/s/mmux9ys035xi6iu/RESTUD26454_Replication.zip).
