#!/usr/bin/env bash
#
# tests/solo-sandbox.sh — solo mode inside the sandbox with expiry (WS-AI-004, WS-SEC-003) and swarm agents at the
# full level (WS-AI-015): the solo profile keeps the sandbox, tmux-solo marks the tab with an expiry that tmux-watch
# enforces, --unsandboxed is an audited exception, «new» goes to a worktree, and tmux-swarm starts each agent with a
# full-level profile that denies git push (or refuses without --setting-sources). tmux and Claude are simulated (no
# server is started); git runs only in temporary repositories.
#
# Usage: bash tests/solo-sandbox.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

BIN="$ROOT/files/home/.local/bin"
export HOME="$T/home" CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors" WS_LEVELS_DIR="$T/levels" \
       WS_WATCH_STATE="$T/watch" WS_WATCH_BURN="$T/burn" GIT_CONFIG_GLOBAL="$T/gitconfig" WS_FULL_READ=1
unset WS_SOLO_HOURS WS_SWARM_LEVEL TMUX TMUX_PANE
mkdir -p "$HOME/.claude/hooks" "$HOME/.config/claude-solo" "$HOME/.local/bin" "$T/fake"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"
cp "$ROOT/files/home/.config/claude-solo/settings.json" "$HOME/.config/claude-solo/"
mkdir -p "$HOME/.config/claude-levels"; cp "$ROOT/files/home/.config/claude-levels/normal-adds.json" "$HOME/.config/claude-levels/"
printf '[user]\n\tname = t\n\temail = t@t\n[core]\n\thooksPath = /dev/null\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
F="$T/fake"
# Simulated tmux: logs every call; answers queries from FAKE_* variables; list-windows -f returns $F/solo-windows.
cat > "$F/tmux" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_DIR/log"
case "$1" in
  display) case "${!#}" in
             *pane_current_command*) echo bash ;; *pane_pid*) echo 999999 ;; *pane_current_path*) echo "${FAKE_PATH:-/tmp}" ;;
             '#W') echo api ;; *window_id*) echo @1 ;; *pane_id*) echo %1 ;; *) echo x ;; esac ;;
  list-windows) [[ "$*" == *"-f #{@csolo}"* ]] && cat "$FAKE_DIR/solo-windows" 2>/dev/null ;;
  new-window) echo @9 ;;
  show|show-options) o="${!#}"; v="FAKE_${o#@}"; [[ -n "${!v:-}" ]] && echo "${!v}" ;;
esac
exit 0
EOF
chmod +x "$F/tmux"
run() { env FAKE_DIR="$F" PATH="$F:$BIN:$PATH" "$@"; }

echo "1) the solo profile"
check "solo keeps the sandbox on, only auto-allows sandboxed commands and refuses unsandboxed retries" \
  jq -e '. == {sandbox: {enabled: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: false}}' "$ROOT/files/home/.config/claude-solo/settings.json"
check "ws-audit expects exactly that profile" \
  grep -qF 'want = {"sandbox": {"enabled": True, "autoAllowBashIfSandboxed": True, "allowUnsandboxedCommands": False}}' "$BIN/ws-audit"

echo "2) tmux-solo"
: > "$F/log"; t0="$(date +%s)"
run bash "$BIN/tmux-solo" this %1 >/dev/null 2>&1
check "this: restarts Claude in auto mode with the generated solo profile" \
  grep -qF -- "send-keys -t %1 -l WS_LEVEL=solo claude-resume --permission-mode auto --settings '$WS_LEVELS_DIR/solo.json'" "$F/log"
check "  which keeps the sandbox and excludes NO command from it (ADR-022)" \
  jq -e '.sandbox.enabled and .sandbox.autoAllowBashIfSandboxed and (.sandbox.allowUnsandboxedCommands == false) and (.sandbox | has("excludedCommands") | not)' "$WS_LEVELS_DIR/solo.json"
n_ex="$(jq '.sandbox.excludedCommands | length' "$ROOT/files/home/.config/claude-levels/normal-adds.json")"
check "  and makes every command normal excludes an ask rule, so the classifier cannot approve it" \
  jq -e --argjson n "$n_ex" '(.permissions.ask | index("Bash(gh *)")) and (.permissions.ask | index("Bash(git push *)")) and (.permissions.ask | index("Bash(az *)")) and ([.permissions.ask[] | select(startswith("Bash("))] | length) == $n' "$WS_LEVELS_DIR/solo.json"
until="$(sed -n 's/.*set -w -t @1 @csolo 1 ; set -w -t @1 @csolo_until \([0-9]*\).*/\1/p' "$F/log")"
check "marks the tab and its expiry, 4 h by default" bash -c "[[ -n '$until' ]] && (( $until - $t0 >= 14390 && $until - $t0 <= 14410 ))"
check "solo-on is recorded in the audit log" bash -c "grep -h '\"ev\":\"solo-on\"' '$CLAUDE_AUDIT_DIR'/*.jsonl | grep -q '4 h'"
: > "$F/log"; run env FAKE_csolo_hours=2 bash "$BIN/tmux-solo" this %1 >/dev/null 2>&1
check "@csolo_hours sets the default expiry" bash -c "u=\$(sed -n 's/.*@csolo_until \([0-9]*\).*/\1/p' '$F/log'); (( u - $(date +%s) <= 7210 && u - $(date +%s) >= 7190 ))"
: > "$F/log"; run bash "$BIN/tmux-solo" this %1 --hours 30 >/dev/null 2>&1
check "an expiry over 24 h is refused" not grep -q 'send-keys' "$F/log"
: > "$F/log"; run bash "$BIN/tmux-solo" this %1 --unsandboxed >/dev/null 2>&1
check "--unsandboxed uses a generated sandbox-off profile" bash -c "grep -qF -- \"--settings '$WS_LEVELS_DIR/solo-unsandboxed.json'\" '$F/log' && jq -e '.sandbox.enabled == false' '$WS_LEVELS_DIR/solo-unsandboxed.json'"
check "  built like the other solo profiles: the network tools still ask" \
  jq -e '(.permissions.ask | index("Bash(gh *)")) and (.permissions.ask | index("Bash(kubectl *)")) and .sandbox.autoAllowBashIfSandboxed' "$WS_LEVELS_DIR/solo-unsandboxed.json"
check "and is visible: 🔓 in the tab name, @csolo_nosb and an audit event" bash -c "grep -q 'rename-window -t @1 🔓🤖api' '$F/log' && grep -q '@csolo_nosb 1' '$F/log' && grep -hq '\"ev\":\"solo-unsandboxed\"' '$CLAUDE_AUDIT_DIR'/*.jsonl"
: > "$F/log"; run bash "$BIN/tmux-solo" this %1 --with-network-tools >/dev/null 2>&1
check "--with-network-tools: the normal exclusions come back, each one asking" \
  jq -e '.sandbox.enabled and (.sandbox.excludedCommands | index("gh *")) and (.permissions.ask | index("Bash(gh *)")) and (.permissions.ask | index("Bash(git push *)"))' "$WS_LEVELS_DIR/solo-net.json"
check "  started with that profile, marked 🌐 and @csolo_net, audited as solo-network-tools" \
  bash -c "grep -qF -- \"--settings '$WS_LEVELS_DIR/solo-net.json'\" '$F/log' && grep -q 'rename-window -t @1 🌐🤖api' '$F/log' && grep -q '@csolo_net 1' '$F/log' && grep -hq '\"ev\":\"solo-network-tools\"' '$CLAUDE_AUDIT_DIR'/*.jsonl"
check "  time-boxed: 1 h by default" bash -c "u=\$(sed -n 's/.*@csolo_until \([0-9]*\).*/\1/p' '$F/log'); (( u - $(date +%s) <= 3610 && u - $(date +%s) >= 3590 ))"
: > "$F/log"; run bash "$BIN/tmux-solo" this %1 --with-network-tools --hours 5 >/dev/null 2>&1
check "  and 4 h at most" not grep -q 'send-keys' "$F/log"
: > "$F/log"; run bash "$BIN/tmux-solo" this %1 --with-network-tools --unsandboxed >/dev/null 2>&1
check "  never together with --unsandboxed" not grep -q 'send-keys' "$F/log"
: > "$F/log"; run bash "$BIN/tmux-solo" normal %1 >/dev/null 2>&1
check "normal: back to the normal level and every solo mark removed" bash -c "grep -qF -- \"-l WS_LEVEL=normal claude-resume --settings '$WS_LEVELS_DIR/normal.json'\" '$F/log' && grep -q 'set -wu -t @1 @csolo_until' '$F/log' && grep -q 'set -wu -t @1 @csolo_nosb' '$F/log' && grep -q 'set -wu -t @1 @csolo_net' '$F/log'"
R="$T/repo"; git init -q "$R" && git -C "$R" commit -q --allow-empty -m "chore: init"
: > "$F/log"; run bash "$BIN/tmux-solo" new "$R" >/dev/null 2>&1
check "new in a git repo: its own worktree and branch by default" bash -c "ls -d '$R'.wt/solo-* && git -C '$R' branch --list 'solo/*' | grep -q solo/ && grep -q 'new-window .* -c $R.wt/solo-' '$F/log'"
: > "$F/log"; run bash "$BIN/tmux-solo" new "$R" --here >/dev/null 2>&1
check "new --here stays in the folder" grep -q "new-window .* -c $R -n 🤖repo" "$F/log"

echo "3) tmux-watch returns an expired solo tab to normal"
printf '#!/bin/bash\necho "$*" >> "%s/solo.log"\n' "$T" > "$HOME/.local/bin/tmux-solo"; chmod +x "$HOME/.local/bin/tmux-solo"
printf '@1|%%1|%s|🤖api\n@2|%%2|%s|🤖web\n' "$(( $(date +%s) - 5 ))" "$(( $(date +%s) + 3600 ))" > "$F/solo-windows"
: > "$F/log"; run bash "$BIN/tmux-watch" >/dev/null 2>&1; sleep 1
check "the expired tab goes back to normal" grep -qx 'normal %1' "$T/solo.log"
check "the one still in time is left alone" not grep -q '%2' "$T/solo.log"
check "the expiry mark is cleared first, so it runs once" grep -q 'set -wu -t @1 @csolo_until' "$F/log"
mkdir -p "$T/state"; : > "$T/state/ws-stop-all"
check "the bar shows the emergency stop" bash -c "env FAKE_DIR='$F' PATH='$F:$PATH' WS_STATE_DIR='$T/state' bash '$BIN/tmux-watch' | grep -q 'STOP'"

echo "4) tmux-swarm agents at the full level"
mkdir -p "$HOME/.claude"
jq -n '{permissions: {deny: ["Read(~/.ssh/**)"], ask: ["Bash(terraform apply*)"]}, sandbox: {enabled: true, excludedCommands: ["gh *", "git push *"]}}' \
  > "$HOME/.claude/settings.json"
printf '#!/bin/bash\n[[ "$1" == --help ]] && echo "  --setting-sources <sources>"\n[[ " $* " == *" -p "* ]] && { cat >/dev/null; printf "Sub one\\n---\\nSub two\\n"; }\nexit 0\n' > "$F/claude"
chmod +x "$F/claude"
cmd="$(run bash "$BIN/tmux-swarm" command full "$R" "$T/agent.json")"
check "an agent starts with only project/local sources and its own profile" test "$cmd" = "claude --setting-sources project,local --settings $T/agent.json"
check "the profile is the full level: no commands outside the sandbox" jq -e '.sandbox.enabled and (.sandbox.allowUnsandboxedCommands == false) and (.sandbox | has("excludedCommands") | not)' "$T/agent.json"
check "reads are limited to the agent's repository" jq -e --arg r "/$R" '.sandbox.filesystem.allowRead | index($r)' "$T/agent.json"
check "git push and gh pr create are denied, the user's deny rules stay" jq -e '(.permissions.deny | index("Bash(git push*)")) and (.permissions.deny | index("Bash(gh pr create*)")) and (.permissions.deny | index("Read(~/.ssh/**)"))' "$T/agent.json"
check "the profile is private (0600)" test "$(stat -c %a "$T/agent.json")" = 600
cmd="$(run bash "$BIN/tmux-swarm" command normal "$R" "$T/agent-n.json")"
check "the normal exception still denies push" bash -c "[[ '$cmd' == 'claude --settings $T/agent-n.json' ]] && jq -e '.permissions.deny | index(\"Bash(git push*)\")' '$T/agent-n.json'"
check "  and carries the normal level's exclusions" jq -e '.sandbox.excludedCommands | index("az *")' "$T/agent-n.json"
: > "$F/log"
( cd "$R" && printf 'y\n' | run env EDITOR=true bash "$BIN/tmux-swarm" new "add validation" >/dev/null 2>&1 )
check "tmux-swarm new starts every agent with its full profile" bash -c "[[ \$(grep -c 'new-window -d .*--setting-sources project,local --settings .*/profiles/' '$F/log') == 2 ]]"
id="$(find "$HOME/.local/share/tmux-swarm" -maxdepth 1 -name '*.json' -printf '%f\n' | sed 's/\.json$//' | head -1)"
check "the state records the level and each agent's profile" jq -e '.level == "full" and (.tasks | all(.profile | test("/profiles/")))' "$HOME/.local/share/tmux-swarm/$id.json"
printf '#!/bin/bash\n[[ " $* " == *" -p "* ]] && { cat >/dev/null; echo "Sub"; }\nexit 0\n' > "$F/claude"
R2="$T/repo2"; git init -q "$R2" && git -C "$R2" commit -q --allow-empty -m "chore: init"
out="$( cd "$R2" && printf 'y\n' | run env EDITOR=true bash "$BIN/tmux-swarm" new "goal" 2>&1 )"
check "without --setting-sources the swarm refuses and says why" bash -c "grep -q 'no --setting-sources' <<<'$out' && ! ls -d '$R2'.wt >/dev/null 2>&1"
( cd "$R2" && printf 'y\n' | run env EDITOR=true WS_SWARM_LEVEL=normal bash "$BIN/tmux-swarm" new "goal" >/dev/null 2>&1 )
check "WS_SWARM_LEVEL=normal is the audited exception" bash -c "grep -h '\"ev\":\"swarm-normal\"' '$CLAUDE_AUDIT_DIR'/*.jsonl | grep -q 'normal level'"
check "--budget needs a number" bash -c "cd '$R' && ! printf 'y\n' | env FAKE_DIR='$F' PATH='$F:$BIN:$PATH' EDITOR=true bash '$BIN/tmux-swarm' new --budget lots goal"
if command -v shellcheck >/dev/null; then
  check "shellcheck tmux-solo, tmux-watch, tmux-swarm" shellcheck -S warning "$BIN/tmux-solo" "$BIN/tmux-watch" "$BIN/tmux-swarm"
fi

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
