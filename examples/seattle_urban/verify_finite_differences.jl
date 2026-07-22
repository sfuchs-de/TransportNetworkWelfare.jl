using TransportNetworkWelfare

function main()
    config = joinpath(@__DIR__, "generated", "config.toml")
    isfile(config) || error("run prepare.jl first")
    model = build_model(load_project(config))
    result = welfare_effects(model)
    maximum_index = argmax(getproperty.(result.directed, :primitive_F))
    indices = unique([1, maximum_index, length(result.directed)])
    rows = NamedTuple[]
    for index in indices
        row = result.directed[index]
        finite = urban_finite_difference(model, row.edge_id; step=1e-5)
        push!(rows, (;
            row.edge_id, analytic=row.primitive_F,
            finite_difference=finite.elasticity,
            absolute_error=abs(row.primitive_F-finite.elasticity),
            residual=max(finite.plus.residual, finite.minus.residual),
        ))
    end
    for row in rows
        println(TransportNetworkWelfare.json_value(Dict(string(k) => v for (k, v) in pairs(row))))
    end
    maximum(row.absolute_error for row in rows) < 1e-6 ||
        error("Seattle finite-difference verification exceeded tolerance")
end

main()
