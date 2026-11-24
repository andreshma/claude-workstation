# Security Policy

claude-workstation configures tmux, Claude Code hooks and helper scripts on a developer workstation (WSL2 on Windows).
This document explains the security model and how to report a vulnerability.

## Supported versions

| Version | Security fixes |
|---|---|
| 2.x | Yes |
| < 2.0 | No — upgrade with `ws-actualizar` |

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.** Use GitHub's private vulnerability reporting:
<https://github.com/andreshma/claude-workstation/security/advisories/new>. Include the affected version or commit, the
impact and reproduction steps (describe the class of problem; no weaponized exploit). The maintainer (GitHub:
andreshma) aims to acknowledge within **5 business days**, agrees a disclosure date with you and credits you unless
you prefer otherwise.

## Security model

- **Secrets** live only in the Windows Credential Manager (`ws-secret`, DPAPI). Tokens are passed to tools through file
  descriptors, never argv. The repository contains no credentials; exports are scanned before every commit.
- **Telemetry is local** (`~/.local/share/ws-telemetria`, 0700). Usage data built from transcripts and hooks holds
  counts, timings and tool names. The local OpenTelemetry collector (`ws-otel`, ADR-014) listens only on `127.0.0.1`
  and also stores the text of prompts, responses and tool calls, with recognizable secrets masked;
  `WS_OTEL_CONTENIDO=0` turns content off. That folder must stay out of unencrypted backups and cloud sync. What goes
  to Telegram or into Claude summaries is redacted first (`ws-redactar`).
- **Telegram control** answers only the owner's chat, with one-time codes that expire in 10 minutes, closed options,
  no button for dangerous commands, and free-text replies only with a PIN.
- **Claude Code protection levels** per tab (ADR-012, ADR-013): full (sandbox without excluded commands + ask/deny
  rules + guard hook), normal, and pure (no sandbox and no workstation allow/ask rules). A floor stays on in every
  level: the deny rules and the guard hook. Organization managed settings still apply.
- **Supply chain**: CI pins no third-party actions; gitleaks is verified by checksum; Dependabot watches workflows.
