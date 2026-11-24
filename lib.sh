# shellcheck shell=bash
# lib.sh — funciones comunes de export.sh e install.sh (kit claude-workstation).

# Raíz del repo y carpeta espejo del $HOME (las usan export.sh e install.sh).
# shellcheck disable=SC2034
KIT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
FILES="$KIT/files/home"
# shellcheck disable=SC2034
MCP_FILE="$KIT/files/mcp-servers.json"

log()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'xx  %s\n' "$*" >&2; exit 1; }

#######################################
# Lista las rutas del manifiesto (sin comentarios ni líneas vacías).
# Outputs: una ruta relativa a $HOME por línea.
#######################################
manifest_paths() { grep -vE '^\s*(#|$)' "$KIT/manifest.txt"; }

#######################################
# Expande el manifiesto a archivos concretos bajo una raíz dada.
# Arguments: raíz ($HOME para exportar, $FILES para instalar).
# Outputs: rutas relativas de archivos existentes.
#######################################
manifest_files() {
  local root="$1" p
  while IFS= read -r p; do
    if [[ "$p" == */ ]]; then
      [[ -d "$root/$p" ]] && (cd "$root" && find "${p%/}" -maxdepth 1 -type f ! -name '*.bak.*' | sort)
    else
      [[ -f "$root/$p" ]] && printf '%s\n' "$p"
    fi
  done < <(manifest_paths)
}

#######################################
# Detecta secretos en archivos (tokens, llaves, connection strings).
# Omite las rutas de secrets-allow.txt (relativas a files/): archivos que CONTIENEN los
# patrones de detección, como guard.sh, y no secretos reales.
# Arguments: directorio a revisar.
# Returns: 0 si encontró algo (y lo imprime), 1 si está limpio.
#######################################
find_secrets() {
  local allow="$KIT/secrets-allow.txt" f rel hit=1
  while IFS= read -r -d '' f; do
    rel="${f#"$KIT"/files/}"
    if [[ -f "$allow" ]] && grep -vE '^\s*(#|$)' "$allow" | grep -qxF "$rel"; then continue; fi
    grep -EnIH -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AccountKey=[A-Za-z0-9+/=]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|SharedAccessSignature=|[?&]sig=[A-Za-z0-9%]{30,}|"(password|secret|client_secret|api_key|token)"[[:space:]]*:[[:space:]]*"[^"*]{6,}"' "$f" && hit=0
  done < <(find "$@" -type f -print0)
  return "$hit"
}

#######################################
# Usuario de Windows: $WIN_USER, o el que reporta Windows por interop (vacío si no hay).
# Outputs: nombre de usuario de Windows.
#######################################
win_user() {
  if [[ -n "${WIN_USER:-}" ]]; then echo "$WIN_USER"; return; fi
  cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r' || true
}

# re_escape <texto> — escapa los caracteres especiales de una expresión regular de sed.
re_escape() { printf '%s' "$1" | sed -e 's/[.*^$#&/\\[]/\\&/g' -e 's/]/\\]/g'; }

#######################################
# Convierte en plantilla los archivos de una carpeta: reemplaza las rutas y usuarios de
# esta máquina por marcadores, para que el kit sirva a cualquier persona del equipo.
#   /mnt/c/Users/<usuario Windows> → @WINHOME@   ·   <usuario Windows> → @WIN_USER@
#   $HOME → @HOME@   ·   <usuario Linux> → @LINUX_USER@
# Arguments: carpeta, usuario de Windows, home de Linux, usuario de Linux.
#######################################
templatize() {
  local dir="$1" wu home lu f
  wu="$(re_escape "$2")"; home="$(re_escape "$3")"; lu="$(re_escape "$4")"
  while IFS= read -r -d '' f; do
    grep -Iq . "$f" || continue
    [[ -n "$wu" ]] && sed -i "s#/mnt/c/Users/${wu}#@WINHOME@#g" "$f"
    [[ -n "$home" ]] && sed -i "s#${home}#@HOME@#g" "$f"
    [[ -n "$wu" ]] && sed -i "s#${wu}#@WIN_USER@#g" "$f"
    [[ -n "$lu" ]] && sed -i "s#\b${lu}\b#@LINUX_USER@#g" "$f"
  done < <(find "$dir" -type f -print0)
}

#######################################
# Sustituye los marcadores por los valores de la máquina destino (inverso de templatize).
# Arguments: carpeta, usuario de Windows, home de Linux, usuario de Linux.
#######################################
render_templates() {
  local dir="$1" wu="$2" home="$3" lu="$4" f
  while IFS= read -r -d '' f; do
    grep -Iq . "$f" || continue
    grep -q '@\(WINHOME\|WIN_USER\|HOME\|LINUX_USER\)@' "$f" || continue
    sed -i -e "s#@WINHOME@#/mnt/c/Users/${wu}#g" -e "s#@WIN_USER@#${wu}#g" \
           -e "s#@HOME@#${home}#g" -e "s#@LINUX_USER@#${lu}#g" "$f"
  done < <(find "$dir" -type f -print0)
}
