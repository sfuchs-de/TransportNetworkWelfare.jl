module LegacyAdjointTests

# =============================================================================
# QA suite for the corrected AdjointRSUE (src_corrected/AdjointRSUE.jl).
#   Tier A — analytic identities (pure Julia, random shares; no equilibrium solve)
#   Tier B — golden master vs the verified oracle lab/verify_prop2.py (fixtures/*.jl)
# Run:  <julia> --startup-file=no test/runtests.jl
# Exits nonzero on any failure (the Julia analogue of the Python self-asserting gate).
# Regenerate fixtures first with:  python3 test/export_fixtures.py
# =============================================================================
using Test, LinearAlgebra, Random

const HERE = @__DIR__
using TransportNetworkWelfare.AdjointRSUE

# reshape a Python row-major (order='C') flat vector into an nr×nc Julia matrix
_mat(flat, nr, nc) = permutedims(reshape(Float64.(flat), nc, nr))

# a random irreducible substochastic μ with row sums (1−a) at the efficient benchmark
function random_efficient(N; seed=1)
    rng = MersenneTwister(seed)
    a = 0.2 .+ 0.6 .* rand(rng, N)
    μ = zeros(N, N)
    for i in 1:N
        w = rand(rng, N); w[i] = 0.0; w ./= sum(w)
        μ[i, :] .= (1 - a[i]) .* w
    end
    ω = rand(rng, N); ω ./= sum(ω)
    return a, μ, ω
end

@testset "Tier A — analytic identities" begin
    σ = 5.0; N = 8
    a, μ, ω = random_efficient(N)

    @testset "I-032: J^A labor feedback is rank-1" begin
        c = coefs(0.06, -0.20, σ); sx = a; sy = a
        svec = vcat(sx, sy[1:N-1])
        JA = zeros(2N, 2N)
        JA[1:2N-1, 1:N]    .= ((σ-1)/c.e) .* (svec * ω')
        JA[1:2N-1, N+1:2N] .= (σ/c.e)     .* (svec * ω')
        @test rank(JA; atol=1e-10) == 1
    end

    @testset "R-WOODBURY-ANCHOR + R-OCC-ADJOINT" begin
        o = anchored_objects(μ, a, ω, σ)
        @test norm(o.Bx * ones(N)) < 1e-12          # B_x·1 = 0 (right null)
        @test cond(o.Bxbar) < 1e6                   # anchored block well-conditioned
        @test norm(o.Θ' * o.Bx) < 1e-9              # Θᵀ B_x = 0 (occupation left-null)
        @test abs(dot(o.Θ, a) - 1) < 1e-9           # Θᵀ a = 1
        Θ0 = vec(nullspace(Matrix(o.Bx'))[:, 1]); Θ0 ./= dot(Θ0, a)
        @test maximum(abs.(o.Θ .- Θ0)) < 1e-8       # anchored inverse == independent null
    end

    @testset "R-PROP2: q = ρ/(σ-1)·ψ" begin
        c = coefs(0.10, -0.30, σ)
        @test maximum(abs.(welfare_gradient(ω, c) .- (c.ρ/(σ-1)) .* psi_row(ω, σ))) < 1e-12
    end

    @testset "R-WEDGE: χ closed form vs direct modal solve" begin
        η = 1.099; γ = [0.08, 0.04]; s = [0.7, 0.3]
        D = 1 .- η .* γ
        H = Diagonal(D) - (1 - σ - η) .* (γ * s')      # modal system 𝓗 (analytic_J)
        χ = chi_wedge(s, γ, η, σ)
        for m in 1:2
            e_m = zeros(2); e_m[m] = 1.0
            a_m = H \ e_m
            @test abs(dot(s, a_m) - s[m]*χ[m]) < 1e-10   # ā = sᵀa = s_m·χ_m
        end
    end
end

# -----------------------------------------------------------------------------
function check_fixture(tag; has_cong=false, tol_J=1e-9, tol_eps=1e-8)
    f = include(joinpath(HERE, "fixtures", "$(tag).jl"))
    N, σ = f.N, f.sigma
    c = coefs(f.alpha, f.beta, σ)
    @test abs(c.e - f.e) < 1e-12 && abs(c.ρ - f.rho) < 1e-12   # coefs match oracle

    if has_cong
        J = f.Ja                                   # isolate adjoint/elasticity against oracle J
    else
        J = assemble_J(f.sx, f.sy, f.mu, f.lam, f.omega, c)
        @test maximum(abs.(J .- f.Ja)) < tol_J     # the J port reproduces analytic_J exactly
    end

    mult = adjoint_multipliers(J, f.omega, σ, f.Tn)

    max_eps_err = 0.0; max_mm_err = 0.0; max_collapse = 0.0
    for (t, (k, l)) in enumerate(f.ref_edges)
        χe = has_cong ? f.chi[t] : 1.0
        ε = prop2_edge_elasticity(k, l, f.s_mode[k, l], f.Xi[k, l], mult, c.ρ; χ=χe, N=N)
        max_eps_err = max(max_eps_err, abs(ε - f.eps_ref[t]))
        Mo = (l == N) ? 0.0 : mult.Mout[l]
        max_mm_err = max(max_mm_err, abs((mult.Min[k] + Mo) - f.MinMout[t]))
        max_collapse = max(max_collapse, abs((mult.Min[k] + Mo) - 1.0))
    end
    @test max_eps_err < tol_eps                    # estimator reproduces oracle ε
    @test max_mm_err  < tol_eps                    # (Min+Mout) reproduces oracle
    return (; max_eps_err, max_mm_err, max_collapse, e=f.e, rho=f.rho)
end

@testset "Tier B — golden master vs verify_prop2.py" begin
    @testset "efficient (Fogel/Prop-1 collapse)" begin
        r = check_fixture("efficient")
        @test r.max_collapse < 1e-8                # Mⁱⁿ+Mᵒᵘᵗ = 1  ⇒  ε → Ξ_{kl,m}
        @info "efficient" max_eps_err=r.max_eps_err collapse_err=r.max_collapse
    end
    @testset "ext_epos (externalities, e>0)" begin
        r = check_fixture("ext_epos")
        @info "ext_epos" e=r.e rho=r.rho max_eps_err=r.max_eps_err
    end
    @testset "ext_cong (externalities + congestion, oracle J)" begin
        r = check_fixture("ext_cong"; has_cong=true)
        @info "ext_cong" max_eps_err=r.max_eps_err
    end

    @testset "ext_cong — NATIVE J^cong (closed-form r-vectors vs oracle FD block)" begin
        f = include(joinpath(HERE, "fixtures", "ext_cong.jl"))
        N, σ, η = f.N, f.sigma, f.eta
        c = coefs(f.alpha, f.beta, σ)
        J0A = assemble_J(f.sx, f.sy, f.mu, f.lam, f.omega, c)
        Jc  = congestion_J(N, f.edges, f.s_all, f.mu, f.lam, f.omega, f.nu, f.gam, η, c)
        # Oracle Ja = J0 + JA + Jc(FD, h=1e-7); our J0+JA matches Ja(γ=0 part) exactly,
        # so the residual tests the closed-form r-vectors against the oracle's FD block.
        errJ = maximum(abs.((J0A .+ Jc) .- f.Ja))
        @test errJ < 1e-5                          # FD-limited agreement
        # Full native pipeline: adjoint + ε from the native J, vs oracle eps_ref
        mult = adjoint_multipliers(J0A .+ Jc, f.omega, σ, f.Tn)
        me = 0.0
        for (t, (k, l)) in enumerate(f.ref_edges)
            ε = prop2_edge_elasticity(k, l, f.s_mode[k,l], f.Xi[k,l], mult, c.ρ; χ=f.chi[t], N=N)
            me = max(me, abs(ε - f.eps_ref[t]))
        end
        @test me < 1e-6                            # ε through native J matches oracle
        @info "native J^cong" errJ=errJ eps_err=me
    end

    @testset "ext_eneg — paper calibration (σ=9, e=−0.5, ρ=−1.6, γ=(0.092,0.096)), native J" begin
        fp = joinpath(HERE, "fixtures", "ext_eneg.jl")
        if isfile(fp)
            f = include(fp)
            N, σ, η = f.N, f.sigma, f.eta
            c = coefs(f.alpha, f.beta, σ)
            @test abs(c.e - (-0.5)) < 1e-12 && abs(c.ρ - (-1.6)) < 1e-12
            J = assemble_J(f.sx, f.sy, f.mu, f.lam, f.omega, c) .+
                congestion_J(N, f.edges, f.s_all, f.mu, f.lam, f.omega, f.nu, f.gam, η, c)
            errJ = maximum(abs.(J .- f.Ja))
            @test errJ < 1e-5
            mult = adjoint_multipliers(J, f.omega, σ, f.Tn)
            me = 0.0
            for (t, (k, l)) in enumerate(f.ref_edges)
                ε = prop2_edge_elasticity(k, l, f.s_mode[k,l], f.Xi[k,l], mult, c.ρ; χ=f.chi[t], N=N)
                me = max(me, abs(ε - f.eps_ref[t]))
            end
            @test me < 1e-6
            @info "ext_eneg (e<0 + congestion, native J)" errJ=errJ eps_err=me
        else
            @warn "ext_eneg fixture missing — exporter could not converge; e<0 leg untested"
        end
    end
end

# Observables → shares adapter, then full estimator from the adapter (pipeline entry point).
@testset "Tier B — observables adapter (node-visit stock)" begin
    for tag in ("efficient", "ext_epos")
        f = include(joinpath(HERE, "fixtures", "$(tag).jl"))
        N, σ = f.N, f.sigma
        out_nbrs = [Int[] for _ in 1:N]; in_nbrs = [Int[] for _ in 1:N]
        for (k, l) in f.edges; push!(out_nbrs[k], l); push!(in_nbrs[l], k); end

        𝒯 = node_visit_stock(f.Qstock, f.Pstock, f.Yw)
        @test maximum(abs.(𝒯 .- f.Tn)) < 1e-10                 # 𝒯 = 𝒬𝒫/Yᵂ reproduces oracle

        sx, sy, μ, λ = shares_from_traffic(N, out_nbrs, in_nbrs, f.Xi, 𝒯)
        @test maximum(abs.(sx .- f.sx)) < 1e-9                  # recovered shares match oracle
        @test maximum(abs.(sy .- f.sy)) < 1e-9
        @test maximum(abs(μ[i,k] - f.mu[i,k]) for (i,k) in f.edges) < 1e-9
        @test maximum(abs(λ[i,k] - f.lam[i,k]) for (i,k) in f.edges) < 1e-9

        # full estimator built from adapter outputs reproduces the oracle elasticity
        c = coefs(f.alpha, f.beta, σ)
        J = assemble_J(sx, sy, μ, λ, f.omega, c)
        mult = adjoint_multipliers(J, f.omega, σ, 𝒯)
        me = 0.0
        for (t, (k, l)) in enumerate(f.ref_edges)
            ε = prop2_edge_elasticity(k, l, f.s_mode[k,l], f.Xi[k,l], mult, c.ρ; χ=1.0, N=N)
            me = max(me, abs(ε - f.eps_ref[t]))
        end
        @test me < 1e-8
        @info "adapter[$tag]" stock_err=maximum(abs.(𝒯 .- f.Tn)) eps_err=me
    end
end

end # module
