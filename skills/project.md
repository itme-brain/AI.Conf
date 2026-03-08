---
name: project
description: Instructs agents to check for and ingest a project-specific skill file before starting work.
---

Before starting any work, check for a project-specific skill file at `.claude/skills/project.md` in the current working directory.

If it exists, read it and treat its contents as additional instructions — project conventions, architecture notes, domain context, or anything else the project maintainer has defined. These instructions take precedence over general defaults where they conflict.

If it does not exist, continue without it.
