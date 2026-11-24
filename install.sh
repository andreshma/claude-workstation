#!/usr/bin/env bash
#
# install.sh — aplica la configuración del repo (files/) a esta máquina SIN planchar:
# cada archivo que cambia se respalda antes como <archivo>.bak.<fecha>; lo que ya es igual no se toca.
#
# Uso: bash install.sh [--dry-run] [--no-plugins] [--no-mcp] [--no-git-hooks] [--win-user USUARIO] [--repos RUTA]
#   --dry-run          muestra qué cambiaría (nuevo / cambia / igual) sin escribir nada
#   --no-plugins       no instala TPM ni los plugins de tmux
#   --no-mcp           no registra servidores MCP
#   --win-user USUARIO usuario de Windows (por defecto lo detecta; si no puede, lo pregunta)
#   --repos RUTA       carpeta de repos (por defecto /mnt/c/Users/<usuario>/source/repos)
# Los archivos del kit son plantillas: @WINHOME@, @WIN_USER@, @HOME@ y @LINUX_USER@ se
# reemplazan por los valores de esta máquina antes de instalar.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

DRY=0 PLUGINS=1 MCP=1 GITHOOKS=1 REPOS_DIR=""
STAMP="$(date +%Y%m%d-%H%M%S)"
while (( $# )); do
  case "$1" in
    --dry-run) DRY=1 ;; --no-plugins) PLUGINS=0 ;; --no-mcp) MCP=0 ;; --no-git-hooks) GITHOOKS=0 ;;
    --win-user) export WIN_USER="${2:?falta el usuario}"; shift ;;
    --repos) REPOS_DIR="${2:?falta la ruta}"; shift ;;
    -h|--help) sed -n '3,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
  shift
done
[[ -d "$FILES" ]] || die "No hay files/: corre primero export.sh en la máquina de origen"

WU="$(win_user)"
if [[ -z "$WU" && -t 0 ]]; then read -rp "Usuario de Windows (carpeta en C:\\Users\\): " WU; fi
[[ -n "$WU" ]] || die "No pude detectar el usuario de Windows: usa --win-user USUARIO"
REPOS_DIR="${REPOS_DIR:-/mnt/c/Users/$WU/source/repos}"
log "Usuario de Windows: $WU · repos: $REPOS_DIR"

# Copia renderizada de las plantillas: lo que se instala ya trae las rutas de esta máquina.
RENDER="$(mktemp -d)"; trap 'rm -rf "$RENDER"' EXIT
cp -a "$KIT/files/." "$RENDER/"
render_templates "$RENDER" "$WU" "$HOME" "$(id -un)"
FILES="$RENDER/home"; MCP_FILE="$RENDER/mcp-servers.json"

#######################################
# Copia un archivo del repo a $HOME con respaldo si cambia.
# Arguments: ruta relativa. Outputs: estado (nuevo / cambia / igual).
#######################################
apply_file() {
  local rel="$1" src="$FILES/$1" dst="$HOME/$1"
  if [[ ! -e "$dst" ]]; then
    printf '  nuevo   %s\n' "$rel"
  elif cmp -s "$src" "$dst"; then
    printf '  igual   %s\n' "$rel"; return 0
  else
    printf '  cambia  %s\n' "$rel"
    (( DRY )) || cp -p "$dst" "$dst.bak.$STAMP"
  fi
  (( DRY )) || install -D -m "$(stat -c '%a' "$src")" "$src" "$dst"
}

#######################################
# Agrega a ~/.bashrc las líneas del kit que falten (no duplica las que ya existen).
#######################################
ensure_bashrc() {
  local line
  local -a lines=(
    "export REPOS=$REPOS_DIR"
    '[ -f ~/.config/tmux-claude/functions.sh ] && . ~/.config/tmux-claude/functions.sh'
    '[ -f ~/.config/tmux-claude/cuentas.sh ] && . ~/.config/tmux-claude/cuentas.sh'
    '[ -f ~/.config/tmux-claude/shell.sh ] && . ~/.config/tmux-claude/shell.sh'
  )
  for line in "${lines[@]}"; do
    if grep -qF "${line##* ~/}" "$HOME/.bashrc" 2>/dev/null; then printf '  igual   .bashrc: %s\n' "${line:0:50}"
    else printf '  agrega  .bashrc: %s\n' "${line:0:50}"; (( DRY )) || printf '%s\n' "$line" >> "$HOME/.bashrc"; fi
  done
}

log "Archivos ($([[ $DRY -eq 1 ]] && echo 'simulación' || echo "respaldo: *.bak.$STAMP"))"
while IFS= read -r rel; do apply_file "$rel"; done < <(manifest_files "$FILES")
ensure_bashrc

# Compuerta de git: los hooks del kit (secretos, mensaje, push a main) solo corren si git los busca en
# ~/.config/git/hooks. Se fija solo si no hay otro valor: no pisa el tuyo. --no-git-hooks lo omite.
if (( GITHOOKS )); then
  log "Compuerta de git"
  hp_actual="$(git config --global --get core.hooksPath 2>/dev/null || true)"
  if [[ "$hp_actual" == "$HOME/.config/git/hooks" ]]; then printf '  igual   core.hooksPath\n'
  elif [[ -z "$hp_actual" ]]; then
    printf '  nuevo   core.hooksPath → ~/.config/git/hooks\n'
    (( DRY )) || git config --global core.hooksPath "$HOME/.config/git/hooks"
  else printf '  omite   core.hooksPath ya apunta a %s (no se cambia)\n' "$hp_actual"; fi
fi

if (( PLUGINS )); then
  log "Plugins de tmux"
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    printf '  nuevo   tpm\n'; (( DRY )) || git clone -q https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
  (( DRY )) || "$HOME/.tmux/plugins/tpm/bin/install_plugins" | sed 's/^/  /'
fi

if (( MCP )) && [[ -s "$MCP_FILE" ]]; then
  log "Servidores MCP de usuario"
  command -v claude >/dev/null || die "Falta Claude Code: curl -fsSL https://claude.ai/install.sh -o /tmp/ci.sh, revísalo y bash /tmp/ci.sh"
  while IFS= read -r name; do
    cmd="$(jq -r --arg n "$name" '.[$n].command // empty' "$MCP_FILE")"
    if [[ "$cmd" == /* && ! -e "$cmd" ]]; then printf '  omite   %s (no existe %s en esta máquina)\n' "$name" "$cmd"; continue; fi
    if claude mcp get "$name" >/dev/null 2>&1; then printf '  igual   %s\n' "$name"
    else printf '  nuevo   %s\n' "$name"; (( DRY )) || claude mcp add-json "$name" "$(jq -c --arg n "$name" '.[$n]' "$MCP_FILE")" --scope user >/dev/null
    fi
  done < <(jq -r 'keys[]' "$MCP_FILE")
fi

if [[ -f "$KIT/files/windows/.wslconfig" ]]; then
  log "Windows: compara a mano files/windows/.wslconfig con %UserProfile%\\.wslconfig (no se aplica automático)"
fi
if (( DRY )); then log "Simulación: no se escribió nada."
else log "Listo. Recarga: tmux source-file ~/.tmux.conf; en cada pestaña /exit y claude -c"; fi
