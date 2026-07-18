module LegacyRouteDecompositionTests

# =============================================================================
# Independent checks for the exact common-baseline IFT decomposition.
# Run: julia --project=. --startup-file=no test/runtests_decomposition.jl
# =============================================================================
using Test, LinearAlgebra, Random

const HERE = @__DIR__
using TransportNetworkWelfare.AdjointRSUE
using TransportNetworkWelfare.IFTDecomposition

_mat(flat, nr, nc) = permutedims(reshape(Float64.(flat), nc, nr))
od_index(i, j, N) = i + (j - 1) * N

function route_object(K, sx, nu)
    N = length(sx)
    T = (Matrix{Float64}(I, N, N) - K) \ Matrix{Float64}(I, N, N)
    Xod = Diagonal(nu) * T * Diagonal(sx)
    return (; K, T, Xod)
end

function route_state_rows(N)
    nv = 2N + 1
    S = zeros(N, nv)
    D = zeros(N, nv)
    for i in 1:N
        S[i, i] = 0.30
        S[i, N+i] = -0.10
        D[i, i] = -0.20
        D[i, N+i] = 0.25
        D[i, end] = -0.15
    end
    return S, D, zeros(nv)
end

function central_jacobian(f, x; step=1e-6)
    y = f(x)
    J = zeros(length(y), length(x))
    for j in eachindex(x)
        plus = copy(x); plus[j] += step
        minus = copy(x); minus[j] -= step
        J[:, j] .= (f(plus) .- f(minus)) ./ (2step)
    end
    return J
end

function solve_fixed_route_system(delta, shock_edge, J0, B, incidence,
                                  xod, Zod, edge_traffic, gamma, sigma)
    nv = size(J0, 1)
    Cn = length(gamma)
    value = zeros(nv + Cn)
    function residual(candidate)
        state = @view candidate[1:nv]
        costs = @view candidate[nv+1:end]
        log_flow = Zod * state + (1 - sigma) .* (incidence * costs)
        flow = xod .* exp.(log_flow)
        traffic_hat = vec(permutedims(incidence) * flow) ./ edge_traffic
        spatial = J0 * state + B * costs + delta .* B[:, shock_edge]
        congestion = costs .- gamma .* log.(traffic_hat)
        return vcat(spatial, congestion)
    end
    for _ in 1:30
        current = residual(value)
        norm(current, Inf) < 1e-13 && return value
        derivative = central_jacobian(residual, value)
        value .-= derivative \ current
    end
    error("fixed-route toy system did not converge")
end

function fixture(tag)
    return include(joinpath(HERE, "fixtures", "$(tag).jl"))
end

@testset "IFT decomposition" begin
    f = fixture("ext_cong")
    c = coefs(f.alpha, f.beta, f.sigma)

    @testset "Jacobian ownership and closure ladder" begin
        parts = jacobian_parts(f.sx, f.sy, f.mu, f.lam, f.omega, c)
        @test parts.sparse + parts.global_feedback ≈ parts.total atol=1e-12 rtol=0
        @test rank(parts.global_feedback; atol=1e-10) == 1

        closures = build_closures(
            f.N, f.edges, f.s_all, f.sx, f.sy, f.mu, f.lam,
            f.omega, f.nu, f.gam, f.eta, c)
        @test closures.NC ≈ parts.total atol=1e-12 rtol=0
        @test closures.NT ≈ closures.NC + closures.road_congestion atol=1e-12 rtol=0
        @test closures.F ≈ closures.NT + closures.port_congestion atol=1e-12 rtol=0
        @test closures.FM ≈ closures.NC + closures.fixed_mode_congestion atol=1e-12 rtol=0
        @test all(isfinite, values(closures.conditions))
    end

    @testset "Fixed-mode limiting cases" begin
        nedge = length(f.edges)

        # With one active mode, flexible and fixed modal allocations coincide.
        one_mode_shares = hcat(ones(nedge), zeros(nedge))
        one_mode_gamma = [0.08, 0.0]
        flexible_one = congestion_J(
            f.N, f.edges, one_mode_shares, f.mu, f.lam,
            f.omega, f.nu, one_mode_gamma, f.eta, c)
        fixed_one = fixed_mode_congestion_J(
            f.N, f.edges, one_mode_shares, f.mu, f.lam,
            f.omega, f.nu, one_mode_gamma, f.sigma, c)
        @test flexible_one ≈ fixed_one atol=1e-12 rtol=0

        # Equal congestion elasticities leave no relative modal-cost response.
        equal_gamma = fill(0.06, f.M)
        flexible_equal = congestion_J(
            f.N, f.edges, f.s_all, f.mu, f.lam,
            f.omega, f.nu, equal_gamma, f.eta, c)
        fixed_equal = fixed_mode_congestion_J(
            f.N, f.edges, f.s_all, f.mu, f.lam,
            f.omega, f.nu, equal_gamma, f.sigma, c)
        @test flexible_equal ≈ fixed_equal atol=1e-12 rtol=0

        zero_gamma = zeros(f.M)
        flexible_zero = congestion_J(
            f.N, f.edges, f.s_all, f.mu, f.lam,
            f.omega, f.nu, zero_gamma, f.eta, c)
        fixed_zero = fixed_mode_congestion_J(
            f.N, f.edges, f.s_all, f.mu, f.lam,
            f.omega, f.nu, zero_gamma, f.sigma, c)
        @test iszero(flexible_zero)
        @test iszero(fixed_zero)
    end

    @testset "Inverse-Jacobian identity" begin
        rng = MersenneTwister(20260711)
        n = 9
        JA = Matrix(I, n, n) + 0.05 .* randn(rng, n, n)
        JB = Matrix(I, n, n) + 0.05 .* randn(rng, n, n)
        q = randn(rng, n)
        b = randn(rng, n)
        direct = operator_gain(JA, q, b) - operator_gain(JB, q, b)
        @test inverse_gap(JA, JB, q, b) ≈ direct atol=1e-12 rtol=1e-12
    end

    @testset "Route reconstruction on oracle fixture" begin
        route = reconstruct_route_kernel(f.mu, f.sx, f.nu, f.Xi)
        d = route.diagnostics
        @test d.spectral_radius < 1
        @test d.row_error < 1e-12
        @test d.column_error < 1e-12
        @test d.absorption_error < 1e-12
        @test d.edge_error < 1e-12
    end

    @testset "Route incidence: unique path and parallel paths" begin
        h = 1e-6

        # The only 1-to-4 route is 1->2->4. Conditional edge use stays one
        # after either edge is perturbed, so the full and frozen route margins
        # coincide on this OD pair.
        Ku = zeros(4, 4)
        Ku[1, 2] = 0.40
        Ku[2, 4] = 0.50
        unique_edges = [(1, 2), (2, 4)]
        Tu = (Matrix{Float64}(I, 4, 4) - Ku) \ Matrix{Float64}(I, 4, 4)
        Iu = route_incidence(Tu, Ku, unique_edges)
        @test Iu[od_index(1, 4, 4), :] ≈ ones(2) atol=1e-12 rtol=0
        for edge in unique_edges
            Kplus = copy(Ku)
            Kminus = copy(Ku)
            Kplus[edge...] *= exp(h)
            Kminus[edge...] *= exp(-h)
            Tplus = (Matrix{Float64}(I, 4, 4) - Kplus) \ Matrix{Float64}(I, 4, 4)
            Tminus = (Matrix{Float64}(I, 4, 4) - Kminus) \ Matrix{Float64}(I, 4, 4)
            fd = (log(Tplus[1, 4]) - log(Tminus[1, 4])) / (2h)
            t = findfirst(==(edge), unique_edges)
            @test fd ≈ Iu[od_index(1, 4, 4), t] atol=1e-9 rtol=1e-9

            pplus = Kplus[1, 2] * Kplus[2, 4] / Tplus[1, 4]
            pminus = Kminus[1, 2] * Kminus[2, 4] / Tminus[1, 4]
            @test (log(pplus) - log(pminus)) / (2h) ≈ 0 atol=1e-9
        end

        # Two parallel 1-to-4 paths. Incidence must equal an independent
        # central difference of the route resolvent with respect to log K_e.
        Kp = zeros(4, 4)
        Kp[1, 2] = 0.30
        Kp[2, 4] = 0.40
        Kp[1, 3] = 0.20
        Kp[3, 4] = 0.50
        parallel_edges = [(1, 2), (2, 4), (1, 3), (3, 4)]
        Tp = (Matrix{Float64}(I, 4, 4) - Kp) \ Matrix{Float64}(I, 4, 4)
        Ip = route_incidence(Tp, Kp, parallel_edges)
        for (t, edge) in enumerate(parallel_edges)
            Kplus = copy(Kp)
            Kminus = copy(Kp)
            Kplus[edge...] *= exp(h)
            Kminus[edge...] *= exp(-h)
            Tplus = (Matrix{Float64}(I, 4, 4) - Kplus) \ Matrix{Float64}(I, 4, 4)
            Tminus = (Matrix{Float64}(I, 4, 4) - Kminus) \ Matrix{Float64}(I, 4, 4)
            fd = (log(Tplus[1, 4]) - log(Tminus[1, 4])) / (2h)
            @test fd ≈ Ip[od_index(1, 4, 4), t] atol=1e-9 rtol=1e-9
        end
        @test 0 < Ip[od_index(1, 4, 4), 1] < 1
        @test 0 < Ip[od_index(1, 4, 4), 3] < 1
    end

    @testset "FR closure: unique and parallel routes" begin
        sigma = 3.5
        nu = [0.28, 0.22, 0.27, 0.23]
        S, D, dlogY = route_state_rows(4)

        Ku = zeros(4, 4)
        Ku[1, 2] = 0.40
        Ku[2, 4] = 0.50
        sxu = 1 .- vec(sum(Ku; dims=2))
        unique_edges = [(1, 2), (2, 4)]
        route_u = route_object(Ku, sxu, nu)
        soft_u = soft_route_operators(
            route_u, unique_edges, nu, sxu, S, D, dlogY, sigma)
        fixed_u = fixed_route_operators(
            route_u, unique_edges, route_u.Xod, S, D, dlogY, sigma;
            return_incidence=true)
        @test maximum(abs.(soft_u.B .- fixed_u.B)) < 1e-12
        @test maximum(abs.(soft_u.Qz .- fixed_u.Qz)) < 1e-12
        @test maximum(abs.(soft_u.C .- fixed_u.C)) < 1e-12

        gamma_u = fill(0.04, length(unique_edges))
        pass_soft_u = Matrix{Float64}(I, 2, 2) .-
            (1 - sigma) .* (reshape(gamma_u, :, 1) .* soft_u.C)
        pass_fixed_u = Matrix{Float64}(I, 2, 2) .-
            (1 - sigma) .* (reshape(gamma_u, :, 1) .* fixed_u.C)
        A_soft_u = pass_soft_u \ (reshape(gamma_u, :, 1) .* soft_u.Qz)
        A_fixed_u = pass_fixed_u \ (reshape(gamma_u, :, 1) .* fixed_u.Qz)
        J0_u = 2 .* Matrix{Float64}(I, size(S, 2), size(S, 2))
        J_soft_u = J0_u + soft_u.B * A_soft_u
        J_fixed_u = J0_u + fixed_u.B * A_fixed_u
        @test maximum(abs.(J_soft_u .- J_fixed_u)) < 1e-12

        Kp = zeros(4, 4)
        Kp[1, 2] = 0.30
        Kp[2, 4] = 0.40
        Kp[1, 3] = 0.20
        Kp[3, 4] = 0.50
        sxp = 1 .- vec(sum(Kp; dims=2))
        parallel_edges = [(1, 2), (2, 4), (1, 3), (3, 4)]
        route_p = route_object(Kp, sxp, nu)
        soft_p = soft_route_operators(
            route_p, parallel_edges, nu, sxp, S, D, dlogY, sigma)
        fixed_p = fixed_route_operators(
            route_p, parallel_edges, route_p.Xod, S, D, dlogY, sigma;
            return_incidence=true)
        @test maximum(abs.(soft_p.B .- fixed_p.B)) < 1e-12
        @test maximum(abs.(soft_p.C .- fixed_p.C)) > 1e-3

        step = 1e-6
        xod = vec(route_p.Xod)
        incidence = fixed_p.incidence
        for shock_edge in eachindex(parallel_edges)
            plus_flow = xod .* exp.((1 - sigma) .* step .* incidence[:, shock_edge])
            minus_flow = xod .* exp.(-(1 - sigma) .* step .* incidence[:, shock_edge])
            plus_traffic = vec(permutedims(incidence) * plus_flow)
            minus_traffic = vec(permutedims(incidence) * minus_flow)
            fd = (log.(plus_traffic) .- log.(minus_traffic)) ./ (2step)
            @test maximum(abs.(fd .- (1 - sigma) .* fixed_p.C[:, shock_edge])) < 1e-9

            edge = parallel_edges[shock_edge]
            Kplus = copy(Kp); Kplus[edge...] *= exp((1 - sigma) * step)
            Kminus = copy(Kp); Kminus[edge...] *= exp(-(1 - sigma) * step)
            plus = route_object(Kplus, sxp, nu)
            minus = route_object(Kminus, sxp, nu)
            plus_traffic_soft = [
                vec(permutedims(nu) * plus.T)[k] * Kplus[k, l] * (plus.T * sxp)[l]
                for (k, l) in parallel_edges
            ]
            minus_traffic_soft = [
                vec(permutedims(nu) * minus.T)[k] * Kminus[k, l] * (minus.T * sxp)[l]
                for (k, l) in parallel_edges
            ]
            fd_soft = (log.(plus_traffic_soft) .- log.(minus_traffic_soft)) ./ (2step)
            @test maximum(abs.(fd_soft .- (1 - sigma) .* soft_p.C[:, shock_edge])) < 1e-9
        end

        Zod = zeros(16, size(S, 2))
        for j in 1:4, i in 1:4
            Zod[od_index(i, j, 4), :] .= S[i, :] .+ D[j, :] .- dlogY
        end
        direction = collect(range(-0.2, 0.2; length=size(S, 2)))
        plus_flow = xod .* exp.(step .* (Zod * direction))
        minus_flow = xod .* exp.(-step .* (Zod * direction))
        plus_traffic = vec(permutedims(incidence) * plus_flow)
        minus_traffic = vec(permutedims(incidence) * minus_flow)
        fd_state = (log.(plus_traffic) .- log.(minus_traffic)) ./ (2step)
        @test maximum(abs.(fd_state .- fixed_p.Qz * direction)) < 1e-9

        gamma_p = fill(0.04, length(parallel_edges))
        pass_fixed_p = Matrix{Float64}(I, 4, 4) .-
            (1 - sigma) .* (reshape(gamma_p, :, 1) .* fixed_p.C)
        A_fixed_p = pass_fixed_p \ (reshape(gamma_p, :, 1) .* fixed_p.Qz)
        J0_p = 2 .* Matrix{Float64}(I, size(S, 2), size(S, 2))
        J0_p .+= 0.01 .* (ones(size(J0_p)) .- Matrix{Float64}(I, size(J0_p)...))
        J_fixed_p = J0_p + fixed_p.B * A_fixed_p
        policy_edge = 1
        policy_step = 1e-5
        plus_solution = solve_fixed_route_system(
            policy_step, policy_edge, J0_p, fixed_p.B, incidence,
            xod, Zod, fixed_p.edge_traffic, gamma_p, sigma)
        minus_solution = solve_fixed_route_system(
            -policy_step, policy_edge, J0_p, fixed_p.B, incidence,
            xod, Zod, fixed_p.edge_traffic, gamma_p, sigma)
        fd_equilibrium = (plus_solution[1:size(S, 2)] .-
            minus_solution[1:size(S, 2)]) ./ (2policy_step)
        analytic_equilibrium = -(J_fixed_p \ fixed_p.B[:, policy_edge])
        @test maximum(abs.(fd_equilibrium .- analytic_equilibrium)) < 2e-8
    end
end

end # module
