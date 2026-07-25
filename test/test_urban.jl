module UrbanCommutingTests

using Test
using TransportNetworkWelfare
using LinearAlgebra

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, ".."))
const LEGACY_CONFIG = joinpath(ROOT, "examples", "urban_toy", "config.toml")
const MULTIMODAL_CONFIG =
    joinpath(ROOT, "examples", "urban_multimodal", "config.toml")

function absolute_config(source_path::AbstractString)
    source = read(source_path, String)
    root = dirname(source_path)
    return replace(
        source,
        "nodes = \"data/nodes.csv\"" =>
            "nodes = \"$(joinpath(root, "data", "nodes.csv"))\"",
        "edge_modes = \"data/edge_modes.csv\"" =>
            "edge_modes = \"$(joinpath(root, "data", "edge_modes.csv"))\"",
    )
end

@testset "Allen-Arkolakis one-mode regression oracle" begin
    project = load_project(LEGACY_CONFIG)
    @test project.spatial isa UrbanCommuting
    @test project.congestion isa EdgeCongestion
    @test TNW.commuting_theta(project.parameters) == 6.83
    report = validate(project)
    @test report.valid
    @test report.spatial_specification == "urban_commuting"
    @test report.nodes == 3
    @test report.directed_edges == 6
    @test report.one_mode_regression.available
    @test report.one_mode_regression.state_response_error < 1e-10
    @test report.one_mode_regression.welfare_error < 1e-10
    @test report.one_mode_regression.raw_jacobian_difference > 1e-6
    @test occursin(
        "different residual rows",
        report.one_mode_regression.residual_normalization)

    model = build_model(project)
    result = welfare_effects(model)
    decomposition = decompose_welfare(model)
    @test result.diagnostics["verified"]
    @test result.diagnostics["closure_level"] == "urban_decomposition"
    @test decomposition.diagnostics["verified"]
    @test length(result.directed) == 6
    @test length(result.physical) == 3
    @test maximum(abs(row.realized_F-row.realized_FM)
                  for row in decomposition.directed) < 1e-10
    @test_throws ArgumentError edge_local_welfare_effects(project)

    data = model.data
    c = TNW.legacy_urban_coefficients(model)
    zero_state = zeros(2data.N+1)
    zero_shocks = zeros(length(data.edges))
    residual(state) = TNW.UrbanCommutingIFT.exact_hat_residual(
        state, zero_shocks, data.edges, data.sx, data.sy, data.mu, data.lam,
        data.residence, data.workplace, c)
    numerical_J = TNW.UrbanCommutingIFT.numerical_jacobian(residual, zero_state)
    oracle_J = TNW.UrbanCommutingIFT.jacobian(
        data.sx, data.sy, data.mu, data.lam,
        data.residence, data.workplace, c)
    @test maximum(abs.(oracle_J-numerical_J)) < 2e-9

    perturbed_state = collect(range(-0.02, 0.02; length=length(zero_state)))
    perturbed_shocks = collect(range(-0.01, 0.01; length=length(data.edges)))
    perturbed_residual(state) = TNW.UrbanCommutingIFT.exact_hat_residual(
        state, perturbed_shocks, data.edges, data.sx, data.sy, data.mu, data.lam,
        data.residence, data.workplace, c)
    numerical_perturbed = TNW.UrbanCommutingIFT.numerical_jacobian(
        perturbed_residual, perturbed_state)
    analytic_perturbed = TNW.UrbanCommutingIFT.exact_hat_jacobian(
        perturbed_state, perturbed_shocks, data.edges, data.sx, data.sy,
        data.mu, data.lam, data.residence, data.workplace, c)
    @test maximum(abs.(analytic_perturbed-numerical_perturbed)) < 2e-9

    numerical_B = zeros(size(oracle_J, 1), length(data.edges))
    step = 1e-6
    for edge in eachindex(data.edges)
        plus, minus = copy(zero_shocks), copy(zero_shocks)
        plus[edge] = step
        minus[edge] = -step
        numerical_B[:, edge] .= (
            TNW.UrbanCommutingIFT.exact_hat_residual(
                zero_state, plus, data.edges, data.sx, data.sy, data.mu, data.lam,
                data.residence, data.workplace, c) -
            TNW.UrbanCommutingIFT.exact_hat_residual(
                zero_state, minus, data.edges, data.sx, data.sy, data.mu, data.lam,
                data.residence, data.workplace, c)
        )/(2step)
    end
    oracle_B = TNW.UrbanCommutingIFT.cost_loading(
        data.N, data.edges, data.mu, data.lam, c)
    @test maximum(abs.(oracle_B-numerical_B)) < 2e-9
    primitive = TNW.primitive_forcing(model)
    @test maximum(abs.(
        model.closures.F\primitive.forcing-oracle_J\oracle_B)) < 1e-10

    by_id = Dict(row.edge_id => row.primitive_F for row in result.directed)
    for edge_id in model.basis.policy_edge_ids
        finite_difference = urban_finite_difference(model, edge_id; step=1e-5)
        @test finite_difference.elasticity ≈ by_id[edge_id] atol=2e-7 rtol=0
        @test finite_difference.plus.residual < 1e-10
        @test finite_difference.minus.residual < 1e-10
    end
end

@testset "Multimodal urban closures and nonlinear finite differences" begin
    project = load_project(MULTIMODAL_CONFIG)
    report = validate(project)
    @test report.valid
    @test report.nodes == 4
    @test report.directed_edges == 10
    @test report.active_edge_modes == 20
    @test report.modes == ["road", "transit"]
    @test report.stock_disagreement < 1e-10
    @test report.route_bilateral_row_error < 1e-10
    @test report.route_bilateral_column_error < 1e-10
    @test report.route_edge_error < 1e-10

    model = build_model(project)
    result = decompose_welfare(model)
    @test result.diagnostics["verified"]
    @test result.diagnostics["max_inverse_gap_error"] < 1e-10
    @test result.diagnostics["max_ladder_error"] < 1e-10
    @test length(result.directed) == 10
    @test length(result.physical) == 5
    @test any(abs(row.d_terminal) > 1e-6 for row in result.directed)
    @test any(abs(row.d_mode) > 1e-6 for row in result.directed)
    @test any(abs(row.d_route) > 1e-6 for row in result.directed)
    mktempdir() do first
        mktempdir() do second
            first_paths = write_results(result, first; project)
            second_paths = write_results(result, second; project)
            first_csv = filter(path -> endswith(path, ".csv"), first_paths)
            second_csv = filter(path -> endswith(path, ".csv"), second_paths)
            @test TNW.file_sha256.(first_csv) == TNW.file_sha256.(second_csv)
            manifest = read(
                only(filter(path -> endswith(path, "run_manifest.json"), first_paths)),
                String)
            @test occursin("\"spatial_closure\":\"urban_commuting\"", manifest)
            @test occursin("\"route_curvature_value\":6", manifest)
            @test occursin("\"policy_mode\":\"road\"", manifest)
        end
    end

    mirror_project = Project(
        project.config_path, project.root, project.name, project.schema_version,
        project.input, EconomicGeography(), project.parameters, project.modal,
        project.congestion, project.policy, project.output_dir,
        project.sensitivity, project.condition_limit, project.tolerance, project.raw)
    source_state, destination_state, aggregate_state =
        TNW.urban_bilateral_state_rows(project, model.data.N)
    mirror_basis = TNW.build_spatial_transport_basis(
        mirror_project, model.data;
        source=model.data.residence,
        destination=model.data.workplace,
        source_state,
        destination_state,
        aggregate_state,
        route_curvature=TNW.commuting_theta(project.parameters),
        state_map=Matrix{Float64}(I, 2model.data.N+1, 2model.data.N+1),
    )
    @test maximum(abs.(mirror_basis.Croute_soft-model.basis.Croute_soft)) < 1e-10
    @test maximum(abs.(mirror_basis.Croute_fixed-model.basis.Croute_fixed)) < 1e-10
    mirror_transport = TNW.build_transport_closure(
        mirror_project, model.data, mirror_basis, model.closures.B)
    @test maximum(abs.(mirror_transport.H-model.closures.transport.F.H)) < 1e-10
    @test maximum(abs.(mirror_transport.Xq-model.closures.transport.F.Xq)) < 1e-10

    realized_forcing =
        model.closures.B*model.basis.Sagg[:, model.basis.policy_pairs]
    for closure in (:NC, :NT, :F, :FM, :FR)
        primitive = TNW.primitive_forcing(model, closure)
        primitive_analytic = TNW.operator_gain(
            getproperty(model.closures, closure), model.closures.q,
            primitive.forcing)
        realized_analytic = TNW.operator_gain(
            getproperty(model.closures, closure), model.closures.q,
            realized_forcing)
        for policy_index in (1, length(model.basis.policy_pairs))
            primitive_fd = urban_multimodal_finite_difference(
                model, policy_index; closure, shock_type=:primitive, step=1e-5)
            realized_fd = urban_multimodal_finite_difference(
                model, policy_index; closure, shock_type=:realized, step=1e-5)
            @test primitive_fd.elasticity ≈ primitive_analytic[policy_index] atol=1e-6 rtol=0
            @test realized_fd.elasticity ≈ realized_analytic[policy_index] atol=1e-6 rtol=0
            primitive_state =
                -(getproperty(model.closures, closure) \ primitive.forcing[:, policy_index])
            realized_state =
                -(getproperty(model.closures, closure) \ realized_forcing[:, policy_index])
            primitive_fd_state =
                (primitive_fd.plus.state-primitive_fd.minus.state)/(2e-5)
            realized_fd_state =
                (realized_fd.plus.state-realized_fd.minus.state)/(2e-5)
            @test maximum(abs.(primitive_fd_state-primitive_state)) < 1e-6
            @test maximum(abs.(realized_fd_state-realized_state)) < 1e-6
            @test primitive_fd.plus.residual < 1e-9
            @test primitive_fd.minus.residual < 1e-9
            @test realized_fd.plus.residual < 1e-9
            @test realized_fd.minus.residual < 1e-9
        end
    end
end

@testset "Urban limits, invariance, and schema failures" begin
    legacy = absolute_config(LEGACY_CONFIG)
    efficient = replace(
        legacy,
        "alpha = -0.12" => "alpha = 0.0",
        "beta = -0.10" => "beta = 0.0",
        "lambda = 0.07144948755490483" => "lambda = 0.0",
    )
    mktempdir() do directory
        path = joinpath(directory, "efficient.toml")
        write(path, efficient)
        result = welfare_effects(load_project(path))
        @test maximum(abs(row.primitive_F-row.hulten)
                      for row in result.directed) < 1e-10
    end

    multimodal = absolute_config(MULTIMODAL_CONFIG)
    no_terminal = replace(multimodal, "transit = 0.04" => "transit = 0.0")
    terminal_only = replace(
        multimodal,
        "specification = \"composite\"" =>
            "specification = \"endpoint_terminal\"",
    )
    no_congestion = replace(
        multimodal,
        "specification = \"composite\"" => "specification = \"none\"",
    )
    reversed_modes = replace(
        multimodal,
        "mode_order = [\"road\", \"transit\"]" =>
            "mode_order = [\"transit\", \"road\"]",
    )
    mktempdir() do directory
        terminal_path = joinpath(directory, "no-terminal.toml")
        write(terminal_path, no_terminal)
        terminal_result = decompose_welfare(load_project(terminal_path))
        @test maximum(abs(row.realized_F-row.realized_NT)
                      for row in terminal_result.directed) < 1e-10

        terminal_only_path = joinpath(directory, "terminal-only.toml")
        write(terminal_only_path, terminal_only)
        terminal_only_result = decompose_welfare(load_project(terminal_only_path))
        @test maximum(abs(row.realized_NC-row.realized_NT)
                      for row in terminal_only_result.directed) < 1e-10
        @test any(abs(row.realized_NT-row.realized_F) > 1e-6
                  for row in terminal_only_result.directed)

        none_path = joinpath(directory, "none.toml")
        write(none_path, no_congestion)
        none_result = decompose_welfare(load_project(none_path))
        @test maximum(abs(row.realized_F-row.primitive_F)
                      for row in none_result.directed) < 1e-10

        reverse_path = joinpath(directory, "reverse-modes.toml")
        write(reverse_path, reversed_modes)
        baseline = Dict(row.edge_id => row.primitive_F
                        for row in decompose_welfare(load_project(
                            MULTIMODAL_CONFIG)).directed)
        permuted = Dict(row.edge_id => row.primitive_F
                        for row in decompose_welfare(load_project(reverse_path)).directed)
        @test keys(baseline) == keys(permuted)
        @test maximum(abs(baseline[key]-permuted[key]) for key in keys(baseline)) < 1e-10

        node_lines = readlines(joinpath(
            ROOT, "examples", "urban_multimodal", "data", "nodes.csv"))
        permuted_nodes_path = joinpath(directory, "nodes-permuted.csv")
        write(permuted_nodes_path, join(vcat(first(node_lines), reverse(node_lines[2:end])), "\n")*"\n")
        original_nodes_path =
            joinpath(ROOT, "examples", "urban_multimodal", "data", "nodes.csv")
        node_config = replace(
            multimodal,
            "nodes = \"$original_nodes_path\"" => "nodes = \"$permuted_nodes_path\"",
        )
        node_path = joinpath(directory, "reverse-nodes.toml")
        write(node_path, node_config)
        node_permuted = Dict(row.edge_id => row.primitive_F
            for row in decompose_welfare(load_project(node_path)).directed)
        @test maximum(abs(baseline[key]-node_permuted[key])
                      for key in keys(baseline)) < 1e-10
    end

    @test_throws ArgumentError UrbanCommuting(-0.1)
    @test_throws ArgumentError TNW.UrbanCommutingIFT.coefficients(0, 0, 0, 0)
    malformed = replace(legacy, "theta = 6.83" => "theta = 6.83\nsigma = 8.0")
    double_congestion = replace(
        legacy,
        "specification = \"none\"" =>
            "specification = \"edge\"\n\n[congestion.edge]\nroad = 0.1",
    )
    mktempdir() do directory
        malformed_path = joinpath(directory, "malformed.toml")
        write(malformed_path, malformed)
        @test_throws ArgumentError load_project(malformed_path)

        double_path = joinpath(directory, "double.toml")
        write(double_path, double_congestion)
        @test_throws ArgumentError load_project(double_path)

        nodes_path = joinpath(ROOT, "examples", "urban_multimodal", "data", "nodes.csv")
        edges_path = joinpath(ROOT, "examples", "urban_multimodal", "data", "edge_modes.csv")
        bad_edges = replace(
            read(edges_path, String),
            "0.03166533522595979" => "0.04166533522595979",
        )
        bad_edges_path = joinpath(directory, "bad-edges.csv")
        write(bad_edges_path, bad_edges)
        bad_config = replace(
            multimodal,
            "edge_modes = \"$edges_path\"" => "edge_modes = \"$bad_edges_path\"",
        )
        bad_path = joinpath(directory, "bad-accounting.toml")
        write(bad_path, bad_config)
        @test_throws ArgumentError validate(load_project(bad_path))

        missing_terminal_edges = replace(
            read(edges_path, String),
            "A_station,B_station" => ",B_station",
            count=1,
        )
        missing_terminal_path = joinpath(directory, "missing-terminal.csv")
        write(missing_terminal_path, missing_terminal_edges)
        missing_terminal_config = replace(
            multimodal,
            "edge_modes = \"$edges_path\"" =>
                "edge_modes = \"$missing_terminal_path\"",
        )
        missing_terminal_config_path =
            joinpath(directory, "missing-terminal.toml")
        write(missing_terminal_config_path, missing_terminal_config)
        @test_throws ArgumentError validate(load_project(
            missing_terminal_config_path))
    end
end

@testset "Unique-route urban limit" begin
    mktempdir() do directory
        write(joinpath(directory, "nodes.csv"),
            "node_id,residents,employment\n" *
            "A,0.5,0.4\nB,0.3,0.3\nC,0.2,0.30000000000000004\n")
        write(joinpath(directory, "edges.csv"),
            "edge_id,physical_link_id,origin,destination,mode,flow\n" *
            "AB,AB,A,B,road,0.1\nBC,BC,B,C,road,0.1\n")
        write(joinpath(directory, "config.toml"), """
            schema_version = 1
            name = "urban-unique-route"
            [input]
            adapter = "generic_csv_v1"
            nodes = "nodes.csv"
            edge_modes = "edges.csv"
            mode_order = ["road"]
            [input.transformations]
            normalize_residents = true
            normalize_employment = true
            flow_conversion = "none"
            symmetrize = false
            pad_nodes = 0
            modal_rescale = false
            [model]
            spatial_specification = "urban_commuting"
            alpha = -0.05
            beta = -0.08
            theta = 5.0
            modal_specification = "choice_logsum"
            eta = 1.2
            route_curvature = "theorem"
            [congestion]
            specification = "edge"
            [congestion.edge]
            road = 0.04
            [policy]
            mode = "road"
            unit = "directed_arc"
            shock_fraction = 0.01
            [output]
            directory = "output"
            [diagnostics]
            tolerance = 1.0e-10
            condition_limit = 1.0e12
        """)
        result = decompose_welfare(load_project(joinpath(directory, "config.toml")))
        @test maximum(abs(row.realized_F-row.realized_FR)
                      for row in result.directed) < 1e-10
        @test maximum(abs(row.realized_F-row.realized_FM)
                      for row in result.directed) < 1e-10
    end
end

end
