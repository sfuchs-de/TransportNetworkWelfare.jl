#!/usr/bin/env julia

module SeattleMultimodalBuilder

using CSV
using Dates
using Downloads
using Printf
using SHA
using TOML
using TransportNetworkWelfare

const EXAMPLE_ROOT = @__DIR__
const SOURCE_MANIFEST = joinpath(EXAMPLE_ROOT, "sources.toml")
const DEFAULT_SERVICE_DATE = Date(2017, 6, 14)
const ROAD_CONGESTION = 0.488 / 6.83

sha256_file(path::AbstractString) = bytes2hex(open(SHA.sha256, path))
sha1_file(path::AbstractString) = bytes2hex(open(SHA.sha1, path))

function source_path(root::AbstractString, candidates)
    for relative in candidates
        path = joinpath(root, relative)
        isfile(path) && return path
    end
    throw(ArgumentError(
        "none of the required source paths exists below $root: $(join(candidates, ", "))"))
end

function verified_aa_sources(root::AbstractString;
                             manifest_path::AbstractString=SOURCE_MANIFEST)
    specification = TOML.parsefile(manifest_path)["allen_arkolakis_replication"]
    paths = Dict(
        "nodes" => source_path(root, (
            joinpath("counterfactuals", "seattle", "node_lr_lf_seattle.csv"),
            joinpath("ReplicationFinal", "counterfactuals", "seattle",
                     "node_lr_lf_seattle.csv"),
        )),
        "adjacency" => source_path(root, (
            joinpath("counterfactuals", "seattle", "sparse_adjmat_seattle.csv"),
            joinpath("ReplicationFinal", "counterfactuals", "seattle",
                     "sparse_adjmat_seattle.csv"),
        )),
        "commute" => source_path(root, (
            joinpath("counterfactuals", "seattle", "sparse_commute_seattle.csv"),
            joinpath("ReplicationFinal", "counterfactuals", "seattle",
                     "sparse_commute_seattle.csv"),
        )),
        "crosswalk" => source_path(root, (
            joinpath("data", "seattle", "derived", "grid_seattle_area_xwalk.txt"),
            joinpath("ReplicationFinal", "data", "seattle", "derived",
                     "grid_seattle_area_xwalk.txt"),
        )),
    )
    expected = Dict(
        "nodes" => String(specification["nodes_sha256"]),
        "adjacency" => String(specification["adjacency_sha256"]),
        "commute" => String(specification["commute_sha256"]),
        "crosswalk" => String(specification["grid_block_group_crosswalk_sha256"]),
    )
    actual = Dict(name => sha256_file(path) for (name, path) in paths)
    for name in keys(expected)
        actual[name] == expected[name] || throw(ArgumentError(
            "Allen-Arkolakis $name hash mismatch: expected $(expected[name]), " *
            "observed $(actual[name])"))
    end
    return (; paths, hashes=actual, specification)
end

function read_aa_nodes(path::AbstractString)
    rows = collect(CSV.File(path; header=false))
    length(rows) == 217 || throw(ArgumentError("expected 217 Seattle grid nodes"))
    ids = Int[]
    longitude = Float64[]
    latitude = Float64[]
    for row in rows
        push!(ids, Int(row.Column1))
        push!(longitude, Float64(row.Column4))
        push!(latitude, Float64(row.Column5))
    end
    sort(ids) == collect(1:217) ||
        throw(ArgumentError("Seattle node IDs must be exactly 1:217"))
    return (; ids, longitude, latitude)
end

function read_commute_matrix(path::AbstractString, N::Int)
    commute = zeros(N, N)
    rows = 0
    for row in CSV.File(path; header=false)
        i, j, value = Int(row.Column1), Int(row.Column2), Float64(row.Column3)
        1 <= i <= N && 1 <= j <= N ||
            throw(ArgumentError("commute row has an out-of-range node"))
        isfinite(value) && value >= 0 ||
            throw(ArgumentError("commute flows must be finite and nonnegative"))
        commute[i, j] == 0 ||
            throw(ArgumentError("duplicate commute pair $i->$j"))
        commute[i, j] = value
        rows += 1
    end
    rows == 47_089 ||
        throw(ArgumentError("expected the complete 217-by-217 commute matrix"))
    total = sum(commute)
    total > 0 || throw(ArgumentError("commute matrix has zero total"))
    all(>(0), vec(sum(commute; dims=2))) ||
        throw(ArgumentError("every Seattle node must have positive resident commuters"))
    all(>(0), vec(sum(commute; dims=1))) ||
        throw(ArgumentError("every Seattle node must have positive workplace commuters"))
    return commute
end

function read_road_arcs(path::AbstractString)
    arcs = NamedTuple[]
    seen = Set{Tuple{Int,Int}}()
    for row in CSV.File(path; header=false)
        i, j = Int(row.Column1), Int(row.Column2)
        pair = (i, j)
        pair in seen && throw(ArgumentError("duplicate road arc $i->$j"))
        push!(seen, pair)
        time = Float64(row.Column5)
        isfinite(time) && time > 0 ||
            throw(ArgumentError("road travel time must be finite and positive"))
        push!(arcs, (; origin=i, destination=j, mode=:road, cost=60time,
                    service_count=1, route_count=1))
    end
    length(arcs) == 1_384 ||
        throw(ArgumentError("expected 1,384 directed Seattle road arcs"))
    for arc in arcs
        (arc.destination, arc.origin) in seen ||
            throw(ArgumentError("road arc $(arc.origin)->$(arc.destination) is not reciprocal"))
    end
    length(Set((min(a.origin, a.destination), max(a.origin, a.destination))
               for a in arcs)) == 692 ||
        throw(ArgumentError("expected 692 reciprocal Seattle road links"))
    return sort!(arcs; by=a -> (a.origin, a.destination))
end

"""
Parse the Census API's array-of-string-arrays response without adding a JSON
runtime dependency to the Julia package. The requested ACS endpoint returns
only strings and does not use nested objects or null values.
"""
function parse_census_string_rows(text::AbstractString)
    rows = Vector{Vector{String}}()
    row = String[]
    buffer = IOBuffer()
    depth = 0
    in_string = false
    escaped = false
    for character in text
        if in_string
            if escaped
                character == 'n' ? write(buffer, '\n') :
                character == 'r' ? write(buffer, '\r') :
                character == 't' ? write(buffer, '\t') : write(buffer, character)
                escaped = false
            elseif character == '\\'
                escaped = true
            elseif character == '"'
                push!(row, String(take!(buffer)))
                in_string = false
            else
                write(buffer, character)
            end
        elseif character == '"'
            in_string = true
        elseif character == '['
            depth += 1
            depth == 2 && (row = String[])
        elseif character == ']'
            if depth == 2
                isempty(row) ||
                    push!(rows, row)
            end
            depth -= 1
            depth >= 0 || throw(ArgumentError("malformed Census JSON array"))
        end
    end
    !in_string && depth == 0 ||
        throw(ArgumentError("unterminated Census JSON response"))
    isempty(rows) && throw(ArgumentError("Census response contains no rows"))
    return rows
end

function read_acs_commute_modes(path::AbstractString)
    isfile(path) || throw(ArgumentError("ACS response not found: $path"))
    rows = parse_census_string_rows(read(path, String))
    header = first(rows)
    required = (
        "B08301_001E", "B08301_010E", "state", "county", "tract", "block group",
    )
    indices = Dict(name => findfirst(==(name), header) for name in required)
    all(value -> value !== nothing, values(indices)) ||
        throw(ArgumentError("ACS response lacks one or more required fields"))
    estimates = Dict{String,NamedTuple}()
    suppressed = 0
    for row in rows[2:end]
        total = parse(Float64, row[indices["B08301_001E"]])
        transit = parse(Float64, row[indices["B08301_010E"]])
        if total < 0 || transit < 0
            suppressed += 1
            continue
        end
        transit <= total || throw(ArgumentError(
            "ACS public-transit workers exceed all commuters"))
        geoid = join((
            row[indices["state"]], row[indices["county"]],
            row[indices["tract"]], row[indices["block group"]],
        ))
        estimates[geoid] = (; total, transit)
    end
    isempty(estimates) && throw(ArgumentError("ACS response has no usable estimates"))
    return (; estimates, suppressed, response_sha256=sha256_file(path))
end

function fetch_acs_commute_modes(output::AbstractString;
                                 manifest_path::AbstractString=SOURCE_MANIFEST)
    key = strip(get(ENV, "CENSUS_API_KEY", ""))
    isempty(key) && throw(ArgumentError(
        "set CENSUS_API_KEY or provide a cached ACS response with --acs"))
    specification = TOML.parsefile(manifest_path)["acs_2017"]
    endpoint = String(specification["endpoint_without_key"])
    mkpath(dirname(output))
    temporary = tempname(dirname(output))
    try
        try
            Downloads.download(endpoint * "&key=" * key, temporary)
        catch
            throw(ArgumentError(
                "the 2017 ACS B08301 request failed; the Census API key is omitted from this error"))
        end
        rows = parse_census_string_rows(read(temporary, String))
        length(rows) > 1 || throw(ArgumentError("Census API returned no observations"))
        mv(temporary, output; force=true)
    finally
        isfile(temporary) && rm(temporary; force=true)
    end
    return output
end

function aggregate_transit_shares(path::AbstractString, acs, node_ids)
    active = Dict(node => index for (index, node) in enumerate(node_ids))
    records = NamedTuple[]
    geoid_area = Dict{String,Float64}()
    for row in CSV.File(path; normalizenames=false)
        geoid = string(getproperty(row, :GEOID))
        grid = Int(getproperty(row, :OBJECTID_1))
        area = Float64(getproperty(row, :AREA))
        isfinite(area) && area > 0 ||
            throw(ArgumentError("crosswalk areas must be finite and positive"))
        push!(records, (; geoid, grid, area))
        geoid_area[geoid] = get(geoid_area, geoid, 0.0) + area
    end
    total = zeros(length(node_ids))
    transit = zeros(length(node_ids))
    active_area = 0.0
    matched_area = 0.0
    used_geoids = Set{String}()
    for record in records
        haskey(active, record.grid) || continue
        active_area += record.area
        estimate = get(acs.estimates, record.geoid, nothing)
        estimate === nothing && continue
        matched_area += record.area
        push!(used_geoids, record.geoid)
        weight = record.area / geoid_area[record.geoid]
        index = active[record.grid]
        total[index] += weight * estimate.total
        transit[index] += weight * estimate.transit
    end
    zero_nodes = node_ids[findall(<=(0), total)]
    isempty(zero_nodes) || throw(ArgumentError(
        "ACS/crosswalk aggregation leaves nodes without commuters: " *
        join(zero_nodes, ", ")))
    shares = transit ./ total
    all((0 .<= shares) .& (shares .<= 1)) ||
        throw(ArgumentError("aggregated transit shares must lie in [0,1]"))
    return (; shares, total, transit, used_geoids=length(used_geoids),
            area_coverage=matched_area/active_area,
            minimum_share=minimum(shares), maximum_share=maximum(shares),
            aggregate_share=sum(transit)/sum(total))
end

function verify_gtfs_sources(root::AbstractString;
                             manifest_path::AbstractString=SOURCE_MANIFEST,
                             verify::Bool=true)
    specification = TOML.parsefile(manifest_path)["king_county_gtfs_2017"]
    expected = Dict{String,String}(specification["files"])
    paths = Dict{String,String}()
    hashes = Dict{String,String}()
    for name in sort!(collect(keys(expected)))
        path = joinpath(root, name)
        isfile(path) || throw(ArgumentError(
            "pinned 2017 GTFS file is missing: $path"))
        paths[name] = path
        hashes[name] = sha1_file(path)
        verify && hashes[name] != expected[name] && throw(ArgumentError(
            "2017 GTFS $name hash mismatch: expected $(expected[name]), " *
            "observed $(hashes[name])"))
    end
    return (; paths, hashes, specification)
end

parse_gtfs_date(value) = Date(string(value), dateformat"yyyymmdd")

function parse_gtfs_time(value)
    pieces = split(string(value), ':')
    length(pieces) == 3 ||
        throw(ArgumentError("invalid GTFS time: $value"))
    hours, minutes, seconds = parse.(Int, pieces)
    0 <= minutes < 60 && 0 <= seconds < 60 && hours >= 0 ||
        throw(ArgumentError("invalid GTFS time: $value"))
    return 3600hours + 60minutes + seconds
end

function active_services(paths, service_date::Date)
    weekday = Symbol(lowercase(dayname(service_date)))
    services = Set{String}()
    for row in CSV.File(paths["calendar.txt"]; normalizenames=false)
        start_date = parse_gtfs_date(getproperty(row, :start_date))
        end_date = parse_gtfs_date(getproperty(row, :end_date))
        active = Int(getproperty(row, weekday)) == 1 &&
                 start_date <= service_date <= end_date
        active && push!(services, string(getproperty(row, :service_id)))
    end
    for row in CSV.File(paths["calendar_dates.txt"]; normalizenames=false)
        parse_gtfs_date(getproperty(row, :date)) == service_date || continue
        service = string(getproperty(row, :service_id))
        exception = Int(getproperty(row, :exception_type))
        exception == 1 ? push!(services, service) :
        exception == 2 ? delete!(services, service) :
        throw(ArgumentError("invalid GTFS calendar exception type $exception"))
    end
    isempty(services) &&
        throw(ArgumentError("GTFS has no active service on $service_date"))
    return services
end

function transit_mode(route_type)
    value = Int(route_type)
    value in (0, 1, 2) && return :rail
    value == 3 && return :bus
    value == 4 && return :ferry
    return :transit_other
end

function haversine_km(lon1, lat1, lon2, lat2)
    radius = 6_371.0088
    phi1, phi2 = deg2rad(lat1), deg2rad(lat2)
    dphi = phi2 - phi1
    dlambda = deg2rad(lon2-lon1)
    a = sin(dphi/2)^2 + cos(phi1)*cos(phi2)*sin(dlambda/2)^2
    return 2radius*asin(min(1.0, sqrt(a)))
end

function nearest_node(lon, lat, nodes; max_snap_km)
    distances = [haversine_km(lon, lat, nodes.longitude[index],
                              nodes.latitude[index])
                 for index in eachindex(nodes.ids)]
    index = argmin(distances)
    return distances[index] <= max_snap_km ? nodes.ids[index] : nothing
end

mutable struct ConnectionStats
    total_seconds::Float64
    count::Int
    routes::Set{String}
end

function read_gtfs_network(root::AbstractString, nodes;
                           service_date::Date=DEFAULT_SERVICE_DATE,
                           max_snap_km::Real=2.0,
                           wait_weight::Real=1.0,
                           manifest_path::AbstractString=SOURCE_MANIFEST,
                           verify::Bool=true)
    isfinite(max_snap_km) && max_snap_km > 0 ||
        throw(ArgumentError("max_snap_km must be finite and positive"))
    isfinite(wait_weight) && wait_weight >= 0 ||
        throw(ArgumentError("wait_weight must be finite and nonnegative"))
    sources = verify_gtfs_sources(root; manifest_path, verify)
    source_counts = Dict(
        "agencies" => countlines(sources.paths["agency.txt"])-1,
        "routes" => countlines(sources.paths["routes.txt"])-1,
        "stops" => countlines(sources.paths["stops.txt"])-1,
        "trips" => countlines(sources.paths["trips.txt"])-1,
        "shapes" => countlines(sources.paths["shapes.txt"])-1,
        "stop_times" => countlines(sources.paths["stop_times.txt"])-1,
    )
    if verify
        for (name, field) in (
            "agencies" => "expected_agencies",
            "routes" => "expected_routes",
            "stops" => "expected_stops",
            "trips" => "expected_trips",
            "shapes" => "expected_shapes",
            "stop_times" => "expected_stop_times",
        )
            source_counts[name] == Int(sources.specification[field]) ||
                throw(ArgumentError(
                    "2017 GTFS $name count mismatch: expected " *
                    "$(sources.specification[field]), observed $(source_counts[name])"))
        end
    end
    services = active_services(sources.paths, service_date)

    route_modes = Dict{String,Symbol}()
    route_names = Dict{String,String}()
    route_agencies = Dict{String,String}()
    for row in CSV.File(sources.paths["routes.txt"]; normalizenames=false)
        route = string(getproperty(row, :route_id))
        route_modes[route] = transit_mode(getproperty(row, :route_type))
        short_name = getproperty(row, :route_short_name)
        route_names[route] = short_name === missing ||
                             isempty(strip(string(short_name))) ?
                             route : string(short_name)
        agency = :agency_id in propertynames(row) ?
                 getproperty(row, :agency_id) : missing
        route_agencies[route] =
            agency === missing ? "" : string(agency)
    end
    trips = Dict{String,NamedTuple}()
    for row in CSV.File(sources.paths["trips.txt"]; normalizenames=false)
        string(getproperty(row, :service_id)) in services || continue
        route = string(getproperty(row, :route_id))
        trips[string(getproperty(row, :trip_id))] =
            (; route, mode=route_modes[route])
    end
    isempty(trips) &&
        throw(ArgumentError("GTFS has no active trips on $service_date"))

    stop_nodes = Dict{String,Union{Nothing,Int}}()
    mapped_stops = 0
    for row in CSV.File(sources.paths["stops.txt"]; normalizenames=false)
        location = :location_type in propertynames(row) &&
                   getproperty(row, :location_type) !== missing &&
                   !isempty(strip(string(getproperty(row, :location_type)))) ?
                   Int(getproperty(row, :location_type)) : 0
        location == 0 || continue
        stop = string(getproperty(row, :stop_id))
        mapped = nearest_node(
            Float64(getproperty(row, :stop_lon)),
            Float64(getproperty(row, :stop_lat)),
            nodes; max_snap_km)
        stop_nodes[stop] = mapped
        mapped !== nothing && (mapped_stops += 1)
    end

    connections = Dict{Tuple{Int,Int,Symbol},ConnectionStats}()
    route_connections = Dict{Tuple{String,Int,Int,Symbol},Int}()
    previous = Dict{String,NamedTuple}()
    minimum_time = typemax(Int)
    maximum_time = typemin(Int)
    active_stop_times = 0
    for row in CSV.Rows(sources.paths["stop_times.txt"]; reusebuffer=true,
                        normalizenames=false)
        trip = string(getproperty(row, :trip_id))
        info = get(trips, trip, nothing)
        info === nothing && continue
        sequence = parse(Int, string(getproperty(row, :stop_sequence)))
        arrival = parse_gtfs_time(getproperty(row, :arrival_time))
        departure = parse_gtfs_time(getproperty(row, :departure_time))
        stop = string(getproperty(row, :stop_id))
        node = get(stop_nodes, stop, nothing)
        minimum_time = min(minimum_time, arrival)
        maximum_time = max(maximum_time, departure)
        active_stop_times += 1
        prior = get(previous, trip, nothing)
        prior !== nothing && sequence <= prior.sequence &&
            throw(ArgumentError("GTFS stop_sequence is not increasing for trip $trip"))
        if node !== nothing && prior !== nothing && prior.node !== nothing &&
           node != prior.node
            elapsed = max(1, arrival-prior.departure)
            key = (prior.node, node, info.mode)
            stats = get!(connections, key,
                ConnectionStats(0.0, 0, Set{String}()))
            stats.total_seconds += elapsed
            stats.count += 1
            push!(stats.routes, route_names[info.route])
            route_key = (info.route, prior.node, node, info.mode)
            route_connections[route_key] =
                get(route_connections, route_key, 0)+1
        end
        previous[trip] = (; node, departure, sequence)
    end
    isempty(connections) &&
        throw(ArgumentError("GTFS produces no mapped grid-to-grid connections"))
    service_window = max(1, maximum_time-minimum_time)
    arcs = NamedTuple[]
    for (key, stats) in connections
        i, j, mode = key
        mean_seconds = stats.total_seconds/stats.count
        expected_wait = 0.5service_window/stats.count
        push!(arcs, (; origin=i, destination=j, mode,
                    cost=mean_seconds+wait_weight*expected_wait,
                    service_count=stats.count, route_count=length(stats.routes)))
    end
    sort!(arcs; by=a -> (a.origin, a.destination, String(a.mode)))
    route_edges = NamedTuple[]
    for ((route, origin, destination, mode), service_count) in route_connections
        push!(route_edges, (;
            bundle_id="route:$route",
            route_id=route,
            route_name=route_names[route],
            agency_id=route_agencies[route],
            mode,
            origin,
            destination,
            service_count,
        ))
    end
    sort!(route_edges; by=row ->
        (String(row.mode), row.route_name, row.route_id, row.origin, row.destination))
    source_provenance = Dict(
        "archive_provider" =>
            get(sources.specification, "mobility_database_feed_id", nothing) === nothing ?
            "transitland_feed_version" :
            "mobility_database_historical_archive",
        "mobility_database_feed_id" =>
            get(sources.specification, "mobility_database_feed_id", missing),
        "mobility_database_dataset_id" =>
            get(sources.specification, "mobility_database_dataset_id", missing),
        "mobility_database_feed_page" =>
            get(sources.specification, "mobility_database_feed_page", missing),
        "transitland_archive_page" =>
            get(sources.specification, "archive_page", missing),
    )
    return (; arcs, source_hashes=sources.hashes,
            feed_version=String(sources.specification["feed_version_sha1"]),
            archive_sha256=get(
                sources.specification, "archive_sha256", missing),
            source_provenance,
            source_counts,
            service_date=string(service_date), active_services=length(services),
            active_trips=length(trips), active_stop_times, mapped_stops,
            total_stops=length(stop_nodes), mapped_connections=length(arcs),
            route_edges,
            service_window_seconds=service_window,
            max_snap_km=Float64(max_snap_km), wait_weight=Float64(wait_weight))
end

function adjacency(N::Int, arcs)
    graph = [NamedTuple[] for _ in 1:N]
    for arc in arcs
        1 <= arc.origin <= N && 1 <= arc.destination <= N ||
            throw(ArgumentError("route arc endpoint is outside 1:$N"))
        isfinite(arc.cost) && arc.cost > 0 ||
            throw(ArgumentError("route costs must be finite and positive"))
        push!(graph[arc.origin], arc)
    end
    foreach(values -> sort!(values; by=a ->
        (a.destination, a.cost, String(a.mode))), graph)
    return graph
end

function shortest_path_tree(graph, origin::Int)
    N = length(graph)
    distances = fill(Inf, N)
    predecessor = Vector{Union{Nothing,NamedTuple}}(nothing, N)
    visited = falses(N)
    distances[origin] = 0.0
    for _ in 1:N
        current = 0
        best = Inf
        for node in 1:N
            if !visited[node] && distances[node] < best
                current = node
                best = distances[node]
            end
        end
        current == 0 && break
        visited[current] = true
        for arc in graph[current]
            candidate = distances[current] + arc.cost
            old = predecessor[arc.destination]
            tie_key = (current, String(arc.mode))
            old_key = old === nothing ? (typemax(Int), "") :
                      (old.origin, String(old.mode))
            if candidate < distances[arc.destination]-1e-12 ||
               (abs(candidate-distances[arc.destination]) <= 1e-12 &&
                tie_key < old_key)
                distances[arc.destination] = candidate
                predecessor[arc.destination] =
                    (; origin=current, mode=arc.mode)
            end
        end
    end
    return (; distances, predecessor)
end

function add_path_flow!(flows, tree, origin::Int, destination::Int, mass::Float64)
    mass == 0 && return
    node = destination
    steps = 0
    while node != origin
        prior = tree.predecessor[node]
        prior === nothing && throw(ArgumentError(
            "no route from $origin to $destination"))
        key = (prior.origin, node, prior.mode)
        flows[key] = get(flows, key, 0.0) + mass
        node = prior.origin
        steps += 1
        steps <= length(tree.predecessor) ||
            throw(ArgumentError("predecessor path contains a cycle"))
    end
end

function route_commuters(commute::AbstractMatrix, transit_shares,
                         road_arcs, transit_arcs;
                         road_interiority_share::Real=1e-8)
    N = size(commute, 1)
    size(commute) == (N, N) ||
        throw(ArgumentError("commute matrix must be square"))
    length(transit_shares) == N ||
        throw(ArgumentError("one transit share is required per origin"))
    all((0 .<= transit_shares) .& (transit_shares .<= 1)) ||
        throw(ArgumentError("transit shares must lie in [0,1]"))
    isfinite(road_interiority_share) && road_interiority_share >= 0 ||
        throw(ArgumentError("road_interiority_share must be finite and nonnegative"))
    road_graph = adjacency(N, road_arcs)
    transit_graph = adjacency(N, transit_arcs)
    flows = Dict{Tuple{Int,Int,Symbol},Float64}()
    requested_transit = 0.0
    routed_transit = 0.0
    fallback_to_road = 0.0
    requested_by_origin = zeros(N)
    routed_by_origin = zeros(N)
    fallback_by_origin = zeros(N)
    local_commuters = sum(commute[i, i] for i in 1:N)
    for origin in 1:N
        road_tree = shortest_path_tree(road_graph, origin)
        transit_tree = shortest_path_tree(transit_graph, origin)
        for destination in 1:N
            origin == destination && continue
            mass = Float64(commute[origin, destination])
            mass == 0 && continue
            transit_mass = mass*transit_shares[origin]
            requested_transit += transit_mass
            requested_by_origin[origin] += transit_mass
            if transit_mass > 0 && isfinite(transit_tree.distances[destination])
                add_path_flow!(
                    flows, transit_tree, origin, destination, transit_mass)
                routed_transit += transit_mass
                routed_by_origin[origin] += transit_mass
            else
                fallback_to_road += transit_mass
                fallback_by_origin[origin] += transit_mass
                transit_mass = 0.0
            end
            road_mass = mass-transit_mass
            isfinite(road_tree.distances[destination]) || throw(ArgumentError(
                "road network cannot route commuters from $origin to $destination"))
            add_path_flow!(flows, road_tree, origin, destination, road_mass)
        end
    end

    road_pairs = Set((arc.origin, arc.destination) for arc in road_arcs)
    for (i, j) in road_pairs
        (j, i) in road_pairs || throw(ArgumentError(
            "the road interiority circulation requires reciprocal arcs"))
    end
    commuter_total = sum(commute)
    floor_per_arc = isempty(road_arcs) ? 0.0 :
                    commuter_total*road_interiority_share/length(road_arcs)
    for arc in road_arcs
        key = (arc.origin, arc.destination, :road)
        flows[key] = get(flows, key, 0.0) + floor_per_arc
    end

    residents = vec(sum(commute; dims=2))
    employment = vec(sum(commute; dims=1))
    divergence = zeros(N)
    for ((i, j, _), flow) in flows
        divergence[i] += flow
        divergence[j] -= flow
    end
    balance_error = maximum(abs.(divergence .- (residents-employment)))
    transit_assignment_error = maximum(abs.(
        requested_by_origin .- routed_by_origin .- fallback_by_origin))
    return (; flows, residents, employment, balance_error,
            requested_transit, routed_transit, fallback_to_road,
            requested_by_origin, routed_by_origin, fallback_by_origin,
            transit_assignment_error,
            local_commuters, road_interiority_share=Float64(road_interiority_share),
            road_floor_per_arc=floor_per_arc)
end

function historical_aadt_stock_disagreement(nodes_path, adjacency_path)
    nodes = collect(CSV.File(nodes_path; header=false))
    residents = Float64[row.Column2 for row in nodes]
    employment = Float64[row.Column3 for row in nodes]
    residents ./= sum(residents)
    employment ./= sum(employment)
    total = (sum(Float64(row.Column2) for row in nodes) +
             sum(Float64(row.Column3) for row in nodes))/2
    outgoing = zeros(length(nodes))
    incoming = zeros(length(nodes))
    for row in CSV.File(adjacency_path; header=false)
        i, j, flow = Int(row.Column1), Int(row.Column2), Float64(row.Column3)/total
        outgoing[i] += flow
        incoming[j] += flow
    end
    return maximum(abs.((employment+outgoing) .- (residents+incoming)))
end

function write_nodes(path, nodes, routed)
    open(path, "w") do io
        println(io, "node_id,residents,employment,longitude,latitude")
        for index in eachindex(nodes.ids)
            @printf(io, "%d,%.17g,%.17g,%.17g,%.17g\n",
                nodes.ids[index], routed.residents[index],
                routed.employment[index], nodes.longitude[index],
                nodes.latitude[index])
        end
    end
end

function write_edge_modes(path, routed, road_arcs, transit_arcs)
    costs = Dict(
        (arc.origin, arc.destination, arc.mode) => arc.cost
        for arc in vcat(road_arcs, transit_arcs)
    )
    services = Dict(
        (arc.origin, arc.destination, arc.mode) =>
            (arc.service_count, arc.route_count)
        for arc in vcat(road_arcs, transit_arcs)
    )
    open(path, "w") do io
        println(io, join((
            "edge_id", "physical_link_id", "origin", "destination", "mode",
            "flow", "origin_terminal_id", "destination_terminal_id",
            "assignment_cost_seconds", "daily_service_count", "route_count",
        ), ','))
        for key in sort!(collect(keys(routed.flows));
                         by=value -> (value[1], value[2], String(value[3])))
            i, j, mode = key
            flow = routed.flows[key]
            flow > 0 || continue
            edge_id = "$(i)_$(j)"
            physical = "$(min(i,j))_$(max(i,j))"
            origin_terminal = mode == :road ? "" : "grid_$i"
            destination_terminal = mode == :road ? "" : "grid_$j"
            service_count, route_count = get(services, key, (0, 0))
            cost = costs[key]
            @printf(io, "%s,%s,%d,%d,%s,%.17g,%s,%s,%.17g,%d,%d\n",
                edge_id, physical, i, j, String(mode), flow,
                origin_terminal, destination_terminal, cost,
                service_count, route_count)
        end
    end
end

function write_route_bundles(path, route_edges, routed)
    active = Set(key for (key, flow) in routed.flows if flow > 0)
    source_by_bundle = Dict{String,Vector{NamedTuple}}()
    for row in route_edges
        push!(get!(source_by_bundle, row.bundle_id, NamedTuple[]), row)
    end
    complete_bundles = Set(
        bundle for (bundle, rows) in source_by_bundle
        if all((row.origin, row.destination, row.mode) in active for row in rows))
    retained = [row for row in route_edges if row.bundle_id in complete_bundles]
    isempty(retained) &&
        throw(ArgumentError(
            "no complete GTFS route corridor lies on the active transit-flow support"))
    open(path, "w") do io
        println(io, join((
            "bundle_id", "edge_id", "mode", "weight", "route_id",
            "route_name", "agency_id", "origin", "destination", "service_count",
        ), ','))
        for row in retained
            values = (
                row.bundle_id,
                "$(row.origin)_$(row.destination)",
                String(row.mode),
                1.0,
                row.route_id,
                row.route_name,
                row.agency_id,
                row.origin,
                row.destination,
                row.service_count,
            )
            println(io, join(TransportNetworkWelfare.csv_escape.(values), ','))
        end
    end
    bundles = unique(row.bundle_id for row in retained)
    return (; rows=length(retained), bundles=length(bundles),
            source_rows=length(route_edges),
            source_bundles=length(source_by_bundle),
            excluded_incomplete_bundles=
                length(source_by_bundle)-length(complete_bundles),
            complete_bundle_share=
                length(complete_bundles)/length(source_by_bundle))
end

function write_fallback_by_origin(path, routed)
    open(path, "w") do io
        println(io, "origin,requested_transit,routed_transit,fallback_to_road,fallback_share")
        for origin in eachindex(routed.requested_by_origin)
            requested = routed.requested_by_origin[origin]
            fallback = routed.fallback_by_origin[origin]
            share = requested > 0 ? fallback/requested : 0.0
            @printf(io, "%d,%.17g,%.17g,%.17g,%.17g\n",
                origin, requested, routed.routed_by_origin[origin], fallback, share)
        end
    end
    return path
end

function write_config(path, modes; eta::Real,
                      terminal_lambda::Union{Nothing,Real}=nothing,
                      policy_mode::Symbol=:road,
                      policy_unit::Symbol=:both,
                      output_directory::AbstractString="output")
    isfinite(eta) && eta > 0 ||
        throw(ArgumentError("eta must be finite and positive"))
    if terminal_lambda !== nothing
        isfinite(terminal_lambda) && terminal_lambda >= 0 ||
            throw(ArgumentError("terminal_lambda must be finite and nonnegative"))
    end
    transit_modes = [mode for mode in modes if mode != :road]
    policy_mode in modes ||
        throw(ArgumentError("policy mode $policy_mode is absent from generated modes"))
    policy_unit in (:directed_arc, :physical_link, :both) ||
        throw(ArgumentError("invalid policy unit $policy_unit"))
    open(path, "w") do io
        println(io, "schema_version = 1")
        println(io, "name = \"seattle-2017-multimodal-urban-candidate\"")
        println(io)
        println(io, "[input]")
        println(io, "adapter = \"generic_csv_v1\"")
        println(io, "nodes = \"data/nodes.csv\"")
        println(io, "edge_modes = \"data/edge_modes.csv\"")
        println(io, "mode_order = [",
                join(("\"$(String(mode))\"" for mode in modes), ", "), "]")
        println(io)
        println(io, "[input.transformations]")
        println(io, "normalize_residents = true")
        println(io, "normalize_employment = true")
        println(io, "flow_conversion = \"divide_by_total_commuters\"")
        println(io, "symmetrize = false")
        println(io, "pad_nodes = 0")
        println(io, "modal_rescale = false")
        println(io)
        println(io, "[model]")
        println(io, "spatial_specification = \"urban_commuting\"")
        println(io, "alpha = -0.12")
        println(io, "beta = -0.10")
        println(io, "theta = 6.83")
        println(io, "modal_specification = \"choice_logsum\"")
        @printf(io, "eta = %.17g\n", eta)
        println(io, "route_curvature = \"theorem\"")
        println(io)
        println(io, "[congestion]")
        println(io, "specification = \"",
                terminal_lambda === nothing ? "edge" : "composite", "\"")
        terminal_lambda !== nothing && println(io, "endpoint_scale = 1.0")
        println(io)
        println(io, "[congestion.edge]")
        @printf(io, "road = %.17g\n", ROAD_CONGESTION)
        if terminal_lambda !== nothing
            println(io)
            println(io, "[congestion.terminal]")
            for mode in transit_modes
                @printf(io, "%s = %.17g\n", String(mode), terminal_lambda)
            end
        end
        println(io)
        println(io, "[policy]")
        println(io, "mode = \"$(String(policy_mode))\"")
        println(io, "unit = \"$(String(policy_unit))\"")
        println(io, "shock_fraction = 0.01")
        println(io)
        println(io, "[output]")
        println(io, "directory = \"$output_directory\"")
        println(io)
        println(io, "[sensitivity]")
        println(io, "eta = [0.75, 0.90, 1.099, 1.25, 1.40]")
        println(io)
        println(io, "[diagnostics]")
        println(io, "tolerance = 1.0e-10")
        println(io, "condition_limit = 1.0e12")
    end
    return path
end

function build_example(aa_root::AbstractString, gtfs_root::AbstractString,
                       acs_path::AbstractString, output::AbstractString;
                       eta::Real, service_date::Date=DEFAULT_SERVICE_DATE,
                       max_snap_km::Real=2.0, wait_weight::Real=1.0,
                       road_interiority_share::Real=1e-8,
                       terminal_lambda::Union{Nothing,Real}=nothing,
                       manifest_path::AbstractString=SOURCE_MANIFEST,
                       verify_gtfs::Bool=true)
    sources = verified_aa_sources(aa_root; manifest_path)
    nodes = read_aa_nodes(sources.paths["nodes"])
    commute = read_commute_matrix(sources.paths["commute"], length(nodes.ids))
    road_arcs = read_road_arcs(sources.paths["adjacency"])
    acs = read_acs_commute_modes(acs_path)
    shares = aggregate_transit_shares(
        sources.paths["crosswalk"], acs, nodes.ids)
    gtfs = read_gtfs_network(
        gtfs_root, nodes; service_date, max_snap_km, wait_weight,
        manifest_path, verify=verify_gtfs)
    routed = route_commuters(
        commute, shares.shares, road_arcs, gtfs.arcs; road_interiority_share)
    routed.balance_error <= 1e-10*max(sum(commute), 1.0) || throw(ArgumentError(
        "routed commuter flows fail flow conservation by $(routed.balance_error)"))
    routed.transit_assignment_error <= 1e-10*max(routed.requested_transit, 1.0) ||
        throw(ArgumentError(
            "transit assignment accounting error is $(routed.transit_assignment_error)"))
    fallback_share = routed.requested_transit > 0 ?
                     routed.fallback_to_road/routed.requested_transit : 0.0
    fallback_share <= 0.05 || throw(ArgumentError(
        "transit fallback share $(100*fallback_share)% exceeds the five-percent gate"))

    data = joinpath(output, "data")
    mkpath(data)
    nodes_path = joinpath(data, "nodes.csv")
    edges_path = joinpath(data, "edge_modes.csv")
    bundles_path = joinpath(data, "route_bundles.csv")
    fallback_path = joinpath(data, "transit_fallback_by_origin.csv")
    config_path = joinpath(output, "config.toml")
    write_nodes(nodes_path, nodes, routed)
    write_edge_modes(edges_path, routed, road_arcs, gtfs.arcs)
    bundle_summary = write_route_bundles(bundles_path, gtfs.route_edges, routed)
    write_fallback_by_origin(fallback_path, routed)
    modes = sort!(unique(key[3] for key in keys(routed.flows));
                  by=mode -> (mode == :road ? "" : String(mode)))
    first(modes) == :road ||
        throw(ArgumentError("generated mode order must start with road"))
    required_modes = Set((:road, :bus, :rail, :ferry))
    required_modes ⊆ Set(modes) || throw(ArgumentError(
        "the exact Seattle exercise requires road, bus, rail, and ferry; " *
        "observed $(join(String.(modes), ", "))"))
    write_config(config_path, modes; eta, terminal_lambda)
    config_paths = Dict(:road => config_path)
    for mode in (:bus, :rail, :ferry)
        path = joinpath(output, "config_$(String(mode)).toml")
        write_config(path, modes; eta, terminal_lambda, policy_mode=mode,
                     policy_unit=:directed_arc,
                     output_directory="output_$(String(mode))")
        config_paths[mode] = path
    end

    validations = Dict{String,Any}()
    for (mode, path) in config_paths
        report = TransportNetworkWelfare.validate(
            TransportNetworkWelfare.load_project(path))
        report.valid || throw(ArgumentError(
            "generated Seattle project is invalid for policy mode $mode"))
        maximum((
            report.stock_disagreement,
            report.route_absorption_error,
            report.route_bilateral_row_error,
            report.route_bilateral_column_error,
            report.route_edge_error,
        )) <= 1e-10 || throw(ArgumentError(
            "generated Seattle project exceeds the 1e-10 accounting gate " *
            "for policy mode $mode"))
        validations[String(mode)] = report
    end
    validation = validations["road"]
    generated_hashes = Dict(
        "nodes.csv" => sha256_file(nodes_path),
        "edge_modes.csv" => sha256_file(edges_path),
        "route_bundles.csv" => sha256_file(bundles_path),
        "transit_fallback_by_origin.csv" => sha256_file(fallback_path),
    )
    for (mode, path) in config_paths
        generated_hashes[basename(path)] = sha256_file(path)
    end
    manifest = Dict{String,Any}(
        "specification_status" => "candidate",
        "verification_status" => "data_and_accounting_contract_passed",
        "release_status" => "external_sources_not_redistributed",
        "source_hashes" => Dict(
            "allen_arkolakis" => sources.hashes,
            "acs_response_sha256" => acs.response_sha256,
            "gtfs_files_sha1" => gtfs.source_hashes,
            "gtfs_feed_version_sha1" => gtfs.feed_version,
            "gtfs_archive_sha256" => gtfs.archive_sha256,
        ),
        "generated_hashes" => generated_hashes,
        "nodes" => length(nodes.ids),
        "road_arcs_available" => length(road_arcs),
        "road_links_available" => 692,
        "generated_directed_edges" => validation.directed_edges,
        "generated_active_edge_modes" => validation.active_edge_modes,
        "policy_configurations" =>
            Dict(String(mode) => relpath(path, output) for (mode, path) in config_paths),
        "modes" => String.(modes),
        "total_commuters" => sum(commute),
        "local_commuters" => routed.local_commuters,
        "acs" => Dict(
            "aggregate_public_transit_share" => shares.aggregate_share,
            "minimum_grid_share" => shares.minimum_share,
            "maximum_grid_share" => shares.maximum_share,
            "crosswalk_area_coverage" => shares.area_coverage,
            "block_groups_used" => shares.used_geoids,
            "suppressed_block_groups" => acs.suppressed,
        ),
        "gtfs" => Dict(
            "source_provenance" => gtfs.source_provenance,
            "service_date" => gtfs.service_date,
            "active_services" => gtfs.active_services,
            "active_trips" => gtfs.active_trips,
            "source_counts" => gtfs.source_counts,
            "mapped_stops" => gtfs.mapped_stops,
            "total_stops" => gtfs.total_stops,
            "mapped_connections" => gtfs.mapped_connections,
            "route_bundle_rows" => bundle_summary.rows,
            "route_bundles" => bundle_summary.bundles,
            "route_source_rows" => bundle_summary.source_rows,
            "route_source_bundles" => bundle_summary.source_bundles,
            "route_excluded_incomplete_bundles" =>
                bundle_summary.excluded_incomplete_bundles,
            "route_complete_bundle_share" => bundle_summary.complete_bundle_share,
            "max_snap_km" => gtfs.max_snap_km,
            "wait_weight" => gtfs.wait_weight,
        ),
        "routing" => Dict(
            "requested_nonlocal_transit_commuters" => routed.requested_transit,
            "routed_transit_commuters" => routed.routed_transit,
            "transit_fallback_to_road" => routed.fallback_to_road,
            "transit_fallback_share" => fallback_share,
            "transit_assignment_error" => routed.transit_assignment_error,
            "flow_balance_error" => routed.balance_error,
            "road_interiority_share" => routed.road_interiority_share,
            "road_floor_per_arc" => routed.road_floor_per_arc,
        ),
        "historical_aadt_stock_disagreement" =>
            historical_aadt_stock_disagreement(
                sources.paths["nodes"], sources.paths["adjacency"]),
        "calibration" => Dict(
            "alpha" => -0.12, "beta" => -0.10, "theta" => 6.83,
            "eta" => Float64(eta),
            "eta_status" =>
                eta == 1.099 ? "transferred_economic_geography_baseline" :
                "user_supplied_candidate",
            "road_congestion" => ROAD_CONGESTION,
            "terminal_congestion" =>
                terminal_lambda === nothing ? missing : Float64(terminal_lambda),
        ),
        "transformations" => [
            "residence and workplace masses are row and column sums of the 2017 LODES OD matrix",
            "origin public-transit shares are 2017 ACS B08301 estimates area-allocated to the Allen-Arkolakis grid",
            "public-transit paths use the pinned 2017 GTFS weekday network",
            "unreachable public-transit OD mass is reassigned to road and reported",
            "road paths use Allen-Arkolakis observed road travel times",
            "a declared reciprocal road circulation gives every published road arc positive baseline flow",
            "HPMS AADT is retained only as a historical validation comparison",
        ],
        "limitations" => [
            "ACS identifies origin mode shares, not route-level ridership",
            "GTFS schedules identify service and paths, not passenger counts",
            "grid-level transit routing abstracts from walking and explicit transfer nodes",
            "buses do not yet contribute to the road-mode congestion stock",
            "eta is not estimated from Seattle data",
        ],
    )
    manifest_path_out = joinpath(output, "build_manifest.json")
    open(manifest_path_out, "w") do io
        println(io, TransportNetworkWelfare.json_value(manifest))
    end
    return manifest
end

function option(args, name; default=nothing)
    index = findfirst(==(name), args)
    index === nothing && return default
    index < length(args) ||
        throw(ArgumentError("$name requires a value"))
    return args[index+1]
end

function main(args=ARGS)
    data_root = option(args, "--data-root";
        default=get(ENV, "SEATTLE_TRANSIT_DATA_ROOT", ""))
    default_aa = isempty(data_root) ? "" :
        joinpath(data_root, "raw", "allen_arkolakis", "extracted",
                 "ReplicationFinal")
    default_gtfs = isempty(data_root) ? "" :
        joinpath(data_root, "raw", "king_county_gtfs_2017", "extracted")
    default_acs = isempty(data_root) ?
        joinpath(EXAMPLE_ROOT, "raw", "acs_2017_king_county_b08301.json") :
        joinpath(data_root, "raw", "acs", "acs_2017_king_county_b08301.json")
    aa_root = option(args, "--aa-root";
        default=get(ENV, "AA_REPLICATION_ROOT", default_aa))
    gtfs_root = option(args, "--gtfs-root";
        default=get(ENV, "SEATTLE_GTFS_2017_ROOT", default_gtfs))
    isempty(aa_root) && throw(ArgumentError(
        "set AA_REPLICATION_ROOT or pass --aa-root"))
    isempty(gtfs_root) && throw(ArgumentError(
        "set SEATTLE_GTFS_2017_ROOT or pass --gtfs-root"))
    eta_text = option(args, "--eta")
    eta_text === nothing && throw(ArgumentError(
        "--eta is required because Seattle does not supply an estimated modal elasticity"))
    eta = parse(Float64, eta_text)
    output = abspath(option(args, "--output";
        default=joinpath(EXAMPLE_ROOT, "generated")))
    acs_path = abspath(option(args, "--acs";
        default=default_acs))
    if !isfile(acs_path)
        "--offline" in args && throw(ArgumentError(
            "cached ACS response is missing in offline mode: $acs_path"))
        fetch_acs_commute_modes(acs_path)
    end
    service_date = Date(option(args, "--service-date";
        default=string(DEFAULT_SERVICE_DATE)))
    max_snap_km = parse(Float64, option(args, "--max-snap-km"; default="2.0"))
    wait_weight = parse(Float64, option(args, "--wait-weight"; default="1.0"))
    road_floor = parse(Float64, option(
        args, "--road-interiority-share"; default="1e-8"))
    terminal_text = option(args, "--terminal-lambda")
    terminal_lambda = terminal_text === nothing ? nothing :
                      parse(Float64, terminal_text)
    result = build_example(
        aa_root, gtfs_root, acs_path, output; eta, service_date,
        max_snap_km, wait_weight, road_interiority_share=road_floor,
        terminal_lambda)
    println(TransportNetworkWelfare.json_value(result))
    return 0
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(SeattleMultimodalBuilder.main())
    catch error
        showerror(stderr, error)
        println(stderr)
        exit(1)
    end
end
