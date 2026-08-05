function _accepted_status(model::JuMP.Model)
    status = termination_status(model)
    status in (JuMP.MOI.OPTIMAL, JuMP.MOI.LOCALLY_SOLVED) ||
        throw(ErrorException("optimizer terminated with status $status"))
    return status
end

"""
    solve_route_primal(economy, origin, destination; route=route_dual(economy))

Solve one OD entropy-regularized Markov occupancy problem directly and compare
it with the soft-Bellman route dual. The destination absorbs one unit; cycles
and repeated edge traversals remain feasible.
"""
function solve_route_primal(e::IsomorphismEconomy, origin::Int, destination::Int;
                            route=route_dual(e), positivity::Real=1e-12)
    origin != destination || throw(ArgumentError("route-primal check requires origin != destination"))
    N = length(e.A)
    1 <= origin <= N && 1 <= destination <= N || throw(BoundsError())
    edges = active_edges(e)
    E = length(edges)
    edge_origin = first.(edges)
    log_edge_cost = [log(e.kappa[i, j]) for (i, j) in edges]
    incoming = [Int[] for _ in 1:N]
    outgoing = [Int[] for _ in 1:N]
    for (index, (i, j)) in enumerate(edges)
        push!(outgoing[i], index)
        push!(incoming[j], index)
    end

    model = Model(Ipopt.Optimizer)
    set_silent(model)
    set_optimizer_attribute(model, "tol", 1e-11)
    set_optimizer_attribute(model, "constr_viol_tol", 1e-11)
    set_optimizer_attribute(model, "max_iter", 2_000)
    @variable(model, f[1:E] >= positivity)
    @expression(model, occupancy[k=1:N],
        (k == origin ? 1.0 : 0.0) + sum(f[index] for index in incoming[k]))

    for k in 1:N
        k == destination && continue
        @constraint(model, occupancy[k] == sum(f[index] for index in outgoing[k]))
    end

    for (index, (i, j)) in enumerate(edges)
        initial = route.G[origin, i] * route.K[i, j] * route.G[j, destination] /
                  route.G[origin, destination]
        set_start_value(f[index], max(initial, 10positivity))
    end

    invtheta = 1 / e.theta
    @objective(model, Min,
        sum(f[index] * log_edge_cost[index] +
            invtheta * f[index] * log(f[index] / occupancy[edge_origin[index]])
            for index in 1:E) +
        invtheta * log(1 / occupancy[destination]))
    optimize!(model)
    status = _accepted_status(model)

    flow = zeros(Float64, N, N)
    for (index, (i, j)) in enumerate(edges)
        flow[i, j] = value(f[index])
    end
    occupancy_value = [value(occupancy[k]) for k in 1:N]
    conservation = zeros(Float64, N)
    for k in 1:N
        conservation[k] = (k == origin ? 1.0 : 0.0) + sum(flow[:, k]) -
                          (k == destination ? 1.0 : 0.0) - sum(flow[k, :])
    end
    dual_flow = zeros(Float64, N, N)
    for (i, j) in edges
        dual_flow[i, j] = route.G[origin, i] * route.K[i, j] * route.G[j, destination] /
                          route.G[origin, destination]
    end
    dual_value = -log(route.G[origin, destination]) / e.theta
    return (;
        objective=objective_value(model), dual_value, flow, dual_flow,
        occupancy=occupancy_value, conservation,
        flow_error=norm(flow - dual_flow, Inf),
        value_error=abs(objective_value(model) - dual_value), status,
    )
end

"""
    solve_spatial_planner(economy; route=route_dual(economy), start=solve_full_afw(...))

Directly solve the efficient spatial planner after the entropy route technology
has been dualized to its exact unit costs `tau`. This is the fixed-network
Fajgelbaum--Schaal-style planner block.
"""
function solve_spatial_planner(e::IsomorphismEconomy; route=route_dual(e), start=nothing)
    N = length(e.A)
    benchmark = isnothing(start) ? solve_full_afw(e; route) : start
    model = Model(Ipopt.Optimizer)
    set_silent(model)
    set_optimizer_attribute(model, "tol", 1e-10)
    set_optimizer_attribute(model, "constr_viol_tol", 1e-10)
    set_optimizer_attribute(model, "max_iter", 5_000)

    positivity = 1e-11
    @variable(model, W >= positivity)
    @variable(model, L[1:N] >= positivity)
    @variable(model, c[1:N, 1:N] >= positivity)
    set_start_value(W, benchmark.W)
    for i in 1:N
        set_start_value(L[i], benchmark.L[i])
        for j in 1:N
            set_start_value(c[i, j], max(benchmark.c[i, j], 10positivity))
        end
    end

    @constraint(model, sum(L) == e.labor)
    @constraint(model, [i=1:N],
        sum(route.tau[i, j] * c[i, j] for j in 1:N) <= e.A[i] * L[i])
    goods_power = (e.sigma - 1) / e.sigma
    for j in 1:N
        @NLconstraint(model,
            sum(c[i, j]^goods_power for i in 1:N) >=
            (W * L[j] / e.u[j])^goods_power)
    end
    @NLobjective(model, Max, log(W))
    optimize!(model)
    status = _accepted_status(model)

    W_value = value(W)
    L_value = value.(L)
    c_value = value.(c)
    resource_slack = [e.A[i] * L_value[i] -
                      sum(route.tau[i, j] * c_value[i, j] for j in 1:N)
                      for i in 1:N]
    utility_slack = [
        sum(c_value[i, j]^goods_power for i in 1:N) -
        (W_value * L_value[j] / e.u[j])^goods_power for j in 1:N
    ]
    return (;
        W=W_value, L=L_value, c=c_value, status,
        resource_slack, utility_slack,
    )
end
