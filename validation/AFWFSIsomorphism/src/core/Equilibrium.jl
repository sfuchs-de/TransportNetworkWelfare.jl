function _price_system(e::IsomorphismEconomy, tau::AbstractMatrix, logp::AbstractVector)
    N = length(e.A)
    p = exp.(logp)
    delivered = reshape(p, N, 1) .* tau
    weights = delivered .^ (1 - e.sigma)
    denominators = vec(sum(weights; dims=1))
    P = denominators .^ (1 / (1 - e.sigma))
    welfare_by_location = e.A .* p .* e.u ./ P
    residual = zeros(Float64, N)
    residual[1:N-1] .= log.(welfare_by_location[1:N-1]) .- log(welfare_by_location[N])
    residual[N] = logp[N]
    return residual, (; p, delivered, weights, denominators, P, welfare_by_location)
end

function _stationary_income(trade_shares::AbstractMatrix)
    N = size(trade_shares, 1)
    system = Matrix{Float64}(I, N, N) - trade_shares
    system[N, :] .= 1.0
    rhs = zeros(Float64, N); rhs[N] = 1.0
    shares = system \ rhs
    minimum(shares) > -1e-10 || throw(ErrorException("stationary income has negative entries"))
    shares = max.(shares, 0.0)
    shares ./= sum(shares)
    return shares
end

function _full_solution_from_tau(e::IsomorphismEconomy, tau::AbstractMatrix;
                                 initial_logp=nothing)
    N = length(e.A)
    x0 = isnothing(initial_logp) ? zeros(N) : Vector{Float64}(initial_logp)
    f(logp) = first(_price_system(e, tau, logp))
    solved = _newton_solve(f, x0)
    residual, prices = _price_system(e, tau, solved.x)
    trade_shares = prices.weights ./ reshape(prices.denominators, 1, N)
    income_unit = _stationary_income(trade_shares)
    wages = e.A .* prices.p
    income_scale = e.labor / sum(income_unit ./ wages)
    income = income_scale .* income_unit
    L = income ./ wages
    W = mean(prices.welfare_by_location)
    X = trade_shares .* reshape(income, 1, N)
    c = X ./ prices.delivered
    return (;
        W, L, wages, p=prices.p, P=prices.P, income, X, c,
        trade_shares, tau=Matrix(tau), logp=solved.x,
        residual=norm(residual, Inf), iterations=solved.iteration,
    )
end

"""Solve the full bilateral efficient AFW equilibrium for arbitrary route curvature."""
function solve_full_afw(e::IsomorphismEconomy; route=route_dual(e), initial_logp=nothing)
    solution = _full_solution_from_tau(e, route.tau; initial_logp)
    traffic = route_edge_traffic(e, route, solution.X)
    return merge(solution, (; route, Xi=traffic))
end

"""
    route_edge_traffic(economy, route, X)

Expected edge traversals, valued by bilateral expenditure and normalized by
world income. This is the general-route-curvature social-savings traffic object.
"""
function route_edge_traffic(e::IsomorphismEconomy, route, X::AbstractMatrix)
    N = length(e.A)
    Xi = zeros(Float64, N, N)
    Y = sum(X)
    for (k, l) in active_edges(e)
        total = 0.0
        for i in 1:N, j in 1:N
            intensity = route.G[i, k] * route.K[k, l] * route.G[l, j] / route.G[i, j]
            total += X[i, j] * intensity
        end
        Xi[k, l] = total / Y
    end
    return Xi
end
