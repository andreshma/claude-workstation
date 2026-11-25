#!/usr/bin/env bash
#
# tests/profiles.sh — per-tab profiles (ws-profile, ADR-021) in a temporary HOME, with a simulated tmux and fake
# claude, az and gh that only log their arguments and environment: creating a profile (isolated by default, shared
# with --share-with), the logins with each profile's own folders, refusing to run inside Claude, the environment a
# shell or a restarted tab gets (project pin > tab > default), the fence against other profiles' conversations and
# logins, the MemPalace modes (off blocks, wing:W rewrites the wing), switching a tab (resume only with a shared
# store), claude-account as a wrapper, removing, the audit checks and the migration from claude-accounts.
# No tmux server is started, nothing outside the temporary folder is read or written.
#
# Usage: bash tests/profiles.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

K="$ROOT/files/home"
H="$T/home" F="$T/fake" L="$T/log"
mkdir -p "$H/.local/bin" "$H/.local/lib" "$H/.claude/hooks" "$H/.claude/projects/-repo" "$H/.config/tmux-claude" \
         "$H/.config/claude-levels" "$F" "$T/repos/acme-app/src" "$T/repos/acme-app.wt/feature" "$T/repos/other"
for b in ws-profile claude-account tmux-level claude-resume; do cp "$K/.local/bin/$b" "$H/.local/bin/"; done
cp "$K/.local/lib/ws-profile.sh" "$K/.local/lib/ws-credential-paths.txt" "$H/.local/lib/"
cp "$K/.claude/settings.json" "$H/.claude/settings.json"
cp "$K/.claude/hooks/"{memory-filter.sh,memory-gate.sh,guard.sh} "$H/.claude/hooks/"
cp "$K/.config/tmux-claude/accounts.sh" "$H/.config/tmux-claude/"
cp "$K/.config/claude-levels/normal-adds.json" "$H/.config/claude-levels/"
echo '{"type":"user","cwd":"/repo"}' > "$H/.claude/projects/-repo/c1.jsonl"
echo '{"hasCompletedOnboarding":true,"theme":"dark","oauthAccount":{"emailAddress":"owner@example.test"},"mcpServers":{"mempalace":{"type":"stdio"},"azure":{"type":"stdio"}}}' > "$H/.claude.json"
printf '#!/bin/bash\ncat >/dev/null; printf "%%s|%%s\\n" "$1" "$2" >> "%s/audit.log"\n' "$T" > "$H/.claude/hooks/audit.sh"
chmod +x "$H/.claude/hooks/"*.sh "$H/.local/bin/"*

# Fake CLIs: each logs «name args | the variables of a profile». claude answers auth status per config dir.
for c in claude az gh; do
  cat > "$F/$c" <<EOF
#!/bin/bash
echo "$c \$* | CLAUDE_CONFIG_DIR=\${CLAUDE_CONFIG_DIR:-} AZURE_CONFIG_DIR=\${AZURE_CONFIG_DIR:-} GH_CONFIG_DIR=\${GH_CONFIG_DIR:-} KUBECONFIG=\${KUBECONFIG:-} WS_PROFILE=\${WS_PROFILE:-} WS_MEMORY=\${WS_MEMORY:-}" >> "$L"
if [[ "$c \${1:-} \${2:-}" == "claude auth status" ]]; then
  case "\${CLAUDE_CONFIG_DIR:-}" in *personal) echo "Organization: \${ORG_PERSONAL:-Personal Org}" ;; "") echo "Organization: Company" ;; *) echo "Organization: Client" ;; esac
fi
exit 0
EOF
  chmod +x "$F/$c"
done
# Simulated tmux: logs every call; answers the queries the scripts make from FAKE_* variables (no server).
cat > "$F/tmux" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_DIR/tmux.log"
case "$1" in
  display) case "${!#}" in
             *pane_current_command*) echo bash ;; *pane_pid*) echo 999999 ;; *pane_current_path*) echo "${FAKE_PATH:-/tmp}" ;;
             '#W') echo api ;; *window_id*) echo @1 ;; *pane_id*) echo %1 ;; *) echo x ;; esac ;;
  show|show-options) o="${!#}"; v="FAKE_${o#@}"; [[ -n "${!v:-}" ]] && echo "${!v}" ;;
  has-session) exit 1 ;;
esac
exit 0
EOF
chmod +x "$F/tmux"
export FAKE_DIR="$T"
unset TMUX TMUX_PANE CLAUDECODE CLAUDE_CONFIG_DIR WS_PROFILE WS_PROFILE_PANE WS_MEMORY WS_AGENT AZURE_CONFIG_DIR GH_CONFIG_DIR \
      KUBECONFIG AZURE_TOKEN_CREDENTIALS XDG_CONFIG_HOME XDG_CACHE_HOME
run() { env HOME="$H" PATH="$H/.local/bin:$F:/usr/bin:/bin" WS_LEVELS_DIR="$T/levels" "$@"; }
WP() { run ws-profile "$@"; }
TEN=00000000-0000-0000-0000-0000000000aa SUB=00000000-0000-0000-0000-0000000000bb   # placeholders, not real ids

echo "1) Creating profiles"
check "an invalid name is refused" not WP new "Bad Name" --no-login
check "a built-in name is refused" not WP new work --no-login
check "it refuses to run inside Claude (logins are yours)" bash -c "! CLAUDECODE=1 HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' ws-profile new inside --no-login && [[ ! -e '$H/.config/ws-profiles/inside' ]]"
WP new acme --tenant "$TEN" --subscription "$SUB" --no-login > "$T/new.out" 2>&1
A="$H/.claude-profiles/acme" C="$H/.config/ws-agent/acme"
check "new writes profile.conf (0600) with the tenant, subscription and isolated defaults" bash -c "
  [[ \$(stat -c %a '$H/.config/ws-profiles/acme/profile.conf') == 600 ]] && grep -qx 'tenant=$TEN' '$H/.config/ws-profiles/acme/profile.conf' \
  && grep -qx 'share_conversations=no' '$H/.config/ws-profiles/acme/profile.conf' && grep -qx 'memory=off' '$H/.config/ws-profiles/acme/profile.conf'"
check "its credential dirs are under ~/.config/ws-agent/acme (0700): the agent identity of the same name" bash -c "
  [[ \$(stat -c %a '$C') == 700 && \$(stat -c %a '$C/azure') == 700 && -d '$C/gh' && -d '$C/kube' ]]"
check "the kit setup is linked (settings, hooks) and the conversations are NOT" bash -c "
  [[ -L '$A/settings.json' && -L '$A/hooks' && ! -e '$A/projects' && ! -e '$A/history.jsonl' && ! -e '$A/.credentials.json' ]]"
check "the start-up state and MCP servers are copied, without the account or MemPalace (memory off)" \
  jq -e '.hasCompletedOnboarding and .mcpServers.azure and (.mcpServers.mempalace | not) and (.oauthAccount | not)' "$A/.claude.json"
check "a profile that already exists is not overwritten" not WP new acme --no-login
WP new beta --share-with acme --memory wing:beta_wing --no-login >/dev/null 2>&1
check "--share-with links its conversations to that profile's store" bash -c "[[ \$(readlink '$H/.claude-profiles/beta/projects') == '$A/projects' && -d '$A/projects' ]]"
check "--memory wing:W is stored; an invalid memory value is refused" bash -c "grep -qx 'memory=wing:beta_wing' '$H/.config/ws-profiles/beta/profile.conf' && ! HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' ws-profile new bad --memory 'wing:../x' --no-login"
check "list shows the built-in and the custom profiles" bash -c "WP() { env HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' ws-profile \"\$@\"; }; o=\$(WP list); [[ \$o == *work* && \$o == *personal* && \$o == *acme*off*own* && \$o == *beta*wing:beta_wing*'with acme'* ]]"

echo "2) Logins, each with the profile's own folders"
: > "$L"
WP login acme azure >/dev/null 2>&1
check "az login --tenant and az account set --subscription run with the profile's AZURE_CONFIG_DIR" bash -c "
  grep -q '^az login --tenant $TEN | .*AZURE_CONFIG_DIR=$C/azure' '$L' && grep -q '^az account set --subscription $SUB | .*AZURE_CONFIG_DIR=$C/azure' '$L'"
WP login acme gh >/dev/null 2>&1; WP login acme claude >/dev/null 2>&1
check "gh auth login runs with its GH_CONFIG_DIR, claude auth login with its CLAUDE_CONFIG_DIR" bash -c "
  grep -q '^gh auth login | .*GH_CONFIG_DIR=$C/gh' '$L' && grep -q '^claude auth login | CLAUDE_CONFIG_DIR=$A ' '$L'"
printf 'apiVersion: v1\n' > "$T/kc"; printf '%s\n' "$T/kc" | WP login acme kube >/dev/null 2>&1
check "the kubeconfig is copied into the profile (0600)" bash -c "[[ \$(stat -c %a '$C/kube/config') == 600 ]]"
check "a login from inside Claude is refused" not env CLAUDECODE=1 HOME="$H" PATH="$H/.local/bin:$F:/usr/bin:/bin" ws-profile login acme claude

echo "3) The environment of a profile"
envof() { run bash -c 'eval "$(ws-profile --export '"$1"')" && echo "${CLAUDE_CONFIG_DIR:-unset}|${AZURE_CONFIG_DIR:-unset}|${GH_CONFIG_DIR:-unset}|${KUBECONFIG:-unset}|${AZURE_TOKEN_CREDENTIALS:-unset}|$WS_PROFILE|${WS_MEMORY:-unset}"'; }
check "acme: its Claude dir, az, gh and kubectl folders, the Azure MCP pinned to the az login, memory off" \
  test "$(envof acme)" == "$A|$C/azure|$C/gh|$C/kube/config|AzureCliCredential|acme|off"
check "personal: ~/.claude-personal and your usual credentials; work: CLAUDE_CONFIG_DIR unset" \
  bash -c "[[ \"$(envof personal)\" == '$H/.claude-personal|unset|unset|unset|unset|personal|unset' && \"$(envof work)\" == 'unset|unset|unset|unset|unset|work|unset' ]]"
r="$(run env KUBECONFIG=/my/kube.conf bash -c 'eval "$(ws-profile --export acme)"; eval "$(ws-profile --export work)"; echo "${AZURE_CONFIG_DIR:-unset}|${KUBECONFIG:-unset}|${AZURE_TOKEN_CREDENTIALS:-unset}"')"
check "back to work drops what acme set, and only that" test "$r" == "unset|unset|unset"
r="$(run env KUBECONFIG=/my/kube.conf bash -c 'eval "$(ws-profile --export work)"; echo "$KUBECONFIG"')"
check "a built-in profile keeps a KUBECONFIG of your own" test "$r" == /my/kube.conf
check "an invalid name exports «false», so «eval … && claude» does not start Claude" bash -c "
  [[ \$(HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' ws-profile --export 'x;rm' 2>/dev/null) == false ]]"

echo "4) Which profile a new shell gets (accounts.sh): project pin > tab > default"
WP project acme "$T/repos/acme-app" >/dev/null 2>&1
sh_in() { ( cd "$1" && env -u CLAUDE_CONFIG_DIR -u WS_PROFILE ${2:+"$2"} HOME="$H" PATH="$H/.local/bin:$F:/usr/bin:/bin" FAKE_DIR="$T" \
             bash -c ". '$H/.config/tmux-claude/accounts.sh'; echo \"\${WS_PROFILE:-none}|\${CLAUDE_CONFIG_DIR:-unset}|\${AZURE_CONFIG_DIR:-unset}\"" 2>/dev/null ); }
check "the pinned repo, a subfolder and its worktree open with acme" bash -c "
  [[ '$(sh_in "$T/repos/acme-app/src")' == 'acme|$A|$C/azure' && '$(sh_in "$T/repos/acme-app.wt/feature")' == 'acme|$A|$C/azure' ]]"
check "another folder opens with the default (work)" test "$(sh_in "$T/repos/other")" == "work|unset|unset"
WP use personal >/dev/null 2>&1
check "ws-profile use sets the default for new tabs" test "$(sh_in "$T/repos/other")" == "personal|$H/.claude-personal|unset"
check "the project pin wins over the default" test "$(sh_in "$T/repos/acme-app")" == "acme|$A|$C/azure"
check "a split of a tab with a profile takes the tab's profile (@cprofile)" \
  test "$(sh_in "$T/repos/other" "TMUX=/x,1,0" | head -1)" == "personal|$H/.claude-personal|unset"
r="$( cd "$T/repos/other" && env HOME="$H" PATH="$H/.local/bin:$F:/usr/bin:/bin" FAKE_DIR="$T" TMUX=/x,1,0 TMUX_PANE=%7 FAKE_cprofile=beta \
      bash -c ". '$H/.config/tmux-claude/accounts.sh'; echo \"\$WS_PROFILE|\$WS_MEMORY\"" 2>/dev/null )"
check "…with TMUX_PANE: the tab's beta, and its memory mode" test "$r" == "beta|wing:beta_wing"
r="$( cd "$T/repos/other" && env HOME="$H" PATH="$H/.local/bin:$F:/usr/bin:/bin" FAKE_DIR="$T" TMUX=/x,1,0 TMUX_PANE=%8 WS_PROFILE=acme WS_PROFILE_PANE=%3 \
      bash -c ". '$H/.config/tmux-claude/accounts.sh'; echo \"\$WS_PROFILE\"" 2>/dev/null )"
check "a new pane does not inherit another pane's profile from the server's environment" test "$r" == personal
r="$( cd "$T/repos/other" && env HOME="$H" PATH="$H/.local/bin:$F:/usr/bin:/bin" WS_PROFILE=acme \
      bash -c ". '$H/.config/tmux-claude/accounts.sh'; echo \"\$WS_PROFILE\"" 2>/dev/null )"
check "a nested shell of a profiled shell keeps its profile" test "$r" == acme
r="$( cd "$T/repos/other" && env HOME="$H" PATH="$H/.local/bin:$F:/usr/bin:/bin" CLAUDE_CONFIG_DIR=/my/own/claude \
      bash -c ". '$H/.config/tmux-claude/accounts.sh'; echo \"\$CLAUDE_CONFIG_DIR\"" 2>/dev/null )"
check "a CLAUDE_CONFIG_DIR of your own is left alone" test "$r" == /my/own/claude
check "--resolve gives the same answer" test "$(WP --resolve "$T/repos/acme-app.wt/feature")" == acme
WP use work >/dev/null 2>&1

echo "5) The fence: other profiles' conversations and logins (tmux-level --fenced, claude-resume)"
echo x > "$A/.credentials.json"; mkdir -p "$A/projects/-x"
fw="$(WP --fence work)"; fa="$(WP --fence acme)"; fb="$(WP --fence beta)"
check "work's tabs cannot read acme's conversations nor any profile's Claude login" \
  jq -e --arg a "$A" '(.dirs | index($a + "/projects")) and (.files | index($a + "/.credentials.json")) and (.dirs | index($ENV.HOME + "/.claude/projects") | not)' <<<"$fw"
check "acme's tabs cannot read work's conversations, the MemPalace copies or the audit log" \
  env HOME="$H" jq -e '(.dirs | index($ENV.HOME + "/.claude/projects")) and (.dirs | index($ENV.HOME + "/.cache/ws-memory")) and (.dirs | index($ENV.HOME + "/.claude/audit"))' <<<"$fa"
check "beta shares acme's store: acme's conversations stay readable to it, work's do not" \
  env HOME="$H" jq -e --arg a "$A" '(.dirs | index($a + "/projects") | not) and (.dirs | index($ENV.HOME + "/.claude/projects"))' <<<"$fb"
mkdir -p "$T/levels"; echo '{"sandbox":{"excludedCommands":["az *"]}}' > "$T/levels/normal.json"
g="$(run env WS_PROFILE=acme tmux-level --fenced "$T/levels/normal.json")"
check "tmux-level --fenced writes normal@acme.json (0600): only adds denyRead and Read deny rules" bash -c "
  [[ '$g' == '$T/levels/normal@acme.json' && \$(stat -c %a '$g') == 600 ]] && jq -e --arg w '/$H/.claude/projects' --arg c '/$A/.credentials.json' \
  '(.sandbox.excludedCommands == [\"az *\"]) and (.sandbox.filesystem.denyRead | index(\$w)) and (.sandbox.filesystem.denyRead | index(\$c))
   and (.permissions.deny | index(\"Read(\" + \$w + \"/**)\")) and (.permissions.deny | index(\"Read(\" + \$c + \")\"))' '$g'"
H2="$T/home2"; mkdir -p "$H2/.local/bin" "$H2/.local/lib"; cp "$H/.local/bin/"{ws-profile,tmux-level} "$H2/.local/bin/"; cp "$H/.local/lib/ws-profile.sh" "$H2/.local/lib/"
check "with only work and personal (one store, no custom profile) the file is used as it is" \
  test "$(env HOME="$H2" PATH="$H2/.local/bin:$F:/usr/bin:/bin" tmux-level --fenced "$T/levels/normal.json")" == "$T/levels/normal.json"
: > "$L"
( cd "$T/repos/acme-app" && run env WS_PROFILE=acme CLAUDE_CONFIG_DIR="$A" claude-resume --settings "$T/levels/normal.json" ) </dev/null
check "claude-resume starts Claude with the fenced copy" grep -q "^claude --settings $T/levels/normal@acme.json " "$L"
mkdir -p "$A/projects/${T//[^A-Za-z0-9]/-}-repos-acme-app"; echo '{}' > "$A/projects/${T//[^A-Za-z0-9]/-}-repos-acme-app/s.jsonl"; : > "$L"
( cd "$T/repos/acme-app" && run env WS_PROFILE=acme CLAUDE_CONFIG_DIR="$A" claude-resume --new --settings "$T/levels/normal.json" ) </dev/null
check "claude-resume --new starts a new conversation even when the folder has one" bash -c "grep -q '^claude --settings ' '$L' && ! grep -q -- '--continue' '$L'"

echo "6) MemPalace per profile (memory-filter.sh, memory-gate.sh)"
MF="$H/.claude/hooks/memory-filter.sh" MG="$H/.claude/hooks/memory-gate.sh"
printf '#!/bin/bash\ncat > "%s/mp.in"; echo ran >> "%s/mp.ran"\n' "$T" "$T" > "$F/mempalace-fake"; chmod +x "$F/mempalace-fake"
tr="$T/sess-1.jsonl"; printf '%s\n' '{"type":"user","cwd":"/home/u/clients/acme-secret-project","message":{"content":"hi"}}' \
  '{"type":"assistant","cwd":"/home/u/clients/acme-secret-project","message":{"content":"ok"}}' > "$tr"
hook() { jq -nc --arg t "$tr" '{hook_event_name: "Stop", session_id: "s1", transcript_path: $t, cwd: "/home/u/clients/acme-secret-project"}' \
         | run env "$@" bash "$MF" mempalace-fake mempalace hook run --hook stop; }
rm -f "$T/mp.ran"; hook WS_MEMORY=off
check "memory off: the MemPalace hook is NOT run, and the skip is audited" bash -c "[[ ! -e '$T/mp.ran' ]] && grep -q 'memory-skip|.*memory off' '$T/audit.log'"
rm -f "$T/mp.ran"; hook CLAUDE_CONFIG_DIR="$A"
check "…also for a Claude started by hand in acme's dir (no WS_MEMORY): the profile's memory is off" test ! -e "$T/mp.ran"
cp "$F/mempalace-fake" "$F/recall-fake"; rm -f "$T/mp.ran"
jq -nc '{prompt: "find the book"}' | run env WS_MEMORY=off bash "$MF" "$F/recall-fake" recall_hook.py
check "the recall hook (books, not your work) still runs with memory off" test -e "$T/mp.ran"
rm -f "$T/mp.ran"; hook WS_MEMORY=wing:acme_w
cp_tp="$(jq -r .transcript_path "$T/mp.in")"
check "memory wing:W: MemPalace gets a copy whose cwd is /ws-profile/W (the wing it files into)" bash -c "
  [[ '$cp_tp' != '$tr' ]] && [[ \$(jq -r .cwd '$cp_tp' | sort -u) == /ws-profile/acme_w ]] && [[ \$(jq -r .cwd '$T/mp.in') == /ws-profile/acme_w ]]"
check "…the real folder name reaches it nowhere, and the original transcript is untouched" bash -c "
  ! grep -q acme-secret-project '$cp_tp' && ! grep -q acme-secret-project '$T/mp.in' && grep -q acme-secret-project '$tr'"
hook WS_MEMORY=wing:acme_w; cp2="$(jq -r .transcript_path "$T/mp.in")"
check "…one copy per session, replaced on every hook (not one per reply)" test "$cp_tp" == "$cp2"
rm -f "$T/mp.ran"; hook WS_MEMORY=on
check "memory on (work, personal): the hook gets the transcript unchanged" bash -c "[[ -e '$T/mp.ran' && \$(jq -r .transcript_path '$T/mp.in') == '$tr' ]]"
gate() { jq -nc --arg t "mcp__mempalace__mempalace_$1" --argjson i "$2" '{hook_event_name: "PreToolUse", tool_name: $t, tool_input: $i, session_id: "s", cwd: "/r"}' \
         | run env "${@:3}" bash "$MG"; }
check "memory off: a MemPalace READ is blocked (the palace holds other clients' work)" bash -c "
  jq -nc '{hook_event_name: \"PreToolUse\", tool_name: \"mcp__mempalace__mempalace_search\", tool_input: {query: \"x\"}}' | HOME='$H' WS_PROFILE=acme WS_MEMORY=off bash '$MG' 2>/dev/null; [[ \$? == 2 ]]"
r="$(gate search '{"query":"x","wing":"other"}' WS_MEMORY=wing:acme_w)"
check "memory wing:W: a search is allowed with its wing forced to W" jq -e '.hookSpecificOutput.permissionDecision == "allow" and .hookSpecificOutput.updatedInput.wing == "acme_w"' <<<"$r"
r="$(gate add_drawer '{"wing":"other","room":"r","content":"c"}' WS_MEMORY=wing:acme_w)"
check "…a write still asks you, with the wing forced" jq -e '.hookSpecificOutput.permissionDecision == "ask" and .hookSpecificOutput.updatedInput.wing == "acme_w"' <<<"$r"
check "…a tool that cannot be limited to one wing (kg_query, get_drawer) is blocked" bash -c "
  for t in kg_query get_drawer status; do jq -nc --arg t \"mcp__mempalace__mempalace_\$t\" '{tool_name: \$t, tool_input: {}}' | HOME='$H' WS_MEMORY=wing:acme_w bash '$MG' 2>/dev/null; [[ \$? == 2 ]] || exit 1; done"
check "memory on: a read passes untouched" bash -c "[[ -z \$(jq -nc '{tool_name: \"mcp__mempalace__mempalace_search\", tool_input: {query: \"x\"}}' | HOME='$H' bash '$MG') ]]"

echo "7) Switching a tab (simulated tmux)"
: > "$T/tmux.log"
r="$(run env FAKE_PATH="$T/repos/other" TMUX=/x,1,0 ws-profile tab beta %1 2>&1)"
check "a profile that is not signed in to Claude is refused" bash -c "grep -q 'beta.*is not signed in' '$T/tmux.log' && ! grep -q 'send-keys' '$T/tmux.log'"
: > "$T/tmux.log"
run env FAKE_PATH="$T/repos/other" ws-profile tab acme %1 >/dev/null 2>&1
check "work → acme (another store): a NEW conversation, typed after the profile's environment" \
  grep -qF -- "send-keys -t %1 -l eval \"\$(ws-profile --export acme)\" && claude-resume --new --settings '$T/levels/normal.json'" "$T/tmux.log"
check "…and the tab is marked: @cprofile, its label and colour, @caccount work" bash -c "
  grep -q 'set -w -t @1 @cprofile acme' '$T/tmux.log' && grep -q 'set -w -t @1 @cprofile_label acme' '$T/tmux.log' && grep -q 'set -w -t @1 @cprofile_colour colour214' '$T/tmux.log' && grep -q 'set -w -t @1 @caccount work' '$T/tmux.log'"
check "…audited" grep -q 'profile-tab|work → acme (new conversation)' "$T/audit.log"
WP setup personal >/dev/null 2>&1; echo x > "$H/.claude-personal/.credentials.json"
: > "$T/tmux.log"
run env FAKE_PATH="$T/repos/other" ws-profile tab personal %1 >/dev/null 2>&1
check "work → personal (shared store): resumes the same conversation, «·P» added" bash -c "
  grep -qF -- \"send-keys -t %1 -l eval \\\"\\\$(ws-profile --export personal)\\\" && claude-resume --settings '$T/levels/normal.json'\" '$T/tmux.log' && grep -q 'rename-window -t @1 api·P' '$T/tmux.log'"
: > "$T/tmux.log"
run env FAKE_PATH="$T/repos/other" FAKE_cprofile=acme FAKE_csolo=1 ws-profile tab work %1 >/dev/null 2>&1
check "a tab in solo mode stays in solo mode (as claude-account did)" grep -q -- "-l eval .*--export work)\" && claude-resume --new --permission-mode auto --settings" "$T/tmux.log"
: > "$T/tmux.log"
run env FAKE_cprofile=acme tmux-level --command normal "" --pane %1 > "$T/cmd.out"
check "tmux-level --command … --pane keeps the tab's profile" grep -qF "eval \"\$(ws-profile --export acme)\" && claude-resume --settings" "$T/cmd.out"
check "tmux-level --command without --pane is unchanged (no prefix)" bash -c "[[ \$(HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' WS_LEVELS_DIR='$T/levels' tmux-level --command normal) == claude-resume* ]]"

echo "8) claude-account is a wrapper"
run claude-account use personal >/dev/null 2>&1
check "claude-account use writes the profiles' default" test "$(cat "$H/.config/ws-profiles/default")" == personal
run claude-account project work "$T/repos/other" >/dev/null 2>&1
check "claude-account project pins in the profiles' projects.conf" grep -qx "work $T/repos/other" "$H/.config/ws-profiles/projects.conf"
check "claude-account projects lists them" bash -c "HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' claude-account projects | grep -q 'work *$T/repos/other'"
check "claude-account status shows each organisation" bash -c "HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' claude-account status | grep -q 'personal: Organization: Personal Org'"
run claude-account use work >/dev/null 2>&1

echo "9) The audit checks (ws-audit → ws-profile audit)"
out="$(WP audit)"
check "the kit's settings keep every profile's logins out of the sandbox" bash -c "grep -q \$'^ok\tprofile acme: the sandbox cannot read its Claude login' <<<'$out' && grep -q \$'^ok\tprofile acme: the sandbox cannot read its az, gh and kubectl' <<<'$out'"
WP new gamma --tenant "$TEN" --subscription "$SUB" --no-login >/dev/null 2>&1
ln -s "$H/.claude/projects" "$H/.claude-profiles/gamma/projects"
out="$(WP audit)"
check "two profiles with the same tenant and subscription are reported" grep -q $'^warn\tprofiles acme and gamma declare the same tenant and subscription' <<<"$out"
check "an isolated profile with a conversation link fails" grep -q $'^fail\tprofile gamma is isolated but links conversations' <<<"$out"
jq '.sandbox.filesystem.denyRead -= ["~/.claude-profiles/*/.credentials.json", "~/.config/ws-agent"]' "$K/.claude/settings.json" > "$H/.claude/settings.json"
out="$(WP audit)"
check "a profile login the sandbox could read fails" grep -q $'^fail\tprofile acme: its Claude login is readable by sandboxed commands' <<<"$out"
check "…and so do its az, gh and kubectl credentials" grep -q $'^fail\tprofile acme: its az, gh or kubectl credentials are readable' <<<"$out"
cp "$K/.claude/settings.json" "$H/.claude/settings.json"
WP setup gamma >/dev/null 2>&1
check "ws-profile setup removes the link of an isolated profile (the data stays)" bash -c "[[ ! -e '$H/.claude-profiles/gamma/projects' && -d '$H/.claude/projects/-repo' ]]"

echo "10) Removing a profile"
printf 'n\n' | WP remove gamma >/dev/null 2>&1
check "answering no changes nothing" test -f "$H/.config/ws-profiles/gamma/profile.conf"
printf 'y\nno\n' | WP remove gamma >/dev/null 2>&1
check "yes removes its settings; its credentials stay without the typed name" bash -c "[[ ! -e '$H/.config/ws-profiles/gamma' && -d '$H/.config/ws-agent/gamma' && -d '$H/.claude-profiles/gamma' ]]"
WP new delta --no-login >/dev/null 2>&1; WP project delta "$T/repos/other" >/dev/null 2>&1; WP use delta >/dev/null 2>&1
printf 'y\ndelta\n' | WP remove delta >/dev/null 2>&1
check "the typed name deletes its credentials and conversations, its pins and the default" bash -c "
  [[ ! -e '$H/.config/ws-agent/delta' && ! -e '$H/.claude-profiles/delta' ]] && ! grep -q '^delta ' '$H/.config/ws-profiles/projects.conf' && [[ \$(cat '$H/.config/ws-profiles/default') == work ]]"
check "built-in profiles cannot be removed; nothing is removed from inside Claude" bash -c "
  ! HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' ws-profile remove work </dev/null && printf 'y\nacme\n' | { ! CLAUDECODE=1 HOME='$H' PATH='$H/.local/bin:$F:/usr/bin:/bin' ws-profile remove acme; } && [[ -d '$C' ]]"

echo "11) Migration from claude-accounts (migrate.sh, idempotent, dry run)"
M="$T/mig"; mkdir -p "$M/.config/claude-accounts"; echo personal > "$M/.config/claude-accounts/active"
printf 'personal /a/b\nwork /c/d\ntrabajo /e/f\n' > "$M/.config/claude-accounts/projects.conf"
mig() { HOME="$M" DRY="$1" KIT="$ROOT" bash -c 'source "$KIT/lib.sh"; source "$KIT/migrate.sh"; migrate_profiles' 2>&1; }
out="$(mig 1)"
check "dry run: says what it would do and writes nothing" bash -c "[[ '$out' == *'default = personal'* && ! -e '$M/.config/ws-profiles' ]]"
mig 0 >/dev/null
check "moves the default and the pinned projects (an old value means work)" bash -c "
  [[ \$(cat '$M/.config/ws-profiles/default') == personal ]] && diff <(printf 'personal /a/b\nwork /c/d\nwork /e/f\n') '$M/.config/ws-profiles/projects.conf'"
echo work > "$M/.config/claude-accounts/active"; out="$(mig 0)"
check "a second run changes nothing (the new files win)" bash -c "[[ -z '$out' && \$(cat '$M/.config/ws-profiles/default') == personal ]]"

echo "12) Static: the sandbox, the guard and the managed policy cover every profile's credentials"
S="$K/.claude/settings.json"
check "denyRead has ~/.config/ws-agent (every profile's az, gh and kube) and the glob of every profile's Claude login" \
  jq -e '.sandbox.filesystem.denyRead | index("~/.config/ws-agent") and index("~/.claude-profiles/*/.credentials.json")' "$S"
check "Read deny rules for the same, and Edit deny rules for the profiles' config and Claude dirs" \
  jq -e '.permissions.deny | index("Read(~/.claude-profiles/*/.credentials.json)") and index("Read(~/.config/ws-agent/**)") and index("Edit(~/.config/ws-profiles/**)") and index("Edit(~/.claude-profiles/*/settings.json)")' "$S"
check "the managed policy carries the same rules" \
  jq -e '.permissions.deny | index("Read(~/.claude-profiles/*/.credentials.json)") and index("Edit(~/.config/ws-profiles/**)")' "$ROOT/files/etc/claude-code/managed-settings.json"
# shellcheck disable=SC2088  # a literal line of the list
check "the guard's credential list has the glob" grep -qxF '~/.claude-profiles/*/.credentials.json' "$K/.local/lib/ws-credential-paths.txt"
for f in "$K/.local/bin/ws-profile" "$K/.local/lib/ws-profile.sh" "$K/.config/tmux-claude/accounts.sh"; do
  check "shellcheck and bash -n: ${f#"$ROOT"/}" bash -c "bash -n '$f' && { ! command -v shellcheck || shellcheck -S warning -x '$f'; }"
done

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
