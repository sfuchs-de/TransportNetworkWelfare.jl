# Numerical diagnostics and failures

Validation precedes model construction. It checks identifiers, endpoints, positive flows, terminal fields, physical-link pairing, units, declared transformations, exposure-stock accounting, and route contraction.

Each analysis records:

- route spectral radius, absorption error, bilateral row and column errors, and edge-traffic reconstruction error;
- condition numbers for `NC`, `NT`, `F`, `FM`, and `FR` and their transport systems;
- transport solve residuals;
- closure-ladder, inverse-gap, and Hulten-accounting residuals;
- package, configuration, input, and output hashes.

The default condition-number ceiling is ``10^{12}`` and the identity tolerance is ``10^{-10}``. A failed factorization or condition gate stops the run. There is no ridge fallback.

Common failures are actionable:

- `route kernel is not contractive`: absorption shares or flows do not define a terminating route process;
- `exposure stocks differ`: node-level outgoing and incoming traffic accounting is inconsistent;
- `physical link ... must have exactly two policy directions`: an opposite directed policy row is absent or misidentified;
- `missing ... terminal_id`: terminal congestion is active without a declared endpoint;
- `leaves the baseline regular branch`: a sensitivity path crosses ``e=0``;
- `RSUE input hash mismatch`: the external file is not the audited vintage.
