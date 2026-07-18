"""
AdjointRSUE — corrected Proposition-2 estimator (2026-07-10).

Implements the coefficient map, residual Jacobian, welfare row, market-access
exposure stock, congestion block, modal pass-through, and edge elasticity used in
the repaired derivation. The implementation is checked against the independent
oracle in `lab/verify_prop2.py` and the fixtures in `test/fixtures/`.

  C1  no anchored Woodbury / singular ridge  → the Jacobian is the verified four-block
                                               + rank-1 labor feedback + normalization row;
                                               the redundant G2_N row is *replaced* by a
                                               normalization, so the efficient benchmark is
                                               nonsingular and needs no ridge.
  C3  prefactor (σ−1), denom (α+1)−σ(α+β)     → uses ρ=(1+α+β)/e and e=1+β(σ−1)+ασ everywhere.
  C4  normalize by Y,E (openness totals)      → normalize multipliers by the node-visit
                                               stock 𝒯_i = 𝒫_i𝒬_i/Yᵂ.
  C6  ad-hoc "Prop 3" headline                → the elasticity is the proved
                                               ε = χ·ρ·s_{kl,m}·Ξ_{kl}·(Mₖⁱⁿ+Mₗᵒᵘᵗ).

The Fogel/Proposition-1 collapse (Mⁱⁿ+Mᵒᵘᵗ=1 and ε→Ξ at α=β=γ=0) holds to
approximately 1e-12 in the bundled tests.
"""
module AdjointRSUE

using LinearAlgebra

export Coef, coefs, psi_row, welfare_gradient
export assemble_J, adjoint_multipliers, prop2_edge_elasticity
export node_visit_stock, shares_from_traffic, anchored_objects, chi_wedge, congestion_J

# ── coefficients (verify_prop2.py: coefs) ──────────────────────────────────────
struct Coef
    α::Float64; β::Float64; σ::Float64; e::Float64
    cA::Float64; cB::Float64; cC::Float64; cE::Float64; ρ::Float64
end

"""coefs(α, β, σ) → Coef. Regularity scalar e = 1 + β(σ−1) + ασ (R-XY); ρ = (1+α+β)/e."""
function coefs(α::Real, β::Real, σ::Real)
    e = 1 + β*(σ-1) + α*σ
    @assert abs(e) > 1e-10 "regularity violated: e ≈ 0 (Prop 2 requires e ≠ 0)"
    @assert abs(1 + α + β) > 1e-10 "regularity violated: 1+α+β ≈ 0 (Prop 2 requires 1+α+β ≠ 0)"
    Coef(α, β, σ, e, (1+α)/e, σ*(α+β)/e, (α+β)*(σ-1)/e, 1 - σ*(α+β)/e, (1+α+β)/e)
end

# ── welfare rows (verify_prop2.py: psi, q at lines 263-264) ─────────────────────
"ψ = [(1−σ)ω, −σω]  (the adjoint selector row)."
psi_row(ω::AbstractVector, σ::Real) = vcat((1-σ) .* ω, (-σ) .* ω)
"q = D_z ln W = −ρ[ω, (σ/(σ−1))ω].  Note q = ρ/(σ−1)·ψ."
welfare_gradient(ω::AbstractVector, c::Coef) =
    vcat(-c.ρ .* ω, (-c.ρ*c.σ/(c.σ-1)) .* ω)

# ── the verified Jacobian J = J0 + JA  (verify_prop2.py: analytic_J, γ=0 path) ──
# sx,sy :: length-N local (domestic-absorption) shares; μ,λ :: N×N substochastic
# shares (λ indexed [origin i, dest j], as in verify_prop2 `lam`); ω :: labor shares.
"""
    assemble_J(sx, sy, μ, λ, ω, c) -> J (2N×2N)

Four-block network Jacobian J0 + rank-1 fixed-labor feedback JA + the G2_N normalization
row. Mirrors `analytic_J` with γ=0 (no congestion block); for congestion, add Jc
separately (see `chi_wedge` for the per-edge wedge).
"""
function assemble_J(sx::AbstractVector, sy::AbstractVector,
                    μ::AbstractMatrix, λ::AbstractMatrix,
                    ω::AbstractVector, c::Coef)
    N = length(sx); σ = c.σ
    Iₙ = Matrix{Float64}(I, N, N)
    J = zeros(2N, 2N)
    # --- J0: four blocks (analytic_J lines 143-146) ---
    J[1:N,      1:N]    .= Diagonal(sx) .- c.cA .* Iₙ .+ c.cA .* μ
    J[1:N,      N+1:2N] .= c.cB .* Iₙ .- c.cB .* μ
    λT = permutedims(λ)                                   # lam.T
    bx = c.cC .* (Iₙ .- λT)
    by = Diagonal(sy) .- c.cE .* (Iₙ .- λT)
    J[N+1:2N-1, 1:N]    .= bx[1:N-1, :]
    J[N+1:2N-1, N+1:2N] .= by[1:N-1, :]
    # --- normalization row G2_N (analytic_J lines 147-148) ---
    J[2N, N]  = c.α / c.e
    J[2N, 2N] = -(1 + c.β*(σ-1)) / ((σ-1)*c.e)
    # --- JA: rank-1 labor feedback, rows 1..2N-1 only (lines 150-153) ---
    svec = vcat(sx, sy[1:N-1])                            # stacked, length 2N-1
    outer = svec * permutedims(ω)                         # (2N-1)×N
    J[1:2N-1, 1:N]    .+= ((σ-1)/c.e) .* outer
    J[1:2N-1, N+1:2N] .+= (σ/c.e)     .* outer
    return J
end

# ── adjoint multipliers via J' ℓ = ψ  (𝓛 = −ψᵀJ⁻¹; normalize by 𝒯) ──────────────
"""
    adjoint_multipliers(J, ω, σ, 𝒯) -> (; 𝓛in, 𝓛out, Min, Mout)

Solve J'ℓ = ψ (NO ridge). 𝓛in = −ℓ[1:N], 𝓛out = −ℓ[N+1:2N]; node multipliers
Min = 𝓛in./𝒯, Mout = 𝓛out./𝒯. By the occupation identity 𝓛out[N] ≈ 0 (normalization row).
"""
function adjoint_multipliers(J::AbstractMatrix, ω::AbstractVector, σ::Real, 𝒯::AbstractVector)
    N = length(ω)
    ψ = psi_row(ω, σ)
    ℓ = permutedims(J) \ ψ                # J'ℓ = ψ  ⇒  ℓ_c = (ψᵀJ⁻¹)_c
    𝓛in  = .-ℓ[1:N]
    𝓛out = .-ℓ[N+1:2N]
    return (; 𝓛in, 𝓛out, Min = 𝓛in ./ 𝒯, Mout = 𝓛out ./ 𝒯)
end

# ── corrected Prop-2 edge elasticity (R-PROP2) ─────────────────────────────────
"""
    prop2_edge_elasticity(k, l, m_share, Xi_kl, mult, ρ; χ=1.0, N) -> ε

ε ≡ −d ln W / d ln κ̄_{kl,m} = χ · ρ · s_{kl,m} · Ξ_{kl} · (Mₖⁱⁿ + Mₗᵒᵘᵗ).
`mult` is the NamedTuple from `adjoint_multipliers`; `m_share` = s_{kl,m}; the l=N
normalization node contributes Mₗᵒᵘᵗ = 0.
"""
function prop2_edge_elasticity(k::Int, l::Int, m_share::Real, Xi_kl::Real,
                               mult, ρ::Real; χ::Real=1.0, N::Int)
    Mo = (l == N) ? 0.0 : mult.Mout[l]
    return χ * ρ * m_share * Xi_kl * (mult.Min[k] + Mo)
end

# ── node-visit stock + observables adapter (R-NODE-VISIT) ──────────────────────
# The shares the corrected Jacobian needs are recovered through the node-visit stock
# 𝒯 (NOT through 𝒬=Π^{1−σ} — dividing by 𝒬 instead of 𝒯 is exactly the C4 error). The
# forms below are golden-master validated (test/runtests.jl, "adapter via node-visit stock").
"""
    node_visit_stock(𝒬, 𝒫, Yw) -> 𝒯

𝒯_i = 𝒬_i·𝒫_i / Yᵂ, the pre-absorption node-visit stock (R-NODE-VISIT). Here
𝒬_i = Π_i^{1−σ} (origin market-access stock) and 𝒫_i = P_i^{1−σ} (destination stock).
These two stocks come from the equilibrium recursions; recovering 𝒯 from *raw traffic
alone* is the open observability question (manuscript ISSUES #5), not assumed here.
"""
node_visit_stock(𝒬::AbstractVector, 𝒫::AbstractVector, Yw::Real) = (𝒬 .* 𝒫) ./ Yw

"""
    shares_from_traffic(N, out_nbrs, in_nbrs, Xi_tot, 𝒯) -> (sx, sy, μ, λ)

Given edge traffic Ξ and the node-visit stock 𝒯, recover the structural shares via the
traffic lemma (Ξ_{ik} = μ_{ik}𝒯_i = λ_{ik}𝒯_k) and the openness identity:
- μ[i,k] = Ξ[i,k]/𝒯_i, λ[i,k] = Ξ[i,k]/𝒯_k   (substochastic; rows/cols sum to 1−sx, 1−sy)
- sx_i = 1 − O_i^{out}/𝒯_i, sy_i = 1 − O_i^{in}/𝒯_i   (O = Σ Ξ openness)
"""
function shares_from_traffic(N::Int, out_nbrs, in_nbrs,
                             Xi_tot::AbstractMatrix, 𝒯::AbstractVector)
    μ = zeros(N, N); λ = zeros(N, N)
    Oout = zeros(N); Oin = zeros(N)
    for i in 1:N, k in out_nbrs[i]
        v = Xi_tot[i,k]; Oout[i] += v
        𝒯[i] > 0 && (μ[i,k] = v/𝒯[i])
    end
    for k in 1:N, i in in_nbrs[k]
        v = Xi_tot[i,k]; Oin[k] += v
        𝒯[k] > 0 && (λ[i,k] = v/𝒯[k])
    end
    sx = [𝒯[i] > 0 ? 1 - Oout[i]/𝒯[i] : 0.0 for i in 1:N]
    sy = [𝒯[i] > 0 ? 1 - Oin[i]/𝒯[i]  : 0.0 for i in 1:N]
    return sx, sy, μ, λ
end

# ── anchored Woodbury (R-WOODBURY-ANCHOR) ──────────────────────────────────────
"""
    anchored_objects(μ, a, ω, σ) -> (; Bx, Bxbar, Θ)

Efficient-benchmark block Bx = diag(a) − I + μ is singular (Bx·1 = 0); anchoring with the
rank-1 labor term gives a nonsingular Bxbar, and (1−σ)ωᵀBxbar⁻¹ = −Θᵀ reproduces the
occupation measure Θ.
"""
function anchored_objects(μ::AbstractMatrix, a::AbstractVector, ω::AbstractVector, σ::Real)
    N = length(a)
    Bx = Matrix(Diagonal(a)) - Matrix{Float64}(I, N, N) + μ
    Bxbar = Bx + (σ-1) .* (a * permutedims(ω))
    Θ = vec((σ-1) .* (permutedims(ω) / Bxbar))     # (1−σ)ωᵀBxbar⁻¹ = −Θᵀ
    return (; Bx, Bxbar, Θ)
end

# ── congestion Jacobian block J^cong (appendix, App. l.300–316; closes review F2) ──
"""
    congestion_J(N, edges, s_edges, μ, λ, ω, ν, γ, η, c::Coef) -> Jc (2N×2N)

The endogenous congestion feedback block of J = J⁰ + J^𝒜 + J^cong. Appendix rows
(directed neighbor sets, per I-028):

  J^cong[G1_i, ·] = (1−σ) Σ_{r∈𝒩⁺(i)} μ_{ir} ∂lnκ_{ir}/∂z
  J^cong[G2_i, ·] = (1−σ) Σ_{r∈𝒩⁻(i)} λ_{ri} ∂lnκ_{ri}/∂z    (i ≤ N−1; G2_N row = 0)

Per edge (i,j), the modal system 𝓗a = γ·dln𝓡 (δ=0) gives ∂lnκ_{ij}/∂z = g_{ij}·r(i,j)
with the scalar g_{ij} = sᵀ𝓗⁻¹γ, 𝓗 = diag(1−ηγ) − (1−σ−η)γsᵀ. The r-vectors — the
I-031 closed form, derived from ln𝓡_{ij} = ln𝒫_i + ln𝒬_j − lnYᵂ through the reduced
form (unit terms at i,j plus ω- and ν-aggregates; ν = income shares wL/Yᵂ):

  r^x(i,j) = −C·e_i + A·e_j − ((σ−1)/e)·ω − A·ν
  r^y(i,j) = ((1−β)/e)·e_i − B·e_j − (σ/e)·ω − ((1−β)/e)·ν

Verified against the oracle's FD-built block on the ext_cong fixture (test suite).
`s_edges` is E×M mode shares aligned with `edges`; γ length-M congestion elasticities.
With γ = 0 the block is identically zero.
"""
function congestion_J(N::Int, edges::Vector{Tuple{Int,Int}}, s_edges::AbstractMatrix,
                      μ::AbstractMatrix, λ::AbstractMatrix,
                      ω::AbstractVector, ν::AbstractVector,
                      γ::AbstractVector, η::Real, c::Coef)
    σ = c.σ
    Jc = zeros(2N, 2N)
    all(iszero, γ) && return Jc
    D = 1 .- η .* γ
    # closed-form r-vector coefficients
    cP_x = -c.cC;          cQ_x = c.cA
    cP_y = (1 - c.β)/c.e;  cQ_y = -c.cB
    densx = (-(σ-1)/c.e) .* ω .+ (-c.cA) .* ν            # x-block dense part
    densy = (-σ/c.e) .* ω .+ (-(1 - c.β)/c.e) .* ν       # y-block dense part

    @inline function add_edge_row!(row::Int, w::Real, i::Int, j::Int)
        @views Jc[row, 1:N]    .+= w .* densx
        @views Jc[row, N+1:2N] .+= w .* densy
        Jc[row, i]   += w * cP_x;  Jc[row, j]    += w * cQ_x
        Jc[row, N+i] += w * cP_y;  Jc[row, N+j]  += w * cQ_y
        return nothing
    end

    for (t, (i, j)) in enumerate(edges)
        s = @view s_edges[t, :]
        H = Matrix(Diagonal(D)) .- (1 - σ - η) .* (γ * permutedims(s))
        g = dot(s, H \ γ)                                # dlnκ_ij = g · dln𝓡_ij
        g == 0.0 && continue
        μ[i,j] > 0 && add_edge_row!(i, (1-σ)*μ[i,j]*g, i, j)          # G1_i row
        (j <= N-1 && λ[i,j] > 0) && add_edge_row!(N+j, (1-σ)*λ[i,j]*g, i, j)  # G2_j row
    end
    return Jc
end

# ── congestion wedge χ (verify_prop2.py: chi_wedge) ────────────────────────────
"""
    chi_wedge(s, γ, η, σ) -> χ (vector over modes)

D_m = 1 − ηγ_m ;  B = (1−σ−η)Σ_m s_m γ_m/D_m ;  χ_m = 1/(D_m(1−B)).  χ = 1 when γ = 0.
"""
function chi_wedge(s::AbstractVector, γ::AbstractVector, η::Real, σ::Real)
    D = 1 .- η .* γ
    B = (1 - σ - η) * sum(s .* γ ./ D)
    return 1.0 ./ (D .* (1 - B))
end

end # module
