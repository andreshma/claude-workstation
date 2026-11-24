# Governance

## Roles

- **Maintainer** — [@andreshma](https://github.com/andreshma). Reviews and merges pull requests, triages issues,
  cuts releases and handles security reports. The maintainer has the final say on scope and design.
- **Contributors** — anyone who opens an issue, a discussion or a pull request. Contributors who keep making good
  changes may be invited as maintainers.

## How decisions are made

- Day-to-day changes are decided in the pull request that makes them.
- Changes to an architectural decision (anything in [docs/adr/](docs/adr/)) need a new or superseding ADR in the same
  pull request.
- Larger proposals start as a [Discussion](https://github.com/andreshma/claude-workstation/discussions) so the design
  can be agreed before anyone writes code.

## Merging

Contributions arrive as pull requests with green CI (shellcheck, Python compile and bandit, secret scan,
isolated behavior tests). Force pushes and deletion of `main` are blocked.

## Releases

Versions follow [Semantic Versioning](https://semver.org/). Each release has a section in [CHANGELOG.md](CHANGELOG.md),
a `vX.Y.Z` tag and a GitHub release; `CITATION.cff` carries the same version.

## Security

Vulnerabilities are handled privately as described in [SECURITY.md](SECURITY.md).

## Code of conduct

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
