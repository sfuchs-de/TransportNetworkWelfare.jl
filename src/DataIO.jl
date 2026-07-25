struct EdgeModeRow
    edge_id::String
    physical_link_id::String
    origin::String
    destination::String
    mode::Symbol
    flow::Float64
    origin_terminal_id::Union{Nothing,String}
    destination_terminal_id::Union{Nothing,String}
    congestion_elasticity::Union{Nothing,Float64}
end

struct NetworkData
    N::Int
    node_ids::Vector{String}
    node_index::Dict{String,Int}
    longitude::Vector{Union{Missing,Float64}}
    latitude::Vector{Union{Missing,Float64}}
    modes::Vector{Symbol}
    omega::Vector{Float64}
    nu::Vector{Float64}
    mode_flows::Vector{SparseMatrixCSC{Float64,Int}}
    Xi::SparseMatrixCSC{Float64,Int}
    out_neighbors::Vector{Vector{Int}}
    in_neighbors::Vector{Vector{Int}}
    Tnode::Vector{Float64}
    sx::Vector{Float64}
    sy::Vector{Float64}
    mu::Matrix{Float64}
    lam::Matrix{Float64}
    edges::Vector{Tuple{Int,Int}}
    edge_ids::Vector{String}
    physical_link_ids::Vector{String}
    edge_index::Dict{Tuple{Int,Int},Int}
    s_edges::Matrix{Float64}
    s_edges_by_pair::Dict{Tuple{Int,Int},Vector{Float64}}
    policy_edges::Vector{Tuple{Int,Int}}
    policy_edge_ids::Vector{String}
    policy_physical_link_ids::Vector{String}
    pair_origin_terminal::Dict{Tuple{Int,Int},String}
    pair_destination_terminal::Dict{Tuple{Int,Int},String}
    pair_edge_congestion::Dict{Tuple{Int,Int},Float64}
    transformations::Vector{String}
    input_hashes::Dict{String,String}
    stock_disagreement::Float64
    residence::Union{Nothing,Vector{Float64}}
    workplace::Union{Nothing,Vector{Float64}}
end

file_sha256(path::AbstractString) = bytes2hex(open(SHA.sha256, path))

function require_columns(path::AbstractString, columns, required)
    available = Set(String.(columns))
    missing = [name for name in required if !(name in available)]
    isempty(missing) ||
        throw(ArgumentError("$path is missing required columns: $(join(missing, ", "))"))
end

cell_string(value) = value === missing ? "" : strip(string(value))

function cell_float(value, path, column, row)
    value === missing && throw(ArgumentError("$path row $row has missing $column"))
    number = try
        Float64(value)
    catch
        try
            parse(Float64, String(value))
        catch
            throw(ArgumentError("$path row $row has invalid $column=$(repr(value))"))
        end
    end
    isfinite(number) || throw(ArgumentError("$path row $row has nonfinite $column"))
    return number
end

function read_nodes(path::AbstractString)
    isfile(path) || throw(ArgumentError("nodes file not found: $path"))
    table = CSV.File(path; normalizenames=false)
    require_columns(path, propertynames(table), ["node_id", "labor", "income"])
    ids = String[]
    labor = Float64[]
    income = Float64[]
    longitude = Union{Missing,Float64}[]
    latitude = Union{Missing,Float64}[]
    has_lon = :longitude in propertynames(table)
    has_lat = :latitude in propertynames(table)
    for (row_number, row) in enumerate(table)
        id = cell_string(getproperty(row, :node_id))
        isempty(id) && throw(ArgumentError("$path row $row_number has an empty node_id"))
        push!(ids, id)
        push!(labor, cell_float(getproperty(row, :labor), path, "labor", row_number))
        push!(income, cell_float(getproperty(row, :income), path, "income", row_number))
        push!(longitude, has_lon && getproperty(row, :longitude) !== missing ?
              cell_float(getproperty(row, :longitude), path, "longitude", row_number) : missing)
        push!(latitude, has_lat && getproperty(row, :latitude) !== missing ?
              cell_float(getproperty(row, :latitude), path, "latitude", row_number) : missing)
    end
    isempty(ids) && throw(ArgumentError("nodes file is empty: $path"))
    length(unique(ids)) == length(ids) || throw(ArgumentError("node_id values must be unique"))
    all(>(0), labor) || throw(ArgumentError("labor must be strictly positive"))
    all(>(0), income) || throw(ArgumentError("income must be strictly positive"))
    return (; ids, labor, income, longitude, latitude)
end

function read_urban_nodes(path::AbstractString)
    isfile(path) || throw(ArgumentError("nodes file not found: $path"))
    table = CSV.File(path; normalizenames=false)
    require_columns(path, propertynames(table), ["node_id", "residents", "employment"])
    ids = String[]
    residents = Float64[]
    employment = Float64[]
    longitude = Union{Missing,Float64}[]
    latitude = Union{Missing,Float64}[]
    has_lon = :longitude in propertynames(table)
    has_lat = :latitude in propertynames(table)
    for (row_number, row) in enumerate(table)
        id = cell_string(getproperty(row, :node_id))
        isempty(id) && throw(ArgumentError("$path row $row_number has an empty node_id"))
        push!(ids, id)
        push!(residents,
              cell_float(getproperty(row, :residents), path, "residents", row_number))
        push!(employment,
              cell_float(getproperty(row, :employment), path, "employment", row_number))
        push!(longitude, has_lon && getproperty(row, :longitude) !== missing ?
              cell_float(getproperty(row, :longitude), path, "longitude", row_number) : missing)
        push!(latitude, has_lat && getproperty(row, :latitude) !== missing ?
              cell_float(getproperty(row, :latitude), path, "latitude", row_number) : missing)
    end
    isempty(ids) && throw(ArgumentError("nodes file is empty: $path"))
    length(unique(ids)) == length(ids) || throw(ArgumentError("node_id values must be unique"))
    all(>(0), residents) || throw(ArgumentError("residents must be strictly positive"))
    all(>(0), employment) || throw(ArgumentError("employment must be strictly positive"))
    return (; ids, residents, employment, longitude, latitude)
end

function optional_terminal(row, name::Symbol)
    name in propertynames(row) || return nothing
    value = cell_string(getproperty(row, name))
    return isempty(value) ? nothing : value
end

function read_edge_modes(path::AbstractString; congestion_column::Union{Nothing,String}=nothing)
    isfile(path) || throw(ArgumentError("edge-modes file not found: $path"))
    table = CSV.File(path; normalizenames=false)
    require_columns(path, propertynames(table), [
        "edge_id", "physical_link_id", "origin", "destination", "mode", "flow",
    ])
    congestion_column !== nothing && congestion_column in (
        "edge_id", "physical_link_id", "origin", "destination", "mode", "flow",
        "origin_terminal_id", "destination_terminal_id",
    ) && throw(ArgumentError(
        "edge-congestion input column must not reuse a reserved edge_modes column"))
    column_symbol = congestion_column === nothing ? nothing : Symbol(congestion_column)
    column_symbol !== nothing && !(column_symbol in propertynames(table)) &&
        throw(ArgumentError("$path is missing configured edge-congestion column: $congestion_column"))
    rows = EdgeModeRow[]
    for (row_number, row) in enumerate(table)
        values = Dict(name => cell_string(getproperty(row, Symbol(name))) for name in
                      ("edge_id", "physical_link_id", "origin", "destination", "mode"))
        for (name, value) in values
            isempty(value) && throw(ArgumentError("$path row $row_number has an empty $name"))
        end
        flow = cell_float(getproperty(row, :flow), path, "flow", row_number)
        flow > 0 || throw(ArgumentError("$path row $row_number has nonpositive flow; active edge-modes must be interior"))
        congestion_elasticity = column_symbol === nothing ? nothing :
            cell_float(getproperty(row, column_symbol), path, congestion_column, row_number)
        congestion_elasticity !== nothing && congestion_elasticity < 0 &&
            throw(ArgumentError("$path row $row_number has negative $congestion_column"))
        push!(rows, EdgeModeRow(
            values["edge_id"], values["physical_link_id"], values["origin"],
            values["destination"], Symbol(values["mode"]), flow,
            optional_terminal(row, :origin_terminal_id),
            optional_terminal(row, :destination_terminal_id),
            congestion_elasticity,
        ))
    end
    isempty(rows) && throw(ArgumentError("edge-modes file is empty: $path"))
    keys = [(row.edge_id, row.mode) for row in rows]
    length(unique(keys)) == length(keys) ||
        throw(ArgumentError("(edge_id, mode) rows must be unique"))
    return rows
end

function declared_transformations(project::Project)
    raw = get(project.input, "transformations", Dict{String,Any}())
    normalize_labor = Bool(get(raw, "normalize_labor", false))
    normalize_income = Bool(get(raw, "normalize_income", false))
    flow_conversion = lowercase(String(get(raw, "flow_conversion", "none")))
    symmetrize = Bool(get(raw, "symmetrize", false))
    pad_nodes = Int(get(raw, "pad_nodes", 0))
    modal_rescale = Bool(get(raw, "modal_rescale", false))
    symmetrize && throw(ArgumentError("generic inputs are never symmetrized internally; supply both directions explicitly"))
    pad_nodes == 0 || throw(ArgumentError("generic inputs do not permit node padding"))
    !modal_rescale || throw(ArgumentError("generic inputs do not permit modal rescaling"))
    flow_conversion in ("none", "divide_by_world_income") ||
        throw(ArgumentError("flow_conversion must be none or divide_by_world_income"))
    return (; normalize_labor, normalize_income, flow_conversion,
            ledger=String[
                "normalize_labor=$normalize_labor",
                "normalize_income=$normalize_income",
                "flow_conversion=$flow_conversion",
                "symmetrize=false",
                "pad_nodes=0",
                "modal_rescale=false",
            ])
end

function declared_urban_transformations(project::Project)
    raw = get(project.input, "transformations", Dict{String,Any}())
    normalize_residents = Bool(get(raw, "normalize_residents", false))
    normalize_employment = Bool(get(raw, "normalize_employment", false))
    flow_conversion = lowercase(String(get(raw, "flow_conversion", "none")))
    symmetrize = Bool(get(raw, "symmetrize", false))
    pad_nodes = Int(get(raw, "pad_nodes", 0))
    modal_rescale = Bool(get(raw, "modal_rescale", false))
    symmetrize && throw(ArgumentError(
        "generic urban inputs are never symmetrized internally; supply both directions explicitly"))
    pad_nodes == 0 || throw(ArgumentError("generic urban inputs do not permit node padding"))
    !modal_rescale || throw(ArgumentError("generic urban inputs do not permit modal rescaling"))
    flow_conversion in ("none", "divide_by_total_commuters") || throw(ArgumentError(
        "urban flow_conversion must be none or divide_by_total_commuters"))
    return (; normalize_residents, normalize_employment, flow_conversion,
            ledger=String[
                "normalize_residents=$normalize_residents",
                "normalize_employment=$normalize_employment",
                "flow_conversion=$flow_conversion",
                "symmetrize=false",
                "pad_nodes=0",
                "modal_rescale=false",
            ])
end

function validate_edge_metadata(rows::Vector{EdgeModeRow}, node_index)
    metadata = Dict{String,Tuple{String,String,String}}()
    directed_pairs = Dict{Tuple{String,String},String}()
    for row in rows
        haskey(node_index, row.origin) || throw(ArgumentError("edge $(row.edge_id) has unknown origin $(row.origin)"))
        haskey(node_index, row.destination) || throw(ArgumentError("edge $(row.edge_id) has unknown destination $(row.destination)"))
        row.origin != row.destination || throw(ArgumentError("self edge $(row.edge_id) is not supported"))
        current = (row.origin, row.destination, row.physical_link_id)
        previous = get(metadata, row.edge_id, current)
        previous == current || throw(ArgumentError("edge_id $(row.edge_id) has inconsistent endpoints or physical_link_id"))
        metadata[row.edge_id] = current
        pair = (row.origin, row.destination)
        prior_id = get(directed_pairs, pair, row.edge_id)
        prior_id == row.edge_id ||
            throw(ArgumentError("parallel edge_ids with the same endpoints are not supported; insert route nodes explicitly"))
        directed_pairs[pair] = row.edge_id
    end
    return metadata
end

function mode_order(project::Project, rows)
    observed = Set(row.mode for row in rows)
    raw = get(project.input, "mode_order", String[])
    raw isa AbstractVector || throw(ArgumentError("mode_order must be an array"))
    all(value -> value isa AbstractString && !isempty(strip(value)), raw) ||
        throw(ArgumentError("mode_order entries must be nonempty strings"))
    modes = isempty(raw) ? sort!(collect(observed); by=String) : Symbol.(raw)
    length(unique(modes)) == length(modes) || throw(ArgumentError("mode_order contains duplicates"))
    Set(modes) == observed ||
        throw(ArgumentError("mode_order must list each observed mode exactly once"))
    return modes
end

function require_terminal_ids(project::Project, rows)
    active_modes = configured_active_modes(project, (row.mode for row in rows))
    active = Set(mode for (mode, lambda) in terminal_lambdas(project.congestion)
                 if lambda > 0 && mode in active_modes)
    for row in rows
        row.mode in active || continue
        row.origin_terminal_id === nothing &&
            throw(ArgumentError("edge $(row.edge_id), mode $(row.mode) is missing origin_terminal_id"))
        row.destination_terminal_id === nothing &&
            throw(ArgumentError("edge $(row.edge_id), mode $(row.mode) is missing destination_terminal_id"))
    end
end

function physical_policy_check(project::Project, rows)
    project.policy.unit == :directed_arc && return
    policy_rows = [row for row in rows if row.mode == project.policy.mode]
    grouped = Dict{String,Vector{EdgeModeRow}}()
    for row in policy_rows
        push!(get!(grouped, row.physical_link_id, EdgeModeRow[]), row)
    end
    isempty(grouped) && throw(ArgumentError("policy mode $(project.policy.mode) has no active edge-modes"))
    for (link, group) in grouped
        length(group) == 2 || throw(ArgumentError("physical link $link must have exactly two policy directions"))
        a, b = group
        (a.origin == b.destination && a.destination == b.origin) ||
            throw(ArgumentError("physical link $link does not pair opposite directions"))
    end
end

function build_network(project::Project, nodes, rows::Vector{EdgeModeRow}; input_hashes)
    transforms = declared_transformations(project)
    transforms.normalize_labor || throw(ArgumentError("set input.transformations.normalize_labor=true"))
    transforms.normalize_income || throw(ArgumentError("set input.transformations.normalize_income=true"))
    node_index = Dict(id => i for (i, id) in enumerate(nodes.ids))
    metadata = validate_edge_metadata(rows, node_index)
    validate_congestion_modes(project, (row.mode for row in rows))
    require_terminal_ids(project, rows)
    physical_policy_check(project, rows)
    modes = mode_order(project, rows)
    mode_index = Dict(mode => m for (m, mode) in enumerate(modes))
    project.policy.mode in modes || throw(ArgumentError("policy mode $(project.policy.mode) is absent"))

    omega = nodes.labor ./ sum(nodes.labor)
    nu = nodes.income ./ sum(nodes.income)
    scale = transforms.flow_conversion == "divide_by_world_income" ? sum(nodes.income) : 1.0
    normalized_rows = [EdgeModeRow(
        row.edge_id, row.physical_link_id, row.origin, row.destination, row.mode,
        row.flow / scale, row.origin_terminal_id, row.destination_terminal_id,
        row.congestion_elasticity,
    ) for row in rows]

    N = length(nodes.ids)
    mode_flows = [spzeros(N, N) for _ in modes]
    for row in normalized_rows
        i, j, m = node_index[row.origin], node_index[row.destination], mode_index[row.mode]
        mode_flows[m][i, j] = row.flow
    end
    Xi = spzeros(N, N)
    for flow in mode_flows
        Xi .+= flow
    end
    dropzeros!(Xi)
    origins, destinations, _ = findnz(Xi)
    edges = sort!(collect(zip(origins, destinations)))
    edge_index = Dict(edge => t for (t, edge) in enumerate(edges))
    edge_row = Dict((node_index[row.origin], node_index[row.destination]) => row for row in normalized_rows)
    rows_by_edge = Dict{Tuple{Int,Int},Vector{EdgeModeRow}}()
    for row in normalized_rows
        edge = (node_index[row.origin], node_index[row.destination])
        push!(get!(rows_by_edge, edge, EdgeModeRow[]), row)
    end
    edge_ids = [edge_row[edge].edge_id for edge in edges]
    physical_ids = [edge_row[edge].physical_link_id for edge in edges]

    out_neighbors = [Int[] for _ in 1:N]
    in_neighbors = [Int[] for _ in 1:N]
    for (i, j) in edges
        push!(out_neighbors[i], j)
        push!(in_neighbors[j], i)
    end
    foreach(sort!, out_neighbors)
    foreach(sort!, in_neighbors)
    T_origin = nu .+ vec(sum(Xi; dims=2))
    T_destination = nu .+ vec(sum(Xi; dims=1))
    stock_disagreement = maximum(abs.(T_origin .- T_destination))
    stock_disagreement <= project.tolerance ||
        throw(ArgumentError("outgoing and incoming exposure stocks differ by $stock_disagreement; flows must satisfy the accounting identities"))
    Tnode = T_origin
    sx = nu ./ T_origin
    sy = nu ./ T_destination
    all((0 .< sx) .& (sx .< 1)) ||
        throw(ArgumentError("origin absorption shares must be interior"))
    all((0 .< sy) .& (sy .< 1)) ||
        throw(ArgumentError("destination absorption shares must be interior"))
    mu = zeros(N, N)
    lam = zeros(N, N)
    for (i, j) in edges
        mu[i, j] = Xi[i, j] / T_origin[i]
        lam[i, j] = Xi[i, j] / T_destination[j]
    end

    s_edges = zeros(length(edges), length(modes))
    shares = Dict{Tuple{Int,Int},Vector{Float64}}()
    terminal_origin = Dict{Tuple{Int,Int},String}()
    terminal_destination = Dict{Tuple{Int,Int},String}()
    pair_edge_congestion = Dict{Tuple{Int,Int},Float64}()
    active_modes = configured_active_modes(project, modes)
    for (t, edge) in enumerate(edges)
        i, j = edge
        values = [flow[i, j] for flow in mode_flows] ./ Xi[i, j]
        s_edges[t, :] .= values
        shares[edge] = collect(values)
        for row in rows_by_edge[edge]
            m = mode_index[row.mode]
            pkey = (t, m)
            row.origin_terminal_id !== nothing && (terminal_origin[pkey] = row.origin_terminal_id)
            row.destination_terminal_id !== nothing && (terminal_destination[pkey] = row.destination_terminal_id)
            if row.congestion_elasticity !== nothing
                row.congestion_elasticity > 0 && !(row.mode in active_modes) &&
                    throw(ArgumentError(
                        "edge congestion is positive for inactive mode '$(row.mode)'"))
                pair_edge_congestion[pkey] = row.congestion_elasticity
            end
        end
    end

    policy_rows = [row for row in normalized_rows if row.mode == project.policy.mode]
    policy_edges = sort!([(node_index[row.origin], node_index[row.destination]) for row in policy_rows])
    policy_lookup = Dict((node_index[row.origin], node_index[row.destination]) => row for row in policy_rows)
    policy_edge_ids = [policy_lookup[edge].edge_id for edge in policy_edges]
    policy_physical_ids = [policy_lookup[edge].physical_link_id for edge in policy_edges]

    return NetworkData(
        N, nodes.ids, node_index, nodes.longitude, nodes.latitude, modes,
        omega, nu, mode_flows, Xi, out_neighbors, in_neighbors, Tnode, sx, sy,
        mu, lam, edges, edge_ids, physical_ids, edge_index, s_edges, shares,
        policy_edges, policy_edge_ids, policy_physical_ids,
        terminal_origin, terminal_destination, pair_edge_congestion, transforms.ledger,
        Dict{String,String}(input_hashes), stock_disagreement, nothing, nothing,
    )
end

function load_generic_network(project::Project)
    nodes_path = input_path(project, "nodes")
    edges_path = input_path(project, "edge_modes")
    nodes = read_nodes(nodes_path)
    rows = read_edge_modes(edges_path; congestion_column=edge_input_column(project.congestion))
    hashes = Dict(basename(nodes_path) => file_sha256(nodes_path),
                  basename(edges_path) => file_sha256(edges_path))
    return build_network(project, nodes, rows; input_hashes=hashes)
end

function build_urban_network(project::Project, nodes, rows::Vector{EdgeModeRow}; input_hashes)
    project.spatial isa UrbanCommuting ||
        throw(ArgumentError("urban network builder requires UrbanCommuting"))
    transforms = declared_urban_transformations(project)
    transforms.normalize_residents ||
        throw(ArgumentError("set input.transformations.normalize_residents=true"))
    transforms.normalize_employment ||
        throw(ArgumentError("set input.transformations.normalize_employment=true"))
    node_index = Dict(id => i for (i, id) in enumerate(nodes.ids))
    validate_edge_metadata(rows, node_index)
    validate_congestion_modes(project, (row.mode for row in rows))
    require_terminal_ids(project, rows)
    physical_policy_check(project, rows)
    modes = mode_order(project, rows)
    mode_index = Dict(mode => m for (m, mode) in enumerate(modes))
    project.policy.mode in modes ||
        throw(ArgumentError("urban policy mode $(project.policy.mode) is absent"))

    residence = nodes.residents ./ sum(nodes.residents)
    workplace = nodes.employment ./ sum(nodes.employment)
    commuter_total = (sum(nodes.residents) + sum(nodes.employment)) / 2
    scale = transforms.flow_conversion == "divide_by_total_commuters" ? commuter_total : 1.0
    normalized_rows = [EdgeModeRow(
        row.edge_id, row.physical_link_id, row.origin, row.destination, row.mode,
        row.flow / scale, row.origin_terminal_id, row.destination_terminal_id,
        row.congestion_elasticity,
    ) for row in rows]

    N = length(nodes.ids)
    mode_flows = [spzeros(N, N) for _ in modes]
    for row in normalized_rows
        i, j, m = node_index[row.origin], node_index[row.destination], mode_index[row.mode]
        mode_flows[m][i, j] = row.flow
    end
    Xi = spzeros(N, N)
    for flow in mode_flows
        Xi .+= flow
    end
    dropzeros!(Xi)
    origins, destinations, _ = findnz(Xi)
    edges = sort!(collect(zip(origins, destinations)))
    edge_index = Dict(edge => t for (t, edge) in enumerate(edges))
    rows_by_edge = Dict{Tuple{Int,Int},Vector{EdgeModeRow}}()
    for row in normalized_rows
        edge = (node_index[row.origin], node_index[row.destination])
        push!(get!(rows_by_edge, edge, EdgeModeRow[]), row)
    end
    edge_ids = [first(rows_by_edge[edge]).edge_id for edge in edges]
    physical_ids = [first(rows_by_edge[edge]).physical_link_id for edge in edges]

    out_neighbors = [Int[] for _ in 1:N]
    in_neighbors = [Int[] for _ in 1:N]
    for (i, j) in edges
        push!(out_neighbors[i], j)
        push!(in_neighbors[j], i)
    end
    foreach(sort!, out_neighbors)
    foreach(sort!, in_neighbors)

    T_out = workplace .+ vec(sum(Xi; dims=2))
    T_in = residence .+ vec(sum(Xi; dims=1))
    stock_disagreement = maximum(abs.(T_out .- T_in))
    stock_disagreement <= project.tolerance || throw(ArgumentError(
        "urban residence, workplace, and edge flows imply inconsistent recursive stocks " *
        "(maximum disagreement $stock_disagreement); declare a balancing transformation " *
        "outside the package before loading the data"))
    Tnode = T_out
    sx = workplace ./ T_out
    sy = residence ./ T_in
    all((0 .< sx) .& (sx .<= 1)) ||
        throw(ArgumentError("urban workplace-retention shares must lie in (0,1]"))
    all((0 .< sy) .& (sy .<= 1)) ||
        throw(ArgumentError("urban residence-retention shares must lie in (0,1]"))
    mu = zeros(N, N)
    lam = zeros(N, N)
    for (i, j) in edges
        mu[i, j] = Xi[i, j] / T_out[i]
        lam[i, j] = Xi[i, j] / T_in[j]
    end

    s_edges = zeros(length(edges), length(modes))
    shares = Dict{Tuple{Int,Int},Vector{Float64}}()
    terminal_origin = Dict{Tuple{Int,Int},String}()
    terminal_destination = Dict{Tuple{Int,Int},String}()
    pair_edge_congestion = Dict{Tuple{Int,Int},Float64}()
    active_modes = configured_active_modes(project, modes)
    for (t, edge) in enumerate(edges)
        i, j = edge
        values = [flow[i, j] for flow in mode_flows] ./ Xi[i, j]
        s_edges[t, :] .= values
        shares[edge] = collect(values)
        for row in rows_by_edge[edge]
            m = mode_index[row.mode]
            pkey = (t, m)
            row.origin_terminal_id !== nothing &&
                (terminal_origin[pkey] = row.origin_terminal_id)
            row.destination_terminal_id !== nothing &&
                (terminal_destination[pkey] = row.destination_terminal_id)
            if row.congestion_elasticity !== nothing
                row.congestion_elasticity > 0 && !(row.mode in active_modes) &&
                    throw(ArgumentError(
                        "edge congestion is positive for inactive mode '$(row.mode)'"))
                pair_edge_congestion[pkey] = row.congestion_elasticity
            end
        end
    end

    policy_rows = [row for row in normalized_rows if row.mode == project.policy.mode]
    policy_edges = sort!([(node_index[row.origin], node_index[row.destination]) for row in policy_rows])
    policy_lookup = Dict((node_index[row.origin], node_index[row.destination]) => row
                         for row in policy_rows)
    policy_edge_ids = [policy_lookup[edge].edge_id for edge in policy_edges]
    policy_physical_ids = [policy_lookup[edge].physical_link_id for edge in policy_edges]
    ledger = vcat(transforms.ledger, ["commuter_total=$(commuter_total)"])

    return NetworkData(
        N, nodes.ids, node_index, nodes.longitude, nodes.latitude, modes,
        residence, workplace, mode_flows, Xi, out_neighbors, in_neighbors,
        Tnode, sx, sy, mu, lam, edges, edge_ids, physical_ids,
        edge_index, s_edges, shares, policy_edges, policy_edge_ids,
        policy_physical_ids, terminal_origin, terminal_destination,
        pair_edge_congestion, ledger,
        Dict{String,String}(input_hashes), stock_disagreement, residence, workplace,
    )
end

function load_generic_urban_network(project::Project)
    nodes_path = input_path(project, "nodes")
    edges_path = input_path(project, "edge_modes")
    nodes = read_urban_nodes(nodes_path)
    rows = read_edge_modes(
        edges_path; congestion_column=edge_input_column(project.congestion))
    hashes = Dict(basename(nodes_path) => file_sha256(nodes_path),
                  basename(edges_path) => file_sha256(edges_path))
    return build_urban_network(project, nodes, rows; input_hashes=hashes)
end

function edge_congestion_metadata(project::Project, data)
    source = edge_congestion_source(project.congestion)
    column = edge_input_column(project.congestion)
    scale = edge_congestion_scale(project.congestion)
    active_modes = configured_active_modes(project, data.modes)
    values = if source == "input_column"
        [value*scale for ((_, m), value) in data.pair_edge_congestion
         if data.modes[m] in active_modes]
    elseif source == "mode"
        [get(edge_lambdas(project.congestion), data.modes[m], 0.0)
         for m in eachindex(data.modes) if data.modes[m] in active_modes
         for _ in 1:nnz(data.mode_flows[m])]
    else
        Float64[]
    end
    summary = Dict{String,Any}(
        "source" => source,
        "input_column" => column === nothing ? missing : column,
        "scale" => scale,
        "count" => length(values),
        "positive_count" => count(>(0), values),
    )
    if !isempty(values)
        summary["minimum"] = minimum(values)
        summary["median"] = median(values)
        summary["mean"] = mean(values)
        summary["maximum"] = maximum(values)
    end
    return summary
end

function load_network(project::Project)
    adapter = lowercase(String(get(project.input, "adapter", "generic_csv_v1")))
    if adapter == "generic_csv_v1"
        return project.spatial isa UrbanCommuting ?
            load_generic_urban_network(project) : load_generic_network(project)
    end
    adapter == "rsue_frozen_2026_07_12" && return load_rsue_network(project)
    adapter == "rsue_census_ports_2017_v1" && return load_rsue_network(project)
    throw(ArgumentError("unknown input adapter: $adapter"))
end

"Validate input schemas, accounting identities, route contraction, and model regularity."
function validate(project::Project)
    isfinite(project.condition_limit) && 1 < project.condition_limit <= 1e12 ||
        throw(ArgumentError("condition_limit must be finite and lie in (1, 1e12]"))
    isfinite(project.tolerance) && project.tolerance > 0 ||
        throw(ArgumentError("diagnostic tolerance must be finite and positive"))
    data = load_network(project)
    if project.spatial isa UrbanCommuting
        model = build_urban_welfare_model(project; data)
        route = model.basis.diagnostics
        regression = urban_oracle_regression(model)
        regression.available &&
            maximum((regression.state_response_error, regression.welfare_error)) >
                project.tolerance &&
            throw(ArgumentError(
                "the shared urban transport system failed its one-mode regression gate"))
        return (;
            valid=true, spatial_specification=spatial_name(project.spatial),
            nodes=data.N, directed_edges=length(data.edges),
            active_edge_modes=sum(nnz, data.mode_flows),
            policy_arcs=length(data.policy_edges), modes=String.(data.modes),
            theta=commuting_theta(project.parameters),
            route_spectral_radius=route.spectral_radius,
            route_absorption_error=route.absorption_error,
            route_bilateral_row_error=route.row_error,
            route_bilateral_column_error=route.column_error,
            route_edge_error=route.edge_error,
            stock_disagreement=data.stock_disagreement,
            condition_urban=model.closures.conditions.F,
            condition_transport=model.closures.transport.F.condition,
            one_mode_regression=regression,
            transformations=data.transformations,
            input_hashes=data.input_hashes,
            edge_congestion=edge_congestion_metadata(project, data),
            decomposition_incidence_gib=missing,
        )
    end
    c = AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    spectral_radius = maximum(abs, eigvals(data.mu))
    isfinite(spectral_radius) && spectral_radius < 1 ||
        throw(ArgumentError("route kernel is not contractive"))
    all(isfinite, (c.e, c.ρ)) ||
        throw(ArgumentError("model coefficients are nonfinite"))
    return (;
        valid=true,
        spatial_specification=spatial_name(project.spatial),
        nodes=data.N,
        directed_edges=length(data.edges),
        active_edge_modes=sum(nnz, data.mode_flows),
        policy_arcs=length(data.policy_edges),
        modes=String.(data.modes),
        e=c.e,
        rho=c.ρ,
        route_spectral_radius=spectral_radius,
        stock_disagreement=data.stock_disagreement,
        transformations=data.transformations,
        input_hashes=data.input_hashes,
        edge_congestion=edge_congestion_metadata(project, data),
        decomposition_incidence_gib=data.N^2*length(data.edges)*sizeof(Float64)/2.0^30,
    )
end
