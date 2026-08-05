"""
    IsomorphismEconomy(A, u, kappa, sigma, theta; labor=1.0)

Efficient integrated spatial economy used to verify the AFW--Fajgelbaum--Schaal
isomorphism. `kappa[i,j]` is the positive cost of an active directed edge and
`Inf` denotes an absent edge. The zero-edge walk is represented separately by
an identity term in the route resolvent.
"""
struct IsomorphismEconomy{T<:AbstractFloat}
    A::Vector{T}
    u::Vector{T}
    kappa::Matrix{T}
    sigma::T
    theta::T
    labor::T
end

function IsomorphismEconomy(A::AbstractVector, u::AbstractVector,
                            kappa::AbstractMatrix, sigma::Real, theta::Real;
                            labor::Real=1.0)
    N = length(A)
    length(u) == N || throw(DimensionMismatch("A and u must have the same length"))
    size(kappa) == (N, N) || throw(DimensionMismatch("kappa must be N by N"))
    all(isfinite, A) && all(>(0), A) || throw(ArgumentError("A must be finite and positive"))
    all(isfinite, u) && all(>(0), u) || throw(ArgumentError("u must be finite and positive"))
    sigma > 1 || throw(ArgumentError("sigma must exceed one"))
    theta > 0 || throw(ArgumentError("theta must be positive"))
    labor > 0 || throw(ArgumentError("labor must be positive"))
    K = Matrix{Float64}(kappa)
    for i in 1:N
        K[i, i] = Inf
    end
    for value in K
        isinf(value) || value > 0 || throw(ArgumentError("active edge costs must be positive"))
    end
    return IsomorphismEconomy(
        Vector{Float64}(A), Vector{Float64}(u), K,
        Float64(sigma), Float64(theta), Float64(labor),
    )
end

with_theta(e::IsomorphismEconomy, theta::Real) =
    IsomorphismEconomy(e.A, e.u, e.kappa, e.sigma, theta; labor=e.labor)

"""Deterministic five-node network with cycles and several competing routes."""
function synthetic_economy(; sigma::Real=4.0, theta::Real=sigma - 1, labor::Real=1.0)
    N = 5
    kappa = fill(Inf, N, N)
    edges = [
        (1,2,2.40), (2,3,2.30), (3,4,2.20), (4,5,2.30), (5,1,2.50),
        (2,1,2.80), (3,2,2.70), (4,3,2.60), (5,4,2.70), (1,5,2.90),
        (1,3,3.20), (2,4,3.10), (3,5,3.00), (4,1,3.30), (5,2,3.20),
    ]
    for (i, j, value) in edges
        kappa[i, j] = value
    end
    A = [1.00, 1.10, 0.92, 1.18, 1.04]
    u = [1.00, 0.96, 1.09, 0.91, 1.05]
    return IsomorphismEconomy(A, u, kappa, sigma, theta; labor)
end

active_edges(e::IsomorphismEconomy) =
    [(i, j) for i in axes(e.kappa, 1), j in axes(e.kappa, 2)
     if i != j && isfinite(e.kappa[i, j])]

function _kernel(e::IsomorphismEconomy; exponent::Real=e.theta)
    N = length(e.A)
    K = zeros(Float64, N, N)
    for (i, j) in active_edges(e)
        K[i, j] = e.kappa[i, j]^(-exponent)
    end
    return K
end
