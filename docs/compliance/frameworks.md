# Frameworks

The AI, security and governance frameworks the control catalogue ([controls.yaml](controls.yaml)) maps to: the version
in force on 2026-11-26, where it was verified, how it applies to a single-user developer workstation that runs AI
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

Verified online on 2026-11-26 (round 4; first on 2026-11-25) from the official pages listed, unless the notes say otherwise.

| Prefix | Framework | Version | Date | Official URL | How it applies to this workstation | Out of scope, and why |
|---|---|---|---|---|---|---|
| `OWASP-LLM25` | OWASP Top 10 for LLM Applications | 2025 edition | November 2024 | <https://genai.owasp.org/llm-top-10/> | The risk list for the LLM the agents call and for the kit scripts that consume model output. | Model training and hosting: the kit uses a hosted model and trains nothing. |
| `OWASP-LLM26` | OWASP GenAI LLM Top 10 | 2026 edition (current) | 2026-08-03 (resource page; the PDF cover still reads "Publication date to be set") | <https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/> | Supersedes the 2025 list; every 2025 mapping is carried over by the [crosswalk](#owasp-llm-top-10-2025-to-2026). | Same as 2025. |
| `OWASP-ASI` | OWASP Top 10 for Agentic Applications | 2026 edition | 2025-12-09 | <https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/> | The primary list: the kit is an agent harness with tools, memory, parallel agents and a remote approval channel. | Nothing; all ten items apply. |
| `OWASP-NHI` | OWASP Non-Human Identities Top 10 | 2025 (no 2026 edition found) | Not stated on the page | <https://owasp.org/projects/non-human-identities-top-10> | Agents act with the user's tokens; the kit keeps its own bot token, PIN and backup key. | `NHI6` cloud deployment configuration: the kit deploys nothing to the cloud. |
| `OWASP-MCP3P` | CheatSheet: A Practical Guide for Securely Using Third-Party MCP Servers | 1.0 | 2025-11-04 | <https://genai.owasp.org/resource/cheatsheet-a-practical-guide-for-securely-using-third-party-mcp-servers-1-0/> | The kit registers five third-party MCP servers. Items are the mitigation topics named on the resource page. | Nothing within the topics used. |
| - | A Practical Guide for Secure MCP Server Development | Final (no version number shown) | 2026-02-16 | <https://genai.owasp.org/resource/a-practical-guide-for-secure-mcp-server-development/> | Listed for completeness. | Not mapped: the kit develops no MCP server; it only configures them. |
| `OWASP-AITM` | Agentic AI - Threats and Mitigations | 1.1 | December 2025 (cover of the PDF the page now serves; the page still shows 2025-02-17, the date of 1.0) | <https://genai.owasp.org/resource/agentic-ai-threats-and-mitigations/> | The threat taxonomy behind the agentic Top 10: `T1` to `T17`, read from the "Detailed Threat Model" table of the 1.1 PDF. | Nothing: all seventeen threats are mapped; `T14` and `T16` only through the swarm and the MCP and inter-agent controls. |
| `OWASP-MCP10` | OWASP MCP Top 10 | 2025 (beta: "Phase 3 - Beta Release and Pilot Testing") | Not stated | <https://owasp.org/www-project-mcp-top-10/> | `MCP01` to `MCP10` for the five MCP servers the kit registers and confines. | Nothing. Titles may still change while the list is in beta; `MCP06` has two titles (project page and repository), both recorded. |
| `OWASP-RTM` | GenAI Red Teaming Manual: A Practical Guide for Adversarial Testing of Generative AI Models & Systems | 1.0 | October 2026 (page 2026-10-20) | <https://genai.owasp.org/resource/genai-red-teaming-manual-version-1-0/> | The adversarial test catalogue for WS-AI-027 and the `ws-audit --ai` cases; items are section numbers (the manual's test-case ids such as TS-1 or TC-2 are local to each section). | Model-level testing (weights, training data, fine-tuning): no model is trained or hosted. |
| `OWASP-SAA` | Securing Agentic Applications (V2: A Builder & Defender's Guide) | 2.0 | October 2026 (page 2026-11-10) | <https://genai.owasp.org/resource/securing-agentic-applications-v2/> | Key components `KC1` to `KC6.6`; its section 5.5.1 (coding and computer-use agents) describes this workstation. | Orchestration and reasoning components the kit does not build (`KC1` to `KC3`); `KC6.6` operating critical systems. |
| - | GenAI Red Teaming Guide: A Practical Approach to Evaluating AI Vulnerabilities | 1.0 | 2025-01-22 | <https://genai.owasp.org/resource/genai-red-teaming-guide/> | Its appendix D names twelve agentic red-teaming tasks; the newer Manual (`OWASP-RTM`) gives them test cases and oracles. | Not mapped: the Manual is cited instead. |
| - | Securing Agentic Applications Guide | 1.0 | 2025-07-27 | <https://genai.owasp.org/resource/securing-agentic-applications-guide-1-0/> | Superseded by V2. | Not mapped. |
| - | AIVSS Scoring System For OWASP Agentic AI Core Security Risks | v0.8 (document); the AIVSS 1.0 calculator is marked live on the site | Not stated (released with the AIUC-1 crosswalk, 2026) | <https://aivss.owasp.org/> | A scoring method over CVSS v4.0 for ten core agentic risks; usable to score a finding of this catalogue. | Not mapped: a scoring system, not a control list, and its risks carry no identifiers. |
| - | State of Agentic AI Security and Governance | 2.01 | June 2026 | <https://genai.owasp.org/resource/state-of-agentic-ai-security-and-governance/> | Landscape report. | Not mapped: no requirements or identifiers. |
| - | Multi-Agentic system Threat Modeling Guide | 1.0 | 2025-04-23 | <https://genai.owasp.org/resource/multi-agentic-system-threat-modeling-guide-v1-0/> | Read for the swarm threat model (docs/THREAT_MODEL.md). | Not mapped: identifiers not verified (the PDF was not read). |
| - | Agent Name Service (ANS) for Secure Al Agent Discovery ("Al" as published) | 1.0 | 2025-05-14 | <https://genai.owasp.org/resource/agent-name-service-ans-for-secure-al-agent-discovery-v1-0/> | - | Not applicable: the kit discovers no agents over a network. |
| - | OWASP Secure Coding with AI Cheat Sheet | Not stated | Not stated | <https://cheatsheetseries.owasp.org/cheatsheets/Secure_Coding_with_AI_Cheat_Sheet.html> | Names Claude Code; its sections on indirect injection in the development loop, MCP, sandboxing, rules files and sub-agent propagation match the kit's controls. | Not mapped: no identifiers. |
| - | OWASP Agent Control Standard (ACS) | Release 0.1.5 (specification 0.1.0; 0.2.0 planned for March 2027) | Page 2026-09-01 | <https://genai.owasp.org/resource/agent-control-standard-acs/> | Runtime enforcement for agents; the kit's hooks already implement its allow, deny, ask and modify dispositions. | Not mapped: it defines hook methods and profiles, not control identifiers. |
| `NIST-AI-RMF` | NIST AI Risk Management Framework (NIST AI 100-1) and Playbook | 1.0 | 2023-01-26 | <https://www.nist.gov/itl/ai-risk-management-framework>, <https://airc.nist.gov/airmf-resources/playbook/> | GOVERN, MAP, MEASURE and MANAGE subcategories that one owner can act on: inventory, oversight, monitoring, incidents, third parties. | Subcategories about teams, diversity, external stakeholders and model evaluation science (see the assessment's not-mapped list). NIST states a revision is in progress; none is published. |
| `NIST-600-1` | NIST AI 600-1, Generative AI Profile | Final | 2024-07-26 | <https://doi.org/10.6028/NIST.AI.600-1> | The 12 GAI risks; seven concern how the agents handle data, code, memory and suppliers. | Content-harm risks (CBRN, violent or abusive content, bias, environment): the kit constrains actions, not model text. |
| `SSDF` | NIST SP 800-218, Secure Software Development Framework | 1.1 | 2022-02 | <https://csrc.nist.gov/pubs/sp/800/218/final> | The kit is software: its own development, CI, releases and update channel. | `PW.6` compilation settings: the kit is shell and Python scripts with nothing to compile. |
| `SSDF-1.2-IPD` | NIST SP 800-218 Rev. 1 (SSDF 1.2), initial public draft | 1.2 draft | 2025-12-17 | <https://csrc.nist.gov/pubs/sp/800/218/r1/ipd> | Only the two new practices reported by NIST (`PO.6` continuous improvement, `PW.10` robust updates). | Draft: comments closed 2026-01-30; a final version was not found. |
| `SSDF-218A` | NIST SP 800-218A, SSDF Community Profile for Generative AI and Dual-Use Foundation Models | Final | 2024-07-26 | <https://csrc.nist.gov/pubs/sp/800/218/a/final> | It augments SSDF practices with AI considerations; cited at practice level for third-party AI components and testing. | Model training, weights and data pipelines: the kit produces no model. The profile's own new task IDs were not verified. |
| `CSF` | NIST Cybersecurity Framework | 2.0 | 2024-02-26 | <https://www.nist.gov/cyberframework> | Subcategories for identity, data, platform, logging, monitoring, supply chain and response on one workstation. | Categories that need an organisation: `GV.OC`, `GV.RM`, `PR.AT`, `RS.AN`, `RS.CO`, `RS.MI`, `RC.CO`. The NIST Cyber AI Profile (NIST IR 8596) is still the initial preliminary draft of 2025-12-16 and is not mapped; the SP 800-53 overlays for AI (COSAiS, renamed COSIS on 2026-10-20) have no public draft of any overlay yet. |
| `CIS-v8` | CIS Critical Security Controls | 8.1 | 2024-06-25 | <https://www.cisecurity.org/controls/v8-1> | Safeguards that make sense for one developer endpoint: software inventory, secure configuration, data protection, logging, backups, application security. Every Implementation Group 1 safeguard was reviewed (56, [CIS Controls Navigator](https://www.cisecurity.org/controls/cis-controls-navigator)); those that apply are mapped. | Enterprise network infrastructure and monitoring (12, 13), physical and HR safeguards, penetration testing programmes (18), awareness programmes (14). IG1 safeguards left to the organisation's Windows and identity baseline: 3.6 device encryption, 4.3 session locking, 4.7 default accounts, 5.2 and 5.3 passwords and dormant accounts, 6.3 to 6.5 MFA, 9.1 and 9.2 browsers and DNS filtering, 10.1 to 10.3 anti-malware, 12.1 network infrastructure, 14.1 to 14.8 awareness. No v8.2 or v9 was found. |
| `CIS-Ubuntu` | CIS Ubuntu Linux 24.04 LTS Benchmark | 2.0.0 | 2026 (listed in CIS's June 2026 update) | <https://www.cisecurity.org/benchmark/ubuntu_linux> | Only the items the kit configures or checks: updates, permissions, umask, firewall and listening services, sshd, logging. | Section numbers are not cited: the benchmark PDF is licensed and v2.0.0 renumbered sections. Boot, partitioning, kernel modules and AppArmor are not evaluated because the kit neither configures nor checks them and WSL's kernel differs. Whether a WSL-specific benchmark exists was not verified. |
| - | CIS Microsoft Windows 11 Enterprise Benchmark | 5.1.1 (download page; 5.1.0 was announced in the September 2026 update) | Not stated | <https://www.cisecurity.org/benchmark/microsoft_windows_desktop> | The kit touches Windows only through the Credential Manager, a PowerShell profile and an HKCU protocol handler. | Not mapped: the Windows baseline is the organisation's; the kit changes no Windows security setting. |
| `NSA-DAISS` | NSA AISC and partners, Deploying AI Systems Securely (CSI) | 1.0 | 2024-04-15 | <https://media.defense.gov/2024/Apr/15/2003439257/-1/-1/0/CSI-DEPLOYING-AI-SYSTEMS-SECURELY.PDF> | The deployment environment here is the workstation: governance, hardening, monitoring, access control, updates. Items are the guidance's headings. | "Protect model weights": the kit hosts no model. |
| `NSA-AIDATA` | NSA AISC and partners, AI Data Security: Best Practices for Securing Data Used to Train & Operate AI Systems (CSI) | Final | 2025-05-22 | <https://media.defense.gov/2025/May/22/2003720601/-1/-1/0/CSI_AI_DATA_SECURITY.PDF> | The data that operates the agents: prompts, memory, retrieval corpora, telemetry and backups. Items `BP1` to `BP10` are the ten numbered best practices. | Training-data sections (data drift, poisoned training sets): no training happens here. |
| `NSA-AGENTIC` | ASD's ACSC, CISA, NSA and partners, Careful Adoption of Agentic AI Services | Final | 2026-05-01 | <https://www.cyber.gov.au/business-government/secure-design/artificial-intelligence/careful-adoption-of-agentic-ai-services> | The five risk categories of agents: privilege, design and configuration, behavioural, structural and accountability; best practices grouped design, develop, deploy and operate. | Headings read on 2026-11-26 from the Canadian Centre for Cyber Security's copy (<https://cyber.gc.ca/en/guidance/careful-adoption-agentic-ai>, modified 2026-09-10); cyber.gov.au timed out. The catalogue cites the privilege, structural and accountability categories; design and configuration and behavioural risks are covered by the same controls (the guard, the levels, the filter) and not cited separately. |
| - | Canadian Centre for Cyber Security with CISA and partners, Managing AI Token Consumption for Operational Resilience (ITSM.00.125) | Final | October 2026 (page modified 2026-10-22, verified 2026-11-26) | <https://cyber.gc.ca/en/guidance/managing-ai-token-consumption-operational-resilience-itsm00125> | Spend caps and consumption monitoring (WS-AI-019: budgets, the hard stop and the per-session cap). | Not mapped: guidance without item identifiers; six section headings read, from "Demystifying AI tokens" to "Optimizing AI token usage". |
| - | NIST CAISSI, NSA and CISA, Key Practices for Incident Readiness and Response in Super Intelligence Training and Evaluation | Final | 2026-10-16 | <https://www.nist.gov/news-events/news/2026/10/key-practices-incident-readiness-and-response-super-intelligence-training> | - | Not applicable: incidents during model training and evaluation; no model is trained here. |
| `WAF-SEC` | Microsoft Azure Well-Architected Framework, Security checklist | Page updated 2026-06-26 | 2026-06-26 | <https://learn.microsoft.com/azure/well-architected/security/checklist> | `SE:01` to `SE:12` read with the workstation as the workload. | Azure platform services: the kit deploys none. |
| `WAF-REL` | Azure Well-Architected Framework, Reliability checklist | Page updated 2026-05-29 | 2026-05-29 | <https://learn.microsoft.com/azure/well-architected/reliability/checklist> | `RE:04` recovery targets, `RE:07` self-preservation, `RE:09` recovery plans and `RE:10` health, for one workstation and its backups. | `RE:02`, `RE:03`, `RE:05`, `RE:06`, `RE:08`: user flows, redundancy, scaling and chaos testing of a multi-instance workload. |
| `WAF-CO` | Azure Well-Architected Framework, Cost Optimization checklist | Page updated 2025-10-30 | 2025-10-30 | <https://learn.microsoft.com/azure/well-architected/cost-optimization/checklist> | `CO:03` and `CO:04`: the model spend the kit measures and caps. | The rest (rates, billing increments, environment, data and scaling costs): Azure billing of workloads the kit does not deploy. |
| `WAF-OE` | Azure Well-Architected Framework, Operational Excellence checklist | 11 items, renumbered 2026-02-11 (page updated 2026-06-11) | 2026-02-11 | <https://learn.microsoft.com/azure/well-architected/operational-excellence/checklist> | `OE:04` quality, `OE:05` configuration as code, `OE:06` supply chain, `OE:08` incidents, `OE:09` testing, `OE:11` safe deployment, applied to the kit itself. | `OE:01` to `OE:03` and `OE:07`, `OE:10`: team practices and monitoring stacks of an organisation. The 2026 renumbering moved testing to `OE:09`, automation to `OE:10` and safe deployment to `OE:11`. |
| `WAF-PE` | Azure Well-Architected Framework, Performance Efficiency checklist | Page updated 2026-05-06 | 2026-04-20 | <https://learn.microsoft.com/azure/well-architected/performance-efficiency/checklist> | `PE:01`, `PE:04` and `PE:12`: budgets for the hooks on every tool call and for the shell start-up. | Capacity planning, scaling, data and critical-flow items of a cloud workload. |
| `WAF-AI` | Azure Well-Architected Framework, AI workload guidance | Page updated 2026-05-07 | 2026-05-07 | <https://learn.microsoft.com/azure/well-architected/ai/> | Application design, grounding data, operations, testing and responsible AI pages. | Training data design, data platform, application platform and the MLOps and GenAIOps page (updated 2026-11-06): no training or AI hosting here. |
| `MCSB` | Microsoft cloud security benchmark | v2 (preview); supersedes MCSB v1 (and through it the Azure Security Benchmark v3) | Overview 2026-01-15; domain pages reviewed 2025-12-01 | <https://learn.microsoft.com/security/benchmark/azure/overview> | The workstation is a privileged access workstation that operates Azure (PA-6), so only the controls a developer endpoint satisfies are mapped: privileged access, identity, DevOps security, logging, backup, incident response, posture, and the new AI Security domain (`AI-1` to `AI-7`). The monthly currency check watches the preview turning GA and a v3. | The controls for Azure services the kit does not deploy (most of NS, DP, AM, PV-3 and PV-4, DS-5 DAST, LT-2, LT-4); `ES-1` to `ES-3` are the organisation's endpoint protection (WS-SEC-024). v2 has no per-service baselines yet and no Governance and Strategy domain. |
| `CAF` | Microsoft Cloud Adoption Framework: AI adoption (Govern AI, Secure AI) and the Govern and Manage methodologies | Govern AI and Secure AI updated 2026-10-15; Govern 2026-06-25 (monitor compliance); Manage 2026-10-27 | 2026-10-15 | <https://learn.microsoft.com/azure/cloud-adoption-framework/ai/govern>, <https://learn.microsoft.com/azure/cloud-adoption-framework/ai/secure>, <https://learn.microsoft.com/azure/cloud-adoption-framework/govern/monitor-cloud-governance>, <https://learn.microsoft.com/azure/cloud-adoption-framework/manage/protect> | The governance and security process steps scaled to one owner. Items are the numbered steps of those pages. | AI strategy, plan, ready phases, Manage AI, the cloud governance team and the Secure methodology's organisational steps, Azure Policy, Purview and Defender: organisational and Azure-platform processes. |
| `MS-RAI` | Microsoft Responsible AI principles | Six principles (Responsible AI Standard v2, June 2022; no newer Standard; 2026 Transparency Report published) | 2022-06 | <https://www.microsoft.com/ai/responsible-ai> | Accountability, transparency, reliability and safety, privacy and security of how the agents are operated. | Fairness and inclusiveness: the kit makes no decisions about people. The Standard's goal IDs were not verified, so only principle names are used. |
| `ISO42001` | ISO/IEC 42001:2023, AI management system | 2023 (EN ISO/IEC 42001:2026 adopts it unchanged) | 2023-12 | <https://www.iso.org/standard/81230.html> | Clauses 4 to 10 and the Annex A control objective groups `A.2` to `A.10`, for the owner's own management of AI use. | The paid text was not available: clause names follow the ISO harmonized structure and Annex A group names come from public summaries; individual Annex A controls are not cited because summaries disagree on their numbering. Certification and organisational roles are out of scope. iso.org could not be read on 2026-11-25; a search index lists the standard as "to be revised". |
| `ISO25010` | ISO/IEC 25010:2023, Systems and software Quality Requirements and Evaluation (SQuaRE): Product quality model | Second edition | 2023-11 | <https://www.iso.org/standard/78176.html> | The nine product quality characteristics applied to the kit as a product; items are the characteristic names. | Sub-characteristics are not cited (they come from a secondary source); the quality-in-use model of ISO/IEC 25019 is not mapped. |
| `ATLAS` | MITRE ATLAS | Release 2026.10 (data format 6.1.0) | 2026-10-28 | <https://atlas.mitre.org>, <https://github.com/mitre-atlas/atlas-data> | Cross-reference for injection, memory poisoning and the agent techniques (tool invocation, configuration, credentials, exfiltration, tool poisoning, agentic resource consumption). | Model-level techniques (weights, training data). |
| - | EU AI Act (Regulation (EU) 2024/1689), as simplified by the AI Omnibus in force 2026-07-27 | - | - | <https://digital-strategy.ec.europa.eu/en/policies/regulatory-framework-ai> | The owner deploys a hosted general-purpose model for their own professional work: Article 4 (AI literacy) applies, covered by WS-GOV-012 and the AI use policy. The AI Omnibus turned Article 4 into an obligation of means for deployers ("take measures supporting" AI literacy) and moved the high-risk dates to 2027-12-02 (Annex III) and 2028-08-02 (Annex I), according to the Commission's page and law-firm summaries; the Official Journal text was not read. | Not mapped: no provider obligations (the kit trains and places no model on the market) and no high-risk use. |

## Version notes

- **OWASP LLM Top 10.** The 2026 edition is the current one; the 2025 edition requested for this phase is mapped and
  every 2025 reference is carried to 2026 automatically. The 2026 list has no "System Prompt Leakage" entry; the
  closest new entry is `LLM08:2026` Hidden Context Exposure. That pairing is inferred from the names; the official
  2025-to-2026 mapping inside the 2026 document was not read.
- **OWASP agentic work.** The Top 10 for Agentic Applications (December 2025) uses `ASI01` to `ASI10` and has no
  later revision. The Threats and Mitigations guide 1.1 (December 2025) is now read from its PDF and mapped as
  `OWASP-AITM` (`T1` to `T17`; `T16` Insecure Inter-Agent Protocol Abuse and `T17` Supply Chain Compromise are the
  additions over 1.0, and `T9` gained "Agent Identity Compromise"; the 1.0 list was recalled, not re-read).
- **OWASP GenAI project, round 3 (2026-11-25).** Added `OWASP-MCP10` (beta), `OWASP-RTM` (the Red Teaming Manual of
  October 2026, the only OWASP catalogue with pass and fail oracles for agents) and `OWASP-SAA` (Securing Agentic
  Applications V2, which calls coding agents "by definition, a Lethal Trifecta" and names CLAUDE.md and mcp.json as
  supply-chain vectors). The Red Teaming Manual's cases the kit did not test became `ws-audit --ai` cases (grant
  modification, MCP registration write, unsandboxed retry, an instruction planted in a README) and the fake-server
  test of `tests/mcp-jail.sh`; its "MCP definition drift (rug pull)" case is the new gap WS-AI-031.
- **SSDF.** Version 1.1 is final. Version 1.2 (SP 800-218 Rev. 1) is still the initial public draft of 2025-12-17
  (comments closed 2026-01-30, no second draft); NIST's slides of 2026-05-20 name the new practices `PO.6` Continuous
  Process Improvement and `PW.10` Robust and Reliable Updates, cited with the `SSDF-1.2-IPD` prefix.
- **NIST AI RMF.** 1.0 remains in force; NIST states it "is being revised as part of the White House AI Action Plan",
  with no draft. NIST AI 600-1, SP 800-218A and CSF 2.0 are unchanged.
- **"Super Intelligence" labels.** After a US Executive Order of 2026-09-29, NIST and CISA web pages write "SI" for
  "AI" (for example "Deploying SI Systems Securely"); NIST states that previously issued documents were not altered,
  so the catalogue cites the original titles and identifiers.
- **Microsoft cloud security benchmark.** v2 is a preview ("Microsoft cloud security benchmark v2 is currently in
  preview") that supersedes v1; v1 is listed under previous benchmarks without a retirement date, and no GA date or v3
  is announced. `PA-6` was renamed from "Use privileged access workstations" (v1) to "Use privileged access solution"
  (v2); its text still describes privileged access workstations. `framework_currency.py` alerts when the preview
  marker disappears or a v3 appears.
- **Well-Architected Operational Excellence.** The checklist was renumbered to eleven items on 2026-02-11; the
  catalogue uses the new numbers. The Security, Reliability, Cost and Performance checklists kept their numbering.
- **CIS Ubuntu 24.04.** v2.0.0 replaced v1.0.0 in 2026; Canonical's USG profile still targets v1.0.0 according to its
  documentation. CIS also publishes a separate Ubuntu 24.04 STIG benchmark (v1.0.0), not mapped.
- **MITRE ATLAS** moved from semantic versions to monthly releases (`YYYY.MM`); release 2026.10 keeps `AML.T0051`,
  `AML.T0080` and `AML.T0080.000` with their names.
- **Round 4 (2026-11-26).** Every row re-checked: nothing superseded, no draft became final, no preview became GA
  (MCSB v2 still "currently in preview"; SSDF 1.2 and IR 8596 still drafts; ATLAS 2026.10 still the latest release).
  Corrected: the Red Teaming Guide's date (2025-01-22). Now verified: the NSA and partners' agentic guidance headings
  (five risk categories) and ITSM.00.125. Noted: the AIVSS 1.0 calculator (the document stays v0.8) and the AI
  Omnibus wording of Article 4. Watched, not mapped: NIST SP 2400-102e2026, "Adversarial Machine Learning: A Taxonomy
  and Terminology of Attacks and Mitigations" (initial public draft, comments 2026-11-09 to 2026-12-18; it continues the
  AI 100-2 series with agentic systems), and the OWASP GenAI Data Security Best Practices v2 (three parts,
  2026-11-02 to 2026-11-24). Not fetchable on 2026-11-26: iso.org and media.defense.gov (HTTP 403), cyber.gov.au
  (timeout); those rows keep the 2026-11-25 reading.
- **Checked and unchanged on 2026-11-25:** OWASP LLM Top 10 2026, Agentic Top 10 2026, NHI Top 10 2025, the
  third-party MCP cheat sheet 1.0, NIST AI RMF 1.0, AI 600-1, SSDF 1.1, SP 800-218A, CSF 2.0, IR 8596 (preliminary
  draft), CIS Controls 8.1, CIS Ubuntu 24.04 2.0.0, the three NSA and partner documents, WAF Security, WAF AI, CAF
  Govern AI and Secure AI, the Responsible AI Standard v2. Changed: MCSB (added), CIS Windows 11 (5.1.1), ATLAS
  (2026.10), WAF Operational Excellence (renumbered), the OWASP agentic threats guide (1.1 now read).

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
| OWASP LLM Top 10 2026 official crosswalk from 2025 | Name-based crosswalk above |
| NSA "Careful Adoption of Agentic AI Services" headings on the official site (cyber.gov.au) | Read on the Canadian Centre for Cyber Security's copy of the same guidance (2026-11-26) |
| EU AI Act Article 4 as amended by the AI Omnibus | The Commission's page and law-firm summaries; the Official Journal text was not read |
| ISO/IEC 42001 and 25010 pages, NSA DAISS and AI data security PDFs on 2026-11-26 | HTTP 403; the 2026-11-25 reading stands |
| CIS Ubuntu 24.04 v2.0.0 section numbers | Recommendations cited by name, marked "(id unverified)" |
| CIS Windows 11 Enterprise 5.1.1 release date | Version from the download page; not mapped |
| ISO/IEC 42001 Annex A individual control numbers, and whether a revision is in progress | Group level `A.2` to `A.10` only; iso.org could not be read |
| ISO/IEC 25010:2023 sub-characteristics | Characteristic names only (from the ISO abstract) |
| Microsoft Responsible AI Standard v2 goal identifiers | Principle names only |
| MCSB v2 criticality levels (Must, Should, Nice to have) per control | Not used |
| OWASP MCP Top 10 final titles (beta) | Titles of the 2025 beta, both titles of `MCP06` recorded |
| `CLAUDE_CODE_SESSION_ID` in Claude Code's documentation | Observed in the environment Claude Code gives commands; the Agent-Session trailer says `unknown` without it (ADR 0023) |
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
| `ASI04` | Agentic Supply Chain Vulnerabilities | WS-AI-009, WS-AI-010, WS-AI-031, WS-GOV-002, WS-SEC-015, WS-SEC-016 |
| `ASI05` | Unexpected Code Execution | WS-AI-004, WS-AI-017, WS-AI-027, WS-SEC-001, WS-SEC-005, WS-SEC-022, WS-SEC-027 |
| `ASI06` | Memory and Context Poisoning | WS-AI-001, WS-AI-012, WS-AI-013, WS-AI-014, WS-AI-024 |
| `ASI07` | Insecure Inter-Agent Communication | WS-AI-015, WS-AI-029 |
| `ASI08` | Cascading Failures | WS-AI-015, WS-AI-019, WS-AI-025, WS-AI-028, WS-GOV-015 |
| `ASI09` | Human-Agent Trust Exploitation | WS-AI-005, WS-AI-006, WS-AI-007, WS-AI-018, WS-AI-029 |
| `ASI10` | Rogue Agents | WS-AI-004, WS-AI-014, WS-AI-025, WS-AI-030, WS-GOV-003, WS-SEC-010, WS-SEC-011 |

### `OWASP-NHI`

| ID | Item | Controls |
|---|---|---|
| `NHI1` | Improper Offboarding | WS-GOV-010 |
| `NHI2` | Secret Leakage | WS-AI-022, WS-GOV-003, WS-SEC-002, WS-SEC-004, WS-SEC-007, WS-SEC-008 |
| `NHI3` | Vulnerable Third-Party NHI | WS-AI-009 |
| `NHI4` | Insecure Authentication | WS-AI-007, WS-SEC-012 |
| `NHI5` | Overprivileged NHI | WS-AI-003, WS-AI-026 |
| `NHI7` | Long-Lived Secrets | WS-GOV-010, WS-SEC-007 |
| `NHI8` | Environment Isolation | WS-AI-026, WS-SEC-006 |
| `NHI9` | NHI Reuse | WS-AI-015, WS-AI-026, WS-SEC-025 |
| `NHI10` | Human Use of NHI | WS-AI-026 |

### `OWASP-MCP3P`

| ID | Item | Controls |
|---|---|---|
| `authorization` | Authorization | WS-AI-005, WS-AI-011, WS-AI-012 |
| `client-sandboxing` | Client sandboxing | WS-AI-001, WS-AI-011 |
| `governance-workflows` | Governance workflows | WS-AI-010, WS-GOV-002 |
| `secure-server-discovery` | Secure server discovery | WS-AI-009, WS-AI-010, WS-AI-031 |

### `OWASP-AITM`

| ID | Item | Controls |
|---|---|---|
| `T1` | Memory Poisoning | WS-AI-012, WS-AI-013 |
| `T2` | Tool Misuse | WS-AI-005, WS-AI-011, WS-SEC-005 |
| `T3` | Privilege Compromise | WS-AI-003, WS-AI-026, WS-SEC-002 |
| `T4` | Resource Overload | WS-AI-019 |
| `T5` | Cascading Hallucination Attacks | WS-AI-021 |
| `T6` | Intent Breaking & Goal Manipulation | WS-AI-001 |
| `T7` | Misaligned & Deceptive Behaviors | WS-AI-030 |
| `T8` | Repudiation & Untraceability | WS-AI-026, WS-SEC-010, WS-SEC-011 |
| `T9` | Identity Spoofing & Impersonation / Agent Identity Compromise | WS-AI-007, WS-AI-026 |
| `T10` | Overwhelming Human in the Loop | WS-AI-006 |
| `T11` | Unexpected RCE and Code Attacks | WS-AI-017, WS-SEC-001 |
| `T12` | Agent Communication Poisoning | WS-AI-029 |
| `T13` | Rogue Agents in Multi-Agent Systems | WS-AI-015, WS-AI-025 |
| `T14` | Human Attacks on Multi-Agent Systems | WS-AI-015 |
| `T15` | Human Manipulation | WS-GOV-012 |
| `T16` | Insecure Inter-Agent Protocol Abuse | WS-AI-011, WS-AI-029 |
| `T17` | Supply Chain Compromise | WS-AI-009, WS-SEC-016 |

### `OWASP-MCP10`

| ID | Item | Controls |
|---|---|---|
| `MCP01` | Token Mismanagement & Secret Exposure | WS-AI-011, WS-SEC-002 |
| `MCP02` | Privilege Escalation via Scope Creep | WS-AI-011 |
| `MCP03` | Tool Poisoning | WS-AI-001, WS-AI-031 |
| `MCP04` | Software Supply Chain Attacks & Dependency Tampering | WS-AI-009 |
| `MCP05` | Command Injection & Execution | WS-AI-011 |
| `MCP06` | Prompt Injection via Contextual Payloads (repository title: Intent Flow Subversion) | WS-AI-001 |
| `MCP07` | Insufficient Authentication & Authorization | WS-AI-005 |
| `MCP08` | Lack of Audit and Telemetry | WS-SEC-010 |
| `MCP09` | Shadow MCP Servers | WS-AI-010 |
| `MCP10` | Context Injection & Over-Sharing | WS-AI-022 |

### `OWASP-RTM`

| ID | Item | Controls |
|---|---|---|
| `4.3.3` | Indirect Prompt Injection | WS-AI-001, WS-AI-027 |
| `4.5.1` | Model Context Protocol (MCP) Servers | WS-AI-011, WS-AI-031 |
| `4.5.2` | Agent Skills | WS-AI-014 |
| `4.5.4` | Agent Memory | WS-AI-012 |
| `5.2.1` | Tools and API Escalations | WS-AI-014, WS-AI-027 |
| `5.2.2` | Autonomous-agent task-chain escalation | WS-AI-004, WS-AI-007 |

### `OWASP-SAA`

| ID | Item | Controls |
|---|---|---|
| `KC4` | Memory Modules | WS-AI-012 |
| `KC5` | Tool Integration Frameworks | WS-AI-011 |
| `KC6.2` | Code Execution | WS-SEC-001 |
| `KC6.5` | Controlling PC Operations (Filesystem, OS Commands) | WS-SEC-001, WS-SEC-022 |

### `NIST-AI-RMF`

| ID | Item | Controls |
|---|---|---|
| `GOVERN-1.1` | Legal and regulatory requirements understood, managed and documented | WS-GOV-001 |
| `MAP-1.1` | Intended purpose and context documented | WS-GOV-001, WS-GOV-011 |
| `MEASURE-1.1` | Metrics for significant risks | WS-GOV-005 |
| `MANAGE-1.1` | Decide whether to proceed | WS-GOV-011 |
| `GOVERN-1.2` | Trustworthy AI characteristics integrated into policies | WS-GOV-001 |
| `MANAGE-1.2` | Risk treatment prioritized | WS-GOV-004 |
| `MEASURE-1.2` | Metrics and controls reassessed | WS-GOV-005 |
| `MANAGE-1.3` | Responses to high-priority risks planned | WS-AI-002 |
| `GOVERN-1.3` | Risk management effort set by risk tolerance | WS-GOV-001 |
| `GOVERN-1.4` | Risk management process and outcomes established through transparent policies | WS-GOV-001 |
| `MANAGE-1.4` | Residual risks documented | WS-GOV-004, WS-GOV-006, WS-GOV-011 |
| `MAP-1.5` | Risk tolerances documented | WS-GOV-001 |
| `GOVERN-1.5` | Ongoing monitoring and periodic review planned | WS-GOV-004, WS-GOV-005 |
| `GOVERN-1.6` | Mechanisms to inventory AI systems | WS-GOV-002 |
| `GOVERN-1.7` | Processes to decommission AI systems safely | WS-GOV-010 |
| `MAP-2.1` | Task and methods defined | WS-AI-020 |
| `MEASURE-2.1` | Test sets and tools documented | WS-AI-027 |
| `GOVERN-2.1` | Roles, responsibilities and lines of communication documented | WS-GOV-009 |
| `MANAGE-2.2` | Mechanisms sustain value of deployed systems | WS-AI-019 |
| `GOVERN-2.2` | AI risk management training | WS-GOV-012 |
| `MAP-2.2` | Knowledge limits and human oversight documented | WS-GOV-012 |
| `MANAGE-2.3` | Respond to and recover from unknown risks | WS-AI-025, WS-GOV-003 |
| `MANAGE-2.4` | Mechanisms to supersede, disengage or deactivate AI systems | WS-AI-004, WS-AI-025 |
| `MEASURE-2.4` | Functionality and behavior monitored in production | WS-AI-019, WS-AI-030 |
| `MEASURE-2.5` | Validity and reliability | WS-AI-021 |
| `MEASURE-2.6` | Safety evaluated; fails safely | WS-AI-028 |
| `MEASURE-2.7` | Security and resilience evaluated | WS-AI-001, WS-AI-012, WS-AI-027 |
| `MEASURE-2.8` | Transparency and accountability risks examined | WS-AI-006, WS-AI-029, WS-SEC-010 |
| `MEASURE-2.10` | Privacy risks examined | WS-AI-022, WS-AI-023 |
| `MEASURE-3.1` | Emergent risks tracked after deployment | WS-AI-006, WS-AI-013 |
| `MANAGE-3.1` | Third-party risks monitored | WS-AI-009, WS-GOV-008 |
| `MAP-3.1` | Benefits documented | WS-GOV-011 |
| `GOVERN-3.2` | Roles for human-AI configurations and oversight | WS-AI-005 |
| `MANAGE-3.2` | Pre-trained models monitored | WS-GOV-002 |
| `MAP-3.2` | Costs of AI errors documented | WS-GOV-011 |
| `MAP-3.3` | Application scope documented | WS-GOV-001 |
| `MEASURE-3.3` | User feedback and appeal channels | WS-GOV-007 |
| `MAP-3.5` | Human oversight processes defined | WS-AI-004, WS-AI-005, WS-AI-015 |
| `MANAGE-4.1` | Post-deployment monitoring plans | WS-AI-013, WS-AI-030 |
| `MAP-4.1` | Legal and technology risks of third-party components mapped | WS-GOV-002 |
| `MAP-4.2` | Internal risk controls for third-party AI components | WS-AI-009 |
| `MANAGE-4.2` | Continuous improvement | WS-GOV-005 |
| `GOVERN-4.2` | Risks and impacts documented and communicated | WS-GOV-006 |
| `GOVERN-4.3` | Practices for testing, incident identification and information sharing | WS-AI-027, WS-GOV-003 |
| `MANAGE-4.3` | Incidents and errors communicated and tracked | WS-GOV-003 |
| `MAP-5.1` | Likelihood and magnitude of impacts documented | WS-GOV-004 |
| `GOVERN-6.1` | Policies for third-party AI risks | WS-AI-009, WS-AI-010, WS-GOV-008 |
| `GOVERN-6.2` | Contingency for third-party failures | WS-GOV-003 |

### `NIST-600-1`

| ID | Item | Controls |
|---|---|---|
| `Confabulation` | Confabulation | WS-AI-021 |
| `Data Privacy` | Data Privacy | WS-AI-022, WS-AI-023, WS-GOV-001, WS-GOV-008, WS-SEC-009 |
| `Human-AI Configuration` | Human-AI Configuration | WS-AI-004, WS-AI-005, WS-AI-006, WS-AI-007, WS-AI-020, WS-GOV-012 |
| `Information Integrity` | Information Integrity | WS-AI-012, WS-AI-013, WS-AI-014, WS-AI-024 |
| `Information Security` | Information Security | WS-AI-001, WS-AI-002, WS-AI-011, WS-AI-012, WS-AI-017, WS-AI-022 |
| `Intellectual Property` | Intellectual Property | WS-AI-024, WS-GOV-001 |
| `Value Chain and Component Integration` | Value Chain and Component Integration | WS-AI-009, WS-GOV-002, WS-GOV-008, WS-SEC-015, WS-SEC-016, WS-SEC-018 |

### `SSDF`

| ID | Item | Controls |
|---|---|---|
| `PS.1` | Protect all forms of code from unauthorized access and tampering | WS-AI-014, WS-GOV-009, WS-SEC-005 |
| `RV.1` | Identify and confirm vulnerabilities on an ongoing basis | WS-GOV-007, WS-SEC-017 |
| `PO.1` | Define security requirements for software development | WS-GOV-001 |
| `PW.1` | Design software to meet security requirements and mitigate security risks | WS-GOV-004 |
| `PS.2` | Provide a mechanism for verifying software release integrity | WS-SEC-015 |
| `PW.2` | Review the software design | WS-GOV-004 |
| `RV.2` | Assess, prioritize and remediate vulnerabilities | WS-GOV-007 |
| `PO.2` | Implement roles and responsibilities | WS-GOV-009 |
| `PO.3` | Implement supporting toolchains | WS-SEC-004, WS-SEC-016, WS-SEC-017 |
| `PS.3` | Archive and protect each software release | WS-SEC-015, WS-SEC-018 |
| `RV.3` | Analyze vulnerabilities to identify root causes | WS-GOV-003 |
| `PW.4` | Reuse existing, well-secured software | WS-AI-009, WS-SEC-016, WS-SEC-018 |
| `PO.4` | Define and use criteria for software security checks | WS-GOV-005, WS-SEC-004, WS-SEC-017 |
| `PW.5` | Create source code by adhering to secure coding practices | WS-AI-017, WS-SEC-027, WS-SEC-028 |
| `PO.5` | Implement and maintain secure environments for software development | WS-SEC-001, WS-SEC-026 |
| `PW.7` | Review and/or analyze human-readable code | WS-AI-021, WS-SEC-004, WS-SEC-008, WS-SEC-017 |
| `PW.8` | Test executable code | WS-AI-021, WS-AI-027, WS-SEC-017 |
| `PW.9` | Configure software to have secure settings by default | WS-AI-002, WS-AI-003, WS-AI-008 |

### `SSDF-1.2-IPD`

| ID | Item | Controls |
|---|---|---|
| `PO.6` | Continuous Process Improvement (draft) | WS-GOV-005 |
| `PW.10` | Robust and Reliable Updates (draft) | WS-SEC-015 |

### `SSDF-218A`

| ID | Item | Controls |
|---|---|---|
| `PW.4` | Reuse well-secured software (AI considerations) | WS-AI-009 |
| `PW.8` | Test executable code (AI considerations) | WS-AI-027 |

### `CSF`

| ID | Item | Controls |
|---|---|---|
| `PR.PS-01` | Configuration management | WS-AI-002, WS-AI-014, WS-AI-028, WS-SEC-001, WS-SEC-026, WS-SEC-027 |
| `PR.AA-01` | Identity and credential management | WS-AI-007, WS-AI-026, WS-GOV-010, WS-SEC-002, WS-SEC-007, WS-SEC-025 |
| `PR.IR-01` | Networks protected from unauthorized logical access | WS-AI-011, WS-SEC-001, WS-SEC-003, WS-SEC-012, WS-SEC-021, WS-SEC-022 |
| `PR.DS-01` | Data-at-rest protection | WS-AI-023, WS-SEC-002, WS-SEC-007, WS-SEC-008, WS-SEC-012, WS-SEC-013, WS-SEC-020 |
| `RS.MA-01` | Incident response plan executed | WS-AI-025, WS-GOV-003 |
| `DE.CM-01` | Network and network service monitoring | WS-AI-030, WS-SEC-003, WS-SEC-021 |
| `RC.RP-01` | Recovery portion of the plan executed | WS-GOV-003, WS-SEC-014 |
| `ID.RA-01` | Asset vulnerability identification | WS-SEC-019, WS-SEC-026 |
| `GV.PO-01` | Policy for managing cybersecurity risks established | WS-GOV-001, WS-GOV-006 |
| `GV.OV-01` | Risk strategy outcomes reviewed | WS-GOV-005 |
| `ID.IM-01` | Improvements identified from evaluations | WS-GOV-005 |
| `PR.DS-02` | Data-in-transit protection | WS-AI-022, WS-SEC-009 |
| `DE.AE-02` | Adverse events analyzed | WS-AI-030 |
| `PR.PS-02` | Software maintenance, replacement and removal | WS-SEC-015, WS-SEC-019 |
| `ID.AM-02` | Software, services and systems inventory | WS-GOV-002, WS-SEC-018 |
| `GV.RR-02` | Roles, responsibilities and authorities established | WS-GOV-009, WS-GOV-012 |
| `DE.CM-03` | Personnel activity and technology usage monitoring | WS-AI-006, WS-SEC-010 |
| `DE.AE-03` | Information correlated across sources | WS-AI-030 |
| `ID.RA-03` | Threat identification | WS-GOV-004 |
| `PR.PS-04` | Log generation and availability | WS-SEC-010, WS-SEC-011, WS-SEC-023, WS-SEC-029 |
| `ID.AM-04` | Supplier services inventory | WS-GOV-002 |
| `PR.AA-05` | Access permissions and authorization | WS-AI-002, WS-AI-003, WS-AI-004, WS-AI-005, WS-AI-007, WS-AI-008, WS-AI-011, WS-AI-015, WS-AI-016, WS-AI-018, WS-AI-026, WS-SEC-006, WS-SEC-020, WS-SEC-022 |
| `PR.PS-05` | Unauthorized software prevention | WS-AI-010, WS-SEC-005 |
| `ID.RA-05` | Inherent risk and response prioritization | WS-GOV-004 |
| `GV.SC-05` | Supply chain requirements | WS-GOV-008 |
| `PR.PS-06` | Secure software development | WS-AI-021, WS-SEC-004, WS-SEC-017 |
| `DE.CM-06` | External service provider monitoring | WS-GOV-008 |
| `GV.SC-07` | Ongoing supplier risk monitoring | WS-AI-009, WS-GOV-008, WS-SEC-016 |
| `ID.AM-07` | Data inventory and metadata | WS-AI-013, WS-GOV-002 |
| `ID.RA-07` | Change and exception management | WS-GOV-009 |
| `GV.SC-08` | Suppliers included in incident response | WS-GOV-003 |
| `ID.RA-08` | Vulnerability disclosure handling | WS-GOV-007 |
| `ID.AM-08` | Life cycle management | WS-GOV-010 |
| `DE.CM-09` | Computing hardware, software and runtime monitoring | WS-AI-001, WS-AI-019, WS-AI-030, WS-SEC-024 |
| `ID.RA-09` | Hardware and software integrity checks | WS-AI-009, WS-SEC-015, WS-SEC-016 |
| `PR.DS-10` | Data-in-use protection | WS-AI-012, WS-AI-014, WS-AI-022 |
| `PR.DS-11` | Data backups | WS-SEC-013, WS-SEC-014 |

### `CIS-v8`

| ID | Item | Controls |
|---|---|---|
| `1.1` | Establish and Maintain Detailed Enterprise Asset Inventory | WS-GOV-002 |
| `2.1` | Establish and Maintain a Software Inventory | WS-GOV-002, WS-SEC-018 |
| `2.2` | Ensure Authorized Software is Currently Supported | WS-AI-009, WS-SEC-016 |
| `2.3` | Address Unauthorized Software | WS-AI-010 |
| `2.5` | Allowlist Authorized Software | WS-AI-010 |
| `2.7` | Allowlist Authorized Scripts | WS-AI-008, WS-AI-018, WS-SEC-005, WS-SEC-022 |
| `3.3` | Configure Data Access Control Lists | WS-SEC-002, WS-SEC-012, WS-SEC-020, WS-SEC-022 |
| `3.4` | Enforce Data Retention | WS-AI-023, WS-SEC-013 |
| `3.5` | Securely Dispose of Data | WS-AI-023, WS-GOV-010 |
| `3.11` | Encrypt Sensitive Data at Rest | WS-AI-023, WS-SEC-007 |
| `3.13` | Deploy a Data Loss Prevention Solution | WS-AI-022, WS-SEC-009 |
| `4.1` | Establish and Maintain a Secure Configuration Process | WS-AI-002, WS-AI-014, WS-GOV-005, WS-SEC-001, WS-SEC-026 |
| `4.5` | Implement and Manage a Firewall on End-User Devices | WS-SEC-003, WS-SEC-021 |
| `4.8` | Uninstall or Disable Unnecessary Services | WS-SEC-021 |
| `5.1` | Establish and Maintain an Inventory of Accounts | WS-AI-026 |
| `5.4` | Restrict Administrator Privileges to Dedicated Administrator Accounts | WS-AI-026, WS-SEC-025 |
| `6.1` | Establish an Access Granting Process | WS-AI-026 |
| `6.2` | Establish an Access Revoking Process | WS-GOV-010 |
| `6.8` | Define and Maintain Role-Based Access Control | WS-AI-003, WS-AI-026, WS-SEC-006 |
| `7.1` | Establish and Maintain a Vulnerability Management Process | WS-SEC-019 |
| `7.2` | Establish and Maintain a Remediation Process | WS-GOV-007 |
| `7.3` | Perform Automated Operating System Patch Management | WS-SEC-019 |
| `7.4` | Perform Automated Application Patch Management | WS-SEC-019 |
| `8.1` | Establish and Maintain an Audit Log Management Process | WS-SEC-011 |
| `8.2` | Collect Audit Logs | WS-SEC-010, WS-SEC-023 |
| `8.3` | Ensure Adequate Audit Log Storage | WS-SEC-011 |
| `8.5` | Collect Detailed Audit Logs | WS-SEC-010 |
| `8.7` | Collect URL Request Audit Logs | WS-SEC-010 |
| `8.8` | Collect Command-Line Audit Logs | WS-SEC-010 |
| `8.9` | Centralize Audit Logs | WS-SEC-011 |
| `8.10` | Retain Audit Logs | WS-SEC-011 |
| `8.11` | Conduct Audit Log Reviews | WS-AI-030 |
| `11.1` | Establish and Maintain a Data Recovery Process | WS-GOV-013, WS-SEC-014 |
| `11.2` | Perform Automated Backups | WS-SEC-013 |
| `11.3` | Protect Recovery Data | WS-SEC-013 |
| `11.4` | Establish and Maintain an Isolated Instance of Recovery Data | WS-SEC-013 |
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
| `17.2` | Establish and Maintain Contact Information for Reporting Security Incidents | WS-GOV-007 |
| `17.3` | Establish and Maintain an Enterprise Process for Reporting Incidents | WS-GOV-003 |
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
| `privilege risks` | Privilege risks (heading verified 2026-11-26; the guidance numbers no categories) | WS-AI-002, WS-AI-004, WS-AI-026 |
| `structural risks` | Structural risks (heading verified 2026-11-26) | WS-AI-015 |
| `accountability risks` | Accountability risks (heading verified 2026-11-26) | WS-AI-005, WS-AI-006, WS-AI-026, WS-SEC-010, WS-SEC-011 |

### `WAF-SEC`

| ID | Item | Controls |
|---|---|---|
| `SE:01` | Establish a security baseline | WS-AI-002, WS-GOV-005, WS-SEC-026 |
| `SE:02` | Align secure development lifecycle | WS-AI-009, WS-AI-021, WS-GOV-009, WS-SEC-004, WS-SEC-015, WS-SEC-016, WS-SEC-017, WS-SEC-018 |
| `SE:03` | Classify and apply sensitivity labels | WS-AI-022, WS-GOV-002, WS-SEC-009 |
| `SE:04` | Create intentional segmentation and perimeters | WS-AI-003, WS-AI-015, WS-SEC-001, WS-SEC-006, WS-SEC-022 |
| `SE:05` | Strict, conditional and auditable IAM | WS-AI-003, WS-AI-007, WS-AI-008, WS-AI-016, WS-AI-026, WS-SEC-025 |
| `SE:06` | Isolate, filter and control network traffic | WS-AI-011, WS-SEC-003, WS-SEC-012, WS-SEC-021 |
| `SE:07` | Encrypt data | WS-AI-023, WS-SEC-013 |
| `SE:08` | Harden all workload components | WS-AI-002, WS-AI-010, WS-AI-014, WS-AI-028, WS-SEC-001, WS-SEC-005, WS-SEC-019, WS-SEC-020, WS-SEC-027, WS-SEC-028 |
| `SE:09` | Protect application secrets | WS-GOV-010, WS-SEC-002, WS-SEC-004, WS-SEC-007, WS-SEC-008 |
| `SE:10` | Holistic monitoring strategy | WS-AI-030, WS-SEC-010, WS-SEC-011, WS-SEC-023 |
| `SE:11` | Comprehensive testing regimen | WS-AI-027, WS-GOV-004, WS-SEC-017 |
| `SE:12` | Define and test incident response procedures | WS-AI-025, WS-GOV-003, WS-SEC-014 |

### `WAF-AI`

| ID | Item | Controls |
|---|---|---|
| `application-design` | Application design | WS-AI-001, WS-AI-017 |
| `grounding-data-design` | Grounding data design | WS-AI-012, WS-AI-024 |
| `operations` | Workload operations | WS-AI-006, WS-AI-019 |
| `responsible-ai` | Responsible AI | WS-GOV-001 |

### `MCSB`

| ID | Item | Controls |
|---|---|---|
| `NS-8` | Detect and disable insecure services and protocols | WS-SEC-021 |
| `IM-3` | Manage application identities securely and automatically | WS-AI-026 |
| `IM-6` | Use strong authentication controls | WS-AI-007 |
| `IM-8` | Restrict the exposure of credentials and secrets | WS-AI-011, WS-AI-022, WS-SEC-002, WS-SEC-007, WS-SEC-008 |
| `PA-1` | Separate and limit highly privileged/administrative users | WS-AI-026, WS-SEC-025 |
| `PA-2` | Avoid standing access for user accounts and permissions | WS-AI-026 |
| `PA-3` | Manage lifecycle of identities and entitlements | WS-GOV-010 |
| `PA-4` | Review and reconcile user access regularly | WS-GOV-010 |
| `PA-6` | Use privileged access solution (v1: Use privileged access workstations) | WS-SEC-001, WS-SEC-025, WS-SEC-026 |
| `PA-7` | Follow just enough administration (least privilege) principle | WS-AI-003, WS-AI-008, WS-AI-016, WS-AI-026 |
| `DP-4` | Enable data at rest encryption by default | WS-SEC-013 |
| `DP-6` | Use a secure key management process | WS-GOV-010, WS-SEC-007 |
| `DP-8` | Ensure security of key and certificate repository | WS-SEC-007 |
| `AM-1` | Track asset inventory and their risks | WS-GOV-002, WS-SEC-018 |
| `AM-2` | Use only approved services | WS-AI-010, WS-GOV-008 |
| `AM-5` | Use only approved applications in virtual machine | WS-AI-010, WS-SEC-016 |
| `LT-1` | Enable threat detection capabilities | WS-AI-030 |
| `LT-3` | Enable logging for security investigation | WS-SEC-010 |
| `LT-5` | Centralize security log management and analysis | WS-SEC-011 |
| `LT-6` | Configure log storage retention | WS-SEC-011 |
| `LT-7` | Use approved time synchronization sources | WS-SEC-029 |
| `IR-1` | Preparation - update incident response plan and handling process | WS-GOV-003 |
| `IR-2` | Preparation - setup incident notification | WS-AI-030 |
| `IR-6` | Containment, eradication and recovery - automate the incident handling | WS-AI-025 |
| `IR-7` | Post-incident activity - conduct lessons learned and retain evidence | WS-GOV-003 |
| `PV-1` | Define and establish secure configurations | WS-AI-002, WS-SEC-026 |
| `PV-2` | Audit and enforce secure configurations | WS-GOV-005, WS-SEC-026 |
| `PV-5` | Perform vulnerability assessments | WS-SEC-017, WS-SEC-019 |
| `PV-6` | Rapidly and automatically remediate vulnerabilities | WS-SEC-019 |
| `PV-7` | Conduct regular red team operations | WS-AI-027 |
| `ES-1` | Use Endpoint Detection and Response (EDR) | WS-SEC-024 |
| `ES-2` | Use modern anti-malware software | WS-SEC-024 |
| `ES-3` | Ensure anti-malware software and signatures are updated | WS-SEC-024 |
| `BR-1` | Ensure regular automated backups | WS-SEC-013 |
| `BR-2` | Protect backup and recovery data | WS-SEC-013 |
| `BR-3` | Monitor backups | WS-SEC-013 |
| `BR-4` | Regularly test backup | WS-SEC-014 |
| `DS-1` | Conduct threat modeling | WS-GOV-004 |
| `DS-2` | Secure the software supply chain | WS-AI-009, WS-SEC-016, WS-SEC-018 |
| `DS-3` | Secure the DevOps infrastructure | WS-SEC-017 |
| `DS-4` | Integrate Static Application Security Testing (SAST) | WS-SEC-004, WS-SEC-017 |
| `DS-6` | Secure the workload lifecycle | WS-SEC-015 |
| `AI-1` | Ensure use of approved models | WS-AI-020, WS-GOV-002 |
| `AI-2` | Implement multi-layered content filtering | WS-AI-001, WS-AI-022 |
| `AI-3` | Adopt safety meta-prompts | WS-AI-014 |
| `AI-4` | Apply least privilege for agent functions | WS-AI-003, WS-AI-011, WS-AI-016 |
| `AI-5` | Ensure human-in-the-loop | WS-AI-004, WS-AI-005 |
| `AI-6` | Establish monitoring and detection | WS-AI-006, WS-AI-030 |
| `AI-7` | Perform continuous AI Red Teaming | WS-AI-027 |

### `WAF-REL`

| ID | Item | Controls |
|---|---|---|
| `RE:04` | Define reliability and recovery targets | WS-GOV-013 |
| `RE:07` | Strengthen the resiliency of your workload by implementing self-preservation and self-healing measures | WS-AI-028, WS-GOV-015 |
| `RE:09` | Implement structured, tested, and documented disaster recovery (DR) plans | WS-GOV-003, WS-GOV-013, WS-SEC-014 |
| `RE:10` | Continuously measure and track system health using uptime and reliability indicators | WS-GOV-015, WS-SEC-026 |

### `WAF-CO`

| ID | Item | Controls |
|---|---|---|
| `CO:03` | Collect and review cost data | WS-AI-019 |
| `CO:04` | Set spending guardrails | WS-AI-019 |

### `WAF-OE`

| ID | Item | Controls |
|---|---|---|
| `OE:04` | Enhance software development and quality assurance | WS-SEC-017 |
| `OE:05` | Use a standardized infrastructure as code (IaC) approach to prepare resources and configurations | WS-GOV-009 |
| `OE:06` | Build a workload supply chain that drives changes | WS-SEC-015 |
| `OE:08` | Establish a clear, structured incident management process | WS-GOV-003 |
| `OE:09` | Enhance the quality of your workload (testing) | WS-AI-027 |
| `OE:11` | Clearly define your workload's safe deployment practices | WS-SEC-015 |

### `WAF-PE`

| ID | Item | Controls |
|---|---|---|
| `PE:01` | Define performance targets | WS-GOV-014 |
| `PE:04` | Establish consistent performance measurement | WS-GOV-014 |
| `PE:12` | Continuously optimize performance | WS-GOV-014 |

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
| `govern.monitor-compliance` | Govern: 5. Monitor cloud compliance | WS-GOV-005 |
| `manage.monitor` | Manage: 3. Monitor your Azure cloud estate | WS-AI-030 |
| `manage.protect` | Manage: 4. Protect your Azure cloud estate | WS-SEC-013 |

### `MS-RAI`

| ID | Item | Controls |
|---|---|---|
| `Reliability and Safety` | Reliability and Safety | WS-AI-002, WS-AI-021, WS-AI-028, WS-GOV-004, WS-GOV-015 |
| `Privacy and Security` | Privacy and Security | WS-AI-022, WS-AI-023, WS-GOV-001 |
| `Transparency` | Transparency | WS-GOV-006, WS-GOV-011, WS-GOV-012, WS-SEC-010 |
| `Accountability` | Accountability | WS-AI-004, WS-AI-005, WS-AI-020, WS-AI-025, WS-GOV-001 |

### `ISO42001`

| ID | Item | Controls |
|---|---|---|
| `A.2` | Policies related to AI | WS-GOV-001 |
| `A.3` | Internal organization | WS-AI-026, WS-GOV-009 |
| `A.4` | Resources for AI systems | WS-GOV-002 |
| `4` | Context of the organization | WS-GOV-011 |
| `5` | Leadership | WS-GOV-001 |
| `A.5` | Assessing impacts of AI systems | WS-GOV-004, WS-GOV-011 |
| `A.6` | AI system life cycle | WS-AI-021, WS-AI-025, WS-GOV-006, WS-GOV-010, WS-SEC-010, WS-SEC-011, WS-SEC-015 |
| `6` | Planning | WS-GOV-004 |
| `A.7` | Data for AI systems | WS-AI-012, WS-AI-013, WS-AI-023, WS-AI-024 |
| `7` | Support | WS-GOV-006, WS-GOV-012 |
| `A.8` | Information for interested parties of AI systems | WS-GOV-003, WS-GOV-007, WS-GOV-012 |
| `8` | Operation | WS-GOV-004, WS-GOV-011 |
| `A.9` | Use of AI systems | WS-AI-002, WS-AI-004, WS-AI-005, WS-AI-006, WS-AI-007, WS-AI-015, WS-AI-018, WS-AI-020, WS-GOV-001 |
| `9` | Performance evaluation | WS-GOV-005 |
| `A.10` | Third-party and customer relationships | WS-AI-009, WS-AI-010, WS-GOV-008, WS-SEC-025 |
| `10` | Improvement | WS-GOV-003, WS-GOV-005 |

### `ISO25010`

| ID | Item | Controls |
|---|---|---|
| `Compatibility` | Compatibility | WS-SEC-025 |
| `Flexibility` | Flexibility | WS-GOV-009 |
| `Functional suitability` | Functional suitability | WS-AI-021, WS-SEC-017 |
| `Interaction capability` | Interaction capability | WS-AI-005, WS-GOV-012 |
| `Maintainability` | Maintainability | WS-GOV-009, WS-SEC-017 |
| `Performance efficiency` | Performance efficiency | WS-GOV-014 |
| `Reliability` | Reliability | WS-AI-028, WS-GOV-013, WS-GOV-015, WS-SEC-014 |
| `Safety` | Safety | WS-AI-002, WS-AI-028 |
| `Security` | Security | WS-SEC-001, WS-SEC-002, WS-SEC-011 |

### `ATLAS`

| ID | Item | Controls |
|---|---|---|
| `AML.T0034.002` | Cost Harvesting: Agentic Resource Consumption | WS-AI-019 |
| `AML.T0051` | LLM Prompt Injection | WS-AI-001 |
| `AML.T0053` | AI Agent Tool Invocation | WS-AI-005, WS-AI-011 |
| `AML.T0080` | AI Agent Context Poisoning | WS-AI-012 |
| `AML.T0080.000` | Memory | WS-AI-012 |
| `AML.T0081` | Modify AI Agent Configuration | WS-AI-014 |
| `AML.T0083` | Credentials from AI Agent Configuration | WS-AI-011, WS-SEC-002 |
| `AML.T0086` | Exfiltration via AI Agent Tool Invocation | WS-SEC-003 |
| `AML.T0110` | AI Agent Tool Poisoning | WS-AI-009, WS-AI-031 |
