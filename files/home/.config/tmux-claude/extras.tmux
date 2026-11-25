# ~/.config/tmux-claude/extras.tmux — patch 52 shortcuts (loaded by ~/.tmux.conf at the end).
# Ctrl+b e       send Claude the output of the neighboring pane (redacted, without Enter)
# Ctrl+b Space   command palette: searches any option of the menus
# Ctrl+b N       notify me when the command in this pane finishes (again: cancels)
# Ctrl+b u       extract URLs, paths, hashes, IDs… from the screen
# Ctrl+b ?       quick question to Claude (Haiku) in a popup
# Ctrl+b E       tab label (blocked, in review, ready…)
bind e run-shell -b "~/.local/bin/tmux-pane '#{pane_id}'"
bind Space display-popup -E -w 80% -h 70% -T ' Command palette ' "~/.local/bin/tmux-popup-run ~/.local/bin/tmux-palette '#{pane_id}'"
bind N run-shell -b "~/.local/bin/tmux-notify-me '#{pane_id}'"
bind u display-popup -E -w 85% -h 70% -T ' Extract from the screen ' "~/.local/bin/tmux-popup-run ~/.local/bin/tmux-extract '#{pane_id}'"
bind ? display-popup -E -w 80% -h 70% -d "#{pane_current_path}" -T ' Quick question ' "~/.local/bin/tmux-popup-run ~/.local/bin/tmux-ask '#{pane_id}'"
bind E run-shell -b "~/.local/bin/tmux-label --menu '#{window_id}'"
# Favorites: * adds or removes the current tab, F opens the finder on the favorites view. The ★ is restored when tabs
# open or a client attaches.
bind * run-shell -b "~/.local/bin/tmux-favorites --toggle '#{window_id}'"
bind F display-popup -E -w 92% -h 80% -T ' Find ' "~/.local/bin/tmux-popup-run ~/.local/bin/tmux-find --view favorites"
set-hook -g 'after-new-window[62]' 'run-shell -b "~/.local/bin/tmux-favorites --mark"'
set-hook -g 'client-attached[62]' 'run-shell -b "~/.local/bin/tmux-favorites --mark"'
run-shell -b "~/.local/bin/tmux-background --bar"
# Label, CI/PR and your segments (~/.config/ws-local/bar-extra.conf) return to the status bar after a theme change.
set-hook -g 'client-attached[52]' 'run-shell -b "~/.local/bin/tmux-background --bar"'
set-hook -g 'client-session-changed[52]' 'run-shell -b "~/.local/bin/tmux-background --bar"'

# Safety net for the menus: they pause the status bar refresh while open (status-interval 0) and restore it
# on close. If something left it at 0, switching tab or session brings it back to its value.
set-hook -g 'after-select-window[61]' 'if -F "#{==:#{status-interval},0}" "set -gF status-interval \"#{?@si_prev,#{@si_prev},15}\""'
set-hook -g 'client-session-changed[61]' 'if -F "#{==:#{status-interval},0}" "set -gF status-interval \"#{?@si_prev,#{@si_prev},15}\""'
