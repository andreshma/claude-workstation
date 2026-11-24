# ~/.config/tmux-claude/maravillas.tmux — atajos del parche 52 (lo carga ~/.tmux.conf al final).
# Ctrl+b e       mandar a Claude la salida del panel de al lado (redactada, sin Enter)
# Ctrl+b Espacio paleta de comandos: busca cualquier opción de los menús
# Ctrl+b N       avísame cuando termine el comando de este panel (otra vez: cancela)
# Ctrl+b u       extraer URLs, rutas, hashes, IDs… de la pantalla
# Ctrl+b ?       pregunta rápida a Claude (Haiku) en una flotante
# Ctrl+b E       etiqueta de la pestaña (bloqueada, en revisión, lista…)
bind e run-shell -b "~/.local/bin/tmux-panel '#{pane_id}'"
bind Space display-popup -E -w 80% -h 70% -T ' Paleta de comandos ' "~/.local/bin/tmux-flot-run ~/.local/bin/tmux-paleta '#{pane_id}'"
bind N run-shell -b "~/.local/bin/tmux-avisame '#{pane_id}'"
bind u display-popup -E -w 85% -h 70% -T ' Extraer de la pantalla ' "~/.local/bin/tmux-flot-run ~/.local/bin/tmux-extraer '#{pane_id}'"
bind ? display-popup -E -w 80% -h 70% -d "#{pane_current_path}" -T ' Pregunta rápida ' "~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pregunta '#{pane_id}'"
bind E run-shell -b "~/.local/bin/tmux-etiqueta --menu '#{window_id}'"
# Favoritas: * pone o quita la pestaña actual, F abre la lista. La ★ se repone al abrir pestañas o conectar.
bind * run-shell -b "~/.local/bin/tmux-favoritos --alternar '#{window_id}'"
bind F display-popup -E -w 85% -h 70% -T ' Favoritas ' "~/.local/bin/tmux-flot-run ~/.local/bin/tmux-favoritos"
set-hook -g 'after-new-window[62]' 'run-shell -b "~/.local/bin/tmux-favoritos --marcar"'
set-hook -g 'client-attached[62]' 'run-shell -b "~/.local/bin/tmux-favoritos --marcar"'
run-shell -b "~/.local/bin/tmux-fondo --barra"
# Etiqueta, CI/PR y tus segmentos (~/.config/ws-local/barra-extra.conf) vuelven a la barra tras un cambio de tema.
set-hook -g 'client-attached[52]' 'run-shell -b "~/.local/bin/tmux-fondo --barra"'
set-hook -g 'client-session-changed[52]' 'run-shell -b "~/.local/bin/tmux-fondo --barra"'

# Red de seguridad de los menús: pausan el refresco de la barra mientras están abiertos (status-interval 0) y lo
# reponen al cerrarse. Si algo lo dejara en 0, al cambiar de pestaña o de sesión vuelve a su valor.
set-hook -g 'after-select-window[61]' 'if -F "#{==:#{status-interval},0}" "set -gF status-interval \"#{?@si_prev,#{@si_prev},15}\""'
set-hook -g 'client-session-changed[61]' 'if -F "#{==:#{status-interval},0}" "set -gF status-interval \"#{?@si_prev,#{@si_prev},15}\""'
