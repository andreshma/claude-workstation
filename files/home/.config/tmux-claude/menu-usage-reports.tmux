# menu-usage-reports.tmux — Submenu: the three reports (full with Claude findings, quick, last week).
# Opened from menu-usage.tmux («Reports ›»). Backspace returns to the previous menu.
# While the menu is open the status bar does not refresh: a refresh redraws the menu on top and flickers.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] 📊  Reports " -x C -y C -- \
  "Full report with Claude findings (usage, agents, MemPalace, recall)" i "display-popup -E -w 92% -h 85% -T ' Report with Claude ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-report --ai --ai-memory --open'\"" \
  "Quick report, without Claude" j "display-popup -E -w 92% -h 85% -T ' Quick report ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-report --open'\"" \
  "Report for last week" s "display-popup -E -w 92% -h 85% -T ' Week ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-telemetry week | less -R'\"" \
  '' \
  "‹ Back" BSpace "source-file ~/.config/tmux-claude/menu-usage.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
