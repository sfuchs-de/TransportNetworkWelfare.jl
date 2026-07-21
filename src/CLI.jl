function usage(io::IO=stdout)
    println(io, "Usage: julia --project=. bin/tnw.jl COMMAND CONFIG")
    println(io, "Commands: validate, analyze, decompose, sensitivity, replicate-rsue")
end

function print_summary(value)
    println(json_value(value))
end

function require_verified(result)
    get(result.diagnostics, "verified", false) ||
        error("analysis failed its numerical verification gate")
    return result
end

function run_command(command::String, config::String)
    command in ("validate", "analyze", "decompose", "sensitivity", "replicate-rsue") ||
        throw(ArgumentError("unknown command: $command"))
    project = load_project(config)
    config_label = relpath(project.config_path, project.root)
    if command == "validate"
        report = validate(project)
        print_summary(report)
        return 0
    end
    model = build_model(project)
    if command == "analyze"
        result = require_verified(welfare_effects(model))
        paths = write_results(result, project.output_dir; project,
            command="analyze $config_label")
        print_summary(Dict("status" => "ok", "outputs" => paths))
    elseif command == "decompose"
        result = require_verified(decompose_welfare(model))
        paths = write_results(result, project.output_dir; project,
            command="decompose $config_label")
        print_summary(Dict("status" => "ok", "outputs" => paths))
    elseif command == "sensitivity"
        rows = all_sensitivity_paths(model)
        isempty(rows) && throw(ArgumentError("the configuration declares no sensitivity paths"))
        path = write_table(joinpath(project.output_dir, "sensitivity.csv"), rows)
        baseline = require_verified(decompose_welfare(model))
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
    length(args) == 2 || (usage(stderr); return 2)
    try
        return run_command(String(args[1]), String(args[2]))
    catch error_value
        println(stderr, "ERROR: ", sprint(showerror, error_value))
        return 1
    end
end
