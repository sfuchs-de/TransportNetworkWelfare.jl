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

end # module
