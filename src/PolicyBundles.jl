"One weighted edge-mode component of a coordinated primitive-cost shock."
struct PolicyBundleEntry
    bundle_id::String
    edge_id::String
    mode::Symbol
    weight::Float64
    function PolicyBundleEntry(bundle_id, edge_id, mode, weight::Real)
        bundle = strip(String(bundle_id))
        edge = strip(String(edge_id))
        isempty(bundle) && throw(ArgumentError("policy bundle_id must be nonempty"))
        isempty(edge) && throw(ArgumentError("policy bundle edge_id must be nonempty"))
        mode_name = strip(String(mode))
        isempty(mode_name) && throw(ArgumentError("policy bundle mode must be nonempty"))
        isfinite(weight) && weight > 0 ||
            throw(ArgumentError("policy bundle weight must be finite and positive"))
        new(bundle, edge, Symbol(mode_name), Float64(weight))
    end
end

"Load a sparse set of coordinated primitive-cost shocks from CSV."
function load_policy_bundles(path::AbstractString)
    isfile(path) || throw(ArgumentError("policy-bundle file not found: $path"))
    table = CSV.File(path; normalizenames=false)
    names = Set(Symbol.(propertynames(table)))
    required = Set((:bundle_id, :edge_id, :mode, :weight))
    required ⊆ names ||
        throw(ArgumentError("policy-bundle CSV requires bundle_id, edge_id, mode, and weight"))
    entries = PolicyBundleEntry[]
    seen = Set{Tuple{String,String,Symbol}}()
    for row in table
        entry = PolicyBundleEntry(
            getproperty(row, :bundle_id),
            getproperty(row, :edge_id),
            getproperty(row, :mode),
            Float64(getproperty(row, :weight)),
        )
        key = (entry.bundle_id, entry.edge_id, entry.mode)
        key in seen && throw(ArgumentError(
            "duplicate policy-bundle entry $(entry.bundle_id), $(entry.edge_id), $(entry.mode)"))
        push!(seen, key)
        push!(entries, entry)
    end
    isempty(entries) && throw(ArgumentError("policy-bundle CSV contains no entries"))
    sort!(entries; by=entry -> (entry.bundle_id, String(entry.mode), entry.edge_id))
    return entries
end

function bundle_rows(rows::AbstractVector{<:NamedTuple},
                     entries::AbstractVector{PolicyBundleEntry};
                     shock_fraction::Real)
    isfinite(shock_fraction) && 0 < shock_fraction < 1 ||
        throw(ArgumentError("shock_fraction must be finite and lie in (0, 1)"))
    isempty(rows) && throw(ArgumentError(
        "policy bundles require directed policy results"))
    available = Dict{Tuple{String,Symbol},NamedTuple}()
    for row in rows
        key = (String(row.edge_id), Symbol(row.mode))
        haskey(available, key) && throw(ArgumentError(
            "directed results contain duplicate edge-mode $key"))
        available[key] = row
    end
    grouped = Dict{String,Vector{PolicyBundleEntry}}()
    for entry in entries
        haskey(available, (entry.edge_id, entry.mode)) || throw(ArgumentError(
            "policy bundle $(entry.bundle_id) references missing edge-mode " *
            "$(entry.edge_id), $(entry.mode)"))
        push!(get!(grouped, entry.bundle_id, PolicyBundleEntry[]), entry)
    end
    output = NamedTuple[]
    for bundle_id in sort!(collect(keys(grouped)))
        group = grouped[bundle_id]
        modes = unique(entry.mode for entry in group)
        length(modes) == 1 || throw(ArgumentError(
            "policy bundle $bundle_id must contain one transport mode"))
        hulten = sum(entry.weight*available[(entry.edge_id, entry.mode)].hulten
                     for entry in group)
        realized = sum(entry.weight*available[(entry.edge_id, entry.mode)].realized_F
                       for entry in group)
        primitive = sum(entry.weight*available[(entry.edge_id, entry.mode)].primitive_F
                        for entry in group)
        push!(output, (;
            bundle_id,
            mode=String(only(modes)),
            entries=length(group),
            total_weight=sum(entry.weight for entry in group),
            hulten,
            realized_F=realized,
            primitive_F=primitive,
            chi_effective=effective_ratio(realized, primitive, hulten),
            primitive_pass_through=realized-primitive,
            shock_fraction=Float64(shock_fraction),
            traditional_gain_pct=100*shock_fraction*hulten,
            extended_gain_pct=100*shock_fraction*primitive,
        ))
    end
    return output
end

"Aggregate directed welfare derivatives into declared coordinated policy bundles."
function bundle_welfare_effects(result::Union{WelfareResults,DecompositionResults},
                                entries::AbstractVector{PolicyBundleEntry};
                                shock_fraction::Real=0.01)
    return bundle_rows(result.directed, entries; shock_fraction)
end

function bundle_welfare_effects(model::TransportModel,
                                entries::AbstractVector{PolicyBundleEntry})
    modes = unique(entry.mode for entry in entries)
    length(modes) == 1 || throw(ArgumentError(
        "a model-level policy-bundle evaluation requires one transport mode"))
    only(modes) == model.project.policy.mode || throw(ArgumentError(
        "policy-bundle mode $(only(modes)) does not match model policy mode " *
        "$(model.project.policy.mode)"))
    result = welfare_effects(model)
    return bundle_welfare_effects(
        result, entries; shock_fraction=model.project.policy.shock_fraction)
end
