#!/usr/bin/env bash
#
# tests/gate-secret-scan.sh — the git gate's secret scan is mandatory (WS-SEC-004), in a temporary HOME and repo:
# without gitleaks a commit is blocked with the install command, ws.gate.allowNoGitleaks lets it through and logs it,
# a gitleaks finding blocks, a clean scan passes, and `ws-gate bypasses` lists repositories where the gate does not
# run in full (local core.hooksPath, ws.gate.skip, ws.gate.allowNoGitleaks).
#
# Usage: bash tests/gate-secret-scan.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"; unset XDG_STATE_HOME XDG_CONFIG_HOME REPOS
mkdir -p "$HOME/.local/bin" "$HOME/.config/git"
cp "$ROOT/files/home/.local/bin/ws-gate" "$HOME/.local/bin/"; cp -r "$ROOT/files/home/.config/git/hooks" "$HOME/.config/git/"
git config --global user.name ci; git config --global user.email ci@example.invalid; git config --global init.defaultBranch main
git config --global core.hooksPath "$HOME/.config/git/hooks"

# A PATH with what the gate and git need, and no gitleaks, shellcheck, ruff or other optional tool.
NB="$T/nogl"; mkdir -p "$NB"
for c in bash sh env git cat grep sed awk stat date mkdir head tail find sort cut jq dirname basename rm mktemp tr wc ln \
         printf id uname xargs; do p="$(command -v "$c")" && [[ "$p" == /* ]] && ln -sf "$p" "$NB/$c"; done
WB="$T/withgl"; mkdir -p "$WB"; cp -a "$NB/." "$WB/"
printf '#!/bin/sh\n[ -f "$GL_RESULT" ] && exit "$(cat "$GL_RESULT")"; exit 0\n' > "$WB/gitleaks"; chmod 755 "$WB/gitleaks"
export GL_RESULT="$T/gl-result"

R="$T/repo"; git init -q "$R"
commit() { echo "$RANDOM" >> "$R/f.txt"; git -C "$R" add f.txt; PATH="$1" git -C "$R" commit -qm "chore: change" 2>"$T/err"; }

echo "1) gitleaks missing"
check "the commit is blocked" not commit "$NB"
check "  and the message gives ws-tools install base" grep -q 'ws-tools install base' "$T/err"
check "  and names the per-repo opt-out" grep -q 'ws.gate.allowNoGitleaks' "$T/err"
git -C "$R" reset -q
git -C "$R" config ws.gate.allowNoGitleaks true
check "ws.gate.allowNoGitleaks lets it through" commit "$NB"
check "  with a warning" grep -q 'secrets were NOT checked' "$T/err"
check "  and the opt-out is logged" grep -q "allowNoGitleaks" "$HOME/.local/state/ws-gate/opt-outs.log"
git -C "$R" config --unset ws.gate.allowNoGitleaks
git -C "$R" config ws.gate.skip lint,size
check "ws.gate.skip cannot switch the secret scan off" not commit "$NB"
git -C "$R" reset -q; git -C "$R" config --unset ws.gate.skip

echo "2) gitleaks present"
echo 1 > "$GL_RESULT"
check "a finding blocks the commit" not commit "$WB"
check "  with the details command" grep -q 'gitleaks protect --staged' "$T/err"
git -C "$R" reset -q; echo 0 > "$GL_RESULT"
check "a clean scan passes" commit "$WB"

echo "3) ws-gate bypasses"
mkdir -p "$T/code"; for n in clean husky skipper nogl; do git init -q "$T/code/$n"; done
git -C "$T/code/husky" config core.hooksPath .husky
git -C "$T/code/skipper" config ws.gate.skip osv
git -C "$T/code/nogl" config ws.gate.allowNoGitleaks true
out="$(PATH="$NB" bash "$HOME/.local/bin/ws-gate" bypasses "$T/code")"; rc=$?
check "exit 1 when a repository bypasses the gate" test "$rc" -eq 1
check "lists the local core.hooksPath" grep -q 'husky.*local core.hooksPath=.husky' <<<"$out"
check "lists ws.gate.skip" grep -q 'skipper.*ws.gate.skip=osv' <<<"$out"
check "lists ws.gate.allowNoGitleaks" grep -q 'nogl.*allowNoGitleaks' <<<"$out"
check "does not list a clean repository" not grep -q '/clean' <<<"$out"
check "exit 0 when none does" bash -c "PATH='$NB' bash '$HOME/.local/bin/ws-gate' bypasses '$T/code/clean'"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
