#!/usr/bin/env bash
#
# tests/run.sh — tests of the kit in temporary HOMEs (does not touch your machine):
# export captures the manifest, blocks secrets, install is idempotent, --dry-run does not write,
# a modified file is backed up (under ~/.local/share/ws-kit/backup.<date>/) before it is replaced, the old
# side-by-side *.bak.<date> copies are moved away by --prune-backups, .bashrc gets no duplicate lines and an installation
# made with the Spanish names (before 3.0) is migrated without losing or overwriting anything.
# If files/ exists (a real export), it also validates its JSON and lints its scripts.
#
# Usage: bash tests/run.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

# The installer looks in the Windows registry for the notification handler and patches that file (migrate.sh).
# No test may query the real registry or reach a real Windows file, whether the machine has reg.exe (WSL) or not:
# a reg.exe that answers nothing goes first in PATH for the whole suite. The handler tests put their own in front.
NOWIN="$T/nowin"; mkdir -p "$NOWIN"; printf '#!/bin/sh\nexit 0\n' > "$NOWIN/reg.exe"; chmod 755 "$NOWIN/reg.exe"
export PATH="$NOWIN:$PATH"

# Isolated working kit (copy of the repo without the real files/)
K="$T/kit"; mkdir -p "$K/tests"; cp "$ROOT"/{lib.sh,migrate.sh,renames.tsv,export.sh,install.sh,manifest.txt,secrets-allow.txt} "$K/"

# Source HOME with a sample configuration
A="$T/a"; mkdir -p "$A/.claude/hooks" "$A/.claude/agents" "$A/.local/bin" "$A/.config/tmux-claude"
echo 'set -g mouse on' > "$A/.tmux.conf"
echo '{"model":"opusplan","hooks":{}}' > "$A/.claude/settings.json"
printf '#!/usr/bin/env bash\n# detection pattern (not a secret): SharedAccessSignature=\necho ok\n' > "$A/.claude/hooks/guard.sh"; chmod 755 "$A/.claude/hooks/guard.sh"
printf '#!/usr/bin/env bash\n# another hook with the same pattern, NOT allowed\n' > "$A/.claude/hooks/other.sh"
echo 'old' > "$A/.claude/hooks/guard.sh.bak.20260101"
echo '---' > "$A/.claude/agents/explorer.md"
printf '#!/usr/bin/env bash\n' > "$A/.local/bin/tmux-dash"; chmod 755 "$A/.local/bin/tmux-dash"
printf 'tw() { :; }\n# paths: /mnt/c/Users/nobody.x/repos %s/code\n' "$A" > "$A/.config/tmux-claude/functions.sh"
echo '{"mcpServers":{"recall":{"type":"stdio","command":"/x/python.exe","args":["-m","recall","mcp"]}}}' > "$A/.claude.json"

echo "1) export"
HOME="$A" WIN_USER=nobody.x bash "$K/export.sh" > "$T/exp.log" 2>&1
check "exports the files of the manifest" test -f "$K/files/home/.claude/settings.json"
check "exports directories (hooks, agents)" test -f "$K/files/home/.claude/hooks/guard.sh"
check "keeps execute permissions" test -x "$K/files/home/.claude/hooks/guard.sh"
check "skips *.bak.* backups" not test -e "$K/files/home/.claude/hooks/guard.sh.bak.20260101"
check "exports the MCP servers" test "$(jq -r 'keys[0]' "$K/files/mcp-servers.json")" = recall

check "guard.sh (in secrets-allow) does not block the export" grep -q 'No secrets' "$T/exp.log"
check "turns personal paths into a template" grep -q '@WINHOME@/repos @HOME@/code' "$K/files/home/.config/tmux-claude/functions.sh"
check "leaves no Windows user in the kit" not grep -rq 'nobody\.x' "$K/files/home"

echo "2) secret blocking"
cp -r "$K" "$T/kit2"; echo 'AccountKey=abcdefghijklmnopqrstuvwxyz0123456789==' >> "$A/.tmux.conf"
check "export fails with a secret" not env HOME="$A" WIN_USER=nobody.x bash "$T/kit2/export.sh"
check "and leaves no half-written files/" not test -d "$T/kit2/files"
sed -i '/AccountKey/d' "$A/.tmux.conf"
echo '# SharedAccessSignature=' >> "$A/.claude/hooks/other.sh"
check "a pattern outside secrets-allow does block" not env HOME="$A" WIN_USER=nobody.x bash "$T/kit2/export.sh"
sed -i '/SharedAccessSignature/d' "$A/.claude/hooks/other.sh"

echo "3) install on a new machine"
B="$T/b"; mkdir -p "$B"
HOME="$B" WIN_USER=other bash "$K/install.sh" --dry-run --no-plugins --no-mcp > "$T/dry.log" 2>&1
check "--dry-run writes nothing" test -z "$(find "$B" -type f)"
check "--dry-run lists what is new" grep -q 'new     .claude/settings.json' "$T/dry.log"
HOME="$B" WIN_USER=other bash "$K/install.sh" --no-plugins --no-mcp > "$T/i1.log" 2>&1
check "installs the same as the source" diff -q "$A/.claude/settings.json" "$B/.claude/settings.json"
# Simulates a machine where the user is not detected: no WIN_USER and no cmd.exe (outside /mnt/*).
NO_WIN_PATH="$(tr ':' '\n' <<<"$PATH" | grep -v '^/mnt/' | paste -sd:)"
check "no Windows user: refuses with a clear message" bash -c "env -u WIN_USER HOME='$T/c' PATH='$NO_WIN_PATH' bash '$K/install.sh' --dry-run --no-plugins --no-mcp </dev/null 2>&1 | grep -q -- '--win-user'"
check "installs executable scripts" test -x "$B/.claude/hooks/guard.sh"
check "adds lines to .bashrc" grep -qF 'tmux-claude/functions.sh' "$B/.bashrc"
check "templates with the paths of the target machine" grep -qF "/mnt/c/Users/other/repos $B/code" "$B/.config/tmux-claude/functions.sh"
check "REPOS follows the target user" grep -qxF 'export REPOS=/mnt/c/Users/other/source/repos' "$B/.bashrc"

echo "4) idempotency and no overwriting"
HOME="$B" WIN_USER=other bash "$K/install.sh" --no-plugins --no-mcp > "$T/i2.log" 2>&1
check "second install: everything the same" not grep -qE '^  (new|changed|added)' "$T/i2.log"
check ".bashrc without duplicates" test "$(grep -cF 'tmux-claude/functions.sh' "$B/.bashrc")" = 1
echo 'set -g status off' > "$B/.tmux.conf"
HOME="$B" WIN_USER=other bash "$K/install.sh" --no-plugins --no-mcp > "$T/i3.log" 2>&1
check "a changed file is reported" grep -q 'changed .tmux.conf' "$T/i3.log"
check "and backed up before it is replaced, under ~/.local/share/ws-kit/backup.<date>/" grep -qx 'set -g status off' "$B"/.local/share/ws-kit/backup.*/.tmux.conf
check "no backup is left next to the file" not compgen -G "$B/.tmux.conf.bak.*"
check "the header names the backup folder once" test "$(grep -c 'backup: ~/.local/share/ws-kit/backup\.[0-9]*-[0-9]*)$' "$T/i3.log")" = 1
check "an install that changes nothing creates no backup folder" test "$(find "$B/.local/share/ws-kit" -maxdepth 1 -name 'backup.*' | wc -l)" = 1
# Rotation: the newest 10 backup.<date> folders stay; pre-english.<date> and backup.legacy are never deleted.
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do mkdir -p "$B/.local/share/ws-kit/backup.200001$i-000000"; done
mkdir -p "$B/.local/share/ws-kit/pre-english.20000101-000000" "$B/.local/share/ws-kit/backup.legacy"
echo 'set -g status on' > "$B/.tmux.conf"; sleep 1   # the folder is named to the second: this run gets its own
HOME="$B" WIN_USER=other bash "$K/install.sh" --dry-run --no-plugins --no-mcp > "$T/i4.log" 2>&1
check "--dry-run deletes no old backup folder" test "$(find "$B/.local/share/ws-kit" -maxdepth 1 -name 'backup.[0-9]*' | wc -l)" = 13
HOME="$B" WIN_USER=other bash "$K/install.sh" --no-plugins --no-mcp > "$T/i5.log" 2>&1
check "keeps the newest 10 backup folders" test "$(find "$B/.local/share/ws-kit" -maxdepth 1 -name 'backup.[0-9]*' | wc -l)" = 10
check "deletes the oldest and keeps the newest" bash -c "[[ ! -e '$B/.local/share/ws-kit/backup.20000104-000000' && -d '$B/.local/share/ws-kit/backup.20000105-000000' ]] && grep -qx 'set -g status on' '$B'/.local/share/ws-kit/backup.20[1-9]*/.tmux.conf"
check "never deletes pre-english.<date> or backup.legacy" test -d "$B/.local/share/ws-kit/pre-english.20000101-000000" -a -d "$B/.local/share/ws-kit/backup.legacy"
# --prune-backups: the copies earlier versions left next to each file move to backup.legacy; nothing else is touched.
L="$B/.local/share/ws-kit/backup.legacy"
echo one > "$B/.tmux.conf.bak.20260101-101010"; echo two > "$B/.claude/hooks/guard.sh.bak.20260102-101010"
echo three > "$B/.config/tmux-claude/menu-sesion.tmux.bak.20260103-101010"; echo four > "$B/.bashrc.bak.20260104-101010"
echo mine > "$B/notes.txt.bak.20260101-101010"; echo mine > "$B/.config/tmux-claude/own.bak.txt"
before="$(cd "$B" && find . -type f | sort)"
HOME="$B" bash "$K/install.sh" --prune-backups --dry-run > "$T/p0.log" 2>&1
check "--prune-backups --dry-run moves nothing and gives the count" bash -c "[[ \"\$(cd '$B' && find . -type f | sort)\" == \"\$1\" ]] && grep -q '4 backup files would be moved' '$T/p0.log'" _ "$before"
HOME="$B" bash "$K/install.sh" --prune-backups > "$T/p1.log" 2>&1
check "--prune-backups moves the copies of the manifest paths (files and folders)" bash -c "[[ \$(cat '$L/.tmux.conf.20260101-101010') == one && \$(cat '$L/.claude/hooks/guard.sh.20260102-101010') == two ]]"
check "--prune-backups moves the copies of the names used before 3.0 and of .bashrc" bash -c "[[ \$(cat '$L/.config/tmux-claude/menu-sesion.tmux.20260103-101010') == three && \$(cat '$L/.bashrc.20260104-101010') == four ]]"
check "--prune-backups prints the count and leaves none next to the files" bash -c "grep -q '^==> 4 backup files moved' '$T/p1.log' && ! compgen -G '$B/.tmux.conf.bak.*' && ! compgen -G '$B/.claude/hooks/*.bak.*'"
check "--prune-backups leaves files that are not the kit's" bash -c "[[ -f '$B/notes.txt.bak.20260101-101010' && -f '$B/.config/tmux-claude/own.bak.txt' ]]"
HOME="$B" bash "$K/install.sh" --prune-backups > "$T/p2.log" 2>&1
check "--prune-backups again: nothing left to move" grep -q '^==> 0 backup files moved' "$T/p2.log"

echo "5) migration of an installation made with the Spanish names (migrate.sh, renames.tsv)"
MARK='# ws-kit shim: deprecated name, safe to delete'
# snap <home> — every file with its checksum, and every folder: two equal snapshots mean nothing was written.
snap() { ( cd "$1" && find . \( -type f -o -type l \) -print0 | sort -z | xargs -0 -r md5sum; find . -type d | sort ); }
M="$T/m"; mkdir -p "$M/.config/ws-telemetria" "$M/.config/tmux-claude" "$M/.local/bin" "$M/.claude/hooks" "$M/.local/share/ws-telemetria/trazas"
echo 'kit=25' > "$M/.config/ws-telemetria/presupuestos.conf"                    # data in a folder that is renamed too
echo '{"evento":"Stop"}' > "$M/.local/share/ws-telemetria/trazas/2026-01-01.jsonl"
echo '/old/favorite' > "$M/.config/tmux-claude/favoritos"; echo '/new/favorite' > "$M/.config/tmux-claude/favorites"   # both exist
printf '#!/usr/bin/env bash\necho old-nivel\n' > "$M/.local/bin/tmux-nivel"; chmod 755 "$M/.local/bin/tmux-nivel"       # old command
printf '#!/usr/bin/env bash\necho "new-level $*"\n' > "$M/.local/bin/tmux-level"; chmod 755 "$M/.local/bin/tmux-level"
printf '#!/usr/bin/env bash\necho old-trazas\n' > "$M/.claude/hooks/ws-trazas.sh"; chmod 755 "$M/.claude/hooks/ws-trazas.sh"   # old hook
echo '# old menu' > "$M/.config/tmux-claude/menu-sesion.tmux"                    # old kit file nobody calls
printf '%s\n' '# mine' '[ -f ~/.config/tmux-claude/cuentas.sh ] && . ~/.config/tmux-claude/cuentas.sh' > "$M/.bashrc"
before="$(snap "$M")"
HOME="$M" WIN_USER=other bash "$K/install.sh" --dry-run --no-plugins --no-mcp > "$T/m0.log" 2>&1
check "--dry-run migrates nothing" test "$(snap "$M")" = "$before"
check "--dry-run lists what it would move" grep -q 'moved   .config/ws-telemetria → .config/ws-telemetry' "$T/m0.log"
HOME="$M" WIN_USER=other bash "$K/install.sh" --no-plugins --no-mcp > "$T/m1.log" 2>&1
check "data: the folder and the file inside it move to the new names" test "$(cat "$M/.config/ws-telemetry/budgets.conf" 2>/dev/null)" = 'kit=25'
check "data: nothing is left under the old name" not test -e "$M/.config/ws-telemetria"
check "data: the traces keep their content, untouched" test "$(cat "$M/.local/share/ws-telemetry/traces/2026-01-01.jsonl" 2>/dev/null)" = '{"evento":"Stop"}'
check "data: when both names exist it warns" grep -q 'both ~/.config/tmux-claude/favoritos and ~/.config/tmux-claude/favorites exist' "$T/m1.log"
check "data: and leaves both as they were" test "$(cat "$M/.config/tmux-claude/favoritos" "$M/.config/tmux-claude/favorites" | paste -sd' ')" = '/old/favorite /new/favorite'
check "old command: a wrapper is left under the old name" grep -qxF "$MARK" "$M/.local/bin/tmux-nivel"
check "old command: the wrapper runs the new one with its arguments" test "$(HOME="$M" "$M/.local/bin/tmux-nivel" a 'b c' 2>/dev/null)" = 'new-level a b c'
check "old command: the wrapper says the name changed" bash -c "HOME='$M' '$M/.local/bin/tmux-nivel' 2>&1 >/dev/null | grep -q 'tmux-nivel was renamed to tmux-level'"
check "old hook: gets its wrapper too" grep -qxF "$MARK" "$M/.claude/hooks/ws-trazas.sh"
check "old kit files are set aside, not deleted (commands)" grep -qx 'echo old-nivel' "$M"/.local/share/ws-kit/pre-english.*/.local/bin/tmux-nivel
check "old kit files are set aside, not deleted (menus)" grep -qx '# old menu' "$M"/.local/share/ws-kit/pre-english.*/.config/tmux-claude/menu-sesion.tmux
check "and the old menu is gone from its folder" not test -e "$M/.config/tmux-claude/menu-sesion.tmux"
check ".bashrc: the old line now loads accounts.sh" grep -qxF '[ -f ~/.config/tmux-claude/accounts.sh ] && . ~/.config/tmux-claude/accounts.sh' "$M/.bashrc"
check ".bashrc: no line with the old name, no duplicate, and a backup" bash -c "! grep -q 'cuentas\.sh' '$M/.bashrc' && [[ \$(grep -c 'accounts\.sh' '$M/.bashrc') == 1 ]] && grep -q 'cuentas\.sh' '$M'/.local/share/ws-kit/backup.*/.bashrc && ! compgen -G '$M/.bashrc.bak.*'"
check "a migrated installation keeps Spanish (lang = es)" test "$(cat "$M/.config/tmux-claude/lang" 2>/dev/null)" = es
check "a new installation does not set the language" not test -e "$B/.config/tmux-claude/lang"
check "and is told to restart tmux only when names changed" bash -c "grep -q 'restart tmux' '$T/m1.log' && ! grep -q 'restart tmux' '$T/i1.log'"
after="$(snap "$M")"
HOME="$M" WIN_USER=other bash "$K/install.sh" --no-plugins --no-mcp > "$T/m2.log" 2>&1
check "second run: nothing left to migrate" not grep -qE '^  (moved|shim|dropped|changed|new|added) ' "$T/m2.log"
check "second run: writes nothing" test "$(snap "$M")" = "$after"
printf '#!/usr/bin/env bash\necho mine\n' > "$M/.local/bin/tmux-foco"; chmod 755 "$M/.local/bin/tmux-foco"   # yours, under an old name
after="$(snap "$M")"
HOME="$M" bash "$K/install.sh" --remove-shims --dry-run > "$T/m3.log" 2>&1
check "--remove-shims --dry-run deletes nothing" test "$(snap "$M")" = "$after"
HOME="$M" bash "$K/install.sh" --remove-shims > "$T/m4.log" 2>&1
check "--remove-shims deletes the wrappers" bash -c "[[ ! -e '$M/.local/bin/tmux-nivel' && ! -e '$M/.claude/hooks/ws-trazas.sh' ]] && grep -q 'removed .local/bin/tmux-nivel' '$T/m4.log'"
check "--remove-shims deletes only wrappers" bash -c "grep -qx 'echo mine' '$M/.local/bin/tmux-foco' && [[ -x '$M/.local/bin/tmux-level' && -f '$M/.config/ws-telemetry/budgets.conf' ]]"
check "--remove-shims: the old files set aside stay" test -f "$(ls "$M"/.local/share/ws-kit/pre-english.*/.local/bin/tmux-nivel)"
HOME="$M" bash "$K/install.sh" --remove-shims > "$T/m5.log" 2>&1
check "--remove-shims again: none left" grep -q 'none left' "$T/m5.log"

# Windows side: the handler registered for ws-claude:// (a .ps1 outside WSL) is patched in place. Simulated with a
# reg.exe that answers like the real one (CRLF lines) and a wslpath that maps the Windows path to a fixture in $T.
WX="$T/win"; PS="$WX/files/h.ps1"; mkdir -p "$WX/reg" "$WX/wsl" "$WX/files"
cat > "$WX/reg/reg.exe" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WX/reg.calls"
printf '\r\n%s\r\n%s\r\n\r\n' 'HKEY_CURRENT_USER\Software\Classes\ws-claude\shell\open\command' \\
  '    (Default)    REG_SZ    powershell.exe -NoProfile -File "C:\Users\x\h.ps1" "%1"'
EOF
cat > "$WX/wsl/wslpath" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$WX/wslpath.calls"
echo "$PS"
EOF
chmod 755 "$WX/reg/reg.exe" "$WX/wsl/wslpath"
# shellcheck disable=SC2016  # PowerShell text, not shell: nothing in it must expand
printf '%s\r\n' 'param([string]$Uri)' \
  'if ($Uri -match '\''^ws-claude://foco/(\d{1,6})/?$'\'') {' \
  '  wsl.exe -e bash -lc "~/.local/bin/tmux-foco $($Matches[1])"' \
  '}' > "$PS"
cp "$PS" "$WX/h.orig"
WIN_PATH="$WX/reg:$WX/wsl:$PATH"
# PATH without any reg.exe (neither the real one nor the simulated ones), as on a machine without Windows.
NO_REG_PATH="$WX/wsl:$(tr ':' '\n' <<<"$PATH" | while IFS= read -r d; do [[ -e "$d/reg.exe" ]] || printf '%s\n' "$d"; done | paste -sd:)"
# accepts <address> — the address matches the expression the handler has right now.
accepts()       { grep -qP -- "$(sed -n "s/.*-match '\([^']*\)'.*/\1/p" "$PS" | tr -d '\r')" <<<"$1"; }
old_address()   { accepts 'ws-claude://foco/12' && ! accepts 'ws-claude://focus/12'; }
both_addresses() { accepts 'ws-claude://focus/12' && accepts 'ws-claude://foco/123456' && ! accepts 'ws-claude://other/12' && ! accepts 'ws-claude://focus/x'; }
crlf_kept()     { [[ "$(wc -l < "$PS")" == 4 ]] && ! grep -qv $'\r$' "$PS"; }
one_backup()    { local b=("$PS".bak.*); [[ ${#b[@]} == 1 ]] && cmp -s "${b[0]}" "$WX/h.orig"; }
looked_up()     { grep -q 'Classes.ws-claude.shell.open.command' "$WX/reg.calls" && grep -qxF 'C:\Users\x\h.ps1' "$WX/wslpath.calls"; }
untouched()     { [[ ! -s "$WX/reg.calls" ]] && cmp -s "$PS" "$WX/h.orig" && [[ "$(snap "$WX/files")" == "$after" ]]; }
H="$T/h"; mkdir -p "$H"
after="$(snap "$WX/files")"
check "handler: the fixture knows only the old address" old_address
HOME="$H" WIN_USER=other PATH="$WIN_PATH" bash "$K/install.sh" --dry-run --no-plugins --no-mcp > "$T/h0.log" 2>&1
check "handler: --dry-run changes nothing and leaves no backup" test "$(snap "$WX/files")" = "$after"
check "handler: --dry-run says what it would change" grep -qF 'changed Windows handler C:\Users\x\h.ps1' "$T/h0.log"
HOME="$H" WIN_USER=other PATH="$WIN_PATH" bash "$K/install.sh" --no-plugins --no-mcp > "$T/h1.log" 2>&1
check "handler: found through the registry key and wslpath" looked_up
check "handler: accepts ws-claude://focus and still ws-claude://foco" both_addresses
check "handler: calls tmux-goto, no longer tmux-foco" bash -c "grep -q '/\.local/bin/tmux-goto ' '$PS' && ! grep -q 'tmux-foco' '$PS'"
check "handler: keeps its CRLF line endings" crlf_kept
check "handler: a backup with the old content is left next to it" one_backup
check "handler: the change is reported" grep -qF 'changed Windows handler C:\Users\x\h.ps1' "$T/h1.log"
after="$(snap "$WX/files")"
HOME="$H" WIN_USER=other PATH="$WIN_PATH" bash "$K/install.sh" --no-plugins --no-mcp > "$T/h2.log" 2>&1
check "handler: a second run changes nothing" test "$(snap "$WX/files")" = "$after"
check "handler: and reports nothing" not grep -q 'Windows handler' "$T/h2.log"
rm -f "$PS".bak.*; cp "$WX/h.orig" "$PS"; : > "$WX/reg.calls"; after="$(snap "$WX/files")"
check "handler: with no reg.exe in PATH the install still succeeds" env HOME="$T/h-noreg" WIN_USER=other PATH="$NO_REG_PATH" bash "$K/install.sh" --no-plugins --no-mcp
check "handler: and then nothing is looked up or touched" untouched
check "handler: that PATH really has no reg.exe" not env PATH="$NO_REG_PATH" bash -c 'command -v reg.exe'
check "the other tests cannot reach the real registry (a silent reg.exe is first in PATH)" test "$(command -v reg.exe)" = "$NOWIN/reg.exe"

if [[ -d "$ROOT/files" ]]; then
  echo "6) real export of the repo"
  for j in "$ROOT/files/home/.claude/settings.json" "$ROOT/files/mcp-servers.json"; do
    [[ -f "$j" ]] && check "valid JSON: ${j#"$ROOT"/}" jq empty "$j"
  done
  if command -v shellcheck >/dev/null; then
    while IFS= read -r s; do check "shellcheck ${s#"$ROOT"/}" shellcheck -S warning "$s"; done < \
      <(grep -rlE '^#!.*(bash|sh)' "$ROOT/files/home" 2>/dev/null)
  fi
fi

echo "7) PreToolUse guard"
check "guard: evasions, false positives and failing closed" bash "$ROOT/tests/guard.sh"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
