#!/usr/bin/env bash
#
# export.sh — captures this machine's REAL configuration into the repo (files/).
# Copies what manifest.txt lists, the user MCP servers (~/.claude.json → mcpServers)
# and the Windows .wslconfig. Turns personal paths and users into template placeholders
# (@WINHOME@, @WIN_USER@, @HOME@, @LINUX_USER@) so the kit works for the whole team.
# Refuses to export if it detects secrets.
#
# Usage: bash export.sh      Then: git diff, review and commit (Conventional Commits).
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

rm -rf "$KIT/files" && mkdir -p "$FILES"
n=0
while IFS= read -r rel; do
  install -D -m "$(stat -c '%a' "$HOME/$rel")" "$HOME/$rel" "$FILES/$rel"
  n=$((n + 1))
done < <(manifest_files "$HOME")
log "$n configuration files"

if [[ -s "$HOME/.claude.json" ]]; then
  jq '.mcpServers // {}' "$HOME/.claude.json" > "$MCP_FILE"
  log "$(jq 'length' "$MCP_FILE") user MCP servers: $(jq -r 'keys | join(", ")' "$MCP_FILE")"
fi

WU="$(win_user)"
wslconfig="/mnt/c/Users/${WU:-no-user}/.wslconfig"
if [[ -f "$wslconfig" ]]; then
  install -D -m 644 "$wslconfig" "$KIT/files/windows/.wslconfig" && log "Windows .wslconfig"
fi

templatize "$KIT/files" "$WU" "$HOME" "$(id -un)"
log "Personal paths turned into template placeholders (Windows user: ${WU:-not detected})"

if find_secrets "$KIT/files"; then
  rm -rf "$KIT/files"
  die "Possible secrets detected (above). Nothing was exported: move them to Key Vault or a helper and run again."
fi
log "No secrets. Review with: git -C \"$KIT\" diff --stat"
