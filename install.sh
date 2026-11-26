#!/usr/bin/env bash
#
# install.sh — applies the repo's configuration (files/) to this machine WITHOUT overwriting blindly:
# every file that changes is copied first to ~/.local/share/ws-kit/backup.<date>/<same path>; what is already the
# same is left alone. The newest 10 backup folders are kept.
#
# Usage: bash install.sh [--dry-run] [--no-plugins] [--no-mcp] [--no-git-hooks] [--win-user USER] [--repos PATH]
#                        [--mcp-opt-in NAME]... [--mcp-accept NAME]... [--mcp-refresh]
#        bash install.sh --managed [--mcp-allowlist] [--dry-run] [--win-user USER]   the managed policy, as root
#        bash install.sh --remove-shims   deletes the wrappers left under the names used before 3.0
#        bash install.sh --prune-backups [--dry-run]   moves the <file>.bak.<date> copies that earlier versions left
#                           next to each file into ~/.local/share/ws-kit/backup.legacy/
#   --dry-run          shows what would change (new / changed / same) without writing anything
#   --no-plugins       does not install TPM or the tmux plugins
#   --no-mcp           does not register MCP servers
#   --win-user USER    Windows user (detected by default; if it cannot, it asks)
#   --repos PATH       repos folder (default /mnt/c/Users/<user>/source/repos)
#   --mcp-opt-in NAME  also registers an MCP server the lock marks opt-in (chrome-devtools)
#   --mcp-accept NAME  re-pins a local MCP executable whose sha256 changed, after you reviewed the change
#   --mcp-refresh      re-registers the kit's MCP servers whose registered definition differs from mcp-servers.json
#   --managed          installs ONLY the managed policy (ADR-013, WS-AI-002) with sudo: the drop-in
#                      /etc/claude-code/managed-settings.d/50-ws-kit.json (deny floor, guard failing closed, bypass
#                      mode off), a root-owned copy of guard.sh in /etc/claude-code/hooks/ and the credential list;
#                      it prints every command first and asks; with --dry-run it only prints them. Never automatic.
#   --mcp-allowlist    with --managed, also the drop-in 55-ws-mcp-allow.json (ADR-024, WS-AI-010): allowedMcpServers
#                      generated from mcp-servers.json (each server by its exact command or URL) and
#                      allowManagedMcpServersOnly. It BLOCKS every other server, the claude.ai connectors and plugin
#                      servers included, unless they are listed in ~/.config/ws-mcp/allow-extra.json (a JSON array of
#                      {"serverUrl": …} or {"serverCommand": […]} entries). The file is printed before sudo asks.
# Every stdio MCP server with a "jail" object in mcp-servers.json is registered through ws-mcp-jail (bubblewrap);
# "jail": false needs a "jailOptOut" reason (Windows executables cannot be confined). Every stdio server also runs
# through ws-mcp-keepalive (ADR-025: restarted when it exits mid-session) unless it says "keepalive": false. A
# registration that runs the same server without the kit's current wrappers is re-registered automatically;
# --mcp-refresh re-registers any other difference.
# MCP servers are checked against files/mcp-servers.lock.json first: npm ones are installed with ws-pinned from a
# committed package-lock.json, local executables are pinned by sha256 on first use; a mismatch skips that server.
# The kit's files are templates: @WINHOME@, @WIN_USER@, @HOME@ and @LINUX_USER@ are
# replaced with this machine's values before installing.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/migrate.sh"

DRY=0 PLUGINS=1 MCP=1 GITHOOKS=1 SHIMS=0 PRUNE=0 REPOS_DIR="" MCP_REFRESH=0 MANAGED=0 MCP_ALLOW=0
MCP_OPT_IN=() MCP_ACCEPT=()
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$HOME/.local/share/ws-kit"   # also holds pre-english.<date> (migrate.sh), which is never pruned
BACKUP_DIR="$BACKUP_ROOT/backup.$STAMP"
BACKUP_KEEP=10
while (( $# )); do
  case "$1" in
    --dry-run) DRY=1 ;; --no-plugins) PLUGINS=0 ;; --no-mcp) MCP=0 ;; --no-git-hooks) GITHOOKS=0 ;;
    --remove-shims) SHIMS=1 ;;
    --prune-backups) PRUNE=1 ;;
    --win-user) export WIN_USER="${2:?missing user}"; shift ;;
    --repos) REPOS_DIR="${2:?missing path}"; shift ;;
    --mcp-opt-in) MCP_OPT_IN+=("${2:?missing server name}"); shift ;;
    --mcp-accept) MCP_ACCEPT+=("${2:?missing server name}"); shift ;;
    --mcp-refresh) MCP_REFRESH=1 ;;
    --managed) MANAGED=1 ;;
    --mcp-allowlist) MCP_ALLOW=1 ;;
    -h|--help) sed -n '3,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

#######################################
# Copies a file of $HOME into this run's backup folder, keeping its relative path. Used before a file is replaced
# (apply_file) and by migrate.sh for ~/.bashrc. Does nothing in a dry run, and never replaces a copy already there.
# Arguments: path relative to $HOME.
#######################################
backup_file() {
  (( DRY )) && return 0
  [[ -e "$BACKUP_DIR/$1" ]] && return 0
  mkdir -p "$(dirname "$BACKUP_DIR/$1")" && cp -p "$HOME/$1" "$BACKUP_DIR/$1"
}

#######################################
# Keeps the newest $BACKUP_KEEP backup.<date> folders and deletes the older ones. Only folders named by a date are
# touched: pre-english.<date> and backup.legacy are never deleted.
#######################################
rotate_backups() {
  local d
  while IFS= read -r d; do rm -rf -- "$d"; done < <(
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'backup.[0-9]*' 2>/dev/null | sort -r \
      | tail -n +$((BACKUP_KEEP + 1))
  )
}

#######################################
# Moves the <file>.bak.<date> copies that versions before 3.0 left next to each file into
# ~/.local/share/ws-kit/backup.legacy/<relative path>.<date>. Looks only at the kit's own paths: every manifest
# path (files, and the files directly inside its folders), ~/.bashrc and the names used before 3.0 (renames.tsv).
# Outputs: one line per file and the count. Uses DRY.
#######################################
prune_legacy_backups() {
  local p f rel n=0 dest="$BACKUP_ROOT/backup.legacy"
  while IFS= read -r f; do
    [[ -f "$f" && "$f" =~ ^(.*)\.bak\.([0-9][0-9-]*)$ ]] || continue
    rel="${BASH_REMATCH[1]#"$HOME"/}.${BASH_REMATCH[2]}"
    printf '  moved   %s\n' "${f#"$HOME"/}"; n=$((n + 1))
    (( DRY )) || { mkdir -p "$(dirname "$dest/$rel")" && mv -f -- "$f" "$dest/$rel"; }
  done < <(
    { manifest_paths; echo .bashrc; awk -F'\t' '$1 !~ /^#/ && NF >= 3 { print $2 }' "$KIT/renames.tsv"; } | sort -u \
      | while IFS= read -r p; do
          if [[ "$p" == */ ]]; then find "$HOME/${p%/}" -maxdepth 1 -type f -name '*.bak.*' 2>/dev/null || true
          else compgen -G "$HOME/$p.bak.*" || true; fi
        done | sort -u
  )
  if (( DRY )); then log "Dry run: $n backup files would be moved to ${dest/#"$HOME"/\~}"
  else log "$n backup files moved to ${dest/#"$HOME"/\~}"; fi
}

if (( SHIMS )); then log "Wrappers of the old names"; remove_shims; exit 0; fi
if (( PRUNE )); then log "Backups left next to the files (*.bak.<date>)"; prune_legacy_backups; exit 0; fi
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
FILES="$RENDER/home"; MCP_FILE="$RENDER/mcp-servers.json"; MCP_LOCK="$RENDER/mcp-servers.lock.json"
# The owner's per-server choices made from Menu → Settings (ADR-028): ~/.config/ws-mcp/overrides.json may only turn
# the keepalive of a kit server off or on ({"<name>": {"keepalive": false}}); any other key is ignored.
if [[ -s "$HOME/.config/ws-mcp/overrides.json" ]] && jq -e 'type == "object"' "$HOME/.config/ws-mcp/overrides.json" >/dev/null 2>&1; then
  jq --slurpfile o "$HOME/.config/ws-mcp/overrides.json" 'reduce ($o[0] | to_entries[]) as $e (.;
      if has($e.key) and ($e.value.keepalive | type) == "boolean" then .[$e.key].keepalive = $e.value.keepalive else . end)' \
    "$MCP_FILE" > "$RENDER/mcp-servers.ov.json" && mv "$RENDER/mcp-servers.ov.json" "$MCP_FILE"
fi

#######################################
# Copies a file from the repo to $HOME, with a backup (backup_file) if it changes.
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
    backup_file "$rel"
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
    '[ -f ~/.config/tmux-claude/accounts.sh ] && . ~/.config/tmux-claude/accounts.sh'
    '[ -f ~/.config/tmux-claude/shell.sh ] && . ~/.config/tmux-claude/shell.sh'
  )
  for line in "${lines[@]}"; do
    if grep -qF "${line##* ~/}" "$HOME/.bashrc" 2>/dev/null; then printf '  same    .bashrc: %s\n' "${line:0:50}"
    else printf '  added   .bashrc: %s\n' "${line:0:50}"; (( DRY )) || printf '%s\n' "$line" >> "$HOME/.bashrc"; fi
  done
}

#######################################
# The user-scope registration of an MCP server, as Claude Code stored it in ~/.claude.json (empty if none).
# Arguments: server name. Outputs: compact JSON.
#######################################
mcp_registered() { jq -c --arg n "$1" '.mcpServers[$n] // empty' "$HOME/.claude.json" 2>/dev/null || true; }

#######################################
# Whether a registered definition is the kit's: same type, command, args, env and url (other keys Claude Code adds,
# such as alwaysLoad, are ignored). Arguments: registered JSON, wanted JSON.
#######################################
mcp_same() {
  local k='{type: (.type // "stdio"), command: (.command // ""), args: (.args // []), env: (.env // {}),
            url: (.url // "")}'
  [[ "$(jq -cS "$k" <<<"$1")" == "$(jq -cS "$k" <<<"$2")" ]]
}

#######################################
# Checks an MCP server against mcp-servers.lock.json before it is registered (WS-AI-009):
#   npm    → the lock's version and integrity agree with the committed package-lock.json, and ws-pinned installs it
#            with npm ci --ignore-scripts (a tarball that does not match is refused); opt-in servers only with
#            --mcp-opt-in or when already registered
#   local  → the executable exists and its sha256 matches the one pinned on first use (--mcp-accept re-pins)
#   remote → the URL is the one in the lock
# Arguments: server name. Outputs: a "skipped" line with the reason. Returns: 0 if it may be registered. Uses DRY.
#######################################
mcp_verify() {
  local n="$1" src cmd pin="$FILES/.local/bin/ws-pinned" locks="$FILES/.local/lib/ws-npm" npm pkg v rc
  src="$(jq -r --arg n "$n" '.servers[$n].source // empty' "$MCP_LOCK")"
  cmd="$(jq -r --arg n "$n" '.[$n].command // empty' "$MCP_FILE")"
  case "$src" in
    npm)
      npm="$(jq -r --arg n "$n" '.servers[$n].npm' "$MCP_LOCK")"
      pkg="$(jq -r --arg n "$n" '.servers[$n].package' "$MCP_LOCK")"
      if [[ "$(jq -r --arg n "$n" '.servers[$n].optIn // false' "$MCP_LOCK")" == true && -z "$(mcp_registered "$n")" \
            && " ${MCP_OPT_IN[*]} " != *" $n "* ]]; then
        printf '  skipped %s (opt-in: bash install.sh --mcp-opt-in %s; see docs/USAGE.md)\n' "$n" "$n"; return 1
      fi
      v="$(jq -r --arg p "node_modules/$pkg" '"\(.packages[$p].version)|\(.packages[$p].integrity)"' \
             "$locks/$npm/package-lock.json" 2>/dev/null)"
      if [[ "$v" != "$(jq -r --arg n "$n" '.servers[$n] | "\(.version)|\(.integrity)"' "$MCP_LOCK")" ]]; then
        warn "MCP $n: mcp-servers.lock.json and ws-npm/$npm/package-lock.json disagree; not registered"; return 1
      fi
      if (( DRY )); then printf '  check   %s (%s@%s, installed with ws-pinned)\n' "$n" "$pkg" "${v%%|*}"; return 0; fi
      if ! WS_NPM_LOCKS="$locks" bash "$pin" install "$npm" </dev/null; then
        warn "MCP $n: the pinned install failed; the session runs without it"; return 1
      fi ;;
    local)
      if [[ "$cmd" != /* || ! -e "$cmd" ]]; then
        printf '  skipped %s (%s does not exist on this machine)\n' "$n" "$cmd"; return 1
      fi
      (( DRY )) && return 0
      rc=0; WS_NPM_LOCKS="$locks" bash "$pin" local-check "$n" "$cmd" </dev/null || rc=$?
      if (( rc == 3 )) || { (( rc == 1 )) && [[ " ${MCP_ACCEPT[*]} " == *" $n "* ]]; }; then
        WS_NPM_LOCKS="$locks" bash "$pin" local-pin "$n" "$cmd" </dev/null
      elif (( rc != 0 )); then
        warn "MCP $n: $cmd changed since it was pinned; not registered."
        warn "Review the change, then: bash install.sh --mcp-accept $n"
        return 1
      fi ;;
    remote)
      if [[ "$(jq -r --arg n "$n" '.[$n].url // ""' "$MCP_FILE")" \
            != "$(jq -r --arg n "$n" '.servers[$n].url' "$MCP_LOCK")" ]]; then
        warn "MCP $n: its URL is not the one in mcp-servers.lock.json; not registered"; return 1
      fi ;;
    *) warn "MCP $n is not in mcp-servers.lock.json; not registered"; return 1 ;;
  esac
}

#######################################
# --managed: the managed policy, installed as root so that neither the agent nor your own files can change it. It is
# a drop-in in managed-settings.d (an organization's managed-settings.json, if there is one, is left alone: Claude
# Code merges the drop-ins after it), the root-owned guard.sh that the policy runs and the credential list it reads.
# Every sudo command is printed first and runs only after you say yes; DRY only prints them.
#######################################
MANAGED_DIR=/etc/claude-code
managed_steps() {   # managed_steps <runner> — the commands, each passed to <runner>
  local src="$RENDER/etc/claude-code/managed-settings.json" d="$MANAGED_DIR"
  "$1" install -d -o root -g root -m 755 "$d" "$d/hooks" "$d/managed-settings.d"
  "$1" install -o root -g root -m 644 "$src" "$d/managed-settings.d/50-ws-kit.json"
  "$1" install -o root -g root -m 755 "$FILES/.claude/hooks/guard.sh" "$d/hooks/guard.sh"
  "$1" install -o root -g root -m 644 "$FILES/.local/lib/ws-credential-paths.txt" "$d/ws-credential-paths.txt"
  if (( MCP_ALLOW )); then "$1" install -o root -g root -m 644 "$RENDER/55-ws-mcp-allow.json" "$d/managed-settings.d/55-ws-mcp-allow.json"; fi
}
install_managed() {
  local r
  show_cmd() { printf '  sudo'; printf ' %q' "$@"; printf '\n'; }
  run_cmd() { show_cmd "$@"; sudo "$@"; }
  jq -e 'type == "object"' "$RENDER/etc/claude-code/managed-settings.json" >/dev/null 2>&1 \
    || die "files/etc/claude-code/managed-settings.json is missing or not valid JSON"
  log "Managed policy (root, $MANAGED_DIR)"
  if (( MCP_ALLOW )); then
    mcp_allowlist "$MCP_FILE" "$HOME" "$HOME/.config/ws-mcp/allow-extra.json" > "$RENDER/55-ws-mcp-allow.json" \
      || die "could not generate the MCP allow list"
    printf '  MCP allow list (55-ws-mcp-allow.json): every other MCP server will be blocked, the claude.ai connectors\n'
    printf '  and plugin servers included, unless ~/.config/ws-mcp/allow-extra.json lists them:\n'
    jq -c '.allowedMcpServers[]' "$RENDER/55-ws-mcp-allow.json" | sed 's/^/    /'
  fi
  [[ -f "$MANAGED_DIR/managed-settings.json" ]] \
    && printf '  kept    %s (not the kit'"'"'s: Claude Code merges the drop-in after it)\n' "$MANAGED_DIR/managed-settings.json"
  printf '  These commands will run:\n'; managed_steps show_cmd
  if (( DRY )); then log "Dry run: nothing was run."; return 0; fi
  [[ -t 0 ]] || die "--managed asks before it runs sudo: run it in a terminal"
  read -rp "Run them with sudo? [y/N] " r
  [[ "$r" =~ ^[yY]([eE][sS])?$ ]] || { log "Nothing changed."; return 0; }
  managed_steps run_cmd || die "a sudo command failed: check $MANAGED_DIR"
  log "Done. Restart Claude; /status shows the managed source and claude doctor lists anything it rejected."
  log "After each kit update that changes guard.sh, run bash install.sh --managed again."
}
if (( MANAGED )); then install_managed; exit 0; fi

migrate_names
migrate_profiles
log "Files ($([[ $DRY -eq 1 ]] && echo 'dry run' || echo "backup: ${BACKUP_DIR/#"$HOME"/\~}"))"
while IFS= read -r rel; do apply_file "$rel"; done < <(manifest_files "$FILES")
ensure_bashrc
(( DRY )) || rotate_backups

# Git gate: the kit's hooks (secrets, message, push to main) only run if git looks for them in
# ~/.config/git/hooks. Set only if there is no other value: it does not override yours. --no-git-hooks skips it.
if (( GITHOOKS )); then
  log "Git gate"
  hp_current="$(git config --global --get core.hooksPath 2>/dev/null || true)"
  if [[ "$hp_current" == "$HOME/.config/git/hooks" ]]; then printf '  same    core.hooksPath\n'
  elif [[ -z "$hp_current" ]]; then
    printf '  new     core.hooksPath → ~/.config/git/hooks\n'
    (( DRY )) || git config --global core.hooksPath "$HOME/.config/git/hooks"
  else printf '  skipped core.hooksPath already points to %s (not changed)\n' "$hp_current"; fi
fi

# TPM and the tmux plugins at the commits of plugins.lock (WS-SEC-016), not TPM's install_plugins (branch tip): a plugin
# that cannot be put at its commit is left out of ~/.tmux/plugins and reported; the install goes on.
if (( PLUGINS )); then
  log "tmux plugins (pinned by commit in ~/.config/tmux-claude/plugins.lock)"
  if (( DRY )); then
    awk '!/^[[:space:]]*#/ && NF >= 3 { printf "  check   %s %s\n", $1, substr($3, 1, 12) }' \
      "$FILES/.config/tmux-claude/plugins.lock"
  elif ! WS_PLUGINS_LOCK="$FILES/.config/tmux-claude/plugins.lock" \
         bash "$FILES/.local/bin/ws-plugins" apply </dev/null | sed 's/^/  /'; then
    warn "A tmux plugin is not at its pinned commit (see above): ws-plugins verify; tmux runs without it."
  fi
fi

if (( MCP )) && [[ -s "$MCP_FILE" ]]; then
  log "User MCP servers (checked against mcp-servers.lock.json)"
  command -v claude >/dev/null || die "Claude Code is missing: curl -fsSL https://claude.ai/install.sh -o /tmp/ci.sh, review it and bash /tmp/ci.sh"
  [[ -s "$MCP_LOCK" ]] || die "files/mcp-servers.lock.json is missing: no MCP server is registered without its lock"
  while IFS= read -r name; do
    # Lock first: anything the lock does not vouch for is skipped, never registered on trust.
    if ! mcp_verify "$name"; then continue; fi
    # A server with a "jail" object is registered through ws-mcp-jail (ADR-024); "jail": false keeps its reason.
    want="$(mcp_want "$MCP_FILE" "$name" "$HOME")"
    if [[ "$(jq -r --arg n "$name" '.[$n].jail | type' "$MCP_FILE")" == object ]] && ! command -v bwrap >/dev/null; then
      warn "MCP $name runs in ws-mcp-jail, which needs bubblewrap (sudo apt-get install bubblewrap): it will not start"
    elif [[ "$(jq -r --arg n "$name" '.[$n].jail' "$MCP_FILE")" == false ]]; then
      printf '  note    %s is not jailed: %s\n' "$name" "$(jq -r --arg n "$name" '.[$n].jailOptOut // "no reason given"' "$MCP_FILE" | cut -c1-90)"
    fi
    if [[ "$(jq -r --arg n "$name" '(.[$n].type // "stdio") + " " + (.[$n].keepalive | tostring)' "$MCP_FILE")" == "stdio false" ]]; then
      printf '  note    %s is not kept alive (keepalive: false): if it exits, /mcp → Reconnect\n' "$name"
    fi
    have="$(mcp_registered "$name")"
    if [[ -n "$have" ]]; then
      if mcp_same "$have" "$want"; then printf '  same    %s\n' "$name"; continue; fi
      # Refresh on request; always when the registration is the unpinned npx form an earlier kit used, or the same
      # server without the kit's current wrappers (ws-mcp-keepalive, ws-mcp-jail): what runs inside does not change.
      if mcp_same "$(mcp_unwrap <<<"$have")" "$(mcp_unwrap <<<"$want")"; then
        printf '  changed %s (same server, registered again with the wrappers of mcp-servers.json)\n' "$name"
        (( DRY )) || { claude mcp remove "$name" --scope user </dev/null >/dev/null 2>&1 || true
                     claude mcp add-json "$name" "$want" --scope user </dev/null >/dev/null; }
      elif (( MCP_REFRESH )) \
         || [[ "$(jq -r '.command // ""' <<<"$have")" == npx && "$(jq -r '.command' <<<"$want")" != npx ]]; then
        printf '  changed %s (re-registered from mcp-servers.json)\n' "$name"
        (( DRY )) || { claude mcp remove "$name" --scope user </dev/null >/dev/null 2>&1 || true
                     claude mcp add-json "$name" "$want" --scope user </dev/null >/dev/null; }
      else printf '  differs %s (registered by hand? bash install.sh --mcp-refresh replaces it)\n' "$name"; fi
    elif claude mcp get "$name" </dev/null >/dev/null 2>&1; then
      printf '  same    %s (registered in another scope)\n' "$name"
    else
      printf '  new     %s\n' "$name"
      (( DRY )) || claude mcp add-json "$name" "$want" --scope user </dev/null >/dev/null
    fi
  done < <(jq -r 'keys[]' "$MCP_FILE")
fi

# Custom profiles (ADR-021) keep their own .claude.json: give them the kit's setup links and MCP definitions again.
if (( ! DRY )) && [[ -x "$HOME/.local/bin/ws-profile" ]] && compgen -G "$HOME/.config/ws-profiles/*/profile.conf" >/dev/null; then
  log "Profiles (kit setup and MCP servers)"
  for f in "$HOME"/.config/ws-profiles/*/profile.conf; do
    n="${f%/profile.conf}"; n="${n##*/}"
    printf '  profile %s\n' "$n"
    "$HOME/.local/bin/ws-profile" setup "$n" | sed 's/^/  /' || warn "ws-profile setup $n did not finish: run it again"
  done
fi
# The managed copy of the guard is not updated by a normal install (it needs sudo): say so when it is stale.
if [[ -f "$MANAGED_DIR/hooks/guard.sh" ]] && ! cmp -s "$MANAGED_DIR/hooks/guard.sh" "$FILES/.claude/hooks/guard.sh"; then
  warn "$MANAGED_DIR/hooks/guard.sh is older than the kit's: run bash install.sh --managed"
fi
if [[ -f "$KIT/files/windows/.wslconfig" ]]; then
  log "Windows: compare files/windows/.wslconfig with %UserProfile%\\.wslconfig by hand (it is not applied automatically)"
fi
if (( DRY )); then log "Dry run: nothing was written."
elif (( MIGRATED )); then
  log "Done. Names changed: save your work and restart tmux (tmux kill-server, then open it again); the tabs come back."
  log "When nothing calls the old names any more: bash install.sh --remove-shims"
  if (( HANDLER_STALE )); then
    warn "The Windows handler of ws-claude:// could not be updated: clicking a notification will not jump to its tab."
    warn "In that .ps1, accept ws-claude://focus/N and call tmux-goto (see windows/ws-claude-focus.ps1)."
  fi
else log "Done. Reload: tmux source-file ~/.tmux.conf; then restart Claude in every tab (tmux-claude-restart --all): a running Claude keeps the old settings or loses the sandbox exclusions"; fi
