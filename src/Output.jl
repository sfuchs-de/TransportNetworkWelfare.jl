function csv_escape(value)
    value === missing && return ""
    value isa AbstractFloat && return isfinite(value) ? @sprintf("%.17g", value) : ""
    text = string(value)
    occursin(r"[\",\n\r]", text) || return text
    return "\"" * replace(text, "\"" => "\"\"") * "\""
end

function write_table(path::AbstractString, rows::Vector{<:NamedTuple})
    mkpath(dirname(path))
    isempty(rows) && return path
    fields = propertynames(first(rows))
    open(path, "w") do io
        println(io, join(string.(fields), ','))
        for row in rows
            println(io, join((csv_escape(getproperty(row, field)) for field in fields), ','))
        end
    end
    return path
end

function json_escape(value::AbstractString)
    value = replace(value, '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n",
                    '\r' => "\\r", '\t' => "\\t")
    return "\"$value\""
end

function json_value(value)
    value === nothing && return "null"
    value === missing && return "null"
    value isa Bool && return value ? "true" : "false"
    value isa Integer && return string(value)
    value isa AbstractFloat && return isfinite(value) ? @sprintf("%.17g", value) : "null"
    value isa AbstractString && return json_escape(value)
    value isa Symbol && return json_escape(String(value))
    value isa NamedTuple && return json_value(Dict(string(k) => getproperty(value, k) for k in keys(value)))
    value isa AbstractDict && return "{" * join((json_escape(string(k))*":"*json_value(value[k])
        for k in sort!(collect(keys(value)); by=string)), ',') * "}"
    if value isa Tuple || value isa AbstractVector
        return "[" * join(json_value.(collect(value)), ',') * "]"
    end
    return json_escape(string(value))
end

function package_commit()
    root = normpath(joinpath(@__DIR__, ".."))
    try
        return readchomp(pipeline(`git -C $root rev-parse HEAD`; stderr=devnull))
    catch
        return "uncommitted"
    end
end

function run_manifest(project::Project, result, outputs; command="api")
    package_root = normpath(joinpath(@__DIR__, ".."))
    return Dict{String,Any}(
        "schema_version" => 1,
        "created_at_utc" => string(now(UTC)),
        "package" => "TransportNetworkWelfare",
        "package_version" => "0.1.0",
        "git_commit" => package_commit(),
        "julia_version" => string(VERSION),
        "command" => command,
        "config_path" => relpath(project.config_path, package_root),
        "config_sha256" => file_sha256(project.config_path),
        "input_hashes" => result.diagnostics["input_hashes"],
        "transformations" => result.diagnostics["transformations"],
        "model_variant" => Dict(
            "modal" => modal_name(project.modal),
            "congestion" => string(nameof(typeof(project.congestion))),
            "route_curvature" => "theorem",
            "policy_unit" => String(project.policy.unit),
        ),
        "parameters" => Dict(
            "alpha" => project.parameters.alpha,
            "beta" => project.parameters.beta,
            "sigma" => project.parameters.sigma,
            "eta" => project.modal.eta,
            "edge_congestion" => Dict(string(k) => v for (k, v) in edge_lambdas(project.congestion)),
            "terminal_congestion" => Dict(string(k) => v for (k, v) in terminal_lambdas(project.congestion)),
            "terminal_endpoint_scale" => terminal_scale(project.congestion),
        ),
        "condition_numbers" => Dict(k => v for (k, v) in result.diagnostics if startswith(k, "condition_")),
        "verification_status" => result.diagnostics["verified"] ? "passed" : "failed",
        "diagnostics" => result.diagnostics,
        "output_hashes" => Dict(basename(path) => file_sha256(path) for path in outputs),
    )
end

function enrich_diagnostics!(result, model::TransportModel)
    result.diagnostics["input_hashes"] = model.data.input_hashes
    result.diagnostics["transformations"] = model.data.transformations
    result.diagnostics["shock_fraction"] = model.project.policy.shock_fraction
    result.diagnostics["one_percent_gain_scale"] = 100*model.project.policy.shock_fraction
    return result
end

"Write result CSVs, diagnostics, and an optional run manifest."
function write_results(result::Union{WelfareResults,DecompositionResults},
                       output_dir::AbstractString;
                       project::Union{Nothing,Project}=nothing,
                       command::AbstractString="api")
    mkpath(output_dir)
    prefix = result isa DecompositionResults ? "decomposition" : "welfare"
    outputs = String[]
    push!(outputs, write_table(joinpath(output_dir, "$(prefix)_directed.csv"), result.directed))
    !isempty(result.physical) &&
        push!(outputs, write_table(joinpath(output_dir, "$(prefix)_physical.csv"), result.physical))
    diagnostics_path = joinpath(output_dir, "diagnostics.json")
    open(diagnostics_path, "w") do io
        println(io, json_value(result.diagnostics))
    end
    push!(outputs, diagnostics_path)
    if project !== nothing
        manifest = run_manifest(project, result, outputs; command)
        manifest_path = joinpath(output_dir, "run_manifest.json")
        open(manifest_path, "w") do io
            println(io, json_value(manifest))
        end
        push!(outputs, manifest_path)
    end
    return outputs
end
