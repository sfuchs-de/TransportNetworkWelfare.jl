#!/usr/bin/env julia

using Printf
using SHA
using Statistics
using TOML
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, ".."))
const GRID_CONFIG = joinpath(ROOT, "examples", "grid_multimodal", "config.toml")
const DEFAULT_OUTPUT = joinpath(ROOT, "docs", "practitioner-guide", "generated")
const EXTERNAL_ASSET_FILES = Set(["external-example-results.tex"])
const RSUE_ROOT = joinpath(
    ROOT, "replication", "rsue", "output", "rsue_paper_choice_edge_census_2017")
const RSUE_EXPECTED = joinpath(ROOT, "replication", "rsue", "expected_summary.toml")
const RSUE_PUBLIC_CLAIMS = joinpath(ROOT, "replication", "rsue", "public_claims.toml")
const GUIDE_EXAMPLES = [
    (
        stem="grid",
        label="Multimodal grid (EG)",
        config=joinpath(ROOT, "examples", "grid_multimodal", "config.toml"),
    ),
    (
        stem="braess",
        label="Braess-style routes (EG)",
        config=joinpath(ROOT, "examples", "braess", "config.toml"),
    ),
    (
        stem="cow",
        label="Cow network (EG)",
        config=joinpath(ROOT, "examples", "cow", "config.toml"),
    ),
    (
        stem="urban",
        label="Multimodal urban (U)",
        config=joinpath(ROOT, "examples", "urban_multimodal", "config.toml"),
    ),
]

file_sha256(path) = bytes2hex(open(SHA.sha256, path))
tex_escape(value) = replace(string(value), "_" => "\\_", "&" => "\\&", "%" => "\\%")
sfmt(format, values...) = Printf.format(Printf.Format(format), values...)
fmt(value; digits=6) = sfmt("%.*f", digits, value)

function tex_scientific(value; digits=2)
    value == 0 && return "0"
    exponent = floor(Int, log10(abs(value)))
    coefficient = value / 10.0^exponent
    return sfmt("%.*f", digits, coefficient) * "\\times 10^{" *
           string(exponent) * "}"
end

function rank_map(rows, field)
    ordered = sort(rows; by=row -> (-getproperty(row, field), row.physical_link_id))
    return Dict(row.physical_link_id => rank for (rank, row) in enumerate(ordered))
end

function physical_label(identifier)
    matched = match(r"^([HV])_r(\d+)_c(\d+)$", identifier)
    matched === nothing && return tex_escape(identifier)
    kind, row, column = matched.captures
    if kind == "H"
        return "Row $row, columns $column--$(parse(Int, column) + 1)"
    end
    return "Column $column, rows $row--$(parse(Int, row) + 1)"
end

function standalone_header(io)
    println(io, "\\documentclass[tikz,border=4pt]{standalone}")
    println(io, "\\pdfinfoomitdate=1")
    println(io, "\\pdftrailerid{}")
    println(io, "\\pdfsuppressptexinfo=-1")
    println(io, "\\usepackage{pgfplots}")
    println(io, "\\usepgfplotslibrary{groupplots}")
    println(io, "\\usetikzlibrary{arrows.meta,calc}")
    println(io, "\\pgfplotsset{compat=1.18}")
    println(io, "\\definecolor{guideblue}{RGB}{30,113,164}")
    println(io, "\\definecolor{guideteal}{RGB}{42,157,143}")
    println(io, "\\definecolor{guideorange}{RGB}{202,104,42}")
    println(io, "\\definecolor{guidegold}{RGB}{225,174,51}")
    println(io, "\\definecolor{guidegray}{RGB}{103,112,119}")
    println(io, "\\begin{document}")
end

standalone_footer(io) = println(io, "\\end{document}")

function node_coordinates(model)
    return Dict(
        model.data.node_ids[i] => (
            Float64(model.data.longitude[i]), Float64(model.data.latitude[i]),
            model.data.nu[i],
        )
        for i in eachindex(model.data.node_ids)
    )
end

function physical_edges(rows)
    return sort([
        (row.physical_link_id, row.endpoint_a, row.endpoint_b)
        for row in rows
    ]; by=first)
end

function write_example_visual_data(root, spec, model, result)
    data = model.data
    any(ismissing, data.longitude) &&
        error("guide example $(spec.label) has missing longitude values")
    any(ismissing, data.latitude) &&
        error("guide example $(spec.label) has missing latitude values")
    directory = joinpath(root, "example-assets", spec.stem)
    mkpath(directory)

    terminal_nodes = Set{String}()
    for ((edge_index, _), _) in data.pair_origin_terminal
        origin, _ = data.edges[edge_index]
        push!(terminal_nodes, data.node_ids[origin])
    end
    for ((edge_index, _), _) in data.pair_destination_terminal
        _, destination = data.edges[edge_index]
        push!(terminal_nodes, data.node_ids[destination])
    end
    open(joinpath(directory, "nodes.csv"), "w") do io
        println(io, "node_id,x,y,activity,terminal")
        for index in eachindex(data.node_ids)
            activity = 0.5 * (data.omega[index] + data.nu[index])
            println(io, join((
                data.node_ids[index],
                sfmt("%.17g", Float64(data.longitude[index])),
                sfmt("%.17g", Float64(data.latitude[index])),
                sfmt("%.17g", activity),
                lowercase(string(data.node_ids[index] in terminal_nodes)),
            ), ","))
        end
    end

    modes_by_link = Dict{String,Set{String}}()
    for (edge_index, edge) in enumerate(data.edges)
        link = data.physical_link_ids[edge_index]
        for (mode_index, mode) in enumerate(data.modes)
            data.mode_flows[mode_index][edge...] > 0 || continue
            push!(get!(modes_by_link, link, Set{String}()), String(mode))
        end
    end
    open(joinpath(directory, "links.csv"), "w") do io
        println(io,
            "physical_link_id,endpoint_a,endpoint_b,hulten,primitive_F,modes")
        for row in sort(result.physical; by=row -> row.physical_link_id)
            modes = join(sort!(collect(modes_by_link[row.physical_link_id])), "|")
            println(io, join((
                row.physical_link_id,
                row.endpoint_a,
                row.endpoint_b,
                sfmt("%.17g", row.hulten),
                sfmt("%.17g", row.primitive_F),
                modes,
            ), ","))
        end
    end
end

function generated_files(root; exclude=Set{String}())
    files = String[]
    for (directory, _, names) in walkdir(root)
        for name in names
            relative = relpath(joinpath(directory, name), root)
            relative in exclude || push!(files, relative)
        end
    end
    return sort!(files)
end

function csv_values_match(generated, committed; rtol=1e-12, atol=1e-14)
    generated_lines = readlines(generated)
    committed_lines = readlines(committed)
    length(generated_lines) == length(committed_lines) || return false
    for (generated_line, committed_line) in zip(generated_lines, committed_lines)
        generated_cells = split(generated_line, ",")
        committed_cells = split(committed_line, ",")
        length(generated_cells) == length(committed_cells) || return false
        for (generated_cell, committed_cell) in zip(generated_cells, committed_cells)
            generated_cell == committed_cell && continue
            generated_value = tryparse(Float64, generated_cell)
            committed_value = tryparse(Float64, committed_cell)
            generated_value === nothing && return false
            committed_value === nothing && return false
            isapprox(generated_value, committed_value; rtol=rtol, atol=atol) ||
                return false
        end
    end
    return true
end

function tex_scientific_value(value)
    parsed = tryparse(Float64, value)
    parsed !== nothing && return parsed
    matched = match(
        r"^([+-]?[0-9]+(?:\.[0-9]+)?)\\times 10\^\{([+-]?[0-9]+)\}$",
        value,
    )
    matched === nothing && return nothing
    return parse(Float64, matched.captures[1]) *
           10.0^parse(Int, matched.captures[2])
end

function grid_results_match(generated, committed; diagnostic_tolerance=1e-10)
    generated_lines = readlines(generated)
    committed_lines = readlines(committed)
    length(generated_lines) == length(committed_lines) || return false
    diagnostic_names = Set([
        "GridInverseGapError",
        "GridLadderError",
        "GridChannelError",
    ])
    macro_pattern = r"^\\providecommand\{\\([^}]+)\}\{(.+)\}$"
    for (generated_line, committed_line) in zip(generated_lines, committed_lines)
        generated_line == committed_line && continue
        generated_macro = match(macro_pattern, generated_line)
        committed_macro = match(macro_pattern, committed_line)
        generated_macro === nothing && return false
        committed_macro === nothing && return false
        generated_macro.captures[1] == committed_macro.captures[1] || return false
        generated_macro.captures[1] in diagnostic_names || return false
        generated_value = tex_scientific_value(generated_macro.captures[2])
        committed_value = tex_scientific_value(committed_macro.captures[2])
        generated_value === nothing && return false
        committed_value === nothing && return false
        abs(generated_value) <= diagnostic_tolerance || return false
        abs(committed_value) <= diagnostic_tolerance || return false
    end
    return true
end

function generated_asset_matches(file, generated, committed)
    if startswith(file, "example-assets/") && endswith(file, ".csv")
        return csv_values_match(generated, committed)
    elseif file == "grid-results.tex"
        return grid_results_match(generated, committed)
    end
    return read(generated) == read(committed)
end

function transit_links(model)
    mode_index = findfirst(==(:transit), model.data.modes)
    mode_index === nothing && return Set{String}()
    links = Set{String}()
    for (edge_index, (origin, destination)) in enumerate(model.data.edges)
        model.data.mode_flows[mode_index][origin, destination] > 0 || continue
        push!(links, model.data.physical_link_ids[edge_index])
    end
    return links
end

function transit_nodes(model)
    links = transit_links(model)
    stations = Set{String}()
    for (edge_index, (origin, destination)) in enumerate(model.data.edges)
        model.data.physical_link_ids[edge_index] in links || continue
        push!(stations, model.data.node_ids[origin])
        push!(stations, model.data.node_ids[destination])
    end
    return stations
end

function write_network_figure(path, model, rows)
    coordinates = node_coordinates(model)
    transit = transit_links(model)
    stations = transit_nodes(model)
    open(path, "w") do io
        standalone_header(io)
        println(io, "\\begin{tikzpicture}[x=1.08cm,y=1.08cm]")
        for (link, a, b) in physical_edges(rows)
            xa, ya, _ = coordinates[a]
            xb, yb, _ = coordinates[b]
            println(io, sfmt(
                "\\draw[guidegray!48,line width=0.85pt,line cap=round] " *
                "(%.3f,%.3f)--(%.3f,%.3f);",
                xa, ya, xb, yb))
            if link in transit
                println(io, sfmt(
                    "\\draw[white,line width=4.2pt,line cap=round] " *
                    "(%.3f,%.3f)--(%.3f,%.3f);", xa, ya, xb, yb))
                println(io, sfmt(
                    "\\draw[guideblue,line width=2.5pt,line cap=round] " *
                    "(%.3f,%.3f)--(%.3f,%.3f);", xa, ya, xb, yb))
            end
        end
        maximum_income = maximum(last(coordinates[id]) for id in keys(coordinates))
        for id in sort!(collect(keys(coordinates)))
            x, y, income = coordinates[id]
            radius = 0.055 + 0.115 * sqrt(income / maximum_income)
            if id in stations
                println(io, sfmt(
                    "\\fill[white] (%.3f,%.3f) circle (%.4fcm);",
                    x, y, radius + 0.045))
                println(io, sfmt(
                    "\\draw[guideblue,line width=1.0pt] " *
                    "(%.3f,%.3f) circle (%.4fcm);",
                    x, y, radius + 0.035))
            end
            println(io, sfmt(
                "\\filldraw[fill=guidegold!72,draw=black!68,line width=0.45pt] " *
                "(%.3f,%.3f) circle (%.4fcm);", x, y, radius))
        end
        println(io,
            "\\draw[guidegray!70,line width=0.8pt] (5.0,4.0)--(5.32,4.35);")
        println(io,
            "\\node[anchor=west,font=\\small,text=guidegray] at (5.36,4.35) " *
            "{road link};")
        println(io,
            "\\draw[guideblue,line width=1.1pt] (5.0,3.0)--(5.32,3.35);")
        println(io,
            "\\node[anchor=west,font=\\small,text=guideblue] at (5.36,3.35) " *
            "{transit spine};")
        println(io,
            "\\draw[guideorange!85,line width=0.8pt] (3.0,3.0)--(3.42,2.60);")
        println(io,
            "\\node[anchor=west,font=\\small,text=guideorange!90!black] " *
            "at (3.46,2.60) {economic activity};")
        println(io,
            "\\node[anchor=north,font=\\scriptsize,text=guideblue] at " *
            "(1.0,2.77) {terminal};")
        println(io, "\\end{tikzpicture}")
        standalone_footer(io)
    end
end

function write_decomposition(path, rows, components)
    closures = [
        ("Traditional approach", mean(row.hulten for row in rows)),
        ("No congestion", mean(row.realized_NC for row in rows)),
        ("Road congestion", mean(row.realized_NT for row in rows)),
        ("Full realized-cost effect", mean(row.realized_F for row in rows)),
        ("Extended approach", mean(row.primitive_F for row in rows)),
    ]
    net_gap = sum(last, components)
    direct_gap = closures[1][2] - closures[end][2]
    abs(net_gap - direct_gap) <= 1e-10 ||
        error("grid decomposition components do not reconstruct the mean welfare gap")
    ordered_components = [
        components[5],
        components[4],
        components[3],
        components[2],
        components[1],
        ("Net gap", net_gap),
    ]
    open(path, "w") do io
        standalone_header(io)
        println(io, "\\begin{tikzpicture}")
        println(io,
            "\\begin{axis}[name=ladder,width=7.2cm,height=7.0cm," *
            "at={(0cm,0cm)},anchor=south west," *
            "xmin=0.004,xmax=0.0132,ymin=0.5,ymax=5.5," *
            "ytick={1,2,3,4,5}," *
            "yticklabels={Extended approach,Full realized-cost effect," *
            "Road congestion,No congestion,Traditional approach}," *
            "axis lines=left,axis line style={black!60}," *
            "xmajorgrids=true,grid style={black!8}," *
            "xlabel={Mean welfare elasticity}," *
            "tick label style={font=\\small},label style={font=\\small}," *
            "scaled ticks=false,xticklabel style={/pgf/number format/fixed," *
            "/pgf/number format/precision=3},clip=false]")
        println(io, "\\addplot[guidegray!70,line width=0.8pt] coordinates {")
        for (index, (_, value)) in enumerate(closures)
            println(io, sfmt("(%.12f,%d)", value, 6 - index))
        end
        println(io, "};")
        println(io,
            "\\addplot[only marks,mark=*,mark size=2.8pt,draw=white," *
            "line width=0.45pt,fill=guideteal] coordinates {")
        for (index, (_, value)) in enumerate(closures[2:4])
            println(io, sfmt("(%.12f,%d)", value, 5 - index))
        end
        println(io, "};")
        println(io, sfmt(
            "\\addplot[only marks,mark=*,mark size=3.2pt,draw=white," *
            "line width=0.5pt,fill=black!68] coordinates {(%.12f,5)};",
            closures[1][2]))
        println(io, sfmt(
            "\\addplot[only marks,mark=*,mark size=3.2pt,draw=white," *
            "line width=0.5pt,fill=guideblue] coordinates {(%.12f,1)};",
            closures[end][2]))
        println(io, sfmt(
            "\\addplot[only marks,mark=square*,mark size=2.3pt," *
            "draw=guideorange,fill=white] coordinates {(%.12f,2.22)};",
            mean(row.realized_FM for row in rows)))
        println(io, sfmt(
            "\\addplot[only marks,mark=triangle*,mark size=2.6pt," *
            "draw=guideorange,fill=white] coordinates {(%.12f,1.78)};",
            mean(row.realized_FR for row in rows)))
        println(io, sfmt(
            "\\node[anchor=east,font=\\scriptsize\\bfseries,text=guideorange] at " *
            "(axis cs:%.12f,2.22) [xshift=-5pt] {FM};",
            mean(row.realized_FM for row in rows)))
        println(io, sfmt(
            "\\node[anchor=east,font=\\scriptsize\\bfseries,text=guideorange] at " *
            "(axis cs:%.12f,1.78) [xshift=-5pt] {FR};",
            mean(row.realized_FR for row in rows)))
        println(io,
            "\\node[anchor=south west,font=\\small\\bfseries] at " *
            "(rel axis cs:0,1.03) {(a)};")
        println(io, "\\end{axis}")

        println(io,
            "\\begin{axis}[width=8.5cm,height=7.0cm," *
            "at={(8.3cm,0cm)},anchor=south west," *
            "xmin=-0.0315,xmax=0.0315,ymin=0.5,ymax=6.5," *
            "ytick={1,2,3,4,5,6}," *
            "yticklabels={Net gap,Pass-through,Terminal congestion," *
            "Road congestion,GE propagation,Externalities}," *
            "axis lines=left,axis line style={black!60}," *
            "xmajorgrids=true,grid style={black!8}," *
            "xlabel={Traditional approach \$-\$ Extended approach}," *
            "tick label style={font=\\small},label style={font=\\small}," *
            "scaled ticks=false,xticklabel style={/pgf/number format/fixed," *
            "/pgf/number format/precision=2},clip=false]")
        println(io,
            "\\draw[black!50,line width=0.7pt] " *
            "(axis cs:0,0.5)--(axis cs:0,6.5);")
        for (index, (_, value)) in enumerate(ordered_components)
            y = 7 - index
            is_net = index == length(ordered_components)
            color = is_net ? "black!72" : (value >= 0 ? "guideblue" : "guideorange")
            mark = is_net ? "diamond*" : "circle*"
            println(io, sfmt(
                "\\draw[%s,line width=1.35pt] " *
                "(axis cs:0,%d)--(axis cs:%.12f,%d);",
                color, y, value, y))
            println(io, sfmt(
                "\\addplot[only marks,mark=%s,mark size=2.6pt," *
                "draw=white,line width=0.35pt,fill=%s] " *
                "coordinates {(%.12f,%d)};",
                mark, color, value, y))
            println(io, sfmt(
                "\\node[anchor=west,font=\\scriptsize,text=%s,fill=white," *
                "inner sep=1pt] at " *
                "(axis cs:%.12f,%d) [xshift=4pt] {%.5f};",
                color, value, y, value))
        end
        println(io,
            "\\node[anchor=south west,font=\\small\\bfseries] at " *
            "(rel axis cs:0,1.03) {(b)};")
        println(io, "\\end{axis}")
        println(io, "\\end{tikzpicture}")
        standalone_footer(io)
    end
end

function write_grid_macros(path, model, result, pearson, spearman,
                           hulten_ranks, extended_ranks, rise, fall, components,
                           validation)
    rows = result.physical
    top = first(sort(rows; by=row -> (-row.primitive_F, row.physical_link_id)))
    open(path, "w") do io
        println(io, "% Generated by scripts/build_practitioner_guide_assets.jl; do not edit.")
        mean_extended = mean(row.primitive_F for row in rows)
        shock_fraction = model.project.policy.shock_fraction
        pairs = [
            "GridNodeCount" => string(model.data.N),
            "GridDirectedRoadArcCount" => string(length(result.directed)),
            "GridPhysicalRoadLinkCount" => string(length(rows)),
            "GridActiveEdgeModeCount" => string(model.basis.P),
            "GridDecompositionIncidenceGiB" =>
                fmt(validation.decomposition_incidence_gib; digits=6),
            "GridMeanTraditional" => fmt(mean(row.hulten for row in rows)),
            "GridMeanRealizedNC" => fmt(mean(row.realized_NC for row in rows)),
            "GridMeanRealizedNT" => fmt(mean(row.realized_NT for row in rows)),
            "GridMeanRealizedF" => fmt(mean(row.realized_F for row in rows)),
            "GridMeanRealizedFM" => fmt(mean(row.realized_FM for row in rows)),
            "GridMeanRealizedFR" => fmt(mean(row.realized_FR for row in rows)),
            "GridMeanExtended" => fmt(mean_extended),
            "GridPolicyShockPercent" => fmt(100*shock_fraction; digits=1),
            "GridMeanExtendedLogGain" => fmt(shock_fraction*mean_extended; digits=8),
            "GridMeanExtendedPercentGain" => fmt(
                100*shock_fraction*mean_extended; digits=6),
            "GridMedianExtended" => fmt(median(row.primitive_F for row in rows)),
            "GridMaximumExtended" => fmt(maximum(row.primitive_F for row in rows)),
            "GridTopLink" => physical_label(top.physical_link_id),
            "GridTopLinkCode" => tex_escape(top.physical_link_id),
            "GridTopTraditional" => fmt(top.hulten),
            "GridTopRealized" => fmt(top.realized_F),
            "GridTopPrimitive" => fmt(top.primitive_F),
            "GridTopPrimitiveLogGain" =>
                fmt(shock_fraction*top.primitive_F; digits=8),
            "GridTopPrimitivePercentGain" =>
                fmt(100*shock_fraction*top.primitive_F; digits=6),
            "GridMeanModeWedge" => fmt(mean(row.d_mode for row in rows)),
            "GridMeanRouteWedge" => fmt(mean(row.d_route for row in rows)),
            "GridPearson" => fmt(pearson; digits=3),
            "GridSpearman" => fmt(spearman; digits=3),
            "GridRouteSpectralRadius" => fmt(result.diagnostics["route_spectral_radius"]; digits=3),
            "GridConditionF" => tex_scientific(result.diagnostics["condition_F"]; digits=2),
            "GridInverseGapError" => tex_scientific(result.diagnostics["max_inverse_gap_error"]),
            "GridLadderError" => tex_scientific(result.diagnostics["max_ladder_error"]),
            "GridChannelError" => tex_scientific(
                result.diagnostics["max_channel_reconstruction_error"]),
            "GridRiseLink" => tex_escape(rise.physical_link_id),
            "GridRiseTraditionalRank" => string(hulten_ranks[rise.physical_link_id]),
            "GridRiseExtendedRank" => string(extended_ranks[rise.physical_link_id]),
            "GridFallLink" => tex_escape(fall.physical_link_id),
            "GridFallTraditionalRank" => string(hulten_ranks[fall.physical_link_id]),
            "GridFallExtendedRank" => string(extended_ranks[fall.physical_link_id]),
            "GridExternalityComponent" => fmt(components[5][2]),
            "GridPropagationComponent" => fmt(components[4][2]),
            "GridRoadComponent" => fmt(components[3][2]),
            "GridTerminalComponent" => fmt(components[2][2]),
            "GridPassThroughComponent" => fmt(components[1][2]),
        ]
        for (name, value) in pairs
            println(io, "\\providecommand{\\", name, "}{", value, "}")
        end
    end
end

function summarize_example(spec, model, result)
    get(result.diagnostics, "verified", false) ||
        error("guide example $(spec.label) failed verification")
    rows = result.physical
    isempty(rows) && error("guide example $(spec.label) has no physical-link results")
    hulten_ranks = rank_map(rows, :hulten)
    extended_ranks = rank_map(rows, :primitive_F)
    rank_shifts = [
        abs(hulten_ranks[row.physical_link_id] -
            extended_ranks[row.physical_link_id])
        for row in rows
    ]
    # Keep the ranking comparison informative in both five-link and larger examples.
    top_count = min(5, max(1, ceil(Int, 0.2length(rows))))
    top_hulten = Set(
        row.physical_link_id
        for row in sort(rows; by=row -> (-row.hulten, row.physical_link_id))[1:top_count]
    )
    top_extended = Set(
        row.physical_link_id
        for row in sort(rows; by=row -> (-row.primitive_F, row.physical_link_id))[1:top_count]
    )
    return (
        label=spec.label,
        nodes=model.data.N,
        links=length(rows),
        mean_hulten=mean(row.hulten for row in rows),
        mean_extended=mean(row.primitive_F for row in rows),
        rank_correlation=TNW.spearman_correlation(
            [row.hulten for row in rows],
            [row.primitive_F for row in rows],
        ),
        maximum_rank_shift=maximum(rank_shifts),
        top_overlap=length(intersect(top_hulten, top_extended)),
        top_count=top_count,
        congestion_effect=mean(row.realized_F - row.realized_NC for row in rows),
        mode_effect=mean(row.realized_F - row.realized_FM for row in rows),
        route_effect=mean(row.realized_F - row.realized_FR for row in rows),
        hulten_collapse_error=maximum(
            abs(row.hulten - row.realized_NC) for row in rows),
    )
end

function write_example_results(macros_path, mechanisms_path, summaries)
    urban = only(summary for summary in summaries
                 if summary.label == "Multimodal urban (U)")
    cow = only(summary for summary in summaries
               if summary.label == "Cow network (EG)")
    open(macros_path, "w") do io
        println(io, "% Generated by scripts/build_practitioner_guide_assets.jl; do not edit.")
        println(io, "\\providecommand{\\GuideUrbanHultenCollapseError}{",
            tex_scientific(urban.hulten_collapse_error), "}")
        println(io, "\\providecommand{\\GuideCowTopOverlap}{",
            cow.top_overlap, "}")
        println(io, "\\providecommand{\\GuideCowTopCount}{",
            cow.top_count, "}")
        println(io, "\\providecommand{\\GuideCowMaximumRankShift}{",
            cow.maximum_rank_shift, "}")
    end
    open(mechanisms_path, "w") do io
        println(io, "% Generated by scripts/build_practitioner_guide_assets.jl; do not edit.")
        println(io, "\\begin{tabular}{lrrrr}")
        println(io, "\\toprule")
        println(io,
            "Example & Congestion & Mode flexibility & Route flexibility & " *
            "Top-\$k\$ overlap \\\\")
        println(io, "\\midrule")
        for summary in summaries
            println(io,
                tex_escape(summary.label), " & ",
                fmt(summary.congestion_effect), " & ",
                fmt(summary.mode_effect), " & ",
                fmt(summary.route_effect), " & ",
                summary.top_overlap, "/", summary.top_count, " \\\\")
        end
        println(io, "\\bottomrule")
        println(io, "\\end{tabular}")
    end
end

function verify_rsue_claims()
    expected = TOML.parsefile(RSUE_EXPECTED)["paper_choice_edge_census_2017"]
    file_sha256(RSUE_PUBLIC_CLAIMS) == expected["public_claims_sha256"] ||
        error("public RSUE claim ledger does not match expected_summary.toml")
    public = TOML.parsefile(RSUE_PUBLIC_CLAIMS)
    public["specification_status"] == "accepted" ||
        error("public RSUE claim ledger has not accepted the specification")
    public["verification_status"] == "accepted" ||
        error("public RSUE claim ledger has not accepted numerical verification")

    network = public["network"]
    results = public["results"]
    hashes = public["source_hashes"]
    tolerance = expected["numeric_comparison_tolerance"]
    network["nodes"] == expected["nodes"] ||
        error("public RSUE node count differs from expected_summary.toml")
    network["directed_policy_arcs"] == expected["directed_policy_arcs"] ||
        error("public RSUE directed-arc count differs from expected_summary.toml")
    network["physical_policy_links"] == expected["physical_policy_links"] ||
        error("public RSUE physical-link count differs from expected_summary.toml")
    hashes["configuration"] == expected["config_sha256"] ||
        error("public RSUE configuration hash differs from expected_summary.toml")
    hashes["census_overlay"] == expected["census_overlay_sha256"] ||
        error("public RSUE Census-overlay hash differs from expected_summary.toml")
    hashes["directed_output"] == expected["directed_output_sha256"] ||
        error("public RSUE directed-output hash differs from expected_summary.toml")
    hashes["physical_output"] == expected["physical_output_sha256"] ||
        error("public RSUE physical-output hash differs from expected_summary.toml")
    hashes["claim_ledger"] == expected["claims_sha256"] ||
        error("public RSUE source-ledger hash differs from expected_summary.toml")
    comparisons = (
        results["mean_primitive_elasticity"] =>
            expected["mean_physical_primitive_elasticity"],
        results["median_primitive_elasticity"] =>
            expected["median_physical_primitive_elasticity"],
        results["maximum_primitive_elasticity"] =>
            expected["maximum_physical_primitive_elasticity"],
        results["pearson_hulten"] => expected["pearson_hulten"],
        results["spearman_hulten"] => expected["spearman_hulten"],
    )
    all(abs(actual - target) <= tolerance for (actual, target) in comparisons) ||
        error("public RSUE claims do not reproduce expected aggregate claims")

    physical = joinpath(RSUE_ROOT, "decomposition_physical.csv")
    claims = joinpath(RSUE_ROOT, "paper_claims.json")
    if isfile(physical) || isfile(claims)
        isfile(physical) && isfile(claims) ||
            error("local RSUE verification requires both the physical output and claim ledger")
        file_sha256(physical) == expected["physical_output_sha256"] ||
            error("local RSUE physical output does not match expected_summary.toml")
        file_sha256(claims) == expected["claims_sha256"] ||
            error("local RSUE claim ledger does not match expected_summary.toml")
    end
    return public
end

function write_rsue_macros(path)
    public = verify_rsue_claims()
    network = public["network"]
    results = public["results"]
    components = public["decomposition"]

    open(path, "w") do io
        println(io, "% Generated by scripts/build_practitioner_guide_assets.jl; do not edit.")
        pairs = [
            "GuideRSUENodeCount" => string(network["nodes"]),
            "GuideRSUEDirectedArcCount" => string(network["directed_policy_arcs"]),
            "GuideRSUEPhysicalLinkCount" => string(network["physical_policy_links"]),
            "GuideRSUEMeanTraditional" =>
                fmt(results["mean_traditional_elasticity"]; digits=7),
            "GuideRSUEMeanRealized" =>
                fmt(results["mean_realized_elasticity"]; digits=7),
            "GuideRSUEMeanExtended" =>
                fmt(results["mean_primitive_elasticity"]; digits=7),
            "GuideRSUEMedianExtended" =>
                fmt(results["median_primitive_elasticity"]; digits=7),
            "GuideRSUEMaximumExtended" =>
                fmt(results["maximum_primitive_elasticity"]; digits=7),
            "GuideRSUEPearson" => fmt(results["pearson_hulten"]; digits=3),
            "GuideRSUESpearman" => fmt(results["spearman_hulten"]; digits=3),
            "GuideRSUETopTenOverlap" => string(results["top_ten_overlap"]),
            "GuideRSUEExternalityComponent" =>
                fmt(components["mean_externality_component"]; digits=7),
            "GuideRSUEPropagationComponent" =>
                fmt(components["mean_propagation_component"]; digits=7),
            "GuideRSUERoadComponent" =>
                fmt(components["mean_road_component"]; digits=7),
            "GuideRSUETerminalComponent" =>
                fmt(components["mean_terminal_component"]; digits=7),
            "GuideRSUEPassThroughComponent" =>
                fmt(components["mean_pass_through_component"]; digits=7),
        ]
        for (name, value) in pairs
            println(io, "\\providecommand{\\", name, "}{", value, "}")
        end
    end
end

function generate(output)
    mkpath(output)
    project = load_project(GRID_CONFIG)
    validation = validate(project)
    validation.valid || error("grid validation failed")
    model = build_model(project)
    result = decompose_welfare(model)
    result.diagnostics["verified"] || error("grid decomposition failed verification")
    rows = result.physical
    hulten = [row.hulten for row in rows]
    extended = [row.primitive_F for row in rows]
    pearson = cor(hulten, extended)
    spearman = TNW.spearman_correlation(hulten, extended)
    hulten_ranks = rank_map(rows, :hulten)
    extended_ranks = rank_map(rows, :primitive_F)
    rise = argmax(row -> hulten_ranks[row.physical_link_id] -
                         extended_ranks[row.physical_link_id], rows)
    fall = argmax(row -> extended_ranks[row.physical_link_id] -
                         hulten_ranks[row.physical_link_id], rows)
    components = [
        ("Pass-through", mean(row.primitive_pass_through for row in rows)),
        ("Terminal congestion", mean(row.primitive_terminal for row in rows)),
        ("Road congestion", mean(row.primitive_edge for row in rows)),
        ("GE propagation", mean(row.primitive_propagation for row in rows)),
        ("Externalities", mean(row.primitive_externality for row in rows)),
    ]

    write_grid_macros(joinpath(output, "grid-results.tex"), model, result,
        pearson, spearman, hulten_ranks, extended_ranks, rise, fall, components,
        validation)
    write_rsue_macros(joinpath(output, "rsue-results.tex"))
    example_summaries = []
    for (index, spec) in enumerate(GUIDE_EXAMPLES)
        example_model, example_result = if index == 1
            model, result
        else
            example_project = load_project(spec.config)
            built_model = build_model(example_project)
            built_model, decompose_welfare(built_model)
        end
        push!(example_summaries,
            summarize_example(spec, example_model, example_result))
        write_example_visual_data(
            output, spec, example_model, example_result)
    end
    write_example_results(
        joinpath(output, "example-results.tex"),
        joinpath(output, "example-mechanisms.tex"),
        example_summaries,
    )
    write_network_figure(joinpath(output, "grid-network.tex"), model, rows)
    write_decomposition(joinpath(output, "grid-decomposition.tex"), rows, components)
    return generated_files(output)
end

function check_generated()
    isdir(DEFAULT_OUTPUT) || error("committed guide assets are missing")
    mktempdir() do temporary
        files = generate(temporary)
        committed = generated_files(DEFAULT_OUTPUT; exclude=EXTERNAL_ASSET_FILES)
        files == committed || error(
            "generated guide asset inventory differs: generated=$files committed=$committed")
        for file in files
            generated_asset_matches(
                file, joinpath(temporary, file), joinpath(DEFAULT_OUTPUT, file)) ||
                error("generated guide asset drift: $file")
        end
    end
    println("practitioner-guide generated sources accepted")
end

if "--check" in ARGS
    check_generated()
else
    output_index = findfirst(==("--output"), ARGS)
    output = output_index === nothing ? DEFAULT_OUTPUT :
             abspath(ARGS[output_index + 1])
    println.(generate(output))
end
