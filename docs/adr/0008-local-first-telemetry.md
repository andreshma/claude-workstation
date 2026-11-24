# 0008. Local-first telemetry

- Status: Accepted
- Date: 2026-11-17

## Context and problem statement

This record was written retroactively, on 2026-11-24. The original text of ADR-008 is not in this repository; the
decision is reconstructed from the changelog (versions 1.8.0 and 1.30.0), from the header of `ws-telemetry` and
`ws-traces.sh`, which name this ADR, and from [ADR 0014](0014-local-opentelemetry-collector.md), which amends it. The
date is the release date of version 1.8.0.

Several Claude Code sessions run all day across repositories and nobody knows what the usage looks like: how many
tokens each turn, session, project and model consumes, what that would cost, and which resources the Claude processes
use on the machine. Claude Code already writes a transcript of every conversation under `~/.claude/projects`, with the
exact token counts of each response.

### Later changes

- Phase F2 (version 1.30.0, 2026-11-19) added hook traces (`ws-traces.sh`), under the same content rule: counts,
  timings and names, never content.
- [ADR 0014](0014-local-opentelemetry-collector.md) relaxes the content rule for the local OpenTelemetry collector
  only: it may store prompt, response and tool text, still on the machine.

## Decision drivers

- Usage must be measurable per turn, session, project, branch and model.
- The text of prompts and responses must not be copied into the telemetry.
- The data must stay on the machine.
- A subscription plan is not billed per token, so cost can only be an equivalent.

## Considered options

The alternatives weighed when the decision was made are not recorded in this repository. The implemented option is the
one described under Decision.

## Decision

Telemetry is local first. `ws-telemetry` reads local sources only, all read-only:

- the Claude Code transcripts (`~/.claude/projects/**.jsonl`): exact tokens per response (input, output, cache written
  and read, reasoning), model, session, folder, branch and subagents; responses repeated by streaming are counted once;
- the terminal copilot's usage records;
- samples of the Claude processes taken every minute from `/proc`: CPU, memory, disk operations and bytes per project.

It never stores the text of prompts or responses: only lengths, counts and tool names. Cost is the equivalent at API
prices, from a price table that `~/.config/ws-telemetry/prices.json` can override. The data lives in
`~/.local/share/ws-telemetry` with mode 0700 and is kept for 13 months. An HTML dashboard is regenerated every minute
and reloads by itself; `ws-telemetry summary` prints a summary and `ws-telemetry sql` queries the data with DuckDB,
which is optional.

## Consequences

- Positive: usage, cost and machine resources are visible per turn, session, project, branch and model without sending
  anything off the machine.
- Positive: cost and token history can be rebuilt from the transcripts Claude Code keeps.
- Negative: costs are API-equivalent prices, not what a subscription plan bills.
- Negative: what does not appear in a transcript or a hook cannot be measured this way (API latency and errors, who
  decides each permission); [ADR 0014](0014-local-opentelemetry-collector.md) covers that gap.
