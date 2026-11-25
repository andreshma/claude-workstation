# shellcheck shell=bash
#
# accounts.sh — applies in every new shell the Claude account chosen for new tabs
# (claude-account use work|personal). A tab switched with "claude-account tab"
# keeps its own account in its shell. Shortcuts: claude-work / claude-personal.
#
# Account PER PROJECT: if the folder where the shell opens (or its repo, or a repo.wt/… worktree) has a fixed account
# in ~/.config/claude-accounts/projects.conf, that one wins over the default account. So one project always opens with
# one account and another with the other, without remembering to switch. Set it with:
# claude-account project work|personal [folder].
_account_project() {   # prints the fixed account of $PWD; exits with 1 if there is none
  local f="$HOME/.config/claude-accounts/projects.conf" c r
  [[ -r "$f" ]] || return 1
  while read -r c r; do
    [[ -n "$c" && "$c" != \#* && -n "$r" ]] || continue
    r="${r%/}"
    if [[ "$PWD" == "$r" || "$PWD" == "$r"/* || "$PWD" == "$r".wt/* ]]; then printf '%s\n' "$c"; return 0; fi
  done < "$f"
  return 1
}
if _ws_c="$(_account_project)"; then
  if [[ "$_ws_c" == personal ]]; then export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"; else unset CLAUDE_CONFIG_DIR; fi
elif [[ -z "${CLAUDE_CONFIG_DIR+x}" && "$(cat "$HOME/.config/claude-accounts/active" 2>/dev/null)" == personal ]]; then
  export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"
fi
unset _ws_c
alias claude-work='env -u CLAUDE_CONFIG_DIR claude'
alias claude-trabajo=claude-work   # deprecated name, kept so old habits keep working
alias claude-personal='CLAUDE_CONFIG_DIR="$HOME/.claude-personal" claude'
