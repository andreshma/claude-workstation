# Frameworks

The AI, security and governance frameworks the control catalogue ([controls.yaml](controls.yaml)) maps to: the version
in force on 2026-11-25, where it was verified, how it applies to a single-user developer workstation that runs AI
agents, and what is out of scope. The [assessment](assessment.md) uses these sources.

## Contents

- [How to read a reference](#how-to-read-a-reference)
- [Sources](#sources)
- [Version notes](#version-notes)
- [OWASP LLM Top 10: 2025 to 2026](#owasp-llm-top-10-2025-to-2026)
- [Not verified](#not-verified)
- [Item IDs used in the catalogue](#item-ids-used-in-the-catalogue)

## How to read a reference

Each `maps_to` entry is `<prefix>:<item>`. The prefix names the framework (table below); the item is everything after
the first colon, so `WAF-SEC:SE:05` is item `SE:05` of the Well-Architected security checklist. Items whose official
text has no identifier (headings, principles, topic names) are written by their exact name. An item marked "(id
unverified)" in [Item IDs used in the catalogue](#item-ids-used-in-the-catalogue) is cited by name because its number
could not be confirmed from a public source.

## Sources

Verified online on 2026-11-25 from the official pages listed, unless the notes say otherwise.

| Prefix | Framework | Version | Date | Official URL | How it applies to this workstation | Out of scope, and why |
|---|---|---|---|---|---|---|
| `OWASP-LLM25` | OWASP Top 10 for LLM Applications | 2025 edition | November 2024 | <https://genai.owasp.org/llm-top-10/> | The risk list for the LLM the agents call and for the kit scripts that consume model output. | Model training and hosting: the kit uses a hosted model and trains nothing. |
| `OWASP-LLM26` | OWASP GenAI LLM Top 10 | 2026 edition (current) | 2026-08-03 | <https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/> | Supersedes the 2025 list; every 2025 mapping is carried over by the [crosswalk](#owasp-llm-top-10-2025-to-2026). | Same as 2025. |
| `OWASP-ASI` | OWASP Top 10 for Agentic Applications | 2026 edition | 2025-12-09 | <https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/> | The primary list: the kit is an agent harness with tools, memory, parallel agents and a remote approval channel. | Nothing; all ten items apply. |
| `OWASP-NHI` | OWASP Non-Human Identities Top 10 | 2025 | Not stated on the page | <https://owasp.org/projects/non-human-identities-top-10> | Agents act with the user's tokens; the kit keeps its own bot token, PIN and backup key. | `NHI6` cloud deployment configuration: the kit deploys nothing to the cloud. |
| `OWASP-MCP3P` | CheatSheet: A Practical Guide for Securely Using Third-Party MCP Servers | 1.0 | 2025-11-04 | <https://genai.owasp.org/resource/cheatsheet-a-practical-guide-for-securely-using-third-party-mcp-servers-1-0/> | The kit registers five third-party MCP servers. Items are the mitigation topics named on the resource page. | Nothing within the topics used. |
| - | A Practical Guide for Secure MCP Server Development | Final (no version number shown) | 2026-02-16 | <https://genai.owasp.org/resource/a-practical-guide-for-secure-mcp-server-development/> | Listed for completeness. | Not mapped: the kit develops no MCP server; it only configures them. |
| - | OWASP Agentic AI: Threats and Mitigations | 1.0 (page); 1.1 reported | 2025-02-17; 1.1 in December 2025 | <https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/> | Background taxonomy behind the agentic Top 10. | Not mapped by threat number: the T-numbering of version 1.1 could not be read from the official PDF, so the catalogue maps to `OWASP-ASI` instead. |
| - | OWASP Agent Control Standard (ACS) | Not stated | Announced 2026-09-01 | <https://genai.owasp.org/resource/agent-control-standard-acs/> | Runtime enforcement guidance for agents; relevant to Phase 2. | Not mapped: no control identifier scheme could be verified. |
| `NIST-AI-RMF` | NIST AI Risk Management Framework (NIST AI 100-1) and Playbook | 1.0 | 2023-01-26 | <https://www.nist.gov/itl/ai-risk-management-framework>, <https://airc.nist.gov/airmf-resources/playbook/> | GOVERN, MAP, MEASURE and MANAGE subcategories that one owner can act on: inventory, oversight, monitoring, incidents, third parties. | Subcategories about teams, diversity, external stakeholders and model evaluation science (see the assessment's not-mapped list). NIST states a revision is in progress; none is published. |
| `NIST-600-1` | NIST AI 600-1, Generative AI Profile | Final | 2024-07-26 | <https://doi.org/10.6028/NIST.AI.600-1> | The 12 GAI risks; seven concern how the agents handle data, code, memory and suppliers. | Content-harm risks (CBRN, violent or abusive content, bias, environment): the kit constrains actions, not model text. |
| `SSDF` | NIST SP 800-218, Secure Software Development Framework | 1.1 | 2022-02 | <https://csrc.nist.gov/pubs/sp/800/218/final> | The kit is software: its own development, CI, releases and update channel. | `PW.6` compilation settings: the kit is shell and Python scripts with nothing to compile. |
| `SSDF-1.2-IPD` | NIST SP 800-218 Rev. 1 (SSDF 1.2), initial public draft | 1.2 draft | 2025-12-17 | <https://csrc.nist.gov/pubs/sp/800/218/r1/ipd> | Only the two new practices reported by NIST (`PO.6` continuous improvement, `PW.10` robust updates). | Draft: comments closed 2026-01-30; a final version was not found. |
| `SSDF-218A` | NIST SP 800-218A, SSDF Community Profile for Generative AI and Dual-Use Foundation Models | Final | 2024-07-26 | <https://csrc.nist.gov/pubs/sp/800/218/a/final> | It augments SSDF practices with AI considerations; cited at practice level for third-party AI components and testing. | Model training, weights and data pipelines: the kit produces no model. The profile's own new task IDs were not verified. |
| `CSF` | NIST Cybersecurity Framework | 2.0 | 2024-02-26 | <https://www.nist.gov/cyberframework> | Subcategories for identity, data, platform, logging, monitoring, supply chain and response on one workstation. | Categories that need an organisation: `GV.OC`, `GV.RM`, `PR.AT`, `RS.AN`, `RS.CO`, `RS.MI`, `RC.CO`. The NIST Cyber AI Profile (NIST IR 8596) is a preliminary draft (2025-12-16) and is not mapped. |
| `CIS-v8` | CIS Critical Security Controls | 8.1 | 2024-06-25 | <https://www.cisecurity.org/controls/v8-1> | Safeguards that make sense for one developer endpoint: software inventory, secure configuration, data protection, logging, backups, application security. | Enterprise network infrastructure and monitoring (12, 13), physical and HR safeguards, penetration testing programmes (18), awareness programmes (14). No v8.2 or v9 release was found. |
| `CIS-Ubuntu` | CIS Ubuntu Linux 24.04 LTS Benchmark | 2.0.0 | 2026 (listed in CIS's June 2026 update) | <https://www.cisecurity.org/benchmark/ubuntu_linux> | Only the items the kit configures or checks: updates, permissions, umask, firewall and listening services, sshd, logging. | Section numbers are not cited: the benchmark PDF is licensed and v2.0.0 renumbered sections. Boot, partitioning, kernel modules and AppArmor are not evaluated because the kit neither configures nor checks them and WSL's kernel differs. Whether a WSL-specific benchmark exists was not verified. |
| - | CIS Microsoft Windows 11 Enterprise Benchmark | 5.1.0 (secondary listing) | 2026-09 (secondary listing) | <https://www.cisecurity.org/benchmark/microsoft_windows_desktop> | The kit touches Windows only through the Credential Manager, a PowerShell profile and an HKCU protocol handler. | Not mapped: the Windows baseline is the organisation's; the kit changes no Windows security setting. |
| `NSA-DAISS` | NSA AISC and partners, Deploying AI Systems Securely (CSI) | 1.0 | 2024-04-15 | <https://media.defense.gov/2024/Apr/15/2003439257/-1/-1/0/CSI-DEPLOYING-AI-SYSTEMS-SECURELY.PDF> | The deployment environment here is the workstation: governance, hardening, monitoring, access control, updates. Items are the guidance's headings. | "Protect model weights": the kit hosts no model. |
| `NSA-AIDATA` | NSA AISC and partners, AI Data Security: Best Practices for Securing Data Used to Train & Operate AI Systems (CSI) | Final | 2025-05-22 | <https://media.defense.gov/2025/May/22/2003720601/-1/-1/0/CSI_AI_DATA_SECURITY.PDF> | The data that operates the agents: prompts, memory, retrieval corpora, telemetry and backups. Items `BP1` to `BP10` are the ten numbered best practices. | Training-data sections (data drift, poisoned training sets): no training happens here. |
| `NSA-AGENTIC` | ASD's ACSC, CISA, NSA and partners, Careful Adoption of Agentic AI Services | Final | 2026-05-01 | <https://www.cyber.gov.au/business-government/secure-design/artificial-intelligence/careful-adoption-of-agentic-ai-services> | Privilege, structural and accountability risks of agents. | Section headings could not be read (the official site timed out); items cite the three risk categories named in summaries and are marked unverified. |
| `WAF-SEC` | Microsoft Azure Well-Architected Framework, Security checklist | Page updated 2026-06-26 | 2026-06-26 | <https://learn.microsoft.com/azure/well-architected/security/checklist> | `SE:01` to `SE:12` read with the workstation as the workload. | Azure platform services: the kit deploys none. |
| `WAF-AI` | Azure Well-Architected Framework, AI workload guidance | Page updated 2026-05-07 | 2026-05-07 | <https://learn.microsoft.com/azure/well-architected/ai/> | Application design, grounding data, operations, testing and responsible AI pages. | Training data design, data platform and application platform pages: no training or AI hosting here. |
| `CAF` | Microsoft Cloud Adoption Framework, AI adoption: Govern AI and Secure AI | Govern AI and Secure AI updated 2026-10-15 | 2026-10-15 | <https://learn.microsoft.com/azure/cloud-adoption-framework/ai/govern>, <https://learn.microsoft.com/azure/cloud-adoption-framework/ai/secure> | The governance and security process steps scaled to one owner. Items are the numbered steps of those pages. | AI strategy, plan, ready and manage phases, Azure Policy, Purview and Defender: organisational and Azure-platform processes. |
| `MS-RAI` | Microsoft Responsible AI principles | Six principles (Responsible AI Standard v2, June 2022) | 2022-06 | <https://www.microsoft.com/ai/responsible-ai> | Accountability, transparency, reliability and safety, privacy and security of how the agents are operated. | Fairness and inclusiveness: the kit makes no decisions about people. The Standard's goal IDs were not verified, so only principle names are used. |
| `ISO42001` | ISO/IEC 42001:2023, AI management system | 2023 | 2023-12 | <https://www.iso.org/standard/81230.html> | Clauses 4 to 10 and the Annex A control objective groups `A.2` to `A.10`, for the owner's own management of AI use. | The paid text was not available: clause names follow the ISO harmonized structure and Annex A group names come from public summaries; individual Annex A controls are not cited because summaries disagree on their numbering. Certification and organisational roles are out of scope. |
| `ATLAS` | MITRE ATLAS | Version not verified | - | <https://atlas.mitre.org> | Cross-reference for the injection and memory-poisoning techniques. | Only techniques confirmed by public descriptions are cited. |

## Version notes

- **OWASP LLM Top 10.** The 2026 edition is the current one; the 2025 edition requested for this phase is mapped and
  every 2025 reference is carried to 2026 automatically. The 2026 list has no "System Prompt Leakage" entry; the
  closest new entry is `LLM08:2026` Hidden Context Exposure. That pairing is inferred from the names; the official
  2025-to-2026 mapping inside the 2026 document was not read.
- **OWASP agentic work.** The Top 10 for Agentic Applications (December 2025) uses `ASI01` to `ASI10`. The Threats and
  Mitigations guide reached 1.1 in December 2025 according to OWASP's announcement; its threat numbers are not used.
- **SSDF.** Version 1.1 is final. Version 1.2 (SP 800-218 Rev. 1) is a draft; NIST's 2026 presentations list the new
  practices `PO.6` and `PW.10`, which are cited with the `SSDF-1.2-IPD` prefix.
- **NIST AI RMF.** 1.0 remains in force; NIST reports a revision in progress without a draft.
- **CIS Ubuntu 24.04.** v2.0.0 replaced v1.0.0 in 2026; Canonical's USG profile still targets v1.0.0 according to its
  documentation.

## OWASP LLM Top 10: 2025 to 2026

| 2025 | 2026 | Note |
|---|---|---|
| `LLM01` Prompt Injection | `LLM01` Prompt Injection | Same name |
| `LLM02` Sensitive Information Disclosure | `LLM02` Sensitive Information Disclosure | Same name |
| `LLM03` Supply Chain | `LLM04` Supply Chain | Same name |
| `LLM04` Data and Model Poisoning | `LLM05` Data and Model Poisoning | Same name |
| `LLM05` Improper Output Handling | `LLM10` Improper Output Handling | Same name |
| `LLM06` Excessive Agency | `LLM03` Excessive Agency | Same name |
| `LLM07` System Prompt Leakage | `LLM08` Hidden Context Exposure | Inferred |
| `LLM08` Vector and Embedding Weaknesses | `LLM09` Vector and Embedding Weaknesses | Same name |
| `LLM09` Misinformation | `LLM07` Misinformation | Same name |
| `LLM10` Unbounded Consumption | `LLM06` Unbounded Consumption | Same name |

## Not verified

| Item | What was done instead |
|---|---|
| OWASP Agentic Threats and Mitigations 1.1 threat numbers (T1 onwards) | Mapped to `OWASP-ASI` only |
| OWASP LLM Top 10 2026 official crosswalk from 2025 | Name-based crosswalk above |
| NSA "Careful Adoption of Agentic AI Services" headings | Three risk categories from summaries, marked unverified |
| CIS Ubuntu 24.04 v2.0.0 section numbers | Recommendations cited by name, marked "(id unverified)" |
| CIS Windows 11 Enterprise version | From secondary listings; not mapped |
| ISO/IEC 42001 Annex A individual control numbers | Group level `A.2` to `A.10` only |
| Microsoft Responsible AI Standard v2 goal identifiers | Principle names only |
| MITRE ATLAS release version | Technique IDs from public descriptions only |
| Publication dates of OWASP LLM 2025 (November 2024), SSDF 1.1 (February 2022), CSF 2.0 (2024-02-26), AI RMF 1.0 (2023-01-26), ISO/IEC 42001 (December 2023) and the Responsible AI Standard v2 (June 2022) | Recalled, not re-read during this check; the versions themselves were confirmed current |
| NIST SP 800-218A task-level additions | Practice level only |

## Item IDs used in the catalogue

Every `maps_to` reference in [controls.yaml](controls.yaml) appears below, with the controls that cite it. The list was
checked against the catalogue when it was written (no reference outside this list); Phase 4 turns that check into CI.

### `OWASP-LLM25`

| ID | Item | Controls |
|---|---|---|
| `LLM01` | Prompt Injection | WS-AI-001, WS-AI-014, WS-AI-027 |
| `LLM02` | Sensitive Information Disclosure | WS-AI-022, WS-AI-023, WS-SEC-002, WS-SEC-003, WS-SEC-004, WS-SEC-007, WS-SEC-008, WS-SEC-009 |
| `LLM03` | Supply Chain | WS-AI-009, WS-AI-010, WS-SEC-015, WS-SEC-016 |
| `LLM04` | Data and Model Poisoning | WS-AI-012, WS-AI-013, WS-AI-024 |
| `LLM05` | Improper Output Handling | WS-AI-017, WS-AI-018, WS-AI-021, WS-SEC-028 |
| `LLM06` | Excessive Agency | WS-AI-002, WS-AI-003, WS-AI-004, WS-AI-005, WS-AI-008, WS-AI-011, WS-AI-016, WS-AI-018, WS-SEC-001, WS-SEC-005, WS-SEC-022 |
| `LLM07` | System Prompt Leakage | WS-AI-022, WS-SEC-008 |
| `LLM08` | Vector and Embedding Weaknesses | WS-AI-012, WS-AI-024 |
| `LLM09` | Misinformation | WS-AI-021 |
| `LLM10` | Unbounded Consumption | WS-AI-019 |

### `OWASP-LLM26`

| ID | Item | Controls |
|---|---|---|
| `LLM01` | Prompt Injection | WS-AI-001, WS-AI-014, WS-AI-027 |
| `LLM02` | Sensitive Information Disclosure | WS-AI-022, WS-AI-023, WS-SEC-002, WS-SEC-003, WS-SEC-004, WS-SEC-007, WS-SEC-008, WS-SEC-009 |
| `LLM03` | Excessive Agency | WS-AI-002, WS-AI-003, WS-AI-004, WS-AI-005, WS-AI-008, WS-AI-011, WS-AI-016, WS-AI-018, WS-SEC-001, WS-SEC-005, WS-SEC-022 |
| `LLM04` | Supply Chain | WS-AI-009, WS-AI-010, WS-SEC-015, WS-SEC-016 |
| `LLM05` | Data and Model Poisoning | WS-AI-012, WS-AI-013, WS-AI-024 |
| `LLM06` | Unbounded Consumption | WS-AI-019 |
| `LLM07` | Misinformation | WS-AI-021 |
| `LLM08` | Hidden Context Exposure | WS-AI-022, WS-SEC-008 |
| `LLM09` | Vector and Embedding Weaknesses | WS-AI-012, WS-AI-024 |
| `LLM10` | Improper Output Handling | WS-AI-017, WS-AI-018, WS-AI-021, WS-SEC-028 |

### `OWASP-ASI`

| ID | Item | Controls |
|---|---|---|
| `ASI01` | Agent Goal Hijack | WS-AI-001, WS-AI-027, WS-AI-030 |
| `ASI02` | Tool Misuse and Exploitation | WS-AI-002, WS-AI-003, WS-AI-004, WS-AI-005, WS-AI-008, WS-AI-011, WS-AI-018, WS-SEC-003, WS-SEC-005 |
| `ASI03` | Identity and Privilege Abuse | WS-AI-002, WS-AI-003, WS-AI-007, WS-AI-015, WS-AI-016, WS-AI-026, WS-SEC-002, WS-SEC-006 |
| `ASI04` | Agentic Supply Chain Vulnerabilities | WS-AI-009, WS-AI-010, WS-SEC-015, WS-SEC-016, WS-GOV-002 |
| `ASI05` | Unexpected Code Execution | WS-AI-004, WS-AI-017, WS-AI-027, WS-SEC-001, WS-SEC-005, WS-SEC-022, WS-SEC-027 |
| `ASI06` | Memory and Context Poisoning | WS-AI-001, WS-AI-012, WS-AI-013, WS-AI-014, WS-AI-024 |
| `ASI07` | Insecure Inter-Agent Communication | WS-AI-015, WS-AI-029 |
| `ASI08` | Cascading Failures | WS-AI-015, WS-AI-019, WS-AI-025, WS-AI-028 |
| `ASI09` | Human-Agent Trust Exploitation | WS-AI-005, WS-AI-006, WS-AI-007, WS-AI-018, WS-AI-029 |
| `ASI10` | Rogue Agents | WS-AI-004, WS-AI-014, WS-AI-025, WS-AI-030, WS-SEC-010, WS-SEC-011, WS-GOV-003 |

### `OWASP-NHI`

| ID | Item | Controls |
|---|---|---|
| `NHI1` | Improper Offboarding | WS-GOV-010 |
| `NHI2` | Secret Leakage | WS-AI-022, WS-SEC-002, WS-SEC-004, WS-SEC-007, WS-SEC-008, WS-GOV-003 |
| `NHI3` | Vulnerable Third-Party NHI | WS-AI-009 |
| `NHI4` | Insecure Authentication | WS-AI-007, WS-SEC-012 |
| `NHI5` | Overprivileged NHI | WS-AI-003, WS-AI-026 |
| `NHI7` | Long-Lived Secrets | WS-SEC-007, WS-GOV-010 |
| `NHI8` | Environment Isolation | WS-AI-026, WS-SEC-006 |
| `NHI9` | NHI Reuse | WS-AI-015, WS-AI-026, WS-SEC-025 |
| `NHI10` | Human Use of NHI | WS-AI-026 |

### `OWASP-MCP3P`

| ID | Item | Controls |
|---|---|---|
| `authorization` | Authorization | WS-AI-005, WS-AI-011, WS-AI-012 |
| `client-sandboxing` | Client sandboxing | WS-AI-001, WS-AI-011 |
| `secure-server-discovery` | Secure server discovery | WS-AI-009, WS-AI-010 |
| `governance-workflows` | Governance workflows | WS-AI-010, WS-GOV-002 |

### `NIST-AI-RMF`

| ID | Item | Controls |
|---|---|---|
| `GOVERN-1.1` | Legal and regulatory requirements understood, managed and documented | WS-GOV-001 |
| `GOVERN-1.2` | Trustworthy AI characteristics integrated into policies | WS-GOV-001 |
| `GOVERN-1.3` | Risk management effort set by risk tolerance | WS-GOV-001 |
| `GOVERN-1.4` | Risk management process and outcomes established through transparent policies | WS-GOV-001 |
| `GOVERN-1.5` | Ongoing monitoring and periodic review planned | WS-GOV-004, WS-GOV-005 |
| `GOVERN-1.6` | Mechanisms to inventory AI systems | WS-GOV-002 |
| `GOVERN-1.7` | Processes to decommission AI systems safely | WS-GOV-010 |
| `GOVERN-2.1` | Roles, responsibilities and lines of communication documented | WS-GOV-009 |
| `GOVERN-2.2` | AI risk management training | WS-GOV-012 |
| `GOVERN-3.2` | Roles for human-AI configurations and oversight | WS-AI-005 |
| `GOVERN-4.2` | Risks and impacts documented and communicated | WS-GOV-006 |
| `GOVERN-4.3` | Practices for testing, incident identification and information sharing | WS-AI-027, WS-GOV-003 |
| `GOVERN-6.1` | Policies for third-party AI risks | WS-AI-009, WS-AI-010, WS-GOV-008 |
| `GOVERN-6.2` | Contingency for third-party failures | WS-GOV-003 |
| `MAP-1.1` | Intended purpose and context documented | WS-GOV-001, WS-GOV-011 |
| `MAP-1.5` | Risk tolerances documented | WS-GOV-001 |
| `MAP-2.1` | Task and methods defined | WS-AI-020 |
| `MAP-2.2` | Knowledge limits and human oversight documented | WS-GOV-012 |
| `MAP-3.1` | Benefits documented | WS-GOV-011 |
| `MAP-3.2` | Costs of AI errors documented | WS-GOV-011 |
| `MAP-3.3` | Application scope documented | WS-GOV-001 |
| `MAP-3.5` | Human oversight processes defined | WS-AI-004, WS-AI-005, WS-AI-015 |
| `MAP-4.1` | Legal and technology risks of third-party components mapped | WS-GOV-002 |
| `MAP-4.2` | Internal risk controls for third-party AI components | WS-AI-009 |
| `MAP-5.1` | Likelihood and magnitude of impacts documented | WS-GOV-004 |
| `MEASURE-1.1` | Metrics for significant risks | WS-GOV-005 |
| `MEASURE-1.2` | Metrics and controls reassessed | WS-GOV-005 |
| `MEASURE-2.1` | Test sets and tools documented | WS-AI-027 |
| `MEASURE-2.4` | Functionality and behavior monitored in production | WS-AI-019, WS-AI-030 |
| `MEASURE-2.5` | Validity and reliability | WS-AI-021 |
| `MEASURE-2.6` | Safety evaluated; fails safely | WS-AI-028 |
| `MEASURE-2.7` | Security and resilience evaluated | WS-AI-001, WS-AI-012, WS-AI-027 |
| `MEASURE-2.8` | Transparency and accountability risks examined | WS-AI-006, WS-AI-029, WS-SEC-010 |
| `MEASURE-2.10` | Privacy risks examined | WS-AI-022, WS-AI-023 |
| `MEASURE-3.1` | Emergent risks tracked after deployment | WS-AI-006, WS-AI-013 |
| `MEASURE-3.3` | User feedback and appeal channels | WS-GOV-007 |
| `MANAGE-1.1` | Decide whether to proceed | WS-GOV-011 |
| `MANAGE-1.2` | Risk treatment prioritized | WS-GOV-004 |
| `MANAGE-1.3` | Responses to high-priority risks planned | WS-AI-002 |
| `MANAGE-1.4` | Residual risks documented | WS-GOV-004, WS-GOV-006, WS-GOV-011 |
| `MANAGE-2.2` | Mechanisms sustain value of deployed systems | WS-AI-019 |
| `MANAGE-2.3` | Respond to and recover from unknown risks | WS-AI-025, WS-GOV-003 |
| `MANAGE-2.4` | Mechanisms to supersede, disengage or deactivate AI systems | WS-AI-004, WS-AI-025 |
| `MANAGE-3.1` | Third-party risks monitored | WS-AI-009, WS-GOV-008 |
| `MANAGE-3.2` | Pre-trained models monitored | WS-GOV-002 |
| `MANAGE-4.1` | Post-deployment monitoring plans | WS-AI-013, WS-AI-030 |
| `MANAGE-4.2` | Continuous improvement | WS-GOV-005 |
| `MANAGE-4.3` | Incidents and errors communicated and tracked | WS-GOV-003 |

### `NIST-600-1`

| ID | Item | Controls |
|---|---|---|
| `Confabulation` | Confabulation | WS-AI-021 |
| `Data Privacy` | Data Privacy | WS-AI-022, WS-AI-023, WS-SEC-009, WS-GOV-001, WS-GOV-008 |
| `Human-AI Configuration` | Human-AI Configuration | WS-AI-004, WS-AI-005, WS-AI-006, WS-AI-007, WS-AI-020, WS-GOV-012 |
| `Information Integrity` | Information Integrity | WS-AI-012, WS-AI-013, WS-AI-014, WS-AI-024 |
| `Information Security` | Information Security | WS-AI-001, WS-AI-002, WS-AI-011, WS-AI-012, WS-AI-017, WS-AI-022 |
| `Intellectual Property` | Intellectual Property | WS-AI-024, WS-GOV-001 |
| `Value Chain and Component Integration` | Value Chain and Component Integration | WS-AI-009, WS-SEC-015, WS-SEC-016, WS-SEC-018, WS-GOV-002, WS-GOV-008 |

### `SSDF`

| ID | Item | Controls |
|---|---|---|
| `PO.1` | Define security requirements for software development | WS-GOV-001 |
| `PO.2` | Implement roles and responsibilities | WS-GOV-009 |
| `PO.3` | Implement supporting toolchains | WS-SEC-004, WS-SEC-016, WS-SEC-017 |
| `PO.4` | Define and use criteria for software security checks | WS-SEC-004, WS-SEC-017, WS-GOV-005 |
| `PO.5` | Implement and maintain secure environments for software development | WS-SEC-001, WS-SEC-026 |
| `PS.1` | Protect all forms of code from unauthorized access and tampering | WS-AI-014, WS-SEC-005, WS-GOV-009 |
| `PS.2` | Provide a mechanism for verifying software release integrity | WS-SEC-015 |
| `PS.3` | Archive and protect each software release | WS-SEC-015, WS-SEC-018 |
| `PW.1` | Design software to meet security requirements and mitigate security risks | WS-GOV-004 |
| `PW.2` | Review the software design | WS-GOV-004 |
| `PW.4` | Reuse existing, well-secured software | WS-AI-009, WS-SEC-016, WS-SEC-018 |
| `PW.5` | Create source code by adhering to secure coding practices | WS-AI-017, WS-SEC-027, WS-SEC-028 |
| `PW.7` | Review and/or analyze human-readable code | WS-AI-021, WS-SEC-004, WS-SEC-008, WS-SEC-017 |
| `PW.8` | Test executable code | WS-AI-021, WS-AI-027, WS-SEC-017 |
| `PW.9` | Configure software to have secure settings by default | WS-AI-002, WS-AI-003, WS-AI-008 |
| `RV.1` | Identify and confirm vulnerabilities on an ongoing basis | WS-SEC-017, WS-GOV-007 |
| `RV.2` | Assess, prioritize and remediate vulnerabilities | WS-GOV-007 |
| `RV.3` | Analyze vulnerabilities to identify root causes | WS-GOV-003 |

### `SSDF-1.2-IPD`

| ID | Item | Controls |
|---|---|---|
| `PO.6` | Continuous improvement (draft) | WS-GOV-005 |
| `PW.10` | Robust updates (draft) | WS-SEC-015 |

### `SSDF-218A`

| ID | Item | Controls |
|---|---|---|
| `PW.4` | Reuse well-secured software (AI considerations) | WS-AI-009 |
| `PW.8` | Test executable code (AI considerations) | WS-AI-027 |

### `CSF`

| ID | Item | Controls |
|---|---|---|
| `GV.PO-01` | Policy for managing cybersecurity risks established | WS-GOV-001, WS-GOV-006 |
| `GV.OV-01` | Risk strategy outcomes reviewed | WS-GOV-005 |
| `GV.RR-02` | Roles, responsibilities and authorities established | WS-GOV-009, WS-GOV-012 |
| `GV.SC-05` | Supply chain requirements | WS-GOV-008 |
| `GV.SC-07` | Ongoing supplier risk monitoring | WS-AI-009, WS-SEC-016, WS-GOV-008 |
| `GV.SC-08` | Suppliers included in incident response | WS-GOV-003 |
| `ID.AM-02` | Software, services and systems inventory | WS-SEC-018, WS-GOV-002 |
| `ID.AM-04` | Supplier services inventory | WS-GOV-002 |
| `ID.AM-07` | Data inventory and metadata | WS-AI-013, WS-GOV-002 |
| `ID.AM-08` | Life cycle management | WS-GOV-010 |
| `ID.RA-01` | Asset vulnerability identification | WS-SEC-019, WS-SEC-026 |
| `ID.RA-03` | Threat identification | WS-GOV-004 |
| `ID.RA-05` | Inherent risk and response prioritization | WS-GOV-004 |
| `ID.RA-07` | Change and exception management | WS-GOV-009 |
| `ID.RA-08` | Vulnerability disclosure handling | WS-GOV-007 |
| `ID.RA-09` | Hardware and software integrity checks | WS-AI-009, WS-SEC-015, WS-SEC-016 |
| `ID.IM-01` | Improvements identified from evaluations | WS-GOV-005 |
| `PR.AA-01` | Identity and credential management | WS-AI-007, WS-AI-026, WS-SEC-002, WS-SEC-007, WS-SEC-025, WS-GOV-010 |
| `PR.AA-05` | Access permissions and authorization | WS-AI-002, WS-AI-003, WS-AI-004, WS-AI-005, WS-AI-007, WS-AI-008, WS-AI-011, WS-AI-015, WS-AI-016, WS-AI-018, WS-AI-026, WS-SEC-006, WS-SEC-020, WS-SEC-022 |
| `PR.DS-01` | Data-at-rest protection | WS-AI-023, WS-SEC-002, WS-SEC-007, WS-SEC-008, WS-SEC-012, WS-SEC-013, WS-SEC-020 |
| `PR.DS-02` | Data-in-transit protection | WS-AI-022, WS-SEC-009 |
| `PR.DS-10` | Data-in-use protection | WS-AI-012, WS-AI-014, WS-AI-022 |
| `PR.DS-11` | Data backups | WS-SEC-013, WS-SEC-014 |
| `PR.PS-01` | Configuration management | WS-AI-002, WS-AI-014, WS-AI-028, WS-SEC-001, WS-SEC-026, WS-SEC-027 |
| `PR.PS-02` | Software maintenance, replacement and removal | WS-SEC-015, WS-SEC-019 |
| `PR.PS-04` | Log generation and availability | WS-SEC-010, WS-SEC-011, WS-SEC-023 |
| `PR.PS-05` | Unauthorized software prevention | WS-AI-010, WS-SEC-005 |
| `PR.PS-06` | Secure software development | WS-AI-021, WS-SEC-004, WS-SEC-017 |
| `PR.IR-01` | Networks protected from unauthorized logical access | WS-AI-011, WS-SEC-001, WS-SEC-003, WS-SEC-012, WS-SEC-021, WS-SEC-022 |
| `DE.CM-01` | Network and network service monitoring | WS-AI-030, WS-SEC-003, WS-SEC-021 |
| `DE.CM-03` | Personnel activity and technology usage monitoring | WS-AI-006, WS-SEC-010 |
| `DE.CM-06` | External service provider monitoring | WS-GOV-008 |
| `DE.CM-09` | Computing hardware, software and runtime monitoring | WS-AI-001, WS-AI-019, WS-AI-030, WS-SEC-024 |
| `DE.AE-02` | Adverse events analyzed | WS-AI-030 |
| `DE.AE-03` | Information correlated across sources | WS-AI-030 |
| `RS.MA-01` | Incident response plan executed | WS-AI-025, WS-GOV-003 |
| `RC.RP-01` | Recovery portion of the plan executed | WS-SEC-014, WS-GOV-003 |

### `CIS-v8`

| ID | Item | Controls |
|---|---|---|
| `1.1` | Establish and Maintain Detailed Enterprise Asset Inventory | WS-GOV-002 |
| `2.1` | Establish and Maintain a Software Inventory | WS-SEC-018, WS-GOV-002 |
| `2.2` | Ensure Authorized Software is Currently Supported | WS-AI-009, WS-SEC-016 |
| `2.3` | Address Unauthorized Software | WS-AI-010 |
| `2.5` | Allowlist Authorized Software | WS-AI-010 |
| `2.7` | Allowlist Authorized Scripts | WS-AI-008, WS-AI-018, WS-SEC-005, WS-SEC-022 |
| `3.3` | Configure Data Access Control Lists | WS-SEC-002, WS-SEC-012, WS-SEC-020, WS-SEC-022 |
| `3.4` | Enforce Data Retention | WS-AI-023, WS-SEC-013 |
| `3.11` | Encrypt Sensitive Data at Rest | WS-AI-023, WS-SEC-007 |
| `3.13` | Deploy a Data Loss Prevention Solution | WS-AI-022, WS-SEC-009 |
| `4.1` | Establish and Maintain a Secure Configuration Process | WS-AI-002, WS-AI-014, WS-SEC-001, WS-SEC-026, WS-GOV-005 |
| `4.5` | Implement and Manage a Firewall on End-User Devices | WS-SEC-003, WS-SEC-021 |
| `4.8` | Uninstall or Disable Unnecessary Services | WS-SEC-021 |
| `5.4` | Restrict Administrator Privileges to Dedicated Administrator Accounts | WS-AI-026, WS-SEC-025 |
| `6.2` | Establish an Access Revoking Process | WS-GOV-010 |
| `6.8` | Define and Maintain Role-Based Access Control | WS-AI-003, WS-AI-026, WS-SEC-006 |
| `7.1` | Establish and Maintain a Vulnerability Management Process | WS-SEC-019 |
| `7.3` | Perform Automated Operating System Patch Management | WS-SEC-019 |
| `7.4` | Perform Automated Application Patch Management | WS-SEC-019 |
| `8.2` | Collect Audit Logs | WS-SEC-010, WS-SEC-023 |
| `8.3` | Ensure Adequate Audit Log Storage | WS-SEC-011 |
| `8.5` | Collect Detailed Audit Logs | WS-SEC-010 |
| `8.7` | Collect URL Request Audit Logs | WS-SEC-010 |
| `8.8` | Collect Command-Line Audit Logs | WS-SEC-010 |
| `8.9` | Centralize Audit Logs | WS-SEC-011 |
| `8.10` | Retain Audit Logs | WS-SEC-011 |
| `8.11` | Conduct Audit Log Reviews | WS-AI-030 |
| `11.1` | Establish and Maintain a Data Recovery Process | WS-SEC-014 |
| `11.2` | Perform Automated Backups | WS-SEC-013 |
| `11.3` | Protect Recovery Data | WS-SEC-013 |
| `11.5` | Test Data Recovery | WS-SEC-014 |
| `15.1` | Establish and Maintain an Inventory of Service Providers | WS-GOV-002, WS-GOV-008 |
| `15.4` | Ensure Service Provider Contracts Include Security Requirements | WS-GOV-008 |
| `15.6` | Monitor Service Providers | WS-GOV-008 |
| `16.1` | Establish and Maintain a Secure Application Development Process | WS-SEC-017 |
| `16.2` | Establish and Maintain a Process to Accept and Address Software Vulnerabilities | WS-GOV-007 |
| `16.4` | Establish and Manage an Inventory of Third-Party Software Components | WS-SEC-004, WS-SEC-018 |
| `16.5` | Use Up-to-Date and Trusted Third-Party Software Components | WS-AI-009, WS-SEC-015, WS-SEC-016 |
| `16.12` | Implement Code-Level Security Checks | WS-AI-017, WS-AI-021, WS-AI-027, WS-SEC-004, WS-SEC-008, WS-SEC-017, WS-SEC-027, WS-SEC-028 |
| `16.14` | Conduct Threat Modeling | WS-GOV-004 |
| `17.1` | Designate Personnel to Manage Incident Handling | WS-GOV-003 |
| `17.4` | Establish and Maintain an Incident Response Process | WS-AI-025, WS-GOV-003 |
| `17.7` | Conduct Routine Incident Response Exercises | WS-GOV-003 |
| `17.8` | Conduct Post-Incident Reviews | WS-GOV-003 |

### `CIS-Ubuntu`

| ID | Item | Controls |
|---|---|---|
| `Software updates` | Software updates (id unverified) | WS-SEC-019 |
| `Host based firewall` | Host based firewall (id unverified) | WS-SEC-021 |
| `Configure SSH server` | Configure SSH server (id unverified) | WS-SEC-021 |
| `Default user umask` | Default user umask (id unverified) | WS-SEC-020 |
| `User home directory permissions` | User home directory permissions (id unverified) | WS-SEC-020 |
| `System file permissions` | System file permissions (id unverified) | WS-SEC-001 |
| `Configure auditd` | Configure auditd (id unverified) | WS-SEC-023 |
| `Configure journald` | Configure journald (id unverified) | WS-SEC-023 |

### `NSA-DAISS`

| ID | Item | Controls |
|---|---|---|
| `Manage deployment environment governance` | Manage deployment environment governance | WS-SEC-026 |
| `Ensure a robust deployment environment architecture` | Ensure a robust deployment environment architecture | WS-AI-003, WS-SEC-001 |
| `Harden deployment environment configurations` | Harden deployment environment configurations | WS-AI-014, WS-SEC-022 |
| `Protect deployment networks from threats` | Protect deployment networks from threats | WS-SEC-003, WS-SEC-021 |
| `Validate the AI system before and during use` | Validate the AI system before and during use | WS-AI-001, WS-AI-009 |
| `Secure exposed APIs` | Secure exposed APIs | WS-AI-007, WS-AI-011 |
| `Actively monitor model behavior` | Actively monitor model behavior | WS-AI-019, WS-AI-030 |
| `Enforce strict access controls` | Enforce strict access controls | WS-AI-002, WS-SEC-002 |
| `Ensure user awareness and training` | Ensure user awareness and training | WS-GOV-012 |
| `Conduct audits and penetration testing` | Conduct audits and penetration testing | WS-AI-027 |
| `Implement robust logging and monitoring` | Implement robust logging and monitoring | WS-SEC-010 |
| `Update and patch regularly` | Update and patch regularly | WS-SEC-015, WS-SEC-019 |
| `Prepare for high availability (HA) and disaster recovery (DR)` | Prepare for high availability (HA) and disaster recovery (DR) | WS-SEC-013, WS-SEC-014 |
| `Plan secure delete capabilities` | Plan secure delete capabilities | WS-AI-023 |

### `NSA-AIDATA`

| ID | Item | Controls |
|---|---|---|
| `BP1` | Source reliable data and track data provenance | WS-AI-001, WS-AI-012, WS-AI-013, WS-AI-024 |
| `BP2` | Verify and maintain data integrity during storage and transport | WS-AI-012, WS-SEC-011 |
| `BP3` | Employ digital signatures to authenticate trusted data revisions | WS-AI-013, WS-SEC-011 |
| `BP4` | Leverage trusted infrastructure | WS-SEC-001, WS-SEC-003 |
| `BP5` | Classify data and use access controls | WS-SEC-002 |
| `BP6` | Encrypt data | WS-AI-023, WS-SEC-007, WS-SEC-013 |
| `BP7` | Store data securely | WS-SEC-013 |
| `BP8` | Leverage privacy-preserving techniques | WS-AI-022 |
| `BP9` | Delete data securely | WS-AI-023, WS-GOV-010 |
| `BP10` | Conduct ongoing data security risk assessments | WS-AI-013 |

### `NSA-AGENTIC`

| ID | Item | Controls |
|---|---|---|
| `privilege risks` | Privilege risks (category name from secondary summaries; id unverified) | WS-AI-002, WS-AI-004, WS-AI-026 |
| `structural risks` | Structural risks (id unverified) | WS-AI-015 |
| `accountability risks` | Accountability risks (id unverified) | WS-AI-005, WS-AI-006, WS-AI-026, WS-SEC-010, WS-SEC-011 |

### `WAF-SEC`

| ID | Item | Controls |
|---|---|---|
| `SE:01` | Establish a security baseline | WS-AI-002, WS-SEC-026, WS-GOV-005 |
| `SE:02` | Align secure development lifecycle | WS-AI-009, WS-AI-021, WS-SEC-004, WS-SEC-015, WS-SEC-016, WS-SEC-017, WS-SEC-018, WS-GOV-009 |
| `SE:03` | Classify and apply sensitivity labels | WS-AI-022, WS-SEC-009, WS-GOV-002 |
| `SE:04` | Create intentional segmentation and perimeters | WS-AI-003, WS-AI-015, WS-SEC-001, WS-SEC-006, WS-SEC-022 |
| `SE:05` | Strict, conditional and auditable IAM | WS-AI-003, WS-AI-007, WS-AI-008, WS-AI-016, WS-AI-026, WS-SEC-025 |
| `SE:06` | Isolate, filter and control network traffic | WS-AI-011, WS-SEC-003, WS-SEC-012, WS-SEC-021 |
| `SE:07` | Encrypt data | WS-AI-023, WS-SEC-013 |
| `SE:08` | Harden all workload components | WS-AI-002, WS-AI-010, WS-AI-014, WS-AI-028, WS-SEC-001, WS-SEC-005, WS-SEC-019, WS-SEC-020, WS-SEC-027, WS-SEC-028 |
| `SE:09` | Protect application secrets | WS-SEC-002, WS-SEC-004, WS-SEC-007, WS-SEC-008, WS-GOV-010 |
| `SE:10` | Holistic monitoring strategy | WS-AI-030, WS-SEC-010, WS-SEC-011, WS-SEC-023 |
| `SE:11` | Comprehensive testing regimen | WS-AI-027, WS-SEC-017, WS-GOV-004 |
| `SE:12` | Define and test incident response procedures | WS-AI-025, WS-SEC-014, WS-GOV-003 |

### `WAF-AI`

| ID | Item | Controls |
|---|---|---|
| `application-design` | Application design | WS-AI-001, WS-AI-017 |
| `grounding-data-design` | Grounding data design | WS-AI-012, WS-AI-024 |
| `operations` | Workload operations | WS-AI-006, WS-AI-019 |
| `responsible-ai` | Responsible AI | WS-GOV-001 |

### `CAF`

| ID | Item | Controls |
|---|---|---|
| `govern.assess-risks` | Govern AI: 1. Assess AI organizational risks | WS-GOV-008, WS-GOV-011 |
| `govern.document-policies` | Govern AI: 2. Document AI governance policies | WS-AI-009, WS-AI-020, WS-GOV-001 |
| `govern.enforce-policies` | Govern AI: 3. Enforce AI governance policies | WS-AI-005, WS-AI-010 |
| `govern.monitor-risks` | Govern AI: 4. Monitor AI organizational risks | WS-GOV-005 |
| `secure.discover-risks` | Secure AI: Discover AI security risks | WS-AI-001, WS-AI-027, WS-GOV-004 |
| `secure.protect-resources` | Secure AI: Protect AI resources and data - Secure AI resources | WS-GOV-002 |
| `secure.protect-data` | Secure AI: Protect AI resources and data - Secure AI data | WS-AI-022 |
| `secure.detect-threats` | Secure AI: Detect AI security threats | WS-AI-030, WS-GOV-003 |

### `MS-RAI`

| ID | Item | Controls |
|---|---|---|
| `Reliability and Safety` | Reliability and Safety | WS-AI-002, WS-AI-021, WS-AI-028, WS-GOV-004 |
| `Privacy and Security` | Privacy and Security | WS-AI-022, WS-AI-023, WS-GOV-001 |
| `Transparency` | Transparency | WS-SEC-010, WS-GOV-006, WS-GOV-011, WS-GOV-012 |
| `Accountability` | Accountability | WS-AI-004, WS-AI-005, WS-AI-020, WS-AI-025, WS-GOV-001 |

### `ISO42001`

| ID | Item | Controls |
|---|---|---|
| `4` | Context of the organization | WS-GOV-011 |
| `5` | Leadership | WS-GOV-001 |
| `6` | Planning | WS-GOV-004 |
| `7` | Support | WS-GOV-006, WS-GOV-012 |
| `8` | Operation | WS-GOV-004, WS-GOV-011 |
| `9` | Performance evaluation | WS-GOV-005 |
| `10` | Improvement | WS-GOV-003, WS-GOV-005 |
| `A.2` | Policies related to AI | WS-GOV-001 |
| `A.3` | Internal organization | WS-AI-026, WS-GOV-009 |
| `A.4` | Resources for AI systems | WS-GOV-002 |
| `A.5` | Assessing impacts of AI systems | WS-GOV-004, WS-GOV-011 |
| `A.6` | AI system life cycle | WS-AI-021, WS-AI-025, WS-SEC-010, WS-SEC-011, WS-SEC-015, WS-GOV-006, WS-GOV-010 |
| `A.7` | Data for AI systems | WS-AI-012, WS-AI-013, WS-AI-023, WS-AI-024 |
| `A.8` | Information for interested parties of AI systems | WS-GOV-003, WS-GOV-007, WS-GOV-012 |
| `A.9` | Use of AI systems | WS-AI-002, WS-AI-004, WS-AI-005, WS-AI-006, WS-AI-007, WS-AI-015, WS-AI-018, WS-AI-020, WS-GOV-001 |
| `A.10` | Third-party and customer relationships | WS-AI-009, WS-AI-010, WS-SEC-025, WS-GOV-008 |

### `ATLAS`

| ID | Item | Controls |
|---|---|---|
| `AML.T0051` | LLM Prompt Injection | WS-AI-001 |
| `AML.T0080` | AI Agent Context Poisoning | WS-AI-012 |
| `AML.T0080.000` | Memory | WS-AI-012 |
