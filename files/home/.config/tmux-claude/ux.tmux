# ~/.config/tmux-claude/ux.tmux — patch 58: menu/popup style, monitor and the active-tabs window.
# Ctrl+b a   active now, from all groups (Enter goes to the tab)
# Ctrl+b v   shows or hides the compute monitor (second line of the status bar)
bind a display-popup -E -w 92% -h 70% -T ' Active now ' "~/.local/bin/tmux-flot-run ~/.local/bin/tmux-activas"
bind v run-shell -b "~/.local/bin/tmux-hud --alternar"
run-shell -b "~/.local/bin/tmux-ux"

# Ctrl+b j stays free: «Recent jobs» was removed from the menu and the shortcut (tmux-recientes is still installed).
unbind -q j
