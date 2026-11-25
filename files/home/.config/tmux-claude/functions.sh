# shellcheck shell=bash
# Functions to open repos with Claude Code in tmux. Loaded from ~/.bashrc.

# _claude_cmd <dir> — "claude --continue" if that directory already has conversations, otherwise "claude".
_claude_cmd() {
  local k="${1//[^A-Za-z0-9]/-}"
  if compgen -G "$HOME/.claude/projects/$k/*.jsonl" >/dev/null; then echo "claude --continue"; else echo "claude"; fi
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
}

# two <dir> [name] — like tw, but starts Claude with Opus (Menu → Open a folder with Opus).
two() {
  local d; d="$(realpath -e "${1:-.}")" || return 1
  tmux new-window -n "${2:-$(basename "$d")}" -c "$d" \; send-keys "$(_claude_cmd "$d") --model opus" Enter
}

# WSL ↔ Windows bridge and prompt with context
# shellcheck source=/dev/null
[ -f ~/.config/tmux-claude/wsl-bridge.sh ] && . ~/.config/tmux-claude/wsl-bridge.sh
