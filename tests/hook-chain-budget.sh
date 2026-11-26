#!/usr/bin/env bash
#
# tests/hook-chain-budget.sh — performance budget of the interactive path (WS-GOV-014): every PreToolUse and
# PostToolUse hook that settings.json runs for a typical Bash call (no matcher, or a matcher that matches Bash), run
# in order as Claude Code runs them (sequentially, worst case), with the hook JSON on stdin, in a temporary HOME with
# the kit's hooks. The whole chain must average under WS_HOOK_BUDGET_MS (400) over 5 runs, after a warm-up; the
# figure per hook is printed so a slow one is visible. Read: also a typical Read call (read-convert, read-screen).
#
# Usage: bash tests/hook-chain-budget.sh      (exit 0 = within budget)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BUDGET="${WS_HOOK_BUDGET_MS:-400}"
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
export HOME="$T/home" CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors.txt" WS_STATE_DIR="$T/state"
unset TMUX TMUX_PANE
mkdir -p "$HOME/.claude" "$HOME/.local" "$T/proj"
cp -a "$ROOT/files/home/.claude/hooks" "$HOME/.claude/"
cp -a "$ROOT/files/home/.local/bin" "$ROOT/files/home/.local/lib" "$HOME/.local/"
S="$ROOT/files/home/.claude/settings.json"
printf 'hello\n' > "$T/proj/README.md"

# chain <event> <tool> — the commands of every hook group of that event whose matcher matches the tool, in order.
chain() {
  jq -r --arg t "$2" --arg e "$1" '.hooks[$e][] | objects | (.matcher // "") as $m | select($m == "" or ($t | test("^(" + $m + ")$")))
    | .hooks[] | select(.type == "command" and (has("if") | not)) | .command' "$S"
}
ms() { local s e; s=$(date +%s%N); "$@" >/dev/null 2>&1; e=$(date +%s%N); echo $(( (e - s) / 1000000 )); }
run_chain() {   # run_chain <event> <tool> <json> — runs the chain once, prints «total» then «ms<TAB>hook» lines
  local c t total=0 out=""
  while IFS= read -r c; do
    c="${c/#\~/$HOME}"
    t=$(ms bash -c "$c" <<<"$3")
    total=$((total + t)); out+="$t"$'\t'"${c#"$HOME"/}"$'\n'
  done < <(chain "$1" "$2")
  printf '%s\n%s' "$total" "$out"
}
measure() {   # measure <label> <event> <tool> <json>
  local sum=0 r first
  run_chain "$2" "$3" "$4" >/dev/null   # warm-up (page cache, jq)
  for _ in 1 2 3 4 5; do r="$(run_chain "$2" "$3" "$4")"; first="${r%%$'\n'*}"; sum=$((sum + first)); done
  echo "  $1: $((sum / 5)) ms on average (budget $BUDGET ms); last run per hook:"
  tail -n +2 <<<"$r" | sed '/^$/d; s/^/      /'
  (( sum / 5 <= BUDGET ))
}
bash_in="$(jq -nc --arg c "$T/proj" '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: "git status"}, cwd: $c, session_id: "s"}')"
post_in="$(jq -nc --arg c "$T/proj" '{hook_event_name: "PostToolUse", tool_name: "Bash", tool_input: {command: "git status"}, tool_response: {stdout: "On branch main"}, cwd: $c, session_id: "s"}')"
read_in="$(jq -nc --arg c "$T/proj" --arg f "$T/proj/README.md" '{hook_event_name: "PreToolUse", tool_name: "Read", tool_input: {file_path: $f}, cwd: $c, session_id: "s"}')"
check "the chain has the guard, the audit and the runtime gate" bash -c "$(declare -f chain); S='$S'; chain PreToolUse Bash | grep -q guard.sh && chain PreToolUse Bash | grep -q audit.sh && chain PreToolUse Bash | grep -q ws-runtime-gate.sh"
check "PreToolUse for a Bash call stays within budget" measure "PreToolUse Bash" PreToolUse Bash "$bash_in"
check "PostToolUse for a Bash call stays within budget" measure "PostToolUse Bash" PostToolUse Bash "$post_in"
check "PreToolUse for a Read call stays within budget" measure "PreToolUse Read" PreToolUse Read "$read_in"
measure "PreToolUse Bash" PreToolUse Bash "$bash_in"

echo
echo "Result: $PASS ok · $FAIL failed"
(( FAIL == 0 ))
