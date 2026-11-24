# Working standards

If your organization or the repo has its own engineering guide, that one rules: read it before proposing or reviewing
code. If anything here conflicts with that guide or with the repo's README, tell me before acting.

## Precedence
Law → client contract and policies → organization policies → standard and guides → project decisions
(ADR/README). Every deviation is made explicit (reason, risk, owner, review date) in an ADR, the README or a ticket.

## How to work with me
- Respond in the language I write in. Decision first, then reasoning and trade-offs.
- Tables and code before paragraphs; do not explain basic concepts.
- When a design is ambiguous: recommendation + at least one alternative with trade-offs.
- Before a cloud change (az, terraform, kubectl) show the command and the active subscription or context.

## Git
- Conventional Commits `type(scope): description` in the imperative (feat, fix, chore, docs, refactor, test,
  ci, perf, style, build), unless the repo defines another convention.
- Atomic commits. Never `Co-authored-by` (the configuration already blocks it).
- Branching strategy as the README says (trunk-based or GitFlow); PR with a reviewer into main or release;
  signed commits if the client requires them.

## Documentation
- Non-trivial decision → ADR (Status, Context, Decision, Consequences, Alternatives). Architecture → C4.
  Non-functional requirements → FURPS+. No heavy artifacts for trivial tasks.
- Repos: README (purpose, setup, variables, runbook) and CHANGELOG (Keep a Changelog).
- Code: the language's idiomatic documentation; public surface and the non-obvious why, no redundant comments.

## Quality
- Test pyramid; all new code comes with its tests. Mandatory for auth, payments, permissions and destructive
  migrations. Coverage as confidence in the change, not as a percentage.
- Non-production, anonymized test data. Explicit DoD in PRs; contract testing between services.

## Security and AI
- OWASP Top 10, ASVS and LLM Top 10 as a checklist; threat modeling at design time.
- Secrets in Key Vault: never in code, prompts, fixtures or logs. Least privilege.
- Agents and tools get the same rigor as a privileged user (authz, allowlist, sandbox);
  human in the loop for destructive actions.
- Generated code is reviewed like any PR; it does not replace the security review or the tests.

## Cloud and CI/CD
IaC first, no ClickOps in prod; tagging env, owner, cost-center, project; multi-AZ in prod.
Pipeline Lint → SAST → Test → Build → DAST → Deploy → Smoke; rollback and SLOs before production.

## Files
Office or PDF → Markdown (MarkItDown or pandoc) before processing; if there is no tool, ask me for the converted file.

## Obsidian
I have an Obsidian vault accessible through the `obsidian` CLI (search, read, tasks, daily:read…).
Use it for my notes, tasks and daily notes; MemPalace is for decisions and project history.
Write to the vault only if I ask you to. Never delete, publish or run code there.

## Sandbox: cloud and network commands
- Run `az`, `kubectl`, `gh`, `terraform` and `git push/pull/fetch/clone/ls-remote` alone in the call:
  no `|`, `&&`, `cd`, redirection to a file or `$(...)`. Otherwise the sandbox traps them and they fail.
- Filter with `--query` and `-o tsv|json` instead of `| jq`; use `git -C <path>` instead of `cd`.
