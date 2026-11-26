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

#######################################
# The definition install.sh registers for an MCP server (ADR-024): a stdio server whose entry in mcp-servers.json
# has a "jail" object runs through ~/.local/bin/ws-mcp-jail, with --net, --azure-config, --ro and --rw taken from
# that object; "jail": false (with "jailOptOut", the reason) or an HTTP server is registered as written. The jail
# keys are never passed to claude mcp add-json.
# Arguments: mcp-servers.json, server name, home. Outputs: compact JSON.
#######################################
mcp_want() {
  jq -c --arg n "$2" --arg h "$3" '.[$n] as $s
    | ($s | del(.jail, .jailOptOut)) as $d
    | if (($s.type // "stdio") == "stdio") and (($s.jail | type) == "object") then
        $d + {command: ($h + "/.local/bin/ws-mcp-jail"),
              args: (["--name", $n] + (if $s.jail.net then ["--net"] else ["--no-net"] end)
                     + (if $s.jail.azureConfig then ["--azure-config"] else [] end)
                     + ([($s.jail.ro // [])[] | ["--ro", .]] | add // [])
                     + ([($s.jail.rw // [])[] | ["--rw", .]] | add // [])
                     + ["--", $s.command] + ($s.args // []))}
      else $d end' "$1"
}

#######################################
# The inverse of mcp_want for export.sh: a registration that runs through ws-mcp-jail goes back to the server's own
# command and arguments, and keeps the kit's jail keys. Arguments: kit mcp-servers.json, ~/.claude.json.
# Outputs: the merged mcp-servers.json.
#######################################
mcp_unwrap_merge() {
  jq -s '(.[0] // {}) as $k
    | ((.[1].mcpServers // {}) | to_entries | map(
        .key as $n | .value |= (
          (if ((.command // "") | endswith("/ws-mcp-jail")) and ((.args // []) | index("--")) then
             (.args | index("--")) as $i | .command = .args[$i + 1] | .args = .args[($i + 2):]
           else . end)
          + ({jail: $k[$n].jail, jailOptOut: $k[$n].jailOptOut} | with_entries(select(.value != null)))))
       | from_entries) as $r
    | $k + $r' "$1" "$2"
}

#######################################
# The managed MCP allow list (WS-AI-010, ADR-024), as a managed-settings.d drop-in: one entry per kit server, matched
# by what it runs, never by name (Claude Code's docs: «A serverName entry, in either list, is not a security
# control»): serverCommand is the exact command and arguments install.sh registers (ws-mcp-jail included), serverUrl
# the exact URL of an HTTP server. allowManagedMcpServersOnly makes Claude Code ignore allow lists in user, project
# and local settings, so a repository cannot widen it. Every other server is blocked, the claude.ai connectors and
# plugin servers included, unless the owner lists them in the optional extra file (a JSON array of allowedMcpServers
# entries, e.g. {"serverUrl": "https://mcp.example.com/*"}), reviewed when install.sh --managed prints it.
# Arguments: rendered mcp-servers.json, home, [extra entries file]. Outputs: the drop-in JSON.
#######################################
mcp_allowlist() {
  local n extra='[]' entries=()
  if [[ -n "${3:-}" && -s "$3" ]]; then
    extra="$(jq -c 'if type == "array" then . else error("not an array") end' "$3" 2>/dev/null)" \
      || { warn "$3 is not a JSON array of allowedMcpServers entries: ignored"; extra='[]'; }
  fi
  while IFS= read -r n; do
    entries+=("$(mcp_want "$1" "$n" "$2" | jq -c 'if .type == "http" then {serverUrl: .url}
                                                  else {serverCommand: ([.command] + (.args // []))} end')")
  done < <(jq -r 'keys[]' "$1")
  printf '%s\n' "${entries[@]}" | jq -s --argjson x "$extra" \
    '{allowManagedMcpServersOnly: true, allowedMcpServers: (. + $x | unique)}'
}
