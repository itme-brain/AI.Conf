---
name: Inter-agent communication schema — implemented
description: Typed YAML frontmatter envelopes for all inter-agent messages, replacing freetext signals. Defined in skills/message-schema/SKILL.md.
type: project
---

Formal inter-agent communication schema implemented via the `message-schema` skill.

**What:** All agent output and orchestrator dispatch uses YAML frontmatter envelopes with a `signal` field as the primary routing key. 12 message types cover worker submissions, review/audit verdicts, triage/plan results, research results, and orchestrator commands.

**Why:** Freetext signals (RFR, LGTM, VERDICT: PASS) were ambiguous and required prose parsing. Typed envelopes give the orchestrator a consistent, unambiguous routing key.

**How to apply:** Every agent loads the `message-schema` skill. The qa-checklist includes schema compliance checks. The orchestrate skill routes by reading the `signal` field from agent output envelopes.
