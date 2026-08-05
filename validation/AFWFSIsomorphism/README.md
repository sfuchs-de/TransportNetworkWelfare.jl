# AFW--Fajgelbaum--Schaal Isomorphism Validation

This Julia subpackage numerically validates the commutative diagram connecting:

1. the entropy-regularized Markov route-flow primal;
2. its soft-Bellman route dual;
3. the efficient fixed-network spatial planner;
4. the full bilateral Allen--Fuchs--Wong decentralized equilibrium;
5. the condensed recursive AFW market-access system at `theta = sigma - 1`;
6. the AFW welfare adjoint; and
7. the hard-routing Fajgelbaum--Schaal limit.

The level comparison and the derivative comparison are deliberately separate.
At each finite route curvature, the efficient planner and full decentralized
equilibrium should coincide. At equal curvature, the full equilibrium should
also coincide with the two-field recursive system. The adjoint then evaluates
the derivative of that common allocation. Increasing route curvature while
holding the goods elasticity fixed tests convergence to hard routing.

## Why this is a subpackage

`JuMP.jl` and `Ipopt.jl` are used only for independent planner and route-primal
checks. Keeping them under `validation/` avoids adding nonlinear-optimization
dependencies to the main `TransportNetworkWelfare.jl` package. The recursive
Jacobian and adjoint are taken directly from
`TransportNetworkWelfare.AdjointRSUE`, so the validation exercises the same
kernel used by the package rather than a duplicate implementation.

## Run

From this directory:

```bash
julia --project=. -e 'using Pkg; Pkg.develop(path="../.."); Pkg.instantiate(); Pkg.test()'
```

Generate the machine-readable report:

```bash
julia --project=. scripts/run_validation.jl output/validation.toml
```

## Tests

The suite requires:

- route-primal and soft-Bellman values and edge occupancies to agree;
- planner welfare, labor, and bilateral consumption to match the full AFW equilibrium;
- the recursive AFW system to match the full equilibrium at `theta = sigma - 1`;
- the recursive closure to fail away from equal curvature (negative control);
- the efficient AFW adjoint, finite differences, and traffic to agree; and
- route costs and spatial allocations to converge monotonically to hard routing.

The synthetic network is small, directed, strongly connected, cyclic, and has
several competing routes. No restricted empirical data are required.
