"""
More-specific Float64 implementation of `solve_expanded_planner`.

The destination conservation row is omitted for each OD block. It is implied by
the other rows because one unit is injected at the origin and one unit is
absorbed at the destination. Dropping it removes the exact row dependence that
otherwise makes the nonlinear KKT system singular.
"""
function solve_expanded_planner(e::IsomorphismEconomy{Float64};
                                route=route_dual(e), start=nothing,
                                positivity::Real=1e-12)
    N = length(e.A)
    benchmark = isnothing(start) ? solve_full_afw(e; route) : start
    network = _network_incidence(e)
    E = length(network.edges)
    OD = N * N
    od_index = reshape(collect(1:OD), N, N)
    od_origin = repeat(collect(1:N), outer=N)
    od_destination = repeat(collect(1:N), inner=N)

    model = Model(Ipopt.Optimizer)
    set_optimizer_attribute(model, "tol", 2e-10)
    set_optimizer_attribute(model, "constr_viol_tol", 2e-10)
    set_optimizer_attribute(model, "max_iter", 8_000)
    set_optimizer_attribute(model, "check_derivatives_for_naninf", "yes")
    set_optimizer_attribute(model, "print_level", 5)

    @variable(model, W >= positivity)
    @variable(model, L[1:N] >= positivity)
    @variable(model, c[1:N, 1:N] >= positivity)
    @variable(model, f[1:OD, 1:E] >= positivity)
    @expression(model, occupancy[od=1:OD, k=1:N],
        (k == od_origin[od] ? 1.0 : 0.0) +
        sum(f[od, index] for index in network.incoming[k]))

    set_start_value(W, benchmark.W)
    for i in 1:N
        set_start_value(L[i], benchmark.L[i])
        for j in 1:N
            set_start_value(c[i, j], max(benchmark.c[i, j], 10positivity))
            od = od_index[i, j]
            for (index, (k, l)) in enumerate(network.edges)
                initial = route.G[i, k] * route.K[k, l] * route.G[l, j] / route.G[i, j]
                set_start_value(f[od, index], max(initial, 10positivity))
            end
        end
    end

    for od in 1:OD, k in 1:N
        k == od_destination[od] && continue
        @constraint(model,
            occupancy[od, k] == sum(f[od, index] for index in network.outgoing[k]))
    end

    invtheta = 1 / e.theta
    route_log_cost = Vector{Any}(undef, OD)
    for od in 1:OD
        destination = od_destination[od]
        route_log_cost[od] = @NLexpression(model,
            sum(f[od, index] * network.log_edge_cost[index] +
                invtheta * f[od, index] *
                    log(f[od, index] / occupancy[od, network.edge_origin[index]])
                for index in 1:E) +
            invtheta * log(1 / occupancy[od, destination]))
    end

    @constraint(model, sum(L) == e.labor)
    for i in 1:N
        @NLconstraint(model,
            sum(c[i, j] * exp(route_log_cost[od_index[i, j]]) for j in 1:N) <=
            e.A[i] * L[i])
    end
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
    route_log_value = [value(route_log_cost[od]) for od in 1:OD]
    route_cost = reshape(exp.(route_log_value), N, N)
    flow = zeros(Float64, N, N, N, N)
    dual_flow = zeros(Float64, N, N, N, N)
    for i in 1:N, j in 1:N
        od = od_index[i, j]
        for (index, (k, l)) in enumerate(network.edges)
            flow[i, j, k, l] = value(f[od, index])
            dual_flow[i, j, k, l] =
                route.G[i, k] * route.K[k, l] * route.G[l, j] / route.G[i, j]
        end
    end
    conservation_error = 0.0
    for i in 1:N, j in 1:N, k in 1:N
        lhs = (k == i ? 1.0 : 0.0) + sum(flow[i, j, h, k] for h in 1:N)
        rhs = (k == j ? 1.0 : 0.0) + sum(flow[i, j, k, l] for l in 1:N)
        conservation_error = max(conservation_error, abs(lhs - rhs))
    end
    resource_slack = [e.A[i] * L_value[i] -
                      sum(route_cost[i, j] * c_value[i, j] for j in 1:N)
                      for i in 1:N]
    utility_slack = [
        sum(c_value[i, j]^goods_power for i in 1:N) -
        (W_value * L_value[j] / e.u[j])^goods_power for j in 1:N
    ]
    return (;
        W=W_value, L=L_value, c=c_value, route_cost, flow, dual_flow, status,
        route_cost_error=norm(route_cost - route.tau, Inf),
        flow_error=norm(flow - dual_flow, Inf), conservation_error,
        resource_slack, utility_slack,
    )
end
