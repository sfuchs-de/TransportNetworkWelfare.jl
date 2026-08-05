function _recursive_components(e::IsomorphismEconomy, z::AbstractVector)
    abs(e.theta - (e.sigma - 1)) <= 1e-10 || throw(ArgumentError(
        "recursive AFW condensation requires theta = sigma - 1"))
    N = length(e.A)
    sigma = e.sigma
    x = exp.(z[1:N]); y = exp.(z[N+1:2N])
    Z = x .* y .^ (sigma / (sigma - 1))
    W = e.labor / sum(Z)
    L = W .* Z
    wages = y .^ (-1 / (sigma - 1))
    aggregate = (sum(Z) / e.labor)^(sigma - 1)
    phi = (e.A .* e.u) .^ (sigma - 1)
    S1 = phi .* aggregate .* x
    S2 = phi .* aggregate .* y
    mu_numerator = zeros(Float64, N, N)
    lambda_numerator = zeros(Float64, N, N)
    for (i, k) in active_edges(e)
        value = e.kappa[i, k]^(1 - sigma)
        mu_numerator[i, k] = value * (e.A[k] / e.A[i])^(1 - sigma) * x[k]
        S1[i] += mu_numerator[i, k]
        lambda_numerator[i, k] = value * (e.u[i] / e.u[k])^(1 - sigma) * y[i]
        S2[k] += lambda_numerator[i, k]
    end
    residual = zeros(Float64, 2N)
    residual[1:N] .= log.(S1) .- log.(x)
    residual[N+1:2N-1] .= log.(S2[1:N-1]) .- log.(y[1:N-1])
    residual[2N] = -log(y[N]) / (sigma - 1)
    sx = phi .* aggregate .* x ./ S1
    sy = phi .* aggregate .* y ./ S2
    mu = mu_numerator ./ reshape(S1, N, 1)
    lambda = lambda_numerator ./ reshape(S2, 1, N)
    omega = L ./ e.labor
    inward = W^(sigma - 1) .* wages .^ (1 - sigma) .* e.u .^ (1 - sigma)
    outward = e.A .^ (1 - sigma) .* wages .^ sigma .* L
    Y = sum(wages .* L)
    exposure = inward .* outward ./ Y
    Xi = zeros(Float64, N, N)
    for (i, j) in active_edges(e)
        Xi[i, j] = e.kappa[i, j]^(1 - sigma) * inward[i] * outward[j] / Y
    end
    return (;
        residual, x, y, Z, W, L, wages, aggregate, S1, S2,
        sx, sy, mu, lambda, omega, inward, outward, exposure, Xi, Y,
    )
end

"""Independently solve the two-market-access recursive AFW system."""
function solve_recursive_afw(e::IsomorphismEconomy; start=nothing)
    abs(e.theta - (e.sigma - 1)) <= 1e-10 || throw(ArgumentError(
        "recursive AFW condensation requires theta = sigma - 1"))
    benchmark = isnothing(start) ? solve_full_afw(e) : start
    wages = benchmark.wages ./ benchmark.wages[end]
    x0 = benchmark.L .* wages .^ e.sigma ./ benchmark.W
    y0 = wages .^ (1 - e.sigma)
    z0 = log.(vcat(x0, y0))
    f(z) = _recursive_components(e, z).residual
    solved = _newton_solve(f, z0)
    components = _recursive_components(e, solved.x)
    return merge(components, (;
        z=solved.x, iterations=solved.iteration,
        residual_norm=norm(components.residual, Inf),
    ))
end

"""Residual of the paper's linear market-access closure at a full AFW allocation."""
function recursive_closure_residual(e::IsomorphismEconomy, full=solve_full_afw(e))
    N = length(e.A)
    sigma = e.sigma
    Ksigma = _kernel(e; exponent=sigma - 1)
    inward = full.P .^ (1 - sigma)
    outward = e.A .^ (1 - sigma) .* full.wages .^ sigma .* full.L
    local_inward = e.A .^ (sigma - 1) .* full.wages .^ (1 - sigma)
    local_outward = full.W^(1 - sigma) .* e.u .^ (sigma - 1) .*
                     full.wages .^ sigma .* full.L
    r_in = inward - local_inward - transpose(Ksigma) * inward
    r_out = outward - local_outward - Ksigma * outward
    return max(norm(r_in, Inf) / max(norm(inward, Inf), 1e-12),
               norm(r_out, Inf) / max(norm(outward, Inf), 1e-12))
end

"""Evaluate the efficient recursive adjoint and compare it with exposure/traffic."""
function adjoint_diagnostics(e::IsomorphismEconomy, recursive=solve_recursive_afw(e))
    N = length(e.A)
    coefficients = AR.coefs(0.0, 0.0, e.sigma)
    J = AR.assemble_J(recursive.sx, recursive.sy, recursive.mu,
                      recursive.lambda, recursive.omega, coefficients)
    multipliers = AR.adjoint_multipliers(
        J, recursive.omega, e.sigma, recursive.exposure)
    elasticity = zeros(Float64, N, N)
    endpoint_sum = fill(NaN, N, N)
    for (k, l) in active_edges(e)
        elasticity[k, l] = AR.prop2_edge_elasticity(
            k, l, 1.0, recursive.Xi[k, l], multipliers, 1.0; N=N)
        endpoint_sum[k, l] = multipliers.Min[k] + (l == N ? 0.0 : multipliers.Mout[l])
    end
    edge_mask = [isfinite(e.kappa[i, j]) && i != j for i in 1:N, j in 1:N]
    return (;
        J, multipliers, elasticity, endpoint_sum,
        traffic_error=maximum(abs.(elasticity[edge_mask] - recursive.Xi[edge_mask])),
        endpoint_error=maximum(abs.(endpoint_sum[edge_mask] .- 1.0)),
        linear_residual=norm(transpose(J) *
            vcat(-multipliers.𝓛in, -multipliers.𝓛out) -
            AR.psi_row(recursive.omega, e.sigma), Inf),
    )
end

"""Central finite-difference planner/equilibrium welfare effects for every edge."""
function finite_difference_edge_effects(e::IsomorphismEconomy; step::Real=1e-5,
                                        baseline=solve_full_afw(e))
    N = length(e.A)
    effects = zeros(Float64, N, N)
    for (k, l) in active_edges(e)
        plus_kappa = copy(e.kappa); minus_kappa = copy(e.kappa)
        plus_kappa[k, l] *= exp(step)
        minus_kappa[k, l] *= exp(-step)
        plus = IsomorphismEconomy(e.A, e.u, plus_kappa, e.sigma, e.theta; labor=e.labor)
        minus = IsomorphismEconomy(e.A, e.u, minus_kappa, e.sigma, e.theta; labor=e.labor)
        plus_solution = solve_full_afw(plus; initial_logp=baseline.logp)
        minus_solution = solve_full_afw(minus; initial_logp=baseline.logp)
        effects[k, l] = -(log(plus_solution.W) - log(minus_solution.W)) / (2step)
    end
    return effects
end
