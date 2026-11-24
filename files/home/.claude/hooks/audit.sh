#!/usr/bin/env bash
#
# audit.sh <evento> [motivo] — bitácora de auditoría local de Claude Code (JSONL diario en
# ~/.claude/audit/). Guarda metadatos: quién/dónde/qué herramienta/qué comando. No guarda el
# texto de los prompts ni el contenido de archivos (DLP); los comandos van con secretos redactados.
# Silencioso: no escribe a stdout (en UserPromptSubmit eso se agregaría al contexto de Claude).
input="$(cat)"
dir="${CLAUDE_AUDIT_DIR:-$HOME/.claude/audit}"
mkdir -p "$dir" && chmod 700 "$dir"
[ "${1:-}" = start ] && find "$dir" -name "*.jsonl" -mtime +90 -delete
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
repo="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)"; repo="${repo##*/}"
branch="$(git -C "${cwd:-.}" branch --show-current 2>/dev/null)"
jq -c --arg ev "${1:-event}" --arg reason "${2:-}" --arg ts "$(date -Is)" \
      --arg repo "$repo" --arg branch "$branch" --arg user "$USER" '
  def redact:
    gsub("(?<k>password|passwd|secret|token|api[_-]?key|accountkey|client[_-]?secret|sig)(?<s>\\s*[=:]\\s*)[^\\s&;|\"'"'"']+"; "\(.k)\(.s)***"; "i")
    | gsub("(?<k>--(password|secret|token|client-secret|api-key|sas-token))(?<s>\\s+)[^\\s&;|\"'"'"']+"; "\(.k)\(.s)***"; "i")
    | gsub("(?<k>bearer\\s+)[A-Za-z0-9._~+/=-]+"; "\(.k)***"; "i");
  {ts: $ts, ev: $ev, user: $user, session: .session_id, repo: $repo, branch: $branch, cwd: .cwd,
   tool: .tool_name,
   cmd: (.tool_input.command // null | if . then redact else . end),
   file: (.tool_input.file_path // .tool_input.notebook_path // null),
   prompt_chars: (.prompt // null | if . then length else . end),
   reason: (if $reason == "" then null else $reason end)}
  | with_entries(select(.value != null and .value != ""))' <<<"$input" >> "$dir/$(date +%F).jsonl" 2>/dev/null
exit 0
