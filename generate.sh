#!/usr/bin/env bash
set -euo pipefail

# generate.sh — generates both Claude and Codex output directories from
# shared agent source files plus a vendor-neutral runtime config.
# Agent source files (agents/*.md) are the single source of truth; this
# script derives tool-specific equivalents.
#
# Template variables in agent bodies are expanded per-target:
#   ${PLANS_DIR}      — where plans live (.claude/plans vs plans)
#   ${WEB_SEARCH}     — how web search is referenced
#   ${SEARCH_TOOLS}   — how codebase search tools are referenced
#
# Idempotent: safe to run multiple times.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENTS_SRC="$SCRIPT_DIR/agents"
RULES_DIR="$SCRIPT_DIR/rules"
CLAUDE_MD="$SCRIPT_DIR/CLAUDE.md"
SETTINGS_SHARED_YAML="$SCRIPT_DIR/SETTINGS.yaml"
TEAM_YAML="$SCRIPT_DIR/TEAM.yaml"
SETTINGS_JSON="$SCRIPT_DIR/settings.json"

CLAUDE_DIR="$SCRIPT_DIR/claude"
CLAUDE_AGENTS_DIR="$CLAUDE_DIR/agents"

CODEX_DIR="$SCRIPT_DIR/codex"
CODEX_AGENTS_DIR="$CODEX_DIR/agents"

# ---------------------------------------------------------------------------
# Template variable values per target (KEY=VALUE pairs)
# ---------------------------------------------------------------------------
CLAUDE_VARS=(
    "PLANS_DIR=.claude/plans"
    "WEB_SEARCH=via WebFetch/WebSearch"
    "SEARCH_TOOLS=Use Grep/Glob/Read"
)

CODEX_VARS=(
    "PLANS_DIR=plans"
    "WEB_SEARCH=via web search"
    "SEARCH_TOOLS=Search the codebase"
)

# ---------------------------------------------------------------------------
# extract_body — extracts everything after the second --- (YAML frontmatter)
# ---------------------------------------------------------------------------
extract_body() {
    local file="$1"
    awk 'BEGIN{fm=0} /^---$/{if(fm==0){fm=1;next} if(fm==1){fm=2;next}} fm==2{print}' "$file"
}

# ---------------------------------------------------------------------------
# expand_body — runs envsubst on body text, substituting only our 3 variables
#   $1 = body text
#   $2.. = KEY=VALUE pairs to export
# ---------------------------------------------------------------------------
expand_body() {
    local body="$1"
    shift
    # Export only the specified variables
    for pair in "$@"; do
        export "${pair%%=*}=${pair#*=}"
    done
    echo "$body" | envsubst '${PLANS_DIR} ${WEB_SEARCH} ${SEARCH_TOOLS}'
    # Clean up exported variables
    for pair in "$@"; do
        unset "${pair%%=*}"
    done
}

# ---------------------------------------------------------------------------
# yaml_escape_single_quoted — escapes text for YAML single-quoted scalars
# ---------------------------------------------------------------------------
yaml_escape_single_quoted() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# ---------------------------------------------------------------------------
# csv_from_yaml_array — joins YAML array values from stdin with ", "
# ---------------------------------------------------------------------------
csv_from_yaml_array() {
    local first=1
    local item
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ "$first" -eq 0 ]; then
            printf ', '
        fi
        printf '%s' "$item"
        first=0
    done
}

# ---------------------------------------------------------------------------
# validate_team_protocol — validates TEAM protocol fields and referenced files
# ---------------------------------------------------------------------------
validate_team_protocol() {
    [ -f "$TEAM_YAML" ] || {
        echo "Error: missing $TEAM_YAML"
        exit 1
    }

    yq -e '.version == 1' "$TEAM_YAML" > /dev/null
    yq -e '.agents.order and .agents.items and .skills.order and .skills.items and .rules.order and .rules.items' "$TEAM_YAML" > /dev/null

    local section id ids_in_order
    for section in agents skills rules; do
        while IFS= read -r id; do
            [ -n "$id" ] || continue
            yq -e ".${section}.items.${id}" "$TEAM_YAML" > /dev/null
            [ "$(yq -r ".${section}.items.${id}.id" "$TEAM_YAML")" = "$id" ] || {
                echo "Error: TEAM ${section} item '${id}' has mismatched id field"
                exit 1
            }
        done < <(yq -r ".${section}.order[]" "$TEAM_YAML")

        ids_in_order="$(yq -r ".${section}.order[]" "$TEAM_YAML")"
        while IFS= read -r id; do
            [ -n "$id" ] || continue
            printf '%s\n' "$ids_in_order" | grep -qx "$id" || {
                echo "Error: TEAM ${section} item '${id}' missing from order list"
                exit 1
            }
        done < <(yq -r ".${section}.items | keys | .[]" "$TEAM_YAML")
    done

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        local path
        path="$SCRIPT_DIR/$(yq -r ".agents.items.${id}.instruction_file" "$TEAM_YAML")"
        [ -f "$path" ] || {
            echo "Error: missing agent instruction file for '${id}': $path"
            exit 1
        }
    done < <(yq -r '.agents.order[]' "$TEAM_YAML")

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        local path
        path="$SCRIPT_DIR/$(yq -r ".skills.items.${id}.instruction_file" "$TEAM_YAML")"
        [ -f "$path" ] || {
            echo "Error: missing skill instruction file for '${id}': $path"
            exit 1
        }
    done < <(yq -r '.skills.order[]' "$TEAM_YAML")

    while IFS= read -r id; do
        [ -n "$id" ] || continue
        local path
        path="$SCRIPT_DIR/$(yq -r ".rules.items.${id}.source_file" "$TEAM_YAML")"
        [ -f "$path" ] || {
            echo "Error: missing rule source file for '${id}': $path"
            exit 1
        }
    done < <(yq -r '.rules.order[]' "$TEAM_YAML")
}

# ---------------------------------------------------------------------------
# validate_shared_settings — validates the shared protocol fields we rely on
# ---------------------------------------------------------------------------
validate_shared_settings() {
    [ -f "$SETTINGS_SHARED_YAML" ] || {
        echo "Error: missing $SETTINGS_SHARED_YAML"
        exit 1
    }

    yq -e '.version == 1' "$SETTINGS_SHARED_YAML" > /dev/null
    yq -e '.model.class == "fast" or .model.class == "balanced" or .model.class == "powerful"' "$SETTINGS_SHARED_YAML" > /dev/null
    yq -e '.model.reasoning == "low" or .model.reasoning == "medium" or .model.reasoning == "high" or .model.reasoning == "max"' "$SETTINGS_SHARED_YAML" > /dev/null
    yq -e '.runtime.filesystem == "read-only" or .runtime.filesystem == "workspace-write"' "$SETTINGS_SHARED_YAML" > /dev/null
    yq -e '.runtime.approval == "manual" or .runtime.approval == "guarded-auto" or .runtime.approval == "full-auto"' "$SETTINGS_SHARED_YAML" > /dev/null
    yq -e '(.runtime.network_access | type) == "!!bool"' "$SETTINGS_SHARED_YAML" > /dev/null
    yq -e '
        (.runtime.tools // []) as $tools |
        (
            $tools |
            map(
                select(
                    . == "shell" or
                    . == "read" or
                    . == "edit" or
                    . == "write" or
                    . == "glob" or
                    . == "grep" or
                    . == "web_fetch" or
                    . == "web_search"
                )
            ) |
            length
        ) == ($tools | length)
    ' "$SETTINGS_SHARED_YAML" > /dev/null
}

# ---------------------------------------------------------------------------
# map_model_class_to_claude — maps shared model.class to Claude model value
# ---------------------------------------------------------------------------
map_model_class_to_claude() {
    local model_class="$1"
    case "$model_class" in
        fast)      echo "haiku" ;;
        powerful)  echo "opus" ;;
        balanced)  echo "sonnet" ;;
        *)         echo "sonnet" ;;
    esac
}

# ---------------------------------------------------------------------------
# map_approval_intent_to_codex_policy — shared approval intent to Codex value
# ---------------------------------------------------------------------------
map_approval_intent_to_codex_policy() {
    local approval_intent="$1"
    case "$approval_intent" in
        manual)        echo "on-request" ;;
        full-auto)     echo "never" ;;
        guarded-auto)  echo "untrusted" ;;
        *)             echo "untrusted" ;;
    esac
}

# ---------------------------------------------------------------------------
# map_filesystem_intent_to_claude_mode — shared filesystem to Claude mode
# ---------------------------------------------------------------------------
map_filesystem_intent_to_claude_mode() {
    local filesystem="$1"
    case "$filesystem" in
        read-only)        echo "plan" ;;
        workspace-write)  echo "acceptEdits" ;;
        *)                echo "acceptEdits" ;;
    esac
}

# ---------------------------------------------------------------------------
# map_portable_tool_to_claude — shared runtime tool to Claude allow-list name
# ---------------------------------------------------------------------------
map_portable_tool_to_claude() {
    local tool="$1"
    case "$tool" in
        shell)       echo "Bash" ;;
        read)        echo "Read" ;;
        edit)        echo "Edit" ;;
        write)       echo "Write" ;;
        glob)        echo "Glob" ;;
        grep)        echo "Grep" ;;
        web_fetch)   echo "WebFetch" ;;
        web_search)  echo "WebSearch" ;;
        *)           echo "$tool" ;;
    esac
}

# ---------------------------------------------------------------------------
# json_escape — escapes a string for JSON string literal output
# ---------------------------------------------------------------------------
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ---------------------------------------------------------------------------
# json_array_from_lines — renders stdin as a compact JSON string array
# ---------------------------------------------------------------------------
json_array_from_lines() {
    local first=1
    local item

    printf '['
    while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ "$first" -eq 0 ]; then
            printf ', '
        fi
        printf '"%s"' "$(json_escape "$item")"
        first=0
    done
    printf ']'
}

# ---------------------------------------------------------------------------
# generate_legacy_settings_json — emits Claude-compatible settings.json
# from SETTINGS.yaml so downstream generation stays backward-compatible
# ---------------------------------------------------------------------------
generate_legacy_settings_json() {
    local model_class model_reasoning runtime_filesystem runtime_approval
    local claude_model claude_default_mode codex_approval_policy codex_network_access
    local allow_json deny_json ask_json claude_md_excludes_json

    model_class="$(yq -r '.model.class' "$SETTINGS_SHARED_YAML")"
    model_reasoning="$(yq -r '.model.reasoning' "$SETTINGS_SHARED_YAML")"
    runtime_filesystem="$(yq -r '.runtime.filesystem' "$SETTINGS_SHARED_YAML")"
    runtime_approval="$(yq -r '.runtime.approval' "$SETTINGS_SHARED_YAML")"

    claude_model="$(map_model_class_to_claude "$model_class")"
    claude_default_mode="$(map_filesystem_intent_to_claude_mode "$runtime_filesystem")"
    codex_approval_policy="$(yq -r '.targets.codex.approval_policy // ""' "$SETTINGS_SHARED_YAML")"
    codex_network_access="$(yq -r '.targets.codex.network_access // .runtime.network_access // false' "$SETTINGS_SHARED_YAML")"

    if [ -z "$codex_approval_policy" ] || [ "$codex_approval_policy" = "null" ]; then
        codex_approval_policy="$(map_approval_intent_to_codex_policy "$runtime_approval")"
    fi

    allow_json="$(
        yq -r '.runtime.tools[]' "$SETTINGS_SHARED_YAML" \
            | while IFS= read -r tool; do
                map_portable_tool_to_claude "$tool"
              done \
            | json_array_from_lines
    )"

    deny_json="$(
        {
            yq -r '.safety.protected_paths[]' "$SETTINGS_SHARED_YAML" | while IFS= read -r path; do
                printf 'Read(%s)\n' "$path"
                printf 'Write(%s)\n' "$path"
                printf 'Edit(%s)\n' "$path"
            done
        } | json_array_from_lines
    )"

    ask_json="$(
        yq -r '.safety.dangerous_shell_commands.ask[]' "$SETTINGS_SHARED_YAML" \
            | while IFS= read -r cmd; do
                printf 'Bash(%s)\n' "$cmd"
              done \
            | json_array_from_lines
    )"

    claude_md_excludes_json="$(
        yq -r '(.targets.claude.claude_md_excludes // [".claude/agent-memory/**"])[]' "$SETTINGS_SHARED_YAML" \
            | json_array_from_lines
    )"

    cat > "$SETTINGS_JSON" <<JSON
{
  "\$schema": "https://json.schemastore.org/claude-code-settings.json",
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "permissions": {
    "allow": ${allow_json},
    "deny": ${deny_json},
    "ask": ${ask_json},
    "defaultMode": "${claude_default_mode}"
  },
  "model": "${claude_model}",
  "effortLevel": "${model_reasoning}",
  "codex": {
    "approvalPolicy": "${codex_approval_policy}",
    "networkAccess": ${codex_network_access}
  },
  "claudeMdExcludes": ${claude_md_excludes_json}
}
JSON
}

# ---------------------------------------------------------------------------
# prepare_settings_json — ensures the Claude-compatible settings.json
# artifact exists from the shared runtime config
# ---------------------------------------------------------------------------
prepare_settings_json() {
    echo "Using shared config: $SETTINGS_SHARED_YAML"
    validate_shared_settings
    validate_team_protocol
    generate_legacy_settings_json
    echo "Generated compatibility artifact: $SETTINGS_JSON"
}

# ---------------------------------------------------------------------------
# map_model — maps Claude model name to Codex model name
# ---------------------------------------------------------------------------
map_model() {
    local model="$1"
    case "$model" in
        opus)   echo "gpt-5.4" ;;
        sonnet) echo "gpt-5.3-codex" ;;
        haiku)  echo "gpt-5.1-codex-mini" ;;
        *)      echo "gpt-5.3-codex" ;;
    esac
}

# ---------------------------------------------------------------------------
# map_effort — maps Claude effort level to Codex model_reasoning_effort
# ---------------------------------------------------------------------------
map_effort() {
    local effort="$1"
    case "$effort" in
        low)    echo "low" ;;
        medium) echo "medium" ;;
        high)   echo "high" ;;
        max)    echo "xhigh" ;;
        *)      echo "medium" ;;
    esac
}

# ---------------------------------------------------------------------------
# map_sandbox_mode — determines Codex sandbox_mode from agent metadata
#   $1 = permissionMode value (plan / acceptEdits / "")
#   $2 = tools list (comma-separated)
# ---------------------------------------------------------------------------
map_sandbox_mode() {
    local permission_mode="$1"
    local tools="$2"

    # plan mode is read-only
    if [ "$permission_mode" = "plan" ]; then
        echo "read-only"
        return
    fi

    # acceptEdits with Write or Edit tool → workspace-write
    if [ "$permission_mode" = "acceptEdits" ]; then
        if echo "$tools" | grep -qE '\b(Write|Edit)\b'; then
            echo "workspace-write"
            return
        fi
    fi

    # Default: read-only
    echo "read-only"
}

# ---------------------------------------------------------------------------
# map_default_sandbox_mode — determines Codex sandbox_mode from shared config
#   $1 = Claude permissions.defaultMode value
# ---------------------------------------------------------------------------
map_default_sandbox_mode() {
    local default_mode="$1"

    case "$default_mode" in
        plan)         echo "read-only" ;;
        acceptEdits)  echo "workspace-write" ;;
        *)            echo "workspace-write" ;;
    esac
}

# ---------------------------------------------------------------------------
# map_approval_policy — determines Codex approval_policy from shared config
#   $1 = runtime.approval value (manual / guarded-auto / full-auto)
#   $2 = optional Codex approval override from shared config
# ---------------------------------------------------------------------------
map_approval_policy() {
    local runtime_approval="$1"
    local override="$2"

    if [ -n "$override" ] && [ "$override" != "null" ]; then
        echo "$override"
        return
    fi

    map_approval_intent_to_codex_policy "$runtime_approval"
}

# ---------------------------------------------------------------------------
# generate_claude — produces claude/ output directory
# ---------------------------------------------------------------------------
generate_claude() {
    echo "=== Generating Claude output ==="

    # Clean and recreate output directories
    rm -rf "$CLAUDE_DIR"
    mkdir -p "$CLAUDE_AGENTS_DIR"

    # Copy CLAUDE.md
    cp "$CLAUDE_MD" "$CLAUDE_DIR/CLAUDE.md"
    echo "Copied: $CLAUDE_DIR/CLAUDE.md"

    # Copy settings.json
    cp "$SETTINGS_JSON" "$CLAUDE_DIR/settings.json"
    echo "Copied: $CLAUDE_DIR/settings.json"

    # Create relative symlinks for rules and skills
    ln -s ../rules "$CLAUDE_DIR/rules"
    echo "Symlinked: $CLAUDE_DIR/rules -> ../rules"

    ln -s ../skills "$CLAUDE_DIR/skills"
    echo "Symlinked: $CLAUDE_DIR/skills -> ../skills"

    # Generate agent .md files from TEAM metadata + markdown instruction body
    local agent_id
    while IFS= read -r agent_id; do
        [ -n "$agent_id" ] || continue

        local name description model effort permission_mode
        local src_file dst_file body expanded_body
        local max_turns background memory isolation
        local tools_csv disallowed_tools_csv

        name="$(yq -r ".agents.items.${agent_id}.name" "$TEAM_YAML")"
        description="$(yq -r ".agents.items.${agent_id}.description" "$TEAM_YAML")"
        model="$(yq -r ".agents.items.${agent_id}.model" "$TEAM_YAML")"
        effort="$(yq -r ".agents.items.${agent_id}.effort // \"\"" "$TEAM_YAML")"
        permission_mode="$(yq -r ".agents.items.${agent_id}.permission_mode // \"\"" "$TEAM_YAML")"
        tools_csv="$(yq -r ".agents.items.${agent_id}.tools[]" "$TEAM_YAML" | csv_from_yaml_array)"
        disallowed_tools_csv="$(yq -r ".agents.items.${agent_id}.disallowed_tools // [] | .[]" "$TEAM_YAML" | csv_from_yaml_array)"
        max_turns="$(yq -r ".agents.items.${agent_id}.max_turns // \"\"" "$TEAM_YAML")"
        background="$(yq -r ".agents.items.${agent_id}.background // \"\"" "$TEAM_YAML")"
        memory="$(yq -r ".agents.items.${agent_id}.memory // \"\"" "$TEAM_YAML")"
        isolation="$(yq -r ".agents.items.${agent_id}.isolation // \"\"" "$TEAM_YAML")"

        src_file="$SCRIPT_DIR/$(yq -r ".agents.items.${agent_id}.instruction_file" "$TEAM_YAML")"
        dst_file="$CLAUDE_AGENTS_DIR/${name}.md"

        body="$(extract_body "$src_file")"
        expanded_body="$(expand_body "$body" "${CLAUDE_VARS[@]}")"

        {
            echo "---"
            echo "name: '$(yaml_escape_single_quoted "$name")'"
            echo "description: '$(yaml_escape_single_quoted "$description")'"
            echo "model: '$(yaml_escape_single_quoted "$model")'"
            if [ -n "$effort" ] && [ "$effort" != "null" ]; then
                echo "effort: '$(yaml_escape_single_quoted "$effort")'"
            fi
            if [ -n "$permission_mode" ] && [ "$permission_mode" != "null" ]; then
                echo "permissionMode: '$(yaml_escape_single_quoted "$permission_mode")'"
            fi
            echo "tools: '$(yaml_escape_single_quoted "$tools_csv")'"
            if [ -n "$disallowed_tools_csv" ] && [ "$disallowed_tools_csv" != "null" ]; then
                echo "disallowedTools: '$(yaml_escape_single_quoted "$disallowed_tools_csv")'"
            fi
            if [ "$background" = "true" ]; then
                echo "background: true"
            fi
            if [ -n "$memory" ] && [ "$memory" != "null" ]; then
                echo "memory: '$(yaml_escape_single_quoted "$memory")'"
            fi
            if [ -n "$isolation" ] && [ "$isolation" != "null" ]; then
                echo "isolation: '$(yaml_escape_single_quoted "$isolation")'"
            fi
            if [ -n "$max_turns" ] && [ "$max_turns" != "null" ]; then
                echo "maxTurns: $max_turns"
            fi
            echo "skills:"
            yq -r ".agents.items.${agent_id}.skills[]" "$TEAM_YAML" | while IFS= read -r skill; do
                echo "  - $(yaml_escape_single_quoted "$skill")"
            done
            echo "---"
            echo ""
            echo "$expanded_body"
        } > "$dst_file"

        echo "Generated: $dst_file"
    done < <(yq -r '.agents.order[]' "$TEAM_YAML")
}

# ---------------------------------------------------------------------------
# generate_codex — produces codex/ output directory
# ---------------------------------------------------------------------------
generate_codex() {
    echo ""
    echo "=== Generating Codex output ==="

    # Clean and recreate output directories
    rm -rf "$CODEX_DIR"
    mkdir -p "$CODEX_AGENTS_DIR"
    ln -s ../skills "$CODEX_DIR/skills"
    echo "Symlinked: $CODEX_DIR/skills -> ../skills"

    # Generate agent .toml files from TEAM metadata + markdown instruction body
    echo "Generating Codex agent definitions..."
    local agent_id
    while IFS= read -r agent_id; do
        [ -n "$agent_id" ] || continue

        local name description model effort permission_mode tools disallowed_tools
        local agent_skills
        local src_file dst_file
        name="$(yq -r ".agents.items.${agent_id}.name" "$TEAM_YAML")"
        description="$(yq -r ".agents.items.${agent_id}.description" "$TEAM_YAML")"
        model="$(yq -r ".agents.items.${agent_id}.model" "$TEAM_YAML")"
        effort="$(yq -r ".agents.items.${agent_id}.effort // \"\"" "$TEAM_YAML")"
        permission_mode="$(yq -r ".agents.items.${agent_id}.permission_mode // \"\"" "$TEAM_YAML")"
        tools="$(yq -r ".agents.items.${agent_id}.tools[]" "$TEAM_YAML" | csv_from_yaml_array)"
        disallowed_tools="$(yq -r ".agents.items.${agent_id}.disallowed_tools // [] | .[]" "$TEAM_YAML" | csv_from_yaml_array)"
        agent_skills="$(yq -r ".agents.items.${agent_id}.skills[]" "$TEAM_YAML")"
        src_file="$SCRIPT_DIR/$(yq -r ".agents.items.${agent_id}.instruction_file" "$TEAM_YAML")"
        dst_file="$CODEX_AGENTS_DIR/${name}.toml"

        # Map to Codex equivalents
        local codex_model codex_effort codex_sandbox
        codex_model="$(map_model "$model")"
        codex_effort="$(map_effort "${effort:-medium}")"
        codex_sandbox="$(map_sandbox_mode "$permission_mode" "$tools")"

        # Extract and expand body with Codex variable values
        local body expanded_body
        body="$(extract_body "$src_file")"
        expanded_body="$(expand_body "$body" "${CODEX_VARS[@]}")"

        # Build developer_instructions: append disallowedTools note if present
        local developer_instructions
        developer_instructions="$expanded_body"
        if [ -n "$disallowed_tools" ] && [ "$disallowed_tools" != "null" ]; then
            developer_instructions="${developer_instructions}

You do NOT have access to these tools: ${disallowed_tools}"
        fi

        # TOML multiline basic strings use """ delimiters; reject raw delimiter
        # sequences in instruction bodies so generated TOML remains parseable.
        if printf '%s' "$developer_instructions" | grep -q '"""'; then
            echo "Error: agent instruction contains raw triple quotes (\"\"\") which break TOML in $src_file"
            exit 1
        fi

        # Write TOML output
        cat > "$dst_file" <<TOML
name = "${name}"
description = "${description}"
model = "${codex_model}"
model_reasoning_effort = "${codex_effort}"
sandbox_mode = "${codex_sandbox}"
TOML

        cat >> "$dst_file" <<TOML
developer_instructions = """
${developer_instructions}
"""
TOML

        local skill_id skill_applies enabled
        while IFS= read -r skill_id; do
            [ -n "$skill_id" ] || continue
            skill_applies="$(yq -r ".skills.items.${skill_id}.applies_to[]" "$TEAM_YAML")"
            if ! printf '%s\n' "$skill_applies" | grep -qx "codex"; then
                continue
            fi

            enabled=false
            if printf '%s\n' "$agent_skills" | grep -qx "$skill_id"; then
                enabled=true
            fi

            cat >> "$dst_file" <<TOML
[[skills.config]]
path = "../skills/${skill_id}/SKILL.md"
enabled = ${enabled}

TOML
        done < <(yq -r '.skills.order[]' "$TEAM_YAML")

        echo "Generated: $dst_file"
    done < <(yq -r '.agents.order[]' "$TEAM_YAML")

    # Generate AGENTS.md — concatenate TEAM-ordered rules with tool-agnostic header
    echo ""
    echo "Generating codex/AGENTS.md..."
    {
        echo "# Agent Team Instructions"
        echo ""
        echo "Agent-team specific protocols live in skills (orchestrate, conventions, worker-protocol, qa-checklist, message-schema)."
        local rule_id rules_file
        while IFS= read -r rule_id; do
            [ -n "$rule_id" ] || continue
            yq -r ".rules.items.${rule_id}.applies_to[]" "$TEAM_YAML" | grep -qx "codex" || continue
            rules_file="$SCRIPT_DIR/$(yq -r ".rules.items.${rule_id}.source_file" "$TEAM_YAML")"
            echo ""
            cat "$rules_file"
        done < <(yq -r '.rules.order[]' "$TEAM_YAML")
    } > "$CODEX_DIR/AGENTS.md"
    echo "Generated: $CODEX_DIR/AGENTS.md"

    # Generate config.toml — derive sandbox/approval defaults from shared config
    echo ""
    echo "Generating codex/config.toml..."

    local default_mode runtime_approval codex_approval_override codex_network_access
    default_mode="$(map_filesystem_intent_to_claude_mode "$(yq -r '.runtime.filesystem' "$SETTINGS_SHARED_YAML")")"
    runtime_approval="$(yq -r '.runtime.approval' "$SETTINGS_SHARED_YAML")"
    codex_approval_override="$(yq -r '.targets.codex.approval_policy // ""' "$SETTINGS_SHARED_YAML")"
    codex_network_access="$(yq -r '.targets.codex.network_access // .runtime.network_access // false' "$SETTINGS_SHARED_YAML")"

    local config_sandbox config_approval
    config_sandbox="$(map_default_sandbox_mode "$default_mode")"
    config_approval="$(map_approval_policy "$runtime_approval" "$codex_approval_override")"

    cat > "$CODEX_DIR/config.toml" <<TOML
#:schema https://developers.openai.com/codex/config-schema.json
model = "gpt-5.3-codex"
model_reasoning_effort = "medium"
sandbox_mode = "${config_sandbox}"
approval_policy = "${config_approval}"

[sandbox_workspace_write]
network_access = ${codex_network_access}
TOML
    echo "Generated: $CODEX_DIR/config.toml"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
prepare_settings_json
generate_claude
generate_codex

echo ""
echo "Done."
