#!/usr/bin/env bash
#
# tests/gate-commit-msg.sh — the git gate's commit-message step (ADR-023): Conventional Commits and no
# Co-authored-by in real repositories; throwaway repositories (under the temp dir AND without any remote) skip only
# the format and lint checks, saying so once, while secrets and Co-authored-by still apply and a push re-checks every
# message; a commit made from a Claude Code session carries «Agent-Session: <profile>/<session>» (and «Agent:» under
# an agent identity), a forged trailer is replaced, and a commit from a plain shell carries nothing (WS-AI-026).
# Everything runs in a temporary HOME with temporary repositories; nothing is pushed anywhere but a local bare repo.
#
# Usage: bash tests/gate-commit-msg.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T="$(realpath "$T")"
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

case "$T/" in /tmp/*|/var/tmp/*) ;; *) echo "skip: the temp dir ($T) is not under /tmp or /var/tmp"; exit 0 ;; esac
# A plain shell: none of the variables Claude Code sets in the commands it starts.
unset CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID CLAUDECODE WS_AGENT WS_PROFILE CLAUDE_CONFIG_DIR WS_GATE_TEMP_ROOTS
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"; unset XDG_STATE_HOME XDG_CONFIG_HOME REPOS
mkdir -p "$HOME/.local/bin" "$HOME/.config/git"
cp "$ROOT/files/home/.local/bin/ws-gate" "$HOME/.local/bin/"; cp -r "$ROOT/files/home/.config/git/hooks" "$HOME/.config/git/"
git config --global user.name ci; git config --global user.email ci@example.invalid; git config --global init.defaultBranch main
git config --global core.hooksPath "$HOME/.config/git/hooks"
# A fake gitleaks that passes unless $GL_RESULT says otherwise, and a fake shellcheck that always fails (lint).
B="$T/bin"; mkdir -p "$B"
printf '#!/bin/sh\n[ -f "$GL_RESULT" ] && exit "$(cat "$GL_RESULT")"; exit 0\n' > "$B/gitleaks"
printf '#!/bin/sh\necho "SC2086 fake finding"; exit 1\n' > "$B/shellcheck"
chmod 755 "$B/gitleaks" "$B/shellcheck"
export GL_RESULT="$T/gl-result" PATH="$B:$PATH"

# commit <repo> <message> [file] — stages a change and commits it; stderr goes to $T/err.
commit() {
  local r="$1" m="$2" f="${3:-f.txt}"
  echo "$RANDOM" >> "$r/$f"; git -C "$r" add "$f"; git -C "$r" commit -q -m "$m" 2>"$T/err"
}
body() { git -C "$1" log -1 --format=%B; }

echo "1) a throwaway repository (under the temp dir, no remote)"
W="$T/scratch"; git init -q "$W"
check "a non-conventional message is accepted" commit "$W" "v1"
check "  and the reason is printed" grep -q 'throwaway repository' "$T/err"
commit "$W" "v2"
check "  only once per repository" not grep -q 'throwaway repository' "$T/err"
check "lint is skipped there too" commit "$W" "v3" x.sh
check "Co-authored-by is still refused" not commit "$W" "$(printf 'v4\n\nCo-authored-by: x <x@example.invalid>')"
git -C "$W" reset -q
echo 1 > "$GL_RESULT"
check "a secret finding still blocks" not commit "$W" "v5"
git -C "$W" reset -q; rm -f "$GL_RESULT"
check "a forbidden file still blocks" not commit "$W" "v6" .env
git -C "$W" reset -q

echo "2) never a throwaway: a remote, or outside the temp roots"
R="$T/withremote"; git init -q "$R"; git -C "$R" remote add origin "$T/bare.git"
check "a repository with a remote enforces Conventional Commits" not commit "$R" "v1"
check "  with the format hint" grep -q 'Conventional Commits' "$T/err"
git -C "$R" reset -q
check "  and lint" not commit "$R" "chore: add script" x.sh
git -C "$R" reset -q
O="$T/outside"; git init -q "$O"
check "outside the temp roots (narrowed for the test) it is enforced" \
  bash -c "export WS_GATE_TEMP_ROOTS='$T/only-here'; echo 1 >> '$O/f'; git -C '$O' add f; ! git -C '$O' commit -q -m v1"
git -C "$O" reset -q
check "a temp root outside /tmp and /var/tmp is ignored (it cannot widen the rule)" \
  bash -c "export WS_GATE_TEMP_ROOTS='/home:/:/usr/tmp'; echo 1 >> '$O/f'; git -C '$O' add f; ! git -C '$O' commit -q -m v1"
git -C "$O" reset -q
G="$T/wtsrc"; git init -q "$G"; commit "$G" "chore: init" >/dev/null 2>&1; git -C "$G" remote add origin "$T/bare.git"
git -C "$G" worktree add -q "$T/wt" -b side 2>/dev/null
check "a worktree of a repository with a remote is not a throwaway" not commit "$T/wt" "v1"
check "a conventional message passes in a real repository" commit "$R" "feat(gate): add a check"

echo "3) a push from a repository under the temp dir re-checks every message"
git init -q --bare "$T/bare.git"
P="$T/pushme"; git init -q "$P"; commit "$P" "chore: base"; commit "$P" "wip"; git -C "$P" branch -q -M feat
git -C "$P" remote add origin "$T/bare.git"
check "the push is blocked by the non-conventional commit" not git -C "$P" push -q origin feat
git -C "$P" push origin feat 2>"$T/err" >/dev/null
check "  and the commit is named" grep -q 'every pushed message is checked' "$T/err"
git -C "$P" commit -q --amend -m "fix: real message" 2>/dev/null
check "after rewording, the push passes" git -C "$P" push -q origin feat

echo "4) the Agent-Session trailer (WS-AI-026)"
A="$T/agentrepo"; git init -q "$A"; git -C "$A" remote add origin "$T/bare.git"
commit "$A" "feat: from a plain shell"
check "a commit from a plain shell carries no agent trailer" not grep -qE '^(Agent-Session|Agent):' <(body "$A")
CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=0b4f2c1e-1111-4222-8333-944445555666 WS_PROFILE=personal \
  commit "$A" "feat: from a Claude tab"
check "a commit from a Claude session carries Agent-Session: <profile>/<session>" \
  grep -qx 'Agent-Session: personal/0b4f2c1e-1111-4222-8333-944445555666' <(body "$A")
check "  and no Agent trailer without an agent identity" not grep -q '^Agent:' <(body "$A")
check "  and never Co-authored-by" not grep -qi '^co-authored-by:' <(body "$A")
check "  the subject is untouched (Conventional Commits still holds)" test "$(git -C "$A" log -1 --format=%s)" = "feat: from a Claude tab"
CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=s-2 WS_AGENT=deployer CLAUDE_CONFIG_DIR="$HOME/.claude-profiles/client1" \
  commit "$A" "$(printf 'fix: forged trailer\n\nAgent-Session: work/fake')"
check "under an agent identity it adds Agent: <WS_AGENT>" grep -qx 'Agent: deployer' <(body "$A")
check "the profile comes from CLAUDE_CONFIG_DIR when WS_PROFILE is unset" grep -qx 'Agent-Session: client1/s-2' <(body "$A")
check "  and a forged Agent-Session trailer is replaced, not kept" not grep -q 'work/fake' <(body "$A")
CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID='bad id;rm' commit "$A" "chore: odd id"
check "an unexpected session id is recorded as unknown" grep -qx 'Agent-Session: work/unknown' <(body "$A")
check "a refused message gets no trailer and no commit" \
  bash -c "! CLAUDE_CODE_CHILD_SESSION=1 git -C '$A' commit -q --allow-empty -m 'bad message' 2>/dev/null"
git -C "$A" config ws.gate.agentTrailer false
CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=s-3 commit "$A" "chore: opted out"
check "ws.gate.agentTrailer=false leaves it out" not grep -q '^Agent-Session:' <(body "$A")
check "  and the opt-out is logged" grep -q 'agentTrailer' "$HOME/.local/state/ws-gate/opt-outs.log"

echo "5) ws.gate.skip=yaml: only yamllint is skipped (a repo whose YAML is a dialect checked by its own CI)"
Y="$T/yamlrepo"; git init -q "$Y"; git -C "$Y" remote add origin "$T/bare.git"
printf '#!/bin/sh\necho "syntax error: mapping values are not allowed here"; exit 1\n' > "$B/yamllint"; chmod 755 "$B/yamllint"
check "a YAML file yamllint rejects blocks the commit" not commit "$Y" "chore: add data" data.yaml
git -C "$Y" config ws.gate.skip yaml
check "  and passes with ws.gate.skip=yaml" commit "$Y" "chore: add data" data.yaml
check "  while a shell script is still linted (shellcheck finding blocks)" not commit "$Y" "chore: add script" run.sh
rm -f "$B/yamllint"

REAL_SC="$(PATH="${PATH#"$B:"}" command -v shellcheck || true)"
[[ -n "$REAL_SC" ]] && check "shellcheck ws-gate" "$REAL_SC" -S warning "$ROOT/files/home/.local/bin/ws-gate"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
