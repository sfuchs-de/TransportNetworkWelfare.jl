#!/usr/bin/env julia

module CowMeshBuilder

using LinearAlgebra
using Printf
using SHA
using Statistics
using TOML
using TransportNetworkWelfare

const ROOT = @__DIR__
const DEFAULT_MESH = joinpath(ROOT, "assets", "cow.ply")
const DEFAULT_OUTPUT = joinpath(ROOT, "mesh_data")
const SOURCE_MANIFEST = joinpath(ROOT, "sources.toml")

sha256(path) = bytes2hex(open(SHA.sha256, path))

function read_ascii_ply(path)
    open(path) do io
        strip(readline(io)) == "ply" || error("$path is not a PLY file")
        ascii = false
        vertex_count = face_count = 0
        while !eof(io)
            line = strip(readline(io))
            line == "format ascii 1.0" && (ascii = true)
            startswith(line, "element vertex ") &&
                (vertex_count = parse(Int, split(line)[end]))
            startswith(line, "element face ") &&
                (face_count = parse(Int, split(line)[end]))
            line == "end_header" && break
        end
        ascii && vertex_count > 0 && face_count > 0 ||
            error("$path must be a nonempty ASCII PLY 1.0 mesh")
        vertices = Matrix{Float64}(undef, vertex_count, 3)
        for i in 1:vertex_count
            values = split(readline(io))
            length(values) >= 3 || error("incomplete PLY vertex table")
            vertices[i, :] .= parse.(Float64, values[1:3])
        end
        faces = Vector{Vector{Int}}(undef, face_count)
        for f in 1:face_count
            values = parse.(Int, split(readline(io)))
            length(values) == values[1]+1 || error("invalid PLY polygon face")
            face = values[2:end] .+ 1
            all(index -> 1 <= index <= vertex_count, face) ||
                error("PLY face contains an invalid vertex index")
            faces[f] = face
        end
        return vertices, faces
    end
end

function mesh_edges(faces)
    edges = Set{Tuple{Int,Int}}()
    for face in faces
        for q in eachindex(face)
            i, j = face[q], face[mod1(q+1, length(face))]
            i == j && error("PLY face contains a self-edge")
            push!(edges, minmax(i, j))
        end
    end
    return sort!(collect(edges))
end

function activity_weights(vertices)
    lower = vec(minimum(vertices; dims=1))
    span = vec(maximum(vertices; dims=1))-lower
    all(>(0), span) || error("mesh vertices must span three dimensions")
    x = @. 2*(vertices[:, 1]-lower[1])/span[1]-1
    height = @. (vertices[:, 2]-lower[2])/span[2]
    depth_scale = maximum(abs, vertices[:, 3])
    depth = vertices[:, 3] ./ depth_scale
    body = @. exp(-((x+0.30)/0.70)^2-((height-0.55)/0.45)^2-(depth/0.90)^2)
    head = @. exp(-((x-0.72)/0.27)^2-((height-0.58)/0.32)^2-(depth/0.85)^2)
    weights = @. 0.10+1.25*body+head
    return weights ./ sum(weights)
end

function balanced_edge_flows(vertices, edges, income; openness=0.75, tolerance=1e-12)
    0 < openness < 1 || error("openness must lie in (0,1)")
    lengths = [norm(vertices[i, :]-vertices[j, :]) for (i, j) in edges]
    median_length = median(lengths)
    affinity = exp.(-lengths ./ median_length)
    target = openness .* income
    weighted_degree = zeros(length(income))
    for (q, (i, j)) in enumerate(edges)
        weighted_degree[i] += affinity[q]
        weighted_degree[j] += affinity[q]
    end
    all(>(0), weighted_degree) || error("mesh contains an isolated vertex")
    scaling = sqrt.(target ./ weighted_degree)
    relative_error = Inf
    iterations = 0
    for iteration in 1:20_000
        neighbor_sum = zeros(length(income))
        for (q, (i, j)) in enumerate(edges)
            neighbor_sum[i] += affinity[q]*scaling[j]
            neighbor_sum[j] += affinity[q]*scaling[i]
        end
        ratio = target ./ (scaling .* neighbor_sum)
        relative_error = maximum(abs.(ratio .- 1))
        iterations = iteration
        relative_error <= tolerance && break
        scaling .*= sqrt.(ratio)
    end
    relative_error <= tolerance ||
        error("symmetric flow balancing did not converge: $relative_error")
    flow = [scaling[i]*affinity[q]*scaling[j] for (q, (i, j)) in enumerate(edges)]
    outgoing = zeros(length(income))
    for (value, (i, j)) in zip(flow, edges)
        outgoing[i] += value
        outgoing[j] += value
    end
    balance_error = maximum(abs.(outgoing-target))
    return (; flow, balance_error, iterations, relative_error, median_length, openness)
end

vertex_id(i) = @sprintf("V%04d", i)

function write_network(output, vertices, edges, income, balanced)
    mkpath(output)
    nodes_path = joinpath(output, "nodes.csv")
    edges_path = joinpath(output, "edge_modes.csv")
    open(nodes_path, "w") do io
        println(io, "node_id,labor,income,longitude,latitude,elevation")
        for i in axes(vertices, 1)
            @printf(io, "%s,%.17g,%.17g,%.17g,%.17g,%.17g\n",
                vertex_id(i), income[i], income[i], vertices[i, 1],
                vertices[i, 2], vertices[i, 3])
        end
    end
    open(edges_path, "w") do io
        println(io, "edge_id,physical_link_id,origin,destination,mode,flow,origin_terminal_id,destination_terminal_id")
        for (q, ((i, j), flow)) in enumerate(zip(edges, balanced.flow))
            physical = @sprintf("M%05d", q)
            @printf(io, "%sF,%s,%s,%s,road,%.17g,,\n",
                physical, physical, vertex_id(i), vertex_id(j), flow)
            @printf(io, "%sR,%s,%s,%s,road,%.17g,,\n",
                physical, physical, vertex_id(j), vertex_id(i), flow)
        end
    end
    return nodes_path, edges_path
end

function main(args=ARGS)
    mesh = isempty(args) ? DEFAULT_MESH : abspath(args[1])
    output = length(args) < 2 ? DEFAULT_OUTPUT : abspath(args[2])
    isfile(mesh) || error("missing $mesh; run python examples/cow/prepare_surface.py")
    specification = TOML.parsefile(SOURCE_MANIFEST)["mesh"]
    actual_hash = sha256(mesh)
    actual_hash == specification["sha256"] ||
        error("cow mesh hash $actual_hash does not match sources.toml")
    vertices, faces = read_ascii_ply(mesh)
    size(vertices, 1) == specification["vertices"] || error("unexpected vertex count")
    length(faces) == specification["faces"] || error("unexpected face count")
    edges = mesh_edges(faces)
    income = activity_weights(vertices)
    balanced = balanced_edge_flows(vertices, edges, income)
    nodes_path, edges_path = write_network(output, vertices, edges, income, balanced)
    manifest = Dict{String,Any}(
        "source_mesh_sha256" => actual_hash,
        "nodes" => size(vertices, 1),
        "faces" => length(faces),
        "physical_links" => length(edges),
        "directed_arcs" => 2*length(edges),
        "traffic_to_income_ratio" => balanced.openness,
        "flow_balance_error" => balanced.balance_error,
        "scaling_iterations" => balanced.iterations,
        "scaling_relative_error" => balanced.relative_error,
        "median_mesh_edge_length" => balanced.median_length,
        "generated_hashes" => Dict(
            "nodes.csv" => sha256(nodes_path),
            "edge_modes.csv" => sha256(edges_path),
        ),
        "calibration" => [
            "labor_share=income_share=positive body/head activity mixture",
            "undirected_link_affinity=exp(-mesh_edge_length/median_mesh_edge_length)",
            "symmetric_matrix_scaling enforces outgoing_flow=0.75*income_share",
            "each mesh edge becomes two equal-flow directed road arcs",
        ],
    )
    manifest_path = joinpath(output, "build_manifest.json")
    open(manifest_path, "w") do io
        println(io, TransportNetworkWelfare.json_value(manifest))
    end
    println(TransportNetworkWelfare.json_value(merge(manifest, Dict(
        "status" => "ok", "output" => output))))
end

end # module

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    CowMeshBuilder.main()
end
