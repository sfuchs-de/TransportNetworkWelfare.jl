# Public Release Checklist

## Automated gates

- [x] Package, CLI, synthetic examples, and documentation run without private
  data or credentials.
- [x] Julia tests, nonlinear finite differences, algebraic identities, and
  deterministic artifact checks pass.
- [x] `Project.toml`, `CITATION.cff`, changelog, practitioner guide, and locked
  RSUE environment agree on version `0.3.0`.
- [x] Provenance, secret, local-path, helper-artifact, and repository-content
  checks run in CI.
- [x] The tag workflow rebuilds the practitioner guide and publishes its
  SHA-256 checksum.

## External approval gates

- [x] Coauthors approve the code, MIT license, citation, and public
  description.
- [x] The authors reviewed the tracked externally derived guide assets and
  elected to distribute the derived scholarly figures with source attribution.
  This decision does not relicense any source data. See
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- [x] The manuscript identifies the accepted configuration and tagged
  software release.

## Final publication steps

- [x] Run `make public-release-check` from a clean clone.
- [ ] Create and verify tag `v0.3.0`.
- [ ] Confirm the GitHub release contains the checked practitioner-guide PDF
  and checksum.
- [x] Change repository visibility only after the automated and external gates
  above are complete.
