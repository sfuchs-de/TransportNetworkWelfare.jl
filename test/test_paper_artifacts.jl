module PaperArtifactTests

using Test

include(joinpath(@__DIR__, "..", "replication", "rsue", "build_paper_artifacts.jl"))

@testset "Paper macros respect the configured shock size" begin
    statistics = Dict{String,Any}(
        "shock_fraction" => 0.025,
        "mean_gain_percent" => 0.1,
        "median_gain_percent" => 0.09,
        "maximum_gain_percent" => 0.2,
        "p10_elasticity" => 0.004,
        "p90_elasticity" => 0.008,
        "pearson_hulten" => 0.9,
        "spearman_hulten" => 0.8,
        "top_decile_median_ratio" => 2.0,
    )
    decomposition = Dict{String,Any}(
        "road_congestion_change_percent" => 1.0,
        "fixed_modes_change_percent" => 2.0,
        "fixed_routes_change_percent" => 3.0,
        "primitive_to_realized_percent" => 4.0,
        "primitive_to_hulten_percent" => 5.0,
    )
    ranking = Dict{String,Any}("overlap_count" => 6, "jaccard_index" => 0.5)
    robustness = Dict{String,Any}(
        "mean_difference_percent" => 0.01,
        "physical_link_correlation" => 0.99,
    )
    diagnostics = Dict{String,Any}("nodes" => 3, "directed_policy_arcs" => 6)
    mktempdir() do directory
        path = write_tex_macros(joinpath(directory, "paper_results.tex"), statistics,
            decomposition, ranking, robustness, diagnostics)
        output = read(path, String)
        @test occursin("\\PaperPtenGainPercent}{0.01}", output)
        @test occursin("\\PaperPninetiethGainPercent}{0.02}", output)
        @test occursin("\\PaperTopTenTableCount}{10}", output)
        @test occursin("\\PaperTopLinkTableCount}{30}", output)
    end
end

@testset "Sensitivity link panel reconciles with aggregate output" begin
    summaries = [(
        model_role="headline", parameter="eta", value=1.0,
        mean_physical_elasticity=0.15,
        spearman_vs_baseline=1.0,
    )]
    links = [
        (
            model_role="headline", parameter="eta", value=1.0,
            extended_elasticity=0.1, baseline_extended_elasticity=0.1,
        ),
        (
            model_role="headline", parameter="eta", value=1.0,
            extended_elasticity=0.2, baseline_extended_elasticity=0.2,
        ),
    ]
    diagnostics = validate_sensitivity_panel(
        summaries, links; expected_links=2)
    @test diagnostics["groups"] == 1
    @test diagnostics["rows"] == 2
    @test diagnostics["maximum_mean_error"] <= 1.0e-12
    @test diagnostics["maximum_rank_correlation_error"] <= 1.0e-12

    bad = [merge(summaries[1], (mean_physical_elasticity=0.2,))]
    @test_throws ErrorException validate_sensitivity_panel(
        bad, links; expected_links=2)
end

end # module
