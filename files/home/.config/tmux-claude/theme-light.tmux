# theme-light.tmux — light theme colors. Applied by tmux-theme; do not load it by hand.
# @t_* are the semantic colors used by the status bar, the hooks and the scripts.
set -g @theme_current light
set -g @t_ok colour28
set -g @t_think colour25
set -g @t_tool colour130
set -g @t_alert colour160
set -g @t_agent colour90
set -g @t_az colour130
set -g @t_branch colour25
set -g status-style 'bg=colour253,fg=colour238'
setw -g window-status-style 'bg=colour251,fg=colour238'
setw -g window-status-current-style 'bg=colour231,fg=colour16,bold'
setw -g window-status-bell-style 'bg=colour220,fg=colour16,bold'
set -g pane-border-style 'fg=colour250'
set -g pane-active-border-style 'fg=colour25'
set -g message-style 'bg=colour254,fg=colour236'
set -g message-command-style 'bg=colour254,fg=colour236'
setw -g mode-style 'bg=colour153,fg=colour16'
set -gq menu-style 'bg=colour255,fg=colour236'
set -gq menu-selected-style 'bg=colour153,fg=colour16,bold'
set -gq menu-border-style 'fg=colour245'
set -gq popup-style 'bg=default,fg=default'
set -gq popup-border-style 'fg=colour245'
setw -g clock-mode-colour colour25
