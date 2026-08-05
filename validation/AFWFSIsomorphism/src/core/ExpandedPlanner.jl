"""
Direct Float64 implementation of the expanded entropy-regularized planner.

The destination conservation row is omitted for each OD block because it is
implied by the other rows once one unit is injected at the origin and one unit
is absorbed at the destination. Route occupancies are parameterized in logs,
which keeps every flow and every node occupancy strictly positive and prevents
undefined entropy derivatives during the nonlinear solve.
"""
function solve_expanded_planner(e::IsomorphismEconomy{Float64};
                                route=route_dual(e), start=nothing,
                                log_flow_lower::Real=-40.0,
                                log_flow_upper::Real=10.0)
    N = length(e.A)
    benchmark = isnothing(start) ? solve_full_afw(e; route) : start
    network = _network_incidence(e)
    E = length(network.edges)
    OD = N * N
    od_index = reshape(collect(1:OD), N, N)
    # `od_index[i,j] = i + (j-1)N`: origin varies fastest in Julia's
    # column-major layout, while destination is constant within each block.
    od_origin = repeat(collect(1:N), outer=N)
    od_destination = repeat(collect(1:N), inner=N)
    source = zeros(Float64, OD, N)
    for od in 1:OD
        source[od, od_origin[od]] = 1.0
    end

    model = Model(Ipopt.Optimizer)
    set_optimizer_attribute(model, "tol", 2e-10)
    set_optimizer_attribute(model, "constr_viol_tol", 2e-10)
    set_optimizer_attribute(model, "max_iter", 8_000)
    set_optimizer_attribute(model, "check_derivatives_for_naninf", "yes")
    set_optimizer_attribute(model, "print_level", 5)

    positivity = 1e-12
    @variable(model, W >= positivity)
    @variable(model, L[1:N] >= positivity)
    @variable(model, c[1:N, 1:N] >= positivity)
    @variable(model, log_flow_lower <= g[1:OD, 1:E] <= log_flow_upper)
    @NLexpression(model, occupancy[od=1:OD, k=1:N],
        source[od, k] +
        sum(exp(g[od, index]) for index in network.incoming[k]))

    set_start_value(W, benchmark.W)
    for i in 1:N
        set_start_value(L[i], benchmark.L[i])
        for j in 1:N
            set_start_value(c[i, j], max(benchmark.c[i, j], 10positivity))
            od = od_index[i, j]
            for (index, (k, l)) in enumerate(network.edges)
                initial = route.G[i, k] * route.K[k, l] * route.G[l, j] /
                          route.G[i, j]
                initial_log = log(max(initial, exp(log_flow_lower)))
                set_start_value(g[od, index],
                    clamp(initial_log, log_flow_lower + 1e-8,
                          log_flow_upper - 1e-8))
            end
        end
    end

    for od in 1:OD, k in 1:N
        k == od_destination[od] && continue
        @NLconstraint(model,
            occupancy[od, k] ==
            sum(exp(g[od, index]) for index in network.outgoing[k]))
    end

    invtheta = 1 / e.theta
    @NLexpression(model, route_log_cost[od=1:OD],
        sum(
            exp(g[od, index]) * network.log_edge_cost[index] +
            invtheta * exp(g[od, index]) *
                (g[od, index] -
                 log(occupancy[od, network.edge_origin[index]]))
            for index in 1:E
        ) - invtheta * log(occupancy[od, od_destination[od]]))

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
    route_log_value = value.(route_log_cost)
    route_cost = reshape(exp.(route_log_value), N, N)
    flow = zeros(Float64, N, N, N, N)
    dual_flow = zeros(Float64, N, N, N, N)
    for i in 1:N, j in 1:N
        od = od_index[i, j]
        for (index, (k, l)) in enumerate(network.edges)
            flow[i, j, k, l] = exp(value(g[od, index]))
            dual_flow[i, j, k, l] =
                route.G[i, k] * route.K[k, l] * route.G[l, j] /
                route.G[i, j]
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
