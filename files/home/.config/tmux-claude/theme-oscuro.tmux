# theme-oscuro.tmux — dark theme colors. Applied by tmux-theme; do not load it by hand.
# @t_* are the semantic colors used by the status bar, the hooks and the scripts.
set -g @theme_actual oscuro
set -g @t_ok colour82
set -g @t_think colour39
set -g @t_tool colour214
set -g @t_alert colour196
set -g @t_agent colour177
set -g @t_az colour214
set -g @t_branch colour110
set -g status-style 'bg=colour235,fg=colour250'
setw -g window-status-style 'bg=colour237,fg=colour250'
setw -g window-status-current-style 'bg=colour238,fg=colour255,bold'
setw -g window-status-bell-style 'bg=colour220,fg=colour16,bold'
set -g pane-border-style 'fg=colour238'
set -g pane-active-border-style 'fg=colour60'
set -g message-style 'bg=colour236,fg=colour252'
set -g message-command-style 'bg=colour236,fg=colour252'
setw -g mode-style 'bg=colour60,fg=colour255'
set -gq menu-style 'bg=colour236,fg=colour252'
set -gq menu-selected-style 'bg=colour60,fg=colour255,bold'
set -gq menu-border-style 'fg=colour60'
set -gq popup-style 'bg=default,fg=default'
set -gq popup-border-style 'fg=colour60'
setw -g clock-mode-colour colour60
