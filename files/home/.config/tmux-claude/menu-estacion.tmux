# menu-estacion.tmux — Submenú: salud, respaldos, seguridad, Azure, avisos y actualización.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] ⚙  Estación " -x C -y C -- \
  "-#[nodim]── Salud y respaldos ──" "" "" \
  "Revisión de la estación" v "display-popup -E -w 92% -h 85% -T ' Revisión ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-check; ws-health'\"" \
  "Respaldar Claude ahora" b "display-popup -E -w 92% -h 85% -T ' Respaldo ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-backup-lite'\"" \
  "Probar el último respaldo" B "display-popup -E -w 92% -h 85% -T ' Prueba de respaldo ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-restore-lite'\"" \
  "Tu configuración personal: sincronizar" P "display-popup -E -w 92% -h 85% -T ' Configuración personal ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-personal sync; ws-personal estado'\"" \
  "Reiniciar Claude en todas las pestañas libres (toma la configuración nueva)" R "confirm-before -p \"¿Salir y volver a entrar en todas las pestañas de Claude que no estén trabajando? Retoman su conversación (y/n)\" \"run-shell -b '~/.local/bin/tmux-claude-restart --todas'\"" \
  "Actualizar la estación desde el kit" U "display-popup -E -w 92% -h 85% -T ' Actualizar ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-actualizar'\"" \
  "-#[nodim]── Seguridad y nube ──" "" "" \
  "Calidad y seguridad del repo" Q "display-popup -E -w 95% -h 90% -T ' Calidad del repo ' -d \"#{pane_current_path}\" \"~/.local/bin/tmux-flot-run ~/.local/bin/ws-gate repo-view\"" \
  "Auditoría de Claude" u "display-popup -E -w 90% -h 80% -T ' Auditoría ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'claude-report'\"" \
  "Cambiar suscripción de Azure" z "display-popup -E -w 80% -h 70% -T ' Suscripción de Azure ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-az-sub\"" \
  "Herramientas instaladas" I "display-popup -E -w 92% -h 85% -T ' Herramientas ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-tools'\"" \
  "-#[nodim]── Avisos ──" "" "" \
  "Avisos de Windows: #{?#{==:#{@cnotify},off},apagados,encendidos}" n "if -F '#{==:#{@cnotify},off}' 'set -g @cnotify on ; display \"Avisos de Windows encendidos\"' 'set -g @cnotify off ; display \"Avisos de Windows apagados\"'" \
  "Telegram: encender o apagar avisos" g "run-shell -b '~/.local/bin/ws-telegram alternar'" \
  "Telegram: respuestas de texto sí/no (PIN)" G "run-shell -b '~/.local/bin/ws-telegram texto alternar'" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
