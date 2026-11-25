#!/usr/bin/env bash
#
# config-change.sh — ConfigChange hook: records in the audit log (audit.sh, event «config-change») every settings,
# policy or skill file that changes while a session runs, with its source and path (WS-AI-014). guard.sh blocks the
# agent's own writes it can see; this leaves a trace of the ones it cannot (a script, an editor, another process)
# and of yours, so a review of the log shows when the configuration that steers the agent moved.
# Observing only: it never blocks the change and exits 0 on any error.
# Usage: ConfigChange hook (hook JSON on stdin). Tests: bash tests/hooks-settings.sh
set -uo pipefail
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
what="$(jq -r '[(.source // "unknown"), (.file_path // empty)] | join(" ")' <<<"$input" 2>/dev/null)" || exit 0
"$HOME/.claude/hooks/audit.sh" config-change "${what:-unknown}" <<<"$input" >/dev/null 2>&1
exit 0
