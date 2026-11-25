#!/usr/bin/env bash
#
# tests/backup-encryption.sh — light backups encrypted by default and Windows-side copies that expire (WS-SEC-013),
# in a temporary HOME: with only the cloud key the backup is .age and opens with it, with no key it is made in clear
# with a warning and logged UNENCRYPTED, ws-restore-lite --test opens an encrypted one, and the expiry pass deletes
# old copies whose original is gone while keeping current ones, the newest tmux save and last.txt.
#
# Usage: bash tests/backup-encryption.sh      (exit 0 = all OK; the encryption cases need age, else they are skipped)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0 SKIP=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
skip()  { SKIP=$((SKIP+1)); echo "  skip $1"; }
not()   { ! "$@"; }
B="$ROOT/files/home/.local/bin"

export HOME="$T/home" WS_BACKUP_DEST="$T/dest" WS_BACKUP_LOCK="$T/lock" WS_BACKUP_WINHOME="$T/win" WS_BACKUP_MIN_GB=0
mkdir -p "$HOME/.claude/projects/-repo" "$HOME/.local/share/tmux/resurrect" "$HOME/.config/ws-backup" "$T/win" "$T/fb"
printf '{"type":"user"}\n' > "$HOME/.claude/projects/-repo/c1.jsonl"
printf 'window\t0\n' > "$HOME/.local/share/tmux/resurrect/last"
# No inventory commands of the real machine, no Windows: claude, cmd.exe and friends answer nothing.
for c in claude cmd.exe wslvar apt-mark pipx npm cargo az kubectl; do printf '#!/bin/sh\nexit 1\n' > "$T/fb/$c"; done
chmod 755 "$T/fb"/*; export PATH="$T/fb:$PATH"
backup() { bash "$B/ws-backup-lite" --now 2>"$T/err"; }
latest() { find "$WS_BACKUP_DEST" -maxdepth 1 -name 'claude-lite-*' ! -name '*.sha256' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-; }

echo "1) no recipient"
mkdir -p "$T/win/ws-telemetry"; echo "2026-01-01 abc 3 x" > "$T/win/ws-telemetry/audit-anchors.txt"
check "the backup is made" backup
check "  with a copy of the audit anchors (WS-SEC-011)" bash -c "f=\$(find '$WS_BACKUP_DEST' -name 'claude-lite-*' ! -name '*.sha256' | head -1); { zstd -dc \"\$f\" 2>/dev/null || gzip -dc \"\$f\"; } | tar -xOf - inventory/audit-anchors.txt | grep -q '2026-01-01 abc'"
check "  in clear (no .age)" bash -c "[[ \$(find '$WS_BACKUP_DEST' -name 'claude-lite-*.age' | wc -l) -eq 0 ]]"
check "  with a loud warning" grep -q 'UNENCRYPTED backup' "$T/err"
check "  and logged as UNENCRYPTED" grep -q 'UNENCRYPTED' "$HOME/.local/state/ws-backup-lite.log"
rm -f "$WS_BACKUP_DEST"/claude-lite-*

echo "2) the cloud key only (ws-backup-cloud setup)"
if command -v age-keygen >/dev/null && command -v age >/dev/null; then
  age-keygen -o "$T/cloud.key" 2>/dev/null; age-keygen -y "$T/cloud.key" > "$HOME/.config/ws-backup/cloud-recipient"
  check "the backup is encrypted by default" bash -c "backup() { bash '$B/ws-backup-lite' --now 2>/dev/null; }; backup && ls '$WS_BACKUP_DEST'/claude-lite-*.age"
  f="$(latest)"
  check "  it opens with the cloud key and holds the conversations" bash -c "age -d -i '$T/cloud.key' '$f' | zstd -dc 2>/dev/null | tar -t | grep -q 'c1.jsonl' || age -d -i '$T/cloud.key' '$f' | gzip -dc | tar -t | grep -q c1.jsonl"
  check "  and is logged as encrypted" grep -q ' encrypted)' "$HOME/.local/state/ws-backup-lite.log"
  check "ws-restore-lite --test opens it with --identity" bash -c "bash '$B/ws-restore-lite' --test '$f' --identity '$T/cloud.key' | grep -q 'extracts completely'"
  # Without --identity: the cloud key is read from Credential Manager (simulated ws-secret).
  printf '#!/bin/sh\n[ "$1" = get ] && [ "$2" = age-backup ] && cat "%s" && exit 0\nexit 1\n' "$T/cloud.key" > "$T/fb/ws-secret"; chmod 755 "$T/fb/ws-secret"
  check "  and without it, with the key from Credential Manager" bash -c "bash '$B/ws-restore-lite' --test '$f' | grep -q 'extracts completely'"
  check "  leaving no key file behind in the temp folder" bash -c "! grep -rls 'AGE-SECRET-KEY' \"\${TMPDIR:-/tmp}\" --include='tmp.*' 2>/dev/null | grep -q ."
  age-keygen -o "$T/mine.key" 2>/dev/null; age-keygen -y "$T/mine.key" > "$HOME/.config/ws-backup/age-recipients"
  rm -f "$WS_BACKUP_DEST"/claude-lite-*   # same minute stamp: start from an empty destination
  backup 2>/dev/null; f="$(latest)"
  check "with both files it opens with either key" bash -c "age -d -i '$T/mine.key' '$f' >/dev/null && age -d -i '$T/cloud.key' '$f' >/dev/null"
else skip "age is not installed"; fi

echo "3) expiry of the Windows-side copies"
W="$T/win"; mkdir -p "$W/.claude-wsl-backup/projects/-repo" "$W/.claude-wsl-backup/projects/-gone" "$W/.tmux-resurrect-backup"
cp "$HOME/.claude/projects/-repo/c1.jsonl" "$W/.claude-wsl-backup/projects/-repo/c1.jsonl"
echo old > "$W/.claude-wsl-backup/projects/-gone/old.jsonl"; echo recent > "$W/.claude-wsl-backup/projects/-gone/recent.jsonl"
touch -d '40 days ago' "$W/.claude-wsl-backup/projects/-repo/c1.jsonl" "$W/.claude-wsl-backup/projects/-gone/old.jsonl"
for d in 50 45 2; do echo "$d" > "$W/.tmux-resurrect-backup/tmux_resurrect_$d.txt"; touch -d "$d days ago" "$W/.tmux-resurrect-backup/tmux_resurrect_$d.txt"; done
echo last > "$W/.tmux-resurrect-backup/last.txt"; touch -d '90 days ago' "$W/.tmux-resurrect-backup/last.txt"
check "a run with its own destination and no WS_BACKUP_WINHOME prunes nothing" \
  bash -c "env -u WS_BACKUP_WINHOME bash '$B/ws-backup-lite' --prune-copies && test -e '$W/.claude-wsl-backup/projects/-gone/old.jsonl'"
check "the expiry pass runs" bash "$B/ws-backup-lite" --prune-copies
check "an old copy whose original is gone is deleted" not test -e "$W/.claude-wsl-backup/projects/-gone/old.jsonl"
check "a recent copy stays" test -e "$W/.claude-wsl-backup/projects/-gone/recent.jsonl"
check "an old copy whose original still exists stays" test -e "$W/.claude-wsl-backup/projects/-repo/c1.jsonl"
check "old tmux saves are deleted" bash -c "! test -e '$W/.tmux-resurrect-backup/tmux_resurrect_50.txt' && ! test -e '$W/.tmux-resurrect-backup/tmux_resurrect_45.txt'"
check "the recent tmux save and last.txt stay" bash -c "test -e '$W/.tmux-resurrect-backup/tmux_resurrect_2.txt' && test -e '$W/.tmux-resurrect-backup/last.txt'"
for d in 60 70; do echo "$d" > "$W/.tmux-resurrect-backup/tmux_resurrect_$d.txt"; touch -d "$d days ago" "$W/.tmux-resurrect-backup/tmux_resurrect_$d.txt"; done
rm -f "$W/.tmux-resurrect-backup/tmux_resurrect_2.txt"
bash "$B/ws-backup-lite" --prune-copies
check "the newest tmux save stays even when it is old" test -e "$W/.tmux-resurrect-backup/tmux_resurrect_60.txt"
check "WS_BACKUP_COPY_DAYS=0 turns the expiry off" bash -c "WS_BACKUP_COPY_DAYS=0 bash '$B/ws-backup-lite' --prune-copies && test -e '$W/.tmux-resurrect-backup/tmux_resurrect_60.txt'"
check "the expiry is logged" grep -q 'expired' "$HOME/.local/state/ws-backup-lite.log"

printf '\n%d ok, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
