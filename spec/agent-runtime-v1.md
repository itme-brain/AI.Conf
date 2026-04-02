# Agent Runtime Config v1

`SETTINGS.yaml` is the human-authored source of truth for portable runtime intent in this repo.

Team inventory metadata is defined separately in `TEAM.yaml` (see `spec/team-protocol-v1.md`). This spec only covers runtime policy.

## Goals

- Keep one editable config for approval, filesystem, network, and model intent.
- Generate backward-compatible Claude and Codex outputs from that shared intent.
- Make adapter lossiness explicit where provider config surfaces do not line up.

## Scope

Version 1 standardizes:

- portable model tier and reasoning level
- filesystem access intent
- approval intent
- network access intent
- portable tool classes
- protected path rules
- dangerous shell command prompts
- target-specific escape hatches only when the target exposes settings with no shared equivalent

Version 1 does not attempt to standardize:

- every provider model name
- provider-specific tool grammars
- every future runtime capability for local agents, IDE plugins, or hosted agents

## Shared fields

### `model`

- `class`: `fast | balanced | powerful`
- `reasoning`: `low | medium | high | max`

### `runtime`

- `filesystem`: `read-only | workspace-write`
- `approval`: `manual | guarded-auto | full-auto`
- `network_access`: boolean
- `tools`: portable tool classes such as `shell`, `read`, `edit`, `write`, `glob`, `grep`, `web_fetch`, `web_search`

### `safety`

- `protected_paths`: glob patterns that should remain blocked from normal reads or writes
- `dangerous_shell_commands.ask`: shell command patterns that should remain approval-gated

### `targets`

Target blocks are escape hatches, not the main schema. Use them only where a runtime exposes a knob with no shared equivalent.

Current target-specific fields:

- `targets.claude.claude_md_excludes`
- `targets.codex.approval_policy`
- `targets.codex.network_access`

## Adapter rules

### Claude Code

`settings.json` is generated as a compatibility artifact.

- `runtime.filesystem = read-only` -> `permissions.defaultMode = "plan"`
- `runtime.filesystem = workspace-write` -> `permissions.defaultMode = "acceptEdits"`
- `runtime.tools` -> Claude tool allow-list
- `safety.protected_paths` -> Claude `deny` entries for `Read`, `Write`, and `Edit`
- `dangerous_shell_commands.ask` -> Claude `ask` entries wrapped as `Bash(...)`

Lossiness:

- Claude vends `allow` / `deny` / `ask` as tool-pattern rules.
- Shared `approval` intent does not map 1:1 to Claude beyond `plan` vs `acceptEdits`.

### Codex CLI

`codex/config.toml` is generated directly from shared intent.

- `runtime.filesystem = read-only` -> `sandbox_mode = "read-only"`
- `runtime.filesystem = workspace-write` -> `sandbox_mode = "workspace-write"`
- `runtime.approval = manual` -> `approval_policy = "on-request"`
- `runtime.approval = guarded-auto` -> `approval_policy = "untrusted"`
- `runtime.approval = full-auto` -> `approval_policy = "never"`
- `runtime.network_access` -> `[sandbox_workspace_write].network_access`

Lossiness:

- Codex does not expose Claude-style per-tool `allow` / `deny` / `ask` pattern controls in `config.toml`.
- Protected paths and dangerous command prompts are therefore only partially representable in Codex config today.

## Compatibility contract

The repo preserves these compatibility artifacts:

- `settings.json`
- `claude/settings.json`
- `claude/CLAUDE.md`
- `codex/config.toml`
- `codex/AGENTS.md`
- generated agent outputs for both targets

These are build artifacts, not authored source files. `SETTINGS.yaml` is the required runtime input.
