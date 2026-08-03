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

function inverse_state_map(N::Int, omega::AbstractVector, c::AdjointRSUE.Coef;
                           endogenous::AbstractVector{Bool}=trues(N))
    V = zeros(2N + 1, 2N)
    qW = AdjointRSUE.welfare_gradient(omega, c)
    wage_y = -(1 + c.β * (c.σ - 1)) / ((c.σ - 1) * c.e)
    for i in findall(endogenous)
        V[i, i] = c.α / c.e
        V[i, N+i] = wage_y
        V[N+i, :] .= qW ./ (1 + c.α + c.β)
        V[N+i, i] += 1 / c.e
        V[N+i, N+i] += c.σ / ((c.σ - 1) * c.e)
    end
    V[end, :] .= qW
    locations = findall(endogenous)
    return V[:, vcat(locations, N .+ locations)]
end

function bilateral_state_rows(N::Int, c::AdjointRSUE.Coef;
                              endogenous::AbstractVector{Bool}=trues(N))
    nv = 2N + 1
    S = zeros(N, nv)
    D = zeros(N, nv)
    for i in findall(endogenous)
        S[i, i] = 1 - c.σ
        S[i, N+i] = (c.σ - 1) * c.α
        D[i, i] = c.σ
        D[i, N+i] = (c.σ - 1) * c.β + 1
        D[i, end] = 1 - c.σ
    end
    return S, D, zeros(nv)
end

economic_welfare_gradient(data::NetworkData, c::AdjointRSUE.Coef) =
    AdjointRSUE.reduced_welfare_gradient(data.omega, c, data.endogenous)

function active_transport_modes(project::Project, data::NetworkData)
    return sort!(collect(configured_active_modes(project, data.modes)); by=String)
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

function build_route_basis(project::Project, data::NetworkData; include_fixed::Bool=true)
    c = AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    S, D, dlogY = bilateral_state_rows(data.N, c; endogenous=data.endogenous)
    dlogY[1:data.N] .= data.nu
    dlogY[data.N+1:2*data.N] .= data.nu
    Vz = inverse_state_map(data.N, data.omega, c; endogenous=data.endogenous)
    accepted = all(data.endogenous) ? IFTDecomposition.response_rows(
        data.N, build_pair_basis(project, data).active_network_edges,
        data.omega, data.nu, c) : nothing
    basis = build_spatial_transport_basis(
        project, data;
        source=data.source_margin,
        destination=data.destination_margin,
        source_state=S,
        destination_state=D,
        aggregate_state=dlogY,
        route_curvature=project.parameters.sigma-1,
        state_map=Vz,
        include_fixed,
        accepted_state=accepted,
    )
    return merge(basis, (; sigma=project.parameters.sigma))
end

function route_state_matrix(data::NetworkData, basis, c::AdjointRSUE.Coef;
                            route::Symbol=:soft)
    S, D, dlogY = bilateral_state_rows(data.N, c; endogenous=data.endogenous)
    dlogY[1:data.N] .= data.nu
    dlogY[data.N+1:2*data.N] .= data.nu
    dense = if route == :fixed
        basis.fixed_source_weights * S + basis.fixed_destination_weights * D .-
            permutedims(dlogY)
    elseif route == :soft
        T = basis.route.T
        Pstock = vec(permutedims(data.source_margin) * T)
        Qstock = T * data.sx
        Pz = zeros(data.N, 2*data.N+1)
        Qz = zeros(data.N, 2*data.N+1)
        for k in 1:data.N
            Pz[k, :] .= vec(permutedims(data.source_margin .* T[:, k] ./ Pstock[k]) * S)
            Qz[k, :] .= vec(permutedims(T[k, :] .* data.sx ./ Qstock[k]) * D)
        end
        Pz[first.(basis.active_network_edges), :] +
            Qz[last.(basis.active_network_edges), :] .- permutedims(dlogY)
    else
        throw(ArgumentError("route closure must be soft or fixed"))
    end
    return dense * inverse_state_map(
        data.N, data.omega, c; endogenous=data.endogenous)
end

function edge_congestion_value(project::Project, data::NetworkData,
                               edge_index::Int, mode_index::Int)
    column = edge_input_column(project.congestion)
    if column !== nothing
        key = (edge_index, mode_index)
        haskey(data.pair_edge_congestion, key) || throw(ArgumentError(
            "configured edge-congestion column '$column' is missing an active edge-mode value"))
        return edge_congestion_scale(project.congestion) * data.pair_edge_congestion[key]
    end
    return get(edge_lambdas(project.congestion), data.modes[mode_index], 0.0)
end

function congestion_matrices(project::Project, data::NetworkData, basis;
                             include_edge::Bool=true, include_terminal::Bool=true)
    terminal_lambda = include_terminal ? terminal_lambdas(project.congestion) : Dict{Symbol,Float64}()
    scale = terminal_scale(project.congestion)
    edge_pair_lambda = zeros(basis.P)
    if include_edge
        for p in 1:basis.P
            tglobal = basis.active_edges[basis.pair_edge[p]]
            edge_pair_lambda[p] = edge_congestion_value(
                project, data, tglobal, basis.pair_mode[p])
        end
    end
    qkeys = Any[]
    qindex = Dict{Any,Int}()
    edge_q = Dict{Int,Int}()
    terminal_groups = Dict{Tuple{Symbol,Symbol,String},Vector{Int}}()
    terminal_for_pair = Dict{Tuple{Int,Symbol},Int}()

    for p in 1:basis.P
        edge_pair_lambda[p] > 0 || continue
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
        lambda_edge = edge_pair_lambda[p]
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
    return (; A, G, Q, qkeys, edge_pair_lambda, edge_states=length(edge_q),
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
        left = zeros(size(B, 1), 0)
        right = zeros(0, size(B, 1))
        condition = 1.0
        solve_residual = 0.0
    else
        H = Matrix{Float64}(I, congestion.Q, congestion.Q) .-
            Matrix(congestion.A * response.Xq)
        factor = lu(H; check=true)
        AQz = congestion.A * response.Xz
        quantity_state = factor \ Matrix(AQz)
        right = Matrix(AQz)
        left = B * basis.Sagg * congestion.G * (factor \ Matrix{Float64}(I, congestion.Q, congestion.Q))
        edge_cost_state = basis.Sagg * (congestion.G * quantity_state)
        Jc = left * right
        solve_residual = norm(H*quantity_state-AQz, Inf) / max(norm(AQz, Inf), eps())
        condition = cond(H)
    end
    return (;
        route, fixed_modal, congestion..., response..., H, quantity_state,
        edge_cost_state, Jc, left, right, solve_residual, condition,
    )
end

zero_factor(n::Int) = (U=zeros(n, 0), V=zeros(0, n))
transport_factor(closure) = (U=closure.left, V=closure.right)

function difference_factor(a, b)
    # Factor a.Jc-b.Jc without fitting or numerical rank reduction.
    U = hcat(a.left, b.left)
    V = vcat(a.right, -b.right)
    return (; U, V)
end

function closure_block(name::Symbol, J, factors, road, terminal)
    reconstruction = factors.D + factors.u*permutedims(factors.v) +
                     road.U*road.V + terminal.U*terminal.V
    return (;
        name, J, D=factors.D, u=factors.u, v=factors.v, road, terminal,
        reconstruction_residual=maximum(abs.(J-reconstruction)),
    )
end

function build_closures(project::Project, data::NetworkData, basis)
    c = AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    point_basis = merge(basis, (;
        Qz_soft=route_state_matrix(data, basis, c; route=:soft),
        Qz_fixed=route_state_matrix(data, basis, c; route=:fixed),
    ))
    J0 = AdjointRSUE.assemble_J(
        data.sx, data.sy, data.mu, data.lam, data.omega, c;
        endogenous=data.endogenous, normalization_node=data.normalization_node)
    B = IFTDecomposition.cost_loading_matrix(
        data.N, point_basis.active_network_edges, data.mu, data.lam, c.σ;
        endogenous=data.endogenous, normalization_node=data.normalization_node)
    NCt = build_transport_closure(project, data, point_basis, B;
        include_edge=false, include_terminal=false)
    NTt = build_transport_closure(project, data, point_basis, B;
        include_edge=true, include_terminal=false)
    Ft = build_transport_closure(project, data, point_basis, B)
    FMt = build_transport_closure(project, data, point_basis, B; fixed_modal=true)
    FRt = build_transport_closure(project, data, point_basis, B; route=:fixed)
    FMNTt = build_transport_closure(project, data, point_basis, B;
        fixed_modal=true, include_terminal=false)
    FRNTt = build_transport_closure(project, data, point_basis, B;
        route=:fixed, include_terminal=false)
    J_NC, J_NT = J0+NCt.Jc, J0+NTt.Jc
    J_F, J_FM, J_FR = J0+Ft.Jc, J0+FMt.Jc, J0+FRt.Jc
    conditions = (NC=cond(J_NC), NT=cond(J_NT), F=cond(J_F),
                  FM=cond(J_FM), FR=cond(J_FR))
    all(value -> condition_within_limit(value, project.condition_limit), values(conditions)) ||
        error("an equilibrium closure exceeds the condition-number gate")
    all(value -> condition_within_limit(value, project.condition_limit),
        (NCt.condition, NTt.condition, Ft.condition, FMt.condition, FRt.condition,
         FMNTt.condition, FRNTt.condition)) ||
        error("a transport closure exceeds the condition-number gate")
    factors = IFTDecomposition.jacobian_factors(
        data.sx, data.sy, data.mu, data.lam, data.omega, c;
        endogenous=data.endogenous, normalization_node=data.normalization_node)
    factors.residual <= project.tolerance ||
        error("no-congestion Jacobian factorization exceeded tolerance")
    zero = zero_factor(size(J0, 1))
    road_F = transport_factor(NTt)
    term_F = difference_factor(Ft, NTt)
    road_FM = transport_factor(FMNTt)
    term_FM = difference_factor(FMt, FMNTt)
    road_FR = transport_factor(FRNTt)
    term_FR = difference_factor(FRt, FRNTt)
    blocks = (;
        NC=closure_block(:NC, J_NC, factors, zero, zero),
        NT=closure_block(:NT, J_NT, factors, road_F, zero),
        F=closure_block(:F, J_F, factors, road_F, term_F),
        FM=closure_block(:FM, J_FM, factors, road_FM, term_FM),
        FR=closure_block(:FR, J_FR, factors, road_FR, term_FR),
    )
    maximum(getproperty(blocks, name).reconstruction_residual for name in keys(blocks)) <=
        project.tolerance || error("closure Jacobian block reconstruction exceeded tolerance")
    return (;
        c, B, J0, NC=J_NC, NT=J_NT, F=J_F, FM=J_FM, FR=J_FR,
        transport=(NC=NCt, NT=NTt, F=Ft, FM=FMt, FR=FRt,
                   FMNT=FMNTt, FRNT=FRNTt), conditions, blocks,
        edge_block=J_NT-J_NC, terminal_block=J_F-J_NT,
        mode_core=J_FM-J_F, route_core=J_FR-J_F,
    ), point_basis
end

"Load project data and build the common route-modal-congestion closure system."
function build_model(project::Project)
    project.spatial isa UrbanCommuting && return build_urban_model(project)
    isfinite(project.condition_limit) && 1 < project.condition_limit <= 1e12 ||
        throw(ArgumentError("condition_limit must be finite and lie in (1, 1e12]"))
    isfinite(project.tolerance) && project.tolerance > 0 ||
        throw(ArgumentError("diagnostic tolerance must be finite and positive"))
    data = load_network(project)
    basis = build_route_basis(project, data)
    closures, point_basis = build_closures(project, data, basis)
    return TransportModel(project, data, point_basis, closures)
end

function build_welfare_model(project::Project)
    project.spatial isa UrbanCommuting && return build_urban_welfare_model(project)
    isfinite(project.condition_limit) && 1 < project.condition_limit <= 1e12 ||
        throw(ArgumentError("condition_limit must be finite and lie in (1, 1e12]"))
    data = load_network(project)
    basis = build_route_basis(project, data; include_fixed=false)
    c = AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    point_basis = merge(basis, (;
        Qz_soft=route_state_matrix(data, basis, c; route=:soft),
    ))
    J0 = AdjointRSUE.assemble_J(
        data.sx, data.sy, data.mu, data.lam, data.omega, c;
        endogenous=data.endogenous, normalization_node=data.normalization_node)
    B = IFTDecomposition.cost_loading_matrix(
        data.N, point_basis.active_network_edges, data.mu, data.lam, c.σ;
        endogenous=data.endogenous, normalization_node=data.normalization_node)
    Ft = build_transport_closure(project, data, point_basis, B)
    JF = J0+Ft.Jc
    condition = cond(JF)
    condition_within_limit(condition, project.condition_limit) ||
        error("the full equilibrium closure exceeds the condition-number gate")
    condition_within_limit(Ft.condition, project.condition_limit) ||
        error("the full transport closure exceeds the condition-number gate")
    closures = (; c, B, J0, F=JF, transport=(F=Ft,),
                 conditions=(F=condition,), level=:welfare)
    return TransportModel(project, data, point_basis, closures)
end

function primitive_forcing(model::TransportModel, closure_name::Symbol=:F)
    basis = model.basis
    hasproperty(model.closures.transport, closure_name) ||
        throw(ArgumentError("transport closure $closure_name is unavailable"))
    closure = getproperty(model.closures.transport, closure_name)
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

function structured_gap(JA::AbstractMatrix, U::AbstractMatrix, V::AbstractMatrix,
                        q::AbstractVector, forcing::AbstractMatrix)
    isempty(U) && return zeros(size(forcing, 2))
    left = permutedims(permutedims(JA) \ q) * U
    middle = Matrix{Float64}(I, size(V, 1), size(V, 1)) + V*(JA \ U)
    right = middle \ (V*(JA \ forcing))
    return vec(left*right)
end

function mixed_channels(full, alternative, q::AbstractVector,
                        forcing::AbstractMatrix, normalization::AbstractVector)
    S = alternative.D-full.D
    road_difference = alternative.road.U*alternative.road.V-
                      full.road.U*full.road.V
    terminal_difference = alternative.terminal.U*alternative.terminal.V-
                          full.terminal.U*full.terminal.V
    C = road_difference+terminal_difference
    K = full.J+S+C
    R = hcat(full.u, alternative.u-full.u)
    Q = hcat(alternative.v-full.v, alternative.v)
    gamma = Matrix{Float64}(I, 2, 2)+permutedims(Q)*(K\R)
    y = K\forcing
    pfull = permutedims(permutedims(full.J)\q)
    pk = permutedims(permutedims(K)\q)
    allocation = vec(pfull*S*y) ./ normalization
    scarcity = vec(pfull*C*y) ./ normalization
    equilibrium = vec(pk*R*(gamma\(permutedims(Q)*y))) ./ normalization
    total = allocation+scarcity+equilibrium
    jacobian_residual = maximum(abs.(alternative.J-(K+R*permutedims(Q))))
    return (; allocation, scarcity, equilibrium, total, jacobian_residual)
end

function effective_ratio(realized::Real, primitive::Real, traffic::Real)
    all(isfinite, (realized, primitive, traffic)) ||
        throw(ArgumentError("effective-ratio inputs must be finite"))
    scale = max(abs(primitive), abs(traffic), floatmin(Float64))
    return abs(realized) > sqrt(eps(Float64))*scale ? primitive/realized : missing
end

function decomposition_rows(model::TransportModel)
    data, basis, closures = model.data, model.basis, model.closures
    q = economic_welfare_gradient(data, closures.c)
    realized_forcing = closures.B * basis.Sagg[:, basis.policy_pairs]
    primitive = primitive_forcing(model)
    names = (:NC, :NT, :F, :FM, :FR)
    elasticities = Dict(name => operator_gain(getproperty(closures, name), q, realized_forcing)
                        for name in names)
    primitive_values = operator_gain(closures.F, q, primitive.forcing)
    traffic = [data.mode_flows[basis.policy_mode][edge...] for edge in basis.policy_edges]
    normalization = closures.c.ρ .* traffic
    road_scarcity = structured_gap(
        closures.NC, closures.blocks.F.road.U, closures.blocks.F.road.V,
        q, realized_forcing) ./ normalization
    terminal_scarcity = structured_gap(
        closures.NT, closures.blocks.F.terminal.U, closures.blocks.F.terminal.V,
        q, realized_forcing) ./ normalization
    mode_channels = mixed_channels(
        closures.blocks.F, closures.blocks.FM, q, realized_forcing, normalization)
    route_channels = mixed_channels(
        closures.blocks.F, closures.blocks.FR, q, realized_forcing, normalization)
    maximum((mode_channels.jacobian_residual, route_channels.jacobian_residual)) <=
        model.project.tolerance || error("mixed closure Jacobian reconstruction exceeded tolerance")
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
        all(isfinite, (values[:F], primitive_values[r])) ||
            error("full-closure welfare elasticities are nonfinite")
        chi = effective_ratio(values[:F], primitive_values[r], Xi)
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
        primitive_pass_through = values[:F] - primitive_values[r]
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
            edge_allocation=0.0, edge_scarcity=road_scarcity[r], edge_equilibrium=0.0,
            terminal_allocation=0.0, terminal_scarcity=terminal_scarcity[r], terminal_equilibrium=0.0,
            mode_allocation=mode_channels.allocation[r],
            mode_scarcity=mode_channels.scarcity[r],
            mode_equilibrium=mode_channels.equilibrium[r],
            route_allocation=route_channels.allocation[r],
            route_scarcity=route_channels.scarcity[r],
            route_equilibrium=route_channels.equilibrium[r],
            channel_residual_edge=d_edge-road_scarcity[r],
            channel_residual_terminal=d_terminal-terminal_scarcity[r],
            channel_residual_mode=d_mode-mode_channels.total[r],
            channel_residual_route=d_route-route_channels.total[r],
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

function aggregate_physical(rows::AbstractVector{<:NamedTuple}, rho::Real)
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
    normalized_channels = (
        :edge_allocation, :edge_scarcity, :edge_equilibrium,
        :terminal_allocation, :terminal_scarcity, :terminal_equilibrium,
        :mode_allocation, :mode_scarcity, :mode_equilibrium,
        :route_allocation, :route_scarcity, :route_equilibrium,
        :channel_residual_edge, :channel_residual_terminal,
        :channel_residual_mode, :channel_residual_route,
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
        all(isfinite, (sums[:realized_F], sums[:primitive_F])) ||
            error("physical-link welfare elasticities are nonfinite")
        mNC, mNT = sums[:realized_NC]/(rho*h), sums[:realized_NT]/(rho*h)
        mF, mFM, mFR = sums[:realized_F]/(rho*h), sums[:realized_FM]/(rho*h),
                        sums[:realized_FR]/(rho*h)
        d_edge, d_terminal, d_mode, d_route = mNC-mNT, mNT-mF, mF-mFM, mF-mFR
        channels = Dict(field =>
            sum(row.hulten*getproperty(row, field) for row in group)/h
            for field in normalized_channels)
        push!(output, (;
            physical_link_id=link, directions=2,
            endpoint_a=min(a.origin, a.destination), endpoint_b=max(a.origin, a.destination),
            (field => sums[field] for field in additive)...,
            chi_effective=effective_ratio(sums[:realized_F], sums[:primitive_F], h),
            m_NC=mNC, m_NT=mNT, m_F=mF, m_FM=mFM, m_FR=mFR,
            d_edge, d_road=d_edge, d_terminal, d_mode, d_route,
            (field => channels[field] for field in normalized_channels)...,
        ))
    end
    return output
end
