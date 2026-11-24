#!/usr/bin/env bash
#
# win-hook.sh <exe de Windows> [args...] — corre un hook de Windows (MemPalace, recall) desde
# Claude Code en WSL. Traduce a rutas de Windows los campos transcript_path y cwd del JSON del hook,
# para que el proceso de Windows pueda abrirlos, y devuelve su salida y su código de salida tal cual.
set -o pipefail
input="$(cat)"
win() { if [ -n "$1" ]; then wslpath -w "$1" 2>/dev/null || printf '%s' "$1"; fi; }
tp="$(jq -r '.transcript_path // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
jq -c --arg tp "$(win "$tp")" --arg cwd "$(win "$cwd")" \
  '(if .transcript_path then .transcript_path = $tp else . end) | (if .cwd then .cwd = $cwd else . end)' \
  <<<"$input" | "$@"
