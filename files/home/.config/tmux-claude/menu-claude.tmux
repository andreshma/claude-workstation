# menu-claude.tmux — Submenú: Claude en esta pestaña: conversación, modelo, trabajar con otras pestañas y cuentas.
# Generado por el parche 58 (menús con secciones). Retroceso vuelve al menú anterior.
# Mientras el menú está abierto la barra no se refresca: su refresco redibuja el menú encima y parpadea.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] 🤖  Claude · #W · #{?#{@cs},#{@cs},sin Claude} " -x C -y C -- \
  "-#[nodim]── Conversación ──" "" "" \
  "Ver contexto" c "send-keys /context Enter" \
  "Compactar conversación" k "confirm-before -p \"¿Compactar la conversación de #W? (y/n)\" \"send-keys /compact Enter\"" \
  "Volver a un punto anterior" b "send-keys /rewind Enter" \
  "Transcripción y razonamiento" t "send-keys C-o" \
  "Tareas y subagentes" T "send-keys /tasks Enter" \
  "Interrumpir" e "send-keys Escape" \
  "Mandar a segundo plano" B "send-keys C-b" \
  "-#[nodim]── Modelo y modo ──" "" "" \
  "Modelo: #{?#{@cmodel},#{@cmodel},—} ›" 9 "source-file ~/.config/tmux-claude/menu-claude-modelo.tmux" \
  "Modo de permisos / plan" p "send-keys BTab" \
  "Protección: #{?@cnivel,#{@cnivel},normal}#{?#{@csolo}, · modo solo,} ›" S "source-file ~/.config/tmux-claude/menu-claude-nivel.tmux" \
  "-#[nodim]── Con otras pestañas ──" "" "" \
  "Mandar el panel de al lado a Claude (Ctrl+b e)" x "run-shell -b '~/.local/bin/tmux-panel #{pane_id}'" \
  "Mismo texto a varias pestañas con Claude" D "display-popup -E -w 85% -h 70% -T ' Difundir ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-difundir\"" \
  "Enjambre: varias Claude en paralelo sobre una meta" Z "display-popup -E -w 92% -h 85% -T ' Enjambre ' -d \"#{pane_current_path}\" \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-enjambre nuevo\"" \
  "Exportar mi trabajo para otro Claude (traspaso)" E "display-popup -E -w 92% -h 85% -T ' Traspaso ' \"~/.local/bin/tmux-flot-run ~/.local/bin/tmux-pause 'ws-traspaso #{pane_id}'\"" \
  "Claude solo en pestaña nueva" s "run-shell -b '~/.local/bin/tmux-solo nueva \"#{pane_current_path}\"'" \
  "Claude solo en worktree nuevo" w "run-shell -b '~/.local/bin/tmux-solo worktree \"#{pane_current_path}\"'" \
  "-#[nodim]── Cuenta ──" "" "" \
  "Cambiar esta pestaña a cuenta #{?#{==:#{@ccuenta},personal},trabajo,personal} (misma conversación)" a "confirm-before -p \"¿Cambiar #W de cuenta? (y/n)\" \"run-shell -b '~/.local/bin/claude-cuenta pestaña #{pane_id}'\"" \
  "Pestañas nuevas con: #{?#{==:#{@ccuenta_def},personal},personal → usar trabajo,trabajo → usar personal}" n "run-shell -b '~/.local/bin/claude-cuenta usar #{?#{==:#{@ccuenta_def},personal},trabajo,personal}'" \
  "Este proyecto siempre con la cuenta de esta pestaña (#{?#{==:#{@ccuenta},personal},personal,trabajo})" f "run-shell -b '~/.local/bin/claude-cuenta proyecto #{?#{==:#{@ccuenta},personal},personal,trabajo} --pane #{pane_id}'" \
  "Iniciar sesión en cuenta personal" L "new-window -n login-personal \"~/.local/bin/tmux-pause 'claude-cuenta login personal'\"" \
  '' \
  "Más comandos de Claude ›" '+' "source-file ~/.config/tmux-claude/menu-claude-mas.tmux" \
  '' \
  "‹ Volver" BSpace "source-file ~/.config/tmux-claude/menu.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
