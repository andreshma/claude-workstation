# Architecture Decision Records

This folder holds the architecture decisions of claude-workstation in [MADR](https://adr.github.io/madr/) format: one
file per decision, with its context, the options considered, the decision and its consequences. A record is immutable
once accepted: a later decision does not edit it, it adds a new record that supersedes or amends the earlier one. Code
comments and the changelog refer to a record as `ADR-0NN` (for example `ADR-013` for record 0013).

| # | Title | Status |
|---|---|---|
| 0001 | Not recorded in this repository | Not applicable |
| 0002 | Not recorded in this repository | Not applicable |
| 0003 | Not recorded in this repository | Not applicable |
| 0004 | Not recorded in this repository | Not applicable |
| 0005 | Not recorded in this repository | Not applicable |
| 0006 | Not recorded in this repository | Not applicable |
| 0007 | Not recorded in this repository | Not applicable |
| [0008](0008-local-first-telemetry.md) | Local-first telemetry | Accepted, amended by [0014](0014-local-opentelemetry-collector.md) |
| [0009](0009-model-routing-with-confirmation.md) | Model routing per task, with confirmation | Accepted |
| [0010](0010-telegram-remote-control.md) | Notifications and replies over Telegram | Accepted, amended by [0013](0013-minimum-protection-floor.md) |
| [0011](0011-personal-configuration.md) | Personal configuration versioned outside the kit | Accepted |
| [0012](0012-per-tab-protection.md) | Three per-tab protection levels for Claude | Accepted, partly superseded by [0013](0013-minimum-protection-floor.md) and, for solo mode, by [0016](0016-solo-mode-inside-the-sandbox.md) |
| [0013](0013-minimum-protection-floor.md) | A minimum protection floor that no mode turns off | Accepted, implemented in phases; strict base and managed policy in [0019](0019-strict-base-and-level-profiles.md) |
| [0014](0014-local-opentelemetry-collector.md) | Local OpenTelemetry collector and full on-machine logging | Accepted |
| [0015](0015-english-names-and-language-selector.md) | English names and a language selector | Accepted |
| [0016](0016-solo-mode-inside-the-sandbox.md) | Solo mode inside the sandbox, with an expiry | Accepted, amended by [0022](0022-solo-mode-without-excluded-commands.md) |
| [0017](0017-defence-in-depth-for-agent-configuration.md) | Defence in depth for agent configuration and untrusted content | Accepted |
| [0018](0018-supply-chain-pinning-and-signed-releases.md) | Supply-chain pinning and signed kit releases | Accepted |
| [0019](0019-strict-base-and-level-profiles.md) | Strict base settings with level profiles and an optional managed drop-in | Accepted |
| [0020](0020-agent-scoped-identities.md) | Agent-scoped identities per tab | Accepted, amended by [0021](0021-per-tab-profiles.md) and [0023](0023-git-gate-agent-trailer-and-throwaway-repositories.md) |
| [0021](0021-per-tab-profiles.md) | Per-tab profiles: Claude organisation, Azure tenant, credentials and memory per tab | Accepted |
| [0022](0022-solo-mode-without-excluded-commands.md) | Solo mode keeps every command in the sandbox; network tools are an audited, time-boxed opt-in that asks | Accepted |
| [0023](0023-git-gate-agent-trailer-and-throwaway-repositories.md) | Git gate: an Agent-Session trailer on agent commits, and throwaway repositories | Accepted |
| [0024](0024-mcp-server-confinement-and-allow-list.md) | Local MCP servers in bubblewrap (ws-mcp-jail) and a managed MCP allow list | Accepted |

Records 0001 to 0007 are not in this repository. Its history mentions 0001 to 0006 only as part of a design
document that was never part of it, and nothing mentions 0007; the code, the changelog and the other documents do not
refer to any of them, so they are not reconstructed here. Records 0008 to 0010 were recorded retroactively from the
changelog and the code that implements them; each says so in its context.

To add a record, copy [template.md](template.md) to `NNNN-kebab-title.md` with the next number, fill in every section,
add a row to this table and link the record from the pull request that implements the decision.
