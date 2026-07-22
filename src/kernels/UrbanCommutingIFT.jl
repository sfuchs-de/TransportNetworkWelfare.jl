"""
Local welfare derivatives for the Allen-Arkolakis urban commuting model.

The state contains log changes in residence shares, workplace shares, and the
Allen-Arkolakis scale variable `chi`. Since aggregate welfare is proportional
to `chi^(-1/theta)`, the welfare row has final entry `-1/theta`.

This kernel follows the exact-hat equations in the Seattle replication archive.
It is separate from `AdjointRSUE`: routing concepts are common, but the urban
residual equations and welfare closure are not the trade model with new labels.
"""
module UrbanCommutingIFT

using LinearAlgebra

export Coefficients, coefficients, jacobian, cost_loading, welfare_gradient
export exact_hat_residual, exact_hat_jacobian, solve_exact_hat, finite_difference_elasticity

struct Coefficients
    alpha::Float64
    beta::Float64
    theta::Float64
    lambda::Float64
    denominator::Float64
    transform::Matrix{Float64}
    local_workplace::Float64
    local_residence::Float64
    remote_residence::Float64
    remote_workplace::Float64
    scale_remote::Float64
end

function coefficients(alpha::Real, beta::Real, theta::Real, lambda::Real)
    all(isfinite, (alpha, beta, theta, lambda)) ||
        throw(ArgumentError("urban parameters must be finite"))
    theta > 0 || throw(ArgumentError("urban theta must be positive"))
    lambda >= 0 || throw(ArgumentError("urban lambda must be nonnegative"))
    denominator = 1 + theta*lambda
    transform = [
        1-beta*theta                    theta*lambda*(1-alpha*theta)/denominator
        theta*lambda*(1-beta*theta)/denominator  1-alpha*theta
    ]
    abs(det(transform)) > 1e-10 || throw(ArgumentError(
        "urban residence-workplace transformation is singular"))
    local_workplace = theta*alpha + theta*lambda*(1-alpha*theta)/denominator
    local_residence = theta*beta + theta*lambda*(1-beta*theta)/denominator
    remote_residence = (1-beta*theta)/denominator
    remote_workplace = (1-alpha*theta)/denominator
    scale_remote = theta*lambda/denominator
    return Coefficients(
        Float64(alpha), Float64(beta), Float64(theta), Float64(lambda),
        denominator, transform, local_workplace, local_residence,
        remote_residence, remote_workplace, scale_remote,
    )
end

"""
    jacobian(sx, sy, mu, lam, residence, workplace, c)

Return the baseline Jacobian for the log exact-hat residual. The first `N`
rows are the workplace-side equations, the next `N-1` are the residence-side
equations, and the final two rows normalize residence and workplace shares.
"""
function jacobian(sx::AbstractVector, sy::AbstractVector,
                  mu::AbstractMatrix, lam::AbstractMatrix,
                  residence::AbstractVector, workplace::AbstractVector,
                  c::Coefficients)
    N = length(sx)
    all(length(v) == N for v in (sy, residence, workplace)) ||
        throw(DimensionMismatch("urban node vectors must have equal length"))
    size(mu) == (N, N) && size(lam) == (N, N) ||
        throw(DimensionMismatch("urban transition matrices must be N by N"))
    J = zeros(2N+1, 2N+1)
    a11, a12 = c.transform[1, 1], c.transform[1, 2]
    a21, a22 = c.transform[2, 1], c.transform[2, 2]

    for i in 1:N
        J[i, i] += a11
        J[i, N+i] += a12 - sx[i]*c.local_workplace
        @views J[i, 1:N] .-= mu[i, :].*c.remote_residence
        J[i, 2N+1] -= sx[i] + (1-sx[i])*c.scale_remote
    end
    for i in 1:N-1
        row = N+i
        J[row, i] += a21 - sy[i]*c.local_residence
        J[row, N+i] += a22
        @views J[row, N+1:2N] .-= lam[:, i].*c.remote_workplace
        J[row, 2N+1] -= sy[i] + (1-sy[i])*c.scale_remote
    end
    J[2N, 1:N] .= residence
    J[2N+1, N+1:2N] .= workplace
    return J
end

"Derivative of the urban residual with respect to primitive directed-edge costs."
function cost_loading(N::Int, edges::AbstractVector{<:Tuple},
                      mu::AbstractMatrix, lam::AbstractMatrix,
                      c::Coefficients)
    B = zeros(2N+1, length(edges))
    coefficient = c.theta/c.denominator
    for (edge_index, (i, j)) in enumerate(edges)
        B[i, edge_index] = coefficient*mu[i, j]
        j <= N-1 && (B[N+j, edge_index] = coefficient*lam[i, j])
    end
    return B
end

"Gradient of log aggregate welfare with respect to the urban log state."
function welfare_gradient(N::Int, c::Coefficients)
    q = zeros(2N+1)
    q[end] = -1/c.theta
    return q
end

function log_weighted_sum(local_weight::Real, local_log::Real,
                          network_weights::AbstractVector,
                          network_logs::AbstractVector)
    values = Float64[]
    weights = Float64[]
    local_weight > 0 && (push!(weights, local_weight); push!(values, local_log))
    for (weight, value) in zip(network_weights, network_logs)
        weight > 0 || continue
        push!(weights, weight)
        push!(values, value)
    end
    pivot = maximum(values)
    return pivot + log(sum(weight*exp(value-pivot) for (weight, value) in zip(weights, values)))
end

"Exact-hat residual used for independent nonlinear finite-difference checks."
function exact_hat_residual(z::AbstractVector, edge_shocks::AbstractVector,
                            edges::AbstractVector{<:Tuple},
                            sx::AbstractVector, sy::AbstractVector,
                            mu::AbstractMatrix, lam::AbstractMatrix,
                            residence::AbstractVector, workplace::AbstractVector,
                            c::Coefficients)
    N = length(sx)
    length(z) == 2N+1 || throw(DimensionMismatch("urban state must have length 2N+1"))
    length(edge_shocks) == length(edges) ||
        throw(DimensionMismatch("edge shock vector has the wrong length"))
    r = @view z[1:N]
    f = @view z[N+1:2N]
    logchi = z[end]
    shock = zeros(N, N)
    for (value, (i, j)) in zip(edge_shocks, edges)
        shock[i, j] = value
    end
    G = zeros(2N+1)
    cost_coefficient = -c.theta/c.denominator

    for i in 1:N
        network_logs = [
            c.scale_remote*logchi + cost_coefficient*shock[i, j] +
            c.remote_residence*r[j] for j in 1:N
        ]
        rhs = log_weighted_sum(
            sx[i], logchi+c.local_workplace*f[i], @view(mu[i, :]), network_logs)
        G[i] = c.transform[1, 1]*r[i] + c.transform[1, 2]*f[i] - rhs
    end
    for i in 1:N-1
        network_logs = [
            c.scale_remote*logchi + cost_coefficient*shock[j, i] +
            c.remote_workplace*f[j] for j in 1:N
        ]
        rhs = log_weighted_sum(
            sy[i], logchi+c.local_residence*r[i], @view(lam[:, i]), network_logs)
        G[N+i] = c.transform[2, 1]*r[i] + c.transform[2, 2]*f[i] - rhs
    end
    G[2N] = log(sum(residence.*exp.(r)))
    G[2N+1] = log(sum(workplace.*exp.(f)))
    return G
end

function normalized_component_weights(local_weight::Real, local_log::Real,
                                      network_weights::AbstractVector,
                                      network_logs::AbstractVector)
    logs = vcat(local_log, network_logs)
    raw_weights = vcat(local_weight, network_weights)
    pivot = maximum(logs[index] for index in eachindex(logs) if raw_weights[index] > 0)
    scaled = [raw_weights[index] > 0 ?
              raw_weights[index]*exp(logs[index]-pivot) : 0.0
              for index in eachindex(logs)]
    return scaled ./ sum(scaled)
end

"Analytic state Jacobian of the nonlinear urban exact-hat residual."
function exact_hat_jacobian(z::AbstractVector, edge_shocks::AbstractVector,
                            edges::AbstractVector{<:Tuple},
                            sx::AbstractVector, sy::AbstractVector,
                            mu::AbstractMatrix, lam::AbstractMatrix,
                            residence::AbstractVector, workplace::AbstractVector,
                            c::Coefficients)
    N = length(sx)
    r = @view z[1:N]
    f = @view z[N+1:2N]
    logchi = z[end]
    shock = zeros(N, N)
    for (value, (i, j)) in zip(edge_shocks, edges)
        shock[i, j] = value
    end
    J = zeros(2N+1, 2N+1)
    cost_coefficient = -c.theta/c.denominator
    for i in 1:N
        network_logs = [
            c.scale_remote*logchi + cost_coefficient*shock[i, j] +
            c.remote_residence*r[j] for j in 1:N
        ]
        posterior = normalized_component_weights(
            sx[i], logchi+c.local_workplace*f[i], @view(mu[i, :]), network_logs)
        local_probability = posterior[1]
        network_probability = @view posterior[2:end]
        J[i, i] += c.transform[1, 1]
        J[i, N+i] += c.transform[1, 2] -
                      local_probability*c.local_workplace
        @views J[i, 1:N] .-= network_probability.*c.remote_residence
        J[i, 2N+1] -= local_probability +
                       sum(network_probability)*c.scale_remote
    end
    for i in 1:N-1
        network_logs = [
            c.scale_remote*logchi + cost_coefficient*shock[j, i] +
            c.remote_workplace*f[j] for j in 1:N
        ]
        posterior = normalized_component_weights(
            sy[i], logchi+c.local_residence*r[i], @view(lam[:, i]), network_logs)
        local_probability = posterior[1]
        network_probability = @view posterior[2:end]
        J[N+i, i] += c.transform[2, 1] -
                      local_probability*c.local_residence
        J[N+i, N+i] += c.transform[2, 2]
        @views J[N+i, N+1:2N] .-= network_probability.*c.remote_workplace
        J[N+i, 2N+1] -= local_probability +
                         sum(network_probability)*c.scale_remote
    end
    residence_weights = residence.*exp.(r)
    workplace_weights = workplace.*exp.(f)
    J[2N, 1:N] .= residence_weights./sum(residence_weights)
    J[2N+1, N+1:2N] .= workplace_weights./sum(workplace_weights)
    return J
end

function numerical_jacobian(function_value, x::AbstractVector; step::Real=1e-6)
    baseline = function_value(x)
    J = zeros(length(baseline), length(x))
    for column in eachindex(x)
        plus, minus = copy(x), copy(x)
        plus[column] += step
        minus[column] -= step
        J[:, column] .= (function_value(plus)-function_value(minus))/(2step)
    end
    return J
end

"Solve the urban exact-hat system with a damped Newton method."
function solve_exact_hat(edge_shocks::AbstractVector, edges::AbstractVector{<:Tuple},
                         sx::AbstractVector, sy::AbstractVector,
                         mu::AbstractMatrix, lam::AbstractMatrix,
                         residence::AbstractVector, workplace::AbstractVector,
                         c::Coefficients; tolerance::Real=1e-11,
                         max_iterations::Int=60)
    N = length(sx)
    residual(z) = exact_hat_residual(
        z, edge_shocks, edges, sx, sy, mu, lam, residence, workplace, c)
    z = zeros(2N+1)
    for iteration in 1:max_iterations
        value = residual(z)
        norm(value, Inf) <= tolerance && return (;
            state=z, log_welfare=-z[end]/c.theta,
            residual=norm(value, Inf), iterations=iteration-1,
        )
        J = exact_hat_jacobian(
            z, edge_shocks, edges, sx, sy, mu, lam, residence, workplace, c)
        direction = -(J\value)
        old_norm = norm(value)
        scale = 1.0
        accepted = false
        while scale >= 2.0^-20
            candidate = z + scale*direction
            if norm(residual(candidate)) < old_norm
                z = candidate
                accepted = true
                break
            end
            scale /= 2
        end
        accepted || error("urban exact-hat Newton step failed to reduce the residual")
    end
    error("urban exact-hat solver did not converge in $max_iterations iterations")
end

"Central finite-difference welfare elasticity for one directed primitive-cost shock."
function finite_difference_elasticity(edge_index::Int, edges::AbstractVector{<:Tuple},
                                      sx::AbstractVector, sy::AbstractVector,
                                      mu::AbstractMatrix, lam::AbstractMatrix,
                                      residence::AbstractVector, workplace::AbstractVector,
                                      c::Coefficients; step::Real=1e-5)
    1 <= edge_index <= length(edges) || throw(BoundsError(edges, edge_index))
    shocks = zeros(length(edges))
    shocks[edge_index] = step
    plus = solve_exact_hat(shocks, edges, sx, sy, mu, lam, residence, workplace, c)
    shocks[edge_index] = -step
    minus = solve_exact_hat(shocks, edges, sx, sy, mu, lam, residence, workplace, c)
    elasticity = -(plus.log_welfare-minus.log_welfare)/(2step)
    return (; elasticity, plus, minus)
end

end
