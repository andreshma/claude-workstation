#!/usr/bin/env bash
#
# tests/hooks-prompt-screen.sh — tests of the prompt secret screen (files/home/.claude/hooks/prompt-screen.sh) in a
# temporary HOME: prompts with secrets are blocked (and never echoed back), #allow-secret passes and is logged,
# ordinary prompts about code and credentials pass, and without ws-redact or jq the screen lets prompts through
# with one warning. Prints the false-positive rate it measured on the benign prompts.
# Fixture secrets are fake and built at run time, so this file holds no secret shapes.
# Usage: bash tests/hooks-prompt-screen.sh
set -uo pipefail
export LC_ALL=C.UTF-8
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$root/files/home/.claude/hooks/prompt-screen.sh"
H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
mkdir -p "$H/.claude/hooks" "$H/run"
printf '#!/bin/bash\ncat >/dev/null; printf "%%s|%%s\\n" "$1" "$2" >> "%s/audit.log"\n' "$H" > "$H/.claude/hooks/audit.sh"
chmod +x "$H/.claude/hooks/audit.sh"
ok=0; bad=0
pass() { ok=$((ok + 1)); }
fail() { bad=$((bad + 1)); printf '  FAIL  %s\n' "$1"; }
# screen <prompt> [redact] — the hook's JSON answer (empty when the prompt passes).
screen() {
  jq -nc --arg p "$1" '{prompt: $p, session_id: "s", hook_event_name: "UserPromptSubmit"}' |
    HOME="$H" XDG_RUNTIME_DIR="$H/run" WS_REDACT="${2:-$root/files/home/.local/bin/ws-redact}" bash "$HOOK" 2>/dev/null
}
r() { printf '%s' "$1" | rev; }   # fixtures are stored reversed so no secret shape appears in this file
gh="$(r 'hgfedcba9876543210ZYXWVUTSRQPONMLKJIHG_phg')"
aws="$(r 'ELPMAXE7NNDOFSOIAIKA')"
pw="$(r 'tiK7#s3gnaR')"

blocked=0; nb=0
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  nb=$((nb + 1)); out="$(screen "$p")"
  if [[ "$(jq -r '.decision // empty' <<<"$out")" == block ]]; then
    blocked=$((blocked + 1))
    jq -e '.hookSpecificOutput.suppressOriginalPrompt == true' <<<"$out" >/dev/null && pass || fail "block without suppressOriginalPrompt: $p"
    for s in "$gh" "$aws" "$pw"; do grep -qF -- "$s" <<<"$out" && fail "the block message repeats the secret"; done
  else
    fail "not blocked: $p"
  fi
done <<EOF
clone it with this token: $gh
export AWS_ACCESS_KEY_ID=$aws and run the deploy
connect to postgres://admin:$pw@db.internal:5432/app
the password=$pw does not work on the staging box
here is the config: {"client_secret": "$pw"}
Authorization: Bearer $(r 'ybuR0987654321zyxwvutsrqp')
EOF
(( blocked == nb )) && pass || fail "blocked $blocked of $nb prompts with secrets"
out="$(screen "$(printf 'first line\nsecond with token=%s\nthird' "$pw")")"
grep -q 'line 2' <<<"$out" && pass || fail "the message names the line ($out)"

out="$(screen "#allow-secret use password=$pw for the demo")"
[[ -z "$out" ]] && pass || fail "#allow-secret must pass ($out)"
grep -q '^secret-allowed|' "$H/audit.log" && pass || fail "#allow-secret is logged"
grep -q '^secret-blocked|' "$H/audit.log" && pass || fail "a block is logged"
grep -qF -- "$pw" "$H/audit.log" && fail "the audit log must never hold the secret" || pass

fp=0; nc=0; fps=()
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  nc=$((nc + 1)); out="$(screen "$p")"
  [[ -n "$out" ]] && { fp=$((fp + 1)); fps+=("$p"); }
done <<'EOF'
fix the login bug in auth.py
I have a basic question about bearer tokens and OAuth
set api_key = os.environ["OPENAI_KEY"] in config.py
read the password from Key Vault: password = ${DB_PASSWORD}
the password: it fails when the field is empty
rotate the token every 90 days and document it in the runbook
why does az account get-access-token fail with AADSTS50076?
use Authorization: Bearer $TOKEN in the curl example
add a test where password=secret is rejected as too weak
token: abc
the secret is to cache the client
configure client_secret=<your-secret> in the template
replace the connectionstring with {{ .Values.db }}
explica por qué falla el token de GitHub en el pipeline
the regex for sig= in SAS URLs is wrong
api-key header missing in the request to /v1/messages
EOF
(( fp == 0 )) && pass || fail "false positives: ${fps[*]}"

# Without ws-redact: passes, warns once per Claude process.
out="$(screen "password=$pw" /nonexistent/ws-redact)"
grep -q 'not screened' <<<"$out" && pass || fail "a missing ws-redact warns ($out)"
out="$(screen "password=$pw" /nonexistent/ws-redact)"
[[ -z "$out" ]] && pass || fail "the warning is shown only once"

printf 'prompt-screen: blocked %d/%d prompts with secrets · false positives %d/%d\n' "$blocked" "$nb" "$fp" "$nc"
printf 'hooks-prompt-screen: %d ok, %d failed\n' "$ok" "$bad"
(( bad == 0 ))
