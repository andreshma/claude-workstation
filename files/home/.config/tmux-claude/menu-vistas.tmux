# menu-vistas.tmux — Submenú: monitor, enfoque, segundo monitor/espejo, flotantes, historial y grabación.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] ◫  Vistas y utilidades " -x C -y C -- \
  "-#[nodim]── Ver ──" "" "" \
  "#{?#{==:#{status},2},Ocultar,Mostrar} monitor de cómputo (Ctrl+b v)" v "run-shell -b '~/.local/bin/tmux-hud --alternar'" \
  "Subagentes en vivo (Ctrl+b A)" A "display-popup -E -w 90% -h 70% -T ' Subagentes en vivo ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-agents\"" \
  "Modo enfoque: 25/50/90 min sin avisos" f "run-shell -b '~/.local/bin/tmux-enfoque --menu'" \
  "Segundo monitor (mismo grupo, independiente)" m "run-shell -b '~/.local/bin/tmux-monitor2'" \
  "Espejo de solo lectura (compartir pantalla)" e "run-shell -b '~/.local/bin/tmux-monitor2 --espejo'" \
  "-#[nodim]── Flotantes ──" "" "" \
  "Shell flotante persistente (Ctrl+b g)" g "display-popup -E -w 80% -h 75% -T ' Shell ' -d \"#{pane_current_path}\" \"~/.local/bin/tmux-flot-run --persistente env PESTANA=#{window_id} bash -l\"" \
  "PowerShell flotante (Ctrl+b P)" P "display-popup -E -w 80% -h 75% -T ' PowerShell ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pwsh\"" \
  "-#[nodim]── Historial y grabación ──" "" "" \
  "Buscar en el historial de todos los paneles" h "display-popup -E -w 85% -h 75% -T ' Historial ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-historial\"" \
  "Historial buscable: #{?#{==:#{@historial},on},apagar,encender}" y "run-shell -b '~/.local/bin/tmux-historial #{?#{==:#{@historial},on},off,on}'" \
  "#{?@grabando,Detener grabación,Grabar este panel}" r "run-shell -b '~/.local/bin/tmux-grabar #{pane_id}'" \
  "Abrir carpeta de grabaciones" V "run-shell -b 'mkdir -p @WINHOME@/Videos/Claude; explorer.exe \"$(wslpath -w @WINHOME@/Videos/Claude)\" || true'" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
