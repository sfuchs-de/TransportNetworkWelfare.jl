using CSV
using Statistics
using TOML
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const HERE = @__DIR__
const config = joinpath(HERE, "rsue_legacy_audited.toml")
const expected = TOML.parsefile(joinpath(HERE, "expected_summary.toml"))

project = load_project(config)
result = decompose_welfare(project)
target = expected["results"]

result.diagnostics["nodes"] == expected["network"]["nodes"] ||
    error("RSUE node count does not match the frozen summary")
length(result.directed) == expected["network"]["directed_policy_arcs"] ||
    error("RSUE directed-policy count does not match the frozen summary")
length(result.physical) == expected["network"]["physical_policy_links"] ||
    error("RSUE physical-link count does not match the frozen summary")
abs(mean(row.primitive_F for row in result.directed) -
    target["mean_directed_primitive_elasticity"]) < 5e-15 ||
    error("RSUE mean directed elasticity does not match the frozen summary")
abs(median(row.primitive_F for row in result.directed) -
    target["median_directed_primitive_elasticity"]) < 5e-15 ||
    error("RSUE median directed elasticity does not match the frozen summary")
result.diagnostics["verified"] || error("RSUE result failed internal verification")

frozen_root = get(ENV, "RSUE_FROZEN_RESULTS_ROOT", "")
if !isempty(frozen_root)
    frozen_files = Dict(
        "directed_output_sha256" => "ift_complete_directed.csv",
        "physical_output_sha256" => "ift_complete_physical.csv",
        "diagnostics_sha256" => "complete_decomposition_diagnostics.csv",
    )
    for (expected_key, filename) in frozen_files
        path = joinpath(frozen_root, filename)
        isfile(path) || error("frozen output not found: $path")
        actual_hash = TNW.file_sha256(path)
        expected_hash = target[expected_key]
        actual_hash == expected_hash || error(
            "frozen output hash mismatch for $filename: expected $expected_hash, got $actual_hash")
    end

    directed_path = joinpath(frozen_root, frozen_files["directed_output_sha256"])
    old = Dict((Int(row.k), Int(row.l)) => row for row in CSV.File(directed_path))
    length(old) == length(result.directed) || error("frozen directed output has the wrong row count")
    field_pairs = (
        (:hulten, :hulten),
        (:realized_NC, :realized_NC), (:realized_NT, :realized_NT),
        (:realized_F, :realized_F), (:realized_FM, :realized_FM),
        (:realized_FR, :realized_FR), (:primitive_F, :primitive_F),
        (:chi_effective, :chi_effective),
        (:m_NC, :m_NC), (:m_NT, :m_NT), (:m_F, :m_F),
        (:m_FM, :m_FM), (:m_FR, :m_FR),
        (:d_edge, :d_road), (:d_terminal, :d_terminal),
        (:d_mode, :d_mode), (:d_route, :d_route),
        (:edge_allocation, :road_allocation), (:edge_scarcity, :road_scarcity),
        (:edge_equilibrium, :road_equilibrium),
        (:terminal_allocation, :terminal_allocation),
        (:terminal_scarcity, :terminal_scarcity),
        (:terminal_equilibrium, :terminal_equilibrium),
        (:mode_allocation, :mode_allocation), (:mode_scarcity, :mode_scarcity),
        (:mode_equilibrium, :mode_equilibrium),
        (:route_allocation, :route_allocation), (:route_scarcity, :route_scarcity),
        (:route_equilibrium, :route_equilibrium),
        (:hulten_realized_gap, :hulten_realized_gap),
        (:hulten_externality, :hulten_externality),
        (:hulten_attenuation, :hulten_attenuation),
        (:primitive_gap, :primitive_gap),
        (:primitive_externality, :primitive_externality),
        (:primitive_propagation, :primitive_propagation),
        (:primitive_edge, :primitive_road),
        (:primitive_terminal, :primitive_terminal),
        (:primitive_pass_through, :primitive_pass_through),
        (:identity_residual_edge, :identity_residual_road),
        (:identity_residual_terminal, :identity_residual_terminal),
        (:identity_residual_mode, :identity_residual_mode),
        (:identity_residual_route, :identity_residual_route),
    )
    directed_error = maximum(
        abs(getproperty(row, current)-Float64(getproperty(old[(row.origin_index,
            row.destination_index)], frozen)))
        for row in result.directed for (current, frozen) in field_pairs
    )
    physical_path = joinpath(frozen_root, frozen_files["physical_output_sha256"])
    pair_key(a, b) = minmax(string(a), string(b))
    old_physical = Dict(pair_key(row.k, row.l) => row for row in CSV.File(physical_path))
    length(old_physical) == length(result.physical) ||
        error("frozen physical output has the wrong row count")
    all(row.directions == Int(old_physical[pair_key(
        row.endpoint_a, row.endpoint_b)].directions) for row in result.physical) ||
        error("physical-link direction counts do not match the frozen output")
    physical_error = maximum(
        abs(getproperty(row, current)-Float64(getproperty(old_physical[pair_key(
            row.endpoint_a, row.endpoint_b)], frozen)))
        for row in result.physical for (current, frozen) in field_pairs
    )
    maximum_error = max(directed_error, physical_error)
    maximum_error < target["numeric_comparison_tolerance"] ||
        error("RSUE directed output exceeds the frozen numeric tolerance: $maximum_error")
    legacy_residuals = (
        :parallel_residual_road, :parallel_residual_terminal,
        :channel_residual_mode, :channel_residual_route,
    )
    maximum_legacy_residual = maximum(
        abs(Float64(getproperty(row, field))) for row in values(old) for field in legacy_residuals)
    maximum_legacy_residual < target["numeric_comparison_tolerance"] ||
        error("legacy-only decomposition residual exceeds tolerance: $maximum_legacy_residual")
    println("frozen hashes and row-level comparison passed; maximum absolute error = $maximum_error")
end

println("RSUE legacy acceptance passed")
