module ExternalRSUETests

using Test
using Statistics
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
    else
        @info "Skipping restricted RSUE acceptance test because RSUE_DATA_ROOT is not set"
        @test_skip haskey(ENV, "RSUE_DATA_ROOT")
    end
end

end # module
