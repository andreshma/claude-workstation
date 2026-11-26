# menu-telegram.tmux — Submenu: every Telegram setting with its current value (ADR 0010, ADR 0026).
# Opened from Menu → Workstation → Telegram. ws-telegram menu-sync publishes the values as @tg_* options first.
# These are your actions: the menu runs outside Claude, and Claude cannot change the settings file (guard.sh).
# The PIN is typed only in a terminal popup (ws-telegram text pin → Windows Credential Manager), never through tmux.
# While the menu is open the status bar does not refresh: a refresh redraws the menu on top and flickers.
run-shell '~/.local/bin/ws-telegram menu-sync'
if -F '#{!=:#{status-interval},0}' 'set -gF @si_prev "#{status-interval}"'
set -g status-interval 0
display-menu -O -T "#[align=centre] ✉  Telegram · #{?@tg_on,#{@tg_on},?} · #{?@tg_mode,#{@tg_mode},approvals} " -x C -y C -- \
  "Notifications: #{?@tg_on,#{@tg_on},?} (switch)" o "run-shell -b '~/.local/bin/ws-telegram toggle'" \
  "-#[nodim]── What is sent at once ──" "" "" \
  "Only what needs me, the rest in the digest (approvals)#{?#{==:#{@tg_mode},approvals}, ✓,}" a "run-shell -b '~/.local/bin/ws-telegram notify approvals'" \
  "Only the digest#{?#{==:#{@tg_mode},digest}, ✓,}" d "run-shell -b '~/.local/bin/ws-telegram notify digest'" \
  "Everything#{?#{==:#{@tg_mode},all}, ✓,}" e "run-shell -b '~/.local/bin/ws-telegram notify all'" \
  "Only security alerts#{?#{==:#{@tg_mode},off}, ✓,}" x "run-shell -b '~/.local/bin/ws-telegram notify off'" \
  "-#[nodim]── Digest: #{?@tg_digest,#{@tg_digest},1h} ──" "" "" \
  "Every 30 min#{?#{==:#{@tg_digest},30m}, ✓,}" 3 "run-shell -b '~/.local/bin/ws-telegram digest 30m'" \
  "Every hour (default)#{?#{==:#{@tg_digest},1h}, ✓,}" 1 "run-shell -b '~/.local/bin/ws-telegram digest 1h'" \
  "Every 2 h#{?#{==:#{@tg_digest},2h}, ✓,}" 2 "run-shell -b '~/.local/bin/ws-telegram digest 2h'" \
  "Every 4 h#{?#{==:#{@tg_digest},4h}, ✓,}" 4 "run-shell -b '~/.local/bin/ws-telegram digest 4h'" \
  "No digest#{?#{==:#{@tg_digest},off}, ✓,}" 0 "run-shell -b '~/.local/bin/ws-telegram digest off'" \
  "Send the digest now" n "run-shell -b '~/.local/bin/ws-telegram digest now'" \
  "-#[nodim]── Quiet hours: #{?@tg_quiet,#{@tg_quiet},off} (only security alerts and blocking approvals) ──" "" "" \
  "22:00-07:00#{?#{==:#{@tg_quiet},22:00-07:00}, ✓,}" q "run-shell -b '~/.local/bin/ws-telegram quiet 22:00-07:00'" \
  "23:00-08:00#{?#{==:#{@tg_quiet},23:00-08:00}, ✓,}" w "run-shell -b '~/.local/bin/ws-telegram quiet 23:00-08:00'" \
  "Other hours…" c "command-prompt -p 'Quiet hours (HH:MM-HH:MM, 24 h):' \"run-shell -b '~/.local/bin/ws-telegram quiet %1'\"" \
  "No quiet hours#{?#{==:#{@tg_quiet},off}, ✓,}" z "run-shell -b '~/.local/bin/ws-telegram quiet off'" \
  "-#[nodim]── PIN and replies ──" "" "" \
  "Text replies with the PIN: #{?@tg_text,#{@tg_text},off} (switch)" t "run-shell -b '~/.local/bin/ws-telegram text toggle'" \
  "Approvals: PIN for #{?#{==:#{@tg_approve},pin},every approval,risky dialogs only} (switch)" p "run-shell -b '~/.local/bin/ws-telegram approve #{?#{==:#{@tg_approve},pin},risky,pin}'" \
  "▶ Run: #{?#{==:#{@tg_run},no-pin},no PIN,asks for the PIN} (switch)" r "#{?#{==:#{@tg_run},no-pin},run-shell -b '~/.local/bin/ws-telegram run pin',confirm-before -p \"▶ Run without the PIN? Whoever holds your unlocked phone could run (y/n)\" \"run-shell -b '~/.local/bin/ws-telegram run no-pin'\"}" \
  "Set or change the PIN (typed in a terminal)" P "display-popup -E -w 80% -h 50% -T ' Telegram PIN ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-telegram text pin'\"" \
  "-#[nodim]── Check ──" "" "" \
  "Send a test message" s "run-shell -b '~/.local/bin/ws-telegram test'" \
  "Status: service, mode, PIN loaded, last API error" S "display-popup -E -w 92% -h 85% -T ' Telegram ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-telegram status'\"" \
  "Link your bot (first time)" B "display-popup -E -w 92% -h 85% -T ' Telegram setup ' \"~/.local/bin/tmux-popup-run ~/.local/bin/tmux-pause 'ws-telegram setup'\"" \
  '' \
  "‹ Back" BSpace "source-file ~/.config/tmux-claude/menu-workstation.tmux"
set -gF status-interval '#{?@si_prev,#{@si_prev},15}'
