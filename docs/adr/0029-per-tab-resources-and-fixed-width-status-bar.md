# 0029. Per-tab resources from one /proc sampler, and a status bar of fixed-width segments

- Status: Accepted
- Date: 2026-11-26

## Context and problem statement

Referred to in code and changelog as ADR-029. The owner asked for each tab's CPU, RAM, IOPS, GPU and network in the
status bar, "fixed — no auto size, with fixed sections — because it looks like it jumps when those values change".

Two problems. First, the bar only showed machine-wide numbers (`tmux-hud`, Ctrl+b v), and nothing says which of ~40
tabs is using the machine. Second, the bar moved: with ~40 tabs the tab list is wider than the terminal, tmux scrolls
it around the current tab, and every segment whose width changes moves the whole list. The causes found in the kit:
tab names cut but not padded (`#{=14:…}`), the bell `!`, the stall `⏳`, the subagent count `◆N` and the context `9%` →
`10%` appearing, disappearing or growing in every tab; the current tab's state text with a ticking timer (`42s` → `1m`
→ `1h05`); a traffic light (`tmux-watch`) whose content comes and goes; the Azure subscription and the branch of any
length; and on the monitor line, numbers without fixed width (`5%`/`43%`, `9.8/16G`, `180K`/`1.2M`, `🧠2`/`🧠12`) and
sparklines shorter than 16 until 16 samples exist.

What Linux can attribute to a process, checked on the owner's machine (WSL2, kernel 6.18, 20 cores, RTX 3070 Ti Laptop,
2026-11-26):

| Metric | Per process? | Source |
|---|---|---|
| CPU | yes | `/proc/<pid>/stat` utime+stime (+cutime+cstime of reaped children) |
| RAM | yes | `/proc/<pid>/smaps_rollup` PSS (133 ms of CPU for 177 processes: too slow to read every 2 s), RSS in `stat` |
| I/O | partly | `/proc/<pid>/io`: `syscr+syscw` count read/write system calls on every fd (files, pipes, terminals, sockets), not disk operations; `read_bytes+write_bytes` are block-layer bytes of the Linux disk, so `/mnt/c` (9p) does not show there. There is no per-process disk IOPS counter |
| Network | TCP only, without privileges | `sock_diag` netlink (what `ss -ti` uses) gives `tcpi_bytes_acked` / `tcpi_bytes_received` per socket; `/proc/<pid>/fd` maps socket inode → process. UDP/QUIC bytes and other network namespaces are not visible; `nethogs` (needs `cap_net_raw,cap_net_admin`) and `bpftrace` are not installed |
| GPU | no on WSL2 | NVML loads (`libnvidia-ml.so.1` in `/usr/lib/wsl/lib`, driver model WDDM): utilisation and memory of the whole GPU work; `nvmlDeviceGetComputeRunningProcesses` and `nvidia-smi --query-compute-apps` return no processes and `pmon` shows `-`. Windows processes reached through interop (`.exe` MCP servers) are outside Linux altogether |

## Decision drivers

- Never show a machine-wide number as if it were the tab's.
- The bar must not move when a value changes; a structural change (a tab opened, Claude started in a tab) may.
- Cost: the status bar must not walk `/proc`; one sampler per tmux server within ~1 % of one core with 40 tabs and
  300 processes (WS-GOV-014).
- Python standard library only; no capabilities, packages or root.

## Considered options

- **A. One sampler per server writing tmux options (chosen).** A tab = a tmux window; its processes = every pane's
  process and all descendants. The bar reads `#{E:@res_p}`; the sampler pays the `/proc` walk once.
- **B. `#(…)` per tab in the window format.** tmux runs one job per tab per refresh: 40 processes walking `/proc`
  every 15 s, and tmux does not pad job output.
- **C. cgroups per tab** (a systemd scope per pane). Exact CPU/RAM/IO accounting including exited processes, but it
  needs systemd user sessions in WSL and changes how every pane is started.
- **D. nethogs or eBPF for network.** Covers UDP, but needs capabilities set with sudo or root, and a resident
  packet capture.

## Decision

Option A, in `tmux-res` (Python, stdlib):

- **Attribution**: breadth-first from each `pane_pid` over the ppid tree of `/proc/*/stat`, deduplicated (a linked
  window counts once). A process seen in a tab keeps it after its parent dies and a subreaper adopts it (keyed by
  pid + start time). Processes outside every tab are not read again until the next full scan (30 s).
- **CPU** is % of ONE core (100 % = one busy core, like `top`), shown `%3d%%` and capped at 999 %. The delta uses
  utime+stime+cutime+cstime; when a child the sampler had seen ends, what was already counted of it is subtracted
  from the parent that reaped it, so it is counted once; a process born after the previous sample counts from zero.
- **RAM** is PSS from `smaps_rollup`, read for new processes at once and refreshed in turns (`@ws_res_pss_every`,
  60 s), scaled by the RSS in between; RSS where `smaps_rollup` cannot be read (the cache says which).
- **IO** shows `syscr+syscw` per second (labelled as I/O operations, documented as system calls) and storage bytes
  per second, with the same reaped-child correction; a process with no CPU time since the previous sample is not read.
- **NET** is TCP per tab from `sock_diag`, loopback left out; the socket map is refreshed only for processes that had
  sockets (10 s), fully every 60 s or every 20 s while unmapped traffic exists.
- **GPU**: NVML through `ctypes` (loaded once, ~0.1 ms a query; `nvidia-smi` every 60 s as a fallback). Per tab only
  when the driver reports processes; otherwise `--`. The machine's GPU goes to a separate segment after `| host`.
- **Where**: the monitor line (Ctrl+b v) starts with `tab N` and the active tab's panel, then `| host` and the
  machine's GPU and `tmux-hud`. With the monitor hidden the compact `tab CPU … RAM …` goes to the right of line 1.
  `@ws_res_mode full|compact|off` (Menu → Settings, `ws-settings res-mode`, `tmux-res mode`). The CPU glyph after each
  tab (`@ws_res_tabs`) is off by default: with ~40 tabs the list already needs ~1000 columns, so 2 more per tab only
  pushes more tabs out of view.
- **Fixed width everywhere**: every value of the panel has a fixed width and fixed unit per field; tab names are cut
  and padded; each tab has a 2-column state slot and a 4-column context slot; the current tab's state text is 18
  columns; `tmux-watch`, the subscription and the branch go through `tmux-fit` (pads and cuts by display columns);
  `tmux-hud` uses fixed widths and pads its sparklines.
- **Cost**: one tmux call per sample carries the reads and the writes of the previous sample; only changed and shown
  options are written, in batches under tmux's 16 KB command limit, never while a menu is open; with nothing to
  write the tabs are read again every 10 s; with no client attached nothing is sampled.

## Consequences

- Positive: each tab's own usage, honest about what it is (TCP only, system calls, % of one core, GPU `--` on WSL);
  the bar keeps every column when values change (`tests/tab-resources.sh` renders it through a second tmux client).
- Negative: tabs take their full slot widths even when empty (about the same width as a tab with Claude running
  before); the subagent count `◆N` is gone from the other tabs (their `●` turns purple and the current tab's state
  says "🐝 3 agents"). Network of a socket opened by a process that had none shows up within 20 s; UDP/QUIC and
  Windows processes are not counted; a tab's CPU and I/O lose the last ≤2 s of a child that its parent did not reap.
  `tmux-res` adds one resident Python process per tmux server. Measured on the owner's machine with 40 tabs, ~290
  processes in them and ~550 on the machine (host load average 7-14, 120 s each): sampler plus its tmux client
  0.7-1.05 % of one core with idle tabs, 1.1-2.0 % with 10 busy tabs; one sample is ~10 ms of CPU in-process. The
  budget is met at idle and crossed with many busy tabs on a loaded host: `@ws_res_interval 3` or `4` scales it down.
  Before the optimisations above (outsiders skipped, idle processes read every third sample, partial socket maps,
  NVML instead of `nvidia-smi`, raw reads, off-screen tabs every 10 s) the same load cost 3.4 %.
