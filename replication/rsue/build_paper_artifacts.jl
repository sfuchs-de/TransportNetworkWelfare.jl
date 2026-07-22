#!/usr/bin/env julia

using Statistics
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const HERE = @__DIR__
const MAIN_CONFIG = joinpath(HERE, "rsue_paper_choice_edge_census_2017.toml")
const TERMINAL_CONFIG = joinpath(HERE, "rsue_paper_terminal_extension_census_2017.toml")
const CONTROL_CONFIG = joinpath(HERE, "rsue_paper_choice_edge_legacy_ports_control.toml")
const ROOT = normpath(joinpath(HERE, "..", ".."))

function sorted_physical(result)
    rows = collect(result.physical)
    sort!(rows; by=row -> row.physical_link_id)
    return rows
end

function write_json(path::AbstractString, value)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, TNW.json_value(value))
    end
    return path
end

function result_statistics(rows, shock_fraction)
    hulten = [row.hulten for row in rows]
    welfare = [row.primitive_F for row in rows]
    top_count = ceil(Int, 0.10length(rows))
    top = sort(welfare; rev=true)[1:top_count]
    return Dict{String,Any}(
        "mean_elasticity" => mean(welfare),
        "median_elasticity" => median(welfare),
        "minimum_elasticity" => minimum(welfare),
        "maximum_elasticity" => maximum(welfare),
        "p10_elasticity" => quantile(welfare, 0.10),
        "p25_elasticity" => quantile(welfare, 0.25),
        "p75_elasticity" => quantile(welfare, 0.75),
        "p90_elasticity" => quantile(welfare, 0.90),
        "mean_gain_percent" => 100shock_fraction*mean(welfare),
        "median_gain_percent" => 100shock_fraction*median(welfare),
        "maximum_gain_percent" => 100shock_fraction*maximum(welfare),
        "pearson_hulten" => cor(hulten, welfare),
        "spearman_hulten" => TNW.spearman_correlation(hulten, welfare),
        "top_decile_count" => top_count,
        "top_decile_median_ratio" => median(top)/median(welfare),
        "top_decile_mean_ratio" => mean(top)/mean(welfare),
    )
end

function decomposition_statistics(rows)
    mean_field(name) = mean(getproperty(row, name) for row in rows)
    hulten = mean_field(:hulten)
    realized_nc = mean_field(:realized_NC)
    realized_f = mean_field(:realized_F)
    realized_fm = mean_field(:realized_FM)
    realized_fr = mean_field(:realized_FR)
    primitive_f = mean_field(:primitive_F)
    return Dict{String,Any}(
        "mean_hulten" => hulten,
        "mean_realized_no_congestion" => realized_nc,
        "mean_realized_full" => realized_f,
        "mean_realized_fixed_modes" => realized_fm,
        "mean_realized_fixed_routes" => realized_fr,
        "mean_primitive_full" => primitive_f,
        "road_congestion_change_percent" => 100*(realized_f/realized_nc-1),
        "fixed_modes_change_percent" => 100*(realized_fm/realized_f-1),
        "fixed_routes_change_percent" => 100*(realized_fr/realized_f-1),
        "primitive_to_realized_percent" => 100*primitive_f/realized_f,
        "primitive_to_hulten_percent" => 100*primitive_f/hulten,
        "mean_externality_component" => mean_field(:primitive_externality),
        "mean_propagation_component" => mean_field(:primitive_propagation),
        "mean_road_component" => mean_field(:primitive_edge),
        "mean_terminal_component" => mean_field(:primitive_terminal),
        "mean_pass_through_component" => mean_field(:primitive_pass_through),
        "mean_hulten_gap" => hulten-primitive_f,
    )
end

function link_geometry(model, rows)
    data = model.data
    output = NamedTuple[]
    for row in rows
        a = data.node_index[row.endpoint_a]
        b = data.node_index[row.endpoint_b]
        push!(output, (;
            row.physical_link_id, row.endpoint_a, row.endpoint_b,
            longitude_a=data.longitude[a], latitude_a=data.latitude[a],
            longitude_b=data.longitude[b], latitude_b=data.latitude[b],
            row.hulten, row.primitive_F,
        ))
    end
    return output
end

function top_links(rows, count::Int=20)
    ordered = sort(rows; by=row -> row.primitive_F, rev=true)
    return [Dict{String,Any}(
        "rank" => rank,
        "physical_link_id" => row.physical_link_id,
        "endpoint_a" => row.endpoint_a,
        "endpoint_b" => row.endpoint_b,
        "primitive_elasticity" => row.primitive_F,
        "hulten_elasticity" => row.hulten,
    ) for (rank, row) in enumerate(ordered[1:min(count, length(ordered))])]
end

function top_link_comparison(rows, count::Int=10)
    traditional = sort(rows; by=row -> (-row.hulten, row.physical_link_id))
    extended = sort(rows; by=row -> (-row.primitive_F, row.physical_link_id))
    traditional_rank = Dict(row.physical_link_id => rank for (rank, row) in enumerate(traditional))
    extended_rank = Dict(row.physical_link_id => rank for (rank, row) in enumerate(extended))

    function entries(ordered)
        return [Dict{String,Any}(
            "rank" => rank,
            "physical_link_id" => row.physical_link_id,
            "endpoint_a" => row.endpoint_a,
            "endpoint_b" => row.endpoint_b,
            "traditional_rank" => traditional_rank[row.physical_link_id],
            "extended_rank" => extended_rank[row.physical_link_id],
            "hulten_elasticity" => row.hulten,
            "primitive_elasticity" => row.primitive_F,
        ) for (rank, row) in enumerate(ordered[1:min(count, length(ordered))])]
    end

    traditional_ids = Set(row.physical_link_id for row in traditional[1:min(count, length(traditional))])
    extended_ids = Set(row.physical_link_id for row in extended[1:min(count, length(extended))])
    overlap = intersect(traditional_ids, extended_ids)
    combined = union(traditional_ids, extended_ids)
    return Dict{String,Any}(
        "count_per_measure" => min(count, length(rows)),
        "overlap_count" => length(overlap),
        "union_count" => length(combined),
        "jaccard_index" => length(overlap)/length(combined),
        "traditional" => entries(traditional),
        "extended" => entries(extended),
    )
end

function sensitivity_rows(model, role::String, parameters)
    output = NamedTuple[]
    for parameter in parameters
        values = model.project.sensitivity[parameter]
        rows = TNW.sensitivity_rank_path(model, parameter, values)
        append!(output, [(; model_role=role, row...) for row in rows])
    end
    return output
end

function tex_number(value; digits=6)
    return string(round(value; digits))
end

function write_tex_macros(path, statistics, decomposition, ranking, robustness, diagnostics)
    open(path, "w") do io
        println(io, "% Generated by replication/rsue/build_paper_artifacts.jl; do not edit.")
        println(io, "\\providecommand{\\PaperNodeCount}{", diagnostics["nodes"], "}")
        println(io, "\\providecommand{\\PaperDomesticNodeCount}{228}")
        println(io, "\\providecommand{\\PaperForeignRegionCount}{6}")
        println(io, "\\providecommand{\\PaperDirectedRoadArcCount}{", diagnostics["directed_policy_arcs"], "}")
        println(io, "\\providecommand{\\PaperPhysicalRoadLinkCount}{352}")
        println(io, "\\providecommand{\\PaperMeanGainPercent}{", tex_number(statistics["mean_gain_percent"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperMedianGainPercent}{", tex_number(statistics["median_gain_percent"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperMaximumGainPercent}{", tex_number(statistics["maximum_gain_percent"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperPtenGainPercent}{", tex_number(statistics["p10_elasticity"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperPninetiethGainPercent}{", tex_number(statistics["p90_elasticity"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperHultenCorrelation}{", tex_number(statistics["pearson_hulten"]; digits=3), "}")
        println(io, "\\providecommand{\\PaperHultenRankCorrelation}{", tex_number(statistics["spearman_hulten"]; digits=3), "}")
        println(io, "\\providecommand{\\PaperTopDecileRatio}{", tex_number(statistics["top_decile_median_ratio"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperTopTenOverlap}{", ranking["overlap_count"], "}")
        println(io, "\\providecommand{\\PaperTopTenJaccard}{", tex_number(ranking["jaccard_index"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperRoadCongestionChangePercent}{", tex_number(decomposition["road_congestion_change_percent"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperFixedModesChangePercent}{", tex_number(decomposition["fixed_modes_change_percent"]; digits=3), "}")
        println(io, "\\providecommand{\\PaperFixedRoutesChangePercent}{", tex_number(decomposition["fixed_routes_change_percent"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperPrimitiveToRealizedPercent}{", tex_number(decomposition["primitive_to_realized_percent"]; digits=1), "}")
        println(io, "\\providecommand{\\PaperPrimitiveToHultenPercent}{", tex_number(decomposition["primitive_to_hulten_percent"]; digits=1), "}")
        println(io, "\\providecommand{\\PaperPortMeanDifferencePercent}{", tex_number(robustness["mean_difference_percent"]; digits=4), "}")
        println(io, "\\providecommand{\\PaperPortResultCorrelation}{", tex_number(robustness["physical_link_correlation"]; digits=6), "}")
    end
    return path
end

function main()
    main_project = TNW.load_project(MAIN_CONFIG)
    main_model = TNW.build_model(main_project)
    main_result = TNW.decompose_welfare(main_model)
    main_result.diagnostics["verified"] || error("headline result failed verification")
    physical = sorted_physical(main_result)
    length(main_result.directed) == 704 || error("expected 704 directed road arcs")
    length(physical) == 352 || error("expected 352 physical road links")

    control_project = TNW.load_project(CONTROL_CONFIG)
    control_model = TNW.build_model(control_project)
    control_result = TNW.decompose_welfare(control_model)
    control = sorted_physical(control_result)
    [row.physical_link_id for row in physical] == [row.physical_link_id for row in control] ||
        error("headline and port-control physical links differ")
    headline_values = [row.primitive_F for row in physical]
    control_values = [row.primitive_F for row in control]
    robustness = Dict{String,Any}(
        "control" => "choice-logsum edge-local model with legacy symmetrized port flows",
        "mean_difference_percent" => 100*(mean(headline_values)/mean(control_values)-1),
        "median_difference_percent" => 100*(median(headline_values)/median(control_values)-1),
        "physical_link_correlation" => cor(headline_values, control_values),
        "physical_link_rank_correlation" => TNW.spearman_correlation(headline_values, control_values),
    )

    main_sensitivity = sensitivity_rows(
        main_model, "headline_edge_local",
        [:alpha, :beta, :net_dispersion, :eta, :lambda_road],
    )
    terminal_project = TNW.load_project(TERMINAL_CONFIG)
    terminal_model = TNW.build_model(terminal_project)
    extension_sensitivity = sensitivity_rows(
        terminal_model, "terminal_extension",
        [:common_congestion, :lambda_terminal],
    )
    all_sensitivity = vcat(main_sensitivity, extension_sensitivity)

    output_dir = main_project.output_dir
    mkpath(output_dir)
    directed_path = TNW.write_table(joinpath(output_dir, "decomposition_directed.csv"), main_result.directed)
    physical_path = TNW.write_table(joinpath(output_dir, "decomposition_physical.csv"), physical)
    geometry_path = TNW.write_table(
        joinpath(output_dir, "paper_link_geometry.csv"), link_geometry(main_model, physical))
    sensitivity_path = TNW.write_table(
        joinpath(output_dir, "paper_sensitivity.csv"), all_sensitivity)
    top_links_csv_path = joinpath(output_dir, "paper_top_links.csv")
    top_links_tex_path = joinpath(output_dir, "paper_top_links.tex")

    statistics = result_statistics(physical, main_project.policy.shock_fraction)
    decomposition = decomposition_statistics(physical)
    ranking = top_link_comparison(physical)
    census_diagnostics_source = joinpath(
        HERE, "census_ports", "derived", "2017", "census_port_region_diagnostics.json")
    census_diagnostics_path = joinpath(output_dir, "census_port_source_metadata.json")
    cp(census_diagnostics_source, census_diagnostics_path; force=true)
    claims = Dict{String,Any}(
        "schema_version" => 1,
        "status" => "accepted",
        "policy" => Dict(
            "unit" => "bidirectional_physical_link",
            "shock" => "simultaneous one-percent primitive road-cost reduction in both directions",
            "directed_arcs" => length(main_result.directed),
            "physical_links" => length(physical),
        ),
        "network" => Dict(
            "nodes" => main_model.data.N,
            "domestic_nodes" => 228,
            "foreign_regions" => 6,
            "international_flows" => "directional 2017 Census containerized vessel trade, balanced to common margins",
            "census_overlay_sha256" => main_project.input["census_port_overlay_sha256"],
            "census_source_metadata" => basename(census_diagnostics_path),
        ),
        "model" => Dict(
            "modal" => "choice_logsum",
            "eta" => main_project.modal.eta,
            "congestion" => "edge_local_road",
            "lambda_road" => TNW.edge_lambdas(main_project.congestion)[:road],
            "terminal_congestion" => "extension_only",
        ),
        "results" => statistics,
        "decomposition" => decomposition,
        "port_data_robustness" => robustness,
        "top_links" => top_links(physical),
        "top_link_comparison" => ranking,
        "source_files" => Dict(
            "directed" => basename(directed_path),
            "physical" => basename(physical_path),
            "geometry" => basename(geometry_path),
            "sensitivity" => basename(sensitivity_path),
            "top_link_comparison_csv" => basename(top_links_csv_path),
            "top_link_comparison_tex" => basename(top_links_tex_path),
        ),
    )
    claims_path = write_json(joinpath(output_dir, "paper_claims.json"), claims)
    tex_path = write_tex_macros(
        joinpath(output_dir, "paper_results.tex"), statistics, decomposition, ranking,
        robustness, main_result.diagnostics)

    labels_path = joinpath(output_dir, "paper_link_labels.csv")
    run(`python3 $(joinpath(HERE, "build_cbsa_crosswalk.py")) $geometry_path $claims_path $labels_path --cache-dir $(joinpath(HERE, ".public_cache")) --top-links-csv $top_links_csv_path --top-links-tex $top_links_tex_path`)

    figure_dir = joinpath(output_dir, "figures")
    run(`python3 $(joinpath(ROOT, "plots", "rsue_paper_figures.py")) $output_dir $figure_dir`)
    figure_outputs = sort!(filter(isfile, [
        joinpath(figure_dir, "$(name).$(extension)")
        for name in ("rsue_hulten_map", "rsue_ift_map", "rsue_hulten_vs_ift", "rsue_decomposition", "rsue_sensitivity")
        for extension in ("pdf", "png")
    ]))
    length(figure_outputs) == 10 || error("paper figure generation did not produce ten artifacts")
    extra_outputs = [
        geometry_path, labels_path, top_links_csv_path, top_links_tex_path,
        sensitivity_path, claims_path, tex_path,
        census_diagnostics_path,
        figure_outputs...,
    ]
    paths = TNW.write_results(
        main_result, output_dir; project=main_project,
        command="paper-artifacts $(basename(MAIN_CONFIG))", extra_outputs,
    )
    println(TNW.json_value(Dict(
        "status" => "ok",
        "outputs" => paths,
        "statistics" => statistics,
        "decomposition" => decomposition,
        "top_link_comparison" => ranking,
        "port_data_robustness" => robustness,
    )))
end

main()
