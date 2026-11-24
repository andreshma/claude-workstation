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
`feat(tmux): …`, `fix(ruteo): …`, `docs: …`. Types: feat, fix, chore, docs, refactor, test, ci, perf, style, build.
**Do not add `Co-authored-by` trailers.**

## Language

English for code, comments, messages, interface labels, documentation, commits, issues and pull requests.

Two exceptions exist today:

- Command names, flags and some stored values are still Spanish words (`tmux-nivel`, `--todas`, `completo`), pending a
  rename. Do not translate them one by one; write them as they are in the code.
- Regular expressions and keyword lists that match prompts typed in Spanish (model routing, intent detection) stay in
  Spanish on purpose, with a comment that says so.

## Documentation

Public scripts start with a header comment (what it does, usage, side effects).

| Change | Update |
|---|---|
| A key binding, menu label, status label or command | [docs/USAGE.md](docs/USAGE.md); the generated manual (`ws-menus --ver`) follows the installed menus |
| A component, hook, flow or stored state | [docs/architecture.md](docs/architecture.md), and [docs/DIAGRAMS.md](docs/DIAGRAMS.md) when a diagram changes |
| A permission rule, the sandbox, the guard, the gate, Telegram, telemetry content or backups | [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) and [SECURITY.md](SECURITY.md) |
| A test suite, a static check or a CI job | [docs/TESTING.md](docs/TESTING.md) |
| A failure mode, an operational step, upgrading or recovery | [docs/runbook.md](docs/runbook.md) |
| Anything a user notices | [CHANGELOG.md](CHANGELOG.md), under `[Unreleased]` |

Non-trivial decisions get an ADR in [docs/adr/](docs/adr/README.md): copy `template.md` and fill in Status, Context and
problem statement, Decision drivers, Considered options, Decision and Consequences. A change to an accepted decision
needs a new or superseding ADR in the same pull request.

A diagram that appears in a document is repeated unchanged in `docs/DIAGRAMS.md`. Diagrams are Mermaid blocks.
