# Global Claude Code Instructions

## Session Behavior
- Treat each session as stateless — do not assume context from prior sessions
- The CLAUDE.md hierarchy is the only source of persistent context
- If something needs to carry forward across sessions, it belongs in a CLAUDE.md file, not in session memory


## Commits & Git Workflow
- Make many small, tightly scoped commits — one logical change per commit
- Commit messages should be concise and imperative ("Add X", "Fix Y", "Remove Z")
- Ask before pushing to remote or force-pushing
- Ask before opening PRs unless explicitly told to

## Responses & Explanations
- Be concise — lead with the action or answer, not the preamble
- Include just enough reasoning to explain *why* a decision was made, not a full walkthrough
- Skip trailing summaries ("Here's what I did...") — the diff speaks for itself
- No emojis unless explicitly asked

## Tool & Approach Philosophy
- Prefer tools and solutions that are declarative and reproducible over imperative one-offs
- Portability across dev environments is a first-class concern — avoid hardcoding machine-specific paths or assumptions
- The right tool for the job is the right tool — no language/framework bias, but favor things that can be version-pinned and reproduced

## Parallelism
- Always parallelize independent work — tool calls, subagents, file reads, searches
- When a task has components that don't depend on each other, run them concurrently by default
- Spin up subagents for distinct workstreams (audits, refactors, tests, docs) rather than working sequentially
- Subagents should always use the Sonnet model for best speed and token efficiency
- Sequential execution should be the exception, not the default

## Verification
- After making changes, run relevant tests or build commands to verify correctness before reporting success
- If no tests exist for the changed code, say so rather than silently assuming it works
- Prefer running single targeted tests over the full suite unless asked otherwise

## Context Management
- Use subagents for exploratory reads and investigations to keep the main context clean
- Prefer scoped file reads (offset/limit) over reading entire large files
- When a task is complete or the topic shifts significantly, suggest /clear

## When Things Go Wrong
- If an approach fails twice, stop and reassess rather than continuing to iterate
- Present the failure clearly and propose an alternative before proceeding

## Research Before Acting
- Before implementing a solution, research it — read relevant documentation, search for existing patterns, check official sources
- Do not reason from first principles when documentation or prior art exists
- Prefer verified answers over confident guesses
