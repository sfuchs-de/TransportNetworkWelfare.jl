struct Project
    config_path::String
    root::String
    name::String
    schema_version::Int
    input::Dict{String,Any}
    spatial::AbstractSpatialSpecification
    parameters::StructuralParameters
    modal::AbstractModalSpecification
    congestion::AbstractCongestionSpecification
    policy::PolicySpecification
    output_dir::String
    sensitivity::Dict{Symbol,Vector{Float64}}
    condition_limit::Float64
    tolerance::Float64
    raw::Dict{String,Any}
end


# Backward-compatible positional constructor for callers written before spatial
# specifications were introduced. Economic geography remains the default.
function Project(config_path::String, root::String, name::String, schema_version::Int,
                 input::Dict{String,Any}, parameters::StructuralParameters,
                 modal::AbstractModalSpecification,
                 congestion::AbstractCongestionSpecification,
                 policy::PolicySpecification, output_dir::String,
                 sensitivity::Dict{Symbol,Vector{Float64}}, condition_limit::Float64,
                 tolerance::Float64, raw::Dict{String,Any})
    return Project(config_path, root, name, schema_version, input,
                   EconomicGeography(), parameters, modal, congestion, policy,
                   output_dir, sensitivity, condition_limit, tolerance, raw)
end

function expand_environment(value::AbstractString)
    return replace(value, r"\$\{[A-Za-z_][A-Za-z0-9_]*\}" => token -> begin
        variable = String(token)[3:end-1]
        haskey(ENV, variable) ||
            throw(ArgumentError("environment variable $variable is required by the configuration"))
        ENV[variable]
    end)
end

function resolve_path(root::AbstractString, value::AbstractString)
    expanded = expand_environment(value)
    return isabspath(expanded) ? normpath(expanded) : normpath(joinpath(root, expanded))
end

function parse_modal(model::AbstractDict)
    name = lowercase(String(get(model, "modal_specification", "choice_logsum")))
    eta = Float64(get(model, "eta", 1.0))
    name == "choice_logsum" && return ChoiceLogsum(eta)
    name == "component_ces" && return ComponentCES(eta)
    throw(ArgumentError("unknown modal specification: $name"))
end

function parse_spatial(model::AbstractDict)
    name = lowercase(String(get(model, "spatial_specification", "economic_geography")))
    name == "economic_geography" && return EconomicGeography()
    name == "urban_commuting" && return UrbanCommuting(get(model, "lambda", 0.0))
    throw(ArgumentError("unknown spatial specification: $name"))
end

function parse_congestion(raw::AbstractDict)
    name = lowercase(String(get(raw, "specification", "none")))
    edge_values = get(raw, "edge", Dict{String,Any}())
    terminal_values = get(raw, "terminal", Dict{String,Any}())
    endpoint_scale = Float64(get(raw, "endpoint_scale", 1.0))
    edge_source = lowercase(String(get(raw, "source", "mode")))
    edge_column = String(get(raw, "column", "congestion_elasticity"))
    edge_scale = Float64(get(raw, "scale", 1.0))
    edge_source in ("mode", "input_column") ||
        throw(ArgumentError("edge-congestion source must be mode or input_column"))
    edge_enabled = name in ("edge", "composite")
    edge_source == "input_column" && !edge_enabled && throw(ArgumentError(
        "source=input_column requires edge or composite congestion"))
    edge_source == "mode" && haskey(raw, "column") && throw(ArgumentError(
        "congestion.column is only valid with source=input_column"))
    edge_source == "mode" && haskey(raw, "scale") && throw(ArgumentError(
        "congestion.scale is only valid with source=input_column"))
    edge_specification() = edge_source == "mode" ? EdgeCongestion(edge_values) :
        EdgeCongestion(; input_column=edge_column, scale=edge_scale)
    edge_source == "input_column" && !isempty(edge_values) && throw(ArgumentError(
        "edge congestion cannot mix [congestion.edge] values with source=input_column"))
    name == "none" && return NoCongestion()
    name == "edge" && return edge_specification()
    name == "endpoint_terminal" &&
        return EndpointTerminalCongestion(terminal_values, endpoint_scale)
    name == "composite" && return CompositeCongestion(
        edge_specification(),
        EndpointTerminalCongestion(terminal_values, endpoint_scale),
    )
    throw(ArgumentError("unknown congestion specification: $name"))
end

function parse_route_curvature(value)
    value isa Real && return IndependentRouteCurvature(Float64(value))
    lowercase(string(value)) == "theorem" && return TheoremRouteCurvature()
    try
        return IndependentRouteCurvature(parse(Float64, string(value)))
    catch
        throw(ArgumentError("route_curvature must be 'theorem'; independent values are not supported"))
    end
end

function parse_sensitivity(raw::AbstractDict)
    paths = Dict{Symbol,Vector{Float64}}()
    for (name, values) in raw
        values isa AbstractVector ||
            throw(ArgumentError("sensitivity path '$name' must be an array"))
        parsed = Float64.(values)
        isempty(parsed) && throw(ArgumentError("sensitivity path '$name' must not be empty"))
        all(isfinite, parsed) ||
            throw(ArgumentError("sensitivity path '$name' contains a nonfinite value"))
        paths[Symbol(name)] = parsed
    end
    return paths
end

"Load and type-check a schema-versioned project configuration."
function load_project(config_path::AbstractString)
    path = abspath(config_path)
    isfile(path) || throw(ArgumentError("configuration file not found: $path"))
    raw = TOML.parsefile(path)
    version = Int(get(raw, "schema_version", 0))
    version == 1 || throw(ArgumentError("unsupported schema_version=$version; expected 1"))
    root = dirname(path)
    model = get(raw, "model", Dict{String,Any}())
    input = Dict{String,Any}(get(raw, "input", Dict{String,Any}()))
    isempty(input) && throw(ArgumentError("configuration requires an [input] section"))

    spatial = parse_spatial(model)
    curvature = parse_route_curvature(get(model, "route_curvature", "theorem"))
    sigma = if spatial isa UrbanCommuting
        haskey(model, "theta") ||
            throw(ArgumentError("urban_commuting requires model.theta"))
        theta = Float64(model["theta"])
        isfinite(theta) && theta > 0 ||
            throw(ArgumentError("urban commuting theta must be finite and positive"))
        if haskey(model, "sigma")
            supplied = Float64(model["sigma"])
            isapprox(supplied, theta + 1; atol=1e-12, rtol=0) ||
                throw(ArgumentError("for urban_commuting, sigma must equal theta+1 when both are supplied"))
        end
        theta + 1
    else
        haskey(model, "theta") && throw(ArgumentError(
            "model.theta is reserved for spatial_specification=urban_commuting"))
        get(model, "sigma", 0.0)
    end
    parameters = StructuralParameters(
        get(model, "alpha", 0.0),
        get(model, "beta", 0.0),
        sigma,
        curvature,
        check_trade_regularity=spatial isa EconomicGeography,
    )
    modal = parse_modal(model)
    congestion = parse_congestion(get(raw, "congestion", Dict{String,Any}()))
    policy_raw = get(raw, "policy", Dict{String,Any}())
    policy = PolicySpecification(
        get(policy_raw, "mode", "road"),
        get(policy_raw, "unit", "both"),
        get(policy_raw, "shock_fraction", 0.01),
    )
    output_raw = get(raw, "output", Dict{String,Any}())
    output_dir = resolve_path(root, String(get(output_raw, "directory", "output")))
    diagnostics = get(raw, "diagnostics", Dict{String,Any}())
    condition_limit = Float64(get(diagnostics, "condition_limit", 1e12))
    tolerance = Float64(get(diagnostics, "tolerance", 1e-10))
    isfinite(condition_limit) && 1 < condition_limit <= 1e12 ||
        throw(ArgumentError("condition_limit must be finite and lie in (1, 1e12]"))
    isfinite(tolerance) && tolerance > 0 ||
        throw(ArgumentError("diagnostic tolerance must be finite and positive"))

    return Project(
        path,
        root,
        String(get(raw, "name", splitext(basename(path))[1])),
        version,
        input,
        spatial,
        parameters,
        modal,
        congestion,
        policy,
        output_dir,
        parse_sensitivity(get(raw, "sensitivity", Dict{String,Any}())),
        condition_limit,
        tolerance,
        Dict{String,Any}(raw),
    )
end

function input_path(project::Project, key::String)
    haskey(project.input, key) || throw(ArgumentError("[input] requires '$key'"))
    return resolve_path(project.root, String(project.input[key]))
end
