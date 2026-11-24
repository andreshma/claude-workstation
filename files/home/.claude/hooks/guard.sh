#!/usr/bin/env bash
#
# guard.sh — guardarraíles deterministas para Claude Code (hook PreToolUse). Es parte del PISO de ADR-013: corre en
# todos los niveles de protección (completo, normal, solo y puro).
# Bloquea con exit 2 (Claude recibe el motivo y busca otra vía) acciones contra política:
#   · git push forzado (--force, -f, -fu, +refspec) · push a main/master (explícito, refs/heads/… o estando en esa rama)
#   · saltarse la compuerta de git (--no-verify, core.hooksPath, ws.gate.*) · commits con Co-authored-by
#   · bajar y ejecutar (curl|wget … | sh, sh <(curl …)) · leer secretos con ws-secret get
#   · az, kubectl y helm mutantes contra producción (suscripción o contexto activos, o indicados en el comando)
#   · escribir secretos en archivos (llaves privadas, tokens, AccountKey, SAS)
# Falla CERRADO: si no puede leer la entrada (sin jq o JSON inválido) bloquea, porque no sabe qué está dejando pasar.
# Para decidir ignora el texto entre comillas (un echo o un grep que mencionan un push forzado no se bloquean).
# Es defensa en profundidad, no un control absoluto: RBAC y la revisión humana siguen mandando.
input="$(cat)"
if ! command -v jq >/dev/null 2>&1 || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$input"; then
  printf 'BLOQUEADO por política (guard.sh): no pude leer la acción (falta jq o la entrada no es JSON)\n' >&2
  exit 2
fi
tool="$(jq -r '.tool_name // ""' <<<"$input")"
PROD="${GUARD_PROD_REGEX:-prod|prd|produccion}"

# block <motivo> — registra en la auditoría y bloquea la acción.
block() {
  "$HOME/.claude/hooks/audit.sh" blocked "$1" <<<"$input" >/dev/null 2>&1
  printf 'BLOQUEADO por política (guard.sh): %s\n' "$1" >&2
  exit 2
}

case "$tool" in
  Bash)
    cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
    cwd="$(jq -r '.cwd // ""' <<<"$input")"
    # Sin el texto entre comillas: lo que queda son las palabras que la shell ejecuta.
    sc="$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$cmd")"
    GIT='git([[:space:]]+-[cC][[:space:]]*[^[:space:]]+)*[[:space:]]+'
    if grep -Eq "${GIT}push([[:space:]]|\$)" <<<"$sc"; then
      resto="$(grep -Eo "${GIT}push[^|;&]*" <<<"$sc" | sed -E "s/^${GIT}push//" | tr '\n' ' ')"
      grep -Eq '(^|[[:space:]])(--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|$)|(^|[[:space:]])\+[^[:space:]]' <<<"$resto" &&
        block "git push forzado (usa --force-with-lease en tu rama, o hazlo tú)"
      grep -Eq '(^|[[:space:]:/])(main|master)([[:space:]]|$)' <<<"$resto" &&
        block "push directo a main/master: trabaja en una rama y abre PR"
      # «git push» sin rama (cero o un argumento que no es opción) o con HEAD: sube la rama actual.
      args="$(tr ' ' '\n' <<<"$resto" | grep -Evc '^(-.*)?$')"
      if (( args < 2 )) || grep -Eq '(^|[[:space:]:])HEAD([[:space:]:]|$)' <<<"$resto"; then
        rama="$(git -C "${cwd:-.}" branch --show-current 2>/dev/null)"
        [[ "$rama" == main || "$rama" == master ]] && block "push estando en $rama: trabaja en una rama y abre PR"
      fi
    fi
    grep -Eq "${GIT}(commit|push|merge|rebase|am|cherry-pick)[^|;&]*[[:space:]]--no-verify([[:space:]]|\$)" <<<"$sc" &&
      block "--no-verify salta la compuerta de git: corrige lo que marca"
    grep -Eq '(^|[;&|[:space:]])git[[:space:]]' <<<"$sc" && grep -Eqi 'core\.hookspath|ws\.gate\.' <<<"$sc" &&
      block "cambiar core.hooksPath o ws.gate.* desactiva la compuerta de git: hazlo tú si de verdad hace falta"
    grep -Eq "${GIT}commit" <<<"$sc" && grep -qi 'co-authored-by' <<<"$cmd" &&
      block "Co-authored-by está prohibido por la política de la organización"
    grep -Eq '(curl|wget)[^|;&]*\|[[:space:]]*(sudo([[:space:]]+-[^[:space:]]+)*[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$)' <<<"$sc" &&
      block "curl|sh: descarga el script, revísalo y ejecútalo tú"
    grep -Eq '(^|[;&|[:space:]])(ba|z|da)?sh[[:space:]]+<\([[:space:]]*(curl|wget)' <<<"$sc" &&
      block "sh <(curl …): descarga el script, revísalo y ejecútalo tú"
    grep -Eq '(^|[;&|[:space:](])ws-secret[[:space:]]+get([[:space:]]|$)' <<<"$sc" &&
      block "ws-secret get muestra un secreto: úsalo tú, fuera de Claude"
    if grep -Eq '(^|[;&|[:space:]])az[[:space:]].*[[:space:]](create|update|delete|delete-batch|set|start|stop|restart|deallocate|scale|purge|deploy|invoke|assign|import|swap|upload|remove)([[:space:]]|$)' <<<"$sc"; then
      sub="$(grep -Eo -- '--subscription[[:space:]=]+[^[:space:]]+' <<<"$cmd" | sed -E 's/--subscription[[:space:]=]+//' | tr -d "\"'" | head -1)"
      [[ -n "$sub" ]] || sub="$(sed '1s/^\xEF\xBB\xBF//' "$HOME/.azure/azureProfile.json" 2>/dev/null | jq -r '.subscriptions[]? | select(.isDefault) | .name' 2>/dev/null)"
      grep -Eqi "$PROD" <<<"$sub" &&
        block "az mutante contra la suscripción de producción ($sub): ejecútalo tú, fuera de Claude"
    fi
    if grep -Eq '(^|[;&|[:space:]])(kubectl|helm)([[:space:]]+[^[:space:]|;&]+)*[[:space:]]+(delete|apply|scale|patch|replace|drain|cordon|rollout|uninstall|upgrade|install|rollback|edit|annotate|label|taint)([[:space:]]|$)' <<<"$sc"; then
      ctx="$(grep -Eo -- '--(kube-)?context[[:space:]=]+[^[:space:]]+' <<<"$cmd" | sed -E 's/--(kube-)?context[[:space:]=]+//' | tr -d "\"'" | head -1)"
      [[ -n "$ctx" ]] || ctx="$(kubectl config current-context 2>/dev/null)"
      grep -Eqi "$PROD" <<<"$ctx" &&
        block "kubectl/helm mutante contra el contexto de producción ($ctx): ejecútalo tú, fuera de Claude"
    fi
    # PowerShell de Windows corre fuera de la sandbox: sin comandos codificados ni «baja y ejecuta» (aquí sí cuenta el
    # texto entre comillas, porque el guion va dentro de -Command "…").
    if grep -Eqi '(^|[;&|[:space:]])(pwsh|powershell)(\.exe)?([[:space:]]|$)' <<<"$sc"; then
      grep -Eqi '[[:space:]]-(e|ec|enc|enco[a-z]*)[[:space:]]' <<<"$cmd" &&
        block "PowerShell con comando codificado (-EncodedCommand): escríbelo en claro o ejecútalo tú"
      grep -Eqi '(iex|invoke-expression)' <<<"$cmd" && grep -Eqi '(iwr|irm|invoke-webrequest|invoke-restmethod|downloadstring|downloadfile|start-bitstransfer)' <<<"$cmd" &&
        block "PowerShell que descarga y ejecuta: baja el script, revísalo y ejecútalo tú"
    fi
    # Lo que git ejecuta después, fuera de la sandbox (hooks, alias, filtros): no se escribe desde Claude.
    grep -Eq '(>|>>|(^|[;&|[:space:]])(tee|cp|mv|install|ln|chmod|rm|touch|truncate|dd)[[:space:]]|sed[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i)[^|;&]*\.git/(hooks(/|[[:space:]]|$)|config([[:space:]]|$))' <<<"$cmd" &&
      block "escribir en .git/hooks o .git/config deja código que se ejecuta fuera de la sandbox: hazlo tú"
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    ruta="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$input")"
    grep -Eq '(^|/)\.git/(hooks/|config$|info/attributes$)' <<<"$ruta" &&
      block "escribir en .git/hooks o .git/config deja código que se ejecuta fuera de la sandbox: hazlo tú"
    content="$(jq -r '[.tool_input.content, .tool_input.new_string, .tool_input.new_source, (.tool_input.edits[]?.new_string)] | map(select(. != null)) | join("\n")' <<<"$input")"
    grep -Eq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AccountKey=[A-Za-z0-9+/=]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|SharedAccessSignature=|[?&]sig=[A-Za-z0-9%]{30,}' <<<"$content" &&
      block "el contenido parece incluir un secreto: usa Key Vault o una referencia a variable"
    ;;
esac
exit 0
