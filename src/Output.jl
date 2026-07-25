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
    io = IOBuffer()
    print(io, '"')
    for character in value
        if character == '"'
            print(io, "\\\"")
        elseif character == '\\'
            print(io, "\\\\")
        elseif character == '\b'
            print(io, "\\b")
        elseif character == '\f'
            print(io, "\\f")
        elseif character == '\n'
            print(io, "\\n")
        elseif character == '\r'
            print(io, "\\r")
        elseif character == '\t'
            print(io, "\\t")
        elseif Int(character) < 0x20
            @printf(io, "\\u%04x", Int(character))
        else
            print(io, character)
        end
    end
    print(io, '"')
    return String(take!(io))
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
    if value isa AbstractDict
        keys_by_string = Dict{String,Any}()
        for key in keys(value)
            text = string(key)
            haskey(keys_by_string, text) && throw(ArgumentError(
                "JSON object contains keys that both encode as '$text'"))
            keys_by_string[text] = key
        end
        return "{" * join((json_escape(text)*":"*json_value(value[keys_by_string[text]])
            for text in sort!(collect(keys(keys_by_string)))), ',') * "}"
    end
    if value isa Tuple || value isa AbstractVector
        return "[" * join(json_value.(collect(value)), ',') * "]"
    end
    throw(ArgumentError("unsupported JSON value of type $(typeof(value))"))
end

function package_git_state()
    root = normpath(joinpath(@__DIR__, ".."))
    try
        commit = readchomp(pipeline(`git -C $root rev-parse HEAD`; stderr=devnull))
        status = readchomp(pipeline(
            `git -C $root status --porcelain --untracked-files=normal`; stderr=devnull))
        return (; commit, dirty=!isempty(status))
    catch
        return (; commit="uncommitted", dirty=true)
    end
end

function package_version()
    root = normpath(joinpath(@__DIR__, ".."))
    metadata = TOML.parsefile(joinpath(root, "Project.toml"))
    return String(metadata["version"])
end

function environment_metadata()
    project_path = Base.active_project()
    manifest_path = project_path === nothing ? nothing : joinpath(dirname(project_path), "Manifest.toml")
    return Dict{String,Any}(
        "active_project" => project_path === nothing ? missing : basename(project_path),
        "manifest_sha256" => manifest_path !== nothing && isfile(manifest_path) ?
            file_sha256(manifest_path) : missing,
        "blas" => string(LinearAlgebra.BLAS.get_config()),
    )
end

function run_manifest(project::Project, diagnostics::AbstractDict, outputs; command="api")
    git = package_git_state()
    output_paths = String.(collect(outputs))
    all(isfile, output_paths) || throw(ArgumentError("every manifest output must exist"))
    output_names = basename.(output_paths)
    length(unique(output_names)) == length(output_names) ||
        throw(ArgumentError("manifest output basenames must be unique"))
    return Dict{String,Any}(
        "schema_version" => 1,
        "created_at_utc" => string(now(UTC)),
        "package" => "TransportNetworkWelfare",
        "package_version" => package_version(),
        "git_commit" => git.commit,
        "git_dirty" => git.dirty,
        "julia_version" => string(VERSION),
        "environment" => environment_metadata(),
        "command" => command,
        "config_path" => relpath(project.config_path, project.root),
        "config_sha256" => file_sha256(project.config_path),
        "input_hashes" => diagnostics["input_hashes"],
        "transformations" => diagnostics["transformations"],
        "model_variant" => Dict(
            "spatial_closure" => spatial_name(project.spatial),
            "modal" => modal_name(project.modal),
            "congestion" => string(nameof(typeof(project.congestion))),
            "route_curvature" => "theorem",
            "route_curvature_value" => project.spatial isa UrbanCommuting ?
                commuting_theta(project.parameters) : project.parameters.sigma-1,
            "policy_mode" => String(project.policy.mode),
            "policy_unit" => String(project.policy.unit),
        ),
        "parameters" => Dict(
            "alpha" => project.parameters.alpha,
            "beta" => project.parameters.beta,
            "sigma" => project.parameters.sigma,
            "theta" => project.spatial isa UrbanCommuting ?
                commuting_theta(project.parameters) : missing,
            "eta" => project.modal.eta,
            "edge_congestion" => Dict(string(k) => v for (k, v) in edge_lambdas(project.congestion)),
            "edge_congestion_source" => edge_congestion_source(project.congestion),
            "edge_congestion_input_column" => something(
                edge_input_column(project.congestion), missing),
            "edge_congestion_scale" => edge_congestion_scale(project.congestion),
            "terminal_congestion" => Dict(string(k) => v for (k, v) in terminal_lambdas(project.congestion)),
            "terminal_endpoint_scale" => terminal_scale(project.congestion),
        ),
        "condition_numbers" => Dict(k => v for (k, v) in diagnostics if startswith(k, "condition_")),
        "verification_status" => diagnostics["verified"] ? "passed" : "failed",
        "diagnostics" => diagnostics,
        "output_hashes" => Dict(basename(path) => file_sha256(path) for path in output_paths),
    )
end

run_manifest(project::Project, result, outputs; command="api") =
    run_manifest(project, result.diagnostics, outputs; command)

function write_run_manifest(project::Project, diagnostics::AbstractDict, outputs,
                            output_dir::AbstractString; command::AbstractString="api")
    mkpath(output_dir)
    manifest = run_manifest(project, diagnostics, outputs; command)
    manifest_path = joinpath(output_dir, "run_manifest.json")
    open(manifest_path, "w") do io
        println(io, json_value(manifest))
    end
    return manifest_path
end

"Write result CSVs, diagnostics, and an optional run manifest."
function write_results(result::Union{WelfareResults,DecompositionResults},
                       output_dir::AbstractString;
                       project::Union{Nothing,Project}=nothing,
                       command::AbstractString="api",
                       extra_outputs::Vector{String}=String[])
    mkpath(output_dir)
    prefix = result isa DecompositionResults ? "decomposition" : "welfare"
    outputs = String[]
    !isempty(result.directed) &&
        push!(outputs, write_table(joinpath(output_dir, "$(prefix)_directed.csv"), result.directed))
    !isempty(result.physical) &&
        push!(outputs, write_table(joinpath(output_dir, "$(prefix)_physical.csv"), result.physical))
    diagnostics_path = joinpath(output_dir, "diagnostics.json")
    open(diagnostics_path, "w") do io
        println(io, json_value(result.diagnostics))
    end
    push!(outputs, diagnostics_path)
    append!(outputs, extra_outputs)
    if project !== nothing
        manifest_path = write_run_manifest(
            project, result.diagnostics, outputs, output_dir; command)
        push!(outputs, manifest_path)
    end
    return outputs
end
