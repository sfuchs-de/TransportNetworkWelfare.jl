using SparseArrays
using LinearAlgebra

function external_central_jacobian(function_value, point; step=1e-6)
    result = zeros(length(function_value(point)), length(point))
    for j in eachindex(point)
        plus, minus = copy(point), copy(point)
        plus[j] += step
        minus[j] -= step
        result[:, j] .= (function_value(plus)-function_value(minus))/(2step)
    end
    return result
end

function solve_external_closure(model, pair, delta)
    closure = model.closures.transport.F
    basis = model.basis
    n, qcount = size(model.closures.J0, 1), closure.Q
    state = zeros(n+qcount)
    theta = zeros(basis.P)
    theta[basis.policy_pairs[pair]] = delta
    function residual(value)
        z = @view value[1:n]
        log_quantity = @view value[n+1:end]
        modal_cost = theta + closure.G*log_quantity
        edge_cost = basis.Sagg*modal_cost
        log_pair_flow = closure.Xz*z + basis.L*(closure.Croute*edge_cost)
        !closure.fixed_modal &&
            (log_pair_flow .+= TransportNetworkWelfare.modal_power(model.project.modal) .*
                (modal_cost-basis.L*edge_cost))
        spatial = model.closures.J0*z + model.closures.B*edge_cost
        qcount == 0 && return spatial
        quantities = closure.A*exp.(log_pair_flow)
        return vcat(spatial, log_quantity-log.(quantities))
    end
    for _ in 1:40
        current = residual(state)
        norm(current, Inf) < 1e-13 && return state
        state .-= external_central_jacobian(residual, state) \ current
    end
    error("external-node finite-difference solve did not converge")
end

function external_node_fixture()
    directory = mktempdir()
    write(joinpath(directory, "nodes.csv"), """
node_id,labor,income,external_supply,external_demand
A,1.0,1.0,0,0
B,1.0,1.0,0,0
F,1.0,1.0,0.1,0.1
""")
    write(joinpath(directory, "edge_modes.csv"), """
edge_id,physical_link_id,origin,destination,mode,flow
AB,AB,A,B,road,0.020
BA,AB,B,A,road,0.020
AF,AF,A,F,road,0.010
FA,AF,F,A,road,0.010
BF,BF,B,F,road,0.015
FB,BF,F,B,road,0.015
""")
    write(joinpath(directory, "config.toml"), """
schema_version = 1
name = "external-node-fixture"

[input]
adapter = "generic_csv_v1"
nodes = "nodes.csv"
edge_modes = "edge_modes.csv"
mode_order = ["road"]

[input.transformations]
normalize_labor = true
normalize_income = true
flow_conversion = "none"
symmetrize = false
pad_nodes = 0
modal_rescale = false

[model]
spatial_specification = "economic_geography"
external_nodes = ["F"]
alpha = 0.10
beta = -0.30
sigma = 9.0
eta = 1.099
modal_specification = "choice_logsum"
route_curvature = "theorem"

[congestion]
specification = "edge"

[congestion.edge]
road = 0.05

[policy]
mode = "road"
unit = "both"
shock_fraction = 0.01

[output]
directory = "output"

[diagnostics]
tolerance = 1.0e-10
condition_limit = 1.0e12
""")
    return joinpath(directory, "config.toml")
end

@testset "Fixed external supply and demand closure" begin
    project = load_project(external_node_fixture())
    @test project.spatial isa EconomicGeography
    @test project.spatial.external_node_ids == ["F"]
    report = validate(project)
    @test report.nodes == 3
    @test report.equilibrium_closure == "fixed_external_supply_demand"
    @test report.welfare_constituency == "endogenous_residents"
    @test report.endogenous_nodes == 2
    @test report.external_nodes == 1

    data = TransportNetworkWelfare.load_network(project)
    @test data.endogenous == Bool[true, true, false]
    @test data.normalization_node == 2
    @test data.omega == [0.5, 0.5, 0.0]
    @test data.nu == [0.5, 0.5, 0.0]
    @test data.source_margin == [0.5, 0.5, 0.1]
    @test data.destination_margin == [0.5, 0.5, 0.1]

    model = build_model(project)
    @test size(model.closures.J0) == (4, 4)
    @test size(model.closures.B, 1) == 4
    @test model.basis.diagnostics.row_error < 1e-12
    @test model.basis.diagnostics.column_error < 1e-12
    @test model.basis.diagnostics.edge_error < 1e-12

    c = model.closures.c
    state_map = TransportNetworkWelfare.inverse_state_map(
        data.N, data.omega, c; endogenous=data.endogenous)
    @test maximum(abs, state_map[3, :]) == 0
    @test maximum(abs, state_map[data.N+3, :]) == 0

    result = decompose_welfare(model)
    @test result.diagnostics["verified"]
    @test result.diagnostics["equilibrium_closure"] == "fixed_external_supply_demand"
    @test result.diagnostics["welfare_constituency"] == "endogenous_residents"
    @test result.diagnostics["hulten_collapse_applicable"] === false
    @test result.diagnostics["endogenous_nodes"] == 2
    @test result.diagnostics["external_nodes"] == 1
    @test length(result.physical) == 3
    @test all(row -> isfinite(row.primitive_F), result.physical)

    q = TransportNetworkWelfare.economic_welfare_gradient(data, c)
    shock = 1e-5
    for pair in eachindex(model.basis.policy_pairs)
        plus = solve_external_closure(model, pair, shock)
        minus = solve_external_closure(model, pair, -shock)
        finite_difference = -dot(q, plus[1:4]-minus[1:4])/(2shock)
        @test finite_difference ≈ result.directed[pair].primitive_F atol=1e-8 rtol=1e-6
    end
end

@testset "External schedules fail explicitly" begin
    config = external_node_fixture()
    nodes_path = joinpath(dirname(config), "nodes.csv")
    write(nodes_path, replace(read(nodes_path, String), "0.1,0.1" => "0.1,"))
    @test_throws ArgumentError validate(load_project(config))
end
