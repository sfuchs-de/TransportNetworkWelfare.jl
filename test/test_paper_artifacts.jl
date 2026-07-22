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
    end
end

end # module
