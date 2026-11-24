#!/usr/bin/env bash
#
# intent-route.sh — UserPromptSubmit hook: based on the intent of the prompt, tells Claude which
# subagent to delegate to (architect = Opus, explorer = Haiku). It does not change the session model
# (Claude Code does not allow that from hooks): it adds a context note. With no match, it does nothing.
p="$(jq -r '.prompt // ""' | tr '[:upper:]' '[:lower:]')"
# The patterns come from the language packs (keys intent.design and intent.explore; see ws-lang): English, plus
# Spanish with `ws-lang es`. Without the library or the packs it stays silent.
# shellcheck source=/dev/null
source "$HOME/.local/lib/ws-lang.sh" 2>/dev/null || exit 0
re=""
if ws_lang_var re intent.design && grep -Eq -- "$re" <<<"$p"; then
  echo "Intent routing: design, security or deep analysis task. Delegate the analysis to the 'architect' subagent (Opus) and then implement it yourself."
elif ws_lang_var re intent.explore && grep -Eq -- "$re" <<<"$p"; then
  echo "Intent routing: exploration or reading task. Delegate to the 'explorer' subagent (Haiku)."
fi
exit 0
