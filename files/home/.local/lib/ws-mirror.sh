# shellcheck shell=bash
#
# ws-mirror.sh — the Windows-side mirrors (%UserProfile%\.claude-wsl-backup and .tmux-resurrect-backup) encrypted with
# age (WS-SEC-013). Sourced by ws-backup (conversations and audit log) and tmux-backup (tmux saves).
# Each file is mirrored on its own as <name>.age, encrypted to the same keys as the light backup
# (~/.config/ws-backup/age-recipients and the ws-backup-cloud key cloud-recipient), so the copy stays incremental:
# a file is encrypted again only when the original is newer than its copy (the copy takes the original's mtime).
# Without a key, or without age, the mirror stays in clear (what earlier versions did) and the state file says
# UNENCRYPTED, which ws-audit reports. When a key appears, the clear copies already there are sealed in place.
# Restore: ws-restore-lite --mirror <path> (old clear copies and new .age ones alike). Expiry: ws-backup-lite.
# Usage: source ~/.local/lib/ws-mirror.sh; mirror_init; mirror_tree <src dir> <mirror dir>; mirror_done <mirror dir>

WS_MIRROR_CONF="${WS_MIRROR_CONF:-$HOME/.config/ws-backup}"
WS_MIRROR_STATE="${WS_MIRROR_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/ws-backup-mirror.state}"
MIRROR_AGE=() MIRROR_WHY=""

#######################################
# Chooses the mode: encrypted when a recipient file exists and age is installed, clear otherwise.
# Globals: MIRROR_AGE (age -R arguments, empty in clear), MIRROR_WHY (why it is in clear).
#######################################
mirror_init() {
  local r
  MIRROR_AGE=() MIRROR_WHY=""
  for r in "$WS_MIRROR_CONF/age-recipients" "$WS_MIRROR_CONF/cloud-recipient"; do
    [[ -s "$r" ]] && MIRROR_AGE+=(-R "$r")
  done
  if (( ${#MIRROR_AGE[@]} == 0 )); then MIRROR_WHY="no recipient (ws-backup-cloud setup creates one)"
  elif ! command -v age >/dev/null 2>&1; then
    MIRROR_AGE=(); MIRROR_WHY="age is not installed (sudo apt-get install age)"
  fi
}

#######################################
# Mirrors one file: <dst>.age when encrypting (the clear <dst> of an earlier run is removed), else <dst> in clear.
# Only when the original is newer than the copy. The copy is written next to it and renamed (never half a file).
# Arguments: source file, destination path without .age. Returns: 1 if the copy failed.
#######################################
mirror_file() {
  local src="$1" dst="$2" out part
  if (( ${#MIRROR_AGE[@]} )); then out="$dst.age"; else out="$dst"; fi
  [[ "$src" -nt "$out" ]] || return 0
  mkdir -p "$(dirname "$out")" || return 1
  part="$(dirname "$out")/.$(basename "$out").partial"
  if (( ${#MIRROR_AGE[@]} )); then age "${MIRROR_AGE[@]}" -o "$part" "$src" 2>/dev/null
  else cp -fL "$src" "$part" 2>/dev/null; fi || { rm -f "$part"; return 1; }
  touch -r "$src" "$part" && mv -f "$part" "$out" || { rm -f "$part"; return 1; }
  (( ${#MIRROR_AGE[@]} )) && rm -f "$dst"
  return 0
}

#######################################
# Mirrors every file under a folder, keeping relative paths. Arguments: source folder, mirror folder.
# Outputs: nothing. Returns: 1 if any file failed.
#######################################
mirror_tree() {
  local src="${1%/}" dst="${2%/}" f rc=0
  [[ -d "$src" ]] || return 0
  while IFS= read -r -d '' f; do
    mirror_file "$f" "$dst/${f#"$src/"}" || rc=1
  done < <(find "$src" -type f ! -name '*.lock' -print0 2>/dev/null)
  return "$rc"
}

#######################################
# Encrypts in place the clear copies left in a mirror folder (by an earlier version or a period without a key), with
# their mtime, so expiry and restore treat them like the others. Runs only when encrypting; dot files stay.
# Arguments: mirror folder.
#######################################
mirror_seal() {
  local d="${1%/}" f part
  (( ${#MIRROR_AGE[@]} )) && [[ -d "$d" ]] || return 0
  while IFS= read -r -d '' f; do
    part="$(dirname "$f")/.$(basename "$f").age.partial"
    if age "${MIRROR_AGE[@]}" -o "$part" "$f" 2>/dev/null && touch -r "$f" "$part" && mv -f "$part" "$f.age"; then
      rm -f "$f"
    else rm -f "$part"; fi
  done < <(find "$d" -type f ! -name '*.age' ! -name '.*' -print0 2>/dev/null)
}

#######################################
# Records the mode of a mirror run: «<date> <mirror dir> encrypted» or «… UNENCRYPTED: <why>» (ws-audit reads the
# last line), and seals the clear copies when the mode turns to encrypted. Arguments: mirror folder.
#######################################
mirror_done() {
  local d="${1%/}" mode="encrypted" prev
  (( ${#MIRROR_AGE[@]} )) || mode="UNENCRYPTED: $MIRROR_WHY"
  prev="$(cat "$d/.mode" 2>/dev/null)"
  [[ "$mode" == encrypted && "$prev" != encrypted ]] && mirror_seal "$d"
  printf '%s\n' "${mode%%:*}" > "$d/.mode" 2>/dev/null
  mkdir -p "$(dirname "$WS_MIRROR_STATE")" 2>/dev/null
  printf '%s %s %s\n' "$(date -Is)" "$d" "$mode" >> "$WS_MIRROR_STATE" 2>/dev/null
  # Keeps the state file short: the last 200 runs.
  if (( $(wc -l < "$WS_MIRROR_STATE" 2>/dev/null || echo 0) > 400 )); then
    tail -n 200 "$WS_MIRROR_STATE" > "$WS_MIRROR_STATE.tmp" 2>/dev/null \
      && mv -f "$WS_MIRROR_STATE.tmp" "$WS_MIRROR_STATE"
  fi
}
