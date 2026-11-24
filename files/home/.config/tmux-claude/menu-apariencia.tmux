# menu-apariencia.tmux — Submenú: tema (oscuro, claro, automático) y protector de pantalla.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] 🎨  Apariencia · tema #{?@theme_mode,#{@theme_mode},oscuro} " -x C -y C -- \
  "-#[nodim]── Tema ──" "" "" \
  "Tema oscuro#{?#{==:#{@theme_mode},oscuro}, ✓,}" o "run-shell '~/.local/bin/tmux-theme oscuro'" \
  "Tema claro#{?#{==:#{@theme_mode},claro}, ✓,}" c "run-shell '~/.local/bin/tmux-theme claro'" \
  "Automático: sigue a Windows#{?#{==:#{@theme_mode},auto}, ✓,}" a "run-shell '~/.local/bin/tmux-theme auto'" \
  "#{?#{@cs},,-}Tema de Claude en esta pestaña (/theme)" t "send-keys /theme Enter" \
  "-#[nodim]── Protector de pantalla ──" "" "" \
  "Elegir escena de una lista (actual: #{?@saver_scene,#{@saver_scene},aleatoria})" s "display-popup -E -w 80% -h 60% -T ' Escenas del protector ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-escena\"" \
  "Ponerlo ahora" p "lock-client" \
  "Siguiente escena" n "run-shell '~/.local/bin/tmux-saver --siguiente-escena'" \
  "Protector: #{?#{==:#{@saver},off},apagado,encendido (10 min)}" e "run-shell '~/.local/bin/tmux-saver --toggle'" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
