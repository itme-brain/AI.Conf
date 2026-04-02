---
date: 2026-04-02
task: template-based dual-target generator
tier: 2
status: active
---

## Plan: Template-based dual-target generator

## Summary

Refactor agent-team from "Claude source of truth with a Codex converter" to "tool-agnostic templates with a generator that produces both Claude and Codex output." Agent bodies gain `${VAR}` placeholders for tool-specific references. Skills and rules are made tool-agnostic by replacing Claude-specific tool names and paths with generic language. A new `generate.sh` replaces `generate-codex.sh` and produces both `claude/` and `codex/` output directories. `install.sh` changes to symlink from the generated `claude/` directory. The orchestrate skill stays Claude-only since it is deeply tied to Claude's Agent tool dispatch model.

## Out of Scope

- Changing agent frontmatter schema (YAML fields stay as-is; the generator handles YAML-to-TOML conversion)
- Adding new agents or skills
- Changing the orchestrate skill's content (it stays Claude-only, not templated)
- Changing conventions skill content (already tool-agnostic)
- Modifying the message-schema envelope format
- Codex config.toml generation (the current `generate-codex.sh` logic for mapping model/effort/sandbox is preserved, not redesigned)
- README content updates beyond what's needed to reflect the new structure

## Research Findings

**envsubst scoping:** `envsubst '${PLANS_DIR} ${WEB_SEARCH}'` substitutes only the listed variables, leaving other `$` references untouched. Safe for use in files with YAML frontmatter and bash-like content.

**Codex path conventions:** Codex has no `.claude/plans/` equivalent -- plans are regular files at `plans/` (project-relative). No `.claude/memory/` -- use `memory/` or omit. Skills are discovered from `~/.agents/skills/` via `SKILL.md` auto-matching or `skills.config` in agent TOML. Skills are NOT inlined into `developer_instructions`.

**Skill strategy:** Option B (make skills tool-agnostic) for most skills. Orchestrate stays Claude-only. Tool name references like "Use Read/Glob/Grep" add marginal value and can be replaced with generic language like "Search the codebase."

## Codebase Analysis

### Files to modify

| File | Change |
|---|---|
| `agents/architect.md` | Replace `.claude/plans/` (lines 19, 106) with `${PLANS_DIR}` |
| `agents/reviewer.md` | Replace `via WebFetch/WebSearch` (line 33) with `${WEB_SEARCH}` |
| `agents/debugger.md` | Replace `Use Grep` (line 25) with `${SEARCH_TOOLS}` |
| `agents/documenter.md` | Replace `Use Read/Glob/Grep` (line 29) with `${SEARCH_TOOLS}` |
| `skills/message-schema/SKILL.md` | Replace `.claude/plans/` (lines 155, 205) with `${PLANS_DIR}` |
| `skills/project/SKILL.md` | Replace `.claude/skills/project.md` (lines 7, 9) with `${PROJECT_SKILL_PATH}` |
| `skills/worker-protocol/SKILL.md` | Replace `Read/Glob/Grep` (line 50) with generic language |
| `skills/qa-checklist/SKILL.md` | Replace `Read/Grep` (line 13) with generic language |
| `rules/01-session.md` | Replace `.claude/memory/` (lines 3, 9, 12) with `${MEMORY_DIR}` |
| `rules/04-tools.md` | Replace `suggest /clear` (line 17) with `${CLEAR_CMD}` |
| `generate-codex.sh` | **Delete** -- replaced by `generate.sh` |
| `generate.sh` | **New** -- produces both `claude/` and `codex/` |
| `install.sh` | Rewire Claude symlinks to point at `claude/` output directory |
| `.gitignore` | Add `claude/` to exclusions |
| `flake.nix` | Add `envsubst` (from `gettext`) to devShell packages |

### Files for context (read-only)

| File | Why |
|---|---|
| `agents/worker.md` | Confirm no Claude-specific references in body (clean) |
| `agents/auditor.md` | Confirm no Claude-specific references in body (clean) |
| `agents/researcher.md` | Confirm no Claude-specific references in body (clean) |
| `skills/orchestrate/SKILL.md` | Confirm Claude-only decision (deeply coupled) |
| `skills/conventions/SKILL.md` | Confirm already tool-agnostic (clean) |
| `rules/02-responses.md` through `rules/07-research.md` | Confirm no Claude-specific references (clean, except 04-tools.md) |
| `codex/config.toml` | Understand current generated output (reference only) |

### Current patterns

- **Shell scripts** use `set -euo pipefail`, `SCRIPT_DIR` idiom, echo-based progress reporting
- **yq** (yq-go) is the YAML/JSON processor -- used for frontmatter extraction and settings parsing
- **Generated output** is committed to `codex/` but gitignored; `claude/` will follow the same pattern
- **Symlink strategy** in install.sh: directory symlinks for agents/skills/rules, file symlinks for individual config files; backup-on-conflict pattern
- **Agent markdown** uses YAML frontmatter with specific schema fields (`name`, `description`, `model`, `effort`, `permissionMode`, `tools`, `disallowedTools`, `maxTurns`, `skills`, `isolation`, `background`, `memory`)

## Interface Contracts

### Module ownership

- `generate.sh`: owned by Step 5 (Wave 3), responsible for template expansion + output generation
- `agents/*.md` templates: owned by Steps 1-2 (Wave 1), responsible for adding `${VAR}` placeholders
- `skills/` tool-agnostic edits: owned by Step 3 (Wave 1), responsible for removing tool-specific language
- `rules/` tool-agnostic edits: owned by Step 4 (Wave 1), responsible for removing tool-specific paths
- `install.sh`: owned by Step 6 (Wave 3), responsible for rewiring symlink sources
- `.gitignore` + `flake.nix`: owned by Step 7 (Wave 2), support infrastructure

### Shared interfaces

**Template variable contract** -- all workers must use exactly these variable names and nothing else:

```bash
# Variable definitions used by generate.sh for envsubst
# Claude target
PLANS_DIR=".claude/plans"
WEB_SEARCH="via WebFetch/WebSearch"
SEARCH_TOOLS="Use Grep/Glob/Read"
CLEAR_CMD="suggest /clear"
MEMORY_DIR=".claude/memory"
PROJECT_SKILL_PATH=".claude/skills/project.md"

# Codex target
PLANS_DIR="plans"
WEB_SEARCH="via web search"
SEARCH_TOOLS="Search the codebase"
CLEAR_CMD="suggest starting a new session"
MEMORY_DIR="memory"
PROJECT_SKILL_PATH=".agents/skills/project/SKILL.md"
```

**Agent body extraction pattern** (preserved from `generate-codex.sh`):
```bash
# Extract body after closing --- of frontmatter
awk 'BEGIN{fm=0} /^---$/{if(fm==0){fm=1;next} if(fm==1){fm=2;next}} fm==2{print}' "$src_file"
```

**Claude output directory structure:**
```
claude/
├── agents/           # Expanded .md files (frontmatter preserved, body substituted)
├── CLAUDE.md         # Copied from source
├── settings.json     # Copied from source
├── rules -> ../rules # Symlink to shared rules (already tool-agnostic after Wave 1)
└── skills -> ../skills # Symlink to shared skills (already tool-agnostic after Wave 1)
```

**Codex output directory structure:**
```
codex/
├── agents/           # Generated .toml files (body substituted with Codex values)
├── AGENTS.md         # Generated from CLAUDE.md + expanded rules
└── config.toml       # Generated from settings.json
```

### Conventions for this task

- Error handling: `set -euo pipefail` in all shell scripts. Echo progress for each major operation. Non-zero exit on failure.
- Naming: `${UPPER_SNAKE_CASE}` for template variables. `kebab-case` for file names.
- Template markers: Use `${VAR}` syntax only. Never use `$VAR` (ambiguous with shell) or `{{VAR}}` (not envsubst-compatible).
- Skill/rule edits: Replace tool-specific language with generic equivalents. Do NOT add `${VAR}` placeholders to skills or rules -- they are made tool-agnostic directly, not templated. Only agent bodies and message-schema (which references plan paths in examples) use template variables.

**Correction on skill/rule strategy:** Skills and rules become tool-agnostic by direct edit (hardcoded generic language). They are then shared as-is between both targets via symlinks from the output directories. Template variables (`${VAR}`) are used ONLY in agent body markdown and in message-schema's example paths. This keeps the template surface minimal.

However, `rules/01-session.md` and `rules/04-tools.md` present a problem: their content differs between Claude and Codex (`.claude/memory/` vs `memory/`, `/clear` vs "new session"). Two approaches:

**Approach A -- Template the rules too:** Add `${VAR}` placeholders to rules and expand them per-target. This means rules can't be symlinked; they must be copied into each output directory.
**Approach B -- Make rules fully generic:** Use tool-agnostic language ("the project memory directory", "suggest clearing context"). No placeholders needed; rules stay shared.

**Decision: Approach B.** The rules are guidance for agent behavior, not config. Generic language ("the project memory directory at the project root") communicates the intent without coupling to a specific path. The exact path is already established by the agent body templates and skills. This keeps the template surface to just agent bodies + message-schema examples.

**Revised skill/rule edit strategy:**
- `rules/01-session.md`: Replace `.claude/memory/` with `memory/` (tool-agnostic path). This works for both targets because the rules describe conceptual behavior ("persist in the memory directory"), and the actual path resolution happens in agent instructions.
- `rules/04-tools.md`: Replace `suggest /clear` with `suggest clearing context or starting a new session` (tool-agnostic).
- `skills/worker-protocol/SKILL.md`: Replace `use Read/Glob/Grep directly` with `verify by reading the relevant files directly` (tool-agnostic).
- `skills/qa-checklist/SKILL.md`: Replace `Verify with Read/Grep if uncertain` with `Verify by reading the code if uncertain` (tool-agnostic).
- `skills/project/SKILL.md`: This one references a concrete file path (`.claude/skills/project.md`). Two options: (a) make it generic ("check for a project-specific skill file in the standard location"), or (b) template it. Since the path genuinely differs between tools and is specific enough to matter, **template it** with `${PROJECT_SKILL_PATH}`. This means the project skill gets expanded per-target, not symlinked. But since skills are directory-symlinked as a whole, we need a different approach: generate only this one skill per-target, or restructure.

**Revised approach for project skill:** The simplest solution is to make the path generic. The project skill says "check for a project-specific skill file" -- the agent already knows where to look because each tool has its own conventions. Change the instruction to: "Check for a project-specific skill file in the current working directory's configuration. For Claude Code, this is `.claude/skills/project.md`. For Codex, this is discovered via the standard skill path." Actually this leaks tool awareness into the shared file.

**Final decision for project skill:** Make it fully generic: "Before starting any work, check for a project-specific skill file in the current working directory. The location depends on the tool configuration." The concrete path is not needed -- each tool resolves its own skill paths. The skill's purpose is behavioral ("check for project context before starting"), not path-specific.

Similarly for message-schema `plan_file` examples: these show `.claude/plans/kebab-case-title.md` as an example value. For Codex, this would be `plans/kebab-case-title.md`. Since message-schema is loaded as a skill (shared), we should either template it or make the example generic. **Decision:** Use `plans/kebab-case-title.md` as the example (dropping the `.claude/` prefix). This is the tool-agnostic path. Claude's architect agent body already specifies the full `.claude/plans/` path, so the schema example doesn't need to repeat the tool-specific prefix.

**Final template variable list (reduced):**

Only agent body markdown files use `${VAR}` placeholders. Everything else is made tool-agnostic by direct edit.

| Variable | Claude value | Codex value | Used in |
|---|---|---|---|
| `${PLANS_DIR}` | `.claude/plans` | `plans` | architect.md body |
| `${WEB_SEARCH}` | `via WebFetch/WebSearch` | `via web search` | reviewer.md body |
| `${SEARCH_TOOLS}` | `Use Grep/Glob/Read` | `Search the codebase` | debugger.md body, documenter.md body |

Skills, rules, and message-schema are made tool-agnostic by direct edit (no placeholders).

## Approach

**Strategy:** Two-layer approach.

1. **Layer 1 -- Tool-agnostic shared content.** Skills and rules are edited to remove Claude-specific tool names and paths. They become shared infrastructure, symlinked from both output directories.

2. **Layer 2 -- Templated agent bodies.** Agent markdown files in `agents/` gain `${VAR}` placeholders in their body text (not frontmatter). `generate.sh` expands these with tool-specific values and writes the results to `claude/` and `codex/`.

The generator (`generate.sh`) replaces `generate-codex.sh` and handles both targets:
- **Claude target:** Expand templates with Claude values, copy frontmatter-intact agent .md files to `claude/agents/`, copy CLAUDE.md and settings.json, symlink to shared skills/rules.
- **Codex target:** Expand templates with Codex values, convert YAML frontmatter to TOML (preserving existing model/effort/sandbox mapping logic), generate AGENTS.md from CLAUDE.md + expanded rules, generate config.toml from settings.json.

**Alternative considered: Jinja/m4 templating.** Rejected -- envsubst is simpler, already available via gettext in Nix, and sufficient for the ~3 variable substitutions in agent bodies. The complexity of Jinja (conditional blocks, filters) is not needed.

**Alternative considered: Keep Claude agents as source, derive Codex only.** This is the current approach. Rejected because it means the "source" files contain Claude-specific references that leak into Codex output (the current bug this refactor fixes). Making the source tool-agnostic eliminates the class of bugs where a Codex agent says "Use Grep" or references `.claude/plans/`.

## Risks & Gotchas

1. **envsubst touching unintended `$` in agent bodies.** Mitigated by using the scoped form: `envsubst '${PLANS_DIR} ${WEB_SEARCH} ${SEARCH_TOOLS}'`. Only listed variables are substituted. The architect body contains `$` in example YAML blocks, which must NOT be substituted.

2. **YAML frontmatter containing `$`.** The frontmatter is not passed through envsubst -- only the body. The generator extracts frontmatter and body separately, expands only the body, then reassembles.

3. **Skills/rules shared as symlinks -- edit affects both targets immediately.** This is intentional. The skills and rules are tool-agnostic after Wave 1, so sharing is correct. But if someone adds a Claude-specific reference to a shared skill later, it leaks to Codex. The README should document this constraint.

4. **Codex config.toml gets overwritten.** The user's `codex/config.toml` has been manually edited (different content than what generate-codex.sh produces). `generate.sh` will overwrite it. Mitigation: document that `codex/config.toml` is generated and should not be hand-edited. User customizations should go in the source `settings.json`.

5. **install.sh behavior change.** Currently installs directly from `agents/` source. After this change, it installs from `claude/agents/` (generated). Users must run `generate.sh` before `install.sh`. The install script should check for this and error with guidance.

6. **orchestrate skill references `.claude/plans/` paths.** This is acceptable -- orchestrate is Claude-only (not used by Codex). The skill is still shared via the skills directory symlink, but Codex agents don't load it (it's not in their skills list).

## Risk Tags

breaking-change (install.sh workflow changes: generate.sh must run first), data-mutation (generates files to claude/ and codex/ directories)

## Implementation Waves

### Wave 1 -- Make skills and rules tool-agnostic (4 parallel tasks)

These are independent edits to different files. No task depends on another.

- [ ] **Step 1: Template agent bodies** -- Add `${VAR}` placeholders to agent markdown files.
  - `agents/architect.md`: Replace `.claude/plans/<kebab-case-title>.md` with `${PLANS_DIR}/<kebab-case-title>.md` (line 19) and `.claude/plans/kebab-case-title.md` with `${PLANS_DIR}/kebab-case-title.md` (line 106). There is also a `.claude/plans/` reference on line 69 inside the orchestrator's resume instruction -- replace that too. Verify no other `.claude/` references exist in the body.
  - `agents/reviewer.md`: Replace `via WebFetch/WebSearch` with `${WEB_SEARCH}` (line 33).
  - `agents/debugger.md`: Replace `Use Grep to find the relevant code` with `${SEARCH_TOOLS} to find the relevant code` (line 25). Verify the surrounding sentence reads naturally.
  - `agents/documenter.md`: Replace `Use Read/Glob/Grep to understand the actual behavior` with `${SEARCH_TOOLS} to understand the actual behavior` (line 29).

- [ ] **Step 2: Make message-schema tool-agnostic** -- Edit `skills/message-schema/SKILL.md`.
  - Replace `plan_file: .claude/plans/kebab-case-title.md` with `plan_file: plans/kebab-case-title.md` (lines 155, 205). This is an example value in the schema, not a literal config -- using the generic path is correct.
  - Do NOT change the envelope structure or field names.

- [ ] **Step 3: Make skills tool-agnostic** -- Edit skills that contain Claude-specific tool names.
  - `skills/worker-protocol/SKILL.md` line 50: Replace `use Read/Glob/Grep directly. Don't guess at file contents — verify.` with `verify by reading the relevant files. Don't guess at file contents.`
  - `skills/qa-checklist/SKILL.md` line 13: Replace `Verify with Read/Grep if uncertain.` with `Verify by reading the code if uncertain.`
  - `skills/project/SKILL.md` lines 7, 9: Replace `.claude/skills/project.md` with `a project-specific skill file`. Rewrite the two sentences:
    - Line 7: "Before starting any work, check for a project-specific skill file in the current working directory's tool configuration."
    - Line 9: "If one exists, read it and treat its contents as additional instructions..."
  - Do NOT edit `skills/orchestrate/SKILL.md` (stays Claude-only) or `skills/conventions/SKILL.md` (already clean).

- [ ] **Step 4: Make rules tool-agnostic** -- Edit rules with Claude-specific references.
  - `rules/01-session.md`: Replace all three occurrences of `.claude/memory/` with `memory/`. Update surrounding prose if needed for clarity. The CLAUDE.md hierarchy reference on line 3 is fine -- it's a generic concept name, not a file path (each tool has its own hierarchy).
  - `rules/04-tools.md` line 17: Replace `suggest /clear` with `suggest clearing context or starting a new session`.

### Wave 2 -- Infrastructure (depends on Wave 1 for knowing the final variable list)

- [ ] **Step 5: Update .gitignore and flake.nix** -- Support infrastructure for the new generator.
  - `.gitignore`: Add `claude/` line (generated output, same treatment as `codex/`). Keep the existing `codex/` line.
  - `flake.nix`: Add `pkgs.gettext` to the devShell packages list (provides `envsubst`). Keep existing `pkgs.yq-go` and `pkgs.codex`.

### Wave 3 -- Generator and installer (depends on Wave 1 for templates, Wave 2 for infrastructure)

- [ ] **Step 6: Write generate.sh** -- New unified generator replacing `generate-codex.sh`.
  - Location: `generate.sh` (project root, same level as old `generate-codex.sh`)
  - Delete `generate-codex.sh` (or rename -- but deleting is cleaner since the new script fully replaces it)
  - **Claude target generation:**
    1. Create `claude/agents/` directory
    2. For each `agents/*.md`: extract frontmatter and body separately. Run body through `envsubst '${PLANS_DIR} ${WEB_SEARCH} ${SEARCH_TOOLS}'` with Claude variable values. Reassemble frontmatter + expanded body. Write to `claude/agents/<name>.md`.
    3. Copy `CLAUDE.md` to `claude/CLAUDE.md`
    4. Copy `settings.json` to `claude/settings.json`
    5. Create relative symlinks: `claude/rules -> ../rules`, `claude/skills -> ../skills`
  - **Codex target generation** (preserve all existing logic from `generate-codex.sh`):
    1. Create `codex/agents/` directory
    2. For each `agents/*.md`: extract frontmatter and body. Run body through `envsubst '${PLANS_DIR} ${WEB_SEARCH} ${SEARCH_TOOLS}'` with Codex variable values. Convert frontmatter to TOML format (same mapping functions: `map_model`, `map_effort`, `map_sandbox_mode`). Write to `codex/agents/<name>.toml`.
    3. Generate `codex/AGENTS.md` from `CLAUDE.md` + rules/*.md (same logic as current `generate-codex.sh`)
    4. Generate `codex/config.toml` from `settings.json` (same logic as current)
  - **Script structure:**
    ```bash
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # --- Variable definitions ---
    # Claude target
    declare -A CLAUDE_VARS=(
      [PLANS_DIR]=".claude/plans"
      [WEB_SEARCH]="via WebFetch/WebSearch"
      [SEARCH_TOOLS]="Use Grep/Glob/Read"
    )
    # Codex target
    declare -A CODEX_VARS=(
      [PLANS_DIR]="plans"
      [WEB_SEARCH]="via web search"
      [SEARCH_TOOLS]="Search the codebase"
    )

    # --- Shared functions ---
    extract_frontmatter() { ... }  # yq --front-matter=extract
    extract_body() { ... }         # awk pattern from current script
    expand_body() { ... }          # envsubst with scoped variable list

    # --- Claude generation ---
    generate_claude() { ... }

    # --- Codex generation (ported from generate-codex.sh) ---
    generate_codex() { ... }

    generate_claude
    generate_codex
    echo "Done. Run ./install.sh to link into tool directories."
    ```
  - **Key detail for envsubst scoping:** The `expand_body` function must export only the target's variables, run envsubst with the explicit variable list, then unset them. This prevents cross-contamination and protects other `$` references in the body.
    ```bash
    expand_body() {
      local body="$1"
      shift
      # Remaining args are KEY=VALUE pairs
      local var_list=""
      for pair in "$@"; do
        local key="${pair%%=*}"
        local val="${pair#*=}"
        export "$key=$val"
        var_list+=" \${$key}"
      done
      echo "$body" | envsubst "$var_list"
      for pair in "$@"; do
        unset "${pair%%=*}"
      done
    }
    ```

- [ ] **Step 7: Update install.sh** -- Rewire to use generated output.
  - **Claude installation:** Change `AGENTS_SRC` from `$SCRIPT_DIR/agents` to `$SCRIPT_DIR/claude/agents`. Change `CLAUDE_MD_SRC` from `$SCRIPT_DIR/CLAUDE.md` to `$SCRIPT_DIR/claude/CLAUDE.md`. Change `SETTINGS_SRC` from `$SCRIPT_DIR/settings.json` to `$SCRIPT_DIR/claude/settings.json`. Skills and rules still symlink from source (they're tool-agnostic and shared): `SKILLS_SRC="$SCRIPT_DIR/skills"`, `RULES_SRC="$SCRIPT_DIR/rules"` (unchanged).
  - **Pre-flight check:** At the top of install.sh, verify `claude/` directory exists. If not, print: `"Error: claude/ not found. Run ./generate.sh first."` and exit 1.
  - **Codex installation:** Change `codex/agents` source to `$SCRIPT_DIR/codex/agents` (already correct). Keep all other Codex paths the same.
  - Preserve the entire symlink helper infrastructure (create_symlink, create_file_symlink, OS detection, backup logic).

### Wave 4 -- Documentation and cleanup (depends on Wave 3)

- [ ] **Step 8: Update README.md** -- Reflect the new workflow.
  - Quick install section: add `./generate.sh` before `./install.sh`
  - Codex CLI compatibility section: update to reflect `generate.sh` replaces `generate-codex.sh` and now generates both targets
  - "What gets generated" table: add Claude row showing `agents/*.md` -> `claude/agents/*.md`
  - Add a note about template variables and the tool-agnostic constraint on shared skills/rules
  - Remove references to `generate-codex.sh`

## Acceptance Criteria

1. `./generate.sh` produces `claude/agents/*.md` with Claude-specific values expanded (`.claude/plans/`, `Use Grep/Glob/Read`, etc.) -- verified by: grep the generated files for expanded values, confirm no `${` remains
2. `./generate.sh` produces `codex/agents/*.toml` with Codex-specific values expanded (`plans/`, `Search the codebase`, etc.) -- verified by: grep the generated files for expanded values, confirm no `${` remains
3. No Claude-specific tool names (`Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch`, `Edit`, `Write`) appear in skills (except orchestrate) or rules -- verified by: grep shared skills and rules for these tool names
4. No `.claude/` paths appear in skills (except orchestrate) or rules -- verified by: grep shared skills and rules for `.claude/`
5. `./install.sh` errors with a helpful message if `claude/` does not exist -- verified by: manual test
6. `./install.sh` successfully symlinks from `claude/` when it exists -- verified by: manual test
7. Codex output is functionally identical to what `generate-codex.sh` produced (same TOML structure, same model/effort/sandbox mappings) except with Codex-specific values substituted -- verified by: diff old and new codex/ output
8. The `envsubst` expansion does NOT touch `$` characters in YAML frontmatter or example code blocks -- verified by: inspect architect.md generated output for intact `$` in YAML examples
9. `flake.nix` devShell includes `gettext` (provides envsubst) -- verified by: `nix develop -c which envsubst`
