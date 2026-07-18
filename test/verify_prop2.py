"""Independent numerical verification of Propositions 1-2, Corollary 1, and all
appendix lemmas in EvalTransportImprovements_AFW (2_Model.tex + 99_Appendix_update_2.tex).

Implements the model from scratch (gravity equilibrium with externalities, multimodal
edge-cost CES index, per-edge congestion fixed point, soft-routing resolvent), solves
the (x,y) residual system G=0, and checks every claimed identity against brute force.
"""
import sys
import numpy as np
np.random.seed(7)
np.set_printoptions(precision=4, suppress=True)
CHECKS = []   # (label, value, tolerance) accumulated for the self-asserting gate (HANDBOOK §7)

# ---------------- parameters / network ----------------
N, M = 6, 2
sigma, eta = 4.0, 2.0
Lbar = 2.0

edges = [(i, (i+1) % N) for i in range(N)] + [((i+1) % N, i) for i in range(N)] \
        + [(0, 3), (3, 0), (1, 4), (4, 1)]
edges = sorted(set(edges))
E = len(edges)
kbar = np.full((N, N, M), np.inf)
for (i, j) in edges:
    base = np.random.uniform(1.7, 2.6)
    kbar[i, j, 0] = base
    kbar[i, j, 1] = base * np.random.uniform(0.95, 1.45)
Abar = np.random.uniform(0.85, 1.2, N)
ubar = np.random.uniform(0.85, 1.2, N)

def coefs(alpha, beta):
    e = 1 + beta*(sigma-1) + alpha*sigma
    return dict(e=e, cA=(1+alpha)/e, cB=sigma*(alpha+beta)/e,
                cC=(alpha+beta)*(sigma-1)/e, cE=1-sigma*(alpha+beta)/e,
                rho=(1+alpha+beta)/e)

# ---------------- core model objects ----------------
def reduced(z, alpha, beta):
    """w, L, W, A, u, P, Q, Yw, Z from state z=(lnx, lny)."""
    c = coefs(alpha, beta)
    lnx, lny = z[:N], z[N:]
    x, y = np.exp(lnx), np.exp(lny)
    Z = x**(1/c['e']) * y**(sigma/((sigma-1)*c['e']))
    W = (Lbar/Z.sum())**(1+alpha+beta)
    L = W**(1/(1+alpha+beta)) * Z
    w = x**(alpha/c['e']) * y**(-(1+beta*(sigma-1))/((sigma-1)*c['e']))
    A = Abar * L**alpha
    u = ubar * L**beta
    Q = A**(1-sigma) * w**sigma * L           # \Pi^{1-sigma}
    P = W**(sigma-1) * (u*w)**(1-sigma)       # P^{1-sigma}
    Yw = (w*L).sum()
    return dict(x=x, y=y, Z=Z, W=W, L=L, w=w, A=A, u=u, P=P, Q=Q, Yw=Yw, **c)

def edge_costs(z, alpha, beta, gam, kbar_loc=None, tol=1e-15):
    """Per-edge modal congestion fixed point given z. Returns kappa_edge (NxN),
    kappa_mode (NxNxM), shares s (NxNxM), R (NxN, traffic non-cost component)."""
    kb = kbar if kbar_loc is None else kbar_loc
    r = reduced(z, alpha, beta)
    R = np.outer(r['P'], r['Q']) / r['Yw']    # R_ij = P_i Q_j / Yw
    km = np.where(np.isfinite(kb), kb, np.inf).copy()
    for _ in range(800):
        with np.errstate(over='ignore', invalid='ignore'):
            ke = (np.nansum(np.where(np.isfinite(km), km**eta, 0.0), axis=2))**(1/eta)
        ke[~np.isfinite(km).any(axis=2)] = np.inf
        with np.errstate(over='ignore', invalid='ignore'):
            s = np.where(np.isfinite(km), km**eta / np.where(ke[:, :, None] > 0, ke[:, :, None]**eta, 1), 0.0)
        Xi = np.where(np.isfinite(ke), ke**(1-sigma) * R, 0.0)
        Xim = s * Xi[:, :, None]
        new = np.where(np.isfinite(kb), kb * np.where(Xim > 0, Xim, 1.0)**gam[None, None, :], np.inf)
        with np.errstate(invalid='ignore'):
            distance = np.nanmax(np.abs(np.where(np.isfinite(new), new - km, 0.0)))
        if distance < tol:
            km = new; break
        km = 0.5*km + 0.5*new if np.isfinite(km).any() else new
    with np.errstate(over='ignore'):
        ke = (np.nansum(np.where(np.isfinite(km), km**eta, 0.0), axis=2))**(1/eta)
    ke[~np.isfinite(km).any(axis=2)] = np.inf
    s = np.where(np.isfinite(km), km**eta / np.where(np.isfinite(ke[:, :, None]), ke[:, :, None]**eta, 1), 0.0)
    return ke, km, s, R

def residual_pieces(z, alpha, beta, gam, kbar_loc=None):
    c = coefs(alpha, beta)
    r = reduced(z, alpha, beta)
    ke, km, s, R = edge_costs(z, alpha, beta, gam, kbar_loc)
    K = np.where(np.isfinite(ke), ke**(1-sigma), 0.0)
    phi = (Abar*ubar)**(sigma-1)
    Acal = (r['Z'].sum()/Lbar)**(sigma-1)
    x, y = r['x'], r['y']
    XA = x**c['cA'] * y**(-c['cB'])                 # x_j^A y_j^{-B}
    YB = x**(-c['cC']) * y**c['cE']                 # x_j^{-C} y_j^{E}
    S1 = phi*Acal*x + (K * (Abar[None, :]/Abar[:, None])**(1-sigma) * XA[None, :]).sum(1)
    S2 = phi*Acal*y + (K.T * (ubar[None, :]/ubar[:, None])**(1-sigma) * YB[None, :]).sum(1)
    sx = phi*Acal*x/S1
    sy = phi*Acal*y/S2
    mu = K * (Abar[None, :]/Abar[:, None])**(1-sigma) * XA[None, :] / S1[:, None]      # mu_ij
    lam = K * (ubar[:, None]/ubar[None, :])**(1-sigma) * YB[:, None] / S2[None, :]     # lam_ij (origin i, dest j)
    return dict(r=r, c=c, ke=ke, km=km, s=s, R=R, K=K, phi=phi, Acal=Acal,
                S1=S1, S2=S2, sx=sx, sy=sy, mu=mu, lam=lam)

def G(z, alpha, beta, gam, kbar_loc=None):
    p = residual_pieces(z, alpha, beta, gam, kbar_loc)
    c, x, y = p['c'], p['r']['x'], p['r']['y']
    g1 = np.log(p['S1']) - c['cA']*np.log(x) + c['cB']*np.log(y)
    g2 = np.log(p['S2']) + c['cC']*np.log(x) - c['cE']*np.log(y)
    gN = (alpha/c['e'])*np.log(x[N-1]) - (1+beta*(sigma-1))/((sigma-1)*c['e'])*np.log(y[N-1])
    return np.concatenate([g1, g2[:N-1], [gN]])

def fd_jac(f, z, h=1e-7):
    n = len(z); Jm = np.zeros((n, n))
    for j in range(n):
        zp, zm = z.copy(), z.copy(); zp[j] += h; zm[j] -= h
        Jm[:, j] = (f(zp) - f(zm))/(2*h)
    return Jm

def solve_eq(alpha, beta, gam, kbar_loc=None, z0=None):
    rng = np.random.default_rng(3)
    z = (0.02*rng.standard_normal(2*N)) if z0 is None else z0.copy()
    f = lambda zz: G(zz, alpha, beta, gam, kbar_loc)
    for it in range(120):
        g = f(z)
        if np.max(np.abs(g)) < 1e-13:
            break
        Jm = fd_jac(f, z)
        try:
            step = np.linalg.solve(Jm, g)
        except np.linalg.LinAlgError:
            step = np.linalg.lstsq(Jm, g, rcond=None)[0]
        sc = min(1.0, 1.5/np.max(np.abs(step)))   # cap step size
        for _ in range(40):                        # backtracking line search
            zn = z - sc*step
            gn = f(zn)
            if np.all(np.isfinite(gn)) and np.max(np.abs(gn)) < np.max(np.abs(g)):
                break
            sc *= 0.5
        z = zn
    return z, np.max(np.abs(f(z)))

def analytic_J(z, alpha, beta, gam, kbar_loc=None, with_cong=True):
    p = residual_pieces(z, alpha, beta, gam, kbar_loc)
    c, r = p['c'], p['r']
    omega = r['L']/Lbar
    Sx, Sy = np.diag(p['sx']), np.diag(p['sy'])
    mu, lam = p['mu'], p['lam']
    I = np.eye(N)
    J0 = np.zeros((2*N, 2*N))
    J0[:N, :N] = Sx - c['cA']*I + c['cA']*mu
    J0[:N, N:] = c['cB']*I - c['cB']*mu
    J0[N:2*N-1, :N] = (c['cC']*(I - lam.T))[:N-1, :]
    J0[N:2*N-1, N:] = (Sy - c['cE']*(I - lam.T))[:N-1, :]
    J0[2*N-1, N-1] = alpha/c['e']
    J0[2*N-1, N+N-1] = -(1+beta*(sigma-1))/((sigma-1)*c['e'])
    JA = np.zeros((2*N, 2*N))
    JA[:N, :N] = (sigma-1)/c['e'] * np.outer(p['sx'], omega)
    JA[:N, N:] = sigma/c['e'] * np.outer(p['sx'], omega)
    JA[N:2*N-1, :N] = (sigma-1)/c['e'] * np.outer(p['sy'][:N-1], omega)
    JA[N:2*N-1, N:] = sigma/c['e'] * np.outer(p['sy'][:N-1], omega)
    Jc = np.zeros((2*N, 2*N))
    if with_cong and np.any(gam != 0):
        # dlnkappa_ij/dz via per-edge modal system; dlnR_ij/dz by FD on reduced form
        h = 1e-7
        dlnk = np.zeros((N, N, 2*N))
        for (i, j) in edges:
            svec = p['s'][i, j, :]
            D = 1 - eta*gam
            H = np.diag(D) - np.outer(gam*(1-sigma-eta), svec)
            Hinv = np.linalg.inv(H)
            for col in range(2*N):
                zp, zm = z.copy(), z.copy(); zp[col] += h; zm[col] -= h
                rp, rm = reduced(zp, alpha, beta), reduced(zm, alpha, beta)
                lnRp = np.log(rp['P'][i]*rp['Q'][j]/rp['Yw'])
                lnRm = np.log(rm['P'][i]*rm['Q'][j]/rm['Yw'])
                dR = (lnRp - lnRm)/(2*h)
                a = Hinv @ (gam*dR)
                dlnk[i, j, col] = svec @ a
        for i in range(N):
            for jj in range(2*N):
                Jc[i, jj] = (1-sigma)*sum(p['mu'][i, rr]*dlnk[i, rr, jj] for rr in range(N) if p['mu'][i, rr] > 0)
        for i in range(N-1):
            for jj in range(2*N):
                Jc[N+i, jj] = (1-sigma)*sum(p['lam'][rr, i]*dlnk[rr, i, jj] for rr in range(N) if p['lam'][rr, i] > 0)
    return J0 + JA + Jc, p, omega

def chi_wedge(svec, gam):
    D = 1 - eta*gam
    B = (1-sigma-eta)*np.sum(svec*gam/D)
    return 1.0/(D[:]* (1-B))   # vector over modes m: chi_m = 1/(D_m (1-B))

def welfare_fd(alpha, beta, gam, k, l, m, z0, h=1e-5):
    out = []
    for sgn in (+1, -1):
        kb = kbar.copy(); kb[k, l, m] *= np.exp(sgn*h)
        z, res = solve_eq(alpha, beta, gam, kbar_loc=kb, z0=z0)
        assert res < 1e-10, res
        out.append(np.log(reduced(z, alpha, beta)['W']))
    return (out[0] - out[1])/(2*h)

def report(label, val, tol=1e-9):
    CHECKS.append((label, float(val), tol))
    print(f"  {label:62s} {val:.3e}   (tol {tol:.0e})")

# =======================================================================
print("="*100)
print("RUN A: externalities + congestion  (alpha=0.06, beta=-0.20, gamma=(0.08,0.04))")
alpha, beta = 0.06, -0.20
gam = np.array([0.08, 0.04])
c = coefs(alpha, beta)
print(f"  e={c['e']:.4f}  rho={c['rho']:.4f}")
z, res = solve_eq(alpha, beta, gam)
print(f"  Newton residual: {res:.2e}"); CHECKS.append(("Newton equilibrium residual", float(res), 1e-10))
p = residual_pieces(z, alpha, beta, gam)
r = p['r']

# --- A0: is this a genuine equilibrium of the ORIGINAL model? ---
K = p['K']
sr = max(abs(np.linalg.eigvals(K)))
T = np.linalg.inv(np.eye(N) - K)        # tau^{1-sigma} all-walk resolvent
print(f"  spectral radius of K: {sr:.4f}")
PDS = ((np.outer((r['w']/r['A'])**(1-sigma), np.ones(N)) * T).sum(0))   # P_j^{1-sigma} from sum
report("P_j^{1-sigma}: DS sum vs reduced form", np.max(np.abs(PDS - r['P'])))
Wj = r['w']*r['u']/PDS**(1/(1-sigma))
report("welfare equalization max|W_j/W - 1|", np.max(np.abs(Wj/r['W']-1)))
X = r['W']**(1-sigma) * np.outer(r['A']**(sigma-1)*r['w']**(1-sigma), r['u']**(sigma-1)*r['w']**sigma*r['L']) * T
report("goods market clearing max|sum_j X_ij - w_i L_i|", np.max(np.abs(X.sum(1)-r['w']*r['L'])))
report("budget max|sum_j X_ji - w_i L_i|", np.max(np.abs(X.sum(0)-r['w']*r['L'])))
# traffic two ways: brute-force double-sum vs kappa^{1-s} P_k Q_l / Yw
Tau = T  # tau_{ij}^{1-sigma}
Xi_brute = np.zeros((N, N))
for (kk, ll) in edges:
    acc = 0.0
    for i in range(N):
        for j in range(N):
            acc += X[i, j] * (Tau[i, kk]*p['K'][kk, ll]*Tau[ll, j]/Tau[i, j])
    Xi_brute[kk, ll] = acc / r['Yw']
Xi = p['K'] * np.outer(r['P'], r['Q']) / r['Yw']
report("traffic factorization max|Xi_brute - K P_k Q_l/Yw|", np.max(np.abs(Xi_brute - np.where(np.isfinite(p['ke']), Xi, 0))))

# --- A1: traffic lemma ---
Tn = r['P']*r['Q']/r['Yw']
err1 = max(abs(Xi[i, j] - p['mu'][i, j]*Tn[i]) for (i, j) in edges)
err2 = max(abs(Xi[i, j] - p['lam'][i, j]*Tn[j]) for (i, j) in edges)
report("Lemma traffic-node-visits: |Xi - mu T_i|", err1)
report("Lemma traffic-node-visits: |Xi - lam T_j|", err2)
O = np.array([sum(Xi[i, j] for j in range(N) if np.isfinite(p['ke'][i, j])) for i in range(N)])
In = np.array([sum(Xi[i, j] for i in range(N) if np.isfinite(p['ke'][i, j])) for j in range(N)])
report("O_i = (1-s^x) T_i", np.max(np.abs(O - (1-p['sx'])*Tn)))
report("I_j = (1-s^y) T_j", np.max(np.abs(In - (1-p['sy'])*Tn)))

# --- A2: analytic J vs FD J ---
Ja, _, omega = analytic_J(z, alpha, beta, gam)
Jf = fd_jac(lambda zz: G(zz, alpha, beta, gam), z)
report("max|J_analytic - J_fd|", np.max(np.abs(Ja - Jf)), tol=1e-6)

# --- A3: direct wedge zeta vs FD at fixed z ---
k_, l_, m_ = edges[2][0], edges[2][1], 0
h = 1e-6
kbp, kbm = kbar.copy(), kbar.copy()
kbp[k_, l_, m_] *= np.exp(h); kbm[k_, l_, m_] *= np.exp(-h)
kep, *_ = edge_costs(z, alpha, beta, gam, kbp)
kem, *_ = edge_costs(z, alpha, beta, gam, kbm)
zeta_fd = (np.log(kep[k_, l_]) - np.log(kem[k_, l_]))/(2*h)
chi_vec = chi_wedge(p['s'][k_, l_, :], gam)
zeta_formula = p['s'][k_, l_, m_]*chi_vec[m_]
report("zeta: FD vs wedge-lemma formula", abs(zeta_fd - zeta_formula))

# --- A4: end-to-end Prop 2, first-nature shock, several edges ---
psi = np.concatenate([(1-sigma)*omega, -sigma*omega])
q = np.concatenate([-c['rho']*omega, -c['rho']*sigma/(sigma-1)*omega])
Jinv = np.linalg.inv(Ja)
print("  --- first-nature FD vs operator vs scalar formula ---")
for (k_, l_), m_ in [(edges[2], 0), (edges[5], 1), ((N-1, 0), 0), ((0, N-1) if np.isfinite(kbar[0, N-1, 0]) else edges[7], 0)]:
    if not np.isfinite(kbar[k_, l_, m_]):
        continue
    fd = -welfare_fd(alpha, beta, gam, k_, l_, m_, z)
    chi_vec = chi_wedge(p['s'][k_, l_, :], gam)
    zeta = p['s'][k_, l_, m_]*chi_vec[m_]
    b = np.zeros(2*N)
    b[k_] = (1-sigma)*zeta*p['mu'][k_, l_]
    if l_ <= N-2:
        b[N+l_] = (1-sigma)*zeta*p['lam'][k_, l_]
    op = q @ Jinv @ b
    Lin = -psi @ Jinv @ np.eye(2*N)[k_]
    Lout = 0.0 if l_ == N-1 else -psi @ Jinv @ np.eye(2*N)[N+l_]
    Min, Mout = Lin/Tn[k_], Lout/Tn[l_]
    scal = chi_vec[m_]*c['rho']*p['s'][k_, l_, m_]*Xi[k_, l_]*(Min+Mout)
    print(f"   edge ({k_},{l_},m={m_}): FD={fd:.10f}  qJ^-1b={op:.10f}  scalar={scal:.10f}  "
          f"|FD-op|={abs(fd-op):.2e}  |FD-scal|={abs(fd-scal):.2e}")
    CHECKS.append(("A: FD = operator (congestion live in J)", abs(fd-op), 1e-6))
    CHECKS.append(("A: FD = scalar formula (congestion live in J)", abs(fd-scal), 1e-6))

# hatted multipliers equivalence
k_, l_ = edges[2]
Lin = -psi @ Jinv @ np.eye(2*N)[k_]
Mh_in = (1-p['sx'][k_])*Lin/O[k_]
report("hatted vs node-visit multiplier (in)", abs(Mh_in - Lin/Tn[k_]))

# =======================================================================
print("="*100)
print("RUN B: efficient benchmark (alpha=beta=0, gamma=0)")
gam0 = np.array([0.0, 0.0])
zA = z.copy()
zw = zA.copy()
for t in np.linspace(1.0, 0.0, 9)[1:]:          # homotopy from Run A params to efficient
    zw, res = solve_eq(0.06*t, -0.20*t, gam*t, z0=zw)
alpha, beta = 0.0, 0.0
c = coefs(alpha, beta)
z, res = solve_eq(alpha, beta, gam0, z0=zw)
print(f"  Newton residual: {res:.2e}"); CHECKS.append(("Newton equilibrium residual", float(res), 1e-10))
p = residual_pieces(z, alpha, beta, gam0)
r = p['r']
Ja, _, omega = analytic_J(z, alpha, beta, gam0)
Jf = fd_jac(lambda zz: G(zz, alpha, beta, gam0), z)
report("max|J_analytic - J_fd|", np.max(np.abs(Ja - Jf)), tol=1e-6)
Jinv = np.linalg.inv(Ja)
psi = np.concatenate([(1-sigma)*omega, -sigma*omega])
Xi = p['K']*np.outer(r['P'], r['Q'])/r['Yw']
Tn = r['P']*r['Q']/r['Yw']

# occupation lemma
a_loc = p['sx']
report("s^x = s^y at efficient eqm", np.max(np.abs(p['sx']-p['sy'])))
Theta = r['x']*r['y']/(a_loc*np.sum(r['x']*r['y']))
report("Theta = T (market-access stock)", np.max(np.abs(Theta - Tn)))
Bx = np.diag(a_loc) - np.eye(N) + p['mu']
report("Theta^T B_x = 0", np.max(np.abs(Theta @ Bx)))
report("sum a_i Theta_i = 1", abs(np.sum(a_loc*Theta)-1))
adj = psi @ Jinv
report("psi^T J^-1 = [-Theta, 0]  (x-block)", np.max(np.abs(adj[:N] + Theta)))
report("psi^T J^-1 = [-Theta, 0]  (y-block)", np.max(np.abs(adj[N:])))

# Prop1/Corollary end-to-end + M_in+M_out=1
print("  --- efficient: FD vs Xi_klm ---")
for (k_, l_), m_ in [(edges[1], 0), (edges[6], 1), ((N-1, 0), 0)]:
    if not np.isfinite(kbar[k_, l_, m_]):
        continue
    fd = -welfare_fd(alpha, beta, gam0, k_, l_, m_, z)
    pred = p['s'][k_, l_, m_]*Xi[k_, l_]
    Lin = -psi @ Jinv @ np.eye(2*N)[k_]
    Lout = 0.0 if l_ == N-1 else -psi @ Jinv @ np.eye(2*N)[N+l_]
    print(f"   edge ({k_},{l_},m={m_}): FD={fd:.10f}  Xi_klm={pred:.10f}  |diff|={abs(fd-pred):.2e}   "
          f"M_in+M_out={Lin/Tn[k_]+Lout/Tn[l_]:.10f}")
    CHECKS.append(("B: FD = Xi_klm (Prop 1 / efficient)", abs(fd-pred), 1e-6))
    CHECKS.append(("B: M_in+M_out = 1 (efficient)", abs(Lin/Tn[k_]+Lout/Tn[l_]-1), 1e-6))

# anchored Woodbury
Bxbar = Bx + (sigma-1)*np.outer(a_loc, omega)
report("anchored: (1-sigma) w^T Bxbar^-1 = -Theta", np.max(np.abs((1-sigma)*omega @ np.linalg.inv(Bxbar) + Theta)))
lamT = p['lam'].T
By_full = np.diag(p['sy']) - np.eye(N) + lamT
By = np.vstack([By_full[:N-1, :], np.zeros(N)])
By[N-1, N-1] = -1/(sigma-1)
DG0 = np.block([[Bx, np.zeros((N, N))], [np.zeros((N, N)), By]])
Ux = np.concatenate([(sigma-1)*a_loc, (sigma-1)*a_loc[:N-1], [0]])
Vx = np.concatenate([omega, np.zeros(N)])
Uy = np.concatenate([sigma*a_loc, sigma*a_loc[:N-1], [0]])
Vy = np.concatenate([np.zeros(N), omega])
H = DG0 + np.outer(Ux, Vx)
report("J_eff = DG0 + UxVx^T + UyVy^T", np.max(np.abs(Ja - (H + np.outer(Uy, Vy)))))
Hinv = np.linalg.inv(H)
SM = Hinv - np.outer(Hinv @ Uy, Vy @ Hinv)/(1 + Vy @ Hinv @ Uy)
report("Sherman-Morrison inverse matches J^-1", np.max(np.abs(SM - Jinv)))

# =======================================================================
print("="*100)
print("RUN C: externalities only (alpha=0.06, beta=-0.20, gamma=0) — spillover Woodbury")
alpha, beta = 0.06, -0.20
c = coefs(alpha, beta)
z, res = solve_eq(alpha, beta, gam0, z0=zA)
print(f"  Newton residual: {res:.2e}"); CHECKS.append(("Newton equilibrium residual", float(res), 1e-10))
p = residual_pieces(z, alpha, beta, gam0)
r = p['r']
Ja, _, omega = analytic_J(z, alpha, beta, gam0)
Jinv = np.linalg.inv(Ja)
psi = np.concatenate([(1-sigma)*omega, -sigma*omega])
q = np.concatenate([-c['rho']*omega, -c['rho']*sigma/(sigma-1)*omega])
Xi = p['K']*np.outer(r['P'], r['Q'])/r['Yw']
Tn = r['P']*r['Q']/r['Yw']
# J0 (sparse) and the rank-1 fixed-labor correction written as UV^T with two (parallel-U) columns (I-032)
J0 = Ja.copy()
ux = np.concatenate([(sigma-1)/c['e']*p['sx'], (sigma-1)/c['e']*p['sy'][:N-1], [0]])
uy = np.concatenate([sigma/c['e']*p['sx'], sigma/c['e']*p['sy'][:N-1], [0]])
vx = np.concatenate([omega, np.zeros(N)])
vy = np.concatenate([np.zeros(N), omega])
J0 = Ja - np.outer(ux, vx) - np.outer(uy, vy)
Rm = np.linalg.inv(J0)
U = np.column_stack([ux, uy]); V = np.column_stack([vx, vy])
Om = np.eye(2) + V.T @ Rm @ U
Jw = Rm - Rm @ U @ np.linalg.inv(Om) @ V.T @ Rm
report("spillover Woodbury: J^-1 = R - RU Om^-1 V^T R", np.max(np.abs(Jw - Jinv)))
print("  --- externalities-only: FD vs scalar formula ---")
for (k_, l_), m_ in [(edges[3], 0), (edges[9], 1)]:
    fd = -welfare_fd(alpha, beta, gam0, k_, l_, m_, z)
    Lin = -psi @ Jinv @ np.eye(2*N)[k_]
    Lout = 0.0 if l_ == N-1 else -psi @ Jinv @ np.eye(2*N)[N+l_]
    scal = c['rho']*p['s'][k_, l_, m_]*Xi[k_, l_]*(Lin/Tn[k_]+Lout/Tn[l_])
    print(f"   edge ({k_},{l_},m={m_}): FD={fd:.10f}  scalar={scal:.10f}  |diff|={abs(fd-scal):.2e}")
    CHECKS.append(("C: FD = scalar (externalities only)", abs(fd-scal), 1e-6))

# =======================================================================
# RUN D: the paper's calibration regime (sigma=9, alpha=0.10, beta=-0.30 => e=-0.5, rho=-1.6),
# gamma = (lambda_road, lambda_port) = (0.092, 0.096). Closes the ledger's verification-regime gap
# (only e>0 was exercised before) and asserts rank(J^A)=1 (I-032).
print("="*100)
print("RUN D: paper calibration regime (sigma=9, alpha=0.10, beta=-0.30, gamma=(0.092,0.096))")
sigma = 9.0                       # module-global; all model functions read it dynamically
alpha, beta = 0.10, -0.30
gamD = np.array([0.092, 0.096])
c = coefs(alpha, beta)
print(f"  e={c['e']:.4f}  rho={c['rho']:.4f}")
CHECKS.append(("D: e = -0.5 at paper calibration", abs(c['e'] + 0.5), 1e-12))
CHECKS.append(("D: rho = -1.6 at paper calibration", abs(c['rho'] + 1.6), 1e-12))
z, res = solve_eq(alpha, beta, gamD, z0=0.05*np.random.default_rng(0).standard_normal(2*N))
print(f"  Newton residual: {res:.2e}"); CHECKS.append(("Newton equilibrium residual (D)", float(res), 1e-10))
p = residual_pieces(z, alpha, beta, gamD)
r = p['r']
Ja, _, omega = analytic_J(z, alpha, beta, gamD)
Jf = fd_jac(lambda zz: G(zz, alpha, beta, gamD), z)
report("D: max|J_analytic - J_fd| (e<0 regime)", np.max(np.abs(Ja - Jf)), 1e-6)
# rank-1 fixed-labor feedback (I-032): the two U-columns are parallel, u_x = ((sigma-1)/sigma) u_y
ux = np.concatenate([(sigma-1)/c['e']*p['sx'], (sigma-1)/c['e']*p['sy'][:N-1], [0]])
uy = np.concatenate([sigma/c['e']*p['sx'], sigma/c['e']*p['sy'][:N-1], [0]])
JA = np.outer(ux, np.concatenate([omega, np.zeros(N)])) + np.outer(uy, np.concatenate([np.zeros(N), omega]))
CHECKS.append(("D: rank(J^A) == 1 (I-032)", float(np.linalg.matrix_rank(JA) - 1), 0.0))
print(f"  rank(J^A) = {np.linalg.matrix_rank(JA)}")
psi = np.concatenate([(1-sigma)*omega, -sigma*omega])
q = np.concatenate([-c['rho']*omega, -c['rho']*sigma/(sigma-1)*omega])
Jinv = np.linalg.inv(Ja)
Xi = p['K']*np.outer(r['P'], r['Q'])/r['Yw']
Tn = r['P']*r['Q']/r['Yw']
print("  --- paper regime: FD vs operator vs scalar formula ---")
for (k_, l_), m_ in [(edges[2], 0), (edges[5], 1)]:
    fd = -welfare_fd(alpha, beta, gamD, k_, l_, m_, z)
    chi_vec = chi_wedge(p['s'][k_, l_, :], gamD)
    zeta = p['s'][k_, l_, m_]*chi_vec[m_]
    b = np.zeros(2*N)
    b[k_] = (1-sigma)*zeta*p['mu'][k_, l_]
    if l_ <= N-2:
        b[N+l_] = (1-sigma)*zeta*p['lam'][k_, l_]
    op = q @ Jinv @ b
    Lin = -psi @ Jinv @ np.eye(2*N)[k_]
    Lout = 0.0 if l_ == N-1 else -psi @ Jinv @ np.eye(2*N)[N+l_]
    Msum = Lin/Tn[k_] + Lout/Tn[l_]
    scal = chi_vec[m_]*c['rho']*p['s'][k_, l_, m_]*Xi[k_, l_]*Msum
    print(f"   edge ({k_},{l_},m={m_}): FD={fd:.10f}  qJ^-1b={op:.10f}  scalar={scal:.10f}  "
          f"M_in+M_out={Msum:+.4f}  |FD-op|={abs(fd-op):.2e}  |FD-scal|={abs(fd-scal):.2e}")
    CHECKS.append(("D: FD = operator (paper regime, e<0)", abs(fd-op), 1e-6))
    CHECKS.append(("D: FD = scalar formula (paper regime, e<0)", abs(fd-scal), 1e-6))
    # sign structure at e<0: rho<0 but M_in+M_out<0, so the welfare gain stays positive (ISSUES #8)
    CHECKS.append(("D: welfare gain positive despite rho<0", float(-min(fd, 0.0)), 0.0))
    CHECKS.append(("D: multiplier sum negative at e<0", float(max(Msum, 0.0)), 0.0))

print("="*100)
fails = [(l, v, t) for (l, v, t) in CHECKS if not (v <= t)]
print(f"CHECKS: {len(CHECKS)-len(fails)}/{len(CHECKS)} within tolerance")
for l, v, t in fails:
    print(f"  FAILED  {l}: {v:.3e} > tol {t:.1e}")
if fails:
    print("FAIL"); sys.exit(1)
print("ALL CHECKS PASSED"); print("PASS"); sys.exit(0)
