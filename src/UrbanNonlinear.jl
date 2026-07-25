function stable_power_mean(log_changes::AbstractVector,
                           weights::AbstractVector, power::Real)
    length(log_changes) == length(weights) ||
        throw(DimensionMismatch("modal costs and weights must have equal length"))
    pivot = maximum(power .* log_changes)
    return (pivot + log(sum(weights .* exp.(power .* log_changes .- pivot)))) / power
end

function urban_route_allocation(model::TransportModel, state::AbstractVector,
                                edge_costs::AbstractVector, route::Symbol)
    data, basis = model.data, model.basis
    source_state, destination_state, _ =
        urban_bilateral_state_rows(model.project, data.N)
    source_log = source_state*state
    destination_log = destination_state*state
    if route == :soft
        K = copy(basis.route.K)
        for (edge_index, (i, j)) in enumerate(basis.active_network_edges)
            K[i, j] *= exp(-basis.route_curvature*edge_costs[edge_index])
        end
        spectral_radius = maximum(abs, eigvals(K))
        spectral_radius < 1 || throw(ArgumentError(
            "counterfactual urban route kernel is not contractive"))
        T = (Matrix{Float64}(I, data.N, data.N)-K) \
            Matrix{Float64}(I, data.N, data.N)
        source = data.residence .* exp.(source_log)
        destination = data.sx .* exp.(destination_log)
        P = vec(permutedims(source)*T)
        Q = T*destination
        edge_flows = [
            P[i]*K[i, j]*Q[j] for (i, j) in basis.active_network_edges
        ]
        Xod = Diagonal(source)*T*Diagonal(destination)
        return (; Xod, edge_flows, spectral_radius)
    elseif route == :fixed
        basis.fixed_incidence === nothing && throw(ArgumentError(
            "fixed-route nonlinear check requires a decomposition model"))
        od_log_state = vec(source_log .+ permutedims(destination_log))
        path_cost = basis.fixed_incidence*edge_costs
        od_flow = vec(basis.route.Xod) .* exp.(
            od_log_state .- basis.route_curvature .* path_cost)
        edge_flows = vec(permutedims(basis.fixed_incidence)*od_flow)
        return (;
            Xod=reshape(od_flow, data.N, data.N),
            edge_flows,
            spectral_radius=basis.diagnostics.spectral_radius,
        )
    end
    throw(ArgumentError("route closure must be soft or fixed"))
end

function urban_pair_allocation(model::TransportModel, state::AbstractVector,
                               pair_costs::AbstractVector, closure)
    basis, data = model.basis, model.data
    length(pair_costs) == basis.P ||
        throw(DimensionMismatch("pair-cost vector must have length P"))
    edge_costs = zeros(basis.E)
    modal_shares = zeros(basis.P)
    power = modal_power(model.project.modal)
    for edge_index in 1:basis.E
        global_edge = basis.active_edges[edge_index]
        pairs = basis.edge_pairs[global_edge]
        weights = [
            data.s_edges[global_edge, basis.pair_mode[pair]] for pair in pairs
        ]
        if closure.fixed_modal
            edge_costs[edge_index] = dot(weights, pair_costs[pairs])
            modal_shares[pairs] .= weights
        else
            edge_costs[edge_index] =
                stable_power_mean(pair_costs[pairs], weights, power)
            unnormalized = weights .* exp.(
                power .* (pair_costs[pairs] .- edge_costs[edge_index]))
            modal_shares[pairs] .= unnormalized ./ sum(unnormalized)
        end
    end
    route = urban_route_allocation(model, state, edge_costs, closure.route)
    pair_flows = modal_shares .* route.edge_flows[basis.pair_edge]
    return (; pair_costs, edge_costs, modal_shares, pair_flows, route...)
end

function solve_urban_transport(model::TransportModel, state::AbstractVector,
                               primitive_shock::AbstractVector, closure;
                               tolerance::Real=1e-12,
                               max_iterations::Int=500,
                               relaxation::Real=0.1)
    basis = model.basis
    length(primitive_shock) == basis.P ||
        throw(DimensionMismatch("primitive shock vector must have length P"))
    isfinite(relaxation) && 0 < relaxation <= 1 ||
        throw(ArgumentError("urban transport relaxation must lie in (0,1]"))
    pair_costs = Float64.(primitive_shock)
    closure.Q == 0 &&
        return merge(urban_pair_allocation(model, state, pair_costs, closure),
                     (; cost_residual=0.0, iterations=0))
    for iteration in 1:max_iterations
        allocation = urban_pair_allocation(model, state, pair_costs, closure)
        quantity_ratio = closure.A*(allocation.pair_flows ./ basis.pair_flow)
        all(value -> isfinite(value) && value > 0, quantity_ratio) ||
            throw(ArgumentError("urban congestion quantities must remain positive"))
        updated = primitive_shock + closure.G*log.(quantity_ratio)
        residual = norm(updated-pair_costs, Inf)
        if residual <= tolerance
            final = urban_pair_allocation(model, state, updated, closure)
            return merge(final, (; cost_residual=residual, iterations=iteration))
        end
        pair_costs .=
            (1-relaxation) .* pair_costs .+ relaxation .* updated
    end
    error("urban transport fixed point did not converge in $max_iterations iterations")
end

function urban_counterfactual_residual(
        model::TransportModel, state::AbstractVector,
        pair_shock::AbstractVector, closure_name::Symbol;
        shock_type::Symbol=:primitive)
    model.project.spatial isa UrbanCommuting ||
        throw(ArgumentError("urban counterfactual requires an urban model"))
    closure = getproperty(model.closures.transport, closure_name)
    allocation = if shock_type == :primitive
        solve_urban_transport(model, state, pair_shock, closure)
    elseif shock_type == :realized
        endogenous = solve_urban_transport(
            model, state, zeros(model.basis.P), closure)
        target_edge_cost = model.basis.Sagg*pair_shock
        route = urban_route_allocation(
            model, state, endogenous.edge_costs+target_edge_cost, closure.route)
        merge(endogenous, route)
    else
        throw(ArgumentError("shock_type must be primitive or realized"))
    end

    data = model.data
    N = data.N
    length(state) == 2N+1 ||
        throw(DimensionMismatch("urban state must have length 2N+1"))
    residence_change = @view state[1:N]
    workplace_change = @view state[N+1:2N]
    row_margins = vec(sum(allocation.Xod; dims=2))
    column_margins = vec(sum(allocation.Xod; dims=1))
    residual = zeros(2N+1)
    residual[1:N] .=
        log.(row_margins ./ data.residence) .- residence_change
    residual[N+1:2N-1] .=
        log.(column_margins[1:N-1] ./ data.workplace[1:N-1]) .-
        workplace_change[1:N-1]
    residual[2N] = log(sum(data.residence .* exp.(residence_change)))
    residual[2N+1] = log(sum(data.workplace .* exp.(workplace_change)))
    return residual
end

function numerical_state_jacobian(function_value, state::AbstractVector;
                                  step::Real=1e-6)
    baseline = function_value(state)
    J = zeros(length(baseline), length(state))
    for column in eachindex(state)
        plus, minus = copy(state), copy(state)
        plus[column] += step
        minus[column] -= step
        J[:, column] .= (function_value(plus)-function_value(minus))/(2step)
    end
    return J
end

function inadmissible_urban_trial(error)
    message = sprint(showerror, error)
    return error isa ArgumentError && (
               occursin("route kernel is not contractive", message) ||
               occursin("congestion quantities must remain positive", message)
           ) ||
           error isa ErrorException &&
               occursin("transport fixed point did not converge", message)
end

function urban_counterfactual_baseline_jacobian(
        model::TransportModel, closure_name::Symbol)
    data, basis = model.data, model.basis
    closure = getproperty(model.closures.transport, closure_name)
    closure.route == :soft || throw(ArgumentError(
        "the direct-margin baseline Jacobian requires flexible routing"))
    N = data.N
    nv = 2N+1
    source_state, destination_state, _ =
        urban_bilateral_state_rows(model.project, N)
    T = basis.route.T
    K = basis.route.K
    source = data.residence
    destination = data.sx
    P = vec(permutedims(source)*T)
    Q = T*destination
    minimum(P) > 0 && minimum(Q) > 0 ||
        throw(ArgumentError(
            "urban baseline exposures must be strictly positive"))

    J = zeros(nv, nv)
    absorption = T*Diagonal(destination)
    J[1:N, :] .= source_state + absorption*destination_state
    source_weights = Diagonal(source)*T*Diagonal(1 ./ P)
    column_state = permutedims(source_weights)*source_state +
                   destination_state
    J[N+1:2N-1, :] .= column_state[1:N-1, :]
    for i in 1:N
        J[i, i] -= 1
    end
    for i in 1:N-1
        J[N+i, N+i] -= 1
    end
    J[2N, 1:N] .= data.residence
    J[2N+1, N+1:2N] .= data.workplace

    theta = basis.route_curvature
    edge_cost_loading = zeros(nv, basis.E)
    for (edge_index, (i, j)) in enumerate(basis.active_network_edges)
        weight = K[i, j]
        edge_cost_loading[1:N, edge_index] .=
            -theta .* T[:, i] .* weight .* Q[j] ./ Q
        edge_cost_loading[N+1:2N-1, edge_index] .=
            -theta .* P[i] .* weight .* T[j, 1:N-1] ./ P[1:N-1]
    end
    J .+= edge_cost_loading*closure.edge_cost_state
    return J
end

function solve_urban_counterfactual(
        model::TransportModel, pair_shock::AbstractVector,
        closure_name::Symbol; shock_type::Symbol=:primitive,
        tolerance::Real=1e-11, max_iterations::Int=40,
        state_jacobian::Symbol=:numerical)
    state_jacobian in (:numerical, :baseline_analytic) ||
        throw(ArgumentError(
            "state_jacobian must be :numerical or :baseline_analytic"))
    state = zeros(2model.data.N+1)
    approximate_jacobian = state_jacobian == :baseline_analytic ?
        urban_counterfactual_baseline_jacobian(
            model, closure_name) : nothing
    residual(value) = urban_counterfactual_residual(
        model, value, pair_shock, closure_name; shock_type)
    for iteration in 1:max_iterations
        value = residual(state)
        norm(value, Inf) <= tolerance && return (;
            state,
            log_welfare=-state[end]/commuting_theta(model.project.parameters),
            residual=norm(value, Inf),
            iterations=iteration-1,
        )
        J = state_jacobian == :numerical ?
            numerical_state_jacobian(residual, state) :
            approximate_jacobian
        condition = cond(J)
        condition_within_limit(condition, model.project.condition_limit) ||
            error("urban nonlinear counterfactual Jacobian exceeds the condition gate")
        direction = -(J\value)
        old_norm = norm(value)
        scale = 1.0
        accepted = false
        while scale >= 2.0^-20
            candidate = state+scale*direction
            candidate_residual = try
                residual(candidate)
            catch error
                inadmissible_urban_trial(error) || rethrow()
                scale /= 2
                continue
            end
            if norm(candidate_residual) < old_norm
                if approximate_jacobian !== nothing
                    state_step = candidate-state
                    denominator = dot(state_step, state_step)
                    if denominator > eps(Float64)
                        residual_step = candidate_residual-value
                        approximate_jacobian .+=
                            ((residual_step -
                              approximate_jacobian*state_step) *
                             permutedims(state_step)) / denominator
                    end
                end
                state = candidate
                accepted = true
                break
            end
            scale /= 2
        end
        accepted ||
            error(
                "urban nonlinear counterfactual step failed to reduce the " *
                "residual at iteration $iteration (norm=$old_norm)")
    end
    error("urban nonlinear counterfactual did not converge in $max_iterations iterations")
end

"""
Independent nonlinear central finite difference for one urban policy edge-mode.

A primitive shock enters the modal cost fixed point. A realized shock instead
holds fixed the induced aggregate edge-cost change. This compensated
perturbation is the nonlinear counterpart of the realized-cost forcing
`B*Sagg*e_p`; congestion still responds to the urban state, but does not alter
the imposed realized shock.
"""
function urban_multimodal_finite_difference(
        model::TransportModel, policy_index::Int;
        closure::Symbol=:F, shock_type::Symbol=:primitive,
        step::Real=1e-5, state_jacobian::Symbol=:numerical)
    model.project.spatial isa UrbanCommuting ||
        throw(ArgumentError("urban finite difference requires an urban model"))
    hasproperty(model.closures, closure) ||
        throw(ArgumentError("urban closure $closure is unavailable"))
    1 <= policy_index <= length(model.basis.policy_pairs) ||
        throw(BoundsError(model.basis.policy_pairs, policy_index))
    shocks = zeros(model.basis.P)
    pair = model.basis.policy_pairs[policy_index]
    shocks[pair] = step
    plus = solve_urban_counterfactual(
        model, shocks, closure; shock_type, state_jacobian)
    shocks[pair] = -step
    minus = solve_urban_counterfactual(
        model, shocks, closure; shock_type, state_jacobian)
    elasticity = -(plus.log_welfare-minus.log_welfare)/(2step)
    return (; elasticity, plus, minus, closure, shock_type)
end

function urban_multimodal_finite_difference(
        model::TransportModel, edge_id::AbstractString; kwargs...)
    index = findfirst(==(String(edge_id)), model.basis.policy_edge_ids)
    index === nothing && throw(ArgumentError("unknown urban policy edge_id: $edge_id"))
    return urban_multimodal_finite_difference(model, index; kwargs...)
end
