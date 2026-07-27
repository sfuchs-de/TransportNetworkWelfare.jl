#!/usr/bin/env julia

using LinearAlgebra
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

function traffic_ranked_subset_statistics(rows, counts=(50, 100))
    ordered = sort(
        collect(rows);
        by=row -> (-row.hulten, row.physical_link_id),
    )
    output = Dict{String,Any}()
    for count in counts
        1 < count <= length(ordered) ||
            error("traffic-ranked subset size must be between 2 and $(length(ordered))")
        subset = ordered[1:count]
        hulten = [row.hulten for row in subset]
        welfare = [row.primitive_F for row in subset]
        output[string(count)] = Dict{String,Any}(
            "selection" => "descending traditional traffic statistic, then physical_link_id",
            "count" => count,
            "pearson" => cor(hulten, welfare),
            "spearman" => TNW.spearman_correlation(hulten, welfare),
        )
    end
    return output
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

function mechanism_path_rows(main_model, main_rows)
    efficient_project = TNW.replace_project(
        main_model.project; alpha=0.0, beta=0.0)
    efficient_model = TNW.model_at(main_model, efficient_project)
    efficient_result = TNW.decompose_welfare(efficient_model)
    efficient_rows = sorted_physical(efficient_result)
    [row.physical_link_id for row in efficient_rows] ==
        [row.physical_link_id for row in main_rows] ||
        error("efficient-reference and headline physical links differ")

    data, basis, closures = (
        efficient_model.data, efficient_model.basis, efficient_model.closures)
    fixed_no_congestion = TNW.build_transport_closure(
        efficient_project, data, basis, closures.B;
        route=:fixed, include_edge=false, include_terminal=false)
    fixed_jacobian = closures.J0+fixed_no_congestion.Jc
    TNW.condition_within_limit(
        cond(fixed_jacobian), efficient_project.condition_limit) ||
        error("efficient fixed-route closure exceeds the condition-number gate")
    q = TNW.AdjointRSUE.welfare_gradient(data.omega, closures.c)
    realized_forcing = closures.B*basis.Sagg[:, basis.policy_pairs]
    fixed_directed = TNW.operator_gain(
        fixed_jacobian, q, realized_forcing)
    fixed_by_link = Dict{String,Float64}()
    for (index, physical_link_id) in enumerate(basis.policy_physical_ids)
        fixed_by_link[physical_link_id] =
            get(fixed_by_link, physical_link_id, 0.0)+fixed_directed[index]
    end

    output = NamedTuple[]
    for (headline, efficient) in zip(main_rows, efficient_rows)
        traditional = headline.hulten
        fixed_route = fixed_by_link[headline.physical_link_id]
        flexible_efficient = efficient.realized_NC
        efficient_congestion = efficient.realized_F
        spatial_equilibrium = headline.realized_F
        extended = headline.primitive_F
        fixed_route_change = fixed_route-traditional
        route_mode_change = flexible_efficient-fixed_route
        congestion_change = efficient_congestion-flexible_efficient
        spatial_externality_change =
            spatial_equilibrium-efficient_congestion
        pass_through_change = extended-spatial_equilibrium
        net_change = extended-traditional
        identity_residual = net_change-sum((
            fixed_route_change, route_mode_change, congestion_change,
            spatial_externality_change, pass_through_change,
        ))
        push!(output, (;
            headline.physical_link_id,
            headline.endpoint_a,
            headline.endpoint_b,
            traditional,
            fixed_route,
            flexible_efficient,
            efficient_congestion,
            spatial_equilibrium,
            extended,
            fixed_route_change,
            route_mode_change,
            congestion_change,
            spatial_externality_change,
            pass_through_change,
            net_change,
            identity_residual,
        ))
    end

    fixed_collapse_error = maximum(abs(
        row.fixed_route-row.traditional) for row in output)
    flexible_collapse_error = maximum(abs(
        row.flexible_efficient-row.traditional) for row in output)
    identity_error = maximum(abs(row.identity_residual) for row in output)
    tolerance = main_model.project.tolerance
    fixed_collapse_error <= tolerance ||
        error("efficient fixed-route welfare does not reproduce Hulten")
    flexible_collapse_error <= tolerance ||
        error("efficient route-modal welfare does not reproduce Hulten")
    identity_error <= tolerance ||
        error("nested mechanism path does not reconstruct the extended result")
    return output, efficient_result
end

function mechanism_path_statistics(rows)
    mean_field(name) = mean(getproperty(row, name) for row in rows)
    return Dict{String,Any}(
        "mean_traditional" => mean_field(:traditional),
        "mean_fixed_route" => mean_field(:fixed_route),
        "mean_flexible_efficient" => mean_field(:flexible_efficient),
        "mean_efficient_congestion" => mean_field(:efficient_congestion),
        "mean_spatial_equilibrium" => mean_field(:spatial_equilibrium),
        "mean_extended" => mean_field(:extended),
        "mean_fixed_route_change" => mean_field(:fixed_route_change),
        "mean_route_mode_change" => mean_field(:route_mode_change),
        "mean_congestion_change" => mean_field(:congestion_change),
        "mean_spatial_externality_change" =>
            mean_field(:spatial_externality_change),
        "mean_pass_through_change" => mean_field(:pass_through_change),
        "mean_net_change" => mean_field(:net_change),
        "maximum_identity_residual" =>
            maximum(abs(row.identity_residual) for row in rows),
        "maximum_fixed_route_collapse_error" =>
            maximum(abs(row.fixed_route-row.traditional) for row in rows),
        "maximum_flexible_efficient_collapse_error" =>
            maximum(abs(row.flexible_efficient-row.traditional) for row in rows),
        "verified" => true,
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
                is_baseline=isapprox(
                    value, baseline_value; rtol=0.0,
                    atol=10eps(Float64)),
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

function modal_competition_diagnostics(model, sensitivity, sensitivity_links)
    basis = model.basis
    active_modes_per_edge = zeros(Int, basis.E)
    for edge in basis.pair_edge
        active_modes_per_edge[edge] += 1
    end
    road_shares = Float64[]
    mode_counts = Int[]
    for pair in basis.policy_pairs
        edge = basis.pair_edge[pair]
        push!(mode_counts, active_modes_per_edge[edge])
        push!(road_shares, basis.Sagg[edge, pair])
    end
    eta_summaries = filter(row -> row.parameter == "eta", sensitivity)
    eta_links = filter(row -> row.parameter == "eta", sensitivity_links)
    isempty(eta_summaries) && error("eta sensitivity summary is unavailable")
    isempty(eta_links) && error("eta link-level sensitivity is unavailable")
    return Dict{String,Any}(
        "treated_directed_road_arcs" => length(basis.policy_pairs),
        "single_active_mode_road_arcs" => count(==(1), mode_counts),
        "median_road_modal_share" => median(road_shares),
        "road_arcs_below_90_percent_modal_share" =>
            count(share -> share < 0.90, road_shares),
        "minimum_eta_rank_correlation" =>
            minimum(row.spearman_vs_baseline for row in eta_summaries),
        "maximum_absolute_eta_rank_change" =>
            maximum(abs(row.rank_change) for row in eta_links),
    )
end

function tex_number(value; digits=6)
    return string(round(value; digits))
end

function write_tex_macros(path, statistics, decomposition, mechanism, ranking,
                          robustness, diagnostics, modal_diagnostics)
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
        for (count, prefix) in ((50, "Fifty"), (100, "Hundred"))
            subset = statistics["traffic_ranked_subsets"][string(count)]
            println(io, "\\providecommand{\\PaperTop", prefix, "TrafficCorrelation}{",
                tex_number(subset["pearson"]; digits=3), "}")
            println(io, "\\providecommand{\\PaperTop", prefix, "TrafficRankCorrelation}{",
                tex_number(subset["spearman"]; digits=3), "}")
        end
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
        println(io, "\\providecommand{\\PaperEfficientCongestionMean}{", tex_number(mechanism["mean_efficient_congestion"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperSpatialEquilibriumMean}{", tex_number(mechanism["mean_spatial_equilibrium"]; digits=7), "}")
        println(io, "\\providecommand{\\PaperTraditionalMeanScaled}{", tex_number(1.0e4*mechanism["mean_traditional"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperEfficientCongestionMeanScaled}{", tex_number(1.0e4*mechanism["mean_efficient_congestion"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperSpatialEquilibriumMeanScaled}{", tex_number(1.0e4*mechanism["mean_spatial_equilibrium"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperExtendedMeanScaled}{", tex_number(1.0e4*mechanism["mean_extended"]; digits=2), "}")
        println(io, "\\providecommand{\\PaperCongestionStepPercent}{", tex_number(100*(mechanism["mean_efficient_congestion"]/mechanism["mean_flexible_efficient"]-1); digits=1), "}")
        println(io, "\\providecommand{\\PaperSpatialExternalityStepPercent}{", tex_number(100*(mechanism["mean_spatial_equilibrium"]/mechanism["mean_efficient_congestion"]-1); digits=1), "}")
        println(io, "\\providecommand{\\PaperPortMeanDifferencePercent}{", tex_number(robustness["mean_difference_percent"]; digits=4), "}")
        println(io, "\\providecommand{\\PaperPortResultCorrelation}{", tex_number(robustness["physical_link_correlation"]; digits=6), "}")
        println(io, "\\providecommand{\\PaperSingleModeRoadArcCount}{",
            modal_diagnostics["single_active_mode_road_arcs"], "}")
        println(io, "\\providecommand{\\PaperMedianRoadModalShare}{",
            tex_number(modal_diagnostics["median_road_modal_share"]; digits=3), "}")
        println(io, "\\providecommand{\\PaperLowRoadModalShareArcCount}{",
            modal_diagnostics["road_arcs_below_90_percent_modal_share"], "}")
        println(io, "\\providecommand{\\PaperEtaMinimumRankCorrelation}{",
            tex_number(modal_diagnostics["minimum_eta_rank_correlation"]; digits=6), "}")
        println(io, "\\providecommand{\\PaperEtaMaximumRankChange}{",
            Int(modal_diagnostics["maximum_absolute_eta_rank_change"]), "}")
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
    mechanism_rows, efficient_result = mechanism_path_rows(main_model, physical)
    efficient_result.diagnostics["verified"] ||
        error("efficient-reference mechanism result failed verification")
    mechanism = mechanism_path_statistics(mechanism_rows)

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
    sensitivity_link_diagnostics["expected_parameter_values"] = 35
    length(all_sensitivity) == 35 ||
        error("paper sensitivity output must contain 35 parameter values")
    extension_sensitivity_diagnostics = validate_sensitivity_panel(
        extension_sensitivity, extension_sensitivity_links)
    modal_diagnostics = modal_competition_diagnostics(
        main_model, main_sensitivity, main_sensitivity_links)

    output_dir = main_project.output_dir
    mkpath(output_dir)
    directed_path = TNW.write_table(joinpath(output_dir, "decomposition_directed.csv"), main_result.directed)
    physical_path = TNW.write_table(joinpath(output_dir, "decomposition_physical.csv"), physical)
    mechanism_path = TNW.write_table(
        joinpath(output_dir, "paper_mechanism_path_links.csv"),
        mechanism_rows)
    geometry_path = TNW.write_table(
        joinpath(output_dir, "paper_link_geometry.csv"), link_geometry(main_model, physical))
    sensitivity_path = TNW.write_table(
        joinpath(output_dir, "paper_sensitivity.csv"), all_sensitivity)
    sensitivity_links_path = TNW.write_table(
        joinpath(output_dir, "paper_sensitivity_links.csv"),
        all_sensitivity_links)
    extension_sensitivity_path = TNW.write_table(
        joinpath(output_dir, "extension_sensitivity.csv"),
        extension_sensitivity)
    extension_sensitivity_links_path = TNW.write_table(
        joinpath(output_dir, "extension_sensitivity_links.csv"),
        extension_sensitivity_links)
    top_ten_csv_path = joinpath(output_dir, "paper_top_10_links.csv")
    top_ten_tex_path = joinpath(output_dir, "paper_top_10_links.tex")
    top_thirty_csv_path = joinpath(output_dir, "paper_top_30_links.csv")
    top_thirty_tex_path = joinpath(output_dir, "paper_top_30_links.tex")

    statistics = result_statistics(physical, main_project.policy.shock_fraction)
    statistics["traffic_ranked_subsets"] =
        traffic_ranked_subset_statistics(physical)
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
        "modal_competition_diagnostics" => modal_diagnostics,
        "decomposition" => decomposition,
        "mechanism_path" => mechanism,
        "port_data_robustness" => robustness,
        "top_links" => top_links(physical),
        "top_link_comparison" => ranking,
        "appendix_top_link_comparison" => appendix_ranking,
        "sensitivity_link_panel" => sensitivity_link_diagnostics,
        "extension_sensitivity_link_panel" =>
            extension_sensitivity_diagnostics,
        "source_files" => Dict(
            "directed" => basename(directed_path),
            "physical" => basename(physical_path),
            "mechanism_path" => basename(mechanism_path),
            "geometry" => basename(geometry_path),
            "sensitivity" => basename(sensitivity_path),
            "sensitivity_links" => basename(sensitivity_links_path),
            "extension_sensitivity" => basename(extension_sensitivity_path),
            "extension_sensitivity_links" =>
                basename(extension_sensitivity_links_path),
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
        joinpath(output_dir, "paper_results.tex"), statistics, decomposition,
        mechanism, ranking, robustness, main_result.diagnostics,
        modal_diagnostics)

    labels_path = joinpath(output_dir, "paper_link_labels.csv")
    run(`python3 $(joinpath(HERE, "build_cbsa_crosswalk.py")) $geometry_path $claims_path $labels_path --cache-dir $(joinpath(HERE, ".public_cache")) --sensitivity-links $sensitivity_links_path --top-10-links-csv $top_ten_csv_path --top-10-links-tex $top_ten_tex_path --top-30-links-csv $top_thirty_csv_path --top-30-links-tex $top_thirty_tex_path`)

    figure_dir = joinpath(output_dir, "figures")
    run(`python3 $(joinpath(ROOT, "plots", "rsue_paper_figures.py")) $output_dir $figure_dir`)
    figure_outputs = sort!(filter(isfile, [
        joinpath(figure_dir, "$(name).$(extension)")
        for name in ("rsue_traffic_map", "rsue_hulten_map", "rsue_ift_map",
                     "rsue_hulten_vs_ift", "rsue_decomposition",
                     "rsue_sensitivity")
        for extension in ("pdf", "png")
    ]))
    length(figure_outputs) == 12 || error(
        "paper figure generation did not produce twelve artifacts")
    extra_outputs = [
        geometry_path, labels_path, mechanism_path,
        sensitivity_path, sensitivity_links_path,
        extension_sensitivity_path, extension_sensitivity_links_path,
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
        "mechanism_path" => mechanism,
        "top_link_comparison" => ranking,
        "port_data_robustness" => robustness,
    )))
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main()
end
