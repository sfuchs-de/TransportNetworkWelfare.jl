"""
Route-consistent common-baseline IFT decomposition.

The transport block is written in edge-mode traffic and congestion-quantity
states. For closure S,

    x = Qz_S * z + C_S * a
    a = theta + G_S * q
    q = A * x

so H_S = I - A*C_S*G_S and the reduced equilibrium Jacobian is

    J_S = J0 + B*Sagg*G_S*H_S^(-1)*A*Qz_S.

Road quantities are directed road traffic. Terminal quantities are weighted
outbound and inbound rail traffic totals. This representation keeps endpoint
terminal congestion exact without solving in the full edge-mode dimension.
"""
module IFTCompleteDecomposition

using LinearAlgebra
using SparseArrays

using ..AdjointRSUE
using ..IFTDecomposition
using ..RSUETerminalCongestion: build_pair_basis

export build_complete_route_basis, build_complete_closures
export complete_road_decomposition, aggregate_complete_links
export primitive_road_forcing, structured_inverse_gap, structured_parallel_gap
export route_state_matrix, evaluate_complete_sensitivity_point

const ROUTE_TOL = 1e-10

"""Map derivatives in z=(log x,log y) into v=(log w,log L,log W)."""
function inverse_state_map(N::Int, omega::AbstractVector, c::Coef)
    V = zeros(2N + 1, 2N)
    qW = welfare_gradient(omega, c)
    wage_y = -(1 + c.β * (c.σ - 1)) / ((c.σ - 1) * c.e)
    for i in 1:N
        V[i, i] = c.α / c.e
        V[i, N+i] = wage_y
        V[N+i, :] .= qW ./ (1 + c.α + c.β)
        V[N+i, i] += 1 / c.e
        V[N+i, N+i] += c.σ / ((c.σ - 1) * c.e)
    end
    V[end, :] .= qW
    return V
end

"""Bilateral-flow rows in v=(log w,log L,log W)."""
function bilateral_state_rows(N::Int, c::Coef)
    nv = 2N + 1
    S = zeros(N, nv)
    D = zeros(N, nv)
    for i in 1:N
        S[i, i] = 1 - c.σ
        S[i, N+i] = (c.σ - 1) * c.α
        D[i, i] = c.σ
        D[i, N+i] = (c.σ - 1) * c.β + 1
        D[i, end] = 1 - c.σ
    end
    dlogY = zeros(nv)
    dlogY[1:N] .= 0.0
    return S, D, dlogY
end

function active_edge_and_pair_basis(data, full_basis)
    road_mode = full_basis.road_mode
    rail_mode = full_basis.mode_index[:rail]
    active_pairs = [p for p in 1:full_basis.P
                    if full_basis.pair_mode[p] in (road_mode, rail_mode)]
    active_global_edges = sort!(unique(full_basis.pair_edge[active_pairs]))
    edge_local = Dict(t => e for (e, t) in enumerate(active_global_edges))
    active_edges = data.edges[active_global_edges]

    P = length(active_pairs)
    E = length(active_edges)
    pair_edge = [edge_local[full_basis.pair_edge[p]] for p in active_pairs]
    pair_mode = full_basis.pair_mode[active_pairs]
    pair_origin = full_basis.pair_origin[active_pairs]
    pair_destination = full_basis.pair_destination[active_pairs]
    pair_flow = full_basis.pair_flow[active_pairs]
    full_to_active = Dict(p => a for (a, p) in enumerate(active_pairs))

    rows = collect(1:P)
    L = sparse(rows, pair_edge, ones(P), P, E)
    Sagg = sparse(pair_edge, rows,
        [data.s_edges[active_global_edges[pair_edge[p]], pair_mode[p]] for p in 1:P],
        E, P)

    road_active_pairs = Int[]
    road_global_pair = Dict{Tuple{Int,Int},Int}()
    for (r, edge) in enumerate(data.road_edges)
        t = full_basis.edge_index[edge]
        pfull = full_basis.pair_lookup[(t, road_mode)]
        p = full_to_active[pfull]
        push!(road_active_pairs, p)
        road_global_pair[edge] = p
    end

    rail_pairs = findall(==(rail_mode), pair_mode)
    out_nodes = sort!(unique(pair_origin[rail_pairs]))
    in_nodes = sort!(unique(pair_destination[rail_pairs]))
    out_q = Dict(node => length(road_active_pairs) + q for (q, node) in enumerate(out_nodes))
    in_q = Dict(node => length(road_active_pairs) + length(out_nodes) + q
                for (q, node) in enumerate(in_nodes))
    Q = length(road_active_pairs) + length(out_nodes) + length(in_nodes)

    arows = Int[]; acols = Int[]; avals = Float64[]
    road_q_for_pair = Dict{Int,Int}()
    for (q, p) in enumerate(road_active_pairs)
        push!(arows, q); push!(acols, p); push!(avals, 1.0)
        road_q_for_pair[p] = q
    end
    out_totals = Dict(node => sum(pair_flow[p] for p in rail_pairs if pair_origin[p] == node)
                      for node in out_nodes)
    in_totals = Dict(node => sum(pair_flow[p] for p in rail_pairs if pair_destination[p] == node)
                     for node in in_nodes)
    for p in rail_pairs
        i, j = pair_origin[p], pair_destination[p]
        push!(arows, out_q[i]); push!(acols, p); push!(avals, pair_flow[p] / out_totals[i])
        push!(arows, in_q[j]); push!(acols, p); push!(avals, pair_flow[p] / in_totals[j])
    end
    A = sparse(arows, acols, avals, Q, P)

    return (;
        P, E, Q, active_pairs, active_global_edges, active_edges, edge_local,
        pair_edge, pair_mode, pair_origin, pair_destination, pair_flow,
        road_mode, rail_mode, rail_pairs, road_active_pairs, road_global_pair,
        out_nodes, in_nodes, out_q, in_q, road_q_for_pair,
        L, Sagg, A,
    )
end

"""
Precompute soft- and fixed-route edge operators on all road/rail edges.

The fixed-route matrix uses products of baseline expected OD edge counts. The
soft-route matrix uses the derivative of the route resolvent. Both are converted
from transition elasticities to cost elasticities by multiplying by 1-sigma.
"""
function build_complete_route_basis(data; alpha::Real=0.10, beta::Real=-0.30,
                                    sigma::Real=9.0)
    c = coefs(alpha, beta, sigma)
    full_basis = build_pair_basis(data)
    rb = active_edge_and_pair_basis(data, full_basis)
    route = reconstruct_route_kernel(data.mu, data.sx, data.nu, data.Xi)

    N = data.N
    S, D, dlogY = bilateral_state_rows(N, c)
    dlogY[1:N] .= data.nu
    dlogY[N+1:2N] .= data.nu
    soft = soft_route_operators(
        route, rb.active_edges, data.nu, data.sx, S, D, dlogY, sigma)
    fixed = fixed_route_operators(
        route, rb.active_edges, route.Xod, S, D, dlogY, sigma)
    Vz = inverse_state_map(N, data.omega, c)
    Qz_soft = soft.Qz * Vz
    Qz_fixed = fixed.Qz * Vz
    accepted_Qz = response_rows(N, rb.active_edges, data.omega, data.nu, c)
    soft_state_error = maximum(abs.(Qz_soft .- accepted_Qz))

    edge_target = [data.Xi[i, j] for (i, j) in rb.active_edges]
    fixed_edge_relative_error = maximum(abs.(fixed.edge_traffic .- edge_target) ./
                                        max.(abs.(edge_target), 1e-15))
    soft_edge_relative_error = maximum(abs.(soft.edge_traffic .- edge_target) ./
                                       max.(abs.(edge_target), 1e-15))
    fixed_edge_relative_error < ROUTE_TOL ||
        error("fixed route traffic reconstruction failed: $fixed_edge_relative_error")
    soft_edge_relative_error < ROUTE_TOL ||
        error("soft route traffic reconstruction failed: $soft_edge_relative_error")

    return merge(rb, (;
        sigma=Float64(sigma), route,
        Croute_soft=(1 - sigma) .* soft.C,
        Croute_fixed=(1 - sigma) .* fixed.C,
        Qz_soft, Qz_fixed,
        fixed_source_weights=fixed.source_weights,
        fixed_destination_weights=fixed.destination_weights,
        diagnostics=(;
            route.diagnostics...,
            soft_state_error,
            fixed_edge_relative_error,
            soft_edge_relative_error,
            fixed_source_weight_error=fixed.source_weight_error,
            fixed_destination_weight_error=fixed.destination_weight_error,
        ),
    ))
end

"""Closure-specific edge-traffic response to the current spatial state."""
function route_state_matrix(data, rb, c::Coef; route::Symbol=:soft)
    N = data.N
    S, D, dlogY = bilateral_state_rows(N, c)
    dlogY[1:N] .= data.nu
    dlogY[N+1:2N] .= data.nu
    dense = if route == :fixed
        rb.fixed_source_weights * S + rb.fixed_destination_weights * D .-
            permutedims(dlogY)
    elseif route == :soft
        T = rb.route.T
        P = vec(permutedims(data.nu) * T)
        Q = T * data.sx
        Pz = zeros(N, 2N+1)
        Qz = zeros(N, 2N+1)
        for k in 1:N
            Pz[k, :] .= vec(permutedims(data.nu .* T[:, k] ./ P[k]) * S)
            Qz[k, :] .= vec(permutedims(T[k, :] .* data.sx ./ Q[k]) * D)
        end
        Pz[first.(rb.active_edges), :] + Qz[last.(rb.active_edges), :] .-
            permutedims(dlogY)
    else
        error("unknown route closure: $route")
    end
    return dense * inverse_state_map(N, data.omega, c)
end

function congestion_cost_map(rb; lambda_road::Real, lambda_terminal::Real,
                             road::Bool=true, terminal::Bool=true)
    rows = Int[]; cols = Int[]; vals = Float64[]
    if road && lambda_road != 0
        for p in rb.road_active_pairs
            push!(rows, p); push!(cols, rb.road_q_for_pair[p]); push!(vals, Float64(lambda_road))
        end
    end
    if terminal && lambda_terminal != 0
        for p in rb.rail_pairs
            push!(rows, p); push!(cols, rb.out_q[rb.pair_origin[p]])
            push!(vals, Float64(lambda_terminal))
            push!(rows, p); push!(cols, rb.in_q[rb.pair_destination[p]])
            push!(vals, Float64(lambda_terminal))
        end
    end
    return sparse(rows, cols, vals, rb.P, rb.Q)
end

function pair_response_matrices(rb, G::AbstractMatrix;
                                route::Symbol=:soft,
                                modal::Symbol=:flexible,
                                eta::Real=1.099)
    Croute = route == :soft ? rb.Croute_soft :
             route == :fixed ? rb.Croute_fixed :
             error("unknown route closure: $route")
    Qz_edge = route == :soft ? rb.Qz_soft : rb.Qz_fixed
    Kedge = rb.Sagg * G
    Xq = rb.L * (Croute * Kedge)
    if modal == :flexible
        Xq .+= eta .* (G .- rb.L * Kedge)
    elseif modal != :fixed
        error("unknown modal closure: $modal")
    end
    Xz = rb.L * Qz_edge
    return (; Croute, Qz_edge, Kedge, Xq, Xz)
end

function build_transport_closure(data, rb, B::AbstractMatrix;
                                 route::Symbol=:soft,
                                 modal::Symbol=:flexible,
                                 eta::Real=1.099,
                                 lambda_road::Real=0.092,
                                 lambda_terminal::Real=0.096,
                                 road::Bool=true,
                                 terminal::Bool=true,
                                 diagnostics::Bool=true)
    G = congestion_cost_map(rb; lambda_road, lambda_terminal, road, terminal)
    response = pair_response_matrices(rb, G; route, modal, eta)
    AC = rb.A * response.Xq
    H = Matrix{Float64}(I, rb.Q, rb.Q) .- Matrix(AC)
    factor = lu(H; check=true)
    AQz = rb.A * response.Xz
    quantity_state = factor \ Matrix(AQz)
    edge_cost_state = rb.Sagg * (G * quantity_state)
    Jc = B * edge_cost_state
    BG = B * (rb.Sagg * G)
    left = diagnostics ? permutedims(permutedims(H) \ permutedims(BG)) : nothing
    solve_residual = norm(H * quantity_state - AQz, Inf) /
        max(norm(AQz, Inf), eps(Float64))
    condition = diagnostics ? cond(H) : NaN
    return (;
        route, modal, road, terminal, G, H, factor, AQz, quantity_state,
        edge_cost_state, Jc, left, solve_residual, condition,
        response...,
    )
end

"""Build NC, NT, F, FM, and FR in the common route-modal-terminal basis."""
function build_complete_closures(data, rb;
                                 alpha::Real=0.10, beta::Real=-0.30,
                                 eta::Real=1.099,
                                 lambda_road::Real=0.092,
                                 lambda_terminal::Real=0.096,
                                 diagnostics::Bool=true)
    c = coefs(alpha, beta, rb.sigma)
    rb_point = merge(rb, (;
        Qz_soft=route_state_matrix(data, rb, c; route=:soft),
        Qz_fixed=route_state_matrix(data, rb, c; route=:fixed),
    ))
    J0 = assemble_J(data.sx, data.sy, data.mu, data.lam, data.omega, c)
    B = cost_loading_matrix(data.N, rb_point.active_edges, data.mu, data.lam, c.σ)
    NC_transport = build_transport_closure(
        data, rb_point, B; eta, lambda_road, lambda_terminal,
        road=false, terminal=false, diagnostics)
    NT_transport = build_transport_closure(
        data, rb_point, B; eta, lambda_road, lambda_terminal,
        road=true, terminal=false, diagnostics)
    F_transport = build_transport_closure(
        data, rb_point, B; eta, lambda_road, lambda_terminal,
        road=true, terminal=true, diagnostics)
    FM_transport = build_transport_closure(
        data, rb_point, B; modal=:fixed, eta, lambda_road, lambda_terminal,
        road=true, terminal=true, diagnostics)
    FR_transport = build_transport_closure(
        data, rb_point, B; route=:fixed, eta, lambda_road, lambda_terminal,
        road=true, terminal=true, diagnostics)

    J_NC = J0 + NC_transport.Jc
    J_NT = J0 + NT_transport.Jc
    J_F = J0 + F_transport.Jc
    J_FM = J0 + FM_transport.Jc
    J_FR = J0 + FR_transport.Jc
    parts = jacobian_parts(data.sx, data.sy, data.mu, data.lam, data.omega, c)

    return (;
        c, B, D=parts.sparse, uv=parts.global_feedback, J0,
        NC=J_NC, NT=J_NT, F=J_F, FM=J_FM, FR=J_FR,
        transport=(NC=NC_transport, NT=NT_transport, F=F_transport,
                   FM=FM_transport, FR=FR_transport),
        road_block=J_NT-J_NC,
        terminal_block=J_F-J_NT,
        mode_core=J_FM-J_F,
        route_core=J_FR-J_F,
        structured=diagnostics ? (
            road=(U=NT_transport.left, V=NT_transport.AQz),
            terminal=(U=F_transport.left-NT_transport.left, V=F_transport.AQz),
        ) : nothing,
        conditions=diagnostics ? (NC=cond(J_NC), NT=cond(J_NT), F=cond(J_F),
                                  FM=cond(J_FM), FR=cond(J_FR)) :
                                 (NC=NaN, NT=NaN, F=NaN, FM=NaN, FR=NaN),
    )
end

function evaluate_complete_sensitivity_point(data, rb;
                                             alpha::Real=0.10,
                                             beta::Real=-0.30,
                                             eta::Real=1.099,
                                             lambda_road::Real=0.092,
                                             lambda_terminal::Real=0.096,
                                             require_net_dispersion::Bool=true,
                                             require_negative_e::Bool=true,
                                             regularity_margin::Real=0.05)
    alpha + beta < 0 || !require_net_dispersion ||
        error("parameter point is not net dispersive")
    c = coefs(alpha, beta, rb.sigma)
    c.e < 0 || !require_negative_e || error("parameter point leaves e<0 branch")
    abs(c.e) >= regularity_margin || error("parameter point is too close to e=0")
    1 + alpha + beta > regularity_margin ||
        error("parameter point is too close to 1+alpha+beta=0")

    rb_point = merge(rb, (; Qz_soft=route_state_matrix(data, rb, c; route=:soft)))
    J0 = assemble_J(data.sx, data.sy, data.mu, data.lam, data.omega, c)
    B = cost_loading_matrix(data.N, rb.active_edges, data.mu, data.lam, c.σ)
    transport = build_transport_closure(
        data, rb_point, B; route=:soft, modal=:flexible, eta,
        lambda_road, lambda_terminal, road=true, terminal=true,
        diagnostics=false)
    J = J0 + transport.Jc
    factor_Jt = lu(permutedims(J); check=true)
    q = welfare_gradient(data.omega, c)
    adjoint = factor_Jt \ q
    solve_residual = norm(permutedims(J)*adjoint-q, Inf) / max(norm(q, Inf), eps())
    rcond_J = LinearAlgebra.LAPACK.gecon!('I', factor_Jt.factors, opnorm(J, Inf))
    rcond_H = LinearAlgebra.LAPACK.gecon!('I', transport.factor.factors, opnorm(transport.H, Inf))

    selector = sparsevec(rb.road_active_pairs,
        fill(1/length(rb.road_active_pairs), length(rb.road_active_pairs)), rb.P)
    kedge = rb.Sagg * selector
    xdirect = rb.L * (transport.Croute * kedge) +
        eta .* (selector - rb.L*kedge)
    qdirect = rb.A * xdirect
    qresponse = transport.factor \ qdirect
    aggregate_cost = rb.Sagg * (selector + transport.G*qresponse)
    forcing = B * aggregate_cost
    mean_directed = dot(adjoint, forcing)
    transport_residual = norm(transport.H*qresponse-qdirect, Inf) /
        max(norm(qdirect, Inf), eps())

    return (;
        alpha=Float64(alpha), beta=Float64(beta),
        net_dispersion=Float64(-(alpha+beta)), eta=Float64(eta),
        lambda_road=Float64(lambda_road), lambda_terminal=Float64(lambda_terminal),
        e=c.e, rho=c.ρ, rcond_J, rcond_H, solve_residual, transport_residual,
        mean_directed_elasticity=mean_directed,
        mean_physical_elasticity=2mean_directed,
        mean_directed_gain_pct_1pct=mean_directed,
        mean_physical_gain_pct_1pct=2mean_directed,
    )
end

"""Exact inverse-gap term q' JA^-1 (JB-JA) JB^-1 b."""
function structured_inverse_gap(JA::AbstractMatrix, JB::AbstractMatrix,
                                q::AbstractVector, b::AbstractVector)
    return dot(permutedims(JA) \ q, (JB-JA) * (JB \ b))
end

"""Structured parallel-sum gap for JB=JA+U*V."""
function structured_parallel_gap(JA::AbstractMatrix, U::AbstractMatrix,
                                 V::AbstractMatrix, q::AbstractVector,
                                 b::AbstractVector)
    adjoint = permutedims(JA) \ q
    response = JA \ b
    middle = Matrix{Float64}(I, size(V, 1), size(V, 1)) + V * (JA \ U)
    return dot(adjoint, U * (middle \ (V * response)))
end

function structured_parallel_gaps(JA::AbstractMatrix, U::AbstractMatrix,
                                  V::AbstractMatrix, q::AbstractVector,
                                  forcing::AbstractMatrix)
    factor = lu(JA)
    adjoint = permutedims(JA) \ q
    response = factor \ forcing
    middle = Matrix{Float64}(I, size(V, 1), size(V, 1)) + V * (factor \ U)
    correction = U * (middle \ (V * response))
    return vec(permutedims(adjoint) * correction)
end

"""Primitive road forcing after route, mode, road, and terminal pass-through."""
function primitive_road_forcing(rb, closure, B::AbstractMatrix, eta::Real)
    R = length(rb.road_active_pairs)
    selectors = sparse(rb.road_active_pairs, collect(1:R), ones(R), rb.P, R)
    Kedge = rb.Sagg * selectors
    Xdirect = rb.L * (closure.Croute * Kedge)
    if closure.modal == :flexible
        Xdirect .+= eta .* (selectors .- rb.L * Kedge)
    end
    qdirect = rb.A * Xdirect
    qresponse = closure.factor \ Matrix(qdirect)
    realized_pair_cost = selectors + closure.G * qresponse
    aggregate_cost = rb.Sagg * realized_pair_cost
    forcing = B * aggregate_cost
    residual = norm(closure.H * qresponse - qdirect, Inf) /
        max(norm(qdirect, Inf), eps(Float64))
    return (; selectors, aggregate_cost, forcing, qresponse, residual)
end

function complete_road_decomposition(data, rb, closures; eta::Real=1.099)
    c = closures.c
    q = welfare_gradient(data.omega, c)
    names = (:NC, :NT, :F, :FM, :FR)
    adj = Dict(name => permutedims(getproperty(closures, name)) \ q for name in names)

    realized_forcing = closures.B * (rb.Sagg[:, rb.road_active_pairs])
    primitive = primitive_road_forcing(rb, closures.transport.F, closures.B, eta)
    E = Dict(name => vec(permutedims(adj[name]) * realized_forcing) for name in names)
    Etheta = vec(permutedims(adj[:F]) * primitive.forcing)
    road_parallel_values = structured_parallel_gaps(
        closures.NC, closures.structured.road.U, closures.structured.road.V,
        q, realized_forcing)
    terminal_parallel_values = structured_parallel_gaps(
        closures.NT, closures.structured.terminal.U, closures.structured.terminal.V,
        q, realized_forcing)

    rows = NamedTuple[]
    for r in eachindex(data.road_edges)
        k, l = data.road_edges[r]
        Xi = data.road[k, l]
        values = Dict(name => E[name][r] for name in names)
        m = Dict(name => values[name] / (c.ρ * Xi) for name in names)
        mNC, mNT, mF, mFM, mFR = (m[name] for name in names)
        d_road = mNC - mNT
        d_terminal = mNT - mF
        d_mode = mF - mFM
        d_route = mF - mFR
        chi_effective = Etheta[r] / values[:F]

        b = realized_forcing[:, r]
        id_road = (values[:NC] - values[:NT]) -
            structured_inverse_gap(closures.NC, closures.NT, q, b)
        id_terminal = (values[:NT] - values[:F]) -
            structured_inverse_gap(closures.NT, closures.F, q, b)
        id_mode = (values[:F] - values[:FM]) -
            structured_inverse_gap(closures.F, closures.FM, q, b)
        id_route = (values[:F] - values[:FR]) -
            structured_inverse_gap(closures.F, closures.FR, q, b)
        parallel_road = road_parallel_values[r]
        parallel_terminal = terminal_parallel_values[r]

        mode_scarcity = structured_inverse_gap(closures.F, closures.FM, q, b) /
            (c.ρ * Xi)
        route_scarcity = structured_inverse_gap(closures.F, closures.FR, q, b) /
            (c.ρ * Xi)

        hulten_realized_gap = Xi - values[:F]
        hulten_externality = Xi * (1 - c.ρ)
        hulten_attenuation = c.ρ * Xi * (1 - mF)
        primitive_gap = Xi - Etheta[r]
        primitive_externality = hulten_externality
        primitive_propagation = c.ρ * Xi * (1 - mNC)
        primitive_road = c.ρ * Xi * d_road
        primitive_terminal = c.ρ * Xi * d_terminal
        primitive_pass_through = c.ρ * Xi * mF * (1 - chi_effective)

        push!(rows, (;
            k, l, hulten=Xi,
            realized_NC=values[:NC], realized_NT=values[:NT],
            realized_F=values[:F], realized_FM=values[:FM], realized_FR=values[:FR],
            primitive_F=Etheta[r], chi_effective,
            m_NC=mNC, m_NT=mNT, m_F=mF, m_FM=mFM, m_FR=mFR,
            d_road, d_terminal, d_mode, d_route,
            road_allocation=0.0, road_scarcity=d_road, road_equilibrium=0.0,
            terminal_allocation=0.0, terminal_scarcity=d_terminal, terminal_equilibrium=0.0,
            mode_allocation=0.0, mode_scarcity, mode_equilibrium=0.0,
            route_allocation=0.0, route_scarcity, route_equilibrium=0.0,
            hulten_realized_gap, hulten_externality, hulten_attenuation,
            primitive_gap, primitive_externality, primitive_propagation,
            primitive_road, primitive_terminal, primitive_pass_through,
            identity_residual_road=id_road,
            identity_residual_terminal=id_terminal,
            identity_residual_mode=id_mode,
            identity_residual_route=id_route,
            parallel_residual_road=(values[:NC]-values[:NT])-parallel_road,
            parallel_residual_terminal=(values[:NT]-values[:F])-parallel_terminal,
            channel_residual_mode=d_mode-mode_scarcity,
            channel_residual_route=d_route-route_scarcity,
        ))
    end
    return rows, primitive
end

function aggregate_complete_links(rows::Vector{<:NamedTuple}, rho::Real)
    grouped = Dict{Tuple{Int,Int},Vector{NamedTuple}}()
    for row in rows
        push!(get!(grouped, minmax(row.k, row.l), NamedTuple[]), row)
    end
    out = NamedTuple[]
    additive = (
        :hulten, :realized_NC, :realized_NT, :realized_F, :realized_FM, :realized_FR,
        :primitive_F, :hulten_realized_gap, :hulten_externality, :hulten_attenuation,
        :primitive_gap, :primitive_externality, :primitive_propagation,
        :primitive_road, :primitive_terminal, :primitive_pass_through,
        :identity_residual_road, :identity_residual_terminal,
        :identity_residual_mode, :identity_residual_route,
        :parallel_residual_road, :parallel_residual_terminal,
    )
    for key in sort!(collect(keys(grouped)))
        group = grouped[key]
        length(group) == 2 || error("physical link $key does not have two directions")
        sums = Dict(name => sum(getproperty(row, name) for row in group) for name in additive)
        h = sums[:hulten]
        mNC = sums[:realized_NC] / (rho*h)
        mNT = sums[:realized_NT] / (rho*h)
        mF = sums[:realized_F] / (rho*h)
        mFM = sums[:realized_FM] / (rho*h)
        mFR = sums[:realized_FR] / (rho*h)
        d_road, d_terminal = mNC-mNT, mNT-mF
        d_mode, d_route = mF-mFM, mF-mFR
        push!(out, (;
            k=key[1], l=key[2], directions=2,
            (name => sums[name] for name in additive)...,
            chi_effective=sums[:primitive_F]/sums[:realized_F],
            m_NC=mNC, m_NT=mNT, m_F=mF, m_FM=mFM, m_FR=mFR,
            d_road, d_terminal, d_mode, d_route,
            road_allocation=0.0, road_scarcity=d_road, road_equilibrium=0.0,
            terminal_allocation=0.0, terminal_scarcity=d_terminal, terminal_equilibrium=0.0,
            mode_allocation=0.0, mode_scarcity=d_mode, mode_equilibrium=0.0,
            route_allocation=0.0, route_scarcity=d_route, route_equilibrium=0.0,
        ))
    end
    return out
end

end # module
