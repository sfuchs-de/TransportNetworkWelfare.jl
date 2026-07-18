function usage(io::IO=stdout)
    println(io, "Usage: julia --project=. bin/tnw.jl COMMAND CONFIG")
    println(io, "Commands: validate, analyze, decompose, sensitivity, replicate-rsue")
end

function print_summary(value)
    println(json_value(value))
end

function run_command(command::String, config::String)
    project = load_project(config)
    if command == "validate"
        report = validate(project)
        print_summary(report)
        return 0
    end
    model = build_model(project)
    if command == "analyze"
        result = enrich_diagnostics!(welfare_effects(model), model)
        paths = write_results(result, project.output_dir; project, command="analyze $config")
        print_summary(Dict("status" => "ok", "outputs" => paths))
    elseif command == "decompose"
        result = enrich_diagnostics!(decompose_welfare(model), model)
        paths = write_results(result, project.output_dir; project, command="decompose $config")
        print_summary(Dict("status" => "ok", "outputs" => paths))
    elseif command == "sensitivity"
        rows = all_sensitivity_paths(model)
        path = write_table(joinpath(project.output_dir, "sensitivity.csv"), rows)
        print_summary(Dict("status" => "ok", "output" => path, "rows" => length(rows)))
    elseif command == "replicate-rsue"
        lowercase(String(get(project.input, "adapter", ""))) == "rsue_frozen_2026_07_12" ||
            throw(ArgumentError("replicate-rsue requires the frozen RSUE adapter"))
        result = enrich_diagnostics!(decompose_welfare(model), model)
        paths = write_results(result, project.output_dir; project, command="replicate-rsue $config")
        if !isempty(project.sensitivity)
            sensitivity = all_sensitivity_paths(model)
            push!(paths, write_table(joinpath(project.output_dir, "sensitivity.csv"), sensitivity))
        end
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
