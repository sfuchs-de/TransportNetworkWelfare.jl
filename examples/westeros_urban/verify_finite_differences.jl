using TransportNetworkWelfare

function main()
    root = @__DIR__
    project = load_project(joinpath(root, "generated", "config.toml"))
    model = build_model(project)
    result = welfare_effects(model)

    analytic = [row.primitive_F for row in result.directed]
    ordered = sortperm(analytic)
    checks = unique([first(ordered), ordered[cld(length(ordered), 2)], last(ordered)])
    maximum_error = 0.0
    for index in checks
        finite = urban_finite_difference(model, index; step=1e-5)
        error = abs(analytic[index] - finite.elasticity)
        maximum_error = max(maximum_error, error)
        println((;
            edge_id=model.basis.policy_edge_ids[index],
            analytic=analytic[index],
            finite_difference=finite.elasticity,
            error,
            nonlinear_residual=max(finite.plus.residual, finite.minus.residual),
        ))
    end
    maximum_error <= 1e-6 || error("Westeros urban finite-difference check failed")
    println("maximum_error=$maximum_error")
end

main()
