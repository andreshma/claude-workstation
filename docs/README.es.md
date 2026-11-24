# claude-workstation

[![ci](https://github.com/andreshma/claude-workstation/actions/workflows/ci.yml/badge.svg)](https://github.com/andreshma/claude-workstation/actions/workflows/ci.yml)

Versión corta en español del [README](../README.md). La documentación completa está en inglés:
[uso diario](USAGE.md), [arquitectura](architecture.md), [modelo de amenazas](THREAT_MODEL.md),
[pruebas](TESTING.md) y [runbook](runbook.md).

Estación de trabajo para **Claude Code + tmux en WSL2**, versionada y reinstalable. Una sesión `dev` con una pestaña por repo o worktree, cada una con su Claude; nada se pierde al cerrar la terminal, reiniciar WSL o apagar la laptop.

El repo **captura la configuración real** de una máquina (`export.sh`) y la **reinstala sin planchar** en otra (`install.sh`): todo archivo que cambia se respalda antes como `*.bak.<fecha>`. Las rutas y usuarios personales se guardan como plantilla. El kit no nombra a ninguna empresa: la cuenta del trabajo se llama `trabajo` y los estándares que instala son genéricos (`~/.claude/estandares.md`); los de tu organización van en tu configuración personal.

## Arquitectura

```
Windows ── Windows Terminal (perfil Ubuntu → tmux -u new -As dev) · perfil de PowerShell (dev, devo…)
   │          avisos de Windows · Administrador de credenciales (ws-secret) · respaldos en %UserProfile%
WSL2 Ubuntu 24.04
   └─ tmux (sesión dev y una sesión por grupo) ── resurrect + continuum (cada minuto + al cambiar pestañas)
        ├─ pestaña por repo ── Claude Code (cuenta trabajo o personal)
        │     hooks: estado, auditoría, guard, ruteo, trazas, avisos, lint, documentos→Markdown
        │     sandbox (bubblewrap) · permisos allow/ask/deny · nivel de protección por pestaña
        │     OpenTelemetry → ws-otel (127.0.0.1) → ~/.local/share/ws-telemetria/otel
        ├─ barra: estado de cada Claude, ⚠ te esperan, ⏳ sin avance, ◉ consumo, suscripción y rama
        ├─ vigía (tmux-watch): recordatorios, consumo, mantiene vivo ws-otel
        └─ menú, paleta, flotantes (repos, tablero, activas, subagentes), protector de pantalla
git ── hooks globales (_chain → ws-gate: secretos, lint, Conventional Commits, push a main, dependencias, IaC)
informes ── ws-telemetria (tablero) · ws-informe (30 días) · ws-hooks · todo local
```

## Qué incluye

| Ruta (`files/home/…`) | Qué es |
|---|---|
| `.tmux.conf`, `.config/tmux-claude/` | Pestañas, barra con el estado de cada Claude, menús, temas, plantillas, `functions.sh` (`tw`, `twt`, `two`, `tp`), `cuentas.sh`, `roots.txt` |
| `.local/bin/tmux-*` | Selector de repos y pestañas, tablero, activas, estado (`tmux-estado`), vigía (`tmux-watch`), niveles (`tmux-nivel`, `tmux-solo`), reinicio (`tmux-claude-restart`), subagentes, grabación, protector (`tmux-saver`, `tmux-arte`) |
| `.local/bin/ws-*` | Salud (`ws-check`, `ws-health`, `ws-verify`, `ws-auditoria`), respaldos, herramientas, compuerta (`ws-gate`), telemetría (`ws-telemetria`, `ws-informe`, `ws-otel`, `ws-hooks`), `ws-cache`, Telegram, secretos, pruebas (`ws-test`) |
| `.local/bin/claude-cuenta` | Dos cuentas de Claude (`trabajo` y `personal`), por pestaña y por proyecto |
| `.claude/settings.json`, `.claude/hooks/` | Modelo, permisos, sandbox, exportación de OpenTelemetry, status line y hooks |
| `.claude/agents/` | `arquitecto`, `depurador`, `explorador`, `sql-rapido` |
| `.claude/CLAUDE.md`, `estandares.md` | Estándares de trabajo genéricos |
| `.config/git/hooks/` | `_chain`: compuerta `ws-gate` y luego los hooks propios del repo |
| `files/mcp-servers.json` | Servidores MCP de usuario; los que no existen en la máquina se omiten con aviso |
| `windows/` | `profile.ps1` (atajos de PowerShell) e `instalar.ps1` |

Fuera del repo a propósito: conversaciones, auditoría, telemetría, credenciales y respaldos.

## Instalación en una máquina nueva

1. **Windows:** WSL2 con Ubuntu 24.04.
2. **Ubuntu:** `sudo apt-get install -y tmux git jq fzf gh bubblewrap socat rsync shellcheck`.
3. **Claude Code:** instálalo e inicia sesión (`claude auth login`).
4. **Kit:**
   ```bash
   git clone https://github.com/andreshma/claude-workstation ~/code/claude-workstation
   cd ~/code/claude-workstation
   bash tests/run.sh                 # pruebas en HOMEs temporales; no tocan tu máquina
   bash install.sh --dry-run         # qué cambiaría
   bash install.sh                   # detecta tu usuario de Windows; si no, usa --win-user
   ```
5. **Herramientas:** `ws-tools install base nube calidad`. Opcional: `ws-tools install numpy chafa` (escenas del protector).
6. **Compuerta de git:** `install.sh` apunta git a los hooks del kit si no tienes otra ruta configurada (`--no-git-hooks` lo omite).
7. **Windows:** en PowerShell, `windows\instalar.ps1`.
8. **Sesiones:** `az login`, `gh auth login`; en tmux, `Ctrl+b I` (plugins); `ws-check` y `ws-health` en OK.

| Opción de `install.sh` | Uso |
|---|---|
| `--dry-run` | Muestra `nuevo` / `cambia` / `igual` sin escribir |
| `--win-user USUARIO` | Usuario de Windows si no se detecta |
| `--repos RUTA` | Carpeta de repos (por defecto `/mnt/c/Users/<usuario>/source/repos`) |
| `--no-plugins` · `--no-mcp` | Sin plugins de tmux · sin registrar MCP |

Marcadores de plantilla: `@WINHOME@`, `@WIN_USER@`, `@HOME@`, `@LINUX_USER@`.

## Uso diario (resumen)

| Quiero | Cómo |
|---|---|
| Entrar | `dev` en PowerShell, el acceso directo o Windows Terminal |
| Abrir un repo con Claude | `Ctrl+b o` · `tw <carpeta>` |
| Moverme entre pestañas | `Alt+1…9`, `Alt+←/→`, `Alt+0` (última), `Alt+s` (buscar), `Alt+↑/↓` (grupo) |
| Menú con todo | `Ctrl+b m` o clic en `≡ menú` · paleta: `Ctrl+b Espacio` |
| Ver qué me espera | Barra (`⚠`) · `Ctrl+b a` (activas) · `Ctrl+b D` (tablero) · Menú → `g` (ir a la siguiente que te espera) |
| Elegir el modelo por tarea | `cr "tarea"` · Menú → Claude → Modelo · el ruteo pregunta antes de cambiar |
| Cambiar la protección de una pestaña | Menú → Claude → Protección · `tmux-nivel completo\|normal\|puro` |
| Dejar a Claude trabajando solo | Menú → Claude → «Claude solo en pestaña nueva» o «en worktree nuevo» (`tmux-solo`) |
| Cambiar de cuenta | Menú → Claude → Cuenta · `claude-cuenta pestaña` · `claude-cuenta usar trabajo\|personal` |
| Fijar la cuenta de un proyecto | `claude-cuenta proyecto trabajo\|personal [carpeta]` · `claude-cuenta proyectos` |
| Reiniciar Claude en todas las pestañas libres | Menú → Estación → `R` · `tmux-claude-restart --todas` (`--lista` muestra qué haría) |
| Responder desde el celular | `ws-telegram configurar` (una vez) · botones en Telegram |
| Ver consumo e informes | Menú → Consumo e informes · `ws-telemetria abrir` · `ws-informe` |
| Cuánto tardan los hooks | `ws-hooks` · `ws-hooks tiempo SessionStart` |
| Probar toda la estación | `ws-test` (aislado, sin gastar uso) · `ws-test --ia` (con Claude real) |
| Atajos y manual | `Ctrl+b h` · `ws-menus --ver` |

### Estado por pestaña

🧠 pensando · 🔧 herramienta · ✋ aprobar · ❓ te pregunta · **👉 te toca** (Claude terminó su turno dejándote una pregunta o algo por hacer; `WS_TETOCA=0` lo apaga) · 📦 compactando · 🐝 agentes · ✔ listo · ⏳ sin avance · ⛔ interrumpido · ✖ error API. La barra cuenta en `⚠` las pestañas que te esperan, incluidas las de «te toca».

### Niveles de protección (ADR-012 y ADR-013)

| Nivel | Sandbox | Reglas `allow`/`ask` del kit | Piso: `deny` + `guard.sh` |
|---|---|---|---|
| **completo** 🔒 | Encendido, sin comandos excluidos | Sí | Sí |
| **normal** | Encendido, con los comandos excluidos de tu `settings.json` | Sí | Sí |
| **puro** 🔓 | Apagado | No | Sí |
| **modo solo** 🤖 | Apagado (modo `auto`) | Sí | Sí |

El piso no lo apaga ningún nivel. La fase 2 de ADR-013 sigue pendiente; el detalle está en el [modelo de amenazas](THREAT_MODEL.md#pending-work).

### Telemetría

Todo queda en la máquina. Las trazas de los hooks y lo que sale de las transcripciones guardan solo conteos, tiempos y nombres. El colector local de OpenTelemetry (`ws-otel`, ADR-014) guarda todo lo que emite Claude Code, incluido el texto de prompts, respuestas y herramientas, con los secretos reconocibles tapados; `WS_OTEL_CONTENIDO=0` lo deja sin contenido. El tablero y `ws-informe` suman API, permisos, tiempo activo y las **razones para estimar** (palabras, tokens, llamadas, costo y máquina por turno).

### Protector de pantalla

Todas las escenas las dibuja `tmux-arte`: 25 escenas de arte ASCII animado; 12 usan el motor de sombreado y necesitan `python3-numpy`. La escena `galeria` muestra tus imágenes y GIF de `~/.config/tmux-claude/galeria` con `chafa`.

## Mantenimiento

```bash
ws-check && ws-health        # estado de la estación y de la resiliencia
ws-update                    # Claude Code, plugins, paquetes
ws-actualizar                # actualiza la estación desde el kit; vuelve atrás si ws-test falla
tmux-claude-restart --todas  # las pestañas libres toman la configuración nueva
bash export.sh               # captura lo instalado hacia el kit
ws-verify                    # prueba de todo el setup (solo lee) antes de subir
```

## Runbook

Guía completa paso a paso: [runbook.md](runbook.md). Resumen:

| Síntoma | Acción |
|---|---|
| Faltan pestañas al volver | Menú → Pestañas y sesión → Recuperar pestañas de un guardado anterior (`tmux-recuperar`) |
| Claude no retoma la conversación | En la pestaña: `claude -c` o `claude -r` |
| Algo dejó de funcionar tras `install.sh` | Restaura el `*.bak.<fecha>` del archivo |
| `export.sh` se niega por «posibles secretos» | Mueve el secreto a un vault; si es un patrón de detección, agrégalo a `secrets-allow.txt` con revisión |
| La compuerta bloquea un commit | Corrige lo marcado con ✖; por repo, desde tu terminal: `git config ws.gate.skip …` |
| Claude: «Read-only file system» | Es el sandbox; ejecútalo tú con `!` o agrega una exclusión justificada |
| Las pestañas abiertas no mandan OpenTelemetry | La exportación arranca con Claude: `tmux-claude-restart --todas` |
| WSL dañado | Ubuntu nuevo → `install.sh` → `ws-restore-lite --restaurar` → logins |
| ¿El respaldo sirve? | `ws-restore-lite` (prueba en carpeta temporal; no toca tu `$HOME`) |

## Seguridad

Secretos solo en el Administrador de credenciales de Windows (`ws-secret`); el kit bloquea exportarlos. Claude trabaja en sandbox con permisos mínimos: lecturas enumeradas libres, cambios en la nube, bases de datos e infraestructura con confirmación, lectura de credenciales y saltarse la compuerta prohibidos. El guard falla cerrado y bloquea push forzado, push a `main`, `--no-verify`, cambios a `core.hooksPath`, `Co-authored-by`, `curl | sh`, `ws-secret get`, cambios de `az`, `kubectl` y `helm` en producción y secretos en archivos. Detalle, riesgos residuales y pendientes: [THREAT_MODEL.md](THREAT_MODEL.md) y [SECURITY.md](../SECURITY.md).

## Convenciones

Conventional Commits en imperativo (`feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `perf`, `style`, `build`), commits atómicos, sin `Co-authored-by`. Cambios registrados en [CHANGELOG.md](../CHANGELOG.md) (Keep a Changelog). Cómo contribuir: [CONTRIBUTING.md](../CONTRIBUTING.md).

## Configuración personal (ws-personal)

Lo que es solo tuyo (segmentos de la barra, presupuestos, ajustes de ruteo y Telegram, plantillas propias, los estándares de tu organización) no va en este kit: va a tu repo privado con `ws-personal` ([ADR-011](adr/0011-personal-configuration.md)).

```bash
ws-personal init --github     # una vez: crea el repo privado y lo sube
ws-personal agregar .config/algo/mio.conf
ws-personal restaurar         # en una PC nueva, después de install.sh
```

Se sincroniza solo una vez al día; si algo parece secreto, no hace commit y te avisa.

ADR: [011 configuración personal](adr/0011-personal-configuration.md) · [012 protección por pestaña](adr/0012-per-tab-protection.md) · [013 piso mínimo](adr/0013-minimum-protection-floor.md) · [014 colector local de OpenTelemetry](adr/0014-local-opentelemetry-collector.md).
