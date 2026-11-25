# shellcheck shell=bash
#
# ws-lang.sh — language selector library. Loaded (sourced) by the hooks, `cr`, ws-telegram and `ws-lang`.
#
# The kit's interface is English only. What depends on the language is what the kit RECOGNISES in text typed by
# you or written by Claude, and the language Claude is asked to write in:
#   en (default)  English patterns                      · Claude writes reports and handoffs in English
#   es            English AND Spanish patterns (mixed)  · Claude writes them in Spanish
# Setting: ~/.config/tmux-claude/lang (one word); WS_LANG=en|es in the environment overrides it; anything else,
# or no file, means en. Every consumer reads it each time: changing it needs no restart.
# Packs: ~/.local/lib/ws-lang/en.conf and es.conf (key=value, the value verbatim up to the end of the line).
#
# Cheap on purpose (the hooks run it on every Claude event): only bash builtins, no process is started.
#   ws_lang              prints en|es
#   ws_lang_name         prints English|Spanish
#   ws_lang_pat KEY      prints the English value of KEY; with es, "<en>|<es>" when the Spanish pack has the key
#                        (only one side when the other is missing; no output and exit 1 when neither has it)
#   ws_lang_list KEY     same lookup, joined with a space instead of "|" (word lists)
#   ws_lang_var VAR KEY [SEP]   same lookup into the variable VAR, without a subshell (SEP defaults to "|");
#                        VAR is left empty and the exit status is 1 when neither pack has the key
# Python consumers carry a small reader of the same files; this file is the reference implementation.

WS_LANG_DIR="${WS_LANG_DIR:-$HOME/.local/lib/ws-lang}"
WS_LANG_FILE="${WS_LANG_FILE:-$HOME/.config/tmux-claude/lang}"

# _ws_lang — leaves the language code in REPLY.
_ws_lang() {
  local l="${WS_LANG:-}" _rest
  l="${l,,}"
  if [[ "$l" != en && "$l" != es ]]; then
    l=""
    [[ -r "$WS_LANG_FILE" ]] && { read -r l _rest < "$WS_LANG_FILE" || true; }
    l="${l,,}"
  fi
  if [[ "$l" == es ]]; then REPLY=es; else REPLY=en; fi
}

# _ws_lang_lookup FILE KEY — value of KEY in a pack, in REPLY; 1 if the pack or the key is missing or empty.
_ws_lang_lookup() {
  local line
  REPLY=""
  [[ -r "$1" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$2="* ]]; then
      REPLY="${line#*=}"; REPLY="${REPLY%$'\r'}"
      [[ -n "$REPLY" ]]; return
    fi
  done < "$1"
  return 1
}

# _ws_lang_join KEY SEP — "<en><SEP><es>" in REPLY (see ws_lang_pat); 1 when neither pack has the key.
_ws_lang_join() {
  local en="" es="" l
  _ws_lang; l="$REPLY"
  if _ws_lang_lookup "$WS_LANG_DIR/en.conf" "$1"; then en="$REPLY"; fi
  if [[ "$l" == es ]] && _ws_lang_lookup "$WS_LANG_DIR/es.conf" "$1"; then es="$REPLY"; fi
  if [[ -n "$en" && -n "$es" ]]; then REPLY="$en$2$es"; else REPLY="$en$es"; fi
  [[ -n "$REPLY" ]]
}

ws_lang()      { _ws_lang; printf '%s\n' "$REPLY"; }
ws_lang_name() { _ws_lang; if [[ "$REPLY" == es ]]; then echo Spanish; else echo English; fi; }
ws_lang_pat()  { _ws_lang_join "${1:-}" "|" && printf '%s\n' "$REPLY"; }
ws_lang_list() { _ws_lang_join "${1:-}" " " && printf '%s\n' "$REPLY"; }
ws_lang_var() {
  if _ws_lang_join "${2:-}" "${3-|}"; then printf -v "$1" '%s' "$REPLY"; else printf -v "$1" '%s' ""; return 1; fi
}
