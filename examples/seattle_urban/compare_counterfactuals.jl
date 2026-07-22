using CSV
using LinearAlgebra
using Statistics
using TransportNetworkWelfare

function source_path(root, name)
    candidates = (
        joinpath(root, "counterfactuals", "seattle", name),
        joinpath(root, "ReplicationFinal", "counterfactuals", "seattle", name),
    )
    index = findfirst(isfile, candidates)
    index === nothing && error("could not find $name below AA_REPLICATION_ROOT=$root")
    return candidates[index]
end

function correlation(left, right)
    l = left .- mean(left)
    r = right .- mean(right)
    return dot(l, r)/(sqrt(dot(l, l))*sqrt(dot(r, r)))
end

function main()
    root = get(ENV, "AA_REPLICATION_ROOT", "")
    isempty(root) && error("set AA_REPLICATION_ROOT to the extracted replication archive")
    exact_path = source_path(root, "all_chi_lr_lf_ber.csv")
    ift_path = joinpath(@__DIR__, "generated", "output", "welfare_directed.csv")
    isfile(ift_path) || error("run prepare.jl and the analyze command first")

    ift = Dict((Int(row.origin), Int(row.destination)) => row.primitive_F
               for row in CSV.File(ift_path))
    exact = Dict{Tuple{Int,Int},Float64}()
    for row in CSV.File(exact_path; header=false)
        key = (Int(row.Column1), Int(row.Column2))
        haskey(exact, key) || (exact[key] = Float64(row.Column4))
    end
    keys(ift) == keys(exact) || error("IFT and exact-hat edge identifiers differ")
    ordered = sort!(collect(keys(ift)))
    local_values = [ift[key] for key in ordered]
    finite_values = [(-log(exact[key])/6.83)/(-log(0.99)) for key in ordered]
    summary = Dict(
        "edges" => length(ordered),
        "correlation" => correlation(local_values, finite_values),
        "mean_local_ift" => mean(local_values),
        "mean_finite_one_percent" => mean(finite_values),
        "maximum_absolute_difference" => maximum(abs.(local_values-finite_values)),
        "interpretation" => "local derivative versus finite one-percent counterfactual",
    )
    println(TransportNetworkWelfare.json_value(summary))
end

main()
