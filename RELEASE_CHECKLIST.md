# Public Release Checklist

## Automated gates

- [x] Package, CLI, synthetic examples, and documentation run without private
  data or credentials.
- [x] Julia tests, independent finite differences, algebraic identities, and
  deterministic artifact checks pass.
- [x] `Project.toml`, `CITATION.cff`, changelog, practitioner guide, and locked
  RSUE environment agree on version `0.2.0`.
- [x] Provenance, secret, local-path, helper-artifact, and repository-content
  checks run in CI.
- [x] The tag workflow rebuilds the practitioner guide and publishes its
  SHA-256 checksum.

## External approval gates

- [ ] Coauthors approve the code, MIT license, citation, and public
  description.
- [ ] Redistribution terms for tracked externally derived guide assets are
  confirmed, or those assets are removed before public visibility. See
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- [ ] The manuscript identifies the accepted configuration and tagged
  software release.

## Final publication steps

- [ ] Run `make public-release-check` from a clean clone.
- [ ] Create and verify tag `v0.2.0`.
- [ ] Confirm the GitHub release contains the checked practitioner-guide PDF
  and checksum.
- [ ] Change repository visibility only after the automated and external gates
  above are complete.
