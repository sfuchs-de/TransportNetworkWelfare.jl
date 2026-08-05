"""
    run_validation(; output=nothing)

Run the numerical commutative-diagram test:
1. Markov route-flow primal versus soft-Bellman dual;
2. entropy-regularized spatial planner versus full AFW equilibrium;
3. full versus recursive AFW equilibrium at `theta=sigma-1`;
4. recursive adjoint versus traffic and finite differences;
5. failure of recursive condensation away from equal curvature;
6. convergence to hard routing.
"""
function run_validation(; output=nothing)
    e = synthetic_economy()
    route = route_dual(e)
    full = solve_full_afw(e; route)
    route_primal = solve_route_primal(e, 1, 4; route)
    planner = solve_spatial_planner(e; route, start=full)
    recursive = solve_recursive_afw(e; start=full)
    adjoint = adjoint_diagnostics(e, recursive)
    finite_difference = finite_difference_edge_effects(e; baseline=full)
    edge_mask = [isfinite(e.kappa[i, j]) && i != j for i in axes(e.kappa, 1), j in axes(e.kappa, 2)]
    fd_error = maximum(abs.(finite_difference[edge_mask] - adjoint.elasticity[edge_mask]))

    mismatch = with_theta(e, 2.2)
    mismatch_full = solve_full_afw(mismatch)
    mismatch_residual = recursive_closure_residual(mismatch, mismatch_full)
    hard = hard_limit_diagnostics(e)
    hard_last = last(hard.rows)

    results = Dict{String, Any}(
        "network" => Dict(
            "nodes" => length(e.A),
            "edges" => length(active_edges(e)),
            "sigma" => e.sigma,
            "theta" => e.theta,
            "route_spectral_radius" => route.spectral_radius,
        ),
        "route_primal_dual" => Dict(
            "value_error" => route_primal.value_error,
            "flow_error" => route_primal.flow_error,
            "conservation_error" => norm(route_primal.conservation, Inf),
        ),
        "planner_equilibrium" => Dict(
            "welfare_error" => abs(planner.W - full.W),
            "labor_error" => norm(planner.L - full.L, Inf),
            "consumption_error" => norm(planner.c - full.c, Inf),
            "resource_binding_error" => norm(planner.resource_slack, Inf),
            "utility_binding_error" => norm(planner.utility_slack, Inf),
        ),
        "recursive_condensation" => Dict(
            "welfare_error" => abs(recursive.W - full.W),
            "labor_error" => norm(recursive.L - full.L, Inf),
            "residual" => recursive.residual_norm,
            "closure_residual" => recursive_closure_residual(e, full),
            "mismatch_residual_theta_2_2" => mismatch_residual,
        ),
        "adjoint" => Dict(
            "traffic_error" => adjoint.traffic_error,
            "endpoint_error" => adjoint.endpoint_error,
            "linear_residual" => adjoint.linear_residual,
            "finite_difference_error" => fd_error,
        ),
        "hard_limit" => Dict(
            "theta_last" => hard_last.theta,
            "tau_error_last" => hard_last.tau_error,
            "welfare_error_last" => hard_last.welfare_error,
            "labor_error_last" => hard_last.labor_error,
            "monotone" => all(row.monotone for row in hard.rows),
        ),
    )
    isnothing(output) || write_validation_report(output, results)
    return results
end
