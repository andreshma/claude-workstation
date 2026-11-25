#!/usr/bin/env bash
#
# tests/hooks-settings.sh — static and fixture checks of the phase-2 settings (files/home/.claude/settings.json), the
# managed policy template (files/etc/claude-code/managed-settings.json) and the hooks they register: valid JSON, the
# deny rules for MCP/plugin registration and for the agent's own configuration, the credential list shared by the
# sandbox and guard.sh, the hooks present and executable, the guard failing closed, the official security plugin
# enabled, and the ConfigChange hook leaving an audit line. Temporary HOME, no tmux, no network.
# Usage: bash tests/hooks-settings.sh
set -uo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
S="$root/files/home/.claude/settings.json"
M="$root/files/etc/claude-code/managed-settings.json"
HK="$root/files/home/.claude/hooks"
LIST="$root/files/home/.local/lib/ws-credential-paths.txt"
H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
ok=0; bad=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok=$((ok + 1)); else bad=$((bad + 1)); printf '  FAIL  %s\n' "$d"; fi; }
has() { jq -e --arg r "$2" '.permissions.deny | index($r) != null' "$1"; }

check "settings.json is valid JSON" jq -e . "$S"
check "the managed template is valid JSON" jq -e . "$M"
for r in 'Bash(claude mcp add*)' 'Bash(claude mcp add-json*)' 'Bash(claude mcp remove*)' 'Bash(claude plugin install*)' \
         'Bash(gh auth token*)' 'Bash(ws-learn*)' 'Edit(~/.claude/settings.json)' 'Edit(~/.claude/hooks/**)' \
         'Edit(~/.claude.json)' 'Edit(~/.config/git/hooks/**)' 'Edit(~/.config/claude-levels/**)' 'Read(~/.config/ws-agent/**)'; do
  check "deny rule $r" has "$S" "$r"
done
check "bypassPermissions mode is disabled" jq -e '.permissions.disableBypassPermissionsMode == "disable"' "$S"
check "project .mcp.json servers are not approved wholesale" jq -e '.enableAllProjectMcpServers == false' "$S"
check "the official claude-security plugin is enabled" jq -e '.enabledPlugins["claude-security@claude-plugins-official"] == true' "$S"
check "the guard blocks when it fails (onFailure)" jq -e '[.hooks.PreToolUse[].hooks[] | select(.command == "~/.claude/hooks/guard.sh") | .onFailure] == ["block"]' "$S"
check "untrusted-content on WebFetch, WebSearch and MCP" jq -e '[.hooks.PostToolUse[] | select(.matcher == "^(WebFetch|WebSearch|mcp__.*)$") | .hooks[].command] == ["~/.claude/hooks/untrusted-content.sh"]' "$S"
check "untrusted-content on network Bash commands (if rules)" jq -e '[.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | startswith("~/.claude/hooks/untrusted-content.sh")) | .if] | index("Bash(curl *)") != null and index("Bash(gh issue view *)") != null' "$S"
check "prompt-screen on UserPromptSubmit" jq -e '[.hooks.UserPromptSubmit[].hooks[].command] | index("~/.claude/hooks/prompt-screen.sh") != null' "$S"
check "config-change on ConfigChange" jq -e '.hooks.ConfigChange[0].hooks[0].command == "~/.claude/hooks/config-change.sh"' "$S"
for f in guard.sh untrusted-content.sh prompt-screen.sh config-change.sh; do
  check "$f is executable" test -x "$HK/$f"
  check "$f is shellcheck-clean" shellcheck -S warning "$HK/$f"
done
# Phase-2 integration: runtime gate, memory gate and filter, protected state, the strict base (ADR-013).
check "ws-runtime-gate on PreToolUse and UserPromptSubmit" jq -e '[.hooks.PreToolUse[], .hooks.UserPromptSubmit[] | .hooks[].command | select(. == "~/.claude/hooks/ws-runtime-gate.sh")] | length == 2' "$S"
check "memory-gate on MemPalace tools and on prompts" jq -e '([.hooks.PreToolUse[] | select(.matcher == "mcp__.*mempalace.*") | .hooks[].command] == ["~/.claude/hooks/memory-gate.sh"]) and ([.hooks.UserPromptSubmit[].hooks[].command] | index("~/.claude/hooks/memory-gate.sh") != null)' "$S"
check "every MemPalace and recall hook goes through memory-filter.sh" jq -e '([.hooks[][].hooks[] | select(.command | endswith("/win-hook.sh"))] | length == 0) and ([.hooks[][].hooks[] | select(.command | endswith("/memory-filter.sh")) | select(.args[0] == "@HOME@/.claude/hooks/win-hook.sh") | .args[1:] | join(" ") | select(test("mempalace.exe hook run --hook (stop|precompact|session-end)|recall_hook"))] | length == 4)' "$S"
for r in 'Bash(ws-memory*)' 'Bash(ws-stop-all --clear*)' 'Bash(ws-telemetry budgets --override*)' 'Edit(~/.claude/audit/**)' \
         'Edit(~/.local/state/ws-stop-all)' 'Edit(~/.config/ws-kit/**)' 'Edit(~/.local/share/ws-kit/**)' 'Edit(~/.local/lib/ws-npm/**)' \
         'Edit(~/.config/agent-browser/**)' 'Edit(~/.config/ws-telegram/**)'; do
  check "deny rule $r" has "$S" "$r"
done
for r in 'Bash(*.exe*)' 'mcp__mempalace__*add*' 'Bash(mempalace *)' 'Bash(ws-kit-update*--allow-unsigned*)' 'Bash(ws-telegram approve*)'; do
  check "ask rule $r" jq -e --arg r "$r" '.permissions.ask | index($r) != null' "$S"
done
for f in ws-runtime-gate.sh memory-gate.sh memory-filter.sh; do check "$f is executable" test -x "$HK/$f"; done
check "the user settings exclude no command from the sandbox (strict base, ADR-013)" jq -e '.sandbox | has("excludedCommands") | not' "$S"
check "the normal level adds the exclusions (normal-adds.json)" \
  jq -e '(keys == ["sandbox"]) and (.sandbox | keys == ["excludedCommands"]) and (.sandbox.excludedCommands | index("git push *"))' "$root/files/home/.config/claude-levels/normal-adds.json"
check "the normal level adds no interpreter, shell or network client" \
  jq -e '[.sandbox.excludedCommands[] | select(test("^(bash|sh|zsh|python3?|node|curl|wget|ssh|env|sudo|docker [*]|docker (run|exec))( |$)"))] | length == 0' "$root/files/home/.config/claude-levels/normal-adds.json"
# The credential list (guard.sh) and the sandbox's denyRead are one list.
check "ws-credential-paths.txt equals sandbox.filesystem.denyRead" \
  diff <(grep -Ev '^[[:space:]]*(#|$)' "$LIST" | sort) <(jq -r '.sandbox.filesystem.denyRead[]' "$S" | sort)
check "every denyRead path also has a Read deny rule" bash -c '
  for p in $(jq -r ".sandbox.filesystem.denyRead[] | gsub(\" \"; \"%20\")" "$1"); do
    p="${p//%20/ }"; jq -e --arg a "Read($p)" --arg b "Read($p/**)" ".permissions.deny | index(\$a) != null or index(\$b) != null" "$1" >/dev/null || { echo "$p"; exit 1; }
  done' _ "$S"
# The managed floor: the same deny rules as the user file, the guard from a root-owned copy, failing closed.
check "the managed template carries the whole deny floor" \
  diff <(jq -r '.permissions.deny[]' "$M" | sort) <(jq -r '.permissions.deny[]' "$S" | sort)
check "the managed template runs the root-owned guard and fails closed" \
  jq -e '.hooks.PreToolUse[0].hooks[0] == {type: "command", command: "/etc/claude-code/hooks/guard.sh", onFailure: "block"}' "$M"
check "the managed template disables bypass mode" jq -e '.permissions.disableBypassPermissionsMode == "disable"' "$M"
check "the managed template sets no allow rules or excluded commands" jq -e '(.permissions.allow // []) == [] and (.sandbox.excludedCommands // []) == []' "$M"
# ConfigChange: one audit line with the source and the file.
mkdir -p "$H/.claude/hooks"
printf '#!/bin/bash\ncat >/dev/null; printf "%%s|%%s\\n" "$1" "$2" >> "%s/audit.log"\n' "$H" > "$H/.claude/hooks/audit.sh"
chmod +x "$H/.claude/hooks/audit.sh"
printf '{"hook_event_name":"ConfigChange","session_id":"s","source":"user_settings","file_path":"/h/.claude/settings.json"}' |
  HOME="$H" bash "$HK/config-change.sh"; r=$?
check "config-change exits 0" test "$r" -eq 0
check "config-change logs the source and the file" grep -qx 'config-change|user_settings /h/.claude/settings.json' "$H/audit.log"
r="$(printf 'nope' | HOME="$H" bash "$HK/config-change.sh" >/dev/null 2>&1; echo $?)"
check "config-change never fails" test "$r" -eq 0

# install.sh --managed: prints every sudo command, writes nothing in a dry run, never runs without a terminal.
mkdir -p "$H/mh/bin"; printf '#!/bin/sh\nexit 0\n' > "$H/mh/bin/reg.exe"; chmod +x "$H/mh/bin/reg.exe"
printf '#!/bin/sh\necho "sudo was called" >> "%s/sudo.log"\n' "$H" > "$H/mh/bin/sudo"; chmod +x "$H/mh/bin/sudo"
out="$(HOME="$H/mh" PATH="$H/mh/bin:$PATH" bash "$root/install.sh" --managed --dry-run --win-user tester 2>&1)"
check "--managed --dry-run lists the drop-in, the root guard and the credential list" bash -c '
  grep -q "sudo install -o root -g root -m 644 .*managed-settings.json /etc/claude-code/managed-settings.d/50-ws-kit.json" <<<"$1" &&
  grep -q "sudo install -o root -g root -m 755 .*/guard.sh /etc/claude-code/hooks/guard.sh" <<<"$1" &&
  grep -q "/etc/claude-code/ws-credential-paths.txt" <<<"$1" && grep -q "Dry run: nothing was run" <<<"$1"' _ "$out"
check "--managed --dry-run runs no sudo and installs nothing else" bash -c "[[ ! -e '$H/sudo.log' && ! -e '$H/mh/.claude' ]]"
HOME="$H/mh" PATH="$H/mh/bin:$PATH" bash "$root/install.sh" --managed --win-user tester </dev/null >/dev/null 2>&1; r=$?
check "--managed without a terminal refuses and runs no sudo" bash -c "[[ $r != 0 && ! -e '$H/sudo.log' ]]"

printf 'hooks-settings: %d ok, %d failed\n' "$ok" "$bad"
(( bad == 0 ))
