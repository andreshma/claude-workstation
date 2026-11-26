#!/usr/bin/env bash
#
# tests/redaction-out.sh — text that leaves the terminal is redacted (WS-SEC-009): a tmux-record recording is redacted
# in place when it stops (every output event, the JSON kept valid, plain events untouched, WS_RECORD_KEEP_RAW keeps a
# 0600 raw copy), and the Windows toast of win-notify.sh goes through ws-redact before PowerShell sees it.
#
# Usage: bash tests/redaction-out.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
export HOME="$T/home"; mkdir -p "$HOME/.local/lib"
cp "$ROOT/files/home/.local/lib/ws_mcp_policy.py" "$HOME/.local/lib/"
R="$ROOT/files/home/.local/bin/tmux-record"
tok="ghp_$(printf 'K%.0s' {1..36})"
{ echo '{"version": 2, "width": 80, "height": 24}'
  printf '[0.5, "o", "export TOKEN=%s\\r\\n"]\n' "$tok"
  printf '[0.9, "o", "Authorization: Bearer abcdefghijklmnop\\r\\n"]\n'
  printf '[1.2, "o", "plain output\\r\\n"]\n'; } > "$T/r.cast"
n="$(bash "$R" --redact "$T/r.cast")"
check "the recording is redacted in place (2 events changed)" test "$n" == 2
check "no secret is left" bash -c "! grep -q '$tok' '$T/r.cast' && ! grep -q abcdefghijklmnop '$T/r.cast'"
check "the file is still valid asciicast (JSON lines)" bash -c "jq -e . '$T/r.cast' >/dev/null"
check "plain events are untouched" grep -qF '[1.2, "o", "plain output\r\n"]' "$T/r.cast"
check "the stop path keeps a 0600 raw copy only with WS_RECORD_KEEP_RAW=1" grep -q 'WS_RECORD_KEEP_RAW:-0}" == 1' "$R"
check "the stop path redacts before the gif is made" bash -c "awk '/red=\"\\\$\\(redact_cast/{r=NR} /agg --quiet/{a=NR} END{exit !(r && a && r < a)}' '$R'"
W="$ROOT/files/home/.claude/hooks/win-notify.sh"
check "win-notify redacts the toast title and text" bash -c "grep -q 'title=\"\$(\"\$HOME/.local/bin/ws-redact\" <<<\"\$title\")\"' '$W' && grep -q 'body=\"\$(\"\$HOME/.local/bin/ws-redact\" <<<\"\$body\")\"' '$W'"
check "…before the PowerShell script is built" bash -c "awk '/ws-redact\" <<<\"\\\$body/{r=NR} /^ps=/{p=NR} END{exit !(r && p && r < p)}' '$W'"
check "shellcheck tmux-record and win-notify.sh" shellcheck -S warning "$R" "$W"

echo
echo "Result: $PASS ok · $FAIL failed"
(( FAIL == 0 ))
