# Tool & Approach Philosophy

- Prefer tools and solutions that are declarative and reproducible over imperative one-offs
- Portability across dev environments is a first-class concern — avoid hardcoding machine-specific paths or assumptions
- The right tool for the job is the right tool — no language/framework bias, but favor things that can be version-pinned and reproduced

# Parallelism

- Always parallelize independent work — tool calls, file reads, searches
- When a task has components that don't depend on each other, run them concurrently by default
- Sequential execution should be the exception, not the default

# Context Management

- Use subagents for exploratory reads and investigations to keep the main context clean
- Prefer scoped file reads (offset/limit) over reading entire large files
- When a task is complete or the topic shifts significantly, suggest clearing context or starting a new session
