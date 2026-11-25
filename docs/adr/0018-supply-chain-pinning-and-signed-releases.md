# 0018. Supply-chain pinning and signed kit releases

- Status: Accepted
- Date: 2026-11-25

## Context and problem statement

Referred to in code and changelog as ADR-018.

Everything the kit installs runs with the owner's privileges, and the MCP servers run outside the sandbox. The
compliance assessment ([docs/compliance/assessment.md](../compliance/assessment.md)) found:

- **WS-AI-009 (high).** The Azure MCP server was a beta resolved by `npx -y` on every start, with no lock file or
  integrity hash for its dependencies; the local MCP executables (MemPalace, recall) had no checksum; `ws-update`
  dropped the prerelease suffix when comparing versions.
- **WS-SEC-015 (high).** `ws-kit-update` pulled the branch tip with `--ff-only`: whoever could push to the remote
  changed hooks and settings on every workstation at the next update.
- **WS-SEC-016, WS-SEC-017, WS-SEC-018.** CI actions were pinned by tag, CodeQL kept checkout credentials, and the
  kit published no SBOM.

The question: how should third-party code reach the workstation, and how does a workstation know that a kit update
comes from the maintainer?

## Decision drivers

- No code may arrive through a moving reference (a tag, a branch tip, `npx -y`, `latest`) without a review
  (OWASP ASI04; NIST SSDF PS.2, PW.4; SLSA-style provenance).
- A compromised remote or a compromised maintainer account alone must not be enough to change every workstation.
- Forks without the maintainer's key must still be able to update, visibly.
- Pin bumps must stay cheap: Dependabot proposes, a human merges.

## Considered options

- **A. Keep `npx -y` and branch updates, add `npm audit` and a changelog check.** Little work; still trusts whatever
  the registry or the remote serves at that moment.
- **B. Vendor every package into the repository.** Exact, but heavy, and the kit would redistribute third-party code.
- **C. Committed lock files with integrity, `npm ci --ignore-scripts`, trust on first use for local executables, and
  SSH-signed release tags verified against a key the workstation already has (chosen).**
- **D. Sigstore or cosign for releases.** Strong provenance; needs an identity provider and tooling the workstation
  does not have, for a single maintainer.

## Decision

Option **C**.

- **npm packages.** Each pinned package has a committed `package.json` and `package-lock.json` (sha512 of every
  tarball) under `files/home/.local/lib/ws-npm/<name>/` (azure-mcp, chrome-devtools-mcp, agent-browser).
  `ws-pinned install` runs `npm ci --ignore-scripts` into `~/.local/share/ws-kit/npm/<name>` and records a hash of the
  installed tree; `ws-pinned verify [--online]` checks the lock, the version, the integrity and the tree hash
  (`--online` adds `npm audit signatures`). `files/mcp-servers.lock.json` records each MCP server: npm servers by
  package, version and integrity, remote servers by URL, local ones as `trust: first-use`.
- **Azure MCP** runs from the pinned install (`@HOME@/.local/share/ws-kit/npm/azure-mcp/node_modules/.bin/azmcp`), still
  on `4.0.0-beta.7`; the lock records why (`prereleaseReason`: the ask rules were written against the 4.0 beta tool
  names; 3.0.0 was not checked).
- **Local MCP executables.** `install.sh` pins the sha256 of `mempalace` and `recall` on first registration
  (`~/.local/share/ws-kit/mcp-trust.tsv`); a later mismatch skips that server with a warning until the owner runs
  `bash install.sh --mcp-accept NAME`. A server missing from the lock is not registered.
- **Opt-in servers.** `chrome-devtools` is in the lock with `optIn: true` and is registered only with
  `--mcp-opt-in chrome-devtools`.
- **Kit updates.** `ws-kit-update` fetches only `vX.Y.Z` tags into `refs/ws-kit/tags`, takes the newest ahead of
  `HEAD`, requires an annotated tag whose name matches, runs `git verify-tag` with the **installed**
  `~/.config/ws-kit/allowed_signers` (plus `allowed_signers.local` for forks), and moves with `git merge --ff-only
  <tag>`. A refusal exits 11 and raises a Telegram security alert; `--allow-unsigned` is logged to
  `~/.local/state/ws-kit-update.log` and reported over Telegram. Rollback through `ws-test` is unchanged.
- **CI.** Actions pinned by commit SHA with the version as a comment; `persist-credentials: false` everywhere; zizmor
  checks the workflows; `release.yml` refuses an unsigned or lightweight tag and attaches a CycloneDX SBOM built by
  `.github/scripts/sbom.py`; Dependabot covers actions and the pinned npm packages with a 7-day cooldown.

## Consequences

- Positive: nothing third-party changes on a workstation without a committed, reviewed pin; a pushed commit or tag
  without the maintainer's signature is not installed.
- Positive: the signature check uses the key already on the machine, so a release cannot vouch for itself.
- Negative (breaking): until the maintainer's public key is added to `files/home/.config/ws-kit/allowed_signers`,
  `ws-kit-update` refuses every release (exit 11) unless `--allow-unsigned` is used.
- Negative: the maintainer must sign every release tag (`docs/runbook.md`, "Signing a release") and keep the key safe;
  losing it means a new key shipped through a manually verified update.
- Negative: a pin bump is now three edits (package.json, package-lock.json, `files/mcp-servers.lock.json`);
  `tests/supply-chain.sh` fails until they agree.
- Still open: the Azure server stays on a beta; MCP servers are not confined (`ws-mcp-jail` is not built); tmux
  plugins and TPM are still cloned at the branch tip; `ws-tools` still trusts the checksum file published next to
  each binary; trust on first use cannot detect an executable that was already compromised when first pinned.
