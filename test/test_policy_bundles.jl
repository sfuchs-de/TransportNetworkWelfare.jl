module PolicyBundleTests

using Test
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, ".."))
const CONFIG = joinpath(ROOT, "examples", "toy", "config.toml")
const URBAN_CONFIG = joinpath(ROOT, "examples", "urban_multimodal", "config.toml")

@testset "Sparse policy bundles" begin
    project = load_project(CONFIG)
    model = build_model(project)
    result = welfare_effects(model)
    rows = Dict(row.edge_id => row for row in result.directed)
    entries = [
        PolicyBundleEntry("corridor", "AB", :road, 1.0),
        PolicyBundleEntry("corridor", "BC", :road, 0.5),
    ]
    bundled = only(bundle_welfare_effects(model, entries))
    @test bundled.bundle_id == "corridor"
    @test bundled.mode == "road"
    @test bundled.entries == 2
    @test bundled.total_weight == 1.5
    @test bundled.hulten ≈ rows["AB"].hulten + 0.5rows["BC"].hulten
    @test bundled.realized_F ≈ rows["AB"].realized_F + 0.5rows["BC"].realized_F
    @test bundled.primitive_F ≈ rows["AB"].primitive_F + 0.5rows["BC"].primitive_F
    @test bundled.extended_gain_pct ≈
        100project.policy.shock_fraction*bundled.primitive_F

    @test_throws ArgumentError PolicyBundleEntry("", "AB", :road, 1.0)
    @test_throws ArgumentError PolicyBundleEntry("a", "", :road, 1.0)
    @test_throws ArgumentError PolicyBundleEntry("a", "AB", "", 1.0)
    @test_throws ArgumentError PolicyBundleEntry("a", "AB", :road, 0.0)
    @test_throws ArgumentError bundle_welfare_effects(
        model, [PolicyBundleEntry("a", "AB", :rail, 1.0)])
    @test_throws ArgumentError bundle_welfare_effects(
        result, [PolicyBundleEntry("a", "missing", :road, 1.0)])
end

@testset "Policy-bundle nonlinear finite difference" begin
    model = TNW.build_welfare_model(load_project(URBAN_CONFIG))
    entries = [
        PolicyBundleEntry("joint", model.basis.policy_edge_ids[1], :road, 1.0),
        PolicyBundleEntry("joint", model.basis.policy_edge_ids[2], :road, 0.4),
    ]
    analytic = only(bundle_welfare_effects(model, entries)).primitive_F
    step = 1e-5
    shocks = zeros(model.basis.P)
    for entry in entries
        index = findfirst(==(entry.edge_id), model.basis.policy_edge_ids)
        shocks[model.basis.policy_pairs[index]] = step*entry.weight
    end
    plus = TNW.solve_urban_counterfactual(
        model, shocks, :F; shock_type=:primitive)
    minus = TNW.solve_urban_counterfactual(
        model, -shocks, :F; shock_type=:primitive)
    finite_difference = -(plus.log_welfare-minus.log_welfare)/(2step)
    @test analytic ≈ finite_difference atol=1e-6 rtol=0
end

@testset "Policy-bundle CSV validation" begin
    mktempdir() do directory
        valid = joinpath(directory, "valid.csv")
        write(valid,
              "bundle_id,edge_id,mode,weight\n" *
              "route-2,BC,road,0.5\n" *
              "route-1,AB,road,1.0\n")
        entries = load_policy_bundles(valid)
        @test getproperty.(entries, :bundle_id) == ["route-1", "route-2"]

        duplicate = joinpath(directory, "duplicate.csv")
        write(duplicate,
              "bundle_id,edge_id,mode,weight\n" *
              "route-1,AB,road,1.0\n" *
              "route-1,AB,road,2.0\n")
        @test_throws ArgumentError load_policy_bundles(duplicate)

        invalid = joinpath(directory, "invalid.csv")
        write(invalid, "bundle_id,edge_id,mode,weight\nroute-1,AB,road,NaN\n")
        @test_throws ArgumentError load_policy_bundles(invalid)
    end
end

end
