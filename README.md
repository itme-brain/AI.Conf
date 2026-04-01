# agent-team

A portable Claude Code agent team configuration. Clone it, run `install.sh`, and your Claude Code sessions get a full team of specialized subagents and shared skills — on any machine.

## Quick install

```bash
git clone <repo-url> ~/Documents/Personal/projects/agent-team
cd ~/Documents/Personal/projects/agent-team
./install.sh
```

The script symlinks `agents/`, `skills/`, `CLAUDE.md`, and `settings.json` into `~/.claude/`. Works on Linux, macOS, and Windows (Git Bash).

## Agents

| Agent | Model | Role |
|---|---|---|
| `grunt` | haiku | Trivial tasks — typos, renames, one-liners. No planning or review. |
| `worker` | sonnet | Default implementer for well-defined tasks. |
| `senior-worker` | opus | Escalation for architectural complexity or worker failures. |
| `debugger` | sonnet | Diagnoses and fixes bugs with minimal targeted changes. |
| `docs-writer` | sonnet | Writes and updates docs. Never modifies source code. |
| `plan` | opus | Research-first planning. Produces implementation plans for workers. Read-only. |
| `code-reviewer` | sonnet | Reviews diffs for quality, correctness, and coverage. Read-only. |
| `security-auditor` | opus | Audits security-sensitive changes for vulnerabilities. Read-only. |
| `karen` | opus | Independent fact-checker. Verifies worker output against source and web. Read-only, runs in background. |

## Skills

| Skill | Purpose |
|---|---|
| `orchestrate` | Orchestration framework — load on demand to decompose and delegate complex tasks |
| `conventions` | Core coding conventions and quality priorities shared by all agents |
| `worker-protocol` | Output format, feedback handling, and operational procedures for worker agents |
| `qa-checklist` | Self-validation checklist workers run before returning results |
| `project` | Instructs agents to check for and ingest a project-specific skill file before starting work |

## How to use

In an interactive Claude Code session, load the orchestrate skill when a task is complex enough to warrant delegation:

```
/skill orchestrate
```

Once loaded, Claude acts as orchestrator — decomposing tasks, selecting agents, reviewing output, and managing the git flow. Agents are auto-delegated based on task type; you don't invoke them directly.

For simple tasks, agents can be invoked directly:

```
/agent worker Fix the broken pagination in the user list endpoint
```

## Project-specific config

Each project repo can extend the team with local config in `.claude/`:

- `.claude/CLAUDE.md` — project-specific instructions (architecture notes, domain conventions, stack details)
- `.claude/agents/` — project-local agent overrides or additions
- `.claude/skills/project.md` — skill file that agents automatically ingest before starting work (see the `project` skill)

Commit `.claude/` with the project so the team has context wherever it runs.

## Agent memory

Agents with `memory: project` scope write persistent memory to `.claude/agent-memory/` in the project directory. This memory is project-scoped and can be committed with the repo so future sessions pick up where prior ones left off.
