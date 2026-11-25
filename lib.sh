# shellcheck shell=bash
# lib.sh — functions shared by export.sh and install.sh (claude-workstation kit).

# Repo root and the folder that mirrors $HOME (used by export.sh and install.sh).
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
# Lists the manifest's paths (without comments or empty lines).
# Outputs: one path relative to $HOME per line.
#######################################
manifest_paths() { grep -vE '^\s*(#|$)' "$KIT/manifest.txt"; }

#######################################
# Expands the manifest into concrete files under a given root.
# Arguments: root ($HOME to export, $FILES to install).
# Outputs: relative paths of existing files. In a folder, *.bak.* files are skipped: the copies that installers
# before 3.0 left next to each file (now they go to ~/.local/share/ws-kit/backup.<date>/; `install.sh
# --prune-backups` moves the old ones away).
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
# Detects secrets in files (tokens, keys, connection strings).
# Skips the paths in secrets-allow.txt (relative to files/): files that CONTAIN the
# detection patterns, like guard.sh, and not real secrets.
# Arguments: directory to check.
# Returns: 0 if it found something (and prints it), 1 if it is clean.
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
# Windows user: $WIN_USER, or the one Windows reports through interop (empty if none).
# Outputs: Windows user name.
#######################################
win_user() {
  if [[ -n "${WIN_USER:-}" ]]; then echo "$WIN_USER"; return; fi
  cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r' || true
}

# re_escape <text> — escapes the special characters of a sed regular expression.
re_escape() { printf '%s' "$1" | sed -e 's/[.*^$#&/\\[]/\\&/g' -e 's/]/\\]/g'; }

#######################################
# Turns the files of a folder into templates: replaces this machine's paths and users
# with placeholders, so the kit works for anyone on the team.
#   /mnt/c/Users/<Windows user> → @WINHOME@   ·   <Windows user> → @WIN_USER@
#   $HOME → @HOME@   ·   <Linux user> → @LINUX_USER@
# Arguments: folder, Windows user, Linux home, Linux user.
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
# Replaces the placeholders with the target machine's values (inverse of templatize).
# Arguments: folder, Windows user, Linux home, Linux user.
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
