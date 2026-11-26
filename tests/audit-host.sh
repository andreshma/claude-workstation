#!/usr/bin/env bash
#
# tests/audit-host.sh — ws-audit's host checks (WS-SEC-019, -020, -021, -023, -029), calling host_hygiene() on a
# temporary HOME with simulated ss, dpkg-query, apt, pgrep, timedatectl, powershell.exe and cmd.exe:
#   patching     only the security pocket counts; unattended-upgrades must be installed and enabled
#   permissions  a group-writable home fails, a loose umask warns, the audit and swarm folders must be 0700
#   listeners    a socket bound beyond loopback warns, loopback ones pass; a running sshd warns; the WSL networking
#                mode is read from the Windows .wslconfig
#   clock        a skew against the Windows clock over 5 s warns; without interop, timedatectl is used
#   logging      journald persistence and auditd are reported (auditd as an accepted risk)
#
# Usage: bash tests/audit-host.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
export HOME="$T/home" WS_APT_CONF="$T/apt"; mkdir -p "$HOME/.claude/audit" "$HOME/.local/share/tmux-swarm" "$T/apt" "$T/bin" "$T/win"
chmod 755 "$HOME"; chmod 700 "$HOME/.claude/audit" "$HOME/.local/share/tmux-swarm"
B="$T/bin"
fake() { printf '#!/bin/bash\n%s\n' "$2" > "$B/$1"; chmod 755 "$B/$1"; }
fake apt 'printf "openssl/noble-security 3.0 amd64 [upgradable]\nvim/noble-updates 9 amd64 [upgradable]\nlibsecurity-x/noble-updates 1 amd64 [upgradable]\n"'
fake dpkg-query 'printf "install ok installed"'
fake ss 'printf "tcp LISTEN 0 128 127.0.0.1:14318 0.0.0.0:*\ntcp LISTEN 0 128 0.0.0.0:8080 0.0.0.0:*\ntcp LISTEN 0 128 [::1]:9000 [::]:*\n"'
fake pgrep '[[ "$*" == *sshd* && -n "${FAKE_SSHD:-}" ]]'
fake powershell.exe 'echo "$(( $(date +%s) + ${FAKE_SKEW:-0} ))"'
fake cmd.exe 'echo "C:\\Users\\tester"'
fake wslpath "echo '$T/win'"
fake timedatectl 'echo "${FAKE_NTP:-yes}"'
printf '[wsl2]\nnetworkingMode=mirrored\n' > "$T/win/.wslconfig"
printf 'APT::Periodic::Unattended-Upgrade "1";\n' > "$T/apt/20auto-upgrades"
run() {
  env PATH="$B:$PATH" "$@" python3 -I - "$ROOT/files/home/.local/bin/ws-audit" <<'EOF'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("ws_audit", sys.argv[1])
spec = importlib.util.spec_from_loader("ws_audit", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
m.host_hygiene()
for r in m.R:
    print("\t".join((r["status"], r["what"], r["detail"], r["reco"])))
EOF
}
run > "$T/out"
check "only the security pocket counts (1 of 3 upgradable lines)" grep -q $'^warn\tpending updates from the security pocket: 1' "$T/out"
check "unattended-upgrades installed and enabled passes" grep -q $'^ok\tautomatic security updates' "$T/out"
check "a home without group or other write passes" grep -q $'^ok\tpermissions ~: 0o755' "$T/out"
check "the audit and swarm folders at 0700 pass" bash -c "grep -q \$'^ok\tpermissions ~/.claude/audit' '$T/out' && grep -q \$'^ok\tpermissions ~/.local/share/tmux-swarm' '$T/out'"
check "a listener on 0.0.0.0 warns, loopback ones do not" grep -q $'^warn\tservices listening beyond loopback: 1\ttcp 0.0.0.0:8080' "$T/out"
check "no sshd passes" grep -q $'^ok\tsshd\tnot running' "$T/out"
check "the WSL networking mode is read from .wslconfig" grep -q $'^info\tWSL networking mode: mirrored' "$T/out"
check "a clock in step with Windows passes" grep -q $'^ok\tclock skew against Windows: [0-1] s' "$T/out"
check "journald and auditd are reported" bash -c "grep -q 'journald keeps logs' '$T/out' && grep -q \$'^info\tauditd' '$T/out'"
chmod 775 "$HOME"; chmod 750 "$HOME/.claude/audit"; rm "$T/apt/20auto-upgrades"
run env FAKE_SSHD=1 FAKE_SKEW=120 > "$T/out"
check "a group-writable home fails" grep -q $'^fail\tpermissions ~: 0o775' "$T/out"
check "an audit folder readable by the group fails" grep -q $'^fail\tpermissions ~/.claude/audit: 0o750' "$T/out"
check "unattended-upgrades not enabled warns" grep -q $'^warn\tautomatic security updates' "$T/out"
check "a running sshd warns" grep -q $'^warn\tsshd\trunning' "$T/out"
check "a 2-minute clock skew warns" grep -q $'^warn\tclock skew against Windows: 1[12][0-9] s' "$T/out"
# Interop unavailable: a failing stub, not a removed one, so a real powershell.exe later in PATH (a WSL session with
# Windows interop) cannot answer in its place.
fake powershell.exe 'exit 127'
run env FAKE_NTP=no > "$T/out"
check "without interop, an unsynchronised clock warns through timedatectl" grep -q $'^warn\tclock synchronised (NTP): no' "$T/out"
chmod 755 "$HOME"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
