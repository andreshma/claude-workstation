# menu-claude-modelo.tmux — Submenú: modelo de esta pestaña (cambia solo esta pestaña; tu modelo por defecto no se toca).
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] Modelo de esta pestaña · ahora #{?#{@cmodel},#{@cmodel},—} " -x C -y C -- \
  "Fable 5.2   · arquitectura, ADR, análisis exhaustivo#{?#{m/i:*fable*,#{@cmodel}}, ✓,}" f "run-shell -b '~/.local/bin/cr --cambiar fable'" \
  "Opus 5.5    · día a día, depuración, seguridad#{?#{m/i:*opus*,#{@cmodel}}, ✓,}" o "run-shell -b '~/.local/bin/cr --cambiar opus'" \
  "Sonnet 5.5  · SQL, cambios acotados, textos cortos#{?#{m/i:*sonnet*,#{@cmodel}}, ✓,}" s "run-shell -b '~/.local/bin/cr --cambiar sonnet'" \
  "Haiku 5.5   · búsquedas y preguntas simples#{?#{m/i:*haiku*,#{@cmodel}}, ✓,}" h "run-shell -b '~/.local/bin/cr --cambiar haiku'" \
  "Selector de modelos de Claude (Alt+P)" M "send-keys M-p" \
  "-#[nodim]── Ruteo automático ──" "" "" \
  "#{?#{==:#{@cruteo},off},Encender,Apagar} ruteo automático en TODAS las pestañas (pregunta antes de cambiar)" r "if -F '#{==:#{@cruteo},off}' 'set -g @cruteo on' 'set -g @cruteo off'" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu-claude.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
