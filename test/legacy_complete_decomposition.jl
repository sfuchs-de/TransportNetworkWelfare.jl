module LegacyCompleteDecompositionTests

using Test, LinearAlgebra, SparseArrays

const HERE = @__DIR__
const ROOT = normpath(joinpath(HERE, ".."))
using TransportNetworkWelfare.AdjointRSUE
using TransportNetworkWelfare.IFTDecomposition
using TransportNetworkWelfare.RSUETerminalCongestion
using TransportNetworkWelfare.IFTCompleteDecomposition

function central_jacobian(f, x; step=1e-6)
    base = f(x)
    J = zeros(length(base), length(x))
    for j in eachindex(x)
        plus = copy(x); plus[j] += step
        minus = copy(x); minus[j] -= step
        J[:, j] .= (f(plus) .- f(minus)) ./ (2step)
    end
    return J
end

function solve_nonlinear_toy(delta, pair, primitive, model)
    n, Q = size(model.J0, 1), size(model.A, 1)
    value = zeros(n + Q)
    theta = zeros(size(model.C, 2))
    primitive && (theta[pair] = delta)
    realized = primitive ? zeros(n) : delta .* model.BS[:, pair]
    function residual(v)
        z = @view v[1:n]
        logq = @view v[n+1:end]
        a = theta + model.G * logq
        logx = model.Qz * z + model.C * a
        quantities = model.A * exp.(logx)
        return vcat(model.J0*z + model.BS*a + realized,
                    logq - log.(quantities))
    end
    for _ in 1:40
        current = residual(value)
        norm(current, Inf) < 1e-13 && return value
        value .-= central_jacobian(residual, value) \ current
    end
    error("toy equilibrium did not converge")
end

function toy_model(; route=:soft, modal=:flexible, road=true, terminal=true,
                   unique_route=false)
    n, E, P, Q = 3, 2, 4, 3
    J0 = [1.8 0.1 0.0; 0.05 1.6 0.08; 0.0 0.06 1.7]
    B = [0.12 0.03; -0.04 0.10; 0.07 -0.02]
    L = [1.0 0.0; 1.0 0.0; 0.0 1.0; 0.0 1.0]
    Sagg = [0.65 0.35 0.0 0.0; 0.0 0.0 0.55 0.45]
    A = [1.0 0.0 0.0 0.0; 0.0 0.6 0.0 0.4; 0.0 0.4 0.0 0.6]
    Qedge_soft = [0.10 -0.05 0.02; -0.03 0.08 0.04]
    Qedge_fixed = [0.07 -0.02 0.01; -0.01 0.05 0.03]
    Croute_soft = [-1.10 0.18; 0.12 -0.95]
    Croute_fixed = [-0.92 0.08; 0.04 -0.81]
    Qedge = route == :soft || unique_route ? Qedge_soft : Qedge_fixed
    Croute = route == :soft || unique_route ? Croute_soft : Croute_fixed
    G = zeros(P, Q)
    road && (G[1, 1] = 0.07)
    if terminal
        G[2, 2] = 0.05; G[2, 3] = 0.05
        G[4, 2] = 0.05; G[4, 3] = 0.05
    end
    eta = 1.2
    Kedge = Sagg * G
    C = L * Croute * Sagg
    modal == :flexible && (C .+= eta .* (Matrix(I, P, P) .- L*Sagg))
    Qz = L * Qedge
    H = Matrix(I, Q, Q) - A*C*G
    J = J0 + B*Sagg*G*(H \ (A*Qz))
    BS = B*Sagg
    return (; J0, B, L, Sagg, A, Qz, C, G, H, J, BS, eta)
end

@testset "Complete route-modal-terminal decomposition" begin
    @testset "Inverse x-y transformation" begin
        alpha, beta, sigma = 0.10, -0.30, 9.0
        c = coefs(alpha, beta, sigma)
        omega = [0.2, 0.3, 0.5]
        V = IFTCompleteDecomposition.inverse_state_map(3, omega, c)
        function transform(z)
            x, y = z[1:3], z[4:6]
            Z = omega .* exp.(x ./ c.e .+ sigma .* y ./ ((sigma-1)*c.e))
            W = (1 / sum(Z))^(1 + alpha + beta)
            logw = alpha .* x ./ c.e .-
                (1 + beta*(sigma-1)) .* y ./ ((sigma-1)*c.e)
            logL = log(W)/(1+alpha+beta) .+ log.(Z)
            return vcat(logw, logL, log(W))
        end
        @test maximum(abs.(central_jacobian(transform, zeros(6)) .- V)) < 1e-8
    end

    @testset "Nonlinear closure finite differences" begin
        closures = Dict(
            :NC => toy_model(road=false, terminal=false),
            :NT => toy_model(road=true, terminal=false),
            :F => toy_model(),
            :FM => toy_model(modal=:fixed),
            :FR => toy_model(route=:fixed),
        )
        welfare = [0.4, -0.2, 0.3]
        step = 1e-5
        for (name, model) in closures, primitive in (false, true)
            plus = solve_nonlinear_toy(step, 1, primitive, model)
            minus = solve_nonlinear_toy(-step, 1, primitive, model)
            fd = -dot(welfare, plus[1:3] .- minus[1:3]) / (2step)
            if primitive
                e = zeros(4); e[1] = 1
                direct = model.BS*e + model.BS*model.G*(model.H \ (model.A*model.C*e))
                analytic = dot(welfare, model.J \ direct)
            else
                analytic = dot(welfare, model.J \ model.BS[:, 1])
            end
            @test fd ≈ analytic atol=1e-8 rtol=1e-7
        end

        no_terminal = toy_model(terminal=false)
        @test no_terminal.J ≈ closures[:NT].J atol=1e-12 rtol=0
        no_congestion = toy_model(road=false, terminal=false)
        @test no_congestion.J ≈ no_congestion.J0 atol=1e-12 rtol=0

        unique_soft = toy_model(unique_route=true)
        unique_fixed = toy_model(route=:fixed, unique_route=true)
        @test unique_fixed.J ≈ unique_soft.J atol=1e-12 rtol=0

        # One active mode per edge makes the flexible and fixed modal lifts equal.
        Lone = Matrix(I, 2, 2)
        Sone = Matrix(I, 2, 2)
        Gone = [0.05 0.0; 0.0 0.04]
        Croute = [-1.0 0.1; 0.05 -0.9]
        Cflex = Lone*Croute*Sone + 1.2*(Matrix(I, 2, 2)-Lone*Sone)
        Cfixed = Lone*Croute*Sone
        @test Cflex == Cfixed
    end

end

end # module
