# Support

claude-workstation is maintained by one person in their spare time. Use the channel that fits your question.

## Where to ask

| Need | Channel |
|---|---|
| Ask how to install, configure or use the workstation | [Discussions, Q&A](https://github.com/andreshma/claude-workstation/discussions/categories/q-a) |
| Share an idea or discuss a design change before coding it | [Discussions, Ideas](https://github.com/andreshma/claude-workstation/discussions/categories/ideas) |
| Report a reproducible bug | [New issue, Bug report](https://github.com/andreshma/claude-workstation/issues/new?template=bug_report.yml) |
| Propose a concrete feature | [New issue, Feature request](https://github.com/andreshma/claude-workstation/issues/new?template=feature_request.yml) |
| Report a security vulnerability | [Private advisory](https://github.com/andreshma/claude-workstation/security/advisories/new); never a public issue (see [SECURITY.md](SECURITY.md)) |

## Before you ask

Check the [runbook](docs/runbook.md) and run `ws-test` (isolated, it does not touch your session).

## What to include

Include the output of `ws-verify` (or `ws-test`) and your Windows, WSL distro, tmux and Claude Code versions. Do not
paste prompts, transcripts, tokens, your `~/.claude/settings.json` or anything from `~/.config/ws-local/`.

## Response time

There is no guaranteed response time. Pull requests that follow [CONTRIBUTING.md](CONTRIBUTING.md) are the fastest way
to get a fix in.
