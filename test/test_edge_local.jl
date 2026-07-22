module EdgeLocalTests

using LinearAlgebra
using Test
using TransportNetworkWelfare

const TNW = TransportNetworkWelfare
const ROOT = normpath(joinpath(@__DIR__, ".."))
const COW_CONFIG = joinpath(ROOT, "examples", "cow", "config.toml")
const TOY_CONFIG = joinpath(ROOT, "examples", "toy", "config.toml")

function independent_dense_jacobian(project, data)
    c = TNW.AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    jacobian = TNW.AdjointRSUE.assemble_J(
        data.sx, data.sy, data.mu, data.lam, data.omega, c)
    power = TNW.modal_power(project.modal)
    dense_x = (-(c.σ-1)/c.e) .* data.omega .- c.cA .* data.nu
    dense_y = (-c.σ/c.e) .* data.omega .- ((1-c.β)/c.e) .* data.nu
    for (t, (i, j)) in enumerate(data.edges)
        shares = @view data.s_edges[t, :]
        gamma = [TNW.edge_congestion_value(project, data, t, m)
                 for m in eachindex(data.modes)]
        diagonal = 1 .- power .* gamma
        system = Matrix(Diagonal(diagonal)) .-
                 (1-c.σ-power) .* (gamma*permutedims(shares))
        gain = dot(shares, system \ gamma)
        r = vcat(copy(dense_x), copy(dense_y))
        r[i] += -c.cC
        r[j] += c.cA
        r[length(data.sx)+i] += (1-c.β)/c.e
        r[length(data.sx)+j] += -c.cB
        jacobian[i, :] .+= (1-c.σ)*data.mu[i, j]*gain .* r
        j < data.N &&
            (jacobian[data.N+j, :] .+= (1-c.σ)*data.lam[i, j]*gain .* r)
    end
    return jacobian
end

@testset "Sparse edge-local Jacobian and adjoint" begin
    project = load_project(COW_CONFIG)
    data = TNW.load_network(project)
    components = TNW.edge_local_jacobian_components(project, data)
    reconstructed = Matrix(components.sparse_core)+
                    components.low_rank_rows*permutedims(components.low_rank_columns)
    independent = independent_dense_jacobian(project, data)
    @test reconstructed ≈ independent atol=1e-12 rtol=0

    sparse_solution = TNW.sparse_low_rank_adjoint(
        components, data.omega, components.c.σ)
    dense_solution = transpose(independent) \
        TNW.AdjointRSUE.psi_row(data.omega, components.c.σ)
    @test sparse_solution.solution ≈ dense_solution atol=1e-10 rtol=1e-10
    @test sparse_solution.residual < 1e-11

    result = edge_local_welfare_effects(project)
    @test result.diagnostics["verified"]
    @test result.diagnostics["closure_level"] == "edge_local_sparse"
    @test length(result.directed) == 72
    @test length(result.physical) == 36
    @test all(isfinite(row.primitive_F) for row in result.directed)
end

@testset "Edge-local output matches the full welfare closure" begin
    project = load_project(TOY_CONFIG)
    edge_only = TNW.replace_project(project; congestion=
        EdgeCongestion(Dict(:road => 0.05, :rail => 0.0)))
    sparse_result = edge_local_welfare_effects(edge_only)
    full_result = welfare_effects(edge_only)
    sparse_rows = Dict(row.edge_id => row for row in sparse_result.directed)
    full_rows = Dict(row.edge_id => row for row in full_result.directed)
    @test keys(sparse_rows) == keys(full_rows)
    @test maximum(abs(sparse_rows[id].primitive_F-full_rows[id].primitive_F)
                  for id in keys(full_rows)) < 1e-10
    @test all(ismissing(row.realized_F) for row in sparse_result.directed)
    @test all(ismissing(row.chi_effective) for row in sparse_result.directed)
    @test !sparse_result.diagnostics["realized_friction_available"]
end

@testset "Efficient edge-local Hulten collapse" begin
    project = load_project(COW_CONFIG)
    efficient = TNW.replace_project(
        project; alpha=0.0, beta=0.0, congestion=NoCongestion())
    result = edge_local_welfare_effects(efficient)
    @test maximum(abs(row.primitive_F-row.hulten) for row in result.directed) < 1e-10
    @test all(ismissing(row.realized_F) for row in result.directed)
end

@testset "Unsupported edge-local terminal channel" begin
    project = load_project(COW_CONFIG)
    data = TNW.load_network(project)
    terminal = TNW.replace_project(project; congestion=
        EndpointTerminalCongestion(Dict(:road => 0.1)))
    @test_throws ArgumentError TNW.edge_local_jacobian_components(terminal, data)
end

end # module
