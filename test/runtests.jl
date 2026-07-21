using Test
using TransportNetworkWelfare

@testset "TransportNetworkWelfare" begin
    include("test_api.jl")
    include("test_modal.jl")
    include("test_schema.jl")
    include("test_census_ports.jl")
    include("legacy_adjoint.jl")
    include("legacy_route_decomposition.jl")
    include("legacy_complete_decomposition.jl")
    include("legacy_terminal_congestion.jl")
    include("test_external_rsue.jl")
end
