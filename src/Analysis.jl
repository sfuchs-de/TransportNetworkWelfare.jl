function enrich_diagnostics!(result, model::TransportModel)
    result.diagnostics["input_hashes"] = model.data.input_hashes
    result.diagnostics["transformations"] = model.data.transformations
    result.diagnostics["shock_fraction"] = model.project.policy.shock_fraction
    result.diagnostics["one_percent_gain_scale"] = 100*model.project.policy.shock_fraction
    return result
end


function welfare_rows(model::TransportModel)
    data, basis, closures = model.data, model.basis, model.closures
    q = AdjointRSUE.welfare_gradient(data.omega, closures.c)
    realized_forcing = closures.B * basis.Sagg[:, basis.policy_pairs]
    realized = operator_gain(closures.F, q, realized_forcing)
    primitive = primitive_forcing(model)
    primitive_values = operator_gain(closures.F, q, primitive.forcing)
    rows = NamedTuple[]
    for r in eachindex(basis.policy_pairs)
        k, l = basis.policy_edges[r]
        Xi = data.mode_flows[basis.policy_mode][k, l]
        push!(rows, (;
            edge_id=basis.policy_edge_ids[r],
            physical_link_id=basis.policy_physical_ids[r],
            origin=data.node_ids[k], destination=data.node_ids[l],
            origin_index=k, destination_index=l,
            mode=String(model.project.policy.mode), hulten=Xi,
            realized_F=realized[r], primitive_F=primitive_values[r],
            chi_effective=effective_ratio(realized[r], primitive_values[r], Xi),
            primitive_pass_through=realized[r]-primitive_values[r],
        ))
    end
    return rows, primitive
end


function aggregate_welfare_physical(rows::AbstractVector{<:NamedTuple})
    grouped = Dict{String,Vector{NamedTuple}}()
    for row in rows
        push!(get!(grouped, row.physical_link_id, NamedTuple[]), row)
    end
    output = NamedTuple[]
    for link in sort!(collect(keys(grouped)))
        group = grouped[link]
        length(group) == 2 || throw(ArgumentError(
            "physical link $link must have exactly two policy directions"))
        a, b = group
        a.origin == b.destination && a.destination == b.origin ||
            throw(ArgumentError("physical link $link does not contain opposite directions"))
        hulten = sum(row.hulten for row in group)
        realized = sum(row.realized_F for row in group)
        primitive = sum(row.primitive_F for row in group)
        push!(output, (;
            physical_link_id=link, directions=2,
            endpoint_a=min(a.origin, a.destination), endpoint_b=max(a.origin, a.destination),
            hulten, realized_F=realized, primitive_F=primitive,
            chi_effective=effective_ratio(realized, primitive, hulten),
            primitive_pass_through=realized-primitive,
        ))
    end
    return output
end


function welfare_diagnostics(model::TransportModel, rows, primitive)
    route = model.basis.diagnostics
    finite_rows = all(row -> all(value ->
        !(value isa AbstractFloat) || isfinite(value), row), rows)
    verified = finite_rows && primitive.residual <= model.project.tolerance
    return Dict{String,Any}(
        "verified" => verified,
        "finite_outputs" => finite_rows,
        "closure_level" => "welfare",
        "nodes" => model.data.N,
        "directed_edges" => length(model.data.edges),
        "active_edge_mode_pairs" => model.basis.P,
        "directed_policy_arcs" => length(rows),
        "modal_specification" => modal_name(model.project.modal),
        "congestion_specification" => string(nameof(typeof(model.project.congestion))),
        "condition_F" => model.closures.conditions.F,
        "condition_transport_F" => model.closures.transport.F.condition,
        "route_spectral_radius" => route.spectral_radius,
        "route_absorption_error" => route.absorption_error,
        "route_edge_error" => route.edge_error,
        "soft_route_edge_relative_error" => route.soft_edge_relative_error,
        "primitive_transport_residual" => primitive.residual,
        "undefined_chi_effective" => count(ismissing, getproperty.(rows, :chi_effective)),
        "mean_directed_primitive_elasticity" => mean(row.primitive_F for row in rows),
        "mean_directed_hulten_elasticity" => mean(row.hulten for row in rows),
    )
end

function result_diagnostics(model::TransportModel, rows, primitive)
    closures = model.closures
    route = model.basis.diagnostics
    max_identity = maximum(abs(getproperty(row, field)) for row in rows for field in (
        :identity_residual_edge, :identity_residual_terminal,
        :identity_residual_mode, :identity_residual_route,
    ))
    max_ladder = maximum(abs, vcat(
        [row.m_F-(row.m_NC-row.d_edge-row.d_terminal) for row in rows],
        [row.m_F-(row.m_FM+row.d_mode) for row in rows],
        [row.m_F-(row.m_FR+row.d_route) for row in rows],
    ))
    max_realized_hulten = maximum(abs(row.hulten_realized_gap-
        (row.hulten_externality+row.hulten_attenuation)) for row in rows)
    max_primitive_hulten = maximum(abs(row.primitive_gap-(
        row.primitive_externality+row.primitive_propagation+row.primitive_edge+
        row.primitive_terminal+row.primitive_pass_through)) for row in rows)
    max_channel = maximum(abs(getproperty(row, field)) for row in rows for field in (
        :channel_residual_edge, :channel_residual_terminal,
        :channel_residual_mode, :channel_residual_route,
    ))
    max_block_reconstruction = maximum(
        getproperty(closures.blocks, name).reconstruction_residual
        for name in keys(closures.blocks))
    tolerance = model.project.tolerance
    finite_rows = all(row -> all(value -> !(value isa AbstractFloat) || isfinite(value), row), rows)
    finite_diagnostics = all(isfinite, (
        max_identity, max_ladder, max_realized_hulten, max_primitive_hulten,
        max_channel, max_block_reconstruction,
        primitive.residual, route.spectral_radius, route.absorption_error,
        route.row_error, route.column_error, route.edge_error,
        route.fixed_edge_relative_error, route.soft_edge_relative_error,
        closures.conditions.NC, closures.conditions.NT, closures.conditions.F,
        closures.conditions.FM, closures.conditions.FR,
        closures.transport.NT.condition, closures.transport.F.condition,
        closures.transport.FM.condition, closures.transport.FR.condition,
    ))
    verified = finite_rows && finite_diagnostics &&
        maximum((max_identity, max_ladder, max_realized_hulten,
                 max_primitive_hulten, max_channel, max_block_reconstruction,
                 primitive.residual)) <= tolerance
    return Dict{String,Any}(
        "verified" => verified,
        "finite_outputs" => finite_rows && finite_diagnostics,
        "nodes" => model.data.N,
        "directed_edges" => length(model.data.edges),
        "active_edge_mode_pairs" => model.basis.P,
        "directed_policy_arcs" => length(rows),
        "modal_specification" => modal_name(model.project.modal),
        "modal_power" => modal_power(model.project.modal),
        "congestion_specification" => string(nameof(typeof(model.project.congestion))),
        "alpha" => model.project.parameters.alpha,
        "beta" => model.project.parameters.beta,
        "sigma" => model.project.parameters.sigma,
        "eta" => model.project.modal.eta,
        "e" => closures.c.e,
        "rho" => closures.c.ρ,
        "condition_NC" => closures.conditions.NC,
        "condition_NT" => closures.conditions.NT,
        "condition_F" => closures.conditions.F,
        "condition_FM" => closures.conditions.FM,
        "condition_FR" => closures.conditions.FR,
        "condition_transport_NT" => closures.transport.NT.condition,
        "condition_transport_F" => closures.transport.F.condition,
        "condition_transport_FM" => closures.transport.FM.condition,
        "condition_transport_FR" => closures.transport.FR.condition,
        "route_spectral_radius" => route.spectral_radius,
        "route_absorption_error" => route.absorption_error,
        "route_bilateral_row_error" => route.row_error,
        "route_bilateral_column_error" => route.column_error,
        "route_edge_error" => route.edge_error,
        "fixed_route_edge_relative_error" => route.fixed_edge_relative_error,
        "soft_route_edge_relative_error" => route.soft_edge_relative_error,
        "max_inverse_gap_error" => max_identity,
        "max_ladder_error" => max_ladder,
        "max_realized_hulten_error" => max_realized_hulten,
        "max_primitive_hulten_error" => max_primitive_hulten,
        "max_channel_reconstruction_error" => max_channel,
        "max_jacobian_block_reconstruction_error" => max_block_reconstruction,
        "primitive_transport_residual" => primitive.residual,
        "undefined_chi_effective" => count(ismissing, getproperty.(rows, :chi_effective)),
        "mean_directed_primitive_elasticity" => mean(row.primitive_F for row in rows),
        "mean_directed_hulten_elasticity" => mean(row.hulten for row in rows),
    )
end

"Compute directed-arc and physical-link welfare effects under the full closure."
function welfare_effects(model::TransportModel)
    if hasproperty(model.closures, :level) && model.closures.level == :welfare
        rows, primitive = welfare_rows(model)
        physical_rows = model.project.policy.unit == :directed_arc ? NamedTuple[] :
                        aggregate_welfare_physical(rows)
        directed = model.project.policy.unit == :physical_link ? NamedTuple[] : rows
        diagnostics = welfare_diagnostics(model, rows, primitive)
        return enrich_diagnostics!(WelfareResults(directed, physical_rows, diagnostics), model)
    end
    rows, primitive = decomposition_rows(model)
    physical_rows = model.project.policy.unit == :directed_arc ? NamedTuple[] :
                    aggregate_physical(rows, model.closures.c.ρ)
    directed = model.project.policy.unit == :physical_link ? NamedTuple[] : rows
    diagnostics = result_diagnostics(model, rows, primitive)
    return enrich_diagnostics!(WelfareResults(directed, physical_rows, diagnostics), model)
end

welfare_effects(project::Project) = welfare_effects(build_welfare_model(project))

"Compute the exact closure ladder and analytical welfare decomposition."
function decompose_welfare(model::TransportModel)
    rows, primitive = decomposition_rows(model)
    physical_rows = model.project.policy.unit == :directed_arc ? NamedTuple[] :
                    aggregate_physical(rows, model.closures.c.ρ)
    directed = model.project.policy.unit == :physical_link ? NamedTuple[] : rows
    diagnostics = result_diagnostics(model, rows, primitive)
    return enrich_diagnostics!(DecompositionResults(directed, physical_rows, diagnostics), model)
end

decompose_welfare(project::Project) = decompose_welfare(build_model(project))
