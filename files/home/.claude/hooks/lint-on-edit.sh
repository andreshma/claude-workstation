#!/usr/bin/env bash
#
# lint-on-edit.sh — hook PostToolUse (Edit|Write|MultiEdit): revisa con ws-gate el archivo
# que Claude acaba de escribir y, si hay hallazgos, se los pasa como contexto para que los
# corrija en el momento. Nunca bloquea; máximo 20 s.
input="$(cat)"
f="$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)"
[[ -n "$f" && -f "$f" ]] || exit 0
gate="$HOME/.local/bin/ws-gate"; [[ -x "$gate" ]] || exit 0
# WS_GATE_SIN_CODIGO_REPO: los hooks corren fuera del sandbox, así que aquí no se ejecutan linters que cargan código o
# configuración del repo (eslint y prettier de node_modules); esos se quedan para el pre-commit.
out="$(cd "$(dirname "$f")" && WS_GATE_SIN_CODIGO_REPO=1 timeout 20 "$gate" file "$f" 2>&1)" && exit 0
out="$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out" | head -40)"
[[ -n "$out" ]] || exit 0
jq -n --arg c "Lint de ${f##*/} (ws-gate) encontró esto; corrígelo antes de seguir:
$out" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
