#!/usr/bin/env julia

module SeattleTransitImpacts

using CSV
using Printf
using SHA
using Statistics
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const EXAMPLE_ROOT = @__DIR__
const PACKAGE_ROOT = normpath(joinpath(EXAMPLE_ROOT, "..", ".."))
const TRANSIT_MODES = (:bus, :rail, :ferry)
const ETA_VALUES = (0.75, 0.90, 1.099, 1.25, 1.40)

sha256_file(path::AbstractString) = bytes2hex(open(SHA.sha256, path))

function option(args, name; default=nothing)
    index = findfirst(==(name), args)
    index === nothing && return default
    index < length(args) || throw(ArgumentError("$name requires a value"))
    return args[index+1]
end

function require_exact_build(generated_root::AbstractString)
    manifest = joinpath(generated_root, "build_manifest.json")
    isfile(manifest) || throw(ArgumentError(
        "Seattle build manifest is missing: run prepare.jl with the exact 2017 sources"))
    text = read(manifest, String)
    occursin("ad172e653aa881557a5f3cb84f2ace6819308600", text) ||
        throw(ArgumentError("Seattle build does not identify the pinned 2017 GTFS"))
    occursin("\"eta\":1.099", text) || throw(ArgumentError(
        "Seattle build must use the transferred baseline eta=1.099"))
    return manifest
end

function correlation(left, right)
    length(left) > 1 || return missing
    std(left) > 0 && std(right) > 0 || return missing
    return cor(left, right)
end

function rank_map(rows, field)
    order = sortperm(rows; by=row -> (-getproperty(row, field),
                                      String(row.corridor_id)))
    return Dict(rows[index].corridor_id => rank for (rank, index) in enumerate(order))
end

function aggregate_corridors(rows; mode::AbstractString)
    grouped = Dict{Tuple{String,String},Vector{NamedTuple}}()
    for row in rows
        origin, destination = String(row.origin), String(row.destination)
        key = origin < destination ? (origin, destination) : (destination, origin)
        push!(get!(grouped, key, NamedTuple[]), row)
    end
    output = NamedTuple[]
    for key in sort!(collect(keys(grouped)))
        group = grouped[key]
        ordered = Set((String(row.origin), String(row.destination)) for row in group)
        push!(output, (;
            corridor_id="$(key[1])_$(key[2])",
            origin=key[1],
            destination=key[2],
            mode=String(mode),
            directions=length(ordered),
            complete_reciprocal=length(ordered) == 2,
            hulten=sum(row.hulten for row in group),
            realized_F=sum(row.realized_F for row in group),
            primitive_F=sum(row.primitive_F for row in group),
            primitive_pass_through=sum(row.primitive_pass_through for row in group),
            traditional_gain_pct=sum(row.hulten for row in group),
            extended_gain_pct=sum(row.primitive_F for row in group),
            extended_minus_traditional_pct=
                sum(row.primitive_F-row.hulten for row in group),
        ))
    end
    traditional = rank_map(output, :hulten)
    extended = rank_map(output, :primitive_F)
    return [merge(row, (;
        traditional_rank=traditional[row.corridor_id],
        extended_rank=extended[row.corridor_id],
    )) for row in output]
end

function aggregate_all_transit(mode_rows)
    grouped = Dict{Tuple{String,String},Vector{NamedTuple}}()
    for rows in values(mode_rows), row in rows
        key = (String(row.origin), String(row.destination))
        push!(get!(grouped, key, NamedTuple[]), row)
    end
    directed = NamedTuple[]
    for key in sort!(collect(keys(grouped)))
        group = grouped[key]
        push!(directed, (;
            edge_id="$(key[1])_$(key[2])",
            physical_link_id="$(min(key...))_$(max(key...))",
            origin=key[1],
            destination=key[2],
            mode="all_transit",
            hulten=sum(row.hulten for row in group),
            realized_F=sum(row.realized_F for row in group),
            primitive_F=sum(row.primitive_F for row in group),
            primitive_pass_through=sum(row.primitive_pass_through for row in group),
        ))
    end
    return directed
end

function route_metadata(path::AbstractString)
    metadata = Dict{String,NamedTuple}()
    for row in CSV.File(path; normalizenames=false)
        bundle = string(getproperty(row, :bundle_id))
        agency = getproperty(row, :agency_id)
        item = (;
            route_id=string(getproperty(row, :route_id)),
            route_name=string(getproperty(row, :route_name)),
            agency_id=agency === missing ? "" : string(agency),
        )
        if haskey(metadata, bundle)
            metadata[bundle] == item || throw(ArgumentError(
                "route bundle $bundle has inconsistent metadata"))
        else
            metadata[bundle] = item
        end
    end
    return metadata
end

canonical_route_label(value) =
    uppercase(join(split(strip(string(value))), " "))

function route_service_activity(path::AbstractString)
    grouped = Dict{String,NamedTuple}()
    counts = Dict{String,Int}()
    for row in CSV.File(path; normalizenames=false)
        bundle = string(getproperty(row, :bundle_id))
        metadata = (;
            route_id=string(getproperty(row, :route_id)),
            route_name=string(getproperty(row, :route_name)),
            mode=string(getproperty(row, :mode)),
        )
        if haskey(grouped, bundle)
            grouped[bundle] == metadata || throw(ArgumentError(
                "route bundle $bundle has inconsistent activity metadata"))
        else
            grouped[bundle] = metadata
        end
        counts[bundle] = get(counts, bundle, 0) +
            Int(getproperty(row, :service_count))
    end
    return [merge(grouped[bundle], (;
        bundle_id=bundle,
        scheduled_edge_traversals=counts[bundle],
    )) for bundle in sort!(collect(keys(grouped)))]
end

function compare_route_activity(bundle_path::AbstractString,
                                metro_path::AbstractString)
    isfile(metro_path) || throw(ArgumentError(
        "Metro route-activity table is missing: $metro_path"))
    metro = Dict{String,NamedTuple}()
    for row in CSV.File(metro_path; normalizenames=false)
        route = canonical_route_label(getproperty(row, :route))
        haskey(metro, route) && throw(ArgumentError(
            "Metro route-activity table contains duplicate route $route"))
        rides = getproperty(row, :weekday_rides_fall_2016)
        metro[route] = (;
            metro_weekday_rides_fall_2016=
                rides === missing ? missing : Float64(rides),
            metro_ridership_censored_below_50=Bool(
                getproperty(row, :weekday_rides_fall_2016_censored_below_50)),
        )
    end
    comparison = NamedTuple[]
    for row in route_service_activity(bundle_path)
        row.mode == "bus" || continue
        key = canonical_route_label(row.route_name)
        observed = get(metro, key, (;
            metro_weekday_rides_fall_2016=missing,
            metro_ridership_censored_below_50=false,
        ))
        push!(comparison, merge(row, observed, (;
            matched_metro_route=haskey(metro, key),
        )))
    end
    isempty(comparison) && throw(ArgumentError(
        "route-activity comparison contains no bus routes"))
    matched = filter(row ->
        row.matched_metro_route &&
        !ismissing(row.metro_weekday_rides_fall_2016), comparison)
    service = Float64[row.scheduled_edge_traversals for row in matched]
    ridership = Float64[row.metro_weekday_rides_fall_2016 for row in matched]
    summary = (;
        gtfs_bus_routes=length(comparison),
        metro_routes_matched=count(row.matched_metro_route for row in comparison),
        metro_routes_with_numeric_ridership=length(matched),
        metro_route_coverage=count(row.matched_metro_route for row in comparison) /
            length(comparison),
        pearson_service_ridership=correlation(service, ridership),
        spearman_service_ridership=length(matched) > 1 ?
            TNW.spearman_correlation(service, ridership) : missing,
        interpretation="external comparison only; GTFS schedule activity is not observed ridership",
    )
    return (; comparison, summary)
end

function add_route_metadata(rows, metadata)
    enriched = [merge(row, metadata[row.bundle_id]) for row in rows]
    traditional_order = sortperm(enriched; by=row ->
        (-row.hulten, row.route_name, row.route_id))
    extended_order = sortperm(enriched; by=row ->
        (-row.primitive_F, row.route_name, row.route_id))
    traditional = Dict(enriched[index].bundle_id => rank
                       for (rank, index) in enumerate(traditional_order))
    extended = Dict(enriched[index].bundle_id => rank
                    for (rank, index) in enumerate(extended_order))
    return [merge(row, (;
        traditional_rank=traditional[row.bundle_id],
        extended_rank=extended[row.bundle_id],
    )) for row in enriched]
end

function top_union(rows, count::Int)
    selected = [row for row in rows
                if row.traditional_rank <= count || row.extended_rank <= count]
    sort!(selected; by=row ->
        (min(row.traditional_rank, row.extended_rank),
         row.extended_rank, row.traditional_rank))
    return selected
end

function mode_summary(mode, rows, corridors, routes)
    hulten = getproperty.(rows, :hulten)
    primitive = getproperty.(rows, :primitive_F)
    return (;
        mode=String(mode),
        directed_interventions=length(rows),
        mapped_corridors=length(corridors),
        reciprocal_corridors=count(row.complete_reciprocal for row in corridors),
        route_corridors=length(routes),
        mean_traditional_gain_pct=mean(hulten),
        mean_extended_gain_pct=mean(primitive),
        median_traditional_gain_pct=median(hulten),
        median_extended_gain_pct=median(primitive),
        pearson=correlation(hulten, primitive),
        spearman=length(rows) > 1 ?
            TNW.spearman_correlation(hulten, primitive) : missing,
    )
end

function finite_difference_rows(model, result)
    count = length(result.directed)
    count > 0 || throw(ArgumentError("finite differences require policy arcs"))
    ordering = sortperm(result.directed; by=row -> row.hulten)
    selected = unique(ordering[index] for index in
        (1, cld(count, 2), count))
    output = NamedTuple[]
    for index in selected
        analytic = result.directed[index].primitive_F
        check = TNW.urban_multimodal_finite_difference(
            model, index; closure=:F, shock_type=:primitive, step=1e-5,
            state_jacobian=:baseline_analytic)
        error = abs(analytic-check.elasticity)
        push!(output, (;
            mode=String(model.project.policy.mode),
            edge_id=result.directed[index].edge_id,
            traffic_quantile=index == selected[1] ? "low" :
                             index == selected[end] ? "high" : "middle",
            analytic,
            finite_difference=check.elasticity,
            nonlinear_state_jacobian="baseline_analytic_preconditioner",
            absolute_error=error,
            passed=error <= 1e-6,
        ))
    end
    all(row.passed for row in output) || throw(ArgumentError(
        "Seattle finite-difference verification exceeded 1e-6"))
    return output
end

function eta_rows(project, baseline_rows)
    baseline = Dict(String(row.edge_id) => row.primitive_F for row in baseline_rows)
    baseline_keys = sort!(collect(keys(baseline)))
    output = NamedTuple[]
    effects_by_eta = Dict{Float64,Vector{Float64}}()
    for eta in ETA_VALUES
        candidate = TNW.replace_project(project; modal=ChoiceLogsum(eta))
        result = welfare_effects(TNW.build_welfare_model(candidate))
        effects = Dict(String(row.edge_id) => row.primitive_F for row in result.directed)
        sort!(collect(keys(effects))) == baseline_keys ||
            throw(ArgumentError("eta sensitivity changed the policy-edge support"))
        base_vector = [baseline[key] for key in baseline_keys]
        vector = [effects[key] for key in baseline_keys]
        effects_by_eta[eta] = vector
        push!(output, (;
            mode=String(project.policy.mode),
            eta,
            mean_extended_gain_pct=mean(vector),
            median_extended_gain_pct=median(vector),
            spearman_vs_eta_1_099=length(vector) > 1 ?
                TNW.spearman_correlation(base_vector, vector) : missing,
            minimum_extended_gain_pct=minimum(vector),
            maximum_extended_gain_pct=maximum(vector),
            verified=result.diagnostics["verified"],
        ))
    end
    return (; rows=output, effects=effects_by_eta,
            baseline=[baseline[key] for key in baseline_keys])
end

function write_tex_table(path, rows; identifier::Symbol, label::AbstractString)
    open(path, "w") do io
        println(io, "\\begin{tabular}{llrrrr}")
        println(io, "\\toprule")
        println(io, "$label & Mode & Traditional & Extended & " *
                    "Traditional rank & Extended rank \\\\")
        println(io, "\\midrule")
        for row in rows
            name = replace(String(getproperty(row, identifier)),
                           "_" => "\\_", "&" => "\\&", "%" => "\\%")
            @printf(io, "%s & %s & %.6g & %.6g & %d & %d \\\\\n",
                name, row.mode, row.traditional_gain_pct,
                row.extended_gain_pct, row.traditional_rank, row.extended_rank)
        end
        println(io, "\\bottomrule")
        println(io, "\\end{tabular}")
    end
    return path
end

function run_plots(output, generated_root, geography_root, python)
    script = joinpath(PACKAGE_ROOT, "plots", "seattle_transit_impacts.py")
    nodes = joinpath(generated_root, "data", "nodes.csv")
    run(`$python $script --artifacts $output --nodes $nodes --geography-root $geography_root`)
    stems = (
        "seattle_transit_welfare_map",
        "seattle_all_transit_welfare_map",
        "seattle_transit_extended_minus_traditional",
        "seattle_transit_traditional_extended",
        "seattle_route_corridor_rankings",
        "seattle_eta_sensitivity",
    )
    paths = [joinpath(output, "$stem.$extension")
             for stem in stems for extension in ("pdf", "png")]
    all(isfile, paths) || throw(ArgumentError(
        "Seattle plotting command did not produce its complete output set"))
    return paths
end

function build(generated_root::AbstractString, output::AbstractString;
               geography_root::AbstractString,
               metro_activity_path::AbstractString,
               plots::Bool=true,
               python::AbstractString="python3")
    root = abspath(generated_root)
    destination = abspath(output)
    mkpath(destination)
    build_manifest = require_exact_build(root)
    bundles_path = joinpath(root, "data", "route_bundles.csv")
    all_entries = load_policy_bundles(bundles_path)
    metadata = route_metadata(bundles_path)
    route_validation = compare_route_activity(
        bundles_path, abspath(metro_activity_path))

    mode_rows = Dict{Symbol,Vector{NamedTuple}}()
    mode_corridors = Dict{Symbol,Vector{NamedTuple}}()
    mode_routes = Dict{Symbol,Vector{NamedTuple}}()
    summaries = NamedTuple[]
    finite_differences = NamedTuple[]
    sensitivity = NamedTuple[]
    eta_effects = Dict{Symbol,Dict{Float64,Vector{Float64}}}()
    eta_baselines = Dict{Symbol,Vector{Float64}}()
    outputs = String[]

    for mode in TRANSIT_MODES
        config = joinpath(root, "config_$(String(mode)).toml")
        project = load_project(config)
        project.modal isa ChoiceLogsum && project.modal.eta == 1.099 ||
            throw(ArgumentError("Seattle policy configuration must use ChoiceLogsum(1.099)"))
        model = TNW.build_welfare_model(project)
        result = welfare_effects(model)
        result.diagnostics["verified"] ||
            throw(ArgumentError("Seattle $mode welfare analysis failed verification"))
        rows = result.directed
        mode_rows[mode] = rows
        corridors = aggregate_corridors(rows; mode=String(mode))
        mode_corridors[mode] = corridors
        entries = filter(entry -> entry.mode == mode, all_entries)
        routes = isempty(entries) ? NamedTuple[] : add_route_metadata(
            bundle_welfare_effects(model, entries), metadata)
        mode_routes[mode] = routes

        push!(outputs, TNW.write_table(
            joinpath(destination, "directed_$(String(mode)).csv"), rows))
        push!(outputs, TNW.write_table(
            joinpath(destination, "links_$(String(mode)).csv"), corridors))
        isempty(routes) || push!(outputs, TNW.write_table(
            joinpath(destination, "routes_$(String(mode)).csv"), routes))
        append!(summaries, [mode_summary(mode, rows, corridors, routes)])
        append!(finite_differences, finite_difference_rows(model, result))
        eta_report = eta_rows(project, rows)
        append!(sensitivity, eta_report.rows)
        eta_effects[mode] = eta_report.effects
        eta_baselines[mode] = eta_report.baseline
    end

    all_directed = aggregate_all_transit(mode_rows)
    all_corridors = aggregate_corridors(all_directed; mode="all_transit")
    all_routes = reduce(vcat, (mode_routes[mode] for mode in TRANSIT_MODES);
                        init=NamedTuple[])
    all_summary = mode_summary(:all_transit, all_directed, all_corridors, all_routes)
    push!(summaries, all_summary)

    for eta in ETA_VALUES
        vector = reduce(vcat, (eta_effects[mode][eta] for mode in TRANSIT_MODES);
                        init=Float64[])
        baseline = reduce(vcat, (eta_baselines[mode] for mode in TRANSIT_MODES);
                          init=Float64[])
        push!(sensitivity, (;
            mode="all_transit",
            eta,
            mean_extended_gain_pct=mean(vector),
            median_extended_gain_pct=median(vector),
            spearman_vs_eta_1_099=TNW.spearman_correlation(baseline, vector),
            minimum_extended_gain_pct=minimum(vector),
            maximum_extended_gain_pct=maximum(vector),
            verified=true,
        ))
    end

    link_union = reduce(vcat,
        (top_union(mode_corridors[mode], 30) for mode in TRANSIT_MODES);
        init=NamedTuple[])
    route_union = NamedTuple[]
    for mode in TRANSIT_MODES
        append!(route_union, top_union(mode_routes[mode], 30))
    end
    sort!(link_union; by=row ->
        (row.mode, min(row.traditional_rank, row.extended_rank),
         row.extended_rank, row.corridor_id))
    sort!(route_union; by=row ->
        (row.mode, min(row.traditional_rank, row.extended_rank),
         row.extended_rank, row.route_id))
    append!(outputs, [
        TNW.write_table(joinpath(destination, "directed_all_transit.csv"), all_directed),
        TNW.write_table(joinpath(destination, "links_all_transit.csv"), all_corridors),
        TNW.write_table(joinpath(destination, "routes_all_transit.csv"), all_routes),
        TNW.write_table(joinpath(destination, "top30_links.csv"), link_union),
        TNW.write_table(joinpath(destination, "top30_routes.csv"), route_union),
        TNW.write_table(joinpath(destination, "eta_sensitivity.csv"), sensitivity),
        TNW.write_table(joinpath(destination, "finite_difference_checks.csv"),
                        finite_differences),
        TNW.write_table(joinpath(destination, "summary.csv"), summaries),
        TNW.write_table(
            joinpath(destination, "route_activity_validation.csv"),
            route_validation.comparison),
        TNW.write_table(
            joinpath(destination, "route_activity_validation_summary.csv"),
            [route_validation.summary]),
        write_tex_table(joinpath(destination, "top30_links.tex"), link_union;
                        identifier=:corridor_id, label="Link"),
        write_tex_table(joinpath(destination, "top30_routes.tex"), route_union;
                        identifier=:route_name, label="Route"),
    ])

    plots && append!(outputs,
        run_plots(destination, root, geography_root, python))
    all(row.passed for row in finite_differences) ||
        throw(ArgumentError("finite-difference checks did not pass"))
    manifest = Dict{String,Any}(
        "schema_version" => 1,
        "vintage" => 2017,
        "eta" => 1.099,
        "eta_status" => "transferred_economic_geography_baseline",
        "policy_shock" => "one-percent primitive generalized-cost reduction",
        "modes" => String.(TRANSIT_MODES),
        "build_manifest_sha256" => sha256_file(build_manifest),
        "route_bundle_sha256" => sha256_file(bundles_path),
        "finite_difference_tolerance" => 1e-6,
        "finite_difference_max_error" =>
            maximum(row.absolute_error for row in finite_differences),
        "metro_route_activity_sha256" => sha256_file(metro_activity_path),
        "metro_route_activity_validation" => route_validation.summary,
        "verification_status" => "passed",
        "output_hashes" =>
            Dict(basename(path) => sha256_file(path) for path in outputs),
    )
    manifest_path = joinpath(destination, "artifact_manifest.json")
    open(manifest_path, "w") do io
        println(io, TNW.json_value(manifest))
    end
    return (; manifest_path, outputs, summaries)
end

function main(args=ARGS)
    generated = abspath(option(args, "--generated-root";
        default=joinpath(EXAMPLE_ROOT, "generated")))
    output = abspath(option(args, "--output";
        default=joinpath(generated, "impacts")))
    data_root = option(args, "--data-root";
        default=get(ENV, "SEATTLE_TRANSIT_DATA_ROOT", ""))
    geography = option(args, "--geography-root";
        default=isempty(data_root) ? "" :
            joinpath(data_root, "raw", "geography"))
    isempty(geography) && throw(ArgumentError(
        "set SEATTLE_TRANSIT_DATA_ROOT or pass --geography-root"))
    metro_activity = option(args, "--metro-route-activity";
        default=isempty(data_root) ? "" :
            joinpath(data_root, "derived", "metro_route_activity_fall_2016.csv"))
    isempty(metro_activity) && throw(ArgumentError(
        "set SEATTLE_TRANSIT_DATA_ROOT or pass --metro-route-activity"))
    result = build(generated, output; geography_root=abspath(geography),
                   metro_activity_path=abspath(metro_activity),
                   plots=!("--skip-plots" in args),
                   python=String(option(args, "--python"; default="python3")))
    println(TNW.json_value(Dict(
        "status" => "ok", "manifest" => result.manifest_path)))
    return 0
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(SeattleTransitImpacts.main())
    catch error
        showerror(stderr, error)
        println(stderr)
        exit(1)
    end
end
