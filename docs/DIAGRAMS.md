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
    telem[("Local telemetry<br/>~/.local/share/ws-telemetria")]
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
    conf[".tmux.conf<br/>maravillas.tmux, ux.tmux"]
    menus["menu*.tmux<br/>tmux-paleta"]
    watch["tmux-watch"]
    fondo["tmux-fondo"]
    estado["tmux-estado"]
    views["tmux-dash, tmux-activas<br/>tmux-pick, tmux-agents"]
    levels["tmux-nivel, tmux-solo<br/>tmux-claude-restart"]
  end

  subgraph claudel["Claude Code layer"]
    settings["settings.json<br/>permissions, sandbox, env"]
    state["tmux-state.sh"]
    guard["audit.sh, guard.sh"]
    trazas["ws-trazas.sh"]
    other["ws-ruteo.sh, intent-route.sh<br/>lint-on-edit.sh, read-convert.sh<br/>win-notify.sh, win-hook.sh"]
    sl["statusline.sh"]
    agents["agents/*.md"]
  end

  subgraph telem["Telemetry"]
    otel["ws-otel"]
    wst["ws-telemetria"]
    informe["ws-informe"]
    hooksum["ws-hooks"]
    data[("~/.local/share/ws-telemetria")]
  end

  subgraph gitl["git"]
    chain[".config/git/hooks/_chain"]
    gate["ws-gate"]
  end

  inst --> payload --> tmuxl & claudel & telem & gitl
  conf --> watch --> fondo --> estado
  watch --> otel
  settings --> state & guard & trazas & other
  state --> estado
  sl --> watch
  trazas --> data
  otel --> data
  wst --> data
  data --> informe & hooksum
  levels --> settings
  chain --> gate
```

### Telemetry sources and readers

The diagram shows which process writes each telemetry source and which commands read the result.

```mermaid
flowchart LR
  subgraph sources["Sources"]
    tx["Transcripts<br/>~/.claude/projects/**.jsonl"]
    tz["Hook traces<br/>trazas/YYYY-MM-DD.jsonl"]
    rs["Resource samples<br/>raw/recursos-YYYY-MM-DD.jsonl"]
    ot["OpenTelemetry<br/>otel/YYYY-MM-DD.jsonl"]
    ev["Events<br/>routing, Telegram"]
  end
  cc["Claude Code"] -- "OTLP http/json to 127.0.0.1:14318" --> col["ws-otel"] --> ot
  cc -- "hooks" --> tzs["ws-trazas.sh"] --> tz
  tx & tz & rs & ot & ev --> wst["ws-telemetria build"]
  wst --> html["tablero.html"]
  wst --> turnos[("turnos.jsonl")]
  wst -. "imported as a module" .-> inf["ws-informe"]
  inf --> rep["informe-YYYY-MM-DD.html and .md"]
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
  participant TZ as ws-trazas.sh
  participant T as tmux (window options)
  participant E as tmux-estado
  participant W as tmux-watch (status refresh)

  C->>ST: PreToolUse (JSON on stdin)
  ST->>T: @cfase=herramienta, @cdet="Bash: npm test", @cdesde, @cmain
  ST->>E: --pintar window
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
  C->>TZ: PreToolUse / PostToolUse
  TZ-->>TZ: append one line to trazas/YYYY-MM-DD.jsonl
  C->>ST: PostToolUse
  ST->>T: @cfase=pensando
  loop every status-interval
    W->>T: read @cmain, @cts of every window
    W-->>W: ⚠ / ⏳ / ◉, reminders, ws-otel asegurar, tmux-fondo
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
  tx["Claude Code transcripts<br/>~/.claude/projects"] --> build["ws-telemetria build<br/>every minute"]
  tr["Hook traces<br/>ws-trazas.sh, 13 events"] --> build
  res["Per-minute samples<br/>CPU, RAM, disk, network"] --> build
  cc["Claude Code<br/>OTLP http/json"] --> otel["ws-otel<br/>127.0.0.1:14318"]
  otel --> ofiles[("otel/YYYY-MM-DD.jsonl<br/>0600, secrets masked")]
  ofiles --> build
  rt["Routing decisions"] --> build
  tg["Telegram events"] --> build
  build --> dash["Usage dashboard<br/>tablero.html"]
  build --> turns[("turnos.jsonl<br/>one row per turn")]
  turns --> report["ws-informe<br/>30-day report, HTML and Markdown"]
  ofiles --> report
  ofiles --> hk["ws-hooks<br/>hook time per event"]
  turns --> est["ws-telemetria estimar<br/>hours and cost per ticket"]
  turns --> csv["CSV export, DuckDB"]
```

### A report is built

The sequence shows what `ws-informe` reads and when it calls Claude.

```mermaid
sequenceDiagram
  autonumber
  participant U as User
  participant I as ws-informe
  participant W as ws-telemetria (module)
  participant D as ~/.local/share/ws-telemetria
  participant X as Other local sources
  participant C as claude -p (only with --ia)

  U->>I: ws-informe [--dias 30] [--ia]
  I->>W: load ws-telemetria as a module (one source of truth)
  W->>D: read transcripts-derived turns, traces, resource samples, otel/*.jsonl
  W-->>I: turns, tool detail, estimation, otel summary, ratios
  I->>X: routing and Telegram events, MemPalace and recall logs if present, Claude memories, commands, skills
  I-->>I: rule-based findings ("what to improve and what to create")
  opt --ia
    I->>C: aggregated metrics only, no tools
    C-->>I: findings and suggested actions
  end
  I-->>U: informe-YYYY-MM-DD.html and .md (Windows profile and informes/)
```

## State and lifecycle

The state diagram shows the phases of a tab and what moves it from one to the next.

```mermaid
stateDiagram-v2
  [*] --> listo: session starts
  listo --> pensando: prompt sent
  pensando --> herramienta: tool call
  herramienta --> pensando: tool result
  herramienta --> permiso: permission dialog
  pensando --> pregunta: Claude opens a question dialog
  permiso --> herramienta: answered
  pregunta --> pensando: answered
  pensando --> compactando: compaction
  compactando --> pensando: automatic compaction ends
  pensando --> listo: turn ends
  pensando --> tetoca: turn ends with a question or a request
  pensando --> error: API error
  pensando --> interrumpido: Esc (read from the screen)
  tetoca --> pensando: next prompt
```

The state names are the values stored in the tmux window option `@cfase`.

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
  hooks["Notification hooks"] -- "ws-redactar" --> tg[("Telegram Bot API")]
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
