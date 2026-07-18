"""Parameter-curvature calculations for the corrected local RSUE estimator."""
module RSUEParameterSensitivity

using LinearAlgebra
using Statistics

using ..AdjointRSUE
using ..IFTDecomposition: edge_shock
using ..RSUETerminalCongestion

export evaluate_sensitivity_point, evaluate_terminal_sensitivity_point

function modal_regularities(data, gamma::AbstractVector, eta::Real, sigma::Real)
    min_D = minimum(abs.(1 .- eta .* gamma))
    min_outer = Inf
    for t in axes(data.s_edges, 1)
        shares = @view data.s_edges[t, :]
        D = 1 .- eta .* gamma
        outer = 1 - (1 - sigma - eta) * sum(shares .* gamma ./ D)
        min_outer = min(min_outer, abs(outer))
    end
    return min_D, min_outer
end

function physical_sums(edges, edge_values)
    grouped = Dict{Tuple{Int,Int},Float64}()
    counts = Dict{Tuple{Int,Int},Int}()
    for (edge, value) in zip(edges, edge_values)
        key = minmax(edge...)
        grouped[key] = get(grouped, key, 0.0) + value
        counts[key] = get(counts, key, 0) + 1
    end
    length(grouped) == 352 || error("expected 352 physical road links")
    all(==(2), values(counts)) || error("a physical link is missing one direction")
    return [grouped[key] for key in sort!(collect(keys(grouped)))]
end

"""
Evaluate one parameter vector while holding observed traffic and allocation
shares fixed. The returned 1-percent gains are local first-order translations,
not re-solved finite counterfactuals.
"""
function evaluate_sensitivity_point(data;
                                    alpha::Real=0.10,
                                    beta::Real=-0.30,
                                    sigma::Real=9.0,
                                    eta::Real=1.099,
                                    lambda_road::Real=0.092,
                                    lambda_terminal::Real=0.096,
                                    shock_fraction::Real=0.01,
                                    require_net_dispersion::Bool=true,
                                    require_negative_e::Bool=true,
                                    regularity_margin::Real=0.05,
                                    rcond_floor::Real=1e-12)
    0 < shock_fraction < 1 || error("shock_fraction must lie in (0,1)")
    alpha + beta < 0 || !require_net_dispersion ||
        error("parameter point is not net dispersive: alpha + beta >= 0")

    c = coefs(alpha, beta, sigma)
    c.e < 0 || !require_negative_e ||
        error("parameter point leaves the baseline e < 0 branch")
    abs(c.e) >= regularity_margin ||
        error("parameter point is too close to e = 0")
    1 + alpha + beta > regularity_margin ||
        error("parameter point is too close to 1 + alpha + beta = 0")

    gamma = [Float64(lambda_road), 0.0, 0.0, Float64(lambda_terminal)]
    min_modal_D, min_modal_outer = modal_regularities(data, gamma, eta, sigma)
    min_modal_D >= regularity_margin || error("modal diagonal is near singular")
    min_modal_outer >= regularity_margin || error("modal outer system is near singular")

    J = assemble_J(data.sx, data.sy, data.mu, data.lam, data.omega, c) .+
        congestion_J(
            data.N, data.edges, data.s_edges, data.mu, data.lam,
            data.omega, data.nu, gamma, eta, c)
    Jt = permutedims(J)
    factor = lu(Jt; check=true)
    psi = psi_row(data.omega, sigma)
    ell = factor \ psi
    solve_residual = norm(Jt * ell - psi, Inf) / max(norm(psi, Inf), eps(Float64))
    rcond_inf = LinearAlgebra.LAPACK.gecon!('1', factor.factors, opnorm(J, Inf))
    rcond_inf >= rcond_floor || error("equilibrium Jacobian is numerically singular")

    Lin = .-ell[1:data.N]
    Lout = .-ell[data.N+1:2 * data.N]
    Min = Lin ./ data.Tnode
    Mout = Lout ./ data.Tnode
    adjoint_q = (c.ρ / (sigma - 1)) .* ell

    elasticities = Float64[]
    max_scalar_residual = 0.0
    min_chi = Inf
    max_chi = -Inf
    for (k, l) in data.road_edges
        Xi_mode = data.road[k, l]
        Xi_edge = data.Xi[k, l]
        share = Xi_mode / Xi_edge
        shares = data.s_edges_by_pair[(k, l)]
        chi = chi_wedge(shares, gamma, eta, sigma)[1]
        multiplier = Min[k] + (l == data.N ? 0.0 : Mout[l])
        scalar = chi * c.ρ * Xi_mode * multiplier
        b = edge_shock(data.N, k, l, share, data.mu, data.lam, sigma)
        operator = chi * dot(adjoint_q, b)
        max_scalar_residual = max(max_scalar_residual, abs(scalar - operator))
        push!(elasticities, scalar)
        min_chi = min(min_chi, chi)
        max_chi = max(max_chi, chi)
    end

    all(isfinite, elasticities) || error("nonfinite welfare elasticity")
    physical = physical_sums(data.road_edges, elasticities)
    linear_scale = 100 * shock_fraction
    log_shock = -log1p(-shock_fraction)
    directed_log_gain = 100 .* expm1.(log_shock .* elasticities)
    physical_log_gain = 100 .* expm1.(log_shock .* physical)

    return (;
        alpha=Float64(alpha),
        beta=Float64(beta),
        net_dispersion=Float64(-(alpha + beta)),
        sigma=Float64(sigma),
        eta=Float64(eta),
        lambda_road=Float64(lambda_road),
        lambda_terminal=Float64(lambda_terminal),
        e=c.e,
        rho=c.ρ,
        rcond_inf,
        solve_residual,
        min_modal_D,
        min_modal_outer,
        min_chi,
        max_chi,
        max_scalar_residual,
        directed_arcs=length(elasticities),
        physical_links=length(physical),
        mean_directed_elasticity=mean(elasticities),
        mean_physical_elasticity=mean(physical),
        mean_directed_gain_pct_1pct=linear_scale * mean(elasticities),
        mean_physical_gain_pct_1pct=linear_scale * mean(physical),
        mean_directed_log_translation_pct_1pct=mean(directed_log_gain),
        mean_physical_log_translation_pct_1pct=mean(physical_log_gain),
        minimum_directed_elasticity=minimum(elasticities),
        maximum_directed_elasticity=maximum(elasticities),
        negative_directed_elasticities=count(x -> x < 0, elasticities),
    )
end

"""
Evaluate one point using edge-specific road congestion and endpoint rail-terminal
congestion. The observed allocation is held fixed. The mean is computed from one
average primitive-shock solve, which is exactly equivalent to averaging the 704
individual linear derivatives.
"""
function evaluate_terminal_sensitivity_point(data;
                                             basis=build_pair_basis(data),
                                             transport=nothing,
                                             alpha::Real=0.10,
                                             beta::Real=-0.30,
                                             sigma::Real=9.0,
                                             eta::Real=1.099,
                                             lambda_road::Real=0.092,
                                             lambda_terminal::Real=0.096,
                                             lambda_port_edge::Real=0.0,
                                             terminal_endpoint_scale::Real=1.0,
                                             shock_fraction::Real=0.01,
                                             require_net_dispersion::Bool=true,
                                             require_negative_e::Bool=true,
                                             regularity_margin::Real=0.05,
                                             rcond_floor::Real=1e-12)
    0 < shock_fraction < 1 || error("shock_fraction must lie in (0,1)")
    if transport === nothing
        transport = build_transport_linearization(
            data;
            basis,
            sigma,
            eta,
            lambda_road,
            lambda_terminal,
            lambda_port_edge,
            terminal_endpoint_scale,
        )
    else
        transport.sigma == sigma || error("transport sigma does not match requested sigma")
        transport.eta == eta || error("transport eta does not match requested eta")
        transport.lambda_road == lambda_road ||
            error("transport road lambda does not match requested lambda")
        transport.lambda_terminal == lambda_terminal ||
            error("transport terminal lambda does not match requested lambda")
        transport.lambda_port_edge == lambda_port_edge ||
            error("transport port-edge lambda does not match requested lambda")
        transport.terminal_endpoint_scale == terminal_endpoint_scale ||
            error("transport endpoint scale does not match requested scale")
    end

    result = evaluate_terminal_model(
        data,
        transport;
        alpha,
        beta,
        require_net_dispersion,
        require_negative_e,
        regularity_margin,
        rcond_floor,
    )
    linear_scale = 100 * shock_fraction
    return (;
        result.alpha,
        result.beta,
        result.net_dispersion,
        result.sigma,
        result.eta,
        result.lambda_road,
        result.lambda_terminal,
        result.lambda_port_edge,
        result.terminal_endpoint_scale,
        result.e,
        result.rho,
        result.rcond_inf,
        result.solve_residual,
        result.transport_direct_solve_residual,
        result.transport_state_solve_residual,
        result.transport_pivot_ratio,
        result.active_edge_mode_pairs,
        result.road_pairs,
        result.terminal_pairs,
        result.terminal_nodes,
        result.port_pairs,
        directed_arcs=length(data.road_edges),
        physical_links=length(data.road_edges) ÷ 2,
        result.mean_directed_elasticity,
        result.mean_physical_elasticity,
        mean_directed_gain_pct_1pct=linear_scale * result.mean_directed_elasticity,
        mean_physical_gain_pct_1pct=linear_scale * result.mean_physical_elasticity,
    )
end

end # module
