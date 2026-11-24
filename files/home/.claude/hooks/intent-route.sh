#!/usr/bin/env bash
#
# intent-route.sh — UserPromptSubmit hook: based on the intent of the prompt, tells Claude which
# subagent to delegate to (arquitecto = Opus, explorador = Haiku). It does not change the session model
# (Claude Code does not allow that from hooks): it adds a context note. With no match, it does nothing.
p="$(jq -r '.prompt // ""' | tr '[:upper:]' '[:lower:]')"
# Spanish on purpose: the patterns match prompts typed in Spanish.
if grep -Eq 'arquitect|diseñ|disen|adr|c4|trade-?off|threat|amenaza|seguridad|owasp|vulnerab|migraci|causa ra|root cause' <<<"$p"; then
  echo "Intent routing: design, security or deep analysis task. Delegate the analysis to the 'arquitecto' subagent (Opus) and then implement it yourself."
elif grep -Eq '^(busca|dónde|donde|lista|explora|mapea|encuentra|qué hace|que hace)|dónde está|donde esta' <<<"$p"; then
  echo "Intent routing: exploration or reading task. Delegate to the 'explorador' subagent (Haiku)."
fi
exit 0
