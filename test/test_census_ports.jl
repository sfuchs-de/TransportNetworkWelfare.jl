module CensusPortTests

using SparseArrays
using Test
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, ".."))
const CONFIG = joinpath(
    ROOT, "replication", "rsue", "rsue_census_ports_2017_candidate.toml")

@testset "Census port overlay" begin
    project = load_project(CONFIG)
    matrix, digest, rows, residual = TNW.rsue_census_port_matrix(project, 234, 228)
    @test digest == project.input["census_port_overlay_sha256"]
    @test rows == 210
    @test nnz(matrix) == rows
    @test sum(matrix) ≈ 1 atol=1e-14 rtol=0
    @test residual < 1e-12
    @test maximum(abs.(vec(sum(matrix; dims=2)) .- vec(sum(matrix; dims=1)))) < 1e-12
    @test sum(matrix[1:228, 229:234]) ≈ 0.5 atol=1e-12 rtol=0
    @test sum(matrix[229:234, 1:228]) ≈ 0.5 atol=1e-12 rtol=0

    directory = mktempdir()
    overlay = joinpath(directory, "unbalanced.csv")
    write(overlay,
        "origin_node,destination_node,domestic_node,foreign_node,direction,model_share\n" *
        "1,229,1,229,domestic_to_foreign,0.6\n" *
        "229,1,1,229,foreign_to_domestic,0.4\n")
    config = read(CONFIG, String)
    toml_overlay = replace(overlay, '\\' => '/')
    config = replace(config,
        r"census_port_overlay = .*" => "census_port_overlay = \"$toml_overlay\"",
        r"census_port_overlay_sha256 = .*" =>
            "census_port_overlay_sha256 = \"$(TNW.file_sha256(overlay))\"",
    )
    config_path = joinpath(directory, "config.toml")
    write(config_path, config)
    @test_throws ArgumentError TNW.rsue_census_port_matrix(
        load_project(config_path), 234, 228)
end

end # module
