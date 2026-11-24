#!/usr/bin/env bash
#
# win-hook.sh <Windows exe> [args...] — runs a Windows hook (MemPalace, recall) from
# Claude Code on WSL. Converts the transcript_path and cwd fields of the hook JSON to Windows paths,
# so the Windows process can open them, and returns its output and exit code unchanged.
set -o pipefail
input="$(cat)"
win() { if [ -n "$1" ]; then wslpath -w "$1" 2>/dev/null || printf '%s' "$1"; fi; }
tp="$(jq -r '.transcript_path // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
jq -c --arg tp "$(win "$tp")" --arg cwd "$(win "$cwd")" \
  '(if .transcript_path then .transcript_path = $tp else . end) | (if .cwd then .cwd = $cwd else . end)' \
  <<<"$input" | "$@"
