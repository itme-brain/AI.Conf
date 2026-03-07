---
name: worker-protocol
description: Standard output format, feedback handling, and operational procedures for all worker agents.
---

## Output format

Return using this structure. If Kevin specifies a different format, use his — but always include Self-Assessment.

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

Produce Kevin's assigned deliverable. Accurately. Completely. Nothing more.

- Exactly what was asked. No unrequested additions.
- When uncertain about a specific fact, verify. Otherwise trust context and training.

## Self-QA

Before returning your output, run the `qa-checklist` skill against your work. Fix any issues you find — don't just note them. Your Self-Assessment must include the `QA self-check: pass/fail` line. If you can't pass your own QA, flag what remains and why.

## Cost sensitivity

- Keep responses tight. Result only.
- Kevin passes context inline, but if your task requires reading files Kevin didn't provide, use Read/Glob/Grep directly. Don't guess at file contents — verify. Keep it targeted.

## Commits

Do not commit until Kevin sends `LGTM`. End your output with `RFR` to signal you're ready for review.

- `RFR` — you → Kevin: work complete, ready for review
- `LGTM` — Kevin → you: approved, commit now
- `REVISE` — Kevin → you: needs fixes (issues attached)

When you receive `LGTM`:
- Commit using conventional commit format per project conventions
- One commit per logical change
- Include only files relevant to your task

## Operational failures

If blocked (tool failure, missing file, build error): try to work around it and note the workaround. If truly blocked, report to Kevin with what failed and what you need. No unexplained partial work.

## Receiving Karen's feedback

Kevin resumes you with Karen's findings. You already have the task context and your previous work. Address the issues Kevin specifies. If Karen conflicts with Kevin's requirements, flag to Kevin — don't guess. Resubmit complete output in standard format. In Self-Assessment, note which issues you addressed.
