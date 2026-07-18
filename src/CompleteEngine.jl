struct TransportModel
    project::Project
    data::NetworkData
    basis::NamedTuple
    closures::NamedTuple
end

struct WelfareResults
    directed::Vector{NamedTuple}
    physical::Vector{NamedTuple}
    diagnostics::Dict{String,Any}
end

struct DecompositionResults
    directed::Vector{NamedTuple}
    physical::Vector{NamedTuple}
    diagnostics::Dict{String,Any}
end

function inverse_state_map(N::Int, omega::AbstractVector, c::AdjointRSUE.Coef)
    V = zeros(2N + 1, 2N)
    qW = AdjointRSUE.welfare_gradient(omega, c)
    wage_y = -(1 + c.β * (c.σ - 1)) / ((c.σ - 1) * c.e)
    for i in 1:N
        V[i, i] = c.α / c.e
        V[i, N+i] = wage_y
        V[N+i, :] .= qW ./ (1 + c.α + c.β)
        V[N+i, i] += 1 / c.e
        V[N+i, N+i] += c.σ / ((c.σ - 1) * c.e)
    end
    V[end, :] .= qW
    return V
end

function bilateral_state_rows(N::Int, c::AdjointRSUE.Coef)
    nv = 2N + 1
    S = zeros(N, nv)
    D = zeros(N, nv)
    for i in 1:N
        S[i, i] = 1 - c.σ
        S[i, N+i] = (c.σ - 1) * c.α
        D[i, i] = c.σ
        D[i, N+i] = (c.σ - 1) * c.β + 1
        D[i, end] = 1 - c.σ
    end
    return S, D, zeros(nv)
end

function active_transport_modes(project::Project, data::NetworkData)
    model = get(project.raw, "model", Dict{String,Any}())
    configured = get(model, "active_transport_modes", String[])
    modes = isempty(configured) ? copy(data.modes) : Symbol.(configured)
    all(mode in data.modes for mode in modes) ||
        throw(ArgumentError("active_transport_modes contains a mode absent from the data"))
    project.policy.mode in modes ||
        throw(ArgumentError("active_transport_modes must include the policy mode"))
    return modes
end

function build_pair_basis(project::Project, data::NetworkData)
    mode_index = Dict(mode => m for (m, mode) in enumerate(data.modes))
    active_modes = Set(active_transport_modes(project, data))
    pair_edge = Int[]
    pair_mode = Int[]
    pair_origin = Int[]
    pair_destination = Int[]
    pair_flow = Float64[]
    pair_lookup = Dict{Tuple{Int,Int},Int}()
    edge_pairs = [Int[] for _ in data.edges]
    for (t, (i, j)) in enumerate(data.edges), m in eachindex(data.modes)
        data.modes[m] in active_modes || continue
        flow = Float64(data.mode_flows[m][i, j])
        flow > 0 || continue
        push!(pair_edge, t)
        push!(pair_mode, m)
        push!(pair_origin, i)
        push!(pair_destination, j)
        push!(pair_flow, flow)
        p = length(pair_edge)
        pair_lookup[(t, m)] = p
        push!(edge_pairs[t], p)
    end
    active_edges = findall(pairs -> !isempty(pairs), edge_pairs)
    edge_local = Dict(t => e for (e, t) in enumerate(active_edges))
    active_network_edges = data.edges[active_edges]
    active_pair_ids = collect(eachindex(pair_edge))
    pair_edge_global = copy(pair_edge)
    pair_edge = [edge_local[t] for t in pair_edge]
    P, E = length(pair_edge), length(active_edges)
    P > 0 || throw(ArgumentError("no active edge-mode pairs"))
    rows = collect(1:P)
    L = sparse(rows, pair_edge, ones(P), P, E)
    Sagg = sparse(pair_edge, rows,
        [data.s_edges[active_edges[pair_edge[p]], pair_mode[p]] for p in 1:P], E, P)

    policy_mode = mode_index[project.policy.mode]
    policy_pairs = Int[]
    policy_edges = Tuple{Int,Int}[]
    policy_edge_ids = String[]
    policy_physical_ids = String[]
    for edge in data.policy_edges
        tglobal = data.edge_index[edge]
        haskey(edge_local, tglobal) || continue
        p = get(pair_lookup, (tglobal, policy_mode), 0)
        p > 0 || throw(ArgumentError("policy edge $edge lacks an active $(project.policy.mode) pair"))
        push!(policy_pairs, p)
        push!(policy_edges, edge)
        index = findfirst(==(edge), data.policy_edges)
        push!(policy_edge_ids, data.policy_edge_ids[index])
        push!(policy_physical_ids, data.policy_physical_link_ids[index])
    end

    return (;
        P, E, active_edges, active_network_edges, edge_local, active_pair_ids,
        pair_edge, pair_edge_global, pair_mode, pair_origin, pair_destination,
        pair_flow, pair_lookup, edge_pairs, mode_index, active_modes=collect(active_modes),
        policy_mode, policy_pairs, policy_edges, policy_edge_ids, policy_physical_ids,
        L, Sagg,
    )
end

function build_route_basis(project::Project, data::NetworkData)
    c = AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    pairs = build_pair_basis(project, data)
    route = IFTDecomposition.reconstruct_route_kernel(data.mu, data.sx, data.nu, data.Xi)
    S, D, dlogY = bilateral_state_rows(data.N, c)
    dlogY[1:data.N] .= data.nu
        dlogY[data.N+1:2*data.N] .= data.nu
    soft = IFTDecomposition.soft_route_operators(
        route, pairs.active_network_edges, data.nu, data.sx, S, D, dlogY,
        project.parameters.sigma)
    fixed = IFTDecomposition.fixed_route_operators(
        route, pairs.active_network_edges, route.Xod, S, D, dlogY,
        project.parameters.sigma)
    Vz = inverse_state_map(data.N, data.omega, c)
    Qz_soft = soft.Qz * Vz
    Qz_fixed = fixed.Qz * Vz
    accepted = IFTDecomposition.response_rows(
        data.N, pairs.active_network_edges, data.omega, data.nu, c)
    edge_target = [data.Xi[i, j] for (i, j) in pairs.active_network_edges]
    soft_edge_error = maximum(abs.(soft.edge_traffic .- edge_target) ./ max.(edge_target, eps()))
    fixed_edge_error = maximum(abs.(fixed.edge_traffic .- edge_target) ./ max.(edge_target, eps()))
    max(soft_edge_error, fixed_edge_error) <= project.tolerance ||
        error("route traffic reconstruction exceeded tolerance")
    return merge(pairs, (;
        sigma=project.parameters.sigma,
        route,
        Croute_soft=(1-project.parameters.sigma) .* soft.C,
        Croute_fixed=(1-project.parameters.sigma) .* fixed.C,
        Qz_soft,
        Qz_fixed,
        fixed_source_weights=fixed.source_weights,
        fixed_destination_weights=fixed.destination_weights,
        diagnostics=(;
            route.diagnostics...,
            soft_state_error=maximum(abs.(Qz_soft .- accepted)),
            soft_edge_relative_error=soft_edge_error,
            fixed_edge_relative_error=fixed_edge_error,
            fixed_source_weight_error=fixed.source_weight_error,
            fixed_destination_weight_error=fixed.destination_weight_error,
        ),
    ))
end

function route_state_matrix(data::NetworkData, basis, c::AdjointRSUE.Coef;
                            route::Symbol=:soft)
    S, D, dlogY = bilateral_state_rows(data.N, c)
    dlogY[1:data.N] .= data.nu
    dlogY[data.N+1:2*data.N] .= data.nu
    dense = if route == :fixed
        basis.fixed_source_weights * S + basis.fixed_destination_weights * D .-
            permutedims(dlogY)
    elseif route == :soft
        T = basis.route.T
        Pstock = vec(permutedims(data.nu) * T)
        Qstock = T * data.sx
        Pz = zeros(data.N, 2*data.N+1)
        Qz = zeros(data.N, 2*data.N+1)
        for k in 1:data.N
            Pz[k, :] .= vec(permutedims(data.nu .* T[:, k] ./ Pstock[k]) * S)
            Qz[k, :] .= vec(permutedims(T[k, :] .* data.sx ./ Qstock[k]) * D)
        end
        Pz[first.(basis.active_network_edges), :] +
            Qz[last.(basis.active_network_edges), :] .- permutedims(dlogY)
    else
        throw(ArgumentError("route closure must be soft or fixed"))
    end
    return dense * inverse_state_map(data.N, data.omega, c)
end

function congestion_matrices(project::Project, data::NetworkData, basis;
                             include_edge::Bool=true, include_terminal::Bool=true)
    edge_lambda = include_edge ? edge_lambdas(project.congestion) : Dict{Symbol,Float64}()
    terminal_lambda = include_terminal ? terminal_lambdas(project.congestion) : Dict{Symbol,Float64}()
    scale = terminal_scale(project.congestion)
    qkeys = Any[]
    qindex = Dict{Any,Int}()
    edge_q = Dict{Int,Int}()
    terminal_groups = Dict{Tuple{Symbol,Symbol,String},Vector{Int}}()
    terminal_for_pair = Dict{Tuple{Int,Symbol},Int}()

    for p in 1:basis.P
        mode = data.modes[basis.pair_mode[p]]
        get(edge_lambda, mode, 0.0) > 0 || continue
        key = (:edge, p)
        push!(qkeys, key)
        edge_q[p] = length(qkeys)
        qindex[key] = length(qkeys)
    end
    for p in 1:basis.P
        mode = data.modes[basis.pair_mode[p]]
        get(terminal_lambda, mode, 0.0) > 0 || continue
        tglobal = basis.active_edges[basis.pair_edge[p]]
        pkey = (tglobal, basis.pair_mode[p])
        origin_id = get(data.pair_origin_terminal, pkey, nothing)
        destination_id = get(data.pair_destination_terminal, pkey, nothing)
        origin_id === nothing && error("missing origin terminal ID for active pair $p")
        destination_id === nothing && error("missing destination terminal ID for active pair $p")
        push!(get!(terminal_groups, (:out, mode, origin_id), Int[]), p)
        push!(get!(terminal_groups, (:in, mode, destination_id), Int[]), p)
    end
    for key in sort!(collect(keys(terminal_groups)); by=string)
        push!(qkeys, key)
        qindex[key] = length(qkeys)
    end

    Q = length(qkeys)
    arows = Int[]; acols = Int[]; avals = Float64[]
    for (p, q) in edge_q
        push!(arows, q); push!(acols, p); push!(avals, 1.0)
    end
    for (key, pairs) in terminal_groups
        q = qindex[key]
        total = sum(basis.pair_flow[p] for p in pairs)
        total > 0 || error("terminal group $key has zero traffic")
        for p in pairs
            push!(arows, q); push!(acols, p); push!(avals, basis.pair_flow[p] / total)
        end
    end
    A = sparse(arows, acols, avals, Q, basis.P)

    grows = Int[]; gcols = Int[]; gvals = Float64[]
    for p in 1:basis.P
        mode = data.modes[basis.pair_mode[p]]
        lambda_edge = get(edge_lambda, mode, 0.0)
        if lambda_edge > 0
            push!(grows, p); push!(gcols, edge_q[p]); push!(gvals, lambda_edge)
        end
        lambda_terminal = get(terminal_lambda, mode, 0.0)
        if lambda_terminal > 0
            tglobal = basis.active_edges[basis.pair_edge[p]]
            pkey = (tglobal, basis.pair_mode[p])
            outkey = (:out, mode, data.pair_origin_terminal[pkey])
            inkey = (:in, mode, data.pair_destination_terminal[pkey])
            push!(grows, p); push!(gcols, qindex[outkey]); push!(gvals, lambda_terminal*scale)
            push!(grows, p); push!(gcols, qindex[inkey]); push!(gvals, lambda_terminal*scale)
        end
    end
    G = sparse(grows, gcols, gvals, basis.P, Q)
    return (; A, G, Q, qkeys, edge_states=length(edge_q),
            terminal_states=length(terminal_groups))
end

function pair_response_matrices(basis, G::AbstractMatrix, modal::AbstractModalSpecification;
                                route::Symbol=:soft, fixed_modal::Bool=false)
    Croute = route == :soft ? basis.Croute_soft :
             route == :fixed ? basis.Croute_fixed :
             throw(ArgumentError("route closure must be soft or fixed"))
    Qz_edge = route == :soft ? basis.Qz_soft : basis.Qz_fixed
    Kedge = basis.Sagg * G
    Xq = basis.L * (Croute * Kedge)
    !fixed_modal && (Xq .+= modal_power(modal) .* (G .- basis.L*Kedge))
    Xz = basis.L * Qz_edge
    return (; Croute, Qz_edge, Kedge, Xq, Xz)
end

function build_transport_closure(project::Project, data::NetworkData, basis,
                                 B::AbstractMatrix;
                                 route::Symbol=:soft, fixed_modal::Bool=false,
                                 include_edge::Bool=true, include_terminal::Bool=true)
    congestion = congestion_matrices(project, data, basis; include_edge, include_terminal)
    response = pair_response_matrices(
        basis, congestion.G, project.modal; route, fixed_modal)
    if congestion.Q == 0
        H = zeros(0, 0)
        quantity_state = zeros(0, size(response.Xz, 2))
        edge_cost_state = zeros(basis.E, size(response.Xz, 2))
        Jc = zeros(size(B, 1), size(B, 1))
        condition = 1.0
        solve_residual = 0.0
    else
        H = Matrix{Float64}(I, congestion.Q, congestion.Q) .-
            Matrix(congestion.A * response.Xq)
        factor = lu(H; check=true)
        AQz = congestion.A * response.Xz
        quantity_state = factor \ Matrix(AQz)
        edge_cost_state = basis.Sagg * (congestion.G * quantity_state)
        Jc = B * edge_cost_state
        solve_residual = norm(H*quantity_state-AQz, Inf) / max(norm(AQz, Inf), eps())
        condition = cond(H)
    end
    return (;
        route, fixed_modal, congestion..., response..., H, quantity_state,
        edge_cost_state, Jc, solve_residual, condition,
    )
end

function build_closures(project::Project, data::NetworkData, basis)
    c = AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    point_basis = merge(basis, (;
        Qz_soft=route_state_matrix(data, basis, c; route=:soft),
        Qz_fixed=route_state_matrix(data, basis, c; route=:fixed),
    ))
    J0 = AdjointRSUE.assemble_J(data.sx, data.sy, data.mu, data.lam, data.omega, c)
    B = IFTDecomposition.cost_loading_matrix(
        data.N, point_basis.active_network_edges, data.mu, data.lam, c.σ)
    NCt = build_transport_closure(project, data, point_basis, B;
        include_edge=false, include_terminal=false)
    NTt = build_transport_closure(project, data, point_basis, B;
        include_edge=true, include_terminal=false)
    Ft = build_transport_closure(project, data, point_basis, B)
    FMt = build_transport_closure(project, data, point_basis, B; fixed_modal=true)
    FRt = build_transport_closure(project, data, point_basis, B; route=:fixed)
    J_NC, J_NT = J0+NCt.Jc, J0+NTt.Jc
    J_F, J_FM, J_FR = J0+Ft.Jc, J0+FMt.Jc, J0+FRt.Jc
    conditions = (NC=cond(J_NC), NT=cond(J_NT), F=cond(J_F),
                  FM=cond(J_FM), FR=cond(J_FR))
    maximum(values(conditions)) <= project.condition_limit ||
        error("an equilibrium closure exceeds the condition-number gate")
    maximum((NCt.condition, NTt.condition, Ft.condition, FMt.condition, FRt.condition)) <=
        project.condition_limit || error("a transport closure exceeds the condition-number gate")
    return (;
        c, B, J0, NC=J_NC, NT=J_NT, F=J_F, FM=J_FM, FR=J_FR,
        transport=(NC=NCt, NT=NTt, F=Ft, FM=FMt, FR=FRt), conditions,
        edge_block=J_NT-J_NC, terminal_block=J_F-J_NT,
        mode_core=J_FM-J_F, route_core=J_FR-J_F,
    ), point_basis
end

"Load project data and build the common route-modal-congestion closure system."
function build_model(project::Project)
    data = load_network(project)
    basis = build_route_basis(project, data)
    closures, point_basis = build_closures(project, data, basis)
    return TransportModel(project, data, point_basis, closures)
end

function primitive_forcing(model::TransportModel)
    basis = model.basis
    closure = model.closures.transport.F
    R = length(basis.policy_pairs)
    selectors = sparse(basis.policy_pairs, collect(1:R), ones(R), basis.P, R)
    Kedge = basis.Sagg * selectors
    Xdirect = basis.L * (closure.Croute * Kedge)
    !closure.fixed_modal &&
        (Xdirect .+= modal_power(model.project.modal) .* (selectors .- basis.L*Kedge))
    if closure.Q == 0
        qresponse = zeros(0, R)
        aggregate_cost = basis.Sagg * selectors
        residual = 0.0
    else
        qdirect = closure.A * Xdirect
        qresponse = closure.H \ Matrix(qdirect)
        aggregate_cost = basis.Sagg * (selectors + closure.G*qresponse)
        residual = norm(closure.H*qresponse-qdirect, Inf) / max(norm(qdirect, Inf), eps())
    end
    forcing = model.closures.B * aggregate_cost
    return (; selectors, aggregate_cost, forcing, qresponse, residual)
end

operator_gain(J::AbstractMatrix, q::AbstractVector, forcing::AbstractMatrix) =
    vec(permutedims(permutedims(J) \ q) * forcing)

function inverse_gap(JA::AbstractMatrix, JB::AbstractMatrix,
                     q::AbstractVector, b::AbstractVector)
    return dot(permutedims(JA) \ q, (JB-JA) * (JB \ b))
end

function decomposition_rows(model::TransportModel)
    data, basis, closures = model.data, model.basis, model.closures
    q = AdjointRSUE.welfare_gradient(data.omega, closures.c)
    realized_forcing = closures.B * basis.Sagg[:, basis.policy_pairs]
    primitive = primitive_forcing(model)
    names = (:NC, :NT, :F, :FM, :FR)
    elasticities = Dict(name => operator_gain(getproperty(closures, name), q, realized_forcing)
                        for name in names)
    primitive_values = operator_gain(closures.F, q, primitive.forcing)
    rows = NamedTuple[]
    for r in eachindex(basis.policy_pairs)
        k, l = basis.policy_edges[r]
        Xi = data.mode_flows[basis.policy_mode][k, l]
        values = Dict(name => elasticities[name][r] for name in names)
        multipliers = Dict(name => values[name] / (closures.c.ρ*Xi) for name in names)
        d_edge = multipliers[:NC]-multipliers[:NT]
        d_terminal = multipliers[:NT]-multipliers[:F]
        d_mode = multipliers[:F]-multipliers[:FM]
        d_route = multipliers[:F]-multipliers[:FR]
        chi = primitive_values[r] / values[:F]
        b = realized_forcing[:, r]
        identity_edge = (values[:NC]-values[:NT])-
            inverse_gap(closures.NC, closures.NT, q, b)
        identity_terminal = (values[:NT]-values[:F])-
            inverse_gap(closures.NT, closures.F, q, b)
        identity_mode = (values[:F]-values[:FM])-
            inverse_gap(closures.F, closures.FM, q, b)
        identity_route = (values[:F]-values[:FR])-
            inverse_gap(closures.F, closures.FR, q, b)
        hulten_realized_gap = Xi-values[:F]
        hulten_externality = Xi*(1-closures.c.ρ)
        hulten_attenuation = closures.c.ρ*Xi*(1-multipliers[:F])
        primitive_gap = Xi-primitive_values[r]
        primitive_externality = hulten_externality
        primitive_propagation = closures.c.ρ*Xi*(1-multipliers[:NC])
        primitive_edge = closures.c.ρ*Xi*d_edge
        primitive_terminal = closures.c.ρ*Xi*d_terminal
        primitive_pass_through = closures.c.ρ*Xi*multipliers[:F]*(1-chi)
        push!(rows, (;
            edge_id=basis.policy_edge_ids[r],
            physical_link_id=basis.policy_physical_ids[r],
            origin=data.node_ids[k], destination=data.node_ids[l],
            origin_index=k, destination_index=l,
            mode=String(model.project.policy.mode), hulten=Xi,
            realized_NC=values[:NC], realized_NT=values[:NT],
            realized_F=values[:F], realized_FM=values[:FM], realized_FR=values[:FR],
            primitive_F=primitive_values[r], chi_effective=chi,
            m_NC=multipliers[:NC], m_NT=multipliers[:NT], m_F=multipliers[:F],
            m_FM=multipliers[:FM], m_FR=multipliers[:FR],
            d_edge, d_road=d_edge, d_terminal, d_mode, d_route,
            edge_allocation=0.0, edge_scarcity=d_edge, edge_equilibrium=0.0,
            terminal_allocation=0.0, terminal_scarcity=d_terminal, terminal_equilibrium=0.0,
            mode_allocation=0.0, mode_scarcity=d_mode, mode_equilibrium=0.0,
            route_allocation=0.0, route_scarcity=d_route, route_equilibrium=0.0,
            hulten_realized_gap, hulten_externality, hulten_attenuation,
            primitive_gap, primitive_externality, primitive_propagation,
            primitive_edge, primitive_road=primitive_edge, primitive_terminal,
            primitive_pass_through,
            identity_residual_edge=identity_edge,
            identity_residual_terminal=identity_terminal,
            identity_residual_mode=identity_mode,
            identity_residual_route=identity_route,
        ))
    end
    return rows, primitive
end

function aggregate_physical(rows::Vector{NamedTuple}, rho::Real)
    grouped = Dict{String,Vector{NamedTuple}}()
    for row in rows
        push!(get!(grouped, row.physical_link_id, NamedTuple[]), row)
    end
    output = NamedTuple[]
    additive = (
        :hulten, :realized_NC, :realized_NT, :realized_F, :realized_FM,
        :realized_FR, :primitive_F, :hulten_realized_gap, :hulten_externality,
        :hulten_attenuation, :primitive_gap, :primitive_externality,
        :primitive_propagation, :primitive_edge, :primitive_road,
        :primitive_terminal, :primitive_pass_through, :identity_residual_edge,
        :identity_residual_terminal, :identity_residual_mode, :identity_residual_route,
    )
    for link in sort!(collect(keys(grouped)))
        group = grouped[link]
        length(group) == 2 ||
            throw(ArgumentError("physical link $link must have exactly two policy directions"))
        a, b = group
        a.origin == b.destination && a.destination == b.origin ||
            throw(ArgumentError("physical link $link does not contain opposite directions"))
        sums = Dict(field => sum(getproperty(row, field) for row in group) for field in additive)
        h = sums[:hulten]
        mNC, mNT = sums[:realized_NC]/(rho*h), sums[:realized_NT]/(rho*h)
        mF, mFM, mFR = sums[:realized_F]/(rho*h), sums[:realized_FM]/(rho*h),
                        sums[:realized_FR]/(rho*h)
        d_edge, d_terminal, d_mode, d_route = mNC-mNT, mNT-mF, mF-mFM, mF-mFR
        push!(output, (;
            physical_link_id=link, directions=2,
            endpoint_a=min(a.origin, a.destination), endpoint_b=max(a.origin, a.destination),
            (field => sums[field] for field in additive)...,
            chi_effective=sums[:primitive_F]/sums[:realized_F],
            m_NC=mNC, m_NT=mNT, m_F=mF, m_FM=mFM, m_FR=mFR,
            d_edge, d_road=d_edge, d_terminal, d_mode, d_route,
            edge_allocation=0.0, edge_scarcity=d_edge, edge_equilibrium=0.0,
            terminal_allocation=0.0, terminal_scarcity=d_terminal, terminal_equilibrium=0.0,
            mode_allocation=0.0, mode_scarcity=d_mode, mode_equilibrium=0.0,
            route_allocation=0.0, route_scarcity=d_route, route_equilibrium=0.0,
        ))
    end
    return output
end
