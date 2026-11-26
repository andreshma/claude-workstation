#!/usr/bin/env bash
#
# tests/tab-resources.sh — per-tab resources in the status bar (tmux-res, ADR-029) and the fixed-width bar:
#   1) formats: every field keeps its width for extreme values (0, 999 %, 0 B, 512 GiB, huge IOPS)
#   2) attribution on a synthetic /proc (WS_RES_PROC): pane trees, deduplication, a reparented process keeps its tab,
#      an unrelated process counts nowhere; CPU/IO delta math including a child reaped by its parent (counted
#      once), a process born between samples, PSS vs RSS; TCP bytes per tab (sock_diag fixture), loopback left out,
#      a socket opened between samples counted once it is mapped; GPU per tab only when the driver reports processes
#   3) the rendered panel, compact segment and tab glyph have a constant visible width whatever the values
#   4) cache format (tabs.tsv, meta.json); one sampler per server (lock + PID file), a second one exits
#   5) the status path never walks /proc: the formats only read @res_* options; tmux-fit pads and cuts by columns
#   6) on a private tmux server (-L res under the temp dir, never yours): the rendered bar is captured through a
#      second client before and after the values change: the tab list and every label stay in the same columns.
#      Where tmux cannot create its socket (Claude Code's sandbox) part 6 is skipped and says so.
# Usage: bash tests/tab-resources.sh      (exit 0 = all OK)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; T="$(realpath "$T")"
cleanup() {
  local d; for d in "$T"/tm*; do [[ -d "$d" ]] && env -u TMUX TMUX_TMPDIR="$d" tmux -L res kill-server 2>/dev/null; done
  [[ -n "${DPID:-}" ]] && kill "$DPID" 2>/dev/null
  rm -rf "$T"
}
trap cleanup EXIT
PASS=0 FAIL=0 SKIP=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not() { ! "$@"; }
B="$ROOT/files/home/.local/bin"
R="$B/tmux-res"
unset TMUX TMUX_PANE CLAUDECODE XDG_CONFIG_HOME
export HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WS_RES_HZ=100 WS_RES_PAGE=4096 LC_ALL=C.UTF-8 WS_RES_NVIDIA_SMI=none
# A plain «tmux» anywhere in this test (or in a script it runs) finds no server: never yours.
export TMUX_TMPDIR="$T/no-server"
# The status scripts keep state in /tmp by default (shared with your live bar): here everything stays in $T.
export WS_WATCH_STATE="$T/watch" WS_WATCH_BURN="$T/burn" WS_STATE_DIR="$T/wsstate"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
res() { python3 -I -B "$R" "$@"; }

echo "== 1. fixed-width formats"
fmt_is() { [[ "$(res fmt "$1" "$2")" == "[$3]" ]]; }
check "CPU 0 → '  0%'"              fmt_is cpu 0 '  0%'
check "CPU 999 → '999%'"            fmt_is cpu 999 '999%'
check "CPU 5000 is capped at 999%"  fmt_is cpu 5000 '999%'
check "RAM 0 → '  0.0G'"            fmt_is gib 0 '  0.0G'
check "RAM 512 GiB → '512.0G'"      fmt_is gib 549755813888 '512.0G'
check "RAM 5 TiB is capped"         fmt_is gib 5497558138880 '999.9G'
check "IOPS 0 → '   0'"             fmt_is ops 0 '   0'
check "IOPS 9949 → '9.9k'"          fmt_is ops 9949 '9.9k'
check "IOPS 999499 → '999k'"        fmt_is ops 999499 '999k'
check "IOPS 1e15 is capped '999T'"  fmt_is ops 1e15 '999T'
check "bytes 0 → '  0B'"            fmt_is bytes 0 '  0B'
check "bytes 1024 → '1.0K'"         fmt_is bytes 1024 '1.0K'
check "bytes 1e18 is capped"        fmt_is bytes 1e18 '999T'
widths_ok() {   # every formatted value of each kind has the same width over a sweep of magnitudes
  local k v w want
  for k in cpu:4 gib:6 ops:4 bytes:4; do
    want="${k#*:}"
    for v in 0 0.4 1 9.94 9.96 99 999 999.4 999.6 1000 1023 1024 9999 12345 99999 999999 1e6 1e7 1e9 1e12 1e15 1e20; do
      w="$(res fmt "${k%%:*}" "$v")"; w="${w#[}"; w="${w%]}"
      (( ${#w} == want )) || { echo "${k%%:*} $v → [$w]" >&2; return 1; }
    done
  done
}
check "every value of every field keeps its width (sweep 0 … 1e20)" widths_ok

echo "== 2. attribution on a synthetic /proc"
P="$T/proc"; mkdir -p "$P"
printf 'cpu 1 2 3 4\nbtime 900\n' > "$P/stat"
# mkproc pid ppid start_ticks total_ticks rss_pages [syscr syscw read_bytes write_bytes] — total goes to utime
mkproc() {
  local d="$P/$1"; mkdir -p "$d/fd"
  printf '%s (p %s) S %s 0 0 0 -1 0 0 0 0 0 %s 0 0 0 20 0 1 0 %s 0 %s 0\n' "$1" "$1" "$2" "$4" "$3" "$5" > "$d/stat"
  printf 'rchar: 0\nwchar: 0\nsyscr: %s\nsyscw: %s\nread_bytes: %s\nwrite_bytes: %s\ncancelled_write_bytes: 0\n' \
    "${6:-0}" "${7:-0}" "${8:-0}" "${9:-0}" > "$d/io"
}
pss() { printf 'Rss: 1 kB\nPss: %s kB\n' "$2" > "$P/$1/smaps_rollup"; }
sock() { ln -sf "socket:[$2]" "$P/$1/fd/$3"; }
# Tab @1: 100 (shell) → 101 (node) → 102 → 103; tab @2: 200 → 201 and 202; 300 belongs to nobody.
mkproc 100 1   10 50   1000
mkproc 101 100 20 1000 51200 100 0 0 0;  pss 101 102400
mkproc 102 101 30 300  1000  500 0 0 0
mkproc 103 102 40 10   1000
mkproc 200 1   10 5    1000
mkproc 201 200 20 100  2000
mkproc 202 200 0  7    1000
mkproc 300 1   10 9999 99999
sock 101 5001 3; sock 200 5002 5
printf 'P\t@1\t100\nP\t@2\t200\nP\t@1\t100\nC\tc1\nG\t\t\t15\t\t\t\t\toff\t\t\t2\n' > "$T/panes"
printf '5001\t1000\t1000\t0\n5002\t0\t0\t1\n5004\t50\t50\t0\n' > "$T/tcp"
export WS_RES_PROC="$P" WS_RES_PANES="$T/panes" WS_RES_TCP="$T/tcp" WS_RES_DIR="$T/state"
row() { awk -F'\t' -v w="$1" '$1 == w' "$T/out"; }
field() { row "$1" | cut -f"$2"; }
WS_RES_NOW=1000 res sample > "$T/out"
check "first sample: two tabs (a linked window counted once)"  test "$(cut -f1 "$T/out" | grep -c '^@')" -eq 2
check "first sample: no rates yet (--)"                        test "$(field @1 2)" = -
check "tab @1 has its 4 processes, tab @2 its 3"               test "$(field @1 10):$(field @2 10)" = "4:3"
# Second sample, 2 s later: 101 +200 ticks of its own; 102 ended (total 340) and 101 reaped it (cutime +340);
# 103 was reparented to 1 (subreaper) and ran 20 ticks; 104 was born at 1001 (after the previous sample) with 40 ticks;
# 202 already existed (start 0) but is new to us: a baseline, not a burst. 201 ran 10 ticks.
rm -rf "$P/102"
mkproc 101 100 20 1540 51200 2700 0 0 2097152; pss 101 102400; sock 101 5001 3
mkproc 103 1   40 30   1000
mkproc 104 101 10100 40 1000
mkproc 201 200 20 110  2000; sock 201 5003 4
printf '5001\t2098152\t1049576\t0\n5002\t9999999\t9999999\t1\n5003\t0\t4096\t0\n5004\t50\t50\t0\n' > "$T/tcp"
WS_RES_NOW=1002 res sample > "$T/out"
# @1: 101 (200 own + 340-300 of the reaped child) + 103 20 + 104 40 = 300 ticks / 2 s = 150 %
check "CPU of a tab: own + reaped child counted once + reparented + newborn = 150 %"  test "$(field @1 2)" = 150.0
check "CPU of tab @2: 10 ticks in 2 s = 5 %; the old-but-new process is a baseline"     test "$(field @2 2)" = 5.0
check "an unrelated process (300) counts in no tab"   not grep -q '9999' "$T/out"
check "the reparented process keeps its tab"          test "$(field @1 10)" = 4
# IO of @1: 101 went 100 → 2700 syscalls, of which 600 came from the reaped child last seen at 500 → 2100 / 2 s
check "IO ops/s with the reaped child counted once (1050/s)"  test "$(field @1 5)" = 1050.0
check "storage bytes/s (2 MiB in 2 s = 1 MiB/s)"              test "$(field @1 6)" = 1048576.0
# RAM: 101 PSS 100 MiB (RSS 200 MiB); the others have no smaps_rollup → RSS (1000 pages each) → «rss»
check "RAM: PSS where readable, RSS otherwise (kind says rss)" \
  test "$(field @1 3):$(field @1 4)" = "$(( 104857600 + 3 * 4096000 )):rss"
check "NET: 2 MiB up and 1 MiB down in 2 s on the tab's socket" test "$(field @1 8):$(field @1 7)" = "1048576.0:524288.0"
check "NET: loopback is left out"                                test "$(field @2 7)" = 0.0
# 5003 appeared after the previous sample on a process of @2; the socket map is refreshed at most every 6 s when
# unknown traffic shows up, and the processes that had no socket (201) are looked at again by the full map, every 20 s
# while unknown traffic remains: at 1022 it is mapped and its 4 KiB (counted from zero) land in @2 (over 20 s).
WS_RES_NOW=1010 res sample > "$T/out"
check "a socket of a process that had none is not mapped by the cheap partial map" test "$(field @2 7)" = 0.0
WS_RES_NOW=1022 res sample > "$T/out"
check "…the full map finds it and its bytes are counted from zero (4096 B over 12 s)" test "$(field @2 7)" = 341.333
check "GPU per tab is unknown (-) when the driver reports no processes" bash -c "cut -f9 '$T/out' | sort -u | grep -qx -- -"

echo "== 3. constant visible width of the rendered segments"
cat > "$T/widths.py" <<'EOF'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("tmuxres", sys.argv[1])
spec = importlib.util.spec_from_loader("tmuxres", loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)
cfg = {"cpu_warn": 80, "cpu_crit": 150, "ram_warn": 4, "ram_crit": 8}
rows = [{}, {"cpu": 0, "mem": 0, "ops": 0, "iob": 0, "rx": 0, "tx": 0, "gpu": 0},
        {"cpu": 999, "mem": 512 * 2**30, "ops": 1e15, "iob": 1e18, "rx": 1e18, "tx": 1e18, "gpu": 80 * 2**30},
        {"cpu": 5000, "mem": 7 * 2**40, "ops": 9.96, "iob": 999.6, "rx": 1023, "tx": 1024, "gpu": None},
        {"cpu": 85.4, "mem": 5 * 2**30, "ops": 12345, "iob": 3e6, "rx": None, "tx": None}]
widths = set()
for gp in (False, True):
    for r in rows:
        widths.add(tuple(len(m.visible(s)) for s in m.render(r, cfg, gp)))
print(sorted(widths))
sys.exit(0 if len(widths) == 1 and list(widths)[0][2] == 1 else 1)
EOF
check "full panel, compact segment and glyph: one width for every value" python3 -I -B "$T/widths.py" "$R"
python3 -I -B "$T/widths.py" "$R" | sed 's/^/       widths (full, compact, glyph): /'
check "the dynamic part is ASCII or single-width glyphs only" python3 -I -B -c "
import importlib.machinery,importlib.util,sys,unicodedata
l=importlib.machinery.SourceFileLoader('m','$R');s=importlib.util.spec_from_loader('m',l);m=importlib.util.module_from_spec(s);l.exec_module(m)
t=''.join(m.visible(x) for x in m.render({'cpu':150,'mem':1,'ops':1,'iob':1,'rx':1,'tx':1,'gpu':1},{'cpu_warn':80,'cpu_crit':150,'ram_warn':4,'ram_crit':8},True))
sys.exit(any(unicodedata.east_asian_width(c) in 'WF' or unicodedata.combining(c) for c in t))"
check "host GPU segment keeps its width (util 0/100, unknown)" python3 -I -B -c "
import importlib.machinery,importlib.util,sys
l=importlib.machinery.SourceFileLoader('m','$R');s=importlib.util.spec_from_loader('m',l);m=importlib.util.module_from_spec(s);l.exec_module(m)
w={len(m.visible(m.render_host_gpu(g))) for g in ({'util':0,'used':0,'total':8192},{'util':100,'used':8100,'total':8192},{'util':None,'used':None,'total':8192})}
sys.exit(len(w)!=1)"

echo "== 2b. GPU per tab when the driver reports processes"
printf '#!/bin/sh\ncase "$1" in --query-gpu*) echo "37, 3646, 8192" ;; --query-compute-apps*) echo "101, 512" ;; esac\n' > "$T/smi"
chmod 755 "$T/smi"
WS_RES_NVIDIA_SMI="$T/smi" WS_RES_NOW=1012 res sample > "$T/out"
check "GPU memory of the tab's processes (512 MiB in @1)"  test "$(field @1 9)" = 536870912
check "the other tab shows 0, not unknown"                 test "$(field @2 9)" = 0
check "host GPU line: utilisation and memory"              bash -c "grep '^host' '$T/out' | grep -q '37%.*3.6/8G'"

echo "== 4. cache and single instance"
check "tabs.tsv: versioned header and 10 columns per tab" bash -c "head -1 '$T/state/tabs.tsv' | grep -q '^# tmux-res v1' \
  && awk -F'\t' 'NR > 1 && NF != 10 { exit 1 }' '$T/state/tabs.tsv'"
check "meta.json: cost and what this machine can attribute" python3 -I -B -c "
import json,sys; m=json.load(open('$T/state/meta.json'))
sys.exit(not all(k in m for k in ('cost','net_per_tab','pss','gpu_host','gpu_per_tab','interval')))"
D2="$T/state2"; mkdir -p "$D2"
WS_RES_DIR="$D2" WS_RES_INTERVAL=0.2 python3 -I -B "$R" daemon > "$T/d1.log" 2>&1 &
DPID=$!
for _ in $(seq 1 50); do [[ -s "$D2/pid" && -s "$D2/tabs.tsv" ]] && break; sleep 0.1; done
check "the sampler writes its PID file and the cache"   test "$(cat "$D2/pid" 2>/dev/null)" = "$DPID"
WS_RES_DIR="$D2" timeout 5 python3 -I -B "$R" daemon --samples 1 > "$T/d2.log" 2>&1
check "a second sampler for the same server exits at once" grep -q 'already running' "$T/d2.log"
check "…and the PID file still names the first one"       test "$(cat "$D2/pid")" = "$DPID"
WS_RES_DIR="$D2" python3 -I -B "$R" ensure
sleep 0.5
check "ensure does not start a duplicate"   test "$(pgrep -fc "$R daemon")" -le 1
kill "$DPID"; wait "$DPID" 2>/dev/null; DPID=""
check "on SIGTERM the sampler removes its PID file" test ! -e "$D2/pid"
cnt() { local n=0 p; for p in /proc/[0-9]*; do grep -qas -- "$R" "$p/cmdline" && n=$((n+1)); done; echo "$n"; }
check "no sampler is left running" test "$(cnt)" -eq 0
unset WS_RES_PROC WS_RES_PANES WS_RES_TCP WS_RES_DIR

echo "== 4b. budget (WS-GOV-014): one sample with 40 tabs and 300 processes"
P2="$T/proc2"; mkdir -p "$P2"; printf 'btime 900\n' > "$P2/stat"; : > "$T/panes2"; : > "$T/tcp2"
for w in $(seq 1 40); do
  root=$(( w * 100 )); printf 'P\t@%d\t%d\n' "$w" "$root" >> "$T/panes2"
  for c in 0 1 2 3 4 5 6; do
    pid=$(( root + c )); par=$(( c == 0 ? 1 : root + c - 1 )); d="$P2/$pid"; mkdir -p "$d/fd"
    printf '%s (p) S %s 0 0 0 -1 0 0 0 0 0 %s 0 0 0 20 0 1 0 10 0 1000 0\n' "$pid" "$par" "$(( pid % 7 ))" > "$d/stat"
    printf 'syscr: 1\nsyscw: 1\nread_bytes: 0\nwrite_bytes: 0\n' > "$d/io"; printf 'Pss: 1000 kB\n' > "$d/smaps_rollup"
    for f in 0 1 2 3 4 5 6 7 8 9; do ln -s /dev/null "$d/fd/$f"; done
    ln -s "socket:[$pid]" "$d/fd/10"; printf '%s\t%s\t%s\t0\n' "$pid" "$pid" "$pid" >> "$T/tcp2"
  done
done
for o in $(seq 9000 9260); do mkdir -p "$P2/$o"; printf '%s (o) S 1 0 0 0 -1 0 0 0 0 0 5 0 0 0 20 0 1 0 10 0 10 0\n' "$o" > "$P2/$o/stat"; done
printf 'G\t\t\t15\t\t\t\t\toff\t\t\t2\n' >> "$T/panes2"
cost="$(WS_RES_PROC="$P2" WS_RES_TCP="$T/tcp2" python3 -I -B -c "
import importlib.machinery as im, importlib.util as iu, time
l = im.SourceFileLoader('m', '$R'); s = iu.spec_from_loader('m', l); m = iu.module_from_spec(s); l.exec_module(m)
panes, _, g = m.parse_read(open('$T/panes2').read()); S = m.Sampler(); t = 1000.0
for _ in range(3): t += 2; S.sample(panes, t)
c = time.process_time()
for _ in range(30): t += 2; S.sample(panes, t)
print(round((time.process_time() - c) / 30 * 1000, 1))")"
echo "       ${cost} ms of CPU per sample (synthetic /proc; the real one costs the kernel more)"
check "a sample costs under 20 ms of CPU (1 % of a core every 2 s)" python3 -I -B -c "import sys; sys.exit(not $cost < 20)"

echo "== 4c. Menu → Settings: ws-settings res-mode / res-tabs"
mkdir -p "$HOME/.local/bin" "$HOME/.claude/hooks"
cp "$B/ws-settings" "$R" "$HOME/.local/bin/"; cp "$ROOT/files/home/.claude/hooks/audit.sh" "$HOME/.claude/hooks/"
export CLAUDE_AUDIT_DIR="$T/audit" CLAUDE_AUDIT_ANCHORS="$T/anchors"
ws() { bash "$HOME/.local/bin/ws-settings" "$@"; }
check "refused inside Claude"                     bash -c "CLAUDECODE=1 bash '$HOME/.local/bin/ws-settings' res-mode off; [[ \$? == 2 ]]"
check "res-mode compact is saved for tmux-res"    bash -c "$(declare -f ws); ws res-mode compact && grep -qx res_mode=compact '$HOME/.config/tmux-claude/settings'"
check "res-tabs on is saved"                      bash -c "$(declare -f ws); ws res-tabs on && grep -qx res_tabs=on '$HOME/.config/tmux-claude/settings'"
check "an unknown mode is refused"                bash -c "$(declare -f ws); ws res-mode loud; [[ \$? == 2 ]]"
check "show lists both values"                    bash -c "$(declare -f ws); ws show | grep -q 'resmode *compact' && ws show | grep -q 'restabs *on'"
check "the change is in the audit log"            grep -rq 'tab resources compact' "$T/audit"
rm -rf "$HOME/.config/tmux-claude/settings" "$HOME/.local/bin" "$HOME/.claude"

echo "== 5. the status path never walks /proc"
FMT="$T/formats"
{ grep -E "status-right|status-left|window-status|status-format" "$ROOT/files/home/.tmux.conf"
  grep -h 'tmux set -ag "$o" \|tmux set -g status-format' "$B/tmux-ux" "$B/tmux-background"; } > "$FMT"
check "no status format reads /proc or runs tmux-res"   not grep -qE '/proc|tmux-res' "$FMT"
check "the resource segments only read @res_* options"  bash -c "grep -o '#{E:@res_[a-z]*}' '$FMT' | sort -u | wc -l | grep -qx 4"
check "tmux-hud reads only machine-wide files (no /proc/<pid>)" not grep -qE '/proc/(\[|\*|\$|[0-9])' "$B/tmux-hud"
check "tmux-background only checks a PID (no /proc walk)"       not grep -qE 'for .* /proc/|/proc/\[0-9\]|/proc/\*' "$B/tmux-background"
check "every #() of the right side and the monitor line is a fixed-width producer" bash -c "
  grep -hoE '#\([^)]*\)' '$FMT' | grep -vE '^#\(~/.local/bin/(tmux-watch|tmux-hud|tmux-fit [0-9]+ -- )' | grep -q . && exit 1 || exit 0"
fit_w() { printf '%s' "$1" | bash "$B/tmux-fit" "${@:2}" | bash "$B/tmux-fit" --width; }
check "tmux-fit pads ASCII to N"                     test "$(fit_w abc 12)" = 12
check "tmux-fit cuts long text to N (with …)"        test "$(fit_w 'a very long subscription name' 12)" = 12
check "tmux-fit counts emoji as two columns"         test "$(fit_w '⏳⏳⏳⏳⏳⏳⏳⏳' 9)" = 9
check "tmux-fit ignores #[…] styles"                 test "$(fit_w '#[fg=red]⚠ 2,5#[default] ⏳ 3(12m)' -r 24)" = 24
check "tmux-fit runs a command and fits its first line" test "$(bash "$B/tmux-fit" 8 -- printf 'feature/very-long\nx')" = "feature…"
check "tmux-fit with an empty command output is N blanks" test "$(bash "$B/tmux-fit" 5 -- true | wc -c)" -eq 5
check "tmux-watch pads its traffic light (tmux-fit -r @ws_watch_width)" grep -q 'tmux-fit" -r "\$w"' "$B/tmux-watch"
check "shellcheck: tmux-fit, tmux-hud, tmux-ux, tmux-background, tmux-watch, ws-settings" \
  shellcheck -S warning "$B/tmux-fit" "$B/tmux-hud" "$B/tmux-ux" "$B/tmux-background" "$B/tmux-watch" "$B/ws-settings"
check "tmux-res compiles (stdlib only)" bash -c "python3 -I -B -c \"import ast,sys; t=ast.parse(open('$R').read()); \
mods={a.name.split('.')[0] for n in ast.walk(t) if isinstance(n,ast.Import) for a in n.names}|{n.module.split('.')[0] for n in ast.walk(t) if isinstance(n,ast.ImportFrom)}; \
sys.exit(bool(mods - set(sys.stdlib_module_names)))\""

echo "== 6. on a private tmux server: the bar keeps its columns when the values change"
A="$T/tma"; V="$T/tmv"; mkdir -p "$A" "$V"
ta() { env -u TMUX TMUX_TMPDIR="$A" tmux -L res "$@"; }
tv() { env -u TMUX TMUX_TMPDIR="$V" tmux -L res "$@"; }
if ta -f /dev/null new-session -d -s probe "sleep 1" 2>/dev/null; then
  ta kill-server 2>/dev/null; sleep 0.3
  # The kit's home, with stand-ins for what would leave the temp dir (collector, network) — the formats are the kit's.
  cp -a "$ROOT/files/home/." "$HOME/"
  for f in ws-otel ws-anomaly tmux-branch tmux-save-now tmux-history ws-personal tmux-recover ws-lang tmux-theme az; do
    printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/$f"; chmod 755 "$HOME/.local/bin/$f"
  done
  export PATH="$HOME/.local/bin:/usr/bin:/bin"
  ta -f "$HOME/.tmux.conf" new-session -d -s dev -n first -x 220 -y 20 "sleep 600" 2>/dev/null
  ta source-file "$HOME/.config/tmux-claude/theme-dark.tmux"
  ta new-window -d -t dev -n second "sleep 600"; ta new-window -d -t dev -n third "sleep 600"
  ta set -g status 2; ta set -g status-interval 1; ta set -g @ws_res_mode full; ta set -g @ws_res_tabs on
  ta set -g status-right-length 160
  sleep 1
  SA="$A/tmux-$(id -u)/res"
  # appends the tab glyph slot and starts the sampler; TMUX names server A so no plain «tmux» can reach another one
  TMUX="$SA,1,0" bash "$HOME/.local/bin/tmux-background" --bar
  # A client to look at: the second server's pane runs «tmux attach» of the first; its screen IS the rendered bar.
  tv -f /dev/null new-session -d -s view -x 220 -y 8 "env -u TMUX TMUX_TMPDIR='$A' TERM=xterm-256color tmux -L res attach -t dev"
  ok_sampler=0
  for _ in $(seq 1 40); do [[ -n "$(ta show -wqv -t dev:1 @res_p)" ]] && { ok_sampler=1; break; }; sleep 0.25; done
  check "the sampler (started by tmux-background) writes @res_p for the tab" test "$ok_sampler" = 1
  (( ok_sampler )) || { ls -la "$XDG_RUNTIME_DIR"/tmux-res-*/* 2>&1; cat "$XDG_RUNTIME_DIR"/tmux-res-*/*/log 2>&1; } | sed 's/^/       /'
  w_live="$(ta display -p -t dev:1 '#{E:@res_p}' | bash "$B/tmux-fit" --width)"
  check "the live panel has the constant width (61 columns)" test "$w_live" = 61
  sleep 3
  snap() { tv capture-pane -p -t view | head -2 | sed -E 's/[0-9]{2}:[0-9]{2} *$//'; }
  # Set extreme values by hand (the sampler is stopped so it does not overwrite them).
  TMUX="$SA,1,0" python3 -I -B "$HOME/.local/bin/tmux-res" stop >/dev/null 2>&1 || true
  mv "$HOME/.local/bin/tmux-res" "$T/tmux-res.off"   # tmux-background would start it again on the next refresh
  ta set -g @ws_res_mode full
  setvals() {   # $1: cpu %, $2: ctx %, $3: bell on/off, $4: stall
    local p c t
    IFS=$'\t' read -r p c t < <(python3 -I -B -c "
import importlib.machinery,importlib.util
l=importlib.machinery.SourceFileLoader('m','$R');s=importlib.util.spec_from_loader('m',l);m=importlib.util.module_from_spec(s);l.exec_module(m)
c=$1; r={'cpu':c,'mem':c*2**28,'ops':c*1e9,'iob':c*1e9,'rx':c*1e7,'tx':c,'gpu':None}
print('\t'.join(m.render(r,{'cpu_warn':80,'cpu_crit':150,'ram_warn':4,'ram_crit':8},False)))")
    local w; for w in 1 2 3; do ta set -w -t "dev:$w" @res_p "$p"; ta set -w -t "dev:$w" @res_c "$c"; ta set -w -t "dev:$w" @res_t "$t"; done
    ta set -w -t dev:2 @cctx "$2"; ta set -w -t dev:3 @cctx "$2"
    if [[ "$4" == 1 ]]; then ta set -w -t dev:3 @cstall 1; else ta set -wu -t dev:3 @cstall; fi
    ta set -w -t dev:1 @cs "$5"
    ta refresh-client -S 2>/dev/null; sleep 2.5
  }
  setvals 0 5 0 0 "✔ done"; s1="$(snap)"
  setvals 999 100 0 1 "🔧 Bash 1h05"; s2="$(snap)"
  setvals 5000 62 0 0 "🧠 thinking 42s"; s3="$(snap)"
  printf '%s\n' "$s1" "$s2" > "$T/snaps"
  cat > "$T/cols.py" <<'EOF'
import re, sys, unicodedata
# cols.py A B — the column of every label on line 1 (tab names, menu) and in the first 90 columns of line 2 (the
# tab panel and «host») must be the same in both captures.
a, b = (open(f, encoding="utf-8").read().splitlines() + ["", ""] for f in sys.argv[1:3])
def col(line, i):   # screen column of character i: emoji and CJK take two columns, as in tmux
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 0 if unicodedata.combining(c) else 1 for c in line[:i])
def cols(line, n=None):
    line = line if n is None else line[:n]
    return [(m.group(), col(line, m.start()))
            for m in re.finditer(r"first|second|third|menu|tab|host|CPU|RAM|IO|NET|GPU|/s", line)]
bad = [(i, cols(a[i], n), cols(b[i], n)) for i, n in ((0, None), (1, 90)) if cols(a[i], n) != cols(b[i], n)]
print(bad or "same columns")
sys.exit(1 if bad else 0)
EOF
  same_cols() { printf '%s\n' "$1" > "$T/c1"; printf '%s\n' "$2" > "$T/c2"; python3 -I -B "$T/cols.py" "$T/c1" "$T/c2" > "$T/cols.out" || { sed 's/^/       moved: /' "$T/cols.out" >> "$T/moved"; false; }; }
  check "the bar was rendered (tab names and the tab panel are on screen)" \
    bash -c "grep -q second <<<'$s1' && grep -q 'host' <<<'$s1' && grep -q 'CPU' <<<'$s1'"
  check "0 → 999 % (and ctx 5 → 100 %, a stall, a longer state): every column stays" same_cols "$s1" "$s2"
  check "999 → 5000 % (and ctx 100 → 62 %, another state): every column stays"         same_cols "$s2" "$s3"
  ta set -g status on; sleep 2.5; s4="$(snap)"
  check "monitor line hidden: the compact tab segment shows on the right" grep -q 'tab CPU' <<<"$s4"
  tv kill-server 2>/dev/null; ta kill-server 2>/dev/null
  sed -n 1,2p <<<"$s2" | sed 's/^/       /'; [[ -s "$T/moved" ]] && cat "$T/moved"
else
  SKIP=$((SKIP+1)); echo "  skip private tmux server checks: tmux cannot create its socket here"
fi

# tmux-az-name: the subscription segment reads the CLI's profile instead of running az on every refresh.
AZ="$ROOT/files/home/.local/bin/tmux-az-name"
AZT="$(mktemp -d)"; mkdir -p "$AZT/bom" "$AZT/none" "$AZT/missing"
printf '\xEF\xBB\xBF{"subscriptions":[{"name":"Other","isDefault":false},{"name":"Default Sub","isDefault":true}]}' \
  > "$AZT/bom/azureProfile.json"
printf '{"subscriptions":[{"name":"Other","isDefault":false}]}' > "$AZT/none/azureProfile.json"
check "tmux-az-name reads the default subscription through a byte order mark" \
  bash -c "[[ \"\$(AZURE_CONFIG_DIR='$AZT/bom' '$AZ')\" == 'Default Sub' ]]"
check "tmux-az-name prints nothing without a default subscription" \
  bash -c "[[ -z \"\$(AZURE_CONFIG_DIR='$AZT/none' '$AZ')\" ]]"
check "tmux-az-name prints nothing and exits 0 without a profile" \
  bash -c "out=\"\$(AZURE_CONFIG_DIR='$AZT/missing' '$AZ')\" && [[ -z \$out ]]"
check "the status bar no longer runs az account show" \
  bash -c "! grep -q 'az account show' '$ROOT/files/home/.tmux.conf' && grep -q 'tmux-az-name' '$ROOT/files/home/.tmux.conf'"
rm -rf "$AZT"

echo
echo "tab-resources: $PASS ok, $FAIL failed, $SKIP skipped"
(( FAIL == 0 ))
