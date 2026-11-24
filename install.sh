#!/usr/bin/env bash
#
# install.sh — applies the repo's configuration (files/) to this machine WITHOUT overwriting blindly:
# every file that changes is backed up first as <file>.bak.<date>; what is already the same is left alone.
#
# Usage: bash install.sh [--dry-run] [--no-plugins] [--no-mcp] [--no-git-hooks] [--win-user USER] [--repos PATH]
#   --dry-run          shows what would change (new / changed / same) without writing anything
#   --no-plugins       does not install TPM or the tmux plugins
#   --no-mcp           does not register MCP servers
#   --win-user USER    Windows user (detected by default; if it cannot, it asks)
#   --repos PATH       repos folder (default /mnt/c/Users/<user>/source/repos)
# The kit's files are templates: @WINHOME@, @WIN_USER@, @HOME@ and @LINUX_USER@ are
# replaced with this machine's values before installing.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

DRY=0 PLUGINS=1 MCP=1 GITHOOKS=1 REPOS_DIR=""
STAMP="$(date +%Y%m%d-%H%M%S)"
while (( $# )); do
  case "$1" in
    --dry-run) DRY=1 ;; --no-plugins) PLUGINS=0 ;; --no-mcp) MCP=0 ;; --no-git-hooks) GITHOOKS=0 ;;
    --win-user) export WIN_USER="${2:?missing user}"; shift ;;
    --repos) REPOS_DIR="${2:?missing path}"; shift ;;
    -h|--help) sed -n '3,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
[[ -d "$FILES" ]] || die "There is no files/: run export.sh first on the source machine"

WU="$(win_user)"
if [[ -z "$WU" && -t 0 ]]; then read -rp "Windows user (folder in C:\\Users\\): " WU; fi
[[ -n "$WU" ]] || die "Could not detect the Windows user: use --win-user USER"
REPOS_DIR="${REPOS_DIR:-/mnt/c/Users/$WU/source/repos}"
log "Windows user: $WU · repos: $REPOS_DIR"

# Rendered copy of the templates: what gets installed already has this machine's paths.
RENDER="$(mktemp -d)"; trap 'rm -rf "$RENDER"' EXIT
cp -a "$KIT/files/." "$RENDER/"
render_templates "$RENDER" "$WU" "$HOME" "$(id -un)"
FILES="$RENDER/home"; MCP_FILE="$RENDER/mcp-servers.json"

#######################################
# Copies a file from the repo to $HOME, with a backup if it changes.
# Arguments: relative path. Outputs: status (new / changed / same).
#######################################
apply_file() {
  local rel="$1" src="$FILES/$1" dst="$HOME/$1"
  if [[ ! -e "$dst" ]]; then
    printf '  new     %s\n' "$rel"
  elif cmp -s "$src" "$dst"; then
    printf '  same    %s\n' "$rel"; return 0
  else
    printf '  changed %s\n' "$rel"
    (( DRY )) || cp -p "$dst" "$dst.bak.$STAMP"
  fi
  (( DRY )) || install -D -m "$(stat -c '%a' "$src")" "$src" "$dst"
}

#######################################
# Adds to ~/.bashrc the kit's lines that are missing (does not duplicate existing ones).
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
    if grep -qF "${line##* ~/}" "$HOME/.bashrc" 2>/dev/null; then printf '  same    .bashrc: %s\n' "${line:0:50}"
    else printf '  added   .bashrc: %s\n' "${line:0:50}"; (( DRY )) || printf '%s\n' "$line" >> "$HOME/.bashrc"; fi
  done
}

log "Files ($([[ $DRY -eq 1 ]] && echo 'dry run' || echo "backup: *.bak.$STAMP"))"
while IFS= read -r rel; do apply_file "$rel"; done < <(manifest_files "$FILES")
ensure_bashrc

# Git gate: the kit's hooks (secrets, message, push to main) only run if git looks for them in
# ~/.config/git/hooks. Set only if there is no other value: it does not override yours. --no-git-hooks skips it.
if (( GITHOOKS )); then
  log "Git gate"
  hp_actual="$(git config --global --get core.hooksPath 2>/dev/null || true)"
  if [[ "$hp_actual" == "$HOME/.config/git/hooks" ]]; then printf '  same    core.hooksPath\n'
  elif [[ -z "$hp_actual" ]]; then
    printf '  new     core.hooksPath → ~/.config/git/hooks\n'
    (( DRY )) || git config --global core.hooksPath "$HOME/.config/git/hooks"
  else printf '  skipped core.hooksPath already points to %s (not changed)\n' "$hp_actual"; fi
fi

if (( PLUGINS )); then
  log "tmux plugins"
  if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
    printf '  new     tpm\n'; (( DRY )) || git clone -q https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
  fi
  (( DRY )) || "$HOME/.tmux/plugins/tpm/bin/install_plugins" | sed 's/^/  /'
fi

if (( MCP )) && [[ -s "$MCP_FILE" ]]; then
  log "User MCP servers"
  command -v claude >/dev/null || die "Claude Code is missing: curl -fsSL https://claude.ai/install.sh -o /tmp/ci.sh, review it and bash /tmp/ci.sh"
  while IFS= read -r name; do
    cmd="$(jq -r --arg n "$name" '.[$n].command // empty' "$MCP_FILE")"
    if [[ "$cmd" == /* && ! -e "$cmd" ]]; then printf '  skipped %s (%s does not exist on this machine)\n' "$name" "$cmd"; continue; fi
    if claude mcp get "$name" >/dev/null 2>&1; then printf '  same    %s\n' "$name"
    else printf '  new     %s\n' "$name"; (( DRY )) || claude mcp add-json "$name" "$(jq -c --arg n "$name" '.[$n]' "$MCP_FILE")" --scope user >/dev/null
    fi
  done < <(jq -r 'keys[]' "$MCP_FILE")
fi

if [[ -f "$KIT/files/windows/.wslconfig" ]]; then
  log "Windows: compare files/windows/.wslconfig with %UserProfile%\\.wslconfig by hand (it is not applied automatically)"
fi
if (( DRY )); then log "Dry run: nothing was written."
else log "Done. Reload: tmux source-file ~/.tmux.conf; in each tab /exit and claude -c"; fi
