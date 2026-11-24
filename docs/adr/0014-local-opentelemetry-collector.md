# 0014. Local OpenTelemetry collector and full on-machine logging

- Status: Accepted
- Date: 2026-11-20

## Context and problem statement

Referred to in code and changelog as ADR-014. This record amends
[0008](0008-local-first-telemetry.md), local-first telemetry, on one point: content may now be stored, locally only.

The kit's telemetry came from two sources: the Claude Code transcripts
(tokens, words, turns) and the hooks (tools, timings, permissions requested).
What does not go through a hook was missing:

- every API call with its duration, tokens and cost;
- API errors with their code and retries;
- who decides each permission (a rule, a hook or the person);
- the person's active time and Claude's; the commits, lines and PRs that
  Claude Code itself counts;
- how long hooks, compactions, subagents and MCP connections take.

Claude Code emits all of that through OpenTelemetry (metrics, events, and
traces in beta). In addition, the owner decided not to discard anything: the
data is used to analyze, project and estimate AI-assisted work, and it stays
on their machine. ADR-008 forbade storing content (prompts, commands,
outputs); that rule is relaxed here, for this collector only.

## Decision drivers

- What does not go through a hook must be measurable: API calls, API errors, permission decisions, active time.
- The owner decided not to discard anything: the data is used to analyze, project and estimate AI-assisted work.
- The data must stay on the machine.
- Secrets must not sit in clear text on disk.
- No extra binary to install, verify and update.

## Considered options

| Option | For | Against |
|---|---|---|
| Own local collector, `ws-otel` (chosen) | See Consequences | See Consequences |
| Official OpenTelemetry Collector with a file exporter | Standard, many processors | One more binary to install, verify and update; a lot for writing to a file |
| Keep only hooks and transcripts | Nothing new to operate | API latency and errors and the origin of each permission cannot be measured that way |
| Export to a cloud service | Ready-made, shared dashboards | The data leaves the machine; with content turned on that is not acceptable |
| Store without content (counts only) | Lower risk on disk | The owner asked not to discard anything; it remains as an optional mode (`WS_OTEL_CONTENT=0`) |

## Decision

1. **Own, local collector** (`ws-otel`): a small HTTP server in Python, with
   no dependencies, that listens only on `127.0.0.1:14318`, receives OTLP as
   `http/json`, flattens each signal to one line and stores it in
   `~/.local/share/ws-telemetry/otel/YYYY-MM-DD.jsonl` (directory 0700, files
   0600). It compresses after 35 days and deletes after 13 months. The tmux
   watchdog starts it if it is not running.
2. **Claude Code exports everything it can** (`env` in
   `~/.claude/settings.json`): metrics, events and traces; prompt and response
   text, tool parameters and content, version, entry point and repository.
3. **Everything is stored, with secrets masked.** Tokens, keys and passwords
   recognizable by their shape are replaced with `[SECRET]`: they add nothing
   to the analysis and must not sit in clear text on disk.
   `WS_OTEL_CONTENT=0` returns the collector to content-free mode (only
   counts, timings and names).
4. **Raw API bodies are not turned on** (`OTEL_LOG_RAW_API_BODIES`): every
   request repeats the full context, it would be gigabytes per day, and that
   conversation is already complete in the Claude Code transcripts.
5. **The reports add the new data**: the dashboard and `ws-report` show API
   (latency, first token, errors by code, exhausted retries, cost by origin),
   permissions by source, active time, hooks, compactions, subagents, MCP and
   skills, and a block of **ratios for estimating** (text, model, cost and
   machine per turn, per word and per token).

## Consequences

- Positive: the measurement gaps are covered without depending on an external
  service; the format is standard and can later be forwarded to another
  destination by changing the exporter.
- Positive: there is a numeric basis for estimating: words and tokens per
  turn, calls per turn, cost per active hour, CPU and disk per token.
- Negative: **the disk now stores the text of prompts, responses, commands and
  outputs.** Secret masking is pattern-based: a secret with an unrecognized
  shape can remain in clear text. The directory must stay out of unencrypted
  backups and out of any cloud sync.
- Negative: **if the endpoint is changed to an external destination, that
  content would leave the machine.** Before doing so, the content options must
  be turned off (`OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_ASSISTANT_RESPONSES`,
  `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT`).
- Negative: traces are beta in Claude Code and may change; disk volume grows
  noticeably with content.
- Negative: export is enabled when Claude starts: open tabs emit nothing until
  they are restarted.
