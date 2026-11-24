# shellcheck shell=bash
# shellcheck source=/dev/null
#
# shell.sh — terminal cómoda: completado con Tab, fzf, sugerencias en gris (ble.sh) y copiloto
# de IA. Lo carga functions.sh solo en shells interactivas. Para apagar ble.sh en una sesión:
# `ble-detach`; para siempre: `touch ~/.config/tmux-claude/sin-ble`.
[[ $- == *i* ]] || return 0

# 1) ble.sh primero (sin adjuntarse todavía): reemplaza el editor de línea y trae
#    autosugerencias del historial y colores de sintaxis.
_ble="$HOME/.local/share/blesh/ble.sh"
if [[ -f "$_ble" && ! -f "$HOME/.config/tmux-claude/sin-ble" && -z "${BLE_VERSION-}" ]]; then
  source "$_ble" --attach=none
fi
unset _ble

# 2) Completado con Tab: bash-completion + completaciones generadas por ws-completions
#    (~/.local/share/bash-completion/completions, carga perezosa por comando).
if ! declare -F _init_completion >/dev/null && [[ -f /usr/share/bash-completion/bash_completion ]]; then
  source /usr/share/bash-completion/bash_completion
fi
# Completado para los comandos propios de la estación.
complete -W "esta normal nueva worktree" tmux-solo
complete -W "install groups" ws-tools
complete -W "--ahora --si-toca" ws-backup-lite
complete -W "--probar --restaurar" ws-restore-lite
complete -W "--rapido" ws-verify
complete -d tw twt two

# 3) fzf: Ctrl+R historial, Ctrl+T archivo, Alt+C carpeta, **<Tab> rutas.
if command -v fzf >/dev/null; then
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
  if [[ ${BLE_VERSION-} ]]; then
    ble-import -d integration/fzf-completion
    ble-import -d integration/fzf-key-bindings
  elif fzf --bash >/dev/null 2>&1; then
    eval "$(fzf --bash)"
  else
    for _f in /usr/share/doc/fzf/examples/key-bindings.bash /usr/share/bash-completion/completions/fzf; do
      [[ -f "$_f" ]] && source "$_f"
    done; unset _f
  fi
fi

# 4) Copiloto de IA (Alt+a sugerir · Alt+e explicar · Alt+x corregir).
[[ -f "$HOME/.config/tmux-claude/ai-shell.sh" ]] && source "$HOME/.config/tmux-claude/ai-shell.sh"

# 5) ble.sh se adjunta al final, cuando todo lo anterior ya está definido.
# --- Historial sin secretos (ws-patch30) ---
# Un espacio al inicio del comando = no se guarda. Líneas con credenciales tampoco.
HISTCONTROL=ignoreboth:erasedups
HISTIGNORE='*secret=*:*SECRET=*:*password=*:*PASSWORD=*:*passwd=*:*token=*:*TOKEN=*:*AccountKey=*:*SharedAccessSignature*:*ghp_*:*github_pat_*:*sk-ant-*:*AKIA*:*Bearer *:*--password*:*--client-secret*'

[[ ${BLE_VERSION-} ]] && ble-attach
