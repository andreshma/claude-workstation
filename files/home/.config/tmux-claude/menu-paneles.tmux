# menu-paneles.tmux — Submenú: dividir, zoom, layouts, copiar y avisos del panel actual.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] ▦  Paneles · #W " -x C -y C -- \
  "-#[nodim]── Acomodar ──" "" "" \
  "Dividir lado a lado" v "split-window -h -c '#{pane_current_path}'" \
  "Dividir arriba y abajo" h "split-window -v -c '#{pane_current_path}'" \
  "Zoom del panel (otra vez para volver)" z "resize-pane -Z" \
  "Layout principal 65 %" M "select-layout main-vertical" \
  "Mosaico" T "select-layout tiled" \
  "Sacar el panel a su pestaña" '!' "break-pane" \
  "Cerrar este panel" x "confirm-before -p \"¿Cerrar este panel? (y/n)\" kill-pane" \
  "-#[nodim]── Copiar ──" "" "" \
  "Scroll y copiar (v marca, y copia, q sale)" c "copy-mode" \
  "Copiar las últimas 200 líneas" Y "run-shell \"tmux capture-pane -pJ -S -200 -t '#{pane_id}' | tmux load-buffer -w - && tmux display 'Últimas 200 líneas copiadas'\"" \
  "Extraer URLs, rutas, IDs… (Ctrl+b u)" u "display-popup -E -w 85% -h 70% -T ' Extraer de la pantalla ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-extraer #{pane_id}\"" \
  "-#[nodim]── Avisos ──" "" "" \
  "Avísame cuando termine (Ctrl+b N)" N "run-shell -b '~/.local/bin/tmux-avisame #{pane_id}'" \
  "Logs en vivo con alarma" L "display-popup -E -w 85% -h 70% -T ' Logs en vivo ' -d \"#{pane_current_path}\" \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-logs\"" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
