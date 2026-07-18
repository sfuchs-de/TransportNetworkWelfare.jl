"""Exact local linearization with edge congestion and endpoint terminal congestion."""
module RSUETerminalCongestion

using LinearAlgebra
using SparseArrays
using Statistics

using ..AdjointRSUE
using ..IFTDecomposition: response_rows, cost_loading_matrix

export build_pair_basis, build_transport_linearization
export direct_road_response, evaluate_terminal_model

"""Index the positive-flow edge-mode pairs used by the modal congestion system."""
function build_pair_basis(data)
    E = length(data.edges)
    M = length(data.modes)
    N = data.N
    edge_index = Dict(edge => t for (t, edge) in enumerate(data.edges))
    mode_index = Dict(mode => m for (m, mode) in enumerate(data.modes))

    pair_edge = Int[]
    pair_mode = Int[]
    pair_origin = Int[]
    pair_destination = Int[]
    pair_flow = Float64[]
    pair_lookup = Dict{Tuple{Int,Int},Int}()
    edge_pairs = [Int[] for _ in 1:E]
    outgoing = [[Int[] for _ in 1:N] for _ in 1:M]
    incoming = [[Int[] for _ in 1:N] for _ in 1:M]

    for (t, (i, j)) in enumerate(data.edges), m in 1:M
        flow = Float64(data.mode_flows[m][i, j])
        flow > 0 || continue
        push!(pair_edge, t)
        push!(pair_mode, m)
        push!(pair_origin, i)
        push!(pair_destination, j)
        push!(pair_flow, flow)
        p = length(pair_edge)
        pair_lookup[(t, m)] = p
        push!(edge_pairs[t], p)
        push!(outgoing[m][i], p)
        push!(incoming[m][j], p)
    end

    P = length(pair_edge)
    road_mode = get(mode_index, :road, 0)
    road_mode > 0 || error("the active mode set has no :road mode")
    road_pairs = Int[]
    for edge in data.road_edges
        t = edge_index[edge]
        p = get(pair_lookup, (t, road_mode), 0)
        p > 0 || error("road edge $edge has no active road pair")
        push!(road_pairs, p)
    end

    out_totals = zeros(M, N)
    in_totals = zeros(M, N)
    for p in 1:P
        m = pair_mode[p]
        out_totals[m, pair_origin[p]] += pair_flow[p]
        in_totals[m, pair_destination[p]] += pair_flow[p]
    end

    return (;
        N, E, M, P,
        edge_index,
        mode_index,
        pair_edge,
        pair_mode,
        pair_origin,
        pair_destination,
        pair_flow,
        pair_lookup,
        edge_pairs,
        outgoing,
        incoming,
        out_totals,
        in_totals,
        road_mode,
        road_pairs,
    )
end

function modal_traffic_matrix(data, basis, sigma::Real, eta::Real)
    rows = Int[]
    cols = Int[]
    vals = Float64[]
    aggregate_coefficient = 1 - sigma - eta
    for t in 1:basis.E
        pairs = basis.edge_pairs[t]
        for p in pairs, q in pairs
            value = aggregate_coefficient * data.s_edges[t, basis.pair_mode[q]]
            p == q && (value += eta)
            value == 0 && continue
            push!(rows, p)
            push!(cols, q)
            push!(vals, value)
        end
    end
    return sparse(rows, cols, vals, basis.P, basis.P)
end

function aggregate_cost_matrix(data, basis)
    rows = Int[]
    cols = Int[]
    vals = Float64[]
    for p in 1:basis.P
        t = basis.pair_edge[p]
        m = basis.pair_mode[p]
        share = data.s_edges[t, m]
        share > 0 || error("active pair has a nonpositive modal share")
        push!(rows, t)
        push!(cols, p)
        push!(vals, share)
    end
    return sparse(rows, cols, vals, basis.E, basis.P)
end

function congestion_map(data, basis;
                        lambda_road::Real,
                        lambda_terminal::Real,
                        lambda_port_edge::Real,
                        terminal_modes,
                        terminal_endpoint_scale::Real,
                        port_mode::Symbol)
    lambda_road >= 0 || error("lambda_road must be nonnegative")
    lambda_terminal >= 0 || error("lambda_terminal must be nonnegative")
    lambda_port_edge >= 0 || error("lambda_port_edge must be nonnegative")
    terminal_endpoint_scale >= 0 || error("terminal_endpoint_scale must be nonnegative")

    terminal_mode_indices = Int[]
    for mode in terminal_modes
        m = get(basis.mode_index, mode, 0)
        m > 0 || error("unknown terminal mode: $mode")
        push!(terminal_mode_indices, m)
    end
    terminal_mode_set = Set(terminal_mode_indices)
    port_mode_index = get(basis.mode_index, port_mode, 0)

    rows = Int[]
    cols = Int[]
    vals = Float64[]
    for p in 1:basis.P
        m = basis.pair_mode[p]
        i = basis.pair_origin[p]
        j = basis.pair_destination[p]

        if m == basis.road_mode && lambda_road > 0
            push!(rows, p); push!(cols, p); push!(vals, Float64(lambda_road))
        end
        if m == port_mode_index && lambda_port_edge > 0
            push!(rows, p); push!(cols, p); push!(vals, Float64(lambda_port_edge))
        end
        if m in terminal_mode_set && lambda_terminal > 0
            endpoint_lambda = Float64(lambda_terminal * terminal_endpoint_scale)
            out_total = basis.out_totals[m, i]
            in_total = basis.in_totals[m, j]
            out_total > 0 || error("active terminal pair has zero origin-mode traffic")
            in_total > 0 || error("active terminal pair has zero destination-mode traffic")
            for q in basis.outgoing[m][i]
                push!(rows, p)
                push!(cols, q)
                push!(vals, endpoint_lambda * basis.pair_flow[q] / out_total)
            end
            for q in basis.incoming[m][j]
                push!(rows, p)
                push!(cols, q)
                push!(vals, endpoint_lambda * basis.pair_flow[q] / in_total)
            end
        end
    end
    Gamma = sparse(rows, cols, vals, basis.P, basis.P)
    terminal_nodes = sort!(unique(vcat(
        [i for m in terminal_mode_indices for i in 1:basis.N if !isempty(basis.outgoing[m][i])],
        [i for m in terminal_mode_indices for i in 1:basis.N if !isempty(basis.incoming[m][i])],
    )))
    terminal_pairs = count(m -> m in terminal_mode_set, basis.pair_mode)
    port_pairs = port_mode_index == 0 ? 0 : count(==(port_mode_index), basis.pair_mode)
    return Gamma, terminal_mode_indices, terminal_nodes, terminal_pairs, port_pairs
end

function factor_pivot_ratio(factor)
    pivots = abs.(diag(factor.U))
    isempty(pivots) && return NaN
    maximum(pivots) == 0 && return 0.0
    return minimum(pivots) / maximum(pivots)
end

"""
Build the modal/terminal linearization while holding the observed allocation fixed.

For active pair `p=(e,m)`, modal traffic satisfies `x = Rz + Ca`. Congestion
satisfies `a = delta + Gamma*x`, so `H = I - Gamma*C`. Road congestion is
edge-specific. Terminal congestion depends on total traffic in a terminal mode
at both endpoints. `lambda_port_edge` is kept separate and is zero by default.
"""
function build_transport_linearization(data;
                                       basis=build_pair_basis(data),
                                       sigma::Real=9.0,
                                       eta::Real=1.099,
                                       lambda_road::Real=0.092,
                                       lambda_terminal::Real=0.096,
                                       lambda_port_edge::Real=0.0,
                                       terminal_modes=(:rail,),
                                       terminal_endpoint_scale::Real=1.0,
                                       port_mode::Symbol=:water_for)
    eta > 0 || error("eta must be positive")
    C = modal_traffic_matrix(data, basis, sigma, eta)
    Sagg = aggregate_cost_matrix(data, basis)
    Gamma, terminal_mode_indices, terminal_nodes, terminal_pairs, port_pairs = congestion_map(
        data, basis;
        lambda_road,
        lambda_terminal,
        lambda_port_edge,
        terminal_modes,
        terminal_endpoint_scale,
        port_mode,
    )
    H = spdiagm(0 => ones(basis.P)) - Gamma * C
    factor = lu(H; check=true)

    selector_mean = sparsevec(
        basis.road_pairs,
        fill(1 / length(basis.road_pairs), length(basis.road_pairs)),
        basis.P,
    )
    pair_direct_mean = factor \ Vector(selector_mean)
    aggregate_direct_mean = Sagg * pair_direct_mean
    rhs_norm = max(norm(selector_mean, Inf), eps(Float64))
    direct_solve_residual = norm(H * pair_direct_mean - selector_mean, Inf) / rhs_norm

    return (;
        basis,
        sigma=Float64(sigma),
        eta=Float64(eta),
        lambda_road=Float64(lambda_road),
        lambda_terminal=Float64(lambda_terminal),
        lambda_port_edge=Float64(lambda_port_edge),
        terminal_modes=Tuple(terminal_modes),
        terminal_mode_indices,
        terminal_endpoint_scale=Float64(terminal_endpoint_scale),
        terminal_nodes,
        terminal_pairs,
        port_pairs,
        C,
        Sagg,
        Gamma,
        H,
        factor,
        pair_direct_mean,
        aggregate_direct_mean,
        direct_solve_residual,
        pivot_ratio=factor_pivot_ratio(factor),
    )
end

"""Return pair-level and aggregate-cost responses to all primitive road shocks."""
function direct_road_response(transport)
    basis = transport.basis
    selectors = sparse(
        basis.road_pairs,
        collect(1:length(basis.road_pairs)),
        ones(length(basis.road_pairs)),
        basis.P,
        length(basis.road_pairs),
    )
    pair = transport.factor \ Matrix(selectors)
    aggregate = transport.Sagg * pair
    residual = norm(transport.H * pair - selectors, Inf) /
        max(norm(selectors, Inf), eps(Float64))
    return (; pair, aggregate, residual)
end

"""Evaluate the corrected welfare derivative with the endpoint-terminal operator."""
function evaluate_terminal_model(data, transport;
                                 alpha::Real=0.10,
                                 beta::Real=-0.30,
                                 require_net_dispersion::Bool=true,
                                 require_negative_e::Bool=true,
                                 regularity_margin::Real=0.05,
                                 rcond_floor::Real=1e-12,
                                 full_road_results::Bool=false)
    alpha + beta < 0 || !require_net_dispersion ||
        error("parameter point is not net dispersive: alpha + beta >= 0")
    c = coefs(alpha, beta, transport.sigma)
    c.e < 0 || !require_negative_e ||
        error("parameter point leaves the baseline e < 0 branch")
    abs(c.e) >= regularity_margin || error("parameter point is too close to e = 0")
    1 + alpha + beta > regularity_margin ||
        error("parameter point is too close to 1 + alpha + beta = 0")

    basis = transport.basis
    R_edge = response_rows(data.N, data.edges, data.omega, data.nu, c)
    R_pair = R_edge[basis.pair_edge, :]
    state_rhs = transport.Gamma * R_pair
    pair_state = transport.factor \ state_rhs
    aggregate_state = transport.Sagg * pair_state
    state_solve_residual = norm(transport.H * pair_state - state_rhs, Inf) /
        max(norm(state_rhs, Inf), eps(Float64))

    B = cost_loading_matrix(data.N, data.edges, data.mu, data.lam, c.σ)
    J_congestion = B * aggregate_state
    J = assemble_J(data.sx, data.sy, data.mu, data.lam, data.omega, c) .+ J_congestion
    Jt = permutedims(J)
    factor_Jt = lu(Jt; check=true)
    q = welfare_gradient(data.omega, c)
    adjoint = factor_Jt \ q
    solve_residual = norm(Jt * adjoint - q, Inf) / max(norm(q, Inf), eps(Float64))
    rcond_inf = LinearAlgebra.LAPACK.gecon!('I', factor_Jt.factors, opnorm(J, Inf))
    rcond_inf >= rcond_floor || error("equilibrium Jacobian is numerically singular")

    mean_forcing = B * transport.aggregate_direct_mean
    mean_directed = dot(adjoint, mean_forcing)
    edge_elasticities = Float64[]
    direct_residual = transport.direct_solve_residual
    mean_projection_residual = 0.0
    maximum_nonlocal_aggregate_response = NaN
    if full_road_results
        direct = direct_road_response(transport)
        forcing = B * direct.aggregate
        edge_elasticities = vec(permutedims(adjoint) * forcing)
        direct_residual = direct.residual
        mean_projection_residual = abs(mean(edge_elasticities) - mean_directed)

        own_edges = basis.pair_edge[basis.road_pairs]
        max_nonlocal = 0.0
        for column in axes(direct.aggregate, 2), t in axes(direct.aggregate, 1)
            t == own_edges[column] && continue
            max_nonlocal = max(max_nonlocal, abs(direct.aggregate[t, column]))
        end
        maximum_nonlocal_aggregate_response = max_nonlocal
    end

    all(isfinite, (mean_directed, rcond_inf, solve_residual, state_solve_residual)) ||
        error("nonfinite terminal-congestion result")
    return (;
        alpha=Float64(alpha),
        beta=Float64(beta),
        net_dispersion=Float64(-(alpha + beta)),
        sigma=transport.sigma,
        eta=transport.eta,
        lambda_road=transport.lambda_road,
        lambda_terminal=transport.lambda_terminal,
        lambda_port_edge=transport.lambda_port_edge,
        terminal_endpoint_scale=transport.terminal_endpoint_scale,
        e=c.e,
        rho=c.ρ,
        rcond_inf,
        solve_residual,
        transport_direct_solve_residual=direct_residual,
        transport_state_solve_residual=state_solve_residual,
        transport_pivot_ratio=transport.pivot_ratio,
        mean_projection_residual,
        maximum_nonlocal_aggregate_response,
        active_edge_mode_pairs=basis.P,
        road_pairs=length(basis.road_pairs),
        terminal_pairs=transport.terminal_pairs,
        terminal_nodes=length(transport.terminal_nodes),
        port_pairs=transport.port_pairs,
        mean_directed_elasticity=mean_directed,
        mean_physical_elasticity=2 * mean_directed,
        mean_directed_gain_pct_1pct=mean_directed,
        mean_physical_gain_pct_1pct=2 * mean_directed,
        minimum_directed_elasticity=isempty(edge_elasticities) ? NaN : minimum(edge_elasticities),
        maximum_directed_elasticity=isempty(edge_elasticities) ? NaN : maximum(edge_elasticities),
        negative_directed_elasticities=isempty(edge_elasticities) ? -1 :
            count(value -> value < 0, edge_elasticities),
        edge_elasticities,
        J,
        J_congestion,
    )
end

end # module
