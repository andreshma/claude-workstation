#!/usr/bin/env bash
#
# tests/menu-escaping.sh — untrusted names never become tmux or shell syntax in the menus (WS-SEC-028). A menu item's
# command is expanded as a format once, then PARSED as tmux commands: a tab named «x";kill-server;"y» or a folder
# named «a'b";touch PWNED;'c» pasted there would run. The menus pass names on as formats instead (##W,
# ##{pane_current_path}, and ##{q:pane_current_path} for a shell argument, which run-shell quotes itself):
#   1) static: no item command of any menu*.tmux carries #W or #{pane_current_path} unescaped, nor a shell argument
#      without q:; titles and labels (rendered, never parsed) may
#   2) live, on a private tmux server (its own socket, never yours) in a folder and a tab with hostile names: one
#      format pass leaves the escaped forms literal, and run-shell's #{q:…} hands the shell the exact path, with
#      nothing executed (skipped where tmux cannot create its socket, e.g. inside Claude Code's sandbox)
#
# Usage: bash tests/menu-escaping.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; T="$(realpath "$T")"
SOCK="$T/s"
trap 'env -u TMUX tmux -S "$SOCK" kill-server 2>/dev/null; rm -rf "$T"' EXIT
PASS=0 FAIL=0 SKIP=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
M="$ROOT/files/home/.config/tmux-claude"

echo "== 1. static"
cat > "$T/scan.py" <<'EOF'
import re, sys
bad = []
for p in sys.argv[1:]:
    for n, line in enumerate(open(p, encoding="utf-8"), 1):
        m = re.match(r'^  ("(?:[^"\\]|\\.)*"|\'[^\']*\') \S+ (.*)$', line)
        if not m:
            continue
        cmd = m.group(2)
        for pat, why in ((r"(?<!#)#W", "#W"), (r"(?<!#)#\{pane_current_path\}", "#{pane_current_path}"),
                         (r"(?<!#)#\{q:", "#{q: expanded by the menu")):
            if re.search(pat, cmd):
                bad.append(f"{p.rsplit('/', 1)[-1]}:{n}: {why}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
EOF
out="$(python3 "$T/scan.py" "$M"/menu*.tmux)"; [[ -n "$out" ]] && printf '%s\n' "$out"
check "no menu command pastes a tab name or a folder path as text" test -z "$out"
check "shell arguments use ##{q:pane_current_path}" grep -q 'tmux-solo new ##{q:pane_current_path}' "$M/menu-claude-level.tmux"

echo "== 2. live"
mkdir -p "$T/w/a'b\";touch PWNED;'c"
if env -u TMUX tmux -S "$SOCK" -f /dev/null new-session -d -s v -n 'x";kill-server;"y' -c "$T/w/a'b\";touch PWNED;'c" "sleep 60" 2>/dev/null; then
  tm() { env -u TMUX tmux -S "$SOCK" "$@"; }
  check "one format pass leaves ##W and ##{…} literal" test "$(tm display -p -t v "##W ##{pane_current_path} ##{q:pane_current_path}")" == '#W #{pane_current_path} #{q:pane_current_path}'
  check "the unescaped form would have pasted the hostile name" bash -c "[[ \"\$(env -u TMUX tmux -S '$SOCK' display -p -t v '#W')\" == *kill-server* ]]"
  tm run-shell -t v "cd '$T' && printf '%s\n' #{q:pane_current_path} > '$T/q.out'"
  check "run-shell's #{q:…} gives the shell the exact path" bash -c "[[ \"\$(cat '$T/q.out')\" == '$T/w/a'\\''b\";touch PWNED;'\\''c' ]]"
  check "…and nothing in the name ran (no file named PWNED anywhere)" bash -c "! find '$T' -name PWNED | grep -q ."
  check "the server is still there (no kill-server from a name)" tm has-session -t v
else
  SKIP=$((SKIP+1)); echo "  skip live checks: tmux cannot create its socket here"
fi

echo
echo "Result: $PASS ok · $FAIL failed · $SKIP skipped"
(( FAIL == 0 ))
