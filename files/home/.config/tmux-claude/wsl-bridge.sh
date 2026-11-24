# shellcheck shell=bash
# wsl-bridge.sh — WSL ↔ Windows bridge and prompt with context. Loaded by functions.sh
# (which in turn is loaded by ~/.bashrc). Source: claude-workstation kit.
#
#   wopen [path|URL]   opens in Windows with the default app (wslview)
#   wexp  [folder]     opens the folder in Windows Explorer
#   wpath [path]       equivalent Windows path (C:\…)
#   wcopy              copies stdin to the Windows clipboard (accents included):  git diff | wcopy
#   wpaste             prints the Windows clipboard:                              wpaste > notes.md

# Windows browser for az login, gh auth, tool links, etc.
command -v wslview >/dev/null && export BROWSER=wslview

wopen() { wslview "${1:-.}"; }
wexp()  { explorer.exe "$(wslpath -w "${1:-.}")" || true; }
wpath() { wslpath -w "${1:-.}"; }
wcopy() { { printf '\xff\xfe'; iconv -f utf-8 -t utf-16le; } | clip.exe; }
wpaste() {
  powershell.exe -NoProfile -NonInteractive -Command \
    '[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Clipboard' | sed 's/\r$//'
}

# Prompt with context (starship): interactive shells only.
if [[ $- == *i* ]] && command -v starship >/dev/null; then
  eval "$(starship init bash)"
fi
