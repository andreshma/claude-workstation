#!/usr/bin/env bash
#
# tests/run.sh — tests of the kit in temporary HOMEs (does not touch your machine):
# export captures the manifest, blocks secrets, install is idempotent, --dry-run does not write,
# a modified file is backed up before it is replaced and .bashrc gets no duplicate lines.
# If files/ exists (a real export), it also validates its JSON and lints its scripts.
#
# Usage: bash tests/run.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

# Isolated working kit (copy of the repo without the real files/)
K="$T/kit"; mkdir -p "$K/tests"; cp "$ROOT"/{lib.sh,export.sh,install.sh,manifest.txt,secrets-allow.txt} "$K/"

# Source HOME with a sample configuration
A="$T/a"; mkdir -p "$A/.claude/hooks" "$A/.claude/agents" "$A/.local/bin" "$A/.config/tmux-claude"
echo 'set -g mouse on' > "$A/.tmux.conf"
echo '{"model":"opusplan","hooks":{}}' > "$A/.claude/settings.json"
printf '#!/usr/bin/env bash\n# detection pattern (not a secret): SharedAccessSignature=\necho ok\n' > "$A/.claude/hooks/guard.sh"; chmod 755 "$A/.claude/hooks/guard.sh"
printf '#!/usr/bin/env bash\n# another hook with the same pattern, NOT allowed\n' > "$A/.claude/hooks/other.sh"
echo 'old' > "$A/.claude/hooks/guard.sh.bak.20260101"
echo '---' > "$A/.claude/agents/explorador.md"
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
SIN_WIN_PATH="$(tr ':' '\n' <<<"$PATH" | grep -v '^/mnt/' | paste -sd:)"
check "no Windows user: refuses with a clear message" bash -c "env -u WIN_USER HOME='$T/c' PATH='$SIN_WIN_PATH' bash '$K/install.sh' --dry-run --no-plugins --no-mcp </dev/null 2>&1 | grep -q -- '--win-user'"
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
check "and backed up before it is replaced" grep -rq 'status off' "$B"/.tmux.conf.bak.*

if [[ -d "$ROOT/files" ]]; then
  echo "5) real export of the repo"
  for j in "$ROOT/files/home/.claude/settings.json" "$ROOT/files/mcp-servers.json"; do
    [[ -f "$j" ]] && check "valid JSON: ${j#"$ROOT"/}" jq empty "$j"
  done
  if command -v shellcheck >/dev/null; then
    while IFS= read -r s; do check "shellcheck ${s#"$ROOT"/}" shellcheck -S warning "$s"; done < \
      <(grep -rlE '^#!.*(bash|sh)' "$ROOT/files/home" 2>/dev/null)
  fi
fi

echo "6) PreToolUse guard"
check "guard: evasions, false positives and failing closed" bash "$ROOT/tests/guard.sh"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
