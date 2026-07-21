module ExternalRSUETests

using Test
using Statistics
using TOML
using TransportNetworkWelfare

const ROOT = normpath(joinpath(@__DIR__, ".."))

@testset "External RSUE legacy acceptance" begin
    if haskey(ENV, "RSUE_DATA_ROOT")
        project = load_project(joinpath(ROOT, "replication", "rsue", "rsue_legacy_audited.toml"))
        result = decompose_welfare(project)
        @test length(result.directed) == 704
        @test length(result.physical) == 352
        @test result.diagnostics["verified"]
        @test mean(row.primitive_F for row in result.directed) ≈
            0.00010716227429258084 atol=5e-15 rtol=0
        @test maximum(abs(row.identity_residual_route) for row in result.directed) < 1e-10

        census_project = load_project(joinpath(
            ROOT, "replication", "rsue", "rsue_census_ports_2017_candidate.toml"))
        census_report = validate(census_project)
        @test census_report.stock_disagreement < 1e-12
        @test "foreign_port_symmetrize=false" in census_report.transformations
        census_result = decompose_welfare(census_project)
        @test length(census_result.directed) == 704
        @test length(census_result.physical) == 352
        @test census_result.diagnostics["verified"]
        census_expected = TOML.parsefile(joinpath(
            ROOT, "replication", "rsue", "census_ports", "expected_summary.toml"))
        @test mean(row.primitive_F for row in census_result.directed) ≈
            census_expected["results"]["mean_directed_primitive_elasticity"] atol=5e-15 rtol=0
        @test median(row.primitive_F for row in census_result.directed) ≈
            census_expected["results"]["median_directed_primitive_elasticity"] atol=5e-15 rtol=0
        @test maximum(abs(row.identity_residual_route) for row in census_result.directed) < 1e-10

        control_project = load_project(joinpath(
            ROOT, "replication", "rsue", "rsue_legacy_ports_all_modes_control.toml"))
        control_result = decompose_welfare(control_project)
        control_values = [row.primitive_F for row in control_result.directed]
        census_values = [row.primitive_F for row in census_result.directed]
        comparison = census_expected["same_specification_legacy_port_comparison"]
        @test mean(control_values) ≈
            comparison["control_mean_directed_primitive_elasticity"] atol=5e-15 rtol=0
        @test 100 * (mean(census_values) / mean(control_values) - 1) ≈
            comparison["candidate_mean_percent_difference"] atol=1e-10 rtol=0
        @test cor(control_values, census_values) ≈
            comparison["directed_primitive_correlation"] atol=1e-12 rtol=0
        @test maximum(abs.(control_values .- census_values)) ≈
            comparison["maximum_absolute_directed_difference"] atol=5e-15 rtol=0

        paper_project = load_project(joinpath(
            ROOT, "replication", "rsue", "rsue_paper_choice_edge_census_2017.toml"))
        @test paper_project.modal isa ChoiceLogsum
        @test paper_project.modal.eta == 1.099
        @test paper_project.congestion isa EdgeCongestion
        paper_result = decompose_welfare(paper_project)
        @test length(paper_result.directed) == 704
        @test length(paper_result.physical) == 352
        @test paper_result.diagnostics["verified"]
        @test mean(row.primitive_F for row in paper_result.physical) ≈
            0.00022309500106787019 atol=5e-15 rtol=0
        @test median(row.primitive_F for row in paper_result.physical) ≈
            0.00018070218508596498 atol=5e-15 rtol=0
        @test maximum(abs(row.identity_residual_route) for row in paper_result.directed) < 1e-10
    else
        @info "Skipping restricted RSUE acceptance test because RSUE_DATA_ROOT is not set"
        @test_skip haskey(ENV, "RSUE_DATA_ROOT")
    end
end

end # module
