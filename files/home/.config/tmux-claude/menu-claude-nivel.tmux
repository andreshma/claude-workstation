# menu-claude-nivel.tmux — Submenú: nivel de protección de Claude en esta pestaña (ADR-012). Reinicia Claude y retoma la conversación.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] 🛡  Protección · #W · #{?@cnivel,#{@cnivel},normal} " -x C -y C -- \
  "Completo: sandbox sin escapatorias + reglas del kit#{?#{==:#{@cnivel},completo}, ✓,}" c "confirm-before -p \"¿Reiniciar #W con protección completa? Retoma la conversación (y/n)\" \"run-shell -b '~/.local/bin/tmux-nivel completo #{pane_id}'\"" \
  "Normal: tu configuración de siempre#{?@cnivel,, ✓}" n "confirm-before -p \"¿Reiniciar #W con protección normal? Retoma la conversación (y/n)\" \"run-shell -b '~/.local/bin/tmux-nivel normal #{pane_id}'\"" \
  "Puro: sin sandbox ni permisos del kit (queda el piso)#{?#{==:#{@cnivel},puro}, ✓,}" p "confirm-before -p \"¿Reiniciar #W como Claude puro (sin sandbox; queda el piso)? (y/n)\" \"run-shell -b '~/.local/bin/tmux-nivel puro #{pane_id}'\"" \
  "-#[nodim]── Otro arranque ──" "" "" \
  "#{?#{@csolo},Salir del modo solo,Modo solo: auto sin sandbox (lo crítico te lo pregunta)}" s "confirm-before -p \"#{?#{@csolo},¿Regresar #W a modo normal?,¿Pasar #W a modo solo: auto sin sandbox?} (y/n)\" \"run-shell -b '~/.local/bin/tmux-solo #{?#{@csolo},normal,esta} #{pane_id}'\"" \
  "Reiniciar sin cambiar la protección (retoma la conversación)" C "confirm-before -p \"¿Reiniciar Claude en #W? (y/n)\" \"run-shell -b '~/.local/bin/tmux-claude-restart #{pane_id}'\"" \
  "-#[nodim]── Ver ──" "" "" \
  "Reglas activas (/permissions)" r "send-keys /permissions Enter" \
  "Estado del sandbox (/sandbox)" x "send-keys /sandbox Enter" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu-claude.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
