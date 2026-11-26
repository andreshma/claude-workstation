# menu-settings.tmux — Submenu: every workstation setting with its current value (ADR-028). Menu → Settings (S).
# ws-settings menu-sync publishes the values as @ws_set_* options first. These are your actions: the menu runs
# outside Claude, ws-settings refuses to change anything from inside Claude and guard.sh blocks it there too. What
# lowers protection or removes something asks first; secrets are only typed in a terminal popup, never through tmux.
# While the menu is open the status bar does not refresh: a refresh redraws the menu on top and flickers.
run-shell '~/.local/bin/ws-settings menu-sync'
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] ⚙  Settings " -x C -y C -- \
  "-#[nodim]── New tabs ──" "" "" \
  "Protection of new tabs: #{?@ws_set_level,#{@ws_set_level},normal} (switch)" L "#{?#{==:#{@ws_set_level},full},confirm-before -p \"New tabs at the normal level (excluded commands leave the sandbox)? (y/n)\" \"run-shell -b '~/.local/bin/ws-settings level normal'\",run-shell -b '~/.local/bin/ws-settings level full'}" \
  "Profile of new tabs and this project: #{?@ws_set_profile,#{@ws_set_profile},work} ›" p "run-shell -b '~/.local/bin/ws-profile menu #{pane_id}'" \
  "Language of prompts and reports: #{?#{==:#{@ws_lang},es},Spanish,English} (switch)" l "run-shell -b '~/.local/bin/ws-settings lang #{?#{==:#{@ws_lang},es},en,es}'" \
  "-#[nodim]── MCP servers ──" "" "" \
  "chrome-devtools (opt-in): #{?@ws_set_chrome,#{@ws_set_chrome},off} (switch)" c "#{?#{==:#{@ws_set_chrome},on},confirm-before -p \"Remove the chrome-devtools MCP server? (y/n)\" \"run-shell -b '~/.local/bin/ws-settings chrome off'\",display-popup -E -w 92% -h 85% -T ' chrome-devtools ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-settings chrome on'\"}" \
  "Restart on exit (keepalive): #{?@ws_set_keepalive,#{@ws_set_keepalive},none} ›" k "run-shell -b '~/.local/bin/ws-settings menu-keepalive'" \
  "Azure egress allow list: #{?@ws_set_egress,#{@ws_set_egress},off} (#{?#{==:#{@ws_set_egress},enforce},back to audit,enforce it})" e "#{?#{==:#{@ws_set_egress},enforce},confirm-before -p \"Back to audit: Azure MCP may reach hosts outside its list again (logged)? (y/n)\" \"run-shell -b '~/.local/bin/ws-settings egress azure audit'\",confirm-before -p \"Enforce: Azure MCP reaches only its listed hosts (check the report first)? (y/n)\" \"run-shell -b '~/.local/bin/ws-settings egress azure enforce'\"}" \
  "Hosts the jailed servers reached (egress report)" r "display-popup -E -w 92% -h 85% -T ' Egress ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-egress-proxy report'\"" \
  "Tool-definition changes to review: #{?@ws_set_pending,#{@ws_set_pending},0}" t "display-popup -E -w 95% -h 90% -T ' MCP tool definitions ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-settings mcp-review'\"" \
  "Managed MCP allow list: #{?@ws_set_allowlist,#{@ws_set_allowlist},?} (install, sudo)" a "display-popup -E -w 95% -h 90% -T ' MCP allow list ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-settings allowlist'\"" \
  "Your MCP tool rules (filter.local.json, editor)" f "display-popup -E -w 92% -h 85% -T ' MCP tool rules ' \"~/.local/bin/tmux-popup-run ~/.local/bin/ws-settings filter\"" \
  "-#[nodim]── Backups ──" "" "" \
  "Encryption key: #{?@ws_set_backupkey,#{@ws_set_backupkey},?} (set up, in a terminal)" b "display-popup -E -w 92% -h 85% -T ' Backup key ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-settings backup-key'\"" \
  "Windows-side copies expire after: #{?@ws_set_copydays,#{@ws_set_copydays},30} days" d "command-prompt -p 'Days before a Windows-side backup copy expires (0 = never):' -I '#{?@ws_set_copydays,#{@ws_set_copydays},30}' \"run-shell -b '~/.local/bin/ws-settings copy-days %1'\"" \
  "Cloud copy now (encrypted, OneDrive)" o "display-popup -E -w 92% -h 85% -T ' Cloud backup ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-backup-cloud'\"" \
  "Test the latest cloud copy" O "display-popup -E -w 92% -h 85% -T ' Cloud backup test ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-backup-cloud test'\"" \
  "-#[nodim]── Spend ──" "" "" \
  "Budgets: #{?@ws_set_budgets,#{@ws_set_budgets},0} (edit)" B "display-popup -E -w 92% -h 85% -T ' Budgets ' \"~/.local/bin/tmux-popup-run ~/.local/bin/ws-settings budgets\"" \
  "Hold work at 100 % of a budget (hard): #{?@ws_set_hard,#{@ws_set_hard},off} (switch)" H "#{?#{==:#{@ws_set_hard},on},confirm-before -p \"Let work go on past a budget (alerts only)? (y/n)\" \"run-shell -b '~/.local/bin/ws-settings hard off'\",run-shell -b '~/.local/bin/ws-settings hard on'}" \
  "-#[nodim]── Guard ──" "" "" \
  "Production subscriptions and contexts: #{?@ws_set_production,#{@ws_set_production},0} (edit)" P "display-popup -E -w 92% -h 85% -T ' Production ' \"~/.local/bin/tmux-popup-run ~/.local/bin/ws-settings production\"" \
  "Claude may edit CLAUDE.md, commands, agents, skills: #{?@ws_set_window,#{@ws_set_window},closed}" W "#{?#{==:#{@ws_set_window},closed},confirm-before -p \"Let Claude edit CLAUDE.md and its commands/agents/skills for 30 min (each write audited)? (y/n)\" \"run-shell -b '~/.local/bin/ws-settings window open'\",run-shell -b '~/.local/bin/ws-settings window close'}" \
  "Secret rotation periods (edit)" R "display-popup -E -w 92% -h 85% -T ' Secret rotation ' \"~/.local/bin/tmux-popup-run ~/.local/bin/ws-settings rotation\"" \
  "-#[nodim]── Notifications, appearance and status bar ──" "" "" \
  "Windows notifications: #{?#{==:#{@cnotify},off},off,on} (switch)" n "run-shell -b '~/.local/bin/ws-settings notify #{?#{==:#{@cnotify},off},on,off}'" \
  "Telegram: on/off, what is sent, digest, quiet hours, PIN ›" g "source-file ~/.config/tmux-claude/menu-telegram.tmux" \
  "Theme and screensaver ›" v "source-file ~/.config/tmux-claude/menu-appearance.tmux" \
  "Tab resources in the status bar: #{?@ws_set_resmode,#{@ws_set_resmode},full} (full → compact → off)" u "run-shell -b '~/.local/bin/ws-settings res-mode #{?#{==:#{@ws_set_resmode},compact},off,#{?#{==:#{@ws_set_resmode},off},full,compact}}'" \
  "CPU glyph after each tab: #{?@ws_set_restabs,#{@ws_set_restabs},off} (switch)" i "run-shell -b '~/.local/bin/ws-settings res-tabs #{?#{==:#{@ws_set_restabs},on},off,on}'" \
  "Tab resources sampled every #{?@ws_set_resinterval,#{@ws_set_resinterval},2} s (2 → 3 → 4 → 5)" j "run-shell -b '~/.local/bin/ws-settings res-interval #{?#{==:#{@ws_set_resinterval},2},3,#{?#{==:#{@ws_set_resinterval},3},4,#{?#{==:#{@ws_set_resinterval},4},5,2}}}'" \
  "-#[nodim]── Kit and checks ──" "" "" \
  "Update the kit (signed release)" U "display-popup -E -w 92% -h 85% -T ' Update ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-kit-update'\"" \
  "Audit the workstation (ws-audit)" A "display-popup -E -w 95% -h 90% -T ' Audit ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-audit'\"" \
  "Compliance against the catalogue (ws-audit --compliance)" C "display-popup -E -w 95% -h 90% -T ' Compliance ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-audit --compliance'\"" \
  "Health (ws-health)" h "display-popup -E -w 92% -h 85% -T ' Health ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-health'\"" \
  "All current values" s "display-popup -E -w 80% -h 60% -T ' Settings ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-settings show'\"" \
  '' \
  "‹ Back" BSpace "source-file ~/.config/tmux-claude/menu.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
