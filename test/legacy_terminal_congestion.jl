module LegacyTerminalCongestionTests

# Independent checks for edge congestion plus endpoint terminal congestion.
using Test
using LinearAlgebra
using SparseArrays
using Statistics

const HERE = @__DIR__
using TransportNetworkWelfare.AdjointRSUE
using TransportNetworkWelfare.IFTDecomposition
using TransportNetworkWelfare.RSUETerminalCongestion

const ROOT = normpath(joinpath(HERE, ".."))

function toy_data()
    N = 3
    modes = (:road, :rail)
    edges = [(1, 2), (2, 1), (2, 3), (3, 2)]
    road = sparse([1, 2, 2, 3], [2, 1, 3, 2], [0.030, 0.020, 0.010, 0.015], N, N)
    rail = sparse([1, 2, 2, 3], [2, 1, 3, 2], [0.010, 0.015, 0.020, 0.012], N, N)
    mode_flows = [road, rail]
    Xi = road + rail
    s_edges = zeros(length(edges), length(modes))
    for (t, (i, j)) in enumerate(edges)
        s_edges[t, :] .= [flow[i, j] for flow in mode_flows] ./ Xi[i, j]
    end
    return (; N, modes, edges, road_edges=copy(edges), mode_flows, s_edges)
end

function weighted_logsumexp(values, weights)
    maximum_value = maximum(values)
    return maximum_value + log(sum(weights .* exp.(values .- maximum_value)))
end

function exact_modal_logtraffic(a, z, R_edge, data, basis, eta, sigma)
    aggregate = zeros(basis.E)
    for t in 1:basis.E
        pairs = basis.edge_pairs[t]
        values = [eta * a[p] for p in pairs]
        weights = [data.s_edges[t, basis.pair_mode[p]] for p in pairs]
        aggregate[t] = weighted_logsumexp(values, weights) / eta
    end
    x = zeros(basis.P)
    for p in 1:basis.P
        t = basis.pair_edge[p]
        x[p] = dot(@view(R_edge[t, :]), z) + eta * a[p] +
            (1 - sigma - eta) * aggregate[t]
    end
    return x
end

function exact_terminal_residual(a, z, delta, R_edge, data, basis;
                                 eta, sigma, lambda_road, lambda_terminal)
    x = exact_modal_logtraffic(a, z, R_edge, data, basis, eta, sigma)
    residual = a .- delta
    rail_mode = basis.mode_index[:rail]
    for p in 1:basis.P
        m = basis.pair_mode[p]
        i = basis.pair_origin[p]
        j = basis.pair_destination[p]
        if m == basis.road_mode
            residual[p] -= lambda_road * x[p]
        elseif m == rail_mode
            out = basis.outgoing[m][i]
            incoming = basis.incoming[m][j]
            out_weights = [basis.pair_flow[q] / basis.out_totals[m, i] for q in out]
            in_weights = [basis.pair_flow[q] / basis.in_totals[m, j] for q in incoming]
            residual[p] -= lambda_terminal * (
                weighted_logsumexp(x[out], out_weights) +
                weighted_logsumexp(x[incoming], in_weights))
        end
    end
    return residual
end

function central_jacobian(f, x; step=1e-6)
    y = f(x)
    J = zeros(length(y), length(x))
    for j in eachindex(x)
        xp = copy(x); xp[j] += step
        xm = copy(x); xm[j] -= step
        J[:, j] .= (f(xp) .- f(xm)) ./ (2step)
    end
    return J
end

function solve_exact_terminal(delta, R_edge, data, basis;
                              eta, sigma, lambda_road, lambda_terminal)
    a = zeros(basis.P)
    z = zeros(size(R_edge, 2))
    for _ in 1:20_000
        residual = exact_terminal_residual(
            a, z, delta, R_edge, data, basis;
            eta, sigma, lambda_road, lambda_terminal)
        norm(residual, Inf) < 1e-14 && return a
        a .-= 0.35 .* residual
    end
    error("toy nonlinear terminal fixed point did not converge")
end

function solve_coupled_terminal(delta, J0, B, R_edge, data, basis;
                                eta, sigma, lambda_road, lambda_terminal)
    state_dimension = size(J0, 1)
    unknown = zeros(state_dimension + basis.P)
    function residual(value)
        z = @view value[1:state_dimension]
        a = @view value[state_dimension+1:end]
        aggregate_cost = zeros(basis.E)
        for p in 1:basis.P
            t = basis.pair_edge[p]
            aggregate_cost[t] += data.s_edges[t, basis.pair_mode[p]] * a[p]
        end
        spatial = J0 * z + B * aggregate_cost
        terminal = exact_terminal_residual(
            a, z, delta, R_edge, data, basis;
            eta, sigma, lambda_road, lambda_terminal)
        return vcat(spatial, terminal)
    end
    for _ in 1:30
        value = residual(unknown)
        norm(value, Inf) < 1e-13 && return unknown
        derivative = central_jacobian(residual, unknown; step=1e-6)
        unknown .-= derivative \ value
    end
    error("coupled toy equilibrium did not converge")
end

@testset "Endpoint terminal congestion" begin
    @testset "independent nonlinear linearization" begin
        data = toy_data()
        basis = build_pair_basis(data)
        sigma, eta = 4.0, 1.2
        lambda_road, lambda_terminal = 0.05, 0.04
        transport = build_transport_linearization(
            data;
            basis,
            sigma,
            eta,
            lambda_road,
            lambda_terminal,
        )
        R_edge = [
             0.20 -0.10  0.05;
            -0.15  0.30 -0.02;
             0.08  0.04 -0.25;
            -0.11  0.07  0.19;
        ]
        zeros_pair = zeros(basis.P)
        zeros_state = zeros(size(R_edge, 2))
        zeros_shock = zeros(basis.P)
        residual_a(a) = exact_terminal_residual(
            a, zeros_state, zeros_shock, R_edge, data, basis;
            eta, sigma, lambda_road, lambda_terminal)
        residual_z(z) = exact_terminal_residual(
            zeros_pair, z, zeros_shock, R_edge, data, basis;
            eta, sigma, lambda_road, lambda_terminal)

        fd_a = central_jacobian(residual_a, zeros_pair)
        fd_z = central_jacobian(residual_z, zeros_state)
        R_pair = R_edge[basis.pair_edge, :]
        @test maximum(abs.(fd_a .- Matrix(transport.H))) < 2e-9
        @test maximum(abs.(fd_z .+ Matrix(transport.Gamma) * R_pair)) < 2e-9

        p = basis.road_pairs[2]
        step = 1e-5
        shock = zeros(basis.P); shock[p] = step
        plus = solve_exact_terminal(
            shock, R_edge, data, basis;
            eta, sigma, lambda_road, lambda_terminal)
        minus = solve_exact_terminal(
            -shock, R_edge, data, basis;
            eta, sigma, lambda_road, lambda_terminal)
        fd_response = (plus .- minus) ./ (2step)
        analytic_response = transport.factor \ Vector(sparsevec([p], [1.0], basis.P))
        @test maximum(abs.(fd_response .- analytic_response)) < 2e-8

        J0 = [1.8 0.1 -0.1; -0.2 1.5 0.05; 0.08 -0.12 1.7]
        B = [
             0.20 -0.10  0.04  0.03;
            -0.05  0.18 -0.07  0.02;
             0.03  0.06  0.16 -0.09;
        ]
        plus_joint = solve_coupled_terminal(
            shock, J0, B, R_edge, data, basis;
            eta, sigma, lambda_road, lambda_terminal)
        minus_joint = solve_coupled_terminal(
            -shock, J0, B, R_edge, data, basis;
            eta, sigma, lambda_road, lambda_terminal)
        fd_state = (plus_joint[1:3] .- minus_joint[1:3]) ./ (2step)
        R_pair = R_edge[basis.pair_edge, :]
        pair_state = transport.factor \ (transport.Gamma * R_pair)
        aggregate_state = transport.Sagg * pair_state
        aggregate_direct = transport.Sagg * analytic_response
        J = J0 + B * aggregate_state
        forcing = B * aggregate_direct
        analytic_state = -(J \ forcing)
        q = [0.4, -0.2, 0.3]
        @test maximum(abs.(fd_state .- analytic_state)) < 2e-8
        @test isapprox(-dot(q, fd_state), dot(q, J \ forcing); atol=2e-9, rtol=0)
    end

end

end # module
