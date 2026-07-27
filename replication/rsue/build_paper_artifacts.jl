#!/usr/bin/env julia

using Statistics
using TOML
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

function accepted_verification(project, model)
    path = joinpath(HERE, "verification", "choice_logsum_rsue_fd.toml")
    isfile(path) || error("missing full-network choice-logsum verification report: $path")
    report = TOML.parsefile(path)
    report["verification_status"] == "accepted" ||
        error("choice-logsum verification report is not accepted")
    report["config_sha256"] == TNW.file_sha256(project.config_path) ||
        error("choice-logsum verification report has a stale configuration hash")
    Dict{String,String}(report["input_hashes"]) == model.data.input_hashes ||
        error("choice-logsum verification report has stale input hashes")
    for (relative, expected) in report["source_hashes"]
        TNW.file_sha256(joinpath(ROOT, relative)) == expected ||
            error("choice-logsum verification report has a stale source hash: $relative")
    end
    return path, report
end

function result_statistics(rows, shock_fraction)
    hulten = [row.hulten for row in rows]
    welfare = [row.primitive_F for row in rows]
    top_count = ceil(Int, 0.10length(rows))
    top = sort(welfare; rev=true)[1:top_count]
    return Dict{String,Any}(
        "shock_fraction" => shock_fraction,
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

function descending_ranks(values)
    return TNW.average_ranks(-collect(values))
end

function baseline_parameter_value(model, parameter::Symbol)
    project = model.project
    parameter == :alpha && return project.parameters.alpha
    parameter == :beta && return project.parameters.beta
    parameter == :net_dispersion &&
        return -(project.parameters.alpha+project.parameters.beta)
    parameter == :eta && return project.modal.eta
    parameter == :lambda_road &&
        return TNW.edge_lambdas(project.congestion)[:road]
    parameter == :common_congestion && return 1.0
    if parameter == :lambda_terminal
        terminal_values = collect(Base.values(
            TNW.terminal_lambdas(project.congestion)))
        isempty(terminal_values) &&
            error("terminal-congestion baseline is unavailable")
        all(isapprox(value, first(terminal_values);
                     rtol=0.0, atol=10eps(Float64))
            for value in terminal_values) ||
            error("terminal-congestion channels do not share one baseline")
        return first(terminal_values)
    end
    error("unsupported sensitivity parameter: $parameter")
end

function sensitivity_outputs(model, baseline_rows, role::String, parameters)
    summaries = NamedTuple[]
    link_rows = NamedTuple[]
    baseline_ids = [row.physical_link_id for row in baseline_rows]
    baseline_effects = [row.primitive_F for row in baseline_rows]
    baseline_ranks = descending_ranks(baseline_effects)
    for parameter in parameters
        values = model.project.sensitivity[parameter]
        baseline_value = baseline_parameter_value(model, parameter)
        for value in Float64.(values)
            project = TNW.project_at(model.project, parameter, value)
            candidate = TNW.welfare_model_at(model, project; enforce_branch=true)
            result = TNW.welfare_effects(candidate)
            result.diagnostics["verified"] || error(
                "sensitivity point $(parameter)=$(value) failed verification")
            physical = sorted_physical(result)
            [row.physical_link_id for row in physical] == baseline_ids ||
                error("sensitivity point changed the physical-link set")
            effects = [row.primitive_F for row in physical]
            ranks = descending_ranks(effects)
            rank_correlation = TNW.spearman_correlation(
                baseline_effects, effects)
            push!(summaries, (;
                model_role=role,
                parameter=String(parameter),
                value,
                mean_physical_elasticity=mean(effects),
                mean_physical_gain_pct=
                    100*project.policy.shock_fraction*mean(effects),
                spearman_vs_baseline=rank_correlation,
                minimum_physical_elasticity=minimum(effects),
                maximum_physical_elasticity=maximum(effects),
                verified=true,
            ))
            for (index, row) in enumerate(physical)
                push!(link_rows, (;
                    model_role=role,
                    parameter=String(parameter),
                    value,
                    row.physical_link_id,
                    row.endpoint_a,
                    row.endpoint_b,
                    traditional_elasticity=row.hulten,
                    extended_elasticity=row.primitive_F,
                    gain_percent=
                        100*project.policy.shock_fraction*row.primitive_F,
                    baseline_extended_elasticity=baseline_effects[index],
                    rank=ranks[index],
                    baseline_rank=baseline_ranks[index],
                    rank_change=baseline_ranks[index]-ranks[index],
                    is_baseline=isapprox(
                        value, baseline_value; rtol=0.0,
                        atol=10eps(Float64)),
                    verified=true,
                ))
            end
        end
    end
    return summaries, link_rows
end

function validate_sensitivity_panel(summaries, link_rows;
                                    expected_links::Int=352,
                                    tolerance::Float64=1.0e-12)
    groups = Dict{Tuple{String,String,Float64},Vector{NamedTuple}}()
    for row in link_rows
        key = (row.model_role, row.parameter, Float64(row.value))
        push!(get!(groups, key, NamedTuple[]), row)
    end
    maximum_mean_error = 0.0
    maximum_rank_error = 0.0
    for summary in summaries
        key = (
            summary.model_role, summary.parameter, Float64(summary.value))
        haskey(groups, key) || error("sensitivity link panel is missing $key")
        rows = groups[key]
        length(rows) == expected_links ||
            error("sensitivity group $key has $(length(rows)) links")
        effects = [row.extended_elasticity for row in rows]
        baseline = [row.baseline_extended_elasticity for row in rows]
        mean_error = abs(mean(effects)-summary.mean_physical_elasticity)
        rank_error = abs(
            TNW.spearman_correlation(baseline, effects)-
            summary.spearman_vs_baseline)
        maximum_mean_error = max(maximum_mean_error, mean_error)
        maximum_rank_error = max(maximum_rank_error, rank_error)
        mean_error <= tolerance ||
            error("sensitivity mean does not match aggregate output for $key")
        rank_error <= tolerance ||
            error("sensitivity rank correlation does not match aggregate output for $key")
    end
    length(groups) == length(summaries) ||
        error("sensitivity link panel contains unexpected groups")
    return Dict{String,Any}(
        "groups" => length(groups),
        "rows" => length(link_rows),
        "links_per_group" => expected_links,
        "maximum_mean_error" => maximum_mean_error,
        "maximum_rank_correlation_error" => maximum_rank_error,
        "verified" => true,
    )
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
        scale = 100*statistics["shock_fraction"]
        println(io, "\\providecommand{\\PaperPtenGainPercent}{", tex_number(scale*statistics["p10_elasticity"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperPninetiethGainPercent}{", tex_number(scale*statistics["p90_elasticity"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperHultenCorrelation}{", tex_number(statistics["pearson_hulten"]; digits=3), "}")
        println(io, "\\providecommand{\\PaperHultenRankCorrelation}{", tex_number(statistics["spearman_hulten"]; digits=3), "}")
        println(io, "\\providecommand{\\PaperTopDecileRatio}{", tex_number(statistics["top_decile_median_ratio"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperTopTenOverlap}{", ranking["overlap_count"], "}")
        println(io, "\\providecommand{\\PaperTopTenJaccard}{", tex_number(ranking["jaccard_index"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperTopTenTableCount}{10}")
        println(io, "\\providecommand{\\PaperTopLinkTableCount}{30}")
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
    verification_path, verification_report = accepted_verification(main_project, main_model)
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

    main_sensitivity, main_sensitivity_links = sensitivity_outputs(
        main_model, physical, "headline_edge_local",
        [:alpha, :beta, :net_dispersion, :eta, :lambda_road],
    )
    terminal_project = TNW.load_project(TERMINAL_CONFIG)
    terminal_model = TNW.build_model(terminal_project)
    terminal_baseline = sorted_physical(TNW.welfare_effects(terminal_model))
    extension_sensitivity, extension_sensitivity_links = sensitivity_outputs(
        terminal_model, terminal_baseline, "terminal_extension",
        [:common_congestion, :lambda_terminal],
    )
    all_sensitivity = vcat(main_sensitivity, extension_sensitivity)
    all_sensitivity_links = vcat(
        main_sensitivity_links, extension_sensitivity_links)
    sensitivity_link_diagnostics = validate_sensitivity_panel(
        all_sensitivity, all_sensitivity_links)

    output_dir = main_project.output_dir
    mkpath(output_dir)
    directed_path = TNW.write_table(joinpath(output_dir, "decomposition_directed.csv"), main_result.directed)
    physical_path = TNW.write_table(joinpath(output_dir, "decomposition_physical.csv"), physical)
    geometry_path = TNW.write_table(
        joinpath(output_dir, "paper_link_geometry.csv"), link_geometry(main_model, physical))
    sensitivity_path = TNW.write_table(
        joinpath(output_dir, "paper_sensitivity.csv"), all_sensitivity)
    sensitivity_links_path = TNW.write_table(
        joinpath(output_dir, "paper_sensitivity_links.csv"),
        all_sensitivity_links)
    top_ten_csv_path = joinpath(output_dir, "paper_top_10_links.csv")
    top_ten_tex_path = joinpath(output_dir, "paper_top_10_links.tex")
    top_thirty_csv_path = joinpath(output_dir, "paper_top_30_links.csv")
    top_thirty_tex_path = joinpath(output_dir, "paper_top_30_links.tex")

    statistics = result_statistics(physical, main_project.policy.shock_fraction)
    decomposition = decomposition_statistics(physical)
    ranking = top_link_comparison(physical, 10)
    appendix_ranking = top_link_comparison(physical, 30)
    census_diagnostics_source = joinpath(
        HERE, "census_ports", "derived", "2017", "census_port_region_diagnostics.json")
    census_diagnostics_path = joinpath(output_dir, "census_port_source_metadata.json")
    cp(census_diagnostics_source, census_diagnostics_path; force=true)
    claims = Dict{String,Any}(
        "schema_version" => 1,
        "specification_status" => "accepted",
        "verification_status" => verification_report["verification_status"],
        "release_status" => "restricted_data_pending",
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
        "appendix_top_link_comparison" => appendix_ranking,
        "sensitivity_link_panel" => sensitivity_link_diagnostics,
        "source_files" => Dict(
            "directed" => basename(directed_path),
            "physical" => basename(physical_path),
            "geometry" => basename(geometry_path),
            "sensitivity" => basename(sensitivity_path),
            "sensitivity_links" => basename(sensitivity_links_path),
            "top_10_links_csv" => basename(top_ten_csv_path),
            "top_10_links_tex" => basename(top_ten_tex_path),
            "top_30_links_csv" => basename(top_thirty_csv_path),
            "top_30_links_tex" => basename(top_thirty_tex_path),
            "choice_logsum_verification" => basename(verification_path),
        ),
        "choice_logsum_verification_sha256" => TNW.file_sha256(verification_path),
        "environment_locks" => Dict(
            "julia_manifest_sha256" => TNW.file_sha256(
                joinpath(HERE, "environment", "Manifest.toml")),
            "python_verification_requirements_sha256" => TNW.file_sha256(
                joinpath(ROOT, "verification", "requirements-linux.txt")),
            "python_plot_requirements_sha256" => TNW.file_sha256(
                joinpath(ROOT, "plots", "requirements.txt")),
        ),
    )
    claims_path = write_json(joinpath(output_dir, "paper_claims.json"), claims)
    tex_path = write_tex_macros(
        joinpath(output_dir, "paper_results.tex"), statistics, decomposition, ranking,
        robustness, main_result.diagnostics)

    labels_path = joinpath(output_dir, "paper_link_labels.csv")
    run(`python3 $(joinpath(HERE, "build_cbsa_crosswalk.py")) $geometry_path $claims_path $labels_path --cache-dir $(joinpath(HERE, ".public_cache")) --sensitivity-links $sensitivity_links_path --top-10-links-csv $top_ten_csv_path --top-10-links-tex $top_ten_tex_path --top-30-links-csv $top_thirty_csv_path --top-30-links-tex $top_thirty_tex_path`)

    figure_dir = joinpath(output_dir, "figures")
    run(`python3 $(joinpath(ROOT, "plots", "rsue_paper_figures.py")) $output_dir $figure_dir`)
    figure_outputs = sort!(filter(isfile, [
        joinpath(figure_dir, "$(name).$(extension)")
        for name in ("rsue_hulten_map", "rsue_ift_map", "rsue_hulten_vs_ift", "rsue_decomposition", "rsue_sensitivity")
        for extension in ("pdf", "png")
    ]))
    length(figure_outputs) == 10 || error("paper figure generation did not produce ten artifacts")
    extra_outputs = [
        geometry_path, labels_path, sensitivity_path, sensitivity_links_path,
        top_ten_csv_path, top_ten_tex_path,
        top_thirty_csv_path, top_thirty_tex_path,
        claims_path, tex_path, verification_path,
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

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main()
end
