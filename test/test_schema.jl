module SchemaTests

using Test
using TransportNetworkWelfare

const ROOT = normpath(joinpath(@__DIR__, ".."))
const BASE = joinpath(ROOT, "examples", "toy")

function isolated_project(modify_nodes=identity, modify_edges=identity, modify_config=identity)
    directory = mktempdir()
    mkpath(joinpath(directory, "data"))
    nodes = modify_nodes(read(joinpath(BASE, "data", "nodes.csv"), String))
    edges = modify_edges(read(joinpath(BASE, "data", "edge_modes.csv"), String))
    config = modify_config(read(joinpath(BASE, "config.toml"), String))
    write(joinpath(directory, "data", "nodes.csv"), nodes)
    write(joinpath(directory, "data", "edge_modes.csv"), edges)
    write(joinpath(directory, "config.toml"), config)
    return directory, joinpath(directory, "config.toml")
end

@testset "Schema failures are explicit" begin
    directory, path = isolated_project(nodes -> nodes*"A,1,1,0,0\n")
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity,
        edges -> replace(edges, "AB,AB,A,B,road" => "AB,AB,Z,B,road"; count=1))
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity,
        edges -> replace(edges, "road,0.010" => "road,-0.010"; count=1))
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity,
        edges -> replace(edges, "BA,AB,B,A,road" => "BA,BA,B,A,road"; count=1))
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity,
        edges -> replace(edges, "rail,0.003,TA,TB" => "rail,0.003,,TB"; count=1))
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "flow_conversion = \"none\"" => "flow_conversion = \"miles\""))
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "route_curvature = \"theorem\"" => "route_curvature = 2.0"))
    @test_throws ArgumentError load_project(path)

    directory, path = isolated_project(identity,
        edges -> replace(edges, "road,0.010" => "road,0.0"; count=1))
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity,
        edges -> edges*"AB,AB,A,B,road,0.010,,\n")
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity,
        edges -> replace(edges, "AB,AB,A,B,road,0.010" =>
                                "AB,AB,A,B,road,0.011"; count=1))
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity,
        edges -> edges*"AB-alternative,AB-alternative,A,B,road,0.001,,\n")
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "beta = -0.30" => "beta = -0.2375"))
    @test_throws ArgumentError validate(load_project(path))

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "alpha = 0.10" => "alpha = inf"))
    @test_throws ArgumentError load_project(path)

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "condition_limit = 1.0e12" =>
                                  "condition_limit = inf"))
    @test_throws ArgumentError load_project(path)

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "tolerance = 1.0e-10" => "tolerance = nan"))
    @test_throws ArgumentError load_project(path)

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "eta = [0.70, 0.90, 1.099, 1.30, 1.50]" =>
                                  "eta = [0.70, inf]"))
    @test_throws ArgumentError load_project(path)

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "eta = [0.70, 0.90, 1.099, 1.30, 1.50]" =>
                                  "eta = 1.099"))
    @test_throws ArgumentError load_project(path)

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "eta = [0.70, 0.90, 1.099, 1.30, 1.50]" =>
                                  "eta = []"))
    @test_throws ArgumentError load_project(path)

    directory, path = isolated_project(identity, identity,
        config -> replace(config, "mode_order = [\"road\", \"rail\"]" =>
                                  "mode_order = \"road\""))
    @test_throws ArgumentError validate(load_project(path))
end

@testset "Typed specifications reject nonfinite values" begin
    @test_throws ArgumentError ChoiceLogsum(Inf)
    @test_throws ArgumentError ComponentCES(NaN)
    @test_throws ArgumentError EdgeCongestion(Dict(:road => Inf))
    @test_throws ArgumentError EndpointTerminalCongestion(Dict(:rail => NaN))
    @test_throws ArgumentError EndpointTerminalCongestion(Dict(:rail => 0.1), Inf)
end

@testset "Missing external RSUE data has an actionable error" begin
    config = joinpath(ROOT, "replication", "rsue", "rsue_legacy_audited.toml")
    previous = pop!(ENV, "RSUE_DATA_ROOT", nothing)
    try
        @test_throws ArgumentError validate(load_project(config))
    finally
        previous === nothing || (ENV["RSUE_DATA_ROOT"] = previous)
    end
end

end # module
