# Governance

How AI is governed on a workstation installed from this kit: the rules of use, the inventory, the incident
procedure and the review calendar. They are written for one owner and stay short on purpose. The controls they
satisfy are in [controls.yaml](../compliance/controls.yaml); each section of each document ends with a "Maps to" line
naming those control ids and framework items ([frameworks.md](../compliance/frameworks.md)).

| Document | What it answers | Controls |
|---|---|---|
| [AI-USE-POLICY.md](AI-USE-POLICY.md) | What data may reach models and memory, approved models, what needs a person, which protection level to use, what is prohibited, impact assessment | WS-GOV-001, WS-GOV-011, WS-GOV-012 |
| [AI-BOM.md](AI-BOM.md) | Every model, agent, MCP server, agent tool, hook and external service, with version, data and risk; generated tables checked in CI | WS-GOV-002, WS-GOV-008 |
| [AI-INCIDENT-RESPONSE.md](AI-INCIDENT-RESPONSE.md) | Detect, contain, eradicate, recover and record for AI-specific incidents | WS-GOV-003 |
| [REVIEW-CADENCE.md](REVIEW-CADENCE.md) | What is reviewed monthly, quarterly, per Claude Code release and yearly, and the evidence left | WS-GOV-004, WS-GOV-005, WS-GOV-010 |

Conventions:

- Facts about the kit link to the file that implements them. A mechanism that is still open is named with its control
  id ([assessment, Status after phase 2](../compliance/assessment.md#status-after-phase-2)).
- A decision the owner made that is not yet confirmed is marked "owner to confirm".
- The inventory tables of the AI-BOM are generated (`python3 .github/scripts/ai_bom.py --write`) and CI fails when they
  drift (`tests/ai-bom.sh`); the rest is written by hand.
- Operational steps live in the [runbook](../runbook.md); threats and residual risks in the
  [threat model](../THREAT_MODEL.md); decisions in [ADRs](../adr/README.md). These documents link to them instead of
  repeating them.
