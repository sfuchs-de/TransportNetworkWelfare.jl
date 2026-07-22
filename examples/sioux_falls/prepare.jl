#!/usr/bin/env julia

module SiouxFallsBuilder

using Downloads
using Printf
using SHA
using TOML
using TransportNetworkWelfare

const EXAMPLE_ROOT = @__DIR__
const SOURCE_MANIFEST = joinpath(EXAMPLE_ROOT, "sources.toml")

sha256(path::AbstractString) = bytes2hex(open(SHA.sha256, path))

function source_specifications(manifest_path::AbstractString=SOURCE_MANIFEST)
    manifest = TOML.parsefile(manifest_path)
    files = Dict{String,NamedTuple}()
    for (name, entry) in manifest["files"]
        files[String(name)] = (url=String(entry["url"]), sha256=String(entry["sha256"]))
    end
    return (; commit=String(manifest["commit"]), files)
end

function verified_sources(source_dir::AbstractString; download::Bool=true,
                          manifest_path::AbstractString=SOURCE_MANIFEST)
    specification = source_specifications(manifest_path)
    mkpath(source_dir)
    paths = Dict{String,String}()
    for name in sort!(collect(keys(specification.files)))
        entry = specification.files[name]
        path = joinpath(source_dir, name)
        if !isfile(path)
            download || throw(ArgumentError(
                "missing cached Sioux Falls source $path; rerun without --offline"))
            temporary = tempname(source_dir)
            Downloads.download(entry.url, temporary)
            actual = sha256(temporary)
            actual == entry.sha256 || throw(ArgumentError(
                "downloaded $name has SHA-256 $actual; expected $(entry.sha256)"))
            mv(temporary, path; force=true)
        end
        actual = sha256(path)
        actual == entry.sha256 || throw(ArgumentError(
            "cached $name has SHA-256 $actual; expected $(entry.sha256)"))
        paths[name] = path
    end
    return (; commit=specification.commit, paths,
            hashes=Dict(name => specification.files[name].sha256 for name in keys(paths)))
end

function parse_network(path::AbstractString)
    links = Dict{Tuple{Int,Int},NamedTuple}()
    for (line_number, raw) in enumerate(eachline(path))
        fields = split(strip(replace(raw, ';' => ' ')))
        length(fields) == 10 || continue
        origin, destination = tryparse(Int, fields[1]), tryparse(Int, fields[2])
        origin === nothing && continue
        destination === nothing && continue
        key = (origin, destination)
        haskey(links, key) &&
            throw(ArgumentError("duplicate network link $key at line $line_number"))
        values = parse.(Float64, fields[3:10])
        links[key] = (capacity=values[1], length=values[2],
            free_flow_time=values[3], b=values[4], power=values[5],
            speed=values[6], toll=values[7], link_type=values[8])
    end
    isempty(links) && throw(ArgumentError("no network links parsed from $path"))
    return links
end

function parse_flows(path::AbstractString)
    flows = Dict{Tuple{Int,Int},NamedTuple}()
    for (line_number, raw) in enumerate(eachline(path))
        fields = split(strip(raw))
        length(fields) == 4 || continue
        origin, destination = tryparse(Int, fields[1]), tryparse(Int, fields[2])
        origin === nothing && continue
        destination === nothing && continue
        key = (origin, destination)
        haskey(flows, key) &&
            throw(ArgumentError("duplicate assigned flow $key at line $line_number"))
        volume, cost = parse.(Float64, fields[3:4])
        volume > 0 || throw(ArgumentError("assigned flow $key must be positive"))
        flows[key] = (; volume, cost)
    end
    isempty(flows) && throw(ArgumentError("no assigned flows parsed from $path"))
    return flows
end

function parse_nodes(path::AbstractString)
    nodes = Dict{Int,Tuple{Float64,Float64}}()
    for (line_number, raw) in enumerate(eachline(path))
        fields = split(strip(replace(raw, ';' => ' ')))
        length(fields) == 3 || continue
        node = tryparse(Int, fields[1])
        node === nothing && continue
        haskey(nodes, node) &&
            throw(ArgumentError("duplicate node $node at line $line_number"))
        nodes[node] = (parse(Float64, fields[2]), parse(Float64, fields[3]))
    end
    isempty(nodes) && throw(ArgumentError("no nodes parsed from $path"))
    return nodes
end

function parse_trips(path::AbstractString)
    text = read(path, String)
    total_match = match(r"<TOTAL OD FLOW>\s+([0-9.eE+-]+)", text)
    total_match === nothing && throw(ArgumentError("trip file lacks TOTAL OD FLOW metadata"))
    total = parse(Float64, total_match.captures[1])
    matrix = zeros(24, 24)
    origin = nothing
    for raw in eachline(IOBuffer(text))
        origin_match = match(r"^\s*Origin\s+(\d+)", raw)
        if origin_match !== nothing
            origin = parse(Int, origin_match.captures[1])
            continue
        end
        origin === nothing && continue
        for item in eachmatch(r"(\d+)\s*:\s*([0-9.eE+-]+)", raw)
            destination = parse(Int, item.captures[1])
            matrix[origin, destination] = parse(Float64, item.captures[2])
        end
    end
    abs(sum(matrix)-total) <= 1e-8*max(total, 1.0) ||
        throw(ArgumentError("trip entries do not sum to TOTAL OD FLOW"))
    return (; matrix, total)
end

function bpr_elasticity(volume, capacity, b, power)
    all(isfinite, (volume, capacity, b, power)) ||
        throw(ArgumentError("BPR inputs must be finite"))
    volume >= 0 && capacity > 0 && b >= 0 && power >= 0 ||
        throw(ArgumentError("BPR inputs have invalid signs"))
    load = b*(volume/capacity)^power
    return power*load/(1+load)
end

function validate_benchmark(nodes, links, flows, trips)
    sort!(collect(keys(nodes))) == collect(1:24) ||
        throw(ArgumentError("expected Sioux Falls nodes 1:24"))
    Set(keys(links)) == Set(keys(flows)) ||
        throw(ArgumentError("network and assigned-flow directed links differ"))
    length(links) == 76 || throw(ArgumentError("expected 76 directed links"))
    for (i, j) in keys(links)
        haskey(links, (j, i)) || throw(ArgumentError("link $i->$j lacks its reciprocal"))
    end
    physical = Set((min(i, j), max(i, j)) for (i, j) in keys(links))
    length(physical) == 38 || throw(ArgumentError("expected 38 physical links"))
    productions = vec(sum(trips.matrix; dims=2))
    attractions = vec(sum(trips.matrix; dims=1))
    raw_margin_error = maximum(abs.(productions-attractions))
    raw_balance = zeros(24)
    for ((i, j), flow) in flows
        raw_balance[i] += flow.volume
        raw_balance[j] -= flow.volume
    end
    raw_flow_error = maximum(abs, raw_balance)
    maximum(abs.(raw_balance .- (productions-attractions))) <= 1e-8 ||
        throw(ArgumentError(
            "assigned-flow imbalances do not reproduce the published OD margins"))

    balanced_margins = (productions+attractions)./2
    balanced_flows = Dict{Tuple{Int,Int},NamedTuple}()
    for (i, j) in keys(flows)
        volume = (flows[(i, j)].volume+flows[(j, i)].volume)/2
        link = links[(i, j)]
        cost = link.free_flow_time*(1+link.b*(volume/link.capacity)^link.power)
        balanced_flows[(i, j)] = (; volume, cost)
    end
    balance = zeros(24)
    for ((i, j), flow) in balanced_flows
        balance[i] += flow.volume
        balance[j] -= flow.volume
    end
    balanced_flow_error = maximum(abs, balance)
    balanced_flow_error <= 1e-10 || throw(ArgumentError(
        "reciprocal-average link flows violate conservation by $balanced_flow_error"))
    abs(sum(balanced_margins)-trips.total) <= 1e-10*trips.total ||
        throw(ArgumentError("balanced OD margins do not preserve total trips"))
    all(>(0), balanced_margins) ||
        throw(ArgumentError("balanced OD margins must be strictly positive"))
    return (; physical_links=length(physical), balanced_margins, balanced_flows,
            raw_margin_error, raw_flow_error, balanced_flow_error)
end

function write_nodes(path, nodes, productions, total)
    open(path, "w") do io
        println(io, "node_id,labor,income,longitude,latitude")
        for node in sort!(collect(keys(nodes)))
            longitude, latitude = nodes[node]
            share = productions[node]/total
            @printf(io, "%d,%.17g,%.17g,%.17g,%.17g\n",
                    node, share, share, longitude, latitude)
        end
    end
end

function write_edges(path, links, flows, total)
    open(path, "w") do io
        println(io, join(("edge_id", "physical_link_id", "origin", "destination",
            "mode", "flow", "origin_terminal_id", "destination_terminal_id",
            "capacity", "free_flow_time", "bpr_b", "bpr_power", "assigned_cost",
            "congestion_elasticity"), ','))
        for (i, j) in sort!(collect(keys(links)))
            link, flow = links[(i, j)], flows[(i, j)]
            edge_id = "$(i)_$(j)"
            physical_id = "$(min(i,j))_$(max(i,j))"
            elasticity = bpr_elasticity(
                flow.volume, link.capacity, link.b, link.power)
            @printf(io, "%s,%s,%d,%d,road,%.17g,,,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g\n",
                edge_id, physical_id, i, j, flow.volume/total, link.capacity,
                link.free_flow_time, link.b, link.power, flow.cost, elasticity)
        end
    end
end

function build_example(source_dir::AbstractString, output_dir::AbstractString;
                       download::Bool=true, manifest_path::AbstractString=SOURCE_MANIFEST)
    sources = verified_sources(source_dir; download, manifest_path)
    nodes = parse_nodes(sources.paths["SiouxFalls_node.tntp"])
    links = parse_network(sources.paths["SiouxFalls_net.tntp"])
    flows = parse_flows(sources.paths["SiouxFalls_flow.tntp"])
    trips = parse_trips(sources.paths["SiouxFalls_trips.tntp"])
    checks = validate_benchmark(nodes, links, flows, trips)
    mkpath(output_dir)
    nodes_path = joinpath(output_dir, "nodes.csv")
    edges_path = joinpath(output_dir, "edge_modes.csv")
    write_nodes(nodes_path, nodes, checks.balanced_margins, trips.total)
    write_edges(edges_path, links, checks.balanced_flows, trips.total)
    generated = Dict{String,Any}(
        "source_commit" => sources.commit,
        "source_hashes" => sources.hashes,
        "generated_hashes" => Dict(
            "nodes.csv" => sha256(nodes_path), "edge_modes.csv" => sha256(edges_path)),
        "nodes" => length(nodes), "directed_links" => length(links),
        "physical_links" => checks.physical_links, "total_od_flow" => trips.total,
        "raw_od_margin_error" => checks.raw_margin_error,
        "raw_assigned_flow_balance_error" => checks.raw_flow_error,
        "balanced_assigned_flow_error" => checks.balanced_flow_error,
        "transformations" => [
            "balanced_margin=(od_production+od_attraction)/2",
            "labor_share=balanced_margin/total_od_flow",
            "income_share=balanced_margin/total_od_flow",
            "balanced_link_volume=(assigned_forward+assigned_reverse)/2",
            "edge_flow=balanced_link_volume/total_od_flow",
            "edge_congestion_elasticity=local_bpr_log_derivative",
        ],
    )
    manifest_output = joinpath(output_dir, "build_manifest.json")
    open(manifest_output, "w") do io
        println(io, TransportNetworkWelfare.json_value(generated))
    end
    return generated
end

function main(args=ARGS)
    offline = "--offline" in args
    source_dir = joinpath(EXAMPLE_ROOT, "raw")
    for (index, argument) in enumerate(args)
        argument == "--source-dir" && index < length(args) &&
            (source_dir = abspath(args[index+1]))
    end
    result = build_example(source_dir, joinpath(EXAMPLE_ROOT, "generated");
                           download=!offline)
    println(TransportNetworkWelfare.json_value(result))
    return 0
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(SiouxFallsBuilder.main())
end
