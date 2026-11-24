# Contributing

Thanks for helping! The workstation's user interface and docs are in **Spanish**; issues and pull requests can be in
Spanish or English.

## Ground rules

- **No secrets, ever.** Keys live in the Windows Credential Manager (`ws-secret`), never in files, env vars or argv.
  `export.sh` and the pre-commit gate (`ws-gate`, gitleaks) block anything that looks like a secret.
- **No personal data.** Paths, user names and machine-specific values are exported as templates; `ws-verify` checks it.
- **Fail safe.** Hooks never block Claude on their own errors (they exit 0) and never store prompt text.
- **Human in the loop** for anything destructive or that leaves the machine (Telegram, pushes, releases).

## Workflow

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

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), imperative, one logical change per commit:
`feat(tmux): …`, `fix(ruteo): …`, `docs: …`. Types: feat · fix · chore · docs · refactor · test · ci · perf · style ·
build. **Do not add `Co-authored-by` trailers.**

## Documentation

Public scripts start with a header comment (what it does, usage, side effects). Non-trivial decisions get an ADR in
`docs/adr/` (Status · Context · Decision · Consequences · Alternatives).
