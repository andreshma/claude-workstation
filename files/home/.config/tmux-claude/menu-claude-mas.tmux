# menu-claude-mas.tmux — submenu: more Claude shortcuts and commands (sent to the current tab).
# While the menu is open the status bar does not refresh: a refresh redraws the menu on top and flickers.
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] Claude · more commands " -x C -y C \
  "Claude task list (Ctrl+T)"                 d "send-keys C-t" \
  "Edit the prompt in the editor (Ctrl+G)"    g "send-keys C-g" \
  "Stash or restore the draft (Ctrl+S)"       x "send-keys C-s" \
  "Fast mode on/off (Alt+O)"                  f "send-keys M-o" \
  "Stop background subagents"                 K "send-keys C-x C-k" \
  "Redraw the screen (Ctrl+L)"                l "send-keys C-l" \
  '' \
  "Status and account (/status)"              i "send-keys /status Enter" \
  "Usage and limits (/usage)"                 u "send-keys /usage Enter" \
  "MCP servers (/mcp)"                        m "send-keys /mcp Enter" \
  "Effort (/effort)"                          E "send-keys /effort Enter" \
  '' \
  "‹ Back"                                    BSpace "source-file ~/.config/tmux-claude/menu-claude.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
