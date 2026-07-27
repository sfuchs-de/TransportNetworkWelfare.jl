using TransportNetworkWelfare

function main()
    root = @__DIR__
    project = load_project(joinpath(root, "generated", "config.toml"))
    project.spatial isa EconomicGeography ||
        error("Westeros must use the economic-geography closure")
    report = validate(project)
    report.valid || error("Westeros validation failed")

    result = decompose_welfare(project)
    length(result.directed) == 2 * length(result.physical) ||
        error("Westeros physical links are not reciprocal pairs")
    all(isfinite(row.primitive_F) for row in result.directed) ||
        error("Westeros welfare effects contain nonfinite values")

    identity_error = maximum(
        max(
            abs(row.identity_residual_edge),
            abs(row.identity_residual_terminal),
            abs(row.identity_residual_mode),
            abs(row.identity_residual_route),
        )
        for row in result.directed
    )
    channel_error = maximum(
        max(
            abs(row.channel_residual_edge),
            abs(row.channel_residual_terminal),
            abs(row.channel_residual_mode),
            abs(row.channel_residual_route),
        )
        for row in result.directed
    )
    terminal_error = maximum(
        max(abs(row.d_terminal), abs(row.primitive_terminal))
        for row in result.directed
    )
    identity_error <= project.tolerance ||
        error("Westeros decomposition identity failed: $identity_error")
    channel_error <= project.tolerance ||
        error("Westeros channel reconstruction failed: $channel_error")
    terminal_error <= project.tolerance ||
        error("inactive terminal channel is nonzero: $terminal_error")

    println((
        spatial_specification="economic_geography",
        nodes=report.nodes,
        directed_arcs=length(result.directed),
        physical_links=length(result.physical),
        identity_error,
        channel_error,
        terminal_error,
    ))
end

main()
