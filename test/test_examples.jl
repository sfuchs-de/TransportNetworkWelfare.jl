module CanonicalExampleTests

using Test
using LinearAlgebra
using TransportNetworkWelfare

const ROOT = normpath(joinpath(@__DIR__, ".."))

include(joinpath(ROOT, "examples", "sioux_falls", "prepare.jl"))
include(joinpath(ROOT, "examples", "cow", "build_mesh_network.jl"))

@testset "Braess-style routing example" begin
    project = load_project(joinpath(ROOT, "examples", "braess", "config.toml"))
    @test validate(project).valid
    result = decompose_welfare(project)
    @test length(result.directed) == 10
    @test length(result.physical) == 5
    @test maximum(abs(row.d_route) for row in result.directed) > 1e-3
    @test maximum(abs(row.identity_residual_route) for row in result.directed) < 1e-10
end

@testset "Multimodal grid guide example" begin
    config = joinpath(ROOT, "examples", "grid_multimodal", "config.toml")
    project = load_project(config)
    report = validate(project)
    @test report.valid
    @test report.nodes == 25
    @test report.directed_edges == 80
    @test report.policy_arcs == 80

    model = build_model(project)
    result = decompose_welfare(model)
    @test length(result.directed) == 80
    @test length(result.physical) == 40
    @test model.basis.P == 88
    @test result.diagnostics["verified"]
    @test result.diagnostics["route_spectral_radius"] < 1
    @test result.diagnostics["max_inverse_gap_error"] < 1e-10
    @test result.diagnostics["max_ladder_error"] < 1e-10
    @test result.diagnostics["max_channel_reconstruction_error"] < 1e-10

    hulten_rank = sort(result.physical; by=row -> row.hulten, rev=true)
    extended_rank = sort(result.physical; by=row -> row.primitive_F, rev=true)
    hulten_position = Dict(row.physical_link_id => rank
                           for (rank, row) in enumerate(hulten_rank))
    extended_position = Dict(row.physical_link_id => rank
                             for (rank, row) in enumerate(extended_rank))
    @test maximum(abs(hulten_position[id]-extended_position[id])
                  for id in keys(hulten_position)) >= 8

    function check_policy_finite_difference(candidate, edge_id)
        candidate_result = decompose_welfare(candidate)
        pair = findfirst(==(edge_id), candidate.basis.policy_edge_ids)
        @test pair !== nothing
        shock = 1e-5
        plus = Main.ModalConventionTests.solve_full_closure(candidate, pair, shock)
        minus = Main.ModalConventionTests.solve_full_closure(candidate, pair, -shock)
        welfare_row = TransportNetworkWelfare.AdjointRSUE.welfare_gradient(
            candidate.data.omega, candidate.closures.c)
        n = size(candidate.closures.J0, 1)
        finite_difference = -dot(welfare_row, plus[1:n]-minus[1:n])/(2shock)
        @test isapprox(
            finite_difference,
            candidate_result.directed[pair].primitive_F;
            atol=1e-8,
            rtol=1e-6,
        )
    end

    check_policy_finite_difference(model, "H_r3_c3_E")

    mktempdir() do directory
        mkpath(joinpath(directory, "data"))
        cp(joinpath(dirname(config), "data", "nodes.csv"),
           joinpath(directory, "data", "nodes.csv"))
        cp(joinpath(dirname(config), "data", "edge_modes.csv"),
           joinpath(directory, "data", "edge_modes.csv"))
        transit_config = replace(
            read(config, String),
            "mode = \"road\"" => "mode = \"transit\"",
        )
        write(joinpath(directory, "config.toml"), transit_config)
        transit_model = build_model(load_project(joinpath(directory, "config.toml")))
        check_policy_finite_difference(transit_model, "H_r3_c3_E")
    end

    efficient = TransportNetworkWelfare.model_at(
        model,
        TransportNetworkWelfare.replace_project(
            project; alpha=0.0, beta=0.0, congestion=NoCongestion()),
    )
    efficient_result = decompose_welfare(efficient)
    @test maximum(abs(row.primitive_F-row.hulten)
                  for row in efficient_result.directed) < 1e-8

    zero_terminal = TransportNetworkWelfare.model_at(
        model,
        TransportNetworkWelfare.replace_project(
            project;
            congestion=CompositeCongestion(
                EdgeCongestion(Dict(:road => 0.08)),
                EndpointTerminalCongestion(Dict(:transit => 0.0)),
            ),
        ),
    )
    @test zero_terminal.closures.NT ≈ zero_terminal.closures.F atol=1e-12 rtol=0

    mktempdir() do directory
        mkpath(joinpath(directory, "data"))
        cp(joinpath(dirname(config), "data", "nodes.csv"),
           joinpath(directory, "data", "nodes.csv"))
        lines = split(chomp(read(
            joinpath(dirname(config), "data", "edge_modes.csv"), String)), '\n')
        road_only = vcat(lines[1], filter(line -> occursin(",road,", line), lines[2:end]))
        write(joinpath(directory, "data", "edge_modes.csv"), join(road_only, '\n')*"\n")
        one_mode_config = read(config, String)
        one_mode_config = replace(
            one_mode_config,
            "mode_order = [\"road\", \"transit\"]" => "mode_order = [\"road\"]",
        )
        old_congestion = """[congestion]
specification = "composite"
endpoint_scale = 1.0

[congestion.edge]
road = 0.08

[congestion.terminal]
transit = 0.025
"""
        new_congestion = """[congestion]
specification = "edge"

[congestion.edge]
road = 0.08
"""
        one_mode_config = replace(one_mode_config, old_congestion => new_congestion)
        write(joinpath(directory, "config.toml"), one_mode_config)
        one_mode = build_model(load_project(joinpath(directory, "config.toml")))
        @test one_mode.closures.F ≈ one_mode.closures.FM atol=1e-12 rtol=0
    end
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

@testset "Cow mesh network builder" begin
    vertices = [
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        0.0 0.0 1.0
    ]
    faces = [[1, 2, 3], [1, 2, 4], [1, 3, 4], [2, 3, 4]]
    edges = CowMeshBuilder.mesh_edges(faces)
    @test length(edges) == 6
    income = fill(0.25, 4)
    balanced = CowMeshBuilder.balanced_edge_flows(
        vertices, edges, income; openness=0.5)
    outgoing = zeros(4)
    for (flow, (i, j)) in zip(balanced.flow, edges)
        outgoing[i] += flow
        outgoing[j] += flow
    end
    @test outgoing ≈ 0.5 .* income atol=1e-12 rtol=0
    @test balanced.balance_error < 1e-12
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
