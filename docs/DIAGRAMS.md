# Diagrams

Every diagram of the documentation in one place. Each one is repeated here unchanged from the document that explains
it; when a diagram changes, change it in both files.

| Diagram | Explained in |
|---|---|
| System context | [architecture.md](architecture.md#context), [README](../README.md#how-it-works) |
| Components | [architecture.md](architecture.md#components), [architecture.md](architecture.md#telemetry) |
| Sequences | [architecture.md](architecture.md#flows) |
| State and lifecycle | [architecture.md](architecture.md#state) |
| Trust boundaries | [THREAT_MODEL.md](THREAT_MODEL.md#trust-boundaries) |

## Contents

- [System context (C4 level 1)](#system-context-c4-level-1)
- [Components (C4 level 2)](#components-c4-level-2)
- [Sequences](#sequences)
- [State and lifecycle](#state-and-lifecycle)
- [Trust boundaries](#trust-boundaries)

## System context (C4 level 1)

### The workstation and its neighbors

The diagram shows the workstation as one system, the people who use it and the systems it talks to (C4 level 1).

```mermaid
flowchart LR
  user(["Developer"])
  phone(["Phone with Telegram"])
  subgraph windows["Windows 11"]
    wt["Windows Terminal"]
    cred[("Credential Manager")]
    toast["Notifications"]
    winfs[("Windows profile<br/>backups, reports")]
  end
  subgraph wsl["WSL2, Ubuntu 24.04"]
    ws["claude-workstation<br/>tmux + Claude Code + scripts"]
  end
  api[("Claude API")]
  remote[("Git remote")]
  tgapi[("Telegram Bot API")]

  user --> wt --> ws
  ws <--> api
  ws --> remote
  ws --> toast
  ws --> winfs
  ws <-. "secrets on demand" .-> cred
  ws <-. "redacted text, buttons" .-> tgapi <--> phone
```

What crosses the machine boundary: Claude Code's traffic to the Claude API, git pushes, Telegram messages, the kit's
`claude -p` calls, the optional terminal copilot and the optional encrypted cloud backup. Telemetry does not.

### The workstation at run time

The diagram shows the workstation, the Windows side it relies on and the three external services it talks to.

```mermaid
flowchart LR
  user(["Developer"])
  phone(["Phone with Telegram"])
  subgraph windows["Windows 11"]
    wt["Windows Terminal<br/>profile and shortcuts"]
    cred[("Credential Manager<br/>ws-secret, DPAPI")]
    toast["Windows notifications"]
  end
  subgraph wsl["WSL2, Ubuntu 24.04"]
    tmux["tmux session dev<br/>one tab per repo or worktree"]
    claude["Claude Code<br/>one per tab, work or personal account"]
    hooks["Hooks<br/>state, guard, routing, traces"]
    gate["Git hooks<br/>ws-gate"]
    otel["ws-otel<br/>OTLP collector on 127.0.0.1"]
    telem[("Local telemetry<br/>~/.local/share/ws-telemetry")]
  end
  api[("Claude API")]
  remote[("Git remote")]

  user --> wt --> tmux --> claude
  claude --> hooks
  hooks --> tmux
  hooks --> telem
  hooks --> toast
  claude -- "metrics, events, traces" --> otel --> telem
  claude <--> api
  claude --> gate --> remote
  hooks -. "redacted alerts" .-> phone
  phone -. "buttons, PIN-protected text" .-> tmux
  cred -. "keys read on demand" .-> hooks
```

Solid arrows are local calls and Claude Code's own traffic; dotted arrows are optional or on-demand paths.

## Components (C4 level 2)

### Installed components

The diagram shows the groups of files the installer puts in place and how they call each other (C4 level 2).

```mermaid
flowchart TB
  subgraph kit["Repository"]
    manifest["manifest.txt"]
    exp["export.sh"]
    inst["install.sh"]
    lib["lib.sh"]
    payload["files/home/…"]
  end

  subgraph tmuxl["tmux layer"]
    conf[".tmux.conf<br/>extras.tmux, ux.tmux"]
    menus["menu*.tmux<br/>tmux-palette"]
    watch["tmux-watch"]
    bg["tmux-background"]
    status["tmux-status"]
    views["tmux-dash, tmux-active<br/>tmux-pick, tmux-agents"]
    levels["tmux-level, tmux-solo<br/>tmux-claude-restart"]
  end

  subgraph claudel["Claude Code layer"]
    settings["settings.json<br/>permissions, sandbox, env"]
    state["tmux-state.sh"]
    guard["audit.sh, guard.sh"]
    traces["ws-traces.sh"]
    other["ws-routing.sh, intent-route.sh<br/>lint-on-edit.sh, read-convert.sh<br/>win-notify.sh, win-hook.sh"]
    sl["statusline.sh"]
    agents["agents/*.md"]
  end

  subgraph telem["Telemetry"]
    otel["ws-otel"]
    wst["ws-telemetry"]
    report["ws-report"]
    hooksum["ws-hooks"]
    data[("~/.local/share/ws-telemetry")]
  end

  subgraph gitl["git"]
    chain[".config/git/hooks/_chain"]
    gate["ws-gate"]
  end

  inst --> payload --> tmuxl & claudel & telem & gitl
  conf --> watch --> bg --> status
  watch --> otel
  settings --> state & guard & traces & other
  state --> status
  sl --> watch
  traces --> data
  otel --> data
  wst --> data
  data --> report & hooksum
  levels --> settings
  chain --> gate
```

### Telemetry sources and readers

The diagram shows which process writes each telemetry source and which commands read the result.

```mermaid
flowchart LR
  subgraph sources["Sources"]
    tx["Transcripts<br/>~/.claude/projects/**.jsonl"]
    tr["Hook traces<br/>traces/YYYY-MM-DD.jsonl"]
    rs["Resource samples<br/>raw/resources-YYYY-MM-DD.jsonl"]
    ot["OpenTelemetry<br/>otel/YYYY-MM-DD.jsonl"]
    ev["Events<br/>routing, Telegram"]
  end
  cc["Claude Code"] -- "OTLP http/json to 127.0.0.1:14318" --> col["ws-otel"] --> ot
  cc -- "hooks" --> trs["ws-traces.sh"] --> tr
  tx & tr & rs & ot & ev --> wst["ws-telemetry build"]
  wst --> html["dashboard.html"]
  wst --> turns[("turns.jsonl")]
  wst -. "imported as a module" .-> inf["ws-report"]
  inf --> rep["report-YYYY-MM-DD.html and .md"]
  ot --> wh["ws-hooks"]
```

## Sequences

### A Claude hook event

The sequence shows a Bash tool call in a tab, from the hooks' point of view.

```mermaid
sequenceDiagram
  autonumber
  participant C as Claude Code
  participant ST as tmux-state.sh
  participant AU as audit.sh
  participant G as guard.sh
  participant TR as ws-traces.sh
  participant T as tmux (window options)
  participant E as tmux-status
  participant W as tmux-watch (status refresh)

  C->>ST: PreToolUse (JSON on stdin)
  ST->>T: @cphase=tool, @cdet="Bash: npm test", @csince, @cmain
  ST->>E: --paint window
  E->>T: @cs="🔧 Bash 0s", @csc=color (only if changed)
  C->>AU: PreToolUse
  AU-->>AU: append metadata to ~/.claude/audit
  C->>G: PreToolUse
  alt policy violation or unreadable input
    G->>AU: blocked + reason
    G-->>C: exit 2, reason on stderr
  else allowed
    G-->>C: exit 0
  end
  C->>TR: PreToolUse / PostToolUse
  TR-->>TR: append one line to traces/YYYY-MM-DD.jsonl
  C->>ST: PostToolUse
  ST->>T: @cphase=thinking
  loop every status-interval
    W->>T: read @cmain, @cts of every window
    W-->>W: ⚠ / ⏳ / ◉, reminders, ws-otel ensure, tmux-background
  end
```

### Guardrails on every command and commit

The sequence shows the checks a tool call, a commit and a push go through before anything reaches the remote.

```mermaid
sequenceDiagram
  autonumber
  participant D as Developer
  participant C as Claude Code
  participant H as PreToolUse hooks (audit, guard.sh)
  participant P as Permission rules (allow / ask / deny)
  participant S as Sandbox
  participant G as ws-gate (git hooks)
  participant R as Git remote

  D->>C: prompt
  C->>H: tool call (command, file edit)
  H-->>C: exit 0, or exit 2 with the reason (blocked)
  C->>P: same tool call
  P-->>C: allow, ask the developer, or deny
  C->>S: run inside the sandbox (per the tab's protection level)
  S-->>C: result
  C->>G: git commit
  G-->>C: secrets, forbidden or large files, lint, Conventional Commits
  C->>G: git push
  G-->>R: only if the branch, dependency and IaC checks allow it
```

### Local data becomes the dashboard and the reports

The flowchart shows how raw local data becomes the dashboard, the report and the exports.

```mermaid
flowchart LR
  tx["Claude Code transcripts<br/>~/.claude/projects"] --> build["ws-telemetry build<br/>every minute"]
  tr["Hook traces<br/>ws-traces.sh, 13 events"] --> build
  res["Per-minute samples<br/>CPU, RAM, disk, network"] --> build
  cc["Claude Code<br/>OTLP http/json"] --> otel["ws-otel<br/>127.0.0.1:14318"]
  otel --> ofiles[("otel/YYYY-MM-DD.jsonl<br/>0600, secrets masked")]
  ofiles --> build
  rt["Routing decisions"] --> build
  tg["Telegram events"] --> build
  build --> dash["Usage dashboard<br/>dashboard.html"]
  build --> turns[("turns.jsonl<br/>one row per turn")]
  turns --> report["ws-report<br/>30-day report, HTML and Markdown"]
  ofiles --> report
  ofiles --> hk["ws-hooks<br/>hook time per event"]
  turns --> est["ws-telemetry estimate<br/>hours and cost per ticket"]
  turns --> csv["CSV export, DuckDB"]
```

### A report is built

The sequence shows what `ws-report` reads and when it calls Claude.

```mermaid
sequenceDiagram
  autonumber
  participant U as User
  participant I as ws-report
  participant W as ws-telemetry (module)
  participant D as ~/.local/share/ws-telemetry
  participant X as Other local sources
  participant C as claude -p (only with --ai)

  U->>I: ws-report [--days 30] [--ai]
  I->>W: load ws-telemetry as a module (one source of truth)
  W->>D: read transcripts-derived turns, traces, resource samples, otel/*.jsonl
  W-->>I: turns, tool detail, estimation, otel summary, ratios
  I->>X: routing and Telegram events, MemPalace and recall logs if present, Claude memories, commands, skills
  I-->>I: rule-based findings ("what to improve and what to create")
  opt --ai
    I->>C: aggregated metrics only, no tools
    C-->>I: findings and suggested actions
  end
  I-->>U: report-YYYY-MM-DD.html and .md (Windows profile and reports/)
```

## State and lifecycle

The state diagram shows the phases of a tab and what moves it from one to the next.

```mermaid
stateDiagram-v2
  [*] --> done: session starts
  done --> thinking: prompt sent
  thinking --> tool: tool call
  tool --> thinking: tool result
  tool --> permission: permission dialog
  thinking --> question: Claude opens a question dialog
  permission --> tool: answered
  question --> thinking: answered
  thinking --> compacting: compaction
  compacting --> thinking: automatic compaction ends
  thinking --> done: turn ends
  thinking --> yourturn: turn ends with a question or a request
  thinking --> error: API error
  thinking --> interrupted: Esc (read from the screen)
  yourturn --> thinking: next prompt
```

The state names are the values stored in the tmux window option `@cphase`.

## Trust boundaries

The diagram shows where untrusted text enters, which checks a tool call crosses and what leaves the machine.

```mermaid
flowchart TB
  user(["User at the keyboard"]) --> tmux["tmux session"]
  tmux --> claude["Claude Code, one per tab"]
  repo[("Repository content, tool output,<br/>web pages, MCP results")] -. "UNTRUSTED text" .-> claude
  claude -- "PreToolUse: audit.sh, guard.sh" --> rules{{"Permission rules<br/>allow, ask, deny"}}
  rules -- "sandboxed command" --> sbx["Sandbox (bubblewrap)<br/>denyRead credentials, network allowlist"]
  rules -- "excluded command (az, gh, git push, kubectl…)" --> host["User's shell privileges"]
  claude -- "git commit and push" --> gate{{"ws-gate (git hooks)"}} --> remote[("Git remote")]
  claude -- "OTLP http/json" --> otel["ws-otel<br/>127.0.0.1 only"] --> disk[("otel/*.jsonl, mode 0600")]
  claude <--> api[("Claude API")]
  hooks["Notification hooks"] -- "ws-redact" --> tg[("Telegram Bot API")]
  phone(["Owner's phone"]) --> tg
  tg -- "owner's chat id, one-time code, screen re-read" --> tmux
  cred[("Windows Credential Manager")] -. "ws-secret, on demand" .-> hooks
  other(["Other local process"]) -. "can POST to the collector,<br/>same privilege as the user" .-> otel

  classDef untrusted stroke-dasharray: 5 5
  classDef external stroke-width: 2px
  class repo,other untrusted
  class api,remote,tg,phone external
```

Dashed nodes are untrusted inputs; nodes with a thick border are outside the machine.
