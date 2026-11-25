#!/usr/bin/env bash
#
# tests/supply-tools.sh — third-party tools and tmux plugins are pinned and verified (WS-SEC-016), offline, in a
# temporary HOME with a local mirror of the release downloads and local git repositories as plugin upstreams:
#   ws-tools     installs a GitHub binary only when its sha256 equals the pin of ws-tools.lock; a signed upstream
#                (cosign) is verified, with the pinned cosign installed first when missing; a mismatch fails closed and
#                WS_TOOLS_ALLOW_UNVERIFIED=1 is logged and lands in the audit hash chain; checkov is installed at its
#                pinned version; `install gate` brings the git gate's scanners
#   ws-plugins   clones each plugin at its plugins.lock commit, puts back a changed file, moves out a plugin with an
#                added script or a rewritten history, keeps an untouched checkout when upstream is unreachable, and
#                verify fails on an unpinned @plugin; the override is audited; install.sh uses it instead of TPM
#   bump-pinned  .github/scripts/bump-pinned.sh brings mcp-servers.lock.json and the AI-BOM in step with a package-lock
#                a Dependabot branch changed; the SBOM carries the pins
#
# Usage: bash tests/supply-tools.sh      (exit 0 = all OK; needs git, jq, unzip and python3)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }
B="$ROOT/files/home/.local/bin"
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig" CLAUDE_AUDIT_DIR="$T/audit"
unset XDG_STATE_HOME XDG_CONFIG_HOME
mkdir -p "$HOME/.local/bin" "$HOME/.claude/hooks" "$T/fb" "$T/gh"
cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"; chmod 755 "$HOME/.claude/hooks/audit.sh"
git config --global user.name ci; git config --global user.email ci@example.invalid; git config --global init.defaultBranch main
# Only the system folders and the fakes: no cosign, osv-scanner or checkov of this machine.
export PATH="$HOME/.local/bin:$T/fb:/usr/bin:/bin"
printf '#!/bin/sh\necho "$@" >> "%s/pipx.log"\n' "$T" > "$T/fb/pipx"
printf '#!/bin/sh\necho "$@" >> "%s/cosign.log"\nexit "$(cat %s/cosign-rc 2>/dev/null || echo 0)"\n' "$T" "$T" > "$T/fb/cosign.fake"
chmod 755 "$T/fb/pipx" "$T/fb/cosign.fake"

# The mirror: <repo>/releases/download/<version>/<asset>, served as file://.
rel() { mkdir -p "$T/gh/$1/releases/download/$2"; printf '%s' "$T/gh/$1/releases/download/$2"; }
OSV="$(rel google/osv-scanner v2.7.1)"; printf '#!/bin/sh\necho osv-scanner 2.7.1\n' > "$OSV/osv-scanner_linux_amd64"
TFL="$(rel terraform-linters/tflint v0.66.0)"; mkdir -p "$T/z"; printf '#!/bin/sh\necho TFLint 0.66.0\n' > "$T/z/tflint"
(cd "$T/z" && zip -q "$TFL/tflint_linux_amd64.zip" tflint 2>/dev/null) || python3 -c "
import sys, zipfile; z = zipfile.ZipFile(sys.argv[1], 'w'); z.write(sys.argv[2], 'tflint'); z.close()" "$TFL/tflint_linux_amd64.zip" "$T/z/tflint"
COS="$(rel sigstore/cosign v3.1.4)"; cp "$T/fb/cosign.fake" "$COS/cosign-linux-amd64"
sha() { sha256sum "$1" | cut -d' ' -f1; }
(cd "$TFL" && sha256sum tflint_linux_amd64.zip > checksums.txt && echo sig > checksums.txt.keyless.sig && echo pem > checksums.txt.pem)
mklock() {
  {
    printf 'osv-scanner v2.7.1 github:google/osv-scanner osv-scanner_linux_amd64 %s none\n' "$(sha "$OSV/osv-scanner_linux_amd64")"
    printf 'tflint v0.66.0 github:terraform-linters/tflint tflint_linux_amd64.zip %s cosign:checksums.txt\n' "$(sha "$TFL/tflint_linux_amd64.zip")"
    printf 'cosign v3.1.4 github:sigstore/cosign cosign-linux-amd64 %s none\n' "$(sha "$COS/cosign-linux-amd64")"
    printf 'checkov 3.4.5 pypi:checkov - - none\n'
  } > "$T/tools.lock"
}
mklock
export WS_TOOLS_LOCK="$T/tools.lock" WS_TOOLS_GH_BASE="file://$T/gh" WS_TOOLS_NO_INVENTORY=1
tools() { bash "$B/ws-tools" install --force "$@" > "$T/out" 2>&1; }

echo "1) ws-tools: pinned binaries"
check "a binary whose sha256 matches the pin is installed" bash -c "$(declare -f tools); B='$B' T='$T'; tools osv-scanner && test -x '$HOME/.local/bin/osv-scanner'"
rm -f "$HOME/.local/bin/osv-scanner"; echo tampered >> "$OSV/osv-scanner_linux_amd64"
check "a binary that differs from its pin is refused (exit 1)" not tools osv-scanner
check "  nothing is installed" not test -e "$HOME/.local/bin/osv-scanner"
check "  and the message names the override" grep -q 'WS_TOOLS_ALLOW_UNVERIFIED' "$T/out"
check "WS_TOOLS_ALLOW_UNVERIFIED=1 installs it anyway" bash -c "WS_TOOLS_ALLOW_UNVERIFIED=1 bash '$B/ws-tools' install --force osv-scanner && test -x '$HOME/.local/bin/osv-scanner'"
check "  logged in the overrides log" grep -q 'osv-scanner' "$HOME/.local/state/ws-tools/overrides.log"
check "  and in the audit log, chained" bash -c "grep -h '\"ev\":\"override\"' '$T'/audit/*.jsonl | grep -q 'ws-tools unverified osv-scanner' && python3 '$B/ws-audit' --verify-log '$T/audit'"
rm -f "$HOME/.local/bin/osv-scanner"

echo "2) ws-tools: a signed upstream (cosign)"
echo 0 > "$T/cosign-rc"
check "the pinned cosign is installed first when missing, then tflint" bash -c "$(declare -f tools); B='$B' T='$T'; tools tflint && test -x '$HOME/.local/bin/cosign' && test -x '$HOME/.local/bin/tflint'"
check "  cosign checked the checksum file against GitHub Actions of the same repository" \
  bash -c "grep -q 'verify-blob' '$T/cosign.log' && grep -q 'token.actions.githubusercontent.com' '$T/cosign.log' && grep -q 'terraform-linters/tflint/' '$T/cosign.log'"
rm -f "$HOME/.local/bin/tflint"; echo 1 > "$T/cosign-rc"
check "a signature that does not verify is refused" not tools tflint
check "  nothing is installed" not test -e "$HOME/.local/bin/tflint"
echo 0 > "$T/cosign-rc"; echo "0000  tflint_linux_amd64.zip" > "$TFL/checksums.txt"
check "a signed checksum file that does not list the pin is refused" not tools tflint
check "checkov is installed at its pinned version" bash -c "$(declare -f tools); B='$B' T='$T'; tools checkov && grep -qx 'install checkov==3.4.5' '$T/pipx.log'"
check "ws-tools install gate asks for the three scanners" bash -c "rm -f '$T/pipx.log'; bash '$B/ws-tools' install --force gate >/dev/null 2>&1; grep -q 'checkov==3.4.5' '$T/pipx.log'"
check "the kit's lock pins every GitHub binary ws-tools installs, with a 64-hex sha256" bash -c "
  for n in osv-scanner tflint k9s hadolint starship agg cosign; do
    awk -v n=\$n '\$1 == n && \$3 ~ /^github:/ && \$5 ~ /^[0-9a-f]{64}\$/ { f = 1 } END { exit !f }' '$ROOT/files/home/.local/lib/ws-tools.lock' || exit 1; done"
check "no installer downloads a moving latest release" not grep -q 'releases/latest' "$B/ws-tools"

echo "3) ws-plugins: tmux plugins pinned by commit"
up() { git init -q "$T/up/$1"; for i in 1 2; do echo "v$i" > "$T/up/$1/main.sh"; printf 'run main\n' > "$T/up/$1/$1.tmux"
       git -C "$T/up/$1" add -A; git -C "$T/up/$1" commit -qm "c$i"; done; }
up plug-a; up plug-b
A1="$(git -C "$T/up/plug-a" rev-parse HEAD~1)"; B2="$(git -C "$T/up/plug-b" rev-parse HEAD)"
printf '# test\nplug-a file://%s %s\nplug-b file://%s %s\n' "$T/up/plug-a" "$A1" "$T/up/plug-b" "$B2" > "$T/plugins.lock"
printf "set -g @plugin 'x/plug-a'\nset -g @plugin 'y/plug-b'\n" > "$T/tmux.conf"
export WS_PLUGINS_LOCK="$T/plugins.lock" WS_PLUGINS_DIR="$T/plugins" WS_PLUGINS_CONF="$T/tmux.conf"
P="$B/ws-plugins"
check "apply clones each plugin" bash "$P" apply
check "  at its pinned commit, not the branch tip" test "$(git -C "$T/plugins/plug-a" rev-parse HEAD)" = "$A1"
check "verify passes" bash "$P" verify
echo evil > "$T/plugins/plug-a/main.sh"
check "a changed file fails verify" not bash "$P" verify
check "  apply puts the pinned file back" bash -c "bash '$P' apply && grep -qx v1 '$T/plugins/plug-a/main.sh' && bash '$P' verify"
echo 'run-shell evil' > "$T/plugins/plug-b/extra.tmux"
check "an added script fails verify" not bash "$P" verify
check "  apply moves the plugin out (tmux does not load it)" bash -c "! bash '$P' apply; ! test -e '$T/plugins/plug-b' && ls '$HOME/.local/share/ws-kit/plugins-quarantine/' | grep -q '^plug-b\.'"
check "  and apply clones it again clean" bash -c "bash '$P' apply && bash '$P' verify"
echo 'run-shell evil' > "$T/plugins/plug-b/extra.tmux"
check "WS_PLUGINS_ALLOW_UNPINNED=1 keeps it" bash -c "WS_PLUGINS_ALLOW_UNPINNED=1 bash '$P' apply && test -e '$T/plugins/plug-b/extra.tmux'"
check "  logged and in the audit log" bash -c "grep -q plug-b '$HOME/.local/state/ws-plugins/overrides.log' && grep -qh 'ws-plugins unpinned plug-b' '$T'/audit/*.jsonl"
rm -f "$T/plugins/plug-b/extra.tmux"
sed -i "s/ $A1\$/ 0123456789abcdef0123456789abcdef01234567/" "$T/plugins.lock"
check "a pin upstream no longer has (rewritten history) is refused and moved out" bash -c "! bash '$P' apply; ! test -e '$T/plugins/plug-a'"
# A checkout made before the pin moved to a newer upstream commit, and upstream now out of reach.
git clone -q "$T/up/plug-a" "$T/plugins/plug-a"
echo v3 > "$T/up/plug-a/main.sh"; git -C "$T/up/plug-a" commit -qam c3; A3="$(git -C "$T/up/plug-a" rev-parse HEAD)"
printf '# test\nplug-a file://%s/gone %s\nplug-b file://%s %s\n' "$T/up" "$A3" "$T/up/plug-b" "$B2" > "$T/plugins.lock"
check "upstream unreachable: an untouched checkout is kept (exit 1, a warning)" bash -c "! bash '$P' apply > '$T/p.out'; test -d '$T/plugins/plug-a' && grep -q 'not reachable' '$T/p.out'"
printf "set -g @plugin 'z/plug-c'\n" >> "$T/tmux.conf"
check "an @plugin of tmux.conf missing from the lock fails verify" bash -c "bash '$P' verify | grep -q 'plug-c.*not in plugins.lock'"
check "the kit's plugins.lock pins every @plugin of .tmux.conf by a 40-hex commit" bash -c "
  WS_PLUGINS_LOCK='$ROOT/files/home/.config/tmux-claude/plugins.lock' WS_PLUGINS_CONF='$ROOT/files/home/.tmux.conf' \
    WS_PLUGINS_DIR='$T/none' bash '$P' verify | grep -q 'not in plugins.lock' && exit 1
  awk '!/^#/ && NF >= 3 && \$3 !~ /^[0-9a-f]{40}\$/ { exit 1 }' '$ROOT/files/home/.config/tmux-claude/plugins.lock'"
check "install.sh applies the pins instead of TPM's install_plugins" bash -c "grep -q 'ws-plugins\" apply' '$ROOT/install.sh' && ! grep -q 'install_plugins\"' '$ROOT/install.sh'"
check "ws-update re-applies the pins instead of update_plugins" grep -q 'ws-plugins apply' "$B/ws-update"

echo "4) bump-pinned.sh and the SBOM"
K="$T/kit"; mkdir -p "$K"; git -C "$ROOT" ls-files -co --exclude-standard -z | (cd "$ROOT" && tar --null -T - -cf -) | tar -C "$K" -xf -
L="$K/files/home/.local/lib/ws-npm/agent-browser"
jq '.dependencies["agent-browser"] = "9.9.9"' "$L/package.json" > "$T/p" && cat "$T/p" > "$L/package.json"
jq '.packages[""].dependencies["agent-browser"] = "9.9.9" | .packages["node_modules/agent-browser"].version = "9.9.9"
    | .packages["node_modules/agent-browser"].integrity = "sha512-TEST"' "$L/package-lock.json" > "$T/p" && cat "$T/p" > "$L/package-lock.json"
check "without a version it syncs the lock a Dependabot branch changed" bash -c "BUMP_NO_TESTS=1 bash '$K/.github/scripts/bump-pinned.sh' agent-browser"
check "  mcp-servers.lock.json has the new version and integrity" jq -e '.tools["agent-browser"] | .version == "9.9.9" and .integrity == "sha512-TEST"' "$K/files/mcp-servers.lock.json"
check "  and the AI-BOM was regenerated" grep -q 'agent-browser@9.9.9' "$K/docs/governance/AI-BOM.md"
jq '.dependencies["agent-browser"] = "9.9.10-beta.1"' "$L/package.json" > "$T/p" && cat "$T/p" > "$L/package.json"
jq '.packages["node_modules/agent-browser"].version = "9.9.10-beta.1"' "$L/package-lock.json" > "$T/p" && cat "$T/p" > "$L/package-lock.json"
check "a prerelease without its reason in the lock is refused" not env BUMP_NO_TESTS=1 bash "$K/.github/scripts/bump-pinned.sh" agent-browser
check "package.json and package-lock.json that disagree are refused" bash -c "
  jq '.dependencies[\"agent-browser\"] = \"1.0.0\"' '$L/package.json' > '$T/p' && cat '$T/p' > '$L/package.json'
  ! BUMP_NO_TESTS=1 bash '$K/.github/scripts/bump-pinned.sh' agent-browser"
python3 -I "$ROOT/.github/scripts/sbom.py" -o "$T/sbom.json" 2>/dev/null
check "the SBOM marks every tmux plugin pinned, with its commit" \
  jq -e '[.components[] | select(.properties[]? | .name == "ws:installedBy" or .name == "installedBy") | select(.purl | startswith("pkg:github/")) | select(.name | test("tpm|tmux-|extrakto"))] | length >= 4 and all(.version | test("^[0-9a-f]{40}$"))' "$T/sbom.json"
check "  and the ws-tools binaries with their sha256" jq -e '[.components[] | select(.name == "osv-scanner")][0].hashes[0].content | test("^[0-9a-f]{64}$")' "$T/sbom.json"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
