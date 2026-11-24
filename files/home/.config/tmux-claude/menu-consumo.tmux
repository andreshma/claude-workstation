# menu-consumo.tmux — Submenú: consumo, trazas, estimación, reporte semanal y presupuestos.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] 📊  Consumo e informes " -x C -y C -- \
  "-#[nodim]── Informes ──" "" "" \
  "Informe completo con hallazgos de Claude (uso, agentes, MemPalace, recall)" i "display-popup -E -w 92% -h 85% -T ' Informe con Claude ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-informe --ia --ia-memoria --abrir'\"" \
  "Informe rápido, sin Claude" j "display-popup -E -w 92% -h 85% -T ' Informe rápido ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-informe --abrir'\"" \
  "Aprender de mí: hechos para MemPalace (tú eliges)" a "display-popup -E -w 92% -h 85% -T ' Aprender de mí ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-aprender hechos'\"" \
  "Crear comandos «/» de lo que repites" k "display-popup -E -w 92% -h 85% -T ' Comandos propios ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-aprender comandos'\"" \
  "-#[nodim]── Consumo ──" "" "" \
  "Tablero de consumo (navegador)" c "run-shell -b '~/.local/bin/ws-telemetria abrir'" \
  "Herramientas: tiempos, errores y costo (7 días)" r "display-popup -E -w 92% -h 85% -T ' Herramientas ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-telemetria trazas'\"" \
  "Estimación por ticket (90 días)" t "display-popup -E -w 92% -h 85% -T ' Estimación ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-telemetria estimar'\"" \
  "Reporte de la semana pasada" s "display-popup -E -w 92% -h 85% -T ' Semana ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-telemetria semana | less -R'\"" \
  "Presupuestos del mes" p "display-popup -E -w 92% -h 85% -T ' Presupuestos ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-telemetria presupuestos'\"" \
  "Exportar CSV para Excel o Power BI" x "run-shell -b '~/.local/bin/ws-telemetria exportar >/dev/null && tmux display \"CSV en %UserProfile%\\ws-telemetria\\datos\"'" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
