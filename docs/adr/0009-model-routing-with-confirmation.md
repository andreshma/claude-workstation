# 0009. Model routing per task, with confirmation

- Status: Accepted
- Date: 2026-11-18

## Context and problem statement

This record was written retroactively, on 2026-11-24. The original text of ADR-009 is not in this repository; the
decision is reconstructed from the changelog (versions 1.10.0, 1.17.0 and 1.32.2) and from the headers of
`ws-ruteo.sh` (hook and library), `cr`, `reglas.conf` and `ajustes.conf`, which name this ADR. The date is the release
date of version 1.10.0, which the changelog labels "ADR-009, R1".

Every task runs on whatever model the tab has, which is usually the most expensive one. The work falls into tiers
that fit different models: architecture and exhaustive analysis, day-to-day work and debugging, SQL and scoped
changes, searches and simple questions. A model must not change without the user's answer.

### Later changes

- Version 1.17.0: moving down a model is only proposed with little context (below 30 %, `bajar_max_ctx` in
  `~/.config/ws-ruteo/ajustes.conf`). With more context, changing the model re-reads everything without cache and
  costs more than it saves: the hook does not block and suggests the cheap subagent to Claude instead (`sql-rapido`
  for SQL, `explorador` for searches). Moving up a model still always asks.
- Version 1.32.2: the input box is cleared before `/model` is typed, and the hook does not ask in the 2 minutes after
  a change or when the text carries a pasted `/model`.

## Decision drivers

- The model should fit the task: architecture and exhaustive analysis, day-to-day work and debugging, SQL and scoped
  changes, searches and simple questions.
- Nothing changes without the user's answer.
- The typed text must not be lost and the user's default model must not change.
- One rule table for every entry point.

## Considered options

The alternatives weighed when the decision was made are not recorded in this repository. The implemented option is the
one described under Decision.

## Decision

Route the model per task, always with the user's confirmation.

- A single rule table, `~/.config/ws-ruteo/reglas.conf`, serves the Claude Code hook and the `cr` command. Each line is
  `level|id|regular expression`; the first match wins. With no match the level is `opus`, and the hook does not ask.
- The UserPromptSubmit hook (`ws-ruteo.sh`): if a rule says the task belongs to a different tier than the tab's model,
  it stops the submission, saves the text (mode 0600, deleted once used) and opens a popup with three choices: switch
  and send, send with the current model, or give the text back for editing. With no answer in 30 seconds it sends with
  the current model. A failure in the hook never blocks Claude.
- `cr "task"` classifies, explains (`--explica`), simulates (`--dry-run`), forces a tier (`-t`) and sends the task to
  the tab's Claude with the right model. With no matching rule it asks Haiku, with the text redacted; with confidence
  below 0.7 it goes up one tier. `cr --probar` runs 20 labeled tasks against the rules.
- The tab's model changes with `/model`; the user's default model is not touched.
- A menu sets the model of the tab by hand and turns automatic routing on or off.
- Subagents by tier: `arquitecto`, `depurador`, `sql-rapido` and `explorador`. A fallback model applies, for that turn
  only, when the main model is overloaded or down.
- Routing decisions are recorded in the telemetry (`~/.local/share/ws-telemetria/ruteo/`), without the text of the
  tasks.

## Consequences

- Positive: tasks that match a rule run on the tier that fits them, and the user decides each switch.
- Positive: the hook, the command and the menu classify the same way, because they share one table.
- Negative: the rules are regular expressions over the prompt text and have to be maintained; `cr --probar` must stay
  at 90 % or more.
- Negative: changing the model in a conversation with a lot of context re-reads everything without cache, which is why
  moving down is limited to little context.
- Negative: a confirmation popup interrupts the submission for up to 30 seconds when a rule matches.
