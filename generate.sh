#!/usr/bin/env bash
set -euo pipefail

# generate.sh — generates both Claude and Codex output directories from
# shared agent source files. Agent source files (agents/*.md) are the
# single source of truth; this script derives tool-specific equivalents.
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
# extract_frontmatter_block — extracts the raw frontmatter including delimiters
# ---------------------------------------------------------------------------
extract_frontmatter_block() {
    local file="$1"
    awk 'BEGIN{fm=0} /^---$/{if(fm==0){fm=1;print;next} if(fm==1){print;exit}} fm==1{print}' "$file"
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
# map_model — maps Claude model name to Codex model name
# ---------------------------------------------------------------------------
map_model() {
    local model="$1"
    case "$model" in
        opus)   echo "o3" ;;
        sonnet) echo "o4-mini" ;;
        haiku)  echo "o4-mini" ;;
        *)      echo "o4-mini" ;;
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
# map_sandbox_mode — determines Codex sandbox_mode from agent frontmatter
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

    # Generate agent .md files with expanded template variables
    for agent_file in "$AGENTS_SRC"/*.md; do
        [ -f "$agent_file" ] || continue

        local agent_basename
        agent_basename="$(basename "$agent_file")"
        local dst_file="$CLAUDE_AGENTS_DIR/$agent_basename"

        # Extract frontmatter and body separately
        local frontmatter body expanded_body
        frontmatter="$(extract_frontmatter_block "$agent_file")"
        body="$(extract_body "$agent_file")"
        expanded_body="$(expand_body "$body" "${CLAUDE_VARS[@]}")"

        # Reassemble: frontmatter + expanded body
        {
            echo "$frontmatter"
            echo "$expanded_body"
        } > "$dst_file"

        echo "Generated: $dst_file"
    done
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

    # Generate agent .toml files
    echo "Generating Codex agent definitions..."
    for agent_file in "$AGENTS_SRC"/*.md; do
        [ -f "$agent_file" ] || continue

        local agent_basename
        agent_basename="$(basename "$agent_file" .md)"
        local dst_file="$CODEX_AGENTS_DIR/${agent_basename}.toml"

        # Extract YAML frontmatter using yq
        local frontmatter
        frontmatter="$(yq --front-matter=extract '.' "$agent_file")"

        # Extract individual fields from frontmatter
        local name description model effort permission_mode tools disallowed_tools
        name="$(echo "$frontmatter" | yq '.name // ""')"
        description="$(echo "$frontmatter" | yq '.description // ""')"
        model="$(echo "$frontmatter" | yq '.model // ""')"
        effort="$(echo "$frontmatter" | yq '.effort // ""')"
        permission_mode="$(echo "$frontmatter" | yq '.permissionMode // ""')"
        tools="$(echo "$frontmatter" | yq '.tools // ""')"
        disallowed_tools="$(echo "$frontmatter" | yq '.disallowedTools // ""')"

        # Map to Codex equivalents
        local codex_model codex_effort codex_sandbox
        codex_model="$(map_model "$model")"
        codex_effort="$(map_effort "${effort:-medium}")"
        codex_sandbox="$(map_sandbox_mode "$permission_mode" "$tools")"

        # Extract and expand body with Codex variable values
        local body expanded_body
        body="$(extract_body "$agent_file")"
        expanded_body="$(expand_body "$body" "${CODEX_VARS[@]}")"

        # Build developer_instructions: append disallowedTools note if present
        local developer_instructions
        developer_instructions="$expanded_body"
        if [ -n "$disallowed_tools" ] && [ "$disallowed_tools" != "null" ]; then
            developer_instructions="${developer_instructions}

You do NOT have access to these tools: ${disallowed_tools}"
        fi

        # Write TOML output
        cat > "$dst_file" <<TOML
name = "${name}"
description = "${description}"
model = "${codex_model}"
model_reasoning_effort = "${codex_effort}"
sandbox_mode = "${codex_sandbox}"
developer_instructions = """
${developer_instructions}
"""
TOML

        echo "Generated: $dst_file"
    done

    # Generate AGENTS.md — concatenate rules/*.md with tool-agnostic header
    echo ""
    echo "Generating codex/AGENTS.md..."
    {
        echo "# Agent Team Instructions"
        echo ""
        echo "Agent-team specific protocols live in skills (orchestrate, conventions, worker-protocol, qa-checklist, message-schema, project)."
        for rules_file in $(ls "$RULES_DIR"/*.md | sort); do
            echo ""
            cat "$rules_file"
        done
    } > "$CODEX_DIR/AGENTS.md"
    echo "Generated: $CODEX_DIR/AGENTS.md"

    # Generate config.toml — derive sandbox_mode from settings.json defaultMode
    echo ""
    echo "Generating codex/config.toml..."

    local default_mode
    default_mode="$(yq -r '.permissions.defaultMode // "acceptEdits"' "$SETTINGS_JSON")"

    # Map Claude defaultMode to Codex sandbox_mode
    local config_sandbox
    case "$default_mode" in
        plan)         config_sandbox="read-only" ;;
        acceptEdits)  config_sandbox="workspace-write" ;;
        *)            config_sandbox="workspace-write" ;;
    esac

    cat > "$CODEX_DIR/config.toml" <<TOML
model = "o4-mini"
model_reasoning_effort = "medium"
sandbox_mode = "${config_sandbox}"
approval_policy = "on-request"
TOML
    echo "Generated: $CODEX_DIR/config.toml"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
generate_claude
generate_codex

echo ""
echo "Done."
