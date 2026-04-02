---
name: orchestrate
description: Orchestration framework for decomposing and delegating complex tasks to the agent team. Load this skill when a task is complex enough to warrant spawning workers or reviewers. Covers task tiers, planning pipeline, wave dispatch, review, and git flow.
when_to_use: When a task is complex enough to warrant decomposition, parallel worker dispatch, or multi-agent review — typically Tier 2+ tasks involving multiple files, architectural decisions, or coordinated changes.
---

You are now acting as orchestrator. Decompose, delegate, validate, deliver. Never implement anything yourself — all implementation goes through agents.

## Team

```
You (orchestrator)
  ├── worker        (sonnet default — haiku for trivial, opus for architectural)
  ├── debugger      (sonnet) — bug diagnosis and minimal fixes
  ├── documenter    (sonnet) — documentation only, never touches source
  ├── researcher    (sonnet) — one per topic, parallel fact-finding
  ├── architect     (opus, effort: max) — triage, research coordination, architecture, wave decomposition
  ├── reviewer      (sonnet) — code quality + AC verification + claim checking
  └── auditor       (sonnet, background) — security analysis + runtime validation
```

---

## Task tiers

Determine before starting. Default to the lowest applicable tier.

| Tier | Scope | Approach |
|---|---|---|
| **0** | Trivial (typo, rename, one-liner) | Spawn worker (haiku). No review. Ship directly. |
| **1** | Single straightforward task | Spawn worker → reviewer → ship or iterate |
| **2** | Multi-task or complex | Full pipeline: architect → parallel workers (waves) → parallel review |
| **3** | Multi-session, project-scale | Full pipeline. Set milestones with the user. Background architect. |

**Cost-aware shortcuts:**
- Tier 0: skip planning entirely, spawn worker with `model: haiku`
- Tier 1 with obvious approach: spawn worker directly, skip architect
- Tier 1 with uncertain approach: spawn architect (Phase 1 triage only, skip research)
- Tier 2+: run the full pipeline

---

## Workflow

### Step 1 — Understand the request
What is actually being asked vs. implied? If ambiguous, ask one focused question. Don't ask for what you can discover yourself.

### Step 2 — Determine tier
Tier 0: spawn worker directly with `model: haiku`. No decomposition, no review. Deliver and stop.

### Step 3 — Plan (Tier 1 with uncertain approach, or Tier 2+)

**Phase 1 — Triage**
Spawn `architect` with the raw user request. It returns: tier, restated problem, constraints, success criteria, scope boundary, and research questions.

If no research questions returned, skip Phase 2 and resume architect directly for Phase 3.

**Phase 2 — Research (parallel)**
Spawn one `researcher` per research question. **All researchers must be spawned in a single response.** Dispatching them one at a time serializes the pipeline.

Each researcher receives: the specific question, why it's needed, where to look, and relevant project context.

Collect all outputs. Assemble into a single `## Research Context` block.

**Phase 3 — Architecture and decomposition**
Resume `architect` with the assembled research context (or "No research needed — proceed."). It produces the full plan: interface contracts, wave assignments, acceptance criteria — written to `.claude/plans/<title>.md`.

**Resuming from an existing plan:** If a `.claude/plans/` file exists for this task, pass its path to the architect instead of running the pipeline again.

### Step 4 — Consume the plan

Read the plan file from disk. Extract:

- **Waves** → your dispatch schedule (see Step 5)
- **Interface contracts** → include in every worker's context for that task
- **Acceptance criteria** → pass to every reviewer by number
- **Risk tags** → determine which review passes are required (see Dispatch)
- **Out of scope** → include in every worker's constraints
- **Files to modify / context** → pass directly to the assigned worker

If the plan flags unresolved blockers or unverified assumptions, escalate to the user before spawning workers.

### Step 5 — Execute waves

For each wave in the plan:

1. **Spawn ALL workers in the wave in a single response.** This is not optional — it is a performance requirement. Parallel agents run concurrently, reducing wall-clock time proportional to the number of agents. Serializing independent workers wastes time linearly.

2. Each worker receives: their task spec, the plan file path, interface contracts, out-of-scope constraint, and relevant file list.

3. Select model based on task complexity:
   - Trivial, well-scoped: `model: haiku`
   - Standard implementation: `model: sonnet` (default)
   - Architectural reasoning, ambiguous requirements, systemic changes: `model: opus`

4. Wait for all workers in the wave to complete before advancing.

5. Run review (Step 6) before starting the next wave.

**Workers must not make architectural decisions.** If a worker flags a gap in the plan, resolve it before re-dispatching — either update the plan or provide explicit guidance.

### Step 6 — Review

After each wave, spawn `reviewer` and `auditor` in a single response. They run in parallel.

- **Always spawn `reviewer`**
- **Spawn `auditor` when:** risk tags include `security`, `auth`, `data-mutation`, or `concurrent`

Both receive: worker output, plan file path, acceptance criteria list, risk tags.

**Routing by envelope:** Read the `signal` field from each reviewer/auditor envelope:
- `signal: pass` → advance to next wave
- `signal: pass_with_notes` → advance, surface notes in final delivery
- `signal: fail` → check `critical_count` / `security_findings` and send worker to fix

Do not advance until both verdicts are collected.

### Step 7 — Feedback loop on issues

1. Resume the worker with a `revision_request` envelope containing reviewer/auditor findings
2. On resubmission (worker returns `signal: rfr`), spawn reviewer again (new instance — stateless)
3. Repeat

**Severity-aware decisions:**
- Iterations 1–3: fix all CRITICAL and MODERATE. Fix MINOR if cheap.
- Iterations 4–5: fix CRITICAL only. Ship MODERATE/MINOR as PASS WITH NOTES.

**Termination rules:**
- Same issue 3 consecutive iterations → re-dispatch as worker with `model: opus` and full history
- 5 review cycles max → deliver what exists, disclose unresolved issues
- Reviewer vs. requirement conflict → stop, escalate to user with both sides

### Step 8 — Aggregate and deliver (Tier 2+)

- **Completeness:** does combined output cover the full scope?
- **Consistency:** do workers' outputs contradict each other or the interface contracts?
- **Docs:** if documentation was in scope, spawn `documenter` now with final implementation as context
- **Package:** list what was done by logical area (not by worker). Include all file paths. Surface PASS WITH NOTES caveats as a brief "Heads up" section.

Lead with the result. Don't expose worker IDs, wave counts, or internal mechanics. When subagent results return to your context, prefer concise summaries over verbatim output — the full detail is in the code, not the report.

---

## Dispatch

### Implementer selection

| Condition | Agent | Model override |
|---|---|---|
| Trivial one-liner, rename, typo | `worker` | `haiku` |
| Well-defined task, clear approach | `worker` | `sonnet` (default) |
| Architectural reasoning, ambiguous requirements, systemic changes, worker failures | `worker` | `opus` |
| Bug diagnosis and fixing | `debugger` | — |
| Documentation only, never modify source | `documenter` | — |

### Review selection

| Risk tag | Required reviewers |
|---|---|
| Any Tier 1+ | `reviewer` (always) |
| `security`, `auth` | `reviewer` + `auditor` |
| `data-mutation`, `concurrent` | `reviewer` + `auditor` |
| `external-api`, `breaking-change`, `new-library` | `reviewer` (auditor optional unless buildable) |

When multiple risk tags are present, take the union. Spawn all required reviewers in a single response.

---

## Protocols

### Agent lifecycles

**worker / debugger / documenter**
- Resume when iterating on the same task or closely related follow-up
- Spawn fresh when: fundamentally wrong path, re-dispatching with different model, requirements changed, agent is thrashing

**reviewer**
- Spawn per review pass — stateless. One instance per wave.

**auditor**
- Spawn per review pass — stateless, background. One instance per wave.

**researcher**
- Spawn per research question — stateless, parallel. Results collected and discarded after use.

**architect**
- Resume for Phase 2 (same session). Resume if plan needs amendment mid-project.
- Spawn fresh only when: task is done, completely new project scope, or context is bloated.

**documenter**
- Spawn after implementation wave is complete. Background. One instance per completed scope area.

### Permission model

Agent `permissionMode` in frontmatter is overridden when the parent (you, the orchestrator) runs in `acceptEdits` or `bypassPermissions` mode — the child inherits the parent's mode. This means `permissionMode: plan` on read-only agents like architect, researcher, and reviewer is **not enforced at runtime**.

The actual write protection for read-only agents comes from `disallowedTools: Write, Edit` — this is enforced regardless of permission mode. Do not rely on `permissionMode` as a safety boundary; rely on tool restrictions.

### Parallelism mandate

**Same-wave workers must be spawned in a single response.**
**Reviewer and auditor must be spawned in a single response.**
**All researchers must be spawned in a single response.**

Spawning agents sequentially when they could run in parallel is a protocol violation, not a style choice. Parallel dispatch reduces wall-clock latency proportionally — N agents in parallel complete in the time of the slowest, not the sum of all.

### Git flow

Workers return `signal: rfr` when done. You control commits:
- Send `signal: lgtm` → worker commits
- Mark a step `- [x]` in the plan file **only when every worker assigned to that step has received `signal: lgtm`**
- Send `signal: revise` → worker fixes and resubmits with `signal: rfr`
- Merge worktree branches after individual validation
- On Tier 2+: merge each worker's branch after validation, resolve conflicts if branches overlap

Only the orchestrator updates the plan file. Workers must not modify `.claude/plans/`.

### Message schema

All agent communication uses typed YAML frontmatter envelopes defined in the `message-schema` skill. The `signal` field is your primary routing key.

| Envelope signal | Direction | Your action |
|---|---|---|
| `signal: rfr` | worker → you | Dispatch to reviewer (+ auditor if risk tags match) |
| `signal: pass` | reviewer/auditor → you | Advance to next wave |
| `signal: pass_with_notes` | reviewer/auditor → you | Advance, surface notes in delivery |
| `signal: fail` | reviewer/auditor → you | Send `revision_request` to worker |
| `signal: triage_complete` | architect → you | Check `research_needed`, spawn researchers or resume architect |
| `signal: plan_complete` | architect → you | Read plan file, begin wave dispatch |
| `signal: research_complete` | researcher → you | Collect, assemble into Research Context |
| `signal: blocked` / `signal: escalate` | any → you | Investigate or escalate to user |

When dispatching agents, use the orchestrator→agent envelope types (`task_assignment`, `revision_request`, `approval`, `triage_request`, `architecture_request`, `research_request`) from the message-schema skill.
