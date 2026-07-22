"Build the Allen-Arkolakis urban IFT at an observed commuting baseline."
function build_urban_welfare_model(project::Project)
    project.spatial isa UrbanCommuting ||
        throw(ArgumentError("urban model builder requires spatial_specification=urban_commuting"))
    data = load_network(project)
    c = UrbanCommutingIFT.coefficients(
        project.parameters.alpha, project.parameters.beta,
        commuting_theta(project.parameters), project.spatial.congestion_elasticity)
    J = UrbanCommutingIFT.jacobian(
        data.sx, data.sy, data.mu, data.lam, data.residence, data.workplace, c)
    all_edges_loading = UrbanCommutingIFT.cost_loading(
        data.N, data.edges, data.mu, data.lam, c)
    policy_columns = [data.edge_index[edge] for edge in data.policy_edges]
    B = all_edges_loading[:, policy_columns]
    condition = cond(J)
    condition_within_limit(condition, project.condition_limit) ||
        error("the urban equilibrium closure exceeds the condition-number gate")
    q = UrbanCommutingIFT.welfare_gradient(data.N, c)
    adjoint = permutedims(J) \ q
    solve_residual = norm(permutedims(J)*adjoint-q, Inf)/max(norm(q, Inf), eps())
    solve_residual <= project.tolerance ||
        error("the urban adjoint solve exceeded the residual tolerance")
    basis = (;
        policy_edges=data.policy_edges,
        policy_edge_ids=data.policy_edge_ids,
        policy_physical_ids=data.policy_physical_link_ids,
        policy_columns,
    )
    closures = (;
        level=:urban_welfare, c, J, B, q, adjoint,
        conditions=(F=condition,), solve_residual,
    )
    return TransportModel(project, data, basis, closures)
end

"Nonlinear central finite-difference check for one urban policy arc."
function urban_finite_difference(model::TransportModel, edge_index::Int; step::Real=1e-5)
    model.project.spatial isa UrbanCommuting ||
        throw(ArgumentError("urban_finite_difference requires an urban model"))
    1 <= edge_index <= length(model.basis.policy_edges) ||
        throw(BoundsError(model.basis.policy_edges, edge_index))
    global_edge = model.basis.policy_columns[edge_index]
    return UrbanCommutingIFT.finite_difference_elasticity(
        global_edge, model.data.edges, model.data.sx, model.data.sy,
        model.data.mu, model.data.lam, model.data.residence,
        model.data.workplace, model.closures.c; step,
    )
end

function urban_finite_difference(model::TransportModel, edge_id::AbstractString;
                                 step::Real=1e-5)
    index = findfirst(==(String(edge_id)), model.basis.policy_edge_ids)
    index === nothing && throw(ArgumentError("unknown urban policy edge_id: $edge_id"))
    return urban_finite_difference(model, index; step)
end
