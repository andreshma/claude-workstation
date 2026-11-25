# shellcheck shell=bash
# migrate.sh — moves an installation made before 3.0 (Spanish names) to the English names. Sourced by install.sh,
# which calls migrate_names before copying the kit's files. It is idempotent: on a machine that is already
# migrated, or was never installed, it does nothing. The table of names is renames.tsv.
#
#   data  your settings and data are MOVED to the new name; if the new name already exists nothing is touched
#         and a warning is printed, so nothing is ever overwritten.
#   shim  an old command or hook is set aside and replaced by a wrapper that calls the new name. Tabs opened
#         before the update keep working until they are restarted; the wrappers are removed with
#         `bash install.sh --remove-shims` once nothing calls the old names.
#   drop  an old kit file nobody calls any more is set aside.
#   retired  a command replaced after 3.0: wrapper like shim, but it does not count as a migration.
# "Set aside" means moved to ~/.local/share/ws-kit/pre-english.<date>/ with its path, never deleted.

SHIM_MARK='# ws-kit shim: deprecated name, safe to delete'
MIGRATED=0
HANDLER_STALE=0   # 1: a Windows notification handler exists and still expects the old address

#######################################
# Prints the rows of renames.tsv of one kind as "old<TAB>new".
# Arguments: kind (data | shim | drop).
#######################################
rename_rows() { awk -F'\t' -v k="$1" '$1 == k { print $2 "\t" $3 }' "$KIT/renames.tsv"; }

#######################################
# Moves a kit file out of the way, keeping its relative path under the backup folder.
# Arguments: path relative to $HOME.
#######################################
set_aside() {
  local rel="$1" dest="$HOME/.local/share/ws-kit/pre-english.$STAMP"
  (( DRY )) && return 0
  mkdir -p "$dest/$(dirname "$rel")" && mv -f "$HOME/$rel" "$dest/$rel"
}

#######################################
# Applies renames.tsv to $HOME. Uses DRY and STAMP from install.sh.
#######################################
migrate_names() {
  local old new header=0
  say() { (( header )) || { log "Names from before 3.0 → English (renames.tsv)"; header=1; }; printf '  %s\n' "$*"; }

  # Background services started by the old version keep running the old code: the Telegram service under the old
  # pid file name, and the OTel collector, which would recreate the old data folder on its next write. Both are
  # stopped BEFORE anything is moved; tmux brings the new ones up within a minute (ws-telegram ensure, ws-otel ensure).
  local pidf pid name
  for name in ws-telegram ws-otel; do
    if [[ "$name" == ws-telegram ]]; then pidf="$HOME/.local/state/ws-telegram/servicio.pid"
    else
      # The collector's pid file is per user, not under $HOME: only touch it when $HOME is this user's real home
      # (an install into another HOME, as the tests do, must never stop the real collector).
      pidf="${XDG_RUNTIME_DIR:-/tmp}/ws-otel-$(id -u)/pid"
      [[ -d "$HOME/.local/share/ws-telemetria" && "$HOME" == "$(getent passwd "$(id -u)" | cut -d: -f6)" ]] || continue
    fi
    [[ -f "$pidf" ]] || continue
    pid="$(cat "$pidf" 2>/dev/null)"
    say "stopped the old $name service (it restarts by itself)"; MIGRATED=1
    if (( ! DRY )); then
      if [[ "$pid" =~ ^[0-9]+$ ]] && grep -qa "$name" "/proc/$pid/cmdline" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
      rm -f "$pidf" 2>/dev/null || true
    fi
  done

  # In a dry run nothing is moved, so a row that lives inside a folder renamed by an earlier row is looked up where
  # it still is: PENDING maps "new folder" → "old folder" for the moves that were only announced.
  local -A PENDING=()
  at() {   # path as renames.tsv names it → where it is on disk right now
    local p="$1" k
    for k in "${!PENDING[@]}"; do
      if [[ "$p" == "$k" || "$p" == "$k"/* ]]; then p="${PENDING[$k]}${p#"$k"}"; break; fi
    done
    printf '%s' "$HOME/$p"
  }

  while IFS=$'\t' read -r old new; do
    [[ -e "$(at "$old")" || -L "$(at "$old")" ]] || continue
    # An old folder with no file in it is only a leftover (a sandbox mount point, a service that recreated it):
    # it is removed instead of being reported as a conflict.
    if [[ -d "$HOME/$old" && ! -L "$HOME/$old" && -e "$HOME/$new" && -z "$(find "$HOME/$old" ! -type d -print -quit 2>/dev/null)" ]]; then
      say "removed $old (empty leftover; $new is in use)"
      (( DRY )) || find "$HOME/$old" -depth -type d -empty -delete 2>/dev/null || true
      continue
    fi
    if [[ -e "$(at "$new")" || -L "$(at "$new")" ]]; then
      warn "both ~/$old and ~/$new exist: left as they are, merge them by hand"; continue
    fi
    say "moved   $old → $new"; MIGRATED=1
    if (( DRY )); then PENDING[$new]="$(p="$(at "$old")"; printf '%s' "${p#"$HOME"/}")"
    else mkdir -p "$(dirname "$HOME/$new")" && mv "$HOME/$old" "$HOME/$new"; fi
  done < <(rename_rows data)

  # retired: a command replaced after 3.0. It gets the same wrapper, but it is not a sign of an installation that
  # comes from the Spanish names (no language default, no «restart tmux» note).
  while IFS=$'\t' read -r kind old new; do
    [[ -f "$(at "$old")" ]] || continue
    grep -qxF "$SHIM_MARK" "$(at "$old")" 2>/dev/null && continue    # already a wrapper
    say "shim    $old → $new"; [[ "$kind" == shim ]] && MIGRATED=1
    set_aside "$old"
    (( DRY )) && continue
    printf '%s\n' '#!/usr/bin/env bash' "$SHIM_MARK" \
      "echo \"$(basename "$old") was renamed to $(basename "$new"); its options were renamed too (see docs/USAGE.md).\" >&2" \
      "exec \"\$HOME/$new\" \"\$@\"" > "$HOME/$old"
    chmod 755 "$HOME/$old"
  done < <(awk -F'\t' '$1 == "shim" || $1 == "retired"' "$KIT/renames.tsv")

  while IFS=$'\t' read -r old new; do
    [[ -f "$(at "$old")" ]] || continue
    say "dropped $old (now $new)"; MIGRATED=1
    set_aside "$old"
  done < <(rename_rows drop)

  # ~/.bashrc sourced the accounts file by its old name. Its backup goes to this run's backup folder (backup_file).
  if grep -q 'tmux-claude/cuentas\.sh' "$HOME/.bashrc" 2>/dev/null; then
    say "changed .bashrc: cuentas.sh → accounts.sh"; MIGRATED=1
    (( DRY )) || { backup_file .bashrc; sed -i 's#tmux-claude/cuentas\.sh#tmux-claude/accounts.sh#g' "$HOME/.bashrc"; }
  fi

  # Profiles generated by the old tmux-nivel: they are rebuilt on every use under ~/.config/claude-levels.
  if [[ -d "$HOME/.config/claude-niveles" ]]; then
    say "dropped .config/claude-niveles (generated profiles; rebuilt in .config/claude-levels)"; MIGRATED=1
    (( DRY )) || { mkdir -p "$HOME/.local/share/ws-kit/pre-english.$STAMP/.config" \
                   && mv "$HOME/.config/claude-niveles" "$HOME/.local/share/ws-kit/pre-english.$STAMP/.config/"; }
  fi

  # Windows side: the notification handler registered for ws-claude:// (a .ps1 outside WSL) only knows the old
  # address and the old command. It is patched in place, with a backup next to it (<file>.bak.<date>: the file lives
  # on the Windows side, so its backup stays there and not in ~/.local/share/ws-kit); if it cannot be updated,
  # install.sh says so in its closing note (HANDLER_STALE).
  local reg ps f
  if command -v reg.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    reg="$(reg.exe query 'HKCU\Software\Classes\ws-claude\shell\open\command' /ve 2>/dev/null | tr -d '\r' || true)"
    ps="$(grep -oiE '[a-z]:\\[^"]*\.ps1' <<<"$reg" | head -1 || true)"
    f=""; if [[ -n "$ps" ]]; then f="$(wslpath "$ps" 2>/dev/null || true)"; fi
    if [[ -n "$ps" && ! -f "$f" ]]; then HANDLER_STALE=1    # registered, but its file is not reachable from WSL
    elif [[ -n "$f" ]] && grep -q 'tmux-foco' "$f"; then
      say "changed Windows handler $ps (accepts ws-claude://focus, calls tmux-goto)"; MIGRATED=1
      if (( ! DRY )); then
        if ! { cp -p "$f" "$f.bak.$STAMP" \
               && sed -i -e 's#ws-claude://foco/(#ws-claude://(?:focus|foco)/(#' -e 's#tmux-foco#tmux-goto#g' "$f"; }; then
          # shellcheck disable=SC2034  # read by install.sh
          HANDLER_STALE=1
        fi
      fi
    fi
  fi

  # An installation that comes from the Spanish names keeps recognising prompts typed in Spanish.
  if (( MIGRATED )) && [[ ! -e "$HOME/.config/tmux-claude/lang" ]]; then
    say "new     .config/tmux-claude/lang = es (change it with ws-lang en)"
    (( DRY )) || { mkdir -p "$HOME/.config/tmux-claude" && echo es > "$HOME/.config/tmux-claude/lang"; }
  fi
  return 0
}

#######################################
# Deletes the wrappers left under the old names (only files that carry the wrapper mark).
#######################################
remove_shims() {
  local old new n=0
  while IFS=$'\t' read -r old new; do
    if [[ -f "$HOME/$old" ]] && grep -qxF "$SHIM_MARK" "$HOME/$old"; then
      printf '  removed %s\n' "$old"; n=$((n + 1)); (( DRY )) || rm -f "$HOME/$old"
    fi
  done < <(awk -F'\t' -v OFS='\t' '$1 == "shim" || $1 == "retired" { print $2, $3 }' "$KIT/renames.tsv")
  (( n )) || printf '  none left\n'
}
