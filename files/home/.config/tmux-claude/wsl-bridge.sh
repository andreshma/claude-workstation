# shellcheck shell=bash
# wsl-bridge.sh — puente WSL ↔ Windows y prompt con contexto. Lo carga functions.sh
# (que a su vez carga ~/.bashrc). Fuente: kit claude-workstation.
#
#   wopen [ruta|URL]   abre en Windows con la app predeterminada (wslview)
#   wexp  [carpeta]    abre la carpeta en el Explorador de Windows
#   wpath [ruta]       ruta de Windows equivalente (C:\…)
#   wcopy              copia stdin al portapapeles de Windows (con acentos):  git diff | wcopy
#   wpaste             imprime el portapapeles de Windows:                    wpaste > notas.md

# Navegador de Windows para az login, gh auth, enlaces de herramientas, etc.
command -v wslview >/dev/null && export BROWSER=wslview

wopen() { wslview "${1:-.}"; }
wexp()  { explorer.exe "$(wslpath -w "${1:-.}")" || true; }
wpath() { wslpath -w "${1:-.}"; }
wcopy() { { printf '\xff\xfe'; iconv -f utf-8 -t utf-16le; } | clip.exe; }
wpaste() {
  powershell.exe -NoProfile -NonInteractive -Command \
    '[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Clipboard' | sed 's/\r$//'
}

# Prompt con contexto (starship): solo en shells interactivos.
if [[ $- == *i* ]] && command -v starship >/dev/null; then
  eval "$(starship init bash)"
fi
