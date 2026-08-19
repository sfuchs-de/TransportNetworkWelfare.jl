module VerificationProvenance

using Printf
using SHA
using SparseArrays

const SOURCE_HASH_SCOPE =
    "all Julia package sources under src plus the RSUE finite-difference verification sources"
const INDEPENDENCE_SCOPE =
    "independent nonlinear equilibrium solve conditional on package-constructed baseline operators and welfare row"

file_sha256(path::AbstractString) = bytes2hex(open(SHA.sha256, path))
portable_path(path::AbstractString) = replace(path, '\\' => '/')

function verification_source_paths(root::AbstractString)
    source_root = joinpath(root, "src")
    paths = String[]
    for (directory, _, files) in walkdir(source_root)
        for file in files
            endswith(file, ".jl") || continue
            path = joinpath(directory, file)
            push!(paths, portable_path(relpath(path, root)))
        end
    end
    append!(paths, [
        "replication/rsue/verify_choice_logsum_fd.jl",
        "replication/rsue/verification/VerificationProvenance.jl",
    ])
    return sort!(unique!(paths))
end

function verification_source_hashes(root::AbstractString)
    return Dict(path => file_sha256(joinpath(root, path))
                for path in verification_source_paths(root))
end

function digest_hash_map(values::AbstractDict)
    io = IOBuffer()
    for key in sort!(collect(keys(values)); by=string)
        println(io, string(key), "=", values[key])
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

function numeric_array_sha256(values::AbstractArray)
    io = IOBuffer()
    println(io, "size=", join(size(values), ","))
    if issparse(values)
        rows, columns, entries = findnz(values)
        println(io, "nnz=", length(entries))
        for index in eachindex(entries)
            @printf(io, "%d,%d,%.12e\n",
                    rows[index], columns[index], Float64(entries[index]))
        end
    else
        for value in values
            @printf(io, "%.12e\n", Float64(value))
        end
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

function baseline_operator_hashes(model, welfare_row)
    closure = model.closures.transport.F
    operators = Dict{String,Any}(
        "basis_L" => model.basis.L,
        "basis_Sagg" => model.basis.Sagg,
        "spatial_B" => model.closures.B,
        "spatial_J0" => model.closures.J0,
        "transport_A" => closure.A,
        "transport_Croute" => closure.Croute,
        "transport_G" => closure.G,
        "transport_H" => closure.H,
        "transport_Jc" => closure.Jc,
        "transport_Kedge" => closure.Kedge,
        "transport_Qz_edge" => closure.Qz_edge,
        "transport_Xq" => closure.Xq,
        "transport_Xz" => closure.Xz,
        "transport_edge_cost_state" => closure.edge_cost_state,
        "transport_left" => closure.left,
        "transport_quantity_state" => closure.quantity_state,
        "transport_right" => closure.right,
        "welfare_row" => welfare_row,
    )
    return Dict(name => numeric_array_sha256(values)
                for (name, values) in operators)
end

function validate_source_provenance(report::AbstractDict, root::AbstractString)
    get(report, "schema_version", 0) == 2 ||
        error("choice-logsum verification report must use schema version 2")
    get(report, "source_hash_scope", "") == SOURCE_HASH_SCOPE ||
        error("choice-logsum verification report has an unexpected source-hash scope")
    get(report, "independence_scope", "") == INDEPENDENCE_SCOPE ||
        error("choice-logsum verification report has an unexpected independence scope")
    expected = verification_source_hashes(root)
    observed = Dict{String,String}(get(report, "source_hashes", Dict()))
    Set(keys(observed)) == Set(keys(expected)) ||
        error("choice-logsum verification report does not cover the complete Julia source set")
    for path in sort!(collect(keys(expected)))
        observed[path] == expected[path] ||
            error("choice-logsum verification report has a stale source hash: $path")
    end
    get(report, "source_tree_sha256", "") == digest_hash_map(observed) ||
        error("choice-logsum verification report has a stale source-tree hash")
    return true
end

function validate_operator_provenance(report::AbstractDict, model, welfare_row)
    expected = baseline_operator_hashes(model, welfare_row)
    observed = Dict{String,String}(get(report, "operator_hashes", Dict()))
    Set(keys(observed)) == Set(keys(expected)) ||
        error("choice-logsum verification report does not cover the complete baseline operator set")
    for name in sort!(collect(keys(expected)))
        observed[name] == expected[name] ||
            error("choice-logsum verification report has a stale baseline operator hash: $name")
    end
    get(report, "operator_bundle_sha256", "") == digest_hash_map(observed) ||
        error("choice-logsum verification report has a stale operator-bundle hash")
    return true
end

end # module
