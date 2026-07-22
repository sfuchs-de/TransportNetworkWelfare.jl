module EdgeCongestionTests

using Test
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, ".."))
const TOY = joinpath(ROOT, "examples", "toy")

function column_project(; edge_transform=identity, config_transform=identity)
    directory = mktempdir()
    mkpath(joinpath(directory, "data"))
    cp(joinpath(TOY, "data", "nodes.csv"), joinpath(directory, "data", "nodes.csv"))
    lines = split(chomp(read(joinpath(TOY, "data", "edge_modes.csv"), String)), '\n')
    edges = [lines[1]*",congestion_elasticity"]
    for line in lines[2:end]
        cells = split(line, ','; keepempty=true)
        push!(edges, line*","*(cells[5] == "road" ? "0.05" : "0.0"))
    end
    write(joinpath(directory, "data", "edge_modes.csv"),
          edge_transform(join(edges, '\n')*"\n"))
    config = read(joinpath(TOY, "config.toml"), String)
    old = """[congestion]
specification = "composite"
endpoint_scale = 1.0

[congestion.edge]
road = 0.05

[congestion.terminal]
rail = 0.03
"""
    new = """[congestion]
specification = "composite"
source = "input_column"
column = "congestion_elasticity"
scale = 1.0
endpoint_scale = 1.0

[congestion.terminal]
rail = 0.03
"""
    config = replace(config, old => new)
    write(joinpath(directory, "config.toml"), config_transform(config))
    return directory, load_project(joinpath(directory, "config.toml"))
end

function drop_last_csv_column(text)
    lines = split(chomp(text), '\n')
    reduced = [join(split(line, ','; keepempty=true)[1:end-1], ',') for line in lines]
    return join(reduced, '\n')*"\n"
end

@testset "Input-column edge congestion" begin
    @test EdgeCongestion(; input_column="congestion_elasticity", scale=1.5).scale == 1.5
    @test_throws ArgumentError EdgeCongestion(
        Dict(:road => 0.1), "congestion_elasticity", 1.0)
    @test_throws ArgumentError EdgeCongestion(Dict(:road => 0.1), nothing, 2.0)
    @test_throws ArgumentError EdgeCongestion(; input_column=" ")
    @test_throws ArgumentError EdgeCongestion(; input_column="lambda", scale=-1)

    _, project = column_project()
    report = validate(project)
    @test report.valid
    @test report.edge_congestion["source"] == "input_column"
    @test report.edge_congestion["input_column"] == "congestion_elasticity"
    @test report.edge_congestion["count"] == 10
    @test report.edge_congestion["positive_count"] == 6
    @test report.edge_congestion["minimum"] == 0.0
    @test report.edge_congestion["maximum"] == 0.05

    baseline = decompose_welfare(load_project(joinpath(TOY, "config.toml")))
    heterogeneous = decompose_welfare(project)
    @test maximum(abs(a.primitive_F-b.primitive_F) for
        (a, b) in zip(baseline.directed, heterogeneous.directed)) < 1e-12

    model = build_model(project)
    path = sensitivity_path(model, :edge_congestion_scale, [0.0, 1.0, 1.5])
    @test length(path) == 3
    @test all(row.verified for row in path)
    @test_throws ArgumentError sensitivity_path(model, :lambda_road, [0.05])

    mktempdir() do output
        result = decompose_welfare(model)
        paths = write_results(result, output; project)
        manifest = read(only(filter(path -> endswith(path, "run_manifest.json"), paths)), String)
        @test occursin("\"edge_congestion_source\":\"input_column\"", manifest)
        @test occursin("\"edge_congestion_input_column\":\"congestion_elasticity\"", manifest)
        @test occursin("\"edge_congestion_scale\":1", manifest)
    end
end

@testset "Input-column schema failures" begin
    _, missing_column = column_project(
        edge_transform=drop_last_csv_column)
    @test_throws ArgumentError validate(missing_column)

    _, blank_value = column_project(
        edge_transform=edges -> replace(edges, "0.05" => ""; count=1))
    @test_throws ArgumentError validate(blank_value)

    _, negative_value = column_project(
        edge_transform=edges -> replace(edges, ",0.05" => ",-0.01"; count=1))
    @test_throws ArgumentError validate(negative_value)

    _, nonfinite_value = column_project(
        edge_transform=edges -> replace(edges, ",0.05" => ",Inf"; count=1))
    @test_throws ArgumentError validate(nonfinite_value)

    _, reserved_column = column_project(
        config_transform=config -> replace(
            config, "column = \"congestion_elasticity\"" => "column = \"flow\""))
    @test_throws ArgumentError validate(reserved_column)

    @test_throws ArgumentError column_project(config_transform=config -> replace(
        config, "[congestion.terminal]" =>
            "[congestion.edge]\nroad = 0.05\n\n[congestion.terminal]"))

    @test_throws ArgumentError column_project(config_transform=config -> replace(
        config, "specification = \"composite\"" =>
            "specification = \"endpoint_terminal\""; count=1))

    active_road(config) = replace(
        replace(config, "route_curvature = \"theorem\"" =>
            "route_curvature = \"theorem\"\nactive_transport_modes = [\"road\"]"),
        "rail = 0.03" => "rail = 0.0",
    )
    _, road_only = column_project(config_transform=active_road)
    road_report = validate(road_only)
    @test road_report.edge_congestion["count"] == 6
    @test road_report.edge_congestion["positive_count"] == 6

    _, inactive_positive = column_project(
        edge_transform=edges -> replace(edges, ",0.0" => ",0.01"; count=1),
        config_transform=active_road,
    )
    @test_throws ArgumentError validate(inactive_positive)
end

end # module
