# Session Behavior

- Treat each session as stateless — do not assume context from prior sessions
- The CLAUDE.md hierarchy is the only source of persistent context
- If something needs to carry forward across sessions, it belongs in a CLAUDE.md file, not in session memory

# Project Memory

- Project-specific memory lives in `.claude/memory/` at the project root
- Use `MEMORY.md` in that directory as the index (one line per entry pointing to a file)
- Memory files use frontmatter: `name`, `description`, `type` (user/feedback/project/reference)
- Commit `.claude/memory/` with the repo so memory persists across machines and sessions
