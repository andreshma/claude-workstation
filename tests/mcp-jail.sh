#!/usr/bin/env bash
#
# tests/mcp-jail.sh — ws-mcp-jail confines local stdio MCP servers (WS-AI-011, ADR-024), in a temporary HOME:
#   1) the bubblewrap command it builds (--print, runs anywhere): no bind of ~/.ssh, ~/.claude, the audit log, other
#      profiles' logins or the Windows drives; the state dir is the only writable place; tokens leave the environment
#   2) refusals: a Windows executable (exit 126, it cannot be confined), --ro/--rw of a denied path, an
#      AZURE_CONFIG_DIR that is not ~/.azure or a profile's, and fail-closed without a usable bubblewrap (exit 125)
#   3) live, when bubblewrap can create namespaces here: a fake MCP server answers initialize and reports what it
#      could read; it must see none of the denied files and be able to write only its state dir
#   4) install.sh's registration wraps the servers of files/mcp-servers.json that have a "jail" object, keeps the
#      opted-out ones (with their reason) unwrapped, and every local stdio server is either jailed or opted out
#
# Usage: bash tests/mcp-jail.sh      (exit 0 = all OK; the live part is skipped with the reason when bubblewrap
#        cannot create namespaces, e.g. inside another sandbox)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T="$(realpath "$T")"
PASS=0 FAIL=0 SKIP=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
skip()  { SKIP=$((SKIP+1)); echo "  skip $1"; }
not()   { ! "$@"; }

J="$ROOT/files/home/.local/bin/ws-mcp-jail"
export HOME="$T/home"; unset XDG_STATE_HOME AZURE_CONFIG_DIR CLAUDE_AUDIT_DIR
mkdir -p "$HOME/.local/lib" "$HOME/.ssh" "$HOME/.claude/audit" "$HOME/.config/ws-agent/mine/azure" \
         "$HOME/.config/ws-agent/other/azure" "$HOME/.local/share/ws-kit/npm/fake/node_modules/.bin"
cp "$ROOT/files/home/.local/lib/ws-credential-paths.txt" "$HOME/.local/lib/"
echo "PRIVATE-KEY" > "$HOME/.ssh/id_test"; echo "AUDIT" > "$HOME/.claude/audit/today.jsonl"
echo "OTHER-TOKEN" > "$HOME/.config/ws-agent/other/azure/msal_token_cache.json"
echo "MY-TOKEN" > "$HOME/.config/ws-agent/mine/azure/msal_token_cache.json"
# A fake stdio MCP server: answers initialize and reports which denied files it could read and where it could write.
S="$HOME/.local/share/ws-kit/npm/fake/node_modules/.bin/fake"
cat > "$S" <<'EOF'
#!/bin/sh
read -r _req
r=""
for f in "$HOME/.ssh/id_test" "$HOME/.claude/audit/today.jsonl" "$HOME/.config/ws-agent/other/azure/msal_token_cache.json" \
         /mnt/c/Windows/System32/drivers/etc/hosts; do
  if cat "$f" >/dev/null 2>&1; then r="$r READ:$f"; fi
done
[ -n "${AZURE_CONFIG_DIR:-}" ] && cat "$AZURE_CONFIG_DIR/msal_token_cache.json" >/dev/null 2>&1 && r="$r OWN-AZURE"
: > "$XDG_STATE_HOME/../w" 2>/dev/null && r="$r WROTE-STATE"
: > "$HOME/escape" 2>/dev/null && [ -e "$HOME/escape" ] && r="$r WROTE-HOME"
[ -n "${GH_TOKEN:-}" ] && r="$r TOKEN"
[ -e /run/WSL ] && r="$r WSL-INTEROP"
printf '{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"fake"},"report":"%s"}}\n' "$r"
EOF
chmod 755 "$S"

echo "1) the bubblewrap command"
out="$(GH_TOKEN=secret AZURE_CONFIG_DIR="$HOME/.config/ws-agent/mine/azure" bash "$J" --print --name fake --net --azure-config -- "$S")"
check "it runs the server under bwrap with every namespace unshared" grep -q '^bwrap --unshare-all --die-with-parent' <<<"$out"
check "  and drops every capability" grep -qF -- '--cap-drop ALL' <<<"$out"
check "no bind of ~/.ssh" not grep -qF -- "$HOME/.ssh" <<<"$out"
check "no bind of ~/.claude (conversations, logins, the audit log)" not grep -qF -- "$HOME/.claude" <<<"$out"
check "no bind of another profile's logins" not grep -qF -- "ws-agent/other" <<<"$out"
check "the tab's own AZURE_CONFIG_DIR is bound read-write with --azure-config" \
  grep -qF -- "--bind $HOME/.config/ws-agent/mine/azure $HOME/.config/ws-agent/mine/azure" <<<"$out"
check "no bind of a Windows drive" not grep -qE -- '--(ro-)?bind /mnt/[a-z]( |/)' <<<"$out"
check "/run is a private tmpfs (no WSL interop or agent sockets)" grep -qF -- '--tmpfs /run' <<<"$out"
check "the only read-write binds are its state dir and the Azure config" \
  bash -c "[[ \$(grep -oE -- '--bind [^ ]+' <<<'$out' | sort -u | wc -l) == 2 ]] && grep -qF -- '--bind $HOME/.local/state/ws-mcp/fake' <<<'$out'"
check "tokens are removed from the environment" grep -qF -- '--unsetenv GH_TOKEN' <<<"$out"
check "the network is shared only with --net" bash -c "grep -qF -- '--share-net' <<<'$out' && ! bash '$J' --print -- '$S' | grep -qF -- '--share-net'"

echo "2) refusals"
printf 'MZ\x90\x00' > "$T/server.exe"; chmod 755 "$T/server.exe"
bash "$J" -- "$T/server.exe" 2>"$T/err"; rc=$?
check "a Windows executable is refused (exit 126), never run unconfined" test "$rc" -eq 126
check "  and the message says why and what to do" grep -q 'bubblewrap cannot confine a Windows process' "$T/err"
check "--ro ~/.ssh is refused" not bash "$J" --print --ro "$HOME/.ssh" -- "$S"
check "--rw of the whole home is refused" not bash "$J" --print --rw "$HOME" -- "$S"
check "--ro of a Windows drive is refused" bash -c "[[ ! -d /mnt/c ]] || ! bash '$J' --print --ro /mnt/c/Users -- '$S'"
check "--ro of the audit log is refused" not bash "$J" --print --ro "$HOME/.claude/audit" -- "$S"
check "an AZURE_CONFIG_DIR outside ~/.azure and the profiles is refused" \
  not env AZURE_CONFIG_DIR="$HOME/.ssh" bash "$J" --print --azure-config -- "$S"
mkdir -p "$T/nobwrap"; printf '#!/bin/sh\nexit 1\n' > "$T/nobwrap/bwrap"; chmod 755 "$T/nobwrap/bwrap"
PATH="$T/nobwrap:$PATH" bash "$J" -- "$S" </dev/null 2>"$T/err"; rc=$?
check "without a usable bubblewrap the server is not started (exit 125, fail closed)" test "$rc" -eq 125
check "  and the message says so" grep -q 'NOT started: fail closed' "$T/err"

echo "3) live: a fake MCP server inside the jail"
if bash "$J" --probe; then
  rep="$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    | GH_TOKEN=secret AZURE_CONFIG_DIR="$HOME/.config/ws-agent/mine/azure" bash "$J" --name fake --azure-config -- "$S" 2>"$T/err")"
  check "the server starts and answers initialize over stdio" grep -q '"serverInfo"' <<<"$rep"
  check "it cannot read ~/.ssh, the audit log, another profile's logins or C:" not grep -q 'READ:' <<<"$rep"
  check "it reads its own profile's Azure config" grep -q 'OWN-AZURE' <<<"$rep"
  check "it writes its state dir" grep -q 'WROTE-STATE' <<<"$rep"
  check "  and a write to HOME stays inside the jail" bash -c "[[ ! -e '$HOME/escape' ]]"
  check "no token reaches it" not grep -q 'TOKEN' <<<"$rep"
  check "no WSL interop socket inside" not grep -q 'WSL-INTEROP' <<<"$rep"
else
  skip "bubblewrap cannot create namespaces here (nested sandbox?): run tests/mcp-jail.sh outside it"
fi

echo "4) registration (install.sh)"
# shellcheck source=/dev/null
want() { bash -c 'source "$1/lib.sh"; mcp_want "$2" "$3" "$4"' _ "$ROOT" "$ROOT/files/mcp-servers.json" "$1" "$HOME"; }
check "lib.sh has mcp_want" grep -q '^mcp_want()' "$ROOT/lib.sh"
w="$(want azure)"
check "azure is registered through ws-mcp-jail with the network and its Azure config" \
  jq -e --arg h "$HOME" '.command == ($h + "/.local/bin/ws-mcp-jail") and (.args | index("--net")) and (.args | index("--azure-config")) and (.args[(.args | index("--")) + 1] | endswith("azmcp"))' <<<"$w"
check "  and the jail keys are not passed to claude mcp add-json" jq -e 'has("jail") or has("jailOptOut") | not' <<<"$w"
check "mempalace stays unwrapped: a Windows executable, opted out with a reason" \
  bash -c "jq -e '.command | endswith(\"mempalace-mcp.exe\")' <<<'$(want mempalace)' && jq -e '.mempalace.jail == false and (.mempalace.jailOptOut | length > 20)' '$ROOT/files/mcp-servers.json'"
check "every stdio server is jailed or opted out with a reason" \
  jq -e '[to_entries[] | select((.value.type // "stdio") == "stdio") | select((.value.jail | type) != "object" and ((.value.jail == false and (.value.jailOptOut // "" | length) > 0) | not))] | length == 0' "$ROOT/files/mcp-servers.json"
jq -n --argjson a "$(want azure)" '{mcpServers: {azure: $a}}' > "$T/claude.json"
m="$(bash -c 'source "$1/lib.sh"; mcp_unwrap_merge "$2" "$3"' _ "$ROOT" "$ROOT/files/mcp-servers.json" "$T/claude.json")"
check "export.sh unwraps a jailed registration back to the server's command and keeps the jail keys" \
  jq -e --slurpfile k "$ROOT/files/mcp-servers.json" '.azure == $k[0].azure' <<<"$m"
check "HTTP servers carry no jail key" jq -e '[.[] | select(.type == "http") | select(has("jail"))] | length == 0' "$ROOT/files/mcp-servers.json"
if command -v shellcheck >/dev/null; then check "shellcheck ws-mcp-jail" shellcheck -S warning "$J"; fi

printf '\n%d ok, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
(( FAIL == 0 ))
