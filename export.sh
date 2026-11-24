#!/usr/bin/env bash
#
# export.sh — captura la configuración REAL de esta máquina hacia el repo (files/).
# Copia lo que lista manifest.txt, los servidores MCP de usuario (~/.claude.json → mcpServers)
# y el .wslconfig de Windows. Convierte en plantilla las rutas y usuarios personales
# (@WINHOME@, @WIN_USER@, @HOME@, @LINUX_USER@) para que el kit sirva a todo el equipo.
# Se niega a exportar si detecta secretos.
#
# Uso: bash export.sh        Después: git diff, revisar y commit (Conventional Commits).
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

rm -rf "$KIT/files" && mkdir -p "$FILES"
n=0
while IFS= read -r rel; do
  install -D -m "$(stat -c '%a' "$HOME/$rel")" "$HOME/$rel" "$FILES/$rel"
  n=$((n + 1))
done < <(manifest_files "$HOME")
log "$n archivos de configuración"

if [[ -s "$HOME/.claude.json" ]]; then
  jq '.mcpServers // {}' "$HOME/.claude.json" > "$MCP_FILE"
  log "$(jq 'length' "$MCP_FILE") servidores MCP de usuario: $(jq -r 'keys | join(", ")' "$MCP_FILE")"
fi

WU="$(win_user)"
wslconfig="/mnt/c/Users/${WU:-sin-usuario}/.wslconfig"
if [[ -f "$wslconfig" ]]; then
  install -D -m 644 "$wslconfig" "$KIT/files/windows/.wslconfig" && log ".wslconfig de Windows"
fi

templatize "$KIT/files" "$WU" "$HOME" "$(id -un)"
log "Rutas personales convertidas en plantilla (usuario de Windows: ${WU:-no detectado})"

if find_secrets "$KIT/files"; then
  rm -rf "$KIT/files"
  die "Se detectaron posibles secretos (arriba). No se exportó nada: muévelos a Key Vault o a un helper y vuelve a correr."
fi
log "Sin secretos. Revisa con: git -C \"$KIT\" diff --stat"
