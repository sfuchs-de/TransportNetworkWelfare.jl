module ModalConventionTests

using Test
using LinearAlgebra
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare

function central_jacobian(function_value, point; step=1e-6)
    result = zeros(length(function_value(point)), length(point))
    for j in eachindex(point)
        plus, minus = copy(point), copy(point)
        plus[j] += step
        minus[j] -= step
        result[:, j] .= (function_value(plus)-function_value(minus))/(2step)
    end
    return result
end

function nonlinear_modal_logflows(costs, shares, specification, sigma)
    power = TNW.modal_power(specification)
    log_index = log(sum(shares .* exp.(power .* costs))) / power
    return (1-sigma-power) .* log_index .+ power .* costs
end

function solve_full_closure(model, pair, delta; step=1e-6)
    closure = model.closures.transport.F
    basis = model.basis
    n = size(model.closures.J0, 1)
    qcount = closure.Q
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
            (log_pair_flow .+= TNW.modal_power(model.project.modal) .*
                (modal_cost-basis.L*edge_cost))
        spatial = model.closures.J0*z + model.closures.B*edge_cost
        qcount == 0 && return spatial
        quantities = closure.A*exp.(log_pair_flow)
        return vcat(spatial, log_quantity-log.(quantities))
    end

    for _ in 1:40
        current = residual(state)
        norm(current, Inf) < 1e-13 && return state
        state .-= central_jacobian(residual, state; step) \ current
    end
    error("nonlinear closure finite-difference solve did not converge")
end

@testset "Both modal conventions match independent nonlinear derivatives" begin
    shares = [0.23, 0.31, 0.46]
    sigma, eta = 5.0, 1.7
    for specification in (ChoiceLogsum(eta), ComponentCES(eta))
        power = TNW.modal_power(specification)
        expected = (1-sigma-power) .* (ones(3)*permutedims(shares)) .+
            power .* Matrix{Float64}(I, 3, 3)
        finite_difference = central_jacobian(
            costs -> nonlinear_modal_logflows(costs, shares, specification, sigma),
            zeros(3),
        )
        @test finite_difference ≈ expected atol=1e-9 rtol=1e-9
    end
    @test TNW.modal_power(ChoiceLogsum(eta)) == -eta
    @test TNW.modal_power(ComponentCES(eta)) == eta
end

@testset "Modal and congestion limiting cases" begin
    config = normpath(joinpath(@__DIR__, "..", "examples", "toy", "config.toml"))
    project = load_project(config)
    model = build_model(project)

    mktempdir() do directory
        mkpath(joinpath(directory, "data"))
        nodes = read(joinpath(dirname(config), "data", "nodes.csv"), String)
        edge_lines = split(chomp(read(joinpath(dirname(config), "data", "edge_modes.csv"), String)), '\n')
        road_only = vcat(edge_lines[1], filter(line -> occursin(",road,", line), edge_lines[2:end]))
        write(joinpath(directory, "data", "nodes.csv"), nodes)
        write(joinpath(directory, "data", "edge_modes.csv"), join(road_only, '\n')*"\n")
        raw_config = read(config, String)
        raw_config = replace(raw_config, "mode_order = [\"road\", \"rail\"]" => "mode_order = [\"road\"]")
        raw_config = replace(raw_config, "specification = \"composite\"" => "specification = \"edge\"")
        write(joinpath(directory, "config.toml"), raw_config)
        one_model = build_model(load_project(joinpath(directory, "config.toml")))
        @test one_model.closures.F ≈ one_model.closures.FM atol=1e-12 rtol=0
    end

    zero_terminal = TNW.replace_project(project; congestion=CompositeCongestion(
        EdgeCongestion(Dict(:road => 0.05)),
        EndpointTerminalCongestion(Dict(:rail => 0.0)),
    ))
    zero_model = TNW.model_at(model, zero_terminal)
    @test zero_model.closures.NT ≈ zero_model.closures.F atol=1e-12 rtol=0
end

@testset "Choice-logsum paper derivative matches central finite differences" begin
    config = normpath(joinpath(@__DIR__, "..", "examples", "toy", "config.toml"))
    baseline = build_model(load_project(config))
    cases = (
        efficient=TNW.replace_project(
            baseline.project; alpha=0.0, beta=0.0, congestion=NoCongestion()),
        externality=TNW.replace_project(
            baseline.project; congestion=NoCongestion()),
        congestion=TNW.replace_project(
            baseline.project; congestion=EdgeCongestion(Dict(:road => 0.05))),
    )
    shock = 1e-5
    for (name, project) in pairs(cases)
        model = TNW.model_at(baseline, project)
        @test model.project.modal isa ChoiceLogsum
        result = decompose_welfare(model)
        welfare_row = TNW.AdjointRSUE.welfare_gradient(
            model.data.omega, model.closures.c)
        for pair in eachindex(model.basis.policy_pairs)
            plus = solve_full_closure(model, pair, shock)
            minus = solve_full_closure(model, pair, -shock)
            n = size(model.closures.J0, 1)
            finite_difference = -dot(welfare_row, plus[1:n]-minus[1:n])/(2shock)
            analytic = result.directed[pair].primitive_F
            @test finite_difference ≈ analytic atol=1e-8 rtol=1e-6
        end
        @test result.diagnostics["verified"]
        @test name in (:efficient, :externality, :congestion)
    end
end

@testset "Heterogeneous edge congestion matches nonlinear finite differences" begin
    source = normpath(joinpath(@__DIR__, "..", "examples", "toy"))
    mktempdir() do directory
        mkpath(joinpath(directory, "data"))
        cp(joinpath(source, "data", "nodes.csv"), joinpath(directory, "data", "nodes.csv"))
        lines = split(chomp(read(joinpath(source, "data", "edge_modes.csv"), String)), '\n')
        output = [lines[1]*",congestion_elasticity"]
        road_values = Dict("AB" => 0.02, "BA" => 0.03, "AC" => 0.04,
                           "CA" => 0.05, "BC" => 0.06, "CB" => 0.07)
        for line in lines[2:end]
            cells = split(line, ','; keepempty=true)
            value = cells[5] == "road" ? road_values[cells[1]] : 0.0
            push!(output, line*","*string(value))
        end
        write(joinpath(directory, "data", "edge_modes.csv"), join(output, '\n')*"\n")
        config = read(joinpath(source, "config.toml"), String)
        old = """[congestion]
specification = "composite"
endpoint_scale = 1.0

[congestion.edge]
road = 0.05

[congestion.terminal]
rail = 0.03
"""
        new = """[congestion]
specification = "edge"
source = "input_column"
column = "congestion_elasticity"
scale = 1.0
"""
        write(joinpath(directory, "config.toml"), replace(config, old => new))
        model = build_model(load_project(joinpath(directory, "config.toml")))
        result = decompose_welfare(model)
        welfare_row = TNW.AdjointRSUE.welfare_gradient(
            model.data.omega, model.closures.c)
        shock = 1e-5
        for pair in eachindex(model.basis.policy_pairs)
            plus = solve_full_closure(model, pair, shock)
            minus = solve_full_closure(model, pair, -shock)
            n = size(model.closures.J0, 1)
            finite_difference = -dot(welfare_row, plus[1:n]-minus[1:n])/(2shock)
            @test finite_difference ≈ result.directed[pair].primitive_F atol=1e-8 rtol=1e-6
        end
    end
end

end # module
