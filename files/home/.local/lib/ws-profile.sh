# shellcheck shell=bash disable=SC2034  # the WSP_* globals are read by the scripts that source this file
#
# ws-profile.sh — per-tab profiles (ADR-021): the ONE place that knows what a profile is and which environment a tab
# runs with. Sourced by ~/.config/tmux-claude/accounts.sh (every new shell), ws-profile, claude-account, tmux-state.sh
# and the memory hooks; tmux-level and claude-resume reach it through ws-profile. Pure bash: nothing here starts a
# process, so a new shell stays fast; the functions return their result in REPLY (or WSP_* arrays) instead of printing
# it, and every one returns 0 (safe under set -e) except the predicates wsp_valid, wsp_builtin, wsp_exists and a
# failing wsp_exports.
#
# A profile = a Claude config dir + the az, gh and kubectl credential dirs + options, in
# ~/.config/ws-profiles/<name>/profile.conf (key=value lines, read as data, never sourced):
#   claude_dir=~/.claude-profiles/<name>   ~/.claude, ~/.claude-personal or ~/.claude-profiles/<one folder>
#   tenant=<tenant id>   subscription=<subscription id or name>     used by the login and by ws-audit
#   share_conversations=no|<profile>      no: its own conversations, history, todos… (isolated, the default)
#   memory=off|on|wing:<wing>             MemPalace for this tab: off (default), on, or only that wing
#   label=<text>   colour=<tmux colour>    what the status bar shows for the tab
# Built in, with no file: work (~/.claude and your default credentials) and personal (~/.claude-personal, the same
# conversations as work): exactly the two accounts of claude-account. The credentials of profile <name> live in
# ~/.config/ws-agent/<name>/{azure,gh,kube/config}, the same folder as the agent identity of that name (ADR-020),
# which the sandbox denies as a whole; the non-secret profile.conf stays readable.
# Names: ^[a-z0-9][a-z0-9_-]{0,31}$. Precedence for a NEW shell (tab or pane): the project pin
# (~/.config/ws-profiles/projects.conf: «<name> <folder>», the repo and its <repo>.wt/ worktrees) > the tab's profile
# (@cprofile, for a split) > the default for new tabs (~/.config/ws-profiles/default) > work. A restart of a tab keeps
# the tab's profile.

WSP_CONF="$HOME/.config/ws-profiles"
WSP_CREDS="$HOME/.config/ws-agent"
WSP_CLAUDE_ROOT="$HOME/.claude-profiles"
WSP_LEGACY="$HOME/.config/claude-accounts"
# What a profile shares with the kit setup (linked to ~/.claude) and what holds conversations (linked only with
# share_conversations). Everything else in a Claude dir is the profile's own: login, .claude.json, policies, caches.
WSP_SETUP=(settings.json CLAUDE.md standards.md rules hooks agents commands skills workflows output-styles
  keybindings.json themes plugins statusline.sh statusline-present.sh)
WSP_CONVO=(projects history.jsonl todos tasks plans file-history paste-cache agent-memory)
# The variables a profile sets; WS_PROFILE_PANE marks the pane they were set for (a nested shell keeps them).
WSP_VARS=(CLAUDE_CONFIG_DIR AZURE_CONFIG_DIR GH_CONFIG_DIR KUBECONFIG AZURE_TOKEN_CREDENTIALS WS_PROFILE WS_MEMORY)

wsp_valid()   { [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]; }
wsp_builtin() { [[ "$1" == work || "$1" == personal ]]; }
wsp_exists()  { wsp_builtin "$1" || { wsp_valid "$1" && [[ -f "$WSP_CONF/$1/profile.conf" ]]; }; }

# wsp_get NAME KEY — REPLY = the value of KEY for profile NAME, with its default. Unknown custom names get the
# isolated defaults (fail closed: a pin to a deleted profile never falls back to another account).
wsp_get() {
  local n="$1" k="$2" f l key val
  REPLY=""
  if wsp_builtin "$n"; then
    case "$k" in
      claude_dir) [[ "$n" == work ]] && REPLY="$HOME/.claude" || REPLY="$HOME/.claude-personal" ;;
      share_conversations) [[ "$n" == work ]] && REPLY=no || REPLY=work ;;
      memory) REPLY=on ;;
    esac
    return 0
  fi
  f="$WSP_CONF/$n/profile.conf"
  if [[ -r "$f" ]]; then
    while IFS= read -r l || [[ -n "$l" ]]; do
      l="${l%$'\r'}"; [[ "$l" == *=* && "$l" != \#* ]] || continue
      key="${l%%=*}"; val="${l#*=}"
      key="${key//[[:space:]]/}"; val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
      [[ "$key" == "$k" ]] && { REPLY="$val"; break; }
    done < "$f"
  fi
  case "$k" in
    claude_dir)
      [[ -n "$REPLY" ]] || REPLY="$WSP_CLAUDE_ROOT/$n"
      REPLY="${REPLY/#\~/$HOME}"; REPLY="${REPLY%/}"
      # Only the two accounts' dirs or one folder under ~/.claude-profiles: anything else is not a profile dir.
      if [[ "$REPLY" != "$HOME/.claude" && "$REPLY" != "$HOME/.claude-personal" ]] \
         && ! [[ "$REPLY" == "$WSP_CLAUDE_ROOT"/* && "${REPLY#"$WSP_CLAUDE_ROOT"/}" =~ ^[A-Za-z0-9_-]+$ ]]; then
        REPLY="$WSP_CLAUDE_ROOT/$n"
      fi ;;
    share_conversations) wsp_valid "$REPLY" || REPLY=no ;;
    memory) [[ "$REPLY" == on || "$REPLY" =~ ^wing:[a-z0-9][a-z0-9_]{0,63}$ ]] || REPLY=off ;;
    label) [[ -n "$REPLY" ]] || REPLY="$n"; REPLY="${REPLY//[^[:alnum:] ._@+-]/}"; REPLY="${REPLY:0:16}" ;;
    colour) [[ "$REPLY" =~ ^(colour[0-9]{1,3}|#[0-9a-fA-F]{6}|[a-z]+)$ ]] || REPLY=colour214 ;;
    tenant|subscription) REPLY="${REPLY//[^A-Za-z0-9 ._()-]/}" ;;
  esac
  return 0
}

# wsp_store NAME — REPLY = the Claude dir that holds NAME's conversations: its own dir, or the end of its
# share_conversations chain (at most 4 hops; a loop ends in the profile's own dir).
wsp_store() {
  local n="$1" i dir
  for (( i = 0; i < 4; i++ )); do
    wsp_get "$n" claude_dir; dir="$REPLY"
    [[ "$dir" == "$HOME/.claude-personal" ]] && dir="$HOME/.claude"   # personal links work's conversations
    wsp_get "$n" share_conversations
    if [[ "$REPLY" == no || "$REPLY" == "$n" || "$dir" == "$HOME/.claude" ]]; then REPLY="$dir"; return 0; fi
    n="$REPLY"
  done
  wsp_get "$1" claude_dir
}

# wsp_pin DIR — REPLY = the profile pinned to the project that contains DIR (the longest matching folder), or "".
wsp_pin() {
  local d="${1%/}" f="$WSP_CONF/projects.conf" n r best=0
  REPLY=""
  [[ -r "$f" ]] || f="$WSP_LEGACY/projects.conf"
  [[ -r "$f" ]] || return 0
  while read -r n r || [[ -n "$n" ]]; do
    [[ -n "$n" && "$n" != \#* && -n "$r" ]] && wsp_valid "$n" || continue
    r="${r%/}"
    if [[ "$d" == "$r" || "$d" == "$r"/* || "$d" == "$r".wt/* ]] && (( ${#r} > best )); then REPLY="$n"; best=${#r}; fi
  done < "$f"
  return 0
}

# wsp_default — REPLY = the profile for new tabs (ws-profile use), work when none is set.
wsp_default() {
  REPLY=""
  if [[ -r "$WSP_CONF/default" ]]; then read -r REPLY < "$WSP_CONF/default" || true
  elif [[ -r "$WSP_LEGACY/active" ]]; then read -r REPLY < "$WSP_LEGACY/active" || true; fi
  wsp_valid "${REPLY:-}" || REPLY=work
}

# wsp_resolve DIR [TAB] — REPLY = the profile a new shell in DIR starts with: pin > TAB > default.
wsp_resolve() {
  wsp_pin "${1:-$PWD}"; [[ -n "$REPLY" ]] && return 0
  if [[ -n "${2:-}" ]] && wsp_valid "$2"; then REPLY="$2"; return 0; fi
  wsp_default
}

# wsp_of_dir DIR — REPLY = the profile whose Claude dir is DIR (for a Claude started by hand with CLAUDE_CONFIG_DIR).
wsp_of_dir() {
  local d="${1%/}"
  case "$d" in
    ""|"$HOME/.claude") REPLY=work ;;
    "$HOME/.claude-personal") REPLY=personal ;;
    "$WSP_CLAUDE_ROOT"/*) REPLY="${d#"$WSP_CLAUDE_ROOT"/}"; wsp_valid "$REPLY" || REPLY="" ;;
    *) REPLY="" ;;
  esac
}

# wsp_exports NAME — REPLY = the shell statements that give the CURRENT shell profile NAME's environment. Built-in
# profiles keep your own az, gh and kubectl settings and only drop what another profile left (paths under
# ~/.config/ws-agent); a custom profile sets all of them. Evaluated by accounts.sh and, typed into a pane, through
# `eval "$(ws-profile --export NAME)"` by the launchers that restart a tab.
wsp_exports() {
  local n="$1" s="" v dir mem c="$WSP_CREDS/$1"
  wsp_valid "$n" || { REPLY="false"; return 1; }
  if wsp_builtin "$n"; then
    if [[ "$n" == work ]]; then s="unset CLAUDE_CONFIG_DIR; "
    else printf -v s 'export CLAUDE_CONFIG_DIR=%q; ' "$HOME/.claude-personal"; fi
    for v in AZURE_CONFIG_DIR GH_CONFIG_DIR KUBECONFIG; do
      [[ "${!v:-}" == "$WSP_CREDS/"* ]] && s+="unset $v; "
    done
    [[ -n "${WS_PROFILE:-}" ]] && ! wsp_builtin "${WS_PROFILE:-}" && s+="unset AZURE_TOKEN_CREDENTIALS; "
    printf -v REPLY '%sunset WS_MEMORY; export WS_PROFILE=%s WS_PROFILE_PANE=%q' "$s" "$n" "${TMUX_PANE:-}"
    return 0
  fi
  wsp_get "$n" claude_dir; dir="$REPLY"
  wsp_get "$n" memory; mem="$REPLY"
  # ~/.claude must be reached with CLAUDE_CONFIG_DIR unset: set, Claude reads ~/.claude/.claude.json, not ~/.claude.json.
  if [[ "$dir" == "$HOME/.claude" ]]; then s="unset CLAUDE_CONFIG_DIR; export"
  else printf -v s 'export CLAUDE_CONFIG_DIR=%q' "$dir"; fi
  printf -v REPLY '%s AZURE_CONFIG_DIR=%q GH_CONFIG_DIR=%q KUBECONFIG=%q AZURE_TOKEN_CREDENTIALS=AzureCliCredential WS_PROFILE=%s WS_MEMORY=%q WS_PROFILE_PANE=%q' \
    "$s" "$c/azure" "$c/gh" "$c/kube/config" "$n" "$mem" "${TMUX_PANE:-}"
}

# wsp_memory — REPLY = the MemPalace mode of THIS process: off | on | wing:<w>. WS_MEMORY first (set with the
# profile); without it, the profile of CLAUDE_CONFIG_DIR, so a Claude started by hand in an isolated profile's dir is
# still kept out (fail closed: a dir under ~/.claude-profiles with no readable profile is off).
wsp_memory() {
  local m="${WS_MEMORY:-}"
  if [[ -z "$m" ]]; then
    if [[ -n "${WS_PROFILE:-}" ]] && ! wsp_builtin "$WS_PROFILE"; then wsp_get "$WS_PROFILE" memory; m="$REPLY"
    else wsp_of_dir "${CLAUDE_CONFIG_DIR:-}"
      if [[ -z "$REPLY" ]]; then m=on; elif wsp_builtin "$REPLY"; then m=on; else wsp_get "$REPLY" memory; m="$REPLY"; fi
    fi
  fi
  [[ "$m" == on || "$m" =~ ^wing:[a-z0-9][a-z0-9_]{0,63}$ ]] || m=off
  REPLY="$m"
}

# wsp_names — WSP_NAMES = every profile: the built-in ones, then each ~/.config/ws-profiles/<name>/profile.conf.
wsp_names() {
  local f n
  WSP_NAMES=(work personal)
  for f in "$WSP_CONF"/*/profile.conf; do
    [[ -f "$f" ]] || continue
    n="${f%/profile.conf}"; n="${n##*/}"
    if wsp_valid "$n" && ! wsp_builtin "$n"; then WSP_NAMES+=("$n"); fi
  done
}
