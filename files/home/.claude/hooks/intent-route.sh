#!/usr/bin/env bash
#
# intent-route.sh — hook UserPromptSubmit: según la intención del prompt, indica a Claude en qué
# subagente delegar (arquitecto = Opus, explorador = Haiku). No cambia el modelo de la sesión
# (Claude Code no lo permite desde hooks): agrega una nota de contexto. Sin coincidencia, no hace nada.
p="$(jq -r '.prompt // ""' | tr '[:upper:]' '[:lower:]')"
if grep -Eq 'arquitect|diseñ|disen|adr|c4|trade-?off|threat|amenaza|seguridad|owasp|vulnerab|migraci|causa ra|root cause' <<<"$p"; then
  echo "Ruteo por intención: tarea de diseño, seguridad o análisis profundo. Delega el análisis en el subagente 'arquitecto' (Opus) y después implementa tú."
elif grep -Eq '^(busca|dónde|donde|lista|explora|mapea|encuentra|qué hace|que hace)|dónde está|donde esta' <<<"$p"; then
  echo "Ruteo por intención: tarea de exploración o lectura. Delega en el subagente 'explorador' (Haiku)."
fi
exit 0
