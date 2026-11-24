#!/usr/bin/env bash
#
# guard.sh — deterministic guardrails for Claude Code (PreToolUse hook). Part of the FLOOR of ADR-013: it runs at
# every protection level (completo, normal, solo and puro).
# Blocks with exit 2 (Claude receives the reason and looks for another way) actions against policy:
#   · forced git push (--force, -f, -fu, +refspec) · push to main/master (explicit, refs/heads/… or while on that one)
#   · bypassing the git gate (--no-verify, core.hooksPath, ws.gate.*) · commits with Co-authored-by
#   · download and run (curl|wget … | sh, sh <(curl …)) · reading secrets with ws-secret get
#   · mutating az, kubectl and helm against production (active subscription or context, or the one given in the command)
#   · writing secrets to files (private keys, tokens, AccountKey, SAS)
# Fails CLOSED: if it cannot read the input (no jq or invalid JSON) it blocks, because it does not know what it is
# letting through. To decide, it ignores quoted text (an echo or a grep that mention a forced push are not blocked).
# It is defense in depth, not an absolute control: RBAC and human review still rule.
input="$(cat)"
if ! command -v jq >/dev/null 2>&1 || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$input"; then
  printf 'BLOCKED by policy (guard.sh): could not read the action (jq is missing or the input is not JSON)\n' >&2
  exit 2
fi
tool="$(jq -r '.tool_name // ""' <<<"$input")"
PROD="${GUARD_PROD_REGEX:-prod|prd|produccion}"

# block <reason> — records it in the audit log and blocks the action.
block() {
  "$HOME/.claude/hooks/audit.sh" blocked "$1" <<<"$input" >/dev/null 2>&1
  printf 'BLOCKED by policy (guard.sh): %s\n' "$1" >&2
  exit 2
}

case "$tool" in
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    cwd="$(jq -r '.cwd // ""' <<<"$input")"
    # Without the quoted text: what remains are the words the shell executes.
    sc="$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$cmd")"
    GIT='git([[:space:]]+-[cC][[:space:]]*[^[:space:]]+)*[[:space:]]+'
    if grep -Eq "${GIT}push([[:space:]]|\$)" <<<"$sc"; then
      resto="$(grep -Eo "${GIT}push[^|;&]*" <<<"$sc" | sed -E "s/^${GIT}push//" | tr '\n' ' ')"
      grep -Eq '(^|[[:space:]])(--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)|(^|[[:space:]])\+[^[:space:]]' <<<"$resto" &&
        block "forced git push (use --force-with-lease on your branch, or do it yourself)"
      grep -Eq '(^|[[:space:]:/])(main|master)([[:space:]]|$)' <<<"$resto" &&
        block "direct push to main/master: work on a branch and open a PR"
      # «git push» with no branch (zero or one non-option argument) or with HEAD: pushes the current branch.
      args="$(tr ' ' '\n' <<<"$resto" | grep -Evc '^(-.*)?$')"
      if (( args < 2 )) || grep -Eq '(^|[[:space:]:])HEAD([[:space:]:]|$)' <<<"$resto"; then
        rama="$(git -C "${cwd:-.}" branch --show-current 2>/dev/null)"
        [[ "$rama" == main || "$rama" == master ]] && block "push while on $rama: work on a branch and open a PR"
      fi
    fi
    grep -Eq "${GIT}(commit|push|merge|rebase|am|cherry-pick)[^|;&]*[[:space:]]--no-verify([[:space:]]|\$)" <<<"$sc" &&
      block "--no-verify bypasses the git gate: fix what it flags"
    grep -Eq '(^|[;&|[:space:]])git[[:space:]]' <<<"$sc" && grep -Eqi 'core\.hookspath|ws\.gate\.' <<<"$sc" &&
      block "changing core.hooksPath or ws.gate.* disables the git gate: do it yourself if it is really needed"
    grep -Eq "${GIT}commit" <<<"$sc" && grep -qi 'co-authored-by' <<<"$cmd" &&
      block "Co-authored-by is forbidden by the organization's policy"
    grep -Eq '(curl|wget)[^|;&]*\|[[:space:]]*(sudo([[:space:]]+-[^[:space:]]+)*[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$)' <<<"$sc" &&
      block "curl|sh: download the script, review it and run it yourself"
    grep -Eq '(^|[;&|[:space:]])(ba|z|da)?sh[[:space:]]+<\([[:space:]]*(curl|wget)' <<<"$sc" &&
      block "sh <(curl …): download the script, review it and run it yourself"
    grep -Eq '(^|[;&|[:space:](])ws-secret[[:space:]]+get([[:space:]]|$)' <<<"$sc" &&
      block "ws-secret get prints a secret: use it yourself, outside Claude"
    if grep -Eq '(^|[;&|[:space:]])az[[:space:]].*[[:space:]](create|update|delete|delete-batch|set|start|stop|restart|deallocate|scale|purge|deploy|invoke|assign|import|swap|upload|remove)([[:space:]]|$)' <<<"$sc"; then
      sub="$(grep -Eo -- '--subscription[[:space:]=]+[^[:space:]]+' <<<"$cmd" | sed -E 's/--subscription[[:space:]=]+//' | tr -d "\"'" | head -1)"
      [[ -n "$sub" ]] || sub="$(sed '1s/^\xEF\xBB\xBF//' "$HOME/.azure/azureProfile.json" 2>/dev/null | jq -r '.subscriptions[]? | select(.isDefault) | .name' 2>/dev/null)"
      grep -Eqi "$PROD" <<<"$sub" &&
        block "mutating az against the production subscription ($sub): run it yourself, outside Claude"
    fi
    if grep -Eq '(^|[;&|[:space:]])(kubectl|helm)([[:space:]]+[^[:space:]|;&]+)*[[:space:]]+(delete|apply|scale|patch|replace|drain|cordon|rollout|uninstall|upgrade|install|rollback|edit|annotate|label|taint)([[:space:]]|$)' <<<"$sc"; then
      ctx="$(grep -Eo -- '--(kube-)?context[[:space:]=]+[^[:space:]]+' <<<"$cmd" | sed -E 's/--(kube-)?context[[:space:]=]+//' | tr -d "\"'" | head -1)"
      [[ -n "$ctx" ]] || ctx="$(kubectl config current-context 2>/dev/null)"
      grep -Eqi "$PROD" <<<"$ctx" &&
        block "mutating kubectl/helm against the production context ($ctx): run it yourself, outside Claude"
    fi
    # Windows PowerShell runs outside the sandbox: no encoded commands and no «download and run» (here the quoted
    # text does count, because the script goes inside -Command "…").
    if grep -Eqi '(^|[;&|[:space:]])(pwsh|powershell)(\.exe)?([[:space:]]|$)' <<<"$sc"; then
      grep -Eqi '[[:space:]]-(e|ec|enc|enco[a-z]*)[[:space:]]' <<<"$cmd" &&
        block "PowerShell with an encoded command (-EncodedCommand): write it in plain text or run it yourself"
      grep -Eqi '(iex|invoke-expression)' <<<"$cmd" && grep -Eqi '(iwr|irm|invoke-webrequest|invoke-restmethod|downloadstring|downloadfile|start-bitstransfer)' <<<"$cmd" &&
        block "PowerShell that downloads and runs: download the script, review it and run it yourself"
    fi
    # What git runs later, outside the sandbox (hooks, aliases, filters): not written from Claude.
    grep -Eq '(>|>>|(^|[;&|[:space:]])(tee|cp|mv|install|ln|chmod|rm|touch|truncate|dd)[[:space:]]|sed[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i)[^|;&]*\.git/(hooks(/|[[:space:]]|$)|config([[:space:]]|$))' <<<"$cmd" &&
      block "writing to .git/hooks or .git/config leaves code that runs outside the sandbox: do it yourself"
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    ruta="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
    grep -Eq '(^|/)\.git/(hooks/|config$|info/attributes$)' <<<"$ruta" &&
      block "writing to .git/hooks or .git/config leaves code that runs outside the sandbox: do it yourself"
    content="$(jq -r '[.tool_input.content, .tool_input.new_string, .tool_input.new_source, (.tool_input.edits[]?.new_string)] | map(select(. != null)) | join("\n")' <<<"$input")"
    grep -Eq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AccountKey=[A-Za-z0-9+/=]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|SharedAccessSignature=|[?&]sig=[A-Za-z0-9%]{30,}' <<<"$content" &&
      block "the content seems to include a secret: use Key Vault or a variable reference"
    ;;
esac
exit 0
