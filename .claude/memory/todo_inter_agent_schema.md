---
name: TODO — formal JSON schema for inter-agent communication
description: Planned work to replace informal signal/text conventions with a typed JSON schema for all inter-agent messages
type: project
---

Define a formal JSON schema for all inter-agent communication in the agent team.

**Why:** Current protocol relies on freetext signals (RFR, LGTM, REVISE, VERDICT: PASS, etc.) and unstructured prose output. A typed schema would make messages machine-readable, easier to validate, and more reliable for orchestrator parsing — especially as parallelism increases and the orchestrator is managing multiple concurrent agent outputs.

**How to apply:** Design the schema before any further changes to the orchestrate skill or agent protocols. All agent output formats (reviewer verdict, auditor verdict, worker RFR, architect triage response, etc.) should conform to it. Consider whether the schema lives as a skill, a standalone JSON Schema file, or embedded in agent frontmatter.
