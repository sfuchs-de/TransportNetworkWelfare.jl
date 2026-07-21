function rsue_input_directory(project::Project)
    haskey(project.input, "data_root") ||
        throw(ArgumentError("RSUE replication requires input.data_root, normally '\${RSUE_DATA_ROOT}'"))
    root = resolve_path(project.root, String(project.input["data_root"]))
    direct = joinpath(root, "node_labor_income_interstate.csv")
    nested = joinpath(root, "Input", "node_labor_income_interstate.csv")
    isfile(direct) && return root
    isfile(nested) && return joinpath(root, "Input")
    throw(ArgumentError("RSUE inputs were not found below $root; set RSUE_DATA_ROOT to the directory containing the audited RSUE CSV files or its parent"))
end

function verify_rsue_manifest(project::Project, input_dir::AbstractString)
    manifest_path = haskey(project.input, "manifest") ?
        resolve_path(project.root, String(project.input["manifest"])) :
        normpath(joinpath(@__DIR__, "..", "replication", "rsue", "input_manifest.toml"))
    isfile(manifest_path) || throw(ArgumentError("RSUE input manifest not found: $manifest_path"))
    manifest = TOML.parsefile(manifest_path)
    expected = get(manifest, "files", Dict{String,Any}())
    isempty(expected) && throw(ArgumentError("RSUE input manifest contains no [files] entries"))
    actual = Dict{String,String}()
    for (name, digest) in expected
        path = joinpath(input_dir, name)
        isfile(path) || throw(ArgumentError("RSUE input is missing: $path"))
        actual[name] = file_sha256(path)
        lowercase(actual[name]) == lowercase(String(digest)) ||
            throw(ArgumentError("RSUE input hash mismatch for $name; expected $digest, got $(actual[name])"))
    end
    return actual
end

function require_rsue_transformations(project::Project)
    raw = get(project.input, "transformations", Dict{String,Any}())
    expected = Dict{String,Any}(
        "domestic_nodes" => 228,
        "padded_foreign_nodes" => 6,
        "symmetrize_modes" => true,
        "normalize_mode_matrices" => true,
        "apply_rsue_modal_weights" => true,
        "filter_rail_by_terminal_count" => true,
    )
    for (key, value) in expected
        get(raw, key, nothing) == value ||
            throw(ArgumentError("RSUE adapter requires input.transformations.$key=$(repr(value))"))
    end
    return ["$key=$(expected[key])" for key in sort!(collect(keys(expected)))]
end

function require_rsue_census_transformations(project::Project)
    raw = get(project.input, "transformations", Dict{String,Any}())
    expected = Dict{String,Any}(
        "foreign_port_symmetrize" => false,
        "foreign_port_balance" => "ras_common_normalized_port_and_region_margins",
        "foreign_port_measure" => "CNT_VAL_MO",
        "foreign_port_period" => "2017-01:2017-12",
    )
    for (key, value) in expected
        get(raw, key, nothing) == value ||
            throw(ArgumentError("RSUE Census adapter requires input.transformations.$key=$(repr(value))"))
    end
    return ["$key=$(expected[key])" for key in sort!(collect(keys(expected)))]
end

function rsue_triplets(table, value_column::Int, n::Int)
    origins = Int.(@view table[:, 1])
    destinations = Int.(@view table[:, 2])
    values = Float64.(@view table[:, value_column])
    matrix = sparse(origins, destinations, values, n, n)
    matrix[diagind(matrix)] .= 0
    dropzeros!(matrix)
    return matrix
end

rsue_symmetrize(matrix) = matrix .+ permutedims(matrix)

function rsue_normalize!(matrix)
    total = sum(matrix)
    total > 0 && (matrix ./= total)
    return matrix
end

function rsue_census_port_matrix(project::Project, n::Int, n_domestic::Int)
    path = input_path(project, "census_port_overlay")
    expected_hash = lowercase(String(get(project.input, "census_port_overlay_sha256", "")))
    isempty(expected_hash) &&
        throw(ArgumentError("RSUE Census adapter requires input.census_port_overlay_sha256"))
    actual_hash = file_sha256(path)
    actual_hash == expected_hash || throw(ArgumentError(
        "RSUE Census port-overlay hash mismatch; expected $expected_hash, got $actual_hash"))

    table = CSV.File(path; normalizenames=false)
    require_columns(path, propertynames(table), [
        "origin_node", "destination_node", "domestic_node", "foreign_node",
        "direction", "model_share",
    ])
    origins = Int[]
    destinations = Int[]
    shares = Float64[]
    seen = Set{Tuple{Int,Int}}()
    node_balance = zeros(n)
    for (row_number, row) in enumerate(table)
        origin_value = cell_float(getproperty(row, :origin_node), path, "origin_node", row_number)
        destination_value = cell_float(getproperty(row, :destination_node), path, "destination_node", row_number)
        domestic_value = cell_float(getproperty(row, :domestic_node), path, "domestic_node", row_number)
        foreign_value = cell_float(getproperty(row, :foreign_node), path, "foreign_node", row_number)
        all(isinteger, (origin_value, destination_value, domestic_value, foreign_value)) ||
            throw(ArgumentError("$path row $row_number has a noninteger node identifier"))
        origin, destination = Int(origin_value), Int(destination_value)
        domestic, foreign = Int(domestic_value), Int(foreign_value)
        1 <= domestic <= n_domestic ||
            throw(ArgumentError("$path row $row_number has invalid domestic_node=$domestic"))
        n_domestic < foreign <= n ||
            throw(ArgumentError("$path row $row_number has invalid foreign_node=$foreign"))
        direction = cell_string(getproperty(row, :direction))
        expected_pair = if direction == "domestic_to_foreign"
            (domestic, foreign)
        elseif direction == "foreign_to_domestic"
            (foreign, domestic)
        else
            throw(ArgumentError("$path row $row_number has invalid direction=$(repr(direction))"))
        end
        (origin, destination) == expected_pair || throw(ArgumentError(
            "$path row $row_number has endpoints inconsistent with $direction"))
        pair = (origin, destination)
        pair in seen && throw(ArgumentError("$path contains duplicate directed pair $pair"))
        push!(seen, pair)
        share = cell_float(getproperty(row, :model_share), path, "model_share", row_number)
        share > 0 || throw(ArgumentError("$path row $row_number has nonpositive model_share"))
        push!(origins, origin)
        push!(destinations, destination)
        push!(shares, share)
        node_balance[origin] += share
        node_balance[destination] -= share
    end
    isempty(shares) && throw(ArgumentError("RSUE Census port overlay is empty: $path"))
    abs(sum(shares) - 1) <= 10 * project.tolerance || throw(ArgumentError(
        "RSUE Census port-overlay shares sum to $(sum(shares)), not one"))
    balance_residual = maximum(abs, node_balance)
    balance_residual <= 10 * project.tolerance || throw(ArgumentError(
        "RSUE Census port overlay violates the balanced-flow identity by $balance_residual"))
    return sparse(origins, destinations, shares, n, n), actual_hash,
        length(shares), balance_residual
end

"Load a declared 234-node RSUE calibration while recording every transformation."
function load_rsue_network(project::Project)
    project.policy.mode == :road ||
        throw(ArgumentError("the RSUE adapters currently support road policy shocks only"))
    adapter = lowercase(String(get(project.input, "adapter", "")))
    census_ports = adapter == "rsue_census_ports_2017_v1"
    adapter in ("rsue_frozen_2026_07_12", "rsue_census_ports_2017_v1") ||
        throw(ArgumentError("unsupported RSUE adapter: $adapter"))
    input_dir = rsue_input_directory(project)
    input_hashes = verify_rsue_manifest(project, input_dir)
    transformations = require_rsue_transformations(project)
    census_ports && append!(transformations, require_rsue_census_transformations(project))
    readcsv(name) = readdlm(joinpath(input_dir, name), ',', Float64)

    N_dom, N = 228, 234
    modes = [:road, :rail, :water_dom, :water_for]
    road_table = readcsv("sparse_adjmat_interstate.csv")
    rail_table = readcsv("bilateral_rail_sparse.csv")
    barge_table = readcsv("bilateral_barges_sparse.csv")
    port_table = census_ports ? nothing : readcsv("bilateral_port_sparse.csv")
    terminal_count = vec(readcsv("terminals_count.csv"))
    nodes = readcsv("node_labor_income_interstate.csv")

    labor_domestic = nodes[:, 2] ./ sum(nodes[:, 2])
    income_domestic = nodes[:, 3] ./ sum(nodes[:, 3])
    labor = zeros(N)
    income = zeros(N)
    labor[1:N_dom] .= labor_domestic
    income[1:N_dom] .= income_domestic
    labor[N_dom+1:N] .= mean(labor_domestic)
    income[N_dom+1:N] .= mean(income_domestic)
    omega = labor ./ sum(labor)
    nu = income ./ sum(income)

    road = rsue_triplets(road_table, 3, N)
    rail = rsue_triplets(rail_table, 4, N)
    barge = rsue_triplets(barge_table, 8, N)
    port, census_overlay_rows, census_balance_residual = if census_ports
        matrix, digest, rows, residual = rsue_census_port_matrix(project, N, N_dom)
        input_hashes[basename(input_path(project, "census_port_overlay"))] = digest
        matrix, rows, residual
    else
        rsue_triplets(vcat(port_table, port_table[:, [2, 1, 3]]), 3, N), 0, 0.0
    end
    for i in 1:min(N_dom, length(terminal_count))
        if terminal_count[i] == 0
            rail[i, :] .= 0
            rail[:, i] .= 0
        end
    end
    dropzeros!(rail)

    aggregates = [
        1257.1 * 1838648.0,
        1051.5 * 1712567.0,
        432.5 * 474858.0,
        3611.5 * 102256.0,
    ]
    tradable_adjustment = 1512525 / (1512525 + 3959839)
    mode_weights = tradable_adjustment .* aggregates ./ sum(aggregates)
    mode_flows = [road, rail, barge, port]
    for m in eachindex(mode_flows)
        mode_flows[m] = if census_ports && m == 4
            rsue_normalize!(mode_flows[m])
        else
            rsue_normalize!(rsue_symmetrize(mode_flows[m]))
        end
        mode_flows[m] .*= mode_weights[m]
    end
    road, rail, barge, port = mode_flows

    Xi = spzeros(N, N)
    for flow in mode_flows
        Xi .+= flow
    end
    dropzeros!(Xi)
    origins, destinations, _ = findnz(Xi)
    edges = sort!(collect(zip(origins, destinations)))
    edge_index = Dict(edge => t for (t, edge) in enumerate(edges))
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
    stock_disagreement <= project.tolerance || error("RSUE exposure-stock identity failed")
    sx = nu ./ T_origin
    sy = nu ./ T_destination
    mu = zeros(N, N)
    lam = zeros(N, N)
    for (i, j) in edges
        mu[i, j] = Xi[i, j] / T_origin[i]
        lam[i, j] = Xi[i, j] / T_destination[j]
    end

    s_edges = zeros(length(edges), length(modes))
    shares = Dict{Tuple{Int,Int},Vector{Float64}}()
    for (t, (i, j)) in enumerate(edges)
        values = [flow[i, j] for flow in mode_flows] ./ Xi[i, j]
        s_edges[t, :] .= values
        shares[(i, j)] = collect(values)
    end
    road_edges = sort!([(i, j) for (i, j) in edges if road[i, j] > 0])
    all((j, i) in road_edges for (i, j) in road_edges) ||
        error("every RSUE road arc must have an opposite direction")

    node_ids = string.(1:N)
    longitude = Union{Missing,Float64}[i <= size(nodes, 1) ? nodes[i, 4] : missing for i in 1:N]
    latitude = Union{Missing,Float64}[i <= size(nodes, 1) ? nodes[i, 5] : missing for i in 1:N]
    edge_ids = ["$(i)_$(j)" for (i, j) in edges]
    physical_ids = ["$(min(i,j))_$(max(i,j))" for (i, j) in edges]
    policy_edge_ids = ["$(i)_$(j)" for (i, j) in road_edges]
    policy_physical_ids = ["$(min(i,j))_$(max(i,j))" for (i, j) in road_edges]
    terminal_origin = Dict{Tuple{Int,Int},String}()
    terminal_destination = Dict{Tuple{Int,Int},String}()
    rail_mode = findfirst(==(:rail), modes)
    for (t, (i, j)) in enumerate(edges)
        rail[i, j] > 0 || continue
        terminal_origin[(t, rail_mode)] = string(i)
        terminal_destination[(t, rail_mode)] = string(j)
    end

    formatted_weights = join([@sprintf("%.17g", value) for value in mode_weights], ';')
    append!(transformations, [
        "mode_weights=$formatted_weights",
        "tradable_adjustment=$(@sprintf("%.17g", tradable_adjustment))",
    ])
    if census_ports
        append!(transformations, [
            "census_port_overlay_rows=$census_overlay_rows",
            "census_port_balance_residual=$(@sprintf("%.17g", census_balance_residual))",
        ])
    end
    return NetworkData(
        N, node_ids, Dict(id => i for (i, id) in enumerate(node_ids)),
        longitude, latitude, modes, omega, nu, mode_flows, Xi,
        out_neighbors, in_neighbors, T_origin, sx, sy, mu, lam, edges,
        edge_ids, physical_ids, edge_index, s_edges, shares, road_edges,
        policy_edge_ids, policy_physical_ids, terminal_origin, terminal_destination,
        transformations, input_hashes, stock_disagreement,
    )
end
