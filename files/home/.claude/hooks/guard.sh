#!/usr/bin/env bash
#
# guard.sh — deterministic guardrails for Claude Code (PreToolUse hook). Part of the FLOOR of ADR-013: it runs at
# every protection level (full, normal, solo and bare).
# Blocks with exit 2 (Claude receives the reason and looks for another way) actions against policy:
#   · forced git push (--force, -f, -fu, +refspec) · push to main/master (explicit, refs/heads/… or while on that one)
#   · bypassing the git gate (--no-verify, core.hooksPath, ws.gate.*) · commits with Co-authored-by
#   · download and run (curl|wget … | sh, sh <(curl …)) · reading secrets with ws-secret get, gh auth token or
#     kubectl config view --raw · running ws-learn and «ws-memory save-facts|review» (they ask YOU to approve what
#     they save), «ws-stop-all --clear», «ws-telemetry budgets --override», setting WS_MEMORY_APPROVED/WS_MEMORY_GATE,
#     and MemPalace's own write commands (mempalace mine|add|kg|…), which skip the memory gate
#   · mutating az, kubectl, helm and Azure MCP tools against production: a subscription (ID or name) or kube context
#     listed in ~/.config/ws-guard/production.conf, or one whose name matches GUARD_PROD_REGEX
#   · writing secrets to files (private keys, tokens, AccountKey, SAS)
#   · writing to the agent's persistent configuration (WS-AI-014), with a file tool or with a shell redirection, tee,
#     cp, mv, ln, install, rm, sed -i, dd, tar…: settings*.json, hooks, ~/.claude.json, plugins, the status line, the
#     level and solo profiles, the guard's own lists, ~/.config/git/hooks, /etc/claude-code, the kit's update keys and
#     pinned packages (~/.config/ws-kit, ~/.local/share/ws-kit, ~/.local/lib/ws-npm), agent-browser's policy, the
#     Telegram configuration, the audit log and its Windows anchors, the stop and budget markers and the gate's
#     opt-out log (always); CLAUDE.md, commands, agents, skills and the Windows-side .claude folder (unless you
#     opened a window, see below); a recursive rm, mv, rsync, cp -r, tar or unzip that contains any of them
#     · claude mcp add|add-json|remove and claude plugin install|enable|marketplace add (WS-AI-010)
#   · the owner's settings (Menu → Settings, ADR-028): ws-settings (except show, get, menu-sync), ws-mcp-tools
#     approve|forget (trusted MCP tool definitions, ADR-027), tmux-level default|bare, tmux-solo, ws-telegram's
#     settings (all but status and menu-sync), ws-lang en|es|--toggle, ws-kit-update, ws-backup-cloud setup, WS_LEVEL
#   · naming a credential store in a command, or reaching one through a link or «..» (WS-SEC-002): the list is
#     ~/.local/lib/ws-credential-paths.txt (the same entries as sandbox.filesystem.denyRead) plus, when installed,
#     /etc/claude-code/ws-credential-paths.txt; without either, a built-in minimum
#   · in a tab with an agent identity (WS_AGENT, set by tmux-level) or a custom profile (WS_PROFILE other than work or
#     personal, ADR-021), switching Claude, az, gh or kubectl to other credentials (CLAUDE_CONFIG_DIR,
#     AZURE_CONFIG_DIR, GH_CONFIG_DIR, KUBECONFIG, AZURE_TOKEN_CREDENTIALS, GIT_SSH_COMMAND, tokens, --kubeconfig, env -i, logins:
#     az login, gh auth login|switch|refresh|setup-git, claude auth login|logout, claude setup-token) (WS-AI-026);
#     in any tab, setting WS_PROFILE or WS_MEMORY (the memory mode the MemPalace hooks honour), and the commands that
#     switch or create profiles and accounts (ws-profile new|login|logout|tab|use|project|remove|setup,
#     claude-account setup|login|logout|tab|use|project): profiles, their config (~/.config/ws-profiles) and their
#     Claude dirs (~/.claude-profiles/*: settings, hooks, .claude.json; the login is a credential store) are yours
# Fails CLOSED: if it cannot read the input (no jq or invalid JSON) or resolve the paths, it blocks, because it does
# not know what it is letting through. To decide, it ignores quoted text that contains spaces (an echo, a grep or a
# commit message that mention a forced push or a protected file are not blocked); a quoted single word still counts
# as a path, with the shell's rules (no ~ inside quotes, no $HOME inside single quotes).
# It is defense in depth, not an absolute control: a command it cannot parse (python -c, base64…) gets past it, and
# RBAC, the sandbox and human review still rule.
# Window for CLAUDE.md/commands/agents/skills (owner only, from a plain shell; the agent cannot write it):
#   date -d '+30 min' +%s > ~/.config/ws-guard/allow-config-writes      (each allowed write is audited)
# Usage: PreToolUse hook (hook JSON on stdin, exit 2 blocks). Tests: bash tests/guard.sh
set -uo pipefail
input="$(cat)"
closed() { printf 'BLOCKED by policy (guard.sh): %s\n' "$1" >&2; exit 2; }
if ! command -v jq >/dev/null 2>&1 || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$input"; then
  closed "could not read the action (jq is missing or the input is not JSON)"
fi
# One jq call for every field the checks use: each jq start costs ~5 ms, on every tool call.
fields="$(jq -r '@sh "tool=\(.tool_name // "" | tostring) cmd=\(.tool_input.command // "" | tostring) cwd=\(.cwd // "" | tostring) path=\(.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // "" | tostring)"' <<<"$input" 2>/dev/null)" \
  || closed "could not read the action's fields"
tool="" cmd="" cwd="" path=""
eval "$fields"
H="$HOME"
PROD="${GUARD_PROD_REGEX:-prod|prd|produccion}"
PROD_CONF="${WS_GUARD_PRODUCTION:-$H/.config/ws-guard/production.conf}"

# block <reason> — records it in the audit log and blocks the action.
block() {
  "$H/.claude/hooks/audit.sh" blocked "$1" <<<"$input" >/dev/null 2>&1
  printf 'BLOCKED by policy (guard.sh): %s\n' "$1" >&2
  exit 2
}

# --- Protected locations ---------------------------------------------------------------------------------------
# hard: what steers or constrains every later session, or runs outside the sandbox; never written from Claude.
# soft: instructions and personal extensions; writable only inside a window the owner opens (header).
cfg_hard=() cfg_soft=()
for d in "$H/.claude" "$H/.claude-personal" "$H"/.claude-profiles/* ${CLAUDE_CONFIG_DIR:+"$CLAUDE_CONFIG_DIR"}; do
  [[ "$d" == "$H/.claude-profiles/*" ]] && continue   # no profile dir: the glob stayed as it is
  cfg_hard+=("$d/settings.json" "$d/settings.local.json" "$d/hooks" "$d/.claude.json" "$d/plugins" "$d/statusline.sh")
  cfg_soft+=("$d/CLAUDE.md" "$d/commands" "$d/agents" "$d/skills")
done
cfg_hard+=("$H/.claude.json" "$H/.config/git/hooks" "$H/.config/claude-levels" "$H/.config/claude-solo"
  "$H/.config/ws-guard" "$H/.config/ws-agent" "$H/.config/ws-profiles" "$H/.config/claude-accounts"
  "$H/.local/lib/ws-credential-paths.txt" "$H/.local/lib/ws-profile.sh" /etc/claude-code
  "$H/.config/ws-kit" "$H/.local/share/ws-kit" "$H/.local/lib/ws-npm" "$H/.config/agent-browser" "$H/.config/ws-telegram"
  "$H/.claude/audit" "$H/.local/state/ws-stop-all" "$H/.local/state/ws-budget-over" "$H/.local/state/ws-budget-override"
  "$H/.local/state/ws-gate" "$H/.local/lib/ws-tools.lock" "$H/.local/lib/ws-mirror.sh" "$H/.config/tmux-claude/plugins.lock"
  "$H/.tmux/plugins" "$H/.local/state/ws-tools" "$H/.local/state/ws-plugins" "$H/.local/state/ws-backup-mirror.state"
  "$H/.local/bin/ws-mcp-jail" "$H/.local/bin/ws-gate" "$H/.config/ws-mcp"   # ADR-024: the MCP jail and its allow list
  "$H/.local/bin/ws-mcp-keepalive" "$H/.local/state/ws-mcp"   # ADR-025: the keepalive, its logs and the jail state
  "$H/.local/bin/ws-mcp-filter" "$H/.local/bin/ws-mcp-tools" "$H/.local/bin/ws-egress-proxy" "$H/.local/lib/ws_mcp_policy.py"
  "$H/.local/bin/ws-settings" "$H/.config/ws-secret" "$H/.config/ws-backup" "$H/.config/ws-telemetry/budgets.conf")   # ADR-027, ADR-028
cred=()
for f in /etc/claude-code/ws-credential-paths.txt "$H/.local/lib/ws-credential-paths.txt"; do
  [[ -r "$f" ]] || continue
  while IFS= read -r l || [[ -n "$l" ]]; do
    l="${l%%#*}"; l="${l%"${l##*[![:space:]]}"}"; l="${l#"${l%%[![:space:]]*}"}"
    [[ -n "$l" ]] || continue
    l="${l/#\~/$H}"
    if [[ "$l" == *[*?[]* ]]; then   # a glob line (one entry per profile): what it matches now
      while IFS= read -r g; do cred+=("$g"); done < <(compgen -G "$l" 2>/dev/null | head -200)
    else cred+=("$l"); fi
  done < "$f"
done
(( ${#cred[@]} )) || cred=("$H/.ssh" "$H/.aws" "$H/.azure" "$H/.config/gh" "$H/.kube" "$H/.gnupg" "$H/.netrc"
  "$H/.git-credentials" "$H/.docker/config.json" "$H/.claude/.credentials.json" "$H/.claude-personal/.credentials.json")

# expand <word> <base> — the path the shell would use, in REPLY: ~ and $HOME expanded, relative to <base>. Words
# from quoted text arrive with ~ as \002 and (single quotes) $ as \003, so they are not expanded, as in the shell.
expand() {
  local w="$1"
  case "$w" in
    \~|\~/*) w="$H${w:1}" ;;
    '$HOME'|'$HOME/'*) w="$H${w:5}" ;;
    '${HOME}'|'${HOME}/'*) w="$H${w:7}" ;;
  esac
  [[ "$w" == /* ]] || w="$2/$w"
  REPLY="$w"
}

# scan — checks the paths queued in kinds[]/paths[] («w» any word, «t» a write target, «a» a recursive target that
# also counts when it CONTAINS a root: rm -r ~/.claude, rsync … ~/). Resolves them all with one realpath call (links
# followed, «..» removed) and prints «<cred|hard|soft> <path>» for each hit: any word under a credential store, a
# write target under any root, and (soft) a write under a Windows-side .claude folder, whose CLAUDE.md the kit
# imports. Compared in lowercase (/mnt/c ignores case).
kinds=() paths=()
queue() { local w; for w in "${@:3}"; do [[ -n "$w" && ${#w} -le 1024 ]] || continue; expand "$w" "$2"; kinds+=("$1"); paths+=("$REPLY"); done; }
scan() {
  (( ${#paths[@]} )) || return 0
  local roots=("${cred[@]}" "${cfg_hard[@]}" "${cfg_soft[@]}") rk=() res n _
  for _ in "${cred[@]}"; do rk+=(cred); done
  for _ in "${cfg_hard[@]}"; do rk+=(hard); done
  for _ in "${cfg_soft[@]}"; do rk+=(soft); done
  n=$(( ${#roots[@]} + ${#paths[@]} ))
  res="$(realpath -m -- "${roots[@]}" "${paths[@]}" 2>/dev/null)"
  [[ "$(grep -c '' <<<"$res")" == "$n" ]] || closed "could not resolve the paths of the action"
  paste <(printf '%s\n' "${rk[@]}" "${kinds[@]}") <(printf '%s\n' "$res") | awk -F'\t' -v nr="${#roots[@]}" '
    NR <= nr { r[NR] = tolower($2); k[NR] = $1; next }
    { p = tolower($2)
      for (i = 1; i <= nr; i++) {
        hit = (p == r[i] || index(p, r[i] "/") == 1)
        if (!hit && $1 == "a" && k[i] != "cred") hit = (p == "/" || index(r[i], p "/") == 1)
        if (hit && (k[i] == "cred" || $1 != "w") && !seen[k[i]]++) print k[i] "\t" $2 }
      if ($1 != "w" && p ~ /^\/mnt\/[a-z]\/users\/[^\/]+\/\.claude(\/|$)/ && !seen["soft"]++) print "soft\t" $2
      if ($1 != "w" && p ~ /^\/mnt\/[a-z]\/users\/[^\/]+\/ws-telemetry(\/audit-anchors\.txt)?$/ && !seen["hard"]++) print "hard\t" $2 }'
}
# verdict — blocks on what scan found: credential stores and hard roots always; soft roots outside the window.
verdict() {
  local hits kind p now until=0
  hits="$(scan)" || exit 2
  [[ -n "$hits" ]] || return 0
  while IFS=$'\t' read -r kind p; do
    case "$kind" in
      cred) block "that names a credential store ($p): credentials are not read from Claude; use the tool's own login" ;;
      hard) block "that writes to the agent's persistent configuration ($p): change it yourself, in a plain shell" ;;
    esac
  done <<<"$hits"
  { read -r until < "$H/.config/ws-guard/allow-config-writes"; } 2>/dev/null
  printf -v now '%(%s)T' -1
  if [[ "$until" =~ ^[0-9]+$ ]] && (( until > now )); then
    "$H/.claude/hooks/audit.sh" config-write-allowed "${hits//$'\t'/ }" <<<"$input" >/dev/null 2>&1
    return 0
  fi
  p="$(cut -f2 <<<"$hits" | head -1)"
  block "that writes to CLAUDE.md, commands, agents or skills ($p), which steer later sessions: do it yourself, or open a window (see guard.sh)"
}

# prod_listed <kind> <value…> — 0 (and PROD_HIT) when a value is listed in production.conf under <kind>.
prod_listed() {
  local kind="$1" k v x; shift
  [[ -r "$PROD_CONF" ]] || return 1
  while read -r k v || [[ -n "$k" ]]; do   # the value is the rest of the line: names may have spaces
    v="${v%%#*}"; v="${v%"${v##*[![:space:]]}"}"
    [[ "$k" == "$kind" && -n "$v" ]] || continue
    for x in "$@"; do [[ -n "$x" && "${x,,}" == "${v,,}" ]] && { PROD_HIT="$x"; return 0; }; done
  done < "$PROD_CONF"
  return 1
}
# prod_sub <what> <subscription…> — blocks when one of them is production (listed first, then by name).
prod_sub() {
  local what="$1" s; shift
  prod_listed subscription "$@" && block "$what against a production subscription listed in production.conf ($PROD_HIT): run it yourself, outside Claude"
  for s in "$@"; do
    grep -Eqi "$PROD" <<<"$s" && block "$what against the production subscription ($s): run it yourself, outside Claude"
  done
  return 0
}

case "$tool" in
  Bash)
    # Without the quoted text: what remains are the words the shell executes.
    sc="$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$cmd")"
    GIT='git([[:space:]]+-[cC][[:space:]]*[^[:space:]]+)*[[:space:]]+'
    if grep -Eq "${GIT}push([[:space:]]|\$)" <<<"$sc"; then
      rest="$(grep -Eo "${GIT}push[^|;&]*" <<<"$sc" | sed -E "s/^${GIT}push//" | tr '\n' ' ')"
      grep -Eq '(^|[[:space:]])(--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)|(^|[[:space:]])\+[^[:space:]]' <<<"$rest" &&
        block "forced git push (use --force-with-lease on your branch, or do it yourself)"
      grep -Eq '(^|[[:space:]:/])(main|master)([[:space:]]|$)' <<<"$rest" &&
        block "direct push to main/master: work on a branch and open a PR"
      # «git push» with no branch (zero or one non-option argument) or with HEAD: pushes the current branch.
      args="$(tr ' ' '\n' <<<"$rest" | grep -Evc '^(-.*)?$')"
      if (( args < 2 )) || grep -Eq '(^|[[:space:]:])HEAD([[:space:]:]|$)' <<<"$rest"; then
        branch="$(git -C "${cwd:-.}" branch --show-current 2>/dev/null)"
        [[ "$branch" == main || "$branch" == master ]] && block "push while on $branch: work on a branch and open a PR"
      fi
    fi
    grep -Eq "${GIT}(commit|push|merge|rebase|am|cherry-pick)[^|;&]*[[:space:]]--no-verify([[:space:]]|\$)" <<<"$sc" &&
      block "--no-verify bypasses the git gate: fix what it flags"
    grep -Eq '(^|[;&|[:space:]])git[[:space:]]' <<<"$sc" && grep -Eqi 'core\.hookspath|ws\.gate\.' <<<"$sc" &&
      block "changing core.hooksPath or ws.gate.* disables the git gate: do it yourself if it is really needed"
    grep -Eq '(^|[;&|[:space:](])(export[[:space:]]+)?WS_MEMORY_(APPROVED|GATE)=' <<<"$sc" &&
      block "WS_MEMORY_APPROVED and WS_MEMORY_GATE are set by you or ws-memory, never from Claude"
    grep -Eq '(^|[;&|[:space:](])(export[[:space:]]+)?WS_(TOOLS_ALLOW_UNVERIFIED|PLUGINS_ALLOW_UNPINNED)=' <<<"$sc" &&
      block "WS_TOOLS_ALLOW_UNVERIFIED and WS_PLUGINS_ALLOW_UNPINNED install unverified code: you decide that, not Claude"
    grep -Eq '(^|[;&|[:space:](])(export[[:space:]]+|unset[[:space:]]+([^;&|]*[[:space:]])?|-u[[:space:]]*)?(WS_MEMORY|WS_PROFILE|WS_PROFILE_PANE)([=[:space:]]|$)' <<<"$sc" &&
      block "WS_PROFILE and WS_MEMORY come with the tab's profile (ws-profile): they are not changed from Claude"
    grep -Eq '(^|[;&|[:space:](])(export[[:space:]]+|unset[[:space:]]+([^;&|]*[[:space:]])?|-u[[:space:]]*)?WS_LEVEL([=[:space:]]|$)' <<<"$sc" &&
      block "WS_LEVEL comes with the tab's protection level (tmux-level): it is not changed from Claude"
    grep -Eq "${GIT}commit" <<<"$sc" && grep -qi 'co-authored-by' <<<"$cmd" &&
      block "Co-authored-by is forbidden by the organization's policy"
    grep -Eq '(curl|wget)[^|;&]*\|[[:space:]]*(sudo([[:space:]]+-[^[:space:]]+)*[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$)' <<<"$sc" &&
      block "curl|sh: download the script, review it and run it yourself"
    grep -Eq '(^|[;&|[:space:]])(ba|z|da)?sh[[:space:]]+<\([[:space:]]*(curl|wget)' <<<"$sc" &&
      block "sh <(curl …): download the script, review it and run it yourself"
    grep -Eq '(^|[;&|[:space:](])ws-secret[[:space:]]+get([[:space:]]|$)' <<<"$sc" &&
      block "ws-secret get prints a secret: use it yourself, outside Claude"
    grep -Eq '(^|[;&|[:space:](])gh[[:space:]]+auth[[:space:]]+token([[:space:]]|$)' <<<"$sc" &&
      block "gh auth token prints a credential: gh uses it by itself, it is never needed in the conversation"
    grep -Eq '(^|[;&|[:space:](])kubectl([[:space:]]+[^[:space:]|;&]+)*[[:space:]]+config[[:space:]]+view([^|;&]*)--raw' <<<"$sc" &&
      block "kubectl config view --raw prints the cluster credentials: use kubectl config view without --raw"
    grep -Eq '(^|[;&|[:space:](])(claude|claude-resume)([[:space:]]+-[^[:space:]]+)*[[:space:]]+mcp[[:space:]]+(add|add-json|add-from-claude-desktop|remove)([[:space:]]|$)' <<<"$sc" &&
      block "registering or removing MCP servers changes what runs outside the sandbox in every session: do it yourself (claude mcp … in a plain shell)"
    grep -Eq '(^|[;&|[:space:](])claude([[:space:]]+-[^[:space:]]+)*[[:space:]]+plugins?[[:space:]]+(install|i|enable|marketplace[[:space:]]+add)([[:space:]]|$)' <<<"$sc" &&
      block "installing or enabling plugins adds hooks and MCP servers to every session: do it yourself (/plugin or claude plugin … in a plain shell)"
    if grep -Eq '(^|[;&|[:space:]])az[[:space:]].*[[:space:]](create|update|delete|delete-batch|set|start|stop|restart|deallocate|scale|purge|deploy|invoke|assign|import|swap|upload|remove)([[:space:]]|$)' <<<"$sc"; then
      subs=()
      while IFS= read -r s; do [[ -n "$s" ]] && subs+=("$s"); done < <(
        grep -Eo -- "--subscription([[:space:]]+|=)(\"[^\"]*\"|'[^']*'|[^[:space:]]+)" <<<"$cmd" | sed -E 's/^--subscription([[:space:]]+|=)//' | tr -d "\"'"
        grep -Eio '/subscriptions/[0-9a-f-]{36}' <<<"$cmd" | cut -d/ -f3
        grep -Eo '(ARM|AZURE)_SUBSCRIPTION_ID=[^[:space:];&|]+' <<<"$cmd" | cut -d= -f2 | tr -d "\"'")
      if (( ${#subs[@]} == 0 )); then   # the active one: name and ID (the CLI's own profile, per identity)
        while IFS= read -r s; do [[ -n "$s" ]] && subs+=("$s"); done < <(sed '1s/^\xEF\xBB\xBF//' \
          "${AZURE_CONFIG_DIR:-$H/.azure}/azureProfile.json" 2>/dev/null | jq -r '.subscriptions[]? | select(.isDefault) | .name, .id' 2>/dev/null)
      fi
      (( ${#subs[@]} )) && prod_sub "mutating az" "${subs[@]}"
    fi
    if grep -Eq '(^|[;&|[:space:]])(kubectl|helm)([[:space:]]+[^[:space:]|;&]+)*[[:space:]]+(delete|apply|scale|patch|replace|drain|cordon|rollout|uninstall|upgrade|install|rollback|edit|annotate|label|taint)([[:space:]]|$)' <<<"$sc"; then
      ctx="$(grep -Eo -- '--(kube-)?context[[:space:]=]+[^[:space:]]+' <<<"$cmd" | sed -E 's/--(kube-)?context[[:space:]=]+//' | tr -d "\"'" | head -1)"
      [[ -n "$ctx" ]] || ctx="$(kubectl config current-context 2>/dev/null)"
      prod_listed context "$ctx" &&
        block "mutating kubectl/helm against a production context listed in production.conf ($ctx): run it yourself, outside Claude"
      grep -Eqi "$PROD" <<<"$ctx" &&
        block "mutating kubectl/helm against the production context ($ctx): run it yourself, outside Claude"
    fi
    # Windows PowerShell runs outside the sandbox: no encoded commands and no «download and run» (here the quoted
    # text does count, because the script goes inside -Command "…").
    if grep -Eqi '(^|[;&|[:space:]])(pwsh|powershell)(\.exe)?([[:space:]]|$)' <<<"$sc"; then
      grep -Eqi '[[:space:]]-(e|ec|enc|enco[a-z]*)[[:space:]]' <<<"$cmd" &&
        block "PowerShell with an encoded command (-EncodedCommand): write it in plain text or run it yourself"
      grep -Eqi '(iex|invoke-expression)' <<<"$cmd" && grep -Eqi '(iwr|irm|invoke-webrequest|invoke-restmethod|downloadstring|downloadfile|start-bitstransfer)' <<<"$cmd" &&
        block "PowerShell that downloads and runs: download the script, review it and run it yourself"
    fi
    # What git runs later, outside the sandbox (hooks, aliases, filters): not written from Claude.
    grep -Eq '(>|>>|(^|[;&|[:space:]])(tee|cp|mv|install|ln|chmod|rm|touch|truncate|dd)[[:space:]]|sed[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i)[^|;&]*\.git/(hooks(/|[[:space:]]|$)|config([[:space:]]|$))' <<<"$cmd" &&
      block "writing to .git/hooks or .git/config leaves code that runs outside the sandbox: do it yourself"
    # An agent identity or a custom profile stays what it is: no switching Claude or the CLIs to other credentials
    # (WS-AI-026, ADR-021). The built-in profiles (work, personal) are your own sessions and keep today's rules.
    who=""
    if [[ -n "${WS_AGENT:-}" ]]; then who="agent identity «$WS_AGENT»"
    elif [[ -n "${WS_PROFILE:-}" && "$WS_PROFILE" != work && "$WS_PROFILE" != personal ]]; then who="profile «$WS_PROFILE»"; fi
    if [[ -n "$who" ]]; then
      grep -Eq '(^|[;&|[:space:]])(export[[:space:]]+|unset[[:space:]]+([^;&|]*[[:space:]])?|-u[[:space:]]*)?(CLAUDE_CONFIG_DIR|AZURE_CONFIG_DIR|GH_CONFIG_DIR|KUBECONFIG|AZURE_TOKEN_CREDENTIALS|GH_TOKEN|GITHUB_TOKEN|GH_ENTERPRISE_TOKEN|AZURE_CLIENT_SECRET|ARM_CLIENT_SECRET|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN|GIT_SSH_COMMAND|GIT_SSH|SSH_AUTH_SOCK)([=[:space:]]|$)|--kubeconfig([=[:space:]]|$)|(^|[;&|[:space:]])env[[:space:]]+(-[a-zA-Z]*i|--ignore-environment)([[:space:]]|$)' <<<"$sc" &&
        block "this tab runs as the $who: it cannot switch Claude, az, gh or kubectl to other credentials"
      grep -Eq '(^|[;&|[:space:]])(az[[:space:]]+(login|logout|account[[:space:]]+clear)|gh[[:space:]]+auth[[:space:]]+(login|logout|switch|refresh|setup-git)|claude[[:space:]]+(auth[[:space:]]+(login|logout)|setup-token))([[:space:]]|$)' <<<"$sc" &&
        block "this tab runs as the $who: logging in or switching accounts is done by you, in a terminal (ws-profile login)"
    fi

    # Paths: the words the shell will use, split into simple commands. Heredoc bodies are data (dropped); quoted
    # text with spaces is a mention (dropped) unless it holds a $(…) or `…`; a quoted single word is a path.
    pc="$(printf '%s' "$cmd" | tr '\n' '\001' | awk '{
      n = split($0, L, "\001"); out = ""; delim = ""
      for (i = 1; i <= n; i++) {
        line = L[i]
        if (delim != "") { t = line; gsub(/^[ \t]+|[ \t]+$/, "", t); if (t == delim) delim = ""; continue }
        if (match(line, /(^|[^<])<<-?[ \t]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*/)) {
          d = substr(line, RSTART, RLENGTH); sub(/^[^<]*<<-?[ \t]*["'"'"']?/, "", d); delim = d }
        out = out (out == "" ? "" : "\001") line
      }
      s = out; r = ""
      while (match(s, /'"'"'[^'"'"']*'"'"'|"([^"\\]|\\.)*"/)) {
        q = substr(s, RSTART, RLENGTH); body = substr(q, 2, RLENGTH - 2); r = r substr(s, 1, RSTART - 1)
        if (substr(q, 1, 1) == "'"'"'") {
          if (body !~ /[ \t\001]/) { gsub(/~/, "\002", body); gsub(/\$/, "\003", body); r = r body } else r = r " "
        } else if (body ~ /\$\(|`/) r = r " " body " "
        else if (body !~ /[ \t\001]/) { gsub(/~/, "\002", body); r = r body }
        else r = r " "
        s = substr(s, RSTART + RLENGTH)
      }
      printf "%s", r s }' | sed -E 's/[0-9]*>&[0-9-]+/ /g; s/&>>?/ > /g; s/>\|/>/g; s/(>>?|<)/ \1 /g; s/&&|\|\||[;&|()`]|\$\(|\x01/\n/g')"
    base="${cwd:-$PWD}"
    while IFS= read -r seg; do
      read -ra tok <<<"$seg"
      (( ${#tok[@]} )) || continue
      words=() targets=() redir="" j=0
      for t in "${tok[@]}"; do   # redirections first: «> x» is a target whatever the command
        if [[ -n "$redir" ]]; then [[ "$redir" == ">" ]] && targets+=("$t"); words+=("$t"); redir=""; continue; fi
        case "$t" in '>'|'>>') redir=">" ;; '<') redir="<" ;; *) words+=("$t") ;; esac
      done
      tok=("${words[@]}"); words=()
      # Every word as a path (cred check): VAR=value and --opt=value give their value, @file its file.
      for t in "${tok[@]}"; do
        case "$t" in
          --*=*|[A-Za-z_]*=*) words+=("${t#*=}") ;;
          -?/*|'-?$HOME'*) words+=("${t:2}") ;;
          -*) ;;
          @*) words+=("${t:1}") ;;
          *) words+=("$t") ;;
        esac
      done
      # The command itself, after VAR=value assignments and wrappers (sudo, env, timeout, nice, xargs…).
      while (( j < ${#tok[@]} )); do
        t="${tok[j]}"
        if [[ "$t" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then j=$((j + 1)); continue; fi
        case "${t##*/}" in
          sudo|doas|env|command|builtin|exec|nohup|nice|ionice|time|timeout|stdbuf|xargs|unbuffer)
            j=$((j + 1))
            while (( j < ${#tok[@]} )) && [[ "${tok[j]}" == -* || "${tok[j]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= || "${tok[j]}" =~ ^[0-9.]+[smhd]?$ ]]; do j=$((j + 1)); done ;;
          *) break ;;
        esac
      done
      c="${tok[j]:-}"; c="${c##*/}"
      [[ "$c" == ws-learn ]] && block "ws-learn saves what YOU approve: run it yourself in a terminal (Menu → Usage)"
      # Profiles and accounts decide which organisation and tenant a tab talks to (ADR-021): read-only commands pass.
      [[ "$c" == ws-profile && "${tok[j+1]:-}" =~ ^(new|login|logout|tab|use|project|remove|setup|menu)$ ]] &&
        block "ws-profile ${tok[j+1]} changes which account a tab uses: run it yourself (Menu → Claude → Profile)"
      [[ "$c" == claude-account && "${tok[j+1]:-}" =~ ^(setup|login|logout|tab|use|project)$ ]] &&
        block "claude-account ${tok[j+1]} changes which account a tab uses: run it yourself (Menu → Claude)"
      case "$c" in   # what only the owner approves or lifts (WS-AI-012, WS-AI-019, WS-AI-025)
        ws-memory) [[ "${tok[j+1]:-}" =~ ^(save-facts|review|profile)$ ]] &&
          block "ws-memory ${tok[j+1]} approves memory writes: run it yourself in a terminal" ;;
        ws-stop-all) [[ " ${tok[*]:j+1} " == *" --clear "* ]] &&
          block "clearing the emergency stop is yours: run «ws-stop-all --clear» in a terminal" ;;
        ws-telemetry) [[ " ${tok[*]:j+1} " == *" budgets "* && " ${tok[*]:j+1} " == *" --override"* ]] &&
          block "overriding a hard budget is yours: run «ws-telemetry budgets --override» in a terminal" ;;
        ws-mcp-tools) [[ "${tok[j+1]:-}" =~ ^(approve|forget)$ ]] &&
          block "ws-mcp-tools ${tok[j+1]} decides which MCP tool definitions are trusted: run it yourself in a terminal (Menu → Settings)" ;;
        ws-settings) [[ -n "${tok[j+1]:-}" && ! "${tok[j+1]}" =~ ^(show|get|menu-sync|help|-h|--help)$ ]] &&
          block "ws-settings ${tok[j+1]} changes the workstation's settings: that is yours (Menu → Settings)" ;;
        tmux-level) [[ "${tok[j+1]:-}" =~ ^(bare|puro)$ || ( "${tok[j+1]:-}" == default && -n "${tok[j+2]:-}" ) ]] &&
          block "tmux-level ${tok[j+1]} lowers or sets the protection of your tabs: that is yours (Menu → Settings or Claude → Protection)" ;;
        tmux-solo) [[ -n "${tok[j+1]:-}" && ! "${tok[j+1]}" =~ ^(status|help|-h|--help)$ ]] &&
          block "tmux-solo starts an agent that approves its own commands: that is yours (Menu → Claude → Protection)" ;;
        ws-telegram) [[ -n "${tok[j+1]:-}" && ! "${tok[j+1]}" =~ ^(status|menu-sync|help|-h|--help)$ ]] &&
          block "ws-telegram ${tok[j+1]} changes the phone channel that approves this agent: that is yours (Menu → Settings → Telegram)" ;;
        ws-lang) [[ "${tok[j+1]:-}" =~ ^(en|es|--toggle)$ ]] &&
          block "ws-lang ${tok[j+1]} changes the language of the kit's patterns: that is yours (Menu → Settings)" ;;
        ws-kit-update) block "ws-kit-update installs a new version of the kit: run it yourself (Menu → Settings)" ;;
        ws-backup-cloud) [[ "${tok[j+1]:-}" == setup ]] &&
          block "ws-backup-cloud setup creates and shows the backup key: run it yourself in a terminal (Menu → Settings)" ;;
        mempalace|mempalace.exe)
          [[ "${tok[j+1]:-}" =~ ^(mine|add|kg|diary|import|sync|hook|init|repair|compress|split|migrate|delete|remove|forget|write|update|patch)$ ]] &&
            block "writing to MemPalace from the shell skips the memory gate: use the MCP tools (they ask you) or do it yourself" ;;
      esac
      # Options that name the destination (-t, -C, -d, -o…) for the commands where they do; -r/-R/-a: recursive.
      nonopt=() atargets=() tdir="" inplace=0 extract=0 rec=0 mkd=0
      for (( k = j + 1; k < ${#tok[@]}; k++ )); do
        t="${tok[k]}"
        case "$t" in
          -t|--target-directory|-C|--directory|-d|-o|--output|-O|--output-document|-P|--directory-prefix)
            if [[ "$c" == install && "$t" == -d ]]; then mkd=1
            elif [[ "$c" =~ ^(ln|cp|mv|install|rsync|tar|unzip|curl|wget|sort)$ ]]; then tdir="${tok[k+1]:-}"; k=$((k + 1)); fi ;;
          --target-directory=*|--directory=*|--output=*|--output-document=*|--directory-prefix=*) tdir="${t#*=}" ;;
          --in-place*) inplace=1 ;;
          --extract|--get) extract=1 ;;
          --recursive|--archive) rec=1 ;;
          of=*) [[ "$c" == dd ]] && targets+=("${t#of=}") ;;
          --*) ;;
          -*) [[ "$t" =~ ^-[a-zA-Z]*i ]] && inplace=1; [[ "$t" =~ x ]] && extract=1; [[ "$t" =~ [rRa] ]] && rec=1 ;;
          *) nonopt+=("$t"); [[ $k == $((j + 1)) && "$c" == tar && "$t" =~ ^[a-zA-Z]*x ]] && extract=1 ;;
        esac
      done
      n=${#nonopt[@]}; dest="$tdir"; [[ -z "$dest" ]] && (( n >= 2 )) && dest="${nonopt[-1]}"
      case "$c" in
        cd) if (( n )); then expand "${nonopt[0]}" "$base"; base="$REPLY"; else base="$H"; fi ;;
        rm|rmdir|unlink|shred) atargets+=("${nonopt[@]}") ;;
        mv) if [[ -n "$tdir" ]]; then atargets+=("${nonopt[@]}"); targets+=("$tdir")
            elif (( n >= 2 )); then atargets+=("${nonopt[@]:0:n-1}"); targets+=("$dest")
            else atargets+=("${nonopt[@]}"); fi ;;
        chmod|chown|chgrp|chattr|setfacl) if (( rec )); then atargets+=("${nonopt[@]}"); else targets+=("${nonopt[@]}"); fi ;;
        tee|truncate|touch|mkdir|mkfifo) targets+=("${nonopt[@]}") ;;
        cp|scp|ln) [[ -n "$dest" ]] && { if (( rec )); then atargets+=("$dest"); else targets+=("$dest"); fi; } ;;
        rsync) [[ -n "$dest" ]] && atargets+=("$dest") ;;
        install) if (( mkd )); then targets+=("${nonopt[@]}"); elif [[ -n "$dest" ]]; then targets+=("$dest"); elif (( n == 1 )); then targets+=("${nonopt[0]}"); fi ;;
        sed|perl) (( inplace )) && targets+=("${nonopt[@]}") ;;
        tar) (( extract )) && atargets+=("${tdir:-.}") ;;
        unzip) atargets+=("${tdir:-.}") ;;
        curl|wget|sort) [[ -n "$tdir" ]] && targets+=("$tdir") ;;
      esac
      queue w "$base" "${words[@]}"
      queue t "$base" "${targets[@]}"
      queue a "$base" "${atargets[@]}"
      # Globs: what they match now (cred check), so «cat ~/.ss?/id*» counts as ~/.ssh.
      for t in "${words[@]}"; do
        [[ "$t" == *[*?[]* ]] || continue
        expand "$t" "$base"; g=()
        mapfile -t g < <(compgen -G "$REPLY" 2>/dev/null | head -200)
        (( ${#g[@]} )) && { kinds+=("${g[@]/*/w}"); paths+=("${g[@]}"); }
      done
    done <<<"$pc"
    verdict
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    grep -Eq '(^|/)\.git/(hooks/|config$|info/attributes$)' <<<"$path" &&
      block "writing to .git/hooks or .git/config leaves code that runs outside the sandbox: do it yourself"
    content="$(jq -r '[.tool_input.content, .tool_input.new_string, .tool_input.new_source, (.tool_input.edits[]?.new_string)] | map(select(. != null)) | join("\n")' <<<"$input")"
    grep -Eq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AccountKey=[A-Za-z0-9+/=]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|SharedAccess[S]ignature=|[?&]sig=[A-Za-z0-9%]{30,}' <<<"$content" &&
      block "the content seems to include a secret: use Key Vault or a variable reference"
    [[ -n "$path" ]] && { queue t "${cwd:-$PWD}" "$path"; verdict; }
    ;;
  Read|Grep|Glob)
    # The Read deny rules match the path as written; this also catches a link or «..» that leads to a store.
    [[ -n "$path" ]] && { queue w "${cwd:-$PWD}" "$path"; verdict; }
    ;;
  mcp__azure__*)
    # Azure MCP tools: a mutating operation that names a production subscription (WS-SEC-006).
    ops="$(jq -r '[.tool_name, (.tool_input | .. | objects | (.command?, .intent?, .operation?) | strings)] | join(" ")' <<<"$input" 2>/dev/null)"
    if grep -Eqi '(^|[^[:alpha:]])(create|update|delete|set|start|stop|restart|deallocate|scale|purge|deploy|invoke|assign|import|swap|upload|remove|put|patch|write)([^[:alpha:]]|$)' <<<"$ops"; then
      subs=()
      while IFS= read -r s; do [[ -n "$s" ]] && subs+=("$s"); done < <(jq -r '
        [(.tool_input | .. | objects | to_entries[] | select(.key | test("^subscription(_?id)?$"; "i")) | .value | strings),
         (.tool_input | .. | strings | scan("/subscriptions/([0-9a-fA-F-]{36})") | .[0])] | unique[]' <<<"$input" 2>/dev/null)
      (( ${#subs[@]} )) && prod_sub "a mutating Azure MCP tool" "${subs[@]}"
    fi
    ;;
esac
exit 0
