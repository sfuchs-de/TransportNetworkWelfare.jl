module APITests

using Test
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, ".."))
const CONFIG = joinpath(ROOT, "examples", "toy", "config.toml")

function by_edge(rows)
    return Dict(row.edge_id => row for row in rows)
end

function replace_diagnostics(project; condition_limit=project.condition_limit,
                             tolerance=project.tolerance)
    return Project(
        project.config_path, project.root, project.name, project.schema_version,
        project.input, project.parameters, project.modal, project.congestion,
        project.policy, project.output_dir, project.sensitivity,
        condition_limit, tolerance, project.raw,
    )
end

@testset "Typed API and closure ladder" begin
    @test_throws ArgumentError TNW.run_command("unknown", "missing.toml")
    @test TNW.json_escape("a\b\f\x01") == "\"a\\b\\f\\u0001\""
    project = load_project(CONFIG)
    report = validate(project)
    @test report.valid
    @test report.nodes == 3
    @test report.policy_arcs == 6
    model = build_model(project)
    welfare = welfare_effects(model)
    decomposition = decompose_welfare(model)
    @test length(welfare.directed) == 6
    @test length(welfare.physical) == 3
    @test length(decomposition.directed) == 6
    @test decomposition.diagnostics["verified"]
    @test decomposition.diagnostics["input_hashes"] == model.data.input_hashes
    @test decomposition.diagnostics["transformations"] == model.data.transformations
    @test maximum(abs(row.identity_residual_edge) for row in decomposition.directed) < 1e-12
    @test maximum(abs(row.identity_residual_terminal) for row in decomposition.directed) < 1e-12
    @test maximum(abs(row.identity_residual_mode) for row in decomposition.directed) < 1e-12
    @test maximum(abs(row.identity_residual_route) for row in decomposition.directed) < 1e-12
    @test all(isfinite(row.primitive_F) for row in decomposition.directed)

    none_project = TNW.replace_project(project; congestion=NoCongestion())
    none_model = TNW.model_at(model, none_project)
    @test none_model.closures.NC ≈ none_model.closures.NT atol=1e-12 rtol=0
    @test none_model.closures.NC ≈ none_model.closures.F atol=1e-12 rtol=0

    edge_project = TNW.replace_project(project;
        congestion=EdgeCongestion(Dict(:road => 0.05)))
    edge_model = TNW.model_at(model, edge_project)
    @test edge_model.closures.NT ≈ edge_model.closures.F atol=1e-12 rtol=0

    terminal_project = TNW.replace_project(project;
        congestion=EndpointTerminalCongestion(Dict(:rail => 0.03)))
    terminal_model = TNW.model_at(model, terminal_project)
    @test terminal_model.closures.NC ≈ terminal_model.closures.NT atol=1e-12 rtol=0

    efficient_project = TNW.replace_project(project;
        alpha=0.0, beta=0.0, congestion=NoCongestion())
    efficient_model = TNW.model_at(model, efficient_project)
    efficient = decompose_welfare(efficient_model)
    @test maximum(abs(row.primitive_F-row.hulten) for row in efficient.directed) < 1e-10
    @test maximum(abs(row.realized_F-row.hulten) for row in efficient.directed) < 1e-10
end

@testset "External project initialization" begin
    @test TNW.main(["--help"]) == 0
    mktempdir() do parent
        destination = joinpath(parent, "my-network")
        @test TNW.run_command("init", destination) == 0
        config = joinpath(destination, "config.toml")
        @test isfile(config)
        @test isfile(joinpath(destination, "README.md"))
        @test isfile(joinpath(destination, "data", "nodes.csv"))
        @test isfile(joinpath(destination, "data", "edge_modes.csv"))
        @test validate(load_project(config)).valid
        @test TNW.run_command("decompose", config) == 0
        @test isfile(joinpath(destination, "output", "decomposition_directed.csv"))
        @test isfile(joinpath(destination, "output", "decomposition_physical.csv"))
        @test isfile(joinpath(destination, "output", "run_manifest.json"))
        @test_throws ArgumentError initialize_project(destination)
    end
end

@testset "Sensitivity and deterministic output" begin
    project = load_project(CONFIG)
    model = build_model(project)
    values = project.sensitivity[:eta]
    rows = sensitivity_path(model, :eta, values)
    @test length(rows) == length(values)
    @test all(row.verified for row in rows)
    @test all(isfinite(row.mean_directed_elasticity) for row in rows)

    rank_rows = TNW.sensitivity_rank_path(model, :eta, values[1:2])
    @test length(rank_rows) == 2
    @test all(isfinite(row.spearman_vs_baseline) for row in rank_rows)
    @test all(-1 <= row.spearman_vs_baseline <= 1 for row in rank_rows)
    baseline = only(row for row in rows if row.value == project.modal.eta)
    full_mean = sum(row.primitive_F for row in decompose_welfare(model).directed) /
        length(model.basis.policy_pairs)
    @test baseline.mean_directed_elasticity ≈ full_mean atol=1e-12 rtol=0
    @test_throws ArgumentError sensitivity_path(model, :alpha, [0.18])
    @test_throws ArgumentError sensitivity_path(model, :eta, [Inf])
    @test !TNW.condition_within_limit(Inf, 1e12)
    @test !TNW.condition_within_limit(1.0, Inf)

    bad_condition = replace_diagnostics(project; condition_limit=Inf)
    @test_throws ArgumentError validate(bad_condition)
    @test_throws ArgumentError build_model(bad_condition)
    bad_tolerance = replace_diagnostics(project; tolerance=NaN)
    @test_throws ArgumentError validate(bad_tolerance)
    @test_throws ArgumentError build_model(bad_tolerance)

    result = decompose_welfare(model)
    mktempdir() do first_dir
        mktempdir() do second_dir
            first_paths = write_results(result, first_dir; project)
            second_paths = write_results(result, second_dir; project)
            first_csv = filter(path -> endswith(path, ".csv"), first_paths)
            second_csv = filter(path -> endswith(path, ".csv"), second_paths)
            @test length(first_csv) == length(second_csv)
            @test TNW.file_sha256.(first_csv) == TNW.file_sha256.(second_csv)
        end
    end

    mktempdir() do directory
        mkpath(joinpath(directory, "data"))
        cp(joinpath(ROOT, "examples", "toy", "data", "nodes.csv"),
           joinpath(directory, "data", "nodes.csv"))
        cp(joinpath(ROOT, "examples", "toy", "data", "edge_modes.csv"),
           joinpath(directory, "data", "edge_modes.csv"))
        source = read(CONFIG, String)
        compact = split(source, "[sensitivity]"; limit=2)[1] *
                  "[sensitivity]\neta = [1.099]\n"
        config = joinpath(directory, "config.toml")
        write(config, compact)
        @test TNW.run_command("sensitivity", config) == 0
        sensitivity = joinpath(directory, "output", "sensitivity.csv")
        manifest = joinpath(directory, "output", "run_manifest.json")
        @test isfile(sensitivity)
        @test isfile(manifest)
        manifest_text = read(manifest, String)
        @test occursin("\"sensitivity.csv\":\"$(TNW.file_sha256(sensitivity))\"", manifest_text)
        @test occursin("\"package_version\":\"$(TNW.package_version())\"", manifest_text)
        @test occursin(r"\"git_dirty\":(?:true|false)", manifest_text)
        @test occursin("\"config_path\":\"config.toml\"", manifest_text)
        @test !occursin(directory, manifest_text)
    end
end

@testset "Node and mode permutation invariance" begin
    baseline = decompose_welfare(load_project(CONFIG))
    source_nodes = read(joinpath(ROOT, "examples", "toy", "data", "nodes.csv"), String)
    source_edges = read(joinpath(ROOT, "examples", "toy", "data", "edge_modes.csv"), String)
    source_config = read(CONFIG, String)
    mktempdir() do directory
        mkpath(joinpath(directory, "data"))
        node_lines = split(chomp(source_nodes), '\n')
        write(joinpath(directory, "data", "nodes.csv"),
              join([node_lines[1], node_lines[4], node_lines[2], node_lines[3]], '\n')*"\n")
        edge_lines = split(chomp(source_edges), '\n')
        write(joinpath(directory, "data", "edge_modes.csv"),
              join(vcat(edge_lines[1], reverse(edge_lines[2:end])), '\n')*"\n")
        permuted_config = replace(source_config,
            "mode_order = [\"road\", \"rail\"]" => "mode_order = [\"rail\", \"road\"]")
        write(joinpath(directory, "config.toml"), permuted_config)
        permuted = decompose_welfare(load_project(joinpath(directory, "config.toml")))
        base = by_edge(baseline.directed)
        alternative = by_edge(permuted.directed)
        @test keys(base) == keys(alternative)
        @test maximum(abs(base[id].primitive_F-alternative[id].primitive_F) for id in keys(base)) < 1e-11
        @test maximum(abs(base[id].realized_F-alternative[id].realized_F) for id in keys(base)) < 1e-11
    end
end

@testset "Coherent unit rescaling" begin
    baseline = decompose_welfare(load_project(CONFIG))
    mktempdir() do directory
        mkpath(joinpath(directory, "data"))
        write(joinpath(directory, "data", "nodes.csv"),
            "node_id,labor,income,longitude,latitude\n" *
            "A,10,12,-87.63,41.88\nB,11,10,-90.20,38.63\nC,9,8,-84.39,33.75\n")
        rows = split(chomp(read(joinpath(ROOT, "examples", "toy", "data", "edge_modes.csv"), String)), '\n')
        scaled = [rows[1]]
        for line in rows[2:end]
            cells = split(line, ','; keepempty=true)
            cells[6] = string(parse(Float64, cells[6])*30)
            push!(scaled, join(cells, ','))
        end
        write(joinpath(directory, "data", "edge_modes.csv"), join(scaled, '\n')*"\n")
        config = replace(read(CONFIG, String),
            "flow_conversion = \"none\"" => "flow_conversion = \"divide_by_world_income\"")
        write(joinpath(directory, "config.toml"), config)
        rescaled = decompose_welfare(load_project(joinpath(directory, "config.toml")))
        base = by_edge(baseline.directed)
        alternative = by_edge(rescaled.directed)
        @test maximum(abs(base[id].primitive_F-alternative[id].primitive_F) for id in keys(base)) < 1e-12
    end
end

end # module
