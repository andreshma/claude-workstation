#!/usr/bin/env bash
#
# tests/settings-menu.sh — Menu → Settings and its backend ws-settings (ADR-028), in a temporary HOME with a private
# tmux server (its own socket under the temp dir, never your server) and a fake claude:
#   1) the menus parse in tmux (source-file -n), every #{?…} conditional has exactly two branches (no stray comma),
#      the main menu links Settings, every script an entry calls is in the kit, every ws-settings subcommand an
#      entry uses exists, the menu pauses the status refresh like the others
#   2) menu-sync publishes the current values and every label renders without a leftover format
#   3) each setting: new-tab level, copy expiry, hard stop, the config-write window, egress mode (the jail follows the
#      owner's file), keepalive off/on (re-registered, remembered for install.sh), editors that save only valid files
#      (production, budgets, filter rules), refusal inside Claude
#   4) guard.sh: every changing entry is blocked from Claude, the read-only ones pass
#
# Usage: bash tests/settings-menu.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; T="$(realpath "$T")"
SOCK="$T/tmux.sock"
cleanup() { env -u TMUX tmux -S "$SOCK" kill-server 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
PASS=0 FAIL=0 SKIP=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }

M="$ROOT/files/home/.config/tmux-claude"
B="$ROOT/files/home/.local/bin"
S="$B/ws-settings"
export HOME="$T/home"; unset CLAUDECODE WS_PROFILE WS_LEVEL XDG_STATE_HOME XDG_CONFIG_HOME
export CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors.txt"
mkdir -p "$HOME/.claude/hooks" "$HOME/.local/bin" "$HOME/.config/ws-mcp" "$T/fake"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"; chmod 755 "$HOME/.claude/hooks/audit.sh"
for f in ws-settings tmux-level ws-lang ws-mcp-tools ws-egress-proxy ws-mcp-jail; do cp "$B/$f" "$HOME/.local/bin/"; done
mkdir -p "$HOME/.local/lib"; cp -a "$ROOT/files/home/.local/lib/ws-lang.sh" "$ROOT/files/home/.local/lib/ws-lang" \
  "$ROOT/files/home/.local/lib/ws_mcp_policy.py" "$HOME/.local/lib/"
cp "$ROOT/files/home/.config/ws-mcp/egress.json" "$HOME/.config/ws-mcp/"
# A fake claude: logs «mcp» calls, knows nothing else.
printf '#!/bin/sh\necho "$*" >> "%s/claude.log"\n' "$T" > "$T/fake/claude"; chmod 755 "$T/fake/claude"
export PATH="$HOME/.local/bin:$T/fake:/usr/bin:/bin"
tm() { env -u TMUX tmux -S "$SOCK" "$@"; }

echo "== 1. menus"
# A private tmux server (its own socket); where tmux cannot create one (Claude Code's sandbox), the tmux checks skip.
HAVE_TMUX=0
tm -f /dev/null new-session -d -s t -x 200 -y 50 "sleep 600" 2>/dev/null && HAVE_TMUX=1
if (( HAVE_TMUX )); then
  for m in "$M"/menu-settings.tmux "$M"/menu.tmux; do
    r="$(tm source-file -n "$m" 2>&1)"; check "${m##*/} parses" test -z "$r"
  done
else
  SKIP=$((SKIP+1)); echo "  skip tmux parse and render checks: tmux cannot create its socket here"
fi
cat > "$T/cond.py" <<'EOF'
import re, sys
bad = []
for p in sys.argv[1:]:
    s = open(p, encoding="utf-8").read()
    for m in re.finditer(r"#\{\?", s):
        depth, j, commas = 0, m.start(), 0
        while j < len(s):
            if s.startswith("#{", j):
                depth += 1; j += 2; continue
            if s[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            elif s[j] == "," and depth == 1:
                commas += 1
            j += 1
        if commas != 2:
            bad.append(f"{p.rsplit('/', 1)[-1]}: {s[m.start():m.start() + 60]!r} ({commas} commas)")
print("\n".join(bad))
sys.exit(1 if bad else 0)
EOF
check "every #{?…} conditional of the Settings menu has exactly two branches" python3 "$T/cond.py" "$M/menu-settings.tmux"
check "the main menu opens Settings" grep -q 'source-file ~/.config/tmux-claude/menu-settings.tmux' "$M/menu.tmux"
missing=""
# shellcheck disable=SC2088  # the tilde is part of the text searched for in the menu
for f in $(grep -ohE '~/\.local/bin/[A-Za-z0-9_-]+' "$M/menu-settings.tmux" | sort -u); do [[ -x "$ROOT/files/home/${f#\~/}" ]] || missing+=" $f"; done
for f in $(grep -ohE "tmux-pause '[a-z0-9-]+" "$M/menu-settings.tmux" | sed "s/tmux-pause '//" | sort -u); do [[ -x "$B/$f" ]] || missing+=" $f"; done
check "every script an entry calls is in the kit" test -z "$missing"
subs="$(grep -v '^#' "$M/menu-settings.tmux" | grep -ohE "ws-settings [a-z-]+" | awk '{print $2}' | sort -u)"
nosub=""; for s in $subs; do grep -qE "^  (${s}|${s}\|[a-z|-]+|[a-z|-]+\|${s})\)" "$S" || nosub+=" $s"; done
check "every ws-settings subcommand an entry uses exists ($(wc -w <<<"$subs") of them)" test -z "$nosub"
check "the menu pauses the status bar refresh and restores it" bash -c "[[ \$(grep -c status-interval '$M/menu-settings.tmux') == 3 && \$(tail -1 '$M/menu-settings.tmux') == 'set -gF status-interval'* ]]"

echo "== 2. values"
printf 'hard=1\nmy-repo=50\n' > "$T/b.conf"; mkdir -p "$HOME/.config/ws-telemetry"; cp "$T/b.conf" "$HOME/.config/ws-telemetry/budgets.conf"
mkdir -p "$HOME/.config/ws-guard"; printf 'subscription 0000-prod\n' > "$HOME/.config/ws-guard/production.conf"
if (( HAVE_TMUX )); then
TMUX="$SOCK,1,0" "$S" menu-sync
check "menu-sync publishes the level of new tabs" test "$(tm show -gv @ws_set_level)" == normal
check "…the budgets and the hard stop" bash -c "[[ \$(env -u TMUX tmux -S '$SOCK' show -gv @ws_set_budgets) == 1 && \$(env -u TMUX tmux -S '$SOCK' show -gv @ws_set_hard) == on ]]"
check "…production entries, the window, the egress mode, the copy expiry" bash -c "[[ \$(env -u TMUX tmux -S '$SOCK' show -gv @ws_set_production) == 1 && \$(env -u TMUX tmux -S '$SOCK' show -gv @ws_set_window) == closed && \$(env -u TMUX tmux -S '$SOCK' show -gv @ws_set_egress) == audit && \$(env -u TMUX tmux -S '$SOCK' show -gv @ws_set_copydays) == 30 ]]"
left=""
while IFS= read -r label; do
  out="$(tm display -p -- "$label")"; [[ "$out" == *'#{'* ]] && left+=" [$label]"
done < <(grep -oE '^  "[^"]*#\{[^"]*"' "$M/menu-settings.tmux" | sed -E 's/^  "//; s/"$//')
check "every label renders with its value (no leftover format)" test -z "$left"
check "a rendered label shows the value" bash -c "[[ \"\$(env -u TMUX tmux -S '$SOCK' display -p 'Hard: #{?@ws_set_hard,#{@ws_set_hard},off}')\" == 'Hard: on' ]]"
fi
check "show lists the values without tmux" bash -c "'$S' show | grep -q 'hard *on' && '$S' show | grep -q 'production *1'"

echo "== 3. settings"
check "refused inside Claude (exit 2)" bash -c "CLAUDECODE=1 '$S' level full; [[ \$? == 2 ]]"
check "show runs inside Claude (read-only)" bash -c "CLAUDECODE=1 '$S' show | grep -q 'level'"
"$S" level full >/dev/null
check "level full: new tabs start at full" test "$(tmux-level default)" == full
check "…and the new-tab command is the full one" bash -c "tmux-level --new-tab-command '$T' 2>/dev/null | grep -q '^WS_LEVEL=full ' || [[ \$? == 1 ]]"
"$S" level normal >/dev/null
check "level normal: back to normal" test "$(tmux-level default)" == normal
check "bare is never a default" bash -c "! '$S' level bare"
"$S" copy-days 14 >/dev/null
check "copy-days writes the expiry ws-backup-lite reads" bash -c "[[ \$(cat '$HOME/.config/ws-backup/copy-days') == 14 ]] && grep -q 'ws-backup/copy-days' '$B/ws-backup-lite'"
check "copy-days refuses a non-number" bash -c "! '$S' copy-days abc"
"$S" hard off >/dev/null
check "hard off keeps the budgets and drops hard=1" bash -c "! grep -q '^hard=' '$HOME/.config/ws-telemetry/budgets.conf' && grep -q 'my-repo=50' '$HOME/.config/ws-telemetry/budgets.conf'"
"$S" hard on >/dev/null
check "hard on adds hard=1 once" test "$(grep -c '^hard=1' "$HOME/.config/ws-telemetry/budgets.conf")" == 1
"$S" window open >/dev/null
check "window open: 30 min, read by the guard's file (0600)" bash -c "u=\$(cat '$HOME/.config/ws-guard/allow-config-writes'); (( u - \$(date +%s) > 1700 && u - \$(date +%s) <= 1800 )) && [[ \$(stat -c %a '$HOME/.config/ws-guard/allow-config-writes') == 600 ]]"
"$S" window close >/dev/null
check "window close removes it" test ! -e "$HOME/.config/ws-guard/allow-config-writes"
check "window changes are audited" grep -rqs 'config-write window' "$T/audit"
"$S" egress azure enforce >/dev/null
check "egress: the owner's file overrides the kit's mode" jq -e '.azure.mode == "enforce"' "$HOME/.config/ws-mcp/egress.local.json"
mkdir -p "$T/srv"; printf '#!/bin/sh\n' > "$T/srv/s"; chmod 755 "$T/srv/s"
check "…and the jail follows it (no shared network)" bash -c "out=\$(bash '$HOME/.local/bin/ws-mcp-jail' --print --name azure --net --egress -- '$T/srv/s'); [[ \$out != *--share-net* && \$out == *ws-egress-proxy* ]]"
"$S" egress azure off >/dev/null
check "…off shares the network again" bash -c "out=\$(bash '$HOME/.local/bin/ws-mcp-jail' --print --name azure --net --egress -- '$T/srv/s'); [[ \$out == *--share-net* ]]"
check "…and ws-egress-proxy reads the owner's mode too" bash -c "ws-egress-proxy check azure evil.example | grep -q 'mode off'"
jq -n --arg k "$HOME/.local/bin/ws-mcp-keepalive" '{mcpServers: {recall: {type: "stdio", command: $k, args: ["--name", "recall", "--", "/w/python.exe", "-m", "recall"]}}}' > "$HOME/.claude.json"
: > "$T/claude.log"
"$S" keepalive recall off >/dev/null
check "keepalive off: re-registered without the keepalive" grep -q 'mcp add-json recall {"type":"stdio","command":"/w/python.exe","args":\["-m","recall"\]} --scope user' "$T/claude.log"
check "…and remembered for install.sh" jq -e '.recall.keepalive == false' "$HOME/.config/ws-mcp/overrides.json"
check "install.sh applies the owner's keepalive choice" grep -q 'overrides.json' "$ROOT/install.sh"
check "keepalive of an unknown server is refused" bash -c "! '$S' keepalive nothere on"
printf '#!/bin/sh\nprintf "subscription 1111-prod-sub\\ncontext aks-prod\\n" > "$1"\n' > "$T/ed-ok"
printf '#!/bin/sh\nprintf "this is not valid\\n" > "$1"\n' > "$T/ed-bad"
chmod 755 "$T/ed-ok" "$T/ed-bad"
EDITOR="$T/ed-bad" "$S" production >/dev/null 2>&1
check "an invalid production.conf is not saved" grep -q '0000-prod' "$HOME/.config/ws-guard/production.conf"
EDITOR="$T/ed-ok" "$S" production >/dev/null
check "a valid production.conf is saved (0600)" bash -c "grep -q '1111-prod-sub' '$HOME/.config/ws-guard/production.conf' && [[ \$(stat -c %a '$HOME/.config/ws-guard/production.conf') == 600 ]]"
printf '#!/bin/sh\nprintf "{\\"servers\\": {\\"azure\\": {\\"deny\\": [\\"deploy*\\"]}}}\\n" > "$1"\n' > "$T/ed-json"; chmod 755 "$T/ed-json"
EDITOR="$T/ed-json" "$S" filter >/dev/null
check "the owner's MCP rules are saved as filter.local.json" jq -e '.servers.azure.deny == ["deploy*"]' "$HOME/.config/ws-mcp/filter.local.json"
cp "$ROOT/files/home/.config/ws-mcp/filter.json" "$HOME/.config/ws-mcp/filter.json"
check "a tool the owner denied is not allowed, another one is" python3 -c "
import sys; sys.path.insert(0, '$HOME/.local/lib')
import ws_mcp_policy as p
pol, note = p.load_policy(); r = p.server_rules(pol, 'azure', {'level': 'normal', 'profile': '', 'memory': ''})
assert not p.tool_allowed(r, 'deploy_app')[0] and p.tool_allowed(r, 'storage_list')[0], r
"
check "unknown settings are a usage error" bash -c "'$S' nonsense; [[ \$? == 2 ]]"

echo "== 4. guard"
G="$ROOT/files/home/.claude/hooks/guard.sh"
blocked() { jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}, cwd: "/tmp"}' | bash "$G" >/dev/null 2>&1; [[ $? == 2 ]]; }
passes() { jq -nc --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}, cwd: "/tmp"}' | bash "$G" >/dev/null 2>&1; }
# shellcheck disable=SC2088  # the tilde is part of the command text the guard reads
for c in "ws-settings level normal" "ws-settings window open" "ws-settings egress azure off" "ws-settings hard off" \
         "ws-settings keepalive recall off" "ws-mcp-tools approve azure" "tmux-level default normal" "tmux-level bare %1" \
         "tmux-solo this %1" "ws-telegram toggle" "ws-telegram run no-pin" "ws-lang es" "ws-kit-update" \
         "ws-backup-cloud setup" "WS_LEVEL=full claude" "env WS_LEVEL=bare claude-resume" "~/.local/bin/ws-settings production"; do
  check "blocked from Claude: $c" blocked "$c"
done
for c in "ws-settings show" "ws-settings menu-sync" "ws-telegram status" "ws-lang --get" "tmux-level default" \
         "ws-mcp-tools status" "ws-egress-proxy report"; do
  check "passes: $c" passes "$c"
done
wblocked() { jq -nc --arg p "$1" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}, cwd: "/tmp"}' | bash "$G" >/dev/null 2>&1; [[ $? == 2 ]]; }
for p in "$HOME/.config/ws-mcp/filter.local.json" "$HOME/.config/ws-mcp/egress.local.json" "$HOME/.config/ws-telemetry/budgets.conf" \
         "$HOME/.config/ws-secret/rotation.conf" "$HOME/.config/ws-backup/copy-days" "$HOME/.config/claude-levels/default" \
         "$HOME/.local/share/ws-kit/mcp-tools.lock.json" "$HOME/.local/bin/ws-settings" "$HOME/.local/lib/ws_mcp_policy.py"; do
  check "Claude cannot write ${p#"$HOME"/}" wblocked "$p"
done
check "shellcheck ws-settings" shellcheck -S warning "$S"

echo
echo "Result: $PASS ok · $FAIL failed · $SKIP skipped"
(( FAIL == 0 ))
