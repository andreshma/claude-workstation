# ~/.config/tmux-claude/ux.tmux — parche 58: estilo de menús/flotantes, monitor y ventana de activas.
# Ctrl+b a   activas ahora, de todos los grupos (Enter va a la pestaña)
# Ctrl+b v   muestra u oculta el monitor de cómputo (segunda línea de la barra)
bind a display-popup -E -w 92% -h 70% -T ' Activas ahora ' "~/.local/bin/tmux-flot-run ~/.local/bin/tmux-activas"
bind v run-shell -b "~/.local/bin/tmux-hud --alternar"
run-shell -b "~/.local/bin/tmux-ux"

# Ctrl+b j queda libre: «Trabajos recientes» se quitó del menú y del atajo (tmux-recientes sigue instalado).
unbind -q j
