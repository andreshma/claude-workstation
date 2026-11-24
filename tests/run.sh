#!/usr/bin/env bash
#
# tests/run.sh — pruebas del kit en HOMEs temporales (no toca tu máquina):
# export captura el manifiesto, bloquea secretos, install es idempotente, --dry-run no escribe,
# un archivo modificado se respalda antes de reemplazarse y .bashrc no duplica líneas.
# Si existe files/ (export real), también valida sus JSON y el lint de sus scripts.
#
# Uso: bash tests/run.sh      (exit 0 = todo OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }

# Kit de trabajo aislado (copia del repo sin files/ reales)
K="$T/kit"; mkdir -p "$K/tests"; cp "$ROOT"/{lib.sh,export.sh,install.sh,manifest.txt,secrets-allow.txt} "$K/"

# HOME de origen con una configuración de ejemplo
A="$T/a"; mkdir -p "$A/.claude/hooks" "$A/.claude/agents" "$A/.local/bin" "$A/.config/tmux-claude"
echo 'set -g mouse on' > "$A/.tmux.conf"
echo '{"model":"opusplan","hooks":{}}' > "$A/.claude/settings.json"
printf '#!/usr/bin/env bash\n# patrón de detección (no es secreto): SharedAccessSignature=\necho ok\n' > "$A/.claude/hooks/guard.sh"; chmod 755 "$A/.claude/hooks/guard.sh"
printf '#!/usr/bin/env bash\n# otro hook con el mismo patrón NO permitido\n' > "$A/.claude/hooks/otro.sh"
echo 'old' > "$A/.claude/hooks/guard.sh.bak.20260101"
echo '---' > "$A/.claude/agents/explorador.md"
printf '#!/usr/bin/env bash\n' > "$A/.local/bin/tmux-dash"; chmod 755 "$A/.local/bin/tmux-dash"
printf 'tw() { :; }\n# rutas: /mnt/c/Users/nadie.x/repos %s/code\n' "$A" > "$A/.config/tmux-claude/functions.sh"
echo '{"mcpServers":{"recall":{"type":"stdio","command":"/x/python.exe","args":["-m","recall","mcp"]}}}' > "$A/.claude.json"

echo "1) export"
HOME="$A" WIN_USER=nadie.x bash "$K/export.sh" > "$T/exp.log" 2>&1
check "exporta archivos del manifiesto" test -f "$K/files/home/.claude/settings.json"
check "exporta directorios (hooks, agents)" test -f "$K/files/home/.claude/hooks/guard.sh"
check "conserva permisos de ejecución" test -x "$K/files/home/.claude/hooks/guard.sh"
check "omite respaldos *.bak.*" not test -e "$K/files/home/.claude/hooks/guard.sh.bak.20260101"
check "exporta servidores MCP" test "$(jq -r 'keys[0]' "$K/files/mcp-servers.json")" = recall

check "guard.sh (en secrets-allow) no bloquea el export" grep -q 'Sin secretos' "$T/exp.log"
check "convierte rutas personales en plantilla" grep -q '@WINHOME@/repos @HOME@/code' "$K/files/home/.config/tmux-claude/functions.sh"
check "no deja el usuario de Windows en el kit" not grep -rq 'nadie\.x' "$K/files/home"

echo "2) bloqueo de secretos"
cp -r "$K" "$T/kit2"; echo 'AccountKey=abcdefghijklmnopqrstuvwxyz0123456789==' >> "$A/.tmux.conf"
check "export falla con un secreto" not env HOME="$A" WIN_USER=nadie.x bash "$T/kit2/export.sh"
check "y no deja files/ a medias" not test -d "$T/kit2/files"
sed -i '/AccountKey/d' "$A/.tmux.conf"
echo '# SharedAccessSignature=' >> "$A/.claude/hooks/otro.sh"
check "un patrón fuera de secrets-allow sí bloquea" not env HOME="$A" WIN_USER=nadie.x bash "$T/kit2/export.sh"
sed -i '/SharedAccessSignature/d' "$A/.claude/hooks/otro.sh"

echo "3) install en una máquina nueva"
B="$T/b"; mkdir -p "$B"
HOME="$B" WIN_USER=otra bash "$K/install.sh" --dry-run --no-plugins --no-mcp > "$T/dry.log" 2>&1
check "--dry-run no escribe nada" test -z "$(find "$B" -type f)"
check "--dry-run lista lo nuevo" grep -q 'nuevo   .claude/settings.json' "$T/dry.log"
HOME="$B" WIN_USER=otra bash "$K/install.sh" --no-plugins --no-mcp > "$T/i1.log" 2>&1
check "instala igual que el origen" diff -q "$A/.claude/settings.json" "$B/.claude/settings.json"
# Simula una máquina donde no se detecta el usuario: sin WIN_USER y sin cmd.exe (fuera de /mnt/*).
SIN_WIN_PATH="$(tr ':' '\n' <<<"$PATH" | grep -v '^/mnt/' | paste -sd:)"
check "sin usuario de Windows: se niega con mensaje claro" bash -c "env -u WIN_USER HOME='$T/c' PATH='$SIN_WIN_PATH' bash '$K/install.sh' --dry-run --no-plugins --no-mcp </dev/null 2>&1 | grep -q -- '--win-user'"
check "instala scripts ejecutables" test -x "$B/.claude/hooks/guard.sh"
check "agrega líneas a .bashrc" grep -qF 'tmux-claude/functions.sh' "$B/.bashrc"
check "plantillas con las rutas de la máquina destino" grep -qF "/mnt/c/Users/otra/repos $B/code" "$B/.config/tmux-claude/functions.sh"
check "REPOS según el usuario destino" grep -qxF 'export REPOS=/mnt/c/Users/otra/source/repos' "$B/.bashrc"

echo "4) idempotencia y no planchar"
HOME="$B" WIN_USER=otra bash "$K/install.sh" --no-plugins --no-mcp > "$T/i2.log" 2>&1
check "segunda instalación: todo igual" not grep -qE '^  (nuevo|cambia|agrega)' "$T/i2.log"
check ".bashrc sin duplicados" test "$(grep -cF 'tmux-claude/functions.sh' "$B/.bashrc")" = 1
echo 'set -g status off' > "$B/.tmux.conf"
HOME="$B" WIN_USER=otra bash "$K/install.sh" --no-plugins --no-mcp > "$T/i3.log" 2>&1
check "archivo cambiado se reporta" grep -q 'cambia  .tmux.conf' "$T/i3.log"
check "y se respalda antes de reemplazar" grep -rq 'status off' "$B"/.tmux.conf.bak.*

if [[ -d "$ROOT/files" ]]; then
  echo "5) export real del repo"
  for j in "$ROOT/files/home/.claude/settings.json" "$ROOT/files/mcp-servers.json"; do
    [[ -f "$j" ]] && check "JSON válido: ${j#"$ROOT"/}" jq empty "$j"
  done
  if command -v shellcheck >/dev/null; then
    while IFS= read -r s; do check "shellcheck ${s#"$ROOT"/}" shellcheck -S warning "$s"; done < \
      <(grep -rlE '^#!.*(bash|sh)' "$ROOT/files/home" 2>/dev/null)
  fi
fi

echo "6) guard de PreToolUse"
check "guard: evasiones, falsos positivos y fallo cerrado" bash "$ROOT/tests/guard.sh"

printf '\n%d ok, %d fallidas\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
