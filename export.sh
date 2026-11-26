#!/usr/bin/env bash
#
# export.sh — captures this machine's REAL configuration into the repo (files/).
# Copies what manifest.txt lists, the user MCP servers (~/.claude.json → mcpServers, merged into the kit's)
# and the Windows .wslconfig. Turns personal paths and users into template placeholders
# (@WINHOME@, @WIN_USER@, @HOME@, @LINUX_USER@) so the kit works for the whole team.
# Refuses to export if it detects secrets.
#
# Usage: bash export.sh      Then: git diff, review and commit (Conventional Commits).
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# Kit-only files that do not come from $HOME survive the export: the MCP lock (WS-AI-009), the managed policy
# template (files/etc, installed by install.sh --managed) and the MCP definitions, which are merged below.
KEEP="$(mktemp -d)"; trap 'rm -rf "$KEEP"' EXIT
for k in mcp-servers.json mcp-servers.lock.json etc; do if [[ -e "$KIT/files/$k" ]]; then cp -a "$KIT/files/$k" "$KEEP/"; fi; done
rm -rf "$KIT/files" && mkdir -p "$FILES"
for k in mcp-servers.lock.json etc; do if [[ -e "$KEEP/$k" ]]; then cp -a "$KEEP/$k" "$KIT/files/"; fi; done
n=0
while IFS= read -r rel; do
  install -D -m "$(stat -c '%a' "$HOME/$rel")" "$HOME/$rel" "$FILES/$rel"
  n=$((n + 1))
done < <(manifest_files "$HOME")
log "$n configuration files"

if [[ -s "$HOME/.claude.json" ]]; then
  # Merged, not replaced: a kit server that is not registered here (an opt-in one such as chrome-devtools) stays; a
  # registered one takes this machine's definition, unwrapped from ws-mcp-keepalive and ws-mcp-jail, with the kit's
  # jail and keepalive keys (ADR-024, ADR-025).
  [[ -s "$KEEP/mcp-servers.json" ]] || echo '{}' > "$KEEP/mcp-servers.json"
  mcp_unwrap_merge "$KEEP/mcp-servers.json" "$HOME/.claude.json" > "$MCP_FILE"
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
