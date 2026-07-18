abstract type AbstractModalSpecification end

"Economically standard negative-power mode-choice logsum."
struct ChoiceLogsum <: AbstractModalSpecification
    eta::Float64
    function ChoiceLogsum(eta::Real)
        eta > 0 || throw(ArgumentError("eta must be positive"))
        new(Float64(eta))
    end
end

"Legacy positive-power component index used by the audited July 2026 RSUE package."
struct ComponentCES <: AbstractModalSpecification
    eta::Float64
    function ComponentCES(eta::Real)
        eta > 0 || throw(ArgumentError("eta must be positive"))
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
        all(v >= 0 for v in Base.values(lambdas)) ||
            throw(ArgumentError("edge-congestion elasticities must be nonnegative"))
        new(lambdas)
    end
end

struct EndpointTerminalCongestion <: AbstractCongestionSpecification
    lambda_by_mode::Dict{Symbol,Float64}
    endpoint_scale::Float64
    function EndpointTerminalCongestion(raw::AbstractDict, endpoint_scale::Real=1.0)
        lambdas = Dict(Symbol(k) => Float64(v) for (k, v) in raw)
        all(v >= 0 for v in Base.values(lambdas)) ||
            throw(ArgumentError("terminal-congestion elasticities must be nonnegative"))
        endpoint_scale >= 0 || throw(ArgumentError("endpoint_scale must be nonnegative"))
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
        sigma > 1 || throw(ArgumentError("sigma must exceed one"))
        route_curvature isa TheoremRouteCurvature ||
            throw(ArgumentError("independent route curvature is reserved but not supported by the current theorem"))
        new(Float64(alpha), Float64(beta), Float64(sigma), route_curvature)
    end
end

struct PolicySpecification
    mode::Symbol
    unit::Symbol
    shock_fraction::Float64
    function PolicySpecification(mode, unit, shock_fraction::Real)
        normalized = Symbol(unit)
        normalized in (:directed_arc, :physical_link, :both) ||
            throw(ArgumentError("policy unit must be directed_arc, physical_link, or both"))
        0 < shock_fraction < 1 ||
            throw(ArgumentError("shock_fraction must lie strictly between zero and one"))
        new(Symbol(mode), normalized, Float64(shock_fraction))
    end
end
