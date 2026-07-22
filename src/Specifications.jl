abstract type AbstractModalSpecification end

"Economically standard negative-power mode-choice logsum."
struct ChoiceLogsum <: AbstractModalSpecification
    eta::Float64
    function ChoiceLogsum(eta::Real)
        isfinite(eta) && eta > 0 ||
            throw(ArgumentError("eta must be finite and positive"))
        new(Float64(eta))
    end
end

"Legacy positive-power component index used by the audited July 2026 RSUE package."
struct ComponentCES <: AbstractModalSpecification
    eta::Float64
    function ComponentCES(eta::Real)
        isfinite(eta) && eta > 0 ||
            throw(ArgumentError("eta must be finite and positive"))
        new(Float64(eta))
    end
end

modal_power(spec::ChoiceLogsum) = -spec.eta
modal_power(spec::ComponentCES) = spec.eta
modal_name(::ChoiceLogsum) = "choice_logsum"
modal_name(::ComponentCES) = "component_ces"

abstract type AbstractRouteCurvature end
struct TheoremRouteCurvature <: AbstractRouteCurvature end

"Reserved extension point. The current theorem does not support an independent value."
struct IndependentRouteCurvature <: AbstractRouteCurvature
    value::Float64
end

abstract type AbstractCongestionSpecification end
struct NoCongestion <: AbstractCongestionSpecification end

struct EdgeCongestion <: AbstractCongestionSpecification
    lambda_by_mode::Dict{Symbol,Float64}
    function EdgeCongestion(raw::AbstractDict)
        lambdas = Dict(Symbol(k) => Float64(v) for (k, v) in raw)
        all(v -> isfinite(v) && v >= 0, Base.values(lambdas)) ||
            throw(ArgumentError("edge-congestion elasticities must be finite and nonnegative"))
        new(lambdas)
    end
end

struct EndpointTerminalCongestion <: AbstractCongestionSpecification
    lambda_by_mode::Dict{Symbol,Float64}
    endpoint_scale::Float64
    function EndpointTerminalCongestion(raw::AbstractDict, endpoint_scale::Real=1.0)
        lambdas = Dict(Symbol(k) => Float64(v) for (k, v) in raw)
        all(v -> isfinite(v) && v >= 0, Base.values(lambdas)) ||
            throw(ArgumentError("terminal-congestion elasticities must be finite and nonnegative"))
        isfinite(endpoint_scale) && endpoint_scale >= 0 ||
            throw(ArgumentError("endpoint_scale must be finite and nonnegative"))
        new(lambdas, Float64(endpoint_scale))
    end
end

struct CompositeCongestion <: AbstractCongestionSpecification
    edge::EdgeCongestion
    terminal::EndpointTerminalCongestion
end

edge_lambdas(::NoCongestion) = Dict{Symbol,Float64}()
edge_lambdas(spec::EdgeCongestion) = spec.lambda_by_mode
edge_lambdas(::EndpointTerminalCongestion) = Dict{Symbol,Float64}()
edge_lambdas(spec::CompositeCongestion) = spec.edge.lambda_by_mode

terminal_lambdas(::NoCongestion) = Dict{Symbol,Float64}()
terminal_lambdas(::EdgeCongestion) = Dict{Symbol,Float64}()
terminal_lambdas(spec::EndpointTerminalCongestion) = spec.lambda_by_mode
terminal_lambdas(spec::CompositeCongestion) = spec.terminal.lambda_by_mode

terminal_scale(::NoCongestion) = 0.0
terminal_scale(::EdgeCongestion) = 0.0
terminal_scale(spec::EndpointTerminalCongestion) = spec.endpoint_scale
terminal_scale(spec::CompositeCongestion) = spec.terminal.endpoint_scale

struct StructuralParameters
    alpha::Float64
    beta::Float64
    sigma::Float64
    route_curvature::AbstractRouteCurvature
    function StructuralParameters(alpha::Real, beta::Real, sigma::Real,
                                  route_curvature::AbstractRouteCurvature)
        all(isfinite, (alpha, beta, sigma)) ||
            throw(ArgumentError("alpha, beta, and sigma must be finite"))
        sigma > 1 || throw(ArgumentError("sigma must exceed one"))
        route_curvature isa TheoremRouteCurvature ||
            throw(ArgumentError("independent route curvature is reserved but not supported by the current theorem"))
        e = 1 + beta*(sigma-1) + alpha*sigma
        abs(e) > 1e-10 ||
            throw(ArgumentError("regularity violated: e is too close to zero"))
        abs(1 + alpha + beta) > 1e-10 ||
            throw(ArgumentError("regularity violated: 1+alpha+beta is too close to zero"))
        new(Float64(alpha), Float64(beta), Float64(sigma), route_curvature)
    end
end

struct PolicySpecification
    mode::Symbol
    unit::Symbol
    shock_fraction::Float64
    function PolicySpecification(mode, unit, shock_fraction::Real)
        mode_name = String(mode)
        isempty(strip(mode_name)) && throw(ArgumentError("policy mode must be nonempty"))
        normalized = Symbol(unit)
        normalized in (:directed_arc, :physical_link, :both) ||
            throw(ArgumentError("policy unit must be directed_arc, physical_link, or both"))
        isfinite(shock_fraction) && 0 < shock_fraction < 1 ||
            throw(ArgumentError("shock_fraction must be finite and lie strictly between zero and one"))
        new(Symbol(mode_name), normalized, Float64(shock_fraction))
    end
end

condition_within_limit(value::Real, limit::Real) =
    isfinite(value) && isfinite(limit) && value > 0 && value <= limit

function configured_active_modes(project, observed_modes)
    observed = Set(Symbol.(observed_modes))
    model = get(project.raw, "model", Dict{String,Any}())
    configured = get(model, "active_transport_modes", String[])
    modes = isempty(configured) ? observed : Set(Symbol.(configured))
    all(mode in observed for mode in modes) ||
        throw(ArgumentError("active_transport_modes contains a mode absent from the data"))
    project.policy.mode in modes ||
        throw(ArgumentError("active_transport_modes must include the policy mode"))
    return modes
end

function validate_congestion_modes(project, observed_modes)
    observed = Set(Symbol.(observed_modes))
    active = configured_active_modes(project, observed)
    for (channel, lambdas) in (("edge", edge_lambdas(project.congestion)),
                               ("terminal", terminal_lambdas(project.congestion)))
        for (mode, lambda) in lambdas
            mode in observed || throw(ArgumentError(
                "$channel-congestion mode '$mode' is absent from the data"))
            lambda == 0 || mode in active || throw(ArgumentError(
                "$channel congestion is positive for inactive mode '$mode'"))
        end
    end
    return active
end
