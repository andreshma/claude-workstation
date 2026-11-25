# Security policy

claude-workstation configures tmux, Claude Code hooks and helper scripts on a developer workstation (WSL2 on Windows).
This document explains which versions are supported, how to report a vulnerability and the security model.

## Supported versions

| Version | Security fixes |
|---|---|
| 3.x | Yes |
| 2.x | Security fixes only, until the wrappers for the old command names are removed (the next major version) |
| < 2.0 | No; upgrade with `ws-kit-update` |

## Reporting a vulnerability

**Do not open a public issue for security vulnerabilities.** Use GitHub's private vulnerability reporting:
<https://github.com/andreshma/claude-workstation/security/advisories/new>. Include the affected version or commit, the
impact and reproduction steps (describe the class of problem; no weaponized exploit). The maintainer (GitHub:
andreshma) aims to acknowledge within **5 business days**, agrees a disclosure date with you and credits you unless
you prefer otherwise.

## Security model

The full analysis, with residual risks, is in [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md).

- **Secrets** live only in the Windows Credential Manager (`ws-secret`, DPAPI). Tokens are passed to tools through file
  descriptors, never argv. The repository contains no credentials; exports are scanned before every commit.
- **Telemetry is local** (`~/.local/share/ws-telemetry`, 0700). Usage data built from transcripts and hooks holds
  counts, timings and tool names. The local OpenTelemetry collector (`ws-otel`,
  [ADR 0014](docs/adr/0014-local-opentelemetry-collector.md)) listens only on `127.0.0.1` and also stores the text of
  prompts, responses and tool calls, with recognizable secrets masked; `WS_OTEL_CONTENT=0` turns content off. That
  folder must stay out of unencrypted backups and cloud sync. What goes to Telegram or into Claude summaries is
  redacted first (`ws-redact`).
- **Telegram control** answers only the owner's chat, with one-time codes that expire in 10 minutes, closed options,
  no button for dangerous commands, and free-text replies only with a PIN.
- **Claude Code protection levels** per tab ([ADR 0012](docs/adr/0012-per-tab-protection.md),
  [ADR 0013](docs/adr/0013-minimum-protection-floor.md)): full (sandbox without excluded commands + ask/deny rules +
  guard hook), normal, and pure (`bare`: no sandbox and no workstation allow/ask rules). A floor stays on in every
  level: the deny rules and the guard hook. Organization managed settings still apply.
- **Supply chain**: CI pins no third-party actions; gitleaks is verified by checksum; Dependabot watches workflows.
- **Upgrades from 2.x**: the installer moves data to the English names without overwriting, and the sandbox deny
  rules cover the credential and telemetry folders under both their old and their new paths while the old ones may
  still exist.
