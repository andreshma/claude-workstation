# shellcheck shell=bash
#
# accounts.sh — gives every new shell the PROFILE of its tab (ADR-021, ~/.local/lib/ws-profile.sh): its Claude
# account (CLAUDE_CONFIG_DIR) and, for a custom profile, its az, gh and kubectl credentials (AZURE_CONFIG_DIR,
# GH_CONFIG_DIR, KUBECONFIG), WS_PROFILE and WS_MEMORY. So a Claude, an az, a gh or a kubectl typed by hand in a tab
# runs with the same identity as the tab's Claude.
# Which profile: the project pin of the folder the shell opens in (its repo or a repo.wt/… worktree:
# ws-profile project NAME [folder]) > the tab's profile (a split of a tab switched with ws-profile tab) > a nested
# shell of a profiled pane keeps it > the default for new tabs (ws-profile use NAME) > work.
# Shortcuts: claude-work / claude-personal / claude-as NAME start Claude once with that profile (not the tab's).
if [ -r "$HOME/.local/lib/ws-profile.sh" ]; then
  # shellcheck source=../../.local/lib/ws-profile.sh
  . "$HOME/.local/lib/ws-profile.sh"
  _ws_tab=""
  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] && _ws_tab="$(tmux show -wqv -t "$TMUX_PANE" @cprofile 2>/dev/null)"
  # A nested shell (same pane, or no tmux) keeps what its parent set; a new pane does not inherit the server's copy.
  if [[ -z "$_ws_tab" && -n "${WS_PROFILE:-}" ]] && { [[ -z "${TMUX_PANE:-}" ]] || [[ "${WS_PROFILE_PANE:-}" == "$TMUX_PANE" ]]; }; then
    _ws_tab="$WS_PROFILE"
  elif [[ -z "$_ws_tab" && -z "${TMUX_PANE:-}" && -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    wsp_of_dir "$CLAUDE_CONFIG_DIR"; _ws_tab="${REPLY:--}"   # CLAUDE_CONFIG_DIR=… bash, as before the profiles
  fi
  wsp_pin "$PWD"
  # A CLAUDE_CONFIG_DIR of your own (not a profile's) is left alone unless the project pins a profile.
  if [[ -n "$REPLY" || "$_ws_tab" != - ]]; then
    [[ "$_ws_tab" == - ]] && _ws_tab=""
    wsp_resolve "$PWD" "$_ws_tab"
    if wsp_exports "$REPLY"; then eval "$REPLY"; fi
  fi
  if [[ $- == *i* ]] && ! wsp_exists "${WS_PROFILE:-work}"; then
    printf 'ws-profile: this tab runs as «%s», which is not set up (ws-profile new %s): Claude will ask you to log in\n' \
      "${WS_PROFILE:-}" "${WS_PROFILE:-}" >&2
  fi
  unset _ws_tab
fi
claude-as()       { local n="${1:?profile}"; shift; ( eval "$(ws-profile --export "$n")" && exec claude "$@" ); }
claude-work()     { claude-as work "$@"; }
claude-personal() { claude-as personal "$@"; }
claude-trabajo()  { claude-as work "$@"; }   # deprecated name, kept so old habits keep working
