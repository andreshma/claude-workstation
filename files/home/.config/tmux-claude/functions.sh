# shellcheck shell=bash
# Funciones para abrir repos con Claude Code en tmux. Se cargan desde ~/.bashrc.

# _claude_cmd <dir> — "claude --continue" si ya hay conversaciones de ese directorio, si no "claude".
_claude_cmd() {
  local k="${1//[^A-Za-z0-9]/-}"
  if compgen -G "$HOME/.claude/projects/$k/*.jsonl" >/dev/null; then echo "claude --continue"; else echo "claude"; fi
}

# twt <repo> <rama> — crea (si falta) el worktree en <repo>.wt/<rama> y lo abre con tw.
twt() {
  local r; r="$(git -C "${1:?repo}" rev-parse --show-toplevel)" || return 1
  local b="${2:?rama}" w="$r.wt/${2//\//-}"
  [ -d "$w" ] || git -C "$r" worktree add -b "$b" "$w" 2>/dev/null || git -C "$r" worktree add "$w" "$b" || return 1
  tw "$w" "$(basename "$r")@${2//\//-}"
}

# tp <dir> — agrega <dir> como pane de la ventana actual con Claude y reacomoda en mosaico.
tp() {
  local d; d="$(realpath -e "${1:-.}")" || return 1
  tmux split-window -c "$d" \; select-layout tiled \; send-keys "$(_claude_cmd "$d")" Enter
}

# tw <dir> [nombre] — pestaña del proyecto solo con Claude, a pantalla completa (sin shell lateral).
tw() {
  local d; d="$(realpath -e "${1:-.}")" || return 1
  tmux new-window -n "${2:-$(basename "$d")}" -c "$d" \; send-keys "$(_claude_cmd "$d")" Enter
}

# two <dir> [nombre] — como tw, pero arranca Claude con Opus (Menú → Abrir carpeta con Opus).
two() {
  local d; d="$(realpath -e "${1:-.}")" || return 1
  tmux new-window -n "${2:-$(basename "$d")}" -c "$d" \; send-keys "$(_claude_cmd "$d") --model opus" Enter
}

# Puente WSL ↔ Windows y prompt con contexto
# shellcheck source=/dev/null
[ -f ~/.config/tmux-claude/wsl-bridge.sh ] && . ~/.config/tmux-claude/wsl-bridge.sh
