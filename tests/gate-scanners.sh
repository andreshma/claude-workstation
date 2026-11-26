#!/usr/bin/env bash
#
# tests/gate-scanners.sh — osv-scanner and checkov in the git gate's pre-push (WS-SEC-004), in a temporary HOME and
# repo with simulated scanners: each is mandatory only when the push has files it applies to (a lock file or manifest;
# Terraform, Bicep, a Dockerfile, a Kubernetes manifest or a CI workflow), a missing one blocks with the ws-tools
# install command, ws.gate.allowNoOsv and ws.gate.allowNoCheckov let the push through with a warning and a line in
# the opt-out log, `ws-gate bypasses` lists them, a push without such files needs neither, and ws.gate.skip still
# skips a check. Also checks that `ws-tools install gate` names the three scanners.
#
# Usage: bash tests/gate-scanners.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"; unset XDG_STATE_HOME XDG_CONFIG_HOME REPOS
mkdir -p "$HOME/.local/bin"
GATE="$ROOT/files/home/.local/bin/ws-gate"
git config --global user.name ci; git config --global user.email ci@example.invalid; git config --global init.defaultBranch main

# A PATH with what the gate needs and no scanner; another with simulated osv-scanner and checkov.
NB="$T/none"; mkdir -p "$NB"
for c in bash sh env git cat grep sed awk stat date mkdir head tail find sort cut jq dirname basename rm mktemp tr wc ln \
         printf id uname xargs; do p="$(command -v "$c")" && [[ "$p" == /* ]] && ln -sf "$p" "$NB/$c"; done
SB="$T/scanners"; mkdir -p "$SB"; cp -a "$NB/." "$SB/"
printf '#!/bin/sh\necho "{\\"results\\":[]}"\n' > "$SB/osv-scanner"
printf '#!/bin/sh\necho "Passed checks: 1, Failed checks: 0"\n' > "$SB/checkov"
chmod 755 "$SB/osv-scanner" "$SB/checkov"

R="$T/repo"; git init -q "$R"; echo base > "$R/README.md"; git -C "$R" add README.md; git -C "$R" commit -qm "chore: base"
BASE="$(git -C "$R" rev-parse HEAD)"; git -C "$R" switch -qc feat
# push_with <PATH> <file>... — commits the files on feat and runs the pre-push hook for feat against the base commit.
push_with() {
  local path="$1" f; shift
  git -C "$R" reset -q --hard "$BASE"
  for f in "$@"; do mkdir -p "$(dirname "$R/$f")"; cat > "$R/$f"; git -C "$R" add -- "$f"; done < /dev/null
  [[ -n "${CONTENT:-}" ]] && for f in "$@"; do printf '%s\n' "$CONTENT" > "$R/$f"; git -C "$R" add -- "$f"; done
  git -C "$R" commit -qm "chore: change" --no-verify
  (cd "$R" && printf 'refs/heads/feat %s refs/heads/feat %s\n' "$(git rev-parse HEAD)" "$BASE" \
     | PATH="$path" bash "$GATE" pre-push origin) 2>"$T/err"
}
LOG="$HOME/.local/state/ws-gate/opt-outs.log"

echo "1) a push with no file a scanner applies to"
check "needs neither osv-scanner nor checkov" push_with "$NB" docs/notes.md
CONTENT=$'name: x\nvalue: 1' check "  nor a plain YAML file (checkov only notes it)" push_with "$NB" config/app.yaml

echo "2) osv-scanner"
check "a push that changes a lock file is blocked without osv-scanner" not push_with "$NB" package-lock.json
check "  the message gives ws-tools install osv-scanner" grep -q 'ws-tools install osv-scanner' "$T/err"
check "  and names the per-repo opt-out" grep -q 'ws.gate.allowNoOsv' "$T/err"
check "a manifest counts too (go.mod)" not push_with "$NB" go.mod
check "with osv-scanner installed it passes" push_with "$SB" package-lock.json
git -C "$R" config ws.gate.allowNoOsv true
check "ws.gate.allowNoOsv lets it through" push_with "$NB" package-lock.json
check "  with a warning" grep -q 'dependencies of this push were NOT checked' "$T/err"
check "  and a line in the opt-out log" grep -q 'allowNoOsv' "$LOG"
check "ws-gate bypasses lists it" bash -c "PATH='$NB' bash '$GATE' bypasses '$T' | grep -q 'ws.gate.allowNoOsv=true'"
git -C "$R" config --unset ws.gate.allowNoOsv
git -C "$R" config ws.gate.skip osv
check "ws.gate.skip=osv still skips the check" push_with "$NB" package-lock.json
git -C "$R" config --unset ws.gate.skip

echo "3) checkov"
check "Terraform without checkov is blocked" not push_with "$NB" infra/main.tf
check "  the message gives ws-tools install checkov" grep -q 'ws-tools install checkov' "$T/err"
check "  and names the per-repo opt-out" grep -q 'ws.gate.allowNoCheckov' "$T/err"
check "a Dockerfile is blocked too" not push_with "$NB" Dockerfile
check "a Bicep file is blocked too" not push_with "$NB" main.bicep
CONTENT=$'on: push\njobs: {}' check "a CI workflow is blocked too" not push_with "$NB" .github/workflows/ci.yml
CONTENT=$'apiVersion: v1\nkind: Pod\nmetadata:\n  name: x' check "a Kubernetes manifest is blocked too" not push_with "$NB" k8s/pod.yaml
check "with checkov installed it passes" push_with "$SB" infra/main.tf
git -C "$R" config ws.gate.allowNoCheckov true
check "ws.gate.allowNoCheckov lets it through" push_with "$NB" infra/main.tf
check "  with a warning and a line in the opt-out log" bash -c "grep -q 'NOT checked' '$T/err' && grep -q allowNoCheckov '$LOG'"
check "ws-gate bypasses lists it" bash -c "PATH='$NB' bash '$GATE' bypasses '$T' | grep -q 'ws.gate.allowNoCheckov=true'"
git -C "$R" config --unset ws.gate.allowNoCheckov

echo "4) ws-tools"
check "ws-tools install gate is a named set with gitleaks, osv-scanner and checkov" \
  bash -c "grep -qE '^[[:space:]]+gate\) .*gitleaks.*osv-scanner.*checkov' '$ROOT/files/home/.local/bin/ws-tools'"
check "osv-scanner and checkov are pinned in the tools lock" \
  bash -c "grep -qE '^osv-scanner[[:space:]]+v[0-9]' '$ROOT/files/home/.local/lib/ws-tools.lock' && grep -qE '^checkov[[:space:]]+[0-9]' '$ROOT/files/home/.local/lib/ws-tools.lock'"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
