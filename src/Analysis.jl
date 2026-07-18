function enrich_diagnostics!(result, model::TransportModel)
    result.diagnostics["input_hashes"] = model.data.input_hashes
    result.diagnostics["transformations"] = model.data.transformations
    result.diagnostics["shock_fraction"] = model.project.policy.shock_fraction
    result.diagnostics["one_percent_gain_scale"] = 100*model.project.policy.shock_fraction
    return result
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
    tolerance = model.project.tolerance
    finite_rows = all(row -> all(value -> !(value isa AbstractFloat) || isfinite(value), row), rows)
    finite_diagnostics = all(isfinite, (
        max_identity, max_ladder, max_realized_hulten, max_primitive_hulten,
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
                 max_primitive_hulten, primitive.residual)) <= tolerance
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
        "primitive_transport_residual" => primitive.residual,
        "mean_directed_primitive_elasticity" => mean(row.primitive_F for row in rows),
        "mean_directed_hulten_elasticity" => mean(row.hulten for row in rows),
    )
end

"Compute directed-arc and physical-link welfare effects under the full closure."
function welfare_effects(model::TransportModel)
    rows, primitive = decomposition_rows(model)
    physical = model.project.policy.unit == :directed_arc ? NamedTuple[] :
        aggregate_physical(rows, model.closures.c.ρ)
    diagnostics = result_diagnostics(model, rows, primitive)
    return enrich_diagnostics!(WelfareResults(rows, physical, diagnostics), model)
end

welfare_effects(project::Project) = welfare_effects(build_model(project))

"Compute the exact closure ladder and analytical welfare decomposition."
function decompose_welfare(model::TransportModel)
    rows, primitive = decomposition_rows(model)
    physical = model.project.policy.unit == :directed_arc ? NamedTuple[] :
        aggregate_physical(rows, model.closures.c.ρ)
    diagnostics = result_diagnostics(model, rows, primitive)
    return enrich_diagnostics!(DecompositionResults(rows, physical, diagnostics), model)
end

decompose_welfare(project::Project) = decompose_welfare(build_model(project))
