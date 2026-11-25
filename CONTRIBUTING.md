# Contributing

Thanks for helping. This guide covers the rules, the setup, the workflow and which document to update for each kind of
change.

## Contents

- [Ground rules](#ground-rules)
- [Dev setup](#dev-setup)
- [Workflow](#workflow)
- [Commits](#commits)
- [Language](#language)
- [Documentation](#documentation)

## Ground rules

- **No secrets, ever.** Keys live in the Windows Credential Manager (`ws-secret`), never in files, env vars or argv.
  `export.sh` and the pre-commit gate (`ws-gate`, gitleaks) block anything that looks like a secret.
- **No personal data.** Paths, user names and machine-specific values are exported as templates; `ws-verify` checks it.
- **Fail safe.** Hooks never block Claude on their own errors (they exit 0) and never store prompt text.
- **Human in the loop** for anything destructive or that leaves the machine (Telegram, pushes, releases).

## Dev setup

You need Windows 11 with WSL2 (Ubuntu 24.04), tmux 3.3 or newer and Claude Code. The details are in
[docs/USAGE.md](docs/USAGE.md#1-requirements).

1. Fork and clone the repository.
2. Install the base packages and the linters: `tmux git jq fzf gh bubblewrap socat rsync shellcheck`, plus `bandit`
   for the Python scripts.
3. Run the installer tests, which use temporary homes and do not touch your machine:

   ```bash
   bash tests/run.sh
   ```

4. Install the kit to test a change in the installed workstation. Run it in a normal shell, outside Claude Code:

   ```bash
   bash install.sh --dry-run
   bash install.sh
   ```

## Workflow

Branch from `main`; changes reach `main` only through reviewed pull requests with green CI.

1. Fork and branch from `main` (`feat/…`, `fix/…`).
2. Make the change in `files/home/…` (what `install.sh` installs) and, if you add a file, list it in `manifest.txt`.
3. Run the checks:

   ```bash
   shellcheck -S warning <changed scripts>
   python3 -m py_compile <changed python scripts> && bandit -q -ll <changed python scripts>
   for t in tests/*.sh; do bash "$t" >/dev/null || echo "FAILED: $t"; done   # every standalone suite
   ws-test            # isolated behavior tests: HOME, tmux and Claude are sandboxed
   ```

4. Add a line under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog).
5. Open a pull request using the template.

Definition of done:

- The checks above and CI pass.
- New behavior comes with a test (see [docs/TESTING.md](docs/TESTING.md#before-opening-a-pull-request)).
- New files are listed in `manifest.txt`.
- User-visible changes are under `[Unreleased]` in the changelog and in the documents listed below.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), imperative, one logical change per commit:
`feat(tmux): …`, `fix(routing): …`, `docs: …`. Types: feat, fix, chore, docs, refactor, test, ci, perf, style, build.
**Do not add `Co-authored-by` trailers.**

## Language

English for code, comments, messages, interface labels, documentation, commits, issues and pull requests. That
includes every identifier: command and file names, subcommands, options, environment variables, tmux options, config
keys, JSON fields and stored values ([ADR 0015](docs/adr/0015-english-names-and-language-selector.md)).

Spanish appears in three places only, each marked with a comment:

- **Language packs.** Words and expressions that match prompts and answers typed in another language are data, and
  they live in the pack of that language (`files/home/.local/lib/ws-lang/es.conf`,
  `files/home/.config/ws-routing/rules.es.conf`), never in a script. A new pattern goes into `en.conf` and, when it
  has a Spanish form, into `es.conf` under the same key. The user picks the packs with `ws-lang`.
- **Fixtures of the `es` pack** in `ws-test` and `cr --test`.
- **Compatibility with the names used before 3.0**: the old names in `renames.tsv`, and the tables that read old
  data and settings (`LEGACY…` in the Python scripts, `(.new // .old)` in jq). Do not add new ones, and do not remove
  them before the next major version.

A rename of anything the user can see or has on disk needs a row in `renames.tsv` (kind `data`, `shim` or `drop`),
a line in the rename tables of [docs/USAGE.md](docs/USAGE.md#18-upgrading-from-2x-names) and a `Changed` entry in the
changelog.

## Documentation

Public scripts start with a header comment (what it does, usage, side effects).

| Change | Update |
|---|---|
| A key binding, menu label, status label or command | [docs/USAGE.md](docs/USAGE.md); the generated manual (`ws-menus --show`) follows the installed menus |
| A component, hook, flow or stored state | [docs/architecture.md](docs/architecture.md), and [docs/DIAGRAMS.md](docs/DIAGRAMS.md) when a diagram changes |
| A permission rule, the sandbox, the guard, the gate, Telegram, telemetry content or backups | [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) and [SECURITY.md](SECURITY.md) |
| A test suite, a static check or a CI job | [docs/TESTING.md](docs/TESTING.md) |
| A language pack key or a new language | [docs/USAGE.md](docs/USAGE.md#15-language) and [docs/architecture.md](docs/architecture.md#language-packs) |
| A failure mode, an operational step, upgrading or recovery | [docs/runbook.md](docs/runbook.md) |
| A security control: what it does, its evidence (`file:line`) or its check | [docs/compliance/controls.yaml](docs/compliance/controls.yaml) and, when a status changes, the coverage tables of [docs/compliance/assessment.md](docs/compliance/assessment.md); `tests/compliance.sh` fails when they disagree |
| A model, subagent, MCP server, hook or external AI service | [docs/governance/AI-BOM.md](docs/governance/AI-BOM.md): regenerate its tables with `bash tests/ai-bom.sh --write`; CI fails when they are stale |
| Anything a user notices | [CHANGELOG.md](CHANGELOG.md), under `[Unreleased]` |

Non-trivial decisions get an ADR in [docs/adr/](docs/adr/README.md): copy `template.md` and fill in Status, Context and
problem statement, Decision drivers, Considered options, Decision and Consequences. A change to an accepted decision
needs a new or superseding ADR in the same pull request.

A diagram that appears in a document is repeated unchanged in `docs/DIAGRAMS.md`. Diagrams are Mermaid blocks.
