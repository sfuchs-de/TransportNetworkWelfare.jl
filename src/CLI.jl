function usage(io::IO=stdout)
    println(io, "Usage:")
    println(io, "  julia --project=. bin/tnw.jl init DIRECTORY [economic_geography|urban_commuting]")
    println(io, "  julia --project=. bin/tnw.jl COMMAND CONFIG")
    println(io, "Commands: init, validate, analyze, analyze-edge-local, decompose, sensitivity, replicate-rsue")
end

function print_summary(value)
    println(json_value(value))
end

function require_verified(result)
    get(result.diagnostics, "verified", false) ||
        error("analysis failed its numerical verification gate")
    return result
end

function initialization_template(spatial_specification)
    specification = replace(lowercase(strip(string(spatial_specification))), "-" => "_")
    if specification == "economic_geography"
        return specification, "toy"
    elseif specification == "urban_commuting"
        return specification, "urban_multimodal"
    end
    throw(ArgumentError(
        "initialization model must be economic_geography or urban_commuting, got " *
        repr(spatial_specification)))
end

function write_initialization_readme(path, specification)
    node_columns = specification == "economic_geography" ?
        "labor and income" : "residents and employment"
    write(path, """# Transport Network Welfare project

This directory is a portable `$specification` application for
`TransportNetworkWelfare.jl`. The committed seed files run as supplied. Replace
them with model-ready inputs only after recording each raw source and
transformation in `sources.toml` and `scripts/prepare_inputs.jl`.

The node table requires $node_columns. The edge-mode table requires directed,
positive model flows in one common normalization. The package validates these
tables but does not silently balance, symmetrize, geocode, or convert physical
counts into economic flows.

From the package checkout, run:

```bash
PKG=/path/to/TransportNetworkWelfare.jl
julia --project="\$PKG" "\$PKG/bin/tnw.jl" validate config.toml
julia --project="\$PKG" "\$PKG/bin/tnw.jl" analyze config.toml
julia --project="\$PKG" "\$PKG/bin/tnw.jl" decompose config.toml
```

Keep raw downloads outside Git unless their licenses permit redistribution.
Archive `sources.toml`, the preprocessing code, model-ready CSVs, configuration,
and run manifest for every accepted result vintage. See
`docs/src/own-data.md` in the package for the full data and GIS workflow.
""")
end

function write_source_manifest(path, specification)
    write(path, """schema_version = 1
spatial_specification = "$specification"

[sources]

[processing]
entrypoint = "scripts/prepare_inputs.jl"
model_ready_nodes = "data/nodes.csv"
model_ready_edge_modes = "data/edge_modes.csv"
notes = "Replace the seed rows through a versioned, explicit preprocessing step."
""")
end

function write_preparation_entrypoint(path)
    write(path, """#!/usr/bin/env julia

# Replace this seed check with the application's versioned raw-to-model-ready
# transformations. Keep downloads outside Git unless redistribution is allowed.
const ROOT = normpath(joinpath(@__DIR__, ".."))
const REQUIRED = (
    joinpath(ROOT, "data", "nodes.csv"),
    joinpath(ROOT, "data", "edge_modes.csv"),
    joinpath(ROOT, "sources.toml"),
)

for input in REQUIRED
    isfile(input) || error("missing required project input: \$input")
end

println("Model-ready seed inputs are present.")
println("Document raw sources and transformations before replacing them.")
""")
end

"Create a runnable generic CSV/TOML project from a bundled model template."
function initialize_project(destination::AbstractString;
                            spatial_specification="economic_geography")
    specification, template_name =
        initialization_template(spatial_specification)
    target = abspath(destination)
    if ispath(target)
        isdir(target) || throw(ArgumentError("initialization target is not a directory: $target"))
        isempty(readdir(target)) ||
            throw(ArgumentError("initialization target must be absent or empty: $target"))
    else
        mkpath(target)
    end

    template = normpath(joinpath(@__DIR__, "..", "examples", template_name))
    copied_files = (
        "config.toml",
        joinpath("data", "nodes.csv"),
        joinpath("data", "edge_modes.csv"),
    )
    all(relative -> isfile(joinpath(template, relative)), copied_files) ||
        error("bundled project template is incomplete")
    for relative in copied_files
        output = joinpath(target, relative)
        mkpath(dirname(output))
        cp(joinpath(template, relative), output)
    end
    mkpath(joinpath(target, "scripts"))
    mkpath(joinpath(target, "figures"))
    write_initialization_readme(joinpath(target, "README.md"), specification)
    write_source_manifest(joinpath(target, "sources.toml"), specification)
    write_preparation_entrypoint(joinpath(target, "scripts", "prepare_inputs.jl"))
    files = [
        "README.md",
        "sources.toml",
        "config.toml",
        joinpath("scripts", "prepare_inputs.jl"),
        joinpath("data", "nodes.csv"),
        joinpath("data", "edge_modes.csv"),
    ]
    return (;
        status="ok",
        project_root=target,
        config=joinpath(target, "config.toml"),
        spatial_specification=specification,
        files,
    )
end

function run_command(command::String, config::String;
                     spatial_specification="economic_geography")
    command in ("init", "validate", "analyze", "analyze-edge-local", "decompose", "sensitivity", "replicate-rsue") ||
        throw(ArgumentError("unknown command: $command"))
    if command == "init"
        print_summary(initialize_project(
            config; spatial_specification=spatial_specification))
        return 0
    end
    project = load_project(config)
    config_label = relpath(project.config_path, project.root)
    if command == "validate"
        report = validate(project)
        print_summary(report)
        return 0
    end
    if command == "analyze"
        result = require_verified(welfare_effects(project))
        paths = write_results(result, project.output_dir; project,
            command="analyze $config_label")
        print_summary(Dict("status" => "ok", "outputs" => paths))
    elseif command == "analyze-edge-local"
        result = require_verified(edge_local_welfare_effects(project))
        paths = write_results(result, project.output_dir; project,
            command="analyze-edge-local $config_label")
        print_summary(Dict("status" => "ok", "outputs" => paths))
    elseif command == "decompose"
        model = build_model(project)
        result = require_verified(decompose_welfare(model))
        paths = write_results(result, project.output_dir; project,
            command="decompose $config_label")
        print_summary(Dict("status" => "ok", "outputs" => paths))
    elseif command == "sensitivity"
        model = build_welfare_model(project)
        rows = all_sensitivity_paths(model)
        isempty(rows) && throw(ArgumentError("the configuration declares no sensitivity paths"))
        path = write_table(joinpath(project.output_dir, "sensitivity.csv"), rows)
        baseline = require_verified(welfare_effects(model))
        baseline.diagnostics["sensitivity_rows"] = length(rows)
        baseline.diagnostics["sensitivity_verified"] = all(row.verified for row in rows)
        baseline.diagnostics["verified"] &= baseline.diagnostics["sensitivity_verified"]
        manifest = write_run_manifest(
            project, baseline.diagnostics, [path], project.output_dir;
            command="sensitivity $config_label",
        )
        print_summary(Dict(
            "status" => "ok", "outputs" => [path, manifest], "rows" => length(rows)))
    elseif command == "replicate-rsue"
        model = build_model(project)
        adapter = lowercase(String(get(project.input, "adapter", "")))
        adapter in ("rsue_frozen_2026_07_12", "rsue_census_ports_2017_v1") ||
            throw(ArgumentError("replicate-rsue requires a supported RSUE adapter"))
        result = require_verified(decompose_welfare(model))
        extra_outputs = String[]
        if !isempty(project.sensitivity)
            sensitivity = all_sensitivity_paths(model)
            result.diagnostics["sensitivity_rows"] = length(sensitivity)
            result.diagnostics["sensitivity_verified"] = all(row.verified for row in sensitivity)
            result.diagnostics["verified"] &= result.diagnostics["sensitivity_verified"]
            push!(extra_outputs,
                write_table(joinpath(project.output_dir, "sensitivity.csv"), sensitivity))
        end
        paths = write_results(result, project.output_dir; project,
            command="replicate-rsue $config_label", extra_outputs)
        print_summary(Dict("status" => "ok", "outputs" => paths))
    else
        throw(ArgumentError("unknown command: $command"))
    end
    return 0
end

function main(args=ARGS)
    if length(args) == 1 && String(args[1]) in ("help", "--help", "-h")
        usage()
        return 0
    end
    if !isempty(args) && String(args[1]) == "init"
        length(args) in (2, 3) || (usage(stderr); return 2)
        specification = length(args) == 3 ?
            String(args[3]) : "economic_geography"
        try
            return run_command(
                "init", String(args[2]);
                spatial_specification=specification)
        catch error_value
            println(stderr, "ERROR: ", sprint(showerror, error_value))
            return 1
        end
    end
    length(args) == 2 || (usage(stderr); return 2)
    try
        return run_command(String(args[1]), String(args[2]))
    catch error_value
        println(stderr, "ERROR: ", sprint(showerror, error_value))
        return 1
    end
end
