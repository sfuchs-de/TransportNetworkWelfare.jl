module UrbanCommutingTests

using Test
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, ".."))
const CONFIG = joinpath(ROOT, "examples", "urban_toy", "config.toml")

@testset "Allen-Arkolakis urban model" begin
    project = load_project(CONFIG)
    @test project.spatial isa UrbanCommuting
    @test TNW.commuting_theta(project.parameters) == 6.83
    report = validate(project)
    @test report.valid
    @test report.spatial_specification == "urban_commuting"
    @test report.nodes == 3
    @test report.directed_edges == 6

    model = build_model(project)
    result = welfare_effects(model)
    @test result.diagnostics["verified"]
    @test result.diagnostics["closure_level"] == "urban_welfare"
    @test length(result.directed) == 6
    @test length(result.physical) == 3
    @test_throws ArgumentError decompose_welfare(model)
    @test_throws ArgumentError edge_local_welfare_effects(project)

    data, c = model.data, model.closures.c
    zero_state = zeros(2data.N+1)
    zero_shocks = zeros(length(data.edges))
    residual(state) = TNW.UrbanCommutingIFT.exact_hat_residual(
        state, zero_shocks, data.edges, data.sx, data.sy, data.mu, data.lam,
        data.residence, data.workplace, c)
    numerical_J = TNW.UrbanCommutingIFT.numerical_jacobian(residual, zero_state)
    @test maximum(abs.(model.closures.J-numerical_J)) < 2e-9
    perturbed_state = collect(range(-0.02, 0.02; length=length(zero_state)))
    perturbed_shocks = collect(range(-0.01, 0.01; length=length(data.edges)))
    perturbed_residual(state) = TNW.UrbanCommutingIFT.exact_hat_residual(
        state, perturbed_shocks, data.edges, data.sx, data.sy, data.mu, data.lam,
        data.residence, data.workplace, c)
    numerical_perturbed = TNW.UrbanCommutingIFT.numerical_jacobian(
        perturbed_residual, perturbed_state)
    analytic_perturbed = TNW.UrbanCommutingIFT.exact_hat_jacobian(
        perturbed_state, perturbed_shocks, data.edges, data.sx, data.sy,
        data.mu, data.lam, data.residence, data.workplace, c)
    @test maximum(abs.(analytic_perturbed-numerical_perturbed)) < 2e-9

    numerical_B = zeros(size(model.closures.J, 1), length(data.edges))
    step = 1e-6
    for edge in eachindex(data.edges)
        plus, minus = copy(zero_shocks), copy(zero_shocks)
        plus[edge] = step
        minus[edge] = -step
        numerical_B[:, edge] .= (
            TNW.UrbanCommutingIFT.exact_hat_residual(
                zero_state, plus, data.edges, data.sx, data.sy, data.mu, data.lam,
                data.residence, data.workplace, c) -
            TNW.UrbanCommutingIFT.exact_hat_residual(
                zero_state, minus, data.edges, data.sx, data.sy, data.mu, data.lam,
                data.residence, data.workplace, c)
        )/(2step)
    end
    analytic_B = TNW.UrbanCommutingIFT.cost_loading(
        data.N, data.edges, data.mu, data.lam, c)
    @test maximum(abs.(analytic_B-numerical_B)) < 2e-9

    by_id = Dict(row.edge_id => row.primitive_F for row in result.directed)
    for edge_id in model.basis.policy_edge_ids
        finite_difference = urban_finite_difference(model, edge_id; step=1e-5)
        @test finite_difference.elasticity ≈ by_id[edge_id] atol=2e-7 rtol=0
        @test finite_difference.plus.residual < 1e-10
        @test finite_difference.minus.residual < 1e-10
    end
end

@testset "Urban efficient benchmark and schema" begin
    source = read(CONFIG, String)
    nodes = joinpath(ROOT, "examples", "urban_toy", "data", "nodes.csv")
    edges = joinpath(ROOT, "examples", "urban_toy", "data", "edge_modes.csv")
    efficient = replace(source,
        "nodes = \"data/nodes.csv\"" => "nodes = \"$nodes\"",
        "edge_modes = \"data/edge_modes.csv\"" => "edge_modes = \"$edges\"",
        "alpha = -0.12" => "alpha = 0.0",
        "beta = -0.10" => "beta = 0.0",
        "lambda = 0.07144948755490483" => "lambda = 0.0",
    )
    mktempdir() do directory
        path = joinpath(directory, "efficient.toml")
        write(path, efficient)
        result = welfare_effects(load_project(path))
        @test maximum(abs(row.primitive_F-row.hulten) for row in result.directed) < 1e-10
    end

    @test_throws ArgumentError UrbanCommuting(-0.1)
    @test_throws ArgumentError TNW.UrbanCommutingIFT.coefficients(0, 0, 0, 0)
    @test_throws ArgumentError TNW.StructuralParameters(
        0.0, -1/6.83, 7.83, TheoremRouteCurvature())
    malformed = replace(source, "theta = 6.83" => "theta = 6.83\nsigma = 8.0")
    mktempdir() do directory
        path = joinpath(directory, "malformed.toml")
        write(path, malformed)
        @test_throws ArgumentError load_project(path)
    end
    urban_trade_singularity = replace(source, "beta = -0.10" => "beta = -0.14641288433382138")
    mktempdir() do directory
        path = joinpath(directory, "urban-trade-singularity.toml")
        write(path, urban_trade_singularity)
        @test load_project(path).spatial isa UrbanCommuting
    end
end

end
