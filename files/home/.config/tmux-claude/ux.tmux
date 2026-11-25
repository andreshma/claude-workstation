# ~/.config/tmux-claude/ux.tmux — patch 58: menu/popup style, monitor and the finder views.
# Ctrl+b a   finder on the active view: active now, from all groups (Enter goes to the tab)
# Ctrl+b j   finder on the recent view: recent Claude conversations of all projects, open or not
# Ctrl+b v   shows or hides the compute monitor (second line of the status bar)
bind a display-popup -E -w 92% -h 80% -T ' Find ' "~/.local/bin/tmux-popup-run ~/.local/bin/tmux-find --view active"
bind j display-popup -E -w 92% -h 80% -T ' Find ' "~/.local/bin/tmux-popup-run ~/.local/bin/tmux-find --view recent"
bind v run-shell -b "~/.local/bin/tmux-hud --toggle"
run-shell -b "~/.local/bin/tmux-ux"
