<!-- Thanks for contributing. Keep pull requests focused and small where possible. -->

## What and why

<!-- What does this change and why? Link any issue: Closes #123 -->

## Type

- [ ] feat
- [ ] fix
- [ ] docs
- [ ] refactor / chore

## Safety checklist (required)

- [ ] No secrets, tokens, personal paths or user names (they are exported as templates).
- [ ] Hooks still exit 0 on their own errors and never store prompt text, full commands or file contents.
- [ ] Anything that leaves the machine is redacted (`ws-redactar`) and needs the user's confirmation.
- [ ] No new third-party GitHub Actions; new tools are verified (checksum or signature).

## Tests

- [ ] `shellcheck -S warning` and `python3 -m py_compile` + `bandit -q -ll` pass on changed scripts.
- [ ] `ws-test` passes (isolated).
- [ ] New files are listed in `manifest.txt`; user-visible changes are under `[Unreleased]` in `CHANGELOG.md`.
- [ ] Commits follow Conventional Commits, without `Co-authored-by`.

## Documentation

- [ ] The documents named in `CONTRIBUTING.md` for this kind of change are updated, in English.
- [ ] A non-trivial decision has an ADR in `docs/adr/`.
