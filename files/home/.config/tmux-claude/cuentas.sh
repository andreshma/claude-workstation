# shellcheck shell=bash
#
# cuentas.sh — applies in every new shell the Claude account chosen for new tabs
# (claude-cuenta usar trabajo|personal). A tab switched with "claude-cuenta pestaña"
# keeps its own account in its shell. Shortcuts: claude-trabajo / claude-personal.
#
# Account PER PROJECT: if the folder where the shell opens (or its repo, or a repo.wt/… worktree) has a fixed account
# in ~/.config/claude-cuentas/proyectos.conf, that one wins over the default account. So one project always opens with
# one account and another with the other, without remembering to switch. Set it with:
# claude-cuenta proyecto trabajo|personal [folder].
_cuenta_proyecto() {   # prints the fixed account of $PWD; exits with 1 if there is none
  local f="$HOME/.config/claude-cuentas/proyectos.conf" c r
  [[ -r "$f" ]] || return 1
  while read -r c r; do
    [[ -n "$c" && "$c" != \#* && -n "$r" ]] || continue
    r="${r%/}"
    if [[ "$PWD" == "$r" || "$PWD" == "$r"/* || "$PWD" == "$r".wt/* ]]; then printf '%s\n' "$c"; return 0; fi
  done < "$f"
  return 1
}
if _ws_c="$(_cuenta_proyecto)"; then
  if [[ "$_ws_c" == personal ]]; then export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"; else unset CLAUDE_CONFIG_DIR; fi
elif [[ -z "${CLAUDE_CONFIG_DIR+x}" && "$(cat "$HOME/.config/claude-cuentas/activa" 2>/dev/null)" == personal ]]; then
  export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"
fi
unset _ws_c
alias claude-trabajo='env -u CLAUDE_CONFIG_DIR claude'
alias claude-personal='CLAUDE_CONFIG_DIR="$HOME/.claude-personal" claude'
