# shellcheck shell=bash
#
# cuentas.sh — aplica en cada shell nueva la cuenta de Claude elegida para pestañas nuevas
# (claude-cuenta usar trabajo|personal). Una pestaña cambiada con "claude-cuenta pestaña"
# conserva su propia cuenta en su shell. Atajos: claude-trabajo / claude-personal.
#
# Cuenta POR PROYECTO: si la carpeta donde abre la shell (o su repo, o un worktree repo.wt/…) tiene cuenta fija en
# ~/.config/claude-cuentas/proyectos.conf, esa manda sobre la cuenta por defecto. Así un proyecto abre siempre con una
# cuenta y otro con otra, sin acordarte de cambiarla. Se fija con: claude-cuenta proyecto trabajo|personal [carpeta].
_cuenta_proyecto() {   # imprime la cuenta fija de $PWD; sale con 1 si no tiene
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
