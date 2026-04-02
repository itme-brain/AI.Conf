# agent-team

A portable Claude Code agent team configuration. Clone it, run `install.sh`, and your Claude Code sessions get a full team of specialized subagents and shared skills — on any machine.

## Quick install

```bash
git clone <repo-url> ~/agent-team
cd ~/agent-team
nix develop              # enter devShell with yq + envsubst
./generate.sh            # generate Claude + Codex config from templates
./install.sh             # symlinks into ~/.claude/ and ~/.codex/ (if present)
```

The scripts generate configuration for both Claude Code and Codex CLI (if `~/.codex/` exists), then symlink agents, skills, rules, CLAUDE.md, and settings.json into `~/.claude/`. Works on Linux, macOS, and Windows (Git Bash).

## Maintenance

**Symlink fragility:** `~/.claude/CLAUDE.md` and `~/.claude/settings.json` are installed as symlinks by `install.sh`. Some tools (including Claude Code itself when writing settings) resolve symlinks to regular files on write, silently breaking the link. If edits to the repo are no longer reflected in `~/.claude/`, re-run `./install.sh` to restore the symlinks.

## Agents

| Agent | Model | Role |
|---|---|---|
| `worker` | sonnet (haiku/opus by orchestrator) | Universal implementer. Model scaled to task complexity. |
| `debugger` | sonnet | Diagnoses and fixes bugs with minimal targeted changes. |
| `documenter` | sonnet | Writes and updates docs. Never modifies source code. |
| `architect` | opus | Triage, research coordination, architecture design, wave decomposition. Read-only. |
| `researcher` | sonnet | Parallel fact-finding. One instance per research question. Read-only. |
| `reviewer` | sonnet | Code quality review + AC verification + claim checking. Read-only. |
| `auditor` | sonnet | Security analysis + runtime validation. Read-only, runs in background. |

## Skills

| Skill | Purpose |
|---|---|
| `orchestrate` | Orchestration framework — load on demand to decompose and delegate complex tasks |
| `conventions` | Core coding conventions and quality priorities shared by all agents |
| `worker-protocol` | Output format, feedback handling, and operational procedures for worker agents |
| `qa-checklist` | Self-validation checklist workers run before returning results |
| `message-schema` | Typed YAML frontmatter envelopes for all inter-agent communication |
| `project` | Instructs agents to check for and ingest a project-specific skill file before starting work |

## Rules

Global instructions are modularized in `rules/` and auto-loaded by Claude Code from `~/.claude/rules/` on every session. Each file covers a focused topic (git workflow, Nix preferences, response style, etc.). Agent-team specific protocols live in skills, not rules.

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

## Codex CLI compatibility

This project also generates configuration for [OpenAI Codex CLI](https://github.com/openai/codex). Claude Code config is the source of truth; Codex config is derived from it.

### Setup

```bash
nix develop              # enter devShell with yq + envsubst
./generate.sh            # generate Claude + Codex config from templates
./install.sh             # installs both Claude and Codex (if ~/.codex exists)
```

### What gets generated

| Source | Generated | Location |
|---|---|---|
| `agents/*.md` (templates) | `claude/agents/*.md` | `~/.claude/agents/` |
| `agents/*.md` (templates) | `codex/agents/*.toml` | `~/.codex/agents/` |
| `CLAUDE.md` + `rules/*.md` | `codex/AGENTS.md` | `~/.codex/AGENTS.md` |
| `settings.json` | `codex/config.toml` | `~/.codex/config.toml` |
| `skills/` | (shared as-is) | `~/.claude/skills/` + `~/.agents/skills/` |

### Model mapping

| Claude Code | Codex CLI |
|---|---|
| `opus` | `o3` |
| `sonnet` | `o4-mini` |
| `haiku` | `o4-mini` |

### Template variables

Agent body text uses `${VAR}` placeholders that are expanded per-target by `generate.sh`:

| Variable | Claude | Codex |
|---|---|---|
| `${PLANS_DIR}` | `.claude/plans` | `plans` |
| `${WEB_SEARCH}` | `via WebFetch/WebSearch` | `via web search` |
| `${SEARCH_TOOLS}` | `Use Grep/Glob/Read` | `Search the codebase` |

Skills and rules are tool-agnostic and shared as-is — do not add tool-specific references to them.

## Project-specific config

Each project repo can extend the team with local config in `.claude/`:

- `.claude/CLAUDE.md` — project-specific instructions (architecture notes, domain conventions, stack details)
- `.claude/agents/` — project-local agent overrides or additions
- `.claude/skills/project.md` — skill file that agents automatically ingest before starting work (see the `project` skill)

Commit `.claude/` with the project so the team has context wherever it runs.

## Memory

Two memory systems coexist:

- **Manual memory** (`.claude/memory/`) — curated context files with YAML frontmatter, indexed by `MEMORY.md`. Loaded as part of the CLAUDE.md hierarchy on every session. Use this for project decisions, user preferences, and reference pointers.
- **Agent memory** (`.claude/agent-memory/`) — Claude Code's built-in runtime memory, written automatically by agents with `memory: project` scope. Excluded from CLAUDE.md context via `claudeMdExcludes` to avoid polluting the context window.

Commit both directories with the repo so memory persists across machines and sessions.
