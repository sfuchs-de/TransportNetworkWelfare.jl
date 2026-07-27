# Mathematical Result Cards

## 1. Primitive policy elasticity

- **Why it is needed:** Link rankings require one policy object with a fixed
  sign and unit.
- **Objects:** \(\theta_{klm}=\log\bar\kappa_{kl,m}\) and aggregate welfare
  \(W\).
- **Result:** \(E_{klm}=-d\log W/d\theta_{klm}\).
- **Interpretation:** A positive value is the welfare gain from a primitive
  cost reduction. Multiplication by a small shock fraction gives the
  first-order log-welfare change.
- **Next use:** Defines every Hulten, realized-cost, and primitive-cost output.

## 2. Recursive route resolvent

- **Why it is needed:** Bilateral route costs and edge incidence must be
  reconstructed from a directed network without enumerating paths.
- **Objects:** Substochastic continuation matrix \(K\), source margin \(o\),
  destination absorption vector \(a\).
- **Assumption:** \(\rho(K)<1\).
- **Derivation route:** Iterate the local route recursion to obtain
  \(T=I+K+K^2+\cdots=(I-K)^{-1}\), then form
  \(X^{OD}=\operatorname{diag}(o)T\operatorname{diag}(a)\).
- **Interpretation:** \(K^r\) collects weighted walks of length \(r\);
  differentiating the resolvent gives flexible route incidence.
- **Next use:** Supplies route derivatives and the fixed-route comparison.

## 3. Negative-power modal logsum

- **Why it is needed:** Several modes may serve the same directed edge.
- **Objects:** Realized modal costs \(\kappa_{e,m}\) and substitution
  parameter \(\eta>0\).
- **Result:**
  \[
  \kappa_e=\left(\sum_m\kappa_{e,m}^{-\eta}\right)^{-1/\eta},
  \qquad
  s_{e,m}=\frac{\kappa_{e,m}^{-\eta}}
  {\sum_n\kappa_{e,n}^{-\eta}}.
  \]
- **Interpretation:** \(s_{e,m}\) is both the aggregate-cost elasticity and
  modal traffic share under the maintained logsum. Baseline shifters
  rationalize observed shares; \(\eta\) governs local substitution.
- **Next use:** Aggregates edge-mode shocks and defines modal traffic.

## 4. Efficient Hulten benchmark

- **Why it is needed:** Traffic is the natural comparator for the extended
  derivative.
- **Scope:** Economic geography with \(\alpha=\beta=0\), zero congestion, and
  an interior efficient equilibrium.
- **Result:**
  \[
  -\frac{d\log W}{d\log\bar\kappa_{kl,m}}=\Xi_{kl,m}.
  \]
- **Derivation route:** The envelope theorem removes the first-order welfare
  value of induced reallocations, leaving the direct resource saving.
- **Interpretation:** Adjustment can be large even though its first-order
  welfare contribution vanishes at the efficient baseline.
- **Next use:** Unit test and reference point for the extended statistic.

## 5. IFT and adjoint welfare derivative

- **Why it is needed:** Congestion and spatial externalities give induced
  reallocations first-order welfare value.
- **Objects:** Closure residual \(G_c(z_c,\theta)=0\), Jacobian \(J_c\),
  welfare row \(q_c^\top\), forcing \(b_{c,p}=G_{c,\theta_p}\).
- **Assumption:** Interior differentiability and nonsingular \(J_c\).
- **Substitution chain:**
  \[
  J_cdz_c+b_{c,p}d\theta_p=0
  \Rightarrow
  \frac{dz_c}{d\theta_p}=-J_c^{-1}b_{c,p}
  \Rightarrow
  E_{c,p}=q_c^\top J_c^{-1}b_{c,p}.
  \]
  Solving \(J_c^\top\psi_c=q_c\) yields
  \(E_{c,p}=\psi_c^\top b_{c,p}\).
- **Interpretation:** One adjoint solve prices every candidate policy forcing.
- **Appendix link:** Appendix B records the computational sequence.

## 6. Transport Schur complement and primitive forcing

- **Why it is needed:** Route, mode, and congestion responses are joint
  endogenous objects rather than separate corrections.
- **Objects:** \(Q_{z_c}^S,C^S,\Gamma^S,S_{\mathrm{agg}}\), and
  \(B_{\kappa,c}\).
- **Substitution chain:**
  \[
  d\xi=Q_{z_c}^Sdz_c+C^Sdh,\qquad
  dh=d\theta+\Gamma^Sd\xi,
  \]
  hence
  \[
  dh=(I-\Gamma^SC^S)^{-1}
  (d\theta+\Gamma^SQ_{z_c}^Sdz_c).
  \]
  The \(dz_c\) term augments the spatial Jacobian; the \(d\theta\) term forms
  the primitive forcing after cost aggregation and spatial loading.
- **Interpretation:** The same transport system governs state feedback and
  primitive-to-user pass-through.
- **Appendix link:** Appendix B expands the modal, route, and congestion
  matrices used by `primitive_forcing`.

## 7. Economic-geography Proposition 2 factorization

- **Why it is needed:** The adjoint derivative computes link effects but does
  not expose why equal-traffic links can rank differently.
- **Objects:** Traffic \(\Xi_{kl,m}\), pass-through \(\chi_{klm}\), common
  scale \(\rho=(1+\alpha+\beta)/e\), and endpoint multipliers
  \(\mathcal M_k^{in},\mathcal M_l^{out}\).
- **Result:**
  \[
  -\frac{d\log W}{d\theta_{klm}}
  =\chi_{klm}\rho\Xi_{kl,m}
  (\mathcal M_k^{in}+\mathcal M_l^{out}).
  \]
- **Interpretation:** Traffic fixes direct exposure; pass-through measures
  transport attenuation; \(\rho\) is common across links; access multipliers
  generate link-specific equilibrium incidence.
- **Limit check:** Setting \(\alpha=\beta=0\), congestion to zero, and the
  multiplier sum to one recovers Hulten.
- **Scope:** This scalar factorization is not the urban formula.

## 8. Urban welfare projection

- **Why it is needed:** Residence and workplace choices imply a different
  welfare row from trade.
- **Objects:** \(z_U=(d\log l^R,d\log l^F,d\log\varpi_U)\) and
  \(q_U^\top=(0,\ldots,0,-1/\theta_U)\).
- **Result:** \(E_{U,p}=q_U^\top J_{U,S}^{-1}b_{U,p}^\theta\).
- **Interpretation:** The transport derivative is shared, while the state
  response and welfare projection are urban-specific.
- **Next use:** Supports multimodal transit policies and urban closure gaps.

## 9. Closure ladder and inverse-gap identity

- **Why it is needed:** Mechanism comparisons should not be confounded by
  separate recalibration.
- **Objects:** Common-baseline closures \(NC,NT,F,FM,FR\).
- **Identity:**
  \[
  J_A^{-1}-J_B^{-1}=J_A^{-1}(J_B-J_A)J_B^{-1}.
  \]
- **Economic-geography ladder:**
  \[
  m_F=m_{NC}-d_{edge}-d_{terminal}
  =m_{FM}+d_{mode}=m_{FR}+d_{route}.
  \]
- **Interpretation:** Congestion terms form an additive ladder; mode and route
   wedges are alternative comparisons with the full closure.
- **Subcomponents:** The general mixed update separates allocation, scarcity,
  and aggregate-equilibrium terms. Under the current common-baseline
  specification, the first and third terms are exact zeros, so scarcity carries
  each closure wedge.
- **Appendix link:** Appendix B records the structured and rank-two updates.

## 10. Hulten-gap accounting

- **Why it is needed:** The difference between traffic and the primitive
  derivative can contain large offsetting components.
- **Derivation route:** Substitute
  \(E_{e,F}^r=\rho\Xi_em_{e,F}\), the closure ladder, and
  \(E_{e,F}^\theta=\chi_e^{eff}E_{e,F}^r\).
- **Result:** The gap separates common externality scaling, propagation,
  edge congestion, terminal congestion, and primitive-cost pass-through.
- **Interpretation:** Components are signed levels. Percentage shares are
  inappropriate when their net sum is small.
- **Next use:** Interprets the grid and freight result vintages.
