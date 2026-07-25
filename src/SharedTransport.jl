"""
Build the route and edge-mode operators shared by all spatial closures.

The caller supplies the spatial model's source and destination margins, their
log-response rows, and the route curvature. The modal, congestion, and
pass-through code downstream of this basis is spatial-model neutral.
"""
function build_spatial_transport_basis(
        project::Project, data::NetworkData;
        source::AbstractVector,
        destination::AbstractVector,
        source_state::AbstractMatrix,
        destination_state::AbstractMatrix,
        aggregate_state::AbstractVector,
        route_curvature::Real,
        state_map::AbstractMatrix,
        include_fixed::Bool=true,
        accepted_state::Union{Nothing,AbstractMatrix}=nothing)
    N = data.N
    all(length(vector) == N for vector in (source, destination)) ||
        throw(DimensionMismatch("transport margins must have length N"))
    size(source_state, 1) == N && size(destination_state, 1) == N ||
        throw(DimensionMismatch("transport state rows must have N rows"))
    size(source_state, 2) == size(destination_state, 2) ==
        length(aggregate_state) == size(state_map, 1) ||
        throw(DimensionMismatch("transport state maps have incompatible dimensions"))

    pairs = build_pair_basis(project, data)
    route = IFTDecomposition.reconstruct_route_kernel(
        data.mu, data.sx, source, destination, data.Xi)
    soft = IFTDecomposition.soft_route_operators(
        route, pairs.active_network_edges, source, data.sx,
        source_state, destination_state, aggregate_state;
        route_curvature,
    )
    Qz_soft = soft.Qz * state_map
    edge_target = [data.Xi[i, j] for (i, j) in pairs.active_network_edges]
    soft_edge_error = maximum(
        abs.(soft.edge_traffic .- edge_target) ./ max.(edge_target, eps()))
    soft_edge_error <= project.tolerance ||
        error("route traffic reconstruction exceeded tolerance")

    fixed = include_fixed ? IFTDecomposition.fixed_route_operators(
        route, pairs.active_network_edges, route.Xod,
        source_state, destination_state, aggregate_state;
        route_curvature, return_incidence=true,
    ) : nothing
    Qz_fixed = include_fixed ? fixed.Qz * state_map : nothing
    fixed_edge_error = include_fixed ? maximum(
        abs.(fixed.edge_traffic .- edge_target) ./ max.(edge_target, eps())) : missing
    include_fixed && fixed_edge_error > project.tolerance &&
        error("fixed-route traffic reconstruction exceeded tolerance")
    state_error = accepted_state === nothing ? missing :
        maximum(abs.(Qz_soft .- accepted_state))

    return merge(pairs, (;
        route_curvature,
        route,
        Croute_soft=-route_curvature .* soft.C,
        Croute_fixed=include_fixed ? -route_curvature .* fixed.C : nothing,
        Qz_soft,
        Qz_fixed,
        fixed_source_weights=include_fixed ? fixed.source_weights : nothing,
        fixed_destination_weights=include_fixed ? fixed.destination_weights : nothing,
        fixed_incidence=include_fixed ? fixed.incidence : nothing,
        diagnostics=(;
            route.diagnostics...,
            soft_state_error=state_error,
            soft_edge_relative_error=soft_edge_error,
            fixed_edge_relative_error=fixed_edge_error,
            fixed_source_weight_error=include_fixed ? fixed.source_weight_error : missing,
            fixed_destination_weight_error=include_fixed ?
                fixed.destination_weight_error : missing,
        ),
    ))
end
