# menu-sesion.tmux — Submenú: moverse entre pestañas y grupos, la pestaña actual, guardar y recuperar.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] 🗂  Pestañas y sesión · #S › #W " -x C -y C -- \
  "-#[nodim]── Moverse ──" "" "" \
  "Ir por número…" N "command-prompt -p 'Número de pestaña:' \"select-window -t ':%%'\"" \
  "Grupos y pestañas (Alt+←/→ pestaña, Alt+↑/↓ grupo)" S "choose-tree -sZ -O name" \
  "-#[nodim]── Esta pestaña ──" "" "" \
  "Resumen: qué, dónde y en qué se quedó (doble clic)" i "display-popup -E -w 84% -h 70% -T ' Resumen de la pestaña ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-resumen\"" \
  "Etiqueta de la pestaña (Ctrl+b E)" E "run-shell -b '~/.local/bin/tmux-etiqueta --menu #{window_id}'" \
  "Renombrar pestaña" r "command-prompt -I \"#W\" \"rename-window -- '%%'\"" \
  "Cerrar pestaña" x "confirm-before -p \"¿Cerrar la pestaña #W? (y/n)\" kill-window" \
  "-#[nodim]── Guardar y recuperar ──" "" "" \
  "Guardar sesión ahora" s "run-shell ~/.tmux/plugins/tmux-resurrect/scripts/save.sh" \
  "Restaurar sesión guardada" R "confirm-before -p \"¿Restaurar? Si las pestañas ya están abiertas pueden duplicarse (y/n)\" \"run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh\"" \
  "Recuperar pestañas de un guardado anterior" u "display-popup -E -w 90% -h 70% -T ' Recuperar pestañas ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-recuperar\"" \
  "Traer conversaciones recientes a tmux" t "display-popup -E -w 90% -h 80% -T ' Traer conversaciones ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-traer\"" \
  "Guardar esta pestaña como plantilla" G "command-prompt -p 'Nombre de la plantilla:' \"run-shell -b '~/.local/bin/tmux-plantilla --guardar %% #{window_id}'\"" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
