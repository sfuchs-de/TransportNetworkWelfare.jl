"""
    route_dual(economy)

Solve the entropy-regularized route block through its soft-Bellman/resolvent
dual. Returns `K`, `G=(I-K)^{-1}`, effective bilateral costs `tau`, and the
route-kernel spectral radius.
"""
function route_dual(e::IsomorphismEconomy)
    N = length(e.A)
    K = _kernel(e)
    spectral_radius = maximum(abs.(eigvals(K)))
    spectral_radius < 1 - 1e-12 || throw(ArgumentError(
        "route kernel is not contractive: spectral radius = $spectral_radius"))
    identity = Matrix{Float64}(I, N, N)
    G = (identity - K) \ identity
    minimum(G) > 0 || throw(ArgumentError("every ordered pair must be reachable"))
    tau = G .^ (-1 / e.theta)
    return (; K, G, tau, spectral_radius)
end

function _finite_difference_jacobian(f, x::AbstractVector)
    fx = f(x)
    m, n = length(fx), length(x)
    J = zeros(Float64, m, n)
    for j in 1:n
        h = cbrt(eps(Float64)) * max(1.0, abs(x[j]))
        xp = copy(x); xm = copy(x)
        xp[j] += h; xm[j] -= h
        J[:, j] .= (f(xp) .- f(xm)) ./ (2h)
    end
    return J
end

function _newton_solve(f, x0::AbstractVector; tolerance::Real=1e-11,
                       max_iterations::Int=100)
    x = Vector{Float64}(x0)
    for iteration in 1:max_iterations
        residual = f(x)
        residual_norm = norm(residual, Inf)
        residual_norm <= tolerance && return (; x, residual, iteration, converged=true)
        J = _finite_difference_jacobian(f, x)
        step = J \ residual
        scale = 1.0
        accepted = false
        while scale >= 2.0^-20
            candidate = x .- scale .* step
            candidate_norm = norm(f(candidate), Inf)
            if isfinite(candidate_norm) && candidate_norm < residual_norm
                x = candidate
                accepted = true
                break
            end
            scale *= 0.5
        end
        accepted || throw(ErrorException(
            "Newton line search failed at residual $residual_norm"))
    end
    residual = f(x)
    throw(ErrorException("Newton solver did not converge; residual=$(norm(residual, Inf))"))
end
