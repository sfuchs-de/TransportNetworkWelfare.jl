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
        "traffic_ranked_subsets" => Dict(
            "50" => Dict("pearson" => 0.7, "spearman" => 0.6),
            "100" => Dict("pearson" => 0.8, "spearman" => 0.75),
        ),
    )
    decomposition = Dict{String,Any}(
        "road_congestion_change_percent" => 1.0,
        "fixed_modes_change_percent" => 2.0,
        "fixed_routes_change_percent" => 3.0,
        "primitive_to_realized_percent" => 4.0,
        "primitive_to_hulten_percent" => 5.0,
    )
    welfare_path = Dict{String,Any}(
        "mean_traditional" => 0.0004,
        "mean_domestic_efficient" => 0.00042,
        "mean_spatial_no_congestion" => 0.0005,
        "mean_extended" => 0.0003,
        "mean_boundary_adjustment" => 0.00002,
        "mean_spatial_externality_adjustment" => 0.00008,
        "mean_direct_externality_adjustment" => -0.0002,
        "mean_market_access_propagation_adjustment" => 0.0003,
        "mean_spatial_adjustment" => 0.0001,
        "mean_road_congestion_adjustment" => -0.00005,
        "mean_pass_through_adjustment" => -0.00015,
        "mean_road_congestion_policy_adjustment" => -0.0002,
        "mean_congestion_pass_through_change" => -0.0002,
        "mean_net_change" => -0.0001,
    )
    ranking = Dict{String,Any}("overlap_count" => 6, "jaccard_index" => 0.5)
    robustness = Dict{String,Any}(
        "mean_difference_percent" => 0.01,
        "physical_link_correlation" => 0.99,
    )
    diagnostics = Dict{String,Any}("nodes" => 3, "directed_policy_arcs" => 6)
    modal_diagnostics = Dict{String,Any}(
        "single_active_mode_road_arcs" => 5,
        "median_road_modal_share" => 1.0,
        "road_arcs_below_90_percent_modal_share" => 1,
        "minimum_eta_rank_correlation" => 0.99,
        "maximum_absolute_eta_rank_change" => 2.0,
    )
    mktempdir() do directory
        path = write_tex_macros(joinpath(directory, "paper_results.tex"), statistics,
            decomposition, welfare_path, ranking, robustness, diagnostics,
            modal_diagnostics)
        output = read(path, String)
        @test occursin("\\PaperPtenGainPercent}{0.01}", output)
        @test occursin("\\PaperPninetiethGainPercent}{0.02}", output)
        @test occursin("\\PaperTopTenTableCount}{10}", output)
        @test occursin("\\PaperTopLinkTableCount}{30}", output)
        @test occursin("\\PaperSpatialNoCongestionMeanScaled}{0.125}", output)
        @test occursin("\\PaperDomesticEfficientMeanScaled}{0.105}", output)
        @test occursin("\\PaperBoundaryAdjustmentScaled}{0.005}", output)
        @test occursin("\\PaperNetSpatialAdjustmentScaled}{0.025}", output)
        @test occursin("\\PaperRoadCongestionPolicyAdjustmentScaled}{-0.05}", output)
        @test occursin("\\PaperCongestionPassThroughAdjustmentScaled}{-0.05}", output)
        @test occursin("\\PaperNetExtendedAdjustmentScaled}{-0.025}", output)
        @test occursin("\\PaperTopFiftyTrafficCorrelation}{0.7}", output)
        @test occursin("\\PaperTopHundredTrafficRankCorrelation}{0.75}", output)
        @test occursin("\\PaperSingleModeRoadArcCount}{5}", output)
    end
end

@testset "Traffic-ranked correlations are deterministic" begin
    rows = [
        (physical_link_id="b", hulten=0.4, primitive_F=0.2),
        (physical_link_id="a", hulten=0.5, primitive_F=0.1),
        (physical_link_id="c", hulten=0.3, primitive_F=0.3),
        (physical_link_id="d", hulten=0.2, primitive_F=0.5),
    ]
    subsets = traffic_ranked_subset_statistics(rows, (3,))
    @test subsets["3"]["count"] == 3
    @test subsets["3"]["selection"] ==
        "descending traditional traffic statistic, then physical_link_id"
    @test isapprox(subsets["3"]["pearson"], -1.0; atol=1.0e-12)
    @test isapprox(subsets["3"]["spearman"], -1.0; atol=1.0e-12)
end

@testset "Policy-relevant path preserves the welfare identity" begin
    rows = [(
        traditional=0.0010,
        domestic_efficient=0.00102,
        spatial_no_congestion=0.0011,
        extended=0.0007,
        boundary_adjustment=0.00002,
        spatial_externality_adjustment=0.00008,
        direct_externality_adjustment=-0.0002,
        market_access_propagation_adjustment=0.0003,
        road_congestion_adjustment=-0.0001,
        terminal_congestion_adjustment=0.0,
        pass_through_adjustment=-0.0003,
        spatial_adjustment=0.0001,
        road_congestion_policy_adjustment=-0.0004,
        congestion_pass_through_change=-0.0004,
        net_change=-0.0003,
        spatial_component_residual=0.0,
        congestion_component_residual=0.0,
        identity_residual=0.0,
    )]
    summary = welfare_path_statistics(rows)
    @test summary["mean_traditional"] == 0.001
    @test summary["mean_domestic_efficient"] == 0.00102
    @test summary["mean_extended"] == 0.0007
    @test summary["mean_spatial_adjustment"] == 0.0001
    @test summary["mean_road_congestion_policy_adjustment"] == -0.0004
    @test summary["mean_congestion_pass_through_change"] == -0.0004
    @test summary["maximum_spatial_component_residual"] == 0.0
    @test summary["maximum_congestion_component_residual"] == 0.0
    @test summary["maximum_identity_residual"] == 0.0
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
