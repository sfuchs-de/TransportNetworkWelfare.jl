module CanonicalExampleTests

using Test
using TransportNetworkWelfare

const ROOT = normpath(joinpath(@__DIR__, ".."))

include(joinpath(ROOT, "examples", "sioux_falls", "prepare.jl"))

@testset "Braess-style routing example" begin
    project = load_project(joinpath(ROOT, "examples", "braess", "config.toml"))
    @test validate(project).valid
    result = decompose_welfare(project)
    @test length(result.directed) == 10
    @test length(result.physical) == 5
    @test maximum(abs(row.d_route) for row in result.directed) > 1e-3
    @test maximum(abs(row.identity_residual_route) for row in result.directed) < 1e-10
end

@testset "Cow network example" begin
    project = load_project(joinpath(ROOT, "examples", "cow", "config.toml"))
    report = validate(project)
    @test report.valid
    @test report.nodes == 30
    node_lines = readlines(joinpath(ROOT, "examples", "cow", "data", "nodes.csv"))
    header = split(first(node_lines), ',')
    elevation_column = findfirst(==("elevation"), header)
    @test elevation_column !== nothing
    elevations = [parse(Float64, split(line, ',')[elevation_column]) for line in node_lines[2:end]]
    @test all(isfinite, elevations)
    @test minimum(elevations) < 0 < maximum(elevations)
    @test maximum(elevations)-minimum(elevations) > 1.0
    result = decompose_welfare(project)
    @test length(result.directed) == 72
    @test length(result.physical) == 36
    hulten_rank = sort(result.physical; by=row -> row.hulten, rev=true)
    extended_rank = sort(result.physical; by=row -> row.primitive_F, rev=true)
    @test first(hulten_rank).physical_link_id == "C1_C2"
    @test first(extended_rank).physical_link_id == "C1_C2"
    @test getproperty.(hulten_rank[1:5], :physical_link_id) !=
          getproperty.(extended_rank[1:5], :physical_link_id)
    @test "H3_H4" in getproperty.(extended_rank[1:5], :physical_link_id)
    @test !("H3_H4" in getproperty.(hulten_rank[1:5], :physical_link_id))
    shifted = only(row for row in result.physical if row.physical_link_id == "H3_H4")
    @test abs(shifted.edge_scarcity) > 1e-3
    @test abs(shifted.route_scarcity) > 1e-3
    mktempdir() do first
        mktempdir() do second
            first_paths = write_results(result, first)
            second_paths = write_results(result, second)
            @test TransportNetworkWelfare.file_sha256.(first_paths) ==
                  TransportNetworkWelfare.file_sha256.(second_paths)
        end
    end
end

@testset "Sioux Falls parsers and BPR derivative" begin
    builder = SiouxFallsBuilder
    volume, capacity, b, power = 850.0, 1000.0, 0.15, 4.0
    analytic = builder.bpr_elasticity(volume, capacity, b, power)
    step = 1e-6
    log_cost(log_volume) = log(1+b*(exp(log_volume)/capacity)^power)
    finite_difference = (log_cost(log(volume)+step)-log_cost(log(volume)-step))/(2step)
    @test analytic ≈ finite_difference atol=1e-10 rtol=1e-8
    @test builder.bpr_elasticity(0.0, capacity, b, power) == 0.0
    @test_throws ArgumentError builder.bpr_elasticity(volume, 0.0, b, power)

    mktempdir() do directory
        network = joinpath(directory, "net.tntp")
        flow = joinpath(directory, "flow.tntp")
        node = joinpath(directory, "node.tntp")
        trips = joinpath(directory, "trips.tntp")
        write(network, "1 2 1000 1 1 0.15 4 0 0 1 ;\n")
        write(flow, "1 2 50 1.2\n")
        write(node, "1 0.0 0.0 ;\n2 1.0 0.0 ;\n")
        trip_rows = ["Origin $i\n$i : 1.0;" for i in 1:24]
        write(trips, "<NUMBER OF ZONES> 24\n<TOTAL OD FLOW> 24.0\n<END OF METADATA>\n\n" *
                     join(trip_rows, '\n'))
        @test only(keys(builder.parse_network(network))) == (1, 2)
        @test builder.parse_flows(flow)[(1, 2)].volume == 50.0
        @test builder.parse_nodes(node)[2] == (1.0, 0.0)
        parsed_trips = builder.parse_trips(trips)
        @test parsed_trips.total == 24.0
        @test sum(parsed_trips.matrix) == 24.0
    end
end

@testset "Optional pinned Sioux Falls integration" begin
    source = get(ENV, "TNW_SIOUX_FALLS_SOURCE_DIR", "")
    if isempty(source)
        @test_skip "set TNW_SIOUX_FALLS_SOURCE_DIR for the pinned-data integration test"
    else
        mktempdir() do output
            manifest = SiouxFallsBuilder.build_example(source, output; download=false)
            @test manifest["nodes"] == 24
            @test manifest["directed_links"] == 76
            @test manifest["physical_links"] == 38
            @test manifest["balanced_assigned_flow_error"] < 1e-10
            for name in ("config_efficient.toml", "config_extended.toml")
                config = read(joinpath(ROOT, "examples", "sioux_falls", name), String)
                config = replace(config, "generated/nodes.csv" => "nodes.csv",
                                         "generated/edge_modes.csv" => "edge_modes.csv")
                path = joinpath(output, name)
                write(path, config)
                project = load_project(path)
                @test validate(project).valid
                result = decompose_welfare(project)
                @test result.diagnostics["verified"]
                if name == "config_efficient.toml"
                    @test maximum(abs(row.primitive_F-row.hulten) for
                                  row in result.directed) < 1e-10
                end
            end
        end
    end
end

end # module
