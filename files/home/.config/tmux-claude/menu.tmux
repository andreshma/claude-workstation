# menu.tmux — Menú principal de la estación (Ctrl+b m, o clic a la derecha de la barra). Cada «›» abre un submenú; Retroceso vuelve.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] ☰  #S › #W · #{?#{@cs},#{@cs},sin Claude}#{?#{@cctx}, · ctx #{@cctx}%,} " -x C -y C -- \
  "-#[nodim]── Ir a ──" "" "" \
  "Activas ahora, de todos los grupos (Ctrl+b a)" a "display-popup -E -w 92% -h 70% -T ' Activas ahora ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-activas\"" \
  "Ir a la siguiente que te espera o lleva rato sin avance" g "run-shell '~/.local/bin/tmux-watch --goto'" \
  "Buscar pestaña por nombre" f "display-popup -E -w 85% -h 75% -T ' Buscar pestaña ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pick\"" \
  "Tablero de pestañas (Ctrl+b D)" D "display-popup -E -w 92% -h 70% -T ' Tablero de pestañas ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-dash\"" \
  "Abrir carpeta o repo (Ctrl+b o)" o "display-popup -E -w 80% -h 70% -T ' Abrir carpeta ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-open\"" \
  "Abrir carpeta con Opus" O "display-popup -E -w 80% -h 70% -T ' Abrir con Opus ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-open --opus\"" \
  "Abrir carpeta con plantilla (Claude + pruebas + git)" T "display-popup -E -w 80% -h 60% -T ' Abrir con plantilla ' -d \"#{pane_current_path}\" \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-plantilla\"" \
  "Nuevo worktree de este repo" w "command-prompt -p Rama: \"run-shell -b \\\"~/.local/bin/tmux-worktree '#{pane_current_path}' '%1'\\\"\"" \
  "-#[nodim]── Esta pestaña ──" "" "" \
  "#{?#{@cs},,-}Claude en esta pestaña ›" c "source-file ~/.config/tmux-claude/menu-claude.tmux" \
  "Pestañas y sesión ›" s "source-file ~/.config/tmux-claude/menu-sesion.tmux" \
  "Paneles, copiar y avisos ›" l "source-file ~/.config/tmux-claude/menu-paneles.tmux" \
  "-#[nodim]── Herramientas ──" "" "" \
  "Paleta de comandos (Ctrl+b Espacio)" p "display-popup -E -w 80% -h 70% -T ' Paleta de comandos ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-paleta #{pane_id}\"" \
  "Pregunta rápida a Claude (Ctrl+b ?)" '?' "display-popup -E -w 80% -h 70% -T ' Pregunta rápida ' -d \"#{pane_current_path}\" \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pregunta #{pane_id}\"" \
  "Vistas: monitor, enfoque, flotantes, historial ›" x "source-file ~/.config/tmux-claude/menu-vistas.tmux" \
  "Consumo e informes ›" r "source-file ~/.config/tmux-claude/menu-consumo.tmux" \
  "Estación: salud, respaldos, avisos ›" e "source-file ~/.config/tmux-claude/menu-estacion.tmux" \
  "Apariencia y protector de pantalla ›" v "source-file ~/.config/tmux-claude/menu-apariencia.tmux" \
  "-#[nodim]── Ayuda ──" "" "" \
  "Manual completo (todo lo instalado)" m "display-popup -E -w 92% -h 85% -T ' Manual ' ~/.local/bin/tmux-flot-run ~/.local/bin/ws-menus --ver" \
  "Atajos de teclado" h "display-popup -E -w 92% -h 80% -T ' Atajos ' ~/.local/bin/tmux-flot-run ~/.local/bin/tmux-help"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
