# shellcheck shell=bash
# Functions to open repos with Claude Code in tmux. Loaded from ~/.bashrc.

# _claude_cmd <dir> — the command a new tab starts Claude with: the level for new tabs (tmux-level default, normal
# unless you chose full in Menu → Settings; tmux-level --new-tab-command: claude-resume, which continues the folder's
# conversation or starts a new one, with that level's profile). Without tmux-level: "claude --continue" if that
# directory already has conversations, otherwise "claude".
_claude_cmd() {
  local k="${1//[^A-Za-z0-9]/-}" c
  if c="$("$HOME/.local/bin/tmux-level" --new-tab-command "$1" 2>/dev/null)" && [[ -n "$c" ]]; then echo "$c"; return; fi
  if c="$("$HOME/.local/bin/tmux-level" --command normal 2>/dev/null)" && [[ -n "$c" ]]; then echo "$c"; return; fi
  if compgen -G "$HOME/.claude/projects/$k/*.jsonl" >/dev/null; then echo "claude --continue"; else echo "claude"; fi
}

# _claude_mark [window] — marks a new tab with the level it starts at, when that is «full» (🔒), as tmux-level does.
# shellcheck disable=SC2120  # the window is optional: tw and two mark the current one, tmux-open passes its own
_claude_mark() {
  [[ "$("$HOME/.local/bin/tmux-level" default 2>/dev/null)" == full ]] || return 0
  tmux set -w ${1:+-t "$1"} @clevel full \; set -w ${1:+-t "$1"} @clevel_ico "🔒" 2>/dev/null
}

# twt <repo> <branch> — creates (if missing) the worktree at <repo>.wt/<branch> and opens it with tw.
twt() {
  local r; r="$(git -C "${1:?repo}" rev-parse --show-toplevel)" || return 1
  local b="${2:?branch}" w="$r.wt/${2//\//-}"
  [ -d "$w" ] || git -C "$r" worktree add -b "$b" "$w" 2>/dev/null || git -C "$r" worktree add "$w" "$b" || return 1
  tw "$w" "$(basename "$r")@${2//\//-}"
}

# tp <dir> — adds <dir> as a pane of the current tab with Claude and rearranges as tiled.
tp() {
  local d; d="$(realpath -e "${1:-.}")" || return 1
  tmux split-window -c "$d" \; select-layout tiled \; send-keys "$(_claude_cmd "$d")" Enter
}

# tw <dir> [name] — project tab with Claude only, full screen (no side shell).
tw() {
  local d; d="$(realpath -e "${1:-.}")" || return 1
  tmux new-window -n "${2:-$(basename "$d")}" -c "$d" \; send-keys "$(_claude_cmd "$d")" Enter
  _claude_mark
}

# two <dir> [name] — like tw, but starts Claude with Opus (Menu → Open a folder with Opus).
two() {
  local d; d="$(realpath -e "${1:-.}")" || return 1
  tmux new-window -n "${2:-$(basename "$d")}" -c "$d" \; send-keys "$(_claude_cmd "$d") --model opus" Enter
  _claude_mark
}

# WSL ↔ Windows bridge and prompt with context
# shellcheck source=/dev/null
[ -f ~/.config/tmux-claude/wsl-bridge.sh ] && . ~/.config/tmux-claude/wsl-bridge.sh
