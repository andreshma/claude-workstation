#!/usr/bin/env bash
#
# tests/backup-encryption.sh — light backups encrypted by default and Windows-side copies that expire (WS-SEC-013),
# in a temporary HOME: with only the cloud key the backup is .age and opens with it, with no key it is made in clear
# with a warning and logged UNENCRYPTED, ws-restore-lite --test opens an encrypted one, and the expiry pass deletes
# old copies whose original is gone while keeping current ones, the newest tmux save and last.txt. ws-restore-lite
# --test reports a backup without conversations instead of exiting silently. The Windows-side mirrors (ws-backup,
# tmux-backup) are in clear without a key and encrypted per file with one, clear copies are sealed, the copy stays
# incremental, ws-restore-lite --mirror restores old clear and new encrypted mirrors, and expiry handles .age copies.
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

echo "4) ws-restore-lite --test on a backup without conversations"
mkdir -p "$T/noproj/.local/share/tmux/resurrect" "$T/noproj/inventory"
printf 'window\t0\n' > "$T/noproj/.local/share/tmux/resurrect/last"; echo vim > "$T/noproj/inventory/apt-manual.txt"
tar -C "$T/noproj" -cf - .local inventory | gzip > "$T/claude-lite-noproj.tar.gz"
bash "$B/ws-restore-lite" --test "$T/claude-lite-noproj.tar.gz" > "$T/np.out" 2>&1; rc=$?
check "it says why it fails (no silent exit under set -e)" grep -q 'FAIL.*contains no conversations' "$T/np.out"
check "  it still checks the rest of the backup" grep -q 'saved tabs' "$T/np.out"
check "  and gives a verdict with exit 1" bash -c "grep -q '1 failed' '$T/np.out' && test $rc -eq 1"

echo "5) the Windows-side mirrors (ws-backup, tmux-backup)"
M="$T/mw"; mkdir -p "$M" "$HOME/.claude/audit"; echo '{"ev":"start"}' > "$HOME/.claude/audit/2026-01-01.jsonl"
mkdir -p "$HOME/.local/lib"; cp "$ROOT/files/home/.local/lib/ws-mirror.sh" "$HOME/.local/lib/"
for f in 2026-01-01T10 2026-01-02T10; do echo "window $f" > "$HOME/.local/share/tmux/resurrect/tmux_resurrect_$f.txt"; done
ln -sf "$HOME/.local/share/tmux/resurrect/tmux_resurrect_2026-01-02T10.txt" "$HOME/.local/share/tmux/resurrect/last"
mirror() { WS_BACKUP_WINHOME="$M" bash "$B/ws-backup" --now; }
tbackup() { WS_BACKUP_WINHOME="$M" WS_TMUX_BACKUP_NO_CHAIN=1 bash "$B/tmux-backup"; }
mv "$HOME/.config/ws-backup" "$T/keys.off"; mkdir -p "$HOME/.config/ws-backup"
mirror
check "without a key the conversation mirror is in clear (as before)" test -f "$M/.claude-wsl-backup/projects/-repo/c1.jsonl"
check "  and the state says UNENCRYPTED" grep -q 'claude-wsl-backup UNENCRYPTED' "$HOME/.local/state/ws-backup-mirror.state"
check "an old clear mirror restores with --mirror" bash -c "bash '$B/ws-restore-lite' --mirror '$M/.claude-wsl-backup/projects' --to '$T/r0' && cmp '$T/r0/projects/-repo/c1.jsonl' '$HOME/.claude/projects/-repo/c1.jsonl'"
rm -rf "$HOME/.config/ws-backup"; mv "$T/keys.off" "$HOME/.config/ws-backup"
if command -v age >/dev/null && [[ -s "$HOME/.config/ws-backup/cloud-recipient" ]]; then
  mirror
  check "with the key the next run encrypts (WS-SEC-013)" test -f "$M/.claude-wsl-backup/projects/-repo/c1.jsonl.age"
  check "  the clear copy is removed" not test -e "$M/.claude-wsl-backup/projects/-repo/c1.jsonl"
  check "  no clear file is left anywhere in the mirror" bash -c "! find '$M/.claude-wsl-backup' -type f ! -name '*.age' ! -name '.*' | grep -q ."
  check "  the audit log is mirrored too" test -f "$M/.claude-wsl-backup/audit/2026-01-01.jsonl.age"
  check "  the copy opens with the cloud key" bash -c "age -d -i '$T/cloud.key' '$M/.claude-wsl-backup/projects/-repo/c1.jsonl.age' | cmp - '$HOME/.claude/projects/-repo/c1.jsonl'"
  check "  and keeps the original's mtime" test "$(stat -c %Y "$M/.claude-wsl-backup/projects/-repo/c1.jsonl.age")" -eq "$(stat -c %Y "$HOME/.claude/projects/-repo/c1.jsonl")"
  check "  the state says encrypted" bash -c "tail -1 '$HOME/.local/state/ws-backup-mirror.state' | grep -q ' encrypted$'"
  echo orphan > "$M/.claude-wsl-backup/projects/-repo/left.jsonl"; rm -f "$M/.claude-wsl-backup/.mode"
  mirror
  check "a clear copy left by an earlier version is sealed in place" bash -c "test -f '$M/.claude-wsl-backup/projects/-repo/left.jsonl.age' && ! test -e '$M/.claude-wsl-backup/projects/-repo/left.jsonl'"
  i1="$(stat -c %i "$M/.claude-wsl-backup/projects/-repo/c1.jsonl.age")"; mirror
  check "an unchanged conversation is not encrypted again (incremental)" test "$(stat -c %i "$M/.claude-wsl-backup/projects/-repo/c1.jsonl.age")" = "$i1"
  echo '{"type":"assistant"}' >> "$HOME/.claude/projects/-repo/c1.jsonl"; touch -d '+1 minute' "$HOME/.claude/projects/-repo/c1.jsonl"; mirror
  check "a conversation that grew is encrypted again" bash -c "age -d -i '$T/cloud.key' '$M/.claude-wsl-backup/projects/-repo/c1.jsonl.age' | grep -q assistant"
  check "the 15-minute limit still applies without --now" bash -c "touch '$M/.claude-wsl-backup/.last'; echo x >> '$HOME/.claude/projects/-repo/c1.jsonl'; touch -d '+2 minutes' '$HOME/.claude/projects/-repo/c1.jsonl'; WS_BACKUP_WINHOME='$M' bash '$B/ws-backup'; ! age -d -i '$T/cloud.key' '$M/.claude-wsl-backup/projects/-repo/c1.jsonl.age' | grep -qx x"
  tbackup
  check "tmux-backup encrypts the tmux saves" bash -c "test -f '$M/.tmux-resurrect-backup/tmux_resurrect_2026-01-01T10.txt.age' && test -f '$M/.tmux-resurrect-backup/last.txt.age'"
  check "  last.txt is the save last points to" bash -c "age -d -i '$T/cloud.key' '$M/.tmux-resurrect-backup/last.txt.age' | grep -q 2026-01-02T10"
  check "  and nothing tmux saved is left in clear" bash -c "! find '$M/.tmux-resurrect-backup' -type f -name '*.txt' | grep -q ."
  check "ws-restore-lite --mirror decrypts a conversation folder" bash -c "bash '$B/ws-restore-lite' --mirror '$M/.claude-wsl-backup/projects/-repo' --to '$T/r1' --identity '$T/cloud.key' && grep -q assistant '$T/r1/-repo/c1.jsonl'"
  check "  and a tmux save, with the key from Credential Manager" bash -c "bash '$B/ws-restore-lite' --mirror '$M/.tmux-resurrect-backup' --to '$T/r2' && grep -q 2026-01-02T10 '$T/r2/.tmux-resurrect-backup/last.txt'"
  check "  without overwriting what is already there" bash -c "echo mine > '$T/r1/-repo/c1.jsonl'; bash '$B/ws-restore-lite' --mirror '$M/.claude-wsl-backup/projects/-repo' --to '$T/r1' --identity '$T/cloud.key'; grep -qx mine '$T/r1/-repo/c1.jsonl'"
  age-keygen -o "$T/other.key" 2>/dev/null
  check "  a key it was not encrypted to fails with exit 1" not bash "$B/ws-restore-lite" --mirror "$M/.claude-wsl-backup/projects/-repo" --to "$T/r3" --identity "$T/other.key"
  rm -f "$HOME/.claude/projects/-repo/left.jsonl"; touch -d '40 days ago' "$M/.claude-wsl-backup/projects/-repo/left.jsonl.age"
  for d in 50 3; do f="$M/.tmux-resurrect-backup/tmux_resurrect_old$d.txt.age"; echo x > "$f"; touch -d "$d days ago" "$f"; done
  WS_BACKUP_WINHOME="$M" bash "$B/ws-backup-lite" --prune-copies
  check "expiry removes an old encrypted copy whose original is gone" not test -e "$M/.claude-wsl-backup/projects/-repo/left.jsonl.age"
  check "  and keeps an encrypted copy whose original exists" test -e "$M/.claude-wsl-backup/projects/-repo/c1.jsonl.age"
  check "  old encrypted tmux saves expire, recent ones stay" bash -c "! test -e '$M/.tmux-resurrect-backup/tmux_resurrect_old50.txt.age' && test -e '$M/.tmux-resurrect-backup/tmux_resurrect_old3.txt.age'"
  check "  last.txt.age stays" test -e "$M/.tmux-resurrect-backup/last.txt.age"
else skip "age is not installed: the encrypted mirror cases"; fi

printf '\n%d ok, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
