# agent-team

A Claude Code agent team with structured orchestration, review, and git management.

## Team structure

```
User (invokes via `claude --agent kevin`)
  └── Kevin (sonnet) ← PM and orchestrator
        ├── Grunt (haiku) ← trivial tasks (Tier 0)
        ├── Workers (sonnet) ← default implementers
        ├── Senior Workers (opus) ← complex/architectural tasks
        └── Karen (sonnet, background) ← independent reviewer, fact-checker
```

## Agents

| Agent | Model | Role |
|---|---|---|
| `kevin` | sonnet | PM — decomposes, delegates, validates, delivers. Never writes code. |
| `worker` | sonnet | Default implementer. Runs in isolated worktree. |
| `senior-worker` | opus | Escalation for architectural complexity or worker failures. |
| `grunt` | haiku | Lightweight worker for trivial one-liners. |
| `karen` | sonnet | Independent reviewer and fact-checker. Read-only, runs in background. |

## Skills

| Skill | Used by | Purpose |
|---|---|---|
| `conventions` | All agents | Coding conventions, commit format, quality priorities |
| `worker-protocol` | Workers, Senior Workers | Output format, commit flow (RFR/LGTM/REVISE), feedback handling |
| `qa-checklist` | Workers, Senior Workers | Self-validation checklist before returning output |

## Communication signals

| Signal | Direction | Meaning |
|---|---|---|
| `RFR` | Worker → Kevin | Work complete, ready for review |
| `LGTM` | Kevin → Worker | Approved, commit now |
| `REVISE` | Kevin → Worker | Needs fixes (issues attached) |
| `REVIEW` | Kevin → Karen | New review request |
| `RE-REVIEW` | Kevin → Karen | Updated output after fixes |
| `PASS` / `PASS WITH NOTES` / `FAIL` | Karen → Kevin | Review verdict |

## Installation

```bash
# Clone the repo
git clone <repo-url> ~/Documents/projects/agent-team
cd ~/Documents/projects/agent-team

# Run the install script (creates symlinks to ~/.claude/)
./install.sh
```

The install script symlinks `agents/` and `skills/` into `~/.claude/`. Works on Windows, Linux, and macOS.

## Usage

```bash
claude --agent kevin
```

Kevin handles everything from there — task tiers, worker dispatch, review, git management, and delivery.
