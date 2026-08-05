"""All-pairs hard shortest-route costs in multiplicative units."""
function hard_route_costs(e::IsomorphismEconomy)
    N = length(e.A)
    distance = fill(Inf, N, N)
    for i in 1:N
        distance[i, i] = 0.0
    end
    for (i, j) in active_edges(e)
        distance[i, j] = min(distance[i, j], log(e.kappa[i, j]))
    end
    for k in 1:N, i in 1:N, j in 1:N
        candidate = distance[i, k] + distance[k, j]
        candidate < distance[i, j] && (distance[i, j] = candidate)
    end
    all(isfinite, distance) || throw(ArgumentError("hard route graph is not strongly connected"))
    return exp.(distance)
end

"""
    hard_limit_diagnostics(economy; theta_grid=(2,4,...,256))

Hold the goods elasticity fixed and raise only route curvature. The returned
sequence therefore isolates the zero-entropy limit rather than changing route
and goods substitution together. The extended grid is intentional: convergence
can be slow when the first- and second-best route costs are close.
"""
function hard_limit_diagnostics(e::IsomorphismEconomy;
                                theta_grid=(2.0, 4.0, 8.0, 16.0, 32.0,
                                            64.0, 128.0, 256.0))
    tau_hard = hard_route_costs(e)
    hard = _full_solution_from_tau(e, tau_hard)
    rows = NamedTuple[]
    previous_tau_error = Inf
    for theta in theta_grid
        current_e = with_theta(e, theta)
        route = route_dual(current_e)
        full = solve_full_afw(current_e; route)
        tau_error = maximum(abs.(log.(route.tau) - log.(tau_hard)))
        push!(rows, (;
            theta=Float64(theta),
            tau_error,
            welfare_error=abs(full.W - hard.W),
            labor_error=norm(full.L - hard.L, Inf),
            monotone=tau_error <= previous_tau_error + 1e-10,
        ))
        previous_tau_error = tau_error
    end
    return (; hard, rows)
end

function write_validation_report(path::AbstractString, results::AbstractDict)
    mkpath(dirname(path))
    open(path, "w") do io
        TOML.print(io, results; sorted=true)
    end
    return path
end
