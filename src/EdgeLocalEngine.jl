"""Sparse edge-local welfare calculations for networks too large for route decomposition."""

function edge_local_modal_terms(project::Project, data::NetworkData)
    c = AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    power = modal_power(project.modal)
    policy_mode = findfirst(==(project.policy.mode), data.modes)
    policy_mode === nothing && throw(ArgumentError("policy mode is absent from the data"))
    edge_gain = zeros(length(data.edges))
    primitive_local_factor = zeros(length(data.edges))
    maximum_condition = 1.0
    for t in eachindex(data.edges)
        shares = @view data.s_edges[t, :]
        gamma = [edge_congestion_value(project, data, t, m) for m in eachindex(data.modes)]
        diagonal = 1 .- power .* gamma
        minimum(abs, diagonal) > sqrt(eps(Float64)) ||
            error("an edge-local modal system has a singular diagonal")
        system = Matrix(Diagonal(diagonal)) .-
                 (1-c.σ-power) .* (gamma * permutedims(shares))
        system_condition = cond(system)
        condition_within_limit(system_condition, project.condition_limit) ||
            error("an edge-local modal system exceeds the condition-number gate")
        maximum_condition = max(maximum_condition, system_condition)
        factor = lu(system; check=true)
        edge_gain[t] = dot(shares, factor \ gamma)
        if shares[policy_mode] > 0
            selector = zeros(length(data.modes))
            selector[policy_mode] = 1.0
            zeta = dot(shares, factor \ selector)
            primitive_local_factor[t] = zeta / shares[policy_mode]
        end
    end
    return (; edge_gain, primitive_local_factor, maximum_condition, c, policy_mode)
end

function edge_local_jacobian_components(project::Project, data::NetworkData)
    all(iszero, values(terminal_lambdas(project.congestion))) || throw(ArgumentError(
        "the scalable edge-local solver does not include endpoint-terminal congestion"))
    modal = edge_local_modal_terms(project, data)
    c, N = modal.c, data.N
    dimension = 2N
    row_indices = Int[]
    column_indices = Int[]
    nonzero_values = Float64[]
    add_entry(row, column, value) = if value != 0
        push!(row_indices, row)
        push!(column_indices, column)
        push!(nonzero_values, value)
    end

    for i in 1:N
        add_entry(i, i, data.sx[i]-c.cA)
        add_entry(i, N+i, c.cB)
        if i < N
            add_entry(N+i, i, c.cC)
            add_entry(N+i, N+i, data.sy[i]-c.cE)
        end
    end
    add_entry(2N, N, c.α/c.e)
    add_entry(2N, 2N,
        -(1+c.β*(c.σ-1))/((c.σ-1)*c.e))

    congestion_rows = zeros(dimension)
    local_x_origin = -c.cC
    local_x_destination = c.cA
    local_y_origin = (1-c.β)/c.e
    local_y_destination = -c.cB
    for (t, (i, j)) in enumerate(data.edges)
        mu = data.mu[i, j]
        lambda = data.lam[i, j]
        add_entry(i, j, c.cA*mu)
        add_entry(i, N+j, -c.cB*mu)
        if j < N
            add_entry(N+j, i, -c.cC*lambda)
            add_entry(N+j, N+i, c.cE*lambda)
        end
        gain = modal.edge_gain[t]
        gain == 0 && continue
        outgoing = (1-c.σ)*mu*gain
        add_entry(i, i, outgoing*local_x_origin)
        add_entry(i, j, outgoing*local_x_destination)
        add_entry(i, N+i, outgoing*local_y_origin)
        add_entry(i, N+j, outgoing*local_y_destination)
        congestion_rows[i] += outgoing
        if j < N
            incoming = (1-c.σ)*lambda*gain
            add_entry(N+j, i, incoming*local_x_origin)
            add_entry(N+j, j, incoming*local_x_destination)
            add_entry(N+j, N+i, incoming*local_y_origin)
            add_entry(N+j, N+j, incoming*local_y_destination)
            congestion_rows[N+j] += incoming
        end
    end

    sparse_core = sparse(row_indices, column_indices, nonzero_values, dimension, dimension)
    labor_rows = vcat(data.sx, data.sy[1:N-1], 0.0)
    labor_columns = vcat(
        ((c.σ-1)/c.e) .* data.omega,
        (c.σ/c.e) .* data.omega,
    )
    dense_congestion = vcat(
        (-(c.σ-1)/c.e) .* data.omega .- c.cA .* data.nu,
        (-c.σ/c.e) .* data.omega .- ((1-c.β)/c.e) .* data.nu,
    )
    low_rank_rows = hcat(labor_rows, congestion_rows)
    low_rank_columns = hcat(labor_columns, dense_congestion)
    return (; sparse_core, low_rank_rows, low_rank_columns, modal...)
end

function sparse_low_rank_adjoint(components, omega, sigma)
    selector = AdjointRSUE.psi_row(omega, sigma)
    function solve_components(core, U, V; anchored=false)
        factor = lu(sparse(transpose(core)); check=true)
        solved = factor \ hcat(selector, V)
        base = solved[:, 1]
        bridge = solved[:, 2:end]
        middle = Matrix{Float64}(I, size(U, 2), size(U, 2))+
                 permutedims(U)*bridge
        solution = base-bridge*(middle \ (permutedims(U)*base))
        residual_vector = transpose(core)*solution+
                          V*(permutedims(U)*solution)-selector
        residual = norm(residual_vector, Inf)/max(norm(selector, Inf), eps(Float64))
        return (; solution, residual, middle_condition=cond(middle),
                correction_rank=size(U, 2), anchored, factor)
    end

    core = components.sparse_core
    U, V = components.low_rank_rows, components.low_rank_columns
    result = try
        solve_components(core, U, V)
    catch error_value
        error_value isa SingularException || rethrow()
        nothing
    end
    if result !== nothing && result.residual <= 1e-9 &&
       result.middle_condition <= 1e12
        return result
    end
    # The efficient limit can make the unanchored sparse core singular even
    # though the full Jacobian is regular. Add and exactly subtract one sparse
    # diagonal anchor before applying Woodbury.
    anchored_core = copy(core)
    anchor_index = length(omega)
    anchored_core[anchor_index, anchor_index] += 1.0
    anchor = zeros(size(core, 1))
    anchor[anchor_index] = 1.0
    return solve_components(
        anchored_core, hcat(U, -anchor), hcat(V, anchor); anchored=true)
end

"""
    edge_local_welfare_effects(project)

Compute the Proposition-2 primitive-cost derivative with a sparse core and exact
low-rank Woodbury correction. This pathway omits the route-consistent realized-
friction forcing and the `FM`/`FR` closure ladder. It is intended for networks
whose dense route-incidence objects are too large to construct.
"""
function edge_local_welfare_effects(project::Project)
    project.spatial isa UrbanCommuting && throw(ArgumentError(
        "analyze-edge-local is the economic-geography Proposition-2 estimator; " *
        "use analyze for urban_commuting"))
    isfinite(project.condition_limit) && 1 < project.condition_limit <= 1e12 ||
        throw(ArgumentError("condition_limit must be finite and lie in (1, 1e12]"))
    isfinite(project.tolerance) && project.tolerance > 0 ||
        throw(ArgumentError("diagnostic tolerance must be finite and positive"))
    data = load_network(project)
    components = edge_local_jacobian_components(project, data)
    contraction_bound = maximum(vec(sum(data.mu; dims=2)))
    contraction_bound < 1 || error("the edge-local route kernel is not contractive")
    adjoint = sparse_low_rank_adjoint(components, data.omega, components.c.σ)
    adjoint.residual <= max(project.tolerance, 1e-9) ||
        error("the sparse edge-local adjoint residual exceeds tolerance")
    condition_within_limit(adjoint.middle_condition, project.condition_limit) ||
        error("the edge-local Woodbury system exceeds the condition-number gate")

    N = data.N
    ell = adjoint.solution
    multipliers = (;
        Min=(-ell[1:N]) ./ data.Tnode,
        Mout=(-ell[N+1:2N]) ./ data.Tnode,
    )
    rows = NamedTuple[]
    for r in eachindex(data.policy_edges)
        i, j = data.policy_edges[r]
        t = data.edge_index[(i, j)]
        share = data.s_edges[t, components.policy_mode]
        traffic = data.mode_flows[components.policy_mode][i, j]
        proposition_factor = AdjointRSUE.prop2_edge_elasticity(
            i, j, share, data.Xi[i, j], multipliers, components.c.ρ; N)
        primitive = components.primitive_local_factor[t]*proposition_factor
        push!(rows, (;
            edge_id=data.policy_edge_ids[r],
            physical_link_id=data.policy_physical_link_ids[r],
            origin=data.node_ids[i], destination=data.node_ids[j],
            origin_index=i, destination_index=j,
            mode=String(project.policy.mode), hulten=traffic,
            realized_F=missing, primitive_F=primitive,
            chi_effective=missing, primitive_pass_through=missing,
        ))
    end
    finite_rows = all(row -> all(value ->
        !(value isa AbstractFloat) || isfinite(value), row), rows)
    physical = project.policy.unit == :directed_arc ? NamedTuple[] :
               aggregate_edge_local_physical(rows)
    directed = project.policy.unit == :physical_link ? NamedTuple[] : rows
    diagnostics = Dict{String,Any}(
        "verified" => finite_rows,
        "finite_outputs" => finite_rows,
        "closure_level" => "edge_local_sparse",
        "nodes" => N,
        "directed_edges" => length(data.edges),
        "directed_policy_arcs" => length(rows),
        "modal_specification" => modal_name(project.modal),
        "congestion_specification" => string(nameof(typeof(project.congestion))),
        "rho" => components.c.ρ,
        "route_contraction_upper_bound" => contraction_bound,
        "adjoint_relative_residual" => adjoint.residual,
        "woodbury_condition" => adjoint.middle_condition,
        "woodbury_rank" => adjoint.correction_rank,
        "woodbury_anchor_used" => adjoint.anchored,
        "maximum_modal_condition" => components.maximum_condition,
        "undefined_chi_effective" => count(ismissing, getproperty.(rows, :chi_effective)),
        "realized_friction_available" => false,
        "realized_friction_unavailable_reason" =>
            "the route-consistent realized-friction forcing requires transport operators omitted by the edge-local solver",
        "mean_directed_primitive_elasticity" => mean(row.primitive_F for row in rows),
        "mean_directed_hulten_elasticity" => mean(row.hulten for row in rows),
        "decomposition_available" => false,
        "decomposition_unavailable_reason" =>
            "FM/FR dense route-incidence operators are not constructed by the edge-local solver",
    )
    diagnostics["input_hashes"] = data.input_hashes
    diagnostics["transformations"] = data.transformations
    diagnostics["edge_congestion"] = edge_congestion_metadata(project, data)
    diagnostics["shock_fraction"] = project.policy.shock_fraction
    diagnostics["one_percent_gain_scale"] = 100*project.policy.shock_fraction
    return WelfareResults(directed, physical, diagnostics)
end

function aggregate_edge_local_physical(rows::AbstractVector{<:NamedTuple})
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
        push!(output, (;
            physical_link_id=link, directions=2,
            endpoint_a=min(a.origin, a.destination),
            endpoint_b=max(a.origin, a.destination),
            hulten=sum(row.hulten for row in group),
            realized_F=missing,
            primitive_F=sum(row.primitive_F for row in group),
            chi_effective=missing,
            primitive_pass_through=missing,
        ))
    end
    return output
end
