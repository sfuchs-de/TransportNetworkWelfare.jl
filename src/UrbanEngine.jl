"Origin and destination state rows for the Allen-Arkolakis commuting gravity equation."
function urban_bilateral_state_rows(project::Project, N::Int)
    theta = commuting_theta(project.parameters)
    nv = 2N + 1
    source = zeros(N, nv)
    destination = zeros(N, nv)
    for i in 1:N
        source[i, i] = theta*project.parameters.beta
        source[i, end] = 0.5
        destination[i, N+i] = theta*project.parameters.alpha
        destination[i, end] = 0.5
    end
    return source, destination, zeros(nv)
end

function build_urban_route_basis(project::Project, data::NetworkData;
                                 include_fixed::Bool=true)
    source_state, destination_state, aggregate_state =
        urban_bilateral_state_rows(project, data.N)
    return build_spatial_transport_basis(
        project, data;
        source=data.residence,
        destination=data.workplace,
        source_state,
        destination_state,
        aggregate_state,
        route_curvature=commuting_theta(project.parameters),
        state_map=Matrix{Float64}(I, 2data.N+1, 2data.N+1),
        include_fixed,
    )
end

function urban_base_objects(project::Project, data::NetworkData, basis)
    theta = commuting_theta(project.parameters)
    c = UrbanCommutingIFT.coefficients(
        project.parameters.alpha, project.parameters.beta, theta, 0.0)
    J0 = UrbanCommutingIFT.jacobian(
        data.sx, data.sy, data.mu, data.lam,
        data.residence, data.workplace, c)
    B = UrbanCommutingIFT.cost_loading(
        data.N, basis.active_network_edges, data.mu, data.lam, c)
    q = UrbanCommutingIFT.welfare_gradient(data.N, c)
    return (; c, J0, B, q)
end

function check_urban_closure_conditions(project::Project, closures, transports)
    all(value -> condition_within_limit(value, project.condition_limit),
        values(closures)) ||
        error("an urban equilibrium closure exceeds the condition-number gate")
    all(value -> condition_within_limit(value, project.condition_limit),
        transports) ||
        error("an urban transport closure exceeds the condition-number gate")
end

"Build the common-baseline urban NC, NT, F, FM, and FR closure ladder."
function build_urban_closures(project::Project, data::NetworkData, basis)
    base = urban_base_objects(project, data, basis)
    NCt = build_transport_closure(
        project, data, basis, base.B; include_edge=false, include_terminal=false)
    NTt = build_transport_closure(
        project, data, basis, base.B; include_edge=true, include_terminal=false)
    Ft = build_transport_closure(project, data, basis, base.B)
    FMt = build_transport_closure(
        project, data, basis, base.B; fixed_modal=true)
    FRt = build_transport_closure(
        project, data, basis, base.B; route=:fixed)
    J_NC = base.J0 + NCt.Jc
    J_NT = base.J0 + NTt.Jc
    J_F = base.J0 + Ft.Jc
    J_FM = base.J0 + FMt.Jc
    J_FR = base.J0 + FRt.Jc
    conditions = (
        NC=cond(J_NC), NT=cond(J_NT), F=cond(J_F),
        FM=cond(J_FM), FR=cond(J_FR),
    )
    check_urban_closure_conditions(
        project, conditions,
        (NCt.condition, NTt.condition, Ft.condition, FMt.condition, FRt.condition))
    return (;
        level=:urban_decomposition,
        base...,
        J=J_F,
        NC=J_NC,
        NT=J_NT,
        F=J_F,
        FM=J_FM,
        FR=J_FR,
        transport=(NC=NCt, NT=NTt, F=Ft, FM=FMt, FR=FRt),
        conditions,
    )
end

"Build all urban closures for welfare analysis and decomposition."
function build_urban_model(project::Project; data::Union{Nothing,NetworkData}=nothing)
    project.spatial isa UrbanCommuting ||
        throw(ArgumentError("urban model builder requires spatial_specification=urban_commuting"))
    network = data === nothing ? load_network(project) : data
    basis = build_urban_route_basis(project, network)
    closures = build_urban_closures(project, network, basis)
    return TransportModel(project, network, basis, closures)
end

"Build only the full urban closure for ordinary welfare analysis."
function build_urban_welfare_model(project::Project;
                                   data::Union{Nothing,NetworkData}=nothing)
    project.spatial isa UrbanCommuting ||
        throw(ArgumentError("urban model builder requires spatial_specification=urban_commuting"))
    network = data === nothing ? load_network(project) : data
    basis = build_urban_route_basis(project, network; include_fixed=false)
    base = urban_base_objects(project, network, basis)
    transport = build_transport_closure(project, network, basis, base.B)
    J = base.J0 + transport.Jc
    condition = cond(J)
    check_urban_closure_conditions(
        project, (F=condition,), (transport.condition,))
    adjoint = permutedims(J) \ base.q
    solve_residual = norm(permutedims(J)*adjoint-base.q, Inf) /
        max(norm(base.q, Inf), eps())
    solve_residual <= project.tolerance ||
        error("the urban adjoint solve exceeded the residual tolerance")
    closures = (;
        level=:urban_welfare,
        base...,
        J,
        F=J,
        adjoint,
        transport=(F=transport,),
        conditions=(F=condition,),
        solve_residual,
    )
    return TransportModel(project, network, basis, closures)
end

function legacy_urban_coefficients(model::TransportModel)
    data, project = model.data, model.project
    length(data.modes) == 1 ||
        throw(ArgumentError("the one-mode urban regression oracle requires one observed mode"))
    isempty(terminal_lambdas(project.congestion)) ||
        throw(ArgumentError("the one-mode urban regression oracle excludes terminal congestion"))
    values = [
        edge_congestion_value(project, data, t, 1)
        for t in eachindex(data.edges)
    ]
    maximum(values)-minimum(values) <= project.tolerance ||
        throw(ArgumentError("the one-mode urban regression oracle requires a common edge elasticity"))
    return UrbanCommutingIFT.coefficients(
        project.parameters.alpha, project.parameters.beta,
        commuting_theta(project.parameters), first(values))
end

function urban_oracle_regression(model::TransportModel)
    try
        c = legacy_urban_coefficients(model)
        data, basis = model.data, model.basis
        oracle_J = UrbanCommutingIFT.jacobian(
            data.sx, data.sy, data.mu, data.lam,
            data.residence, data.workplace, c)
        oracle_B_all = UrbanCommutingIFT.cost_loading(
            data.N, data.edges, data.mu, data.lam, c)
        oracle_columns = [data.edge_index[edge] for edge in basis.policy_edges]
        oracle_B = oracle_B_all[:, oracle_columns]
        primitive = primitive_forcing(model)
        shared_response = model.closures.F \ primitive.forcing
        oracle_response = oracle_J \ oracle_B
        q = UrbanCommutingIFT.welfare_gradient(data.N, c)
        shared_welfare = operator_gain(
            model.closures.F, model.closures.q, primitive.forcing)
        oracle_welfare = operator_gain(oracle_J, q, oracle_B)
        return (;
            available=true,
            residual_normalization="shared Schur system and exact-hat oracle use different residual rows",
            state_response_error=maximum(abs.(shared_response-oracle_response)),
            welfare_error=maximum(abs.(shared_welfare-oracle_welfare)),
            raw_jacobian_difference=maximum(abs.(model.closures.F-oracle_J)),
            primitive_forcing_difference=maximum(abs.(primitive.forcing-oracle_B)),
        )
    catch error
        error isa ArgumentError || rethrow()
        return (;
            available=false,
            reason=sprint(showerror, error),
            residual_normalization=missing,
            state_response_error=missing,
            welfare_error=missing,
            raw_jacobian_difference=missing,
            primitive_forcing_difference=missing,
        )
    end
end

"Nonlinear central finite-difference check using the independent one-mode oracle."
function urban_finite_difference(model::TransportModel, edge_index::Int;
                                 step::Real=1e-5,
                                 closure::Symbol=:F,
                                 shock_type::Symbol=:primitive)
    model.project.spatial isa UrbanCommuting ||
        throw(ArgumentError("urban_finite_difference requires an urban model"))
    1 <= edge_index <= length(model.basis.policy_edges) ||
        throw(BoundsError(model.basis.policy_edges, edge_index))
    if length(model.data.modes) != 1 || !isempty(terminal_lambdas(model.project.congestion)) ||
       closure != :F || shock_type != :primitive
        return urban_multimodal_finite_difference(
            model, edge_index; closure, shock_type, step)
    end
    global_edge = model.basis.active_edges[
        model.basis.pair_edge[model.basis.policy_pairs[edge_index]]]
    c = legacy_urban_coefficients(model)
    return UrbanCommutingIFT.finite_difference_elasticity(
        global_edge, model.data.edges, model.data.sx, model.data.sy,
        model.data.mu, model.data.lam, model.data.residence,
        model.data.workplace, c; step,
    )
end

function urban_finite_difference(model::TransportModel, edge_id::AbstractString;
                                 kwargs...)
    index = findfirst(==(String(edge_id)), model.basis.policy_edge_ids)
    index === nothing && throw(ArgumentError("unknown urban policy edge_id: $edge_id"))
    return urban_finite_difference(model, index; kwargs...)
end
