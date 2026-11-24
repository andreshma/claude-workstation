#!/usr/bin/env bash
#
# ws-trazas.sh — Claude Code hook for almost every event: one JSON line per event, to mine later
# (estimation per ticket, bottlenecks, human wait, cost per type of work). ADR-008, phase F2.
#
# What it stores (never the content: no prompts, no full commands, no files, no outputs):
#   herramienta  (PostToolUse/Failure) tool, MCP server and method, summarized action, duration, wait for your
#                approval within that duration, ok/error type, input and output bytes, lines +/− and extension
#                (Edit/Write), programs on the Bash line, skill, subagent type and model, permission mode.
#                Summarized action: Bash → program and subcommand («git commit»); Edit/Write/Read → path relative to
#                the repo; WebFetch → domain; Task/Agent → subagent type; MCP → method; Skill → name.
#   prompt       (UserPromptSubmit) characters, words, «/x» command if it is one, whether it is a question, has code.
#   turno        (Stop/StopFailure) duration of the turn since your prompt.
#   aviso        (Notification) type (permission, inactivity…) and the tool asking for permission.
#   denegado     (PermissionDenied) tool and action.
#   subagente    (SubagentStart/Stop) type and duration.
#   compactacion (PreCompact) manual/auto and size of the transcript.
#   sesion       (SessionStart/End) source or reason, initial commit, uncommitted files; on close: commits made and
#                lines +/− since the start (diff against the initial commit).
# Common: ts, ts_ms, sesion, proyecto, rama, ticket (from the branch: ABC-123).
# Destination: ~/.local/share/ws-telemetria/trazas/YYYY-MM-DD.jsonl (0700). ws-telemetria compresses those older
# than 35 days and deletes those older than 13 months. Silent; always exit 0 (it never blocks Claude).
set -uo pipefail
entrada="$(cat)"
DIR="${WS_TRAZAS_DIR:-$HOME/.local/share/ws-telemetria/trazas}"
RUN="${XDG_RUNTIME_DIR:-/tmp}/ws-trazas-$(id -u)"
mkdir -p "$DIR" "$RUN/t" "$RUN/s" 2>/dev/null && chmod 700 "$DIR" "$RUN" 2>/dev/null
ahora="$(date +%s%3N)"
limpio() { printf '%s' "${1//[^A-Za-z0-9_-]/}"; }

IFS=$'\x1f' read -r ev tuid ses cwd ntipo agente < <(jq -r '[.hook_event_name // "", .tool_use_id // "", .session_id // "",
  .cwd // "", .notification_type // "", .agent_id // ""] | join("\u001f")' <<<"$entrada" 2>/dev/null)
ses="$(limpio "${ses:-s}")"; S="$RUN/s/$ses"

# Timestamps (no trace written)
case "$ev" in
  PreToolUse) printf '%s' "$ahora" > "$RUN/t/$(limpio "${tuid:-$ses}")"; exit 0 ;;
  "") exit 0 ;;
esac

git_() { GIT_OPTIONAL_LOCKS=0 timeout "${T_GIT:-1}" git -C "${cwd:-.}" "$@" 2>/dev/null; }
rama="$(git_ branch --show-current || true)"
raiz="$(git_ rev-parse --show-toplevel || echo "$cwd")"
leer() { cat "$1" 2>/dev/null || true; }
extra='{}'

case "$ev" in
  PostToolUse|PostToolUseFailure)
    m="$RUN/t/$(limpio "${tuid:-$ses}")"; ini="$(leer "$m")"; rm -f "$m"
    esp="$(leer "$S.espera")"; dur=""; espera=""
    [[ -n "$ini" ]] && dur=$(( ahora - ini ))
    # If approval was requested after the tool started, that time was yours, not the tool's.
    if [[ -n "$esp" && -n "$ini" ]] && (( esp >= ini )); then espera=$(( ahora - esp )); rm -f "$S.espera"; fi
    extra="$(jq -nc --arg d "$dur" --arg e "$espera" '{dur_ms: ($d | tonumber? // null), espera_ms: ($e | tonumber? // null)}')" ;;
  UserPromptSubmit)
    printf '%s' "$ahora" > "$S.turno"; rm -f "$S.espera" ;;
  Stop|StopFailure)
    ini="$(leer "$S.turno")"; rm -f "$S.turno" "$S.espera"
    [[ -n "$ini" ]] && extra="{\"dur_ms\":$(( ahora - ini ))}" ;;
  Notification)
    [[ "$ntipo" =~ permission|elicitation|needs_input ]] && printf '%s' "$ahora" > "$S.espera" ;;
  SubagentStart)
    printf '%s' "$ahora" > "$S.sub-$(limpio "$agente")" ;;
  SubagentStop)
    f="$S.sub-$(limpio "$agente")"; ini="$(leer "$f")"; rm -f "$f"
    [[ -n "$ini" ]] && extra="{\"dur_ms\":$(( ahora - ini ))}" ;;
  PreCompact)
    tp="$(jq -r '.transcript_path // empty' <<<"$entrada")"
    extra="{\"transcripcion_bytes\":$(stat -c %s "$tp" 2>/dev/null || echo null)}" ;;
  SessionStart)
    sha="$(T_GIT=3 git_ rev-parse HEAD || true)"     # git is slow on /mnt/c: with 1 s the starting commit was missed
    sucios="$(T_GIT=2 git_ status --porcelain | wc -l)"
    [[ -n "$sha" ]] && printf '%s %s' "$sha" "$ahora" > "$S.git"
    extra="$(jq -nc --arg s "${sha:0:12}" --arg n "$sucios" '{commit: $s, sin_commit: ($n | tonumber? // 0)}')" ;;
  SessionEnd)
    read -r sha ini < <(leer "$S.git"); rm -f "$S.git" "$S".sub-* "$S.turno" "$S.espera"
    if [[ -n "${sha:-}" ]]; then
      n="$(git_ rev-list --count "$sha..HEAD" || echo 0)"
      st="$(T_GIT=3 git_ diff --shortstat "$sha" || true)"
      extra="$(jq -nc --arg n "$n" --arg st "$st" --arg i "${ini:-}" --arg a "$ahora" '{commits: ($n | tonumber? // 0),
        archivos: (($st | capture("(?<x>[0-9]+) files? changed").x // "0") | tonumber),
        lineas_mas: (($st | capture("(?<x>[0-9]+) insertion").x // "0") | tonumber),
        lineas_menos: (($st | capture("(?<x>[0-9]+) deletion").x // "0") | tonumber),
        dur_ms: (if $i == "" then null else (($a | tonumber) - ($i | tonumber)) end)}')"
    else
      # Without the starting commit (the session resumed with another id or git did not answer in time): take the time
      # of the first message of the conversation and count the commits and lines since then.
      tp="$(jq -r '.transcript_path // empty' <<<"$entrada" 2>/dev/null)"
      t0="$([[ -f "$tp" ]] && head -c 400000 "$tp" | jq -r 'select(.timestamp != null) | .timestamp' 2>/dev/null | head -1)"
      if [[ -n "$t0" ]]; then
        n="$(T_GIT=3 git_ rev-list --count --since="$t0" HEAD || true)"
        base="$(T_GIT=3 git_ rev-list -1 --before="$t0" HEAD || true)"
        st="$([[ -n "$base" ]] && T_GIT=3 git_ diff --shortstat "$base" || true)"
        [[ -n "$n" ]] && extra="$(jq -nc --arg n "$n" --arg st "$st" '{commits: ($n | tonumber? // 0), desde: "conversacion",
          archivos: (($st | capture("(?<x>[0-9]+) files? changed").x // "0") | tonumber),
          lineas_mas: (($st | capture("(?<x>[0-9]+) insertion").x // "0") | tonumber),
          lineas_menos: (($st | capture("(?<x>[0-9]+) deletion").x // "0") | tonumber)}')"
      fi
    fi ;;
  PermissionDenied) ;;
  *) exit 0 ;;
esac

jq -c --argjson x "$extra" --arg ts_ms "$ahora" --arg rama "$rama" --arg raiz "$raiz" --arg ev "$ev" '
  def rel(p): (p // "") as $p | if $p | startswith($raiz + "/") then ($p | ltrimstr($raiz + "/")) else ($p | split("/") | last) end;
  def lineas(s): if (s // "") == "" then 0 else ((s | split("\n") | length)) end;
  def segmentos: [splits("\\s*(&&|\\|\\||;|\\|)\\s*")] | map(select(length > 0));
  def palabras(s): [s | splits("\\s+") | select(length > 0)];
  # Program of a Bash segment: without VAR=x variables, sudo, env, timeout N, nice; base name only.
  def programa: palabras(.) | map(select(test("^[A-Za-z_][A-Za-z0-9_]*=") | not))
      | until((length == 0) or (.[0] | test("^(sudo|env|nice|time|command|exec|nohup|timeout|[0-9]+[smh]?)$") | not); .[1:]);
  def errtipo(e): (e // "" | ascii_downcase) as $e
      | if $e == "" then null elif ($e | test("timed? ?out|timeout")) then "timeout"
        elif ($e | test("permission|denied|not allowed|forbidden|403|401")) then "permiso"
        elif ($e | test("no such file|not found|enoent|does not exist|404")) then "no_existe"
        elif ($e | test("interrupt|cancel|abort")) then "interrumpido"
        elif ($e | test("network|connect|econn|dns|tls|ssl|socket")) then "red"
        elif ($e | test("syntax|parse|invalid|unexpected")) then "sintaxis"
        elif ($e | test("exit code|exited with|status [1-9]")) then "salida_no_cero"
        elif ($e | test("old_string|not unique|must read|modified since")) then "edicion" else "otro" end;
  (.tool_name // "") as $t | (.tool_input // {}) as $i | (.tool_response // null) as $r
  | ($t | if startswith("mcp__") then split("__") else null end) as $mp
  | {ts: (now | todate), ts_ms: ($ts_ms | tonumber), evento: $ev, sesion: (.session_id // ""),
     proyecto: ((.cwd // "") | split("/") | last), rama: $rama,
     ticket: (($rama | capture("(?<k>[A-Z][A-Z0-9]+-[0-9]+)").k) // ""), permiso: (.permission_mode // null),
     subagente: ((.agent_id // null) != null), agente_tipo: (.agent_type // null)}
  + (if ($ev | test("^(PostToolUse|PostToolUseFailure|PermissionDenied)$")) then
      (if $t == "Bash" then (($i.command // "") | segmentos | map(programa) | map(select(length > 0))
                              | map(select(.[0] != "cd"))) else [] end) as $segs
      # Plausible program names: lowercase, short and with few digits (a pasted token or key does not pass).
      | ($segs | map(.[0] | split("/") | last
          | select(test("^[a-z][a-z0-9._+-]{0,24}$") and ([scan("[0-9]")] | length) <= 3))) as $progs
      | {tipo: (if $ev == "PermissionDenied" then "denegado" else "herramienta" end), herramienta: $t,
         mcp: ($mp // [] | .[1]), mcp_metodo: ($mp // [] | .[2:] | join("__") | select(length > 0) // null),
         accion: (if $t == "Bash" then (if ($segs | length) == 0 then "" else
                    ([$progs[0] // ""] + (if $segs[0][1] == "-m" then $segs[0][2:3] else $segs[0][1:2] end
                      | map(select(test("^[a-z][a-z_-]{1,19}$"))))) | join(" ") end)
                  elif ($t | test("^(Edit|MultiEdit|Write|Read|NotebookEdit|NotebookRead)$")) then rel($i.file_path // $i.notebook_path)
                  elif $t == "WebFetch" then (($i.url // "") | capture("^https?://(?<h>[^/:]+)").h // "")
                  elif ($t | test("^(Task|Agent)$")) then ($i.subagent_type // "general")
                  elif $t == "Skill" then ($i.skill // $i.command // "")
                  elif $t == "SlashCommand" then (($i.command // "") | capture("^(?<c>/[A-Za-z0-9:_-]+)").c // "")
                  elif $mp then ($mp[2:] | join("__")) else "" end),
         programas: (if $t == "Bash" then ($progs | unique) else null end),
         # Commits made by this command: «git … commit» segments (with -c/-C before the subcommand), without --dry-run.
         commits: (if $t == "Bash" and $ev == "PostToolUse" then
                     ([$segs[] | select((.[0] | split("/") | last) == "git") | select(any(.[]; . == "--dry-run") | not)
                       | .[1:] | until(length == 0 or (.[0] | startswith("-") | not); if (.[0] | test("^-[cC]$")) then .[2:] else .[1:] end)
                       | select((.[0] // "") == "commit")] | length | select(. > 0) // null)
                   else null end),
         tuberia: (if $t == "Bash" then ($segs | length) else null end),
         fondo: (if $t == "Bash" then ($i.run_in_background // false) else null end),
         ext: (($i.file_path // $i.notebook_path // "") | capture("\\.(?<e>[A-Za-z0-9]{1,8})$").e // null),
         lineas_mas: (if $t == "Edit" then lineas($i.new_string) elif $t == "Write" then lineas($i.content)
                      elif $t == "MultiEdit" then ([$i.edits[]? | lineas(.new_string)] | add // 0) else null end),
         lineas_menos: (if $t == "Edit" then lineas($i.old_string)
                        elif $t == "MultiEdit" then ([$i.edits[]? | lineas(.old_string)] | add // 0) else null end),
         modelo_pedido: ($i.model // null),
         ok: ($ev == "PostToolUse" and (($r | type) != "object" or ((($r.is_error // false) or ($r.interrupted // false)) | not))),
         codigo_salida: (if ($r | type) == "object" then ($r.exit_code // $r.exitCode // null) else null end),
         error_tipo: (if $ev == "PostToolUseFailure" then errtipo(.error // ($r | tostring))
                      elif ($r | type) == "object" and ($r.is_error // false) then errtipo($r.error // $r.content // "") else null end),
         interrumpido: ((.is_interrupt // false) or (($r | type) == "object" and ($r.interrupted // false))),
         bytes_entrada: ($i | tostring | length), bytes_salida: (($r // "") | tostring | length), id: (.tool_use_id // "")}
    elif $ev == "UserPromptSubmit" then (.prompt // "") as $p
      | {tipo: "prompt", chars: ($p | length), palabras: (palabras($p) | length),
         comando: ($p | capture("^\\s*(?<c>/[A-Za-z0-9:_-]+)").c // null), pregunta: ($p | test("\\?\\s*$")),
         con_codigo: ($p | test("```")), lineas: lineas($p)}
    elif ($ev | test("^Stop")) then {tipo: "turno", fallo: ($ev == "StopFailure"),
         motivo: (.error_type // .reason // null), continuado: (.stop_hook_active // false)}
    elif $ev == "Notification" then {tipo: "aviso", aviso: (.notification_type // ""),
         herramienta: ((.message // "") | capture("permission to use (?<h>[A-Za-z0-9_]+)").h // null)}
    elif ($ev | test("^Subagent")) then {tipo: "subagente", fase: (if $ev == "SubagentStart" then "inicio" else "fin" end),
         agente: (.agent_type // null), id: (.agent_id // "")}
    elif $ev == "PreCompact" then {tipo: "compactacion", disparo: (.trigger // ""), con_instrucciones: ((.custom_instructions // "") != "")}
    elif $ev == "SessionStart" then {tipo: "sesion", fase: "inicio", origen: (.source // ""), modelo: (.model // null)}
    elif $ev == "SessionEnd" then {tipo: "sesion", fase: "fin", motivo: (.reason // "")}
    else {tipo: "otro"} end)
  + $x
  | with_entries(select(.value != null))' <<<"$entrada" >> "$DIR/$(date +%F).jsonl" 2>/dev/null || true

# Orphan timestamps: tools older than 2 h; sessions older than 3 days
find "$RUN/t" -type f -mmin +120 -delete 2>/dev/null || true
find "$RUN/s" -type f -mmin +4320 -delete 2>/dev/null || true
exit 0
