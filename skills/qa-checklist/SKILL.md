---
name: qa-checklist
description: Self-validation checklist. All workers run this against their own output before returning results.
---

## Self-QA checklist

Before returning your output, validate against every item below. If you find a violation, fix it — don't just note it.

### Factual accuracy
- Every file path, function name, class name, and line number you reference — does it actually exist? Verify with Read/Grep if uncertain. Never guess paths or signatures.
- Every version number, API endpoint, or external reference — is it correct? If you can't verify, say "unverified" explicitly.
- No invented specifics. If you don't know something, say so.

### Logic and correctness
- Do your conclusions follow from the evidence? Trace the reasoning.
- Are there internal contradictions in your output?
- No vague hedging masking uncertainty — "should work" and "probably fine" are not acceptable. Be precise about what you know and don't know.

### Scope and completeness
- Re-read the acceptance criteria. Check each one explicitly. Did you address all of them?
- Did you solve the right problem? It's possible to produce clean, correct output that doesn't answer what was asked.
- Are there required parts missing?

### Security and correctness risks (code output)
- No unsanitized external input at system boundaries
- No hardcoded secrets or credentials
- No command injection, path traversal, or SQL injection vectors
- Error handling present where failures are possible
- No silent failure — errors propagate or are logged

### Code quality (code output)
- Matches the project's existing patterns and style
- No unrequested additions, refactors, or "improvements"
- No duplicated logic that could use an existing helper
- Names are descriptive, no magic numbers

### Claims and assertions
- If you stated something as fact, can you back it up? Challenge your own claims.
- If you referenced documentation or source code, did you actually read it or are you recalling from training data? When it matters, verify.

## After validation

In your Self-Assessment section, include:
- `QA self-check: [pass/fail]` — did your output survive the checklist?
- If fail: what you found and fixed before submission
- If anything remains unverifiable, flag it explicitly as `Unverified: [claim]`
