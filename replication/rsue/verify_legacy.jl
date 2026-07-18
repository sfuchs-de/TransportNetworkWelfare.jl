using CSV
using Statistics
using TOML
using TransportNetworkWelfare

const HERE = @__DIR__
const config = joinpath(HERE, "rsue_legacy_audited.toml")
const expected = TOML.parsefile(joinpath(HERE, "expected_summary.toml"))

project = load_project(config)
result = decompose_welfare(project)
target = expected["results"]

@assert length(result.directed) == expected["network"]["directed_policy_arcs"]
@assert length(result.physical) == expected["network"]["physical_policy_links"]
@assert abs(mean(row.primitive_F for row in result.directed) -
            target["mean_directed_primitive_elasticity"]) < 5e-15
@assert abs(median(row.primitive_F for row in result.directed) -
            target["median_directed_primitive_elasticity"]) < 5e-15
@assert result.diagnostics["verified"]

frozen_root = get(ENV, "RSUE_FROZEN_RESULTS_ROOT", "")
if !isempty(frozen_root)
    path = joinpath(frozen_root, "ift_complete_directed.csv")
    isfile(path) || error("frozen directed output not found: $path")
    old = Dict((Int(row.k), Int(row.l)) => row for row in CSV.File(path))
    fields = (:hulten, :realized_NC, :realized_NT, :realized_F, :realized_FM,
              :realized_FR, :primitive_F, :chi_effective, :m_NC, :m_NT,
              :m_F, :m_FM, :m_FR, :d_terminal, :d_mode, :d_route)
    maximum_error = maximum(
        abs(getproperty(row, field)-Float64(getproperty(old[(row.origin_index,
            row.destination_index)], field)))
        for row in result.directed for field in fields
    )
    @assert maximum_error < target["numeric_comparison_tolerance"]
    println("full frozen-output comparison passed; maximum absolute error = $maximum_error")
end

println("RSUE legacy acceptance passed")
