# Economic model

The package evaluates derivatives of aggregate welfare with respect to primitive edge-mode transport costs. The spatial equilibrium block allows productivity and amenities to respond to local labor through elasticities ``\alpha`` and ``\beta``. Trade has elasticity ``\sigma``. The current theorem ties route curvature to this trade elasticity; an independent route-elasticity type is reserved but rejected at validation.

## Modal specifications

`ChoiceLogsum(eta)` is the default. It uses a negative-power cost index and yields the conventional substitution response toward a mode whose cost falls.

`ComponentCES(eta)` is the legacy positive-power component index used by the frozen RSUE pipeline. It is retained to reproduce that pipeline, not presented as interchangeable with `ChoiceLogsum`.

The two types change one signed modal-power term throughout the transport linearization. Tests compare both analytic matrices against independent central differences of their nonlinear cost indices.

## Congestion specifications

- `NoCongestion()` removes all congestion feedback.
- `EdgeCongestion(lambda_by_mode)` makes realized edge-mode costs respond to traffic on that edge-mode.
- `EndpointTerminalCongestion(lambda_by_mode)` makes a mode's cost respond to total traffic at both declared endpoint terminals.
- `CompositeCongestion(edge, terminal)` combines the two channels.

Congestion elasticities are nonnegative and mode-specific. A terminal-congested edge-mode must identify both endpoint terminals in the input.

## Maintained conditions

The baseline must be interior, the route kernel must be contractive, exposure stocks must be positive, and the spatial and transport systems must be nonsingular. The regularity scalar is

```math
e=1+\beta(\sigma-1)+\alpha\sigma.
```

Sensitivity paths remain on the baseline sign branch of ``e``, retain net dispersion, and stay away from singular boundaries. The package never applies ridge regularization.
