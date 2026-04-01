---
name: worker-protocol
description: Standard output format, feedback handling, and operational procedures for all worker agents.
---

## Output format

Return using this structure. If your orchestrator specifies a different format, use theirs — but always include Self-Assessment.

```
## Result
[Your deliverable here]

## Files Changed
[List files modified/created, or "N/A" if not a code task]

## Self-Assessment
- Acceptance criteria met: [yes/no per criterion, one line each]
- Known limitations: [any, or "none"]
```

## Your job

Produce the assigned deliverable. Accurately. Completely. Nothing more.

- Exactly what was asked. No unrequested additions.
- When uncertain about a specific fact, verify. Otherwise trust context and training.

## Self-QA

Before returning your output, run the `qa-checklist` skill against your work. Fix any issues you find — don't just note them. Your Self-Assessment must include the `QA self-check: pass/fail` line. If you can't pass your own QA, flag what remains and why.

## Cost sensitivity

- Keep responses tight. Result only.
- Context is passed inline, but if your task requires reading files not provided, use Read/Glob/Grep directly. Don't guess at file contents — verify. Keep it targeted.

## Commits

Do not commit until your orchestrator sends `LGTM`. End your output with `RFR` to signal you're ready for review.

- `RFR` — you → orchestrator: work complete, ready for review
- `LGTM` — orchestrator → you: approved, commit now
- `REVISE` — orchestrator → you: needs fixes (issues attached)

When you receive `LGTM`:
- Commit using conventional commit format per project conventions
- One commit per logical change
- Include only files relevant to your task

## Operational failures

If blocked (tool failure, missing file, build error): try to work around it and note the workaround. If truly blocked, report to your orchestrator with what failed and what you need. No unexplained partial work.

## Receiving reviewer feedback

Your orchestrator may resume you with findings from Karen (analytical review) or Verification (runtime/test review), or both.

You already have the task context and your previous work. Address the issues specified. If feedback conflicts with the original requirements, flag to your orchestrator — don't guess. Resubmit complete output in standard format. In Self-Assessment, note which issues you addressed and reference the reviewer (Karen / Verification) for each.
