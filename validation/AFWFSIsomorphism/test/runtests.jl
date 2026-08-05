using AFWFSIsomorphism
using LinearAlgebra
using Test

@testset "AFW--Fajgelbaum--Schaal isomorphism" begin
    economy = synthetic_economy()
    route = route_dual(economy)
    full = solve_full_afw(economy; route)

    @testset "entropy route-flow primal and soft-Bellman dual" begin
        primal = solve_route_primal(economy, 1, 4; route)
        @test norm(primal.conservation, Inf) <= 1e-8
        @test primal.value_error <= 2e-7
        @test primal.flow_error <= 2e-6
    end

    @testset "expanded entropy planner and full decentralized AFW equilibrium" begin
        planner = solve_expanded_planner(economy; route, start=full)
        @test abs(planner.W - full.W) <= 5e-6
        @test norm(planner.L - full.L, Inf) <= 1e-5
        @test norm(planner.c - full.c, Inf) <= 1e-5
        @test planner.route_cost_error <= 1e-5
        @test planner.flow_error <= 2e-5
        @test planner.conservation_error <= 2e-8
        @test norm(planner.resource_slack, Inf) <= 2e-6
        @test norm(planner.utility_slack, Inf) <= 2e-6
    end

    @testset "route-dualized spatial planner and full AFW equilibrium" begin
        planner = solve_spatial_planner(economy; route, start=full)
        @test abs(planner.W - full.W) <= 2e-7
        @test norm(planner.L - full.L, Inf) <= 3e-6
        @test norm(planner.c - full.c, Inf) <= 3e-6
        @test norm(planner.resource_slack, Inf) <= 2e-7
        @test norm(planner.utility_slack, Inf) <= 2e-7
    end

    @testset "equal-curvature recursive condensation" begin
        recursive = solve_recursive_afw(economy; start=full)
        @test recursive.residual_norm <= 1e-9
        @test abs(recursive.W - full.W) <= 2e-9
        @test norm(recursive.L - full.L, Inf) <= 2e-8
        @test recursive_closure_residual(economy, full) <= 2e-10

        mismatch = with_theta(economy, 2.2)
        mismatch_full = solve_full_afw(mismatch)
        @test recursive_closure_residual(mismatch, mismatch_full) >= 1e-5
    end

    @testset "adjoint, social savings, and finite differences" begin
        recursive = solve_recursive_afw(economy; start=full)
        adjoint = adjoint_diagnostics(economy, recursive)
        finite_difference = finite_difference_edge_effects(economy; baseline=full)
        mask = [isfinite(economy.kappa[i, j]) && i != j
                for i in axes(economy.kappa, 1), j in axes(economy.kappa, 2)]
        @test adjoint.linear_residual <= 2e-9
        @test adjoint.traffic_error <= 2e-9
        @test adjoint.endpoint_error <= 2e-8
        @test maximum(abs.(finite_difference[mask] - adjoint.elasticity[mask])) <= 2e-6
    end

    @testset "hard-routing limit" begin
        diagnostics = hard_limit_diagnostics(economy)
        @test all(row.monotone for row in diagnostics.rows)
        @test last(diagnostics.rows).tau_error <= 5e-6
        @test last(diagnostics.rows).welfare_error <= 5e-7
        @test last(diagnostics.rows).labor_error <= 5e-6
    end

    @testset "report" begin
        destination = tempname() * ".toml"
        results = run_validation(output=destination)
        @test isfile(destination)
        @test results["recursive_condensation"]["mismatch_residual_theta_2_2"] >= 1e-5
        @test results["expanded_planner_equilibrium"]["route_cost_error"] <= 1e-5
    end
end
