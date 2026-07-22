"""
Exact common-baseline decompositions for the corrected Proposition-2 estimator.

The module works with realized edge-mode frictions first. Primitive-cost
pass-through is applied afterward through `chi_wedge`. This keeps the welfare
row and direct shock map fixed across the NC, NT, F, and FM closures, which is
the condition needed for the inverse-Jacobian gap identity.
"""
module IFTDecomposition

using LinearAlgebra

using ..AdjointRSUE

export jacobian_parts, jacobian_factors, response_rows, cost_loading_matrix
export fixed_mode_congestion_J, build_closures
export reconstruct_route_kernel, route_incidence
export soft_route_operators, fixed_route_operators, route_bridge_probe
export edge_shock, operator_gain, inverse_gap
export decompose_road_edges, aggregate_physical_links

"""Split `assemble_J` into its sparse and fixed-labor aggregate blocks."""
function jacobian_parts(sx::AbstractVector, sy::AbstractVector,
                        mu::AbstractMatrix, lam::AbstractMatrix,
                        omega::AbstractVector, c::Coef)
    N = length(sx)
    sigma = c.σ
    J_global = zeros(2N, 2N)
    stacked = vcat(sx, sy[1:N-1])
    outer = stacked * permutedims(omega)
    J_global[1:2N-1, 1:N] .= ((sigma - 1) / c.e) .* outer
    J_global[1:2N-1, N+1:2N] .= (sigma / c.e) .* outer

    J_total = assemble_J(sx, sy, mu, lam, omega, c)
    J_sparse = J_total .- J_global
    return (; sparse=J_sparse, global_feedback=J_global, total=J_total)
end

"""Analytic sparse-plus-rank-one factorization of the no-congestion Jacobian."""
function jacobian_factors(sx::AbstractVector, sy::AbstractVector,
                          mu::AbstractMatrix, lam::AbstractMatrix,
                          omega::AbstractVector, c::Coef)
    parts = jacobian_parts(sx, sy, mu, lam, omega, c)
    N = length(sx)
    stacked = vcat(sx, sy[1:N-1])
    u = zeros(2N)
    u[1:2N-1] .= ((c.σ-1)/c.e) .* stacked
    v = vcat(omega, (c.σ/(c.σ-1)) .* omega)
    residual = maximum(abs.(parts.total .- (parts.sparse + u*permutedims(v))))
    return (; D=parts.sparse, u, v, total=parts.total, residual)
end

"""
Return the edge-by-state matrix for the non-cost component of traffic growth.

For edge `(i,j)`, the row is the appendix object
`d log R_ij / d(log x, log y)` used by `congestion_J`.
"""
function response_rows(N::Int, edges::Vector{Tuple{Int,Int}},
                       omega::AbstractVector, nu::AbstractVector, c::Coef)
    sigma = c.σ
    R = zeros(length(edges), 2N)
    dense_x = (-(sigma - 1) / c.e) .* omega .- c.cA .* nu
    dense_y = (-sigma / c.e) .* omega .- ((1 - c.β) / c.e) .* nu

    for (t, (i, j)) in enumerate(edges)
        @views R[t, 1:N] .= dense_x
        @views R[t, N+1:2N] .= dense_y
        R[t, i] += -c.cC
        R[t, j] += c.cA
        R[t, N+i] += (1 - c.β) / c.e
        R[t, N+j] += -c.cB
    end
    return R
end

"""Derivative of the residual system with respect to aggregate edge costs."""
function cost_loading_matrix(N::Int, edges::Vector{Tuple{Int,Int}},
                             mu::AbstractMatrix, lam::AbstractMatrix,
                             sigma::Real)
    B = zeros(2N, length(edges))
    for (t, (i, j)) in enumerate(edges)
        B[i, t] = (1 - sigma) * mu[i, j]
        if j <= N - 1
            B[N+j, t] = (1 - sigma) * lam[i, j]
        end
    end
    return B
end

"""Aggregate-cost feedback from traffic when modal traffic shares are frozen."""
function fixed_mode_feedback(s::AbstractVector, gamma::AbstractVector,
                             sigma::Real)
    gamma_bar = dot(s, gamma)
    denom = 1 - (1 - sigma) * gamma_bar
    abs(denom) > 1e-12 || error("singular fixed-mode congestion system")
    return gamma_bar / denom
end

"""
Congestion block under the fixed-observed-modal-share closure.

The closure sets `d log Xi_m = d log Xi` while retaining all baseline modes.
It is not a literal road-only recalibration.
"""
function fixed_mode_congestion_J(N::Int, edges::Vector{Tuple{Int,Int}},
                                 s_edges::AbstractMatrix,
                                 mu::AbstractMatrix, lam::AbstractMatrix,
                                 omega::AbstractVector, nu::AbstractVector,
                                 gamma::AbstractVector, sigma::Real, c::Coef)
    R = response_rows(N, edges, omega, nu, c)
    B = cost_loading_matrix(N, edges, mu, lam, sigma)
    g = [fixed_mode_feedback(@view(s_edges[t, :]), gamma, sigma)
         for t in axes(s_edges, 1)]
    return B * (g .* R)
end

"""Construct the exact NC, NT, F, and fixed-mode closure Jacobians."""
function build_closures(N::Int, edges::Vector{Tuple{Int,Int}},
                        s_edges::AbstractMatrix,
                        sx::AbstractVector, sy::AbstractVector,
                        mu::AbstractMatrix, lam::AbstractMatrix,
                        omega::AbstractVector, nu::AbstractVector,
                        gamma_full::AbstractVector, eta::Real, c::Coef;
                        road_mode::Int=1, port_mode::Int=4)
    parts = jacobian_parts(sx, sy, mu, lam, omega, c)
    J_NC = copy(parts.total)

    gamma_road = zeros(length(gamma_full))
    gamma_road[road_mode] = gamma_full[road_mode]
    Jc_road = congestion_J(N, edges, s_edges, mu, lam, omega, nu,
                           gamma_road, eta, c)
    J_NT = J_NC .+ Jc_road

    Jc_full = congestion_J(N, edges, s_edges, mu, lam, omega, nu,
                           gamma_full, eta, c)
    J_F = J_NC .+ Jc_full
    J_FM = J_NC .+ fixed_mode_congestion_J(
        N, edges, s_edges, mu, lam, omega, nu, gamma_full, c.σ, c)

    return (;
        NC=J_NC,
        NT=J_NT,
        F=J_F,
        FM=J_FM,
        sparse=parts.sparse,
        global_feedback=parts.global_feedback,
        road_congestion=J_NT .- J_NC,
        port_congestion=J_F .- J_NT,
        fixed_mode_congestion=J_FM .- J_NC,
        conditions=(
            NC=cond(J_NC),
            NT=cond(J_NT),
            F=cond(J_F),
            FM=cond(J_FM),
        ),
    )
end

"""
Reconstruct the soft-route resolvent and the implied bilateral flow matrix.

The gauge `K=mu` is valid because the original edge-pass matrix is diagonally
similar to `mu`. Conditional route intensities and flow reconstructions are
invariant to that diagonal similarity.
"""
function reconstruct_route_kernel(mu::AbstractMatrix, sx::AbstractVector,
                                  nu::AbstractVector, Xi::AbstractMatrix)
    N = length(sx)
    K = Matrix{Float64}(mu)
    T = (Matrix{Float64}(I, N, N) .- K) \ Matrix{Float64}(I, N, N)
    absorption = T * Diagonal(sx)
    Xod = Diagonal(nu) * absorption
    visits = vec(permutedims(nu) * T)
    Xi_reconstructed = Diagonal(visits) * K

    spectral_radius = maximum(abs.(eigvals(K)))
    row_error = maximum(abs.(vec(sum(Xod; dims=2)) .- nu))
    column_error = maximum(abs.(vec(sum(Xod; dims=1)) .- nu))
    absorption_error = maximum(abs.(vec(sum(absorption; dims=2)) .- 1))
    edge_error = maximum(abs.(Xi_reconstructed .- Xi))
    edge_relative_error = maximum(abs.(Xi_reconstructed .- Xi) ./ max.(abs.(Xi), 1e-15))

    return (;
        K,
        T,
        absorption,
        Xod,
        visits,
        Xi_reconstructed,
        diagnostics=(;
            spectral_radius,
            row_error,
            column_error,
            absorption_error,
            edge_error,
            edge_relative_error,
        ),
    )
end

"""OD-by-edge expected traversal counts under the reconstructed soft-route kernel."""
function route_incidence(T::AbstractMatrix, K::AbstractMatrix,
                         edges::Vector{Tuple{Int,Int}})
    N = size(T, 1)
    denom = max.(T, eps(Float64))
    incidence = Matrix{Float64}(undef, N * N, length(edges))
    for (t, (k, l)) in enumerate(edges)
        intensity = K[k, l] .* (T[:, k] * permutedims(T[l, :])) ./ denom
        incidence[:, t] .= vec(intensity)
    end
    return incidence
end

"""Traffic and residual operators when route weights adjust endogenously."""
function soft_route_operators(route, active_edges::Vector{Tuple{Int,Int}},
                              source::AbstractVector, destination::AbstractVector,
                              S::AbstractMatrix, D::AbstractMatrix,
                              dlogY::AbstractVector, sigma::Real)
    N = length(source)
    nv = size(S, 2)
    T = route.T
    K = route.K
    P = vec(permutedims(source) * T)
    Q = T * destination
    Cn = length(active_edges)
    ks = first.(active_edges)
    ls = last.(active_edges)
    kvals = [K[k, l] for (k, l) in active_edges]

    B = zeros(nv, Cn)
    for a in 1:Cn
        k, l = active_edges[a]
        out_weights = T[:, k] .* kvals[a] .* Q[l] ./ Q
        in_weights = P[k] .* kvals[a] .* T[l, :] ./ P
        B[1:N, a] .= (sigma - 1) .* out_weights
        B[N+1:2N-1, a] .= (sigma - 1) .* in_weights[1:N-1]
    end

    Pz = zeros(N, nv)
    Qz_node = zeros(N, nv)
    for k in 1:N
        Pz[k, :] .= vec(permutedims(source .* T[:, k] ./ P[k]) * S)
    end
    for l in 1:N
        Qz_node[l, :] .= vec(permutedims(T[l, :] .* destination ./ Q[l]) * D)
    end
    Qz = Pz[ks, :] .+ Qz_node[ls, :] .- permutedims(dlogY)

    C = zeros(Cn, Cn)
    for a in 1:Cn
        k, l = active_edges[a]
        for f in 1:Cn
            u, v = active_edges[f]
            C[a, f] =
                P[u] * kvals[f] * T[v, k] / P[k] +
                T[l, u] * kvals[f] * Q[v] / Q[l]
        end
        C[a, a] += 1
    end
    edge_traffic = [P[k] * K[k, l] * Q[l] for (k, l) in active_edges]
    return (; B, Qz, C, edge_traffic, P, Q)
end

"""
Traffic and residual operators when baseline OD edge-use weights are frozen.

The fixed-route traffic response uses products of baseline expected edge counts,
not the second moment generated by endogenous route reweighting. This distinction
is the route covariance removed by the FR closure.
"""
function fixed_route_operators(route, active_edges::Vector{Tuple{Int,Int}},
                               Xod::AbstractMatrix,
                               S::AbstractMatrix, D::AbstractMatrix,
                               dlogY::AbstractVector, sigma::Real;
                               return_incidence::Bool=false)
    N = size(Xod, 1)
    nv = size(S, 2)
    Cn = length(active_edges)
    incidence = route_incidence(route.T, route.K, active_edges)
    raw_incidence = return_incidence ? copy(incidence) : nothing
    xod = vec(Xod)
    edge_traffic = vec(permutedims(incidence) * xod)
    minimum(edge_traffic) > 0 || error("fixed-route active edge has zero traffic")

    source_weights = zeros(Cn, N)
    destination_weights = zeros(Cn, N)
    for a in 1:Cn
        inverse_traffic = 1 / edge_traffic[a]
        @inbounds for j in 1:N, i in 1:N
            od = i + (j - 1) * N
            weight = Xod[i, j] * incidence[od, a] * inverse_traffic
            source_weights[a, i] += weight
            destination_weights[a, j] += weight
        end
    end

    row_mass = vec(sum(Xod; dims=2))
    column_mass = vec(sum(Xod; dims=1))
    B = zeros(nv, Cn)
    for a in 1:Cn
        for i in 1:N
            row_mass[i] > 0 &&
                (B[i, a] = (sigma - 1) * edge_traffic[a] * source_weights[a, i] / row_mass[i])
            if i <= N - 1 && column_mass[i] > 0
                B[N+i, a] = (sigma - 1) * edge_traffic[a] *
                    destination_weights[a, i] / column_mass[i]
            end
        end
    end

    Qz = source_weights * S + destination_weights * D .- permutedims(dlogY)
    square_root_flow = sqrt.(max.(xod, 0.0))
    for a in 1:Cn
        @views incidence[:, a] .*= square_root_flow
    end
    second_product = permutedims(incidence) * incidence
    C = second_product ./ reshape(edge_traffic, :, 1)

    source_weight_error = maximum(abs.(vec(sum(source_weights; dims=2)) .- 1))
    destination_weight_error = maximum(abs.(vec(sum(destination_weights; dims=2)) .- 1))
    return (;
        B,
        Qz,
        C,
        edge_traffic,
        source_weights,
        destination_weights,
        incidence=raw_incidence,
        source_weight_error,
        destination_weight_error,
    )
end

"""
Audit a common dense-gravity basis against the corrected sparse estimator.

The no-congestion comparison is an equivalence check. The full comparison adds
the structural route-resolvent traffic response to the modal congestion system.
`route_available` is true only if both representations reproduce the corrected
edge derivatives. A failure therefore disables FR rather than substituting an
alternative estimand.
"""
function route_bridge_probe(route, edges::Vector{Tuple{Int,Int}},
                            s_edges::AbstractMatrix,
                            road_edges::Vector{Tuple{Int,Int}},
                            road_flow::AbstractMatrix, Xi::AbstractMatrix,
                            closures,
                            sx::AbstractVector, mu::AbstractMatrix,
                            lam::AbstractMatrix, omega::AbstractVector,
                            nu::AbstractVector, Tnode::AbstractVector,
                            gamma::AbstractVector, eta::Real, c::Coef;
                            tolerance::Real=1e-8)
    N = length(sx)
    sigma = c.σ
    nv = 2N + 1
    Xod = route.Xod
    source = nu
    destination = sx

    # Log derivatives of the two gravity factors in v=(log w, log L, log W).
    S = zeros(N, nv)
    D = zeros(N, nv)
    for i in 1:N
        S[i, i] = 1 - sigma
        S[i, N+i] = (sigma - 1) * c.α
        D[i, i] = sigma
        D[i, N+i] = (sigma - 1) * c.β + 1
        D[i, 2N+1] = 1 - sigma
    end

    # Dense no-congestion residual system: N sales, N-1 purchases,
    # fixed labor, and one wage normalization.
    J_dense_NC = zeros(nv, nv)
    for i in 1:N
        J_dense_NC[i, i] += 1
        J_dense_NC[i, N+i] += 1
        J_dense_NC[i, :] .-= S[i, :]
        J_dense_NC[i, :] .-= vec(permutedims(Xod[i, :] ./ nu[i]) * D)
    end
    for j in 1:N-1
        row = N + j
        J_dense_NC[row, j] += 1
        J_dense_NC[row, N+j] += 1
        J_dense_NC[row, :] .-= D[j, :]
        J_dense_NC[row, :] .-= vec(permutedims(Xod[:, j] ./ nu[j]) * S)
    end
    J_dense_NC[2N, N+1:2N] .= omega
    J_dense_NC[2N+1, N] = 1

    # Only edges carrying a congested mode enter the structural bridge.
    h_all = zeros(length(edges))
    for t in eachindex(edges)
        s = @view s_edges[t, :]
        Kmodal = Matrix(Diagonal(1 .- eta .* gamma)) .+
            eta .* (gamma * permutedims(s))
        h_all[t] = dot(s, Kmodal \ gamma)
    end
    active = findall(x -> abs(x) > 1e-15, h_all)
    active_edges = edges[active]
    h = h_all[active]
    Cn = length(active)
    dlogY = zeros(nv)
    dlogY[1:N] .= nu
    dlogY[N+1:2N] .= nu
    soft = soft_route_operators(
        route, active_edges, source, destination, S, D, dlogY, sigma)
    fixed = fixed_route_operators(
        route, active_edges, Xod, S, D, dlogY, sigma)
    B = soft.B
    Qz = soft.Qz
    C_full = soft.C

    pass_matrix = Matrix{Float64}(I, Cn, Cn) .-
        (1 - sigma) .* (reshape(h, :, 1) .* C_full)
    A_full = pass_matrix \ (reshape(h, :, 1) .* Qz)
    J_dense_F = J_dense_NC .+ B * A_full

    pass_fixed = Matrix{Float64}(I, Cn, Cn) .-
        (1 - sigma) .* (reshape(h, :, 1) .* fixed.C)
    A_fixed = pass_fixed \ (reshape(h, :, 1) .* fixed.Qz)
    J_dense_FR = J_dense_NC .+ fixed.B * A_fixed

    q_sparse = welfare_gradient(omega, c)
    welfare_selector = zeros(nv)
    welfare_selector[end] = 1
    adj_dense_NC = permutedims(J_dense_NC) \ welfare_selector
    adj_dense_F = permutedims(J_dense_F) \ welfare_selector
    adj_dense_FR = permutedims(J_dense_FR) \ welfare_selector
    adj_sparse_NC = permutedims(closures.NC) \ q_sparse
    adj_sparse_F = permutedims(closures.F) \ q_sparse
    active_lookup = Dict(edge => a for (a, edge) in enumerate(active_edges))
    errors_NC_abs = Float64[]
    errors_NC_rel = Float64[]
    errors_F_abs = Float64[]
    errors_F_rel = Float64[]
    route_identity_residuals = Float64[]
    route_results = Dict{Tuple{Int,Int},NamedTuple}()
    factor_dense_FR = lu(J_dense_FR)
    for (k, l) in road_edges
        a = active_lookup[(k, l)]
        share = road_flow[k, l] / Xi[k, l]
        b_dense = share .* B[:, a]
        E_dense_NC = dot(adj_dense_NC, b_dense)
        E_dense_F = dot(adj_dense_F, b_dense)
        E_dense_FR = dot(adj_dense_FR, b_dense)
        b_sparse = edge_shock(N, k, l, share, mu, lam, sigma)
        E_sparse_NC = dot(adj_sparse_NC, b_sparse)
        E_sparse_F = dot(adj_sparse_F, b_sparse)
        push!(errors_NC_abs, abs(E_dense_NC - E_sparse_NC))
        push!(errors_NC_rel, abs(E_dense_NC - E_sparse_NC) / max(abs(E_sparse_NC), 1e-15))
        push!(errors_F_abs, abs(E_dense_F - E_sparse_F))
        push!(errors_F_rel, abs(E_dense_F - E_sparse_F) / max(abs(E_sparse_F), 1e-15))
        response_FR = factor_dense_FR \ b_dense
        identity_residual = (E_dense_F - E_dense_FR) -
            dot(adj_dense_F, (J_dense_FR .- J_dense_F) * response_FR)
        push!(route_identity_residuals, abs(identity_residual))
        Xi_mode = road_flow[k, l]
        m_FR = E_dense_FR / (c.ρ * Xi_mode)
        route_results[(k, l)] = (;
            realized_FR=E_dense_FR,
            m_FR,
            scalar_residual_FR=E_dense_FR - c.ρ * Xi_mode * m_FR,
            identity_residual_route=identity_residual,
        )
    end

    max_NC_abs = maximum(errors_NC_abs)
    max_NC_rel = maximum(errors_NC_rel)
    max_F_abs = maximum(errors_F_abs)
    max_F_rel = maximum(errors_F_rel)
    fixed_edge_target = [Xi[k, l] for (k, l) in active_edges]
    fixed_edge_error = maximum(abs.(fixed.edge_traffic .- fixed_edge_target))
    fixed_edge_relative_error = maximum(
        abs.(fixed.edge_traffic .- fixed_edge_target) ./ max.(abs.(fixed_edge_target), 1e-15))
    fixed_B_error = maximum(abs.(fixed.B .- soft.B))
    max_route_identity_residual = maximum(route_identity_residuals)
    route_available =
        max_NC_rel < tolerance &&
        max_F_rel < tolerance &&
        fixed_edge_relative_error < tolerance &&
        fixed_B_error < tolerance &&
        max_route_identity_residual < tolerance

    return (;
        route_available,
        status=route_available ? "verified" : "unavailable_common_basis_bridge_failed",
        active_congestion_edges=Cn,
        max_NC_abs,
        max_NC_rel,
        max_F_abs,
        max_F_rel,
        cond_dense_NC=cond(J_dense_NC),
        cond_dense_F=cond(J_dense_F),
        cond_dense_FR=cond(J_dense_FR),
        cond_pass_full=cond(pass_matrix),
        cond_pass_fixed=cond(pass_fixed),
        fixed_edge_error,
        fixed_edge_relative_error,
        fixed_B_error,
        fixed_source_weight_error=fixed.source_weight_error,
        fixed_destination_weight_error=fixed.destination_weight_error,
        max_route_identity_residual,
        route_results,
    )
end

"""Direct residual shock for one realized edge-mode friction."""
function edge_shock(N::Int, k::Int, l::Int, mode_share::Real,
                    mu::AbstractMatrix, lam::AbstractMatrix, sigma::Real)
    b = zeros(2N)
    scale = (1 - sigma) * mode_share
    b[k] = scale * mu[k, l]
    if l <= N - 1
        b[N+l] = scale * lam[k, l]
    end
    return b
end

"""Realized-friction welfare gain `-d log W / d vartheta`."""
operator_gain(J::AbstractMatrix, q::AbstractVector, b::AbstractVector) =
    dot(q, J \ b)

"""
Exact inverse-Jacobian gap identity.

Returns `q' J_A^-1 (J_B-J_A) J_B^-1 b`, which must equal `E_A-E_B`.
"""
function inverse_gap(JA::AbstractMatrix, JB::AbstractMatrix,
                     q::AbstractVector, b::AbstractVector)
    adjoint_A = permutedims(JA) \ q
    response_B = JB \ b
    return dot(adjoint_A, (JB .- JA) * response_B)
end

@inline function edge_multiplier(mult, k::Int, l::Int, N::Int)
    return mult.Min[k] + (l == N ? 0.0 : mult.Mout[l])
end

"""Compute the exact directed-road decomposition for the verified closures."""
function decompose_road_edges(road_edges::Vector{Tuple{Int,Int}},
                              road_flow::AbstractMatrix, Xi::AbstractMatrix,
                              s_edges_by_pair::Dict{Tuple{Int,Int},Vector{Float64}},
                              route_available::Bool,
                              closures, mu::AbstractMatrix, lam::AbstractMatrix,
                              omega::AbstractVector, Tnode::AbstractVector,
                              gamma::AbstractVector, eta::Real, c::Coef;
                              road_mode::Int=1, route_results=nothing)
    N = length(omega)
    route_available && route_results === nothing &&
        error("verified route closure requires edge-level route results")
    q = welfare_gradient(omega, c)
    mult_NC = adjoint_multipliers(closures.NC, omega, c.σ, Tnode)
    mult_NT = adjoint_multipliers(closures.NT, omega, c.σ, Tnode)
    mult_F = adjoint_multipliers(closures.F, omega, c.σ, Tnode)
    mult_FM = adjoint_multipliers(closures.FM, omega, c.σ, Tnode)
    adj_NC = permutedims(closures.NC) \ q
    adj_NT = permutedims(closures.NT) \ q
    adj_F = permutedims(closures.F) \ q
    adj_FM = permutedims(closures.FM) \ q
    fac_NT = lu(closures.NT)
    fac_F = lu(closures.F)
    fac_FM = lu(closures.FM)

    rows = NamedTuple[]
    for (k, l) in road_edges
        Xi_mode = road_flow[k, l]
        Xi_edge = Xi[k, l]
        Xi_mode > 0 || continue
        s = Xi_mode / Xi_edge
        shares = s_edges_by_pair[(k, l)]
        chi = chi_wedge(shares, gamma, eta, c.σ)[road_mode]
        b = edge_shock(N, k, l, s, mu, lam, c.σ)

        m_NC = edge_multiplier(mult_NC, k, l, N)
        m_NT = edge_multiplier(mult_NT, k, l, N)
        m_F = edge_multiplier(mult_F, k, l, N)
        m_FM = edge_multiplier(mult_FM, k, l, N)
        route_result = route_available ? route_results[(k, l)] : nothing
        m_FR = route_available ? route_result.m_FR : NaN

        E_NC = c.ρ * Xi_mode * m_NC
        E_NT = c.ρ * Xi_mode * m_NT
        E_F = c.ρ * Xi_mode * m_F
        E_FM = c.ρ * Xi_mode * m_FM
        E_FR = route_available ? route_result.realized_FR : NaN
        E_primitive = chi * E_F

        d_road = m_NC - m_NT
        d_port = m_NT - m_F
        d_mode = m_F - m_FM
        d_route = route_available ? m_F - m_FR : NaN

        gap_externality = Xi_mode * (1 - c.ρ)
        gap_propagation = c.ρ * Xi_mode * (1 - m_NC)
        gap_road = c.ρ * Xi_mode * d_road
        gap_port = c.ρ * Xi_mode * d_port
        gap_pass_through = c.ρ * Xi_mode * m_F * (1 - chi)
        gap_total = Xi_mode - E_primitive
        gap_residual = gap_total - (
            gap_externality + gap_propagation + gap_road + gap_port + gap_pass_through)

        op_NC = dot(adj_NC, b)
        op_NT = dot(adj_NT, b)
        op_F = dot(adj_F, b)
        op_FM = dot(adj_FM, b)
        scalar_residual_FR = route_available ? route_result.scalar_residual_FR : NaN

        response_NT = fac_NT \ b
        response_F = fac_F \ b
        response_FM = fac_FM \ b
        id_road = (E_NC - E_NT) -
            dot(adj_NC, (closures.NT .- closures.NC) * response_NT)
        id_port = (E_NT - E_F) -
            dot(adj_NT, (closures.F .- closures.NT) * response_F)
        id_mode = (E_F - E_FM) -
            dot(adj_F, (closures.FM .- closures.F) * response_FM)
        id_route = route_available ? route_result.identity_residual_route : NaN

        push!(rows, (;
            k, l,
            hulten=Xi_mode,
            realized_NC=E_NC,
            realized_NT=E_NT,
            realized_F=E_F,
            realized_FM=E_FM,
            realized_FR=E_FR,
            primitive_F=E_primitive,
            m_NC, m_NT, m_F, m_FM, m_FR,
            d_road, d_port, d_mode, d_route,
            mode_contribution=c.ρ * Xi_mode * d_mode,
            route_contribution=route_available ? c.ρ * Xi_mode * d_route : NaN,
            chi,
            gap_total,
            gap_externality,
            gap_propagation,
            gap_road,
            gap_port,
            gap_pass_through,
            gap_residual,
            scalar_residual_NC=E_NC - op_NC,
            scalar_residual_NT=E_NT - op_NT,
            scalar_residual_F=E_F - op_F,
            scalar_residual_FM=E_FM - op_FM,
            scalar_residual_FR,
            identity_residual_road=id_road,
            identity_residual_port=id_port,
            identity_residual_mode=id_mode,
            identity_residual_route=id_route,
            route_available,
        ))
    end
    return rows
end

"""Sum directed elasticities and components into physical-link results."""
function aggregate_physical_links(rows::Vector{<:NamedTuple}, rho::Real)
    grouped = Dict{Tuple{Int,Int},Vector{NamedTuple}}()
    for row in rows
        key = minmax(row.k, row.l)
        push!(get!(grouped, key, NamedTuple[]), row)
    end

    out = NamedTuple[]
    for key in sort!(collect(keys(grouped)))
        group = grouped[key]
        hulten = sum(r.hulten for r in group)
        sumfield(name) = sum(getproperty(r, name) for r in group)
        route_ok = all(r.route_available for r in group)
        E_NC = sumfield(:realized_NC)
        E_NT = sumfield(:realized_NT)
        E_F = sumfield(:realized_F)
        E_FM = sumfield(:realized_FM)
        E_FR = route_ok ? sumfield(:realized_FR) : NaN
        m_NC = E_NC / (rho * hulten)
        m_NT = E_NT / (rho * hulten)
        m_F = E_F / (rho * hulten)
        m_FM = E_FM / (rho * hulten)
        m_FR = route_ok ? E_FR / (rho * hulten) : NaN
        primitive = sumfield(:primitive_F)
        chi_effective = E_F == 0 ? NaN : primitive / E_F

        push!(out, (;
            k=key[1], l=key[2], directions=length(group),
            hulten,
            realized_NC=E_NC,
            realized_NT=E_NT,
            realized_F=E_F,
            realized_FM=E_FM,
            realized_FR=E_FR,
            primitive_F=primitive,
            m_NC, m_NT, m_F, m_FM, m_FR,
            d_road=m_NC - m_NT,
            d_port=m_NT - m_F,
            d_mode=m_F - m_FM,
            d_route=route_ok ? m_F - m_FR : NaN,
            mode_contribution=sumfield(:mode_contribution),
            route_contribution=route_ok ? sumfield(:route_contribution) : NaN,
            chi_effective,
            gap_total=sumfield(:gap_total),
            gap_externality=sumfield(:gap_externality),
            gap_propagation=sumfield(:gap_propagation),
            gap_road=sumfield(:gap_road),
            gap_port=sumfield(:gap_port),
            gap_pass_through=sumfield(:gap_pass_through),
            gap_residual=sumfield(:gap_residual),
            identity_residual_road=sumfield(:identity_residual_road),
            identity_residual_port=sumfield(:identity_residual_port),
            identity_residual_mode=sumfield(:identity_residual_mode),
            identity_residual_route=route_ok ? sumfield(:identity_residual_route) : NaN,
            route_available=route_ok,
        ))
    end
    return out
end

end # module
