#!/usr/bin/env julia

using LinearAlgebra
using TOML
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, "..", ".."))

function nonlinear_solve(model, policy_pair::Int, shock::Float64)
    closure = model.closures.transport.F
    basis = model.basis
    n, qcount = size(model.closures.J0, 1), closure.Q
    state = zeros(n+qcount)
    theta = zeros(basis.P)
    theta[basis.policy_pairs[policy_pair]] = shock
    power = TNW.modal_power(model.project.modal)
    identity_pair = Matrix{Float64}(I, basis.P, basis.P)
    edge_aggregate = basis.L*basis.Sagg
    flow_z = closure.Xz
    flow_q = basis.L*(closure.Croute*(basis.Sagg*closure.G)) +
             power*(closure.G-edge_aggregate*closure.G)
    flow_theta = basis.L*(closure.Croute*basis.Sagg) +
                 power*(identity_pair-edge_aggregate)
    spatial_q = model.closures.B*basis.Sagg*closure.G
    spatial_theta = model.closures.B*basis.Sagg*theta

    for iteration in 1:20
        z = @view state[1:n]
        log_quantity = @view state[n+1:end]
        log_flow = flow_z*z+flow_q*log_quantity+flow_theta*theta
        exp_flow = exp.(log_flow)
        quantity = closure.A*exp_flow
        all(value -> isfinite(value) && value > 0, quantity) ||
            error("nonlinear transport quantities left the positive branch")
        residual = vcat(
            model.closures.J0*z+spatial_q*log_quantity+spatial_theta,
            log_quantity-log.(quantity),
        )
        norm(residual, Inf) < 1e-12 && return state, iteration, norm(residual, Inf)
        weighted = Diagonal(1 ./ quantity)*closure.A*Diagonal(exp_flow)
        jacobian = [model.closures.J0 spatial_q;
                    -weighted*flow_z Matrix{Float64}(I, qcount, qcount)-weighted*flow_q]
        state .-= jacobian\residual
    end
    error("nonlinear choice-logsum solve did not converge")
end

function stratified_indices(rows, count::Int=7)
    order = sortperm(getproperty.(rows, :hulten))
    positions = unique(round.(Int, range(1, length(order); length=min(count, length(order)))))
    return order[positions]
end

function main(args=ARGS)
    length(args) == 2 || error("usage: verify_choice_logsum_fd.jl CONFIG OUTPUT_TOML")
    config, output = abspath(args[1]), abspath(args[2])
    project = TNW.load_project(config)
    project.modal isa TNW.ChoiceLogsum || error("verification requires ChoiceLogsum")
    model = TNW.build_model(project)
    results = TNW.decompose_welfare(model)
    isempty(results.directed) && error("verification requires directed results")
    welfare_row = TNW.economic_welfare_gradient(model.data, model.closures.c)
    step = 1e-5
    samples = Dict{String,Any}[]
    max_absolute_error = 0.0
    max_relative_error = 0.0
    for pair in stratified_indices(results.directed)
        plus, plus_iterations, plus_residual = nonlinear_solve(model, pair, step)
        minus, minus_iterations, minus_residual = nonlinear_solve(model, pair, -step)
        n = size(model.closures.J0, 1)
        finite_difference = -dot(welfare_row, plus[1:n]-minus[1:n])/(2step)
        analytic = results.directed[pair].primitive_F
        absolute_error = abs(finite_difference-analytic)
        relative_error = absolute_error/max(abs(analytic), 1e-12)
        max_absolute_error = max(max_absolute_error, absolute_error)
        max_relative_error = max(max_relative_error, relative_error)
        push!(samples, Dict(
            "edge_id" => results.directed[pair].edge_id,
            "traffic" => results.directed[pair].hulten,
            "analytic" => analytic,
            "finite_difference" => finite_difference,
            "absolute_error" => absolute_error,
            "relative_error" => relative_error,
            "plus_iterations" => plus_iterations,
            "minus_iterations" => minus_iterations,
            "maximum_solve_residual" => max(plus_residual, minus_residual),
        ))
    end
    source_paths = [
        "src/CompleteEngine.jl",
        "src/kernels/AdjointRSUE.jl",
        "src/kernels/IFTDecomposition.jl",
        "replication/rsue/verify_choice_logsum_fd.jl",
    ]
    max_solve_residual = maximum(sample["maximum_solve_residual"] for sample in samples)
    passed = max_absolute_error <= 1e-6 && max_solve_residual <= 1e-10
    report = Dict{String,Any}(
        "schema_version" => 1,
        "verification_status" => passed ? "accepted" : "failed",
        "modal_specification" => "choice_logsum",
        "finite_difference_step" => step,
        "absolute_error_tolerance" => 1e-6,
        "solve_residual_tolerance" => 1e-10,
        "max_absolute_error" => max_absolute_error,
        "max_relative_error" => max_relative_error,
        "max_solve_residual" => max_solve_residual,
        "config_sha256" => TNW.file_sha256(config),
        "input_hashes" => model.data.input_hashes,
        "source_hashes" => Dict(path => TNW.file_sha256(joinpath(ROOT, path)) for path in source_paths),
        "samples" => samples,
    )
    mkpath(dirname(output))
    open(output, "w") do io
        TOML.print(io, report; sorted=true)
    end
    passed || error("choice-logsum finite-difference verification failed")
    println("choice-logsum finite differences accepted: max abs error = $max_absolute_error")
end

main()
