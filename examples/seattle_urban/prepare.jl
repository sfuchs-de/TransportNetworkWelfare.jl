using CSV
using SHA

const EXPECTED_NODES = "be2e30db8e32890e939a7f1e6fe5f6f893e7140ecac74fd2ddec41d83684796f"
const EXPECTED_ADJACENCY = "c8264f6e94c9a87084313cca19f297ebafc7253bb1b3ed054c7f6c079ffc47d7"

sha256_file(path) = bytes2hex(open(SHA.sha256, path))

function source_path(root, name)
    candidates = (
        joinpath(root, "counterfactuals", "seattle", name),
        joinpath(root, "ReplicationFinal", "counterfactuals", "seattle", name),
    )
    path = findfirst(isfile, candidates)
    path === nothing && error("could not find $name below AA_REPLICATION_ROOT=$root")
    return candidates[path]
end

function main()
    root = get(ENV, "AA_REPLICATION_ROOT", "")
    isempty(root) && error("set AA_REPLICATION_ROOT to the extracted Allen-Arkolakis replication")
    nodes_path = source_path(root, "node_lr_lf_seattle.csv")
    adjacency_path = source_path(root, "sparse_adjmat_seattle.csv")
    sha256_file(nodes_path) == EXPECTED_NODES || error("Seattle node-file hash mismatch")
    sha256_file(adjacency_path) == EXPECTED_ADJACENCY || error("Seattle adjacency-file hash mismatch")
    nodes = collect(CSV.File(nodes_path; header=false))
    edges = collect(CSV.File(adjacency_path; header=false))
    length(nodes) == 217 || error("expected 217 Seattle nodes")
    length(edges) == 1384 || error("expected 1384 directed Seattle edges")

    output = joinpath(@__DIR__, "generated")
    data = joinpath(output, "data")
    mkpath(data)
    open(joinpath(data, "nodes.csv"), "w") do io
        println(io, "node_id,residents,employment,longitude,latitude")
        for row in nodes
            println(io, join((row.Column1, row.Column2, row.Column3,
                              row.Column4, row.Column5), ','))
        end
    end
    open(joinpath(data, "edge_modes.csv"), "w") do io
        println(io, "edge_id,physical_link_id,origin,destination,mode,flow")
        for row in edges
            i, j = Int(row.Column1), Int(row.Column2)
            link = i < j ? "$(i)-$(j)" : "$(j)-$(i)"
            println(io, "$(i)-$(j),$link,$i,$j,road,$(row.Column3)")
        end
    end
    cp(joinpath(@__DIR__, "config.template.toml"), joinpath(output, "config.toml"); force=true)
    println(joinpath(output, "config.toml"))
end

main()
